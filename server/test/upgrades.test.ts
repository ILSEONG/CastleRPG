// 공용 업그레이드(개정 20 §2·§4): 비용 공식, count 합계, 404·409·400, 원자성(동시 요청), 마이그레이션, 시드 검증, 응답 형식.
import assert from 'node:assert/strict'
import { cpSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import * as R from '../src/rules.ts'
import { CsvError, DATA_DIR, readTables, TABLES } from '../src/seed.ts'
import { barrier, setup, T0 } from './helpers.ts'

const DEF = (o: Partial<R.UpgradeDef> = {}): R.UpgradeDef => ({ id: 'atk', name: '공격력', per_level: 0.5, unit: 'pct', max_level: 200, cost_base: 1000, cost_growth: 1.05, ...o })
const gold = (id: string, tenths: number, S: Awaited<ReturnType<typeof setup>>) => S.db.query('update player_state set gold_tenths = $2 where player_id = $1', [id, tenths])

test('비용 공식: L → L+1 = round(cost_base × growth^L), 레벨 0부터. count는 합계', () => {
  assert.deepEqual([0, 1].map((l) => R.upgradeStepCost(DEF(), l)), [1000, 1050])
  assert.equal(R.upgradeStepCost(DEF(), 49), Math.round(1000 * 1.05 ** 49)) // 약 1.09만(50번째 올림)
  assert.equal(R.upgradeStepCost(DEF(), 199) > 16_000_000 && R.upgradeStepCost(DEF(), 199) < 17_000_000, true) // 199레벨 약 1,640만
  const aspd = DEF({ cost_base: 5000, cost_growth: 1.07 })
  assert.equal(R.upgradeStepCost(aspd, 0), 5000)
  assert.equal(R.upgradeStepCost(aspd, 1), 5350)
  assert.equal(R.upgradeCost(DEF(), 0, 3), 1000 + 1050 + 1103) // 1102.5 → 1103(반올림 위로)
  assert.equal(R.upgradeCost(DEF(), 5, 4), [5, 6, 7, 8].reduce((s, l) => s + Math.round(1000 * 1.05 ** l), 0))
})

test('CSV 표가 서버에 시드되고 gamedata에 upgrades 행(파일 순서)이 나온다', async () => {
  const S = await setup()
  try {
    const g = (await S.req('GET', '/v1/gamedata')).json
    assert.deepEqual(g.upgrades.map((u: any) => u.id), ['atk', 'hp', 'aspd', 'mspd', 'crit_rate', 'crit_dmg'])
    assert.deepEqual(g.upgrades[2], { id: 'aspd', name: '공격속도', per_level: 0.25, unit: 'pct', max_level: 100, cost_base: 5000, cost_growth: 1.07 })
    const t = await S.db.query("select count(*)::int as n from information_schema.tables where table_name in ('upgrade_defs', 'player_upgrades')")
    assert.equal(t[0].n, 2)
  } finally {
    await S.close()
  }
})

test('업그레이드 1회·3회: 골드(tenths × 10)를 합계만큼 빼고 레벨이 오른다. 응답 = 플레이어 응답 + level + upgrades, 로그', async () => {
  const S = await setup()
  try {
    S.clock.t = T0
    const { token, id } = await S.login()
    assert.deepEqual((await S.req('GET', '/v1/player', { token })).json.player.upgrades, {})
    await gold(id, 100_000 * 10 + 5, S)
    let r = await S.req('POST', '/v1/upgrade', { token, body: { id: 'atk', count: 1 } })
    assert.deepEqual([r.status, r.json.level, r.json.player.upgrades, r.json.player.gold_tenths], [200, 1, { atk: 1 }, 1_000_005 - 10_000])
    r = await S.req('POST', '/v1/upgrade', { token, body: { id: 'atk', count: 3 } }) // 1→4: 1050 + 1103 + 1158
    assert.deepEqual([r.status, r.json.level, r.json.player.gold_tenths], [200, 4, 1_000_005 - 10_000 - (1050 + 1103 + 1158) * 10])
    r = await S.req('POST', '/v1/upgrade', { token, body: { id: 'crit_dmg', count: 2 } })
    assert.deepEqual(r.json.player.upgrades, { atk: 4, crit_dmg: 2 })
    const p = (await S.req('GET', '/v1/player', { token })).json.player
    assert.deepEqual(p.upgrades, { atk: 4, crit_dmg: 2 }) // 다시 읽어도 그대로(재접속 복원)
    const logs = await S.db.query("select detail from economy_log where player_id = $1 and kind = 'upgrade' order by id", [id])
    assert.equal(logs.length, 3)
    assert.deepEqual(logs[1].detail, { id: 'atk', from: 1, to: 4, count: 3, gold: 3311, gold_tenths: -33_110 })
  } finally {
    await S.close()
  }
})

test('오류: 모르는 id 404, 최대 레벨 409 max_level, 골드 부족 409 not_enough_gold(아무것도 안 바뀐다), 잘못된 count 400', async () => {
  const S = await setup()
  try {
    S.clock.t = T0
    const { token, id } = await S.login()
    const up = (body: unknown) => S.req('POST', '/v1/upgrade', { token, body })
    await gold(id, 100_000_000 * 10, S)
    assert.equal((await up({ id: 'nope', count: 1 })).status, 404)
    for (const count of [0, 101, 1.5, '2', null]) assert.equal((await up({ id: 'atk', count })).status, 400, `count ${count}`)
    assert.equal((await up({ count: 1 })).status, 400)
    assert.equal((await S.req('POST', '/v1/upgrade', { body: { id: 'atk', count: 1 } })).status, 401)
    // 상한: mspd 80레벨. 80까지 올리고 한 번 더는 409, 81이 되는 count도 409(일부만 오르지 않는다)
    let r = await up({ id: 'mspd', count: 79 })
    assert.equal(r.status, 200)
    r = await up({ id: 'mspd', count: 2 })
    assert.deepEqual([r.status, r.json.error], [409, 'max_level'])
    assert.equal((await up({ id: 'mspd', count: 1 })).status, 200)
    r = await up({ id: 'mspd', count: 1 })
    assert.deepEqual([r.status, r.json.error], [409, 'max_level'])
    // 골드 부족: 정확히 1레벨 값(1000)보다 1 모자라면 409, 정확히면 성공
    await gold(id, 999 * 10 + 9, S)
    r = await up({ id: 'atk', count: 1 })
    assert.deepEqual([r.status, r.json.error], [409, 'not_enough_gold'])
    let p = (await S.req('GET', '/v1/player', { token })).json.player
    assert.deepEqual([p.gold_tenths, p.upgrades.atk], [9999, undefined])
    await gold(id, 1000 * 10, S)
    assert.equal((await up({ id: 'atk', count: 1 })).status, 200)
    // 합계가 모자라면(1레벨 값은 되지만 2회 합계는 안 됨) 409
    await gold(id, 1100 * 10, S)
    r = await up({ id: 'atk', count: 2 })
    assert.deepEqual([r.status, r.json.error], [409, 'not_enough_gold'])
    p = (await S.req('GET', '/v1/player', { token })).json.player
    assert.deepEqual([p.gold_tenths, p.upgrades.atk], [11_000, 1])
  } finally {
    await S.close()
  }
})

test('원자성: 같은 순간 두 업그레이드가 겹치면 하나만 반영(version 가드), 골드는 한 번만 빠지고 로그도 하나', async () => {
  const b = barrier()
  const S = await setup({ wrapQuery: b.wrap })
  try {
    S.clock.t = T0
    const { token, id } = await S.login()
    await gold(id, 1000 * 10, S) // 1레벨 1회분
    b.arm()
    const [r1, r2] = await Promise.all([
      S.req('POST', '/v1/upgrade', { token, body: { id: 'atk', count: 1 } }),
      S.req('POST', '/v1/upgrade', { token, body: { id: 'atk', count: 1 } }),
    ])
    assert.equal(b.arrived(), 2)
    assert.deepEqual([r1.status, r2.status].sort(), [200, 409]) // 진 쪽은 다시 읽고 골드 부족
    const p = (await S.req('GET', '/v1/player', { token })).json.player
    assert.deepEqual([p.gold_tenths, p.upgrades], [0, { atk: 1 }])
    const n = await S.db.query("select count(*)::int as n from economy_log where player_id = $1 and kind = 'upgrade'", [id])
    assert.equal(n[0].n, 1)
  } finally {
    await S.close()
  }
})

test('시드 검증: per_level·cost_base > 0, growth ≥ 1, max_level ≥ 1, unit은 pct·pp만. 오류는 파일·줄·열', async () => {
  const d = mkdtempSync(join(tmpdir(), 'upg-'))
  for (const t of TABLES) cpSync(join(DATA_DIR, t.file), join(d, t.file))
  const orig = readFileSync(join(DATA_DIR, 'upgrades.csv'), 'utf8')
  const bad = async (row: string, want: RegExp) => {
    writeFileSync(join(d, 'upgrades.csv'), orig + row + '\n')
    await assert.rejects(readTables(d), (e: unknown) => e instanceof CsvError && e.errors.some((m) => want.test(m)), row)
  }
  await readTables(d) // 원본은 통과
  await bad('x1,가,0,pct,10,100,1.1', /upgrades\.csv line \d+ column 'per_level'/)
  await bad('x2,가,1,pct,10,0,1.1', /column 'cost_base'/)
  await bad('x3,가,1,pct,10,100,0.9', /column 'cost_growth'/)
  await bad('x4,가,1,pct,0,100,1.1', /column 'max_level'/)
  await bad('x5,가,1,bad,10,100,1.1', /column 'unit'/)
  await bad('atk,가,1,pct,10,100,1.1', /duplicate key 'atk'/)
})

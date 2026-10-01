// 병사(개정 13 §8): 생산 공식·게으른 생산(시계 주입: 3시간 → 1마리, 레벨 반영, 상한), 합성(원자성, 부족·최대), 배치(인구 상한, 보유 상한,
// 키 형식, 합성 후 자르기), 008 업그레이드, 플레이어 격리, 시드 검증.
import assert from 'node:assert/strict'
import { cpSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { after, before, test } from 'node:test'
import { MIGRATIONS_DIR, migrate, openDb } from '../src/db.ts'
import * as R from '../src/rules.ts'
import { CsvError, DATA_DIR, readTables, TABLES } from '../src/seed.ts'
import { barrier, setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
const tmp: string[] = []
before(async () => {
  S = await setup()
})
after(async () => {
  await S.close()
  for (const d of tmp) {
    try {
      rmSync(d, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 })
    } catch {
      // OS 임시 폴더라 남아도 해가 없다
    }
  }
})

const H3 = 10800 // 1레벨 한 마리 시간
const CFG: R.Config = { soldier_prod_sec: '10800', soldier_prod_level_factor: '0.95' }
const player = async (token: string) => (await S.req('GET', '/v1/player', { token })).json.player
const merge = (token: string, body: unknown) => S.req('POST', '/v1/soldiers/merge', { token, body })
const deploy = (token: string, d: unknown) => S.req('POST', '/v1/soldiers/deploy', { token, body: { deploy: d } })
const logs = async (id: string, kind: string) => S.db.query('select detail from economy_log where player_id = $1 and kind = $2 order by id', [id, kind])
async function give(q: Setup['db']['query'], id: string, s: Record<string, number>) {
  for (const [k, n] of Object.entries(s)) {
    const [type, tier] = k.split(':')
    await q('insert into player_soldiers (player_id, type, tier, count) values ($1, $2, $3, $4) on conflict (player_id, type, tier) do update set count = $4', [id, type, Number(tier), n])
  }
}
const setLevel = (id: string, b: string, l: number) => S.db.query('update player_buildings set level = $3 where player_id = $1 and building = $2', [id, b, l])

test('생산 공식: 한 마리 = 10800 × 0.95^(L−1)(Lv10 약 1시간 54분, Lv30 약 41분), 지난 시간 / 한 마리(남은 시간 유지), 상한 720분이면 지금으로, 시계 되돌림은 0', () => {
  assert.equal(R.soldierUnitSec(CFG, 1), H3)
  assert.equal(R.soldierUnitSec(CFG, 10), R.grown(H3, 0.95, 9))
  assert.ok(Math.abs(R.soldierUnitSec(CFG, 10) - 6806.7) < 0.1 && Math.abs(R.soldierUnitSec(CFG, 30) / 60 - 40.7) < 0.1)
  assert.deepEqual(R.soldierProdStep(T0, T0 + H3 - 1, H3, 720), { count: 0, last: T0, changed: false })
  assert.deepEqual(R.soldierProdStep(T0, T0 + H3, H3, 720), { count: 1, last: T0 + H3, changed: true })
  assert.deepEqual(R.soldierProdStep(T0, T0 + 3 * H3 + 5, H3, 720), { count: 3, last: T0 + 3 * H3, changed: true }) // 5초는 남긴다
  assert.deepEqual(R.soldierProdStep(T0, T0 + 100 * 3600, H3, 720), { count: 4, last: T0 + 100 * 3600, changed: true }) // 꺼진 동안은 12시간까지
  assert.deepEqual(R.soldierProdStep(T0, T0 - 50, H3, 720), { count: 0, last: T0 - 50, changed: true })
  assert.deepEqual(R.trimDeploy({ 'infantry:1': 5, 'archer:1': 2, 'cavalry:2': 1 }, { 'infantry:1': 3, 'archer:1': 2 }), { 'infantry:1': 3, 'archer:1': 2 })
})

test('게으른 생산(시계 주입): 3시간 → 병사 건물마다 1티어 1마리·로그 한 번, 레벨이 시간을 줄이고, 꺼진 동안은 상한(720분)까지, 응답 last_collect', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  S.clock.t = T0 + H3 - 1
  assert.deepEqual((await player(token)).soldiers, {})
  S.clock.t = T0 + H3
  const p = await player(token)
  assert.deepEqual(p.soldiers, { 'infantry:1': 1, 'archer:1': 1, 'cavalry:1': 1 })
  assert.deepEqual([p.buildings.barracks, p.buildings.stable], [{ level: 1, last_collect: T0 + H3 }, { level: 1, last_collect: T0 + H3 }])
  const [l] = await logs(id, 'soldier_prod')
  assert.deepEqual(l.detail.map((x: any) => [x.type, x.count, x.level, x.from, x.to]), [['infantry', 1, 1, T0, T0 + H3], ['archer', 1, 1, T0, T0 + H3], ['cavalry', 1, 1, T0, T0 + H3]])
  assert.equal((await player(token)).soldiers['infantry:1'], 1) // 같은 시각에 다시 읽어도 그대로
  // 막사 Lv 10: 한 마리 약 6,807초 — 보병만 하나 더
  await setLevel(id, 'barracks', 10)
  S.clock.t = T0 + H3 + Math.ceil(R.soldierUnitSec(CFG, 10))
  assert.deepEqual((await player(token)).soldiers, { 'infantry:1': 2, 'archer:1': 1, 'cavalry:1': 1 })
  // 100시간 꺼져 있었다: 궁병 +4(12시간 상한), 보병 Lv 10은 floor(43200 / 6806.7) = 6
  S.clock.t += 100 * 3600
  const q = await player(token)
  assert.deepEqual(q.soldiers, { 'infantry:1': 8, 'archer:1': 5, 'cavalry:1': 5 })
  assert.equal(q.buildings.archery.last_collect, S.clock.t)
  assert.equal((await logs(id, 'soldier_prod')).length, 3)
  // test/age가 병사 건물도 당긴다: 3시간 앞당기면 하나씩
  assert.deepEqual((await S.req('POST', '/v1/test/age', { token, body: { minutes: 180 } })).json.player.soldiers, { 'infantry:1': 9, 'archer:1': 6, 'cavalry:1': 6 })
})

test('합성: 같은 병종·티어 5마리 → 한 티어 위 1마리, 부족은 409 not_enough, 최대 티어는 409 max_tier, 모르는 병종·틀린 티어는 400, 로그', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await give(S.db.query, id, { 'infantry:1': 12, 'cavalry:5': 7 })
  let r = await merge(token, { type: 'infantry', tier: 1 })
  assert.deepEqual([r.status, r.json.player.soldiers, r.json.merged], [200, { 'infantry:1': 7, 'infantry:2': 1, 'cavalry:5': 7 }, { type: 'infantry', tier: 2 }])
  r = await merge(token, { type: 'infantry', tier: 1 })
  assert.deepEqual(r.json.player.soldiers, { 'infantry:1': 2, 'infantry:2': 2, 'cavalry:5': 7 })
  r = await merge(token, { type: 'infantry', tier: 1 })
  assert.deepEqual([r.status, r.json.error], [409, 'not_enough'])
  r = await merge(token, { type: 'infantry', tier: 2 })
  assert.deepEqual([r.status, r.json.error], [409, 'not_enough'])
  r = await merge(token, { type: 'cavalry', tier: 5 })
  assert.deepEqual([r.status, r.json.error], [409, 'max_tier'])
  for (const [body, code] of [[{ type: 'knight', tier: 1 }, 'unknown_soldier'], [{ type: '__proto__', tier: 1 }, 'unknown_soldier'], [{ type: 'infantry', tier: 0 }, 'bad_request'],
    [{ type: 'infantry', tier: 1.5 }, 'bad_request'], [{ type: 'infantry' }, 'bad_request'], [{ tier: 1 }, 'bad_request']] as [unknown, string][]) {
    r = await merge(token, body)
    assert.deepEqual([r.status, r.json.error], [400, code], JSON.stringify(body))
  }
  assert.equal((await S.req('POST', '/v1/soldiers/merge', { body: { type: 'infantry', tier: 1 } })).status, 401)
  assert.deepEqual((await logs(id, 'soldier_merge')).map((l) => [l.detail.type, l.detail.tier, l.detail.count, l.detail.have]), [['infantry', 1, 5, 12], ['infantry', 1, 5, 7]])
  assert.deepEqual((await player(token)).soldiers, { 'infantry:1': 2, 'infantry:2': 2, 'cavalry:5': 7 }) // 거부는 아무것도 안 바꿨다
})

test('합성 원자성: 5마리로 같은 version을 읽은 합성 2건 — 하나 200, 하나 409 not_enough, 보유는 한 번만 바뀌고 로그 하나', async () => {
  const b = barrier()
  const T = await setup({ wrapQuery: b.wrap })
  try {
    T.clock.t = T0
    const { token, id } = await T.login()
    await give(T.db.query, id, { 'archer:1': 5 })
    b.arm()
    const body = { type: 'archer', tier: 1 }
    const [r1, r2] = await Promise.all([T.req('POST', '/v1/soldiers/merge', { token, body }), T.req('POST', '/v1/soldiers/merge', { token, body })])
    assert.equal(b.arrived(), 2, 'both requests read the same version before either wrote')
    assert.deepEqual([r1.status, r2.status].sort(), [200, 409])
    assert.equal((r1.status === 409 ? r1 : r2).json.error, 'not_enough')
    const rows = await T.db.query('select type, tier, count from player_soldiers where player_id = $1 order by tier', [id])
    assert.deepEqual(rows, [{ type: 'archer', tier: 1, count: 0 }, { type: 'archer', tier: 2, count: 1 }])
    assert.equal((await T.db.query("select count(*)::int as n from economy_log where player_id = $1 and kind = 'soldier_merge'", [id]))[0].n, 1)
  } finally {
    await T.close()
  }
})

test('배치: 보유 이하·합계 ≤ 인구·키 형식(400 bad_deploy), 저장·재요청 멱등, 민가가 인구를 늘리면 더 둔다, 합성하면 배치를 보유로 자른다', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await give(S.db.query, id, { 'infantry:1': 10, 'archer:1': 3 })
  assert.equal((await player(token)).population, 6)
  let r = await deploy(token, { 'infantry:1': 4, 'archer:1': 2, 'cavalry:1': 0 })
  assert.deepEqual([r.status, r.json.player.soldier_deploy], [200, { 'infantry:1': 4, 'archer:1': 2 }]) // 0은 저장하지 않는다
  r = await deploy(token, { 'infantry:1': 4, 'archer:1': 2 })
  assert.deepEqual([r.status, r.json.player.soldier_deploy], [200, { 'infantry:1': 4, 'archer:1': 2 }])
  const bad: unknown[] = [
    { 'infantry:1': 7 }, // 인구 6 초과
    { 'infantry:1': 3, 'archer:1': 4 }, // 궁병 3마리뿐
    { 'cavalry:1': 1 }, // 없음
    { 'knight:1': 1 }, { 'infantry:0': 1 }, { 'infantry:6': 1 }, { infantry: 1 }, JSON.parse('{"__proto__": 1}'), { 'infantry:01': 1 },
    { 'infantry:1': -1 }, { 'infantry:1': 1.5 }, { 'infantry:1': '2' },
  ]
  for (const d of bad) {
    r = await deploy(token, d)
    assert.deepEqual([r.status, r.json.error], [400, 'bad_deploy'], JSON.stringify(d))
  }
  for (const body of [{}, { deploy: [] }, { deploy: null }, { deploy: 'x' }]) assert.equal((await S.req('POST', '/v1/soldiers/deploy', { token, body })).status, 400)
  assert.deepEqual((await player(token)).soldier_deploy, { 'infantry:1': 4, 'archer:1': 2 }) // 거부는 아무것도 안 바꿨다
  await setLevel(id, 'houses', 4) // 인구 12
  r = await deploy(token, { 'infantry:1': 9, 'archer:1': 3 })
  assert.deepEqual([r.status, r.json.player.population, r.json.player.soldier_deploy], [200, 12, { 'infantry:1': 9, 'archer:1': 3 }])
  // 합성: 보병 10 → 5(+ 2티어 1). 배치 9는 5로 잘리고, 2티어는 저절로 배치되지 않는다
  r = await merge(token, { type: 'infantry', tier: 1 })
  assert.deepEqual([r.json.player.soldiers, r.json.player.soldier_deploy], [{ 'infantry:1': 5, 'infantry:2': 1, 'archer:1': 3 }, { 'infantry:1': 5, 'archer:1': 3 }])
  const [s] = await S.db.query('select soldier_deploy from player_state where player_id = $1', [id])
  assert.deepEqual(s.soldier_deploy, { 'infantry:1': 5, 'archer:1': 3 })
  assert.deepEqual((await logs(id, 'soldier_merge'))[0].detail, { type: 'infantry', tier: 1, count: 5, have: 10, deployed: 9, deployed_after: 5 })
})

test('플레이어 격리: 한 플레이어의 생산·합성·배치는 다른 플레이어 보유·배치에 닿지 않는다', async () => {
  S.clock.t = T0
  const a = await S.login()
  const b = await S.login()
  await give(S.db.query, a.id, { 'cavalry:1': 6 })
  assert.equal((await merge(a.token, { type: 'cavalry', tier: 1 })).status, 200)
  assert.equal((await deploy(a.token, { 'cavalry:1': 1, 'cavalry:2': 1 })).status, 200)
  assert.deepEqual((await deploy(b.token, { 'cavalry:1': 1 })).status, 400) // b는 기병이 없다
  const pb = await player(b.token)
  assert.deepEqual([pb.soldiers, pb.soldier_deploy], [{}, {}])
  assert.equal((await S.db.query('select count(*)::int as n from player_soldiers where player_id = $1', [b.id]))[0].n, 0)
  S.clock.t = T0 + H3
  assert.deepEqual((await player(b.token)).soldiers, { 'infantry:1': 1, 'archer:1': 1, 'cavalry:1': 1 })
  assert.deepEqual((await player(a.token)).soldiers, { 'infantry:1': 1, 'archer:1': 1, 'cavalry:1': 2, 'cavalry:2': 1 })
})

test('마이그레이션 008: 007까지 적용된 DB의 기존 플레이어는 궁병 훈련소·기병 마구간 Lv 1 행을 받고(생산 시각 = 지금), 막사 생산 시각도 지금, 배치 {}·보유 없음', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'castle-mig-'))
  tmp.push(dir)
  const all = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort()
  for (const f of all.filter((f) => f < '008')) cpSync(join(MIGRATIONS_DIR, f), join(dir, f))
  const d = await openDb({})
  try {
    await migrate(d, dir)
    const [p] = await d.query("insert into players (device_id) values ('mig-008-device-0001') returning id")
    await d.query('insert into player_state (player_id) values ($1)', [p.id])
    await d.query("insert into player_buildings (player_id, building, level, last_collect) values ($1, 'barracks', 3, to_timestamp($2)), ($1, 'lumber', 2, to_timestamp($2))", [p.id, T0 - 86400])
    const t0 = Date.now() / 1000
    assert.deepEqual(await migrate(d), ['008_soldiers.sql'])
    const rows = await d.query('select building, level, extract(epoch from last_collect)::float8 as lc from player_buildings where player_id = $1 order by building', [p.id])
    assert.deepEqual(rows.map((r) => `${r.building}:${r.level}`), ['archery:1', 'barracks:3', 'lumber:2', 'stable:1'])
    const lc = Object.fromEntries(rows.map((r) => [r.building, r.lc]))
    assert.ok(lc.archery >= t0 - 5 && lc.stable >= t0 - 5 && lc.barracks >= t0 - 5, JSON.stringify(lc)) // 지금부터 센다
    assert.equal(lc.lumber, T0 - 86400) // 자원 건물은 그대로
    const [s] = await d.query('select soldier_deploy from player_state where player_id = $1', [p.id])
    assert.deepEqual(s.soldier_deploy, {})
    assert.deepEqual(await d.query('select * from player_soldiers'), [])
  } finally {
    await d.close()
  }
})

test('시드 검증: 병종 건물은 건물 표에·병종마다 다르게, hp·range·atk_interval·speed > 0, atk·aggro ≥ 0, 병사 설정 범위·필수', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'castle-data-'))
  tmp.push(dir)
  for (const t of TABLES) cpSync(join(DATA_DIR, t.file), join(dir, t.file))
  const sol = readFileSync(join(DATA_DIR, 'soldiers.csv'), 'utf8')
  const cfg = readFileSync(join(DATA_DIR, 'config.csv'), 'utf8')
  const cases: [string, string, RegExp][] = [
    ['soldiers.csv', sol.replace('archer,궁병,archery,', 'archer,궁병,range,'), /soldiers\.csv line 3 column 'building': building 'range' is not in buildings\.csv/],
    ['soldiers.csv', sol.replace('cavalry,기병,stable,', 'cavalry,기병,barracks,'), /soldiers\.csv line 4 column 'building': building 'barracks' already makes another soldier/],
    ['soldiers.csv', sol.replace('infantry,보병,barracks,320,', 'infantry,보병,barracks,0,'), /line 2 column 'hp': must be greater than 0: 0/],
    ['soldiers.csv', sol.replace(',8.0,10,Knight', ',0,10,Knight'), /line 4 column 'speed': must be greater than 0/],
    ['soldiers.csv', sol.replace('archer,궁병,archery,180,18,', 'archer,궁병,archery,180,-1,'), /line 3 column 'atk': must be 0 or more: -1/],
    ['soldiers.csv', sol.replace('archer,궁병,archery,180,18,8,', 'archer,궁병,archery,180,18,x,'), /line 3 column 'range': not a number: 'x'/],
    ['config.csv', cfg.replace('soldier_max_tier,5', 'soldier_max_tier,0'), /soldier_max_tier must be an integer of at least 1: '0'/],
    ['config.csv', cfg.replace('soldier_merge_count,5', 'soldier_merge_count,2.5'), /soldier_merge_count must be an integer of at least 1/],
    ['config.csv', cfg.replace('soldier_prod_sec,10800', 'soldier_prod_sec,0'), /soldier_prod_sec must be greater than 0/],
    ['config.csv', cfg.replace(/^soldier_tier_mult,.*\n/m, ''), /missing key 'soldier_tier_mult'/],
  ]
  for (const [file, text, re] of cases) {
    writeFileSync(join(dir, file), text)
    await assert.rejects(readTables(dir), (e: unknown) => {
      assert.ok(e instanceof CsvError)
      assert.equal(e.errors.length, 1, `${re}: ${e.errors.join(' | ')}`)
      assert.match(e.errors[0], re)
      return true
    })
    writeFileSync(join(dir, file), file === 'soldiers.csv' ? sol : cfg)
  }
  await readTables(dir) // 원래대로면 통과
})

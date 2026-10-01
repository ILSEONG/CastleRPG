// 건물 레벨업(개정 12 §2.2~2.4): 비용·시간 공식, 단계 표, 성채 상한·선행·일꾼·자원 검사 순서, 게으른 완료(시계 주입),
// 자원 건물 자동 수집, 원자성(동시 2건), 007 업그레이드, 주점 확률·민가 인구(사용자 지시: 축적 상한 대신 인구), 배치 길이 확장,
// build_now 훅, 시드 검증.
import assert from 'node:assert/strict'
import { cpSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { after, before, test } from 'node:test'
import { MIGRATIONS_DIR, migrate, openDb } from '../src/db.ts'
import * as R from '../src/rules.ts'
import { createApp } from '../src/app.ts'
import { CsvError, DATA_DIR, readTables, seed, TABLES } from '../src/seed.ts'
import { barrier, setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
const rand = { next: [] as number[] } // 모집 난수(비면 암호학적 난수)
const tmp: string[] = []
before(async () => {
  S = await setup({ random: () => rand.next.shift() ?? R.cryptoRandom() })
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

const CFG: R.Config = {
  keep_slot_tiers: '1:4|5:8|10:12', keep_interior_tiers: '1:20|5:24|10:28', pop_base: '6', pop_per_house: '2',
  gacha_rate_ssr: '0.03', gacha_rate_sr: '0.17', tavern_ssr_per_level: '0.001', tavern_sr_per_level: '0.003',
}
const defs = async () => (await S.db.query('select id, name, max_level, wood, stone, food, base_sec, req1, req2 from building_defs order by ord')) as R.BuildingDef[]
const def = async (id: string) => (await defs()).find((d) => d.id === id) as R.BuildingDef
const upgrade = (token: string, building: unknown) => S.req('POST', '/v1/building/upgrade', { token, body: { building } })
const player = async (token: string) => (await S.req('GET', '/v1/player', { token })).json.player
const logs = async (id: string, kind: string) => S.db.query('select detail from economy_log where player_id = $1 and kind = $2 order by id', [id, kind])
const setRes = (id: string, r: Record<string, number>) =>
  Promise.all(Object.entries(r).map(([res, n]) => S.db.query('update player_resources set amount = $3 where player_id = $1 and res = $2', [id, res, n])))
// 건물 레벨을 DB에 직접(성채·성문은 player_state 레벨도 — 서버가 지키는 불변식)
async function setLevels(id: string, levels: Record<string, number>) {
  for (const [b, l] of Object.entries(levels)) {
    await S.db.query('update player_buildings set level = $3 where player_id = $1 and building = $2', [id, b, l])
    if (b === 'keep') await S.db.query('update player_state set keep_level = $2 where player_id = $1', [id, l])
    if (b === 'gate') await S.db.query('update player_state set gate_level = $2 where player_id = $1', [id, l])
  }
}
const RICH = { wood: 1_000_000, stone: 1_000_000, food: 1_000_000 }

test('비용·시간 공식: L → L+1 비용 = round(값 × 1.35^(L−1)), 시간 = round(base_sec × 1.5^(L−1)) — 스펙 예시(성채 10 → 11 ≈ 4,470 · 38분, 20레벨 ≈ 2,217배)', async () => {
  const keep = await def('keep')
  const lumber = await def('lumber')
  const gate = await def('gate')
  assert.deepEqual([R.buildCost(lumber, 1), R.buildSec(lumber, 1)], [{ wood: 60, stone: 80, food: 40 }, 20]) // 스펙 예: 벌목장 1 → 2
  assert.deepEqual([R.buildCost(keep, 2), R.buildSec(keep, 2)], [{ wood: 405, stone: 405, food: 270 }, 90])
  assert.deepEqual([R.buildCost(keep, 10), R.buildSec(keep, 10)], [{ wood: 4468, stone: 4468, food: 2979 }, 2307]) // 약 4,470 · 2,980 · 38분
  assert.deepEqual([R.buildCost(gate, 2), R.buildSec(gate, 2)], [{ wood: 203, stone: 338, food: 0 }, 68]) // 337.5·67.5는 0에서 먼 쪽으로
  assert.equal(R.buildSec(lumber, 20), 44337) // 20 × 1.5^19 ≈ 2,217배 ≈ 12시간
  assert.deepEqual(R.buildCost(keep, 29), { wood: 1338033, stone: 1338033, food: 892022 })
  assert.equal(R.grown(300, 1.35, 9), 300 * 1.35 * 1.35 * 1.35 * 1.35 * 1.35 * 1.35 * 1.35 * 1.35 * 1.35)
})

test('단계 표: "레벨:값|…" 파싱(1부터 오름차순), 레벨 이하 마지막 단계 값 — 슬롯 4/8/12, 민가 인구, 주점 확률', () => {
  assert.deepEqual(R.parseTiers('1:4|5:8|10:12'), [[1, 4], [5, 8], [10, 12]])
  assert.deepEqual(R.parseTiers(' 1 : 20 | 5:24 '), [[1, 20], [5, 24]])
  for (const bad of ['', '4|8|12', '2:4|5:8', '1:4|5:8|5:9', '1:4|3:8|2:9', '1:x', '1:4|', '1:4|5', 'a:1', '1.5:4']) {
    assert.equal(R.parseTiers(bad), null, bad)
  }
  assert.deepEqual([1, 4, 5, 9, 10, 30].map((l) => R.heroSlots(CFG, l)), [4, 4, 8, 8, 12, 12])
  assert.deepEqual([0, 1, 5, 10].map((l) => R.tierValue(CFG, 'keep_interior_tiers', l)), [20, 20, 24, 28])
  assert.throws(() => R.heroSlots({ keep_slot_tiers: '4|8|12' }, 1), /tier table/)
  assert.deepEqual([0, 1, 2, 3, 30].map((l) => R.population(CFG, l)), [6, 6, 8, 10, 64]) // 인구 = 6 + 2 × (민가 − 1)
  const r11 = R.gachaRates(CFG, 11)
  assert.deepEqual(R.gachaRates(CFG, 1), { ssr: 0.03, sr: 0.17 })
  assert.ok(Math.abs(r11.ssr - 0.04) < 1e-12 && Math.abs(r11.sr - 0.2) < 1e-12, JSON.stringify(r11))
})

test('검사 순서(rules.upgradeBlock): 존재 → 최대 레벨 → 성채 상한(성채 제외) → 선행(req ≥ T−1) → 일꾼 → 자원', async () => {
  const d = await defs()
  const lv = (o: Record<string, number>) => ({ keep: 1, gate: 1, barracks: 1, tavern: 1, lab: 1, houses: 1, lumber: 1, quarry: 1, farm: 1, ...o })
  const none = { wood: 0, stone: 0, food: 0 }
  assert.equal(R.upgradeBlock('mine', d, lv({}), false, RICH), 'unknown')
  assert.equal(R.upgradeBlock('farm', d, lv({ farm: 30, keep: 30 }), true, none), 'max_level') // 최대 레벨이 먼저
  assert.equal(R.upgradeBlock('lumber', d, lv({}), true, none), 'keep_cap') // 목표 2 > 성채 1
  assert.equal(R.upgradeBlock('keep', d, lv({ keep: 3, gate: 1, barracks: 3 }), true, none), 'prereq') // 성채 4: 성문 ≥ 3 필요
  assert.equal(R.upgradeBlock('tavern', d, lv({ keep: 5, tavern: 3, barracks: 2 }), true, none), 'prereq') // 주점 4: 막사 ≥ 3
  assert.equal(R.upgradeBlock('tavern', d, lv({ keep: 5, tavern: 3, barracks: 3 }), true, none), 'builder_busy')
  assert.equal(R.upgradeBlock('tavern', d, lv({ keep: 5, tavern: 3, barracks: 3 }), false, none), 'not_enough')
  assert.equal(R.upgradeBlock('tavern', d, lv({ keep: 5, tavern: 3, barracks: 3 }), false, R.buildCost(d.find((x) => x.id === 'tavern') as R.BuildingDef, 3)), '')
  assert.equal(R.upgradeBlock('keep', d, lv({}), false, { wood: 300, stone: 300, food: 199 }), 'not_enough')
  assert.equal(R.upgradeBlock('keep', d, lv({}), false, { wood: 300, stone: 300, food: 200 }), '') // 성채 1 → 2: 성문·막사 ≥ 1
})

test('새 플레이어: 모든 건물 레벨 1·일꾼 없음. 업그레이드 → 자원 차감·일꾼(서버 시각 + 시간)·로그, 중복은 409 builder_busy, 응답 build', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  let p = await player(token)
  assert.deepEqual(Object.fromEntries(Object.entries(p.buildings).map(([k, v]: [string, any]) => [k, v.level])),
    { keep: 1, gate: 1, barracks: 1, tavern: 1, lab: 1, houses: 1, lumber: 1, quarry: 1, farm: 1, archery: 1, stable: 1 })
  assert.equal(p.build, null)
  let r = await upgrade(token, 'keep')
  assert.deepEqual([r.status, r.json.error], [409, 'not_enough'])
  r = await upgrade(token, 'lumber')
  assert.deepEqual([r.status, r.json.error], [409, 'keep_cap'])
  await setRes(id, { wood: 1000, stone: 1000, food: 1000 })
  S.clock.t = T0 + 5
  r = await upgrade(token, 'keep')
  assert.equal(r.status, 200)
  assert.deepEqual(r.json.build, { id: 'keep', finish: T0 + 65 })
  assert.deepEqual([r.json.player.build, r.json.player.res, r.json.player.buildings.keep], [{ id: 'keep', finish: T0 + 65 }, { wood: 700, stone: 700, food: 800 }, { level: 1 }])
  const busy = await upgrade(token, 'keep')
  assert.deepEqual([busy.status, busy.json.error], [409, 'builder_busy'])
  assert.equal((await upgrade(token, 'gate')).json.error, 'keep_cap') // 상한이 일꾼보다 먼저(검사 순서)
  assert.deepEqual((await logs(id, 'build_start')).map((l) => l.detail), [{ building: 'keep', from: 1, to: 2, cost: { wood: 300, stone: 300, food: 200 }, finish: T0 + 65, collect: null }])
  for (const bad of ['mine', '__proto__', 'constructor', 'wood']) {
    r = await upgrade(token, bad)
    assert.deepEqual([r.status, r.json.error], [400, 'unknown_building'], bad)
  }
  for (const body of [{}, { building: '' }, { building: 5 }]) assert.equal((await S.req('POST', '/v1/building/upgrade', { token, body })).status, 400)
  assert.equal((await S.req('POST', '/v1/building/upgrade', { body: { building: 'keep' } })).status, 401)
  p = await player(token)
  assert.deepEqual([p.res, p.build], [{ wood: 700, stone: 700, food: 800 }, { id: 'keep', finish: T0 + 65 }]) // 거부는 아무것도 안 바꿨다
})

test('게으른 완료(시계 주입): 끝나는 시각 전에는 그대로, 지나면 다음 요청(어느 것이든)이 레벨 +1·일꾼 비움·build_done 로그 한 번, 성채면 keep_level도', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setRes(id, RICH)
  await upgrade(token, 'keep') // T0 + 60
  S.clock.t = T0 + 59.9
  let p = await player(token)
  assert.deepEqual([p.buildings.keep.level, p.keep_level, p.build], [1, 1, { id: 'keep', finish: T0 + 60 }])
  S.clock.t = T0 + 60
  const r = await S.req('POST', '/v1/sell', { token, body: { res: 'food' } }) // 상관없는 요청도 완료를 먼저 한다
  assert.deepEqual([r.json.player.buildings.keep.level, r.json.player.keep_level, r.json.player.build], [2, 2, null])
  p = await player(token)
  assert.deepEqual([p.buildings.keep.level, p.build], [2, null])
  assert.deepEqual((await logs(id, 'build_done')).map((l) => l.detail), [{ building: 'keep', from: 1, to: 2, finish: T0 + 60 }])
  // 성문: gate_level도 오르고, 성채 2라 목표 2까지
  assert.equal((await upgrade(token, 'gate')).status, 200)
  S.clock.t += 1000
  p = await player(token)
  assert.deepEqual([p.buildings.gate.level, p.gate_level, p.build], [2, 2, null])
  assert.equal((await upgrade(token, 'gate')).json.error, 'keep_cap') // 목표 3 > 성채 2
  const [s] = await S.db.query('select keep_level, gate_level, build_id, build_finish from player_state where player_id = $1', [id])
  assert.deepEqual(s, { keep_level: 2, gate_level: 2, build_id: null, build_finish: null })
})

test('자원 건물 업그레이드: 먼저 자동 수집(남은 초 유지)하고 그 양까지 비용에 쓴다. 완료 뒤 쌓임은 새 레벨', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setLevels(id, { keep: 2 })
  await setRes(id, { wood: 40, stone: 80, food: 40 }) // 목재 20 모자람 — 2분 30초 쌓인 20으로 채운다
  S.clock.t = T0 + 150
  const r = await upgrade(token, 'lumber')
  assert.equal(r.status, 200)
  assert.deepEqual([r.json.player.res, r.json.player.buildings.lumber], [{ wood: 0, stone: 0, food: 0 }, { level: 1, last_collect: T0 + 120 }])
  const [l] = await logs(id, 'build_start')
  assert.deepEqual(l.detail.collect, { res: 'wood', amount: 20, from: T0, to: T0 + 120 })
  S.clock.t = T0 + 150 + 20 // 완료(20초)
  const p = await player(token)
  assert.deepEqual([p.buildings.lumber.level, p.build], [2, null])
  S.clock.t = T0 + 120 + 600 // 지난 수집에서 10분: 새 레벨 2 → 200
  assert.equal((await S.req('POST', '/v1/collect', { token, body: { building: 'lumber' } })).json.amount, 200)
  // 자동 수집으로도 모자라면 409이고 수집도 안 된다
  await setLevels(id, { keep: 3 })
  await setRes(id, { wood: 0, stone: 0, food: 0 })
  S.clock.t += 300
  const no = await upgrade(token, 'lumber')
  assert.deepEqual([no.status, no.json.error], [409, 'not_enough'])
  assert.deepEqual((await player(token)).res, { wood: 0, stone: 0, food: 0 })
})

test('선행·상한·최대 레벨: 주점 4는 막사 ≥ 3, 성채 4는 성문·막사 ≥ 3, 최대 레벨이면 409 max_level', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setRes(id, RICH)
  await setLevels(id, { keep: 5, tavern: 3, barracks: 2 })
  assert.equal((await upgrade(token, 'tavern')).json.error, 'prereq')
  await setLevels(id, { barracks: 3 })
  assert.equal((await upgrade(token, 'tavern')).status, 200)
  S.clock.t += 10_000
  assert.equal((await player(token)).buildings.tavern.level, 4)
  await setLevels(id, { keep: 3, gate: 3, barracks: 2 })
  assert.equal((await upgrade(token, 'keep')).json.error, 'prereq')
  await setLevels(id, { farm: 30, keep: 30 })
  assert.equal((await upgrade(token, 'farm')).json.error, 'max_level')
})

test('원자성: 같은 version을 읽은 업그레이드 2건(다른 건물) — 하나 200, 하나 409 builder_busy, 자원 한 번, 로그 하나', async () => {
  const b = barrier()
  const T = await setup({ wrapQuery: b.wrap })
  try {
    T.clock.t = T0
    const { token, id } = await T.login()
    await T.db.query('update player_resources set amount = 100000 where player_id = $1', [id])
    await T.db.query("update player_buildings set level = 2 where player_id = $1 and building = 'keep'", [id])
    b.arm()
    const [r1, r2] = await Promise.all([
      T.req('POST', '/v1/building/upgrade', { token, body: { building: 'barracks' } }),
      T.req('POST', '/v1/building/upgrade', { token, body: { building: 'houses' } }),
    ])
    assert.equal(b.arrived(), 2, 'both requests read the same version before either wrote')
    assert.deepEqual([r1.status, r2.status].sort(), [200, 409])
    assert.equal((r1.status === 409 ? r1 : r2).json.error, 'builder_busy')
    const won = r1.status === 200 ? 'barracks' : 'houses'
    const d = (await T.db.query('select wood, stone, food from building_defs where id = $1', [won]))[0]
    const res = await T.db.query('select res, amount from player_resources where player_id = $1 order by res', [id])
    assert.deepEqual(res.map((x) => [x.res, Number(x.amount)]), [['food', 100000 - d.food], ['stone', 100000 - d.stone], ['wood', 100000 - d.wood]])
    const [s] = await T.db.query('select build_id from player_state where player_id = $1', [id])
    assert.equal(s.build_id, won)
    assert.equal((await T.db.query("select count(*)::int as n from economy_log where player_id = $1 and kind = 'build_start'", [id]))[0].n, 1)
  } finally {
    await T.close()
  }
})

test('원자성: 끝난 건설을 두 요청이 동시에 읽어도 완료는 한 번(레벨 +1, build_done 로그 1)', async () => {
  const b = barrier()
  const T = await setup({ wrapQuery: b.wrap })
  try {
    T.clock.t = T0
    const { token, id } = await T.login()
    await T.db.query('update player_resources set amount = 100000 where player_id = $1', [id])
    assert.equal((await T.req('POST', '/v1/building/upgrade', { token, body: { building: 'keep' } })).status, 200)
    T.clock.t = T0 + 61
    b.arm()
    const [r1, r2] = await Promise.all([T.req('GET', '/v1/player', { token }), T.req('GET', '/v1/player', { token })])
    assert.equal(b.arrived(), 2)
    assert.deepEqual([r1.json.player.buildings.keep.level, r2.json.player.buildings.keep.level], [2, 2])
    const [k] = await T.db.query("select level from player_buildings where player_id = $1 and building = 'keep'", [id])
    assert.equal(k.level, 2)
    assert.equal((await T.db.query("select count(*)::int as n from economy_log where player_id = $1 and kind = 'build_done'", [id]))[0].n, 1)
  } finally {
    await T.close()
  }
})

test('주점·민가 효과: 주점 레벨이 모집 확률을 올리고(SSR +0.1%p/레벨), 민가 레벨이 인구(player.population)를 늘린다. 축적 상한은 민가와 무관(720분)', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await S.db.query('update player_state set gold_tenths = 100000 where player_id = $1', [id])
  rand.next = [0.0305, 0] // 주점 1: SSR 3% 밖 → SR(풀 첫째 bron)
  assert.deepEqual((await S.req('POST', '/v1/gacha', { token, body: { count: 1 } })).json.results.map((x: any) => x.grade), ['SR'])
  await setLevels(id, { tavern: 2 }) // SSR 3.1%
  rand.next = [0.0305, 0]
  assert.deepEqual((await S.req('POST', '/v1/gacha', { token, body: { count: 1 } })).json.results.map((x: any) => [x.grade, x.hero_id]), [['SSR', 'arteon']])
  rand.next = []
  assert.equal((await player(token)).population, 6) // 민가 1
  await setLevels(id, { houses: 4 })
  assert.equal((await player(token)).population, 12) // 6 + 2 × 3
  await S.req('POST', '/v1/test/age', { token, body: { minutes: 1000 } })
  assert.equal((await S.req('POST', '/v1/collect', { token, body: { building: 'lumber' } })).json.amount, 720 * 10) // 민가 4여도 720분
  // 민가 업그레이드(실제 경로) → 완료 → 인구 +2
  await setRes(id, RICH)
  await setLevels(id, { keep: 5 })
  assert.equal((await upgrade(token, 'houses')).status, 200)
  assert.equal((await S.req('POST', '/v1/test/build_now', { token })).json.player.population, 14)
})

test('배치 길이 확장: 성채 4 → 5(실제 업그레이드 + build_now)면 슬롯 8 — 응답 배치는 null로 채우고 /v1/deploy도 8칸', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setRes(id, RICH)
  await setLevels(id, { keep: 4, gate: 4, barracks: 4 })
  assert.equal((await player(token)).deploy.length, 4)
  assert.equal((await upgrade(token, 'keep')).status, 200)
  const r = await S.req('POST', '/v1/test/build_now', { token })
  assert.equal(r.status, 200)
  assert.deepEqual([r.json.player.buildings.keep.level, r.json.player.keep_level, r.json.player.build], [5, 5, null])
  assert.deepEqual(r.json.player.deploy, ['hans', 'ella', 'dorik', 'nina', null, null, null, null])
  assert.equal((await S.req('POST', '/v1/deploy', { token, body: { deploy: ['hans', 'ella', 'dorik', 'nina'] } })).status, 400)
  assert.equal((await S.req('POST', '/v1/deploy', { token, body: { deploy: [null, 'ella', null, 'nina', 'hans', null, 'dorik', null] } })).status, 200)
  assert.equal((await S.req('POST', '/v1/test/build_now', { token })).json.player.build, null) // 쉬는 중이면 아무것도 안 한다
})

test('build_now 훅: ALLOW_TEST_HOOKS가 없으면 404, 토큰이 없으면 401', async () => {
  S.clock.t = T0
  const { token } = await S.login()
  assert.equal((await S.req('POST', '/v1/test/build_now')).status, 401)
  const res = await S.makeApp({ allowTestHooks: false }).request('/v1/test/build_now', { method: 'POST', headers: { authorization: `Bearer ${token}` } })
  assert.equal(res.status, 404)
})

test('마이그레이션 007: 006까지 적용된 DB의 기존 플레이어는 성채·성문 행을 keep_level·gate_level로 받고, 자원 건물 행은 그대로, 나머지는 요청 때 레벨 1', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'castle-mig-'))
  tmp.push(dir)
  const all = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort()
  for (const f of all.filter((f) => f < '007')) cpSync(join(MIGRATIONS_DIR, f), join(dir, f))
  const d = await openDb({})
  try {
    await migrate(d, dir)
    const dev = 'mig-007-device-0001'
    const [p] = await d.query('insert into players (device_id) values ($1) returning id', [dev])
    await d.query('insert into player_state (player_id, keep_level, gate_level) values ($1, 3, 2)', [p.id])
    await d.query("insert into player_buildings (player_id, building, level, last_collect) values ($1, 'lumber', 2, to_timestamp($2))", [p.id, T0 - 100])
    assert.deepEqual(await migrate(d), all.filter((f) => f >= '007'))
    const rows = await d.query('select building, level from player_buildings where player_id = $1 order by building', [p.id])
    assert.deepEqual(rows.map((r) => `${r.building}:${r.level}`), ['archery:1', 'gate:2', 'keep:3', 'lumber:2', 'stable:1']) // 008: 병사 건물 둘
    const [s] = await d.query('select build_id, build_finish from player_state where player_id = $1', [p.id])
    assert.deepEqual(s, { build_id: null, build_finish: null })
    await seed(d)
    const app = createApp({ query: d.query, now: () => T0, jwtSecret: 'test-secret-0123456789abcdef0123456789' })
    const call = async (method: string, path: string, token?: string, body?: unknown) => {
      const headers: Record<string, string> = { 'content-type': 'application/json' }
      if (token) headers.authorization = `Bearer ${token}`
      const res = await app.request(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) })
      return res.json()
    }
    const { token } = await call('POST', '/v1/auth/guest', undefined, { device_id: dev })
    const pl = (await call('GET', '/v1/player', token)).player
    assert.deepEqual(Object.fromEntries(Object.entries(pl.buildings).map(([k, v]: [string, any]) => [k, v.level])),
      { keep: 3, gate: 2, barracks: 1, tavern: 1, lab: 1, houses: 1, lumber: 2, quarry: 1, farm: 1, archery: 1, stable: 1 })
    assert.deepEqual([pl.buildings.lumber.last_collect, pl.buildings.keep.last_collect, pl.keep_level, pl.build], [T0 - 100, undefined, 3, null])
    assert.equal(pl.deploy.length, 4) // 성채 3: 첫 단계
  } finally {
    await d.close()
  }
})

test('시드 검증: 건물 선행은 표 안, 비용 0 이상 정수, base_sec > 0, 최대 레벨 ≥ 1, 성채·성문 필수, 자원 건물은 건물 표에, 단계 표 형식, 주점 증가분 ≤ 1', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'castle-data-'))
  tmp.push(dir)
  for (const t of TABLES) cpSync(join(DATA_DIR, t.file), join(dir, t.file))
  const bld = readFileSync(join(DATA_DIR, 'buildings.csv'), 'utf8')
  const cfg = readFileSync(join(DATA_DIR, 'config.csv'), 'utf8')
  const cases: [string, string, RegExp][] = [
    ['buildings.csv', bld.replace('tavern,주점,30,180,100,150,40,barracks,', 'tavern,주점,30,180,100,150,40,mine,'), /buildings\.csv line 5 column 'req1': unknown building 'mine'/],
    ['buildings.csv', bld.replace('lab,연구소,30,150,200,80,', 'lab,연구소,30,-150,200,80,'), /buildings\.csv line 6 column 'wood': must be 0 or more: -150/],
    ['buildings.csv', bld.replace('lab,연구소,30,150,200,80,', 'lab,연구소,30,150.5,200,80,'), /column 'wood': not an integer: '150\.5'/],
    ['buildings.csv', bld.replace('houses,민가,30,160,80,120,30', 'houses,민가,30,160,80,120,0'), /line 7 column 'base_sec': must be greater than 0: 0/],
    ['buildings.csv', bld.replace('farm,농장,30,', 'farm,농장,0,'), /line 10 column 'max_level': must be at least 1: 0/],
    ['buildings.csv', bld.replace(/^gate,.*\n/m, '').replace('keep,성채,30,300,300,200,60,gate,barracks', 'keep,성채,30,300,300,200,60,,barracks'), /missing required building 'gate'/],
    ['buildings.csv', bld.replace(/^quarry,.*\n/m, '').replace('gate,성문,30,150,250,0,45,quarry,', 'gate,성문,30,150,250,0,45,,'), /resources\.csv line 3 column 'building': building 'quarry' is not in buildings\.csv/],
    ['config.csv', cfg.replace('keep_slot_tiers,1:4|5:8|10:12', 'keep_slot_tiers,4|8|12'), /config\.csv line 5 column 'value': not a tier table/],
    ['config.csv', cfg.replace('keep_interior_tiers,1:20|5:24|10:28', 'keep_interior_tiers,1:20|5:24.5'), /not a tier table/],
    ['config.csv', cfg.replace('keep_interior_tiers,1:20|5:24|10:28', 'keep_interior_tiers,2:20'), /not a tier table/],
    ['config.csv', cfg.replace('tavern_sr_per_level,0.003', 'tavern_sr_per_level,1.5'), /tavern_sr_per_level must be in 0\.\.1: '1\.5'/],
    ['config.csv', cfg.replace('lab_atk_per_level,0.03', 'lab_atk_per_level,-0.03'), /lab_atk_per_level must be 0 or more/],
    ['config.csv', cfg.replace(/^pop_per_house,.*\n/m, ''), /missing key 'pop_per_house'/],
    ['config.csv', cfg.replace('pop_base,6', 'pop_base,6.5'), /pop_base must be a non-negative integer: '6\.5'/],
  ]
  for (const [file, text, re] of cases) {
    writeFileSync(join(dir, file), text)
    await assert.rejects(readTables(dir), (e: unknown) => {
      assert.ok(e instanceof CsvError)
      assert.equal(e.errors.length, 1, `${re}: ${e.errors.join(' | ')}`)
      assert.match(e.errors[0], re)
      return true
    })
    writeFileSync(join(dir, file), file === 'buildings.csv' ? bld : cfg)
  }
  await readTables(dir) // 원래대로면 통과
})

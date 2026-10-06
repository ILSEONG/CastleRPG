// 병사(개정 13 §8): 합성(원자성, 부족·최대), 배치(인구 상한, 보유 상한, 키 형식, 합성 후 자르기), 008 업그레이드, 플레이어 격리, 시드 검증.
// 훈련(개정 16 §2): 비용·시간·묶음 상한, 400·409 3종, 수령 전·후, 취소 환불, 동시 시작 원자성, 자동 생산 없음, test/age, 010 업그레이드.
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
const CFG: R.Config = { train_base_min: '180', train_step_min: '30', train_cost_tier_mult: '5', soldier_max_tier: '5' }
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

const train = (token: string, body: unknown) => S.req('POST', '/v1/soldiers/train', { token, body })
const collect = (token: string, building: string) => S.req('POST', '/v1/soldiers/collect', { token, body: { building } })
const cancel = (token: string, building: string) => S.req('POST', '/v1/soldiers/cancel', { token, body: { building } })
const setRes = (id: string, r: Record<string, number>) => Promise.all(Object.entries(r).map(([res, n]) =>
  S.db.query('update player_resources set amount = $3 where player_id = $1 and res = $2', [id, res, n])))
const NONE = { barracks: null, archery: null, stable: null }

test('훈련 공식: 1마리 = (180 − 30 × 티어 안 단계)분(개정 19), 묶음 상한 = 10 + 2(L−1), 비용 "자원:수|…" × n, 환불은 절반 내림', () => {
  const cfg: R.Config = { ...CFG, train_batch_base: '10', train_batch_per_level: '2', train_cost_infantry: 'food:30|wood:20', train_cost_archer: '0' }
  assert.equal(R.soldierUnitSec(CFG, 1), H3)
  assert.deepEqual([R.trainMax(cfg, 1), R.trainMax(cfg, 5), R.trainMax(cfg, 30)], [10, 18, 68])
  assert.deepEqual(R.trainCost(cfg, 'infantry', 8), { food: 240, wood: 160 })
  assert.deepEqual(R.trainCost(cfg, 'archer', 8), {}) // "0" = 무료
  assert.throws(() => R.trainCost(cfg, 'cavalry', 1), /train_cost_cavalry/)
  assert.deepEqual(R.parseTrainCost(' food : 40 | stone:20 '), { food: 40, stone: 20 })
  for (const bad of ['', 'food', 'food:-1', 'food:1.5', 'gold:5', 'food:1|food:2', 'food:1|', 'food:1,wood:2']) assert.equal(R.parseTrainCost(bad), null, bad)
  assert.deepEqual(R.trainRefund({ food: 75, wood: 90, stone: 1 }), { food: 37, wood: 45, stone: 0 })
  assert.deepEqual(R.trimDeploy({ 'infantry:1': 5, 'archer:1': 2, 'cavalry:2': 1 }, { 'infantry:1': 3, 'archer:1': 2 }), { 'infantry:1': 3, 'archer:1': 2 })
})

test('자동 생산 없음: 시간이 흘러도(100시간) 보유는 그대로, 병사 건물은 생산 시각을 주지 않고 대기열은 null, soldier_prod 로그 없음', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  S.clock.t = T0 + 100 * 3600
  const p = await player(token)
  assert.deepEqual([p.soldiers, p.training, p.buildings.barracks, p.buildings.stable], [{}, NONE, { level: 1 }, { level: 1 }])
  assert.deepEqual((await S.req('POST', '/v1/test/age', { token, body: { minutes: 6000 } })).json.player.soldiers, {})
  assert.equal((await logs(id, 'soldier_prod')).length, 0)
})

test('훈련: 비용 즉시 차감·끝나는 시각 = 지금 + n × 1마리, 진행 중 409 training, 수령 전 409 not_ready, 수령 → 1티어 +n·대기열 비움, 다시 수령 409 empty, 로그', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setRes(id, { food: 1000, wood: 1000, stone: 1000 })
  let r = await train(token, { building: 'barracks', count: 8 })
  const fin = T0 + 8 * H3
  assert.deepEqual([r.status, r.json.player.res, r.json.player.training, r.json.training], [200, { food: 760, wood: 840, stone: 1000 },
    { ...NONE, barracks: { count: 8, tier: 1, finish: fin } }, { building: 'barracks', count: 8, tier: 1, finish: fin }])
  r = await train(token, { building: 'barracks', count: 1 })
  assert.deepEqual([r.status, r.json.error], [409, 'training'])
  r = await collect(token, 'barracks')
  assert.deepEqual([r.status, r.json.error], [409, 'not_ready'])
  S.clock.t = fin - 1
  assert.deepEqual([(await collect(token, 'barracks')).json.error, (await player(token)).soldiers], ['not_ready', {}]) // 시간이 흘러도 저절로 들어오지 않는다
  S.clock.t = fin + 3600
  r = await train(token, { building: 'barracks', count: 1 }) // 끝났지만 수령 전
  assert.deepEqual([r.status, r.json.error, (await player(token)).soldiers], [409, 'ready_to_collect', {}])
  r = await collect(token, 'barracks')
  assert.deepEqual([r.status, r.json.player.soldiers, r.json.player.training, r.json.collected], [200, { 'infantry:1': 8 }, NONE, { type: 'infantry', count: 8, tier: 1 }])
  r = await collect(token, 'barracks') // 응답을 잃고 다시 보내도 두 번 받지 않는다
  assert.deepEqual([r.status, r.json.error, (await player(token)).soldiers], [409, 'empty', { 'infantry:1': 8 }])
  assert.deepEqual((await player(token)).res, { food: 760, wood: 840, stone: 1000 }) // 거부는 아무것도 안 바꿨다
  assert.deepEqual((await logs(id, 'train_start')).map((l) => l.detail), [{ building: 'barracks', type: 'infantry', count: 8, tier: 1, level: 1, unit_sec: H3, cost: { food: 240, wood: 160 }, finish: fin }])
  assert.deepEqual((await logs(id, 'train_collect')).map((l) => l.detail), [{ building: 'barracks', type: 'infantry', count: 8, tier: 1, finish: fin }])
  // 기병: 식량 40·석재 20, 막사와 따로 돈다
  r = await train(token, { building: 'stable', count: 10 })
  assert.deepEqual([r.status, r.json.player.res, r.json.player.training.stable.count], [200, { food: 360, wood: 840, stone: 800 }, 10])
})

test('훈련 검사: 병사 건물 아님·count 범위(1..묶음 상한, 레벨로 는다) 400, 자원 부족 409 not_enough, 레벨이 1마리 시간을 줄이고(Lv5 1:00) 진행 중 레벨업은 끝나는 시각을 안 바꾼다', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setRes(id, { food: 100, wood: 100, stone: 0 })
  const bad: [unknown, string][] = [[{ building: 'lumber', count: 1 }, 'not_soldier_building'], [{ building: 'nope', count: 1 }, 'not_soldier_building'],
    [{ building: '__proto__', count: 1 }, 'not_soldier_building'], [{ building: 'barracks', count: 11 }, 'bad_request'], [{ building: 'barracks', count: 0 }, 'bad_request'],
    [{ building: 'barracks', count: 1.5 }, 'bad_request'], [{ building: 'barracks', count: '2' }, 'bad_request'], [{ building: 'barracks' }, 'bad_request'], [{ count: 1 }, 'bad_request']]
  for (const [body, code] of bad) {
    const r = await train(token, body)
    assert.deepEqual([r.status, r.json.error], [400, code], JSON.stringify(body))
  }
  for (const [b, code] of [['lumber', 'not_soldier_building'], ['archery', 'empty']]) {
    assert.deepEqual([(await collect(token, b)).json.error, (await cancel(token, b)).json.error], [code, code], b)
  }
  let r = await train(token, { building: 'barracks', count: 4 }) // 식량 120 > 100
  assert.deepEqual([r.status, r.json.error], [409, 'not_enough'])
  r = await train(token, { building: 'stable', count: 1 }) // 석재 0
  assert.deepEqual([r.status, r.json.error, (await player(token)).training], [409, 'not_enough', NONE])
  await setRes(id, { food: 10000, wood: 10000 })
  await setLevel(id, 'barracks', 5) // 상한 18, 1마리 1:00
  assert.equal((await train(token, { building: 'barracks', count: 19 })).status, 400)
  r = await train(token, { building: 'barracks', count: 18 })
  const fin = T0 + 18 * R.soldierUnitSec(CFG, 5)
  assert.deepEqual([r.status, r.json.player.training.barracks], [200, { count: 18, tier: 1, finish: fin }])
  await setLevel(id, 'barracks', 9) // 진행 중 레벨이 올라도 끝나는 시각은 그대로
  assert.deepEqual((await player(token)).training.barracks, { count: 18, tier: 1, finish: fin })
  assert.equal((await logs(id, 'train_start'))[0].detail.unit_sec, R.soldierUnitSec(CFG, 5))
})

test('훈련 취소: 진행 중이면 비용의 50%(자원마다 내림) 환불·대기열 비움·로그, 끝난 뒤엔 409 ready_to_collect, 무료("0") 설정이면 비용 없이 훈련', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setRes(id, { food: 1000, wood: 1000, stone: 1000 })
  assert.equal((await train(token, { building: 'archery', count: 3 })).status, 200) // 식량 75·목재 90
  S.clock.t = T0 + 60
  let r = await cancel(token, 'archery')
  assert.deepEqual([r.status, r.json.player.res, r.json.player.training, r.json.refund], [200, { food: 962, wood: 955, stone: 1000 }, NONE, { food: 37, wood: 45 }])
  assert.deepEqual((await cancel(token, 'archery')).json.error, 'empty')
  assert.deepEqual((await logs(id, 'train_cancel')).map((l) => l.detail), [{ building: 'archery', type: 'archer', count: 3, tier: 1, finish: T0 + 3 * H3, refund: { food: 37, wood: 45 } }])
  assert.equal((await train(token, { building: 'archery', count: 1 })).status, 200)
  S.clock.t += H3
  r = await cancel(token, 'archery')
  assert.deepEqual([r.status, r.json.error], [409, 'ready_to_collect'])
  assert.deepEqual((await collect(token, 'archery')).json.player.soldiers, { 'archer:1': 1 })
  await S.db.query("update game_config set value = '0' where key = 'train_cost_archer'")
  try {
    await setRes(id, { food: 0, wood: 0, stone: 0 })
    r = await train(token, { building: 'archery', count: 2 })
    assert.deepEqual([r.status, r.json.player.res, r.json.player.training.archery.count], [200, { food: 0, wood: 0, stone: 0 }, 2])
    assert.deepEqual((await cancel(token, 'archery')).json.refund, {})
  } finally {
    await S.db.query("update game_config set value = 'food:25|wood:30' where key = 'train_cost_archer'")
  }
})

test('훈련 원자성: 같은 version을 읽은 시작 2건 — 하나 200, 하나 409 training, 비용·대기열·로그는 한 번만', async () => {
  const b = barrier()
  const T = await setup({ wrapQuery: b.wrap })
  try {
    T.clock.t = T0
    const { token, id } = await T.login()
    await T.db.query("update player_resources set amount = 1000 where player_id = $1", [id])
    b.arm()
    const body = { building: 'stable', count: 5 }
    const [r1, r2] = await Promise.all([T.req('POST', '/v1/soldiers/train', { token, body }), T.req('POST', '/v1/soldiers/train', { token, body })])
    assert.equal(b.arrived(), 2, 'both requests read the same version before either wrote')
    assert.deepEqual([r1.status, r2.status].sort(), [200, 409])
    assert.equal((r1.status === 409 ? r1 : r2).json.error, 'training')
    const res = await T.db.query('select res, amount::int as n from player_resources where player_id = $1 order by res', [id])
    assert.deepEqual(res, [{ res: 'food', n: 800 }, { res: 'stone', n: 900 }, { res: 'wood', n: 1000 }])
    const [q] = await T.db.query("select train_count, extract(epoch from train_finish)::float8 as f from player_buildings where player_id = $1 and building = 'stable'", [id])
    assert.deepEqual(q, { train_count: 5, f: T0 + 5 * H3 })
    assert.equal((await T.db.query("select count(*)::int as n from economy_log where player_id = $1 and kind = 'train_start'", [id]))[0].n, 1)
  } finally {
    await T.close()
  }
})

test('test/age가 훈련 끝나는 시각도 당긴다(통합 테스트 훅): 3시간 앞당기면 1마리 묶음을 바로 수령', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setRes(id, { food: 100, wood: 100 })
  assert.equal((await train(token, { building: 'barracks', count: 1 })).status, 200)
  const r = await S.req('POST', '/v1/test/age', { token, body: { minutes: 180 } })
  assert.deepEqual(r.json.player.training.barracks, { count: 1, tier: 1, finish: T0 })
  assert.deepEqual((await collect(token, 'barracks')).json.player.soldiers, { 'infantry:1': 1 })
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

test('플레이어 격리: 한 플레이어의 훈련·합성·배치는 다른 플레이어 보유·배치·대기열에 닿지 않는다', async () => {
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
  await setRes(b.id, { food: 100, wood: 100 })
  assert.equal((await train(b.token, { building: 'barracks', count: 2 })).status, 200)
  assert.deepEqual((await collect(a.token, 'barracks')).json.error, 'empty') // a의 대기열은 비어 있다
  S.clock.t = T0 + 2 * H3
  assert.deepEqual((await collect(b.token, 'barracks')).json.player.soldiers, { 'infantry:1': 2 })
  const pa = await player(a.token)
  assert.deepEqual([pa.soldiers, pa.training], [{ 'cavalry:1': 1, 'cavalry:2': 1 }, NONE])
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
    assert.deepEqual(await migrate(d), all.filter((f) => f >= '008'))
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

test('마이그레이션 010: 009까지 적용된 DB의 병사 건물 행은 빈 대기열(0·null)을 받고, 수·끝나는 시각이 어긋난 행은 제약이 막는다', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'castle-mig-'))
  tmp.push(dir)
  const all = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort()
  for (const f of all.filter((f) => f < '010')) cpSync(join(MIGRATIONS_DIR, f), join(dir, f))
  const d = await openDb({})
  try {
    await migrate(d, dir)
    const [p] = await d.query("insert into players (device_id) values ('mig-010-device-0001') returning id")
    await d.query('insert into player_state (player_id) values ($1)', [p.id])
    await d.query("insert into player_buildings (player_id, building, level) values ($1, 'barracks', 3), ($1, 'lumber', 2)", [p.id])
    assert.deepEqual(await migrate(d), all.filter((f) => f >= '010'))
    const rows = await d.query('select building, level, train_count, train_finish from player_buildings where player_id = $1 order by building', [p.id])
    assert.deepEqual(rows, [{ building: 'barracks', level: 3, train_count: 0, train_finish: null }, { building: 'lumber', level: 2, train_count: 0, train_finish: null }])
    await assert.rejects(d.query("update player_buildings set train_count = 3 where player_id = $1 and building = 'barracks'", [p.id]), /train_queue/)
    await assert.rejects(d.query("update player_buildings set train_finish = now() where player_id = $1 and building = 'barracks'", [p.id]), /train_queue/)
    await assert.rejects(d.query("update player_buildings set train_count = -1, train_finish = now() where player_id = $1 and building = 'barracks'", [p.id]), /check/)
    const cfg = await d.query("select key, value from game_config where key like 'train_%' order by key")
    assert.deepEqual(cfg.map((r) => r.key), ['train_base_min', 'train_batch_base', 'train_batch_per_level', 'train_cost_archer', 'train_cost_cavalry', 'train_cost_infantry', 'train_cost_tier_mult', 'train_step_min'])
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
    ['config.csv', cfg.replace('train_step_min,3', 'train_step_min,0'), /train_step_min must be an integer of at least 1/],
    ['config.csv', cfg.replace(/^soldier_tier_mult,.*\n/m, ''), /missing key 'soldier_tier_mult'/],
    ['config.csv', cfg.replace('train_batch_base,1', 'train_batch_base,0'), /train_batch_base must be an integer of at least 1: '0'/],
    ['config.csv', cfg.replace('train_batch_per_level,0', 'train_batch_per_level,1.5'), /train_batch_per_level must be a non-negative integer: '1.5'/],
    ['config.csv', cfg.replace(/^train_cost_archer,.*\n/m, ''), /missing key 'train_cost_archer'/],
    ['config.csv', cfg.replace('train_cost_cavalry,food:40|stone:20', 'train_cost_cavalry,food:40|gold:20'), /line \d+ column 'value': train_cost_cavalry must be 'res:amount\|…'/],
    ['config.csv', cfg.replace('train_cost_infantry,food:30|wood:20', 'train_cost_infantry,food:-30'), /train_cost_infantry must be/],
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

// --- 개정 19: 막사 레벨이 훈련 티어·시간을 정한다 ---
test('r19 표: 티어·1마리 시간(L 1, 2, 6, 7, 12, 13, 19, 25, 30, 31), 비용 ×5^(t−1)', () => {
  const cfg: R.Config = { ...CFG, train_cost_infantry: 'food:30|wood:20' }
  const want: [number, number, number][] = [[1, 1, 180], [2, 1, 150], [6, 1, 30], [7, 2, 180], [12, 2, 30], [13, 3, 180], [19, 4, 180], [25, 5, 180], [30, 5, 30], [31, 5, 30]]
  for (const [L, t, min] of want) assert.deepEqual([R.trainTier(cfg, L), R.soldierUnitSec(cfg, L) / 60], [t, min], 'L' + L)
  assert.deepEqual(R.trainCost(cfg, 'infantry', 2, 1), { food: 60, wood: 40 })
  assert.deepEqual(R.trainCost(cfg, 'infantry', 2, 2), { food: 300, wood: 200 })
  assert.deepEqual(R.trainCost(cfg, 'infantry', 1, 3), { food: 750, wood: 500 })
})

test('r19 서버: Lv7 막사는 T2 3:00·비용 ×5, 수령은 infantry:2, 진행 중 묶음은 레벨업 뒤에도 티어·시각 고정, 취소 환불은 그 티어 기준', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setRes(id, { food: 100000, wood: 100000 })
  await setLevel(id, 'barracks', 7)
  let r = await train(token, { building: 'barracks', count: 2 })
  assert.deepEqual([r.status, r.json.player.res.food, r.json.player.res.wood], [200, 100000 - 300, 100000 - 200])
  assert.deepEqual(r.json.player.training.barracks, { count: 2, tier: 2, finish: T0 + 2 * H3 })
  await setLevel(id, 'barracks', 13) // 진행 중 레벨업: T3로 올라도 묶음은 그대로
  assert.deepEqual((await player(token)).training.barracks, { count: 2, tier: 2, finish: T0 + 2 * H3 })
  r = await cancel(token, 'barracks')
  assert.deepEqual(r.json.refund, { food: 150, wood: 100 })
  await setLevel(id, 'barracks', 7)
  assert.equal((await train(token, { building: 'barracks', count: 2 })).status, 200)
  await setLevel(id, 'barracks', 13)
  S.clock.t = T0 + 2 * H3
  r = await collect(token, 'barracks')
  assert.deepEqual([r.status, r.json.player.soldiers, r.json.collected], [200, { 'infantry:2': 2 }, { type: 'infantry', count: 2, tier: 2 }])
  assert.equal((await logs(id, 'train_start'))[0].detail.tier, 2)
})

test('r19 마이그레이션 013: train_tier 열, 진행 중 묶음 1·빈 건물 null, 새 설정 키, 옛 soldier_prod_* 제거', async () => {
  S.clock.t = T0
  const { id } = await S.login()
  const cols = await S.db.query("select column_name from information_schema.columns where table_name = 'player_buildings' and column_name = 'train_tier'")
  assert.equal(cols.length, 1)
  const [b] = await S.db.query("select train_tier from player_buildings where player_id = $1 and building = 'barracks'", [id])
  assert.equal(b.train_tier, null)
  const keys = (await S.db.query("select key from game_config where key in ('train_base_min','train_step_min','train_cost_tier_mult','soldier_prod_sec')")).map((x) => x.key).sort()
  assert.deepEqual(keys, ['train_base_min', 'train_cost_tier_mult', 'train_step_min'])
})

test('r19 마이그레이션 013 업그레이드: 012 이전 DB의 진행 중 묶음은 train_tier 1, 빈 건물은 null', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'castle-mig-'))
  tmp.push(dir)
  const all = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort()
  for (const f of all.filter((f) => f < '013')) cpSync(join(MIGRATIONS_DIR, f), join(dir, f))
  const d = await openDb({})
  try {
    await migrate(d, dir)
    const [p] = await d.query("insert into players (device_id) values ('mig-013-device-0001') returning id")
    await d.query('insert into player_state (player_id) values ($1)', [p.id])
    await d.query("insert into player_buildings (player_id, building, level, train_count, train_finish) values ($1, 'barracks', 3, 4, now()), ($1, 'stable', 1, 0, null)", [p.id])
    assert.deepEqual(await migrate(d), all.filter((f) => f >= '013'))
    const rows = await d.query('select building, train_tier from player_buildings where player_id = $1 order by building', [p.id])
    assert.deepEqual(rows, [{ building: 'barracks', train_tier: 1 }, { building: 'stable', train_tier: null }])
  } finally {
    await d.close()
  }
})

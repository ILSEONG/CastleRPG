// 연구 테크트리(개정 24 §2~§4): 비용·시간 공식(연구소·연구 속도), 잠금(연구소·선행), 바쁨·부족 409, 취소 환불, 다이아 즉시 완료,
// 게으른 자동 완료, 서버 권위 효과(수집·건설 시간·판매·처치 골드·훈련 시간·비용·인구), 원자성, 마이그레이션 016, 시드 검증, 응답 형식.
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
let G: { research: R.ResearchDef[]; config: R.Config; stages: R.StageRow[] }
const tmp: string[] = []
before(async () => {
  S = await setup()
  G = (await S.req('GET', '/v1/gamedata')).json
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

const def = (id: string) => G.research.find((d) => d.id === id) as R.ResearchDef
const player = async (token: string) => (await S.req('GET', '/v1/player', { token })).json.player
const start = (token: string, id: unknown) => S.req('POST', '/v1/research/start', { token, body: { id } })
const logs = async (id: string, kind = 'research') => (await S.db.query('select detail from economy_log where player_id = $1 and kind = $2 order by id', [id, kind])).map((r) => r.detail)
const setRes = (id: string, r: Record<string, number>) =>
  Promise.all(Object.entries(r).map(([res, n]) => S.db.query('update player_resources set amount = $3 where player_id = $1 and res = $2', [id, res, n])))
const setGold = (id: string, tenths: number) => S.db.query('update player_state set gold_tenths = $2 where player_id = $1', [id, tenths])
const setDia = (id: string, n: number) => S.db.query('update player_state set diamonds = $2 where player_id = $1', [id, n])
const setLevel = (id: string, building: string, l: number) => S.db.query('update player_buildings set level = $3 where player_id = $1 and building = $2', [id, building, l])
// 연구 레벨을 DB에 직접(효과·잠금 준비)
async function setResearch(id: string, levels: Record<string, number>) {
  for (const [k, l] of Object.entries(levels)) {
    await S.db.query('insert into player_research (player_id, id, level) values ($1, $2, $3) on conflict (player_id, id) do update set level = excluded.level', [id, k, l])
  }
}
const RICH = { wood: 1_000_000, stone: 1_000_000, food: 1_000_000 }
async function fresh(t = T0) {
  S.clock.t = t
  return S.login()
}

test('공식: 비용 = round(값 × 1.3^n), 시간 = round(base_sec × 1.35^n / (1 + 연구 속도)), 속도 = research_speed_pct/100 + 0.02 × (연구소 − 1)', () => {
  const c = G.config
  assert.deepEqual([0, 1, 2, 3].map((n) => R.researchCost(c, def('wood_tech'), n)), [
    { wood: 1200, stone: 800, food: 1000, gold: 0 }, { wood: 1560, stone: 1040, food: 1300, gold: 0 },
    { wood: 2028, stone: 1352, food: 1690, gold: 0 }, { wood: 2636, stone: 1758, food: 2197, gold: 0 }])
  assert.deepEqual(R.researchCost(c, def('construct'), 1), { wood: 5200, stone: 3900, food: 4550, gold: 6500 })
  assert.deepEqual(R.researchCost(c, def('elite'), 9), { wood: 424180, stone: 318135, food: 371157, gold: 1590675 })
  // 스펙 예: 벌목술 1레벨 60초, 10레벨 약 15분, 정예 전술 10레벨 약 15시간(보너스 없이)
  assert.deepEqual([0, 1, 2, 9].map((n) => R.researchSec(c, def('wood_tech'), n, 0)), [60, 81, 109, 894])
  assert.equal(R.researchSec(c, def('elite'), 9, 0), 53617)
  const none = R.researchBonus(G.research, {})
  assert.equal(R.researchSpeed(c, none, 1), 0)
  assert.equal(R.researchSec(c, def('construct'), 0, R.researchSpeed(c, none, 3)), 288) // 300 / 1.04
  const speed = R.researchSpeed(c, R.researchBonus(G.research, { method: 5 }), 11) // 0.15 + 0.2
  assert.ok(Math.abs(speed - 0.35) < 1e-12, String(speed))
  assert.equal(R.researchSec(c, def('construct'), 0, speed), 222) // 300 / 1.35
  assert.equal(R.researchSpeed(c, none, 30), 0.02 * 29) // Lv30 +58%
})

test('효과 합계: 모든 키(없으면 0), 같은 effect끼리 더하고, 레벨은 0..max_level로 자른다. 환불·다이아 비용', () => {
  const b = R.researchBonus(G.research, { hero_weapon: 3, legend_weapon: 2, barracks_ext: 9, wood_tech: -4, ghost: 7 })
  assert.deepEqual(Object.keys(b), R.RESEARCH_EFFECTS)
  assert.equal(b.hero_atk_pct, 3 * 3 + 2 * 4) // 무기 연마 + 전설의 무기
  assert.equal(b.pop_add, 5) // barracks_ext 최대 5
  assert.equal(b.wood_pct, 0)
  assert.equal(Object.values(b).reduce((s, v) => s + v, 0), 17 + 5)
  assert.deepEqual(R.researchRefund(G.config, { wood: 2028, stone: 1352, food: 1690, gold: 651 }), { wood: 1014, stone: 676, food: 845, gold: 325 })
  assert.deepEqual([0.5, 1, 60, 60.5, 61, 3600].map((left) => R.researchDiaCost(G.config, T0 + left, T0)), [1, 1, 1, 2, 2, 60])
  assert.equal(R.researchDiaCost(G.config, T0, T0), 1) // 최소 1
  // 생산 %·훈련 할인: pct 0이면 예전 값 그대로
  assert.equal(R.pendingAmount(100, 2, 600, 720), 2000)
  assert.equal(R.pendingAmount(100, 1, 600, 720, 15), 1150) // floor(100 × 1.15) = 115/분
  assert.equal(R.researchProdPct({ ...b, wood_pct: 15, res_pct: 3 }, 'wood'), 18)
  assert.deepEqual(R.trainCost(G.config, 'infantry', 2, 1, 10), { food: 2700, wood: 1800 })
  assert.deepEqual(R.trainCost(G.config, 'infantry', 1, 1, 0.04), { food: 1499, wood: 1000 }) // 1499.4 → 1499, 999.6 → 1000
  assert.deepEqual(R.trainCost(G.config, 'infantry', 1, 1, 100), {}) // 0인 자원은 뺀다
})

test('시작 → 자동 완료: 비용 전부 차감, 진행 {id, finish}, 끝나는 시각이 지나면 다음 읽기가 레벨 +1(로그 start·done). 다음 레벨은 1.3배·1.35배', async () => {
  const { token, id } = await fresh()
  await setRes(id, { wood: 10000, stone: 10000, food: 10000 })
  let r = await start(token, 'wood_tech')
  assert.equal(r.status, 200)
  assert.deepEqual([r.json.player.res, r.json.player.research], [{ wood: 8800, stone: 9200, food: 9000 }, { levels: {}, current: { id: 'wood_tech', finish: T0 + 60 } }])
  S.clock.t = T0 + 59.9
  assert.deepEqual((await player(token)).research.current, { id: 'wood_tech', finish: T0 + 60 })
  S.clock.t = T0 + 60
  assert.deepEqual((await player(token)).research, { levels: { wood_tech: 1 }, current: null })
  r = await start(token, 'wood_tech')
  assert.deepEqual([r.status, r.json.player.res, r.json.player.research.current], [200, { wood: 7240, stone: 8160, food: 7700 }, { id: 'wood_tech', finish: T0 + 60 + 81 }])
  assert.deepEqual(await logs(id), [
    { action: 'start', id: 'wood_tech', level: 1, cost: { wood: 1200, stone: 800, food: 1000, gold: 0 }, sec: 60, finish: T0 + 60 },
    { action: 'done', id: 'wood_tech', level: 1, finish: T0 + 60 },
    { action: 'start', id: 'wood_tech', level: 2, cost: { wood: 1560, stone: 1040, food: 1300, gold: 0 }, sec: 81, finish: T0 + 141 },
  ])
  // 테스트 훅 age가 연구 끝나는 시각도 당긴다(앱 통합 테스트용) — 같은 응답이 완료를 반영
  r = await S.req('POST', '/v1/test/age', { token, body: { minutes: 2 } })
  assert.deepEqual(r.json.player.research, { levels: { wood_tech: 2 }, current: null })
})

test('연구 속도: 연구소 레벨과 연구 방법론(research_speed_pct)이 시간을 줄인다. 골드는 정수 골드 × 10 tenths를 뺀다', async () => {
  const { token, id } = await fresh()
  await setRes(id, RICH)
  await setGold(id, 5000 * 10 + 7)
  await setLevel(id, 'lab', 11)
  await setResearch(id, { wood_tech: 3, stone_tech: 3, method: 5 })
  const r = await start(token, 'construct')
  assert.equal(r.status, 200)
  assert.deepEqual([r.json.player.research.current, r.json.player.gold_tenths], [{ id: 'construct', finish: T0 + 222 }, 7])
})

test('검사 순서: 400(id 형식) → 404 unknown_research → 409 research_busy → max_level → locked(연구소·선행) → not_enough_resources → not_enough_gold', async () => {
  const { token, id } = await fresh()
  for (const bad of [undefined, '', 5, null]) assert.equal((await start(token, bad)).status, 400, String(bad))
  let r = await start(token, 'nope')
  assert.deepEqual([r.status, r.json.error], [404, 'unknown_research'])
  // 자원 0: 1단 노드도 not_enough_resources
  r = await start(token, 'wood_tech')
  assert.deepEqual([r.status, r.json.error], [409, 'not_enough_resources'])
  // 잠금: 연구소 Lv 1 < 3
  await setRes(id, RICH)
  r = await start(token, 'construct')
  assert.deepEqual([r.status, r.json.error], [409, 'locked'])
  await setLevel(id, 'lab', 3)
  await setResearch(id, { wood_tech: 3, stone_tech: 2 }) // 선행 2 모자람
  r = await start(token, 'construct')
  assert.deepEqual([r.status, r.json.error], [409, 'locked'])
  await setResearch(id, { stone_tech: 3 })
  r = await start(token, 'construct') // 이제 열림 — 골드 5000 부족
  assert.deepEqual([r.status, r.json.error], [409, 'not_enough_gold'])
  await setRes(id, { wood: 3999 })
  r = await start(token, 'construct') // 자원과 골드가 둘 다 모자라면 자원이 먼저
  assert.deepEqual([r.status, r.json.error], [409, 'not_enough_resources'])
  let p = await player(token)
  assert.deepEqual([p.res.wood, p.gold_tenths, p.research.current], [3999, 0, null]) // 아무것도 안 바뀐다
  await setResearch(id, { wood_tech: 10 })
  r = await start(token, 'wood_tech')
  assert.deepEqual([r.status, r.json.error], [409, 'max_level'])
  // 진행 중이면 다른 노드도 research_busy(최대 레벨보다 먼저), 모르는 노드는 그래도 404
  assert.equal((await start(token, 'stone_tech')).status, 200)
  for (const [node, code] of [['food_tech', 'research_busy'], ['wood_tech', 'research_busy'], ['construct', 'research_busy']]) {
    r = await start(token, node)
    assert.deepEqual([r.status, r.json.error], [409, code], node)
  }
  assert.equal((await start(token, 'nope')).status, 404)
  p = await player(token)
  assert.deepEqual(p.research.current, { id: 'stone_tech', finish: T0 + Math.round(R.grown(60, 1.35, 3) / 1.04) })
  assert.equal((await logs(id)).length, 1)
})

test('취소: 진행 중이 아니면 409 no_research. 그 레벨 비용의 50%(자원·골드마다 내림)를 돌려주고 비운다', async () => {
  const { token, id } = await fresh()
  assert.deepEqual([(await S.req('POST', '/v1/research/cancel', { token })).status, (await S.req('POST', '/v1/research/cancel', { token })).json.error], [409, 'no_research'])
  await setRes(id, { wood: 10000, stone: 10000, food: 10000 })
  await setResearch(id, { wood_tech: 2 })
  assert.equal((await start(token, 'wood_tech')).status, 200) // 2 → 3: 2028·1352·1690
  let r = await S.req('POST', '/v1/research/cancel', { token, body: {} })
  assert.deepEqual([r.status, r.json.refund, r.json.player.res, r.json.player.research], [200, { wood: 1014, stone: 676, food: 845, gold: 0 },
    { wood: 10000 - 2028 + 1014, stone: 10000 - 1352 + 676, food: 10000 - 1690 + 845 }, { levels: { wood_tech: 2 }, current: null }])
  // 골드 환불은 정수 골드 × 10 tenths
  await setLevel(id, 'lab', 3)
  await setResearch(id, { wood_tech: 3, stone_tech: 3, construct: 1 })
  await setGold(id, 6500 * 10 + 3)
  assert.equal((await start(token, 'construct')).status, 200) // 1 → 2: 5200·3900·4550·6500
  r = await S.req('POST', '/v1/research/cancel', { token })
  assert.deepEqual([r.json.refund, r.json.player.gold_tenths], [{ wood: 2600, stone: 1950, food: 2275, gold: 3250 }, 3 + 32500])
  const l = await logs(id)
  assert.deepEqual(l.filter((x: any) => x.action === 'cancel'), [
    { action: 'cancel', id: 'wood_tech', level: 3, refund: { wood: 1014, stone: 676, food: 845, gold: 0 } },
    { action: 'cancel', id: 'construct', level: 2, refund: { wood: 2600, stone: 1950, food: 2275, gold: 3250 } },
  ])
  assert.equal((await S.req('POST', '/v1/research/cancel', { token })).json.error, 'no_research')
})

test('다이아 즉시 완료: 비용 = max(1, ceil(남은 초 / 60) × 1), 모자라면 409 not_enough_diamonds(안 바뀐다), 진행 중이 아니면 409 no_research', async () => {
  const { token, id } = await fresh()
  let r = await S.req('POST', '/v1/research/finish', { token })
  assert.deepEqual([r.status, r.json.error], [409, 'no_research'])
  await setRes(id, RICH)
  await setGold(id, 5000 * 10)
  await setLevel(id, 'lab', 3)
  await setResearch(id, { wood_tech: 3, stone_tech: 3 })
  assert.equal((await start(token, 'construct')).status, 200) // 288초
  // 5분 이하는 무료(free_finish.test.ts)라 다이아 비용을 보려고 끝나는 시각을 1000초 뒤로 늘린다 → 17 다이아
  await S.db.query('update player_state set research_finish = to_timestamp($2::float8) where player_id = $1', [id, T0 + 1000])
  await setDia(id, 16)
  r = await S.req('POST', '/v1/research/finish', { token })
  assert.deepEqual([r.status, r.json.error], [409, 'not_enough_diamonds'])
  let p = await player(token)
  assert.deepEqual([p.diamonds, p.research.current], [16, { id: 'construct', finish: T0 + 1000 }])
  S.clock.t = T0 + 280 // 남은 720초 → 12 다이아
  r = await S.req('POST', '/v1/research/finish', { token, body: {} })
  assert.deepEqual([r.status, r.json.diamonds_spent, r.json.player.diamonds, r.json.player.research], [200, 12, 4, { levels: { wood_tech: 3, stone_tech: 3, construct: 1 }, current: null }])
  assert.deepEqual((await logs(id)).at(-1), { action: 'finish', id: 'construct', level: 1, diamonds: 12 })
  S.clock.t = T0 + 1000 // 이미 끝났으니 자동 완료가 다시 오르지 않는다
  p = await player(token)
  assert.equal(p.research.levels.construct, 1)
  assert.equal((await logs(id)).filter((x: any) => x.action === 'done').length, 0)
})

test('효과(서버 권위): 생산(wood_pct + res_pct, 분당 내림)·업그레이드 자동 수집·건설 시간(build_speed_pct)', async () => {
  const { token, id } = await fresh()
  await setResearch(id, { wood_tech: 3, abundance: 1 }) // 목재 15 + 3 = 18%, 석재 3%
  S.clock.t = T0 + 600
  let r = await S.req('POST', '/v1/collect', { token, body: { building: 'lumber' } })
  assert.equal(r.json.amount, 10 * Math.floor(100 * 118 / 100)) // 118/분 × 10분(연구 없으면 1000)
  r = await S.req('POST', '/v1/collect', { token, body: { building: 'quarry' } })
  assert.equal(r.json.amount, 10 * 103) // floor(100 × 1.03) = 103
  // 업그레이드 자동 수집도 같은 규칙(목재 15% → 115/분), 건설 시간 = round(20 / 1.15) = 17
  await setResearch(id, { abundance: 0, construct: 5 })
  await setRes(id, RICH)
  for (const b of ['keep', 'gate', 'barracks']) await setLevel(id, b, 2) // 성채 상한·성채 선행
  await S.db.query('update player_state set keep_level = 2, gate_level = 2 where player_id = $1', [id])
  S.clock.t = T0 + 1200
  r = await S.req('POST', '/v1/building/upgrade', { token, body: { building: 'lumber' } })
  assert.equal(r.status, 200)
  assert.deepEqual([r.json.build, r.json.player.res.wood], [{ id: 'lumber', finish: T0 + 1200 + 17 }, 1_000_000 + 10 * 115 - 600])
  S.clock.t = T0 + 1217
  await setResearch(id, { construct: 10 })
  r = await S.req('POST', '/v1/building/upgrade', { token, body: { building: 'keep' } })
  assert.deepEqual(r.json.build, { id: 'keep', finish: T0 + 1217 + 69 }) // round(90 / 1.3)
})

test('효과: 판매(sell_pct, 자원마다 내림 — 단일·all·items), 처치 골드(kill_gold_pct, 처치 1회 tenths에서 내림)', async () => {
  const { token, id } = await fresh(T0 + 30)
  await setResearch(id, { commerce: 5 })
  const rates = R.merchantRates(R.hourIndex(T0 + 30), G.config)
  const want = (amount: number, res: string, price: number) => Math.floor(R.sellValue(amount, price, rates[res]) * 115 / 100)
  await setRes(id, { wood: 7, stone: 9, food: 11 })
  let r = await S.req('POST', '/v1/sell', { token, body: { res: 'wood', amount: 7 } })
  assert.equal(r.json.gold_gained, want(7, 'wood', 1))
  r = await S.req('POST', '/v1/sell', { token, body: { items: [{ res: 'stone', amount: 4 }, { res: 'food', amount: 5 }] } })
  assert.equal(r.json.gold_gained, want(4, 'stone', 2) + want(5, 'food', 1))
  r = await S.req('POST', '/v1/sell', { token, body: { res: 'all' } })
  assert.equal(r.json.gold_gained, want(5, 'stone', 2) + want(6, 'food', 1))
  assert.ok(want(1000, 'wood', 1) > R.sellValue(1000, 1, rates.wood))
  // 처치 골드: 1단계 grunt 100 tenths × 1.15 = 115, 보스 2500 → 2875
  await setResearch(id, { plunder: 3 })
  S.clock.t = T0 + 60 // 처치 상한 버킷: 가입 뒤 30초
  const base = R.killGoldTenths(10, G.stages[0])
  assert.equal(base, 100)
  const before = (await player(token)).gold_tenths
  r = await S.req('POST', '/v1/kills', { token, body: { seq: 1, stage: 1, kills: { grunt: 3, epic_boss: 1 } } })
  assert.equal(r.json.gold_gained_tenths, 3 * 115 + 2875)
  assert.equal(r.json.player.gold_tenths, before + 3 * 115 + 2875)
})

test('효과: 훈련 시간(train_speed_pct, 반올림 없음)·비용(train_cost_pct, 반올림)·취소 환불(할인된 비용의 절반), 인구(pop_add)', async () => {
  const { token, id } = await fresh()
  await setRes(id, { wood: 10000, stone: 10000, food: 10000 })
  await setResearch(id, { drill_manual: 5, logistics: 5 }) // 시간 ÷ 1.15, 비용 × 0.9
  // 실제 설정은 1마리씩. 반올림 검사는 2마리 묶음으로 하므로 옛 묶음 상한을 쓴다
  await S.db.query("update game_config set value = '10' where key = 'train_batch_base'")
  let r = await S.req('POST', '/v1/soldiers/train', { token, body: { building: 'barracks', count: 2 } })
  assert.equal(r.status, 200)
  const unit = R.soldierUnitSec(G.config, 1)
  assert.deepEqual([r.json.training.finish, r.json.player.res], [T0 + 2 * unit / (1 + 15 / 100), { wood: 10000 - 1800, stone: 10000, food: 10000 - 2700 }])
  assert.deepEqual((await logs(id, 'train_start'))[0].cost, { food: 2700, wood: 1800 })
  r = await S.req('POST', '/v1/soldiers/cancel', { token, body: { building: 'barracks' } })
  assert.deepEqual([r.json.refund, r.json.player.res], [{ food: 1350, wood: 900 }, { wood: 10000 - 1800 + 900, stone: 10000, food: 10000 - 2700 + 1350 }])
  // 자원이 할인된 비용만큼만 있어도 된다
  await setRes(id, { wood: 1800, food: 2700 })
  assert.equal((await S.req('POST', '/v1/soldiers/train', { token, body: { building: 'barracks', count: 2 } })).status, 200)
  // 인구 = 6 + pop_add(병영 확장 3)
  await S.db.query("insert into player_soldiers (player_id, type, tier, count) values ($1, 'infantry', 1, 20)", [id])
  assert.equal((await player(token)).population, 6)
  await setResearch(id, { barracks_ext: 3 })
  assert.equal((await player(token)).population, 9)
  const deploy = (n: number) => S.req('POST', '/v1/soldiers/deploy', { token, body: { deploy: { 'infantry:1': n } } })
  assert.equal((await deploy(9)).status, 200)
  assert.deepEqual([(await deploy(10)).status, (await deploy(10)).json.error], [400, 'bad_deploy'])
})

test('원자성: 같은 순간 두 연구 시작이 겹치면 하나만 반영(version 가드) — 다른 쪽은 409 research_busy, 비용은 한 번만 빠지고 로그도 하나', async () => {
  const b = barrier()
  const T = await setup({ wrapQuery: b.wrap })
  try {
    T.clock.t = T0
    const { token, id } = await T.login()
    await T.db.query("update player_resources set amount = 10000 where player_id = $1", [id])
    b.arm()
    const [r1, r2] = await Promise.all([
      T.req('POST', '/v1/research/start', { token, body: { id: 'wood_tech' } }),
      T.req('POST', '/v1/research/start', { token, body: { id: 'stone_tech' } }),
    ])
    assert.equal(b.arrived(), 2)
    assert.deepEqual([r1.status, r2.status].sort(), [200, 409])
    assert.equal([r1, r2].find((r) => r.status === 409)?.json.error, 'research_busy')
    const p = (await T.req('GET', '/v1/player', { token })).json.player
    assert.deepEqual(p.res, { wood: 8800, stone: 9200, food: 9000 })
    const n = await T.db.query("select count(*)::int as n from economy_log where player_id = $1 and kind = 'research'", [id])
    assert.equal(n[0].n, 1)
  } finally {
    await T.close()
  }
})

test('gamedata: research 22행(파일 순서, CSV 열 이름 키, 빈 선행은 null), 연구 설정, lab_atk_per_level 없음. 응답 levels는 표에 있는 노드만', async () => {
  const g = (await S.req('GET', '/v1/gamedata')).json
  const csv = readFileSync(join(DATA_DIR, 'research.csv'), 'utf8').trim().split('\n').slice(1).map((l) => l.split(',')[0])
  assert.equal(g.research.length, 22)
  assert.deepEqual(g.research.map((d: any) => d.id), csv)
  assert.deepEqual(g.research[3], {
    id: 'construct', branch: 'economy', tier: 2, name: '건축학', effect: 'build_speed_pct', per_level: 3, max_level: 10, lab_req: 3,
    req1: 'wood_tech', req1_lv: 3, req2: 'stone_tech', req2_lv: 3, wood: 4000, stone: 3000, food: 3500, gold: 5000, base_sec: 300,
  })
  assert.deepEqual([g.research[0].req1, g.research[0].req1_lv, g.research[4].req2, g.research[4].req2_lv], [null, null, null, null])
  assert.deepEqual(['research_cost_growth', 'research_time_growth', 'lab_research_speed_per_level', 'research_cancel_refund', 'research_dia_per_min'].map((k) => g.config[k]),
    ['1.3', '1.35', '0.02', '0.5', '1'])
  assert.equal(g.config.lab_atk_per_level, undefined)
  const { token, id } = await fresh()
  await setResearch(id, { ghost: 4, wood_tech: 0, hero_weapon: 2 })
  assert.deepEqual((await player(token)).research, { levels: { hero_weapon: 2 }, current: null })
})

test('마이그레이션 016: 015까지 적용된 DB에 연구 표·player_research·진행 열이 생기고 설정 기본값이 들어가며 lab_atk_per_level은 지워진다', async () => {
  const all = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort()
  const dir = mkdtempSync(join(tmpdir(), 'castle-mig-'))
  tmp.push(dir)
  for (const f of all.filter((f) => f < '016')) cpSync(join(MIGRATIONS_DIR, f), join(dir, f))
  const d = await openDb({})
  try {
    await migrate(d, dir)
    const [p] = await d.query("insert into players (device_id) values ('mig-016-device-0001') returning id")
    await d.query('insert into player_state (player_id) values ($1)', [p.id])
    await d.query("insert into game_config (key, value) values ('lab_atk_per_level', '0.03'), ('research_cost_growth', '1.5')")
    assert.deepEqual((await migrate(d)).slice(0, 3), ['016_research.sql', '017_offline_gold.sql', '018_social_login.sql']) // 뒤에 019·020…이 붙는다
    const [s] = await d.query('select research_id, research_finish from player_state where player_id = $1', [p.id])
    assert.deepEqual(s, { research_id: null, research_finish: null })
    const cfg = await d.query("select key, value from game_config where key like 'research%' or key like 'lab_%' order by key")
    assert.deepEqual(cfg.map((r) => `${r.key}=${r.value}`), ['lab_research_speed_per_level=0.02', 'research_cancel_refund=0.5', 'research_cost_growth=1.5',
      'research_dia_per_min=1', 'research_time_growth=1.35']) // 이미 있던 값은 그대로
    assert.deepEqual(await d.query('select count(*)::int as n from research_defs'), [{ n: 0 }])
    await assert.rejects(d.query("insert into player_research (player_id, id, level) values ($1, 'wood_tech', -1)", [p.id]))
    await assert.rejects(d.query("update player_state set research_id = 'wood_tech' where player_id = $1", [p.id])) // 끝나는 시각 없이
    await d.query("update player_state set research_id = 'wood_tech', research_finish = now() where player_id = $1", [p.id])
  } finally {
    await d.close()
  }
})

test('시드 검증: research.csv(branch·effect, 숫자 범위, 선행은 표 안·레벨과 함께·1..그 노드 max_level 정수)와 연구 설정 범위. 오류는 파일·줄·열', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'castle-data-'))
  tmp.push(dir)
  for (const t of TABLES) cpSync(join(DATA_DIR, t.file), join(dir, t.file))
  const rs = readFileSync(join(DATA_DIR, 'research.csv'), 'utf8')
  const cfg = readFileSync(join(DATA_DIR, 'config.csv'), 'utf8')
  const W = 'wood_tech,economy,1,벌목술,wood_pct,5,10,1,,,,,1200,800,1000,0,60'
  const C = 'construct,economy,2,건축학,build_speed_pct,3,10,3,wood_tech,3,stone_tech,3,'
  const L = 'legend_armor,hero,3,불굴의 의지,hero_hp_pct,4,10,15,arcana,5,,,40000,30000,35000,150000,3600'
  const cases: [string, string, RegExp][] = [
    ['research.csv', rs.replace(W, W.replace('economy', 'navy')), /research\.csv line 2 column 'branch': must be one of economy\/military\/hero: 'navy'/],
    ['research.csv', rs.replace(W, W.replace('wood_pct', 'lumber_pct')), /research\.csv line 2 column 'effect': unknown effect 'lumber_pct'/],
    ['research.csv', rs.replace(W, W.replace(/,60$/, ',0')), /line 2 column 'base_sec': must be greater than 0: 0/],
    ['research.csv', rs.replace(L, L.replace(',4,10,15,', ',4,0,15,')), /line 23 column 'max_level': must be at least 1: 0/],
    ['research.csv', rs.replace(L, L.replace('hero,3,', 'hero,0,')), /line 23 column 'tier': must be at least 1: 0/],
    ['research.csv', rs.replace(L, L.replace(',150000,', ',-1,')), /line 23 column 'gold': must be 0 or more: -1/],
    ['research.csv', rs.replace(L, L.replace(',4,10,', ',x,10,')), /line 23 column 'per_level': not a number: 'x'/],
    ['research.csv', rs.replace(C, C.replace('wood_tech,3', 'wood_tek,3')), /line 5 column 'req1': unknown research 'wood_tek'/],
    ['research.csv', rs.replace(C, C.replace('wood_tech,3', 'wood_tech,11')), /line 5 column 'req1_lv': must be an integer in 1\.\.10 \(max level of 'wood_tech'\): 11/],
    ['research.csv', rs.replace(C, C.replace('stone_tech,3', 'stone_tech,2.5')), /line 5 column 'req2_lv': must be an integer in 1\.\.10/],
    ['research.csv', rs.replace(C, C.replace('stone_tech,3', 'stone_tech,0')), /line 5 column 'req2_lv': must be an integer in 1\.\.10/],
    ['research.csv', rs.replace(C, C.replace('wood_tech,3', 'wood_tech,')), /line 5 column 'req1_lv': req1 and req1_lv must be both set or both empty/],
    ['research.csv', rs.replace(C, C.replace('wood_tech,3', ',3')), /line 5 column 'req1': req1 and req1_lv must be both set or both empty/],
    ['research.csv', rs.replace(L, L.replace('legend_armor', 'arcana')), /duplicate key 'arcana'/],
    ['config.csv', cfg.replace('research_cost_growth,1.3', 'research_cost_growth,0.9'), /config\.csv line \d+ column 'value': research_cost_growth must be 1 or more: '0\.9'/],
    ['config.csv', cfg.replace('research_time_growth,1.35', 'research_time_growth,0.5'), /research_time_growth must be 1 or more/],
    ['config.csv', cfg.replace('lab_research_speed_per_level,0.02', 'lab_research_speed_per_level,-0.01'), /lab_research_speed_per_level must be 0 or more/],
    ['config.csv', cfg.replace('research_cancel_refund,0.5', 'research_cancel_refund,1.5'), /research_cancel_refund must be in 0\.\.1: '1\.5'/],
    ['config.csv', cfg.replace('research_dia_per_min,1', 'research_dia_per_min,1.5'), /research_dia_per_min must be a non-negative integer: '1\.5'/],
    ['config.csv', cfg.replace('research_dia_per_min,1', 'research_dia_per_min,abc'), /config\.csv line \d+ column 'value': not a number: 'abc'/],
    ['config.csv', cfg.replace(/^research_cost_growth,.*\n/m, ''), /missing key 'research_cost_growth'/],
  ]
  for (const [file, text, re] of cases) {
    assert.notEqual(text, file === 'research.csv' ? rs : cfg, `${re}: replacement did not apply`)
    writeFileSync(join(dir, file), text)
    await assert.rejects(readTables(dir), (e: unknown) => {
      assert.ok(e instanceof CsvError)
      assert.equal(e.errors.length, 1, `${re}: ${e.errors.join(' | ')}`)
      assert.match(e.errors[0], re)
      return true
    })
    writeFileSync(join(dir, file), file === 'research.csv' ? rs : cfg)
  }
  const t = await readTables(dir) // 원래대로면 통과
  assert.equal(t.research.length, 22)
})

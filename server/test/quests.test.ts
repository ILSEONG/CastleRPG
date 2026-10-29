// 튜토리얼·반복 퀘스트(온라인): 새 플레이어 공터·튜토리얼 상태, 공터 짓기·수집·훈련·연구 거부, 튜토리얼 훈련 5초, 보상 받기(진행 번호·needs·재전송),
// 반복 퀘스트(바퀴 보상·간격·튜토리얼 중 거부), 다이아 모집권 모집, 기존 플레이어는 skipped, 시드 검증.
import assert from 'node:assert/strict'
import { cpSync, mkdtempSync, readdirSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { after, before, test } from 'node:test'
import { MIGRATIONS_DIR, migrate, openDb } from '../src/db.ts'
import * as M from '../src/missions.ts'
import * as R from '../src/rules.ts'
import { readTables, seed } from '../src/seed.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

// 2026-10-13: 성채 레벨로 여는 새 건물 5종과 자원 건물 2~4번째 채는 늘 공터로 시작한다(정렬)
const LOTS = ['dispatch', 'forge', 'goldmine', 'guild_hall', 'warehouse', 'watchtower',
  ...['lumber', 'quarry', 'farm'].flatMap((b) => [2, 3, 4].map((n) => `${b}#${n}`))].sort()

let S: Setup
before(async () => {
  S = await setup({ tutorial: true })
})
after(async () => {
  await S.close()
})

const player = async (token: string) => (await S.req('GET', '/v1/player', { token })).json.player
const claim = (token: string, body: unknown) => S.req('POST', '/v1/quest/claim', { token, body })
// 서버가 세는 사건 수를 채운다(진행 확인 — 통합 테스트 2026-10-07)
const pump = (token: string, n = 1_000_000) => S.req('POST', '/v1/test/events', { token, body: { events: Object.fromEntries(M.EVENTS.map((k) => [k, n])) } })
const setStage = (token: string, stage: number) => S.req('POST', '/v1/test/stage', { token, body: { stage } })
const setRes = (id: string, r: Record<string, number>) => Promise.all(Object.entries(r).map(([res, n]) =>
  S.db.query('update player_resources set amount = $3 where player_id = $1 and res = $2', [id, res, n])))
const tutorialRows = async () => (await readTables()).quests.filter((r) => r.type === 'tutorial')

test('새 플레이어: 튜토리얼 active, 성채·성문 밖 건물은 공터(레벨 1 그대로), 모집권 0', async () => {
  S.clock.t = T0
  const { token } = await S.login()
  const p = await player(token)
  assert.deepEqual(p.quest, { tut_state: 'active', tut_step: 0, rep_n: 0, rep: null }) // 가이드 중엔 반복 퀘스트 진행이 없다
  assert.equal(p.dia_tickets, 0)
  assert.deepEqual(p.unbuilt, ['archery', 'barracks', 'farm', 'houses', 'lab', 'lumber', 'quarry', 'stable', 'tavern', ...LOTS].sort())
  assert.equal(p.buildings.lumber.level, 1)
})

test('공터: 수집·훈련·연구는 409, 짓기는 선행·성채 상한 없이 Lv 1 비용·시간, 다 지으면 공터에서 빠지고 레벨은 1, 생산은 다 지은 시각부터', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  assert.equal((await S.req('POST', '/v1/collect', { token, body: { building: 'lumber' } })).json.error, 'unbuilt')
  assert.equal((await S.req('POST', '/v1/soldiers/train', { token, body: { building: 'barracks', count: 1 } })).json.error, 'unbuilt')
  assert.equal((await S.req('POST', '/v1/research/start', { token, body: { id: 'wood_tech' } })).json.error, 'lab_unbuilt')
  await setRes(id, { wood: 10000, stone: 10000, food: 10000 })
  const g = (await S.req('GET', '/v1/gamedata')).json
  const def = g.buildings.find((b: any) => b.id === 'stable') // 선행(막사·궁병)이 있어도 공터는 그냥 짓는다
  const r = await S.req('POST', '/v1/building/upgrade', { token, body: { building: 'stable' } })
  assert.equal(r.status, 200)
  const cost = R.buildCost(def, 1)
  assert.deepEqual(r.json.player.res, { wood: 10000 - cost.wood, stone: 10000 - cost.stone, food: 10000 - cost.food })
  assert.equal(r.json.build.finish, T0 + 5) // 공터 첫 건설 = lot_build_sec(5)초
  assert.equal((await S.req('POST', '/v1/building/upgrade', { token, body: { building: 'lumber' } })).json.error, 'builder_busy')
  const done = (await S.req('POST', '/v1/test/build_now', { token })).json.player
  assert.equal(done.buildings.stable.level, 1)
  assert.ok(!done.unbuilt.includes('stable'))
  const [log] = await S.db.query("select detail from economy_log where player_id = $1 and kind = 'build_done'", [id])
  assert.deepEqual([log.detail.from, log.detail.to], [0, 1])
  // 자원 건물: 다 지은 시각부터 쌓인다
  await S.req('POST', '/v1/building/upgrade', { token, body: { building: 'lumber' } })
  const built = (await S.req('POST', '/v1/test/build_now', { token })).json.player
  assert.ok(!built.unbuilt.includes('lumber'))
  assert.equal(built.buildings.lumber.last_collect, S.clock.t)
})

test('튜토리얼 훈련: 1마리씩(2마리는 400), 1마리 tutorial_train_sec(5)초', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await S.db.query("update player_state set unbuilt = array_remove(unbuilt, 'barracks') where player_id = $1", [id])
  await setRes(id, { wood: 10000, stone: 10000, food: 10000 })
  assert.equal((await S.req('POST', '/v1/soldiers/train', { token, body: { building: 'barracks', count: 2 } })).status, 400)
  const r = await S.req('POST', '/v1/soldiers/train', { token, body: { building: 'barracks', count: 1 } })
  assert.equal(r.status, 200)
  assert.equal(r.json.training.finish, T0 + 5)
  // 첫 1마리만 5초: 받은 뒤(아직 훈련 미션이어도) 다음 훈련은 원래 시간(사용자 2026-10-13 "계속 5초로 뽑는 버그")
  S.clock.t = T0 + 6
  assert.equal((await S.req('POST', '/v1/soldiers/collect', { token, body: { building: 'barracks' } })).status, 200)
  const r2 = await S.req('POST', '/v1/soldiers/train', { token, body: { building: 'barracks', count: 1 } })
  assert.equal(r2.status, 200)
  assert.equal(r2.json.training.finish, T0 + 6 + 180 * 60)
})

test('튜토리얼 훈련 미션을 넘기면(튜토리얼은 진행 중) 원래 훈련 시간', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  const k = (await tutorialRows()).findIndex((x) => x.id === 'train')
  await S.db.query("update player_state set unbuilt = array_remove(unbuilt, 'barracks'), tut_step = $2 where player_id = $1", [id, k + 1])
  await setRes(id, { wood: 10000, stone: 10000, food: 10000 })
  const r = await S.req('POST', '/v1/soldiers/train', { token, body: { building: 'barracks', count: 1 } })
  assert.equal(r.status, 200)
  assert.equal((await player(token)).quest.tut_state, 'active')
  assert.equal(r.json.training.finish, T0 + 180 * 60)
})

test('튜토리얼 보상: 지금 단계만(재전송·건너뛰기는 409 stale), needs(지은 건물)를 본다, 보상은 표 그대로, 마지막 단계면 done', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  const rows = await tutorialRows()
  const before = await player(token)
  assert.equal(rows[0].id, 'stage_1_1') // 가이드 2026-10-23: 1번 = 첫 전투
  assert.equal((await claim(token, { type: 'tutorial', step: 0 })).json.error, 'not_done')
  await setStage(token, 2)
  let r = await claim(token, { type: 'tutorial', step: 0 })
  assert.equal(r.status, 200)
  const rw = R.parseReward(rows[0].reward as string)!
  assert.deepEqual(r.json.reward, rw)
  for (const k of R.BUILD_RES) assert.equal(r.json.player.res[k], before.res[k] + (rw[k] ?? 0))
  assert.equal(r.json.player.quest.tut_step, 1)
  assert.equal((await claim(token, { type: 'tutorial', step: 0 })).json.error, 'stale')
  assert.equal((await claim(token, { type: 'tutorial', step: 2 })).json.error, 'stale')
  const lb = rows.findIndex((x) => x.id === 'build_lumber')
  assert.equal(rows[lb].needs, 'build:lumber')
  await S.db.query('update player_state set tut_step = $2 where player_id = $1', [id, lb])
  assert.equal((await claim(token, { type: 'tutorial', step: lb })).json.error, 'not_done')
  await S.db.query("update player_state set unbuilt = array_remove(unbuilt, 'lumber') where player_id = $1", [id])
  assert.equal((await claim(token, { type: 'tutorial', step: lb })).status, 200)
  // 여러 건물(2026-10-23 채석장·농장): 둘 다 지어야. 2026-10-29부터 벌목장과 채석장·농장 사이에 사이 퀘스트가 낀다
  const qf = rows.findIndex((x) => x.id === 'build_quarry_farm')
  assert.ok(qf > lb + 1)
  assert.equal(rows[qf].needs, 'build:quarry+farm')
  await S.db.query('update player_state set tut_step = $2 where player_id = $1', [id, qf])
  await S.db.query("update player_state set unbuilt = array_remove(unbuilt, 'quarry') where player_id = $1", [id])
  assert.equal((await claim(token, { type: 'tutorial', step: qf })).json.error, 'not_done')
  await S.db.query("update player_state set unbuilt = array_remove(unbuilt, 'farm') where player_id = $1", [id])
  assert.equal((await claim(token, { type: 'tutorial', step: qf })).status, 200)
  // 열쇠 보상: 던전 단계 사이 퀘스트(골드 던전 2단계) 앞 처치 퀘스트가 골드 던전 열쇠 1개
  const k = rows.findIndex((x) => x.id === 'dungeon_gold_2') - 1
  assert.equal(rows[k].id, 'kill_60')
  assert.ok(rows[k].reward.split('|').includes('keys_gold:1'))
  await S.db.query('update player_state set tut_step = $2, unbuilt = $3 where player_id = $1', [id, k, []])
  const keys = (await player(token)).dungeons.gold.keys
  assert.equal((await claim(token, { type: 'tutorial', step: k })).json.error, 'not_done') // 처치 60마리를 서버가 아직 못 셌다
  await pump(token, 100)
  r = await claim(token, { type: 'tutorial', step: k })
  assert.equal(r.json.player.dungeons.gold.keys, keys + 1)
  // 던전 단계 퀘스트: 최고 단계가 그 단계 이상이어야(dungeon_<종류>_<단계>)
  assert.equal((await claim(token, { type: 'tutorial', step: k + 1 })).json.error, 'not_done')
  await S.db.query("update player_dungeons set best_level = 2 where player_id = $1 and type = 'gold'", [id])
  assert.equal((await claim(token, { type: 'tutorial', step: k + 1 })).status, 200)
  // 능력치 사이 퀘스트(치명타 확률 등 6종)는 그 능력치 레벨을 본다
  const cr = rows.findIndex((x) => x.id === 'crit_rate_1')
  await S.db.query('update player_state set tut_step = $2 where player_id = $1', [id, cr])
  assert.equal((await claim(token, { type: 'tutorial', step: cr })).json.error, 'not_done')
  // 자원 보상: 골드 던전 2단계 퀘스트가 다음 미션(농장 Lv 2) 자원을 준다
  const t = rows.findIndex((x) => x.id === 'farm_2') - 1
  assert.equal(rows[t].id, 'dungeon_gold_2')
  const rr = R.parseReward(rows[t].reward as string)!
  assert.ok((rr.wood ?? 0) > 0 || (rr.stone ?? 0) > 0 || (rr.food ?? 0) > 0)
  assert.ok(rows[rows.findIndex((x) => x.id === 'build_quarry_farm')].reward.split('|').includes('tickets:10')) // 규칙 미션 뒤로 아무것도 안 쓰면 모집권
  await S.db.query('update player_state set tut_step = $2 where player_id = $1', [id, t])
  const res0 = (await player(token)).res
  const kr = (await claim(token, { type: 'tutorial', step: t })).json.player.res
  assert.deepEqual(R.BUILD_RES.map((x) => kr[x] - res0[x]), R.BUILD_RES.map((x) => rr[x] ?? 0))
  // 사이 퀘스트(2026-10-29 저녁 — 처치를 줄이고 대신 넣은 것): 영웅 모집 N회(누적 모집), 던전 클리어(누적 승리), 건물 레벨업(needs)
  const g1 = rows.findIndex((x) => x.id === 'gacha_10_1')
  const dw = rows.findIndex((x) => x.id === 'dwin_gold_1')
  const q2 = rows.findIndex((x) => x.id === 'quarry_2')
  assert.ok(rows[g1 - 1].reward.split('|').includes('tickets:10') && rows[dw - 1].reward.split('|').includes('keys_gold:1'))
  assert.equal(rows[q2].needs, 'level:quarry:2')
  const p2 = await S.login()
  for (const [step, ev, n] of [[g1, 'gacha', 10], [dw, 'dungeon_win', 1]] as const) {
    await S.db.query('update player_state set tut_step = $2 where player_id = $1', [p2.id, step])
    assert.equal((await claim(p2.token, { type: 'tutorial', step })).json.error, 'not_done')
    await S.req('POST', '/v1/test/events', { token: p2.token, body: { events: { [ev]: n } } })
    assert.equal((await claim(p2.token, { type: 'tutorial', step })).status, 200)
  }
  // 1-15 · 거래소 · 마지막(파티)
  const s15 = rows.findIndex((x) => x.id === 'stage_1_15')
  const ex = rows.findIndex((x) => x.id === 'exchange_look')
  assert.equal(rows[rows.length - 1].id, 'party_clear') // 가이드 2026-10-15: 마지막 = 파티 던전 첫 클리어
  assert.ok(s15 < ex && ex < rows.length - 1)
  await S.db.query('update player_state set tut_step = $2, keep_level = 9, gate_level = 9 where player_id = $1', [id, s15])
  assert.equal((await claim(token, { type: 'tutorial', step: s15 })).json.error, 'not_done') // 1-15를 아직 안 깼다
  await setStage(token, 16)
  r = await claim(token, { type: 'tutorial', step: s15 })
  assert.equal(r.status, 200)
  assert.equal(r.json.player.quest.tut_state, 'active')
  await S.db.query('update player_state set tut_step = $2 where player_id = $1', [id, ex])
  r = await claim(token, { type: 'tutorial', step: ex }) // 거래소 둘러보기(앱이 센다)
  assert.equal(r.status, 200)
  assert.equal(r.json.player.quest.tut_state, 'active')
  await S.db.query('update player_state set tut_step = $2 where player_id = $1', [id, rows.length - 1])
  assert.equal((await claim(token, { type: 'tutorial', step: rows.length - 1 })).json.error, 'not_done') // 파티 던전을 아직 못 이겼다
  await S.db.query("insert into party_stats (player_id, quest, best, day, clears) values ($1, 'spider', 0, 0, 0)", [id]) // 지기만 했다
  assert.equal((await claim(token, { type: 'tutorial', step: rows.length - 1 })).json.error, 'not_done')
  await S.db.query("insert into party_stats (player_id, quest, best, day, clears) values ($1, 'lich', 1, 0, 1)", [id])
  r = await claim(token, { type: 'tutorial', step: rows.length - 1 })
  assert.equal(r.status, 200)
  assert.deepEqual(r.json.reward, { diamonds: 50 })
  assert.equal(r.json.player.quest.tut_state, 'done')
  assert.equal((await claim(token, { type: 'tutorial', step: rows.length })).json.error, 'no_tutorial')
  const logs = await S.db.query("select detail from economy_log where player_id = $1 and kind = 'quest' order by id", [id])
  assert.equal(logs.length, 9) // 1-1·벌목장·채석장+농장·열쇠·골드 던전 2단계·자원·1-15·거래소·파티
})

test('반복 퀘스트: 튜토리얼 중엔 409, 번호대로, quest_repeat_min_sec 간격, 보상 = reward × (1 + 바퀴) + fixed', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  assert.equal((await claim(token, { type: 'repeat', n: 0 })).json.error, 'tutorial_running')
  await S.db.query("update player_state set tut_state = 'skipped' where player_id = $1", [id])
  // 순서(메이플스토리 키우기식 2026-10-29): 스테이지 돌파 → 처치 → 모집 → 던전 → 영웅 → 성장 → 건물 → 수집 → 판매
  assert.deepEqual((await player(token)).quest.rep, { have: 2, need: 2, from: null }) // 기준 라운드가 없으면(가이드를 건너뛴 성주) 이미 끝난 것으로
  let r = await claim(token, { type: 'repeat', n: 0 })
  assert.equal(r.status, 200)
  assert.deepEqual([r.json.reward, r.json.player.diamonds], [{ diamonds: 20 }, 20])
  assert.equal(r.json.player.quest.rep_n, 1)
  assert.equal((await claim(token, { type: 'repeat', n: 0 })).json.error, 'stale')
  assert.equal((await claim(token, { type: 'repeat', n: 1 })).json.error, 'too_soon')
  S.clock.t = T0 + 30
  const gold0 = (await player(token)).gold
  assert.deepEqual((await player(token)).quest.rep, { have: 0, need: 100, from: null }) // 앱 카드가 이 진행을 보인다
  assert.equal((await claim(token, { type: 'repeat', n: 1 })).json.error, 'not_done') // 처치 100마리를 서버가 아직 못 셌다
  await pump(token)
  r = await claim(token, { type: 'repeat', n: 1 })
  assert.equal(r.status, 200)
  assert.deepEqual(r.json.reward, { gold: 3000 })
  assert.equal(r.json.player.gold, gold0 + 3000)
  assert.equal(r.json.player.quest.rep_n, 2)
  S.clock.t = T0 + 60
  assert.equal((await claim(token, { type: 'repeat', n: 2 })).json.error, 'not_done') // 받은 뒤부터 다시 센다(모집 10회)
  await pump(token)
  assert.deepEqual((await claim(token, { type: 'repeat', n: 2 })).json.reward, { tickets: 1 })
  // 두 번째 바퀴: 스테이지는 받을 때 라운드 + 2, reward × 2, fixed 그대로
  await S.db.query('update player_state set rep_n = 6 where player_id = $1', [id])
  S.clock.t = T0 + 90
  assert.deepEqual((await player(token)).quest.rep, { have: 0, need: 2, from: 1 }) // 앱: 「스테이지 1-2 클리어」(받을 때 라운드 1 → 1-2까지 깨면 3)
  assert.equal((await claim(token, { type: 'repeat', n: 6 })).json.error, 'not_done')
  await setStage(token, 3)
  assert.deepEqual((await player(token)).quest.rep, { have: 2, need: 2, from: 1 })
  assert.deepEqual((await claim(token, { type: 'repeat', n: 6 })).json.reward, { diamonds: 20 })
  S.clock.t = T0 + 120
  await pump(token)
  assert.deepEqual((await claim(token, { type: 'repeat', n: 7 })).json.reward, { gold: 6000 })
  assert.equal((await claim(token, { type: 'nope', n: 0 })).status, 400)
})

test('다이아 모집권 모집: 1장 = 1회, 모자라면 409 not_enough_tickets, 다이아·천장은 다이아 모집과 같이 센다', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  assert.equal((await S.req('POST', '/v1/gacha', { token, body: { count: 10, currency: 'ticket' } })).json.error, 'not_enough_tickets')
  await S.db.query('update player_state set dia_tickets = 12 where player_id = $1', [id])
  const r = await S.req('POST', '/v1/gacha', { token, body: { count: 10, currency: 'ticket' } })
  assert.equal(r.status, 200)
  assert.equal(r.json.results.length, 10)
  assert.equal(r.json.player.dia_tickets, 2)
  assert.equal(r.json.player.diamonds, 0)
})

test('튜토리얼을 끈 설정(tutorial_new_players 0): 새 플레이어는 skipped·공터 없음', async () => {
  await S.db.query("update game_config set value = '0' where key = 'tutorial_new_players'")
  try {
    const { token } = await S.login()
    const p = await player(token)
    assert.deepEqual([p.quest.tut_state, p.unbuilt], ['skipped', LOTS]) // 성채 레벨로 여는 건물·n번째 채만 공터
  } finally {
    await S.db.query("update game_config set value = '1' where key = 'tutorial_new_players'")
  }
})

test('퀘스트 표: 튜토리얼 행·반복 행, 보상 키 형식, needs 형식', async () => {
  const t = await readTables()
  assert.ok(t.quests.some((r) => r.type === 'tutorial') && t.quests.some((r) => r.type === 'repeat'))
  for (const r of t.quests) {
    assert.ok(R.parseReward(r.reward as string) !== null && R.parseReward(r.fixed as string) !== null, String(r.id))
    assert.notEqual(R.parseNeeds(r.needs as string), null, String(r.id))
  }
  assert.equal(R.parseReward('gold:1|gold:2'), null)
  assert.equal(R.parseReward('mana:1'), null)
  assert.deepEqual(R.parseNeeds('level:keep:2'), { kind: 'level', buildings: ['keep'], level: 2 })
  assert.deepEqual(R.parseNeeds('build:quarry+farm'), { kind: 'build', buildings: ['quarry', 'farm'], level: 1 })
  assert.equal(R.parseNeeds('build:quarry+'), null)
  assert.equal(R.parseNeeds('level:keep:0'), null)
})

test('마이그레이션 019: 이미 있던 플레이어도 튜토리얼 1단계부터(active·공터는 성채·성문 밖 전부, 모집권 0)', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'castle-mig-'))
  for (const f of readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql') && f < '019')) cpSync(join(MIGRATIONS_DIR, f), join(dir, f))
  const d = await openDb({})
  try {
    await migrate(d, dir)
    await seed(d).catch(() => undefined) // 018 시점 표(퀘스트 표 없음)는 실패해도 된다 — 건물·자원 표만 있으면 된다
    await d.query("insert into building_defs (id, name, max_level, wood, stone, food, base_sec) values ('keep', 'k', 30, 1, 1, 1, 1), ('gate', 'g', 30, 1, 1, 1, 1), ('lab', 'l', 30, 1, 1, 1, 1) on conflict do nothing")
    await d.query("insert into resources (id, name, building, per_min, price) values ('wood', 'w', 'lumber', 1, 1) on conflict do nothing")
    const [p] = await d.query("insert into players (device_id) values ('mig-019-device-0001') returning id")
    await d.query('insert into player_state (player_id) values ($1)', [p.id])
    const applied = await migrate(d)
    assert.ok(applied[0] === '019_quests.sql')
    const [s] = await d.query('select tut_state, tut_step, rep_n, dia_tickets, unbuilt from player_state where player_id = $1', [p.id])
    assert.equal(s.tut_state, 'active')
    assert.equal(s.tut_step, 0)
    assert.equal(s.dia_tickets, 0)
    assert.ok(s.unbuilt.includes('lab') && s.unbuilt.includes('lumber') && !s.unbuilt.includes('keep') && !s.unbuilt.includes('gate'))
  } finally {
    await d.close()
    rmSync(dir, { recursive: true, force: true })
  }
})

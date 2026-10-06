// 튜토리얼·반복 퀘스트(온라인): 새 플레이어 공터·튜토리얼 상태, 공터 짓기·수집·훈련·연구 거부, 튜토리얼 훈련 5초, 보상 받기(진행 번호·needs·재전송),
// 반복 퀘스트(바퀴 보상·간격·튜토리얼 중 거부), 다이아 모집권 모집, 기존 플레이어는 skipped, 시드 검증.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as R from '../src/rules.ts'
import { readTables } from '../src/seed.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup({ tutorial: true })
})
after(async () => {
  await S.close()
})

const player = async (token: string) => (await S.req('GET', '/v1/player', { token })).json.player
const claim = (token: string, body: unknown) => S.req('POST', '/v1/quest/claim', { token, body })
const setRes = (id: string, r: Record<string, number>) => Promise.all(Object.entries(r).map(([res, n]) =>
  S.db.query('update player_resources set amount = $3 where player_id = $1 and res = $2', [id, res, n])))
const tutorialRows = async () => (await readTables()).quests.filter((r) => r.type === 'tutorial')

test('새 플레이어: 튜토리얼 active, 성채·성문 밖 건물은 공터(레벨 1 그대로), 모집권 0', async () => {
  S.clock.t = T0
  const { token } = await S.login()
  const p = await player(token)
  assert.deepEqual(p.quest, { tut_state: 'active', tut_step: 0, rep_n: 0 })
  assert.equal(p.dia_tickets, 0)
  assert.deepEqual(p.unbuilt, ['archery', 'barracks', 'farm', 'houses', 'lab', 'lumber', 'quarry', 'stable', 'tavern'])
  assert.equal(p.buildings.lumber.level, 1)
})

test('공터: 수집·훈련·연구는 409, 짓기는 선행·성채 상한 없이 Lv 1 비용·시간, 다 지으면 공터에서 빠지고 레벨은 1, 생산은 다 지은 시각부터', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  assert.equal((await S.req('POST', '/v1/collect', { token, body: { building: 'lumber' } })).json.error, 'unbuilt')
  assert.equal((await S.req('POST', '/v1/soldiers/train', { token, body: { building: 'barracks', count: 1 } })).json.error, 'unbuilt')
  assert.equal((await S.req('POST', '/v1/research/start', { token, body: { id: 'wood_tech' } })).json.error, 'lab_unbuilt')
  await setRes(id, { wood: 1000, stone: 1000, food: 1000 })
  const g = (await S.req('GET', '/v1/gamedata')).json
  const def = g.buildings.find((b: any) => b.id === 'stable') // 선행(막사·궁병)이 있어도 공터는 그냥 짓는다
  const r = await S.req('POST', '/v1/building/upgrade', { token, body: { building: 'stable' } })
  assert.equal(r.status, 200)
  const cost = R.buildCost(def, 1)
  assert.deepEqual(r.json.player.res, { wood: 1000 - cost.wood, stone: 1000 - cost.stone, food: 1000 - cost.food })
  assert.equal(r.json.build.finish, T0 + R.buildSec(def, 1))
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
  await setRes(id, { wood: 1000, stone: 1000, food: 1000 })
  assert.equal((await S.req('POST', '/v1/soldiers/train', { token, body: { building: 'barracks', count: 2 } })).status, 400)
  const r = await S.req('POST', '/v1/soldiers/train', { token, body: { building: 'barracks', count: 1 } })
  assert.equal(r.status, 200)
  assert.equal(r.json.training.finish, T0 + 5)
})

test('튜토리얼 보상: 지금 단계만(재전송·건너뛰기는 409 stale), needs(지은 건물)를 본다, 보상은 표 그대로, 마지막 단계면 done', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  const rows = await tutorialRows()
  const before = await player(token)
  let r = await claim(token, { type: 'tutorial', step: 0 })
  assert.equal(r.status, 200)
  const rw = R.parseReward(rows[0].reward as string)!
  assert.deepEqual(r.json.reward, rw)
  for (const k of R.BUILD_RES) assert.equal(r.json.player.res[k], before.res[k] + (rw[k] ?? 0))
  assert.equal(r.json.player.quest.tut_step, 1)
  assert.equal((await claim(token, { type: 'tutorial', step: 0 })).json.error, 'stale')
  assert.equal((await claim(token, { type: 'tutorial', step: 2 })).json.error, 'stale')
  assert.equal(rows[1].needs, 'build:lumber')
  assert.equal((await claim(token, { type: 'tutorial', step: 1 })).json.error, 'not_done')
  await S.db.query("update player_state set unbuilt = array_remove(unbuilt, 'lumber') where player_id = $1", [id])
  assert.equal((await claim(token, { type: 'tutorial', step: 1 })).status, 200)
  // 열쇠 보상(kill_100 → 골드 던전 열쇠 2)
  const k = rows.findIndex((x) => x.reward === 'keys_gold:2')
  await S.db.query('update player_state set tut_step = $2, unbuilt = $3 where player_id = $1', [id, k, []])
  const keys = (await player(token)).dungeons.gold.keys
  r = await claim(token, { type: 'tutorial', step: k })
  assert.equal(r.json.player.dungeons.gold.keys, keys + 2)
  // 모집권 보상
  const t = rows.findIndex((x, i) => i > k && x.reward === 'tickets:10' && !x.needs)
  await S.db.query('update player_state set tut_step = $2 where player_id = $1', [id, t])
  assert.equal((await claim(token, { type: 'tutorial', step: t })).json.player.dia_tickets, 10)
  // 마지막
  await S.db.query('update player_state set tut_step = $2, keep_level = 9, gate_level = 9 where player_id = $1', [id, rows.length - 1])
  r = await claim(token, { type: 'tutorial', step: rows.length - 1 })
  assert.equal(r.status, 200)
  assert.equal(r.json.player.quest.tut_state, 'done')
  assert.equal((await claim(token, { type: 'tutorial', step: rows.length })).json.error, 'no_tutorial')
  const logs = await S.db.query("select detail from economy_log where player_id = $1 and kind = 'quest' order by id", [id])
  assert.equal(logs.length, 5)
})

test('반복 퀘스트: 튜토리얼 중엔 409, 번호대로, quest_repeat_min_sec 간격, 보상 = reward × (1 + 바퀴) + fixed', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  assert.equal((await claim(token, { type: 'repeat', n: 0 })).json.error, 'tutorial_running')
  await S.db.query("update player_state set tut_state = 'skipped' where player_id = $1", [id])
  const gold0 = (await player(token)).gold
  let r = await claim(token, { type: 'repeat', n: 0 })
  assert.equal(r.status, 200)
  assert.deepEqual(r.json.reward, { gold: 3000 })
  assert.equal(r.json.player.gold, gold0 + 3000)
  assert.equal(r.json.player.quest.rep_n, 1)
  assert.equal((await claim(token, { type: 'repeat', n: 0 })).json.error, 'stale')
  assert.equal((await claim(token, { type: 'repeat', n: 1 })).json.error, 'too_soon')
  S.clock.t = T0 + 30
  assert.deepEqual((await claim(token, { type: 'repeat', n: 1 })).json.reward, { gold: 2000 })
  S.clock.t = T0 + 60
  r = await claim(token, { type: 'repeat', n: 2 })
  assert.deepEqual([r.json.reward, r.json.player.diamonds], [{ diamonds: 20 }, 20])
  // 두 번째 바퀴: reward × 2, fixed 그대로
  await S.db.query('update player_state set rep_n = 9 where player_id = $1', [id])
  S.clock.t = T0 + 90
  assert.deepEqual((await claim(token, { type: 'repeat', n: 9 })).json.reward, { gold: 6000 })
  await S.db.query('update player_state set rep_n = 15 where player_id = $1', [id])
  S.clock.t = T0 + 120
  assert.deepEqual((await claim(token, { type: 'repeat', n: 15 })).json.reward, { tickets: 1 })
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
    assert.deepEqual([p.quest.tut_state, p.unbuilt], ['skipped', []])
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
  assert.deepEqual(R.parseNeeds('level:keep:2'), { kind: 'level', building: 'keep', level: 2 })
  assert.equal(R.parseNeeds('level:keep:0'), null)
})

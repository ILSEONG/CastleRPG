// 무료 즉시 완료(사용자 2026-10-06): 남은 시간이 free_finish_sec초(300) 이하인 건설·훈련·연구는 공짜로 바로 끝낸다(시계 차 10초 여유).
// 더 길면 409 too_long(건설)·not_ready(훈련)·다이아 비용(연구) 그대로.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as R from '../src/rules.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup()
})
after(() => S.close())

const player = async (token: string) => (await S.req('GET', '/v1/player', { token })).json.player
const logs = async (id: string, kind: string) => (await S.db.query('select detail from economy_log where player_id = $1 and kind = $2 order by id', [id, kind])).map((r) => r.detail)
const setRes = (id: string, r: Record<string, number>) =>
  Promise.all(Object.entries(r).map(([res, n]) => S.db.query('update player_resources set amount = $3 where player_id = $1 and res = $2', [id, res, n])))
const RICH = { wood: 1_000_000, stone: 1_000_000, food: 1_000_000 }
async function fresh() {
  S.clock.t = T0
  const l = await S.login()
  await setRes(l.id, RICH)
  return l
}

test('설정: free_finish_sec 300(없으면 300), 여유 10초', () => {
  assert.equal(R.freeFinishSec({ free_finish_sec: '300' }), 300)
  assert.equal(R.freeFinishSec({}), 300)
  assert.equal(R.freeFinishOk({}, T0 + 310, T0), true)
  assert.equal(R.freeFinishOk({}, T0 + 311, T0), false)
})

test('건설: 5분 넘게 남으면 409 too_long, 5분 이하면 바로 레벨 +1·일꾼 비움(build_free·build_done 로그), 짓는 중 아니면 409 no_build', async () => {
  const { token, id } = await fresh()
  let r = await S.req('POST', '/v1/building/finish', { token, body: {} })
  assert.deepEqual([r.status, r.json.error], [409, 'no_build'])
  assert.equal((await S.req('POST', '/v1/building/upgrade', { token, body: { building: 'keep' } })).status, 200)
  await S.db.query('update player_state set build_finish = to_timestamp($2::float8) where player_id = $1', [id, T0 + 1000])
  r = await S.req('POST', '/v1/building/finish', { token, body: {} })
  assert.deepEqual([r.status, r.json.error], [409, 'too_long'])
  S.clock.t = T0 + 700 // 남은 300초
  r = await S.req('POST', '/v1/building/finish', { token, body: {} })
  assert.equal(r.status, 200)
  assert.deepEqual([r.json.player.build, r.json.player.buildings.keep.level], [null, 2])
  assert.deepEqual(await logs(id, 'build_free'), [{ building: 'keep', finish: T0 + 1000, left: 300 }])
  assert.equal((await logs(id, 'build_done')).length, 1)
  assert.equal((await player(token)).buildings.keep.level, 2) // 다시 읽어도 한 번만 올랐다
})

test('훈련: collect {free: true}는 5분 이하 남았을 때 바로 받는다. free 없이·더 길면 409 not_ready', async () => {
  const { token, id } = await fresh()
  let r = await S.req('POST', '/v1/soldiers/train', { token, body: { building: 'barracks', count: 1 } })
  assert.equal(r.status, 200)
  const finish = r.json.training.finish
  assert.ok(finish - T0 > 300)
  r = await S.req('POST', '/v1/soldiers/collect', { token, body: { building: 'barracks', free: true } })
  assert.deepEqual([r.status, r.json.error], [409, 'not_ready'])
  S.clock.t = finish - 200
  r = await S.req('POST', '/v1/soldiers/collect', { token, body: { building: 'barracks' } })
  assert.deepEqual([r.status, r.json.error], [409, 'not_ready'])
  r = await S.req('POST', '/v1/soldiers/collect', { token, body: { building: 'barracks', free: true } })
  assert.equal(r.status, 200)
  assert.deepEqual([r.json.collected, r.json.player.soldiers['infantry:1']], [{ type: r.json.collected.type, count: 1, tier: 1 }, 1])
  assert.equal(r.json.player.training.barracks ?? null, null)
  assert.equal((await logs(id, 'train_collect'))[0].free, 200)
})

test('연구: 5분 이하 남으면 /v1/research/finish가 0 다이아로 끝낸다(더 길면 다이아 비용)', async () => {
  const { token, id } = await fresh()
  await S.db.query('update player_state set gold_tenths = 100000000, diamonds = 0 where player_id = $1', [id])
  await S.db.query("insert into player_research (player_id, id, level) values ($1, 'wood_tech', 9)", [id])
  let r = await S.req('POST', '/v1/research/start', { token, body: { id: 'wood_tech' } })
  assert.equal(r.status, 200)
  const finish = r.json.player.research.current.finish
  r = await S.req('POST', '/v1/research/finish', { token })
  assert.deepEqual([r.status, r.json.error], [409, 'not_enough_diamonds'])
  S.clock.t = finish - 299
  r = await S.req('POST', '/v1/research/finish', { token })
  assert.deepEqual([r.status, r.json.diamonds_spent, r.json.player.diamonds, r.json.player.research.levels.wood_tech, r.json.player.research.current], [200, 0, 0, 10, null])
})

// 방치 주머니: 보상(출석·미션)으로 받아 보관, POST /v1/pouch/open이 지금의 방치 수입 × 주머니 시간을 준다(골드 = 오프라인 처치 골드 식,
// 자원 = 자원 건물 생산 식), 보유보다 많이 열면 not_enough, 모르는 주머니 404, 마이그레이션 026.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as P from '../src/pouches.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup()
})
after(async () => {
  await S.close()
})

const DAY = 86400
const open = (token: string, id: string, count = 1) => S.req('POST', '/v1/pouch/open', { token, body: { id, count } })

test('pouches.ts: 12종, 보상 키 → 주머니, 더하기·빼기', () => {
  assert.equal(P.IDS.length, 12)
  assert.deepEqual(P.parse('gold_360'), { kind: 'gold', min: 360 })
  assert.equal(P.parse('gold_45'), null)
  assert.deepEqual(P.fromReward({ gold: 5, pouch_gold_10: 1, pouch_res_60: 2, pouch_nope: 3 }), { gold_10: 1, res_60: 2 })
  assert.deepEqual(P.add({ gold_10: 1 }, { gold_10: -1, res_30: 2 }), { res_30: 2 })
  assert.deepEqual(P.normalize({ gold_10: 2, res_30: 0, x: 4, gold_60: 1.5 }), { gold_10: 2 })
})

test('출석 1일차 골드 주머니(30분) → 열면 스테이지 1 방치 골드 30분(108,000 tenths), 다시 열면 not_enough', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  let r = await S.req('POST', '/v1/attendance/claim', { token, body: { day: 1 } })
  assert.deepEqual(r.json.player.pouches, { gold_30: 1 })
  const before = r.json.player.gold_tenths
  r = await open(token, 'gold_30')
  assert.equal(r.status, 200)
  assert.deepEqual(r.json.opened, { id: 'gold_30', count: 1, gold_tenths: 108_000, res: {} })
  assert.equal(r.json.player.gold_tenths, before + 108_000)
  assert.deepEqual(r.json.player.pouches, {})
  assert.equal((await open(token, 'gold_30')).json.error, 'not_enough')
  assert.equal((await open(token, 'gold_15')).status, 404)
  const logs = await S.db.query("select detail from economy_log where player_id = $1 and kind = 'pouch'", [id])
  assert.equal(logs.length, 1)
})

test('출석 3일차 자원 주머니(30분) → 목재·석재·식량 건물 30분 생산(레벨 1), 여러 개 한 번에', async () => {
  S.clock.t = T0
  const { token } = await S.login()
  for (let d = 1; d <= 3; d++) {
    S.clock.t = T0 + (d - 1) * DAY
    assert.equal((await S.req('POST', '/v1/attendance/claim', { token, body: { day: d } })).status, 200)
  }
  const p = (await S.req('GET', '/v1/player', { token })).json.player
  assert.deepEqual(p.pouches, { gold_30: 1, res_30: 1 })
  const r = await open(token, 'res_30')
  assert.deepEqual(r.json.opened.res, { wood: 300, stone: 150, food: 300 })
  assert.equal(r.json.player.res.wood, p.res.wood + 300)
  assert.equal((await open(token, 'gold_30', 2)).json.error, 'not_enough')
})

test('미션 보상의 주머니: 일일 처치 미션 → 골드 주머니(10분)', async () => {
  S.clock.t = T0
  const { token } = await S.login()
  const r = await S.req('POST', '/v1/mission/claim', { token, body: { id: 'd_kill' } })
  assert.equal(r.status, 200)
  assert.deepEqual(r.json.player.pouches, { gold_10: 1 })
  assert.equal((await open(token, 'gold_10')).json.opened.gold_tenths, 36_000)
})

test('받을 것이 없으면(튜토리얼: 자원 건물이 공터) 409 empty, 주머니는 남는다', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await S.db.query(`update player_state set pouches = '{"res_60": 1}'::jsonb, unbuilt = array['lumber', 'quarry', 'farm'] where player_id = $1`, [id])
  const r = await open(token, 'res_60')
  assert.equal(r.json.error, 'empty')
  assert.deepEqual((await S.req('GET', '/v1/player', { token })).json.player.pouches, { res_60: 1 })
})

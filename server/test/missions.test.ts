// 미션(일일·주간·반복): 표·진행 읽기, 일일·주간 한 번씩, daily_count·daily_bonus 서버 판정, 날·주 리셋, 반복 미션 순서·간격, 보상 반영.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as M from '../src/missions.ts'
import * as R from '../src/rules.ts'
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

const claim = (token: string, body: unknown) => S.req('POST', '/v1/mission/claim', { token, body })
const H = 15 // daily_reset_utc_hour
// T0가 속한 주의 월요일 리셋 + 1시간(그 주 안에서 날짜를 옮겨 다닌다)
const monday = R.resetAt(M.weekStart(M.weekOf(R.resetDay(T0, H))), H) + 3600

test('주 번호: 월요일 00:00 KST에 바뀐다', () => {
  const mon = R.resetDay(Date.UTC(2026, 9, 4, 15, 0, 0) / 1000, H) // 2026-10-05(월) 00:00 KST
  assert.equal(M.weekOf(mon), M.weekOf(mon - 1) + 1)
  assert.equal(M.weekOf(mon + 6), M.weekOf(mon))
  assert.equal(M.weekStart(M.weekOf(mon)), mon)
})

test('GET /v1/missions: 표와 빈 진행, 플레이어 응답에도 진행', async () => {
  S.clock.t = monday
  const { token } = await S.login()
  const r = await S.req('GET', '/v1/missions', { token })
  assert.equal(r.status, 200)
  assert.equal(r.json.defs.length, M.DEFS.length)
  const m = r.json.missions
  assert.deepEqual([m.d, m.w, m.wd, m.r], [[], [], 0, {}])
  assert.equal(m.next_day, R.resetAt(m.day + 1, H))
  assert.equal(m.next_week, R.resetAt(M.weekStart(m.week + 1), H))
  const p = (await S.req('GET', '/v1/player', { token })).json.player
  assert.deepEqual(p.missions.d, [])
})

test('일일 미션: 보상 반영, 하루 한 번(409 claimed), 다음 날 다시', async () => {
  S.clock.t = monday
  const { token } = await S.login()
  const before = (await S.req('GET', '/v1/player', { token })).json.player
  const r = await claim(token, { id: 'd_kill' })
  assert.equal(r.status, 200)
  assert.deepEqual(r.json.reward, { gold: 3000, pouch_gold_10: 1 })
  assert.deepEqual(r.json.player.pouches, { gold_10: 1 })
  assert.equal(r.json.player.gold, before.gold + 3000)
  assert.deepEqual(r.json.player.missions.d, ['d_kill'])
  assert.equal((await claim(token, { id: 'd_kill' })).json.error, 'claimed')
  const res = await claim(token, { id: 'd_collect' })
  assert.equal(res.json.player.res.wood, before.res.wood + 300)
  S.clock.t = monday + 86400
  const next = await claim(token, { id: 'd_kill' })
  assert.equal(next.status, 200)
  assert.deepEqual(next.json.player.missions.d, ['d_kill'])
})

test('일일 보너스: 다른 일일 미션 6개를 받아야(409 not_done), 받으면 다이아·모집권 + 주간 보너스 날 수 +1', async () => {
  S.clock.t = monday
  const { token } = await S.login()
  assert.equal((await claim(token, { id: 'd_all' })).json.error, 'not_done')
  for (const id of ['d_kill', 'd_collect', 'd_sell', 'd_hero', 'd_growth']) assert.equal((await claim(token, { id })).status, 200)
  assert.equal((await claim(token, { id: 'd_all' })).json.error, 'not_done')
  const p0 = (await claim(token, { id: 'd_gacha' })).json.player
  const r = await claim(token, { id: 'd_all' })
  assert.equal(r.status, 200)
  assert.equal(r.json.player.diamonds, p0.diamonds + 100)
  assert.equal(r.json.player.dia_tickets, p0.dia_tickets + 1)
  assert.equal(r.json.player.missions.wd, 1)
})

test('주간 보너스: 일일 보너스 5일, 주가 바뀌면 주간 기록·날 수가 지워진다', async () => {
  S.clock.t = monday
  const { token } = await S.login()
  const daily = ['d_kill', 'd_collect', 'd_sell', 'd_hero', 'd_growth', 'd_gacha', 'd_all']
  for (let day = 0; day < 5; day++) {
    S.clock.t = monday + day * 86400
    if (day === 4) assert.equal((await claim(token, { id: 'w_bonus' })).json.error, 'not_done')
    for (const id of daily) assert.equal((await claim(token, { id })).status, 200, `${id} on day ${day}`)
  }
  const r = await claim(token, { id: 'w_bonus' })
  assert.equal(r.status, 200)
  assert.equal((await claim(token, { id: 'w_bonus' })).json.error, 'claimed')
  assert.equal((await claim(token, { id: 'w_kill' })).status, 200)
  S.clock.t = monday + 7 * 86400
  const p = (await S.req('GET', '/v1/player', { token })).json.player
  assert.deepEqual([p.missions.w, p.missions.wd], [[], 0])
  assert.equal((await claim(token, { id: 'w_kill' })).status, 200)
})

test('반복 미션: n = 받은 횟수(409 stale), 다른 반복 미션도 곧바로 받는다(간격 없음), 횟수는 리셋되지 않는다', async () => {
  S.clock.t = monday
  const { token } = await S.login()
  assert.equal((await claim(token, { id: 'r_kill' })).status, 400)
  assert.equal((await claim(token, { id: 'r_kill', n: 1 })).json.error, 'stale')
  const r = await claim(token, { id: 'r_kill', n: 0 })
  assert.equal(r.status, 200)
  assert.deepEqual(r.json.player.missions.r, { r_kill: 1 })
  assert.equal((await claim(token, { id: 'r_kill', n: 0 })).json.error, 'stale')
  assert.equal((await claim(token, { id: 'r_stage', n: 0 })).status, 200)
  assert.equal((await claim(token, { id: 'r_kill', n: 1 })).status, 200)
  S.clock.t += 8 * 86400
  const p = (await S.req('GET', '/v1/player', { token })).json.player
  assert.deepEqual(p.missions.r, { r_kill: 2, r_stage: 1 })
  assert.equal(M.targetOf(M.def('r_kill')!, 2), 2000)
})

test('모르는 미션 404, 로그인 없이 401', async () => {
  const { token } = await S.login()
  assert.equal((await claim(token, { id: 'nope' })).status, 404)
  assert.equal((await S.req('POST', '/v1/mission/claim', { body: { id: 'd_kill' } })).status, 401)
})

test('표: id 유일, 보상 키는 퀘스트 보상 키, 목표 ≥ 1, 반복 미션만 step', () => {
  assert.equal(new Set(M.DEFS.map((d) => d.id)).size, M.DEFS.length)
  for (const d of M.DEFS) {
    assert.ok(Object.keys(d.reward).length > 0 && Object.keys(d.reward).every((k) => R.QUEST_REWARD_KEYS.includes(k) || Object.keys(P.fromReward({ [k]: 1 })).length === 1), d.id)
    assert.ok(d.target >= 1, d.id)
    assert.equal(d.step !== undefined, d.type === 'repeat', d.id)
  }
  const others = M.DEFS.filter((d) => d.type === 'daily' && d.kind !== 'daily_count').length
  assert.ok(M.def('d_all')!.target <= others)
})

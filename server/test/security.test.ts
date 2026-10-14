// 보안 점검(2026-10-14): 계정 만들기 도배 상한, 쿠폰 코드 맞히기 상한, PVP·던전 승리 힘 타당성.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as P from '../src/pvp.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup()
  S.clock.t = T0
})
after(() => S.close())

const dev = (n: number) => `sec-device-${String(n).padStart(8, '0')}`

test('새 게스트 계정은 한 IP에서 10분에 20개까지, 이미 있는 계정 로그인·다른 IP는 그대로', async () => {
  const guest = (d: string, ip: string) => S.req('POST', '/v1/auth/guest', { body: { device_id: d }, headers: { 'cf-connecting-ip': ip } })
  for (let i = 0; i < 20; i++) assert.equal((await guest(dev(i), '203.0.113.7')).status, 200)
  const r = await guest(dev(20), '203.0.113.7')
  assert.deepEqual([r.status, r.json.error], [429, 'too_many_requests'])
  assert.equal((await guest(dev(3), '203.0.113.7')).status, 200, 'existing account still logs in')
  assert.equal((await guest(dev(21), '203.0.113.8')).status, 200, 'another network')
  assert.equal((await S.req('POST', '/v1/auth/guest', { body: { device_id: dev(22) } })).status, 200, 'no trusted IP header → no IP limit')
  S.clock.t += 601
  assert.equal((await guest(dev(23), '203.0.113.7')).status, 200, 'next window')
  S.clock.t = T0
})

test('쿠폰: 틀린 코드 10번이면 10분 동안 429 too_many_attempts', async () => {
  const p = await S.login()
  for (let i = 0; i < 10; i++) assert.equal((await S.req('POST', '/v1/coupon', { token: p.token, body: { code: `NOPE${i}` } })).json.error, 'unknown_coupon')
  assert.equal((await S.req('POST', '/v1/coupon', { token: p.token, body: { code: 'NOPE99' } })).status, 429)
  S.clock.t += 601
  assert.equal((await S.req('POST', '/v1/coupon', { token: p.token, body: { code: 'NOPE99' } })).json.error, 'unknown_coupon')
  S.clock.t = T0
})

test('PVP: 내 팀 힘이 상대의 40%보다 작으면 win:true를 보내도 패배', async () => {
  assert.ok(P.plausibleWin(400, 1000))
  assert.ok(!P.plausibleWin(399, 1000))
  assert.ok(P.plausibleWin(null, 1000), 'old battles without a stored power')
  const p = await S.login()
  const FIVE = ['hans', 'ella', 'dorik', 'nina', 'kyle']
  for (const id of FIVE) await S.db.query('insert into player_heroes (player_id, hero_id) values ($1, $2) on conflict do nothing', [p.id, id])
  const heroes = FIVE.map((id) => ({ id, hp: 500, atk: 30 }))
  const fight = async (oppPower: number | null) => {
    const st = await S.req('POST', '/v1/pvp/start', { token: p.token, body: { mode: 'duel', heroes } })
    assert.equal(st.status, 200, JSON.stringify(st.json))
    const [row] = await S.db.query("select (opponent->>'my_power')::float8 as mine from pvp_battles where id = $1", [st.json.battle.id])
    assert.ok(Number(row.mine) > 0, 'start stores my team power')
    if (oppPower !== null) await S.db.query("update pvp_battles set opponent = jsonb_set(opponent, '{power}', $2::jsonb) where id = $1", [st.json.battle.id, JSON.stringify(oppPower)])
    S.clock.t += 30
    return (await S.req('POST', '/v1/pvp/finish', { token: p.token, body: { battle_id: st.json.battle.id, win: true } })).json.result
  }
  assert.equal((await fight(null)).win, true, 'fair bot opponent')
  const r = await fight(1e12)
  assert.equal(r.win, false)
  assert.equal(r.claimed_win, true)
  S.clock.t = T0
})

test('던전: 편성의 서버 계산 피해로 그 단계 적을 못 잡으면 승리 409 implausible', async () => {
  const p = await S.login()
  const party = ['hans', 'ella', 'dorik', 'nina', 'arteon', 'ignis']
  for (const id of party) await S.db.query('insert into player_heroes (player_id, hero_id) values ($1, $2) on conflict do nothing', [p.id, id])
  const s = await S.req('POST', '/v1/dungeon/start', { token: p.token, body: { type: 'gold', level: 1, party } })
  assert.equal(s.status, 200, JSON.stringify(s.json))
  await S.db.query('update dungeon_runs set level = 400 where run_id = $1', [s.json.run_id]) // 고친 앱이 높은 단계로 시작한 것처럼
  S.clock.t += 30
  const r = await S.req('POST', '/v1/dungeon/finish', { token: p.token, body: { run_id: s.json.run_id, win: true, elapsed: 30 } })
  assert.deepEqual([r.status, r.json.error], [409, 'implausible'])
  await S.db.query('update dungeon_runs set level = 1 where run_id = $1', [s.json.run_id])
  assert.equal((await S.req('POST', '/v1/dungeon/finish', { token: p.token, body: { run_id: s.json.run_id, win: true, elapsed: 30 } })).status, 200)
  S.clock.t = T0
})

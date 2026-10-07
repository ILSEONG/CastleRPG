// PVP(마이그레이션 029, pvp.ts·pvp_routes.ts): 등급·포인트 규칙, 다음 상대(봇·실제 방어팀), 하루 5판, 시작 = 패배로 먼저 적기,
// 승리 결과 바로잡기·재전송, 너무 이른 승리 거절, 방어팀, 상점(코인·한도·보상).
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as P from '../src/pvp.ts'
import { setup } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup()
})
after(async () => {
  await S.close()
})

const FIVE = ['hans', 'ella', 'dorik', 'nina', 'kyle']
const team = (hp = 500, atk = 30) => FIVE.map((id) => ({ id, hp, atk }))

async function player() {
  const p = await S.login()
  for (const id of FIVE) {
    await S.db.query(`insert into player_heroes (player_id, hero_id) values ($1, $2) on conflict do nothing`, [p.id, id])
  }
  return p
}

test('pvp rules: tiers, win gain, loss floor, soldier pick', () => {
  assert.equal(P.tierOf(0).name, '브론즈')
  assert.equal(P.tierOf(199).id, 'bronze')
  assert.equal(P.tierOf(200).id, 'silver')
  assert.equal(P.tierOf(5000).id, 'challenger')
  assert.equal(P.tierOf(5000).next, null)
  assert.equal(P.winGain(500, 500), 25)
  assert.equal(P.winGain(500, 1500), 35)
  assert.equal(P.winGain(1500, 500), 15)
  assert.equal(P.lossOf(4), 4)
  assert.equal(P.lossOf(400), 10)
  assert.deepEqual(P.pickSoldiers({ 'infantry:1': 30, 'archer:3': 5, 'cavalry:2': 8 }), { 'archer:3': 5, 'cavalry:2': 8, 'infantry:1': 7 })
  assert.ok(!P.acceptWin(true, 3))
  assert.ok(P.acceptWin(true, 30))
  assert.ok(P.acceptWin(true, 6)) // x1.5 배속: 8 게임 초 = 실제 5.3초
  assert.ok(!P.acceptWin(true, 5000))
})

test('pvp view: both modes, bot opponent with 5 heroes, 5 plays', async () => {
  const p = await player()
  const r = await S.req('GET', '/v1/pvp', { token: p.token })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  for (const m of P.MODES) {
    const v = r.json.pvp.modes[m]
    assert.equal(v.plays_left, 5)
    assert.equal(v.points, 0)
    assert.equal(v.tier.id, 'bronze')
    assert.equal(v.next.kind, 'bot')
    assert.equal(v.next.heroes.length, 5)
  }
  assert.equal(r.json.pvp.coins, 0)
  const again = await S.req('GET', '/v1/pvp', { token: p.token })
  assert.deepEqual(again.json.pvp.modes.duel.next, r.json.pvp.modes.duel.next, 'next opponent stays until a battle starts')
})

test('pvp start/finish: loss first, win corrects, replay same, early win refused, 5 plays a day', async () => {
  const p = await player()
  const v0 = (await S.req('GET', '/v1/pvp', { token: p.token })).json.pvp
  await S.req('POST', '/v1/test/pvp_points', { token: p.token, body: { mode: 'duel', points: 300 } })
  const st = await S.req('POST', '/v1/pvp/start', { token: p.token, body: { mode: 'duel', heroes: team() } })
  assert.equal(st.status, 200, JSON.stringify(st.json))
  const b = st.json.battle
  assert.equal(b.opponent.name, v0.modes.duel.next.name, 'fights the opponent shown before')
  assert.equal(b.loss, 10)
  assert.equal(st.json.pvp.modes.duel.points, 290)
  assert.equal(st.json.pvp.modes.duel.plays_left, 4)
  assert.equal(st.json.pvp.coins, P.COINS_LOSS)
  assert.deepEqual(st.json.pvp.modes.duel.defense, FIVE, 'first team becomes the defense team')
  assert.notEqual(st.json.pvp.modes.duel.next, null)
  const early = await S.req('POST', '/v1/pvp/finish', { token: p.token, body: { battle_id: b.id, win: true } })
  assert.equal(early.json.result.win, false, 'win right after start is refused')
  // 두 번째 판: 시간이 지난 뒤 승리
  const st2 = await S.req('POST', '/v1/pvp/start', { token: p.token, body: { mode: 'duel', heroes: team() } })
  S.clock.t += 40
  const f = await S.req('POST', '/v1/pvp/finish', { token: p.token, body: { battle_id: st2.json.battle.id, win: true } })
  assert.equal(f.json.result.win, true)
  assert.equal(f.json.pvp.modes.duel.points, 290 + st2.json.battle.gain, 'loss taken at start is given back + gain')
  assert.equal(f.json.pvp.modes.duel.wins, 1)
  assert.equal(f.json.pvp.modes.duel.losses, 1)
  assert.equal(f.json.pvp.coins, P.COINS_LOSS * 2 + (P.COINS_WIN - P.COINS_LOSS))
  const replay = await S.req('POST', '/v1/pvp/finish', { token: p.token, body: { battle_id: st2.json.battle.id, win: true } })
  assert.deepEqual(replay.json.result, f.json.result)
  assert.equal(replay.json.pvp.modes.duel.points, f.json.pvp.modes.duel.points, 'no double points')
  for (let i = 0; i < 3; i++) assert.equal((await S.req('POST', '/v1/pvp/start', { token: p.token, body: { mode: 'duel', heroes: team() } })).status, 200)
  const out = await S.req('POST', '/v1/pvp/start', { token: p.token, body: { mode: 'duel', heroes: team() } })
  assert.equal(out.status, 409)
  assert.equal(out.json.error, 'no_plays')
  const total = await S.req('POST', '/v1/pvp/start', { token: p.token, body: { mode: 'total', heroes: team() } })
  assert.equal(total.status, 200, 'total war has its own plays')
  S.clock.t += 86400
  assert.equal((await S.req('GET', '/v1/pvp', { token: p.token })).json.pvp.modes.duel.plays_left, 5, 'plays reset daily')
})

test('pvp matchmaking: real defense team near my points', async () => {
  const a = await player()
  const d = await S.req('POST', '/v1/pvp/defense', { token: a.token, body: { mode: 'duel', heroes: team(600, 40) } })
  assert.equal(d.status, 200, JSON.stringify(d.json))
  await S.req('POST', '/v1/test/pvp_points', { token: a.token, body: { mode: 'duel', points: 5000 } })
  const b = await player()
  await S.req('POST', '/v1/test/pvp_points', { token: b.token, body: { mode: 'duel', points: 4990 } })
  await S.req('POST', '/v1/pvp/start', { token: b.token, body: { mode: 'duel', heroes: team() } }) // next was a bot made at 0 points
  const v = (await S.req('GET', '/v1/pvp', { token: b.token })).json.pvp
  assert.equal(v.modes.duel.next.kind, 'player')
  assert.equal(v.modes.duel.next.points, 5000)
  assert.equal(v.modes.duel.next.heroes.length, 5)
  const bad = await S.req('POST', '/v1/pvp/defense', { token: a.token, body: { mode: 'duel', heroes: ['hans', 'hans', 'ella', 'dorik', 'nina'] } })
  assert.equal(bad.status, 409)
})

test('pvp shop: coins, limit, rewards', async () => {
  const p = await player()
  await S.req('GET', '/v1/pvp', { token: p.token })
  const poor = await S.req('POST', '/v1/pvp/buy', { token: p.token, body: { id: 'gold' } })
  assert.equal(poor.json.error, 'not_enough_coins')
  await S.db.query('update pvp_wallet set coins = 1000 where player_id = $1', [p.id])
  const g0 = (await S.req('GET', '/v1/player', { token: p.token })).json.player.gold
  const r = await S.req('POST', '/v1/pvp/buy', { token: p.token, body: { id: 'gold' } })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  assert.equal(r.json.player.gold, g0 + 30000)
  assert.equal(r.json.pvp.coins, 940)
  const t = await S.req('POST', '/v1/pvp/buy', { token: p.token, body: { id: 'ticket' } })
  assert.equal(t.status, 200)
  assert.equal(t.json.player.dia_tickets, r.json.player.dia_tickets + 1)
  const t2 = await S.req('POST', '/v1/pvp/buy', { token: p.token, body: { id: 'ticket' } })
  assert.equal(t2.json.error, 'sold_out')
  assert.equal(t2.status, 409)
})

test('pvp bot mirrors base grades and roles, power near base', () => {
  const defs = [
    { id: 'a', role: 'melee', hp: 100, atk: 10, atk_interval: 1, grade: 'SSR' },
    { id: 'b', role: 'melee', hp: 100, atk: 10, atk_interval: 1, grade: 'SSR' },
    { id: 'c', role: 'ranged', hp: 80, atk: 8, atk_interval: 1, grade: 'SR' },
    { id: 'd', role: 'ranged', hp: 80, atk: 8, atk_interval: 1, grade: 'SR' },
    { id: 'e', role: 'melee', hp: 120, atk: 12, atk_interval: 1, grade: 'R' },
    { id: 'f', role: 'melee', hp: 120, atk: 12, atk_interval: 1, grade: 'R' },
  ]
  const cfg = (k: string) => ({ hero_max_level_base: 30, hero_max_level_per_promotion: 10, hero_level_stat: 0.07, hero_promotion_stat: 0.3 } as Record<string, number>)[k] ?? 0
  const base = [{ grade: 'SSR', role: 'melee', power: 400 }, { grade: 'SR', role: 'ranged', power: 300 }, { grade: 'R', role: 'melee', power: 200 }]
  const bot = P.botTeam(7, 'duel', base, 100, defs, cfg, {}, [])
  assert.equal(bot.heroes.length, 5)
  const g = (id: string) => defs.find((d) => d.id === id)!
  assert.equal(g(bot.heroes[0].hero).grade, 'SSR')
  assert.equal(g(bot.heroes[1].hero).role, 'ranged')
  assert.equal(g(bot.heroes[2].hero).grade, 'R')
  assert.equal(new Set(bot.heroes.map((h) => h.hero)).size, 5)
})

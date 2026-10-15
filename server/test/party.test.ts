// 파티 퀘스트(마이그레이션 050, party.ts·party_routes.ts): 난이도 배수, 장신구 등급, 매칭(사람끼리·AI 성주 채움), 입장 수락·거절·시간 초과,
// 판 결과(승리 타당성·하루 보상 수·재전송), 잠긴 난이도, 병사 보유 검사, 반지 장착.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as PQ from '../src/party.ts'
import * as R from '../src/rules.ts'
import { setup } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup()
})
after(async () => {
  await S.close()
})

async function player(hero = 'hans') {
  const p = await S.login()
  await S.db.query(`insert into player_heroes (player_id, hero_id) values ($1, $2) on conflict do nothing`, [p.id, hero])
  return p
}

const queueLich = (p: { token: string }, diff = 1, hero = 'hans') => S.req('POST', '/v1/party/queue', { token: p.token, body: { quest: 'lich', diff, hero: { id: hero, hp: 500, atk: 40 } } })

test('party rules: user difficulty steps, drop grades', () => {
  assert.deepEqual(PQ.DIFF_MULT, [1, 10, 50, 150]) // 보통 = 쉬움 ×10, 어려움 = 보통 ×5, 매우 어려움 = 어려움 ×3
  assert.equal(PQ.bossStats('lich', 2).hp, PQ.BOSS.lich.hp * 10)
  assert.equal(PQ.bossStats('spider', 4).atk, PQ.BOSS.spider.atk * 150)
  assert.equal(PQ.dropGrade(R.EQUIP_GRADES, 1, () => 0), 'N')
  assert.equal(PQ.dropGrade(R.EQUIP_GRADES, 1, () => 0.9999), 'SSR') // 쉬움은 UR·LR 없음
  assert.equal(PQ.dropGrade(R.EQUIP_GRADES, 4, () => 0), 'R') // 매우 어려움은 N 없음
  assert.equal(PQ.dropGrade(R.EQUIP_GRADES, 4, () => 0.9999), 'LR')
  assert.ok(R.EQUIP_SLOTS.includes('ring') && R.EQUIP_SLOTS.includes('necklace'))
  assert.equal(R.itemStats({ slot: 'ring', weapon_kind: null, grade: 'SR' }).atk, Math.round(12 * 2.2))
  assert.equal(R.itemStats({ slot: 'necklace', weapon_kind: null, grade: 'N' }).hp, 110)
})

test('party hub: 4 humans match, all must accept, decline drops only the decliner', () => {
  let n = 0
  const bot = (): PQ.Seat => ({ pid: null, name: `bot${n++}`, dps: 1, power: 1, accepted: true })
  const hub = new PQ.PartyHub(bot, () => 0.5)
  const seat = (pid: string): PQ.Seat => ({ pid, name: pid, dps: 10, power: 100, accepted: false })
  for (const id of ['a', 'b', 'c']) hub.join(seat(id), 'lich', 1, 0)
  assert.equal(hub.matches.size, 0, 'three are not enough for the lich')
  hub.join(seat('d'), 'lich', 1, 1)
  const m = [...hub.matches.values()][0]
  assert.equal(m.state, 'confirm')
  assert.equal(m.seats.length, 4)
  hub.answer('a', m.id, true, 2)
  hub.answer('b', m.id, true, 2)
  hub.answer('c', m.id, false, 3)
  assert.equal(hub.matches.size, 0)
  assert.deepEqual(hub.queue.map((t) => t.seat.pid).sort(), ['a', 'b', 'd'], 'the decliner leaves the queue, the others go back')
  hub.tick(4)
  const m2 = [...hub.matches.values()][0]
  assert.ok(m2, 'they waited long enough: an AI lord fills the seat at once')
  assert.equal(m2.seats.filter((s) => s.pid == null).length, 1)
  for (const id of ['a', 'b', 'd']) hub.answer(id, m2.id, true, 5)
  assert.equal(m2.state, 'live')
  // 수락 시간 초과: 안 누른 사람만 빠진다
  for (const id of ['e', 'f', 'g']) hub.join(seat(id), 'spider', 2, 10)
  const m3 = hub.matchOf('e')!
  hub.answer('e', m3.id, true, 11)
  hub.tick(10 + PQ.CONFIRM_SEC + 1)
  assert.deepEqual(hub.queue.filter((t) => t.quest === 'spider').map((t) => t.seat.pid), [], 'requeued e matched again with bots')
  assert.ok(hub.matchOf('e') && !hub.matchOf('f') && !hub.matchOf('g'))
})

test('party hub: a lone player gets AI lords after the wait, stale tickets drop', () => {
  const hub = new PQ.PartyHub(() => ({ pid: null, name: 'bot', dps: 1, power: 1, accepted: true }), () => 0.5)
  hub.join({ pid: 'solo', name: 's', dps: 5, power: 5, accepted: false }, 'lich', 1, 0)
  for (let t = 5; t < PQ.BOT_WAIT_SEC; t += 5) {
    hub.seen('solo', t) // 앱이 대기 중 계속 묻는다
    hub.tick(t)
  }
  assert.equal(hub.matches.size, 0)
  hub.seen('solo', PQ.BOT_WAIT_SEC)
  hub.tick(PQ.BOT_WAIT_SEC)
  assert.equal(hub.matchOf('solo')!.seats.length, 4)
  hub.join({ pid: 'gone', name: 'g', dps: 5, power: 5, accepted: false }, 'spider', 1, 100)
  hub.tick(100 + PQ.QUEUE_STALE_SEC + 1)
  assert.equal(hub.ticketOf('gone'), null)
})

test('party routes: queue, bots, accept, live run, win gives a ring once, replay is idempotent', async () => {
  const p = await player()
  const q = await queueLich(p)
  assert.equal(q.status, 200, JSON.stringify(q.json))
  assert.equal(q.json.party.queue.state, 'queued')
  assert.equal(q.json.party.quests.lich.clears_left, PQ.REWARD_CLEARS)
  const now = await S.req('POST', '/v1/test/party_bots_now', { token: p.token })
  assert.equal(now.json.party.queue.state, 'confirm', JSON.stringify(now.json.party.queue))
  assert.equal(now.json.party.queue.seats.length, 4)
  assert.equal(now.json.party.queue.seats.filter((s: any) => s.bot).length, 3)
  assert.ok(now.json.party.queue.seats.every((s: any) => s.bot ? s.hero.hero && s.hero.hp > 0 : s.me))
  assert.ok(!JSON.stringify(now.json).includes(p.id), 'player ids are not sent')
  const acc = await S.req('POST', '/v1/party/accept', { token: p.token, body: { match_id: now.json.party.queue.match_id, accept: true } })
  const live = acc.json.party.queue
  assert.equal(live.state, 'live')
  assert.equal(live.boss.hp, PQ.BOSS.lich.hp)
  assert.equal(live.me, 0)
  // 너무 이른 승리는 패배로 닫힌다
  S.clock.t += 60
  const fin = await S.req('POST', '/v1/party/finish', { token: p.token, body: { run_id: live.run_id, win: true, elapsed: 60 } })
  assert.equal(fin.status, 200, JSON.stringify(fin.json))
  assert.equal(fin.json.result.win, true, JSON.stringify(fin.json.result))
  const ring = fin.json.result.rewards.items[0]
  assert.equal(ring.slot, 'ring')
  assert.ok(fin.json.player.items.some((it: any) => it.slot === 'ring'))
  assert.equal(fin.json.party.quests.lich.best, 1)
  assert.equal(fin.json.party.quests.lich.clears_left, PQ.REWARD_CLEARS - 1)
  const again = await S.req('POST', '/v1/party/finish', { token: p.token, body: { run_id: live.run_id, win: true, elapsed: 60 } })
  assert.deepEqual(again.json.result, fin.json.result)
  assert.equal(again.json.player.items.filter((it: any) => it.slot === 'ring').length, 1, 'no second ring')
  // 반지를 낀다
  const eq = await S.req('POST', '/v1/equip', { token: p.token, body: { hero_id: 'hans', slot: 'ring', item_id: fin.json.player.items.find((it: any) => it.slot === 'ring').id } })
  assert.equal(eq.status, 200, JSON.stringify(eq.json))
})

test('party routes: locked difficulty, too-fast win, no soldiers, decline', async () => {
  const p = await player()
  const lk = await queueLich(p, 2)
  assert.equal(lk.status, 409)
  assert.equal(lk.json.error, 'locked', JSON.stringify(lk.json))
  const q = await queueLich(p, 1)
  assert.equal(q.status, 200)
  const now = await S.req('POST', '/v1/test/party_bots_now', { token: p.token })
  const acc = await S.req('POST', '/v1/party/accept', { token: p.token, body: { match_id: now.json.party.queue.match_id, accept: true } })
  S.clock.t += 5
  const fin = await S.req('POST', '/v1/party/finish', { token: p.token, body: { run_id: acc.json.party.queue.run_id, win: true, elapsed: 5 } })
  assert.equal(fin.json.result.win, false, 'a 5 s win is not plausible')
  assert.equal(fin.json.party.quests.lich.best, 0)
  // 거미 여왕: 병사가 없으면 못 들어간다
  const sp = await S.req('POST', '/v1/party/queue', { token: p.token, body: { quest: 'spider', diff: 1, soldiers: [1, 2, 3, 4].map(() => ({ type: 'infantry', tier: 1 })) } })
  assert.equal(sp.status, 409)
  const p2 = await player()
  const r = await S.req('POST', '/v1/party/queue', { token: p2.token, body: { quest: 'spider', diff: 1, soldiers: [{ type: 'infantry', tier: 1 }] } })
  assert.equal(r.status, 400)
  // 거절하면 대기열에서도 빠진다
  const q3 = await queueLich(p2)
  assert.equal(q3.status, 200)
  const c3 = await S.req('POST', '/v1/test/party_bots_now', { token: p2.token })
  const no = await S.req('POST', '/v1/party/accept', { token: p2.token, body: { match_id: c3.json.party.queue.match_id, accept: false } })
  assert.equal(no.json.party.queue.state, 'idle')
})

test('party: the super admin gets AI lords at once (owner testing alone)', async () => {
  const p = await player()
  await S.req('POST', '/v1/test/admin', { token: p.token })
  const q = await queueLich(p, 1)
  assert.equal(q.status, 200)
  assert.equal(q.json.party.queue.state, 'confirm', JSON.stringify(q.json.party.queue))
  assert.equal(q.json.party.queue.seats.filter((s: { bot?: boolean }) => s.bot).length, 3)
  const n = await player()
  const q2 = await queueLich(n, 1)
  assert.equal(q2.json.party.queue.state, 'queued', 'other players still wait for real lords first')
})

test('party hub: a party (code) sits together, strangers fill the rest, then AI lords', () => {
  let n = 0
  const bot = (): PQ.Seat => ({ pid: null, name: `bot${n++}`, dps: 1, power: 1, accepted: true })
  const hub = new PQ.PartyHub(bot, () => 0.3)
  const seat = (pid: string): PQ.Seat => ({ pid, name: pid, dps: 10, power: 100, accepted: false })
  const l = hub.createLobby(seat('lead'), 'lich', 1, 0) as PQ.Lobby
  assert.equal(l.code.length, PQ.CODE_LEN)
  assert.equal(hub.joinLobby('NOPE00', seat('x'), 1), 'no_code')
  assert.ok(typeof hub.joinLobby(l.code, seat('m1'), 1) !== 'string')
  assert.ok(typeof hub.joinLobby(l.code, seat('m2'), 1) !== 'string')
  // 혼자 온 두 사람이 먼저 기다리고 있다: 파티 3명 + 한 사람이 한 매치, 남은 사람은 계속 대기
  hub.join(seat('s1'), 'lich', 1, 2)
  hub.join(seat('s2'), 'lich', 1, 2)
  assert.equal(hub.startLobby('m1', 1, 3), 'not_leader')
  hub.startLobby('lead', 1, 3)
  const m = hub.matchOf('lead')!
  assert.ok(m, 'the party matched')
  assert.deepEqual(m.seats.map((s) => s.pid).filter((p) => p !== 's1' && p !== 's2').sort(), ['lead', 'm1', 'm2'])
  assert.ok(hub.matchOf('m1') === m && hub.matchOf('m2') === m, 'party members are in the same match')
  assert.equal(m.seats.length, 4)
  // 파티는 가득 차면 못 들어간다(리치 4명)
  assert.ok(typeof hub.joinLobby(l.code, seat('m3'), 4) !== 'string')
  assert.equal(hub.joinLobby(l.code, seat('m4'), 4), 'full')
  // 방장이 나가면 다음 사람이 방장, 다 나가면 파티가 없어진다
  hub.leaveLobby('lead')
  assert.equal(hub.lobbies.get(l.code)!.leader, 'm1')
  for (const p of ['m1', 'm2', 'm3']) hub.leaveLobby(p)
  assert.equal(hub.lobbies.size, 0)
  // 혼자인 파티: 기다린 뒤 AI 성주
  const l2 = hub.createLobby(seat('solo'), 'spider', 1, 100) as PQ.Lobby
  hub.joinLobby(l2.code, seat('p2'), 100)
  hub.startLobby('solo', 1, 100)
  assert.equal(hub.matchOf('solo'), null)
  hub.seen('solo', 100 + PQ.BOT_WAIT_SEC)
  hub.seen('p2', 100 + PQ.BOT_WAIT_SEC)
  hub.tick(100 + PQ.BOT_WAIT_SEC)
  const m2 = hub.matchOf('solo')!
  assert.ok(m2 && hub.matchOf('p2') === m2 && m2.seats.filter((s) => s.pid == null).length === 1)
})

test('party routes: create a party, join by code, leader starts, wrong codes are rate limited', async () => {
  const a = await player()
  const b = await player()
  const c = await player()
  const lich = { quest: 'lich', diff: 1, hero: { id: 'hans', hp: 500, atk: 40 } }
  const cr = await S.req('POST', '/v1/party/lobby/create', { token: a.token, body: lich })
  assert.equal(cr.status, 200, JSON.stringify(cr.json))
  const code = cr.json.party.lobby.code
  assert.equal(cr.json.party.lobby.leader, true)
  const jb = await S.req('POST', '/v1/party/lobby/join', { token: b.token, body: { code: code.toLowerCase(), hero: lich.hero } })
  assert.equal(jb.status, 200, JSON.stringify(jb.json))
  assert.equal(jb.json.party.lobby.members.length, 2)
  assert.equal(jb.json.party.lobby.leader, false)
  const solo = await queueLich(b)
  assert.equal(solo.json.error, 'in_lobby', 'a party member cannot queue alone')
  const notLead = await S.req('POST', '/v1/party/lobby/start', { token: b.token, body: { diff: 1 } })
  assert.equal(notLead.json.error, 'not_leader')
  const locked = await S.req('POST', '/v1/party/lobby/start', { token: a.token, body: { diff: 2 } })
  assert.equal(locked.json.error, 'member_locked')
  const st = await S.req('POST', '/v1/party/lobby/start', { token: a.token, body: { diff: 1 } })
  assert.equal(st.json.party.queue.state, 'queued')
  const sb = await S.req('GET', '/v1/party', { token: b.token })
  assert.equal(sb.json.party.queue.state, 'queued', 'the member is queued too')
  await S.req('POST', '/v1/test/party_bots_now', { token: a.token })
  const ca = await S.req('GET', '/v1/party', { token: a.token })
  const cb = await S.req('GET', '/v1/party', { token: b.token })
  assert.equal(ca.json.party.queue.state, 'confirm', JSON.stringify(ca.json.party.queue))
  assert.equal(ca.json.party.queue.match_id, cb.json.party.queue.match_id, 'same match')
  // 틀린 코드는 JOIN_TRIES번까지만
  let last = 0
  for (let i = 0; i <= PQ.JOIN_TRIES; i++) last = (await S.req('POST', '/v1/party/lobby/join', { token: c.token, body: { code: 'ZZZZZ9', hero: lich.hero } })).status
  assert.equal(last, 429)
  const lv = await S.req('POST', '/v1/party/lobby/leave', { token: b.token })
  assert.equal(lv.json.party.lobby, null)
})

test('party routes: invite an online friend or guild member, they accept with the code or decline', async () => {
  const a = await player()
  const b = await player()
  const g = await player()
  const stranger = await player()
  const away = await player()
  await S.db.query('insert into friend_links (a, b, accepted) values ($1, $2, true), ($1, $3, true)', [a.id, b.id, away.id])
  const [gid] = await S.db.query(`insert into guilds (name, seed, created_at, virtual_n) values ('초대길드', 1, now(), 0) returning id`)
  await S.db.query('insert into player_guild (player_id, guild_id, joined_at) values ($1, $3, now()), ($2, $3, now())', [a.id, g.id, gid.id])
  for (const p of [b, g, stranger]) await S.req('GET', '/v1/party/invites', { token: p.token }) // 접속 중(away는 요청이 없다)
  const lich = { quest: 'lich', diff: 1, hero: { id: 'hans', hp: 500, atk: 40 } }
  const noParty = await S.req('POST', '/v1/party/invite', { token: a.token, body: { to: b.id } })
  assert.equal(noParty.json.error, 'no_lobby')
  await S.req('POST', '/v1/party/lobby/create', { token: a.token, body: lich })
  const list = await S.req('GET', '/v1/party/invitable', { token: a.token })
  const byId = new Map(list.json.people.map((x: any) => [x.id, x]))
  assert.equal(list.json.people.length, 3, 'friends + guild members, not strangers')
  assert.deepEqual([(byId.get(b.id) as any).online, (byId.get(g.id) as any).guild, (byId.get(away.id) as any).online], [true, true, false])
  assert.equal((await S.req('POST', '/v1/party/invite', { token: a.token, body: { to: stranger.id } })).json.error, 'not_friend')
  assert.equal((await S.req('POST', '/v1/party/invite', { token: a.token, body: { to: away.id } })).json.error, 'offline')
  assert.equal((await S.req('POST', '/v1/party/invite', { token: a.token, body: { to: b.id } })).status, 200)
  assert.equal((await S.req('POST', '/v1/party/invite', { token: a.token, body: { to: b.id } })).status, 200, 'sending again replaces it')
  assert.equal((await S.req('POST', '/v1/party/invite', { token: a.token, body: { to: g.id } })).status, 200)
  const ib = await S.req('GET', '/v1/party/invites', { token: b.token })
  assert.equal(ib.json.invites.length, 1)
  const inv = ib.json.invites[0]
  assert.equal(inv.quest, 'lich')
  assert.equal(inv.name, R.friendName(a.id))
  // b 수락(코드로 참가) → 초대가 사라진다
  const jb = await S.req('POST', '/v1/party/lobby/join', { token: b.token, body: { code: inv.code, hero: lich.hero } })
  assert.equal(jb.json.party.lobby.members.length, 2)
  assert.equal((await S.req('GET', '/v1/party/invites', { token: b.token })).json.invites.length, 0)
  assert.equal((await S.req('POST', '/v1/party/invite', { token: a.token, body: { to: b.id } })).json.error, 'member')
  // g 거절
  const ig = await S.req('GET', '/v1/party/invites', { token: g.token })
  const dg = await S.req('POST', '/v1/party/invite/decline', { token: g.token, body: { id: ig.json.invites[0].id } })
  assert.equal(dg.json.invites.length, 0)
  // 도배 막기
  let last = 0
  for (let i = 0; i < PQ.INVITE_MAX; i++) last = (await S.req('POST', '/v1/party/invite', { token: a.token, body: { to: g.id } })).status
  assert.equal(last, 429)
})

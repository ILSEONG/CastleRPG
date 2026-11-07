// 파티 퀘스트(마이그레이션 050, party.ts·party_routes.ts): 난이도 배수, 장신구 등급, 매칭(사람끼리·AI 성주 채움), 입장 수락·거절·시간 초과,
// 판 결과(승리 타당성·하루 보상 수·재전송), 잠긴 난이도, 병사 보유 검사, 반지 장착.
import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import { EventEmitter } from 'node:events'
import { after, before, test } from 'node:test'
import * as PQ from '../src/party.ts'
import { MAX_BUFFER, PartyLive } from '../src/party_live.ts'
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
  for (const id of ['a', 'b', 'd']) hub.seen(id, 4 + PQ.BOT_WAIT_SEC)
  hub.tick(4 + PQ.BOT_WAIT_SEC)
  assert.equal(hub.matches.size, 0, 'no AI lords (user 2026-11-07): the empty seat waits for a person')
  hub.join(seat('h'), 'lich', 1, 4 + PQ.BOT_WAIT_SEC)
  const m2 = [...hub.matches.values()][0]
  assert.ok(m2, 'a fourth person fills the seat')
  assert.equal(m2.seats.filter((s) => s.pid == null).length, 0)
  for (const id of ['a', 'b', 'd', 'h']) hub.answer(id, m2.id, true, 5)
  assert.equal(m2.state, 'live')
  // 수락 시간 초과: 안 누른 사람만 빠진다
  for (const id of ['e', 'f', 'g']) hub.join(seat(id), 'spider', 2, 10)
  const m3 = hub.matchOf('e')!
  hub.answer('e', m3.id, true, 11)
  hub.tick(10 + PQ.CONFIRM_SEC + 1)
  assert.deepEqual(hub.queue.filter((t) => t.quest === 'spider').map((t) => t.seat.pid), ['e'], 'e waits again for people, f and g are out')
  assert.ok(!hub.matchOf('e') && !hub.matchOf('f') && !hub.matchOf('g'))
})

test('party hub: a lone player never gets AI lords (only a bots seat — admin test — does), stale tickets drop', () => {
  const hub = new PQ.PartyHub(() => ({ pid: null, name: 'bot', dps: 1, power: 1, accepted: true }), () => 0.5)
  hub.join({ pid: 'solo', name: 's', dps: 5, power: 5, accepted: false }, 'lich', 1, 0)
  for (let t = 5; t <= PQ.BOT_WAIT_SEC * 4; t += 5) {
    hub.seen('solo', t) // 앱이 대기 중 계속 묻는다
    hub.tick(t)
  }
  assert.equal(hub.matches.size, 0, 'no AI lords for players')
  hub.leave('solo')
  hub.join({ pid: 'admin', name: 'a', dps: 5, power: 5, accepted: false, bots: true }, 'lich', 1, 200)
  hub.seen('admin', 200 + PQ.BOT_WAIT_SEC - 1)
  hub.tick(200 + PQ.BOT_WAIT_SEC - 1)
  assert.equal(hub.matches.size, 0)
  hub.seen('admin', 200 + PQ.BOT_WAIT_SEC)
  hub.tick(200 + PQ.BOT_WAIT_SEC)
  assert.equal(hub.matchOf('admin')!.seats.length, 4)
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
  // 너무 이른 승리는 패배로 닫힌다(AI 성주와만 한 판: 힘 여유 SOLO_DPS_SLACK — 한스 혼자의 초당 피해로도 170초면 쉬움 보스를 깎는다)
  S.clock.t += 170
  const fin = await S.req('POST', '/v1/party/finish', { token: p.token, body: { run_id: live.run_id, win: true, elapsed: 170 } })
  assert.equal(fin.status, 200, JSON.stringify(fin.json))
  assert.equal(fin.json.result.win, true, JSON.stringify(fin.json.result))
  const ring = fin.json.result.rewards.items[0]
  assert.equal(ring.slot, 'ring')
  assert.ok(fin.json.player.items.some((it: any) => it.slot === 'ring'))
  assert.equal(fin.json.party.quests.lich.best, 1)
  assert.equal(fin.json.party.quests.lich.clears_left, PQ.REWARD_CLEARS - 1)
  const again = await S.req('POST', '/v1/party/finish', { token: p.token, body: { run_id: live.run_id, win: true, elapsed: 170 } })
  assert.deepEqual(again.json.result, fin.json.result)
  assert.equal(ring.id, fin.json.player.items.find((it: any) => it.slot === 'ring').id, 'the result names the ring that was granted')
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
  // 파티원이 판(수락 확인·전투)에 앉아 있으면 새 사람은 못 들어간다
  assert.equal(hub.joinLobby(l.code, seat('m3'), 4), 'busy')
  // 방장이 나가면 다음 사람이 방장, 다 나가면 파티가 없어진다
  hub.leaveLobby('lead')
  assert.equal(hub.lobbies.get(l.code)!.leader, 'm1')
  for (const p of ['m1', 'm2', 'm3']) hub.leaveLobby(p)
  assert.equal(hub.lobbies.size, 0)
  // 2명 파티(거미 3자리): AI 성주 없이 계속 기다린다 — 매칭 중에 코드(모집 초대장)로 들어온 사람은 같은 대기에 붙어 함께 앉는다
  const l2 = hub.createLobby(seat('solo'), 'spider', 1, 100) as PQ.Lobby
  hub.joinLobby(l2.code, seat('p2'), 100)
  hub.startLobby('solo', 1, 100)
  assert.equal(hub.matchOf('solo'), null)
  hub.seen('solo', 100 + PQ.BOT_WAIT_SEC)
  hub.seen('p2', 100 + PQ.BOT_WAIT_SEC)
  hub.tick(100 + PQ.BOT_WAIT_SEC)
  assert.equal(hub.matchOf('solo'), null, 'no AI lords')
  assert.ok(hub.lobbyQueued(l2))
  assert.ok(typeof hub.joinLobby(l2.code, seat('p3'), 101 + PQ.BOT_WAIT_SEC) !== 'string')
  const m2 = hub.matchOf('solo')!
  assert.ok(m2 && hub.matchOf('p2') === m2 && hub.matchOf('p3') === m2 && m2.seats.every((s) => s.pid != null))
  assert.equal(hub.joinLobby(l2.code, seat('late'), 102 + PQ.BOT_WAIT_SEC), 'full')
  // 혼자 매칭 중에 모집: 그 대기가 파티(방장) 대기로 바뀌고 기다린 시간은 그대로
  hub.join(seat('alone'), 'lich', 2, 300)
  const l3 = hub.lobbyFromTicket('alone', 310)!
  assert.ok(l3 && l3.leader === 'alone' && hub.ticketOf('alone')!.seat.group === l3.code && hub.ticketOf('alone')!.since === 300)
  assert.equal(hub.lobbyFromTicket('alone', 311), null, 'already a party ticket')
  const rec = { code: l3.code, quest: 'lich' as const, diff: 2, at: 310 }
  assert.deepEqual(hub.recruitOpen(rec, 320), { open: true, count: 1, size: 4 })
  assert.equal(hub.recruitOpen(rec, 310 + PQ.RECRUIT_TTL_SEC).open, false, 'cards expire')
  hub.leaveLobby('alone')
  assert.equal(hub.recruitOpen(rec, 320).open, false, 'the party is gone')
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

test('party routes: locked until the guide reaches the party mission (finished/skipped guides and the super admin are open)', async () => {
  const a = await player()
  const b = await player()
  const [{ n }] = await S.db.query(`select count(*)::int as n from quest_defs where type = 'tutorial' and ord < (select ord from quest_defs where id = 'party_clear')`)
  await S.db.query(`update player_state set tut_state = 'active', tut_step = 3 where player_id = $1`, [b.id])
  const lich = { quest: 'lich', diff: 1, hero: { id: 'hans', hp: 500, atk: 40 } }
  assert.equal((await S.req('POST', '/v1/party/queue', { token: b.token, body: lich })).json.error, 'guide_locked')
  assert.equal((await S.req('POST', '/v1/party/lobby/create', { token: b.token, body: lich })).json.error, 'guide_locked')
  // a가 파티를 만들고 친구 b를 부르면: 목록에 잠김 표시, 초대는 거절
  await S.db.query('insert into friend_links (a, b, accepted) values ($1, $2, true)', [a.id, b.id])
  const cr = await S.req('POST', '/v1/party/lobby/create', { token: a.token, body: lich })
  assert.equal(cr.status, 200, 'a skipped guide is open')
  assert.equal((await S.req('POST', '/v1/party/lobby/join', { token: b.token, body: { code: cr.json.party.lobby.code, hero: lich.hero } })).json.error, 'guide_locked')
  const list = await S.req('GET', '/v1/party/invitable', { token: a.token })
  assert.equal(list.json.people[0].locked, true)
  assert.equal((await S.req('POST', '/v1/party/invite', { token: a.token, body: { to: b.id } })).json.error, 'their_locked')
  // 가이드가 파티 미션에 닿으면 열린다
  await S.db.query(`update player_state set tut_step = $2 where player_id = $1`, [b.id, n])
  assert.equal((await S.req('POST', '/v1/party/lobby/join', { token: b.token, body: { code: cr.json.party.lobby.code, hero: lich.hero } })).status, 200)
})

// 열린 run 하나를 바로 만든다(매칭 없이 — 결과 검사만 본다). match가 같으면 사람 여럿이 함께한 판
async function openRun(T: Setup, pid: string, o: { match?: string; dps: number; ago: number }) {
  const id = randomUUID()
  await T.db.query(`insert into party_runs (id, match_id, player_id, quest, diff, dps, boss_hp, started_at) values ($1, $2, $3, 'lich', 1, $4, $5, to_timestamp($6::float8))`,
    [id, o.match ?? randomUUID(), pid, o.dps, PQ.BOSS.lich.hp, T.clock.t - o.ago])
  return id
}
const winRun = (T: Setup, token: string, run: string, elapsed: number) => T.req('POST', '/v1/party/finish', { token, body: { run_id: run, win: true, elapsed } })

test('party finish: parallel finishes of many open runs give at most REWARD_CLEARS rings a day, and each result names a ring that was granted', async () => {
  let slow = false
  const T = await setup({
    wrapQuery: (q) => async (text, params) => {
      if (slow) await new Promise((r) => setTimeout(r, 1)) // 요청들이 서로 끼어들게(PGlite만으로는 한 요청씩 돈다)
      return q(text, params)
    },
  })
  try {
    const p = await T.login()
    const runs: string[] = []
    for (let i = 0; i < 8; i++) runs.push(await openRun(T, p.id, { dps: 1000, ago: 100 }))
    slow = true
    const res = await Promise.all(runs.map((id) => winRun(T, p.token, id, 60)))
    slow = false
    assert.ok(res.every((r) => r.status === 200), JSON.stringify(res.map((r) => r.json)))
    const rings = (await T.db.query("select id from player_items where player_id = $1 and slot = 'ring'", [p.id])).map((r) => Number(r.id)).sort()
    const named = res.flatMap((r) => r.json.result.rewards.items ?? []).map((it: any) => Number(it.id)).sort()
    assert.equal(rings.length, PQ.REWARD_CLEARS, 'the daily cap holds')
    assert.deepEqual(named, rings, 'results name exactly the rings in the bag')
    assert.ok(res.every((r) => r.json.result.win === true))
    assert.equal(res.filter((r) => r.json.result.no_reward).length, runs.length - PQ.REWARD_CLEARS)
    assert.equal((await T.req('GET', '/v1/party', { token: p.token })).json.party.quests.lich.clears_left, 0)
  } finally {
    await T.close()
  }
})

test('party: a new run closes my other open runs (re-queueing after a match started cannot stack open runs)', async () => {
  const p = await player()
  const liveRun = async () => {
    assert.equal((await queueLich(p)).status, 200)
    const c = await S.req('POST', '/v1/test/party_bots_now', { token: p.token })
    const acc = await S.req('POST', '/v1/party/accept', { token: p.token, body: { match_id: c.json.party.queue.match_id, accept: true } })
    assert.equal(acc.json.party.queue.state, 'live', JSON.stringify(acc.json.party.queue))
    return acc.json.party.queue.run_id as string
  }
  const first = await liveRun()
  const second = await liveRun() // 앞 판을 끝내지 않고 다시 매칭
  assert.notEqual(first, second)
  const rows = await S.db.query('select id::text as id, closed from party_runs where player_id = $1', [p.id])
  assert.deepEqual(Object.fromEntries(rows.map((r) => [r.id, r.closed])), { [first]: true, [second]: false })
  S.clock.t += 170
  const old = await winRun(S, p.token, first, 170)
  assert.equal(old.json.result, null, 'the replaced run gives nothing')
  assert.equal(old.json.player.items.filter((it: any) => it.slot === 'ring').length, 0)
  assert.equal((await winRun(S, p.token, second, 170)).json.result.win, true)
})

test('party finish: alone with AI lords the win check is tighter (power slack SOLO_DPS_SLACK, real time >= elapsed); with another lord it stays DPS_SLACK', async () => {
  const hp = PQ.BOSS.lich.hp
  const e = hp / (100 * 5) // 초당 100: DPS_SLACK(8)로는 되고 SOLO_DPS_SLACK(3)로는 안 되는 시간
  assert.ok(100 * e * PQ.DPS_SLACK >= hp && 100 * e * PQ.SOLO_DPS_SLACK < hp)
  const a = await S.login()
  assert.equal((await winRun(S, a.token, await openRun(S, a.id, { dps: 100, ago: 60 }), e)).json.result.win, false, 'too weak for a solo win')
  assert.equal((await winRun(S, a.token, await openRun(S, a.id, { dps: 1000, ago: 60 }), 100)).json.result.win, false,
    '100 s of battle in 60 s of real time (party battles are always x1)')
  const ok = await winRun(S, a.token, await openRun(S, a.id, { dps: 1000, ago: 105 }), 100)
  assert.equal(ok.json.result.win, true)
  assert.equal(ok.json.result.rewards.items.length, 1)
  // run 행만 있는 두 번째 사람(부계정이 GET 한 번으로 run만 만든 경우)은 사람으로 세지 않는다 — 실시간 방에 들어온 사람만(2026-11-06 보안 점검)
  const b = await S.login()
  const c = await S.login()
  const match = randomUUID()
  const rb = await openRun(S, b.id, { match, dps: 100, ago: 60 })
  await openRun(S, c.id, { match, dps: 100, ago: 60 })
  assert.equal((await winRun(S, b.token, rb, e)).json.result.win, false)
})


test('party leave: leaving a match others still fight blocks matching until it ends; 3+ leaves in 24 h ban matching 10/30/60 min', async () => {
  assert.equal(PQ.leaveBanSec(2), 0)
  assert.deepEqual([3, 4, 5, 9].map(PQ.leaveBanSec), [600, 1800, 3600, 3600])
  const a = await player()
  const b = await player()
  assert.equal((await queueLich(a)).status, 200)
  assert.equal((await queueLich(b)).status, 200)
  const c = await S.req('POST', '/v1/test/party_bots_now', { token: a.token })
  const mid = c.json.party.queue.match_id
  assert.equal(c.json.party.queue.seats.filter((s: any) => !s.bot).length, 2, JSON.stringify(c.json.party.queue))
  await S.req('POST', '/v1/party/accept', { token: a.token, body: { match_id: mid, accept: true } })
  const rb = (await S.req('POST', '/v1/party/accept', { token: b.token, body: { match_id: mid, accept: true } })).json.party.queue
  const ra = (await S.req('GET', '/v1/party', { token: a.token })).json.party.queue
  assert.equal(ra.state, 'live')
  assert.equal(rb.state, 'live')
  S.clock.t += 30
  // a가 중간에 나간다(포기 = 패배 결과)
  const fa = await S.req('POST', '/v1/party/finish', { token: a.token, body: { run_id: ra.run_id, win: false, elapsed: 30 } })
  assert.equal(fa.status, 200, JSON.stringify(fa.json))
  assert.equal(fa.json.party.queue.state, 'idle')
  assert.equal(fa.json.party.block.reason, 'match_running')
  assert.ok(fa.json.party.block.left > 0 && fa.json.party.block.left <= PQ.TIME_LIMIT.lich + PQ.LEFT_SLACK_SEC)
  const again = await queueLich(a)
  assert.equal(again.status, 409)
  assert.equal(again.json.error, 'match_running', JSON.stringify(again.json))
  assert.equal((await S.db.query('select 1 from party_leaves where player_id = $1', [a.id])).length, 1)
  // 남은 b가 판을 끝내면 a는 다시 매칭할 수 있다(1번은 제한 없음). b는 탈주가 아니다
  const fb = await S.req('POST', '/v1/party/finish', { token: b.token, body: { run_id: rb.run_id, win: false, elapsed: 60 } })
  assert.equal(fb.status, 200)
  assert.equal(fb.json.party.block, null)
  assert.equal((await S.req('GET', '/v1/party', { token: a.token })).json.party.block, null)
  assert.equal((await S.db.query('select 1 from party_leaves where player_id = $1', [b.id])).length, 0)
  // 24시간 안에 3번째 탈주 → 10분 매칭 제한
  await S.db.query('insert into party_leaves (player_id, at) values ($1, to_timestamp($2::float8)), ($1, to_timestamp($2::float8))', [a.id, S.clock.t])
  const v = await S.req('GET', '/v1/party', { token: a.token })
  assert.deepEqual(v.json.party.block, { reason: 'leave_penalty', left: 600 })
  const q = await queueLich(a)
  assert.equal(q.status, 409)
  S.clock.t += 601
  assert.equal((await S.req('GET', '/v1/party', { token: a.token })).json.party.block, null)
  assert.equal((await queueLich(a)).status, 200)
})
// 가짜 소켓(방이 쓰는 ws.WebSocket 부분만). close·terminate의 'close'는 진짜처럼 다음 틱에 온다
function fakeWs() {
  const ws = Object.assign(new EventEmitter(), {
    readyState: 1, bufferedAmount: 0, sent: [] as any[], pings: 0, dead: false, closed: false,
    send(s: string) { ws.sent.push(JSON.parse(s)) },
    ping() { ws.pings++ },
    terminate() { ws.dead = true; ws.shut() },
    close() { ws.closed = true; ws.shut() },
    shut() { ws.readyState = 2; setImmediate(() => { ws.readyState = 3; ws.emit('close') }) },
  })
  return ws
}
const tick = () => new Promise((r) => setImmediate(r))

test('party live room: slow readers are cut, the heartbeat drops dead connections, ended or removed matches close their rooms', async () => {
  const live = new PartyLive()
  const matches = new Set(['m1', 'm2'])
  live.seatOf = (m) => (matches.has(m) ? 0 : -1)
  try {
    const [a, b, c] = [fakeWs(), fakeWs(), fakeWs()]
    live.join('m1', 'pa', a as any)
    live.join('m1', 'pb', b as any)
    live.join('m1', 'pc', c as any)
    assert.equal(a.sent[0].host, true)
    // 받지 못하고 1 MB 넘게 쌓인 연결은 더 보내지 않고 끊는다
    b.bufferedAmount = MAX_BUFFER + 1
    a.emit('message', JSON.stringify({ t: 'snap', s: { c: 1 } }))
    assert.ok(c.sent.some((m) => m.t === 'snap'))
    assert.ok(b.dead && !b.sent.some((m) => m.t === 'snap'))
    await tick()
    // 심장 박동: ping, 다음 박동까지 pong이 없으면 끊는다
    live.sweep()
    assert.deepEqual([a.pings, c.pings], [1, 1])
    a.emit('pong')
    live.sweep()
    assert.deepEqual([a.dead, c.dead, a.pings], [false, true, 2])
    await tick()
    // 매치가 없어지면(모두 끝냈다·30분) 방을 닫는다
    matches.delete('m1')
    live.sweep()
    assert.ok(a.closed && !live.rooms.has('m1'))
    // 끝난 방: end를 읽을 박동 하나를 주고 닫는다
    const [d, e] = [fakeWs(), fakeWs()]
    live.join('m2', 'pd', d as any)
    live.join('m2', 'pe', e as any)
    d.emit('message', JSON.stringify({ t: 'end', win: true, elapsed: 50 }))
    assert.ok(e.sent.some((m) => m.t === 'end'))
    live.sweep()
    d.emit('pong')
    e.emit('pong')
    assert.equal(e.closed, false, 'one beat to read end')
    live.sweep()
    assert.deepEqual([d.closed, e.closed, live.rooms.size], [true, true, 0])
  } finally {
    live.close()
  }
})

test('party recruit: [파티원 모집] posts an invite card in the all chat, others join from it (also while matching), cards close when full', async () => {
  const a = await player()
  const b = await player()
  const c = await player()
  const lich = { quest: 'lich', diff: 1, hero: { id: 'hans', hp: 500, atk: 40 } }
  // 파티가 없으면 만들고 올린다
  const r1 = await S.req('POST', '/v1/party/recruit', { token: a.token, body: lich })
  assert.equal(r1.status, 200, JSON.stringify(r1.json))
  const code = r1.json.party.lobby.code
  assert.equal(r1.json.party.lobby.leader, true)
  assert.deepEqual(r1.json.msg.party, { code, quest: 'lich', diff: 1, open: true, count: 1, size: 4 })
  assert.ok(r1.json.msg.text.includes('[파티 모집]') && r1.json.msg.text.includes(code), r1.json.msg.text)
  // 다른 성주의 채팅에도 초대장으로 보인다
  const seen = await S.req('GET', '/v1/chat', { token: b.token })
  const card = seen.json.all.find((m: any) => m.id === r1.json.msg.id)
  assert.equal(card.party.code, code)
  assert.equal(card.me, false)
  // 같은 파티는 RECRUIT_GAP_SEC에 한 번
  S.clock.t += 3
  const again = await S.req('POST', '/v1/party/recruit', { token: a.token, body: {} })
  assert.equal(again.json.error, 'recruit_wait', JSON.stringify(again.json))
  // 방장이 매칭을 시작해도(사람만 기다린다) 초대장으로 들어온 사람은 같은 대기에 붙는다
  const st = await S.req('POST', '/v1/party/lobby/start', { token: a.token, body: { diff: 1 } })
  assert.equal(st.json.party.queue.state, 'queued')
  assert.equal(st.json.party.queue.bots, false)
  assert.equal(st.json.party.queue.bot_in, 0)
  const jb = await S.req('POST', '/v1/party/lobby/join', { token: b.token, body: { code: card.party.code, hero: lich.hero } })
  assert.equal(jb.status, 200, JSON.stringify(jb.json))
  assert.equal(jb.json.party.queue.state, 'queued', 'joined the running queue')
  for (let i = 0; i < PQ.RECRUIT_GAP_SEC / 10; i++) {
    S.clock.t += 10
    await S.req('GET', '/v1/party', { token: a.token })
    await S.req('GET', '/v1/party', { token: b.token })
  }
  const r2 = await S.req('POST', '/v1/party/recruit', { token: b.token, body: {} })
  assert.equal(r2.status, 200, 'any member can recruit')
  assert.equal(r2.json.msg.party.count, 2)
  for (let i = 0; i < 9; i++) {  // 앱이 대기 중 계속 묻는다
    S.clock.t += 10
    await S.req('GET', '/v1/party', { token: b.token })
    assert.equal((await S.req('GET', '/v1/party', { token: a.token })).json.party.queue.state, 'queued', 'no AI lords fill the seats')
  }
  // 두 사람 더 → 자리가 다 차서 매치, 옛 초대장은 닫힌다
  await S.req('POST', '/v1/party/lobby/join', { token: c.token, body: { code, hero: lich.hero } })
  const d = await player()
  const jd = await S.req('POST', '/v1/party/lobby/join', { token: d.token, body: { code, hero: lich.hero } })
  assert.equal(jd.json.party.queue.state, 'confirm', JSON.stringify(jd.json.party.queue))
  assert.ok(jd.json.party.queue.seats.every((s: any) => !s.bot))
  const after = await S.req('GET', '/v1/chat', { token: d.token })
  assert.equal(after.json.all.find((m: any) => m.id === r1.json.msg.id).party.open, false)
  const e = await player()
  const late = await S.req('POST', '/v1/party/lobby/join', { token: e.token, body: { code, hero: lich.hero } })
  assert.equal(late.json.error, 'full')
  // 혼자 매칭 중에 모집: 그 대기가 파티 대기가 된다
  const q = await queueLich(e)
  assert.equal(q.json.party.queue.state, 'queued')
  const r3 = await S.req('POST', '/v1/party/recruit', { token: e.token, body: {} })
  assert.equal(r3.status, 200, JSON.stringify(r3.json))
  assert.equal(r3.json.party.queue.state, 'queued')
  assert.equal(r3.json.party.lobby.leader, true)
  // 채팅 금지면 못 올린다
  const f = await player()
  await S.db.query(`insert into chat_mutes (player_id, until, reason, at) values ($1, null, 't', now())`, [f.id])
  const muted = await S.req('POST', '/v1/party/recruit', { token: f.token, body: lich })
  assert.equal(muted.json.error, 'muted')
})

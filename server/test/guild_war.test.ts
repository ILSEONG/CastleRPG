// 길드전(공성전, 마이그레이션 021, guild_war.ts·war_routes.ts·war_live.ts): 규칙(주·상대·성 합치기·점수), 수비 영웅, 전투 열기·합류·끝,
// 한 주 한 번(길드원이 시각을 정한다, 기본 토요일 21:00), 주간 보상, 실시간 방(방장·중계·명령·방장 넘김·끝 저장).
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import { serve } from '@hono/node-server'
import * as W from '../src/guild_war.ts'
import { WarLive } from '../src/war_live.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup()
})
after(async () => {
  await S.close()
})

const setStage = (id: string, n: number) => S.db.query('update player_state set stage = $2 where player_id = $1', [id, n])
const STARTERS = ['hans', 'ella', 'dorik', 'nina']
const squad = (hp = 500, atk = 30) => STARTERS.map((id) => ({ id, hp, atk }))

async function member(gid?: string) {
  const p = await S.login()
  await setStage(p.id, 11)
  if (!gid) {
    const g = (await S.req('GET', '/v1/guild', { token: p.token })).json.guild
    gid = g.recommendations[0].id
  }
  const r = await S.req('POST', '/v1/guild/join', { token: p.token, body: { guild_id: gid } })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  return { ...p, gid: gid! }
}

const war = async (token: string) => (await S.req('GET', '/v1/guild/war', { token })).json.war
const HOUR = 15 // 테스트 서버 리셋 시(UTC) = 00:00 KST
const resetAt = (d: number) => d * 86400 + HOUR * 3600
// t가 든 주의 기본 공성 시각(토요일 21:00 KST)
const defaultAt = (t: number) => W.battleAt(W.weekOf(Math.floor((t - HOUR * 3600) / 86400)), null, resetAt)

test('war rules: monday weeks, deterministic enemy, castle only goes down', () => {
  // 리셋 날 3 = KST 1970-01-05(월)
  assert.equal(W.weekOf(3), W.weekOf(9))
  assert.notEqual(W.weekOf(2), W.weekOf(3))
  assert.equal(W.dayInWeek(3), 0)
  const cfg = (k: string) => ({ hero_level_stat: 0.042, hero_level_stat_melee: 0.0315, promote_mult: 1.3, hero_max_level_base: 20, hero_max_level_per_promotion: 10 } as Record<string, number>)[k]
  const heroes = [
    { id: 'a', role: 'melee', hp: 900, atk: 30, atk_interval: 0.8, grade: 'R' }, { id: 'b', role: 'ranged', hp: 400, atk: 40, atk_interval: 1.0, grade: 'R' },
    { id: 'c', role: 'melee', hp: 700, atk: 35, atk_interval: 1.0, grade: 'SR' }, { id: 'd', role: 'ranged', hp: 450, atk: 38, atk_interval: 1.2, grade: 'SR' },
    { id: 'e', role: 'melee', hp: 800, atk: 33, atk_interval: 0.9, grade: 'SSR' },
  ]
  const f = W.fitHero(heroes[0], 400, cfg)
  assert.ok(Math.abs(W.heroPower(heroes[0], f.level, f.promotion, cfg) - 400) < 30)
  const e1 = W.enemyGuild(42, 15, 800, heroes, cfg)
  assert.deepEqual(e1, W.enemyGuild(42, 15, 800, heroes, cfg), 'same seed → same enemy')
  assert.equal(e1.defenders.length, 60)
  assert.deepEqual([0, 1, 2, 3].map((l) => e1.defenders.filter((d) => d.lane === l).length), [16, 16, 16, 12])
  assert.ok(e1.members.every((m) => m.power >= 800 * 0.85 - 1 && m.power <= 800 * 1.15 + 1))
  const c0 = W.freshCastle(e1.defenders)
  const c1 = W.mergeCastle(c0, { gates: [0, c0.gates[1] + 999, -5, 'x'], keep: c0.keep - 100, defenders: { 1: 0, 2: 0.5, 999: 0, 3: 2 } }, e1.defenders)
  assert.equal(c1.gates[0], 0)
  assert.equal(c1.gates[1], c0.gates[1], 'a gate never heals')
  assert.equal(c1.gates[2], c0.gates[2], 'bad values are ignored')
  assert.equal(c1.keep, c0.keep - 100)
  assert.deepEqual(c1.dead, { 1: 0, 2: 0.5 })
  const c2 = W.mergeCastle(c1, { defenders: { 1: 1, 2: 0.7 } }, e1.defenders)
  assert.deepEqual(c2.dead, { 1: 0, 2: 0.5 }, 'defenders never come back')
  const mx = W.castleMax(e1.defenders)
  assert.equal(W.castlePoints(c2, mx.keep), 1 * W.PTS_KILL + 1 * W.PTS_GATE)
  // 점수: 처치 1 · 성문 10 · 성채 최대 체력 3%마다 1
  assert.equal(W.PTS_GATE, 10)
  assert.equal(W.keepPoints(mx.keep, mx.keep), 0)
  assert.equal(W.keepPoints(mx.keep * 0.97, mx.keep), 1)
  assert.equal(W.keepPoints(mx.keep * 0.9401, mx.keep), 1)
  assert.equal(W.keepPoints(mx.keep * 0.94, mx.keep), 2)
  assert.equal(W.keepPoints(0, mx.keep), 33)
  const ep = W.enemyPoints(7, 100, 1, W.castleCap(15))
  assert.ok(ep >= 0 && ep <= W.castleCap(15))
  assert.equal(ep, W.enemyPoints(7, 100, 1, W.castleCap(15)))
  // 공성 시각: 기본 토요일 21:00, 고른 시각은 그 주 안
  const wk = W.weekOf(3)
  assert.equal(W.battleAt(wk, null, resetAt), resetAt(W.weekStart(wk) + 5) + 21 * 3600)
  assert.equal(W.pickAt(wk, 6, 23, resetAt), resetAt(W.weekStart(wk) + 6) + 23 * 3600)
  assert.equal(W.pickAt(wk, 7, 0, resetAt), null)
  assert.equal(W.pickAt(wk, 0, 24, resetAt), null)
})

test('war: view, defense heroes, members pick the weekly time, enter opens the battle with AI squads, a second member joins', async () => {
  const a = await member()
  let w = await war(a.token)
  assert.equal(w.battle.state, 'waiting')
  assert.equal(w.schedule.at, defaultAt(S.clock.t), 'default: saturday 21:00')
  assert.equal(w.schedule.set, false)
  assert.equal((await S.req('POST', '/v1/guild/war/enter', { token: a.token, body: { heroes: squad() } })).json.error, 'not_yet')
  // 시각 정하기: 지금보다 뒤, 이번 주 안
  const nowDay = W.dayInWeek(Math.floor((S.clock.t - HOUR * 3600) / 86400))
  let s = await S.req('POST', '/v1/guild/war/schedule', { token: a.token, body: { day: nowDay, hour: 0 } })
  assert.equal(s.json.error, 'schedule_past')
  s = await S.req('POST', '/v1/guild/war/schedule', { token: a.token, body: { day: 6, hour: 20 } })
  assert.equal(s.status, 200, JSON.stringify(s.json))
  assert.equal(s.json.war.schedule.set, true)
  const at = s.json.war.schedule.at
  assert.equal(at, W.pickAt(W.weekOf(Math.floor((S.clock.t - HOUR * 3600) / 86400)), 6, 20, resetAt))
  assert.equal((await S.req('POST', '/v1/guild/war/schedule', { token: a.token, body: { day: 9, hour: 0 } })).status, 400)
  S.clock.t = at + 5
  assert.equal(w.castle.gates.length, 4)
  assert.ok(w.enemy.members >= 15 && w.castle.defenders === w.enemy.members * 4)
  assert.equal(w.points, 0)
  let r = await S.req('POST', '/v1/guild/war/defense', { token: a.token, body: { heroes: squad() } })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  assert.deepEqual(r.json.war.defense, STARTERS)
  assert.equal((await S.req('POST', '/v1/guild/war/defense', { token: a.token, body: { heroes: [{ id: 'arteon' }] } })).json.error, 'bad_heroes', 'only owned heroes')
  r = await S.req('POST', '/v1/guild/war/enter', { token: a.token, body: { heroes: squad(1e9, 1e9) } })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  const plan = r.json.plan
  assert.equal(plan.my_id, a.id)
  assert.equal(plan.duration, W.BATTLE_SEC)
  assert.ok(plan.defenders.length >= 60)
  const mine = plan.attackers.find((s: any) => s.owner === a.id)
  assert.ok(mine && !mine.ai && mine.heroes.length === 4)
  assert.ok(mine.heroes.every((h: any) => h.hp < 1e9 && h.atk < 1e9), 'stats are capped')
  assert.ok(plan.attackers.filter((s: any) => s.ai).length >= 10, 'virtual members attack as AI squads')
  assert.equal(r.json.war.battle.state, 'live')
  // 같은 길드 두 번째 길드원: 같은 전투에 합류
  const b = await member(a.gid)
  const r2 = await S.req('POST', '/v1/guild/war/enter', { token: b.token, body: { heroes: squad() } })
  assert.equal(r2.status, 200)
  assert.equal(r2.json.plan.battle_id, plan.battle_id)
  assert.ok(r2.json.plan.attackers.some((s: any) => s.owner === b.id))
  assert.ok(r2.json.plan.clock >= 0)
  // 다시 들어와도 분대는 하나
  const r3 = await S.req('POST', '/v1/guild/war/enter', { token: a.token, body: { heroes: squad() } })
  assert.equal(r3.json.plan.attackers.filter((s: any) => s.owner === a.id).length, 1)
  // 끝: 성 상태를 보내면 점수가 오르고 전투가 닫힌다
  const d1 = plan.defenders[0]
  const fin = await S.req('POST', '/v1/guild/war/finish', { token: a.token, body: { battle_id: plan.battle_id,
    state: { gates: [0, plan.gates[1].hp, plan.gates[2].hp, plan.gates[3].hp], keep: plan.keep.hp, defenders: { [d1.uid]: 0 } } } })
  assert.equal(fin.status, 200, JSON.stringify(fin.json))
  assert.equal(fin.json.war.points, W.PTS_KILL + W.PTS_GATE)
  assert.equal(fin.json.war.battle.state, 'done')
  assert.equal((await S.req('POST', '/v1/guild/war/enter', { token: b.token, body: { heroes: squad() } })).json.error, 'battle_done', 'one battle a week')
  assert.equal((await S.req('POST', '/v1/guild/war/schedule', { token: a.token, body: { day: 6, hour: 23 } })).json.error, 'schedule_locked')
  // 우리 공성 시간이 끝나면 상대 점수가 보인다
  assert.equal(fin.json.war.enemy_points, 0)
  S.clock.t = at + W.BATTLE_SEC + 1
  const after = await war(a.token)
  assert.equal(after.enemy_days.length, 1)
  assert.equal(after.enemy_points, after.enemy_days[0])
  S.clock.t = T0
})

test('war: weekly reward once', async () => {
  const a = await member()
  await war(a.token)
  S.clock.t += 8 * 86400
  const w = await war(a.token)
  assert.ok(w.claim, 'last week can be claimed')
  const before = (await S.req('GET', '/v1/player', { token: a.token })).json.player
  const r = await S.req('POST', '/v1/guild/war/claim', { token: a.token })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  const reward = r.json.result.reward
  assert.equal(r.json.player.diamonds, before.diamonds + reward.diamonds)
  assert.equal((await S.req('POST', '/v1/guild/war/claim', { token: a.token })).json.error, 'nothing')
  S.clock.t = T0
})

test('war live room: host relay, commands, host hand-over, end saves the castle', async () => {
  const live = new WarLive()
  const app = S.makeApp({ warLive: live })
  const server = serve({ fetch: app.fetch, port: 0, hostname: '127.0.0.1' })
  await new Promise((r) => server.once('listening', r))
  live.attach(server as any)
  const port = (server.address() as any).port
  const req = async (method: string, path: string, token: string, body?: unknown) => {
    const res = await app.request(path, { method, headers: { authorization: `Bearer ${token}`, ...(body ? { 'content-type': 'application/json' } : {}) },
      body: body ? JSON.stringify(body) : undefined })
    return { status: res.status, json: await res.json() as any }
  }
  S.clock.t = defaultAt(T0 + 7 * 86400) + 5 // 다음 주 기본 공성 시각(앞 테스트가 이번 주 전투를 닫았다)
  try {
    const a = await member()
    const b = await member(a.gid)
    const ea = await req('POST', '/v1/guild/war/enter', a.token, { heroes: squad() })
    assert.equal(ea.status, 200, JSON.stringify(ea.json))
    const pa = ea.json.plan
    const pb = (await req('POST', '/v1/guild/war/enter', b.token, { heroes: squad() })).json.plan
    assert.equal(pa.battle_id, pb.battle_id)
    assert.equal(pa.live, '/v1/guild/war/live')
    const open = (token: string) => new Promise<{ ws: WebSocket; msgs: any[] }>((res, rej) => {
      const ws = new WebSocket(`ws://127.0.0.1:${port}${pa.live}?battle=${pa.battle_id}&token=${token}`)
      const msgs: any[] = []
      ws.onmessage = (e) => msgs.push(JSON.parse(String(e.data)))
      ws.onopen = () => res({ ws, msgs })
      ws.onerror = () => rej(new Error('ws error'))
    })
    const until = async (f: () => boolean) => {
      for (let i = 0; i < 100 && !f(); i++) await new Promise((r) => setTimeout(r, 20))
      assert.ok(f())
    }
    const A = await open(a.token)
    await until(() => A.msgs.length > 0)
    assert.deepEqual(A.msgs[0], { t: 'hello', host: true, snap: null })
    const B = await open(b.token)
    await until(() => B.msgs.length > 0)
    assert.equal(B.msgs[0].host, false)
    A.ws.send(JSON.stringify({ t: 'snap', s: { c: 1.5 } }))
    await until(() => B.msgs.some((m) => m.t === 'snap'))
    B.ws.send(JSON.stringify({ t: 'cmd', uid: 1001, pos: [1, 2] }))
    await until(() => A.msgs.some((m) => m.t === 'cmd'))
    assert.deepEqual(A.msgs.find((m) => m.t === 'cmd'), { t: 'cmd', from: b.id, uid: 1001, pos: [1, 2] })
    B.ws.send(JSON.stringify({ t: 'snap', s: { c: 9 } }))  // 방장이 아니면 무시
    await new Promise((r) => setTimeout(r, 60))
    assert.equal(A.msgs.filter((m) => m.t === 'snap').length, 0)
    // 다른 길드 사람·토큰 없음은 못 들어온다
    const outsider = await member()
    await assert.rejects(open(outsider.token))
    // 방장이 나가면 B가 이어받는다(마지막 스냅샷과 함께)
    A.ws.close()
    await until(() => B.msgs.some((m) => m.t === 'host'))
    assert.deepEqual(B.msgs.find((m) => m.t === 'host').snap, { c: 1.5 })
    const d1 = pb.defenders[0]
    B.ws.send(JSON.stringify({ t: 'end', state: { defenders: { [d1.uid]: 0 }, gates: [pb.gates[0].hp, 0, pb.gates[2].hp, pb.gates[3].hp], keep: pb.keep.hp } }))
    await until(() => B.msgs.some((m) => m.t === 'end'))
    const w = (await req('GET', '/v1/guild/war', b.token)).json.war
    assert.equal(w.points, W.PTS_KILL + W.PTS_GATE)
    assert.equal(w.battle.state, 'done')
    B.ws.close()
  } finally {
    live.close()
    server.close()
    S.clock.t = T0
  }
})

test('war: super admin opens the siege any time, and a finished week opens again with a fresh castle', async () => {
  S.clock.t = T0
  const a = await member()
  const mate = await member(a.gid)
  await S.db.query("insert into admin_emails (email) values ('war-admin@example.com') on conflict do nothing")
  await S.db.query("insert into player_identities (provider, provider_uid, player_id, email) values ('google', 'war-admin', $1, 'war-admin@example.com')", [a.id])
  assert.ok(S.clock.t < defaultAt(S.clock.t))
  assert.equal((await S.req('POST', '/v1/guild/war/enter', { token: mate.token, body: { heroes: squad() } })).json.error, 'not_yet') // 보통 길드원은 그대로
  const r = await S.req('POST', '/v1/guild/war/enter', { token: a.token, body: { heroes: squad() } })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  assert.ok(r.json.plan.attackers.some((s: any) => s.ai)) // 실제 사람이 없는 자리는 AI 분대
  const id1 = r.json.plan.battle_id
  const fin = await S.req('POST', '/v1/guild/war/finish', { token: a.token, body: { battle_id: id1, state: { keep: 0 } } })
  assert.equal(fin.json.war.battle.state, 'done')
  assert.equal((await S.req('POST', '/v1/guild/war/enter', { token: mate.token, body: { heroes: squad() } })).json.error, 'conquered')
  const again = await S.req('POST', '/v1/guild/war/enter', { token: a.token, body: { heroes: squad() } })
  assert.equal(again.status, 200, JSON.stringify(again.json))
  assert.notEqual(again.json.plan.battle_id, id1)
  assert.equal(again.json.plan.keep.hp, again.json.plan.keep.max) // 새 성
})

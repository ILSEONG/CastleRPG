// 랭킹(server/src/ranking.ts): 스테이지(값·동점 순서·내 순위), 전투력, 길드(주간 드래곤 피해·정산 우편·장비 상자), 캐시, 입력 검사.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as G from '../src/guild.ts'
import * as R from '../src/rules.ts'
import * as Rk from '../src/ranking.ts'
import { RANK_CACHE_SEC, sortEntries } from '../src/ranking.ts'
import { setup } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup()
})
after(async () => {
  await S.close()
})

const rank = async (token: string, board: string) => (await S.req('GET', `/v1/ranking/${board}`, { token })).json
const skip = () => (S.clock.t += RANK_CACHE_SEC + 1) // 캐시를 넘긴다
const setStage = (id: string, n: number, t: number) =>
  S.db.query('update player_state set stage = $2, last_stage_clear = to_timestamp($3::float8) where player_id = $1', [id, n, t])

test('ranking: sort order is value, then tie, then earlier time', () => {
  const xs = sortEntries([
    { key: 'a', name: 'a', value: 5, t: 20 },
    { key: 'b', name: 'b', value: 7, t: 30 },
    { key: 'c', name: 'c', value: 5, t: 10 },
    { key: 'd', name: 'd', value: 5, t: 0, tie: 1 },
  ])
  assert.deepEqual(xs.map((x) => x.key), ['b', 'd', 'c', 'a'])
})

test('ranking: stage board orders real players, ties go to who got there first, me is marked', async () => {
  const a = await S.login()
  const b = await S.login()
  const c = await S.login()
  await setStage(a.id, 900, S.clock.t - 100)
  await setStage(b.id, 950, S.clock.t - 50)
  await setStage(c.id, 900, S.clock.t - 200)
  skip()
  const r = await rank(a.token, 'stage')
  assert.equal(r.board, 'stage')
  assert.deepEqual(r.top.slice(0, 3).map((e: any) => [e.name, e.value]), [[G.playerName(b.id), 950], [G.playerName(c.id), 900], [G.playerName(a.id), 900]])
  assert.deepEqual(r.me, { rank: 3, name: G.playerName(a.id), value: 900, me: true })
  assert.equal(r.top[2].me, true)
  assert.equal(r.top[0].me, false)
  assert.ok(r.total >= 3)
})

test('ranking: power board uses deployed heroes; dungeon boards are gone', async () => {
  const p = await S.login()
  skip()
  const pw = await rank(p.token, 'power')
  assert.ok(pw.me && pw.me.value > 0, 'starter heroes are deployed and have power')
  const before = pw.me.value
  await S.db.query(`update player_state set deploy = '[]'::jsonb where player_id = $1`, [p.id])
  skip()
  assert.equal((await rank(p.token, 'power')).me, null)
  assert.ok(before > 0)

  for (const b of ['dungeon_gold', 'dungeon_equip']) assert.equal((await S.req('GET', `/v1/ranking/${b}`, { token: p.token })).status, 400)
})

test('ranking: guild board = this week dragon damage (system guilds too), level/members shown, my boss damage adds to my guild', async () => {
  const p = await S.login()
  await setStage(p.id, 11, S.clock.t - 1000)
  const recs = (await S.req('GET', '/v1/guild', { token: p.token })).json.guild.recommendations
  assert.equal(recs.length, 5)
  skip()
  let r = await rank(p.token, 'guild')
  assert.ok(r.total >= 1)
  assert.equal(r.me, null)
  assert.equal(r.season.in_guild, false)
  assert.ok(r.season.ends_at > S.clock.t && r.season.ends_at - S.clock.t <= 7 * 86400)
  assert.deepEqual(r.season.rewards.map((x: any) => [x.from, x.to]), [[1, 1], [2, 10], [11, 100]])
  assert.deepEqual(r.season.boxes, R.EQUIP_BOXES)
  for (const e of r.top) assert.ok(e.value > 0 && e.level >= 1 && e.members >= 1 && typeof e.emblem === 'number')
  for (let i = 1; i < r.top.length; i++) assert.ok(r.top[i - 1].value >= r.top[i].value)
  const rec = recs[0]
  assert.equal((await S.req('POST', '/v1/guild/join', { token: p.token, body: { guild_id: rec.id } })).status, 200)
  const before = (await S.db.query('select coalesce(sum(dmg), 0)::int as d from guild_week_damage where guild_id = $1', [rec.id]))[0].d
  const run = (await S.req('POST', '/v1/guild/boss/start', { token: p.token })).json.result
  S.clock.t += G.BOSS_FIGHT_SEC
  assert.equal((await S.req('POST', '/v1/guild/boss/finish', { token: p.token, body: { run_id: run.run_id, dmg: 777 } })).json.result.dmg, 777)
  const after = (await S.db.query('select coalesce(sum(dmg), 0)::int as d from guild_week_damage where guild_id = $1', [rec.id]))[0].d
  assert.equal(after - before, 777)
  skip()
  r = await rank(p.token, 'guild')
  assert.equal(r.me.name, rec.name)
  assert.equal(r.season.in_guild, true)
  const st = await rank(p.token, 'stage')
  assert.equal(st.me.guild, rec.name)
})

test('ranking: when the week ends, every member of a top-100 guild gets one box mail; once only; the box opens into gear', async () => {
  const a = await S.login()
  const b = await S.login()
  for (const x of [a, b]) await setStage(x.id, 11, S.clock.t - 1000)
  const rec = (await S.req('GET', '/v1/guild', { token: a.token })).json.guild.recommendations[1]
  for (const x of [a, b]) assert.equal((await S.req('POST', '/v1/guild/join', { token: x.token, body: { guild_id: rec.id } })).status, 200)
  const run = (await S.req('POST', '/v1/guild/boss/start', { token: a.token })).json.result
  S.clock.t += G.BOSS_FIGHT_SEC
  await S.req('POST', '/v1/guild/boss/finish', { token: a.token, body: { run_id: run.run_id, dmg: 500 } })
  skip()
  const mine = (await rank(a.token, 'guild')).me
  assert.ok(mine, 'my guild is on the board')
  const ends = (await rank(a.token, 'guild')).season.ends_at
  S.clock.t = ends + 60
  const late = await S.login() // 주가 끝난 뒤 들어온 길드원은 지난 주 보상이 없다
  await setStage(late.id, 11, S.clock.t - 1000)
  await S.req('POST', '/v1/guild/join', { token: late.token, body: { guild_id: rec.id } })
  const mailsA = (await S.req('GET', '/v1/mail', { token: a.token })).json.mails.filter((m: any) => m.title.includes('길드 랭킹'))
  assert.equal(mailsA.length, 1)
  const m = mailsA[0]
  const finalRank = Number(/(\d+)위/.exec(m.body)?.[1]) // 주 끝까지 다른 길드도 피해를 쌓아 순위가 바뀔 수 있다
  assert.ok(finalRank >= 1 && finalRank <= 100)
  const want = Rk.guildReward(finalRank)
  assert.deepEqual(m.reward, want)
  assert.ok(m.body.includes(rec.name))
  assert.equal((await S.req('GET', '/v1/mail', { token: b.token })).json.mails.filter((x: any) => x.title.includes('길드 랭킹')).length, 1, 'members who did not hit also get it')
  assert.equal((await S.req('GET', '/v1/mail', { token: late.token })).json.mails.filter((x: any) => x.title.includes('길드 랭킹')).length, 0)
  await rank(a.token, 'guild') // 다시 정산해도 한 번만
  assert.equal((await S.req('GET', '/v1/mail', { token: a.token })).json.mails.filter((x: any) => x.title.includes('길드 랭킹')).length, 1)
  const got = await S.req('POST', '/v1/mail/claim', { token: a.token, body: { ids: [m.id] } })
  assert.equal(got.status, 200, JSON.stringify(got.json))
  const items = got.json.reward.items
  assert.equal(items.length, 1)
  const box = Object.keys(want!)[0].slice(R.EQUIP_BOX_PREFIX.length)
  assert.ok((R.EQUIP_BOXES[box][items[0].grade] ?? 0) > 0, `${items[0].grade} can come from the ${box} box`)
})

test('ranking: guild reward bands are 1 / 2-10 / 11-100, nothing after 100', () => {
  assert.deepEqual(Rk.guildReward(1), { equip_box_top: 1 })
  assert.deepEqual(Rk.guildReward(2), { equip_box_high: 1 })
  assert.deepEqual(Rk.guildReward(10), { equip_box_high: 1 })
  assert.deepEqual(Rk.guildReward(11), { equip_box_normal: 1 })
  assert.deepEqual(Rk.guildReward(100), { equip_box_normal: 1 })
  assert.equal(Rk.guildReward(101), null)
  for (const w of Object.values(R.EQUIP_BOXES)) assert.equal(Object.values(w).reduce((s, x) => s + x, 0), 100)
})

test('ranking: lists are cached for a short while', async () => {
  const p = await S.login()
  await setStage(p.id, 5000, S.clock.t - 10)
  skip()
  assert.equal((await rank(p.token, 'stage')).me.value, 5000)
  await setStage(p.id, 5001, S.clock.t - 5)
  assert.equal((await rank(p.token, 'stage')).me.value, 5000)
  skip()
  assert.equal((await rank(p.token, 'stage')).me.value, 5001)
})

test('ranking: unknown board is 400, no token is 401', async () => {
  const p = await S.login()
  assert.equal((await S.req('GET', '/v1/ranking/nope', { token: p.token })).status, 400)
  assert.equal((await S.req('GET', '/v1/ranking/stage')).status, 401)
})

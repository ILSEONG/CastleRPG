// 랭킹(server/src/ranking.ts): 스테이지(값·동점 순서·내 순위), 전투력, 던전, 길드(시스템 길드 포함·내 길드), 캐시, 입력 검사.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as G from '../src/guild.ts'
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

test('ranking: guild board lists system guilds with level/members/boss, and my guild once I join', async () => {
  const p = await S.login()
  await setStage(p.id, 11, S.clock.t - 1000)
  const recs = (await S.req('GET', '/v1/guild', { token: p.token })).json.guild.recommendations
  assert.equal(recs.length, 5)
  skip()
  let r = await rank(p.token, 'guild')
  assert.ok(r.total >= 5)
  assert.equal(r.me, null)
  for (const e of r.top) {
    assert.ok(e.value >= 1 && e.members >= 1 && e.boss >= 1 && typeof e.emblem === 'number')
  }
  for (let i = 1; i < r.top.length; i++) assert.ok(r.top[i - 1].value >= r.top[i].value)
  const rec = recs[0]
  const top = r.top.find((e: any) => e.name === rec.name)
  assert.equal(top.value, rec.level)
  assert.equal((await S.req('POST', '/v1/guild/join', { token: p.token, body: { guild_id: rec.id } })).status, 200)
  skip()
  r = await rank(p.token, 'guild')
  assert.equal(r.me.name, rec.name)
  assert.equal(r.me.members, top.members + 1)
  const st = await rank(p.token, 'stage')
  assert.equal(st.me.guild, rec.name)
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

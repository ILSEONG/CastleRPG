// 친구(2026-10-06): 친구 코드로 신청·수락·삭제, 서로 신청하면 바로 친구, 상한, 대표 영웅, 추천,
// 모집권 던전 도우미 = 오늘 안 쓴 친구의 영웅(키 "f:<id>") — 친구가 없거나 다 썼으면 시스템 후보 3.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as R from '../src/rules.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup()
})
after(async () => {
  await S.close()
})

const get = async (token: string) => (await S.req('GET', '/v1/friends', { token })).json
const post = (token: string, op: string, body: unknown) => S.req('POST', `/v1/friends/${op}`, { token, body })
const player = async (token: string) => (await S.req('GET', '/v1/player', { token })).json.player

async function fresh(heroes = ['hans', 'ella', 'dorik', 'nina', 'arteon']) {
  S.clock.t = T0
  const { token, id } = await S.login()
  for (const h of heroes) await S.db.query('insert into player_heroes (player_id, hero_id) values ($1, $2) on conflict do nothing', [id, h])
  await player(token)
  return { token, id }
}

test('이름·코드는 id에서 정해진다', () => {
  const id = '0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0'
  assert.equal(R.friendCode(id), '0F1E2D3C')
  assert.equal(R.friendName(id), R.friendName(id))
  assert.match(R.friendName(id), /^\S+$/)
})

test('친구 코드로 신청 → 상대 수락 → 친구, 삭제', async () => {
  const a = await fresh()
  const b = await fresh()
  const va = await get(a.token)
  assert.equal(va.code, R.friendCode(a.id))
  assert.equal(va.cap, R.FRIEND_CAP)
  assert.ok(va.hero && va.hero.hero_id)
  const vb = await get(b.token)
  assert.equal((await post(a.token, 'request', { code: 'ZZZZZZZZ' })).json.error, 'bad_request')
  assert.equal((await post(a.token, 'request', { code: va.code })).json.error, 'self')
  const r = await post(a.token, 'request', { code: vb.code.toLowerCase() })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  assert.equal(r.json.outgoing.length, 1)
  assert.equal(r.json.outgoing[0].id, b.id)
  assert.equal((await post(a.token, 'request', { code: vb.code })).json.error, 'already_requested')
  const inc = await get(b.token)
  assert.equal(inc.incoming.length, 1)
  assert.equal(inc.incoming[0].name, R.friendName(a.id))
  assert.equal((await post(a.token, 'accept', { id: b.id })).json.error, 'no_request') // 보낸 쪽은 수락 못 한다
  const ok = await post(b.token, 'accept', { id: a.id })
  assert.equal(ok.status, 200, JSON.stringify(ok.json))
  assert.equal(ok.json.friends.length, 1)
  assert.equal(ok.json.incoming.length, 0)
  assert.equal((await get(a.token)).friends[0].id, b.id)
  assert.equal((await post(a.token, 'request', { id: b.id })).json.error, 'already_friends')
  const rm = await post(a.token, 'remove', { id: b.id })
  assert.equal(rm.json.friends.length, 0)
  assert.equal((await get(b.token)).friends.length, 0)
  assert.equal((await post(a.token, 'remove', { id: b.id })).json.error, 'not_friend')
})

test('서로 신청하면 바로 친구, 추천에는 친구·나 빼고 최근 접속자', async () => {
  const a = await fresh()
  const b = await fresh()
  const rec = await get(a.token)
  assert.ok(!rec.recommend.some((x: any) => x.id === a.id))
  await post(a.token, 'request', { id: b.id })
  assert.ok(!(await get(a.token)).recommend.some((x: any) => x.id === b.id))
  const r = await post(b.token, 'request', { id: a.id })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  assert.equal(r.json.friends.length, 1)
})

test('대표 영웅: 고른 영웅, null이면 가장 강한 영웅, 없는 영웅 거부', async () => {
  const a = await fresh(['hans', 'ella', 'dorik'])
  await S.db.query("update player_heroes set level = 20 where player_id = $1 and hero_id = 'ella'", [a.id])
  assert.equal((await get(a.token)).hero.hero_id, 'ella')
  assert.equal((await post(a.token, 'hero', { hero_id: 'luna' })).json.error, 'not_owned')
  const r = await post(a.token, 'hero', { hero_id: 'hans' })
  assert.equal(r.json.hero.hero_id, 'hans')
  assert.equal(r.json.hero_chosen, 'hans')
  assert.equal((await post(a.token, 'hero', { hero_id: null })).json.hero.hero_id, 'ella')
})

test('상한: 친구 + 보낸 신청이 FRIEND_CAP이면 friend_full', async () => {
  const a = await fresh()
  for (let i = 0; i < R.FRIEND_CAP; i++) {
    const o = await fresh(['hans'])
    await S.db.query('insert into friend_links (a, b, accepted) values ($1, $2, $3)', [a.id, o.id, i % 2 === 0 || i > 20])
  }
  const c = await fresh()
  assert.equal((await post(a.token, 'request', { id: c.id })).json.error, 'friend_full')
  await S.db.query('update friend_links set accepted = true where a = $1', [a.id])
  assert.equal((await post(c.token, 'request', { id: a.id })).json.error, 'their_full')
})

test('모집권 던전: 친구가 있으면 도우미 = 친구 영웅(키 f:id), 클리어 뒤 그 친구는 오늘 못 쓰고 다 쓰면 시스템 후보', async () => {
  const a = await fresh()
  const b = await fresh(['luna', 'hans'])
  await S.db.query("update player_heroes set level = 15, promotion = 1 where player_id = $1 and hero_id = 'luna'", [b.id])
  await post(a.token, 'request', { id: b.id })
  await post(b.token, 'accept', { id: a.id })
  const t = (await player(a.token)).dungeons.ticket
  assert.equal(t.helpers.length, 1)
  const h = t.helpers[0]
  assert.equal(h.key, `f:${b.id}`)
  assert.deepEqual(h.friend, { id: b.id, name: R.friendName(b.id) })
  assert.equal(h.hero_id, 'luna')
  assert.equal(h.level, 15)
  assert.equal(h.promotion, 1)
  const party = ['hans', 'ella', 'dorik', 'nina']
  assert.equal((await S.req('POST', '/v1/dungeon/start', { token: a.token, body: { type: 'ticket', level: 1, party, helper: 'luna' } })).json.error, 'helper_unavailable')
  const s = await S.req('POST', '/v1/dungeon/start', { token: a.token, body: { type: 'ticket', level: 1, party, helper: h.key } })
  assert.equal(s.status, 200, JSON.stringify(s.json))
  assert.equal(s.json.helper.friend.id, b.id)
  await S.req('POST', '/v1/test/dungeon_age', { token: a.token, body: { run_id: s.json.run_id, seconds: 25 } })
  const f = await S.req('POST', '/v1/dungeon/finish', { token: a.token, body: { run_id: s.json.run_id, win: true, elapsed: 21 } })
  assert.equal(f.status, 200, JSON.stringify(f.json))
  const q = (await player(a.token)).dungeons.ticket
  assert.deepEqual(q.helpers_used, [`f:${b.id}`])
  assert.equal(q.helpers.length, 3) // 친구를 다 썼으니 시스템 후보
  assert.ok(q.helpers.every((x: any) => x.key === x.hero_id && !x.friend))
  assert.deepEqual((await get(a.token)).used_today, [b.id])
})

// 친구 다이아 선물(2026-11-05): 친구 한 명에게 하루 한 번 100개, 보내는 사람·받는 사람 각각 하루 3,000개(00:00 KST 초기화), 받는 친구는 우편으로 받는다.
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

const gift = (token: string, body: unknown) => S.req('POST', '/v1/friends/gift', { token, body })
const player = async (token: string) => (await S.req('GET', '/v1/player', { token })).json.player
const dia = async (id: string) => Number((await S.db.query('select diamonds from player_state where player_id = $1', [id]))[0].diamonds)

async function fresh(diamonds = 10_000) {
  const { token, id } = await S.login()
  await player(token)
  await S.db.query('update player_state set diamonds = $2 where player_id = $1', [id, diamonds])
  return { token, id }
}
const befriend = (a: string, b: string, accepted = true) => S.db.query('insert into friend_links (a, b, accepted) values ($1, $2, $3)', [a, b, accepted])

test('한 명에게 100개 → 내 다이아 −100, 친구 우편 +100, 같은 날 두 번은 gift_sent', async () => {
  S.clock.t = T0
  const a = await fresh()
  const b = await fresh(0)
  await befriend(b.id, a.id)
  const r = await gift(a.token, { id: b.id })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  assert.equal(r.json.gift_sent, 1)
  assert.equal(r.json.gift.per, R.FRIEND_GIFT_DIA)
  assert.equal(r.json.gift.cap, R.FRIEND_GIFT_DAILY)
  assert.equal(r.json.gift.sent, 100)
  assert.deepEqual(r.json.gift.sent_to, [b.id])
  assert.equal(await dia(a.id), 9_900)
  assert.equal((await gift(a.token, { id: b.id })).json.error, 'gift_sent')
  assert.equal(await dia(a.id), 9_900)
  // 받는 쪽: 목록에 '보낸 친구', 우편에 다이아 100
  const fb = (await S.req('GET', '/v1/friends', { token: b.token })).json
  assert.deepEqual(fb.gift.received_from, [a.id])
  const mails = (await S.req('GET', '/v1/mail', { token: b.token })).json.mails
  assert.equal(mails.length, 1)
  assert.deepEqual(mails[0].reward, { diamonds: 100 })
  assert.match(mails[0].body, new RegExp(R.friendName(a.id)))
  const c = await S.req('POST', '/v1/mail/claim', { token: b.token, body: { ids: [mails[0].id] } })
  assert.equal(c.status, 200, JSON.stringify(c.json))
  assert.equal(await dia(b.id), 100)
  // 받은 친구도 나에게 보낼 수 있다(서로 따로 센다)
  assert.equal((await gift(b.token, { id: a.id })).status, 200)
})

test('친구가 아니면(신청 중 포함) not_friend, 다이아가 모자라면 not_enough_diamonds', async () => {
  S.clock.t = T0
  const a = await fresh(99)
  const b = await fresh()
  const c = await fresh()
  await befriend(a.id, b.id)
  await befriend(a.id, c.id, false)
  assert.equal((await gift(a.token, { id: c.id })).json.error, 'not_friend')
  assert.equal((await gift(a.token, { id: b.id })).json.error, 'not_enough_diamonds')
  assert.equal(await dia(a.id), 99)
  assert.equal((await gift(a.token, {})).json.error, 'bad_request')
})

test('모두 보내기: 하루 3,000개(30명)를 넘지 않고, 다음 날 00:00 KST에 다시 보낼 수 있다', async () => {
  S.clock.t = T0
  const a = await fresh(1_000_000)
  const fs = []
  for (let i = 0; i < R.FRIEND_CAP; i++) {
    const o = await fresh(0)
    await befriend(a.id, o.id)
    fs.push(o)
  }
  assert.equal((await gift(a.token, { id: fs[0].id })).status, 200)
  const r = await gift(a.token, { all: true })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  assert.equal(r.json.gift_sent, R.FRIEND_CAP - 1)
  assert.equal(r.json.gift.sent, R.FRIEND_GIFT_DAILY)
  assert.equal(await dia(a.id), 1_000_000 - R.FRIEND_GIFT_DAILY)
  assert.equal((await gift(a.token, { all: true })).json.error, 'gift_cap')
  // 친구 하나를 지우고 새 친구를 사귀어도 오늘은 상한
  await S.db.query('delete from friend_links where a = $1 and b = $2', [a.id, fs[0].id])
  const n = await fresh(0)
  await befriend(a.id, n.id)
  assert.equal((await gift(a.token, { id: n.id })).json.error, 'gift_cap')
  const [{ sum }] = await S.db.query('select sum(amount)::int as sum from friend_gifts where sender = $1', [a.id])
  assert.equal(sum, R.FRIEND_GIFT_DAILY)
  // 다음 리셋(00:00 KST)
  const next = (await S.req('GET', '/v1/friends', { token: a.token })).json.gift.next_reset
  S.clock.t = next + 1
  const d = await gift(a.token, { id: n.id })
  assert.equal(d.status, 200, JSON.stringify(d.json))
  assert.equal(d.json.gift.sent, 100)
  assert.deepEqual(d.json.gift.sent_to, [n.id])
})

test('모두 보내기는 가진 다이아만큼만, 보낼 친구가 없으면 gift_none', async () => {
  S.clock.t = T0
  const a = await fresh(250)
  const os = []
  for (let i = 0; i < 3; i++) {
    const o = await fresh(0)
    await befriend(o.id, a.id)
    os.push(o)
  }
  const r = await gift(a.token, { all: true })
  assert.equal(r.json.gift_sent, 2)
  assert.equal(await dia(a.id), 50)
  const lone = await fresh()
  assert.equal((await gift(lone.token, { all: true })).json.error, 'gift_none')
})

test('동시에 보낸 선물도 하루 상한을 넘지 못한다', async () => {
  let slow = false
  const T = await setup({
    wrapQuery: (q) => async (text, params) => {
      if (slow) await new Promise((r) => setTimeout(r, 1))
      return q(text, params)
    },
  })
  try {
    const me = await T.login()
    await T.req('GET', '/v1/player', { token: me.token })
    await T.db.query('update player_state set diamonds = 100000 where player_id = $1', [me.id])
    const os = []
    for (let i = 0; i < 35; i++) {
      const o = await T.login()
      await T.db.query('insert into friend_links (a, b, accepted) values ($1, $2, true)', [me.id, o.id])
      os.push(o)
    }
    // 앞의 25명은 미리 보내 두고, 남은 10명에게 동시에(+ 같은 친구 두 번) 보낸다 → 5명만
    await T.db.query(`insert into friend_gifts (sender, receiver, day, amount)
      select $1, b, $2, 100 from friend_links where a = $1 order by created_at, b limit 25`, [me.id, R.resetDay(T.clock.t, 15)])
    const sent = (await T.db.query('select receiver::text as r from friend_gifts where sender = $1', [me.id])).map((x) => x.r)
    const rest = os.filter((o) => !sent.includes(o.id))
    slow = true
    const res = await Promise.all([...rest, rest[0]].map((o) => T.req('POST', '/v1/friends/gift', { token: me.token, body: { id: o.id } })))
    slow = false
    assert.equal(res.filter((r) => r.status === 200).length, 5, JSON.stringify(res.map((r) => r.json.error)))
    const [{ sum }] = await T.db.query('select sum(amount)::int as sum from friend_gifts where sender = $1', [me.id])
    assert.equal(sum, R.FRIEND_GIFT_DAILY)
    const [{ diamonds }] = await T.db.query('select diamonds from player_state where player_id = $1', [me.id])
    assert.equal(Number(diamonds), 100000 - 500)
  } finally {
    await T.close()
  }
})

test('받는 쪽도 하루 3,000개까지: 31번째 친구는 their_gift_full, 모두 보내기에서는 빠진다', async () => {
  S.clock.t = T0
  const r = await fresh(0)
  const givers = []
  for (let i = 0; i < 31; i++) {
    const o = await fresh(1000)
    await befriend(o.id, r.id)
    givers.push(o)
  }
  for (const o of givers.slice(0, 30)) assert.equal((await gift(o.token, { id: r.id })).status, 200)
  const last = givers[30]
  assert.equal((await gift(last.token, { id: r.id })).json.error, 'their_gift_full')
  assert.equal(await dia(last.id), 1000)
  const v = (await S.req('GET', '/v1/friends', { token: last.token })).json.gift
  assert.deepEqual(v.full, [r.id])
  const mine = (await S.req('GET', '/v1/friends', { token: r.token })).json.gift
  assert.equal(mine.received, R.FRIEND_GIFT_DAILY)
  // 모두 보내기: 가득 찬 친구는 빼고 보낸다
  const other = await fresh(0)
  await befriend(last.id, other.id)
  const a = await gift(last.token, { all: true })
  assert.equal(a.json.gift_sent, 1)
  assert.deepEqual(a.json.gift.sent_to, [other.id])
  assert.equal((await gift(last.token, { all: true })).json.error, 'gift_none')
  const [{ sum }] = await S.db.query('select sum(amount)::int as sum from friend_gifts where receiver = $1', [r.id])
  assert.equal(sum, R.FRIEND_GIFT_DAILY)
})

test('여러 친구가 한 사람에게 동시에 보내도 받는 쪽 3,000개를 넘지 않는다', async () => {
  let slow = false
  const T = await setup({
    wrapQuery: (q) => async (text, params) => {
      if (slow) await new Promise((r) => setTimeout(r, 1))
      return q(text, params)
    },
  })
  try {
    const me = await T.login()
    const gs = []
    for (let i = 0; i < 34; i++) {
      const o = await T.login()
      await T.req('GET', '/v1/player', { token: o.token })
      await T.db.query('update player_state set diamonds = 1000 where player_id = $1', [o.id])
      await T.db.query('insert into friend_links (a, b, accepted) values ($1, $2, true)', [o.id, me.id])
      gs.push(o)
    }
    await T.db.query(`insert into friend_gifts (sender, receiver, day, amount) select x, $1, $2, 100 from unnest($3::uuid[]) as x`,
      [me.id, R.resetDay(T.clock.t, 15), gs.slice(0, 26).map((o) => o.id)])
    slow = true
    const res = await Promise.all(gs.slice(26).map((o) => T.req('POST', '/v1/friends/gift', { token: o.token, body: { id: me.id } })))
    slow = false
    assert.equal(res.filter((r) => r.status === 200).length, 4, JSON.stringify(res.map((r) => r.json.error)))
    assert.ok(res.filter((r) => r.status !== 200).every((r) => r.json.error === 'their_gift_full'))
    const [{ sum }] = await T.db.query('select sum(amount)::int as sum from friend_gifts where receiver = $1', [me.id])
    assert.equal(sum, R.FRIEND_GIFT_DAILY)
  } finally {
    await T.close()
  }
})

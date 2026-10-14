// 빠른 두 번 탭(같은 요청 두 개가 같은 순간): 두 요청이 같은 version을 읽은 뒤 쓰기를 겨루게 하고(barrier), 한 번만 받거나 한 번만 빠지는지 본다.
// 보상 받기(미션·퀘스트·출석·우편·쿠폰), 구매(상점·결제·거래소), 길드(창설·기부).
import assert from 'node:assert/strict'
import { test } from 'node:test'
import * as G from '../src/guild.ts'
import * as M from '../src/missions.ts'
import { barrier, setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

type Res = Awaited<ReturnType<Setup['req']>>

// 같은 요청 두 개를 barrier로 겨루게 한다. 결과 두 개(상태 코드 오름차순).
async function race(S: Setup, b: ReturnType<typeof barrier>, send: () => Promise<Res>): Promise<Res[]> {
  b.arm()
  const rs = await Promise.all([send(), send()])
  assert.equal(b.arrived(), 2, 'both requests read the player before either wrote')
  return rs.sort((x, y) => x.status - y.status)
}
const logCount = async (S: Setup, id: string, kind: string) =>
  Number((await S.db.query('select count(*)::int as n from economy_log where player_id = $1 and kind = $2', [id, kind]))[0].n)
const player = async (S: Setup, token: string) => (await S.req('GET', '/v1/player', { token })).json.player

test('미션 받기 두 번 탭: 보상은 한 번(진 쪽 409 claimed), 로그 하나', async () => {
  const b = barrier()
  const S = await setup({ wrapQuery: b.wrap })
  try {
    S.clock.t = T0
    const { token, id } = await S.login()
    await S.req('POST', '/v1/test/events', { token, body: { events: Object.fromEntries(M.EVENTS.map((k) => [k, 1_000_000])) } })
    const g0 = (await player(S, token)).gold
    const [ok, lost] = await race(S, b, () => S.req('POST', '/v1/mission/claim', { token, body: { id: 'd_kill' } }))
    assert.equal(ok.status, 200, JSON.stringify(ok.json))
    assert.deepEqual([lost.status, lost.json.error], [409, 'claimed'])
    assert.equal((await player(S, token)).gold, g0 + 3000)
    assert.equal(await logCount(S, id, 'mission'), 1)
  } finally {
    await S.close()
  }
})

test('튜토리얼 퀘스트 받기 두 번 탭: 단계는 한 번만 오르고 보상도 한 번(진 쪽 409 stale)', async () => {
  const b = barrier()
  const S = await setup({ wrapQuery: b.wrap, tutorial: true })
  try {
    S.clock.t = T0
    const { token, id } = await S.login()
    const [ok, lost] = await race(S, b, () => S.req('POST', '/v1/quest/claim', { token, body: { type: 'tutorial', step: 0 } }))
    assert.equal(ok.status, 200, JSON.stringify(ok.json))
    assert.deepEqual([lost.status, lost.json.error], [409, 'stale'])
    assert.equal((await player(S, token)).quest.tut_step, 1)
    assert.equal(await logCount(S, id, 'quest'), 1)
  } finally {
    await S.close()
  }
})

test('출석 받기 두 번 탭: 하루치 한 번', async () => {
  const b = barrier()
  const S = await setup({ wrapQuery: b.wrap })
  try {
    S.clock.t = T0
    const { token, id } = await S.login()
    const [ok, lost] = await race(S, b, () => S.req('POST', '/v1/attendance/claim', { token, body: { day: 1 } }))
    assert.equal(ok.status, 200, JSON.stringify(ok.json))
    assert.equal(lost.status, 409)
    assert.equal((await player(S, token)).attendance.n, 1)
    assert.equal(await logCount(S, id, 'attendance'), 1)
  } finally {
    await S.close()
  }
})

test('상점 구매 두 번 탭(같은 n): 한 번만 사고 다이아도 한 번만 빠진다(진 쪽 409 stale)', async () => {
  const b = barrier()
  const S = await setup({ wrapQuery: b.wrap })
  try {
    S.clock.t = T0
    const { token, id } = await S.login()
    const dia = (await S.req('POST', '/v1/test/grant_diamonds', { token, body: { amount: 1000 } })).json.player.diamonds
    const [ok, lost] = await race(S, b, () => S.req('POST', '/v1/shop/buy', { token, body: { id: 'd_ticket', n: 0 } }))
    assert.equal(ok.status, 200, JSON.stringify(ok.json))
    assert.equal(lost.status, 409)
    const p = await player(S, token)
    assert.equal(p.diamonds, dia - 240)
    assert.deepEqual(p.shop.d, { d_ticket: 1 })
    assert.equal(await logCount(S, id, 'shop'), 1)
  } finally {
    await S.close()
  }
})

test('결제 영수증 두 번(같은 주문 번호가 동시에): 지급은 한 번, 다른 쪽은 already 또는 409 order_pending', async () => {
  // 주문 행(on conflict do nothing)이 먼저 겨룬다 — 진 쪽은 플레이어를 읽지 않으므로 barrier 없이 같은 틱에 보낸다
  const S = await setup()
  try {
    S.clock.t = T0
    const { token, id } = await S.login()
    const d0 = (await player(S, token)).diamonds
    const send = () => S.req('POST', '/v1/iap/purchase', { token, body: { product: 'dia_2', provider: 'test', order_id: 'tap' } })
    const [ok, other] = (await Promise.all([send(), send()])).sort((x, y) => x.status - y.status)
    assert.equal(ok.status, 200, JSON.stringify(ok.json))
    assert.ok(other.json.already === true || other.json.error === 'order_pending', JSON.stringify(other.json))
    if (other.status === 200 && !other.json.already) assert.fail('both requests granted the order')
    assert.equal((await player(S, token)).diamonds, d0 + 16000)
    assert.equal(await logCount(S, id, 'iap'), 1)
    // 지급이 끝난 뒤 다시 보내면 already
    const again = await S.req('POST', '/v1/iap/purchase', { token, body: { product: 'dia_2', provider: 'test', order_id: 'tap' } })
    assert.deepEqual([again.status, again.json.already], [200, true])
  } finally {
    await S.close()
  }
})

test('결제: 먼저 온 요청이 지급 전이면 같은 주문의 두 번째는 already가 아니라 409 order_pending(지급 없이 소비하지 않는다)', async () => {
  const S = await setup()
  try {
    S.clock.t = T0
    const { token, id } = await S.login()
    // 지급 전 상태를 만든다: 주문 행만 있고 economy_log iap가 없다
    await S.db.query("insert into iap_orders (order_id, player_id, product, provider, krw) values ('test:half', $1, 'dia_2', 'test', 0)", [id])
    const r = await S.req('POST', '/v1/iap/purchase', { token, body: { product: 'dia_2', provider: 'test', order_id: 'half' } })
    assert.deepEqual([r.status, r.json.error], [409, 'order_pending'])
  } finally {
    await S.close()
  }
})

test('우편 받기 두 번 탭: 보상은 한 번(진 쪽 409 claimed)', async () => {
  const b = barrier()
  const S = await setup({ wrapQuery: b.wrap })
  try {
    S.clock.t = T0
    const admin = await S.login()
    await S.db.query("insert into player_identities (provider, provider_uid, player_id, email) values ('google', 'tap-admin', $1, 'tap-admin@example.com')", [admin.id])
    await S.db.query("insert into admin_emails (email) values ('tap-admin@example.com') on conflict do nothing")
    const me = await S.login()
    const code = me.id.replace(/-/g, '').slice(0, 8).toUpperCase()
    assert.equal((await S.req('POST', '/v1/admin/mail', { token: admin.token, body: { to: code, title: '보상', body: '', reward: { diamonds: 300 } } })).status, 200)
    const d0 = (await player(S, me.token)).diamonds
    const mail = (await S.req('GET', '/v1/mail', { token: me.token })).json.mails[0]
    const [ok, lost] = await race(S, b, () => S.req('POST', '/v1/mail/claim', { token: me.token, body: { ids: [mail.id] } }))
    assert.equal(ok.status, 200, JSON.stringify(ok.json))
    assert.deepEqual([lost.status, lost.json.error], [409, 'claimed'])
    assert.equal((await player(S, me.token)).diamonds, d0 + 300)
    assert.equal(await logCount(S, me.id, 'mail'), 1)
  } finally {
    await S.close()
  }
})

test('쿠폰 두 번 탭(barrier): 계정당 한 번', async () => {
  const b = barrier()
  const S = await setup({ wrapQuery: b.wrap })
  try {
    S.clock.t = T0
    const { token, id } = await S.login()
    await S.db.query(`insert into coupons (code, reward, max_uses, created_at, starts_at, note) values ('RACE1', '{"diamonds": 70}'::jsonb, null,
      to_timestamp($1::float8), to_timestamp($1::float8), '')`, [T0 - 10])
    const d0 = (await player(S, token)).diamonds
    const [ok, lost] = await race(S, b, () => S.req('POST', '/v1/coupon', { token, body: { code: 'RACE1' } }))
    assert.equal(ok.status, 200, JSON.stringify(ok.json))
    assert.deepEqual([lost.status, lost.json.error], [409, 'coupon_used'])
    assert.equal((await player(S, token)).diamonds, d0 + 70)
    assert.equal(await logCount(S, id, 'coupon'), 1)
  } finally {
    await S.close()
  }
})

test('거래소 사기 두 번 탭: 장비 하나·값 한 번(진 쪽 409 sold_out)', async () => {
  const b = barrier()
  const S = await setup({ wrapQuery: b.wrap })
  try {
    S.clock.t = T0
    const seller = await S.login()
    const buyer = await S.login()
    await player(S, seller.token)
    await player(S, buyer.token)
    await S.db.query('update player_state set gold_tenths = $2 where player_id = $1', [buyer.id, 100_000 * 10])
    const [it] = await S.db.query("insert into player_items (player_id, slot, weapon_kind, grade, level) values ($1, 'hat', null, 'SR', 5) returning id", [seller.id])
    const item = Number(it.id)
    const l = await S.req('POST', '/v1/market/list', { token: seller.token, body: { item_id: item, currency: 'gold', price: 1000 } })
    assert.equal(l.status, 200, JSON.stringify(l.json))
    const listing = l.json.market.mine[0].id
    const [ok, lost] = await race(S, b, () => S.req('POST', '/v1/market/buy', { token: buyer.token, body: { id: listing, currency: 'gold', price: 1000 } }))
    assert.equal(ok.status, 200, JSON.stringify(ok.json))
    assert.deepEqual([lost.status, lost.json.error], [409, 'sold_out'])
    const p = await player(S, buyer.token)
    assert.equal(p.gold, 100_000 - 1000)
    assert.equal(p.items.filter((x: any) => x.id === item).length, 1)
    // 대금 받기 두 번: 한 번만
    const [c1, c2] = (await Promise.all([
      S.req('POST', '/v1/market/collect', { token: seller.token, body: {} }),
      S.req('POST', '/v1/market/collect', { token: seller.token, body: {} }),
    ])).sort((x, y) => x.status - y.status)
    assert.equal(c1.status, 200, JSON.stringify(c1.json))
    assert.deepEqual([c2.status, c2.json.error], [409, 'nothing_to_collect'])
    assert.equal(await logCount(S, buyer.id, 'market'), 1)
  } finally {
    await S.close()
  }
})

test('길드 창설 두 번 탭: 길드 하나, 골드 한 번(진 쪽 409 in_guild)', async () => {
  const b = barrier()
  const S = await setup({ wrapQuery: b.wrap })
  try {
    S.clock.t = T0
    const { token, id } = await S.login()
    await S.db.query('update player_state set stage = 11, gold_tenths = $2 where player_id = $1', [id, (G.CREATE_GOLD + 10) * 10])
    const [ok, lost] = await race(S, b, () => S.req('POST', '/v1/guild/create', { token, body: { name: '두번탭', emblem: 1 } }))
    assert.equal(ok.status, 200, JSON.stringify(ok.json))
    assert.deepEqual([lost.status, lost.json.error], [409, 'in_guild'])
    assert.equal((await player(S, token)).gold, 10)
    assert.equal(Number((await S.db.query('select count(*)::int as n from guilds where owner = $1', [id]))[0].n), 1)
  } finally {
    await S.close()
  }
})

test('길드 기부 두 번 탭(하루 1번인 다이아 기부): 한 번만 빠지고 한 번만 센다(진 쪽 409 donated)', async () => {
  const b = barrier()
  const S = await setup({ wrapQuery: b.wrap })
  try {
    S.clock.t = T0
    const { token, id } = await S.login()
    await S.db.query('update player_state set stage = 11, gold_tenths = $2, diamonds = 1000 where player_id = $1', [id, (G.CREATE_GOLD + 10) * 10])
    assert.equal((await S.req('POST', '/v1/guild/create', { token, body: { name: '기부길드', emblem: 1 } })).status, 200)
    const [ok, lost] = await race(S, b, () => S.req('POST', '/v1/guild/donate', { token, body: { kind: 'dia' } }))
    assert.equal(ok.status, 200, JSON.stringify(ok.json))
    assert.deepEqual([lost.status, lost.json.error], [409, 'donated'])
    assert.equal((await player(S, token)).diamonds, 1000 - G.DONATIONS.dia.diamonds)
    const [pg] = await S.db.query('select coins from player_guild where player_id = $1', [id])
    assert.equal(Number(pg.coins), G.DONATIONS.dia.coins)
  } finally {
    await S.close()
  }
})

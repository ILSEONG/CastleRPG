// 상점: POST /v1/shop/buy — 무료 선물·다이아·골드 상품, 기간 한도(sold_out), 재전송(stale), 모자람(not_enough), 일일·주간 리셋. 마이그레이션 028.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as SH from '../src/shop.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup()
})
after(async () => {
  await S.close()
})

const DAY = 86400
const buy = (token: string, id: string, n = 0) => S.req('POST', '/v1/shop/buy', { token, body: { id, n } })

test('shop.ts: 상품 id는 겹치지 않고 한도·가격이 맞다', () => {
  assert.equal(new Set(SH.ITEMS.map((x) => x.id)).size, SH.ITEMS.length)
  for (const x of SH.ITEMS) {
    assert.ok(x.limit >= 1)
    assert.equal(x.currency === 'free' || x.currency === 'ad', x.price === 0)
    assert.equal(x.currency === 'ad', x.tab === 'ad')
  }
})

test('무료 선물: 받으면 다이아 + 주머니, 같은 날 두 번은 sold_out, 다음 날 다시', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  const p0 = (await S.req('GET', '/v1/player', { token })).json.player
  assert.deepEqual(p0.shop.d, {})
  let r = await buy(token, 'd_free')
  assert.equal(r.status, 200)
  assert.equal(r.json.player.diamonds, p0.diamonds + 50)
  assert.equal(r.json.player.pouches.gold_60, (p0.pouches.gold_60 ?? 0) + 1)
  assert.deepEqual(r.json.player.shop.d, { d_free: 1 })
  assert.equal((await buy(token, 'd_free', 0)).json.error, 'sold_out')
  S.clock.t = T0 + DAY
  r = await buy(token, 'd_free', 0)
  assert.equal(r.status, 200)
  const logs = await S.db.query("select detail from economy_log where player_id = $1 and kind = 'shop'", [id])
  assert.equal(logs.length, 2)
})

test('다이아 상품: 모자라면 not_enough, 있으면 빼고 열쇠·모집권, n이 다르면 stale', async () => {
  S.clock.t = T0
  const { token } = await S.login()
  const d0 = (await S.req('GET', '/v1/player', { token })).json.player.diamonds
  assert.ok(d0 < 2400)
  assert.equal((await buy(token, 'w_tickets')).json.error, 'not_enough')
  let r = await S.req('POST', '/v1/test/grant_diamonds', { token, body: { amount: 1000 } })
  const dia = r.json.player.diamonds
  const tickets = r.json.player.dia_tickets
  r = await buy(token, 'd_ticket')
  assert.equal(r.status, 200)
  assert.equal(r.json.player.diamonds, dia - 240)
  assert.equal(r.json.player.dia_tickets, tickets + 1)
  const keys = r.json.player.dungeons.gold.keys
  r = await buy(token, 'd_key_gold', 0)
  assert.equal(r.json.player.dungeons.gold.keys, keys + 1)
  assert.equal((await buy(token, 'd_key_gold', 0)).json.error, 'stale')
  assert.equal((await buy(token, 'd_key_gold', 1)).status, 200)
  assert.equal((await buy(token, 'd_key_gold', 2)).status, 200)
  assert.equal((await buy(token, 'd_key_gold', 3)).json.error, 'sold_out')
  assert.equal((await buy(token, 'nope')).status, 404)
})

test('자원 꾸러미: 다이아를 빼고 자원, 주간 상품은 다음 주(월요일)까지 sold_out', async () => {
  S.clock.t = T0
  const { token } = await S.login()
  let r = await S.req('POST', '/v1/test/grant_diamonds', { token, body: { amount: 1000 } })
  const dia = r.json.player.diamonds
  const wood = r.json.player.res.wood
  r = await buy(token, 'w_res')
  assert.equal(r.status, 200)
  assert.equal(r.json.player.diamonds, dia - 300)
  assert.equal(r.json.player.res.wood, wood + 100000)
  assert.deepEqual(r.json.player.shop.w, { w_res: 1 })
  assert.equal((await buy(token, 'w_free')).status, 200)
  assert.equal((await buy(token, 'w_free', 0)).json.error, 'sold_out')
  S.clock.t = T0 + 7 * DAY
  assert.equal((await buy(token, 'w_free', 0)).status, 200)
})

test('광고 상품: 광고를 봐야(ad: true, 아니면 409 ad_required) 받고, 매일 한도, 광고 제거 구매자는 광고 없이 바로', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  const p0 = (await S.req('GET', '/v1/player', { token })).json.player
  assert.equal((await buy(token, 'a_dia')).json.error, 'ad_required')
  const ad = (n: number) => S.req('POST', '/v1/shop/buy', { token, body: { id: 'a_dia', n, ad: true } })
  for (let n = 0; n < 5; n++) assert.equal((await ad(n)).status, 200)
  assert.equal((await ad(5)).json.error, 'sold_out')
  let p = (await S.req('GET', '/v1/player', { token })).json.player
  assert.equal(p.diamonds, p0.diamonds + 500)
  assert.deepEqual(p.shop.d, { a_dia: 5 })
  const k = await S.req('POST', '/v1/shop/buy', { token, body: { id: 'a_key_gold', n: 0, ad: true } })
  assert.equal(k.status, 200)
  assert.equal((await S.req('POST', '/v1/iap/purchase', { token, body: { product: 'no_ads', provider: 'test', order_id: 'ad1' } })).status, 200)
  const r = await buy(token, 'a_ticket') // 광고 없이
  assert.equal(r.status, 200)
  assert.equal(r.json.player.dia_tickets, p0.dia_tickets + 1)
  S.clock.t = T0 + DAY
  p = (await S.req('GET', '/v1/player', { token })).json.player
  assert.deepEqual(p.shop.d, {})
  assert.equal((await buy(token, 'a_dia')).status, 200)
  const logs = await S.db.query("select detail from economy_log where player_id = $1 and kind = 'shop' order by id", [id])
  assert.equal(logs.at(-1).detail.ad, false)
  assert.equal(logs[0].detail.ad, true)
})

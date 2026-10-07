// 거래소(033): 올리기·내리기·사기·대금 받기, 수수료 10%, 한도·기한·장착·자기 판매·보관함·값 검사, 동시 구매는 한 사람만.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import type { Query } from '../src/db.ts'
import * as MK from '../src/market.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup()
})
after(() => S.close())

const player = async (token: string) => (await S.req('GET', '/v1/player', { token })).json.player
const post = (token: string, path: string, body: unknown = {}) => S.req('POST', `/v1/market/${path}`, { token, body })
const setWallet = (q: Query, id: string, gold: number, dia: number) =>
  q('update player_state set gold_tenths = $2, diamonds = $3 where player_id = $1', [id, gold * 10, dia])
async function addItem(q: Query, id: string, grade = 'SR', slot = 'hat'): Promise<number> {
  const [r] = await q('insert into player_items (player_id, slot, weapon_kind, grade, level) values ($1, $2, $3, $4, 5) returning id',
    [id, slot, slot === 'weapon' ? 'sword' : null, grade])
  return Number(r.id)
}
async function two() {
  S.clock.t = T0
  const a = await S.login()
  const b = await S.login()
  await player(a.token)
  await player(b.token)
  await setWallet(S.db.query, a.id, 0, 0)
  await setWallet(S.db.query, b.id, 100_000, 5_000)
  return { a, b }
}

test('proceeds = 90% rounded down', () => {
  assert.equal(MK.proceedsOf(1000), 900)
  assert.equal(MK.proceedsOf(15), 13)
  assert.equal(MK.proceedsOf(10), 9)
})

test('list → browse → buy → collect: item moves, buyer pays price, seller gets 90%', async () => {
  const { a, b } = await two()
  const item = await addItem(S.db.query, a.id, 'SSR')
  let r = await post(a.token, 'list', { item_id: item, currency: 'gold', price: 1000 })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  assert.ok(!r.json.player.items.some((x: any) => x.id === item), 'listed item leaves the bag')
  assert.equal(r.json.market.mine.length, 1)
  assert.equal(r.json.market.mine[0].proceeds, 900)
  assert.equal(r.json.market.mine[0].item.grade, 'SSR')

  // 내 판매는 구매 목록에 안 보인다, 남에게는 보인다
  assert.equal((await S.req('GET', '/v1/market?currency=gold', { token: a.token })).json.listings.length, 0)
  const browse = (await S.req('GET', '/v1/market?currency=gold&grade=SSR', { token: b.token })).json.listings
  const l = browse.find((x: any) => x.item.id === item)
  assert.ok(l)
  assert.equal(l.price, 1000)
  assert.equal(l.item.slot, 'hat')
  assert.equal((await S.req('GET', '/v1/market?currency=diamonds', { token: b.token })).json.listings.some((x: any) => x.id === l.id), false)

  // 자기 판매는 못 산다
  assert.equal((await post(a.token, 'buy', { id: l.id, currency: 'gold', price: 1000 })).json.error, 'own_listing')
  // 값이 다르면 409
  assert.equal((await post(b.token, 'buy', { id: l.id, currency: 'gold', price: 999 })).json.error, 'price_changed')

  r = await post(b.token, 'buy', { id: l.id, currency: 'gold', price: 1000 })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  assert.equal(r.json.player.gold, 99_000)
  assert.ok(r.json.player.items.some((x: any) => x.id === item && x.grade === 'SSR'))
  assert.equal(r.json.bought.id, l.id)
  // 두 번째 구매는 매진
  assert.equal((await post(b.token, 'buy', { id: l.id, currency: 'gold', price: 1000 })).json.error, 'sold_out')

  let pa = await player(a.token)
  assert.equal(pa.market_sold, 1)
  assert.equal(pa.gold, 0)
  r = await post(a.token, 'collect')
  assert.equal(r.status, 200, JSON.stringify(r.json))
  assert.deepEqual(r.json.collected, { gold: 900, diamonds: 0 })
  assert.equal(r.json.player.gold, 900)
  assert.equal(r.json.player.market_sold, 0)
  assert.equal(r.json.market.mine.length, 0)
  assert.equal((await post(a.token, 'collect')).json.error, 'nothing_to_collect')
  pa = await player(a.token)
  assert.equal(pa.gold, 900)
})

test('diamond listing, cancel returns the item, expiry returns it too', async () => {
  const { a, b } = await two()
  const i1 = await addItem(S.db.query, a.id, 'UR')
  const i2 = await addItem(S.db.query, a.id, 'R')
  let r = await post(a.token, 'list', { item_id: i1, currency: 'diamonds', price: 500 })
  assert.equal(r.status, 200)
  const id1 = r.json.market.mine[0].id
  r = await post(a.token, 'cancel', { id: id1 })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  assert.ok(r.json.player.items.some((x: any) => x.id === i1))
  assert.equal(r.json.market.mine.length, 0)
  assert.equal((await post(b.token, 'buy', { id: id1, currency: 'diamonds', price: 500 })).json.error, 'sold_out')

  r = await post(a.token, 'list', { item_id: i2, currency: 'diamonds', price: 20 })
  const id2 = r.json.market.mine[0].id
  S.clock.t += MK.DURATION_SEC + 1
  const pa = await player(a.token)
  assert.ok(pa.items.some((x: any) => x.id === i2), 'expired listing returns to the bag')
  assert.equal((await post(b.token, 'buy', { id: id2, currency: 'diamonds', price: 20 })).json.error, 'sold_out')
  // 다시 올릴 수 있다
  r = await post(a.token, 'list', { item_id: i2, currency: 'diamonds', price: 30 })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  r = await post(b.token, 'buy', { id: r.json.market.mine[0].id, currency: 'diamonds', price: 30 })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  assert.equal(r.json.player.diamonds, 4_970)
  r = await post(a.token, 'collect')
  assert.deepEqual(r.json.collected, { gold: 0, diamonds: 27 })
})

test('list checks: equipped, not mine, price limits, 10 at once', async () => {
  const { a, b } = await two()
  const theirs = await addItem(S.db.query, b.id)
  assert.equal((await post(a.token, 'list', { item_id: theirs, currency: 'gold', price: 1000 })).json.error, 'unknown_item')
  const eq = await addItem(S.db.query, a.id)
  const hero = Object.keys((await player(a.token)).heroes)[0]
  await S.db.query("insert into player_equipment (player_id, hero_id, slot, item_id) values ($1, $2, 'hat', $3)", [a.id, hero, eq])
  assert.equal((await post(a.token, 'list', { item_id: eq, currency: 'gold', price: 1000 })).json.error, 'equipped')
  const it = await addItem(S.db.query, a.id)
  assert.equal((await post(a.token, 'list', { item_id: it, currency: 'gold', price: 99 })).json.error, 'bad_price')
  assert.equal((await post(a.token, 'list', { item_id: it, currency: 'diamonds', price: 100_001 })).json.error, 'bad_price')
  assert.equal((await post(a.token, 'list', { item_id: it, currency: 'ruby', price: 100 })).status, 400)
  for (let k = 0; k < MK.MAX_ACTIVE; k++) {
    const x = await addItem(S.db.query, a.id)
    assert.equal((await post(a.token, 'list', { item_id: x, currency: 'gold', price: 100 + k })).status, 200)
  }
  assert.equal((await post(a.token, 'list', { item_id: it, currency: 'gold', price: 1000 })).json.error, 'too_many_listings')
  // 판매 중인 장비는 장착·판매 못 한다(보관함에 없다)
  const listed = (await S.req('GET', '/v1/market/mine', { token: a.token })).json.mine[0].item.id
  assert.equal((await S.req('POST', '/v1/items/sell', { token: a.token, body: { item_ids: [listed] } })).status, 404)
})

test('buy checks: not enough money, bag full', async () => {
  const { a, b } = await two()
  const it = await addItem(S.db.query, a.id)
  const r = await post(a.token, 'list', { item_id: it, currency: 'gold', price: 200_000 })
  const id = r.json.market.mine[0].id
  assert.equal((await post(b.token, 'buy', { id, currency: 'gold', price: 200_000 })).json.error, 'not_enough_gold')
  await setWallet(S.db.query, b.id, 300_000, 0)
  await S.db.query("insert into player_items (player_id, slot, grade, level) select $1, 'hat', 'N', 1 from generate_series(1, 300)", [b.id])
  assert.equal((await post(b.token, 'buy', { id, currency: 'gold', price: 200_000 })).json.error, 'bag_full')
})

test('two buyers at once: only one gets the item, the other keeps their gold', async () => {
  const { a, b } = await two()
  const c = await S.login()
  await player(c.token)
  await setWallet(S.db.query, c.id, 100_000, 0)
  const it = await addItem(S.db.query, a.id, 'LR')
  const id = (await post(a.token, 'list', { item_id: it, currency: 'gold', price: 5000 })).json.market.mine[0].id
  const [rb, rc] = await Promise.all([post(b.token, 'buy', { id, currency: 'gold', price: 5000 }), post(c.token, 'buy', { id, currency: 'gold', price: 5000 })])
  const ok = [rb, rc].filter((r) => r.status === 200)
  assert.equal(ok.length, 1, JSON.stringify([rb.json, rc.json]))
  const lost = [rb, rc].find((r) => r.status !== 200)!
  assert.equal(lost.json.error, 'sold_out')
  const golds = [(await player(b.token)).gold, (await player(c.token)).gold].sort((x, y) => x - y)
  assert.deepEqual(golds, [95_000, 100_000])
  const [row] = await S.db.query('select count(*)::int as n from player_items where id = $1', [it])
  assert.equal(row.n, 1)
})

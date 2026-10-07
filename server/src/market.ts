// 거래소(2026-10-07, 마이그레이션 033): 내 장비를 골드나 다이아로 올리고 다른 플레이어가 산다. 정산 수수료 10%(산 사람은 올린 값을 내고,
// 판 사람은 90%를 내림해 받는다). 판매는 48시간, 한 사람이 동시에 10개까지. 장착 중인 장비는 못 올린다. 자기 판매는 못 산다.
// 사기는 서버가 정한다(한 판매는 한 사람만 — app.ts commit의 marketBuy). 판 대금은 [내 판매]에서 받는다.
// 다이아 거래 안전장치(BM): 다이아 값은 10..100,000, 골드 값은 100..1,000,000,000.
//  GET  /v1/market?currency=gold|diamonds&slot=&grade=&sort=cheap|dear|new  → {server_now, rules, listings: [판매]}(남의 판매 중, 최대 50)
//  GET  /v1/market/mine                         → {server_now, rules, mine: [판매]}(판매 중 + 팔렸고 대금 안 받은 것)
//  POST /v1/market/list    {item_id, currency, price} → 플레이어 응답 + {market: {rules, mine}}
//  POST /v1/market/cancel  {id}                → 플레이어 응답 + {market}
//  POST /v1/market/collect {}                  → 플레이어 응답 + {market, collected: {gold, diamonds}}
//  POST /v1/market/buy     {id, currency, price} → 플레이어 응답 + {bought: 판매}(값은 화면에 보인 그대로 보낸다 — 다르면 409)
// 판매 = {id, item(보관함과 같은 장비 형식), currency, price, proceeds, status, seller, expires_at, sold_at}.
import type { Hono } from 'hono'
import * as G from './guild.ts'
import * as R from './rules.ts'

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Any = any

export const CURRENCIES = ['gold', 'diamonds'] as const
export const FEE_PCT = 10
export const MAX_ACTIVE = 10
export const DURATION_SEC = 48 * 3600
export const PRICE_LIMITS: Record<string, [number, number]> = { gold: [100, 1_000_000_000], diamonds: [10, 100_000] }
export const BROWSE_LIMIT = 50
export const SORTS = ['cheap', 'dear', 'new'] as const

export const RULES = { fee_pct: FEE_PCT, max_active: MAX_ACTIVE, duration_sec: DURATION_SEC, price_limits: PRICE_LIMITS }

// 판 사람이 받는 값: 값의 90% 내림.
export const proceedsOf = (price: number) => Math.floor((price * (100 - FEE_PCT)) / 100)

const ITEM_JSON = `(to_jsonb(i) - 'player_id' - 'created_at')`
const ROW_COLS = `l.id, l.currency, l.price, l.proceeds, l.status, l.seller_id::text as seller_id, extract(epoch from l.expires_at)::float8 as expires_at,
  extract(epoch from l.sold_at)::float8 as sold_at`

export function registerMarket(app: Hono<Any>, d: Any) {
  const { query, auth, clock, loadGame, loadPlayer, commit, view, body, ApiError, random, testHooks } = d
  const MAX_ATTEMPTS = 5

  const toListing = (r: Any) => ({
    id: Number(r.id), item: typeof r.item === 'string' ? JSON.parse(r.item) : r.item, currency: String(r.currency), price: Number(r.price),
    proceeds: Number(r.proceeds), status: String(r.status), seller: G.playerName(String(r.seller_id)), expires_at: Number(r.expires_at),
    sold_at: r.sold_at == null ? null : Number(r.sold_at),
  })

  // 기한이 지난 판매를 expired로(장비는 이미 판매자 보관함에 다시 보인다 — 플레이어 읽기가 기한으로 거른다).
  const sweep = (now: number) => query(`update market_listings set status = 'expired' where status = 'active' and expires_at <= to_timestamp($1::float8)`, [now])

  async function mine(id: string, now: number) {
    const rows = await query(`select ${ROW_COLS}, coalesce(${ITEM_JSON}, l.item) as item from market_listings l
      left join player_items i on i.id = l.item_id and i.player_id = l.seller_id and l.status = 'active'
      where l.seller_id = $1 and (l.status = 'sold' or (l.status = 'active' and l.expires_at > to_timestamp($2::float8)))
      order by l.status = 'sold' desc, l.id desc`, [id, now])
    return rows.map(toListing)
  }

  const currencyOf = (v: unknown): string => {
    if (typeof v !== 'string' || !(CURRENCIES as readonly string[]).includes(v)) throw new ApiError(400, 'bad_request', `'currency' must be one of ${CURRENCIES.join(', ')}`)
    return v
  }
  const idOf = (v: unknown, key = 'id'): number => {
    if (typeof v !== 'number' || !Number.isInteger(v) || v < 1) throw new ApiError(400, 'bad_request', `'${key}' must be a positive integer`)
    return v
  }

  // 읽기 → 계산 → 조건부 쓰기(app.ts mutate와 같다). 응답 = 플레이어 응답 + extra(쓴 뒤 다시 읽은 내 판매 포함).
  async function run(c: Any, plan: (pl: Any, game: Any, now: number) => Promise<{ change: Any; extra?: Record<string, unknown> }>) {
    const id = c.get('playerId') as string
    for (let i = 0; i < MAX_ATTEMPTS; i++) {
      const now = clock()
      await sweep(now)
      const game = await loadGame()
      const pl = await loadPlayer(id, game, now)
      const { change, extra } = await plan(pl, game, now)
      const r = await commit(id, pl.version, change, now)
      if (!r) continue
      const after = await loadPlayer(id, game, now)
      return c.json({ ...view(after, game, now), ...extra, market: { rules: RULES, mine: await mine(id, now) } })
    }
    throw new ApiError(409, 'conflict', 'concurrent update; try again')
  }

  app.get('/v1/market', auth, async (c: Any) => {
    const id = c.get('playerId') as string
    const now = clock()
    await sweep(now)
    const currency = currencyOf(c.req.query('currency') ?? 'gold')
    const slot = c.req.query('slot') ?? ''
    const grade = c.req.query('grade') ?? ''
    const sort = c.req.query('sort') ?? 'cheap'
    if (!(SORTS as readonly string[]).includes(sort)) throw new ApiError(400, 'bad_request', `'sort' must be one of ${SORTS.join(', ')}`)
    const order = sort === 'dear' ? 'l.price desc, l.id' : sort === 'new' ? 'l.id desc' : 'l.price, l.id'
    const rows = await query(`select ${ROW_COLS}, ${ITEM_JSON} as item from market_listings l join player_items i on i.id = l.item_id and i.player_id = l.seller_id
      where l.status = 'active' and l.expires_at > to_timestamp($1::float8) and l.currency = $2 and l.seller_id <> $3
        and ($4 = '' or i.slot = $4) and ($5 = '' or i.grade = $5)
      order by ${order} limit ${BROWSE_LIMIT}`, [now, currency, id, slot, grade])
    return c.json({ server_now: now, rules: RULES, listings: rows.map(toListing) })
  })

  app.get('/v1/market/mine', auth, async (c: Any) => {
    const now = clock()
    await sweep(now)
    return c.json({ server_now: now, rules: RULES, mine: await mine(c.get('playerId') as string, now) })
  })

  app.post('/v1/market/list', auth, async (c: Any) => {
    const b = await body(c)
    const itemId = idOf(b.item_id, 'item_id')
    const currency = currencyOf(b.currency)
    const [lo, hi] = PRICE_LIMITS[currency]
    const price = b.price
    if (typeof price !== 'number' || !Number.isInteger(price) || price < lo || price > hi) throw new ApiError(400, 'bad_price', `'price' must be an integer in ${lo}..${hi}`)
    return run(c, async (pl, _game, now) => {
      const item = pl.items.find((x: Any) => x.id === itemId)
      if (!item) throw new ApiError(404, 'unknown_item', `no item ${itemId} in your bag`)
      if (pl.equipment.some((e: Any) => e.item_id === itemId)) throw new ApiError(409, 'equipped', `item ${itemId} is equipped`)
      const [n] = await query(`select count(*)::int as n from market_listings where seller_id = $1 and status = 'active' and expires_at > to_timestamp($2::float8)`, [pl.id, now])
      if (Number(n.n) >= MAX_ACTIVE) throw new ApiError(409, 'too_many_listings', `at most ${MAX_ACTIVE} listings at once`)
      const [snap] = await query(`select ${ITEM_JSON} as item from player_items i where id = $1`, [itemId])
      const proceeds = proceedsOf(price)
      return {
        change: { marketList: { item_id: itemId, item: snap?.item ?? item, currency, price, proceeds, expires: now + DURATION_SEC },
          log: { kind: 'market', detail: { action: 'list', item_id: itemId, currency, price } } },
      }
    })
  })

  app.post('/v1/market/cancel', auth, async (c: Any) => {
    const id = idOf((await body(c)).id)
    return run(c, async (pl, _game, now) => {
      const [r] = await query(`select status, extract(epoch from expires_at)::float8 as expires_at from market_listings where id = $1 and seller_id = $2`, [id, pl.id])
      if (!r) throw new ApiError(404, 'unknown_listing', `no listing ${id} of yours`)
      if (r.status === 'sold') throw new ApiError(409, 'already_sold', 'the item was already sold')
      if (r.status !== 'active' || Number(r.expires_at) <= now) throw new ApiError(409, 'not_active', 'the listing is no longer on sale')
      return { change: { marketCancel: id, log: { kind: 'market', detail: { action: 'cancel', id } } } }
    })
  })

  app.post('/v1/market/collect', auth, async (c: Any) => {
    await body(c)
    return run(c, async (pl) => {
      const rows = await query(`select id, currency, proceeds from market_listings where seller_id = $1 and status = 'sold' order by id`, [pl.id])
      if (!rows.length) throw new ApiError(409, 'nothing_to_collect', 'no sold listings to collect')
      let gold = 0
      let diamonds = 0
      for (const r of rows) if (r.currency === 'gold') gold += Number(r.proceeds); else diamonds += Number(r.proceeds)
      const ids = rows.map((r: Any) => Number(r.id))
      return {
        change: { marketCollect: ids, goldTenths: gold * 10, diamonds, log: { kind: 'market', detail: { action: 'collect', ids, gold, diamonds } } },
        extra: { collected: { gold, diamonds } },
      }
    })
  })

  if (testHooks) {
    // 통합 테스트용: 등급마다 장비 하나(부위 무작위, 굴림 rollItem)를 보관함에 넣는다 {grades: ['SR', ...]}.
    app.post('/v1/test/grant_items', auth, async (c: Any) => {
      const grades = (await body(c)).grades
      if (!Array.isArray(grades) || !grades.length || grades.length > 50 || !grades.every((g) => R.EQUIP_GRADES.includes(g))) {
        throw new ApiError(400, 'bad_request', "'grades' must be 1..50 equipment grades")
      }
      const slots = ['weapon', ...R.ARMOR_SLOTS]
      const items = grades.map((g: string) => {
        const slot = slots[Math.floor(random() * slots.length)]
        return R.rollItem(slot, slot === 'weapon' ? R.WEAPON_KINDS[Math.floor(random() * R.WEAPON_KINDS.length)] : null, g, random)
      })
      return run(c, async () => ({ change: { items } }))
    })
  }

  app.post('/v1/market/buy', auth, async (c: Any) => {
    const b = await body(c)
    const id = idOf(b.id)
    const currency = currencyOf(b.currency)
    const price = b.price
    if (typeof price !== 'number' || !Number.isInteger(price) || price < 1) throw new ApiError(400, 'bad_request', "'price' must be a positive integer")
    return run(c, async (pl, game, now) => {
      const [r] = await query(`select ${ROW_COLS}, ${ITEM_JSON} as item from market_listings l join player_items i on i.id = l.item_id and i.player_id = l.seller_id
        where l.id = $1`, [id])
      if (!r || r.status !== 'active' || Number(r.expires_at) <= now) throw new ApiError(409, 'sold_out', 'the listing is no longer on sale')
      if (r.seller_id === pl.id) throw new ApiError(409, 'own_listing', 'you cannot buy your own listing')
      if (r.currency !== currency || Number(r.price) !== price) throw new ApiError(409, 'price_changed', 'the listing price is different')
      if (pl.items.length >= R.cfgNum(game.config, 'equip_bag_cap')) throw new ApiError(409, 'bag_full', 'the item bag is full')
      const have = currency === 'gold' ? Math.floor(pl.gold_tenths / 10) : pl.diamonds
      if (have < price) throw new ApiError(409, currency === 'gold' ? 'not_enough_gold' : 'not_enough_diamonds', `not enough ${currency}`)
      const listing = toListing({ ...r, status: 'sold', sold_at: now })
      return {
        change: {
          marketBuy: { id, currency, price }, ...(currency === 'gold' ? { goldTenths: -price * 10 } : { diamonds: -price }),
          log: { kind: 'market', detail: { action: 'buy', id, item_id: Number(r.item?.id), currency, price, seller: r.seller_id } },
        },
        extra: { bought: listing },
      }
    })
  })
}

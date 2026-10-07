// PVP 엔드포인트(마이그레이션 028, 규칙 pvp.ts). createApp 안에서 registerPvp로 붙인다.
//  GET  /v1/pvp                               → {server_now, pvp}
//  POST /v1/pvp/defense {mode, heroes × 5}    방어팀(보유 영웅 5, 능력치는 capStats로 자른다). 총력전은 지금 보유 병사에서 병사도 고른다
//  POST /v1/pvp/start   {mode, heroes × 5}    판 하나를 쓰고 미리 정해 둔 상대(next)와 싸움을 연다 — 패배로 먼저 적는다 → {pvp, battle}
//  POST /v1/pvp/finish  {battle_id, win}      결과(승리면 포인트·코인을 바로잡는다). 같은 판을 다시 보내면 같은 결과
//  POST /v1/pvp/buy     {id}                  PVP 상점(코인) → 플레이어 응답 + {pvp, result}
// pvp = {coins, next_reset, shop: [{id, give, price, limit, period, bought}], modes: {duel, total}}.
// 모드 = {points, tier, wins, losses, plays_left, plays, defense: [영웅 id], power, next: 상대}. 방어팀을 안 정했으면 처음 시작한 팀이 방어팀이 된다.
import type { Hono } from 'hono'
import * as P from './pvp.ts'
import * as G from './guild.ts'
import * as R from './rules.ts'
import { weekOf } from './guild_war.ts'
import type { HeroDef } from './guild_war.ts'

const json = (v: unknown) => (typeof v === 'string' ? JSON.parse(v) : v)

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Any = any

export function registerPvp(app: Hono<Any>, d: Any) {
  const { query, auth, clock, loadGame, loadPlayer, commit, view, body, strField, blocked, grant, random, ApiError } = d

  const cfgOf = (game: Any) => (k: string) => R.cfgNum(game.config, k)
  const defsOf = (game: Any): HeroDef[] => game.heroes.map((h: Any) => ({ id: String(h.id), role: String(h.role), hp: Number(h.hp), atk: Number(h.atk),
    atk_interval: Number(h.atk_interval), grade: String(h.grade) }))
  const modeOf = (v: unknown): P.Mode => {
    if (!P.isMode(v)) throw new ApiError(400, 'bad_request', `'mode' must be one of ${P.MODES.join(', ')}`)
    return v
  }

  interface Row { mode: P.Mode; points: number; wins: number; losses: number; day: number; plays: number; defense: P.TeamHero[]; soldiers: P.Soldiers; power: number; next: P.Opponent | null }
  const toRow = (r: Any): Row => ({ mode: r.mode, points: Number(r.points), wins: Number(r.wins), losses: Number(r.losses), day: Number(r.day), plays: Number(r.plays),
    defense: json(r.defense) ?? [], soldiers: json(r.soldiers) ?? {}, power: Number(r.power), next: r.next == null ? null : json(r.next) })

  async function ctx(c: Any) {
    const id = c.get('playerId') as string
    const now = clock()
    const game = await loadGame()
    const pl = await loadPlayer(id, game, now)
    const hour = R.cfgNum(game.config, 'daily_reset_utc_hour')
    return { id, now, game, pl, hour, today: R.resetDay(now, hour) }
  }

  // 보유 병사 중 총력전 병사(높은 티어부터 상한까지).
  const mySoldiers = (x: Any) => P.pickSoldiers(x.pl.soldiers)

  // 봇의 기준 팀: 방어팀이 있으면 그 영웅들, 없으면 전투력 높은 영웅 5명(장비 포함) — 등급·역할·전투력.
  function myBase(x: Any, row: Row): P.BaseHero[] {
    const defs = defsOf(x.game)
    if (row.defense.length) {
      return row.defense.flatMap((h) => {
        const d = defs.find((g) => g.id === h.hero)
        return d ? [{ grade: d.grade, role: d.role, power: R.powerOf(d, h.hp, h.atk) }] : []
      })
    }
    const eq = R.heroEquip(x.pl.items, x.pl.equipment)
    const ps = Object.entries(x.pl.heroes as Record<string, Any>).flatMap(([id, h]) => {
      const def = x.game.heroes.find((g: Any) => g.id === id)
      return def ? [{ grade: String(def.grade), role: String(def.role), power: R.heroPower(def, h.level, h.promotion, eq[id] ?? { hp: 0, atk: 0 }, x.game.config) }] : []
    }).sort((a, b) => b.power - a.power)
    return ps.slice(0, P.TEAM)
  }

  // 다음 상대: 포인트가 가까운 실제 방어팀(MATCH_RANGE 안, 가까운 MATCH_N 중 하나), 없으면 봇.
  async function pickOpponent(x: Any, row: Row): Promise<P.Opponent> {
    const rows = await query(`select player_id::text as id, points, defense, soldiers, power from pvp_stats
      where mode = $1 and player_id <> $2 and defense <> '[]'::jsonb and abs(points - $3) <= ${P.MATCH_RANGE}
      order by abs(points - $3), player_id limit ${P.MATCH_N}`, [row.mode, x.id, row.points])
    const last = row.next?.id
    const pool = rows.length > 1 ? rows.filter((r: Any) => r.id !== last) : rows
    if (pool.length) {
      const r = pool[Math.floor(random() * pool.length)]
      return { kind: 'player', id: String(r.id), name: G.playerName(String(r.id)), points: Number(r.points), power: Number(r.power),
        heroes: json(r.defense), soldiers: row.mode === 'total' ? json(r.soldiers) ?? {} : {} }
    }
    const seed = Math.floor(random() * 2 ** 31)
    return P.botTeam(seed, row.mode, myBase(x, row), row.points, defsOf(x.game), cfgOf(x.game), row.mode === 'total' ? mySoldiers(x) : {},
      x.game.soldiers.map((s: Any) => String(s.id)))
  }

  // 두 모드 행·지갑을 채우고, 다음 상대가 없으면 정해 둔다.
  async function rows(x: Any): Promise<Record<P.Mode, Row>> {
    await query(`insert into pvp_stats (player_id, mode) select $1, m from unnest($2::text[]) as m on conflict do nothing`, [x.id, [...P.MODES]])
    await query('insert into pvp_wallet (player_id) values ($1) on conflict do nothing', [x.id])
    const out = {} as Record<P.Mode, Row>
    for (const r of await query('select * from pvp_stats where player_id = $1', [x.id])) {
      const row = toRow(r)
      if (!P.isMode(row.mode)) continue
      if (!row.next) {
        row.next = await pickOpponent(x, row)
        await query('update pvp_stats set next = $3::jsonb where player_id = $1 and mode = $2 and next is null', [x.id, row.mode, JSON.stringify(row.next)])
        const [again] = await query('select next from pvp_stats where player_id = $1 and mode = $2', [x.id, row.mode])
        row.next = json(again.next)
      }
      out[row.mode] = row
    }
    return out
  }

  const oppView = (o: P.Opponent | null) => (o ? { kind: o.kind, name: o.name, points: o.points, tier: P.tierOf(o.points), power: o.power,
    heroes: o.heroes, soldiers: o.soldiers } : null)

  async function pvpView(x: Any) {
    const rs = await rows(x)
    const [w] = await query('select coins, shop from pvp_wallet where player_id = $1', [x.id])
    const shop = P.shopToday(json(w?.shop), x.today, weekOf(x.today))
    const modes: Record<string, unknown> = {}
    for (const m of P.MODES) {
      const r = rs[m]
      const used = r.day === x.today ? r.plays : 0
      modes[m] = { points: r.points, tier: P.tierOf(r.points), wins: r.wins, losses: r.losses, plays_left: Math.max(0, P.PLAYS - used), plays: P.PLAYS,
        defense: r.defense.map((h) => h.hero), soldiers: r.soldiers, power: r.power, next: oppView(r.next), time: P.BATTLE_SEC[m] }
    }
    return {
      coins: Number(w?.coins ?? 0), next_reset: R.nextReset(x.now, x.game.config), my_soldiers: mySoldiers(x),
      shop: P.SHOP.map((s) => ({ ...s, bought: shop.bought[s.id] ?? 0 })), modes,
    }
  }

  const teamOrThrow = (x: Any, raw: unknown) => {
    const t = P.teamOf(raw, x.pl.heroes, defsOf(x.game), cfgOf(x.game))
    if (!t) throw blocked('bad_heroes', `heroes must be ${P.TEAM} different heroes you own`)
    return t
  }

  app.get('/v1/pvp', auth, async (c) => {
    const x = await ctx(c)
    return c.json({ server_now: x.now, pvp: await pvpView(x) })
  })

  app.post('/v1/pvp/defense', auth, async (c) => {
    const b = await body(c)
    const x = await ctx(c)
    const mode = modeOf(b.mode)
    const team = teamOrThrow(x, b.heroes)
    await rows(x)
    const soldiers = mode === 'total' ? mySoldiers(x) : {}
    await query('update pvp_stats set defense = $3::jsonb, soldiers = $4::jsonb, power = $5 where player_id = $1 and mode = $2',
      [x.id, mode, JSON.stringify(team), JSON.stringify(soldiers), P.teamPower(team, defsOf(x.game))])
    return c.json({ server_now: x.now, pvp: await pvpView(x) })
  })

  app.post('/v1/pvp/start', auth, async (c) => {
    const b = await body(c)
    const mode = modeOf(b.mode)
    for (let i = 0; i < 4; i++) {
      const x = await ctx(c)
      const team = teamOrThrow(x, b.heroes)
      const r = (await rows(x))[mode]
      const used = r.day === x.today ? r.plays : 0
      if (used >= P.PLAYS) throw blocked('no_plays', 'no plays left today')
      const opp = r.next!
      const loss = P.lossOf(r.points)
      const gain = P.winGain(r.points, opp.points)
      const after = { ...r, points: r.points - loss, next: null as P.Opponent | null }
      const nextOpp = await pickOpponent(x, { ...after, next: opp })
      const defs = defsOf(x.game)
      const setDefense = r.defense.length === 0 // 방어팀이 없으면 이 팀이 방어팀
      const soldiers = mode === 'total' ? mySoldiers(x) : {}
      const [res] = await query(`with u as (update pvp_stats set day = $3, plays = $4, points = points - $5, losses = losses + 1, next = $6::jsonb,
          defense = case when $7 then $8::jsonb else defense end, soldiers = case when $7 then $9::jsonb else soldiers end,
          power = case when $7 then $10 else power end
          where player_id = $1 and mode = $2 and day = $11 and plays = $12 and points = $13 and next = $14::jsonb returning player_id),
        b as (insert into pvp_battles (player_id, mode, opponent, started_at, loss, gain)
          select player_id, $2, $14::jsonb, to_timestamp($15::float8), $5, $16 from u returning id::text),
        w as (update pvp_wallet set coins = coins + ${P.COINS_LOSS} where player_id = $1 and exists (select 1 from u) returning 1)
        select (select id from b) as id`,
      [x.id, mode, x.today, used + 1, loss, JSON.stringify(nextOpp), setDefense, JSON.stringify(team), JSON.stringify(soldiers), P.teamPower(team, defs),
        r.day, r.plays, r.points, JSON.stringify(opp), x.now, gain])
      if (!res?.id) continue
      const battle = { id: String(res.id), mode, opponent: oppView(opp), me: team, my_soldiers: soldiers, loss, gain, time: P.BATTLE_SEC[mode] }
      return c.json({ server_now: x.now, pvp: await pvpView(x), battle })
    }
    throw new ApiError(409, 'conflict', 'concurrent update; try again')
  })

  app.post('/v1/pvp/finish', auth, async (c) => {
    const b = await body(c)
    const battleId = strField(b, 'battle_id')
    if (!/^[0-9a-f-]{36}$/i.test(battleId)) throw new ApiError(400, 'bad_request', "'battle_id' must be a uuid")
    const x = await ctx(c)
    const [bt] = await query(`select mode, loss, gain, closed, result, extract(epoch from started_at)::float8 as started_at from pvp_battles
      where id = $1 and player_id = $2`, [battleId, x.id])
    if (!bt) throw new ApiError(404, 'no_battle', 'unknown battle')
    if (!bt.closed) {
      const win = P.acceptWin(b.win === true, x.now - Number(bt.started_at))
      const delta = win ? Number(bt.gain) : -Number(bt.loss)
      const coins = win ? P.COINS_WIN : P.COINS_LOSS
      const result = { win, delta, coins, claimed_win: b.win === true }
      await query(`with b as (update pvp_battles set closed = true, result = $3::jsonb where id = $1 and player_id = $2 and not closed returning mode, loss, gain),
          s as (update pvp_stats set points = points + b.loss + b.gain, wins = wins + 1, losses = losses - 1 from b
            where $4 and pvp_stats.player_id = $2 and pvp_stats.mode = b.mode returning 1),
          w as (update pvp_wallet set coins = coins + ${P.COINS_WIN - P.COINS_LOSS} where $4 and player_id = $2 and exists (select 1 from b) returning 1)
          select 1`, [battleId, x.id, JSON.stringify(result), win])
    }
    const [done] = await query('select result from pvp_battles where id = $1', [battleId])
    return c.json({ server_now: x.now, pvp: await pvpView(x), result: json(done.result) })
  })

  app.post('/v1/pvp/buy', auth, async (c) => {
    const itemId = strField(await body(c), 'id')
    const it = P.SHOP.find((s) => s.id === itemId)
    if (!it) throw new ApiError(400, 'bad_item', `unknown shop item '${itemId}'`)
    const id = c.get('playerId') as string
    for (let i = 0; i < 4; i++) {
      const x = await ctx(c)
      await rows(x)
      const [w] = await query('select coins, shop from pvp_wallet where player_id = $1', [id])
      const shop = P.shopToday(json(w.shop), x.today, weekOf(x.today))
      if ((shop.bought[it.id] ?? 0) >= it.limit) throw blocked('sold_out', 'purchase limit reached')
      if (Number(w.coins) < it.price) throw blocked('not_enough_coins', 'not enough pvp coins')
      if (it.give.equip && x.pl.items.length + it.give.equip > R.cfgNum(x.game.config, 'equip_bag_cap')) throw blocked('bag_full', 'equipment bag is full')
      const ch: Any = {}
      const give = { ...it.give }
      if (give.tickets) {
        ch.diaTickets = give.tickets
        delete give.tickets
      }
      grant({ pl: x.pl, game: x.game }, give, ch, { n: 0 })
      if ((it.give.shards || it.give.ssr_shards) && !ch.shards) throw blocked('no_heroes', 'no hero to receive shards')
      ch.pvpBuy = { price: it.price, shop: { ...shop, bought: { ...shop.bought, [it.id]: (shop.bought[it.id] ?? 0) + 1 } } }
      ch.log = { kind: 'pvp_buy', detail: { id: it.id, price: it.price } }
      if (!(await commit(id, x.pl.version, ch, x.now))) continue
      const pl2 = await loadPlayer(id, x.game, x.now)
      return c.json({ ...view(pl2, x.game, x.now), pvp: await pvpView({ ...x, pl: pl2 }),
        result: { id: it.id, give: it.give, shards: ch.shards ?? {}, items: ch.items ?? [] } })
    }
    throw new ApiError(409, 'conflict', 'concurrent update; try again')
  })

  // 테스트 훅: 포인트를 정한다(등급·매칭 확인).
  if (d.testHooks) {
    app.post('/v1/test/pvp_points', auth, async (c) => {
      const b = await body(c)
      const x = await ctx(c)
      await rows(x)
      await query('update pvp_stats set points = $3 where player_id = $1 and mode = $2', [x.id, modeOf(b.mode), Math.max(0, Math.floor(Number(b.points) || 0))])
      return c.json({ server_now: x.now, pvp: await pvpView(x) })
    })
  }
}

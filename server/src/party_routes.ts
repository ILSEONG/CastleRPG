// 파티 퀘스트 엔드포인트(마이그레이션 050, 규칙·매칭 party.ts, 실시간 방 party_live.ts). createApp 안에서 registerParty로 붙인다.
//  GET  /v1/party                                  → {server_now, party}
//  POST /v1/party/queue  {quest, diff, hero?, soldiers?} 매칭 대기열에 넣는다 → {server_now, party}
//        리치: hero = {id, hp, atk}(보유 영웅, 능력치는 capStats로 자른다) · 거미 여왕: soldiers = [{type, tier}] × 4(보유한 병사만 — 출전해도 줄지 않는다)
//  POST /v1/party/cancel                           대기 그만두기(확인 중이면 거절과 같다)
//  POST /v1/party/accept {match_id, accept}        [입장 수락]·거절
//  POST /v1/party/finish {run_id, win, elapsed}    판 결과 — 승리면 타당성 검사 뒤 장신구 1개(하루 REWARD_CLEARS번까지). 같은 판을 다시 보내면 같은 결과
// party = {quests: {lich|spider: {best, clears_left}}, queue: 내 상태}. 내 상태(앱이 대기 중 1초마다 GET /v1/party로 묻는다):
//  {state: 'idle'} · {state: 'queued', quest, diff, waited, bot_in} · {state: 'confirm', match_id, quest, diff, left, seats, accepted}
//  · {state: 'live', match_id, run_id, quest, diff, seed, elapsed, time_limit, boss, seats, me, result}
// seats = [{name, bot, me, accepted, hero?, soldiers?}](자리 순서 = 전투 자리 번호). 플레이어 id는 내보내지 않는다.
import type { Hono } from 'hono'
import { randomUUID } from 'node:crypto'
import * as PQ from './party.ts'
import * as G from './guild.ts'
import * as R from './rules.ts'
import { capStats, fitHero, heroStats } from './guild_war.ts'
import type { HeroDef } from './guild_war.ts'
import type { PartyLive } from './party_live.ts'

const json = (v: unknown) => (typeof v === 'string' ? JSON.parse(v) : v)
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Any = any

export function registerParty(app: Hono<Any>, d: Any, live?: PartyLive) {
  const { query, auth, clock, loadGame, loadPlayer, guildCtx, commit, view: playerView, body, blocked, random, ApiError, verifyToken } = d

  const cfgOf = (game: Any) => Object.assign((k: string) => R.cfgNum(game.config, k), { config: game.config })
  const defsOf = (game: Any): HeroDef[] => game.heroes.map((h: Any) => ({ id: String(h.id), role: String(h.role), hp: Number(h.hp), atk: Number(h.atk),
    atk_interval: Number(h.atk_interval), grade: String(h.grade) }))
  const soldierOf = (game: Any, type: string, tier: number) => {
    const s = game.soldiers.find((x: Any) => String(x.id) === type)
    if (!s) return null
    const m = R.cfgNum(game.config, 'soldier_tier_mult') ** (Math.max(1, tier) - 1)
    return { type, tier, hp: Math.round(Number(s.hp) * m), atk: Math.round(Number(s.atk) * m * 10) / 10, interval: Number(s.atk_interval) }
  }
  const soldierDps = (game: Any, list: PQ.SoldierUnit[]) => list.reduce((a, s) => a + s.atk / Math.max(0.1, soldierOf(game, s.type, s.tier)?.interval ?? 1), 0)

  // AI 성주: 리치 = 기준 자리 전투력에 맞춘 무작위 영웅, 거미 = 기준 자리와 같은 티어의 무작위 병종 4마리. 게임 표는 마지막으로 읽은 것.
  let lastGame: Any = null
  const makeBot = (quest: PQ.Quest, _diff: number, like: PQ.Seat, n: number, r: () => number): PQ.Seat => {
    const game = lastGame
    const name = G.nickname(Math.floor(r() * 2 ** 31) ^ n)
    if (quest === 'lich') {
      const defs = defsOf(game)
      const def = defs[Math.floor(r() * defs.length)]
      const f = fitHero(def, like.power, cfgOf(game))
      const s = heroStats(def, f.level, f.promotion, cfgOf(game))
      const hero = { hero: def.id, level: f.level, promotion: f.promotion, hp: Math.round(s.hp), atk: Math.round(s.atk * 10) / 10 }
      return { pid: null, name, hero, dps: hero.atk / Math.max(0.1, def.atk_interval), power: like.power, accepted: true }
    }
    const types = game.soldiers.map((s: Any) => String(s.id))
    const soldiers = (like.soldiers ?? []).map((s) => {
      const t = soldierOf(game, types[Math.floor(r() * types.length)], s.tier)!
      return { type: t.type, tier: t.tier, hp: t.hp, atk: t.atk }
    })
    return { pid: null, name, soldiers, dps: soldierDps(game, soldiers), power: like.power, accepted: true }
  }
  const hub = new PQ.PartyHub(makeBot, random)

  async function ctx(c: Any) {
    const id = c.get('playerId') as string
    const now = clock()
    const game = await loadGame()
    lastGame = game
    const pl = await loadPlayer(id, game, now)
    const hour = R.cfgNum(game.config, 'daily_reset_utc_hour')
    return { id, now, game, pl, today: R.resetDay(now, hour) }
  }

  async function stats(x: Any): Promise<Record<string, { best: number; clears_left: number }>> {
    const rows = await query('select quest, best, day, clears from party_stats where player_id = $1', [x.id])
    const out: Record<string, { best: number; clears_left: number }> = {}
    for (const q of PQ.QUESTS) {
      const r = rows.find((y: Any) => y.quest === q)
      const used = r && Number(r.day) === x.today ? Number(r.clears) : 0
      out[q] = { best: Number(r?.best ?? 0), clears_left: Math.max(0, PQ.REWARD_CLEARS - used) }
    }
    return out
  }

  const seatView = (s: PQ.Seat, me: string) => ({ name: s.name, bot: s.pid == null, me: s.pid === me, accepted: s.accepted,
    ...(s.hero ? { hero: s.hero } : {}), ...(s.soldiers ? { soldiers: s.soldiers } : {}) })

  async function myState(x: Any): Promise<Record<string, unknown>> {
    hub.tick(x.now)
    hub.seen(x.id, x.now)
    const t = hub.ticketOf(x.id)
    if (t) return { state: 'queued', quest: t.quest, diff: t.diff, waited: Math.floor(x.now - t.since), bot_in: Math.max(0, Math.ceil(PQ.BOT_WAIT_SEC - (x.now - t.since))) }
    const m = hub.matchOf(x.id)
    if (!m) return { state: 'idle' }
    const seats = m.seats.map((s) => seatView(s, x.id))
    if (m.state === 'confirm') {
      return { state: 'confirm', match_id: m.id, quest: m.quest, diff: m.diff, left: Math.max(0, Math.ceil(m.deadline - x.now)), seats,
        accepted: m.seats.find((s) => s.pid === x.id)!.accepted }
    }
    // 시작한 판: 내 run 행(처음 물을 때 만든다 — 매치 전체 초당 피해·보스 HP를 함께 적어 승리 타당성에 쓴다)
    const dps = m.seats.reduce((a, s) => a + s.dps, 0)
    const boss = PQ.bossStats(m.quest, m.diff)
    await query(`insert into party_runs (id, match_id, player_id, quest, diff, dps, boss_hp, started_at) values ($1, $2, $3, $4, $5, $6, $7, to_timestamp($8::float8))
      on conflict (match_id, player_id) do nothing`, [randomUUID(), m.id, x.id, m.quest, m.diff, dps, boss.hp, m.started])
    const [run] = await query('select id::text as id from party_runs where match_id = $1 and player_id = $2', [m.id, x.id])
    return { state: 'live', match_id: m.id, run_id: run.id, quest: m.quest, diff: m.diff, seed: m.seed, elapsed: Math.max(0, x.now - m.started),
      time_limit: PQ.TIME_LIMIT[m.quest], boss, seats, me: m.seats.findIndex((s) => s.pid === x.id), result: m.result }
  }

  const view = async (x: Any) => ({ server_now: x.now, party: { quests: await stats(x), queue: await myState(x) } })

  app.get('/v1/party', auth, async (c) => c.json(await view(await ctx(c))))

  app.post('/v1/party/queue', auth, async (c) => {
    const b = await body(c)
    const x = await ctx(c)
    const quest = b.quest
    if (!PQ.isQuest(quest)) throw new ApiError(400, 'bad_request', `'quest' must be one of ${PQ.QUESTS.join(', ')}`)
    const diff = b.diff
    if (typeof diff !== 'number' || !Number.isInteger(diff) || diff < 1 || diff > PQ.DIFFS) throw new ApiError(400, 'bad_request', `'diff' must be 1..${PQ.DIFFS}`)
    const st = (await stats(x))[quest]
    if (diff > st.best + 1) throw blocked('locked', `difficulty ${diff} is locked (best ${st.best})`)
    if (x.pl.items.length + 1 > R.cfgNum(x.game.config, 'equip_bag_cap')) throw blocked('bag_full', 'the item bag is full')
    const name = R.friendName(x.id)
    let seat: PQ.Seat
    if (quest === 'lich') {
      const h = b.hero as Any
      const id = typeof h?.id === 'string' ? h.id : ''
      const own = x.pl.heroes[id]
      const def = defsOf(x.game).find((g) => g.id === id)
      if (!own || !def) throw new ApiError(400, 'bad_party', "'hero' must be {id, hp, atk} of a hero you own")
      const gx = await guildCtx(x.id, x.pl, x.game, x.now)
      const lim = R.statLimit(x.pl, x.game, gx.st ? G.buffPct(gx.st.lv.level) : 0)
      const s = capStats(def, Number(own.level), Number(own.promotion), h.hp, h.atk, cfgOf(x.game), lim)
      const hero = { hero: id, level: Number(own.level), promotion: Number(own.promotion), hp: Math.round(s.hp), atk: Math.round(s.atk * 10) / 10 }
      seat = { pid: x.id, name, hero, dps: hero.atk / Math.max(0.1, def.atk_interval), power: R.powerOf(def, hero.hp, hero.atk), accepted: false }
    } else {
      const list = b.soldiers
      if (!Array.isArray(list) || list.length !== PQ.SOLDIERS_PER) throw new ApiError(400, 'bad_party', `'soldiers' must be ${PQ.SOLDIERS_PER} {type, tier}`)
      const need: Record<string, number> = {}
      const soldiers: PQ.SoldierUnit[] = []
      for (const raw of list as Any[]) {
        const tier = Number(raw?.tier)
        const s = Number.isInteger(tier) && tier >= 1 && tier <= 99 ? soldierOf(x.game, String(raw?.type ?? ''), tier) : null
        if (!s) throw new ApiError(400, 'bad_party', `'soldiers' must be ${PQ.SOLDIERS_PER} {type, tier}`)
        const k = `${s.type}:${s.tier}`
        need[k] = (need[k] ?? 0) + 1
        soldiers.push({ type: s.type, tier: s.tier, hp: s.hp, atk: s.atk })
      }
      for (const [k, n] of Object.entries(need)) if ((x.pl.soldiers[k] ?? 0) < n) throw blocked('no_soldiers', `not enough ${k} soldiers`)
      const dps = soldierDps(x.game, soldiers)
      seat = { pid: x.id, name, soldiers, dps, power: soldiers.reduce((a, s) => a + s.hp / 10 + s.atk * 2, 0), accepted: false }
    }
    if (!hub.join(seat, quest, diff, x.now)) throw blocked('in_match', 'you are already in a party match')
    return c.json(await view(x))
  })

  app.post('/v1/party/cancel', auth, async (c) => {
    const x = await ctx(c)
    hub.leave(x.id)
    const m = hub.matchOf(x.id)
    if (m && m.state === 'confirm') hub.answer(x.id, m.id, false, x.now)
    return c.json(await view(x))
  })

  app.post('/v1/party/accept', auth, async (c) => {
    const b = await body(c)
    const x = await ctx(c)
    const matchId = typeof b.match_id === 'string' ? b.match_id : ''
    if (typeof b.accept !== 'boolean') throw new ApiError(400, 'bad_request', "'accept' must be true or false")
    hub.tick(x.now)
    const m = hub.matches.get(matchId)
    if (!m || !m.seats.some((s) => s.pid === x.id)) throw blocked('no_match', 'the match is gone')
    if (m.state === 'confirm') hub.answer(x.id, m.id, b.accept, x.now) // 이미 시작했으면(다시 누름) 그대로
    return c.json(await view(x))
  })

  app.post('/v1/party/finish', auth, async (c) => {
    const b = await body(c)
    const runId = typeof b.run_id === 'string' ? b.run_id : ''
    if (!UUID_RE.test(runId)) throw new ApiError(400, 'bad_request', "'run_id' must be a run id")
    const elapsed = Number(b.elapsed)
    if (typeof b.win !== 'boolean' || !Number.isFinite(elapsed) || elapsed < 0) throw new ApiError(400, 'bad_request', "'win' and 'elapsed' are required")
    const x = await ctx(c)
    const [run] = await query(`select id::text as id, match_id, quest, diff, dps, boss_hp, extract(epoch from started_at)::float8 as started_at, closed, result
      from party_runs where id = $1 and player_id = $2`, [runId, x.id])
    if (!run) throw new ApiError(404, 'unknown_run', 'no such run')
    const quest = run.quest as PQ.Quest
    if (!run.closed) {
      // 결과: 방장이 방에서 알린 값(있으면). 없으면 보낸 값 — 승리이고 실시간 방에 방장이 없을 때만(연결이 끊겨 혼자 끝냄) 매치 결과로 남긴다
      // (도중에 나간 사람의 패배가 다른 성주들의 판을 패배로 만들지 않게)
      // 방에 방장이 있는데 아직 결과가 없으면 보낸 승리는 믿지 않는다(앱은 방의 end를 받은 뒤에 보낸다 — 먼저 오는 건 포기·끊김)
      const hostLive = !!live?.rooms.get(run.match_id)?.host
      if (b.win && !hostLive) hub.report(run.match_id, true, elapsed)
      const told = hub.matches.get(run.match_id)?.result ?? { win: b.win && !hostLive, elapsed }
      const real = x.now - Number(run.started_at)
      const limit = PQ.TIME_LIMIT[quest]
      const plausible = told.elapsed >= PQ.MIN_CLEAR_SEC && told.elapsed <= limit + 5 && real >= told.elapsed / R.MAX_GAME_SPEED - R.RUN_SLACK_SEC
        && real <= R.RUN_TTL_SEC && Number(run.dps) * told.elapsed * PQ.DPS_SLACK >= Number(run.boss_hp)
      const win = told.win && plausible
      const st = (await stats(x))[quest]
      const reward = win && st.clears_left > 0
      const item = reward ? R.rollItem(PQ.ACCESSORY[quest], null, PQ.dropGrade(R.EQUIP_GRADES, Number(run.diff), random), random) : null
      // 먼저 run을 닫는다(한 요청만 이긴다) — 그 요청이 보상을 준다
      const [closed] = await query(`with r as (update party_runs set closed = true, result = $3::jsonb where id = $1 and player_id = $2 and not closed returning quest, diff),
          s as (insert into party_stats (player_id, quest, best, day, clears) select $2, quest, case when $4 then diff else 0 end, $5, case when $6 then 1 else 0 end from r
            on conflict (player_id, quest) do update set best = greatest(party_stats.best, excluded.best),
              clears = case when party_stats.day = excluded.day then party_stats.clears + excluded.clears else excluded.clears end, day = excluded.day returning 1)
          select (select count(*) from r)::int as n`,
      [runId, x.id, JSON.stringify({ win, rewards: item ? { items: [item] } : {}, claimed_win: b.win, no_reward: win && !reward }), win, x.today, reward])
      if (Number(closed?.n) === 1 && item) {
        for (let i = 0; i < 4; i++) {
          const pl = await loadPlayer(x.id, x.game, x.now)
          const r = await commit(x.id, pl.version, { items: [item], log: { kind: 'party_clear', detail: { run_id: runId, quest, diff: Number(run.diff), item } } }, x.now)
          if (r) break
        }
      }
    }
    if (hub.matches.get(run.match_id)?.seats.some((s) => s.pid === x.id && !s.left)) hub.release(x.id) // 끝낸 판에서 놓아준다(다음 매칭)
    const [done] = await query('select result from party_runs where id = $1', [runId])
    const pl2 = await loadPlayer(x.id, x.game, x.now)
    return c.json({ ...playerView(pl2, x.game, x.now), ...(await view({ ...x, pl: pl2 })), result: json(done.result) }) // 플레이어 응답(보관함) + party + 결과
  })

  if (live) {
    live.verify = verifyToken
    live.seatOf = (matchId, pid) => {
      const m = hub.matches.get(matchId)
      return m && m.state === 'live' ? m.seats.findIndex((s) => s.pid === pid) : -1
    }
    live.onEnd = (matchId, _pid, win, elapsed) => hub.report(matchId, win, elapsed)
  }

  // 테스트 훅: AI 성주 대기 시간 없이 바로 채운다(혼자 시험).
  if (d.testHooks) {
    app.post('/v1/test/party_bots_now', auth, async (c) => {
      const x = await ctx(c)
      const t = hub.ticketOf(x.id)
      if (t) t.since = x.now - PQ.BOT_WAIT_SEC
      return c.json(await view(x))
    })
  }
  return hub
}

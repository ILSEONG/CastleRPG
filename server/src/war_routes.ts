// 길드전(공성전) 엔드포인트(마이그레이션 021, 규칙 guild_war.ts, 실시간 방 war_live.ts). createApp 안에서 registerGuildWar로 붙인다 —
// 길드 쪽 읽기(guildCtx)·쓰기(commit — 다이아·길드 코인)를 그대로 쓴다.
//  GET  /v1/guild/war           → {server_now, war}
//  POST /v1/guild/war/defense   {heroes: [{id, hp, atk}] × 4}  내 수비 영웅(보유 영웅, 능력치는 capStats로 자른다)
//  POST /v1/guild/war/schedule  {day: 0~6, hour: 0~23}         이번 주 공성 시각을 정한다(길드원 누구나, 그 시각이 오기 전까지)
//  POST /v1/guild/war/enter     {heroes: [{id, hp, atk}] × 4}  이번 주 공성 전투에 들어간다(공성 시각 ~ +BATTLE_SEC 사이, 없으면 연다) → {war, plan}
//  POST /v1/guild/war/finish    {battle_id, state}             방이 없을 때(실시간 연결 실패) 방장 기기가 결과를 직접 보낸다
//  POST /v1/guild/war/claim                                    지난 주 결과 보상(승리·패배)
// 응답의 war = warView: 이번 주 상대·점수·성 상태·오늘 전투·내 수비 영웅·길드원 수비 힘·받을 보상.
import type { Hono } from 'hono'
import * as W from './guild_war.ts'
import * as G from './guild.ts'
import * as R from './rules.ts'
import { mulberry32 } from './rules.ts'
import { LIVE_PATH } from './war_live.ts'
import type { WarLive } from './war_live.ts'

const json = (v: unknown) => (typeof v === 'string' ? JSON.parse(v) : v)

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Any = any

export function registerGuildWar(app: Hono<Any>, d: Any, live: WarLive | undefined) {
  const { query, auth, clock, loadGame, loadPlayer, guildCtx, commit, view, body, strField, blocked, rowOf, needGuild, grant, ApiError } = d

  const cfgOf = (game: Any) => (k: string) => R.cfgNum(game.config, k)
  const defsOf = (game: Any): W.HeroDef[] => game.heroes.map((h: Any) => ({ id: String(h.id), role: String(h.role), hp: Number(h.hp), atk: Number(h.atk),
    atk_interval: Number(h.atk_interval), grade: String(h.grade) }))

  // 우리 길드원(실제 + 앉은 가상): {key, name, power, real, player_id?, vi?}
  function ourMembers(x: Any) {
    const cap = G.capacity(x.st.lv.level)
    const out: { key: string; name: string; power: number; real: boolean; vi?: number }[] = []
    for (const m of x.members) out.push({ key: m.player_id, name: G.playerName(m.player_id), power: Number(m.power), real: true })
    for (const vm of G.seated(x.st.vt.members, x.now, cap, x.members.length)) {
      out.push({ key: `v:${vm.i}`, name: vm.name, power: x.st.vt.day[vm.i]?.power ?? vm.power0, real: false, vi: vm.i })
    }
    return out
  }

  // 이번 주 전쟁 행(없으면 만든다 — 상대 힘은 지금 우리 길드원 평균으로 그 주 내내 고정).
  async function warRow(x: Any, week: number) {
    const [r] = await query(`select enemy_seed, power, members, castle, extract(epoch from battle_at)::float8 as battle_at, battle_by
      from guild_wars where guild_id = $1 and week = $2`, [x.g.id, week])
    if (r) {
      return { seed: Number(r.enemy_seed), power: Number(r.power), members: Number(r.members), castle: json(r.castle) as W.Castle,
        at: W.battleAt(week, r.battle_at == null ? null : Number(r.battle_at), (d) => R.resetAt(d, x.hour)), by: r.battle_by == null ? '' : String(r.battle_by),
        set: r.battle_at != null }
    }
    const ms = ourMembers(x)
    const avg = Math.round(ms.reduce((a, m) => a + m.power, 0) / Math.max(1, ms.length))
    const seed = W.enemySeed(Number(x.g.seed), week)
    const n = G.capacity(x.st.lv.level)
    const enemy = W.enemyGuild(seed, n, avg, defsOf(x.game), cfgOf(x.game))
    await query(`insert into guild_wars (guild_id, week, enemy_seed, power, members, castle) values ($1, $2, $3, $4, $5, $6::jsonb)
      on conflict (guild_id, week) do nothing`, [x.g.id, week, seed, avg, n, JSON.stringify(W.freshCastle(enemy.defenders))])
    return warRow(x, week)
  }

  const enemyOf = (x: Any, w: Any) => W.enemyGuild(w.seed, w.members, w.power, defsOf(x.game), cfgOf(x.game))

  // 그 주 공성 전투(한 주 하나).
  async function battleOf(gid: string, week: number) {
    const [b] = await query(`select id::text, week, day, extract(epoch from started_at)::float8 as started_at, extract(epoch from ends_at)::float8 as ends_at,
      roster, closed from guild_war_battles where guild_id = $1 and week = $2 order by started_at limit 1`, [gid, week])
    return b ? { id: String(b.id), started_at: Number(b.started_at), ends_at: Number(b.ends_at), roster: json(b.roster) as Any[], closed: Boolean(b.closed) } : null
  }

  async function defenseOf(ids: string[]) {
    if (!ids.length) return new Map<string, Any[]>()
    const rows = await query('select player_id::text, heroes from war_defense where player_id = any($1::uuid[])', [ids])
    return new Map<string, Any[]>(rows.map((r: Any) => [String(r.player_id), json(r.heroes)]))
  }

  // 우리 수비 힘(상대 점수의 기준): 실제 길드원은 고른 수비 영웅 전투력 합(없으면 배치 전투력), 가상은 전투력.
  async function ourDefense(x: Any) {
    const ms = ourMembers(x)
    const defense = await defenseOf(ms.filter((m) => m.real).map((m) => m.key))
    const cfg = cfgOf(x.game)
    const defs = defsOf(x.game)
    let total = 0
    for (const m of ms) {
      const hs = defense.get(m.key)
      if (hs && hs.length) {
        total += hs.reduce((a: number, h: Any) => {
          const def = defs.find((dd) => dd.id === h.hero)
          return a + (Number.isFinite(h.power) ? Number(h.power) : def ? W.heroPower(def, h.level, h.promotion, cfg) : 0) // 장비 포함(앱 hero_power와 같다)
        }, 0)
      } else total += m.power
    }
    return { total, members: ms, defense }
  }

  async function warView(x: Any) {
    const { g } = needGuild(x)
    const day = R.resetDay(x.now, x.hour)
    const week = W.weekOf(day)
    const w = await warRow(x, week)
    const enemy = enemyOf(x, w)
    const mx = W.castleMax(enemy.defenders)
    const ours = await ourDefense(x)
    const ratio = enemy.power / Math.max(1, ours.total)
    const ends = w.at + W.BATTLE_SEC
    const enemyPts = x.now >= ends ? W.enemyPoints(w.seed, week, ratio, W.castleCap(ours.members.length)) : 0 // 상대 공성은 우리 공성 시간이 끝나면 보인다
    const b = await battleOf(g.id, week)
    const state = b?.closed || x.now >= ends ? 'done' : x.now < w.at ? 'waiting' : 'live'
    const mine = ours.defense.get(x.id) ?? []
    const out: Record<string, unknown> = {
      week, day: W.dayInWeek(day), week_ends: R.resetAt(W.weekStart(week + 1), x.hour),
      enemy: { name: enemy.name, emblem: enemy.emblem, power: enemy.power, members: enemy.members.length },
      points: W.castlePoints(w.castle, mx.keep), enemy_points: enemyPts, enemy_days: x.now >= ends ? [enemyPts] : [],
      schedule: { at: w.at, ends_at: ends, by: w.by, set: w.set, can_change: x.now < w.at },
      castle: { gates: w.castle.gates.map((hp, i) => ({ hp, max: mx.gates[i] })), keep: { hp: w.castle.keep, max: mx.keep },
        kills: W.killsIn(w.castle), defenders: enemy.defenders.length },
      battle: b ? { id: b.id, state, started_at: b.started_at, ends_at: b.ends_at, joined: b.roster.filter((s: Any) => !s.ai).length,
        me_in: b.roster.some((s: Any) => s.owner === x.id) } : { state, started_at: w.at, ends_at: ends },
      defense: mine.map((h: Any) => h.hero),
      members: ours.members.map((m) => ({ name: m.name, power: m.power, real: m.real, mine: m.key === x.id,
        defense: (ours.defense.get(m.key) ?? []).map((h: Any) => h.hero) })),
      claim: await claimable(x, week),
    }
    return out
  }

  // 지난 주 보상: 지난 주 전쟁 행이 있고 아직 안 받았으면 {week, win, points, enemy_points, reward}.
  async function claimable(x: Any, week: number) {
    const last = week - 1
    const [r] = await query('select 1 from guild_wars where guild_id = $1 and week = $2', [x.g.id, last])
    if (!r) return null
    const [c] = await query('select 1 from war_claims where player_id = $1 and week = $2', [x.id, last])
    if (c) return null
    const w = await warRow(x, last)
    const ours = await ourDefense(x)
    const enemy = enemyOf(x, w)
    const pts = W.castlePoints(w.castle, W.castleMax(enemy.defenders).keep)
    const ep = W.enemyPoints(w.seed, last, enemy.power / Math.max(1, ours.total), W.castleCap(ours.members.length))
    const win = pts > ep
    return { week: last, win, points: pts, enemy_points: ep, reward: win ? W.REWARD_WIN : W.REWARD_LOSE }
  }

  async function ctx(c: Any) {
    const id = c.get('playerId') as string
    const now = clock()
    const game = await loadGame()
    const pl = await loadPlayer(id, game, now)
    const x = await guildCtx(id, pl, game, now)
    return x
  }

  // 앱이 보낸 영웅 4명 → 보유 확인 + 레벨·승급은 서버 값, 능력치는 capStats.
  function squadOf(x: Any, raw: unknown): W.SquadHero[] {
    if (!Array.isArray(raw) || raw.length < 1 || raw.length > W.SQUAD) throw new ApiError(400, 'bad_request', `'heroes' must list 1-${W.SQUAD} heroes`)
    const seen = new Set<string>()
    const defs = defsOf(x.game)
    const cfg = cfgOf(x.game)
    const lim = R.statLimit(x.pl, x.game, x.st ? G.buffPct(x.st.lv.level) : 0) // 상한 = (기본 + 장비) × 내 성장·연구·길드 배율
    return raw.map((h: Any) => {
      const id = typeof h === 'string' ? h : String(h?.id ?? '')
      const own = x.pl.heroes[id]
      const def = defs.find((dd) => dd.id === id)
      if (!own || !def || seen.has(id)) throw blocked('bad_heroes', 'heroes must be 4 different heroes you own')
      seen.add(id)
      const lv = Number(own.level ?? 1)
      const pr = Number(own.promotion ?? 0)
      const s = W.capStats(def, lv, pr, h?.hp, h?.atk, cfg, lim)
      return { hero: id, level: lv, promotion: pr, hp: Math.round(s.hp), atk: Math.round(s.atk * 10) / 10,
        power: R.heroPower(def, lv, pr, lim.equip[id] ?? { hp: 0, atk: 0 }, x.game.config) }
    })
  }

  app.get('/v1/guild/war', auth, async (c) => {
    const x = await ctx(c)
    return c.json({ server_now: x.now, war: await warView(x) })
  })

  app.post('/v1/guild/war/defense', auth, async (c) => {
    const b = await body(c)
    const x = await ctx(c)
    needGuild(x)
    const sq = squadOf(x, b.heroes)
    await query(`insert into war_defense (player_id, heroes) values ($1, $2::jsonb) on conflict (player_id) do update set heroes = excluded.heroes`,
      [x.id, JSON.stringify(sq)])
    return c.json({ server_now: x.now, war: await warView(x) })
  })

  // 이번 주 공성 시각을 정한다: 길드원 누구나, 지금 정해진 시각이 오기 전까지. 새 시각은 지금보다 뒤여야 한다.
  app.post('/v1/guild/war/schedule', auth, async (c) => {
    const b = await body(c)
    const x = await ctx(c)
    const { g } = needGuild(x)
    const week = W.weekOf(R.resetDay(x.now, x.hour))
    const w = await warRow(x, week)
    if (x.now >= w.at) throw blocked('schedule_locked', "this week's siege time has already come")
    const at = W.pickAt(week, Number(b.day), Number(b.hour), (d) => R.resetAt(d, x.hour))
    if (at == null) throw new ApiError(400, 'bad_request', "'day' must be 0-6 and 'hour' 0-23 within this week")
    if (at <= x.now) throw blocked('schedule_past', 'pick a time later than now')
    const by = G.playerName(x.id)
    await query('update guild_wars set battle_at = to_timestamp($3::float8), battle_by = $4 where guild_id = $1 and week = $2 and (battle_at is null or battle_at > to_timestamp($5::float8))',
      [g.id, week, at, by, x.now])
    const dayNames = ['월', '화', '수', '목', '금', '토', '일']
    await query('insert into guild_log (guild_id, at, text) values ($1, to_timestamp($2::float8), $3)',
      [g.id, x.now, `${by}님이 이번 주 공성 시각을 ${dayNames[Number(b.day)]}요일 ${Number(b.hour)}:00로 정했습니다`])
    return c.json({ server_now: x.now, war: await warView(x) })
  })

  // 슈퍼관리자(Player.admin): 공성 시각을 기다리지 않는다 — 아직이면 지금으로 당기고, 이번 주 공성이 끝났거나 성채가 함락됐으면
  // 그 주 전투를 지우고 새 성으로 다시 연다(그 길드의 이번 주 점수가 처음부터). 진행 중이면 그대로 합류.
  async function adminOpen(x: Any, gid: string, week: number, w: Any) {
    const bt = await battleOf(gid, week)
    const over = w.castle.keep <= 0 || (bt && bt.closed) || x.now >= w.at + W.BATTLE_SEC
    if (x.now >= w.at && !over) return w
    if (over) {
      await query('delete from guild_war_battles where guild_id = $1 and week = $2', [gid, week])
      await query('update guild_wars set castle = $3::jsonb where guild_id = $1 and week = $2', [gid, week, JSON.stringify(W.freshCastle(enemyOf(x, w).defenders))])
    }
    await query('update guild_wars set battle_at = to_timestamp($3::float8), battle_by = $4 where guild_id = $1 and week = $2', [gid, week, x.now - 1, G.playerName(x.id)])
    return warRow(x, week)
  }

  // 이번 주 전투에 들어간다(공성 시각 ~ +BATTLE_SEC): 없으면 연다(가상 길드원 분대 + 나), 진행 중이면 내 분대를 더한다(방에 알린다). 끝났으면 막힌다.
  app.post('/v1/guild/war/enter', auth, async (c) => {
    const b = await body(c)
    const x = await ctx(c)
    const { g } = needGuild(x)
    const sq = squadOf(x, b.heroes)
    const day = R.resetDay(x.now, x.hour)
    const week = W.weekOf(day)
    let w = await warRow(x, week)
    if (x.pl.admin) w = await adminOpen(x, g.id, week, w)
    if (w.castle.keep <= 0) throw blocked('conquered', 'the enemy keep has already fallen this week')
    if (x.now < w.at) throw blocked('not_yet', "this week's siege has not started yet")
    let bt = await battleOf(g.id, week)
    if ((bt && bt.closed) || x.now >= w.at + W.BATTLE_SEC) throw blocked('battle_done', "this week's siege is over")
    let added: Any = null
    if (!bt) {
      const roster: Any[] = []
      const cfg = cfgOf(x.game)
      for (const m of ourMembers(x).filter((mm) => !mm.real)) {
        const r = mulberry32(G.mix(Number(g.seed), week, day >>> 0, m.vi ?? 0))
        const pw = m.power * (W.VIRTUAL_POWER_RANGE[0] + r() * (W.VIRTUAL_POWER_RANGE[1] - W.VIRTUAL_POWER_RANGE[0]))
        roster.push({ owner: m.key, name: m.name, squad: roster.length, lane: roster.length % 4, ai: true, heroes: W.randomSquad(r, defsOf(x.game), pw, cfg) })
      }
      added = { owner: x.id, name: G.playerName(x.id), squad: roster.length, lane: roster.length % 4, ai: false, heroes: sq }
      roster.push(added)
      await query(`insert into guild_war_battles (guild_id, week, day, started_at, ends_at, roster) values ($1, $2, $3, to_timestamp($4::float8),
        to_timestamp($5::float8), $6::jsonb) on conflict (guild_id, day) do nothing`, [g.id, week, R.resetDay(w.at, x.hour), w.at, w.at + W.BATTLE_SEC, JSON.stringify(roster)])
      bt = await battleOf(g.id, week)
      if (!bt || !bt.roster.some((s: Any) => s.owner === x.id)) added = null  // 겨뤄서 다른 사람이 먼저 열었다
    }
    if (bt && !bt.roster.some((s: Any) => s.owner === x.id)) {
      added = { owner: x.id, name: G.playerName(x.id), squad: bt.roster.length, lane: bt.roster.length % 4, ai: false, heroes: sq }
      await query(`update guild_war_battles set roster = roster || $2::jsonb where id = $1 and not (roster @> $3::jsonb)`,
        [bt.id, JSON.stringify([added]), JSON.stringify([{ owner: x.id }])])
      bt = await battleOf(g.id, week)
      added = bt?.roster.find((s: Any) => s.owner === x.id) ?? null
      if (added && live) live.broadcast(bt!.id, { t: 'roster', squad: added })
    }
    if (!bt) throw new ApiError(409, 'conflict', 'try again')
    const enemy = enemyOf(x, w)
    const mx = W.castleMax(enemy.defenders)
    const plan = {
      battle_id: bt.id, my_id: x.id, enemy_name: enemy.name, duration: W.BATTLE_SEC, clock: Math.max(0, x.now - bt.started_at),
      gates: w.castle.gates.map((hp, i) => ({ hp, max: mx.gates[i] })), keep: { hp: w.castle.keep, max: mx.keep },
      defenders: enemy.defenders.map((dd) => ({ ...dd, ratio: W.ratioOf(w.castle, dd.uid) })).filter((dd) => dd.ratio > 0),
      attackers: bt.roster, live: live ? LIVE_PATH : '',
    }
    return c.json({ server_now: x.now, war: await warView(x), plan })
  })

  // 성 상태 합치기(실시간 방의 ckpt·end, 또는 REST finish). 그 전투의 로스터에 있는 사람만. final이면 전투를 닫는다.
  async function saveState(battleId: string, pid: string, state: Any, final: boolean) {
    const [b] = await query(`select guild_id::text, week, roster, closed from guild_war_battles where id = $1`, [battleId])
    if (!b || Boolean(b.closed)) return false
    if (!(json(b.roster) as Any[]).some((s) => s.owner === pid)) return false
    const now = clock()
    const game = await loadGame()
    const pl = await loadPlayer(pid, game, now)
    const x = await guildCtx(pid, pl, game, now)
    if (!x.g || x.g.id !== String(b.guild_id)) return false
    const w = await warRow(x, Number(b.week))
    const enemy = enemyOf(x, w)
    const merged = W.mergeCastle(w.castle, state && typeof state === 'object' ? state : {}, enemy.defenders)
    await query('update guild_wars set castle = $3::jsonb where guild_id = $1 and week = $2', [x.g.id, Number(b.week), JSON.stringify(merged)])
    if (final || merged.keep <= 0) await query('update guild_war_battles set closed = true where id = $1', [battleId])
    return true
  }

  app.post('/v1/guild/war/finish', auth, async (c) => {
    const b = await body(c)
    const battleId = strField(b, 'battle_id')
    const id = c.get('playerId') as string
    if (live && live.hostOf(battleId) && live.hostOf(battleId) !== id) throw blocked('not_host', 'another member is running this battle')
    await saveState(battleId, id, b.state, true)
    const x = await ctx(c)
    return c.json({ server_now: x.now, war: await warView(x) })
  })

  app.post('/v1/guild/war/claim', auth, async (c) => {
    const id = c.get('playerId') as string
    for (let i = 0; i < 4; i++) {
      const x = await ctx(c)
      needGuild(x)
      const week = W.weekOf(R.resetDay(x.now, x.hour))
      const cl = await claimable(x, week)
      if (!cl) throw blocked('nothing', 'no war reward to claim')
      const [ins] = await query('insert into war_claims (player_id, week) values ($1, $2) on conflict do nothing returning 1', [id, cl.week])
      if (!ins) throw blocked('nothing', 'no war reward to claim')
      const ch: Any = {}
      const coins = { n: x.pg.coins }
      grant(x, cl.reward, ch, coins)
      ch.guild = { row: rowOf(x, { coins: coins.n }) }
      if (!(await commit(id, x.pl.version, ch, x.now))) {
        await query('delete from war_claims where player_id = $1 and week = $2', [id, cl.week])
        continue
      }
      const pl2 = await loadPlayer(id, x.game, x.now)
      const x2 = await guildCtx(id, pl2, x.game, x.now)
      return c.json({ ...view(pl2, x.game, x.now), war: await warView(x2), result: cl })
    }
    throw new ApiError(409, 'conflict', 'concurrent update; try again')
  })

  // 통합 체크·화면 확인용(ALLOW_TEST_HOOKS): 이번 주 공성 시각을 지금으로 당긴다(시계를 못 돌리는 앱 체크가 전투를 연다).
  if (d.testHooks) {
    app.post('/v1/test/war_now', auth, async (c) => {
      const x = await ctx(c)
      const { g } = needGuild(x)
      const week = W.weekOf(R.resetDay(x.now, x.hour))
      await warRow(x, week)
      await query('update guild_wars set battle_at = to_timestamp($3::float8), battle_by = $4 where guild_id = $1 and week = $2', [g.id, week, x.now - 1, 'test'])
      return c.json({ server_now: x.now, war: await warView(x) })
    })
  }

  // 실시간 방 연결: 토큰 확인·로스터 확인·성 상태 저장.
  if (live) {
    live.verify = d.verifyToken
    live.canJoin = async (battleId: string, pid: string) => {
      if (!/^[0-9a-f-]{36}$/i.test(battleId)) return false
      const [b] = await query('select roster, closed, extract(epoch from ends_at)::float8 as ends_at from guild_war_battles where id = $1', [battleId])
      return !!b && !b.closed && clock() < Number(b.ends_at) + 30 && (json(b.roster) as Any[]).some((s) => s.owner === pid)
    }
    live.onState = async (battleId: string, pid: string, state: unknown, final: boolean) => {
      await saveState(battleId, pid, state, final)
    }
  }
}

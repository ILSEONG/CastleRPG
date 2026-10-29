// 랭킹(GET /v1/ranking/:board, 던전 랭킹은 사용자 요청으로 뺐다). 새 표 없이 지금 있는 표에서 계산한다(마이그레이션 없음).
// - stage: 실제 플레이어의 도달 라운드(player_state.stage, 전체 라운드). 같으면 먼저 도달한 사람(last_stage_clear)이 위.
// - power: 배치 영웅 전투력(guild.ts teamPower, 장비 포함 — 길드원 목록·영웅 목록과 같은 값). 0이면 뺀다.
// - guild: 주간 시즌(2026-10-29 사용자: "길드 랭킹은 드래곤 보스 길드 총 피해량으로"). 이번 주(월요일 0시 KST ~) 길드원이 드래곤에 준
//   피해 합 순(실제 길드원 = guild_week_damage, 가상 길드원 몫은 G.virtualDmgBetween). 피해 0인 길드는 뺀다. 같으면 누적 경험치 → 만든 순.
//   주가 바뀌면 지난 주 순위로 보상 우편(settle): 1위 최고급, 2~10위 고급, 11~100위 일반 장비 상자 — 그 길드의 실제 길드원 모두.
// 이름: 플레이어는 별명 칸이 없어 길드원 목록과 같은 G.playerName(id)을 쓴다. 목록은 RANK_CACHE_SEC 동안 재사용한다(내 순위는 그 목록에서 찾는다).
import type { Query, Row } from './db.ts'
import * as G from './guild.ts'
import * as R from './rules.ts'
import { weekOf, weekStart } from './guild_war.ts'
import { txt } from './texts.ts'

export { weekOf }

export const BOARDS = ['stage', 'power', 'guild'] as const
export type Board = (typeof BOARDS)[number]
export const TOP_N = 50
export const GUILD_TOP_N = 100 // 길드 보드는 보상 순위(100위)까지 보인다
// 길드 랭킹 주간 보상 [마지막 순위, 보상]: 1위 / 2~10위 / 11~100위(2026-10-29 사용자). 상자 = rules.EQUIP_BOXES.
export const GUILD_REWARDS: [number, Record<string, number>][] = [[1, { equip_box_top: 1 }], [10, { equip_box_high: 1 }], [100, { equip_box_normal: 1 }]]
export const guildReward = (rank: number) => GUILD_REWARDS.find(([last]) => rank <= last)?.[1] ?? null
export const MAIL_DAYS = 14 // 보상 우편 보관 기간
export const RANK_CACHE_SEC = 30

export interface Entry {
  key: string // 플레이어 id 또는 길드 id(응답에는 안 나간다)
  name: string
  value: number // 정렬 값(stage = 도달 라운드, power, guild = 레벨)
  t: number // 같은 값끼리 순서(작을수록 위)
  guild?: string // 플레이어가 든 길드 이름
  emblem?: number
  members?: number
  exp?: number
  boss?: number
  level?: number
  tie?: number // 같은 값끼리 앞 순서(클수록 위, guild = 누적 경험치)
}

export const PLAYERS_SQL = `select s.player_id::text as id, s.stage, extract(epoch from s.last_stage_clear)::float8 as t, s.deploy, s.slot_levels,
  coalesce((select level from player_buildings b where b.player_id = s.player_id and b.building = $1), 1) as keep,
  coalesce((select json_object_agg(hero_id, json_build_object('level', level, 'promotion', promotion)) from player_heroes h where h.player_id = s.player_id), '{}'::json) as heroes,
  coalesce((select json_agg(json_build_object('hero_id', e.hero_id, 'item_id', i.id, 'id', i.id, 'slot', i.slot, 'grade', i.grade, 'rolls', i.rolls))
    from player_equipment e join player_items i on i.id = e.item_id where e.player_id = s.player_id), '[]'::json) as equip,
  g.name as guild
  from player_state s left join player_guild pg on pg.player_id = s.player_id left join guilds g on g.id = pg.guild_id`

export const GUILDS_SQL = `select g.id::text, g.name, g.emblem, g.owner::text, g.seed, extract(epoch from g.created_at)::float8 as created_at, g.virtual_n, g.exp,
  g.boss_damage, (select count(*)::int from player_guild m where m.guild_id = g.id) as real_n,
  coalesce((select w.dmg from guild_week_damage w where w.guild_id = g.id and w.week = $1), 0) as week_dmg from guilds g`

const json = (v: unknown) => (typeof v === 'string' ? JSON.parse(v) : v)

// 정렬: 값 큰 순 → tie 큰 순 → t 작은 순 → key.
export function sortEntries(xs: Entry[]): Entry[] {
  return xs.sort((a, b) => b.value - a.value || (b.tie ?? 0) - (a.tie ?? 0) || a.t - b.t || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0))
}

export interface GameLike {
  heroes: Record<string, any>[]
  config: R.Config
}

export function playerEntries(rows: Row[], board: Board, game: GameLike): Entry[] {
  const cfg = (k: string) => R.cfgNum(game.config, k)
  const defs = game.heroes.map((h) => ({ id: String(h.id), role: String(h.role), atk: Number(h.atk), hp: Number(h.hp), atk_interval: Number(h.atk_interval), grade: String(h.grade) }))
  const out: Entry[] = []
  for (const r of rows) {
    const base = { key: String(r.id), name: G.playerName(String(r.id)), guild: r.guild == null ? undefined : String(r.guild), t: Number(r.t) }
    if (board === 'stage') {
      out.push({ ...base, value: Number(r.stage) })
    } else {
      const heroes = json(r.heroes) as Record<string, { level: number; promotion: number }>
      const raw = json(r.deploy)
      const slots = R.heroSlots(game.config, Number(r.keep))
      const deploy = Array.isArray(raw) ? raw.slice(0, slots).filter((x): x is string => typeof x === 'string' && Object.hasOwn(heroes, x)) : []
      const eq = (json(r.equip ?? '[]') as any[]).map((x) => ({ id: Number(x.id), hero_id: String(x.hero_id), item_id: Number(x.item_id), slot: String(x.slot), weapon_kind: null, grade: String(x.grade), level: Number(x.level) }))
      const power = G.teamPower(deploy, heroes, defs, cfg, R.heroEquip(eq, eq, R.cleanSlotLevels(json(r.slot_levels ?? '{}'))))
      if (power > 0) out.push({ ...base, value: power, t: 0 })
    }
  }
  return sortEntries(out)
}

// 주 week의 길드 순위. until = 이 시각까지 낸 피해(진행 중인 주 = 지금, 정산 = 그 주 끝).
export function guildEntries(rows: Row[], until: number, hour: number, week: number): Entry[] {
  const out: Entry[] = []
  const from = weekStart(week)
  for (const r of rows) {
    const g = { id: String(r.id), seed: Number(r.seed), created_at: Number(r.created_at), virtual_n: Number(r.virtual_n),
      system: r.owner == null && Number(r.virtual_n) >= G.SYSTEM_VIRTUAL[0] }
    if (g.created_at > until) continue
    const vt = G.virtualTotals(g, until, hour)
    const dmg = Number(r.week_dmg) + G.virtualDmgBetween(g, from, from + 6, until, hour)
    if (dmg <= 0) continue
    const exp = Number(r.exp) + vt.exp
    const virtualNow = vt.members.filter((m) => m.join_t <= until).length
    out.push({
      key: g.id, name: String(r.name), emblem: Number(r.emblem), value: dmg, tie: exp, t: g.created_at,
      members: virtualNow + Number(r.real_n), exp, level: G.levelOf(exp).level, boss: Number(r.boss_damage) + vt.dmg,
    })
  }
  return sortEntries(out)
}

// 응답 한 줄(순위는 1부터, 같은 값이어도 순서대로 매긴다).
export function view(e: Entry, rank: number, me: boolean) {
  const out: Record<string, unknown> = { rank, name: e.name, value: e.value, me }
  if (e.guild !== undefined) out.guild = e.guild
  if (e.emblem !== undefined) Object.assign(out, { emblem: e.emblem, members: e.members, boss: e.boss, level: e.level })
  return out
}

// 목록 캐시(보드마다). 플레이어 보드는 한 번 읽어 넷을 함께 만든다.
export function rankingStore(query: Query, clock: () => number, loadGame: () => Promise<GameLike>) {
  const cache = new Map<Board, { at: number; list: Entry[] }>()
  // 만드는 중인 목록(플레이어 보드 둘은 'player' 하나). 캐시가 끝난 순간 몰린 요청이 다 같이 전체 플레이어를 읽지 않고 한 번을 기다린다.
  const building = new Map<string, Promise<{ at: number; list: Entry[] }>>()
  function list(board: Board): Promise<{ at: number; list: Entry[] }> {
    const now = clock()
    const hit = cache.get(board)
    if (hit && now - hit.at < RANK_CACHE_SEC && now >= hit.at) return Promise.resolve(hit)
    const key = board === 'guild' ? 'guild' : 'player'
    let p = building.get(key)
    if (!p) {
      p = rebuild(board, now).finally(() => building.delete(key))
      building.set(key, p)
    }
    return p.then(() => cache.get(board)!)
  }
  async function rebuild(board: Board, now: number): Promise<{ at: number; list: Entry[] }> {
    const game = await loadGame()
    if (board === 'guild') {
      const hour = R.cfgNum(game.config, 'daily_reset_utc_hour')
      const week = weekOf(R.resetDay(now, hour))
      // 주간 표(059)가 아직 없는 DB(배포와 마이그레이션 사이)면 빈 목록 — 길드 랭킹만 비고 다른 보드·부팅은 그대로
      const rows = await query(GUILDS_SQL, [week]).catch((e) => (console.error('guild ranking failed', e), [] as Row[]))
      const v = { at: now, list: guildEntries(rows, now, hour, week) }
      cache.set(board, v)
      return v
    }
    const rows = await query(PLAYERS_SQL, [R.KEEP])
    for (const b of BOARDS) if (b !== 'guild') cache.set(b, { at: now, list: playerEntries(rows, b, game) })
    return cache.get(board)!
  }
  // 지난 주 길드 랭킹 정산(한 번만): 그 주 순위 → 보상 순위 안 길드의 실제 길드원(그 주 끝 전에 가입)에게 우편.
  // guild_rank_settled 행을 넣는 같은 문장이 우편을 넣는다 — 서버 여러 대·몰린 요청이 겨뤄도 한 번만 보낸다.
  // 실제 길드원 피해 기록(guild_week_damage)이 하나도 없는 주는 우편 없이 정산만 한다(기능이 생기기 전 주·아무도 안 친 주).
  let settledWeek = -1
  let settling: Promise<void> | null = null
  async function settleOnce(now: number) {
    const game = await loadGame()
    const hour = R.cfgNum(game.config, 'daily_reset_utc_hour')
    const week = weekOf(R.resetDay(now, hour)) - 1
    if (week <= settledWeek) return
    if ((await query('select 1 from guild_rank_settled where week = $1', [week])).length) {
      settledWeek = week
      return
    }
    const end = R.resetAt(weekStart(week + 1), hour)
    const real = (await query('select count(*)::int as n from guild_week_damage where week = $1 and dmg > 0', [week]))[0]
    const list = Number(real?.n ?? 0) > 0 ? guildEntries(await query(GUILDS_SQL, [week]), end - 1e-3, hour, week) : []
    const ids: string[] = []
    const ranks: number[] = []
    const rewards: string[] = []
    list.forEach((e, i) => {
      const rw = guildReward(i + 1)
      if (rw) { ids.push(e.key); ranks.push(i + 1); rewards.push(JSON.stringify(rw)) }
    })
    await query(`with s as (insert into guild_rank_settled (week, guilds) values ($1, $2) on conflict (week) do nothing returning week),
      r as (select * from unnest($3::uuid[], $4::int[], $5::jsonb[]) as t(gid, rk, reward))
      insert into mails (player_id, title, body, reward, created_at, expires_at)
      select pg.player_id, $6, replace(replace($7, '{rank}', r.rk::text), '{guild}', g.name), r.reward,
        to_timestamp($8::float8), to_timestamp($8::float8) + make_interval(days => $9)
      from r join guilds g on g.id = r.gid join player_guild pg on pg.guild_id = r.gid
      where exists (select 1 from s) and (pg.joined_at is null or pg.joined_at < to_timestamp($10::float8))`,
    [week, ids.length, ids, ranks, rewards, txt('server.ranking.guild_mail.title'), txt('server.ranking.guild_mail.body'), now, MAIL_DAYS, end])
    settledWeek = week
  }
  function settle(): Promise<void> {
    if (!settling) settling = settleOnce(clock()).finally(() => { settling = null })
    return settling
  }
  // myKey: 플레이어 보드 = 내 id, guild = 내 길드 id(없으면 null)
  async function board(board: Board, myKey: string | null) {
    const { at, list: xs } = await list(board)
    const i = myKey == null ? -1 : xs.findIndex((e) => e.key === myKey)
    const n = board === 'guild' ? GUILD_TOP_N : TOP_N
    const out: Record<string, unknown> = {
      board, updated_at: at, total: xs.length,
      top: xs.slice(0, n).map((e, k) => view(e, k + 1, k === i)),
      me: i >= 0 ? view(xs[i], i + 1, true) : null,
    }
    if (board === 'guild') {
      const hour = R.cfgNum((await loadGame()).config, 'daily_reset_utc_hour')
      const week = weekOf(R.resetDay(at, hour))
      out.season = { week, ends_at: R.resetAt(weekStart(week + 1), hour), in_guild: myKey != null,
        rewards: GUILD_REWARDS.map(([last, reward], k) => ({ from: k === 0 ? 1 : GUILD_REWARDS[k - 1][0] + 1, to: last, reward })),
        boxes: R.EQUIP_BOXES }
    }
    return out
  }
  return { board, settle, clear: () => { cache.clear(); building.clear(); settledWeek = -1 } }
}

// 랭킹(GET /v1/ranking/:board). 새 표 없이 지금 있는 표에서 계산한다(마이그레이션 없음).
// - stage: 실제 플레이어의 도달 라운드(player_state.stage, 전체 라운드). 같으면 먼저 도달한 사람(last_stage_clear)이 위.
// - power: 배치 영웅 전투력(guild.ts teamPower — 길드원 목록과 같은 값). 0이면 뺀다.
// - dungeon_gold / dungeon_equip: 던전 최고 단계(player_dungeons.best_level). 0이면 뺀다.
// - guild: 모든 길드(직접 만든 길드 + 서버가 만든 시스템 길드). 길드 레벨 → 누적 경험치 → 보스 단계 순. 가상 길드원 몫은
//   길드 화면과 같은 계산(G.virtualTotals)으로 더한다.
// 이름: 플레이어는 별명 칸이 없어 길드원 목록과 같은 G.playerName(id)을 쓴다. 목록은 RANK_CACHE_SEC 동안 재사용한다(내 순위는 그 목록에서 찾는다).
import type { Query, Row } from './db.ts'
import * as G from './guild.ts'
import * as R from './rules.ts'

export const BOARDS = ['stage', 'power', 'dungeon_gold', 'dungeon_equip', 'guild'] as const
export type Board = (typeof BOARDS)[number]
export const TOP_N = 50
export const RANK_CACHE_SEC = 30

export interface Entry {
  key: string // 플레이어 id 또는 길드 id(응답에는 안 나간다)
  name: string
  value: number // 정렬 값(stage = 도달 라운드, power, 던전 단계, guild = 레벨)
  t: number // 같은 값끼리 순서(작을수록 위)
  guild?: string // 플레이어가 든 길드 이름
  emblem?: number
  members?: number
  exp?: number
  boss?: number
  tie?: number // 같은 값끼리 앞 순서(클수록 위, guild = 누적 경험치)
}

export const PLAYERS_SQL = `select s.player_id::text as id, s.stage, extract(epoch from s.last_stage_clear)::float8 as t, s.deploy,
  coalesce((select level from player_buildings b where b.player_id = s.player_id and b.building = $1), 1) as keep,
  coalesce((select json_object_agg(hero_id, json_build_object('level', level, 'promotion', promotion)) from player_heroes h where h.player_id = s.player_id), '{}'::json) as heroes,
  coalesce((select json_object_agg(type, best_level) from player_dungeons d where d.player_id = s.player_id), '{}'::json) as dungeons,
  g.name as guild
  from player_state s left join player_guild pg on pg.player_id = s.player_id left join guilds g on g.id = pg.guild_id`

export const GUILDS_SQL = `select g.id::text, g.name, g.emblem, g.owner::text, g.seed, extract(epoch from g.created_at)::float8 as created_at, g.virtual_n, g.exp,
  g.boss_damage, (select count(*)::int from player_guild m where m.guild_id = g.id) as real_n from guilds g`

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
    } else if (board === 'power') {
      const heroes = json(r.heroes) as Record<string, { level: number; promotion: number }>
      const raw = json(r.deploy)
      const slots = R.heroSlots(game.config, Number(r.keep))
      const deploy = Array.isArray(raw) ? raw.slice(0, slots).filter((x): x is string => typeof x === 'string' && Object.hasOwn(heroes, x)) : []
      const power = G.teamPower(deploy, heroes, defs, cfg)
      if (power > 0) out.push({ ...base, value: power, t: 0 })
    } else {
      const best = Number((json(r.dungeons) as Record<string, number>)[board === 'dungeon_gold' ? 'gold' : 'equip'] ?? 0)
      if (best > 0) out.push({ ...base, value: best, t: 0 })
    }
  }
  return sortEntries(out)
}

export function guildEntries(rows: Row[], now: number, hour: number): Entry[] {
  const out: Entry[] = []
  for (const r of rows) {
    const g = { id: String(r.id), seed: Number(r.seed), created_at: Number(r.created_at), virtual_n: Number(r.virtual_n),
      system: r.owner == null && Number(r.virtual_n) >= G.SYSTEM_VIRTUAL[0] }
    const vt = G.virtualTotals(g, now, hour)
    const exp = Number(r.exp) + vt.exp
    const virtualNow = vt.members.filter((m) => m.join_t <= now).length
    out.push({
      key: g.id, name: String(r.name), emblem: Number(r.emblem), value: G.levelOf(exp).level, tie: exp, t: g.created_at,
      members: virtualNow + Number(r.real_n), exp, boss: G.bossOf(Number(r.boss_damage) + vt.dmg).level,
    })
  }
  return sortEntries(out)
}

// 응답 한 줄(순위는 1부터, 같은 값이어도 순서대로 매긴다).
export function view(e: Entry, rank: number, me: boolean) {
  const out: Record<string, unknown> = { rank, name: e.name, value: e.value, me }
  if (e.guild !== undefined) out.guild = e.guild
  if (e.emblem !== undefined) Object.assign(out, { emblem: e.emblem, members: e.members, boss: e.boss })
  return out
}

// 목록 캐시(보드마다). 플레이어 보드는 한 번 읽어 넷을 함께 만든다.
export function rankingStore(query: Query, clock: () => number, loadGame: () => Promise<GameLike>) {
  const cache = new Map<Board, { at: number; list: Entry[] }>()
  async function list(board: Board): Promise<{ at: number; list: Entry[] }> {
    const now = clock()
    const hit = cache.get(board)
    if (hit && now - hit.at < RANK_CACHE_SEC && now >= hit.at) return hit
    const game = await loadGame()
    if (board === 'guild') {
      const v = { at: now, list: guildEntries(await query(GUILDS_SQL), now, R.cfgNum(game.config, 'daily_reset_utc_hour')) }
      cache.set(board, v)
      return v
    }
    const rows = await query(PLAYERS_SQL, [R.KEEP])
    for (const b of BOARDS) if (b !== 'guild') cache.set(b, { at: now, list: playerEntries(rows, b, game) })
    return cache.get(board)!
  }
  // myKey: 플레이어 보드 = 내 id, guild = 내 길드 id(없으면 null)
  async function board(board: Board, myKey: string | null) {
    const { at, list: xs } = await list(board)
    const i = myKey == null ? -1 : xs.findIndex((e) => e.key === myKey)
    return {
      board, updated_at: at, total: xs.length,
      top: xs.slice(0, TOP_N).map((e, k) => view(e, k + 1, k === i)),
      me: i >= 0 ? view(xs[i], i + 1, true) : null,
    }
  }
  return { board, clear: () => cache.clear() }
}

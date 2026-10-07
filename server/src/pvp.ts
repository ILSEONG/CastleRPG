// PVP(사용자 2026-10-07, 마이그레이션 029, 엔드포인트 pvp_routes.ts) 규칙(순수 함수). 앱 scripts/pvp_rules.gd와 같은 수치·식.
// 모드 둘: duel(결투 — 영웅 5 대 5, 내 영웅은 조종, 상대는 AI), total(총력전 — 영웅 5 + 병사, 양쪽 다 AI). 실시간이 아니다:
// 상대 = 그 플레이어가 미리 정한 방어팀(pvp_stats.defense). 모드마다 하루 PLAYS번, 포인트·등급(브론즈~챌린저)이 따로다.
// 시작에 판 하나를 쓰고 패배로 먼저 적어 둔다(도중에 나가도 패배) — 승리로 끝나면 바로잡는다. 전투는 앱이 돌리고 서버는 결과가 그럴듯한지만 본다.
// 코인(PVP 코인) 하나를 두 모드가 함께 벌고 PVP 상점에서 쓴다.
import { MAX_GAME_SPEED, mulberry32, powerOf, type StatLimit } from './rules.ts'
import { mix, nickname } from './guild.ts'
import { capStats, fitHero, heroStats } from './guild_war.ts'
import type { HeroDef } from './guild_war.ts'

export const MODES = ['duel', 'total'] as const
export type Mode = (typeof MODES)[number]
export const TEAM = 5 // 한 팀 영웅 수
export const PLAYS = 5 // 모드마다 하루 판 수
export const BATTLE_SEC: Record<Mode, number> = { duel: 90, total: 120 } // 제한 시간(끝나면 남은 체력 비율이 큰 쪽이 이긴다 — 같으면 방어)
export const MIN_WIN_SEC = 8 // 시작 뒤 이 게임 초(x1.5 배속이면 실제 MIN_WIN_SEC ÷ 1.5초)보다 빨리 온 승리는 받지 않는다
export const LATE_SEC = 900 // 시작 뒤 이만큼 지나 온 결과는 받지 않는다(패배 그대로)
export const SOLDIER_CAP = 20 // 총력전 한 쪽 병사 수 상한(높은 티어부터)
export const WIN_BASE = 25 // 승리 포인트 = WIN_BASE + (상대 − 나) ÷ WIN_DIFF_DIV (± WIN_DIFF_CAP)
export const WIN_DIFF_DIV = 20
export const WIN_DIFF_CAP = 10
export const LOSS = 10 // 패배 포인트(0 아래로는 안 내려간다)
export const COINS_WIN = 30
export const COINS_LOSS = 10
export const MATCH_N = 10 // 포인트가 가장 가까운 실제 방어팀 이만큼 중 하나
export const MATCH_RANGE = 200 // 이 포인트 차 안에서만 실제 방어팀(없으면 봇)
export const BOT_POWER: [number, number] = [0.9, 1.05] // 봇 힘 = 내 기준 힘 × 이 범위
export const MIN_POWER = 250

// [id, 이름, 이 포인트 이상]
export const TIERS: [string, string, number][] = [
  ['bronze', '브론즈', 0], ['silver', '실버', 200], ['gold', '골드', 500], ['platinum', '플래티넘', 900],
  ['diamond', '다이아몬드', 1400], ['master', '마스터', 2000], ['challenger', '챌린저', 2700],
]

// PVP 상점(코인). period: day = 매일 리셋, week = 월요일 리셋(길드전과 같은 주).
export const SHOP: { id: string; give: Record<string, number>; price: number; limit: number; period: 'day' | 'week' }[] = [
  { id: 'gold', give: { gold: 30000 }, price: 60, limit: 3, period: 'day' },
  { id: 'equip', give: { equip: 1 }, price: 50, limit: 3, period: 'day' },
  { id: 'dia', give: { diamonds: 50 }, price: 150, limit: 2, period: 'day' },
  { id: 'ticket', give: { tickets: 1 }, price: 250, limit: 1, period: 'day' },
  { id: 'shards', give: { shards: 3 }, price: 200, limit: 5, period: 'week' },
  { id: 'ssr', give: { ssr_shards: 1 }, price: 600, limit: 2, period: 'week' },
]

export const isMode = (m: unknown): m is Mode => typeof m === 'string' && (MODES as readonly string[]).includes(m)

export function tierOf(points: number): { id: string; name: string; min: number; next: number | null } {
  let i = 0
  while (i + 1 < TIERS.length && points >= TIERS[i + 1][2]) i++
  return { id: TIERS[i][0], name: TIERS[i][1], min: TIERS[i][2], next: i + 1 < TIERS.length ? TIERS[i + 1][2] : null }
}

export const winGain = (me: number, opp: number) =>
  WIN_BASE + Math.max(-WIN_DIFF_CAP, Math.min(WIN_DIFF_CAP, Math.round((opp - me) / WIN_DIFF_DIV)))
export const lossOf = (me: number) => Math.min(LOSS, Math.max(0, me))

export interface TeamHero { hero: string; level: number; promotion: number; hp: number; atk: number }
export interface Soldiers { [key: string]: number } // "병종:티어" → 수
export interface Opponent { kind: 'player' | 'bot'; id?: string; name: string; points: number; power: number; heroes: TeamHero[]; soldiers: Soldiers }

export const teamPower = (team: TeamHero[], defs: HeroDef[]) =>
  Math.round(team.reduce((a, h) => {
    const d = defs.find((x) => x.id === h.hero)
    return a + (d ? powerOf(d, h.hp, h.atk) : 0)
  }, 0))

// 보유 병사 → 총력전 병사(높은 티어부터, 같으면 병종 이름 순, 합 SOLDIER_CAP).
export function pickSoldiers(owned: Record<string, number>): Soldiers {
  const keys = Object.keys(owned).filter((k) => owned[k] > 0)
    .sort((a, b) => Number(b.split(':')[1]) - Number(a.split(':')[1]) || a.localeCompare(b))
  const out: Soldiers = {}
  let left = SOLDIER_CAP
  for (const k of keys) {
    const n = Math.min(left, Math.floor(owned[k]))
    if (n > 0) out[k] = n
    left -= n
    if (left <= 0) break
  }
  return out
}

// 봇 방어팀의 기준: 내 팀 영웅 한 명의 등급·역할·전투력.
export interface BaseHero { grade: string; role: string; power: number }

// 봇 방어팀: 기준 팀(내 방어팀, 없으면 전투력 높은 5명)의 영웅마다 같은 등급(되면 같은 역할)의 다른 영웅을 골라 그 전투력 × BOT_POWER에 맞춘다.
// 등급을 맞추는 까닭: 전투력 식에 등급 배율(SSR 2·SR 1.4)이 있어 같은 전투력이라도 낮은 등급은 능력치가 훨씬 크다 — 등급이 섞이면 봇이 늘 이긴다.
// 기준이 모자라면(영웅 5명 미만) 빈 자리는 MIN_POWER / TEAM 힘의 아무 영웅. 총력전이면 내 병사 수만큼 티어를 맞춘 병사.
export function botTeam(seed: number, mode: Mode, base: BaseHero[], points: number, heroes: HeroDef[], cfg: (k: string) => number,
  mySoldiers: Soldiers, soldierIds: string[]): Opponent {
  const r = mulberry32(seed)
  const pool = [...heroes].sort((a, b) => a.id.localeCompare(b.id))
  const picks: HeroDef[] = []
  const take = (list: HeroDef[]) => {
    const left = list.filter((h) => !picks.includes(h))
    if (!left.length) return false
    picks.push(left[Math.floor(r() * left.length)])
    return true
  }
  const scale = BOT_POWER[0] + r() * (BOT_POWER[1] - BOT_POWER[0])
  const targets: number[] = []
  for (let i = 0; i < TEAM && picks.length < pool.length; i++) {
    const b = base[i]
    if (b) {
      take(pool.filter((h) => h.grade === b.grade && h.role === b.role)) || take(pool.filter((h) => h.grade === b.grade)) || take(pool)
      targets.push(Math.max(MIN_POWER / TEAM, b.power) * scale)
    } else {
      take(pool)
      targets.push((MIN_POWER / TEAM) * scale)
    }
  }
  const team: TeamHero[] = picks.map((d, i) => {
    const f = fitHero(d, targets[i], cfg)
    const s = heroStats(d, f.level, f.promotion, cfg)
    return { hero: d.id, level: f.level, promotion: f.promotion, hp: Math.round(s.hp), atk: Math.round(s.atk * 10) / 10 }
  })
  const soldiers: Soldiers = {}
  if (mode === 'total' && soldierIds.length) {
    for (const [k, n] of Object.entries(mySoldiers)) {
      const tier = Number(k.split(':')[1])
      const type = soldierIds[Math.floor(r() * soldierIds.length)]
      const key = `${type}:${tier}`
      soldiers[key] = (soldiers[key] ?? 0) + n
    }
  }
  return { kind: 'bot', name: nickname(mix(seed, 11)), points: Math.max(0, Math.round(points + (r() - 0.5) * 60)), power: teamPower(team, heroes),
    heroes: team, soldiers }
}

// 앱이 보낸 영웅 5명(보유·서로 다름) → 서버 레벨·승급 + 자른 능력치. 못 쓰면 null.
export function teamOf(raw: unknown, owned: Record<string, { level: number; promotion: number }>, defs: HeroDef[], cfg: (k: string) => number,
  lim?: StatLimit): TeamHero[] | null {
  if (!Array.isArray(raw) || raw.length !== TEAM) return null
  const seen = new Set<string>()
  const out: TeamHero[] = []
  for (const h of raw) {
    const id = typeof h === 'string' ? h : String((h as { id?: unknown })?.id ?? '')
    const own = owned[id]
    const def = defs.find((d) => d.id === id)
    if (!own || !def || seen.has(id)) return null
    seen.add(id)
    const lv = Number(own.level ?? 1)
    const pr = Number(own.promotion ?? 0)
    const s = capStats(def, lv, pr, (h as { hp?: unknown })?.hp, (h as { atk?: unknown })?.atk, cfg, lim)
    out.push({ hero: id, level: lv, promotion: pr, hp: Math.round(s.hp), atk: Math.round(s.atk * 10) / 10 })
  }
  return out
}

// 결과가 그럴듯한가: 승리는 MIN_WIN_SEC 뒤에만, LATE_SEC가 지난 결과는 버린다(패배 그대로).
export function acceptWin(win: boolean, elapsed: number): boolean {
  return win && elapsed >= MIN_WIN_SEC / MAX_GAME_SPEED && elapsed <= LATE_SEC
}

export interface Shop { day: number; week: number; bought: Record<string, number> }
export function shopToday(saved: Partial<Shop> | null, day: number, week: number): Shop {
  const s = saved ?? {}
  const bought: Record<string, number> = {}
  for (const it of SHOP) {
    const keep = it.period === 'day' ? s.day === day : s.week === week
    if (keep && s.bought?.[it.id]) bought[it.id] = Number(s.bought[it.id])
  }
  return { day, week, bought }
}

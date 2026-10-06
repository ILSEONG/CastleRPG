// 길드전(공성전) 규칙(순수 함수). 앱 scripts/war_rules.gd·guild_war.gd와 같은 수치·식.
// 한 길드 = 한 주(월요일 리셋)에 상대 길드 하나. 상대는 가상 길드(enemy_seed로 매번 같은 값을 계산한다) — 길드원마다 수비 영웅 4명이 네 성문에 나뉘어 선다.
// 공성 전투: 하루 1번, 첫 길드원이 들어가면 시작해 BATTLE_SEC초. 그 사이 누구나 합류한다(실시간 방: war_live.ts). 가상 길드원 공격 분대는 AI.
// 성 상태(성문·성채 체력, 수비 영웅별 남은 체력 비율)는 전쟁 행(guild_wars.castle)에 저장되고 전투 결과로만 줄어든다(mergeCastle — 늘지 않는다).
// 점수: 수비 영웅 처치 1 · 성문 20 · 성채 100(서버가 성 상태 차이로 센다). 상대 점수 = 가상 상대가 하루 한 번 우리 성을 친 결과(enemyPoints).
import { mulberry32, powerOf } from './rules.ts'
import { guildName, mix, nickname } from './guild.ts'

export const BATTLE_SEC = 600
export const RESPAWN_SEC = 30
export const SQUAD = 4
export const PTS_KILL = 1
export const PTS_GATE = 20
export const PTS_KEEP = 100
export const REWARD_WIN = { coins: 300, diamonds: 100 }
export const REWARD_LOSE = { coins: 100, diamonds: 30 }
export const GATE_HP_SHARE = 3.0
export const KEEP_HP_SHARE = 6.0
export const MIN_GATE_HP = 3000
export const MIN_KEEP_HP = 8000
export const ENEMY_DAY_BASE = 45 // 같은 힘의 상대가 하루에 얻는 점수(± ENEMY_DAY_SPREAD)
export const ENEMY_DAY_SPREAD = 0.25
export const ENEMY_POWER_RANGE: [number, number] = [0.85, 1.15] // 상대 길드원 힘 = 우리 길드원 평균 × 이 범위
export const VIRTUAL_POWER_RANGE: [number, number] = [0.8, 1.05] // 우리 가상 길드원 공격 분대 힘 = 그 길드원 전투력 기준
export const STAT_CAP = 4 // 앱이 보낸 영웅 능력치 상한 = 기본(레벨·승급) × 이것(성장·연구·장비·길드 버프 몫)
export const MAX_PROMOTION = 5
export const MIN_POWER = 250

export const weekOf = (day: number) => Math.floor((day + 3) / 7) // 리셋 날(유닉스 일 기준) → 주. 월요일에 바뀐다
export const weekStart = (week: number) => week * 7 - 3
export const dayInWeek = (day: number) => day - weekStart(weekOf(day)) // 0 = 월요일

export interface HeroDef { id: string; role: string; hp: number; atk: number; atk_interval: number; grade: string }
type Cfg = (k: string) => number

// 앱 GameData.hero_stats(장비 없이): 기본 × 레벨 배율(근접은 따로) × 승급 배율^승급.
export function heroStats(def: HeroDef, level: number, promotion: number, cfg: Cfg) {
  const lv = 1 + cfg(def.role === 'melee' ? 'hero_level_stat_melee' : 'hero_level_stat') * (level - 1)
  const m = lv * cfg('promote_mult') ** Math.max(0, Math.min(promotion, MAX_PROMOTION))
  return { hp: def.hp * m, atk: def.atk * m }
}

export const heroPower = (def: HeroDef, level: number, promotion: number, cfg: Cfg) => {
  const s = heroStats(def, level, promotion, cfg)
  return powerOf(def, s.hp, s.atk) // 앱 GameData.hero_power(장비 없이)와 같은 식

}

export const maxLevel = (promotion: number, cfg: Cfg) => cfg('hero_max_level_base') + cfg('hero_max_level_per_promotion') * promotion

// 목표 전투력에 가장 가까운 (레벨, 승급). 같으면 낮은 승급.
export function fitHero(def: HeroDef, target: number, cfg: Cfg) {
  let best = { level: 1, promotion: 0 }
  let bestD = Infinity
  for (let p = 0; p <= 3; p++) {
    for (let l = 1; l <= maxLevel(p, cfg); l++) {
      const d = Math.abs(heroPower(def, l, p, cfg) - target)
      if (d < bestD - 1e-9) {
        bestD = d
        best = { level: l, promotion: p }
      }
    }
  }
  return best
}

export interface SquadHero { hero: string; level: number; promotion: number; hp: number; atk: number }

// 무작위 영웅 4명(근접 ≥ 1, 원거리 ≥ 1), 길드원 전투력(배치 영웅 합 기준)에 맞춘 레벨.
export function randomSquad(r: () => number, heroes: HeroDef[], power: number, cfg: Cfg): SquadHero[] {
  const pool = [...heroes].sort((a, b) => a.id.localeCompare(b.id))
  const melee = pool.filter((h) => h.role === 'melee')
  const ranged = pool.filter((h) => h.role !== 'melee')
  const picks: HeroDef[] = []
  const take = (list: HeroDef[]) => {
    const left = list.filter((h) => !picks.includes(h))
    if (left.length) picks.push(left[Math.floor(r() * left.length)])
  }
  take(melee)
  take(ranged)
  while (picks.length < SQUAD && picks.length < pool.length) take(pool)
  const per = Math.max(MIN_POWER, power) / SQUAD
  return picks.map((d) => {
    const f = fitHero(d, per, cfg)
    const s = heroStats(d, f.level, f.promotion, cfg)
    return { hero: d.id, level: f.level, promotion: f.promotion, hp: Math.round(s.hp), atk: Math.round(s.atk * 10) / 10 }
  })
}

export interface Defender extends SquadHero { uid: number; owner: string; name: string; squad: number; lane: number }
export interface Enemy { seed: number; name: string; emblem: number; power: number; members: { name: string; power: number }[]; defenders: Defender[] }

// 상대 길드: seed와 우리 길드(인원 n, 길드원 평균 전투력 avg)로 정해진다.
export function enemyGuild(seed: number, n: number, avg: number, heroes: HeroDef[], cfg: Cfg): Enemy {
  const r = mulberry32(mix(seed, 31))
  const members: Enemy['members'] = []
  const defenders: Defender[] = []
  for (let m = 0; m < n; m++) {
    const power = Math.round(Math.max(MIN_POWER, avg) * (ENEMY_POWER_RANGE[0] + r() * (ENEMY_POWER_RANGE[1] - ENEMY_POWER_RANGE[0])))
    const name = nickname(mix(seed, 500 + m))
    members.push({ name, power })
    const sq = randomSquad(r, heroes, power, cfg)
    sq.forEach((h, i) => defenders.push({ ...h, uid: 1 + m * SQUAD + i, owner: `d:${m}`, name, squad: m, lane: m % 4 }))
  }
  return { seed, name: guildName(mix(seed, 3)), emblem: mix(seed, 4) % 8, power: Math.round(members.reduce((a, b) => a + b.power, 0)), members, defenders }
}

export interface Castle { gates: number[]; keep: number; dead: Record<string, number> } // dead: uid → 남은 체력 비율(< 1인 것만, 0 = 쓰러짐)

export function castleMax(defs: Defender[]) {
  const lane = [0, 0, 0, 0]
  let all = 0
  for (const d of defs) {
    lane[d.lane] += d.hp
    all += d.hp
  }
  return { gates: lane.map((h) => Math.max(MIN_GATE_HP, Math.round(h * GATE_HP_SHARE))), keep: Math.max(MIN_KEEP_HP, Math.round(all * KEEP_HP_SHARE)) }
}

export function freshCastle(defs: Defender[]): Castle {
  const mx = castleMax(defs)
  return { gates: [...mx.gates], keep: mx.keep, dead: {} }
}

export const ratioOf = (c: Castle, uid: number) => (Object.hasOwn(c.dead, String(uid)) ? c.dead[String(uid)] : 1)
export const killsIn = (c: Castle) => Object.values(c.dead).filter((v) => v <= 0).length
export const gatesDown = (c: Castle) => c.gates.filter((g) => g <= 0).length

// 성 점수(전쟁 전체 누적 = 지금 성 상태로 센다).
export const castlePoints = (c: Castle) => killsIn(c) * PTS_KILL + gatesDown(c) * PTS_GATE + (c.keep <= 0 ? PTS_KEEP : 0)

// 전투 결과(방장 기기가 보낸 성 상태)를 합친다: 줄어든 값만 받는다(체력이 늘거나 부활하지 않는다). 모르는 uid·범위 밖 값은 버린다.
export function mergeCastle(c: Castle, r: { gates?: unknown; keep?: unknown; defenders?: unknown }, defs: Defender[]): Castle {
  const out: Castle = { gates: [...c.gates], keep: c.keep, dead: { ...c.dead } }
  if (Array.isArray(r.gates)) {
    for (let i = 0; i < 4; i++) {
      const v = Number(r.gates[i])
      if (Number.isFinite(v) && v >= 0) out.gates[i] = Math.min(out.gates[i], Math.round(v))
    }
  }
  const k = Number(r.keep)
  if (Number.isFinite(k) && k >= 0) out.keep = Math.min(out.keep, Math.round(k))
  if (r.defenders && typeof r.defenders === 'object') {
    const known = new Set(defs.map((d) => String(d.uid)))
    for (const [uid, v] of Object.entries(r.defenders as Record<string, unknown>)) {
      const x = Number(v)
      if (!known.has(uid) || !Number.isFinite(x) || x < 0 || x > 1) continue
      const cur = Object.hasOwn(out.dead, uid) ? out.dead[uid] : 1
      const nv = Math.round(Math.min(cur, x) * 1000) / 1000
      if (nv < 1) out.dead[uid] = nv
    }
  }
  return out
}

// 상대(가상)가 우리 성을 친 점수 합: 이번 주 지난 날 + 오늘(날마다 리셋 때 한 번). ratio = 상대 힘 ÷ 우리 수비 힘.
export function enemyPoints(seed: number, week: number, daysDone: number, ratio: number, cap: number): number[] {
  const out: number[] = []
  let total = 0
  for (let d = 0; d < daysDone; d++) {
    const r = mulberry32(mix(seed, week >>> 0, 900 + d))
    const v = Math.round(ENEMY_DAY_BASE * Math.max(0.2, Math.min(2.5, ratio)) * (1 - ENEMY_DAY_SPREAD + 2 * ENEMY_DAY_SPREAD * r()))
    const add = Math.max(0, Math.min(v, cap - total))
    total += add
    out.push(add)
  }
  return out
}

// 우리 성 만점(상대 점수 상한): 우리 길드원 수 × 4 처치 + 성문 4 + 성채.
export const castleCap = (members: number) => members * SQUAD * PTS_KILL + 4 * PTS_GATE + PTS_KEEP

export const enemySeed = (guildSeed: number, week: number) => mix(guildSeed, week >>> 0, 77)

// 보내온 영웅 능력치를 믿을 만한 범위로 자른다(기본 × STAT_CAP 이하, 0보다 크게).
export function capStats(def: HeroDef, level: number, promotion: number, hp: unknown, atk: unknown, cfg: Cfg) {
  const base = heroStats(def, level, promotion, cfg)
  const h = Number(hp)
  const a = Number(atk)
  return {
    hp: Number.isFinite(h) && h > 0 ? Math.min(h, base.hp * STAT_CAP) : base.hp,
    atk: Number.isFinite(a) && a > 0 ? Math.min(a, base.atk * STAT_CAP) : base.atk,
  }
}

// 길드 규칙(순수 함수, 시간 인자). 앱 scripts/guild.gd와 같은 수치·규칙.
// 길드 경험치·보스 누적 피해 = 실제 길드원이 쌓은 값(guilds.exp·boss_damage) + 가상 길드원 몫(virtualTotals — 길드 seed·생성 시각·지금으로
// 매번 같은 값을 계산한다. 저장하지 않으므로 여러 요청이 겨뤄도 두 번 세지 않는다). 레벨·보스 단계는 누적값에서 나온다.
import { mulberry32, powerOf, resetAt, resetDay } from './rules.ts'

// 길드 레벨은 끝이 없다(2026-10-06 사용자: "길드 레벨은 무제한"). 레벨마다 영웅 공격력·체력 +BUFF_PER_LEVEL %.
// 길드 인원(실제 + 가상): 1~5레벨 15명, FULL_LEVEL(6)부터 20명(최대 20명 유지). 실제 유저가 우선이고 가상 길드원은 남는 자리만 채운다(seated).
export const FULL_LEVEL = 6
export const MEMBERS_BASE = 15
export const MEMBERS_MAX = 20
export const capacity = (level: number) => (level >= FULL_LEVEL ? MEMBERS_MAX : MEMBERS_BASE)
export const BUFF_PER_LEVEL = 1 // 길드 레벨당 영웅 공격력·체력 %
export const UNLOCK_STAGE = 11 // 서버 stage(전체 라운드)가 이 이상 = 1-10 클리어
export const CREATE_GOLD = 500_000
export const ATTEND_REWARD = { gold: 3000, coins: 30 }
export const ATTEND_EXP = 10
export const ATTEND_BOXES: [number, Record<string, number>][] = [[5, { coins: 20, gold: 5000 }], [10, { coins: 40, diamonds: 20 }],
  [15, { coins: 60, diamonds: 30 }], [20, { coins: 100, diamonds: 50 }]]
export const DONATIONS: Record<string, { name: string; gold: number; diamonds: number; exp: number; coins: number; daily: number }> = {
  gold: { name: '골드 기부', gold: 10000, diamonds: 0, exp: 20, coins: 20, daily: 3 },
  dia: { name: '다이아 기부', gold: 0, diamonds: 50, exp: 60, coins: 60, daily: 1 },
  royal: { name: '왕실 기부', gold: 0, diamonds: 200, exp: 250, coins: 250, daily: 1 },
}
export const BOSS_TRIES = 2
export const BOSS_FIGHT_SEC = 20
// 드래곤(2026-10-06 개편): 길드원마다 하루 BOSS_TRIES번 따로 친다. 매 판 Lv 1에서 시작해 쓰러뜨릴 때마다 같은 판 안에서 다음 레벨로 오른다.
// 한 판 점수 = 그 판에서 드래곤에 준 피해. 내 점수 = 오늘 두 판의 합, 길드 점수 = 길드원 점수의 합(오늘). Lv n 최대 HP = BASE × GROWTH^(n−1).
export const BOSS_HP_BASE = 1000
export const BOSS_HP_GROWTH = 1.22
export const BOSS_NAMES = ['드래곤']
// 실제 전투(앱이 BOSS_FIGHT_SEC초 동안 영웅으로 드래곤을 친다): 시작에 도전 1회를 쓰고, 끝에 앱이 낸 피해를 받는다.
// 받는 피해 상한 = 시작 때 내 팀 초당 피해 × 초 × BOSS_DMG_CAP(조작 방지 — 실제 전투가 이보다 많이 내면 잘린다).
// 시작 뒤 BOSS_FIGHT_SEC ÷ 1.5(x1.5 배속, rules.MAX_GAME_SPEED) − BOSS_SLACK_SEC 실제 초 전에 끝내면 거절(too_early), BOSS_RUN_TTL초가 지나면 피해 0으로 끝난다.
export const BOSS_DMG_CAP = 3
export const BOSS_SLACK_SEC = 2
export const BOSS_RUN_TTL = 600
// 판 등급: [등급, 도달한 드래곤 레벨 이상, 코인, 골드]
export const BOSS_GRADES: [string, number, number, number][] = [['S', 15, 120, 30000], ['A', 10, 90, 20000], ['B', 6, 60, 12000],
  ['C', 3, 40, 8000], ['D', 1, 25, 5000]]
export const SHOP: { id: string; give: Record<string, number>; price: number; limit: number; period: 'day' | 'week' }[] = [
  { id: 'dia', give: { diamonds: 50 }, price: 150, limit: 2, period: 'day' },
  { id: 'gold', give: { gold: 30000 }, price: 60, limit: 3, period: 'day' },
  { id: 'equip', give: { equip: 1 }, price: 50, limit: 3, period: 'day' }, // 장비 상자: 장비 던전 최고 단계 드롭 1개(2026-10-06, 식량 대신)
  { id: 'shards', give: { shards: 3 }, price: 200, limit: 5, period: 'week' },
  { id: 'ssr', give: { ssr_shards: 1 }, price: 600, limit: 2, period: 'week' },
]
export const EMBLEMS = 8
export const RECOMMEND_N = 5
export const SYSTEM_VIRTUAL = [12, 18] // 시스템 길드 가상 길드원 수 범위
export const CREATED_VIRTUAL = 10 // 직접 만든 길드: 가상 길드원이 몇 시간마다 한 명씩 이만큼까지 들어온다
export const SIM_DAYS_MAX = 400 // 가상 활동을 세는 최대 날수(아주 오래된 길드도 계산량이 묶이게)

const NAME_A = ['새벽', '은빛', '붉은', '강철', '푸른', '황금', '서리', '폭풍', '달빛', '불꽃', '검은', '하얀', '용맹한', '고요한', '별빛', '천둥']
const NAME_B = ['방패단', '기사단', '수호대', '검술회', '원정대', '늑대단', '망루', '용병단', '결사대', '깃발단', '성채', '사냥단']
const NICK_A = ['졸린', '용감한', '배고픈', '빠른', '느긋한', '씩씩한', '조용한', '화난', '행복한', '수상한', '귀여운', '우직한', '새침한', '엉뚱한']
const NICK_B = ['감자', '고양이', '기사', '궁수', '곰', '여우', '도토리', '망치', '방패', '늑대', '토끼', '수염', '마법사', '호박']
export const NOTICES = ['매일 출석과 기부 부탁드려요!', '보스는 하루 두 번 꼭 쳐 주세요', '즐겁게 함께 성장해요', '초보 환영, 질문은 언제든지',
  '주말엔 왕실 기부 이벤트!', '출석 20명 달성 목표!']
export const CREATED_NOTICE = '함께 성장할 길드원을 모집합니다!'

// 정수 seed들 → 32비트 seed(순서가 다르면 다른 값).
export function mix(...xs: number[]): number {
  let h = 0x811c9dc5
  for (const x of xs) {
    h = Math.imul(h ^ (x >>> 0), 0x01000193) >>> 0
    h = Math.imul(h ^ (h >>> 15), 0x2c1b3c6d) >>> 0
  }
  return h >>> 0
}

const pick = <T>(r: () => number, a: T[]) => a[Math.floor(r() * a.length)]
const range = (r: () => number, a: number, b: number) => a + r() * (b - a)

export function guildName(seed: number): string {
  const r = mulberry32(seed)
  return `${pick(r, NAME_A)} ${pick(r, NAME_B)}`
}

export function nickname(seed: number): string {
  const r = mulberry32(seed)
  let s = pick(r, NICK_A) + pick(r, NICK_B)
  if (r() < 0.4) s += String(1 + Math.floor(r() * 99))
  return s
}

// 플레이어 id(uuid) → 길드원 이름(같은 id면 늘 같다).
export function playerName(id: string): string {
  const hex = id.replace(/-/g, '')
  return nickname(mix(parseInt(hex.slice(0, 8), 16), parseInt(hex.slice(8, 16), 16)))
}

// --- 레벨·보스 ---

export const expNeed = (level: number) => Math.round(150 * level ** 1.3)

// 누적 경험치 → {level, exp(그 레벨 안), need}
export function levelOf(total: number) {
  let level = 1
  let left = Math.max(0, total)
  while (left >= expNeed(level)) {
    left -= expNeed(level)
    level++
  }
  return { level, exp: left, need: expNeed(level) }
}

// 자리에 앉은 가상 길드원: 지금까지 들어온 순서대로 (인원 − 실제 길드원 수)명까지.
export function seated<T extends { join_t: number }>(members: T[], now: number, cap: number, real: number): T[] {
  return members.filter((m) => m.join_t <= now).sort((a, b) => a.join_t - b.join_t).slice(0, Math.max(0, cap - real))
}

export const buffPct = (level: number) => BUFF_PER_LEVEL * Math.max(level, 0)
export const bossMax = (level: number) => Math.round(BOSS_HP_BASE * BOSS_HP_GROWTH ** (Math.max(level, 1) - 1))
export const bossName = (level: number) => BOSS_NAMES[(Math.max(level, 1) - 1) % BOSS_NAMES.length]

// 한 판 피해 → {level(도달한 레벨), hp(그 레벨 남은 HP)} — Lv 1부터 쓰러뜨린 만큼 오른다.
export function bossOf(damage: number) {
  let level = 1
  let left = Math.max(0, damage)
  while (left >= bossMax(level) && level < 10_000) {
    left -= bossMax(level)
    level++
  }
  return { level, hp: bossMax(level) - left, max: bossMax(level) }
}

export function bossGrade(dmg: number) {
  const lv = bossOf(dmg).level
  return BOSS_GRADES.find((g) => lv >= g[1]) ?? BOSS_GRADES[BOSS_GRADES.length - 1]
}

// --- 가상 길드원 ---

export interface GuildRow {
  id: string
  seed: number
  created_at: number
  virtual_n: number
  system: boolean // 시스템 길드(owner 없음)면 가상 길드원이 처음부터 다 있다
}

export interface VMember {
  i: number
  name: string
  role: string
  power0: number
  att_p: number
  join_t: number
}

// 가상 길드원 전투력 배율(2026-10-06 전투력 식 개편 — 등급·원거리 배율로 실제 플레이어 전투력이 약 2배가 되어 표시를 맞춘다).
// 보스 피해는 예전 값 그대로(virtualDay에서 나눈다).
export const VIRTUAL_POWER_SCALE = 2

export function virtualMembers(g: GuildRow): VMember[] {
  const r = mulberry32(mix(g.seed, 7))
  const out: VMember[] = []
  let t = g.created_at
  for (let i = 0; i < g.virtual_n; i++) {
    if (!g.system) t += i === 0 ? 600 : range(r, 0.5, 3) * 3600
    const role = g.system ? (i === 0 ? '길드장' : i === 1 ? '부길드장' : i < 6 ? '정예' : '길드원') : (i < 3 ? '정예' : '길드원')
    out.push({ i, name: nickname(mix(g.seed, 1000 + i)), role, power0: (250 + Math.floor(r() * 1100)) * VIRTUAL_POWER_SCALE, att_p: range(r, 0.55, 0.97), join_t: g.system ? g.created_at : t })
  }
  return out
}

// 가상 길드원 i의 d일 활동(안 하면 null). t = 활동 시각, exp, dmg = 보스 피해 합, kind = 기부 종류("" = 출석만).
export function virtualDay(g: GuildRow, m: VMember, d: number, hour: number) {
  const r = mulberry32(mix(g.seed, m.i, d >>> 0))
  if (r() >= m.att_p) return null
  const t = resetAt(d, hour) + range(r, 0.3, 23.5) * 3600
  if (t < m.join_t) return null
  const roll = r()
  const kind = roll < 0.04 ? 'royal' : roll < 0.2 ? 'dia' : roll < 0.85 ? 'gold' : ''
  const hits = 1 + Math.floor(r() * BOSS_TRIES)
  const days = Math.max(0, (t - g.created_at) / 86400)
  const power = m.power0 * (1 + 0.04 * days)
  let dmg = 0
  for (let h = 0; h < hits; h++) dmg += Math.round((power / VIRTUAL_POWER_SCALE) * range(r, 2.8, 4.2))
  return { t, kind, exp: ATTEND_EXP + (kind ? DONATIONS[kind].exp : 0), dmg, hits, power: Math.round(power) }
}

// 가상 길드원 몫의 누적(지금까지) + 오늘 길드원별 상태.
export function virtualTotals(g: GuildRow, now: number, hour: number) {
  const members = virtualMembers(g)
  const today = resetDay(now, hour)
  const first = Math.max(resetDay(g.created_at, hour), today - SIM_DAYS_MAX)
  let exp = 0
  let dmg = 0
  const day: Record<number, { att: boolean; contrib: number; dmg: number; last: number; power: number; kind: string }> = {}
  const log: { t: number; text: string }[] = []
  for (const m of members) day[m.i] = { att: false, contrib: 0, dmg: 0, last: 0, power: m.power0, kind: '' }
  for (let d = first; d <= today; d++) {
    for (const m of members) {
      const e = virtualDay(g, m, d, hour)
      if (!e || e.t > now) continue
      exp += e.exp
      dmg += e.dmg
      const s = day[m.i]
      s.last = e.t
      s.power = e.power
      if (d === today) {
        s.att = true
        s.contrib = e.exp + 10 * e.hits
        s.dmg = e.dmg
        s.kind = e.kind
        log.push({ t: e.t, text: e.kind ? `${m.name}님이 ${DONATIONS[e.kind].name}를 했습니다` : `${m.name}님이 출석했습니다` })
      }
    }
  }
  return { exp, dmg, members, day, log }
}

// 시스템 길드 하나(추천 목록을 채운다): 생성 시각을 며칠 앞당겨 레벨이 붙어 있게.
export function systemGuild(seed: number, now: number) {
  const r = mulberry32(mix(seed, 3))
  return {
    seed,
    name: guildName(seed),
    emblem: Math.floor(r() * EMBLEMS),
    notice: pick(r, NOTICES),
    created_at: now - range(r, 3, 45) * 86400,
    virtual_n: SYSTEM_VIRTUAL[0] + Math.floor(r() * (SYSTEM_VIRTUAL[1] - SYSTEM_VIRTUAL[0] + 1)),
  }
}

// --- 내 일일 상태 ---

export interface Mine {
  day: number
  attended: boolean
  donations: Record<string, number>
  boxes: number[]
  boss_tries: number
  boss_best: number
  boss_total: number
  contrib: number
  shop_day: { day: number; bought: Record<string, number> }
  shop_week: { week: number; bought: Record<string, number> }
  boss_run: { id: string; t: number; cap: number; level: number } | null // 진행 중인 보스 전투(시작에 도전 1회를 썼다)
}

// 저장된 값 → 오늘 값(날이 바뀌었으면 일일 값을 비운다).
export function mineToday(saved: Partial<Mine> | null, now: number, hour: number): Mine {
  const d = resetDay(now, hour)
  const w = Math.floor(d / 7)
  const s = saved ?? {}
  const same = s.day === d
  const sd = s.shop_day?.day === d ? s.shop_day : { day: d, bought: {} }
  const sw = s.shop_week?.week === w ? s.shop_week : { week: w, bought: {} }
  return {
    day: d,
    attended: same ? !!s.attended : false,
    donations: same ? { ...(s.donations ?? {}) } : {},
    boxes: same ? [...(s.boxes ?? [])] : [],
    boss_tries: same ? Number(s.boss_tries ?? 0) : 0,
    boss_best: same ? Number(s.boss_best ?? 0) : 0,
    boss_total: same ? Number(s.boss_total ?? 0) : 0,
    contrib: same ? Number(s.contrib ?? 0) : 0,
    shop_day: { day: sd.day, bought: { ...sd.bought } },
    shop_week: { week: sw.week, bought: { ...sw.bought } },
    boss_run: same && s.boss_run ? { ...s.boss_run } : null,
  }
}

// --- 내 팀 피해 ---

export interface HeroDef {
  id: string
  role: string
  atk: number
  hp: number
  atk_interval: number
  grade: string
}

// 영웅 최종 공격 = 기본 × 레벨 배율 × 승급 배율 × (1 + 성장 공격 %) × (1 + 길드 버프 %). 초당 피해 = 공격 × (1 + 성장 공속) / 간격.
export function teamDps(deploy: string[], heroes: Record<string, { level: number; promotion: number }>, defs: HeroDef[],
  cfg: (k: string) => number, atkPct: number, aspdPct: number, buff: number): number {
  let out = 0
  for (const id of deploy) {
    const def = defs.find((h) => h.id === id)
    const h = heroes[id]
    if (!def || !h) continue
    const lv = 1 + cfg(def.role === 'melee' ? 'hero_level_stat_melee' : 'hero_level_stat') * (h.level - 1)
    let pm = 1
    for (let i = 0; i < Math.min(h.promotion, 5); i++) pm *= cfg('promote_mult')
    const atk = def.atk * lv * pm * (1 + atkPct) * (1 + buff / 100)
    out += (atk * (1 + aspdPct)) / Math.max(0.1, def.atk_interval)
  }
  return out
}

// 배치 영웅 전투력 합(앱 GameData.hero_power와 같은 식). equip = 영웅 id → 장비 합계 {hp, atk}(없으면 0) — 영웅 목록처럼 장비 포함.
export function teamPower(deploy: string[], heroes: Record<string, { level: number; promotion: number }>, defs: HeroDef[], cfg: (k: string) => number,
  equip: Record<string, { hp: number; atk: number }> = {}): number {
  let out = 0
  for (const id of deploy) {
    const def = defs.find((h) => h.id === id)
    const h = heroes[id]
    if (!def || !h) continue
    const lv = 1 + cfg(def.role === 'melee' ? 'hero_level_stat_melee' : 'hero_level_stat') * (h.level - 1)
    let pm = 1
    for (let i = 0; i < Math.min(h.promotion, 5); i++) pm *= cfg('promote_mult')
    const eq = equip[id] ?? { hp: 0, atk: 0 }
    out += powerOf(def, def.hp * lv * pm + eq.hp, def.atk * lv * pm + eq.atk)
  }
  return out
}

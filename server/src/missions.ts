// 미션(2026-10-06): 일일·주간·반복. 오른쪽 아래 메뉴 [미션] 창(앱 scripts/missions.gd·mission_panel.gd)이 GET /v1/missions로 표와 진행을 받는다.
// 일일 = 리셋 날짜(daily_reset_utc_hour, 00:00 KST)마다, 주간 = 월요일 리셋마다 받은 기록이 지워진다. 반복 = 받을 때마다 목표가 step만큼 커지고 끝없이 받는다.
// 사건 수(처치·수집·모집…)는 앱이 센다(튜토리얼·반복 퀘스트와 같다 — 서버는 받은 기록·기간·순서만 본다). 서버가 직접 보는 것:
// daily_count(오늘 받은 다른 일일 미션 수)·daily_bonus(이번 주에 일일 보너스를 받은 날 수).
// 보상 키: 자원(wood·stone·food)·gold·diamonds·tickets(다이아 모집권)·keys_<던전 종류>(열쇠)·pouch_<id>(방치 주머니, pouches.ts). 보상은 반복 미션도 늘지 않는다.

export type MissionType = 'daily' | 'weekly' | 'repeat'

export interface MissionDef {
  id: string
  type: MissionType
  kind: string // 앱이 세는 사건(kill·collect·…) 또는 서버가 보는 daily_count·daily_bonus
  title: string // %d = 목표
  target: number // 반복 미션은 첫 목표
  step?: number // 반복 미션: 받을 때마다 목표 +step
  reward: Record<string, number>
}

const RES = (n: number) => ({ wood: n, stone: n, food: n })

export const DEFS: MissionDef[] = [
  // 일일(8 + 보너스)
  { id: 'd_kill', type: 'daily', kind: 'kill', title: '몬스터 %d마리 처치', target: 300, reward: { gold: 3000, pouch_gold_10: 1 } },
  { id: 'd_collect', type: 'daily', kind: 'collect', title: '자원 %d번 수집', target: 5, reward: { ...RES(3000), pouch_res_10: 1 } },
  { id: 'd_sell', type: 'daily', kind: 'sell', title: '상인과 %d번 거래', target: 2, reward: { gold: 2000 } },
  { id: 'd_hero', type: 'daily', kind: 'hero_level', title: '영웅 레벨업 %d회', target: 5, reward: { gold: 3000 } },
  { id: 'd_growth', type: 'daily', kind: 'growth', title: '성장 강화 %d회', target: 3, reward: { gold: 3000 } },
  { id: 'd_gacha', type: 'daily', kind: 'gacha', title: '영웅 %d회 모집', target: 10, reward: { diamonds: 30 } },
  { id: 'd_dungeon', type: 'daily', kind: 'dungeon_win', title: '던전 %d번 클리어', target: 2, reward: { diamonds: 30 } },
  { id: 'd_guild', type: 'daily', kind: 'guild_attend', title: '길드 출석', target: 1, reward: { diamonds: 20 } },
  { id: 'd_all', type: 'daily', kind: 'daily_count', title: '일일 미션 %d개 완료', target: 6, reward: { diamonds: 100, tickets: 1, pouch_gold_60: 1 } },
  // 주간
  { id: 'w_bonus', type: 'weekly', kind: 'daily_bonus', title: '일일 미션 보너스 %d일 받기', target: 5, reward: { tickets: 5, pouch_gold_360: 1, pouch_res_360: 1 } },
  { id: 'w_kill', type: 'weekly', kind: 'kill', title: '몬스터 %d마리 처치', target: 3000, reward: { gold: 30000, pouch_gold_240: 1 } },
  { id: 'w_dungeon', type: 'weekly', kind: 'dungeon_win', title: '던전 %d번 클리어', target: 10, reward: { diamonds: 150 } },
  { id: 'w_gacha', type: 'weekly', kind: 'gacha', title: '영웅 %d회 모집', target: 50, reward: { diamonds: 150 } },
  { id: 'w_hero', type: 'weekly', kind: 'hero_level', title: '영웅 레벨업 %d회', target: 30, reward: { gold: 30000 } },
  { id: 'w_build', type: 'weekly', kind: 'build_up', title: '건물 레벨업 %d번 완료', target: 3, reward: { ...RES(20000), pouch_res_240: 1 } },
  { id: 'w_research', type: 'weekly', kind: 'research', title: '연구 %d번 시작', target: 2, reward: { gold: 20000 } },
  { id: 'w_train', type: 'weekly', kind: 'train', title: '병사 훈련 %d번', target: 3, reward: { gold: 10000 } },
  { id: 'w_boss', type: 'weekly', kind: 'guild_boss', title: '길드 보스 %d번 도전', target: 3, reward: { diamonds: 100 } },
  // 반복(목표 = target + step × 받은 횟수)
  { id: 'r_kill', type: 'repeat', kind: 'kill', title: '몬스터 %d마리 처치', target: 1000, step: 500, reward: { gold: 5000, pouch_gold_30: 1 } },
  { id: 'r_stage', type: 'repeat', kind: 'stage', title: '라운드 %d번 클리어', target: 10, step: 5, reward: { diamonds: 20 } },
  { id: 'r_collect', type: 'repeat', kind: 'collect', title: '자원 %d번 수집', target: 20, step: 10, reward: { ...RES(5000), pouch_res_30: 1 } },
  { id: 'r_sell', type: 'repeat', kind: 'sell', title: '상인과 %d번 거래', target: 10, step: 5, reward: { gold: 5000 } },
  { id: 'r_hero', type: 'repeat', kind: 'hero_level', title: '영웅 레벨업 %d회', target: 20, step: 10, reward: { gold: 5000 } },
  { id: 'r_growth', type: 'repeat', kind: 'growth', title: '성장 강화 %d회', target: 20, step: 10, reward: { gold: 5000 } },
  { id: 'r_gacha', type: 'repeat', kind: 'gacha', title: '영웅 %d회 모집', target: 30, step: 10, reward: { tickets: 1 } },
  { id: 'r_dungeon', type: 'repeat', kind: 'dungeon_win', title: '던전 %d번 클리어', target: 5, step: 3, reward: { diamonds: 30 } },
]

// 플레이어 미션 상태(player_state.missions jsonb): 리셋 날짜·주 번호, 오늘·이번 주에 받은 id, 이번 주 일일 보너스 받은 날 수,
// 반복 미션 받은 횟수, 마지막 반복 미션 받은 시각(유닉스 초).
export interface MissionState {
  day: number
  week: number
  d: string[]
  w: string[]
  wd: number
  r: Record<string, number>
  rt: number | null
  c: Counters
}

// 서버가 센 사건 수(통합 테스트 2026-10-07: 보상 받기가 앱의 진행 주장을 믿지 않게). 미션 상태 jsonb의 c에 둔다(마이그레이션 없음).
// d·w: 오늘·이번 주 사건 수(cd·cw가 그 날·주), t: 이 기능이 생긴 뒤 누적, rb: 반복 미션 id → 지금까지 받으며 쓴 누적 사건 수,
// qs: 마지막 반복 퀘스트(가이드 카드)를 받을 때의 t와 stage(null = 아직 안 받음 — 이 기능이 생긴 뒤 누적을 진행으로 본다).
export interface Counters {
  cd: number
  d: Record<string, number>
  cw: number
  w: Record<string, number>
  t: Record<string, number>
  rb: Record<string, number>
  qs: Record<string, number> | null
}

// 서버가 세는 사건(앱 missions.gd·tutorial.gd가 세는 것과 같은 이름)
export const EVENTS = ['kill', 'collect', 'sell', 'stage', 'hero_level', 'growth', 'gacha', 'dungeon_win', 'guild_attend', 'guild_boss', 'build_up',
  'research', 'train'] as const

// 주 번호: 월요일에 시작한다(리셋 날짜 0 = 1970-01-02 금요일 KST).
export const weekOf = (day: number) => Math.floor((day + 4) / 7)
// 그 주가 시작하는 리셋 날짜
export const weekStart = (week: number) => week * 7 - 4

export const def = (id: string) => DEFS.find((d) => d.id === id)

// 반복 미션 목표(받은 횟수 n번째)
export const targetOf = (d: MissionDef, n: number) => d.target + (d.step ?? 0) * n

const nums = (v: unknown): Record<string, number> => {
  const out: Record<string, number> = {}
  if (v && typeof v === 'object' && !Array.isArray(v)) {
    for (const [k, x] of Object.entries(v as Record<string, unknown>)) if (Number.isInteger(x) && (x as number) > 0) out[k] = x as number
  }
  return out
}

const strs = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : [])

// 저장된 값 → 오늘 기준 상태(날이 바뀌었으면 일일 기록을, 주가 바뀌었으면 주간 기록을 비운다).
export function normalize(raw: unknown, day: number): MissionState {
  const m = (raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {}) as Record<string, unknown>
  const week = weekOf(day)
  const r: Record<string, number> = {}
  if (m.r && typeof m.r === 'object' && !Array.isArray(m.r)) {
    for (const [k, v] of Object.entries(m.r as Record<string, unknown>)) if (Number.isInteger(v) && (v as number) > 0) r[k] = v as number
  }
  const sameWeek = Number(m.week) === week
  return {
    day,
    week,
    d: Number(m.day) === day ? strs(m.d) : [],
    w: sameWeek ? strs(m.w) : [],
    wd: sameWeek && Number.isInteger(m.wd) ? (m.wd as number) : 0,
    r,
    rt: typeof m.rt === 'number' ? m.rt : null,
    c: counters(m.c, day),
  }
}

// 저장된 사건 수 → 오늘 기준(날·주가 바뀌었으면 그 수를 비운다)
function counters(raw: unknown, day: number): Counters {
  const c = (raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {}) as Record<string, unknown>
  const week = weekOf(day)
  return {
    cd: day,
    d: Number(c.cd) === day ? nums(c.d) : {},
    cw: week,
    w: Number(c.cw) === week ? nums(c.w) : {},
    t: nums(c.t),
    rb: nums(c.rb),
    qs: c.qs && typeof c.qs === 'object' && !Array.isArray(c.qs) ? nums(c.qs) : null,
  }
}

// 사건을 더한 미션 상태(받은 기록은 그대로)
export function addEvents(raw: unknown, events: Record<string, number>, day: number): MissionState {
  const m = normalize(raw, day)
  const add = (o: Record<string, number>) => {
    const out = { ...o }
    for (const [k, n] of Object.entries(events)) if (n > 0) out[k] = (out[k] ?? 0) + n
    return out
  }
  return { ...m, c: { ...m.c, d: add(m.c.d), w: add(m.c.w), t: add(m.c.t) } }
}

// 미션 진행(서버가 센 수): 일일 = 오늘, 주간 = 이번 주, 반복 = 마지막으로 받은 뒤
export function progress(d: MissionDef, m: MissionState): number {
  if (d.type === 'daily') return m.c.d[d.kind] ?? 0
  if (d.type === 'weekly') return m.c.w[d.kind] ?? 0
  return Math.max(0, (m.c.t[d.kind] ?? 0) - (m.c.rb[d.id] ?? 0))
}

// 앱에 보내는 진행 {d: 사건 → 오늘, w: 사건 → 이번 주, r: 반복 미션 id → 받은 뒤}
export function progressView(m: MissionState) {
  const r: Record<string, number> = {}
  for (const d of DEFS) if (d.type === 'repeat') r[d.id] = progress(d, m)
  return { d: m.c.d, w: m.c.w, r }
}

// 오늘 받은 일일 미션 수(보너스 제외)
export const dailyCount = (m: MissionState) => m.d.filter((id) => def(id)?.kind !== 'daily_count').length

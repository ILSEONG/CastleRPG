// 파견소 의뢰(사용자 2026-10-13 "파견소도 만들어줘"): 파견소 건물(키 dispatch)에서 의뢰를 받아 영웅을 보내고, 시간이 지나면 보상을 받는다.
// AFK 아레나 현상금 게시판·에픽세븐 파견을 참고했다 — 희귀도마다 인원·시간·보상이 다르고, 의뢰마다 보낼 수 있는 영웅(유형·등급)이 다르다.
// - 희귀도 N·R·SR·SSR. 의뢰 = {id, rarity, size(보낼 인원), grade(최소 등급), types(보낼 수 있는 유형 archetype), min(기본 분), reward}
// - 영웅 조건: 등급 ≥ grade 그리고 유형 ∈ types. 한 영웅은 의뢰 하나에만(파견 중에도 전투에는 나간다).
// - 하루(일일 리셋)에 받는 의뢰 수 = slots(파견소 레벨). 레벨이 오르면 그날 바로 더 받는다. 리셋 때 시작하지 않은 의뢰는 새로 바뀌고,
//   진행 중·끝나고 아직 안 받은 의뢰는 남는다. 받은 의뢰는 목록에서 빠진다(그날 몫이 다시 채워지지 않는다).
// - 새로고침: 시작하지 않은 의뢰를 모두 다시 뽑는다. 하루 첫 번은 무료, 그다음 REFRESH_DIA 다이아(하루 PAID_REFRESH_MAX번까지).
// - 즉시 완료: 남은 분당 다이아 1(올림).
// 파견소 레벨 효과: 하루 의뢰 수(slots), 희귀도 확률(odds), 파견 시간 감소(timeMult).
// 저장: player_state.dispatch jsonb = {day, got, free, paid, seq, list}. 시간은 유닉스 초(서버 시각).

export const KEY = 'dispatch' // 건물 키
export const RARITIES = ['N', 'R', 'SR', 'SSR'] as const
export type Rarity = (typeof RARITIES)[number]
export const GRADES = ['R', 'SR', 'SSR', 'UR'] // 영웅 등급 낮은 순
export const TYPES = ['tank', 'bruiser', 'assassin', 'caster', 'marksman', 'support'] // 영웅 유형(heroes.csv archetype)

// 희귀도 규칙: 인원·최소 등급·허용 유형 수·기본 시간(분)·보상 후보(하나를 뽑는다)
export const RULES: Record<Rarity, { size: number; grade: string; types: number; min: number; rewards: Record<string, number>[] }> = {
  N: { size: 1, grade: 'R', types: 3, min: 60, rewards: [{ pouch_gold_60: 1 }, { pouch_res_60: 1 }, { speedup_any_15: 1 }] },
  R: { size: 2, grade: 'R', types: 3, min: 120, rewards: [{ pouch_gold_120: 1 }, { pouch_res_120: 1 }, { speedup_any_60: 1 }, { diamonds: 20 }] },
  SR: { size: 2, grade: 'SR', types: 3, min: 240, rewards: [{ pouch_gold_240: 1 }, { pouch_res_240: 1 }, { speedup_any_180: 1 }, { diamonds: 50 }, { keys_gold: 1 }, { keys_equip: 1 }] },
  SSR: { size: 2, grade: 'SSR', types: 4, min: 480, rewards: [{ tickets: 1 }, { diamonds: 150 }, { speedup_any_480: 1 }, { pouch_gold_360: 1, pouch_res_360: 1 }, { keys_equip: 2 }] },
}

export const MAX_LEVEL = 30
export const REFRESH_DIA = 50
export const PAID_REFRESH_MAX = 5
export const MAX_LIST = 40 // 목록 상한(진행 중이 쌓여도)

// 하루 의뢰 수: Lv 1 → 3, 5레벨마다 +1(Lv 30 → 9). 0(짓지 않음)이면 0.
export const slots = (level: number) => (level <= 0 ? 0 : 3 + Math.floor(Math.min(level, MAX_LEVEL) / 5))
// 희귀도 확률(%) N·R·SR·SSR: Lv 1 [60, 30, 9, 1] → Lv 30 [25, 40, 25, 10] 직선.
export function odds(level: number): number[] {
  const t = (Math.min(Math.max(level, 1), MAX_LEVEL) - 1) / (MAX_LEVEL - 1)
  const lo = [60, 30, 9, 1]
  const hi = [25, 40, 25, 10]
  return lo.map((a, i) => Math.round((a + (hi[i] - a) * t) * 10) / 10)
}
// 파견 시간 배율: 레벨마다 −1%(Lv 1 = 1, Lv 30 = 0.71)
export const timeMult = (level: number) => 1 - 0.01 * (Math.min(Math.max(level, 1), MAX_LEVEL) - 1)
export const durationSec = (rarity: Rarity, level: number) => Math.round(RULES[rarity].min * 60 * timeMult(level))

export interface Job {
  id: number
  rarity: Rarity
  size: number
  grade: string
  types: string[]
  min: number
  reward: Record<string, number>
  heroes: string[] | null // 보낸 영웅(시작 전 null)
  finish: number | null // 끝나는 시각(시작 전 null)
}
export interface State {
  day: number // 리셋 날짜(rules.resetDay)
  got: number // 오늘 받은 의뢰 수(새로고침은 세지 않는다)
  free: boolean // 오늘 무료 새로고침을 썼다
  paid: number // 오늘 다이아 새로고침 수
  seq: number // 다음 의뢰 id
  list: Job[]
}

const pick = <T>(xs: readonly T[], rnd: () => number): T => xs[Math.min(xs.length - 1, Math.floor(rnd() * xs.length))]

export function rollRarity(level: number, rnd: () => number): Rarity {
  const o = odds(level)
  let r = rnd() * o.reduce((a, b) => a + b, 0)
  for (let i = 0; i < RARITIES.length; i++) {
    r -= o[i]
    if (r < 0) return RARITIES[i]
  }
  return 'N'
}

// 의뢰 하나 뽑기(id는 쓰는 쪽이). 유형은 TYPES에서 겹치지 않게 RULES.types개(표 순서로 정렬).
export function roll(id: number, level: number, rnd: () => number): Job {
  const rarity = rollRarity(level, rnd)
  const rule = RULES[rarity]
  const pool = [...TYPES]
  const types: string[] = []
  while (types.length < rule.types) types.push(pool.splice(Math.floor(rnd() * pool.length) % pool.length, 1)[0])
  types.sort((a, b) => TYPES.indexOf(a) - TYPES.indexOf(b))
  return { id, rarity, size: rule.size, grade: rule.grade, types, min: rule.min, reward: { ...pick(rule.rewards, rnd) }, heroes: null, finish: null }
}

const isJob = (j: any): j is Job => j && Number.isInteger(j.id) && RARITIES.includes(j.rarity) && Number.isInteger(j.size) && GRADES.includes(j.grade)
  && Array.isArray(j.types) && j.types.every((t: unknown) => TYPES.includes(String(t))) && Number.isFinite(j.min) && j.reward && typeof j.reward === 'object'
  && (j.heroes === null || (Array.isArray(j.heroes) && j.heroes.every((h: unknown) => typeof h === 'string')))
  && (j.finish === null || Number.isFinite(j.finish))

// 저장된 값 → 오늘 기준 상태. 날이 바뀌었으면 시작하지 않은 의뢰를 버리고 새날 몫으로. 그다음 오늘 받을 몫(slots − got)만큼 새로 뽑는다.
// changed = 저장할 것이 바뀌었다(GET도 이때만 쓴다).
export function normalize(raw: unknown, day: number, level: number, rnd: () => number): { state: State; changed: boolean } {
  const r = raw && typeof raw === 'object' && !Array.isArray(raw) ? (raw as any) : {}
  let st: State = {
    day: Number.isInteger(r.day) ? r.day : -1,
    got: Number.isInteger(r.got) ? r.got : 0,
    free: r.free === true,
    paid: Number.isInteger(r.paid) ? r.paid : 0,
    seq: Number.isInteger(r.seq) && r.seq > 0 ? r.seq : 1,
    list: Array.isArray(r.list) ? r.list.filter(isJob).map((j: Job) => ({ ...j, types: [...j.types], reward: { ...j.reward }, heroes: j.heroes ? [...j.heroes] : null })) : [],
  }
  let changed = false
  if (st.day !== day) {
    st = { ...st, day, got: 0, free: false, paid: 0, list: st.list.filter((j) => j.heroes !== null) }
    changed = true
  }
  while (st.got < slots(level) && st.list.length < MAX_LIST) {
    st.list.push(roll(st.seq, level, rnd))
    st.seq += 1
    st.got += 1
    changed = true
  }
  return { state: st, changed }
}

// 시작하지 않은 의뢰를 다시 뽑는다(id는 새로).
export function reroll(st: State, level: number, rnd: () => number): State {
  const out = { ...st, list: [...st.list] }
  for (let i = 0; i < out.list.length; i++) {
    if (out.list[i].heroes !== null) continue
    out.list[i] = roll(out.seq, level, rnd)
    out.seq += 1
  }
  return out
}

// 영웅이 그 의뢰 조건에 맞는가(def = heroes.csv 행)
export const eligible = (job: Pick<Job, 'grade' | 'types'>, def: { grade?: unknown; archetype?: unknown }) =>
  GRADES.indexOf(String(def.grade)) >= GRADES.indexOf(job.grade) && job.types.includes(String(def.archetype))

// 지금 파견 중인 영웅(끝났지만 아직 안 받은 것도 — 받을 때 풀린다)
export const busy = (st: State) => new Set(st.list.flatMap((j) => j.heroes ?? []))

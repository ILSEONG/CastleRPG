// 가속 아이템과 일꾼 고용권(2026-10-13, 라오킹식 건설 개편). 보상으로 받아 가방에 두었다가 쓴다.
// - build_<분>: 건설 시간을 그 분만큼 줄인다. research_<분>: 연구 시간. any_<분>(범용): 건설·연구 어느 쪽에나.
// - builder_<분>: 두 번째 일꾼을 그 분만큼 쓴다(이미 있으면 끝나는 시각에 더한다). 쓰는 중에 기한이 지나도 짓던 건물은 끝까지 짓는다.
// 보상 표의 키: speedup_<id>(예: speedup_build_60: 2). 보관: player_state.speedups {id: 개수}.

export const KINDS = ['build', 'research', 'any'] as const
export const MINUTES = [5, 15, 60, 180, 480, 1440]
export const BUILDER_MINUTES = [1440, 2880, 10080, 43200] // 1일·2일·7일·30일
export const IDS = [...KINDS.flatMap((k) => MINUTES.map((m) => `${k}_${m}`)), ...BUILDER_MINUTES.map((m) => `builder_${m}`)]
export const REWARD_PREFIX = 'speedup_'
export const MAX_USE = 999 // 한 번에 쓰는 최대 개수
export const TARGETS = ['build', 'research'] as const

export type Kind = (typeof KINDS)[number] | 'builder'

export function parse(id: string): { kind: Kind; min: number } | null {
  if (!IDS.includes(id)) return null
  const i = id.lastIndexOf('_')
  return { kind: id.slice(0, i) as Kind, min: Number(id.slice(i + 1)) }
}

// 그 아이템을 그 타이머(build | research)에 쓸 수 있나
export const fits = (kind: Kind, target: string) => kind === 'any' || kind === target

// 저장된 값 → 표에 있는 id의 양의 정수 개수만
export function normalize(raw: unknown): Record<string, number> {
  const out: Record<string, number> = {}
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return out
  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) if (IDS.includes(k) && Number.isInteger(v) && (v as number) > 0) out[k] = v as number
  return out
}

// 보상 → 받을 아이템 {id: 개수}
export function fromReward(reward: object): Record<string, number> {
  const out: Record<string, number> = {}
  for (const [k, v] of Object.entries(reward)) {
    const id = k.startsWith(REWARD_PREFIX) ? k.slice(REWARD_PREFIX.length) : ''
    if (IDS.includes(id) && Number.isInteger(v) && v > 0) out[id] = (out[id] ?? 0) + v
  }
  return out
}

// 보유 + 증감(0 이하가 되면 지운다)
export function add(held: Record<string, number>, delta: Record<string, number>): Record<string, number> {
  const out = { ...held }
  for (const [k, d] of Object.entries(delta)) {
    const n = (out[k] ?? 0) + d
    if (n > 0) out[k] = n
    else delete out[k]
  }
  return out
}

// 두 번째 일꾼을 지금 쓸 수 있나(기한 = 유닉스 초, null = 없음)
export const builder2Active = (until: number | null, now: number) => until !== null && until > now

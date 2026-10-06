// 방치 주머니(2026-10-06): 골드 주머니·자원 주머니, 10분·30분·1시간·2시간·4시간·6시간. 출석·미션 보상으로 받아 보관했다가 연다.
// 여는 순간의 방치 수입으로 값을 정한다(스테이지·건물 레벨·연구가 오르면 같은 주머니도 더 많이 준다):
// - 골드 = 그 시간만큼 떠나 있었을 때의 오프라인 처치 골드(rules.offlineReward — 현재 스테이지·kill_gold_pct·offline_gold_mult, 상한 = 주머니 시간)
// - 자원 = 목재·석재·식량 건물이 그 시간 동안 쌓는 양(rules.pendingAmount — 건물 레벨·생산 연구, 상한 = 주머니 시간). 아직 짓지 않은 건물은 0.
// 보상 표의 키: pouch_<id>(예: pouch_gold_60: 1). 보관: player_state.pouches {id: 개수}.

export const KINDS = ['gold', 'res'] as const
export const MINUTES = [10, 30, 60, 120, 240, 360]
export const IDS = KINDS.flatMap((k) => MINUTES.map((m) => `${k}_${m}`))
export const REWARD_PREFIX = 'pouch_'
export const MAX_OPEN = 999 // 한 번에 여는 최대 개수

export function parse(id: string): { kind: (typeof KINDS)[number]; min: number } | null {
  if (!IDS.includes(id)) return null
  const [kind, min] = id.split('_')
  return { kind: kind as (typeof KINDS)[number], min: Number(min) }
}

// 저장된 값 → 표에 있는 id의 양의 정수 개수만
export function normalize(raw: unknown): Record<string, number> {
  const out: Record<string, number> = {}
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return out
  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) if (IDS.includes(k) && Number.isInteger(v) && (v as number) > 0) out[k] = v as number
  return out
}

// 보상 → 받을 주머니 {id: 개수}
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

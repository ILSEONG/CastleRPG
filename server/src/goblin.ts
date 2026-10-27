// 황금 고블린(사용자 2026-10-13): 성 전투 지도에 5~10분마다 황금 보따리를 든 고블린이 나와 돌아다닌다(앱). 영웅이 잡으면 앱이
// POST /v1/goblin/claim을 보내고 서버가 보상을 정한다:
// - 골드 = 지금의 방치 수입 GOLD_MIN분(방치 주머니 골드와 같은 식 — 스테이지·처치 골드 연구가 오르면 같이 오른다)
// - 그날 처음 BONUS_DAILY마리까지는 덤: SPEEDUP_P 확률로 가속 5분, DIA_P 확률로 다이아 DIA(둘 다 따로 굴린다)
// 앞 보상에서 MIN_GAP_SEC초가 지나야 받는다(앱은 5분 이상 간격으로만 내보낸다 — 여유 30초). 아니면 409 too_soon.
// 저장: player_state.goblin jsonb = {at(마지막으로 받은 유닉스 초), day(리셋 날짜), n(그날 잡은 수)}.

export const MIN_GAP_SEC = 270
export const GOLD_MIN = 30  // 2026-10-25 처치 골드 절반 뒤에도 보따리 값은 그대로(사용자 "황금 고블린은 냅둬") — 예전 15분치와 같은 골드
export const BONUS_DAILY = 20
export const SPEEDUP_P = 0.3
export const SPEEDUP = { speedup_any_5: 1 }
export const DIA_P = 0.1
export const DIA = 10

export interface State {
  at: number | null
  day: number
  n: number
}

export function normalize(raw: unknown, day: number): State {
  const r = raw && typeof raw === 'object' && !Array.isArray(raw) ? (raw as any) : {}
  const at = Number.isFinite(r.at) ? Number(r.at) : null
  const same = Number.isInteger(r.day) && r.day === day
  return { at, day, n: same && Number.isInteger(r.n) && r.n > 0 ? r.n : 0 }
}

// 덤 보상(골드 말고). n = 오늘 이미 잡은 수.
export function bonus(n: number, rnd: () => number): Record<string, number> {
  if (n >= BONUS_DAILY) return {}
  const out: Record<string, number> = {}
  if (rnd() < SPEEDUP_P) Object.assign(out, SPEEDUP)
  if (rnd() < DIA_P) out.diamonds = DIA
  return out
}

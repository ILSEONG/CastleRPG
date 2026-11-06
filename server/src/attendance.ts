// 28일 출석 이벤트(2026-10-06): 하루(daily_reset_utc_hour 기준 리셋 날짜)에 한 번, 다음 칸(1..28일차)의 보상을 받는다.
// 날짜가 이어지지 않아도 된다(받은 날 수만 센다). 28일차까지 받으면 끝. 보상 표는 서버가 정하고 GET /v1/attendance가 앱에 준다.
// 보상 키: gold·diamonds·tickets(다이아 모집권)·wood·stone·food·keys_<던전 종류>(열쇠)·hero(영웅 1명, 있으면 복제 +1 = 조각 +1)·
// equip(장비 상자 = 그 등급의 장비 1개, 부위는 던전 드롭과 같은 규칙으로 무작위)·pouch_<id>(방치 주머니, pouches.ts)·speedup_<id>(가속 아이템·일꾼 고용권, speedups.ts).

export const DAYS = 28

export interface AttendReward {
  gold?: number
  diamonds?: number
  tickets?: number
  wood?: number
  stone?: number
  food?: number
  keys_gold?: number
  keys_equip?: number
  keys_ticket?: number
  hero?: string
  equip?: { grade: string }
  [pouch: `pouch_${string}`]: number
  [speedup: `speedup_${string}`]: number
}

// 1..28일차(인덱스 0 = 1일차). 7·14·21·28일차가 큰 보상.
export const REWARDS: AttendReward[] = [
  // 1주차
  { pouch_gold_30: 2, speedup_builder_2880: 1 },
  { tickets: 5, speedup_any_180: 2 },
  { pouch_res_30: 2 },
  { diamonds: 1000 },
  { keys_equip: 2 },
  { pouch_gold_60: 2 },
  { equip: { grade: 'SR' }, tickets: 5, speedup_build_1440: 1 },
  // 2주차
  { pouch_gold_60: 2 },
  { tickets: 5, speedup_any_180: 2 },
  { keys_gold: 3 },
  { diamonds: 1500 },
  { pouch_res_60: 2 },
  { keys_ticket: 2 },
  { hero: 'luna', tickets: 10, speedup_any_1440: 1 },
  // 3주차
  { pouch_gold_120: 2 },
  { tickets: 5, speedup_any_180: 2 },
  { keys_equip: 2 },
  { diamonds: 2000 },
  { pouch_res_120: 2 },
  { pouch_gold_240: 2 },
  { equip: { grade: 'SSR' }, speedup_research_1440: 1 },
  // 4주차
  { pouch_gold_240: 2 },
  { tickets: 10, speedup_any_180: 2 },
  { equip: { grade: 'SR' } },
  { diamonds: 3000, pouch_res_240: 1 },
  { keys_ticket: 3 },
  { tickets: 20, pouch_gold_360: 1, pouch_res_360: 1 },
  { hero: 'arteon', speedup_builder_10080: 1 },
]

// 받을 수 있는가: 아직 28일차 전이고 오늘(리셋 날짜) 받지 않았다.
export const canClaim = (n: number, lastDay: number | null, today: number) => n < DAYS && (lastDay === null || lastDay < today)

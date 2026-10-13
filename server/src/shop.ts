// 상점(2026-10-07): 하단 탭 [상점]. 방치형 게임 상점처럼 일일·주간 한정 상품을 게임 재화(다이아·골드)로 산다 — 실결제는 없다.
// 일일 상품은 daily_reset_utc_hour 리셋 날짜마다, 주간 상품은 미션과 같은 주(월요일, missions.ts weekOf)마다 살 수 있는 횟수가 돌아온다.
// 가격 0 = 무료 선물. 받는 것(give)은 보상 키(gold·diamonds·tickets·wood·stone·food·keys_<던전>·pouch_<id>)로, 출석·미션 보상과 같은 규칙.
// 기록: player_state.shop {day, week, d: {id: 오늘 산 수}, w: {id: 이번 주 산 수}}(마이그레이션 028). 앱 scripts/shop.gd ITEMS가 같은 표를 쓴다.
import { weekOf } from './missions.ts'

export type ShopTab = 'daily' | 'weekly' | 'ad'
export type Currency = 'free' | 'diamonds' | 'gold' | 'ad'

export interface ShopItem {
  id: string
  tab: ShopTab
  name: string
  currency: Currency
  price: number
  limit: number // 리셋 기간(일일·주간)마다 살 수 있는 횟수
  give: Record<string, number>
}

export const ITEMS: ShopItem[] = [
  // 일일
  { id: 'd_free', tab: 'daily', name: '매일 무료 선물', currency: 'free', price: 0, limit: 1, give: { diamonds: 50, pouch_gold_60: 1 } },
  { id: 'd_ticket', tab: 'daily', name: '다이아 모집권 할인', currency: 'diamonds', price: 240, limit: 1, give: { tickets: 1 } },
  { id: 'd_pouch_gold', tab: 'daily', name: '골드 주머니(1시간)', currency: 'diamonds', price: 40, limit: 3, give: { pouch_gold_60: 1 } },
  { id: 'd_pouch_res', tab: 'daily', name: '자원 주머니(1시간)', currency: 'diamonds', price: 40, limit: 3, give: { pouch_res_60: 1 } },
  { id: 'd_key_gold', tab: 'daily', name: '골드 던전 입장권', currency: 'diamonds', price: 60, limit: 3, give: { keys_gold: 1 } },
  { id: 'd_key_equip', tab: 'daily', name: '장비 던전 입장권', currency: 'diamonds', price: 100, limit: 2, give: { keys_equip: 1 } },
  { id: 'd_key_ticket', tab: 'daily', name: '모집권 던전 입장권', currency: 'diamonds', price: 150, limit: 1, give: { keys_ticket: 1 } },
  { id: 'd_res', tab: 'daily', name: '자원 꾸러미', currency: 'diamonds', price: 50, limit: 3, give: { wood: 10000, stone: 10000, food: 10000 } },
  // 가속 아이템(2026-10-13 라오킹식 건설): 다이아로 사는 값은 직접 즉시 완료(분당 1다이아)보다 싸다 — 1시간 40, 8시간 250, 1일 700
  { id: 'd_sp_build', tab: 'daily', name: '건설 가속 1시간', currency: 'diamonds', price: 40, limit: 3, give: { speedup_build_60: 1 } },
  { id: 'd_sp_research', tab: 'daily', name: '연구 가속 1시간', currency: 'diamonds', price: 40, limit: 3, give: { speedup_research_60: 1 } },
  // 광고(2026-10-12, 사용자 "광고보면 다이아주고, 던전 입장권 주고, 이런 광고 상점"): 보상형 광고를 보면 받는다, 매일 리셋(일일과 같은 기록 d).
  // 광고 제거(iap no_ads) 구매자는 광고 없이 바로 받는다 — 서버는 광고 제거가 아니면 body.ad = true(광고를 끝까지 봤다)를 요구한다.
  { id: 'a_dia', tab: 'ad', name: '광고 다이아', currency: 'ad', price: 0, limit: 5, give: { diamonds: 100 } },
  { id: 'a_ticket', tab: 'ad', name: '광고 모집권', currency: 'ad', price: 0, limit: 2, give: { tickets: 1 } },
  { id: 'a_key_gold', tab: 'ad', name: '골드 던전 입장권', currency: 'ad', price: 0, limit: 2, give: { keys_gold: 1 } },
  { id: 'a_key_equip', tab: 'ad', name: '장비 던전 입장권', currency: 'ad', price: 0, limit: 1, give: { keys_equip: 1 } },
  { id: 'a_key_ticket', tab: 'ad', name: '모집권 던전 입장권', currency: 'ad', price: 0, limit: 1, give: { keys_ticket: 1 } },
  { id: 'a_pouch_gold', tab: 'ad', name: '골드 주머니(1시간)', currency: 'ad', price: 0, limit: 3, give: { pouch_gold_60: 1 } },
  { id: 'a_pouch_res', tab: 'ad', name: '자원 주머니(1시간)', currency: 'ad', price: 0, limit: 3, give: { pouch_res_60: 1 } },
  { id: 'a_sp_any', tab: 'ad', name: '범용 가속 15분', currency: 'ad', price: 0, limit: 3, give: { speedup_any_15: 1 } },
  // 주간
  { id: 'w_free', tab: 'weekly', name: '주간 무료 선물', currency: 'free', price: 0, limit: 1, give: { diamonds: 150, tickets: 2 } },
  { id: 'w_tickets', tab: 'weekly', name: '모집권 10장 묶음', currency: 'diamonds', price: 2400, limit: 1, give: { tickets: 10 } },
  { id: 'w_pouch_gold', tab: 'weekly', name: '골드 주머니(6시간)', currency: 'diamonds', price: 200, limit: 2, give: { pouch_gold_360: 1 } },
  { id: 'w_pouch_res', tab: 'weekly', name: '자원 주머니(6시간)', currency: 'diamonds', price: 200, limit: 2, give: { pouch_res_360: 1 } },
  { id: 'w_sp_any', tab: 'weekly', name: '범용 가속 8시간', currency: 'diamonds', price: 250, limit: 3, give: { speedup_any_480: 1 } },
  { id: 'w_sp_build', tab: 'weekly', name: '건설 가속 1일', currency: 'diamonds', price: 700, limit: 2, give: { speedup_build_1440: 1 } },
  { id: 'w_sp_research', tab: 'weekly', name: '연구 가속 1일', currency: 'diamonds', price: 700, limit: 2, give: { speedup_research_1440: 1 } },
  { id: 'w_builder', tab: 'weekly', name: '일꾼 고용권 7일', currency: 'diamonds', price: 1000, limit: 1, give: { speedup_builder_10080: 1 } },
  { id: 'w_res', tab: 'weekly', name: '큰 자원 꾸러미', currency: 'diamonds', price: 300, limit: 2, give: { wood: 100000, stone: 100000, food: 100000 } },
]

export const item = (id: string) => ITEMS.find((x) => x.id === id)

export interface ShopState {
  day: number
  week: number
  d: Record<string, number>
  w: Record<string, number>
}

// 일일 기록 d = 일일 + 광고 상품, 주간 기록 w = 주간 상품
const counts = (raw: unknown, weekly: boolean): Record<string, number> => {
  const out: Record<string, number> = {}
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return out
  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
    const x = item(k)
    if (x && (x.tab === 'weekly') === weekly && Number.isInteger(v) && (v as number) > 0) out[k] = v as number
  }
  return out
}

// 저장된 값 → 오늘(리셋 날짜)·이번 주 기준. 날·주가 바뀌었으면 그 기록을 비운다.
export function normalize(raw: unknown, day: number): ShopState {
  const s = raw && typeof raw === 'object' && !Array.isArray(raw) ? (raw as Record<string, unknown>) : {}
  const week = weekOf(day)
  return {
    day,
    week,
    d: Number(s.day) === day ? counts(s.d, false) : {},
    w: Number(s.week) === week ? counts(s.w, true) : {},
  }
}

export const bought = (s: ShopState, x: ShopItem) => (x.tab === 'weekly' ? s.w : s.d)[x.id] ?? 0

// 한 번 산 기록을 더한 새 상태
export function add(s: ShopState, x: ShopItem): ShopState {
  const key = x.tab === 'weekly' ? 'w' : 'd'
  return { ...s, [key]: { ...s[key], [x.id]: bought(s, x) + 1 } }
}

// BM(2026-10-07, BM 총괄 = Claude): 실결제 상품(다이아 충전·월정액·패키지·성장 패스)과 그 혜택. 방치형 게임 정석 구성:
// - 다이아 충전 6단계: 단계마다 첫 구매는 기본 다이아 2배(보너스 대신), 이후는 기본 + 보너스.
// - 월정액 2종(30일): 사면 즉시 다이아, 기간 동안 매일 한 번 [받기]. 남은 기간에 다시 사면 30일이 이어 붙는다(최대 180일).
// - 패키지: 신규 스타터(평생 1회), 일일(하루 1회)·주간(주 1회) 한정 패키지.
// - 핫딜: 보스 격파(25라운드마다)·다이아 부족·패배 때 1시간 한정 특가가 뜬다(한 번에 하나, 계기마다 쉬는 시간). 뜬 핫딜만 그 시간 안에 한 번 살 수 있다.
// - 성장 패스: 라운드 달성 단계마다 무료 보상(누구나) + 유료 보상(패스 구매자). 산 뒤에는 지난 단계 유료 보상도 받는다.
// 결제 확인(provider): 'google' = Google Play 영수증(앱 등록·상품 등록 전이라 지금은 iap_enabled 설정이 0이면 503 payments_unavailable),
// 'test' = 통합 테스트(allowTestHooks)만. 같은 주문 번호는 한 번만(iap_orders 기본 키).
// 기록: player_state.iap {first: [첫 구매 보너스를 쓴 충전 id], n: {상품 id: 평생 산 수}, day, week, d: {id: 오늘}, w: {id: 이번 주},
// monthly: {종류: {until: 마지막 날(리셋 날짜), claimed: 마지막으로 받은 날}}, passes: [산 패스], gp: {free: [단계], paid: [단계]},
// hot: {id, until: 끝나는 시각(유닉스 초), bought} | null, hcool: {계기: 마지막으로 뜬 시각}, hs: 핫딜을 띄운 마지막 보스 단계(깬 라운드 / 25)}.
// 앱 scripts/iap_items.gd가 같은 표를 쓴다(단위 테스트가 비교한다).
import { weekOf } from './missions.ts'
import { txt } from './texts.ts'

export type Reward = Record<string, number>
export type Kind = 'diamond' | 'monthly' | 'package' | 'pass' | 'hot'
export type Period = 'once' | 'daily' | 'weekly' | 'none'

export interface Product {
  id: string
  kind: Kind
  name: string
  krw: number
  give: Reward // 사면 바로 받는 것
  bonus?: number // 충전: 첫 구매가 아닐 때 더 주는 다이아(첫 구매는 기본 다이아만큼 더 = 2배)
  period?: Period // 패키지 한도 기간
  limit?: number // 그 기간 한도
  days?: number // 월정액 기간
  daily?: Reward // 월정액 매일 보상
  value?: number // 핫딜: 가격 대비 가치 배수(화면 표시 "가치 N배")
}

export const PRODUCTS: Product[] = [
  // 다이아 충전
  { id: 'dia_1', kind: 'diamond', name: txt('server.iap.products.dia_1.name'), krw: 1200, give: { diamonds: 1650 }, bonus: 150 },
  { id: 'dia_2', kind: 'diamond', name: txt('server.iap.products.dia_2.name'), krw: 5900, give: { diamonds: 8000 }, bonus: 1650 },
  { id: 'dia_3', kind: 'diamond', name: txt('server.iap.products.dia_3.name'), krw: 12000, give: { diamonds: 16500 }, bonus: 4400 },
  { id: 'dia_4', kind: 'diamond', name: txt('server.iap.products.dia_4.name'), krw: 33000, give: { diamonds: 46500 }, bonus: 15000 },
  { id: 'dia_5', kind: 'diamond', name: txt('server.iap.products.dia_5.name'), krw: 59000, give: { diamonds: 87000 }, bonus: 31000 },
  { id: 'dia_6', kind: 'diamond', name: txt('server.iap.products.dia_6.name'), krw: 99000, give: { diamonds: 156000 }, bonus: 66000 },
  // 월정액
  { id: 'monthly', kind: 'monthly', name: txt('server.iap.products.monthly.name'), krw: 4900, give: { diamonds: 1500 }, days: 30, daily: { diamonds: 500, speedup_build_60: 1, speedup_research_60: 1 } },
  { id: 'monthly_plus', kind: 'monthly', name: txt('server.iap.products.monthly_plus.name'), krw: 14900, give: { diamonds: 5000, speedup_builder_43200: 1 }, days: 30, daily: { diamonds: 800, tickets: 3, pouch_gold_240: 1, speedup_any_180: 1 } },
  // 패키지
  { id: 'pkg_starter', kind: 'package', name: txt('server.iap.products.pkg_starter.name'), krw: 1200, period: 'once', limit: 1, give: { diamonds: 1500, tickets: 30, pouch_gold_120: 5, pouch_res_120: 5, speedup_builder_10080: 1, speedup_build_60: 5 } },
  { id: 'pkg_daily', kind: 'package', name: txt('server.iap.products.pkg_daily.name'), krw: 1200, period: 'daily', limit: 1, give: { diamonds: 600, tickets: 8, keys_gold: 3, speedup_any_60: 3 } },
  { id: 'pkg_weekly', kind: 'package', name: txt('server.iap.products.pkg_weekly.name'), krw: 5900, period: 'weekly', limit: 1, give: { diamonds: 4000, tickets: 50, keys_equip: 5, speedup_any_480: 3, speedup_builder_10080: 1 } },
  { id: 'pkg_growth', kind: 'package', name: txt('server.iap.products.pkg_growth.name'), krw: 33000, period: 'once', limit: 1, give: { diamonds: 30000, tickets: 150, pouch_gold_360: 10, pouch_res_360: 10, speedup_builder_43200: 1, speedup_build_1440: 5, speedup_research_1440: 5 } },
  // 핫딜(1시간 한정, 뜬 것만)
  { id: 'hot_boss', kind: 'hot', name: txt('server.iap.products.hot_boss.name'), krw: 3300, value: 5, give: { diamonds: 18000, tickets: 20, pouch_gold_360: 3, speedup_build_480: 3 } },
  { id: 'hot_dia', kind: 'hot', name: txt('server.iap.products.hot_dia.name'), krw: 5900, value: 5, give: { diamonds: 40000, tickets: 15 } },
  { id: 'hot_defeat', kind: 'hot', name: txt('server.iap.products.hot_defeat.name'), krw: 4900, value: 5, give: { diamonds: 30000, tickets: 20, pouch_gold_360: 5, pouch_res_360: 5, speedup_any_480: 3 } },
  // 패스
  { id: 'pass_growth', kind: 'pass', name: txt('server.iap.products.pass_growth.name'), krw: 9900, give: {} },
  // 광고 제거: 상점 [광고] 상품을 광고 없이 바로 받는다(view.ad_free). 구매 보너스는 없다(사용자 2026-10-12 "광고제거 사면 이득보는걸 지우고").
  { id: 'no_ads', kind: 'pass', name: txt('server.iap.products.no_ads.name'), krw: 5500, give: {} },
]

// 성장 패스 단계: 라운드(GameData.round_label — 25라운드 = 1스테이지)를 깨면 받는다. free = 누구나, paid = 패스 구매자.
export const GROWTH: { round: number; free: Reward; paid: Reward }[] = [
  { round: 10, free: { diamonds: 60 }, paid: { diamonds: 1800, speedup_any_180: 2 } },
  { round: 25, free: { tickets: 2 }, paid: { diamonds: 1800, tickets: 12, speedup_any_180: 2 } },
  { round: 50, free: { diamonds: 100 }, paid: { diamonds: 2400, speedup_any_180: 2 } },
  { round: 75, free: { tickets: 2 }, paid: { diamonds: 2400, tickets: 18, speedup_any_180: 2 } },
  { round: 100, free: { diamonds: 100 }, paid: { diamonds: 3000, speedup_any_180: 2, speedup_builder_10080: 1 } },
  { round: 150, free: { tickets: 2 }, paid: { diamonds: 3000, tickets: 18, speedup_any_180: 2 } },
  { round: 200, free: { diamonds: 160 }, paid: { diamonds: 3600, speedup_any_180: 2 } },
  { round: 250, free: { tickets: 4 }, paid: { diamonds: 3600, tickets: 30, speedup_any_180: 2 } },
  { round: 300, free: { diamonds: 200 }, paid: { diamonds: 4800, speedup_any_180: 2, speedup_builder_10080: 1 } },
  { round: 375, free: { tickets: 4 }, paid: { diamonds: 4800, tickets: 30, speedup_any_180: 2 } },
  { round: 450, free: { diamonds: 200 }, paid: { diamonds: 6000, speedup_any_180: 2 } },
  { round: 550, free: { tickets: 6 }, paid: { diamonds: 6000, tickets: 60, speedup_any_180: 2 } },
]

export const MONTHLY_MAX_DAYS = 180

// 핫딜: 계기 → 상품, 뜬 뒤 살 수 있는 시간, 계기마다 다시 뜨기까지 쉬는 시간(초). 보스는 25라운드(1스테이지)마다 한 번.
export const HOT_SEC = 3600
export const HOT: Record<string, { product: string; cool: number }> = {
  boss: { product: 'hot_boss', cool: 6 * 3600 },
  dia: { product: 'hot_dia', cool: 24 * 3600 },
  defeat: { product: 'hot_defeat', cool: 12 * 3600 },
}
export const HOT_ROUNDS = 25

export const product = (id: string) => PRODUCTS.find((p) => p.id === id)

export interface IapState {
  first: string[]
  n: Record<string, number>
  day: number
  week: number
  d: Record<string, number>
  w: Record<string, number>
  monthly: Record<string, { until: number; claimed: number | null }>
  passes: string[]
  gp: { free: number[]; paid: number[] }
  hot: { id: string; until: number; bought: boolean } | null
  hcool: Record<string, number>
  hs: number
}

const obj = (x: unknown): Record<string, unknown> => (x && typeof x === 'object' && !Array.isArray(x) ? (x as Record<string, unknown>) : {})
const ints = (x: unknown): Record<string, number> => {
  const out: Record<string, number> = {}
  for (const [k, v] of Object.entries(obj(x))) if (product(k) && Number.isInteger(v) && (v as number) > 0) out[k] = v as number
  return out
}
const idxs = (x: unknown, max: number) => (Array.isArray(x) ? [...new Set(x.filter((i) => Number.isInteger(i) && i >= 0 && i < max))].sort((a, b) => a - b) : [])

// 저장된 값 → 오늘(리셋 날짜)·이번 주 기준(날·주가 바뀌면 그 기간 기록을 비운다).
export function normalize(raw: unknown, day: number): IapState {
  const s = obj(raw)
  const week = weekOf(day)
  const monthly: IapState['monthly'] = {}
  for (const [k, v] of Object.entries(obj(s.monthly))) {
    const m = obj(v)
    if (product(k)?.kind === 'monthly' && Number.isInteger(m.until)) monthly[k] = { until: m.until as number, claimed: Number.isInteger(m.claimed) ? (m.claimed as number) : null }
  }
  const gp = obj(s.gp)
  return {
    first: Array.isArray(s.first) ? s.first.filter((x): x is string => typeof x === 'string' && product(x)?.kind === 'diamond') : [],
    n: ints(s.n),
    day,
    week,
    d: Number(s.day) === day ? ints(s.d) : {},
    w: Number(s.week) === week ? ints(s.w) : {},
    monthly,
    passes: Array.isArray(s.passes) ? s.passes.filter((x): x is string => typeof x === 'string' && product(x)?.kind === 'pass') : [],
    gp: { free: idxs(gp.free, GROWTH.length), paid: idxs(gp.paid, GROWTH.length) },
    hot: hotOf(s.hot),
    hcool: Object.fromEntries(Object.entries(obj(s.hcool)).filter(([k, v]) => HOT[k] && typeof v === 'number' && Number.isFinite(v))) as Record<string, number>,
    hs: Number.isInteger(s.hs) && (s.hs as number) >= 0 ? (s.hs as number) : 0,
  }
}

function hotOf(x: unknown): IapState['hot'] {
  const h = obj(x)
  return typeof h.id === 'string' && product(h.id)?.kind === 'hot' && typeof h.until === 'number' ? { id: h.id, until: h.until, bought: h.bought === true } : null
}

// 지금 떠 있는 핫딜(안 샀고 시간 안). 없으면 null.
export const activeHot = (s: IapState, now: number) => (s.hot && !s.hot.bought && s.hot.until > now ? s.hot : null)

// 핫딜 띄우기: 이미 떠 있으면 'active', 쉬는 시간이면 'cooldown', 보스는 새 단계를 깨지 않았으면 'not_ready'. 되면 새 상태.
export function offerHot(s: IapState, trigger: string, now: number, cleared: number): IapState | 'active' | 'cooldown' | 'not_ready' | 'unknown' {
  const h = HOT[trigger]
  if (!h) return 'unknown'
  if (activeHot(s, now)) return 'active'
  const stage = Math.floor(cleared / HOT_ROUNDS)
  if (trigger === 'boss' && stage <= s.hs) return 'not_ready'
  const last = s.hcool[trigger]
  if (last != null && now - last < h.cool) {
    if (trigger === 'boss') return { ...s, hs: stage } // 쉬는 동안 깬 단계는 넘긴다
    return 'cooldown'
  }
  return { ...s, hot: { id: h.product, until: now + HOT_SEC, bought: false }, hcool: { ...s.hcool, [trigger]: now }, hs: trigger === 'boss' ? stage : s.hs }
}

// 지금 더 살 수 있는가(패키지 한도·패스 중복·핫딜은 떠 있는 것만). 월정액·충전은 언제나(월정액은 최대 기간까지).
export function canBuy(s: IapState, p: Product, now = 0): boolean {
  if (p.kind === 'hot') return activeHot(s, now)?.id === p.id
  if (p.kind === 'pass') return !s.passes.includes(p.id)
  if (p.kind === 'monthly') return monthlyLeft(s, p.id) + (p.days ?? 0) <= MONTHLY_MAX_DAYS
  if (p.kind !== 'package') return true
  const had = p.period === 'daily' ? s.d[p.id] ?? 0 : p.period === 'weekly' ? s.w[p.id] ?? 0 : s.n[p.id] ?? 0
  return had < (p.limit ?? 1)
}

// 월정액 남은 날 수(오늘 포함). 없으면 0.
export function monthlyLeft(s: IapState, id: string): number {
  const m = s.monthly[id]
  return m && m.until >= s.day ? m.until - s.day + 1 : 0
}

// 사면 받는 것(충전 첫 구매 2배·보너스 반영)과 새 상태.
export function purchase(s: IapState, p: Product): { give: Reward; state: IapState } {
  const give: Reward = { ...p.give }
  const st: IapState = { ...s, n: { ...s.n, [p.id]: (s.n[p.id] ?? 0) + 1 }, d: { ...s.d }, w: { ...s.w }, monthly: { ...s.monthly }, first: [...s.first], passes: [...s.passes] }
  if (p.kind === 'diamond') {
    const base = p.give.diamonds ?? 0
    if (!s.first.includes(p.id)) {
      give.diamonds = base * 2
      st.first.push(p.id)
    } else give.diamonds = base + (p.bonus ?? 0)
  }
  if (p.kind === 'package') {
    if (p.period === 'daily') st.d[p.id] = (s.d[p.id] ?? 0) + 1
    if (p.period === 'weekly') st.w[p.id] = (s.w[p.id] ?? 0) + 1
  }
  if (p.kind === 'monthly') {
    const left = monthlyLeft(s, p.id)
    const old = s.monthly[p.id]
    st.monthly[p.id] = { until: s.day + left + (p.days ?? 30) - 1, claimed: left > 0 && old ? old.claimed : null }
  }
  if (p.kind === 'pass') st.passes.push(p.id)
  if (p.kind === 'hot' && s.hot) st.hot = { ...s.hot, bought: true }
  return { give, state: st }
}

// 월정액 오늘 받을 수 있는가.
export const canClaimMonthly = (s: IapState, id: string) => monthlyLeft(s, id) > 0 && s.monthly[id].claimed !== s.day

// 성장 패스 단계 받을 수 있는가: 그 라운드를 깼고(cleared = 깬 마지막 라운드), 아직 안 받았고, 유료는 패스가 있다.
// 광고 제거를 샀다(보상형 광고를 보지 않고 바로 받는다).
export const adFree = (s: IapState) => s.passes.includes('no_ads')

export function canClaimGrowth(s: IapState, tier: number, track: 'free' | 'paid', cleared: number): boolean {
  const t = GROWTH[tier]
  if (!t || cleared < t.round || s.gp[track].includes(tier)) return false
  return track === 'free' || s.passes.includes('pass_growth')
}

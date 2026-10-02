// 경제 규칙(순수 함수, 시간은 인자 — 유닉스 초). 앱 economy.gd(개정 7)·game_data.gd(개정 8)와 같은 규칙.
import { randomBytes } from 'node:crypto'

export type Config = Record<string, string>

// 48비트 암호학적 난수 → [0, 1). 모집의 기본 난수.
export const cryptoRandom = () => randomBytes(6).readUIntBE(0, 6) / 2 ** 48

export interface StageRow {
  stage: number
  hp_mult: number
  atk_mult: number
  gold_mult: number
  waves: number
  wave_size: number
  idle_interval: number
}

export const STAGE_COLS = ['hp_mult', 'atk_mult', 'gold_mult', 'waves', 'wave_size', 'idle_interval'] as const
const INT_COLS = ['waves', 'wave_size']
export const EXTEND_ROWS = 12 // 표 너머 연장 기울기를 잴 마지막 행 수
export const MIN_IDLE_INTERVAL = 0.5

export function cfgNum(config: Config, key: string): number {
  const v = Number(config[key])
  if (config[key] === undefined || config[key].trim() === '' || !Number.isFinite(v)) throw new Error(`config '${key}' is missing or not a number`)
  return v
}

// Godot roundi와 같게 .5는 0에서 먼 쪽으로.
export const roundHalfAway = (v: number) => Math.sign(v) * Math.round(Math.abs(v))

// --- 축적과 수집 (개정 7 §2) ---

// 쌓인 양 = floor(min(경과, 상한)/60) × 분당 × 레벨. 경과가 0 이하면 0.
export function pendingAmount(perMin: number, level: number, elapsedSec: number, capMin: number): number {
  if (elapsedSec <= 0) return 0
  return Math.floor(Math.min(elapsedSec, capMin * 60) / 60) * perMin * level
}

// 수집 한 번: 상한 미만이면 수집한 분만큼만 옮기고(남은 초 유지), 상한이면 지금으로, 경과가 음수면 지금으로(수집 0).
// 쌓인 양이 0이면 changed = false(아무것도 안 바뀜).
export function collectStep(lastCollect: number, now: number, perMin: number, level: number, capMin: number) {
  if (now < lastCollect) return { amount: 0, lastCollect: now, changed: true }
  const elapsed = now - lastCollect
  const amount = pendingAmount(perMin, level, elapsed, capMin)
  if (amount === 0) return { amount: 0, lastCollect, changed: false }
  const next = elapsed >= capMin * 60 ? now : lastCollect + Math.floor(elapsed / 60) * 60
  return { amount, lastCollect: next, changed: true }
}

// --- 상인 시세 (개정 7 §3, 서버는 mulberry32) ---

export const hourIndex = (unix: number) => Math.floor(unix / 3600)
export const nextChange = (unix: number) => (hourIndex(unix) + 1) * 3600

export function mulberry32(seed: number): () => number {
  let a = seed >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

// 자원마다 따로 뽑는다(개정 11). 시드 = (시간 칸, 자원 순번)을 섞은 값.
export const MERCHANT_RES = ['wood', 'stone', 'food']
export const merchantSeed = (hour: number, index: number) => (Math.imul(hour | 0, 0x9e3779b1) ^ Math.imul(index + 1, 0x85ebca6b)) >>> 0

export function merchantRates(hour: number, config: Config, ids: string[] = MERCHANT_RES): Record<string, number> {
  const out: Record<string, number> = {}
  ids.forEach((id, i) => { out[id] = merchantRate(merchantSeed(hour, i), config) })
  return out
}

// 시드만의 결정적 함수. jackpot_p 확률로 jackpot_rate, 나머지는 min..max를 step 단위로, 가중치 1 → 1/ratio 직선.
export function merchantRate(seed: number, config: Config): number {
  const rnd = mulberry32(seed)
  if (rnd() < cfgNum(config, 'merchant_jackpot_p')) return cfgNum(config, 'merchant_jackpot_rate')
  const step = cfgNum(config, 'merchant_rate_step')
  const min = cfgNum(config, 'merchant_rate_min')
  const n = Math.round((cfgNum(config, 'merchant_rate_max') - min) / step) + 1
  const at = (i: number) => Math.round((min + i * step) * 1000) / 1000 // 0.001 단위(step이 1/정수가 아니어도)
  if (n <= 1) return at(0)
  const lowW = 1 / cfgNum(config, 'merchant_low_high_ratio')
  const ws: number[] = []
  let total = 0
  for (let i = 0; i < n; i++) {
    ws.push(1 - ((1 - lowW) * i) / (n - 1))
    total += ws[i]
  }
  let pick = rnd() * total
  for (let i = 0; i < n; i++) {
    pick -= ws[i]
    if (pick < 0) return at(i)
  }
  return at(n - 1)
}

// floor(수량 × 단가 × 배율). 배율을 0.001 단위 정수로 바꿔 내림 오차를 없앤다.
export function sellValue(amount: number, price: number, rate: number): number {
  return Math.floor((amount * price * Math.round(rate * 1000)) / 1000)
}

// --- 스테이지·처치 (개정 8) ---

// n번째 스테이지(1부터). 표 끝을 넘으면 마지막 EXTEND_ROWS행의 평균 기울기로 직선 연장(정수 열 ≥ 1, 방치 간격 ≥ 0.5).
export function stageRow(n: number, rows: StageRow[]): StageRow {
  if (rows.length === 0) throw new Error('stages table is empty')
  n = Math.max(n, 1)
  if (n <= rows.length) return rows[n - 1]
  const last = rows[rows.length - 1]
  const back = Math.min(EXTEND_ROWS, rows.length - 1)
  const base = rows[rows.length - 1 - back]
  const k = n - rows.length
  const out = { stage: n } as StageRow
  for (const col of STAGE_COLS) {
    const slope = back > 0 ? (last[col] - base[col]) / back : 0
    const v = last[col] + slope * k
    out[col] = INT_COLS.includes(col) ? Math.max(1, roundHalfAway(v)) : v
  }
  out.idle_interval = Math.max(out.idle_interval, MIN_IDLE_INTERVAL)
  return out
}

// 처치 골드(tenths, 0.1 단위 정수) = max(1, round(gold × gold_mult × 10)). 앱 GameData.kill_gold_tenths와 같은 식.
export function killGoldTenths(monsterGold: number, stage: StageRow): number {
  return Math.max(1, roundHalfAway(monsterGold * stage.gold_mult * 10))
}

// 처치 토큰 버킷. 지난 보고 시각은 최대 burstSec초 전까지만 인정한다(from) — 쌓이는 상한이 burstSec × rate로 묶인다.
// 상한 = max(0, ceil((now − from) × rate)). kept개를 인정하면 다음 보고 시각 = from + kept / rate(쓴 만큼만 앞으로).
// 같은 순간 여러 번 보내도 합쳐서 버킷 이상은 못 얻는다.
export function killBucket(lastReport: number, now: number, ratePerSec: number, burstSec: number) {
  const from = Math.max(lastReport, now - burstSec)
  const cap = Math.max(0, Math.ceil((now - from) * ratePerSec))
  return { cap, after: (kept: number) => (kept > 0 ? from + kept / ratePerSec : from) }
}

// 스테이지 최소 클리어 시간(초) = 웨이브 수 × 웨이브 크기 / 초당 처치 상한. 이보다 빠른 클리어는 받지 않는다.
export const minClearSec = (row: StageRow, ratePerSec: number) => (row.waves * row.wave_size) / ratePerSec

// --- 영웅 (개정 10) ---

// 배치 슬롯 수 = 성채 단계 표 keep_slot_tiers(개정 12). 앱 GameData.hero_slots와 같다.
export const heroSlots = (config: Config, keepLevel: number) => tierValue(config, 'keep_slot_tiers', keepLevel)

// --- 건물 (개정 12 §2.2·§2.3) — 앱 GameData.build_cost·build_sec·tier_value와 같은 식 ---

export const BUILD_RES = ['wood', 'stone', 'food'] // 건물 비용 열 = 자원 id
export const BUILD_COST_GROWTH = 1.35
export const BUILD_TIME_GROWTH = 1.5
export const KEEP = 'keep' // 다른 건물의 상한·영웅 슬롯·성 HP
export const GATE = 'gate' // 성문 HP
export const HOUSES = 'houses' // 인구(병사 배치 상한, 개정 13)
export const TAVERN = 'tavern' // 모집 확률

export interface BuildingDef {
  id: string
  name: string
  max_level: number
  wood: number
  stone: number
  food: number
  base_sec: number
  req1: string | null
  req2: string | null
}

// base × growth^n을 곱셈 n번으로 — 앱(GDScript)과 같은 IEEE 곱셈 순서라 pow 구현 차이로 반올림이 갈리지 않는다.
export function grown(base: number, growth: number, n: number): number {
  let v = base
  for (let i = 0; i < n; i++) v *= growth
  return v
}

// L → L+1 비용 {wood, stone, food} = round(값 × 1.35^(L−1)).
export function buildCost(def: BuildingDef, level: number): Record<string, number> {
  const out: Record<string, number> = {}
  for (const r of BUILD_RES) out[r] = roundHalfAway(grown(Number(def[r as 'wood']), BUILD_COST_GROWTH, level - 1))
  return out
}

// L → L+1 시간(초) = round(base_sec × 1.5^(L−1)).
export const buildSec = (def: BuildingDef, level: number) => roundHalfAway(grown(Number(def.base_sec), BUILD_TIME_GROWTH, level - 1))

// 단계 표 "레벨:값|…" → [[레벨, 값], …]. 레벨은 1부터 오름차순 정수, 값은 숫자. 틀리면 null.
export function parseTiers(text: string): [number, number][] | null {
  const out: [number, number][] = []
  for (const part of String(text).split('|')) {
    const m = /^\s*(\d+)\s*:\s*([+-]?(\d+(\.\d*)?|\.\d+))\s*$/.exec(part)
    if (!m) return null
    const level = Number(m[1])
    if (out.length === 0 ? level !== 1 : level <= out[out.length - 1][0]) return null
    out.push([level, Number(m[2])])
  }
  return out
}

// 레벨 이하인 마지막 단계의 값.
export function tierValue(config: Config, key: string, level: number): number {
  const tiers = parseTiers(config[key] ?? '')
  if (!tiers) throw new Error(`config '${key}' is missing or not a tier table`)
  let v = tiers[0][1]
  for (const [l, x] of tiers) if (level >= l) v = x
  return v
}

// 인구 = pop_base + pop_per_house × (민가 − 1)(사용자 지시 2026-10-01: 민가는 축적 상한 대신 인구. 병사 배치 상한).
export const population = (config: Config, housesLevel: number) =>
  cfgNum(config, 'pop_base') + cfgNum(config, 'pop_per_house') * (Math.max(housesLevel, 1) - 1)

// --- 병사 (개정 13) — 앱 GameData.soldier_unit_sec·Economy.auto_deploy와 같은 식 ---

export interface SoldierDef {
  id: string
  name: string
  building: string
  hp: number
  atk: number
  range: number
  atk_interval: number
  speed: number
  aggro: number
  model: string
}

// 보유·배치 키 "병종:티어"
export const soldierKey = (type: string, tier: number) => `${type}:${tier}`
export function parseSoldierKey(key: string, defs: SoldierDef[], maxTier: number): { type: string; tier: number } | null {
  const m = /^([a-z_]+):([1-9]\d*)$/.exec(key)
  if (!m || !defs.some((d) => d.id === m[1]) || Number(m[2]) > maxTier) return null
  return { type: m[1], tier: Number(m[2]) }
}

// 훈련 티어(개정 19): 한 티어 = k(= train_base_min / train_step_min)레벨. t = min(최대 티어, 1 + floor((L−1)/k)).
const trainK = (config: Config) => Math.max(1, Math.floor(cfgNum(config, 'train_base_min') / cfgNum(config, 'train_step_min')))
export const trainTier = (config: Config, level: number) =>
  Math.min(cfgNum(config, 'soldier_max_tier'), 1 + Math.floor((Math.max(level, 1) - 1) / trainK(config)))
// 1마리 훈련 시간(초) = (train_base_min − train_step_min × s) × 60, s = (L−1) mod k(마지막 티어 뒤는 k−1로 고정). n마리는 n × 이 값.
export function soldierUnitSec(config: Config, level: number): number {
  const k = trainK(config)
  const L = Math.max(level, 1) - 1
  const s = L >= cfgNum(config, 'soldier_max_tier') * k ? k - 1 : L % k
  return (cfgNum(config, 'train_base_min') - cfgNum(config, 'train_step_min') * s) * 60
}

// --- 훈련 (개정 16) — 앱 GameData.train_unit_cost·train_max와 같은 식 ---

// 1마리 비용 "자원:수|…"(train_cost_<병종>, 수는 0 이상 정수, 자원은 BUILD_RES, 겹치면 안 된다). "0"이면 무료 {}. 틀리면 null.
export function parseTrainCost(text: string): Record<string, number> | null {
  if (String(text).trim() === '0') return {}
  const out: Record<string, number> = {}
  for (const part of String(text).split('|')) {
    const m = /^\s*([a-z]+)\s*:\s*(\d+)\s*$/.exec(part)
    if (!m || !BUILD_RES.includes(m[1]) || Object.hasOwn(out, m[1])) return null
    out[m[1]] = Number(m[2])
  }
  return out
}

// n마리 비용 {자원: 수} = 1마리 비용 × train_cost_tier_mult^(tier−1) × n(개정 19).
export function trainCost(config: Config, type: string, n: number, tier = 1): Record<string, number> {
  const one = parseTrainCost(config[`train_cost_${type}`] ?? '')
  if (!one) throw new Error(`config 'train_cost_${type}' is missing or not 'res:amount|…'`)
  const m = cfgNum(config, 'train_cost_tier_mult') ** (tier - 1)
  return Object.fromEntries(Object.entries(one).map(([r, v]) => [r, v * m * n]))
}

// 묶음 상한 = train_batch_base + train_batch_per_level × (L − 1).
export const trainMax = (config: Config, level: number) =>
  cfgNum(config, 'train_batch_base') + cfgNum(config, 'train_batch_per_level') * (Math.max(level, 1) - 1)

// 취소 환불 = 비용의 절반(자원마다 내림).
export const trainRefund = (cost: Record<string, number>) => Object.fromEntries(Object.entries(cost).map(([r, v]) => [r, Math.floor(v / 2)]))

// 합성 뒤 배치 자르기: 배치 수를 보유 수로(0이면 키를 뺀다).
export function trimDeploy(deploy: Record<string, number>, owned: Record<string, number>): Record<string, number> {
  const out: Record<string, number> = {}
  for (const [k, n] of Object.entries(deploy)) {
    const v = Math.min(n, owned[k] ?? 0)
    if (v > 0) out[k] = v
  }
  return out
}

// --- 모집 (개정 23: 골드 레벨·다이아 천장) — 앱 GameData.gacha_*와 같은 식 ---

export const GACHA_GOLD = 'gold'
export const GACHA_DIA = 'diamond'
export const GACHA_CURRENCIES = [GACHA_GOLD, GACHA_DIA]
export const GOLD_COST_STEP = 50 // 골드 1회 비용 반올림 단위(스펙 예시 3,450·5,250·10,550과 맞는 값)

// 골드 모집 레벨을 1..gacha_gold_level_max로(설정 최대가 줄어도 확률이 검사한 범위를 넘지 않게)
const goldLevel = (config: Config, level: number) => Math.min(Math.max(level, 1), cfgNum(config, 'gacha_gold_level_max'))

// 골드 1회 비용 = base × growth^(L−1)을 GOLD_COST_STEP 단위로 반올림.
export const goldCost1 = (config: Config, level: number) =>
  roundHalfAway(grown(cfgNum(config, 'gacha_gold_cost_base'), cfgNum(config, 'gacha_gold_cost_growth'), goldLevel(config, level) - 1) / GOLD_COST_STEP) * GOLD_COST_STEP

// 모집 비용(정수 골드 또는 다이아). 골드 10회 = 1회 × 10(할인 없음).
export function gachaCost(config: Config, currency: string, count: number, level: number): number {
  if (currency === GACHA_DIA) return cfgNum(config, count === 10 ? 'gacha_dia_cost_10' : 'gacha_dia_cost_1')
  return goldCost1(config, level) * count
}

// 모집 확률 {ssr, sr}(R은 나머지). 골드 = base + step × (L − 1), 다이아 = 고정. 둘 다 주점 보너스(tavern_*_per_level × (주점 − 1))를 더한다.
export function gachaRates(config: Config, currency: string, level: number, tavernLevel: number) {
  const t = Math.max(tavernLevel, 1) - 1
  const k = goldLevel(config, level) - 1
  const dia = currency === GACHA_DIA
  const ssr = dia ? cfgNum(config, 'gacha_dia_ssr') : cfgNum(config, 'gacha_gold_ssr_base') + cfgNum(config, 'gacha_gold_ssr_step') * k
  const sr = dia ? cfgNum(config, 'gacha_dia_sr') : cfgNum(config, 'gacha_gold_sr_base') + cfgNum(config, 'gacha_gold_sr_step') * k
  return { ssr: ssr + cfgNum(config, 'tavern_ssr_per_level') * t, sr: sr + cfgNum(config, 'tavern_sr_per_level') * t }
}

// 다음 레벨까지 필요한 누적(그 레벨 안) = gacha_gold_level_pulls × L. 최대 레벨이면 null.
export const goldNext = (config: Config, level: number) =>
  level >= cfgNum(config, 'gacha_gold_level_max') ? null : cfgNum(config, 'gacha_gold_level_pulls') * level

// 골드 모집 add회 누적 → 레벨업(한 번에 여러 레벨, 남은 횟수는 넘긴다). 최대 레벨이면 누적 0.
export function goldLevelUp(config: Config, level: number, pulls: number, add: number) {
  let next = goldNext(config, level)
  pulls += add
  while (next !== null && pulls >= next) {
    pulls -= next
    level += 1
    next = goldNext(config, level)
  }
  return { level, pulls: next === null ? 0 : pulls }
}

// 업그레이드를 못 하는 이유(앱 Economy.upgrade_block_for와 같은 순서·코드). 되면 ''. 스펙 §2.4 검사 순서:
// 존재(unknown) → 최대 레벨(max_level) → 성채 상한(keep_cap, 성채 제외) → 선행(prereq: req ≥ T−1) → 일꾼(builder_busy) → 자원(not_enough).
// levels: 건물 → 레벨(없으면 1), res: 쓸 수 있는 자원(자원 건물이면 자동 수집분을 더해서 넘긴다).
export function upgradeBlock(id: string, defs: BuildingDef[], levels: Record<string, number>, builderBusy: boolean, res: Record<string, number>): string {
  const def = defs.find((d) => d.id === id)
  if (!def) return 'unknown'
  const lv = (b: string) => (Object.hasOwn(levels, b) ? levels[b] : 1)
  const to = lv(id) + 1
  if (lv(id) >= def.max_level) return 'max_level'
  if (id !== KEEP && to > lv(KEEP)) return 'keep_cap'
  for (const req of [def.req1, def.req2]) if (req && lv(req) < to - 1) return 'prereq'
  if (builderBusy) return 'builder_busy'
  const cost = buildCost(def, lv(id))
  if (BUILD_RES.some((r) => (res[r] ?? 0) < cost[r])) return 'not_enough'
  return ''
}

// 모집(스펙 §3.6): 장마다 등급(SSR rates.ssr, SR rates.sr, 나머지 R)을 정하고 그 등급 안에서 균등하게 뽑는다.
// rand는 [0, 1) 난수(서버는 암호학적 난수). rates = gachaRates(기본: 골드 Lv 1·주점 1).
// pity(다이아 모집만, 개정 23)가 있으면 장마다 n += 1, n ≥ max면 SSR 확정, SSR이면 n = 0 — n을 바꿔 둔다. 다이아 10연차는 또
// SR 이상이 gacha_10_min_sr장보다 적으면 뒤에서부터 R을 SR(균등)로 바꾼다. 골드 10연차에는 보장이 없다.
// 앱 Economy.roll_gacha와 같은 규칙.
export function rollGacha(count: number, heroes: { id: string; grade: string }[], config: Config, rand: () => number,
  rates = gachaRates(config, GACHA_GOLD, 1, 1), pity?: { n: number; max: number }) {
  const pools: Record<string, string[]> = { SSR: [], SR: [], R: [] }
  for (const h of heroes) pools[h.grade]?.push(h.id)
  const pick = (grade: string) => {
    const pool = pools[grade]
    if (pool.length === 0) throw new Error(`no ${grade} heroes to recruit`)
    return { id: pool[Math.floor(rand() * pool.length)], grade }
  }
  const { ssr, sr } = rates
  const out: { id: string; grade: string }[] = []
  for (let i = 0; i < count; i++) {
    const r = rand()
    let grade = r < ssr ? 'SSR' : r < ssr + sr ? 'SR' : 'R'
    if (pity) {
      pity.n += 1
      if (pity.n >= pity.max) grade = 'SSR'
      if (grade === 'SSR') pity.n = 0
    }
    out.push(pick(grade))
  }
  if (count === 10 && pity) {
    let need = cfgNum(config, 'gacha_10_min_sr') - out.filter((x) => x.grade !== 'R').length
    for (let i = out.length - 1; i >= 0 && need > 0; i--) {
      if (out[i].grade === 'R') {
        out[i] = pick('SR')
        need--
      }
    }
  }
  return out
}

// --- 영웅 레벨업 (개정 11 §2.1) — 앱 GameData.max_level·levelup_total과 같은 식 ---

export const LEVELUP_GOLD_GROWTH = 1.12

// 최대 레벨 = hero_max_level_base + hero_max_level_per_promotion × 승급(개정 15).
export function heroMaxLevel(promotion: number, config: Config): number {
  return cfgNum(config, 'hero_max_level_base') + cfgNum(config, 'hero_max_level_per_promotion') * promotion
}

// --- 영웅 승급 (개정 15 §1) — 앱 GameData.promote_cost와 같은 식 ---

export const MAX_PROMOTION = 5 // player_heroes.promotion check와 같다

// 승급 p → p+1에 드는 조각 = promote_shards의 p번째(0부터). 최대 승급이면 null.
export function promoteCost(promotion: number, config: Config): number | null {
  if (promotion >= MAX_PROMOTION) return null
  const v = Number(String(config.promote_shards ?? '').split('|')[promotion])
  if (!Number.isInteger(v) || v < 1) throw new Error("config 'promote_shards' is missing or not a list of positive integers")
  return v
}

// level에서 count번 올리는 비용 합계. L → L+1: 골드(정수) = round(levelup_gold_<등급> × 1.12^(L−1)), 개정 12: 골드만.
export function levelupCost(grade: string, level: number, count: number, config: Config) {
  const g = cfgNum(config, `levelup_gold_${grade}`)
  let gold = 0
  for (let l = level; l < level + count; l++) {
    gold += roundHalfAway(g * LEVELUP_GOLD_GROWTH ** (l - 1))
  }
  return { gold }
}

// 상한을 넘는 처치는 버린다 — 싼 몬스터부터 인정하고 비싼 몬스터를 먼저 버린다(부풀린 보스 처치가 먼저 잘린다).
export function clampKills(kills: { id: string; count: number; gold: number }[], cap: number) {
  const total = kills.reduce((s, k) => s + k.count, 0)
  const kept: Record<string, number> = {}
  if (total <= cap) {
    for (const k of kills) kept[k.id] = k.count
    return { kept, clamped: false }
  }
  let left = cap
  for (const k of [...kills].sort((a, b) => a.gold - b.gold || (a.id < b.id ? -1 : 1))) {
    kept[k.id] = Math.min(k.count, left)
    left -= kept[k.id]
  }
  return { kept, clamped: true }
}

// 개정 20 공용 업그레이드(성장). L → L+1 비용 = round(cost_base × cost_growth^L), L = 현재 레벨(0부터)
export interface UpgradeDef {
  id: string
  name: string
  per_level: number
  unit: string
  max_level: number
  cost_base: number
  cost_growth: number
}
export const UPGRADE_UNITS = ['pct', 'pp']
export const upgradeStepCost = (d: UpgradeDef, level: number) => roundHalfAway(Number(d.cost_base) * Number(d.cost_growth) ** level)
// level에서 count번 올리는 비용 합계
export function upgradeCost(d: UpgradeDef, level: number, count: number): number {
  let gold = 0
  for (let l = level; l < level + count; l++) gold += upgradeStepCost(d, l)
  return gold
}

// --- 던전·장비 (개정 18 §2~§5) — 앱 GameData(던전·장비 블록)와 같은 식 ---

export const DUNGEON_TYPES = ['gold', 'equip']
export const EQUIP_GRADES = ['N', 'R', 'SR', 'SSR', 'UR', 'LR'] // 낮은 등급부터. equip_drop.csv 가중치 열 = 이 이름
export const EQUIP_GRADE_MULT: Record<string, number> = { N: 1.0, R: 1.5, SR: 2.2, SSR: 3.2, UR: 4.6, LR: 6.5 }
export const ARMOR_SLOTS = ['hat', 'top', 'bottom', 'shoes', 'pauldron', 'gloves'] // 모든 영웅이 쓴다
export const EQUIP_SLOTS = ['weapon', ...ARMOR_SLOTS]
export const WEAPON_OF: Record<string, string> = { Knight: 'sword', Barbarian: 'axe', Mage: 'staff', Rogue_Hooded: 'crossbow', Rogue: 'dagger' } // 영웅 모델 → 무기 종류
export const WEAPON_KINDS = ['sword', 'axe', 'staff', 'crossbow', 'dagger']
// 부위 → [능력치, 1레벨 값, 레벨당 증가]. 값 = round((1레벨 + 레벨당 × (n − 1)) × 등급 배율)
export const SLOT_STAT: Record<string, [string, number, number]> = {
  weapon: ['atk', 12, 3], top: ['hp', 80, 20], bottom: ['hp', 80, 20], hat: ['hp', 50, 12], pauldron: ['hp', 50, 12], gloves: ['atk', 5, 1.2], shoes: ['hp', 40, 10],
}
export const SHOES_SPEED_PCT = 3 // 신발 이동속도 +3%(등급 무관)
export const RUN_TTL_SEC = 1800 // run 만료(30분)
export const RUN_SLACK_SEC = 5 // finish 타당성: 실제 경과 ≥ elapsed − 5
export const MAX_DUNGEON_LEVEL = 300 // 보상 골드 tenths가 bigint를 넘지 않게(4000 × 1.1^299 × 10 < 2^63)

export interface DungeonState {
  best_level: number
  keys: number
  extra_today: number // 그날 골드 추가 도전 횟수(장비 던전)
  last_reset: number // 마지막으로 반영한 리셋 시각(유닉스 초)
}

export interface DungeonDef {
  id: string
  type: string
  kind: string
  count: number
  delay: number
  hp: number
  atk: number
  speed: number
  range: number
  atk_interval: number
  aggro: number
  scale: number
}

export interface EquipItem {
  id?: number
  slot: string
  weapon_kind: string | null
  grade: string
  level: number
}

// 리셋 날짜 번호: 하루가 daily_reset_utc_hour시(UTC)에 시작한다(15 = 00:00 KST).
export const resetDay = (t: number, hour: number) => Math.floor((t - hour * 3600) / 86400)
export const resetAt = (day: number, hour: number) => day * 86400 + hour * 3600
export function nextReset(now: number, config: Config): number {
  const h = cfgNum(config, 'daily_reset_utc_hour')
  return resetAt(resetDay(now, h) + 1, h)
}

// 처음 보는 던전: 오늘 지급분(열쇠 = 하루 지급), 최고 단계 0.
export function freshDungeon(type: string, now: number, config: Config): DungeonState {
  const h = cfgNum(config, 'daily_reset_utc_hour')
  return { best_level: 0, keys: cfgNum(config, `${type}_key_daily`), extra_today: 0, last_reset: resetAt(resetDay(now, h), h) }
}

// 게으른 일일 리셋: 놓친 리셋 수 × 하루 지급을 상한까지 더하고(이미 상한 위면 그대로) 추가 도전 횟수를 0으로. 리셋이 없으면 그대로.
export function applyReset(type: string, d: DungeonState, now: number, config: Config): DungeonState {
  const h = cfgNum(config, 'daily_reset_utc_hour')
  const days = resetDay(now, h) - resetDay(d.last_reset, h)
  if (days <= 0) return d
  const cap = cfgNum(config, `${type}_key_cap`)
  const keys = Math.max(d.keys, Math.min(cap, d.keys + days * cfgNum(config, `${type}_key_daily`)))
  return { ...d, keys, extra_today: 0, last_reset: resetAt(resetDay(now, h), h) }
}

// 장비 던전 골드 추가 도전 비용 = equip_extra_gold_base × (1 + 그날 추가 도전 횟수).
export const extraCost = (config: Config, extraToday: number) => cfgNum(config, 'equip_extra_gold_base') * (1 + extraToday)
export const partySize = (config: Config, type: string) => cfgNum(config, `${type}_dg_party`)
export const minClearSecOf = (config: Config, type: string) => cfgNum(config, `${type}_dg_min_sec`)

// 골드 던전 보상(정수 골드) = round(gold_dg_base × gold_dg_mult^(n−1)).
export const goldReward = (config: Config, level: number) => roundHalfAway(grown(cfgNum(config, 'gold_dg_base'), cfgNum(config, 'gold_dg_mult'), level - 1))

// 적 능력치 성장: 골드 던전은 HP·공격 모두 gold_dg_growth, 장비 던전은 equip_dg_hp_growth·equip_dg_atk_growth.
export function dungeonGrowth(config: Config, type: string) {
  if (type === 'gold') return { hp: cfgNum(config, 'gold_dg_growth'), atk: cfgNum(config, 'gold_dg_growth') }
  return { hp: cfgNum(config, 'equip_dg_hp_growth'), atk: cfgNum(config, 'equip_dg_atk_growth') }
}

// 단계 n의 적 목록(표 순서): HP·공격 = 기본 × 성장^(n−1)(곱셈 n−1번), 나머지는 표 그대로.
export function dungeonEnemies(defs: DungeonDef[], type: string, level: number, config: Config) {
  const g = dungeonGrowth(config, type)
  return defs.filter((d) => d.type === type).map((d) => ({
    id: d.id, kind: d.kind, count: Number(d.count), delay: Number(d.delay), hp: grown(Number(d.hp), g.hp, level - 1), atk: grown(Number(d.atk), g.atk, level - 1),
    speed: Number(d.speed), range: Number(d.range), atk_interval: Number(d.atk_interval), aggro: Number(d.aggro), scale: Number(d.scale),
  }))
}

// 단계 n의 등급 가중치(equip_drop.csv의 min_level ≤ n인 마지막 행) — EQUIP_GRADES 순서.
export function dropWeights(rows: Record<string, unknown>[], level: number): number[] {
  let row = rows[0]
  for (const r of rows) if (Number(r.min_level) <= level) row = r
  return EQUIP_GRADES.map((g) => Number(row?.[g] ?? 0))
}

// 장비 count개(서버는 암호학적 난수). 장마다: 부위(무기 equip_weapon_p, 아니면 방어구 6부위 균등) → 무기면 종류 균등 → 등급(가중치).
export function rollDrops(rows: Record<string, unknown>[], level: number, count: number, weaponP: number, rand: () => number): EquipItem[] {
  const w = dropWeights(rows, level)
  const total = w.reduce((s, x) => s + x, 0)
  const pickIdx = (n: number) => Math.min(Math.floor(rand() * n), n - 1)
  const out: EquipItem[] = []
  for (let i = 0; i < count; i++) {
    const weapon = rand() < weaponP
    const slot = weapon ? 'weapon' : ARMOR_SLOTS[pickIdx(ARMOR_SLOTS.length)]
    const weapon_kind = weapon ? WEAPON_KINDS[pickIdx(WEAPON_KINDS.length)] : null
    let pick = rand() * total
    let grade = EQUIP_GRADES[0]
    for (let g = 0; g < EQUIP_GRADES.length; g++) {
      if (w[g] <= 0) continue
      grade = EQUIP_GRADES[g]
      pick -= w[g]
      if (pick < 0) break
    }
    out.push({ slot, weapon_kind, grade, level })
  }
  return out
}

// 장비 능력치 {hp, atk, speed_pct}.
export function itemStats(item: EquipItem) {
  const out = { hp: 0, atk: 0, speed_pct: 0 }
  const s = SLOT_STAT[item.slot]
  if (!s) return out
  out[s[0] as 'hp' | 'atk'] = roundHalfAway((s[1] + s[2] * (item.level - 1)) * (EQUIP_GRADE_MULT[item.grade] ?? 0))
  if (item.slot === 'shoes') out.speed_pct = SHOES_SPEED_PCT
  return out
}

// 판매 값 = round(equip_sell_base × 등급 배율 × 레벨).
export const itemSellValue = (config: Config, item: EquipItem) => roundHalfAway(cfgNum(config, 'equip_sell_base') * (EQUIP_GRADE_MULT[item.grade] ?? 0) * item.level)

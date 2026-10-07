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

// 무료 즉시 완료(사용자 2026-10-06): 남은 시간이 free_finish_sec초(기본 300) 이하인 건설·훈련·연구는 공짜로 바로 끝낸다.
// 앱 시계와 서버 시계 차이만큼 FREE_FINISH_SLACK초를 더 봐준다. 시드 전 설정에 키가 없으면 300.
export const FREE_FINISH_SLACK = 10
export function freeFinishSec(config: Config): number {
  return config.free_finish_sec === undefined || config.free_finish_sec.trim() === '' ? 300 : cfgNum(config, 'free_finish_sec')
}
export const freeFinishOk = (config: Config, finish: number, now: number) => finish - now <= freeFinishSec(config) + FREE_FINISH_SLACK

// Godot roundi와 같게 .5는 0에서 먼 쪽으로.
export const roundHalfAway = (v: number) => Math.sign(v) * Math.round(Math.abs(v))

// --- 축적과 수집 (개정 7 §2) ---

// 쌓인 양 = floor(min(경과, 상한)/60) × 분당 생산. 분당 생산 = floor(분당 × 레벨 × (100 + pct) / 100)(pct = 연구 생산 %, 개정 24).
// 경과가 0 이하면 0.
export function pendingAmount(perMin: number, level: number, elapsedSec: number, capMin: number, pct = 0): number {
  if (elapsedSec <= 0) return 0
  return Math.floor(Math.min(elapsedSec, capMin * 60) / 60) * Math.floor(perMin * level * (100 + pct) / 100)
}

// 수집 한 번: 상한 미만이면 수집한 분만큼만 옮기고(남은 초 유지), 상한이면 지금으로, 경과가 음수면 지금으로(수집 0).
// 쌓인 양이 0이면 changed = false(아무것도 안 바뀜).
export function collectStep(lastCollect: number, now: number, perMin: number, level: number, capMin: number, pct = 0) {
  if (now < lastCollect) return { amount: 0, lastCollect: now, changed: true }
  const elapsed = now - lastCollect
  const amount = pendingAmount(perMin, level, elapsed, capMin, pct)
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

// 처치 골드 배율은 지수 곡선(2026-10-07 사용자): (1 + 0.2 × (n − 1)) × 1.01^(n − 1). 표(stages.csv gold_mult)가 이 값이고, 표를 넘으면 같은 곡선으로
// 잇는다(마지막 행 기준 비율), 상한 GOLD_MULT_MAX. 앱 GameData.gold_mult_beyond와 같다.
export const GOLD_LINEAR = 0.2
export const GOLD_GROWTH = 1.01
export const GOLD_MULT_MAX = 1e8
export const goldMultBeyond = (n: number, lastMult: number, rows: number) => rows <= 1 ? lastMult :
  Math.min(lastMult * ((1 + GOLD_LINEAR * (n - 1)) / (1 + GOLD_LINEAR * (rows - 1))) * GOLD_GROWTH ** (n - rows), GOLD_MULT_MAX)

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
  out.gold_mult = goldMultBeyond(n, last.gold_mult, rows.length)
  return out
}

// 처치 골드(tenths, 0.1 단위 정수) = max(1, round(gold × gold_mult × 10)). 앱 GameData.kill_gold_tenths와 같은 식.
export function killGoldTenths(monsterGold: number, stage: StageRow): number {
  return Math.max(1, roundHalfAway(monsterGold * stage.gold_mult * 10))
}

// 오프라인 처치 골드(앱을 끈 동안의 방치 처치, 앱 Economy.offline_reward와 같은 식). 방치 스폰(WaveDirector MODE_IDLE: idle_interval초마다
// 네 면에 spawn_group마리씩, 전부 grunt)을 모두 잡았다고 본다. 초 = min(away, capMin분), OFFLINE_MIN_SEC 미만이면 0.
// 처치 = floor(초 × 4 × group / idleInterval), 골드 tenths = floor(처치 × 1회 tenths × mult).
export const OFFLINE_MIN_SEC = 60
export const OFFLINE_KIND = 'grunt'
export function offlineReward(awaySec: number, capMin: number, idleInterval: number, group: number, perKillTenths: number, mult: number) {
  const sec = Math.min(Math.max(0, awaySec), capMin * 60)
  if (!(sec >= OFFLINE_MIN_SEC) || !(idleInterval > 0)) return { sec: Math.max(0, sec), kills: 0, tenths: 0 }
  const kills = Math.floor(sec * 4 * Math.max(1, Math.round(group)) / idleInterval)
  return { sec, kills, tenths: Math.floor(kills * perKillTenths * Math.max(0, mult)) }
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
export const LAB = 'lab' // 연구 잠금·속도(개정 24)

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

// n마리 비용 {자원: 수} = 1마리 비용 × train_cost_tier_mult^(tier−1) × n(개정 19). 개정 24: 연구 할인 pct% —
// 자원마다 round(v × (100 − pct) / 100)(0 이상), 0인 자원은 뺀다.
export function trainCost(config: Config, type: string, n: number, tier = 1, pct = 0): Record<string, number> {
  const one = parseTrainCost(config[`train_cost_${type}`] ?? '')
  if (!one) throw new Error(`config 'train_cost_${type}' is missing or not 'res:amount|…'`)
  const m = cfgNum(config, 'train_cost_tier_mult') ** (tier - 1)
  return Object.fromEntries(Object.entries(one).map(([r, v]) => [r, Math.max(0, roundHalfAway(v * m * n * (100 - pct) / 100))]).filter(([, v]) => v > 0))
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
export const GACHA_TICKET = 'ticket' // 다이아 모집권(튜토리얼 보상): 다이아 모집 1회 = 1장
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

export const LEVELUP_GOLD_GROWTH = 1.16 // 2026-10-07 1.12 → 1.16(초반은 비슷, 후반 골드 소비 상향). 앱 GameData와 같다

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

export const DUNGEON_TYPES = ['gold', 'equip', 'ticket'] // ticket = 모집권 던전(2026-10-06): 내 영웅 4 + 도우미 영웅 1, 보상 다이아 모집권
export const EQUIP_GRADES = ['N', 'R', 'SR', 'SSR', 'UR', 'LR'] // 낮은 등급부터. equip_drop.csv 가중치 열 = 이 이름
export const EQUIP_GRADE_MULT: Record<string, number> = { N: 1.0, R: 1.5, SR: 2.2, SSR: 3.2, UR: 4.6, LR: 6.5 }
export const ARMOR_SLOTS = ['hat', 'top', 'bottom', 'shoes', 'pauldron', 'gloves'] // 모든 영웅이 쓴다
export const EQUIP_SLOTS = ['weapon', ...ARMOR_SLOTS]
export const WEAPON_OF: Record<string, string> = { Knight: 'sword', Barbarian: 'axe', Mage: 'staff', Rogue_Hooded: 'crossbow', Rogue: 'dagger' } // 영웅 모델 → 무기 종류
export const WEAPON_KINDS = ['sword', 'axe', 'staff', 'crossbow', 'dagger']
// 부위 → [능력치, 기준값]. 2026-10-07 장비 레벨 없앰: 기준값 = 예전 Lv 10 값(반올림). 실제 값 = round(기준값 × 등급 배율 × 굴림 % / 100)
export const SLOT_STAT: Record<string, [string, number]> = {
  weapon: ['atk', 20], top: ['hp', 130], bottom: ['hp', 130], hat: ['hp', 80], pauldron: ['hp', 80], gloves: ['atk', 8], shoes: ['hp', 65],
}
export const SHOES_SPEED_PCT = 3 // 신발 이동속도 기준 +3%(등급 무관, 굴림은 적용)
// 능력치마다 따로 굴리는 배율(정수 %): 85~115. 저장은 rolls {hp|atk|speed_pct: %}, 없으면 100(기준값)
export const ROLL_MIN = 85
export const ROLL_MAX = 115
// 특수 능력치(SR 이상): 줄 수 SR·SSR 1, UR 2, LR 3(서로 다른 종류). 값 = 등급 기준값 × 굴림 % / 100(%, 소수 한 자리)
export const SUB_STATS = ['lifesteal', 'crit_rate', 'crit_dmg', 'aspd', 'dmg_reduce', 'skill_dmg']
export const SUB_COUNT: Record<string, number> = { SR: 1, SSR: 1, UR: 2, LR: 3 }
export const SUB_BASE: Record<string, Record<string, number>> = {
  lifesteal: { SR: 2, SSR: 3, UR: 4.5, LR: 6 }, crit_rate: { SR: 2, SSR: 3, UR: 4.5, LR: 6 }, crit_dmg: { SR: 6, SSR: 9, UR: 13, LR: 18 },
  aspd: { SR: 2, SSR: 3, UR: 4.5, LR: 6 }, dmg_reduce: { SR: 2, SSR: 3, UR: 4.5, LR: 6 }, skill_dmg: { SR: 4, SSR: 6, UR: 9, LR: 12 },
}
export const RUN_TTL_SEC = 1800 // run 만료(30분)
export const RUN_SLACK_SEC = 5 // finish 타당성: 실제 경과 ≥ elapsed ÷ MAX_GAME_SPEED − 5
// 앱 x1.5 배속 버튼(2026-10-07): 전투 시간(게임 초)은 실제 초의 이 배수까지 빨리 갈 수 있다. 전투 길이·제한 시간은 게임 초 그대로,
// 실제 경과와 견주는 검사(던전 finish·PVP 최소 승리·드래곤 too_early)만 이 배수로 나눈다. 앱 speed_button.gd SPEED와 같다.
export const MAX_GAME_SPEED = 1.5
export const MAX_DUNGEON_LEVEL = 300 // 보상 골드 tenths가 bigint를 넘지 않게(4000 × 1.1^299 × 10 < 2^63)

export interface DungeonState {
  best_level: number
  keys: number
  extra_today: number // 그날 골드 추가 도전 횟수(장비 던전)
  last_reset: number // 마지막으로 반영한 리셋 시각(유닉스 초)
  helpers_used?: string[] // 모집권 던전: 오늘 클리어에 쓴 도우미 영웅 id(그날은 다시 못 쓴다, 리셋 때 비운다)
}

// 모집권 던전 도우미(친구 목록이 없어 시스템이 고른 영웅): 그 영웅·레벨·승급(장비 없음)
export interface Helper {
  hero_id: string
  level: number
  promotion: number
  power: number
  key?: string // 고를 때 쓰는 값: 시스템 후보 = 영웅 id, 친구 = "f:<친구 id>"(오늘 쓴 목록 helpers_used에도 이 값이 들어간다)
  friend?: { id: string; name: string } // 친구 영웅이면 그 친구
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

export interface EquipSub {
  id: string
  r: number
}

export interface EquipItem {
  id?: number
  slot: string
  weapon_kind: string | null
  grade: string
  rolls?: Record<string, number> // 능력치 → 굴림 %(85~115). 없는 키는 100
  subs?: EquipSub[] // 특수 능력치(SR 이상)
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
  return { ...d, keys, extra_today: 0, last_reset: resetAt(resetDay(now, h), h), ...(d.helpers_used ? { helpers_used: [] } : {}) }
}

// 장비 던전 골드 추가 도전 비용 = equip_extra_gold_base × (1 + 2 × 그날 추가 도전 횟수)(2026-10-07: 10만·30만·50만·70만…).
export const extraCost = (config: Config, extraToday: number) => cfgNum(config, 'equip_extra_gold_base') * (1 + 2 * Math.max(extraToday, 0))
export const partySize = (config: Config, type: string) => cfgNum(config, `${type}_dg_party`)
export const minClearSecOf = (config: Config, type: string) => cfgNum(config, `${type}_dg_min_sec`)

// 골드 던전 보상(정수 골드) = round(gold_dg_base × gold_dg_mult^(n−1)).
export const goldReward = (config: Config, level: number) => roundHalfAway(grown(cfgNum(config, 'gold_dg_base'), cfgNum(config, 'gold_dg_mult'), level - 1))

// 적 능력치 성장: 골드 던전은 HP·공격 모두 gold_dg_growth, 장비·모집권 던전은 <종류>_dg_hp_growth·<종류>_dg_atk_growth.
export function dungeonGrowth(config: Config, type: string) {
  if (type === 'gold') return { hp: cfgNum(config, 'gold_dg_growth'), atk: cfgNum(config, 'gold_dg_growth') }
  return { hp: cfgNum(config, `${type}_dg_hp_growth`), atk: cfgNum(config, `${type}_dg_atk_growth`) }
}

// 모집권 던전 보상(다이아 모집권 장수) = ticket_reward_base + floor((n − 1) / ticket_reward_step) × ticket_reward_add
// (사용자 2026-10-06: 10장, 5단계마다 2장씩 — 1~5단계 10, 6~10단계 12 …). ticket_reward_add가 없으면(시드 전) 1.
export const ticketReward = (config: Config, level: number) =>
  cfgNum(config, 'ticket_reward_base') + Math.floor((level - 1) / Math.max(1, cfgNum(config, 'ticket_reward_step'))) * (config.ticket_reward_add == null ? 1 : cfgNum(config, 'ticket_reward_add'))

// --- 영웅 전투력 — 앱 GameData.hero_stats·hero_power와 같은 식(모집권 던전 도우미 고르기에만 쓴다) ---
export const levelMult = (config: Config, level: number, role: string) =>
  1 + cfgNum(config, role === 'melee' ? 'hero_level_stat_melee' : 'hero_level_stat') * (level - 1)
export const promoteMult = (config: Config, promotion: number) => grown(1, cfgNum(config, 'promote_mult'), Math.min(Math.max(promotion, 0), MAX_PROMOTION))
// 전투력 = round((HP / 10 + 공격 × 2 / 공격 간격 × 원거리 배율) × 등급 배율), HP·공격 = 표 × 레벨 배율 × 승급 배율 + 장비.
// 2026-10-06 밸런스(앱 GameData.POWER_GRADE·POWER_RANGED와 같다): 같은 레벨·승급·장비면 SSR > SR > R.
export const POWER_GRADE: Record<string, number> = { SSR: 2.0, SR: 1.4, R: 1.0 }
export const POWER_RANGED = 2.0
export const powerOf = (def: { role?: unknown; grade?: unknown; atk_interval: unknown }, hp: number, atk: number) =>
  roundHalfAway((hp / 10 + ((atk * 2) / Number(def.atk_interval)) * (String(def.role ?? '') === 'ranged' ? POWER_RANGED : 1)) * (POWER_GRADE[String(def.grade ?? '')] ?? 1))
export function heroPower(def: Record<string, any>, level: number, promotion: number, equip: { hp: number; atk: number }, config: Config): number {
  const m = levelMult(config, level, String(def.role ?? '')) * promoteMult(config, promotion)
  return powerOf(def, Number(def.hp) * m + equip.hp, Number(def.atk) * m + equip.atk)
}

// FNV-1a 32비트(도우미 순서 섞기 — 앱 GameData.fnv32와 같다).
export function fnv32(s: string): number {
  let h = 0x811c9dc5
  for (const b of new TextEncoder().encode(s)) h = Math.imul(h ^ b, 0x01000193) >>> 0
  return h
}

export const HELPER_COUNT = 3
export const HELPER_FIT = 0.1 // 도우미 전투력이 기준 ±10% 안이면 "적당한 스펙"

// 모집권 던전 도우미 후보 3명(친구 목록이 없을 때 시스템이 고른다, 앱 GameData.helper_candidates와 같은 규칙):
// 기준 전투력 = 내 영웅 전투력(장비 포함) 상위 4명 평균, 승급 = 그 4명 승급 평균(반올림). 영웅 표에서 오늘 쓴 영웅을 빼고
// fnv32("<key>:<리셋 날짜>:<영웅 id>") 순으로 보며, 영웅마다 기준에 가장 가까운 레벨(1..최대, 같으면 낮은 레벨)을 고른다.
// 기준 ±10% 안인 영웅을 앞에서부터 3명, 모자라면 나머지에서 가까운 순으로 채운다. owned = [{def, level, promotion, equip}].
export function helperCandidates(heroDefs: Record<string, any>[], owned: { def: Record<string, any>; level: number; promotion: number; equip: { hp: number; atk: number } }[],
  used: string[], key: string, day: number, config: Config): Helper[] {
  const top = owned.map((o) => ({ power: heroPower(o.def, o.level, o.promotion, o.equip, config), promotion: o.promotion }))
    .sort((a, b) => b.power - a.power).slice(0, 4)
  const ref = top.length ? top.reduce((s, x) => s + x.power, 0) / top.length : 0
  const promotion = top.length ? Math.round(top.reduce((s, x) => s + x.promotion, 0) / top.length) : 0
  const maxLv = heroMaxLevel(promotion, config)
  const pool = heroDefs.filter((d) => !used.includes(String(d.id)))
    .map((d) => ({ d, h: fnv32(`${key}:${day}:${d.id}`) })).sort((a, b) => a.h - b.h || (String(a.d.id) < String(b.d.id) ? -1 : 1))
  const picks = pool.map(({ d }) => {
    let best = { level: 1, power: heroPower(d, 1, promotion, { hp: 0, atk: 0 }, config) }
    for (let l = 2; l <= maxLv; l++) {
      const pw = heroPower(d, l, promotion, { hp: 0, atk: 0 }, config)
      if (Math.abs(pw - ref) < Math.abs(best.power - ref)) best = { level: l, power: pw }
      if (pw > ref) break // 레벨이 오를수록 커진다
    }
    return { hero_id: String(d.id), level: best.level, promotion, power: best.power, diff: Math.abs(best.power - ref) / Math.max(ref, 1) }
  })
  const out = picks.filter((x) => x.diff <= HELPER_FIT).slice(0, HELPER_COUNT)
  if (out.length < HELPER_COUNT) out.push(...picks.filter((x) => !out.includes(x)).sort((a, b) => a.diff - b.diff).slice(0, HELPER_COUNT - out.length))
  return out.map(({ hero_id, level, promotion: pr, power }) => ({ hero_id, level, promotion: pr, power }))
}

// --- 친구(2026-10-06) ---

export const FRIEND_CAP = 30 // 친구 + 보낸 신청 상한
export const FRIEND_RECOMMEND = 5 // 추천 친구 수(최근 3일 안에 접속한 다른 플레이어)
export const FRIEND_RECENT_SEC = 3 * 86400

// 플레이어 이름: id(uuid)에서 정해지는 별명(같은 id면 늘 같다 — 길드 guild.ts playerName과 같은 규칙·같은 낱말).
const NICK_A = ['졸린', '용감한', '배고픈', '빠른', '느긋한', '씩씩한', '조용한', '화난', '행복한', '수상한', '귀여운', '우직한', '새침한', '엉뚱한']
const NICK_B = ['감자', '고양이', '기사', '궁수', '곰', '여우', '도토리', '망치', '방패', '늑대', '토끼', '수염', '마법사', '호박']

function mixName(...xs: number[]): number {
  let h = 0x811c9dc5
  for (const x of xs) {
    h = Math.imul(h ^ (x >>> 0), 0x01000193) >>> 0
    h = Math.imul(h ^ (h >>> 15), 0x2c1b3c6d) >>> 0
  }
  return h >>> 0
}

export function friendName(id: string): string {
  const hex = id.replace(/-/g, '')
  const r = mulberry32(mixName(parseInt(hex.slice(0, 8), 16), parseInt(hex.slice(8, 16), 16)))
  const pick = (a: string[]) => a[Math.floor(r() * a.length)]
  let s = pick(NICK_A) + pick(NICK_B)
  if (r() < 0.4) s += String(1 + Math.floor(r() * 99))
  return s
}

export const friendCode = (id: string) => id.replace(/-/g, '').slice(0, 8).toUpperCase()

// 친구가 빌려주는 영웅: 고른 대표 영웅(가지고 있을 때), 아니면 전투력이 가장 높은 영웅(같으면 id 순 앞). 장비는 빼고 센다
// (도우미는 장비 없이 싸운다). heroes = 영웅 id → {level, promotion}. 영웅이 없으면 null.
export function lentHero(heroDefs: Record<string, any>[], chosen: string | null, heroes: Record<string, { level: number; promotion: number }>,
  config: Config): Helper | null {
  const defs = new Map(heroDefs.map((d) => [String(d.id), d]))
  const of = (id: string) => {
    const h = heroes[id]
    return { hero_id: id, level: Number(h.level), promotion: Number(h.promotion), power: heroPower(defs.get(id)!, Number(h.level), Number(h.promotion), { hp: 0, atk: 0 }, config) }
  }
  const ids = Object.keys(heroes).filter((id) => defs.has(id)).sort()
  if (chosen && ids.includes(chosen)) return of(chosen)
  let best: Helper | null = null
  for (const id of ids) {
    const h = of(id)
    if (!best || h.power > best.power) best = h
  }
  return best
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

// 장비 count개(서버는 암호학적 난수). 장마다: 부위(무기 equip_weapon_p, 아니면 방어구 6부위 균등) → 무기면 종류 균등 → 등급(가중치)
// → 기본 능력치 굴림(부위 능력치, 신발은 이어서 이동속도) → 특수 능력치(SUB_COUNT줄, 남은 종류에서 균등 → 굴림). level은 등급 가중치에만 쓴다.
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
    out.push(rollItem(slot, weapon_kind, grade, rand))
  }
  return out
}

// 부위·등급이 정해진 장비 하나의 굴림(rollDrops 뒤 절반, 앱 GameData.roll_item과 같은 순서).
export function rollItem(slot: string, weapon_kind: string | null, grade: string, rand: () => number): EquipItem {
  const roll = () => ROLL_MIN + Math.min(Math.floor(rand() * (ROLL_MAX - ROLL_MIN + 1)), ROLL_MAX - ROLL_MIN)
  const rolls: Record<string, number> = {}
  rolls[SLOT_STAT[slot][0]] = roll()
  if (slot === 'shoes') rolls.speed_pct = roll()
  const pool = [...SUB_STATS]
  const subs: EquipSub[] = []
  for (let k = 0; k < (SUB_COUNT[grade] ?? 0); k++) {
    const id = pool.splice(Math.min(Math.floor(rand() * pool.length), pool.length - 1), 1)[0]
    subs.push({ id, r: roll() })
  }
  return { slot, weapon_kind, grade, rolls, subs }
}

const rollOf = (item: EquipItem, k: string) => {
  const r = Number(item.rolls?.[k])
  return Number.isFinite(r) ? r : 100
}

// 장비 능력치 {hp, atk, speed_pct}(기본 능력치만 — 특수 능력치는 전투가 쓰고 전투력엔 넣지 않는다).
export function itemStats(item: EquipItem) {
  const out = { hp: 0, atk: 0, speed_pct: 0 }
  const s = SLOT_STAT[item.slot]
  if (!s) return out
  out[s[0] as 'hp' | 'atk'] = roundHalfAway((s[1] * (EQUIP_GRADE_MULT[item.grade] ?? 0) * rollOf(item, s[0])) / 100)
  if (item.slot === 'shoes') out.speed_pct = Math.round(SHOES_SPEED_PCT * rollOf(item, 'speed_pct')) / 100
  return out
}

// 굴림·특수 능력치 검사(저장된 값이 틀리면 버린다): rolls는 그 부위 능력치만 85~115 정수, subs는 그 등급 줄 수 이하의 서로 다른 종류.
export function cleanRolls(slot: string, grade: string, rolls: unknown, subs: unknown): { rolls: Record<string, number>; subs: EquipSub[] } {
  const ok = (r: unknown) => Number.isInteger(r) && (r as number) >= ROLL_MIN && (r as number) <= ROLL_MAX
  const keys = SLOT_STAT[slot] ? [SLOT_STAT[slot][0], ...(slot === 'shoes' ? ['speed_pct'] : [])] : []
  const src = (rolls && typeof rolls === 'object' ? rolls : {}) as Record<string, unknown>
  const outRolls: Record<string, number> = {}
  for (const k of keys) if (ok(src[k])) outRolls[k] = src[k] as number
  const outSubs: EquipSub[] = []
  for (const x of Array.isArray(subs) ? subs : []) {
    if (outSubs.length >= (SUB_COUNT[grade] ?? 0)) break
    if (x && SUB_STATS.includes(x.id) && ok(x.r) && !outSubs.some((y) => y.id === x.id)) outSubs.push({ id: x.id, r: x.r })
  }
  return { rolls: outRolls, subs: outSubs }
}

// 영웅 id → 장착 장비 합계 {hp, atk}(전투력용 — 앱 Economy.equipment_bonus와 같다). equipment = [{hero_id, item_id}].
export function heroEquip(items: EquipItem[], equipment: { hero_id: string; item_id: number }[]): Record<string, { hp: number; atk: number }> {
  const byId = new Map(items.map((it) => [Number(it.id), it]))
  const out: Record<string, { hp: number; atk: number }> = {}
  for (const e of equipment) {
    const it = byId.get(Number(e.item_id))
    if (!it) continue
    const s = itemStats(it)
    const o = (out[e.hero_id] ??= { hp: 0, atk: 0 })
    o.hp += s.hp
    o.atk += s.atk
  }
  return out
}

// 앱이 보낸 영웅 능력치(PVP 방어팀·길드전 수비)를 믿을 상한의 근거(2026-10-07): 영웅별 장비 {hp, atk} + 내 성장·연구·길드 배율.
// 앱 GuildWar.hero_entry = (기본 × 레벨 × 승급 + 장비) × (1 + 성장 %) × (1 + 연구 %) × (1 + 길드 %)와 같은 식.
export interface StatLimit { equip: Record<string, { hp: number; atk: number }>; hp: number; atk: number }
export function statLimit(pl: { upgrades: Record<string, number>; research: Record<string, number>; items: EquipItem[]; equipment: { hero_id: string; item_id: number }[] },
  game: { upgrades: UpgradeDef[]; research: ResearchDef[] }, guildBuffPct: number): StatLimit {
  const up = (id: string) => {
    const d = game.upgrades.find((u) => u.id === id)
    return d ? (Math.min(Math.max(pl.upgrades[id] ?? 0, 0), Number(d.max_level)) * Number(d.per_level)) / 100 : 0
  }
  const rb = researchBonus(game.research, pl.research ?? {})
  const g = 1 + Math.max(0, guildBuffPct) / 100
  return { equip: heroEquip(pl.items ?? [], pl.equipment ?? []), hp: (1 + up('hp')) * (1 + rb.hero_hp_pct / 100) * g, atk: (1 + up('atk')) * (1 + rb.hero_atk_pct / 100) * g }
}

// 판매 값 = round(equip_sell_base × 등급 배율)(2026-10-07 장비 레벨 없앰).
export const itemSellValue = (config: Config, item: EquipItem) => roundHalfAway(cfgNum(config, 'equip_sell_base') * (EQUIP_GRADE_MULT[item.grade] ?? 0))

// --- 연구 테크트리 (개정 24) — 앱 GameData.research_*와 같은 식 ---

export const RESEARCH_BRANCHES = ['economy', 'military', 'hero']
export const RESEARCH_EFFECTS = ['wood_pct', 'stone_pct', 'food_pct', 'res_pct', 'build_speed_pct', 'research_speed_pct', 'sell_pct', 'kill_gold_pct',
  'inf_pct', 'arc_pct', 'cav_pct', 'soldier_pct', 'castle_hp_pct', 'gate_hp_pct', 'train_speed_pct', 'train_cost_pct', 'pop_add',
  'hero_atk_pct', 'hero_hp_pct', 'skill_pct']
export const RESEARCH_RES = ['wood', 'stone', 'food', 'gold'] // 비용 열(골드는 정수 골드)

export interface ResearchDef {
  id: string
  branch: string
  tier: number
  name: string
  effect: string
  per_level: number
  max_level: number
  lab_req: number
  req1: string | null
  req1_lv: number | null
  req2: string | null
  req2_lv: number | null
  wood: number
  stone: number
  food: number
  gold: number
  base_sec: number
}

// 효과 합계 {effect: 합}(모든 키, 없으면 0). 노드마다(표 순서) 레벨(0..max_level로 자름) × per_level을 더한다. % 단위, pop_add는 명.
export function researchBonus(defs: ResearchDef[], levels: Record<string, number>): Record<string, number> {
  const out: Record<string, number> = Object.fromEntries(RESEARCH_EFFECTS.map((e) => [e, 0]))
  for (const d of defs) {
    const lv = Math.min(Math.max(levels[d.id] ?? 0, 0), d.max_level)
    out[d.effect] += lv * d.per_level
  }
  return out
}

// n → n+1 비용(n = 현재 레벨, 0부터) {wood, stone, food, gold} = round(값 × research_cost_growth^n).
export function researchCost(config: Config, def: ResearchDef, n: number): Record<string, number> {
  const g = cfgNum(config, 'research_cost_growth')
  return Object.fromEntries(RESEARCH_RES.map((r) => [r, roundHalfAway(grown(Number(def[r as 'wood']), g, n))]))
}

// 연구 속도 = research_speed_pct / 100 + lab_research_speed_per_level × (연구소 − 1).
export const researchSpeed = (config: Config, bonus: Record<string, number>, labLevel: number) =>
  bonus.research_speed_pct / 100 + cfgNum(config, 'lab_research_speed_per_level') * (Math.max(labLevel, 1) - 1)

// n → n+1 시간(초) = round(base_sec × research_time_growth^n / (1 + 속도)).
export const researchSec = (config: Config, def: ResearchDef, n: number, speed: number) =>
  roundHalfAway(grown(Number(def.base_sec), cfgNum(config, 'research_time_growth'), n) / (1 + speed))

// 연구를 못 하는 이유(앱 GameData.research_block과 같은 순서·코드). 되면 ''. 진행 중(research_busy)은 부르는 쪽이 먼저 본다.
// 최대 레벨(max_level) → 연구소·선행(locked) → 자원(not_enough_resources) → 골드(not_enough_gold). have.gold = 정수 골드.
export function researchBlock(def: ResearchDef, levels: Record<string, number>, labLevel: number, have: Record<string, number>, config: Config): string {
  const n = levels[def.id] ?? 0
  if (n >= def.max_level) return 'max_level'
  const reqs: [string | null, number | null][] = [[def.req1, def.req1_lv], [def.req2, def.req2_lv]]
  if (labLevel < def.lab_req || reqs.some(([id, lv]) => id && (levels[id] ?? 0) < Number(lv))) return 'locked'
  const cost = researchCost(config, def, n)
  if (BUILD_RES.some((r) => (have[r] ?? 0) < cost[r])) return 'not_enough_resources'
  if ((have.gold ?? 0) < cost.gold) return 'not_enough_gold'
  return ''
}

// 취소 환불 = 그 레벨 비용 × research_cancel_refund(자원·골드마다 내림).
export const researchRefund = (config: Config, cost: Record<string, number>) =>
  Object.fromEntries(Object.entries(cost).map(([r, v]) => [r, Math.floor(v * cfgNum(config, 'research_cancel_refund'))]))

// 다이아 즉시 완료 = max(1, ceil(남은 초 / 60) × research_dia_per_min).
export const researchDiaCost = (config: Config, finish: number, now: number) =>
  Math.max(1, Math.ceil((finish - now) / 60) * cfgNum(config, 'research_dia_per_min'))

// 자원 생산 % = 그 자원 % + res_pct(pendingAmount의 pct).
export const researchProdPct = (bonus: Record<string, number>, resId: string) => (bonus[`${resId}_pct`] ?? 0) + bonus.res_pct

// --- 튜토리얼·반복 퀘스트(data/quests.csv) — 앱 tutorial.gd의 보상 규칙을 표로 옮긴 것 ---

export const QUEST_TYPES = ['tutorial', 'repeat']
export const TUT_STATES = ['active', 'done', 'skipped']
// 보상 키: 자원(BUILD_RES)·gold·diamonds·tickets(다이아 모집권)·keys_<던전 종류>
export const QUEST_REWARD_KEYS = [...BUILD_RES, 'gold', 'diamonds', 'tickets', ...DUNGEON_TYPES.map((t) => `keys_${t}`)]
export const TUTORIAL_START_BUILT = [KEEP, GATE] // 새 플레이어(튜토리얼)에 지어져 있는 건물 — 나머지는 공터

export interface QuestDef {
  id: string
  type: string
  needs: string | null
  reward: string | null
  fixed: string | null
}

// "키:수|…" → {키: 수}(빈칸·null이면 {}). 모르는 키·중복·음수·정수 아님이면 null.
export function parseReward(text: string | null | undefined): Record<string, number> | null {
  const out: Record<string, number> = {}
  if (text == null || String(text).trim() === '') return out
  for (const part of String(text).split('|')) {
    const m = /^\s*([a-z_]+)\s*:\s*(\d+)\s*$/.exec(part)
    if (!m || !QUEST_REWARD_KEYS.includes(m[1]) || Object.hasOwn(out, m[1])) return null
    out[m[1]] = Number(m[2])
  }
  return out
}

// needs 형식: 빈칸 | build:<건물> | level:<건물>:<Lv ≥ 1>. 아니면 null, 맞으면 {kind, building, level}.
export function parseNeeds(text: string | null | undefined): { kind: string; building: string; level: number } | null | undefined {
  if (text == null || String(text).trim() === '') return undefined
  const b = /^build:([a-z_]+)$/.exec(String(text).trim())
  if (b) return { kind: 'build', building: b[1], level: 1 }
  const l = /^level:([a-z_]+):(\d+)$/.exec(String(text).trim())
  if (l && Number(l[2]) >= 1) return { kind: 'level', building: l[1], level: Number(l[2]) }
  return null
}

// 반복 퀘스트 n(0부터)의 정의·바퀴: 표의 repeat 행을 순서대로 돈다. 바퀴 c = floor(n / 행 수).
export function repeatQuest(defs: QuestDef[], n: number): { def: QuestDef; cycle: number } | null {
  const rows = defs.filter((d) => d.type === 'repeat')
  if (!rows.length) return null
  return { def: rows[n % rows.length], cycle: Math.floor(n / rows.length) }
}

// 반복 퀘스트 보상 = reward × (1 + 바퀴) + fixed(앱 Tutorial.repeat_reward와 같다).
export function repeatReward(def: QuestDef, cycle: number): Record<string, number> {
  const out: Record<string, number> = {}
  for (const [k, v] of Object.entries(parseReward(def.reward) ?? {})) out[k] = v * (1 + cycle)
  for (const [k, v] of Object.entries(parseReward(def.fixed) ?? {})) out[k] = (out[k] ?? 0) + v
  return out
}

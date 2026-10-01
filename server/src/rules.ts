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

// --- 병사 (개정 13) — 앱 GameData.soldier_unit_sec·Economy.prod_step·auto_deploy와 같은 식 ---

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

// 한 마리 시간(초) = soldier_prod_sec × soldier_prod_level_factor^(L−1)(곱셈 n번 — 앱과 같은 반올림 없는 값).
export const soldierUnitSec = (config: Config, level: number) =>
  grown(cfgNum(config, 'soldier_prod_sec'), cfgNum(config, 'soldier_prod_level_factor'), Math.max(level, 1) - 1)

// 게으른 생산 한 번: 지난 시간(축적 상한 capMin분까지) / 한 마리 시간만큼 만들고, 남은 시간은 유지(상한이면 지금으로).
// 시계가 마지막 생산보다 뒤로 갔으면 0마리, 지금부터 다시. 아무것도 안 바뀌면 changed = false.
export function soldierProdStep(last: number, now: number, unitSec: number, capMin: number) {
  if (now < last) return { count: 0, last: now, changed: true }
  const elapsed = Math.min(now - last, capMin * 60)
  const count = Math.floor(elapsed / unitSec)
  if (count === 0) return { count: 0, last, changed: false }
  return { count, last: now - last >= capMin * 60 ? now : last + count * unitSec, changed: true }
}

// 합성 뒤 배치 자르기: 배치 수를 보유 수로(0이면 키를 뺀다).
export function trimDeploy(deploy: Record<string, number>, owned: Record<string, number>): Record<string, number> {
  const out: Record<string, number> = {}
  for (const [k, n] of Object.entries(deploy)) {
    const v = Math.min(n, owned[k] ?? 0)
    if (v > 0) out[k] = v
  }
  return out
}

// 모집 확률(주점): SSR + tavern_ssr_per_level × (L − 1), SR + tavern_sr_per_level × (L − 1). R은 나머지.
export function gachaRates(config: Config, tavernLevel: number) {
  const k = Math.max(tavernLevel, 1) - 1
  return {
    ssr: cfgNum(config, 'gacha_rate_ssr') + cfgNum(config, 'tavern_ssr_per_level') * k,
    sr: cfgNum(config, 'gacha_rate_sr') + cfgNum(config, 'tavern_sr_per_level') * k,
  }
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

// 모집(스펙 §3.6): 장마다 등급(SSR rate_ssr, SR rate_sr, 나머지 R)을 정하고 그 등급 안에서 균등하게 뽑는다.
// 10연차는 SR 이상이 gacha_10_min_sr장보다 적으면 뒤에서부터 R을 SR(균등)로 바꾼다. rand는 [0, 1) 난수(서버는 암호학적 난수).
// 확률은 주점 레벨로 오른다(개정 12, gachaRates). 앱 Economy.roll_gacha와 같은 규칙.
export function rollGacha(count: number, heroes: { id: string; grade: string }[], config: Config, rand: () => number, tavernLevel = 1) {
  const pools: Record<string, string[]> = { SSR: [], SR: [], R: [] }
  for (const h of heroes) pools[h.grade]?.push(h.id)
  const pick = (grade: string) => {
    const pool = pools[grade]
    if (pool.length === 0) throw new Error(`no ${grade} heroes to recruit`)
    return { id: pool[Math.floor(rand() * pool.length)], grade }
  }
  const { ssr, sr } = gachaRates(config, tavernLevel)
  const out: { id: string; grade: string }[] = []
  for (let i = 0; i < count; i++) {
    const r = rand()
    out.push(pick(r < ssr ? 'SSR' : r < ssr + sr ? 'SR' : 'R'))
  }
  if (count === 10) {
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

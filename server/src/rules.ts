// 경제 규칙(순수 함수, 시간은 인자 — 유닉스 초). 앱 economy.gd(개정 7)·game_data.gd(개정 8)와 같은 규칙.

export type Config = Record<string, string>

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
export const KILL_SLACK = 20 // 처치 상한 여유분

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

// 시간 칸만의 결정적 함수. jackpot_p 확률로 jackpot_rate, 나머지는 min..max를 step 단위로, 가중치 1 → 1/ratio 직선.
export function merchantRate(hour: number, config: Config): number {
  const rnd = mulberry32(hour)
  if (rnd() < cfgNum(config, 'merchant_jackpot_p')) return cfgNum(config, 'merchant_jackpot_rate')
  const step = cfgNum(config, 'merchant_rate_step')
  const min = cfgNum(config, 'merchant_rate_min')
  const perUnit = Math.round(1 / step)
  const lo = Math.round(min * perUnit)
  const n = Math.round((cfgNum(config, 'merchant_rate_max') - min) / step) + 1
  if (n <= 1) return lo / perUnit
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
    if (pick < 0) return (lo + i) / perUnit
  }
  return (lo + n - 1) / perUnit
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

// 처치 골드 = round(gold × gold_mult), 최소 1.
export function killGold(monsterGold: number, stage: StageRow): number {
  return Math.max(1, roundHalfAway(monsterGold * stage.gold_mult))
}

// 총 처치 수 상한 = ceil(지난 보고 이후 초 × 초당 상한) + 20. 경과가 음수면 0초로 본다.
export function killCap(elapsedSec: number, ratePerSec: number): number {
  return Math.ceil(Math.max(0, elapsedSec) * ratePerSec) + KILL_SLACK
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

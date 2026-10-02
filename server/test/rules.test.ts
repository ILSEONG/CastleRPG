// 순수 규칙: 수집·시세·판매·스테이지 연장·처치 골드·처치 상한.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { test } from 'node:test'
import * as R from '../src/rules.ts'
import { DATA_DIR } from '../src/seed.ts'

const CONFIG: R.Config = Object.fromEntries(
  readFileSync(join(DATA_DIR, 'config.csv'), 'utf8').trim().split('\n').slice(1).map((l) => l.trim().split(',')),
)
const STAGES: R.StageRow[] = readFileSync(join(DATA_DIR, 'stages.csv'), 'utf8').trim().split('\n').slice(1).map((l) => {
  const [stage, hp_mult, atk_mult, gold_mult, waves, wave_size, idle_interval] = l.trim().split(',').map(Number)
  return { stage, hp_mult, atk_mult, gold_mult, waves, wave_size, idle_interval }
})
const CAP = 720

test('pendingAmount: 분 내림, 720분 상한, 0 이하 경과는 0', () => {
  assert.equal(R.pendingAmount(10, 1, 59, CAP), 0)
  assert.equal(R.pendingAmount(10, 1, 60, CAP), 10)
  assert.equal(R.pendingAmount(10, 1, 119.9, CAP), 10)
  assert.equal(R.pendingAmount(5, 2, 600, CAP), 100) // 레벨 배수
  assert.equal(R.pendingAmount(10, 1, CAP * 60 + 5000, CAP), 7200)
  assert.equal(R.pendingAmount(10, 1, 0, CAP), 0)
  assert.equal(R.pendingAmount(10, 1, -300, CAP), 0)
})

test('collectStep: 남은 초 유지, 상한이면 지금, 0이면 변화 없음, 음수 경과는 지금으로', () => {
  const L = 1000
  assert.deepEqual(R.collectStep(L, L + 150, 10, 1, CAP), { amount: 20, lastCollect: L + 120, changed: true })
  assert.deepEqual(R.collectStep(L, L + 30, 10, 1, CAP), { amount: 0, lastCollect: L, changed: false })
  const far = L + CAP * 60 + 45
  assert.deepEqual(R.collectStep(L, far, 10, 1, CAP), { amount: 7200, lastCollect: far, changed: true })
  assert.deepEqual(R.collectStep(L, L + CAP * 60, 10, 1, CAP), { amount: 7200, lastCollect: L + CAP * 60, changed: true })
  assert.deepEqual(R.collectStep(L, L - 500, 10, 1, CAP), { amount: 0, lastCollect: L - 500, changed: true })
})

test('merchantRates: 결정적, 값 12개, 20만 칸 × 3자원 표본 분포(2.0 = 5% ± 0.5%, P(0.5)/P(1.5) = 3 ± 0.3)', () => {
  const allowed = new Set([0.5, 0.6, 0.7, 0.8, 0.9, 1, 1.1, 1.2, 1.3, 1.4, 1.5, 2])
  const counts = new Map<number, number>()
  const start = R.hourIndex(1_790_000_000)
  const N = 200_000 * 3
  for (let h = start; h < start + N / 3; h++) {
    for (const r of Object.values(R.merchantRates(h, CONFIG))) counts.set(r, (counts.get(r) ?? 0) + 1)
  }
  for (const v of counts.keys()) assert.ok(allowed.has(v), `unexpected rate ${v}`)
  const jackpot = (counts.get(2) ?? 0) / N
  const ratio = (counts.get(0.5) ?? 0) / (counts.get(1.5) ?? 1)
  assert.ok(Math.abs(jackpot - 0.05) <= 0.005, `jackpot share ${jackpot}`)
  assert.ok(Math.abs(ratio - 3) <= 0.3, `P(0.5)/P(1.5) = ${ratio}`)
  assert.deepEqual(R.merchantRates(start + 7, CONFIG), R.merchantRates(start + 7, CONFIG))
  assert.deepEqual(Object.keys(R.merchantRates(start, CONFIG)), ['wood', 'stone', 'food'])
  assert.equal(R.nextChange(3600 * 10 + 1), 3600 * 11)
  assert.equal(R.hourIndex(3600 * 10 - 0.001), 9)
})

test('merchantRate: step이 1/정수가 아니어도 min + i × step(0.001 단위)', () => {
  const cfg = { ...CONFIG, merchant_rate_step: '0.3' } // 0.5, 0.8, 1.1, 1.4
  const seen = new Set<number>()
  const start = R.hourIndex(1_790_000_000)
  for (let h = start; h < start + 5000; h++) for (const v of Object.values(R.merchantRates(h, cfg))) seen.add(v)
  assert.deepEqual([...seen].sort((a, b) => a - b), [0.5, 0.8, 1.1, 1.4, 2])
})

test('merchantRates: 자원끼리 다르다(표본에서 세 값이 모두 같은 칸은 절반 미만, 자원별 열이 서로 다른 수열)', () => {
  const start = R.hourIndex(1_790_000_000)
  let same = 0
  const cols: Record<string, number[]> = { wood: [], stone: [], food: [] }
  for (let h = start; h < start + 2000; h++) {
    const r = R.merchantRates(h, CONFIG)
    if (r.wood === r.stone && r.stone === r.food) same++
    for (const k of Object.keys(cols)) cols[k].push(r[k])
  }
  assert.ok(same < 400, `all-equal slots ${same}`)
  assert.notDeepEqual(cols.wood, cols.stone)
  assert.notDeepEqual(cols.stone, cols.food)
  assert.notDeepEqual(cols.wood, cols.food)
})

test('sellValue: floor(수량 × 단가 × 배율)', () => {
  assert.equal(R.sellValue(7, 1, 0.5), 3)
  assert.equal(R.sellValue(3, 2, 0.7), 4) // 4.2
  assert.equal(R.sellValue(10, 1, 1.1), 11) // 부동소수로는 10.999…가 될 수 있는 값
  assert.equal(R.sellValue(3, 1, 0.3), 0) // 0.9
  assert.equal(R.sellValue(100, 2, 2), 400)
})

test('stageRow: 표 안은 그대로, 31행부터 마지막 12행 평균 기울기로 연장', () => {
  assert.deepEqual(R.stageRow(1, STAGES), STAGES[0])
  assert.deepEqual(R.stageRow(0, STAGES), STAGES[0]) // 1 미만은 1
  assert.deepEqual(R.stageRow(30, STAGES), STAGES[29])
  const s31 = R.stageRow(31, STAGES)
  assert.equal(s31.stage, 31)
  assert.ok(Math.abs(s31.hp_mult - 4.0) < 1e-9)
  assert.ok(Math.abs(s31.gold_mult - 7.0) < 1e-9)
  assert.equal(s31.wave_size, 68)
  assert.equal(s31.waves, 13) // 13 + 1/3
  assert.equal(R.stageRow(32, STAGES).waves, 14) // 13 + 2/3
  assert.equal(R.stageRow(33, STAGES).waves, 14)
  assert.equal(s31.idle_interval, 8)
})

test('stageRow: 정수 열 ≥ 1, 방치 간격 ≥ 0.5, 1행 표는 기울기 0', () => {
  const down: R.StageRow[] = [
    { stage: 1, hp_mult: 1, atk_mult: 1, gold_mult: 1, waves: 3, wave_size: 3, idle_interval: 2 },
    { stage: 2, hp_mult: 1, atk_mult: 1, gold_mult: 1, waves: 2, wave_size: 2, idle_interval: 1 },
  ]
  const far = R.stageRow(50, down)
  assert.equal(far.waves, 1)
  assert.equal(far.wave_size, 1)
  assert.equal(far.idle_interval, 0.5)
  assert.deepEqual({ ...R.stageRow(9, down.slice(0, 1)), stage: 1 }, down[0])
})

test('killGoldTenths: max(1, round(gold × gold_mult × 10))', () => {
  assert.equal(R.killGoldTenths(2, STAGES[0]), 20)
  assert.equal(R.killGoldTenths(2, STAGES[1]), 24) // 2.4골드
  assert.equal(R.killGoldTenths(2, STAGES[2]), 28) // 2.8골드
  assert.equal(R.killGoldTenths(50, STAGES[2]), 700)
  assert.equal(R.killGoldTenths(5, { ...STAGES[0], gold_mult: 1.5 }), 75) // 7.5골드 (Godot roundi와 같게)
  assert.equal(R.killGoldTenths(0, STAGES[0]), 1)
  assert.equal(R.killGoldTenths(2, R.stageRow(40, STAGES)), 176) // gold_mult 8.8
})

test('killBucket: 상한 = ceil(인정 초 × rate), 인정 초는 최대 burst, 쓴 만큼만 보고 시각이 앞으로', () => {
  const b = R.killBucket(1000, 1010, 5, 60)
  assert.equal(b.cap, 50)
  assert.equal(b.after(50), 1010)
  assert.equal(b.after(20), 1004) // 남은 6초는 다음 보고로
  assert.equal(b.after(0), 1000)
  const far = R.killBucket(0, 1000, 5, 60) // 오래 쉬어도 버킷은 60초 × 5 = 300
  assert.equal(far.cap, 300)
  assert.equal(far.after(0), 940)
  assert.equal(R.killBucket(1000, 1000.1, 5, 60).cap, 1)
  assert.equal(R.killBucket(1010, 1000, 5, 60).cap, 0) // 보고 시각이 미래(시계 되돌림·외상)면 0
  // 같은 순간 반복: 합쳐서 버킷 이상 못 얻는다
  let last = 0
  let got = 0
  for (let i = 0; i < 50; i++) {
    const k = R.killBucket(last, 1000, 5, 60)
    const kept = Math.min(20, k.cap)
    got += kept
    last = k.after(kept)
  }
  assert.equal(got, 300)
})

test('minClearSec: 웨이브 수 × 웨이브 크기 / kill_rate_cap', () => {
  assert.equal(R.minClearSec(STAGES[0], 5), 4.8) // 3 × 8 / 5
  assert.equal(R.minClearSec(STAGES[1], 5), 6) // 3 × 10 / 5
  assert.equal(R.minClearSec(R.stageRow(31, STAGES), 5), (13 * 68) / 5) // 연장 규칙
})

test('clampKills: 넘치면 비싼 몬스터부터 버림', () => {
  const k = [{ id: 'grunt', count: 60, gold: 2 }, { id: 'epic_boss', count: 20, gold: 50 }]
  assert.deepEqual(R.clampKills(k, 100), { kept: { grunt: 60, epic_boss: 20 }, clamped: false })
  assert.deepEqual(R.clampKills(k, 70), { kept: { grunt: 60, epic_boss: 10 }, clamped: true })
  assert.deepEqual(R.clampKills(k, 20), { kept: { grunt: 20, epic_boss: 0 }, clamped: true })
})

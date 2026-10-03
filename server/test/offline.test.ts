// 오프라인 처치 골드: 규칙(rules.offlineReward), POST /v1/offline(지난 활동 이후 방치 처치 × offline_gold_mult, 상한 accum_cap_min,
// 60초 미만 0, 다시 보내도 한 번), 상태를 바꾸는 요청은 활동 시각을 옮긴다, 마이그레이션 017.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import * as R from '../src/rules.ts'
import { setup, T0 } from './helpers.ts'

test('offlineReward: 처치 = floor(초 × 4 × group / idle_interval), tenths = floor(처치 × 1회 × mult), 상한·60초 미만 0', () => {
  assert.deepEqual(R.offlineReward(3600, 720, 8, 3, 100, 0.5), { sec: 3600, kills: 5400, tenths: 270_000 })
  assert.deepEqual(R.offlineReward(59.9, 720, 8, 3, 100, 0.5), { sec: 59.9, kills: 0, tenths: 0 })
  assert.deepEqual(R.offlineReward(60, 720, 8, 3, 100, 0.5), { sec: 60, kills: 90, tenths: 4500 })
  assert.deepEqual(R.offlineReward(100 * 3600, 720, 8, 3, 100, 0.5), { sec: 43_200, kills: 64_800, tenths: 3_240_000 }) // 12시간 상한
  assert.deepEqual(R.offlineReward(-5, 720, 8, 3, 100, 0.5), { sec: 0, kills: 0, tenths: 0 })
  assert.deepEqual(R.offlineReward(3600, 720, 8, 3, 101, 0.5), { sec: 3600, kills: 5400, tenths: 272_700 })
})

test('POST /v1/offline: 첫 정산 0 → 1시간 뒤 방치 처치 × 0.4(스테이지 1 grunt 100 tenths), 곧바로 다시 보내면 0, 로그', async () => {
  const S = await setup()
  try {
    S.clock.t = T0
    const { token, id } = await S.login()
    let r = await S.req('POST', '/v1/offline', { token, body: {} })
    assert.deepEqual([r.status, r.json.offline, r.json.player.gold_tenths], [200, { away_sec: 0, kills: 0, gold_gained_tenths: 0 }, 0])
    S.clock.t = T0 + 3600
    r = await S.req('POST', '/v1/offline', { token, body: {} })
    assert.deepEqual([r.status, r.json.offline, r.json.player.gold_tenths], [200, { away_sec: 3600, kills: 5400, gold_gained_tenths: 216_000 }, 216_000])
    r = await S.req('POST', '/v1/offline', { token, body: {} })
    assert.deepEqual([r.json.offline, r.json.player.gold_tenths], [{ away_sec: 0, kills: 0, gold_gained_tenths: 0 }, 216_000])
    S.clock.t += 30
    r = await S.req('POST', '/v1/offline', { token, body: {} })
    assert.deepEqual([r.json.offline, r.json.player.gold_tenths], [{ away_sec: 30, kills: 0, gold_gained_tenths: 0 }, 216_000]) // 60초 미만
    S.clock.t += 100 * 3600
    r = await S.req('POST', '/v1/offline', { token, body: {} })
    assert.deepEqual([r.json.offline.kills, r.json.offline.gold_gained_tenths], [64_800, 2_592_000]) // 12시간(accum_cap_min) 상한
    assert.equal(r.json.offline.away_sec, 100 * 3600)
    const logs = await S.db.query("select detail from economy_log where player_id = $1 and kind = 'offline' order by id", [id])
    assert.deepEqual(logs.map((l: any) => l.detail.gold_tenths), [216_000, 2_592_000])
    assert.equal((await S.req('GET', '/v1/player', { token })).json.player.gold_tenths, 216_000 + 2_592_000)
  } finally {
    await S.close()
  }
})

test('상태를 바꾸는 요청(처치 보고)은 활동 시각을 옮긴다 — 앱을 켜 둔 동안은 오프라인으로 치지 않는다', async () => {
  const S = await setup()
  try {
    S.clock.t = T0
    const { token } = await S.login()
    await S.req('POST', '/v1/offline', { token, body: {} })
    S.clock.t = T0 + 600
    const k = await S.req('POST', '/v1/kills', { token, body: { seq: 1, stage: 1, kills: { grunt: 3 } } })
    assert.equal(k.status, 200)
    S.clock.t = T0 + 700
    const r = await S.req('POST', '/v1/offline', { token, body: {} })
    assert.deepEqual(r.json.offline, { away_sec: 100, kills: 150, gold_gained_tenths: 6000 })
  } finally {
    await S.close()
  }
})

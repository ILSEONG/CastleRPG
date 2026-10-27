// 스테이지 클리어 힘 타당성(2026-10-27 보안 점검 — 새 계정이 5초마다 stage만 보내 601까지 올렸다): 배치 영웅·병사의 서버 계산 초당 피해 ×
// 시간(지난 클리어 이후 실제 초 × 2, 스폰 길이 48초 ~ 96초) × 여유 배수 3이 그 라운드 적 HP 합보다 작으면 cleared false(상태 그대로) + economy_log stage_clear_refused.
// Lv 1 스타터 팀 초당 피해 = 23/0.8 + 20/1.0 + 23/0.8 + 12/1.0 = 89.5 → 48초 12,888 · 96초 25,776.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as R from '../src/rules.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup()
})
after(async () => {
  await S.close()
})

const clear = (token: string, stage: number) => S.req('POST', '/v1/stage/clear', { token, body: { stage } })
const setStage = (id: string, stage: number) => S.db.query('update player_state set stage = $2 where player_id = $1', [id, stage])
const refused = async (id: string) => (await S.db.query("select detail from economy_log where player_id = $1 and kind = 'stage_clear_refused' order by id", [id])).map((r) => r.detail)

test('rules: 라운드 적 HP 합 = hp_mult × (72 × grunt + 보스), 보스 라운드는 네 성문 × boss_round_mult, 스폰 길이 3 × (8 + 8)초, 병사 초당 피해', async () => {
  const g = (await S.req('GET', '/v1/gamedata')).json
  const hp = (n: number) => R.stageEnemyHp(n, R.stageRow(n, g.stages), g.monsters, g.config)
  assert.equal(hp(1), 72 * 24 + 400)
  assert.equal(hp(25), 3.4 * (72 * 24 + 4 * 1.5 * 400))
  assert.equal(hp(26), 3.5 * (72 * 24 + 400))
  assert.equal(R.stageRoundSec(R.stageRow(601, g.stages), g.config), 48)
  const soldiers = g.soldiers as R.SoldierDef[]
  const near = (a: number, b: number) => assert.ok(Math.abs(a - b) < 1e-9, `${a} != ${b}`)
  // 보병 22 / 1.0초, 2티어 공격 × 1.6, 성장 공격 +10%·공속 +5%, 보병 연구 6% + 정예 3%. 모르는 병종·티어 초과는 건너뛴다
  near(R.soldierDps({ 'infantry:1': 2, 'archer:2': 1, 'dragon:1': 9, 'infantry:9': 9 }, soldiers, g.config, 0, 0, {}), 2 * 22 + 18 * 1.6 / 1.2)
  near(R.soldierDps({ 'infantry:1': 1 }, soldiers, g.config, 0.1, 0.05, { inf_pct: 6, soldier_pct: 3 }), 22 * 1.1 * 1.09 * 1.05)
})

test('정상 속도(라운드 약 75초 ÷ 2배속 = 40초 간격)면 새 계정 기본 배치(스타터 Lv 1)로 1~30라운드를 깬다 — 25라운드 보스 포함', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  for (let stage = 1; stage <= 30; stage++) {
    S.clock.t += 40
    const r = await clear(token, stage)
    assert.deepEqual([r.json.cleared, r.json.player.stage], [true, stage + 1], `stage ${stage}`)
  }
  assert.deepEqual(await refused(id), [])
})

test('배치가 비면(영웅·병사 없음) 1라운드도 못 깬다: cleared false, 상태 그대로, 거절 기록에 숫자', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await S.req('POST', '/v1/deploy', { token, body: { deploy: [null, null, null, null] } })
  S.clock.t += 100
  const r = await clear(token, 1)
  assert.deepEqual([r.status, r.json.cleared, r.json.player.stage], [200, false, 1])
  assert.deepEqual(await refused(id), [{ stage: 1, sec: 100, dps: 0, budget_sec: 96, slack: 3, enemy_hp: 72 * 24 + 400 }])
  assert.equal((await S.db.query("select count(*)::int as n from economy_log where player_id = $1 and kind = 'stage_clear'", [id]))[0].n, 0)
})

test('감사 PoC: 5초마다 보내는 스크립트는 스타터 팀으로 25에서 막히고, 기다려도 74까지 — 601은 못 깬다, 병사를 배치하면 깬다', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  let stage = 1
  for (let i = 0; i < 25; i++) {
    S.clock.t += 5
    stage = (await clear(token, stage)).json.player.stage
  }
  assert.equal(stage, 25) // 24라운드 7,022 ≤ 12,888 < 25라운드 보스 14,035
  let d = (await refused(id))[0]
  assert.deepEqual([d.stage, d.budget_sec, d.dps, d.enemy_hp], [25, 48, 90, 14035])
  // 기다린 만큼(× 2배속) 인정하되 스폰 길이 × 2(96초)까지: 25·50라운드 보스(24,355)는 넘고 75라운드 보스(34,675)에서 막힌다
  S.clock.t += 1000
  assert.equal((await clear(token, 25)).json.cleared, true)
  await setStage(id, 74)
  S.clock.t += 1000
  assert.equal((await clear(token, 74)).json.cleared, true)
  S.clock.t += 1000
  assert.deepEqual([(await clear(token, 75)).json.cleared, (await clear(token, 75)).json.player.stage], [false, 75])
  await setStage(id, 601)
  S.clock.t += 1000
  assert.equal((await clear(token, 601)).json.cleared, false)
  d = (await refused(id)).at(-1)
  assert.deepEqual([d.stage, d.budget_sec, d.enemy_hp], [601, 96, 129808])
  // 보병 20명(초당 440)을 배치하면 그 라운드를 깬다(거절은 클리어 시각을 옮기지 않는다 — 곧바로 다시 보내도 된다)
  await S.db.query("insert into player_soldiers (player_id, type, tier, count) values ($1, 'infantry', 1, 20)", [id])
  await S.db.query(`update player_state set soldier_deploy = '{"infantry:1": 20}'::jsonb where player_id = $1`, [id])
  const r = await clear(token, 601)
  assert.deepEqual([r.json.cleared, r.json.player.stage], [true, 602])
})

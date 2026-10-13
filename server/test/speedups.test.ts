// 2026-10-13 라오킹식 건설: 가속 아이템(건설·연구·범용)·일꾼 고용권과 두 번째 일꾼.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as Sp from '../src/speedups.ts'
import * as M from '../src/missions.ts'
import * as A from '../src/attendance.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup()
})
after(async () => {
  await S.close()
})

const player = async (token: string) => (await S.req('GET', '/v1/player', { token })).json.player
const upgrade = (token: string, building: string) => S.req('POST', '/v1/building/upgrade', { token, body: { building } })
const use = (token: string, body: Record<string, unknown>) => S.req('POST', '/v1/speedup/use', { token, body })
const give = (id: string, items: Record<string, number>) => S.db.query('update player_state set speedups = $2::jsonb where player_id = $1', [id, JSON.stringify(items)])
async function setLevels(id: string, levels: Record<string, number>) {
  for (const [b, l] of Object.entries(levels)) {
    await S.db.query('update player_buildings set level = $3 where player_id = $1 and building = $2', [id, b, l])
    if (b === 'keep') await S.db.query('update player_state set keep_level = $2 where player_id = $1', [id, l])
    if (b === 'gate') await S.db.query('update player_state set gate_level = $2 where player_id = $1', [id, l])
  }
}
const rich = (id: string) => S.db.query('update player_resources set amount = 100000000 where player_id = $1', [id])

test('아이템 표: id 파싱·쓸 수 있는 타이머·보상 키·정리', () => {
  assert.deepEqual(Sp.parse('build_60'), { kind: 'build', min: 60 })
  assert.deepEqual(Sp.parse('any_1440'), { kind: 'any', min: 1440 })
  assert.deepEqual(Sp.parse('builder_2880'), { kind: 'builder', min: 2880 })
  for (const bad of ['build_61', 'any', 'gold_60', '__proto__']) assert.equal(Sp.parse(bad), null, bad)
  assert.ok(Sp.fits('build', 'build') && Sp.fits('any', 'research') && !Sp.fits('research', 'build'))
  assert.deepEqual(Sp.fromReward({ speedup_build_60: 2, speedup_nope_1: 1, gold: 5, pouch_gold_60: 1 }), { build_60: 2 })
  assert.deepEqual(Sp.normalize({ build_60: 2, x: 1, any_5: 0, research_15: 1.5 }), { build_60: 2 })
  // 보상 표에 넣은 키는 모두 아는 아이템
  for (const r of [...M.DEFS.map((d) => d.reward), ...A.REWARDS]) {
    for (const k of Object.keys(r)) if (k.startsWith(Sp.REWARD_PREFIX)) assert.ok(Sp.IDS.includes(k.slice(Sp.REWARD_PREFIX.length)), k)
  }
})

test('건설 가속: 끝나는 시각을 당기고(지금보다 앞으로는 안 감) 다음 요청이 완료, 맞지 않는 아이템·보유 부족·짓는 것 없음은 409', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await rich(id)
  await setLevels(id, { keep: 10, gate: 10, barracks: 10 })
  await give(id, { build_60: 3, research_60: 1, any_5: 1 })
  assert.deepEqual((await use(token, { id: 'build_60', target: 'build' })).json.error, 'no_build')
  const r = await upgrade(token, 'keep') // 10 → 11: 56,220초
  assert.equal(r.status, 200)
  const fin = r.json.build.finish
  assert.equal(fin, T0 + 56220)
  assert.equal((await use(token, { id: 'research_60', target: 'build' })).json.error, 'wrong_target')
  assert.equal((await use(token, { id: 'build_60', target: 'build', count: 4 })).json.error, 'not_enough')
  assert.equal((await use(token, { id: 'build_99', target: 'build' })).status, 404)
  assert.equal((await use(token, { id: 'build_60', target: 'x' })).status, 400)
  assert.equal((await use(token, { id: 'build_60', target: 'build', count: 0 })).status, 400)
  let u = await use(token, { id: 'build_60', target: 'build', count: 2 })
  assert.equal(u.status, 200)
  assert.deepEqual([u.json.player.build, u.json.player.speedups], [{ id: 'keep', finish: fin - 7200 }, { build_60: 1, research_60: 1, any_5: 1 }])
  u = await use(token, { id: 'any_5', target: 'build', building: 'keep' })
  assert.equal(u.json.player.build.finish, fin - 7500)
  // 남은 시간보다 많이 써도 지금까지만(넘친 시간은 사라진다) — 다음 요청이 완료
  S.clock.t = fin - 7500 - 3000
  u = await use(token, { id: 'build_60', target: 'build' })
  assert.equal(u.status, 200)
  assert.deepEqual([u.json.player.buildings.keep.level, u.json.player.build, u.json.player.speedups], [11, null, { research_60: 1 }])
  const logs = await S.db.query("select detail from economy_log where player_id = $1 and kind = 'speedup' order by id", [id])
  assert.equal(logs.length, 3)
})

test('연구 가속: 진행 중 연구의 끝나는 시각을 당긴다', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await rich(id)
  await S.db.query('update player_state set gold_tenths = 100000000000 where player_id = $1', [id])
  await setLevels(id, { keep: 10, lab: 10 })
  await give(id, { research_60: 1, build_5: 1 })
  assert.equal((await use(token, { id: 'research_60', target: 'research' })).json.error, 'no_research')
  const st = await S.req('POST', '/v1/research/start', { token, body: { id: 'wood_tech' } })
  assert.equal(st.status, 200, JSON.stringify(st.json))
  const cur = st.json.player.research.current
  assert.equal((await use(token, { id: 'build_5', target: 'research' })).json.error, 'wrong_target')
  const u = await use(token, { id: 'research_60', target: 'research' })
  assert.equal(u.status, 200)
  const now = u.json.player.research.current
  if (cur.finish - 3600 > T0) assert.deepEqual(now, { id: cur.id, finish: cur.finish - 3600 })
  else assert.equal(now, null) // 한 시간보다 짧은 연구면 바로 끝났다
})

test('두 번째 일꾼: 고용권으로 기한을 늘리고, 기한 안에는 두 건물을 함께 짓는다. 같은 건물은 in_progress, 기한이 지나도 짓던 건물은 끝난다', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await rich(id)
  await setLevels(id, { keep: 12, gate: 10, barracks: 10, farm: 9, quarry: 9 })
  await give(id, { builder_1440: 2 })
  assert.equal((await upgrade(token, 'farm')).status, 200)
  assert.equal((await upgrade(token, 'quarry')).json.error, 'builder_busy')
  assert.equal((await use(token, { id: 'builder_1440', target: 'build' })).status, 200) // target은 무시
  let p = await player(token)
  assert.equal(p.builder2_until, T0 + 86400)
  assert.equal((await use(token, { id: 'builder_1440' })).json.builder2_until, T0 + 2 * 86400) // 기한에 더한다
  assert.equal((await upgrade(token, 'farm')).json.error, 'in_progress')
  const q = await upgrade(token, 'quarry')
  assert.deepEqual([q.status, q.json.builder], [200, 2])
  p = q.json.player
  assert.deepEqual([p.build.id, p.build2.id], ['farm', 'quarry'])
  assert.equal((await upgrade(token, 'lumber')).json.error, 'builder_busy') // 둘 다 바쁘다
  // 기한이 지나도 짓던 채석장은 끝나고, 그 뒤로는 일꾼 하나
  S.clock.t = T0 + 3 * 86400
  p = await player(token)
  assert.deepEqual([p.buildings.farm.level, p.buildings.quarry.level, p.build, p.build2], [10, 10, null, null])
  assert.equal((await upgrade(token, 'farm')).status, 200)
  assert.equal((await upgrade(token, 'quarry')).json.error, 'builder_busy')
  const done = await S.db.query("select detail from economy_log where player_id = $1 and kind = 'build_done' order by id", [id])
  assert.deepEqual(done.map((d) => [d.detail.building, d.detail.builder ?? 1]).sort(), [['farm', 1], ['quarry', 2]])
})

test('무료 완료는 building으로 일꾼을 고른다(생략하면 1번)', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await rich(id)
  await setLevels(id, { keep: 10, gate: 10, barracks: 10 })
  await give(id, { builder_2880: 1 })
  await use(token, { id: 'builder_2880' })
  assert.equal((await upgrade(token, 'lumber')).status, 200) // 1 → 2: 20초
  assert.equal((await upgrade(token, 'houses')).status, 200) // 1 → 2: 20초
  const r = await S.req('POST', '/v1/building/finish', { token, body: { building: 'houses' } })
  assert.equal(r.status, 200)
  assert.deepEqual([r.json.player.buildings.houses.level, r.json.player.build?.id, r.json.player.build2], [2, 'lumber', null])
  assert.equal((await S.req('POST', '/v1/building/finish', { token, body: { building: 'keep' } })).json.error, 'no_build')
})

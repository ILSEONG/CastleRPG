// 자유 건설(2026-10-13): 공터를 고른 자리에 짓기(cell), 자리 규칙(성벽 여유·길·상인 자리·겹침) 409, 지은 건물 옮기기(/v1/building/move),
// 성채·공터 옮기기 거부, 자리 없이 짓기는 기본 자리, 규칙 표(앱 Balance.placement_block과 같은 결과).
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as R from '../src/rules.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup({ tutorial: true })
})
after(async () => {
  await S.close()
})

const player = async (token: string) => (await S.req('GET', '/v1/player', { token })).json.player
const upgrade = (token: string, body: unknown) => S.req('POST', '/v1/building/upgrade', { token, body })
const move = (token: string, body: unknown) => S.req('POST', '/v1/building/move', { token, body })
const RICH = { wood: 1_000_000, stone: 1_000_000, food: 1_000_000 }
const setRes = (id: string, r: Record<string, number>) => Promise.all(Object.entries(r).map(([res, n]) =>
  S.db.query('update player_resources set amount = $3 where player_id = $1 and res = $2', [id, res, n])))

test('규칙: 기본 자리는 모두 된다, 길·상인 자리·성벽 여유·겹침·성채는 막힌다', () => {
  for (const [id, cell] of Object.entries(R.DEFAULT_CELLS)) {
    assert.equal(R.placementBlock(id, cell, 10, R.DEFAULT_CELLS), id === 'keep' ? 'fixed' : '', id)
  }
  const D = R.DEFAULT_CELLS
  assert.equal(R.placementBlock('lumber', [-1, 5], 10, D), 'road')
  assert.equal(R.placementBlock('lumber', [5, -1], 10, D), 'road')
  assert.equal(R.placementBlock('lumber', [1, 3], 10, D), '') // 옛 병사 광장 — 없앴다(2026-10-18)
  assert.equal(R.placementBlock('lumber', [-4, 2], 10, {}), 'square')
  assert.equal(R.placementBlock('lumber', [6, 5], 10, D), 'out')
  assert.equal(R.placementBlock('lumber', [5, 5], 10, D), '')
  assert.equal(R.placementBlock('lumber', [4, 1], 10, D), 'overlap')
  assert.equal(R.placementBlock('lumber', [9, 9], 14, D), '')
  assert.equal(R.placementBlock('nope', [5, 5], 10, D), 'fixed')
})

test('공터를 고른 자리에 짓는다: layout에 남고, 규칙에 걸리면 409 그 이유, 잘못된 cell은 400', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setRes(id, RICH)
  assert.equal((await upgrade(token, { building: 'lumber', cell: [-1, 5] })).json.error, 'road')
  assert.equal((await upgrade(token, { building: 'lumber', cell: [6, 5] })).json.error, 'out')
  assert.equal((await upgrade(token, { building: 'lumber', cell: [-4, 2] })).json.error, 'square')
  assert.equal((await upgrade(token, { building: 'lumber', cell: [1.5, 3] })).status, 400)
  assert.equal((await upgrade(token, { building: 'lumber', cell: 'x' })).status, 400)
  const r = await upgrade(token, { building: 'lumber', cell: [5, 5] })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  assert.deepEqual(r.json.player.layout, { lumber: [5, 5] })
  S.clock.t += 3600
  const p = await player(token)
  assert.ok(!p.unbuilt.includes('lumber'))
  assert.deepEqual(p.layout, { lumber: [5, 5] })
  // 다음 공터: 벌목장 자리와 겹치면 409 overlap, 비어 있던 채석장 기본 자리(5, 2)는 벌목장(5, 5)과 맞닿을 뿐이라 된다
  assert.equal((await upgrade(token, { building: 'farm', cell: [4, 4] })).json.error, 'overlap')
  assert.equal((await upgrade(token, { building: 'quarry' })).status, 200)
  assert.deepEqual((await player(token)).layout, { lumber: [5, 5] })
})

test('옮기기: 지은 건물만, 무료, 규칙 검사 / 성채·공터·모르는 건물 거부', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setRes(id, RICH)
  assert.equal((await upgrade(token, { building: 'lumber', cell: [5, 5] })).status, 200)
  S.clock.t += 3600
  const before = (await player(token)).res
  const r = await move(token, { building: 'lumber', cell: [-8, 5] })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  assert.deepEqual(r.json.player.layout, { lumber: [-8, 5] })
  assert.deepEqual(r.json.player.res, before)
  assert.equal((await move(token, { building: 'lumber', cell: [0, 5] })).json.error, 'road')
  assert.equal((await move(token, { building: 'keep', cell: [5, 5] })).json.error, 'fixed')
  assert.equal((await move(token, { building: 'nope', cell: [5, 5] })).json.error, 'unknown_building')
  assert.equal((await move(token, { building: 'farm', cell: [5, 5] })).json.error, 'unbuilt')
  assert.equal((await move(token, { building: 'lumber' })).status, 400)
  const logs = await S.db.query("select detail from economy_log where player_id = $1 and kind = 'build_move'", [id])
  assert.equal(logs.length, 1)
})

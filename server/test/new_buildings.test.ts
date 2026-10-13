// 2026-10-13 새 건물(창고·금광·대장간·길드 회관·망루)과 자원 건물 n번째 채(lumber#2…): 성채 레벨로 열리고, 처음엔 자리를 골라 짓는다.
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

const player = async (token: string) => (await S.req('GET', '/v1/player', { token })).json.player
const build = (token: string, building: string, cell?: [number, number]) =>
  S.req('POST', '/v1/building/upgrade', { token, body: cell ? { building, cell } : { building } })
const levels = (token: string, lv: Record<string, number>) =>
  S.req('POST', '/v1/test/levels', { token, body: { levels: lv, res: { wood: 100000000, stone: 100000000, food: 100000000 } } })
const done = (token: string) => S.req('POST', '/v1/test/build_now', { token })
const CFG = { res_copy_tiers: '1:1|5:2|10:3|15:4', accum_cap_min: '720', warehouse_cap_min_per_level: '60', goldmine_gold_base: '20', goldmine_gold_exp: '1.5',
  forge_extra_drop_pct_per_level: '2', guild_hall_helps_base: '2', guild_hall_helps_per_level: '1', guild_help_pct: '1', guild_help_min_sec: '60' }

test('규칙: 키 = 종류#n, 성채 레벨별 채 수, 해금 레벨, 효과 식', () => {
  assert.deepEqual([R.typeOf('lumber#3'), R.typeOf('keep'), R.copyIndex('lumber#3'), R.copyIndex('lumber')], ['lumber', 'keep', 3, 1])
  assert.deepEqual([1, 4, 5, 9, 10, 15, 30].map((k) => R.copiesAt(CFG, k)), [1, 1, 2, 2, 3, 4, 4])
  assert.equal(R.maxCopies(CFG), 4)
  assert.deepEqual([2, 3, 4].map((n) => R.copyUnlockKeep(CFG, n)), [5, 10, 15])
  assert.equal(R.accumCapMin(CFG, 0), 720)
  assert.equal(R.accumCapMin(CFG, 3), 900)
  assert.deepEqual([0, 1, 4, 30].map((l) => R.goldminePerMin(CFG, l)), [0, 20, 160, 3286])
  assert.equal(R.forgeExtraP(CFG, 5), 0.1)
  assert.deepEqual([0, 1, 10].map((l) => R.guildHelps(CFG, l)), [0, 2, 11])
  assert.equal(R.afterHelps(1000, 2, CFG), 880) // 60초씩(1%보다 크다)
  assert.equal(R.afterHelps(100000, 1, CFG), 99000) // 1%
})

test('n번째 채·새 건물: 처음엔 공터, 성채 레벨 전엔 keep_cap, 기본 자리가 없으니 no_cell, 자리를 고르면 짓고 다 지으면 Lv 1', async () => {
  S.clock.t = T0
  const { token } = await S.login()
  let p = await player(token)
  for (const k of ['lumber#2', 'farm#4', 'warehouse', 'goldmine', 'forge', 'guild_hall', 'watchtower']) assert.ok(p.unbuilt.includes(k), k)
  await levels(token, { keep: 4 })
  assert.equal((await build(token, 'lumber#2', [-8, 2])).json.error, 'keep_cap') // 2번째 채는 성채 5
  assert.equal((await build(token, 'forge', [-8, 2])).json.error, 'keep_cap') // 대장간은 성채 8
  assert.equal((await build(token, 'goldmine')).json.error, 'no_cell')
  assert.equal((await build(token, 'goldmine', [0, -8])).json.error, 'road')
  assert.equal((await build(token, 'nope#2')).status, 400)
  assert.equal((await build(token, 'lumber#5')).status, 400) // 최대 4채
  const r = await build(token, 'goldmine', [-8, 2])
  assert.equal(r.status, 200, JSON.stringify(r.json))
  assert.deepEqual(r.json.player.layout.goldmine, [-8, 2])
  await done(token)
  p = await player(token)
  assert.ok(!p.unbuilt.includes('goldmine'))
  assert.equal(p.buildings.goldmine.level, 1)
  // 성채 5: 벌목장 2번째 채 — 자기 레벨·자원 수집 시계, 1번째와 따로 올린다
  await levels(token, { keep: 5 })
  assert.equal((await build(token, 'lumber#2', [-8, -2 - 3 - 3])).status, 409) // 다른 건물과 겹침(마구간 -8,-8)
  const r2 = await build(token, 'lumber#2', [5, 5])
  assert.equal(r2.status, 200, JSON.stringify(r2.json))
  await done(token)
  p = await player(token)
  assert.deepEqual([p.unbuilt.includes('lumber#2'), p.buildings['lumber#2'].level, p.buildings.lumber.level], [false, 1, 1])
  // 지은 n번째 채는 옮길 수 있고, 업그레이드는 성채 상한
  assert.equal((await S.req('POST', '/v1/building/move', { token, body: { building: 'lumber#2', cell: [5, -5] } })).status, 409) // 주점 자리
  const up = await build(token, 'lumber#2')
  assert.equal(up.status, 200, JSON.stringify(up.json))
})

test('금광: 분마다 골드가 쌓이고 /v1/collect로 받는다(창고 레벨만큼 상한이 늘어난다)', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await levels(token, { keep: 4 })
  assert.equal((await S.req('POST', '/v1/collect', { token, body: { building: 'goldmine' } })).json.error, 'unbuilt')
  await build(token, 'goldmine', [-8, 2])
  await done(token)
  const g0 = (await player(token)).gold_tenths
  S.clock.t = T0 + 600 // 10분
  const r = await S.req('POST', '/v1/collect', { token, body: { building: 'goldmine' } })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  assert.equal(r.json.amount, 200) // Lv 1: 20/분
  assert.equal(r.json.player.gold_tenths - g0, 2000)
  // 상한: 720분(창고 없음) — 1000분 지나도 720분어치
  S.clock.t = T0 + 600 + 1000 * 60
  assert.equal((await S.req('POST', '/v1/collect', { token, body: { building: 'goldmine' } })).json.amount, 20 * 720)
  // 창고 Lv 2: 상한 +120분
  await levels(token, { keep: 3 })
  const w = await build(token, 'warehouse', [5, 5])
  assert.equal(w.status, 200, JSON.stringify(w.json))
  await done(token)
  await levels(token, { warehouse: 2, keep: 4 })
  S.clock.t += 2000 * 60
  assert.equal((await S.req('POST', '/v1/collect', { token, body: { building: 'goldmine' } })).json.amount, 20 * 840)
  assert.ok(id)
})

test('길드 회관: 길드에 들어 있으면 건설 시간이 도움 수만큼 줄어든다', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await levels(token, { keep: 10, gate: 10, barracks: 10 })
  const gh = await build(token, 'guild_hall', [-8, 2])
  assert.equal(gh.status, 200, JSON.stringify(gh.json))
  await done(token)
  // 길드 밖: 그대로(성채 10 → 11: 56,220초)
  let r = await build(token, 'keep')
  assert.equal(r.json.build.finish, S.clock.t + 56220)
  await done(token)
  await levels(token, { keep: 10 })
  const [g] = await S.db.query("insert into guilds (name, emblem, seed, created_at, virtual_n) values ('회관 시험', 1, 9, now(), 0) returning id::text as id")
  await S.db.query('insert into player_guild (player_id, guild_id) values ($1, $2) on conflict (player_id) do update set guild_id = $2', [id, g.id])
  r = await build(token, 'keep')
  assert.equal(r.json.build.finish, S.clock.t + R.afterHelps(56220, 2, CFG)) // 회관 Lv 1: 도움 2번
})

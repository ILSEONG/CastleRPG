// 황금 고블린(POST /v1/goblin/claim)과 파견소 의뢰(/v1/dispatch*), 마이그레이션 046.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as D from '../src/dispatch.ts'
import * as GB from '../src/goblin.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup()
})
after(async () => {
  await S.close()
})

const DAY = 86400
const seq = (xs: number[]) => {
  let i = 0
  return () => xs[i++ % xs.length]
}

test('dispatch.ts: 레벨 효과(의뢰 수·확률·시간), 뽑기, 조건', () => {
  assert.deepEqual([0, 1, 4, 5, 10, 29, 30].map(D.slots), [0, 3, 3, 4, 5, 8, 9])
  assert.deepEqual(D.odds(1), [60, 30, 9, 1])
  assert.deepEqual(D.odds(30), [25, 40, 25, 10])
  assert.ok(Math.abs(D.odds(15).reduce((a, b) => a + b, 0) - 100) < 0.5)
  assert.equal(D.durationSec('N', 1), 3600)
  assert.equal(D.durationSec('SSR', 30), Math.round(480 * 60 * 0.71))
  assert.equal(D.rollRarity(1, () => 0.995), 'SSR')
  assert.equal(D.rollRarity(1, () => 0), 'N')
  const j = D.roll(7, 1, seq([0.95, 0, 0, 0, 0.5]))
  assert.equal(j.rarity, 'SR')
  assert.equal(j.size, 2)
  assert.equal(j.types.length, 3)
  assert.equal(new Set(j.types).size, 3)
  assert.equal(D.eligible({ grade: 'SR', types: ['tank'] }, { grade: 'SSR', archetype: 'tank' }), true)
  assert.equal(D.eligible({ grade: 'SR', types: ['tank'] }, { grade: 'R', archetype: 'tank' }), false)
  assert.equal(D.eligible({ grade: 'R', types: ['tank'] }, { grade: 'R', archetype: 'caster' }), false)
  // 날이 바뀌면 시작 안 한 것은 버리고 진행 중은 남긴다, 오늘 몫만큼 채운다
  const a = D.normalize({}, 10, 1, Math.random)
  assert.equal(a.state.list.length, 3)
  a.state.list[0] = { ...a.state.list[0], heroes: ['x'], finish: 1 }
  const b = D.normalize(a.state, 11, 5, Math.random)
  assert.equal(b.state.list.length, 5)
  assert.deepEqual(b.state.list[0].heroes, ['x'])
  assert.equal(b.state.got, 4)
  assert.equal(D.normalize(b.state, 11, 5, Math.random).changed, false)
})

test('황금 고블린: 방치 골드 15분, 4분 30초 안에 또 받으면 too_soon, 덤은 하루 20마리까지', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  const p0 = (await S.req('GET', '/v1/player', { token })).json.player
  let r = await S.req('POST', '/v1/goblin/claim', { token })
  assert.equal(r.status, 200)
  assert.equal(r.json.goblin.gold_tenths, 54_000) // 스테이지 1 방치 골드 30분(주머니 10분 = 18,000) = 처치 골드 절반 전 15분치
  assert.equal(r.json.goblin.n, 1)
  assert.ok(r.json.player.gold_tenths >= p0.gold_tenths + 27_000)
  S.clock.t = T0 + GB.MIN_GAP_SEC - 1
  r = await S.req('POST', '/v1/goblin/claim', { token })
  assert.equal(r.json.error, 'too_soon')
  S.clock.t = T0 + GB.MIN_GAP_SEC
  assert.equal((await S.req('POST', '/v1/goblin/claim', { token })).json.goblin.n, 2)
  assert.deepEqual(GB.bonus(GB.BONUS_DAILY, () => 0), {})
  assert.deepEqual(GB.bonus(0, () => 0), { speedup_any_5: 1, diamonds: GB.DIA })
  assert.deepEqual(GB.bonus(0, () => 0.99), {})
  const logs = await S.db.query("select detail from economy_log where player_id = $1 and kind = 'goblin'", [id])
  assert.equal(logs.length, 2)
  // 다음 날이면 오늘 수가 1부터
  S.clock.t = T0 + DAY
  assert.equal((await S.req('POST', '/v1/goblin/claim', { token })).json.goblin.n, 1)
})

async function withOffice(level: number) {
  const { token, id } = await S.login()
  await S.db.query("insert into player_buildings (player_id, building, level) values ($1, 'dispatch', $2) on conflict (player_id, building) do update set level = $2", [id, level])
  await S.db.query("update player_state set unbuilt = array_remove(unbuilt, 'dispatch') where player_id = $1", [id])
  return { token, id }
}

test('파견소가 없으면 409 no_building', async () => {
  S.clock.t = T0
  const { token } = await S.login()
  await S.db.query("delete from player_buildings where building = 'dispatch'")
  assert.equal((await S.req('GET', '/v1/dispatch', { token })).json.error, 'no_building')
})

test('파견소: 목록(같은 날 같은 의뢰), 보내기 조건, 받기, 즉시 완료, 새로고침', async () => {
  S.clock.t = T0
  const { token, id } = await withOffice(1)
  let r = await S.req('GET', '/v1/dispatch', { token })
  assert.equal(r.status, 200)
  const list = r.json.dispatch.list
  assert.equal(list.length, 3)
  assert.equal(r.json.dispatch.slots, 3)
  assert.deepEqual((await S.req('GET', '/v1/dispatch', { token })).json.dispatch.list, list)
  // 모든 영웅을 가졌다고 두고(조건만 본다), 첫 의뢰에 맞는 영웅을 고른다
  const heroes = await S.db.query('select id, grade, archetype from heroes order by id')
  for (const h of heroes) await S.db.query('insert into player_heroes (player_id, hero_id, copies, level) values ($1, $2, 1, 1) on conflict (player_id, hero_id) do update set copies = 1', [id, h.id])
  const job = list[0]
  const fit = heroes.filter((h: any) => D.eligible(job, h)).map((h: any) => h.id)
  const bad = heroes.find((h: any) => !D.eligible(job, h)).id
  assert.equal((await S.req('POST', '/v1/dispatch/start', { token, body: { jobs: [{ id: job.id, heroes: [bad, ...fit].slice(0, job.size) }] } })).json.error, 'bad_heroes')
  assert.equal((await S.req('POST', '/v1/dispatch/start', { token, body: { jobs: [{ id: job.id, heroes: fit.slice(0, job.size + 1) }] } })).json.error, 'bad_heroes')
  r = await S.req('POST', '/v1/dispatch/start', { token, body: { jobs: [{ id: job.id, heroes: fit.slice(0, job.size) }] } })
  assert.equal(r.status, 200)
  const started = r.json.dispatch.list.find((j: any) => j.id === job.id)
  assert.equal(started.finish, T0 + D.durationSec(job.rarity, 1))
  assert.deepEqual(r.json.player.dispatch, [started.finish])
  assert.equal((await S.req('POST', '/v1/dispatch/start', { token, body: { jobs: [{ id: job.id, heroes: fit.slice(0, job.size) }] } })).json.error, 'stale')
  // 같은 영웅을 다른 의뢰에 보내면 busy(조건이 맞을 때)
  const other = list.find((j: any) => j.id !== job.id && fit.slice(0, job.size).some((h: string) => D.eligible(j, heroes.find((x: any) => x.id === h))))
  if (other) {
    const h0 = fit.slice(0, job.size).find((h: string) => D.eligible(other, heroes.find((x: any) => x.id === h)))
    const rest = heroes.filter((h: any) => D.eligible(other, h) && h.id !== h0 && !fit.slice(0, job.size).includes(h.id)).map((h: any) => h.id)
    assert.equal((await S.req('POST', '/v1/dispatch/start', { token, body: { jobs: [{ id: other.id, heroes: [h0, ...rest].slice(0, other.size) }] } })).json.error, 'busy')
  }
  // 아직 안 끝났다
  assert.equal((await S.req('POST', '/v1/dispatch/claim', { token, body: { ids: [job.id] } })).json.error, 'not_done')
  // 즉시 완료(남은 분당 다이아 1)
  await S.db.query('update player_state set diamonds = 10000 where player_id = $1', [id])
  S.clock.t = T0 + 600
  const cost = Math.ceil((started.finish - S.clock.t) / 60)
  assert.equal((await S.req('POST', '/v1/dispatch/finish', { token, body: { id: job.id, cost: cost - 1 } })).json.error, 'stale')
  r = await S.req('POST', '/v1/dispatch/finish', { token, body: { id: job.id, cost } })
  assert.equal(r.status, 200)
  assert.equal(r.json.player.diamonds, 10000 - cost)
  r = await S.req('POST', '/v1/dispatch/claim', { token, body: { ids: [job.id] } })
  assert.equal(r.status, 200)
  assert.deepEqual(r.json.claimed.reward, job.reward)
  assert.equal(r.json.dispatch.list.length, 2) // 받은 의뢰는 빠지고 오늘 몫은 다시 채우지 않는다
  // 새로고침: 첫 번은 무료(paid false), 그다음 다이아
  const before = r.json.dispatch.list.map((j: any) => j.id)
  assert.equal((await S.req('POST', '/v1/dispatch/refresh', { token, body: { paid: true, n: 0 } })).json.error, 'stale')
  r = await S.req('POST', '/v1/dispatch/refresh', { token, body: { paid: false, n: 0 } })
  assert.equal(r.status, 200)
  assert.equal(r.json.dispatch.free_refresh, false)
  assert.notDeepEqual(r.json.dispatch.list.map((j: any) => j.id), before)
  const dia = r.json.player.diamonds
  r = await S.req('POST', '/v1/dispatch/refresh', { token, body: { paid: true, n: 0 } })
  assert.equal(r.json.player.diamonds, dia - D.REFRESH_DIA)
  assert.equal(r.json.dispatch.paid_left, D.PAID_REFRESH_MAX - 1)
})

test('파견소 레벨이 오르면 그날 바로 의뢰가 늘고, 다음 날은 새 의뢰(진행 중은 남는다)', async () => {
  S.clock.t = T0
  const { token, id } = await withOffice(4)
  let r = await S.req('GET', '/v1/dispatch', { token })
  assert.equal(r.json.dispatch.list.length, 3)
  await S.db.query("update player_buildings set level = 10 where player_id = $1 and building = 'dispatch'", [id])
  r = await S.req('GET', '/v1/dispatch', { token })
  assert.equal(r.json.dispatch.list.length, 5)
  S.clock.t = T0 + DAY
  r = await S.req('GET', '/v1/dispatch', { token })
  assert.equal(r.json.dispatch.list.length, 5)
  assert.equal(r.json.dispatch.got, 5)
})

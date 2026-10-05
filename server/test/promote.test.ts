// 영웅 승급(개정 15 §1·§2): 비용 표(5|25|50|100|200), 최대 레벨(승급 기준), 성공(조각 −비용·승급 +1·로그·응답), 404·409·400,
// 모집 중복 → 조각, 레벨업 상한의 승급 반영. 동시 2건은 concurrency.test, 마이그레이션 백필은 seed.test.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as R from '../src/rules.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
const rand = { next: [] as number[] }
before(async () => {
  S = await setup({ random: () => rand.next.shift() ?? R.cryptoRandom() })
})
after(async () => {
  await S.close()
})

const CFG = { promote_shards: '5|25|50|100|200', hero_max_level_base: '20', hero_max_level_per_promotion: '10' }
const setHero = (id: string, hero: string, o: { shards?: number; promotion?: number; level?: number; copies?: number }) =>
  S.db.query(`insert into player_heroes (player_id, hero_id, copies, level, shards, promotion) values ($1, $2, $3, $4, $5, $6)
    on conflict (player_id, hero_id) do update set copies = $3, level = $4, shards = $5, promotion = $6`,
  [id, hero, o.copies ?? 1, o.level ?? 1, o.shards ?? 0, o.promotion ?? 0])
const row = async (id: string, hero: string) =>
  (await S.db.query('select copies, level, shards, promotion from player_heroes where player_id = $1 and hero_id = $2', [id, hero]))[0]
const promote = (token: string, body: unknown) => S.req('POST', '/v1/hero/promote', { token, body })
const logs = async (id: string) => S.db.query("select detail from economy_log where player_id = $1 and kind = 'promote' order by id", [id])

test('비용 표: 승급 p → p+1 조각 = 5|25|50|100|200, 최대(5)는 null. 최대 레벨 = 20 + 10 × 승급(승급 5에서 70)', () => {
  assert.deepEqual([0, 1, 2, 3, 4, 5, 9].map((p) => R.promoteCost(p, CFG)), [5, 25, 50, 100, 200, null, null])
  assert.deepEqual([0, 1, 2, 3, 4, 5].map((p) => R.heroMaxLevel(p, CFG)), [20, 30, 40, 50, 60, 70])
  assert.equal(R.MAX_PROMOTION, 5)
  assert.throws(() => R.promoteCost(0, { promote_shards: 'x|25' }), /promote_shards/)
})

test('승급 성공: 조각 −비용, 승급 +1(다른 값은 그대로), 응답 = 플레이어 응답 + promotion, heroes {copies, level, shards, promotion}, 로그', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setHero(id, 'hans', { copies: 13, shards: 12, level: 7 })
  let r = await promote(token, { hero_id: 'hans' })
  assert.equal(r.status, 200)
  assert.equal(r.json.promotion, 1)
  assert.deepEqual(r.json.player.heroes.hans, { copies: 13, level: 7, shards: 7, promotion: 1 })
  assert.deepEqual(r.json.player.heroes.ella, { copies: 1, level: 1, shards: 0, promotion: 0 })
  assert.deepEqual(await row(id, 'hans'), { copies: 13, level: 7, shards: 7, promotion: 1 })
  await setHero(id, 'hans', { copies: 13, shards: 25, level: 7, promotion: 1 }) // 1 → 2는 정확히 25
  r = await promote(token, { hero_id: 'hans' })
  assert.deepEqual([r.status, r.json.promotion, r.json.player.heroes.hans.shards], [200, 2, 0])
  const p = (await S.req('GET', '/v1/player', { token })).json.player
  assert.deepEqual(p.heroes.hans, { copies: 13, level: 7, shards: 0, promotion: 2 })
  const l = await logs(id)
  assert.deepEqual(l.map((x) => x.detail), [
    { hero_id: 'hans', from: 0, to: 1, shards: 5, shards_before: 12, shards_after: 7 },
    { hero_id: 'hans', from: 1, to: 2, shards: 25, shards_before: 25, shards_after: 0 },
  ])
})

test('조각 부족은 409 not_enough_shards, 최대 승급은 409 max_promotion(조각이 많아도) — 아무것도 안 바뀐다. 404·400·401', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setHero(id, 'nina', { shards: 24, promotion: 1 }) // 1 → 2는 25
  let r = await promote(token, { hero_id: 'nina' })
  assert.deepEqual([r.status, r.json.error], [409, 'not_enough_shards'])
  await setHero(id, 'dorik', { shards: 4 })
  assert.deepEqual((await promote(token, { hero_id: 'dorik' })).json.error, 'not_enough_shards')
  await setHero(id, 'ella', { shards: 9999, promotion: 5 })
  r = await promote(token, { hero_id: 'ella' })
  assert.deepEqual([r.status, r.json.error], [409, 'max_promotion'])
  assert.deepEqual([await row(id, 'nina'), await row(id, 'dorik'), await row(id, 'ella')], [
    { copies: 1, level: 1, shards: 24, promotion: 1 }, { copies: 1, level: 1, shards: 4, promotion: 0 }, { copies: 1, level: 1, shards: 9999, promotion: 5 }])
  assert.equal((await logs(id)).length, 0)
  for (const hero of ['arteon', 'ghost', '__proto__', 'constructor']) {
    r = await promote(token, { hero_id: hero })
    assert.deepEqual([r.status, r.json.error], [404, 'not_owned'], hero)
  }
  await S.db.query("insert into player_heroes (player_id, hero_id, copies, shards) values ($1, 'retired_hero', 9, 99)", [id])
  assert.equal((await promote(token, { hero_id: 'retired_hero' })).status, 404) // 표에서 빠진 영웅
  for (const body of [{}, { hero_id: '' }, { hero_id: 5 }, { hero_id: null }]) {
    assert.equal((await promote(token, body)).status, 400, JSON.stringify(body))
  }
  assert.equal((await S.req('POST', '/v1/hero/promote', { body: { hero_id: 'hans' } })).status, 401)
})

test('최대 레벨은 승급 기준: 승급 0은 20(넘으면 409 max_level), 승급하면 30까지. copies(중복)는 상한과 무관', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await S.db.query('update player_state set gold_tenths = 100000000 where player_id = $1', [id])
  await setHero(id, 'hans', { copies: 9, shards: 8, level: 20 }) // 옛 규칙이면 별 5 → 70
  const lv = (count: number) => S.req('POST', '/v1/hero/levelup', { token, body: { hero_id: 'hans', count } })
  let r = await lv(1)
  assert.deepEqual([r.status, r.json.error], [409, 'max_level'])
  assert.equal((await promote(token, { hero_id: 'hans' })).status, 200)
  r = await lv(10)
  assert.deepEqual([r.status, r.json.level, r.json.player.heroes.hans], [200, 30, { copies: 9, level: 30, shards: 3, promotion: 1 }])
  assert.equal((await lv(1)).json.error, 'max_level')
})

test('모집 중복 → 조각 +1(결과 shards), 새 영웅은 조각 0. 골드 10연차 같은 영웅 10장 = 새 1장 + 조각 9', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await S.db.query('update player_state set gold_tenths = 30000 where player_id = $1', [id])
  rand.next = [0.5, 0] // R 풀 첫째 = hans(보유)
  let r = await S.req('POST', '/v1/gacha', { token, body: { count: 1 } })
  assert.deepEqual(r.json.results, [{ hero_id: 'hans', grade: 'R', new: false, copies: 2, shards: 1 }])
  assert.deepEqual(r.json.player.heroes.hans, { copies: 2, level: 1, shards: 1, promotion: 0 })
  await S.db.query('update player_state set gold_tenths = 300000 where player_id = $1', [id])
  rand.next = Array(30).fill(0.99) // 전부 R 풀 마지막 = tia(새로) — 골드 10연차는 SR 보장이 없다
  r = await S.req('POST', '/v1/gacha', { token, body: { count: 10 } })
  assert.deepEqual(r.json.results.map((x: any) => [x.hero_id, x.new, x.copies, x.shards]), Array.from({ length: 10 }, (_, i) => ['tia', i === 0, i + 1, i]))
  assert.deepEqual([await row(id, 'tia'), await row(id, 'hans')], [{ copies: 10, level: 1, shards: 9, promotion: 0 }, { copies: 2, level: 1, shards: 1, promotion: 0 }])
  assert.deepEqual(r.json.player.heroes.tia, { copies: 10, level: 1, shards: 9, promotion: 0 })
  rand.next = []
})

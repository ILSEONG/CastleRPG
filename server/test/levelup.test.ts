// 영웅 레벨업(개정 11 §2.1·§2.2): 비용 표(1.12^(L−1) 반올림, 식량 × L), count 합계, 최대 레벨(별 반영), 404·409·400, 응답 형식, 로그.
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

const CFG = {
  hero_max_stars: '5', hero_max_level_base: '20', hero_max_level_per_star: '10',
  levelup_gold_R: '30', levelup_gold_SR: '60', levelup_gold_SSR: '120', levelup_food_R: '10', levelup_food_SR: '20', levelup_food_SSR: '40',
}
const setState = (id: string, tenths: number, food: number) => Promise.all([
  S.db.query('update player_state set gold_tenths = $2 where player_id = $1', [id, tenths]),
  S.db.query("update player_resources set amount = $2 where player_id = $1 and res = 'food'", [id, food]),
])
const setHero = (id: string, hero: string, copies: number, level: number) =>
  S.db.query('insert into player_heroes (player_id, hero_id, copies, level) values ($1, $2, $3, $4) on conflict (player_id, hero_id) do update set copies = $3, level = $4', [id, hero, copies, level])
const levelup = (token: string, body: unknown) => S.req('POST', '/v1/hero/levelup', { token, body })
const logs = async (id: string) => S.db.query("select detail from economy_log where player_id = $1 and kind = 'levelup' order by id", [id])

test('비용 표: 골드 = round(등급 값 × 1.12^(L−1)), 식량 = 등급 값 × L. count는 합계. 최대 레벨 = 20 + 10 × 별(별 5에서 70)', () => {
  const one = (g: string, l: number) => R.levelupCost(g, l, 1, CFG)
  assert.deepEqual([1, 2, 3, 4, 5, 10, 19, 20].map((l) => one('R', l).gold), [30, 34, 38, 42, 47, 83, 231, 258])
  assert.deepEqual([1, 2, 3, 10, 19].map((l) => one('SR', l).gold), [60, 67, 75, 166, 461])
  assert.deepEqual([1, 2, 3, 10, 19, 69].map((l) => one('SSR', l).gold), [120, 134, 151, 333, 923, 266690])
  assert.deepEqual([one('R', 1).food, one('R', 19).food, one('SR', 3).food, one('SSR', 20).food], [10, 190, 60, 800])
  assert.deepEqual(R.levelupCost('R', 1, 5, CFG), { gold: 30 + 34 + 38 + 42 + 47, food: 10 + 20 + 30 + 40 + 50 })
  assert.deepEqual(R.levelupCost('SSR', 1, 19, CFG), { gold: 7614, food: 7600 })
  assert.deepEqual([1, 2, 6, 7, 99].map((c) => R.heroMaxLevel(c, CFG)), [20, 30, 70, 70, 70])
})

test('레벨업 1회·3회: 골드(tenths × 10)·식량을 정확히 빼고 레벨이 오른다. 응답 = 플레이어 응답 + level, heroes {copies, level}, 로그', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setState(id, 2005, 200) // 200.5골드
  let r = await levelup(token, { hero_id: 'hans', count: 1 })
  assert.equal(r.status, 200)
  assert.equal(r.json.level, 2)
  assert.deepEqual([r.json.player.gold_tenths, r.json.player.res.food, r.json.player.heroes.hans], [2005 - 300, 190, { copies: 1, level: 2 }])
  assert.deepEqual(r.json.player.heroes.ella, { copies: 1, level: 1 })
  r = await levelup(token, { hero_id: 'hans', count: 3 }) // 2→5: 34 + 38 + 42 골드, 20 + 30 + 40 식량
  assert.deepEqual([r.status, r.json.level, r.json.player.gold_tenths, r.json.player.res.food], [200, 5, 1705 - 1140, 190 - 90])
  const p = (await S.req('GET', '/v1/player', { token })).json.player
  assert.deepEqual([p.heroes.hans, p.gold_tenths, p.res.food], [{ copies: 1, level: 5 }, 565, 100])
  const l = await logs(id)
  assert.equal(l.length, 2)
  assert.deepEqual(l[1].detail, { hero_id: 'hans', from: 2, to: 5, count: 3, gold: 114, food: 90, gold_tenths: -1140 })
})

test('최대 레벨: 별 0은 20까지(넘으면 409 max_level), 별이 오르면 상한도 오른다(별 1 → 30)', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setState(id, 10_000_000, 1_000_000)
  await setHero(id, 'nina', 1, 19)
  let r = await levelup(token, { hero_id: 'nina', count: 2 })
  assert.deepEqual([r.status, r.json.error], [409, 'max_level'])
  r = await levelup(token, { hero_id: 'nina', count: 1 })
  assert.deepEqual([r.status, r.json.level], [200, 20])
  assert.deepEqual([(await levelup(token, { hero_id: 'nina', count: 1 })).json.error], ['max_level'])
  await setHero(id, 'nina', 2, 20) // 중복 하나 = 별 1
  r = await levelup(token, { hero_id: 'nina', count: 10 })
  assert.deepEqual([r.status, r.json.level], [200, 30])
  assert.equal((await levelup(token, { hero_id: 'nina', count: 1 })).status, 409)
})

test('골드나 식량이 모자라면 409 not_enough이고 아무것도 안 바뀐다. 보유하지 않은 영웅은 404, 형이 틀리면 400', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setState(id, 299, 1000) // 29.9골드 < 30
  let r = await levelup(token, { hero_id: 'hans', count: 1 })
  assert.deepEqual([r.status, r.json.error], [409, 'not_enough'])
  await setState(id, 300, 9) // 식량 9 < 10
  assert.deepEqual((await levelup(token, { hero_id: 'hans', count: 1 })).json.error, 'not_enough')
  await setState(id, 300 + 339, 29) // 2회분 골드는 있지만 식량은 1회분(10 + 20 > 29)
  assert.deepEqual((await levelup(token, { hero_id: 'hans', count: 2 })).json.error, 'not_enough')
  const p = (await S.req('GET', '/v1/player', { token })).json.player
  assert.deepEqual([p.gold_tenths, p.res.food, p.heroes.hans], [639, 29, { copies: 1, level: 1 }])
  assert.equal((await logs(id)).length, 0)
  for (const hero of ['arteon', 'ghost', '__proto__', 'constructor']) {
    r = await levelup(token, { hero_id: hero, count: 1 })
    assert.deepEqual([r.status, r.json.error], [404, 'not_owned'], hero)
  }
  for (const body of [{ hero_id: 'hans', count: 0 }, { hero_id: 'hans', count: 101 }, { hero_id: 'hans', count: 1.5 }, { hero_id: 'hans', count: '1' },
    { hero_id: 'hans' }, { count: 1 }, { hero_id: '', count: 1 }, { hero_id: 5, count: 1 }]) {
    assert.equal((await levelup(token, body)).status, 400, JSON.stringify(body))
  }
  assert.equal((await levelup(token, { hero_id: 'hans', count: 100 })).json.error, 'max_level') // 100은 받는다(상한에 걸림)
  assert.equal((await S.req('POST', '/v1/hero/levelup', { body: { hero_id: 'hans', count: 1 } })).status, 401)
})

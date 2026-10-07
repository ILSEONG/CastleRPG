// 영웅 레벨업(개정 11 §2.1·§2.2): 비용 표(1.16^(L−1) 반올림, 골드만 — 개정 12), count 합계, 최대 레벨(승급 반영 — 개정 15), 404·409·400, 응답 형식, 로그.
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
  hero_max_level_base: '20', hero_max_level_per_promotion: '10',
  levelup_gold_R: '30', levelup_gold_SR: '60', levelup_gold_SSR: '120',
}
const setState = (id: string, tenths: number, food = -1) => Promise.all([
  S.db.query('update player_state set gold_tenths = $2 where player_id = $1', [id, tenths]),
  food < 0 ? null : S.db.query("update player_resources set amount = $2 where player_id = $1 and res = 'food'", [id, food]),
])
const setHero = (id: string, hero: string, promotion: number, level: number) =>
  S.db.query('insert into player_heroes (player_id, hero_id, promotion, level) values ($1, $2, $3, $4) on conflict (player_id, hero_id) do update set promotion = $3, level = $4', [id, hero, promotion, level])
const levelup = (token: string, body: unknown) => S.req('POST', '/v1/hero/levelup', { token, body })
const logs = async (id: string) => S.db.query("select detail from economy_log where player_id = $1 and kind = 'levelup' order by id", [id])

test('비용 표: 골드 = round(등급 값 × 1.16^(L−1)), 식량 없음. count는 합계. 최대 레벨 = 20 + 10 × 승급(승급 5에서 70)', () => {
  const one = (g: string, l: number) => R.levelupCost(g, l, 1, CFG)
  assert.deepEqual([1, 2, 3, 4, 5, 10, 19, 20].map((l) => one('R', l).gold), [30, 35, 40, 47, 54, 114, 434, 503])
  assert.deepEqual([1, 2, 3, 10, 19].map((l) => one('SR', l).gold), [60, 70, 81, 228, 868])
  assert.deepEqual([1, 2, 3, 10, 19, 69].map((l) => one('SSR', l).gold), [120, 139, 161, 456, 1736, 2899509])
  assert.deepEqual(R.levelupCost('R', 1, 5, CFG), { gold: 30 + 35 + 40 + 47 + 54 })
  assert.deepEqual(R.levelupCost('SSR', 1, 19, CFG), { gold: 11830 })
  assert.deepEqual([0, 1, 2, 5].map((p) => R.heroMaxLevel(p, CFG)), [20, 30, 40, 70])
})

test('레벨업 1회·3회: 골드(tenths × 10)만 정확히 빼고(식량은 그대로) 레벨이 오른다. 응답 = 플레이어 응답 + level, heroes {copies, level, shards, promotion}, 로그', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setState(id, 2005, 200) // 200.5골드, 식량 200(안 줄어야 한다)
  let r = await levelup(token, { hero_id: 'hans', count: 1 })
  assert.equal(r.status, 200)
  assert.equal(r.json.level, 2)
  assert.deepEqual([r.json.player.gold_tenths, r.json.player.res.food, r.json.player.heroes.hans], [2005 - 300, 200, { copies: 1, level: 2, shards: 0, promotion: 0 }])
  assert.deepEqual(r.json.player.heroes.ella, { copies: 1, level: 1, shards: 0, promotion: 0 })
  r = await levelup(token, { hero_id: 'hans', count: 3 }) // 2→5: 35 + 40 + 47 골드
  assert.deepEqual([r.status, r.json.level, r.json.player.gold_tenths, r.json.player.res.food], [200, 5, 1705 - 1220, 200])
  const p = (await S.req('GET', '/v1/player', { token })).json.player
  assert.deepEqual([p.heroes.hans, p.gold_tenths, p.res.food], [{ copies: 1, level: 5, shards: 0, promotion: 0 }, 485, 200])
  const l = await logs(id)
  assert.equal(l.length, 2)
  assert.deepEqual(l[1].detail, { hero_id: 'hans', from: 2, to: 5, count: 3, gold: 122, gold_tenths: -1220 })
})

test('최대 레벨: 승급 0은 20까지(넘으면 409 max_level), 승급이 오르면 상한도 오른다(승급 1 → 30)', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setState(id, 10_000_000, 1_000_000)
  await setHero(id, 'nina', 0, 19)
  let r = await levelup(token, { hero_id: 'nina', count: 2 })
  assert.deepEqual([r.status, r.json.error], [409, 'max_level'])
  r = await levelup(token, { hero_id: 'nina', count: 1 })
  assert.deepEqual([r.status, r.json.level], [200, 20])
  assert.deepEqual([(await levelup(token, { hero_id: 'nina', count: 1 })).json.error], ['max_level'])
  await setHero(id, 'nina', 1, 20) // 승급 1
  r = await levelup(token, { hero_id: 'nina', count: 10 })
  assert.deepEqual([r.status, r.json.level], [200, 30])
  assert.equal((await levelup(token, { hero_id: 'nina', count: 1 })).status, 409)
})

test('식량이 0이어도 골드만 있으면 레벨업된다(개정 12)', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setState(id, 1000, 0)
  const r = await levelup(token, { hero_id: 'hans', count: 1 })
  assert.deepEqual([r.status, r.json.level, r.json.player.gold_tenths, r.json.player.res.food ?? 0], [200, 2, 700, 0])
})

test('골드가 모자라면 409 not_enough_gold이고(식량이 아무리 많아도) 아무것도 안 바뀐다. 보유하지 않은 영웅은 404, 형이 틀리면 400', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setState(id, 299, 1000) // 29.9골드 < 30
  let r = await levelup(token, { hero_id: 'hans', count: 1 })
  assert.deepEqual([r.status, r.json.error], [409, 'not_enough_gold'])
  await setState(id, 300 + 339, 0) // 3회분 골드가 없다(30 + 35 + 40 = 105 > 63.9)
  assert.deepEqual((await levelup(token, { hero_id: 'hans', count: 3 })).json.error, 'not_enough_gold')
  const p = (await S.req('GET', '/v1/player', { token })).json.player
  assert.deepEqual([p.gold_tenths, p.res.food, p.heroes.hans], [639, 0, { copies: 1, level: 1, shards: 0, promotion: 0 }])
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

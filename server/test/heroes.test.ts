// 영웅(개정 10 §3.6·§3.7): 시작 영웅, 모집(비용·409·결과·copies·조각(개정 15)·10연차 보장·확률), 배치 검증. 난수는 주입(rand.next).
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import { createApp } from '../src/app.ts'
import { migrate, openDb } from '../src/db.ts'
import * as R from '../src/rules.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
const rand = { next: [] as number[] } // 비면 암호학적 난수
before(async () => {
  S = await setup({ random: () => rand.next.shift() ?? R.cryptoRandom() })
})
after(async () => {
  await S.close()
})

const STARTERS = ['hans', 'ella', 'dorik', 'nina']
// 응답 heroes {id: {copies, level, shards, promotion}}(개정 11·15) → {id: copies}
const copiesOf = (h: Record<string, { copies: number }>) => Object.fromEntries(Object.entries(h).map(([k, v]) => [k, v.copies]))
const setGold = (id: string, tenths: number) => S.db.query('update player_state set gold_tenths = $2 where player_id = $1', [id, tenths])
const logs = async (id: string, kind: string) => S.db.query('select detail from economy_log where player_id = $1 and kind = $2 order by id', [id, kind])
const gacha = (token: string, count: unknown) => S.req('POST', '/v1/gacha', { token, body: { count } })
const deploy = (token: string, d: unknown) => S.req('POST', '/v1/deploy', { token, body: { deploy: d } })

test('새 플레이어: 시작 영웅 4종 copies 1, 배치 = 시작 영웅 순서. 다시 로그인해도 그대로', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  const p = (await S.req('GET', '/v1/player', { token })).json.player
  assert.deepEqual(copiesOf(p.heroes), { hans: 1, ella: 1, dorik: 1, nina: 1 })
  assert.deepEqual(p.deploy, STARTERS)
  const rows = await S.db.query('select hero_id, copies from player_heroes where player_id = $1 order by hero_id', [id])
  assert.deepEqual(rows, [{ hero_id: 'dorik', copies: 1 }, { hero_id: 'ella', copies: 1 }, { hero_id: 'hans', copies: 1 }, { hero_id: 'nina', copies: 1 }])
  await deploy(token, ['nina', null, 'hans', null])
  const dev = (await S.db.query('select device_id from players where id = $1', [id]))[0].device_id
  await S.login(dev) // 기존 플레이어: 시작 영웅을 다시 주거나 배치를 되돌리지 않는다
  const again = (await S.req('GET', '/v1/player', { token })).json.player
  assert.deepEqual([copiesOf(again.heroes), again.deploy], [{ hans: 1, ella: 1, dorik: 1, nina: 1 }, ['nina', null, 'hans', null]])
})

test('모집 1회: floor(gold) ≥ 300이면 tenths 3000 차감(소수는 남음), 결과 {hero_id, grade, new, copies}, 중복은 copies +1, economy_log', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setGold(id, 3005)
  rand.next = [0.5, 0] // R(0.5 ≥ 0.03 + 0.17), R 풀 첫째 = hans(이미 보유)
  let r = await gacha(token, 1)
  assert.equal(r.status, 200)
  assert.deepEqual(r.json.results, [{ hero_id: 'hans', grade: 'R', new: false, copies: 2, shards: 1 }])
  assert.deepEqual([r.json.player.gold_tenths, r.json.player.gold, r.json.player.heroes.hans.copies], [5, 0, 2])
  await setGold(id, 3000)
  rand.next = [0.02, 0] // SSR(< 0.03), SSR 풀 첫째 = arteon(새로)
  r = await gacha(token, 1)
  assert.deepEqual(r.json.results, [{ hero_id: 'arteon', grade: 'SSR', new: true, copies: 1, shards: 0 }])
  assert.deepEqual([r.json.player.gold_tenths, r.json.player.heroes.arteon.copies], [0, 1])
  rand.next = [0.19, 0.99] // SR 경계(0.03 ≤ r < 0.2), SR 풀 마지막 = felix
  await setGold(id, 3000)
  assert.deepEqual((await gacha(token, 1)).json.results, [{ hero_id: 'felix', grade: 'SR', new: true, copies: 1, shards: 0 }])
  const p = (await S.req('GET', '/v1/player', { token })).json.player
  assert.deepEqual(copiesOf(p.heroes), { hans: 2, ella: 1, dorik: 1, nina: 1, arteon: 1, felix: 1 })
  const l = await logs(id, 'gacha')
  assert.equal(l.length, 3)
  assert.deepEqual([l[0].detail.count, l[0].detail.cost, l[0].detail.gold_tenths, l[0].detail.results], [1, 300, -3000, [{ hero_id: 'hans', grade: 'R', new: false, copies: 2, shards: 1 }]])
})

test('모집: 골드 부족(floor 299)은 409 not_enough_gold이고 아무것도 안 바뀐다. count가 1·10이 아니면 400', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setGold(id, 2999)
  const r = await gacha(token, 1)
  assert.deepEqual([r.status, r.json.error], [409, 'not_enough_gold'])
  await setGold(id, 26999)
  assert.equal((await gacha(token, 10)).status, 409)
  const p = (await S.req('GET', '/v1/player', { token })).json.player
  assert.deepEqual([p.gold_tenths, copiesOf(p.heroes)], [26999, { hans: 1, ella: 1, dorik: 1, nina: 1 }])
  assert.equal((await logs(id, 'gacha')).length, 0)
  for (const count of [0, 2, 5, 11, '1', 1.5, null]) assert.equal((await gacha(token, count)).status, 400, String(count))
  assert.equal((await S.req('POST', '/v1/gacha', { token, body: {} })).status, 400)
})

test('10연차: 2700(tenths 27000) 차감, 10장, SR 이상이 없으면 마지막 1장을 SR로 바꾼다, 같은 영웅은 장마다 copies 누적', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setGold(id, 27007)
  rand.next = Array(30).fill(0.99) // 전부 R, R 풀 마지막 = jack. 보장: SR 풀 마지막 = felix
  const r = await gacha(token, 10)
  assert.equal(r.status, 200)
  const res = r.json.results
  assert.equal(res.length, 10)
  assert.deepEqual(res.slice(0, 9).map((x: any) => [x.hero_id, x.new, x.copies]), Array.from({ length: 9 }, (_, i) => ['jack', i === 0, i + 1]))
  assert.deepEqual(res[9], { hero_id: 'felix', grade: 'SR', new: true, copies: 1, shards: 0 })
  assert.deepEqual([r.json.player.gold_tenths, r.json.player.heroes.jack.copies, r.json.player.heroes.felix.copies], [7, 9, 1])
  rand.next = []
})

test('확률(10만 회 표본, 암호학적 난수): SSR 3% ± 0.4%, SR 17% ± 0.8%, 등급 안 균등. 10연차 표본은 모두 SR 이상 1장 이상', async () => {
  const cfg = Object.fromEntries((await S.db.query('select key, value from game_config')).map((x) => [x.key, x.value]))
  const heroes = await S.db.query('select id, grade from heroes')
  const n = 100_000
  const out = R.rollGacha(n, heroes as { id: string; grade: string }[], cfg, R.cryptoRandom)
  const count = (g: string) => out.filter((x) => x.grade === g).length / n
  assert.ok(Math.abs(count('SSR') - 0.03) <= 0.004, `SSR ${count('SSR')}`)
  assert.ok(Math.abs(count('SR') - 0.17) <= 0.008, `SR ${count('SR')}`)
  const rs = heroes.filter((h) => h.grade === 'R').map((h) => h.id)
  for (const id of rs) {
    const share = out.filter((x) => x.id === id).length / n / 0.8
    assert.ok(Math.abs(share - 1 / rs.length) <= 0.01, `R ${id} share ${share}`)
  }
  for (let i = 0; i < 2000; i++) {
    const ten = R.rollGacha(10, heroes as { id: string; grade: string }[], cfg, R.cryptoRandom)
    assert.ok(ten.length === 10 && ten.some((x) => x.grade !== 'R'), JSON.stringify(ten))
  }
  for (let i = 0; i < 10; i++) assert.ok(R.cryptoRandom() >= 0 && R.cryptoRandom() < 1)
})

test('배치: 저장되고 다시 읽으면 그대로. 길이·보유·중복·형이 틀리면 400 bad_deploy, null은 여러 개', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  let r = await deploy(token, ['nina', null, 'hans', null])
  assert.equal(r.status, 200)
  assert.deepEqual(r.json.player.deploy, ['nina', null, 'hans', null])
  assert.deepEqual((await S.req('GET', '/v1/player', { token })).json.player.deploy, ['nina', null, 'hans', null])
  for (const bad of [
    ['hans', 'ella', 'dorik'], ['hans', 'ella', 'dorik', 'nina', null], [], // 길이
    ['arteon', null, null, null], ['ghost', null, null, null], ['__proto__', null, null, null], ['constructor', null, null, null], // 보유·표
    ['hans', 'hans', null, null], // 중복
    'hans', { 0: 'hans' }, [1, null, null, null], ['', null, null, null], null, // 형
  ]) {
    const b = await deploy(token, bad)
    assert.deepEqual([b.status, b.json.error], [400, 'bad_deploy'], JSON.stringify(bad))
  }
  assert.deepEqual((await S.req('GET', '/v1/player', { token })).json.player.deploy, ['nina', null, 'hans', null])
  r = await deploy(token, [null, null, null, null])
  assert.deepEqual(r.json.player.deploy, [null, null, null, null])
  await setGold(id, 3000)
  rand.next = [0.02, 0.1] // SSR 풀 둘째 = ignis
  assert.equal((await gacha(token, 1)).json.results[0].hero_id, 'ignis')
  r = await deploy(token, ['ignis', 'ella', 'dorik', 'nina'])
  assert.deepEqual(r.json.player.deploy, ['ignis', 'ella', 'dorik', 'nina'])
  // 성채가 단계를 넘으면 슬롯이 늘고(keep_slot_tiers 1:4|5:8|10:12) 응답 배치는 null로 채운다. 요청 길이도 그 수여야 한다
  await S.db.query("update player_buildings set level = 5 where player_id = $1 and building = 'keep'", [id])
  r = await S.req('GET', '/v1/player', { token })
  assert.deepEqual(r.json.player.deploy, ['ignis', 'ella', 'dorik', 'nina', null, null, null, null])
  assert.equal((await deploy(token, ['ignis', 'ella', 'dorik', 'nina'])).status, 400)
  assert.equal((await deploy(token, ['ignis', 'ella', 'dorik', 'nina', 'hans', null, null, null])).status, 200)
})

test('응답: 표에서 빠진 영웅은 heroes·deploy에서 거른다(보유 기록은 남는다)', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await S.db.query("insert into player_heroes (player_id, hero_id, copies) values ($1, 'retired_hero', 2)", [id])
  await S.db.query(`update player_state set deploy = '["retired_hero", "ella", null, "nina"]'::jsonb where player_id = $1`, [id])
  const p = (await S.req('GET', '/v1/player', { token })).json.player
  assert.deepEqual([copiesOf(p.heroes), p.deploy], [{ hans: 1, ella: 1, dorik: 1, nina: 1 }, [null, 'ella', null, 'nina']])
})

test('시드 전 DB(마이그레이션만): 새 플레이어도 스펙 기본 시작 영웅 4종과 그 순서의 배치를 받는다(마이그레이션 005와 같은 기본값)', async () => {
  const d = await openDb({})
  try {
    await migrate(d)
    const app = createApp({ query: d.query, now: () => T0, jwtSecret: 'test-secret-0123456789abcdef0123456789' })
    const res = await app.request('/v1/auth/guest', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ device_id: 'unseeded-db-device-0001' }) })
    assert.equal(res.status, 200)
    const id = (await res.json()).player_id
    const [s] = await d.query('select deploy from player_state where player_id = $1', [id])
    assert.deepEqual(s.deploy, STARTERS)
    const h = await d.query('select hero_id, copies from player_heroes where player_id = $1 order by hero_id', [id])
    assert.deepEqual(h.map((r) => `${r.hero_id}:${r.copies}`), ['dorik:1', 'ella:1', 'hans:1', 'nina:1'])
  } finally {
    await d.close()
  }
})

// 개정 23 모집: 골드 모집 레벨(비용·확률·누적 레벨업), 다이아(비용·확률·천장 50), 409·원자성, 테스트 훅, 마이그레이션 015, 하위 호환.
import assert from 'node:assert/strict'
import { cpSync, mkdtempSync, readdirSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { after, before, test } from 'node:test'
import { MIGRATIONS_DIR, migrate, openDb } from '../src/db.ts'
import * as R from '../src/rules.ts'
import { barrier, setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
let CFG: R.Config
let HEROES: { id: string; grade: string }[]
const rand = { next: [] as number[] } // 비면 암호학적 난수
const tmp: string[] = []
before(async () => {
  S = await setup({ random: () => rand.next.shift() ?? R.cryptoRandom() })
  CFG = Object.fromEntries((await S.db.query('select key, value from game_config')).map((x) => [x.key, x.value]))
  HEROES = (await S.db.query('select id, grade from heroes')) as { id: string; grade: string }[]
})
after(async () => {
  await S.close()
  for (const d of tmp) rmSync(d, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 })
})

const gacha = (token: string, body: Record<string, unknown>) => S.req('POST', '/v1/gacha', { token, body })
const setState = (id: string, sql: string, v: number) => S.db.query(`update player_state set ${sql} = $2 where player_id = $1`, [id, v])
const share = (out: { grade: string }[], g: string) => out.filter((x) => x.grade === g).length / out.length
const near = (a: number, b: number) => Math.abs(a - b) < 1e-9

test('골드 비용·확률 공식: 1회 = 10000 × 1.25^(L−1)을 50 단위로(L1 10,000 · L2 12,500 · L5 24,400 · L10 74,500), 10회 = × 10(할인 없음), SSR 0.55% + 0.05%p·SR 5% + 0.5%p(L10 1% · 9.5%), 주점 레벨 보너스 없음', () => {
  assert.deepEqual([1, 2, 5, 10].map((l) => R.gachaCost(CFG, 'gold', 1, l)), [10000, 12500, 24400, 74500])
  assert.deepEqual([1, 10].map((l) => R.gachaCost(CFG, 'gold', 10, l)), [100000, 745000])
  assert.equal(R.gachaCost(CFG, 'gold', 1, 11), 74500) // 최대 레벨 넘는 값은 최대로
  const l4 = R.gachaRates(CFG, 'gold', 4)
  const l10 = R.gachaRates(CFG, 'gold', 10)
  assert.ok(near(l4.ssr, 0.007) && near(l4.sr, 0.065) && near(l10.ssr, 0.01) && near(l10.sr, 0.095), JSON.stringify([l4, l10]))
  for (const l of [1, 2]) assert.equal(R.gachaRates(CFG, 'gold', l).ssr, 0) // SSR은 골드 Lv 3부터(주점 보너스도 없음)
  assert.ok(near(R.gachaRates(CFG, 'gold', 3).ssr, 0.0065))
  const t3 = R.gachaRates(CFG, 'gold', 10) // 주점 레벨 보너스 없음(2026-10-18)
  assert.ok(near(t3.ssr, 0.01) && near(t3.sr, 0.095), JSON.stringify(t3))
  assert.deepEqual([R.gachaCost(CFG, 'diamond', 1, 7), R.gachaCost(CFG, 'diamond', 10, 7)], [300, 2700]) // 다이아는 레벨 없음
  const d = R.gachaRates(CFG, 'diamond', 10)
  assert.ok(near(d.ssr, 0.05) && near(d.sr, 0.3), JSON.stringify(d))
})

test('골드 레벨업: 그 레벨 누적 ≥ 40 × L²이면 L+1, 남은 횟수는 넘기고 한 번에 여러 레벨, 최대 10(누적 0)', () => {
  assert.deepEqual([1, 2, 3, 9, 10].map((l) => R.goldNext(CFG, l)), [40, 160, 360, 3240, null])
  assert.deepEqual(R.goldLevelUp(CFG, 1, 39, 1), { level: 2, pulls: 0 })
  assert.deepEqual(R.goldLevelUp(CFG, 1, 38, 1), { level: 1, pulls: 39 })
  assert.deepEqual(R.goldLevelUp(CFG, 1, 35, 10), { level: 2, pulls: 5 }) // 넘김
  assert.deepEqual(R.goldLevelUp(CFG, 1, 0, 200), { level: 3, pulls: 0 }) // 40 + 160
  assert.deepEqual(R.goldLevelUp(CFG, 1, 0, 5000), { level: 7, pulls: 1360 }) // 40 + … + 1440 = 3640, 남은 1360 < 1960
  assert.deepEqual(R.goldLevelUp(CFG, 9, 3235, 10), { level: 10, pulls: 0 })
  assert.deepEqual(R.goldLevelUp(CFG, 10, 0, 10), { level: 10, pulls: 0 })
})

test('확률 표본(10만 장, 암호학적 난수): 골드 Lv 10은 SSR 1% · SR 9.5%(허용 오차 약 6.5σ), 다이아는 SSR 5% · SR 30%(천장 없이) — 다이아가 골드 최대 레벨보다 좋다', () => {
  const n = 100_000
  const gold = R.rollGacha(n, HEROES, CFG, R.cryptoRandom, R.gachaRates(CFG, 'gold', 10))
  assert.ok(Math.abs(share(gold, 'SSR') - 0.01) <= 0.0025 && Math.abs(share(gold, 'SR') - 0.095) <= 0.006, `gold L10 ${share(gold, 'SSR')} ${share(gold, 'SR')}`)
  const dia = R.rollGacha(n, HEROES, CFG, R.cryptoRandom, R.gachaRates(CFG, 'diamond', 1))
  assert.ok(Math.abs(share(dia, 'SSR') - 0.05) <= 0.004 && Math.abs(share(dia, 'SR') - 0.3) <= 0.008, `diamond ${share(dia, 'SSR')} ${share(dia, 'SR')}`)
  const g = R.gachaRates(CFG, 'gold', 10)
  const dr = R.gachaRates(CFG, 'diamond', 1)
  assert.ok(dr.ssr > g.ssr && dr.sr > g.sr, JSON.stringify([dr, g]))
  const l1 = R.rollGacha(n, HEROES, CFG, R.cryptoRandom) // 기본 = 골드 Lv 1
  assert.ok(share(l1, 'SSR') === 0 && Math.abs(share(l1, 'SR') - 0.05) <= 0.0045, `gold L1 ${share(l1, 'SSR')} ${share(l1, 'SR')}`)
})

test('천장 없음(2026-10-30 사용자 "SSR, UR 천장 없애주고"): 다이아로 R만 200장 뽑아도 1회 모집은 전부 R, 10연차는 SR 이상 1장 보장만', () => {
  const allR = () => 0.99
  const dia = R.gachaRates(CFG, 'diamond', 1)
  assert.ok(R.rollGacha(200, HEROES, CFG, allR, dia, true).every((x) => x.grade === 'R'))
  for (let i = 0; i < 20; i++) assert.equal(R.rollGacha(10, HEROES, CFG, allR, dia, true).map((x) => x.grade).join(''), 'RRRRRRRRRSR')
})

test('API 골드: 누적 35에서 10연차(100,000 = 1회 × 10, SR 보장 없음 — 전부 R이면 R 10장) → Lv 2·누적 5, 다음 1회는 12,500. 응답 gacha {gold_level, gold_pulls, gold_next, dia_pity}, 로그 currency·level·pity', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setState(id, 'gold_tenths', 2_000_000)
  await setState(id, 'gacha_gold_pulls', 35)
  rand.next = Array(30).fill(0.99)
  let r = await gacha(token, { count: 10 })
  assert.equal(r.status, 200)
  assert.deepEqual([r.json.player.gold, r.json.player.gacha], [200_000 - 100_000, { gold_level: 2, gold_pulls: 5, gold_next: 160, dia_pity: 0, dia_ur_pity: 0 }])
  assert.equal(r.json.results.map((x: any) => x.grade).join(''), 'RRRRRRRRRR') // 골드 10연차는 SR 이상 보장이 없다
  rand.next = [0.99, 0]
  r = await gacha(token, { count: 1, currency: 'gold' })
  assert.deepEqual([r.json.player.gold, r.json.player.gacha.gold_pulls], [100_000 - 12_500, 6])
  const l = await S.db.query("select detail from economy_log where player_id = $1 and kind = 'gacha' order by id", [id])
  assert.deepEqual(l.map((x) => [x.detail.currency, x.detail.level, x.detail.cost, x.detail.after]),
    [['gold', 1, 100000, { gold_level: 2, gold_pulls: 5 }], ['gold', 2, 12500, { gold_level: 2, gold_pulls: 6 }]])
  // 다시 읽어도 그대로(서버 저장)
  assert.deepEqual((await S.req('GET', '/v1/player', { token })).json.player.gacha, { gold_level: 2, gold_pulls: 6, gold_next: 160, dia_pity: 0, dia_ur_pity: 0 })
  rand.next = []
})

test('API 다이아: 훅으로 3,000 → 1회 300, 저장된 옛 천장 카운터가 49여도 R은 R(천장 없음, 2026-10-30), 10연차 2,700. 부족하면 409 not_enough_diamonds, 이상한 currency는 400', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  let r = await S.req('POST', '/v1/test/grant_diamonds', { token, body: { amount: 3000 } })
  assert.deepEqual([r.status, r.json.player.diamonds], [200, 3000])
  rand.next = [0.99, 0]
  r = await gacha(token, { count: 1, currency: 'diamond' })
  assert.deepEqual([r.json.player.diamonds, r.json.player.gacha.dia_pity, r.json.player.gacha.gold_pulls, r.json.player.gold_tenths], [2700, 0, 0, 0])
  await setState(id, 'gacha_dia_pity', 49)
  await setState(id, 'gacha_dia_ur_pity', 199)
  rand.next = [0.99, 0]
  r = await gacha(token, { count: 1, currency: 'diamond' })
  assert.deepEqual([r.json.results[0].grade, r.json.player.diamonds], ['R', 2400])
  // 2,400 < 2,700: 409, 아무것도 안 바뀐다(골드는 많아도 다이아로 판정)
  await setState(id, 'gold_tenths', 1_000_000)
  r = await gacha(token, { count: 10, currency: 'diamond' })
  assert.deepEqual([r.status, r.json.error], [409, 'not_enough_diamonds'])
  let p = (await S.req('GET', '/v1/player', { token })).json.player
  assert.deepEqual([p.diamonds, p.gold_tenths], [2400, 1_000_000])
  await S.req('POST', '/v1/test/grant_diamonds', { token, body: { amount: 300 } })
  rand.next = Array(30).fill(0.99) // 전부 R → 10연차 보장 SR 1장
  r = await gacha(token, { count: 10, currency: 'diamond' })
  assert.deepEqual([r.json.player.diamonds, r.json.results.map((x: any) => x.grade).join('')], [0, 'RRRRRRRRRSR'])
  for (const currency of ['ruby', 1, '', 'Gold']) assert.equal((await gacha(token, { count: 1, currency })).status, 400, String(currency))
  p = (await S.req('GET', '/v1/player', { token })).json.player
  const l = await S.db.query("select detail from economy_log where player_id = $1 and kind = 'gacha' order by id", [id])
  assert.deepEqual(l.map((x) => [x.detail.currency, x.detail.cost, x.detail.diamonds, x.detail.after]),
    [['diamond', 300, -300, {}], ['diamond', 300, -300, {}], ['diamond', 2700, -2700, {}]])
  assert.deepEqual([p.gold_tenths, p.gacha.gold_level, p.gacha.gold_pulls], [1_000_000, 1, 0]) // 다이아 모집은 골드·골드 레벨과 무관
  rand.next = []
})

test('UR(2026-10-29): 다이아만 0.5%(골드 0), 0.004 < 0.005 → UR. 천장은 없다(2026-10-30)', async () => {
  assert.ok(near(R.gachaRates(CFG, 'diamond', 1).ur ?? 0, 0.005))
  for (const l of [1, 5, 10]) assert.equal(R.gachaRates(CFG, 'gold', l).ur, 0)
  const urs = HEROES.filter((h) => h.grade === 'UR').map((h) => h.id)
  assert.equal(urs.length, 6)
  const out = R.rollGacha(1, HEROES, CFG, () => 0.004, R.gachaRates(CFG, 'diamond', 1), true)
  assert.equal(out[0].grade, 'UR')
  S.clock.t = T0
  const { token } = await S.login()
  await S.req('POST', '/v1/test/grant_diamonds', { token, body: { amount: 300 } })
  rand.next = [0.004, 0]
  const r = await gacha(token, { count: 1, currency: 'diamond' })
  assert.deepEqual([r.status, r.json.results[0].grade, urs.includes(r.json.results[0].hero_id)], [200, 'UR', true])
  rand.next = []
})

test('SSR 조각 합성(2026-10-29): SSR 조각 정확히 10개 → 태생 UR 1명(새 영웅 copies 1), 조각 차감·로그 fuse. 개수가 틀리거나 등급이 섞였거나 모자라면 409, 형식이 틀리면 400', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  const fuse = (picks: unknown) => S.req('POST', '/v1/hero/fuse', { token, body: { picks } })
  await S.db.query("insert into player_heroes (player_id, hero_id, copies, shards) values ($1, 'arteon', 5, 6), ($1, 'ignis', 5, 7), ($1, 'bron', 3, 20)", [id])
  for (const bad of [null, [], {}, { arteon: 0 }, { arteon: 1.5 }, 'x']) assert.equal((await fuse(bad)).status, 400, JSON.stringify(bad))
  assert.equal((await fuse({ arteon: 6, ignis: 3 })).json.error, 'wrong_count')
  assert.equal((await fuse({ arteon: 6, ignis: 3, bron: 1 })).json.error, 'not_fusable')
  assert.equal((await fuse({ arteon: 7, ignis: 3 })).json.error, 'not_enough_shards')
  assert.equal((await fuse({ kyle: 10 })).json.error, 'not_enough_shards') // 없는 영웅
  rand.next = [0]
  const r = await fuse({ arteon: 6, ignis: 4 })
  rand.next = []
  const urs = HEROES.filter((h) => h.grade === 'UR').map((h) => h.id)
  assert.equal(r.status, 200)
  assert.deepEqual([r.json.results.length, r.json.results[0].grade, urs.includes(r.json.results[0].hero_id), r.json.results[0].new], [1, 'UR', true, true])
  const rows = await S.db.query('select hero_id, copies, shards from player_heroes where player_id = $1 order by hero_id', [id])
  const by = Object.fromEntries(rows.map((x) => [x.hero_id, [x.copies, x.shards]]))
  assert.deepEqual([by.arteon, by.ignis, by[r.json.results[0].hero_id]], [[5, 0], [5, 3], [1, 0]])
  const [l] = await S.db.query("select detail from economy_log where player_id = $1 and kind = 'fuse'", [id])
  assert.deepEqual(l.detail.picks, { arteon: 6, ignis: 4 })
})

test('등급별 합성(2026-10-30): R 조각 10개 → SR 1명, SR 조각 10개 → SSR 1명. UR 조각은 합성할 수 없다(409 not_fusable)', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  const fuse = (picks: unknown) => S.req('POST', '/v1/hero/fuse', { token, body: { picks } })
  await S.db.query("insert into player_heroes (player_id, hero_id, copies, shards) values ($1, 'hans', 3, 6), ($1, 'ella', 3, 4), ($1, 'bron', 3, 20), ($1, 'hyeonmu', 2, 10) on conflict (player_id, hero_id) do update set copies = excluded.copies, shards = excluded.shards", [id])
  assert.equal((await fuse({ hyeonmu: 10 })).json.error, 'not_fusable')
  for (const [picks, to] of [[{ hans: 6, ella: 4 }, 'SR'], [{ bron: 10 }, 'SSR']] as const) {
    rand.next = [0]
    const r = await fuse(picks)
    rand.next = []
    assert.equal(r.status, 200, JSON.stringify(r.json))
    const pool = HEROES.filter((h) => h.grade === to).map((h) => h.id)
    assert.deepEqual([r.json.results[0].grade, pool.includes(r.json.results[0].hero_id)], [to, true])
  }
  const rows = await S.db.query("select hero_id, shards from player_heroes where player_id = $1 and hero_id in ('hans', 'ella', 'bron')", [id])
  assert.deepEqual(Object.fromEntries(rows.map((x) => [x.hero_id, x.shards])), { hans: 0, ella: 0, bron: 11 }) // R 합성 결과가 첫 SR 영웅 bron(가진 영웅: 조각 +1)
})

test('하위 호환: currency가 없거나 null이면 골드 모집(Lv 1 비용 10,000, 누적 +1)', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setState(id, 'gold_tenths', 200_000)
  assert.deepEqual((await gacha(token, { count: 1 })).json.player.gacha.gold_pulls, 1)
  const r = await gacha(token, { count: 1, currency: null })
  assert.deepEqual([r.status, r.json.player.gold_tenths, r.json.player.gacha.gold_pulls, r.json.player.diamonds], [200, 0, 2, 0])
})

test('원자성: 다이아 1회분(300)으로 두 요청이 같은 version을 읽고 겨뤄도 하나만 — 200·409, 다이아 0, 천장 +1, 영웅 +1, 로그 1', async () => {
  const b = barrier()
  const T = await setup({ wrapQuery: b.wrap })
  try {
    T.clock.t = T0
    const { token, id } = await T.login()
    await T.db.query('update player_state set diamonds = 300 where player_id = $1', [id])
    b.arm()
    const [r1, r2] = await Promise.all([1, 2].map(() => T.req('POST', '/v1/gacha', { token, body: { count: 1, currency: 'diamond' } })))
    assert.equal(b.arrived(), 2, 'both requests read the same diamonds before either wrote')
    assert.deepEqual([r1.status, r2.status].sort(), [200, 409])
    assert.equal((r1.status === 409 ? r1 : r2).json.error, 'not_enough_diamonds')
    const [s] = await T.db.query('select diamonds, gacha_dia_pity from player_state where player_id = $1', [id])
    const [h] = await T.db.query('select coalesce(sum(copies), 0)::int as n from player_heroes where player_id = $1', [id])
    const [n] = await T.db.query("select count(*)::int as n from economy_log where player_id = $1 and kind = 'gacha'", [id])
    const won = r1.status === 200 ? r1 : r2
    assert.deepEqual([Number(s.diamonds), s.gacha_dia_pity, h.n, n.n, won.status], [0, 0, 5, 1, 200])
  } finally {
    await T.close()
  }
})

test('테스트 훅 grant_diamonds·grant_gold: amount 1..10억 정수(아니면 400), ALLOW_TEST_HOOKS가 없으면 404', async () => {
  S.clock.t = T0
  const { token } = await S.login()
  assert.equal((await S.req('POST', '/v1/test/grant_gold', { token, body: { amount: 90_000 } })).json.player.gold, 90_000)
  for (const amount of [0, -5, 1.5, '3', 1_000_000_001]) {
    assert.equal((await S.req('POST', '/v1/test/grant_diamonds', { token, body: { amount } })).status, 400, String(amount))
  }
  const noHooks = S.makeApp({ allowTestHooks: false })
  for (const path of ['/v1/test/grant_diamonds', '/v1/test/grant_gold']) {
    const res = await noHooks.request(path, { method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: '{"amount":10}' })
    assert.equal(res.status, 404, path)
  }
  assert.equal((await S.req('GET', '/v1/player', { token })).json.player.diamonds, 0)
})

test('마이그레이션 015: 014까지 적용된 DB의 기존 플레이어는 다이아 0·골드 Lv 1·누적 0·천장 0, 옛 모집 설정 키는 새 키로. 다이아는 0 이상', async () => {
  const all = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort()
  const dir = mkdtempSync(join(tmpdir(), 'castle-mig-'))
  tmp.push(dir)
  for (const f of all.filter((f) => f < '015')) cpSync(join(MIGRATIONS_DIR, f), join(dir, f))
  const d = await openDb({})
  try {
    await migrate(d, dir)
    const [p] = await d.query("insert into players (device_id) values ('mig-015-device-0001') returning id")
    await d.query('insert into player_state (player_id, gold_tenths) values ($1, 70)', [p.id])
    await d.query("insert into game_config (key, value) values ('gacha_cost_1', '300'), ('gacha_rate_ssr', '0.03')")
    assert.deepEqual(await migrate(d), all.filter((f) => f >= '015'))
    const [s] = await d.query('select gold_tenths, diamonds, gacha_gold_level, gacha_gold_pulls, gacha_dia_pity from player_state where player_id = $1', [p.id])
    assert.deepEqual([Number(s.gold_tenths), Number(s.diamonds), s.gacha_gold_level, s.gacha_gold_pulls, s.gacha_dia_pity], [70, 0, 1, 0, 0])
    const keys = (await d.query("select key from game_config where key like 'gacha%' order by key")).map((r) => r.key)
    assert.deepEqual(keys, ['gacha_dia_cost_1', 'gacha_dia_cost_10', 'gacha_dia_pity', 'gacha_dia_sr', 'gacha_dia_ssr', 'gacha_dia_ur', 'gacha_dia_ur_pity', 'gacha_gold_cost_base', 'gacha_gold_cost_growth',
      'gacha_gold_level_max', 'gacha_gold_level_pulls', 'gacha_gold_sr_base', 'gacha_gold_sr_step', 'gacha_gold_ssr_base', 'gacha_gold_ssr_step'])
    await assert.rejects(d.query('update player_state set diamonds = -1 where player_id = $1', [p.id]))
    await assert.rejects(d.query('update player_state set gacha_gold_level = 0 where player_id = $1', [p.id]))
  } finally {
    await d.close()
  }
})

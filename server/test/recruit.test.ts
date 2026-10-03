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

test('골드 비용·확률 공식: 1회 = 3000 × 1.15^(L−1)을 50 단위로(L1 3,000 · L2 3,450 · L5 5,250 · L10 10,550), 10회 = × 10(할인 없음), SSR 0.5% + 0.1%p·SR 5% + 0.5%p(L10 1.4% · 9.5%), 주점 보너스는 더한다', () => {
  assert.deepEqual([1, 2, 5, 10].map((l) => R.gachaCost(CFG, 'gold', 1, l)), [3000, 3450, 5250, 10550])
  assert.deepEqual([1, 10].map((l) => R.gachaCost(CFG, 'gold', 10, l)), [30000, 105500])
  assert.equal(R.gachaCost(CFG, 'gold', 1, 11), 10550) // 최대 레벨 넘는 값은 최대로
  const l4 = R.gachaRates(CFG, 'gold', 4, 1)
  const l10 = R.gachaRates(CFG, 'gold', 10, 1)
  assert.ok(near(l4.ssr, 0.008) && near(l4.sr, 0.065) && near(l10.ssr, 0.014) && near(l10.sr, 0.095), JSON.stringify([l4, l10]))
  const t3 = R.gachaRates(CFG, 'gold', 10, 3) // 주점 3: + 0.2%p · 0.6%p
  assert.ok(near(t3.ssr, 0.016) && near(t3.sr, 0.101), JSON.stringify(t3))
  assert.deepEqual([R.gachaCost(CFG, 'diamond', 1, 7), R.gachaCost(CFG, 'diamond', 10, 7)], [300, 2700]) // 다이아는 레벨 없음
  const d = R.gachaRates(CFG, 'diamond', 10, 3)
  assert.ok(near(d.ssr, 0.082) && near(d.sr, 0.306), JSON.stringify(d))
})

test('골드 레벨업: 그 레벨 누적 ≥ 30 × L이면 L+1, 남은 횟수는 넘기고 한 번에 여러 레벨, 최대 10(누적 0)', () => {
  assert.deepEqual([1, 2, 9, 10].map((l) => R.goldNext(CFG, l)), [30, 60, 270, null])
  assert.deepEqual(R.goldLevelUp(CFG, 1, 29, 1), { level: 2, pulls: 0 })
  assert.deepEqual(R.goldLevelUp(CFG, 1, 28, 1), { level: 1, pulls: 29 })
  assert.deepEqual(R.goldLevelUp(CFG, 1, 25, 10), { level: 2, pulls: 5 }) // 넘김
  assert.deepEqual(R.goldLevelUp(CFG, 1, 0, 90), { level: 3, pulls: 0 }) // 30 + 60
  assert.deepEqual(R.goldLevelUp(CFG, 1, 0, 1000), { level: 8, pulls: 160 }) // 30 + … + 210 = 840, 남은 160 < 240
  assert.deepEqual(R.goldLevelUp(CFG, 9, 265, 10), { level: 10, pulls: 0 })
  assert.deepEqual(R.goldLevelUp(CFG, 10, 0, 10), { level: 10, pulls: 0 })
})

test('확률 표본(10만 장, 암호학적 난수): 골드 Lv 10은 SSR 1.4% · SR 9.5%(허용 오차 약 6.5σ), 다이아는 SSR 8% · SR 30%(천장 없이) — 다이아가 골드 최대 레벨보다 좋다', () => {
  const n = 100_000
  const gold = R.rollGacha(n, HEROES, CFG, R.cryptoRandom, R.gachaRates(CFG, 'gold', 10, 1))
  assert.ok(Math.abs(share(gold, 'SSR') - 0.014) <= 0.0025 && Math.abs(share(gold, 'SR') - 0.095) <= 0.006, `gold L10 ${share(gold, 'SSR')} ${share(gold, 'SR')}`)
  const dia = R.rollGacha(n, HEROES, CFG, R.cryptoRandom, R.gachaRates(CFG, 'diamond', 1, 1))
  assert.ok(Math.abs(share(dia, 'SSR') - 0.08) <= 0.004 && Math.abs(share(dia, 'SR') - 0.3) <= 0.008, `diamond ${share(dia, 'SSR')} ${share(dia, 'SR')}`)
  for (const t of [1, 10, 30]) {
    const g = R.gachaRates(CFG, 'gold', 10, t)
    const dr = R.gachaRates(CFG, 'diamond', 1, t)
    assert.ok(dr.ssr > g.ssr && dr.sr > g.sr, `tavern ${t}: ${JSON.stringify([dr, g])}`)
  }
  const l1 = R.rollGacha(n, HEROES, CFG, R.cryptoRandom) // 기본 = 골드 Lv 1
  assert.ok(Math.abs(share(l1, 'SSR') - 0.005) <= 0.0015 && Math.abs(share(l1, 'SR') - 0.05) <= 0.0045, `gold L1 ${share(l1, 'SSR')} ${share(l1, 'SR')}`)
})

test('천장(결정적 난수): SSR 없이 49장이면 50번째가 SSR, 카운터는 SSR에서 0. 10연차 중간에도, 자연 SSR도 카운터를 0으로', () => {
  const allR = () => 0.99
  const pity = { n: 0, max: 50 }
  const first = R.rollGacha(49, HEROES, CFG, allR, R.gachaRates(CFG, 'diamond', 1, 1), pity)
  assert.deepEqual([first.every((x) => x.grade === 'R'), pity.n], [true, 49])
  assert.deepEqual([R.rollGacha(1, HEROES, CFG, allR, R.gachaRates(CFG, 'diamond', 1, 1), pity)[0].grade, pity.n], ['SSR', 0])
  pity.n = 45
  const ten = R.rollGacha(10, HEROES, CFG, allR, R.gachaRates(CFG, 'diamond', 1, 1), pity)
  assert.deepEqual([ten.map((x) => x.grade), pity.n], [['R', 'R', 'R', 'R', 'SSR', 'R', 'R', 'R', 'R', 'R'], 5]) // 5번째(누적 50)가 SSR
  pity.n = 30
  const seq = [0.5, 0, 0.01, 0, 0.5, 0] // R, 자연 SSR, R
  R.rollGacha(3, HEROES, CFG, () => seq.shift() ?? 0.5, R.gachaRates(CFG, 'diamond', 1, 1), pity)
  assert.equal(pity.n, 1)
})

test('API 골드: 누적 25에서 10연차(30,000 = 1회 × 10, SR 보장 없음 — 전부 R이면 R 10장) → Lv 2·누적 5, 다음 1회는 3,450. 응답 gacha {gold_level, gold_pulls, gold_next, dia_pity}, 로그 currency·level·pity', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setState(id, 'gold_tenths', 1_000_000)
  await setState(id, 'gacha_gold_pulls', 25)
  rand.next = Array(30).fill(0.99)
  let r = await gacha(token, { count: 10 })
  assert.equal(r.status, 200)
  assert.deepEqual([r.json.player.gold, r.json.player.gacha], [100_000 - 30_000, { gold_level: 2, gold_pulls: 5, gold_next: 60, dia_pity: 0 }])
  assert.equal(r.json.results.map((x: any) => x.grade).join(''), 'RRRRRRRRRR') // 골드 10연차는 SR 이상 보장이 없다
  rand.next = [0.99, 0]
  r = await gacha(token, { count: 1, currency: 'gold' })
  assert.deepEqual([r.json.player.gold, r.json.player.gacha.gold_pulls], [70_000 - 3_450, 6])
  const l = await S.db.query("select detail from economy_log where player_id = $1 and kind = 'gacha' order by id", [id])
  assert.deepEqual(l.map((x) => [x.detail.currency, x.detail.level, x.detail.cost, x.detail.after]),
    [['gold', 1, 30000, { gold_level: 2, gold_pulls: 5 }], ['gold', 2, 3450, { gold_level: 2, gold_pulls: 6 }]])
  // 다시 읽어도 그대로(서버 저장)
  assert.deepEqual((await S.req('GET', '/v1/player', { token })).json.player.gacha, { gold_level: 2, gold_pulls: 6, gold_next: 60, dia_pity: 0 })
  rand.next = []
})

test('API 다이아: 훅으로 3,000 → 1회 300(천장 +1), 천장 49에서 R만 나와도 SSR 확정 → 0, 10연차 2,700. 부족하면 409 not_enough_diamonds, 이상한 currency는 400', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  let r = await S.req('POST', '/v1/test/grant_diamonds', { token, body: { amount: 3000 } })
  assert.deepEqual([r.status, r.json.player.diamonds], [200, 3000])
  rand.next = [0.99, 0]
  r = await gacha(token, { count: 1, currency: 'diamond' })
  assert.deepEqual([r.json.player.diamonds, r.json.player.gacha.dia_pity, r.json.player.gacha.gold_pulls, r.json.player.gold_tenths], [2700, 1, 0, 0])
  await setState(id, 'gacha_dia_pity', 49)
  rand.next = [0.99, 0]
  r = await gacha(token, { count: 1, currency: 'diamond' })
  assert.deepEqual([r.json.results[0].grade, r.json.player.gacha.dia_pity, r.json.player.diamonds], ['SSR', 0, 2400])
  // 2,400 < 2,700: 409, 아무것도 안 바뀐다(골드는 많아도 다이아로 판정)
  await setState(id, 'gold_tenths', 1_000_000)
  r = await gacha(token, { count: 10, currency: 'diamond' })
  assert.deepEqual([r.status, r.json.error], [409, 'not_enough_diamonds'])
  let p = (await S.req('GET', '/v1/player', { token })).json.player
  assert.deepEqual([p.diamonds, p.gacha.dia_pity, p.gold_tenths], [2400, 0, 1_000_000])
  await S.req('POST', '/v1/test/grant_diamonds', { token, body: { amount: 300 } })
  rand.next = Array(30).fill(0.99) // 전부 R → 10연차 보장 SR 1장(SR은 천장을 되돌리지 않는다)
  r = await gacha(token, { count: 10, currency: 'diamond' })
  assert.deepEqual([r.json.player.diamonds, r.json.player.gacha.dia_pity, r.json.results.map((x: any) => x.grade).join('')], [0, 10, 'RRRRRRRRRSR'])
  for (const currency of ['ruby', 1, '', 'Gold']) assert.equal((await gacha(token, { count: 1, currency })).status, 400, String(currency))
  p = (await S.req('GET', '/v1/player', { token })).json.player
  const l = await S.db.query("select detail from economy_log where player_id = $1 and kind = 'gacha' order by id", [id])
  assert.deepEqual(l.map((x) => [x.detail.currency, x.detail.cost, x.detail.diamonds, x.detail.pity, x.detail.after]),
    [['diamond', 300, -300, 0, { dia_pity: 1 }], ['diamond', 300, -300, 49, { dia_pity: 0 }], ['diamond', 2700, -2700, 0, { dia_pity: 10 }]])
  assert.deepEqual([p.gold_tenths, p.gacha.gold_level, p.gacha.gold_pulls], [1_000_000, 1, 0]) // 다이아 모집은 골드·골드 레벨과 무관
  rand.next = []
})

test('하위 호환: currency가 없거나 null이면 골드 모집(Lv 1 비용 3,000, 누적 +1)', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  await setState(id, 'gold_tenths', 60_000)
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
    assert.deepEqual([Number(s.diamonds), s.gacha_dia_pity, h.n, n.n], [0, won.json.results[0].grade === 'SSR' ? 0 : 1, 5, 1])
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
    assert.deepEqual(keys, ['gacha_dia_cost_1', 'gacha_dia_cost_10', 'gacha_dia_pity', 'gacha_dia_sr', 'gacha_dia_ssr', 'gacha_gold_cost_base', 'gacha_gold_cost_growth',
      'gacha_gold_level_max', 'gacha_gold_level_pulls', 'gacha_gold_sr_base', 'gacha_gold_sr_step', 'gacha_gold_ssr_base', 'gacha_gold_ssr_step'])
    await assert.rejects(d.query('update player_state set diamonds = -1 where player_id = $1', [p.id]))
    await assert.rejects(d.query('update player_state set gacha_gold_level = 0 where player_id = $1', [p.id]))
  } finally {
    await d.close()
  }
})

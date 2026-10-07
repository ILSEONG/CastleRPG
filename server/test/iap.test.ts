// 결제 상품(iap.ts): 충전 첫 구매 2배, 패키지 한도, 월정액 매일 받기·연장, 성장 패스 무료·유료, 같은 주문 번호 한 번, 결제 연결 전 503. 마이그레이션 030.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as IAP from '../src/iap.ts'
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
let order = 0
const buy = (token: string, product: string, provider = 'test', order_id = `o${++order}`) =>
  S.req('POST', '/v1/iap/purchase', { token, body: { product, provider, order_id } })

test('iap.ts: 상품 id가 겹치지 않고, 충전은 클수록 원당 다이아가 많다', () => {
  assert.equal(new Set(IAP.PRODUCTS.map((p) => p.id)).size, IAP.PRODUCTS.length)
  const packs = IAP.PRODUCTS.filter((p) => p.kind === 'diamond')
  for (let i = 1; i < packs.length; i++) {
    const per = (p: IAP.Product) => ((p.give.diamonds ?? 0) + (p.bonus ?? 0)) / p.krw
    assert.ok(per(packs[i]) >= per(packs[i - 1]), packs[i].id)
  }
  for (const p of IAP.PRODUCTS) assert.ok(Object.keys(p.give).filter((k) => k.startsWith('keys_')).length <= 1, p.id)
})

test('결제 연결 전: google은 503 payments_unavailable, 모르는 상품 404', async () => {
  const { token } = await S.login()
  assert.equal((await buy(token, 'dia_1', 'google')).json.error, 'payments_unavailable')
  assert.equal((await buy(token, 'nope')).status, 404)
  const p = (await S.req('GET', '/v1/player', { token })).json.player
  assert.equal(p.iap_enabled, false)
  assert.deepEqual(p.iap.first, [])
})

test('다이아 충전: 첫 구매 2배, 두 번째는 기본 + 보너스, 같은 주문 번호는 한 번', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  const d0 = (await S.req('GET', '/v1/player', { token })).json.player.diamonds
  let r = await buy(token, 'dia_2', 'test', 'same')
  assert.equal(r.status, 200)
  assert.equal(r.json.player.diamonds, d0 + 3000)
  assert.equal((await buy(token, 'dia_2', 'test', 'same')).json.error, 'duplicate_order')
  r = await buy(token, 'dia_2')
  assert.equal(r.json.player.diamonds, d0 + 3000 + 1800)
  assert.deepEqual(r.json.player.iap.first, ['dia_2'])
  const logs = await S.db.query("select detail from economy_log where player_id = $1 and kind = 'iap'", [id])
  assert.equal(logs.length, 2)
})

test('패키지: 스타터 평생 1번, 일일 패키지는 다음 날 다시', async () => {
  S.clock.t = T0
  const { token } = await S.login()
  let r = await buy(token, 'pkg_starter')
  assert.equal(r.status, 200)
  assert.equal(r.json.player.pouches.gold_120, 3)
  assert.equal((await buy(token, 'pkg_starter')).json.error, 'limit')
  const keys = r.json.player.dungeons.gold.keys
  r = await buy(token, 'pkg_daily')
  assert.equal(r.json.player.dungeons.gold.keys, keys + 2)
  assert.equal((await buy(token, 'pkg_daily')).json.error, 'limit')
  S.clock.t = T0 + DAY
  assert.equal((await buy(token, 'pkg_daily')).status, 200)
})

test('월정액: 즉시 300 + 하루 한 번 100, 30일 뒤 끝, 남은 기간에 사면 이어 붙는다', async () => {
  S.clock.t = T0
  const { token } = await S.login()
  const claim = () => S.req('POST', '/v1/iap/monthly/claim', { token, body: { product: 'monthly' } })
  assert.equal((await claim()).json.error, 'inactive')
  let r = await buy(token, 'monthly')
  const d = r.json.player.diamonds
  r = await claim()
  assert.equal(r.json.player.diamonds, d + 200)
  assert.equal((await claim()).json.error, 'claimed')
  S.clock.t = T0 + 29 * DAY
  assert.equal((await claim()).status, 200)
  r = await buy(token, 'monthly')
  const m = r.json.player.iap.monthly.monthly
  assert.equal(m.until - r.json.player.iap.day + 1, 31) // 남은 1일 + 30일
  assert.equal((await claim()).json.error, 'claimed') // 오늘 받은 것은 그대로
  const later = IAP.normalize(r.json.player.iap, r.json.player.iap.day + 31) // 이어 붙인 31일이 지나면 끝(토큰 만료 전이라 규칙으로 본다)
  assert.equal(IAP.monthlyLeft(later, 'monthly'), 0)
})

test('성장 패스: 라운드를 깨야 무료, 유료는 패스를 산 뒤(지난 단계도)', async () => {
  S.clock.t = T0
  const { token } = await S.login()
  const claim = (tier: number, track: string) => S.req('POST', '/v1/iap/growth/claim', { token, body: { tier, track } })
  assert.equal((await claim(0, 'free')).json.error, 'not_ready')
  await S.req('POST', '/v1/test/stage', { token, body: { stage: 30 } })
  let r = await claim(0, 'free')
  assert.equal(r.status, 200)
  assert.deepEqual(r.json.player.iap.gp.free, [0])
  assert.equal((await claim(0, 'free')).json.error, 'not_ready')
  assert.equal((await claim(0, 'paid')).json.error, 'not_ready')
  assert.equal((await claim(2, 'free')).json.error, 'not_ready') // 50라운드 전
  await buy(token, 'pass_growth')
  assert.equal((await buy(token, 'pass_growth')).json.error, 'limit')
  const d = (await S.req('GET', '/v1/player', { token })).json.player.diamonds
  r = await claim(0, 'paid')
  assert.equal(r.json.player.diamonds, d + 600)
  r = await claim(1, 'paid')
  assert.equal(r.json.player.dia_tickets >= 2, true)
})

test('핫딜: 보스 단계·다이아 부족·패배 때 1시간, 한 번에 하나, 뜬 것만 한 번 산다', async () => {
  S.clock.t = T0
  const { token } = await S.login()
  const offer = (trigger: string) => S.req('POST', '/v1/iap/hot', { token, body: { trigger } })
  assert.equal((await buy(token, 'hot_dia')).json.error, 'limit') // 안 뜬 핫딜은 못 산다
  assert.equal((await offer('boss')).json.reason, 'not_ready') // 25라운드 전
  let r = await offer('dia')
  assert.equal(r.status, 200)
  assert.equal(r.json.hot.id, 'hot_dia')
  assert.equal(r.json.hot.until, T0 + IAP.HOT_SEC)
  assert.equal((await offer('defeat')).json.reason, 'active') // 하나만
  r = await buy(token, 'hot_dia')
  assert.equal(r.status, 200)
  assert.equal(r.json.player.iap.hot.bought, true)
  assert.equal((await buy(token, 'hot_dia')).json.error, 'limit')
  assert.equal((await offer('dia')).json.reason, 'cooldown') // 24시간 쉰다
  r = await offer('defeat')
  assert.equal(r.json.hot.id, 'hot_defeat')
  S.clock.t = T0 + IAP.HOT_SEC + 1 // 시간이 지나면 못 산다
  assert.equal((await buy(token, 'hot_defeat')).json.error, 'limit')
  await S.req('POST', '/v1/test/stage', { token, body: { stage: 26 } })
  r = await offer('boss')
  assert.equal(r.json.hot.id, 'hot_boss')
  assert.equal(r.json.player.iap.hs, 1)
  S.clock.t = T0 + 2 * IAP.HOT_SEC + 2
  assert.equal((await offer('boss')).json.reason, 'not_ready') // 같은 단계는 한 번
  await S.req('POST', '/v1/test/stage', { token, body: { stage: 51 } })
  r = await offer('boss') // 6시간 쉬는 중: 단계만 넘기고 핫딜은 없음
  assert.equal(r.status, 200)
  assert.equal(r.json.hot, null)
  assert.equal(r.json.player.iap.hs, 2)
})

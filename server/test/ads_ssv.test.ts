// 보상형 광고 서버 확인(AdMob SSV, ads.ts + /v1/ads/start · /admob/ssv · 상점 [광고] 상품). 마이그레이션 052.
import assert from 'node:assert/strict'
import { generateKeyPairSync, sign } from 'node:crypto'
import { test } from 'node:test'
import * as Ads from '../src/ads.ts'
import { VERIFIER_KEYS_URL } from '../src/ads.ts'
import { setup, T0 } from './helpers.ts'

const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' })
const pem = publicKey.export({ type: 'spki', format: 'pem' }).toString()
const fakeFetch = (async (url: string) => {
  assert.equal(String(url), VERIFIER_KEYS_URL)
  return new Response(JSON.stringify({ keys: [{ keyId: 3335741209, pem, base64: '' }] }), { status: 200 })
}) as unknown as typeof fetch

const OUR_UNIT = '5685684246' // ads.ts AD_UNITS(ca-app-pub-7646904883481371/5685684246)의 숫자 부분 — AdMob 콜백의 ad_unit 모양
const signed = (msg: string, key = privateKey) =>
  `/admob/ssv?${msg}&signature=${sign('sha256', Buffer.from(msg), key).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')}&key_id=3335741209`

// AdMob과 같은 모양의 콜백 쿼리(서명은 signature 앞 전체, web-safe base64, key_id가 맨 끝)
function callback(customData: string, tx: string, key = privateKey, adUnit = OUR_UNIT) {
  return signed(`ad_network=5450213213286189855&ad_unit=${adUnit}&custom_data=${encodeURIComponent(customData)}&reward_amount=1&reward_item=Reward&timestamp=1790000000000&transaction_id=${tx}&user_id=`, key)
}

test('AdMob SSV: 서명 확인, 표 확인, 운영 설정 ad_ssv=1이면 확인된 표로만 광고 상품, 표는 한 상품·한 번만', async () => {
  const S = await setup({ fetch: fakeFetch })
  try {
    const { token } = await S.login()
    const start = async () => (await S.req('POST', '/v1/ads/start', { token })).json.token as string
    const buy = (n: number, ad_token?: string, ad = true) => S.req('POST', '/v1/shop/buy', { token, body: { id: 'a_dia', n, ad, ...(ad_token ? { ad_token } : {}) } })

    // 확인을 켜기 전: 예전처럼 ad: true면 받고, 기록에 ssv 여부만 남긴다
    const t0 = await start()
    assert.match(t0, /^[A-Za-z0-9_-]{24}$/)
    assert.equal((await buy(0, t0)).status, 200)
    assert.equal((await S.req('GET', callback(t0, 'tx0'))).status, 200)
    assert.equal((await buy(1, t0)).status, 200) // 콜백 뒤에 보낸 표 — 기록에 ssv: true

    // 서명 오류
    const { privateKey: other } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' })
    assert.equal((await S.req('GET', callback(t0, 'txbad', other))).status, 403)
    assert.equal((await S.req('GET', callback(t0, 'txbad').replace('reward_amount=1', 'reward_amount=9'))).status, 403)
    assert.equal((await S.req('GET', '/admob/ssv?ad_unit=1')).status, 403)
    assert.equal((await S.req('GET', callback('', 'console-test'))).status, 200) // 콘솔 [확인] 시험 호출(표 없음)

    await S.db.query("insert into ops_config (key, value) values ('ad_ssv', '1')")
    assert.equal((await buy(2)).json.error, 'ad_unverified') // 표 없이 ad: true만
    const t1 = await start()
    assert.equal((await buy(2, t1)).json.error, 'ad_unverified') // AdMob 콜백 전
    assert.equal((await S.req('GET', callback(t1, 'tx1'))).status, 200)
    assert.equal((await S.req('GET', callback(t1, 'tx1'))).status, 200) // 같은 거래 재전송
    const r = await buy(2, t1, false)
    assert.equal(r.status, 200, JSON.stringify(r.json))
    assert.equal((await buy(2, t1)).json.error, 'stale') // 같은 n 재전송 → 두 번 받지 않는다
    assert.equal((await buy(3, t1)).json.error, 'ad_unverified') // 쓴 표로 다음 상품은 안 된다

    // 남의 표는 쓸 수 없다
    const other2 = await S.login()
    const t2 = (await S.req('POST', '/v1/ads/start', { token: other2.token })).json.token
    assert.equal((await S.req('GET', callback(t2, 'tx2'))).status, 200)
    assert.equal((await buy(3, t2)).json.error, 'ad_unverified')

    // 못 산 경우(한도) 표는 돌려놓는다
    const t3 = await start()
    await S.req('GET', callback(t3, 'tx3'))
    assert.equal((await buy(3, t3)).status, 200)
    assert.equal((await buy(4, (await (async () => { const t = await start(); await S.req('GET', callback(t, 'tx4')); return t })()))).status, 200)
    const t5 = await start()
    await S.req('GET', callback(t5, 'tx5'))
    assert.equal((await buy(5, t5)).json.error, 'sold_out') // a_dia 하루 5개
    const [row] = await S.db.query('select used_for from ad_views where token = $1', [t5])
    assert.equal(row.used_for, null)
    const log = await S.db.query("select detail->>'ssv' as ssv from economy_log where kind = 'shop' order by id")
    assert.deepEqual(log.map((x: any) => x.ssv), ['false', 'true', 'true', 'true', 'true'])
  } finally {
    await S.close()
  }
})

test('AdMob SSV: 서명 뒤에 덧붙인 값·남의 광고 단위 콜백은 표를 확인하지 않는다(200은 그대로)', async () => {
  const S = await setup({ fetch: fakeFetch })
  try {
    const { token } = await S.login()
    await S.db.query("insert into ops_config (key, value) values ('ad_ssv', '1')")
    const t = (await S.req('POST', '/v1/ads/start', { token })).json.token as string
    const verified = async () => (await S.db.query('select verified_at from ad_views where token = $1', [t]))[0].verified_at !== null
    // custom_data 없이 서명된 콜백(콘솔 시험·남의 앱) 뒤에 우리 표를 덧붙인다
    const plain = signed(`ad_network=1&ad_unit=${OUR_UNIT}&reward_amount=1&reward_item=Reward&timestamp=1790000000000&transaction_id=txa&user_id=`)
    assert.equal((await S.req('GET', `${plain}&custom_data=${t}&transaction_id=txa2`)).status, 200)
    assert.equal(await verified(), false)
    // 같은 Google 키로 서명된 남의 광고 단위 콜백
    assert.equal((await S.req('GET', callback(t, 'txb', privateKey, '2349074466'))).status, 200)
    assert.equal((await S.req('GET', callback(t, 'txc', privateKey, 'ca-app-pub-1111111111111111/5685684246'))).status, 200)
    assert.equal(await verified(), false)
    assert.equal((await S.req('POST', '/v1/shop/buy', { token, body: { id: 'a_dia', n: 0, ad: true, ad_token: t } })).json.error, 'ad_unverified')
    assert.equal((await S.req('GET', callback(t, 'txd'))).status, 200)
    assert.equal(await verified(), true)
    assert.ok(Ads.adUnitOk(Ads.AD_UNITS, 'ca-app-pub-7646904883481371/5685684246'))
    assert.ok(!Ads.adUnitOk(Ads.AD_UNITS, ''))
    // ADMOB_AD_UNITS(main.ts → adUnits)로 바꾼 목록
    const app = S.makeApp({ adUnits: ['ca-app-pub-7646904883481371/2349074466'] })
    const t2 = (await S.req('POST', '/v1/ads/start', { token })).json.token as string
    assert.equal((await app.request(callback(t2, 'txe', privateKey, '2349074466'))).status, 200)
    assert.notEqual((await S.db.query('select verified_at from ad_views where token = $1', [t2]))[0].verified_at, null)
  } finally {
    await S.close()
  }
})

test('keyStore: 받는 중이면 같이 기다리고, 모르는 key_id·실패는 1분에 한 번만 다시 받는다', async () => {
  let calls = 0
  let t = 0
  let keys = [{ keyId: 1, pem: 'A' }]
  const f = (async () => {
    calls++
    await new Promise((ok) => setTimeout(ok, 5))
    return new Response(JSON.stringify({ keys }), { status: 200 })
  }) as unknown as typeof fetch
  const keyFor = Ads.keyStore(f, () => t)
  assert.deepEqual(await Promise.all([keyFor('1'), keyFor('1'), keyFor('9')]), ['A', 'A', undefined])
  assert.equal(calls, 1)
  for (let i = 0; i < 10; i++) assert.equal(await keyFor(`x${i}`), undefined) // 모르는 key_id 도배
  assert.equal(await keyFor('__proto__'), undefined)
  assert.equal(calls, 1)
  keys = [{ keyId: 9, pem: 'B' }] // 키 교체
  t = 61_000
  assert.equal(await keyFor('9'), 'B')
  assert.equal(calls, 2)
  let fails = 0
  const down = Ads.keyStore((async () => (fails++, new Response('', { status: 500 }))) as unknown as typeof fetch, () => t)
  await assert.rejects(down('1'))
  await assert.rejects(down('1'))
  assert.equal(fails, 1)
})

test('광고 표: 다음 날 같은 n으로 다시 못 쓴다, 쓴 표를 매진 상품에 다시 보내도 풀리지 않는다, 1시간 지난 표 안 받음, 토스 계정은 ad: true', async () => {
  const S = await setup({ fetch: fakeFetch })
  try {
    S.clock.t = T0
    const { token } = await S.login()
    await S.db.query("insert into ops_config (key, value) values ('ad_ssv', '1')")
    let tx = 0
    const ticket = async () => {
      const t = (await S.req('POST', '/v1/ads/start', { token })).json.token as string
      assert.equal((await S.req('GET', callback(t, `tx${++tx}`))).status, 200)
      return t
    }
    const buy = (id: string, n: number, ad_token?: string, tok = token) => S.req('POST', '/v1/shop/buy', { token: tok, body: { id, n, ad: true, ...(ad_token ? { ad_token } : {}) } })
    const t1 = await ticket()
    assert.equal((await buy('a_dia', 0, t1)).status, 200)
    S.clock.t = T0 + 86400 // 다음 리셋 날짜: a_dia 산 수가 다시 0
    assert.equal((await buy('a_dia', 0, t1)).json.error, 'ad_unverified')
    const t2 = await ticket()
    assert.equal((await buy('a_key_equip', 0, t2)).status, 200) // 하루 1개
    assert.equal((await buy('a_key_equip', 0, t2)).json.error, 'sold_out') // 같은 표 재전송
    assert.equal((await buy('a_dia', 0, t2)).json.error, 'ad_unverified') // 표가 풀리지 않았다
    const t3 = await ticket()
    await S.db.query("update ad_views set created_at = now() - interval '2 hours' where token = $1", [t3])
    assert.equal((await buy('a_dia', 0, t3)).json.error, 'ad_unverified')
    assert.equal((await buy('a_dia', 0, await ticket())).status, 200)
    // 토스 미니앱에는 실제 광고가 없다(5초 자리 표시) — 토스 계정은 ad_ssv=1이어도 예전처럼
    const toss = await S.req('POST', '/v1/auth/toss', { body: { hash: 'toss-user-hash-0001' } })
    assert.equal((await buy('a_dia', 0, undefined, toss.json.token)).status, 200)
    assert.equal((await buy('a_dia', 1, undefined)).json.error, 'ad_unverified') // 게스트는 그대로
  } finally {
    await S.close()
  }
})

// 보상형 광고 서버 확인(AdMob SSV, ads.ts + /v1/ads/start · /admob/ssv · 상점 [광고] 상품). 마이그레이션 052.
import assert from 'node:assert/strict'
import { generateKeyPairSync, sign } from 'node:crypto'
import { test } from 'node:test'
import { VERIFIER_KEYS_URL } from '../src/ads.ts'
import { setup } from './helpers.ts'

const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' })
const pem = publicKey.export({ type: 'spki', format: 'pem' }).toString()
const fakeFetch = (async (url: string) => {
  assert.equal(String(url), VERIFIER_KEYS_URL)
  return new Response(JSON.stringify({ keys: [{ keyId: 3335741209, pem, base64: '' }] }), { status: 200 })
}) as unknown as typeof fetch

// AdMob과 같은 모양의 콜백 쿼리(서명은 signature 앞 전체, web-safe base64, key_id가 맨 끝)
function callback(customData: string, tx: string, key = privateKey) {
  const msg = `ad_network=5450213213286189855&ad_unit=2349074466&custom_data=${encodeURIComponent(customData)}&reward_amount=1&reward_item=Reward&timestamp=1790000000000&transaction_id=${tx}&user_id=`
  const sig = sign('sha256', Buffer.from(msg), key).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
  return `/admob/ssv?${msg}&signature=${sig}&key_id=3335741209`
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

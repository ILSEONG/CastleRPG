// 실결제 확인(payments.ts + /v1/iap/purchase google·toss), 약관 페이지(legal.ts), 게스트 계정 연동(/v1/auth/link/*). 마이그레이션 039.
import assert from 'node:assert/strict'
import { createHash, generateKeyPairSync, randomBytes, createVerify } from 'node:crypto'
import { test } from 'node:test'
import * as Pay from '../src/payments.ts'
import { setup } from './helpers.ts'

// 가짜 확인기: token "ok:<상품>"이면 그 상품의 완료 결제, "pending"이면 진행 중, "boom"이면 확인 서버 오류, 그 밖은 무효.
function fakeVerifier(orderPrefix: string) {
  const finished: string[] = []
  const v: Pay.Verifier = {
    async verify({ product, token, account }) {
      if (token === 'boom') throw new Error('down')
      if (token === 'pending') return { ok: false, pending: true, orderId: 'p', product }
      if (token.startsWith('acct:')) return { ok: token.slice(5) === account, orderId: `${orderPrefix}-acct`, product }
      if (token.startsWith('ok:')) {
        const [, paid, n] = token.split(':')
        return { ok: true, orderId: `${orderPrefix}-${paid}-${n ?? 0}`, product: paid }
      }
      return { ok: false, orderId: '', product, reason: 'bad' }
    },
    async finish({ token }) {
      finished.push(token)
    },
  }
  return { v, finished }
}

const buy = (S: any, token: string, product: string, provider: string, t: string) =>
  S.req('POST', '/v1/iap/purchase', { token, body: { product, provider, token: t } })

test('Google 결제: 확인되면 지급 + consume, 다시 보내면 already(+ consume 다시), 진행 중 202, 무효·상품 불일치 402, 확인 오류 502', async () => {
  const g = fakeVerifier('GPA')
  const S = await setup({ payments: { google: g.v } })
  try {
    const { token, id } = await S.login()
    const p0 = (await S.req('GET', '/v1/player', { token })).json.player
    assert.equal(p0.iap_enabled, true)
    assert.deepEqual(p0.iap_providers, ['google'])
    assert.equal(p0.account_tag, Pay.accountTag(id))
    const r = await buy(S, token, 'dia_1', 'google', 'ok:dia_1:1')
    assert.equal(r.status, 200, JSON.stringify(r.json))
    assert.equal(r.json.player.diamonds, p0.diamonds + 600)
    assert.deepEqual(g.finished, ['ok:dia_1:1'])
    const again = await buy(S, token, 'dia_1', 'google', 'ok:dia_1:1')
    assert.equal(again.json.already, true)
    assert.equal(g.finished.length, 2)
    assert.equal((await buy(S, token, 'dia_1', 'google', 'pending')).status, 202)
    assert.equal((await buy(S, token, 'dia_1', 'google', 'nope')).json.error, 'payment_invalid')
    assert.equal((await buy(S, token, 'dia_6', 'google', 'ok:dia_1:2')).json.error, 'payment_invalid') // 싼 결제로 비싼 상품
    assert.equal((await buy(S, token, 'dia_1', 'google', 'boom')).json.error, 'payment_check_failed')
    assert.equal((await buy(S, token, 'dia_1', 'toss', 'ok:dia_1:3')).json.error, 'payments_unavailable')
    assert.equal((await buy(S, token, 'dia_1', 'google', `acct:${Pay.accountTag(id)}`)).status, 200) // 내 계정 표시가 맞는 결제
    const other = await S.login()
    assert.equal((await buy(S, other.token, 'dia_1', 'google', `acct:${Pay.accountTag(id)}`)).json.error, 'payment_invalid') // 남의 계정 결제
    assert.equal((await buy(S, other.token, 'dia_1', 'google', 'ok:dia_1:1')).json.error, 'duplicate_order')
    const p = (await S.req('GET', '/v1/player', { token })).json.player
    assert.equal(p.diamonds, p0.diamonds + 600 + 330)
  } finally {
    await S.close()
  }
})

test('한도에 걸린 실결제는 지급도 consume도 안 한다(Google이 자동 환불), 주문 기록은 계정 삭제 뒤에도 남는다', async () => {
  const g = fakeVerifier('GPA')
  const S = await setup({ payments: { google: g.v } })
  try {
    const { token, id } = await S.login()
    assert.equal((await buy(S, token, 'pkg_starter', 'google', 'ok:pkg_starter:1')).status, 200)
    const second = await buy(S, token, 'pkg_starter', 'google', 'ok:pkg_starter:2')
    assert.equal(second.json.error, 'limit')
    assert.deepEqual(g.finished, ['ok:pkg_starter:1'])
    assert.equal((await S.db.query("select 1 from iap_orders where order_id = 'google:GPA-pkg_starter-2'")).length, 0)
    assert.equal((await S.req('POST', '/v1/account/delete', { token, body: { confirm: 'delete' } })).status, 200)
    const rows = await S.db.query("select player_id, product, krw from iap_orders where order_id = 'google:GPA-pkg_starter-1'")
    assert.deepEqual(rows.map((r: any) => [r.player_id, r.product, r.krw]), [[null, 'pkg_starter', 1200]])
    assert.equal((await S.db.query('select 1 from players where id = $1', [id])).length, 0)
  } finally {
    await S.close()
  }
})

test('토스 결제: sku가 상품 id와 다르면 TOSS_SKUS로 맞춘다, 뷰에 sku 표', async () => {
  const t = fakeVerifier('toss')
  const S = await setup({ payments: { toss: t.v, tossSkus: { dia_1: 'castle_dia_1' } } })
  try {
    const { token } = await S.login()
    const p0 = (await S.req('GET', '/v1/player', { token })).json.player
    assert.deepEqual(p0.iap_providers, ['toss'])
    assert.deepEqual(p0.iap_skus, { toss: { dia_1: 'castle_dia_1' } })
    const r = await buy(S, token, 'dia_1', 'toss', 'ok:castle_dia_1:1')
    assert.equal(r.status, 200, JSON.stringify(r.json))
    assert.equal(r.json.player.diamonds, p0.diamonds + 600)
    assert.equal((await buy(S, token, 'dia_2', 'toss', 'ok:castle_dia_1:2')).json.error, 'payment_invalid')
  } finally {
    await S.close()
  }
})

test('googleVerifier: 서비스 계정 JWT로 토큰을 받고 구매를 조회, 상태·계정 확인, consume', async () => {
  const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 })
  const calls: { url: string; init: any }[] = []
  const purchases: Record<string, any> = {
    t1: { purchaseState: 0, orderId: 'GPA.1', obfuscatedExternalAccountId: 'acc' },
    t2: { purchaseState: 2, orderId: 'GPA.2' },
    t3: { purchaseState: 1, orderId: 'GPA.3' },
    t4: { purchaseState: 0, orderId: 'GPA.4', obfuscatedExternalAccountId: 'someone' },
  }
  const fetchFn = (async (u: any, init: any = {}) => {
    const url = String(u)
    calls.push({ url, init })
    const json = (v: unknown, status = 200) => new Response(JSON.stringify(v), { status })
    if (url === 'https://oauth2.googleapis.com/token') {
      const jwt = new URLSearchParams(init.body).get('assertion')!.split('.')
      assert.ok(createVerify('RSA-SHA256').update(`${jwt[0]}.${jwt[1]}`).verify(publicKey, Buffer.from(jwt[2], 'base64url')))
      assert.equal(JSON.parse(Buffer.from(jwt[1], 'base64url').toString()).scope, 'https://www.googleapis.com/auth/androidpublisher')
      return json({ access_token: 'AT', expires_in: 3600 })
    }
    assert.equal(init.headers.Authorization, 'Bearer AT')
    const m = /applications\/com\.x\/purchases\/products\/dia_1\/tokens\/(\w+)(:consume)?$/.exec(url)
    if (!m) return json({}, 404)
    if (m[2]) return json({})
    return purchases[m[1]] ? json(purchases[m[1]]) : json({ error: 'not found' }, 404)
  }) as typeof fetch
  const v = Pay.googleVerifier({ email: 'sa@x.iam.gserviceaccount.com', privateKey: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(), pkg: 'com.x' }, fetchFn)
  assert.deepEqual(await v.verify({ product: 'dia_1', token: 't1', account: 'acc' }), { ok: true, orderId: 'GPA.1', product: 'dia_1' })
  assert.equal((await v.verify({ product: 'dia_1', token: 't2', account: 'acc' })).pending, true)
  assert.equal((await v.verify({ product: 'dia_1', token: 't3', account: 'acc' })).ok, false)
  assert.equal((await v.verify({ product: 'dia_1', token: 't4', account: 'acc' })).ok, false)
  assert.equal((await v.verify({ product: 'dia_1', token: 'zz', account: 'acc' })).ok, false)
  await v.finish!({ product: 'dia_1', token: 't1' })
  assert.equal(calls.filter((c) => c.url.includes('oauth2')).length, 1, 'access token is cached')
  assert.ok(calls.at(-1)!.url.endsWith('/tokens/t1:consume') && calls.at(-1)!.init.method === 'POST')
})

test('tossVerifier: 주문 상태 조회 결과로 판정, readPayments는 키가 있는 제공자만 켠다', async () => {
  const status: Record<string, any> = {
    a: { resultType: 'SUCCESS', success: { orderId: 'a', status: 'PAYMENT_COMPLETED', sku: 'dia_1', reason: '' } },
    b: { resultType: 'SUCCESS', success: { orderId: 'b', status: 'ORDER_IN_PROGRESS', reason: '' } },
    c: { resultType: 'SUCCESS', success: { orderId: 'c', status: 'REFUNDED', sku: 'dia_1', reason: '' } },
    d: { resultType: 'FAIL', error: { errorCode: '4095', reason: 'limit' } },
  }
  const v = Pay.tossVerifier(async (path, body: any) => {
    assert.equal(path, '/api-partner/v1/apps-in-toss/order/get-order-status')
    return { status: 200, json: status[body.orderId] }
  })
  assert.deepEqual(await v.verify({ product: 'dia_1', token: 'a', account: '' }), { ok: true, orderId: 'a', product: 'dia_1' })
  assert.equal((await v.verify({ product: 'dia_1', token: 'b', account: '' })).pending, true)
  assert.equal((await v.verify({ product: 'dia_1', token: 'c', account: '' })).ok, false)
  await assert.rejects(v.verify({ product: 'dia_1', token: 'd', account: '' }))
  assert.deepEqual(Pay.readPayments({}), {})
  assert.throws(() => Pay.readPayments({ TOSS_MTLS_CERT: '-----BEGIN CERTIFICATE-----' }))
  assert.throws(() => Pay.readPayments({ GOOGLE_PLAY_SERVICE_ACCOUNT: '{"x":1}' }))
  const sa = Buffer.from(JSON.stringify({ client_email: 'a@b', private_key: 'k' })).toString('base64')
  const both = Pay.readPayments({ GOOGLE_PLAY_SERVICE_ACCOUNT: sa, TOSS_MTLS_CERT: '-----C', TOSS_MTLS_KEY: '-----K', TOSS_SKUS: '{"dia_1":"x"}' })
  assert.ok(both.google && both.toss)
  assert.deepEqual(both.tossSkus, { dia_1: 'x' })
})

test('약관·개인정보처리방침·계정 삭제 안내 페이지: 공개 HTML, 운영자·연락처가 들어간다', async () => {
  const S = await setup({ legal: { operator: '테스트 운영자', email: 'help@example.com' } })
  try {
    for (const path of ['/legal/terms', '/legal/privacy', '/legal/account-deletion']) {
      const r = await S.req('GET', path)
      assert.equal(r.status, 200, path)
      assert.ok(r.headers.get('content-type')?.includes('text/html'), path)
      assert.ok(r.text.includes('테스트 운영자') && r.text.includes('help@example.com'), path)
    }
    assert.ok((await S.req('GET', '/legal/privacy')).text.includes('개인정보 보호책임자'))
    const plain = await setup()
    try {
      assert.ok((await plain.req('GET', '/legal/terms')).text.includes('연락처 등록 예정'))
    } finally {
      await plain.close()
    }
  } finally {
    await S.close()
  }
})

const pair = () => {
  const verifier = randomBytes(32).toString('hex')
  return { verifier, challenge: createHash('sha256').update(verifier).digest('hex') }
}

test('계정 연동: 게스트가 Google을 이으면 같은 계정(진행 그대로)에 세션이 생기고, 이미 다른 계정의 Google·같은 제공자 두 번째는 거절', async () => {
  const S = await setup()
  try {
    const guest = await S.login()
    await S.db.query('update player_state set stage = 7 where player_id = $1', [guest.id])
    assert.deepEqual((await S.req('GET', '/v1/auth/links', { token: guest.token })).json.links, [])
    assert.equal((await S.req('POST', '/v1/auth/link/start', { body: { provider: 'google', challenge: pair().challenge } })).status, 401)
    const v = pair()
    const st = await S.req('POST', '/v1/auth/link/start', { token: guest.token, body: { provider: 'google', challenge: v.challenge } })
    assert.equal(st.status, 200, JSON.stringify(st.json))
    const done = await S.req('POST', '/v1/test/oauth_complete', { body: { state: st.json.state, provider_uid: 'g-guest' } })
    assert.equal(done.json.player_id, guest.id)
    const poll = await S.req('POST', '/v1/auth/oauth/poll', { body: { state: st.json.state, verifier: v.verifier } })
    assert.equal(poll.status, 200)
    assert.equal(poll.json.player_id, guest.id)
    assert.equal(poll.json.provider, 'google')
    const viaSession = await S.req('POST', '/v1/auth/session', { body: { session: poll.json.session } })
    assert.equal(viaSession.json.player_id, guest.id)
    assert.equal((await S.req('GET', '/v1/player', { token: viaSession.json.token })).json.player.stage, 7)
    assert.deepEqual((await S.req('GET', '/v1/auth/links', { token: guest.token })).json.links, ['google'])
    // 같은 계정에 Google 두 번째 → 시작부터 409
    assert.equal((await S.req('POST', '/v1/auth/link/start', { token: guest.token, body: { provider: 'google', challenge: pair().challenge } })).json.error, 'provider_taken')
    // 다른 게스트가 이미 이어진 Google 계정을 이으려 하면 already_linked(진행을 바꾸지 않는다)
    const other = await S.login()
    const v2 = pair()
    const st2 = await S.req('POST', '/v1/auth/link/start', { token: other.token, body: { provider: 'google', challenge: v2.challenge } })
    const d2 = await S.req('POST', '/v1/test/oauth_complete', { body: { state: st2.json.state, provider_uid: 'g-guest' } })
    assert.equal(d2.json.error, 'already_linked')
    const p2 = await S.req('POST', '/v1/auth/oauth/poll', { body: { state: st2.json.state, verifier: v2.verifier } })
    assert.equal(p2.status, 409)
    assert.equal(p2.json.error, 'already_linked')
    assert.deepEqual((await S.req('GET', '/v1/auth/links', { token: other.token })).json.links, [])
    // 카카오는 따로 이을 수 있다
    const v3 = pair()
    const st3 = await S.req('POST', '/v1/auth/link/start', { token: guest.token, body: { provider: 'kakao', challenge: v3.challenge } })
    assert.equal((await S.req('POST', '/v1/test/oauth_complete', { body: { state: st3.json.state, provider_uid: 'k-1' } })).json.player_id, guest.id)
    assert.deepEqual((await S.req('GET', '/v1/auth/links', { token: guest.token })).json.links.sort(), ['google', 'kakao'])
  } finally {
    await S.close()
  }
})

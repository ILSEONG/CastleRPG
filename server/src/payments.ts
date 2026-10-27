// 실결제 확인(2026-10-12). 앱이 결제를 마치면 /v1/iap/purchase로 영수증을 보내고, 서버가 결제 제공자에게 진짜 결제인지 물은 뒤에만 지급한다.
// - Google Play(APK): 구매 토큰 → Google Play Developer API purchases.products.get(서비스 계정, 범위 androidpublisher).
//   결제 완료(purchaseState 0)·상품 일치·내 계정(obfuscatedExternalAccountId = accountTag(플레이어))이면 지급, 지급 뒤 서버가 consume한다
//   (모든 상품을 Play Console에 "소모성"으로 등록 — 1회 한정은 서버 한도가 지킨다. 한도에 걸려 지급하지 않은 결제는 consume·확인하지 않아
//   Google이 3일 뒤 자동 환불한다).
// - 토스 인앱 결제(앱인토스 .ait): 주문 번호 → 앱인토스 파트너 API get-order-status(mTLS 인증서). PAYMENT_COMPLETED·PURCHASED이고 sku가
//   맞으면 지급. 지급 완료 통보(completeProductGrant)는 앱이 한다.
// 설정(환경 변수, main.ts → readPayments): GOOGLE_PLAY_SERVICE_ACCOUNT(서비스 계정 JSON, 원문 또는 base64), GOOGLE_PLAY_PACKAGE(기본
// com.ilesong.castlerpg), TOSS_MTLS_CERT·TOSS_MTLS_KEY(PEM, 원문 또는 base64), TOSS_SKUS(선택, {"상품 id":"토스 sku"} JSON — 콘솔 sku가 상품
// id와 다를 때). 설정된 제공자만 켜진다(view.iap_providers) — 키를 넣고 서버를 다시 시작하면 그 플랫폼 결제가 열린다.
import { createHash, createSign } from 'node:crypto'
import { request } from 'node:https'

export type PayProvider = 'google' | 'toss'

export interface Verified {
  ok: boolean
  orderId: string // 제공자 주문 번호(중복 지급 막기 키)
  product: string // 결제된 상품(우리 상품 id)
  pending?: boolean // 아직 결제 진행 중(나중에 다시)
  reason?: string // ok가 아닐 때 로그용
}

export interface Verifier {
  verify(input: { product: string; token: string; account: string }): Promise<Verified>
  finish?(input: { product: string; token: string }): Promise<void> // 지급 뒤 처리(Google consume). 실패해도 지급은 그대로
}

export interface Payments {
  google?: Verifier
  toss?: Verifier
  tossSkus?: Record<string, string> // 상품 id → 토스 sku
}

// 결제에 실어 보내는 내 계정 표시(Google obfuscatedExternalAccountId). 플레이어 id를 그대로 내보내지 않는다.
export const accountTag = (playerId: string) => createHash('sha256').update(`castlerpg:${playerId}`).digest('hex').slice(0, 40)

const decode = (v: string) => {
  const t = v.trim()
  if (!t) return ''
  return t.startsWith('{') || t.startsWith('-----') ? t : Buffer.from(t, 'base64').toString('utf8')
}

export function readPayments(env: Record<string, string | undefined>, fetchFn: typeof fetch = fetch): Payments {
  const out: Payments = {}
  const sa = decode(env.GOOGLE_PLAY_SERVICE_ACCOUNT ?? '')
  if (sa) {
    const key = JSON.parse(sa)
    if (typeof key.client_email !== 'string' || typeof key.private_key !== 'string') throw new Error('GOOGLE_PLAY_SERVICE_ACCOUNT must be a service account JSON key')
    out.google = googleVerifier({ email: key.client_email, privateKey: key.private_key, pkg: env.GOOGLE_PLAY_PACKAGE?.trim() || 'com.ilesong.castlerpg' }, fetchFn)
  }
  const cert = decode(env.TOSS_MTLS_CERT ?? '')
  const pkey = decode(env.TOSS_MTLS_KEY ?? '')
  if (cert || pkey) {
    if (!cert || !pkey) throw new Error('TOSS_MTLS_CERT and TOSS_MTLS_KEY must be set together')
    out.toss = tossVerifier(tossPost(cert, pkey))
  }
  const skus = env.TOSS_SKUS?.trim()
  if (skus) out.tossSkus = JSON.parse(skus)
  return out
}

// --- Google Play ---

const ANDROID_PUBLISHER = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications'

export function googleVerifier(cfg: { email: string; privateKey: string; pkg: string }, fetchFn: typeof fetch): Verifier {
  let cached = { token: '', until: 0 }
  async function accessToken(): Promise<string> {
    const now = Math.floor(Date.now() / 1000)
    if (cached.token && cached.until > now + 60) return cached.token
    const b64 = (o: unknown) => Buffer.from(JSON.stringify(o)).toString('base64url')
    const head = b64({ alg: 'RS256', typ: 'JWT' })
    const claims = b64({ iss: cfg.email, scope: 'https://www.googleapis.com/auth/androidpublisher', aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600 })
    const sig = createSign('RSA-SHA256').update(`${head}.${claims}`).sign(cfg.privateKey).toString('base64url')
    const r = await fetchFn('https://oauth2.googleapis.com/token', {
      method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${head}.${claims}.${sig}` }).toString(),
    })
    const j: any = await r.json().catch(() => null)
    if (!r.ok || typeof j?.access_token !== 'string') throw new Error(`google token failed: ${r.status} ${j?.error ?? ''}`)
    cached = { token: j.access_token, until: now + Number(j.expires_in ?? 3600) }
    return cached.token
  }
  const url = (product: string, token: string, suffix = '') =>
    `${ANDROID_PUBLISHER}/${encodeURIComponent(cfg.pkg)}/purchases/products/${encodeURIComponent(product)}/tokens/${encodeURIComponent(token)}${suffix}`
  return {
    async verify({ product, token, account }) {
      const r = await fetchFn(url(product, token), { headers: { Authorization: `Bearer ${await accessToken()}` } })
      const j: any = await r.json().catch(() => null)
      if (r.status === 404 || r.status === 400) return { ok: false, orderId: '', product, reason: `google ${r.status}` }
      if (!r.ok || !j) throw new Error(`google purchase lookup failed: ${r.status}`)
      const orderId = String(j.orderId ?? '') || `token-${createHash('sha256').update(token).digest('hex').slice(0, 32)}`
      if (j.purchaseState === 2) return { ok: false, pending: true, orderId, product, reason: 'pending' }
      if (j.purchaseState !== 0) return { ok: false, orderId, product, reason: `purchaseState ${j.purchaseState}` }
      if (j.obfuscatedExternalAccountId && j.obfuscatedExternalAccountId !== account) return { ok: false, orderId, product, reason: 'other account' }
      return { ok: true, orderId, product }
    },
    async finish({ product, token }) {
      const r = await fetchFn(url(product, token, ':consume'), { method: 'POST', headers: { Authorization: `Bearer ${await accessToken()}` } })
      if (!r.ok) throw new Error(`google consume failed: ${r.status}`)
    },
  }
}

// --- 토스 인앱 결제 ---

export type TossPost = (path: string, body: unknown) => Promise<{ status: number; json: any }>

// 앱인토스 파트너 API(mTLS). 인증서·키는 콘솔에서 발급(서버 API 이용하기).
export function tossPost(cert: string, key: string): TossPost {
  return (path, body) => new Promise((resolve, reject) => {
    const data = JSON.stringify(body)
    const req = request({ host: 'apps-in-toss-api.toss.im', port: 443, path, method: 'POST', cert, key, timeout: 10_000,
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) } }, (res) => {
      let raw = ''
      res.setEncoding('utf8')
      res.on('data', (c) => (raw += c))
      res.on('end', () => {
        let json: any = null
        try { json = JSON.parse(raw) } catch { /* 본문이 JSON이 아니다 */ }
        resolve({ status: res.statusCode ?? 0, json })
      })
    })
    req.on('timeout', () => req.destroy(new Error('toss api timeout')))
    req.on('error', reject)
    req.end(data)
  })
}

// 토스 주문 번호는 UUID(v7). 소문자로 맞춘 값이 중복 지급 막기 키다 — 대소문자만 다른 같은 주문을 두 번 받지 못하게.
// 모양은 16진수·대시만 본다(문서 예시에 마지막 묶음이 10자인 번호가 있다 — 정상 결제를 UUID 모양으로 거절하지 않게).
const UUID_RE = /^(?=.{8,64}$)[0-9a-f]+(-[0-9a-f]+)*$/i

export function tossVerifier(post: TossPost): Verifier {
  return {
    async verify({ product, token }) {
      if (!UUID_RE.test(token)) return { ok: false, orderId: '', product, reason: 'order id is not a uuid' }
      const orderId = token.toLowerCase()
      const r = await post('/api-partner/v1/apps-in-toss/order/get-order-status', { orderId })
      const s = r.json?.success
      if (r.status !== 200 || r.json?.resultType !== 'SUCCESS' || !s) throw new Error(`toss order lookup failed: ${r.status} ${r.json?.error?.errorCode ?? ''}`)
      // 응답의 orderId(요청한 주문 번호)가 있으면 같은 주문이어야 한다
      if (s.orderId != null && String(s.orderId).toLowerCase() !== orderId) return { ok: false, orderId, product, reason: 'order id mismatch' }
      if (s.status === 'ORDER_IN_PROGRESS') return { ok: false, pending: true, orderId, product, reason: 'in progress' }
      if (s.status !== 'PAYMENT_COMPLETED' && s.status !== 'PURCHASED') return { ok: false, orderId, product, reason: `status ${s.status}` }
      return { ok: true, orderId, product: String(s.sku ?? '') }
    },
  }
}

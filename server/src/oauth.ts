// 소셜 로그인(Google·카카오·네이버) — OAuth 2.0 인가 코드 흐름. 앱은 시스템 브라우저로 /v1/auth/oauth/start가 준 url을 열고,
// 제공자가 서버 콜백(/v1/auth/:provider/callback)으로 돌려보내면 서버가 code를 토큰으로 바꿔 제공자 사용자 id만 읽는다
// (이름은 받지 않는다. Google만 확인된 이메일을 읽는다 — 슈퍼관리자 판별용, admin_emails 표와 맞춘다). 앱은 그동안 /v1/auth/oauth/poll로 결과를 기다린다. 제공자 호출은 주입한 fetch로(테스트는 가짜).
import { txt } from './texts.ts'

export const PROVIDERS = ['google', 'kakao', 'naver'] as const
export type Provider = (typeof PROVIDERS)[number]

export interface ProviderKeys {
  clientId: string
  clientSecret: string // 카카오는 선택(콘솔에서 Client Secret을 켰을 때만)
}

export interface OAuthConfig {
  redirectBase: string // 서버 공개 주소(env PUBLIC_URL) — 콜백 = redirectBase + /v1/auth/<provider>/callback. 비면 전부 꺼짐
  providers: Partial<Record<Provider, ProviderKeys>>
}

interface Endpoints {
  authorize: string
  token: string
  userinfo: string
  scope: string
  uid: (j: any) => unknown // 사용자 정보 응답 → 제공자 안 고유 id
  email?: (j: any) => unknown // 확인된 이메일(없거나 확인 안 됐으면 undefined)
}

const ENDPOINTS: Record<Provider, Endpoints> = {
  google: {
    authorize: 'https://accounts.google.com/o/oauth2/v2/auth',
    token: 'https://oauth2.googleapis.com/token',
    userinfo: 'https://openidconnect.googleapis.com/v1/userinfo',
    scope: 'openid email',
    uid: (j) => j?.sub,
    email: (j) => (j?.email_verified === true || j?.email_verified === 'true' ? j?.email : undefined),
  },
  kakao: {
    authorize: 'https://kauth.kakao.com/oauth/authorize',
    token: 'https://kauth.kakao.com/oauth/token',
    userinfo: 'https://kapi.kakao.com/v2/user/me',
    scope: '',
    uid: (j) => j?.id,
  },
  naver: {
    authorize: 'https://nid.naver.com/oauth2.0/authorize',
    token: 'https://nid.naver.com/oauth2.0/token',
    userinfo: 'https://openapi.naver.com/v1/nid/me',
    scope: '',
    uid: (j) => j?.response?.id,
  },
}

// 테스트 훅 서버 전용 가짜 설정(실제 제공자로는 로그인되지 않는다 — /v1/test/oauth_complete가 끝낸다)
export const TEST_CONFIG: OAuthConfig = {
  redirectBase: 'http://127.0.0.1',
  providers: { google: { clientId: 'test', clientSecret: 'test' }, kakao: { clientId: 'test', clientSecret: '' }, naver: { clientId: 'test', clientSecret: 'test' } },
}

export const isProvider = (v: unknown): v is Provider => typeof v === 'string' && (PROVIDERS as readonly string[]).includes(v)

export const enabledProviders = (cfg: OAuthConfig) => PROVIDERS.filter((p) => cfg.redirectBase && cfg.providers[p])

export const redirectUri = (cfg: OAuthConfig, p: Provider) => `${cfg.redirectBase}/v1/auth/${p}/callback`

// 제공자 로그인 화면 주소. 매번 로그인 화면을 보이게 하지는 않는다(이미 로그인된 브라우저는 곧바로 돌아온다).
export function authorizeUrl(cfg: OAuthConfig, p: Provider, state: string): string {
  const e = ENDPOINTS[p]
  const u = new URL(e.authorize)
  u.searchParams.set('response_type', 'code')
  u.searchParams.set('client_id', cfg.providers[p]!.clientId)
  u.searchParams.set('redirect_uri', redirectUri(cfg, p))
  u.searchParams.set('state', state)
  if (e.scope) u.searchParams.set('scope', e.scope)
  if (p === 'google') u.searchParams.set('prompt', 'select_account')
  return u.toString()
}

// code → 액세스 토큰 → 제공자 사용자 id(문자열)와 확인된 이메일(Google만, 소문자 — 없으면 null). 실패하면 Error(메시지는 로그용 — 비밀은 넣지 않는다).
export async function fetchUid(cfg: OAuthConfig, p: Provider, code: string, state: string, fetchFn: typeof fetch): Promise<{ uid: string; email: string | null }> {
  const e = ENDPOINTS[p]
  const keys = cfg.providers[p]!
  const form = new URLSearchParams({ grant_type: 'authorization_code', code, redirect_uri: redirectUri(cfg, p), client_id: keys.clientId })
  if (keys.clientSecret) form.set('client_secret', keys.clientSecret)
  if (p === 'naver') form.set('state', state)
  const tr = await fetchFn(e.token, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8' }, body: form.toString() })
  const tj: any = await tr.json().catch(() => null)
  const access = tj?.access_token
  if (!tr.ok || typeof access !== 'string' || !access) throw new Error(`${p} token exchange failed: ${tr.status} ${tj?.error ?? ''}`)
  const ur = await fetchFn(e.userinfo, { headers: { Authorization: `Bearer ${access}` } })
  const uj: any = await ur.json().catch(() => null)
  const uid = e.uid(uj)
  if (!ur.ok || (typeof uid !== 'string' && typeof uid !== 'number') || String(uid) === '') throw new Error(`${p} userinfo failed: ${ur.status}`)
  const email = e.email?.(uj)
  return { uid: String(uid), email: typeof email === 'string' && email.includes('@') ? email.trim().toLowerCase() : null }
}

// 콜백 결과 페이지(브라우저에 보인다). 앱으로 돌아가라는 안내만.
// 로그인을 마친 브라우저를 게임 앱으로 돌려보내는 안드로이드 링크(APK 매니페스트의 castlerpg://oauth — addons/castle_billing/export_plugin.gd).
// 앱이 없거나(옛 APK) 브라우저가 막으면 fallback(결과 안내 페이지)으로 간다.
export const APP_PACKAGE = 'com.ilesong.castlerpg'
export const appReturnUrl = (fallback?: string) =>
  `intent://oauth#Intent;scheme=castlerpg;package=${APP_PACKAGE};${fallback ? `S.browser_fallback_url=${encodeURIComponent(fallback)};` : ''}end`
export const isAndroid = (ua: string | undefined) => /Android/i.test(ua ?? '')

// back: 안드로이드면 [게임으로 돌아가기] 버튼(앱 링크)을 붙인다.
export function resultPage(ok: boolean, why?: string, back = false): string {
  const title = ok ? txt('server.oauth.resultpage') : txt('server.oauth.resultpage_2')
  const body = ok ? txt('server.oauth.resultpage_3') : why ? txt('server.oauth.resultpage_4', { why }) : txt('server.oauth.resultpage_5')
  const button = back ? `<a class="b" href="${appReturnUrl()}">${txt('server.oauth.back_to_game')}</a>` : ''
  return `<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>CastleRPG</title><style>body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;font-family:system-ui,sans-serif;
background:#5b93d8;color:#1f2430}.c{background:#fbf6ea;border:3px solid #2b2f3a;border-radius:18px;padding:32px 28px;max-width:320px;text-align:center}
h1{font-size:22px;margin:0 0 12px}p{margin:0;font-size:16px;line-height:1.5}
.b{display:inline-block;margin-top:20px;padding:12px 22px;background:#3f8f4f;color:#fff;border:3px solid #24552e;border-radius:12px;font-weight:700;text-decoration:none}</style></head>
<body><div class="c"><h1>${title}</h1><p>${body}</p>${button}</div></body></html>`
}

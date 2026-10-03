// 소셜 로그인(Google·카카오·네이버) — OAuth 2.0 인가 코드 흐름. 앱은 시스템 브라우저로 /v1/auth/oauth/start가 준 url을 열고,
// 제공자가 서버 콜백(/v1/auth/oauth/:provider/callback)으로 돌려보내면 서버가 code를 토큰으로 바꿔 제공자 사용자 id만 읽는다
// (이메일·이름은 받지 않는다). 앱은 그동안 /v1/auth/oauth/poll로 결과를 기다린다. 제공자 호출은 주입한 fetch로(테스트는 가짜).

export const PROVIDERS = ['google', 'kakao', 'naver'] as const
export type Provider = (typeof PROVIDERS)[number]

export interface ProviderKeys {
  clientId: string
  clientSecret: string // 카카오는 선택(콘솔에서 Client Secret을 켰을 때만)
}

export interface OAuthConfig {
  redirectBase: string // 서버 공개 주소(예: https://api.example.com) — 콜백 = redirectBase + /v1/auth/oauth/<provider>/callback
  providers: Partial<Record<Provider, ProviderKeys>>
}

interface Endpoints {
  authorize: string
  token: string
  userinfo: string
  scope: string
  uid: (j: any) => unknown // 사용자 정보 응답 → 제공자 안 고유 id
}

const ENDPOINTS: Record<Provider, Endpoints> = {
  google: {
    authorize: 'https://accounts.google.com/o/oauth2/v2/auth',
    token: 'https://oauth2.googleapis.com/token',
    userinfo: 'https://openidconnect.googleapis.com/v1/userinfo',
    scope: 'openid',
    uid: (j) => j?.sub,
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

// 환경 변수 → 설정. 키가 없는 제공자는 꺼진다(start가 503 provider_unavailable). 공개 주소가 없으면 전부 꺼진다.
export function readOAuthEnv(env: Record<string, string | undefined>): OAuthConfig {
  const redirectBase = (env.OAUTH_REDIRECT_BASE ?? '').trim().replace(/\/+$/, '')
  const providers: OAuthConfig['providers'] = {}
  const pick = (p: Provider, id?: string, secret?: string, secretRequired = true) => {
    const clientId = id?.trim() ?? ''
    const clientSecret = secret?.trim() ?? ''
    if (clientId && (clientSecret || !secretRequired)) providers[p] = { clientId, clientSecret }
  }
  pick('google', env.GOOGLE_CLIENT_ID, env.GOOGLE_CLIENT_SECRET)
  pick('kakao', env.KAKAO_REST_API_KEY, env.KAKAO_CLIENT_SECRET, false)
  pick('naver', env.NAVER_CLIENT_ID, env.NAVER_CLIENT_SECRET)
  return { redirectBase, providers: redirectBase ? providers : {} }
}

export const enabledProviders = (cfg: OAuthConfig) => PROVIDERS.filter((p) => cfg.redirectBase && cfg.providers[p])

export const redirectUri = (cfg: OAuthConfig, p: Provider) => `${cfg.redirectBase}/v1/auth/oauth/${p}/callback`

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

// code → 액세스 토큰 → 제공자 사용자 id(문자열). 실패하면 Error(메시지는 로그용 — 비밀은 넣지 않는다).
export async function fetchUid(cfg: OAuthConfig, p: Provider, code: string, state: string, fetchFn: typeof fetch): Promise<string> {
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
  return String(uid)
}

// 콜백 결과 페이지(브라우저에 보인다). 앱으로 돌아가라는 안내만.
export function resultPage(ok: boolean): string {
  const title = ok ? '로그인되었습니다' : '로그인하지 못했습니다'
  const body = ok ? '게임으로 돌아가 주세요. 이 창은 닫아도 됩니다.' : '게임으로 돌아가 다시 시도해 주세요.'
  return `<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>CastleRPG</title><style>body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;font-family:system-ui,sans-serif;
background:#5b93d8;color:#1f2430}.c{background:#fbf6ea;border:3px solid #2b2f3a;border-radius:18px;padding:32px 28px;max-width:320px;text-align:center}
h1{font-size:22px;margin:0 0 12px}p{margin:0;font-size:16px;line-height:1.5}</style></head>
<body><div class="c"><h1>${title}</h1><p>${body}</p></div></body></html>`
}

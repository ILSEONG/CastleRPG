// 환경 변수 → 서버 설정. 위험한 조합은 Error로 시작을 거부한다(main.ts가 출력하고 종료). 부작용 없음 — 단위 테스트용.
import { join } from 'node:path'

export const DEV_SECRET = 'castlerpg-dev-only-secret-do-not-use-in-production'
export const MIN_SECRET_LEN = 32
export const OAUTH_PROVIDERS = ['google', 'kakao', 'naver']

const isLoopback = (h: string) => h === 'localhost' || h === '::1' || /^127\.\d+\.\d+\.\d+$/.test(h)

export function readEnv(env: Record<string, string | undefined>) {
  const databaseUrl = env.DATABASE_URL?.trim() ?? ''
  let secret = env.JWT_SECRET?.trim() ?? ''
  const allowTestHooks = env.ALLOW_TEST_HOOKS === '1'
  const warnings: string[] = []
  if (databaseUrl) {
    if (!secret) throw new Error('DATABASE_URL is set but JWT_SECRET is missing')
    if (secret.length < MIN_SECRET_LEN) throw new Error(`JWT_SECRET must be at least ${MIN_SECRET_LEN} characters when DATABASE_URL is set`)
    if (allowTestHooks) throw new Error('ALLOW_TEST_HOOKS=1 is not allowed when DATABASE_URL is set')
  }
  // 개발 모드는 이 컴퓨터에서만 받는다. 운영은 모든 주소.
  const hostname = env.HOST?.trim() || (databaseUrl ? '0.0.0.0' : '127.0.0.1')
  if (!secret) {
    if (!isLoopback(hostname)) throw new Error(`the fixed dev JWT secret is only allowed on a loopback HOST, not '${hostname}'; set JWT_SECRET`)
    secret = DEV_SECRET
    warnings.push('dev mode (no DATABASE_URL) - using the fixed dev JWT secret; never use this setup in production')
  }
  if (allowTestHooks) warnings.push('ALLOW_TEST_HOOKS=1 - /v1/test/age is enabled')
  // 소셜 로그인 provider: ID와 SECRET을 둘 다 준 것만 켜진다
  const oauth: Record<string, { id: string; secret: string }> = {}
  for (const p of OAUTH_PROVIDERS) {
    const key = p.toUpperCase()
    const id = env[`OAUTH_${key}_ID`]?.trim() ?? ''
    const sec = env[`OAUTH_${key}_SECRET`]?.trim() ?? ''
    if (id && sec) oauth[p] = { id, secret: sec }
    else if (id || sec) throw new Error(`OAUTH_${key}_ID and OAUTH_${key}_SECRET must be set together`)
  }
  const publicUrl = (env.PUBLIC_URL?.trim() ?? '').replace(/\/+$/, '')
  if (databaseUrl && Object.keys(oauth).length && !publicUrl) throw new Error('PUBLIC_URL is required when an OAuth provider is configured with DATABASE_URL')
  return {
    databaseUrl,
    secret,
    allowTestHooks,
    oauth,
    publicUrl,
    hostname,
    port: Number(env.PORT || 8787),
    corsOrigins: (env.CORS_ORIGINS ?? '').split(',').map((s) => s.trim()).filter(Boolean),
    pgliteDir: env.PGLITE_DIR?.trim() || join(import.meta.dirname, '..', '.data', 'dev'),
    warnings,
  }
}

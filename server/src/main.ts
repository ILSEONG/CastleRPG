// 서버 시작: 환경 변수 검사(env.ts) → DB 열기(개발 모드면 마이그레이션 + 빈 기획 표 시드) → 포트 열기.
import { serve } from '@hono/node-server'
import { createApp } from './app.ts'
import { migrate, openDb } from './db.ts'
import { readEnv } from './env.ts'
import { enabledProviders } from './oauth.ts'
import type { OAuthConfig } from './oauth.ts'
import { planningEmpty, seed } from './seed.ts'
import { WarLive } from './war_live.ts'
import { readPayments } from './payments.ts'

let cfg: ReturnType<typeof readEnv>
try {
  cfg = readEnv(process.env)
} catch (e) {
  console.error(`[server] ${(e as Error).message} - refusing to start`)
  process.exit(1)
}
for (const w of cfg.warnings) console.warn(`[server] WARNING: ${w}`)
const { databaseUrl, pgliteDir, hostname, port, gameCacheSec } = cfg

const db = await openDb({ databaseUrl, pgliteDir })
if (!databaseUrl) {
  const applied = await migrate(db)
  if (applied.length) console.log(`[server] migrations applied: ${applied.join(', ')}`)
  if (await planningEmpty(db.query)) {
    const r = await seed(db)
    console.log(`[server] seeded planning tables from data/*.csv: ${Object.entries(r).map(([k, v]) => `${k}=${v.upserted}`).join(' ')}`)
  }
}

// 소셜 로그인 설정(env.ts: OAUTH_<PROVIDER>_ID/SECRET + PUBLIC_URL — 콜백은 PUBLIC_URL/v1/auth/<provider>/callback).
// 테스트 훅 서버에 제공자 키가 없으면 앱이 가짜 설정(oauth.TEST_CONFIG)을 쓴다 — /v1/test/oauth_complete로 로그인 흐름을 시험한다
const envOauth: OAuthConfig = {
  redirectBase: cfg.publicUrl,
  providers: Object.fromEntries(Object.entries(cfg.oauth).map(([p, k]) => [p, { clientId: k.id, clientSecret: k.secret }])),
}
const oauth = cfg.allowTestHooks && enabledProviders(envOauth).length === 0 ? undefined : envOauth
console.log(`[server] social login: ${oauth ? enabledProviders(oauth).join(', ') || 'off' : 'test providers (ALLOW_TEST_HOOKS)'}${oauth?.redirectBase ? ` (callbacks under ${oauth.redirectBase})` : ''}`)
const warLive = new WarLive() // 공성전 실시간 방(WebSocket /v1/guild/war/live)
// 실결제 확인(payments.ts): GOOGLE_PLAY_SERVICE_ACCOUNT(+GOOGLE_PLAY_PACKAGE)·TOSS_MTLS_CERT/KEY(+TOSS_SKUS). 설정된 것만 결제가 열린다
let payments: ReturnType<typeof readPayments>
try {
  payments = readPayments(process.env)
} catch (e) {
  console.error(`[server] payments: ${(e as Error).message} - refusing to start`)
  process.exit(1)
}
console.log(`[server] payments: ${['google', 'toss'].filter((k) => (payments as any)[k]).join(', ') || 'off'}`)
// 약관·개인정보처리방침 운영자·사업자등록번호(기본값 = 사장님 사업자, 2026-10-14)·연락처. 환경 변수가 있으면 그 값
const legal = {
  operator: process.env.LEGAL_OPERATOR?.trim() || '일성게임즈',
  bizNo: process.env.LEGAL_BIZ_NO?.trim() || '227-15-93850',
  email: process.env.LEGAL_EMAIL?.trim() ?? '',
}
const app = createApp({ query: db.query, jwtSecret: cfg.secret, allowTestHooks: cfg.allowTestHooks, corsOrigins: cfg.corsOrigins, oauth, warLive, gameCacheSec, payments, legal })
const server = serve({ fetch: app.fetch, port, hostname }, (info) => {
  const store = databaseUrl ? 'neon' : `pglite ${pgliteDir === 'memory' ? '(memory)' : pgliteDir}`
  console.log(`[server] listening on http://${hostname}:${info.port} (${store})`)
})
warLive.attach(server as import('node:http').Server)

// 자기 깨우기: 공개 주소로 들어오는 요청이어야 호스팅이 "활동"으로 센다(Render 무료 인스턴스 15분 규칙). 실패해도 경고만.
if (cfg.keepAliveMin > 0) {
  const url = `${cfg.publicUrl}/v1/health`
  setInterval(() => fetch(url).catch((e) => console.warn(`[server] keep-alive ping failed: ${(e as Error).message}`)), cfg.keepAliveMin * 60_000).unref()
  console.log(`[server] keep-alive: GET ${url} every ${cfg.keepAliveMin} min`)
}

let stopping = false
async function stop() {
  if (stopping) return
  stopping = true
  warLive.close()
  server.close()
  await db.close()
  process.exit(0)
}
process.on('SIGINT', stop)
process.on('SIGTERM', stop)

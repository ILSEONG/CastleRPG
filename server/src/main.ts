// 서버 시작: 환경 변수 읽기 → DB 열기(개발 모드면 마이그레이션 + 빈 기획 표 시드) → 포트 열기.
import { join } from 'node:path'
import { serve } from '@hono/node-server'
import { createApp } from './app.ts'
import { migrate, openDb } from './db.ts'
import { planningEmpty, seed } from './seed.ts'

const DEV_SECRET = 'castlerpg-dev-only-secret-do-not-use-in-production'

const env = process.env
const databaseUrl = env.DATABASE_URL?.trim() ?? ''
let secret = env.JWT_SECRET?.trim() ?? ''

if (databaseUrl && !secret) {
  console.error('[server] DATABASE_URL is set but JWT_SECRET is missing - refusing to start')
  process.exit(1)
}
if (databaseUrl && secret.length < 32) console.warn('[server] WARNING: JWT_SECRET is shorter than 32 characters')
if (!databaseUrl && !secret) {
  secret = DEV_SECRET
  console.warn('[server] WARNING: dev mode (no DATABASE_URL) - using the fixed dev JWT secret; never use this setup in production')
}
const allowTestHooks = env.ALLOW_TEST_HOOKS === '1'
if (allowTestHooks) console.warn('[server] WARNING: ALLOW_TEST_HOOKS=1 - /v1/test/age is enabled')

const pgliteDir = env.PGLITE_DIR?.trim() || join(import.meta.dirname, '..', '.data', 'dev')
const db = await openDb({ databaseUrl, pgliteDir })
if (!databaseUrl) {
  const applied = await migrate(db)
  if (applied.length) console.log(`[server] migrations applied: ${applied.join(', ')}`)
  if (await planningEmpty(db.query)) {
    const r = await seed(db.query)
    console.log(`[server] seeded planning tables from data/*.csv: ${Object.entries(r).map(([k, v]) => `${k}=${v.upserted}`).join(' ')}`)
  }
}

const app = createApp({
  query: db.query,
  jwtSecret: secret,
  allowTestHooks,
  corsOrigins: (env.CORS_ORIGINS ?? '').split(',').map((s) => s.trim()).filter(Boolean),
})
const port = Number(env.PORT || 8787)
// 개발 모드는 이 컴퓨터에서만 받는다(고정 개발 비밀이라 밖에 열지 않는다). 운영은 모든 주소.
const hostname = env.HOST?.trim() || (databaseUrl ? '0.0.0.0' : '127.0.0.1')
const server = serve({ fetch: app.fetch, port, hostname }, (info) => {
  const store = databaseUrl ? 'neon' : `pglite ${pgliteDir === 'memory' ? '(memory)' : pgliteDir}`
  console.log(`[server] listening on http://${hostname}:${info.port} (${store})`)
})

let stopping = false
async function stop() {
  if (stopping) return
  stopping = true
  server.close()
  await db.close()
  process.exit(0)
}
process.on('SIGINT', stop)
process.on('SIGTERM', stop)

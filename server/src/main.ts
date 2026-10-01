// 서버 시작: 환경 변수 검사(env.ts) → DB 열기(개발 모드면 마이그레이션 + 빈 기획 표 시드) → 포트 열기.
import { serve } from '@hono/node-server'
import { createApp } from './app.ts'
import { migrate, openDb } from './db.ts'
import { readEnv } from './env.ts'
import { planningEmpty, seed } from './seed.ts'

let cfg: ReturnType<typeof readEnv>
try {
  cfg = readEnv(process.env)
} catch (e) {
  console.error(`[server] ${(e as Error).message} - refusing to start`)
  process.exit(1)
}
for (const w of cfg.warnings) console.warn(`[server] WARNING: ${w}`)
const { databaseUrl, pgliteDir, hostname, port } = cfg

const db = await openDb({ databaseUrl, pgliteDir })
if (!databaseUrl) {
  const applied = await migrate(db)
  if (applied.length) console.log(`[server] migrations applied: ${applied.join(', ')}`)
  if (await planningEmpty(db.query)) {
    const r = await seed(db)
    console.log(`[server] seeded planning tables from data/*.csv: ${Object.entries(r).map(([k, v]) => `${k}=${v.upserted}`).join(' ')}`)
  }
}

const app = createApp({ query: db.query, jwtSecret: cfg.secret, allowTestHooks: cfg.allowTestHooks, corsOrigins: cfg.corsOrigins })
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

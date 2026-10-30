// DB 접근은 query(text, params) -> rows 하나. DATABASE_URL이 있으면 연결 풀(pg, TCP) — 안 되면 Neon HTTP, 없으면 PGlite(디렉터리 또는 메모리).
// 연결 풀(2026-10-30 사용자 "1~4번 다 해줘"의 2번): Neon HTTP는 쿼리마다 HTTPS 요청을 새로 보내 서버 CPU를 약 2배 쓴다(부하 측정 15% 대 8%).
// 열어 둔 연결을 다시 쓰고, 쉬는 연결은 POOL_IDLE_MS 뒤 닫는다 — 접속자가 없으면 Neon이 잠들 수 있게(무료 사용 시간).
import { mkdir, readdir, readFile } from 'node:fs/promises'
import { join } from 'node:path'

export type Row = Record<string, any>
export type Query = (text: string, params?: unknown[]) => Promise<Row[]>
export interface Stmt {
  text: string
  params?: unknown[]
}
export interface Db {
  query: Query
  batch: (stmts: Stmt[]) => Promise<Row[][]> // 한 트랜잭션(비대화형), 문장별 결과 행
  close: () => Promise<void>
}

export const MIGRATIONS_DIR = join(import.meta.dirname, '..', 'migrations')

// pgliteDir가 비었거나 "memory"면 메모리 DB.
export const POOL_MAX = 10
export const POOL_IDLE_MS = 60_000

// driver: 'pool'(기본, 시작할 때 select 1이 안 되면 'http'로) · 'http'(DB_DRIVER=http로 강제).
export async function openDb(opts: { databaseUrl?: string; pgliteDir?: string; driver?: string; log?: (m: string) => void } = {}): Promise<Db & { driver: string }> {
  if (opts.databaseUrl && opts.driver !== 'http') {
    try {
      return { ...(await openPool(opts.databaseUrl)), driver: 'pool' }
    } catch (e) {
      opts.log?.(`connection pool failed (${(e as Error).message}) - using Neon HTTP`)
    }
  }
  if (opts.databaseUrl) {
    const { neon } = await import('@neondatabase/serverless')
    const sql = neon(opts.databaseUrl)
    return {
      // sql.query()는 then마다 다시 실행되는 지연 객체 — 여기서 한 번만 await해 진짜 Promise로 바꾼다.
      query: async (text, params = []) => (await sql.query(text, params)) as Row[],
      batch: async (stmts) => (await sql.transaction(stmts.map((s) => sql.query(s.text, s.params ?? [])))) as Row[][],
      close: async () => {},
      driver: 'http',
    }
  }
  const { PGlite } = await import('@electric-sql/pglite')
  const dir = opts.pgliteDir && opts.pgliteDir !== 'memory' ? opts.pgliteDir : undefined
  if (dir) await mkdir(dir, { recursive: true })
  const pg = new PGlite(dir)
  await pg.waitReady
  return {
    query: async (text, params = []) => (await pg.query<Row>(text, params)).rows,
    batch: (stmts) => pg.transaction(async (tx) => {
      const out: Row[][] = []
      for (const s of stmts) out.push((await tx.query<Row>(s.text, s.params ?? [])).rows)
      return out
    }),
    close: () => pg.close(),
    driver: 'pglite',
  }
}

// pg 연결 풀. 값 해석(int8·numeric = 문자열, json = 값, timestamptz = Date)은 Neon HTTP 드라이버와 같다.
export async function openPool(url: string, max = POOL_MAX): Promise<Db> {
  const { default: pg } = await import('pg')
  const u = new URL(url)
  const local = u.hostname === 'localhost' || u.hostname === '127.0.0.1'
  // 연결 문자열의 sslmode는 pg가 verify-full처럼 다루는데, Neon은 공인 인증서라 그대로 검증한다. 로컬 시험 DB만 TLS 없이.
  const pool = new pg.Pool({ connectionString: url, max, idleTimeoutMillis: POOL_IDLE_MS, connectionTimeoutMillis: 10_000, ssl: local ? false : { rejectUnauthorized: true } })
  pool.on('error', () => {}) // 쉬는 연결이 끊긴 것(Neon이 잠듦 등) — 다음 쿼리가 새 연결을 연다
  await pool.query('select 1')
  return {
    query: async (text, params = []) => (await pool.query(text, params as unknown[])).rows,
    batch: async (stmts) => {
      const c = await pool.connect()
      try {
        await c.query('begin')
        const out: Row[][] = []
        for (const s of stmts) out.push((await c.query(s.text, (s.params ?? []) as unknown[])).rows)
        await c.query('commit')
        return out
      } catch (e) {
        await c.query('rollback').catch(() => {})
        throw e
      } finally {
        c.release()
      }
    },
    close: () => pool.end(),
  }
}

// 준비된 문장은 한 번에 한 문장만 된다 — 줄 주석을 지우고 ;로 나눈다(마이그레이션엔 문자열 속 ;가 없다).
export function splitSql(text: string): string[] {
  return text
    .split('\n')
    .map((l) => l.replace(/--.*$/, ''))
    .join('\n')
    .split(';')
    .map((s) => s.trim())
    .filter(Boolean)
}

// 아직 안 한 마이그레이션 파일을 이름순으로 하나씩 한 트랜잭션에 적용한다. 적용한 파일 이름을 돌려준다.
export async function migrate(db: Db, dir = MIGRATIONS_DIR): Promise<string[]> {
  await db.query('create table if not exists schema_migrations (name text primary key, applied_at timestamptz not null default now())')
  const done = new Set((await db.query('select name from schema_migrations')).map((r) => r.name))
  const files = (await readdir(dir)).filter((f) => f.endsWith('.sql')).sort()
  const applied: string[] = []
  for (const f of files) {
    if (done.has(f)) continue
    const stmts: Stmt[] = splitSql(await readFile(join(dir, f), 'utf8')).map((text) => ({ text }))
    stmts.push({ text: 'insert into schema_migrations (name) values ($1)', params: [f] })
    await db.batch(stmts)
    applied.push(f)
  }
  return applied
}

// DB 접근은 query(text, params) -> rows 하나. DATABASE_URL이 있으면 Neon HTTP, 없으면 PGlite(디렉터리 또는 메모리).
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
export async function openDb(opts: { databaseUrl?: string; pgliteDir?: string } = {}): Promise<Db> {
  if (opts.databaseUrl) {
    const { neon } = await import('@neondatabase/serverless')
    const sql = neon(opts.databaseUrl)
    return {
      // sql.query()는 then마다 다시 실행되는 지연 객체 — 여기서 한 번만 await해 진짜 Promise로 바꾼다.
      query: async (text, params = []) => (await sql.query(text, params)) as Row[],
      batch: async (stmts) => (await sql.transaction(stmts.map((s) => sql.query(s.text, s.params ?? [])))) as Row[][],
      close: async () => {},
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

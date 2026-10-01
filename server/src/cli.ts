// npm run migrate / seed. DATABASE_URL(Neon)에 적용한다. 없으면 개발용 PGlite(server/.data/dev 또는 PGLITE_DIR).
import { join } from 'node:path'
import { migrate, openDb } from './db.ts'
import { CsvError, seed } from './seed.ts'

const cmd = process.argv[2]
if (cmd !== 'migrate' && cmd !== 'seed') {
  console.error('usage: node src/cli.ts migrate|seed')
  process.exit(2)
}
const databaseUrl = process.env.DATABASE_URL?.trim() ?? ''
const pgliteDir = process.env.PGLITE_DIR?.trim() || join(import.meta.dirname, '..', '.data', 'dev')
console.log(`[${cmd}] target: ${databaseUrl ? 'DATABASE_URL (neon)' : `pglite ${pgliteDir}`}`)
const db = await openDb({ databaseUrl, pgliteDir })
try {
  if (cmd === 'migrate') {
    const applied = await migrate(db)
    console.log(applied.length ? `[migrate] applied: ${applied.join(', ')}` : '[migrate] up to date')
  } else {
    const r = await seed(db.query)
    for (const [t, v] of Object.entries(r)) console.log(`[seed] ${t}: ${v.upserted} upserted, ${v.deleted} deleted`)
  }
} catch (e) {
  console.error(e instanceof CsvError ? e.message : e)
  process.exitCode = 1
} finally {
  await db.close()
}

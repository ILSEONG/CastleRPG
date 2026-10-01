// 마이그레이션·시드: CSV 행 수 = DB 행 수, CSV 규칙(BOM·빈 줄·쉼표만 줄·열 순서), 오류 위치, 사라진 키 삭제.
import assert from 'node:assert/strict'
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { after, before, test } from 'node:test'
import { migrate, openDb } from '../src/db.ts'
import type { Db } from '../src/db.ts'
import { CsvError, DATA_DIR, parseCsv, readTables, seed, TABLES } from '../src/seed.ts'

let db: Db
const tmp: string[] = []
before(async () => {
  db = await openDb({})
})
after(async () => {
  await db.close()
  for (const d of tmp) rmSync(d, { recursive: true, force: true })
})

// data 폴더 사본(일부 파일 바꿔 쓰기용)
function dataCopy(changes: Record<string, string> = {}): string {
  const d = mkdtempSync(join(tmpdir(), 'castle-data-'))
  tmp.push(d)
  for (const t of TABLES) cpSync(join(DATA_DIR, t.file), join(d, t.file))
  for (const [f, text] of Object.entries(changes)) writeFileSync(join(d, f), text)
  return d
}

const csvRows = (file: string) => readFileSync(join(DATA_DIR, file), 'utf8').split('\n').slice(1).filter((l) => l.replace(/,/g, '').trim() !== '').length

test('마이그레이션: 적용하고 기록, 두 번째는 아무것도 안 함', async () => {
  assert.deepEqual(await migrate(db), ['001_init.sql'])
  assert.deepEqual(await migrate(db), [])
  const rows = await db.query('select name from schema_migrations')
  assert.deepEqual(rows.map((r) => r.name), ['001_init.sql'])
})

test('시드: 표마다 CSV 행 수 = DB 행 수, 다시 해도 같다', async () => {
  for (let i = 0; i < 2; i++) {
    const r = await seed(db.query)
    for (const t of TABLES) {
      const [c] = await db.query(`select count(*)::int as n from ${t.table}`)
      assert.equal(c.n, csvRows(t.file), `${t.table} rows`)
      assert.equal(r[t.name].upserted, csvRows(t.file))
      assert.equal(r[t.name].deleted, 0)
    }
  }
  const [s2] = await db.query('select atk_mult from stages where stage = 2')
  assert.equal(s2.atk_mult, 1.15) // real 왕복이 1.149999…로 바뀌지 않는다
  const [w] = await db.query("select name, building, per_min, price from resources where id = 'wood'")
  assert.deepEqual(w, { name: '목재', building: 'lumber', per_min: 10, price: 1 })
  const [cfg] = await db.query("select value from game_config where key = 'hero_slots'")
  assert.equal(cfg.value, '4|8|12')
})

test('시드: CSV에서 사라진 키는 지우고, 바뀐 값은 덮어쓴다', async () => {
  const dir = dataCopy({ 'monsters.csv': 'id,hp,atk,speed,range,atk_interval,aggro,scale,gold\ngrunt,61,10,2.5,1.2,1.0,6.0,1.0,3\n' })
  const r = await seed(db.query, dir)
  assert.deepEqual(r.monsters, { upserted: 1, deleted: 1 })
  const rows = await db.query('select id, hp, gold from monsters')
  assert.deepEqual(rows, [{ id: 'grunt', hp: 61, gold: 3 }])
  await seed(db.query) // 원래대로
  assert.equal((await db.query('select count(*)::int as n from monsters'))[0].n, 2)
})

test('CSV 규칙: BOM, CRLF, 빈 줄, 쉼표만 있는 줄, 열 순서가 달라도 같은 결과', async () => {
  const plain = await readTables(DATA_DIR)
  const messy = '﻿gold,id,scale,aggro,atk_interval,range,speed,atk,hp\r\n\r\n,,,,,,,,\r\n2,grunt,1.0,6.0,1.0,1.2,2.5,10,60\r\n  \r\n50,epic_boss,1.6,8.0,1.2,1.8,1.8,20,400\r\n,,,\r\n'
  const t = await readTables(dataCopy({ 'monsters.csv': messy }))
  const strip = (rows: Record<string, unknown>[]) => rows.map(({ _line, ...r }) => r)
  assert.deepEqual(strip(t.monsters), strip(plain.monsters))
})

test('CSV 오류: 파일·줄·열을 알리고 아무것도 쓰지 않는다', async () => {
  const errs: string[] = []
  parseCsv('id,hp\ngrunt,abc\nboss,\n', 'm.csv', { id: 'key', hp: 'num' }, errs)
  assert.deepEqual(errs, ["m.csv line 2 column 'hp': not a number: 'abc'", "m.csv line 3 column 'hp': not a number: ''"])

  const bad = dataCopy({
    'monsters.csv': 'id,hp,atk,speed,range,atk_interval,aggro,scale\ngrunt,60,10,2.5,1.2,1.0,6.0,1.0\n', // gold 열 없음
    'stages.csv': 'stage,hp_mult,atk_mult,gold_mult,waves,wave_size,idle_interval\n1,1,1,1,3,8,4\n3,1,1,1,3,8,4\n', // 2 빠짐
    'resources.csv': 'id,name,building,per_min,price\nwood,목재,lumber,10,1\nwood,목재,quarry,5,2\nstone,석재,quarry,10.5,2\n', // 중복 키, 정수 아님
    'config.csv': 'key,value\ncastle_hp,lots\n', // 숫자 아님 + 필수 키 없음
  })
  await db.query("update monsters set hp = 999 where id = 'grunt'")
  await assert.rejects(seed(db.query, bad), (e: unknown) => {
    assert.ok(e instanceof CsvError)
    const m = e.errors.join('\n')
    assert.match(m, /monsters\.csv line 1 column 'gold': missing column/)
    assert.match(m, /stages\.csv line 3 column 'stage': stage must continue from 1 without gaps/)
    assert.match(m, /resources\.csv line 4 column 'per_min': not an integer: '10\.5'/)
    assert.match(m, /resources\.csv line 3 column 'id': duplicate key 'wood'/)
    assert.match(m, /config\.csv line 2 column 'value': not a number: 'lots'/)
    assert.match(m, /config\.csv line 0 column 'key': missing key 'kill_rate_cap'/)
    return true
  })
  const [g] = await db.query("select hp from monsters where id = 'grunt'")
  assert.equal(g.hp, 999) // 부분 반영 없음
  await seed(db.query)
})

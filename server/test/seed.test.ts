// 마이그레이션·시드: CSV 행 수 = DB 행 수, CSV 규칙(BOM·빈 줄·쉼표만 줄·열 순서), 오류 위치, 사라진 키 삭제.
import assert from 'node:assert/strict'
import { cpSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { after, before, test } from 'node:test'
import { MIGRATIONS_DIR, migrate, openDb } from '../src/db.ts'
import type { Db } from '../src/db.ts'
import { CsvError, DATA_DIR, parseCsv, readTables, seed, TABLES } from '../src/seed.ts'

let db: Db
const tmp: string[] = []
before(async () => {
  db = await openDb({})
})
after(async () => {
  await db.close()
  for (const d of tmp) {
    try {
      rmSync(d, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 }) // Windows: 백신 등이 막 만든 파일을 잡고 있으면 EBUSY·EPERM
    } catch (e) {
      console.warn(`[seed.test] temp dir left behind: ${d} (${(e as Error).message})`) // OS 임시 폴더라 남아도 해가 없다 — 실패로 치지 않는다
    }
  }
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

const ALL_MIGRATIONS = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort()

test('마이그레이션: 적용하고 기록, 두 번째는 아무것도 안 함', async () => {
  assert.ok(ALL_MIGRATIONS.includes('004_heroes.sql'))
  assert.deepEqual(await migrate(db), ALL_MIGRATIONS)
  assert.deepEqual(await migrate(db), [])
  const rows = await db.query('select name from schema_migrations order by name')
  assert.deepEqual(rows.map((r) => r.name), ALL_MIGRATIONS)
})

test('마이그레이션 003: 001·002만 적용된 DB에서 올리면 gold가 gold_tenths(× 10)가 된다', async () => {
  const old = mkdtempSync(join(tmpdir(), 'castle-mig-'))
  tmp.push(old)
  for (const f of ['001_init.sql', '002_kill_seq_stage_clear.sql']) cpSync(join(MIGRATIONS_DIR, f), join(old, f))
  const d = await openDb({})
  try {
    await migrate(d, old)
    const [p] = await d.query("insert into players (device_id) values ('mig-test-device-0001') returning id")
    await d.query('insert into player_state (player_id, gold) values ($1, 7)', [p.id])
    const applied = await migrate(d)
    assert.equal(applied[0], '003_gold_tenths.sql')
    const [s] = await d.query('select gold_tenths from player_state where player_id = $1', [p.id])
    assert.equal(Number(s.gold_tenths), 70)
    await assert.rejects(d.query('select gold from player_state'))
  } finally {
    await d.close()
  }
})

test('마이그레이션 004: 001·002만 적용된 DB에서 hero_roles를 heroes로 바꾸고, 시드가 22행을 채운다', async () => {
  const old = await openDb({})
  const dir = mkdtempSync(join(tmpdir(), 'castle-mig-'))
  tmp.push(dir)
  for (const f of ['001_init.sql', '002_kill_seq_stage_clear.sql']) cpSync(join(MIGRATIONS_DIR, f), join(dir, f))
  await migrate(old, dir)
  await old.query("insert into hero_roles (id, name, hp, atk, range, atk_interval, speed, aggro) values ('warrior', '전사', 400, 30, 1.8, 0.8, 6, 8)")
  assert.ok((await migrate(old)).includes('004_heroes.sql'))
  assert.equal((await old.query("select to_regclass('hero_roles') as t"))[0].t, null)
  assert.equal((await old.query('select count(*)::int as n from heroes'))[0].n, 0)
  await seed(old)
  assert.equal((await old.query('select count(*)::int as n from heroes'))[0].n, 22)
  await old.close()
})

test('마이그레이션 003~005: 001·002만 적용된 DB에서 올리면 gold × 10, 기존 플레이어는 시작 영웅(copies 1)과 그 순서의 배치를 받는다', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'castle-mig-'))
  tmp.push(dir)
  for (const f of ['001_init.sql', '002_kill_seq_stage_clear.sql']) cpSync(join(MIGRATIONS_DIR, f), join(dir, f))
  const d = await openDb({})
  try {
    await migrate(d, dir)
    const ids: string[] = []
    for (const dev of ['mig-005-device-0001', 'mig-005-device-0002']) {
      const [p] = await d.query('insert into players (device_id) values ($1) returning id', [dev])
      await d.query('insert into player_state (player_id, gold) values ($1, 7)', [p.id])
      ids.push(p.id)
    }
    const applied = await migrate(d)
    assert.deepEqual(applied.slice(0, 3), ['003_gold_tenths.sql', '004_heroes.sql', '005_player_heroes.sql'])
    for (const id of ids) {
      const [s] = await d.query('select gold_tenths, deploy from player_state where player_id = $1', [id])
      assert.deepEqual([Number(s.gold_tenths), s.deploy], [70, ['hans', 'ella', 'dorik', 'nina']]) // 시드 전: 스펙 기본 시작 영웅
      const h = await d.query('select hero_id, copies from player_heroes where player_id = $1 order by hero_id', [id])
      assert.deepEqual(h.map((r) => `${r.hero_id}:${r.copies}`), ['dorik:1', 'ella:1', 'hans:1', 'nina:1'])
    }
    await assert.rejects(d.query("insert into player_heroes (player_id, hero_id, copies) values ($1, 'jack', 0)", [ids[0]]))
    await seed(d)
    assert.equal((await d.query('select count(*)::int as n from heroes'))[0].n, 22)
  } finally {
    await d.close()
  }
})

test('마이그레이션 005: game_config에 starter_heroes가 있으면 그 목록·순서를 쓴다', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'castle-mig-'))
  tmp.push(dir)
  for (const f of ALL_MIGRATIONS.filter((f) => f < '005')) cpSync(join(MIGRATIONS_DIR, f), join(dir, f))
  const d = await openDb({})
  try {
    await migrate(d, dir)
    await d.query("insert into game_config (key, value) values ('starter_heroes', 'nina| jack')")
    const [p] = await d.query("insert into players (device_id) values ('mig-005-device-0003') returning id")
    await d.query('insert into player_state (player_id) values ($1)', [p.id])
    assert.deepEqual(await migrate(d), ALL_MIGRATIONS.filter((f) => f >= '005'))
    const [s] = await d.query('select deploy from player_state where player_id = $1', [p.id])
    assert.deepEqual(s.deploy, ['nina', 'jack'])
    const h = await d.query('select hero_id from player_heroes where player_id = $1 order by hero_id', [p.id])
    assert.deepEqual(h.map((r) => r.hero_id), ['jack', 'nina'])
  } finally {
    await d.close()
  }
})

test('시드: 표마다 CSV 행 수 = DB 행 수, 다시 해도 같다', async () => {
  for (let i = 0; i < 2; i++) {
    const r = await seed(db)
    for (const t of TABLES) {
      const [c] = await db.query(`select count(*)::int as n from ${t.table}`)
      assert.equal(c.n, csvRows(t.file), `${t.table} rows`)
      assert.equal(r[t.name].upserted, csvRows(t.file))
      assert.equal(r[t.name].deleted, 0)
    }
  }
  const [s2] = await db.query('select atk_mult from stages where stage = 2')
  assert.equal(s2.atk_mult, 1.1) // real 왕복이 1.149999…로 바뀌지 않는다
  const [w] = await db.query("select name, building, per_min, price from resources where id = 'wood'")
  assert.deepEqual(w, { name: '목재', building: 'lumber', per_min: 10, price: 1 })
  const [cfg] = await db.query("select value from game_config where key = 'hero_slots'")
  assert.equal(cfg.value, '4|8|12')
  const [ig] = await db.query(`select title, grade, gear, s1b, skill2, s2a, "desc" from heroes where id = 'ignis'`)
  assert.deepEqual(ig, { title: '화염 대마법사', grade: 'SSR', gear: '2H_Staff', s1b: 3.5, skill2: null, s2a: null, desc: '몰려오는 무리 한가운데 거대한 화염구를 떨어뜨린다' })
  const [st] = await db.query("select value from game_config where key = 'starter_heroes'")
  assert.equal(st.value, 'hans|ella|dorik|nina')
})

test('영웅 CSV: 빈 스킬 칸은 null, 숫자 칸 오류, 시작 영웅은 영웅 표에, 등급은 DB 제약', async () => {
  const errs: string[] = []
  const rows = parseCsv('id,skill,a\nx,,\ny,crit,abc\n', 'h.csv', { id: 'key', skill: 'opt', a: 'optnum' }, errs)
  assert.deepEqual(rows.map(({ _line, ...r }) => r), [{ id: 'x', skill: null, a: null }])
  assert.deepEqual(errs, ["h.csv line 3 column 'a': not a number: 'abc'"])
  const cfg = readFileSync(join(DATA_DIR, 'config.csv'), 'utf8').replace('starter_heroes,hans|', 'starter_heroes,ghost|')
  await assert.rejects(readTables(dataCopy({ 'config.csv': cfg })), /unknown hero 'ghost' in starter_heroes/)
  const heroes = readFileSync(join(DATA_DIR, 'heroes.csv'), 'utf8').replace(',SSR,', ',UR,')
  await assert.rejects(seed(db, dataCopy({ 'heroes.csv': heroes })))
  assert.equal((await db.query("select grade from heroes where id = 'arteon'"))[0].grade, 'SSR')
})

test('시드: CSV에서 사라진 키는 지우고, 바뀐 값은 덮어쓴다', async () => {
  const dir = dataCopy({ 'monsters.csv': 'id,hp,atk,speed,range,atk_interval,aggro,scale,gold\ngrunt,61,10,2.5,1.2,1.0,6.0,1.0,3\n' })
  const r = await seed(db, dir)
  assert.deepEqual(r.monsters, { upserted: 1, deleted: 1 })
  const rows = await db.query('select id, hp, gold from monsters')
  assert.deepEqual(rows, [{ id: 'grunt', hp: 61, gold: 3 }])
  await seed(db) // 원래대로
  assert.equal((await db.query('select count(*)::int as n from monsters'))[0].n, 2)
})

test('시드는 한 트랜잭션: 뒤 문장이 실패하면 앞 표도 안 바뀐다', async () => {
  const dir = dataCopy({ 'monsters.csv': 'id,hp,atk,speed,range,atk_interval,aggro,scale,gold\ngrunt,61,10,2.5,1.2,1.0,6.0,1.0,3\n' })
  const failing = { batch: (s: { text: string; params?: unknown[] }[]) => db.batch([...s, { text: 'select 1 / 0' }]) }
  await assert.rejects(seed(failing, dir))
  assert.equal((await db.query('select count(*)::int as n from monsters'))[0].n, 2)
  assert.equal((await db.query("select gold from monsters where id = 'grunt'"))[0].gold, 2)
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
  await assert.rejects(seed(db, bad), (e: unknown) => {
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
  await seed(db)
})

test('모집 설정 검증: 비용·보장 수는 0 이상 정수, 확률은 0..1이고 SSR + SR ≤ 1, 등급마다 영웅이 하나 이상', async () => {
  const cfg = readFileSync(join(DATA_DIR, 'config.csv'), 'utf8')
  const dir = dataCopy() // 사본 하나에 config.csv·heroes.csv만 바꿔 쓴다(임시 폴더를 적게)
  const withCfg = (key: string, value: string) => {
    writeFileSync(join(dir, 'config.csv'), cfg.replace(new RegExp(`^${key},.*$`, 'm'), `${key},${value}`))
    return dir
  }
  const cases: [string, string, RegExp][] = [
    ['gacha_cost_1', '300.5', /gacha_cost_1 must be a non-negative integer: '300\.5'/],
    ['gacha_cost_10', '-1', /gacha_cost_10 must be a non-negative integer: '-1'/],
    ['gacha_10_min_sr', '1.5', /gacha_10_min_sr must be a non-negative integer: '1\.5'/],
    ['gacha_rate_ssr', '1.5', /gacha_rate_ssr must be in 0\.\.1: '1\.5'/],
    ['gacha_rate_sr', '-0.1', /gacha_rate_sr must be in 0\.\.1: '-0\.1'/],
    ['gacha_rate_sr', '0.98', /gacha_rate_sr plus gacha_rate_ssr must be at most 1: 0\.03 \+ 0\.98/],
  ]
  for (const [key, value, re] of cases) {
    await assert.rejects(readTables(withCfg(key, value)), (e: unknown) => {
      assert.ok(e instanceof CsvError)
      assert.equal(e.errors.length, 1, `${key}=${value}: ${e.errors.join(' | ')}`)
      assert.match(e.errors[0], re)
      return true
    })
  }
  const lines = readFileSync(join(DATA_DIR, 'heroes.csv'), 'utf8').split('\n')
  const noSr = lines.filter((l) => !l.split(',').includes('SR')).join('\n')
  writeFileSync(join(dir, 'config.csv'), cfg)
  writeFileSync(join(dir, 'heroes.csv'), noSr)
  await assert.rejects(readTables(dir), /heroes\.csv line 0 column 'grade': no SR heroes to recruit/)
  writeFileSync(join(dir, 'heroes.csv'), lines.join('\n'))
  await readTables(withCfg('gacha_cost_1', '0')) // 0원 모집·확률 경계(합 1)는 받는다
  await readTables(withCfg('gacha_rate_sr', '0.97'))
})

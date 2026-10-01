// data/*.csv → 기획 표. CSV 규칙은 앱 GameData와 같다: 헤더 이름으로 열 찾기, BOM·빈 줄·쉼표만 있는 줄 무시,
// 숫자 검증, 오류는 파일·줄·열. 오류가 하나라도 있으면 아무것도 쓰지 않는다.
import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import type { Db, Query } from './db.ts'

export const DATA_DIR = join(import.meta.dirname, '..', '..', 'data')

// key = 첫 열(문자열, 비면 오류), text = 문자열, num = 숫자, int = 정수, opt·optnum = 비면 null인 문자열·숫자
type ColType = 'key' | 'text' | 'num' | 'int' | 'opt' | 'optnum'
export interface TableSpec {
  name: string // 응답·CSV 이름
  table: string // DB 표
  file: string
  cols: Record<string, ColType>
  sql: Record<string, string> // 열 → DB 형
  ordered: boolean // ord 열(파일 순서)이 있다
}

const real = (names: string[]) => Object.fromEntries(names.map((n) => [n, 'real']))

export const TABLES: TableSpec[] = [
  {
    name: 'monsters', table: 'monsters', file: 'monsters.csv', ordered: true,
    cols: { id: 'key', hp: 'num', atk: 'num', speed: 'num', range: 'num', atk_interval: 'num', aggro: 'num', scale: 'num', gold: 'int' },
    sql: { id: 'text', ...real(['hp', 'atk', 'speed', 'range', 'atk_interval', 'aggro', 'scale']), gold: 'integer' },
  },
  {
    name: 'stages', table: 'stages', file: 'stages.csv', ordered: false,
    cols: { stage: 'key', hp_mult: 'num', atk_mult: 'num', gold_mult: 'num', waves: 'int', wave_size: 'int', idle_interval: 'num' },
    sql: { stage: 'integer', ...real(['hp_mult', 'atk_mult', 'gold_mult']), waves: 'integer', wave_size: 'integer', idle_interval: 'real' },
  },
  {
    name: 'heroes', table: 'heroes', file: 'heroes.csv', ordered: true,
    cols: {
      id: 'key', name: 'text', title: 'text', grade: 'text', role: 'text', archetype: 'text', model: 'text', gear: 'text', color: 'text',
      hp: 'num', atk: 'num', range: 'num', atk_interval: 'num', speed: 'num', aggro: 'num',
      skill1: 'opt', s1a: 'optnum', s1b: 'optnum', s1c: 'optnum', skill2: 'opt', s2a: 'optnum', s2b: 'optnum', s2c: 'optnum', desc: 'text',
    },
    sql: {
      ...Object.fromEntries(['id', 'name', 'title', 'grade', 'role', 'archetype', 'model', 'gear', 'color'].map((n) => [n, 'text'])),
      ...real(['hp', 'atk', 'range', 'atk_interval', 'speed', 'aggro']),
      skill1: 'text', ...real(['s1a', 's1b', 's1c']), skill2: 'text', ...real(['s2a', 's2b', 's2c']), desc: 'text',
    },
  },
  {
    name: 'resources', table: 'resources', file: 'resources.csv', ordered: true,
    cols: { id: 'key', name: 'text', building: 'text', per_min: 'int', price: 'int' },
    sql: { id: 'text', name: 'text', building: 'text', per_min: 'integer', price: 'integer' },
  },
  {
    name: 'config', table: 'game_config', file: 'config.csv', ordered: false,
    cols: { key: 'key', value: 'text' },
    sql: { key: 'text', value: 'text' },
  },
]

// 서버·앱이 쓰는 설정 키(스펙 §2). 숫자 키는 숫자여야 하고, 목록 키는 `|` 구분 항목이 비지 않아야 한다.
export const CONFIG_NUM = ['castle_hp', 'gate_hp_per_level', 'max_live_monsters', 'countdown_sec', 'result_sec', 'wave_gap_sec',
  'spawn_spacing_sec', 'accum_cap_min', 'badge_min', 'merchant_jackpot_p', 'merchant_jackpot_rate', 'merchant_rate_min',
  'merchant_rate_max', 'merchant_rate_step', 'merchant_low_high_ratio', 'kill_rate_cap', 'kill_burst_sec', 'hero_max_stars', 'hero_star_bonus',
  'gacha_cost_1', 'gacha_cost_10', 'gacha_rate_ssr', 'gacha_rate_sr', 'gacha_10_min_sr']
export const CONFIG_LIST = ['hero_slots', 'starter_heroes']

const NUM_RE = /^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$/
export const isNum = (s: string) => NUM_RE.test(s)

export type CsvRow = Record<string, string | number | null>
export type Tables = Record<string, CsvRow[]>

export class CsvError extends Error {
  errors: string[]
  constructor(errors: string[]) {
    super(`data table errors:\n${errors.join('\n')}`)
    this.errors = errors
  }
}

// 행 배열을 돌려주고, 오류는 errors에 "파일 line N column 'c': 이유"로 쌓는다.
export function parseCsv(text: string, file: string, cols: Record<string, ColType>, errors: string[]): CsvRow[] {
  const err = (line: number, col: string, why: string) => errors.push(`${file} line ${line} column '${col}': ${why}`)
  const names = Object.keys(cols)
  const rows: CsvRow[] = []
  const seen = new Set<string>()
  let idx: Record<string, number> | null = null
  const lines = text.replace(/^﻿/, '').split('\n')
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim()
    if (line.replace(/,/g, '').trim() === '') continue // 빈 줄, 엑셀이 남기는 ",,,,," 줄
    const cells = line.split(',').map((c) => c.trim())
    if (!idx) {
      idx = {}
      for (const c of names) {
        idx[c] = cells.indexOf(c)
        if (idx[c] < 0) err(i + 1, c, 'missing column')
      }
      if (Object.values(idx).includes(-1)) return rows
      continue
    }
    const row: CsvRow = {}
    let ok = true
    for (const c of names) {
      const raw = idx[c] < cells.length ? cells[idx[c]] : ''
      const t = cols[c]
      if ((t === 'opt' || t === 'optnum') && raw === '') {
        row[c] = null
      } else if (t === 'key' || t === 'text' || t === 'opt') {
        if (raw === '') {
          err(i + 1, c, 'empty value')
          ok = false
        } else if (t === 'key' && seen.has(raw)) {
          err(i + 1, c, `duplicate key '${raw}'`)
          ok = false
        }
        row[c] = raw
      } else if (!isNum(raw)) {
        err(i + 1, c, `not a number: '${raw}'`)
        ok = false
      } else if (t === 'int' && !Number.isInteger(Number(raw))) {
        err(i + 1, c, `not an integer: '${raw}'`)
        ok = false
      } else {
        row[c] = Number(raw)
      }
    }
    if (ok) {
      seen.add(String(row[names[0]]))
      row._line = i + 1
      rows.push(row)
    }
  }
  if (!idx) err(0, names[0], 'empty file')
  return rows
}

// 표별 추가 규칙: stage는 1부터 빠짐없이, 설정 키 필수·형식.
function checkTable(spec: TableSpec, rows: CsvRow[], errors: string[]): CsvRow[] {
  const err = (line: number, col: string, why: string) => errors.push(`${spec.file} line ${line} column '${col}': ${why}`)
  if (spec.name === 'stages') {
    const out: CsvRow[] = []
    for (const r of rows) {
      if (!isNum(String(r.stage)) || Number(r.stage) !== out.length + 1) {
        err(Number(r._line), 'stage', 'stage must continue from 1 without gaps')
        break
      }
      out.push({ ...r, stage: out.length + 1 })
    }
    rows = out
  }
  if (spec.name === 'config') {
    const byKey = new Map(rows.map((r) => [String(r.key), r]))
    for (const k of [...CONFIG_NUM, ...CONFIG_LIST]) {
      const r = byKey.get(k)
      if (!r) err(0, 'key', `missing key '${k}'`)
      else if (CONFIG_NUM.includes(k) && !isNum(String(r.value))) err(Number(r._line), 'value', `not a number: '${r.value}'`)
      else if (CONFIG_LIST.includes(k) && String(r.value).split('|').some((p) => p.trim() === '')) err(Number(r._line), 'value', `empty list item: '${r.value}'`)
    }
  }
  if (rows.length === 0 && !errors.some((e) => e.startsWith(`${spec.file} `))) err(0, Object.keys(spec.cols)[0], 'no rows')
  return rows
}

// data 폴더의 CSV 전부를 읽어 검증한다. 오류가 있으면 CsvError.
export async function readTables(dataDir = DATA_DIR): Promise<Tables> {
  const errors: string[] = []
  const out: Tables = {}
  for (const spec of TABLES) {
    const path = join(dataDir, spec.file)
    let text: string
    try {
      text = await readFile(path, 'utf8')
    } catch {
      errors.push(`${spec.file} line 0 column '': cannot open file`)
      continue
    }
    out[spec.name] = checkTable(spec, parseCsv(text, spec.file, spec.cols, errors), errors)
  }
  // 시작 영웅은 영웅 표에 있어야 한다(새 플레이어가 받는다)
  const starters = out.config?.find((r) => r.key === 'starter_heroes')
  const heroIds = new Set((out.heroes ?? []).map((h) => String(h.id)))
  for (const id of String(starters?.value ?? '').split('|').map((x) => x.trim()).filter(Boolean)) {
    if (out.heroes && !heroIds.has(id)) errors.push(`config.csv line ${starters?._line} column 'value': unknown hero '${id}' in starter_heroes`)
  }
  if (errors.length) throw new CsvError(errors)
  return out
}

// 열 이름은 따옴표로 — desc 같은 예약어도 CSV 열 이름 그대로 쓴다.
export const ident = (c: string) => `"${c}"`

// 표 하나를 한 문장으로 upsert + 사라진 키 삭제.
function seedSql(spec: TableSpec): string {
  const cols = Object.keys(spec.sql)
  const all = spec.ordered ? [...cols, 'ord'] : cols
  const def = all.map((c) => `${ident(c)} ${c === 'ord' ? 'integer' : spec.sql[c]}`).join(', ')
  const key = ident(cols[0])
  const set = all.slice(1).map((c) => `${ident(c)} = excluded.${ident(c)}`).join(', ')
  const list = all.map(ident).join(', ')
  return `with src as (select * from jsonb_to_recordset($1::jsonb) as x(${def})),
    up as (insert into ${spec.table} (${list}) select ${list} from src
      on conflict (${key}) do update set ${set} returning 1),
    del as (delete from ${spec.table} where ${key} not in (select ${key} from src) returning 1)
    select (select count(*) from up)::int as upserted, (select count(*) from del)::int as deleted`
}

// CSV로 기획 표를 덮어쓴다 — 표 전부를 한 트랜잭션(batch)으로, 중간에 실패하면 아무 표도 안 바뀐다. 표별 {upserted, deleted}.
export async function seed(db: Pick<Db, 'batch'>, dataDir = DATA_DIR): Promise<Record<string, { upserted: number; deleted: number }>> {
  const tables = await readTables(dataDir)
  const stmts = TABLES.map((spec) => {
    const rows = tables[spec.name].map((r, i) => {
      const o: Record<string, unknown> = {}
      for (const c of Object.keys(spec.sql)) o[c] = r[c]
      if (spec.ordered) o.ord = i
      return o
    })
    return { text: seedSql(spec), params: [JSON.stringify(rows)] }
  })
  const out = await db.batch(stmts)
  const result: Record<string, { upserted: number; deleted: number }> = {}
  TABLES.forEach((spec, i) => {
    const [r] = out[i]
    result[spec.name] = { upserted: Number(r.upserted), deleted: Number(r.deleted) }
  })
  return result
}

// 기획 표 중 하나라도 비었으면 true(개발 서버 첫 시작 때 시드).
export async function planningEmpty(query: Query): Promise<boolean> {
  const sel = TABLES.map((t) => `(select count(*) from ${t.table})::int as ${t.name}`).join(', ')
  const [r] = await query(`select ${sel}`)
  return TABLES.some((t) => Number(r[t.name]) === 0)
}

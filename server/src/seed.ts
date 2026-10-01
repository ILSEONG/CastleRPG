// data/*.csv → 기획 표. CSV 규칙은 앱 GameData와 같다: 헤더 이름으로 열 찾기, BOM·빈 줄·쉼표만 있는 줄 무시,
// 숫자 검증, 오류는 파일·줄·열. 오류가 하나라도 있으면 아무것도 쓰지 않는다.
import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import type { Db, Query } from './db.ts'
import { BUILD_RES, GATE, KEEP, parseTiers } from './rules.ts'

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
    // 개정 12: 건물 표(스펙 §2.2). req1·req2는 비면 null(선행 없음)
    name: 'buildings', table: 'building_defs', file: 'buildings.csv', ordered: true,
    cols: { id: 'key', name: 'text', max_level: 'int', wood: 'int', stone: 'int', food: 'int', base_sec: 'num', req1: 'opt', req2: 'opt' },
    sql: { id: 'text', name: 'text', max_level: 'integer', wood: 'integer', stone: 'integer', food: 'integer', base_sec: 'real', req1: 'text', req2: 'text' },
  },
  {
    // 개정 13: 병종 표(1티어 기준). building = 그 병종을 만드는 건물
    name: 'soldiers', table: 'soldier_defs', file: 'soldiers.csv', ordered: true,
    cols: { id: 'key', name: 'text', building: 'text', hp: 'num', atk: 'num', range: 'num', atk_interval: 'num', speed: 'num', aggro: 'num', model: 'text' },
    sql: { id: 'text', name: 'text', building: 'text', ...real(['hp', 'atk', 'range', 'atk_interval', 'speed', 'aggro']), model: 'text' },
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
  'gacha_cost_1', 'gacha_cost_10', 'gacha_rate_ssr', 'gacha_rate_sr', 'gacha_10_min_sr',
  'hero_max_level_base', 'hero_max_level_per_star', 'hero_level_stat', 'levelup_gold_R', 'levelup_gold_SR', 'levelup_gold_SSR',
  'fever_kills', 'fever_sec', 'fever_spawn_mult']
export const CONFIG_LIST = ['starter_heroes']
// 개정 12 건물 효과 숫자 설정(스펙 §2.3, checkBuildings가 범위를 본다)과 성채 단계 표 "레벨:값|…"(rules.parseTiers, 값은 1 이상 정수 —
// 기존 hero_slots 목록과 앱 Balance.INTERIOR_TILES를 대신한다)
export const CONFIG_BUILDING_NUM = ['castle_hp_per_level', 'pop_base', 'pop_per_house', 'lab_atk_per_level',
  'tavern_ssr_per_level', 'tavern_sr_per_level']
const POP_KEYS = ['pop_base', 'pop_per_house'] // 인구는 정수
// 개정 13 병사 설정(checkSoldiers가 범위를 본다): 최대 티어·합성 수는 1 이상 정수, 나머지는 0보다 크다
export const CONFIG_SOLDIER_NUM = ['soldier_max_tier', 'soldier_tier_mult', 'soldier_prod_sec', 'soldier_prod_level_factor', 'soldier_merge_count']
const SOLDIER_INT_KEYS = ['soldier_max_tier', 'soldier_merge_count']
export const CONFIG_TIERS = ['keep_slot_tiers', 'keep_interior_tiers']
export const SLOT_STEP = 4 // 성이 넓어질 때마다 영웅 슬롯 +4(사용자 규칙). 앱 GameData.KEEP_SLOT_STEP
export const MAX_HERO_SLOTS = 12 // 앱 GameData.MAX_HERO_SLOTS
// 시작 영웅 스펙 기본값(§3.1). 마이그레이션 005와 로그인이 설정 행이 없을 때(시드 전 DB) 쓴다.
export const DEFAULT_STARTERS = 'hans|ella|dorik|nina'
export const GRADES = ['R', 'SR', 'SSR']

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
    for (const k of [...CONFIG_NUM, ...CONFIG_LIST, ...CONFIG_BUILDING_NUM, ...CONFIG_SOLDIER_NUM, ...CONFIG_TIERS]) {
      const r = byKey.get(k)
      if (!r) err(0, 'key', `missing key '${k}'`)
      else if ((CONFIG_NUM.includes(k) || CONFIG_BUILDING_NUM.includes(k) || CONFIG_SOLDIER_NUM.includes(k)) && !isNum(String(r.value))) err(Number(r._line), 'value', `not a number: '${r.value}'`)
      else if (CONFIG_LIST.includes(k) && String(r.value).split('|').some((p) => p.trim() === '')) err(Number(r._line), 'value', `empty list item: '${r.value}'`)
      else if (CONFIG_TIERS.includes(k) && !parseTiers(String(r.value))?.every(([, v]) => Number.isInteger(v) && v >= 1)) {
        err(Number(r._line), 'value', `not a tier table 'level:value|…' (levels from 1 ascending, values integers >= 1): '${r.value}'`)
      }
    }
  }
  if (rows.length === 0 && !errors.some((e) => e.startsWith(`${spec.file} `))) err(0, Object.keys(spec.cols)[0], 'no rows')
  return rows
}

// 모집 설정(스펙 §3.6): 비용·10연차 보장 수는 0 이상 정수(소수 비용이면 BigInt(-cost × 10)가 throw → 500), 확률은 0..1이고
// SSR + SR ≤ 1. 레벨업 설정(개정 11 §2.1): 비용·별당 최대 레벨은 0 이상 정수, 최대 레벨 기본은 1 이상 정수, 레벨 배율은 0 이상.
// 숫자가 아닌 값은 checkTable이 이미 알렸으므로 건너뛴다.
const LEVELUP_INT_KEYS = ['hero_max_level_per_star', ...GRADES.map((g) => `levelup_gold_${g}`)]
function checkGacha(config: CsvRow[], errors: string[]) {
  const byKey = new Map(config.map((r) => [String(r.key), r]))
  const raw = (k: string) => String(byKey.get(k)?.value ?? '')
  const num = (k: string) => (isNum(raw(k)) ? Number(raw(k)) : null)
  const err = (k: string, why: string) => errors.push(`config.csv line ${byKey.get(k)?._line} column 'value': ${k} ${why}`)
  for (const k of ['gacha_cost_1', 'gacha_cost_10', 'gacha_10_min_sr', ...LEVELUP_INT_KEYS]) {
    const v = num(k)
    if (v !== null && !(Number.isInteger(v) && v >= 0)) err(k, `must be a non-negative integer: '${raw(k)}'`)
  }
  const base = num('hero_max_level_base')
  if (base !== null && !(Number.isInteger(base) && base >= 1)) err('hero_max_level_base', `must be an integer of at least 1: '${raw('hero_max_level_base')}'`)
  const stat = num('hero_level_stat')
  if (stat !== null && !(stat >= 0)) err('hero_level_stat', `must be 0 or more: '${raw('hero_level_stat')}'`)
  const inUnit = (v: number | null) => v !== null && v >= 0 && v <= 1
  for (const k of ['gacha_rate_ssr', 'gacha_rate_sr']) {
    if (num(k) !== null && !inUnit(num(k))) err(k, `must be in 0..1: '${raw(k)}'`)
  }
  const ssr = num('gacha_rate_ssr')
  const sr = num('gacha_rate_sr')
  if (ssr !== null && sr !== null && inUnit(ssr) && inUnit(sr) && ssr + sr > 1 + 1e-9) {
    err('gacha_rate_sr', `plus gacha_rate_ssr must be at most 1: ${raw('gacha_rate_ssr')} + ${raw('gacha_rate_sr')}`)
  }
}

// 건물 표(개정 12 §2.2, 앱 GameData와 같은 규칙): 최대 레벨 1 이상, 비용 0 이상(정수는 열 형이 본다), base_sec > 0,
// 선행(req1·req2)은 표에 있는 건물, 성채·성문 행 필수(상한·성 HP), 자원 건물은 모두 건물 표에, 비용 열(wood·stone·food)은 자원 id.
// 건물 효과 설정은 0 이상, 주점 확률 증가분은 1 이하, 인구(pop_base·pop_per_house)는 정수.
function checkBuildings(t: Tables, errors: string[]) {
  const rows = t.buildings ?? []
  const ids = new Set(rows.map((b) => String(b.id)))
  const err = (line: unknown, col: string, why: string) => errors.push(`buildings.csv line ${line} column '${col}': ${why}`)
  for (const b of rows) {
    if (!(Number(b.max_level) >= 1)) err(b._line, 'max_level', `must be at least 1: ${b.max_level}`)
    for (const r of BUILD_RES) if (!(Number(b[r]) >= 0)) err(b._line, r, `must be 0 or more: ${b[r]}`)
    if (!(Number(b.base_sec) > 0)) err(b._line, 'base_sec', `must be greater than 0: ${b.base_sec}`)
    for (const c of ['req1', 'req2']) if (b[c] !== null && !ids.has(String(b[c]))) err(b._line, c, `unknown building '${b[c]}'`)
  }
  if (t.buildings) for (const id of [KEEP, GATE]) if (!ids.has(id)) err(0, 'id', `missing required building '${id}'`)
  if (t.buildings && t.resources) {
    const res = new Set(t.resources.map((r) => String(r.id)))
    for (const r of t.resources) if (!ids.has(String(r.building))) errors.push(`resources.csv line ${r._line} column 'building': building '${r.building}' is not in buildings.csv`)
    for (const r of BUILD_RES) if (!res.has(r)) errors.push(`resources.csv line 0 column 'id': building cost resource '${r}' is missing`)
  }
  const byKey = new Map((t.config ?? []).map((r) => [String(r.key), r]))
  for (const k of CONFIG_BUILDING_NUM) {
    const r = byKey.get(k)
    const v = Number(r?.value)
    const tavern = k.startsWith('tavern_')
    const pop = POP_KEYS.includes(k)
    if (r && isNum(String(r.value)) && !(v >= 0 && (!tavern || v <= 1) && (!pop || Number.isInteger(v)))) {
      errors.push(`config.csv line ${r._line} column 'value': ${k} must be ${tavern ? 'in 0..1' : pop ? 'a non-negative integer' : '0 or more'}: '${r.value}'`)
    }
  }
  checkKeepTiers(byKey, errors)
}

// 성채 단계 표 둘은 함께 움직인다(사용자 규칙: 성이 넓어질 때마다 영웅 슬롯 +4, 최대 12). 앱 GameData._check_keep_tiers와 같은 규칙:
// 슬롯 표의 레벨 = 내부 표의 레벨, 슬롯 값 = SLOT_STEP × 단계 번호(4, 8, 12 — MAX_HERO_SLOTS 이하), 내부 값은 단계마다 커진다.
// 형식이 틀린 표는 checkTable이 이미 알렸으므로 둘 다 읽힐 때만 본다.
function checkKeepTiers(byKey: Map<string, CsvRow>, errors: string[]) {
  const read = (k: string) => {
    const t = parseTiers(String(byKey.get(k)?.value ?? ''))
    return t?.every(([, v]) => Number.isInteger(v) && v >= 1) ? t : null
  }
  const slots = read('keep_slot_tiers')
  const interior = read('keep_interior_tiers')
  if (!slots || !interior) return
  const err = (k: string, why: string) => errors.push(`config.csv line ${byKey.get(k)?._line} column 'value': ${k} ${why}`)
  const levels = (t: [number, number][]) => t.map(([l]) => l).join(',')
  if (levels(slots) !== levels(interior)) err('keep_slot_tiers', `levels must match keep_interior_tiers: ${levels(slots)} vs ${levels(interior)}`)
  if (slots.some(([, v], i) => v !== SLOT_STEP * (i + 1) || v > MAX_HERO_SLOTS)) {
    err('keep_slot_tiers', `values must be ${SLOT_STEP} x tier (${SLOT_STEP}, ${SLOT_STEP * 2}, ${SLOT_STEP * 3} — at most ${MAX_HERO_SLOTS}): ${slots.map(([, v]) => v).join(',')}`)
  }
  if (interior.some(([, v], i) => i > 0 && v <= interior[i - 1][1])) err('keep_interior_tiers', `values must grow every tier: ${interior.map(([, v]) => v).join(',')}`)
}

// 병종 표(개정 13, 앱 GameData와 같은 규칙): 건물은 건물 표에 있고 병종마다 다르다(건물 하나 = 병종 하나), hp·range·atk_interval·speed > 0,
// atk·aggro ≥ 0. 병사 설정: 최대 티어·합성 수는 1 이상 정수, 티어 배율·한 마리 시간·레벨 계수는 0보다 크다.
function checkSoldiers(t: Tables, errors: string[]) {
  const rows = t.soldiers ?? []
  const err = (line: unknown, col: string, why: string) => errors.push(`soldiers.csv line ${line} column '${col}': ${why}`)
  const buildings = new Set((t.buildings ?? []).map((b) => String(b.id)))
  const seen = new Set<string>()
  for (const s of rows) {
    if (t.buildings && !buildings.has(String(s.building))) err(s._line, 'building', `building '${s.building}' is not in buildings.csv`)
    else if (seen.has(String(s.building))) err(s._line, 'building', `building '${s.building}' already makes another soldier`)
    seen.add(String(s.building))
    for (const c of ['hp', 'range', 'atk_interval', 'speed']) if (!(Number(s[c]) > 0)) err(s._line, c, `must be greater than 0: ${s[c]}`)
    for (const c of ['atk', 'aggro']) if (!(Number(s[c]) >= 0)) err(s._line, c, `must be 0 or more: ${s[c]}`)
  }
  const byKey = new Map((t.config ?? []).map((r) => [String(r.key), r]))
  for (const k of CONFIG_SOLDIER_NUM) {
    const r = byKey.get(k)
    const v = Number(r?.value)
    const int = SOLDIER_INT_KEYS.includes(k)
    if (r && isNum(String(r.value)) && !(int ? Number.isInteger(v) && v >= 1 : v > 0)) {
      errors.push(`config.csv line ${r._line} column 'value': ${k} must be ${int ? 'an integer of at least 1' : 'greater than 0'}: '${r.value}'`)
    }
  }
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
  if (out.config) checkGacha(out.config, errors)
  checkBuildings(out, errors)
  checkSoldiers(out, errors)
  // 등급마다 영웅이 하나 이상 있어야 모집이 그 등급을 뽑을 수 있다(없으면 /v1/gacha가 500)
  if (out.heroes) {
    for (const g of GRADES) {
      if (!out.heroes.some((h) => h.grade === g)) errors.push(`heroes.csv line 0 column 'grade': no ${g} heroes to recruit`)
    }
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

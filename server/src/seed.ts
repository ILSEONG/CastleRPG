// data/*.csv → 기획 표. CSV 규칙은 앱 GameData와 같다: 헤더 이름으로 열 찾기, BOM·빈 줄·쉼표만 있는 줄 무시,
// 숫자 검증, 오류는 파일·줄·열. 오류가 하나라도 있으면 아무것도 쓰지 않는다.
import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import type { Db, Query } from './db.ts'
import { BUILD_RES, DUNGEON_TYPES, EQUIP_GRADES, GATE, KEEP, MAX_PROMOTION, parseTiers, parseTrainCost, RESEARCH_BRANCHES, RESEARCH_EFFECTS, UPGRADE_UNITS,
  WEAPON_OF } from './rules.ts'

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

// 개정 18 던전 표(스펙 §7): 적 행 = 던전 종류(type)별 기본 능력치(단계 성장은 config), 장비 등급 가중치 = 단계 구간(min_level)별 행.
// equip_drop 가중치 열 이름 = 등급(N…LR, 대문자 — ident가 따옴표로 감싼다)
const DUNGEON_NUM = ['delay', 'hp', 'atk', 'speed', 'range', 'atk_interval', 'aggro', 'scale']
const DUNGEON_TABLES: TableSpec[] = [
  {
    name: 'dungeons', table: 'dungeon_defs', file: 'dungeons.csv', ordered: true,
    cols: { id: 'key', type: 'text', kind: 'text', count: 'int', ...Object.fromEntries(DUNGEON_NUM.map((n) => [n, 'num' as ColType])) },
    sql: { id: 'text', type: 'text', kind: 'text', count: 'integer', ...real(DUNGEON_NUM) },
  },
  {
    name: 'equip_drop', table: 'equip_drop', file: 'equip_drop.csv', ordered: false,
    cols: { min_level: 'key', ...Object.fromEntries(EQUIP_GRADES.map((g) => [g, 'num' as ColType])) },
    sql: { min_level: 'integer', ...real(EQUIP_GRADES) },
  },
]

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
      skill1: 'opt', s1a: 'optnum', s1b: 'optnum', s1c: 'optnum', skill2: 'opt', s2a: 'optnum', s2b: 'optnum', s2c: 'optnum',
      skill3: 'opt', s3a: 'optnum', s3b: 'optnum', s3c: 'optnum', desc: 'text', // 개정 17: 스킬 3(★5)
    },
    sql: {
      ...Object.fromEntries(['id', 'name', 'title', 'grade', 'role', 'archetype', 'model', 'gear', 'color'].map((n) => [n, 'text'])),
      ...real(['hp', 'atk', 'range', 'atk_interval', 'speed', 'aggro']),
      skill1: 'text', ...real(['s1a', 's1b', 's1c']), skill2: 'text', ...real(['s2a', 's2b', 's2c']),
      skill3: 'text', ...real(['s3a', 's3b', 's3c']), desc: 'text',
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
  ...DUNGEON_TABLES,
  {
    // 개정 20: 공용 업그레이드 표(스펙 §2). unit = pct(%) | pp(%p)
    name: 'upgrades', table: 'upgrade_defs', file: 'upgrades.csv', ordered: true,
    cols: { id: 'key', name: 'text', per_level: 'num', unit: 'text', max_level: 'int', cost_base: 'num', cost_growth: 'num' },
    sql: { id: 'text', name: 'text', per_level: 'real', unit: 'text', max_level: 'integer', cost_base: 'real', cost_growth: 'real' },
  },
  {
    // 개정 24: 연구 테크트리(스펙 §2). req1·req2(선행 노드)와 그 레벨은 비면 null(선행 없음)
    name: 'research', table: 'research_defs', file: 'research.csv', ordered: true,
    cols: {
      id: 'key', branch: 'text', tier: 'int', name: 'text', effect: 'text', per_level: 'num', max_level: 'int', lab_req: 'int',
      req1: 'opt', req1_lv: 'optnum', req2: 'opt', req2_lv: 'optnum', wood: 'int', stone: 'int', food: 'int', gold: 'int', base_sec: 'num',
    },
    sql: {
      id: 'text', branch: 'text', tier: 'integer', name: 'text', effect: 'text', per_level: 'real', max_level: 'integer', lab_req: 'integer',
      req1: 'text', req1_lv: 'integer', req2: 'text', req2_lv: 'integer', wood: 'integer', stone: 'integer', food: 'integer', gold: 'integer', base_sec: 'real',
    },
  },
  {
    name: 'config', table: 'game_config', file: 'config.csv', ordered: false,
    cols: { key: 'key', value: 'text' },
    sql: { key: 'text', value: 'text' },
  },
]

// 개정 23 모집 설정(checkGacha가 범위를 본다): 골드 레벨 비용·확률, 다이아 비용·확률·천장
export const GACHA_KEYS = ['gacha_gold_cost_base', 'gacha_gold_cost_growth', 'gacha_gold_level_max', 'gacha_gold_level_pulls',
  'gacha_gold_ssr_base', 'gacha_gold_ssr_step', 'gacha_gold_sr_base', 'gacha_gold_sr_step',
  'gacha_dia_cost_1', 'gacha_dia_cost_10', 'gacha_dia_ssr', 'gacha_dia_sr', 'gacha_dia_pity']
// 서버·앱이 쓰는 설정 키(스펙 §2). 숫자 키는 숫자여야 하고, 목록 키는 `|` 구분 항목이 비지 않아야 한다.
export const CONFIG_NUM = ['castle_hp', 'gate_hp_per_level', 'max_live_monsters', 'countdown_sec', 'result_sec', 'wave_gap_sec',
  'spawn_spacing_sec', 'accum_cap_min', 'badge_min', 'merchant_jackpot_p', 'merchant_jackpot_rate', 'merchant_rate_min',
  'merchant_rate_max', 'merchant_rate_step', 'merchant_low_high_ratio', 'kill_rate_cap', 'kill_burst_sec', 'promote_mult',
  'gacha_10_min_sr', ...GACHA_KEYS,
  'hero_max_level_base', 'hero_max_level_per_promotion', 'hero_level_stat', 'levelup_gold_R', 'levelup_gold_SR', 'levelup_gold_SSR',
  'fever_kills', 'fever_sec', 'fever_spawn_mult', 'skill2_unlock_star', 'skill3_unlock_star', 'spawn_group',
  'rounds_per_stage', 'stage_speed_step', 'stage_speed_cap', 'boss_round_mult'] // 개정 22 라운드(앱 표시·스폰만 — 서버 stage는 전체 라운드 g 그대로)
export const CONFIG_LIST = ['starter_heroes', 'promote_shards']
// 개정 12 건물 효과 숫자 설정(스펙 §2.3, checkBuildings가 범위를 본다)과 성채 단계 표 "레벨:값|…"(rules.parseTiers, 값은 1 이상 정수 —
// 기존 hero_slots 목록과 앱 Balance.INTERIOR_TILES를 대신한다)
export const CONFIG_BUILDING_NUM = ['castle_hp_per_level', 'pop_base', 'pop_per_house', 'tavern_ssr_per_level', 'tavern_sr_per_level']
// 개정 24 연구 설정(checkResearch가 범위를 본다): 비용·시간 성장 ≥ 1, 연구소 속도 ≥ 0, 취소 환불 0..1, 다이아/분 0 이상 정수
export const CONFIG_RESEARCH_NUM = ['research_cost_growth', 'research_time_growth', 'lab_research_speed_per_level', 'research_cancel_refund', 'research_dia_per_min']
const POP_KEYS = ['pop_base', 'pop_per_house'] // 인구는 정수
// 개정 13 병사 설정(checkSoldiers가 범위를 본다): 최대 티어·합성 수·묶음 기본은 1 이상 정수, 묶음 레벨 증가분은 0 이상 정수, 나머지는 0보다 크다.
// 개정 16 훈련: 병종마다 1마리 비용 train_cost_<병종>("자원:수|…", rules.parseTrainCost)도 필수다
export const CONFIG_SOLDIER_NUM = ['soldier_max_tier', 'soldier_tier_mult', 'train_base_min', 'train_step_min', 'train_cost_tier_mult', 'soldier_merge_count',
  'train_batch_base', 'train_batch_per_level']
const SOLDIER_INT_KEYS = ['soldier_max_tier', 'soldier_merge_count', 'train_batch_base', 'train_base_min', 'train_step_min', 'train_cost_tier_mult']
const SOLDIER_INT0_KEYS = ['train_batch_per_level']
export const CONFIG_TIERS = ['keep_slot_tiers', 'keep_interior_tiers']
// 개정 18 던전·장비 설정(checkDungeons가 범위를 본다). 정수 키는 0 이상 정수(INT1은 1 이상), 확률은 0..1, 성장·배율·제한 시간은 0보다 크다
export const CONFIG_DUNGEON_NUM = ['daily_reset_utc_hour', 'gold_key_daily', 'gold_key_cap', 'equip_key_daily', 'equip_key_cap', 'equip_extra_gold_base',
  'gold_dg_base', 'gold_dg_mult', 'gold_dg_growth', 'equip_dg_hp_growth', 'equip_dg_atk_growth', 'gold_dg_party', 'equip_dg_party',
  'gold_dg_min_sec', 'equip_dg_min_sec', 'dungeon_time_limit', 'equip_drop_count', 'equip_weapon_p', 'equip_bag_cap', 'equip_sell_base']
const DUNGEON_INT_KEYS = ['gold_key_daily', 'gold_key_cap', 'equip_key_daily', 'equip_key_cap', 'equip_extra_gold_base', 'gold_dg_base', 'equip_sell_base',
  'gold_dg_min_sec', 'equip_dg_min_sec']
const DUNGEON_INT1_KEYS = ['gold_dg_party', 'equip_dg_party', 'equip_drop_count', 'equip_bag_cap']
export const SLOT_STEP = 4 // 성이 넓어질 때마다 영웅 슬롯 +4(사용자 규칙). 앱 GameData.KEEP_SLOT_STEP
export const MAX_HERO_SLOTS = 12 // 앱 GameData.MAX_HERO_SLOTS
// 시작 영웅 스펙 기본값(§3.1). 마이그레이션 005와 로그인이 설정 행이 없을 때(시드 전 DB) 쓴다.
export const DEFAULT_STARTERS = 'hans|ella|dorik|nina'
export const GRADES = ['R', 'SR', 'SSR']
// 개정 17: 등급별 스킬 수(skill1부터 빈틈없이)와 스킬 종류 — 앱 GameData.GRADE_SKILLS·Skills.KINDS와 같다
export const GRADE_SKILLS: Record<string, number> = { R: 2, SR: 3, SSR: 3 }
export const SKILL_KINDS = ['heal_aura', 'atk_aura', 'dmg_reduce', 'dodge', 'thorns', 'lifesteal', 'haste', 'rage', 'crit', 'execute',
  'boss_slayer', 'cleave', 'multishot', 'chain', 'aoe_blast', 'slow', 'stun', 'poison', 'gate_repair']
const SKILL_COLS = ['skill1', 'skill2', 'skill3']

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
  if (spec.name === 'equip_drop') rows = checkDropRows(rows, err) // 개정 18
  if (spec.name === 'config') {
    const byKey = new Map(rows.map((r) => [String(r.key), r]))
    const nums = [...CONFIG_NUM, ...CONFIG_BUILDING_NUM, ...CONFIG_SOLDIER_NUM, ...CONFIG_DUNGEON_NUM, ...CONFIG_RESEARCH_NUM]
    for (const k of [...CONFIG_NUM, ...CONFIG_LIST, ...CONFIG_BUILDING_NUM, ...CONFIG_SOLDIER_NUM, ...CONFIG_TIERS, ...CONFIG_DUNGEON_NUM, ...CONFIG_RESEARCH_NUM]) {
      const r = byKey.get(k)
      if (!r) err(0, 'key', `missing key '${k}'`)
      else if (nums.includes(k) && !isNum(String(r.value))) err(Number(r._line), 'value', `not a number: '${r.value}'`)
      else if (CONFIG_LIST.includes(k) && String(r.value).split('|').some((p) => p.trim() === '')) err(Number(r._line), 'value', `empty list item: '${r.value}'`)
      else if (CONFIG_TIERS.includes(k) && !parseTiers(String(r.value))?.every(([, v]) => Number.isInteger(v) && v >= 1)) {
        err(Number(r._line), 'value', `not a tier table 'level:value|…' (levels from 1 ascending, values integers >= 1): '${r.value}'`)
      }
    }
  }
  if (rows.length === 0 && !errors.some((e) => e.startsWith(`${spec.file} `))) err(0, Object.keys(spec.cols)[0], 'no rows')
  return rows
}

// 모집 설정(스펙 §3.6·개정 23): 다이아 비용·10연차 보장 수는 0 이상 정수(소수 비용이면 BigInt가 throw → 500), 골드 레벨 최대·레벨당 횟수·천장은
// 1 이상 정수, 골드 기본 비용·확률 base·step은 0 이상, 비용 성장은 1 이상. 확률은 0..1이고 SSR + SR ≤ 1(골드는 최대 레벨 값으로),
// 다이아는 골드 최대 레벨보다 SSR·SR 모두 높다. 레벨업 설정(개정 11 §2.1): 비용·승급당 최대 레벨은 0 이상 정수, 최대 레벨 기본은 1 이상 정수, 레벨 배율은 0 이상.
// 승급(개정 15): promote_shards는 MAX_PROMOTION개의 1 이상 정수, promote_mult는 1 이상.
// 숫자가 아닌 값은 checkTable이 이미 알렸으므로 건너뛴다.
const LEVELUP_INT_KEYS = ['hero_max_level_per_promotion', ...GRADES.map((g) => `levelup_gold_${g}`)]
function checkGacha(config: CsvRow[], errors: string[]) {
  const byKey = new Map(config.map((r) => [String(r.key), r]))
  const raw = (k: string) => String(byKey.get(k)?.value ?? '')
  const num = (k: string) => (isNum(raw(k)) ? Number(raw(k)) : null)
  const err = (k: string, why: string) => errors.push(`config.csv line ${byKey.get(k)?._line} column 'value': ${k} ${why}`)
  for (const k of ['gacha_dia_cost_1', 'gacha_dia_cost_10', 'gacha_10_min_sr', ...LEVELUP_INT_KEYS]) {
    const v = num(k)
    if (v !== null && !(Number.isInteger(v) && v >= 0)) err(k, `must be a non-negative integer: '${raw(k)}'`)
  }
  checkGachaRates(num, raw, err)
  const base = num('hero_max_level_base')
  if (base !== null && !(Number.isInteger(base) && base >= 1)) err('hero_max_level_base', `must be an integer of at least 1: '${raw('hero_max_level_base')}'`)
  const stat = num('hero_level_stat')
  if (stat !== null && !(stat >= 0)) err('hero_level_stat', `must be 0 or more: '${raw('hero_level_stat')}'`)
  const mult = num('promote_mult')
  if (mult !== null && !(mult >= 1)) err('promote_mult', `must be 1 or more: '${raw('promote_mult')}'`)
  // 개정 22 라운드(앱 GameData._check_rounds와 같은 규칙): 스테이지당 라운드는 1 이상 정수, 속도 증가분 0 이상, 상한 1 이상, 보스 배율 0보다 크다
  const rounds: [string, (v: number) => boolean, string][] = [
    ['rounds_per_stage', (v) => Number.isInteger(v) && v >= 1, 'an integer of at least 1'],
    ['stage_speed_step', (v) => v >= 0, '0 or more'],
    ['stage_speed_cap', (v) => v >= 1, '1 or more'],
    ['boss_round_mult', (v) => v > 0, 'greater than 0'],
  ]
  for (const [k, ok, why] of rounds) {
    const v = num(k)
    if (v !== null && !ok(v)) err(k, `must be ${why}: '${raw(k)}'`)
  }
  // 개정 17 스킬 해금 승급: 0..MAX_PROMOTION 정수, skill2 ≤ skill3
  const stars: number[] = []
  for (const k of ['skill2_unlock_star', 'skill3_unlock_star']) {
    if (/^\d+$/.test(raw(k)) && Number(raw(k)) <= MAX_PROMOTION) stars.push(Number(raw(k)))
    else if (num(k) !== null) err(k, `must be an integer in 0..${MAX_PROMOTION}: '${raw(k)}'`)
  }
  if (stars.length === 2 && stars[0] > stars[1]) err('skill3_unlock_star', `must be at least skill2_unlock_star: ${stars[1]} < ${stars[0]}`)
  const shards = raw('promote_shards').split('|').map((x) => x.trim())
  if (byKey.has('promote_shards') && !(shards.length === MAX_PROMOTION && shards.every((x) => /^\d+$/.test(x) && Number(x) >= 1))) {
    err('promote_shards', `must be ${MAX_PROMOTION} integers of at least 1 separated by '|': '${raw('promote_shards')}'`)
  }
}

// 개정 23 모집 확률·레벨(앱 GameData._check_gacha_rates와 같은 규칙). 숫자가 아닌 값은 checkTable이 이미 알렸다.
function checkGachaRates(num: (k: string) => number | null, raw: (k: string) => string, err: (k: string, why: string) => void) {
  const ok = (k: string, test: (v: number) => boolean, why: string) => {
    const v = num(k)
    if (v === null) return null
    if (test(v)) return v
    err(k, `must be ${why}: '${raw(k)}'`)
    return null
  }
  const int1 = (v: number) => Number.isInteger(v) && v >= 1
  const max = ok('gacha_gold_level_max', int1, 'an integer of at least 1')
  ok('gacha_gold_level_pulls', int1, 'an integer of at least 1')
  ok('gacha_dia_pity', int1, 'an integer of at least 1')
  ok('gacha_gold_cost_base', (v) => v >= 0, '0 or more')
  ok('gacha_gold_cost_growth', (v) => v >= 1, '1 or more')
  const [ssrBase, ssrStep, srBase, srStep] = ['gacha_gold_ssr_base', 'gacha_gold_ssr_step', 'gacha_gold_sr_base', 'gacha_gold_sr_step'].map((k) => ok(k, (v) => v >= 0, '0 or more'))
  const unit = (v: number) => v >= 0 && v <= 1
  const dSsr = ok('gacha_dia_ssr', unit, 'in 0..1')
  const dSr = ok('gacha_dia_sr', unit, 'in 0..1')
  if (dSsr !== null && dSr !== null && dSsr + dSr > 1 + 1e-9) err('gacha_dia_sr', `plus gacha_dia_ssr must be at most 1: ${raw('gacha_dia_ssr')} + ${raw('gacha_dia_sr')}`)
  if (max === null || ssrBase === null || ssrStep === null || srBase === null || srStep === null) return
  const r6 = (v: number) => Math.round(v * 1e6) / 1e6
  const ssrMax = ssrBase + ssrStep * (max - 1)
  const srMax = srBase + srStep * (max - 1)
  if (ssrMax + srMax > 1 + 1e-9) return err('gacha_gold_sr_step', `makes the max-level gold rates above 1: SSR ${r6(ssrMax)} + SR ${r6(srMax)}`)
  if (dSsr !== null && !(dSsr > ssrMax + 1e-9)) err('gacha_dia_ssr', `must be above the max-level gold SSR rate ${r6(ssrMax)}: '${raw('gacha_dia_ssr')}'`)
  if (dSr !== null && !(dSr > srMax + 1e-9)) err('gacha_dia_sr', `must be above the max-level gold SR rate ${r6(srMax)}: '${raw('gacha_dia_sr')}'`)
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
// atk·aggro ≥ 0. 병사 설정: 최대 티어·합성 수·묶음 기본은 1 이상 정수, 묶음 레벨 증가분은 0 이상 정수, 티어 배율·한 마리 시간·레벨 계수는
// 0보다 크다. 훈련 비용(개정 16): 병종마다 train_cost_<병종>이 "자원:수|…"(자원 = wood·stone·food, 수 0 이상 정수) 또는 "0".
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
  for (const s of t.config ? rows : []) {
    const k = `train_cost_${s.id}`
    const r = byKey.get(k)
    if (!r) errors.push(`config.csv line 0 column 'key': missing key '${k}'`)
    else if (!parseTrainCost(String(r.value))) errors.push(`config.csv line ${r._line} column 'value': ${k} must be 'res:amount|…' (res wood/stone/food, amount a non-negative integer) or 0: '${r.value}'`)
  }
  for (const k of CONFIG_SOLDIER_NUM) {
    const r = byKey.get(k)
    const v = Number(r?.value)
    const int = SOLDIER_INT_KEYS.includes(k)
    const int0 = SOLDIER_INT0_KEYS.includes(k)
    if (r && isNum(String(r.value)) && !(int ? Number.isInteger(v) && v >= 1 : int0 ? Number.isInteger(v) && v >= 0 : v > 0)) {
      errors.push(`config.csv line ${r._line} column 'value': ${k} must be ${int ? 'an integer of at least 1' : int0 ? 'a non-negative integer' : 'greater than 0'}: '${r.value}'`)
    }
  }
}

// 영웅 스킬(개정 17, 앱 GameData와 같은 규칙): 등급별 개수(SSR·SR 3, R 2)를 skill1부터 빈틈없이, 알려진 종류만, 한 영웅에 같은 종류 둘 없음.
// 숫자 범위는 앱이 본다(Skills.RULES). 모르는 등급은 DB 제약이 막는다.
function checkHeroSkills(rows: CsvRow[], errors: string[]) {
  for (const h of rows) {
    const err = (col: string, why: string) => errors.push(`heroes.csv line ${h._line} column '${col}': ${why}`)
    const want = GRADE_SKILLS[String(h.grade)] ?? 3
    const gap = SKILL_COLS.findIndex((c, i) => (h[c] === null) !== (i >= want))
    if (gap >= 0) err(SKILL_COLS[gap], `${h.grade} heroes have exactly ${want} skills (skill1..skill${want})`)
    const seen = new Set<string>()
    for (const c of SKILL_COLS) {
      const k = h[c]
      if (k === null) continue
      if (!SKILL_KINDS.includes(String(k)) || seen.has(String(k))) err(c, `unknown or repeated skill '${k}'`)
      seen.add(String(k))
    }
  }
}

// 업그레이드 표(개정 20, 앱 GameData와 같은 규칙): per_level·cost_base > 0, cost_growth ≥ 1, max_level ≥ 1, unit은 pct·pp만.
function checkUpgrades(t: Tables, errors: string[]) {
  const err = (line: unknown, col: string, why: string) => errors.push(`upgrades.csv line ${line} column '${col}': ${why}`)
  for (const u of t.upgrades ?? []) {
    for (const c of ['per_level', 'cost_base']) if (!(Number(u[c]) > 0)) err(u._line, c, `must be greater than 0: ${u[c]}`)
    if (!(Number(u.cost_growth) >= 1)) err(u._line, 'cost_growth', `must be 1 or more: ${u.cost_growth}`)
    if (!(Number(u.max_level) >= 1)) err(u._line, 'max_level', `must be at least 1: ${u.max_level}`)
    if (!UPGRADE_UNITS.includes(String(u.unit))) err(u._line, 'unit', `must be one of ${UPGRADE_UNITS.join('/')}: '${u.unit}'`)
  }
}

// --- 개정 18 던전·장비 (앱 GameData._check_dungeons와 같은 규칙) ---

// equip_drop.csv: min_level은 1부터 오름차순 정수(행 = 그 단계부터의 구간), 가중치는 0 이상, 행 합 > 0. min_level을 숫자로 바꾼다.
function checkDropRows(rows: CsvRow[], err: (line: number, col: string, why: string) => void): CsvRow[] {
  const out: CsvRow[] = []
  for (const r of rows) {
    const lv = Number(r.min_level)
    const prev = out.length ? Number(out[out.length - 1].min_level) : 0
    if (!/^\d+$/.test(String(r.min_level)) || (out.length === 0 ? lv !== 1 : lv <= prev)) {
      err(Number(r._line), 'min_level', 'min_level must start at 1 and go up')
      break
    }
    if (EQUIP_GRADES.some((g) => !(Number(r[g]) >= 0))) err(Number(r._line), EQUIP_GRADES.find((g) => !(Number(r[g]) >= 0)) ?? '', 'weights must be 0 or more')
    else if (!(EQUIP_GRADES.reduce((s, g) => s + Number(r[g]), 0) > 0)) err(Number(r._line), 'N', 'weights must not all be 0')
    out.push({ ...r, min_level: lv })
  }
  return out
}

// 적 표(dungeons.csv): type은 gold·equip, 종류마다 행 하나 이상, count 1 이상, delay ≥ 0, hp·speed·range·atk_interval·scale > 0, atk·aggro ≥ 0.
// 설정: 정수 키는 0 이상 정수(파티·드랍 수·보관함은 1 이상), 리셋 시각 0..23, 무기 확률 0..1, 성장·배율·제한 시간 > 0.
// 모든 영웅 모델은 무기 종류가 있어야 한다(rules.WEAPON_OF — 없으면 무기를 못 낀다).
function checkDungeons(t: Tables, errors: string[]) {
  const err = (line: unknown, col: string, why: string) => errors.push(`dungeons.csv line ${line} column '${col}': ${why}`)
  const rows = t.dungeons ?? []
  for (const d of rows) {
    if (!DUNGEON_TYPES.includes(String(d.type))) err(d._line, 'type', `type must be ${DUNGEON_TYPES.join(' or ')}: '${d.type}'`)
    if (!(Number(d.count) >= 1)) err(d._line, 'count', `must be at least 1: ${d.count}`)
    for (const c of ['hp', 'speed', 'range', 'atk_interval', 'scale']) if (!(Number(d[c]) > 0)) err(d._line, c, `must be greater than 0: ${d[c]}`)
    for (const c of ['delay', 'atk', 'aggro']) if (!(Number(d[c]) >= 0)) err(d._line, c, `must be 0 or more: ${d[c]}`)
  }
  if (t.dungeons) for (const type of DUNGEON_TYPES) if (!rows.some((d) => d.type === type)) err(0, 'type', `no enemies for the ${type} dungeon`)
  for (const h of t.heroes ?? []) {
    if (!Object.hasOwn(WEAPON_OF, String(h.model))) errors.push(`heroes.csv line ${h._line} column 'model': model '${h.model}' has no weapon kind`)
  }
  const byKey = new Map((t.config ?? []).map((r) => [String(r.key), r]))
  for (const k of CONFIG_DUNGEON_NUM) {
    const r = byKey.get(k)
    if (!r || !isNum(String(r.value))) continue // 빠짐·숫자 아님은 checkTable이 알렸다
    const v = Number(r.value)
    const why = DUNGEON_INT_KEYS.includes(k) ? (Number.isInteger(v) && v >= 0 ? '' : 'a non-negative integer')
      : DUNGEON_INT1_KEYS.includes(k) ? (Number.isInteger(v) && v >= 1 ? '' : 'an integer of at least 1')
        : k === 'daily_reset_utc_hour' ? (Number.isInteger(v) && v >= 0 && v <= 23 ? '' : 'an integer in 0..23')
          : k === 'equip_weapon_p' ? (v >= 0 && v <= 1 ? '' : 'in 0..1')
            : v > 0 ? '' : 'greater than 0'
    if (why) errors.push(`config.csv line ${r._line} column 'value': ${k} must be ${why}: '${r.value}'`)
  }
}

// 연구 표(개정 24, 앱 GameData와 같은 규칙): 알려진 branch·effect만, 숫자 0 이상(tier·max_level ≥ 1, base_sec > 0),
// 선행(req1·req2)은 표 안의 id이고 그 레벨(req_lv)과 함께 있거나 함께 비며, req_lv는 1..그 노드의 max_level 정수.
// 설정: 비용·시간 성장 ≥ 1, 연구소 속도 ≥ 0, 취소 환불 0..1, 다이아/분 0 이상 정수(숫자 아님·빠짐은 checkTable이 알렸다).
function checkResearch(t: Tables, errors: string[]) {
  const rows = t.research ?? []
  const err = (line: unknown, col: string, why: string) => errors.push(`research.csv line ${line} column '${col}': ${why}`)
  const byId = new Map(rows.map((r) => [String(r.id), r]))
  for (const r of rows) {
    if (!RESEARCH_BRANCHES.includes(String(r.branch))) err(r._line, 'branch', `must be one of ${RESEARCH_BRANCHES.join('/')}: '${r.branch}'`)
    if (!RESEARCH_EFFECTS.includes(String(r.effect))) err(r._line, 'effect', `unknown effect '${r.effect}'`)
    for (const c of ['tier', 'max_level']) if (!(Number(r[c]) >= 1)) err(r._line, c, `must be at least 1: ${r[c]}`)
    for (const c of ['per_level', 'lab_req', 'wood', 'stone', 'food', 'gold']) if (!(Number(r[c]) >= 0)) err(r._line, c, `must be 0 or more: ${r[c]}`)
    if (!(Number(r.base_sec) > 0)) err(r._line, 'base_sec', `must be greater than 0: ${r.base_sec}`)
    for (const [c, lc] of [['req1', 'req1_lv'], ['req2', 'req2_lv']]) {
      const req = r[c]
      const lv = Number(r[lc])
      const node = byId.get(String(req))
      if ((req === null) !== (r[lc] === null)) err(r._line, req === null ? c : lc, `${c} and ${lc} must be both set or both empty`)
      else if (req === null) continue
      else if (!node) err(r._line, c, `unknown research '${req}'`)
      else if (!(Number.isInteger(lv) && lv >= 1 && lv <= Number(node.max_level))) err(r._line, lc, `must be an integer in 1..${node.max_level} (max level of '${req}'): ${r[lc]}`)
    }
  }
  const byKey = new Map((t.config ?? []).map((r) => [String(r.key), r]))
  const rules: [string, (v: number) => boolean, string][] = [
    ['research_cost_growth', (v) => v >= 1, '1 or more'],
    ['research_time_growth', (v) => v >= 1, '1 or more'],
    ['lab_research_speed_per_level', (v) => v >= 0, '0 or more'],
    ['research_cancel_refund', (v) => v >= 0 && v <= 1, 'in 0..1'],
    ['research_dia_per_min', (v) => Number.isInteger(v) && v >= 0, 'a non-negative integer'],
  ]
  for (const [k, ok, why] of rules) {
    const r = byKey.get(k)
    if (r && isNum(String(r.value)) && !ok(Number(r.value))) errors.push(`config.csv line ${r._line} column 'value': ${k} must be ${why}: '${r.value}'`)
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
  checkUpgrades(out, errors)
  checkDungeons(out, errors) // 개정 18
  checkResearch(out, errors) // 개정 24
  // 등급마다 영웅이 하나 이상 있어야 모집이 그 등급을 뽑을 수 있다(없으면 /v1/gacha가 500)
  if (out.heroes) {
    for (const g of GRADES) {
      if (!out.heroes.some((h) => h.grade === g)) errors.push(`heroes.csv line 0 column 'grade': no ${g} heroes to recruit`)
    }
    checkHeroSkills(out.heroes, errors)
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

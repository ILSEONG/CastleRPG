// 게임 문구(다국어, 2026-10-14 사용자 "모든 메시지 라벨을 다국어로 관리, DB에 다국어 테이블"). 사용법: docs/TEXTS.md
// 원본 = DB texts 표(key · ko · en · ja · zh · note, 마이그레이션 049) ← neon:seed가 data/texts.csv와 기획 표 이름(DATA_TEXTS)으로 채운다.
// 서버 문구는 txt('키', {이름: 값}) — 값의 {이름}을 채운다. 시작할 때 data/texts.csv로 채워 두고(DB가 늦거나 비어도 키가 나가지 않게),
// app.ts가 DB 표를 읽으면(loadTexts, 기획 표와 같은 캐시 주기) 그 값으로 바꾼다. 앱은 GET /v1/texts?lang=ko 로 받는다.
// texts.csv: 따옴표 CSV(쉼표가 든 칸은 "…"), 값의 줄바꿈은 \n, 역슬래시는 \\ 로 적는다(한 줄 = 한 문구).
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

export const LANGS = ['ko', 'en', 'ja', 'zh'] as const
export type Lang = (typeof LANGS)[number]
export const DEFAULT_LANG: Lang = 'ko'
export const TEXT_COLS = ['key', ...LANGS, 'note'] as const
export type TextRow = Record<(typeof TEXT_COLS)[number], string | null>
const KEY_RE = /^[a-z0-9_]+(\.[a-z0-9_]+)*$/

// 기획 표의 이름 칸 → 문구 키 data.<표>.<id>.<칸>. 한국어는 표(CSV)가 원본이라 시드가 그 값으로 덮어쓴다 — 다른 언어 칸만 여기서 고친다.
export const DATA_TEXTS: Record<string, string[]> = {
  heroes: ['name', 'title', 'desc'], buildings: ['name'], research: ['name'], resources: ['name'], soldiers: ['name'], upgrades: ['name'],
}

export function unescapeValue(s: string): string {
  return s.replace(/\\(.)/g, (m, c: string) => ({ n: '\n', t: '\t', r: '\r', '\\': '\\' } as Record<string, string>)[c] ?? m)
}

// RFC 4180 CSV(따옴표 안의 쉼표·"" 허용). 줄 = 칸 배열.
export function parseQuotedCsv(text: string): string[][] {
  const out: string[][] = []
  let row: string[] = []
  let cell = ''
  let q = false
  const s = text.replace(/^﻿/, '')
  for (let i = 0; i < s.length; i++) {
    const c = s[i]
    if (q) {
      if (c === '"' && s[i + 1] === '"') { cell += '"'; i++ } else if (c === '"') q = false
      else cell += c
    } else if (c === '"') q = true
    else if (c === ',') { row.push(cell); cell = '' }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && s[i + 1] === '\n') i++
      row.push(cell); cell = ''
      out.push(row); row = []
    } else cell += c
  }
  if (cell !== '' || row.length) { row.push(cell); out.push(row) }
  return out.filter((r) => r.some((x) => x.trim() !== ''))
}

// texts.csv → 행(값은 풀어 둔 문장, 빈 칸 null). 오류는 errors에.
export function parseTexts(text: string, errors: string[], file = 'texts.csv'): TextRow[] {
  const lines = parseQuotedCsv(text)
  if (!lines.length) { errors.push(`${file} line 0 column 'key': empty file`); return [] }
  const head = lines[0].map((h) => h.trim())
  const idx = Object.fromEntries(TEXT_COLS.map((c) => [c, head.indexOf(c)]))
  for (const c of ['key', DEFAULT_LANG]) if (idx[c] < 0) errors.push(`${file} line 1 column '${c}': missing column`)
  if (errors.length) return []
  const seen = new Set<string>()
  const rows: TextRow[] = []
  lines.slice(1).forEach((cells, i) => {
    const get = (c: string) => (idx[c] >= 0 && idx[c] < cells.length && cells[idx[c]] !== '' ? unescapeValue(cells[idx[c]]) : null)
    const key = (get('key') ?? '').trim()
    const line = i + 2
    if (!KEY_RE.test(key)) return errors.push(`${file} line ${line} column 'key': bad key '${key}' (a-z 0-9 _ separated by .)`)
    if (seen.has(key)) return errors.push(`${file} line ${line} column 'key': duplicate key '${key}'`)
    if (get(DEFAULT_LANG) === null) return errors.push(`${file} line ${line} column 'ko': empty value`)
    seen.add(key)
    rows.push(Object.fromEntries(TEXT_COLS.map((c) => [c, c === 'key' ? key : get(c)])) as TextRow)
  })
  return rows
}

// 기획 표(시드가 읽은 행)의 이름 칸 → texts 행(ko만). 다른 언어는 DB에 이미 있는 값을 시드가 지키지 않으므로 texts.csv에 같은 키로 적는다.
export function dataTextRows(tables: Record<string, Record<string, unknown>[]>): TextRow[] {
  const out: TextRow[] = []
  for (const [table, cols] of Object.entries(DATA_TEXTS)) {
    for (const r of tables[table] ?? []) {
      for (const c of cols) {
        const v = r[c]
        if (v === null || v === undefined || v === '') continue
        out.push({ key: `data.${table}.${String(r.id)}.${c}`, ko: String(v), en: null, ja: null, zh: null, note: `data/${table}.csv` })
      }
    }
  }
  return out
}

// texts.csv 행 + 기획 표 이름 행. 같은 키가 texts.csv에도 있으면 그 행의 다른 언어 값을 쓰고 ko는 기획 표 값.
export function mergeTexts(csv: TextRow[], data: TextRow[]): TextRow[] {
  const byKey = new Map(csv.map((r) => [String(r.key), r]))
  const out = csv.filter((r) => !String(r.key).startsWith('data.'))
  for (const d of data) {
    const c = byKey.get(String(d.key))
    out.push(c ? { ...c, ko: d.ko, note: d.note } : d)
  }
  return out
}

// --- 실행 중 문구(언어별 사전) ---
let current: Record<string, Record<string, string>> = {}

// 행 → {언어: {키: 문장}}(빈 칸은 ko).
export function textMaps(rows: TextRow[]): Record<string, Record<string, string>> {
  const out: Record<string, Record<string, string>> = {}
  for (const l of LANGS) {
    const m: Record<string, string> = {}
    for (const r of rows) m[String(r.key)] = String(r[l] ?? r.ko)
    out[l] = m
  }
  return out
}

export function setTexts(rows: TextRow[]): void {
  current = textMaps(rows)
}

export function textMap(lang: string): Record<string, string> {
  return current[lang] ?? current[DEFAULT_LANG] ?? {}
}

// 키 → 문장({이름}은 params로 채운다). 없는 키는 키 그대로(빠진 문구가 바로 보이게).
export function txt(key: string, params?: Record<string, unknown>, lang: string = DEFAULT_LANG): string {
  const s = textMap(lang)[key] ?? current[DEFAULT_LANG]?.[key] ?? key
  if (!params) return s
  return s.replace(/\{([a-z0-9_]+)\}/gi, (m, n: string) => (Object.hasOwn(params, n) ? String(params[n]) : m))
}

// 시작 값: 저장소의 data/texts.csv(서버 코드와 같은 커밋). 읽지 못하면 빈 사전 — 키가 그대로 나간다.
export function loadBundledTexts(dataDir = join(import.meta.dirname, '..', '..', 'data')): TextRow[] {
  try {
    return parseTexts(readFileSync(join(dataDir, 'texts.csv'), 'utf8'), [])
  } catch {
    return []
  }
}

setTexts(loadBundledTexts())

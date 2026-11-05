// 플레이어가 고른 닉네임(2026-11-05, 마이그레이션 067). 이름을 보이는 곳(guild.ts playerName·rules.ts friendName)이 먼저 여기를 본다 —
// 없으면 id에서 정해지는 별명. 동기 함수에서 쓰므로 메모리에 둔다: 서버가 뜰 때 모두 읽고(load), 바꿀 때 바로 넣고(set),
// 서버는 하나(Render Starter)라 주기적으로 다시 읽지 않는다(Neon이 쉬도록).
import { findBad } from './profanity.ts'

const custom = new Map<string, string>()
export const MIN_LEN = 2
export const MAX_LEN = 8
export const DEFAULT_COST = 3000 // 두 번째 변경부터 다이아(game_config nickname_change_dia로 바꿀 수 있다)
const NAME_RE = /^[가-힣A-Za-z0-9]+$/
const RESERVED = ['운영자', '관리자', '운영팀', 'gm', 'admin', '캐슬', 'castlerpg', '시스템']

export function customName(id: string): string | undefined {
  return custom.get(id)
}

export function set(id: string, name: string) {
  custom.set(id, name)
}

export function forget(id: string) {
  custom.delete(id)
}

type Query = (sql: string, params?: unknown[]) => Promise<Record<string, unknown>[]>

export async function load(query: Query) {
  const rows = await query('select id::text as id, nickname from players where nickname is not null')
  custom.clear()
  for (const r of rows) custom.set(String(r.id), String(r.nickname))
}

// 새 닉네임 검사 → 오류 코드(괜찮으면 null): length 2~8자 · chars 한글·영문·숫자만 · bad 금칙어 · reserved 운영자 사칭.
export function check(name: string): 'length' | 'chars' | 'bad' | 'reserved' | null {
  const n = [...name].length
  if (n < MIN_LEN || n > MAX_LEN) return 'length'
  if (!NAME_RE.test(name)) return 'chars'
  if (findBad(name).length) return 'bad'
  const low = name.toLowerCase()
  if (RESERVED.some((w) => low.includes(w))) return 'reserved'
  return null
}

// 이번 변경 값: 처음(changes 0)은 무료, 그 뒤는 cost.
export function priceOf(changes: number, cost: number): number {
  return changes <= 0 ? 0 : cost
}

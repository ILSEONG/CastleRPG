// 파티 퀘스트(사용자 2026-10-15) 규칙과 매칭(서버 메모리). 앱 scripts/party_rules.gd와 같은 수치.
//  리치(lich): 4명 실시간, 성주마다 영웅 1명 — 보상 반지. 거미 여왕(spider): 3명, 성주마다 병사 4마리(조종 없음) — 보상 목걸이.
//  난이도 1 쉬움 · 2 보통(쉬움 ×10) · 3 어려움(보통 ×5) · 4 매우 어려움(어려움 ×3) — 사용자 수치. 배수는 적 HP·공격 모두에.
//  매칭: 같은 퀘스트·난이도 대기열에서 자리 수만큼 모이면 [입장 수락] 확인(CONFIRM_SEC) — 모두 수락해야 시작한다. 거절·시간 초과한 사람은 대기열에서 빠지고
//  수락한 사람은 대기열 앞으로 돌아간다. BOT_WAIT_SEC 넘게 기다리면 빈 자리를 AI 성주가 채운다(동시접속이 적어도 판이 열리게, Claude 기본값).
// 판 결과·보상은 party_routes.ts(표 party_runs·party_stats). 실시간 방은 party_live.ts.
import { randomUUID } from 'node:crypto'
import { mulberry32 } from './rules.ts'

export const QUESTS = ['lich', 'spider'] as const
export type Quest = (typeof QUESTS)[number]
export const isQuest = (q: unknown): q is Quest => typeof q === 'string' && (QUESTS as readonly string[]).includes(q)

export const SEATS: Record<Quest, number> = { lich: 4, spider: 3 } // 사용자: 리치 4명, 거미 여왕 3명
export const SOLDIERS_PER = 4 // 거미 여왕: 성주마다 병사 4마리
export const DIFFS = 4
export const DIFF_MULT = [1, 10, 50, 150] // 사용자: 보통 = 쉬움 ×10, 어려움 = 보통 ×5, 매우 어려움 = 어려움 ×3
export const ACCESSORY: Record<Quest, string> = { lich: 'ring', spider: 'necklace' }

// 아래는 Claude 기본값(2026-10-15, 바꿀 수 있다).
export const BOSS: Record<Quest, { hp: number; atk: number }> = { lich: { hp: 14000, atk: 70 }, spider: { hp: 9000, atk: 40 } } // 쉬움 기준
export const TIME_LIMIT: Record<Quest, number> = { lich: 180, spider: 180 } // 제한 시간(게임 초)
export const MIN_CLEAR_SEC = 2 // 이보다 빠른 승리는 받지 않는다(강한 파티의 빠른 승리는 아래 힘 검사로 본다)
export const REWARD_CLEARS = 3 // 퀘스트마다 하루 보상 받는 클리어 수(넘으면 같이 싸울 수는 있고 보상만 없다)
export const DPS_SLACK = 8 // 승리 힘 타당성 여유: 매치 초당 피해(서버 계산 — 스킬·치명타 빼고) × 걸린 시간 × 이만큼 ≥ 보스 HP(너무 약한·너무 빠른 승리를 함께 막는다)
// 난이도마다 장신구 등급 가중치(N R SR SSR UR LR — 다른 장비와 같은 등급)
export const DROP_WEIGHTS: number[][] = [
  [50, 35, 13, 2, 0, 0],
  [20, 35, 30, 12, 3, 0],
  [5, 20, 35, 28, 10, 2],
  [0, 5, 25, 40, 22, 8],
]
export const CONFIRM_SEC = 15 // [입장 수락] 제한 시간
export const BOT_WAIT_SEC = 30 // 이만큼 기다리면 빈 자리를 AI 성주가 채운다
export const QUEUE_STALE_SEC = 12 // 대기 중 이만큼 상태를 묻지 않으면(앱을 껐다) 대기열에서 뺀다
export const MATCH_TTL_SEC = 1800 // 끝나지 않은 매치는 이만큼 뒤 지운다

export const bossStats = (q: Quest, diff: number) => ({ hp: BOSS[q].hp * DIFF_MULT[diff - 1], atk: BOSS[q].atk * DIFF_MULT[diff - 1] })

// 장신구 등급(난이도 가중치, rand = 0..1).
export function dropGrade(grades: string[], diff: number, rand: () => number): string {
  const w = DROP_WEIGHTS[Math.min(Math.max(diff, 1), DIFFS) - 1]
  let pick = rand() * w.reduce((a, b) => a + b, 0)
  let out = grades[0]
  for (let i = 0; i < grades.length; i++) {
    if (!(w[i] > 0)) continue
    out = grades[i]
    pick -= w[i]
    if (pick < 0) break
  }
  return out
}

// 자리(성주 한 명)의 출전: 리치 = hero {hero, level, promotion, hp, atk}, 거미 = soldiers [{type, tier, hp, atk}] × 4.
export interface HeroUnit { hero: string; level: number; promotion: number; hp: number; atk: number }
export interface SoldierUnit { type: string; tier: number; hp: number; atk: number }
export interface Seat {
  pid: string | null // 사람 플레이어 id, AI 성주는 null
  name: string
  hero?: HeroUnit
  soldiers?: SoldierUnit[]
  dps: number // 서버 계산 초당 피해(승리 타당성)
  power: number // 비슷한 AI 성주 고르기 기준
  accepted: boolean
  left?: boolean // 판을 끝냈거나 나갔다(이 매치로 다시 묶지 않는다)
}
export interface Ticket { seat: Seat; quest: Quest; diff: number; since: number; seen: number }
export interface Match {
  id: string
  quest: Quest
  diff: number
  seats: Seat[]
  state: 'confirm' | 'live'
  deadline: number // confirm: 수락 마감
  started: number // live: 시작 시각
  seed: number
  result: { win: boolean; elapsed: number } | null
  created: number
}

// 매칭 허브. makeBot(quest, diff, 기준 자리, 번호) → AI 성주 자리.
export class PartyHub {
  queue: Ticket[] = []
  matches = new Map<string, Match>()
  private seq = 0
  makeBot: (quest: Quest, diff: number, like: Seat, n: number, rand: () => number) => Seat
  rand: () => number
  constructor(makeBot: (quest: Quest, diff: number, like: Seat, n: number, rand: () => number) => Seat, rand: () => number = Math.random) {
    this.makeBot = makeBot
    this.rand = rand
  }

  matchOf(pid: string): Match | null {
    for (const m of this.matches.values()) if (m.seats.some((s) => s.pid === pid && !s.left)) return m
    return null
  }

  // 판을 끝냈다(결과를 보냈다)·새로 대기열에 들어간다: 그 매치에서 놓아준다. 사람이 모두 나간 매치는 지운다.
  release(pid: string) {
    const m = this.matchOf(pid)
    if (!m) return
    for (const s of m.seats) if (s.pid === pid) s.left = true
    if (m.seats.every((s) => s.pid == null || s.left)) this.matches.delete(m.id)
  }

  ticketOf(pid: string): Ticket | null {
    return this.queue.find((t) => t.seat.pid === pid) ?? null
  }

  // 대기열에 넣는다(이미 있으면 바꾼다). 수락 확인 중인 매치가 있으면 false — 시작한 판은 놓아준다(앱이 꺼져 결과를 못 보냈다).
  join(seat: Seat, quest: Quest, diff: number, now: number): boolean {
    const m = this.matchOf(seat.pid!)
    if (m?.state === 'confirm') return false
    if (m) this.release(seat.pid!)
    this.leave(seat.pid!)
    this.queue.push({ seat: { ...seat, accepted: false }, quest, diff, since: now, seen: now })
    this.tick(now)
    return true
  }

  leave(pid: string) {
    this.queue = this.queue.filter((t) => t.seat.pid !== pid)
  }

  seen(pid: string, now: number) {
    const t = this.ticketOf(pid)
    if (t) t.seen = now
  }

  // 수락(yes) · 거절(no). 거절은 그 사람을 매치에서 빼고(대기열에도 안 넣는다) 다른 사람은 대기열 앞으로.
  answer(pid: string, matchId: string, yes: boolean, now: number): boolean {
    const m = this.matches.get(matchId)
    if (!m || m.state !== 'confirm') return false
    const s = m.seats.find((x) => x.pid === pid)
    if (!s) return false
    if (!yes) {
      this.dissolve(m, new Set([pid]), now)
      return true
    }
    s.accepted = true
    if (m.seats.every((x) => x.accepted)) {
      m.state = 'live'
      m.started = now
    }
    return true
  }

  // 매치를 풀고 수락하지 않은 사람(drop)은 빼고, 나머지 사람은 대기열 앞으로 — 이미 오래 기다렸으니 빈 자리는 곧바로 AI 성주가 채운다.
  private dissolve(m: Match, drop: Set<string>, now: number) {
    this.matches.delete(m.id)
    const back = m.seats.filter((s) => s.pid && !drop.has(s.pid)).map((s) => ({ seat: { ...s, accepted: false }, quest: m.quest, diff: m.diff, since: now - BOT_WAIT_SEC, seen: now }))
    this.queue.unshift(...back)
  }

  // 시간 흐름: 오래 안 물은 대기 빼기 · 수락 마감 · 매치 만들기(사람 먼저, 오래 기다리면 AI 성주로 채움) · 오래된 매치 지우기.
  tick(now: number) {
    this.queue = this.queue.filter((t) => now - t.seen <= QUEUE_STALE_SEC)
    for (const m of [...this.matches.values()]) {
      if (m.state === 'confirm' && now >= m.deadline) this.dissolve(m, new Set(m.seats.filter((s) => s.pid && !s.accepted).map((s) => s.pid!)), now)
      else if (now - m.created > MATCH_TTL_SEC) this.matches.delete(m.id)
    }
    for (const q of QUESTS) {
      for (let d = 1; d <= DIFFS; d++) {
        for (;;) {
          const pool = this.queue.filter((t) => t.quest === q && t.diff === d)
          if (!pool.length) break
          const need = SEATS[q]
          let picks: Ticket[]
          if (pool.length >= need) picks = pool.slice(0, need)
          else if (now - pool[0].since >= BOT_WAIT_SEC) picks = pool
          else break
          this.open(q, d, picks, now)
        }
      }
    }
  }

  private open(quest: Quest, diff: number, picks: Ticket[], now: number) {
    const taken = new Set(picks)
    this.queue = this.queue.filter((t) => !taken.has(t))
    const seats = picks.map((t) => ({ ...t.seat, accepted: false }))
    const r = mulberry32((this.rand() * 2 ** 31) >>> 0)
    for (let n = 0; seats.length < SEATS[quest]; n++) seats.push({ ...this.makeBot(quest, diff, seats[n % picks.length], n, r), accepted: true })
    const id = `${now.toFixed(0)}-${++this.seq}-${randomUUID().slice(0, 8)}`
    this.matches.set(id, { id, quest, diff, seats, state: 'confirm', deadline: now + CONFIRM_SEC, started: 0, seed: Math.floor(this.rand() * 2 ** 31), result: null, created: now })
  }

  // 방장(또는 혼자 남은 기기)이 알린 결과 — 처음 것만 남긴다.
  report(matchId: string, win: boolean, elapsed: number) {
    const m = this.matches.get(matchId)
    if (m && m.state === 'live' && !m.result) m.result = { win, elapsed }
  }
}

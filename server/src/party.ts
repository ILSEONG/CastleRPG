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
// 사람이 나 혼자(나머지 AI 성주)인 판의 여유(2026-10-27 보안 점검): 결과를 내 기기만 정한다. 파티 영웅은 서버가 준 능력치 그대로(성장 치명타·공격 속도 없음) —
// 스킬·거인 사냥·보스 약점(수확 깨기 +30%)을 다 더해도 정상 승리는 초당 피해의 2배 안팎(수확 막·수정·회피로 쉬는 시간도 있다). 여유를 두고 3.
export const SOLO_DPS_SLACK = 3
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
// 파티 코드(사용자 2026-10-15 "파티코드 있어서 파티를 구성할수잇어"): [파티 만들기] → 코드 → 다른 성주가 [코드로 참가]. 방장이 [매칭 시작]을 누르면
// 파티원이 한 묶음으로 대기열에 들어가 같은 매치에 앉고, 빈자리는 무작위 매칭 → BOT_WAIT_SEC 뒤 AI 성주(Claude 기본값).
export const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' // 헷갈리는 0·O·1·I 뺌
export const CODE_LEN = 6
export const LOBBY_STALE_SEC = 30 // 파티원이 이만큼 상태를 묻지 않으면(앱을 껐다) 파티에서 뺀다(대기·매치 중은 빼지 않는다)
export const LOBBY_TTL_SEC = 6 * 3600 // 오래된 파티는 지운다
export const JOIN_TRIES = 10 // 틀린 코드 시도 수(JOIN_WINDOW_SEC 안) — 넘으면 잠시 막는다(코드 맞히기 막기)
export const JOIN_WINDOW_SEC = 600
// 초대(사용자 2026-10-15 "그냥 초대도되고", Claude 기본값): 친구·같은 길드원 중 지금 접속 중인 성주에게. 받은 초대는 INVITE_TTL_SEC 뒤 사라진다.
export const INVITE_TTL_SEC = 60
export const INVITE_INBOX = 5 // 한 사람이 들고 있는 초대 수(넘으면 오래된 것부터 버린다)
export const INVITE_MAX = 20 // 보낸 초대 수 상한(INVITE_WINDOW_SEC 안, 도배 막기)
export const INVITE_WINDOW_SEC = 600
export const ONLINE_SEC = 60 // 마지막 요청이 이 안이면 '접속 중'(앱은 켜져 있으면 20초마다 채팅·초대를 묻는다)

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
  group?: string // 파티 코드(같은 코드의 대기는 한 매치에 함께 앉는다)
}
export interface Lobby { code: string; quest: Quest; diff: number; leader: string; members: { seat: Seat; seen: number }[]; created: number }
export type LobbyError = 'no_code' | 'full' | 'not_leader' | 'no_lobby' | 'busy'
export interface Invite { id: string; from: string; name: string; code: string; quest: Quest; diff: number; at: number }
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
  lobbies = new Map<string, Lobby>()
  invites = new Map<string, Invite[]>() // 받는 사람 → 받은 초대(새것이 뒤)
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
    for (const l of [...this.lobbies.values()]) {
      for (const m of [...l.members]) {
        const pid = m.seat.pid!
        if (now - m.seen > LOBBY_STALE_SEC && !this.ticketOf(pid) && !this.matchOf(pid)) this.leaveLobby(pid)
      }
      if (now - l.created > LOBBY_TTL_SEC) {
        this.queue = this.queue.filter((t) => t.seat.group !== l.code)
        this.lobbies.delete(l.code)
      }
    }
    for (const [pid, list] of this.invites) if (list.every((i) => now - i.at >= INVITE_TTL_SEC)) this.invites.delete(pid)
    for (const q of QUESTS) {
      for (let d = 1; d <= DIFFS; d++) {
        for (;;) {
          const pool = this.queue.filter((t) => t.quest === q && t.diff === d)
          if (!pool.length) break
          // 파티(같은 group)는 한 덩어리 — 먼저 온 순서로 덩어리째 자리에 넣는다
          const units: Ticket[][] = []
          const byKey = new Map<string, Ticket[]>()
          for (const t of pool) {
            const k = t.seat.group ? `g:${t.seat.group}` : `p:${t.seat.pid}`
            let u = byKey.get(k)
            if (!u) {
              u = []
              byKey.set(k, u)
              units.push(u)
            }
            u.push(t)
          }
          const need = SEATS[q]
          // 가장 오래 기다린 덩어리 먼저, 나머지는 큰 덩어리부터(파티가 혼자 온 사람들 때문에 밀리지 않게) — 같은 크기는 먼저 온 순서
          const picks: Ticket[] = [...units[0]]
          const rest = units.slice(1).map((u, i) => ({ u, i })).sort((a, b) => b.u.length - a.u.length || a.i - b.i)
          for (const { u } of rest) if (picks.length + u.length <= need) picks.push(...u)
          if (picks.length >= need || picks.some((t) => now - t.since >= BOT_WAIT_SEC)) this.open(q, d, picks, now)
          else break
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

  // --- 파티(코드) ---

  lobbyOf(pid: string): Lobby | null {
    for (const l of this.lobbies.values()) if (l.members.some((m) => m.seat.pid === pid)) return l
    return null
  }

  private newCode(): string {
    for (;;) {
      let c = ''
      for (let i = 0; i < CODE_LEN; i++) c += CODE_CHARS[Math.floor(this.rand() * CODE_CHARS.length)]
      if (!this.lobbies.has(c)) return c
    }
  }

  // [파티 만들기]: 다른 파티·대기에서 빠지고 새 파티의 방장이 된다. 수락 확인 중이면 'busy'.
  createLobby(seat: Seat, quest: Quest, diff: number, now: number): Lobby | LobbyError {
    if (this.matchOf(seat.pid!)?.state === 'confirm') return 'busy'
    this.leaveLobby(seat.pid!)
    this.leave(seat.pid!)
    const l: Lobby = { code: this.newCode(), quest, diff, leader: seat.pid!, members: [{ seat: { ...seat, accepted: false }, seen: now }], created: now }
    this.lobbies.set(l.code, l)
    return l
  }

  // [코드로 참가]: 같은 파티에 다시 보내면 출전만 바꾼다. 다른 파티에 있었으면 거기서 빠진다.
  joinLobby(code: string, seat: Seat, now: number): Lobby | LobbyError {
    const l = this.lobbies.get(code)
    if (!l) return 'no_code'
    const mine = l.members.find((m) => m.seat.pid === seat.pid)
    if (mine) {
      mine.seat = { ...seat, accepted: false, group: mine.seat.group }
      mine.seen = now
      return l
    }
    if (l.members.length >= SEATS[l.quest]) return 'full'
    if (this.matchOf(seat.pid!)?.state === 'confirm') return 'busy'
    this.leaveLobby(seat.pid!)
    this.leave(seat.pid!)
    l.members.push({ seat: { ...seat, accepted: false }, seen: now })
    return l
  }

  // 파티 나가기: 대기 중이면 대기에서도 빠진다. 방장이 나가면 다음 사람이 방장, 아무도 없으면 파티를 지운다.
  leaveLobby(pid: string) {
    const l = this.lobbyOf(pid)
    if (!l) return
    l.members = l.members.filter((m) => m.seat.pid !== pid)
    const t = this.ticketOf(pid)
    if (t?.seat.group === l.code) this.leave(pid)
    if (!l.members.length) this.lobbies.delete(l.code)
    else if (l.leader === pid) l.leader = l.members[0].seat.pid!
  }

  // 방장이 [매칭 시작]: 파티원 모두 한 묶음(group = 코드)으로 대기열에. 수락 확인·시작한 판에 있는 파티원이 있으면 'busy'.
  startLobby(pid: string, diff: number, now: number): Lobby | LobbyError {
    const l = this.lobbyOf(pid)
    if (!l) return 'no_lobby'
    if (l.leader !== pid) return 'not_leader'
    if (l.members.some((m) => this.matchOf(m.seat.pid!)?.state === 'confirm')) return 'busy'
    l.diff = diff
    for (const m of l.members) {
      const pm = this.matchOf(m.seat.pid!)
      if (pm) this.release(m.seat.pid!)
      this.leave(m.seat.pid!)
      m.seen = now
      this.queue.push({ seat: { ...m.seat, accepted: false, group: l.code }, quest: l.quest, diff, since: now, seen: now })
    }
    this.tick(now)
    return l
  }

  // 방장 [취소]: 파티원 대기를 모두 뺀다(파티는 그대로).
  cancelLobby(pid: string) {
    const l = this.lobbyOf(pid)
    if (!l || l.leader !== pid) return
    this.queue = this.queue.filter((t) => t.seat.group !== l.code)
  }

  // [초대]: 내 파티로 부른다. 같은 사람에게 다시 보내면 앞 초대를 새것으로 바꾼다. 이미 파티원이거나 파티가 가득이면 오류.
  invite(from: string, to: string, now: number): Invite | LobbyError | 'member' {
    const l = this.lobbyOf(from)
    if (!l) return 'no_lobby'
    if (l.members.some((m) => m.seat.pid === to)) return 'member'
    if (l.members.length >= SEATS[l.quest]) return 'full'
    const name = l.members.find((m) => m.seat.pid === from)!.seat.name
    const inv: Invite = { id: randomUUID(), from, name, code: l.code, quest: l.quest, diff: l.diff, at: now }
    const list = (this.invites.get(to) ?? []).filter((i) => i.from !== from && now - i.at < INVITE_TTL_SEC)
    list.push(inv)
    this.invites.set(to, list.slice(-INVITE_INBOX))
    return inv
  }

  // 받은 초대(지난 것, 파티가 없어졌거나 가득 찬 것, 이미 그 파티에 있는 것은 뺀다)
  invitesOf(pid: string, now: number): Invite[] {
    const list = this.invites.get(pid)
    if (!list) return []
    const mine = this.lobbyOf(pid)?.code
    const ok = list.filter((i) => {
      const l = this.lobbies.get(i.code)
      return now - i.at < INVITE_TTL_SEC && l && i.code !== mine && l.members.length < SEATS[l.quest] && l.members.some((m) => m.seat.pid === i.from)
    })
    if (ok.length) this.invites.set(pid, ok)
    else this.invites.delete(pid)
    return ok
  }

  dropInvite(pid: string, id: string) {
    const list = (this.invites.get(pid) ?? []).filter((i) => i.id !== id)
    if (list.length) this.invites.set(pid, list)
    else this.invites.delete(pid)
  }

  lobbySeen(pid: string, now: number) {
    const m = this.lobbyOf(pid)?.members.find((x) => x.seat.pid === pid)
    if (m) m.seen = now
  }

  // 방장(또는 혼자 남은 기기)이 알린 결과 — 처음 것만 남긴다.
  report(matchId: string, win: boolean, elapsed: number) {
    const m = this.matches.get(matchId)
    if (m && m.state === 'live' && !m.result) m.result = { win, elapsed }
  }
}

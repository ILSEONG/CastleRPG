// 공성전 실시간 방(WebSocket, 경로 /v1/guild/war/live?battle=<id>&token=<JWT>). 전투 판단은 방장 기기 한 대가 하고(앱 war_battle.gd),
// 서버는 메시지를 나르기만 한다:
//  방장 → 서버: {t:"snap", s}(SNAP마다 상태 한 장 — 나머지에게 그대로 보내고 마지막 것을 둔다), {t:"ckpt", state}·{t:"end", state}(성 상태 — onState가 DB에 합친다)
//  참가자 → 서버: {t:"cmd", uid, pos}(내 영웅 이동 명령) → 방장에게 {t:"cmd", from, uid, pos}
//  서버 → 클라이언트: {t:"hello", host, snap}(들어왔을 때), {t:"host", snap}(방장이 나가 이어받음), {t:"roster", squad}(새 길드원 분대),
//    {t:"end"}(전투가 끝났다), {t:"snap", s}, {t:"cmd", ...}
// 방장 = 지금 방에 있는 사람 중 먼저 들어온 사람. 한 사람이 다시 접속하면 예전 연결은 닫는다. 방이 비면 지운다(성 상태는 DB에 있다).
import type { IncomingMessage, Server } from 'node:http'
import type { Duplex } from 'node:stream'
import { WebSocketServer } from 'ws'
import type { WebSocket } from 'ws'

export const LIVE_PATH = '/v1/guild/war/live'
const MAX_MSG = 256 * 1024
// 도배 막기(2026-10-14 보안 점검): 한 연결이 1초에 보낼 수 있는 메시지(방장 snap은 0.1초마다 — x2 배속이어도 넉넉하게),
// 성 상태 저장(ckpt — 앱은 10초마다)은 방마다 CKPT_GAP초에 한 번·한 번에 하나만 DB에 간다. end는 늘 받는다.
const MSG_PER_SEC = 60
const CKPT_GAP = 2

interface Client { ws: WebSocket; pid: string; at: number; win: number; n: number }
interface Room { clients: Client[]; host: Client | null; last: unknown; ckptAt: number; saving: boolean }

export class WarLive {
  rooms = new Map<string, Room>()
  // createApp이 채운다
  verify: (token: string) => Promise<string | null> = async () => null
  canJoin: (battleId: string, pid: string) => Promise<boolean> = async () => false
  onState: (battleId: string, pid: string, state: unknown, final: boolean) => Promise<boolean> = async () => false // true = 전투가 닫혔다
  private wss = new WebSocketServer({ noServer: true, maxPayload: MAX_MSG })
  private seq = 0

  attach(server: Server) {
    server.on('upgrade', (req: IncomingMessage, sock: Duplex, head: Buffer) => {
      const url = new URL(req.url ?? '/', 'http://x')
      if (url.pathname !== LIVE_PATH) return
      // 확인 중 오류(DB 오류 등)가 처리 안 된 거부로 새면 Node가 프로세스를 끝낸다 — 소켓만 닫는다
      this.accept(req, sock, head, url).catch((e) => {
        console.warn(`[war] live accept failed: ${(e as Error).message}`)
        sock.destroy()
      })
    })
  }

  private async accept(req: IncomingMessage, sock: Duplex, head: Buffer, url: URL) {
    const battle = url.searchParams.get('battle') ?? ''
    const pid = await this.verify(url.searchParams.get('token') ?? '')
    if (!pid || !(await this.canJoin(battle, pid))) {
      sock.write('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n')
      sock.destroy()
      return
    }
    this.wss.handleUpgrade(req, sock, head, (ws) => this.join(battle, pid, ws))
  }

  join(battle: string, pid: string, ws: WebSocket) {
    let room = this.rooms.get(battle)
    if (!room) {
      room = { clients: [], host: null, last: null, ckptAt: 0, saving: false }
      this.rooms.set(battle, room)
    }
    for (const old of room.clients.filter((c) => c.pid === pid)) {
      this.drop(battle, old)
      old.ws.close(4000, 'replaced')
    }
    const me: Client = { ws, pid, at: ++this.seq, win: 0, n: 0 }
    room.clients.push(me)
    if (!room.host) room.host = me
    send(ws, { t: 'hello', host: room.host === me, snap: room.last ?? null })
    ws.on('message', (raw) => this.onMessage(battle, me, String(raw)))
    ws.on('close', () => this.drop(battle, me))
    ws.on('error', () => this.drop(battle, me))
  }

  private onMessage(battle: string, me: Client, raw: string) {
    const room = this.rooms.get(battle)
    if (!room || !room.clients.includes(me)) return
    const sec = Math.floor(Date.now() / 1000)
    if (me.win !== sec) {
      me.win = sec
      me.n = 0
    }
    if (++me.n > MSG_PER_SEC) return
    let m: Record<string, unknown>
    try {
      m = JSON.parse(raw)
    } catch {
      return
    }
    if (!m || typeof m !== 'object') return
    const isHost = room.host === me
    if (m.t === 'snap' && isHost) {
      const out = JSON.stringify({ t: 'snap', s: m.s })
      room.last = mergeSnap(room.last, m.s)
      for (const c of room.clients) if (c !== me) sendRaw(c.ws, out)
    } else if ((m.t === 'ckpt' || m.t === 'end') && isHost) {
      const end = m.t === 'end'
      const now = Date.now() / 1000
      if (!end && (room.saving || now - room.ckptAt < CKPT_GAP)) return
      room.saving = true
      room.ckptAt = now
      void this.onState(battle, me.pid, m.state, end).then((closed) => {
        // 일찍 온 end(시간이 남았고 성채가 서 있다)는 전투를 닫지 않는다 — 그때는 다른 길드원을 내보내지 않는다
        if (closed) this.broadcast(battle, { t: 'end' })
      }, (e) => console.warn(`[war] state save failed: ${(e as Error).message}`)).finally(() => { room.saving = false })
    } else if (m.t === 'cmd' && !isHost && room.host) {
      send(room.host.ws, { t: 'cmd', from: me.pid, uid: m.uid, pos: m.pos ?? null })
    }
  }

  private drop(battle: string, me: Client) {
    const room = this.rooms.get(battle)
    if (!room) return
    const i = room.clients.indexOf(me)
    if (i < 0) return
    room.clients.splice(i, 1)
    if (room.host === me) {
      room.host = room.clients.reduce<Client | null>((a, c) => (a == null || c.at < a.at ? c : a), null)
      if (room.host) send(room.host.ws, { t: 'host', snap: room.last ?? null })
    }
    if (room.clients.length === 0) this.rooms.delete(battle)
  }

  broadcast(battle: string, msg: unknown) {
    const room = this.rooms.get(battle)
    if (!room) return
    const out = JSON.stringify(msg)
    for (const c of room.clients) sendRaw(c.ws, out)
  }

  hostOf(battle: string): string | null {
    return this.rooms.get(battle)?.host?.pid ?? null
  }

  close() {
    for (const room of this.rooms.values()) for (const c of room.clients) c.ws.close()
    this.rooms.clear()
    this.wss.close()
  }
}

// 방장은 바뀐 영웅 행만 보낸다(앱 war_battle.snapshot_delta) — 새로 들어온 사람·새 방장이 받을 마지막 장은 영웅 행(u)을 합친 것.
// 행 말고는 새 장 값 그대로. 예전 앱(늘 전부 보냄)도 같다.
// 행 = 숫자 몇 개(앱 war_hero/monster.puppet_row)만 받고, 합친 행이 MAX_UNITS를 넘으면 이번 장만 남긴다(2026-10-27 보안 점검:
// 방장이 매번 새 키를 보내 마지막 장을 끝없이 키워 서버 메모리를 다 쓰지 못하게 — 정상 전투는 수백 행, 3초마다 전부 다시 온다).
export const MAX_UNITS = 1024
const MAX_ROW = 12
const okRow = ([k, v]: [string, unknown]) => k.length <= 32 && Array.isArray(v) && v.length <= MAX_ROW && v.every((x) => typeof x === 'number')

export function mergeSnap(prev: any, s: unknown): unknown {
  if (!s || typeof s !== 'object' || Array.isArray(s)) return s
  const u = (s as Record<string, unknown>).u
  if (!u || typeof u !== 'object' || Array.isArray(u)) return s
  const rows = Object.fromEntries(Object.entries(u).filter(okRow).slice(0, MAX_UNITS))
  const pu = prev && typeof prev === 'object' && prev.u && typeof prev.u === 'object' && !Array.isArray(prev.u) ? prev.u : {}
  const merged = { ...pu, ...rows }
  return { ...(s as Record<string, unknown>), u: Object.keys(merged).length > MAX_UNITS ? rows : merged }
}

function send(ws: WebSocket, msg: unknown) {
  sendRaw(ws, JSON.stringify(msg))
}

function sendRaw(ws: WebSocket, s: string) {
  if (ws.readyState === 1) ws.send(s)
}

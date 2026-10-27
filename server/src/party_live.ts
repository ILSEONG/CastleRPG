// 파티 퀘스트 실시간 방(WebSocket, 경로 /v1/party/live?match=<id>&token=<JWT>). 공성전 방(war_live.ts)과 같은 방식: 전투 판단은 방장 기기 한 대가 하고
// (앱 party_battle.gd), 서버는 메시지를 나르기만 한다.
//  방장 → 서버: {t:"snap", s}(상태 한 장 — 나머지에게 그대로 보내고 마지막 것을 둔다), {t:"end", win, elapsed}(결과 — PartyHub.report, 모두에게 end)
//  참가자 → 서버: {t:"cmd", uid, pos}(내 영웅 이동·공격 명령) → 방장에게 {t:"cmd", seat, uid, pos}(seat = 보낸 사람 자리 번호)
//  서버 → 클라이언트: {t:"hello", host, snap}, {t:"host", snap}(방장이 나가 이어받음), {t:"end", win}, {t:"snap", s}, {t:"cmd", ...}
// 방장 = 지금 방에 있는 사람 중 먼저 들어온 사람. 한 사람이 다시 접속하면 예전 연결은 닫는다. 방이 비면 지운다.
import type { IncomingMessage, Server } from 'node:http'
import type { Duplex } from 'node:stream'
import { WebSocketServer } from 'ws'
import type { WebSocket } from 'ws'

export const PARTY_LIVE_PATH = '/v1/party/live'
const MAX_MSG = 128 * 1024
const MSG_PER_SEC = 40 // 방장 snap은 0.2초마다(x2 배속이어도 넉넉), 명령은 탭마다

interface Client { ws: WebSocket; pid: string; at: number; win: number; n: number }
interface Room { clients: Client[]; host: Client | null; last: string | null; ended: boolean }

export class PartyLive {
  rooms = new Map<string, Room>()
  // createApp(party_routes)이 채운다
  verify: (token: string) => Promise<string | null> = async () => null
  seatOf: (matchId: string, pid: string) => number = () => -1 // 그 매치에서 이 사람의 자리 번호(-1 = 못 들어온다)
  onEnd: (matchId: string, pid: string, win: boolean, elapsed: number) => void = () => {}
  private wss = new WebSocketServer({ noServer: true, maxPayload: MAX_MSG })
  private seq = 0

  attach(server: Server) {
    server.on('upgrade', (req: IncomingMessage, sock: Duplex, head: Buffer) => {
      const url = new URL(req.url ?? '/', 'http://x')
      if (url.pathname !== PARTY_LIVE_PATH) return
      this.accept(req, sock, head, url).catch((e) => { // 처리 안 된 거부는 프로세스를 끝낸다(war_live.ts와 같다)
        console.warn(`[party] live accept failed: ${(e as Error).message}`)
        sock.destroy()
      })
    })
  }

  private async accept(req: IncomingMessage, sock: Duplex, head: Buffer, url: URL) {
    const match = url.searchParams.get('match') ?? ''
    const pid = await this.verify(url.searchParams.get('token') ?? '')
    if (!pid || this.seatOf(match, pid) < 0) {
      sock.write('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n')
      sock.destroy()
      return
    }
    this.wss.handleUpgrade(req, sock, head, (ws) => this.join(match, pid, ws))
  }

  join(match: string, pid: string, ws: WebSocket) {
    let room = this.rooms.get(match)
    if (!room) {
      room = { clients: [], host: null, last: null, ended: false }
      this.rooms.set(match, room)
    }
    for (const old of room.clients.filter((c) => c.pid === pid)) {
      this.drop(match, old)
      old.ws.close(4000, 'replaced')
    }
    const me: Client = { ws, pid, at: ++this.seq, win: 0, n: 0 }
    room.clients.push(me)
    if (!room.host) room.host = me
    send(ws, { t: 'hello', host: room.host === me, snap: room.last ? JSON.parse(room.last) : null })
    ws.on('message', (raw) => this.onMessage(match, me, String(raw)))
    ws.on('close', () => this.drop(match, me))
    ws.on('error', () => this.drop(match, me))
  }

  private onMessage(match: string, me: Client, raw: string) {
    const room = this.rooms.get(match)
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
    if (m.t === 'snap' && isHost && !room.ended) {
      const out = JSON.stringify({ t: 'snap', s: m.s })
      room.last = JSON.stringify(m.s)
      for (const c of room.clients) if (c !== me) sendRaw(c.ws, out)
    } else if (m.t === 'end' && isHost && !room.ended) {
      const elapsed = Number(m.elapsed)
      if (typeof m.win !== 'boolean' || !Number.isFinite(elapsed) || elapsed < 0) return
      room.ended = true
      this.onEnd(match, me.pid, m.win, elapsed)
      this.broadcast(match, { t: 'end', win: m.win, elapsed })
    } else if (m.t === 'cmd' && !isHost && room.host) {
      const seat = this.seatOf(match, me.pid) // 플레이어 id는 다른 기기에 보내지 않는다 — 자리 번호로
      if (seat >= 0) send(room.host.ws, { t: 'cmd', seat, uid: m.uid, pos: m.pos ?? null })
    }
  }

  private drop(match: string, me: Client) {
    const room = this.rooms.get(match)
    if (!room) return
    const i = room.clients.indexOf(me)
    if (i < 0) return
    room.clients.splice(i, 1)
    if (room.host === me) {
      room.host = room.clients.reduce<Client | null>((a, c) => (a == null || c.at < a.at ? c : a), null)
      if (room.host) send(room.host.ws, { t: 'host', snap: room.last ? JSON.parse(room.last) : null })
    }
    if (room.clients.length === 0) this.rooms.delete(match)
  }

  broadcast(match: string, msg: unknown) {
    const room = this.rooms.get(match)
    if (!room) return
    const out = JSON.stringify(msg)
    for (const c of room.clients) sendRaw(c.ws, out)
  }

  close() {
    for (const room of this.rooms.values()) for (const c of room.clients) c.ws.close()
    this.rooms.clear()
    this.wss.close()
  }
}

function send(ws: WebSocket, msg: unknown) {
  sendRaw(ws, JSON.stringify(msg))
}

function sendRaw(ws: WebSocket, s: string) {
  if (ws.readyState === 1) ws.send(s)
}

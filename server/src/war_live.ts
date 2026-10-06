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

interface Client { ws: WebSocket; pid: string; at: number }
interface Room { clients: Client[]; host: Client | null; last: string | null }

export class WarLive {
  rooms = new Map<string, Room>()
  // createApp이 채운다
  verify: (token: string) => Promise<string | null> = async () => null
  canJoin: (battleId: string, pid: string) => Promise<boolean> = async () => false
  onState: (battleId: string, pid: string, state: unknown, final: boolean) => Promise<void> = async () => {}
  private wss = new WebSocketServer({ noServer: true, maxPayload: MAX_MSG })
  private seq = 0

  attach(server: Server) {
    server.on('upgrade', (req: IncomingMessage, sock: Duplex, head: Buffer) => {
      const url = new URL(req.url ?? '/', 'http://x')
      if (url.pathname !== LIVE_PATH) return
      void this.accept(req, sock, head, url)
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
      room = { clients: [], host: null, last: null }
      this.rooms.set(battle, room)
    }
    for (const old of room.clients.filter((c) => c.pid === pid)) {
      this.drop(battle, old)
      old.ws.close(4000, 'replaced')
    }
    const me: Client = { ws, pid, at: ++this.seq }
    room.clients.push(me)
    if (!room.host) room.host = me
    send(ws, { t: 'hello', host: room.host === me, snap: room.last ? JSON.parse(room.last) : null })
    ws.on('message', (raw) => this.onMessage(battle, me, String(raw)))
    ws.on('close', () => this.drop(battle, me))
    ws.on('error', () => this.drop(battle, me))
  }

  private onMessage(battle: string, me: Client, raw: string) {
    const room = this.rooms.get(battle)
    if (!room || !room.clients.includes(me)) return
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
      room.last = JSON.stringify(m.s)
      for (const c of room.clients) if (c !== me) sendRaw(c.ws, out)
    } else if ((m.t === 'ckpt' || m.t === 'end') && isHost) {
      void this.onState(battle, me.pid, m.state, m.t === 'end').then(() => {
        if (m.t === 'end') this.broadcast(battle, { t: 'end' })
      }, (e) => console.warn(`[war] state save failed: ${(e as Error).message}`))
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
      if (room.host) send(room.host.ws, { t: 'host', snap: room.last ? JSON.parse(room.last) : null })
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

function send(ws: WebSocket, msg: unknown) {
  sendRaw(ws, JSON.stringify(msg))
}

function sendRaw(ws: WebSocket, s: string) {
  if (ws.readyState === 1) ws.send(s)
}

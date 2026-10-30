// 채팅 실시간 전달(WebSocket, 경로 /v1/chat/live?token=<JWT>, 2026-10-30 사용자 "1~4번 다 해줘"의 3번).
// 앱이 채팅을 3초·20초마다 묻던 것을, 새 메시지가 생길 때 서버가 바로 밀어 준다. 받는 쪽은 듣기만 한다(보내기·신고는 그대로 REST).
//  서버 → 앱: {t:"msg", ch:"all"|"guild", msg:{id, name, text, at, me}}
// 전체 채널은 연결된 모두에게, 길드 채널은 보낼 때의 길드원에게(chat.ts가 받는 사람을 정한다). 보낸 사람은 POST 응답으로 이미 받았으니 빼고 보낸다.
// 한 사람이 다시 접속하면 예전 연결은 닫는다. 앱은 연결이 있으면 가끔만 폴링하고(놓친 줄 채우기), 끊기면 원래 폴링으로 돌아간다.
import type { IncomingMessage, Server } from 'node:http'
import type { Duplex } from 'node:stream'
import { WebSocketServer } from 'ws'
import type { WebSocket } from 'ws'

export const CHAT_LIVE_PATH = '/v1/chat/live'
export const MAX_MSG = 1024 // 앱은 보내지 않는다 — 작게
export const MAX_BUFFER = 256 * 1024 // 받지 않고 쌓이기만 하는 연결은 끊는다
export const HEARTBEAT_MS = 30_000 // 이만큼마다 ping — 그 사이 pong이 없던 연결은 끊는다

interface Client { ws: WebSocket; pid: string; alive: boolean }
export interface ChatRow { id: number; name: string; text: string; at: number; player_id: string }

export class ChatLive {
  clients = new Map<string, Client>()
  // createApp(chat.ts)이 채운다
  verify: (token: string) => Promise<string | null> = async () => null
  private wss = new WebSocketServer({ noServer: true, maxPayload: MAX_MSG })
  private beat = setInterval(() => this.sweep(), HEARTBEAT_MS).unref()

  attach(server: Server) {
    server.on('upgrade', (req: IncomingMessage, sock: Duplex, head: Buffer) => {
      const url = new URL(req.url ?? '/', 'http://x')
      if (url.pathname !== CHAT_LIVE_PATH) return
      this.accept(req, sock, head, url).catch((e) => {
        console.warn(`[chat] live accept failed: ${(e as Error).message}`)
        sock.destroy()
      })
    })
  }

  private async accept(req: IncomingMessage, sock: Duplex, head: Buffer, url: URL) {
    const pid = await this.verify(url.searchParams.get('token') ?? '')
    if (!pid) {
      sock.write('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n')
      sock.destroy()
      return
    }
    this.wss.handleUpgrade(req, sock, head, (ws) => this.join(pid, ws))
  }

  join(pid: string, ws: WebSocket) {
    const old = this.clients.get(pid)
    if (old) {
      this.clients.delete(pid)
      old.ws.close(4000, 'replaced')
    }
    const me: Client = { ws, pid, alive: true }
    this.clients.set(pid, me)
    ws.on('pong', () => { me.alive = true })
    ws.on('close', () => this.drop(me))
    ws.on('error', () => this.drop(me))
  }

  private drop(me: Client) {
    if (this.clients.get(me.pid) === me) this.clients.delete(me.pid)
  }

  // to = 받을 사람 id들(길드 채널), null = 연결된 모두(전체 채널). 보낸 사람은 뺀다.
  publish(ch: 'all' | 'guild', row: ChatRow, to: string[] | null) {
    const sender = String(row.player_id)
    const msg = { id: Number(row.id), name: String(row.name), text: String(row.text), at: Number(row.at), me: false }
    const out = JSON.stringify({ t: 'msg', ch, msg })
    const targets = to === null ? this.clients.values() : to.map((p) => this.clients.get(p)).filter((c): c is Client => !!c)
    for (const c of targets) if (c.pid !== sender) sendRaw(c.ws, out)
  }

  sweep() {
    for (const c of [...this.clients.values()]) {
      if (!c.alive) {
        this.drop(c)
        c.ws.terminate()
      } else if (c.ws.readyState === 1) {
        c.alive = false
        c.ws.ping()
      }
    }
  }

  close() {
    clearInterval(this.beat)
    for (const c of this.clients.values()) c.ws.close()
    this.clients.clear()
    this.wss.close()
  }
}

function sendRaw(ws: WebSocket, s: string) {
  if (ws.readyState !== 1) return
  if (ws.bufferedAmount > MAX_BUFFER) ws.terminate()
  else ws.send(s)
}

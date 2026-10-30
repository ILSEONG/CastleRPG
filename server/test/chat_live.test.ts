// 채팅 실시간 전달(server/src/chat_live.ts): 진짜 소켓으로 접속(토큰 검사) → 보낸 메시지를 바로 받는다. 전체는 모두에게, 길드는 그 길드원에게만, 보낸 사람은 빼고.
// 다시 접속하면 예전 연결을 닫고, 박동에 pong이 없으면 끊는다.
import assert from 'node:assert/strict'
import { EventEmitter } from 'node:events'
import { after, before, test } from 'node:test'
import { serve } from '@hono/node-server'
import { WebSocket } from 'ws'
import { GAP_SEC } from '../src/chat.ts'
import { CHAT_LIVE_PATH, ChatLive } from '../src/chat_live.ts'
import { setup } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup()
})
after(async () => {
  await S.close()
})

function fakeWs() {
  const ws = Object.assign(new EventEmitter(), {
    readyState: 1, bufferedAmount: 0, sent: [] as any[], pings: 0, dead: false, closed: false,
    send(s: string) { ws.sent.push(JSON.parse(s)) },
    ping() { ws.pings++ },
    terminate() { ws.dead = true; ws.shut() },
    close() { ws.closed = true; ws.shut() },
    shut() { ws.readyState = 2; setImmediate(() => { ws.readyState = 3; ws.emit('close') }) },
  })
  return ws
}
const tick = () => new Promise((r) => setImmediate(r))

test('chat live: a real socket with a valid token gets new messages pushed; a bad token is refused', async () => {
  const live = new ChatLive()
  const app = S.makeApp({ chatLive: live })
  const server = serve({ fetch: app.fetch, port: 0, hostname: '127.0.0.1' })
  await new Promise((r) => server.once('listening', r))
  live.attach(server as any)
  const port = (server.address() as any).port
  try {
    const a = await S.login()
    const b = await S.login()
    const bad = new WebSocket(`ws://127.0.0.1:${port}${CHAT_LIVE_PATH}?token=nope`)
    await assert.rejects(new Promise((res, rej) => { bad.on('open', res); bad.on('error', rej) }))
    const ws = new WebSocket(`ws://127.0.0.1:${port}${CHAT_LIVE_PATH}?token=${b.token}`)
    await new Promise((res, rej) => { ws.on('open', res); ws.on('error', rej) })
    const got = new Promise<any>((res) => ws.once('message', (d) => res(JSON.parse(String(d)))))
    S.clock.t += GAP_SEC + 1
    const r = await app.request('/v1/chat', { method: 'POST', headers: { authorization: `Bearer ${a.token}`, 'content-type': 'application/json' }, body: JSON.stringify({ channel: 'all', text: '실시간' }) })
    assert.equal(r.status, 200)
    const sent = await r.json() as any
    const m = await got
    assert.deepEqual([m.t, m.ch, m.msg.id, m.msg.text, m.msg.me], ['msg', 'all', sent.msg.id, '실시간', false])
    ws.close()
  } finally {
    live.close()
    server.close()
  }
})

test('chat live: all goes to everyone but the sender, guild only to that guild', async () => {
  const live = new ChatLive()
  const app = S.makeApp({ chatLive: live })
  const say = async (token: string, channel: string, text: string) => {
    S.clock.t += GAP_SEC + 1
    const r = await app.request('/v1/chat', { method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: JSON.stringify({ channel, text }) })
    assert.equal(r.status, 200)
  }
  try {
    const [a, b, c] = [await S.login(), await S.login(), await S.login()]
    const [g] = await S.db.query("insert into guilds (name, emblem, seed, created_at, virtual_n) values ('실시간길드', 1, 9, now(), 0) returning id::text as id")
    await S.db.query('insert into player_guild (player_id, guild_id) values ($1, $3), ($2, $3)', [a.id, b.id, g.id])
    const [wa, wb, wc] = [fakeWs(), fakeWs(), fakeWs()]
    live.join(a.id, wa as any)
    live.join(b.id, wb as any)
    live.join(c.id, wc as any)
    await say(a.token, 'all', '모두 안녕')
    assert.deepEqual([wa.sent.length, wb.sent.length, wc.sent.length], [0, 1, 1])
    await say(a.token, 'guild', '길드만')
    assert.deepEqual([wa.sent.length, wb.sent.length, wc.sent.length], [0, 2, 1])
    assert.deepEqual([wb.sent[1].ch, wb.sent[1].msg.text], ['guild', '길드만'])
    // 다시 접속하면 예전 연결은 닫는다
    const wb2 = fakeWs()
    live.join(b.id, wb2 as any)
    assert.equal(wb.closed, true)
    await tick()
    assert.equal(live.clients.get(b.id)?.ws, wb2 as any)
    // 박동: pong이 없으면 다음 박동에 끊는다
    live.sweep()
    wb2.emit('pong')
    live.sweep()
    assert.deepEqual([wb2.dead, wc.dead], [false, true])
    await tick()
    assert.equal(live.clients.has(c.id), false)
  } finally {
    live.close()
  }
})

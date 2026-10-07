// 채팅(마이그레이션 032). createApp 안에서 registerChat으로 붙인다. 전달은 폴링(창이 열려 있으면 자주, 닫혀 있으면 가끔).
//  GET  /v1/chat?all=<id>&guild=<id>   각 채널에서 그 id 뒤 메시지(없으면 최근 PAGE개) → {server_now, all: [...], guild: [...] | null, guild_name}
//  POST /v1/chat {channel: 'all'|'guild', text}  보낸다 → {msg}. 거절은 400(too_fast · no_guild · empty)
// 메시지 = {id, name, text, at, me}. 이름은 다른 화면(랭킹·길드원)과 같은 G.playerName(id).
// 길드 채널은 지금 든 길드의 실제 길드원만 본다(가상 길드원은 말하지 않는다).
import type { Hono } from 'hono'
import * as G from './guild.ts'

export const MAX_LEN = 100 // 글자(코드 포인트) 수
export const GAP_SEC = 2 // 한 사람이 다음 메시지를 보낼 수 있을 때까지
export const PAGE = 50 // 한 번에 돌려주는 메시지 수
export const KEEP = 200 // 채널마다 남기는 메시지 수
export const CHANNELS = ['all', 'guild'] as const

// 간단한 욕설 가리기: 공백·기호를 끼워도 잡고, 찾은 글자는 *로 바꾼다.
const BAD = ['시발', '씨발', '씨빨', '시바ㄹ', 'ㅅㅂ', 'ㅆㅂ', '병신', 'ㅂㅅ', '븅신', '좆', '존나', '졸라', '개새끼', '개새', '새끼', '미친놈', '미친년', '닥쳐',
  '꺼져', '엠창', '느금', '니애미', '애미', '애비', 'fuck', 'shit', 'bitch', 'asshole']
const SEP = "[\\s.,_\\-~!@#$%^&*()'\"`|/\\\\]*"
const BAD_RE = new RegExp(BAD.map((w) => [...w].map((ch) => ch.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join(SEP)).join('|'), 'giu')

export function mask(text: string): string {
  return text.replace(BAD_RE, (m) => m.replace(/[^\s]/gu, '*'))
}

// 줄바꿈·제어 문자는 공백 하나로, 앞뒤 공백은 지운다. 너무 길면 MAX_LEN 글자에서 자른다.
export function clean(text: string): string {
  const t = text.replace(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]+/gu, ' ').replace(/\s+/g, ' ').trim()
  return [...t].slice(0, MAX_LEN).join('')
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Any = any

export function registerChat(app: Hono<Any>, d: Any) {
  const { query, auth, clock, body, ApiError } = d
  const bad = (code: string, msg: string) => new ApiError(400, code, msg)

  async function myGuild(id: string): Promise<{ id: string; name: string } | null> {
    const [r] = await query('select g.id::text as id, g.name from player_guild pg join guilds g on g.id = pg.guild_id where pg.player_id = $1', [id])
    return r ? { id: String(r.id), name: String(r.name) } : null
  }

  const out = (r: Any, me: string) => ({ id: Number(r.id), name: String(r.name), text: String(r.text), at: Number(r.at), me: String(r.player_id) === me })

  async function since(channel: string, after: number, me: string) {
    const rows = after > 0
      ? await query(`select id, player_id::text, name, text, extract(epoch from at)::float8 as at from chat_messages
          where channel = $1 and id > $2 order by id limit ${PAGE}`, [channel, after])
      : (await query(`select id, player_id::text, name, text, extract(epoch from at)::float8 as at from chat_messages
          where channel = $1 order by id desc limit ${PAGE}`, [channel])).reverse()
    return rows.map((r: Any) => out(r, me))
  }

  const afterOf = (v: string | undefined) => {
    const n = Number(v ?? 0)
    return Number.isSafeInteger(n) && n > 0 ? n : 0
  }

  app.get('/v1/chat', auth, async (c: Any) => {
    const id = c.get('playerId') as string
    const g = await myGuild(id)
    return c.json({
      server_now: clock(),
      all: await since('all', afterOf(c.req.query('all')), id),
      guild: g ? await since('g:' + g.id, afterOf(c.req.query('guild')), id) : null,
      guild_name: g ? g.name : '',
    })
  })

  app.post('/v1/chat', auth, async (c: Any) => {
    const id = c.get('playerId') as string
    const b = await body(c)
    const ch = b.channel
    if (ch !== 'all' && ch !== 'guild') throw new ApiError(400, 'bad_request', `'channel' must be one of ${CHANNELS.join(', ')}`)
    if (typeof b.text !== 'string') throw new ApiError(400, 'bad_request', "'text' must be a string")
    const text = mask(clean(b.text))
    if (text === '') throw bad('empty', 'message is empty')
    let channel = 'all'
    if (ch === 'guild') {
      const g = await myGuild(id)
      if (!g) throw bad('no_guild', 'not in a guild')
      channel = 'g:' + g.id
    }
    const now = clock()
    const [r] = await query(`insert into chat_messages (channel, player_id, name, text, at)
      select $1, $2, $3, $4, to_timestamp($5::float8)
      where not exists (select 1 from chat_messages where player_id = $2 and at > to_timestamp($5::float8 - ${GAP_SEC}))
      returning id, player_id::text, name, text, extract(epoch from at)::float8 as at`, [channel, id, G.playerName(id), text, now])
    if (!r) throw bad('too_fast', `wait ${GAP_SEC} s between messages`)
    await query(`delete from chat_messages where channel = $1 and id <= (select id from chat_messages where channel = $1 order by id desc offset ${KEEP} limit 1)`, [channel])
    return c.json({ server_now: now, msg: out(r, id) })
  })
}

// 채팅(마이그레이션 032). createApp 안에서 registerChat으로 붙인다. 전달은 폴링(창이 열려 있으면 자주, 닫혀 있으면 가끔).
//  GET  /v1/chat?all=<id>&guild=<id>   각 채널에서 그 id 뒤 메시지(없으면 최근 PAGE개) → {server_now, all: [...], guild: [...] | null, guild_name}
//  POST /v1/chat {channel: 'all'|'guild', text}  보낸다 → {msg}. 거절은 400(too_fast · no_guild · empty). 욕설은 profanity.ts가 가린다(원문은 raw에 남긴다)
//  POST /v1/chat/report {id}   남의 메시지 신고 → {ok, already}. 신고한 사람·신고당한 사람·그 메시지·그때 채널 앞뒤 메시지(CONTEXT개씩, 원문 포함)를 남긴다.
//       거절은 400(no_message · own_message · too_many). 같은 메시지를 다시 신고하면 already: true
//  GET  /v1/chat/reports      관리자만(admin_emails) — 최근 신고 REPORTS_PAGE개 → {reports}
// 메시지 = {id, name, text, at, me}. 이름은 다른 화면(랭킹·길드원)과 같은 G.playerName(id).
// 길드 채널은 지금 든 길드의 실제 길드원만 본다(가상 길드원은 말하지 않는다).
import type { Hono } from 'hono'
import * as G from './guild.ts'
import { mask } from './profanity.ts'

export const MAX_LEN = 100 // 글자(코드 포인트) 수
export const GAP_SEC = 2 // 한 사람이 다음 메시지를 보낼 수 있을 때까지
export const PAGE = 50 // 한 번에 돌려주는 메시지 수
export const KEEP = 200 // 채널마다 남기는 메시지 수
export const CHANNELS = ['all', 'guild'] as const
export const CONTEXT = 10 // 신고 때 남기는 앞뒤 메시지 수(각각)
export const REPORTS_PER_DAY = 20 // 한 사람이 하루(24시간)에 할 수 있는 신고 수
export const REPORTS_PAGE = 100

export { mask } from './profanity.ts'

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
    const raw = clean(b.text)
    const [r] = await query(`insert into chat_messages (channel, player_id, name, text, at, raw)
      select $1, $2, $3, $4, to_timestamp($5::float8), $6
      where not exists (select 1 from chat_messages where player_id = $2 and at > to_timestamp($5::float8 - ${GAP_SEC}))
      returning id, player_id::text, name, text, extract(epoch from at)::float8 as at`, [channel, id, G.playerName(id), text, now, raw === text ? null : raw])
    if (!r) throw bad('too_fast', `wait ${GAP_SEC} s between messages`)
    await query(`delete from chat_messages where channel = $1 and id <= (select id from chat_messages where channel = $1 order by id desc offset ${KEEP} limit 1)`, [channel])
    return c.json({ server_now: now, msg: out(r, id) })
  })

  app.post('/v1/chat/report', auth, async (c: Any) => {
    const id = c.get('playerId') as string
    const b = await body(c)
    const mid = b.id
    if (typeof mid !== 'number' || !Number.isSafeInteger(mid) || mid <= 0) throw new ApiError(400, 'bad_request', "'id' must be a positive integer")
    const [m] = await query('select id, channel, player_id::text, name, text, raw from chat_messages where id = $1', [mid])
    const g = await myGuild(id)
    if (!m || (m.channel !== 'all' && m.channel !== (g ? 'g:' + g.id : ''))) throw bad('no_message', 'message not found')
    if (String(m.player_id) === id) throw bad('own_message', 'cannot report your own message')
    const now = clock()
    const [dup] = await query('select 1 from chat_reports where reporter = $1 and message_id = $2', [id, mid])
    if (dup) return c.json({ server_now: now, ok: true, already: true })
    const [{ n }] = await query('select count(*)::int as n from chat_reports where reporter = $1 and at > to_timestamp($2::float8 - 86400)', [id, now])
    if (Number(n) >= REPORTS_PER_DAY) throw bad('too_many', `at most ${REPORTS_PER_DAY} reports a day`)
    const ctx = await query(`(select id, player_id::text, name, text, raw, extract(epoch from at)::float8 as at from chat_messages where channel = $1 and id < $2 order by id desc limit ${CONTEXT})
      union all (select id, player_id::text, name, text, raw, extract(epoch from at)::float8 as at from chat_messages where channel = $1 and id >= $2 order by id limit ${CONTEXT + 1})`, [m.channel, mid])
    const context = ctx.map((r: Any) => ({ id: Number(r.id), player_id: String(r.player_id), name: String(r.name), text: String(r.text), raw: r.raw == null ? null : String(r.raw), at: Number(r.at) }))
      .sort((a: Any, b: Any) => a.id - b.id)
    await query(`insert into chat_reports (reporter, reporter_name, target, target_name, message_id, channel, text, raw, context, at)
      values ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb, to_timestamp($10::float8)) on conflict (reporter, message_id) do nothing`,
    [id, G.playerName(id), m.player_id, String(m.name), mid, m.channel, String(m.text), m.raw == null ? null : String(m.raw), JSON.stringify(context), now])
    return c.json({ server_now: now, ok: true, already: false })
  })

  app.get('/v1/chat/reports', auth, async (c: Any) => {
    const id = c.get('playerId') as string
    const [a] = await query(`select exists (select 1 from player_identities i join admin_emails a on a.email = i.email
      where i.player_id = $1 and i.provider = 'google') as admin`, [id])
    if (!a?.admin) throw new ApiError(403, 'not_admin', 'admins only')
    const rows = await query(`select id, reporter::text, reporter_name, target::text, target_name, message_id, channel, text, raw, context, status,
      extract(epoch from at)::float8 as at from chat_reports order by id desc limit ${REPORTS_PAGE}`)
    return c.json({ server_now: clock(), reports: rows.map((r: Any) => ({ id: Number(r.id), reporter: r.reporter, reporter_name: r.reporter_name, target: r.target,
      target_name: r.target_name, message_id: Number(r.message_id), channel: r.channel === 'all' ? 'all' : 'guild', text: r.text, raw: r.raw, status: r.status, at: Number(r.at),
      context: typeof r.context === 'string' ? JSON.parse(r.context) : r.context })) })
  })
}

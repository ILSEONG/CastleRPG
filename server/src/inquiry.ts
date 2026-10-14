// 고객 문의(2026-10-14, 마이그레이션 047): 문의 이메일을 두지 않고 게임 안 [문의하기]로 받아 inquiries 표에 둔다.
// 답변은 관리자(admin_emails)가 앱의 운영 관리 창 [문의] 탭에서 쓰고, 그 답변이 그 플레이어에게 우편(보상을 붙일 수 있다)으로 간다.
//
//  GET  /v1/inquiry                         → {server_now, inquiries: [{id, category, body, status, answer, at, answered_at}]} (내 문의 새것 순)
//  POST /v1/inquiry {key, category, body, info?}  → {server_now, inquiry}. key = 앱이 보낼 때마다 만드는 값 — 같은 key면 새로 쌓지 않고
//       처음 것을 돌려준다(연타·재전송). 거절 400 bad_request · 429 too_many_inquiries(답변 대기 MAX_OPEN개 또는 하루 MAX_PER_DAY개)
// 관리자:
//  GET  /v1/admin/inquiries?filter=open|all → {server_now, open, inquiries: [{…, player, code, name}]}
//  POST /v1/admin/inquiry/answer {id, answer, reward?} 답변 + 그 플레이어에게 우편([문의 답변] 분류, 본문 = 답변). 같은 답변을 다시 보내면
//       아무것도 하지 않는다(연타). 다른 답변이면 새 우편으로 다시 답한다.
//  POST /v1/admin/inquiry/close {id, closed}  종료 / 다시 열기(답변이 있으면 answered, 없으면 open)
import type { Context, Hono, Next } from 'hono'
import * as LO from './live_ops.ts'

export const CATEGORIES: Record<string, string> = { account: '계정·로그인', payment: '결제·상점', bug: '버그·오류', suggest: '건의', other: '기타' }
export const INFO_KEYS = ['name', 'login', 'version', 'platform', 'device'] as const
export const MAX_BODY = 1000
export const MAX_ANSWER = 2000
export const MAX_OPEN = 5 // 답변 대기 중인 문의 상한(한 계정)
export const MAX_PER_DAY = 10 // 하루(24시간) 문의 상한(한 계정)
export const PAGE = 30
export const ADMIN_PAGE = 100

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Any = any

const COLS = `i.id::int as id, i.category, i.body, i.status, i.answer, extract(epoch from i.created_at)::float8 as at,
  extract(epoch from i.answered_at)::float8 as answered_at`
const row = (r: Any) => ({ id: Number(r.id), category: String(r.category), body: String(r.body), status: String(r.status), answer: String(r.answer),
  at: Number(r.at), answered_at: r.answered_at ? Number(r.answered_at) : null })

// 앱이 붙인 플레이어 정보 → 아는 키의 짧은 글만.
export function cleanInfo(raw: unknown): Record<string, string> {
  const out: Record<string, string> = {}
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return out
  for (const k of INFO_KEYS) {
    const v = (raw as Record<string, unknown>)[k]
    if (typeof v === 'string' && v.trim() !== '') out[k] = [...v.trim()].slice(0, 80).join('')
  }
  return out
}

export function registerInquiry(app: Hono<Any>, d: Any) {
  const { query, auth, clock, body, ApiError, loadGame, isAdmin } = d

  async function admin(c: Context, next: Next) {
    if (!(await isAdmin(c.get('playerId') as string))) throw new ApiError(403, 'not_admin', 'admins only')
    await next()
  }

  const text = (v: unknown, key: string, max: number): string => {
    if (typeof v !== 'string' || v.trim() === '') throw new ApiError(400, 'bad_request', `'${key}' must be a non-empty string`)
    if ([...v.trim()].length > max) throw new ApiError(400, 'bad_request', `'${key}' must be at most ${max} characters`)
    return v.trim()
  }

  app.get('/v1/inquiry', auth, async (c: Context) => {
    const rows = await query(`select ${COLS} from inquiries i where i.player_id = $1 order by i.created_at desc, i.id desc limit ${PAGE}`, [c.get('playerId')])
    return c.json({ server_now: clock(), inquiries: rows.map(row) })
  })

  app.post('/v1/inquiry', auth, async (c: Context) => {
    const b = await body(c)
    const id = c.get('playerId') as string
    const key = String(b.key ?? '')
    if (!/^[A-Za-z0-9_-]{6,40}$/.test(key)) throw new ApiError(400, 'bad_request', "'key' must be 6-40 letters, digits, - or _")
    const category = String(b.category ?? '')
    if (!(category in CATEGORIES)) throw new ApiError(400, 'bad_request', `'category' must be one of ${Object.keys(CATEGORIES).join(', ')}`)
    const msg = text(b.body, 'body', MAX_BODY)
    const now = clock()
    const old = async () => (await query(`select ${COLS} from inquiries i where i.player_id = $1 and i.client_key = $2`, [id, key]))[0]
    const seen = await old()
    if (seen) return c.json({ server_now: now, inquiry: row(seen) })
    // 상한은 넣는 문장 안에서 센다(동시에 둘이 들어와도 크게 넘지 않게). 걸리면 아무것도 넣지 않는다.
    const [r] = await query(`insert into inquiries (player_id, client_key, category, body, info, created_at)
      select $1, $2, $3, $4, $5::jsonb, to_timestamp($6::float8)
      where (select count(*) from inquiries where player_id = $1 and status = 'open') < ${MAX_OPEN}
        and (select count(*) from inquiries where player_id = $1 and created_at > to_timestamp($6::float8 - 86400)) < ${MAX_PER_DAY}
      on conflict (player_id, client_key) do nothing returning id`, [id, key, category, msg, JSON.stringify(cleanInfo(b.info)), now])
    const got = await old()
    if (!r && !got) throw new ApiError(429, 'too_many_inquiries', `at most ${MAX_OPEN} waiting or ${MAX_PER_DAY} per day`)
    return c.json({ server_now: now, inquiry: row(got) })
  })

  // --- 관리자 ---

  app.get('/v1/admin/inquiries', auth, admin, async (c: Context) => {
    const all = c.req.query('filter') === 'all'
    const rows = await query(`select ${COLS}, i.info, p.friend_code as code, i.player_id::text as player from inquiries i join players p on p.id = i.player_id
      ${all ? '' : "where i.status = 'open'"} order by ${all ? 'i.created_at desc' : 'i.created_at asc'}, i.id limit ${ADMIN_PAGE}`)
    const [n] = await query(`select count(*)::int as n from inquiries where status = 'open'`)
    return c.json({ server_now: clock(), open: Number(n.n), inquiries: rows.map((r: Any) => ({ ...row(r), player: String(r.player), code: String(r.code),
      info: typeof r.info === 'string' ? JSON.parse(r.info) : (r.info ?? {}) })) })
  })

  app.post('/v1/admin/inquiry/answer', auth, admin, async (c: Context) => {
    const b = await body(c)
    if (!Number.isInteger(b.id)) throw new ApiError(400, 'bad_request', "'id' must be an integer")
    const answer = text(b.answer, 'answer', MAX_ANSWER)
    const g = await loadGame()
    const nr = LO.normalizeReward(b.reward ?? {}, new Set(g.heroes.map((h: Any) => String(h.id))))
    if ('error' in nr) throw new ApiError(400, 'bad_reward', nr.error)
    const [q] = await query('select category, body, answer from inquiries where id = $1', [b.id])
    if (!q) throw new ApiError(404, 'unknown_inquiry', 'no such inquiry')
    const now = clock()
    const short = [...String(q.body)].slice(0, 100).join('') + ([...String(q.body)].length > 100 ? '…' : '')
    const title = `[문의 답변] ${CATEGORIES[String(q.category)] ?? '문의'}`
    const mailBody = `${answer}\n\n— 보내신 문의: ${short}`
    // 답변 + 우편을 한 문장으로. 같은 답변이 이미 있으면(연타) 아무것도 하지 않는다.
    const [r] = await query(`with t as (select id, player_id from inquiries where id = $1 and answer is distinct from $2),
        m as (insert into mails (player_id, title, body, reward, created_at, expires_at)
          select player_id, $3, $4, $5::jsonb, to_timestamp($6::float8), to_timestamp($6::float8 + ${LO.MAIL_DEFAULT_DAYS * 86400}) from t returning id)
      update inquiries i set answer = $2, status = 'answered', answered_at = to_timestamp($6::float8), mail_id = m.id from m, t where i.id = t.id
      returning i.mail_id::int as mail_id`, [b.id, answer, title, mailBody, JSON.stringify(nr.reward), now])
    return c.json({ server_now: now, id: b.id, status: 'answered', mail_id: r ? Number(r.mail_id) : null, sent: !!r })
  })

  app.post('/v1/admin/inquiry/close', auth, admin, async (c: Context) => {
    const b = await body(c)
    if (!Number.isInteger(b.id)) throw new ApiError(400, 'bad_request', "'id' must be an integer")
    const [r] = await query(`update inquiries set status = case when $2 then 'closed' when answer <> '' then 'answered' else 'open' end
      where id = $1 returning status`, [b.id, b.closed !== false])
    if (!r) throw new ApiError(404, 'unknown_inquiry', 'no such inquiry')
    return c.json({ server_now: clock(), id: b.id, status: String(r.status) })
  })
}

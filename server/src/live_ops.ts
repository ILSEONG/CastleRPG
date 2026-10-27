// 운영 도구(2026-10-12, 마이그레이션 039): 공지사항·점검·최소 버전, 우편함, 쿠폰. createApp 안에서 registerLiveOps로 붙인다.
// 만드는 쪽은 관리자(admin_emails — 슈퍼관리자 Google 계정)만, 앱의 관리자 창(admin_panel.gd)에서.
//
// 서버 상태(ops_config):
//  GET  /v1/status    로그인 없이 → {server_now, maintenance: {on, text, until}, min_version, store_url, latest_notice}
//  점검 중이면 관리자가 아닌 요청은 503 {error: 'maintenance', message, until} (gate — 로그인·상태·공지·기획 표는 열어 둔다)
//  앱이 X-App-Version을 보내고 그 값이 min_version보다 낮으면 426 {error: 'update_required', min_version, store_url}
// 공지사항:
//  GET  /v1/notices   로그인 없이 → {server_now, notices: [{id, title, body, kind, pinned, at}]} (보이는 것만, 고정 먼저, 새것 순)
// 우편함(한 사람 또는 모두에게):
//  GET  /v1/mail               → {server_now, mails: [{id, title, body, reward, at, expires}]} (아직 안 받았고 기한 전인 것, 새것 순)
//  POST /v1/mail/claim {ids}   그중 받을 수 있는 것을 한 번에 받는다 → 플레이어 응답 + {claimed: [id], reward: [보상…]}
//       하나도 없으면 409 claimed(이미 받음·기한 지남 — 재전송이 두 번 받지 않는다)
// 쿠폰:
//  POST /v1/coupon {code}      → 플레이어 응답 + {code, reward}. 거절 404 unknown_coupon · 409 coupon_used(이 계정이 이미) ·
//       coupon_expired · coupon_used_up(전체 상한) · coupon_not_started
// 관리자:
//  GET  /v1/admin/ops                         → {status, notices(숨긴 것 포함), mails(최근), coupons}
//  POST /v1/admin/status {maintenance?, maintenance_text?, maintenance_until?, min_version?, store_url?}
//  POST /v1/admin/notice {id?, title, body, kind?, pinned?, hidden?, ends_at?}   만들기(id 없음)·고치기
//  POST /v1/admin/mail {to: 'all' | 친구 코드, title, body, reward, expires_days?, new_players?}
//  POST /v1/admin/mail/delete {id}
//  POST /v1/admin/coupon {code, reward, max_uses?, expires_at?, note?}           만들기(같은 코드면 409 coupon_exists)
//  POST /v1/admin/coupon/disable {code, disabled}
// 보상(reward): gold·diamonds·tickets(다이아 모집권)·wood·stone·food·keys_gold·keys_equip·keys_ticket·pouch_<id>(방치 주머니)·
// hero(영웅 id) + hero_n(장 수, 기본 1)·equip {grade, n}(그 등급 장비 n개, 부위 무작위). 출석 보상과 같은 키(attendance.ts)에 개수를 더한 것.
import type { Context, Hono, Next } from 'hono'
import * as P from './pouches.ts'
import * as S from './speedups.ts'
import { Limiter } from './ratelimit.ts'

export const NUMERIC = ['gold', 'diamonds', 'tickets', 'wood', 'stone', 'food', 'keys_gold', 'keys_equip', 'keys_ticket'] as const
export const MAX_AMOUNT: Record<string, number> = { gold: 1e12, diamonds: 1e7, tickets: 10000, wood: 1e12, stone: 1e12, food: 1e12,
  keys_gold: 1000, keys_equip: 1000, keys_ticket: 1000 }
export const MAX_HERO_N = 1000
export const MAX_EQUIP_N = 50
export const MAX_POUCH_N = 999
export const EQUIP_GRADES = ['N', 'R', 'SR', 'SSR', 'UR', 'LR']
export const NOTICE_KINDS = ['notice', 'event', 'update', 'maintenance']
export const MAX_TITLE = 60
export const MAX_BODY = 2000
export const MAIL_PAGE = 100 // 우편함에 보이는 최대 개수
export const MAIL_DEFAULT_DAYS = 30
export const CODE_RE = /^[A-Z0-9]{4,20}$/
export const COUPON_MISSES = 10 // 한 계정이 10분에 틀릴 수 있는 쿠폰 코드 수(코드 맞히기 막기). 넘으면 429 too_many_attempts
export const VERSION_RE = /^\d+(\.\d+){0,3}$/
// 점검·업데이트 중에도 여는 경로(로그인·상태·공지·기획 표·관리자)
const OPEN_IN_MAINTENANCE = [/^\/v1\/(health|status|notices|gamedata|texts)$/, /^\/v1\/auth\//, /^\/v1\/admin\//, /^\/v1\/test\//]
const OPEN_IN_UPDATE = [/^\/v1\/(health|status|notices)$/, /^\/v1\/test\//]

export interface Reward {
  gold?: number
  diamonds?: number
  tickets?: number
  wood?: number
  stone?: number
  food?: number
  keys_gold?: number
  keys_equip?: number
  keys_ticket?: number
  hero?: string
  hero_n?: number
  equip?: { grade: string; n: number }
  [pouch: `pouch_${string}`]: number
  [speedup: `speedup_${string}`]: number
}

export interface OpsStatus {
  maintenance: boolean
  maintenance_text: string
  maintenance_until: number | null // 유닉스 초
  min_version: string
  store_url: string
}

export const DEFAULT_STATUS: OpsStatus = { maintenance: false, maintenance_text: '', maintenance_until: null, min_version: '', store_url: '' }

// "0.2.1" 비교: 숫자 칸끼리(없는 칸 = 0). a < b면 음수.
export function cmpVersion(a: string, b: string): number {
  const x = a.split('.').map(Number)
  const y = b.split('.').map(Number)
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const d = (x[i] || 0) - (y[i] || 0)
    if (d) return d
  }
  return 0
}

// 관리자가 넣은 보상 → 정리한 보상. 모르는 키·틀린 값은 오류 문자열(null = 통과).
export function normalizeReward(raw: unknown, heroIds: Set<string>): { reward: Reward } | { error: string } {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return { error: 'reward must be an object' }
  const out: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
    if ((NUMERIC as readonly string[]).includes(k)) {
      if (!Number.isInteger(v) || (v as number) < 0 || (v as number) > MAX_AMOUNT[k]) return { error: `'${k}' must be an integer in 0..${MAX_AMOUNT[k]}` }
      if (v) out[k] = v
    } else if (k.startsWith(S.REWARD_PREFIX)) {
      if (!S.IDS.includes(k.slice(S.REWARD_PREFIX.length))) return { error: `unknown speed-up '${k}'` }
      if (!Number.isInteger(v) || (v as number) < 0 || (v as number) > MAX_POUCH_N) return { error: `'${k}' must be an integer in 0..${MAX_POUCH_N}` }
      if (v) out[k] = v
    } else if (k.startsWith(P.REWARD_PREFIX)) {
      if (!P.IDS.includes(k.slice(P.REWARD_PREFIX.length))) return { error: `unknown pouch '${k}'` }
      if (!Number.isInteger(v) || (v as number) < 0 || (v as number) > MAX_POUCH_N) return { error: `'${k}' must be an integer in 0..${MAX_POUCH_N}` }
      if (v) out[k] = v
    } else if (k === 'hero') {
      if (v === '' || v === null) continue
      if (typeof v !== 'string' || !heroIds.has(v)) return { error: `unknown hero '${String(v)}'` }
      out.hero = v
    } else if (k === 'hero_n') {
      if (!Number.isInteger(v) || (v as number) < 1 || (v as number) > MAX_HERO_N) return { error: `'hero_n' must be an integer in 1..${MAX_HERO_N}` }
      out.hero_n = v
    } else if (k === 'equip') {
      if (v === null) continue
      const e = v as Record<string, unknown>
      if (!e || typeof e !== 'object' || !EQUIP_GRADES.includes(String(e.grade))) return { error: `'equip.grade' must be one of ${EQUIP_GRADES.join(', ')}` }
      const n = e.n ?? 1
      if (!Number.isInteger(n) || (n as number) < 1 || (n as number) > MAX_EQUIP_N) return { error: `'equip.n' must be an integer in 1..${MAX_EQUIP_N}` }
      out.equip = { grade: String(e.grade), n }
    } else {
      return { error: `unknown reward key '${k}'` }
    }
  }
  if (out.hero_n !== undefined && out.hero === undefined) delete out.hero_n
  if (out.hero !== undefined && out.hero_n === 1) delete out.hero_n
  return { reward: out as Reward }
}

export const isEmptyReward = (r: Reward) => Object.keys(r).length === 0

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Any = any

// 점검·최소 버전 관문(/v1/* 맨 앞에 붙인다 — 라우트보다 먼저). d.status()는 캐시된 서버 상태, d.tokenPlayer(c)는 토큰의 플레이어 id(없으면 null).
export function opsGate(d: Any) {
  return async (c: Context, next: Next) => {
    const path = c.req.path
    // health는 점검·업데이트 중에도 열려 있어 상태가 결과를 바꾸지 않는다 — DB를 읽지 않는다(Render가 몇 초마다 쳐서 Neon이 잠들지 못했다)
    if (c.req.method === 'OPTIONS' || path === '/v1/health') return next()
    const st: OpsStatus = await d.status()
    const v = c.req.header('x-app-version') ?? ''
    if (st.min_version && VERSION_RE.test(v) && cmpVersion(v, st.min_version) < 0 && !OPEN_IN_UPDATE.some((re) => re.test(path))) {
      return c.json({ error: 'update_required', message: 'please update the app', min_version: st.min_version, store_url: st.store_url }, 426)
    }
    if (st.maintenance && !OPEN_IN_MAINTENANCE.some((re) => re.test(path))) {
      const id = await d.tokenPlayer(c)
      if (!id || !(await d.isAdmin(id))) {
        return c.json({ error: 'maintenance', message: st.maintenance_text || 'server maintenance', until: st.maintenance_until }, 503)
      }
    }
    return next()
  }
}

export function registerLiveOps(app: Hono<Any>, d: Any) {
  const { query, auth, clock, body, ApiError, mutate, loadGame, rewardChange, isAdmin, status, setStatus, cacheMs } = d
  const couponMisses = new Limiter(COUPON_MISSES, 600)

  const str = (b: Record<string, unknown>, key: string, max: number, required = true): string => {
    const v = b[key]
    if (v === undefined && !required) return ''
    if (typeof v !== 'string' || (required && v.trim() === '')) throw new ApiError(400, 'bad_request', `'${key}' must be a non-empty string`)
    if ([...v].length > max) throw new ApiError(400, 'bad_request', `'${key}' must be at most ${max} characters`)
    return v.trim()
  }
  const optTime = (b: Record<string, unknown>, key: string): number | null => {
    const v = b[key]
    if (v === undefined || v === null || v === 0) return null
    if (typeof v !== 'number' || !Number.isFinite(v) || v < 0 || v > 4e9) throw new ApiError(400, 'bad_request', `'${key}' must be a unix time or null`)
    return v
  }

  async function heroIds(): Promise<Set<string>> {
    const g = await loadGame()
    return new Set(g.heroes.map((h: Any) => String(h.id)))
  }

  async function reward(raw: unknown): Promise<Reward> {
    const r = normalizeReward(raw ?? {}, await heroIds())
    if ('error' in r) throw new ApiError(400, 'bad_reward', r.error)
    return r.reward
  }

  async function admin(c: Context, next: Next) {
    if (!(await isAdmin(c.get('playerId') as string))) throw new ApiError(403, 'not_admin', 'admins only')
    await next()
  }

  // --- 상태·공지(로그인 없이) ---

  const NOTICE_COLS = `id::int as id, title, body, kind, pinned, hidden, extract(epoch from created_at)::float8 as at,
    extract(epoch from starts_at)::float8 as starts, extract(epoch from ends_at)::float8 as ends`
  const noticeRow = (r: Any) => ({ id: Number(r.id), title: String(r.title), body: String(r.body), kind: String(r.kind), pinned: r.pinned === true,
    at: Number(r.at), ...(r.hidden === true ? { hidden: true } : {}), ...(r.ends ? { ends: Number(r.ends) } : {}) })

  async function visibleNotices(now: number) {
    const rows = await query(`select ${NOTICE_COLS} from notices where not hidden and starts_at <= to_timestamp($1::float8)
      and (ends_at is null or ends_at > to_timestamp($1::float8)) order by pinned desc, created_at desc, id desc limit 30`, [now])
    return rows.map(noticeRow)
  }

  function statusView(st: OpsStatus) {
    return { maintenance: { on: st.maintenance, text: st.maintenance_text, until: st.maintenance_until }, min_version: st.min_version, store_url: st.store_url }
  }

  // 로그인 없이 자주 읽는 공지(목록·최근 id)는 서버 상태(d.status)처럼 d.cacheMs 동안 한 번 읽은 것을 같이 쓴다(운영 10초, 테스트 0 = 매번).
  // 관리자가 공지를 바꾸면 이 서버의 사본은 버린다.
  const memo = new Map<string, { at: number; v: unknown }>()
  async function cached<T>(key: string, read: () => Promise<T>): Promise<T> {
    const m = memo.get(key)
    if (cacheMs && m && Date.now() - m.at < cacheMs) return m.v as T
    const v = await read()
    memo.set(key, { at: Date.now(), v })
    return v
  }

  app.get('/v1/status', async (c: Context) => {
    const now = clock()
    const latest = await cached('latest', async () => {
      const [n] = await query(`select max(id)::int as id from notices where not hidden and starts_at <= to_timestamp($1::float8)
        and (ends_at is null or ends_at > to_timestamp($1::float8))`, [now]).catch(() => [{ id: null }])
      return n?.id ?? 0
    })
    return c.json({ server_now: now, ...statusView(await status()), latest_notice: latest })
  })

  app.get('/v1/notices', async (c: Context) => {
    const now = clock()
    return c.json({ server_now: now, notices: await cached('notices', () => visibleNotices(now)) })
  })

  // --- 우편함 ---

  // 내가 받을 수 있는 우편(아직 안 받음·기한 전·지우지 않음). 모두에게 보낸 우편은 그때 이미 있던 계정만(new_players면 나중 계정도).
  const MAIL_SQL = `select m.id::int as id, m.title, m.body, m.reward, extract(epoch from m.created_at)::float8 as at,
      extract(epoch from m.expires_at)::float8 as expires
    from mails m join players p on p.id = $1
    where not m.deleted and (m.expires_at is null or m.expires_at > to_timestamp($2::float8)) and m.created_at <= to_timestamp($2::float8)
      and (m.player_id = $1 or (m.player_id is null and (m.new_players or m.created_at >= p.created_at)))
      and not exists (select 1 from mail_claims c where c.player_id = $1 and c.mail_id = m.id)`
  const mailRow = (r: Any) => ({ id: Number(r.id), title: String(r.title), body: String(r.body),
    reward: typeof r.reward === 'string' ? JSON.parse(r.reward) : r.reward, at: Number(r.at), expires: r.expires ? Number(r.expires) : null })

  async function myMails(id: string, now: number, ids?: number[]) {
    const extra = ids ? ' and m.id = any($3::bigint[])' : ''
    const rows = await query(`${MAIL_SQL}${extra} order by m.created_at desc, m.id desc limit ${MAIL_PAGE}`, ids ? [id, now, ids] : [id, now])
    return rows.map(mailRow)
  }

  app.get('/v1/mail', auth, async (c: Context) => {
    const now = clock()
    return c.json({ server_now: now, mails: await myMails(c.get('playerId') as string, now) })
  })

  app.post('/v1/mail/claim', auth, async (c: Context) => {
    const b = await body(c)
    const ids = b.ids
    if (!Array.isArray(ids) || ids.length === 0 || ids.length > MAIL_PAGE || !ids.every((x) => Number.isInteger(x) && x > 0)) {
      throw new ApiError(400, 'bad_request', `'ids' must be 1..${MAIL_PAGE} mail ids`)
    }
    const id = c.get('playerId') as string
    return mutate(c, (p: Any, g: Any, now: number, mails: Any[]) => {
      if (!mails.length) throw new ApiError(409, 'claimed', 'no such mail to claim (already claimed or expired)')
      const rewards = mails.map((m) => m.reward as Reward)
      const { change, got } = rewardChange(p, g, now, rewards)
      change.mailClaim = mails.map((m) => m.id)
      change.log = { kind: 'mail', detail: { ids: change.mailClaim, reward: got } }
      return { change, extra: { claimed: change.mailClaim, reward: got }, reload: true }
    }, () => myMails(id, clock(), [...new Set(ids as number[])]))
  })

  // --- 쿠폰 ---

  app.post('/v1/coupon', auth, async (c: Context) => {
    const b = await body(c)
    const code = String(b.code ?? '').trim().toUpperCase().replace(/[\s-]/g, '')
    const id = c.get('playerId') as string
    // 시도마다 먼저 센다 — DB를 기다리는 동안 동시에 여러 코드를 보내도 상한을 넘지 못하게. 틀린 코드가 아니었으면(맞힌 코드·다른 거절) 되돌린다
    const at = clock()
    if (!couponMisses.take(id, at)) throw new ApiError(429, 'too_many_attempts', 'too many wrong coupon codes; try again later')
    let missed = false
    const miss = () => {
      missed = true
      return new ApiError(404, 'unknown_coupon', 'no such coupon')
    }
    try {
      if (!CODE_RE.test(code)) throw miss()
      return await mutate(c, (p: Any, g: Any, now: number, cp: Any) => {
        if (!cp || cp.disabled) throw miss()
        if (cp.used) throw new ApiError(409, 'coupon_used', 'this account already used the coupon')
        if (cp.starts > now) throw new ApiError(409, 'coupon_not_started', 'the coupon is not active yet')
        if (cp.expires && cp.expires <= now) throw new ApiError(409, 'coupon_expired', 'the coupon has expired')
        if (cp.max_uses !== null && cp.uses >= cp.max_uses) throw new ApiError(409, 'coupon_used_up', 'the coupon has been used up')
        const { change, got } = rewardChange(p, g, now, [cp.reward])
        change.coupon = { code, max_uses: cp.max_uses }
        change.log = { kind: 'coupon', detail: { code, reward: got } }
        return { change, extra: { code, reward: got }, reload: true }
      }, async () => {
        const [r] = await query(`select reward, max_uses, uses, disabled, extract(epoch from starts_at)::float8 as starts, extract(epoch from expires_at)::float8 as expires,
          exists (select 1 from coupon_uses u where u.code = c.code and u.player_id = $2) as used from coupons c where code = $1`, [code, id])
        return r ? { reward: typeof r.reward === 'string' ? JSON.parse(r.reward) : r.reward, max_uses: r.max_uses === null ? null : Number(r.max_uses),
          uses: Number(r.uses), disabled: r.disabled === true, starts: Number(r.starts), expires: r.expires ? Number(r.expires) : null, used: r.used === true } : null
      })
    } finally {
      if (!missed) couponMisses.untake(id, at)
    }
  })

  // --- 관리자 ---

  app.get('/v1/admin/ops', auth, admin, async (c: Context) => {
    const now = clock()
    const notices = (await query(`select ${NOTICE_COLS} from notices order by pinned desc, created_at desc, id desc limit 50`)).map(noticeRow)
    const mails = (await query(`select m.id::int as id, m.title, m.body, m.reward, m.new_players, m.deleted, upper(substr(replace(m.player_id::text, '-', ''), 1, 8)) as to_code,
        extract(epoch from m.created_at)::float8 as at, extract(epoch from m.expires_at)::float8 as expires,
        (select count(*)::int from mail_claims c where c.mail_id = m.id) as claims
      from mails m order by m.created_at desc, m.id desc limit 50`)).map((r: Any) => ({ ...mailRow(r), to: r.to_code ?? 'all', claims: Number(r.claims),
      new_players: r.new_players === true, deleted: r.deleted === true }))
    const coupons = (await query(`select code, reward, max_uses, uses, disabled, note, extract(epoch from expires_at)::float8 as expires,
        extract(epoch from created_at)::float8 as at from coupons order by created_at desc limit 50`)).map((r: Any) => ({ code: String(r.code),
      reward: typeof r.reward === 'string' ? JSON.parse(r.reward) : r.reward, max_uses: r.max_uses === null ? null : Number(r.max_uses), uses: Number(r.uses),
      disabled: r.disabled === true, note: String(r.note), expires: r.expires ? Number(r.expires) : null, at: Number(r.at) }))
    return c.json({ server_now: now, status: statusView(await status()), notices, mails, coupons })
  })

  app.post('/v1/admin/status', auth, admin, async (c: Context) => {
    const b = await body(c)
    const cur: OpsStatus = { ...(await status()) }
    if (b.maintenance !== undefined) {
      if (typeof b.maintenance !== 'boolean') throw new ApiError(400, 'bad_request', "'maintenance' must be a boolean")
      cur.maintenance = b.maintenance
    }
    if (b.maintenance_text !== undefined) cur.maintenance_text = str(b, 'maintenance_text', MAX_BODY, false)
    if (b.maintenance_until !== undefined) cur.maintenance_until = optTime(b, 'maintenance_until')
    if (b.min_version !== undefined) {
      const v = str(b, 'min_version', 20, false)
      if (v && !VERSION_RE.test(v)) throw new ApiError(400, 'bad_request', "'min_version' must look like 0.2.1")
      cur.min_version = v
    }
    if (b.store_url !== undefined) {
      const u = str(b, 'store_url', 300, false)
      if (u && !/^https:\/\/\S+$/.test(u)) throw new ApiError(400, 'bad_request', "'store_url' must be an https URL")
      cur.store_url = u
    }
    await setStatus(cur)
    return c.json({ server_now: clock(), status: statusView(cur) })
  })

  app.post('/v1/admin/notice', auth, admin, async (c: Context) => {
    const b = await body(c)
    const title = str(b, 'title', MAX_TITLE)
    const text = str(b, 'body', MAX_BODY, false)
    const kind = b.kind === undefined ? 'notice' : String(b.kind)
    if (!NOTICE_KINDS.includes(kind)) throw new ApiError(400, 'bad_request', `'kind' must be one of ${NOTICE_KINDS.join(', ')}`)
    const pinned = b.pinned === true
    const hidden = b.hidden === true
    const ends = optTime(b, 'ends_at')
    const now = clock()
    let id: number
    if (b.id !== undefined) {
      if (!Number.isInteger(b.id)) throw new ApiError(400, 'bad_request', "'id' must be an integer")
      const [r] = await query(`update notices set title = $2, body = $3, kind = $4, pinned = $5, hidden = $6, ends_at = to_timestamp($7::float8)
        where id = $1 returning id::int as id`, [b.id, title, text, kind, pinned, hidden, ends])
      if (!r) throw new ApiError(404, 'unknown_notice', 'no such notice')
      id = Number(r.id)
    } else {
      const [r] = await query(`insert into notices (title, body, kind, pinned, hidden, created_at, starts_at, ends_at)
        values ($1, $2, $3, $4, $5, to_timestamp($6::float8), to_timestamp($6::float8), to_timestamp($7::float8)) returning id::int as id`, [title, text, kind, pinned, hidden, now, ends])
      id = Number(r.id)
    }
    memo.clear()
    return c.json({ server_now: now, id })
  })

  app.post('/v1/admin/mail', auth, admin, async (c: Context) => {
    const b = await body(c)
    const title = str(b, 'title', MAX_TITLE)
    const text = str(b, 'body', MAX_BODY, false)
    const r = await reward(b.reward)
    const to = String(b.to ?? '').trim().toUpperCase()
    const days = b.expires_days === undefined ? MAIL_DEFAULT_DAYS : b.expires_days
    if (!Number.isInteger(days) || (days as number) < 0 || (days as number) > 3650) throw new ApiError(400, 'bad_request', "'expires_days' must be an integer in 0..3650 (0 = never)")
    let target: string | null = null
    if (to !== 'ALL') {
      if (!/^[0-9A-F]{8}$/.test(to)) throw new ApiError(400, 'bad_request', "'to' must be 'all' or a friend code")
      const [p] = await query('select id from players where friend_code = $1', [to])
      if (!p) throw new ApiError(404, 'unknown_player', `no player with friend code ${to}`)
      target = String(p.id)
    }
    const now = clock()
    const [m] = await query(`insert into mails (player_id, title, body, reward, new_players, created_at, expires_at)
      values ($1::uuid, $2, $3, $4::jsonb, $5, to_timestamp($6::float8), to_timestamp($7::float8)) returning id::int as id`,
    [target, title, text, JSON.stringify(r), b.new_players === true && target === null, now, days ? now + (days as number) * 86400 : null])
    return c.json({ server_now: now, id: Number(m.id), to: target === null ? 'all' : to })
  })

  app.post('/v1/admin/mail/delete', auth, admin, async (c: Context) => {
    const b = await body(c)
    if (!Number.isInteger(b.id)) throw new ApiError(400, 'bad_request', "'id' must be an integer")
    const [r] = await query('update mails set deleted = true where id = $1 returning id', [b.id])
    if (!r) throw new ApiError(404, 'unknown_mail', 'no such mail')
    return c.json({ server_now: clock(), ok: true })
  })

  app.post('/v1/admin/coupon', auth, admin, async (c: Context) => {
    const b = await body(c)
    const code = String(b.code ?? '').trim().toUpperCase()
    if (!CODE_RE.test(code)) throw new ApiError(400, 'bad_request', "'code' must be 4-20 letters A-Z or digits")
    const r = await reward(b.reward)
    if (isEmptyReward(r)) throw new ApiError(400, 'bad_reward', 'a coupon needs a reward')
    const max = b.max_uses === undefined || b.max_uses === null || b.max_uses === 0 ? null : b.max_uses
    if (max !== null && (!Number.isInteger(max) || (max as number) < 1 || (max as number) > 10_000_000)) throw new ApiError(400, 'bad_request', "'max_uses' must be 1..10000000 or null")
    const note = str(b, 'note', 100, false)
    const now = clock()
    const [row] = await query(`insert into coupons (code, reward, max_uses, created_at, starts_at, expires_at, note)
      values ($1, $2::jsonb, $3::int, to_timestamp($4::float8), to_timestamp($4::float8), to_timestamp($5::float8), $6) on conflict (code) do nothing returning code`,
    [code, JSON.stringify(r), max, now, optTime(b, 'expires_at'), note])
    if (!row) throw new ApiError(409, 'coupon_exists', `coupon ${code} already exists`)
    return c.json({ server_now: now, code })
  })

  app.post('/v1/admin/coupon/disable', auth, admin, async (c: Context) => {
    const b = await body(c)
    const code = String(b.code ?? '').trim().toUpperCase()
    const [r] = await query('update coupons set disabled = $2 where code = $1 returning code', [code, b.disabled !== false])
    if (!r) throw new ApiError(404, 'unknown_coupon', 'no such coupon')
    return c.json({ server_now: clock(), ok: true })
  })
}

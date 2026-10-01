// Hono 앱 팩토리. 시계(now)·쿼리 함수를 주입받아 테스트에서 포트 없이 app.request()로 돌린다.
import { createHash } from 'node:crypto'
import { Hono } from 'hono'
import type { Context, Next } from 'hono'
import { bodyLimit } from 'hono/body-limit'
import { cors } from 'hono/cors'
import { sign, verify } from 'hono/jwt'
import type { Query } from './db.ts'
import { TABLES } from './seed.ts'
import * as R from './rules.ts'

export interface AppOptions {
  query: Query
  now?: () => number // 유닉스 초(float)
  jwtSecret: string
  allowTestHooks?: boolean
  corsOrigins?: string[] // 비면 *
}

const TOKEN_TTL = 30 * 86400
const MAX_ATTEMPTS = 4 // 첫 시도 + 충돌 시 재시도 3회
const MAX_BODY = 16 * 1024
const MAX_STAGE = 1_000_000
const MAX_KILL_COUNT = 10_000 // 몬스터 한 종류의 한 번 보고 수
const MAX_INT4 = 2_147_483_647
const MAX_AGE_MIN = 100_000
const DEVICE_RE = /^[A-Za-z0-9-]{16,128}$/
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export class ApiError extends Error {
  status: number
  code: string
  constructor(status: number, code: string, message: string) {
    super(message)
    this.status = status
    this.code = code
  }
}

interface Game {
  monsters: Record<string, any>[]
  stages: R.StageRow[]
  heroes: Record<string, any>[]
  resources: { id: string; name: string; building: string; per_min: number; price: number }[]
  config: R.Config
}

interface Player {
  gold_tenths: number
  stage: number
  keep_level: number
  gate_level: number
  version: number
  last_kill_report: number
  last_stage_clear: number
  kill_seq: number
  res: Record<string, number>
  buildings: Record<string, { level: number; last_collect: number }>
}

// 한 번의 원자적 변경. version이 읽은 값과 같을 때만 전부 적용된다.
interface Change {
  goldTenths?: number // 더할 골드(0.1 단위 정수)
  stage?: number // 새 스테이지
  lastKillReport?: number // 새 처치 보고 시각
  lastStageClear?: number // 새 스테이지 클리어 시각
  killSeq?: number // 새 처치 보고 번호
  res?: Record<string, number> // 자원 증감
  buildings?: Record<string, number> // 건물 → 새 last_collect
  log?: { kind: string; detail: unknown }
}

// 기획 표 전부를 한 쿼리로. 행 키 = CSV 열 이름(열 순서 그대로), 행 순서 = 파일 순서.
const GAME_SQL = 'select ' + TABLES.map((t) => {
  const cols = Object.keys(t.sql)
  if (t.name === 'config') return `(select coalesce(json_object_agg(key, value order by key), '{}'::json) from ${t.table}) as config`
  const obj = `json_build_object(${cols.map((c) => `'${c}', ${c}`).join(', ')})`
  const order = t.ordered ? `ord, ${cols[0]}` : cols[0]
  return `(select coalesce(json_agg(${obj} order by ${order}), '[]'::json) from ${t.table}) as ${t.name}`
}).join(',\n  ')

const PLAYER_SQL = `select s.gold_tenths, s.stage, s.keep_level, s.gate_level, s.version, s.kill_seq,
  extract(epoch from s.last_kill_report)::float8 as last_kill_report,
  extract(epoch from s.last_stage_clear)::float8 as last_stage_clear,
  coalesce((select json_object_agg(res, amount) from player_resources where player_id = s.player_id), '{}'::json) as res,
  coalesce((select json_object_agg(building, json_build_object('level', level, 'last_collect', extract(epoch from last_collect)::float8))
    from player_buildings where player_id = s.player_id), '{}'::json) as buildings
  from player_state s where s.player_id = $1`

// 플레이어를 찾거나 만들고(last_seen 갱신), 빠진 상태·자원·건물 행을 채운다 — 한 문장이라 중간에 끊겨도 반쪽 계정이 없다.
const ENSURE_SQL = `with p as (
    insert into players (device_id, created_at, last_seen) values ($1, to_timestamp($2::float8), to_timestamp($2::float8))
    on conflict (device_id) do update set last_seen = excluded.last_seen returning id),
  s as (insert into player_state (player_id, last_kill_report, last_stage_clear)
    select id, to_timestamp($2::float8), to_timestamp($2::float8) from p on conflict do nothing),
  r as (insert into player_resources (player_id, res) select p.id, resources.id from p, resources on conflict do nothing),
  b as (insert into player_buildings (player_id, building, last_collect) select p.id, resources.building, to_timestamp($2::float8)
    from p, resources on conflict do nothing)
  select id from p`

const ENSURE_ROWS_SQL = `with p as (select $1::uuid as id),
  r as (insert into player_resources (player_id, res) select p.id, resources.id from p, resources on conflict do nothing),
  b as (insert into player_buildings (player_id, building, last_collect) select p.id, resources.building, to_timestamp($2::float8)
    from p, resources on conflict do nothing)
  select 1`

const json = (v: unknown) => (typeof v === 'string' ? JSON.parse(v) : v)
// bigint 파라미터는 정수 문자열로 — Neon은 숫자를 toString()으로 보내 1e21부터 지수 표기가 되고 ::bigint가 거부한다. 정수가 아니면 throw.
const bigint = (v: number) => BigInt(v).toString()

export function createApp(opts: AppOptions) {
  const query = opts.query
  const clock = opts.now ?? (() => Date.now() / 1000)
  const secret = opts.jwtSecret
  const app = new Hono()

  app.use('*', cors({
    origin: opts.corsOrigins?.length ? opts.corsOrigins : '*',
    allowMethods: ['GET', 'POST', 'OPTIONS'],
    allowHeaders: ['Authorization', 'Content-Type', 'If-None-Match'],
    exposeHeaders: ['ETag'],
    maxAge: 600,
  }))

  // 본문은 다 읽기 전에 크기로 끊는다(Content-Length가 있으면 그것으로, 없으면 읽으면서 센다).
  app.use('/v1/*', bodyLimit({
    maxSize: MAX_BODY,
    onError: (c) => c.json({ error: 'payload_too_large', message: `request body must be at most ${MAX_BODY} bytes` }, 413),
  }))

  app.onError((err, c) => {
    if (err instanceof ApiError) return c.json({ error: err.code, message: err.message }, err.status as any)
    console.error('[server] unhandled error:', err)
    return c.json({ error: 'internal', message: 'internal server error' }, 500)
  })
  app.notFound((c) => c.json({ error: 'not_found', message: `no such endpoint: ${c.req.method} ${c.req.path}` }, 404))

  // --- 읽기 ---

  async function loadGame(): Promise<Game> {
    const [r] = await query(GAME_SQL)
    return {
      monsters: json(r.monsters), stages: json(r.stages), heroes: json(r.heroes),
      resources: json(r.resources), config: json(r.config),
    }
  }

  async function loadPlayer(id: string, game: Game, now: number): Promise<Player> {
    for (let i = 0; i < 2; i++) {
      const [r] = await query(PLAYER_SQL, [id])
      if (!r) throw new ApiError(401, 'unknown_player', 'player not found; log in again')
      const res: Record<string, number> = {}
      for (const [k, v] of Object.entries(json(r.res) as Record<string, unknown>)) res[k] = Number(v)
      const buildings: Player['buildings'] = {}
      for (const [k, v] of Object.entries(json(r.buildings) as Record<string, any>)) buildings[k] = { level: Number(v.level), last_collect: Number(v.last_collect) }
      const missing = game.resources.some((x) => !(x.id in res) || !(x.building in buildings))
      if (missing && i === 0) {
        await query(ENSURE_ROWS_SQL, [id, now]) // 나중에 추가된 자원 — 행을 채우고 다시 읽는다
        continue
      }
      return {
        gold_tenths: Number(r.gold_tenths), stage: Number(r.stage), keep_level: Number(r.keep_level), gate_level: Number(r.gate_level),
        version: Number(r.version), last_kill_report: Number(r.last_kill_report), last_stage_clear: Number(r.last_stage_clear),
        kill_seq: Number(r.kill_seq), res, buildings,
      }
    }
    throw new ApiError(500, 'internal', 'player rows missing')
  }

  // 플레이어 응답(스펙 §4 공통).
  function view(p: Player, game: Game, now: number) {
    const res: Record<string, number> = {}
    const buildings: Record<string, { level: number; last_collect: number }> = {}
    for (const r of game.resources) {
      res[r.id] = p.res[r.id] ?? 0
      const b = p.buildings[r.building]
      buildings[r.building] = { level: b?.level ?? 1, last_collect: b?.last_collect ?? now }
    }
    return {
      server_now: now,
      player: { gold_tenths: p.gold_tenths, gold: Math.floor(p.gold_tenths / 10), res, stage: p.stage, keep_level: p.keep_level, gate_level: p.gate_level, kill_seq: p.kill_seq, buildings },
      merchant: { rate: R.merchantRate(R.hourIndex(now), game.config), next_change: R.nextChange(now) },
    }
  }

  // --- 쓰기: version 낙관적 잠금 + 한 문장(CTE) ---

  async function commit(playerId: string, version: number, ch: Change, now: number): Promise<boolean> {
    const params: unknown[] = [playerId, version]
    const p = (v: unknown) => {
      params.push(v)
      return `$${params.length}`
    }
    const sets = ['version = version + 1']
    if (ch.goldTenths) sets.push(`gold_tenths = gold_tenths + ${p(bigint(ch.goldTenths))}::bigint`)
    if (ch.stage !== undefined) sets.push(`stage = ${p(ch.stage)}::int`)
    if (ch.lastKillReport !== undefined) sets.push(`last_kill_report = to_timestamp(${p(ch.lastKillReport)}::float8)`)
    if (ch.lastStageClear !== undefined) sets.push(`last_stage_clear = to_timestamp(${p(ch.lastStageClear)}::float8)`)
    if (ch.killSeq !== undefined) sets.push(`kill_seq = ${p(ch.killSeq)}::int`)
    const ctes = [`s as (update player_state set ${sets.join(', ')} where player_id = $1 and version = $2 returning player_id)`]
    Object.entries(ch.res ?? {}).forEach(([res, d], i) => {
      ctes.push(`r${i} as (update player_resources set amount = amount + ${p(bigint(d))}::bigint
        where player_id = (select player_id from s) and res = ${p(res)} returning 1)`)
    })
    Object.entries(ch.buildings ?? {}).forEach(([b, t], i) => {
      ctes.push(`b${i} as (update player_buildings set last_collect = to_timestamp(${p(t)}::float8)
        where player_id = (select player_id from s) and building = ${p(b)} returning 1)`)
    })
    if (ch.log) {
      ctes.push(`l as (insert into economy_log (player_id, kind, detail, at)
        select player_id, ${p(ch.log.kind)}, ${p(JSON.stringify(ch.log.detail))}::jsonb, to_timestamp(${p(now)}::float8) from s returning 1)`)
    }
    const [r] = await query(`with ${ctes.join(',\n')} select count(*)::int as n from s`, params)
    return Number(r.n) === 1
  }

  function applyLocal(pl: Player, ch: Change) {
    pl.gold_tenths += ch.goldTenths ?? 0
    if (ch.stage !== undefined) pl.stage = ch.stage
    if (ch.lastKillReport !== undefined) pl.last_kill_report = ch.lastKillReport
    if (ch.lastStageClear !== undefined) pl.last_stage_clear = ch.lastStageClear
    if (ch.killSeq !== undefined) pl.kill_seq = ch.killSeq
    for (const [k, d] of Object.entries(ch.res ?? {})) pl.res[k] = (pl.res[k] ?? 0) + d
    for (const [k, t] of Object.entries(ch.buildings ?? {})) pl.buildings[k].last_collect = t
    pl.version += 1
  }

  type Plan = { change?: Change; extra?: Record<string, unknown> }

  // 읽기 → 계산 → 조건부 쓰기. 다른 요청이 먼저 바꿨으면(version 불일치) 다시 읽고 다시 계산한다.
  async function mutate(c: Context, plan: (p: Player, game: Game, now: number) => Plan) {
    const id = c.get('playerId') as string
    for (let i = 0; i < MAX_ATTEMPTS; i++) {
      const now = clock()
      const game = await loadGame()
      const pl = await loadPlayer(id, game, now)
      const { change, extra } = plan(pl, game, now)
      if (change && !(await commit(id, pl.version, change, now))) continue
      if (change) applyLocal(pl, change)
      return c.json({ ...view(pl, game, now), ...extra })
    }
    throw new ApiError(409, 'conflict', 'concurrent update; try again')
  }

  // --- 입력 ---

  async function body(c: Context): Promise<Record<string, unknown>> {
    let b: unknown
    try {
      b = await c.req.json()
    } catch {
      throw new ApiError(400, 'bad_json', 'request body must be JSON')
    }
    if (!b || typeof b !== 'object' || Array.isArray(b)) throw new ApiError(400, 'bad_request', 'request body must be a JSON object')
    return b as Record<string, unknown>
  }

  const isInt = (v: unknown, min: number, max: number): v is number => typeof v === 'number' && Number.isInteger(v) && v >= min && v <= max
  const intField = (b: Record<string, unknown>, key: string, min: number, max: number) => {
    const v = b[key]
    if (!isInt(v, min, max)) throw new ApiError(400, 'bad_request', `'${key}' must be an integer in ${min}..${max}`)
    return v
  }
  const strField = (b: Record<string, unknown>, key: string) => {
    const v = b[key]
    if (typeof v !== 'string' || v === '') throw new ApiError(400, 'bad_request', `'${key}' must be a non-empty string`)
    return v
  }

  // Authorization: Bearer <JWT>. 서명은 hono/jwt, 만료는 주입 시계로 확인한다.
  async function auth(c: Context, next: Next) {
    const h = c.req.header('authorization') ?? ''
    const m = /^Bearer\s+(\S+)$/i.exec(h)
    if (!m) throw new ApiError(401, 'no_token', 'missing bearer token')
    let payload: Record<string, unknown>
    try {
      payload = await verify(m[1], secret, { alg: 'HS256', exp: false, iat: false, nbf: false })
    } catch {
      throw new ApiError(401, 'bad_token', 'invalid token')
    }
    if (typeof payload.exp !== 'number' || payload.exp <= clock()) throw new ApiError(401, 'token_expired', 'token expired')
    if (typeof payload.sub !== 'string' || !UUID_RE.test(payload.sub)) throw new ApiError(401, 'bad_token', 'invalid token subject')
    c.set('playerId', payload.sub)
    await next()
  }

  // --- 엔드포인트 ---

  app.get('/v1/health', (c) => c.json({ ok: true, server_now: clock() }))

  app.post('/v1/auth/guest', async (c) => {
    const b = await body(c)
    const device = b.device_id
    if (typeof device !== 'string' || !DEVICE_RE.test(device)) {
      throw new ApiError(400, 'bad_device_id', 'device_id must be 16-128 characters of [A-Za-z0-9-]')
    }
    const now = clock()
    const [r] = await query(ENSURE_SQL, [device, now])
    const iat = Math.floor(now)
    const token = await sign({ sub: r.id, iat, exp: iat + TOKEN_TTL }, secret, 'HS256')
    return c.json({ token, player_id: r.id })
  })

  app.get('/v1/gamedata', async (c) => {
    const g = await loadGame()
    const data = { monsters: g.monsters, stages: g.stages, heroes: g.heroes, resources: g.resources, config: g.config }
    const version = createHash('sha256').update(JSON.stringify(data)).digest('hex').slice(0, 16)
    const etag = `"${version}"`
    c.header('ETag', etag)
    c.header('Cache-Control', 'no-cache')
    if (c.req.header('if-none-match') === etag) return c.body(null, 304)
    return c.json({ version, ...data })
  })

  app.get('/v1/player', auth, async (c) => {
    const now = clock()
    const game = await loadGame()
    return c.json(view(await loadPlayer(c.get('playerId') as string, game, now), game, now))
  })

  app.post('/v1/collect', auth, async (c) => {
    const building = strField(await body(c), 'building')
    return mutate(c, (p, g, now) => {
      const r = g.resources.find((x) => x.building === building)
      if (!r) throw new ApiError(400, 'not_resource_building', `'${building}' is not a resource building`)
      const b = p.buildings[building]
      const st = R.collectStep(b.last_collect, now, r.per_min, b.level, R.cfgNum(g.config, 'accum_cap_min'))
      if (!st.changed) return { extra: { amount: 0 } }
      return {
        change: {
          res: st.amount ? { [r.id]: st.amount } : {},
          buildings: { [building]: st.lastCollect },
          log: { kind: 'collect', detail: { building, res: r.id, amount: st.amount, level: b.level, from: b.last_collect, to: st.lastCollect } },
        },
        extra: { amount: st.amount },
      }
    })
  })

  app.post('/v1/sell', auth, async (c) => {
    const target = strField(await body(c), 'res')
    return mutate(c, (p, g, now) => {
      const list = target === 'all' ? g.resources : g.resources.filter((x) => x.id === target)
      if (list.length === 0) throw new ApiError(400, 'unknown_resource', `unknown resource '${target}'`)
      const rate = R.merchantRate(R.hourIndex(now), g.config)
      let gold = 0
      const sold: Record<string, number> = {}
      const delta: Record<string, number> = {}
      for (const r of list) {
        const amount = p.res[r.id] ?? 0
        if (amount <= 0) continue
        gold += R.sellValue(amount, r.price, rate)
        sold[r.id] = amount
        delta[r.id] = -amount
      }
      if (Object.keys(sold).length === 0) return { extra: { gold_gained: 0, rate } }
      return { change: { goldTenths: gold * 10, res: delta, log: { kind: 'sell', detail: { res: target, sold, rate, gold, gold_tenths: gold * 10 } } }, extra: { gold_gained: gold, rate } }
    })
  })

  app.post('/v1/kills', auth, async (c) => {
    const b = await body(c)
    const seq = intField(b, 'seq', 0, MAX_INT4)
    const askedStage = intField(b, 'stage', 1, MAX_STAGE)
    const kills = b.kills
    if (!kills || typeof kills !== 'object' || Array.isArray(kills)) throw new ApiError(400, 'bad_request', "'kills' must be an object of monster id -> count")
    const entries = Object.entries(kills as Record<string, unknown>)
    for (const [id, n] of entries) {
      if (!isInt(n, 0, MAX_KILL_COUNT)) throw new ApiError(400, 'bad_request', `kill count for '${id}' must be an integer in 0..${MAX_KILL_COUNT}`)
    }
    return mutate(c, (p, g, now) => {
      const monsters = new Map(g.monsters.map((m) => [m.id, m]))
      for (const [id] of entries) if (!monsters.has(id)) throw new ApiError(400, 'unknown_monster', `unknown monster '${id}'`)
      // 재전송(응답 유실 후 다시 보냄)·순서 뒤바뀜: 이미 반영한 번호면 아무것도 안 한다.
      if (seq <= p.kill_seq) return { extra: { gold_gained_tenths: 0 } }
      const stage = Math.min(askedStage, p.stage)
      const row = R.stageRow(stage, g.stages)
      const bucket = R.killBucket(p.last_kill_report, now, R.cfgNum(g.config, 'kill_rate_cap'), R.cfgNum(g.config, 'kill_burst_sec'))
      const priced = entries.map(([id, n]) => ({ id, count: n as number, gold: R.killGoldTenths(Number(monsters.get(id).gold), row) }))
      const { kept, clamped } = R.clampKills(priced, bucket.cap)
      const tenths = priced.reduce((s, k) => s + kept[k.id] * k.gold, 0) // k.gold = 처치 1회 tenths
      const total = priced.reduce((s, k) => s + k.count, 0)
      const keptTotal = priced.reduce((s, k) => s + kept[k.id], 0)
      const log = total > 0 ? { kind: 'kills', detail: { seq, stage, asked_stage: askedStage, kills, kept, cap: bucket.cap, clamped, gold_tenths: tenths } } : undefined
      return { change: { goldTenths: tenths, lastKillReport: bucket.after(keptTotal), killSeq: seq, log }, extra: { gold_gained_tenths: tenths } }
    })
  })

  app.post('/v1/stage/clear', auth, async (c) => {
    const stage = intField(await body(c), 'stage', 1, MAX_STAGE)
    return mutate(c, (p, g, now) => {
      if (stage !== p.stage) return { extra: { cleared: false } } // 중복·재전송·앞지름: 변화 없음
      // 지난 클리어(새 계정이면 가입) 이후 최소 시간보다 빠르면 받지 않는다 — 스크립트로 스테이지를 올려 처치 골드를 키우지 못한다.
      const sec = now - p.last_stage_clear
      if (sec < R.minClearSec(R.stageRow(stage, g.stages), R.cfgNum(g.config, 'kill_rate_cap'))) return { extra: { cleared: false } }
      return { change: { stage: stage + 1, lastStageClear: now, log: { kind: 'stage_clear', detail: { stage, sec } } }, extra: { cleared: true } }
    })
  })

  if (opts.allowTestHooks) {
    // 통합 테스트용: 그 플레이어 건물의 last_collect를 minutes분 앞당긴다.
    app.post('/v1/test/age', auth, async (c) => {
      const minutes = intField(await body(c), 'minutes', 0, MAX_AGE_MIN)
      const id = c.get('playerId') as string
      await query(`with s as (update player_state set version = version + 1 where player_id = $1 returning player_id)
        update player_buildings set last_collect = last_collect - $2::float8 * interval '1 second'
        where player_id = (select player_id from s)`, [id, minutes * 60])
      const now = clock()
      const game = await loadGame()
      return c.json(view(await loadPlayer(id, game, now), game, now))
    })
  }

  return app
}

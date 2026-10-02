// Hono 앱 팩토리. 시계(now)·쿼리 함수를 주입받아 테스트에서 포트 없이 app.request()로 돌린다.
import { createHash } from 'node:crypto'
import { Hono } from 'hono'
import type { Context, Next } from 'hono'
import { bodyLimit } from 'hono/body-limit'
import { cors } from 'hono/cors'
import { sign, verify } from 'hono/jwt'
import type { Query } from './db.ts'
import { DEFAULT_STARTERS, ident, TABLES } from './seed.ts'
import * as R from './rules.ts'

export interface AppOptions {
  query: Query
  now?: () => number // 유닉스 초(float)
  jwtSecret: string
  allowTestHooks?: boolean
  corsOrigins?: string[] // 비면 *
  random?: () => number // [0, 1) 난수(모집). 기본은 암호학적 난수(R.cryptoRandom) — 테스트만 주입한다
}

const TOKEN_TTL = 30 * 86400
const MAX_ATTEMPTS = 4 // 첫 시도 + 충돌 시 재시도 3회
const MAX_BODY = 16 * 1024
const MAX_STAGE = 1_000_000
const MAX_KILL_COUNT = 10_000 // 몬스터 한 종류의 한 번 보고 수
const MAX_INT4 = 2_147_483_647
const MAX_AGE_MIN = 100_000
const MAX_LEVELUP_COUNT = 100
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
  buildings: R.BuildingDef[] // 개정 12 건물 표(파일 순서)
  soldiers: R.SoldierDef[] // 개정 13 병종 표(파일 순서)
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
  heroes: Record<string, Hero> // 영웅 id → 보유 수·레벨·조각·승급(개정 15)
  deploy: unknown[] // 저장된 그대로(응답에서 슬롯 수·보유로 맞춘다)
  build: { id: string; finish: number } | null // 일꾼(개정 12): 짓는 건물과 끝나는 시각(유닉스 초), 쉬면 null
  soldiers: Record<string, number> // 개정 13: "병종:티어" → 보유 수(0 초과만)
  soldier_deploy: Record<string, number> // "병종:티어" → 배치 수(저장된 그대로 — 응답에서 보유로 자른다)
}

interface Hero {
  copies: number
  level: number
  shards: number // 개정 15: 승급에 쓰는 조각
  promotion: number // 0..R.MAX_PROMOTION
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
  heroes?: Record<string, number> // 영웅 → copies 증가(모집). 새 행은 조각 = 증가 − 1, 있던 행은 조각 += 증가(개정 15)
  heroLevels?: Record<string, number> // 영웅 → 레벨 증가
  promote?: { id: string; cost: number } // 승급(개정 15): 조각 −cost, 승급 +1
  deploy?: (string | null)[] // 새 배치
  build?: { id: string; finish: number } | null // 새 일꾼 상태(개정 12)
  soldiers?: Record<string, number> // "병종:티어" → 보유 증감(개정 13)
  soldierDeploy?: Record<string, number> // 새 병사 배치
  log?: { kind: string; detail: unknown }
}

// 기획 표 전부를 한 쿼리로. 행 키 = CSV 열 이름(열 순서 그대로), 행 순서 = 파일 순서.
const GAME_SQL = 'select ' + TABLES.map((t) => {
  const cols = Object.keys(t.sql)
  if (t.name === 'config') return `(select coalesce(json_object_agg(key, value order by key), '{}'::json) from ${t.table}) as config`
  const obj = `json_build_object(${cols.map((c) => `'${c}', ${ident(c)}`).join(', ')})`
  const order = t.ordered ? `ord, ${cols[0]}` : cols[0]
  return `(select coalesce(json_agg(${obj} order by ${order}), '[]'::json) from ${t.table}) as ${t.name}`
}).join(',\n  ')

const PLAYER_SQL = `select s.gold_tenths, s.stage, s.keep_level, s.gate_level, s.version, s.kill_seq, s.deploy, s.build_id, s.soldier_deploy,
  coalesce((select json_object_agg(type || ':' || tier, count) from player_soldiers where player_id = s.player_id and count > 0), '{}'::json) as soldiers,
  extract(epoch from s.build_finish)::float8 as build_finish,
  extract(epoch from s.last_kill_report)::float8 as last_kill_report,
  extract(epoch from s.last_stage_clear)::float8 as last_stage_clear,
  coalesce((select json_object_agg(res, amount) from player_resources where player_id = s.player_id), '{}'::json) as res,
  coalesce((select json_object_agg(building, json_build_object('level', level, 'last_collect', extract(epoch from last_collect)::float8))
    from player_buildings where player_id = s.player_id), '{}'::json) as buildings,
  coalesce((select json_object_agg(hero_id, json_build_object('copies', copies, 'level', level, 'shards', shards, 'promotion', promotion))
    from player_heroes where player_id = s.player_id), '{}'::json) as heroes
  from player_state s where s.player_id = $1`

// 플레이어를 찾거나 만들고(last_seen 갱신), 빠진 상태·자원·건물 행을 채운다 — 한 문장이라 중간에 끊겨도 반쪽 계정이 없다.
// 새 상태 행이면 시작 영웅($3, JSON 배열)을 copies 1로 주고 그 순서로 배치한다.
const ENSURE_SQL = `with p as (
    insert into players (device_id, created_at, last_seen) values ($1, to_timestamp($2::float8), to_timestamp($2::float8))
    on conflict (device_id) do update set last_seen = excluded.last_seen returning id),
  s as (insert into player_state (player_id, last_kill_report, last_stage_clear, deploy)
    select id, to_timestamp($2::float8), to_timestamp($2::float8), $3::jsonb from p on conflict do nothing returning player_id),
  h as (insert into player_heroes (player_id, hero_id) select s.player_id, x from s, jsonb_array_elements_text($3::jsonb) as x
    on conflict do nothing),
  r as (insert into player_resources (player_id, res) select p.id, resources.id from p, resources on conflict do nothing),
  b as (insert into player_buildings (player_id, building, last_collect) select p.id, x.id, to_timestamp($2::float8)
    from p, (select building as id from resources union select id from building_defs) as x on conflict do nothing)
  select id from p`

// 빠진 행(나중에 추가된 자원·건물)을 채운다. 건물은 레벨 1, 성채·성문은 player_state의 레벨(개정 12).
const ENSURE_ROWS_SQL = `with p as (select $1::uuid as id),
  r as (insert into player_resources (player_id, res) select p.id, resources.id from p, resources on conflict do nothing),
  b as (insert into player_buildings (player_id, building, level, last_collect)
    select s.player_id, x.id, case x.id when $3 then s.keep_level when $4 then s.gate_level else 1 end, to_timestamp($2::float8)
    from player_state s, (select building as id from resources union select id from building_defs) as x
    where s.player_id = $1 on conflict do nothing)
  select 1`

// 게으른 완료(개정 12 §2.4): 다 지은 건물 레벨 +1(성채·성문이면 player_state 레벨도 — 하위 호환), 일꾼 비우기,
// economy_log build_done을 version 가드 한 문장으로. 다른 요청이 먼저 바꿨으면 0행 — 다시 읽는다.
const COMPLETE_SQL = `with s as (update player_state set version = version + 1, build_id = null, build_finish = null,
    keep_level = keep_level + (case when build_id = $5 then 1 else 0 end), gate_level = gate_level + (case when build_id = $6 then 1 else 0 end)
    where player_id = $1 and version = $2 and build_id = $3 returning player_id),
  b as (update player_buildings set level = level + 1 where player_id = (select player_id from s) and building = $3 returning 1),
  l as (insert into economy_log (player_id, kind, detail, at) select player_id, 'build_done', $7::jsonb, to_timestamp($4::float8) from s returning 1)
  select count(*)::int as n from s`

const json = (v: unknown) => (typeof v === 'string' ? JSON.parse(v) : v)
// 건물 레벨(행이 없으면 1)
const level = (p: Player, building: string) => p.buildings[building]?.level ?? 1
// bigint 파라미터는 정수 문자열로 — Neon은 숫자를 toString()으로 보내 1e21부터 지수 표기가 되고 ::bigint가 거부한다. 정수가 아니면 throw.
const bigint = (v: number) => BigInt(v).toString()
// {키: 정수} 사전(DB jsonb·집계) — 숫자가 아닌 값은 버린다
function counts(v: unknown): Record<string, number> {
  const out: Record<string, number> = {}
  if (v && typeof v === 'object' && !Array.isArray(v)) {
    for (const [k, n] of Object.entries(v as Record<string, unknown>)) if (Number.isInteger(Number(n))) out[k] = Number(n)
  }
  return out
}

// 게으른 생산(개정 13 §4): 병사 건물마다 마지막 생산 시각(last_collect)부터 지난 시간(축적 상한까지) / 한 마리 시간만큼 1티어를 만든다
// (남은 시간 유지). 바뀐 게 없으면 null. 건설 중에도 이어진다.
// ponytail: loadPlayer가 완료보다 먼저 생산하므로 끝나는 시각 ~ 그 뒤 첫 요청 사이(앱은 2초마다 묻는다)는 이전 레벨로 센다.
// 정확해야 하면 완료 처리에서 끝나는 시각까지 이전 레벨로 생산한다.
function production(p: Player, game: Game, now: number): Change | null {
  if (game.soldiers.length === 0) return null // 시드 전 DB
  const cap = R.cfgNum(game.config, 'accum_cap_min')
  const buildings: Record<string, number> = {}
  const soldiers: Record<string, number> = {}
  const made: unknown[] = []
  for (const s of game.soldiers) {
    const b = p.buildings[s.building]
    if (!b) continue
    const st = R.soldierProdStep(b.last_collect, now, R.soldierUnitSec(game.config, b.level), cap)
    if (!st.changed) continue
    buildings[s.building] = st.last
    if (st.count > 0) {
      soldiers[R.soldierKey(s.id, 1)] = st.count
      made.push({ building: s.building, type: s.id, count: st.count, level: b.level, from: b.last_collect, to: st.last })
    }
  }
  if (Object.keys(buildings).length === 0) return null
  return { buildings, soldiers, log: made.length ? { kind: 'soldier_prod', detail: made } : undefined }
}

export function createApp(opts: AppOptions) {
  const query = opts.query
  const clock = opts.now ?? (() => Date.now() / 1000)
  const secret = opts.jwtSecret
  const random = opts.random ?? R.cryptoRandom
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
      resources: json(r.resources), buildings: json(r.buildings), soldiers: json(r.soldiers), config: json(r.config),
    }
  }

  // 플레이어 상태 읽기. 플레이어 상태를 읽거나 쓰는 모든 요청이 여기를 지난다 — 다 지은 건물이 있으면 먼저 완료하고
  // (게으른 완료, 개정 12) 다시 읽는다. 빠진 자원·건물 행은 한 번 채우고 다시 읽는다.
  async function loadPlayer(id: string, game: Game, now: number): Promise<Player> {
    let ensured = false
    for (let i = 0; i < MAX_ATTEMPTS + 2; i++) { // 행 채우기·생산·완료가 한 번씩 다시 읽게 한다
      const [r] = await query(PLAYER_SQL, [id])
      if (!r) throw new ApiError(401, 'unknown_player', 'player not found; log in again')
      const res: Record<string, number> = {}
      for (const [k, v] of Object.entries(json(r.res) as Record<string, unknown>)) res[k] = Number(v)
      const buildings: Player['buildings'] = {}
      for (const [k, v] of Object.entries(json(r.buildings) as Record<string, any>)) buildings[k] = { level: Number(v.level), last_collect: Number(v.last_collect) }
      const missing = game.resources.some((x) => !(x.id in res) || !(x.building in buildings)) || game.buildings.some((b) => !(b.id in buildings))
      if (missing) {
        if (ensured) throw new ApiError(500, 'internal', 'player rows missing')
        ensured = true
        await query(ENSURE_ROWS_SQL, [id, now, R.KEEP, R.GATE]) // 나중에 추가된 자원·건물 — 행을 채우고 다시 읽는다
        continue
      }
      const heroes: Player['heroes'] = {}
      for (const [k, v] of Object.entries(json(r.heroes) as Record<string, any>)) heroes[k] = { copies: Number(v.copies), level: Number(v.level), shards: Number(v.shards), promotion: Number(v.promotion) }
      const deploy = json(r.deploy)
      const p: Player = {
        gold_tenths: Number(r.gold_tenths), stage: Number(r.stage), keep_level: Number(r.keep_level), gate_level: Number(r.gate_level),
        version: Number(r.version), last_kill_report: Number(r.last_kill_report), last_stage_clear: Number(r.last_stage_clear),
        kill_seq: Number(r.kill_seq), res, buildings, heroes, deploy: Array.isArray(deploy) ? deploy : [],
        build: typeof r.build_id === 'string' ? { id: r.build_id, finish: Number(r.build_finish) } : null,
        soldiers: counts(json(r.soldiers)), soldier_deploy: counts(json(r.soldier_deploy)),
      }
      const made = production(p, game, now) // 게으른 생산(개정 13) — 완료와 같은 자리, commit의 version 가드 한 문장
      if (made) {
        await commit(id, p.version, made, now)
        continue // 이겼든 졌든 다시 읽는다(졌으면 다른 요청이 이미 생산했다)
      }
      if (p.build && p.build.finish <= now) {
        const from = level(p, p.build.id)
        await query(COMPLETE_SQL, [id, p.version, p.build.id, now, R.KEEP, R.GATE,
          JSON.stringify({ building: p.build.id, from, to: from + 1, finish: p.build.finish })])
        continue // 이겼든 졌든(다른 요청이 먼저 완료했으면 build_id가 비어 있다) 다시 읽는다
      }
      return p
    }
    throw new ApiError(409, 'conflict', 'concurrent update; try again')
  }

  // 플레이어 응답(스펙 §4 공통). buildings = 건물 표의 모든 건물 {level}, 자원·병사 건물은 last_collect(병사는 마지막 생산 시각)도.
  // build = 일꾼 또는 null, population = 민가 레벨의 인구(개정 12). soldiers = 표에 있는 병종의 보유 "병종:티어" → 수(0 초과),
  // soldier_deploy = 배치(보유로 자름, 개정 13).
  function view(p: Player, game: Game, now: number) {
    const res: Record<string, number> = {}
    const buildings: Record<string, { level: number; last_collect?: number }> = {}
    for (const d of game.buildings) buildings[d.id] = { level: level(p, d.id) }
    for (const r of game.resources) {
      res[r.id] = p.res[r.id] ?? 0
      const b = p.buildings[r.building]
      buildings[r.building] = { level: b?.level ?? 1, last_collect: b?.last_collect ?? now }
    }
    for (const s of game.soldiers) {
      const b = p.buildings[s.building]
      buildings[s.building] = { level: b?.level ?? 1, last_collect: b?.last_collect ?? now }
    }
    const maxTier = game.soldiers.length ? R.cfgNum(game.config, 'soldier_max_tier') : 0
    const soldiers: Record<string, number> = {}
    for (const [k, n] of Object.entries(p.soldiers)) if (n > 0 && R.parseSoldierKey(k, game.soldiers, maxTier)) soldiers[k] = n
    // 영웅: 표에 있는 것만. 배치: 길이 = 슬롯 수, 보유하지 않은(표에서 빠진) 영웅은 null
    const known = new Set(game.heroes.map((h) => String(h.id)))
    const heroes: Player['heroes'] = {}
    for (const [id, h] of Object.entries(p.heroes)) if (known.has(id)) heroes[id] = { copies: h.copies, level: h.level, shards: h.shards, promotion: h.promotion }
    const deploy = Array.from({ length: R.heroSlots(game.config, level(p, R.KEEP)) }, (_, i) => {
      const id = p.deploy[i]
      return typeof id === 'string' && Object.hasOwn(heroes, id) ? id : null
    })
    return {
      server_now: now,
      player: {
        gold_tenths: p.gold_tenths, gold: Math.floor(p.gold_tenths / 10), res, stage: p.stage, keep_level: p.keep_level, gate_level: p.gate_level,
        kill_seq: p.kill_seq, buildings, build: p.build, population: R.population(game.config, level(p, R.HOUSES)), heroes, deploy,
        soldiers, soldier_deploy: R.trimDeploy(p.soldier_deploy, soldiers),
      },
      merchant: { rates: R.merchantRates(R.hourIndex(now), game.config, game.resources.map((x) => x.id)), next_change: R.nextChange(now) },
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
    if (ch.deploy !== undefined) sets.push(`deploy = ${p(JSON.stringify(ch.deploy))}::jsonb`)
    if (ch.build !== undefined) sets.push(`build_id = ${p(ch.build?.id ?? null)}::text, build_finish = to_timestamp(${p(ch.build?.finish ?? null)}::float8)`)
    if (ch.soldierDeploy !== undefined) sets.push(`soldier_deploy = ${p(JSON.stringify(ch.soldierDeploy))}::jsonb`)
    const ctes = [`s as (update player_state set ${sets.join(', ')} where player_id = $1 and version = $2 returning player_id)`]
    if (ch.soldiers && Object.keys(ch.soldiers).length) {
      // "병종:티어" → 증감. from s: version 가드가 실패하면 보유도 안 바뀐다. 더하기는 upsert, 빼기는 검사한 기존 행의 update
      // (insert의 후보 행이 음수면 충돌 처리 전에 count ≥ 0 제약에 걸린다)
      const x = `jsonb_each_text(${p(JSON.stringify(ch.soldiers))}::jsonb) as x`
      ctes.push(`sa as (insert into player_soldiers (player_id, type, tier, count)
        select s.player_id, split_part(x.key, ':', 1), split_part(x.key, ':', 2)::int, x.value::int from s, ${x} where x.value::int > 0
        on conflict (player_id, type, tier) do update set count = player_soldiers.count + excluded.count returning 1)`)
      ctes.push(`sd as (update player_soldiers set count = count + x.value::int from s, ${x}
        where x.value::int < 0 and player_soldiers.player_id = s.player_id and type = split_part(x.key, ':', 1) and tier = split_part(x.key, ':', 2)::int returning 1)`)
    }
    if (ch.heroes && Object.keys(ch.heroes).length) {
      // from s: version 가드가 실패하면(s가 비면) 영웅도 안 늘어난다. 조각(개정 15): 새 영웅은 첫 장을 뺀 나머지, 있던 영웅은 전부
      ctes.push(`h as (insert into player_heroes (player_id, hero_id, copies, shards)
        select s.player_id, x.key, x.value::int, x.value::int - 1 from s, jsonb_each_text(${p(JSON.stringify(ch.heroes))}::jsonb) as x
        on conflict (player_id, hero_id) do update set copies = player_heroes.copies + excluded.copies,
          shards = player_heroes.shards + excluded.copies returning 1)`)
    }
    Object.entries(ch.heroLevels ?? {}).forEach(([id, d], i) => {
      ctes.push(`hl${i} as (update player_heroes set level = level + ${p(d)}::int
        where player_id = (select player_id from s) and hero_id = ${p(id)} returning 1)`)
    })
    if (ch.promote) {
      ctes.push(`hp as (update player_heroes set shards = shards - ${p(ch.promote.cost)}::int, promotion = promotion + 1
        where player_id = (select player_id from s) and hero_id = ${p(ch.promote.id)} returning 1)`)
    }
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
    for (const [k, d] of Object.entries(ch.heroes ?? {})) {
      const h = pl.heroes[k]
      pl.heroes[k] = h ? { ...h, copies: h.copies + d, shards: h.shards + d } : { copies: d, level: 1, shards: d - 1, promotion: 0 }
    }
    for (const [k, d] of Object.entries(ch.heroLevels ?? {})) pl.heroes[k].level += d
    if (ch.promote) {
      pl.heroes[ch.promote.id].shards -= ch.promote.cost
      pl.heroes[ch.promote.id].promotion += 1
    }
    if (ch.deploy !== undefined) pl.deploy = ch.deploy
    if (ch.build !== undefined) pl.build = ch.build
    for (const [k, d] of Object.entries(ch.soldiers ?? {})) pl.soldiers[k] = (pl.soldiers[k] ?? 0) + d
    if (ch.soldierDeploy !== undefined) pl.soldier_deploy = ch.soldierDeploy
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
    // 시드 전 DB(마이그레이션만 적용)면 설정 행이 없다 — 마이그레이션 005와 같은 스펙 기본값을 쓴다(새 플레이어가 영웅 0명이 되지 않게)
    const [cfg] = await query("select value from game_config where key = 'starter_heroes'")
    const starters = String(cfg?.value ?? DEFAULT_STARTERS).split('|').map((x) => x.trim()).filter(Boolean)
    const [r] = await query(ENSURE_SQL, [device, now, JSON.stringify(starters)])
    const iat = Math.floor(now)
    const token = await sign({ sub: r.id, iat, exp: iat + TOKEN_TTL }, secret, 'HS256')
    return c.json({ token, player_id: r.id })
  })

  app.get('/v1/gamedata', async (c) => {
    const g = await loadGame()
    const data = { monsters: g.monsters, stages: g.stages, heroes: g.heroes, resources: g.resources, buildings: g.buildings, soldiers: g.soldiers, config: g.config }
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
    const b = await body(c)
    if (b.items !== undefined) {
      // 여러 자원 한 번에(1~3개, 자원 중복 불가). 하나라도 보유 초과면 아무것도 안 판다
      const items = b.items
      if (!Array.isArray(items) || items.length < 1 || items.length > 3) throw new ApiError(400, 'bad_request', "'items' must be an array of 1..3")
      const want = new Map<string, number>()
      for (const it of items) {
        if (!it || typeof it !== 'object' || Array.isArray(it)) throw new ApiError(400, 'bad_request', 'each item must be an object')
        const o = it as Record<string, unknown>
        const id = strField(o, 'res')
        if (want.has(id)) throw new ApiError(400, 'bad_request', `duplicate res '${id}'`)
        want.set(id, intField(o, 'amount', 1, MAX_INT4))
      }
      return mutate(c, (p, g, now) => {
        const rates = R.merchantRates(R.hourIndex(now), g.config, g.resources.map((x) => x.id))
        let gold = 0
        const sold: Record<string, number> = {}
        const delta: Record<string, number> = {}
        for (const [id, amount] of want) {
          const r = g.resources.find((x) => x.id === id)
          if (!r) throw new ApiError(400, 'unknown_resource', `unknown resource '${id}'`)
          const have = p.res[id] ?? 0
          if (amount > have) throw new ApiError(409, 'not_enough', `only ${have} ${id} to sell`)
          gold += R.sellValue(amount, r.price, rates[id])
          sold[id] = amount
          delta[id] = -amount
        }
        return { change: { goldTenths: gold * 10, res: delta, log: { kind: 'sell', detail: { res: 'items', sold, rates: Object.fromEntries(Object.keys(sold).map((id) => [id, rates[id]])), gold, gold_tenths: gold * 10 } } }, extra: { gold_gained: gold, rates } }
      })
    }
    const target = strField(b, 'res')
    // 수량 판매(개정 14 §4): amount 생략 = 전량. 'all'이면 amount는 쓰지 않는다
    const want = target !== 'all' && b.amount !== undefined ? intField(b, 'amount', 1, MAX_INT4) : undefined
    return mutate(c, (p, g, now) => {
      const list = target === 'all' ? g.resources : g.resources.filter((x) => x.id === target)
      if (list.length === 0) throw new ApiError(400, 'unknown_resource', `unknown resource '${target}'`)
      const rates = R.merchantRates(R.hourIndex(now), g.config, g.resources.map((x) => x.id))
      let gold = 0
      const sold: Record<string, number> = {}
      const delta: Record<string, number> = {}
      for (const r of list) {
        const have = p.res[r.id] ?? 0
        if (want !== undefined && want > have) throw new ApiError(409, 'not_enough', `only ${have} ${r.id} to sell`)
        const amount = want ?? have
        if (amount <= 0) continue
        gold += R.sellValue(amount, r.price, rates[r.id])
        sold[r.id] = amount
        delta[r.id] = -amount
      }
      if (Object.keys(sold).length === 0) return { extra: { gold_gained: 0, rates } }
      return { change: { goldTenths: gold * 10, res: delta, log: { kind: 'sell', detail: { res: target, sold, rates: Object.fromEntries(Object.keys(sold).map((id) => [id, rates[id]])), gold, gold_tenths: gold * 10 } } }, extra: { gold_gained: gold, rates } }
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

  // 건물 업그레이드(개정 12 §2.4): 검사 순서 존재(400 unknown_building) → 최대 레벨 → 성채 상한 → 선행 → 일꾼 → 자원
  // (409, 코드 = rules.upgradeBlock). 자원 건물이면 먼저 자동 수집(수집 규칙 그대로, 남은 초 유지)하고 그 양까지 비용에 쓴다 —
  // 레벨이 바뀌는 경계를 깨끗하게. 수집·차감·일꾼(build_id·build_finish = 서버 시각 + 시간)·로그는 version 가드 한 문장.
  app.post('/v1/building/upgrade', auth, async (c) => {
    const building = strField(await body(c), 'building')
    return mutate(c, (p, g, now) => {
      const def = g.buildings.find((d) => d.id === building)
      if (!def) throw new ApiError(400, 'unknown_building', `unknown building '${building}'`)
      const from = level(p, building)
      const res: Record<string, number> = { ...p.res }
      const rdef = g.resources.find((r) => r.building === building)
      let collect: { res: string; amount: number; from: number; to: number } | null = null
      if (rdef) {
        const b = p.buildings[building]
        const st = R.collectStep(b.last_collect, now, rdef.per_min, b.level, R.cfgNum(g.config, 'accum_cap_min'))
        if (st.changed) {
          collect = { res: rdef.id, amount: st.amount, from: b.last_collect, to: st.lastCollect }
          res[rdef.id] = (res[rdef.id] ?? 0) + st.amount
        }
      }
      const levels: Record<string, number> = {}
      for (const d of g.buildings) levels[d.id] = level(p, d.id)
      const why = R.upgradeBlock(building, g.buildings, levels, p.build !== null, res)
      if (why) throw new ApiError(409, why, `cannot upgrade '${building}' from level ${from}: ${why}`)
      const cost = R.buildCost(def, from)
      const finish = now + R.buildSec(def, from)
      const delta: Record<string, number> = {}
      for (const r of R.BUILD_RES) {
        const d = (collect?.res === r ? collect.amount : 0) - cost[r]
        if (d !== 0) delta[r] = d
      }
      return {
        change: {
          res: delta, buildings: collect ? { [building]: collect.to } : {}, build: { id: building, finish },
          log: { kind: 'build_start', detail: { building, from, to: from + 1, cost, finish, collect } },
        },
        extra: { build: { id: building, finish } },
      }
    })
  })

  // 모집(스펙 §3.6·§3.7): 비용(정수 골드)은 floor(gold_tenths / 10)로 판정하고 × 10을 뺀다(소수 부분은 남는다).
  // 골드 차감·영웅 copies·조각·economy_log는 version 가드 한 문장으로 같이 들어가거나 같이 안 들어간다.
  // 개정 15: 이미 가진 영웅이 다시 나오면 copies +1, 조각 +1. 결과 항목의 shards = 그 장까지 반영한 조각.
  app.post('/v1/gacha', auth, async (c) => {
    const count = (await body(c)).count
    if (count !== 1 && count !== 10) throw new ApiError(400, 'bad_request', "'count' must be 1 or 10")
    return mutate(c, (p, g) => {
      const cost = R.cfgNum(g.config, count === 10 ? 'gacha_cost_10' : 'gacha_cost_1')
      if (Math.floor(p.gold_tenths / 10) < cost) throw new ApiError(409, 'not_enough_gold', `recruiting ${count} costs ${cost} gold`)
      const owned: Record<string, { copies: number; shards: number }> = {}
      for (const [id, h] of Object.entries(p.heroes)) owned[id] = { copies: h.copies, shards: h.shards }
      const add: Record<string, number> = {}
      const results = R.rollGacha(count, g.heroes, g.config, random, level(p, R.TAVERN)).map(({ id, grade }) => {
        const o = owned[id]
        const isNew = !(o?.copies > 0)
        owned[id] = isNew ? { copies: 1, shards: 0 } : { copies: o.copies + 1, shards: o.shards + 1 }
        add[id] = (add[id] ?? 0) + 1
        return { hero_id: id, grade, new: isNew, copies: owned[id].copies, shards: owned[id].shards }
      })
      return {
        change: { goldTenths: -cost * 10, heroes: add, log: { kind: 'gacha', detail: { count, cost, gold_tenths: -cost * 10, results } } },
        extra: { results },
      }
    })
  })

  // 배치: 길이 = 슬롯 수, 보유한 영웅만, 중복 금지(null은 여러 개 가능). 아니면 400.
  app.post('/v1/deploy', auth, async (c) => {
    const d = (await body(c)).deploy
    if (!Array.isArray(d) || d.some((x) => x !== null && (typeof x !== 'string' || x === ''))) {
      throw new ApiError(400, 'bad_deploy', "'deploy' must be an array of hero ids or null")
    }
    return mutate(c, (p, g) => {
      const slots = R.heroSlots(g.config, level(p, R.KEEP))
      if (d.length !== slots) throw new ApiError(400, 'bad_deploy', `'deploy' must have ${slots} slots`)
      const ids = d.filter((x): x is string => x !== null)
      if (new Set(ids).size !== ids.length) throw new ApiError(400, 'bad_deploy', 'a hero can be deployed only once')
      const known = new Set(g.heroes.map((h) => String(h.id)))
      for (const id of ids) {
        if (!known.has(id) || !Object.hasOwn(p.heroes, id)) throw new ApiError(400, 'bad_deploy', `hero '${id}' is not owned`)
      }
      return { change: { deploy: d } }
    })
  })

  // 레벨업(개정 11 §2.2): count 1..100. 보유하지 않은 영웅은 404, 최대 레벨을 넘거나 골드가 모자라면 409(max_level / not_enough_gold). 개정 12: 골드만.
  // 골드(정수, × 10 tenths) 차감, 레벨, economy_log는 version 가드 한 문장으로 같이 들어가거나 같이 안 들어간다.
  app.post('/v1/hero/levelup', auth, async (c) => {
    const b = await body(c)
    const heroId = strField(b, 'hero_id')
    const count = intField(b, 'count', 1, MAX_LEVELUP_COUNT)
    return mutate(c, (p, g) => {
      const def = g.heroes.find((h) => h.id === heroId)
      const own = Object.hasOwn(p.heroes, heroId) ? p.heroes[heroId] : undefined
      if (!def || !own) throw new ApiError(404, 'not_owned', `hero '${heroId}' is not owned`)
      const to = own.level + count
      const max = R.heroMaxLevel(own.promotion, g.config) // 개정 15: 승급 기준
      if (to > max) throw new ApiError(409, 'max_level', `level ${to} is above the max level ${max}`)
      const cost = R.levelupCost(String(def.grade), own.level, count, g.config)
      if (Math.floor(p.gold_tenths / 10) < cost.gold) {
        throw new ApiError(409, 'not_enough_gold', `levels ${own.level} -> ${to} cost ${cost.gold} gold`)
      }
      return {
        change: {
          goldTenths: -cost.gold * 10, heroLevels: { [heroId]: count },
          log: { kind: 'levelup', detail: { hero_id: heroId, from: own.level, to, count, gold: cost.gold, gold_tenths: -cost.gold * 10 } },
        },
        extra: { level: to },
      }
    })
  })

  // 승급(개정 15 §2): 검사 순서 보유(404 not_owned) → 최대 승급(409 max_promotion) → 조각(409 not_enough_shards).
  // 조각 −비용·승급 +1·economy_log promote는 version 가드 한 문장 — 같은 순간 두 번 보내도 조각이 1회분이면 하나는 409다.
  app.post('/v1/hero/promote', auth, async (c) => {
    const heroId = strField(await body(c), 'hero_id')
    return mutate(c, (p, g) => {
      const own = Object.hasOwn(p.heroes, heroId) && g.heroes.some((h) => h.id === heroId) ? p.heroes[heroId] : undefined
      if (!own) throw new ApiError(404, 'not_owned', `hero '${heroId}' is not owned`)
      const cost = R.promoteCost(own.promotion, g.config)
      if (cost === null) throw new ApiError(409, 'max_promotion', `hero '${heroId}' is at the max promotion ${own.promotion}`)
      if (own.shards < cost) throw new ApiError(409, 'not_enough_shards', `promotion ${own.promotion} -> ${own.promotion + 1} needs ${cost} shards, have ${own.shards}`)
      const to = own.promotion + 1
      return {
        change: {
          promote: { id: heroId, cost },
          log: { kind: 'promote', detail: { hero_id: heroId, from: own.promotion, to, shards: cost, shards_before: own.shards, shards_after: own.shards - cost } },
        },
        extra: { promotion: to },
      }
    })
  })

  // 병사 합성(개정 13 §5): 같은 병종·티어 soldier_merge_count마리 → 한 티어 위 1마리. 400 unknown_soldier, 409 max_tier(최대 티어),
  // 409 not_enough(부족). 배치가 보유보다 많아지면 보유로 자른다. 보유·배치·economy_log는 version 가드 한 문장.
  app.post('/v1/soldiers/merge', auth, async (c) => {
    const b = await body(c)
    const type = strField(b, 'type')
    const tier = intField(b, 'tier', 1, MAX_INT4)
    return mutate(c, (p, g) => {
      if (!g.soldiers.some((s) => s.id === type)) throw new ApiError(400, 'unknown_soldier', `unknown soldier '${type}'`)
      const max = R.cfgNum(g.config, 'soldier_max_tier')
      if (tier >= max) throw new ApiError(409, 'max_tier', `tier ${tier} cannot merge (max tier ${max})`)
      const need = R.cfgNum(g.config, 'soldier_merge_count')
      const key = R.soldierKey(type, tier)
      const up = R.soldierKey(type, tier + 1)
      const have = p.soldiers[key] ?? 0
      if (have < need) throw new ApiError(409, 'not_enough', `merging needs ${need} of ${key}, have ${have}`)
      const owned = { ...p.soldiers, [key]: have - need, [up]: (p.soldiers[up] ?? 0) + 1 }
      const deploy = R.trimDeploy(p.soldier_deploy, owned)
      return {
        change: {
          soldiers: { [key]: -need, [up]: 1 }, soldierDeploy: deploy,
          log: { kind: 'soldier_merge', detail: { type, tier, count: need, have, deployed: p.soldier_deploy[key] ?? 0, deployed_after: deploy[key] ?? 0 } },
        },
        extra: { merged: { type, tier: tier + 1 } },
      }
    })
  })

  // 병사 배치(개정 13 §6): {deploy: {"병종:티어": 수}}. 키 형식(표에 있는 병종, 티어 1..최대), 0 이상 정수, 보유 이하, 합계 ≤ 인구 — 아니면 400.
  // 같은 배치를 다시 보내도 같다(멱등).
  app.post('/v1/soldiers/deploy', auth, async (c) => {
    const d = (await body(c)).deploy
    if (!d || typeof d !== 'object' || Array.isArray(d)) throw new ApiError(400, 'bad_deploy', "'deploy' must be an object of 'type:tier' -> count")
    const entries = Object.entries(d as Record<string, unknown>)
    for (const [k, n] of entries) {
      if (!isInt(n, 0, MAX_INT4)) throw new ApiError(400, 'bad_deploy', `count for '${k}' must be a non-negative integer`)
    }
    return mutate(c, (p, g) => {
      const max = R.cfgNum(g.config, 'soldier_max_tier')
      const out: Record<string, number> = {}
      let total = 0
      for (const [k, n] of entries as [string, number][]) {
        if (!R.parseSoldierKey(k, g.soldiers, max)) throw new ApiError(400, 'bad_deploy', `'${k}' is not a 'type:tier' key`)
        if (n > (p.soldiers[k] ?? 0)) throw new ApiError(400, 'bad_deploy', `only ${p.soldiers[k] ?? 0} of '${k}' owned`)
        if (n > 0) out[k] = n
        total += n
      }
      const pop = R.population(g.config, level(p, R.HOUSES))
      if (total > pop) throw new ApiError(400, 'bad_deploy', `deploying ${total} is above the population ${pop}`)
      return { change: { soldierDeploy: out } }
    })
  })

  if (opts.allowTestHooks) {
    // 통합 테스트용: 그 플레이어 건물의 last_collect를 minutes분 앞당긴다(자원 건물 수집, 병사 건물 생산 — 개정 13).
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

    // 통합 테스트용(개정 15): 보유 영웅의 조각 수를 정한다(서버 모집은 암호학적 난수라 중복을 만들 수 없다). 없는 영웅은 아무것도 안 바뀐다.
    app.post('/v1/test/shards', auth, async (c) => {
      const b = await body(c)
      const heroId = strField(b, 'hero_id')
      const shards = intField(b, 'shards', 0, MAX_INT4)
      const id = c.get('playerId') as string
      await query(`with s as (update player_state set version = version + 1 where player_id = $1 returning player_id)
        update player_heroes set shards = $3 where player_id = (select player_id from s) and hero_id = $2`, [id, heroId, shards])
      const now = clock()
      const game = await loadGame()
      return c.json(view(await loadPlayer(id, game, now), game, now))
    })

    // 통합 테스트용(개정 12): 진행 중 건설의 끝나는 시각을 지금으로 — 이어지는 플레이어 읽기(이 응답 포함)가 게으른 완료를 한다.
    app.post('/v1/test/build_now', auth, async (c) => {
      const id = c.get('playerId') as string
      await query('update player_state set version = version + 1, build_finish = to_timestamp($2::float8) where player_id = $1 and build_id is not null', [id, clock()])
      const now = clock()
      const game = await loadGame()
      return c.json(view(await loadPlayer(id, game, now), game, now))
    })
  }

  return app
}

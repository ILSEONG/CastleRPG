// Hono 앱 팩토리. 시계(now)·쿼리 함수를 주입받아 테스트에서 포트 없이 app.request()로 돌린다.
import { createHash, randomBytes, randomUUID } from 'node:crypto'
import { Hono } from 'hono'
import type { Context, Next } from 'hono'
import { bodyLimit } from 'hono/body-limit'
import { cors } from 'hono/cors'
import { sign, verify } from 'hono/jwt'
import type { Query, Row } from './db.ts'
import { DEFAULT_STARTERS, ident, TABLES } from './seed.ts'
import * as R from './rules.ts'
import * as O from './oauth.ts'
import * as G from './guild.ts'

export interface AppOptions {
  query: Query
  now?: () => number // 유닉스 초(float)
  jwtSecret: string
  allowTestHooks?: boolean
  corsOrigins?: string[] // 비면 *
  random?: () => number // [0, 1) 난수(모집). 기본은 암호학적 난수(R.cryptoRandom) — 테스트만 주입한다
  oauth?: O.OAuthConfig // 소셜 로그인 제공자 키·공개 주소(없으면 소셜 로그인 꺼짐)
  fetch?: typeof fetch // 제공자 호출(테스트는 가짜)
}

const TOKEN_TTL = 30 * 86400
const MAX_ATTEMPTS = 4 // 첫 시도 + 충돌 시 재시도 3회
const MAX_BODY = 16 * 1024
const MAX_STAGE = 1_000_000
const MAX_KILL_COUNT = 10_000 // 몬스터 한 종류의 한 번 보고 수
const MAX_INT4 = 2_147_483_647
const MAX_AGE_MIN = 100_000
const MAX_LEVELUP_COUNT = 100
const MAX_SELL_ITEMS = 1000 // 개정 18: 장비 판매 한 번의 개수
const RUN_KEEP_SEC = 86400 // 끝난 run은 하루 남긴다(재전송 멱등), 그 뒤 새 start가 지운다
const DEVICE_RE = /^[A-Za-z0-9-]{16,128}$/
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const HEX64_RE = /^[0-9a-f]{64}$/ // 소셜 로그인 state·verifier·challenge·세션 비밀(32바이트 hex)
const OAUTH_TTL = 600 // 진행 중 소셜 로그인 유효 시간(초)
const sha256hex = (s: string) => createHash('sha256').update(s).digest('hex')

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
  upgrades: R.UpgradeDef[] // 개정 20 공용 업그레이드 표(파일 순서)
  dungeons: R.DungeonDef[] // 개정 18 던전 적 표(파일 순서)
  equip_drop: Record<string, number>[] // 개정 18 등급 가중치(min_level 순)
  research: R.ResearchDef[] // 개정 24 연구 노드 표(파일 순서)
  config: R.Config
}

// 개정 18: 보관함 장비(id = player_items.id), 장착 행
type Item = R.EquipItem & { id: number }
interface Equipped {
  hero_id: string
  slot: string
  item_id: number
}
// 던전 run(dungeon_runs 행)
interface Run {
  run_id: string
  type: string
  level: number
  party: string[]
  seed: number
  started_at: number
  closed: boolean
  result: { win?: boolean; rewards?: Record<string, unknown> } | null
}

interface Player {
  gold_tenths: number
  stage: number
  keep_level: number
  gate_level: number
  version: number
  last_kill_report: number
  last_stage_clear: number
  last_active: number | null // 마지막으로 상태를 바꾼 요청의 서버 시각(commit이 쓴다). null = 아직 없음 — 오프라인 처치 골드 기준
  kill_seq: number
  res: Record<string, number>
  buildings: Record<string, { level: number; last_collect: number; train: Train | null }> // train: 병사 건물 훈련 대기열(개정 16), 비면 null
  heroes: Record<string, Hero> // 영웅 id → 보유 수·레벨·조각·승급(개정 15)
  deploy: unknown[] // 저장된 그대로(응답에서 슬롯 수·보유로 맞춘다)
  build: { id: string; finish: number } | null // 일꾼(개정 12): 짓는 건물과 끝나는 시각(유닉스 초), 쉬면 null
  soldiers: Record<string, number> // 개정 13: "병종:티어" → 보유 수(0 초과만)
  soldier_deploy: Record<string, number> // "병종:티어" → 배치 수(저장된 그대로 — 응답에서 보유로 자른다)
  upgrades: Record<string, number> // 개정 20: 업그레이드 id → 레벨(0 초과만)
  dungeons: Record<string, R.DungeonState> // 개정 18: 종류 → 저장된 상태(일일 리셋 전 값 — 쓰는 쪽이 R.applyReset)
  items: Item[] // 보관함(id 순)
  equipment: Equipped[]
  diamonds: number // 개정 23: 다이아(현금 재화)
  gacha: { gold_level: number; gold_pulls: number; dia_pity: number } // 골드 모집 레벨·그 레벨 안 누적, 다이아 천장 카운터
  research: Record<string, number> // 개정 24: 연구 노드 id → 레벨(0 초과만)
  research_cur: { id: string; finish: number } | null // 진행 중인 연구(끝나는 시각 = 유닉스 초), 쉬면 null
}

interface Train {
  count: number
  tier: number // 시작할 때의 훈련 티어(개정 19) — 레벨업해도 그대로
  finish: number // 유닉스 초(서버 시각)
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
  train?: Record<string, Train | null> // 병사 건물 → 새 훈련 대기열(null = 비움, 개정 16)
  upgrades?: Record<string, number> // 업그레이드 id → 레벨 증가(개정 20)
  // 개정 18 던전·장비
  dungeon?: { type: string; state: R.DungeonState } // 그 던전 행을 이 값으로(일일 리셋을 반영한 값)
  runOpen?: { run_id: string; type: string; level: number; party: string[]; seed: number } // 새 run(그 플레이어의 열린 run은 닫는다)
  runClose?: { run_id: string; result: { win: boolean; rewards: Record<string, unknown> } } // run 닫기 — 아직 열려 있을 때만 전체가 적용된다
  items?: R.EquipItem[] // 보관함에 넣을 장비(run 결과에 id와 함께 남는다)
  sellItems?: number[] // 지울 장비 id
  equip?: { hero_id: string; slot: string; item_id: number | null } // 장착(다른 영웅이 끼고 있으면 옮긴다)·해제(null)
  diamonds?: number // 다이아 증감(개정 23)
  gacha?: Partial<Player['gacha']> // 새 모집 상태(개정 23)
  research?: { id: string; finish: number } | null // 새 진행 중 연구(개정 24)
  researchUp?: string // 연구 노드 레벨 +1(개정 24)
  log?: { kind: string; detail: unknown }
  shards?: Record<string, number> // 영웅 → 조각 증가(길드 상점)
  guild?: GuildChange // 길드(player_guild 행·길드 누적·기록)
}

// 길드 변경(전부 from s — version 가드가 실패하면 아무것도 안 바뀐다).
interface GuildChange {
  row: { guild_id: string | null; joined_at: number | null; coins: number; mine: G.Mine; boss_seen: number; power: number } // player_guild 행 전체
  add?: { guild_id: string; exp: number; dmg: number } // 길드 누적에 더한다
  log?: { guild_id: string; text: string }
  create?: { id: string; name: string; emblem: number; seed: number; virtual_n: number; notice: string }
  leave?: { guild_id: string; owner: boolean } // 길드장이 나가면 남은 실제 길드원 중 먼저 들어온 사람이 길드장, 아무도 없으면 직접 만든 길드는 지운다
}

// 기획 표 전부를 한 쿼리로. 행 키 = CSV 열 이름(열 순서 그대로), 행 순서 = 파일 순서.
const GAME_SQL = 'select ' + TABLES.map((t) => {
  const cols = Object.keys(t.sql)
  if (t.name === 'config') return `(select coalesce(json_object_agg(key, value order by key), '{}'::json) from ${t.table}) as config`
  const obj = `json_build_object(${cols.map((c) => `'${c}', ${ident(c)}`).join(', ')})`
  const order = t.ordered ? `ord, ${cols[0]}` : cols[0]
  return `(select coalesce(json_agg(${obj} order by ${order}), '[]'::json) from ${t.table}) as ${t.name}`
}).join(',\n  ')

const PLAYER_SQL = `select s.gold_tenths, s.diamonds, s.gacha_gold_level, s.gacha_gold_pulls, s.gacha_dia_pity, s.stage, s.keep_level, s.gate_level, s.version, s.kill_seq, s.deploy, s.build_id, s.soldier_deploy,
  coalesce((select json_object_agg(type || ':' || tier, count) from player_soldiers where player_id = s.player_id and count > 0), '{}'::json) as soldiers,
  coalesce((select json_object_agg(id, level) from player_upgrades where player_id = s.player_id and level > 0), '{}'::json) as upgrades,
  coalesce((select json_object_agg(id, level) from player_research where player_id = s.player_id and level > 0), '{}'::json) as research,
  s.research_id, extract(epoch from s.research_finish)::float8 as research_finish,
  extract(epoch from s.build_finish)::float8 as build_finish,
  extract(epoch from s.last_kill_report)::float8 as last_kill_report,
  extract(epoch from s.last_stage_clear)::float8 as last_stage_clear,
  extract(epoch from s.last_active)::float8 as last_active,
  coalesce((select json_object_agg(res, amount) from player_resources where player_id = s.player_id), '{}'::json) as res,
  coalesce((select json_object_agg(building, json_build_object('level', level, 'last_collect', extract(epoch from last_collect)::float8,
      'train_count', train_count, 'train_tier', train_tier, 'train_finish', extract(epoch from train_finish)::float8))
    from player_buildings where player_id = s.player_id), '{}'::json) as buildings,
  coalesce((select json_object_agg(hero_id, json_build_object('copies', copies, 'level', level, 'shards', shards, 'promotion', promotion))
    from player_heroes where player_id = s.player_id), '{}'::json) as heroes,
  coalesce((select json_object_agg(type, json_build_object('best_level', best_level, 'keys', keys, 'extra_today', extra_today,
      'last_reset', extract(epoch from last_reset)::float8)) from player_dungeons where player_id = s.player_id), '{}'::json) as dungeons,
  coalesce((select json_agg(json_build_object('id', id, 'slot', slot, 'weapon_kind', weapon_kind, 'grade', grade, 'level', level) order by id)
    from player_items where player_id = s.player_id), '[]'::json) as items,
  coalesce((select json_agg(json_build_object('hero_id', hero_id, 'slot', slot, 'item_id', item_id) order by hero_id, slot)
    from player_equipment where player_id = s.player_id), '[]'::json) as equipment
  from player_state s where s.player_id = $1`

// 개정 18: 빠진 던전 행을 그날 지급분으로 채운다($2 = 오늘 리셋 시각, $3 = [{type, keys}]).
const ENSURE_DUNGEONS_SQL = `insert into player_dungeons (player_id, type, best_level, keys, extra_today, last_reset)
  select $1, x.type, 0, x.keys, 0, to_timestamp($2::float8) from jsonb_to_recordset($3::jsonb) as x(type text, keys integer)
  on conflict do nothing`

const RUN_SQL = `select run_id, type, level, party, seed, extract(epoch from started_at)::float8 as started_at, closed, result
  from dungeon_runs where run_id = $1 and player_id = $2`

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
// 개정 24: 연구 효과 합계(서버 권위 효과: 생산·건설 시간·판매·처치 골드·훈련·인구)와 인구(민가 + 연구 pop_add)
const bonus = (p: Player, g: Game) => R.researchBonus(g.research, p.research)
const population = (p: Player, g: Game) => R.population(g.config, level(p, R.HOUSES)) + Math.floor(bonus(p, g).pop_add)
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

// 병사 건물 id의 병종 정의(개정 16 훈련). 병사 건물이 아니면 400 not_soldier_building.
function soldierAt(game: Game, building: string): R.SoldierDef {
  const s = game.soldiers.find((x) => x.building === building)
  if (!s) throw new ApiError(400, 'not_soldier_building', `'${building}' is not a soldier building`)
  return s
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
      resources: json(r.resources), buildings: json(r.buildings), soldiers: json(r.soldiers), upgrades: json(r.upgrades), config: json(r.config),
      dungeons: json(r.dungeons), equip_drop: json(r.equip_drop), research: json(r.research),
    }
  }

  // 개정 18: run 한 행(그 플레이어 것만). 없으면 null.
  async function loadRun(runId: string, playerId: string): Promise<Run | null> {
    const [r] = await query(RUN_SQL, [runId, playerId])
    if (!r) return null
    const party = json(r.party)
    return {
      run_id: String(r.run_id), type: String(r.type), level: Number(r.level), party: Array.isArray(party) ? party : [], seed: Number(r.seed),
      started_at: Number(r.started_at), closed: r.closed === true, result: r.result ? json(r.result) : null,
    }
  }

  // 플레이어 상태 읽기. 플레이어 상태를 읽거나 쓰는 모든 요청이 여기를 지난다 — 다 지은 건물·끝난 연구가 있으면 먼저 완료하고
  // (게으른 완료, 개정 12·24) 다시 읽는다. 빠진 자원·건물 행은 한 번 채우고 다시 읽는다.
  async function loadPlayer(id: string, game: Game, now: number): Promise<Player> {
    let ensured = false
    let ensuredDungeons = false
    for (let i = 0; i < MAX_ATTEMPTS + 3; i++) { // 행 채우기(자원·건물, 던전)·건설 완료·연구 완료가 한 번씩 다시 읽게 한다
      const [r] = await query(PLAYER_SQL, [id])
      if (!r) throw new ApiError(401, 'unknown_player', 'player not found; log in again')
      const res: Record<string, number> = {}
      for (const [k, v] of Object.entries(json(r.res) as Record<string, unknown>)) res[k] = Number(v)
      const buildings: Player['buildings'] = {}
      for (const [k, v] of Object.entries(json(r.buildings) as Record<string, any>)) {
        const train = Number(v.train_count) > 0 ? { count: Number(v.train_count), tier: Number(v.train_tier ?? 1), finish: Number(v.train_finish) } : null
        buildings[k] = { level: Number(v.level), last_collect: Number(v.last_collect), train }
      }
      const missing = game.resources.some((x) => !(x.id in res) || !(x.building in buildings)) || game.buildings.some((b) => !(b.id in buildings))
      if (missing) {
        if (ensured) throw new ApiError(500, 'internal', 'player rows missing')
        ensured = true
        await query(ENSURE_ROWS_SQL, [id, now, R.KEEP, R.GATE]) // 나중에 추가된 자원·건물 — 행을 채우고 다시 읽는다
        continue
      }
      // 개정 18: 던전 행이 없으면(새 플레이어·012 이전 플레이어) 그날 지급분으로 채우고 다시 읽는다
      const dungeons: Player['dungeons'] = {}
      for (const [k, v] of Object.entries(json(r.dungeons) as Record<string, any>)) {
        dungeons[k] = { best_level: Number(v.best_level), keys: Number(v.keys), extra_today: Number(v.extra_today), last_reset: Number(v.last_reset) }
      }
      const lacking = R.DUNGEON_TYPES.filter((t) => !Object.hasOwn(dungeons, t))
      if (lacking.length) {
        if (ensuredDungeons) throw new ApiError(500, 'internal', 'dungeon rows missing')
        ensuredDungeons = true
        const fresh = lacking.map((t) => R.freshDungeon(t, now, game.config))
        await query(ENSURE_DUNGEONS_SQL, [id, fresh[0].last_reset, JSON.stringify(lacking.map((t, j) => ({ type: t, keys: fresh[j].keys })))])
        continue
      }
      const heroes: Player['heroes'] = {}
      for (const [k, v] of Object.entries(json(r.heroes) as Record<string, any>)) heroes[k] = { copies: Number(v.copies), level: Number(v.level), shards: Number(v.shards), promotion: Number(v.promotion) }
      const deploy = json(r.deploy)
      const p: Player = {
        gold_tenths: Number(r.gold_tenths), stage: Number(r.stage), keep_level: Number(r.keep_level), gate_level: Number(r.gate_level),
        version: Number(r.version), last_kill_report: Number(r.last_kill_report), last_stage_clear: Number(r.last_stage_clear),
        last_active: r.last_active == null ? null : Number(r.last_active),
        kill_seq: Number(r.kill_seq), res, buildings, heroes, deploy: Array.isArray(deploy) ? deploy : [],
        build: typeof r.build_id === 'string' ? { id: r.build_id, finish: Number(r.build_finish) } : null,
        soldiers: counts(json(r.soldiers)), soldier_deploy: counts(json(r.soldier_deploy)), upgrades: counts(json(r.upgrades)),
        dungeons,
        items: (json(r.items) as any[]).map((x) => ({ id: Number(x.id), slot: String(x.slot), weapon_kind: x.weapon_kind ?? null, grade: String(x.grade), level: Number(x.level) })),
        equipment: (json(r.equipment) as any[]).map((x) => ({ hero_id: String(x.hero_id), slot: String(x.slot), item_id: Number(x.item_id) })),
        diamonds: Number(r.diamonds),
        gacha: { gold_level: Number(r.gacha_gold_level), gold_pulls: Number(r.gacha_gold_pulls), dia_pity: Number(r.gacha_dia_pity) },
        research: counts(json(r.research)),
        research_cur: typeof r.research_id === 'string' ? { id: r.research_id, finish: Number(r.research_finish) } : null,
      }
      if (p.build && p.build.finish <= now) {
        const from = level(p, p.build.id)
        await query(COMPLETE_SQL, [id, p.version, p.build.id, now, R.KEEP, R.GATE,
          JSON.stringify({ building: p.build.id, from, to: from + 1, finish: p.build.finish })])
        continue // 이겼든 졌든(다른 요청이 먼저 완료했으면 build_id가 비어 있다) 다시 읽는다
      }
      if (p.research_cur && p.research_cur.finish <= now) {
        // 개정 24: 끝난 연구 — 진행 비우기·레벨 +1·economy_log research done을 version 가드 한 문장으로(건설 완료와 같은 방식)
        const cur = p.research_cur
        await commit(id, p.version, {
          research: null, researchUp: cur.id,
          log: { kind: 'research', detail: { action: 'done', id: cur.id, level: (p.research[cur.id] ?? 0) + 1, finish: cur.finish } },
        }, now)
        continue // 이겼든 졌든 다시 읽는다
      }
      return p
    }
    throw new ApiError(409, 'conflict', 'concurrent update; try again')
  }

  // 플레이어 응답(스펙 §4 공통). buildings = 건물 표의 모든 건물 {level}, 자원 건물은 last_collect도.
  // build = 일꾼 또는 null, population = 민가 레벨의 인구(개정 12) + 연구 pop_add(개정 24). soldiers = 표에 있는 병종의 보유 "병종:티어" → 수(0 초과),
  // soldier_deploy = 배치(보유로 자름, 개정 13). training = 병사 건물 → 훈련 대기열 {count, finish} 또는 null(개정 16).
  function view(p: Player, game: Game, now: number) {
    const res: Record<string, number> = {}
    const buildings: Record<string, { level: number; last_collect?: number }> = {}
    for (const d of game.buildings) buildings[d.id] = { level: level(p, d.id) }
    for (const r of game.resources) {
      res[r.id] = p.res[r.id] ?? 0
      const b = p.buildings[r.building]
      buildings[r.building] = { level: b?.level ?? 1, last_collect: b?.last_collect ?? now }
    }
    const upgrades: Record<string, number> = {}
    for (const u of game.upgrades) if ((p.upgrades[u.id] ?? 0) > 0) upgrades[u.id] = p.upgrades[u.id]
    const training: Record<string, Train | null> = {}
    for (const s of game.soldiers) training[s.building] = p.buildings[s.building]?.train ?? null
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
    // 개정 18: 장착 = 영웅 → {부위: 장비 id}(표에 있고 보유한 영웅만)
    const equipment: Record<string, Record<string, number>> = {}
    for (const e of p.equipment) if (Object.hasOwn(heroes, e.hero_id)) (equipment[e.hero_id] ??= {})[e.slot] = e.item_id
    // 개정 24: 연구 레벨(표에 있는 노드, 0 초과)과 진행 중 연구
    const levels: Record<string, number> = {}
    for (const d of game.research) if ((p.research[d.id] ?? 0) > 0) levels[d.id] = p.research[d.id]
    return {
      server_now: now,
      player: {
        gold_tenths: p.gold_tenths, gold: Math.floor(p.gold_tenths / 10), res, stage: p.stage, keep_level: p.keep_level, gate_level: p.gate_level,
        kill_seq: p.kill_seq, buildings, build: p.build, population: population(p, game), heroes, deploy,
        soldiers, soldier_deploy: R.trimDeploy(p.soldier_deploy, soldiers), training, upgrades,
        dungeons: dungeonsView(p, game, now), items: p.items, equipment,
        diamonds: p.diamonds, // 개정 23: 다이아, 모집 상태(gold_next = 다음 레벨까지 필요한 누적, 최대 레벨이면 null)
        gacha: { ...p.gacha, gold_next: R.goldNext(game.config, p.gacha.gold_level) },
        research: { levels, current: p.research_cur },
      },
      merchant: { rates: R.merchantRates(R.hourIndex(now), game.config, game.resources.map((x) => x.id)), next_change: R.nextChange(now) },
    }
  }

  // 개정 18: 지금(서버 시각) 기준 던전 상태 — 일일 리셋을 반영한다(DB 행은 쓸 때 바뀐다).
  const dungeonState = (p: Player, g: Game, type: string, now: number) =>
    R.applyReset(type, p.dungeons[type] ?? R.freshDungeon(type, now, g.config), now, g.config)

  // 던전 응답(스펙 §7 GET /v1/dungeon·플레이어 응답 dungeons): 종류 → {keys, key_cap, key_daily, best_level, extra_today,
  // extra_cost(장비만, 골드는 null), last_reset, next_reset}. 앱은 last_reset으로 같은 리셋 규칙을 이어서 센다.
  function dungeonsView(p: Player, g: Game, now: number) {
    const out: Record<string, unknown> = {}
    for (const t of R.DUNGEON_TYPES) {
      const st = dungeonState(p, g, t, now)
      out[t] = {
        keys: st.keys, key_cap: R.cfgNum(g.config, `${t}_key_cap`), key_daily: R.cfgNum(g.config, `${t}_key_daily`), best_level: st.best_level,
        extra_today: st.extra_today, extra_cost: t === 'equip' ? R.extraCost(g.config, st.extra_today) : null, last_reset: st.last_reset,
        next_reset: R.nextReset(now, g.config),
      }
    }
    return out
  }

  // --- 쓰기: version 낙관적 잠금 + 한 문장(CTE) ---

  // 성공하면 결과 행({n, run_result?}), version이 달랐으면(또는 닫을 run이 이미 닫혔으면) null.
  async function commit(playerId: string, version: number, ch: Change, now: number): Promise<Row | null> {
    const params: unknown[] = [playerId, version]
    const p = (v: unknown) => {
      params.push(v)
      return `$${params.length}`
    }
    const sets = ['version = version + 1', `last_active = to_timestamp(${p(now)}::float8)`] // 상태를 바꾸는 요청은 모두 활동(오프라인 골드 기준)
    if (ch.goldTenths) sets.push(`gold_tenths = gold_tenths + ${p(bigint(ch.goldTenths))}::bigint`)
    if (ch.stage !== undefined) sets.push(`stage = ${p(ch.stage)}::int`)
    if (ch.lastKillReport !== undefined) sets.push(`last_kill_report = to_timestamp(${p(ch.lastKillReport)}::float8)`)
    if (ch.lastStageClear !== undefined) sets.push(`last_stage_clear = to_timestamp(${p(ch.lastStageClear)}::float8)`)
    if (ch.killSeq !== undefined) sets.push(`kill_seq = ${p(ch.killSeq)}::int`)
    if (ch.deploy !== undefined) sets.push(`deploy = ${p(JSON.stringify(ch.deploy))}::jsonb`)
    if (ch.build !== undefined) sets.push(`build_id = ${p(ch.build?.id ?? null)}::text, build_finish = to_timestamp(${p(ch.build?.finish ?? null)}::float8)`)
    if (ch.soldierDeploy !== undefined) sets.push(`soldier_deploy = ${p(JSON.stringify(ch.soldierDeploy))}::jsonb`)
    if (ch.diamonds) sets.push(`diamonds = diamonds + ${p(bigint(ch.diamonds))}::bigint`)
    if (ch.gacha?.gold_level !== undefined) sets.push(`gacha_gold_level = ${p(ch.gacha.gold_level)}::int`)
    if (ch.gacha?.gold_pulls !== undefined) sets.push(`gacha_gold_pulls = ${p(ch.gacha.gold_pulls)}::int`)
    if (ch.gacha?.dia_pity !== undefined) sets.push(`gacha_dia_pity = ${p(ch.gacha.dia_pity)}::int`)
    if (ch.research !== undefined) sets.push(`research_id = ${p(ch.research?.id ?? null)}::text, research_finish = to_timestamp(${p(ch.research?.finish ?? null)}::float8)`)
    // 개정 18: run을 닫는 변경은 그 run이 아직 열려 있을 때만 전체가 적용된다(version 가드와 함께 — 보상이 두 번 들어가지 않는다)
    const guard = ch.runClose ? ` and exists (select 1 from dungeon_runs where run_id = ${p(ch.runClose.run_id)}::uuid and player_id = $1 and not closed)` : ''
    const ctes = [`s as (update player_state set ${sets.join(', ')} where player_id = $1 and version = $2${guard} returning player_id)`]
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
    Object.entries(ch.train ?? {}).forEach(([b, t], i) => {
      ctes.push(`t${i} as (update player_buildings set train_count = ${p(t?.count ?? 0)}::int, train_tier = ${p(t?.tier ?? null)}::int, train_finish = to_timestamp(${p(t?.finish ?? null)}::float8)
        where player_id = (select player_id from s) and building = ${p(b)} returning 1)`)
    })
    if (ch.upgrades && Object.keys(ch.upgrades).length) {
      // from s: version 가드가 실패하면 레벨도 안 오른다. 새 행은 증가분이 곧 레벨
      ctes.push(`u as (insert into player_upgrades (player_id, id, level) select s.player_id, x.key, x.value::int
        from s, jsonb_each_text(${p(JSON.stringify(ch.upgrades))}::jsonb) as x
        on conflict (player_id, id) do update set level = player_upgrades.level + excluded.level returning 1)`)
    }
    if (ch.researchUp) {
      // 개정 24: from s — version 가드가 실패하면 레벨도 안 오른다. 새 행은 레벨 1
      ctes.push(`ru as (insert into player_research (player_id, id, level) select player_id, ${p(ch.researchUp)}::text, 1 from s
        on conflict (player_id, id) do update set level = player_research.level + 1 returning 1)`)
    }
    Object.entries(ch.shards ?? {}).forEach(([id, d], i) => {
      ctes.push(`hs${i} as (update player_heroes set shards = shards + ${p(d)}::int
        where player_id = (select player_id from s) and hero_id = ${p(id)} returning 1)`)
    })
    if (ch.guild) guildCtes(ch.guild, now, ctes, p)
    dungeonCtes(ch, now, ctes, p)
    if (ch.log) {
      ctes.push(`l as (insert into economy_log (player_id, kind, detail, at)
        select player_id, ${p(ch.log.kind)}, ${p(JSON.stringify(ch.log.detail))}::jsonb, to_timestamp(${p(now)}::float8) from s returning 1)`)
    }
    const runResult = ch.runClose ? ', (select result from rc) as run_result' : ''
    const [r] = await query(`with ${ctes.join(',\n')} select count(*)::int as n${runResult} from s`, params)
    return Number(r.n) === 1 ? r : null
  }

  function guildCtes(gc: GuildChange, now: number, ctes: string[], p: (v: unknown) => string) {
    const sid = '(select player_id from s)'
    if (gc.create) {
      const g = gc.create
      ctes.push(`gc as (insert into guilds (id, name, emblem, notice, owner, seed, created_at, virtual_n)
        select ${p(g.id)}::uuid, ${p(g.name)}, ${p(g.emblem)}::int, ${p(g.notice)}, player_id, ${p(g.seed)}::bigint, to_timestamp(${p(now)}::float8), ${p(g.virtual_n)}::int
        from s returning 1)`)
    }
    const r = gc.row
    ctes.push(`pg as (insert into player_guild (player_id, guild_id, joined_at, coins, mine, boss_seen, power, last_active)
      select player_id, ${p(r.guild_id)}::uuid, to_timestamp(${p(r.joined_at)}::float8), ${p(r.coins)}::int, ${p(JSON.stringify(r.mine))}::jsonb,
        ${p(r.boss_seen)}::int, ${p(r.power)}::int, to_timestamp(${p(now)}::float8) from s
      on conflict (player_id) do update set guild_id = excluded.guild_id, joined_at = excluded.joined_at, coins = excluded.coins, mine = excluded.mine,
        boss_seen = excluded.boss_seen, power = excluded.power, last_active = excluded.last_active returning 1)`)
    if (gc.add && (gc.add.exp || gc.add.dmg)) {
      ctes.push(`ga as (update guilds set exp = exp + ${p(gc.add.exp)}::bigint, boss_damage = boss_damage + ${p(Math.round(gc.add.dmg))}::bigint
        where id = ${p(gc.add.guild_id)}::uuid and exists (select 1 from s) returning 1)`)
    }
    if (gc.log) {
      ctes.push(`gl as (insert into guild_log (guild_id, at, text) select ${p(gc.log.guild_id)}::uuid, to_timestamp(${p(now)}::float8), ${p(gc.log.text)}
        from s returning 1)`)
    }
    if (gc.leave?.owner) {
      const gid = `${p(gc.leave.guild_id)}::uuid`
      const next = `(select player_id from player_guild where guild_id = ${gid} and player_id <> ${sid} order by joined_at, player_id limit 1)`
      ctes.push(`go as (update guilds set owner = ${next} where id = ${gid} and exists (select 1 from s) and ${next} is not null returning 1)`)
      ctes.push(`gd as (delete from guilds where id = ${gid} and exists (select 1 from s) and owner = ${sid} and ${next} is null returning 1)`)
    }
  }

  // 개정 18 던전·장비 변경의 CTE들(전부 from s — version 가드가 실패하면 아무것도 안 바뀐다).
  function dungeonCtes(ch: Change, now: number, ctes: string[], p: (v: unknown) => string) {
    const sid = '(select player_id from s)'
    if (ch.dungeon) {
      const d = ch.dungeon.state
      ctes.push(`dg as (insert into player_dungeons (player_id, type, best_level, keys, extra_today, last_reset)
        select player_id, ${p(ch.dungeon.type)}, ${p(d.best_level)}::int, ${p(d.keys)}::int, ${p(d.extra_today)}::int, to_timestamp(${p(d.last_reset)}::float8) from s
        on conflict (player_id, type) do update set best_level = excluded.best_level, keys = excluded.keys, extra_today = excluded.extra_today,
          last_reset = excluded.last_reset returning 1)`)
    }
    if (ch.runOpen) {
      // 한 번에 run 하나: 열린 run은 결과 없이 닫고(그 run의 finish는 409 run_closed), 하루 지난 run은 지운다
      const r = ch.runOpen
      const keep = p(now - RUN_KEEP_SEC)
      ctes.push(`ro0 as (update dungeon_runs set closed = true where player_id = ${sid} and not closed and started_at >= to_timestamp(${keep}::float8) returning 1)`)
      ctes.push(`ro1 as (delete from dungeon_runs where player_id = ${sid} and started_at < to_timestamp(${keep}::float8) returning 1)`)
      ctes.push(`ro2 as (insert into dungeon_runs (run_id, player_id, type, level, party, seed, started_at)
        select ${p(r.run_id)}::uuid, player_id, ${p(r.type)}, ${p(r.level)}::int, ${p(JSON.stringify(r.party))}::jsonb, ${p(r.seed)}::bigint, to_timestamp(${p(now)}::float8)
        from s returning 1)`)
    }
    if (ch.items?.length) {
      ctes.push(`it as (insert into player_items (player_id, slot, weapon_kind, grade, level, created_at)
        select s.player_id, x.slot, x.weapon_kind, x.grade, x.level, to_timestamp(${p(now)}::float8)
        from s, jsonb_to_recordset(${p(JSON.stringify(ch.items))}::jsonb) as x(slot text, weapon_kind text, grade text, level integer)
        returning id, slot, weapon_kind, grade, level)`)
    }
    if (ch.runClose) {
      // 결과 = {win, rewards}. 장비를 넣었으면 rewards.items에 새 id와 함께 남긴다(재전송이 같은 결과를 받는다)
      const res = `${p(JSON.stringify(ch.runClose.result))}::jsonb`
      const value = ch.items?.length
        ? `jsonb_set(${res}, '{rewards,items}', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'slot', slot, 'weapon_kind', weapon_kind,
            'grade', grade, 'level', level) order by id), '[]'::jsonb) from it))`
        : res
      ctes.push(`rc as (update dungeon_runs set closed = true, result = ${value}
        where run_id = ${p(ch.runClose.run_id)}::uuid and player_id = ${sid} and not closed returning result)`)
    }
    if (ch.sellItems?.length) {
      ctes.push(`si as (delete from player_items where player_id = ${sid}
        and id in (select x::bigint from jsonb_array_elements_text(${p(JSON.stringify(ch.sellItems))}::jsonb) as x) returning 1)`)
    }
    if (ch.equip) {
      const hero = p(ch.equip.hero_id)
      const slot = p(ch.equip.slot)
      if (ch.equip.item_id === null) {
        ctes.push(`eq as (delete from player_equipment where player_id = ${sid} and hero_id = ${hero} and slot = ${slot} returning 1)`)
      } else {
        // 다른 자리에서 빼고 이 자리에 끼운다 — item_id 유일은 문장 끝에 검사한다(012: deferrable)
        const item = p(String(ch.equip.item_id))
        ctes.push(`eq0 as (delete from player_equipment where player_id = ${sid} and item_id = ${item}::bigint
          and not (hero_id = ${hero} and slot = ${slot}) returning 1)`)
        ctes.push(`eq1 as (insert into player_equipment (player_id, hero_id, slot, item_id) select player_id, ${hero}, ${slot}, ${item}::bigint from s
          on conflict (player_id, hero_id, slot) do update set item_id = excluded.item_id returning 1)`)
      }
    }
  }

  function applyLocal(pl: Player, ch: Change) {
    pl.gold_tenths += ch.goldTenths ?? 0
    if (ch.stage !== undefined) pl.stage = ch.stage
    if (ch.lastKillReport !== undefined) pl.last_kill_report = ch.lastKillReport
    if (ch.lastStageClear !== undefined) pl.last_stage_clear = ch.lastStageClear
    if (ch.killSeq !== undefined) pl.kill_seq = ch.killSeq
    for (const [k, d] of Object.entries(ch.res ?? {})) pl.res[k] = (pl.res[k] ?? 0) + d
    for (const [k, t] of Object.entries(ch.buildings ?? {})) pl.buildings[k].last_collect = t
    for (const [k, t] of Object.entries(ch.train ?? {})) pl.buildings[k].train = t
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
    for (const [k, d] of Object.entries(ch.upgrades ?? {})) pl.upgrades[k] = (pl.upgrades[k] ?? 0) + d
    pl.diamonds += ch.diamonds ?? 0
    pl.gacha = { ...pl.gacha, ...ch.gacha }
    if (ch.research !== undefined) pl.research_cur = ch.research
    if (ch.researchUp) pl.research[ch.researchUp] = (pl.research[ch.researchUp] ?? 0) + 1
    for (const [k, d] of Object.entries(ch.shards ?? {})) if (pl.heroes[k]) pl.heroes[k].shards += d
    pl.version += 1
  }

  // reload: 쓴 뒤 플레이어를 다시 읽어 응답한다(applyLocal이 모르는 개정 18 변경). after: 쓴 결과 행으로 응답에 더할 값.
  type Plan = { change?: Change; extra?: Record<string, unknown>; reload?: boolean; after?: (r: Row) => Record<string, unknown> }

  // 읽기 → 계산 → 조건부 쓰기. 다른 요청이 먼저 바꿨으면(version 불일치) 다시 읽고 다시 계산한다.
  // pre: 플레이어를 읽은 뒤 시도마다 더 읽을 것(개정 18 run) — plan의 네 번째 인자.
  async function mutate(c: Context, plan: (p: Player, game: Game, now: number, ctx?: any) => Plan, pre?: (id: string) => Promise<unknown>) {
    const id = c.get('playerId') as string
    for (let i = 0; i < MAX_ATTEMPTS; i++) {
      const now = clock()
      const game = await loadGame()
      let pl = await loadPlayer(id, game, now)
      const { change, extra, reload, after } = plan(pl, game, now, pre ? await pre(id) : undefined)
      let more = {}
      if (change) {
        const r = await commit(id, pl.version, change, now)
        if (!r) continue
        if (reload) pl = await loadPlayer(id, game, now)
        else applyLocal(pl, change)
        if (after) more = after(r)
      }
      return c.json({ ...view(pl, game, now), ...extra, ...more })
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

  // 시작 영웅(새 플레이어). 시드 전 DB(마이그레이션만 적용)면 설정 행이 없다 — 마이그레이션 005와 같은 스펙 기본값을 쓴다(영웅 0명이 되지 않게)
  async function starters(): Promise<string[]> {
    const [cfg] = await query("select value from game_config where key = 'starter_heroes'")
    return String(cfg?.value ?? DEFAULT_STARTERS).split('|').map((x) => x.trim()).filter(Boolean)
  }

  async function issueToken(playerId: string, now: number): Promise<string> {
    const iat = Math.floor(now)
    return sign({ sub: playerId, iat, exp: iat + TOKEN_TTL }, secret, 'HS256')
  }

  app.post('/v1/auth/guest', async (c) => {
    const b = await body(c)
    const device = b.device_id
    if (typeof device !== 'string' || !DEVICE_RE.test(device)) {
      throw new ApiError(400, 'bad_device_id', 'device_id must be 16-128 characters of [A-Za-z0-9-]')
    }
    const now = clock()
    const [r] = await query(ENSURE_SQL, [device, now, JSON.stringify(await starters())])
    return c.json({ token: await issueToken(r.id, now), player_id: r.id })
  })

  // --- 소셜 로그인(Google·카카오·네이버, oauth.ts). 회원가입 없음 — 처음 로그인하면 계정이 생긴다 ---
  // 테스트 훅 서버(ALLOW_TEST_HOOKS)는 설정이 없으면 세 제공자를 가짜 키로 켠다 — /v1/test/oauth_complete로 앱 로그인 흐름을 끝까지 시험한다
  const oauth: O.OAuthConfig = opts.oauth ?? (opts.allowTestHooks ? O.TEST_CONFIG : { redirectBase: '', providers: {} })
  const fetchFn = opts.fetch ?? fetch

  // 켜진 제공자(로그인 화면이 버튼을 고를 때 쓸 수 있다)
  app.get('/v1/auth/providers', (c) => c.json({ providers: O.enabledProviders(oauth) }))

  // 로그인 시작 {provider, challenge = sha256(verifier) hex, device_id?}: 진행 행을 만들고 제공자 로그인 주소를 준다.
  // device_id가 있으면 그 기기의 게스트 계정에 이을 후보로 둔다(그 계정에 아직 소셜 계정이 없을 때만 콜백이 잇는다 — 진행 유지).
  app.post('/v1/auth/oauth/start', async (c) => {
    const b = await body(c)
    const provider = b.provider
    if (!O.isProvider(provider)) throw new ApiError(400, 'unknown_provider', `provider must be one of ${O.PROVIDERS.join(', ')}`)
    if (!O.enabledProviders(oauth).includes(provider)) throw new ApiError(503, 'provider_unavailable', `${provider} login is not configured on this server`)
    if (typeof b.challenge !== 'string' || !HEX64_RE.test(b.challenge)) throw new ApiError(400, 'bad_challenge', 'challenge must be 64 lowercase hex characters')
    const device = b.device_id
    if (device !== undefined && (typeof device !== 'string' || !DEVICE_RE.test(device))) throw new ApiError(400, 'bad_device_id', 'device_id must be 16-128 characters of [A-Za-z0-9-]')
    const now = clock()
    await query('delete from oauth_logins where created_at < to_timestamp($1::float8)', [now - 86400]) // 오래된 진행 행 정리
    let link: string | null = null
    if (typeof device === 'string') link = (await query('select id from players where device_id = $1', [device]))[0]?.id ?? null
    const state = randomBytes(32).toString('hex')
    await query('insert into oauth_logins (state, provider, challenge, link_player, created_at) values ($1, $2, $3, $4, to_timestamp($5::float8))',
      [state, provider, b.challenge, link, now])
    return c.json({ url: O.authorizeUrl(oauth, provider, state), state, expires_in: OAUTH_TTL })
  })

  // 제공자 → 서버 콜백(브라우저). code를 제공자 사용자 id로 바꾸고 플레이어를 찾거나 만들어 진행 행에 적는다. 결과는 안내 페이지.
  app.get('/v1/auth/:provider/callback', async (c) => {
    const p = c.req.param('provider')
    const state = c.req.query('state') ?? ''
    const code = c.req.query('code') ?? ''
    const page = (ok: boolean, status: number) => c.html(O.resultPage(ok), status as any)
    if (!O.isProvider(p) || !HEX64_RE.test(state)) return page(false, 400)
    const now = clock()
    const [row] = await query(`select provider, link_player, extract(epoch from created_at)::float8 as created_at, player_id, error
      from oauth_logins where state = $1`, [state])
    if (!row || row.provider !== p || row.player_id || row.error || now - Number(row.created_at) > OAUTH_TTL) return page(false, 400)
    const fail = async (error: string, status: number) => {
      await query('update oauth_logins set error = $2 where state = $1 and player_id is null', [state, error])
      return page(false, status)
    }
    if (c.req.query('error') || !code || !O.enabledProviders(oauth).includes(p)) return fail('denied', 200) // 사용자가 취소·거부
    let uid: string
    try {
      uid = await O.fetchUid(oauth, p, code, state, fetchFn)
    } catch (e) {
      console.warn(`[server] oauth: ${(e as Error).message}`)
      return fail('provider_error', 502)
    }
    const r = await resolvePlayer(p, uid, row.link_player ?? null, now)
    await query('update oauth_logins set player_id = $2, is_new = $3 where state = $1 and player_id is null and error is null', [state, r.id, r.isNew])
    return page(true, 200)
  })

  // 제공자 계정 → 플레이어: 이은 플레이어 → (없으면) 이을 게스트 계정(소셜 계정이 하나도 없을 때) → (없으면) 새 플레이어.
  async function resolvePlayer(p: O.Provider, uid: string, link: string | null, now: number): Promise<{ id: string; isNew: boolean }> {
    const known = async () => (await query('select player_id from player_identities where provider = $1 and provider_uid = $2', [p, uid]))[0]?.player_id
    const k = await known()
    if (k) return { id: String(k), isNew: false }
    const linkSql = `insert into player_identities (provider, provider_uid, player_id, created_at)
      select $1, $2, $3::uuid, to_timestamp($4::float8) where not exists (select 1 from player_identities where player_id = $3::uuid)
      on conflict do nothing returning player_id`
    if (link && (await query(linkSql, [p, uid, link, now])).length) return { id: link, isNew: false }
    const [made] = await query(ENSURE_SQL, [`oauth:${p}:${randomUUID()}`, now, JSON.stringify(await starters())])
    if ((await query(linkSql, [p, uid, made.id, now])).length) return { id: String(made.id), isNew: true }
    await query('delete from players where id = $1', [made.id]) // 같은 계정의 다른 로그인이 먼저 이었다 — 방금 만든 빈 계정은 지운다
    const again = await known()
    if (!again) throw new ApiError(409, 'conflict', 'concurrent login; try again')
    return { id: String(again), isNew: false }
  }

  // 결과 기다리기 {state, verifier}: 아직이면 202 {pending}. 끝났으면 한 번만 {token, player_id, session, provider, is_new}
  // — session은 자동 로그인 비밀(앱이 저장, 서버는 sha256만). 취소·거부 401 login_denied, 제공자 오류 401 login_failed, 시간 초과 410.
  app.post('/v1/auth/oauth/poll', async (c) => {
    const b = await body(c)
    if (typeof b.state !== 'string' || !HEX64_RE.test(b.state)) throw new ApiError(400, 'bad_state', 'state must be 64 lowercase hex characters')
    if (typeof b.verifier !== 'string' || !HEX64_RE.test(b.verifier)) throw new ApiError(400, 'bad_verifier', 'verifier must be 64 lowercase hex characters')
    const now = clock()
    const [row] = await query(`select provider, challenge, extract(epoch from created_at)::float8 as created_at, player_id, error, is_new
      from oauth_logins where state = $1`, [b.state])
    if (!row) throw new ApiError(404, 'unknown_login', 'no such login (finished or never started)')
    if (sha256hex(b.verifier) !== row.challenge) throw new ApiError(403, 'bad_verifier', 'verifier does not match')
    if (row.error) {
      await query('delete from oauth_logins where state = $1', [b.state])
      throw new ApiError(401, row.error === 'denied' ? 'login_denied' : 'login_failed', 'login was cancelled or failed')
    }
    if (!row.player_id) {
      if (now - Number(row.created_at) > OAUTH_TTL) {
        await query('delete from oauth_logins where state = $1', [b.state])
        throw new ApiError(410, 'login_expired', 'login took too long; start again')
      }
      return c.json({ pending: true }, 202)
    }
    const [done] = await query('delete from oauth_logins where state = $1 and player_id is not null returning player_id', [b.state])
    if (!done) throw new ApiError(404, 'unknown_login', 'no such login (finished or never started)')
    const session = randomBytes(32).toString('hex')
    await query('insert into player_sessions (hash, player_id, provider, created_at, last_used) values ($1, $2, $3, to_timestamp($4::float8), to_timestamp($4::float8))',
      [sha256hex(session), done.player_id, row.provider, now])
    return c.json({ token: await issueToken(String(done.player_id), now), player_id: done.player_id, session, provider: row.provider, is_new: row.is_new === true })
  })

  // 자동 로그인 {session} → 새 토큰. 모르는(로그아웃한) 세션이면 401 bad_session — 앱은 저장한 세션을 지우고 로그인 화면으로.
  app.post('/v1/auth/session', async (c) => {
    const b = await body(c)
    const now = clock()
    const s = typeof b.session === 'string' && HEX64_RE.test(b.session)
      ? (await query('update player_sessions set last_used = to_timestamp($2::float8) where hash = $1 returning player_id, provider', [sha256hex(b.session), now]))[0]
      : undefined
    if (!s) throw new ApiError(401, 'bad_session', 'session is unknown or logged out; log in again')
    await query('update players set last_seen = to_timestamp($2::float8) where id = $1', [s.player_id, now])
    return c.json({ token: await issueToken(String(s.player_id), now), player_id: s.player_id, provider: s.provider })
  })

  // 로그아웃 {session}: 그 세션만 지운다(다른 기기는 그대로). 몰라도 200.
  app.post('/v1/auth/logout', async (c) => {
    const b = await body(c)
    if (typeof b.session === 'string' && HEX64_RE.test(b.session)) await query('delete from player_sessions where hash = $1', [sha256hex(b.session)])
    return c.json({ ok: true })
  })

  app.get('/v1/gamedata', async (c) => {
    const g = await loadGame()
    const data = { monsters: g.monsters, stages: g.stages, heroes: g.heroes, resources: g.resources, buildings: g.buildings, soldiers: g.soldiers, upgrades: g.upgrades,
      dungeons: g.dungeons, equip_drop: g.equip_drop, research: g.research, config: g.config }
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
      const st = R.collectStep(b.last_collect, now, r.per_min, b.level, R.cfgNum(g.config, 'accum_cap_min'), R.researchProdPct(bonus(p, g), r.id))
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
        const pct = bonus(p, g).sell_pct
        let gold = 0
        const sold: Record<string, number> = {}
        const delta: Record<string, number> = {}
        for (const [id, amount] of want) {
          const r = g.resources.find((x) => x.id === id)
          if (!r) throw new ApiError(400, 'unknown_resource', `unknown resource '${id}'`)
          const have = p.res[id] ?? 0
          if (amount > have) throw new ApiError(409, 'not_enough', `only ${have} ${id} to sell`)
          gold += Math.floor(R.sellValue(amount, r.price, rates[id]) * (100 + pct) / 100) // 개정 24: 연구 sell_pct
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
      const pct = bonus(p, g).sell_pct
      let gold = 0
      const sold: Record<string, number> = {}
      const delta: Record<string, number> = {}
      for (const r of list) {
        const have = p.res[r.id] ?? 0
        if (want !== undefined && want > have) throw new ApiError(409, 'not_enough', `only ${have} ${r.id} to sell`)
        const amount = want ?? have
        if (amount <= 0) continue
        gold += Math.floor(R.sellValue(amount, r.price, rates[r.id]) * (100 + pct) / 100) // 개정 24: 연구 sell_pct
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
      const pct = bonus(p, g).kill_gold_pct // 개정 24: 처치 1회 tenths × (100 + kill_gold_pct) / 100, 내림
      const priced = entries.map(([id, n]) => ({ id, count: n as number, gold: Math.floor(R.killGoldTenths(Number(monsters.get(id).gold), row) * (100 + pct) / 100) }))
      const { kept, clamped } = R.clampKills(priced, bucket.cap)
      const tenths = priced.reduce((s, k) => s + kept[k.id] * k.gold, 0) // k.gold = 처치 1회 tenths
      const total = priced.reduce((s, k) => s + k.count, 0)
      const keptTotal = priced.reduce((s, k) => s + kept[k.id], 0)
      const log = total > 0 ? { kind: 'kills', detail: { seq, stage, asked_stage: askedStage, kills, kept, cap: bucket.cap, clamped, gold_tenths: tenths } } : undefined
      return { change: { goldTenths: tenths, lastKillReport: bucket.after(keptTotal), killSeq: seq, log }, extra: { gold_gained_tenths: tenths } }
    })
  })

  // 오프라인 처치 골드(앱을 켤 때·다시 돌아올 때 한 번): 지난 활동(last_active)부터 지금까지를 방치 처치로 쳐서(rules.offlineReward,
  // 현재 스테이지·연구 kill_gold_pct 반영) 골드 × offline_gold_mult를 준다. 활동 시각은 commit이 지금으로 옮긴다 — 다시 보내도 두 번 받지 않는다.
  // 응답 offline = {away_sec, kills, gold_gained_tenths}(away_sec는 상한 전 실제 초, 기록이 없으면 0).
  app.post('/v1/offline', auth, async (c) => {
    return mutate(c, (p, g, now) => {
      const away = p.last_active == null ? 0 : Math.max(0, now - p.last_active)
      const grunt = g.monsters.find((m) => m.id === R.OFFLINE_KIND)
      const row = R.stageRow(p.stage, g.stages)
      const per = grunt ? Math.floor(R.killGoldTenths(Number(grunt.gold), row) * (100 + bonus(p, g).kill_gold_pct) / 100) : 0
      const r = R.offlineReward(away, R.cfgNum(g.config, 'accum_cap_min'), Number(row.idle_interval), R.cfgNum(g.config, 'spawn_group'), per,
        R.cfgNum(g.config, 'offline_gold_mult'))
      const offline = { away_sec: away, kills: r.kills, gold_gained_tenths: r.tenths }
      const log = r.tenths > 0 ? { kind: 'offline', detail: { stage: p.stage, away_sec: away, sec: r.sec, kills: r.kills, gold_tenths: r.tenths } } : undefined
      return { change: { goldTenths: r.tenths, log }, extra: { offline } }
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
      const rb = bonus(p, g)
      let collect: { res: string; amount: number; from: number; to: number } | null = null
      if (rdef) {
        const b = p.buildings[building]
        const st = R.collectStep(b.last_collect, now, rdef.per_min, b.level, R.cfgNum(g.config, 'accum_cap_min'), R.researchProdPct(rb, rdef.id))
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
      const finish = now + R.roundHalfAway(R.buildSec(def, from) / (1 + rb.build_speed_pct / 100)) // 개정 24: 연구 build_speed_pct
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

  // 모집(스펙 §3.6·§3.7, 개정 23): currency = gold(생략 시, 하위 호환) | diamond. 골드 비용(정수)은 floor(gold_tenths / 10)로 판정하고
  // × 10을 뺀다(소수 부분은 남는다). 골드는 모집 레벨의 비용·확률을 쓰고 장수만큼 누적해 레벨업, 다이아는 다이아를 빼고 천장을 센다.
  // 재화 차감·영웅 copies·조각·모집 상태·economy_log는 version 가드 한 문장으로 같이 들어가거나 같이 안 들어간다.
  // 개정 15: 이미 가진 영웅이 다시 나오면 copies +1, 조각 +1. 결과 항목의 shards = 그 장까지 반영한 조각.
  app.post('/v1/gacha', auth, async (c) => {
    const b = await body(c)
    const count = b.count
    if (count !== 1 && count !== 10) throw new ApiError(400, 'bad_request', "'count' must be 1 or 10")
    const currency = b.currency ?? R.GACHA_GOLD
    if (typeof currency !== 'string' || !R.GACHA_CURRENCIES.includes(currency)) throw new ApiError(400, 'bad_request', "'currency' must be gold or diamond")
    const dia = currency === R.GACHA_DIA
    return mutate(c, (p, g) => {
      const lv = p.gacha.gold_level
      const cost = R.gachaCost(g.config, currency, count, lv)
      if (dia ? p.diamonds < cost : Math.floor(p.gold_tenths / 10) < cost) {
        throw new ApiError(409, dia ? 'not_enough_diamonds' : 'not_enough_gold', `recruiting ${count} costs ${cost} ${dia ? 'diamonds' : 'gold'}`)
      }
      const owned: Record<string, { copies: number; shards: number }> = {}
      for (const [id, h] of Object.entries(p.heroes)) owned[id] = { copies: h.copies, shards: h.shards }
      const add: Record<string, number> = {}
      const pity = dia ? { n: p.gacha.dia_pity, max: R.cfgNum(g.config, 'gacha_dia_pity') } : undefined
      const rates = R.gachaRates(g.config, currency, lv, level(p, R.TAVERN))
      const results = R.rollGacha(count, g.heroes, g.config, random, rates, pity).map(({ id, grade }) => {
        const o = owned[id]
        const isNew = !(o?.copies > 0)
        owned[id] = isNew ? { copies: 1, shards: 0 } : { copies: o.copies + 1, shards: o.shards + 1 }
        add[id] = (add[id] ?? 0) + 1
        return { hero_id: id, grade, new: isNew, copies: owned[id].copies, shards: owned[id].shards }
      })
      const up = R.goldLevelUp(g.config, lv, p.gacha.gold_pulls, count)
      const gacha = pity ? { dia_pity: pity.n } : { gold_level: up.level, gold_pulls: up.pulls }
      const paid = dia ? { diamonds: -cost } : { gold_tenths: -cost * 10 }
      const detail = { currency, count, cost, ...paid, level: lv, pity: p.gacha.dia_pity, after: gacha, results }
      return {
        change: { ...(dia ? { diamonds: -cost } : { goldTenths: -cost * 10 }), heroes: add, gacha, log: { kind: 'gacha', detail } },
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

  // 공용 업그레이드(개정 20 §4): count 1..100. 모르는 id는 404 unknown_upgrade, 최대 레벨을 넘으면 409 max_level, 골드가 모자라면 409 not_enough_gold.
  // 골드(정수, × 10 tenths) 차감·레벨·economy_log upgrade는 version 가드 한 문장 — 같이 들어가거나 같이 안 들어간다.
  app.post('/v1/upgrade', auth, async (c) => {
    const b = await body(c)
    const id = strField(b, 'id')
    const count = intField(b, 'count', 1, MAX_LEVELUP_COUNT)
    return mutate(c, (p, g) => {
      const def = g.upgrades.find((u) => u.id === id)
      if (!def) throw new ApiError(404, 'unknown_upgrade', `upgrade '${id}' does not exist`)
      const from = p.upgrades[id] ?? 0
      const to = from + count
      if (to > def.max_level) throw new ApiError(409, 'max_level', `level ${to} is above the max level ${def.max_level}`)
      const gold = R.upgradeCost(def, from, count)
      if (Math.floor(p.gold_tenths / 10) < gold) throw new ApiError(409, 'not_enough_gold', `levels ${from} -> ${to} cost ${gold} gold`)
      return {
        change: {
          goldTenths: -gold * 10, upgrades: { [id]: count },
          log: { kind: 'upgrade', detail: { id, from, to, count, gold, gold_tenths: -gold * 10 } },
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
      const pop = population(p, g)
      if (total > pop) throw new ApiError(400, 'bad_deploy', `deploying ${total} is above the population ${pop}`)
      return { change: { soldierDeploy: out } }
    })
  })

  // 훈련 시작(개정 16 §2): {building, count}. 병사 건물이 아니면 400 not_soldier_building, count가 1..묶음 상한(train_batch_*)이 아니면 400.
  // 대기열이 차 있으면 409 training(진행 중)·ready_to_collect(수령 대기), 자원이 모자라면 409 not_enough. 비용 차감·대기열(끝나는 시각 =
  // 지금 + count × 1마리 시간)·economy_log train_start는 version 가드 한 문장 — 같은 순간 두 번 보내도 하나는 409 training이다.
  app.post('/v1/soldiers/train', auth, async (c) => {
    const b = await body(c)
    const building = strField(b, 'building')
    const count = intField(b, 'count', 1, MAX_INT4)
    return mutate(c, (p, g, now) => {
      const s = soldierAt(g, building)
      const lv = level(p, building)
      const max = R.trainMax(g.config, lv)
      if (count > max) throw new ApiError(400, 'bad_request', `'count' must be an integer in 1..${max}`)
      const q = p.buildings[building].train
      if (q) throw new ApiError(409, q.finish > now ? 'training' : 'ready_to_collect', `'${building}' already has ${q.count} in training`)
      const tier = R.trainTier(g.config, lv)
      const rb = bonus(p, g) // 개정 24: 연구 train_cost_pct(비용 할인)·train_speed_pct(시간 ÷ (1 + b/100), 반올림 없음)
      const cost = R.trainCost(g.config, s.id, count, tier, rb.train_cost_pct)
      if (Object.entries(cost).some(([r, v]) => (p.res[r] ?? 0) < v)) throw new ApiError(409, 'not_enough', `training ${count} costs ${JSON.stringify(cost)}`)
      const unit = R.soldierUnitSec(g.config, lv)
      const train = { count, tier, finish: now + count * unit / (1 + rb.train_speed_pct / 100) }
      const res = Object.fromEntries(Object.entries(cost).filter(([, v]) => v > 0).map(([r, v]) => [r, -v]))
      return {
        change: { res, train: { [building]: train }, log: { kind: 'train_start', detail: { building, type: s.id, count, tier, level: lv, unit_sec: unit, cost, finish: train.finish } } },
        extra: { training: { building, ...train } },
      }
    })
  })

  // 훈련 수령(개정 16 §2): 끝났으면 그 묶음 티어 보유 += count, 대기열 비우기, economy_log train_collect(version 가드 한 문장).
  // 비었으면 409 empty, 아직이면 409 not_ready — 응답을 잃고 다시 보내도 두 번 받지 않는다(멱등).
  app.post('/v1/soldiers/collect', auth, async (c) => {
    const building = strField(await body(c), 'building')
    return mutate(c, (p, g, now) => {
      const s = soldierAt(g, building)
      const q = p.buildings[building].train
      if (!q) throw new ApiError(409, 'empty', `'${building}' has nothing in training`)
      if (q.finish > now) throw new ApiError(409, 'not_ready', `'${building}' finishes training at ${q.finish}`)
      return {
        change: { soldiers: { [R.soldierKey(s.id, q.tier)]: q.count }, train: { [building]: null }, log: { kind: 'train_collect', detail: { building, type: s.id, ...q } } },
        extra: { collected: { type: s.id, count: q.count, tier: q.tier } },
      }
    })
  })

  // 훈련 취소(개정 16 §2): 진행 중이면 비용의 50%(자원마다 내림)를 돌려주고 비운다. economy_log train_cancel. 비었으면 409 empty,
  // 이미 끝났으면 409 ready_to_collect(수령한다).
  // ponytail: 환불은 지금 설정의 비용으로 센다 — 시작 뒤 운영자가 비용을 바꾸면 낸 것과 다르다. 정확해야 하면 낸 비용을 대기열 열에 둔다.
  app.post('/v1/soldiers/cancel', auth, async (c) => {
    const building = strField(await body(c), 'building')
    return mutate(c, (p, g, now) => {
      const s = soldierAt(g, building)
      const q = p.buildings[building].train
      if (!q) throw new ApiError(409, 'empty', `'${building}' has nothing in training`)
      if (q.finish <= now) throw new ApiError(409, 'ready_to_collect', `'${building}' finished training; collect it`)
      const refund = R.trainRefund(R.trainCost(g.config, s.id, q.count, q.tier, bonus(p, g).train_cost_pct)) // 개정 24: 할인된 비용 기준
      return {
        change: {
          res: Object.fromEntries(Object.entries(refund).filter(([, v]) => v > 0)), train: { [building]: null },
          log: { kind: 'train_cancel', detail: { building, type: s.id, ...q, refund } },
        },
        extra: { refund },
      }
    })
  })

  // --- 연구 (개정 24 §3·§4) ---

  // 연구 시작 {id}: 모르는 노드 404 unknown_research → 진행 중 409 research_busy → 409 max_level / locked / not_enough_resources /
  // not_enough_gold(rules.researchBlock 순서). 비용(자원, 골드 × 10 tenths)을 전부 빼고 진행(끝나는 시각 = 지금 + 연구 시간)·
  // economy_log research start는 version 가드 한 문장 — 같은 순간 두 번 보내도 하나는 409 research_busy다.
  app.post('/v1/research/start', auth, async (c) => {
    const id = strField(await body(c), 'id')
    return mutate(c, (p, g, now) => {
      const def = g.research.find((d) => d.id === id)
      if (!def) throw new ApiError(404, 'unknown_research', `research '${id}' does not exist`)
      if (p.research_cur) throw new ApiError(409, 'research_busy', `'${p.research_cur.id}' is already being researched`)
      const lab = level(p, R.LAB)
      const from = p.research[id] ?? 0
      const why = R.researchBlock(def, p.research, lab, { ...p.res, gold: Math.floor(p.gold_tenths / 10) }, g.config)
      if (why) throw new ApiError(409, why, `cannot research '${id}' from level ${from}: ${why}`)
      const cost = R.researchCost(g.config, def, from)
      const sec = R.researchSec(g.config, def, from, R.researchSpeed(g.config, bonus(p, g), lab))
      const finish = now + sec
      const res = Object.fromEntries(R.BUILD_RES.filter((r) => cost[r] > 0).map((r) => [r, -cost[r]]))
      return {
        change: {
          goldTenths: -cost.gold * 10, res, research: { id, finish },
          log: { kind: 'research', detail: { action: 'start', id, level: from + 1, cost, sec, finish } },
        },
      }
    })
  })

  // 연구 취소: 진행 중이 아니면 409 no_research. 그 레벨 비용 × research_cancel_refund(자원·골드마다 내림)를 돌려주고 비운다.
  // ponytail: 환불은 지금 표·설정의 비용으로 센다(훈련 취소와 같다). 낸 비용과 정확히 같아야 하면 진행 열에 비용을 둔다.
  app.post('/v1/research/cancel', auth, async (c) => {
    return mutate(c, (p, g) => {
      const cur = p.research_cur
      if (!cur) throw new ApiError(409, 'no_research', 'nothing is being researched')
      const def = g.research.find((d) => d.id === cur.id)
      const refund = def ? R.researchRefund(g.config, R.researchCost(g.config, def, p.research[cur.id] ?? 0)) : {}
      const res = Object.fromEntries(R.BUILD_RES.filter((r) => refund[r] > 0).map((r) => [r, refund[r]]))
      return {
        change: {
          goldTenths: (refund.gold ?? 0) * 10, res, research: null,
          log: { kind: 'research', detail: { action: 'cancel', id: cur.id, level: (p.research[cur.id] ?? 0) + 1, refund } },
        },
        extra: { refund },
      }
    })
  })

  // 다이아 즉시 완료: 진행 중이 아니면 409 no_research, 다이아가 모자라면 409 not_enough_diamonds(비용 = max(1, ceil(남은 초 / 60) ×
  // research_dia_per_min)). 다이아 차감·진행 비우기·레벨 +1·economy_log research finish는 version 가드 한 문장.
  app.post('/v1/research/finish', auth, async (c) => {
    return mutate(c, (p, g, now) => {
      const cur = p.research_cur
      if (!cur) throw new ApiError(409, 'no_research', 'nothing is being researched')
      const cost = R.researchDiaCost(g.config, cur.finish, now)
      if (p.diamonds < cost) throw new ApiError(409, 'not_enough_diamonds', `finishing now costs ${cost} diamonds`)
      return {
        change: {
          diamonds: -cost, research: null, researchUp: cur.id,
          log: { kind: 'research', detail: { action: 'finish', id: cur.id, level: (p.research[cur.id] ?? 0) + 1, diamonds: cost } },
        },
        extra: { diamonds_spent: cost },
      }
    })
  })

  // --- 던전·장비 (개정 18 §6·§7) ---

  const bagFull = (p: Player, g: Game) => p.items.length + R.cfgNum(g.config, 'equip_drop_count') > R.cfgNum(g.config, 'equip_bag_cap')

  app.get('/v1/dungeon', auth, async (c) => {
    const now = clock()
    const game = await loadGame()
    const p = await loadPlayer(c.get('playerId') as string, game, now)
    return c.json({ server_now: now, dungeons: dungeonsView(p, game, now) })
  })

  app.get('/v1/items', auth, async (c) => {
    const now = clock()
    const game = await loadGame()
    const p = await loadPlayer(c.get('playerId') as string, game, now)
    return c.json({ server_now: now, items: p.items })
  })

  // 도전 시작(스펙 §6.1): {type, level, party}. 검사 순서 type·level 형식(400 bad_request) → party 형식(400 bad_party) → 단계 열림(409 locked:
  // 최고 + 1까지) → 인원(6/4)·중복·보유(400 bad_party) → 보관함(장비, 409 bag_full: 보유 + 드랍 수 > 상한) → 열쇠(409 no_key) — 장비 던전은
  // 열쇠가 없으면 골드 추가 도전 비용(409 not_enough_gold). 아무것도 소모하지 않는다(클리어 때). run을 만들고(열린 run은 닫는다) 응답에
  // run_id·seed·enemies(능력치)·started_at·time_limit·paid_with('key'|'gold')를 더한다.
  app.post('/v1/dungeon/start', auth, async (c) => {
    const b = await body(c)
    const type = b.type
    if (typeof type !== 'string' || !R.DUNGEON_TYPES.includes(type)) throw new ApiError(400, 'bad_request', `'type' must be ${R.DUNGEON_TYPES.join(' or ')}`)
    const lvl = intField(b, 'level', 1, R.MAX_DUNGEON_LEVEL)
    const party = b.party
    if (!Array.isArray(party) || party.some((x) => typeof x !== 'string' || x === '')) throw new ApiError(400, 'bad_party', "'party' must be an array of hero ids")
    return mutate(c, (p, g, now) => {
      const st = dungeonState(p, g, type, now)
      if (lvl > st.best_level + 1) throw new ApiError(409, 'locked', `level ${lvl} is locked (best ${st.best_level})`)
      const size = R.partySize(g.config, type)
      if (party.length !== size) throw new ApiError(400, 'bad_party', `the ${type} dungeon takes ${size} heroes`)
      if (new Set(party).size !== party.length) throw new ApiError(400, 'bad_party', 'a hero can go only once')
      const known = new Set(g.heroes.map((h) => String(h.id)))
      for (const id of party) if (!known.has(id) || !Object.hasOwn(p.heroes, id)) throw new ApiError(400, 'bad_party', `hero '${id}' is not owned`)
      if (type === 'equip' && bagFull(p, g)) throw new ApiError(409, 'bag_full', 'the item bag is full')
      if (st.keys < 1) {
        if (type !== 'equip') throw new ApiError(409, 'no_key', `no ${type} dungeon key left`)
        const cost = R.extraCost(g.config, st.extra_today)
        if (Math.floor(p.gold_tenths / 10) < cost) throw new ApiError(409, 'not_enough_gold', `an extra run costs ${cost} gold`)
      }
      const run = { run_id: randomUUID(), type, level: lvl, party: party as string[], seed: Math.floor(random() * 2 ** 31) }
      return {
        change: { runOpen: run },
        extra: {
          ...run, enemies: R.dungeonEnemies(g.dungeons, type, lvl, g.config), started_at: now, time_limit: R.cfgNum(g.config, 'dungeon_time_limit'),
          paid_with: st.keys >= 1 ? 'key' : 'gold',
        },
        reload: true,
      }
    })
  })

  // 결과(스펙 §6.3): {run_id, win, elapsed}. 없는 run(남의 run 포함) 404 unknown_run. 닫힌 run은 저장한 결과를 그대로 돌려준다(멱등,
  // repeated: true) — 다른 start가 닫은 run(결과 없음)은 409 run_closed. 30분이 지났으면 409 run_expired.
  // 패배: run만 닫는다. 승리: 타당성(elapsed ≥ 최소(골드 15·장비 20초), ≤ 제한 시간, 실제 경과 ≥ elapsed − 5 — 아니면 409 implausible, run은
  // 열린 채) → 열쇠(없으면 장비는 골드 추가 도전 비용, 409 no_key·not_enough_gold) → 보관함(409 bag_full). 열쇠·골드 차감, 보상(골드 tenths 또는
  // 장비 equip_drop_count개 — 암호학적 난수), 최고 단계, run 닫기(결과 저장), economy_log dungeon_clear는 version 가드 + 열린 run 가드 한 문장.
  app.post('/v1/dungeon/finish', auth, async (c) => {
    const b = await body(c)
    const runId = b.run_id
    if (typeof runId !== 'string' || !UUID_RE.test(runId)) throw new ApiError(400, 'bad_request', "'run_id' must be a run id")
    const win = b.win
    if (typeof win !== 'boolean') throw new ApiError(400, 'bad_request', "'win' must be true or false")
    const elapsed = b.elapsed
    if (typeof elapsed !== 'number' || !Number.isFinite(elapsed) || elapsed < 0 || elapsed > R.RUN_TTL_SEC) {
      throw new ApiError(400, 'bad_request', `'elapsed' must be seconds in 0..${R.RUN_TTL_SEC}`)
    }
    return mutate(c, (p, g, now, run: Run | null) => {
      if (!run) throw new ApiError(404, 'unknown_run', 'no such run')
      if (run.closed) {
        if (!run.result) throw new ApiError(409, 'run_closed', 'a newer run replaced this run')
        return { extra: { run_id: runId, win: run.result.win === true, rewards: run.result.rewards ?? {}, repeated: true } }
      }
      const real = now - run.started_at
      if (real > R.RUN_TTL_SEC) throw new ApiError(409, 'run_expired', 'the run expired')
      if (!win) {
        return { change: { runClose: { run_id: runId, result: { win: false, rewards: {} } } }, extra: { run_id: runId, win: false, rewards: {} }, reload: true }
      }
      const type = run.type
      const min = R.minClearSecOf(g.config, type)
      const limit = R.cfgNum(g.config, 'dungeon_time_limit')
      if (elapsed < min || elapsed > limit || real < elapsed - R.RUN_SLACK_SEC) {
        throw new ApiError(409, 'implausible', `a win needs ${min}..${limit} s of battle and as much real time (elapsed ${elapsed}, real ${real.toFixed(1)})`)
      }
      const st = dungeonState(p, g, type, now)
      const next = { ...st, best_level: Math.max(st.best_level, run.level) }
      let cost = 0
      if (st.keys >= 1) next.keys = st.keys - 1
      else if (type === 'equip') {
        cost = R.extraCost(g.config, st.extra_today)
        if (Math.floor(p.gold_tenths / 10) < cost) throw new ApiError(409, 'not_enough_gold', `an extra run costs ${cost} gold`)
        next.extra_today = st.extra_today + 1
      } else throw new ApiError(409, 'no_key', `no ${type} dungeon key left`)
      const rewards: Record<string, unknown> = {}
      let items: R.EquipItem[] = []
      let gain = 0
      if (type === 'gold') {
        gain = R.goldReward(g.config, run.level)
        rewards.gold_tenths = gain * 10
      } else {
        if (bagFull(p, g)) throw new ApiError(409, 'bag_full', 'the item bag is full')
        items = R.rollDrops(g.equip_drop, run.level, R.cfgNum(g.config, 'equip_drop_count'), R.cfgNum(g.config, 'equip_weapon_p'), random)
      }
      return {
        change: {
          goldTenths: (gain - cost) * 10, dungeon: { type, state: next }, items, runClose: { run_id: runId, result: { win: true, rewards } },
          log: {
            kind: 'dungeon_clear', detail: {
              run_id: runId, type, level: run.level, elapsed, real, party: run.party, paid: cost ? { gold: cost } : { key: 1 }, keys_after: next.keys,
              best_level: next.best_level, gold_tenths: gain * 10, items,
            },
          },
        },
        extra: { run_id: runId, win: true },
        reload: true,
        after: (r) => ({ rewards: json(r.run_result)?.rewards ?? rewards }),
      }
    }, (id) => loadRun(runId, id))
  })

  // 장착·해제(스펙 §7): {hero_id, slot, item_id|null}. 보유하지 않은 영웅 404 not_owned, 모르는 부위 400 bad_slot, 남의·없는 장비 404 unknown_item,
  // 부위가 다르면 409 wrong_slot, 무기는 그 영웅 모델의 종류만(409 wrong_weapon). 다른 영웅이 끼고 있으면 옮긴다. 같은 요청을 다시 보내도 같다(멱등).
  app.post('/v1/equip', auth, async (c) => {
    const b = await body(c)
    const heroId = strField(b, 'hero_id')
    const slot = strField(b, 'slot')
    if (!R.EQUIP_SLOTS.includes(slot)) throw new ApiError(400, 'bad_slot', `'slot' must be one of ${R.EQUIP_SLOTS.join(', ')}`)
    const itemId = b.item_id
    if (itemId !== null && !isInt(itemId, 1, Number.MAX_SAFE_INTEGER)) throw new ApiError(400, 'bad_request', "'item_id' must be an item id or null")
    return mutate(c, (p, g) => {
      const def = g.heroes.find((h) => h.id === heroId)
      if (!def || !Object.hasOwn(p.heroes, heroId)) throw new ApiError(404, 'not_owned', `hero '${heroId}' is not owned`)
      const cur = p.equipment.find((e) => e.hero_id === heroId && e.slot === slot)
      if (itemId === null) return cur ? { change: { equip: { hero_id: heroId, slot, item_id: null } }, reload: true } : {}
      const item = p.items.find((x) => x.id === itemId)
      if (!item) throw new ApiError(404, 'unknown_item', `item ${itemId} is not in the bag`)
      if (item.slot !== slot) throw new ApiError(409, 'wrong_slot', `item ${itemId} is a ${item.slot}, not a ${slot}`)
      if (slot === 'weapon' && item.weapon_kind !== R.WEAPON_OF[String(def.model)]) {
        throw new ApiError(409, 'wrong_weapon', `hero '${heroId}' (${def.model}) cannot use a ${item.weapon_kind}`)
      }
      if (cur?.item_id === itemId) return {}
      return { change: { equip: { hero_id: heroId, slot, item_id: itemId } }, reload: true }
    })
  })

  // 장비 판매(스펙 §5): {item_ids: [...]}(1..1000개, 겹치면 400). 남의·없는 장비 404 unknown_item, 장착 중이면 409 equipped(하나라도 그러면
  // 아무것도 안 판다). 값 = round(equip_sell_base × 등급 배율 × 레벨)의 합. 장비 삭제·골드·economy_log item_sell은 version 가드 한 문장.
  app.post('/v1/items/sell', auth, async (c) => {
    const ids = (await body(c)).item_ids
    if (!Array.isArray(ids) || ids.length < 1 || ids.length > MAX_SELL_ITEMS || ids.some((x) => !isInt(x, 1, Number.MAX_SAFE_INTEGER)) || new Set(ids).size !== ids.length) {
      throw new ApiError(400, 'bad_request', `'item_ids' must be 1..${MAX_SELL_ITEMS} distinct item ids`)
    }
    return mutate(c, (p, g) => {
      const byId = new Map(p.items.map((x) => [x.id, x]))
      let gold = 0
      for (const id of ids as number[]) {
        const it = byId.get(id)
        if (!it) throw new ApiError(404, 'unknown_item', `item ${id} is not in the bag`)
        if (p.equipment.some((e) => e.item_id === id)) throw new ApiError(409, 'equipped', `item ${id} is equipped`)
        gold += R.itemSellValue(g.config, it)
      }
      return {
        change: { goldTenths: gold * 10, sellItems: ids, log: { kind: 'item_sell', detail: { items: ids.map((id) => byId.get(id)), gold, gold_tenths: gold * 10 } } },
        extra: { gold_gained: gold },
        reload: true,
      }
    })
  })

  // --- 길드(server/src/guild.ts, 마이그레이션 020) ---
  // 모든 응답 = 플레이어 응답 + guild(guildView). 쓰기는 version 가드 한 문장(commit의 guild CTE). 막힘은 409(코드 = 앱 문구 키).

  interface GuildRow { id: string; name: string; emblem: number; notice: string; owner: string | null; seed: number; created_at: number; virtual_n: number; exp: number; boss_damage: number }
  interface PgRow { guild_id: string | null; joined_at: number | null; coins: number; mine: Partial<G.Mine> | null; boss_seen: number; power: number; last_active: number | null }
  interface GuildCtx {
    id: string; pl: Player; game: Game; now: number; hour: number; mine: G.Mine; pg: PgRow; g: GuildRow | null; st: ReturnType<typeof guildState> | null
    members: (PgRow & { player_id: string })[]; dps: number; power: number
  }

  const GUILD_COLS = `id::text, name, emblem, notice, owner::text, seed, extract(epoch from created_at)::float8 as created_at, virtual_n, exp, boss_damage`
  const toGuild = (r: Row): GuildRow => ({
    id: String(r.id), name: String(r.name), emblem: Number(r.emblem), notice: String(r.notice), owner: r.owner == null ? null : String(r.owner),
    seed: Number(r.seed), created_at: Number(r.created_at), virtual_n: Number(r.virtual_n), exp: Number(r.exp), boss_damage: Number(r.boss_damage),
  })
  const PG_COLS = `player_id::text, guild_id::text, extract(epoch from joined_at)::float8 as joined_at, coins, mine, boss_seen, power,
    extract(epoch from last_active)::float8 as last_active`
  const toPg = (r: Row | undefined): PgRow & { player_id: string } => ({
    player_id: String(r?.player_id ?? ''), guild_id: r?.guild_id == null ? null : String(r.guild_id), joined_at: r?.joined_at == null ? null : Number(r.joined_at),
    coins: Number(r?.coins ?? 0), mine: r?.mine ? json(r.mine) : null, boss_seen: Number(r?.boss_seen ?? 1), power: Number(r?.power ?? 0),
    last_active: r?.last_active == null ? null : Number(r.last_active),
  })

  function guildState(g: GuildRow, now: number, hour: number) {
    const vt = G.virtualTotals({ id: g.id, seed: g.seed, created_at: g.created_at, virtual_n: g.virtual_n, system: g.owner == null && g.virtual_n >= G.SYSTEM_VIRTUAL[0] }, now, hour)
    return { vt, lv: G.levelOf(g.exp + vt.exp), boss: G.bossOf(g.boss_damage + vt.dmg) }
  }

  async function guildCtx(id: string, pl: Player, game: Game, now: number): Promise<GuildCtx> {
    const hour = R.cfgNum(game.config, 'daily_reset_utc_hour')
    const [pr] = await query(`select ${PG_COLS} from player_guild where player_id = $1`, [id])
    const pg = toPg(pr)
    let g: GuildRow | null = null
    let members: GuildCtx['members'] = []
    if (pg.guild_id) {
      const [gr] = await query(`select ${GUILD_COLS} from guilds where id = $1`, [pg.guild_id])
      if (gr) {
        g = toGuild(gr)
        members = (await query(`select ${PG_COLS} from player_guild where guild_id = $1 order by joined_at, player_id`, [g.id])).map(toPg)
      } else pg.guild_id = null
    }
    const st = g ? guildState(g, now, hour) : null
    const cfg = (k: string) => R.cfgNum(game.config, k)
    const slots = R.heroSlots(game.config, level(pl, R.KEEP))
    const deploy = Array.from({ length: slots }, (_, i) => pl.deploy[i]).filter((x): x is string => typeof x === 'string' && Object.hasOwn(pl.heroes, x))
    const defs = game.heroes.map((h) => ({ id: String(h.id), role: String(h.role), atk: Number(h.atk), hp: Number(h.hp), atk_interval: Number(h.atk_interval), grade: String(h.grade) }))
    const up = (uid: string) => {
      const d = game.upgrades.find((u) => u.id === uid)
      return d ? Math.min(pl.upgrades[uid] ?? 0, Number(d.max_level)) * Number(d.per_level) / 100 : 0
    }
    const buff = st ? G.buffPct(st.lv.level) : 0
    return {
      id, pl, game, now, hour, mine: G.mineToday(pg.mine, now, hour), pg, g, st, members,
      dps: G.teamDps(deploy, pl.heroes, defs, cfg, up('atk'), up('aspd'), buff), power: G.teamPower(deploy, pl.heroes, defs, cfg),
    }
  }

  // 추천 길드: 자리가 있는 길드(실제 길드원 < 30 − 가상), 시스템 길드가 RECOMMEND_N보다 적으면 만든다.
  async function recommendations(x: GuildCtx) {
    const open = `select ${GUILD_COLS}, (select count(*)::int from player_guild m where m.guild_id = g.id) as real_n from guilds g`
    let rows = (await query(`${open} where (select count(*) from player_guild m where m.guild_id = g.id) < ${G.MAX_MEMBERS} - g.virtual_n
      order by (owner is null), md5(g.id::text || $1) limit ${G.RECOMMEND_N * 2}`, [String(x.mine.day)]))
    const system = rows.filter((r) => r.owner == null).length
    for (let k = system; k < G.RECOMMEND_N; k++) {
      const seed = Math.floor(random() * 2 ** 31)
      const sg = G.systemGuild(seed, x.now)
      await query(`insert into guilds (name, emblem, notice, owner, seed, created_at, virtual_n) values ($1, $2, $3, null, $4, to_timestamp($5::float8), $6)
        on conflict (name) do nothing`, [sg.name, sg.emblem, sg.notice, seed, sg.created_at, sg.virtual_n])
    }
    if (system < G.RECOMMEND_N) rows = await query(`${open} where (select count(*) from player_guild m where m.guild_id = g.id) < ${G.MAX_MEMBERS} - g.virtual_n
      order by (owner is null), md5(g.id::text || $1) limit ${G.RECOMMEND_N * 2}`, [String(x.mine.day)])
    return rows.slice(0, G.RECOMMEND_N).map((r) => {
      const g = toGuild(r)
      const st = guildState(g, x.now, x.hour)
      const vm = st.vt.members.filter((m) => m.join_t <= x.now)
      const powers = vm.map((m) => st.vt.day[m.i].power)
      return {
        id: g.id, name: g.name, emblem: g.emblem, level: st.lv.level, notice: g.notice, count: vm.length + Number(r.real_n),
        power: powers.length ? Math.round(powers.reduce((a, b) => a + b, 0) / powers.length) : 0,
      }
    })
  }

  async function guildView(x: GuildCtx) {
    const out: Record<string, unknown> = {
      unlocked: x.pl.stage >= G.UNLOCK_STAGE, coins: x.pg.coins, me: x.mine, dps: Math.round(x.dps), power: x.power,
      next_reset: R.nextReset(x.now, x.game.config), guild: null, boss_pending: 0,
    }
    if (!x.g || !x.st) {
      if (x.pl.stage >= G.UNLOCK_STAGE) out.recommendations = await recommendations(x)
      return out
    }
    const g = x.g
    const st = x.st
    const members: Record<string, unknown>[] = []
    let att = x.mine.attended ? 1 : 0
    for (const m of x.members) {
      if (m.player_id === x.id) continue
      const mm = G.mineToday(m.mine, x.now, x.hour)
      if (mm.attended) att++
      members.push({ name: G.playerName(m.player_id), role: m.player_id === g.owner ? '길드장' : '길드원', power: m.power, contrib: mm.contrib, att: mm.attended,
        dmg: mm.boss_total, last: m.last_active ?? 0, real: true })
    }
    for (const vm of st.vt.members) {
      if (vm.join_t > x.now) continue
      const d = st.vt.day[vm.i]
      if (d.att) att++
      const role = g.owner != null && vm.role === '길드장' ? '정예' : vm.role
      members.push({ name: vm.name, role, power: d.power, contrib: d.contrib, att: d.att, dmg: d.dmg, last: d.last })
    }
    const logs = (await query(`select extract(epoch from at)::float8 as t, text from guild_log where guild_id = $1 and at > to_timestamp($2::float8)
      order by at desc limit 20`, [g.id, x.now - 2 * 86400])).map((r) => ({ t: Number(r.t), text: String(r.text) }))
    const log = [...logs, ...st.vt.log].sort((a, b) => a.t - b.t).slice(-30)
    out.boss_pending = Math.max(0, Math.min(G.BOSS_CLAIM_MAX, st.boss.level - x.pg.boss_seen))
    out.guild = {
      id: g.id, name: g.name, emblem: g.emblem, notice: g.notice, mine: g.owner === x.id, level: st.lv.level, exp: st.lv.exp, need: st.lv.need,
      buff: G.buffPct(st.lv.level), boss: { level: st.boss.level, hp: st.boss.hp, max: st.boss.max }, members, attend_count: att, log,
      capacity: G.MAX_MEMBERS,
    }
    return out
  }

  // 길드 쓰기: 읽기 → plan(막히면 ApiError) → commit(version 가드) → 다시 읽어 응답. 겨루면 다시.
  async function guildMutate(c: Context, plan: (x: GuildCtx) => { change?: Change; result?: Record<string, unknown> } | Promise<{ change?: Change; result?: Record<string, unknown> }>) {
    const id = c.get('playerId') as string
    for (let i = 0; i < MAX_ATTEMPTS; i++) {
      const now = clock()
      const game = await loadGame()
      let pl = await loadPlayer(id, game, now)
      let x = await guildCtx(id, pl, game, now)
      const { change, result } = await plan(x)
      if (change) {
        if (!(await commit(id, pl.version, change, now))) continue
        pl = await loadPlayer(id, game, now)
        x = await guildCtx(id, pl, game, now)
      }
      return c.json({ ...view(pl, game, now), guild: await guildView(x), ...(result ? { result } : {}) })
    }
    throw new ApiError(409, 'conflict', 'concurrent update; try again')
  }

  const blocked = (code: string, msg: string) => new ApiError(409, code, msg)
  const rowOf = (x: GuildCtx, over: Partial<GuildChange['row']> = {}): GuildChange['row'] => ({
    guild_id: x.pg.guild_id, joined_at: x.pg.joined_at, coins: x.pg.coins, mine: x.mine, boss_seen: x.pg.boss_seen, power: x.power, ...over,
  })
  const needGuild = (x: GuildCtx) => {
    if (!x.g || !x.st) throw blocked('no_guild', 'join a guild first')
    return { g: x.g, st: x.st }
  }
  // 보상 → Change 조각(골드·다이아·식량·조각; 코인은 row로)
  function grant(x: GuildCtx, give: Record<string, number>, ch: Change, coins: { n: number }) {
    for (const [k, n] of Object.entries(give)) {
      if (k === 'coins') coins.n += n
      else if (k === 'gold') ch.goldTenths = (ch.goldTenths ?? 0) + n * 10
      else if (k === 'diamonds') ch.diamonds = (ch.diamonds ?? 0) + n
      else if (k === 'food') ch.res = { ...(ch.res ?? {}), food: (ch.res?.food ?? 0) + n }
      else if (k === 'shards' || k === 'ssr_shards') {
        const pool = Object.keys(x.pl.heroes).filter((id) => x.game.heroes.some((h) => h.id === id && (k === 'shards' || h.grade === 'SSR'))).sort()
        for (let i = 0; i < n && pool.length; i++) {
          const id = pool[Math.floor(random() * pool.length)]
          ch.shards = { ...(ch.shards ?? {}), [id]: (ch.shards?.[id] ?? 0) + 1 }
        }
      }
    }
  }

  app.get('/v1/guild', auth, async (c) => {
    const id = c.get('playerId') as string
    const now = clock()
    const game = await loadGame()
    const pl = await loadPlayer(id, game, now)
    return c.json({ server_now: now, guild: await guildView(await guildCtx(id, pl, game, now)) })
  })

  app.post('/v1/guild/join', auth, async (c) => {
    const gid = strField(await body(c), 'guild_id')
    if (!UUID_RE.test(gid)) throw new ApiError(400, 'bad_request', "'guild_id' must be a uuid")
    return guildMutate(c, async (x) => {
      if (x.pl.stage < G.UNLOCK_STAGE) throw blocked('locked', 'clear round 1-10 first')
      if (x.g) throw blocked('in_guild', 'already in a guild')
      const [gr] = await query(`select ${GUILD_COLS} from guilds where id = $1`, [gid])
      if (!gr) throw new ApiError(404, 'no_such_guild', 'guild not found')
      const g = toGuild(gr)
      const [{ n }] = await query('select count(*)::int as n from player_guild where guild_id = $1', [gid])
      if (Number(n) >= G.MAX_MEMBERS - g.virtual_n) throw blocked('full', 'guild is full')
      const st = guildState(g, x.now, x.hour)
      return { change: { guild: { row: rowOf(x, { guild_id: gid, joined_at: x.now, boss_seen: st.boss.level }), log: { guild_id: gid, text: `${G.playerName(x.id)}님이 길드에 가입했습니다` } } } }
    })
  })

  app.post('/v1/guild/create', auth, async (c) => {
    const b = await body(c)
    const name = strField(b, 'name').trim()
    const emblem = intField(b, 'emblem', 0, G.EMBLEMS - 1)
    if ([...name].length < 2 || [...name].length > 8) throw new ApiError(400, 'bad_name', 'name must be 2-8 characters')
    return guildMutate(c, async (x) => {
      if (x.pl.stage < G.UNLOCK_STAGE) throw blocked('locked', 'clear round 1-10 first')
      if (x.g) throw blocked('in_guild', 'already in a guild')
      if (x.pl.gold_tenths < G.CREATE_GOLD * 10) throw blocked('not_enough_gold', `creating a guild costs ${G.CREATE_GOLD} gold`)
      const [taken] = await query('select 1 from guilds where name = $1', [name])
      if (taken) throw blocked('name_taken', 'guild name is taken')
      const gid = randomUUID()
      return {
        change: {
          goldTenths: -G.CREATE_GOLD * 10,
          guild: {
            create: { id: gid, name, emblem, seed: Math.floor(random() * 2 ** 31), virtual_n: G.CREATED_VIRTUAL, notice: G.CREATED_NOTICE },
            row: rowOf(x, { guild_id: gid, joined_at: x.now, boss_seen: 1 }), log: { guild_id: gid, text: `${G.playerName(x.id)}님이 길드를 창설했습니다` },
          },
          log: { kind: 'guild', detail: { action: 'create', name, gold: G.CREATE_GOLD } },
        },
      }
    })
  })

  app.post('/v1/guild/leave', auth, async (c) => guildMutate(c, (x) => {
    const { g } = needGuild(x)
    return {
      change: {
        guild: {
          row: rowOf(x, { guild_id: null, joined_at: null, mine: { ...x.mine, contrib: 0, boxes: [] } }),
          log: { guild_id: g.id, text: `${G.playerName(x.id)}님이 길드를 떠났습니다` }, leave: { guild_id: g.id, owner: g.owner === x.id },
        },
      },
    }
  }))

  app.post('/v1/guild/attend', auth, async (c) => guildMutate(c, (x) => {
    const { g } = needGuild(x)
    if (x.mine.attended) throw blocked('attended', 'already attended today')
    const ch: Change = {}
    const coins = { n: x.pg.coins }
    grant(x, G.ATTEND_REWARD, ch, coins)
    ch.guild = {
      row: rowOf(x, { coins: coins.n, mine: { ...x.mine, attended: true, contrib: x.mine.contrib + G.ATTEND_EXP } }),
      add: { guild_id: g.id, exp: G.ATTEND_EXP, dmg: 0 }, log: { guild_id: g.id, text: `${G.playerName(x.id)}님이 출석했습니다` },
    }
    return { change: ch }
  }))

  app.post('/v1/guild/box', auth, async (c) => {
    const index = intField(await body(c), 'index', 0, G.ATTEND_BOXES.length - 1)
    return guildMutate(c, async (x) => {
      needGuild(x)
      if (x.mine.boxes.includes(index)) throw blocked('claimed', 'box already claimed')
      const v = await guildView(x)
      if (!x.mine.attended || Number((v.guild as any).attend_count) < G.ATTEND_BOXES[index][0]) throw blocked('locked', 'not enough attendance yet')
      const ch: Change = {}
      const coins = { n: x.pg.coins }
      grant(x, G.ATTEND_BOXES[index][1], ch, coins)
      ch.guild = { row: rowOf(x, { coins: coins.n, mine: { ...x.mine, boxes: [...x.mine.boxes, index] } }) }
      return { change: ch }
    })
  })

  app.post('/v1/guild/donate', auth, async (c) => {
    const kind = strField(await body(c), 'kind')
    const d = G.DONATIONS[kind]
    if (!d) throw new ApiError(400, 'bad_kind', `unknown donation '${kind}'`)
    return guildMutate(c, (x) => {
      const { g } = needGuild(x)
      if ((x.mine.donations[kind] ?? 0) >= d.daily) throw blocked('donated', 'no donations left today')
      if (x.pl.gold_tenths < d.gold * 10) throw blocked('not_enough_gold', 'not enough gold')
      if (x.pl.diamonds < d.diamonds) throw blocked('not_enough_diamonds', 'not enough diamonds')
      const mine = { ...x.mine, donations: { ...x.mine.donations, [kind]: (x.mine.donations[kind] ?? 0) + 1 }, contrib: x.mine.contrib + d.exp }
      return {
        change: {
          goldTenths: d.gold ? -d.gold * 10 : undefined, diamonds: d.diamonds ? -d.diamonds : undefined,
          guild: { row: rowOf(x, { coins: x.pg.coins + d.coins, mine }), add: { guild_id: g.id, exp: d.exp, dmg: 0 },
            log: { guild_id: g.id, text: `${G.playerName(x.id)}님이 ${d.name}를 했습니다` } },
        },
      }
    })
  })

  // 보스 전투 시작: 도전 1회를 쓰고 전투 표(run_id·초·단계·HP)를 준다. 앱이 영웅으로 드래곤과 싸운 뒤 /boss/finish로 피해를 낸다.
  app.post('/v1/guild/boss/start', auth, async (c) => guildMutate(c, (x) => {
    const { st } = needGuild(x)
    if (x.mine.boss_tries >= G.BOSS_TRIES) throw blocked('no_tries', 'no boss tries left today')
    if (x.dps <= 0) throw blocked('no_heroes', 'no heroes deployed')
    const run = { id: randomUUID(), t: x.now, cap: Math.round(x.dps * G.BOSS_FIGHT_SEC * G.BOSS_DMG_CAP), level: st.boss.level }
    const mine = { ...x.mine, boss_tries: x.mine.boss_tries + 1, boss_run: run }
    return { change: { guild: { row: rowOf(x, { mine }) } },
      result: { run_id: run.id, sec: G.BOSS_FIGHT_SEC, level: st.boss.level, hp: st.boss.hp, max: st.boss.max } }
  }))

  // 보스 전투 끝: 앱이 낸 피해(상한 cap)로 등급·보상·길드 누적 피해. 너무 이르면 too_early, 오래 지났으면 피해 0.
  app.post('/v1/guild/boss/finish', auth, async (c) => {
    const b = await body(c)
    const runId = strField(b, 'run_id')
    const sent = intField(b, 'dmg', 0, 1e12)
    return guildMutate(c, (x) => {
      const { g, st } = needGuild(x)
      const run = x.mine.boss_run
      if (!run || run.id !== runId) throw blocked('no_run', 'no such boss fight')
      const age = x.now - run.t
      if (age < G.BOSS_FIGHT_SEC - G.BOSS_SLACK_SEC) throw blocked('too_early', `the fight lasts ${G.BOSS_FIGHT_SEC} s (${age.toFixed(1)} s so far)`)
      const dmg = age > G.BOSS_RUN_TTL ? 0 : Math.min(sent, run.cap)
      const before = st.boss.level
      const grade = G.bossGrade(dmg, run.level)
      const after = G.bossOf(g.boss_damage + st.vt.dmg + dmg).level
      const ch: Change = {}
      const coins = { n: x.pg.coins }
      grant(x, { coins: grade[2], gold: grade[3] }, ch, coins)
      const mine = { ...x.mine, boss_run: null, boss_best: Math.max(x.mine.boss_best, dmg), boss_total: x.mine.boss_total + dmg, contrib: x.mine.contrib + 10 }
      ch.guild = { row: rowOf(x, { coins: coins.n, mine }), add: { guild_id: g.id, exp: 0, dmg },
        log: { guild_id: g.id, text: `${G.playerName(x.id)}님이 ${G.bossName(before)}에게 ${dmg.toLocaleString('en-US')} 피해` } }
      return { change: ch, result: { dmg, sent, grade: grade[0], coins: grade[2], gold: grade[3], level: run.level, killed: after - before } }
    })
  })

  app.post('/v1/guild/claim', auth, async (c) => guildMutate(c, (x) => {
    const { st } = needGuild(x)
    const n = Math.min(G.BOSS_CLAIM_MAX, st.boss.level - x.pg.boss_seen)
    if (n <= 0) throw blocked('nothing', 'no boss kill rewards')
    const ch: Change = { diamonds: G.BOSS_KILL_REWARD.diamonds * n }
    ch.guild = { row: rowOf(x, { coins: x.pg.coins + G.BOSS_KILL_REWARD.coins * n, boss_seen: st.boss.level }) }
    return { change: ch, result: { kills: n, coins: G.BOSS_KILL_REWARD.coins * n, diamonds: G.BOSS_KILL_REWARD.diamonds * n } }
  }))

  app.post('/v1/guild/buy', auth, async (c) => {
    const itemId = strField(await body(c), 'id')
    const it = G.SHOP.find((s) => s.id === itemId)
    if (!it) throw new ApiError(400, 'bad_item', `unknown shop item '${itemId}'`)
    return guildMutate(c, (x) => {
      const bag = it.period === 'day' ? x.mine.shop_day : x.mine.shop_week
      if ((bag.bought[it.id] ?? 0) >= it.limit) throw blocked('sold_out', 'purchase limit reached')
      if (x.pg.coins < it.price) throw blocked('not_enough_coins', 'not enough guild coins')
      const ch: Change = {}
      const coins = { n: x.pg.coins - it.price }
      grant(x, it.give, ch, coins)
      if ((it.give.shards || it.give.ssr_shards) && !ch.shards) throw blocked('no_heroes', 'no hero to receive shards')
      const nb = { ...bag, bought: { ...bag.bought, [it.id]: (bag.bought[it.id] ?? 0) + 1 } }
      const mine = it.period === 'day' ? { ...x.mine, shop_day: nb as G.Mine['shop_day'] } : { ...x.mine, shop_week: nb as G.Mine['shop_week'] }
      ch.guild = { row: rowOf(x, { coins: coins.n, mine }) }
      return { change: ch, result: { shards: ch.shards ?? {} } }
    })
  })

  if (opts.allowTestHooks) {
    // 통합 테스트용(개정 18): 열린 run의 시작 시각을 seconds초 앞당긴다 — 즉시 승리 훅(앱 Economy.debug_win)이 타당성 검사를 지나게.
    app.post('/v1/test/dungeon_age', auth, async (c) => {
      const b = await body(c)
      const runId = b.run_id
      if (typeof runId !== 'string' || !UUID_RE.test(runId)) throw new ApiError(400, 'bad_request', "'run_id' must be a run id")
      const seconds = intField(b, 'seconds', 0, R.RUN_TTL_SEC)
      const id = c.get('playerId') as string
      await query(`update dungeon_runs set started_at = started_at - $3::float8 * interval '1 second' where run_id = $2 and player_id = $1 and not closed`, [id, runId, seconds])
      const now = clock()
      const game = await loadGame()
      return c.json(view(await loadPlayer(id, game, now), game, now))
    })

    // 통합 테스트용(개정 18): 영웅 한 명을 보유하게 한다(골드 던전 6명 편성 — 서버 모집은 암호학적 난수라 정할 수 없다). 이미 있으면 그대로.
    app.post('/v1/test/grant_hero', auth, async (c) => {
      const heroId = strField(await body(c), 'hero_id')
      const id = c.get('playerId') as string
      await query(`with s as (update player_state set version = version + 1 where player_id = $1 returning player_id)
        insert into player_heroes (player_id, hero_id) select player_id, $2 from s on conflict do nothing`, [id, heroId])
      const now = clock()
      const game = await loadGame()
      return c.json(view(await loadPlayer(id, game, now), game, now))
    })

    // 통합 테스트용(소셜 로그인): 제공자 없이 진행 중 로그인을 끝낸다 {state, provider_uid} 또는 {state, error: "denied"} — 콜백과 같은 처리.
    app.post('/v1/test/oauth_complete', async (c) => {
      const b = await body(c)
      const [row] = await query('select provider, link_player from oauth_logins where state = $1 and player_id is null and error is null', [String(b.state ?? '')])
      if (!row) throw new ApiError(404, 'unknown_login', 'no pending login with that state')
      if (b.error !== undefined) {
        await query('update oauth_logins set error = $2 where state = $1', [b.state, String(b.error)])
        return c.json({ ok: true })
      }
      const r = await resolvePlayer(row.provider, strField(b, 'provider_uid'), row.link_player ?? null, clock())
      await query('update oauth_logins set player_id = $2, is_new = $3 where state = $1', [b.state, r.id, r.isNew])
      return c.json({ ok: true, player_id: r.id, is_new: r.isNew })
    })

    // 통합 테스트용: 그 플레이어 건물의 last_collect(자원 건물 수집)와 훈련 끝나는 시각(개정 16), 연구 끝나는 시각(개정 24)을 minutes분 앞당긴다.
    app.post('/v1/test/age', auth, async (c) => {
      const minutes = intField(await body(c), 'minutes', 0, MAX_AGE_MIN)
      const id = c.get('playerId') as string
      await query(`with s as (update player_state set version = version + 1, research_finish = research_finish - $2::float8 * interval '1 second'
          where player_id = $1 returning player_id)
        update player_buildings set last_collect = last_collect - $2::float8 * interval '1 second', train_finish = train_finish - $2::float8 * interval '1 second'
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

    // 통합 테스트용(개정 19): 병사 건물 레벨을 바로 정한다(막사 Lv 7 = T2를 6번 업그레이드 없이 본다). 병사 건물이 아니면 400.
    app.post('/v1/test/barracks_level', auth, async (c) => {
      const level = intField(await body(c), 'level', 1, 30)
      const id = c.get('playerId') as string
      await query(`with s as (update player_state set version = version + 1 where player_id = $1 returning player_id)
        update player_buildings set level = $2 where player_id = (select player_id from s) and building = 'barracks'`, [id, level])
      const now = clock()
      const game = await loadGame()
      return c.json(view(await loadPlayer(id, game, now), game, now))
    })

    // 개정 23: 다이아·골드를 amount만큼 준다(실결제는 범위 밖 — 개발·통합 테스트용). 골드 모집 레벨업은 30회 × 3,000골드가 든다.
    for (const [path, set] of [['grant_diamonds', 'diamonds = diamonds + $2::bigint'], ['grant_gold', 'gold_tenths = gold_tenths + $2::bigint * 10']]) {
      app.post(`/v1/test/${path}`, auth, async (c) => {
        const amount = intField(await body(c), 'amount', 1, 1_000_000_000)
        const id = c.get('playerId') as string
        await query(`update player_state set version = version + 1, ${set} where player_id = $1`, [id, amount])
        const now = clock()
        const game = await loadGame()
        return c.json(view(await loadPlayer(id, game, now), game, now))
      })
    }

    // 통합 테스트용(길드): 스테이지를 바로 정한다(길드는 1-10 클리어 뒤 = stage 11부터 열린다).
    app.post('/v1/test/stage', auth, async (c) => {
      const stage = intField(await body(c), 'stage', 1, 10_000)
      const id = c.get('playerId') as string
      await query('update player_state set version = version + 1, stage = $2 where player_id = $1', [id, stage])
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

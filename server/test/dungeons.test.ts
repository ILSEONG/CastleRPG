// 던전·장비(개정 18 §2~§7): 일일 리셋(KST 경계·여러 날 누락·상한), start 검사, finish 멱등·타당성·소모(승리만)·보상(골드 공식,
// 장비 5개·등급 분포 표본), 장착 검증(무기 종류), 판매, 보관함 상한, 원자성(동시 finish·중간 실패), 012 마이그레이션, 격리, 시드 검증.
import assert from 'node:assert/strict'
import { cpSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { after, before, test } from 'node:test'
import { MIGRATIONS_DIR, migrate, openDb } from '../src/db.ts'
import type { Query } from '../src/db.ts'
import * as R from '../src/rules.ts'
import { CsvError, DATA_DIR, readTables, TABLES } from '../src/seed.ts'
import { barrier, setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
const tmp: string[] = []
before(async () => {
  S = await setup()
})
after(async () => {
  await S.close()
  for (const d of tmp) {
    try {
      rmSync(d, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 })
    } catch {
      // OS 임시 폴더라 남아도 해가 없다
    }
  }
})

// T0 = 2026-09-21 14:13:20 UTC = 23:13:20 KST. 리셋 = 15:00 UTC(00:00 KST)
const LAST = 1789916400 // T0가 속한 날의 리셋 시각
const MIDNIGHT = LAST + 86400 // T0 다음 00:00 KST
const DAY = 86400
const CFG: R.Config = { daily_reset_utc_hour: '15', gold_key_daily: '3', gold_key_cap: '10', equip_key_daily: '1', equip_key_cap: '3' }
const GOLD6 = ['hans', 'ella', 'dorik', 'nina', 'arteon', 'ignis']
const EQ4 = ['hans', 'ella', 'dorik', 'nina'] // Knight·Rogue_Hooded·Barbarian·Mage

const player = async (token: string, T: Setup = S) => (await T.req('GET', '/v1/player', { token })).json.player
const start = (token: string, body: unknown, T: Setup = S) => T.req('POST', '/v1/dungeon/start', { token, body })
const finish = (token: string, body: unknown, T: Setup = S) => T.req('POST', '/v1/dungeon/finish', { token, body })
const equip = (token: string, body: unknown) => S.req('POST', '/v1/equip', { token, body })
const sell = (token: string, ids: unknown) => S.req('POST', '/v1/items/sell', { token, body: { item_ids: ids } })
const logs = (id: string, kind: string, T: Setup = S) => T.db.query('select detail from economy_log where player_id = $1 and kind = $2 order by id', [id, kind])
const giveHeroes = (q: Query, id: string, ids: string[]) => Promise.all(ids.map((h) => q('insert into player_heroes (player_id, hero_id) values ($1, $2) on conflict do nothing', [id, h])))
const setGold = (q: Query, id: string, gold: number) => q('update player_state set gold_tenths = $2 where player_id = $1', [id, gold * 10])
const setDungeon = (q: Query, id: string, type: string, o: { keys?: number; best_level?: number; extra_today?: number }) =>
  q('update player_dungeons set keys = coalesce($3, keys), best_level = coalesce($4, best_level), extra_today = coalesce($5, extra_today) where player_id = $1 and type = $2',
    [id, type, o.keys ?? null, o.best_level ?? null, o.extra_today ?? null])
async function addItems(q: Query, id: string, items: { slot: string; weapon_kind?: string; grade?: string; level?: number }[]): Promise<number[]> {
  const out: number[] = []
  for (const it of items) {
    const [r] = await q('insert into player_items (player_id, slot, weapon_kind, grade, level) values ($1, $2, $3, $4, $5) returning id',
      [id, it.slot, it.weapon_kind ?? null, it.grade ?? 'N', it.level ?? 1])
    out.push(Number(r.id))
  }
  return out
}
// 새 플레이어(T0) + 영웅 6명 + 던전 행(첫 읽기가 채운다)
async function fresh(T: Setup = S) {
  T.clock.t = T0
  const { token, id } = await T.login()
  await giveHeroes(T.db.query, id, GOLD6)
  await player(token, T)
  return { token, id }
}
const dg = async (token: string) => (await player(token)).dungeons

// --- 순수 규칙 ---

test('일일 리셋 규칙: 15:00 UTC(00:00 KST) 경계, 놓친 날 × 지급을 상한까지(초과분 버림, 이미 넘으면 그대로), 추가 도전 0, 시계 되돌림은 그대로', () => {
  const d = { best_level: 4, keys: 0, extra_today: 2, last_reset: LAST }
  assert.equal(R.resetDay(MIDNIGHT - 1, 15) + 1, R.resetDay(MIDNIGHT, 15)) // 14:59:59 UTC와 15:00:00 UTC는 다른 날
  assert.equal(R.applyReset('gold', d, MIDNIGHT - 1, CFG), d) // 23:59:59 KST: 그대로
  assert.deepEqual(R.applyReset('gold', d, MIDNIGHT, CFG), { best_level: 4, keys: 3, extra_today: 0, last_reset: MIDNIGHT })
  assert.deepEqual(R.applyReset('gold', d, MIDNIGHT + 2 * DAY + 5, CFG), { best_level: 4, keys: 9, extra_today: 0, last_reset: MIDNIGHT + 2 * DAY }) // 3번 놓침
  assert.equal(R.applyReset('gold', d, MIDNIGHT + 3 * DAY, CFG).keys, 10) // 4번 = 12 → 상한 10
  assert.equal(R.applyReset('gold', { ...d, keys: 9 }, MIDNIGHT, CFG).keys, 10) // 9 + 3 → 10(초과분 버림)
  assert.equal(R.applyReset('gold', { ...d, keys: 12 }, MIDNIGHT + 9 * DAY, CFG).keys, 12) // 이미 상한 위(설정 변경)면 줄이지 않는다
  assert.equal(R.applyReset('equip', d, MIDNIGHT + 9 * DAY, CFG).keys, 3) // 장비: 하루 1, 상한 3
  assert.equal(R.applyReset('equip', d, MIDNIGHT, CFG).keys, 1)
  assert.equal(R.applyReset('gold', d, LAST - 10 * DAY, CFG), d) // 시계를 되돌림
  assert.equal(R.nextReset(T0, CFG), MIDNIGHT)
  assert.equal(R.nextReset(MIDNIGHT, CFG), MIDNIGHT + DAY)
  assert.deepEqual(R.freshDungeon('gold', T0, CFG), { best_level: 0, keys: 3, extra_today: 0, last_reset: LAST })
  assert.equal(R.extraCost({ equip_extra_gold_base: '5000' }, 0), 5000)
  assert.equal(R.extraCost({ equip_extra_gold_base: '5000' }, 2), 15000)
})

test('보상·적 능력치·장비 능력치·판매 값: 골드 = round(4000 × 1.1^(n−1)), 적 = 기본 × 성장^(n−1), 장비 = round((기본 + 레벨당 × (n−1)) × 등급 배율)', async () => {
  const g = await S.req('GET', '/v1/gamedata')
  const cfg = g.json.config
  assert.deepEqual([1, 2, 3, 10].map((n) => R.goldReward(cfg, n)), [4000, 4400, 4840, 9432])
  const e1 = R.dungeonEnemies(g.json.dungeons, 'gold', 1, cfg)
  assert.deepEqual(e1.map((e) => [e.kind, e.count, e.delay, e.hp, e.atk]), [['goblin', 10, 0, 120, 14], ['goblin', 5, 5, 120, 14], ['goblin_king', 1, 5, 1500, 40]])
  assert.equal(e1.reduce((s, e) => s + e.count, 0), 16) // 고블린 15 + 왕 1
  const e3 = R.dungeonEnemies(g.json.dungeons, 'gold', 3, cfg)
  assert.ok(Math.abs(e3[0].hp - 120 * 1.12 * 1.12) < 1e-9 && Math.abs(e3[2].atk - 40 * 1.12 * 1.12) < 1e-9)
  const dk = R.dungeonEnemies(g.json.dungeons, 'equip', 2, cfg)
  assert.deepEqual(dk.map((e) => [e.kind, e.count, e.scale]), [['death_knight', 1, 2.2]])
  assert.ok(Math.abs(dk[0].hp - 6900) < 1e-9 && Math.abs(dk[0].atk - 67.2) < 1e-9, JSON.stringify(dk[0]))
  const st = (slot: string, grade: string, level: number) => R.itemStats({ slot, weapon_kind: slot === 'weapon' ? 'sword' : null, grade, level })
  assert.deepEqual(st('weapon', 'N', 1), { hp: 0, atk: 6, speed_pct: 0 })
  assert.deepEqual(st('weapon', 'SR', 3), { hp: 0, atk: 20, speed_pct: 0 }) // 9 × 2.2 = 19.8
  assert.deepEqual(st('gloves', 'R', 1), { hp: 0, atk: 4, speed_pct: 0 }) // 3.75 → 4
  assert.deepEqual(st('gloves', 'N', 2), { hp: 0, atk: 3, speed_pct: 0 }) // 3.1
  assert.deepEqual(st('shoes', 'LR', 1), { hp: 130, atk: 0, speed_pct: 3 })
  assert.deepEqual(st('shoes', 'N', 9), { hp: 60, atk: 0, speed_pct: 3 })
  assert.deepEqual([st('top', 'UR', 5).hp, st('bottom', 'N', 1).hp, st('hat', 'SSR', 10).hp, st('pauldron', 'R', 2).hp], [368, 40, 253, 47])
  assert.deepEqual([['N', 1], ['SR', 3], ['LR', 7]].map(([gr, n]) => R.itemSellValue(cfg, { slot: 'hat', weapon_kind: null, grade: gr as string, level: n as number })), [10, 66, 455])
})

test('등급 표(equip_drop.csv): 단계 구간 1–4·5–9·10–19·20–34·35+, 장비 표본 — 무기 20%, 방어구 6부위 균등, 무기 종류 균등, 등급 = 가중치 비율', async () => {
  const rows = (await S.req('GET', '/v1/gamedata')).json.equip_drop
  assert.deepEqual([1, 4, 5, 9, 10, 19, 20, 34, 35, 300].map((n) => R.dropWeights(rows, n).join('/')),
    ['60/30/9/1/0/0', '60/30/9/1/0/0', '40/35/18/6/1/0', '40/35/18/6/1/0', '20/35/28/13/3.5/0.5', '20/35/28/13/3.5/0.5', '8/25/34/22/9/2',
      '8/25/34/22/9/2', '2/13/30/30/18/7', '2/13/30/30/18/7'])
  // 호출 순서: 부위(무기?) → 무기 종류 또는 방어구 부위 → 등급. 앱 GameData.roll_drops 테스트와 같은 난수열 → 같은 결과
  const seq = [0.1, 0.5, 0.95, 0.9, 0.0, 0.995]
  let k = 0
  assert.deepEqual(R.rollDrops(rows, 1, 2, 0.2, () => seq[k++ % seq.length]),
    [{ slot: 'weapon', weapon_kind: 'staff', grade: 'SR', level: 1 }, { slot: 'hat', weapon_kind: null, grade: 'SSR', level: 1 }])
  const n = 120_000
  const items = R.rollDrops(rows, 12, n, 0.2, R.mulberry32(18))
  assert.equal(items.length, n)
  const share = (f: (x: R.EquipItem) => boolean) => items.filter(f).length / n
  assert.ok(Math.abs(share((x) => x.slot === 'weapon') - 0.2) < 0.005, 'weapon share')
  for (const s of R.ARMOR_SLOTS) assert.ok(Math.abs(share((x) => x.slot === s) - 0.8 / 6) < 0.005, `armor ${s}`)
  for (const k of R.WEAPON_KINDS) assert.ok(Math.abs(share((x) => x.weapon_kind === k) - 0.04) < 0.003, `weapon kind ${k}`)
  assert.ok(items.every((x) => (x.slot === 'weapon') === (x.weapon_kind !== null) && x.level === 12))
  const w = [20, 35, 28, 13, 3.5, 0.5]
  R.EQUIP_GRADES.forEach((g, i) => assert.ok(Math.abs(share((x) => x.grade === g) - w[i] / 100) < 0.005, `grade ${g}: ${share((x) => x.grade === g)}`))
  const low = R.rollDrops(rows, 1, 20_000, 0.2, R.mulberry32(7))
  assert.ok(!low.some((x) => x.grade === 'UR' || x.grade === 'LR'), 'weight 0 grades never drop at levels 1-4')
  assert.equal(R.rollDrops(rows, 1, 5, 0.2, R.cryptoRandom).length, 5)
})

// --- API ---

test('GET /v1/dungeon: 새 플레이어는 그날 지급분(골드 3/10, 장비 1/3), 추가 도전 비용 5000, 다음 리셋 = 다음 00:00 KST, 보관함은 /v1/items', async () => {
  const { token } = await fresh()
  const r = await S.req('GET', '/v1/dungeon', { token })
  assert.equal(r.status, 200)
  const ticket = r.json.dungeons.ticket // 모집권 던전(ticket_dungeon.test.ts가 자세히 본다)
  assert.deepEqual([ticket.keys, ticket.key_cap, ticket.helpers.length, ticket.helpers_used], [1, 3, 3, []])
  delete r.json.dungeons.ticket
  assert.deepEqual(r.json, {
    server_now: T0,
    dungeons: {
      gold: { keys: 3, key_cap: 10, key_daily: 3, best_level: 0, extra_today: 0, extra_cost: null, last_reset: LAST, next_reset: MIDNIGHT },
      equip: { keys: 1, key_cap: 3, key_daily: 1, best_level: 0, extra_today: 0, extra_cost: 5000, last_reset: LAST, next_reset: MIDNIGHT },
    },
  })
  assert.deepEqual((await S.req('GET', '/v1/items', { token })).json, { server_now: T0, items: [] })
  assert.equal((await S.req('GET', '/v1/dungeon')).status, 401)
})

test('일일 리셋(서버 시각): 자정(KST) 전엔 그대로, 자정에 +3, 5일 놓치면 상한 10, 장비 상한 3, 추가 도전 횟수 0 — 다음 쓰기에 저장된다', async () => {
  const { token, id } = await fresh()
  await setDungeon(S.db.query, id, 'gold', { keys: 0 })
  await setDungeon(S.db.query, id, 'equip', { keys: 0, extra_today: 2 })
  S.clock.t = MIDNIGHT - 1
  let d = await dg(token)
  assert.deepEqual([d.gold.keys, d.equip.keys, d.equip.extra_today, d.equip.extra_cost], [0, 0, 2, 15000])
  S.clock.t = MIDNIGHT
  d = await dg(token)
  assert.deepEqual([d.gold.keys, d.equip.keys, d.equip.extra_today, d.equip.extra_cost, d.gold.next_reset], [3, 1, 0, 5000, MIDNIGHT + DAY])
  S.clock.t = MIDNIGHT + 4 * DAY + 100 // 5번
  d = await dg(token)
  assert.deepEqual([d.gold.keys, d.equip.keys, d.gold.last_reset], [10, 3, MIDNIGHT + 4 * DAY])
  const [row] = await S.db.query("select keys from player_dungeons where player_id = $1 and type = 'gold'", [id])
  assert.equal(row.keys, 0) // 읽기는 쓰지 않는다(게으른 리셋)
  // 소모하면 리셋한 값에서 뺀 값이 저장된다
  const s = await start(token, { type: 'gold', level: 1, party: GOLD6 })
  S.clock.t += 30
  await finish(token, { run_id: s.json.run_id, win: true, elapsed: 30 })
  const [row2] = await S.db.query("select keys, extract(epoch from last_reset)::float8 as lr from player_dungeons where player_id = $1 and type = 'gold'", [id])
  assert.deepEqual([row2.keys, row2.lr], [9, MIDNIGHT + 4 * DAY])
  S.clock.t = MIDNIGHT + 5 * DAY
  assert.equal((await dg(token)).gold.keys, 10) // 9 + 3 → 상한
})

test('start 검사: 형식 400, 단계 열림 409 locked, 인원·중복·보유 400 bad_party, 열쇠 409 no_key, 장비는 골드 추가 도전(409 not_enough_gold), 보관함 409 bag_full — 아무것도 소모하지 않는다', async () => {
  const { token, id } = await fresh()
  const bad: [unknown, number, string][] = [
    [{ type: 'fire', level: 1, party: GOLD6 }, 400, 'bad_request'], [{ level: 1, party: GOLD6 }, 400, 'bad_request'],
    [{ type: 'gold', level: 0, party: GOLD6 }, 400, 'bad_request'], [{ type: 'gold', level: 1.5, party: GOLD6 }, 400, 'bad_request'],
    [{ type: 'gold', level: R.MAX_DUNGEON_LEVEL + 1, party: GOLD6 }, 400, 'bad_request'], [{ type: 'gold', level: 1 }, 400, 'bad_party'],
    [{ type: 'gold', level: 1, party: 'hans' }, 400, 'bad_party'], [{ type: 'gold', level: 1, party: [1, 2] }, 400, 'bad_party'],
    [{ type: 'gold', level: 2, party: GOLD6 }, 409, 'locked'], // 최고 0 → 1단계만
    [{ type: 'gold', level: 1, party: EQ4 }, 400, 'bad_party'], // 골드 던전은 6명
    [{ type: 'equip', level: 1, party: GOLD6 }, 400, 'bad_party'], // 장비 던전은 4명
    [{ type: 'gold', level: 1, party: ['hans', 'hans', 'ella', 'dorik', 'nina', 'arteon'] }, 400, 'bad_party'],
    [{ type: 'gold', level: 1, party: ['hans', 'ella', 'dorik', 'nina', 'arteon', 'kyle'] }, 400, 'bad_party'], // kyle 미보유
    [{ type: 'gold', level: 1, party: ['hans', 'ella', 'dorik', 'nina', 'arteon', 'ghost'] }, 400, 'bad_party'],
  ]
  for (const [body, status, code] of bad) {
    const r = await start(token, body)
    assert.deepEqual([r.status, r.json.error], [status, code], JSON.stringify(body))
  }
  await setDungeon(S.db.query, id, 'gold', { keys: 0, best_level: 3 })
  assert.deepEqual([(await start(token, { type: 'gold', level: 4, party: GOLD6 })).json.error, (await start(token, { type: 'gold', level: 5, party: GOLD6 })).json.error], ['no_key', 'locked'])
  await setDungeon(S.db.query, id, 'equip', { keys: 0, extra_today: 1 })
  await setGold(S.db.query, id, 9999)
  assert.deepEqual((await start(token, { type: 'equip', level: 1, party: EQ4 })).json.error, 'not_enough_gold') // 10000 필요
  await setGold(S.db.query, id, 10000)
  let r = await start(token, { type: 'equip', level: 1, party: EQ4 })
  assert.deepEqual([r.status, r.json.paid_with, r.json.player.gold], [200, 'gold', 10000]) // 시작은 골드를 빼지 않는다
  await setDungeon(S.db.query, id, 'equip', { keys: 1 })
  await S.db.query("insert into player_items (player_id, slot, grade, level) select $1, 'hat', 'N', 1 from generate_series(1, 296)", [id])
  assert.deepEqual((await start(token, { type: 'equip', level: 1, party: EQ4 })).json.error, 'bag_full') // 296 + 5 > 300
  await S.db.query("delete from player_items where id = (select min(id) from player_items where player_id = $1)", [id])
  r = await start(token, { type: 'equip', level: 1, party: EQ4 })
  assert.deepEqual([r.status, r.json.paid_with], [200, 'key']) // 295 + 5 = 300
  assert.equal((await player(token)).items.length, 295)
  const d = await dg(token)
  assert.deepEqual([d.gold.keys, d.equip.keys, (await player(token)).gold], [0, 1, 10000]) // 거부·시작은 아무것도 소모하지 않았다
})

test('start 응답: run_id·seed·enemies(그 단계 능력치)·started_at·time_limit, run 행 저장(30분 만료), 새 start는 열린 run을 닫는다(409 run_closed)', async () => {
  const { token, id } = await fresh()
  await setDungeon(S.db.query, id, 'gold', { best_level: 2 })
  const r = await start(token, { type: 'gold', level: 3, party: GOLD6 })
  assert.equal(r.status, 200)
  assert.match(r.json.run_id, /^[0-9a-f-]{36}$/)
  assert.ok(Number.isInteger(r.json.seed) && r.json.seed >= 0 && r.json.seed < 2 ** 31)
  assert.deepEqual([r.json.type, r.json.level, r.json.party, r.json.started_at, r.json.time_limit], ['gold', 3, GOLD6, T0, 120])
  assert.deepEqual(r.json.enemies.map((e: any) => [e.id, e.kind, e.count, e.delay]), [['gold_goblin_a', 'goblin', 10, 0], ['gold_goblin_b', 'goblin', 5, 5], ['gold_king', 'goblin_king', 1, 5]])
  assert.ok(Math.abs(r.json.enemies[2].hp - 1500 * 1.12 ** 2) < 1e-6)
  const [row] = await S.db.query('select type, level, party, seed::float8 as seed, closed, result, extract(epoch from started_at)::float8 as t from dungeon_runs where run_id = $1', [r.json.run_id])
  assert.deepEqual(row, { type: 'gold', level: 3, party: GOLD6, seed: r.json.seed, closed: false, result: null, t: T0 })
  const r2 = await start(token, { type: 'gold', level: 1, party: GOLD6 })
  S.clock.t += 30
  const old = await finish(token, { run_id: r.json.run_id, win: true, elapsed: 30 })
  assert.deepEqual([old.status, old.json.error], [409, 'run_closed'])
  assert.equal((await finish(token, { run_id: r2.json.run_id, win: true, elapsed: 30 })).status, 200)
  S.clock.t = T0 + 2 * DAY // 하루 지난 run은 새 start가 지운다
  await start(token, { type: 'gold', level: 1, party: GOLD6 })
  assert.equal((await S.db.query('select count(*)::int as n from dungeon_runs where player_id = $1', [id]))[0].n, 1)
})

test('finish 골드 던전 승리: 열쇠 −1·골드 +4000(tenths)·최고 단계 1·로그, 재전송은 같은 결과(멱등) — 열쇠·골드 그대로, 다음 단계가 열린다', async () => {
  const { token, id } = await fresh()
  const s = await start(token, { type: 'gold', level: 1, party: GOLD6 })
  S.clock.t = T0 + 31
  const r = await finish(token, { run_id: s.json.run_id, win: true, elapsed: 30 })
  assert.equal(r.status, 200)
  assert.deepEqual([r.json.win, r.json.rewards, r.json.player.gold_tenths, r.json.player.dungeons.gold.keys, r.json.player.dungeons.gold.best_level], [true, { gold_tenths: 40000 }, 40000, 2, 1])
  for (let i = 0; i < 2; i++) {
    const again = await finish(token, { run_id: s.json.run_id, win: true, elapsed: 30 })
    assert.deepEqual([again.status, again.json.win, again.json.rewards, again.json.repeated, again.json.player.gold_tenths, again.json.player.dungeons.gold.keys], [200, true, { gold_tenths: 40000 }, true, 40000, 2])
  }
  const lose = await finish(token, { run_id: s.json.run_id, win: false, elapsed: 30 }) // 이미 끝난 run: 저장한 결과
  assert.deepEqual([lose.json.win, lose.json.rewards], [true, { gold_tenths: 40000 }])
  assert.deepEqual((await logs(id, 'dungeon_clear')).map((l) => [l.detail.type, l.detail.level, l.detail.elapsed, l.detail.paid, l.detail.keys_after, l.detail.gold_tenths, l.detail.party]),
    [['gold', 1, 30, { key: 1 }, 2, 40000, GOLD6]])
  const [run] = await S.db.query('select closed, result from dungeon_runs where run_id = $1', [s.json.run_id])
  assert.deepEqual(run, { closed: true, result: { win: true, rewards: { gold_tenths: 40000 } } })
  assert.equal((await start(token, { type: 'gold', level: 2, party: GOLD6 })).status, 200)
  assert.equal((await start(token, { type: 'gold', level: 3, party: GOLD6 })).json.error, 'locked')
})

test('finish 패배: 열쇠·골드를 소모하지 않고 run만 닫는다(재전송도 같다), 최고 단계 그대로', async () => {
  const { token, id } = await fresh()
  await setDungeon(S.db.query, id, 'equip', { keys: 0 })
  await setGold(S.db.query, id, 6000)
  for (const [type, party] of [['gold', GOLD6], ['equip', EQ4]] as [string, string[]][]) {
    const s = await start(token, { type, level: 1, party })
    S.clock.t += 5
    const r = await finish(token, { run_id: s.json.run_id, win: false, elapsed: 5 })
    assert.deepEqual([r.status, r.json.win, r.json.rewards], [200, false, {}], type)
    const again = await finish(token, { run_id: s.json.run_id, win: true, elapsed: 30 }) // 졌던 run을 이겼다고 다시 보내도 결과는 패배
    assert.deepEqual([again.json.win, again.json.rewards, again.json.repeated], [false, {}, true])
  }
  const d = await dg(token)
  assert.deepEqual([d.gold.keys, d.gold.best_level, d.equip.keys, d.equip.extra_today, (await player(token)).gold, (await player(token)).items], [3, 0, 0, 0, 6000, []])
  assert.equal((await logs(id, 'dungeon_clear')).length, 0)
})

test('finish 타당성: 최소(골드 15·장비 20초)·제한 시간 120초·실제 경과 ≥ elapsed − 5, 아니면 409 implausible(run은 열린 채), 30분 지나면 409 run_expired', async () => {
  const { token } = await fresh()
  const s = await start(token, { type: 'gold', level: 1, party: GOLD6 })
  S.clock.t = T0 + 20
  for (const [elapsed, why] of [[14.9, 'below the minimum'], [30, 'more than real time + 5'], [121, 'above the time limit']] as [number, string][]) {
    const r = await finish(token, { run_id: s.json.run_id, win: true, elapsed })
    assert.deepEqual([r.status, r.json.error], [409, 'implausible'], why)
  }
  const ok = await finish(token, { run_id: s.json.run_id, win: true, elapsed: 25 }) // 실제 20 ≥ 25 − 5
  assert.deepEqual([ok.status, ok.json.rewards], [200, { gold_tenths: 40000 }])
  const e = await start(token, { type: 'equip', level: 1, party: EQ4 })
  S.clock.t += 19.5
  assert.equal((await finish(token, { run_id: e.json.run_id, win: true, elapsed: 19.5 })).json.error, 'implausible') // 장비 최소 20초
  S.clock.t += R.RUN_TTL_SEC
  assert.deepEqual((await finish(token, { run_id: e.json.run_id, win: true, elapsed: 20 })).json.error, 'run_expired')
  for (const body of [{ run_id: 'x', win: true, elapsed: 20 }, { run_id: e.json.run_id, win: 'yes', elapsed: 20 }, { run_id: e.json.run_id, win: true, elapsed: -1 },
    { run_id: e.json.run_id, win: true }, { run_id: e.json.run_id, win: true, elapsed: 1e9 }]) {
    assert.equal((await finish(token, body)).status, 400, JSON.stringify(body))
  }
  assert.deepEqual((await finish(token, { run_id: '00000000-0000-4000-8000-000000000000', win: true, elapsed: 20 })).json.error, 'unknown_run')
})

test('finish 장비 던전 승리: 장비 정확히 5개(id·등급·부위·레벨 = 단계), 열쇠 −1, 재전송은 같은 5개 — 열쇠 없으면 골드 추가 도전(비용 5000 × (1 + 그날 횟수)), 자정에 0', async () => {
  const { token, id } = await fresh()
  const s = await start(token, { type: 'equip', level: 1, party: EQ4 })
  S.clock.t = T0 + 40
  const r = await finish(token, { run_id: s.json.run_id, win: true, elapsed: 40 })
  assert.equal(r.status, 200)
  const items = r.json.rewards.items
  assert.equal(items.length, 5)
  assert.ok(items.every((x: any) => Number.isInteger(x.id) && R.EQUIP_SLOTS.includes(x.slot) && R.EQUIP_GRADES.includes(x.grade) && x.level === 1
    && (x.slot === 'weapon') === R.WEAPON_KINDS.includes(x.weapon_kind) && (x.slot === 'weapon' || x.weapon_kind === null)), JSON.stringify(items))
  assert.ok(items.every((x: any) => ['N', 'R', 'SR', 'SSR'].includes(x.grade)), 'levels 1-4 never drop UR/LR')
  assert.deepEqual(r.json.player.items, items) // 보관함 = 받은 5개(id 순)
  assert.deepEqual([r.json.player.dungeons.equip.keys, r.json.player.dungeons.equip.best_level, r.json.player.gold_tenths], [0, 1, 0])
  const again = await finish(token, { run_id: s.json.run_id, win: true, elapsed: 40 })
  assert.deepEqual([again.json.rewards.items, again.json.player.items.length], [items, 5])
  assert.equal((await S.db.query('select count(*)::int as n from player_items where player_id = $1', [id]))[0].n, 5)
  assert.deepEqual((await logs(id, 'dungeon_clear'))[0].detail.items.length, 5)
  // 열쇠 0: 골드 추가 도전 — 이겼을 때만 골드를 뺀다
  await setGold(S.db.query, id, 20000)
  let x = await start(token, { type: 'equip', level: 2, party: EQ4 })
  assert.deepEqual([x.status, x.json.paid_with], [200, 'gold'])
  S.clock.t += 25
  x = await finish(token, { run_id: x.json.run_id, win: true, elapsed: 25 })
  assert.deepEqual([x.status, x.json.player.gold, x.json.player.dungeons.equip.extra_today, x.json.player.dungeons.equip.extra_cost, x.json.player.items.length, x.json.player.dungeons.equip.best_level],
    [200, 15000, 1, 10000, 10, 2])
  assert.deepEqual((await logs(id, 'dungeon_clear'))[1].detail.paid, { gold: 5000 })
  x = await start(token, { type: 'equip', level: 1, party: EQ4 })
  S.clock.t += 25
  x = await finish(token, { run_id: x.json.run_id, win: true, elapsed: 25 })
  assert.deepEqual([x.json.player.gold, x.json.player.dungeons.equip.extra_today, x.json.player.dungeons.equip.extra_cost], [5000, 2, 15000])
  assert.equal((await start(token, { type: 'equip', level: 1, party: EQ4 })).json.error, 'not_enough_gold')
  S.clock.t = MIDNIGHT
  const d = await dg(token)
  assert.deepEqual([d.equip.keys, d.equip.extra_today, d.equip.extra_cost], [1, 0, 5000]) // 리셋: 열쇠 +1, 횟수 0
})

test('장비 수 = equip_drop_count(설정): 3으로 바꾸면 3개, 보관함 상한 검사도 그 수로', async () => {
  const { token, id } = await fresh()
  await S.db.query("update game_config set value = '3' where key = 'equip_drop_count'")
  try {
    await S.db.query("insert into player_items (player_id, slot, grade, level) select $1, 'hat', 'N', 1 from generate_series(1, 297)", [id])
    const s = await start(token, { type: 'equip', level: 1, party: EQ4 }) // 297 + 3 = 300
    S.clock.t += 20
    const r = await finish(token, { run_id: s.json.run_id, win: true, elapsed: 20 })
    assert.deepEqual([r.status, r.json.rewards.items.length, r.json.player.items.length], [200, 3, 300])
    await setDungeon(S.db.query, id, 'equip', { keys: 1 })
    assert.equal((await start(token, { type: 'equip', level: 1, party: EQ4 })).json.error, 'bag_full')
  } finally {
    await S.db.query("update game_config set value = '5' where key = 'equip_drop_count'")
  }
})

test('장착: 무기는 그 영웅 모델의 종류만(409 wrong_weapon), 부위 다르면 409 wrong_slot, 없는·남의 장비 404, 미보유 영웅 404, 다른 영웅에서 옮기기·해제·멱등', async () => {
  const { token, id } = await fresh()
  const other = await fresh()
  const [sword, axe, staff, hat, hat2, shoes] = await addItems(S.db.query, id, [{ slot: 'weapon', weapon_kind: 'sword', grade: 'SR', level: 3 },
    { slot: 'weapon', weapon_kind: 'axe' }, { slot: 'weapon', weapon_kind: 'staff' }, { slot: 'hat', grade: 'R', level: 2 }, { slot: 'hat' }, { slot: 'shoes' }])
  const [theirs] = await addItems(S.db.query, other.id, [{ slot: 'hat' }])
  let r = await equip(token, { hero_id: 'hans', slot: 'weapon', item_id: sword }) // 한스 = Knight → 검
  assert.deepEqual([r.status, r.json.player.equipment], [200, { hans: { weapon: sword } }])
  for (const [hero, item, code] of [['hans', axe, 'wrong_weapon'], ['hans', staff, 'wrong_weapon'], ['nina', sword, 'wrong_weapon'], ['ella', sword, 'wrong_weapon']] as [string, number, string][]) {
    r = await equip(token, { hero_id: hero, slot: 'weapon', item_id: item })
    assert.deepEqual([r.status, r.json.error], [409, code], `${hero} ${item}`)
  }
  assert.equal((await equip(token, { hero_id: 'dorik', slot: 'weapon', item_id: axe })).status, 200) // Barbarian → 도끼
  assert.equal((await equip(token, { hero_id: 'nina', slot: 'weapon', item_id: staff })).status, 200) // Mage → 지팡이
  const bad: [unknown, number, string][] = [
    [{ hero_id: 'hans', slot: 'hat', item_id: shoes }, 409, 'wrong_slot'], [{ hero_id: 'hans', slot: 'weapon', item_id: hat }, 409, 'wrong_slot'],
    [{ hero_id: 'hans', slot: 'hat', item_id: 999999 }, 404, 'unknown_item'], [{ hero_id: 'hans', slot: 'hat', item_id: theirs }, 404, 'unknown_item'],
    [{ hero_id: 'kyle', slot: 'hat', item_id: hat }, 404, 'not_owned'], [{ hero_id: '__proto__', slot: 'hat', item_id: hat }, 404, 'not_owned'],
    [{ hero_id: 'hans', slot: 'cape', item_id: hat }, 400, 'bad_slot'], [{ hero_id: 'hans', slot: 'hat', item_id: '7' }, 400, 'bad_request'],
    [{ hero_id: 'hans', slot: 'hat' }, 400, 'bad_request'], [{ slot: 'hat', item_id: hat }, 400, 'bad_request'],
  ]
  for (const [body, status, code] of bad) {
    r = await equip(token, body)
    assert.deepEqual([r.status, r.json.error], [status, code], JSON.stringify(body))
  }
  assert.equal((await equip(token, { hero_id: 'hans', slot: 'hat', item_id: hat })).status, 200)
  r = await equip(token, { hero_id: 'ella', slot: 'hat', item_id: hat }) // 한스에서 엘라로 옮긴다
  assert.deepEqual(r.json.player.equipment, { hans: { weapon: sword }, ella: { hat }, dorik: { weapon: axe }, nina: { weapon: staff } })
  r = await equip(token, { hero_id: 'ella', slot: 'hat', item_id: hat2 }) // 같은 자리 바꿔 끼우기
  assert.deepEqual(r.json.player.equipment.ella, { hat: hat2 })
  r = await equip(token, { hero_id: 'ella', slot: 'hat', item_id: hat2 }) // 멱등
  assert.deepEqual([r.status, r.json.player.equipment.ella], [200, { hat: hat2 }])
  r = await equip(token, { hero_id: 'ella', slot: 'hat', item_id: null })
  assert.deepEqual([r.status, r.json.player.equipment.ella], [200, undefined])
  assert.equal((await equip(token, { hero_id: 'ella', slot: 'hat', item_id: null })).status, 200) // 빈 자리 해제도 200
  const rows = await S.db.query('select hero_id, slot, item_id::int as item from player_equipment where player_id = $1 order by hero_id', [id])
  assert.deepEqual(rows, [{ hero_id: 'dorik', slot: 'weapon', item: axe }, { hero_id: 'hans', slot: 'weapon', item: sword }, { hero_id: 'nina', slot: 'weapon', item: staff }])
  assert.deepEqual((await player(other.token)).equipment, {})
})

test('판매: 값 = round(10 × 배율 × 레벨)의 합, 장착 중이면 409 equipped, 없는·남의·겹친 id는 거부 — 하나라도 틀리면 아무것도 안 판다, 로그', async () => {
  const { token, id } = await fresh()
  const other = await fresh()
  const [a, b, c, w] = await addItems(S.db.query, id, [{ slot: 'hat', grade: 'SR', level: 3 }, { slot: 'top', grade: 'N', level: 1 }, { slot: 'gloves', grade: 'LR', level: 7 },
    { slot: 'weapon', weapon_kind: 'sword', grade: 'R', level: 2 }])
  const [theirs] = await addItems(S.db.query, other.id, [{ slot: 'hat' }])
  await equip(token, { hero_id: 'hans', slot: 'weapon', item_id: w })
  for (const [ids, status, code] of [[[a, w], 409, 'equipped'], [[a, theirs], 404, 'unknown_item'], [[a, 999999], 404, 'unknown_item'], [[a, a], 400, 'bad_request'],
    [[], 400, 'bad_request'], ['x', 400, 'bad_request'], [[0], 400, 'bad_request']] as [unknown, number, string][]) {
    const r = await sell(token, ids)
    assert.deepEqual([r.status, r.json.error], [status, code], JSON.stringify(ids))
  }
  assert.deepEqual([(await player(token)).items.length, (await player(token)).gold], [4, 0]) // 거부는 아무것도 안 바꿨다
  const r = await sell(token, [a, b, c])
  assert.deepEqual([r.status, r.json.gold_gained, r.json.player.gold_tenths, r.json.player.items.map((x: any) => x.id)], [200, 66 + 10 + 455, 5310, [w]])
  assert.deepEqual((await sell(token, [a])).json.error, 'unknown_item') // 다시 팔 수 없다
  assert.deepEqual((await logs(id, 'item_sell')).map((l) => [l.detail.gold, l.detail.items.length]), [[531, 3]])
  await equip(token, { hero_id: 'hans', slot: 'weapon', item_id: null })
  assert.equal((await sell(token, [w])).json.gold_gained, 30) // 해제하면 판다(10 × 1.5 × 2)
  assert.deepEqual((await player(other.token)).items.map((x: any) => x.id), [theirs])
})

test('플레이어 격리: 남의 run finish·장비 장착·판매는 404, 한 플레이어의 도전은 다른 플레이어 열쇠·보관함·최고 단계에 닿지 않는다', async () => {
  const a = await fresh()
  const b = await fresh()
  const s = await start(a.token, { type: 'equip', level: 1, party: EQ4 })
  S.clock.t += 30
  assert.deepEqual((await finish(b.token, { run_id: s.json.run_id, win: true, elapsed: 30 })).json.error, 'unknown_run')
  const r = await finish(a.token, { run_id: s.json.run_id, win: true, elapsed: 30 })
  const item = r.json.rewards.items[0]
  assert.deepEqual((await equip(b.token, { hero_id: 'hans', slot: item.slot, item_id: item.id })).json.error, 'unknown_item')
  assert.deepEqual((await sell(b.token, [item.id])).json.error, 'unknown_item')
  const pb = await player(b.token)
  assert.deepEqual([pb.items, pb.equipment, pb.dungeons.equip.keys, pb.dungeons.equip.best_level, pb.gold], [[], {}, 1, 0, 0])
  assert.equal((await player(a.token)).items.length, 5)
})

test('test/dungeon_age: 열린 run 시작 시각을 앞당긴다(즉시 승리 훅) — 훅이 꺼진 서버엔 없다', async () => {
  const { token } = await fresh()
  const s = await start(token, { type: 'gold', level: 1, party: GOLD6 })
  assert.equal((await finish(token, { run_id: s.json.run_id, win: true, elapsed: 15 })).json.error, 'implausible')
  assert.equal((await S.req('POST', '/v1/test/dungeon_age', { token, body: { run_id: s.json.run_id, seconds: 15 } })).status, 200)
  assert.deepEqual((await finish(token, { run_id: s.json.run_id, win: true, elapsed: 15 })).json.rewards, { gold_tenths: 40000 })
  const off = S.makeApp({ allowTestHooks: false })
  for (const path of ['/v1/test/dungeon_age', '/v1/test/grant_hero']) {
    const res = await off.request(path, { method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: '{}' })
    assert.equal(res.status, 404, path)
  }
  const g = await S.req('POST', '/v1/test/grant_hero', { token, body: { hero_id: 'kyle' } })
  assert.deepEqual([g.status, g.json.player.heroes.kyle], [200, { copies: 1, level: 1, shards: 0, promotion: 0 }])
  assert.deepEqual((await S.req('POST', '/v1/test/grant_hero', { token, body: { hero_id: 'kyle' } })).json.player.heroes.kyle.copies, 1) // 이미 있으면 그대로
})

test('finish 원자성(동시): 같은 version을 읽은 finish 2건 — 보상·열쇠 소모·장비·로그는 한 번, 두 응답의 보상은 같다', async () => {
  const b = barrier()
  const T = await setup({ wrapQuery: b.wrap })
  try {
    const { token, id } = await fresh(T)
    const s = await start(token, { type: 'equip', level: 1, party: EQ4 }, T)
    const g = await start(token, { type: 'gold', level: 1, party: GOLD6 }, T) // 장비 run을 닫는다 — 다시 연다
    assert.equal(g.status, 200)
    const s2 = await start(token, { type: 'equip', level: 1, party: EQ4 }, T)
    T.clock.t += 30
    b.arm()
    const body = { run_id: s2.json.run_id, win: true, elapsed: 30 }
    const [r1, r2] = await Promise.all([finish(token, body, T), finish(token, body, T)])
    assert.equal(b.arrived(), 2, 'both requests read the same version before either wrote')
    assert.deepEqual([r1.status, r2.status], [200, 200])
    assert.equal(r1.json.rewards.items.length, 5)
    assert.deepEqual(r1.json.rewards, r2.json.rewards)
    assert.equal([r1, r2].filter((r) => r.json.repeated).length, 1)
    assert.equal((await T.db.query('select count(*)::int as n from player_items where player_id = $1', [id]))[0].n, 5)
    assert.equal((await T.db.query("select keys from player_dungeons where player_id = $1 and type = 'equip'", [id]))[0].keys, 0)
    assert.equal((await logs(id, 'dungeon_clear', T)).length, 1)
    assert.ok(s.json.run_id !== s2.json.run_id)
  } finally {
    await T.close()
  }
})

test('finish 원자성(중간 실패): 장비 넣기가 실패하면 열쇠·골드·최고 단계·run·로그 중 아무것도 바뀌지 않고, 다시 보내면 한 번에 들어간다', async () => {
  let fail = false
  const T = await setup({ wrapQuery: (q) => async (text, params) => {
    if (fail && text.includes('insert into player_items')) throw new Error('injected failure')
    return q(text, params)
  } })
  const err = console.error
  try {
    const { token, id } = await fresh(T)
    const s = await start(token, { type: 'equip', level: 1, party: EQ4 }, T)
    T.clock.t += 30
    fail = true
    console.error = () => {}
    const r = await finish(token, { run_id: s.json.run_id, win: true, elapsed: 30 }, T)
    console.error = err
    fail = false
    assert.equal(r.status, 500)
    const p = await player(token, T)
    assert.deepEqual([p.dungeons.equip.keys, p.dungeons.equip.best_level, p.items, p.gold_tenths], [1, 0, [], 0])
    const [run] = await T.db.query('select closed, result from dungeon_runs where run_id = $1', [s.json.run_id])
    assert.deepEqual(run, { closed: false, result: null })
    assert.equal((await logs(id, 'dungeon_clear', T)).length, 0)
    const ok = await finish(token, { run_id: s.json.run_id, win: true, elapsed: 30 }, T)
    assert.deepEqual([ok.status, ok.json.rewards.items.length, ok.json.player.items.length, ok.json.player.dungeons.equip.keys], [200, 5, 5, 0])
  } finally {
    console.error = err
    await T.close()
  }
})

test('마이그레이션 012: 011까지 적용된 DB에 던전·장비 표와 설정 기본값, 기존 플레이어는 첫 읽기에 그날 지급분 행 — 제약(무기 종류·등급·장착 유일)', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'castle-mig-'))
  tmp.push(dir)
  const all = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort()
  for (const f of all.filter((f) => f < '012')) cpSync(join(MIGRATIONS_DIR, f), join(dir, f))
  const d = await openDb({})
  try {
    await migrate(d, dir)
    const [p] = await d.query("insert into players (device_id) values ('mig-012-device-0001') returning id")
    await d.query('insert into player_state (player_id) values ($1)', [p.id])
    assert.deepEqual(await migrate(d), all.filter((f) => f >= '012'))
    const cfg = await d.query("select key, value from game_config where key like '%dg%' or key like '%key%' or key like 'equip%' or key like 'dungeon%' or key = 'daily_reset_utc_hour' order by key")
    assert.equal(cfg.length, 26) // 모집권 던전 022 +6
    assert.deepEqual(cfg.find((r) => r.key === 'equip_bag_cap'), { key: 'equip_bag_cap', value: '300' })
    assert.deepEqual(await d.query('select * from player_dungeons'), [])
    await assert.rejects(d.query("insert into player_items (player_id, slot, grade, level) values ($1, 'weapon', 'N', 1)", [p.id]), /weapon_has_kind/)
    await assert.rejects(d.query("insert into player_items (player_id, slot, weapon_kind, grade, level) values ($1, 'hat', 'sword', 'N', 1)", [p.id]), /weapon_has_kind/)
    await assert.rejects(d.query("insert into player_items (player_id, slot, grade, level) values ($1, 'hat', 'XR', 1)", [p.id]), /check/)
    const [it] = await d.query("insert into player_items (player_id, slot, grade, level) values ($1, 'hat', 'N', 1) returning id", [p.id])
    await d.query("insert into player_equipment (player_id, hero_id, slot, item_id) values ($1, 'hans', 'hat', $2)", [p.id, it.id])
    await assert.rejects(d.query("insert into player_equipment (player_id, hero_id, slot, item_id) values ($1, 'ella', 'hat', $2)", [p.id, it.id]), /player_equipment_item/)
    await d.query('delete from player_items where id = $1', [it.id]) // 팔면 장착도 지워진다
    assert.deepEqual(await d.query('select * from player_equipment'), [])
    await d.query('delete from players where id = $1', [p.id])
  } finally {
    await d.close()
  }
  // 기존 플레이어(던전 행 없음)는 첫 읽기에 그날 지급분을 받는다
  const { token, id } = await fresh()
  await S.db.query('delete from player_dungeons where player_id = $1', [id])
  S.clock.t = MIDNIGHT + 3 * DAY // 012 전 계정이 며칠 뒤 접속해도 놓친 날은 없다(행이 생긴 날부터 센다)
  const dd = await dg(token)
  assert.deepEqual([dd.gold.keys, dd.equip.keys, dd.gold.last_reset], [3, 1, MIDNIGHT + 3 * DAY])
})

test('마이그레이션 012: 013~015까지 먼저 적용된 DB(012만 빠짐)에도 012만 적용되고 던전 표·설정 기본값이 생긴다. 새 DB는 001~016 전부', async () => {
  const all = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort()
  assert.deepEqual(['011', '012', '013', '014', '015'].map((n) => all.some((f) => f.startsWith(n + '_'))), [true, true, true, true, true])
  const dir = mkdtempSync(join(tmpdir(), 'castle-mig-'))
  tmp.push(dir)
  for (const f of all.filter((f) => !f.startsWith('012_') && f < '022')) cpSync(join(MIGRATIONS_DIR, f), join(dir, f))
  const d = await openDb({})
  try {
    assert.deepEqual(await migrate(d, dir), all.filter((f) => !f.startsWith('012_') && f < '022'))
    assert.deepEqual(await migrate(d), all.filter((f) => f.startsWith('012_') || f >= '022')) // 022(모집권 던전)는 012의 던전 표를 바꾼다
    assert.deepEqual(await migrate(d), [])
    const cfg = await d.query("select key from game_config where key in ('equip_bag_cap', 'train_base_min') order by key")
    assert.deepEqual(cfg.map((r) => r.key), ['equip_bag_cap', 'train_base_min'])
    for (const t of ['dungeon_defs', 'equip_drop', 'player_dungeons', 'player_items', 'player_equipment', 'dungeon_runs', 'upgrade_defs', 'player_upgrades']) {
      assert.deepEqual(await d.query(`select count(*)::int as n from ${t}`), [{ n: 0 }], t)
    }
  } finally {
    await d.close()
  }
  const f = await openDb({})
  try {
    assert.deepEqual(await migrate(f), all)
    assert.equal(all.length, 20) // 친구: 023, 모집권 던전: 022, 개정 24: 016, 오프라인 골드: 017, 소셜 로그인: 018
  } finally {
    await f.close()
  }
})

test('시드 검증: dungeons.csv(type·count·능력치 범위, 종류마다 적), equip_drop.csv(min_level 1부터 오름차순, 가중치 ≥ 0·합 > 0), 던전 설정 범위, 영웅 모델의 무기 종류', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'castle-data-'))
  tmp.push(dir)
  for (const t of TABLES) cpSync(join(DATA_DIR, t.file), join(dir, t.file))
  const files = Object.fromEntries(['dungeons.csv', 'equip_drop.csv', 'config.csv', 'heroes.csv'].map((f) => [f, readFileSync(join(DATA_DIR, f), 'utf8')]))
  const cases: [string, (s: string) => string, RegExp][] = [
    ['dungeons.csv', (s) => s.replace('gold_king,gold,', 'gold_king,fire,'), /dungeons\.csv line 4 column 'type': type must be gold or equip or ticket: 'fire'/],
    ['dungeons.csv', (s) => s.replace('gold_goblin_b,gold,goblin,5,', 'gold_goblin_b,gold,goblin,0,'), /line 3 column 'count': must be at least 1: 0/],
    ['dungeons.csv', (s) => s.replace(',1500,40,', ',0,40,'), /line 4 column 'hp': must be greater than 0: 0/],
    ['dungeons.csv', (s) => s.replace(',6000,60,', ',6000,-1,'), /line 5 column 'atk': must be 0 or more: -1/],
    ['dungeons.csv', (s) => s.replace(/^equip_death_knight.*\n/m, ''), /no enemies for the equip dungeon/],
    ['dungeons.csv', (s) => s.replace(',1500,40,', ',x,40,'), /line 4 column 'hp': not a number: 'x'/],
    ['equip_drop.csv', (s) => s.replace('\n1,60,', '\n2,60,'), /equip_drop\.csv line 2 column 'min_level': min_level must start at 1 and go up/],
    ['equip_drop.csv', (s) => s.replace('\n10,20,', '\n4,20,'), /line 4 column 'min_level': min_level must start at 1 and go up/],
    ['equip_drop.csv', (s) => s.replace('\n5,40,35,', '\n5,-40,35,'), /line 3 column 'N': weights must be 0 or more/],
    ['equip_drop.csv', (s) => s.replace('\n5,40,35,18,6,1,0', '\n5,0,0,0,0,0,0'), /line 3 column 'N': weights must not all be 0/],
    ['config.csv', (s) => s.replace('daily_reset_utc_hour,15', 'daily_reset_utc_hour,24'), /daily_reset_utc_hour must be an integer in 0\.\.23: '24'/],
    ['config.csv', (s) => s.replace('equip_weapon_p,0.2', 'equip_weapon_p,1.5'), /equip_weapon_p must be in 0\.\.1: '1\.5'/],
    ['config.csv', (s) => s.replace('gold_dg_party,6', 'gold_dg_party,0'), /gold_dg_party must be an integer of at least 1: '0'/],
    ['config.csv', (s) => s.replace('gold_key_daily,3', 'gold_key_daily,1.5'), /gold_key_daily must be a non-negative integer: '1\.5'/],
    ['config.csv', (s) => s.replace('gold_dg_mult,1.1', 'gold_dg_mult,0'), /gold_dg_mult must be greater than 0: '0'/],
    ['config.csv', (s) => s.replace(/^gold_dg_base,.*\n/m, ''), /missing key 'gold_dg_base'/],
    ['config.csv', (s) => s.replace('equip_bag_cap,300', 'equip_bag_cap,lots'), /line \d+ column 'value': not a number: 'lots'/],
    ['heroes.csv', (s) => s.replace(',Knight,1H_Sword,#95A5A6,', ',Dragon,1H_Sword,#95A5A6,'), /heroes\.csv line \d+ column 'model': model 'Dragon' has no weapon kind/],
  ]
  for (const [file, edit, re] of cases) {
    const text = edit(files[file])
    assert.notEqual(text, files[file], `case did not change ${file}: ${re}`)
    writeFileSync(join(dir, file), text)
    await assert.rejects(readTables(dir), (e: unknown) => {
      assert.ok(e instanceof CsvError)
      assert.equal(e.errors.length, 1, `${re}: ${e.errors.join(' | ')}`)
      assert.match(e.errors[0], re)
      return true
    })
    writeFileSync(join(dir, file), files[file])
  }
  const t = await readTables(dir) // 원래대로면 통과
  assert.deepEqual(t.equip_drop.map((r) => r.min_level), [1, 5, 10, 20, 35])
})

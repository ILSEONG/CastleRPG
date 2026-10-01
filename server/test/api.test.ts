// HTTP API: 인증, 플레이어 응답, 수집·판매·처치·스테이지 클리어, gamedata, 테스트 훅. 시계는 주입(clock.t).
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import { sign } from 'hono/jwt'
import * as R from '../src/rules.ts'
import { randomDevice, setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup()
})
after(async () => {
  await S.close()
})

const CONFIG = async () => Object.fromEntries((await S.db.query('select key, value from game_config')).map((r) => [r.key, r.value]))
const logs = async (id: string, kind: string) => S.db.query('select detail from economy_log where player_id = $1 and kind = $2 order by id', [id, kind])

test('health: 인증 없이 {ok, server_now}', async () => {
  S.clock.t = T0
  const r = await S.req('GET', '/v1/health')
  assert.equal(r.status, 200)
  assert.deepEqual(r.json, { ok: true, server_now: T0 })
})

test('게스트 로그인: 같은 device_id면 같은 player, last_seen 갱신, 잘못된 device_id는 400', async () => {
  S.clock.t = T0
  const dev = randomDevice()
  const a = await S.login(dev)
  S.clock.t = T0 + 100
  const b = await S.login(dev)
  assert.equal(a.id, b.id)
  assert.notEqual((await S.login()).id, a.id)
  const [p] = await S.db.query('select extract(epoch from last_seen)::float8 as s, extract(epoch from created_at)::float8 as c from players where id = $1', [a.id])
  assert.deepEqual(p, { s: T0 + 100, c: T0 })
  assert.equal((await S.db.query('select count(*)::int as n from player_state where player_id = $1', [a.id]))[0].n, 1)
  for (const bad of ['short', 'x'.repeat(129), 'has space 0123456789', 'unicode-한글-0123456789', 12345678901234567890]) {
    const r = await S.req('POST', '/v1/auth/guest', { body: { device_id: bad } })
    assert.equal(r.status, 400, String(bad))
    assert.equal(r.json.error, 'bad_device_id')
  }
  assert.equal((await S.req('POST', '/v1/auth/guest', { body: 'not json' })).status, 400)
  assert.equal((await S.req('POST', '/v1/auth/guest', { body: [] })).status, 400)
  assert.equal((await S.req('POST', '/v1/auth/guest', { body: { device_id: 'A-b-0123456789-xyz' } })).status, 200)
})

test('JWT: 없음·위조·다른 비밀·만료·이상한 sub는 401', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  assert.equal((await S.req('GET', '/v1/player', { token })).status, 200)
  const noTok = await S.req('GET', '/v1/player')
  assert.equal(noTok.status, 401)
  assert.equal(noTok.json.error, 'no_token')
  assert.equal((await S.req('GET', '/v1/player', { headers: { authorization: token } })).status, 401) // Bearer 없음
  const [h, , sig] = token.split('.')
  const forgedPayload = Buffer.from(JSON.stringify({ sub: id, iat: T0, exp: T0 + 999999999 })).toString('base64url')
  assert.equal((await S.req('GET', '/v1/player', { token: `${h}.${forgedPayload}.${sig}` })).status, 401)
  const otherSecret = await sign({ sub: id, iat: T0, exp: T0 + 3600 }, 'some-other-secret', 'HS256')
  assert.equal((await S.req('GET', '/v1/player', { token: otherSecret })).status, 401)
  assert.equal((await S.req('GET', '/v1/player', { token: 'garbage' })).status, 401)
  const SECRET = 'test-secret-0123456789abcdef0123456789'
  const notUuid = await sign({ sub: 'robert); drop table players', iat: T0, exp: T0 + 3600 }, SECRET, 'HS256')
  assert.equal((await S.req('GET', '/v1/player', { token: notUuid })).status, 401)
  const ghost = await sign({ sub: '00000000-0000-4000-8000-000000000000', iat: T0, exp: T0 + 3600 }, SECRET, 'HS256')
  const g = await S.req('GET', '/v1/player', { token: ghost })
  assert.equal(g.status, 401)
  assert.equal(g.json.error, 'unknown_player')
  S.clock.t = T0 + 30 * 86400 - 1
  assert.equal((await S.req('GET', '/v1/player', { token })).status, 200)
  S.clock.t = T0 + 30 * 86400
  const exp = await S.req('GET', '/v1/player', { token })
  assert.equal(exp.status, 401)
  assert.equal(exp.json.error, 'token_expired')
  for (const p of ['/v1/collect', '/v1/sell', '/v1/kills', '/v1/stage/clear', '/v1/test/age']) {
    assert.equal((await S.req('POST', p, { body: {} })).status, 401, p)
  }
})

test('플레이어 응답 형식: server_now, player{gold,res,stage,keep_level,gate_level,buildings}, merchant{rate,next_change}', async () => {
  S.clock.t = T0 + 0.25
  const { token } = await S.login()
  const r = await S.req('GET', '/v1/player', { token })
  assert.equal(r.status, 200)
  const cfg = await CONFIG()
  assert.deepEqual(r.json, {
    server_now: T0 + 0.25,
    player: {
      gold: 0, res: { wood: 0, stone: 0, food: 0 }, stage: 1, keep_level: 1, gate_level: 1,
      buildings: {
        lumber: { level: 1, last_collect: T0 + 0.25 },
        quarry: { level: 1, last_collect: T0 + 0.25 },
        farm: { level: 1, last_collect: T0 + 0.25 },
      },
    },
    merchant: { rate: R.merchantRate(R.hourIndex(T0), cfg), next_change: (Math.floor(T0 / 3600) + 1) * 3600 },
  })
  assert.equal(r.headers.get('content-type')?.startsWith('application/json'), true)
})

test('수집 규칙(서버 시계): 분 내림·남은 초 유지·상한·0이면 변화 없음·음수 경과·자원 건물 아님 400', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  const collect = (building: string) => S.req('POST', '/v1/collect', { token, body: { building } })

  let r = await collect('lumber')
  assert.equal(r.json.amount, 0)
  assert.equal(r.json.player.buildings.lumber.last_collect, T0)

  S.clock.t = T0 + 150 // 2분 30초
  r = await collect('lumber')
  assert.equal(r.status, 200)
  assert.equal(r.json.amount, 20)
  assert.equal(r.json.player.res.wood, 20)
  assert.equal(r.json.player.buildings.lumber.last_collect, T0 + 120) // 30초는 남긴다
  assert.equal(r.json.server_now, T0 + 150)

  S.clock.t = T0 + 170 // 남은 30초 + 20초 = 50초 < 1분
  r = await collect('lumber')
  assert.equal(r.json.amount, 0)
  assert.equal(r.json.player.buildings.lumber.last_collect, T0 + 120)

  S.clock.t = T0 + 120 + 720 * 60 + 1000 // 상한 넘김
  r = await collect('quarry')
  assert.equal(r.json.amount, 720 * 5)
  assert.equal(r.json.player.res.stone, 3600)
  assert.equal(r.json.player.buildings.quarry.last_collect, S.clock.t)
  r = await collect('lumber')
  assert.equal(r.json.amount, 7200)
  assert.equal(r.json.player.res.wood, 7220)

  const back = S.clock.t - 3000 // 시계가 마지막 수집보다 뒤로: 0, 지금부터 다시
  S.clock.t = back
  r = await collect('lumber')
  assert.equal(r.json.amount, 0)
  assert.equal(r.json.player.buildings.lumber.last_collect, back)
  S.clock.t = back + 60
  assert.equal((await collect('lumber')).json.amount, 10)

  for (const b of ['keep', 'barracks', 'wood']) {
    const bad = await collect(b)
    assert.equal(bad.status, 400, b)
    assert.equal(bad.json.error, 'not_resource_building')
  }
  assert.equal((await S.req('POST', '/v1/collect', { token, body: {} })).status, 400)
  const p = await S.req('GET', '/v1/player', { token })
  assert.deepEqual(p.json.player.res, { wood: 7230, stone: 3600, food: 0 })
  assert.equal((await logs(id, 'collect')).length, 5) // 20, 3600, 7200, 시계 되돌림, 10
})

test('판매: 현재 시세로 그 자원 전부 / all, 골드 증가, 0개면 0, 모르는 자원 400', async () => {
  const cfg = await CONFIG()
  // 시세가 1이 아닌 시간 칸을 고른다(내림이 보이게)
  let t = T0
  while (R.merchantRate(R.hourIndex(t), cfg) === 1) t += 3600
  S.clock.t = t
  const rate = R.merchantRate(R.hourIndex(t), cfg)
  const { token, id } = await S.login()
  await S.req('POST', '/v1/test/age', { token, body: { minutes: 7 } })
  await S.req('POST', '/v1/collect', { token, body: { building: 'lumber' } }) // 70
  await S.req('POST', '/v1/collect', { token, body: { building: 'quarry' } }) // 35
  await S.req('POST', '/v1/collect', { token, body: { building: 'farm' } }) // 70

  let r = await S.req('POST', '/v1/sell', { token, body: { res: 'stone' } })
  assert.equal(r.status, 200)
  assert.equal(r.json.rate, rate)
  assert.equal(r.json.gold_gained, Math.floor(35 * 2 * rate + 1e-9))
  assert.equal(r.json.player.res.stone, 0)
  assert.equal(r.json.player.gold, r.json.gold_gained)
  const g1 = r.json.player.gold

  r = await S.req('POST', '/v1/sell', { token, body: { res: 'all' } })
  const each = R.sellValue(70, 1, rate)
  assert.equal(r.json.gold_gained, each * 2)
  assert.deepEqual(r.json.player.res, { wood: 0, stone: 0, food: 0 })
  assert.equal(r.json.player.gold, g1 + each * 2)

  r = await S.req('POST', '/v1/sell', { token, body: { res: 'all' } })
  assert.equal(r.json.gold_gained, 0)
  assert.equal(r.json.player.gold, g1 + each * 2)
  const bad = await S.req('POST', '/v1/sell', { token, body: { res: 'gold' } })
  assert.equal(bad.status, 400)
  assert.equal(bad.json.error, 'unknown_resource')
  assert.equal((await logs(id, 'sell')).length, 2)
})

test('처치 골드: Σ count × kill_gold(id, stage), stage는 player.stage로 자름, 잘못된 입력 400', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  S.clock.t = T0 + 1000 // 상한 넉넉히
  let r = await S.req('POST', '/v1/kills', { token, body: { stage: 1, kills: { grunt: 10, epic_boss: 1 } } })
  assert.equal(r.status, 200)
  assert.equal(r.json.gold_gained, 10 * 2 + 50)
  assert.equal(r.json.player.gold, 70)

  await S.req('POST', '/v1/stage/clear', { token, body: { stage: 1 } })
  await S.req('POST', '/v1/stage/clear', { token, body: { stage: 2 } }) // 이제 stage 3
  S.clock.t += 1000
  r = await S.req('POST', '/v1/kills', { token, body: { stage: 3, kills: { grunt: 10, epic_boss: 1 } } })
  assert.equal(r.json.gold_gained, 10 * 3 + 70) // gold_mult 1.4: 2.8 → 3, 70
  S.clock.t += 1000
  r = await S.req('POST', '/v1/kills', { token, body: { stage: 99, kills: { grunt: 10 } } }) // 3으로 자름
  assert.equal(r.json.gold_gained, 30)
  S.clock.t += 1000
  r = await S.req('POST', '/v1/kills', { token, body: { stage: 2, kills: { grunt: 5 } } }) // 2.4 → 2
  assert.equal(r.json.gold_gained, 10)
  assert.equal(r.json.player.gold, 70 + 100 + 30 + 10)

  const before = r.json.player.gold
  for (const body of [
    { stage: 0, kills: { grunt: 1 } }, { stage: 1.5, kills: { grunt: 1 } }, { kills: { grunt: 1 } },
    { stage: 1, kills: { grunt: -1 } }, { stage: 1, kills: { grunt: 1.5 } }, { stage: 1, kills: [] }, { stage: 1 },
    { stage: 1, kills: { dragon: 1 } },
  ]) {
    const bad = await S.req('POST', '/v1/kills', { token, body })
    assert.equal(bad.status, 400, JSON.stringify(body))
  }
  assert.equal((await S.req('POST', '/v1/kills', { token, body: { stage: 1, kills: { dragon: 1 } } })).json.error, 'unknown_monster')
  assert.equal((await S.req('GET', '/v1/player', { token })).json.player.gold, before)
  const ks = await logs(id, 'kills')
  assert.equal(ks.length, 4)
  assert.deepEqual(ks[2].detail.kept, { grunt: 10 })
  assert.equal(ks[2].detail.stage, 3)
  assert.equal(ks[2].detail.asked_stage, 99)
})

test('처치 상한: ceil(지난 보고 이후 초 × kill_rate_cap) + 20, 넘는 만큼 버리고 clamped 로그', async () => {
  S.clock.t = T0
  const { token, id } = await S.login() // last_kill_report = T0
  S.clock.t = T0 + 10 // 상한 ceil(10 × 5) + 20 = 70
  let r = await S.req('POST', '/v1/kills', { token, body: { stage: 1, kills: { grunt: 100 } } })
  assert.equal(r.json.gold_gained, 70 * 2)
  r = await S.req('POST', '/v1/kills', { token, body: { stage: 1, kills: { grunt: 30 } } }) // 0초 뒤: 상한 20
  assert.equal(r.json.gold_gained, 20 * 2)
  S.clock.t += 10 // 상한 70: 싼 grunt부터 인정, 비싼 epic_boss를 먼저 버린다
  r = await S.req('POST', '/v1/kills', { token, body: { stage: 1, kills: { epic_boss: 20, grunt: 60 } } })
  assert.equal(r.json.gold_gained, 60 * 2 + 10 * 50)
  S.clock.t += 10 // 상한 안: 그대로
  r = await S.req('POST', '/v1/kills', { token, body: { stage: 1, kills: { grunt: 70 } } })
  assert.equal(r.json.gold_gained, 140)
  assert.equal(r.json.player.gold, 140 + 40 + 620 + 140)
  const ks = await logs(id, 'kills')
  assert.deepEqual(ks.map((k) => k.detail.clamped), [true, true, true, false])
  assert.deepEqual(ks.map((k) => k.detail.cap), [70, 20, 70, 70])
  assert.deepEqual(ks[2].detail.kept, { epic_boss: 10, grunt: 60 })
  const [st] = await S.db.query('select extract(epoch from last_kill_report)::float8 as t from player_state where player_id = $1', [id])
  assert.equal(st.t, S.clock.t)
})

test('스테이지 클리어: 같으면 +1, 아니면 그대로(중복·재전송 안전)', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  let r = await S.req('POST', '/v1/stage/clear', { token, body: { stage: 1 } })
  assert.equal(r.status, 200)
  assert.equal(r.json.player.stage, 2)
  r = await S.req('POST', '/v1/stage/clear', { token, body: { stage: 1 } }) // 재전송
  assert.equal(r.json.player.stage, 2)
  r = await S.req('POST', '/v1/stage/clear', { token, body: { stage: 5 } }) // 앞지름
  assert.equal(r.json.player.stage, 2)
  const [a, b] = await Promise.all([
    S.req('POST', '/v1/stage/clear', { token, body: { stage: 2 } }),
    S.req('POST', '/v1/stage/clear', { token, body: { stage: 2 } }),
  ])
  assert.deepEqual([a.json.player.stage, b.json.player.stage], [3, 3])
  assert.equal((await S.req('GET', '/v1/player', { token })).json.player.stage, 3)
  assert.equal((await S.req('POST', '/v1/stage/clear', { token, body: { stage: 0 } })).status, 400)
  assert.equal((await logs(id, 'stage_clear')).length, 2)
})

test('gamedata: CSV 열 이름 키, 파일 순서, config 문자열, version = 내용 해시(ETag), 내용이 바뀌면 바뀐다', async () => {
  const r = await S.req('GET', '/v1/gamedata')
  assert.equal(r.status, 200)
  const g = r.json
  assert.match(g.version, /^[0-9a-f]{16}$/)
  assert.equal(r.headers.get('etag'), `"${g.version}"`)
  assert.deepEqual(g.monsters[0], { id: 'grunt', hp: 60, atk: 10, speed: 2.5, range: 1.2, atk_interval: 1, aggro: 6, scale: 1, gold: 2 })
  assert.deepEqual(g.monsters.map((m: any) => m.id), ['grunt', 'epic_boss'])
  assert.equal(g.stages.length, 30)
  assert.deepEqual(g.stages[1], { stage: 2, hp_mult: 1.25, atk_mult: 1.15, gold_mult: 1.2, waves: 3, wave_size: 10, idle_interval: 4 })
  assert.deepEqual(g.heroes.map((h: any) => h.id), ['warrior', 'archer'])
  assert.deepEqual(g.heroes[1], { id: 'archer', name: '궁수', hp: 220, atk: 20, range: 9, atk_interval: 1, speed: 6, aggro: 12 })
  assert.deepEqual(g.resources.map((x: any) => x.id), ['wood', 'stone', 'food']) // 파일 순서
  assert.deepEqual(g.resources[1], { id: 'stone', name: '석재', building: 'quarry', per_min: 5, price: 2 })
  assert.equal(g.config.hero_slots, '4|8|12')
  assert.equal(g.config.kill_rate_cap, '5')
  assert.equal(Object.keys(g.config).length, 18)

  const again = await S.req('GET', '/v1/gamedata')
  assert.equal(again.json.version, g.version)
  const cached = await S.req('GET', '/v1/gamedata', { headers: { 'if-none-match': `"${g.version}"` } })
  assert.equal(cached.status, 304)

  await S.db.query("update monsters set gold = 3 where id = 'grunt'")
  const changed = await S.req('GET', '/v1/gamedata')
  assert.notEqual(changed.json.version, g.version)
  assert.equal(changed.json.monsters[0].gold, 3)
  await S.db.query("update monsters set gold = 2 where id = 'grunt'")
  assert.equal((await S.req('GET', '/v1/gamedata')).json.version, g.version)
  await S.db.query("update game_config set value = '6' where key = 'kill_rate_cap'")
  assert.notEqual((await S.req('GET', '/v1/gamedata')).json.version, g.version)
  await S.db.query("update game_config set value = '5' where key = 'kill_rate_cap'")
})

test('test/age: ALLOW_TEST_HOOKS면 last_collect를 minutes분 앞당김, 없으면 404', async () => {
  S.clock.t = T0
  const { token } = await S.login()
  const r = await S.req('POST', '/v1/test/age', { token, body: { minutes: 10 } })
  assert.equal(r.status, 200)
  assert.equal(r.json.player.buildings.lumber.last_collect, T0 - 600)
  assert.equal(r.json.player.buildings.farm.last_collect, T0 - 600)
  assert.equal((await S.req('POST', '/v1/collect', { token, body: { building: 'lumber' } })).json.amount, 100)
  assert.equal((await S.req('POST', '/v1/test/age', { token, body: { minutes: 'x' } })).status, 400)

  const noHooks = S.makeApp({ allowTestHooks: false })
  const res = await noHooks.request('/v1/test/age', {
    method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: '{"minutes":10}',
  })
  assert.equal(res.status, 404)
  assert.equal((await res.json()).error, 'not_found')
})

test('플레이어 격리: A의 토큰으로 B의 상태를 바꿀 수 없다', async () => {
  S.clock.t = T0
  const A = await S.login()
  const B = await S.login()
  const bBefore = (await S.req('GET', '/v1/player', { token: B.token })).json.player
  S.clock.t = T0 + 600
  // body에 B의 id를 넣어도 무시된다 — 플레이어는 토큰의 sub로만 정해진다
  await S.req('POST', '/v1/test/age', { token: A.token, body: { minutes: 30, player_id: B.id } })
  const ca = await S.req('POST', '/v1/collect', { token: A.token, body: { building: 'lumber', player_id: B.id } })
  assert.equal(ca.json.amount, 400)
  await S.req('POST', '/v1/kills', { token: A.token, body: { stage: 1, kills: { grunt: 5 }, player_id: B.id } })
  await S.req('POST', '/v1/stage/clear', { token: A.token, body: { stage: 1, player_id: B.id } })
  await S.req('POST', '/v1/sell', { token: A.token, body: { res: 'all', player_id: B.id } })
  // A의 서명을 그대로 두고 sub만 B로 바꾼 토큰은 거부된다
  const [h, payload, sig] = A.token.split('.')
  const p = JSON.parse(Buffer.from(payload, 'base64url').toString())
  const forged = `${h}.${Buffer.from(JSON.stringify({ ...p, sub: B.id })).toString('base64url')}.${sig}`
  assert.equal((await S.req('POST', '/v1/stage/clear', { token: forged, body: { stage: 1 } })).status, 401)
  assert.equal((await S.req('POST', '/v1/collect', { token: forged, body: { building: 'farm' } })).status, 401)

  const bAfter = (await S.req('GET', '/v1/player', { token: B.token })).json.player
  assert.deepEqual(bAfter, bBefore)
  const a = (await S.req('GET', '/v1/player', { token: A.token })).json.player
  assert.equal(a.stage, 2)
  assert.ok(a.gold > 0)
  const bLogs = await S.db.query('select count(*)::int as n from economy_log where player_id = $1', [B.id])
  assert.equal(bLogs[0].n, 0)
})

test('본문 16 KB 초과는 413 payload_too_large(인증 전에), 이하는 통과', async () => {
  const pad = (n: number) => JSON.stringify({ device_id: 'x', pad: 'a'.repeat(n) })
  const big = pad(16 * 1024) // 16 KB + 머리
  const r = await S.req('POST', '/v1/auth/guest', { body: big })
  assert.equal(r.status, 413)
  assert.equal(r.json.error, 'payload_too_large')
  assert.equal((await S.req('POST', '/v1/kills', { body: big })).status, 413) // 토큰 검사보다 먼저
  const fits = pad(16 * 1024 - 40)
  assert.ok(fits.length <= 16 * 1024)
  assert.equal((await S.req('POST', '/v1/auth/guest', { body: fits })).json.error, 'bad_device_id')
  // Content-Length만 보고 읽기 전에 끊는다(Node 서버 경로)
  const app = S.makeApp()
  const cl = await app.request('/v1/auth/guest', { method: 'POST', headers: { 'content-type': 'application/json', 'content-length': '999999' }, body: '{}' })
  assert.equal(cl.status, 413)
})

test('알 수 없는 경로는 404 JSON, CORS 기본 *', async () => {
  const r = await S.req('GET', '/v1/nope')
  assert.equal(r.status, 404)
  assert.equal(r.json.error, 'not_found')
  const pre = await S.req('OPTIONS', '/v1/player', {
    headers: { origin: 'http://localhost:8060', 'access-control-request-method': 'GET', 'access-control-request-headers': 'authorization' },
  })
  assert.equal(pre.status, 204)
  assert.equal(pre.headers.get('access-control-allow-origin'), '*')
  assert.match(pre.headers.get('access-control-allow-headers') ?? '', /Authorization/)
  const only = S.makeApp({ corsOrigins: ['http://localhost:8060'] })
  const ok = await only.request('/v1/health', { headers: { origin: 'http://localhost:8060' } })
  assert.equal(ok.headers.get('access-control-allow-origin'), 'http://localhost:8060')
  const no = await only.request('/v1/health', { headers: { origin: 'http://evil.example' } })
  assert.equal(no.headers.get('access-control-allow-origin'), null)
})

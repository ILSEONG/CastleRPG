// 길드(마이그레이션 020, server/src/guild.ts): 잠금, 추천(시스템 길드 자동 생성), 가입·창설(골드 500,000·이름 중복)·탈퇴(길드장 위임·빈 길드 삭제),
// 출석·상자, 기부(비용·한도), 보스(피해·등급·횟수·누적 단계·처치 보상), 상점(코인·한도·조각), 일일 초기화, 가상 길드원(경험치가 시간 따라 늘고 겨뤄도 두 번 안 센다).
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as G from '../src/guild.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup()
})
after(async () => {
  await S.close()
})

const guild = async (token: string) => (await S.req('GET', '/v1/guild', { token })).json.guild
const post = (token: string, path: string, body: unknown = {}) => S.req('POST', `/v1/guild/${path}`, { token, body })
const setStage = (id: string, n: number) => S.db.query('update player_state set stage = $2 where player_id = $1', [id, n])
const setGold = (id: string, gold: number) => S.db.query('update player_state set gold_tenths = $2 where player_id = $1', [id, gold * 10])
const setDia = (id: string, n: number) => S.db.query('update player_state set diamonds = $2 where player_id = $1', [id, n])

async function ready() {
  const p = await S.login()
  await setStage(p.id, 11)
  return p
}

test('guild rules: levels, boss steps and virtual members are deterministic', () => {
  assert.equal(G.levelOf(0).level, 1)
  assert.equal(G.levelOf(G.expNeed(1)).level, 2)
  assert.deepEqual(G.bossOf(0), { level: 1, hp: G.bossMax(1), max: G.bossMax(1) })
  const b = G.bossOf(G.bossMax(1) + 10)
  assert.equal(b.level, 2)
  assert.equal(b.hp, G.bossMax(2) - 10)
  // 판 등급 = 한 판에서 도달한 드래곤 레벨(Lv 1부터)
  const reach = (lv: number) => Array.from({ length: lv - 1 }, (_, i) => G.bossMax(i + 1)).reduce((a, b2) => a + b2, 0)
  assert.equal(G.bossOf(reach(15)).level, 15)
  assert.equal(G.bossGrade(reach(15))[0], 'S')
  assert.equal(G.bossGrade(reach(15) - 1)[0], 'A')
  assert.equal(G.bossGrade(reach(3))[0], 'C')
  assert.equal(G.bossGrade(1)[0], 'D')
  const g = { id: 'x', seed: 123, created_at: T0 - 10 * 86400, virtual_n: 15, system: true }
  const a = G.virtualTotals(g, T0, 15)
  assert.deepEqual(a.exp, G.virtualTotals(g, T0, 15).exp)
  assert.ok(a.exp > 0 && a.dmg > 0)
  assert.ok(G.virtualTotals(g, T0 + 86400, 15).exp > a.exp, 'virtual exp grows with time')
  const made = G.virtualMembers({ ...g, system: false, created_at: T0, virtual_n: 10 })
  assert.ok(made.every((m, i) => i === 0 || m.join_t > made[i - 1].join_t), 'created guild: virtual members join one by one')
  assert.equal(G.playerName('8f1e0a0e-0000-4000-8000-000000000001'), G.playerName('8f1e0a0e-0000-4000-8000-000000000001'))
  // 레벨 끝 없음(레벨마다 버프 +1%), 인원 15명 → 6레벨부터 20명(그 뒤로도 20명)
  assert.ok(G.levelOf(1e9).level > 6)
  assert.equal(G.buffPct(40), 40)
  assert.deepEqual([1, 5, 6, 30].map(G.capacity), [15, 15, 20, 20])
  const vm = G.virtualMembers({ ...g, virtual_n: 18 })
  assert.equal(G.seated(vm, T0, 15, 3).length, 12, 'virtual members only fill the seats real players leave')
})

test('guild: locked before round 1-10, then 5 recommendations', async () => {
  const p = await S.login()
  let r = await S.req('GET', '/v1/guild', { token: p.token })
  assert.equal(r.status, 200)
  assert.equal(r.json.guild.unlocked, false)
  assert.equal(r.json.guild.recommendations, undefined)
  assert.equal((await post(p.token, 'create', { name: '테스트', emblem: 0 })).json.error, 'locked')
  await setStage(p.id, 11)
  const v = await guild(p.token)
  assert.equal(v.unlocked, true)
  assert.equal(v.guild, null)
  assert.equal(v.recommendations.length, 5)
  assert.ok(v.recommendations.every((x: any) => x.level >= 1 && x.count >= 12 && x.count <= x.capacity && x.capacity === G.capacity(x.level) && typeof x.name === 'string'))
})

test('guild: join, attend, box, donate, leave keeps coins', async () => {
  const p = await ready()
  const rec = (await guild(p.token)).recommendations[0]
  let r = await post(p.token, 'join', { guild_id: rec.id })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  assert.equal(r.json.guild.guild.id, rec.id)
  assert.ok(r.json.guild.guild.members.length >= 12)
  assert.ok(r.json.guild.guild.members.length + 1 <= r.json.guild.guild.capacity, 'members + me fit the capacity')
  assert.equal((await post(p.token, 'join', { guild_id: rec.id })).json.error, 'in_guild')
  const gold0 = r.json.player.gold_tenths
  r = await post(p.token, 'attend')
  assert.equal(r.status, 200)
  assert.equal(r.json.player.gold_tenths, gold0 + 30000)
  assert.equal(r.json.guild.coins, 30)
  assert.equal(r.json.guild.me.attended, true)
  assert.equal((await post(p.token, 'attend')).json.error, 'attended')
  const count = r.json.guild.guild.attend_count
  r = await post(p.token, 'box', { index: 0 })
  if (count >= 5) {
    assert.equal(r.status, 200)
    assert.equal(r.json.guild.coins, 50)
    assert.equal((await post(p.token, 'box', { index: 0 })).json.error, 'claimed')
  } else assert.equal(r.json.error, 'locked')
  await setGold(p.id, 15000)
  await setDia(p.id, 60)
  r = await post(p.token, 'donate', { kind: 'gold' })
  assert.equal(r.status, 200)
  assert.equal(r.json.player.gold, 5000)
  assert.equal((await post(p.token, 'donate', { kind: 'gold' })).json.error, 'not_enough_gold')
  r = await post(p.token, 'donate', { kind: 'dia' })
  assert.equal(r.json.player.diamonds, 10)
  assert.equal((await post(p.token, 'donate', { kind: 'dia' })).json.error, 'donated')
  assert.equal((await post(p.token, 'donate', { kind: 'royal' })).json.error, 'not_enough_diamonds')
  const coins = r.json.guild.coins
  r = await post(p.token, 'leave')
  assert.equal(r.status, 200)
  assert.equal(r.json.guild.guild, null)
  assert.equal(r.json.guild.coins, coins)
  assert.equal(r.json.guild.me.attended, true, 'attendance stays used for the day after leaving')
})

test('guild: real members see each other, real exp adds to the guild, real players take seats from virtual members', async () => {
  const a = await ready()
  await setGold(a.id, G.CREATE_GOLD)
  const gid = (await post(a.token, 'create', { name: '실제길드', emblem: 1 })).json.guild.guild.id
  const b = await ready()
  await post(b.token, 'join', { guild_id: gid })
  await post(b.token, 'attend')
  const v = (await guild(a.token)).guild
  assert.ok(v.members.some((m: any) => m.real && m.att && m.name === G.playerName(b.id)))
  assert.equal(v.level, 1)
  assert.equal(v.exp, G.ATTEND_EXP, 'real attendance exp goes to the guild')
  // 시스템 길드가 가상 길드원으로 꽉 차 있어도 실제 유저가 들어오면 가상 길드원이 자리를 비운다
  const c = await ready()
  const rec = (await guild(c.token)).recommendations[1]
  const before = rec.count
  await post(c.token, 'join', { guild_id: rec.id })
  const w = (await guild(c.token)).guild
  assert.ok(w.members.length + 1 <= w.capacity)
  assert.equal(w.members.length + 1, Math.min(before + 1, w.capacity))
})

test('guild: create costs 500,000 gold, names are unique, owner leaving hands over or deletes', async () => {
  const a = await ready()
  await setGold(a.id, G.CREATE_GOLD - 1)
  assert.equal((await post(a.token, 'create', { name: '우리길드', emblem: 2 })).json.error, 'not_enough_gold')
  assert.equal((await post(a.token, 'create', { name: '가', emblem: 2 })).json.error, 'bad_name')
  await setGold(a.id, G.CREATE_GOLD + 10)
  let r = await post(a.token, 'create', { name: '우리길드', emblem: 2 })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  assert.equal(r.json.player.gold, 10)
  assert.equal(r.json.guild.guild.mine, true)
  assert.equal(r.json.guild.guild.level, 1)
  assert.equal(r.json.guild.guild.members.length, 0, 'virtual members have not joined yet')
  const gid = r.json.guild.guild.id
  const b = await ready()
  await setGold(b.id, G.CREATE_GOLD)
  assert.equal((await post(b.token, 'create', { name: '우리길드', emblem: 1 })).json.error, 'name_taken')
  await post(b.token, 'join', { guild_id: gid })
  S.clock.t += 86400
  assert.ok((await guild(b.token)).guild.members.length >= 5, 'virtual members join over the day')
  r = await post(a.token, 'leave')
  assert.equal(r.status, 200)
  const [g1] = await S.db.query('select owner::text from guilds where id = $1', [gid])
  assert.equal(g1.owner, b.id, 'owner hands over to the next real member')
  await post(b.token, 'leave')
  assert.equal((await S.db.query('select 1 from guilds where id = $1', [gid])).length, 0, 'an empty created guild is deleted')
  S.clock.t -= 86400
})

test('guild: real boss fight — every fight starts at Lv 1, finish takes the damage (capped, not too early), score adds up, daily reset', async () => {
  const p = await ready()
  const rec = (await guild(p.token)).recommendations[2]
  await post(p.token, 'join', { guild_id: rec.id })
  const v0 = await guild(p.token)
  assert.ok(v0.dps > 0)
  let r = await post(p.token, 'boss/start')
  assert.equal(r.status, 200, JSON.stringify(r.json))
  const run = r.json.result
  assert.equal(run.sec, G.BOSS_FIGHT_SEC)
  assert.equal(run.level, 1)
  assert.equal(run.hp, G.bossMax(1))
  const score0 = v0.guild.boss.score
  assert.equal(r.json.guild.me.boss_tries, 1, 'starting uses a try')
  assert.equal((await post(p.token, 'boss/finish', { run_id: run.run_id, dmg: 1000 })).json.error, 'too_early')
  S.clock.t += Math.ceil(G.BOSS_FIGHT_SEC / 1.5 - G.BOSS_SLACK_SEC) // x1.5 배속: 40 게임 초 = 실제 26.7초(− 여유 2)
  assert.equal((await post(p.token, 'boss/finish', { run_id: 'nope', dmg: 1000 })).json.error, 'no_run')
  r = await post(p.token, 'boss/finish', { run_id: run.run_id, dmg: 1234 })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  const res = r.json.result
  assert.equal(res.dmg, 1234)
  assert.equal(res.grade, G.bossGrade(1234)[0])
  assert.equal(res.level, G.bossOf(1234).level)
  assert.ok(r.json.guild.guild.boss.score >= score0 + 1234, 'guild score = sum of member scores')
  assert.equal(r.json.guild.coins, res.coins)
  assert.equal(r.json.guild.me.boss_best, 1234)
  assert.equal(r.json.guild.me.boss_run, null)
  assert.equal((await post(p.token, 'boss/finish', { run_id: run.run_id, dmg: 1 })).json.error, 'no_run', 'a fight finishes once')
  // 두 번째: 상한(시작 때 초당 피해 × 초 × BOSS_DMG_CAP)을 넘는 피해는 잘린다
  const run2 = (await post(p.token, 'boss/start')).json.result
  assert.equal((await post(p.token, 'boss/start')).json.error, 'no_tries')
  S.clock.t += G.BOSS_FIGHT_SEC
  r = await post(p.token, 'boss/finish', { run_id: run2.run_id, dmg: 1e11 })
  assert.ok(Math.abs(r.json.result.dmg - v0.dps * G.BOSS_FIGHT_SEC * G.BOSS_DMG_CAP) <= G.BOSS_FIGHT_SEC * G.BOSS_DMG_CAP, 'capped (view dps is rounded)')
  assert.equal(r.json.result.sent, 1e11)
  assert.equal(r.json.guild.me.boss_total, 1234 + r.json.result.dmg, 'my score = both fights')
  S.clock.t -= 2 * G.BOSS_FIGHT_SEC
  S.clock.t += 86400
  const nx = await guild(p.token)
  assert.equal(nx.me.boss_tries, 0)
  assert.equal(nx.me.attended, false)
  S.clock.t -= 86400
})

test('guild: a boss fight left too long finishes with 0 damage', async () => {
  const p = await ready()
  const rec = (await guild(p.token)).recommendations[4]
  await post(p.token, 'join', { guild_id: rec.id })
  const run = (await post(p.token, 'boss/start')).json.result
  S.clock.t += G.BOSS_RUN_TTL + 1
  const r = await post(p.token, 'boss/finish', { run_id: run.run_id, dmg: 500 })
  assert.equal(r.status, 200)
  assert.equal(r.json.result.dmg, 0)
  assert.equal(r.json.result.grade, 'D')
  S.clock.t -= G.BOSS_RUN_TTL + 1
})

test('guild: shop spends coins with limits and gives shards of owned heroes', async () => {
  const p = await ready()
  const rec = (await guild(p.token)).recommendations[3]
  await post(p.token, 'join', { guild_id: rec.id })
  await S.db.query('update player_guild set coins = 1000 where player_id = $1', [p.id])
  const dia0 = (await S.req('GET', '/v1/player', { token: p.token })).json.player.diamonds
  let r = await post(p.token, 'buy', { id: 'dia' })
  assert.equal(r.status, 200)
  assert.equal(r.json.player.diamonds, dia0 + 50)
  assert.equal(r.json.guild.coins, 850)
  await post(p.token, 'buy', { id: 'dia' })
  assert.equal((await post(p.token, 'buy', { id: 'dia' })).json.error, 'sold_out')
  const shards = (pl: any) => Object.values(pl.heroes).reduce((s: number, h: any) => s + h.shards, 0)
  const before = shards((await S.req('GET', '/v1/player', { token: p.token })).json.player)
  r = await post(p.token, 'buy', { id: 'shards' })
  assert.equal(r.status, 200)
  assert.equal(shards(r.json.player), before + 3)
  assert.equal(r.json.guild.coins, 500)
  // 장비 상자(식량 대신): 장비 던전 최고 단계(없으면 1)의 드롭 하나
  assert.equal(G.SHOP.some((s2) => s2.id === 'food'), false)
  const items0 = r.json.player.items.length
  r = await post(p.token, 'buy', { id: 'equip' })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  assert.equal(r.json.player.items.length, items0 + 1)
  assert.equal(r.json.player.items.at(-1).level, undefined) // 장비 레벨 없음(2026-10-07), 굴림만
  assert.equal(Object.keys(r.json.player.items.at(-1).rolls).length > 0, true)
  assert.equal(r.json.guild.coins, 450)
  assert.equal((await post(p.token, 'buy', { id: 'nope' })).status, 400)
})

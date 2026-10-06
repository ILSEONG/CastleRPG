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
  assert.equal(G.bossGrade(G.bossMax(1) * 0.25, 1)[0], 'S')
  assert.equal(G.bossGrade(1, 1)[0], 'D')
  const g = { id: 'x', seed: 123, created_at: T0 - 10 * 86400, virtual_n: 15, system: true }
  const a = G.virtualTotals(g, T0, 15)
  assert.deepEqual(a.exp, G.virtualTotals(g, T0, 15).exp)
  assert.ok(a.exp > 0 && a.dmg > 0)
  assert.ok(G.virtualTotals(g, T0 + 86400, 15).exp > a.exp, 'virtual exp grows with time')
  const made = G.virtualMembers({ ...g, system: false, created_at: T0, virtual_n: 10 })
  assert.ok(made.every((m, i) => i === 0 || m.join_t > made[i - 1].join_t), 'created guild: virtual members join one by one')
  assert.equal(G.playerName('8f1e0a0e-0000-4000-8000-000000000001'), G.playerName('8f1e0a0e-0000-4000-8000-000000000001'))
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
  assert.ok(v.recommendations.every((x: any) => x.level >= 1 && x.count >= 12 && x.count < 30 && typeof x.name === 'string'))
})

test('guild: join, attend, box, donate, leave keeps coins', async () => {
  const p = await ready()
  const rec = (await guild(p.token)).recommendations[0]
  let r = await post(p.token, 'join', { guild_id: rec.id })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  assert.equal(r.json.guild.guild.id, rec.id)
  assert.ok(r.json.guild.guild.members.length >= 12)
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

test('guild: real members see each other and real exp adds to the guild', async () => {
  const a = await ready()
  const b = await ready()
  const rec = (await guild(a.token)).recommendations[1]
  await post(a.token, 'join', { guild_id: rec.id })
  const before = (await guild(a.token)).guild
  await post(b.token, 'join', { guild_id: rec.id })
  await post(b.token, 'attend')
  const v = (await guild(a.token)).guild
  assert.equal(v.members.length, before.members.length + 1)
  assert.ok(v.members.some((m: any) => m.real && m.att && m.name === G.playerName(b.id)))
  const total = (x: any) => G.levelOf(0).need * 0 + x.exp + Array.from({ length: x.level - 1 }, (_, i) => G.expNeed(i + 1)).reduce((s, n) => s + n, 0)
  assert.equal(total(v), total(before) + G.ATTEND_EXP)
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

test('guild: boss fight, 2 tries a day, grades, kill rewards, daily reset', async () => {
  const p = await ready()
  const rec = (await guild(p.token)).recommendations[2]
  await post(p.token, 'join', { guild_id: rec.id })
  const v0 = await guild(p.token)
  assert.ok(v0.dps > 0)
  let r = await post(p.token, 'boss')
  assert.equal(r.status, 200, JSON.stringify(r.json))
  const res = r.json.result
  assert.ok(res.dmg > 0 && ['S', 'A', 'B', 'C', 'D'].includes(res.grade))
  assert.equal(res.grade, G.bossGrade(res.dmg, res.level)[0])
  assert.equal(r.json.guild.coins, res.coins)
  await post(p.token, 'boss')
  assert.equal((await post(p.token, 'boss')).json.error, 'no_tries')
  // 보스를 쓰러뜨리면(실제 누적을 크게) 처치 보상이 쌓이고 한 번에 받는다
  await S.db.query('update guilds set boss_damage = boss_damage + $2 where id = $1', [rec.id, G.bossMax(50) * 3])
  const v = await guild(p.token)
  assert.ok(v.boss_pending >= 1)
  const dia0 = (await S.req('GET', '/v1/player', { token: p.token })).json.player.diamonds
  r = await post(p.token, 'claim')
  assert.equal(r.status, 200)
  assert.equal(r.json.player.diamonds, dia0 + G.BOSS_KILL_REWARD.diamonds * v.boss_pending)
  assert.equal(r.json.guild.boss_pending, 0)
  assert.equal((await post(p.token, 'claim')).json.error, 'nothing')
  S.clock.t += 86400
  const nx = await guild(p.token)
  assert.equal(nx.me.boss_tries, 0)
  assert.equal(nx.me.attended, false)
  S.clock.t -= 86400
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
  assert.equal((await post(p.token, 'buy', { id: 'nope' })).status, 400)
})

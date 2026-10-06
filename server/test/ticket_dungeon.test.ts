// 모집권 던전(2026-10-06): 도우미 후보(전투력 ±10%·오늘 쓴 영웅 제외), start 검사(helper 필수·후보만·편성 중복), 클리어 보상(다이아 모집권)·
// 도우미 하루 1회, 일일 리셋 때 도우미 목록 비우기, 022 마이그레이션.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as R from '../src/rules.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup()
})
after(async () => {
  await S.close()
})

const EQ4 = ['hans', 'ella', 'dorik', 'nina']
const player = async (token: string) => (await S.req('GET', '/v1/player', { token })).json.player
const start = (token: string, body: unknown) => S.req('POST', '/v1/dungeon/start', { token, body })
const finish = (token: string, body: unknown) => S.req('POST', '/v1/dungeon/finish', { token, body })
const age = (token: string, runId: string, seconds: number) => S.req('POST', '/v1/test/dungeon_age', { token, body: { run_id: runId, seconds } })

async function fresh() {
  S.clock.t = T0
  const { token, id } = await S.login()
  for (const h of ['hans', 'ella', 'dorik', 'nina', 'arteon', 'ignis']) await S.db.query('insert into player_heroes (player_id, hero_id) values ($1, $2) on conflict do nothing', [id, h])
  await player(token)
  return { token, id }
}

test('도우미 후보: 3명, 기준(상위 4명 평균) ±10% 안, 승급 = 평균, 오늘 쓴 영웅은 빠진다, 같은 날·같은 키는 같은 후보', () => {
  const cfg: R.Config = { hero_level_stat: '0.07', hero_level_stat_melee: '0.07', promote_mult: '1.3', hero_max_level_base: '30', hero_max_level_per_promotion: '10' }
  const defs = Array.from({ length: 12 }, (_, i) => ({ id: `h${i}`, hp: 300 + i * 40, atk: 20 + i * 3, atk_interval: 1.2, role: i % 2 ? 'melee' : 'ranged' }))
  const owned = defs.slice(0, 4).map((def, i) => ({ def, level: 10 + i, promotion: 1, equip: { hp: 0, atk: 0 } }))
  const ref = owned.reduce((s, o) => s + R.heroPower(o.def, o.level, o.promotion, o.equip, cfg), 0) / 4
  const a = R.helperCandidates(defs, owned, [], 'k', 100, cfg)
  assert.equal(a.length, 3)
  assert.equal(new Set(a.map((h) => h.hero_id)).size, 3)
  for (const h of a) {
    assert.equal(h.promotion, 1)
    assert.ok(Math.abs(h.power - ref) / ref <= R.HELPER_FIT, `${h.hero_id} ${h.power} vs ${ref}`)
    assert.equal(h.power, R.heroPower(defs.find((d) => d.id === h.hero_id)!, h.level, 1, { hp: 0, atk: 0 }, cfg))
  }
  assert.deepEqual(R.helperCandidates(defs, owned, [], 'k', 100, cfg), a)
  const b = R.helperCandidates(defs, owned, [a[0].hero_id], 'k', 100, cfg)
  assert.ok(!b.some((h) => h.hero_id === a[0].hero_id))
  assert.equal(b.length, 3)
  assert.equal(R.ticketReward({ ticket_reward_base: '1', ticket_reward_step: '10' }, 1), 1)
  assert.equal(R.ticketReward({ ticket_reward_base: '1', ticket_reward_step: '10' }, 10), 1)
  assert.equal(R.ticketReward({ ticket_reward_base: '1', ticket_reward_step: '10' }, 11), 2)
})

test('모집권 던전: 상태에 후보 3명, helper 없거나 후보 밖이면 거부, 편성과 겹치면 거부, 승리 = 열쇠 1 → 모집권, 도우미는 그날 다시 못 쓴다', async () => {
  const { token } = await fresh()
  const p = await player(token)
  const t = p.dungeons.ticket
  assert.equal(t.keys, 1)
  assert.equal(t.key_cap, 3)
  assert.equal(t.helpers.length, 3)
  assert.deepEqual(t.helpers_used, [])
  assert.equal(p.dia_tickets, 0)
  const helper = t.helpers[0].hero_id
  const party = [...EQ4, 'arteon', 'ignis'].filter((h) => h !== helper).slice(0, 4)
  assert.equal((await start(token, { type: 'ticket', level: 1, party })).json.error, 'bad_party') // helper 없음
  const notOffered = ['hans', 'ella', 'dorik', 'nina', 'arteon', 'ignis'].find((h) => !t.helpers.some((x: any) => x.hero_id === h))
  assert.equal((await start(token, { type: 'ticket', level: 1, party, helper: notOffered })).json.error, 'helper_unavailable')
  assert.equal((await start(token, { type: 'ticket', level: 1, party: party.slice(0, 3), helper })).json.error, 'bad_party') // 4명
  const owned = t.helpers.find((h: any) => [...EQ4, 'arteon', 'ignis'].includes(h.hero_id))
  if (owned) assert.equal((await start(token, { type: 'ticket', level: 1, party: [owned.hero_id, ...party.filter((x) => x !== owned.hero_id)].slice(0, 4), helper: owned.hero_id })).json.error, 'bad_party')
  const s = await start(token, { type: 'ticket', level: 1, party, helper })
  assert.equal(s.status, 200, JSON.stringify(s.json))
  assert.equal(s.json.helper.hero_id, helper)
  assert.ok(s.json.enemies.some((e: any) => e.kind === 'rock_golem'))
  await age(token, s.json.run_id, 25)
  const f = await finish(token, { run_id: s.json.run_id, win: true, elapsed: 21 })
  assert.equal(f.status, 200, JSON.stringify(f.json))
  assert.deepEqual(f.json.rewards, { tickets: 1 })
  const q = await player(token)
  assert.equal(q.dia_tickets, 1)
  assert.equal(q.dungeons.ticket.keys, 0)
  assert.equal(q.dungeons.ticket.best_level, 1)
  assert.deepEqual(q.dungeons.ticket.helpers_used, [helper])
  assert.ok(!q.dungeons.ticket.helpers.some((h: any) => h.hero_id === helper))
  assert.equal((await start(token, { type: 'ticket', level: 2, party, helper })).json.error, 'helper_used')
  // 다음 날: 열쇠 1, 쓴 도우미 목록 비움
  S.clock.t = T0 + 86400
  const n = await player(token)
  assert.equal(n.dungeons.ticket.keys, 1)
  assert.deepEqual(n.dungeons.ticket.helpers_used, [])
})

test('모집권 던전 패배: 열쇠·도우미 그대로', async () => {
  const { token } = await fresh()
  const t = (await player(token)).dungeons.ticket
  const helper = t.helpers[1].hero_id
  const party = ['hans', 'ella', 'dorik', 'nina', 'arteon'].filter((h) => h !== helper).slice(0, 4)
  const s = await start(token, { type: 'ticket', level: 1, party, helper })
  assert.equal(s.status, 200, JSON.stringify(s.json))
  const f = await finish(token, { run_id: s.json.run_id, win: false, elapsed: 30 })
  assert.equal(f.json.win, false)
  const q = await player(token)
  assert.equal(q.dungeons.ticket.keys, 1)
  assert.deepEqual(q.dungeons.ticket.helpers_used, [])
  assert.equal(q.dia_tickets, 0)
})

// 이탈 기록(retention.ts): 접속한 날 기록(하루 한 행), 관리자 통계 — 가입일별 D1·D7, 가이드 단계에서 멈춘 수·이탈 수. 일반 플레이어는 403.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as RT from '../src/retention.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
const DAY = 86400
before(async () => {
  S = await setup()
  S.clock.t = T0
})
// 지금 시계로 관리자 계정을 하나 만든다(토큰 기한 때문에 시계를 옮긴 뒤에 만든다)
async function makeAdmin() {
  const a = await S.login()
  const email = `rt-admin-${a.id}@example.com`
  await S.db.query("insert into player_identities (provider, provider_uid, player_id, email) values ('google', $2, $1, $2)", [a.id, email])
  await S.db.query('insert into admin_emails (email) values ($1) on conflict do nothing', [email])
  return a
}
after(async () => {
  await S.close()
})

const days = async (id: string) => (await S.db.query('select day from player_days where player_id = $1 order by day', [id])).map((r: any) => Number(r.day))

test('KST 날짜: 15:00 UTC에 바뀐다', () => {
  const d = RT.kstDay(Date.UTC(2026, 9, 22, 14, 59) / 1000)
  assert.equal(RT.kstDay(Date.UTC(2026, 9, 22, 15, 0) / 1000), d + 1)
  assert.equal(RT.dayDate(d), '2026-10-22')
})

test('접속한 날: 인증된 요청이 하루 한 행씩 남긴다', async () => {
  S.clock.t = T0
  const p = await S.login()
  await S.req('GET', '/v1/missions', { token: p.token })
  await S.req('GET', '/v1/missions', { token: p.token })
  const d0 = RT.kstDay(T0)
  assert.deepEqual(await days(p.id), [d0])
  S.clock.t = T0 + DAY
  await S.req('GET', '/v1/missions', { token: p.token })
  assert.deepEqual(await days(p.id), [d0, d0 + 1])
  S.clock.t = T0
})

test('관리자 통계: 가입일별 D1·D7, 가이드 멈춘 단계·이탈, 일반 플레이어는 403', async () => {
  const base = T0 + 40 * DAY
  S.clock.t = base
  const d0 = RT.kstDay(base)
  const ps = [await S.login(), await S.login(), await S.login(), await S.login()]
  for (const p of ps) await S.req('GET', '/v1/missions', { token: p.token })
  // 0, 1은 하루 뒤에, 0은 7일 뒤에도 들어온다
  S.clock.t = base + DAY
  for (const p of ps.slice(0, 2)) await S.req('GET', '/v1/missions', { token: p.token })
  S.clock.t = base + 7 * DAY
  await S.req('GET', '/v1/missions', { token: ps[0].token })
  // 가이드: 2, 3은 3번째 미션(인덱스 2)에서 멈췄다. 3은 그 뒤로 안 들어왔다(last_seen = 가입 다음 날).
  await S.db.query("update player_state set tut_state = 'active', tut_step = 2 where player_id = any($1::uuid[])", [[ps[2].id, ps[3].id]])
  await S.db.query("update player_state set tut_state = 'done' where player_id = $1", [ps[0].id])
  await S.db.query("update players set last_seen = to_timestamp($2::float8) where id = $1", [ps[3].id, base])

  S.clock.t = base + 8 * DAY
  const admin = await makeAdmin()
  assert.equal((await S.req('GET', '/v1/admin/retention', { token: ps[1].token })).status, 403)
  const r = await S.req('GET', '/v1/admin/retention', { token: admin.token })
  assert.equal(r.status, 200)
  const c = r.json.cohorts.find((x: any) => x.day === d0)
  assert.deepEqual({ n: c.n, d1: c.d1, d7: c.d7 }, { n: 4, d1: 2, d7: 1 })
  assert.equal(c.date, RT.dayDate(d0))
  assert.ok(r.json.d1.n >= 4 && r.json.d7.n >= 4)
  assert.equal(r.json.today, d0 + 8)
  const s2 = r.json.guide.steps[2]
  assert.ok(s2.here >= 2)
  assert.ok(s2.away >= 1)
  assert.ok(r.json.guide.done >= 1)
  assert.equal(r.json.guide.steps[0].reached, r.json.guide.total)
  // 오늘 막 들어온 계정의 가입일은 D1이 아직 null
  const fresh = await S.login()
  await S.req('GET', '/v1/missions', { token: fresh.token })
  const r2 = await S.req('GET', '/v1/admin/retention', { token: admin.token })
  const today = r2.json.cohorts.find((x: any) => x.day === d0 + 8)
  assert.equal(today.d1, null)
  assert.equal(today.d7, null)
  assert.equal(r2.json.daily[0].day, d0 + 8)
  assert.equal(r2.json.daily[0].n, r2.json.dau)
  const st = r2.json.stages
  assert.ok(st.length >= 1 && st[0].from === 1 && st[0].to === RT.STAGE_BUCKET)
  assert.equal(st.reduce((a: number, x: any) => a + x.n, 0), r2.json.players)
  assert.ok(r2.json.dau >= 3) // 관리자·새 계정·…
  S.clock.t = T0
})

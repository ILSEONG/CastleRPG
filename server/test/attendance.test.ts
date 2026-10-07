// 28일 출석 이벤트: 표·진행 조회, 하루 한 번 받기(재전송·같은 날 두 번·건너뛰기 거부), 보상 반영(골드·모집권·열쇠·장비 상자·영웅), 28일차 뒤 끝.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as A from '../src/attendance.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup()
})
after(async () => {
  await S.close()
})

const DAY = 86400
const claim = (token: string, day: number) => S.req('POST', '/v1/attendance/claim', { token, body: { day } })

test('표·진행 조회: 28칸, 새 플레이어는 0일 + 받을 수 있음, /v1/player에도 요약', async () => {
  S.clock.t = T0
  const { token } = await S.login()
  const r = (await S.req('GET', '/v1/attendance', { token })).json
  assert.equal(r.rewards.length, 28)
  assert.equal(r.n, 0)
  assert.equal(r.can_claim, true)
  assert.ok(r.next_reset > T0 && r.next_reset <= T0 + DAY)
  assert.deepEqual(r.rewards[27], { hero: 'arteon' })
  const p = (await S.req('GET', '/v1/player', { token })).json.player
  assert.deepEqual(p.attendance, { n: 0, days: 28, can_claim: true })
})

test('하루 한 번: 1일차 골드, 같은 날 다시는 claimed, 재전송은 stale, 다음 날 2일차 모집권', async () => {
  S.clock.t = T0
  const { token } = await S.login()
  const before = (await S.req('GET', '/v1/player', { token })).json.player.gold_tenths
  const r = await claim(token, 1)
  assert.equal(r.status, 200)
  assert.equal(r.json.player.gold_tenths, before + A.REWARDS[0].gold! * 10)
  assert.deepEqual(r.json.player.attendance, { n: 1, days: 28, can_claim: false })
  assert.equal((await claim(token, 2)).json.error, 'claimed')
  assert.equal((await claim(token, 1)).json.error, 'stale')
  S.clock.t = T0 + DAY
  assert.equal((await claim(token, 3)).json.error, 'stale')
  const r2 = await claim(token, 2)
  assert.equal(r2.status, 200)
  assert.equal(r2.json.player.dia_tickets, A.REWARDS[1].tickets)
})

test('28일 모두: 열쇠·장비 상자·영웅이 들어가고, 28일차 뒤엔 finished', async () => {
  S.clock.t = T0
  const { token, id } = await S.login()
  let p: any
  for (let d = 1; d <= 28; d++) {
    S.clock.t = T0 + (d - 1) * DAY
    const r = await claim(token, d)
    assert.equal(r.status, 200, `day ${d}: ${JSON.stringify(r.json)}`)
    p = r.json.player
    if (d === 7) assert.equal(r.json.reward.items[0].grade, 'SR')
  }
  assert.equal(p.attendance.n, 28)
  assert.ok(p.heroes.luna && p.heroes.arteon)
  const grades = p.items.map((x: any) => `${x.grade}:${x.subs.length}`).sort()
  assert.deepEqual(grades, ['SR:1', 'SR:1', 'SSR:1']) // 장비 레벨 없음(2026-10-07), SR·SSR 특수 능력치 1줄
  const [log] = await S.db.query("select count(*)::int as n from economy_log where player_id = $1 and kind = 'attendance'", [id])
  assert.equal(log.n, 28)
  S.clock.t = T0 + 28 * DAY
  assert.equal((await claim(token, 28)).json.error, 'finished')
  assert.equal((await S.req('GET', '/v1/attendance', { token })).json.can_claim, false)
})

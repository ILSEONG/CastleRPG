// 로딩 화면 일괄 조회(GET /v1/boot): 창마다 따로 받던 GET 응답을 한 번에 그대로 담는다.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import { setup } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup()
})
after(async () => {
  await S.close()
})

test('boot: one call returns the same views as the per-window GETs', async () => {
  const { token } = await S.login()
  const r = await S.req('GET', '/v1/boot', { token })
  assert.equal(r.status, 200)
  const b = r.json
  for (const [k, path] of [['attendance', '/v1/attendance'], ['missions', '/v1/missions'], ['friends', '/v1/friends'], ['guild', '/v1/guild'],
    ['guild_war', '/v1/guild/war'], ['ranking_stage', '/v1/ranking/stage'], ['ranking_power', '/v1/ranking/power'], ['ranking_guild', '/v1/ranking/guild']]) {
    const one = await S.req('GET', path, { token })
    assert.deepEqual(b[k], one.status === 200 ? one.json : null, k) // 실패한 칸(길드 없는 공성전 등)은 null
  }
  assert.equal(typeof b.server_now, 'number')
})

test('boot: needs a token', async () => {
  assert.equal((await S.req('GET', '/v1/boot')).status, 401)
})

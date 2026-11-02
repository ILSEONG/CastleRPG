// 중복 요청 방지(idempotency.ts, 2026-11-02): 같은 계정·같은 X-Request-Id의 POST는 한 번만 처리하고 다시 오면 처음 답을 그대로 돌려준다.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { Replays } from '../src/idempotency.ts'
import { setup, T0 } from './helpers.ts'

const player = async (S: Awaited<ReturnType<typeof setup>>, token: string) => (await S.req('GET', '/v1/player', { token })).json.player

test('모집 같은 요청 번호 두 번(차례로): 다이아는 한 번만 빠지고 두 번째는 처음 답을 그대로', async () => {
  const S = await setup()
  try {
    S.clock.t = T0
    const { token } = await S.login()
    const dia = (await S.req('POST', '/v1/test/grant_diamonds', { token, body: { amount: 10_000 } })).json.player.diamonds
    const send = () => S.req('POST', '/v1/gacha', { token, body: { count: 10, currency: 'diamond' }, headers: { 'x-request-id': 'tap-0000000001' } })
    const a = await send()
    const b = await send()
    assert.equal(a.status, 200, a.text)
    assert.equal(b.status, 200, b.text)
    assert.equal(b.headers.get('x-replayed'), '1')
    assert.deepEqual(b.json.results, a.json.results)
    assert.equal((await player(S, token)).diamonds, dia - 2700)
    // 다른 번호는 새 요청(두 번 누른 것이 아니라 두 번 산 것)
    const c = await S.req('POST', '/v1/gacha', { token, body: { count: 10, currency: 'diamond' }, headers: { 'x-request-id': 'tap-0000000002' } })
    assert.equal(c.status, 200, c.text)
    assert.equal((await player(S, token)).diamonds, dia - 5400)
  } finally {
    await S.close()
  }
})

test('상점 구매 같은 요청 번호가 동시에 두 번: 한 번만 사고 두 답 모두 200', async () => {
  const S = await setup()
  try {
    S.clock.t = T0
    const { token } = await S.login()
    const dia = (await S.req('POST', '/v1/test/grant_diamonds', { token, body: { amount: 1000 } })).json.player.diamonds
    const send = () => S.req('POST', '/v1/shop/buy', { token, body: { id: 'd_ticket', n: 0 }, headers: { 'x-request-id': 'shop-000000001' } })
    const [a, b] = await Promise.all([send(), send()])
    assert.deepEqual([a.status, b.status], [200, 200], a.text + b.text)
    const p = await player(S, token)
    assert.equal(p.diamonds, dia - 240)
    assert.deepEqual(p.shop.d, { d_ticket: 1 })
  } finally {
    await S.close()
  }
})

test('실패한 요청은 기억하지 않는다: 같은 번호로 다시 보내면 다시 처리한다', async () => {
  const S = await setup()
  try {
    S.clock.t = T0
    const { token } = await S.login()
    const h = { 'x-request-id': 'retry-00000001' }
    const p0 = await player(S, token)
    const lack = await S.req('POST', '/v1/gacha', { token, body: { count: 10, currency: 'diamond' }, headers: h })
    assert.equal(lack.status, 409)
    await S.req('POST', '/v1/test/grant_diamonds', { token, body: { amount: 2700 - p0.diamonds } })
    const ok = await S.req('POST', '/v1/gacha', { token, body: { count: 10, currency: 'diamond' }, headers: h })
    assert.equal(ok.status, 200, ok.text)
    assert.equal((await player(S, token)).diamonds, 0)
  } finally {
    await S.close()
  }
})

test('요청 번호는 계정마다 따로', async () => {
  const S = await setup()
  try {
    S.clock.t = T0
    const a = await S.login()
    const b = await S.login()
    const h = { 'x-request-id': 'same-000000001' }
    for (const u of [a, b]) {
      await S.req('POST', '/v1/test/grant_diamonds', { token: u.token, body: { amount: 2700 } })
      const r = await S.req('POST', '/v1/gacha', { token: u.token, body: { count: 10, currency: 'diamond' }, headers: h })
      assert.equal(r.status, 200, r.text)
      assert.equal(r.headers.get('x-replayed'), null)
    }
  } finally {
    await S.close()
  }
})

test('Replays: TTL이 지나면 잊고, 바이트 한도를 넘으면 오래된 것부터 버린다', async () => {
  const r = new Replays(120, 10)
  r.begin('a', 0)({ status: 200, body: '123456', type: 'application/json' })
  r.begin('b', 1)({ status: 200, body: '123456', type: 'application/json' })
  assert.equal(r.get('a', 2), null) // 12바이트 > 10: a를 버렸다
  assert.ok(r.get('b', 2))
  assert.equal(r.get('b', 121), null) // TTL
  assert.equal(r.size(), 0)
})

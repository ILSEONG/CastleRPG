// 동시성(스펙 §3): 같은 플레이어 요청이 겹쳐도 두 번 수집·판매되지 않는다. 계속 충돌하면 409.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import type { Query } from '../src/db.ts'
import { setup, T0 } from './helpers.ts'

const isPlayerRead = (text: string) => text.includes('from player_state s where')
const isCommit = (text: string) => text.startsWith('with s as (update player_state set version = version + 1')

// 처음 두 번의 플레이어 읽기를 서로 기다리게 한다 — 두 요청이 반드시 같은 version을 읽은 뒤 쓰기를 겨룬다.
function barrier() {
  let armed = false
  let arrived = 0
  let release = () => {}
  const both = new Promise<void>((r) => (release = r))
  const wrap = (q: Query): Query => async (text, params) => {
    if (armed && isPlayerRead(text) && arrived < 2) {
      arrived++
      if (arrived === 2) release()
      await both
    }
    return q(text, params)
  }
  return { wrap, arm: () => (armed = true), arrived: () => arrived }
}

test('동시 수집 2건은 한 번만 수집된다', async () => {
  const b = barrier()
  const S = await setup({ wrapQuery: b.wrap })
  try {
    S.clock.t = T0
    const { token, id } = await S.login()
    S.clock.t = T0 + 600 // 10분 → 100
    b.arm()
    const [r1, r2] = await Promise.all([
      S.req('POST', '/v1/collect', { token, body: { building: 'lumber' } }),
      S.req('POST', '/v1/collect', { token, body: { building: 'lumber' } }),
    ])
    assert.equal(b.arrived(), 2, 'both requests read before either wrote')
    assert.deepEqual([r1.status, r2.status], [200, 200])
    assert.deepEqual([r1.json.amount, r2.json.amount].sort((x, y) => x - y), [0, 100])
    const p = await S.req('GET', '/v1/player', { token })
    assert.equal(p.json.player.res.wood, 100)
    assert.equal(p.json.player.buildings.lumber.last_collect, T0 + 600)
    const n = await S.db.query("select count(*)::int as n from economy_log where player_id = $1 and kind = 'collect'", [id])
    assert.equal(n[0].n, 1)
  } finally {
    await S.close()
  }
})

test('동시 판매 2건은 한 번만 판다(골드가 두 번 들어오지 않는다)', async () => {
  const b = barrier()
  const S = await setup({ wrapQuery: b.wrap })
  try {
    S.clock.t = T0
    const { token } = await S.login()
    S.clock.t = T0 + 600
    await S.req('POST', '/v1/collect', { token, body: { building: 'lumber' } })
    b.arm()
    const [r1, r2] = await Promise.all([
      S.req('POST', '/v1/sell', { token, body: { res: 'wood' } }),
      S.req('POST', '/v1/sell', { token, body: { res: 'all' } }),
    ])
    assert.equal(b.arrived(), 2)
    const gains = [r1.json.gold_gained, r2.json.gold_gained].sort((x, y) => x - y)
    assert.equal(gains[0], 0)
    const p = await S.req('GET', '/v1/player', { token })
    assert.equal(p.json.player.gold, gains[1])
    assert.equal(p.json.player.res.wood, 0)
  } finally {
    await S.close()
  }
})

test('쓰기 직전마다 다른 쓰기가 끼어들면 재시도 3회 후 409, 아무것도 안 바뀜', async () => {
  let interfere = false
  let commits = 0
  const S = await setup({
    wrapQuery: (q) => async (text, params) => {
      if (interfere && isCommit(text)) {
        commits++
        await q('update player_state set version = version + 1 where player_id = $1', [params?.[0]])
      }
      return q(text, params)
    },
  })
  try {
    S.clock.t = T0
    const { token } = await S.login()
    S.clock.t = T0 + 600
    interfere = true
    const r = await S.req('POST', '/v1/collect', { token, body: { building: 'lumber' } })
    assert.equal(r.status, 409)
    assert.equal(r.json.error, 'conflict')
    assert.equal(commits, 4) // 첫 시도 + 재시도 3회
    interfere = false
    const p = await S.req('GET', '/v1/player', { token })
    assert.equal(p.json.player.res.wood, 0)
    assert.equal(p.json.player.buildings.lumber.last_collect, T0)
  } finally {
    await S.close()
  }
})

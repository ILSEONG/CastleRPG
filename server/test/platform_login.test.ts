// 출시 플랫폼별 로그인(2026-10-07): 앱인토스 게임 로그인(/v1/auth/toss — getUserKeyForGame hash)과 계정 삭제(/v1/account/delete — Google Play 정책).
import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { test } from 'node:test'
import { setup } from './helpers.ts'

const HASH = 'aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3zA5bC7dE9='

test('토스 로그인: 처음이면 계정을 만들고, 같은 hash면 같은 계정, 다른 hash면 다른 계정, DB에는 hash 원문을 두지 않는다', async () => {
  const S = await setup()
  try {
    const a = await S.req('POST', '/v1/auth/toss', { body: { hash: HASH } })
    assert.equal(a.status, 200, JSON.stringify(a.json))
    assert.equal(a.json.provider, 'toss')
    assert.equal(a.json.is_new, true)
    const p = await S.req('GET', '/v1/player', { token: a.json.token })
    assert.equal(p.status, 200)
    const again = await S.req('POST', '/v1/auth/toss', { body: { hash: HASH } })
    assert.equal(again.json.player_id, a.json.player_id)
    assert.equal(again.json.is_new, false)
    const other = await S.req('POST', '/v1/auth/toss', { body: { hash: 'zZ9yY8xX7wW6' } })
    assert.notEqual(other.json.player_id, a.json.player_id)
    const rows = await S.db.query("select provider_uid from player_identities where provider = 'toss'")
    assert.equal(rows.length, 2)
    assert.ok(rows.every((r: any) => /^[0-9a-f]{64}$/.test(r.provider_uid) && r.provider_uid !== HASH))
    assert.ok(rows.some((r: any) => r.provider_uid === createHash('sha256').update(`toss:${HASH}`).digest('hex')))
  } finally {
    await S.close()
  }
})

test('토스 로그인 검증: hash 없음·짧음·공백·너무 김은 400', async () => {
  const S = await setup()
  try {
    for (const hash of [undefined, 'short', 'has space here', 'x'.repeat(513), 12345678]) {
      const r = await S.req('POST', '/v1/auth/toss', { body: { hash } })
      assert.equal(r.status, 400)
      assert.equal(r.json.error, 'bad_hash')
    }
  } finally {
    await S.close()
  }
})

test('계정 삭제: 확인 값이 있어야 하고, 지우면 플레이어가 사라지며 같은 토스 hash로 다시 들어오면 새 계정', async () => {
  const S = await setup()
  try {
    const a = await S.req('POST', '/v1/auth/toss', { body: { hash: HASH } })
    assert.equal((await S.req('POST', '/v1/account/delete', { token: a.json.token, body: {} })).json.error, 'confirm_required')
    assert.equal((await S.req('POST', '/v1/account/delete', { body: { confirm: 'delete' } })).status, 401)
    const d = await S.req('POST', '/v1/account/delete', { token: a.json.token, body: { confirm: 'delete' } })
    assert.equal(d.status, 200, JSON.stringify(d.json))
    assert.equal((await S.db.query('select 1 from players where id = $1', [a.json.player_id])).length, 0)
    assert.equal((await S.db.query('select 1 from player_identities where player_id = $1', [a.json.player_id])).length, 0)
    const back = await S.req('POST', '/v1/auth/toss', { body: { hash: HASH } })
    assert.equal(back.json.is_new, true)
    assert.notEqual(back.json.player_id, a.json.player_id)
  } finally {
    await S.close()
  }
})

test('계정 삭제: 길드장이면 가장 오래된 길드원에게 넘기고, 혼자인 길드는 지운다', async () => {
  const S = await setup()
  try {
    const owner = await S.login()
    const member = await S.login()
    const solo = await S.login()
    await S.db.query(`insert into guilds (id, name, owner, seed, virtual_n, created_at) values
      ('00000000-0000-4000-8000-000000000001', '둘길드', $1, 1, 0, now()), ('00000000-0000-4000-8000-000000000002', '혼자길드', $2, 2, 0, now())`, [owner.id, solo.id])
    await S.db.query(`insert into player_guild (player_id, guild_id, joined_at) values ($1, '00000000-0000-4000-8000-000000000001', now() - interval '2 days'),
      ($2, '00000000-0000-4000-8000-000000000001', now() - interval '1 day'), ($3, '00000000-0000-4000-8000-000000000002', now())`, [owner.id, member.id, solo.id])
    for (const t of [owner.token, solo.token]) assert.equal((await S.req('POST', '/v1/account/delete', { token: t, body: { confirm: 'delete' } })).status, 200)
    const gs = await S.db.query('select id, owner from guilds order by id')
    assert.deepEqual(gs.map((g: any) => [g.id, g.owner]), [['00000000-0000-4000-8000-000000000001', member.id]])
  } finally {
    await S.close()
  }
})

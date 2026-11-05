// 닉네임 변경(2026-11-05): 처음 무료 → 그 뒤 다이아, 검사(길이·글자·금칙어·사칭·중복), 모든 화면이 새 이름(친구·길드·랭킹 = friendName/playerName).
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as R from '../src/rules.ts'
import * as G from '../src/guild.ts'
import * as N from '../src/names.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup()
})
after(async () => {
  await S.close()
})

const rename = (token: string, name: string) => S.req('POST', '/v1/nickname', { token, body: { name } })
const player = async (token: string) => (await S.req('GET', '/v1/player', { token })).json.player

async function fresh(diamonds = 0) {
  S.clock.t = T0
  const { token, id } = await S.login()
  await player(token)
  if (diamonds) await S.db.query('update player_state set diamonds = $2 where player_id = $1', [id, diamonds])
  return { token, id }
}

test('처음은 무료, 두 번째부터 다이아', async () => {
  const a = await fresh()
  const p0 = await player(a.token)
  assert.equal(p0.nickname.name, R.friendName(a.id))
  assert.equal(p0.nickname.changes, 0)
  assert.equal(p0.nickname.price, 0)
  const r = await rename(a.token, '성주님1')
  assert.equal(r.status, 200, JSON.stringify(r.json))
  assert.equal(r.json.name, '성주님1')
  assert.equal(r.json.player.nickname.name, '성주님1')
  assert.equal(r.json.player.nickname.changes, 1)
  assert.equal(r.json.player.nickname.price, N.DEFAULT_COST)
  assert.equal(r.json.player.diamonds, 0)
  assert.equal(R.friendName(a.id), '성주님1')
  assert.equal(G.playerName(a.id), '성주님1')
  assert.equal((await S.req('GET', '/v1/friends', { token: a.token })).json.name, '성주님1')
  const poor = await rename(a.token, '성주님2')
  assert.equal(poor.status, 409)
  assert.equal(poor.json.error, 'not_enough')
  await S.db.query('update player_state set diamonds = $2 where player_id = $1', [a.id, N.DEFAULT_COST + 5])
  const paid = await rename(a.token, '성주님2')
  assert.equal(paid.status, 200, JSON.stringify(paid.json))
  assert.equal(paid.json.player.diamonds, 5)
  assert.equal(paid.json.player.nickname.changes, 2)
  const [log] = await S.db.query("select detail from economy_log where player_id = $1 and kind = 'nickname' order by at desc, id desc limit 1", [a.id])
  assert.equal(Number((log.detail as any).diamonds), N.DEFAULT_COST)
})

test('검사: 길이·글자·금칙어·사칭·같은 이름·중복', async () => {
  const a = await fresh()
  const b = await fresh()
  for (const [name, why] of [['가', 'length'], ['가나다라마바사아자', 'length'], ['성주 님', 'chars'], ['성주!', 'chars'], ['시발', 'bad'], ['운영자123', 'reserved'], ['GMking', 'reserved']]) {
    const r = await rename(a.token, name)
    assert.equal(r.status, 400, name)
    assert.equal(r.json.error, 'bad_name')
    assert.equal(r.json.message, why, name)
  }
  assert.equal((await rename(a.token, R.friendName(a.id))).json.error, 'same_name')
  assert.equal((await rename(a.token, 'Knight7')).status, 200)
  const dup = await rename(b.token, 'knight7')
  assert.equal(dup.status, 409)
  assert.equal(dup.json.error, 'name_taken')
  assert.equal((await player(b.token)).nickname.changes, 0) // 거절되면 무료 기회가 그대로
})

test('서버를 다시 띄워도 고른 이름을 읽는다', async () => {
  const a = await fresh()
  assert.equal((await rename(a.token, '다시읽기')).status, 200)
  N.forget(a.id)
  assert.notEqual(R.friendName(a.id), '다시읽기')
  await N.load(S.db.query.bind(S.db) as any)
  assert.equal(R.friendName(a.id), '다시읽기')
})

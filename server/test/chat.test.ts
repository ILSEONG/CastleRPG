// 채팅(server/src/chat.ts): 전체 채널 보내기·받기, 이어 받기, 길드 채널, 도배 제한, 글자 수·욕설 가리기, 입력 검사, 보관 개수.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as G from '../src/guild.ts'
import { GAP_SEC, KEEP, MAX_LEN, clean, mask } from '../src/chat.ts'
import { setup } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup()
})
after(async () => {
  await S.close()
})

const say = (token: string, channel: string, text: unknown) => S.req('POST', '/v1/chat', { token, body: { channel, text } })
const read = async (token: string, q = '') => (await S.req('GET', '/v1/chat' + q, { token })).json
const wait = () => (S.clock.t += GAP_SEC + 1)

test('chat: all channel sends and both players read it with names, me marked', async () => {
  const a = await S.login()
  const b = await S.login()
  const r = await say(a.token, 'all', '  안녕하세요\n여러분  ')
  assert.equal(r.status, 200)
  assert.equal(r.json.msg.text, '안녕하세요 여러분')
  assert.equal(r.json.msg.name, G.playerName(a.id))
  assert.equal(r.json.msg.me, true)
  const seen = await read(b.token)
  const last = seen.all.at(-1)
  assert.deepEqual([last.name, last.text, last.me], [G.playerName(a.id), '안녕하세요 여러분', false])
  assert.equal(seen.guild, null)
  // 이어 받기: 받은 마지막 id 뒤만
  wait()
  await say(b.token, 'all', '반가워요')
  const more = await read(a.token, `?all=${last.id}`)
  assert.deepEqual(more.all.map((m: any) => m.text), ['반가워요'])
})

test('chat: spam limit refuses a second message within the gap', async () => {
  const a = await S.login()
  wait()
  assert.equal((await say(a.token, 'all', '하나')).status, 200)
  const r = await say(a.token, 'all', '둘')
  assert.equal(r.status, 400)
  assert.equal(r.json.error, 'too_fast')
  wait()
  assert.equal((await say(a.token, 'all', '셋')).status, 200)
})

test('chat: length cap, bad words masked, empty and bad input refused', async () => {
  const a = await S.login()
  wait()
  const long = 'ㄱ'.repeat(MAX_LEN + 30)
  assert.equal([...(await say(a.token, 'all', long)).json.msg.text].length, MAX_LEN)
  assert.equal(mask('야 시 발 진짜'), '야 * * 진짜')
  assert.equal(mask('fUcK you'), '**** you')
  assert.equal(mask('좋은 아침'), '좋은 아침')
  assert.equal(clean('a\u0000b\tc'), 'a b c')
  wait()
  assert.equal((await say(a.token, 'all', '   ')).json.error, 'empty')
  assert.equal((await say(a.token, 'all', 5)).status, 400)
  assert.equal((await say(a.token, 'party', 'hi')).status, 400)
  assert.equal((await say(a.token, 'guild', 'hi')).json.error, 'no_guild')
})

test('chat: guild channel is only for members of that guild', async () => {
  const a = await S.login()
  const b = await S.login()
  const c = await S.login()
  const [g] = await S.db.query("insert into guilds (name, emblem, seed, created_at, virtual_n) values ('채팅길드', 1, 7, now(), 0) returning id::text as id")
  const [h] = await S.db.query("insert into guilds (name, emblem, seed, created_at, virtual_n) values ('다른길드', 2, 8, now(), 0) returning id::text as id")
  await S.db.query('insert into player_guild (player_id, guild_id) values ($1, $3), ($2, $3)', [a.id, b.id, g.id])
  await S.db.query('insert into player_guild (player_id, guild_id) values ($1, $2)', [c.id, h.id])
  wait()
  assert.equal((await say(a.token, 'guild', '길드 여러분')).status, 200)
  const rb = await read(b.token)
  assert.equal(rb.guild_name, '채팅길드')
  assert.deepEqual(rb.guild.map((m: any) => m.text), ['길드 여러분'])
  const rc = await read(c.token)
  assert.deepEqual(rc.guild, [])
  assert.ok(!rb.all.some((m: any) => m.text === '길드 여러분'))
})

test('chat: each channel keeps only the latest messages', async () => {
  const a = await S.login()
  for (let i = 0; i < KEEP + 5; i++) {
    wait()
    await say(a.token, 'all', `m${i}`)
  }
  const [{ n }] = await S.db.query("select count(*)::int as n from chat_messages where channel = 'all'")
  assert.equal(n, KEEP)
  const last = await read(a.token)
  assert.equal(last.all.at(-1).text, `m${KEEP + 4}`)
})

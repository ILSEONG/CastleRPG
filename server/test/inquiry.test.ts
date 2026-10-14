// 고객 문의(inquiry.ts): 보내기(같은 key 한 번만, 상한), 내 문의 목록, 관리자 목록·답변(우편으로 감, 같은 답변 연타 한 번)·종료.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as IQ from '../src/inquiry.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
let admin: { token: string; id: string }
before(async () => {
  S = await setup()
  S.clock.t = T0
  admin = await S.login()
  await S.db.query("insert into player_identities (provider, provider_uid, player_id, email) values ('google', 'iq-admin', $1, 'iq-admin@example.com')", [admin.id])
  await S.db.query("insert into admin_emails (email) values ('iq-admin@example.com') on conflict do nothing")
})
after(async () => {
  await S.close()
})

const send = (token: string, key: string, extra: Record<string, unknown> = {}) =>
  S.req('POST', '/v1/inquiry', { token, body: { key, category: 'bug', body: '전투가 멈춰요', info: { name: '용사', version: '0.2.1', junk: 'x' }, ...extra } })

test('문의 보내기: 같은 key는 한 번만, 내 목록에 보인다, 틀린 값은 400', async () => {
  const { token } = await S.login()
  const a = await send(token, 'key-000001')
  assert.equal(a.status, 200)
  assert.equal(a.json.inquiry.status, 'open')
  const again = await send(token, 'key-000001', { body: '다른 글' })
  assert.equal(again.json.inquiry.id, a.json.inquiry.id)
  assert.equal(again.json.inquiry.body, '전투가 멈춰요')
  const mine = await S.req('GET', '/v1/inquiry', { token })
  assert.equal(mine.json.inquiries.length, 1)
  assert.equal((await send(token, 'key-000002', { category: 'nope' })).status, 400)
  assert.equal((await send(token, 'key-000003', { body: '  ' })).status, 400)
  assert.equal((await send(token, 'key-000004', { body: 'x'.repeat(IQ.MAX_BODY + 1) })).status, 400)
  assert.equal((await send(token, 'k')).status, 400)
  assert.equal((await S.req('GET', '/v1/inquiry')).status, 401)
})

test('상한: 답변 대기 MAX_OPEN개까지', async () => {
  const { token } = await S.login()
  for (let i = 0; i < IQ.MAX_OPEN; i++) assert.equal((await send(token, `open-${i}-key`)).status, 200)
  const r = await send(token, 'open-over-key')
  assert.equal(r.status, 429)
  assert.equal(r.json.error, 'too_many_inquiries')
})

test('관리자: 목록·답변(우편 + 보상, 같은 답변 연타 한 번)·종료·다시 열기, 일반 플레이어는 403', async () => {
  const p = await S.login()
  S.clock.t = T0 + 100
  const q = (await send(p.token, 'answer-key-1')).json.inquiry
  assert.equal((await S.req('GET', '/v1/admin/inquiries', { token: p.token })).status, 403)
  assert.equal((await S.req('POST', '/v1/admin/inquiry/answer', { token: p.token, body: { id: q.id, answer: 'x' } })).status, 403)
  const list = await S.req('GET', '/v1/admin/inquiries', { token: admin.token })
  const row = list.json.inquiries.find((r: any) => r.id === q.id)
  assert.ok(row && row.code === p.id.replace(/-/g, '').slice(0, 8).toUpperCase())
  assert.deepEqual(row.info, { name: '용사', version: '0.2.1' })
  assert.ok(list.json.open >= 1)
  S.clock.t = T0 + 200
  const ans = { id: q.id, answer: '확인했습니다. 보상 드려요', reward: { diamonds: 100 } }
  const a1 = await S.req('POST', '/v1/admin/inquiry/answer', { token: admin.token, body: ans })
  assert.equal(a1.status, 200)
  assert.equal(a1.json.sent, true)
  const a2 = await S.req('POST', '/v1/admin/inquiry/answer', { token: admin.token, body: ans })
  assert.equal(a2.json.sent, false)
  const mails = (await S.req('GET', '/v1/mail', { token: p.token })).json.mails
  assert.equal(mails.length, 1)
  assert.equal(mails[0].title, '[문의 답변] 버그·오류')
  assert.ok(mails[0].body.startsWith('확인했습니다') && mails[0].body.includes('전투가 멈춰요'))
  assert.deepEqual(mails[0].reward, { diamonds: 100 })
  const mine = (await S.req('GET', '/v1/inquiry', { token: p.token })).json.inquiries[0]
  assert.equal(mine.status, 'answered')
  assert.equal(mine.answer, '확인했습니다. 보상 드려요')
  assert.ok(!(await S.req('GET', '/v1/admin/inquiries', { token: admin.token })).json.inquiries.some((r: any) => r.id === q.id))
  const c = await S.req('POST', '/v1/admin/inquiry/close', { token: admin.token, body: { id: q.id, closed: true } })
  assert.equal(c.json.status, 'closed')
  const o = await S.req('POST', '/v1/admin/inquiry/close', { token: admin.token, body: { id: q.id, closed: false } })
  assert.equal(o.json.status, 'answered')
  assert.equal((await S.req('POST', '/v1/admin/inquiry/answer', { token: admin.token, body: { id: 999999, answer: 'x' } })).status, 404)
  assert.equal((await S.req('POST', '/v1/admin/inquiry/answer', { token: admin.token, body: { id: q.id, answer: 'x', reward: { nope: 1 } } })).status, 400)
  assert.ok((await S.req('GET', '/v1/admin/inquiries?filter=all', { token: admin.token })).json.inquiries.some((r: any) => r.id === q.id))
})

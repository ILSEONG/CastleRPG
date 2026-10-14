// 앱 없이 계정 삭제 요청(/legal/account-deletion 양식 → 문의 표 category 'delete') + 관리자 [계정 삭제](/v1/admin/inquiry/delete_account).
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
let admin: { token: string; id: string }
let app: ReturnType<Setup['makeApp']>
before(async () => {
  S = await setup({ legal: { operator: '일성게임즈', email: '', bizNo: '227-15-93850' } })
  S.clock.t = T0
  app = S.makeApp()
  admin = await S.login()
  await S.db.query("insert into player_identities (provider, provider_uid, player_id, email) values ('google', 'wd-admin', $1, 'wd-admin@example.com')", [admin.id])
  await S.db.query("insert into admin_emails (email) values ('wd-admin@example.com') on conflict do nothing")
})
after(() => S.close())

const send = async (form: Record<string, string>) => {
  const res = await app.request('/legal/account-deletion', { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(form).toString() })
  return { status: res.status, text: await res.text() }
}
const code = async (id: string) => String((await S.db.query('select friend_code from players where id = $1', [id]))[0].friend_code)
const requests = async () => (await S.req('GET', '/v1/admin/inquiries?filter=all', { token: admin.token })).json.inquiries.filter((q: any) => q.category === 'delete')

test('삭제 안내 페이지에 요청 양식, 사업자 정보', async () => {
  const r = await S.req('GET', '/legal/account-deletion')
  assert.ok(r.text.includes('action="/legal/account-deletion"') && r.text.includes('name="code"') && r.text.includes('227-15-93850'))
  assert.ok(!r.text.includes('연락처 등록 예정'))
})

test('양식: 친구 코드로 찾아 문의 표에 쌓이고, 같은 계정은 처리 전까지 한 번만, 자동 삭제 없음', async () => {
  const p = await S.login()
  const c = await code(p.id)
  const r = await send({ code: c.toLowerCase(), login: 'kakao', reason: '그만할래요' })
  assert.equal(r.status, 200)
  assert.ok(r.text.includes('삭제 요청을 받았어요'))
  assert.equal((await send({ code: c, login: 'kakao' })).status, 200)
  const rows = (await requests()).filter((q: any) => q.code === c)
  assert.equal(rows.length, 1)
  assert.equal(rows[0].status, 'open')
  assert.ok(rows[0].body.includes(c) && rows[0].body.includes('그만할래요'))
  assert.equal(rows[0].info.login, '카카오')
  assert.equal((await S.db.query('select count(*)::int as n from players where id = $1', [p.id]))[0].n, 1) // 아직 그대로
  // 관리자가 지운다 → 계정 없음, 요청 행은 처리 기록으로 남는다(종료)
  const d = await S.req('POST', '/v1/admin/inquiry/delete_account', { token: admin.token, body: { id: rows[0].id } })
  assert.equal(d.status, 200)
  assert.equal((await S.db.query('select count(*)::int as n from players where id = $1', [p.id]))[0].n, 0)
  const after = (await requests()).find((q: any) => q.id === rows[0].id)
  assert.equal(after.status, 'closed')
  assert.ok(after.answer.includes('계정 삭제 완료') && after.code === '')
  assert.equal((await S.req('POST', '/v1/admin/inquiry/delete_account', { token: admin.token, body: { id: rows[0].id } })).json.error, 'no_account')
})

test('양식: Google 이메일로 찾기, 못 찾아도 같은 화면(남김), 입력 확인·자동 입력 무시', async () => {
  const p = await S.login()
  await S.db.query("insert into player_identities (provider, provider_uid, player_id, email) values ('google', 'wd-user', $1, 'someone@example.com')", [p.id])
  assert.ok((await send({ email: 'Someone@Example.com', login: 'google' })).text.includes('삭제 요청을 받았어요'))
  const mine = (await requests()).find((q: any) => q.player === p.id)
  assert.equal(mine.info.contact, 'someone@example.com')
  const miss = await send({ code: 'ABCDEF12' })
  assert.ok(miss.text.includes('삭제 요청을 받았어요'))
  assert.ok((await requests()).some((q: any) => q.player === '' && q.body.includes('ABCDEF12') && q.body.includes('일치하는 계정 없음')))
  assert.equal((await send({})).status, 400)
  assert.equal((await send({ code: 'xyz' })).status, 400)
  const before = (await requests()).length
  await send({ code: 'ABCDEF13', website: 'http://spam' })
  assert.equal((await requests()).length, before)
  // 답변해도 계정 없는 요청에는 우편이 가지 않는다(모두에게 가는 우편이 되면 안 된다)
  const orphan = (await requests()).find((q: any) => q.player === '')
  const mails0 = (await S.db.query('select count(*)::int as n from mails'))[0].n
  const a = await S.req('POST', '/v1/admin/inquiry/answer', { token: admin.token, body: { id: orphan.id, answer: '계정을 찾지 못했어요' } })
  assert.equal(a.status, 200)
  assert.equal(a.json.mail_id, null)
  assert.equal((await S.db.query('select count(*)::int as n from mails'))[0].n, mails0)
})

test('앱 [문의하기]는 delete 분류를 고를 수 없고, 관리자 삭제는 delete 요청·남의 계정만', async () => {
  const p = await S.login()
  const r = await S.req('POST', '/v1/inquiry', { token: p.token, body: { key: 'wd-key-1', category: 'delete', body: '지워 주세요' } })
  assert.equal(r.status, 400)
  const ok = await S.req('POST', '/v1/inquiry', { token: p.token, body: { key: 'wd-key-2', category: 'other', body: '안녕' } })
  assert.equal((await S.req('POST', '/v1/admin/inquiry/delete_account', { token: admin.token, body: { id: ok.json.inquiry.id } })).json.error, 'not_deletion_request')
  await send({ code: await code(admin.id) })
  const own = (await requests()).find((q: any) => q.player === admin.id)
  assert.equal((await S.req('POST', '/v1/admin/inquiry/delete_account', { token: admin.token, body: { id: own.id } })).json.error, 'own_account')
  assert.equal((await S.req('POST', '/v1/admin/inquiry/delete_account', { token: p.token, body: { id: own.id } })).status, 403)
})

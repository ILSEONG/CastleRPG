// 환불 회수·채팅 금지(2026-11-06, 마이그레이션 069).
import assert from 'node:assert/strict'
import { test } from 'node:test'
import * as Pay from '../src/payments.ts'
import { setup, takeMail } from './helpers.ts'

async function asAdmin(S: any, tag: string) {
  const a = await S.login()
  await S.db.query("insert into player_identities (provider, provider_uid, player_id, email) values ('google', $1, $2, $3)", [`rm-${tag}`, a.id, `rm-${tag}@example.com`])
  await S.db.query('insert into admin_emails (email) values ($1) on conflict do nothing', [`rm-${tag}@example.com`])
  return a
}

test('환불 회수: 받은 다이아를 빼앗고 모자라면 빚(앞으로 얻는 다이아에서 먼저 갚는다), 안 받은 우편은 지운다, 같은 환불은 한 번만', async () => {
  const voided: { orderId: string; token: string; at: number }[] = []
  const g: Pay.Verifier = {
    async verify({ product, token }) { return { ok: true, orderId: `GPA.${token}`, product } },
    async voided() { return voided },
  }
  const S = await setup({ payments: { google: g } })
  try {
    const admin = await asAdmin(S, 'refund')
    const p = await S.login()
    const buy = (t: string, product = 'dia_1') => S.req('POST', '/v1/iap/purchase', { token: p.token, body: { product, provider: 'google', token: t } })
    // 1) 받은 뒤 다 써서 다이아가 없다 → 빚
    const b1 = await buy('a1')
    assert.equal(b1.status, 200, JSON.stringify(b1.json))
    await takeMail(S, p.token, b1)
    const d0 = (await S.req('GET', '/v1/player', { token: p.token })).json.player.diamonds
    await S.db.query('update player_state set diamonds = 1000 where player_id = $1', [p.id])
    voided.push({ orderId: 'GPA.a1', token: 'a1', at: 0 })
    const sync = await S.req('POST', '/v1/admin/refunds/sync', { token: admin.token, body: {} })
    assert.deepEqual([sync.status, sync.json.refunded], [200, 1], JSON.stringify(sync.json))
    let pl = (await S.req('GET', '/v1/player', { token: p.token })).json.player
    assert.equal(pl.diamonds, 0)
    assert.equal(pl.dia_debt, 3300 - 1000)
    assert.ok(d0 >= 3300)
    assert.equal((await S.req('POST', '/v1/admin/refunds/sync', { token: admin.token, body: {} })).json.refunded, 0, 'once')
    // 회수 안내 우편(보상 없음)
    const mails = (await S.req('GET', '/v1/mail', { token: p.token })).json.mails
    assert.ok(mails.some((m: any) => m.title.includes('결제 취소')))
    // 새로 얻는 다이아는 빚부터 갚는다
    const b2 = await buy('a2', 'dia_2')
    const got = await takeMail(S, p.token, b2)
    pl = got.json.player ?? (await S.req('GET', '/v1/player', { token: p.token })).json.player
    assert.equal(pl.diamonds, 16000 - 2300)
    assert.equal(pl.dia_debt ?? 0, 0)
    // 2) 우편을 받기 전에 환불 → 우편만 지운다(관리자가 주문 번호로 직접)
    const b3 = await buy('a3', 'dia_3')
    assert.equal(b3.status, 200)
    const before = (await S.req('GET', '/v1/player', { token: p.token })).json.player.diamonds
    const r = await S.req('POST', '/v1/admin/refund', { token: admin.token, body: { order_id: 'GPA.a3' } })
    assert.equal(r.status, 200, JSON.stringify(r.json))
    assert.ok(r.json.clawback.mail_removed > 0)
    assert.equal((await S.req('GET', '/v1/player', { token: p.token })).json.player.diamonds, before)
    assert.ok(!(await S.req('GET', '/v1/mail', { token: p.token })).json.mails.some((m: any) => m.title.includes('다이아') && m.reward?.diamonds === 33000))
    assert.equal((await S.req('POST', '/v1/admin/refund', { token: admin.token, body: { order_id: 'GPA.a3' } })).json.error, 'already_refunded')
    assert.equal((await S.req('POST', '/v1/admin/refund', { token: admin.token, body: { order_id: 'nope' } })).json.error, 'unknown_order')
    assert.equal((await S.req('POST', '/v1/admin/refund', { token: p.token, body: { order_id: 'GPA.a2' } })).status, 403)
    // 3) 패스 환불 → 패스가 사라진다
    await buy('a4', 'pass_growth')
    assert.ok((await S.req('GET', '/v1/player', { token: p.token })).json.player.iap.passes.includes('pass_growth'))
    await S.req('POST', '/v1/admin/refund', { token: admin.token, body: { order_id: 'google:GPA.a4' } })
    assert.ok(!(await S.req('GET', '/v1/player', { token: p.token })).json.player.iap.passes.includes('pass_growth'))
    const list = await S.req('GET', '/v1/admin/refunds', { token: admin.token })
    assert.equal(list.json.refunds.length, 3)
    assert.ok(list.json.orders.some((o: any) => o.order_id === 'google:GPA.a2'))
  } finally {
    S.close()
  }
})

test('채팅 금지: 관리자가 신고를 보고 금지하면 보내기 403 muted, 신고된 메시지는 지워지고 신고는 닫힌다, 풀면 다시 된다', async () => {
  const S = await setup()
  try {
    const admin = await asAdmin(S, 'mute')
    const bad = await S.login()
    const rep = await S.login()
    const say = (token: string, text: string) => S.req('POST', '/v1/chat', { token, body: { channel: 'all', text } })
    const m = await say(bad.token, '나쁜 말')
    assert.equal(m.status, 200)
    assert.equal((await S.req('POST', '/v1/chat/report', { token: rep.token, body: { id: m.json.msg.id } })).status, 200)
    assert.equal((await S.req('GET', '/v1/admin/chat/reports', { token: rep.token })).status, 403)
    const list = await S.req('GET', '/v1/admin/chat/reports', { token: admin.token })
    assert.equal(list.json.reports.length, 1)
    assert.equal(list.json.reports[0].target, bad.id)
    assert.equal(list.json.reports[0].target_open, 1)
    const mu = await S.req('POST', '/v1/admin/chat/mute', { token: admin.token, body: { player: bad.id, minutes: 60, reason: '욕설' } })
    assert.equal(mu.status, 200, JSON.stringify(mu.json))
    S.clock.t += 3
    assert.deepEqual([(await say(bad.token, '안녕')).status, (await say(bad.token, '안녕')).json.error], [403, 'muted'])
    const chat = await S.req('GET', '/v1/chat', { token: rep.token })
    assert.ok(!chat.json.all.some((x: any) => x.id === m.json.msg.id), 'reported message removed')
    const after = await S.req('GET', '/v1/admin/chat/reports', { token: admin.token })
    assert.equal(after.json.reports.length, 0)
    assert.equal(after.json.mutes[0].player, bad.id)
    assert.equal((await S.req('GET', '/v1/admin/chat/reports?filter=all', { token: admin.token })).json.reports[0].status, 'muted')
    S.clock.t += 3601
    assert.equal((await say(bad.token, '다시')).status, 200, 'mute expires')
    await S.req('POST', '/v1/admin/chat/mute', { token: admin.token, body: { player: bad.id, minutes: -1 } })
    S.clock.t += 3
    assert.equal((await say(bad.token, '또')).json.error, 'muted')
    await S.req('POST', '/v1/admin/chat/mute', { token: admin.token, body: { player: bad.id, minutes: 0 } })
    S.clock.t += 3
    assert.equal((await say(bad.token, '풀림')).status, 200)
    const m2 = await say(rep.token, '보통 말')
    const rep2 = await S.login()
    await S.req('POST', '/v1/chat/report', { token: rep2.token, body: { id: m2.json.msg.id } })
    const open = (await S.req('GET', '/v1/admin/chat/reports', { token: admin.token })).json.reports[0]
    assert.equal((await S.req('POST', '/v1/admin/chat/report', { token: admin.token, body: { id: open.id, status: 'dismissed' } })).json.status, 'dismissed')
    assert.equal((await S.req('GET', '/v1/admin/chat/reports', { token: admin.token })).json.open, 0)
  } finally {
    S.close()
  }
})

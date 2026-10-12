// 운영 도구(live_ops.ts): 공지·점검·최소 버전, 우편함(한 사람·모두, 한 번만, 기한), 쿠폰(계정당 한 번·전체 상한·기한·끄기), 관리자만 만든다.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as LO from '../src/live_ops.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
let admin: { token: string; id: string }
before(async () => {
  S = await setup()
  S.clock.t = T0
  admin = await S.login()
  await S.db.query("insert into player_identities (provider, provider_uid, player_id, email) values ('google', 'ops-admin', $1, 'ops-admin@example.com')", [admin.id])
  await S.db.query("insert into admin_emails (email) values ('ops-admin@example.com') on conflict do nothing")
})
after(async () => {
  await S.close()
})

const A = (path: string, body: unknown) => S.req('POST', path, { token: admin.token, body })
const code = (id: string) => id.replace(/-/g, '').slice(0, 8).toUpperCase()

test('관리자만: 일반 플레이어는 403', async () => {
  const { token } = await S.login()
  assert.equal((await S.req('GET', '/v1/admin/ops', { token })).status, 403)
  assert.equal((await S.req('POST', '/v1/admin/notice', { token, body: { title: 'x' } })).status, 403)
  assert.equal((await S.req('POST', '/v1/admin/mail', { token, body: { to: 'all', title: 'x', reward: { gold: 1 } } })).status, 403)
  assert.equal((await S.req('POST', '/v1/admin/coupon', { token, body: { code: 'ABCD', reward: { gold: 1 } } })).status, 403)
  assert.equal((await S.req('GET', '/v1/admin/ops', { token: admin.token })).status, 200)
})

test('공지: 만들기·고정·숨기기·기한, 로그인 없이 읽는다', async () => {
  S.clock.t = T0 + 10
  const a = await A('/v1/admin/notice', { title: '정기 점검 안내', body: '수요일 오전 점검', kind: 'maintenance' })
  assert.equal(a.status, 200)
  S.clock.t = T0 + 20
  const b = await A('/v1/admin/notice', { title: '이벤트', body: '출석 이벤트', kind: 'event', pinned: true })
  S.clock.t = T0 + 30
  await A('/v1/admin/notice', { title: '숨김', body: '', hidden: true })
  await A('/v1/admin/notice', { title: '끝난 공지', body: '', ends_at: T0 + 31 })
  S.clock.t = T0 + 40
  const r = await S.req('GET', '/v1/notices')
  assert.equal(r.status, 200)
  assert.deepEqual(r.json.notices.map((n: any) => n.title), ['이벤트', '정기 점검 안내'])
  assert.equal(r.json.notices[0].pinned, true)
  const st = await S.req('GET', '/v1/status')
  assert.equal(st.json.latest_notice, b.json.id)
  // 고치기
  await A('/v1/admin/notice', { id: a.json.id, title: '점검 끝', body: '', kind: 'notice' })
  assert.equal((await S.req('GET', '/v1/notices')).json.notices[1].title, '점검 끝')
  assert.equal((await A('/v1/admin/notice', { title: '', body: '' })).status, 400)
  assert.equal((await A('/v1/admin/notice', { id: 99999, title: 'x' })).status, 404)
  const ops = (await S.req('GET', '/v1/admin/ops', { token: admin.token })).json
  assert.ok(ops.notices.some((n: any) => n.hidden))
})

test('점검: 일반 플레이어 503(로그인·상태·공지는 열림), 관리자는 통과, 끄면 다시 열림', async () => {
  const { token } = await S.login()
  const on = await A('/v1/admin/status', { maintenance: true, maintenance_text: '서버 점검 중입니다', maintenance_until: T0 + 3600 })
  assert.equal(on.status, 200)
  const r = await S.req('GET', '/v1/player', { token })
  assert.equal(r.status, 503)
  assert.equal(r.json.error, 'maintenance')
  assert.equal(r.json.message, '서버 점검 중입니다')
  assert.equal(r.json.until, T0 + 3600)
  assert.equal((await S.req('GET', '/v1/status')).json.maintenance.on, true)
  assert.equal((await S.req('GET', '/v1/notices')).status, 200)
  assert.equal((await S.req('POST', '/v1/auth/guest', { body: { device_id: 'ops-maint-device-0001' } })).status, 200)
  assert.equal((await S.req('GET', '/v1/player', { token: admin.token })).status, 200)
  await A('/v1/admin/status', { maintenance: false })
  assert.equal((await S.req('GET', '/v1/player', { token })).status, 200)
})

test('최소 버전: 낮은 버전 426(상태·공지만 열림), 같거나 높으면 통과, 머리글 없으면 통과', async () => {
  const { token } = await S.login()
  await A('/v1/admin/status', { min_version: '0.3.0', store_url: 'https://play.google.com/store/apps/details?id=com.ilesong.castlerpg' })
  const old = await S.req('GET', '/v1/player', { token, headers: { 'x-app-version': '0.2.9' } })
  assert.equal(old.status, 426)
  assert.equal(old.json.error, 'update_required')
  assert.equal(old.json.store_url, 'https://play.google.com/store/apps/details?id=com.ilesong.castlerpg')
  assert.equal((await S.req('GET', '/v1/status', { headers: { 'x-app-version': '0.2.9' } })).status, 200)
  assert.equal((await S.req('GET', '/v1/player', { token, headers: { 'x-app-version': '0.3' } })).status, 200)
  assert.equal((await S.req('GET', '/v1/player', { token, headers: { 'x-app-version': '0.10.0' } })).status, 200)
  assert.equal((await S.req('GET', '/v1/player', { token })).status, 200)
  assert.equal((await A('/v1/admin/status', { min_version: 'abc' })).status, 400)
  await A('/v1/admin/status', { min_version: '' })
  assert.equal((await S.req('GET', '/v1/player', { token, headers: { 'x-app-version': '0.1.0' } })).status, 200)
  assert.ok(LO.cmpVersion('0.2.1', '0.2.10') < 0 && LO.cmpVersion('1.0', '0.9.9') > 0 && LO.cmpVersion('0.2', '0.2.0') === 0)
})

test('우편: 한 사람에게 — 보상(골드·다이아·열쇠 두 종류·영웅·장비·주머니)을 한 번만 받는다', async () => {
  S.clock.t = T0 + 100
  const me = await S.login()
  const before = (await S.req('GET', '/v1/player', { token: me.token })).json.player
  const sent = await A('/v1/admin/mail', { to: code(me.id), title: '문의 보상', body: '불편을 드려 죄송합니다',
    reward: { gold: 5000, diamonds: 300, keys_gold: 2, keys_equip: 1, hero: 'arteon', hero_n: 2, equip: { grade: 'SSR', n: 2 }, pouch_gold_60: 1 } })
  assert.equal(sent.status, 200, JSON.stringify(sent.json))
  assert.equal((await A('/v1/admin/mail', { to: 'FFFFFFFF', title: 'x', reward: {} })).status, 404)
  assert.equal((await A('/v1/admin/mail', { to: 'all', title: 'x', reward: { hero: 'nobody' } })).json.error, 'bad_reward')
  assert.equal((await A('/v1/admin/mail', { to: 'all', title: 'x', reward: { gold: -1 } })).json.error, 'bad_reward')
  const other = await S.login()
  assert.equal((await S.req('GET', '/v1/mail', { token: other.token })).json.mails.length, 0)
  const list = (await S.req('GET', '/v1/mail', { token: me.token })).json.mails
  assert.equal(list.length, 1)
  assert.equal(list[0].title, '문의 보상')
  const r = await S.req('POST', '/v1/mail/claim', { token: me.token, body: { ids: [list[0].id] } })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  const p = r.json.player
  assert.equal(p.gold_tenths, before.gold_tenths + 50000)
  assert.equal(p.diamonds, before.diamonds + 300)
  assert.deepEqual(r.json.claimed, [list[0].id])
  assert.equal(r.json.reward.items.length, 2)
  assert.ok(r.json.reward.items.every((it: any) => it.grade === 'SSR'))
  const dg = (await S.req('GET', '/v1/dungeon', { token: me.token })).json
  const keysOf = (t: string) => (dg.dungeons ?? dg)[t]?.keys
  const k0 = (x: string) => (before.dungeons ?? {})[x]?.keys ?? 0
  assert.ok(keysOf('gold') >= 2 && keysOf('equip') >= 1, JSON.stringify(dg).slice(0, 300) + k0('gold'))
  const hero = (await S.req('GET', '/v1/player', { token: me.token })).json.player.heroes.arteon
  assert.ok(hero && hero.copies >= 2, JSON.stringify(hero))
  // 두 번째는 없다
  assert.equal((await S.req('POST', '/v1/mail/claim', { token: me.token, body: { ids: [list[0].id] } })).json.error, 'claimed')
  assert.equal((await S.req('GET', '/v1/mail', { token: me.token })).json.mails.length, 0)
  // 남의 우편은 못 받는다
  assert.equal((await S.req('POST', '/v1/mail/claim', { token: other.token, body: { ids: [list[0].id] } })).json.error, 'claimed')
})

test('우편: 모두에게 — 그때 있던 계정만(new_players면 나중 계정도), 기한·지우기, 모두 받기', async () => {
  S.clock.t = T0 + 200
  const early = await S.login()
  S.clock.t = T0 + 210
  await A('/v1/admin/mail', { to: 'all', title: '점검 보상', body: '', reward: { diamonds: 100 }, expires_days: 1 })
  await A('/v1/admin/mail', { to: 'all', title: '환영 선물', body: '', reward: { tickets: 3 }, new_players: true, expires_days: 0 })
  const del = await A('/v1/admin/mail', { to: 'all', title: '잘못 보냄', body: '', reward: { gold: 1 } })
  await A('/v1/admin/mail/delete', { id: del.json.id })
  S.clock.t = T0 + 220
  const late = await S.login()
  const eMails = (await S.req('GET', '/v1/mail', { token: early.token })).json.mails
  assert.deepEqual(eMails.map((m: any) => m.title).sort(), ['점검 보상', '환영 선물'].sort())
  const lMails = (await S.req('GET', '/v1/mail', { token: late.token })).json.mails
  assert.deepEqual(lMails.map((m: any) => m.title), ['환영 선물'])
  const before = (await S.req('GET', '/v1/player', { token: early.token })).json.player
  const r = await S.req('POST', '/v1/mail/claim', { token: early.token, body: { ids: eMails.map((m: any) => m.id) } })
  assert.equal(r.status, 200)
  assert.equal(r.json.claimed.length, 2)
  assert.equal(r.json.player.diamonds, before.diamonds + 100)
  assert.equal(r.json.player.dia_tickets, before.dia_tickets + 3)
  // 기한 지난 우편은 안 보이고 못 받는다
  S.clock.t = T0 + 210 + 86400 + 1
  const third = await S.login() // 새 계정이지만 new_players 우편은 보인다
  assert.deepEqual((await S.req('GET', '/v1/mail', { token: third.token })).json.mails.map((m: any) => m.title), ['환영 선물'])
  const ops = (await S.req('GET', '/v1/admin/ops', { token: admin.token })).json
  assert.ok(ops.mails.find((m: any) => m.title === '점검 보상').claims >= 1)
})

test('쿠폰: 계정당 한 번, 대소문자·하이픈 무시, 전체 상한, 기한, 끄기, 없는 코드', async () => {
  S.clock.t = T0 + 300
  assert.equal((await A('/v1/admin/coupon', { code: 'WELCOME2026', reward: { gold: 1000, tickets: 2 } })).status, 200)
  assert.equal((await A('/v1/admin/coupon', { code: 'WELCOME2026', reward: { gold: 1 } })).json.error, 'coupon_exists')
  assert.equal((await A('/v1/admin/coupon', { code: 'NOREWARD', reward: {} })).json.error, 'bad_reward')
  assert.equal((await A('/v1/admin/coupon', { code: 'ab', reward: { gold: 1 } })).status, 400)
  await A('/v1/admin/coupon', { code: 'ONLYTWO', reward: { diamonds: 50 }, max_uses: 2 })
  await A('/v1/admin/coupon', { code: 'SHORTLIVED', reward: { diamonds: 50 }, expires_at: T0 + 400 })
  const u1 = await S.login()
  const before = (await S.req('GET', '/v1/player', { token: u1.token })).json.player
  const r = await S.req('POST', '/v1/coupon', { token: u1.token, body: { code: 'welcome-2026' } })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  assert.equal(r.json.player.gold_tenths, before.gold_tenths + 10000)
  assert.equal(r.json.player.dia_tickets, before.dia_tickets + 2)
  assert.equal((await S.req('POST', '/v1/coupon', { token: u1.token, body: { code: 'WELCOME2026' } })).json.error, 'coupon_used')
  assert.equal((await S.req('POST', '/v1/coupon', { token: u1.token, body: { code: 'NOSUCHCODE' } })).json.error, 'unknown_coupon')
  // 전체 상한 2
  const u2 = await S.login()
  const u3 = await S.login()
  assert.equal((await S.req('POST', '/v1/coupon', { token: u1.token, body: { code: 'ONLYTWO' } })).status, 200)
  assert.equal((await S.req('POST', '/v1/coupon', { token: u2.token, body: { code: 'ONLYTWO' } })).status, 200)
  assert.equal((await S.req('POST', '/v1/coupon', { token: u3.token, body: { code: 'ONLYTWO' } })).json.error, 'coupon_used_up')
  // 기한
  S.clock.t = T0 + 401
  assert.equal((await S.req('POST', '/v1/coupon', { token: u1.token, body: { code: 'SHORTLIVED' } })).json.error, 'coupon_expired')
  // 끄기
  await A('/v1/admin/coupon/disable', { code: 'WELCOME2026' })
  assert.equal((await S.req('POST', '/v1/coupon', { token: u2.token, body: { code: 'WELCOME2026' } })).json.error, 'unknown_coupon')
  const ops = (await S.req('GET', '/v1/admin/ops', { token: admin.token })).json
  const c2 = ops.coupons.find((c: any) => c.code === 'ONLYTWO')
  assert.equal(c2.uses, 2)
})

test('쿠폰 동시 사용: 마지막 한 장은 한 사람만', async () => {
  S.clock.t = T0 + 500
  await A('/v1/admin/coupon', { code: 'LASTONE', reward: { diamonds: 1 }, max_uses: 1 })
  const xs = await Promise.all([S.login(), S.login(), S.login()])
  const rs = await Promise.all(xs.map((x) => S.req('POST', '/v1/coupon', { token: x.token, body: { code: 'LASTONE' } })))
  assert.equal(rs.filter((r) => r.status === 200).length, 1, JSON.stringify(rs.map((r) => r.json?.error ?? r.status)))
  const [row] = await S.db.query("select uses from coupons where code = 'LASTONE'")
  assert.equal(Number(row.uses), 1)
})

test('로딩 일괄 조회에 공지·우편이 들어간다', async () => {
  const { token } = await S.login()
  const r = await S.req('GET', '/v1/boot', { token })
  assert.ok(Array.isArray(r.json.notices.notices))
  assert.ok(Array.isArray(r.json.mail.mails))
})

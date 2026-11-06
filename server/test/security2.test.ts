// 보안 점검 2차(2026-11-06, 해커 관점): 토스 계정 광고 예외 없앰 + 관리자 스위치, 실시간 방 다시 연결 누수, 파티 사람 수 판단,
// 채팅 욕설 우회 글자, 길드 이름·닉네임 사칭, 강제 업데이트 머리글 빼기.
import assert from 'node:assert/strict'
import { EventEmitter } from 'node:events'
import { after, before, test } from 'node:test'
import { clean, mask } from '../src/chat.ts'
import { PartyLive } from '../src/party_live.ts'
import { WarLive } from '../src/war_live.ts'
import * as R from '../src/rules.ts'
import { setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
let admin: { token: string; id: string }
before(async () => {
  S = await setup()
  S.clock.t = T0
  admin = await S.login()
  await S.db.query("insert into player_identities (provider, provider_uid, player_id, email) values ('google', 'sec2-admin', $1, 'sec2@example.com')", [admin.id])
  await S.db.query("insert into admin_emails (email) values ('sec2@example.com') on conflict do nothing")
})
after(() => S.close())

function fakeWs() {
  const ws = Object.assign(new EventEmitter(), {
    readyState: 1, bufferedAmount: 0, sent: [] as any[],
    send(s: string) { ws.sent.push(JSON.parse(s)) },
    ping() {}, terminate() { ws.readyState = 3 }, close() { ws.readyState = 3 },
  })
  return ws as any
}

test('광고 서버 확인 스위치: 관리자가 켜면 토스 계정도 확인된 광고 없이는 광고 상품을 못 받는다, 부팅 응답에 상태', async () => {
  const toss = await S.req('POST', '/v1/auth/toss', { body: { hash: 'sec2-toss-hash-0001' } })
  const buy = (n: number) => S.req('POST', '/v1/shop/buy', { token: toss.json.token, body: { id: 'a_dia', n, ad: true } })
  assert.equal((await buy(0)).status, 200, 'switch off: old behaviour')
  const st = await S.req('POST', '/v1/admin/status', { token: admin.token, body: { ad_ssv: true } })
  assert.equal(st.json.status.ad_ssv, true)
  assert.equal((await S.req('POST', '/v1/admin/status', { token: toss.json.token, body: { ad_ssv: false } })).status, 403)
  assert.equal((await buy(1)).json.error, 'ad_unverified')
  assert.equal((await S.req('GET', '/v1/boot', { token: toss.json.token })).json.ad_ssv, true)
  await S.req('POST', '/v1/admin/status', { token: admin.token, body: { ad_ssv: false } })
})

test('실시간 방: 혼자 있던 방에 다시 연결해도 새 연결이 방에 남는다(지워진 방에 들어가 안 닫히는 연결이 생기지 않는다)', () => {
  const party = new PartyLive()
  party.seatOf = () => 0
  const a1 = fakeWs()
  party.join('m', 'p1', a1)
  const a2 = fakeWs()
  party.join('m', 'p1', a2)
  assert.equal(party.rooms.get('m')?.clients.length, 1)
  assert.equal(party.rooms.get('m')?.clients[0].ws, a2)
  assert.equal(party.humansIn('m'), 1, 'one human even after reconnecting')
  party.join('m', 'p2', fakeWs())
  assert.equal(party.humansIn('m'), 2)
  const war = new WarLive()
  war.join('b', 'p1', fakeWs())
  const w2 = fakeWs()
  war.join('b', 'p1', w2)
  assert.equal(war.rooms.get('b')?.clients[0].ws, w2)
  party.close()
  war.close()
})

test('채팅: 전각·동그라미 글자·첫가끝 초성 욕설도 가린다, 보이지 않는 채움 글자만인 메시지는 빈 메시지', () => {
  assert.equal(mask(clean('ｆｕｃｋ')), '****')
  assert.equal(mask(clean('ⓕⓤⓒⓚ')), '****')
  assert.equal(mask(clean('ᄉᄇ')), '**')
  assert.equal(clean('ㅤㅤ ⠀'), '')
})

test('길드 이름: 보이지 않는 글자·운영자 사칭·기호는 400 bad_name, 가운데 띄어쓰기는 된다', async () => {
  const p = await S.login()
  const create = (name: string) => S.req('POST', '/v1/guild/create', { token: p.token, body: { name, emblem: 1 } })
  for (const name of ['운영자‮공지', '관리자길드', 'GM팀', '길드★']) assert.equal((await create(name)).json.error, 'bad_name', name)
  assert.notEqual((await create('우리 길드')).json.error, 'bad_name')
})

test('닉네임: 남의 자동 별명 모양은 쓸 수 없다', async () => {
  const p = await S.login()
  const other = await S.login()
  const victim = R.friendName(other.id)
  assert.ok(R.looksDefaultName(victim))
  const r = await S.req('POST', '/v1/nickname', { token: p.token, body: { name: victim } })
  assert.deepEqual([r.status, r.json.error], [400, 'bad_name'])
  assert.equal((await S.req('POST', '/v1/nickname', { token: p.token, body: { name: '성주킹' } })).status, 200)
})

test('접속 토큰 유효 시간은 옵션(운영 하루) — 지나면 401', async () => {
  const app = S.makeApp({ tokenTtlSec: 86400 })
  const res = await app.request('/v1/auth/guest', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ device_id: 'sec2-ttl-device-0001' }) })
  const { token } = await res.json() as any
  const get = async () => (await app.request('/v1/player', { headers: { authorization: `Bearer ${token}` } })).status
  assert.equal(await get(), 200)
  S.clock.t += 86401
  assert.equal(await get(), 401)
  S.clock.t = T0
})

// 계정 연동(소셜 로그인): start URL, provider 콜백(가짜 fetch)·연동·전환·기기 옮겨 묶기, poll, 실패·만료·남의 시도, 마이그레이션 017.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import { cpSync, mkdtempSync, readdirSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { migrate, MIGRATIONS_DIR, openDb } from '../src/db.ts'
import { randomDevice, setup, T0 } from './helpers.ts'
import type { Setup } from './helpers.ts'

const PUBLIC = 'https://api.example.test'
const OAUTH = { google: { id: 'g-id', secret: 'g-secret' }, kakao: { id: 'k-id', secret: 'k-secret' }, naver: { id: 'n-id', secret: 'n-secret' } }

// provider 흉내: 토큰 요청 → access_token, 사용자 정보 요청 → me. calls에 요청을 남긴다.
const fake = { me: {} as unknown, tokenStatus: 200, calls: [] as { url: string; init?: RequestInit }[] }
const fetchFake = (async (url: string | URL | Request, init?: RequestInit) => {
  const u = String(url)
  fake.calls.push({ url: u, init })
  if (u.includes('/token')) return new Response(JSON.stringify({ access_token: 'at-1' }), { status: fake.tokenStatus, headers: { 'content-type': 'application/json' } })
  return new Response(JSON.stringify(fake.me), { status: 200, headers: { 'content-type': 'application/json' } })
}) as typeof fetch

let S: Setup
before(async () => {
  S = await setup({ app: { oauth: OAUTH, publicUrl: PUBLIC, fetch: fetchFake } })
})
after(async () => {
  await S.close()
})

const start = async (token: string, provider: string, device: string) => S.req('POST', '/v1/auth/link/start', { token, body: { provider, device_id: device } })
// provider 콜백은 브라우저가 연다 — HTML 응답(S.req는 JSON만 읽는다)
const callback = async (provider: string, q: Record<string, string>) => {
  const r = await S.makeApp().request(`/v1/auth/${provider}/callback?${new URLSearchParams(q)}`)
  return { status: r.status, headers: r.headers, text: await r.text() }
}
const poll = (token: string, nonce: string) => S.req('GET', `/v1/auth/link/poll?nonce=${nonce}`, { token })
const links = async (token: string) => (await S.req('GET', '/v1/auth/links', { token })).json

test('마이그레이션 017: 게스트 로그인이 devices에 기기를 묶고, 같은 기기는 같은 플레이어', async () => {
  const dev = randomDevice()
  const a = await S.login(dev)
  const rows = await S.db.query('select player_id from devices where device_id = $1', [dev])
  assert.equal(rows.length, 1)
  assert.equal(rows[0].player_id, a.id)
  assert.equal((await S.login(dev)).id, a.id)
  assert.deepEqual(await links(a.token), { available: ['google', 'kakao', 'naver'], linked: [] })
})

test('start: provider 로그인 URL(client_id·redirect_uri·state=nonce, google은 scope=openid), 입력 검사, 꺼진 provider는 409', async () => {
  S.clock.t = T0
  const dev = randomDevice()
  const { token } = await S.login(dev)
  for (const [provider, host] of [['google', 'accounts.google.com'], ['kakao', 'kauth.kakao.com'], ['naver', 'nid.naver.com']]) {
    const r = await start(token, provider, dev)
    assert.equal(r.status, 200, provider)
    const u = new URL(r.json.url)
    assert.equal(u.host, host)
    assert.equal(u.searchParams.get('client_id'), OAUTH[provider as keyof typeof OAUTH].id)
    assert.equal(u.searchParams.get('redirect_uri'), `${PUBLIC}/v1/auth/${provider}/callback`)
    assert.equal(u.searchParams.get('response_type'), 'code')
    assert.match(r.json.nonce, /^[0-9a-f]{64}$/)
    assert.equal(u.searchParams.get('state'), r.json.nonce)
    assert.equal(u.searchParams.get('scope'), provider === 'google' ? 'openid' : null)
  }
  assert.equal((await start(token, 'apple', dev)).json.error, 'unknown_provider')
  assert.equal((await start(token, 'google', 'short')).json.error, 'bad_device_id')
  assert.equal((await S.req('POST', '/v1/auth/link/start', { token, body: {} })).status, 400)
  assert.equal((await S.req('POST', '/v1/auth/link/start', { body: { provider: 'google', device_id: dev } })).status, 401)
  // provider가 꺼진 서버(oauth 없음): 409, 연동 상태의 available은 빈 목록
  const bare = S.makeApp({ oauth: undefined, publicUrl: undefined })
  const r = await bare.request('/v1/auth/link/start', { method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: JSON.stringify({ provider: 'google', device_id: dev }) })
  assert.equal(r.status, 409)
  assert.equal((await r.json()).error, 'provider_unavailable')
  const l = await bare.request('/v1/auth/links', { headers: { authorization: `Bearer ${token}` } })
  assert.deepEqual((await l.json()).available, [])
  // 공개 주소가 비면 요청의 origin
  const local = S.makeApp({ publicUrl: undefined })
  const r2 = await local.request('http://127.0.0.1:8787/v1/auth/link/start', { method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: JSON.stringify({ provider: 'kakao', device_id: dev }) })
  assert.equal(new URL((await r2.json()).url).searchParams.get('redirect_uri'), 'http://127.0.0.1:8787/v1/auth/kakao/callback')
})

test('연동: 콜백이 code를 교환해 subject를 지금 플레이어에 묶는다(HTML 200), poll은 done·switched false·같은 플레이어 토큰, 시도는 한 번만', async () => {
  S.clock.t = T0
  const dev = randomDevice()
  const { token, id } = await S.login(dev)
  const { nonce } = (await start(token, 'google', dev)).json
  assert.deepEqual((await poll(token, nonce)).json, { status: 'pending' })
  fake.calls = []
  fake.me = { sub: 'google-sub-1' }
  const cb = await callback('google', { code: 'code-1', state: nonce })
  assert.equal(cb.status, 200)
  assert.match(cb.headers.get('content-type') ?? '', /text\/html/)
  assert.match(cb.text, /로그인 완료/)
  const [tokenCall, meCall] = fake.calls
  assert.equal(tokenCall.url, 'https://oauth2.googleapis.com/token')
  const form = new URLSearchParams(String(tokenCall.init?.body))
  assert.equal(form.get('grant_type'), 'authorization_code')
  assert.equal(form.get('code'), 'code-1')
  assert.equal(form.get('client_id'), 'g-id')
  assert.equal(form.get('client_secret'), 'g-secret')
  assert.equal(form.get('redirect_uri'), `${PUBLIC}/v1/auth/google/callback`)
  assert.equal(form.get('state'), nonce)
  assert.equal(meCall.url, 'https://openidconnect.googleapis.com/v1/userinfo')
  assert.equal((meCall.init?.headers as Record<string, string>).authorization, 'Bearer at-1')
  const p = await poll(token, nonce)
  assert.equal(p.status, 200)
  assert.equal(p.json.status, 'done')
  assert.equal(p.json.switched, false)
  assert.equal(p.json.player_id, id)
  assert.equal((await S.req('GET', '/v1/player', { token: p.json.token })).status, 200)
  assert.equal((await poll(token, nonce)).status, 404) // 가져간 시도는 사라진다
  assert.equal((await callback('google', { code: 'code-1', state: nonce })).status, 400) // 콜백 다시 재생도 안 된다
  assert.deepEqual((await links(token)).linked, ['google'])
  assert.deepEqual(await S.db.query('select player_id from player_identities where provider = $1 and subject = $2', ['google', 'google-sub-1']), [{ player_id: id }])
  // 같은 플레이어가 같은 계정으로 다시 로그인: 바뀌지 않는다
  const again = (await start(token, 'google', dev)).json.nonce
  await callback('google', { code: 'code-2', state: again })
  const p2 = await poll(token, again)
  assert.equal(p2.json.switched, false)
  assert.equal(p2.json.player_id, id)
})

test('전환: 다른 기기의 새 게스트가 이미 묶인 계정으로 로그인하면 그 플레이어가 되고(switched), 기기가 옮겨 묶여 다음 게스트 로그인도 그 플레이어', async () => {
  S.clock.t = T0
  const devA = randomDevice()
  const a = await S.login(devA)
  const n1 = (await start(a.token, 'kakao', devA)).json.nonce
  fake.me = { id: 123456789 } // 카카오 id는 숫자
  await callback('kakao', { code: 'c', state: n1 })
  assert.equal((await poll(a.token, n1)).json.switched, false)
  assert.deepEqual(await S.db.query('select subject from player_identities where player_id = $1', [a.id]), [{ subject: '123456789' }])
  const devB = randomDevice()
  const b = await S.login(devB)
  assert.notEqual(b.id, a.id)
  await S.req('POST', '/v1/test/grant_gold', { token: b.token, body: { amount: 500 } }) // B의 게스트 진행 — 버려진다
  const n2 = (await start(b.token, 'kakao', devB)).json.nonce
  await callback('kakao', { code: 'c2', state: n2 })
  const p = await poll(b.token, n2)
  assert.equal(p.json.status, 'done')
  assert.equal(p.json.switched, true)
  assert.equal(p.json.player_id, a.id)
  const me = await S.req('GET', '/v1/player', { token: p.json.token })
  assert.equal(me.json.player.gold, 0) // A의 상태(B의 500골드가 아니다)
  assert.equal((await S.login(devB)).id, a.id) // 기기 B는 이제 A
  assert.equal((await S.login(devA)).id, a.id)
  assert.deepEqual((await links(p.json.token)).linked, ['kakao'])
  // B(버려진 플레이어)의 시도는 B의 토큰으로만 — A의 토큰으로 B의 nonce를 묻는 건 404
  const n3 = (await start(b.token, 'naver', devB)).json.nonce
  assert.equal((await poll(p.json.token, n3)).status, 404)
  fake.me = { response: { id: 'naver-1' } }
  await callback('naver', { code: 'c3', state: n3 })
  assert.equal((await poll(b.token, n3)).json.switched, false) // 처음 보는 네이버 계정은 B에 묶인다
  assert.deepEqual((await links(b.token)).linked, ['naver'])
})

test('실패: 모르는 state·다른 provider 경로·끝난 시도는 400 HTML, 거부·provider 오류·만료는 poll에서 error 뒤 사라진다', async () => {
  S.clock.t = T0
  const dev = randomDevice()
  const { token } = await S.login(dev)
  assert.equal((await callback('google', { code: 'c', state: 'f'.repeat(64) })).status, 400)
  assert.equal((await callback('google', { code: 'c', state: 'not-a-nonce' })).status, 400)
  assert.equal((await callback('google', { code: 'c' })).status, 400)
  const n1 = (await start(token, 'google', dev)).json.nonce
  assert.equal((await callback('kakao', { code: 'c', state: n1 })).status, 400) // 구글 시도를 카카오 콜백으로
  assert.deepEqual((await poll(token, n1)).json, { status: 'pending' })
  const denied = await callback('google', { error: 'access_denied', state: n1 })
  assert.equal(denied.status, 200)
  assert.match(denied.text, /로그인 실패/)
  assert.deepEqual((await poll(token, n1)).json, { status: 'error', error: 'denied' })
  assert.equal((await poll(token, n1)).status, 404)
  const n2 = (await start(token, 'google', dev)).json.nonce
  fake.tokenStatus = 400
  await callback('google', { code: 'bad', state: n2 })
  fake.tokenStatus = 200
  assert.deepEqual((await poll(token, n2)).json, { status: 'error', error: 'provider' })
  const n3 = (await start(token, 'google', dev)).json.nonce
  fake.me = {} // 사용자 id 없음
  await callback('google', { code: 'c', state: n3 })
  assert.deepEqual((await poll(token, n3)).json, { status: 'error', error: 'provider' })
  const n4 = (await start(token, 'google', dev)).json.nonce
  S.clock.t = T0 + 600
  fake.me = { sub: 'late' }
  await callback('google', { code: 'c', state: n4 })
  assert.deepEqual((await poll(token, n4)).json, { status: 'error', error: 'expired' })
  assert.equal((await S.db.query('select count(*)::int as n from player_identities where subject = $1', ['late']))[0].n, 0)
  const n5 = (await start(token, 'google', dev)).json.nonce
  S.clock.t = T0 + 1200
  assert.deepEqual((await poll(token, n5)).json, { status: 'error', error: 'expired' }) // 콜백 없이 기다리기만 해도
  assert.equal((await poll(token, 'z'.repeat(64))).status, 404)
  assert.equal((await S.req('GET', '/v1/auth/link/poll?nonce=' + n5)).status, 401)
  assert.deepEqual((await links(token)).linked, [])
})

test('테스트 훅 link_done: 콜백 대신 subject로 끝낸다(내 시도만, 한 번만)', async () => {
  S.clock.t = T0
  const dev = randomDevice()
  const { token, id } = await S.login(dev)
  const other = await S.login()
  const { nonce } = (await start(token, 'naver', dev)).json
  assert.equal((await S.req('POST', '/v1/test/link_done', { token: other.token, body: { nonce, subject: 'x' } })).status, 404)
  assert.equal((await S.req('POST', '/v1/test/link_done', { token, body: { nonce } })).status, 400)
  assert.equal((await S.req('POST', '/v1/test/link_done', { token, body: { nonce, subject: 'hook-1' } })).status, 200)
  assert.equal((await S.req('POST', '/v1/test/link_done', { token, body: { nonce, subject: 'hook-1' } })).status, 404)
  const p = await poll(token, nonce)
  assert.deepEqual([p.json.status, p.json.switched, p.json.player_id], ['done', false, id])
})

test('마이그레이션 017: 있던 플레이어의 기기가 devices로 옮겨진다', async () => {
  const all = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort()
  const dir = mkdtempSync(join(tmpdir(), 'castle-mig-'))
  const d = await openDb({})
  try {
    for (const f of all.filter((f) => f < '017')) cpSync(join(MIGRATIONS_DIR, f), join(dir, f))
    await migrate(d, dir)
    const [p] = await d.query("insert into players (device_id) values ('mig-017-device-0001') returning id")
    assert.deepEqual(await migrate(d), ['017_accounts.sql'])
    assert.deepEqual(await d.query('select device_id, player_id from devices'), [{ device_id: 'mig-017-device-0001', player_id: p.id }])
  } finally {
    await d.close()
    rmSync(dir, { recursive: true, force: true })
  }
})

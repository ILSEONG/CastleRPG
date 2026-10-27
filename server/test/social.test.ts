// 소셜 로그인(oauth.ts + /v1/auth/*): 제공자 목록, start 검증, 인가 주소, 콜백(가짜 제공자 fetch) → poll(verifier) → 토큰·세션,
// 같은 계정 재로그인, 기기 게스트 계정 잇기(진행 유지), 취소·제공자 오류·시간 초과, 자동 로그인 세션·로그아웃, 환경 변수.
import assert from 'node:assert/strict'
import { createHash, randomBytes } from 'node:crypto'
import { test } from 'node:test'
import type { Query } from '../src/db.ts'
import * as O from '../src/oauth.ts'
import { setup, T0 } from './helpers.ts'

const OAUTH: O.OAuthConfig = {
  redirectBase: 'https://api.example.com',
  providers: { google: { clientId: 'g-id', clientSecret: 'g-secret' }, kakao: { clientId: 'k-rest', clientSecret: '' }, naver: { clientId: 'n-id', clientSecret: 'n-secret' } },
}

// 가짜 제공자: code "uid:<id>"면 그 id의 사용자, "bad"면 토큰 교환 실패. 받은 요청을 calls에 남긴다.
function fakeProviders() {
  const calls: { url: string; body?: string; auth?: string }[] = []
  const fetchFn = (async (input: any, init: any = {}) => {
    const url = String(input)
    calls.push({ url, body: init.body, auth: init.headers?.Authorization })
    const json = (v: unknown, status = 200) => new Response(JSON.stringify(v), { status, headers: { 'content-type': 'application/json' } })
    if (/token$/.test(url)) {
      const code = new URLSearchParams(init.body).get('code') ?? ''
      return code.startsWith('uid:') ? json({ access_token: `at-${code.slice(4)}`, token_type: 'bearer' }) : json({ error: 'invalid_grant' }, 400)
    }
    const id = String(init.headers?.Authorization ?? '').replace('Bearer at-', '')
    if (url.includes('googleapis')) return json({ sub: id, email: `${id.toLowerCase()}@Example.com`, email_verified: !id.startsWith('unverified') })
    if (url.includes('kakao')) return json({ id: Number(id) })
    if (url.includes('naver')) return json({ resultcode: '00', response: { id } })
    return json({}, 404)
  }) as typeof fetch
  return { calls, fetchFn }
}

const verifierPair = () => {
  const verifier = randomBytes(32).toString('hex')
  return { verifier, challenge: createHash('sha256').update(verifier).digest('hex') }
}

async function begin(S: Awaited<ReturnType<typeof setup>>, provider: string, device?: string) {
  const v = verifierPair()
  const r = await S.req('POST', '/v1/auth/oauth/start', { body: { provider, challenge: v.challenge, ...(device ? { device_id: device } : {}) } })
  assert.equal(r.status, 200, JSON.stringify(r.json))
  return { ...v, state: r.json.state as string, url: new URL(r.json.url) }
}

const callback = (S: Awaited<ReturnType<typeof setup>>, provider: string, q: Record<string, string>) =>
  S.req('GET', `/v1/auth/${provider}/callback?${new URLSearchParams(q)}`)

test('설정: 공개 주소 + 키가 있는 제공자만 켠다, 공개 주소가 없으면 전부 꺼진다, 콜백은 /v1/auth/<provider>/callback', () => {
  const cfg: O.OAuthConfig = { redirectBase: 'https://api.example.com', providers: { google: { clientId: 'g', clientSecret: 's' }, kakao: { clientId: 'k', clientSecret: '' } } }
  assert.deepEqual(O.enabledProviders(cfg), ['google', 'kakao'])
  assert.deepEqual(O.enabledProviders({ ...cfg, redirectBase: '' }), [])
  assert.equal(O.redirectUri(cfg, 'kakao'), 'https://api.example.com/v1/auth/kakao/callback')
})

test('providers·start 검증: 켜진 제공자만, 모르는 제공자 400, 꺼진 제공자 503, challenge 형식 400, 인가 주소', async () => {
  const S = await setup({ oauth: { ...OAUTH, providers: { google: OAUTH.providers.google, kakao: OAUTH.providers.kakao } } })
  try {
    assert.deepEqual((await S.req('GET', '/v1/auth/providers')).json, { providers: ['google', 'kakao'] })
    const v = verifierPair()
    assert.equal((await S.req('POST', '/v1/auth/oauth/start', { body: { provider: 'line', challenge: v.challenge } })).json.error, 'unknown_provider')
    const off = await S.req('POST', '/v1/auth/oauth/start', { body: { provider: 'naver', challenge: v.challenge } })
    assert.deepEqual([off.status, off.json.error], [503, 'provider_unavailable'])
    assert.equal((await S.req('POST', '/v1/auth/oauth/start', { body: { provider: 'google', challenge: 'xyz' } })).json.error, 'bad_challenge')
    const g = await begin(S, 'google')
    assert.equal(g.url.origin + g.url.pathname, 'https://accounts.google.com/o/oauth2/v2/auth')
    assert.deepEqual(Object.fromEntries(g.url.searchParams), { response_type: 'code', client_id: 'g-id',
      redirect_uri: 'https://api.example.com/v1/auth/google/callback', state: g.state, scope: 'openid email', prompt: 'select_account' })
    const k = await begin(S, 'kakao')
    assert.equal(k.url.origin + k.url.pathname, 'https://kauth.kakao.com/oauth/authorize')
    assert.equal(k.url.searchParams.get('client_id'), 'k-rest')
  } finally {
    await S.close()
  }
})

test('첫 로그인 = 새 계정(회원가입 없음): pending 202 → 콜백 → poll 한 번만 토큰·세션, 같은 계정 재로그인은 같은 플레이어', async () => {
  const P = fakeProviders()
  const S = await setup({ oauth: OAUTH, fetch: P.fetchFn })
  try {
    S.clock.t = T0
    const a = await begin(S, 'naver')
    let r = await S.req('POST', '/v1/auth/oauth/poll', { body: { state: a.state, verifier: a.verifier } })
    assert.deepEqual([r.status, r.json], [202, { pending: true }])
    const cb = await callback(S, 'naver', { code: 'uid:N-1', state: a.state })
    assert.equal(cb.status, 200)
    assert.match(cb.text, /로그인되었습니다/)
    const tokenCall = P.calls.find((x) => x.url.endsWith('/oauth2.0/token'))!
    assert.deepEqual(Object.fromEntries(new URLSearchParams(tokenCall.body)), { grant_type: 'authorization_code', code: 'uid:N-1',
      redirect_uri: 'https://api.example.com/v1/auth/naver/callback', client_id: 'n-id', client_secret: 'n-secret', state: a.state })
    const bad = await S.req('POST', '/v1/auth/oauth/poll', { body: { state: a.state, verifier: verifierPair().verifier } })
    assert.deepEqual([bad.status, bad.json.error], [403, 'bad_verifier'])
    r = await S.req('POST', '/v1/auth/oauth/poll', { body: { state: a.state, verifier: a.verifier } })
    assert.equal(r.status, 200)
    assert.deepEqual([r.json.provider, r.json.is_new, r.json.session.length], ['naver', true, 64])
    const p = await S.req('GET', '/v1/player', { token: r.json.token })
    assert.deepEqual([p.status, p.json.player.stage, Object.keys(p.json.player.heroes).length > 0], [200, 1, true]) // 시작 영웅이 있는 새 계정
    assert.equal((await S.req('POST', '/v1/auth/oauth/poll', { body: { state: a.state, verifier: a.verifier } })).status, 404) // 한 번만
    assert.equal((await callback(S, 'naver', { code: 'uid:N-1', state: a.state })).status, 400) // 끝난 state는 다시 못 쓴다
    const b = await begin(S, 'naver')
    await callback(S, 'naver', { code: 'uid:N-1', state: b.state })
    const again = await S.req('POST', '/v1/auth/oauth/poll', { body: { state: b.state, verifier: b.verifier } })
    assert.deepEqual([again.json.player_id, again.json.is_new], [r.json.player_id, false])
  } finally {
    await S.close()
  }
})

test('기기 게스트 계정 잇기: 그 기기로 소셜 로그인하면 게스트 진행 그대로, 이미 소셜 계정이 있는 플레이어에는 다른 계정을 잇지 않는다', async () => {
  const P = fakeProviders()
  const S = await setup({ oauth: OAUTH, fetch: P.fetchFn })
  try {
    S.clock.t = T0
    const device = 'device-0123456789abcdef'
    const guest = await S.login(device)
    await S.db.query('update player_state set gold_tenths = 123450 where player_id = $1', [guest.id])
    const a = await begin(S, 'kakao', device)
    await callback(S, 'kakao', { code: 'uid:777', state: a.state })
    const r = await S.req('POST', '/v1/auth/oauth/poll', { body: { state: a.state, verifier: a.verifier } })
    assert.deepEqual([r.json.player_id, r.json.is_new], [guest.id, false])
    assert.equal((await S.req('GET', '/v1/player', { token: r.json.token })).json.player.gold_tenths, 123450)
    const kakaoUser = P.calls.find((x) => x.url === 'https://kapi.kakao.com/v2/user/me')!
    assert.equal(kakaoUser.auth, 'Bearer at-777')
    const b = await begin(S, 'google', device) // 이미 카카오가 이어진 플레이어 → 구글은 새 계정
    await callback(S, 'google', { code: 'uid:G-9', state: b.state })
    const g = await S.req('POST', '/v1/auth/oauth/poll', { body: { state: b.state, verifier: b.verifier } })
    assert.notEqual(g.json.player_id, guest.id)
    assert.equal(g.json.is_new, true)
  } finally {
    await S.close()
  }
})

test('취소 → 401 login_denied, 제공자 오류 → 콜백 502 + 401 login_failed, 10분 넘으면 410 login_expired', async () => {
  const P = fakeProviders()
  const S = await setup({ oauth: OAUTH, fetch: P.fetchFn })
  try {
    S.clock.t = T0
    const a = await begin(S, 'google')
    assert.equal((await callback(S, 'google', { error: 'access_denied', state: a.state })).status, 200)
    const d = await S.req('POST', '/v1/auth/oauth/poll', { body: { state: a.state, verifier: a.verifier } })
    assert.deepEqual([d.status, d.json.error], [401, 'login_denied'])
    const b = await begin(S, 'google')
    assert.equal((await callback(S, 'google', { code: 'bad', state: b.state })).status, 502)
    const f = await S.req('POST', '/v1/auth/oauth/poll', { body: { state: b.state, verifier: b.verifier } })
    assert.deepEqual([f.status, f.json.error], [401, 'login_failed'])
    const c = await begin(S, 'google')
    S.clock.t = T0 + 601
    const e = await S.req('POST', '/v1/auth/oauth/poll', { body: { state: c.state, verifier: c.verifier } })
    assert.deepEqual([e.status, e.json.error], [410, 'login_expired'])
    assert.equal((await callback(S, 'google', { code: 'uid:late', state: c.state })).status, 400)
  } finally {
    await S.close()
  }
})

test('안드로이드 브라우저: 콜백이 끝나면 게임 앱 링크(castlerpg://oauth)로 302 — 못 열면 결과 안내 페이지, 다른 기기는 안내 페이지 그대로', async () => {
  const P = fakeProviders()
  const S = await setup({ oauth: OAUTH, fetch: P.fetchFn })
  const UA = { 'user-agent': 'Mozilla/5.0 (Linux; Android 14; SM-S918N) AppleWebKit/537.36 Chrome/129.0 Mobile Safari/537.36' }
  const androidCallback = (q: Record<string, string>) => S.req('GET', `/v1/auth/google/callback?${new URLSearchParams(q)}`, { headers: UA })
  const intent = (r: string) => `intent://oauth#Intent;scheme=castlerpg;package=com.ilesong.castlerpg;S.browser_fallback_url=${encodeURIComponent(`https://api.example.com/v1/auth/result?r=${r}`)};end`
  try {
    S.clock.t = T0
    const a = await begin(S, 'google')
    const ok = await androidCallback({ code: 'uid:AND-1', state: a.state })
    assert.deepEqual([ok.status, ok.headers.get('location')], [302, intent('ok')])
    const p = await S.req('POST', '/v1/auth/oauth/poll', { body: { state: a.state, verifier: a.verifier } })
    assert.equal(p.status, 200) // 앱은 돌아오자마자 poll로 결과를 받는다
    const b = await begin(S, 'google')
    const no = await androidCallback({ error: 'access_denied', state: b.state })
    assert.deepEqual([no.status, no.headers.get('location')], [302, intent('denied')])
    const bad = await androidCallback({ code: 'uid:x', state: 'f'.repeat(64) })
    assert.equal(bad.status, 400) // 모르는 진행 — 앱으로 보내지 않고 안내만
    const page = await S.req('GET', '/v1/auth/result?r=ok', { headers: UA })
    assert.ok(page.text.includes('로그인되었습니다') && page.text.includes('게임으로 돌아가기') && page.text.includes('intent://oauth#Intent;scheme=castlerpg;'))
    const fail = await S.req('GET', '/v1/auth/result?r=already_linked')
    assert.ok(fail.text.includes('로그인하지 못했습니다') && !fail.text.includes('게임으로 돌아가기'))
    const c = await begin(S, 'google')
    const pc = await callback(S, 'google', { code: 'uid:PC-1', state: c.state })
    assert.deepEqual([pc.status, pc.headers.get('location')], [200, null])
  } finally {
    await S.close()
  }
})

test('자동 로그인 세션: 같은 플레이어 토큰, 로그아웃하면 401 bad_session', async () => {
  const P = fakeProviders()
  const S = await setup({ oauth: OAUTH, fetch: P.fetchFn })
  try {
    S.clock.t = T0
    const a = await begin(S, 'google')
    await callback(S, 'google', { code: 'uid:G-1', state: a.state })
    const r = await S.req('POST', '/v1/auth/oauth/poll', { body: { state: a.state, verifier: a.verifier } })
    S.clock.t = T0 + 40 * 86400 // 첫 토큰은 만료된 뒤에도 세션으로 다시 들어간다
    const s = await S.req('POST', '/v1/auth/session', { body: { session: r.json.session } })
    assert.deepEqual([s.status, s.json.player_id, s.json.provider], [200, r.json.player_id, 'google'])
    assert.equal((await S.req('GET', '/v1/player', { token: s.json.token })).status, 200)
    assert.equal((await S.req('POST', '/v1/auth/logout', { body: { session: r.json.session } })).status, 200)
    const gone = await S.req('POST', '/v1/auth/session', { body: { session: r.json.session } })
    assert.deepEqual([gone.status, gone.json.error], [401, 'bad_session'])
    assert.equal((await S.req('POST', '/v1/auth/session', { body: { session: 'nope' } })).json.error, 'bad_session')
  } finally {
    await S.close()
  }
})

test('로그인 낚시 막기: 결과를 받는 IP가 콜백(브라우저) IP와 다르면 403 ip_mismatch(진행은 지운다, 관리자·일반 모두) — 같거나 어느 쪽이든 모르면 그대로', async () => {
  const P = fakeProviders()
  const S = await setup({ oauth: OAUTH, fetch: P.fetchFn })
  try {
    S.clock.t = T0
    await S.db.query("insert into admin_emails (email) values ('boss@example.com')")
    const at = (ip?: string) => (ip ? { headers: { 'cf-connecting-ip': ip } } : {})
    const login = async (uid: string, cbIp?: string, pollIp?: string) => {
      const a = await begin(S, 'google')
      await S.req('GET', `/v1/auth/google/callback?${new URLSearchParams({ code: `uid:${uid}`, state: a.state })}`, at(cbIp))
      const poll = () => S.req('POST', '/v1/auth/oauth/poll', { body: { state: a.state, verifier: a.verifier }, ...at(pollIp) })
      return { r: await poll(), poll }
    }
    const phish = await login('BOSS', '198.51.100.1', '203.0.113.66') // 남(203.…)이 시작한 로그인을 관리자 브라우저(198.…)가 끝냈다
    assert.deepEqual([phish.r.status, phish.r.json.error, phish.r.json.token], [403, 'ip_mismatch', undefined])
    assert.equal((await phish.poll()).status, 404)
    assert.equal((await S.db.query('select count(*)::int as n from player_sessions'))[0].n, 0)
    const same = await login('BOSS', '198.51.100.1', '198.51.100.1')
    assert.equal(same.r.status, 200)
    assert.equal((await S.req('GET', '/v1/player', { token: same.r.json.token })).json.player.admin, true)
    assert.equal((await login('BOSS', undefined, '203.0.113.66')).r.status, 200, 'callback IP unknown')
    assert.equal((await login('BOSS', '198.51.100.1')).r.status, 200, 'poll IP unknown')
    assert.equal((await login('someone', '198.51.100.1', '203.0.113.66')).r.json.error, 'ip_mismatch', 'ordinary accounts too')
    assert.equal((await login('someone', '198.51.100.1', '198.51.100.1')).r.status, 200)
  } finally {
    await S.close()
  }
})

test('로그인 낚시 막기: 웹 페이지(Origin 헤더)에서 소셜 로그인 시작·결과 받기는 CORS_ORIGINS에 있는 출처만, 앱(Origin 없음)은 그대로', async () => {
  const P = fakeProviders()
  const S = await setup({ oauth: OAUTH, fetch: P.fetchFn })
  try {
    S.clock.t = T0
    const start = (headers: Record<string, string>) => S.req('POST', '/v1/auth/oauth/start', { body: { provider: 'google', challenge: 'a'.repeat(64) }, headers })
    assert.equal((await start({ origin: 'https://evil.example' })).json.error, 'origin_not_allowed')
    assert.equal((await start({})).status, 200)
    const poll = await S.req('POST', '/v1/auth/oauth/poll', { body: { state: 'b'.repeat(64), verifier: 'c'.repeat(64) }, headers: { origin: 'https://evil.example' } })
    assert.equal(poll.json.error, 'origin_not_allowed')
    const web = S.makeApp({ corsOrigins: ['https://castle-rpg.web.tossmini.com'] })
    const ok = await web.request('/v1/auth/oauth/start', { method: 'POST', headers: { 'content-type': 'application/json', origin: 'https://castle-rpg.web.tossmini.com' },
      body: JSON.stringify({ provider: 'google', challenge: 'a'.repeat(64) }) })
    assert.equal(ok.status, 200, 'a listed web build can still log in')
  } finally {
    await S.close()
  }
})

test('마이그레이션 057 전 DB(callback_ip 열 없음)에서도 소셜 로그인이 된다 — IP 확인만 건너뛴다', async () => {
  const P = fakeProviders()
  const noCol = (q: Query): Query => async (text, params) => {
    if (text.includes('callback_ip')) throw new Error('column "callback_ip" of relation "oauth_logins" does not exist')
    return q(text, params)
  }
  const S = await setup({ oauth: OAUTH, fetch: P.fetchFn, wrapQuery: noCol })
  try {
    S.clock.t = T0
    const a = await begin(S, 'google')
    await S.req('GET', `/v1/auth/google/callback?${new URLSearchParams({ code: 'uid:OLD-DB', state: a.state })}`, { headers: { 'cf-connecting-ip': '198.51.100.1' } })
    const r = await S.req('POST', '/v1/auth/oauth/poll', { body: { state: a.state, verifier: a.verifier }, headers: { 'cf-connecting-ip': '203.0.113.66' } })
    assert.equal(r.status, 200, JSON.stringify(r.json))
    assert.ok(r.json.token)
  } finally {
    await S.close()
  }
})

test('슈퍼관리자: Google 확인 이메일이 admin_emails에 있으면 player.admin, 길드 잠금 해제 — 확인 안 된 이메일·다른 제공자는 아니다', async () => {
  const P = fakeProviders()
  const S = await setup({ oauth: OAUTH, fetch: P.fetchFn })
  try {
    await S.db.query("insert into admin_emails (email) values ('boss@example.com'), ('unverified-boss@example.com')")
    const login = async (provider: string, uid: string) => {
      const a = await begin(S, provider)
      await callback(S, provider, { code: `uid:${uid}`, state: a.state })
      return (await S.req('POST', '/v1/auth/oauth/poll', { body: { state: a.state, verifier: a.verifier } })).json.token as string
    }
    const player = async (token: string) => (await S.req('GET', '/v1/player', { token })).json.player
    const boss = await login('google', 'BOSS')
    assert.equal((await player(boss)).admin, true)
    assert.equal((await S.req('GET', '/v1/guild', { token: boss })).json.guild.unlocked, true) // 라운드 1-10 전인데 길드가 열린다
    assert.equal((await player(await login('google', 'unverified-BOSS'))).admin, false)
    assert.equal((await player(await login('google', 'someone'))).admin, false)
    assert.equal((await player(await login('naver', 'boss'))).admin, false)
    assert.equal((await player((await S.login()).token)).admin, false)
  } finally {
    await S.close()
  }
})

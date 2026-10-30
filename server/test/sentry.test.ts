// 오류 모음(server/src/sentry.ts): DSN이 없으면 꺼짐, 처리 못 한 서버 오류·앱 오류 보고가 Sentry envelope로 간다(요청 값 없이), 같은 오류 반복·분당 한도.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import { PER_MIN, Sentry, parseStack } from '../src/sentry.ts'
import { setup } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => {
  S = await setup()
})
after(async () => {
  await S.close()
})

const DSN = 'https://abc123@o1.ingest.sentry.io/42'
function capture() {
  const posts: { url: string; headers: any; event: any }[] = []
  const s = new Sentry(DSN, { release: 'r1', post: async (url, init) => { posts.push({ url, headers: init.headers, event: JSON.parse(String(init.body).split('\n')[2]) }) } })
  return { s, posts }
}

test('sentry: off without a DSN, bad DSN refused, envelope url and auth from the DSN', () => {
  assert.equal(new Sentry('').on, false)
  assert.equal(new Sentry('').capture({ type: 'E', message: 'x' }), false)
  assert.throws(() => new Sentry('not a dsn'))
  const { s, posts } = capture()
  assert.equal(s.capture({ type: 'TypeError', message: 'boom', stack: 'TypeError: boom\n    at f (/srv/src/app.ts:10:5)\n    at node:internal/x:1:1' }, 1000), true)
  assert.equal(posts[0].url, 'https://o1.ingest.sentry.io/api/42/envelope/')
  assert.match(posts[0].headers['x-sentry-auth'], /sentry_key=abc123/)
  const ev = posts[0].event
  assert.deepEqual([ev.exception.values[0].type, ev.exception.values[0].value, ev.release], ['TypeError', 'boom', 'r1'])
  assert.deepEqual(ev.exception.values[0].stacktrace.frames.map((f: any) => [f.filename, f.in_app]), [['node:internal/x', false], ['/srv/src/app.ts', true]])
  // 같은 오류는 한동안 한 번만, 전체는 분당 PER_MIN건
  assert.equal(s.capture({ type: 'TypeError', message: 'boom', stack: 'TypeError: boom\n    at f (/srv/src/app.ts:10:5)\n    at node:internal/x:1:1' }, 1001), false)
  let n = 0
  for (let i = 0; i < PER_MIN + 5; i++) if (s.capture({ type: 'E', message: 'e' + i }, 1010)) n++
  assert.equal(n, PER_MIN - 1)
})

test('sentry: GDScript stack lines become frames', () => {
  const f = parseStack('[0] _ready (res://scripts/chat.gd:52)\n[1] res://scripts/net.gd:10 - at function: poll')
  assert.deepEqual(f.map((x) => [x.function, x.filename, x.lineno]), [['poll', 'res://scripts/net.gd', 10], ['_ready', 'res://scripts/chat.gd', 52]])
})

test('sentry: an unhandled server error and app error reports are sent, without request values', async () => {
  const { s, posts } = capture()
  const app = S.makeApp({ sentry: s, allowTestHooks: true })
  app.get('/v1/test/explode', () => { throw new Error('kaboom') })
  const r = await app.request('/v1/test/explode')
  assert.equal(r.status, 500)
  assert.equal(posts.at(-1)!.event.exception.values[0].value, 'kaboom')
  const a = await S.login()
  const res = await app.request('/v1/client/errors', { method: 'POST', headers: { authorization: `Bearer ${a.token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ version: '1.2', os: 'Android', errors: [{ message: 'Invalid access to property', stack: '[0] f (res://scripts/x.gd:3)' }, { nope: 1 }, 'junk'] }) })
  assert.deepEqual(await res.json(), { ok: true, taken: 1 })
  const ev = posts.at(-1)!.event
  assert.deepEqual([ev.exception.values[0].type, ev.user.id, ev.tags.app_version, ev.platform], ['ScriptError', a.id, '1.2', 'other'])
  // 오류 모음이 꺼져 있으면 받기만
  const off = S.makeApp({})
  const r2 = await off.request('/v1/client/errors', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ errors: [{ message: 'x' }] }) })
  assert.deepEqual(await r2.json(), { ok: true, taken: 0 })
})

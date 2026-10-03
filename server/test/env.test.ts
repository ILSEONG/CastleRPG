// 시작 설정 검사(src/env.ts): 위험한 조합은 시작 거부.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { DEV_SECRET, readEnv } from '../src/env.ts'

const URL = 'postgresql://user:pass@example.invalid/db?sslmode=require'
const LONG = 'x'.repeat(32)

test('시작 거부: 운영(DATABASE_URL)에서 JWT_SECRET 없음·32자 미만·ALLOW_TEST_HOOKS=1', () => {
  assert.throws(() => readEnv({ DATABASE_URL: URL }), /JWT_SECRET is missing/)
  assert.throws(() => readEnv({ DATABASE_URL: URL, JWT_SECRET: 'x'.repeat(31) }), /at least 32/)
  assert.throws(() => readEnv({ DATABASE_URL: URL, JWT_SECRET: LONG, ALLOW_TEST_HOOKS: '1' }), /ALLOW_TEST_HOOKS/)
  const ok = readEnv({ DATABASE_URL: URL, JWT_SECRET: LONG, CORS_ORIGINS: 'https://a.example, https://b.example' })
  assert.equal(ok.secret, LONG)
  assert.equal(ok.hostname, '0.0.0.0')
  assert.equal(ok.allowTestHooks, false)
  assert.deepEqual(ok.corsOrigins, ['https://a.example', 'https://b.example'])
  assert.deepEqual(ok.warnings, [])
})

test('시작 거부: 고정 개발 비밀은 루프백 HOST에서만', () => {
  const dev = readEnv({})
  assert.equal(dev.secret, DEV_SECRET)
  assert.equal(dev.hostname, '127.0.0.1')
  assert.equal(dev.port, 8787)
  assert.equal(dev.warnings.length, 1)
  for (const h of ['localhost', '::1', '127.0.0.2']) assert.equal(readEnv({ HOST: h }).hostname, h)
  for (const h of ['0.0.0.0', '192.168.0.10', '::']) assert.throws(() => readEnv({ HOST: h }), /loopback/, h)
  // 개발 모드라도 자기 비밀을 주면 밖에 열 수 있다
  assert.equal(readEnv({ HOST: '0.0.0.0', JWT_SECRET: 'my-own-secret' }).hostname, '0.0.0.0')
  assert.equal(readEnv({ ALLOW_TEST_HOOKS: '1', PORT: '8790' }).allowTestHooks, true)
})

test('소셜 로그인 설정: ID·SECRET 둘 다 있어야 켜진다, 운영에서 provider를 켰으면 PUBLIC_URL 필수', () => {
  const on = readEnv({ OAUTH_GOOGLE_ID: 'g', OAUTH_GOOGLE_SECRET: 's', PUBLIC_URL: 'https://api.example.test/' })
  assert.deepEqual(on.oauth, { google: { id: 'g', secret: 's' } })
  assert.equal(on.publicUrl, 'https://api.example.test')
  assert.deepEqual(readEnv({}).oauth, {})
  assert.throws(() => readEnv({ OAUTH_KAKAO_ID: 'k' }), /OAUTH_KAKAO_ID and OAUTH_KAKAO_SECRET/)
  assert.throws(() => readEnv({ DATABASE_URL: URL, JWT_SECRET: LONG, OAUTH_NAVER_ID: 'n', OAUTH_NAVER_SECRET: 's' }), /PUBLIC_URL/)
  assert.equal(readEnv({ DATABASE_URL: URL, JWT_SECRET: LONG, OAUTH_NAVER_ID: 'n', OAUTH_NAVER_SECRET: 's', PUBLIC_URL: 'https://x.test' }).publicUrl, 'https://x.test')
})

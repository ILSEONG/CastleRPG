// 테스트 공용: 메모리 PGlite + 마이그레이션 + 시드 + 시계 주입 앱. 포트 없이 app.request()로 부른다.
import { randomBytes } from 'node:crypto'
import { createApp } from '../src/app.ts'
import type { AppOptions } from '../src/app.ts'
import { migrate, openDb } from '../src/db.ts'
import type { Db, Query } from '../src/db.ts'
import { seed } from '../src/seed.ts'

export const T0 = 1_790_000_000 // 2026-09-21, 정시 아님

export interface Setup {
  db: Db
  clock: { t: number }
  req: (method: string, path: string, o?: { token?: string; body?: unknown; headers?: Record<string, string> }) => Promise<{ status: number; headers: Headers; json: any }>
  login: (device?: string) => Promise<{ token: string; id: string }>
  makeApp: (o?: Partial<AppOptions>) => ReturnType<typeof createApp>
  close: () => Promise<void>
}

export const randomDevice = () => `test-${randomBytes(12).toString('hex')}`

export async function setup(o: { wrapQuery?: (q: Query) => Query; allowTestHooks?: boolean; secret?: string } = {}): Promise<Setup> {
  const db = await openDb({})
  await migrate(db)
  await seed(db)
  const clock = { t: T0 }
  const makeApp = (extra: Partial<AppOptions> = {}) => createApp({
    query: o.wrapQuery ? o.wrapQuery(db.query) : db.query,
    now: () => clock.t,
    jwtSecret: o.secret ?? 'test-secret-0123456789abcdef0123456789',
    allowTestHooks: o.allowTestHooks ?? true,
    ...extra,
  })
  const app = makeApp()
  const req: Setup['req'] = async (method, path, r = {}) => {
    const headers: Record<string, string> = { ...(r.headers ?? {}) }
    if (r.body !== undefined) headers['content-type'] = 'application/json'
    if (r.token) headers.authorization = `Bearer ${r.token}`
    const res = await app.request(path, {
      method,
      headers,
      body: r.body === undefined ? undefined : typeof r.body === 'string' ? r.body : JSON.stringify(r.body),
    })
    const text = await res.text()
    return { status: res.status, headers: res.headers, json: text ? JSON.parse(text) : null }
  }
  const login = async (device = randomDevice()) => {
    const r = await req('POST', '/v1/auth/guest', { body: { device_id: device } })
    if (r.status !== 200) throw new Error(`login failed: ${r.status} ${JSON.stringify(r.json)}`)
    return { token: r.json.token, id: r.json.player_id }
  }
  return { db, clock, req, login, makeApp, close: () => db.close() }
}

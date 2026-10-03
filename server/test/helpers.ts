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
  req: (method: string, path: string, o?: { token?: string; body?: unknown; headers?: Record<string, string> }) => Promise<{ status: number; headers: Headers; json: any; text: string }>
  login: (device?: string) => Promise<{ token: string; id: string }>
  makeApp: (o?: Partial<AppOptions>) => ReturnType<typeof createApp>
  close: () => Promise<void>
}

export const randomDevice = () => `test-${randomBytes(12).toString('hex')}`

// 처음 두 번의 플레이어 읽기를 서로 기다리게 한다 — 두 요청이 반드시 같은 version을 읽은 뒤 쓰기를 겨룬다(setup({wrapQuery: b.wrap})).
export function barrier() {
  let armed = false
  let arrived = 0
  let release = () => {}
  const both = new Promise<void>((r) => (release = r))
  const wrap = (q: Query): Query => async (text, params) => {
    if (armed && text.includes('from player_state s where') && arrived < 2) {
      arrived++
      if (arrived === 2) release()
      await both
    }
    return q(text, params)
  }
  return { wrap, arm: () => (armed = true), arrived: () => arrived }
}

export async function setup(o: { wrapQuery?: (q: Query) => Query; allowTestHooks?: boolean; secret?: string; random?: () => number; oauth?: AppOptions['oauth']; fetch?: typeof fetch } = {}): Promise<Setup> {
  const db = await openDb({})
  await migrate(db)
  await seed(db)
  const clock = { t: T0 }
  const makeApp = (extra: Partial<AppOptions> = {}) => createApp({
    query: o.wrapQuery ? o.wrapQuery(db.query) : db.query,
    now: () => clock.t,
    jwtSecret: o.secret ?? 'test-secret-0123456789abcdef0123456789',
    allowTestHooks: o.allowTestHooks ?? true,
    random: o.random,
    oauth: o.oauth,
    fetch: o.fetch,
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
    let json: any = null
    try {
      json = text ? JSON.parse(text) : null
    } catch {
      json = null // HTML(소셜 로그인 콜백 페이지) — 본문은 text로
    }
    return { status: res.status, headers: res.headers, json, text }
  }
  const login = async (device = randomDevice()) => {
    const r = await req('POST', '/v1/auth/guest', { body: { device_id: device } })
    if (r.status !== 200) throw new Error(`login failed: ${r.status} ${JSON.stringify(r.json)}`)
    return { token: r.json.token, id: r.json.player_id }
  }
  return { db, clock, req, login, makeApp, close: () => db.close() }
}

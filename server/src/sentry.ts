// 오류 모음(Sentry, 2026-10-30 사용자 "1~4번 다 해줘"의 1번). SENTRY_DSN이 있을 때만 켜진다(없으면 아무것도 보내지 않는다).
// 공식 SDK(@sentry/node)는 설치 47 MB에 모든 요청을 추적해 0.5 CPU 서버에 무겁다 — Sentry 받는 주소(envelope)에 fetch 한 번으로 보낸다.
//  서버: app.onError의 처리 못 한 오류, 처리 안 된 거부, 느린 요청(SLOW_MS 넘음 — 경고).
//  앱: POST /v1/client/errors로 받은 GDScript 오류(client_errors.gd).
// 무료 한도(월 5천 건)를 지키려고 같은 오류는 DEDUPE_SEC 동안 한 번, 전체는 분당 PER_MIN 건까지만 보낸다.
// 요청 값(본문·DB 오류의 detail)은 보내지 않는다 — 오류 이름·메시지·스택·경로만.
import { randomUUID } from 'node:crypto'

export const PER_MIN = 30
export const DEDUPE_SEC = 600
export const SLOW_MS = 3000

export interface Report {
  type: string
  message: string
  stack?: string // V8 스택(서버) 또는 GDScript 스택 줄들(앱)
  level?: 'error' | 'warning'
  platform?: 'node' | 'other'
  tags?: Record<string, string>
  user?: string // 플레이어 id
}

export class Sentry {
  readonly on: boolean
  sent = 0 // 테스트용
  private url = ''
  private auth = ''
  private recent = new Map<string, number>()
  private minute = 0
  private n = 0
  private release: string
  private environment: string
  private post: (url: string, init: RequestInit) => Promise<unknown>

  constructor(dsn: string, opts: { release?: string; environment?: string; post?: (url: string, init: RequestInit) => Promise<unknown> } = {}) {
    this.release = opts.release ?? ''
    this.environment = opts.environment ?? 'production'
    this.post = opts.post ?? ((u, i) => fetch(u, i))
    let ok = false
    if (dsn) {
      try {
        const u = new URL(dsn)
        const project = u.pathname.replace(/^\/+|\/+$/g, '')
        if (u.username && project) {
          this.url = `${u.protocol}//${u.host}/api/${project}/envelope/`
          this.auth = `Sentry sentry_version=7, sentry_key=${u.username}, sentry_client=castlerpg/1.0`
          ok = true
        }
      } catch {}
      if (!ok) throw new Error('SENTRY_DSN is not a valid Sentry DSN (https://<key>@<host>/<project>)')
    }
    this.on = ok
  }

  // 보낼지 정한다(꺼짐·같은 오류 반복·분당 한도). now = 유닉스 초
  private allow(key: string, now: number): boolean {
    if (!this.on) return false
    const last = this.recent.get(key)
    if (last !== undefined && now - last < DEDUPE_SEC) return false
    const m = Math.floor(now / 60)
    if (m !== this.minute) {
      this.minute = m
      this.n = 0
    }
    if (this.n >= PER_MIN) return false
    this.n++
    if (this.recent.size > 2000) this.recent.clear()
    this.recent.set(key, now)
    return true
  }

  capture(r: Report, now = Date.now() / 1000): boolean {
    const message = String(r.message).slice(0, 1000)
    const key = `${r.type}|${message.slice(0, 200)}|${(r.stack ?? '').slice(0, 300)}`
    if (!this.allow(key, now)) return false
    const eventId = randomUUID().replaceAll('-', '')
    const frames = parseStack(r.stack ?? '')
    const event = {
      event_id: eventId,
      timestamp: now,
      platform: r.platform ?? 'node',
      level: r.level ?? 'error',
      release: this.release || undefined,
      environment: this.environment,
      tags: r.tags,
      user: r.user ? { id: r.user } : undefined,
      exception: { values: [{ type: r.type.slice(0, 100), value: message, stacktrace: frames.length ? { frames } : undefined }] },
      extra: frames.length || !r.stack ? undefined : { stack: r.stack.slice(0, 4000) },
    }
    const body = `${JSON.stringify({ event_id: eventId, sent_at: new Date(now * 1000).toISOString() })}\n${JSON.stringify({ type: 'event' })}\n${JSON.stringify(event)}\n`
    this.sent++
    this.post(this.url, { method: 'POST', headers: { 'content-type': 'application/x-sentry-envelope', 'x-sentry-auth': this.auth }, body, signal: AbortSignal.timeout(5000) })
      .catch((e) => console.warn(`[sentry] send failed: ${(e as Error).message}`))
    return true
  }
}

// "at fn (file:line:col)" (V8) · "fn (res://x.gd:12)" · "res://x.gd:12 - fn" 줄을 Sentry 프레임으로(오래된 호출이 먼저).
export function parseStack(stack: string): { function?: string; filename: string; lineno?: number; colno?: number; in_app: boolean }[] {
  const out = []
  for (const line of stack.split('\n').slice(0, 50)) {
    const s = line.trim()
    let m = s.match(/^at (?:(.+?) \()?(.+?):(\d+)(?::(\d+))?\)?$/)
    if (m) {
      out.push({ function: m[1], filename: m[2], lineno: Number(m[3]), colno: m[4] ? Number(m[4]) : undefined, in_app: !m[2].includes('node_modules') && !m[2].startsWith('node:') })
      continue
    }
    m = s.match(/^(?:\[\d+\]\s*)?(?:(\S+) \()?(res:\/\/[^:()]+):(\d+)\)?(?: - (?:at function: )?(\S+))?$/)
    if (m) out.push({ function: m[1] ?? m[4], filename: m[2], lineno: Number(m[3]), in_app: true })
  }
  return out.reverse()
}

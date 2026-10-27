// 요청 횟수 상한(2026-10-14 보안 점검): 계정 만들기 도배(게스트·토스·소셜 시작), 쿠폰 코드 맞히기, 웹 계정 삭제 양식 도배를 막는다.
// 2026-10-27: 계정마다 인증 요청 수·IP마다 로그인 없는 DB 요청 수(app.ts — Neon 비용·도배), 계정 연동 시작.
// 서버 한 대의 메모리에만 센다(재시작하면 0부터) — 정확한 과금용이 아니라 자동화된 도배를 늦추는 용도. 창(window)마다 고정 칸으로 센다.
import type { Context } from 'hono'

export class Limiter {
  private hits = new Map<string, { start: number; n: number }>()
  private max: number
  private windowSec: number
  private cap: number
  constructor(max: number, windowSec: number, cap = 50_000) {
    this.max = max
    this.windowSec = windowSec
    this.cap = cap
  }

  // 이번 요청을 세고, 창 안에서 max를 넘었으면 false. now = 유닉스 초.
  take(key: string, now: number): boolean {
    let h = this.hits.get(key)
    if (!h || now - h.start >= this.windowSec) {
      if (this.hits.size >= this.cap) this.prune(now)
      h = { start: now, n: 0 }
      this.hits.set(key, h)
    }
    h.n++
    return h.n <= this.max
  }

  // at(그 take의 시각)에 센 것 하나를 되돌린다 — 세지 않을 결과였다(맞힌 쿠폰 코드 등). 그 뒤 창이 바뀌었으면 그대로.
  untake(key: string, at: number) {
    const h = this.hits.get(key)
    if (h && h.start <= at && at - h.start < this.windowSec && h.n > 0) h.n--
  }

  private prune(now: number) {
    for (const [k, h] of this.hits) if (now - h.start >= this.windowSec) this.hits.delete(k)
    if (this.hits.size >= this.cap) this.hits.clear() // 그래도 가득이면(공격 중) 비운다 — 메모리를 지킨다
  }
}

// 요청한 사람의 IP. 앞단 프록시(Render는 Cloudflare 뒤)가 덮어쓰는 헤더만 믿는다 — 사용자가 마음대로 넣을 수 있는
// X-Forwarded-For 맨 앞 값은 쓰지 않는다. 모르면 null(이때는 IP 상한을 걸지 않는다 — 모두 한 칸에 몰려 정상 사용자가 막히지 않게).
export function clientIp(c: Context): string | null {
  const v = c.req.header('cf-connecting-ip') ?? c.req.header('true-client-ip')
  const ip = v?.trim()
  return ip && ip.length <= 64 ? ip : null
}

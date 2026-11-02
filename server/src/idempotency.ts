// 중복 요청 방지(2026-11-02 사용자 "버튼을 빠르게 두번 누르면 두번 재화가 소모되는 것들이 있는지 조사해, 결재부분, 뽑기부분 다 포함이야"):
// 앱(net.gd)은 인증 POST마다 X-Request-Id(무작위)를 붙이고, 같은 요청을 다시 보낼 때(401 뒤·연결 실패 재시도) 같은 번호를 쓴다.
// 같은 계정·같은 번호가 다시 오면 처리하지 않고 처음 답(2xx)을 그대로 돌려준다 — 처리 중이면 끝날 때까지 기다렸다가 같은 답.
// 처음 요청이 실패(2xx 아님)했으면 기억하지 않는다(다시 보내면 다시 처리 — 실패한 요청은 아무것도 바꾸지 않았다).
// 서버 한 대 메모리(ratelimit.ts와 같다), TTL_SEC 동안. 답 본문은 MAX_BYTES까지만 들고 있고 넘치면 오래된 것부터 버린다.

export type Saved = { status: number; body: string; type: string }

export const TTL_SEC = 120
export const MAX_BYTES = 32 * 1024 * 1024
export const ID_RE = /^[A-Za-z0-9_-]{8,64}$/

type Entry = { at: number; p: Promise<Saved | null>; bytes: number }

export class Replays {
  private map = new Map<string, Entry>()
  private bytes = 0
  private ttlSec: number
  private maxBytes: number
  constructor(ttlSec = TTL_SEC, maxBytes = MAX_BYTES) {
    this.ttlSec = ttlSec
    this.maxBytes = maxBytes
  }

  // key의 앞 요청(처리 중이거나 끝난 2xx). 없으면 null.
  get(key: string, now: number): Promise<Saved | null> | null {
    const e = this.map.get(key)
    if (!e) return null
    if (now - e.at >= this.ttlSec) {
      this.drop(key)
      return null
    }
    return e.p
  }

  // key의 처리를 시작한다. 끝나면 finish(답 또는 null = 기억하지 않음)를 부른다.
  begin(key: string, now: number): (saved: Saved | null) => void {
    let resolve!: (s: Saved | null) => void
    const p = new Promise<Saved | null>((r) => (resolve = r))
    this.drop(key)
    this.map.set(key, { at: now, p, bytes: 0 })
    return (saved) => {
      resolve(saved)
      const e = this.map.get(key)
      if (!e || e.p !== p) return
      if (!saved) {
        this.map.delete(key)
        return
      }
      e.bytes = saved.body.length
      this.bytes += e.bytes
      this.trim(now)
    }
  }

  size() {
    return this.map.size
  }

  private drop(key: string) {
    const e = this.map.get(key)
    if (!e) return
    this.bytes -= e.bytes
    this.map.delete(key)
  }

  private trim(now: number) {
    for (const [k, e] of this.map) {
      if (this.bytes <= this.maxBytes && now - e.at < this.ttlSec) break
      this.drop(k) // Map은 넣은 순서 — 오래된 것부터
    }
  }
}

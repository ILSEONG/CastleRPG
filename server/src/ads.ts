// 보상형 광고 서버 확인(AdMob SSV, 2026-10-22).
// AdMob은 광고를 끝까지 본 사용자마다 우리 콜백 주소를 GET으로 부른다. 쿼리 끝의 signature·key_id는 그 앞 쿼리 문자열 전체에 대한
// ECDSA(SHA-256) 서명이고, 공개 키는 Google이 VERIFIER_KEYS_URL에 둔다(https://developers.google.com/admob/android/ssv).
import { createPublicKey, verify } from 'node:crypto'

export const VERIFIER_KEYS_URL = 'https://www.gstatic.com/admob/reward/verifier-keys.json'
const KEYS_TTL_MS = 24 * 3600 * 1000

export interface SsvParams {
  ad_unit: string
  custom_data: string
  user_id: string
  transaction_id: string
  timestamp: number // 밀리초
  key_id: string
}

// key_id → PEM. 하루 들고 있다가 다시 받는다(모르는 key_id가 오면 곧바로 다시 받는다 — 키 교체).
export function keyStore(fetchFn: typeof fetch) {
  let memo: { at: number; keys: Record<string, string> } | null = null
  async function load(): Promise<Record<string, string>> {
    const res = await fetchFn(VERIFIER_KEYS_URL)
    if (!res.ok) throw new Error(`verifier keys ${res.status}`)
    const j = (await res.json()) as { keys?: { keyId?: number | string; pem?: string }[] }
    const keys: Record<string, string> = {}
    for (const k of j.keys ?? []) if (k.keyId !== undefined && typeof k.pem === 'string') keys[String(k.keyId)] = k.pem
    memo = { at: Date.now(), keys }
    return keys
  }
  return async (keyId: string): Promise<string | undefined> => {
    if (!memo || Date.now() - memo.at > KEYS_TTL_MS) await load()
    if (!memo!.keys[keyId]) await load()
    return memo!.keys[keyId]
  }
}

const webSafe = (s: string) => Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64')

// 콜백 쿼리 문자열(? 뒤, 원문 그대로)을 확인한다. 서명이 맞으면 값들, 아니면 null.
export async function verifySsv(rawQuery: string, keyFor: (keyId: string) => Promise<string | undefined>): Promise<SsvParams | null> {
  const at = rawQuery.indexOf('&signature=')
  if (at <= 0) return null
  const message = rawQuery.slice(0, at)
  const q = new URLSearchParams(rawQuery)
  const sig = q.get('signature') ?? ''
  const keyId = q.get('key_id') ?? ''
  if (!sig || !keyId) return null
  const pem = await keyFor(keyId)
  if (!pem) return null
  let ok = false
  try {
    ok = verify('sha256', Buffer.from(message, 'utf8'), createPublicKey(pem), webSafe(sig))
  } catch {
    ok = false
  }
  if (!ok) return null
  return {
    ad_unit: q.get('ad_unit') ?? '', custom_data: q.get('custom_data') ?? '', user_id: q.get('user_id') ?? '',
    transaction_id: q.get('transaction_id') ?? '', timestamp: Number(q.get('timestamp') ?? 0), key_id: keyId,
  }
}

// 보상형 광고 서버 확인(AdMob SSV, 2026-10-22).
// AdMob은 광고를 끝까지 본 사용자마다 우리 콜백 주소를 GET으로 부른다. 쿼리 끝의 signature·key_id는 그 앞 쿼리 문자열 전체에 대한
// ECDSA(SHA-256) 서명이고, 공개 키는 Google이 VERIFIER_KEYS_URL에 둔다(https://developers.google.com/admob/android/ssv).
import { createPublicKey, verify } from 'node:crypto'

export const VERIFIER_KEYS_URL = 'https://www.gstatic.com/admob/reward/verifier-keys.json'
const KEYS_TTL_MS = 24 * 3600 * 1000
const RELOAD_MS = 60_000 // 키 파일을 다시 받는 최소 간격(모르는 key_id·실패) — 공개 콜백 하나가 바깥 요청 하나가 되지 않게

// 표를 확인하는 우리 보상형 광고 단위(scripts/ad_config.gd ANDROID_REWARDED_ID). 운영은 ADMOB_AD_UNITS(쉼표 구분, main.ts)로 바꾼다.
// Google은 모든 퍼블리셔의 콜백을 같은 키로 서명한다 — 남의 광고 단위 콜백에 우리 표를 실어 보낼 수 있어 광고 단위를 본다.
export const AD_UNITS = ['ca-app-pub-7646904883481371/5685684246']
// 콜백의 ad_unit은 광고 단위 id의 숫자 부분(/ 뒤, 예 2747237135)이다. 목록은 전체 id·숫자 둘 다 받는다.
export const adUnitOk = (units: string[], adUnit: string) => adUnit !== '' && units.some((u) => u === adUnit || u.slice(u.lastIndexOf('/') + 1) === adUnit)

export interface SsvParams {
  ad_unit: string
  custom_data: string
  user_id: string
  transaction_id: string
  timestamp: number // 밀리초
  key_id: string
}

// key_id → PEM. 하루 들고 있다가 다시 받는다(모르는 key_id가 오면 다시 받는다 — 키 교체). 받는 중이면 그 한 번을 같이 기다리고,
// 다시 받기는 RELOAD_MS에 한 번까지(모르는 key_id 도배·키 서버 오류 때 바깥 요청이 늘지 않게). now = 밀리초(테스트 주입).
export function keyStore(fetchFn: typeof fetch, now: () => number = Date.now) {
  let memo: { at: number; keys: Record<string, string> } | null = null
  let loading: Promise<void> | null = null
  let tried = -Infinity
  function load(): Promise<void> {
    if (loading) return loading
    tried = now()
    loading = (async () => {
      const res = await fetchFn(VERIFIER_KEYS_URL)
      if (!res.ok) throw new Error(`verifier keys ${res.status}`)
      const j = (await res.json()) as { keys?: { keyId?: number | string; pem?: string }[] }
      const keys: Record<string, string> = {}
      for (const k of j.keys ?? []) if (k.keyId !== undefined && typeof k.pem === 'string') keys[String(k.keyId)] = k.pem
      memo = { at: now(), keys }
    })().finally(() => (loading = null))
    return loading
  }
  return async (keyId: string): Promise<string | undefined> => {
    if (memo && now() - memo.at <= KEYS_TTL_MS && Object.hasOwn(memo.keys, keyId)) return memo.keys[keyId]
    if (loading || now() - tried >= RELOAD_MS) await load()
    if (!memo) throw new Error('verifier keys unavailable') // 방금 받기에 실패했다 — 503, AdMob이 나중에 다시 부른다
    return Object.hasOwn(memo.keys, keyId) ? memo.keys[keyId] : undefined
  }
}

const webSafe = (s: string) => Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64')

// 콜백 쿼리 문자열(? 뒤, 원문 그대로)을 확인한다. 서명이 맞으면 값들, 아니면 null.
export async function verifySsv(rawQuery: string, keyFor: (keyId: string) => Promise<string | undefined>): Promise<SsvParams | null> {
  const at = rawQuery.indexOf('&signature=')
  if (at <= 0) return null
  const message = rawQuery.slice(0, at)
  const q = new URLSearchParams(message) // 값은 서명된 앞부분에서만 — 서명 뒤에 덧붙인 custom_data 등은 믿지 않는다
  const tail = new URLSearchParams(rawQuery.slice(at + 1))
  const sig = tail.get('signature') ?? ''
  const keyId = tail.get('key_id') ?? ''
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

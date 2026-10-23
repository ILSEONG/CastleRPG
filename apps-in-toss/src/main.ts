// 앱인토스(토스 미니앱) 래퍼: Godot 웹 빌드(public/game/)를 띄우고, 게임이 쓸 토스 SDK 기능을 window.castleToss로 내준다.
// - getUserKey(cb): 게임 로그인 사용자 식별키(getUserKeyForGame hash). cb(hash) 또는 cb('UNSUPPORTED' | 'INVALID_CATEGORY' | 'ERROR').
//   게임(scripts/toss_bridge.gd)이 이 값으로 서버 /v1/auth/toss에 로그인한다.
// - 인앱 결제(2026-10-12, 토스 인앱 결제 IAP — 게임은 scripts/store_pay.gd):
//   buy(sku, onGrant, onDone): 주문서를 연다. 결제가 끝나면 onGrant(orderId) — 게임이 서버(/v1/iap/purchase)에 확인·지급을 받고
//   granted(orderId, ok)로 답하면 그 값이 SDK processProductGrant의 결과(true = 지급 완료)가 된다. 끝나면 onDone('success', orderId) 또는
//   onDone('error', 코드)('UNSUPPORTED' = 토스 앱이 오래됨).
//   pendingOrders(cb): 결제는 됐는데 지급이 안 끝난 주문 cb(JSON [{orderId, sku}]) — 게임이 다시 서버에 보내고 completeGrant(orderId).
// - log(name, json)(2026-10-23, 이탈 기록): 게임 분석 이벤트(scripts/game_log.gd) → SDK Analytics.log(앱인토스 콘솔 분석에서 본다).
//   json = 평평한 {키: 값}. 실패·미지원 토스 앱은 조용히 넘긴다.
// - 안드로이드 뒤로 가기: 종료 확인 창(출시 가이드: 종료할 때 확인 모달) → closeView().
// - 백그라운드로 가면 게임 소리를 멈춘다(AudioContext suspend).
import { Analytics, closeView, getUserKeyForGame, graniteEvent, IAP } from '@apps-in-toss/web-framework'

declare global {
  interface Window {
    castleToss: {
      getUserKey: (cb: (result: string) => void) => void
      buy: (sku: string, onGrant: (orderId: string) => void, onDone: (kind: string, detail: string) => void) => void
      granted: (orderId: string, ok: boolean) => void
      pendingOrders: (cb: (json: string) => void) => void
      completeGrant: (orderId: string) => void
      log: (name: string, json: string) => void
    }
    Engine: any
  }
}

window.castleToss = {
  log(name, json) {
    try {
      const params = JSON.parse(json || '{}')
      Analytics.log({ log_name: name, log_type: 'event', params: params && typeof params === 'object' ? params : {} }).catch(() => {})
    } catch { /* 기록만 빠진다 */ }
  },

  getUserKey(cb) {
    getUserKeyForGame()
      .then((r: any) => {
        if (r === undefined) cb('UNSUPPORTED') // 토스 앱 5.232.0 미만
        else if (r === 'INVALID_CATEGORY' || r === 'ERROR') cb(r)
        else if (r && r.type === 'HASH' && typeof r.hash === 'string') cb(r.hash)
        else cb('ERROR')
      })
      .catch(() => cb('ERROR'))
  },

  buy(sku, onGrant, onDone) {
    if (!IAP.createOneTimePurchaseOrder.isSupported()) {
      onDone('error', 'UNSUPPORTED') // 토스 앱 5.219.0 미만
      return
    }
    let cleanup: (() => void) | null = null
    const end = (kind: string, detail: string) => {
      try { cleanup?.() } catch { /* 이미 끝남 */ }
      cleanup = null
      onDone(kind, detail)
    }
    try {
      cleanup = IAP.createOneTimePurchaseOrder({
        options: {
          sku,
          // 결제가 끝나면 토스가 부른다: 게임이 서버 지급 결과를 granted()로 알려 줄 때까지 기다린다(아니면 토스가 주문을 대기로 남긴다)
          processProductGrant: ({ orderId }) => new Promise<boolean>((resolve) => {
            grants.set(orderId, resolve)
            onGrant(orderId)
          }),
        },
        onEvent: (e) => end('success', e?.data?.orderId ?? ''),
        onError: (err: any) => end('error', String(err?.code ?? err?.message ?? err ?? 'ERROR')),
      })
    } catch (err: any) {
      end('error', String(err?.message ?? 'ERROR'))
    }
  },

  granted(orderId, ok) {
    const r = grants.get(orderId)
    grants.delete(orderId)
    r?.(ok === true)
  },

  pendingOrders(cb) {
    if (!IAP.getPendingOrders.isSupported()) {
      cb('[]')
      return
    }
    IAP.getPendingOrders()
      .then((r: any) => cb(JSON.stringify((r?.orders ?? []).map((o: any) => ({ orderId: String(o.orderId), sku: String(o.sku ?? o.productId ?? '') })))))
      .catch(() => cb('[]'))
  },

  completeGrant(orderId) {
    if (IAP.completeProductGrant.isSupported()) IAP.completeProductGrant({ params: { orderId } }).catch(() => {})
  },
}
const grants = new Map<string, (ok: boolean) => void>() // 주문 번호 → processProductGrant 결과 알리기

// --- 종료 확인 ---
const exitBox = document.getElementById('exit') as HTMLDivElement
document.getElementById('exit-no')!.addEventListener('click', () => (exitBox.style.display = 'none'))
document.getElementById('exit-yes')!.addEventListener('click', () => void closeView())
try {
  graniteEvent.addEventListener('backEvent', {
    onEvent: () => {
      exitBox.style.display = exitBox.style.display === 'flex' ? 'none' : 'flex'
    },
    onError: () => {},
  })
} catch {
  // 토스 밖(일반 브라우저)에서는 뒤로 가기 이벤트가 없다
}

// --- 백그라운드 소리 멈춤(출시 가이드: 토스 앱을 내리거나 화면이 꺼지면 소리가 나지 않아야 한다) ---
// 게임 엔진이 만드는 AudioContext를 모아 두고, 화면이 가려지면 suspend, 다시 보이면 resume한다.
const audioContexts: AudioContext[] = []
const BaseAudioContext = window.AudioContext ?? (window as any).webkitAudioContext
if (BaseAudioContext) {
  const Tracked = class extends BaseAudioContext {
    constructor(...args: any[]) {
      super(...args)
      audioContexts.push(this as unknown as AudioContext)
    }
  }
  window.AudioContext = Tracked as typeof AudioContext
  ;(window as any).webkitAudioContext = Tracked
}
document.addEventListener('visibilitychange', () => {
  for (const ctx of audioContexts) {
    if (document.hidden) void ctx.suspend().catch(() => {})
    else void ctx.resume().catch(() => {})
  }
})

// --- 게임 시작 ---
const bar = document.querySelector('#bar > div') as HTMLDivElement
const loading = document.getElementById('loading') as HTMLDivElement

async function start() {
  const config = await (await fetch('./game/godot-config.json')).json() // dev/build-toss.sh가 Godot 내보내기의 GODOT_CONFIG를 옮겨 둔다
  await new Promise<void>((ok, fail) => {
    const s = document.createElement('script')
    s.src = './game/index.js'
    s.onload = () => ok()
    s.onerror = () => fail(new Error('engine script failed to load'))
    document.head.appendChild(s)
  })
  const engine = new window.Engine({
    ...config,
    executable: 'game/index',
    mainPack: 'game/index.pck',
    ensureCrossOriginIsolationHeaders: false, // 스레드 없는 빌드 — SharedArrayBuffer·서비스 워커가 필요 없다
    serviceWorker: '',
  })
  await engine.startGame({
    onProgress: (cur: number, total: number) => {
      if (total > 0) bar.style.width = `${Math.min(100, (cur / total) * 100)}%`
    },
  })
  loading.style.display = 'none'
}

start().catch((e) => {
  console.error(e)
  loading.innerHTML = '<p style="margin-bottom:20vh;color:#fff;font:18px system-ui">게임을 불러오지 못했습니다. 다시 열어 주세요.</p>'
})

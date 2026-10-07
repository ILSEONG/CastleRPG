// 앱인토스(토스 미니앱) 래퍼: Godot 웹 빌드(public/game/)를 띄우고, 게임이 쓸 토스 SDK 기능을 window.castleToss로 내준다.
// - getUserKey(cb): 게임 로그인 사용자 식별키(getUserKeyForGame hash). cb(hash) 또는 cb('UNSUPPORTED' | 'INVALID_CATEGORY' | 'ERROR').
//   게임(scripts/toss_bridge.gd)이 이 값으로 서버 /v1/auth/toss에 로그인한다.
// - 안드로이드 뒤로 가기: 종료 확인 창(출시 가이드: 종료할 때 확인 모달) → closeView().
import { closeView, getUserKeyForGame, graniteEvent } from '@apps-in-toss/web-framework'

declare global {
  interface Window {
    castleToss: { getUserKey: (cb: (result: string) => void) => void }
    Engine: any
  }
}

window.castleToss = {
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
}

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
  loading.innerHTML = '<p style="margin-bottom:20vh;color:#fff;font:18px system-ui">게임을 불러오지 못했어요. 다시 열어 주세요.</p>'
})

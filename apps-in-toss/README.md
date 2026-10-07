# 앱인토스(토스 미니앱) 빌드

같은 Godot 프로젝트를 토스 앱 안 미니앱(웹)으로 묶는다. Google Play 빌드(APK)와 다른 점:

| | Google Play (APK) | 앱인토스 (.ait) |
|---|---|---|
| 내보내기 프리셋 | Android | AppsInToss (웹, 스레드 없음, 피처 태그 `apps_in_toss`) |
| 로그인 화면 | Google·카카오·네이버 + 게스트 | 없음 — 토스 게임 로그인(`getUserKeyForGame`)으로 바로 시작 |
| 서버 로그인 | `/v1/auth/oauth/*`, `/v1/auth/guest` | `/v1/auth/toss` (hash는 sha256만 저장) |
| 결제 | Google Play 결제(연결 전) | 토스 인앱 결제(연결 전) |

게임은 `scripts/release_platform.gd`로 빌드를 구분한다(`castle/platform`). 래퍼 `src/main.ts`가 토스 SDK를 `window.castleToss`로 내주고
(`scripts/toss_bridge.gd`가 부른다), 안드로이드 뒤로 가기에 종료 확인 창을 띄운다.

## 빌드

```sh
GODOT=godot bash dev/build-toss.sh        # → apps-in-toss/castlerpg.ait (콘솔에 올린다)
BUILD=debug GODOT=godot bash dev/build-toss.sh   # 토스 밖 브라우저 시험용(?api=…&toss_hash=…)
```

앱인토스 제한: 압축 해제 기준 100MB 이하(지금 약 76MB). `apps-in-toss.config.ts`의 `appName`은 콘솔에 등록한 앱 이름과 같아야 한다.
서버 CORS: Render에 `CORS_ORIGINS`를 정했다면 `https://<appName>.web.tossmini.com`, `https://<appName>.private-web.tossmini.com`을 더한다(비우면 전부 허용).

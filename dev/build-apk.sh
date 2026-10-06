#!/usr/bin/env bash
# 안드로이드 APK → export/android/CastleRPG.apk. 창을 띄우지 않는다(--headless).
# 출시 빌드(--export-release): 디버그 템플릿의 검사·디버거 부담이 없어 같은 장면에서 CPU를 덜 쓴다(발열). 화면·동작은 같다.
# 서명 키는 지금까지 쓰던 debug.keystore 그대로(같은 키라 이전 APK 위에 업데이트 설치된다) — 환경 변수로 넘긴다.
# OS.is_debug_build() 개발 플래그(--heroes, --api 등)는 출시 빌드에서 꺼진다. 디버그가 필요하면 BUILD=debug.
# 서버 주소(castle/api_base_url)가 비어 있으면 오프라인 저장으로 돈다. arm64(폰) + x86_64(에뮬레이터).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-./tools/Godot_v4.7.2-stable_win64_console.exe}
KEYSTORE=${KEYSTORE:-$HOME/.local/share/godot/keystores/debug.keystore}
mkdir -p export/android
touch export/.gdignore   # 빌드 산출물을 Godot가 리소스로 임포트하지 않게
"$GODOT" --headless --quiet --path . --import
if [ "${BUILD:-release}" = "debug" ]; then
	"$GODOT" --headless --quiet --path . --export-debug "Android" export/android/CastleRPG.apk
else
	GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE" GODOT_ANDROID_KEYSTORE_RELEASE_USER=androiddebugkey \
		GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=android \
		"$GODOT" --headless --quiet --path . --export-release "Android" export/android/CastleRPG.apk
fi
ls -la export/android/CastleRPG.apk

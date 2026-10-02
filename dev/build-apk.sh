#!/usr/bin/env bash
# 안드로이드 APK → export/android/CastleRPG.apk. 창을 띄우지 않는다(--headless).
# 디버그 빌드(--export-debug, 에디터 설정의 debug.keystore로 서명) — 폰에 바로 설치해 실행한다(adb install -r).
# 서버 주소(castle/api_base_url)가 비어 있으면 오프라인 저장으로 돈다. arm64(폰) + x86_64(에뮬레이터).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=./tools/Godot_v4.7.2-stable_win64_console.exe
mkdir -p export/android
touch export/.gdignore   # 빌드 산출물을 Godot가 리소스로 임포트하지 않게
"$GODOT" --headless --quiet --path . --import
"$GODOT" --headless --quiet --path . --export-debug "Android" export/android/CastleRPG.apk
ls -la export/android/CastleRPG.apk

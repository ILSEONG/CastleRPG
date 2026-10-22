#!/usr/bin/env bash
# 안드로이드 APK → export/android/CastleRPG.apk. 창을 띄우지 않는다(--headless).
# 출시 빌드(--export-release): 디버그 템플릿의 검사·디버거 부담이 없어 같은 장면에서 CPU를 덜 쓴다(발열). 화면·동작은 같다.
# 서명 키는 지금까지 쓰던 debug.keystore 그대로(같은 키라 이전 APK 위에 업데이트 설치된다) — 환경 변수로 넘긴다.
# OS.is_debug_build() 개발 플래그(--heroes, --api 등)는 출시 빌드에서 꺼진다. 디버그가 필요하면 BUILD=debug.
# 서버 주소(castle/api_base_url)가 비어 있으면 오프라인 저장으로 돈다. arm64(폰) + x86_64(에뮬레이터).
# Gradle 빌드(2026-10-12, 푸시 알림 addons/castle_notify·Google Play 결제 addons/castle_billing AAR을 넣으려고): android/build(템플릿 소스, 저장소에 넣지 않는다)가
# 없으면 내보내기 템플릿에서 설치한다(--install-android-build-template). 필요: Android SDK(ANDROID_HOME, platform 36·build-tools 36.1.0 —
# 없으면 Gradle이 받는다), JDK 17+(JAVA_HOME). 첫 빌드는 Gradle·의존성을 받느라 몇 분 걸린다.
# FORMAT=aab: Google Play에 올리는 앱 번들 export/android/CastleRPG.aab(프리셋 gradle_build/export_format을 빌드 동안만 1로).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-./tools/Godot_v4.7.2-stable_win64_console.exe}
KEYSTORE=${KEYSTORE:-$HOME/.local/share/godot/keystores/debug.keystore}
# 스토어 업로드 키(2026-10-22): KEYSTORE=<upload .jks> KEY_ALIAS=upload KEY_PASSWORD=<비밀번호>. 비우면 테스트 키(debug.keystore).
KEY_ALIAS=${KEY_ALIAS:-androiddebugkey}
KEY_PASSWORD=${KEY_PASSWORD:-android}
FORMAT=${FORMAT:-apk}
case "$FORMAT" in
	apk) OUT=export/android/CastleRPG.apk; EXPORT_FORMAT=0 ;;
	aab) OUT=export/android/CastleRPG.aab; EXPORT_FORMAT=1 ;;
	*) echo "FORMAT 은 apk 또는 aab" >&2; exit 1 ;;
esac

mkdir -p export/android
touch export/.gdignore   # 빌드 산출물을 Godot가 리소스로 임포트하지 않게

# 내보내기 형식(APK/AAB)은 프리셋 옵션이라 빌드 동안만 바꾸고 끝나면 되돌린다.
PRESETS_BAK=""
if ! grep -q "^gradle_build/export_format=$EXPORT_FORMAT\$" export_presets.cfg; then
	PRESETS_BAK=$(mktemp)
	cp export_presets.cfg "$PRESETS_BAK"
	trap 'cp "$PRESETS_BAK" export_presets.cfg; rm -f "$PRESETS_BAK"' EXIT
	sed -i "s|^gradle_build/export_format=.*|gradle_build/export_format=$EXPORT_FORMAT|" export_presets.cfg
fi

"$GODOT" --headless --quiet --path . --import
INSTALL=()
[ -d android/build ] || INSTALL=(--install-android-build-template)
if [ "${BUILD:-release}" = "debug" ]; then
	"$GODOT" --headless --quiet --path . "${INSTALL[@]}" --export-debug "Android" "$OUT"
else
	GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE" GODOT_ANDROID_KEYSTORE_RELEASE_USER="$KEY_ALIAS" \
		GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$KEY_PASSWORD" \
		"$GODOT" --headless --quiet --path . "${INSTALL[@]}" --export-release "Android" "$OUT"
fi
ls -la "$OUT"

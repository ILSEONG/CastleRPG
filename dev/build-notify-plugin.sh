#!/usr/bin/env bash
# 알림 안드로이드 플러그인(android_plugins/castle_notify, Java) → addons/castle_notify/bin/castle_notify-release.aar.
# Java 소스를 바꿨을 때만 다시 만든다(AAR은 저장소에 들어 있다). 필요: JDK 17+, Android SDK(ANDROID_HOME), Godot 4.7.2 내보내기 템플릿.
set -euo pipefail
cd "$(dirname "$0")/.."
TEMPLATES=${TEMPLATES:-$HOME/.local/share/godot/export_templates/4.7.2.stable}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
# godot-lib(컴파일 전용) — 템플릿 android_source.zip 안의 AAR에서 classes.jar만 꺼낸다.
unzip -q -o "$TEMPLATES/android_source.zip" libs/release/godot-lib.template_release.aar -d "$WORK"
unzip -q -o "$WORK/libs/release/godot-lib.template_release.aar" classes.jar -d "$WORK"
(cd android_plugins/castle_notify && ./gradlew --no-daemon -q -PgodotLibJar="$WORK/classes.jar" assembleRelease)
cp android_plugins/castle_notify/build/outputs/aar/castle_notify-release.aar addons/castle_notify/bin/
ls -la addons/castle_notify/bin/castle_notify-release.aar

#!/usr/bin/env bash
# 플러그인 AAR을 빌드해 addons/castle_billing/bin/ 으로 복사한다(그 AAR은 커밋되므로 평소 빌드엔 필요 없음).
# 필요: JDK 17+ (JAVA_HOME), Android SDK (ANDROID_HOME 또는 local.properties 의 sdk.dir).
set -euo pipefail
cd "$(dirname "$0")"
export ANDROID_HOME=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}
./gradlew --no-daemon assembleRelease
mkdir -p ../../addons/castle_billing/bin
cp build/outputs/aar/castle_billing-release.aar ../../addons/castle_billing/bin/castle_billing-release.aar
ls -la ../../addons/castle_billing/bin/castle_billing-release.aar

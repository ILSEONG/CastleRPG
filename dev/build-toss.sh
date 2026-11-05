#!/usr/bin/env bash
# 앱인토스(토스 미니앱) 묶음 빌드 → apps-in-toss/*.ait (콘솔에 올리는 파일).
# 1) Godot "AppsInToss" 프리셋(웹, 스레드 없음, 피처 태그 apps_in_toss — 토스 게임 로그인만)으로 apps-in-toss/public/game/에 내보낸다.
# 2) 내보낸 index.html의 GODOT_CONFIG를 godot-config.json으로 옮기고 그 html은 지운다(래퍼 index.html이 대신 띄운다).
# 3) 래퍼(vite + @apps-in-toss/web-framework)를 묶고 `ait build`로 .ait를 만든다. 앱인토스 제한: 압축 해제 기준 100MB 이하.
# BUILD=debug면 디버그 내보내기(?api=·?toss_hash= 사용 가능 — 토스 밖 브라우저 시험용, 올리지 않는다). GODOT=godot 경로를 바꿀 수 있다.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
GODOT=${GODOT:-godot}
OUT=apps-in-toss/public/game
rm -rf "$OUT" && mkdir -p "$OUT"
# 용량 줄이기(토스 묶음만, 2026-11-05 — 엔진 40MB + 게임 데이터 61MB가 100MB를 넘었다). 게임 내용·숫자는 그대로:
#  - 배경 음악 10곡을 약 64kbps로 다시 인코딩(원본 ~105kbps), 그림(jpg) 손실 압축 품질 0.7 → 0.6.
#  - 바꾼 원본·.import는 내보낸 뒤 git으로 되돌리고 다시 가져온다(APK·AAB 빌드에는 영향 없음). SLIM=0이면 건너뛴다.
SLIM_FILES=()
restore_slim() {
  if [ ${#SLIM_FILES[@]} -gt 0 ]; then
    (cd "$ROOT" && git checkout -- "${SLIM_FILES[@]}" && "$GODOT" --headless --quiet --path . --import >/dev/null 2>&1) || true
  fi
}
trap restore_slim EXIT
if [ "${SLIM:-1}" = 1 ]; then
  for f in assets/audio/music/*.ogg; do
    ffmpeg -v error -y -i "$f" -c:a libvorbis -q:a 0 "$f.slim.ogg" && mv "$f.slim.ogg" "$f"
    SLIM_FILES+=("$f")
  done
  while IFS= read -r f; do
    if grep -q '^compress/lossy_quality=0.7$' "$f"; then sed -i 's/^compress\/lossy_quality=0.7$/compress\/lossy_quality=0.6/' "$f"; SLIM_FILES+=("$f"); fi
  done < <(git ls-files '*.jpg.import')
fi
"$GODOT" --headless --quiet --path . --import
if [ "${BUILD:-release}" = debug ]; then MODE=--export-debug; else MODE=--export-release; fi
"$GODOT" --headless --quiet --path . $MODE "AppsInToss" "$OUT/index.html"
node -e '
  const fs = require("fs"); const f = process.argv[1]
  const m = /const GODOT_CONFIG = (\{.*?\});/.exec(fs.readFileSync(f, "utf8"))
  if (!m) throw new Error("GODOT_CONFIG not found in " + f)
  fs.writeFileSync(process.argv[2], m[1])
' "$OUT/index.html" "$OUT/godot-config.json"
rm -f "$OUT/index.html" "$OUT/index.service.worker.js" "$OUT/index.manifest.json" "$OUT/index.offline.html" "$OUT/index.icon.png" "$OUT/index.apple-touch-icon.png"
# 래퍼 index.html의 로딩 배경(game/index.png)은 내보내기가 다시 저장한 무압축 PNG(1.7MB) — 원본(256색, 0.5MB)으로 바꾼다
cp assets/ui/splash.png "$OUT/index.png"
cd apps-in-toss
[ -d node_modules ] || npm ci
npx vite build
du -sh dist
total=$(du -sb dist | cut -f1)
if [ "$total" -gt 100000000 ]; then echo "dist is $total bytes: over the 100MB Apps in Toss limit" >&2; exit 1; fi
restore_slim; SLIM_FILES=()
npx ait build
ls -la *.ait 2>/dev/null || true

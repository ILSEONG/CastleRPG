#!/usr/bin/env bash
# 앱인토스(토스 미니앱) 묶음 빌드 → apps-in-toss/*.ait (콘솔에 올리는 파일).
# 1) Godot "AppsInToss" 프리셋(웹, 스레드 없음, 피처 태그 apps_in_toss — 토스 게임 로그인만)으로 apps-in-toss/public/game/에 내보낸다.
# 2) 내보낸 index.html의 GODOT_CONFIG를 godot-config.json으로 옮기고 그 html은 지운다(래퍼 index.html이 대신 띄운다).
# 3) 래퍼(vite + @apps-in-toss/web-framework)를 묶고 `ait build`로 .ait를 만든다. 앱인토스 제한: 압축 해제 기준 100MB 이하.
# BUILD=debug면 디버그 내보내기(?api=·?toss_hash= 사용 가능 — 토스 밖 브라우저 시험용, 올리지 않는다). GODOT=godot 경로를 바꿀 수 있다.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
OUT=apps-in-toss/public/game
rm -rf "$OUT" && mkdir -p "$OUT"
"$GODOT" --headless --quiet --path . --import
if [ "${BUILD:-release}" = debug ]; then MODE=--export-debug; else MODE=--export-release; fi
"$GODOT" --headless --quiet --path . $MODE "AppsInToss" "$OUT/index.html"
node -e '
  const fs = require("fs"); const f = process.argv[1]
  const m = /const GODOT_CONFIG = (\{.*?\});/.exec(fs.readFileSync(f, "utf8"))
  if (!m) throw new Error("GODOT_CONFIG not found in " + f)
  fs.writeFileSync(process.argv[2], m[1])
' "$OUT/index.html" "$OUT/godot-config.json"
rm -f "$OUT/index.html" "$OUT/index.service.worker.js" "$OUT/index.manifest.json" "$OUT/index.offline.html"
cd apps-in-toss
[ -d node_modules ] || npm ci
npx vite build
du -sh dist
total=$(du -sb dist | cut -f1)
if [ "$total" -gt 100000000 ]; then echo "dist is $total bytes: over the 100MB Apps in Toss limit" >&2; exit 1; fi
npx ait build
ls -la *.ait 2>/dev/null || true

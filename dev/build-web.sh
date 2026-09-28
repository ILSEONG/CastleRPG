#!/usr/bin/env bash
# 웹 빌드 → export/web/index.html. 창을 띄우지 않는다(--headless).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=./tools/Godot_v4.7.2-stable_win64_console.exe
mkdir -p export/web
touch export/.gdignore   # 빌드 산출물을 Godot가 리소스로 임포트하지 않게
"$GODOT" --headless --quiet --path . --import
"$GODOT" --headless --quiet --path . --export-debug "Web" export/web/index.html
ls -la export/web/index.html export/web/index.pck

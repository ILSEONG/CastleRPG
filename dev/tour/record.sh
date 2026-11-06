#!/usr/bin/env bash
# 소개 영상 한 편 녹화: 로컬 테스트 서버(메모리 PGlite)를 새로 띄워 seed.py로 채우고 tests/tour_movie.tscn을 --write-movie로 녹화 → mp4.
# 사용: bash dev/tour/record.sh <item> <slot 0..9> <out.mp4>
# 실서버 DB는 절대 쓰지 않는다(env -u DATABASE_URL). 게임 코드·숫자는 바꾸지 않는다.
set -uo pipefail
cd "$(dirname "$0")/../.."
ITEM=$1; SLOT=${2:-0}; OUT=$3
PORT=$((8790 + SLOT)); API=http://127.0.0.1:$PORT
TMP=$(mktemp -d /tmp/tour_${ITEM}_XXXX)
DEV="tour-main-player-device-0001"
[ "$ITEM" = guide ] && DEV="tour-new-player-device-0002"
echo "{\"device_id\":\"$DEV\"}" > "$TMP/device.json"
cd server
env -u DATABASE_URL PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=$PORT node src/main.ts > "$TMP/server.log" 2>&1 &
SPID=$!
cd ..
trap 'kill $SPID 2>/dev/null' EXIT
for i in $(seq 1 60); do curl -s --noproxy '*' "$API/v1/health" | grep -q '"ok":true' && break; sleep 0.5; done
python3 dev/tour/seed.py "$API" tour-main-player-device-0001 > "$TMP/seed.log" 2>&1 || { cat "$TMP/seed.log"; exit 1; }
if [ "$ITEM" = guide ]; then
  curl -s --noproxy '*' -o /dev/null -X POST -H 'content-type: application/json' -d '{"key":"tutorial_new_players","value":"1"}' "$API/v1/test/config"
fi
timeout 900 xvfb-run -n $((91 + SLOT)) -s "-screen 0 720x1280x24" godot --path . --resolution 720x1280 --write-movie "$TMP/m.avi" --fixed-fps 30 \
  res://tests/tour_movie.tscn -- --api="$API" --device="$TMP/device.json" --item="$ITEM" > "$TMP/godot.log" 2>&1
grep -E "MOVIE|SCRIPT ERROR|TOUR no button|^ERROR: .*tour" "$TMP/godot.log" | head -20
START=$(grep -o "MOVIE start frame [0-9]*" "$TMP/godot.log" | awk '{print $4}')
SS=$(python3 -c "print(max(0, (${START:-0}) / 30 - 0.3))")
ffmpeg -loglevel error -y -ss "$SS" -i "$TMP/m.avi" -c:v libx264 -preset veryfast -crf 24 -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart "$OUT"
ls -la "$OUT"; rm -f "$TMP/m.avi"

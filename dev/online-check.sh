#!/usr/bin/env bash
# 온라인 통합 체크(개정 9 §7): API 서버(메모리 PGlite, ALLOW_TEST_HOOKS=1, 포트 8790)를 띄우고
# Godot 헤드리스로 tests/online_check를 다섯 번 돌린다(2: 같은 기기 id — 골드·자원·스테이지 복원, 3~5: 소셜 로그인·자동 로그인·낡은 세션).
# 서버는 트랩으로 항상 끈다. 둘 다 통과하면 마지막 줄이 ONLINE ALL PASSED.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-./tools/Godot_v4.7.2-stable_win64_console.exe}
PORT=8790
API=http://127.0.0.1:$PORT
TMP=$(mktemp -d)
WTMP=$(cygpath -m "$TMP" 2>/dev/null || echo "$TMP")  # Godot에 넘길 Windows 경로
SERVER_PID=""

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
    # 그래도 남아 있으면 그 포트를 쥔 프로세스를 끈다(시작 전에 비어 있음을 확인했으니 우리 서버다).
    # 서버를 띄우지 않았으면(포트가 이미 쓰이는 중) 남의 서버라 건드리지 않는다.
    local wpid
    wpid=$(netstat -ano 2>/dev/null | grep -E "127\.0\.0\.1:$PORT .*LISTEN" | awk '{print $5}' | head -1)
    if [ -n "$wpid" ]; then taskkill //F //PID "$wpid" >/dev/null 2>&1; fi
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

if curl -s -o /dev/null "$API/v1/health"; then
  echo "port $PORT is already in use"
  exit 1
fi

cd server
PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=$PORT node src/main.ts > "$TMP/server.log" 2>&1 &
SERVER_PID=$!
cd ..

for i in $(seq 1 60); do
  if curl -s "$API/v1/health" | grep -q '"ok":true'; then break; fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then break; fi
  sleep 0.5
done
if ! curl -s "$API/v1/health" | grep -q '"ok":true'; then
  echo "server did not start:"
  cat "$TMP/server.log"
  exit 1
fi
echo "[online-check] server up on $API"
# 통합 체크는 건물이 다 지어진 새 플레이어(튜토리얼 끔)와 옛 훈련 묶음 상한(10 + 2(L−1))으로 규칙을 본다
for kv in tutorial_new_players=0 train_batch_base=10 train_batch_per_level=2; do
  curl -s -o /dev/null -X POST -H 'content-type: application/json' -d "{\"key\":\"${kv%%=*}\",\"value\":\"${kv#*=}\"}" "$API/v1/test/config"
done

ok=1
for phase in 1 2 3 4 5 6; do
  timeout "${ONLINE_TIMEOUT:-300}" "$GODOT" --headless --path . res://tests/online_check.tscn -- \
    --api="$API" --device="$WTMP/device.json" --state="$WTMP/state.json" --phase=$phase > "$TMP/phase$phase.log" 2>&1
  rc=$?
  grep -E "^ONLINE |SCRIPT ERROR|^ERROR|^USER ERROR" "$TMP/phase$phase.log"
  if [ $rc -ne 0 ] || ! grep -q "^ONLINE PHASE $phase PASSED" "$TMP/phase$phase.log"; then
    echo "[online-check] phase $phase failed (exit $rc); log tail:"
    tail -40 "$TMP/phase$phase.log"
    ok=0
    break
  fi
done

if [ $ok -eq 1 ]; then
  echo "ONLINE ALL PASSED"
  exit 0
fi
echo "[online-check] server log tail:"
tail -20 "$TMP/server.log"
echo "ONLINE FAILED"
exit 1

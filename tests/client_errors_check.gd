extends SceneTree
## 앱 오류 보고(scripts/client_errors.gd) 체크: push_error·스크립트 오류가 모이고, 같은 오류는 한 번만, 경고는 빼고, 서버(--api)로 보내진다.
## 실행: cd server && env -u DATABASE_URL PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=8790 node src/main.ts &
##   godot --headless --path . -s res://tests/client_errors_check.gd -- --api=http://127.0.0.1:8790
## 마지막 줄이 CLIENT ERRORS PASSED(실패면 종료 코드 1).

var _fails := 0


func _check(ok: bool, what: String, got := "") -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok or got == "" else " (" + got + ")"))
	if not ok:
		_fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var ce = root.get_node("ClientErrors")
	var c = ce.catcher
	var start: int = c.total
	push_error("client errors check boom")
	push_error("client errors check boom")  # 같은 곳 같은 오류 — 한 번만
	push_warning("client errors check warning")
	_check(c.total - start == 1 and c.pending.size() >= 1, "push_error caught once, warning skipped", "%d" % (c.total - start))
	var last: Dictionary = c.pending[-1]
	_check(str(last.message).contains("boom") and str(last.stack).contains("client_errors_check.gd"), "message and where", str(last))
	var api := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--api="):
			api = a.substr(6)
	if api != "":
		root.get_node("Net").api_base = api
		ce.flush()
		_check(ce.sent >= 1 and c.pending.is_empty(), "sent to the server", "%d" % ce.sent)
		var t := 0.0
		while ce._busy and t < 10.0:
			await process_frame
			t += 1.0 / 60.0
		_check(not ce._busy, "server answered", "")
	print("CLIENT ERRORS PASSED" if _fails == 0 else "CLIENT ERRORS FAILED")
	quit(1 if _fails else 0)

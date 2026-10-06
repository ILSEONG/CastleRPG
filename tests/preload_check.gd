extends Node
## 로딩 화면 미리 받기 체크(개발용): 로컬 서버(메모리 PGlite, ALLOW_TEST_HOOKS=1)에 게스트로 접속해 첫 로딩 화면이 걷힐 때까지 기다린 뒤,
## 창을 열기 전에 이미 창 데이터(출석·랭킹 셋·미션 표·친구)가 들어와 있는지와 워밍업 모델이 다 지워졌는지 본다. 렌더러가 있어야 한다(xvfb).
## 실행: cd server && PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=8790 node src/main.ts &
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/preload_check.tscn -- --api=http://127.0.0.1:8790 --device=/tmp/x/device.json
## 마지막 줄이 PRELOAD CHECK PASSED(실패면 종료 코드 1).

const PreloaderScript := preload("res://scripts/preloader.gd")

var _main
var _fails := 0


func _ready() -> void:
	Fever.save_path = ""
	Guild.save_path = ""
	var device := Net.arg_value("device")
	_check(Net.is_online() and device != "", "online mode with --api and --device", Net.api_base)
	if _fails > 0:
		return _finish()
	Net.device_path = device
	Net.auth_path = device.get_base_dir().path_join("auth.json")
	DirAccess.remove_absolute(device)
	Net.set_auth("guest")
	var t0 := Time.get_ticks_msec()
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_check(await _wait_until(func(): return PreloaderScript.done, 60.0), "loading screen finishes", "")
	print("loading screen took %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	await _frames(10)
	_check(Net.boot_state == "done", "window data fetched during loading (/v1/boot)", Net.boot_state)
	var menu = null
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == "res://scripts/side_menu.gd":
			menu = c
	_check(menu != null, "side menu exists", "")
	if menu == null:
		return _finish()
	_check((menu.windows.event.data.get("rewards", []) as Array).size() == 28, "attendance ready before opening", str(menu.windows.event.data.keys()))
	for b in ["stage", "power", "guild"]:
		_check(menu.windows.ranking.data.has(b), "ranking %s ready before opening" % b, str(menu.windows.ranking.data.keys()))
	_check(Missions._fetched and not Missions.defs.is_empty(), "mission table ready before opening", "")
	_check(str(Economy.friends.get("code", "")) != "", "friend list ready before opening", str(Economy.friends))
	_check(_main.get_node_or_null("PreloadWarmup") == null, "warm-up models cleaned up", "")
	var gets := 0
	for p in ["/v1/attendance", "/v1/missions", "/v1/friends", "/v1/ranking/stage"]:
		gets += int(Net.requested.get(p, 0))
	_check(gets == 0, "no per-window GETs during loading", str(Net.requested))
	_finish()


func _finish() -> void:
	if _fails > 0:
		print("PRELOAD CHECK FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("PRELOAD CHECK PASSED")
		get_tree().quit(0)


func _check(ok: bool, what: String, detail: String) -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + detail))
	if not ok:
		_fails += 1


func _wait_until(cond: Callable, timeout_sec: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while not cond.call():
		if Time.get_ticks_msec() > end:
			return false
		await get_tree().process_frame
	return true


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

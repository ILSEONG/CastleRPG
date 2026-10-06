extends Node
## 온라인 미션 체크 + 화면(개발용): 로컬 서버(메모리 PGlite, ALLOW_TEST_HOOKS=1)에 게스트로 접속해 오른쪽 아래 [메뉴] → [미션] 창을 연다.
## 몬스터 300마리 처치 → 빨간 점 → 일일 [받기](서버 POST /v1/mission/claim) → 같은 날 받은 기록 → 반복 1000마리 받기(목표 1500) → 주간·반복 탭 화면.
## 실행: cd server && PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=8790 node src/main.ts &
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/missions_online.tscn -- --api=http://127.0.0.1:8790 --device=/tmp/x/device.json --out=/tmp/missions.png
## 마지막 줄이 MISSIONS ONLINE PASSED(실패면 종료 코드 1).

var _main
var _menu
var _panel
var _shots: Array = []
var _fails := 0
var _resp_done := false


func _ready() -> void:
	Fever.save_path = ""
	Guild.save_path = ""
	get_window().size = Vector2i(360, 640)
	var device := Net.arg_value("device")
	_check(Net.is_online() and device != "" and Missions.net != null, "online mode with --api and --device", Net.api_base)
	if _fails > 0:
		return _finish()
	Net.device_path = device
	Net.auth_path = device.get_base_dir().path_join("auth.json")
	DirAccess.remove_absolute(device)
	Net.set_auth("guest")
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_check(await _wait_until(func(): return Net.ready_once and _main.camera != null, 30.0), "world built after connecting", "")
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == "res://scripts/side_menu.gd":
			_menu = c
	_check(_menu != null and _menu.buttons.has("mission"), "bottom-right menu has 미션", "")
	if _fails > 0:
		return _finish()
	_panel = _menu.windows.mission
	_check(await _wait_until(func(): return not Economy.server_missions.is_empty(), 10.0), "server mission record arrives with the player", "")
	_check(not _menu.dots().has("mission"), "no mission dot at the start", str(_menu.dots()))
	Missions.note("kill", 1000)
	await _frames(4)
	_check(_menu.dots().has("mission") and _menu.dots().has("toggle"), "red dot on 미션 and 메뉴 when a mission is done", str(_menu.dots()))
	_menu.toggle.pressed.emit()
	await _frames(20)
	await _snap()  # 1. 메뉴 펼침(빨간 점)
	_menu.buttons.mission.pressed.emit()
	_check(_panel.is_open(), "미션 opens the mission sheet", "")
	await _frames(10)
	await _snap()  # 2. 일일
	_check(_panel.buttons.has("claim:d_kill"), "daily kill shows 받기", str(_panel.buttons.keys()))
	var gold := Economy.gold
	_panel.buttons["claim:d_kill"].pressed.emit()
	_check(await _wait_until(func(): return Missions.waiting == "", 10.0), "claim answered", "")
	_check("d_kill" in Economy.server_missions.get("d", []) and Economy.gold >= gold + 3000, "server recorded the claim, gold +3000",
		"%s %d -> %d" % [str(Economy.server_missions), gold, Economy.gold])
	_check(not Missions.claim("d_kill"), "cannot claim twice", "")
	await _frames(20)
	await _snap()  # 3. 받은 뒤
	_panel._pick("weekly")
	await _frames(10)
	await _snap()  # 4. 주간
	_panel._pick("repeat")
	await _frames(10)
	_check(_panel.buttons.has("claim:r_kill"), "repeat kill 1000 shows 받기", "")
	_panel.buttons["claim:r_kill"].pressed.emit()
	_check(await _wait_until(func(): return Missions.waiting == "", 10.0), "repeat claim answered", "")
	var rk: Dictionary = Missions.find("r_kill")
	_check(Missions.times("r_kill") == 1 and Missions.target(rk) == 1500 and Missions.progress(rk) == 0, "repeat target grows to 1500",
		"%d %d %d" % [Missions.times("r_kill"), Missions.target(rk), Missions.progress(rk)])
	await _frames(20)
	await _snap()  # 5. 반복
	_sheet()
	_finish()


func _finish() -> void:
	if _fails > 0:
		print("MISSIONS ONLINE FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("MISSIONS ONLINE PASSED")
		get_tree().quit(0)


func _check(ok: bool, what: String, detail: String) -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + detail))
	if not ok:
		_fails += 1


func _request(path: String, body) -> void:
	_resp_done = false
	Net.send("POST", path, body, func(d):
		Economy.apply_server(d)
		_resp_done = true, func(): _resp_done = true)
	await _wait_until(func(): return _resp_done, 10.0)


func _sheet() -> void:
	var out := "/tmp/missions_online.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var w: int = _shots[0].get_width() / 2
	var h: int = _shots[0].get_height() / 2
	var sheet := Image.create(w * _shots.size(), h, false, Image.FORMAT_RGB8)
	for i in _shots.size():
		var img: Image = _shots[i]
		img.convert(Image.FORMAT_RGB8)
		img.save_png(out.get_basename() + "_%d.png" % (i + 1))
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	sheet.save_png(out)
	print("saved ", out, " shots=", _shots.size())


func _snap() -> void:
	await _frames(8)
	_shots.append(get_viewport().get_texture().get_image())


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

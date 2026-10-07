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
	await _events({"kill": 1000})  # 진행은 서버가 센 수(통합 테스트 2026-10-07) — 테스트 훅으로 채운다
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
	_check(Missions.waiting == "d_kill" and Missions.is_claimed(Missions.find("d_kill")) and Economy.gold >= gold + 3000,
		"claim shows at once, before the reply (claimed, gold +3000)", "waiting=%s gold %d -> %d" % [Missions.waiting, gold, Economy.gold])
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
	# 연달아 받기: 응답을 기다리지 않고 두 번(1500 → 2000), 서버는 보낸 순서대로 확인한다
	await _events({"kill": 3500})
	var d0 := Economy.diamonds
	var g1 := Economy.gold
	_check(Missions.claim("r_kill") and Missions.claim("r_kill") and Missions.times("r_kill") == 3 and Economy.gold >= g1 + 10000,
		"two repeat claims in a row show at once", "times=%d gold %d -> %d" % [Missions.times("r_kill"), g1, Economy.gold])
	_check(await _wait_until(func(): return Missions.waiting == "", 10.0) and Missions.times("r_kill") == 3 and int(Economy.server_missions.get("r", {}).get("r_kill", 0)) == 3,
		"server confirms both chained claims", str(Economy.server_missions))
	_check(Economy.diamonds == d0, "no stray reward", "")
	await _frames(20)
	await _snap()  # 5. 반복
	# 실제 탭(누름 → 처치가 계속 들어오는 0.6초 → 뗌): 누르는 동안 창이 버튼을 다시 만들면 탭이 사라진다(2026-10-06 버그)
	await _events({"hero_level": 20, "growth": 20})
	await _frames(30)
	_check(_panel.buttons.has("claim:r_hero") and _panel.buttons.has("claim:r_growth"), "two repeat missions ready", str(_panel.buttons.keys()))
	for id in ["r_hero", "r_growth"]:
		var b: Button = _panel.buttons["claim:" + id]
		var at: Vector2 = b.get_viewport().get_screen_transform() * b.get_global_rect().get_center()  # 창 좌표(720×1280 → 창 크기)
		_tap(at, true)
		for i in 36:
			Missions.note("kill", 1)
			await get_tree().process_frame
		_tap(at, false)
		_check(await _wait_until(func(): return Missions.waiting == "" and Missions.times(id) == 1, 10.0), "a real tap during combat claims " + id,
			"times=%d" % Missions.times(id))
		await _frames(10)
	_sheet()
	_finish()


func _tap(at: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = at
	ev.global_position = at
	Input.parse_input_event(ev)
	await get_tree().process_frame


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


func _events(ev: Dictionary) -> void:
	await _request("/v1/test/events", {"events": ev})
	Missions.changed.emit()


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

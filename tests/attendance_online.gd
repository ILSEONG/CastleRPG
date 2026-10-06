extends Node
## 온라인 출석 이벤트 체크 + 화면(개발용): 로컬 서버(메모리 PGlite, ALLOW_TEST_HOOKS=1)에 게스트로 접속해 오른쪽 아래 [메뉴] → [이벤트]로
## 28일 출석 창을 연다. 1일차 받기 → 같은 날 다시 못 받음 → (테스트 훅으로 6일 받은 상태) 7일차 받기(SR 장비 상자) → 27일 받은 상태의 28일차(SSR 영웅).
## 실행: cd server && PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=8790 node src/main.ts &
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/attendance_online.tscn -- --api=http://127.0.0.1:8790 --device=/tmp/x/device.json --out=/tmp/attendance.png
## 마지막 줄이 ATTENDANCE ONLINE PASSED(실패면 종료 코드 1).

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
	_check(Net.is_online() and device != "", "online mode with --api and --device", Net.api_base)
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
	_check(_menu != null, "bottom-right menu exists", "")
	if _fails > 0:
		return _finish()
	_panel = _menu.windows.event
	_check(_menu.has_dot(), "menu shows a red dot (reward ready)", str(Economy.attendance))
	await _frames(20)
	await _snap()  # 1. 빨간 점
	_menu.toggle.pressed.emit()
	_menu.buttons.event.pressed.emit()
	_check(_panel.is_open(), "이벤트 opens the attendance window", "")
	_check(await _loaded(), "attendance table loads", "")
	_check(_panel.cells.size() == 28 and _panel.can_claim(), "28 cells, day 1 claimable", str(_panel.data.get("n")))
	await _snap()  # 2. 첫날
	var gold := Economy.gold
	_panel.claim_button.pressed.emit()
	_check(await _wait_until(func(): return not _panel.claiming, 10.0), "claim answered", "")
	_check(_panel.claimed_n() == 1 and not _panel.can_claim() and Economy.gold > gold, "day 1 claimed, gold went up", "%d -> %d" % [gold, Economy.gold])
	_check(not _menu.has_dot(), "red dot gone after claiming", "")
	await _frames(10)
	await _snap()  # 3. 받은 뒤

	await _request("/v1/test/attendance", {"n": 6})
	_panel.fetch()
	_check(await _loaded(), "reload at 6 days", "")
	var items := Economy.items().size()
	_panel.claim_button.pressed.emit()
	_check(await _wait_until(func(): return not _panel.claiming, 10.0), "day 7 answered", "")
	_check(_panel.claimed_n() == 7 and Economy.items().size() == items + 1, "day 7 gives one equipment piece", "%d -> %d" % [items, Economy.items().size()])
	await _frames(10)
	await _snap()  # 4. 7일차

	await _request("/v1/test/attendance", {"n": 27})
	_panel.fetch()
	_check(await _loaded(), "reload at 27 days", "")
	_panel.selected = 27
	_panel._update_info()
	await _frames(30)
	await _snap()  # 5. 28일차 직전
	_panel.claim_button.pressed.emit()
	_check(await _wait_until(func(): return not _panel.claiming, 10.0), "day 28 answered", "")
	_check(Economy.heroes.has("arteon"), "day 28 gives Arteon", str(Economy.heroes.keys()))
	_check(_panel.claim_button.text == "모두 받았어요", "all done", _panel.claim_button.text)
	await _frames(10)
	await _snap()  # 6. 끝
	_sheet()
	_finish()


func _loaded() -> bool:
	var ok: bool = await _wait_until(func(): return not _panel.loading and not _panel.data.is_empty(), 10.0)
	await _frames(6)
	return ok


func _finish() -> void:
	if _fails > 0:
		print("ATTENDANCE ONLINE FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("ATTENDANCE ONLINE PASSED")
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
	var out := "/tmp/attendance_online.png"
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

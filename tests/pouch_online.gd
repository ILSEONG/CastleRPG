extends Node
## 온라인 방치 주머니 체크 + 화면(개발용): 로컬 서버(메모리 PGlite, ALLOW_TEST_HOOKS=1)에 게스트로 접속해 출석 1일차(골드 + 골드 주머니 30분)를 받고,
## 오른쪽 아래 [메뉴] → [가방]에서 주머니를 연다(서버가 준 값 = 앱이 미리 보여 준 값, 골드가 그만큼 오른다). 27일 받은 상태의 출석 창(주머니 칸)도 찍는다.
## 실행: cd server && PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=8790 node src/main.ts &
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/pouch_online.tscn -- --api=http://127.0.0.1:8790 --device=/tmp/x/device.json --out=/tmp/pouch.png
## 마지막 줄이 POUCH ONLINE PASSED(실패면 종료 코드 1).

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
	_check(_menu != null and _menu.windows.has("bag"), "bottom-right menu has 가방", "")
	if _fails > 0:
		return _finish()
	var ev = _menu.windows.event
	_menu.toggle.pressed.emit()
	await _frames(20)
	await _snap()  # 1. 펼친 메뉴([가방])
	_menu.buttons.event.pressed.emit()
	_check(await _wait_until(func(): return not ev.loading and not ev.data.is_empty(), 10.0), "attendance loads", "")
	ev.claim_button.pressed.emit()
	_check(await _wait_until(func(): return not ev.claiming, 10.0), "day 1 claimed", "")
	_check(Economy.pouch_count("gold_30") == 1, "day 1 gives a 30-minute gold pouch", str(Economy.pouches))
	ev.close()
	_panel = _menu.windows.bag
	_menu.toggle.pressed.emit()
	_menu.buttons.bag.pressed.emit()
	_check(_panel.is_open(), "가방 opens", "")
	await _frames(10)
	_check(_panel.buttons.has("open:gold_30"), "gold pouch row with 열기", str(_panel.buttons.keys()))
	await _snap()  # 2. 가방
	var preview: int = Economy.pouch_value("gold_30", GameState.stage).gold_tenths
	var gold := Economy.gold_tenths
	var opened := {}
	Economy.pouch_opened.connect(func(o): opened.merge(o), CONNECT_ONE_SHOT)  # 람다는 지역 변수를 값으로 잡는다 — 사전을 채운다
	_panel.buttons["open:gold_30"].pressed.emit()
	_check(await _wait_until(func(): return not opened.is_empty(), 10.0), "open answered", "")
	_check(int(opened.get("gold_tenths", -1)) == preview and preview > 0, "server value = app preview", "%s vs %d" % [str(opened), preview])
	_check(Economy.gold_tenths >= gold + preview, "gold went up by the pouch", "%d -> %d (+%d)" % [gold, Economy.gold_tenths, preview])
	_check(Economy.pouch_count("gold_30") == 0, "pouch used up", str(Economy.pouches))
	await _frames(10)
	await _snap()  # 3. 연 뒤(알림, 빈 가방)
	_panel.close()

	await _request("/v1/test/attendance", {"n": 26})
	_menu.toggle.pressed.emit()
	_menu.buttons.event.pressed.emit()
	ev.fetch()
	_check(await _wait_until(func(): return not ev.loading and not ev.data.is_empty(), 10.0), "attendance reload at 26", "")
	ev.selected = 26
	ev._update_info()
	await _frames(20)
	await _snap()  # 4. 출석 창 주머니 칸(27일차 선택)
	ev.claim_button.pressed.emit()
	_check(await _wait_until(func(): return not ev.claiming, 10.0), "day 27 claimed", "")
	_check(Economy.pouch_count("gold_360") == 1 and Economy.pouch_count("res_360") == 1, "day 27 gives both 6-hour pouches", str(Economy.pouches))
	ev.close()
	_menu.toggle.pressed.emit()
	_menu.buttons.bag.pressed.emit()
	await _frames(10)
	await _snap()  # 5. 가방(6시간 주머니 둘 — 자원 건물이 아직 공터면 자원 주머니는 잠김)
	if not Economy.unbuilt.is_empty():
		_check(_panel.buttons["open:res_360"].disabled, "resource pouch locked while resource buildings are unbuilt", "")
	var gold2 := Economy.gold_tenths
	opened.clear()
	Economy.pouch_opened.connect(func(o): opened.merge(o), CONNECT_ONE_SHOT)  # 람다는 지역 변수를 값으로 잡는다 — 사전을 채운다
	_panel.buttons["open:gold_360"].pressed.emit()
	_check(await _wait_until(func(): return not opened.is_empty(), 10.0), "6-hour gold pouch answered", "")
	_check(int(opened.get("gold_tenths", 0)) > 0 and Economy.gold_tenths >= gold2 + int(opened.gold_tenths), "gold went up by the 6-hour pouch", str(opened))
	await _frames(10)
	await _snap()  # 6. 골드 주머니 연 뒤
	_sheet()
	_finish()


func _finish() -> void:
	if _fails > 0:
		print("POUCH ONLINE FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("POUCH ONLINE PASSED")
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
	var out := "/tmp/pouch_online.png"
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

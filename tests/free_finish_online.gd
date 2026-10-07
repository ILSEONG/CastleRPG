extends Node
## 온라인 무료 즉시 완료 체크 + 화면(사용자 2026-10-06): 로컬 서버(메모리 PGlite, ALLOW_TEST_HOOKS=1, tutorial_new_players=0)에 게스트로 접속해
## 남은 5분 이하인 건설·훈련·연구를 [무료 즉시 완료]로 끝낸다 — 누르는 즉시 끝난 것으로 보이고, 서버 응답 뒤에도 그대로(되돌림 알림 없음).
## 실행: cd server && PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=8790 node src/main.ts &
##   curl -XPOST localhost:8790/v1/test/config -H 'content-type: application/json' -d '{"key":"tutorial_new_players","value":"0"}'
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/free_finish_online.tscn -- --api=http://127.0.0.1:8790 --device=/tmp/x/device.json --out=/tmp/free.png
## 마지막 줄이 FREE FINISH ONLINE PASSED(실패면 종료 코드 1).

const EconomyScript := preload("res://scripts/economy.gd")

var _main
var _shots: Array = []
var _fails := 0
var _resp_done := false
var _notes: Array = []


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
	if _fails > 0:
		return _finish()
	Economy.notice.connect(func(s): _notes.append(s))
	_check(await _wait_until(func(): return Net.up, 15.0), "connected", "")
	await _frames(30)
	await _request("/v1/test/age", {"minutes": 720})
	for b in ["lumber", "quarry", "farm"]:
		Economy.collect(b, Economy.time_now())
		await _frames(10)
	_check(await _wait_until(func(): return int(Economy.res.get("wood", 0)) > 1000 and int(Economy.res.get("food", 0)) > 1000 and int(Economy.res.get("stone", 0)) > 1000, 10.0),
		"resources collected", str(Economy.res))
	var panel = _main._picker.building_panel

	# 1) 건설: 성채 1 → 2(60초) — 바로 [무료 즉시 완료]
	var keep := Economy.building_level("keep")
	panel.open_building("keep")
	panel.upgrade_button.pressed.emit()
	_check(await _wait_until(func(): return not Economy._waiting.has("build"), 10.0) and Economy.is_building("keep"), "keep upgrade started", str(Economy.build))
	await _frames(5)
	_check(panel.free_build_button.visible, "free finish button shows while 60 s are left", "")
	await _snap()
	panel.free_build_button.pressed.emit()
	_check(Economy.build.is_empty() and Economy.building_level("keep") == keep + 1, "keep is done the moment the button is pressed", str([Economy.build, Economy.building_level("keep")]))
	_check(await _wait_until(func(): return not Economy._waiting.has("build"), 10.0), "server answered the free build finish", "")
	_check(Economy.build.is_empty() and Economy.building_level("keep") == keep + 1 and not _notes.has(EconomyScript.ROLLBACK_TEXT), "server agrees (no rollback)", str(_notes))
	await _snap()
	panel.close()

	# 2) 훈련: 막사 1마리(3시간) → 2시간 56분 당겨 4분 남김 → [무료 즉시 완료]
	var inf := int(Economy.soldier_counts().get("infantry:1", 0))
	panel.open_building("barracks")
	await _frames(3)
	panel.train_button.pressed.emit()
	_check(await _wait_until(func(): return Economy.training("barracks").count > 0 and not Economy.training_waiting("barracks", "train"), 10.0), "training started", "")
	await _frames(5)
	_check(not panel.free_train_button.visible, "no free finish with 3 h left", "")
	await _request("/v1/test/age", {"minutes": 176})
	await _frames(70)
	_check(panel.free_train_button.visible, "free finish button shows with 4 min left", str(Economy.training("barracks")))
	await _snap()
	panel.free_train_button.pressed.emit()
	_check(int(Economy.soldier_counts().get("infantry:1", 0)) == inf + 1 and Economy.training("barracks").count == 0, "soldier arrives the moment the button is pressed", str(Economy.soldier_counts()))
	_check(await _wait_until(func(): return not Economy.training_waiting("barracks", "collect"), 10.0), "server answered the free training finish", "")
	_check(int(Economy.soldier_counts().get("infantry:1", 0)) == inf + 1 and not _notes.has(EconomyScript.ROLLBACK_TEXT), "server agrees (no rollback)", str(_notes))
	panel.close()

	# 3) 연구: 벌목술 Lv 1(60초) — 다이아 0으로 바로
	var dia := Economy.diamonds
	_check(Economy.start_research("wood_tech"), "research started", "")
	_check(await _wait_until(func(): return Economy._hold == 0 and not Economy.research_waiting() and not Economy.research_current.is_empty(), 10.0), "research running", "")
	panel.research.open()
	await _frames(10)
	_check(Economy.research_dia_cost(Economy.time_now()) == 0 and panel.research.dia_button.text == "무료 즉시 완료", "research shows 무료 즉시 완료", panel.research.dia_button.text)
	await _snap()
	panel.research.dia_button.pressed.emit()
	_check(Economy.research_level("wood_tech") == 1 and Economy.research_current.is_empty(), "research is done the moment the button is pressed", "")
	_check(await _wait_until(func(): return Economy._hold == 0 and not Economy.research_waiting(), 10.0), "server answered the free research finish", "")
	_check(Economy.research_level("wood_tech") == 1 and Economy.diamonds == dia and not _notes.has(EconomyScript.ROLLBACK_TEXT), "server agrees, no diamonds spent", str([Economy.diamonds, dia, _notes]))
	await _frames(10)
	await _snap()
	_sheet()
	_finish()


func _finish() -> void:
	if _fails > 0:
		print("FREE FINISH ONLINE FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("FREE FINISH ONLINE PASSED")
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
	var out := "/tmp/free_finish_online.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	if _shots.is_empty():
		return
	var w: int = _shots[0].get_width() / 2
	var h: int = _shots[0].get_height() / 2
	var sheet := Image.create(w * _shots.size(), h, false, Image.FORMAT_RGB8)
	for i in _shots.size():
		var img: Image = _shots[i]
		img.convert(Image.FORMAT_RGB8)
		img.save_png(out.get_basename() + "_%d.png" % (i + 1))
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(w * i, 0))
	sheet.save_png(out)


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

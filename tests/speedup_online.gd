extends Node
## 온라인 가속 아이템·두 번째 일꾼 체크 + 화면(2026-10-13 라오킹식 건설): 로컬 서버(메모리 PGlite, ALLOW_TEST_HOOKS=1, tutorial_new_players=0)에 게스트로 접속해
## 건물 창 [가속] → 목록 [1개]로 건설 시간을 당기고, 가방의 일꾼 고용권 [사용]으로 두 번째 일꾼을 불러 두 건물을 함께 짓는다(서버도 같은 상태, 되돌림 없음).
## 실행: cd server && PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=8790 node src/main.ts &
##   curl -XPOST localhost:8790/v1/test/config -H 'content-type: application/json' -d '{"key":"tutorial_new_players","value":"0"}'
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/speedup_online.tscn -- --api=http://127.0.0.1:8790 --device=/tmp/x/device.json --out=/tmp/speedup.png
## 마지막 줄이 SPEEDUP ONLINE PASSED(실패면 종료 코드 1).

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
	await _request("/v1/test/levels", {"levels": {"keep": 10, "gate": 10, "barracks": 10, "lumber": 9, "quarry": 9}, "res": {"wood": 50000000, "stone": 50000000, "food": 50000000}})
	await _frames(30)  # 성채 단계가 바뀌면 main이 월드를 다시 만든다 — 새 main을 다시 잡는다
	for c in get_children():
		if "_picker" in c and not c.is_queued_for_deletion():
			_main = c
	_check(await _wait_until(func(): return is_instance_valid(_main) and _main.camera != null and _main._picker != null, 30.0), "world rebuilt at keep 10", "")
	await _request("/v1/test/speedups", {"items": {"build_60": 3, "any_5": 2, "builder_1440": 1}})
	_check(Economy.building_level("keep") == 10 and Economy.speedup_count("build_60") == 3 and Economy.speedup_count("builder_1440") == 1, "levels and speed-ups from the server", str(Economy.speedups))
	var panel = _main._picker.building_panel

	# 1) 벌목장 9 → 10 — [가속 ▼] → 건설 가속 1시간 [1개]
	panel.open_building("lumber")
	panel.upgrade_button.pressed.emit()
	_check(await _wait_until(func(): return not Economy._waiting.has("build") and Economy.is_building("lumber"), 10.0), "lumber upgrade started", str(Economy.build))
	await _frames(5)
	var fin0 := float(Economy.build_job("lumber").finish)
	_check(panel.speedup_button.visible and not panel.free_build_button.visible and not panel.speedups.visible, "[가속] shows while building (list folded)", "")
	panel.speedup_button.pressed.emit()
	await _frames(3)
	var rows: Array = panel.speedups.get_children().filter(func(r): return not r.is_queued_for_deletion())
	var names: Array = rows.map(func(r): return r.get_child(0).text if r is HBoxContainer else r.text)
	_check(panel.speedups.visible and names == ["범용 가속 5분 ×2", "건설 가속 1시간 ×3"], "the list shows build + universal items, short first", str(names))
	await _snap()
	var one: Button = rows[1].get_child(1)
	one.pressed.emit()
	_check(Economy.speedup_count("build_60") == 2 and absf(float(Economy.build_job("lumber").finish) - (fin0 - 3600.0)) < 1.0, "[1개] pulls the finish in by 1 h at once", str(Economy.build_job("lumber")))
	_check(await _wait_until(func(): return Economy._hold == 0, 10.0), "server answered the speed-up", "")
	_check(Economy.speedup_count("build_60") == 2 and absf(float(Economy.build_job("lumber").finish) - (fin0 - 3600.0)) < 2.0 and not _notes.has(EconomyScript.SPEEDUP_FAIL_TEXT),
		"server agrees (no rollback)", str([Economy.build, _notes]))
	panel.close()

	# 2) 가방: 일꾼 고용권 [사용] → 두 번째 일꾼 1일
	var bag
	for c in _main.get_children():
		if c.get_script() == preload("res://scripts/pouch_panel.gd"):
			bag = c
	bag.open()
	await _frames(5)
	_check(bag.buttons.has("use:builder_1440") and not bag.buttons.has("use:build_60"), "the bag lists speed-ups; only the builder pass has [사용]", str(bag.buttons.keys()))
	await _snap()
	bag.buttons["use:builder_1440"].pressed.emit()
	_check(Economy.builder2_active(Economy.time_now()) and Economy.speedup_count("builder_1440") == 0, "the second builder is hired at once", str(Economy.builder2_until))
	_check(await _wait_until(func(): return Economy._hold == 0, 10.0) and absf(Economy.builder2_until - (Economy.time_now() + 86400.0)) < 10.0, "server agrees: 1 day", str(Economy.builder2_until))
	bag.close()

	# 3) 두 번째 일꾼으로 채석장을 함께 짓는다
	panel.open_building("quarry")
	await _frames(3)
	_check(not panel.upgrade_button.disabled, "the quarry can start while the lumber mill builds", panel.reason_label.text)
	panel.upgrade_button.pressed.emit()
	_check(await _wait_until(func(): return not Economy._waiting.has("build") and Economy._hold == 0, 10.0) and Economy.is_building("quarry") and Economy.is_building("lumber")
		and Economy.build_jobs().size() == 2, "two buildings build at once", str(Economy.build_jobs()))
	await _frames(10)
	await _snap()
	panel.close()
	await _frames(10)
	await _snap()
	_sheet()
	_finish()


func _finish() -> void:
	if _fails > 0:
		print("SPEEDUP ONLINE FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("SPEEDUP ONLINE PASSED")
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
	var out := "/tmp/speedup_online.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	if _shots.is_empty() or _shots[0] == null:
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


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait_until(cond: Callable, timeout_sec: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while not cond.call():
		if Time.get_ticks_msec() > end:
			return false
		await get_tree().process_frame
	return true

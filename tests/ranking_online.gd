extends Node
## 온라인 랭킹 체크 + 화면(개발용): 로컬 서버(메모리 PGlite, ALLOW_TEST_HOOKS=1)에 게스트로 접속해 HUD 트로피 버튼 → 랭킹 시트의
## [스테이지][전투력][길드]를 차례로 연다. 길드 보드가 비지 않게 길드 창을 한 번 받아(시스템 길드 5개) 하나에 가입한다.
## 다른 플레이어가 있으면 같이 보인다(서버를 띄운 뒤 curl로 게스트 몇 명을 만들어 /v1/test/stage로 라운드를 올려 두면 된다).
## 실행: cd server && PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=8790 node src/main.ts &
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/ranking_online.tscn -- --api=http://127.0.0.1:8790 --device=/tmp/x/device.json --out=/tmp/ranking.png
## 마지막 줄이 RANKING ONLINE PASSED(실패면 종료 코드 1).

var _main
var _button
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
		if c.get_script() != null and c.get_script().resource_path == "res://scripts/ranking_button.gd":
			_button = c
	_check(_button != null and _button.visible, "trophy button on the HUD (online)", "")
	if _fails > 0:
		return _finish()
	_panel = _button.panel

	await _request("/v1/test/stage", {"stage": 37})
	Guild.fetch()
	_check(await _wait_until(func(): return Guild.recommendations().size() == 5, 10.0), "system guilds exist", "")
	Guild.join(Guild.recommendations()[0])
	_check(await _wait_until(func(): return Guild.joined() and not Guild.busy, 10.0), "join a guild", "")
	await _frames(30)
	await _snap()  # 1. HUD 버튼

	_button.button.pressed.emit()
	_check(_panel.is_open(), "button opens the ranking sheet", "")
	_check(await _loaded("stage"), "stage board loads", "")
	var me: Dictionary = _panel.data.stage.get("me", {})
	_check(int(me.get("value", 0)) == 37 and str(me.get("guild", "")) == str(Guild.guild.get("name", "")), "my stage row = 2-12 with my guild", str(me))
	await _snap()  # 2. 스테이지

	_panel._pick("power")
	_check(await _loaded("power"), "power board loads", "")
	_check(_panel.data.power.get("me") is Dictionary, "I have power from starter heroes", "")
	await _snap()  # 3. 전투력

	_panel._pick("guild")
	_check(await _loaded("guild"), "guild board loads", "")
	var g: Dictionary = _panel.data.guild
	_check(int(g.get("total", 0)) >= 5, "guild board lists the system guilds", str(g.get("total")))
	_check(g.get("me") is Dictionary and str(g.me.name) == str(Guild.guild.get("name", "")), "my guild is marked", str(g.get("me")))
	await _snap()  # 4. 길드
	_sheet()
	_finish()


func _loaded(b: String) -> bool:
	var ok: bool = await _wait_until(func(): return _panel.data.has(b) and not _panel._loading.get(b, false), 10.0)
	await _frames(6)
	return ok


func _finish() -> void:
	if _fails > 0:
		print("RANKING ONLINE FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("RANKING ONLINE PASSED")
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
	var out := "/tmp/ranking_online.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var w: int = _shots[0].get_width() / 2
	var h: int = _shots[0].get_height() / 2
	var sheet := Image.create(w * _shots.size(), h, false, Image.FORMAT_RGB8)
	for i in _shots.size():
		var img: Image = _shots[i]
		img.convert(Image.FORMAT_RGB8)
		img.save_png(out.get_basename() + "_%d.png" % (i + 1))  # 한 장씩(원래 크기)
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

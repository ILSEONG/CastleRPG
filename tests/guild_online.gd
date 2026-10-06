extends Node
## 온라인 길드 체크 + 화면(개발용): 로컬 서버(메모리 PGlite, ALLOW_TEST_HOOKS=1)에 게스트로 접속해 길드 탭을 실제로 쓴다 —
## 잠김 → (테스트 훅으로 stage 11) 추천 5개 → 가입 → 출석 → 골드 기부 → 보스 도전 → 상점·길드원 → 탈퇴 → 창설(500,000골드).
## 실행: cd server && PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=8790 node src/main.ts &
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/guild_online.tscn -- --api=http://127.0.0.1:8790 --device=/tmp/x/device.json --out=/tmp/guild_online.png
## 마지막 줄이 GUILD ONLINE PASSED(실패면 종료 코드 1).

var _main
var _tabs
var _panel
var _shots: Array = []
var _fails := 0
var _resp_done := false
var _boss = null


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
	await _frames(10)
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == "res://scripts/tab_bar.gd":
			_tabs = c
	_panel = _tabs.windows.guild
	Guild.boss_done.connect(func(r): _boss = r)

	_tabs.press("guild")
	_check(await _wait_until(func(): return not Guild.remote.is_empty(), 10.0) and not Guild.is_unlocked(), "new player: guild is locked", str(Guild.remote))
	await _snap()

	await _request("/v1/test/stage", {"stage": 11})
	Guild.fetch()
	_check(await _wait_until(func(): return Guild.is_unlocked(), 10.0), "stage 11 unlocks the guild", "")
	var recs: Array = Guild.recommendations()
	_check(recs.size() == 5, "5 recommended guilds", str(recs.size()))
	_panel._rebuild()
	await _snap()

	Guild.join(recs[0])
	_check(await _wait_until(func(): return Guild.joined() and not Guild.busy, 10.0), "join a recommended guild", "")
	_check(Guild.members_now().size() >= 12, "virtual members are listed", str(Guild.members_now().size()))
	var gold0: int = Economy.gold
	Guild.attend()
	_check(await _wait_until(func(): return bool(Guild.me.get("attended", false)) and not Guild.busy, 10.0), "attend", "")
	_check(Guild.coins == 30 and Economy.gold == gold0 + 3000, "attendance pays 3000 gold + 30 coins", "coins=%d gold=%d→%d" % [Guild.coins, gold0, Economy.gold])
	await _request("/v1/test/grant_gold", {"amount": 20000})
	Guild.donate("gold")
	_check(await _wait_until(func(): return Guild.donations_left("gold") == 2 and not Guild.busy, 10.0), "gold donation", "")
	_panel._rebuild()
	await _snap()

	_panel.tab = "boss"
	_panel._rebuild()
	await _snap()
	_panel._start_fight()
	_check(await _wait_until(func(): return _boss != null, 10.0) and float(_boss.get("dmg", 0)) > 0.0, "boss fight returns damage and grade", str(_boss))
	await _frames(70)
	await _snap()
	if not _panel._fight.is_empty():
		_panel._fight.t = 99.0
		await _snap()
		_panel._end_fight()
	_check(int(Guild.me.get("boss_tries", 0)) == 1, "one boss try used", str(Guild.me))

	_panel.tab = "shop"
	_panel._rebuild()
	await _snap()
	_panel.tab = "members"
	_panel._rebuild()
	await _snap()
	_check(Guild.attend_count() >= 1, "my attendance counts toward the guild", str(Guild.attend_count()))

	Guild.leave()
	_check(await _wait_until(func(): return not Guild.joined() and not Guild.busy, 10.0), "leave", "")
	await _request("/v1/test/grant_gold", {"amount": Guild.CREATE_GOLD})
	Guild.create("성벽수호단", 3)
	_check(await _wait_until(func(): return Guild.joined() and not Guild.busy, 10.0) and bool(Guild.guild.get("mine", false)), "create a guild for 500,000 gold", str(Guild.guild.get("name", "")))
	_panel.tab = "home"
	_panel._rebuild()
	await _snap()
	_sheet()
	_finish()


func _finish() -> void:
	if _fails > 0:
		print("GUILD ONLINE FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("GUILD ONLINE PASSED")
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
	var out := "/tmp/guild_online.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var w: int = _shots[0].get_width() / 2
	var h: int = _shots[0].get_height() / 2
	var sheet := Image.create(w * 4, h * 2, false, Image.FORMAT_RGB8)
	for i in mini(_shots.size(), 8):
		var img: Image = _shots[i]
		img.convert(Image.FORMAT_RGB8)
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % 4) * w, (i / 4) * h))
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

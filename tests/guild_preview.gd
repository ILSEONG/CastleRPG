extends Node
## 길드 화면 미리보기(개발용, 화면 필요): 로컬 서버(메모리 PGlite, ALLOW_TEST_HOOKS=1)에 게스트로 접속해 실제 플레이어가 보는 길드 화면을 한 장씩 찍는다 —
## 잠김 → 추천 길드·창설 → 홈(출석·기부) → 보스 탭 → 드래곤 전투(시작·교전·결과) → 상점 → 길드원 → 길드전 탭(공성 시각 대기·수비 편성)
## → (테스트 훅 /v1/test/war_now로 공성 시각을 지금으로) 공성 열림 → 공성 전투(시작·교전·성문) → 전투 뒤 탭.
## 실행: cd server && PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=8790 node src/main.ts &
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/guild_preview.tscn -- --api=http://127.0.0.1:8790 --device=/tmp/x/device.json --out=/tmp/guild_preview
## 코드·숫자는 건드리지 않는다. 파일은 <out>_NN_이름.png.

const HEROES := ["arteon", "ignis", "sylvana", "grom", "baldur", "lumina", "kyle", "nev"]

var _main
var _tabs
var _panel
var _out := "/tmp/guild_preview"
var _n := 0
var _resp_done := false


func _ready() -> void:
	Fever.save_path = ""
	Guild.save_path = ""
	GuildWar.save_path = ""
	if Net.arg_value("out") != "":
		_out = Net.arg_value("out")
	var device := Net.arg_value("device")
	Net.device_path = device
	Net.auth_path = device.get_base_dir().path_join("auth.json")
	DirAccess.remove_absolute(device)
	Net.set_auth("guest")
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _wait_until(func(): return Net.ready_once and _main.camera != null, 30.0)
	await _frames(240)
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == "res://scripts/side_menu.gd":  # 길드는 오른쪽 아래 메뉴
			_tabs = c
	_panel = _tabs.windows.guild

	_open_guild()
	await _wait_until(func(): return not Guild.remote.is_empty(), 10.0)
	await _snap("locked")

	await _request("/v1/test/stage", {"stage": 23})
	await _request("/v1/test/grant_gold", {"amount": 80000})
	await _request("/v1/test/grant_diamonds", {"amount": 500})
	for id in HEROES:
		await _request("/v1/test/grant_hero", {"hero_id": id})
	Guild.fetch()
	await _wait_until(func(): return Guild.is_unlocked() and not Guild.busy, 10.0)
	_panel._rebuild()
	await _snap("join_list")

	var recs: Array = Guild.recommendations()
	Guild.join(recs[0])
	await _wait_until(func(): return Guild.joined() and not Guild.busy, 10.0)
	_panel.tab = "home"
	_panel._rebuild()
	await _snap("home_before_attend")
	Guild.attend()
	await _wait_until(func(): return bool(Guild.me.get("attended", false)) and not Guild.busy, 10.0)
	Guild.donate("gold")
	await _wait_until(func(): return not Guild.busy, 10.0)
	_panel._rebuild()
	await _snap("home_after_attend")

	_panel.tab = "boss"
	_panel._rebuild()
	await _snap("boss_tab")
	_panel._start_fight()
	await _wait_until(func(): return _main._dungeon != null, 10.0)
	var fight = _main._dungeon
	if fight != null:
		await _frames(30)
		await _snap("dragon_start")
		await _frames(300)
		await _snap("dragon_fight")
		await _wait_until(func(): return fight.phase == fight.Phase.RESULT, 40.0)
		await _frames(20)
		await _snap("dragon_result")
		fight.leave()
		await _wait_until(func(): return _main.is_inside_tree(), 5.0)
		await _frames(10)
	_open_guild()
	_panel.tab = "boss"
	_panel._rebuild()
	await _snap("boss_tab_after")

	_panel.tab = "shop"
	_panel._rebuild()
	await _snap("shop")
	_panel.tab = "members"
	_panel._rebuild()
	await _snap("members")

	_panel.tab = "war"
	GuildWar.fetch()
	await _wait_until(func(): return not GuildWar.busy, 10.0)
	await _frames(20)
	_panel._rebuild()
	await _snap("war_attack")
	if _panel.buttons.has("war_mode:defense"):
		_panel.buttons["war_mode:defense"].pressed.emit()
		await _snap("war_defense")
		_panel.buttons["war_mode:attack"].pressed.emit()
		await _frames(4)
	# 공성은 길드원이 정한 시각에 열린다 — 테스트 훅으로 이번 주 공성 시각을 지금으로 당긴다
	_resp_done = false
	Net.send("POST", "/v1/test/war_now", {}, func(d):
		GuildWar._take(d)
		_resp_done = true, func(): _resp_done = true)
	await _wait_until(func(): return _resp_done, 10.0)
	_panel._rebuild()
	await _snap("war_live")
	if _panel.buttons.has("war_act"):
		_panel.buttons["war_act"].pressed.emit()
		var battle = null
		var end := Time.get_ticks_msec() + 15000
		while battle == null and Time.get_ticks_msec() < end:
			await get_tree().process_frame
			battle = _battle()
		print("battle: ", battle)
		if battle != null:
			await _frames(60)
			await _snap("war_battle_start")
			Engine.time_scale = 4.0
			await _wait(25.0)
			Engine.time_scale = 1.0
			await _snap("war_battle_clash")
			Engine.time_scale = 4.0
			await _wait(80.0, func(): return battle.gates_broken() > 0)
			Engine.time_scale = 1.0
			await _snap("war_battle_gate")
			battle.leave()
			await _frames(60)
			_open_guild()
			_panel.tab = "war"
			_panel._rebuild()
			await _frames(30)
			await _snap("war_after")
	print("PREVIEW DONE ", _n)
	get_tree().quit(0)


func _open_guild() -> void:
	if not _panel.is_open():
		_tabs.pick("guild")


func _battle():
	for c in get_tree().root.find_children("*", "", true, false):
		if c.get_script() != null and c.get_script().resource_path == "res://scripts/war_battle.gd":
			return c
	return null


func _request(path: String, body) -> void:
	_resp_done = false
	Net.send("POST", path, body, func(d):
		Economy.apply_server(d)
		_resp_done = true, func(): _resp_done = true)
	await _wait_until(func(): return _resp_done, 10.0)


func _wait(sec: float, cond := Callable()) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().create_timer(0.5, true, false, true).timeout
		t += 0.5
		if cond.is_valid() and cond.call():
			return


func _snap(name_s: String) -> void:
	await _frames(8)
	_n += 1
	var p := "%s_%02d_%s.png" % [_out, _n, name_s]
	get_viewport().get_texture().get_image().save_png(p)
	print("saved ", p)


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

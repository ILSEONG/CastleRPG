extends Node
## 길드전 화면 스냅샷(개발용): 실제 main 씬에서 길드 시트 [길드전] 탭 → [공성 시작] → 공성 전투 장면(시작·교전·성문 돌파) → 나가기 후 탭을 찍는다.
## 화면이 필요하다. 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/war_shots.tscn -- --out=/tmp/war
## 저장 파일은 건드리지 않는다. 전투 대기는 Engine.time_scale로 빨리 돌린다. 스크립트 처리 시간(ms/프레임)도 찍는다.

const HEROES := ["arteon", "ignis", "sylvana", "grom", "baldur", "lumina", "kyle", "nev", "bron", "mira", "torvin", "echo"]

var _main
var _out := "/tmp/war"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	GuildWar.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	for id in HEROES:
		Economy.heroes[id] = 1
		Economy.hero_levels[id] = 30
		Economy.hero_promotions[id] = 2
	Guild.load_save()
	GuildWar.load_save()
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(90)
	Guild.unlocked = true
	var rec: Dictionary = Guild.recommendations()[1]
	rec.level = 6
	Guild.join(rec)
	var tabs = _find("res://scripts/side_menu.gd")  # 길드는 오른쪽 아래 메뉴
	var panel = tabs.windows.guild
	tabs.pick("guild")
	panel.tab = "war"
	panel._rebuild()
	await _snap("1_panel")
	panel.buttons["war_mode:defense"].pressed.emit()
	await _snap("2_defense")
	panel.buttons["war_mode:attack"].pressed.emit()
	GuildWar.fixed_now = float(GuildWar.war.battle.started_at) + 1.0  # 공성 시각으로
	GuildWar.fetch()
	panel._rebuild()
	await _frames(4)
	panel.buttons["war_act"].pressed.emit()
	await _frames(60)
	var battle = _battle()
	print("battle: ", battle)
	await _snap("3_battle_deploy")
	print("[shots] deploying %s left %.0f" % [battle.deploying, battle.deploy_left])
	var mine: Array = battle.units(0).filter(func(u): return u.mine)
	for i in mine.size():  # 내 분대를 왼쪽 면 앞으로 옮겨 본다
		battle.deploy_unit(mine[i], Vector3(-(battle.half + 20.0), 0.0, -3.0 + 2.0 * i))
	await _snap("3b_battle_deployed")
	battle.request_start()
	await _snap("3c_battle_start")
	Engine.time_scale = 4.0
	await _wait(25.0)
	Engine.time_scale = 1.0
	await _measure(battle, "clash")
	await _snap("4_battle_clash")
	Engine.time_scale = 4.0
	await _wait(80.0, func(): return battle.gates_broken() > 0)
	Engine.time_scale = 1.0
	await _snap("5_battle_gate")
	print("[shots] clock %.0f kills %d gates %d keep %.0f" % [battle.clock, battle.kills, battle.gates_broken(), battle.keep.hp])
	battle.leave()
	await _frames(30)
	tabs.pick("guild")
	panel.tab = "war"
	panel._rebuild()
	await _snap("6_panel_after")
	get_tree().quit()


func _battle():
	for c in get_children():
		if c.get_script() != null and c.get_script().resource_path == "res://scripts/war_battle.gd":
			return c
	for c in get_tree().root.get_children():
		if c.get_script() != null and c.get_script().resource_path == "res://scripts/war_battle.gd":
			return c
	return null


func _measure(battle, tag: String) -> void:
	var sum := 0.0
	var n := 0
	for i in 60:
		await get_tree().process_frame
		sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		n += 1
	print("[perf] %s units %d — process %.2f ms/frame" % [tag, battle.units(0).size() + battle.units(1).size(), sum / n])


func _wait(sec: float, cond := Callable()) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().create_timer(0.5, true, false, true).timeout
		t += 0.5
		if cond.is_valid() and cond.call():
			return


func _snap(name_s: String) -> void:
	await _frames(8)
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, name_s])
	print("saved ", name_s)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _find(path: String) -> Node:
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
	return null

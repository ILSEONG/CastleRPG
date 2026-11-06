extends Node
## 스토어(구글 플레이) 휴대전화 스크린샷용 원본 장면(개발용, 2026-11-06): 장면 하나를 여러 순간 찍어 따로 저장한다.
## 화면이 필요하다. 실행(세로 1080x1920 권장):
##   xvfb-run -a -s "-screen 0 1080x1920x24" godot --path . --resolution 1080x1920 res://tests/store_shots.tscn -- --scene=stage --out=/tmp/shots
## --scene: castle | stage | gold | dragon | pvp | war | summon. 저장 파일은 건드리지 않는다(오프라인, save_path = "").

const GameData := preload("res://scripts/game_data.gd")
const SummonStage := preload("res://scripts/summon_stage.gd")
const LINEUP := ["chronos", "jujak", "hyeonmu", "baekho", "cheongryong", "yeonhwa", "ignis", "lumina", "arteon", "valen", "sylvana", "gaia"]

var _main
var _out := "/tmp/shots"
var _scene := "stage"
var _n := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--scene="):
			_scene = a.substr(8)
	DirAccess.make_dir_recursive_absolute(_out)
	if _scene == "summon":
		await _summon()
		get_tree().quit()
		return
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	GuildWar.save_path = ""
	Tutorial.save_path = ""
	Pvp.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	for id in LINEUP:
		Economy.heroes[id] = 1
		Economy.hero_levels[id] = int(Net.arg_value("lv")) if Net.arg_value("lv") != "" else 60
		Economy.hero_promotions[id] = 3
	Economy.soldiers = {"infantry:3": 30, "archer:3": 30, "cavalry:3": 20}
	Economy.gold = 1284500
	Economy.diamonds = 12850
	Economy.res = {"wood": 482300, "stone": 361900, "food": 527400}
	Economy.set_deploy(["hyeonmu", "baekho", "chronos", "jujak", "cheongryong", "yeonhwa", "ignis", "lumina"])
	Guild.load_save()
	GuildWar.load_save()
	Pvp.load_save()
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(120)
	match _scene:
		"castle":
			await _snap()
			await _wait(4.0)
			await _snap()
		"stage":
			GameState.stage = int(Net.arg_value("stage")) if Net.arg_value("stage") != "" else 30
			GameState.start_stage()
			var rig = _main.camera.get_parent()
			rig.zoom_by(float(Net.arg_value("zoom")) if Net.arg_value("zoom") != "" else 0.6)
			for t in [6.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0]:
				var strip = _main._strip
				if strip != null and not strip.cells.is_empty():
					strip.pick(strip.cells[(_n) % strip.cells.size()].hero)
				await _wait(t)
				await _snap()
		"gold":
			_main._dev_dungeon("gold")
			for t in [5.0, 3.0, 3.0, 3.0, 3.0, 3.0]:
				await _wait(t)
				await _snap()
		"dragon":
			Guild.unlocked = true
			Guild.join(Guild.recommendations()[0])
			var menu = _find("res://scripts/side_menu.gd")
			menu.pick("guild")
			var panel = menu.windows.guild
			panel.tab = "boss"
			panel._rebuild()
			await _frames(10)
			panel._start_fight()
			for t in [4.0, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5]:
				await _wait(t)
				await _snap()
		"pvp":
			Pvp.fetch()
			var tabs = _find("res://scripts/tab_bar.gd")
			tabs.press("dungeon")
			var dp = tabs.windows.dungeon
			dp.set_section("pvp")
			await _frames(10)
			dp.pvp.open_mode("total")
			await _frames(3)
			dp.pvp._start()
			for t in [3.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0]:
				await _wait(t)
				await _snap()
		"war":
			Guild.unlocked = true
			var rec: Dictionary = Guild.recommendations()[1]
			rec.level = 6
			Guild.join(rec)
			var menu2 = _find("res://scripts/side_menu.gd")
			var gp = menu2.windows.guild
			menu2.pick("guild")
			gp.tab = "war"
			gp._rebuild()
			await _frames(10)
			gp.buttons["war_mode:attack"].pressed.emit()
			GuildWar.fixed_now = float(GuildWar.war.battle.started_at) + 1.0
			GuildWar.fetch()
			gp._rebuild()
			await _frames(4)
			gp.buttons["war_act"].pressed.emit()
			await _frames(60)
			var battle = _battle()
			battle.request_start()
			Engine.time_scale = 3.0
			for t in [15.0, 10.0, 10.0, 10.0, 10.0, 10.0]:
				await _wait(t)
				Engine.time_scale = 1.0
				await _frames(3)
				await _snap()
				Engine.time_scale = 3.0
			Engine.time_scale = 1.0
	get_tree().quit()


func _summon() -> void:
	var st = SummonStage.new()
	add_child(st)
	await get_tree().process_frame
	for g in ["SSR", "UR"]:
		st.play(g, 10)
		for x in [0.3, 0.46, 0.6, 0.75, 0.9, 0.97]:
			while st._t < x * st._len:
				await get_tree().process_frame
			await _snap(g)
		st.stop()


func _battle():
	for n in get_tree().root.find_children("*", "", true, false):
		if n.get_script() != null and str(n.get_script().resource_path).ends_with("war_battle.gd"):
			return n
	return null


func _find(path: String):
	for n in get_tree().root.find_children("*", "", true, false):
		if n.get_script() != null and n.get_script().resource_path == path:
			return n
	return null


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, false).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _snap(tag := "") -> void:
	await RenderingServer.frame_post_draw
	_n += 1
	var p := "%s/%s%s_%02d.png" % [_out, _scene, tag, _n]
	get_viewport().get_texture().get_image().save_png(p)
	print("[store_shots] ", p)

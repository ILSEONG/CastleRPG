extends Node
## 맵 퀄리티 전/후(개발용, 2026-11-06): 내 성과 콘텐츠 무대(던전 4종, PVP 결투·총력전, 길드 드래곤)를 실제 게임 화면 그대로 한 장씩 찍는다.
## 화면이 필요하다. 저장 파일은 건드리지 않는다.
## 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/map_shots.tscn -- --out=/tmp/maps [--sec=5] [--modes=castle,gold]

const GameData := preload("res://scripts/game_data.gd")
const MODES := ["castle", "gold", "stone", "equip", "ticket", "duel", "total", "dragon"]

var _main
var _modes: Array = MODES
var _out := "/tmp/maps"


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Pvp.save_path = ""
	Pvp.load_save()
	Guild.load_save()
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	for h in GameData.heroes():
		Economy.heroes[str(h.id)] = 1
	Economy.soldiers = {"infantry:2": 8, "archer:1": 10, "cavalry:3": 6}
	var sec := float(Net.arg_value("sec")) if Net.arg_value("sec") != "" else 1.5
	if Net.arg_value("modes") != "":
		_modes = Array(Net.arg_value("modes").split(","))
	if Net.arg_value("out") != "":
		_out = Net.arg_value("out")
	DirAccess.make_dir_recursive_absolute(_out)
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(90)
	Pvp.fetch()
	Guild.unlocked = true
	Guild.join(Guild.recommendations()[0])
	for m in _modes:
		if m == "castle":
			await get_tree().create_timer(8.0).timeout
			await _save(m)
			continue
		await _start(m)
		if _main._dungeon == null:
			print("FAIL no scene for ", m)
			get_tree().quit(1)
			return
		await get_tree().create_timer(sec).timeout
		await _save(m)
		_main.leave_dungeon()
		Pvp.battle = {}
		await _frames(20)
	get_tree().quit()


func _save(m: String) -> void:
	var hidden: Array = []
	if Net.arg_value("ui") == "":  # 기본: 맵만 보이게 화면 UI(CanvasLayer)를 잠깐 숨긴다
		for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
			if c.visible:
				c.visible = false
				hidden.append(c)
		await _frames(2)
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png("%s/%s.png" % [_out, m])
	print("saved ", m)
	for c in hidden:
		c.visible = true


func _start(m: String) -> void:
	if m in ["gold", "equip", "ticket", "stone"]:
		_main._dev_dungeon(m)
	elif m == "dragon":
		var menu = _find("res://scripts/side_menu.gd")
		menu.pick("guild")
		var panel = menu.windows.guild
		panel.tab = "boss"
		panel._rebuild()
		await _frames(10)
		panel._start_fight()
	else:
		var tabs = _find("res://scripts/tab_bar.gd")
		tabs.press("dungeon")
		var panel = tabs.windows.dungeon
		panel.set_section("pvp")
		panel.pvp.open_mode(m)
		await _frames(3)
		if m == "duel":  # 방어팀 정하기(pvp_shots와 같은 순서)
			panel.pvp._open_picker("team")
			panel.pvp._confirm_pick()
			panel.pvp.open_mode(m)
			await _frames(3)
		panel.pvp._start()
	for i in 300:
		await get_tree().process_frame
		if _main._dungeon != null:
			break
	await _frames(10)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _find(path: String) -> Node:
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
	return null

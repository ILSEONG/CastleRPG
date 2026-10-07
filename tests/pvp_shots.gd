extends Node
## PVP 화면 스냅샷(개발용): 던전 시트 [PVP] 탭 홈·결투 페이지·영웅 고르기, 결투·총력전 전투, 결과, 상점 [PVP] 탭을 찍어 한 장으로 붙인다.
## 화면이 필요하다. 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/pvp_shots.tscn -- --out=/tmp/pvp.png
## 저장 파일은 건드리지 않는다(오프라인, save_path = "").

const GameData := preload("res://scripts/game_data.gd")

var _main
var _shots: Array = []
var _result := {}


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Pvp.save_path = ""
	Pvp.load_save()
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	for h in GameData.heroes():
		Economy.heroes[str(h.id)] = 1
	Economy.soldiers = {"infantry:2": 8, "archer:1": 10, "cavalry:3": 6}
	Pvp.local.coins = 420
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(90)
	Pvp.fetch()
	var tabs = _find("res://scripts/tab_bar.gd")
	tabs.press("dungeon")
	var panel = tabs.windows.dungeon
	panel.set_section("pvp")
	await _snap()
	panel.pvp.open_mode("duel")
	await _snap()
	panel.pvp._open_picker("team")
	await _snap()
	panel.pvp._confirm_pick()
	Pvp.result_ready.connect(func(r): _result = r)
	for m in ["duel", "total"]:
		panel.pvp.open_mode(m)
		await _frames(3)
		panel.pvp._start()
		await _frames(30)
		await get_tree().create_timer(4.0).timeout
		await _snap()
		Engine.time_scale = 8.0
		_result = {}
		while _result.is_empty():
			await _frames(10)
		Engine.time_scale = 1.0
		if m == "total":
			await _snap()
		_main.leave_dungeon()
		await _frames(10)
	tabs.windows.shop.open_tab("pvp")
	await _snap()
	var out := "/tmp/pvp.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var w: int = _shots[0].get_width() / 2
	var h: int = _shots[0].get_height() / 2
	var sheet := Image.create(w * 4, h * 2, false, Image.FORMAT_RGB8)
	for i in _shots.size():
		var img: Image = _shots[i]
		img.convert(Image.FORMAT_RGB8)
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % 4) * w, (i / 4) * h))
	sheet.save_png(out)
	print("saved ", out, " shots=", _shots.size())
	get_tree().quit()


func _snap() -> void:
	await _frames(8)
	_shots.append(get_viewport().get_texture().get_image())


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _find(path: String) -> Node:
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
	return null

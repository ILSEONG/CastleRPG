extends Node
## 전투 중 UI 스냅샷(개발용): 성 대기(메뉴 UI) → 스테이지 진행(메뉴 숨김 + 하단 영웅 초상화 줄, 초상화로 영웅 선택) → 골드 던전(하단 띠로 선택)을 찍어 한 장으로 붙인다.
## 화면이 필요하다(헤드리스 불가). 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/battle_ui_shots.tscn -- --out=/tmp/battle_ui.png
## 저장 파일은 건드리지 않는다.

var _main
var _shots: Array = []


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	for h in GameData_heroes().slice(0, 5):
		Economy.heroes[h.id] = 1
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(120)
	_shots.append(get_viewport().get_texture().get_image())
	GameState.start_stage()
	await _frames(90)
	var strip = _main._strip
	if not strip.cells.is_empty():
		strip.pick(strip.cells[0].hero)
	await _frames(30)
	_shots.append(get_viewport().get_texture().get_image())
	_main._dev_dungeon("gold")
	await _frames(120)
	var d = _main._dungeon
	if d != null and not d.hud.strip.is_empty():
		d.hud.pick(d.hud.strip[1].hero)
	await _frames(20)
	_shots.append(get_viewport().get_texture().get_image())
	var out := "/tmp/battle_ui.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var w := 540
	var h := 960
	var sheet := Image.create(w * _shots.size(), h, false, Image.FORMAT_RGB8)
	for i in _shots.size():
		var img: Image = _shots[i]
		img.convert(Image.FORMAT_RGB8)
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	sheet.save_png(out)
	print("saved ", out)
	get_tree().quit()


func GameData_heroes() -> Array:
	return preload("res://scripts/game_data.gd").heroes()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

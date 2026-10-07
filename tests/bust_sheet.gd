extends Node
## 영웅 흉상 초상화 한 장(개발용, 2026-10-07 디자인 보강 5번): Portraits로 모든 영웅의 "bust:<id>"를 렌더해 등급 색 칸 위에 6열로 붙여 저장한다.
## 화면(렌더러)이 필요하다. 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/bust_sheet.tscn -- --out=/tmp/busts.png [--full=1]

const GameData := preload("res://scripts/game_data.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")
const Art := preload("res://scripts/art.gd")
const CELL := 160
const COLS := 6


func _ready() -> void:
	GameData.load_tables()
	var p = PortraitsScript.new()
	add_child(p)
	var pre := "hero:" if Net.arg_value("full") != "" else "bust:"
	var keys: Array = GameData.heroes().map(func(h): return pre + str(h.id))
	for k in keys:
		PortraitsScript.portrait(k)
	for i in 600:
		await get_tree().process_frame
		if keys.all(func(k): return PortraitsScript.has_portrait(k)):
			break
	var rows := ceili(keys.size() / float(COLS))
	var sheet := Image.create_empty(CELL * COLS, CELL * rows, false, Image.FORMAT_RGBA8)
	for i in keys.size():
		var h := GameData.hero(keys[i].substr(5))
		var at := Vector2i(i % COLS * CELL, i / COLS * CELL)
		sheet.fill_rect(Rect2i(at, Vector2i(CELL, CELL)), Color(Art.GRADE_COLORS.get(h.grade, Color.GRAY)).lightened(0.35))
		var img: Image = PortraitsScript.portrait(keys[i]).get_image()
		img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
		if Net.arg_value("marks") != "":  # 얼굴 가운데 높이(FACE_Y) 표시
			sheet.fill_rect(Rect2i(at + Vector2i(0, int(PortraitsScript.FACE_Y * CELL)), Vector2i(CELL, 2)), Color.RED)
	var out := Net.arg_value("out") if Net.arg_value("out") != "" else "/tmp/busts.png"
	sheet.save_png(out)
	print("saved ", out, " (", keys.filter(func(k): return PortraitsScript.has_portrait(k)).size(), "/", keys.size(), " rendered)")
	get_tree().quit()

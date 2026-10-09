extends Node
## 던전 탭 카드 띠 스냅샷(개발용): -- --old 면 예전 3D 스냅샷 띠(DungeonArt.enabled = false), 아니면 일러스트 띠. 목록을 내려 셋째 카드도 찍는다.
## 화면이 필요하다. 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/dungeon_shots.tscn -- --out=/tmp/dungeon.png [--old]
## 저장 파일은 건드리지 않는다(오프라인, save_path = "").

const DungeonArt := preload("res://scripts/dungeon_art.gd")

var _main
var _shots: Array = []


func _ready() -> void:
	DungeonArt.enabled = not ("--old" in OS.get_cmdline_user_args())
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(90)
	var tabs = _find("res://scripts/tab_bar.gd")
	tabs.press("dungeon")
	await _frames(60)  # 예전 띠는 스냅샷이 렌더될 때까지
	await _snap()
	var dp = _find("res://scripts/dungeon_panel.gd")
	for s in dp.find_children("*", "ScrollContainer", true, false):
		s.scroll_vertical = 10000
	await _snap()
	var out := "/tmp/dungeon.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var w: int = _shots[0].get_width()
	var h: int = _shots[0].get_height()
	var sheet := Image.create(w * 2, h, false, Image.FORMAT_RGB8)
	for i in _shots.size():
		var img: Image = _shots[i]
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(i * w, 0))
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

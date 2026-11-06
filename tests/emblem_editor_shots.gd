extends Node
## 길드 문양 편집 화면 스냅샷(개발용, 화면 필요, 오프라인): 창설 카드 → 문양 만들기 창(모양·문양·배경 색·문양 색 탭) → 길드장 홈([문양 변경]) → 랭킹 크기.
## 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/emblem_editor_shots.tscn -- --out=/tmp/emblem_editor.png
## 저장 파일은 건드리지 않는다.

var _main
var _shots: Array = []


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Guild.load_save()
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(90)
	var tabs = _find("res://scripts/side_menu.gd")
	var panel = tabs.windows.guild
	tabs.pick("guild")
	Guild.unlocked = true
	Economy.gold = 600000
	panel._rebuild()
	await _frames(4)
	panel.scroll.scroll_vertical = 100000
	await _snap()
	panel.buttons.emblem_make.pressed.emit()
	var ed = panel.emblem_editor
	ed.shape = 0
	ed.symbol = 16
	ed.bg = 5
	ed.fg = 0
	ed._rebuild()
	await _snap()
	ed.set_tab("symbol")
	await _snap()
	ed.set_tab("bg")
	await _snap()
	ed.set_tab("fg")
	ed.pick(2)
	await _snap()
	ed.buttons.save.pressed.emit()
	panel._rebuild()
	await _snap()
	panel.name_edit.text = "은빛기사단"
	panel.buttons.create.pressed.emit()
	await _frames(4)
	panel._rebuild()
	await _frames(2)
	panel.scroll.scroll_vertical = 0
	await _snap()
	panel.buttons.emblem_change.pressed.emit()
	ed.set_tab("shape")
	ed.pick(4)
	await _snap()
	var out := "/tmp/emblem_editor.png"
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
	await _frames(12)
	_shots.append(get_viewport().get_texture().get_image())


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _find(path: String) -> Node:
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
	return null

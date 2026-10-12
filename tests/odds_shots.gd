extends Node
## 모집 확률 안내 스냅샷(개발용): 다이아 모집 창, [확률 정보](다이아), 골드 확률 안내 맨 아래(레벨별 표).
## 화면이 필요하다. 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/odds_shots.tscn -- --out=/tmp/odds.png
## 저장 파일은 건드리지 않는다(오프라인, save_path = "").

var _main
var _shots: Array = []


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(90)
	Economy.diamonds = 500
	Economy.gold = 20000
	Economy.changed.emit()
	var tabs = _find("res://scripts/tab_bar.gd")
	tabs.press("recruit")
	await _frames(20)
	var rec = tabs.windows.recruit
	rec.set_currency(rec.DIA)
	await _frames(4)
	await _snap()
	rec.odds_button.pressed.emit()
	await _frames(6)
	await _snap()
	rec.odds.visible = false
	rec.set_currency(rec.GOLD)
	rec.odds_button.pressed.emit()
	await _frames(6)
	var sc: ScrollContainer = rec.odds.list.get_parent()
	sc.scroll_vertical = 100000
	await _frames(6)
	await _snap()
	var out := "/tmp/odds.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var w: int = _shots[0].get_width() / 2
	var h: int = _shots[0].get_height() / 2
	var sheet := Image.create(w * 3, h, false, Image.FORMAT_RGB8)
	for i in _shots.size():
		var img: Image = _shots[i]
		img.convert(Image.FORMAT_RGB8)
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % 3) * w, (i / 3) * h))
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

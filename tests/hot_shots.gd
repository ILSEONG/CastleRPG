extends Node
## 핫딜 화면 스냅샷(개발용): 패배 계기로 뜬 핫딜 창, 닫은 뒤 성 화면 [핫딜] 버튼, 상점 [패키지] 맨 위 핫딜 카드.
## 화면이 필요하다. 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/hot_shots.tscn -- --out=/tmp/hot.png
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
	var hot = _find("res://scripts/hot_deal.gd")
	GameState.stage = 26
	GameState.stage_failed.emit(26)  # 패배 계기 → 오프라인이라 곧바로 핫딜, 대기 중이라 창이 열린다
	await _frames(10)
	await _snap()
	hot.close()
	await _frames(10)
	await _snap()
	var tabs = _find("res://scripts/tab_bar.gd")
	tabs.press("shop")
	await _snap()
	var out := "/tmp/hot.png"
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

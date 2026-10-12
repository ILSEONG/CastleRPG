extends Node
## 창 모양 스냅샷(개발용, 2026-10-12 두루마리 창): 실제 main 씬에서 팝업·시트 창을 하나씩 열어 --dir에 720×1280 PNG로 저장한다.
## 화면이 필요하다. 저장 파일은 건드리지 않는다.
## 실행: xvfb-run -a godot --path . --resolution 720x1280 --rendering-driver opengl3 res://tests/window_shots.tscn -- --dir=/tmp/window_shots
## unroll_mid.png = 상인 창이 펼쳐지는 중간 한 장.

const HEROES := ["arteon", "ignis", "sylvana", "grom", "baldur", "lumina", "kyle", "nev", "luna", "valen"]

var _main
var _dir := "/tmp/window_shots"


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Pvp.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	for id in HEROES:
		Economy.heroes[id] = 1
	Economy.diamonds = 500
	if Net.arg_value("dir") != "":
		_dir = Net.arg_value("dir")
	DirAccess.make_dir_recursive_absolute(_dir)
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(120)
	var w = _win("merchant_panel.gd")
	w.open()
	await get_tree().create_timer(0.06).timeout  # 펼치는 중간 한 장
	_save("unroll_mid")
	await _shot("merchant", w)
	w = _win("building_panel.gd")
	w.open_building("keep")
	await _shot("building", w)
	w = _win("offline_panel.gd")
	w.show_report({"away_sec": 7380.0, "kills": 1234, "gold_tenths": 56780000})
	await _shot("offline", w)
	w = _win("settings_panel.gd")
	w.open()
	await _shot("settings", w)
	w = _win("recruit_panel.gd")
	w.open()
	await _shot("recruit", w)
	for s in ["hero_panel.gd", "growth_panel.gd", "shop_panel.gd", "mission_panel.gd"]:
		w = _win(s)
		w.open()
		await _shot(s.get_basename().replace("_panel", ""), w)
	print("saved to ", _dir)
	get_tree().quit()


func _win(script_file: String):
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path.get_file() == script_file:
			return c
	push_warning("no window " + script_file)
	return null


func _shot(name_s: String, w) -> void:
	await get_tree().create_timer(0.5).timeout  # 펼침(UNROLL_SEC)이 끝나게
	await _frames(2)
	_save(name_s)
	w.close()
	await _frames(2)


func _save(name_s: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png("%s/%s.png" % [_dir, name_s])
	print("saved ", name_s)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

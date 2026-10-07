extends Node
## 드래곤 전투 공격 장면(개발용, 화면 필요, 2026-10-07): 길드 보스 전투에서 드래곤 공격마다 젖힌 순간·타격 직후를 찍어 시트로 모은다(공격 4번 = 8장).
## 공격 n번(--n=장 수), 타격 뒤 --lag=프레임.
## 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/dragon_fight_shots.tscn -- --out=/tmp/dragon_fight.png

var _main
var _shots: Array = []
var _labels: Array = []


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Guild.load_save()
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(60)
	Guild.unlocked = true
	Guild.join(Guild.recommendations()[0])
	var tabs = _find("res://scripts/side_menu.gd")
	tabs.pick("guild")
	var panel = tabs.windows.guild
	panel.tab = "boss"
	panel._rebuild()
	await _frames(10)
	panel._start_fight()
	var scene = null
	for i in 120:
		await get_tree().process_frame
		scene = _main._dungeon
		if scene != null:
			break
	if scene == null:
		print("FAIL no boss scene")
		get_tree().quit(1)
		return
	var dragon = scene.dragon
	var model = dragon._model
	var seen := 0
	var peaked := false
	var t_end := Time.get_ticks_msec() + 30000
	while _shots.size() < int(Net.arg_value("n") if Net.arg_value("n") != "" else "8") and Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		var k: float = model._act_t / model._act_len if model._act != "" else 0.0
		if model._act != "" and not peaked and k >= 0.4:
			peaked = true
			await _snap(model.attack_kind + " 젖힘")
		if dragon.attacks > seen:
			seen = dragon.attacks
			peaked = false
			await _frames(int(Net.arg_value("lag") if Net.arg_value("lag") != "" else "5"))
			await _snap(model.attack_kind + " 타격")
	var out := Net.arg_value("out") if Net.arg_value("out") != "" else "/tmp/dragon_fight.png"
	var w: int = _shots[0].get_width() / 2
	var h: int = _shots[0].get_height() / 2
	var rows := (_shots.size() + 3) / 4
	var sheet := Image.create(w * 4, h * rows, false, Image.FORMAT_RGB8)
	for i in _shots.size():
		var img: Image = _shots[i]
		img.convert(Image.FORMAT_RGB8)
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % 4) * w, (i / 4) * h))
	sheet.save_png(out)
	print("saved ", out, " ", _labels)
	get_tree().quit()


func _snap(label: String) -> void:
	await RenderingServer.frame_post_draw
	_shots.append(get_viewport().get_texture().get_image())
	_labels.append(label)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _find(path: String) -> Node:
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
	return null

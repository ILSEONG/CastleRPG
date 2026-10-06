extends Node
## 길드 화면 스냅샷(개발용): 실제 main 씬에서 길드 시트를 열고 화면(잠김 → 미가입 → 홈 → 보스 → 상점 → 길드원 — 보스 전투 장면은 tests/guild_boss_shots)을 찍어 한 장으로 붙인다.
## 화면이 필요하다(헤드리스 불가). 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/guild_shots.tscn -- --out=/tmp/guild.png
## 저장 파일은 건드리지 않는다(Economy·Fever·Guild save_path = "").

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
	var tabs = _find("res://scripts/tab_bar.gd")
	var panel = tabs.windows.guild
	tabs.press("guild")
	await _snap()
	Guild.unlocked = true
	Economy.gold = 60000
	Economy.diamonds = 300
	panel._rebuild()
	await _snap()
	var rec: Dictionary = Guild.recommendations()[1]
	rec.level = 6
	Guild.join(rec)
	Guild.attend()
	Guild.donate("gold")
	for m in Guild.guild.members:
		m.att = m.att or randf() < 0.5
	panel._rebuild()
	await _snap()
	panel.tab = "boss"
	panel._rebuild()
	await _snap()
	panel.tab = "shop"
	Guild.coins = 700
	panel._rebuild()
	await _snap()
	panel.tab = "members"
	panel._rebuild()
	await _snap()
	var out := "/tmp/guild.png"
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

extends Node
## 길드 보스 실제 전투 확인(개발용, 화면 필요): 오프라인으로 길드에 들어가 [도전] → 드래곤 전투 장면을 찍고, 실제 피해(dragon.dealt)와
## 배치 영웅 초당 피해 × 20초(예전 계산)를 비교해 찍는다. 저장 파일은 건드리지 않는다.
## 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/guild_boss_shots.tscn -- --out=/tmp/guild_boss.png [--level=30] [--promo=2]

var _main
var _shots: Array = []


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	var lv := int(Net.arg_value("level")) if Net.arg_value("level") != "" else 1
	var promo := int(Net.arg_value("promo")) if Net.arg_value("promo") != "" else 0
	Guild.load_save()
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(60)
	for id in Economy.heroes:
		Economy.hero_levels[id] = lv
		Economy.hero_promotions[id] = promo
	Guild.unlocked = true
	Guild.join(Guild.recommendations()[0])
	var tabs = _find("res://scripts/tab_bar.gd")
	tabs.press("guild")
	var panel = tabs.windows.guild
	panel.tab = "boss"
	panel._rebuild()
	await _frames(30)
	await _snap()
	var dps := Guild.team_dps()
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
	await _frames(20)
	await _snap()
	await _secs(6.0)
	await _snap()
	await _secs(6.0)
	print("HP after 12 s: ", scene.heroes.map(func(h): return snappedf(h.hp_ratio(), 0.01)))
	await _snap()
	while scene.phase != scene.Phase.RESULT:
		await get_tree().process_frame
	var dealt: float = scene.dragon.dealt
	print("DAMAGE level=%d promo=%d heroes=%d dealt=%d old=%d ratio=%.2f attacks=%d alive=%d result=%s" % [lv, promo, scene.heroes.size(), int(dealt),
		int(dps * 20.0), dealt / maxf(1.0, dps * 20.0), scene.dragon.attacks, scene.heroes.filter(func(h): return h.is_alive()).size(), scene.result])
	await _frames(20)
	await _snap()
	scene.leave()
	await _frames(30)
	await _snap()
	var out := Net.arg_value("out") if Net.arg_value("out") != "" else "/tmp/guild_boss.png"
	var w: int = _shots[0].get_width() / 2
	var h: int = _shots[0].get_height() / 2
	var sheet := Image.create(w * 3, h * 2, false, Image.FORMAT_RGB8)
	for i in mini(_shots.size(), 6):
		var img: Image = _shots[i]
		img.convert(Image.FORMAT_RGB8)
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % 3) * w, (i / 3) * h))
	sheet.save_png(out)
	print("saved ", out)
	get_tree().quit()


func _snap() -> void:
	await _frames(4)
	_shots.append(get_viewport().get_texture().get_image())


func _secs(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _find(path: String) -> Node:
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
	return null

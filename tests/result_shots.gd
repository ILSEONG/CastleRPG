extends Node
## 모집 카드 뒤집기·승패 리본 화면(개발용, 2026-10-07 디자인 보강 4번): 모집 10회 결과(SSR·SR·R 섞어서)를 띄우고 몇 순간을 찍고,
## 골드 던전 승리·패배 결과 창, 성 라운드 클리어(보스 라운드)를 찍어 --dir에 720×1280 PNG로 저장한다. 화면이 필요하다. 저장 파일은 건드리지 않는다.
## 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/result_shots.tscn -- --dir=/tmp/result_shots

const GameData := preload("res://scripts/game_data.gd")

var _main
var _dir := "/tmp/result_shots"


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Pvp.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	if Net.arg_value("dir") != "":
		_dir = Net.arg_value("dir")
	DirAccess.make_dir_recursive_absolute(_dir)
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(90)
	# 1. 모집 10회 결과: SSR 1 · SR 2 · R 7(새 영웅 + 중복 섞어서)
	var by := {"SSR": [], "SR": [], "R": []}
	for h in GameData.heroes():
		by[h.grade].append(h.id)
	var picks := [by.R[0], by.SR[0], by.R[1], by.R[2], by.R[3], by.R[4], by.SSR[0], by.R[5], by.SR[1], by.R[6]]
	var results: Array = []
	for i in picks.size():
		var id: String = picks[i]
		results.append({"hero_id": id, "grade": GameData.hero(id).grade, "new": i % 3 != 2, "shards": 3})
		Economy.heroes[id] = 1
	var rp = _find("res://scripts/recruit_panel.gd")
	rp.open()
	await _frames(20)
	rp._show_results(results)
	var t0 := Time.get_ticks_msec()
	for at in [0.05, 0.55, 0.95, 1.7]:
		while Time.get_ticks_msec() - t0 < at * 1000.0:
			await get_tree().process_frame
		_save("recruit_%.2f" % at)
	rp.close()
	await _frames(20)
	# 2. 골드 던전 결과(승리·패배)
	_main._dev_dungeon("gold")
	for i in 300:
		await get_tree().process_frame
		if _main._dungeon != null:
			break
	await _frames(20)
	var d = _main._dungeon
	d.result = {"win": true, "rewards": {"gold_tenths": 40000}}
	d.hud.show_result()
	await _wait(0.12)
	_save("dungeon_win_enter")
	await _wait(1.0)
	_save("dungeon_win")
	d.result = {"win": false}
	d.hud.show_result()
	await _wait(1.0)
	_save("dungeon_lose")
	_main.leave_dungeon()
	await _frames(30)
	# 3. 성 라운드 클리어(보스 라운드)
	var hud = _main._hud
	var boss := GameData.rounds_per_stage()
	hud._on_cleared(boss)
	await _wait(1.0)
	_save("stage_clear")
	print("saved to ", _dir)
	get_tree().quit()


func _save(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png("%s/%s.png" % [_dir, name])


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _find(path: String) -> Node:
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
	return null

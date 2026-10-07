extends Node
## 영웅 카드 화면(개발용, 2026-10-07 디자인 보강 5번): 영웅 창 목록, 골드 던전 편성, 모집 10회 결과, 성 전투 초상화 줄을 찍어
## --dir에 720×1280 PNG로 저장한다. 모든 영웅을 갖고(승급 섞어서) 초상화 렌더가 끝날 때까지 기다린다. 화면이 필요하다. 저장 파일은 건드리지 않는다.
## 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/card_shots.tscn -- --dir=/tmp/card_shots

const GameData := preload("res://scripts/game_data.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")

var _main
var _dir := "/tmp/card_shots"


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
	var i := 0
	for h in GameData.heroes():
		Economy.heroes[str(h.id)] = 1
		Economy.hero_promotions[str(h.id)] = i % 4
		i += 1
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(30)
	for k in 900:  # 로딩 화면이 초상화를 줄 세운다 — 다 그려질 때까지
		await get_tree().process_frame
		if PortraitsScript.current != null and PortraitsScript.current.queue.is_empty() and PortraitsScript.current._pending == "":
			break
	await _frames(30)
	var tabs = _find("res://scripts/tab_bar.gd")
	tabs.press("hero")
	await _wait_portraits()
	_save("hero_list")
	var hw = tabs.windows.hero
	hw.show_detail("valen")
	await _wait(1.0)
	_save("hero_detail_art")
	hw.big_card.show_model = true
	await _wait(1.5)
	_save("hero_detail_model")
	hw.big_card.show_model = false
	hw._show_list()
	await _frames(5)
	tabs.press("hero")
	await _frames(10)
	tabs.press("dungeon")
	await _frames(10)
	var dw = tabs.windows.dungeon
	dw.open_form("gold")
	await _wait_portraits()
	_save("dungeon_form")
	dw.close()
	await _frames(10)
	var by := {"SSR": [], "SR": [], "R": []}
	for h in GameData.heroes():
		by[h.grade].append(h.id)
	var picks := [by.R[0], by.SR[0], by.R[1], by.R[2], by.R[3], by.R[4], by.SSR[0], by.R[5], by.SR[1], by.R[6]]
	var results: Array = []
	for j in picks.size():
		results.append({"hero_id": picks[j], "grade": GameData.hero(picks[j]).grade, "new": j % 3 != 2, "shards": 3})
	var rp = _find("res://scripts/recruit_panel.gd")
	rp.open()
	await _frames(10)
	rp._show_results(results)
	await _wait(2.0)
	await _wait_portraits()
	_save("recruit")
	rp.close()
	await _frames(10)
	GameState.start_stage()
	await _wait(2.5)
	_save("stage_strip")
	print("saved to ", _dir)
	get_tree().quit()


func _wait_portraits() -> void:
	for k in 600:
		await get_tree().process_frame
		var p = PortraitsScript.current
		if p == null or (p.queue.is_empty() and p._pending == ""):
			break
	await _frames(6)


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

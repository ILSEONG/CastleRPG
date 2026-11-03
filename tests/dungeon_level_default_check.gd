extends Node
## 던전 창 단계 기본값 확인(개발용, 2026-11-03): 낮춰 고른 뒤 창을 닫았다 열면 도전 가능한 가장 높은 단계, 클리어로 최고 단계가 오르면 따라 오른다.
##   godot --headless --path . res://tests/dungeon_level_default_check.tscn
func _ready() -> void:
	Economy.save_path = ""
	Tutorial.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Fever.save_path = ""
	Guild.save_path = ""
	Party.save_path = ""
	Tutorial.state = "skipped"
	var m = preload("res://scenes/main.tscn").instantiate()
	add_child(m)
	for i in 30:
		await get_tree().process_frame
	Economy.dungeons.gold.best_level = 5
	var p = null
	for c in m.get_children():
		if c.get_script() == preload("res://scripts/dungeon_panel.gd"):
			p = c
	p.open()
	await get_tree().process_frame
	var a: int = p.level_of("gold")
	p.step_level("gold", -3)
	var b: int = p.level_of("gold")
	p.close()
	await get_tree().process_frame
	p.open()
	await get_tree().process_frame
	var c: int = p.level_of("gold")
	Economy.dungeons.gold.best_level = 6
	var d: int = p.level_of("gold")
	print("LEVELS open %d, lowered %d, reopened %d, after clear %d -> %s" % [a, b, c, d, "OK" if [a, b, c, d] == [6, 3, 6, 7] else "FAIL"])
	var pv = p.party_tab
	Party.view = {"quests": {"lich": {"best": 2, "clears_left": 3}, "spider": {"best": 0, "clears_left": 3}}, "queue": {"state": "idle"}}
	pv.diff["lich"] = 1
	Tutorial.state = "skipped"
	p.section = "party"
	p._show_list(false)
	await get_tree().process_frame
	print("PARTY lich diff %d (want 3), spider %d (want 1)" % [pv.diff["lich"], pv.diff["spider"]])
	get_tree().quit(0)

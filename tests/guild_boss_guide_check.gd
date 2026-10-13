extends Node
## 가이드 「길드 보스 도전」 미션 중 드래곤 전투를 끝까지(결과·성으로 돌아오기) — 2026-10-13 "길드던전 깨니까 팅겼어".
## 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/guild_boss_guide_check.tscn  (마지막 줄 GUIDE BOSS PASSED)

var _main
var _fails := 0


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Guild.load_save()
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(60)
	Guild.unlocked = true
	Guild.join(Guild.recommendations()[0])
	var idx := -1
	for i in Tutorial.MISSIONS.size():
		if str(Tutorial.MISSIONS[i].id) == "guild_boss":
			idx = i
	Tutorial.state = "active"
	Tutorial.step = idx
	Tutorial.count = 0
	Tutorial.tours_on = true  # 실제 게임처럼 포커스 설명을 띄운다
	Tutorial.changed.emit()
	await _frames(10)
	var tabs = _find(_main, "res://scripts/side_menu.gd")
	tabs.pick("guild")
	await _frames(30)
	var panel = tabs.windows.guild
	panel.tab = "boss"
	panel._rebuild()
	await _frames(60)
	if Tutorial.tour_node != null:
		Tutorial.tour_node.finish()
	panel._start_fight()
	var scene = null
	for i in 240:
		await get_tree().process_frame
		scene = _main._dungeon
		if scene != null:
			break
	_check(scene != null, "boss fight opens")
	if scene == null:
		_end()
		return
	Engine.time_scale = 4.0
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(scene) and scene.phase != scene.Phase.RESULT and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	Engine.time_scale = 1.0
	_check(is_instance_valid(scene) and scene.phase == scene.Phase.RESULT, "fight reaches the result")
	await _frames(120)  # 결과 화면에서 가이드가 반응할 시간(포커스 설명·카드)
	print("[guide] step=%d complete=%s tour=%s" % [Tutorial.step, Tutorial.complete(), Tutorial.tour_node])
	if is_instance_valid(scene):
		scene.leave()
	await _frames(180)
	_check(_main._dungeon == null, "back to the castle")
	var card = _find(_main, "res://scripts/tutorial_card.gd")
	_check(card != null and is_instance_valid(card._pointer), "guide arrow survives the guild window closing (a freed arrow crashed the release APK)")
	print("[guide] after leave step=%d complete=%s tour=%s" % [Tutorial.step, Tutorial.complete(), Tutorial.tour_node])
	if Tutorial.complete():
		Tutorial.claim()
	await _frames(180)
	_end()


func _end() -> void:
	print("GUIDE BOSS %s" % ("PASSED" if _fails == 0 else "FAILED %d" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _find(n: Node, path: String):
	if n.get_script() != null and n.get_script().resource_path == path:
		return n
	for c in n.get_children():
		var r = _find(c, path)
		if r != null:
			return r
	return null

extends Node
## 던전 입장·결과 화면 스냅샷(개발용, 2026-10-29 던전 품질 개선). 셋(골드·장비·모집권)을 즉시 승리 훅으로 열어
## 입장 직후(0.3초·1.2초)와 결과 화면을 찍는다. 화면이 필요하다. 실행:
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/dungeon_flow_shots.tscn -- --out=/tmp/flow

const GameData := preload("res://scripts/game_data.gd")

var _main
var _out := "/tmp/flow"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Party.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	for h in GameData.heroes():
		Economy.heroes[str(h.id)] = 1
		Economy.hero_levels[str(h.id)] = 20
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(30)
	for t in ["gold", "equip", "ticket"]:
		for c in get_children():
			if c.get_script() == _main.get_script() and not c.is_queued_for_deletion():
				_main = c
		var party: Array = GameData.heroes().slice(0, GameData.party_size(t)).map(func(h): return str(h.id))
		var helper := ""
		if t == "ticket":
			for hc in Economy.helper_candidates():
				if not party.has(hc.hero_id):
					helper = str(hc.key)
					break
		var before: int = _main._dungeon.get_instance_id() if _main._dungeon != null else 0
		Economy.debug_win_on = t != "ticket"
		Economy.start_dungeon(t, 1, party, helper)
		await _wait_until(func(): return _main._dungeon != null and _main._dungeon.get_instance_id() != before and _main._dungeon.is_inside_tree(), 8.0)
		var d = _main._dungeon
		if d == null:
			continue
		await get_tree().create_timer(0.3).timeout
		_shot("%s_in03" % t)
		await get_tree().create_timer(0.9).timeout
		_shot("%s_in12" % t)
		if t == "ticket":
			d._report(false)
		await _wait_until(func(): return d.phase == d.Phase.RESULT, 25.0)
		await get_tree().create_timer(0.8).timeout
		_shot("%s_result" % t)
		Economy.debug_win_on = false
		d.leave()
		await get_tree().create_timer(3.0).timeout
	get_tree().quit(0)


func _shot(name_s: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, name_s])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait_until(cond: Callable, timeout_sec: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while not cond.call():
		if Time.get_ticks_msec() > end:
			return false
		await get_tree().process_frame
	return true

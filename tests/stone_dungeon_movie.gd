extends Node
## 강화석 던전 시연 영상(개발용, 오프라인): 입장 연출 → 전투 끝까지 → 결과 화면. 화면이 필요하다(--write-movie와 함께):
##   xvfb-run -a godot --path . --resolution 720x1280 --write-movie /tmp/stone.avi --fixed-fps 30 res://tests/stone_dungeon_movie.tscn -- --lv=20 --level=1
## 저장 파일은 건드리지 않는다.

const GameData := preload("res://scripts/game_data.gd")

var _main
var _lv := 20
var _level := 1


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lv="):
			_lv = int(a.substr(5))
		elif a.begins_with("--level="):
			_level = int(a.substr(8))
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Party.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	for h in GameData.heroes():
		Economy.heroes[str(h.id)] = 1
		Economy.hero_levels[str(h.id)] = _lv
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(1.5).timeout
	var party: Array = ["hans", "ella", "dorik", "nina", "arteon"]
	Economy.start_dungeon("stone", _level, party, "")
	await _wait_until(func(): return _main._dungeon != null and _main._dungeon.is_inside_tree(), 8.0)
	var d = _main._dungeon
	if d != null:
		await _wait_until(func(): return d.phase == d.Phase.RESULT, 900.0)
		await get_tree().create_timer(4.0).timeout
	get_tree().quit(0)


func _wait_until(cond: Callable, timeout_sec: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while not cond.call():
		if Time.get_ticks_msec() > end:
			return false
		await get_tree().process_frame
	return true

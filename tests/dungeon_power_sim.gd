extends Node
## 던전 권장 전투력 재기(개발용, 오프라인, 2026-11-07 사용자 "각 던전의 클리어 권장 스펙"). 정해 둔 팀(장비 없음, 모두 같은 레벨·그 레벨에 맞는 승급)으로
## 단계마다 이기는 가장 낮은 영웅 레벨을 이분 탐색하고 그때 팀 전투력(Economy와 같은 hero_power 합)을 찍는다. 실행:
##   godot --headless --fixed-fps 30 --path . res://tests/dungeon_power_sim.tscn -- --type=stone --stages=1,5,10,20
## 저장 파일은 건드리지 않는다.

const GameData := preload("res://scripts/game_data.gd")
const TEAMS := {"gold": ["arteon", "grom", "sylvana", "ignis", "lumina", "kyle"], "equip": ["arteon", "grom", "sylvana", "lumina"],
	"ticket": ["arteon", "grom", "sylvana", "lumina"], "stone": ["arteon", "grom", "sylvana", "ignis", "lumina"]}
const HELPER := "seraphine"

var _main
var _type := "stone"
var _stages: Array = [1, 5, 10, 20]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--type="):
			_type = a.substr(7)
		elif a.begins_with("--stages="):
			_stages = Array(a.substr(9).split(",")).map(func(s): return int(s))
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Party.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	for h in GameData.heroes():
		Economy.heroes[str(h.id)] = 1
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(1.0).timeout
	var lo_hint := 1
	for st in _stages:
		var lo := lo_hint
		var hi := 300
		if not await _wins(st, hi):
			print("SIM %s stage %d: not cleared even at Lv300" % [_type, st])
			continue
		while lo < hi:
			var mid := (lo + hi) / 2
			if await _wins(st, mid):
				hi = mid
			else:
				lo = mid + 1
		lo_hint = lo
		print("SIM %s stage %d: min Lv %d promo %d team power %d" % [_type, st, lo, _promo(lo), _team_power(lo)])
	get_tree().quit(0)


func _promo(lv: int) -> int:
	return clampi(ceili(lv / 50.0) - 1, 0, GameData.MAX_PROMOTION)


func _set_team(lv: int) -> void:
	for id in TEAMS[_type] + [HELPER]:
		Economy.hero_levels[id] = lv
		Economy.hero_promotions[id] = _promo(lv)


func _team_power(lv: int) -> int:
	_set_team(lv)
	var p := 0
	for id in TEAMS[_type]:
		p += GameData.hero_power(GameData.hero(id), lv, _promo(lv), {})
	if _type == "ticket":
		p += GameData.hero_power(GameData.hero(HELPER), lv, _promo(lv), {})
	return p


func _wins(stage: int, lv: int) -> bool:
	_set_team(lv)
	var run := {"run_id": "sim%d_%d" % [stage, lv], "seed": 12345 + stage, "type": _type, "level": stage, "party": TEAMS[_type].duplicate(),
		"enemies": GameData.dungeon_enemies(_type, stage), "started_at": Economy.time_now(), "time_limit": GameData.config_num("dungeon_time_limit")}
	if _type == "ticket":
		run.helper = {"hero_id": HELPER, "level": lv, "promotion": _promo(lv)}
	Economy.current_run = run.duplicate(true)
	Economy.dungeon_started.emit(run)
	await _wait_until(func(): return _main._dungeon != null and _main._dungeon.is_inside_tree(), 10.0)
	var d = _main._dungeon
	var won := false
	var end := Time.get_ticks_msec() + 600000
	while d != null and is_instance_valid(d) and Time.get_ticks_msec() < end:
		if d.phase == d.Phase.WON:
			won = true
			break
		if d.phase != d.Phase.FIGHT:
			break
		await get_tree().process_frame
	print("  try stage %d Lv %d -> %s (%.0f s)" % [stage, lv, "WIN" if won else "lose", d.clock if d != null else -1.0])
	_main.leave_dungeon()
	await get_tree().process_frame
	return won


func _wait_until(cond: Callable, timeout_sec: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while not cond.call():
		if Time.get_ticks_msec() > end:
			return false
		await get_tree().process_frame
	return true

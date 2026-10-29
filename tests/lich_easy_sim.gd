extends Node
## 리치의 무덤 쉬움 승률 재기(개발용, 2026-10-29 가이드 마지막 미션 "파티 던전 클리어"가 x1에서 지는지).
## 가이드를 막 마친 팀(영웅 Lv HERO_LV, 승급 PROMO)으로 오프라인 매칭(AI 성주 3명 = 내 영웅 능력치 복사)을 RUNS번 x1로 끝까지 돌린다.
## 내 영웅은 손대지 않는다(조작 없는 최악). 실행:
##   godot --headless --path . res://tests/lich_easy_sim.tscn -- --hero=hans --lv=20 --runs=3

const GameData := preload("res://scripts/game_data.gd")
const BattleScript := preload("res://scripts/party_battle.gd")

var _main
var _hero := "hans"
var _lv := 20
var _promo := 0
var _runs := 3
var _scale := 1.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hero="):
			_hero = a.substr(7)
		elif a.begins_with("--lv="):
			_lv = int(a.substr(5))
		elif a.begins_with("--promo="):
			_promo = int(a.substr(8))
		elif a.begins_with("--scale="):
			_scale = float(a.substr(8))
		elif a.begins_with("--runs="):
			_runs = int(a.substr(7))
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Party.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	Party.auto_accept = true
	Party.view = {"quests": Party._local_quests(), "queue": {"state": "idle"}}
	Economy.heroes = {_hero: 1}
	Economy.hero_levels[_hero] = _lv
	if _promo > 0:
		Economy.hero_promotions[_hero] = _promo
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(30)
	var rows := []
	for i in _runs:
		Party.start_queue("lich", 1, _hero, Party.pick_soldiers())
		await _wait_until(func(): return _battle() != null, 10.0)
		var b = _battle()
		if b == null:
			print("LICH run %d: battle did not open" % i)
			continue
		Engine.time_scale = _scale
		var hp0: float = float(b.boss.hp_max) if b.boss != null else 0.0
		await _wait_until(func(): return not is_instance_valid(b) or b.done, 400.0)
		var left: float = float(b.boss.hp) / maxf(1.0, hp0) if is_instance_valid(b) and b.boss != null else -1.0
		rows.append([i, b.result.get("win", false), b.clock, left * 100.0, b.heroes.filter(func(u): return is_instance_valid(u) and u.is_alive()).size()])
		print("LICH run %d: win %s clock %.1f boss hp left %.0f%% heroes alive %d" % rows[-1])
		Engine.time_scale = 1.0
		for k in 2:
			if is_instance_valid(b) and b.hud != null:
				b.hud._on_leave()
			await get_tree().create_timer(0.5).timeout
		await _wait_until(func(): return _battle() == null and Party.state() == "idle", 10.0)
		await _frames(30)
	print("LICH %s Lv%d promo %d x%.1f: %d / %d wins" % [_hero, _lv, _promo, _scale, rows.filter(func(r): return r[1]).size(), rows.size()])
	get_tree().quit(0)


func _battle():
	for c in get_children():
		if c.get_script() == BattleScript and not c.is_queued_for_deletion():
			return c
	return null


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

extends Node
## 던전 보스 공격 리듬 재기(개발용, 2026-10-29 "적 보스 공격모션이 왤캐 찔끔 찔끔"): 던전 하나를 끝까지 돌리며 보스가
## 휘두름·걷기·기절·밀려남·대기에 쓴 시간과 휘두른 수·끊긴 수를 센다. 실행:
##   godot --headless --path . res://tests/boss_rhythm_probe.tscn -- --type=stone
const GameData := preload("res://scripts/game_data.gd")
var _main
var _type := "stone"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--type="):
			_type = a.substr(7)
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
	await get_tree().create_timer(1.0).timeout
	var party: Array = GameData.heroes().slice(0, GameData.party_size(_type)).map(func(h): return str(h.id))
	var helper := ""
	if _type == "ticket":
		for hc in Economy.helper_candidates():
			if not party.has(hc.hero_id):
				helper = str(hc.key)
				break
	Economy.start_dungeon(_type, 1, party, helper)
	while _main._dungeon == null or not _main._dungeon.is_inside_tree():
		await get_tree().process_frame
	var d = _main._dungeon
	while d.boss == null and d.phase != d.Phase.RESULT:
		await get_tree().process_frame
	var b = d.boss
	var t := {"swing": 0.0, "walk": 0.0, "stun": 0.0, "knock": 0.0, "idle": 0.0, "cast": 0.0}
	var started := 0
	var cut := 0
	var last_swings: int = b.swings
	var prev_left := -1.0
	var anims := {}
	var log := []
	var clock := 0.0
	while is_instance_valid(b) and b.is_alive() and d.phase != d.Phase.RESULT:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		clock += dt
		if not is_instance_valid(b):
			break
		var st := "idle"
		if b.is_stunned():
			st = "stun"
		elif b.has_method("is_telegraphing") and b.is_telegraphing():
			st = "cast"
		elif b._knock_t > 0.0:
			st = "knock"
		elif b._swing_left >= 0.0 or b._model.is_busy():
			st = "swing" if b._model._current in b._model._spec.get("attacks", [b._model._spec.anims.attack]) else "cast"
		elif b._walking:
			st = "walk"
		t[st] += dt
		if b.swings != last_swings:
			started += b.swings - last_swings
			last_swings = b.swings
			anims[b._model._current] = anims.get(b._model._current, 0) + 1
		if prev_left > 0.0 and b._swing_left < 0.0 and b._knock_t > 0.0:
			cut += 1
		prev_left = b._swing_left
		if log.size() < 400 and (log.is_empty() or log[-1][1] != st):
			log.append([snappedf(clock, 0.01), st])
	print("BOSS %s: %.1fs  swings %d  cut by knock %d  anims %s" % [_type, clock, started, cut, anims])
	print("BOSS time: ", t, "  patterns ", [b.get("spins"), b.get("slams"), b.get("sweeps"), b.get("charges")] if is_instance_valid(b) else [])
	print("BOSS log: ", log.slice(0, 80))
	get_tree().quit(0)

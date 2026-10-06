extends Node
## 공성전 성능 측정(개발용, 헤드리스 — 그리기 제외 스크립트 시간): 20 대 20 분대(영웅 160명) 전투에서 프레임당 처리 시간.
## 실행: godot --headless --path . res://tests/war_perf.tscn -- --squads=20 [--off=brain,crowd,bars,numbers]

const WarCheck := preload("res://tests/war_check.gd")
const BattleScript := preload("res://scripts/war_battle.gd")


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	preload("res://scripts/game_data.gd")._config.fx_shake = "0"
	var n := int(_arg("squads", "20"))
	var off := _arg("off", "").split(",")
	var b = BattleScript.new()
	b.plan = WarCheck.make_plan(n, n)
	add_child(b)
	await get_tree().process_frame
	for c in b.get_children():
		var p := str(c.get_script().resource_path) if c.get_script() != null else ""
		if ("crowd" in off and p.ends_with("crowd.gd")) or ("bars" in off and p.ends_with("hp_bars.gd")) or ("numbers" in off and p.ends_with("damage_numbers.gd")):
			c.process_mode = Node.PROCESS_MODE_DISABLED
			print("off ", p)
	if "units" in off:
		for u in b.units(0) + b.units(1):
			u.set_process(false)
		print("off units")
	if "models" in off:
		for u in b.units(0) + b.units(1):
			u._model.set_process(false)
			u._model.visible = false
		print("off models")
	if "anim" in off:
		for u in b.units(0) + b.units(1):
			for ap in u.find_children("*", "AnimationMixer", true, false):
				ap.active = false
		print("off anim")
	for phase in [["march", 4.0], ["clash", 12.0], ["fight", 12.0]]:
		var t0 := Time.get_ticks_msec()
		var frames := 0
		var sum := 0.0
		while (Time.get_ticks_msec() - t0) / 1000.0 < float(phase[1]):
			await get_tree().process_frame
			frames += 1
			sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var counts := {}
		for nd in b.find_children("*", "", true, false):
			var k := str(nd.get_script().resource_path.get_file()) if nd.get_script() != null else nd.get_class()
			if nd.is_processing() or nd.is_physics_processing():
				counts[k] = counts.get(k, 0) + 1
		var top := counts.keys()
		top.sort_custom(func(a, c): return counts[a] > counts[c])
		print("  tweens ", get_tree().get_processed_tweens().size(), " nodes ", b.find_children("*", "", true, false).size())
		print("  processing nodes: ", top.slice(0, 12).map(func(k): return "%s %d" % [k, counts[k]]))
		print("[perf] %s: %d frames, %.1f ms/frame wall, %.1f ms process/frame, battle clock %.1f, alive %d" % [phase[0], frames, float(phase[1]) * 1000.0 / frames, sum / frames, b.clock, b.units(0).filter(func(u): return u.is_alive()).size() + b.units(1).filter(func(u): return u.is_alive()).size()])
	get_tree().quit()


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % k):
			return a.substr(k.length() + 3)
	return d

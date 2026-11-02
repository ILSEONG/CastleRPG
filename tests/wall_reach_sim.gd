extends Node
## 성벽 위 원거리 영웅의 화력 지원 거리 측정(개발용, 헤드리스, 2026-11-02 사용자 "성문위에 원거리 영웅들이 사거리가 안돼서 화력지원을 못해").
## 성 스테이지를 돌리며 성 밖에서 보병과 붙어 싸우는(보병 2 m 안) 괴물마다, 같은 면 성벽 위 원거리 영웅까지의 수평 거리를 모은다.
## 실행: godot --headless --fixed-fps 30 --path . res://tests/wall_reach_sim.tscn -- --keep=10 --infantry=12 --round=40
## 출력: 영웅 자리별 거리 분위수와, 영웅 사거리 안에 든 비율.

const GameData := preload("res://scripts/game_data.gd")
const Formation := preload("res://scripts/formation.gd")

var dists := {}  # 영웅 id → 거리들


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % k):
			return a.split("=", true, 1)[1]
	return d


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Fever.reset()
	GameData._config.fx_shake = "0"
	Economy.reset(Time.get_unix_time_from_system())
	Pvp.save_path = ""
	var keep := int(_arg("keep", "10"))
	Economy.levels[GameData.KEEP] = keep
	Economy.levels[GameData.GATE] = keep
	var slots := GameData.hero_slots(keep)
	var melee := GameData.heroes().filter(func(h): return h.role == "melee").map(func(h): return str(h.id))
	var ranged := GameData.heroes().filter(func(h): return h.role == "ranged").map(func(h): return str(h.id))
	var team := []
	for i in slots:
		team.append(melee[i] if i % 8 < 4 else ranged[i])  # 첫 바퀴 근접(성문 앞), 둘째 바퀴 원거리(성벽 위)
	for id in team:
		Economy.heroes[id] = 1
		Economy.hero_levels[id] = 30
	Economy.deploy = team.duplicate()
	var inf := int(_arg("infantry", "12"))
	Economy.soldiers = {"infantry:2": inf * 4}
	Economy.soldier_deployed = {"infantry:2": inf * 4}
	Economy.levels[GameData.KEEP] = keep
	var main = preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 5:
		await get_tree().process_frame
	GameState.auto_continue = false
	GameState.stage = int(_arg("round", "40"))
	var done := [false]
	GameState.stage_cleared.connect(func(_s): done[0] = true)
	GameState.stage_failed.connect(func(_s): done[0] = true)
	GameState.start_stage()
	var t := 0.0
	var half: float = main.castle.half if "castle" in main else 0.0
	while not done[0] and t < 150.0:
		await get_tree().process_frame
		t += 1.0 / 30.0
		var sol := get_tree().get_nodes_in_group("soldiers").filter(func(s): return s.is_alive() and not Formation.is_inside(half, s.global_position) and s.global_position.y < 1.0)
		var wall := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.has_method("is_on_wall") and h.is_alive() and h.role == "ranged" and h.is_on_wall())
		var fight := []
		for m in get_tree().get_nodes_in_group("monsters"):
			if m.is_alive() and not Formation.is_inside(half, m.global_position) \
					and sol.any(func(s): return Formation.flat_distance(s.global_position, m.global_position) <= 2.0):
				fight.append(m.global_position)
		for h in wall:  # 영웅마다 가장 가까운 교전 괴물(같은 면 · 가장 가까운 성문 쪽)까지
			var side := Formation.side_of(h.global_position)
			var best := INF
			for p in fight:
				if Formation.side_of(p) == side and Formation.nearest_gate(half, side, p) == Formation.nearest_gate(half, side, h.global_position):
					best = minf(best, Formation.flat_distance(h.global_position, p))
			if best == INF:
				continue
			var k := "%s(%sm)" % [h.def.id, h.def.range]
			if not dists.has(k):
				dists[k] = []
			dists[k].append(best)
	print("WALLSIM half=%s soldiers=%d" % [half, get_tree().get_nodes_in_group("soldiers").size()])
	for k in dists:
		var a: Array = dists[k]
		a.sort()
		var r := float(k.get_slice("(", 1).trim_suffix("m)"))
		var inr := a.filter(func(x): return x <= r).size()
		print("WALLSIM %s n=%d p10=%.1f p50=%.1f p90=%.1f in_range=%d%%" % [k, a.size(), a[a.size() / 10], a[a.size() / 2], a[a.size() * 9 / 10], 100 * inr / a.size()])
	get_tree().quit()

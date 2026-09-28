extends SceneTree
## 순수 로직 헤드리스 테스트.
## 실행: ./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd

const Balance := preload("res://scripts/balance.gd")
const WaveDirector := preload("res://scripts/wave_director.gd")

var _fails := 0


func _init() -> void:
	test_balance_monotonic()
	test_balance_tables()
	test_wave_stage_ends_with_boss()
	test_wave_total_monotonic()
	test_wave_idle_cycle()
	if _fails > 0:
		printerr("FAILED %d" % _fails)
	else:
		print("ALL PASSED")
	quit(1 if _fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		printerr("FAIL: " + msg)


func test_balance_monotonic() -> void:
	for stage in range(1, 20):
		check(Balance.hp_scale(stage + 1) >= Balance.hp_scale(stage), "hp_scale monotonic at %d" % stage)
		check(Balance.atk_scale(stage + 1) >= Balance.atk_scale(stage), "atk_scale monotonic at %d" % stage)
		check(Balance.wave_count(stage + 1) >= Balance.wave_count(stage), "wave_count monotonic at %d" % stage)
		check(Balance.wave_size(stage + 1, 0) >= Balance.wave_size(stage, 0), "wave_size monotonic at %d" % stage)


func test_balance_tables() -> void:
	check(Balance.hero_slots(1) == 4, "keep level 1 gives 4 heroes")
	check(Balance.hero_slots(2) == 8, "keep level 2 gives 8 heroes")
	check(Balance.hero_slots(3) == 12, "keep level 3 gives 12 heroes")
	check(Balance.hero_slots(99) == 12, "keep level beyond table clamps to last")
	check(Balance.gate_hp_max(1) == 400.0, "gate hp at level 1")
	check(Balance.gate_hp_max(2) > Balance.gate_hp_max(1), "gate hp grows with level")
	check(Balance.MONSTER.has("grunt") and Balance.MONSTER.has("epic_boss"), "monster table has grunt and epic_boss")
	for kind in Balance.MONSTER:
		for key in ["hp", "atk", "speed", "range", "atk_interval", "scale", "color"]:
			check(Balance.MONSTER[kind].has(key), "monster %s has %s" % [kind, key])


func test_wave_stage_ends_with_boss() -> void:
	var ev := WaveDirector.build(1, WaveDirector.MODE_STAGE)
	check(ev.size() > 1, "stage schedule has events")
	check(ev[-1].kind == "epic_boss", "last event is epic_boss")
	for i in range(1, ev.size()):
		check(ev[i].time >= ev[i - 1].time, "events sorted at %d" % i)
	var bosses := ev.filter(func(e): return e.kind == "epic_boss").size()
	check(bosses == 1, "exactly one boss")
	for e in ev:
		check(e.side >= 0 and e.side <= 3, "side in range")


func test_wave_total_monotonic() -> void:
	var prev := 0
	for stage in range(1, 11):
		var n := WaveDirector.build(stage, WaveDirector.MODE_STAGE).size()
		check(n >= prev, "spawn count non-decreasing at stage %d" % stage)
		prev = n


func test_wave_idle_cycle() -> void:
	var ev := WaveDirector.build(1, WaveDirector.MODE_IDLE)
	check(ev.size() == 4, "idle cycle spawns 4")
	check(ev[0].time > 0.0, "first idle spawn is not at t=0")
	var sides: Array = ev.map(func(e): return e.side)
	check(sides == [0, 1, 2, 3], "idle sides rotate 0..3")
	for e in ev:
		check(e.kind == "grunt", "idle spawns grunts only")

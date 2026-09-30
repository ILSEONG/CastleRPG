extends SceneTree
## 순수 로직 헤드리스 테스트.
## 실행: ./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd

const Balance := preload("res://scripts/balance.gd")
const WaveDirector := preload("res://scripts/wave_director.gd")
const GameStateScript := preload("res://scripts/game_state.gd")
const FormationScript := preload("res://scripts/formation.gd")
const Art := preload("res://scripts/art.gd")

var _fails := 0


func _init() -> void:
	test_balance_monotonic()
	test_balance_tables()
	test_wave_stage_ends_with_boss()
	test_wave_total_monotonic()
	test_wave_idle_cycle()
	test_gamestate_win_loop()
	test_gamestate_fail_keeps_stage()
	test_gamestate_stop_after_stage()
	test_gamestate_gate_broken_once()
	test_gamestate_idle_castle_break_refills()
	test_gamestate_start_stage_refills()
	test_gamestate_hero_count()
	test_layout_tables()
	test_building_layout()
	test_formation_claims()
	test_formation_positions()
	test_art_assets()
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
		for key in ["hp", "atk", "speed", "range", "atk_interval", "scale"]:
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


func test_gamestate_win_loop() -> void:
	var gs = GameStateScript.new()
	var modes: Array = []
	gs.mode_changed.connect(func(m): modes.append(m))
	check(gs.mode == gs.Mode.IDLE, "starts idle")
	gs.start_stage()
	check(gs.mode == gs.Mode.STAGE, "stage after start")
	gs.on_all_monsters_dead()
	check(gs.stage == 2, "stage incremented on clear")
	check(gs.mode == gs.Mode.RESULT, "result after clear")
	gs.advance(Balance.RESULT_SEC + 0.01)
	check(gs.mode == gs.Mode.COUNTDOWN, "countdown after result")
	check(gs.countdown_left() > 2.9, "countdown starts near 3s")
	gs.advance(Balance.COUNTDOWN_SEC + 0.01)
	check(gs.mode == gs.Mode.STAGE, "stage after countdown")
	check(modes == [gs.Mode.STAGE, gs.Mode.RESULT, gs.Mode.COUNTDOWN, gs.Mode.STAGE], "transition order %s" % [modes])
	gs.free()


func test_gamestate_fail_keeps_stage() -> void:
	var gs = GameStateScript.new()
	var failed: Array = []
	gs.stage_failed.connect(func(s): failed.append(s))
	gs.stage = 5
	gs.start_stage()
	gs.damage_castle(Balance.CASTLE_HP + 1.0)
	check(gs.castle_hp == 0.0, "castle hp clamps at 0")
	check(gs.mode == gs.Mode.RESULT, "result after castle destroyed")
	check(failed == [5], "stage_failed emitted with stage 5")
	gs.damage_castle(50.0)
	check(gs.mode == gs.Mode.RESULT, "extra damage after destruction ignored")
	gs.advance(Balance.RESULT_SEC + 0.01)
	check(gs.mode == gs.Mode.IDLE, "idle after fail")
	check(gs.stage == 5, "stage kept on fail")
	check(gs.castle_hp == gs.castle_hp_max, "castle healed after fail")
	gs.free()


func test_gamestate_stop_after_stage() -> void:
	var gs = GameStateScript.new()
	gs.start_stage()
	gs.stop_after_stage()
	check(gs.stop_requested, "stop requested")
	gs.stop_after_stage()
	check(not gs.stop_requested, "stop toggled off")
	gs.stop_after_stage()
	gs.on_all_monsters_dead()
	gs.advance(Balance.RESULT_SEC + 0.01)
	check(gs.mode == gs.Mode.IDLE, "idle when stop requested after clear")
	check(gs.stage == 2, "stage still incremented")
	gs.free()


func test_gamestate_gate_broken_once() -> void:
	var gs = GameStateScript.new()
	var broken: Array = []
	gs.gate_broken.connect(func(s): broken.append(s))
	gs.damage_gate(2, gs.gate_hp_max * 0.5)
	check(not gs.is_gate_broken(2), "half damage does not break gate")
	gs.damage_gate(2, gs.gate_hp_max)
	gs.damage_gate(2, 10.0)
	check(gs.is_gate_broken(2), "gate broken")
	check(gs.gate_hp[2] == 0.0, "gate hp clamps at 0")
	check(broken == [2], "gate_broken emitted exactly once, got %s" % [broken])
	check(not gs.is_gate_broken(0), "other gates untouched")
	gs.refill()
	check(gs.gate_hp[2] == gs.gate_hp_max, "gate restored on refill")
	gs.free()


func test_gamestate_idle_castle_break_refills() -> void:
	var gs = GameStateScript.new()
	var refills := [0]
	gs.refilled.connect(func(): refills[0] += 1)
	gs.damage_gate(1, 9999.0)
	gs.damage_castle(9999.0)
	check(gs.mode == gs.Mode.IDLE, "idle mode kept")
	check(gs.castle_hp == gs.castle_hp_max, "castle healed immediately in idle")
	check(not gs.is_gate_broken(1), "gates restored in idle refill")
	check(refills[0] == 1, "refilled emitted once")
	gs.free()


func test_gamestate_start_stage_refills() -> void:
	var gs = GameStateScript.new()
	var refills := [0]
	gs.refilled.connect(func(): refills[0] += 1)
	gs.damage_gate(3, gs.gate_hp_max * 0.5)
	gs.damage_castle(100.0)
	check(not gs.is_gate_broken(3) and gs.gate_hp[3] < gs.gate_hp_max, "gate damaged, not broken, in idle")
	check(gs.castle_hp < gs.castle_hp_max and gs.mode == gs.Mode.IDLE, "castle damaged in idle")
	gs.start_stage()
	check(gs.gate_hp[3] == gs.gate_hp_max, "start_stage refills the gate")
	check(gs.castle_hp == gs.castle_hp_max, "start_stage refills the castle")
	check(refills[0] == 1, "refilled emitted once, got %d" % refills[0])
	check(gs.mode == gs.Mode.STAGE, "stage mode after start_stage")
	gs.free()


func test_gamestate_hero_count() -> void:
	var gs = GameStateScript.new()
	check(gs.hero_count() == 4, "4 heroes at keep level 1")
	gs.keep_level = 2
	check(gs.hero_count() == 8, "8 heroes at keep level 2")
	gs.free()


func test_layout_tables() -> void:
	check(Balance.interior_half(1) == 16.0, "interior half is 16m at keep level 1")
	check(Balance.interior_half(2) > Balance.interior_half(1), "interior grows at keep level 2")
	check(Balance.interior_half(3) > Balance.interior_half(2), "interior grows at keep level 3")
	check(Balance.interior_half(99) == Balance.interior_half(3), "interior clamps beyond table")
	check(Balance.hero_role(0) == "warrior" and Balance.hero_role(1) == "archer", "roster starts warrior, archer")
	check(Balance.hero_role(2) == "warrior" and Balance.hero_role(3) == "archer", "roster alternates")
	for role in Balance.HERO_ROLES:
		for key in ["name", "hp", "atk", "range", "atk_interval", "speed"]:
			check(Balance.HERO_ROLES[role].has(key), "role %s has %s" % [role, key])
	check(Balance.HERO_ROLES.archer.range > Balance.HERO_ROLES.warrior.range, "archer outranges warrior")


func test_building_layout() -> void:
	var half_tiles := floori(Balance.INTERIOR_TILES[0] / 2.0)
	var allowed := Rect2i(-half_tiles + 1, -half_tiles + 1, 2 * half_tiles - 2, 2 * half_tiles - 2)
	var road_ns := Rect2i(-1, -half_tiles, 2, 2 * half_tiles)
	var road_ew := Rect2i(-half_tiles, -1, 2 * half_tiles, 2)
	var placed: Array = []
	var ids := {}
	for b in Balance.BUILDINGS:
		var r := Rect2i(b.cell, b.size)
		check(allowed.encloses(r), "%s inside level-1 interior with 1-tile wall margin" % b.id)
		if b.id != "keep":
			check(not r.intersects(road_ns) and not r.intersects(road_ew), "%s stays off the cross roads" % b.id)
		for other in placed:
			check(not r.intersects(other), "%s overlaps no other building" % b.id)
		placed.append(r)
		ids[b.id] = true
	for id in ["keep", "barracks", "tavern", "lab", "houses", "lumber", "quarry", "farm"]:
		check(ids.has(id), "building %s present" % id)
	var keep := Balance.building("keep")
	check(Rect2i(keep.cell, keep.size).get_center() == Vector2i(0, 0), "keep centered on the crossroads")
	check(Balance.building("nope").is_empty(), "unknown building id gives empty dict")


func test_formation_claims() -> void:
	var f = FormationScript.new()
	var gate: int = FormationScript.POST_GATE
	var wall: int = FormationScript.POST_WALL
	check(f.claim(0, 0, gate) == 0, "first gate claim gets slot 0")
	check(f.claim(1, 0, gate) == 1, "second gate claim gets slot 1")
	check(f.claim(2, 0, gate) == 2, "third gate claim gets slot 2")
	check(f.claim(3, 0, gate) == -1, "gate post full at capacity 3")
	check(f.assignment(3).is_empty(), "failed claim leaves hero unassigned")
	check(f.claim(1, 0, gate) == 1, "re-claiming own post keeps the slot")
	check(f.claim(1, 0, wall) == 0, "moving to the wall claims wall slot 0")
	check(f.claim(3, 0, gate) == 1, "slot freed by the move is reusable")
	f.release(0)
	check(f.claim(4, 0, gate) == 0, "released slot is reusable")
	check(f.claim(5, 2, gate) == 0, "other side is independent")
	var a: Dictionary = f.assignment(1)
	check(a.side == 0 and a.post == wall and a.slot == 0, "assignment reports side, post and slot")
	check(FormationScript.capacity(gate) == Balance.GATE_FRONT_SLOTS.size(), "gate capacity from balance")
	check(FormationScript.capacity(wall) == Balance.WALL_TOP_SLOTS.size(), "wall capacity from balance")
	# Test that hero with existing assignment keeps it when move to full post fails
	# Gate side 0 currently full (heroes 0, 3, 2 at slots 0, 1, 2)
	# Wall side 0 has 3 empty slots (1, 2, 3)
	check(f.claim(6, 0, wall) == 1, "claim wall slot 1")
	check(f.claim(7, 0, wall) == 2, "claim wall slot 2")
	check(f.claim(8, 0, wall) == 3, "claim wall slot 3")
	# Wall side 0 is now full (4 slots: heroes 1, 6, 7, 8 at slots 0, 1, 2, 3)
	check(f.claim(3, 0, wall) == -1, "hero 3 cannot move to full wall")
	var a3_after: Dictionary = f.assignment(3)
	check(a3_after.side == 0 and a3_after.post == gate and a3_after.slot == 1, "hero 3 kept original assignment at gate slot 1")
	check(f.claim(9, 0, gate) == -1, "gate still full, cannot add new hero")
	check(f.assignment(3).slot == 1, "hero 3 still holds gate slot 1")


func test_formation_positions() -> void:
	var half := Balance.interior_half(1)
	var outer := half + Balance.WALL_T
	var seen := {}
	for side in 4:
		var dir: Vector3 = FormationScript.SIDE_DIR[side]
		check(dir.dot(FormationScript.gate_position(half, side)) == half + Balance.WALL_T / 2.0, "gate on wall centerline, side %d" % side)
		check(dir.dot(FormationScript.gate_target(half, side)) > outer, "gate target outside the wall face, side %d" % side)
		check(dir.dot(FormationScript.spawn_center(half, side)) > outer + 10.0, "spawn far outside, side %d" % side)
		for slot in FormationScript.capacity(FormationScript.POST_GATE):
			var p: Vector3 = FormationScript.slot_position(half, side, FormationScript.POST_GATE, slot)
			check(p.y == 0.0 and dir.dot(p) > outer, "gate slot on the ground outside the wall (side %d slot %d)" % [side, slot])
			seen[p] = true
		for slot in FormationScript.capacity(FormationScript.POST_WALL):
			var p: Vector3 = FormationScript.slot_position(half, side, FormationScript.POST_WALL, slot)
			check(p.y == Balance.WALL_H, "wall slot on the wall top (side %d slot %d)" % [side, slot])
			check(absf(dir.dot(p) - (half + Balance.WALL_T / 2.0)) < 0.001, "wall slot on the wall centerline")
			check(absf(FormationScript.perp(side).dot(p)) > Balance.GATE_W / 2.0, "wall slot beside the gate, not above it")
			seen[p] = true
	check(seen.size() == 4 * (Balance.GATE_FRONT_SLOTS.size() + Balance.WALL_TOP_SLOTS.size()), "all slot positions distinct")
	var keep := Balance.building("keep")
	var keep_half: float = keep.size.x * Balance.TILE / 2.0
	for side in 4:
		var k: Vector3 = FormationScript.keep_target(side)
		check(FormationScript.SIDE_DIR[side].dot(k) > keep_half, "keep target outside the keep footprint, side %d" % side)
	check(is_equal_approx(FormationScript.flat_distance(Vector3(0, 3, 0), Vector3(3, 0, 4)), 5.0), "flat distance ignores height")


func test_art_assets() -> void:
	var specs := {}
	specs.merge(Art.HERO_MODELS)
	specs.merge(Art.MONSTER_MODELS)
	var visible_gear := {"warrior": ["1H_Sword", "Round_Shield"], "archer": ["2H_Crossbow"]}  # Knight, Rogue_Hooded
	for key in Balance.HERO_ROLES:
		check(Art.HERO_MODELS.has(key), "hero role %s has a model" % key)
	for key in Balance.MONSTER:
		check(Art.MONSTER_MODELS.has(key), "monster %s has a model" % key)
	for key in specs:
		var spec: Dictionary = specs[key]
		check(ResourceLoader.exists(spec.scene), "%s model exists" % key)
		if not ResourceLoader.exists(spec.scene):
			continue
		var root: Node = (load(spec.scene) as PackedScene).instantiate()
		var players := root.find_children("*", "AnimationPlayer", true, false)
		check(players.size() == 1, "%s has one AnimationPlayer" % key)
		if players.size() == 1:
			var ap: AnimationPlayer = players[0]
			for anim in spec.anims.values():
				check(ap.has_animation(anim), "%s has animation %s" % [key, anim])
			if Art.MONSTER_MODELS.has(key) and ap.has_animation(spec.anims.death):
				var death_len := ap.get_animation(spec.anims.death).length
				check(Art.CORPSE_SEC <= death_len, "%s corpse removed before death animation ends: CORPSE_SEC %.2f <= %.2f" % [key, Art.CORPSE_SEC, death_len])
		for mesh_name in spec.hide:
			check(root.find_child(mesh_name, true, false) != null, "%s has mesh %s to hide" % [key, mesh_name])
		for mesh_name in visible_gear.get(key, []):
			var g := root.find_child(mesh_name, true, false) as Node3D
			check(g != null and g.visible and not spec.hide.has(mesh_name), "%s shows gear %s" % [key, mesh_name])
		if spec.has("weapon"):
			check(ResourceLoader.exists(spec.weapon), "%s weapon exists" % key)
			var skels := root.find_children("*", "Skeleton3D", true, false)
			check(skels.size() == 1 and (skels[0] as Skeleton3D).find_bone(Art.WEAPON_BONE) >= 0, "%s has bone %s" % [key, Art.WEAPON_BONE])
		root.free()
	for b in Balance.BUILDINGS:
		check(Art.BUILDING_MODELS.has(b.id) and ResourceLoader.exists(Art.BUILDING_MODELS[b.id]), "building %s has a model" % b.id)
	for path in [Art.WALL_MODEL, Art.GATE_MODEL, Art.TOWER_MODEL, Art.ARROW_MODEL] + Art.NATURE_MODELS:
		check(ResourceLoader.exists(path), "model exists: %s" % path)
	var gate: Node = (load(Art.GATE_MODEL) as PackedScene).instantiate()
	for door in Art.GATE_DOORS:
		check(gate.find_child(door, true, false) != null, "gate model has %s" % door)
	var wall: Node3D = (load(Art.WALL_MODEL) as PackedScene).instantiate()
	var wb := Art.model_aabb(wall)
	check(absf(wb.size.x - Art.WALL_MODEL_LEN) < 0.05 and absf(wb.size.y - Art.WALL_MODEL_H) < 0.05 and absf(wb.size.z - Art.WALL_MODEL_T) < 0.05, "wall model size matches Art constants: %s" % wb.size)
	gate.free()
	wall.free()
	var arrow: Node3D = (load(Art.ARROW_MODEL) as PackedScene).instantiate()
	var ab := Art.model_aabb(arrow)
	check(ab.size.y > ab.size.x and ab.size.y > ab.size.z, "arrow model long axis is Y (ARROW_PITCH_FIX): %s" % ab.size)
	arrow.free()
	for id in Art.BUILDING_MODELS:
		var bm: Node3D = (load(Art.BUILDING_MODELS[id]) as PackedScene).instantiate()
		var bb := Art.model_aabb(bm)
		check(bb.size.x > 0.0 and bb.size.z > 0.0, "building %s model has non-zero x/z size: %s" % [id, bb.size])
		bm.free()

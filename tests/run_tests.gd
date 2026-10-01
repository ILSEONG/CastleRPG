extends SceneTree
## 순수 로직 헤드리스 테스트.
## 실행: ./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd

const Balance := preload("res://scripts/balance.gd")
const GameData := preload("res://scripts/game_data.gd")
const WaveDirector := preload("res://scripts/wave_director.gd")
const GameStateScript := preload("res://scripts/game_state.gd")
const FormationScript := preload("res://scripts/formation.gd")
const Art := preload("res://scripts/art.gd")
const MeshKitScript := preload("res://scripts/mesh_kit.gd")
const TownKitScript := preload("res://scripts/town_kit.gd")
const IconsScript := preload("res://scripts/icons.gd")

class ErrorCounter extends Logger:
	var count := 0
	func _log_error(_fn: String, _file: String, _line: int, _code: String, _why: String, _notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1  # SCRIPT ERROR는 그 테스트 함수만 중단시키므로 여기서 센다

var _fails := 0
var _errors := ErrorCounter.new()


func _init() -> void:
	OS.add_logger(_errors)
	test_game_data()
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
	test_lowpoly_conversion()
	test_route()
	test_stairs_and_wall_routes()
	test_buildings_clear_stairs()
	test_is_inside()
	test_mesh_kit()
	test_castle_parts()
	test_town_recipes()
	test_economy_pending()
	test_economy_collect()
	test_economy_merchant()
	test_economy_sell()
	test_economy_save()
	test_merchant_spot()
	test_icon_shapes()
	if _errors.count > 0:
		printerr("SCRIPT ERRORS %d" % _errors.count)
	_fails += _errors.count
	if _fails > 0:
		printerr("FAILED %d" % _fails)
	else:
		print("ALL PASSED")
	quit(1 if _fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		printerr("FAIL: " + msg)


func test_game_data() -> void:
	GameData.load_tables()
	check(GameData.errors == 0, "default tables load without errors")
	var grunt := GameData.monster("grunt")
	check(grunt.hp == 60.0 and grunt.gold == 2 and GameData.monster("epic_boss").gold == 50, "monster table values")
	for key in ["hp", "atk", "speed", "range", "atk_interval", "scale", "aggro", "gold"]:
		for kind in ["grunt", "epic_boss"]:
			check(GameData.monster(kind).has(key), "monster %s has %s" % [kind, key])
	for s in range(1, 31):  # 1~30행은 예전 공식과 같다
		var r := GameData.stage(s)
		check(is_equal_approx(r.hp_mult, 1.0 + 0.25 * (s - 1)) and is_equal_approx(r.atk_mult, 1.0 + 0.15 * (s - 1)), "hp/atk mult at stage %d" % s)
		check(int(r.waves) == 3 + floori(s / 3.0) and int(r.wave_size) == 6 + 2 * s and r.idle_interval == 4.0, "waves/size/idle at stage %d" % s)
		check(is_equal_approx(r.gold_mult, 1.0 + 0.2 * (s - 1)), "gold_mult at stage %d" % s)
	var r31 := GameData.stage(31)  # 직선 연장
	var r30 := GameData.stage(30)
	var r29 := GameData.stage(29)
	check(is_equal_approx(r31.hp_mult, 2.0 * r30.hp_mult - r29.hp_mult) and is_equal_approx(GameData.stage(40).hp_mult, 1.0 + 0.25 * 39), "stage beyond table extrapolates hp_mult")
	check(int(GameData.stage(40).wave_size) == 86 and int(GameData.stage(33).waves) == 16, "extrapolated int columns round")
	check(GameData.kill_gold("grunt", 1) == 2 and GameData.kill_gold("grunt", 2) == 2 and GameData.kill_gold("grunt", 3) == 3, "kill_gold rounds (2 x 1.2 = 2.4 -> 2, 2 x 1.4 = 2.8 -> 3)")
	check(GameData.kill_gold("epic_boss", 2) == 60 and GameData.kill_gold("grunt", 31) == 14, "kill_gold boss and extrapolated stage")
	# 임시 CSV: BOM, 빈 줄, CRLF, 열 순서 바꿈
	var mp := "user://t_monsters.csv"
	var sp := "user://t_stages.csv"
	_write(mp, "\ufeffgold,id,scale,hp,atk,speed,range,atk_interval,aggro\r\n\r\n0.4,grunt,1,10,2,1,1,1,1\r\n\r\n")
	_write(sp, "\ufeffwaves,stage,wave_size,hp_mult,atk_mult,gold_mult,idle_interval\r\n3,1,6,1,1,1,4\r\n\r\n5,2,8,2,1,3,4\r\n")
	GameData.load_tables(mp, sp)
	check(GameData.errors == 0 and GameData.monster("grunt").hp == 10.0 and GameData.stage(2).hp_mult == 2.0 and int(GameData.stage(2).waves) == 5, "BOM, blank lines, CRLF and reordered columns parse the same")
	check(GameData.kill_gold("grunt", 1) == 1, "kill_gold has a minimum of 1")
	# 깨진 표: 숫자 아님, 빠진 열, stage 건너뜀. 오류 수를 세고 로거 몫은 뺀다
	var logged := _errors.count
	_write(mp, "id,hp,atk,speed,range,atk_interval,aggro,scale
grunt,60,1,1,1,1,1,1
")
	GameData.load_tables(mp, sp)
	check(GameData.errors == 1, "missing column reports one error")
	_write(mp, "id,hp,atk,speed,range,atk_interval,aggro,scale,gold\ngrunt,abc,1,1,1,1,1,1,1\n")
	GameData.load_tables(mp, sp)
	check(GameData.errors == 1, "non-numeric cell reports one error")
	_write(sp, "stage,hp_mult,atk_mult,gold_mult,waves,wave_size,idle_interval\n1,1,1,1,3,6,4\n3,1,1,1,3,6,4\n")
	GameData.load_tables(mp, sp)
	check(GameData.errors == 2, "stage gap reports an error")
	check(_errors.count - logged == 4, "table errors go through push_error")
	_errors.count = logged
	DirAccess.remove_absolute(mp)
	DirAccess.remove_absolute(sp)
	GameData.load_tables()
	check(GameData.errors == 0 and GameData.stage(1).hp_mult == 1.0, "default tables restored")


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)


func test_balance_tables() -> void:
	check(Balance.hero_slots(1) == 4, "keep level 1 gives 4 heroes")
	check(Balance.hero_slots(2) == 8, "keep level 2 gives 8 heroes")
	check(Balance.hero_slots(3) == 12, "keep level 3 gives 12 heroes")
	check(Balance.hero_slots(99) == 12, "keep level beyond table clamps to last")
	check(Balance.gate_hp_max(1) == 400.0, "gate hp at level 1")
	check(Balance.gate_hp_max(2) > Balance.gate_hp_max(1), "gate hp grows with level")


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
	check(Balance.interior_half(1) == 20.0, "interior half is 20m at keep level 1")
	check(Balance.interior_half(2) > Balance.interior_half(1), "interior grows at keep level 2")
	check(Balance.interior_half(3) > Balance.interior_half(2), "interior grows at keep level 3")
	check(Balance.interior_half(99) == Balance.interior_half(3), "interior clamps beyond table")
	check(Balance.hero_role(0) == "warrior" and Balance.hero_role(1) == "archer", "roster starts warrior, archer")
	check(Balance.hero_role(2) == "warrior" and Balance.hero_role(3) == "archer", "roster alternates")
	for role in Balance.HERO_ROLES:
		for key in ["name", "hp", "atk", "range", "atk_interval", "speed", "aggro"]:
			check(Balance.HERO_ROLES[role].has(key), "role %s has %s" % [role, key])
	check(Balance.HERO_ROLES.archer.range > Balance.HERO_ROLES.warrior.range, "archer outranges warrior")


func test_building_layout() -> void:
	var half_tiles := floori(Balance.INTERIOR_TILES[0] / 2.0)
	var allowed := Rect2i(-half_tiles + 2, -half_tiles + 2, 2 * half_tiles - 4, 2 * half_tiles - 4)  # 벽 쪽 2타일: 계단 띠 + 성문 안쪽↔계단 앞 통로
	var road_ns := Rect2i(-1, -half_tiles, 2, 2 * half_tiles)
	var road_ew := Rect2i(-half_tiles, -1, 2 * half_tiles, 2)
	var placed: Array = []
	var ids := {}
	for b in Balance.BUILDINGS:
		var r := Rect2i(b.cell, b.size)
		check(allowed.encloses(r), "%s inside level-1 interior with 2-tile wall margin (stair strip + inner lane)" % b.id)
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
	for key in ["grunt", "epic_boss"]:
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
	check(ResourceLoader.exists(Art.ARROW_MODEL), "model exists: %s" % Art.ARROW_MODEL)
	var arrow: Node3D = (load(Art.ARROW_MODEL) as PackedScene).instantiate()
	var ab := Art.model_aabb(arrow)
	check(ab.size.y > ab.size.x and ab.size.y > ab.size.z, "arrow model long axis is Y (ARROW_PITCH_FIX): %s" % ab.size)
	arrow.free()


func test_lowpoly_conversion() -> void:
	for path in [Art.HERO_MODELS.warrior.scene, Art.HERO_MODELS.archer.scene, Art.MONSTER_MODELS.grunt.scene, Art.MONSTER_MODELS.grunt.weapon,
			Art.ARROW_MODEL]:
		var root: Node = Art.instance(path)
		var surfaces := 0
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				surfaces += 1
				var mat := mi.get_active_material(i)
				var src := mi.mesh.surface_get_material(i) as BaseMaterial3D  # 원본 (덮어쓰기는 MeshInstance에만 걸린다)
				var want: Shader = Art.LOWPOLY_DOUBLE_SHADER if src != null and src.cull_mode == BaseMaterial3D.CULL_DISABLED else Art.LOWPOLY_SHADER
				var ok := (mat is ShaderMaterial and (mat as ShaderMaterial).shader == want) \
					or (mat is BaseMaterial3D and ((mat as BaseMaterial3D).emission_enabled or (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED))
				check(ok, "%s surface %s/%d is low-poly with the source's sidedness (or an emissive/transparent exception)" % [path, mi.name, i])
		check(surfaces > 0, "%s has surfaces" % path)
		root.free()
	var knight: Node = Art.instance(Art.HERO_MODELS.warrior.scene)
	var cape_mat := (knight.find_child("Knight_Cape", true, false) as MeshInstance3D).get_active_material(0) as ShaderMaterial
	check(cape_mat != null and cape_mat.shader == Art.LOWPOLY_DOUBLE_SHADER, "double-sided source (Knight cape, open mesh) uses the double-sided low-poly shader")
	knight.free()
	var a: Node = Art.instance(Art.ARROW_MODEL)
	var b: Node = Art.instance(Art.ARROW_MODEL)
	var ma: Material = (a.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).get_active_material(0)
	var mb: Material = (b.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).get_active_material(0)
	check(ma == mb, "same source material shares one low-poly material")
	a.free()
	b.free()


func test_route() -> void:
	var half := Balance.interior_half(1)
	var F = FormationScript
	check(F.side_of(Vector3(0, 0, -30)) == 0 and F.side_of(Vector3(30, 0, 1)) == 1 and F.side_of(Vector3(2, 0, 30)) == 2 and F.side_of(Vector3(-30, 0, 0)) == 3, "side_of picks the facing side")
	for side in 4:
		var dir: Vector3 = F.SIDE_DIR[side]
		check(dir.dot(F.gate_inner(half, side)) < half, "gate inner point inside the walls, side %d" % side)
		check(dir.dot(F.gate_outer(half, side)) > half + Balance.WALL_T, "gate outer point outside the walls, side %d" % side)
	var inside_a := Vector3(-6, 0, -6)
	var inside_b := Vector3(6, 0, 6)
	check(F.route(half, inside_a, inside_b) == [inside_b], "inside to inside goes straight")
	var out_n := Vector3(5, 0, -40)
	var r: Array = F.route(half, inside_a, out_n)
	check(r == [F.gate_inner(half, 0), F.gate_outer(half, 0), out_n], "inside to outside leaves through the destination's gate: %s" % [r])
	r = F.route(half, out_n, inside_a)
	check(r == [F.gate_outer(half, 0), F.gate_inner(half, 0), inside_a], "outside to inside enters through the start's gate: %s" % [r])
	var out_s := Vector3(-5, 0, 40)
	var lane: float = half - Balance.STAIR_W - F.GATE_PASS_MARGIN  # 안쪽 통로 고리 깊이 (gate_inner·stair_approach)
	var ne: Vector3 = (F.SIDE_DIR[0] + F.SIDE_DIR[1]) * lane
	var se: Vector3 = (F.SIDE_DIR[2] + F.SIDE_DIR[1]) * lane
	r = F.route(half, out_n, out_s)
	check(r == [F.gate_outer(half, 0), F.gate_inner(half, 0), ne, se, F.gate_inner(half, 2), F.gate_outer(half, 2), out_s], "outside across the castle goes gate to gate around the lane corners: %s" % [r])
	var out_n2 := Vector3(-25, 0, -40)
	check(F.route(half, out_n, out_n2) == [out_n2], "outside to outside on the same side goes straight")
	var gate_n := F.slot_position(half, 0, F.POST_GATE, 0)
	var gate_e := F.slot_position(half, 1, F.POST_GATE, 0)
	r = F.route(half, gate_n, gate_e)
	check(r == [F.gate_outer(half, 0), F.gate_inner(half, 0), ne, F.gate_inner(half, 1), F.gate_outer(half, 1), gate_e], "adjacent gate fronts route through both gates via the lane corner: %s" % [r])
	var wall_e := F.slot_position(half, 1, F.POST_WALL, 0)  # 동쪽 성벽 위 -옆(z = -4) → 계단 end -1
	var stairs_e := [F.wall_landing(half, 1, -1.0), F.stair_top(half, 1, -1.0), F.stair_bottom(half, 1, -1.0), F.stair_approach(half, 1, -1.0)]
	r = F.route(half, wall_e, out_s)
	check(r == stairs_e + [se, F.gate_inner(half, 2), F.gate_outer(half, 2), out_s], "wall top to outside goes down the stairs, then leaves through a gate: %s" % [r])
	r = F.route(half, out_s, wall_e)
	stairs_e.reverse()
	check(r == [F.gate_outer(half, 2), F.gate_inner(half, 2), se] + stairs_e + [wall_e], "outside to wall top enters through a gate, then climbs the stairs: %s" % [r])
	var mid_gate := Vector3(0, 0, -(half + Balance.WALL_T * 0.75))  # 성문 통로 바깥쪽 절반 = 안
	var field_n := Vector3(-40, 0, -41)
	r = F.route(half, mid_gate, field_n)
	check(r == [F.gate_inner(half, 0), F.gate_outer(half, 0), field_n], "gate-passage point counts as inside and leaves via gate inner then outer, not through the wall: %s" % [r])


func test_stairs_and_wall_routes() -> void:
	var F = FormationScript
	var half := Balance.interior_half(1)
	check(half == 20.0, "interior half is 20m at keep level 1 (1.25x)")
	for side in 4:
		var dir: Vector3 = F.SIDE_DIR[side]
		var pp: Vector3 = F.perp(side)
		for e in [-1.0, 1.0]:
			var top: Vector3 = F.stair_top(half, side, e)
			var bot: Vector3 = F.stair_bottom(half, side, e)
			var land: Vector3 = F.wall_landing(half, side, e)
			check(is_equal_approx(top.y, Balance.WALL_H) and bot.y == 0.0 and is_equal_approx(land.y, Balance.WALL_H), "stair heights side %d end %d" % [side, e])
			check(dir.dot(top) < half and dir.dot(bot) < half and dir.dot(top) > half - Balance.STAIR_W, "stairs sit in the strip inside the wall")
			check(absf(pp.dot(top)) > Balance.GATE_W / 2.0 and absf(pp.dot(bot)) > absf(pp.dot(top)), "stairs beside the gate, climbing toward it")
			check(F.region(half, land) == F.REGION_WALL and F.region(half, bot) == F.REGION_INSIDE, "landing is wall top, bottom is inside ground")
			var app: Vector3 = F.stair_approach(half, side, e)
			check(app.y == 0.0 and dir.dot(app) < half - Balance.STAIR_W and pp.dot(app) * e > absf(pp.dot(bot)) and not _in_stair_footprint(half, app),
				"stair approach is on the ground off the strip, beyond the stair's foot (side %d end %d)" % [side, e])
		check(dir.dot(F.gate_inner(half, side)) < half - Balance.STAIR_W, "gate inner point is off the stair strip, side %d" % side)
	var wall_n := F.slot_position(half, 0, F.POST_WALL, 1)   # 북쪽 성벽 위, +옆
	var inside := Vector3(6, 0, 6)
	var r: Array = F.route(half, inside, wall_n)
	var e_n := 1.0 if F.perp(0).dot(wall_n) >= 0.0 else -1.0
	check(r.size() >= 5 and r[-5] == F.stair_approach(half, 0, e_n) and r[-4] == F.stair_bottom(half, 0, e_n) and r[-3] == F.stair_top(half, 0, e_n) and r[-2] == F.wall_landing(half, 0, e_n) and r[-1] == wall_n, "inside to wall top climbs the stairs: %s" % [r])
	var out_s := Vector3(-5, 0, 45)
	r = F.route(half, wall_n, out_s)
	check(r[0] == F.wall_landing(half, 0, e_n) and r[1] == F.stair_top(half, 0, e_n) and r[2] == F.stair_bottom(half, 0, e_n) and r[3] == F.stair_approach(half, 0, e_n), "wall top to outside goes down the stairs first: %s" % [r])
	check(r.has(F.gate_inner(half, 2)) and r.has(F.gate_outer(half, 2)) and r[-1] == out_s, "then leaves through a gate")
	var wall_n2 := F.slot_position(half, 0, F.POST_WALL, 0)
	check(F.route(half, wall_n, wall_n2) == [wall_n2], "same-side wall top walks straight")
	var wall_e := F.slot_position(half, 1, F.POST_WALL, 0)
	r = F.route(half, wall_n, wall_e)
	var e_e := 1.0 if F.perp(1).dot(wall_e) >= 0.0 else -1.0
	check(r[2] == F.stair_bottom(half, 0, e_n) and r[3] == F.stair_approach(half, 0, e_n) and r[-5] == F.stair_approach(half, 1, e_e) and r[-4] == F.stair_bottom(half, 1, e_e) and r[-1] == wall_e, "wall top to another side's wall top goes down and up: %s" % [r])
	var out_n := Vector3(5, 0, -45)
	r = F.route(half, out_n, wall_n)
	check(r[0] == F.gate_outer(half, 0) and r[1] == F.gate_inner(half, 0) and r[-5] == F.stair_approach(half, 0, e_n) and r[-4] == F.stair_bottom(half, 0, e_n), "outside to wall top enters a gate then climbs: %s" % [r])
	# 어떤 구간도 성벽 띠를 곧장 오르내리지 않는다: 높이가 바뀌는 구간은 계단 윗단↔아랫단, 윗단↔landing 뿐.
	# 지상 구간(양 끝 y=0)은 계단 발판(띠 × 계단 길이)을 지나지 않는다 — 0.1 m 간격으로 샘플.
	var pairs := [[inside, wall_n], [wall_n, out_s], [wall_n, wall_e], [out_n, wall_n]]
	for s in 4:
		for slot in 2:  # WALL_TOP_SLOTS[0] = -4 (end -1), [1] = +4 (end +1)
			var w := F.slot_position(half, s, F.POST_WALL, slot)
			pairs.append([inside, w])
			pairs.append([w, inside])
	for pair in pairs:
		var pts: Array = [pair[0]] + F.route(half, pair[0], pair[1])
		for i in range(1, pts.size()):
			var a: Vector3 = pts[i - 1]
			var b: Vector3 = pts[i]
			if absf(a.y) < 0.01 and absf(b.y) < 0.01:
				var hit := false
				for q in _leg_samples(a, b):
					hit = hit or _in_stair_footprint(half, q)
				check(not hit,"ground leg stays off every stair footprint (%s -> %s, route %s -> %s)" % [a, b, pair[0], pair[1]])
			if absf(a.y - b.y) > 0.01:
				var ok := false
				for s in 4:
					for e in [-1.0, 1.0]:
						var st: Vector3 = F.stair_top(half, s, e)
						var sb: Vector3 = F.stair_bottom(half, s, e)
						if (a.is_equal_approx(st) and b.is_equal_approx(sb)) or (a.is_equal_approx(sb) and b.is_equal_approx(st)):
							ok = true
				check(ok, "height changes only on a stair flight (%s -> %s)" % [a, b])


## 계단 발판: 면의 띠(성벽 안쪽 STAIR_W) × 성문 옆 GATE_W/2 + STAIR_GAP .. + STAIR_RUN (양쪽 end). 경계선 위는 밖(아랫단이 경계에 있다).
func _in_stair_footprint(half: float, p: Vector3) -> bool:
	var lo := Balance.GATE_W / 2.0 + Balance.STAIR_GAP
	for s in 4:
		var depth: float = FormationScript.SIDE_DIR[s].dot(p)
		var along: float = absf(FormationScript.perp(s).dot(p))
		if depth > half - Balance.STAIR_W + 0.01 and depth < half - 0.01 and along > lo + 0.01 and along < lo + Balance.STAIR_RUN - 0.01:
			return true
	return false


## a → b 수평 선분 위 0.1 m 간격 샘플(양 끝 포함).
func _leg_samples(a: Vector3, b: Vector3) -> Array:
	var n := ceili(FormationScript.flat_distance(a, b) / 0.1)
	var out := []
	for k in range(n + 1):
		out.append(a.lerp(b, float(k) / maxf(n, 1)))
	return out


## 건물 부지(성채 포함)는 계단·성문 통과 지점과 계단 발판을 비우고, 모든 자리 사이 경로(면을 넘나드는 것 포함)의 지상 구간은 부지·계단 발판을 지나지 않는다.
func test_buildings_clear_stairs() -> void:
	var F = FormationScript
	var half := Balance.interior_half(1)
	var lo := Balance.GATE_W / 2.0 + Balance.STAIR_GAP
	var plots := {}  # id -> Rect2 (x, z)
	for b in Balance.BUILDINGS:
		plots[b.id] = Rect2(Vector2(b.cell) * Balance.TILE, Vector2(b.size) * Balance.TILE)
	for s in 4:
		var dir: Vector3 = F.SIDE_DIR[s]
		var pp: Vector3 = F.perp(s)
		for e in [-1.0, 1.0]:
			var c1: Vector3 = dir * (half - Balance.STAIR_W) + pp * (e * lo)
			var c2: Vector3 = dir * half + pp * (e * (lo + Balance.STAIR_RUN))
			var foot := Rect2(Vector2(c1.x, c1.z), Vector2.ZERO).expand(Vector2(c2.x, c2.z))
			for id in plots:
				var plot: Rect2 = plots[id]
				for p in [F.stair_approach(half, s, e), F.gate_inner(half, s), F.stair_bottom(half, s, e)]:
					check(not plot.has_point(Vector2(p.x, p.z)), "%s plot does not contain stair/gate point %s" % [id, p])
				check(not plot.intersects(foot), "%s plot does not overlap the stair footprint (side %d end %d)" % [id, s, e])
	# 모든 면의 성문 앞·성벽 위 자리와 성문 안쪽 사이 모든 경로(면을 넘나드는 것 포함): 지상 구간은 부지도 계단 발판도 지나지 않는다.
	var inner := {}  # id -> 경계선을 뺀 부지
	for id in plots:
		inner[id] = (plots[id] as Rect2).grow(-0.01)
	for level in [1, 2, 3]:
		var h := Balance.interior_half(level)
		var spots: Array = []
		for s in 4:
			spots.append(F.gate_inner(h, s))
			for post in [F.POST_GATE, F.POST_WALL]:
				for slot in F.capacity(post):
					spots.append(F.slot_position(h, s, post, slot))
		var bad_plot: Array = []
		var bad_stair: Array = []
		for from in spots:
			for to in spots:
				if from == to:
					continue
				var pts: Array = [from] + F.route(h, from, to)
				for i in range(1, pts.size()):
					var a: Vector3 = pts[i - 1]
					var b: Vector3 = pts[i]
					if absf(a.y) > 0.01 or absf(b.y) > 0.01:
						continue
					for q in _leg_samples(a, b):
						for id in plots:
							if (inner[id] as Rect2).has_point(Vector2(q.x, q.z)):
								bad_plot.append("%s: %s -> %s (route %s -> %s)" % [id, a, b, from, to])
						if _in_stair_footprint(h, q):
							bad_stair.append("%s -> %s (route %s -> %s)" % [a, b, from, to])
		check(bad_plot.is_empty(), "level %d: no ground leg between any two spots passes a building plot (%d hit samples, first %s)" % [level, bad_plot.size(), bad_plot.slice(0, 1)])
		check(bad_stair.is_empty(), "level %d: no ground leg between any two spots passes a stair footprint (%d hit samples, first %s)" % [level, bad_stair.size(), bad_stair.slice(0, 1)])


func test_is_inside() -> void:
	var half := Balance.interior_half(1)
	check(FormationScript.is_inside(half, Vector3(0, 0, -(half + Balance.WALL_T - 0.1))), "just inside the outer wall face counts as inside")
	check(not FormationScript.is_inside(half, Vector3(0, 0, -(half + Balance.WALL_T + 0.1))), "just outside the outer wall face counts as outside")
	check(FormationScript.is_inside(half, Vector3(0, Balance.WALL_H, -(half + Balance.WALL_T / 2.0))), "wall top counts as inside")


func test_mesh_kit() -> void:
	var k = MeshKitScript.new()
	k.box(Vector3.ZERO, Vector3(2, 1, 3), Color.RED)
	check(k.triangle_count() == 10, "box without bottom = 5 faces = 10 triangles")
	var m: ArrayMesh = k.commit()
	var arrays := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	check(verts.size() == 30 and cols.size() == 30 and cols[0] == Color.RED, "unshared vertices with vertex colours")
	var aabb := m.get_aabb()
	check(aabb.position.is_equal_approx(Vector3(-1, 0, -1.5)) and aabb.size.is_equal_approx(Vector3(2, 1, 3)), "box bounds")
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]  # 윗면 삼각형 2개(정점 0~5) 다음이 옆면
	check(nrm[0].distance_to(Vector3.UP) < 0.001 and absf(nrm[6].y) < 0.001 and absf(nrm[6].length() - 1.0) < 0.001,
		"flat per-face normals (not averaged over shared corners): top %s, side %s" % [nrm[0], nrm[6]])
	# 감기: 모든 삼각형이 같은 규약(바깥 기준)으로 감겨 있다. 상자는 넘긴 순서가 이미 규약대로라
	# 뒤집기 분기를 타지 않으므로, 한 경사면을 반대 순서로 넘기는 박공지붕도 함께 본다.
	check(_wound_outward(verts, Vector3(0, 0.5, 0)), "every box triangle wound front-facing outward")
	var g = MeshKitScript.new()
	g.gable(Vector3.ZERO, Vector3(2, 0, 2), 1.0, Color.BLUE)
	var gv: PackedVector3Array = g.commit().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(_wound_outward(gv, Vector3(0, 0.3, 0)), "every gable triangle wound front-facing outward")
	var pr = MeshKitScript.new()
	pr.prism_n(Vector3.ZERO, 6, 1.0, 0.7, 2.0, Color.GREEN, 0.3)
	check(_wound_outward(pr.commit().surface_get_arrays(0)[Mesh.ARRAY_VERTEX], Vector3(0, 1.0, 0)), "every prism_n (frustum) triangle wound front-facing outward")
	var cn = MeshKitScript.new()
	cn.cone(Vector3.ZERO, 7, 1.0, 2.0, Color.GREEN)
	check(_wound_outward(cn.commit().surface_get_arrays(0)[Mesh.ARRAY_VERTEX], Vector3(0, 0.5, 0)), "every cone triangle wound front-facing outward")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var rk = MeshKitScript.new()
	rk.rock(Vector3(0, 0.3, 0), 1.0, Color.GRAY, rng, 0.7, 0.0)  # 가장 낮은 꼭짓점 ≤ 0.3 − 0.85×0.7×0.8 < 0 → 바닥에 눌린다
	var rm: ArrayMesh = rk.commit()
	check(rk.triangle_count() == 20 and _wound_outward(rm.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], Vector3(0, 0.3, 0)), "rock: 20 triangles, all wound front-facing outward")
	check(is_equal_approx(rm.get_aabb().position.y, 0.0), "rock floor_y flattens its bottom onto the floor: %s" % rm.get_aabb())


## 볼록 도형의 모든 삼각형이 안쪽 점 center 기준 바깥을 앞면(MeshKit 규약)으로 감겼는가.
func _wound_outward(verts: PackedVector3Array, center: Vector3) -> bool:
	for i in range(0, verts.size(), 3):
		var a := verts[i]
		var b := verts[i + 1]
		var c := verts[i + 2]
		var ccw_out := (b - a).cross(c - a).dot((a + b + c) / 3.0 - center) > 0.0
		if ccw_out == MeshKitScript.CLOCKWISE_FRONT:
			return false
	return true


func test_castle_parts() -> void:
	for pair in [["wall_run", TownKitScript.wall_run(10.0)], ["gatehouse", TownKitScript.gatehouse()], ["gate_doors", TownKitScript.gate_doors()], ["corner_tower", TownKitScript.corner_tower()], ["stairs", TownKitScript.stairs()]]:
		var m: ArrayMesh = pair[1]
		check(m.get_surface_count() == 1 and m.get_aabb().size.length() > 0.5, "%s has one non-empty surface" % pair[0])
	var sm: ArrayMesh = TownKitScript.stairs()
	var st: AABB = sm.get_aabb()
	check(is_equal_approx(st.size.x, Balance.STAIR_RUN) and is_equal_approx(st.end.y, Balance.WALL_H) and is_equal_approx(st.size.z, Balance.STAIR_W), "stairs span run x wall height x stair width: %s" % st)
	# 높은 쪽이 +X(윗단)여야 castle.gd 배치와 맞는다: 가장 높은 정점들은 마지막 단 칸 안, 그중 하나는 x = STAIR_RUN.
	var sv: PackedVector3Array = sm.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var d := Balance.STAIR_RUN / Balance.STAIR_STEPS
	var top_xs: Array = []
	for v in sv:
		if is_equal_approx(v.y, Balance.WALL_H):
			top_xs.append(v.x)
	check(not top_xs.is_empty() and top_xs.min() > Balance.STAIR_RUN - d - 0.01 and is_equal_approx(top_xs.max(), Balance.STAIR_RUN), "stair mesh is highest at x = STAIR_RUN (top end): %s" % [top_xs])
	# 아랫단(x=0, y=0) → 윗단(x=RUN, y=WALL_H) 직선 경사를 걷는 발은 디딤판 아래로 반 단 넘게 묻히지 않는다.
	var worst := 0.0
	for i in 601:
		var x := Balance.STAIR_RUN * i / 600.0
		var tread := 0.0
		for t in range(0, sv.size(), 3):
			var a := sv[t]
			if is_equal_approx(a.y, sv[t + 1].y) and is_equal_approx(a.y, sv[t + 2].y) and x >= minf(a.x, minf(sv[t + 1].x, sv[t + 2].x)) - 0.001 and x <= maxf(a.x, maxf(sv[t + 1].x, sv[t + 2].x)) + 0.001:
				tread = maxf(tread, a.y)
		worst = maxf(worst, tread - Balance.WALL_H * x / Balance.STAIR_RUN)
	check(worst <= Balance.WALL_H / Balance.STAIR_STEPS / 2.0 + 0.001, "feet on the straight stair slope sink at most half a riser: %.3f m" % worst)


## 건물 레시피는 부지 안·바닥 위·부지 가운데, 자연물·산은 한 표면으로 땅 근처에 놓인다.
func test_town_recipes() -> void:
	for b in Balance.BUILDINGS:
		var m: ArrayMesh = TownKitScript.building(b.id)
		var box := m.get_aabb()
		var plot := Vector2(b.size.x * Balance.TILE - Art.BUILDING_GAP, b.size.y * Balance.TILE - Art.BUILDING_GAP)
		check(box.size.x <= plot.x + 0.01 and box.size.z <= plot.y + 0.01, "%s fits its plot: %s vs %s" % [b.id, box.size, plot])
		check(absf(box.position.y) < 0.01 and box.size.y > 1.0, "%s stands on the ground" % b.id)
		check(absf(box.get_center().x) < 0.6 and absf(box.get_center().z) < 0.6, "%s centred on its plot" % b.id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for f in [TownKitScript.tree_pine, TownKitScript.tree_round, TownKitScript.bush, TownKitScript.rock_cluster, TownKitScript.mountain]:
		var m: ArrayMesh = f.call(rng)
		check(m.get_surface_count() == 1 and m.get_aabb().position.y > -0.3, "%s is one surface resting near the ground" % f.get_method())


# --- 경제 (개정 7) ---
const EconomyScript := preload("res://scripts/economy.gd")
const ECON_TMP := "user://test_economy_save.json"


func _econ(now: float):
	var e = EconomyScript.new()
	e.save_path = ""
	e.reset(now)
	return e


func test_economy_pending() -> void:
	check(EconomyScript.rate_per_min("wood", 1) == 10 and EconomyScript.rate_per_min("stone", 3) == 15, "rate = per_min x level")
	check(EconomyScript.pending_amount("wood", 1, 59.9) == 0, "pending: under a minute is 0")
	check(EconomyScript.pending_amount("wood", 1, 119.9) == 10, "pending floors minutes")
	check(EconomyScript.pending_amount("stone", 2, 600.0) == 100, "pending scales with level")
	check(EconomyScript.pending_amount("wood", 1, 720 * 60.0) == 7200 and EconomyScript.pending_amount("wood", 1, 99999999.0) == 7200, "pending capped at 720 min")
	check(EconomyScript.pending_amount("wood", 1, -500.0) == 0, "pending: negative elapsed is 0")
	check(EconomyScript.res_of("lumber") == "wood" and EconomyScript.res_of("quarry") == "stone" and EconomyScript.res_of("farm") == "food" and EconomyScript.res_of("keep") == "", "res_of maps resource buildings only")


func test_economy_collect() -> void:
	var e = _econ(1000.0)
	e.last_collect.lumber = 1000.0 - 150.0  # 2분 30초
	check(e.collect("lumber", 1000.0) == 20 and e.res.wood == 20, "collect adds 2 min of wood")
	check(is_equal_approx(e.last_collect.lumber, 1000.0 - 30.0), "collect keeps the leftover 30 s: %s" % e.last_collect.lumber)
	check(e.collect("lumber", 1000.0) == 0 and is_equal_approx(e.last_collect.lumber, 970.0) and e.res.wood == 20, "collect with nothing pending changes nothing")
	e.last_collect.quarry = 1000.0 - 800 * 60.0  # 상한 초과
	check(e.collect("quarry", 1000.0) == 720 * 5 and e.last_collect.quarry == 1000.0, "collect at the cap snaps last_collect to now")
	e.last_collect.farm = 5000.0  # 시계를 되돌림
	check(e.collect("farm", 1000.0) == 0 and e.last_collect.farm == 1000.0, "collect with negative elapsed gives 0 and restarts from now")
	e.last_collect.farm = 1000.0 - 4 * 60.0
	check(not e.show_badge("farm", 1000.0), "no badge under 5 minutes")
	e.last_collect.farm = 1000.0 - 5 * 60.0
	check(e.show_badge("farm", 1000.0) and not e.show_badge("keep", 1000.0), "badge at 5 minutes, never on non-resource buildings")
	e.free()


func test_economy_merchant() -> void:
	var h := 480000
	check(EconomyScript.merchant_rate(h) == EconomyScript.merchant_rate(EconomyScript.hour_index(h * 3600.0 + 3599.0)), "rate is the same within an hour slot")
	check(EconomyScript.hour_index(7199.9) == 1 and EconomyScript.hour_index(7200.0) == 2, "hour_index floors on the hour")
	var allowed := [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 2.0]
	var counts := {}
	var n := 200000
	var bad := 0
	for i in n:
		var r := EconomyScript.merchant_rate(i)
		if not allowed.has(r):
			bad += 1
		counts[r] = counts.get(r, 0) + 1
	check(bad == 0, "every rate is one of the 12 exact values (%d off)" % bad)
	var jack: float = counts.get(2.0, 0) / float(n)
	check(absf(jack - 0.05) <= 0.005, "jackpot share %.4f is 5%% +- 0.5%%" % jack)
	var ratio: float = counts.get(0.5, 0) / float(maxi(1, counts.get(1.5, 0)))
	check(absf(ratio - 3.0) <= 0.3, "P(0.5)/P(1.5) = %.2f is 3 +- 0.3" % ratio)
	var e = _econ(3600.0 * h + 100.0)
	check(is_equal_approx(e.seconds_to_next_rate(3600.0 * h + 100.0), 3500.0) and e.current_rate(3600.0 * h + 100.0) == EconomyScript.merchant_rate(h), "seconds_to_next_rate / current_rate follow the hour slot")
	e.free()


func test_economy_sell() -> void:
	check(EconomyScript.sell_value("wood", 7, 0.5) == 3 and EconomyScript.sell_value("stone", 7, 1.3) == 18 and EconomyScript.sell_value("food", 100, 1.1) == 110 and EconomyScript.sell_value("wood", 10, 2.0) == 20, "sell_value floors (no float error)")
	var now := 3600.0 * 480000.0
	var e = _econ(now)
	var rate: float = e.current_rate(now)
	e.res.wood = 40
	e.res.stone = 9
	e.res.food = 13
	var g: int = e.sell("wood", now)
	check(g == EconomyScript.sell_value("wood", 40, rate) and e.res.wood == 0 and e.gold == g, "sell zeroes the resource and adds gold")
	var before: int = e.gold
	var g2: int = e.sell_all(now)
	check(e.res.stone == 0 and e.res.food == 0 and e.gold == before + g2 and g2 == EconomyScript.sell_value("stone", 9, rate) + EconomyScript.sell_value("food", 13, rate), "sell_all sells everything")
	e.add_gold(5)
	check(e.gold == before + g2 + 5, "add_gold")
	e.free()


func test_economy_save() -> void:
	var now := 1.8e9
	var e = _econ(now)
	e.save_path = ECON_TMP
	e.gold = 77
	e.res.wood = 12
	e.last_collect.lumber = now - 90.5
	e.levels.farm = 3
	e.save()
	e.gold = 78
	e.save()  # 이미 있는 파일 위로 다시 저장(임시 파일 → 바꿔 끼우기)
	check(not FileAccess.file_exists(ECON_TMP + ".tmp"), "save leaves no temp file behind")
	var e2 = _econ(0.0)
	e2.save_path = ECON_TMP
	e2.load_save(now + 5.0)
	check(e2.gold == 78 and e2.res.wood == 12 and e2.res.wood is int and e2.levels.farm == 3 and e2.levels.farm is int and is_equal_approx(e2.last_collect.lumber, now - 90.5), "save round-trips with int types restored")
	for junk in ["{not json", "[1,2]", "{\"version\":1,\"gold\":5}", "{\"version\":2,\"gold\":1,\"res\":{},\"last_collect\":{},\"levels\":{}}"]:
		var f := FileAccess.open(ECON_TMP, FileAccess.WRITE)
		f.store_string(junk)
		f.close()
		e2.gold = 99
		e2.load_save(now)
		check(e2.gold == 0 and e2.res.wood == 0 and e2.levels.lumber == 1 and e2.last_collect.lumber == now, "corrupt save (%s) falls back to defaults" % junk)
	DirAccess.remove_absolute(ECON_TMP)
	e2.gold = 99
	e2.load_save(now)
	check(e2.gold == 0, "missing save file gives defaults")
	e2.save_path = ""
	e2.gold = 5
	e2.save()
	check(not FileAccess.file_exists(ECON_TMP), "save_path empty writes no file")
	e.free()
	e2.free()


## 상인(반경 0.6 m)과 수레(AABB)는 건물 부지·십자 도로·안쪽 통로 고리(깊이 half−3, 레벨 1~3)를 침범하지 않고, 수레는 크기 한계 안.
func test_merchant_spot() -> void:
	var box := TownKitScript.merchant_cart().get_aabb()
	check(box.size.x <= 2.4 and box.size.z <= 1.6 and box.size.y <= 2.6, "cart fits 2.4 x 1.6 x 2.6: %s" % box.size)
	check(absf(box.position.y) < 0.01 and absf(box.get_center().x) < 0.2 and absf(box.get_center().z) < 0.2, "cart origin is bottom centre: %s" % box)
	var cart_c: Vector3 = Balance.MERCHANT_POS + Balance.MERCHANT_CART_OFFSET
	var r := Balance.MERCHANT_RADIUS
	var rects := [  # 상인 사각형, 수레 사각형 (x, z)
		Rect2(Balance.MERCHANT_POS.x - r, Balance.MERCHANT_POS.z - r, 2.0 * r, 2.0 * r),
		Rect2(cart_c.x + box.position.x, cart_c.z + box.position.z, box.size.x, box.size.z),
	]
	check(not rects[0].intersects(rects[1]), "merchant and cart do not overlap")
	for rc in rects:
		for b in Balance.BUILDINGS:
			var plot := Rect2(Vector2(b.cell) * Balance.TILE, Vector2(b.size) * Balance.TILE)
			check(not rc.intersects(plot), "merchant spot %s clear of %s plot" % [rc, b.id])
		var off_x: bool = rc.position.x >= 2.0 or rc.end.x <= -2.0
		var off_z: bool = rc.position.y >= 2.0 or rc.end.y <= -2.0
		check(off_x and off_z, "merchant spot %s off the cross roads (tiles -1..0 = +-2 m)" % rc)
		# 사각형 안 |x|, |z|의 범위(축을 걸치지 않음 — 위 검사) → max(|x|,|z|) 범위
		var ax := [minf(absf(rc.position.x), absf(rc.end.x)), maxf(absf(rc.position.x), absf(rc.end.x))]
		var az := [minf(absf(rc.position.y), absf(rc.end.y)), maxf(absf(rc.position.y), absf(rc.end.y))]
		for level in [1, 2, 3]:
			var lane := Balance.interior_half(level) - Balance.STAIR_W - FormationScript.GATE_PASS_MARGIN
			var lo: float = maxf(ax[0], az[0])
			var hi: float = maxf(ax[1], az[1])
			check(hi < lane - 1.0 or lo > lane + 1.0, "merchant spot %s clear of level %d lane ring (depth %.1f)" % [rc, level, lane])


## 아이콘 네 종류 모두 도형이 있고(다각형 ≥ 3점, 단위 박스 안), 모르는 종류는 비어 있다. (그리기 호출은 _draw 안에서만 가능해 도형 단위로 검사)
func test_icon_shapes() -> void:
	for kind in IconsScript.KINDS:
		var shapes: Array = IconsScript.shapes(kind)
		check(shapes.size() >= 2, "icon %s has shapes" % kind)
		for s in shapes:
			check(s[0].size() >= 3, "icon %s polygon has >= 3 points" % kind)
			for p in s[0]:
				check(absf(p.x) <= 0.5 and absf(p.y) <= 0.5, "icon %s point %s inside the unit box" % [kind, p])
	check(IconsScript.shapes("nope").is_empty(), "unknown icon kind draws nothing")

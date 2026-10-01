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
const LowpolyBoxScript := preload("res://scripts/lowpoly_box.gd")
const UiKit := preload("res://scripts/ui_kit.gd")
const HpBarsScript := preload("res://scripts/hp_bars.gd")
const HeroCardScript := preload("res://scripts/hero_card.gd")

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
	test_game_tables()
	test_apply_remote()
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
	test_economy_online()
	test_merchant_spot()
	test_icon_shapes()
	test_lowpoly_box()
	test_hp_bars_batch()
	test_hero_card_geometry()
	test_gold_tenths()
	test_heroes_table()
	test_skill_formulas()
	test_deploy_and_stars()
	test_gate_repair()
	test_fx_meshes()
	test_gacha_offline()
	test_roster()
	test_skill_text()
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
	for s in range(1, 31):  # 1~30행은 직선 공식(개정 10: HP·공격력 10%, 골드 20%)
		var r := GameData.stage(s)
		check(is_equal_approx(r.hp_mult, 1.0 + 0.10 * (s - 1)) and is_equal_approx(r.atk_mult, 1.0 + 0.10 * (s - 1)), "hp/atk mult at stage %d" % s)
		check(int(r.waves) == 3 + floori(s / 3.0) and int(r.wave_size) == 6 + 2 * s and r.idle_interval == 4.0, "waves/size/idle at stage %d" % s)
		check(is_equal_approx(r.gold_mult, 1.0 + 0.2 * (s - 1)), "gold_mult at stage %d" % s)
	var r31 := GameData.stage(31)  # 직선 연장
	var r30 := GameData.stage(30)
	var r29 := GameData.stage(29)
	check(is_equal_approx(r31.hp_mult, 2.0 * r30.hp_mult - r29.hp_mult) and is_equal_approx(GameData.stage(40).hp_mult, 1.0 + 0.10 * 39), "stage beyond table extrapolates hp_mult")
	check(int(GameData.stage(40).wave_size) == 86 and int(GameData.stage(33).waves) == 14, "extrapolated int columns follow the 12-row slope and round (waves 33 = 14, same as the old 3 + floor(s/3))")
	check(GameData.kill_gold_tenths("grunt", 1) == 20 and GameData.kill_gold_tenths("grunt", 2) == 24 and GameData.kill_gold_tenths("grunt", 3) == 28, "kill_gold_tenths keeps one decimal (2 x 1.2 = 2.4 -> 24, 2 x 1.4 = 2.8 -> 28)")
	check(GameData.kill_gold_tenths("epic_boss", 2) == 600 and GameData.kill_gold_tenths("grunt", 31) == 140, "kill_gold_tenths boss and extrapolated stage")
	# 임시 CSV: BOM, 빈 줄, CRLF, 열 순서 바꿈
	var mp := "user://t_monsters.csv"
	var sp := "user://t_stages.csv"
	_write(mp, "\ufeffgold,id,scale,hp,atk,speed,range,atk_interval,aggro\r\n\r\n0.04,grunt,1,10,2,1,1,1,1\r\n5,epic_boss,2,50,5,1,1,1,1\r\n\r\n")
	_write(sp, "\ufeffwaves,stage,wave_size,hp_mult,atk_mult,gold_mult,idle_interval\r\n3,1,6,1,1,1,4\r\n\r\n5,2,8,2,1,3,4\r\n")
	GameData.load_tables(mp, sp)
	check(GameData.errors == 0 and GameData.monster("grunt").hp == 10.0 and GameData.stage(2).hp_mult == 2.0 and int(GameData.stage(2).waves) == 5, "BOM, blank lines, CRLF and reordered columns parse the same")
	check(GameData.kill_gold_tenths("grunt", 1) == 1, "kill_gold_tenths has a minimum of 1")
	# 깨진 표: 숫자 아님, 빠진 열, stage 건너뜀. 오류 수를 세고 로거 몫은 뺀다
	var logged := _errors.count
	_write(mp, "id,hp,atk,speed,range,atk_interval,aggro,scale\ngrunt,60,1,1,1,1,1,1\n")
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
	check(GameData.hero_slots(1) == 4, "keep level 1 gives 4 heroes")
	check(GameData.hero_slots(2) == 8, "keep level 2 gives 8 heroes")
	check(GameData.hero_slots(3) == 12, "keep level 3 gives 12 heroes")
	check(GameData.hero_slots(99) == 12, "keep level beyond table clamps to last")
	check(GameData.gate_hp_max(1) == 400.0, "gate hp at level 1")
	check(GameData.gate_hp_max(2) > GameData.gate_hp_max(1), "gate hp grows with level")


func test_game_tables() -> void:
	GameData.load_tables()
	check(GameData.errors == 0, "default tables incl. heroes/resources/config load without errors")
	# Balance에서 옮긴 값 — 이전 상수와 같다(하드코딩 기대값)
	var heroes := GameData.heroes()
	check(heroes.size() == 22 and heroes[0].id == "arteon" and heroes[21].id == "jack", "heroes keep file order")
	var w := GameData.hero("hans")
	check(w.name == "한스" and w.title == "민병대 검사" and w.grade == "R" and w.role == "melee" and w.model == "Knight" and w.gear == "1H_Sword" \
		and w.color == "#95A5A6" and w.hp == 440.0 and w.atk == 30.0 and w.range == 1.8 and w.atk_interval == 0.8 and w.speed == 6.0 and w.aggro == 8.0 \
		and w.skills == {"lifesteal": [10.0, 0.0, 0.0]}, "hans row")
	var a := GameData.hero("arteon")
	check(a.skills == {"heal_aura": [6.0, 6.0, 8.0], "dmg_reduce": [25.0, 0.0, 0.0]} and a.desc.begins_with("성문 앞을"), "arteon row: two skills, empty numbers are 0, desc")
	check(GameData.hero("ignis").skills.size() == 1, "an empty skill2 is no skill")
	check(GameData.hero("nobody").is_empty(), "unknown hero is empty")
	var res := GameData.resources()
	check(res.size() == 3 and res[0].id == "wood" and res[1].id == "stone" and res[2].id == "food", "resources keep file order")
	var st := GameData.resource("stone")
	check(st.name == "석재" and st.building == "quarry" and st.per_min == 5.0 and st.price == 2.0, "stone row = old RESOURCES")
	check(GameData.resource("wood").building == "lumber" and GameData.resource("food").per_min == 10.0 and GameData.resource("food").building == "farm", "wood/food rows")
	check(GameData.resource_of_building("farm") == "food" and GameData.resource_of_building("keep") == "", "resource_of_building")
	var nums := {"castle_hp": 1000.0, "gate_hp_per_level": 400.0, "max_live_monsters": 120.0, "countdown_sec": 3.0, "result_sec": 2.0,
		"wave_gap_sec": 8.0, "spawn_spacing_sec": 0.5, "accum_cap_min": 720.0, "badge_min": 5.0, "merchant_jackpot_p": 0.05,
		"merchant_jackpot_rate": 2.0, "merchant_rate_min": 0.5, "merchant_rate_max": 1.5, "merchant_rate_step": 0.1,
		"merchant_low_high_ratio": 3.0, "kill_rate_cap": 5.0}
	for key in nums:
		check(GameData.config_num(key) == nums[key], "config %s = %s" % [key, nums[key]])
	check(GameData.config_list("hero_slots") == [4.0, 8.0, 12.0], "config_list parses numbers")
	check(GameData.config_list("starter_heroes") == ["hans", "ella", "dorik", "nina"], "config_list keeps strings")
	check(GameData.config_list("nope").is_empty() and GameData.config_num("nope") == 0.0, "unknown config key is empty / 0")
	check(GameData.config_num("hero_max_stars") == 5.0 and GameData.config_num("hero_star_bonus") == 0.1 and GameData.config_num("gacha_cost_10") == 2700.0, "hero/gacha config")
	# 깨진 config 파일: 필수 키 빠짐
	var logged := _errors.count
	var cp := "user://t_config.csv"
	_write(cp, "key,value\ncastle_hp,1000\nhero_slots,4|8|12\nstarter_heroes,hans|ella\n")
	GameData.load_tables(GameData.MONSTERS_PATH, GameData.STAGES_PATH, GameData.HEROES_PATH, GameData.RESOURCES_PATH, cp)
	check(GameData.errors == GameData.CONFIG_NUM_KEYS.size() - 1, "config file missing keys reports one error per key")
	_errors.count = logged
	DirAccess.remove_absolute(cp)
	GameData.load_tables()
	check(GameData.errors == 0, "default tables restored after config test")


func _payload() -> Dictionary:
	var stages := []
	for s in range(1, 31):
		var r := GameData.stage(s).duplicate()
		stages.append(r)
	var cfg := {}
	for k in GameData.CONFIG_NUM_KEYS + GameData.CONFIG_LIST_KEYS:
		cfg[k] = String(GameData._config[k])
	return {"version": "t", "monsters": [GameData.monster("grunt").duplicate(), GameData.monster("epic_boss").duplicate()],
		"stages": stages, "heroes": GameData.heroes().duplicate(true), "resources": GameData.resources().duplicate(true), "config": cfg}


## 교체 성공은 새 값으로, 실패는 직전 상태 그대로. 호출자가 끝에 기본 표를 복구한다(실패해도 복구되게 분리).
func _remote_checks() -> int:
	var expected_errors := 0
	var p := _payload()
	check(GameData.apply_remote(p) and GameData.errors == 0, "apply_remote accepts a payload equal to the tables")
	p = _payload()
	p.heroes[0].hp = 999.0
	p.resources[0].per_min = 20
	p.monsters[0].gold = 7
	p.stages = p.stages.slice(0, 10)
	p.stages.reverse()  # 순서가 뒤섞여도 stage 번호로 정렬해 읽는다
	p.config.castle_hp = "2000"
	p.config.hero_slots = "5|9"
	p.config.starter_heroes = "jack|kyle"
	p.heroes[1].s1a = 5  # 서버 행처럼: 숫자는 숫자, 빈 칸은 null
	p.heroes[1].skill2 = null
	p.heroes[1].s2a = null
	check(GameData.apply_remote(p) and GameData.errors == 0, "apply_remote accepts changed payload")
	check(GameData.hero("arteon").hp == 999.0 and GameData.heroes().size() == 22 and GameData.default_deploy(3) == ["jack", "kyle", null], "remote heroes + starters replace the table")
	check(GameData.hero("ignis").skills == {"aoe_blast": [5.0, 3.5, 220.0]}, "remote hero row with numbers and nulls parses skills")
	check(GameData.resource("wood").per_min == 20.0 and GameData.monster("grunt").gold == 7.0, "remote resources/monsters replace the table")
	check(GameData.config_num("castle_hp") == 2000.0 and GameData.hero_slots(1) == 5 and GameData.hero_slots(9) == 9, "remote config replaces the table")
	check(is_equal_approx(GameData.stage(10).hp_mult, 1.9) and GameData.stage(1).hp_mult == 1.0, "remote stages replace the table")
	var gs = GameStateScript.new()  # 표가 바뀐 뒤에는 새 값으로 시작한다
	check(gs.castle_hp_max == 2000.0 and gs.hero_count() == 5, "GameState reads the replaced tables")
	gs.free()
	# 틀린 payload는 거부하고 위 상태를 그대로 둔다. [이름, 고치는 함수, 오류 수]
	var bad := [
		["monster cell not a number", 1], ["monster column missing", 1], ["stage gap", 1], ["hero name empty", 1],
		["duplicate hero id", 1], ["resource building duplicated", 1], ["config key missing", 1], ["config value not a number", 1],
		["starter names an unknown hero", 1], ["boss monster missing", 1], ["table is not an array", 1], ["table is empty", 1],
		["row is not an object", 1], ["config is not an object", 1], ["two bad rows", 2],
		["hero model unknown", 1], ["hero gear not on the model", 1], ["resource building not in the layout", 1],
		["unknown skill", 1], ["repeated skill", 1], ["skill number missing", 1], ["skill number not a number", 1],
		["grade unknown", 1], ["role unknown", 1], ["color not #RRGGBB", 1],
		["gacha cost not an integer", 1], ["gacha cost negative", 1], ["gacha guarantee not an integer", 1], ["gacha rate above 1", 1],
		["gacha rates sum above 1", 1], ["a grade with no heroes", 1], ["multishot 0", 1], ["skill cooldown 0", 1], ["haste -100", 1],
		["stun every 2.5th attack", 1], ["hero attack interval 0", 1], ["hero hp negative", 1],
	]
	var before := _tables_hash()
	for entry in bad:
		var q := _payload()
		_corrupt(q, entry[0])
		var ok := GameData.apply_remote(q)
		check(not ok and GameData.errors == entry[1], "apply_remote rejects: %s (errors %d)" % [entry[0], GameData.errors])
		expected_errors += GameData.errors
		check(_tables_hash() == before, "tables unchanged after rejected payload: %s" % entry[0])
	return expected_errors


## 모든 표의 내용 해시(깊은 비교) — 거부된 payload가 표를 하나도 안 바꿨는지 본다.
func _tables_hash() -> int:
	return hash([GameData._monsters, GameData._stages, GameData._heroes, GameData._resources, GameData._config])


## payload q를 이름에 맞게 한 곳(또는 둘) 망가뜨린다.
func _corrupt(q: Dictionary, what: String) -> void:
	match what:
		"monster cell not a number": q.monsters[0].hp = "abc"
		"monster column missing": q.monsters[1].erase("gold")
		"stage gap": q.stages.remove_at(3)
		"hero name empty": q.heroes[1].name = ""
		"duplicate hero id": q.heroes[1].id = "arteon"
		"resource building duplicated": q.resources[1].building = "lumber"
		"config key missing": q.config.erase("badge_min")
		"config value not a number": q.config.castle_hp = "lots"
		"starter names an unknown hero": q.config.starter_heroes = "hans|ghost"
		"boss monster missing": q.monsters.remove_at(1)
		"table is not an array": q.heroes = {}
		"table is empty": q.resources = []
		"row is not an object": q.heroes.append(5)
		"config is not an object": q.config = []
		"two bad rows":
			q.monsters[0].atk = "x"
			q.heroes[0].hp = null
		"hero model unknown": q.heroes[0].model = "Dragon"  # 앱에 모델이 없다(hero.gd가 Art.HERO_MODELS[model]로 깨진다)
		"hero gear not on the model": q.heroes[0].gear = "1H_Sword|2H_Staff"
		"unknown skill": q.heroes[0].skill1 = "fly"
		"repeated skill": q.heroes[0].skill2 = "heal_aura"
		"skill number missing": q.heroes[0].s1c = ""  # heal_aura는 숫자 셋
		"skill number not a number": q.heroes[2].s1a = "three"
		"grade unknown": q.heroes[0].grade = "UR"
		"role unknown": q.heroes[0].role = "flying"
		"color not #RRGGBB": q.heroes[0].color = "gold"
		"gacha cost not an integer": q.config.gacha_cost_1 = "300.5"  # 서버 BigInt(-cost × 10)가 throw
		"gacha cost negative": q.config.gacha_cost_10 = "-1"
		"gacha guarantee not an integer": q.config.gacha_10_min_sr = "1.5"
		"gacha rate above 1": q.config.gacha_rate_ssr = "1.5"
		"gacha rates sum above 1": q.config.gacha_rate_sr = "0.98"
		"a grade with no heroes": q.heroes = q.heroes.filter(func(h): return h.grade != "SR")  # roll_gacha가 빈 풀에서 깨진다
		"multishot 0": q.heroes[2].s1a = 0  # 실바나: slice(0, -1)
		"skill cooldown 0": q.heroes[1].s1a = 0  # 이그니스 aoe_blast: 매 프레임 폭발
		"haste -100": q.heroes[13].s1a = -100  # 리안: 간격 ÷ 0
		"stun every 2.5th attack": q.heroes[9].s2a = 2.5  # 네브
		"hero attack interval 0": q.heroes[0].atk_interval = 0
		"hero hp negative": q.heroes[0].hp = -5
		"resource building not in the layout": q.resources[0].building = "mine"  # 배치에 없다(badges.gd가 깨진다)


func test_apply_remote() -> void:
	var logged := _errors.count
	GameData.load_tables()
	var expected := _remote_checks()
	check(_errors.count - logged == expected, "rejected payloads report each error through push_error")
	_errors.count = logged
	GameData.load_tables()
	check(GameData.errors == 0 and GameData.hero("arteon").hp == 1040.0 and GameData.config_num("castle_hp") == 1000.0 and GameData.heroes().size() == 22, "default tables restored after apply_remote tests")


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
	gs.advance(GameData.config_num("result_sec") + 0.01)
	check(gs.mode == gs.Mode.COUNTDOWN, "countdown after result")
	check(gs.countdown_left() > 2.9, "countdown starts near 3s")
	gs.advance(GameData.config_num("countdown_sec") + 0.01)
	check(gs.mode == gs.Mode.STAGE, "stage after countdown")
	check(modes == [gs.Mode.STAGE, gs.Mode.RESULT, gs.Mode.COUNTDOWN, gs.Mode.STAGE], "transition order %s" % [modes])
	gs.free()


func test_gamestate_fail_keeps_stage() -> void:
	var gs = GameStateScript.new()
	var failed: Array = []
	gs.stage_failed.connect(func(s): failed.append(s))
	gs.stage = 5
	gs.start_stage()
	gs.damage_castle(GameData.config_num("castle_hp") + 1.0)
	check(gs.castle_hp == 0.0, "castle hp clamps at 0")
	check(gs.mode == gs.Mode.RESULT, "result after castle destroyed")
	check(failed == [5], "stage_failed emitted with stage 5")
	gs.damage_castle(50.0)
	check(gs.mode == gs.Mode.RESULT, "extra damage after destruction ignored")
	gs.advance(GameData.config_num("result_sec") + 0.01)
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
	gs.advance(GameData.config_num("result_sec") + 0.01)
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
	for h in GameData.heroes():
		for key in ["name", "hp", "atk", "range", "atk_interval", "speed", "aggro", "skills"]:
			check(h.has(key), "hero %s has %s" % [h.id, key])
		if h.role == "ranged":
			check(h.range > 1.8, "ranged hero %s outranges melee" % h.id)


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
	for h in GameData.heroes():  # 영웅마다 모델 스펙: gear만 보이고 공격 애니메이션이 있다
		check(Art.HERO_MODELS.has(h.model), "hero %s has a model" % h.id)
		specs["hero " + h.id] = Art.hero_spec(h)
	specs.merge(Art.MONSTER_MODELS)
	for model in Art.HERO_MODELS:  # 모델의 부착물 목록 = GLB의 손 부착물 전부(빠진 것도, 없는 것도 없다)
		var root: Node = (load(Art.HERO_MODELS[model].scene) as PackedScene).instantiate()
		var found := []
		for slot in root.find_children("handslot_*", "BoneAttachment3D", true, false):
			for c in slot.get_children():
				found.append(String(c.name))
		found.sort()
		var listed: Array = Art.HERO_MODELS[model].gear.duplicate()
		listed.sort()
		check(found == listed, "%s attachment list matches the GLB: %s" % [model, found])
		root.free()
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
		var hero: Dictionary = GameData.hero(key.trim_prefix("hero ")) if key.begins_with("hero ") else {}
		for mesh_name in hero.get("gear", "").split("|", false):
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
	var paths: Array = Art.HERO_MODELS.values().map(func(m): return m.scene)
	for path in paths + [Art.MONSTER_MODELS.grunt.scene, Art.MONSTER_MODELS.grunt.weapon, Art.ARROW_MODEL]:
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
	var knight: Node = Art.instance(Art.HERO_MODELS.Knight.scene)
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
	check(g == EconomyScript.sell_value("wood", 40, rate) and e.res.wood == 0 and e.gold == g and e.gold_tenths == g * 10, "sell zeroes the resource and adds whole gold (x10 tenths)")
	var before: int = e.gold
	var g2: int = e.sell_all(now)
	check(e.res.stone == 0 and e.res.food == 0 and e.gold == before + g2 and g2 == EconomyScript.sell_value("stone", 9, rate) + EconomyScript.sell_value("food", 13, rate), "sell_all sells everything")
	e.add_gold_tenths(5)
	check(e.gold_tenths == (before + g2) * 10 + 5 and e.gold == before + g2, "add_gold_tenths adds 0.5 gold and the display floors it away")
	e.free()


func test_economy_save() -> void:
	var now := 1.8e9
	var e = _econ(now)
	e.save_path = ECON_TMP
	e.gold_tenths = 775
	e.res.wood = 12
	e.last_collect.lumber = now - 90.5
	e.levels.farm = 3
	e.save()
	e.gold_tenths = 783
	e.save()  # 이미 있는 파일 위로 다시 저장(임시 파일 → 바꿔 끼우기)
	check(not FileAccess.file_exists(ECON_TMP + ".tmp"), "save leaves no temp file behind")
	var e2 = _econ(0.0)
	e2.save_path = ECON_TMP
	e2.load_save(now + 5.0)
	check(e2.gold_tenths == 783 and e2.gold == 78 and e2.res.wood == 12 and e2.res.wood is int and e2.levels.farm == 3 and e2.levels.farm is int and is_equal_approx(e2.last_collect.lumber, now - 90.5), "save round-trips with int types restored")
	for junk in ["{not json", "[1,2]", "{\"version\":2,\"gold\":5}", "{\"version\":3,\"gold_tenths\":1,\"res\":{},\"last_collect\":{},\"levels\":{}}"]:
		var f := FileAccess.open(ECON_TMP, FileAccess.WRITE)
		f.store_string(junk)
		f.close()
		e2.gold_tenths = 99
		e2.load_save(now)
		check(e2.gold_tenths == 0 and e2.res.wood == 0 and e2.levels.lumber == 1 and e2.last_collect.lumber == now, "corrupt save (%s) falls back to defaults" % junk)
	DirAccess.remove_absolute(ECON_TMP)
	e2.gold_tenths = 99
	e2.load_save(now)
	check(e2.gold_tenths == 0, "missing save file gives defaults")
	e2.save_path = ""
	e2.gold = 5
	e2.save()
	check(not FileAccess.file_exists(ECON_TMP), "save_path empty writes no file")
	e.free()
	e2.free()


## 온라인 도우미(개정 9): apply_server 형 검사, 표시 골드 = 서버 골드 + 안 보낸·보낸 처치(서버 stage로 매김),
## 묶음 하나씩 끝내기, 서버 상한으로 처치 나누기. net은 null 그대로(요청은 안 보낸다).
func test_economy_online() -> void:
	var e = _econ(1000.0)
	var logged := _errors.count
	e.gold_tenths = 5
	check(not e.apply_server({"player": {"gold_tenths": "x"}, "merchant": {}}) and e.gold_tenths == 5 and e.server_stage == 0, "apply_server rejects a malformed reply and changes nothing")
	_errors.count = logged  # 거부는 push_error로 알린다
	var reply := {"player": {"gold_tenths": 1005, "gold": 100, "stage": 3, "kill_seq": 7, "res": {"wood": 4}, "buildings": {"lumber": {"level": 2, "last_collect": 900.0}}},
		"merchant": {"rate": 1.2, "next_change": 3600.0}}
	check(e.apply_server(reply) and e.server_gold_tenths == 1005 and e.gold_tenths == 1005 and e.gold == 100 and e.server_stage == 3 and e.kill_seq == 7 and e.res.wood == 4 and e.res.stone == 0 \
		and e.levels.lumber == 2 and e.last_collect.lumber == 900.0 and e.merchant.rate == 1.2, "apply_server takes the server snapshot")
	e.kills_pending = {1: {"grunt": 2}, 5: {"epic_boss": 1}}
	e.kills_sent = {3: {"grunt": 1}}
	e._recalc_gold()
	var want: int = 1005 + 2 * GameData.kill_gold_tenths("grunt", 1) + GameData.kill_gold_tenths("epic_boss", 3) + GameData.kill_gold_tenths("grunt", 3)
	check(GameData.kill_gold_tenths("epic_boss", 5) != GameData.kill_gold_tenths("epic_boss", 3) and e.gold_tenths == want,
		"displayed gold = server gold + pending + sent, kills above the server stage priced at the server stage (%d vs %d)" % [e.gold_tenths, want])
	e.kills_sent = {3: {"grunt": 10, "epic_boss": 1}}
	e.kills_done(3, {"grunt": 4})
	check(e.kills_sent == {3: {"grunt": 6, "epic_boss": 1}}, "kills_done removes only that batch: %s" % [e.kills_sent])
	e.kills_done(3, {"grunt": 6, "epic_boss": 1})
	check(e.kills_sent.is_empty() and e.gold_tenths == 1005 + 2 * GameData.kill_gold_tenths("grunt", 1) + GameData.kill_gold_tenths("epic_boss", 3), "the last batch empties kills_sent and gold is recalculated")
	check(EconomyScript.split_kills({"grunt": 7, "epic_boss": 1}) == [{"grunt": 7, "epic_boss": 1}], "split_kills keeps a small batch whole")
	var parts: Array = EconomyScript.split_kills({"grunt": 25000, "epic_boss": 3}, 10000)
	check(parts == [{"grunt": 10000, "epic_boss": 3}, {"grunt": 10000}, {"grunt": 5000}] and EconomyScript.MAX_KILL_COUNT == 10000,
		"split_kills caps each kind per batch at the server limit: %s" % [parts])
	e.free()


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


## lowpoly_box: 면 수 고정, 같은 seed면 같은 폴리곤, 다른 seed면 다름. 키트 smoke(상태 4종·바·패널).
func test_lowpoly_box() -> void:
	var r := Rect2(0, 0, 200, 80)
	var a: Array = LowpolyBoxScript.faces(r, 10.0, Color.WHITE, 0.06, 5)
	var b: Array = LowpolyBoxScript.faces(r, 10.0, Color.WHITE, 0.06, 5)
	var c: Array = LowpolyBoxScript.faces(r, 10.0, Color.WHITE, 0.06, 6)
	check(a.size() == LowpolyBoxScript.FACES and a.size() >= 8 and a.size() <= 16, "lowpoly box has 8..16 faces (%d)" % a.size())
	check(a == b, "lowpoly box is deterministic for the same seed")
	check(a != c, "lowpoly box differs for another seed")
	check(LowpolyBoxScript.octagon(r, 10.0).size() == 8, "lowpoly box outline is an octagon")
	check(LowpolyBoxScript.octagon(Rect2(0, 0, 4, 4), 50.0)[0].x <= 2.0, "chamfer clamps to half the short side")
	var styles: Dictionary = UiKit.button_styles(UiKit.AMBER)
	for k in ["normal", "hover", "pressed", "disabled"]:
		check(styles.has(k) and styles[k] is StyleBox, "button style %s exists" % k)
	# 글자는 내용 칸 가운데: 위치 = (위 − 아래) / 2. 눌림이 PRESS_SHIFT만큼 아래, 위·아래 합(버튼 크기)은 네 상태가 같다. 음수 여백(= 기본값) 없음
	var shift := func(sb: StyleBox): return (sb.get_margin(SIDE_TOP) - sb.get_margin(SIDE_BOTTOM)) / 2.0
	var n: StyleBox = styles.normal
	check(is_equal_approx(shift.call(styles.pressed) - shift.call(n), UiKit.PRESS_SHIFT), "pressed style moves the content %.0f px down" % UiKit.PRESS_SHIFT)
	for k in styles:
		var sb: StyleBox = styles[k]
		check(sb.content_margin_top >= 0.0 and sb.content_margin_bottom >= 0.0 and is_equal_approx(sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM), n.get_margin(SIDE_TOP) + n.get_margin(SIDE_BOTTOM)),
			"button style %s: no negative margin, same vertical margin sum as normal" % k)
	check(UiKit.button_styles(UiKit.AMBER) == styles and UiKit.panel(UiKit.CREAM) == UiKit.panel(UiKit.CREAM), "kit styleboxes are reused")
	check(UiKit.bar(UiKit.AMBER).has("fill") and UiKit.bar(UiKit.AMBER).has("background"), "bar has fill and background")
	check(UiKit.GRADE_COLORS.has("R") and UiKit.GRADE_COLORS.has("SR") and UiKit.GRADE_COLORS.has("SSR") and UiKit.GRADE_COLORS == Art.GRADE_COLORS, "grade colors R/SR/SSR from one source (Art)")


## HP 바: 프레임의 8각형을 한 배열에 모은다(LowpolyBox.octagon과 같은 점), 인덱스는 칸마다 부채꼴 6삼각형.
## 다음 프레임에 수가 줄었다 늘어도 배열 길이·인덱스가 맞다(멤버 배열 재사용).
func test_hp_bars_batch() -> void:
	var hb = HpBarsScript.new()
	hb.add_octagon(Vector2(10, 20), Vector2(34, 5), 1.5, Color.RED)
	hb.add_octagon(Vector2(50, 60), Vector2(20, 8), 3.0, Color.BLUE)
	check(hb._flush() and hb.octagons == 2 and hb._pts.size() == 16 and hb._cols.size() == 16 and hb._idx.size() == 36, "two bars: 16 points, 36 indices")
	check(hb._pts.slice(0, 8) == LowpolyBoxScript.octagon(Rect2(10, 20, 34, 5), 1.5) and hb._pts.slice(8, 16) == LowpolyBoxScript.octagon(Rect2(50, 60, 20, 8), 3.0),
		"bar octagons match LowpolyBox.octagon")
	check(hb._cols[0] == Color.RED and hb._cols[15] == Color.BLUE, "one color per octagon")
	check(hb._idx.slice(18, 36) == PackedInt32Array([8, 9, 10, 8, 10, 11, 8, 11, 12, 8, 12, 13, 8, 13, 14, 8, 14, 15]), "second octagon is a fan from its first point: %s" % [hb._idx.slice(18, 36)])
	hb._n = 0
	hb._flush()
	check(hb.octagons == 0, "no bars: nothing to draw")
	for i in 3:
		hb.add_octagon(Vector2(i * 40, 0), Vector2(34, 5), 1.5, Color.WHITE)
	check(hb._flush() and hb._pts.size() == 24 and hb._idx.size() == 54 and hb._idx[36] == 16 and hb._idx[53] == 23 and hb._idx[0] == 0, "three bars after a frame with none: sizes and indices refilled")
	hb.free()


## 영웅 카드: 지오메트리는 (크기, 영웅, 별)이 바뀔 때만 만든다 — SSR이 매 프레임 다시 그려도 반짝임 색만 바뀐다.
func test_hero_card_geometry() -> void:
	var card = HeroCardScript.new()
	card.size = Vector2(118, 160)
	card.hero_id = "arteon"
	card.stars = 2
	var h := GameData.hero("arteon")
	card._ensure_geo(h)
	var body: PackedVector2Array = card._body
	card._t = 0.3
	card._tick_shine(UiKit.GRADE_COLORS.SSR)
	var c1: Color = card._shine_cols[0]
	card._ensure_geo(h)
	card._t = 0.9
	card._tick_shine(UiKit.GRADE_COLORS.SSR)
	check(card.geo_builds == 1 and card._body == body and card._shine_cols[0] != c1, "same card size/hero/stars: geometry built once, only the shimmer colors change")
	check(card._body.size() == (6 + LowpolyBoxScript.FACES) * 3 and card._body_cols.size() == card._body.size() and card._shine.size() == LowpolyBoxScript.FACES * 3,
		"card body = octagon fan + %d faces, SSR shimmer = %d faces" % [LowpolyBoxScript.FACES, LowpolyBoxScript.FACES])
	check(card._top.size() == (6 + 6 + 2 * 10) * 3 and card._top_cols.size() == card._top.size() and card._lines.size() == 4, "two gems and two stars on top: %d points" % card._top.size())
	card.stars = 3
	card._ensure_geo(h)
	check(card.geo_builds == 2 and card._top.size() == (6 + 6 + 3 * 10) * 3, "a star change rebuilds the geometry")
	card.hero_id = "hans"
	card._ensure_geo(GameData.hero("hans"))
	check(card.geo_builds == 3 and card._shine.is_empty(), "an R card has no shimmer")
	card.free()


## 개정 10: 골드 tenths. 표시는 floor, 저장 v1(정수 골드) → v2(tenths) 이전, 오프라인 처치는 tenths로 더한다.
func test_gold_tenths() -> void:
	var now := 1.8e9
	var e = _econ(now)
	e.save_path = ECON_TMP
	e.gold_tenths = 129
	check(e.gold == 12, "display gold floors tenths (129 -> 12)")
	e.gold = 7
	check(e.gold_tenths == 70, "setting whole gold writes x10 tenths")
	e.gold_tenths = 0
	e.add_kill("grunt", 2)
	check(e.gold_tenths == 24 and e.gold == 2, "an offline kill adds 2.4 gold at stage 2 and shows 2")
	e.add_kill("grunt", 2)
	e.add_kill("grunt", 2)
	check(e.gold_tenths == 72 and e.gold == 7, "tenths accumulate across kills (0.8 + 7.2 shows 7)")
	e.save()
	var f := FileAccess.open(ECON_TMP, FileAccess.READ)
	var saved = JSON.parse_string(f.get_as_text())
	f.close()
	check(int(saved.version) == 2 and int(saved.gold_tenths) == 72 and not saved.has("gold"), "save writes version 2 with gold_tenths")
	var v1 := FileAccess.open(ECON_TMP, FileAccess.WRITE)
	v1.store_string(JSON.stringify({"version": 1, "gold": 41, "res": {"wood": 3, "stone": 0, "food": 0}, "last_collect": {"lumber": now, "quarry": now, "farm": now}, "levels": {"lumber": 1, "quarry": 1, "farm": 1}}))
	v1.close()
	var e2 = _econ(0.0)
	e2.save_path = ECON_TMP
	e2.load_save(now)
	check(e2.gold_tenths == 410 and e2.gold == 41 and e2.res.wood == 3, "a version 1 save moves over as gold x 10")
	DirAccess.remove_absolute(ECON_TMP)
	e.free()
	e2.free()


## heroes.csv(스펙 §3.3): 22행, 등급 10/7/5, 스킬은 알려진 종류만(19종 모두 누군가 쓴다), 모델·부착물 존재, 시작 영웅 R 4종(근접 2·원거리 2).
func test_heroes_table() -> void:
	const Skills := preload("res://scripts/skills.gd")
	GameData.load_tables()
	var hs := GameData.heroes()
	check(hs.size() == 22, "22 heroes, got %d" % hs.size())
	var grades := {"SSR": 0, "SR": 0, "R": 0}
	var used := {}
	for h in hs:
		grades[h.grade] += 1
		check(h.role in GameData.ROLES and Art.HERO_MODELS.has(h.model) and Color.html_is_valid(h.color), "hero %s role/model/color" % h.id)
		check(h.skills.size() >= 1, "hero %s has a skill" % h.id)
		for k in h.skills:
			check(Skills.KINDS.has(k), "hero %s skill %s is known" % [h.id, k])
			used[k] = true
		for g in h.gear.split("|"):
			check(g in Art.HERO_MODELS[h.model].gear, "hero %s gear %s on %s" % [h.id, g, h.model])
	check(grades == {"SSR": 10, "SR": 7, "R": 5}, "grades 10/7/5: %s" % grades)
	check(used.size() == Skills.KINDS.size(), "every skill kind is used: %d/%d" % [used.size(), Skills.KINDS.size()])
	check(Skills.RULES.size() == Skills.KINDS.size() and Skills.KINDS.keys().all(func(k): return Skills.RULES.has(k) and Skills.RULES[k].size() == Skills.KINDS[k]),
		"every skill kind has one range rule per number")
	check(Skills.bad_num("multishot", [0.0, 0.0, 0.0]) == 0 and Skills.bad_num("chain", [3.0, 120.0, 4.0]) == 1 and Skills.bad_num("crit", [25.0, 200.0, 0.0]) == -1,
		"skill range: multishot 0 and chain decay above 100% are out, crit 25/200 is in")
	var roles := []
	for id in GameData.config_list("starter_heroes"):
		check(GameData.hero(id).grade == "R", "starter %s is R" % id)
		roles.append(GameData.hero(id).role)
	check(roles == ["melee", "ranged", "melee", "ranged"], "starters alternate melee/ranged: %s" % [roles])


## 스킬 수식(스펙 §3.2): haste·rage 간격, crit·execute·boss_slayer 배율, chain 감쇠, dodge → dmg_reduce → thorns 순서, stun N번째, 오라.
func test_skill_formulas() -> void:
	const Skills := preload("res://scripts/skills.gd")
	check(Skills.interval({}, 1.0, 0.5) == 1.0, "no skill: base interval")
	check(is_equal_approx(Skills.interval({"haste": [30.0, 0.0, 0.0]}, 0.64, 1.0), 0.64 / 1.3), "haste: interval / (1 + a/100)")
	var rage := {"rage": [80.0, 0.0, 0.0]}
	check(Skills.interval(rage, 0.8, 1.0) == 0.8, "rage at full HP: unchanged")
	check(is_equal_approx(Skills.interval(rage, 0.8, 0.5), 0.8 / 1.4), "rage at half HP: speed +40%")
	check(is_equal_approx(Skills.interval(rage, 0.8, 0.0), 0.8 / 1.8), "rage at 0 HP: speed +a% max")
	var crit := {"crit": [25.0, 200.0, 0.0]}
	check(Skills.damage(crit, 40.0, 0.24, 1.0, false) == 80.0, "crit: roll < a% multiplies by b/100")
	check(Skills.damage(crit, 40.0, 0.25, 1.0, false) == 40.0, "crit: roll at a% misses")
	var ex := {"execute": [30.0, 100.0, 0.0]}
	check(Skills.damage(ex, 50.0, 0.9, 0.3, false) == 100.0 and Skills.damage(ex, 50.0, 0.9, 0.31, false) == 50.0, "execute: +b% at or below a% target HP")
	var boss := {"boss_slayer": [150.0, 0.0, 0.0]}
	check(Skills.damage(boss, 60.0, 0.9, 1.0, true) == 150.0 and Skills.damage(boss, 60.0, 0.9, 1.0, false) == 60.0, "boss_slayer: +a% to epic_boss only")
	check(is_equal_approx(Skills.damage(GameData.hero("kyle").skills, 81.0, 0.0, 0.2, false), 81.0 * 2.5 * 2.0), "crit and execute multiply (kyle)")
	var cd := Skills.chain_damages({"chain": [3.0, 70.0, 4.0]}, 100.0)
	check(cd.size() == 3 and is_equal_approx(cd[0], 70.0) and is_equal_approx(cd[1], 49.0) and is_equal_approx(cd[2], 34.3), "chain: a bounces, each x b/100: %s" % [cd])
	check(Skills.chain_damages({}, 100.0).is_empty(), "no chain: no bounces")
	var tank := {"dodge": [20.0, 0.0, 0.0], "dmg_reduce": [25.0, 0.0, 0.0], "thorns": [30.0, 0.0, 0.0]}
	check(Skills.incoming(tank, 100.0, 0.19) == Vector2.ZERO, "dodge first: no damage and nothing reflected")
	var r := Skills.incoming(tank, 100.0, 0.5)
	check(is_equal_approx(r.x, 75.0) and is_equal_approx(r.y, 22.5), "dmg_reduce before thorns: thorns reflect the reduced damage: %s" % r)
	check(Skills.incoming({}, 100.0, 0.0) == Vector2(100.0, 0.0), "no skill: full damage, no reflect")
	var stun := {"stun": [5.0, 1.0, 0.0]}
	check(Skills.stuns(stun, 5) and Skills.stuns(stun, 10) and not Skills.stuns(stun, 4) and not Skills.stuns({}, 5), "stun every N-th attack")
	check(Skills.aura_mult(15.0) == 1.15 and Skills.aura_mult(0.0) == 1.0, "atk_aura multiplier")


## 배치 기본값(오프라인 공급자)과 별 배율.
func test_deploy_and_stars() -> void:
	check(GameData.default_deploy(4) == ["hans", "ella", "dorik", "nina"], "default deploy = starters")
	check(GameData.default_deploy(6) == ["hans", "ella", "dorik", "nina", null, null], "more slots than starters: null")
	check(GameData.default_deploy(2) == ["hans", "ella"], "fewer slots: truncated")
	check(GameData.star_mult(1) == 1.0 and is_equal_approx(GameData.star_mult(3), 1.2) and is_equal_approx(GameData.star_mult(6), 1.5) \
		and is_equal_approx(GameData.star_mult(99), 1.5), "stars = min(copies - 1, 5), x(1 + 0.1 x stars)")
	var gs = GameStateScript.new()
	check(gs.deploy() == GameData.default_deploy(4) and gs.hero_copies("hans") == 1, "GameState deploy provider: starters, copies 1")
	gs.keep_level = 2
	check(gs.deploy().size() == 8 and gs.deploy()[4] == null, "deploy length = hero slots")
	gs.free()


## 성문 회복: 최대치 상한, 부서진 성문 제외, 오를 때만 시그널.
func test_gate_repair() -> void:
	var gs = GameStateScript.new()
	var events := []
	gs.gate_hp_changed.connect(func(s, hp, _mx): events.append([s, hp]))
	gs.damage_gate(1, 100.0)
	events.clear()
	check(gs.repair_gate(1, 40.0) == 40.0 and gs.gate_hp[1] == 340.0 and events == [[1, 340.0]], "repair adds hp and signals")
	check(gs.repair_gate(1, 500.0) == 60.0 and gs.gate_hp[1] == gs.gate_hp_max, "repair capped at max")
	check(gs.repair_gate(1, 10.0) == 0.0 and events.size() == 2, "full gate: no gain, no signal")
	gs.damage_gate(2, 1.0e6)
	check(gs.repair_gate(2, 100.0) == 0.0 and gs.is_gate_broken(2), "broken gate is not repaired")
	gs.free()


## 이펙트 메시: 종류마다 한 면, (종류, 색)마다 캐시, 발밑 링은 선택 링(바깥 0.8)보다 작고 그림자 없음·공유 재질.
func test_fx_meshes() -> void:
	const Fx := preload("res://scripts/fx.gd")
	for kind in ["bolt", "blast", "axe", "heal", "slow", "poison", "repair", "stun"]:
		var m: Mesh = Fx._mesh(kind, Color.RED)
		check(m != null and m.get_surface_count() == 1, "fx mesh %s builds" % kind)
	check(Fx._mesh("bolt", Color.RED) == Fx._mesh("bolt", Color.RED) and Fx._mesh("bolt", Color.RED) != Fx._mesh("bolt", Color.BLUE), "fx meshes cached per kind and color")
	var ring: MeshInstance3D = Fx.foot_ring(Art.GRADE_COLORS.SSR, Color("#F5D76E"))
	var size := ring.mesh.get_aabb().size
	check(size.x < 1.6 and size.z < 1.6 and size.y < 0.1, "foot ring inside the selection ring: %s" % size)
	check(ring.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and ring.material_override == Fx.material(), "foot ring: no shadow, shared material")
	ring.free()


## 개정 10 모집(오프라인, 스펙 §3.6): 10만 장 표본 확률, 10연차 보장(표본 + 조작 난수), 비용 tenths(소수 남음), copies·NEW, 부족하면 알림만,
## 같은 seed면 같은 결과.
func test_gacha_offline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var n := 100000
	var out: Array = EconomyScript.roll_gacha(n, rng.randf)
	var c := {"SSR": 0, "SR": 0, "R": 0}
	for x in out:
		c[x.grade] += 1
	check(out.size() == n and absf(c.SSR / float(n) - 0.03) <= 0.004 and absf(c.SR / float(n) - 0.17) <= 0.008, "gacha rates SSR 3%% +- 0.4%%, SR 17%% +- 0.8%%: %s" % [c])
	check(out.slice(0, 200).all(func(x): return GameData.hero(x.id).grade == x.grade), "each pull is a hero of its grade")
	var all_ten := true
	for i in 2000:
		var ten: Array = EconomyScript.roll_gacha(10, rng.randf)
		all_ten = all_ten and ten.size() == 10 and ten.any(func(x): return x.grade != "R")
	check(all_ten, "every 10-pull has an SR or better (2000 samples)")
	var all_r := func(): return 0.99  # 전부 R, 풀 마지막(jack)
	var rigged: Array = EconomyScript.roll_gacha(10, all_r)
	check(rigged.slice(0, 9).all(func(x): return x.id == "jack") and rigged[9] == {"id": "felix", "grade": "SR"}, "a 10-pull with no SR+ turns the last card into an SR: %s" % [rigged])
	check(EconomyScript.roll_gacha(1, all_r) == [{"id": "jack", "grade": "R"}], "a single pull has no guarantee")
	check(EconomyScript.gacha_cost(1) == 300 and EconomyScript.gacha_cost(10) == 2700, "costs 300 / 2700")
	var e = _econ(1000.0)
	e.rng.seed = 7
	var got := []
	var notices := []
	e.gacha_done.connect(func(r): got.append(r))
	e.notice.connect(func(t): notices.append(t))
	e.gold_tenths = 30005
	check(e.gacha(10) and e.gold_tenths == 3005 and got.size() == 1 and got[0].size() == 10, "10-pull costs 2700 gold (27000 tenths) and returns 10 cards")
	var seen := _econ_starters()
	var consistent := true
	for r in got[0]:
		var before := int(seen.get(r.hero_id, 0))
		seen[r.hero_id] = before + 1
		consistent = consistent and r.new == (before == 0) and r.copies == before + 1 and r.grade == GameData.hero(r.hero_id).grade
	check(consistent and seen == e.heroes, "results: new only on the first copy, copies count up per card, heroes updated: %s" % [got[0]])
	check(e.gacha(1) and e.gold_tenths == 5 and got.size() == 2, "1 pull costs 300 (3000 tenths), the 0.5 fraction stays")
	check(not e.gacha(1) and e.gold_tenths == 5 and got.size() == 2 and notices == [EconomyScript.NO_GOLD_TEXT], "not enough gold: nothing happens, one notice")
	e.gold = 99999
	check(not e.gacha(3) and e.gold == 99999, "only 1 or 10 pulls")
	var a = _econ(0.0)
	var b = _econ(0.0)
	a.rng.seed = 99
	b.rng.seed = 99
	a.gold = 2700
	b.gold = 2700
	a.gacha(10)
	b.gacha(10)
	check(a.heroes == b.heroes and a.heroes != _econ_starters(), "same seed, same pulls")
	e.free()
	a.free()
	b.free()


func _econ_starters() -> Dictionary:
	return {"hans": 1, "ella": 1, "dorik": 1, "nina": 1}


## 보유 영웅·배치(오프라인 save v2, 서버 응답), GameState 공급자(roster 주입), 개발용 --heroes.
func test_roster() -> void:
	var now := 1.8e9
	var e = _econ(now)
	check(e.heroes == _econ_starters() and e.deploy == ["hans", "ella", "dorik", "nina"], "new game: starters copies 1, deployed in order")
	e.save_path = ECON_TMP
	e.heroes["ignis"] = 3
	e.set_deploy(["ignis", null, "hans", "nina"])
	var e2 = _econ(0.0)
	e2.save_path = ECON_TMP
	e2.load_save(now)
	check(e2.heroes == e.heroes and e2.heroes.ignis is int and e2.deploy == ["ignis", null, "hans", "nina"], "save v2 round-trips heroes and deploy: %s %s" % [e2.heroes, e2.deploy])
	var base := {"version": 2, "gold_tenths": 5, "res": {"wood": 0, "stone": 0, "food": 0}, "last_collect": {"lumber": now, "quarry": now, "farm": now}, "levels": {"lumber": 1, "quarry": 1, "farm": 1}}
	_write(ECON_TMP, JSON.stringify(base))
	e2.load_save(now)
	check(e2.gold_tenths == 5 and e2.heroes == _econ_starters() and e2.deploy == ["hans", "ella", "dorik", "nina"], "a v2 save from before heroes loads with the starters")
	for junk in [{"heroes": [], "deploy": []}, {"heroes": {"hans": 1}}, {"heroes": {"hans": "x"}, "deploy": []}, {"heroes": {"hans": 1}, "deploy": [3]}]:
		var bad := base.duplicate()
		bad.merge(junk)
		_write(ECON_TMP, JSON.stringify(bad))
		e2.load_save(now)
		check(e2.gold_tenths == 0 and e2.heroes == _econ_starters(), "malformed heroes/deploy (%s) is a corrupt save: defaults" % [junk])
	DirAccess.remove_absolute(ECON_TMP)
	# 서버 응답
	var o = _econ(1000.0)
	var reply := {"player": {"gold_tenths": 0, "stage": 1, "res": {}, "buildings": {}, "heroes": {"hans": 2, "kyle": 1}, "deploy": ["kyle", null, "hans", null]},
		"merchant": {"rate": 1.0, "next_change": 3600.0}}
	var changes := []
	o.roster_changed.connect(func(): changes.append(1))
	check(o.apply_server(reply) and o.heroes == {"hans": 2, "kyle": 1} and o.deploy == ["kyle", null, "hans", null] and changes.size() == 1, "apply_server takes heroes and deploy (roster_changed once)")
	check(o.apply_server(reply) and changes.size() == 1, "the same roster again does not signal")
	o._pending_deploy = ["hans", null, null, null]
	check(o.apply_server(reply) and o.deploy == ["hans", null, null, null], "a deploy still waiting for its reply is not undone by an older reply")
	o._pending_deploy = null
	var logged := _errors.count
	reply.player.heroes = [1]
	check(not o.apply_server(reply) and o.heroes.hans == 2, "apply_server rejects malformed heroes")
	_errors.count = logged
	# GameState 공급자
	var gs = GameStateScript.new()
	gs.roster = e2
	e2.heroes = {"ignis": 3, "hans": 1, "nina": 1}
	e2.deploy = ["ignis", "ghost", "ignis", "jack", "nina"]  # 모르는 영웅·중복·미보유·슬롯 넘침
	check(gs.deploy() == ["ignis", null, null, null], "provider: slot count, unknown/duplicate/unowned heroes become null: %s" % [gs.deploy()])
	check(gs.hero_copies("ignis") == 3 and gs.hero_copies("hans") == 1, "provider: copies from the roster")
	gs.keep_level = 2
	check(gs.deploy().size() == 8 and gs.deploy()[4] == "nina", "provider: more slots at keep level 2")
	gs.free()
	# 개발용 --heroes
	var d = _econ(now)
	d.save_path = ECON_TMP
	d.heroes["nev"] = 4
	var ok: Array = d.grant_dev_heroes(["ignis", " nev", "ghost", "ignis", "arteon", "grom"])
	check(ok == ["ignis", "nev", "arteon", "grom"] and d.deploy == ok and d.heroes.ignis == 1 and d.heroes.nev == 4 and d.heroes.hans == 1,
		"--heroes grants copies 1 (keeps more), deploys in order, skips unknown and repeated ids: %s" % [ok])
	d.save()
	check(d.save_path == "" and not FileAccess.file_exists(ECON_TMP), "--heroes never writes the save")
	e.free()
	e2.free()
	o.free()
	d.free()


## 스킬 설명(영웅 창 상세): 19종 모두 이름과 숫자를 넣은 한국어 문장(틀 자리 안 남음), 영웅마다 스킬 수치가 문장에 들어간다.
func test_skill_text() -> void:
	const Skills := preload("res://scripts/skills.gd")
	for kind in Skills.KINDS:
		var t := Skills.describe(kind, [6.0, 3.5, 220.0])
		check(t != "" and not t.contains("{") and Skills.NAMES.has(kind) and t.contains("6"), "skill %s: name and a filled sentence: %s" % [kind, t])
	check(Skills.describe("aoe_blast", [5.0, 3.5, 220.0]) == "5초마다 대상 위치에 폭발을 일으켜 반경 3.5m 안 모든 적에게 공격력의 220% 피해를 줍니다.", "aoe_blast sentence with numbers")
	check(Skills.describe("crit", [40.0, 250.0, 0.0]).begins_with("40% 확률로 2.5배"), "crit shows b/100 as a multiplier")
	check(Skills.num_text(6.0) == "6" and Skills.num_text(0.8) == "0.8" and Skills.num_text(3.5) == "3.5" and Skills.num_text(100.0) == "100" and Skills.num_text(0.64) == "0.64", "numbers drop trailing zeros")
	for h in GameData.heroes():
		for kind in h.skills:
			var nums: Array = h.skills[kind]
			check(Skills.describe(kind, nums).contains(Skills.num_text(nums[0])), "hero %s skill %s text has its number" % [h.id, kind])

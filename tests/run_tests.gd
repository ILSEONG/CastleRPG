extends SceneTree
## 순수 로직 헤드리스 테스트.
## 실행: ./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd

const Balance := preload("res://scripts/balance.gd")
const GameData := preload("res://scripts/game_data.gd")
const WaveDirector := preload("res://scripts/wave_director.gd")
const GameStateScript := preload("res://scripts/game_state.gd")
const FeverScript := preload("res://scripts/fever.gd")
const FormationScript := preload("res://scripts/formation.gd")
const Art := preload("res://scripts/art.gd")
const MeshKitScript := preload("res://scripts/mesh_kit.gd")
const TownKitScript := preload("res://scripts/town_kit.gd")
const IconsScript := preload("res://scripts/icons.gd")
const LowpolyBoxScript := preload("res://scripts/lowpoly_box.gd")
const UiKit := preload("res://scripts/ui_kit.gd")
const HpBarsScript := preload("res://scripts/hp_bars.gd")
const HeroCardScript := preload("res://scripts/hero_card.gd")
const DamageNumbersScript := preload("res://scripts/damage_numbers.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")

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
	test_gamestate_stop_stage()
	test_gamestate_auto_continue()
	test_fever_auto_next_persists()
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
	test_economy_sell_amount()
	test_economy_sell_many()
	test_training_tiers()
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
	test_deploy_and_promotion()
	test_gate_repair()
	test_fx_meshes()
	test_gacha_offline()
	test_roster()
	test_skill_text()
	test_merchant_rates()
	test_damage_numbers()
	test_hero_levels()
	test_promotion()
	test_hit_frac()
	test_buildings()
	test_soldiers()
	test_rotate_hold_state()
	test_fever()
	test_portraits()
	test_keep_tier_lockstep()
	test_soldier_figures()
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
	check(GameData.hero_slots(1) == 4 and GameData.hero_slots(4) == 4, "keep levels 1-4 give 4 heroes")
	check(GameData.hero_slots(5) == 8 and GameData.hero_slots(9) == 8, "keep levels 5-9 give 8 heroes")
	check(GameData.hero_slots(10) == 12, "keep level 10 gives 12 heroes")
	check(GameData.hero_slots(99) == 12, "keep level beyond the last tier stays at 12")
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
	check(GameData.config_list("merchant_rate_step") == [0.1], "config_list parses numbers")
	check(GameData.config_list("starter_heroes") == ["hans", "ella", "dorik", "nina"], "config_list keeps strings")
	check(GameData.config_list("nope").is_empty() and GameData.config_num("nope") == 0.0, "unknown config key is empty / 0")
	check(GameData.config_num("promote_mult") == 1.5 and GameData.config_list("promote_shards") == [5.0, 25.0, 50.0, 100.0, 200.0] and GameData.config_num("gacha_cost_10") == 2700.0, "hero/gacha/promotion config")
	# 깨진 config 파일: 필수 키 빠짐
	var logged := _errors.count
	var cp := "user://t_config.csv"
	_write(cp, "key,value\ncastle_hp,1000\nkeep_slot_tiers,1:4|5:8|10:12\nkeep_interior_tiers,1:20|5:24|10:28\nstarter_heroes,hans|ella\n")
	GameData.load_tables(GameData.MONSTERS_PATH, GameData.STAGES_PATH, GameData.HEROES_PATH, GameData.RESOURCES_PATH, cp)
	check(GameData.errors == GameData.CONFIG_NUM_KEYS.size() - 1 + GameData.CONFIG_LIST_KEYS.size() - 1 + GameData.BUILDING_NUM_KEYS.size() + GameData.SOLDIER_NUM_KEYS.size()
		+ GameData.soldiers().size(), "config file missing keys reports one error per key (rev 16: train_cost_<type> per soldier)")
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
	for k in GameData.CONFIG_NUM_KEYS + GameData.CONFIG_LIST_KEYS + GameData.BUILDING_NUM_KEYS + GameData.CONFIG_TIER_KEYS + GameData.SOLDIER_NUM_KEYS:
		cfg[k] = String(GameData._config[k])
	for sd in GameData.soldiers():  # 개정 16 훈련 비용
		cfg["train_cost_" + sd.id] = String(GameData._config["train_cost_" + sd.id])
	return {"version": "t", "monsters": [GameData.monster("grunt").duplicate(), GameData.monster("epic_boss").duplicate()],
		"stages": stages, "heroes": GameData.heroes().duplicate(true), "resources": GameData.resources().duplicate(true),
		"buildings": GameData.buildings().duplicate(true), "soldiers": GameData.soldiers().duplicate(true), "config": cfg}


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
	p.config.keep_slot_tiers = "1:4|3:8|6:12"  # 단계 표 둘은 같은 레벨로 함께 옮긴다(개정 15)
	p.config.keep_interior_tiers = "1:20|3:24|6:28"
	p.config.starter_heroes = "jack|kyle"
	p.heroes[1].s1a = 5  # 서버 행처럼: 숫자는 숫자, 빈 칸은 null
	p.heroes[1].skill2 = null
	p.heroes[1].s2a = null
	check(GameData.apply_remote(p) and GameData.errors == 0, "apply_remote accepts changed payload")
	check(GameData.hero("arteon").hp == 999.0 and GameData.heroes().size() == 22 and GameData.default_deploy(3) == ["jack", "kyle", null], "remote heroes + starters replace the table")
	check(GameData.hero("ignis").skills == {"aoe_blast": [5.0, 3.5, 220.0]}, "remote hero row with numbers and nulls parses skills")
	check(GameData.resource("wood").per_min == 20.0 and GameData.monster("grunt").gold == 7.0, "remote resources/monsters replace the table")
	check(GameData.config_num("castle_hp") == 2000.0 and GameData.hero_slots(2) == 4 and GameData.hero_slots(3) == 8 and GameData.interior_tiles(6) == 28, "remote config replaces the table")
	check(is_equal_approx(GameData.stage(10).hp_mult, 1.9) and GameData.stage(1).hp_mult == 1.0, "remote stages replace the table")
	var gs = GameStateScript.new()  # 표가 바뀐 뒤에는 새 값으로 시작한다
	check(gs.castle_hp_max == 2000.0 and gs.hero_count() == 4, "GameState reads the replaced tables")
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
	return hash([GameData._monsters, GameData._stages, GameData._heroes, GameData._resources, GameData._buildings, GameData._soldiers, GameData._config])


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


func test_gamestate_stop_stage() -> void:
	var gs = GameStateScript.new()
	var cleared: Array = []
	gs.stage_cleared.connect(func(s): cleared.append(s))
	gs.start_stage()
	gs.stage = 3
	gs.castle_hp = 10.0
	gs.gate_hp[1] = 0.0
	var refills := [0]
	gs.refilled.connect(func(): refills[0] += 1)
	gs.stop_stage()
	check(gs.mode == gs.Mode.IDLE and gs.stage == 3 and cleared.is_empty(), "stop mid-stage: idle, same stage, no clear")
	check(refills[0] == 1 and gs.castle_hp == gs.castle_hp_max and gs.gate_hp[1] == gs.gate_hp_max, "stop refills castle and gates")
	gs.start_stage()
	gs.on_all_monsters_dead()
	gs.stop_stage()
	check(gs.mode == gs.Mode.IDLE and gs.stage == 4, "stop during result: idle (clear already counted)")
	gs.advance(10.0)
	check(gs.mode == gs.Mode.IDLE, "no timer carry-over after stop")
	gs.free()


func test_gamestate_auto_continue() -> void:
	var gs = GameStateScript.new()
	check(gs.auto_continue, "continuous is on by default")
	gs.start_stage()
	gs.on_all_monsters_dead()
	gs.advance(GameData.config_num("result_sec") + 0.01)
	check(gs.mode == gs.Mode.COUNTDOWN and gs.stage == 2, "checked: clear counts down to the next stage")
	gs.stop_stage()
	gs.auto_continue = false
	gs.start_stage()
	gs.on_all_monsters_dead()
	gs.advance(GameData.config_num("result_sec") + 0.01)
	check(gs.mode == gs.Mode.IDLE and gs.stage == 3, "unchecked: clear advances the stage then idles")
	gs.free()


func test_fever_auto_next_persists() -> void:
	var path := "user://test_local_tmp.json"
	var a = FeverScript.new()
	a.save_path = path
	a.gauge = 7
	a.auto_next = false
	a.save()
	var b = FeverScript.new()
	b.save_path = path
	b.load_save()
	check(not b.auto_next and b.gauge == 7, "unchecked state and fever gauge persist together")
	DirAccess.remove_absolute(path)
	b.load_save()
	check(b.auto_next, "missing file defaults to checked")
	a.free()
	b.free()


func test_gamestate_gate_broken_once() -> void:
	var gs = GameStateScript.new()
	gs.mode = gs.Mode.STAGE  # 방치 모드는 무적(개정 12 §3) — 피해는 스테이지 모드에서
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
	check(gs.castle_hp == gs.castle_hp_max and gs.gate_hp[1] == gs.gate_hp_max, "idle mode ignores gate and castle damage (invincible)")
	check(refills[0] == 0, "no refill needed in idle")
	gs.free()


func test_gamestate_start_stage_refills() -> void:
	var gs = GameStateScript.new()
	var refills := [0]
	gs.refilled.connect(func(): refills[0] += 1)
	gs.mode = gs.Mode.STAGE  # 피해는 스테이지 모드에서만 — 넣은 뒤 방치로 돌려 start_stage를 부른다
	gs.damage_gate(3, gs.gate_hp_max * 0.5)
	gs.damage_castle(100.0)
	gs.mode = gs.Mode.IDLE
	check(not gs.is_gate_broken(3) and gs.gate_hp[3] < gs.gate_hp_max, "gate damaged, not broken")
	check(gs.castle_hp < gs.castle_hp_max, "castle damaged")
	gs.start_stage()
	check(gs.gate_hp[3] == gs.gate_hp_max, "start_stage refills the gate")
	check(gs.castle_hp == gs.castle_hp_max, "start_stage refills the castle")
	check(refills[0] == 1, "refilled emitted once, got %d" % refills[0])
	check(gs.mode == gs.Mode.STAGE, "stage mode after start_stage")
	gs.free()


func test_gamestate_hero_count() -> void:
	var gs = GameStateScript.new()
	check(gs.hero_count() == 4, "4 heroes at keep level 1")
	gs.keep_level = 5
	check(gs.hero_count() == 8, "8 heroes at keep level 5 (keep tier)")
	gs.free()


func test_layout_tables() -> void:
	check(GameData.interior_half(1) == 20.0 and GameData.interior_half(4) == 20.0, "interior half is 20m at keep levels 1-4")
	check(GameData.interior_half(5) > GameData.interior_half(1), "interior grows at keep level 5")
	check(GameData.interior_half(10) > GameData.interior_half(5), "interior grows at keep level 10")
	check(GameData.interior_half(99) == GameData.interior_half(10), "interior stays at the last tier")
	for h in GameData.heroes():
		for key in ["name", "hp", "atk", "range", "atk_interval", "speed", "aggro", "skills"]:
			check(h.has(key), "hero %s has %s" % [h.id, key])
		if h.role == "ranged":
			check(h.range > 1.8, "ranged hero %s outranges melee" % h.id)


func test_building_layout() -> void:
	var half_tiles := floori(GameData.interior_tiles(1) / 2.0)
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
	for id in ["keep", "barracks", "tavern", "lab", "houses", "lumber", "quarry", "farm", "archery", "stable"]:
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
	var half := GameData.interior_half(1)
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
	var half := GameData.interior_half(1)
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
	var half := GameData.interior_half(1)
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
	var half := GameData.interior_half(1)
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
	for level in [1, 5, 10]:  # 성채 단계마다(keep_interior_tiers)
		var h := GameData.interior_half(level)
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
	var half := GameData.interior_half(1)
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
	check(EconomyScript.merchant_rate(h, "wood") == EconomyScript.merchant_rate(EconomyScript.hour_index(h * 3600.0 + 3599.0), "wood"), "rate is the same within an hour slot")
	check(EconomyScript.hour_index(7199.9) == 1 and EconomyScript.hour_index(7200.0) == 2, "hour_index floors on the hour")
	var allowed := [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 2.0]
	var counts := {}
	var n := 200000 * 3
	var bad := 0
	for i in 200000:
		for id in ["wood", "stone", "food"]:
			var r := EconomyScript.merchant_rate(i, id)
			if not allowed.has(r):
				bad += 1
			counts[r] = counts.get(r, 0) + 1
	check(bad == 0, "every rate is one of the 12 exact values (%d off)" % bad)
	var jack: float = counts.get(2.0, 0) / float(n)
	check(absf(jack - 0.05) <= 0.005, "jackpot share %.4f is 5%% +- 0.5%%" % jack)
	var ratio: float = counts.get(0.5, 0) / float(maxi(1, counts.get(1.5, 0)))
	check(absf(ratio - 3.0) <= 0.3, "P(0.5)/P(1.5) = %.2f is 3 +- 0.3" % ratio)
	var e = _econ(3600.0 * h + 100.0)
	check(is_equal_approx(e.seconds_to_next_rate(3600.0 * h + 100.0), 3500.0) and e.current_rate("stone", 3600.0 * h + 100.0) == EconomyScript.merchant_rate(h, "stone"), "seconds_to_next_rate / current_rate follow the hour slot")
	e.free()


func test_economy_sell() -> void:
	check(EconomyScript.sell_value("wood", 7, 0.5) == 3 and EconomyScript.sell_value("stone", 7, 1.3) == 18 and EconomyScript.sell_value("food", 100, 1.1) == 110 and EconomyScript.sell_value("wood", 10, 2.0) == 20, "sell_value floors (no float error)")
	var now := 3600.0 * 480000.0
	var e = _econ(now)
	var rate: float = e.current_rate("wood", now)
	var rate_s: float = e.current_rate("stone", now)
	var rate_f: float = e.current_rate("food", now)
	e.res.wood = 40
	e.res.stone = 9
	e.res.food = 13
	var g: int = e.sell("wood", now)
	check(g == EconomyScript.sell_value("wood", 40, rate) and e.res.wood == 0 and e.gold == g and e.gold_tenths == g * 10, "sell zeroes the resource and adds whole gold (x10 tenths)")
	var before: int = e.gold
	var g2: int = e.sell_all(now)
	check(e.res.stone == 0 and e.res.food == 0 and e.gold == before + g2 and g2 == EconomyScript.sell_value("stone", 9, rate_s) + EconomyScript.sell_value("food", 13, rate_f), "sell_all sells everything")
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
	for junk in ["{not json", "[1,2]", "{\"version\":2,\"gold\":5}", "{\"version\":6,\"gold_tenths\":1,\"res\":{},\"last_collect\":{},\"levels\":{}}"]:
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
		"merchant": {"rates": {"wood": 1.2, "stone": 0.8, "food": 2.0}, "next_change": 3600.0}}
	check(e.apply_server(reply) and e.server_gold_tenths == 1005 and e.gold_tenths == 1005 and e.gold == 100 and e.server_stage == 3 and e.kill_seq == 7 and e.res.wood == 4 and e.res.stone == 0 \
		and e.levels.lumber == 2 and e.last_collect.lumber == 900.0 and e.merchant.rates.wood == 1.2 and e.merchant.rates.food == 2.0, "apply_server takes the server snapshot")
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
		for level in [1, 5, 10]:  # 성채 단계마다
			var lane := GameData.interior_half(level) - Balance.STAIR_W - FormationScript.GATE_PASS_MARGIN
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
	var clocks := [UiKit.clock(10800.0), UiKit.clock(10800.0 * 0.95), UiKit.clock(9669.2), UiKit.clock(3599.5), UiKit.clock(59.2), UiKit.clock(-3.0)]
	check(clocks == ["3:00:00", "2:51:00", "2:41:10", "1:00:00", "01:00", "00:00"], "soldier clock h:mm:ss / mm:ss, rounded up (%s)" % [clocks])


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
	check(card._top.size() == (6 + 2 * 10) * 3 and card._top_cols.size() == card._top.size() and card._lines.size() == 3, "grade gem and two stars on top (the unique-color hexagon is gone): %d points" % card._top.size())
	card.stars = 3
	card._ensure_geo(h)
	check(card.geo_builds == 2 and card._top.size() == (6 + 3 * 10) * 3, "a star change rebuilds the geometry")
	card.hero_id = "hans"
	card._ensure_geo(GameData.hero("hans"))
	check(card.geo_builds == 3 and card._shine.is_empty(), "an R card has no shimmer")
	# 개정 15: 조각 막대(아래, 별·전투력은 그만큼 위로), 최대 승급 MAX, 승급 연출(별 하나가 날아오는 동안 그 자리 별은 지오메트리에서 빠진다)
	var y0: float = card.star_center(0).y
	card.shards = 3
	card.shard_need = 5
	card._ensure_geo(GameData.hero("hans"))
	var bar: Rect2 = card.shard_bar_rect()
	check(card.geo_builds == 4 and card.shard_text() == "조각 3 / 5" and Rect2(Vector2.ZERO, card.size).encloses(bar) and bar.size.y == HeroCardScript.BAR_H
		and is_equal_approx(card.star_center(0).y, y0 - HeroCardScript.BAR_H - HeroCardScript.BAR_GAP) and card.star_center(0).y + 9.0 < bar.position.y,
		"shard bar at the bottom reads 조각 3 / 5; the stars move up above it: bar %s" % bar)
	card.shard_need = 0
	check(card.shard_text() == "MAX", "max promotion: the bar reads MAX")
	card.shards = -1
	check(card.shard_bar_rect() == Rect2(), "no bar when shards < 0 (slot cards)")
	card.promote_fx()
	card._ensure_geo(GameData.hero("hans"))
	check(card.is_promoting() and card._flying == 2 and card._top.size() == (6 + 2 * 10) * 3 and card.promote_fxs == 1,
		"promote effect: the newest star (3rd) flies in, so only two stars are in the static geometry")
	card._process(HeroCardScript.STAR_FLY_SEC + 0.01)
	card._ensure_geo(GameData.hero("hans"))
	check(card._flying == -1 and card.is_promoting() and card._top.size() == (6 + 3 * 10) * 3, "after the flight the star is set in place while the sparkle ring fades")
	card._process(HeroCardScript.PROMOTE_FX_SEC)
	check(not card.is_promoting(), "the promote effect ends")
	card.free()
	# 상세 큰 카드(live): 피규어가 카드 높이의 대부분(별 줄만 남긴다), 별은 아래에 크게
	var big = HeroCardScript.new()
	big.size = Vector2(656, 440)
	big.live = true
	big.stars = 2
	var fr: Rect2 = big.figure_rect()
	check(fr.size.x == 378.0 and fr.size.y >= big.size.y * 0.8 and Rect2(Vector2.ZERO, big.size).encloses(fr) and big.star_center(0).y > fr.end.y
		and big._star_row()[1] == HeroCardScript.LIVE_STAR_R, "the live big card's figure fills most of it: %s in %s" % [fr, big.size])
	big.free()


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
	check(int(saved.version) == EconomyScript.SAVE_VERSION and int(saved.gold_tenths) == 72 and not saved.has("gold"), "save writes the current version with gold_tenths")
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


## 배치 기본값(오프라인 공급자)과 승급 배율·비용·최대 레벨(개정 15).
func test_deploy_and_promotion() -> void:
	check(GameData.default_deploy(4) == ["hans", "ella", "dorik", "nina"], "default deploy = starters")
	check(GameData.default_deploy(6) == ["hans", "ella", "dorik", "nina", null, null], "more slots than starters: null")
	check(GameData.default_deploy(2) == ["hans", "ella"], "fewer slots: truncated")
	check(GameData.promote_mult(0) == 1.0 and GameData.promote_mult(1) == 1.5 and GameData.promote_mult(2) == 2.25 and is_equal_approx(GameData.promote_mult(5), 7.59375) \
		and GameData.promote_mult(9) == GameData.promote_mult(5), "promotion mult = 1.5^p (p 5 = x7.59), capped at 5")
	check(range(-1, 7).map(func(p): return GameData.promote_cost(p)) == [0, 5, 25, 50, 100, 200, 0, 0] and GameData.MAX_PROMOTION == 5,
		"promotion cost p -> p+1 = 5|25|50|100|200 shards; none at the max (5)")
	check(range(0, 6).map(func(p): return GameData.max_level(p)) == [20, 30, 40, 50, 60, 70], "max level = 20 + 10 x promotion (70 at 5)")
	var gs = GameStateScript.new()
	check(gs.deploy() == GameData.default_deploy(4) and gs.hero_promotion("hans") == 0, "GameState deploy provider: starters, promotion 0")
	gs.keep_level = 5
	check(gs.deploy().size() == 8 and gs.deploy()[4] == null, "deploy length = hero slots")
	gs.free()


## 성문 회복: 최대치 상한, 부서진 성문 제외, 오를 때만 시그널.
func test_gate_repair() -> void:
	var gs = GameStateScript.new()
	gs.mode = gs.Mode.STAGE  # 방치 무적이면 피해가 안 들어간다
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
		consistent = consistent and r.new == (before == 0) and r.copies == before + 1 and r.grade == GameData.hero(r.hero_id).grade and r.shards == before
	check(consistent and seen == e.heroes, "results: new only on the first copy, copies count up per card, heroes updated: %s" % [got[0]])
	check(e.heroes.keys().all(func(id): return e.shards_of(id) == int(e.heroes[id]) - 1) and e.hero_promotions.is_empty(),
		"rev 15: a repeat pull adds a shard (new heroes start at 0); recruiting never promotes: %s" % [e.hero_shards])
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
	check(e2.heroes == e.heroes and e2.heroes.ignis is int and e2.deploy == ["ignis", null, "hans", "nina"], "save v3 round-trips heroes and deploy: %s %s" % [e2.heroes, e2.deploy])
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
	var reply := {"player": {"gold_tenths": 0, "stage": 1, "res": {}, "buildings": {}, "heroes": {"hans": {"copies": 2, "level": 1, "shards": 7, "promotion": 2}, "kyle": {"copies": 1, "level": 3}}, "deploy": ["kyle", null, "hans", null]},
		"merchant": {"rates": {"wood": 1.0, "stone": 1.0, "food": 1.0}, "next_change": 3600.0}}
	var changes := []
	o.roster_changed.connect(func(): changes.append(1))
	check(o.apply_server(reply) and o.heroes == {"hans": 2, "kyle": 1} and o.deploy == ["kyle", null, "hans", null] and o.level_of("kyle") == 3 and o.level_of("hans") == 1 and changes.size() == 1
		and o.shards_of("hans") == 7 and o.promotion_of("hans") == 2 and o.shards_of("kyle") == 0 and o.promotion_of("kyle") == 0,
		"apply_server takes heroes {copies, level, shards, promotion} (missing shards/promotion = 0) and deploy (roster_changed once)")
	check(o.apply_server(reply) and changes.size() == 1, "the same roster again does not signal")
	reply.player.heroes.hans.shards = 2
	reply.player.heroes.hans.promotion = 3
	check(o.apply_server(reply) and changes.size() == 2 and o.shards_of("hans") == 2 and o.promotion_of("hans") == 3, "a promotion (shards and promotion change) signals roster_changed")
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
	e2.hero_promotions = {"ignis": 2}
	e2.deploy = ["ignis", "ghost", "ignis", "jack", "nina"]  # 모르는 영웅·중복·미보유·슬롯 넘침
	check(gs.deploy() == ["ignis", null, null, null], "provider: slot count, unknown/duplicate/unowned heroes become null: %s" % [gs.deploy()])
	check(gs.hero_promotion("ignis") == 2 and gs.hero_promotion("hans") == 0, "provider: promotion from the roster")
	e2.levels["keep"] = 5  # roster가 있으면 성채 레벨은 roster(Economy) 건물 레벨
	check(gs.deploy().size() == 8 and gs.deploy()[4] == "nina", "provider: more slots at keep level 5")
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


## 자원별 시세(개정 11): 오프라인 결정성, 자원끼리 다름, 판매가 자기 배율, 온라인 응답 형식, 최고 배율 자원.
func test_merchant_rates() -> void:
	var ids := ["wood", "stone", "food"]
	var same_all := 0
	var cols := {"wood": [], "stone": [], "food": []}
	for h in range(480000, 482000):
		var a := []
		for id in ids:
			var r := EconomyScript.merchant_rate(h, id)
			check(r == EconomyScript.merchant_rate(h, id), "rate (%d, %s) is deterministic" % [h, id])
			a.append(r)
			cols[id].append(r)
		if a[0] == a[1] and a[1] == a[2]:
			same_all += 1
	check(same_all < 400, "resources get different rates (all-equal slots %d of 2000)" % same_all)
	check(cols.wood != cols.stone and cols.stone != cols.food and cols.wood != cols.food, "each resource has its own rate sequence")
	# 서로 다른 시세인 시간 칸에서 판매는 자기 배율
	var h := 480000
	while EconomyScript.merchant_rate(h, "wood") == EconomyScript.merchant_rate(h, "food"):
		h += 1
	var now := 3600.0 * h
	var e = _econ(now)
	e.res.wood = 100
	e.res.food = 100
	var gw: int = e.sell("wood", now)
	var gf: int = e.sell("food", now)
	check(gw == EconomyScript.sell_value("wood", 100, EconomyScript.merchant_rate(h, "wood")) and gf == EconomyScript.sell_value("food", 100, EconomyScript.merchant_rate(h, "food")) and gw != gf, "sell uses that resource's own rate (same price, different rates)")
	e.net = null
	e.merchant = {"rates": {"wood": 1.0, "stone": 1.4, "food": 1.2}, "next_change": now + 10.0}
	e.net = e  # 온라인 흉내(net != null)
	check(e.current_rate("stone", now) == 1.4 and e.current_rate("food", now) == 1.2, "online rates are used per resource")
	e.net = null
	# 서버 응답 검사: 자원 하나라도 빠지면 거부
	var logged := _errors.count
	check(not e.apply_server({"player": {"gold_tenths": 0, "stage": 1, "res": {}, "buildings": {}}, "merchant": {"rates": {"wood": 1.0}, "next_change": 3600.0}}), "apply_server rejects rates missing a resource")
	_errors.count = logged
	e.free()



## 피해 숫자 대역: 위치·살아 있음·바 높이만 있는 노드.
class DnStub extends Node:
	var global_position := Vector3.ZERO
	var alive := true
	func bar_height() -> float:
		return 1.0
	func is_alive() -> bool:
		return alive


## 피해 숫자: 형식(반올림·1.2k), 0 생략, 풀 상한 80(오래된 것부터), 독 1초 합산, 치명타 "!"·회복 "+"·회피 문구.
func test_damage_numbers() -> void:
	var dn = DamageNumbersScript.new()
	check(dn.format(7.4) == "7" and dn.format(7.5) == "8" and dn.format(999.4) == "999" and dn.format(1000.0) == "1.0k" and dn.format(1234.0) == "1.2k" and dn.format(15600.0) == "15.6k",
		"damage number format: rounded integers, 1.2k from 1000")
	var t := DnStub.new()
	dn.add(t, 0.4, DamageNumbersScript.Kind.HIT)
	dn.add(t, 0.0, DamageNumbersScript.Kind.HEAL)
	check(dn._list.is_empty(), "amounts that round to 0 are not shown")
	dn.add(t, 12.0, DamageNumbersScript.Kind.CRIT)
	dn.add(t, 5.0, DamageNumbersScript.Kind.HEAL)
	dn.add(t, 0.0, DamageNumbersScript.Kind.DODGE)
	check(dn._list.map(func(e): return e.text) == ["12!", "+5", "회피"], "crit gets '!', heal '+', dodge shows the word: %s" % [dn._list.map(func(e): return e.text)])
	dn._list.clear()
	for i in 100:
		dn.add(t, float(i + 1), DamageNumbersScript.Kind.HIT)
	check(dn._list.size() == 80 and dn._list[0].text == "21" and dn._list[-1].text == "100",
		"pool capped at %d, oldest dropped first: %d first %s" % [DamageNumbersScript.MAX_NUMBERS, dn._list.size(), dn._list[0].text])
	dn._list.clear()
	var u := DnStub.new()
	for i in 4:
		dn.add(t, 2.0, DamageNumbersScript.Kind.POISON)
		dn.add(u, 3.0, DamageNumbersScript.Kind.POISON)
	check(dn._list.is_empty() and dn._poison.size() == 2, "poison ticks are held, not shown one by one")
	dn._process(1.0)
	var texts: Array = dn._list.map(func(e): return e.text)
	check(texts.size() == 2 and texts.has("8") and texts.has("12") and dn._poison.is_empty(), "poison sums per target after 1 s: %s" % [texts])
	dn._process(0.9)
	check(dn._list.is_empty(), "numbers disappear after their life")
	dn.free()
	t.free()
	u.free()


## 개정 11 영웅 레벨: 능력치 공식(기본 × 레벨 배율 × 승급 배율 — 개정 15), 전투력, 최대 레벨(승급 반영), 비용 표(서버 levelup.test와 같은 값),
## 오프라인 레벨업(골드 tenths만 차감 — 개정 12, 이유 문구, [×10] 횟수), 저장 v2 → v3, apply_remote의 레벨업 설정 검증.
func test_hero_levels() -> void:
	GameData.load_tables()
	var hans := GameData.hero("hans")
	check(GameData.level_mult(1) == 1.0 and is_equal_approx(GameData.level_mult(10), 1.54) and is_equal_approx(GameData.level_mult(70), 5.14), "level x(1 + 0.06 x (L - 1))")
	var st := GameData.hero_stats(hans, 10, 2)  # 440 × 1.54 × 1.5², 30 × 1.54 × 1.5²
	check(is_equal_approx(st.hp, 440.0 * 1.54 * 2.25) and is_equal_approx(st.atk, 30.0 * 1.54 * 2.25), "stats = base x level mult x promotion mult (1.5^p on base and level-ups alike): %s" % [st])
	check(GameData.hero_power(hans, 1, 0) == 119 and GameData.hero_power(GameData.hero("kyle"), 1, 0) == 317 \
		and GameData.hero_power(hans, 10, 2) == roundi(440.0 * 3.465 / 10.0 + 30.0 * 3.465 * 2.0 / 0.8) and GameData.hero_power(hans, 1, 1) == 179,
		"power = round(HP / 10 + atk x 2 / interval): hans %d, kyle %d" % [GameData.hero_power(hans, 1, 0), GameData.hero_power(GameData.hero("kyle"), 1, 0)])
	var gold := func(g: String, levels: Array): return levels.map(func(l): return GameData.levelup_cost(g, l).gold)
	check(gold.call("R", [1, 2, 3, 4, 5, 10, 19, 20]) == [30, 34, 38, 42, 47, 83, 231, 258] and gold.call("SR", [1, 2, 3, 10, 19]) == [60, 67, 75, 166, 461] \
		and gold.call("SSR", [1, 2, 3, 10, 19, 69]) == [120, 134, 151, 333, 923, 266690], "gold cost table = round(base x 1.12^(L-1)), same as the server")
	check(GameData.levelup_cost("R", 1, 5) == {"gold": 191} and GameData.levelup_cost("SSR", 1, 19) == {"gold": 7614}, "cost is gold only (no food), count sums the levels")
	# 오프라인 레벨업
	var e = _econ(1000.0)
	var got := []
	e.leveled.connect(func(id, l): got.append([id, l]))
	e.gold_tenths = 2005
	e.res.food = 200
	check(e.level_up("hans", 1) and e.level_of("hans") == 2 and e.gold_tenths == 1705 and e.res.food == 200 and got == [["hans", 2]], "offline level up takes 300 tenths and no food")
	check(e.level_up("hans", 3) and e.level_of("hans") == 5 and e.gold_tenths == 565 and e.res.food == 200, "three levels at once take the summed cost")
	var notes := []
	e.notice.connect(func(t): notes.append(t))
	e.gold_tenths = 469  # 46.9골드 < 47
	check(not e.level_up("hans") and e.level_of("hans") == 5 and notes == ["골드 부족"] and e.levelup_block("hans") == "골드 부족", "not enough gold: no change, notice")
	e.gold_tenths = 100000
	e.res.food = 0
	check(e.levelup_block("hans") == "" and e.levelup_block("arteon") == "보유하지 않은 영웅", "no food needed / not owned reason")
	e.gold_tenths = 0
	e.res.food = 100000
	check(e.levelup_block("hans") == "골드 부족", "gold short even with plenty of food")
	# [×10] 횟수: 3회분만 있으면 3
	var c3: Dictionary = GameData.levelup_cost("R", 5, 3)
	e.gold_tenths = int(c3.gold) * 10
	e.res.food = 0
	check(e.levelup_affordable("hans") == 3 and e.levelup_block("hans", 4) != "", "x10 counts the affordable levels (3)")
	e.gold_tenths = 10000000
	e.res.food = 10000000
	e.hero_levels["hans"] = 15
	check(e.levelup_affordable("hans") == 5 and e.levelup_block("hans", 6) == "최대 레벨", "x10 stops at the max level (15 -> 20)")
	e.hero_levels["hans"] = 20
	check(not e.level_up("hans") and e.level_of("hans") == 20 and e.levelup_affordable("hans") == 0, "max level blocks")
	e.heroes["hans"] = 9  # 옛 규칙의 별(중복)은 상한과 무관하다(개정 15)
	check(not e.level_up("hans") and e.level_of("hans") == 20, "copies no longer raise the cap")
	e.hero_promotions["hans"] = 1  # 승급 1 → 최대 30
	check(e.level_up("hans", 10) and e.level_of("hans") == 30, "a promotion raises the cap")
	e.heroes["hans"] = 2
	# GameState 공급자: 레벨
	var gs = GameStateScript.new()
	check(gs.hero_level("hans") == 1, "no roster: level 1")
	gs.roster = e
	check(gs.hero_level("hans") == 30 and gs.hero_level("ella") == 1, "provider: level from the roster")
	gs.free()
	# 저장 v3 왕복, v2 → v3(level 1)
	e.save_path = ECON_TMP
	e.save()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ECON_TMP))
	check(int(raw.version) == EconomyScript.SAVE_VERSION and raw.heroes.hans.copies == 2.0 and raw.heroes.hans.level == 30.0 and raw.heroes.ella.level == 1.0
		and raw.heroes.hans.promotion == 1.0 and raw.heroes.hans.shards == 0.0, "save v6 writes heroes {copies, level, shards, promotion}")
	var e2 = _econ(0.0)
	e2.save_path = ECON_TMP
	e2.load_save(1000.0)
	check(e2.heroes == e.heroes and e2.level_of("hans") == 30 and e2.hero_levels.hans is int and e2.level_of("nina") == 1 and e2.promotion_of("hans") == 1, "save round-trips levels and promotion")
	var v2 := {"version": 2, "gold_tenths": 5, "res": {"wood": 0, "stone": 0, "food": 0}, "last_collect": {"lumber": 0, "quarry": 0, "farm": 0},
		"levels": {"lumber": 1, "quarry": 1, "farm": 1}, "heroes": {"hans": 2, "ignis": 1}, "deploy": ["ignis", "hans"]}
	_write(ECON_TMP, JSON.stringify(v2))
	e2.load_save(1000.0)
	check(e2.gold_tenths == 5 and e2.heroes == {"hans": 2, "ignis": 1} and e2.level_of("hans") == 1 and e2.level_of("ignis") == 1 and e2.deploy == ["ignis", "hans"]
		and e2.shards_of("hans") == 1 and e2.shards_of("ignis") == 0 and e2.hero_promotions == {"hans": 0, "ignis": 0}, "a v2 save loads with level 1; old stars become shards (copies - 1), promotion 0")
	v2.version = 3  # v3인데 heroes가 옛 형식이면 깨진 저장
	_write(ECON_TMP, JSON.stringify(v2))
	e2.load_save(1000.0)
	check(e2.gold_tenths == 0 and e2.heroes == _econ_starters(), "a v3 save with {id: copies} heroes is corrupt: defaults")
	DirAccess.remove_absolute(ECON_TMP)
	e.free()
	e2.free()
	# apply_remote: 레벨업 설정 검증(서버 seed와 같은 규칙)
	var logged := _errors.count
	for bad in [["hero_max_level_base", "0"], ["hero_max_level_per_promotion", "-1"], ["levelup_gold_SSR", "1.5"], ["levelup_gold_R", "-10"], ["hero_level_stat", "-0.1"],
			["promote_shards", "5|25|50|100"], ["promote_shards", "5|25|50|100|0"], ["promote_shards", "5|25|x|100|200"], ["promote_shards", ""], ["promote_mult", "0.9"], ["promote_mult", "x"]]:
		var p := _payload()
		p.config[bad[0]] = bad[1]
		check(not GameData.apply_remote(p) and GameData.errors == 1, "apply_remote rejects %s = %s" % bad)
	_errors.count = logged
	GameData.load_tables()
	check(GameData.errors == 0 and GameData.config_num("hero_max_level_base") == 20.0, "default tables restored")


## 개정 15 승급(오프라인): 조각 −비용·승급 +1·promoted·저장, 부족·최대·미보유 이유와 알림(아무것도 안 바뀜), 능력치 × 1.5와 최대 레벨 +10,
## 5단계 누적 비용(375)과 ×7.59, save v5 → v6(옛 별 = 조각 copies − 1, 승급 0), v6 왕복, 깨진 v6.
func test_promotion() -> void:
	GameData.load_tables()
	var e = _econ(1000.0)
	var got := []
	var notes := []
	e.promoted.connect(func(id, p): got.append([id, p]))
	e.notice.connect(func(t): notes.append(t))
	var arteon := GameData.hero("arteon")
	check(e.promote_block("hans") == "not_enough_shards" and e.promote_cost("hans") == 5 and e.promote_block("arteon") == "not_owned",
		"a starter has no shards (5 needed); an unowned hero cannot promote")
	check(not e.promote("hans") and notes == ["조각 부족"] and e.promotion_of("hans") == 0 and got.is_empty(), "not enough shards: a notice, nothing changes")
	e.heroes["arteon"] = 13
	e.hero_shards["arteon"] = 12
	e.hero_levels["arteon"] = 20
	var before := GameData.hero_stats(arteon, 20, 0)
	check(e.promote("arteon") and e.shards_of("arteon") == 7 and e.promotion_of("arteon") == 1 and e.heroes.arteon == 13 and e.level_of("arteon") == 20 and got == [["arteon", 1]],
		"[승급] spends 5 shards (12 -> 7), promotion 1, copies and level unchanged, promoted signal")
	var after := GameData.hero_stats(arteon, 20, e.promotion_of("arteon"))
	check(is_equal_approx(after.hp, before.hp * 1.5) and is_equal_approx(after.atk, before.atk * 1.5) and GameData.max_level(e.promotion_of("arteon")) == 30
		and e.levelup_block("arteon") == "골드 부족", "promotion: HP/atk x1.5 (base and level-ups), max level 20 -> 30 (Lv 20 can level again)")
	check(e.promote_block("arteon") == "not_enough_shards" and e.promote_cost("arteon") == 25, "next step costs 25")
	e.hero_shards["arteon"] = 25 + 50 + 100 + 200
	for i in 4:
		e.promote("arteon")
	check(e.promotion_of("arteon") == 5 and e.shards_of("arteon") == 0 and is_equal_approx(GameData.promote_mult(5), 7.59375) and GameData.max_level(5) == 70,
		"25 + 50 + 100 + 200 shards take promotion 1 -> 5 (x7.59, max level 70)")
	e.hero_shards["arteon"] = 999
	notes.clear()
	check(e.promote_block("arteon") == "max_promotion" and not e.promote("arteon") and notes == ["최대 승급"] and e.shards_of("arteon") == 999 and e.promotion_of("arteon") == 5,
		"max promotion: a notice, shards kept")
	# 저장: v6 왕복, v5 → v6, 깨진 v6
	e.save_path = ECON_TMP
	e.save()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ECON_TMP))
	check(int(raw.version) == EconomyScript.SAVE_VERSION and raw.heroes.arteon == {"copies": 13.0, "level": 20.0, "shards": 999.0, "promotion": 5.0}, "save v6 writes shards and promotion")
	var e2 = _econ(0.0)
	e2.save_path = ECON_TMP
	e2.load_save(1000.0)
	check(e2.shards_of("arteon") == 999 and e2.promotion_of("arteon") == 5 and e2.hero_promotions.arteon is int and e2.shards_of("hans") == 0, "save v6 round-trips shards and promotion")
	var v5 := {"version": 5, "gold_tenths": 5, "res": {"wood": 0, "stone": 0, "food": 0}, "last_collect": {"lumber": 0, "quarry": 0, "farm": 0},
		"levels": {"lumber": 1, "quarry": 1, "farm": 1}, "build": null, "heroes": {"hans": {"copies": 4, "level": 9}, "ignis": {"copies": 1, "level": 2}}, "deploy": ["ignis", "hans"]}
	_write(ECON_TMP, JSON.stringify(v5))
	e2.load_save(1000.0)
	check(e2.gold_tenths == 5 and e2.shards_of("hans") == 3 and e2.promotion_of("hans") == 0 and e2.shards_of("ignis") == 0 and e2.level_of("hans") == 9 and e2.heroes == {"hans": 4, "ignis": 1},
		"save v5 -> v6: old stars become shards (copies - 1 = 3), promotion 0, levels kept")
	var hp_v5: float = GameData.hero_stats(GameData.hero("hans"), 9, e2.promotion_of("hans")).hp
	check(is_equal_approx(hp_v5, 440.0 * 1.48), "the old +10%%/star bonus is gone: 3 stars of copies give no stat bonus (%.1f)" % hp_v5)
	var v6 := v5.duplicate(true)
	v6.version = 6
	_write(ECON_TMP, JSON.stringify(v6))  # v6인데 shards·promotion이 없다
	e2.load_save(1000.0)
	check(e2.gold_tenths == 0 and e2.heroes == _econ_starters() and e2.hero_shards.is_empty(), "a v6 save without shards/promotion is corrupt: defaults")
	DirAccess.remove_absolute(ECON_TMP)
	e.free()
	e2.free()


## 개정 12 건물: 표(9행·파일 순서), 비용·시간 공식(서버 buildings.test와 같은 값), 단계 표(슬롯·내부), 효과 수치(성 HP·성문 HP·인구·
## 막사·연구소·주점 확률), 업그레이드 판단(이유 코드 순서·선행 목록), 오프라인 업그레이드(즉시 차감·일꾼·자동 수집·게으른 완료),
## 저장 v4·v3 → v4, 온라인 응답(buildings·build — 첫 반영은 완료가 아님), GameState(건물 레벨 → 성·성문 HP·슬롯), apply_remote 검증.
func test_buildings() -> void:
	GameData.load_tables()
	var ids: Array = GameData.buildings().map(func(b): return b.id)
	check(GameData.errors == 0 and ids == ["keep", "gate", "barracks", "tavern", "lab", "houses", "lumber", "quarry", "farm", "archery", "stable"], "buildings.csv: 11 rows in file order: %s" % [ids])
	var gate := GameData.building_def("gate")
	check(gate.name == "성문" and gate.max_level == 30.0 and gate.stone == 250.0 and gate.base_sec == 45.0 and gate.req1 == "quarry" and gate.req2 == "", "gate row (empty req is \"\")")
	# 비용 = round(값 × 1.35^(L−1)), 시간 = round(base_sec × 1.5^(L−1)) — 서버와 같은 표
	check(GameData.build_cost("lumber", 1) == {"wood": 60, "stone": 80, "food": 40} and GameData.build_sec("lumber", 1) == 20, "lumber 1 -> 2: 60/80/40, 20 s")
	check(GameData.build_cost("keep", 2) == {"wood": 405, "stone": 405, "food": 270} and GameData.build_sec("keep", 2) == 90, "keep 2 -> 3")
	check(GameData.build_cost("keep", 10) == {"wood": 4468, "stone": 4468, "food": 2979} and GameData.build_sec("keep", 10) == 2307, "keep 10 -> 11: about 4,470 / 2,980, about 38 min")
	check(GameData.build_cost("gate", 2) == {"wood": 203, "stone": 338, "food": 0} and GameData.build_sec("gate", 2) == 68, "gate 2 -> 3: 337.5 and 67.5 round away from zero")
	check(GameData.build_sec("lumber", 20) == 44337 and GameData.build_cost("keep", 29) == {"wood": 1338033, "stone": 1338033, "food": 892022}, "level 20 is about 2,217x the base time; level 29 costs")
	check(GameData.build_cost("mine", 1).is_empty() and GameData.build_sec("mine", 1) == 0, "unknown building: no cost, no time")
	# 단계 표
	check(GameData.parse_tiers("1:4|5:8|10:12") == [[1, 4.0], [5, 8.0], [10, 12.0]] and GameData.parse_tiers(" 1 : 20 | 5:24 ") == [[1, 20.0], [5, 24.0]], "tier tables parse")
	var bad_tiers := ["", "4|8|12", "2:4|5:8", "1:4|5:8|5:9", "1:4|3:8|2:9", "1:x", "1:4|", "1:4|5", "a:1", "1.5:4"]
	check(bad_tiers.all(func(s): return GameData.parse_tiers(s).is_empty()), "malformed tier tables are rejected")
	check([1, 4, 5, 9, 10, 30].map(func(l): return GameData.hero_slots(l)) == [4, 4, 8, 8, 12, 12], "hero slots by keep tier: 4/8/12")
	check([1, 4, 5, 10].map(func(l): return GameData.interior_tiles(l)) == [20, 20, 24, 28] and GameData.interior_half(5) == 24.0, "interior tiles by keep tier: 20/24/28")
	# 효과 수치
	check(GameData.castle_hp_max(1) == 1000.0 and GameData.castle_hp_max(5) == 1800.0 and GameData.gate_hp_max(3) == 1200.0, "castle hp = 1000 + 200 x (keep - 1), gate hp = 400 x gate")
	check([0, 1, 2, 3, 30].map(func(l): return GameData.population(l)) == [6, 6, 8, 10, 64], "population = 6 + 2 x (houses - 1)")
	check(GameData.lab_atk_bonus(1) == 0.0 and is_equal_approx(GameData.lab_atk_bonus(11), 0.3), "lab +3% per level above 1")
	var r1 := GameData.gacha_rates(1)
	var r11 := GameData.gacha_rates(11)
	check(is_equal_approx(r1.ssr, 0.03) and is_equal_approx(r1.sr, 0.17) and is_equal_approx(r11.ssr, 0.04) and is_equal_approx(r11.sr, 0.2), "tavern: SSR +0.1%p, SR +0.3%p per level")
	var hans := GameData.hero("hans")
	var st := GameData.hero_stats(hans, 1, 0, {"barracks": 5, "lab": 3})
	check(st.hp == 440.0 and is_equal_approx(st.atk, 30.0 * 1.06) and GameData.hero_stats(hans, 1, 0) == {"hp": 440.0, "atk": 30.0},
		"hero atk x(1 + lab); the barracks no longer raises hero HP (rev 13): %s" % [st])
	check(GameData.hero_power(hans, 1, 0, {"barracks": 5, "lab": 3}) == roundi(440.0 / 10.0 + 30.0 * 1.06 * 2.0 / 0.8), "power uses the lab bonus")
	var rig := func(): return 0.0305  # 등급 굴림 0.0305: 주점 1(SSR 3%)은 SR, 주점 2(3.1%)는 SSR
	check(EconomyScript.roll_gacha(1, rig)[0].grade == "SR" and EconomyScript.roll_gacha(1, rig, 2)[0].grade == "SSR", "offline recruiting uses the tavern odds")
	# 판단(순수 함수): unknown → max_level → keep_cap → prereq → in_progress/builder_busy → not_enough
	var none := {"wood": 0, "stone": 0, "food": 0}
	var rich := {"wood": 1000000, "stone": 1000000, "food": 1000000}
	var tav := _lv({"keep": 5, "tavern": 3, "barracks": 3})
	check(EconomyScript.upgrade_block_for("mine", _lv({}), "", rich) == "unknown", "unknown building")
	check(EconomyScript.upgrade_block_for("farm", _lv({"farm": 30, "keep": 30}), "keep", none) == "max_level", "max level comes first")
	check(EconomyScript.upgrade_block_for("lumber", _lv({}), "keep", none) == "keep_cap", "no building above the keep (target 2 > keep 1)")
	check(EconomyScript.upgrade_block_for("keep", _lv({"keep": 3, "barracks": 3}), "lab", none) == "prereq", "keep 4 needs gate >= 3")
	check(EconomyScript.upgrade_block_for("tavern", _lv({"keep": 5, "tavern": 3, "barracks": 2}), "lab", none) == "prereq", "tavern 4 needs barracks >= 3")
	check(EconomyScript.upgrade_block_for("tavern", tav, "lab", none) == "builder_busy" and EconomyScript.upgrade_block_for("tavern", tav, "tavern", none) == "in_progress", "one builder: busy elsewhere / this one")
	check(EconomyScript.upgrade_block_for("tavern", tav, "", none) == "not_enough" and EconomyScript.upgrade_block_for("tavern", tav, "", GameData.build_cost("tavern", 3)) == "", "resources last; the exact cost is enough")
	check(EconomyScript.upgrade_block_for("keep", _lv({}), "", {"wood": 300, "stone": 300, "food": 199}) == "not_enough" and EconomyScript.upgrade_block_for("keep", _lv({}), "", {"wood": 300, "stone": 300, "food": 200}) == "", "keep 1 -> 2 needs gate/barracks >= 1 and 300/300/200")
	check(["unknown", "max_level", "keep_cap", "prereq", "in_progress", "builder_busy", "not_enough", "waiting"].all(func(c): return EconomyScript.BLOCK_TEXT.has(c)), "every reason code has a text")
	# 오프라인 업그레이드
	var now := 1.8e9
	var e = _econ(now)
	var started := []
	var done := []
	var notes := []
	e.build_started.connect(func(id, f): started.append([id, f]))
	e.building_done.connect(func(id, l): done.append([id, l]))
	e.notice.connect(func(tx): notes.append(tx))
	check(e.levels.size() == 11 and e.building_level("keep") == 1 and e.build.is_empty() and e.population() == 6 and e.upgrade_cost("keep") == {"wood": 300, "stone": 300, "food": 200} and e.upgrade_sec("keep") == 60,
		"new game: 11 buildings at level 1, builder idle, population 6")
	check(e.requirements("keep") == [{"id": "gate", "need": 1, "have": 1, "ok": true}, {"id": "barracks", "need": 1, "have": 1, "ok": true}]
		and e.requirements("lumber") == [{"id": "keep", "need": 2, "have": 1, "ok": false}], "requirements: keep cap first, then req1/req2 at target - 1: %s" % [e.requirements("lumber")])
	check(not e.upgrade("lumber", now) and notes == [EconomyScript.BLOCK_TEXT.keep_cap] and e.upgrade_block("keep", now) == "not_enough", "blocked upgrades only show the reason")
	e.res = {"wood": 1000, "stone": 1000, "food": 1000}
	check(e.upgrade("keep", now) and e.res == {"wood": 700, "stone": 700, "food": 800} and e.build == {"id": "keep", "finish": now + 60.0} and started == [["keep", now + 60.0]],
		"offline upgrade takes the cost at once and starts the builder: %s %s" % [e.res, e.build])
	check(e.upgrade_block("keep", now) == "in_progress" and is_equal_approx(e.build_left(now + 15.0), 45.0) and is_equal_approx(e.build_progress(now + 15.0), 0.25) and e.is_building("keep"),
		"builder busy: left 45 s, progress 25%")
	e.complete_due(now + 59.9)
	check(e.building_level("keep") == 1 and done.is_empty(), "not done before the finish time")
	e.complete_due(now + 60.0)
	check(e.building_level("keep") == 2 and e.build.is_empty() and done == [["keep", 2]] and e.build_left(now + 60.0) == 0.0, "lazy completion: level +1, builder free, building_done")
	var t := now + 100.0
	check(e.upgrade("barracks", t) and e.upgrade_block("houses", t) == "builder_busy" and not e.upgrade("houses", t) and notes[-1] == EconomyScript.BLOCK_TEXT.builder_busy, "one builder: a second building waits")
	e.finish_build_now()
	check(e.building_level("barracks") == 2 and e.build.is_empty() and done[-1] == ["barracks", 2], "finish_build_now completes the build (test hook)")
	# 자원 건물: 시작할 때 자동 수집(남은 초 유지) — 쌓인 20으로 모자란 목재를 채운다
	e.res = {"wood": 40, "stone": 80, "food": 40}
	e.last_collect.lumber = t - 150.0
	check(e.upgrade_block("lumber", t) == "" and e.upgrade("lumber", t) and e.res == {"wood": 0, "stone": 0, "food": 0} and is_equal_approx(e.last_collect.lumber, t - 30.0),
		"a resource building collects first and the collected wood pays: %s" % [e.res])
	# 저장 v4 왕복, 꺼진 동안 끝난 건설은 불러올 때 완료
	e.save_path = ECON_TMP
	e.save()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ECON_TMP))
	check(int(raw.version) == EconomyScript.SAVE_VERSION and raw.levels.size() == 11 and raw.levels.keep == 2.0 and raw.build.id == "lumber", "save writes every building level and the builder")
	var e2 = _econ(0.0)
	e2.save_path = ECON_TMP
	e2.load_save(t + 1.0)
	check(e2.levels == e.levels and e2.levels.keep is int and e2.build == e.build, "save v4 round-trips levels and the builder")
	var d2 := []
	e2.building_done.connect(func(id, l): d2.append([id, l]))
	e2.load_save(t + 21.0)  # 벌목장 20초 — 꺼져 있는 동안 끝났다
	check(e2.building_level("lumber") == 2 and e2.build.is_empty() and d2 == [["lumber", 2]], "a build that finished while the app was closed completes on load")
	var v3 := {"version": 3, "gold_tenths": 5, "res": {"wood": 1, "stone": 0, "food": 0}, "last_collect": {"lumber": t, "quarry": t, "farm": t},
		"levels": {"lumber": 3, "quarry": 1, "farm": 2}, "heroes": {"hans": {"copies": 1, "level": 4}}, "deploy": ["hans"]}
	_write(ECON_TMP, JSON.stringify(v3))
	e2.load_save(t)
	check(e2.gold_tenths == 5 and e2.levels == _lv({"lumber": 3, "farm": 2}) and e2.build.is_empty() and e2.level_of("hans") == 4, "save v3 -> v4: keep/gate and the new buildings at 1, no builder: %s" % [e2.levels])
	for junk in [{"build": {"id": "mine", "finish": 1.0}}, {"build": {"id": "keep"}}, {"build": 5}, {"levels": {"lumber": 1, "quarry": 1, "farm": 1, "keep": "x"}}]:
		var bad: Dictionary = v3.duplicate(true)
		bad.version = 4
		bad.merge(junk, true)
		_write(ECON_TMP, JSON.stringify(bad))
		e2.load_save(t)
		check(e2.gold_tenths == 0 and e2.build.is_empty() and e2.building_level("lumber") == 1, "malformed v4 builder/levels (%s) is a corrupt save" % [junk])
	DirAccess.remove_absolute(ECON_TMP)
	# GameState: 건물 레벨 → 성·성문 HP, 슬롯
	var gs = GameStateScript.new()
	gs.roster = e
	gs.refill()
	check(gs.building_level("keep") == 2 and gs.castle_hp_max == 1200.0 and gs.gate_hp_max == 400.0 and gs.hero_count() == 4, "GameState reads building levels from the roster")
	gs.castle_hp = 1100.0
	gs.gate_hp[1] = 0.0
	e.levels.keep = 3
	e.levels.gate = 2
	gs.apply_levels()
	check(gs.castle_hp_max == 1400.0 and gs.castle_hp == 1300.0 and gs.gate_hp_max == 800.0 and gs.gate_hp[0] == 800.0 and gs.gate_hp[1] == 0.0,
		"apply_levels: max HP to the new level, current HP up by the gain, a broken gate stays broken")
	e.levels.keep = 5
	check(gs.hero_count() == 8 and gs.deploy().size() == 8, "keep 5: 8 slots")
	gs.free()
	e.free()
	e2.free()
	# 온라인 응답: 모든 건물 레벨·일꾼. 첫 반영의 레벨 차이는 완료가 아니고, 그 뒤 레벨이 오르면 building_done
	var o = _econ(1000.0)
	var od := []
	o.building_done.connect(func(id, l): od.append([id, l]))
	var reply := {"player": {"gold_tenths": 0, "stage": 1, "res": {}, "buildings": {"keep": {"level": 3}, "lumber": {"level": 2, "last_collect": 900.0}},
		"build": {"id": "gate", "finish": 2000.0}, "population": 6}, "merchant": {"rates": {"wood": 1.0, "stone": 1.0, "food": 1.0}, "next_change": 3600.0}}
	check(o.apply_server(reply) and o.building_level("keep") == 3 and o.building_level("gate") == 1 and o.levels.lumber == 2 and o.build == {"id": "gate", "finish": 2000.0} and od.is_empty(),
		"first reply: levels and builder from the server, no building_done")
	reply.player.buildings["gate"] = {"level": 2}
	reply.player.build = null
	check(o.apply_server(reply) and o.building_level("gate") == 2 and o.build.is_empty() and od == [["gate", 2]], "a later reply with a higher level signals building_done once")
	check(o.apply_server(reply) and od.size() == 1, "the same levels again do not signal")
	var logged := _errors.count
	reply.player.build = "gate"
	check(not o.apply_server(reply) and o.building_level("gate") == 2, "apply_server rejects a malformed builder")
	_errors.count = logged
	o.free()
	# apply_remote: 건물 표·설정 검증(서버 seed와 같은 규칙) — 틀리면 아무것도 안 바꾼다
	var before := _tables_hash()
	for entry in [["req unknown", 1], ["req not a string", 1], ["cost negative", 1], ["cost not an integer", 1], ["base_sec 0", 1], ["max_level 0", 1],
			["building not in the layout", 1], ["keep missing", 1], ["resource building not a building", 2], ["table missing", 1],
			["tiers malformed", 1], ["interior below 20 tiles", 1], ["tavern rate above 1", 1], ["population not an integer", 1], ["building config missing", 1]]:
		var q := _payload()
		_corrupt_buildings(q, entry[0])
		check(not GameData.apply_remote(q) and GameData.errors == entry[1] and _tables_hash() == before, "apply_remote rejects: %s (errors %d)" % [entry[0], GameData.errors])
	var p := _payload()
	p.buildings[1].stone = 300
	check(GameData.apply_remote(p) and GameData.build_cost("gate", 1).stone == 300, "a valid remote buildings table replaces the built-in one")
	_errors.count = logged
	GameData.load_tables()
	check(GameData.errors == 0 and GameData.build_cost("gate", 1).stone == 250, "default tables restored")


## 모든 건물 레벨 1에 o를 덮은 사전.
func _lv(o: Dictionary) -> Dictionary:
	var out := {}
	for b in GameData.buildings():
		out[b.id] = 1
	out.merge(o, true)
	return out


## payload q의 건물 표·설정을 이름에 맞게 한 곳 망가뜨린다.
func _corrupt_buildings(q: Dictionary, what: String) -> void:
	match what:
		"req unknown": q.buildings[3].req1 = "mine"
		"req not a string": q.buildings[3].req1 = 5
		"cost negative": q.buildings[4].wood = -150
		"cost not an integer": q.buildings[4].stone = 1.5
		"base_sec 0": q.buildings[5].base_sec = 0
		"max_level 0": q.buildings[8].max_level = 0
		"building not in the layout": q.buildings.append({"id": "mine", "name": "광산", "max_level": 30, "wood": 1, "stone": 1, "food": 1, "base_sec": 10, "req1": null, "req2": null})
		"keep missing": q.buildings.remove_at(0)
		"resource building not a building": q.buildings.remove_at(7)  # 채석장: 성문의 선행이자 자원 건물
		"table missing": q.erase("buildings")
		"tiers malformed": q.config.keep_slot_tiers = "4|8|12"
		"interior below 20 tiles": q.config.keep_interior_tiers = "1:18|5:24"
		"tavern rate above 1": q.config.tavern_sr_per_level = "1.5"
		"population not an integer": q.config.pop_base = "6.5"
		"building config missing": q.config.erase("castle_hp_per_level")


## 개정 14 §1: 누른 시간·움직임 → 탭(미정) / 회전 대기 / 팬. 회전은 피벗을 안 옮기고 제한이 없다.
func test_rotate_hold_state() -> void:
	var Rig := preload("res://scripts/camera_rig.gd")
	check(Rig.hold_state(0.1, 0.0) == "tap" and Rig.hold_state(Rig.HOLD_SEC - 0.01, 3.0) == "tap", "hold_state: short press is still undecided")
	check(Rig.hold_state(Rig.HOLD_SEC, 0.0) == "hold" and Rig.hold_state(2.0, Rig.DRAG_THRESHOLD_PX) == "hold", "hold_state: 0.35 s without moving is rotate-ready")
	check(Rig.hold_state(0.1, Rig.DRAG_THRESHOLD_PX + 1.0) == "pan" and Rig.hold_state(2.0, 50.0) == "pan", "hold_state: moving past the threshold is a pan")
	var rig := Rig.new()
	rig.rotate_yaw(100.0)
	rig.rotate_yaw(100.0)
	check(is_equal_approx(rig.rotation_degrees.y, -160.0) and rig.position == Vector3.ZERO, "rotate_yaw wraps past 180 (no limit), pivot kept: %s" % rig.rotation_degrees.y)
	rig.free()


## 개정 12-2 §3 공격 동기화: 쓰는 공격 애니메이션(영웅·몬스터·상인)마다 타격 비율이 있고 0 < frac < 1, 그 애니메이션이 GLB에 있다.
func test_hit_frac() -> void:
	var used := {}
	for h in GameData.heroes():
		var spec := Art.hero_spec(h)
		used[spec.anims.attack] = spec.scene
	for key in Art.MONSTER_MODELS:
		used[Art.MONSTER_MODELS[key].anims.attack] = Art.MONSTER_MODELS[key].scene
	used[Art.MERCHANT_MODEL.anims.attack] = Art.MERCHANT_MODEL.scene
	check(used.size() >= 7, "attack animations in use: %s" % [used.keys()])
	for anim in used:
		var f: float = Art.HIT_FRAC.get(anim, -1.0)
		check(f > 0.0 and f < 1.0, "hit_frac for %s in (0, 1): %s" % [anim, f])
		var root: Node = (load(used[anim]) as PackedScene).instantiate()
		var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
		check(ap.has_animation(anim) and ap.get_animation(anim).length > 0.0, "%s plays %s" % [used[anim], anim])
		root.free()
	check(Art.ATTACK_FIT > 0.0 and Art.ATTACK_FIT < 1.0, "attack animation fits inside the interval (x %.2f)" % Art.ATTACK_FIT)


## 개정 13 병사: 표·티어 배율·1마리 시간 공식(서버 soldiers.test와 같은 값)·키, 자동 배치 순서, 합성(5 → 1, 부족·최대, 배치 자르기)·
## 배치 검사(보유·인구·키), save v5 왕복·v4 → v5·깨진 v5, apply_remote 검증, 성채 앞 자리 격자(66칸·겹침 없음·상인·부지 피함·대열), 말 메시.
## 개정 16 훈련: 비용·시간·묶음 상한 공식, 이유(train_block), 시작·수령·취소(50% 내림 환불), 자동 생산 없음(시간이 흘러도·옛 save를 불러도),
## save v7 왕복·v6 → v7(생산 시계 버림·빈 대기열)·깨진 v7, 온라인 응답의 training.
func test_soldiers() -> void:
	GameData.load_tables()
	var ids: Array = GameData.soldiers().map(func(s): return [s.id, s.building])
	check(GameData.errors == 0 and ids == [["infantry", "barracks"], ["archer", "archery"], ["cavalry", "stable"]], "soldiers.csv: 3 rows in file order: %s" % [ids])
	check(GameData.soldier_of_building("stable") == "cavalry" and GameData.soldier_of_building("lab") == "" and GameData.building_def("barracks").name == "보병 막사", "soldier buildings")
	var i1 := GameData.soldier_stats("infantry", 1)
	var i2 := GameData.soldier_stats("infantry", 2)
	check(i1 == {"hp": 320.0, "atk": 22.0, "range": 1.6, "atk_interval": 1.0, "speed": 4.0, "aggro": 7.0} and i2.hp == 640.0 and i2.atk == 44.0 and i2.range == 1.6 and i2.speed == 4.0
		and GameData.soldier_stats("cavalry", 5).hp == 240.0 * 16.0 and GameData.soldier_stats("knight", 1).is_empty(), "tier t: hp/atk x 2^(t-1), the rest unchanged: %s" % [i2])
	check(GameData.soldier_stats("cavalry", 1).speed == 2.0 * GameData.soldier_stats("infantry", 1).speed, "cavalry moves twice as fast as infantry")
	check(GameData.soldier_unit_sec(1) == 10800.0 and GameData.soldier_unit_sec(2) == 9000.0 and GameData.soldier_unit_sec(6) == 1800.0 and GameData.soldier_unit_sec(7) == 10800.0,
		"unit time = 180 - 30 x step min (rev 19): Lv 1 3:00, Lv 2 2:30, Lv 6 0:30, Lv 7 back to 3:00 (next tier)")
	check(GameData.train_max(1) == 10 and GameData.train_max(5) == 18 and GameData.train_max(30) == 68, "batch cap = 10 + 2 x (L - 1)")
	check(EconomyScript.train_cost("infantry", 8) == {"food": 240, "wood": 160} and EconomyScript.train_cost("archer", 3) == {"food": 75, "wood": 90}
		and EconomyScript.train_cost("cavalry", 1) == {"food": 40, "stone": 20} and EconomyScript.train_cost("knight", 1).is_empty(), "train cost = unit cost x n (food:30|wood:20 ...)")
	check(GameData.parse_train_cost(" food : 40 | stone:20 ") == {"food": 40, "stone": 20} and GameData.parse_train_cost("0") == {}
		and ["", "food", "food:-1", "food:+1", "food:1.5", "gold:5", "food:1|food:2", "food:1|", "food:x"].all(func(x): return GameData.parse_train_cost(x) == null),
		"parse_train_cost: 'res:amount|...' with wood/stone/food and non-negative integers, '0' is free (same as the server)")
	check(EconomyScript.parse_soldier_key("archer:2") == ["archer", 2] and EconomyScript.soldier_key("archer", 2) == "archer:2"
		and ["knight:1", "archer:0", "archer:6", "archer:01", "archer", "archer:1:2", 5].all(func(k): return EconomyScript.parse_soldier_key(k).is_empty()), "soldier keys 'type:tier' (tier 1..5)")
	var owned := {"archer:1": 4, "infantry:1": 3, "cavalry:2": 1, "archer:2": 2, "cavalry:1": 5, "knight:1": 9}
	check(EconomyScript.auto_deploy_for(owned, 6) == {"cavalry:2": 1, "archer:2": 2, "infantry:1": 3} and EconomyScript.auto_deploy_for(owned, 9) == {"cavalry:2": 1, "archer:2": 2, "infantry:1": 3, "cavalry:1": 3},
		"auto deploy: higher tier first, the same tier infantry -> cavalry -> archer, up to the population: %s" % [EconomyScript.auto_deploy_for(owned, 9)])
	check(EconomyScript.trim_deploy({"infantry:1": 5, "archer:1": 2, "cavalry:2": 1}, {"infantry:1": 3, "archer:1": 2}) == {"infantry:1": 3, "archer:1": 2}, "trim_deploy cuts the deploy to what is owned")
	# 훈련(개정 16, 오프라인)
	var now := 1.8e9
	var e = _econ(now)
	var notes := []
	var changes := [0]
	e.notice.connect(func(t): notes.append(t))
	e.training_changed.connect(func(): changes[0] += 1)
	check(e.soldier_counts().is_empty() and e.soldier_deploy().is_empty() and e.deployed_total() == 0 and e.population() == 6 and e.train_queues.is_empty()
		and not e.last_collect.has("barracks") and e.training("barracks") == {"count": 0, "tier": 1, "finish": 0.0, "ready": false}, "new game: no soldiers, empty training queues, no production clocks")
	check(e.train_block("lab", 1) == "unknown" and e.train_block("barracks", 0) == "bad_count" and e.train_block("barracks", 11) == "bad_count"
		and e.train_block("barracks", 1) == "not_enough" and not e.start_training("barracks", 1) and notes[-1] == EconomyScript.TRAIN_TEXT.not_enough and e.train_queues.is_empty(),
		"train_block: not a soldier building / count outside 1..10 / not enough resources; a refused start only shows the reason")
	e.res = {"wood": 1000, "stone": 1000, "food": 1000}
	var t0: float = e.time_now()
	check(e.start_training("barracks", 8) and e.res == {"wood": 840, "stone": 1000, "food": 760} and e.training("barracks").count == 8
		and absf(e.training("barracks").finish - (t0 + 8 * 10800.0)) < 2.0 and not e.training("barracks").ready and changes[0] == 1,
		"start: 8 infantry take food 240 / wood 160 at once, finish = now + 8 x 3 h, training_changed")
	check(e.train_block("barracks", 1) == "training" and not e.start_training("barracks", 1) and notes[-1] == EconomyScript.TRAIN_TEXT.training
		and not e.collect_training("barracks") and e.soldiers.is_empty(), "one batch per building: a second start is 'training'; nothing to collect yet")
	check(e.train_time("barracks", 8) == 8 * 10800.0 and e.train_max("barracks") == 10 and e.train_progress("barracks") < 0.01, "train_time = n x unit, train_max by level, progress starts at 0")
	e.levels.barracks = 5  # 레벨이 올라도 진행 중 묶음의 끝나는 시각은 그대로, 다음 묶음부터 빨라진다
	check(absf(e.training("barracks").finish - (t0 + 8 * 10800.0)) < 2.0 and e.train_max("barracks") == 18 and e.train_time("barracks", 1) == GameData.soldier_unit_sec(5),
		"a level-up keeps the running batch's finish; the next batch uses the new unit time and cap")
	e.finish_training_now("barracks")  # 테스트 훅: 끝나는 시각을 지금으로
	check(e.training("barracks").ready and e.train_block("barracks", 1) == "ready_to_collect" and e.soldiers.is_empty(), "done: ready to collect, no soldiers until collected, a new start is 'ready_to_collect'")
	check(e.collect_training("barracks") and e.soldiers == {"infantry:1": 8} and e.train_queues.is_empty() and notes[-1] == "보병 +8" and not e.collect_training("barracks"),
		"collect: tier-1 +8, the queue empties, notice '보병 +8'; collecting again does nothing")
	check(e.start_training("archery", 3) and e.res == {"wood": 750, "stone": 1000, "food": 685} and e.cancel_training("archery")
		and e.res == {"wood": 795, "stone": 1000, "food": 722} and e.train_queues.is_empty() and notes[-1] == EconomyScript.CANCEL_TEXT,
		"cancel: 3 archers (food 75 / wood 90) refund half rounded down (37 / 45) and empty the queue")
	check(e.start_training("stable", 1) and not e.cancel_training("lab") and not e.cancel_training("barracks"), "cancel needs a running batch")
	e.finish_training_now("stable")
	check(not e.cancel_training("stable") and e.training("stable").ready, "a finished batch cannot be cancelled (collect it)")
	# 자동 생산 없음: 오래 지나도(100시간, 시계 되돌림 없이) 보유는 그대로 — 끝난 묶음도 수령해야 들어온다
	var kept: Dictionary = e.soldiers.duplicate()
	e.train_queues.stable.finish = t0 - 100 * 3600.0
	e._process(0.1)  # 매 프레임 일(게으른 완료·저장)이 돌아도
	check(e.soldiers == kept and e.training("stable").count == 1 and not e.has_method("produce_due"), "no automatic production: time passing (and the frame tick) adds no soldiers")
	check(e.collect_training("stable") and e.soldiers == {"infantry:1": 8, "cavalry:1": 1}, "the finished cavalry comes in only when collected")
	# 저장 v7: 대기열 왕복, v6 → v7은 생산 시계를 버리고 대기열을 비운다(시간이 흘러도 병사가 생기지 않는다), 깨진 training은 깨진 저장
	e.start_training("archery", 2)
	e.save_path = ECON_TMP
	e.save()
	var e7 = _econ(0.0)
	e7.save_path = ECON_TMP
	e7.load_save(now)
	var raw7 = JSON.parse_string(FileAccess.get_file_as_string(ECON_TMP))
	check(int(raw7.version) == 8 and EconomyScript.SAVE_VERSION == 8 and e7.train_queues.archery.tier == 1 and e7.train_queues.keys() == ["archery"] and e7.train_queues.archery.count == 2
		and absf(e7.train_queues.archery.finish - e.train_queues.archery.finish) < 0.01 and e7.soldiers == e.soldiers and not raw7.last_collect.has("archery"),
		"save v8 round-trips the training queue and keeps no production clocks: %s" % [e7.train_queues])
	var v6 := {"version": 6, "gold_tenths": 5, "res": {"wood": 0, "stone": 0, "food": 0}, "last_collect": {"lumber": now, "quarry": now, "farm": now, "barracks": now - 100 * 3600.0, "stable": 1.0},
		"levels": {"lumber": 1, "quarry": 1, "farm": 1}, "build": null, "heroes": {"hans": {"copies": 1, "level": 1, "shards": 0, "promotion": 0}}, "deploy": ["hans"], "soldiers": {"infantry:1": 2}, "soldier_deploy": {}}
	_write(ECON_TMP, JSON.stringify(v6))
	e7.load_save(now)
	check(e7.gold_tenths == 5 and e7.soldiers == {"infantry:1": 2} and e7.train_queues.is_empty() and not e7.last_collect.has("barracks") and not e7.last_collect.has("stable"),
		"save v6 -> v7: the old production clocks are dropped, the queue is empty and 100 h of clock make no soldiers")
	for junk in [{"training": [1]}, {"training": {"barracks": 3}}, {"training": {"barracks": {"count": "x", "finish": 1.0}}}]:
		var bad7: Dictionary = v6.duplicate(true)
		bad7.version = 7
		bad7.merge(junk, true)
		_write(ECON_TMP, JSON.stringify(bad7))
		e7.load_save(now)
		check(e7.gold_tenths == 0 and e7.train_queues.is_empty(), "malformed v7 training (%s) is a corrupt save" % [junk])
	var odd: Dictionary = v6.duplicate(true)
	odd.version = 7
	odd.training = {"lab": {"count": 3, "finish": 1.0}, "barracks": {"count": 0, "finish": 1.0}, "stable": {"count": 2, "finish": 5.0}}
	_write(ECON_TMP, JSON.stringify(odd))
	e7.load_save(now)
	check(e7.train_queues == {"stable": {"count": 2, "tier": 1, "finish": 5.0}}, "v7 load (no tier = 1) keeps only soldier buildings with a batch: %s" % [e7.train_queues])
	DirAccess.remove_absolute(ECON_TMP)
	e7.free()
	e.save_path = ""
	# 합성
	e.soldiers = {"infantry:1": 12, "infantry:5": 5}
	e.soldier_deployed = {"infantry:1": 6}
	check(e.can_merge("infantry", 1) and e.merge_block("infantry", 5) == "max_tier" and e.merge_block("knight", 1) == "unknown" and e.merge_block("archer", 1) == "not_enough" and not e.can_merge("archer", 1),
		"merge_block: unknown / max tier / not enough")
	check(e.merge_soldiers("infantry", 1) and e.merge_soldiers("infantry", 1) and e.soldiers == {"infantry:1": 2, "infantry:2": 2, "infantry:5": 5} and e.soldier_deployed == {"infantry:1": 2},
		"merge: 5 of a tier -> 1 of the next, the deploy is trimmed to what is owned: %s %s" % [e.soldiers, e.soldier_deployed])
	check(not e.merge_soldiers("infantry", 1) and notes[-1] == EconomyScript.SOLDIER_TEXT.not_enough and not e.merge_soldiers("infantry", 5) and notes[-1] == EconomyScript.SOLDIER_TEXT.max_tier
		and e.soldiers == {"infantry:1": 2, "infantry:2": 2, "infantry:5": 5}, "a refused merge only shows the reason")
	# 배치
	e.soldiers = {"infantry:1": 10, "archer:2": 3}
	e.soldier_deployed = {}
	check(e.soldier_deploy_block({"infantry:1": 7}) == "over_population" and e.soldier_deploy_block({"archer:2": 4}) == "not_owned" and e.soldier_deploy_block({"knight:1": 1}) == "bad_key"
		and e.soldier_deploy_block({"infantry:1": -1}) == "bad_key" and e.soldier_deploy_block({"infantry:1": 1.5}) == "bad_key" and e.soldier_deploy_block({"infantry:1": "2"}) == "bad_key"
		and e.soldier_deploy_block({"infantry:1": 3, "archer:2": 3}) == "", "deploy checks: keys, owned counts, population")
	check(e.set_soldier_deploy({"infantry:1": 3, "archer:2": 3, "cavalry:1": 0}) and e.soldier_deploy() == {"infantry:1": 3, "archer:2": 3} and e.deployed_total() == 6
		and not e.set_soldier_deploy({"infantry:1": 7}) and notes[-1] == EconomyScript.SOLDIER_TEXT.over_population and e.soldier_deploy() == {"infantry:1": 3, "archer:2": 3},
		"set_soldier_deploy stores a valid deploy (zeros dropped) and refuses one above the population")
	e.levels.houses = 3  # 인구 10
	check(e.auto_deploy() == {"archer:2": 3, "infantry:1": 7}, "auto_deploy: highest tier first up to the population (10): %s" % [e.auto_deploy()])
	# 저장 v5 왕복, v4 → v5, 깨진 v5
	e.save_path = ECON_TMP
	e.save()
	var e2 = _econ(0.0)
	e2.save_path = ECON_TMP
	e2.load_save(now + 360001.0)
	check(int(JSON.parse_string(FileAccess.get_file_as_string(ECON_TMP)).version) == EconomyScript.SAVE_VERSION and e2.soldiers == e.soldiers and e2.soldier_deployed == e.soldier_deployed
		and e2.levels.barracks == 5, "save round-trips soldiers, deploy and levels")
	var v4 := {"version": 4, "gold_tenths": 5, "res": {"wood": 0, "stone": 0, "food": 0}, "last_collect": {"lumber": now, "quarry": now, "farm": now},
		"levels": {"lumber": 1, "quarry": 1, "farm": 1}, "build": null, "heroes": {"hans": {"copies": 1, "level": 1}}, "deploy": ["hans"]}
	_write(ECON_TMP, JSON.stringify(v4))
	e2.load_save(now + 50.0)
	check(e2.gold_tenths == 5 and e2.soldiers.is_empty() and e2.soldier_deployed.is_empty() and e2.train_queues.is_empty() and not e2.last_collect.has("barracks"),
		"save v4 -> current: no soldiers, empty training queues")
	var v5 := v4.duplicate(true)
	v5.version = 5
	v5.soldiers = {"knight:1": 3, "infantry:1": 2}
	v5.soldier_deploy = {"infantry:1": 5}
	_write(ECON_TMP, JSON.stringify(v5))
	e2.load_save(now + 50.0)
	check(e2.gold_tenths == 5 and e2.soldiers == {"infantry:1": 2} and e2.soldier_deployed == {"infantry:1": 2}, "v5 load drops unknown soldier keys and trims the deploy")
	for junk in [{"soldiers": [1]}, {"soldiers": {"infantry:1": "x"}}, {"soldier_deploy": 3}]:
		var bad: Dictionary = v5.duplicate(true)
		bad.merge(junk, true)
		_write(ECON_TMP, JSON.stringify(bad))
		e2.load_save(now)
		check(e2.gold_tenths == 0 and e2.soldiers.is_empty(), "malformed v5 soldiers (%s) is a corrupt save" % [junk])
	DirAccess.remove_absolute(ECON_TMP)
	e.free()
	e2.free()
	# 온라인 응답
	var o = _econ(1000.0)
	var oc := [0]
	o.training_changed.connect(func(): oc[0] += 1)
	var reply := {"player": {"gold_tenths": 0, "stage": 1, "res": {}, "buildings": {"barracks": {"level": 2}},
		"soldiers": {"infantry:1": 3, "knight:1": 2, "archer:2": 0}, "soldier_deploy": {"infantry:1": 2}, "population": 6,
		"training": {"barracks": {"count": 4, "finish": 5000.0}, "archery": null, "stable": {"count": 0, "finish": 1.0}, "lab": {"count": 2, "finish": 1.0}}},
		"merchant": {"rates": {"wood": 1.0, "stone": 1.0, "food": 1.0}, "next_change": 3600.0}}
	check(o.apply_server(reply) and o.soldiers == {"infantry:1": 3} and o.soldier_deployed == {"infantry:1": 2} and o.building_level("barracks") == 2
		and o.train_queues == {"barracks": {"count": 4, "tier": 1, "finish": 5000.0}} and oc[0] == 1,
		"reply: soldiers (known keys only), deploy, training queues of soldier buildings only, training_changed: %s" % [o.train_queues])
	check(o.apply_server(reply) and oc[0] == 1, "the same reply again does not signal training_changed")
	reply.player.training = {"barracks": null}
	check(o.apply_server(reply) and o.train_queues.is_empty() and oc[0] == 2, "an emptied queue in the reply clears it")
	var logged := _errors.count
	reply.player.soldiers = "x"
	check(not o.apply_server(reply) and o.soldiers == {"infantry:1": 3}, "apply_server rejects malformed soldiers")
	reply.player.soldiers = {}
	reply.player.training = [1]
	check(not o.apply_server(reply) and o.soldiers == {"infantry:1": 3}, "apply_server rejects malformed training")
	_errors.count = logged
	o.free()
	# apply_remote: 병종 표·설정 검증 — 틀리면 아무것도 안 바꾼다
	var before := _tables_hash()
	for entry in [["building unknown", 1], ["building shared", 1], ["hp 0", 1], ["atk negative", 1], ["not drawable", 2], ["table missing", 1], ["max tier 0", 1], ["train step 0", 1],
			["train cost bad", 1], ["train cost missing", 1], ["batch base 0", 1], ["batch per level fraction", 1]]:
		var q := _payload()
		match entry[0]:
			"building unknown": q.soldiers[1].building = "mine"
			"building shared": q.soldiers[2].building = "barracks"
			"hp 0": q.soldiers[0].hp = 0
			"atk negative": q.soldiers[1].atk = -1
			"not drawable": q.soldiers[0].id = "dragon"  # 개정 16: train_cost_dragon도 없다(오류 2)
			"table missing": q.erase("soldiers")
			"max tier 0": q.config.soldier_max_tier = "0"
			"train step 0": q.config.train_step_min = "0"
			"train cost bad": q.config.train_cost_archer = "food:25|gold:30"
			"train cost missing": q.config.erase("train_cost_cavalry")
			"batch base 0": q.config.train_batch_base = "0"
			"batch per level fraction": q.config.train_batch_per_level = "1.5"
		check(not GameData.apply_remote(q) and GameData.errors == entry[1] and _tables_hash() == before, "apply_remote rejects soldiers: %s (errors %d)" % [entry[0], GameData.errors])
	_errors.count = logged
	GameData.load_tables()
	check(GameData.errors == 0 and GameData.soldiers().size() == 3, "default tables restored")
	# 성채 앞 자리 격자: 11 × 6 = 66칸, 겹침 없음, 범위 안, 상인·수레·건물 부지 밖. 67번째는 자리 없음
	var units := []
	for i in 66:
		units.append({"type": ["infantry", "archer", "cavalry"][i % 3], "tier": 1 + i % 5})
	var spots: Array = FormationScript.soldier_spots(units)
	var seen := {}
	var inside := true
	for p in spots:
		if p == null:
			inside = false
			continue
		seen[str(p)] = true
		inside = inside and p.x >= Balance.SOLDIER_X.x - 0.001 and p.x <= Balance.SOLDIER_X.y + 0.001 and p.z >= Balance.SOLDIER_Z.x - 0.001 and p.z <= Balance.SOLDIER_Z.y + 0.001 and p.y == 0.0
	check(FormationScript.soldier_grid() == Vector2i(11, 6) and seen.size() == 66 and inside, "66 soldiers get 66 distinct spots inside the square in front of the keep")
	check(FormationScript.soldier_spots(units + [{"type": "infantry", "tier": 1}]).count(null) == 1, "67 soldiers: one of them gets no spot")
	var cart_box := TownKitScript.merchant_cart().get_aabb()
	var cart_c: Vector3 = Balance.MERCHANT_POS + Balance.MERCHANT_CART_OFFSET
	var keep_out := [  # 상인·수레·건물 부지(병사 발밑 원판 반지름만큼 넓혀서)
		Rect2(Balance.MERCHANT_POS.x - Balance.MERCHANT_RADIUS, Balance.MERCHANT_POS.z - Balance.MERCHANT_RADIUS, 2.0 * Balance.MERCHANT_RADIUS, 2.0 * Balance.MERCHANT_RADIUS),
		Rect2(cart_c.x + cart_box.position.x, cart_c.z + cart_box.position.z, cart_box.size.x, cart_box.size.z),
	]
	for b in Balance.BUILDINGS:
		keep_out.append(Rect2(Vector2(b.cell) * Balance.TILE, Vector2(b.size) * Balance.TILE))
	var hits := []
	for p in spots:
		for r in keep_out:
			if (r as Rect2).grow(0.45).has_point(Vector2(p.x, p.z)):
				hits.append([p, r])
	check(hits.is_empty(), "soldier spots stay clear of the merchant, the cart and every building plot: %s" % [hits.slice(0, 2)])
	var few: Array = FormationScript.soldier_spots([{"type": "infantry", "tier": 1}, {"type": "infantry", "tier": 2}, {"type": "infantry", "tier": 2},
		{"type": "archer", "tier": 1}, {"type": "archer", "tier": 1}, {"type": "cavalry", "tier": 3}, {"type": "cavalry", "tier": 1}])
	var want := [Vector3(3.9, 0, 9.1), Vector3(3.0, 0, 9.1), Vector3(2.1, 0, 9.1), Vector3(3.0, 0, 4.6), Vector3(2.1, 0, 4.6), Vector3(-1.5, 0, 9.1), Vector3(7.5, 0, 9.1)]
	var rows_ok := true
	for i in want.size():
		rows_ok = rows_ok and few[i] is Vector3 and (few[i] as Vector3).is_equal_approx(want[i])
	check(rows_ok, "ranks: infantry front row (gate side) highest tier in the middle, archers back row, cavalry at both ends: %s" % [few])
	var cav: Array = FormationScript.soldier_spots(range(6).map(func(i): return {"type": "cavalry", "tier": 1}))
	var cav_zs := cav.filter(func(p): return is_equal_approx(p.x, Balance.SOLDIER_X.x)).map(func(p): return snappedf(p.z, 0.01))
	check(cav_zs == [9.1, 7.3, 5.5] and cav.all(func(p): return is_equal_approx(absf(p.x - 3.0), 4.5)), "six cavalry: both end columns, every other row (horses do not overlap): %s" % [cav])
	var horse := TownKitScript.horse()
	var hb := horse.get_aabb()
	check(horse.get_surface_count() == 1 and absf(hb.position.y) < 0.01 and hb.end.y > TownKitScript.HORSE_BACK and hb.end.y < 2.0 and hb.size.z > hb.size.x * 2.0,
		"horse: one low-poly surface on the ground, head above its back (%.2f m), longer than wide: %s" % [TownKitScript.HORSE_BACK, hb])


## 개정 14 §4 수량 판매(오프라인): amount만큼만 팔고 floor(amount × 단가 × 그 자원 배율) 골드, 보유 초과는 보유로 자른다.
func test_economy_sell_amount() -> void:
	var now := 3600.0 * 480000.0
	var e = _econ(now)
	var rate: float = e.current_rate("wood", now)
	e.res.wood = 40
	var g: int = e.sell("wood", now, 15)
	check(g == EconomyScript.sell_value("wood", 15, rate) and e.res.wood == 25 and e.gold_tenths == g * 10, "sell(amount) sells only that many")
	check(e.sell("wood", now, 0) == 0 and e.res.wood == 25, "sell(amount 0) sells nothing")
	var g2: int = e.sell("wood", now, 999)
	check(e.res.wood == 0 and g2 == EconomyScript.sell_value("wood", 25, rate), "sell(amount above holdings) clamps to holdings")
	e.res.wood = 9
	check(e.sell("wood", now) == EconomyScript.sell_value("wood", 9, rate) and e.res.wood == 0, "sell without amount still sells all")


## 개정 14 §3 FEVER 상태: 게이지(방치 처치만, 200에서 가득, FEVER 중 안 참), 시작 조건, 스폰 배율, 저장.
func test_fever() -> void:
	GameData.load_tables()
	var f = preload("res://scripts/fever.gd").new()
	f.save_path = ""
	check(f.kills_needed() == 200 and GameData.config_num("fever_sec") == 180.0 and GameData.config_num("fever_spawn_mult") == 3.0, "fever config keys")
	for i in 50:
		f.add_kill(false)  # 스테이지 모드 처치는 세지 않는다
	check(f.gauge == 0, "stage-mode kills do not charge the gauge")
	for i in 199:
		f.add_kill(true)
	check(f.gauge == 199 and not f.full() and not f.start() and f.mult() == 1.0, "199 idle kills: not full, cannot start, spawn mult 1")
	f.add_kill(true)
	f.add_kill(true)
	check(f.gauge == 200 and f.full() and f.ratio() == 1.0, "200 idle kills fill the gauge (and stay at 200)")
	check(f.start() and f.active() and f.gauge == 0 and f.left == 180.0 and f.mult() == 3.0, "start: 180 s, gauge back to 0, spawn mult 3")
	f.add_kill(true)
	check(f.gauge == 0 and not f.start(), "the gauge does not charge during FEVER")
	f.advance(179.0)
	check(f.active() and f.mult() == 3.0, "still FEVER at 179 s")
	f.advance(2.0)
	check(not f.active() and f.left == 0.0 and f.mult() == 1.0, "FEVER ends after 180 s")
	f.add_kill(true)
	check(f.gauge == 1, "the gauge charges again from 0 after FEVER")
	# 저장·불러오기(임시 파일)
	var p := "user://fever_test.json"
	f.save_path = p
	f.gauge = 73
	f.left = 42.5
	f.save()
	var g = preload("res://scripts/fever.gd").new()
	g.save_path = p
	g.load_save()
	check(g.gauge == 73 and g.left == 42.5, "save/load round trip")
	var w := FileAccess.open(p, FileAccess.WRITE)
	w.store_string("{broken")
	w.close()
	g.load_save()
	check(g.gauge == 0 and g.left == 0.0, "a corrupt file starts from zero")
	DirAccess.remove_absolute(p)
	f.free()
	g.free()


## 개정 14 §2 영웅 피규어: 캐시 API(헤드리스라 렌더 없음 — 자리표시·큐·저장·알림·미리보기 상태만), 카드의 피규어 자리와 받침.
func test_portraits() -> void:
	var P = PortraitsScript
	check(P.current == null, "no Portraits node outside a world")
	var ph: Texture2D = P.portrait("hero:arteon")
	check(ph != null and ph.get_width() == P.PLACEHOLDER_PX and P.portrait("hero:arteon") == ph and P.portrait("hero:ignis") == ph,
		"before a render the placeholder comes back at once, one per grade color (two SSR heroes share it)")
	check(P.portrait("hero:hans") != ph and P.portrait("soldier:cavalry") != ph and P.portrait("soldier:cavalry") == P.portrait("soldier:archer"),
		"an R hero and the soldier keys get their own silhouette colors")
	var sil: Image = P.silhouette(Color.RED)
	var fy := int(P.feet_y() * P.PLACEHOLDER_PX)
	check(sil.get_pixel(32, fy - 2).a > 0.5 and sil.get_pixel(32, fy + 2).a == 0.0 and sil.get_pixel(2, 2).a == 0.0 and P.feet_y() > 0.75 and P.feet_y() < 0.95,
		"the silhouette stands on the figure's feet line (y %.2f), background transparent" % P.feet_y())
	check(P.spec_of("hero:arteon") == Art.hero_spec(GameData.hero("arteon")) and P.spec_of("soldier:cavalry") == Art.soldier_spec("cavalry", "Knight")
		and P.spec_of("soldier:dragon").is_empty() and P.spec_of("hero:nobody").is_empty(),
		"spec_of: hero and soldier keys use the in-game model spec (gear shown); unknown keys have none")
	var p = P.new()
	P.current = p  # 월드 안이라면 _enter_tree가 한다
	check(not p.can_render, "headless: no renderer")
	P.portrait("hero:hans")
	check(p.queue.is_empty(), "headless: requests are skipped, placeholder only")
	p.can_render = true  # 렌더러가 있는 척 — 큐만 본다(_show는 트리 밖에서 못 쓴다)
	for key in ["hero:hans", "hero:hans", "hero:jack", "soldier:cavalry", "hero:nobody", "soldier:dragon"]:
		P.portrait(key)
	check(p.queue == ["hero:hans", "hero:jack", "soldier:cavalry"], "requests queue once per key in order; keys without a model are not queued: %s" % [p.queue])
	p.live_key = "hero:arteon"
	p._process(0.016)
	check(p.queue == ["hero:hans", "hero:jack", "soldier:cavalry"] and p._pending == "", "the queue waits while the live preview uses the viewport")
	p.live_key = ""
	var got := []
	p.portrait_ready.connect(func(k): got.append(k))
	var tex := ImageTexture.create_from_image(P.silhouette(Color.BLUE))
	p.store("hero:hans", tex)
	P.portrait("hero:hans")
	check(got == ["hero:hans"] and p.queue == ["hero:jack", "soldier:cavalry"] and P.portrait("hero:hans") == tex and P.has_portrait("hero:hans"),
		"a finished render is cached, leaves the queue, fires portrait_ready(key) and is not queued again")
	p.can_render = false
	p.set_live("hero:arteon")
	p.turn(50.0)
	check(p.live_key == "hero:arteon" and is_equal_approx(p.yaw, 30.0) and is_equal_approx(p._pivot.rotation_degrees.y, 30.0) and p.live_texture("hero:arteon") == ph,
		"live preview: a 50 px drag turns the model 30 degrees; headless draws the placeholder instead of the viewport")
	p.set_live("hero:hans")
	check(p.yaw == 0.0 and p._pivot.rotation_degrees.y == 0.0 and p._vp.size == Vector2i(P.LIVE_SIZE, P.LIVE_SIZE), "the next live hero starts facing front; live renders at LIVE_SIZE")
	p.set_live("")
	check(p.live_key == "" and p._vp.size == Vector2i(P.SIZE, P.SIZE), "live preview off; snapshots back at SIZE")
	P.current = null
	p.free()
	check(P.portrait("hero:hans") == tex, "the cache is static: it outlives the node (world rebuild)")
	P._cache.erase("hero:hans")
	# 카드: 피규어 칸은 등급 보석 아래·이름 위(목록·슬롯·상세·모집 크기), 고유 색은 발밑 받침
	for s in [Vector2(200, 240), Vector2(140, 150), Vector2(190, 240), Vector2(118, 160)]:
		var c = HeroCardScript.new()
		c.size = s
		var fr: Rect2 = c.figure_rect()
		var name_top: float = s.y * 0.6 - c._name_size() * 0.7
		check(fr.size.x > 50.0 and fr.position.y >= UiKit.card_gem_center(Rect2(Vector2.ZERO, s)).y + 8.0 and fr.end.y < name_top and Rect2(Vector2.ZERO, s).encloses(fr),
			"card %s: figure %s sits between the grade gem and the name" % [s, fr])
		c.free()
	var card = HeroCardScript.new()
	card.size = Vector2(200, 240)
	card.hero_id = "dorik"
	var dorik := GameData.hero("dorik")
	card._ensure_geo(dorik)
	var fr: Rect2 = card.figure_rect()
	var feet := Vector2(fr.get_center().x, fr.position.y + fr.size.y * P.feet_y())
	check(card._base.size() == 2 * HeroCardScript.BASE_SIDES * 3 and card._base_cols.size() == card._base.size() and card._base_lines.size() == 2
		and card._base_cols.has(Color(dorik.color).darkened(0.35)) and card._base[HeroCardScript.BASE_SIDES * 3].is_equal_approx(feet),
		"the unique color is a two-tone pedestal centered under the figure's feet")
	check(card.figure_texture() == P.portrait("hero:dorik") and card.figure_texture() == P.placeholder("hero:dorik"), "the card draws the placeholder until the figure is rendered")
	card.free()


## 개정 15: 성채 단계 표 둘은 함께 움직인다(사용자 규칙: 성이 넓어질 때마다 영웅 슬롯 +4, 최대 12). CSV(load_tables)와 원격 표(apply_remote)
## 모두 슬롯 표 레벨 = 내부 표 레벨, 슬롯 값 = 4 × 단계(4, 8, 12), 내부 값은 단계마다 커져야 한다. 서버 seed.checkKeepTiers와 같은 규칙.
func test_keep_tier_lockstep() -> void:
	GameData.load_tables()
	var logged := _errors.count
	var bad := [  # [이름, 슬롯 표, 내부 표]
		["slot levels differ", "1:4|6:8|10:12", "1:20|5:24|10:28"],
		["interior has fewer tiers", "1:4|5:8|10:12", "1:20|5:24"],
		["slot value not 4 x tier", "1:4|5:9|10:12", "1:20|5:24|10:28"],
		["slots above 12", "1:4|5:8|10:12|15:16", "1:20|5:24|10:28|15:32"],
		["first tier not 4 slots", "1:6|5:8|10:12", "1:20|5:24|10:28"],
		["interior does not grow", "1:4|5:8|10:12", "1:20|5:24|10:24"],
	]
	var csv := FileAccess.get_file_as_string(GameData.CONFIG_PATH)
	var cp := "user://t_tiers.csv"
	for entry in bad:
		_write(cp, csv.replace("keep_slot_tiers,1:4|5:8|10:12", "keep_slot_tiers," + entry[1]).replace("keep_interior_tiers,1:20|5:24|10:28", "keep_interior_tiers," + entry[2]))
		GameData.load_tables(GameData.MONSTERS_PATH, GameData.STAGES_PATH, GameData.HEROES_PATH, GameData.RESOURCES_PATH, cp)
		check(GameData.errors == 1, "config.csv keep tiers rejected: %s (errors %d)" % [entry[0], GameData.errors])
	DirAccess.remove_absolute(cp)
	GameData.load_tables()
	var before := _tables_hash()
	for entry in bad:
		var q := _payload()
		q.config.keep_slot_tiers = entry[1]
		q.config.keep_interior_tiers = entry[2]
		check(not GameData.apply_remote(q) and GameData.errors == 1 and _tables_hash() == before, "apply_remote keep tiers rejected: %s (errors %d)" % [entry[0], GameData.errors])
	var ok := _payload()
	ok.config.keep_slot_tiers = "1:4|4:8|8:12"  # 같은 레벨로 함께 옮기면 통과
	ok.config.keep_interior_tiers = "1:20|4:22|8:26"
	check(GameData.apply_remote(ok) and [1, 4, 8].map(func(l): return GameData.hero_slots(l)) == [4, 8, 12] and GameData.interior_tiles(4) == 22,
		"keep tiers moved together in lockstep are accepted")
	ok.config.keep_slot_tiers = "1:4|5:8"  # 단계 둘(최대 8)도 규칙 안
	ok.config.keep_interior_tiers = "1:20|5:24"
	check(GameData.apply_remote(ok) and GameData.hero_slots(30) == 8, "two keep tiers (up to 8 slots) are within the rule")
	_errors.count = logged
	GameData.load_tables()
	check(GameData.errors == 0 and GameData.hero_slots(10) == 12, "default tables restored after the keep tier test")


## 개정 15: 병종 몸(SoldierBody — 월드 병사와 병사 피규어가 같이 쓴다)과 병사 크기 0.9. 트리 밖이라 모델 안(GLB)은 만들지 않고 조립만 본다.
## 크기를 키워도 대열 격자(11 × 6, 0.9 m)는 그대로이고, 병사·말 발자리가 건물 메시·상인·수레에 닿지 않는다.
func test_soldier_figures() -> void:
	const SoldierBody := preload("res://scripts/soldier_body.gd")
	check(Art.SOLDIER_SCALE == 0.9 and is_equal_approx(SoldierBody.RIDER_Y, (TownKitScript.HORSE_BACK - SoldierBody.RIDER_HIP) * 0.9),
		"soldiers are drawn at 0.9 and the knight sits on the horse's back (rider y %.2f)" % SoldierBody.RIDER_Y)
	var bodies := {}
	for type in ["infantry", "archer", "cavalry", "cavalry"]:
		var root := Node3D.new()
		var b: Array = SoldierBody.build(root, type)
		bodies[type] = b
		var m = b[0]
		var ok: bool = root.get_child_count() == (2 if type == "cavalry" else 1) and root.get_child(0) == m and is_equal_approx(m.scale.x, Art.SOLDIER_SCALE * Art.CHARACTER_SCALE)
		ok = ok and m._spec == Art.soldier_spec(type, GameData.soldier(type).model) and not m.manual
		if type == "cavalry":
			ok = ok and b[1] is MeshInstance3D and is_equal_approx(b[1].scale.x, Art.SOLDIER_SCALE) and is_equal_approx(m.position.y, SoldierBody.RIDER_Y)
		else:
			ok = ok and b[1] == null and m.position.y == 0.0
		check(ok, "SoldierBody.build(%s): the soldier model (gear %s)%s" % [type, Art.SOLDIERS[type].gear, " on a horse" if type == "cavalry" else ""])
		root.free()
	var inf: Dictionary = Art.soldier_spec("infantry", "Knight")
	var arc: Dictionary = Art.soldier_spec("archer", "Rogue_Hooded")
	check(GameData.soldier("infantry").model == "Knight" and not inf.hide.has("1H_Sword") and not inf.hide.has("Rectangle_Shield") and inf.hide.has("2H_Sword")
		and GameData.soldier("archer").model == "Rogue_Hooded" and not arc.hide.has("2H_Crossbow") and arc.hide.has("Knife"),
		"infantry = Knight with sword and shield; archer = Rogue_Hooded with the crossbow")
	# 0.9 크기 발자리: 보병·궁병 0.8 m 정사각, 기병은 말(+Z를 본다) — 건물 메시·상인·수레와 겹치지 않는다
	var units := []
	for i in 66:
		units.append({"type": ["infantry", "archer", "cavalry"][i % 3], "tier": 1})
	var spots: Array = FormationScript.soldier_spots(units)
	var hb: AABB = TownKitScript.horse().get_aabb()
	var s := Art.SOLDIER_SCALE
	var blocks := []
	for b in Balance.BUILDINGS:
		var c := Vector3((b.cell.x + b.size.x / 2.0) * Balance.TILE, 0, (b.cell.y + b.size.y / 2.0) * Balance.TILE)
		var box: AABB = TownKitScript.building(b.id).get_aabb()
		blocks.append([b.id, Rect2(c.x + box.position.x, c.z + box.position.z, box.size.x, box.size.z)])
	var cart: AABB = TownKitScript.merchant_cart().get_aabb()
	var cc: Vector3 = Balance.MERCHANT_POS + Balance.MERCHANT_CART_OFFSET
	blocks.append(["cart", Rect2(cc.x + cart.position.x, cc.z + cart.position.z, cart.size.x, cart.size.z)])
	blocks.append(["merchant", Rect2(Balance.MERCHANT_POS.x - Balance.MERCHANT_RADIUS, Balance.MERCHANT_POS.z - Balance.MERCHANT_RADIUS, 2.0 * Balance.MERCHANT_RADIUS, 2.0 * Balance.MERCHANT_RADIUS)])
	var hits := []
	for i in spots.size():
		var p: Vector3 = spots[i]
		var foot := Rect2(p.x + hb.position.x * s, p.z + hb.position.z * s, hb.size.x * s, hb.size.z * s) if units[i].type == "cavalry" else Rect2(p.x - 0.4, p.z - 0.4, 0.8, 0.8)
		for blk in blocks:
			if foot.intersects(blk[1]):
				hits.append([units[i].type, p, blk[0]])
	check(FormationScript.soldier_grid() == Vector2i(11, 6) and hits.is_empty(), "at 0.9 the 66-soldier formation (horses %.2f m long) still clears every building mesh, the merchant and the cart: %s" % [hb.size.z * s, hits.slice(0, 3)])


## 여러 자원 한 번에 판매(오프라인): 자원마다 자기 시세, 보유 초과는 보유로 자름, 0은 무시.
func test_economy_sell_many() -> void:
	var now := 3600.0 * 480000.0
	var e = _econ(now)
	e.res.wood = 40
	e.res.stone = 9
	e.res.food = 13
	var want: int = EconomyScript.sell_value("wood", 15, e.current_rate("wood", now)) + EconomyScript.sell_value("stone", 9, e.current_rate("stone", now))
	var g: int = e.sell_many([{"res": "wood", "amount": 15}, {"res": "stone", "amount": 99}, {"res": "food", "amount": 0}], now)
	check(g == want and e.res.wood == 25 and e.res.stone == 0 and e.res.food == 13 and e.gold_tenths == want * 10, "sell_many sells each at its own rate, clamps to holdings, skips 0")
	check(e.sell_many([], now) == 0 and e.sell_many([{"res": "stone", "amount": 5}], now) == 0 and e.gold_tenths == want * 10, "sell_many with nothing to sell changes nothing")
	e.free()


## 개정 19: 막사 레벨이 훈련 티어·시간을 정하고 비용은 티어마다 ×5, 진행 중 묶음은 시작 티어·시각 고정.
func test_training_tiers() -> void:
	var want := [[1, 1, 180], [2, 1, 150], [6, 1, 30], [7, 2, 180], [12, 2, 30], [13, 3, 180], [19, 4, 180], [25, 5, 180], [30, 5, 30], [31, 5, 30]]
	var table_ok := true
	for w in want:
		table_ok = table_ok and GameData.train_tier(w[0]) == w[1] and GameData.soldier_unit_sec(w[0]) == w[2] * 60.0
	check(table_ok, "tier/time table: Lv 1,2,6,7,12,13,19,25,30,31 -> T1 3:00, T1 2:30, T1 0:30, T2 3:00, T2 0:30, T3 3:00, T4, T5 3:00, T5 0:30, T5 0:30")
	check(EconomyScript.train_cost("infantry", 2) == {"food": 60, "wood": 40} and EconomyScript.train_cost("infantry", 2, 2) == {"food": 300, "wood": 200}
		and EconomyScript.train_cost("infantry", 1, 3) == {"food": 750, "wood": 500}, "cost x 5^(tier-1): T2 x5, T3 x25")
	var now := 1.8e9
	var e = _econ(now)
	e.res = {"wood": 100000, "stone": 100000, "food": 100000}
	e.levels.barracks = 7
	var t0: float = e.time_now()
	check(e.train_tier("barracks") == 2 and e.start_training("barracks", 2) and e.res.food == 100000 - 300 and e.res.wood == 100000 - 200
		and e.training("barracks").tier == 2 and absf(e.training("barracks").finish - (t0 + 2 * 10800.0)) < 2.0, "Lv 7 barracks trains T2: 3:00 each, cost x5")
	var fin: float = e.training("barracks").finish
	e.levels.barracks = 13  # 진행 중 레벨업: 묶음은 T2·끝나는 시각 그대로
	check(e.training("barracks").tier == 2 and e.training("barracks").finish == fin and e.train_tier("barracks") == 3, "a level-up keeps the running batch's tier and finish")
	e.finish_training_now("barracks")
	check(e.collect_training("barracks") and e.soldiers == {"infantry:2": 2}, "collect adds the batch's tier (infantry:2), not the current one")
	e.levels.barracks = 7
	e.start_training("barracks", 2)
	e.levels.barracks = 13
	var before: Dictionary = e.res.duplicate()
	check(e.cancel_training("barracks") and e.res.food == before.food + 150 and e.res.wood == before.wood + 100, "cancel refunds half of the batch tier's cost")
	e.free()

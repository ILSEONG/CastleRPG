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
const HeroSkillsScript := preload("res://scripts/hero_skills.gd")
const SkillIconsScript := preload("res://scripts/skill_icons.gd")
const LowpolyBoxScript := preload("res://scripts/lowpoly_box.gd")
const UiKit := preload("res://scripts/ui_kit.gd")
const HpBarsScript := preload("res://scripts/hp_bars.gd")
const HeroCardScript := preload("res://scripts/hero_card.gd")
const DamageNumbersScript := preload("res://scripts/damage_numbers.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")
const MeshMergeScript := preload("res://scripts/mesh_merge.gd")
const UnitModelScript2 := preload("res://scripts/unit_model.gd")

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
	test_enemy_looks()
	test_rounds()
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
	test_soldier_posts()
	test_soldier_command()
	test_skill_unlock()
	test_skill_unlock_validation()
	test_fx_r17_meshes()
	test_toon_materials()
	test_upgrade_tables()
	test_crit_roll_params()
	test_growth_economy()
	test_item_icons()
	test_arena_kit()
	test_dungeon_monsters()
	test_spawn_groups()
	test_idle_four_sides_at_once()
	test_dungeon_tables()
	test_dungeons_offline()
	test_ticket_dungeon_offline()
	test_equipment_offline()
	test_dungeon_save_and_server()
	test_seasons()
	test_recruit_r23()
	test_equip_upgrade_dot()
	test_hero_looks_unique()
	test_hero_look_builder()
	test_meshy_bodies()
	test_attack_sets()
	test_meshy_enemies()
	test_portrait_looks()
	test_scene_snap()
	test_crowd()
	test_research_r24()
	test_free_finish()
	test_offline_gold()
	test_mesh_merge()
	test_guild()
	test_tutorial()
	test_tutorial_online()
	test_missions()
	test_shop()
	test_iap()
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
	# grunt hp·atk 60·10 → 24·4(×0.4): 스폰 3배에도 시작 영웅으로 1스테이지 클리어. 처치 골드는 ×5(grunt 2 → 10, epic_boss 50 → 250)
	check(grunt.hp == 24.0 and grunt.atk == 4.0 and grunt.gold == 10 and GameData.monster("epic_boss").gold == 250, "monster table values")
	for key in ["hp", "atk", "speed", "range", "atk_interval", "scale", "aggro", "gold"]:
		for kind in ["grunt", "epic_boss"]:
			check(GameData.monster(kind).has(key), "monster %s has %s" % [kind, key])
	for s in range(1, 31):  # 1~30행은 직선 공식(개정 10: HP·공격력 10%, 골드 20%)
		var r := GameData.stage(s)
		check(is_equal_approx(r.hp_mult, 1.0 + 0.10 * (s - 1)) and is_equal_approx(r.atk_mult, 1.0 + 0.10 * (s - 1)), "hp/atk mult at stage %d" % s)
		check(int(r.waves) == 3 + floori(s / 3.0) and int(r.wave_size) == 6 + 2 * s and r.idle_interval == 8.0, "waves/size/idle at stage %d" % s)
		check(absf(r.gold_mult - (1.0 + 0.2 * (s - 1)) * pow(1.01, s - 1)) < 0.006, "gold_mult at stage %d follows (1 + 0.2(s-1)) x 1.01^(s-1)" % s)
	var r31 := GameData.stage(31)  # 직선 연장
	var r30 := GameData.stage(30)
	var r29 := GameData.stage(29)
	check(is_equal_approx(r31.hp_mult, 2.0 * r30.hp_mult - r29.hp_mult) and is_equal_approx(GameData.stage(40).hp_mult, 1.0 + 0.10 * 39), "stage beyond table extrapolates hp_mult")
	check(int(GameData.stage(40).wave_size) == 86 and int(GameData.stage(33).waves) == 14, "extrapolated int columns follow the 12-row slope and round (waves 33 = 14, same as the old 3 + floor(s/3))")
	check(GameData.kill_gold_tenths("grunt", 1) == 100 and GameData.kill_gold_tenths("grunt", 2) == 121 and GameData.kill_gold_tenths("grunt", 3) == 143, "kill_gold_tenths = gold x gold_mult in tenths (grunt 10: 10 x 1.21 -> 121, 10 x 1.43 -> 143)")
	check(GameData.kill_gold_tenths("epic_boss", 2) == 3025 and GameData.kill_gold_tenths("grunt", 31) == 943, "kill_gold_tenths boss (250 x 1.21) and extrapolated stage (9.07 x 7/6.8 x 1.01)")
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
	check(GameData.hero_slots(1) == 4 and GameData.hero_slots(8) == 4, "keep levels 1-8 give 4 heroes")
	check(GameData.hero_slots(9) == 8 and GameData.hero_slots(21) == 8, "keep levels 9-21 give 8 heroes")
	check(GameData.hero_slots(22) == 12, "keep level 22 gives 12 heroes")
	check(GameData.hero_slots(99) == 12, "keep level beyond the last tier stays at 12")
	check(GameData.gate_hp_max(1) == 400.0, "gate hp at level 1")
	check(GameData.gate_hp_max(2) > GameData.gate_hp_max(1), "gate hp grows with level")


func test_game_tables() -> void:
	GameData.load_tables()
	check(GameData.errors == 0, "default tables incl. heroes/resources/config load without errors")
	# Balance에서 옮긴 값 — 이전 상수와 같다(하드코딩 기대값)
	var heroes := GameData.heroes()
	check(heroes.size() == 36 and heroes[0].id == "arteon" and heroes[21].id == "jack" and heroes[35].id == "tia", "heroes keep file order")
	var w := GameData.hero("hans")
	check(w.name == "한스" and w.title == "민병대 검사" and w.grade == "R" and w.role == "melee" and w.model == "Knight" and w.gear == "1H_Sword" \
		and w.color == "#95A5A6" and w.hp == 396.0 and w.atk == 23.0 and w.range == 1.8 and w.atk_interval == 0.8 and w.speed == 6.0 and w.aggro == 8.0 \
		and w.skills == {"drain_slash": [8.0, 150.0, 50.0], "dmg_reduce": [10.0, 0.0, 0.0]}, "hans row (R: two skills)")
	var a := GameData.hero("arteon")
	check(a.skills == {"sanctuary": [9.0, 5.0, 5.0], "guard_aura": [6.0, 30.0, 0.0], "holy_smite": [8.0, 250.0, 50.0]} and a.desc.begins_with("성문 앞을"),
		"arteon row: three skills in column order, empty numbers are 0, desc")
	check(GameData.hero("hans").skills.size() == 2 and GameData.hero("ignis").skills.keys() == ["aoe_blast", "haste", "ignite"], "an empty skill3 is no skill (R)")
	check(GameData.hero("nobody").is_empty(), "unknown hero is empty")
	var res := GameData.resources()
	check(res.size() == 3 and res[0].id == "wood" and res[1].id == "stone" and res[2].id == "food", "resources keep file order")
	var st := GameData.resource("stone")
	check(st.name == "석재" and st.building == "quarry" and st.per_min == 100.0 and st.price == 2.0, "stone row = old RESOURCES")
	check(GameData.resource("wood").building == "lumber" and GameData.resource("food").per_min == 100.0 and GameData.resource("food").building == "farm", "wood/food rows")
	check(GameData.resource_of_building("farm") == "food" and GameData.resource_of_building("keep") == "", "resource_of_building")
	var nums := {"castle_hp": 1000.0, "gate_hp_per_level": 400.0, "max_live_monsters": 120.0, "countdown_sec": 3.0, "result_sec": 2.0,
		"wave_gap_sec": 8.0, "spawn_spacing_sec": 1.0, "spawn_group": 3.0, "accum_cap_min": 720.0, "badge_min": 5.0, "merchant_jackpot_p": 0.05,
		"merchant_jackpot_rate": 2.0, "merchant_rate_min": 0.5, "merchant_rate_max": 1.5, "merchant_rate_step": 0.1,
		"merchant_low_high_ratio": 3.0, "kill_rate_cap": 5.0}
	for key in nums:
		check(GameData.config_num(key) == nums[key], "config %s = %s" % [key, nums[key]])
	check(GameData.config_list("merchant_rate_step") == [0.1], "config_list parses numbers")
	check(GameData.config_list("starter_heroes") == ["hans", "ella", "dorik", "nina"], "config_list keeps strings")
	check(GameData.config_list("nope").is_empty() and GameData.config_num("nope") == 0.0, "unknown config key is empty / 0")
	check(GameData.config_num("promote_mult") == 1.3 and GameData.config_list("promote_shards") == [5.0, 25.0, 50.0, 100.0, 200.0] and GameData.config_num("gacha_dia_cost_10") == 2700.0, "hero/gacha/promotion config")
	# 깨진 config 파일: 필수 키 빠짐
	var logged := _errors.count
	var cp := "user://t_config.csv"
	_write(cp, "key,value\ncastle_hp,1000\nkeep_slot_tiers,1:4|5:8|10:12\nkeep_interior_tiers,1:20|5:24|10:28\nstarter_heroes,hans|ella\n")
	GameData.load_tables(GameData.MONSTERS_PATH, GameData.STAGES_PATH, GameData.HEROES_PATH, GameData.RESOURCES_PATH, cp)
	check(GameData.errors == GameData.CONFIG_NUM_KEYS.size() - 1 + GameData.CONFIG_LIST_KEYS.size() - 1 + GameData.BUILDING_NUM_KEYS.size() + GameData.SOLDIER_NUM_KEYS.size()
		+ GameData.soldiers().size() + GameData.DUNGEON_NUM_KEYS.size() + GameData.RESEARCH_NUM_KEYS.size(), "config file missing keys reports one error per key (rev 16: train_cost_<type> per soldier, rev 18: dungeon keys, rev 24: research keys)")
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
	for k in GameData.CONFIG_NUM_KEYS + GameData.CONFIG_LIST_KEYS + GameData.BUILDING_NUM_KEYS + GameData.CONFIG_TIER_KEYS + GameData.SOLDIER_NUM_KEYS + GameData.DUNGEON_NUM_KEYS + GameData.RESEARCH_NUM_KEYS:
		cfg[k] = String(GameData._config[k])
	for sd in GameData.soldiers():  # 개정 16 훈련 비용
		cfg["train_cost_" + sd.id] = String(GameData._config["train_cost_" + sd.id])
	return {"version": "t", "monsters": [GameData.monster("grunt").duplicate(), GameData.monster("epic_boss").duplicate()],
		"stages": stages, "heroes": GameData.heroes().duplicate(true), "resources": GameData.resources().duplicate(true),
		"buildings": GameData.buildings().duplicate(true), "soldiers": GameData.soldiers().duplicate(true),
		"upgrades": GameData.upgrades().duplicate(true), "config": cfg,
		"dungeons": GameData._dungeons.duplicate(true), "equip_drop": GameData._equip_drop.duplicate(true), "research": _research_rows()}


## 연구 표를 서버 행처럼(개정 24): 빈 선행은 null.
func _research_rows() -> Array:
	var out := []
	for d in GameData.research_defs():
		var r: Dictionary = d.duplicate()
		for rq in GameData.RESEARCH_REQS:
			if r[rq[0]] == "":
				r[rq[0]] = null
				r[rq[1]] = null
		out.append(r)
	return out


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
	p.heroes[1].s2b = null
	p.heroes[1].s2c = null
	p.heroes[17].skill3 = null  # 한스(R): 셋째 칸 없음
	p.heroes[17].s3a = null
	check(GameData.apply_remote(p) and GameData.errors == 0, "apply_remote accepts changed payload")
	check(GameData.hero("arteon").hp == 999.0 and GameData.heroes().size() == 36 and GameData.default_deploy(3) == ["jack", "kyle", null], "remote heroes + starters replace the table")
	check(GameData.hero("ignis").skills == {"aoe_blast": [5.0, 3.5, 220.0], "haste": [25.0, 0.0, 0.0], "ignite": [8.0, 3.0, 40.0]}
		and GameData.hero("hans").skills.size() == 2, "remote hero row with numbers and nulls parses skills")
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
		["upgrade unit unknown", 1], ["upgrade growth below 1", 1], ["upgrade max level 0", 1], ["upgrade cost 0", 1], ["upgrades missing", 1], ["duplicate upgrade id", 1],
		["dungeon type unknown", 1], ["dungeon table missing", 1], ["no equip dungeon enemy", 1], ["dungeon count 0", 1], ["drop min_level gap", 1],
		["drop weight negative", 1], ["dungeon config missing", 1], ["reset hour 24", 1], ["weapon chance above 1", 1],
		["rounds per stage 0", 1], ["rounds per stage 2.5", 1], ["speed step negative", 1], ["speed cap below 1", 1], ["boss mult 0", 1], ["round config missing", 1],
		["research branch unknown", 1], ["research effect unknown", 1], ["research prereq unknown", 1], ["research prereq level above max", 1],
		["research prereq without level", 1], ["research base_sec 0", 1], ["research max level 0", 1], ["research table missing", 1], ["duplicate research id", 1],
		["research refund above 1", 1], ["research growth below 1", 1], ["research dia per min 1.5", 1], ["research config missing", 1],
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
	return hash([GameData._monsters, GameData._stages, GameData._heroes, GameData._resources, GameData._buildings, GameData._soldiers, GameData._upgrades, GameData._config,
		GameData._dungeons, GameData._equip_drop, GameData._research])


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
		"gacha cost not an integer": q.config.gacha_dia_cost_1 = "300.5"  # 서버 BigInt(-cost)가 throw
		"gacha cost negative": q.config.gacha_dia_cost_10 = "-1"
		"gacha guarantee not an integer": q.config.gacha_10_min_sr = "1.5"
		"gacha rate above 1": q.config.gacha_dia_ssr = "1.5"
		"gacha rates sum above 1": q.config.gacha_dia_sr = "0.98"
		"a grade with no heroes": q.heroes = q.heroes.filter(func(h): return h.grade != "SR")  # roll_gacha가 빈 풀에서 깨진다
		"multishot 0": q.heroes[2].s2a = 0  # 실바나: slice(0, -1)
		"skill cooldown 0": q.heroes[1].s1a = 0  # 이그니스 aoe_blast: 매 프레임 폭발
		"haste -100": q.heroes[1].s2a = -100  # 이그니스 haste: 간격 ÷ 0
		"stun every 2.5th attack": q.heroes[16].s2a = 2.5  # 펠릭스
		"hero attack interval 0": q.heroes[0].atk_interval = 0
		"hero hp negative": q.heroes[0].hp = -5
		"upgrade unit unknown": q.upgrades[0].unit = "percent"
		"upgrade growth below 1": q.upgrades[1].cost_growth = 0.9
		"upgrade max level 0": q.upgrades[2].max_level = 0
		"upgrade cost 0": q.upgrades[3].cost_base = 0
		"upgrades missing": q.erase("upgrades")
		"duplicate upgrade id": q.upgrades[1].id = "atk"
		"resource building not in the layout": q.resources[0].building = "mine"  # 배치에 없다(badges.gd가 깨진다)
		"dungeon type unknown": q.dungeons[2].type = "fire"  # 개정 18
		"dungeon table missing": q.erase("dungeons")
		"no equip dungeon enemy": q.dungeons = q.dungeons.filter(func(d): return d.type != "equip")
		"dungeon count 0": q.dungeons[0].count = 0
		"drop min_level gap": q.equip_drop[0].min_level = 2
		"drop weight negative": q.equip_drop[1].N = -1
		"dungeon config missing": q.config.erase("gold_dg_base")
		"reset hour 24": q.config.daily_reset_utc_hour = "24"
		"weapon chance above 1": q.config.equip_weapon_p = "1.5"
		"rounds per stage 0": q.config.rounds_per_stage = "0"  # 개정 22: g → S-r 나눗셈이 0으로
		"rounds per stage 2.5": q.config.rounds_per_stage = "2.5"
		"speed step negative": q.config.stage_speed_step = "-0.1"
		"speed cap below 1": q.config.stage_speed_cap = "0.9"
		"boss mult 0": q.config.boss_round_mult = "0"
		"round config missing": q.config.erase("rounds_per_stage")
		"research branch unknown": q.research[0].branch = "magic"  # 개정 24
		"research effect unknown": q.research[0].effect = "fly_pct"
		"research prereq unknown": q.research[3].req1 = "nope"  # 건축학
		"research prereq level above max": q.research[3].req1_lv = 11
		"research prereq without level": q.research[3].req1_lv = null
		"research base_sec 0": q.research[0].base_sec = 0
		"research max level 0": q.research[21].max_level = 0  # 불굴의 의지(아무도 선행으로 쓰지 않는다)
		"research table missing": q.erase("research")
		"duplicate research id": q.research[1].id = "wood_tech"
		"research refund above 1": q.config.research_cancel_refund = "1.5"
		"research growth below 1": q.config.research_cost_growth = "0.9"
		"research dia per min 1.5": q.config.research_dia_per_min = "1.5"
		"research config missing": q.config.erase("research_time_growth")


func test_apply_remote() -> void:
	var logged := _errors.count
	GameData.load_tables()
	var expected := _remote_checks()
	check(_errors.count - logged == expected, "rejected payloads report each error through push_error")
	_errors.count = logged
	GameData.load_tables()
	check(GameData.errors == 0 and GameData.hero("arteon").hp == 936.0 and GameData.config_num("castle_hp") == 1000.0 and GameData.heroes().size() == 36, "default tables restored after apply_remote tests")


## 개정 22 §2: 에픽 보스는 라운드 25(스테이지 마지막)에만, 끝에 하나 — HP × boss_round_mult. 라운드 1~24는 졸개만.
func test_wave_stage_ends_with_boss() -> void:
	var ev := WaveDirector.build(25, WaveDirector.MODE_STAGE)
	check(ev.size() > 1, "stage schedule has events")
	check(ev[-1].kind == "epic_boss" and ev[-1].hp_mult == 1.5, "round 1-25 ends with epic_boss (hp x boss_round_mult 1.5)")
	for i in range(1, ev.size()):
		check(ev[i].time >= ev[i - 1].time, "events sorted at %d" % i)
	var bosses := ev.filter(func(e): return e.kind == "epic_boss").size()
	check(bosses == 1, "exactly one boss")
	for e in ev:
		check(e.side >= 0 and e.side <= 3, "side in range")
	var boss_rounds := []
	for g in range(1, 52):
		if WaveDirector.build(g, WaveDirector.MODE_STAGE).any(func(e): return e.kind == "epic_boss"):
			boss_rounds.append(GameData.round_label(g))
	check(boss_rounds == ["1-25", "2-25"], "g 1..51: a boss only on round 25 of each stage %s" % [boss_rounds])


## 개정 22 §1 §3: 전체 라운드 g ↔ 스테이지 S·라운드 r("S-r"), 적 이동속도 배율 min(2.0, 1 + 0.08 × (S − 1)).
func test_rounds() -> void:
	check(GameData.rounds_per_stage() == 25 and GameData.config_num("stage_speed_step") == 0.08 and GameData.config_num("stage_speed_cap") == 2.0
		and GameData.config_num("boss_round_mult") == 1.5, "round config: 25 rounds, step 0.08, cap 2.0, boss x1.5")
	var sr: Array = [1, 25, 26, 50, 51].map(func(g): return [GameData.round_stage(g), GameData.round_in_stage(g), GameData.round_label(g)])
	check(sr == [[1, 1, "1-1"], [1, 25, "1-25"], [2, 1, "2-1"], [2, 25, "2-25"], [3, 1, "3-1"]], "g -> S, r, 'S-r' for 1, 25, 26, 50, 51: %s" % [sr])
	check([1, 24, 25, 26, 50].map(func(g): return GameData.is_boss_round(g)) == [false, false, true, false, true], "boss round = r 25")
	var mults: Array = [1, 2, 5, 13, 20].map(func(s): return GameData.enemy_speed_mult((s - 1) * 25 + 1))
	var want := [1.0, 1.08, 1.32, 1.96, 2.0]
	var ok := true
	for i in want.size():
		ok = ok and is_equal_approx(mults[i], want[i])
	check(ok, "speed mult for stage 1, 2, 5, 13, 20 = 1.00, 1.08, 1.32, 1.96, 2.0 (cap) %s" % [mults])
	check(GameData.enemy_speed_mult(25) == 1.0 and is_equal_approx(GameData.enemy_speed_mult(50), 1.08), "speed is the same for all 25 rounds of a stage")


func test_wave_total_monotonic() -> void:
	var prev := 0
	for stage in range(1, 11):
		var n := WaveDirector.build(stage, WaveDirector.MODE_STAGE).size()
		check(n >= prev, "spawn count non-decreasing at stage %d" % stage)
		prev = n


func test_enemy_looks() -> void:
	var looks := {}
	for g in range(1, 26):
		looks[GameData.enemy_look(g)] = true
	check(looks.size() == 5, "five different enemy looks within one stage")
	check(GameData.enemy_look(1) == "grunt" and GameData.enemy_look(5) == "grunt" and GameData.enemy_look(6) == "zombie", "look changes every 5 rounds, stage 1 starts with skeletons")
	check(GameData.enemy_look(26) == "imp" and GameData.enemy_look(51) == "frost_troll", "next stage continues with the next looks")
	check(GameData.boss_look(25) == "epic_boss" and GameData.boss_look(50) == "ogre_warlord" and GameData.boss_look(75) == "orc_chief", "boss look changes per stage")
	for look in GameData.ENEMY_LOOKS + GameData.BOSS_LOOKS:
		check(not look in ["goblin", "goblin_king", "death_knight"], "dungeon monsters stay in dungeons: " + look)
	for look in GameData.ENEMY_LOOKS + GameData.BOSS_LOOKS:
		check(Art.MONSTER_MODELS.has(look), "look has a model: " + look)
	for e in WaveDirector.build(6, WaveDirector.MODE_STAGE) + WaveDirector.build(6, WaveDirector.MODE_IDLE):
		check(e.kind in ["grunt", "epic_boss"], "looks keep the monster table ids (stats, gold)")
		check(e.kind != "grunt" or e.look == "zombie", "round 6 grunts look like zombies")
	var boss: Array = WaveDirector.build(50, WaveDirector.MODE_STAGE).filter(func(e): return e.kind == "epic_boss")
	check(boss.size() == 1 and boss[0].look == "ogre_warlord", "stage 2 boss looks like the ogre warlord")


func test_wave_idle_cycle() -> void:
	var ev := WaveDirector.build(1, WaveDirector.MODE_IDLE)
	check(ev.size() == 12, "idle cycle spawns 4 groups of 3")
	check(ev[0].time > 0.0, "first idle spawn is not at t=0")
	var sides: Array = ev.map(func(e): return e.side)
	check(sides == [0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3], "idle sides 0..3, one group per side")
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
	gs.keep_level = 9
	check(gs.hero_count() == 8, "8 heroes at keep level 9 (keep tier)")
	gs.free()


func test_layout_tables() -> void:
	check(GameData.interior_half(1) == 20.0 and GameData.interior_half(8) == 20.0, "interior half is 20m at keep levels 1-8")
	check(GameData.interior_half(9) > GameData.interior_half(8), "interior grows at keep level 9")
	check(GameData.interior_half(22) > GameData.interior_half(21), "interior grows at keep level 22")
	check(GameData.interior_half(99) == GameData.interior_half(22), "interior stays at the last tier")
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
	# claim_near: 누른 지점에 가장 가까운 빈 슬롯(자기 슬롯 포함) — 같은 면 성벽 위 좌↔우 이동
	var g = FormationScript.new()
	var offs: Array = Balance.WALL_TOP_SLOTS
	var right: int = offs.find(offs.max())
	var left: int = offs.find(offs.min())
	check(g.claim_near(0, 0, wall, 99.0) == right, "claim_near picks the slot nearest the tap (far right)")
	check(g.claim_near(0, 0, wall, -99.0) == left, "claim_near moves the same hero across the wall to the far left")
	check(g.assignment(0).slot == left, "claim_near frees the old slot")
	check(g.claim_near(1, 0, wall, -99.0) != left, "claim_near skips a slot another hero holds")
	check(g.claim_near(0, 0, wall, -99.0) == left, "claim_near keeps the hero's own slot when it is nearest")
	for i in range(2, 2 + FormationScript.capacity(wall)):
		g.claim(i, 0, wall)
	check(g.claim_near(20, 0, wall, 0.0) == -1 and g.assignment(20).is_empty(), "claim_near on a full wall fails and assigns nothing")


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
		for at in FormationScript.gate_offsets(half):  # 성문마다 좌우 계단
			var along: float = absf(FormationScript.perp(s).dot(p) - float(at))
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
	for level in [1, 9, 22]:  # 성채 단계마다(keep_interior_tiers)
		var h := GameData.interior_half(level)
		var spots: Array = []
		for s in 4:
			for at in F.gate_offsets(h):
				spots.append(F.gate_inner(h, s, at))
			for post in [F.POST_GATE, F.POST_WALL]:
				for slot in F.capacity(post, F.gates_per_side(h)):
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
	check(EconomyScript.rate_per_min("wood", 1) == 100 and EconomyScript.rate_per_min("stone", 3) == 300, "rate = per_min x level")
	check(EconomyScript.pending_amount("wood", 1, 59.9) == 0, "pending: under a minute is 0")
	check(EconomyScript.pending_amount("wood", 1, 119.9) == 100, "pending floors minutes")
	check(EconomyScript.pending_amount("stone", 2, 600.0) == 2000, "pending scales with level")
	check(EconomyScript.pending_amount("wood", 1, 720 * 60.0) == 72000 and EconomyScript.pending_amount("wood", 1, 99999999.0) == 72000, "pending capped at 720 min")
	check(EconomyScript.pending_amount("wood", 1, -500.0) == 0, "pending: negative elapsed is 0")
	check(EconomyScript.res_of("lumber") == "wood" and EconomyScript.res_of("quarry") == "stone" and EconomyScript.res_of("farm") == "food" and EconomyScript.res_of("keep") == "", "res_of maps resource buildings only")


func test_economy_collect() -> void:
	var e = _econ(1000.0)
	e.last_collect.lumber = 1000.0 - 150.0  # 2분 30초
	check(e.collect("lumber", 1000.0) == 200 and e.res.wood == 200, "collect adds 2 min of wood")
	check(is_equal_approx(e.last_collect.lumber, 1000.0 - 30.0), "collect keeps the leftover 30 s: %s" % e.last_collect.lumber)
	check(e.collect("lumber", 1000.0) == 0 and is_equal_approx(e.last_collect.lumber, 970.0) and e.res.wood == 200, "collect with nothing pending changes nothing")
	e.last_collect.quarry = 1000.0 - 800 * 60.0  # 상한 초과
	check(e.collect("quarry", 1000.0) == 720 * 100 and e.last_collect.quarry == 1000.0, "collect at the cap snaps last_collect to now")
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
		for level in [1, 9, 22]:  # 성채 단계마다
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
	e.gold_tenths = 5
	e.add_kill("grunt", 2)
	check(e.gold_tenths == 126 and e.gold == 12, "an offline kill adds 12.1 gold at stage 2 on top of 0.5 and shows 12")
	e.add_kill("grunt", 2)
	e.add_kill("grunt", 2)
	check(e.gold_tenths == 368 and e.gold == 36, "tenths accumulate across kills (0.5 + 36.3 shows 36)")
	e.save()
	var f := FileAccess.open(ECON_TMP, FileAccess.READ)
	var saved = JSON.parse_string(f.get_as_text())
	f.close()
	check(int(saved.version) == EconomyScript.SAVE_VERSION and int(saved.gold_tenths) == 368 and not saved.has("gold"), "save writes the current version with gold_tenths")
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
	check(hs.size() == 36, "36 heroes, got %d" % hs.size())
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
	check(grades == {"SSR": 16, "SR": 12, "R": 8}, "grades 16/12/8: %s" % grades)
	# crit 스킬은 영웅 표에서 뺐다(성장 치명타와 헷갈리지 않게) — 종류는 남아 있어 표에 다시 쓸 수 있다
	# 2026-10-06 재구성: 영웅 36명 × 고유 스킬 100종(예전 패시브 종류 일부는 표에서 빠졌지만 종류는 남아 있다)
	check(used.size() == 100 and not used.has("crit"), "100 distinct skill kinds on heroes: %d" % used.size())
	for h in hs:  # SSR·SR = 액티브·패시브·액티브, R = 액티브·패시브
		var ks: Array = h.skills.keys()
		var want: Array = [true, false] if h.grade == "R" else [true, false, true]
		check(ks.map(func(k): return HeroSkillsScript.is_active(k)) == want, "hero %s: active/passive slots %s" % [h.id, ks])
	# 초상화 쿨 칸 스킬 그림(2026-10-06): 발동형마다 그림이 있고 그 그림은 도형이 있다
	for k in HeroSkillsScript.ACTIVE + HeroSkillsScript.HERO_ACTIVE:
		check(SkillIconsScript.KIND.has(k) and not SkillIconsScript.shapes(SkillIconsScript.glyph_of(k)).is_empty(), "skill %s has a thumbnail" % k)
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
	check(Skills.damage(boss, 60.0, 0.9, 1.0, true) == 150.0 and is_equal_approx(Skills.damage(boss, 60.0, 0.9, 1.0, false), 78.0), "boss_slayer: +a% to bosses, a/5 to other enemies")
	check(is_equal_approx(Skills.damage({"crit": [40.0, 250.0, 0.0], "execute": [30.0, 100.0, 0.0]}, 81.0, 0.0, 0.2, false), 81.0 * 2.5 * 2.0), "crit and execute multiply")
	check(GameData.heroes().all(func(h): return not h.skills.has("crit")), "no hero has the crit skill (crit comes from growth only)")
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
	check(GameData.promote_mult(0) == 1.0 and is_equal_approx(GameData.promote_mult(1), 1.3) and is_equal_approx(GameData.promote_mult(2), 1.69) and is_equal_approx(GameData.promote_mult(5), 3.71293) \
		and GameData.promote_mult(9) == GameData.promote_mult(5), "promotion mult = 1.3^p (p 5 = x3.71), capped at 5")
	check(range(-1, 7).map(func(p): return GameData.promote_cost(p)) == [0, 5, 25, 50, 100, 200, 0, 0] and GameData.MAX_PROMOTION == 5,
		"promotion cost p -> p+1 = 5|25|50|100|200 shards; none at the max (5)")
	check(range(0, 6).map(func(p): return GameData.max_level(p)) == [20, 30, 40, 50, 60, 70], "max level = 20 + 10 x promotion (70 at 5)")
	var gs = GameStateScript.new()
	check(gs.deploy() == GameData.default_deploy(4) and gs.hero_promotion("hans") == 0, "GameState deploy provider: starters, promotion 0")
	gs.keep_level = 9
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


## 개정 10 모집(오프라인, 스펙 §3.6): 10만 장 표본 확률, 다이아 10연차만 보장(표본 + 조작 난수 — 골드는 없음), 비용 tenths(소수 남음), copies·NEW, 부족하면 알림만,
## 같은 seed면 같은 결과.
func test_gacha_offline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var n := 100000
	var out: Array = EconomyScript.roll_gacha(n, rng.randf)
	var c := {"SSR": 0, "SR": 0, "R": 0}
	for x in out:
		c[x.grade] += 1
	check(out.size() == n and absf(c.SSR / float(n) - 0.005) <= 0.0015 and absf(c.SR / float(n) - 0.05) <= 0.0045, "gold Lv 1 rates SSR 0.5%% +- 0.15%%, SR 5%% +- 0.45%% (~6.5 sigma): %s" % [c])
	check(out.slice(0, 200).all(func(x): return GameData.hero(x.id).grade == x.grade), "each pull is a hero of its grade")
	var dia := GameData.gacha_rates("diamond", 1, 1)
	var all_ten := true
	for i in 2000:
		var ten: Array = EconomyScript.roll_gacha(10, rng.randf, dia, {"n": 0, "max": 50})
		all_ten = all_ten and ten.size() == 10 and ten.any(func(x): return x.grade != "R")
	check(all_ten, "every diamond 10-pull has an SR or better (2000 samples)")
	var all_r := func(): return 0.99  # 전부 R, 풀 마지막(tia)
	var rigged: Array = EconomyScript.roll_gacha(10, all_r, dia, {"n": 0, "max": 50})
	check(rigged.slice(0, 9).all(func(x): return x.id == "tia") and rigged[9] == {"id": "selene", "grade": "SR"}, "a diamond 10-pull with no SR+ turns the last card into an SR: %s" % [rigged])
	var gold_ten: Array = EconomyScript.roll_gacha(10, all_r)
	check(gold_ten.size() == 10 and gold_ten.all(func(x): return x == {"id": "tia", "grade": "R"}), "a gold 10-pull has no SR guarantee (all R stays all R): %s" % [gold_ten])
	check(EconomyScript.roll_gacha(1, all_r) == [{"id": "tia", "grade": "R"}], "a single pull has no guarantee")
	check(GameData.gacha_cost("gold", 1, 1) == 3000 and GameData.gacha_cost("gold", 10, 1) == 30000, "gold Lv 1 costs 3000 / 30000 (10-pull = 1-pull x 10, no discount)")
	var e = _econ(1000.0)
	e.rng.seed = 7
	var got := []
	var notices := []
	e.gacha_done.connect(func(r): got.append(r))
	e.notice.connect(func(t): notices.append(t))
	e.gold_tenths = 330005
	check(e.gacha(10) and e.gold_tenths == 30005 and got.size() == 1 and got[0].size() == 10, "10-pull costs 30000 gold (300000 tenths) and returns 10 cards")
	var seen := _econ_starters()
	var consistent := true
	for r in got[0]:
		var before := int(seen.get(r.hero_id, 0))
		seen[r.hero_id] = before + 1
		consistent = consistent and r.new == (before == 0) and r.copies == before + 1 and r.grade == GameData.hero(r.hero_id).grade and r.shards == before
	check(consistent and seen == e.heroes, "results: new only on the first copy, copies count up per card, heroes updated: %s" % [got[0]])
	check(e.heroes.keys().all(func(id): return e.shards_of(id) == int(e.heroes[id]) - 1) and e.hero_promotions.is_empty(),
		"rev 15: a repeat pull adds a shard (new heroes start at 0); recruiting never promotes: %s" % [e.hero_shards])
	check(e.gacha(1) and e.gold_tenths == 5 and got.size() == 2, "1 pull costs 3000 (30000 tenths), the 0.5 fraction stays")
	check(not e.gacha(1) and e.gold_tenths == 5 and got.size() == 2 and notices == [EconomyScript.NO_GOLD_TEXT], "not enough gold: nothing happens, one notice")
	e.gold = 99999
	check(not e.gacha(3) and e.gold == 99999, "only 1 or 10 pulls")
	var a = _econ(0.0)
	var b = _econ(0.0)
	a.rng.seed = 99
	b.rng.seed = 99
	a.gold = 30000
	b.gold = 30000
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
	e2.levels["keep"] = 9  # roster가 있으면 성채 레벨은 roster(Economy) 건물 레벨
	check(gs.deploy().size() == 8 and gs.deploy()[4] == "nina", "provider: more slots at keep level 9")
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
	check(GameData.level_mult(1) == 1.0 and is_equal_approx(GameData.level_mult(10), 1.378) and is_equal_approx(GameData.level_mult(70), 3.898), "level x(1 + 0.042 x (L - 1))")
	check(GameData.level_mult(1, "melee") == 1.0 and is_equal_approx(GameData.level_mult(10, "melee"), 1.2835) and is_equal_approx(GameData.level_mult(10, "ranged"), 1.378),
		"melee heroes grow slower: x(1 + 0.0315 x (L - 1))")
	var st := GameData.hero_stats(hans, 10, 2)  # 근접: 396 × 1.2835 × 1.3², 23 × 1.2835 × 1.3²
	check(is_equal_approx(st.hp, 396.0 * 1.2835 * 1.69) and is_equal_approx(st.atk, 23.0 * 1.2835 * 1.69), "stats = base x level mult x promotion mult (1.3^p on base and level-ups alike): %s" % [st])
	check(GameData.hero_power(hans, 1, 0) == 97 and GameData.hero_power(GameData.hero("kyle"), 1, 0) == 496 \
		and GameData.hero_power(hans, 10, 2) == roundi(396.0 * 2.169115 / 10.0 + 23.0 * 2.169115 * 2.0 / 0.8) and GameData.hero_power(hans, 1, 1) == 126,
		"power = round((HP / 10 + atk x 2 / interval) x grade): hans %d, kyle %d" % [GameData.hero_power(hans, 1, 0), GameData.hero_power(GameData.hero("kyle"), 1, 0)])
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
	for bad in [["hero_max_level_base", "0"], ["hero_max_level_per_promotion", "-1"], ["levelup_gold_SSR", "1.5"], ["levelup_gold_R", "-10"], ["hero_level_stat", "-0.1"], ["hero_level_stat_melee", "-0.1"],
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
	check(is_equal_approx(after.hp, before.hp * 1.3) and is_equal_approx(after.atk, before.atk * 1.3) and GameData.max_level(e.promotion_of("arteon")) == 30
		and e.levelup_block("arteon") == "골드 부족", "promotion: HP/atk x1.3 (base and level-ups), max level 20 -> 30 (Lv 20 can level again)")
	check(e.promote_block("arteon") == "not_enough_shards" and e.promote_cost("arteon") == 25, "next step costs 25")
	e.hero_shards["arteon"] = 25 + 50 + 100 + 200
	for i in 4:
		e.promote("arteon")
	check(e.promotion_of("arteon") == 5 and e.shards_of("arteon") == 0 and is_equal_approx(GameData.promote_mult(5), 3.71293) and GameData.max_level(5) == 70,
		"25 + 50 + 100 + 200 shards take promotion 1 -> 5 (x3.71, max level 70)")
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
	check(is_equal_approx(hp_v5, 396.0 * 1.252), "the old +10%%/star bonus is gone: 3 stars of copies give no stat bonus (%.1f)" % hp_v5)
	var v6 := v5.duplicate(true)
	v6.version = 6
	_write(ECON_TMP, JSON.stringify(v6))  # v6인데 shards·promotion이 없다
	e2.load_save(1000.0)
	check(e2.gold_tenths == 0 and e2.heroes == _econ_starters() and e2.hero_shards.is_empty(), "a v6 save without shards/promotion is corrupt: defaults")
	DirAccess.remove_absolute(ECON_TMP)
	e.free()
	e2.free()
	# 일괄 승급: 보유 영웅마다 지금 조각으로 갈 수 있는 데까지(단계별 비용 합), 오프라인은 곧바로 반영
	var b = _econ(1000.0)
	var all := []
	b.promoted_all.connect(func(r): all.append(r))
	check(b.promote_all_plan().is_empty(), "bulk promotion: starters without shards have nothing to promote")
	b.hero_shards["hans"] = 31  # 0 -> 2 (5 + 25), 1 left
	b.hero_shards["ella"] = 4  # not enough
	b.heroes["arteon"] = 1
	b.hero_shards["arteon"] = 999
	b.hero_promotions["arteon"] = 4  # 4 -> 5 (200), stops at the max
	var plan: Array = b.promote_all_plan()
	var by := {}
	for r in plan:
		by[r.hero_id] = [r.from, r.to, r.shards]
	check(by == {"hans": [0, 2, 30], "arteon": [4, 5, 200]}, "bulk plan: each hero as far as its shards go: %s" % [by])
	check(b.promote_all() and b.promotion_of("hans") == 2 and b.shards_of("hans") == 1 and b.promotion_of("arteon") == 5 and b.shards_of("arteon") == 799
		and b.promotion_of("ella") == 0 and b.shards_of("ella") == 4 and all.size() == 1 and all[0].size() == 2, "offline bulk promotion applies the plan and signals once")
	check(b.promote_all_plan().is_empty() and not b.promote_all(), "after a bulk promotion nothing is left to promote")
	b.free()


## 개정 12 건물: 표(9행·파일 순서), 비용·시간 공식(서버 buildings.test와 같은 값), 단계 표(슬롯·내부), 효과 수치(성 HP·성문 HP·인구·
## 막사·연구소·주점 확률), 업그레이드 판단(이유 코드 순서·선행 목록), 오프라인 업그레이드(즉시 차감·일꾼·자동 수집·게으른 완료),
## 저장 v4·v3 → v4, 온라인 응답(buildings·build — 첫 반영은 완료가 아님), GameState(건물 레벨 → 성·성문 HP·슬롯), apply_remote 검증.
func test_buildings() -> void:
	GameData.load_tables()
	var ids: Array = GameData.buildings().map(func(b): return b.id)
	check(GameData.errors == 0 and ids == ["keep", "gate", "barracks", "tavern", "lab", "houses", "lumber", "quarry", "farm", "archery", "stable"], "buildings.csv: 11 rows in file order: %s" % [ids])
	var gate := GameData.building_def("gate")
	check(gate.name == "성문" and gate.max_level == 30.0 and gate.stone == 2500.0 and gate.base_sec == 45.0 and gate.req1 == "quarry" and gate.req2 == "", "gate row (empty req is \"\")")
	# 비용 = round(값 × 1.35^(L−1)), 시간 = round(base_sec × 1.5^(L−1)) — 서버와 같은 표
	check(GameData.build_cost("lumber", 1) == {"wood": 600, "stone": 800, "food": 400} and GameData.build_sec("lumber", 1) == 20, "lumber 1 -> 2: 600/800/400, 20 s")
	check(GameData.build_cost("keep", 2) == {"wood": 4050, "stone": 4050, "food": 2700} and GameData.build_sec("keep", 2) == 90, "keep 2 -> 3")
	check(GameData.build_cost("keep", 10) == {"wood": 44681, "stone": 44681, "food": 29787} and GameData.build_sec("keep", 10) == 2307, "keep 10 -> 11: about 44,680 / 29,790, about 38 min")
	check(GameData.build_cost("gate", 2) == {"wood": 2025, "stone": 3375, "food": 0} and GameData.build_sec("gate", 2) == 68 and GameData.build_cost("keep", 3) == {"wood": 5468, "stone": 5468, "food": 3645},
		"gate 2 -> 3: 67.5 s rounds away from zero; keep 3 -> 4: 3000 x 1.35^2 = 5467.5 rounds away from zero")
	check(GameData.build_sec("lumber", 20) == 44337 and GameData.build_cost("keep", 29) == {"wood": 13380328, "stone": 13380328, "food": 8920219}, "level 20 is about 2,217x the base time; level 29 costs")
	check(GameData.build_cost("mine", 1).is_empty() and GameData.build_sec("mine", 1) == 0, "unknown building: no cost, no time")
	# 단계 표
	check(GameData.parse_tiers("1:4|5:8|10:12") == [[1, 4.0], [5, 8.0], [10, 12.0]] and GameData.parse_tiers(" 1 : 20 | 5:24 ") == [[1, 20.0], [5, 24.0]], "tier tables parse")
	var bad_tiers := ["", "4|8|12", "2:4|5:8", "1:4|5:8|5:9", "1:4|3:8|2:9", "1:x", "1:4|", "1:4|5", "a:1", "1.5:4"]
	check(bad_tiers.all(func(s): return GameData.parse_tiers(s).is_empty()), "malformed tier tables are rejected")
	check([1, 8, 9, 21, 22, 30].map(func(l): return GameData.hero_slots(l)) == [4, 4, 8, 8, 12, 12], "hero slots by keep tier: 4/8/12")
	check([1, 8, 9, 22].map(func(l): return GameData.interior_tiles(l)) == [20, 20, 28, 36] and GameData.interior_half(9) == 28.0, "interior tiles by keep tier: 20/28/36")
	check([1, 8, 9, 21, 22, 30].map(func(l): return GameData.gates_at(l)) == [1, 1, 2, 2, 3, 3], "gates per side by keep tier: 1/2/3")
	# 효과 수치
	check(GameData.castle_hp_max(1) == 1000.0 and GameData.castle_hp_max(5) == 1800.0 and GameData.gate_hp_max(3) == 1200.0, "castle hp = 1000 + 200 x (keep - 1), gate hp = 400 x gate")
	check([0, 1, 2, 3, 30].map(func(l): return GameData.population(l)) == [6, 6, 8, 10, 64], "population = 6 + 2 x (houses - 1)")
	check(is_equal_approx(GameData.research_speed({}, 1), 0.0) and is_equal_approx(GameData.research_speed({}, 30), 0.58), "lab: research speed +2% per level above 1 (Lv 30 = +58%)")
	var r1 := GameData.gacha_rates("gold", 1, 1)
	var r11 := GameData.gacha_rates("gold", 1, 11)
	check(is_equal_approx(r1.ssr, 0.005) and is_equal_approx(r1.sr, 0.05) and is_equal_approx(r11.ssr, 0.015) and is_equal_approx(r11.sr, 0.08), "tavern: SSR +0.1%p, SR +0.3%p per level")
	var hans := GameData.hero("hans")
	var st := GameData.hero_stats(hans, 1, 0)
	check(st == {"hp": 396.0, "atk": 23.0} and not GameData.CONFIG_NUM_KEYS.has("lab_atk_per_level") and not GameData.BUILDING_NUM_KEYS.has("lab_atk_per_level")
		and GameData.config_num("lab_atk_per_level") == 0.0 and GameData.hero_power(hans, 1, 0) == roundi(396.0 / 10.0 + 23.0 * 2.0 / 0.8),
		"rev 24: the lab no longer raises hero attack (no lab_atk_per_level); stats and power ignore building levels: %s" % [st])
	var rig := func(): return 0.0055  # 등급 굴림 0.0055: 주점 1(SSR 0.5%)은 SR, 주점 2(0.6%)는 SSR
	check(EconomyScript.roll_gacha(1, rig)[0].grade == "SR" and EconomyScript.roll_gacha(1, rig, GameData.gacha_rates("gold", 1, 2))[0].grade == "SSR", "offline recruiting uses the tavern odds")
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
	check(EconomyScript.upgrade_block_for("keep", _lv({}), "", {"wood": 3000, "stone": 3000, "food": 1999}) == "not_enough" and EconomyScript.upgrade_block_for("keep", _lv({}), "", {"wood": 3000, "stone": 3000, "food": 2000}) == "", "keep 1 -> 2 needs gate/barracks >= 1 and 3000/3000/2000")
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
	check(e.levels.size() == 11 and e.building_level("keep") == 1 and e.build.is_empty() and e.population() == 6 and e.upgrade_cost("keep") == {"wood": 3000, "stone": 3000, "food": 2000} and e.upgrade_sec("keep") == 60,
		"new game: 11 buildings at level 1, builder idle, population 6")
	check(e.requirements("keep") == [{"id": "gate", "need": 1, "have": 1, "ok": true}, {"id": "barracks", "need": 1, "have": 1, "ok": true}]
		and e.requirements("lumber") == [{"id": "keep", "need": 2, "have": 1, "ok": false}], "requirements: keep cap first, then req1/req2 at target - 1: %s" % [e.requirements("lumber")])
	check(not e.upgrade("lumber", now) and notes == [EconomyScript.BLOCK_TEXT.keep_cap] and e.upgrade_block("keep", now) == "not_enough", "blocked upgrades only show the reason")
	e.res = {"wood": 10000, "stone": 10000, "food": 10000}
	check(e.upgrade("keep", now) and e.res == {"wood": 7000, "stone": 7000, "food": 8000} and e.build == {"id": "keep", "finish": now + 60.0} and started == [["keep", now + 60.0]],
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
	# 자원 건물: 시작할 때 자동 수집(남은 초 유지) — 쌓인 200으로 모자란 목재를 채운다
	e.res = {"wood": 400, "stone": 800, "food": 400}
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
	e.levels.keep = 9
	check(gs.hero_count() == 8 and gs.deploy().size() == 8, "keep 9: 8 slots")
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
	check(GameData.errors == 0 and GameData.build_cost("gate", 1).stone == 2500, "default tables restored")


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
	_legacy_training()
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
	check(EconomyScript.train_cost("infantry", 8) == {"food": 2400, "wood": 1600} and EconomyScript.train_cost("archer", 3) == {"food": 750, "wood": 900}
		and EconomyScript.train_cost("cavalry", 1) == {"food": 400, "stone": 200} and EconomyScript.train_cost("knight", 1).is_empty(), "train cost = unit cost x n (food:300|wood:200 ...)")
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
	e.res = {"wood": 10000, "stone": 10000, "food": 10000}
	var t0: float = e.time_now()
	check(e.start_training("barracks", 8) and e.res == {"wood": 8400, "stone": 10000, "food": 7600} and e.training("barracks").count == 8
		and absf(e.training("barracks").finish - (t0 + 8 * 10800.0)) < 2.0 and not e.training("barracks").ready and changes[0] == 1,
		"start: 8 infantry take food 2400 / wood 1600 at once, finish = now + 8 x 3 h, training_changed")
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
	# 보급술 Lv 1(-2%)로 비용을 홀수로 만든다 — 10배 비용(750/900)은 절반이 딱 떨어져 내림을 못 본다
	e.research_levels = {"logistics": 1}
	check(e.start_training("archery", 3) and e.res == {"wood": 7518, "stone": 10000, "food": 6865} and e.cancel_training("archery")
		and e.res == {"wood": 7959, "stone": 10000, "food": 7232} and e.train_queues.is_empty() and notes[-1] == EconomyScript.CANCEL_TEXT,
		"cancel: 3 archers with logistics Lv 1 (food 735 / wood 882) refund half rounded down (367 / 441) and empty the queue")
	e.research_levels = {}
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
	check(int(raw7.version) == EconomyScript.SAVE_VERSION and EconomyScript.SAVE_VERSION >= 10 and e7.train_queues.archery.tier == 1 and e7.train_queues.keys() == ["archery"] and e7.train_queues.archery.count == 2
		and absf(e7.train_queues.archery.finish - e.train_queues.archery.finish) < 0.01 and e7.soldiers == e.soldiers and not raw7.last_collect.has("archery"),
		"save v10 round-trips the training queue (with tier) and keeps no production clocks: %s" % [e7.train_queues])
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
	_legacy_training()
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
	GameData.load_tables()  # 실제 설정(훈련 1마리씩)으로 되돌린다
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


## 개정 14 §3 FEVER 상태: 게이지(방치 처치만, 2000에서 가득, FEVER 중 안 참), 시작 조건, 스폰 배율, 저장.
func test_fever() -> void:
	GameData.load_tables()
	var f = preload("res://scripts/fever.gd").new()
	f.save_path = ""
	check(f.kills_needed() == 2000 and GameData.config_num("fever_sec") == 180.0 and GameData.config_num("fever_spawn_mult") == 3.0, "fever config keys")
	for i in 50:
		f.add_kill(false)  # 스테이지 모드 처치는 세지 않는다
	check(f.gauge == 0, "stage-mode kills do not charge the gauge")
	for i in 1999:
		f.add_kill(true)
	check(f.gauge == 1999 and not f.full() and not f.start() and f.mult() == 1.0, "1999 idle kills: not full, cannot start, spawn mult 1")
	f.add_kill(true)
	f.add_kill(true)
	check(f.gauge == 2000 and f.full() and f.ratio() == 1.0, "2000 idle kills fill the gauge (and stay at 2000)")
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
		_write(cp, csv.replace("keep_slot_tiers,1:4|9:8|22:12", "keep_slot_tiers," + entry[1]).replace("keep_interior_tiers,1:20|9:28|22:36", "keep_interior_tiers," + entry[2]))
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
	check(GameData.errors == 0 and GameData.hero_slots(22) == 12, "default tables restored after the keep tier test")


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


## 개정 17 §1·§2: 스킬 해금 함수(등급·★별 쓰는 스킬), 표 22행 × 칸 수(SSR·SR 3, R 2), 잠긴 스킬은 전투 수식에 안 들어간다.
func test_skill_unlock() -> void:
	const Skills := preload("res://scripts/skills.gd")
	GameData.load_tables()
	check(range(3).map(func(i): return GameData.skill_unlock_star(i)) == [0, 3, 5], "unlock stars: skill1 0, skill2 3, skill3 5")
	var se := GameData.hero("seraphine")
	var by_star := range(6).map(func(p): return GameData.active_skills(se, p).keys())
	check(by_star == [["frost_nova"], ["frost_nova"], ["frost_nova"], ["frost_nova", "slow"], ["frost_nova", "slow"], ["frost_nova", "slow", "frost_chain"]], "SSR seraphine: frost_nova, +slow at 3, +frost_chain at 5: %s" % [by_star])
	var hans := GameData.hero("hans")
	check(GameData.active_skills(hans, 0).keys() == ["drain_slash"] and GameData.active_skills(hans, 3).keys() == ["drain_slash", "dmg_reduce"]
		and GameData.active_skills(hans, 5).size() == 2, "R hans: skill2 at 3, nothing more at 5")
	check(GameData.active_skills(se, 5) == se.skills and GameData.active_skills({}, 5).is_empty(), "everything unlocked at 5 equals the table; no skills -> empty")
	var counts := {"SSR": 0, "SR": 0, "R": 0}
	for h in GameData.heroes():
		counts[h.grade] += 1
		check(h.skills.size() == GameData.GRADE_SKILLS[h.grade], "hero %s (%s) has %d skills" % [h.id, h.grade, h.skills.size()])
	check(GameData.heroes().size() == 36 and counts == {"SSR": 16, "SR": 12, "R": 8}, "36 rows: 16 SSR, 12 SR, 8 R")
	# 잠긴 스킬은 전투 수식에 안 들어간다(능력치는 승급 배율만)
	var kyle := GameData.hero("kyle")
	check(is_equal_approx(Skills.damage(GameData.active_skills(kyle, 0), 61.0, 0.0, 0.2, false), 61.0)
		and is_equal_approx(Skills.damage(GameData.active_skills(kyle, 3), 61.0, 0.0, 0.2, false), 61.0 * 2.0), "kyle: execute (skill2) only adds damage from 3")
	var felix := GameData.hero("felix")
	check(GameData.active_skills(felix, 0).has("spear_throw") and not Skills.stuns(GameData.active_skills(felix, 2), 4) and Skills.stuns(GameData.active_skills(felix, 3), 4),
		"felix: spear_throw (skill1) from 0, stun (skill2) only from 3")
	var jack := GameData.hero("jack")
	check(Skills.incoming(GameData.active_skills(jack, 0), 100.0, 0.0) == Vector2(100.0, 0.0) and Skills.incoming(GameData.active_skills(jack, 3), 100.0, 0.0) == Vector2.ZERO
		and GameData.active_skills(jack, 0).has("cheap_shot"), "jack: cheap_shot (skill1) at 0, dodge (skill2) only from 3")
	var ig := GameData.hero("ignis")
	check(Skills.interval(GameData.active_skills(ig, 2), 1.2, 1.0) == 1.2 and is_equal_approx(Skills.interval(GameData.active_skills(ig, 3), 1.2, 1.0), 1.2 / 1.25),
		"ignis: haste (skill2) only from 3")
	check(GameData.hero_stats(ig, 1, 3).hp == float(ig.hp) * GameData.promote_mult(3), "stats do not depend on unlocked skills")
	check(Skills.name_of("poison", "ignis") == "화상" and Skills.name_of("poison", "mira") == "독" and Skills.name_of("aoe_blast") == "폭발", "per-hero skill names (ignis poison = 화상)")
	check(GameData.fx_shake(), "fx_shake is on by default")
	GameData._config.fx_shake = "0"
	check(not GameData.fx_shake(), "fx_shake 0 turns the camera shake off")
	GameData._config.erase("fx_shake")
	check(GameData.fx_shake(), "a missing fx_shake means on")
	GameData.load_tables()


## 개정 17 앱 검증(CSV·apply_remote): 등급별 스킬 수(SSR·SR 3, R 2, skill1부터 빈틈없이), 해금 설정 0..5 정수·오름차순.
func test_skill_unlock_validation() -> void:
	var logged := _errors.count
	GameData.load_tables()
	var before := _tables_hash()
	for what in ["SR hero without skill3", "R hero with a third skill", "skill2 empty but skill3 set", "unlock star above max",
			"unlock star not an integer", "unlock stars descending", "unlock key missing"]:
		var q := _payload()
		_corrupt_r17(q, what)
		check(not GameData.apply_remote(q) and GameData.errors == 1, "apply_remote rejects: %s (errors %d)" % [what, GameData.errors])
		check(_tables_hash() == before, "tables unchanged after: %s" % what)
	var q := _payload()
	q.config.skill2_unlock_star = "0"
	q.config.skill3_unlock_star = "0"
	check(GameData.apply_remote(q) and GameData.active_skills(GameData.hero("seraphine"), 0).size() == 3, "unlock stars 0 open every skill at once")
	# CSV: 같은 규칙(SR 브론의 셋째 칸을 비운다)
	var hp := "user://t_heroes.csv"
	var csv := FileAccess.get_file_as_string(GameData.HEROES_PATH)
	check(csv.contains(",taunt,10,5,3,stoneskin,25,,,"), "precondition: bron's row has taunt then stoneskin")
	_write(hp, csv.replace(",taunt,10,5,3,stoneskin,25,,,", ",taunt,10,5,3,,,,,"))
	GameData.load_tables(GameData.MONSTERS_PATH, GameData.STAGES_PATH, hp)
	check(GameData.errors == 1, "CSV: an SR row with two skills is one error (got %d)" % GameData.errors)
	DirAccess.remove_absolute(hp)
	_errors.count = logged
	GameData.load_tables()
	check(GameData.errors == 0, "default tables restored after unlock validation")


func _corrupt_r17(q: Dictionary, what: String) -> void:
	match what:
		"SR hero without skill3": q.heroes[10].skill3 = null  # 브론
		"R hero with a third skill":  # 한스
			q.heroes[17].skill3 = "haste"
			q.heroes[17].s3a = 10
		"skill2 empty but skill3 set": q.heroes[0].skill2 = ""
		"unlock star above max": q.config.skill3_unlock_star = "6"
		"unlock star not an integer": q.config.skill2_unlock_star = "2.5"
		"unlock stars descending":
			q.config.skill2_unlock_star = "5"
			q.config.skill3_unlock_star = "4"
		"unlock key missing": q.config.erase("skill2_unlock_star")


## 영웅·몬스터 그림 방식: 로우폴리 재질 → 같은 알베도의 카툰 재질(공유, Art.toon_outlines면 next_pass = 같은 알베도의 외곽선)·실사풍 재질(공유, 외곽선 없음),
## 다른 재질은 그대로. 기본은 카툰(아트 방향 문서). 카툰으로 꾸민 모델(UnitModel.dress)의 표면은 모두 카툰 재질.
func test_toon_materials() -> void:
	const Art := preload("res://scripts/art.gd")
	const UnitModelScript := preload("res://scripts/unit_model.gd")
	var vc := Art.lowpoly_vc_material()
	var t := Art.toon_material(vc) as ShaderMaterial
	check(t != null and t.shader == Art.TOON_SHADER and t.next_pass == null and Art.toon_material(vc) == t
		and t.get_shader_parameter("use_vertex_color") == true, "toon material: toon shader, no outline by default, cached, keeps the albedo inputs")
	Art.toon_outlines = true
	var ol := Art.toon_material(Art.lowpoly_material(StandardMaterial3D.new())).next_pass as ShaderMaterial
	Art.toon_outlines = false
	check(ol != null and ol.shader == Art.TOON_OUTLINE_SHADER, "toon material: with toon_outlines on, an outline pass tinted by the same albedo")
	var plain := StandardMaterial3D.new()
	check(Art.toon_material(plain) == plain and Art.toon_material(t) == t, "toon material: non-low-poly materials stay as they are")
	var r := Art.real_material(vc) as ShaderMaterial
	check(r != null and r.shader == Art.REAL_SHADER and r.next_pass == null and Art.real_material(vc) == r and Art.real_material(plain) == plain,
		"real material: realistic shader, no outline, cached; non-low-poly materials stay")
	check(Art.unit_style == "toon" and Art.style_material(vc) == t, "units are drawn in the toon style by default (docs/art-direction.md)")
	GameData.load_tables()
	var keep_style := Art.unit_style
	Art.unit_style = "toon"
	var spec := Art.hero_spec(GameData.hero("arteon"))
	var model: Node3D = Art.instance(spec.scene)
	UnitModelScript.dress(model, spec)
	Art.unit_style = keep_style
	var all_toon := true
	var n := 0
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if not mi.visible or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i) as ShaderMaterial
			n += 1
			all_toon = all_toon and m != null and (m.shader == Art.TOON_SHADER or m.shader == Art.TOON_DOUBLE_SHADER) and m.next_pass == null
	check(n > 0 and all_toon, "a dressed hero draws every surface with the toon shader and no outline (%d surfaces)" % n)
	model.free()


## 개정 17 이펙트 메시: 새 종류마다 한 면, 가산 재질 하나(공유), atk_aura 고리는 늘 있는 노드(상한 밖).
func test_fx_r17_meshes() -> void:
	const Fx := preload("res://scripts/fx.gd")
	for kind in ["flash", "shock", "shard", "cross", "hammer", "star", "slash", "glow_ring", "aura", "tail", "rays", "pillar", "motes", "burst", "crescent"]:
		var m: Mesh = Fx._mesh(kind, Color.RED)
		check(m != null and m.get_surface_count() == 1, "fx mesh %s builds" % kind)
	var g := Fx.glow_material()
	check(g == Fx.glow_material() and g.shader == Fx.AddShader and Fx.soft_material().shader == Fx.SoftShader, "one shared additive material, one shared soft material")
	for kind in ["p_spark", "p_mote", "p_ember", "p_flake", "p_smoke", "p_chunk", "flames"]:
		var pm: Mesh = Fx._mesh(kind)
		check(pm != null and pm.get_surface_count() == 1, "fx particle/flame mesh %s builds" % kind)
	var live := Fx.live()
	var ring := Fx.aura_ring()
	check(Fx.live() == live and ring.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and ring.material_override == Fx.material(), "aura ring: not counted, no shadow, shared material")
	ring.free()


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


## 개정 21 §2 병사 역할 자리(순수 함수): 궁병 성벽 자리(영웅 성벽 자리·계단 착지점과 안 겹침), 보병 성문 앞 줄(영웅 성문 앞 1.5 m보다 바깥)·
## 부서진 성문 안쪽 막는 줄(성문 폭 안), 기병 순찰 점·고리 경로(성 안에 안 들어감), 광장 → 역할 자리 등장 경로(건물 부지를 안 지남),
## 역할 배정(병종마다 티어 높은 순 북·동·남·서 차례).
func test_soldier_posts() -> void:
	const SC := preload("res://scripts/soldier_command.gd")
	var half := GameData.interior_half(1)
	var offs: Array = FormationScript.soldier_wall_offsets(half)
	check(offs == [2.5, -2.5, 6.0, -6.0, 10.0, -10.0, 13.0, -13.0, 16.5, -16.5], "soldier wall offsets ±2.5 ±6 ±10 ±13 then every 3.5 m up to the corner tower: %s" % [offs])
	var wall_ok := true
	for s in 4:
		for k in offs.size() * 2:
			var p := FormationScript.soldier_wall_spot(half, s, k)
			wall_ok = wall_ok and is_equal_approx(p.y, Balance.WALL_H) and FormationScript.region(half, p) == FormationScript.REGION_WALL and FormationScript.side_of(p) == s
			for slot in Balance.WALL_TOP_SLOTS.size():
				wall_ok = wall_ok and FormationScript.flat_distance(p, FormationScript.slot_position(half, s, FormationScript.POST_WALL, slot)) >= 0.49
			for e in [-1.0, 1.0]:
				wall_ok = wall_ok and FormationScript.flat_distance(p, FormationScript.wall_landing(half, s, e)) >= 0.49
			var depth := FormationScript.SIDE_DIR[s].dot(p)
			wall_ok = wall_ok and depth > half and depth < half + Balance.WALL_T
	check(wall_ok, "archer wall spots: on the wall top (y = WALL_H) of their side, clear of the hero wall slots and the stair landings")
	var rows_ok := true
	var seen := {}
	for k in 16:
		var p := FormationScript.gate_row_spot(half, 0, k)
		seen[str(p)] = true
		var out := -p.z - (half + Balance.WALL_T)
		rows_ok = rows_ok and not FormationScript.is_inside(half, p) and out >= FormationScript.GATE_ROW_FIRST - 0.001 and out > Balance.GATE_FRONT_OFFSET
		var q := FormationScript.gate_row_spot(half, 0, k, true)
		rows_ok = rows_ok and FormationScript.is_inside(half, q) and absf(q.x) <= Balance.GATE_W / 2.0 and -q.z < half
	var r0 := [FormationScript.gate_row_spot(half, 0, 0), FormationScript.gate_row_spot(half, 0, 1), FormationScript.gate_row_spot(half, 0, 3)]
	check(rows_ok and seen.size() == 16 and r0[0].is_equal_approx(Vector3(0, 0, -(half + 5.2))) and r0[1].is_equal_approx(Vector3(-2.4, 0, -(half + 5.2)))
		and r0[2].is_equal_approx(Vector3(-1.0, 0, -(half + 6.8))),
		"infantry rows: 3.2 m row 0/-2.4/+2.4, 4.8 m row -1/+1/-3.2/+3.2 … outside the hero gate slots; a broken gate moves them to blocking rows inside the gate width: %s" % [r0])
	var r := FormationScript.patrol_radius(half)
	var pts := FormationScript.patrol_points(half, 0, 1)
	var pts2 := FormationScript.patrol_points(half, 0, -1)
	check(is_equal_approx(r, half + Balance.WALL_T + 7.0) and pts[0].is_equal_approx(Vector3(0, 0, -r)) and pts[1].is_equal_approx(Vector3(r, 0, -r)) and pts[2].is_equal_approx(Vector3(r, 0, 0))
		and pts2[2].is_equal_approx(Vector3(-r, 0, 0)), "cavalry patrol: gate front -> ring corner -> the next gate front (ring radius half + wall + 7), either direction")
	var ring_ok := true
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i in 200:
		var pair := []
		for j in 2:  # 성 밖 점: 사각 거리(max |x|, |z|)가 성벽 바깥면 + 1 ~ 고리 + 6
			var dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
			pair.append(dir / maxf(absf(dir.x), absf(dir.z)) * rng.randf_range(half + Balance.WALL_T + 1.0, r + 6.0))
		var a: Vector3 = pair[0]
		var b: Vector3 = pair[1]
		var path := FormationScript.ring_route(half, a, b)
		var prev := a
		for p in path:
			ring_ok = ring_ok and not FormationScript.crosses_castle(half, prev, p)
			prev = p
		ring_ok = ring_ok and path[-1] == b
	check(ring_ok, "ring_route never enters the castle (200 random pairs around the ring)")
	var plots := []
	for bd in Balance.BUILDINGS:
		plots.append(Rect2(Vector2(bd.cell) * Balance.TILE, Vector2(bd.size) * Balance.TILE))
	var entry_ok := true
	var units := []
	for i in 66:
		units.append({"type": "infantry", "tier": 1})
	for spot in FormationScript.soldier_spots(units):
		for post in [FormationScript.soldier_wall_spot(half, 0, 3), FormationScript.gate_row_spot(half, 1, 2), FormationScript.patrol_points(half, 3, 1)[0]]:
			var path := FormationScript.soldier_entry_route(half, spot, post)
			entry_ok = entry_ok and path[-1] == post
			var prev: Vector3 = spot
			for p in path.slice(0, 2):  # 광장 → 가운데 길 → 남문 안쪽(그 뒤는 route — 통로 고리 테스트가 본다)
				for pl in plots:
					entry_ok = entry_ok and not _segment_hits(pl, prev, p)
				prev = p
	check(entry_ok, "entry route: plaza spot -> middle road -> south gate inside -> route(); the plaza legs cross no building plot and end at the post")
	var posts: Array = SC.assign_posts([{"type": "infantry", "tier": 1}, {"type": "infantry", "tier": 3}, {"type": "archer", "tier": 1}, {"type": "infantry", "tier": 2},
		{"type": "infantry", "tier": 1}, {"type": "infantry", "tier": 1}, {"type": "cavalry", "tier": 1}])
	var want := [{"side": 2, "slot": 0}, {"side": 0, "slot": 0}, {"side": 0, "slot": 0}, {"side": 1, "slot": 0}, {"side": 3, "slot": 0}, {"side": 0, "slot": 1}, {"side": 0, "slot": 0}]
	check(posts == want, "assign_posts: per type, highest tier first, round robin N/E/S/W: %s" % [posts])


## 수평 선분 a→b가 직사각형 r(x, z)을 지나는가(0.1 m 간격 샘플).
func _segment_hits(r: Rect2, a: Vector3, b: Vector3) -> bool:
	var n := maxi(1, ceili(FormationScript.flat_distance(a, b) / 0.1))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		if r.has_point(Vector2(p.x, p.z)):
			return true
	return false


## 개정 21 §3 전술 지휘관(순수 함수): 위협(반경·성문 배율·부서짐 × 2.5, 몬스터마다 면 하나), 방어력, 심각(두 조건·잔챙이 무시), 필요량,
## 후보 선택(기병 먼저·가까운 순·필요량을 넘으면 멈춤 = 최소 집합), 보내는 면 보호(위협 × 1.2·보병 1명), 흔들림 방지(4초), 복귀(3초 조용·자기 면 심각).
func test_soldier_command() -> void:
	const SC := preload("res://scripts/soldier_command.gd")
	var half := GameData.interior_half(1)
	var gt := FormationScript.gate_target(half, 0)
	var ms := [{"pos": gt + Vector3(0, 0, -3), "power": 1000.0}, {"pos": gt + Vector3(0, 0, -20), "power": 500.0},
		{"pos": FormationScript.gate_inner(half, 1) + Vector3(-2, 0, 1), "power": 300.0}, {"pos": Vector3(0, 0, 0), "power": 700.0}]
	var t: Array = SC.threats(half, ms, [1.0, 1.0, 1.0, 1.0])
	check(t == [1000.0, 300.0, 0.0, 0.0], "threat: monsters within 14 m outside the gate or 8 m inside the passage count for that side only; far ones do not: %s" % [t])
	t = SC.threats(half, ms, [0.5, 0.0, 1.0, 1.0])
	check(is_equal_approx(t[0], 1750.0) and is_equal_approx(t[1], 750.0), "threat x (1 + 1.5 x (1 - gate ratio)): half gate x1.75, broken gate x2.5: %s" % [t])
	check(SC.power(320.0, 22.0, 1.0) == 7040.0 and SC.defenses([{"side": 0, "power": 5.0}, {"side": 2, "power": 3.0}, {"side": 0, "power": 1.0}]) == [6.0, 0.0, 3.0, 0.0],
		"power = HP x damage per second; defense sums per side")
	check(SC.severe(3000.0, 2000.0, 1.0, 0.0) and not SC.severe(2500.0, 2000.0, 1.0, 0.0) and not SC.severe(1900.0, 0.0, 1.0, 0.0)
		and SC.severe(0.0, 9999.0, 0.4, 0.2) and not SC.severe(0.0, 9999.0, 0.4, 0.1) and not SC.severe(0.0, 9999.0, 0.5, 0.3),
		"severe: threat > defense x 1.3 above min_threat, or gate < 45% after losing > 15% in 5 s")
	check(is_equal_approx(SC.need(10000.0, 4000.0), 7000.0) and SC.calm_next([2.5, 1.0, -1.0, 0.0], [0.0, 600.0, 0.0, 0.0], [100.0, 1000.0, 100.0, 0.0], 1.0) == [3.5, -1.0, 0.0, -1.0],
		"need = threat x 1.1 - defense; calm time (-1 = not calm) starts at 0 and grows only while threat < defense x 0.5")
	# 후보 선택: 기병 셋(가까운 순) → 그다음 가까운 보병. 필요량을 넘는 순간 멈춘다. 지원받는 면(0)은 내주지 않는다
	var cands := [{"id": "c2", "type": "cavalry", "side": 2, "power": 4800.0, "dist": 30.0, "prio": 0}, {"id": "c1", "type": "cavalry", "side": 1, "power": 4800.0, "dist": 10.0, "prio": 0},
		{"id": "c3", "type": "cavalry", "side": 3, "power": 4800.0, "dist": 20.0, "prio": 0}, {"id": "i1", "type": "infantry", "side": 1, "power": 7040.0, "dist": 12.0, "prio": 1},
		{"id": "i3", "type": "infantry", "side": 3, "power": 7040.0, "dist": 11.0, "prio": 1}, {"id": "i2", "type": "infantry", "side": 2, "power": 7040.0, "dist": 40.0, "prio": 1},
		{"id": "n0", "type": "cavalry", "side": 0, "power": 4800.0, "dist": 0.0, "prio": 0}]
	var left := [0.0, 20000.0, 20000.0, 20000.0]
	var inf := [2, 2, 2, 2]
	var got: Array = SC.pick(20000.0, 0, cands, [0.0, 0.0, 0.0, 0.0], left, inf)
	check(got == ["c1", "c3", "c2", "i3"] and left == [0.0, 15200.0, 15200.0, 8160.0] and inf == [2, 2, 2, 1],
		"pick: cavalry first (nearest first), then the nearest infantry, stop once the need is met (minimal set; the target side never donates): %s" % [got])
	left = [0.0, 6000.0, 20000.0, 20000.0]
	inf = [2, 1, 2, 2]
	got = SC.pick(30000.0, 0, cands, [0.0, 4000.0, 0.0, 0.0], left, inf)
	check(got == ["c3", "c2", "i3", "i2"] and inf == [2, 1, 1, 1],
		"pick floors: the east keeps defense >= its threat x 1.2 (no cavalry) and its only infantry; others give one infantry each: %s" % [got])
	# plan: 북에 큰 위협 — 다른 면 기병 셋 + 보병은 가까운 순(동·서 다음 남 — 면마다 1명은 남긴다). 궁병은 안 간다. 다음 판단은 더 보내지 않는다
	var sol := _command_units(half)
	var snap := {"half": half, "now": 100.0, "dt": 1.0, "calm": [0.0, 0.0, 0.0, 0.0], "monsters": [{"pos": gt, "power": 48000.0}], "ratio": [1.0, 1.0, 1.0, 1.0],
		"drop": [0.0, 0.0, 0.0, 0.0], "heroes": [], "soldiers": sol}
	var p: Dictionary = SC.plan(snap)
	var sent: Array = p.send.map(func(e): return e[0])
	var powers: Array = sent.map(func(id): return 4800.0 if id.begins_with("c") else 7040.0)
	var total: float = powers.reduce(func(a, b): return a + b, 0.0)
	var need0: float = 48000.0 * 1.1 - (2 * 7040.0 + 4800.0 + 2700.0)
	var inf_order: Array = sent.filter(func(id): return id.begins_with("i")).map(func(id): return int(id[1]))
	check(p.severe == [true, false, false, false] and sent.size() == 6 and sent.slice(0, 3).all(func(id): return id.begins_with("c")) and not sent.has("c0"),
		"plan: a mass at the north gate makes it severe; the three other cavalry go first: %s" % [sent])
	check(inf_order.size() == 3 and inf_order[2] == 2 and inf_order.slice(0, 2).all(func(s): return s == 1 or s == 3) and total >= need0 and total - powers[-1] < need0
		and p.send.all(func(e): return e[1] == 0),
		"plan: then infantry nearest first (east, west, then south — the floor keeps the second east/west one home) until the need %.0f is met — sent %.0f, without the last %.0f (minimal)"
		% [need0, total, total - powers[-1]])
	var home_inf := [0, 0, 0, 0]
	for u in sol:
		if u.type == "infantry" and not sent.has(u.id):
			home_inf[u.side] += 1
	check(home_inf.all(func(n): return n >= 1) and not sent.any(func(id): return id.begins_with("a")), "plan: every side keeps at least one infantry; archers never go: %s" % [home_inf])
	for u in sol:
		if sent.has(u.id):
			u.at = 0
			u.last = 100.0
	snap.now = 101.0
	p = SC.plan(snap)
	check(p.send.is_empty() and p.recall.is_empty() and p.need[0] <= 0.0, "plan: next tick the sent units count for the north; nothing more goes (need %.0f)" % p.need[0])
	# 복귀: 지원 면이 3초 넘게 조용해야, 그리고 배정 4초 뒤에만
	snap.monsters = []
	snap.calm = [5.0, 0.0, 0.0, 0.0]
	snap.now = 102.0
	p = SC.plan(snap)
	check(p.recall.is_empty() and p.calm[0] == 6.0, "anti-flap: units ordered 2 s ago do not return yet even though the north is calm: %s" % [p.recall])
	snap.now = 104.5
	snap.calm = [1.0, 0.0, 0.0, 0.0]
	p = SC.plan(snap)
	check(p.recall.is_empty(), "return waits for 3 s of calm (calm 2 s): %s" % [p.recall])
	snap.calm = [2.5, 0.0, 0.0, 0.0]
	p = SC.plan(snap)
	var back: Array = p.recall.duplicate()
	back.sort()
	var want_back: Array = sent.duplicate()
	want_back.sort()
	check(back == want_back, "after 3 s of calm (4 s past the order) every reinforcement returns home: %s" % [back])
	# 자기 면이 심각해지면 그 면 출신만 돌아간다
	snap.calm = [0.0, 0.0, 0.0, 0.0]
	snap.monsters = [{"pos": gt, "power": 30000.0}, {"pos": FormationScript.gate_target(half, 1), "power": 60000.0}]
	p = SC.plan(snap)
	var east: Array = sent.filter(func(id): return id[1] == "1")
	var east_back: Array = p.recall.duplicate()
	east_back.sort()
	east.sort()
	check(east.size() == 2 and east_back == east, "a reinforcement goes home when its own side (east) turns severe; the others stay: %s" % [p.recall])
	# 흔들림 방지: 2초 전에 배정된 병사는 후보가 아니다
	sol = _command_units(half)
	sol[6].last = 98.0  # 동 기병 c1(면마다 i0·i1·c·a 순)
	snap = {"half": half, "now": 100.0, "dt": 1.0, "calm": [0.0, 0.0, 0.0, 0.0], "monsters": [{"pos": gt, "power": 40000.0}], "ratio": [1.0, 1.0, 1.0, 1.0],
		"drop": [0.0, 0.0, 0.0, 0.0], "heroes": [], "soldiers": sol}
	sent = SC.plan(snap).send.map(func(e): return e[0])
	check(sol[6].id == "c1" and not sent.has("c1") and sent.has("c3"), "anti-flap: a unit ordered 2 s ago is not picked again: %s" % [sent])


## 지휘관 시험 병사: 면마다 보병 2(i<면><칸>)·기병 1(c<면>)·궁병 1(a<면>), 모두 자기 자리.
func _command_units(half: float) -> Array:
	var sol := []
	for s in 4:
		for k in 2:
			sol.append({"id": "i%d%d" % [s, k], "type": "infantry", "side": s, "at": s, "power": 7040.0, "pos": FormationScript.gate_row_spot(half, s, k), "last": -INF, "engaged": false})
		sol.append({"id": "c%d" % s, "type": "cavalry", "side": s, "at": s, "power": 4800.0, "pos": FormationScript.patrol_points(half, s, 1)[0], "last": -INF, "engaged": false})
		sol.append({"id": "a%d" % s, "type": "archer", "side": s, "at": s, "power": 2700.0, "pos": FormationScript.soldier_wall_spot(half, s, 0), "last": -INF, "engaged": false})
	return sol


## 개정 19: 막사 레벨이 훈련 티어·시간을 정하고 비용은 티어마다 ×5, 진행 중 묶음은 시작 티어·시각 고정.
func test_training_tiers() -> void:
	_legacy_training()
	var want := [[1, 1, 180], [2, 1, 150], [6, 1, 30], [7, 2, 180], [12, 2, 30], [13, 3, 180], [19, 4, 180], [25, 5, 180], [30, 5, 30], [31, 5, 30]]
	var table_ok := true
	for w in want:
		table_ok = table_ok and GameData.train_tier(w[0]) == w[1] and GameData.soldier_unit_sec(w[0]) == w[2] * 60.0
	check(table_ok, "tier/time table: Lv 1,2,6,7,12,13,19,25,30,31 -> T1 3:00, T1 2:30, T1 0:30, T2 3:00, T2 0:30, T3 3:00, T4, T5 3:00, T5 0:30, T5 0:30")
	check(EconomyScript.train_cost("infantry", 2) == {"food": 600, "wood": 400} and EconomyScript.train_cost("infantry", 2, 2) == {"food": 3000, "wood": 2000}
		and EconomyScript.train_cost("infantry", 1, 3) == {"food": 7500, "wood": 5000}, "cost x 5^(tier-1): T2 x5, T3 x25")
	var now := 1.8e9
	var e = _econ(now)
	e.res = {"wood": 100000, "stone": 100000, "food": 100000}
	e.levels.barracks = 7
	var t0: float = e.time_now()
	check(e.train_tier("barracks") == 2 and e.start_training("barracks", 2) and e.res.food == 100000 - 3000 and e.res.wood == 100000 - 2000
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
	check(e.cancel_training("barracks") and e.res.food == before.food + 1500 and e.res.wood == before.wood + 1000, "cancel refunds half of the batch tier's cost")
	e.free()


## 성장(개정 20 §2) 표·비용·효과: 서버 upgrades.test.ts와 같은 숫자.
	GameData.load_tables()  # 실제 설정(훈련 1마리씩)으로 되돌린다
func test_upgrade_tables() -> void:
	GameData.load_tables()
	check(GameData.errors == 0 and GameData.upgrades().map(func(u): return u.id) == ["atk", "hp", "aspd", "mspd", "crit_rate", "crit_dmg"], "upgrades.csv loads in file order")
	var a := GameData.upgrade_def("aspd")
	check(a.name == "공격속도" and a.unit == "pct" and a.per_level == 0.25 and a.max_level == 100.0 and a.cost_base == 5000.0 and is_equal_approx(a.cost_growth, 1.07), "aspd row")
	check(GameData.upgrade_def("nope").is_empty() and GameData.upgrade_cost("nope", 3) == 0, "unknown upgrade is empty / cost 0")
	# 비용 = round(base × growth^L), L은 현재 레벨(0부터)
	check(GameData.upgrade_cost("atk", 0) == 1000 and GameData.upgrade_cost("atk", 1) == 1050 and GameData.upgrade_cost("atk", 2) == 1103, "atk costs 1000 / 1050 / 1103")
	check(GameData.upgrade_cost("aspd", 0) == 5000 and GameData.upgrade_cost("aspd", 1) == 5350 and GameData.upgrade_cost("crit_rate", 0) == 6000 and GameData.upgrade_cost("mspd", 0) == 4000, "first-level costs 5000 / 5350 / 6000 / 4000")
	var c49 := GameData.upgrade_cost("atk", 49)
	check(c49 == roundi(1000.0 * pow(1.05, 49)) and c49 > 10000 and c49 < 12000, "atk level 50 costs about 11k (%d)" % c49)
	check(GameData.upgrade_cost("atk", 199) > 15000000 and GameData.upgrade_cost("atk", 199) < 17000000, "atk level 200 costs about 16m")
	# 효과: 분수. 레벨은 0..max로 자른다
	var b0 := GameData.upgrade_bonus({})
	check(b0 == {"atk_pct": 0.0, "hp_pct": 0.0, "aspd_pct": 0.0, "mspd_pct": 0.0, "crit_rate": 0.0, "crit_dmg": 0.0}, "no upgrades = no bonus")
	var b := GameData.upgrade_bonus({"atk": 23, "hp": 200, "aspd": 100, "mspd": 80, "crit_rate": 100, "crit_dmg": 100})
	check(is_equal_approx(b.atk_pct, 0.115) and is_equal_approx(b.hp_pct, 1.0) and is_equal_approx(b.aspd_pct, 0.25) and is_equal_approx(b.mspd_pct, 0.2) \
		and is_equal_approx(b.crit_rate, 0.1) and is_equal_approx(b.crit_dmg, 0.5), "max levels give +100% / +100% / +25% / +20% / +10%p / +50%p, atk 23 = +11.5%")
	var over := GameData.upgrade_bonus({"atk": 9999, "crit_dmg": -5, "ghost": 7})
	check(is_equal_approx(over.atk_pct, 1.0) and over.crit_dmg == 0.0 and over.size() == 6, "levels clamp to 0..max, unknown ids are ignored")


## 치명타 결합(개정 20 §3): 굴림은 한 번, 확률·배율을 더한다.
func test_crit_roll_params() -> void:
	var none := GameData.upgrade_bonus({})
	var r := GameData.crit_roll_params(0.0, 0.0, none)
	check(r.rate == 0.0 and r.mult == 1.5, "no skill, no growth: never crits, base mult 1.5")
	var grown := GameData.upgrade_bonus({"crit_rate": 50, "crit_dmg": 40})
	r = GameData.crit_roll_params(0.0, 0.0, grown)
	check(is_equal_approx(r.rate, 0.05) and is_equal_approx(r.mult, 1.7), "no skill + growth: rate = crit_rate, mult = 1.5 + crit_dmg")
	r = GameData.crit_roll_params(0.25, 2.0, grown)
	check(is_equal_approx(r.rate, 0.30) and is_equal_approx(r.mult, 2.2), "skill + growth: rates add, mult = skill mult + crit_dmg (one roll)")
	r = GameData.crit_roll_params(0.25, 2.0, none)
	check(is_equal_approx(r.rate, 0.25) and r.mult == 2.0, "skill alone is unchanged")
	r = GameData.crit_roll_params(0.95, 2.0, GameData.upgrade_bonus({"crit_rate": 100}))
	check(r.rate == 1.0, "rate is capped at 1")
	r = GameData.crit_roll_params(0.25, 0.0, grown)
	check(is_equal_approx(r.rate, 0.05), "a skill rate without a skill mult is not a skill")


## 온라인 흉내: send를 기록만 한다.
class GrowthNet extends RefCounted:
	var up := true
	var last_error := ""
	var sent: Array = []
	var refreshed := 0
	func flush_kills() -> void:
		pass
	func send(method: String, path: String, body = null, done := Callable(), fail := Callable(), _auth := true, once := false) -> void:
		sent.append({"method": method, "path": path, "body": body, "done": done, "fail": fail, "once": once})
	func refresh() -> void:
		refreshed += 1


## 성장 Economy: 오프라인 강화(골드 합계·최대·부족·저장), 온라인(한 번 보내고 재전송 없음·응답 대기), apply_server, 저장 복원.
func test_growth_economy() -> void:
	GameData.load_tables()
	var e = _econ(1.8e9)
	var notes: Array = []
	e.notice.connect(func(t): notes.append(t))
	var sig := [0]
	e.upgrades_changed.connect(func(): sig[0] += 1)
	e.gold = 50000
	check(e.upgrade_level("atk") == 0 and e.upgrade_total_cost("atk", 3) == 1000 + 1050 + 1103 and e.upgrade_total_cost("atk", 0) == 0, "total cost sums the next n levels")
	check(e.upgrade_count_affordable("atk", 10) == 10 and e.upgrade_count_affordable("atk", 3) == 3, "affordable is capped by max_n")
	e.gold = 3152
	check(e.upgrade_count_affordable("atk", 10) == 2 and e.upgrade_count_affordable("aspd", 10) == 0, "affordable stops where the summed cost passes gold")
	e.gold = 100000
	check(e.growth_up("atk", 3) and e.upgrade_level("atk") == 3 and e.gold_tenths == (100000 - 3153) * 10 and sig[0] == 1, "offline upgrade x3 takes the summed gold and signals")
	check(is_equal_approx(e.upgrade_bonus().atk_pct, 3 * 0.5 / 100.0), "upgrade_bonus reads the state")
	e.gold = 10
	check(not e.growth_up("atk", 1) and notes == ["골드 부족"] and e.upgrade_level("atk") == 3 and e.gold_tenths == 100, "short on gold: no change, notice")
	check(not e.growth_up("zzz", 1) and not e.growth_up("atk", 0) and e.upgrade_level("zzz") == 0, "unknown id / count 0 are refused")
	e.gold = 100000000
	e.upgrades["mspd"] = 79
	check(not e.growth_up("mspd", 2) and e.growth_block("mspd", 2) == "최대 레벨" and e.upgrade_level("mspd") == 79 and e.upgrade_count_affordable("mspd", 10) == 1, "over the cap is refused whole; affordable stops at max")
	check(e.growth_up("mspd", 1) and e.upgrade_level("mspd") == 80 and e.upgrade_count_affordable("mspd", 10) == 0 and e.upgrade_total_cost("mspd", 5) == 0, "max level reached")
	# 저장 복원(v10) — 사슬: v7 → v8(훈련 tier 1) → v9(성장 0) → v10(던전·장비 기본값)
	e.save_path = ECON_TMP
	e.save()
	var e2 = _econ(0.0)
	e2.save_path = ECON_TMP
	e2.load_save(1.8e9)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ECON_TMP))
	check(int(raw.version) == EconomyScript.SAVE_VERSION and e2.upgrades == {"atk": 3, "mspd": 80}, "save v10 writes and restores the upgrades")
	e2.free()
	raw.erase("upgrades")
	raw.version = 7
	raw.training = {"barracks": {"count": 2, "finish": 5.0}}
	var e3 = _econ(0.0)
	check(e3._apply(raw) and e3.upgrades.is_empty() and e3.train_queues == {"barracks": {"count": 2, "tier": 1, "finish": 5.0}},
		"v7 -> v10: the batch gets tier 1 and there are no upgrades: %s" % [e3.train_queues])
	raw.version = 8
	raw.training = {"barracks": {"count": 2, "tier": 3, "finish": 5.0}}
	check(e3._apply(raw) and e3.upgrades.is_empty() and e3.train_queues == {"barracks": {"count": 2, "tier": 3, "finish": 5.0}},
		"v8 -> v10: the batch keeps its tier and upgrades default to none: %s" % [e3.train_queues])
	raw.version = EconomyScript.SAVE_VERSION + 1
	check(not e3._apply(raw), "a save from a newer version (SAVE_VERSION + 1) is refused")
	raw.version = 9
	raw.upgrades = {"atk": 5, "ghost": 3, "hp": 0, "aspd": 9999}
	check(e3._apply(raw) and e3.upgrades == {"atk": 5, "aspd": 100}, "unknown ids and zero are dropped, levels clamp to the max")
	raw.upgrades = {"atk": "x"}
	check(not e3._apply(raw), "a malformed upgrades block is a corrupt save")
	e3.free()
	DirAccess.remove_absolute(ECON_TMP)
	e.free()
	# 온라인: 곧바로 올리고(오프라인 규칙) 한 번 보낸다(once). 응답은 서버 값으로 맞추고, 거절되면 되돌린다
	var o = _econ(1.8e9)
	var n := GrowthNet.new()
	o.net = n
	o.gold = 100000
	o.server_gold_tenths = 1000000
	var notes2: Array = []
	o.notice.connect(func(t): notes2.append(t))
	var cost2: int = o.upgrade_total_cost("hp", 2)
	check(o.growth_up("hp", 2) and not o.upgrades_waiting() and o.upgrade_level("hp") == 2 and o.gold == 100000 - cost2, "online: level and gold change at once, before the reply")
	check(n.sent.size() == 1 and n.sent[0].path == "/v1/upgrade" and n.sent[0].body == {"id": "hp", "count": 2} and n.sent[0].once, "online: one request to /v1/upgrade, sent once (never resent)")
	var reply := {"player": {"gold_tenths": 1000000 - cost2 * 10, "stage": 1, "res": {}, "buildings": {}, "upgrades": {"hp": 2, "ghost": 4}},
		"merchant": {"rates": {"wood": 1.0, "stone": 1.0, "food": 1.0}, "next_change": 3600.0}}
	var sig2 := [0]
	o.upgrades_changed.connect(func(): sig2[0] += 1)
	n.sent[0].done.call(reply)
	check(o.upgrade_level("hp") == 2 and o.upgrades == {"hp": 2} and o.gold == 100000 - cost2 and sig2[0] == 0, "the reply confirms it (unknown ids dropped); nothing jumps, no extra signal")
	check(o.apply_server(reply) and sig2[0] == 0, "the same levels again do not signal")
	check(o.growth_up("hp", 1) and n.sent.size() == 2 and o.upgrade_level("hp") == 3, "the next upgrade goes at once too")
	n.last_error = "not_enough_gold"
	n.sent[1].fail.call()
	check(o.upgrade_level("hp") == 2 and o.gold == 100000 - cost2 and notes2 == [EconomyScript.NO_GOLD_TEXT] and n.refreshed == 1, "a rejected upgrade rolls back, notifies and refreshes the state")
	n.last_error = ""
	check(o.growth_up("hp", 1) and o.upgrade_level("hp") == 3, "can retry after failure")
	n.sent[2].fail.call()
	check(notes2.size() == 2 and notes2[1] == EconomyScript.GROWTH_FAIL_TEXT and n.refreshed == 2 and o.upgrade_level("hp") == 2, "a lost reply rolls back with the generic text and refreshes")
	o.net = null
	o.free()


# --- 개정 18 던전 아트 ---

## 장비 아이콘 11종: 도형 ≥ 3(외곽선 있는 면 포함), 모든 점이 단위 박스 안, 모든 다각형이 삼각분할된다(draw_colored_polygon이 그릴 수 있다),
## 종류마다 모양이 다르다. 장비 칸: 6등급 색 순서, 외곽 8각이 단위 박스 안, 등급 테두리는 등급 색 그대로이고 LR만 시간에 따라 흐른다(이음매 없음).
func test_item_icons() -> void:
	var seen := {}
	for kind in IconsScript.ITEM_KINDS:
		var shapes: Array = IconsScript.shapes(kind)
		check(shapes.size() >= 3 and shapes.any(func(s): return s[2]), "item icon %s has shapes with an outline" % kind)
		for s in shapes:
			var pts := PackedVector2Array(s[0])
			check(pts.size() >= 3 and Geometry2D.triangulate_polygon(pts).size() >= 3, "item icon %s polygon triangulates: %s" % [kind, pts])
			for p in pts:
				check(absf(p.x) <= 0.5 and absf(p.y) <= 0.5, "item icon %s point %s inside the unit box" % [kind, p])
		var sig := str(shapes)
		check(not seen.has(sig), "item icon %s differs from %s" % [kind, seen.get(sig, "")])
		seen[sig] = kind
	check(IconsScript.ITEM_KINDS.size() == 11 and not IconsScript.KINDS.has("sword"), "11 equipment kinds; resource chip kinds stay resources")
	check(Art.ITEM_GRADE_COLORS.keys() == ["N", "R", "SR", "SSR", "UR", "LR"], "six item grades in order")
	check(IconsScript.item_tile().all(func(p): return absf(p.x) <= 0.5 and absf(p.y) <= 0.5), "item tile inside the unit box")
	var n := 33
	var sr := IconsScript.border_colors("SR", n, 0.0)
	check(sr.size() == n and sr == IconsScript.border_colors("SR", n, 5.0) and sr[0] == Art.ITEM_GRADE_COLORS.SR, "SR border = grade colour, still")
	var lr0 := IconsScript.border_colors("LR", n, 0.0)
	check(lr0 != IconsScript.border_colors("LR", n, 0.5) and lr0[0].is_equal_approx(lr0[n - 1]), "LR border flows over time and wraps seamlessly")


## 던전 무대: 평야 = 영웅 6·고블린 15·왕, 성 내부 = 영웅 4·데스나이트. 자리는 바닥에, 전투 자리 안(평야 반경 / 홀 안)에, 서로 1 m 넘게 떨어지고,
## 영웅은 모든 적보다 화면 아래. 조명 설정 키·점광원 ≤ 3(그림자 없음). 이펙트(불꽃·연기·불씨·빛기둥)는 그림자 없음, 평야 반복물은 MultiMesh.
## 드랍 상자(등급마다 메시 하나, 작음, 바닥에 놓임)·빛기둥(높이 PILLAR_H) 그림자 없음.
func test_arena_kit() -> void:
	const ArenaKit := preload("res://scripts/arena_kit.gd")
	for kind in ["plains", "castle"]:
		var st: Dictionary = ArenaKit.plains() if kind == "plains" else ArenaKit.castle()
		var want: Array = [6, 15] if kind == "plains" else [4, 0]
		check(st.heroes.size() == want[0] and st.enemies.size() == want[1] and st.boss is Vector3, "%s: %d hero spots, %d goblin spots + boss" % [kind, want[0], want[1]])
		var spots: Array = st.heroes + st.enemies + [st.boss]
		for i in spots.size():
			var p: Vector3 = spots[i]
			var hall: Vector3 = Basis(Vector3.UP, ArenaKit.HALL_YAW).inverse() * p
			var inside := p.length() < ArenaKit.PLAINS_FIGHT_R if kind == "plains" else maxf(absf(hall.x), absf(hall.z)) < ArenaKit.HALL_HALF - 1.0
			check(inside and p.y == 0.0, "%s spot %d on the floor inside the fight area: %s" % [kind, i, p])
			for j in range(i + 1, spots.size()):
				check(p.distance_to(spots[j]) > 1.0, "%s spots %d and %d apart" % [kind, i, j])
		var lowest_enemy: float = (st.enemies + [st.boss]).map(func(p): return p.dot(ArenaKit.DOWN)).max()
		check(st.heroes.all(func(p): return p.dot(ArenaKit.DOWN) > lowest_enemy + 10.0), "%s heroes start below every enemy on screen" % kind)
		var light: Dictionary = st.light
		var keys := ["background", "ambient", "ambient_energy", "sun_color", "sun_energy", "sun_rot", "shadows", "omni"]
		check(keys.all(func(k): return light.has(k)) and light.omni.size() <= 3, "%s light settings complete, <= 3 omni lights" % kind)
		var lit: Node3D = ArenaKit.lighting(light)
		var omnis := lit.find_children("*", "OmniLight3D", true, false)
		check(omnis.size() == light.omni.size() and omnis.all(func(o): return not o.shadow_enabled) and lit.find_children("*", "WorldEnvironment", true, false).size() == 1,
			"%s lighting node: environment + sun + %d shadowless omni lights" % [kind, light.omni.size()])
		lit.free()
		var effects := 0
		for gi in st.root.find_children("*", "GeometryInstance3D", true, false):
			var m: Material = gi.material_override
			if gi is CPUParticles3D or (m is ShaderMaterial and (m.shader == ArenaKit.GlowShader or m.shader == ArenaKit.SmokeShader)):
				effects += 1
				check(gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s effect %s casts no shadow" % [kind, gi.name])
		if kind == "castle":
			check(effects == 3 and st.root.find_children("*", "CPUParticles3D", true, false).size() == 1, "castle: one flame MultiMesh, one smoke MultiMesh, one ember emitter")
		else:
			check(st.root.find_children("*", "MultiMeshInstance3D", true, false).size() >= 10, "plains: hills, trees, rocks, mountains as MultiMesh")
		st.root.free()
	for g in Art.ITEM_GRADE_COLORS:
		var c: MeshInstance3D = ArenaKit.drop_chest(g)
		var box := c.mesh.get_aabb()
		var p: MeshInstance3D = ArenaKit.light_pillar(g)
		check(box.size.x <= 1.0 and box.size.y < 1.0 and absf(box.position.y) < 0.01 and c.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			and is_equal_approx(p.mesh.get_aabb().size.y, ArenaKit.PILLAR_H) and p.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"%s drop chest small on the floor, light pillar %.0f m, no shadows" % [g, ArenaKit.PILLAR_H])
		c.free()
		p.free()
	var a: MeshInstance3D = ArenaKit.drop_chest("SR")
	var b: MeshInstance3D = ArenaKit.drop_chest("SR")
	var u: MeshInstance3D = ArenaKit.drop_chest("UR")
	check(a.mesh == b.mesh and a.mesh != u.mesh, "drop chest mesh shared per grade")
	a.free()
	b.free()
	u.free()


## 던전 몬스터: 크기 0.8·1.7·2.2, UnitModel.dress 뒤 tint 메시 재질 = 원본 albedo × 색(발광 눈은 색 자체), parts는 그 뼈의 BoneAttachment3D 아래
## 코드 부품으로 붙고, 같은 (재질, 색)은 몬스터끼리 공유한다. (애니메이션·숨김 메시·사망 길이는 test_art_assets가 본다.)
func test_dungeon_monsters() -> void:
	MeshMergeScript.enabled = false  # 부위 메시를 이름으로 본다 — 합치기 전 모습(합치기는 test_mesh_merge)
	const UnitModelScript := preload("res://scripts/unit_model.gd")
	var scales := {"goblin": 0.8, "goblin_king": 1.7, "death_knight": 2.2}
	for key in scales:
		var spec: Dictionary = Art.MONSTER_MODELS[key]
		check(is_equal_approx(spec.scale, scales[key]), "%s drawn at x%.1f" % [key, scales[key]])
		var model: Node3D = Art.instance(spec.scene)
		UnitModelScript.dress(model, spec)
		for mesh_name in spec.tint:
			var mi := model.find_child(mesh_name, true, false) as MeshInstance3D
			var want: Color = spec.tint[mesh_name]
			var m: Material = mi.get_active_material(0) if mi != null else null
			var ok: bool = (m is ShaderMaterial and (m.get_shader_parameter("albedo_color") as Color).is_equal_approx(want)) \
				or (m is BaseMaterial3D and m.emission_enabled and m.albedo_color.is_equal_approx(want))
			check(ok, "%s mesh %s tinted %s" % [key, mesh_name, want])
		var attached := 0
		for ba in model.find_children("*", "BoneAttachment3D", true, false):
			var part: Node = ba.get_child(0) if ba.get_child_count() == 1 else null
			if part != null and (part.name == "DkEyes" or (part is MeshInstance3D and part.material_override == Art.style_material(Art.lowpoly_vc_material()))):
				attached += 1
				check(spec.parts.any(func(pp): return pp[0] == ba.bone_name), "%s part on a listed bone (%s)" % [key, ba.bone_name])
		check(attached == spec.parts.size(), "%s: all %d code parts attached" % [key, spec.parts.size()])
		if key == "goblin":
			var again: Node3D = Art.instance(spec.scene)
			UnitModelScript.dress(again, spec)
			var head := func(root: Node) -> Material: return (root.find_child("Rogue_Head", true, false) as MeshInstance3D).get_active_material(0)
			check(head.call(again) == head.call(model), "two goblins share one tinted skin material")
			again.free()
		model.free()
	MeshMergeScript.enabled = true


## 무리 스폰: 스폰 횟수·면 순서는 예전(한 번에 한 마리) 그대로, 스폰 한 번에 spawn_group(3)마리가 같은 시각·같은 면에 나란히 —
## 몬스터 3배. 간격은 2배: 방치 idle_interval 8초(예전 4초), 스테이지 spawn_spacing_sec 1초(예전 0.5초). 웨이브 사이는 그대로, 보스는 라운드 25에만(개정 22).
func test_spawn_groups() -> void:
	GameData.load_tables()
	check(WaveDirector.group_size() == 3 and GameData.stage(1).idle_interval == 8.0 and GameData.stage(40).idle_interval == 8.0
		and GameData.config_num("spawn_spacing_sec") == 1.0, "spawn_group 3, idle_interval 8 (extrapolated too), spawn_spacing_sec 1.0")
	var idle := WaveDirector.build(1, WaveDirector.MODE_IDLE)
	var times: Array = idle.map(func(e): return e.time)
	check(times.all(func(t): return t == 8.0), "idle: all 12 at t = 8 s %s" % [times])
	check(idle.map(func(e): return e.lane) == [0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2] and idle.all(func(e): return e.lanes == 3), "idle: each group fills lanes 0..2 of 3 on one side")
	for stage in [1, 5, 25, 30]:
		var st := GameData.stage(stage)
		var size := int(st.wave_size)
		var ev := WaveDirector.build(stage, WaveDirector.MODE_STAGE)
		var grunts := ev.filter(func(e): return e.kind == "grunt")
		var boss := 1 if stage == 25 else 0  # 개정 22: 보스는 라운드 25에만
		check(grunts.size() == 3 * int(st.waves) * size and ev.filter(func(e): return e.kind == "epic_boss").size() == boss and (boss == 0 or ev[-1].kind == "epic_boss"),
			"stage %d: 3 x waves x wave_size grunts, a boss last only on round 25" % stage)
		var groups := {}  # 시각 → 그 시각 몬스터들
		for e in grunts:
			groups[e.time] = groups.get(e.time, []) + [e]
		var keys: Array = groups.keys()
		var groups_ok := true
		for i in keys.size():
			var g: Array = groups[keys[i]]
			groups_ok = groups_ok and g.map(func(e): return e.side) == [(i % size) % 4, (i % size) % 4, (i % size) % 4] \
				and g.map(func(e): return e.lane) == [0, 1, 2] and g.all(func(e): return e.lanes == 3)
		check(keys.size() == int(st.waves) * size and groups_ok, "stage %d: wave_size spawns per wave, each 3 at once on one side in lanes 0..2 (side = index in wave %% 4)" % stage)
		var gaps_ok := true
		for i in range(1, keys.size()):
			var want: float = 1.0 if i % size != 0 else 1.0 + GameData.config_num("wave_gap_sec")
			gaps_ok = gaps_ok and is_equal_approx(keys[i] - keys[i - 1], want)
		if boss == 1:
			gaps_ok = gaps_ok and is_equal_approx(ev[-1].time - keys[-1], 1.0 + GameData.config_num("wave_gap_sec"))
		check(gaps_ok, "stage %d: 1 s between spawns, wave gap and boss timing unchanged" % stage)


# --- 던전·장비(개정 18) ---

const DG_LAST := 1789916400.0  # 2026-09-20 15:00 UTC = 09-21 00:00 KST(서버 테스트 T0가 속한 날)
const DG_MID := DG_LAST + 86400.0
const GOLD6 := ["hans", "ella", "dorik", "nina", "arteon", "ignis"]
const EQ4 := ["hans", "ella", "dorik", "nina"]  # Knight·Rogue_Hooded·Barbarian·Mage


## 고정 난수열 Callable(서버 rules.rollDrops와 같은 호출 순서 확인용).
const ItemTextT := preload("res://scripts/item_text.gd")


## 장비 합계 {hp, atk, speed_pct, 특수…}에서 기본 셋만.
func _pick3(b: Dictionary) -> Array:
	return [b.hp, b.atk, b.speed_pct]


func _unique_count(a: Array) -> int:
	var d := {}
	for x in a:
		d[x] = true
	return d.size()


func _seq(values: Array) -> Callable:
	var i := [0]
	return func():
		var v: float = values[i[0] % values.size()]
		i[0] += 1
		return v


## 표·공식(서버 rules와 같은 값): 적 능력치·보상·등급 표·장비 능력치·판매 값·무기 종류·일일 리셋, 장비 합계가 영웅 최종 능력치에 더해진다.
func test_dungeon_tables() -> void:
	GameData.load_tables()
	check(GameData.errors == 0 and GameData.dungeon_rows("gold").size() == 3 and GameData.dungeon_rows("equip").size() == 1, "dungeons.csv: 3 gold rows and 1 equip row")
	var g1 := GameData.dungeon_enemies("gold", 1)
	check(g1.map(func(x): return [x.id, x.kind, x.count, x.delay, x.hp, x.atk]) == [["gold_goblin_a", "goblin", 10, 0.0, 120.0, 14.0], ["gold_goblin_b", "goblin", 5, 5.0, 120.0, 14.0],
		["gold_king", "goblin_king", 1, 5.0, 1500.0, 40.0]] and g1[2].scale == 1.7, "gold level 1: 10 goblins, 5 more + the king after 5 s (HP 120 / atk 14, king 1500 / 40, x1.7): %s" % [g1])
	var g3 := GameData.dungeon_enemies("gold", 3)
	var dk := GameData.dungeon_enemies("equip", 2)
	check(is_equal_approx(g3[0].hp, 120.0 * 1.12 * 1.12) and is_equal_approx(g3[2].atk, 40.0 * 1.12 * 1.12) and dk.size() == 1 and dk[0].kind == "death_knight"
		and is_equal_approx(dk[0].hp, 6900.0) and is_equal_approx(dk[0].atk, 67.2) and dk[0].scale == 2.2, "enemy stats x growth^(n-1): goblins 1.12, death knight HP 1.15 / atk 1.12")
	check([1, 2, 3, 10].map(func(n): return GameData.gold_reward(n)) == [4000, 4400, 4840, 9432], "gold reward = round(4000 x 1.1^(n-1))")
	check(GameData.drop_weights(1) == {"N": 60.0, "R": 30.0, "SR": 9.0, "SSR": 1.0, "UR": 0.0, "LR": 0.0} and GameData.drop_weights(4) == GameData.drop_weights(1)
		and GameData.drop_weights(5).UR == 1.0 and GameData.drop_weights(19).LR == 0.5 and GameData.drop_weights(20).SR == 34.0 and GameData.drop_weights(34).LR == 2.0
		and GameData.drop_weights(35).LR == 7.0 and GameData.drop_weights(300).N == 2.0, "grade table bands 1-4, 5-9, 10-19, 20-34, 35+")
	# 호출 순서: 부위(무기?) → 무기 종류 또는 방어구 부위 → 등급 → 기본 굴림 → 특수(종류 → 굴림). 서버 테스트와 같은 난수열 → 같은 결과
	var fixed := GameData.roll_drops(1, 2, _seq([0.1, 0.5, 0.95, 0.9, 0.0, 0.995, 0.9, 0.0, 0.995, 0.5, 0.4, 0.2]))
	check(fixed == [{"slot": "weapon", "weapon_kind": "staff", "grade": "SR", "rolls": {"atk": 112}, "subs": [{"id": "lifesteal", "r": 115}]},
		{"slot": "hat", "weapon_kind": null, "grade": "SSR", "rolls": {"hp": 100}, "subs": [{"id": "crit_dmg", "r": 91}]}],
		"roll_drops draws slot -> kind/armor -> grade -> rolls -> special stats in the server order: %s" % [fixed])
	var rng := RandomNumberGenerator.new()
	rng.seed = 18
	var many := GameData.roll_drops(12, 60000, rng.randf)
	var share := func(f: Callable) -> float: return many.filter(f).size() / 60000.0
	var w := [20.0, 35.0, 28.0, 13.0, 3.5, 0.5]
	var grades_ok := true
	for i in GameData.EQUIP_GRADES.size():
		var gname: String = GameData.EQUIP_GRADES[i]
		grades_ok = grades_ok and absf(share.call(func(x): return x.grade == gname) - w[i] / 100.0) < 0.007
	check(many.size() == 60000 and absf(share.call(func(x): return x.slot == "weapon") - 0.2) < 0.007 and absf(share.call(func(x): return x.slot == "gloves") - 0.8 / 6.0) < 0.007
		and grades_ok and many.all(func(x): return (x.slot == "weapon") == (x.weapon_kind != null)), "drop sample: weapons 20%, armor slots even, grades follow the weights")
	var rolls_ok := true
	for x in many:
		var ids: Array = x.subs.map(func(y): return y.id)
		rolls_ok = rolls_ok and x.rolls.size() == (2 if x.slot == "shoes" else 1) and x.rolls.values().all(func(r): return r >= 85 and r <= 115) \
			and x.subs.size() == int(GameData.SUB_COUNT.get(x.grade, 0)) and ids.size() == _unique_count(ids)
	check(rolls_ok and many.any(func(x): return x.rolls.values()[0] == 85) and many.any(func(x): return x.rolls.values()[0] == 115),
		"each stat rolls 85..115 on its own; SR/SSR 1, UR 2, LR 3 different special stats")
	# 2026-10-07 장비 레벨 없앰: 값 = round(기준값 x 등급 배율 x 굴림 / 100), 굴림 없으면 100
	var st := func(slot: String, grade: String, rolls := {}) -> Dictionary: return GameData.item_stats({"slot": slot, "weapon_kind": "sword" if slot == "weapon" else null, "grade": grade, "rolls": rolls})
	check(st.call("weapon", "N").atk == 20 and st.call("weapon", "SR", {"atk": 115}).atk == 51 and st.call("gloves", "R", {"atk": 85}).atk == 10
		and st.call("shoes", "LR", {"hp": 100, "speed_pct": 85}).hp == 423 and is_equal_approx(st.call("shoes", "LR", {"speed_pct": 85}).speed_pct, 2.55)
		and st.call("shoes", "N").speed_pct == 3.0 and st.call("top", "UR").hp == 598 and st.call("bottom", "N").hp == 130 and st.call("hat", "SSR").hp == 256
		and st.call("pauldron", "R").hp == 120, "item stats = round(base x grade mult x roll / 100), shoes speed 3% x roll")
	var lr := {"slot": "hat", "grade": "LR", "rolls": {"hp": 90}, "subs": [{"id": "lifesteal", "r": 110}, {"id": "crit_dmg", "r": 85}, {"id": "dmg_reduce", "r": 100}]}
	var ls := GameData.item_stats(lr)
	var lb := GameData.item_stats(lr, true)
	check(ls.hp == 468 and lb.hp == 520 and is_equal_approx(ls.lifesteal, 6.6) and is_equal_approx(ls.crit_dmg, 15.3) and ls.dmg_reduce == 6.0 and lb.lifesteal == 6.0
		and lb.crit_dmg == 18.0 and ls.aspd == 0.0, "special stats = grade base x roll / 100; base=true ignores the rolls: %s" % [ls])
	check(ItemTextT.stat_parts(lr) == [["HP +468", ItemTextT.DOWN_COLOR]] and ItemTextT.sub_parts(lr) == [["흡혈 +6.6%", ItemTextT.UP_COLOR], ["치명타 피해 +15.3%", ItemTextT.DOWN_COLOR],
		["받는 피해 감소 +6%", ItemTextT.INK]], "stat colours: below base red, above green, equal plain: %s %s" % [ItemTextT.stat_parts(lr), ItemTextT.sub_parts(lr)])
	check(GameData.item_sell_value({"grade": "SR"}) == 220 and GameData.item_sell_value({"grade": "N"}) == 100 and GameData.item_sell_value({"grade": "LR"}) == 650,
		"sell value = round(100 x grade mult)")
	var tot := GameData.equip_total([{"slot": "weapon", "weapon_kind": "sword", "grade": "SR", "rolls": {"atk": 100}}, {"slot": "shoes", "grade": "LR", "weapon_kind": null},
		{"slot": "gloves", "grade": "R", "weapon_kind": null}, lr])
	check(tot.hp == 423 + 468 and tot.atk == 44 + 12 and tot.speed_pct == 3.0 and is_equal_approx(tot.lifesteal, 6.6), "equip_total sums the items: %s" % [tot])
	# 저장·서버 값 검사(서버 rules.cleanRolls와 같다)
	check(EconomyScript._clean_rolls("hat", "UR", {"hp": 116, "atk": 100}, [{"id": "aspd", "r": 90}, {"id": "aspd", "r": 99}, {"id": "x", "r": 100}, {"id": "crit_rate", "r": 84},
		{"id": "lifesteal", "r": 85}, {"id": "skill_dmg", "r": 100}]) == {"rolls": {}, "subs": [{"id": "aspd", "r": 90}, {"id": "lifesteal", "r": 85}]}
		and EconomyScript._clean_rolls("shoes", "N", {"hp": 85.0, "speed_pct": 115}, [{"id": "aspd", "r": 100}]) == {"rolls": {"hp": 85, "speed_pct": 115}, "subs": []},
		"stored rolls are checked: out of range, wrong stat, duplicate or extra special stats are dropped")
	check(GameData.weapon_of("Knight") == "sword" and GameData.weapon_of("Barbarian") == "axe" and GameData.weapon_of("Mage") == "staff" and GameData.weapon_of("Rogue_Hooded") == "crossbow"
		and GameData.weapon_of("Rogue") == "dagger" and GameData.heroes().all(func(h): return GameData.weapon_of(h.model) != ""), "every hero model has its own weapon kind")
	# 일일 리셋: 15:00 UTC 경계, 놓친 날 × 지급을 상한까지
	var d := {"best_level": 4, "keys": 0, "extra_today": 2, "last_reset": DG_LAST}
	check(GameData.reset_day(DG_MID - 1.0) + 1 == GameData.reset_day(DG_MID) and GameData.apply_reset("gold", d, DG_MID - 1.0) == d and GameData.next_reset(DG_MID - 1.0) == DG_MID,
		"daily reset: 23:59:59 KST is still the same day")
	check(GameData.apply_reset("gold", d, DG_MID) == {"best_level": 4, "keys": 3, "extra_today": 0, "last_reset": DG_MID}
		and GameData.apply_reset("gold", d, DG_MID + 2 * 86400.0 + 5.0).keys == 9 and GameData.apply_reset("gold", d, DG_MID + 3 * 86400.0).keys == 10
		and GameData.apply_reset("gold", {"best_level": 0, "keys": 12, "extra_today": 0, "last_reset": DG_LAST}, DG_MID + 9 * 86400.0).keys == 12
		and GameData.apply_reset("equip", d, DG_MID + 9 * 86400.0).keys == 3 and GameData.apply_reset("gold", d, DG_LAST - 864000.0) == d,
		"daily reset: +3 at 00:00 KST, missed days x 3 up to the cap 10 (equip 1 / 3), extra runs back to 0, a clock set back changes nothing")
	check(GameData.fresh_dungeon("gold", DG_MID + 100.0) == {"best_level": 0, "keys": 3, "extra_today": 0, "last_reset": DG_MID} and GameData.extra_cost(0) == 100000
		and GameData.extra_cost(2) == 300000 and GameData.party_size("gold") == 6 and GameData.party_size("equip") == 4 and GameData.min_clear_sec("equip") == 20.0,
		"fresh dungeon = today's keys; extra run cost 100000 x (1 + runs today); party 6 / 4")
	# 영웅 최종 능력치 = (기본 × 레벨 × 승급) + 장비 합계(개정 24: 연구소 배율 없음)
	var hans := GameData.hero("hans")
	check(GameData.hero_stats(hans, 1, 0, {"hp": 100, "atk": 12}) == {"hp": 496.0, "atk": 35.0} and is_equal_approx(GameData.hero_stats(hans, 2, 0, {"atk": 12}).atk, 23.0 * 1.0315 + 12.0)
		and GameData.hero_stats(hans, 1, 0) == {"hp": 396.0, "atk": 23.0} and GameData.hero_power(hans, 1, 0, {"hp": 100, "atk": 12}) == roundi(49.6 + 35.0 * 2.0 / 0.8),
		"hero stats add the equipment total flat after the multipliers (no source, no equipment: unchanged)")


## 오프라인 도전(서버와 같은 규칙): 시작 검사, 열쇠·골드는 승리 때만, 타당성, 같은 run 재전송은 같은 결과, 장비 5개, 골드 추가 도전, 보관함 상한, 일일 리셋.
## 모집권 던전(2026-10-06): 열쇠 1 / 3, 보상 다이아 모집권, 도우미 후보 3명(전투력 ±10%·같은 날 같은 후보), 고르기 검사(빈 값·편성과 겹침·
## 후보 아님), 시작 run에 도우미(레벨·승급), 승리 = 열쇠 −1·모집권 +1·그 도우미는 오늘 다시 못 씀(후보에서 빠짐), 패배는 그대로, 다음 날 리셋.
func test_ticket_dungeon_offline() -> void:
	var t0 := Time.get_unix_time_from_system()
	var e = _econ(t0)
	var started := []
	var finished := []
	e.dungeon_started.connect(func(r): started.append(r))
	e.dungeon_finished.connect(func(r): finished.append(r))
	for id in ["arteon", "ignis"]:
		e.heroes[id] = 1
	var st: Dictionary = e.dungeon_state("ticket")
	var hs: Array = st.helpers
	check(st.keys == 1 and st.key_cap == 3 and st.helpers_used == [] and hs.size() == 3 and e.dungeon_reward("ticket", 1) == {"tickets": 10}
		and e.dungeon_reward("ticket", 5) == {"tickets": 10} and e.dungeon_reward("ticket", 6) == {"tickets": 12} and e.dungeon_reward("ticket", 11) == {"tickets": 14} and GameData.party_size("ticket") == 4, "ticket dungeon: 1 / 3 keys, 3 helpers, 10 tickets (+2 per 5 levels): %s" % [hs])
	var top := []
	for id in e.heroes:
		top.append(GameData.hero_power(GameData.hero(id), e.level_of(id), e.promotion_of(id)))
	top.sort()
	top.reverse()
	var ref: float = (top[0] + top[1] + top[2] + top[3]) / 4.0
	check(hs.all(func(h): return absf(h.power - ref) / ref <= GameData.HELPER_FIT or h.level == 1) and e.helper_candidates() == hs,
		"helpers are near the top-4 average power %.0f (same list on the same day): %s" % [ref, hs])
	var helper: String = hs[0].hero_id
	var party: Array = ["hans", "ella", "dorik", "nina", "arteon", "ignis"].filter(func(x): return x != helper).slice(0, 4)
	check(e.dungeon_block("ticket", 1, party, "") == "no_helper" and e.dungeon_block("ticket", 1, party, "kyle" if not hs.any(func(h): return h.hero_id == "kyle") else "zzz") == "helper_unavailable"
		and e.dungeon_block("ticket", 1, party, helper) == "" and e.dungeon_block("ticket", 1, party) == "", "helper checks: none / not offered / ok (card view skips the helper)")
	if e.heroes.has(helper):
		check(e.dungeon_block("ticket", 1, [helper] + party.slice(0, 3), helper) == "bad_party", "the helper hero cannot also be in the party")
	check(e.start_dungeon("ticket", 1, party, helper) and started[-1].helper.hero_id == helper and started[-1].helper.level == hs[0].level and started[-1].enemies.size() == 2,
		"start: the run carries the helper's level and promotion")
	e.finish_dungeon(e.current_run.run_id, false, 10.0)
	check(not finished[-1].win and e.dungeon_state("ticket").keys == 1 and e.dungeon_state("ticket").helpers_used == [], "a loss keeps the key and the helper")
	e.start_dungeon("ticket", 1, party, helper)
	e.debug_win()
	var st2: Dictionary = e.dungeon_state("ticket")
	check(finished[-1].win and finished[-1].rewards == {"tickets": 10} and e.dia_tickets == 10 and st2.keys == 0 and st2.best_level == 1 and st2.helpers_used == [helper]
		and not st2.helpers.any(func(h): return h.hero_id == helper) and e.dungeon_block("ticket", 2, party, helper) == "helper_used",
		"win: key -1, +1 ticket, that helper is used for today: %s" % [st2])
	e.clock_offset = 86400.0
	check(e.dungeon_state("ticket").keys == 1 and e.dungeon_state("ticket").helpers_used == [], "next day: a key and every helper again")
	e.clock_offset = 0.0
	# 전투 장면(도우미 영웅·골렘 조각)은 tests/ticket_check.tscn(오토로드가 필요하다)


func test_dungeons_offline() -> void:
	var t0 := Time.get_unix_time_from_system()
	var e = _econ(t0)
	var started := []
	var finished := []
	var notes := []
	e.dungeon_started.connect(func(r): started.append(r))
	e.dungeon_finished.connect(func(r): finished.append(r))
	e.notice.connect(func(t): notes.append(t))
	for id in ["arteon", "ignis"]:
		e.heroes[id] = 1
	var gs: Dictionary = e.dungeon_state("gold")
	var es: Dictionary = e.dungeon_state("equip")
	check(gs.keys == 3 and gs.key_cap == 10 and gs.best_level == 0 and gs.max_level == 1 and gs.extra_cost == 0 and es.keys == 1 and es.key_cap == 3 and es.extra_cost == 100000
		and absf(gs.next_reset - GameData.next_reset(t0)) < 1.0 and gs.reset_in > 0.0 and gs.reset_in <= 86400.0, "new game: gold 3 / 10, equip 1 / 3, next reset at 00:00 KST")
	check(e.dungeon_reward("gold", 2) == {"gold": 4400} and e.dungeon_reward("equip", 10).count == 5 and e.dungeon_reward("equip", 10).weights.LR == 0.5
		and e.dungeon_enemies("gold", 1).size() == 3, "reward preview and enemy list")
	var party: Array = e.default_party("gold")
	check(party.size() == 6 and GOLD6.all(func(h): return party.has(h)) and e.default_party("equip").size() == 4, "default party = the strongest owned heroes, 6 / 4: %s" % [party])
	check(e.dungeon_block("gold", 2, GOLD6) == "locked" and e.dungeon_block("gold", 1, EQ4) == "bad_party" and e.dungeon_block("gold", 1, ["hans", "hans", "ella", "dorik", "nina", "arteon"]) == "bad_party"
		and e.dungeon_block("gold", 1, ["hans", "ella", "dorik", "nina", "arteon", "kyle"]) == "bad_party" and e.dungeon_block("fire", 1, GOLD6) == "unknown"
		and e.dungeon_block("equip", 1, GOLD6) == "bad_party" and e.dungeon_block("gold", 1, GOLD6) == "", "dungeon_block: unknown / locked / party size, duplicate, not owned")
	check(not e.start_dungeon("gold", 2, GOLD6) and notes[-1] == EconomyScript.DUNGEON_TEXT.locked and started.is_empty(), "a refused start only shows the reason")
	check(e.start_dungeon("gold", 1, GOLD6) and started.size() == 1 and started[0].run_id == e.current_run.run_id and started[0].enemies.size() == 3 and started[0].paid_with == "key"
		and e.dungeon_state("gold").keys == 3, "start: a run with the enemies; nothing is spent yet")
	var run_id: String = e.current_run.run_id
	e.finish_dungeon(run_id, true, 30.0)  # 실제 경과 0초 < 30 − 5
	check(finished[-1].get("error") == "implausible" and e.current_run.run_id == run_id and e.dungeon_state("gold").keys == 3 and e.gold_tenths == 0
		and notes[-1] == EconomyScript.DUNGEON_TEXT.implausible, "a win faster than real time is implausible; the run stays open and nothing changes")
	e.current_run.started_at -= 26.0
	e.finish_dungeon(run_id, true, 30.0)
	check(finished[-1].win and finished[-1].rewards == {"gold_tenths": 40000} and e.gold_tenths == 40000 and e.dungeon_state("gold").keys == 2 and e.dungeon_state("gold").best_level == 1
		and e.current_run.is_empty(), "gold win: key -1, gold +4000, best level 1")
	e.finish_dungeon(run_id, true, 30.0)
	check(finished[-1].repeated and finished[-1].rewards == {"gold_tenths": 40000} and e.gold_tenths == 40000 and e.dungeon_state("gold").keys == 2, "the same run again returns the same result (idempotent)")
	e.start_dungeon("gold", 2, GOLD6)
	e.finish_dungeon(e.current_run.run_id, false, 5.0)
	check(not finished[-1].win and finished[-1].rewards.is_empty() and e.dungeon_state("gold").keys == 2 and e.dungeon_state("gold").best_level == 1 and e.gold_tenths == 40000,
		"a loss spends no key and changes nothing but the run")
	# 장비 던전: 즉시 승리 훅 → 장비 5개
	check(e.start_dungeon("equip", 1, EQ4) and e.debug_win() and finished[-1].win and finished[-1].rewards.items.size() == 5 and e.bag.size() == 5
		and e.bag.map(func(x): return x.id) == [1, 2, 3, 4, 5] and e.next_item_id == 6 and e.dungeon_state("equip").keys == 0 and e.dungeon_state("equip").best_level == 1
		and e.bag.all(func(x): return not x.has("level") and x.rolls.size() >= 1 and x.grade in GameData.EQUIP_GRADES and (x.slot == "weapon") == (x.weapon_kind != null)),
		"equip win (debug_win hook): exactly 5 items with ids 1..5, key -1: %s" % [e.bag])
	check(e.dungeon_block("equip", 1, EQ4) == "not_enough_gold", "no key and 4000 gold < 100000: no extra run")
	e.gold = 316000
	check(e.dungeon_block("equip", 2, EQ4) == "" and e.start_dungeon("equip", 2, EQ4) and started[-1].paid_with == "gold" and e.gold == 316000, "an extra run with gold starts without paying yet")
	e.debug_win()
	var es2: Dictionary = e.dungeon_state("equip")
	check(e.gold == 216000 and es2.extra_today == 1 and es2.extra_cost == 200000 and es2.best_level == 2 and e.bag.size() == 10, "the extra run's win pays 100000 gold; the next one costs 200000")
	e.start_dungeon("equip", 1, EQ4)
	e.finish_dungeon(e.current_run.run_id, false, 25.0)
	check(e.gold == 216000 and e.dungeon_state("equip").extra_today == 1, "a lost extra run pays nothing")
	for i in 286:  # 10 + 286 = 296, + 5 > 300
		e.bag.append({"id": e.next_item_id + i, "slot": "hat", "weapon_kind": null, "grade": "N", "level": 1})
	e.next_item_id += 286
	check(e.bag_full() and e.dungeon_block("equip", 1, EQ4) == "bag_full" and not e.start_dungeon("equip", 1, EQ4) and notes[-1] == "보관함이 가득 찼습니다"
		and e.dungeon_block("gold", 1, GOLD6) == "", "bag cap 300: an equip run is blocked before it starts ('보관함이 가득 찼습니다'); the gold dungeon is not")
	# 일일 리셋(오프라인, 앱 시계)
	e.dungeons.gold = {"best_level": 1, "keys": 0, "extra_today": 0, "last_reset": GameData.reset_at(GameData.reset_day(t0) - 4)}
	e.dungeons.equip.last_reset = GameData.reset_at(GameData.reset_day(t0) - 1)
	check(e.dungeon_state("gold").keys == 10 and e.dungeon_state("equip").keys == 1 and e.dungeon_state("equip").extra_today == 0, "offline daily reset: 4 missed days -> 10 (cap), equip +1 and extra runs back to 0")
	check(not e.finish_dungeon("nope", true, 30.0) or finished[-1].get("error") == "unknown_run", "an unknown run is refused")
	e.free()


## 장착·해제·옮기기·판매(오프라인): 무기 종류 규칙, 장비 합계가 능력치에(equip_source), 장착 중은 못 판다.
func test_equipment_offline() -> void:
	var e = _econ(Time.get_unix_time_from_system())
	var notes := []
	var roster := [0]
	e.notice.connect(func(t): notes.append(t))
	e.roster_changed.connect(func(): roster[0] += 1)
	e.bag = [{"id": 1, "slot": "weapon", "weapon_kind": "sword", "grade": "SR", "rolls": {}, "subs": []}, {"id": 2, "slot": "weapon", "weapon_kind": "axe", "grade": "N", "rolls": {}, "subs": []},
		{"id": 3, "slot": "hat", "weapon_kind": null, "grade": "R", "rolls": {}, "subs": []}, {"id": 4, "slot": "hat", "weapon_kind": null, "grade": "N", "rolls": {}, "subs": []},
		{"id": 5, "slot": "shoes", "weapon_kind": null, "grade": "LR", "rolls": {}, "subs": []}]
	e.next_item_id = 6
	check(e.equip_block("hans", "weapon", 2) == "wrong_weapon" and e.equip_block("nina", "weapon", 1) == "wrong_weapon" and e.equip_block("dorik", "weapon", 2) == ""
		and e.equip_block("hans", "weapon", 1) == "" and e.equip_block("hans", "hat", 5) == "wrong_slot" and e.equip_block("hans", "weapon", 3) == "wrong_slot"
		and e.equip_block("hans", "hat", 99) == "unknown_item" and e.equip_block("kyle", "hat", 3) == "not_owned" and e.equip_block("hans", "cape", 3) == "bad_slot",
		"equip_block: a weapon only fits its model's kind (Knight sword, Barbarian axe); slot, item and hero checks")
	check(not e.equip("hans", "weapon", 2) and notes[-1] == EconomyScript.EQUIP_TEXT.wrong_weapon and e.equipment.is_empty(), "a refused equip only shows the reason")
	var r0: int = roster[0]
	check(e.equip("hans", "weapon", 1) and e.equipment == {"hans": {"weapon": 1}} and _pick3(e.equipment_bonus("hans")) == [0, 44, 0.0] and roster[0] == r0 + 1
		and e.item_owner(1) == "hans" and e.hero_equipment("hans").weapon.weapon_kind == "sword", "equip: the SR sword on hans gives atk +44 (20 x 2.2) and fires roster_changed")
	e.equip("hans", "hat", 3)
	e.equip("ella", "hat", 3)  # 옮긴다
	check(e.equipment == {"hans": {"weapon": 1}, "ella": {"hat": 3}} and e.item_owner(3) == "ella", "equipping an item another hero wears moves it: %s" % [e.equipment])
	check(e.unequip("ella", "hat") and e.equipment == {"hans": {"weapon": 1}} and not e.unequip("ella", "hat"), "unequip empties the slot; an empty slot cannot be unequipped")
	e.equip("hans", "shoes", 5)
	check(_pick3(e.equipment_bonus("hans")) == [423, 44, 3.0], "shoes add HP and +3%% speed: %s" % [e.equipment_bonus("hans")])
	GameData.equip_source = e  # 오토로드 Economy처럼
	var hans := GameData.hero("hans")
	var st := GameData.hero_stats(hans, 1, 0)
	GameData.equip_source = null
	check(st == {"hp": 819.0, "atk": 67.0} and GameData.hero_stats(hans, 1, 0) == {"hp": 396.0, "atk": 23.0}, "with Economy as the equipment source, hero_stats adds hans's gear: %s" % [st])
	check(e.sell_block([1]) == "equipped" and e.sell_block([]) == "bad_request" and e.sell_block([3, 3]) == "bad_request" and e.sell_block([3, 99]) == "unknown_item"
		and e.sell_items([1, 3]) == 0 and notes[-1] == EconomyScript.EQUIP_TEXT.equipped and e.bag.size() == 5, "sell_block: equipped / empty / duplicate / unknown; a refused sale sells nothing")
	check(e.sell_items([3, 4]) == 250 and e.gold_tenths == 2500 and e.bag.map(func(x): return x.id) == [1, 2, 5], "sell: round(100 x 1.5) + 100 = 250 gold, the items leave the bag")
	e.free()


## 저장 v10(왕복·v9 → v10·깨진 v10·끊긴 장착은 버림)과 서버 응답(dungeons·items·equipment) 반영.
func test_dungeon_save_and_server() -> void:
	var t0 := Time.get_unix_time_from_system()
	var tmp := OS.get_temp_dir().path_join("castle_d1_econ_%d.json" % OS.get_process_id())  # user:// 밖(다른 워크트리 체크와 겹치지 않게)
	var e = _econ(t0)
	e.dungeons.gold = {"best_level": 7, "keys": 4, "extra_today": 0, "last_reset": GameData.reset_at(GameData.reset_day(t0))}
	e.dungeons.equip = {"best_level": 3, "keys": 0, "extra_today": 2, "last_reset": GameData.reset_at(GameData.reset_day(t0))}
	e.bag = [{"id": 4, "slot": "weapon", "weapon_kind": "sword", "grade": "UR", "rolls": {"atk": 110}, "subs": [{"id": "aspd", "r": 95}, {"id": "crit_rate", "r": 105}]},
		{"id": 9, "slot": "gloves", "weapon_kind": null, "grade": "N", "rolls": {"atk": 85}, "subs": []}]
	e.equipment = {"hans": {"weapon": 4}}
	e.next_item_id = 10
	e.save_path = tmp
	e.save()
	var e8 = _econ(0.0)
	e8.save_path = tmp
	e8.load_save(t0)
	var raw = JSON.parse_string(FileAccess.get_file_as_string(tmp))
	check(int(raw.version) == EconomyScript.SAVE_VERSION and EconomyScript.SAVE_VERSION >= 10 and e8.dungeons == e.dungeons and e8.bag == e.bag and e8.equipment == e.equipment and e8.next_item_id == 10
		and e8.bag[0].id is int and e8.dungeon_state("equip").extra_today == 2 and e8.equipment_bonus("hans").atk == roundi(20 * 4.6 * 1.1),
		"save v10 round-trips dungeons, the bag, equipment and next_item_id: %s %s" % [e8.dungeons, e8.bag])
	var v9: Dictionary = raw.duplicate(true)
	v9.version = 9
	for k in ["dungeons", "items", "equipment", "next_item_id"]:
		v9.erase(k)
	_write(tmp, JSON.stringify(v9))
	e8.load_save(t0)
	check(e8.gold_tenths == e.gold_tenths and e8.dungeon_state("gold").keys == 3 and e8.dungeon_state("equip").keys == 1 and e8.bag.is_empty() and e8.equipment.is_empty() and e8.next_item_id == 1,
		"save v9 -> v10: today's keys and an empty bag")
	for junk in [{"items": {}}, {"dungeons": []}, {"equipment": {"hans": 4}}, {"items": [{"slot": "hat"}]}, {"dungeons": {"gold": {"keys": "x"}}}, {"next_item_id": "3"}]:
		var bad: Dictionary = raw.duplicate(true)
		bad.merge(junk, true)
		_write(tmp, JSON.stringify(bad))
		e8.load_save(t0)
		check(e8.bag.is_empty() and e8.dungeon_state("gold").best_level == 0, "malformed v10 (%s) is a corrupt save" % [junk])
	var odd: Dictionary = raw.duplicate(true)
	odd.items = raw.items + [{"id": 11, "slot": "cape", "weapon_kind": null, "grade": "N", "level": 1}, {"id": 12, "slot": "weapon", "weapon_kind": null, "grade": "N", "level": 1},
		{"id": 13, "slot": "hat", "weapon_kind": null, "grade": "XR", "level": 1}, {"id": 14, "slot": "top", "weapon_kind": null, "grade": "LR", "level": 2}]
	# JSON.stringify는 키를 정렬한다 — ella가 먼저: top 14는 ella, 검(4)은 Rogue_Hooded가 못 낀다
	odd.equipment = {"hans": {"weapon": 4, "hat": 9, "top": 14, "pauldron": 77}, "ella": {"top": 14, "weapon": 4}, "ghost": {"hat": 9}}
	odd.next_item_id = 2
	_write(tmp, JSON.stringify(odd))
	e8.load_save(t0)
	check(e8.bag.map(func(x): return x.id) == [4, 9, 14] and e8.equipment == {"hans": {"weapon": 4}, "ella": {"top": 14}} and e8.next_item_id == 15,
		"v10 load drops unknown items and wrong-slot / wrong-weapon / missing / doubled / unknown-hero equipment, next_item_id stays above the ids: %s %s" % [e8.bag, e8.equipment])
	DirAccess.remove_absolute(tmp)
	e8.free()
	e.save_path = ""
	# 서버 응답(개정 18 부분)
	var reply := {"player": {"gold_tenths": 50, "stage": 1, "res": {}, "buildings": {},
		"dungeons": {"gold": {"keys": 2, "key_cap": 10, "key_daily": 3, "best_level": 5, "extra_today": 0, "extra_cost": null, "last_reset": DG_LAST, "next_reset": DG_MID},
			"equip": {"keys": 0, "key_cap": 3, "key_daily": 1, "best_level": 1, "extra_today": 1, "extra_cost": 10000, "last_reset": DG_LAST, "next_reset": DG_MID}},
		"items": [{"id": 31, "slot": "weapon", "weapon_kind": "axe", "grade": "SSR", "level": 4}, {"id": 30, "slot": "hat", "weapon_kind": null, "grade": "R", "level": 1}],
		"equipment": {"dorik": {"weapon": 31}}}, "merchant": {"rates": {"wood": 1.0, "stone": 1.0, "food": 1.0}, "next_change": 3600.0}}
	var sig := [0, 0, 0]
	e.dungeons_changed.connect(func(): sig[0] += 1)
	e.items_changed.connect(func(): sig[1] += 1)
	e.roster_changed.connect(func(): sig[2] += 1)
	check(e.apply_server(reply) and e.dungeons.gold == {"best_level": 5, "keys": 2, "extra_today": 0, "last_reset": DG_LAST} and e.bag.map(func(x): return x.id) == [30, 31]
		and e.equipment == {"dorik": {"weapon": 31}} and e.equipment_bonus("dorik").atk == roundi(20 * 3.2) and sig[0] >= 1 and sig[1] >= 1 and sig[2] >= 1,
		"apply_server takes dungeons, the bag (id order) and equipment, and fires dungeons_changed / items_changed / roster_changed")
	var gold_keys: int = e.dungeon_state("gold").keys
	check(gold_keys == GameData.apply_reset("gold", e.dungeons.gold, e.time_now()).keys and gold_keys >= 2, "online dungeon_state counts the daily reset from the server's last_reset")
	var logged := _errors.count
	var bad_reply: Dictionary = reply.duplicate(true)
	bad_reply.player.items = {}
	check(not e.apply_server(bad_reply) and e.bag.size() == 2, "apply_server rejects items that are not an array")
	_errors.count = logged  # 거부는 push_error로 알린다
	e.free()


# --- 계절 (개정 22 §4) ---
const SeasonsScript := preload("res://scripts/seasons.gd")


## 정점 색 중 target(또는 MeshKit.rock이 0~12% 어둡게 한 target)인 것의 수. 정점 색은 8비트로 저장돼 오차를 둔다.
func _count_like(mesh: Mesh, target: Color) -> int:
	var n := 0
	for c in mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
		var f: float = c.g / target.g
		if f > 0.86 and f < 1.02 and absf(c.r - target.r * f) < 0.02 and absf(c.b - target.b * f) < 0.02:
			n += 1
	return n


func test_seasons() -> void:
	check([1, 2, 3, 4, 5, 9].map(func(s): return SeasonsScript.season_of_stage(s)) == [0, 1, 2, 3, 0, 0],
		"season cycle: stage 1 spring, 2 summer, 3 autumn, 4 winter, 5 spring again")
	check([1, 25, 26, 50, 51].map(func(g): return SeasonsScript.stage_of_round(g)) == [1, 1, 2, 2, 3], "global round g -> stage S (25 rounds per stage)")
	check(SeasonsScript.PALETTES.size() == 4 and SeasonsScript.PALETTES.all(func(p): return p.particles.get("amount", 0) <= SeasonsScript.MAX_PARTICLES)
		and SeasonsScript.PALETTES[1].particles.is_empty(), "four seasons, particles at most 150, summer has none")
	# 실제 레시피로 만든 가짜 풍경(buildings.gd season_slots와 같은 모양)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var slots := []
	for pair in [[TownKitScript.tree_pine, 0], [TownKitScript.tree_round, 0], [TownKitScript.tree_round, 1], [TownKitScript.bush, 0],
			[TownKitScript.mountain, 0], [TownKitScript.rock_cluster, 0]]:
		var st: int = rng.state
		var mm := MultiMesh.new()
		mm.mesh = pair[0].call(rng)
		slots.append({"mm": mm, "recipe": pair[0], "idx": pair[1], "state": st, "base": mm.mesh})
	var replay := RandomNumberGenerator.new()
	replay.state = slots[0].state
	check(TownKitScript.tree_pine(replay).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == slots[0].base.surface_get_arrays(0)[Mesh.ARRAY_VERTEX],
		"the saved rng state rebuilds the same shape (default palette keeps the old rng order)")
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/ground_grid.gdshader")
	var s = SeasonsScript.new()
	s.setup(env, sun, mat, {"season_slots": slots}, null)
	s.apply(SeasonsScript.season_of_stage(3), true)
	var au: Dictionary = SeasonsScript.PALETTES[2]
	check(mat.get_shader_parameter("grass_a") == au.grass_a and mat.get_shader_parameter("grass_b") == au.grass_b and env.background_color == au.sky
		and env.ambient_light_color == au.ambient and sun.light_color == au.sun and is_equal_approx(sun.light_energy, au.sun_energy), "autumn sets ground, sky, ambient and sun")
	check(slots.slice(0, 5).all(func(sl): return sl.mm.mesh != sl.base) and slots[5].mm.mesh == slots[5].base, "autumn swaps tree, bush and mountain meshes; rocks stay")
	check(_count_like(slots[1].mm.mesh, au.tree_round[0].leaf) > 0 and _count_like(slots[1].mm.mesh, TownKitScript.LEAF) == 0
		and _count_like(slots[2].mm.mesh, au.tree_round[1].leaf) > 0, "autumn canopies: orange and red variants, no summer green")
	check(s._particles.emitting and s._particles.amount == au.particles.amount, "autumn: falling leaves")
	var autumn_tree: Mesh = slots[1].mm.mesh
	s.apply(3, true)
	check(_count_like(slots[0].mm.mesh, TownKitScript.SNOW) > 0 and _count_like(slots[0].base, TownKitScript.SNOW) == 0, "winter: snow caps on the pines")
	var bare: Mesh = slots[1].mm.mesh
	check(_count_like(bare, TownKitScript.WOOD) + _count_like(bare, TownKitScript.WOOD_DARK) == bare.surface_get_arrays(0)[Mesh.ARRAY_COLOR].size(),
		"winter: round trees are bare wood branches, no canopy")
	check(_count_like(slots[4].mm.mesh, TownKitScript.SNOW) > _count_like(slots[4].base, TownKitScript.SNOW), "winter: the mountain snow band reaches lower")
	check(mat.get_shader_parameter("edge_snow") > 0.0 and s._particles.emitting and s._particles.amount <= SeasonsScript.MAX_PARTICLES, "winter: paving edge snow, snowfall within 150")
	s.apply(2, true)
	check(slots[1].mm.mesh == autumn_tree, "season variants are built once and cached")
	s.apply(1, true)
	check(slots.all(func(sl): return sl.mm.mesh == sl.base) and not s._particles.emitting and mat.get_shader_parameter("edge_snow") == 0.0
		and mat.get_shader_parameter("grass_a") == SeasonsScript.PALETTES[1].grass_a, "summer: base meshes, no particles, no snow")
	s.apply(0, true)
	check(_count_like(slots[1].mm.mesh, SeasonsScript.PALETTES[0].tree_round[0].leaf) > 0, "spring: a blossom tree variant")
	s.stage = 1
	s.change_stage(4)
	check(s.stage == 4 and s.season == 3 and _count_like(slots[0].mm.mesh, TownKitScript.SNOW) > 0, "change_stage(4) moves to winter (outside the tree: at once)")
	SeasonsScript.set_stage(5)  # 살아 있는 월드가 없으면 무시
	check(s.stage == 4, "Seasons.set_stage without a live world is a no-op")
	s.free()
	sun.free()


## 방치 한 번 = 네 면 × 3마리가 같은 시각(동서남북 동시, 순차 아님).
func test_idle_four_sides_at_once() -> void:
	GameData.load_tables()
	var ev := WaveDirector.build(1, WaveDirector.MODE_IDLE)
	var ok := ev.size() == 12 and ev.all(func(e): return e.time == ev[0].time)
	for side in 4:
		ok = ok and ev.filter(func(e): return e.side == side).map(func(e): return e.lane) == [0, 1, 2]
	check(ok, "idle event: 4 sides x 3 lanes at the same time")


## 개정 23 모집: 골드 레벨 비용·확률·레벨업(누적·넘김·최대), 다이아 확률(골드 최대보다 좋다)·천장 50, 오프라인 모집·알림·시그널,
## 저장 v11(v10 → 기본값, 깨진 v11), 서버 응답 diamonds·gacha, 설정 검증, 다이아 아이콘, 스냅 API·키 아트 노드 구조.
func test_recruit_r23() -> void:
	const SceneSnap := preload("res://scripts/scene_snap.gd")
	const RecruitArt := preload("res://scripts/recruit_art.gd")
	GameData.load_tables()
	# 공식(서버 rules와 같은 값)
	check([1, 2, 5, 10].map(func(l): return GameData.gacha_cost("gold", 1, l)) == [3000, 3450, 5250, 10550], "rev 23: gold 1-pull 3000 / 3450 / 5250 / 10550 at Lv 1 / 2 / 5 / 10")
	check(GameData.gacha_cost("gold", 10, 10) == 105500 and GameData.gacha_cost("gold", 1, 99) == 10550 and GameData.gacha_cost("diamond", 1, 7) == 300
		and GameData.gacha_cost("diamond", 10, 7) == 2700, "rev 23: gold 10-pull = 1-pull x 10 (no discount), levels clamp to the max, diamonds ignore the level")
	var l4 := GameData.gacha_rates("gold", 4, 1)
	var l10 := GameData.gacha_rates("gold", 10, 1)
	var dia := GameData.gacha_rates("diamond", 1, 1)
	check(is_equal_approx(l4.ssr, 0.008) and is_equal_approx(l4.sr, 0.065) and is_equal_approx(l10.ssr, 0.014) and is_equal_approx(l10.sr, 0.095),
		"rev 23: gold rates SSR 0.5%% + 0.1%%p, SR 5%% + 0.5%%p per level (Lv 10: 1.4%% / 9.5%%): %s %s" % [l4, l10])
	check(is_equal_approx(dia.ssr, 0.08) and is_equal_approx(dia.sr, 0.3) and dia.ssr > l10.ssr and dia.sr > l10.sr and is_equal_approx(GameData.gacha_rates("diamond", 1, 3).ssr, 0.082),
		"rev 23: diamond rates 8% / 30% beat gold max level; the tavern bonus applies too")
	# 레벨업
	check([1, 2, 9, 10].map(func(l): return GameData.gacha_gold_next(l)) == [30, 60, 270, 0], "rev 23: next level at 30 x L, none at max")
	check(GameData.gacha_level_up(1, 29, 1) == {"level": 2, "pulls": 0} and GameData.gacha_level_up(1, 28, 1) == {"level": 1, "pulls": 29}
		and GameData.gacha_level_up(1, 25, 10) == {"level": 2, "pulls": 5} and GameData.gacha_level_up(1, 0, 1000) == {"level": 8, "pulls": 160}
		and GameData.gacha_level_up(9, 265, 10) == {"level": 10, "pulls": 0} and GameData.gacha_level_up(10, 0, 10) == {"level": 10, "pulls": 0},
		"rev 23: level-up accumulates, carries over, climbs several levels at once and stops at 10")
	# 천장
	var all_r := func(): return 0.99
	var pity := {"n": 0, "max": 50}
	var first: Array = EconomyScript.roll_gacha(49, all_r, dia, pity)
	var fiftieth: Array = EconomyScript.roll_gacha(1, all_r, dia, pity)
	check(first.all(func(x): return x.grade == "R") and fiftieth[0].grade == "SSR" and pity.n == 0, "rev 23: the 50th diamond pull without an SSR is an SSR; the counter resets")
	pity.n = 45
	var ten: Array = EconomyScript.roll_gacha(10, all_r, dia, pity)
	check(ten.map(func(x): return x.grade) == ["R", "R", "R", "R", "SSR", "R", "R", "R", "R", "R"] and pity.n == 5, "rev 23: pity inside a 10-pull (5th card)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var sample: Array = EconomyScript.roll_gacha(100000, rng.randf, l10)
	var ssr := sample.filter(func(x): return x.grade == "SSR").size() / 100000.0
	var sr := sample.filter(func(x): return x.grade == "SR").size() / 100000.0
	check(absf(ssr - 0.014) <= 0.0025 and absf(sr - 0.095) <= 0.006, "rev 23: gold Lv 10 sample SSR 1.4%% +- 0.25%%, SR 9.5%% +- 0.6%%: %s %s" % [ssr, sr])
	# 오프라인 골드: 10연차 3번 = 30회 → Lv 2(알림·시그널·비용)
	var e = _econ(1000.0)
	var notes := []
	var ups := []
	var got := []
	e.notice.connect(func(t): notes.append(t))
	e.gacha_leveled.connect(func(l): ups.append(l))
	e.gacha_done.connect(func(r): got.append(r))
	e.gold = 90000
	check(e.gacha(10) and e.gacha(10) and e.gacha_state().gold_pulls == 20 and e.gacha_state().gold_level == 1 and ups.is_empty(), "rev 23: two 10-pulls are 20/30 at Lv 1")
	check(e.gacha(10) and e.gold == 0 and e.gacha_state() == {"gold_level": 2, "gold_pulls": 0, "gold_next": 60, "dia_pity": 0, "pity_left": 50}
		and ups == [2] and notes == ["골드 모집 Lv 2! SSR 0.6%"] and e.gacha_cost("gold", 1) == 3450,
		"rev 23: the 30th pull levels up: notice, signal, new cost: %s %s" % [e.gacha_state(), notes])
	# 오프라인 다이아
	notes.clear()
	check(not e.gacha(1, "diamond") and notes == [EconomyScript.NO_DIA_TEXT] and got.size() == 3, "rev 23: no diamonds: a notice only")
	e.diamonds = 3000
	check(e.gacha(10, "diamond") and e.diamonds == 300 and e.gacha_state().gold_pulls == 0 and e.gacha_state().gold_level == 2 and e.gold == 0,
		"rev 23: a diamond 10-pull takes 2700 diamonds and leaves gold and the gold level alone")
	e.gacha_dia_pity = 49
	check(e.gacha(1, "diamond") and got[-1][0].grade == "SSR" and e.gacha_dia_pity == 0 and e.diamonds == 0, "rev 23: offline pity — pull 50 is an SSR")
	check(not e.gacha(1, "ruby") and not e.gacha(3, "diamond"), "rev 23: unknown currency or count does nothing")
	# 저장 v11 왕복, v10은 기본값, 모집 상태가 빠진 v11은 깨진 저장
	var tmp := "user://test_r23_save.json"
	e.save_path = tmp
	e.diamonds = 1234
	e.gacha_gold_level = 3
	e.gacha_gold_pulls = 7
	e.gacha_dia_pity = 11
	e.save()
	var raw = JSON.parse_string(FileAccess.get_file_as_string(tmp))
	var e2 = _econ(0.0)
	e2.save_path = tmp
	e2.load_save(1000.0)
	check(int(raw.version) == EconomyScript.SAVE_VERSION and e2.diamonds == 1234 and e2.gacha_state().gold_level == 3 and e2.gacha_gold_pulls == 7 and e2.gacha_dia_pity == 11,
		"rev 23: the save (now v12) round-trips diamonds and the recruit state")
	var v10: Dictionary = raw.duplicate(true)
	v10.version = 10
	v10.erase("diamonds")
	v10.erase("gacha")
	_write(tmp, JSON.stringify(v10))
	e2.load_save(1000.0)
	check(e2.diamonds == 0 and e2.gacha_gold_level == 1 and e2.gacha_gold_pulls == 0 and e2.gacha_dia_pity == 0 and e2.heroes == e.heroes, "rev 23: a v10 save loads with 0 diamonds and gold recruit Lv 1")
	var broken: Dictionary = raw.duplicate(true)
	broken.erase("gacha")
	_write(tmp, JSON.stringify(broken))
	e2.load_save(1000.0)
	check(e2.diamonds == 0 and e2.heroes == _econ_starters(), "rev 23: a v11 save without the recruit state is corrupt (defaults)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	e.save_path = ""
	# 서버 응답: 첫 반영은 접속(알림 없음), 그 뒤 레벨이 오르면 알림·시그널. 형이 틀리면 거부
	var o = _econ(1000.0)
	var o_ups := []
	o.gacha_leveled.connect(func(l): o_ups.append(l))
	var reply := {"player": {"gold_tenths": 0, "stage": 1, "res": {}, "buildings": {}, "diamonds": 2700,
		"gacha": {"gold_level": 4, "gold_pulls": 12, "gold_next": 120, "dia_pity": 37}}, "merchant": {"rates": {"wood": 1.0, "stone": 1.0, "food": 1.0}, "next_change": 3600.0}}
	check(o.apply_server(reply) and o.diamonds == 2700 and o.gacha_state().gold_level == 4 and o.gacha_gold_pulls == 12 and o.gacha_state().pity_left == 13 and o_ups.is_empty(),
		"rev 23: apply_server takes diamonds and the recruit state (first sync is not a level-up)")
	reply.player.gacha.gold_level = 5
	check(o.apply_server(reply) and o_ups == [5], "rev 23: a later server level-up fires gacha_leveled")
	var logged := _errors.count
	var bad: Dictionary = reply.duplicate(true)
	bad.player.diamonds = "lots"
	check(not o.apply_server(bad) and o.diamonds == 2700, "rev 23: apply_server rejects non-number diamonds")
	_errors.count = logged  # 거부는 push_error로 알린다
	o.free()
	e.free()
	e2.free()
	# 설정 검증(서버 seed와 같은 규칙): 다이아는 골드 최대 레벨보다 좋아야 한다 등
	var cases := [["gacha_dia_ssr", "0.014"], ["gacha_dia_sr", "0.095"], ["gacha_gold_ssr_step", "0.01"], ["gacha_gold_level_max", "0"],
		["gacha_gold_level_pulls", "2.5"], ["gacha_dia_pity", "0"], ["gacha_gold_cost_growth", "0.9"], ["gacha_gold_sr_step", "0.11"]]
	logged = _errors.count
	var errs := 0
	for c in cases:
		var q := _payload()
		q.config[c[0]] = c[1]
		var ok: bool = GameData.apply_remote(q)
		check(not ok and GameData.errors == 1, "rev 23: config %s = %s is rejected with one error (got %d)" % [c[0], c[1], GameData.errors])
		errs += GameData.errors
	check(_errors.count - logged == errs, "rev 23: each rejected recruit config reports through push_error")
	_errors.count = logged
	GameData.load_tables()
	check(GameData.errors == 0 and GameData.config_num("gacha_dia_pity") == 50.0, "rev 23: default tables are back")
	# 다이아 아이콘·HUD 칩 종류
	check(IconsScript.KINDS == ["gold", "wood", "stone", "food", "diamond"] and IconsScript.shapes("diamond").size() >= 6, "rev 23: a diamond icon and a fifth resource chip kind")
	# 스냅 API(공용 scene_snap): 헤드리스는 자리표시, 렌더러가 있으면 키 아트를 크기·데우기 프레임과 함께 한 번 큐에 넣고 뷰포트 안에서 build
	var snapper = SceneSnap.new()
	SceneSnap.current = snapper  # node()가 루트에 새로 만들지 않게
	check(SceneSnap.snap(RecruitArt.KEY, RecruitArt.SIZE, RecruitArt.build, RecruitArt.WARM) == SceneSnap.placeholder() and snapper.queue.is_empty(),
		"rev 23: headless, the key art is the shared placeholder (nothing queued)")
	snapper.can_render = true  # 렌더러가 있는 척 — 큐·장면만 본다
	SceneSnap.snap(RecruitArt.KEY, RecruitArt.SIZE, RecruitArt.build, RecruitArt.WARM)
	check(snapper.queue.size() == 1 and snapper.queue[0].size == Vector2i(1264, 600) and snapper.queue[0].warm == RecruitArt.WARM,
		"rev 23: the key art queues once at 2x (1264 x 600) with its warm frames")
	snapper._process(0.016)
	check(snapper.busy == RecruitArt.KEY and snapper._vp.get_child(0).get_node_or_null("Ignis") != null, "rev 23: scene_snap builds the key art inside its viewport")
	SceneSnap.current = null
	snapper.free()
	# 키 아트 노드 구조
	var root := Node3D.new()
	RecruitArt.build(root)
	var names := ["Environment", "Camera", "KeyLight", "RimLight", "FireLight", "Backdrop", "Pedestal", "PedestalGlow", "Pillar", "Ignis", "Fireball", "Shards", "Embers"]
	check(names.all(func(n): return root.get_node_or_null(n) != null), "rev 23: key art builds %s: %s" % [names, root.get_children().map(func(c): return c.name)])
	var cam: Camera3D = root.get_node("Camera")
	var ignis = root.get_node("Ignis")
	var ball: Node3D = root.get_node("Fireball")
	var fwd := -cam.transform.basis.z
	var to_ball := (ball.position - cam.position).normalized()
	check(ignis.get_script() == preload("res://scripts/unit_model.gd") and ignis._spec.scene == Art.hero_spec(GameData.hero("ignis")).scene and ignis.manual,
		"rev 23: Ignis is the hero model (hero look), posed by hand (manual animation)")
	check(cam.current and fwd.y > 0.0 and rad_to_deg(fwd.angle_to(to_ball)) < cam.fov / 2.0 and ball.position.z > ignis.position.z,
		"rev 23: low heroic angle (camera looks up), the fireball is in front of Ignis and in view")
	var rim: OmniLight3D = root.get_node("RimLight")
	check(rim.position.z < ignis.position.z and rim.position.y > 2.0 and ball.get_node("Core").mesh.get_faces().size() == 20 * 3 and ball.get_node("Shell").mesh.get_faces().size() == 20 * 3,
		"rev 23: rim light from behind and above; the fireball is a 20-face icosahedron (core + shell)")
	root.free()


## 영웅 장비 칸 빨간 점(사용자 요청): 그 부위에 아무도 안 낀, 지금보다 점수 높은 장비가 있으면 true. 무기는 그 영웅 모델 종류만.
func test_equip_upgrade_dot() -> void:
	var e = _econ(Time.get_unix_time_from_system())
	e.bag = [{"id": 1, "slot": "hat", "weapon_kind": null, "grade": "N", "level": 1}, {"id": 2, "slot": "hat", "weapon_kind": null, "grade": "SR", "level": 1},
		{"id": 3, "slot": "weapon", "weapon_kind": "axe", "grade": "SSR", "level": 1}]
	e.next_item_id = 4
	check(e.equip_upgrade_available("hans", "hat") and not e.equip_upgrade_available("hans", "weapon") and e.equip_upgrade_available("dorik", "weapon")
		and not e.equip_upgrade_available("hans", "top") and not e.equip_upgrade_available("kyle", "hat"),
		"dot: empty hat slot with a hat in the bag; Knight can't use an axe; Barbarian can; no top items; unowned hero none")
	e.equipment = {"hans": {"hat": 2}}
	check(not e.equip_upgrade_available("hans", "hat") and not e.equip_upgrade_available("nina", "hat") == false,
		"dot: wearing the best hat hides it; another hero still sees the unequipped N hat (the SR one is taken)")
	e.equipment = {"hans": {"hat": 1}}
	check(e.equip_upgrade_available("hans", "hat"), "dot: a better unequipped hat (SR over N) shows the dot")
	e.free()



## 개정 23 영웅 생김새: 22명 모두 생김새가 있고 (모델·팔레트·머리·등·무기·크기) 묶음의 해시가 서로 다르다. 같은 모델끼리는
## 팔레트·머리·무기 중 둘 이상이 다르다. 머리 = 머리 뼈 부품 + 벗긴 모자·투구, 등 = 가슴 부품 + 벗긴 망토, 무기 = gear + swap + 손 부품.
## KayKit 생김새(Art.meshy_bodies = false일 때 돌아가는 모습)를 본다 — Meshy 몸은 영웅마다 제 파일이다(test_meshy_bodies).
func test_hero_looks_unique() -> void:
	Art.meshy_bodies = false
	var heroes: Array = GameData.heroes()
	check(heroes.size() == 36 and heroes.all(func(h): return Art.HERO_LOOKS.has(h.id)), "every hero has a look (%d heroes)" % heroes.size())
	var seen := {}
	var looks := {}
	for h in heroes:
		var t := _look_tuple(h)
		looks[h.id] = t
		var key := var_to_str([h.model, t.palette, t.head, t.back, t.weapon, t.scale]).hash()
		check(not seen.has(key), "%s has its own look (same tuple as %s)" % [h.id, seen.get(key, "")])
		seen[key] = h.id
	for i in heroes.size():
		for j in range(i + 1, heroes.size()):
			var a: Dictionary = heroes[i]
			var b: Dictionary = heroes[j]
			if a.model != b.model:
				continue
			var ta: Dictionary = looks[a.id]
			var tb: Dictionary = looks[b.id]
			var diff := int(ta.palette != tb.palette) + int(ta.head != tb.head) + int(ta.weapon != tb.weapon)
			check(diff >= 2, "%s vs %s (both %s) differ in %d of palette / headgear / weapon, need 2" % [a.id, b.id, a.model, diff])
	Art.meshy_bodies = true


func _look_tuple(h: Dictionary) -> Dictionary:
	var spec := Art.hero_spec(h)
	var cells: Array = spec.palette.keys()
	cells.sort()
	var head := []
	var back := []
	var hand := []
	for p in spec.parts:
		if p[0] == "head":
			head.append(p[1])
		elif String(p[0]).begins_with("handslot"):
			hand.append(p[1])
		else:
			back.append(p[1])
	for m in Art.HERO_LOOKS[h.id].get("hide", []):
		if String(m).ends_with("Cape"):
			back.append(m)
		else:
			head.append(m)
	head.sort()
	back.sort()
	var swap: Dictionary = spec.swap
	var sw: Array = swap.keys().map(func(g): return "%s>%s" % [g, swap[g]])
	sw.sort()
	return {"palette": ",".join(cells.map(func(c): return "%d:%s" % [c, (spec.palette[c] as Color).to_html()])), "head": head,
		"back": back, "weapon": [h.gear, sw, hand], "scale": snappedf(spec.body_scale, 0.001)}


## 생김새 빌더(UnitModel.dress, 성·던전·피규어·줄 세우기 공통): 영웅마다 부품이 적힌 뼈의 BoneAttachment3D 아래(이름 = id, 공유 정점 색 재질),
## swap gear는 숨고 그 손 슬롯에 코드 무기, 벗긴 모자는 숨고 나머지 gear는 보이며, 몸 크기 = scale(±10%), 텍스처 표면은 전부 그 영웅의
## 8×4 칸 색표 재질(팔레트 칸만 알파 1). 같은 영웅 = 같은 재질(캐시), 영웅끼리 다르다. 부품 메시는 id마다 하나. 셰이더가 remap 유니폼과 함께 컴파일된다.
func test_hero_look_builder() -> void:
	MeshMergeScript.enabled = false  # 부위 메시를 이름으로 본다 — 합치기 전 모습(합치기는 test_mesh_merge)
	const UnitModelScript := preload("res://scripts/unit_model.gd")
	const HeroKit := preload("res://scripts/hero_kit.gd")
	for sh in [Art.LOWPOLY_SHADER, Art.LOWPOLY_DOUBLE_SHADER]:
		var names: Array = (sh as Shader).get_shader_uniform_list().map(func(u): return u.name)
		check(names.has("use_remap") and names.has("remap_tex") and names.has("albedo_tex"), "%s compiles with the remap uniforms: %s" % [sh.resource_path, names])
	var used := {}
	for h in GameData.heroes():
		var spec := Art.hero_spec(h)
		var model: Node3D = Art.instance(spec.scene)
		UnitModelScript.dress(model, spec)
		var found := []
		for ba in model.find_children("*", "BoneAttachment3D", true, false):
			for c in ba.get_children():
				if HeroKit.has_part(String(c.name)):
					found.append([String(ba.bone_name), String(c.name)])
					check(c is MeshInstance3D and c.mesh != null and c.mesh.get_surface_count() == 1 and c.material_override == Art.style_material(Art.lowpoly_vc_material()),
						"%s part %s is a shared vertex-color mesh (its unit-style material, shared)" % [h.id, c.name])
					used[String(c.name)] = true
		var want: Array = spec.parts.duplicate()
		for g in spec.swap:
			var gear := model.find_child(g, true, false) as Node3D
			check(gear != null and not gear.visible, "%s swaps out %s" % [h.id, g])
			want.append([String((gear.get_parent() as BoneAttachment3D).bone_name), spec.swap[g]])
		found.sort()
		want.sort()
		check(found == want, "%s: parts on their bones %s (want %s)" % [h.id, found, want])
		for m in Art.HERO_LOOKS[h.id].get("hide", []):
			check(not (model.find_child(m, true, false) as Node3D).visible, "%s takes off %s" % [h.id, m])
		for g in h.gear.split("|"):
			check(spec.swap.has(g) or (model.find_child(g, true, false) as Node3D).visible, "%s still shows gear %s" % [h.id, g])
		check(model.scale.is_equal_approx(Vector3.ONE * spec.body_scale) and absf(spec.body_scale - 1.0) <= 0.1001,
			"%s drawn at x%.2f (within 10%%)" % [h.id, spec.body_scale])
		var tex: ImageTexture = Art.remap_texture(h.id, spec.palette)
		var img := tex.get_image()
		var ok: bool = img.get_size() == Vector2i(8, 4) and not spec.palette.is_empty()
		for cell in 32:
			var px := img.get_pixel(cell % 8, cell / 8)
			ok = ok and (px.a > 0.5) == spec.palette.has(cell) and (not spec.palette.has(cell) or px.is_equal_approx(Color(spec.palette[cell], 1.0)))
		check(ok, "%s color table: 8x4, alpha only on its %d palette cells" % [h.id, spec.palette.size()])
		var textured := 0
		var remapped := 0
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			if mi.name == Art.MESHY_BODY:
				continue  # Meshy 몸 텍스처는 칸 아틀라스가 아니다(test_meshy_bodies)
			for i in (mi as MeshInstance3D).mesh.get_surface_count():
				var m := (mi as MeshInstance3D).get_active_material(i) as ShaderMaterial
				if m != null and m.get_shader_parameter("use_texture"):
					textured += 1
					if m.get_shader_parameter("use_remap") == true and m.get_shader_parameter("remap_tex") == tex:
						remapped += 1
		check(textured > 5 and remapped == textured, "%s: all %d textured surfaces use its color table (%d)" % [h.id, textured, remapped])
		model.free()
	# 표에 있는 영웅의 생김새 부품은 모두 붙고, HeroKit 부품은 모두 어떤 생김새가 쓴다(표보다 생김새가 먼저 들어올 수 있다)
	var named := {}
	var named_listed := {}
	for id in Art.HERO_LOOKS:
		var look: Dictionary = Art.HERO_LOOKS[id]
		for p in look.get("parts", []).map(func(q): return q[1]) + look.get("swap", {}).values():
			named[p] = true
		if not GameData.hero(id).is_empty():  # 표에 있는 영웅 = 스펙이 다는 부품(Meshy 몸이면 손 부품만)
			var spec := Art.hero_spec(GameData.hero(id))
			for p in spec.parts.map(func(q): return q[1]) + spec.swap.values():
				named_listed[p] = true
	check(used.keys().all(func(p): return named_listed.has(p)) and used.size() == named_listed.size(),
		"listed heroes' parts are all built (%d / %d)" % [used.size(), named_listed.size()])
	var known: Array = HeroKit.PARTS  # 람다에선 함수 지역 상수가 안 보인다
	check(named.size() == known.size() and named.keys().all(func(p): return known.has(p)),
		"every HeroKit part is used by some look (%d / %d)" % [named.size(), HeroKit.PARTS.size()])
	var body := func(id: String) -> Material:
		var spec := Art.hero_spec(GameData.hero(id))
		var m: Node3D = Art.instance(spec.scene)
		preload("res://scripts/unit_model.gd").dress(m, spec)  # 람다에선 함수 지역 상수가 안 보인다
		var mat := (m.find_child("Knight_Body", true, false) as MeshInstance3D).get_active_material(0)
		m.free()
		return mat
	check(body.call("arteon") == body.call("arteon") and body.call("arteon") != body.call("bron"), "a hero's skin material is cached; two heroes differ")
	var p1: MeshInstance3D = HeroKit.part("lumina_halo")
	var p2: MeshInstance3D = HeroKit.part("lumina_halo")
	check(p1.mesh == p2.mesh and p1 != p2, "part meshes are built once per id")
	p1.free()
	p2.free()
	MeshMergeScript.enabled = true


## Meshy 몸(docs/meshy-assets.md, Art.MESHY_HERO_DIR): 파일이 있는 영웅만 spec.body = 그 파일이고 부품은 손 부품만(머리·가슴 장식은 몸에 있다).
## 입히면 KayKit 몸(손 슬롯 밖 메시 전부)은 숨고 스켈레톤 아래 MESHY_BODY 하나가 보인다 — KayKit 몸과 같은 Skin·변환(같은 뼈 번호),
## 삼각형 5천 이하, 칸 색표 없이 자기 텍스처, 무기(gear)는 그대로. 파일의 Skin bind도 KayKit과 같다(이름·뼈·자세). 영웅 전원이 Meshy 몸. 끄면 KayKit 생김새.
## 2026-10-06: 근접 영웅·보스 평타 모션은 3가지 이상(원거리 영웅은 하나)(모델에 있고 타격 비율이 있다), 무작위로 고르되 바로 앞 것은 다시 고르지 않는다.
## 병사·일반 몬스터는 하나(골렘 조각은 둘 그대로). 보스는 휘두르던 모션이 끝날 때까지 is_busy.
func test_attack_sets() -> void:
	const UnitModelScript := preload("res://scripts/unit_model.gd")
	var specs := {}
	for h in GameData.heroes():
		specs["hero:" + h.id] = Art.hero_spec(h)
	for k in GameData.BOSS_LOOKS + ["goblin_king", "death_knight", "rock_golem"]:
		specs["boss:" + k] = Art.monster_spec(k)
	var players := {}
	for key in specs:
		var spec: Dictionary = specs[key]
		var list: Array = spec.get("attacks", [])
		if not players.has(spec.scene):
			var m := Art.instance(spec.scene)
			players[spec.scene] = [m, m.find_children("*", "AnimationPlayer", true, false)[0]]
		var ap: AnimationPlayer = players[spec.scene][1]
		var ranged: bool = key.begins_with("hero:") and GameData.hero(key.substr(5)).role == "ranged"
		var ok: bool = (list == [spec.anims.attack] if ranged else list.size() >= 3 and (key.begins_with("boss:") or list[0] == spec.anims.attack))
		for a in list:
			ok = ok and ap.has_animation(a) and Art.HIT_FRAC.has(a) and ap.get_animation(a).loop_mode == Animation.LOOP_NONE
		check(ok, "%s: 3+ attack motions (ranged heroes: one) in the model with hit timing %s" % [key, list])
	for s in players:
		players[s][0].free()
	check(not Art.soldier_spec("infantry", "Knight").has("attacks") and not Art.monster_spec("grunt").has("attacks"), "soldiers and regular monsters keep one attack")
	var last := -1
	var seen := {}
	var repeat := false
	for i in 300:
		var j := UnitModelScript.pick_next(3, last)
		repeat = repeat or j == last
		seen[j] = true
		last = j
	check(not repeat and seen.size() == 3 and UnitModelScript.pick_next(1, 0) == 0, "random pick never repeats the last motion and uses all 3")


func test_meshy_bodies() -> void:
	MeshMergeScript.enabled = false
	const UnitModelScript := preload("res://scripts/unit_model.gd")
	var n := 0
	for h in GameData.heroes():
		var spec := Art.hero_spec(h)
		var path: String = Art.MESHY_HERO_DIR + h.id + ".glb"
		check(spec.has("body") == ResourceLoader.exists(path), "%s has a Meshy body iff %s exists" % [h.id, path])
		if not spec.has("body"):
			continue
		n += 1
		check(spec.body == path and spec.parts.all(func(p): return String(p[0]).begins_with("handslot")),
			"%s: Meshy body, hand parts only %s" % [h.id, spec.parts])
		var model: Node3D = Art.instance(spec.scene)
		UnitModelScript.dress(model, spec)
		var skel := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var body := skel.get_node_or_null(NodePath(Art.MESHY_BODY)) as MeshInstance3D
		var kay: MeshInstance3D = null
		var hidden := true
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var slot := mi.get_parent() as BoneAttachment3D
			if mi == body or (slot != null and String(slot.bone_name).begins_with("handslot")):
				continue
			hidden = hidden and not mi.visible
			if kay == null and mi.skin != null:
				kay = mi
		check(body != null and kay != null and body.visible and body.skin == kay.skin and body.transform == kay.transform and hidden,
			"%s wears its Meshy body on the KayKit skin, KayKit body hidden" % h.id)
		if body == null:
			model.free()
			continue
		var tris: int = body.mesh.get_faces().size() / 3
		check(tris > 1000 and tris <= 5000, "%s Meshy body within 5,000 triangles (%d)" % [h.id, tris])
		var m := body.get_active_material(0) as ShaderMaterial
		check(m != null and m.get_shader_parameter("use_texture") and m.get_shader_parameter("use_remap") != true,
			"%s Meshy body draws its own texture (no color table)" % h.id)
		for g in h.gear.split("|"):
			check(spec.swap.has(g) or (model.find_child(g, true, false) as Node3D).visible, "%s still holds %s" % [h.id, g])
		var src := Art.instance(path)
		var own := (src.find_child(Art.MESHY_BODY, true, false) as MeshInstance3D).skin
		var same: bool = own.get_bind_count() == kay.skin.get_bind_count()
		for i in mini(own.get_bind_count(), kay.skin.get_bind_count()):
			same = same and own.get_bind_name(i) == kay.skin.get_bind_name(i) and own.get_bind_bone(i) == kay.skin.get_bind_bone(i) \
				and own.get_bind_pose(i).is_equal_approx(kay.skin.get_bind_pose(i))
		check(same, "%s body file binds match the %s skin" % [h.id, h.model])
		src.free()
		model.free()
	check(n == GameData.heroes().size(), "every hero has a Meshy body (%d of %d)" % [n, GameData.heroes().size()])
	Art.meshy_bodies = false
	check(not Art.hero_spec(GameData.hero("arteon")).has("body"), "meshy_bodies off: back to the KayKit look")
	Art.meshy_bodies = true
	MeshMergeScript.enabled = true


## 던전 적 Meshy 몸(Art.monster_spec): 고블린·고블린 왕·데스나이트는 KayKit 뼈대에 Meshy 몸을 입고 몸 색(tint)·머리·가슴 부품은 빠지며
## 손 부품(곤봉·대검)과 KayKit 단검은 남는다. 성 몬스터(grunt·epic_boss)는 그대로. meshy_bodies = false면 MONSTER_MODELS 그대로.
func test_meshy_enemies() -> void:
	MeshMergeScript.enabled = false
	const UnitModelScript := preload("res://scripts/unit_model.gd")
	for kind in ["goblin", "goblin_king", "death_knight", "zombie", "lizardman", "werewolf", "imp", "ratman", "mushroom", "frost_troll",
			"ogre_warlord", "demon_lord", "minotaur", "rock_golem", "golemite"]:
		var spec := Art.monster_spec(kind)
		check(spec.get("body", "") == Art.MESHY_ENEMY_DIR + str(Art.MONSTER_MODELS[kind].get("meshy", kind)) + ".glb" and not spec.has("tint")
			and spec.parts.all(func(p): return String(p[0]).begins_with("handslot")), "%s: Meshy body, hand parts only %s" % [kind, spec.get("parts")])
		var model: Node3D = Art.instance(spec.scene)
		UnitModelScript.dress(model, spec)
		var skel := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var body := skel.get_node_or_null(NodePath(Art.MESHY_BODY)) as MeshInstance3D
		var tris: int = body.mesh.get_faces().size() / 3 if body != null else 0
		check(body != null and body.visible and tris > 1000 and tris <= 5000, "%s wears a Meshy body within 5,000 triangles (%d)" % [kind, tris])
		model.free()
	check((Art.monster_spec("goblin").hide as Array).has("Knife_Offhand") and not (Art.monster_spec("goblin").hide as Array).has("Knife"),
		"goblins still hold the KayKit knife")
	check(Art.monster_spec("grunt") == Art.MONSTER_MODELS.grunt and Art.monster_spec("epic_boss") == Art.MONSTER_MODELS.epic_boss,
		"castle monsters keep the KayKit skeletons")
	Art.meshy_bodies = false
	check(Art.monster_spec("death_knight") == Art.MONSTER_MODELS.death_knight, "meshy_bodies off: dungeon enemies back to KayKit")
	Art.meshy_bodies = true
	MeshMergeScript.enabled = true


## 피규어(목록·상세 미리보기·모집 결과 카드)도 같은 생김새: Portraits.spec_of("hero:id") == Art.hero_spec — 팔레트·부품·swap·크기까지. 병사는 그대로.
func test_portrait_looks() -> void:
	for h in GameData.heroes():
		var s: Dictionary = PortraitsScript.spec_of("hero:" + h.id)
		var look: Dictionary = Art.HERO_LOOKS[h.id]
		var parts: Array = look.get("parts", [])
		if s.has("body"):
			parts = parts.filter(func(p): return String(p[0]).begins_with("handslot"))
		check(s == Art.hero_spec(h) and s.look == h.id and s.palette == Art.look_cells(h.model, look.palette) and s.parts == parts
			and s.swap == look.get("swap", {}) and s.body_scale == look.get("scale", 1.0), "portrait of %s carries its look" % h.id)
	check(not Art.soldier_spec("infantry", "Knight").has("palette") and not PortraitsScript.spec_of("soldier:archer").has("palette"),
		"soldiers keep the plain model (no hero look)")


## 장면 스냅샷(scene_snap): 헤드리스는 자리표시만, 요청은 키마다 한 번(순서·크기·데울 프레임), 렌더 중인 키는 다시 넣지 않음,
## 끝난 렌더는 정적 캐시 + snap_ready. 던전 띠 장면(dungeon_snaps)은 카메라·조명과 모델을 넣고, 모든 모델이 카메라 앞 띠 폭 안에 선다.
func test_scene_snap() -> void:
	const S := preload("res://scripts/scene_snap.gd")
	const DungeonSnaps := preload("res://scripts/dungeon_snaps.gd")
	var unit_script := preload("res://scripts/unit_model.gd")  # 람다가 지역 상수를 못 본다
	var p = S.new()
	S.current = p  # node()가 루트에 새로 만들지 않게
	var built := []
	var b := func(root: Node3D): built.append(root)
	var ph: Texture2D = S.snap("t:a", Vector2i(64, 16), b)
	check(not p.can_render and p.queue.is_empty() and ph == S.placeholder() and ph.get_height() == 16 and S.cached("t:a") == null and built.is_empty(),
		"scene snap headless: nothing queued, the shared placeholder comes back, nothing cached")
	p.can_render = true  # 렌더러가 있는 척 — 큐·캐시만 본다
	for k in ["t:a", "t:b", "t:a"]:
		S.snap(k, Vector2i(64, 16), b, 5)
	check(p.queue.map(func(q): return q.key) == ["t:a", "t:b"] and p.queue[0].warm == 5 and p.queue[0].size == Vector2i(64, 16),
		"scene snap: requests queue once per key, in order, with size and warm frames")
	p._process(0.016)
	S.snap("t:a", Vector2i(64, 16), b)
	check(p.busy == "t:a" and built.size() == 1 and built[0].get_parent() == p._vp and p._vp.size == Vector2i(64, 16) and p._vp.world_3d != null
		and p.queue.map(func(q): return q.key) == ["t:b"], "scene snap: one render at a time in its own world; the busy key is not queued again")
	for i in 5:
		p._on_drawn()
	check(p._left == 0 and p.busy == "t:a", "scene snap: warm frames count down before the capture")
	var got := []
	p.snap_ready.connect(func(k): got.append(k))
	var tex := ImageTexture.create_from_image(Image.create_empty(4, 4, false, Image.FORMAT_RGBA8))
	p.store("t:a", tex)
	S.snap("t:a", Vector2i(64, 16), b)
	check(got == ["t:a"] and S.cached("t:a") == tex and S.snap("t:a", Vector2i(64, 16), b) == tex and p.queue.size() == 1,
		"scene snap: a finished render is cached, fires snap_ready(key) and is not queued again")
	S.current = null
	p.free()
	check(S.cached("t:a") == tex, "scene snap: the cache is static (outlives the node)")
	S._cache.erase("t:a")
	for t in ["gold", "equip"]:
		var root := Node3D.new()
		DungeonSnaps.build(root, t, ["arteon", "nobody", "hans", "ignis", "kyle"])
		var cams := root.find_children("*", "Camera3D", true, false)
		var units := root.find_children("*", "", true, false).filter(func(n): return n.get_script() == unit_script)
		var cam: Camera3D = cams[0]
		var half_w := tan(deg_to_rad(cam.fov / 2.0)) * DungeonSnaps.SIZE.aspect()  # 가로 반 화각 tan(세로 화각 기준)
		var inside := true
		for u in units:
			var l: Vector3 = cam.transform.affine_inverse() * (u.position + Vector3(0, 1.0, 0))
			inside = inside and l.z < -1.0 and absf(l.x / -l.z) < half_w * 0.95
		check(cams.size() == 1 and root.find_children("*", "WorldEnvironment", true, false).size() == 1 and units.size() == (11 if t == "gold" else 4) and inside,
			"%s band scene: one camera, the arena lighting, %d models (3 heroes; unknown id skipped), all in front of the camera inside the band width" % [t, units.size()])
		root.free()


# --- 겹침 해소(crowd.gd) ---
const CrowdScript := preload("res://scripts/crowd.gd")


## 한 번 해소(층 lv, 아레나 = half < 0). mv = 이번 프레임 제 걸음(없으면 모두 제자리).
func _crowd_run(half: float, pts: Array, radii: Array, w: Array, lv: Array, mv := []) -> PackedVector2Array:
	var c = CrowdScript.new()
	c.half = half
	var steps := PackedVector2Array(mv)
	steps.resize(pts.size())
	var out: PackedVector2Array = c.separate(PackedVector2Array(pts), PackedFloat32Array(radii), PackedFloat32Array(w), PackedInt32Array(lv), steps)
	c.free()
	return out


func test_crowd() -> void:
	GameData.load_tables()
	# 근접 사거리(중심 거리)는 맞닿는 거리(반지름 합) + 0.1보다 길다 — 밀려 붙어도 친다(사거리 판정은 그대로라 밸런스 유지)
	var hero_r := CrowdScript.HUMAN_R * Art.CHARACTER_SCALE
	var foot_r := hero_r * Art.SOLDIER_SCALE
	var castle_kinds := {"grunt": GameData.monster("grunt"), "epic_boss": GameData.monster("epic_boss")}
	var short := []
	for kind in castle_kinds:
		var m: Dictionary = castle_kinds[kind]
		var mr: float = CrowdScript.MONSTER_R[kind] * float(m.scale)
		for h in GameData.heroes():
			if h.role == "melee" and float(h.range) < hero_r + mr + 0.1:
				short.append("%s vs %s" % [h.id, kind])
		for s in GameData.soldiers():
			var sr: float = CrowdScript.CAVALRY_R if s.id == "cavalry" else foot_r
			if float(s.range) < 3.0 and float(s.range) < sr + mr + 0.1:
				short.append("%s vs %s" % [s.id, kind])
			if float(m.range) < sr + mr + 0.1:
				short.append("%s vs %s" % [kind, s.id])
		if float(m.range) < hero_r + mr + 0.1:
			short.append("%s vs hero" % kind)
	for type in GameData.DUNGEON_TYPES:
		for row in GameData.dungeon_rows(type):
			var mr: float = CrowdScript.MONSTER_R[row.kind] * float(row.scale)
			if float(row.range) < hero_r + mr + 0.1:
				short.append("%s vs hero" % row.kind)
			for h in GameData.heroes():
				if h.role == "melee" and float(h.range) < hero_r + mr + 0.1:
					short.append("%s vs %s" % [h.id, row.kind])
	check(short.is_empty(), "every melee range reaches past contact distance (radius sum + 0.1): %s" % [short])
	check(is_equal_approx(CrowdScript.MONSTER_R.grunt * float(castle_kinds.grunt.scale), 0.4) and CrowdScript.MONSTER_R.epic_boss * float(castle_kinds.epic_boss.scale) > 0.75,
		"radii: grunt 0.4, epic boss ~0.8 (x model scale)")
	# 같은 자리 둘 → 반지름 합만큼 떨어진다. 무게 역수로 나눈다(가벼운 쪽이 4배 더), 처리가 꺼진(w 0) 유닛은 안 밀린다, 다른 층끼리는 안 부딪는다
	var q := _crowd_run(-1.0, [Vector2(1, 1), Vector2(1, 1)], [0.4, 0.4], [1.0, 1.0], [0, 0])
	check(absf(q[0].distance_to(q[1]) - 0.8) < 0.001, "two units on one spot end a radius sum apart (%.3f)" % q[0].distance_to(q[1]))
	q = _crowd_run(-1.0, [Vector2(0, 0), Vector2(0.4, 0)], [0.4, 0.4], [4.0, 1.0], [0, 0])
	check(q[0].is_equal_approx(Vector2(-0.32, 0)) and q[1].is_equal_approx(Vector2(0.48, 0)), "the push splits by inverse mass (light moves 0.32, heavy 0.08): %s" % [q])
	q = _crowd_run(-1.0, [Vector2(0, 0), Vector2(0.4, 0)], [0.4, 0.4], [0.0, 1.0], [0, 0])
	check(q[0] == Vector2.ZERO and q[1].is_equal_approx(Vector2(0.8, 0)), "an immovable unit (w 0) stays, the other takes the whole push")
	# 정면으로 마주 걸어 부딪치면 서로 옆으로 비킨다(같은 줄에서 막혀 멈추지 않는다). 길목에 선 유닛에 걸어 들어가도 옆으로 돈다
	q = _crowd_run(-1.0, [Vector2(0, 0), Vector2(0.6, 0)], [0.4, 0.4], [1.0, 1.0], [0, 0], [Vector2(0.05, 0), Vector2(-0.05, 0)])
	check(q[0].y * q[1].y < 0.0 and absf(q[0].y) > 0.05, "head-on walkers sidestep to opposite sides: %s" % [q])
	q = _crowd_run(-1.0, [Vector2(0, 0), Vector2(0.6, 0)], [0.4, 0.4], [1.0, 0.0], [0, 0], [Vector2(0.05, 0), Vector2.ZERO])
	check(absf(q[0].y) > 0.05 and q[1] == Vector2(0.6, 0), "a walker that bumps a unit standing in its line slides around it: %s" % [q])
	q = _crowd_run(-1.0, [Vector2(0, 0), Vector2(0.2, 0)], [0.4, 0.4], [1.0, 1.0], [0, 1])
	check(q[0] == Vector2.ZERO and q[1] == Vector2(0.2, 0), "ground and wall-top units do not push each other")
	var c = CrowdScript.new()
	c.arena_r = 10.0
	q = c.separate(PackedVector2Array([Vector2(9.9, 0), Vector2(9.5, 0)]), PackedFloat32Array([0.4, 0.4]), PackedFloat32Array([1.0, 0.0]), PackedInt32Array([0, 0]),
		PackedVector2Array([Vector2.ZERO, Vector2.ZERO]))
	c.free()
	check(q[0].length() <= 10.001, "arena: a push never leaves the arena radius (%.2f)" % q[0].length())
	# 성 전장: 밀림은 성벽·성문을 넘기지 않는다
	var half := GameData.interior_half(1)
	var outer := half + Balance.WALL_T
	q = _crowd_run(half, [Vector2(0, -(outer + 0.1)), Vector2(0.1, -(outer + 0.5))], [0.4, 0.4], [1.0, 0.0], [0, 0])
	check(not FormationScript.is_inside(half, Vector3(q[0].x, 0, q[0].y)), "a monster pressed against the closed north gate is not pushed through it: %s" % q[0])
	q = _crowd_run(half, [Vector2(6, -(outer + 0.1)), Vector2(6.1, -(outer + 0.5))], [0.4, 0.4], [1.0, 0.0], [0, 0])
	check(not FormationScript.is_inside(half, Vector3(q[0].x, 0, q[0].y)), "nor through the wall beside it")
	q = _crowd_run(half, [Vector2(6, -(half - 0.1)), Vector2(6.1, -(half - 0.5))], [0.45, 0.45], [1.0, 0.0], [0, 0])
	check(maxf(absf(q[0].x), absf(q[0].y)) < half, "an inside unit is not pushed into the wall: %s" % q[0])
	q = _crowd_run(half, [Vector2(1.8, -(half + 1.0)), Vector2(1.4, -(half + 1.0))], [0.45, 0.45], [1.0, 0.0], [0, 0])
	check(absf(q[0].x) <= Balance.GATE_W / 2.0 + 0.001 and FormationScript.is_inside(half, Vector3(q[0].x, 0, q[0].y)), "a unit in the gate passage stays inside the gate width: %s" % q[0])
	var wall := -(half + Balance.WALL_T / 2.0)
	q = _crowd_run(half, [Vector2(4.0, wall), Vector2(4.1, wall + 0.2)], [0.45, 0.45], [1.0, 0.0], [1, 1])
	check(absf(q[0].y - wall) <= FormationScript.WALK_HALF + 0.001 and q[0].distance_to(q[1]) > 0.85,
		"a wall-top unit shoved off the walk stops at its edge (center line +-0.55 m) and slides along: %s" % [q])
	q = _crowd_run(half, [Vector2(4.0, wall + 0.4), Vector2(4.1, wall + 0.5)], [0.45, 0.45], [0.0, 1.0], [1, 1])
	check(absf(q[1].y - wall) <= FormationScript.WALK_HALF + 0.001 and absf(q[1].x - 4.0) > 0.5,
		"pushed toward the inner edge, it moves along the wall instead of falling off: %s" % [q])
	var lim := half + Balance.WALL_T / 2.0 - Balance.TOWER_SIZE / 2.0
	q = _crowd_run(half, [Vector2(lim - 0.1, wall), Vector2(lim - 0.4, wall)], [0.45, 0.45], [1.0, 0.0], [1, 1])
	check(q[0].x <= lim + 0.001, "and never past the corner tower (%.2f <= %.2f)" % [q[0].x, lim])
	q = _crowd_run(half, [Vector2(0, 4.2), Vector2(0.1, 4.5)], [0.4, 0.4], [1.0, 0.0], [0, 0])
	check(q[0].y >= 3.999, "a unit is not pushed into the keep plot (z %.2f >= 4)" % q[0].y)
	# 200 유닛(30 m 사각형, 빽빽함): 시간을 찍고 수 ms 안(느슨한 확인). 한 번에 겹침이 크게 준다
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pts := []
	var radii := []
	var ws := []
	var lvs := []
	for i in 200:
		pts.append(Vector2(rng.randf_range(-15.0, 15.0), rng.randf_range(-15.0, 15.0)))
		radii.append(rng.randf_range(0.35, 0.8))
		ws.append(1.0 / CrowdScript.mass(radii[i], rng.randf() < 0.5))
		lvs.append(0)
	var t0 := Time.get_ticks_usec()
	q = _crowd_run(-1.0, pts, radii, ws, lvs)
	var usec := Time.get_ticks_usec() - t0
	var before := _worst_overlap(PackedVector2Array(pts), radii)
	for k in 9:  # 프레임마다 한 번씩 10프레임
		q = _crowd_run(-1.0, Array(q), radii, ws, lvs)
	var after := _worst_overlap(q, radii)
	print("crowd: 200 units resolved in %.2f ms (worst overlap %.0f%% -> %.1f%% after 10 frames)" % [usec / 1000.0, before * 100.0, after * 100.0])
	check(usec < 8000, "200 units resolve in a few ms headless (%.2f ms)" % [usec / 1000.0])
	check(after < 0.05, "a dense random pile spreads within 10 frames (worst overlap %.2f -> %.3f of the radius sum)" % [before, after])


## 가장 큰 겹침 / 반지름 합(0 = 안 겹침).
func _worst_overlap(p: PackedVector2Array, radii: Array) -> float:
	var worst := 0.0
	for i in p.size():
		for j in range(i + 1, p.size()):
			var s: float = radii[i] + radii[j]
			worst = maxf(worst, (s - p[i].distance_to(p[j])) / s)
	return worst



## 개정 24 연구: 표(22행·파일 순서·빈 선행), 비용·시간·속도 공식(서버 research.test와 같은 값), 효과 합(같은 효과끼리 더함·최대로 자름),
## 잠금·이유 코드 순서, 오프라인 시작(즉시 차감)·한 번에 하나·게으른 완료·취소 환불·다이아 즉시 완료, 서버 권위 효과의 오프라인 반영
## (생산·건설·판매·처치 골드·훈련 시간·비용·인구)과 성·성문 HP·병종 배율, 저장 v12 왕복·v11 → v12·깨진 v12, 서버 응답(research), 아이콘.
## 무료 즉시 완료(사용자 2026-10-06, 오프라인): 남은 시간이 5분(free_finish_sec) 이하인 건설·훈련은 [무료 즉시 완료]로 바로 끝난다.
func test_free_finish() -> void:
	GameData.load_tables()
	check(EconomyScript.free_finish_sec() == 300.0 and EconomyScript.free_finish_ok(300.0) and not EconomyScript.free_finish_ok(300.5) and not EconomyScript.free_finish_ok(0.0),
		"free finish window: 0 < left <= 300 s")
	var t := Time.get_unix_time_from_system()
	var e = _econ(t)
	var built := []
	e.building_done.connect(func(id, lv): built.append([id, lv]))
	e.res = {"wood": 100000, "stone": 100000, "food": 100000}
	e.build = {"id": "keep", "finish": e.time_now() + 600.0}
	check(not e.can_free_build(e.time_now()) and not e.free_finish_build() and e.building_level("keep") == 1, "10 min left: no free finish")
	e.build.finish = e.time_now() + 299.0
	var lv: int = e.building_level("keep")
	check(e.can_free_build(e.time_now()) and e.free_finish_build() and e.build.is_empty() and e.building_level("keep") == lv + 1 and built == [["keep", lv + 1]],
		"5 min or less left: free finish completes the building at once")
	e.train_queues["barracks"] = {"count": 1, "tier": 1, "finish": e.time_now() + 1000.0}
	check(not e.can_free_train("barracks") and not e.free_finish_training("barracks"), "training with 16 min left: no free finish")
	e.train_queues["barracks"].finish = e.time_now() + 120.0
	var before: int = e.soldier_counts().get("infantry:1", 0)
	check(e.can_free_train("barracks") and e.free_finish_training("barracks") and not e.train_queues.has("barracks") and e.soldier_counts().get("infantry:1", 0) == before + 1,
		"training with 2 min left: free finish collects the soldier")


func test_research_r24() -> void:
	GameData.load_tables()
	_legacy_training()
	var ids: Array = GameData.research_defs().map(func(d): return d.id)
	check(GameData.errors == 0 and ids.size() == 22 and ids[0] == "wood_tech" and ids[7] == "abundance" and ids[16] == "elite" and ids[21] == "legend_armor",
		"research.csv: 22 nodes in file order: %s" % [ids])
	var c := GameData.research_def("construct")
	var w := GameData.research_def("wood_tech")
	check(c.branch == "economy" and c.tier == 2.0 and c.req1 == "wood_tech" and c.req1_lv == 3.0 and c.req2 == "stone_tech" and c.req2_lv == 3.0 and c.lab_req == 3.0
		and w.req1 == "" and w.req1_lv == 0.0 and w.req2 == "", "construct needs wood/stone tech Lv 3 and lab 3; empty prerequisites are \"\" / 0")
	# 비용: round(값 × 1.3^n), n = 지금 레벨(0부터). 시간: round(base × 1.35^n ÷ (1 + 속도))
	check(GameData.research_cost("wood_tech", 0) == {"wood": 1200, "stone": 800, "food": 1000, "gold": 0} and GameData.research_cost("wood_tech", 1) == {"wood": 1560, "stone": 1040, "food": 1300, "gold": 0}
		and GameData.research_cost("construct", 2) == {"wood": 6760, "stone": 5070, "food": 5915, "gold": 845} and GameData.research_cost("construct", 3) == {"wood": 8788, "stone": 6591, "food": 7690, "gold": 1099}
		and GameData.research_cost("nope", 0).is_empty(),
		"research cost = round(value x 1.3^n) (construct Lv 4: 7689.5 and 1098.5 round away from zero): %s" % [GameData.research_cost("construct", 3)])
	check(GameData.research_sec("wood_tech", 0, 0.0) == 60 and GameData.research_sec("wood_tech", 9, 0.0) == 894 and GameData.research_sec("elite", 9, 0.0) == 53617
		and GameData.research_sec("wood_tech", 0, 0.5) == 40 and GameData.research_sec("wood_tech", 1, 0.58) == 51 and GameData.research_sec("nope", 0, 0.0) == 0,
		"research time = round(base x 1.35^n / (1 + speed)): wood Lv 10 about 15 min, elite Lv 10 about 15 h, lab 30 (+58%%) 81 s -> 51 s: %s" % [[GameData.research_sec("wood_tech", 9, 0.0), GameData.research_sec("elite", 9, 0.0), GameData.research_sec("wood_tech", 1, 0.58)]])
	check(is_equal_approx(GameData.research_speed({"research_speed_pct": 30.0}, 11), 0.5) and GameData.research_speed({}, 0) == 0.0,
		"research speed = method % / 100 + 0.02 x (lab - 1)")
	var b := GameData.research_bonus({"hero_weapon": 3, "legend_weapon": 2, "wood_tech": 12, "nope": 5, "stone_tech": -2})
	check(b.size() == GameData.RESEARCH_EFFECTS.size() and b.hero_atk_pct == 17.0 and b.wood_pct == 50.0 and b.stone_pct == 0.0 and b.pop_add == 0.0,
		"bonus: same effect adds up (3 x 3 + 2 x 4 = 17), levels clamp to 0..max, unknown nodes ignored: %s" % [b])
	# 잠금·이유 코드: unknown → max_level → locked(연구소·선행) → not_enough_resources → not_enough_gold
	var rich := {"wood": 99999, "stone": 99999, "food": 99999, "gold": 9999}
	var both := {"wood_tech": 3, "stone_tech": 3}
	check(GameData.research_block("nope", {}, 30, rich) == "unknown_research" and GameData.research_block("wood_tech", {"wood_tech": 10}, 30, rich) == "max_level"
		and GameData.research_block("construct", both, 2, rich) == "locked" and GameData.research_block("construct", {"wood_tech": 3, "stone_tech": 2}, 3, rich) == "locked"
		and GameData.research_block("construct", both, 3, rich) == "" and GameData.research_block("construct", both, 3, {"wood": 4000, "stone": 3000, "food": 3499, "gold": 9999}) == "not_enough_resources"
		and GameData.research_block("construct", both, 3, {"wood": 4000, "stone": 3000, "food": 3500, "gold": 499}) == "not_enough_gold"
		and GameData.research_block("construct", both, 3, {"wood": 4000, "stone": 3000, "food": 3500, "gold": 500}) == "",
		"research_block order: unknown, max, locked (lab, prerequisite), resources, gold")
	check([0.0, 0.5, 60.0, 60.5, 3600.0].map(func(s): return GameData.research_dia_cost(s)) == [1, 1, 1, 2, 60] and GameData.research_refund({"wood": 156, "stone": 105, "food": 0, "gold": 845}) == {"wood": 78, "stone": 52, "gold": 422},
		"instant finish = max(1, ceil(left / 60)) diamonds; cancel refund = floor(cost x 0.5), zero dropped")
	# 오프라인: 시작(비용 즉시) → 한 번에 하나 → 게으른 완료(알림) → 취소 환불 → 다이아 즉시 완료
	var t := Time.get_unix_time_from_system()
	var e = _econ(t)
	var notes := []
	var done := []
	e.notice.connect(func(s): notes.append(s))
	e.research_done.connect(func(id, lv): done.append([id, lv]))
	e.res = {"wood": 10000, "stone": 10000, "food": 10000}
	e.gold = 3000
	check(e.research_available() and e.research_block("construct") == "locked" and e.research_block("wood_tech") == "", "a fresh save can research tier 1, tier 2 is locked")
	check(e.start_research("wood_tech") and e.res == {"wood": 8800, "stone": 9200, "food": 9000} and e.gold == 3000 and e.research_current.id == "wood_tech"
		and absf(e.research_left(e.time_now()) - 60.0) < 1.0 and not e.research_available(), "start: the cost leaves at once, 60 s on the clock, no bubble while busy")
	check(not e.start_research("stone_tech") and e.research_block("stone_tech") == "research_busy" and notes[-1] == EconomyScript.RESEARCH_TEXT.research_busy
		and e.res.wood == 8800 and e.research_current.id == "wood_tech", "only one research at a time: a second start is refused and costs nothing")
	e.complete_due(e.time_now() + 30.0)
	check(e.research_level("wood_tech") == 0 and not e.research_current.is_empty(), "not done before the finish time")
	e.complete_due(e.time_now() + 61.0)
	check(e.research_level("wood_tech") == 1 and e.research_current.is_empty() and done == [["wood_tech", 1]] and notes[-1] == "연구 완료: 벌목술 Lv 1",
		"lazy completion: level +1, research_done, notice '연구 완료: 벌목술 Lv 1'")
	check(e.start_research("stone_tech") and e.cancel_research() and e.res == {"wood": 8200, "stone": 8800, "food": 8500} and e.research_current.is_empty()
		and notes[-1] == EconomyScript.RESEARCH_CANCEL_TEXT and not e.cancel_research(), "cancel refunds floor(50%) of that level's cost (1200/800/1000 -> 600/400/500 back)")
	e.start_research("wood_tech")  # Lv 1 → 2: 81 s — 5분 이하라 무료(사용자 2026-10-06). 다이아 비용을 보려고 400초로 늘린다 → 다이아 7
	check(e.research_dia_cost(e.time_now()) == 0, "81 s left is within the free finish window: 0 diamonds")
	e.research_current.finish = e.time_now() + 400.0
	check(e.research_dia_cost(e.time_now()) == 7 and not e.finish_research_now() and notes[-1] == EconomyScript.NO_DIA_TEXT and e.research_level("wood_tech") == 1,
		"instant finish needs ceil(400 / 60) = 7 diamonds; with none it is refused")
	e.diamonds = 10
	check(e.finish_research_now() and e.diamonds == 3 and e.research_level("wood_tech") == 2 and e.research_current.is_empty() and done[-1] == ["wood_tech", 2],
		"instant finish spends 7 diamonds and completes at once")
	e.start_research("wood_tech")  # Lv 2 → 3: 109 s → 무료
	check(e.research_dia_cost(e.time_now()) == 0 and e.finish_research_now() and e.diamonds == 3 and e.research_level("wood_tech") == 3 and done[-1] == ["wood_tech", 3],
		"5 min or less left: instant finish is free")
	# 서버 권위 효과의 오프라인 반영(서버 research.test와 같은 식)
	# 세 자원 모두 100/분이라 정수 %면 늘 딱 떨어진다 — 내림은 rate_per_min에 13.5%를 직접 넣어 본다
	e.research_levels = {"stone_tech": 2, "abundance": 1}  # 석재 +13%
	e.levels.quarry = 3
	e.levels.lumber = 3  # 아래 건설 시간 검사(벌목장 Lv 3)
	e.last_collect.quarry = t
	check(EconomyScript.rate_per_min("stone", 3, 13.5) == 340 and EconomyScript.rate_per_min("stone", 3, 13.0) == 339 and e.pending("quarry", t + 600.0) == 3390 and EconomyScript.rate_per_min("stone", 3) == 300,
		"production: floor(100 x 3 x 1.135) = floor(340.5) = 340; research +13% = 339 / min (10 min = 3390); no research = 300")
	e.research_levels = {"construct": 5}
	check(e.upgrade_sec("keep") == 52 and e.upgrade_sec("lumber") == 39, "build time = round(60 / 1.15) = 52 s (lumber Lv 3: 45 / 1.15 = 39)")
	e.research_levels = {"commerce": 3}
	check(e.sell_gold("wood", 100, 1.0) == 109 and EconomyScript.sell_value("stone", 7, 1.3, 9.0) == 19 and EconomyScript.sell_value("wood", 100, 1.0) == 100,
		"sell = floor(base x 1.09) (stone 7 x 2 x 1.3 = 18 -> 19)")
	e.research_levels = {"plunder": 2}
	var g0: int = e.gold_tenths
	e.add_kill("grunt", 1)
	check(e.kill_tenths("grunt", 1) == 110 and e.gold_tenths == g0 + 110 and e.kill_tenths("epic_boss", 2) == 3327, "kill gold = floor(tenths x 1.10): grunt 100 -> 110, boss 3025 -> 3327")
	e.research_levels = {"drill_manual": 5, "logistics": 5}
	check(is_equal_approx(e.train_time("barracks", 2), 2.0 * 10800.0 / 1.15) and e.train_cost_now("infantry", 3) == {"food": 810, "wood": 540}
		and EconomyScript.train_cost("infantry", 3) == {"food": 900, "wood": 600}, "training: time / 1.15, cost x 0.90 rounded (900/600 -> 810/540)")
	e.research_levels = {"barracks_ext": 2}
	check(e.population() == 8, "population 6 + 2 (barracks extension Lv 2)")
	var gs = GameStateScript.new()
	gs.roster = e
	e.research_levels = {}
	gs.refill()
	gs.castle_hp = 500.0
	gs.gate_hp[1] = 100.0
	gs.gate_hp[2] = 0.0
	e.research_levels = {"wall_fort": 2, "gate_fort": 4}
	gs.apply_levels(true)
	check(is_equal_approx(gs.castle_hp_max, 1100.0) and is_equal_approx(gs.castle_hp, 550.0) and is_equal_approx(gs.gate_hp_max, 480.0) and is_equal_approx(gs.gate_hp[0], 480.0)
		and is_equal_approx(gs.gate_hp[1], 120.0) and gs.gate_hp[2] == 0.0,
		"castle +10%% / gate +20%%: max HP up, current HP up by the same ratio (a broken gate stays broken): %s" % [[gs.castle_hp_max, gs.castle_hp, gs.gate_hp_max, gs.gate_hp]])
	gs.refill()
	check(is_equal_approx(gs.castle_hp, 1100.0) and is_equal_approx(gs.gate_hp_max, 480.0), "refill uses the research max HP")
	gs.free()
	check(is_equal_approx(GameData.soldier_research_mult("infantry", {"inf_pct": 9.0, "soldier_pct": 3.0, "cav_pct": 30.0}), 1.12)
		and GameData.soldier_research_mult("archer", {"inf_pct": 9.0}) == 1.0, "soldier multiplier = 1 + (type % + elite %) / 100")
	# 저장 v12 왕복, v11 → v12(연구 없음), 깨진 v12
	var tmp := OS.get_temp_dir().path_join("castle_r24_econ_%d.json" % OS.get_process_id())  # user:// 밖(다른 워크트리 체크와 겹치지 않게)
	e.save_path = tmp
	e.research_levels = {"wood_tech": 3, "arcana": 2}
	e.research_current = {"id": "stone_tech", "finish": t + 500.0}
	e.save()
	var raw = JSON.parse_string(FileAccess.get_file_as_string(tmp))
	var e2 = _econ(t)
	e2.save_path = tmp
	e2.load_save(t)
	check(int(raw.version) == 12 and EconomyScript.SAVE_VERSION == 12 and e2.research_levels == {"wood_tech": 3, "arcana": 2} and e2.research_current == {"id": "stone_tech", "finish": t + 500.0},
		"save v12 round-trips research levels and the running research")
	var v11: Dictionary = raw.duplicate(true)
	v11.version = 11
	v11.erase("research")
	_write(tmp, JSON.stringify(v11))
	e2.load_save(t)
	check(e2.research_levels.is_empty() and e2.research_current.is_empty() and e2.diamonds == e.diamonds and e2.res == e.res, "a v11 save migrates to v12 with no research (the rest kept)")
	for bad in [{"levels": [], "current": null}, {"levels": {"wood_tech": "x"}, "current": null}, {"levels": {}, "current": {"id": 5, "finish": 1.0}}, 7]:
		var v: Dictionary = raw.duplicate(true)
		v.research = bad
		_write(tmp, JSON.stringify(v))
		e2.load_save(t)
		check(e2.research_levels.is_empty() and e2.diamonds == 0, "a broken v12 research (%s) is a corrupt save" % [bad])
	DirAccess.remove_absolute(tmp)
	e2.free()
	# 서버 응답: research {levels, current} — 표에 없는 노드·0 레벨은 버림, 첫 반영은 완료가 아니다
	var srv = _econ(t)
	var fired := []
	srv.research_done.connect(func(id, lv): fired.append([id, lv]))
	var reply := func(levels, current): return {"player": {"gold_tenths": 0, "stage": 1, "res": {}, "buildings": {}, "research": {"levels": levels, "current": current}},
		"merchant": {"rates": {"wood": 1.0, "stone": 1.0, "food": 1.0}, "next_change": 3600.0}}
	check(srv.apply_server(reply.call({"wood_tech": 2, "bogus": 3, "stone_tech": 0, "hero_armor": 99}, {"id": "construct", "finish": 5000})) and srv.research_levels == {"wood_tech": 2, "hero_armor": 10}
		and srv.research_current == {"id": "construct", "finish": 5000.0} and fired.is_empty(), "apply_server reads research (unknown/0 dropped, clamped to max); the first reply is not a completion")
	check(srv.apply_server(reply.call({"wood_tech": 3}, null)) and srv.research_current.is_empty() and fired == [["wood_tech", 3]], "a later reply with a higher level fires research_done")
	var logged := _errors.count
	check(not srv.apply_server({"player": {"gold_tenths": 0, "stage": 1, "res": {}, "buildings": {}, "research": []}, "merchant": {"rates": {"wood": 1.0, "stone": 1.0, "food": 1.0}, "next_change": 3600.0}})
		and srv.research_levels == {"wood_tech": 3}, "a malformed research field rejects the reply")
	_errors.count = logged
	srv.free()
	e.free()
	# 아이콘(사용자 규칙: 바로 알아보게) — 연구 노드 그림은 단위 상자 안 다각형
	for kind in IconsScript.RESEARCH_KINDS:
		var shapes: Array = IconsScript.shapes(kind)
		check(shapes.size() >= 4, "research icon %s has shapes" % kind)
		for s in shapes:
			check(Array(s[0]).size() >= 3 and Array(s[0]).all(func(p): return absf(p.x) <= 0.5 and absf(p.y) <= 0.5), "research icon %s polygon inside the unit box: %s" % [kind, s[0]])


## 오프라인 처치 골드: 방치 스폰(idle_interval초마다 네 면 × spawn_group)을 다 잡았다고 보고 처치 골드 × offline_gold_mult(0.4),
## 상한 accum_cap_min분, 60초 미만 없음(서버 rules.offlineReward와 같은 값). 저장의 last_active부터 정산, 두 번 받지 않음, 개요 시그널.
	GameData.load_tables()  # 실제 설정(훈련 1마리씩)으로 되돌린다
func test_offline_gold() -> void:
	GameData.load_tables()
	var per := GameData.kill_gold_tenths("grunt", 1)
	check(per == 100 and GameData.config_num("offline_gold_mult") == 0.4 and GameData.config_num("fever_kills") == 2000.0, "grunt 100 tenths at stage 1, mult 0.4, fever 2000")
	check(EconomyScript.offline_reward(3600.0, 1, per) == {"sec": 3600.0, "kills": 5400, "tenths": 216000}, "1 h: 5400 kills, 21,600 gold (40%)")
	check(EconomyScript.offline_reward(59.9, 1, per).tenths == 0 and EconomyScript.offline_reward(60.0, 1, per) == {"sec": 60.0, "kills": 90, "tenths": 3600}, "under 60 s nothing")
	check(EconomyScript.offline_reward(360000.0, 1, per) == {"sec": 43200.0, "kills": 64800, "tenths": 2592000}, "capped at 12 h")
	var tmp := OS.get_temp_dir().path_join("castle_offline_%d.json" % OS.get_process_id())
	var e = _econ(1.8e9)
	e.save_path = tmp
	e.save()
	var e2 = _econ(1.8e9)
	e2.save_path = tmp
	e2.load_save(1.8e9)
	var from: float = e2._away_from
	var got := []
	e2.offline_reported.connect(func(r): got.append(r))
	e2.claim_offline(1, from + 3600.0)
	check(from > 0.0 and e2.gold_tenths == 216000 and got == [{"away_sec": 3600.0, "kills": 5400, "gold_tenths": 216000}] and e2.offline_report == got[0],
		"load → claim after 1 h: +21,600 gold and one report (from=%s gold=%d got=%s)" % [from, e2.gold_tenths, got])
	e2.claim_offline(1, from + 7200.0)
	check(e2.gold_tenths == 216000 and got.size() == 1, "a second claim without leaving again gives nothing")
	e2._away_from = from + 7200.0  # 백그라운드로 갔다(PAUSED)
	e2.claim_offline(1, from + 7230.0)
	check(e2.gold_tenths == 216000 and got.size() == 1, "back after 30 s: no gold, no report")
	var e3 = _econ(1.8e9)
	e3.claim_offline(1, 1.8e9)
	check(e3.gold_tenths == 0 and e3.offline_report.is_empty(), "a new game (no save) has nothing to claim")
	DirAccess.remove_absolute(tmp)


## 캐릭터 메시 합치기(mesh_merge.gd): 영웅(스킨 부위 + 뼈 부착 무기·모자·코드 부품) → 스켈레톤 아래 "Merged" 하나(재질마다 표면 하나),
## 정점 수 = 보이던 메시 합, Skin bind = 원래 + 단단한 부위마다 하나, 숨긴 장비는 빠지고 빈 부착 노드는 지운다, 같은 스펙은 메시·Skin 공유.
func test_mesh_merge() -> void:
	GameData.load_tables()
	var spec: Dictionary = Art.hero_spec(GameData.hero("arteon"))
	MeshMergeScript.enabled = false
	var plain := Art.instance(spec.scene)
	UnitModelScript2.dress(plain, spec)
	MeshMergeScript.enabled = true
	var verts := 0
	var mats := {}
	var rigid := 0
	var skel0 := plain.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for n in skel0.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var shown := true
		var q: Node = mi
		while q != plain:
			shown = shown and (not (q is Node3D) or q.visible)
			q = q.get_parent()
		if not shown:
			continue
		rigid += 0 if mi.skin != null else 1
		for s in mi.mesh.get_surface_count():
			verts += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			mats[mi.get_active_material(s)] = true
	var a := Art.instance(spec.scene)
	UnitModelScript2.dress(a, spec)
	var b := Art.instance(spec.scene)
	UnitModelScript2.dress(b, spec)
	var skel := a.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var meshes := skel.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.visible and (not (m.get_parent() is Node3D) or m.get_parent().visible))  # 숨긴 장비는 그대로 남는다
	var merged: MeshInstance3D = skel.get_node_or_null("Merged")
	var mverts := 0
	if merged != null:
		for s in merged.mesh.get_surface_count():
			mverts += (merged.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var base_binds: int = skel0.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.skin != null)[0].skin.get_bind_count()
	check(merged != null and meshes.size() == 1 and merged.mesh.get_surface_count() == mats.size() and mverts == verts and rigid > 0
		and merged.skin.get_bind_count() == base_binds + rigid and merged.skeleton == NodePath(".."),
		"arteon merged: one mesh, %d surfaces (one per material), %d vertices, %d + %d binds (meshes=%d surfaces=%d verts=%d)" % [mats.size(), verts, base_binds, rigid,
			meshes.size(), merged.mesh.get_surface_count() if merged else -1, mverts])
	check(skel.get_children().all(func(c): return not (c is BoneAttachment3D) or c.is_queued_for_deletion() or c.get_child_count() > 0), "empty bone attachments are removed")
	var merged_b: MeshInstance3D = (b.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D).get_node_or_null("Merged")
	check(merged_b != null and merged_b.mesh == merged.mesh and merged_b.skin == merged.skin, "the same spec shares one merged mesh and skin")
	for m in [plain, a, b]:
		m.free()



const GuildScript := preload("res://scripts/guild.gd")


## 길드(오프라인 로컬): 잠금, 가입, 출석·상자, 기부(비용·한도), 레벨업·버프, 보스(피해·등급·횟수·처치 넘김), 상점(한도·코인), 가상 길드원, 탈퇴, 저장.
func test_guild() -> void:
	GameData.load_tables()
	var now := GameData.reset_at(20000) + 3600.0  # 그날 01:00 KST
	var e = _econ(now)
	var g = GuildScript.new()
	g.save_path = ""
	g.econ = e
	g.fixed_now = now
	g.rng.seed = 7
	check(not g.is_unlocked() and g.join_block() != "" and g.buff_pct() == 0.0, "guild: locked before 1-10 is cleared, no buff")
	g.unlocked = true
	var recs: Array = g.recommendations(now)
	check(recs.size() == 5 and recs == g.recommendations(now), "guild: 5 recommendations, same within a day")
	g.refresh_recommendations()
	check(g.recommendations(now) != recs, "guild: refresh shows other guilds")
	var rec: Dictionary = recs[0]
	rec.level = 3
	check(g.join(rec, now) and g.joined() and int(g.guild.level) == 3 and g.buff_pct() == 3.0 and g.members_now(now).size() == mini(int(rec.count), GuildScript.capacity(3)) - 1,
		"guild: join copies level and members, buff = level %%: %s" % [g.buff_pct()])
	check(g.join(rec, now) == false, "guild: cannot join twice")
	# 출석
	var gold0: int = e.gold
	check(g.box_state(0) == "locked" and g.attend(now) and not g.attend(now) and e.gold == gold0 + 3000 and g.coins == 30,
		"guild: attend once a day (+3,000 gold, +30 coins)")
	for m in g.guild.members:
		m.att = true
	check(g.attend_count() == int(rec.count) and g.box_state(0) == "ready" and g.claim_box(0) and g.box_state(0) == "claimed" and not g.claim_box(0),
		"guild: attendance box 5 claimable once when 5+ attended")
	# 기부
	e.gold = 15000
	e.diamonds = 60
	check(g.donate("gold", now) and e.gold == 5000 and g.donate_block("gold") == "골드가 부족합니다", "guild: gold donation costs 10,000")
	check(g.donate("dia", now) and e.diamonds == 10 and g.donate_block("dia") == "오늘 기부 횟수를 다 썼습니다" and g.donate_block("royal") == "다이아가 부족합니다",
		"guild: diamond donation once a day")
	# 인원·레벨: 1~5레벨 15명, 6레벨부터 20명(나 포함, 최대 20명), 레벨 끝 없음·버프 레벨당 1%
	check(GuildScript.capacity(1) == 15 and GuildScript.capacity(5) == 15 and GuildScript.capacity(6) == 20 and GuildScript.capacity(40) == 20 and GuildScript.buff_of(99) == 99.0,
		"guild: 15 members, 20 from level 6 on, levels and buff have no cap")
	check(g.members_now(now).size() + 1 <= GuildScript.capacity(int(g.guild.level)), "guild: members + me fit the capacity")
	g.guild.level = 1
	g.guild.exp = 0
	# 레벨업
	var lv := int(g.guild.level)
	g._add_exp(GuildScript.exp_need(lv) * 3)
	check(int(g.guild.level) > lv and g.buff_pct() == float(g.guild.level), "guild: exp levels the guild and the buff follows")
	# 보스
	check(g.team_dps() > 0.0, "guild: starting deploy has damage: %s" % g.team_dps())
	var runs := []
	var results := []
	g.boss_started.connect(func(r): runs.append(r))
	g.boss_done.connect(func(r): results.append(r))
	check(g.start_boss(now) and int(g.me.boss_tries) == 1, "guild: starting a boss fight uses a try")
	var run: Dictionary = g._boss_run.duplicate()
	check(run.level == 1 and float(run.hp) == GuildScript.boss_max(1) and float(run.cap) == roundf(g.team_dps() * GuildScript.BOSS_FIGHT_SEC * GuildScript.BOSS_DMG_CAP),
		"guild: every boss run starts at Lv 1 with a damage cap: %s" % [run])
	var score0 := g.boss_score()
	g.finish_boss(str(run.run_id), 5000.0, now)
	var r1: Dictionary = results.back() if not results.is_empty() else {}
	check(r1.get("dmg", 0.0) == 5000.0 and int(r1.level) == GuildScript.boss_reach(5000.0) and int(r1.level) >= 2 and float(g.me.boss_total) == 5000.0
		and absf(g.boss_score() - score0 - 5000.0) < 0.5,
		"guild: the fight's damage is my score, the dragon levels up within the fight, guild score = sum: %s" % [r1])
	g.finish_boss(str(run.run_id), 5000.0, now)
	check(results.back().get("error", "") == "no_run", "guild: a fight finishes once")
	g.start_boss(now)
	g.finish_boss(str(g._boss_run.run_id), 1e12, now)
	check(results.back().dmg == float(run.cap), "guild: damage is capped at dps × sec × cap: %s" % [results.back()])
	check(g.boss_block() == "오늘 도전 횟수를 다 썼습니다" and not g.start_boss(now), "guild: 2 boss tries a day")
	var reach := func(lv: int) -> float:
		var n := 0.0
		for i in range(1, lv):
			n += GuildScript.boss_max(i)
		return n
	check(GuildScript.boss_grade(reach.call(45))[0] == "SSS+" and GuildScript.boss_grade(reach.call(45) - 1.0)[0] == "SSS" and GuildScript.boss_grade(reach.call(22))[0] == "S"
		and GuildScript.boss_grade(reach.call(4))[0] == "B" and GuildScript.boss_grade(1.0)[0] == "B-", "guild: fight grade by the dragon level reached (B-~SSS+)")
	# 상점
	g.coins = 1000
	var dia0: int = e.diamonds
	check(g.buy("dia") != "" and e.diamonds == dia0 + 50 and g.coins == 850 and g.buy("dia") != "" and g.buy_block("dia") == "구매 한도에 도달했습니다",
		"guild: shop diamonds 50 for 150 coins, 2 a day")
	var shards0 := 0
	for id in e.heroes:
		shards0 += e.shards_of(id)
	g.buy("shards")
	var shards1 := 0
	for id in e.heroes:
		shards1 += e.shards_of(id)
	check(shards1 == shards0 + 3, "guild: shard box gives 3 shards of owned heroes")
	var bag0: int = e.bag.size()
	var got_equip := g.buy("equip")
	check(got_equip != "" and e.bag.size() == bag0 + 1 and e.bag.back().rolls.size() >= 1 and not e.bag.back().has("level") and g.coins == 1000 - 300 - 200 - 50 and not GuildScript.SHOP.any(func(it): return it.id == "food"),
		"guild: equipment box (instead of food) adds one item: %s" % got_equip)
	# 다음 날: 한도·출석 초기화, 가상 길드원이 활동한다
	var exp_before := int(g.guild.exp) + int(g.guild.level) * 100000
	var next := now + 86400.0 + 18.0 * 3600.0  # 다음 날 19:00
	g.fixed_now = next
	g.tick(next, true)
	check(g.attend_block() == "" and g.donations_left("dia") == 1 and g.shop_left("dia") == 2 and int(g.me.boss_tries) == 0,
		"guild: daily limits reset at 00:00 KST")
	check(int(g.guild.exp) + int(g.guild.level) * 100000 > exp_before and g.members_now(next).any(func(m): return m.att),
		"guild: simulated members attend and donate during the day")
	# 저장 왕복
	g.save_path = "user://test_guild.json"
	g.save()
	var h = GuildScript.new()
	h.save_path = "user://test_guild.json"
	h.econ = e
	h.fixed_now = next
	h.load_save()
	check(h.joined() and h.guild.name == g.guild.name and int(h.guild.level) == int(g.guild.level) and h.coins == g.coins and h.buff_pct() == g.buff_pct()
		and h.members_now(next).size() == g.members_now(next).size(), "guild: save round-trips guild, coins and members")
	DirAccess.remove_absolute("user://test_guild.json")
	# 탈퇴: 코인은 남는다. 창설: 혼자 시작, 길드원은 시간이 지나며 들어온다
	var c0: int = g.coins
	check(g.leave() and not g.joined() and g.coins == c0 and g.buff_pct() == 0.0, "guild: leaving keeps coins and drops the buff")
	e.gold = 499999
	check(g.create_block("우리길드") == "골드가 부족합니다", "guild: creating needs 500,000 gold")
	e.gold = 510000
	check(g.create_block("가") != "" and g.create("우리길드", 3, next) and e.gold == 10000 and g.guild.mine and g.members_now(next).is_empty()
		and g.members_now(next + 86400.0).size() >= 5, "guild: creating costs 500,000 gold, starts alone, members join over time")
	g.free()
	h.free()
	e.free()


const TutorialScript := preload("res://scripts/tutorial.gd")


## 튜토리얼: 공터(Economy.unbuilt) 짓기·생산·선행 조건, 다이아 모집권, 미션 완료·보상 규칙·탭 잠금, 저장 왕복.
func test_tutorial() -> void:
	GameData.load_tables()
	var now := 1.8e9
	var e = _econ(now)
	var gs = GameStateScript.new()
	gs.roster = e
	var t = TutorialScript.new()
	t.save_path = ""
	t.econ = e
	t.gs = gs
	t._connect()  # 트리 밖: 시그널(처치·수집·판매·모집)만 잇는다
	t.begin(true)
	check(t.active() and e.is_built("keep") and e.is_built("gate") and not e.is_built("lumber") and e.shown_level("lumber") == 0,
		"tutorial: new game has only keep + gate built")
	check(e.pending("lumber", now + 3600.0) == 0, "tutorial: an unbuilt lumber mill produces nothing")
	check(e.upgrade_block("keep", now) == "prereq" or e.upgrade_block("keep", now) == "not_enough", "tutorial: keep Lv 2 waits for its prerequisites")
	e.res = {"wood": 0, "stone": 0, "food": 0}
	check(e.upgrade_block("lumber", now) == "not_enough", "tutorial: building a lot costs the Lv 1 price")
	# 1. 성채 살펴보기 — 사건(건물 창)
	check(not t.complete() and t.tab_locked("hero") and t.tab_locked("guild") and not t.tab_locked("merchant"), "tutorial: tabs locked at the start")
	e.admin = true  # 슈퍼관리자(서버 player.admin): 가이드 중에도 잠금이 없다
	check(not t.tab_locked("hero") and not t.tab_locked("exchange") and not t.pvp_locked() and not t.dungeon_locked("ticket") and not t.build_locked("lumber"),
		"admin: every guide lock is open")
	e.admin = false
	t.note("open", 1, "lumber")
	check(not t.complete(), "tutorial: opening another building does not count")
	t.note("open", 1, "keep")
	var r0: Dictionary = t.reward(0)
	var c1 := GameData.build_cost("lumber", 1)
	check(t.complete() and int(r0.wood) == ceili(int(c1.wood) * 1.2 / 10.0) * 10 and int(r0.stone) >= int(c1.stone),
		"tutorial: mission 1 pays the next mission's resources + margin: %s" % [r0])
	check(t.claim() and t.step == 1 and int(e.res.wood) == int(r0.wood), "tutorial: claim grants and advances")
	# 2. 벌목장 건설 — 일꾼으로 0 → 1
	check(e.upgrade_block("lumber", now) == "" and e.upgrade("lumber", now), "tutorial: lot construction starts with the reward")
	check(is_equal_approx(float(e.build.finish), now + 5.0), "tutorial: building a lot takes lot_build_sec (5 s): %s" % [e.build])
	check(e.requirements("lumber").is_empty() and not t.complete(), "tutorial: lot has no prerequisites; mission waits for the build")
	e.complete_due(now + 100000.0)
	check(e.is_built("lumber") and e.building_level("lumber") == 1 and t.complete(), "tutorial: finished lot becomes Lv 1 and completes the mission")
	check(e.pending("lumber", float(e.last_collect.lumber) + 120.0) == 200, "tutorial: production counts from the build finish")
	# 보상 규칙
	var kinds := {}
	for i in TutorialScript.MISSIONS.size():
		var rw: Dictionary = t.reward(i)
		if TutorialScript.MISSIONS[i].has("reward"):  # 가이드 성장 미션: 적힌 보상
			check(rw == TutorialScript.MISSIONS[i].reward, "guide: filler mission %d pays its own reward: %s" % [i + 1, rw])
			continue
		var j := i + 1  # 다음 규칙 미션(성장 미션은 건너뛴다)
		while j < TutorialScript.MISSIONS.size() and TutorialScript.MISSIONS[j].has("reward"):
			j += 1
		var nxt: Dictionary = TutorialScript.MISSIONS[j] if j < TutorialScript.MISSIONS.size() else {}
		var want := "tickets"
		if nxt.get("kind", "") in ["build", "level", "train", "research"]:
			want = "res"
		elif nxt.get("kind", "") in ["hero_level", "growth"]:
			want = "gold"
		elif nxt.get("kind", "") == "dungeon":
			want = "keys"
		var got := "tickets" if rw.has("tickets") else ("keys" if rw.keys().any(func(k): return str(k).begins_with("keys_")) else ("res" if rw.has("wood") or rw.has("food") or rw.has("stone") else "gold"))
		kinds[want] = true
		check(got == want and (want != "tickets" or int(rw.tickets) == 10), "tutorial: mission %d reward is %s: %s" % [i + 1, want, rw])
	check(kinds.size() == 4, "tutorial: all four reward kinds appear")
	check(GameData.train_max(1) == 1 and GameData.train_max(30) == 1 and GameData.soldier_unit_sec(1) == 180 * 60.0 and GameData.soldier_unit_sec(6) == 30 * 60.0
		and GameData.train_tier(7) == 2, "training is one soldier per order: 3 h at Lv 1 down to 30 min, tiers unchanged")
	# 튜토리얼 훈련: 1마리씩, 5초
	t.check()
	check(e.tutorial_training and e.train_max("barracks") == 1 and e.train_time("barracks", 1) == 5.0 and t.reward(t.mission_index("train") - 1).has("food"),
		"tutorial: training is one soldier in 5 s")
	var step_was: int = t.step
	t.step = t.mission_index("train") + 1
	t.check()
	check(t.active() and not e.tutorial_training and e.train_time("barracks", 1) == 180 * 60.0, "tutorial: past the training mission, training is back to 3 h")
	t.step = step_was
	t.check()
	# 던전 잠금: 그 던전 미션에 닿기 전엔 잠김
	var locks := []
	for ty in ["gold", "equip", "ticket"]:
		var mi: int = t.mission_index(TutorialScript.DUNGEON_MISSION[ty])
		t.step = mi - 1
		var before: bool = t.dungeon_locked(ty)
		t.step = mi
		locks.append(before and not t.dungeon_locked(ty) and TutorialScript.MISSIONS[mi].arg == ty)
	t.step = step_was
	check(locks == [true, true, true] and t.dungeon_lock_text("ticket") == "가이드 35번째 미션 「모집권 던전」에서 열려요" and t.reward(t.mission_index("dungeon_equip")) == {"keys_ticket": 2},
		"tutorial: each dungeon unlocks at its own mission; the ticket dungeon mission is paid 2 ticket keys: %s" % [locks])
	# 공터 첫 건축: 그 건설 미션에 닿기 전엔 잠김(이미 지은 건물은 아님), 탭 잠금 문구
	var lots_was: Dictionary = e.unbuilt.duplicate()
	var blocks := []
	for m in TutorialScript.MISSIONS:
		if m.kind != "build":
			continue
		var mi: int = t.mission_index(m.id)
		e.unbuilt = {m.arg: true}
		t.step = mi - 1
		var before: bool = t.build_locked(m.arg)
		t.step = mi
		var at: bool = t.build_locked(m.arg)
		e.unbuilt = {}
		t.step = mi - 1
		blocks.append(before and not at and not t.build_locked(m.arg))
	e.unbuilt = lots_was
	t.step = step_was
	check(blocks.size() == 9 and not blocks.has(false) and t.build_lock_text("tavern") == "가이드 16번째 미션 「주점 건설」에서 건설할 수 있어요"
		and t.tab_lock_text("hero") == "가이드 9번째 미션 「영웅 레벨업」에서 열려요",
		"tutorial: an empty lot can't be built before its build mission; lock toasts name the mission number: %s" % [blocks])
	# 가이드: 새 기능을 여는 미션 사이에 성장 미션이 2개 이상, 성장 미션 판정(영웅 레벨·능력치 레벨·PVP)
	var intro := ["build_lumber", "sell", "hero_level", "growth", "build_tavern", "build_barracks", "dungeon_gold", "dungeon_equip", "dungeon_ticket",
		"soldier_deploy", "build_lab", "build_archery", "build_stable", "guild", "pvp"]
	var gaps := []
	for k in range(2, intro.size()):
		gaps.append(t.mission_index(intro[k]) - t.mission_index(intro[k - 1]) - 1)
	check(TutorialScript.MISSIONS.size() == 67 and gaps.min() >= 1 and gaps.filter(func(x): return x >= 2).size() >= 10, "guide: new features are spaced out by growth missions: %s" % [gaps])
	t.step = t.mission_index("hero_lv4_5")
	var hero_lv_was: Dictionary = e.hero_levels.duplicate()
	check(not t.complete() and t.progress_text() == "0/4", "guide: hero level mission waits: %s" % t.progress_text())
	for id in e.heroes.keys().slice(0, 4):
		e.hero_levels[id] = 5
	check(e.heroes.size() >= 4 and t.complete(), "guide: 4 heroes at Lv 5 complete the hero level mission")
	e.hero_levels = hero_lv_was
	t.step = t.mission_index("atk_3")
	e.upgrades["atk"] = 2
	check(not t.complete() and t.progress_text() == "Lv 2/3", "guide: stat level mission shows Lv 2/3")
	e.upgrades["atk"] = 3
	check(t.complete() and t.reward(t.step) == {"gold": 2000}, "guide: stat Lv 3 completes; filler pays its own gold")
	e.upgrades["atk"] = 0
	t.step = t.mission_index("pvp") - 1
	check(t.pvp_locked() and t.pvp_lock_text() == "가이드 64번째 미션 「PVP 결투」에서 열려요", "guide: PVP locked before its mission: %s" % t.pvp_lock_text())
	t.step += 1
	t.count = 0
	check(not t.pvp_locked() and not t.complete(), "guide: PVP opens at its mission")
	t.note("pvp")
	check(t.complete(), "guide: one PVP battle completes the PVP mission")
	t.step = t.mission_index("stage_1_12")
	t.count = 0
	check(not t.complete(), "guide: 1-12 is not cleared by the guild unlock")
	check(TutorialScript.v2_step(0) == 0 and TutorialScript.v2_step(9) == t.mission_index("growth") and TutorialScript.v2_step(20) == t.mission_index("dungeon_ticket")
		and TutorialScript.v2_step(33) == TutorialScript.MISSIONS.size(), "guide: old v2 steps map to the same mission id")
	# 처치·스테이지
	t.step = TutorialScript.MISSIONS.map(func(m): return m.id).find("kill_30")
	t.count = 0
	for i in 29:
		e.add_kill("grunt", 1)
	check(not t.complete() and t.progress_text() == "29/30", "tutorial: kill mission counts kills")
	e.add_kill("grunt", 1)
	check(t.complete(), "tutorial: 30 kills complete the mission")
	t.step = TutorialScript.MISSIONS.map(func(m): return m.id).find("stage_1_3")
	check(not t.complete(), "tutorial: 1-3 not cleared yet")
	gs.stage = 4
	check(t.complete(), "tutorial: reaching round 4 clears 1-3")
	# 다이아 모집권
	e.grant({"tickets": 10})
	var owned: int = e.heroes.size()
	check(e.wallet(GameData.GACHA_TICKET) == 10 and e.gacha(10, GameData.GACHA_TICKET) and e.dia_tickets == 0 and e.diamonds == 0,
		"tutorial: 10 tickets = one diamond 10-pull, no diamonds spent")
	check(e.heroes.size() > owned and not e.gacha(1, GameData.GACHA_TICKET), "tutorial: ticket pull adds heroes; no tickets left")
	e.grant({"keys_gold": 2})
	check(int(e.dungeon_state("gold").keys) == int(GameData.config_num("gold_key_daily")) + 2, "tutorial: dungeon ticket reward adds keys")
	# 저장 왕복(공터·모집권), 옛 저장은 모두 지어짐
	e.grant({"tickets": 3})
	e.save_path = ECON_TMP
	e.save()
	var e2 = EconomyScript.new()
	e2.save_path = ECON_TMP
	e2.load_save(now)
	check(e2.dia_tickets == 3 and not e2.is_built("farm") and e2.is_built("lumber") and not e2.fresh_game, "tutorial: save keeps lots and tickets")
	var f := FileAccess.open(ECON_TMP, FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	d.erase("unbuilt")
	d.erase("dia_tickets")
	f = FileAccess.open(ECON_TMP, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	e2.load_save(now)
	check(e2.unbuilt.is_empty() and e2.dia_tickets == 0, "tutorial: an older save has every building built")
	DirAccess.remove_absolute(ECON_TMP)
	var e3 = EconomyScript.new()
	e3.save_path = ECON_TMP
	e3.load_save(now)
	check(e3.fresh_game, "tutorial: no save file = fresh game")
	# 끝까지
	t.step = TutorialScript.MISSIONS.size() - 1
	t.guild = null
	check(not t.complete() and t.tab_locked("guild") == false, "tutorial: guild tab open at the guild mission")
	t.state = "done"
	t.repeats_on = true
	t.check()
	# 반복 퀘스트: 처치 → 수집 → 스테이지 → 성장 … 바퀴마다 목표·보상이 커진다
	var q: Dictionary = t.mission()
	check(t.repeating() and q.kind == "kill" and int(q.arg) == 100 and int(t.repeat_reward(q).gold) == 3000, "repeat: first quest is kill 100 for 3,000 gold")
	for i in 100:
		e.add_kill("grunt", 1)
	var g0: int = e.gold
	check(t.complete() and t.claim() and e.gold == g0 + 3000 and t.mission().kind == "collect", "repeat: claim pays and moves on")
	t.count = 3
	t.claim()
	gs.stage = 7
	t.best_stage = 7
	t.rep_quest = {}
	q = t.mission()
	check(q.kind == "stage" and not t.complete() and int(q.arg) == 8 and q.title == "스테이지 %s 클리어" % GameData.round_label(8), "repeat: stage target = reached + 1 (two more rounds)")
	gs.stage = 9
	check(t.complete() and t.claim() and t.mission().kind == "growth_up" and t.progress_text() == "0/3", "repeat: stage cleared; growth counts from now")
	t.rep_n = TutorialScript.REPEATS.size()
	t.rep_quest = {}
	q = t.mission()
	check(int(q.arg) == 150 and int(t.repeat_reward(q).gold) == 6000, "repeat: second cycle grows target and reward")
	check(t.save_path == "" and t.mission() == q, "repeat: quest is kept until claimed")
	check(not e.tutorial_training and e.train_max("barracks") == 1 and e.train_time("barracks", 1) == 180 * 60.0, "tutorial done: normal training time, still one per order")
	check(not t.tab_locked("hero") and not t.dungeon_locked("ticket") and t.repeating(), "tutorial done: nothing locked, repeat quests")
	t.free()
	gs.free()
	e.free()
	e2.free()
	e3.free()



## 온라인 튜토리얼·반복 퀘스트: 서버 표 data/quests.csv가 이 규칙(MISSIONS·reward·REPEATS)과 같은지, apply_server가 quest·unbuilt·dia_tickets를
## 받는지, Tutorial이 서버 진행을 따르는지(받기 전엔 카드 없음, 단계가 바뀌면 사건 수를 새로, 끝나면 알림). net은 null(요청은 안 보낸다).
func test_tutorial_online() -> void:
	GameData.load_tables()
	var enc := func(r: Dictionary) -> String:
		var parts := []
		for k in ["wood", "stone", "food", "gold", "diamonds", "tickets", "keys_gold", "keys_equip", "keys_ticket"]:
			if r.has(k):
				parts.append("%s:%d" % [k, int(r[k])])
		return "|".join(parts)
	var rows := []
	var f := FileAccess.open("res://data/quests.csv", FileAccess.READ)
	f.get_csv_line()
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() >= 5:
			rows.append(line)
	var tmp = TutorialScript.new()
	tmp.save_path = ""
	var tut := rows.filter(func(x): return x[1] == "tutorial")
	var rep := rows.filter(func(x): return x[1] == "repeat")
	var same: bool = tut.size() == TutorialScript.MISSIONS.size() and rep.size() == TutorialScript.REPEATS.size()
	var bad := ""
	if same:
		for i in tut.size():
			var m: Dictionary = TutorialScript.MISSIONS[i]
			var needs := ""
			if m.kind == "build":
				needs = "build:%s" % m.arg
			elif m.kind == "level":
				needs = "level:%s:%d" % [m.arg[0], int(m.arg[1])]
			if tut[i][0] != m.id or tut[i][2] != needs or tut[i][3] != enc.call(tmp.reward(i)):
				bad = "%s: %s" % [m.id, tut[i]]
		for i in rep.size():
			var d: Dictionary = TutorialScript.REPEATS[i]
			if rep[i][0] != "rep_" + d.kind or rep[i][3] != enc.call(d.get("reward", {})) or rep[i][4] != enc.call(d.get("fixed", {})):
				bad = "%s: %s" % [d.kind, rep[i]]
	tmp.free()
	check(same and bad == "", "quests.csv matches the tutorial rewards and repeat quests (regenerate it when costs change) %s" % bad)
	var now := 1.8e9
	var e = _econ(now)
	var reply := {"player": {"gold_tenths": 1005, "stage": 3, "res": {"wood": 4}, "buildings": {}, "dia_tickets": 7, "unbuilt": ["lumber", "nope"],
		"quest": {"tut_state": "active", "tut_step": 3, "rep_n": 0}}, "merchant": {"rates": {"wood": 1.2, "stone": 0.8, "food": 2.0}, "next_change": 3600.0}}
	var gs = GameStateScript.new()
	gs.roster = e
	var t = TutorialScript.new()
	t.save_path = ""
	t.econ = e
	t.gs = gs
	t._connect()
	t.go_online()
	check(t.online and t.mission().is_empty() and not t.active(), "online tutorial: no card until the server says where the player is")
	check(e.apply_server(reply) and e.dia_tickets == 7 and e.unbuilt == {"lumber": true} and e.server_quest == {"tut_state": "active", "tut_step": 3, "rep_n": 0},
		"apply_server reads quest progress, lots (known buildings only) and tickets")
	check(t.active() and t.step == 3 and t.mission().id == TutorialScript.MISSIONS[3].id and e.tutorial_training, "online tutorial follows the server step")
	t.count = 5
	e.apply_server(reply)
	check(t.count == 5, "the same server step keeps the event count")
	reply.player.quest = {"tut_state": "active", "tut_step": 4, "rep_n": 0}
	reply.player.unbuilt = []
	var notes := []
	e.notice.connect(func(x): notes.append(x))
	e.apply_server(reply)
	check(t.step == 4 and t.count == 0 and e.unbuilt.is_empty(), "a new server step starts counting again")
	reply.player.quest = {"tut_state": "done", "tut_step": TutorialScript.MISSIONS.size(), "rep_n": 2}
	e.apply_server(reply)
	check(not t.active() and t.repeating() and t.rep_n == 2 and t.mission().kind == TutorialScript.REPEATS[2].kind and notes.has(TutorialScript.DONE_TEXT)
		and not e.tutorial_training, "online: tutorial done → repeat quest from the server's number")
	check(not e.quest_claim_online({"type": "repeat", "n": 2}), "no network, no claim")
	# 온라인 판매 응답도 sold를 낸다(튜토리얼 7 "상인과 거래" — 응답에서 세지 않아 깨지지 않던 버그)
	var sales := []
	e.sold.connect(func(g): sales.append(g))
	var sell_reply: Dictionary = reply.duplicate(true)
	sell_reply.gold_gained = 0
	e._on_sold(sell_reply, "sell:all")
	sell_reply.gold_gained = 120
	e._on_sold(sell_reply, "sell:all")
	check(sales == [120], "an online sale reply with gold signals sold (nothing sold, no signal)")
	t.free()
	gs.free()
	e.free()


## 옛 훈련 설정(1마리 3:00, 묶음 10 + 2 × (L − 1)) — 훈련 규칙 테스트가 쓴다. 실제 설정은 1마리씩·3시간(사용자 2026-10-06).
func _legacy_training() -> void:
	GameData._config.train_base_min = "180"
	GameData._config.train_step_min = "30"
	GameData._config.train_batch_base = "10"
	GameData._config.train_batch_per_level = "2"


const MissionsScript := preload("res://scripts/missions.gd")


## 미션(오프라인): 사건 수, 일일·주간·반복 받기와 보상, 일일 보너스(다른 일일 6개)·주간 보너스(5일), 날·주 리셋, 반복 목표 증가·남은 진행, 저장 왕복.
func test_missions() -> void:
	GameData.load_tables()
	var now := 1.8e9
	var e = _econ(now)
	var m = MissionsScript.new()
	m.save_path = ""
	m.econ = e
	m._connect()
	m.roll()
	var dk: Dictionary = m.find("d_kill")
	check(m.progress(dk) == 0 and not m.can_claim(dk) and m.ready_count() == 0, "missions: nothing to claim at the start")
	for i in 300:
		e.killed.emit("goblin")
	check(m.can_claim(dk) and m.ready_count("daily") == 1 and m.ready_count("weekly") == 0, "missions: 300 kills finish the daily kill mission")
	var gold0: int = e.gold
	check(m.claim("d_kill") and e.gold == gold0 + 3000 and m.is_claimed(dk) and not m.claim("d_kill"), "missions: daily reward once")
	check(m.progress(m.find("w_kill")) == 300 and m.progress(m.find("r_kill")) == 300, "missions: kills also count for weekly and repeat")
	# 반복: 1000 → 받으면 목표 1500, 남은 진행부터
	for i in 800:
		e.killed.emit("goblin")
	var rk: Dictionary = m.find("r_kill")
	check(m.can_claim(rk) and m.claim("r_kill") and m.times("r_kill") == 1 and m.target(rk) == 1500 and m.progress(rk) == 100,
		"missions: repeat target grows and leftover progress carries over")
	# 일일 보너스: 다른 일일 미션 6개
	var dall: Dictionary = m.find("d_all")
	for i in 5:
		e.collected.emit("lumber", "wood", 1)
	e.sold.emit(10)
	e.sold.emit(10)
	e.acted.emit("hero_level", 5)
	e.acted.emit("growth", 3)
	for id in ["d_collect", "d_sell", "d_hero"]:
		m.claim(id)
	check(m.progress(dall) == 4 and not m.can_claim(dall), "missions: daily bonus waits for 6 daily missions")
	m.claim("d_growth")
	e.gacha_done.emit([{}, {}, {}, {}, {}, {}, {}, {}, {}, {}])
	var dia0: int = e.diamonds
	m.claim("d_gacha")
	var t0: int = e.dia_tickets
	check(m.can_claim(dall) and m.claim("d_all") and e.diamonds == dia0 + 130 and e.dia_tickets == t0 + 1 and int(m.claimed.wd) == 1,
		"missions: daily bonus gives diamonds + a ticket and counts a bonus day")
	# 다음 날: 일일 기록·진행이 지워지고 주간·반복은 남는다(같은 주)
	var d0: int = m.day
	m.day -= 1
	m.roll()
	check(m.day == d0 and not m.is_claimed(dk) and m.progress(dk) == 0, "missions: a new day clears daily progress")
	m.week -= 1
	m.day -= 1
	m.roll()
	check(m.progress(m.find("w_kill")) == 0 and int(m.claimed.wd) == 0 and m.times("r_kill") == 1, "missions: a new week clears weekly, repeat stays")
	check(MissionsScript.week_of(MissionsScript.day_of(1791126000.0, 15)) == MissionsScript.week_of(MissionsScript.day_of(1791126000.0 - 1.0, 15)) + 1,
		"missions: weeks start Monday 00:00 KST")
	check(m.goto_of(dk) == "stage" and m.title(m.find("r_kill")) == "몬스터 1500마리 처치", "missions: titles and shortcuts")
	check(MissionsScript.reward_text({"wood": 300, "stone": 300, "food": 300, "tickets": 1}) == "목재·석재·식량 각 300 + 다이아 모집권 1장", "missions: reward text")
	var seen := {}
	for d in MissionsScript.DEFS:
		seen[d.id] = true
	check(seen.size() == MissionsScript.DEFS.size(), "missions: ids are unique")
	m.free()
	e.free()


## 상점(shop_items.gd, 서버 shop.ts와 같은 표): 오프라인 구매 — 무료 선물·다이아·골드, 기간 한도, 모자람.
func test_shop() -> void:
	var items := preload("res://scripts/shop_items.gd")
	var src := FileAccess.get_file_as_string("res://server/src/shop.ts")
	var same := true
	for x in items.ITEMS:
		var line := ""
		for l in src.split("\n"):
			if l.contains("id: '%s'" % x.id):
				line = l
		if not (line.contains("price: %d," % int(x.price)) and line.contains("limit: %d," % int(x.limit)) and line.contains("currency: '%s'" % x.currency)
				and line.contains("tab: '%s'" % x.tab)):
			same = false
			print("  shop item differs from server: ", x.id)
	check(same and src.count("{ id: '") == items.ITEMS.size(), "shop: client item table matches server/src/shop.ts")
	var e = _econ(1000.0)
	e.diamonds = 270
	check(e.shop_free_left("daily") and e.shop_free_left("weekly"), "shop: free gifts waiting at the start")
	check(e.buy_shop("d_free") and e.diamonds == 320 and e.pouch_count("gold_60") == 1 and e.shop_left("d_free") == 0 and e.shop_block("d_free") == "sold_out"
		and not e.shop_free_left("daily"), "shop: daily free gift gives 50 diamonds + gold pouch once")
	check(not e.buy_shop("d_free") and e.diamonds == 320, "shop: free gift can't be taken twice in a day")
	check(e.buy_shop("d_ticket") and e.diamonds == 80 and e.dia_tickets == 1 and not e.buy_shop("d_ticket"), "shop: discounted ticket costs 240 diamonds, once a day")
	var k0 := int(e.dungeon_state("gold").keys)
	check(e.buy_shop("d_key_gold") and e.diamonds == 20 and int(e.dungeon_state("gold").keys) == k0 + 1, "shop: gold dungeon key for 60 diamonds")
	check(e.shop_block("d_key_gold") == "diamonds" and not e.buy_shop("d_key_gold") and e.diamonds == 20, "shop: short of diamonds blocks and spends nothing")
	check(e.shop_block("d_res") == "diamonds", "shop: short of diamonds blocks the resource bundle")
	e.diamonds = 100
	var w0 := int(e.res.get("wood", 0))
	check(e.buy_shop("d_res") and e.diamonds == 50 and int(e.res.wood) == w0 + 10000 and e.shop_left("d_res") == 2, "shop: resource bundle costs 50 diamonds")
	e.shop.day = int(e.shop.day) - 1  # 날이 바뀌었다
	check(e.shop_left("d_free") == 1 and e.shop_left("d_res") == 3 and e.shop_left("w_free") == 1, "shop: a new day refills daily items")
	e.free()


## 결제 상품(iap_items.gd, 서버 iap.ts와 같은 표): 표 비교 + 오프라인 월정액·성장 패스 받기, 결제 연결 전 사기는 알림만.
func test_iap() -> void:
	var items := preload("res://scripts/iap_items.gd")
	var src := FileAccess.get_file_as_string("res://server/src/iap.ts")
	var same := true
	for p in items.PRODUCTS:
		var line := ""
		for l in src.split("\n"):
			if l.contains("id: '%s'" % p.id):
				line = l
		var dia_ok: bool = not p.give.has("diamonds") or line.contains("diamonds: %d" % int(p.give.diamonds))
		if not (line.contains("krw: %d," % int(p.krw)) and line.contains("kind: '%s'" % p.kind) and dia_ok):
			same = false
			print("  iap product differs from server: ", p.id)
	for t in items.GROWTH:
		if not src.contains("round: %d," % int(t.round)):
			same = false
	check(same and src.count("kind: '") == items.PRODUCTS.size(), "iap: client product table matches server/src/iap.ts")
	var e = _econ(1000.0)
	var d0: int = e.diamonds
	check(not e.iap_buy("dia_1") and e.diamonds == d0, "iap: buying before payments are connected gives nothing")
	check(e.iap_first_bonus("dia_1") and e.iap_can_buy("pkg_starter") and e.monthly_left("monthly") == 0 and not e.can_claim_monthly("monthly"), "iap: fresh state")
	check(not e.can_claim_growth(0, "free", 5) and e.can_claim_growth(0, "free", 10) and not e.can_claim_growth(0, "paid", 10), "iap: growth free tier needs the round, paid needs the pass")
	check(e.claim_growth(0, "free", 10) and e.diamonds == d0 + 60 and not e.can_claim_growth(0, "free", 10), "iap: growth free tier 0 gives 60 diamonds once")
	var per: Array = e.shop_period()
	e.iap = {"day": per[0], "week": per[1], "monthly": {"monthly": {"until": int(per[0]) + 2, "claimed": null}}, "passes": ["pass_growth"], "gp": {"free": [0], "paid": []}}
	check(e.monthly_left("monthly") == 3 and e.can_claim_monthly("monthly") and e.claim_monthly("monthly") and e.diamonds == d0 + 260 and not e.can_claim_monthly("monthly"),
		"iap: monthly card gives 100 diamonds once a day")
	check(e.claim_growth(0, "paid", 10) and e.diamonds == d0 + 860 and not e.iap_can_buy("pass_growth"), "iap: with the pass the paid tier pays out")
	# 핫딜(오프라인): 계기에 1시간, 하나만, 뜬 것만 살 수 있다, 보스는 새 25라운드 단계마다
	var got := []
	e.hot_offered.connect(func(h): got.append(h.id))
	check(not e.iap_can_buy("hot_dia") and e.active_hot().is_empty(), "hot: nothing to buy before a deal shows")
	e.hot_offer("boss", 24)
	e.hot_offer("dia", 24)
	check(got == ["hot_dia"] and e.iap_can_buy("hot_dia") and not e.iap_can_buy("hot_boss") and is_equal_approx(float(e.active_hot().until), e.time_now() + 3600.0),
		"hot: short of diamonds shows the 1-hour diamond deal (boss needs round 25)")
	e.hot_offer("defeat", 24)
	check(got == ["hot_dia"], "hot: one deal at a time")
	e.iap.hot.until = e.time_now() - 1.0
	check(e.active_hot().is_empty() and not e.iap_can_buy("hot_dia"), "hot: an expired deal can't be bought")
	e.hot_offer("dia", 24)
	e.hot_offer("boss", 25)
	check(got == ["hot_dia", "hot_boss"] and int(e.iap_view().hs) == 1, "hot: diamond deal rests 24 h, boss stage 1 shows its deal")
	e.free()

extends Node
## 헤드리스 공성전 체크(오토로드 포함). 실행: godot --headless --fixed-fps 30 --path . res://tests/war_check.tscn
## 사례: (1) AI 공격 4분대 vs AI 수비 4분대 — 처치가 나고 스크립트 오류 없음, 분대 집중 공격이 보인다.
## (2) 약한 수비 — 공격이 성문을 부수고 성 안으로 들어가 성채를 친다. (3) 원거리 수비는 근접 적이 붙으면 물러난다.
## (4) 꼭두각시 장면이 방장 스냅샷을 따른다. (5) 영웅 상태 효과(독·둔화·속박·취약·약화·넉백·도발)가 영웅에게도 걸린다.
## (7) 배치 단계: 공격은 성 밖 진영에서 나오고, 배치는 성벽 밖으로 밀리고 면이 바뀌며, 시작 전엔 싸우지 않는다.
## (6) 오프라인 GuildWar: 상대 길드·성·공성 시각(기본·고르기)·전투 열기·결과 저장(줄기만)·한 주 한 번·성채 3% 점수·다음 주 보상.

const GameData := preload("res://scripts/game_data.gd")
const Formation := preload("res://scripts/formation.gd")
const WarRules := preload("res://scripts/war_rules.gd")
const BattleScript := preload("res://scripts/war_battle.gd")
const Balance := preload("res://scripts/balance.gd")

class ErrorCounter extends Logger:
	var count := 0
	var first := ""
	func _log_error(_fn: String, _file: String, _line: int, _code: String, why: String, _notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1
			if first == "":
				first = "%s %s:%d %s" % [_fn, _file, _line, why if why != "" else _code]

const ATT := ["arteon", "ignis", "sylvana", "grom", "baldur", "lumina", "kyle", "nev", "bron", "mira", "torvin", "echo", "felix", "ella", "dorik", "nina"]
const DEF := ["thorgar", "valen", "raven", "harald", "seraphine", "gaia", "dante", "kaz", "luna", "orin", "selene", "grit", "hans", "tia", "pip", "jack"]

var _fails := 0
var _errors := ErrorCounter.new()


func _ready() -> void:
	OS.add_logger(_errors)
	Economy.save_path = ""
	Fever.save_path = ""
	GameData._config.fx_shake = "0"
	Economy.reset(Time.get_unix_time_from_system())
	await _case_fight()
	await _case_siege()
	await _case_kite()
	await _case_puppet()
	await _case_status()
	await _case_deploy()
	await _case_offline_war()
	_check(_errors.count == 0, "no script errors (%d, first: %s)" % [_errors.count, _errors.first])
	print("WAR CHECK %s (%d failed)" % ["OK" if _fails == 0 else "FAILED", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _case_offline_war() -> void:
	print("(6) offline guild war flow")
	Guild.save_path = ""
	GuildWar.save_path = ""
	Guild.load_save()
	GuildWar.load_save()
	Guild.unlocked = true
	var t0 := 1790000000.0  # 고정 시각
	Guild.fixed_now = t0
	GuildWar.fixed_now = t0
	var rec: Dictionary = Guild.recommendations()[0]
	rec.level = 6
	_check(Guild.join(rec), "joined a guild")
	GuildWar.fetch()
	var w: Dictionary = GuildWar.war
	_check(w.enemy.members == 20 and w.castle.defenders == 80, "level-6 guild meets a 20-member enemy with 80 defenders (%d, %d)" % [w.enemy.members, w.castle.defenders])
	var e1: Dictionary = GuildWar.enemy_of()
	_check(GuildWar.enemy_guild(int(GuildWar.local.seed), 20, float(GuildWar.local.power)).hash() == e1.hash(), "enemy is deterministic")
	var ids: Array = GuildWar.default_squad()
	_check(ids.size() == 4, "default squad has 4 heroes")
	var def_at := GuildWar.battle_at(int(w.week), -1.0)
	_check(w.battle.state == "waiting" and w.points == 0 and is_equal_approx(float(w.schedule.at), def_at) and GuildWar.at_text(def_at) == "토요일 21:00"
		and GuildWar.enter_block(ids) != "", "weekly siege waits for its time (default saturday 21:00: %s)" % GuildWar.at_text(float(w.schedule.at)))
	_check(GuildWar.schedule_block(0, 0) != "" and GuildWar.set_schedule(1, 20), "members pick a later time this week (tuesday 20:00)")
	w = GuildWar.war
	var at := float(w.schedule.at)
	_check(GuildWar.at_text(at) == "화요일 20:00" and w.schedule.set and w.battle.state == "waiting", "the picked time shows: %s" % GuildWar.at_text(at))
	t0 = at + 5.0
	GuildWar.fixed_now = t0
	Guild.fixed_now = t0
	GuildWar.fetch()
	_check(GuildWar.war.battle.state == "live" and not GuildWar.war.schedule.can_change, "at the time the siege opens and the time is locked")
	var plan := GuildWar.local_enter(ids.map(func(id): return GuildWar.hero_entry(id)), t0)
	_check(plan.defenders.size() == 80 and plan.attackers.size() == Guild.members_now().size() + 1, "plan: 80 defenders, one squad per member (%d)" % plan.attackers.size())
	_check(plan.attackers.filter(func(sq): return not sq.ai).size() == 1, "only my squad is player-controlled")
	var d1: Dictionary = plan.defenders[0]
	var r := {"battle_id": plan.battle_id, "defenders": {str(d1.uid): 0.0, str(plan.defenders[1].uid): 0.5}, "gates": [0.0, plan.gates[1].hp + 99, plan.gates[2].hp, plan.gates[3].hp], "keep": plan.keep.hp}
	GuildWar.local_save_state(r, false, t0 + 60)
	w = GuildWar.war
	_check(w.points == WarRules.PTS_KILL + WarRules.PTS_GATE and w.castle.gates[1].hp == plan.gates[1].hp, "points from the castle state; gates never heal (%d)" % w.points)
	_check(w.battle.state == "live" and w.enemy_points == 0, "leaving early keeps the battle open; enemy score hidden until our siege ends")
	var again := GuildWar.local_enter(ids.map(func(id): return GuildWar.hero_entry(id)), t0 + 120)
	_check(again.battle_id == plan.battle_id and not again.defenders.any(func(dd): return dd.uid == d1.uid) and absf(again.clock - 125.0) < 1.0, "re-entering resumes the same battle without the fallen defender")
	# 성채 3%마다 1점
	var kp := {"battle_id": plan.battle_id, "keep": float(plan.keep.max) * 0.935}
	GuildWar.local_save_state(kp, true, t0 + 130)
	_check(GuildWar.war.battle.state == "done" and GuildWar.enter_block(ids) != "", "one battle a week")
	_check(GuildWar.war.points == WarRules.PTS_KILL + WarRules.PTS_GATE + 2, "keep: 6.5%% off = 2 points (%d)" % GuildWar.war.points)
	GuildWar.fixed_now = at + WarRules.BATTLE_SEC + 1.0
	GuildWar.fetch()
	_check(GuildWar.war.enemy_days.size() == 1 and GuildWar.war.enemy_points == GuildWar.war.enemy_days[0], "enemy score shows after our siege time")
	GuildWar.fixed_now = t0 + 7 * 86400.0
	Guild.fixed_now = GuildWar.fixed_now
	GuildWar.fetch()
	w = GuildWar.war
	_check(w.points == 0 and w.claim is Dictionary and int(w.claim.points) == WarRules.PTS_KILL + WarRules.PTS_GATE + 2 and not w.schedule.set,
		"next week: new enemy, default time again, last week's result can be claimed")
	var dia: int = Economy.diamonds
	GuildWar.claim()
	_check(Economy.diamonds == dia + int(w.claim.reward.diamonds) and GuildWar.war.claim == null, "claim pays once")
	Guild.fixed_now = -1.0
	GuildWar.fixed_now = -1.0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


static func make_plan(att_n: int, def_n: int, def_mult := 1.0, att_level := 30, def_level := 30) -> Dictionary:
	var defs := []
	var hp_lane := [0.0, 0.0, 0.0, 0.0]
	var hp_all := 0.0
	for m in def_n:
		for i in 4:
			var id: String = DEF[(m * 4 + i) % DEF.size()]
			var def := GameData.hero(id)
			var st := GameData.hero_stats(def, def_level, 2, {})
			var lane := WarRules.lane_of(m)
			defs.append({"uid": 1 + m * 4 + i, "owner": "d:%d" % m, "squad": m, "lane": lane, "hero": id, "level": def_level, "promotion": 2,
				"hp": st.hp * def_mult, "atk": st.atk * def_mult, "ratio": 1.0})
			hp_lane[lane] += st.hp * def_mult
			hp_all += st.hp * def_mult
	var gates := []
	for s in 4:
		var g := WarRules.gate_hp_max(hp_lane[s])
		gates.append({"hp": g, "max": g})
	var k := WarRules.keep_hp_max(hp_all)
	var atts := []
	for m in att_n:
		var hs := []
		for i in 4:
			var id: String = ATT[(m * 4 + i) % ATT.size()]
			var st := GameData.hero_stats(GameData.hero(id), att_level, 2, {})
			hs.append({"hero": id, "level": att_level, "promotion": 2, "hp": st.hp, "atk": st.atk})
		atts.append({"owner": "v:%d" % m, "name": "가상%d" % m, "squad": m, "lane": m % 4, "ai": true, "heroes": hs})
	return {"battle_id": "test", "my_id": "me", "enemy_name": "시험 길드", "duration": 600.0, "gates": gates, "keep": {"hp": k, "max": k},
		"defenders": defs, "attackers": atts}


func _battle(plan: Dictionary, role := "solo"):
	var b = BattleScript.new()
	b.plan = plan
	b.role = role
	add_child(b)
	return b


func _run(b, sec: float, step := 1.0, cond := Callable()) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().create_timer(step, true, false, true).timeout
		t += step
		if cond.is_valid() and cond.call():
			return


func _case_fight() -> void:
	print("(1) AI 4 squads vs AI 4 squads")
	var b = _battle(make_plan(4, 4))
	var shared := [0]
	var gaps := []
	var check := func():
		var alive: Array = (b.units(0) + b.units(1)).filter(func(x): return x.is_alive() and x.is_processing())
		if alive.size() >= 2:
			gaps.append(_min_gap(alive))
		var by := {}
		for u in b.units(1):
			var t = u.current_target()
			if u.is_alive() and t != null:
				var key := "%d:%d" % [u.squad, t.uid]
				by[key] = by.get(key, 0) + 1
		for k in by:
			if by[k] >= 2:
				shared[0] += 1
		return false
	await _run(b, 90.0, 0.5, check)
	print("    kills %d gates broken %d attackers dead now %d, attacker deaths %d" % [b.kills, b.gates_broken(), b.units(0).filter(func(u): return not u.is_alive()).size(), b.attacker_deaths])
	_check(b.kills > 0, "attackers killed some defenders")
	_check(b.units(0).any(func(u): return u.hp < u.hp_max or not u.is_alive()), "defenders hurt attackers")
	_check(shared[0] > 0, "defenders focus fire within a squad (seen %d times)" % shared[0])
	gaps.sort()
	var med: float = gaps[gaps.size() / 2] if gaps.size() > 0 else 0.0
	_check(gaps.size() > 20 and med >= 1.1, "heroes keep personal space while fighting (closest pair, median of %d looks %.2f m)" % [gaps.size(), med])
	b.queue_free()
	await get_tree().process_frame


func _case_siege() -> void:
	print("(2) weak defenders: gate falls, keep is hit")
	var b = _battle(make_plan(4, 4, 0.15, 30, 1))
	var inside := [false]
	await _run(b, 240.0, 1.0, func():
		for u in b.units(0):
			if u.is_alive() and Formation.is_inside(b.half, u.global_position):
				inside[0] = true
		return b.done)
	print("    kills %d gates %d keep %.0f/%.0f done %s" % [b.kills, b.gates_broken(), b.keep.hp, b.keep.hp_max, b.done])
	_check(b.gates_broken() >= 1, "a gate was broken")
	_check(inside[0], "attackers walked into the castle through a broken gate")
	_check(b.keep.hp < b.keep.hp_max, "keep took damage")
	b.queue_free()
	await get_tree().process_frame


func _case_kite() -> void:
	print("(3) ranged defender steps back from a melee attacker")
	var plan := make_plan(0, 0)
	var st := GameData.hero_stats(GameData.hero("raven"), 30, 2, {})
	plan.defenders = [{"uid": 1, "owner": "d:0", "squad": 0, "lane": 2, "hero": "raven", "level": 30, "promotion": 2, "hp": st.hp * 50.0, "atk": 1.0, "ratio": 1.0}]
	var st2 := GameData.hero_stats(GameData.hero("grom"), 30, 2, {})
	plan.attackers = [{"owner": "v:0", "squad": 0, "lane": 2, "ai": true, "heroes": [{"hero": "grom", "level": 30, "promotion": 2, "hp": st2.hp * 50.0, "atk": 1.0}]}]
	var b = _battle(plan)
	await get_tree().process_frame
	var d = b.units(1)[0]
	var a = b.units(0)[0]
	a.global_position = d.global_position + Formation.SIDE_DIR[2] * 1.5
	a.set_home(a.global_position, false)
	var start: Vector3 = d.global_position
	var moved := [0.0]
	await _run(b, 3.0, 0.25, func():
		moved[0] = maxf(moved[0], Formation.flat_distance(start, d.global_position))
		return false)
	_check(moved[0] > 1.5, "ranged defender kited away (%.1f m)" % moved[0])
	b.queue_free()
	await get_tree().process_frame


func _case_puppet() -> void:
	print("(4) puppet follows host snapshots")
	var plan := make_plan(2, 2)
	var host = _battle(plan, "host")
	var pup = _battle(plan, "puppet")
	pup.visible = false
	await _run(host, 6.0, 0.5, func():
		pup.apply_snapshot(host.snapshot())
		return false)
	await _run(host, 1.0, 0.1, func():
		pup.apply_snapshot(host.snapshot())
		return false)
	var worst := 0.0
	for uid in host.units_by_uid:
		var h = host.units_by_uid[uid]
		var p = pup.units_by_uid[uid]
		if h.is_alive():
			worst = maxf(worst, Formation.flat_distance(h.global_position, p.global_position))
	_check(worst < 3.0, "puppet positions track the host (worst %.2f m)" % worst)
	_check(pup.units(0).all(func(u): return u.puppet), "puppet units do not think")
	host.queue_free()
	pup.queue_free()
	await get_tree().process_frame


func _case_status() -> void:
	print("(5) hero status effects")
	var plan := make_plan(1, 0)
	var b = _battle(plan)
	await get_tree().process_frame
	var u = b.units(0)[0]
	u.set_process(true)
	var hp0: float = u.hp
	u.apply_poison(50.0, 1.0)
	u.apply_slow(50.0, 2.0)
	u.apply_root(1.0)
	u.apply_vulnerable(50.0, 2.0)
	u.apply_weaken(50.0, 2.0)
	await _run(b, 1.2, 0.3)
	_check(u.hp < hp0, "poison ticks on a hero")
	_check(u.has_status("slow") and u.has_status("weaken"), "slow and weaken are active")
	var p0: Vector3 = u.global_position
	u.knockback(p0 - Vector3(1, 0, 0), 3.0)
	await _run(b, 0.4, 0.2)
	_check(Formation.flat_distance(p0, u.global_position) > 1.5, "knockback pushes a hero")
	b.queue_free()
	await get_tree().process_frame


func _case_deploy() -> void:
	print("(7) deploy phase before the siege")
	var plan := make_plan(2, 20)
	plan.deploy_left = 300.0
	plan.can_start = true
	var b = _battle(plan)
	var pup = _battle(plan, "puppet")
	pup.visible = false
	await get_tree().process_frame
	_check(b.deploying, "battle starts in the deploy phase")
	_check(_min_gap(b.units(1)) >= 1.9, "80 defenders stand apart at their posts (closest %.2f m)" % _min_gap(b.units(1)))
	var lim: float = b.half + Balance.WALL_T
	_check(b.units(0).all(func(u): return maxf(absf(u.global_position.x), absf(u.global_position.z)) > lim), "attackers spawn outside the walls")
	_check(pup.units(0).all(func(u): return Formation.flat_distance(u._p_pos, Vector3.ZERO) > lim), "puppet attackers do not start at the castle centre")
	var u = b.units(0)[0]
	var want_lane := (int(u.lane) + 1) % 4
	b.deploy_unit(u, Formation.SIDE_DIR[want_lane] * 1.0)  # 성 한가운데를 눌러도
	_check(maxf(absf(u.global_position.x), absf(u.global_position.z)) >= lim + WarRules.DEPLOY_GAP - 0.01, "deploy point is pushed outside the wall gap")
	_check(int(u.lane) == want_lane, "deploying on another side changes the attacked gate")
	var u2 = b.units(0)[1]
	b.deploy_unit(u2, u.global_position)  # 같은 곳을 눌러도
	_check(Formation.flat_distance(u.global_position, u2.global_position) >= WarRules.DEPLOY_SPACE - 0.01, "two heroes deployed on one spot stand apart (%.2f m)" % Formation.flat_distance(u.global_position, u2.global_position))
	_check(_min_gap(b.units(0)) >= 1.5, "camp and deploy spots do not overlap (closest %.2f m)" % _min_gap(b.units(0)))
	var hp_def: Array = b.units(1).map(func(d): return d.hp)
	await _run(b, 5.0, 0.5)
	_check(is_equal_approx(b.clock, 0.0), "clock does not run while deploying")
	_check(b.units(1).map(func(d): return d.hp) == hp_def, "no fighting while deploying")
	_check(b.deploy_left < 300.0 and b.deploy_left > 290.0, "deploy countdown ticks (%.1f)" % b.deploy_left)
	b.request_start()
	_check(not b.deploying, "[전투 시작] begins the fight")
	await _run(b, 2.0, 0.5)
	_check(b.clock > 1.0, "clock runs after start")
	pup.apply_snapshot(b.snapshot())
	_check(not pup.deploying, "puppet leaves the deploy phase from the host snapshot")
	b.queue_free()
	pup.queue_free()
	await get_tree().process_frame
	var b2 = _battle(plan)
	b2.deploy_left = 0.5
	await _run(b2, 1.5, 0.5)
	_check(not b2.deploying, "deploy deadline starts the fight by itself")
	b2.queue_free()
	await get_tree().process_frame


static func _min_gap(us: Array) -> float:
	var best := INF
	for i in us.size():
		for j in range(i + 1, us.size()):
			if absf(us[i].global_position.y - us[j].global_position.y) < 0.3:
				best = minf(best, Formation.flat_distance(us[i].global_position, us[j].global_position))
	return best

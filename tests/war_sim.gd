extends Node
## 공성전 반복 시뮬레이션(개발용, 헤드리스 — 서버·DB 없이 이 기기 안에서만): 시드마다 규모·영웅·레벨·면 배치·플레이어 명령을 바꿔
## 전투를 끝까지 돌리고, 0.5초마다 이상한 장면(성벽·성채 속, 닫힌 성 안의 공격, 성벽 너머 공격, 허공, 맵 밖, 멈춤, 겹침, 노는 공격)을 센다.
## 판마다 한 줄 JSON(--out 파일). 실행: godot --headless --fixed-fps 30 --path . res://tests/war_sim.tscn -- --from=0 --to=25 --out=/path/runs.jsonl

const WarCheck := preload("res://tests/war_check.gd")
const BattleScript := preload("res://scripts/war_battle.gd")
const GameData := preload("res://scripts/game_data.gd")
const Formation := preload("res://scripts/formation.gd")
const WarRules := preload("res://scripts/war_rules.gd")
const Balance := preload("res://scripts/balance.gd")
const HeroScript := preload("res://scripts/hero.gd")

const SAMPLE := 0.5
const STUCK_SEC := 15.0
const IDLE_SEC := 30.0
const PILE_D := 0.5
const EXAMPLES := 3

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	GameData._config.fx_shake = "0"
	var a := int(_arg("from", "0"))
	var z := int(_arg("to", "10"))
	var out := _arg("out", "user://war_sim.jsonl")
	var f := FileAccess.open(out, FileAccess.WRITE)
	for sd in range(a, z):
		var r: Dictionary = await _one(sd)
		f.store_line(JSON.stringify(r))
		f.flush()
		print("run %d: %s %s" % [sd, JSON.stringify(r.result), JSON.stringify(r.anomalies.keys())])
	f.close()
	get_tree().quit()


## 시드 하나의 판: 규모·영웅·레벨·수비 배율·면 배치·플레이어 명령을 정한다.
func _scenario(sd: int) -> Dictionary:
	_rng.seed = sd * 7919 + 17
	seed(sd * 104729 + 3)
	var att_n := _rng.randi_range(3, 20)
	var def_n := _rng.randi_range(5, 20)
	var att_lv := _rng.randi_range(15, 60)
	var def_lv := clampi(att_lv + _rng.randi_range(-15, 15), 10, 60)
	var mult := _rng.randf_range(0.7, 1.4)
	var plan: Dictionary = WarCheck.make_plan(att_n, def_n, mult, att_lv, def_lv)
	var ids := GameData.heroes().map(func(h): return str(h.id))
	for d in plan.defenders:
		var id: String = ids[_rng.randi() % ids.size()]
		var st := GameData.hero_stats(GameData.hero(id), def_lv, 2, {})
		d.hero = id
		d.hp = st.hp * mult
		d.atk = st.atk * mult
	var guild_lv := 1 + sd % 20  # 성 주인 길드 레벨(성문 체력 = 레벨 × GATE_HP_PER_LEVEL)
	var lane_mode := _rng.randi_range(0, 2)  # 0 = 고르게, 1 = 한 면 몰빵, 2 = 무작위
	var focus := _rng.randi_range(0, 3)
	for s in plan.attackers:
		for h in s.heroes:
			var id: String = ids[_rng.randi() % ids.size()]
			var st := GameData.hero_stats(GameData.hero(id), att_lv, 2, {})
			h.hero = id
			h.hp = st.hp
			h.atk = st.atk
		if lane_mode == 1:
			s.lane = focus
		elif lane_mode == 2:
			s.lane = _rng.randi_range(0, 3)
	# 성문은 길드 레벨, 성채는 바뀐 수비 영웅 기준으로 다시(서버 castleMax와 같은 식)
	var hp_lane := [0.0, 0.0, 0.0, 0.0]
	var hp_all := 0.0
	for d in plan.defenders:
		hp_lane[int(d.lane)] += float(d.hp)
		hp_all += float(d.hp)
	for s in 4:
		var g := WarRules.gate_hp_max(guild_lv)
		plan.gates[s] = {"hp": g, "max": g}
	var k := WarRules.keep_hp_max(hp_all)
	plan.keep = {"hp": k, "max": k}
	plan.deploy_left = 3.0
	return {"plan": plan, "att_n": att_n, "def_n": def_n, "att_lv": att_lv, "def_lv": def_lv, "mult": snappedf(mult, 0.01), "guild_lv": guild_lv,
		"lane_mode": ["even", "one_side", "random"][lane_mode], "orders": _rng.randf() < 0.4, "deploy_moves": _rng.randf() < 0.5}


func _one(sd: int) -> Dictionary:
	var sc := _scenario(sd)
	var plan: Dictionary = sc.plan
	var b = BattleScript.new()
	b.plan = plan
	add_child(b)
	await get_tree().process_frame
	var half: float = b.half
	# 배치 단계: 반쯤은 분대를 무작위 자리로 옮겨 본다(다른 면·성벽 틈·성 안 쪽을 눌러도 성 밖 배치 구역으로 밀린다)
	if sc.deploy_moves:
		for u in b.units(0):
			if _rng.randf() < 0.5:
				var ang := _rng.randf() * TAU
				var r := _rng.randf_range(10.0, 70.0)
				b.deploy_unit(u, Vector3(cos(ang) * r, 0.0, sin(ang) * r))
	var deployed_bad := 0
	for u in b.units(0):
		if Formation.is_inside(half, u.global_position) or Formation.in_wall_body(half, u.global_position):
			deployed_bad += 1
	b.begin_fight()
	var an := {}
	var stats := {"samples": 0, "pile_samples": 0, "pile_max": 0, "max_cap_ratio": 0.0}
	var track := {}  # uid → {pos, still, idle}
	var t := 0.0
	var next_order := 10.0
	var att_dps := 0.0
	for s in plan.attackers:
		for h in s.heroes:
			att_dps += float(h.atk) / maxf(0.1, float(GameData.hero(str(h.hero)).atk_interval))
	var first_gate := -1.0
	while not b.done and t < WarRules.BATTLE_SEC + 5.0:
		await get_tree().create_timer(SAMPLE, true, false, true).timeout
		t += SAMPLE
		if first_gate < 0.0 and b.gates_broken() > 0:
			first_gate = b.clock
		if sc.orders and b.clock >= next_order:
			next_order = b.clock + _rng.randf_range(5.0, 15.0)
			_random_order(b)
		_sample(b, an, stats, track)
		if int(t / SAMPLE) % 20 == 0:
			var ratio := _damage(b, plan) / maxf(1.0, att_dps * maxf(1.0, b.clock) * 10.0)
			stats.max_cap_ratio = maxf(stats.max_cap_ratio, ratio)
	var res: Dictionary = b.result.duplicate() if b.done else {"clock": b.clock, "unfinished": true}
	var dmg := _damage(b, plan)
	var cap := att_dps * maxf(1.0, b.clock) * 10.0
	var alive_att := b.units(0).filter(func(u): return u.is_alive()).size()
	var alive_def := b.units(1).filter(func(u): return u.is_alive()).size()
	var out := {"seed": sd, "att_n": sc.att_n, "def_n": sc.def_n, "att_lv": sc.att_lv, "def_lv": sc.def_lv, "mult": sc.mult,
		"lane_mode": sc.lane_mode, "orders": sc.orders, "deploy_moves": sc.deploy_moves, "deployed_bad": deployed_bad,
		"result": {"clock": snappedf(b.clock, 0.1), "kills": b.kills, "defenders": plan.defenders.size(), "gates": b.gates_broken(),
			"keep_pct": snappedf(b.keep.hp_ratio() * 100.0, 0.1), "keep_broken": not b.keep.is_alive(), "att_deaths": b.attacker_deaths,
			"alive_att": alive_att, "alive_def": alive_def, "first_gate": snappedf(first_gate, 0.1), "points": b.points_now(),
			"timeout": b.clock >= WarRules.BATTLE_SEC - 0.5 and b.keep.is_alive(),
			"cap_ratio": snappedf(dmg / maxf(1.0, cap), 0.001), "max_cap_ratio": snappedf(stats.max_cap_ratio, 0.001)},
		"samples": stats.samples, "pile_samples": stats.pile_samples, "pile_max": stats.pile_max, "anomalies": an}
	b.queue_free()
	for n in get_children():
		if n != b:
			n.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return out


## 서버 saveState와 같은 셈: 성문·성채 깎인 양 + 수비 영웅 깎인 체력.
func _damage(b, plan: Dictionary) -> float:
	var d := 0.0
	for i in 4:
		d += maxf(0.0, float(plan.gates[i].max) - b.gates[i].hp)
	d += maxf(0.0, float(plan.keep.max) - b.keep.hp)
	for u in b.units(1):
		d += (1.0 - (u.hp_ratio() if u.is_alive() else 0.0)) * u.hp_max
	return d


## 플레이어 흉내: 공격 영웅 하나에 무작위 이동 명령(성 안·성벽 속·맞은편 포함), 가끔 자동으로 되돌린다.
func _random_order(b) -> void:
	var atts: Array = b.units(0).filter(func(u): return u.is_alive())
	if atts.is_empty():
		return
	var u = atts[_rng.randi() % atts.size()]
	if _rng.randf() < 0.25:
		u.commanded = false
		return
	var ang := _rng.randf() * TAU
	var r := _rng.randf_range(2.0, 55.0)
	u.move_to_point(Vector3(cos(ang) * r, 0.0, sin(ang) * r))


func _note(an: Dictionary, kind: String, msg: String) -> void:
	if not an.has(kind):
		an[kind] = {"n": 0, "ex": []}
	an[kind].n += 1
	if an[kind].ex.size() < EXAMPLES:
		an[kind].ex.append(msg)


func _desc(b, u) -> String:
	var p: Vector3 = u.global_position
	var h: Vector3 = u.stand_position()
	var tg = u.current_target()
	var ts := "-" if tg == null else "(%.1f,%.1f,%.1f)" % [tg.global_position.x, tg.global_position.y, tg.global_position.z]
	var nx := "-" if u._path.is_empty() else "(%.1f,%.1f)" % [u._path[0].x, u._path[0].z]
	return "t=%.1f %s#%d %s %s (%.1f,%.1f,%.1f) st%d cmd%d home(%.1f,%.1f,%.1f) path%d next%s tgt%s spd%.1f stun%d root%d knock%d" % [b.clock, "att" if u.team == 0 else "def", u.uid, str(u.def.id), u.role,
		p.x, p.y, p.z, u.state, int(u.commanded), h.x, h.y, h.z, u._path.size(), nx, ts, u._speed, int(u.is_stunned()), int(u.has_status("root")), int(u.has_status("knockback"))]


func _sample(b, an: Dictionary, stats: Dictionary, track: Dictionary) -> void:
	stats.samples += 1
	var half: float = b.half
	var open: Array = b.open_sides()
	var any_open := open.has(true)
	var ground := []
	for team in 2:
		for u in b.units(team):
			if not u.is_alive():
				track.erase(u)
				continue
			var p: Vector3 = u.global_position
			var key := "%d:%d" % [team, u.uid]
			var m := maxf(absf(p.x), absf(p.z))
			if Formation.in_wall_body(half, p):
				_note(an, "in_wall_body", _desc(b, u))
			if p.y < Balance.WALL_H / 2.0 and m < Formation._keep_half - 0.3:
				_note(an, "in_keep", _desc(b, u) + " | before: " + str(track.get(key, {}).get("last", "")))
			if team == 0 and p.y < Balance.WALL_H / 2.0 and Formation.is_inside(half, p) and not any_open:
				_note(an, "attacker_inside_closed_castle", _desc(b, u))
			if team == 0 and p.y < Balance.WALL_H / 2.0 and m > half and m < half + Balance.WALL_T and not open[Formation.side_of(p)]:
				_note(an, "attacker_in_closed_gate_passage", _desc(b, u) + " open %s" % str(open))
			if team == 0 and p.y > Balance.WALL_H / 2.0:
				_note(an, "attacker_on_wall", _desc(b, u))
			var near_stairs := m > half - Balance.STAIR_W - 0.6 and m < half + 0.6
			if p.y > 0.05 and p.y < Balance.WALL_H - 0.05 and not near_stairs:
				_note(an, "floating", _desc(b, u))
			if p.y >= Balance.WALL_H - 0.05 and (m < half - Balance.STAIR_W - 0.6 or m > half + Balance.WALL_T + 0.1):
				_note(an, "on_air_beyond_wall", _desc(b, u))
			if absf(p.x) > Balance.MAP_HALF or absf(p.z) > Balance.MAP_HALF:
				_note(an, "off_map", _desc(b, u))
			var tg = u.current_target()
			if tg != null and tg.get("is_structure") != true and u.state == HeroScript.State.ATTACK:
				if not u.sees(p, tg.global_position):
					_note(an, "attack_through_wall", _desc(b, u) + " -> #%d (%.1f,%.1f,%.1f) open %s" % [tg.uid, tg.global_position.x, tg.global_position.y, tg.global_position.z, str(open)])
				if u.role != "ranged" and not u.is_on_wall() and tg.global_position.y > Balance.WALL_H / 2.0:
					_note(an, "melee_hits_wall_top", _desc(b, u))
				if Formation.flat_distance(p, tg.global_position) > float(u.def.range) + 3.0 and not u.is_stunned() and not u.has_status("knockback") and u._cast_t <= 0.0:
					_note(an, "attack_out_of_range", _desc(b, u))
			# 멈춤·놀기
			var tr: Dictionary = track.get(key, {"pos": p, "still": 0.0, "idle": 0.0, "noted_s": false, "noted_i": false})
			var moved := Formation.flat_distance(p, tr.pos) + absf(p.y - tr.pos.y)
			var busy: bool = tg != null or u.is_stunned() or u.has_status("root")
			var far: bool = Formation.flat_distance(p, u.stand_position()) > 3.0 or absf(p.y - u.stand_position().y) > 1.0
			if moved < 0.05 and not busy and far:
				tr.still += SAMPLE
			else:
				tr.still = 0.0
				tr.noted_s = false
			if tr.still >= STUCK_SEC and not tr.noted_s:
				tr.noted_s = true
				_note(an, "stuck_away_from_post", _desc(b, u) + " home (%.1f,%.1f,%.1f) path %d" % [u.stand_position().x, u.stand_position().y, u.stand_position().z, u._path.size()])
			if team == 0 and not u.commanded and tg == null and not u.is_walking() and b.keep.is_alive():
				tr.idle += SAMPLE
			else:
				tr.idle = 0.0
				tr.noted_i = false
			if tr.idle >= IDLE_SEC and not tr.noted_i:
				tr.noted_i = true
				_note(an, "auto_attacker_idle_30s", _desc(b, u) + " lane %d gate %s defenders_at %d" % [u.lane, "up" if b.gate(u.lane).is_alive() else "down", b.defenders_at(u.lane)])
			tr.pos = p
			tr.last = _desc(b, u)
			track[key] = tr
			if p.y < Balance.WALL_H / 2.0:
				ground.append(u)
			if team == 1 and u.role == "ranged" and p.y > Balance.WALL_H / 2.0 and u.post_pos.y < Balance.WALL_H / 2.0 and not u.is_walking():
				_note(an, "archer_stuck_on_wall_off_post", _desc(b, u))
	var piles := 0
	for i in ground.size():
		var a: Vector3 = ground[i].global_position
		for j in range(i + 1, ground.size()):
			if Formation.flat_distance(a, ground[j].global_position) < PILE_D:
				piles += 1
	if piles >= 3:
		stats.pile_samples += 1
	stats.pile_max = maxi(stats.pile_max, piles)


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % k):
			return a.substr(k.length() + 3)
	return d

extends Node
## 전투 로직 점검 시뮬레이션(개발용, 헤드리스): 실제 전투 코드(성 스테이지·던전·PVP 결투·총력전)를 n판 돌리며 영웅 행동을 기록한다.
## 한 판 = 무작위 팀(등급·근접/원거리·레벨·승급) → 끝날 때까지 매 프레임 관찰 → JSON 한 줄("SIMROW {...}").
## 실행: godot --headless --fixed-fps 30 --path . res://tests/combat_sim.tscn -- --mode=duel --n=25 --seed=1 [--keep=15]
## mode = stage(성, --keep 성채 레벨: 슬롯 4/8/12) · dungeon(gold·equip·ticket 섞어) · duel · total.
## 기록(영웅마다): 상태별 시간, 사거리 안에 적이 있는데 가만히 선 시간, 걷는데 제자리인 시간, 헛스윙·끊긴 스윙, 표적 바꾸기,
## 스킬 발동·불발·해금됐는데 못 쓴 것, 쓰러진 시각. 적: 나타나서 쓰러질 때까지 초. 소환수: 수명 중 가만히 있던 시간.

const GameData := preload("res://scripts/game_data.gd")
const Formation := preload("res://scripts/formation.gd")
const HeroSkillsScript := preload("res://scripts/hero_skills.gd")
const DungeonScript := preload("res://scripts/dungeon.gd")
const PvpBattleScript := preload("res://scripts/pvp_battle.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")

const DT := 1.0 / 30.0
const STUCK_WIN := 1.5  # 걷는 중 이 시간 동안 STUCK_MOVE m도 못 가면 막힘
const STUCK_MOVE := 0.15
const SWING_SLACK := 0.6

class ErrorCounter extends Logger:
	var count := 0
	var first := []
	func _log_error(fn: String, file: String, line: int, _code: String, why: String, _notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1
			if first.size() < 8:
				first.append("%s:%d %s %s" % [file, line, fn, why])

var rng := RandomNumberGenerator.new()
var _errors := ErrorCounter.new()
var _main
var _t := 0.0
var _heroes: Array = []  # 관찰 중인 영웅 노드
var _hm := {}  # 노드 id → 기록
var _enemies := {}  # 노드 id → {kind, born, dead, boss}
var _summons := {}  # 노드 id → {kind, born, still, last_pos, gone}
var _watch := false


func _ready() -> void:
	OS.add_logger(_errors)
	Economy.save_path = ""
	Fever.save_path = ""
	Fever.reset()
	GameData._config.fx_shake = "0"
	Economy.reset(Time.get_unix_time_from_system())
	Pvp.save_path = ""
	Pvp.load_save()
	rng.seed = int(_arg("seed", "1"))
	var mode := _arg("mode", "duel")
	var n := int(_arg("n", "10"))
	for h in GameData.heroes():
		Economy.heroes[str(h.id)] = 1
	if mode == "stage":
		await _stage_runs(n, int(_arg("keep", "5")))
	else:
		for i in n:
			var row: Dictionary
			match mode:
				"dungeon":
					row = await _dungeon_run(i)
				_:
					row = await _pvp_run(mode, i)
			_emit(row)
	print("SIM ERRORS %d %s" % [_errors.count, JSON.stringify(_errors.first)])
	get_tree().quit()


# --- 팀 ---

const TEMPLATES := ["mixed", "ssr", "sr", "r", "melee", "ranged", "mixed", "mixed"]

func _pick_team(size: int, template: String) -> Array:
	var pool := []
	for h in GameData.heroes():
		match template:
			"ssr":
				if h.grade != "SSR": continue
			"sr":
				if h.grade != "SR": continue
			"r":
				if h.grade != "R": continue
			"melee":
				if h.role != "melee": continue
			"ranged":
				if h.role != "ranged": continue
		pool.append(str(h.id))
	if pool.size() < size:  # 모자라면 아무나로 채운다
		for h in GameData.heroes():
			if not pool.has(str(h.id)):
				pool.append(str(h.id))
	_shuffle(pool)
	return pool.slice(0, size)


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


## 팀 영웅마다 레벨·승급을 Economy에 넣는다(내 영웅 능력치는 Economy에서 읽는다).
func _set_levels(ids: Array, lv_lo: int, lv_hi: int) -> void:
	for id in ids:
		Economy.hero_levels[id] = rng.randi_range(lv_lo, lv_hi)
		Economy.hero_promotions[id] = rng.randi_range(0, GameData.MAX_PROMOTION)


# --- 성 스테이지 ---

func _stage_runs(n: int, keep: int) -> void:
	Economy.levels[GameData.KEEP] = keep
	Economy.levels[GameData.GATE] = keep
	var slots := GameData.hero_slots(keep)
	var team := _pick_team(slots, "mixed")
	Economy.deploy = team.duplicate()
	_set_levels(team, 1, 1)
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	for i in 5:
		await get_tree().process_frame
	GameState.auto_continue = false
	for i in n:
		var template: String = TEMPLATES[i % TEMPLATES.size()]
		team = _pick_team(slots, template)
		Economy.deploy = team.duplicate()
		var lo := 3 if keep < 9 else (20 if keep < 22 else 60)
		var round_g := rng.randi_range(lo, lo * 4)
		var lv := clampi(int(round_g * 0.8) + 10, 5, 150)
		_set_levels(team, maxi(1, lv - 10), lv + 10)
		Economy.roster_changed.emit()  # 대기 중이면 곧바로 다시 만든다
		for k in 3:
			await get_tree().process_frame
		GameState.stage = round_g
		_begin_watch()
		var result := [""]
		var on_clear := func(_s): result[0] = "win"
		var on_fail := func(_s): result[0] = "loss"
		GameState.stage_cleared.connect(on_clear)
		GameState.stage_failed.connect(on_fail)
		GameState.start_stage()
		var heroes := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.has_method("active_slots"))
		_track_heroes(heroes, "monsters")
		var limit := 240.0
		while result[0] == "" and _t < limit:
			await get_tree().process_frame
		GameState.stage_cleared.disconnect(on_clear)
		GameState.stage_failed.disconnect(on_fail)
		var row := _finish_watch()
		row.mode = "stage"
		row.keep = keep
		row.round = round_g
		row.template = template
		row.result = result[0] if result[0] != "" else "timeout"
		row.castle_hp = GameState.castle_hp / maxf(1.0, GameState.castle_hp_max)
		_emit(row)
		if GameState.mode == GameState.Mode.STAGE:
			GameState.stop_stage()
		while GameState.mode != GameState.Mode.IDLE:
			await get_tree().process_frame
		for k in 3:
			await get_tree().process_frame


# --- 던전 ---

func _dungeon_run(i: int) -> Dictionary:
	var types := ["gold", "equip", "ticket"]
	var type: String = types[i % 3]
	var template: String = TEMPLATES[i % TEMPLATES.size()]
	var size := 4 if type != "ticket" else 3
	var party := _pick_team(size, template)
	var level := rng.randi_range(1, 40)
	var lv := clampi(level * 3, 5, 120)
	_set_levels(party, maxi(1, lv - 10), lv + 10)
	var run := {"run_id": "sim%d" % i, "type": type, "level": level, "party": party, "enemies": GameData.dungeon_enemies(type, level),
		"time_limit": GameData.config_num("dungeon_time_limit")}
	var d = DungeonScript.new()
	d.run = run
	add_child(d)
	await get_tree().process_frame
	_begin_watch()
	_track_heroes(d.heroes, "monsters")
	while d.phase == DungeonScript.Phase.FIGHT and _t < 200.0:
		await get_tree().process_frame
	var win: bool = d.phase != DungeonScript.Phase.FIGHT and d.heroes.any(func(h): return h.is_alive()) and d.enemies_left() == 0
	var row := _finish_watch()
	row.mode = "dungeon"
	row.type = type
	row.level = level
	row.template = template
	row.result = "win" if win else ("timeout" if d.heroes.any(func(h): return h.is_alive()) else "loss")
	d.main = null
	d.queue_free()
	for k in 3:
		await get_tree().process_frame
	return row


# --- PVP ---

func _pvp_run(mode: String, i: int) -> Dictionary:
	var ta: String = TEMPLATES[i % TEMPLATES.size()]
	var tb: String = TEMPLATES[(i * 3 + 1) % TEMPLATES.size()]
	var mine := _pick_team(5, ta)
	_set_levels(mine, 40, 60)
	var opp := []
	for id in _pick_team(5, tb):
		opp.append({"hero": id, "level": rng.randi_range(40, 60), "promotion": rng.randi_range(0, GameData.MAX_PROMOTION)})
	var soldiers := {"infantry:2": 8, "archer:1": 6, "cavalry:3": 6}
	var run := {"mode": mode, "me": mine, "my_soldiers": soldiers, "time": 90.0 if mode == "duel" else 120.0,
		"opponent": {"name": "sim", "heroes": opp, "soldiers": soldiers}, "gain": 10, "loss": 10}
	var b = PvpBattleScript.new()
	b.run = run
	add_child(b)
	while b.phase == PvpBattleScript.Phase.INTRO:
		await get_tree().process_frame
	_begin_watch()
	_track_heroes(b._heroes[0] + b._heroes[1], "")
	for s in b._soldiers[0] + b._soldiers[1]:
		_enemies[s.get_instance_id()] = {"kind": "soldier", "born": 0.0, "dead": -1.0, "boss": false, "node": s, "team": s.team}
	while b.phase != PvpBattleScript.Phase.RESULT and _t < 200.0:
		await get_tree().process_frame
	var row := _finish_watch()
	row.mode = mode
	row.template = ta + "_vs_" + tb
	row.result = "win" if b.alive(1) == 0 else ("loss" if b.alive(0) == 0 else "time")
	row.clock = b.clock
	row.alive = [b.alive(0), b.alive(1)]
	row.team_hp = [b.team_hp(0), b.team_hp(1)]
	b.queue_free()
	for k in 3:
		await get_tree().process_frame
	return row


# --- 관찰 ---

func _begin_watch() -> void:
	_t = 0.0
	_heroes = []
	_hm = {}
	_enemies = {}
	_summons = {}
	_watch = true


func _track_heroes(list: Array, _foes: String) -> void:
	for h in list:
		_heroes.append(h)
		var skills := {}
		for k in h._sk:
			if HeroSkillsScript.is_active(k):
				skills[k] = {"casts": 0, "fizz": 0, "prev": _cd(h, k)}
		_hm[h.get_instance_id()] = {"id": str(h.def.id), "grade": str(h.def.grade), "role": str(h.role), "team": int(h.get("team") if h.get("team") != null else 0),
			"level": h._level, "promo": h._promotion, "hp_max": h.hp_max, "atk": h.atk,
			"idle": 0.0, "move": 0.0, "attack": 0.0, "cast": 0.0, "stun": 0.0, "alive": 0.0,
			"idle_foe_in_reach": 0.0, "idle_foe_anywhere": 0.0, "no_target_foe_in_aggro": 0.0, "stuck": 0.0, "dist": 0.0,
			"swings": 0, "whiffs": 0, "cut": 0, "retarget": 0, "died": -1.0,
			"skills": skills, "_pos": h.global_position, "_win": [], "_swing": null, "_target": null, "_attacks": h._attacks}


func _cd(h, k: String) -> float:
	match k:
		"heal_aura":
			return h._heal_cd
		"gate_repair":
			return h._repair_cd
		"aoe_blast":
			return h._blast_cd
	return h._skx.cd_left(k)


func _foes_of(h) -> Array:
	return get_tree().get_nodes_in_group(h.foes).filter(func(f): return is_instance_valid(f) and f.has_method("is_alive") and f.is_alive())


func _process(_delta: float) -> void:
	if not _watch:
		return
	_t += DT
	# 적
	for m in get_tree().get_nodes_in_group("monsters"):
		if m.get("team") != null:
			continue  # PVP 상대 영웅·병사는 영웅·병사로 센다
		var id := m.get_instance_id()
		if not _enemies.has(id):
			_enemies[id] = {"kind": str(m.kind), "born": _t, "dead": -1.0, "boss": bool(m.is_boss), "node": m, "team": 1}
	for id in _enemies:
		var e: Dictionary = _enemies[id]
		if e.dead < 0.0 and (not is_instance_valid(e.node) or not e.node.is_alive()):
			e.dead = _t
	# 소환수
	for s in get_tree().get_nodes_in_group("summons"):
		var id := s.get_instance_id()
		if not _summons.has(id):
			_summons[id] = {"kind": str(s.get("kind")), "born": _t, "still": 0.0, "still_foe": 0.0, "last": s.global_position, "gone": -1.0, "node": s, "attacks": 0}
	for id in _summons:
		var r: Dictionary = _summons[id]
		if r.gone >= 0.0:
			continue
		if not is_instance_valid(r.node) or r.node.is_queued_for_deletion():
			r.gone = _t
			continue
		var p: Vector3 = r.node.global_position
		var foe_near := false
		var owner = r.node.get("owner_hero") if r.node.get("owner_hero") != null else null
		var group := str(r.node.get("foes")) if r.node.get("foes") != null else "monsters"
		for f in get_tree().get_nodes_in_group(group):
			if f.is_alive() and Formation.flat_distance(p, f.global_position) <= 8.0:
				foe_near = true
				break
		if r.node.get("_target") == null:
			r.still += DT  # 표적 없음
			if foe_near:
				r.still_foe += DT  # 10 m 안에 적이 있는데 표적 없음
		r.attacks = int(r.node.get("hits"))
		r.last = p
	# 영웅
	for h in _heroes:
		if not is_instance_valid(h):
			continue
		var r: Dictionary = _hm[h.get_instance_id()]
		if not h.is_alive():
			if r.died < 0.0:
				r.died = _t
			continue
		r.alive += DT
		var p: Vector3 = h.global_position
		r.dist += Vector2(p.x - r._pos.x, p.z - r._pos.z).length()
		r._pos = p
		var st: int = h.state
		var casting: bool = h._cast_t > 0.0
		if h.is_stunned():
			r.stun += DT
		elif casting:
			r.cast += DT
		elif st == h.State.IDLE:
			r.idle += DT
		elif st == h.State.MOVE:
			r.move += DT
		elif st == h.State.ATTACK:
			r.attack += DT
		var foes := _foes_of(h)
		if not h.is_stunned() and not casting and st == h.State.IDLE and not foes.is_empty():
			r.idle_foe_anywhere += DT
			var reach := float(h.def.range)
			var aggro := maxf(float(h.def.aggro), reach)
			var nearest := INF
			for f in foes:
				nearest = minf(nearest, Formation.flat_distance(p, f.global_position) - (float(f.hit_radius()) if f.has_method("hit_radius") else 0.0))
			if nearest <= reach:
				r.idle_foe_in_reach += DT
			if nearest <= aggro and h._target == null:
				r.no_target_foe_in_aggro += DT
		# 걷는데 제자리
		if st == h.State.MOVE and not h.is_stunned():
			r._win.append([_t, p])
			while not r._win.is_empty() and _t - r._win[0][0] > STUCK_WIN:
				r._win.pop_front()
			if _t - r._win[0][0] >= STUCK_WIN - 2 * DT and Formation.flat_distance(r._win[0][1], p) < STUCK_MOVE:
				r.stuck += DT
		else:
			r._win.clear()
		# 스윙: 새 공격 / 스윙이 끝날 때 근접 사거리 밖이면 헛스윙, 이동·기절로 끊기면 cut
		if h._attacks != r._attacks:
			r.swings += h._attacks - r._attacks
			r._attacks = h._attacks
		var sw = h._swing
		if r._swing != null and sw == null:
			var m = r._swing
			if is_instance_valid(m) and m.is_alive():
				if h._swing_left > 0.0:
					r.cut += 1
				elif h.role != "ranged" and Formation.flat_distance(p, m.global_position) > h._reach(m) + SWING_SLACK:
					r.whiffs += 1
		r._swing = sw
		var tg = h._target
		if tg != null and r._target != null and tg != r._target and is_instance_valid(r._target) and r._target.is_alive():
			r.retarget += 1
		if tg != null:
			r._target = tg
		# 스킬: 쿨이 1초 넘게 뛰면 발동 시작, 큰 쿨이 RETRY로 떨어지면 불발
		for k in r.skills:
			var s: Dictionary = r.skills[k]
			var c := _cd(h, k)
			if c - s.prev > 1.0:
				s.casts += 1
			elif s.prev > 1.0 and c <= HeroSkillsScript.RETRY + 0.01 and s.prev - c > 0.5:
				s.fizz += 1
				if _arg("dbg", "") != "":
					var ft = h._target
					var ok: bool = ft != null and is_instance_valid(ft) and ft.is_alive()
					print("FIZZ %s %s t=%.2f %.2f->%.2f wall=%s tgt_alive=%s d=%.2f reach=%.2f stun=%s" % [h.def.id, k, _t, s.prev, c, h.is_on_wall(), ok,
						Formation.flat_distance(h.global_position, ft.global_position) if ok else -1.0, h._reach(ft) if ok else -1.0, h.is_stunned()])
			s.prev = c


func _finish_watch() -> Dictionary:
	_watch = false
	var heroes := []
	for h in _heroes:
		var r: Dictionary = _hm.get(h.get_instance_id() if is_instance_valid(h) else 0, {})
		if r.is_empty():
			continue
		var out := r.duplicate(true)
		for k in ["_pos", "_win", "_swing", "_target", "_attacks"]:
			out.erase(k)
		for k in out.skills:
			out.skills[k].erase("prev")
			out.skills[k]["cd"] = float(h._sk[k][0]) if is_instance_valid(h) else 0.0
		heroes.append(out)
	var enemies := []
	for id in _enemies:
		var e: Dictionary = _enemies[id]
		enemies.append({"kind": e.kind, "boss": e.boss, "team": e.team, "life": (e.dead if e.dead >= 0.0 else _t) - e.born, "killed": e.dead >= 0.0})
	var summons := []
	for id in _summons:
		var s: Dictionary = _summons[id]
		summons.append({"kind": s.kind, "life": (s.gone if s.gone >= 0.0 else _t) - s.born, "still": s.still, "still_foe": s.still_foe, "hits": s.attacks})
	return {"dur": _t, "heroes": heroes, "enemies": enemies, "summons": summons}


func _emit(row: Dictionary) -> void:
	print("SIMROW " + JSON.stringify(row))


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % k):
			return a.substr(k.length() + 3)
	return d

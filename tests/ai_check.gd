extends Node
## 헤드리스 AI 체크: 실제 main 씬(오토로드 포함)에서 영웅·몬스터 인식·추격·복귀·영역 규칙을 확인한다.
## 실행: ./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/ai_check.tscn
## 오토로드를 쓰므로 tests/run_tests.gd(-s)에서 preload 금지. 스포너를 멈추고 몬스터를 직접 놓는다.

const Balance := preload("res://scripts/balance.gd")
const GameData := preload("res://scripts/game_data.gd")
const Formation := preload("res://scripts/formation.gd")
const MonsterScript := preload("res://scripts/monster.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")
const HeroScript := preload("res://scripts/hero.gd")

class ErrorCounter extends Logger:
	var count := 0
	func _log_error(_fn: String, _file: String, _line: int, _code: String, _why: String, _notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1

var _fails := 0
var _errors := ErrorCounter.new()
var _main
var _half := 0.0
var _g  # 지금 사례의 몬스터. 멤버로 둔다 — 지역 변수를 람다가 캡처하면 노드가 해제된 뒤 호출마다 엔진 오류가 난다


func _ready() -> void:
	OS.add_logger(_errors)
	Economy.save_path = ""  # 실제 저장 파일을 건드리지 않는다
	Economy.reset(Time.get_unix_time_from_system())
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(5)
	for c in _main.get_children():
		if c.get_script() == SpawnerScript:
			c.set_process(false)
	_clear_monsters()
	_half = _main.castle.half
	await _run()
	if _errors.count > 0:
		print("AI SCRIPT ERRORS %d" % _errors.count)
	_fails += _errors.count
	if _fails > 0:
		print("AI FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("AI ALL PASSED")
		get_tree().quit(0)


func _run() -> void:
	var heroes := get_tree().get_nodes_in_group("heroes")
	heroes.sort_custom(func(a, b): return a.index < b.index)
	var warrior = heroes[0]  # 기본 배치(시작 영웅): 슬롯 0 한스(근접) = 북(0) 성문 앞
	var archer = heroes[1]   # 슬롯 1 엘라(원거리) = 동(1) 성벽 위
	var warrior_hp: float = warrior.hp_max

	# 배치: 슬롯 i의 영웅 = deploy[i], 면 i % 4, melee는 성문 앞·ranged는 성벽 위
	var deploy: Array = GameState.deploy()
	_check(heroes.size() == deploy.size(), "deploy: one hero per filled slot", "heroes=%d deploy=%s" % [heroes.size(), deploy])
	for h in heroes:
		var want_post: int = Formation.POST_WALL if h.def.role == "ranged" else Formation.POST_GATE
		_check(h.def.id == deploy[h.index] and h.side == h.index % 4 and h.post == want_post and h.global_position.distance_to(h.stand_position()) < 0.01,
			"deploy: slot %d %s on side %d at its role post" % [h.index, h.def.id, h.index % 4], "id=%s side=%d post=%d pos=%s" % [h.def.id, h.side, h.post, h.global_position])

	# (a) 밖 자유 위치 전사와 5 m 떨어진 grunt가 서로 다가가 교전한다(북동쪽 벌판: 북쪽 바깥면에서 22 m, 모서리 너머 12 m)
	var outer := _half + Balance.WALL_T
	var post := Vector3(outer + 12.0, 0, -(outer + 22.0))
	warrior.move_to_point(post)
	await _wait_until(func(): return warrior._path.is_empty() and Formation.flat_distance(warrior.global_position, post) < 0.05, 10.0)
	_check(Formation.flat_distance(warrior.global_position, post) < 0.05, "(a) precondition: warrior stands at its free point", "pos=%s" % warrior.global_position)
	# 전사 -x 쪽: 이 grunt의 진로(북 성문 공격 지점)는 전사에게서 멀어지므로, 전사 쪽으로 오면 진로가 아니라 aggro 때문이다
	var start := post + Vector3(-5, 0, 0)
	_g = _spawn("grunt", 0, start)
	var toward_post := (post - start).normalized()
	var warrior_out := 0.0
	var grunt_in := 0.0
	var t := 0.0
	while t < 2.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		warrior_out = maxf(warrior_out, Formation.flat_distance(warrior.global_position, post))
		if _alive(_g):
			grunt_in = maxf(grunt_in, (_g.global_position - start).dot(toward_post))
	var alive := _alive(_g)
	var d := Formation.flat_distance(warrior.global_position, _g.global_position) if alive else 0.0
	var hurt: bool = warrior.hp < warrior_hp or (alive and _g.hp < _g.hp_max)
	_check(not alive or (d <= 2.0 and hurt), "(a) warrior and grunt close in and fight within 2 s",
		"alive=%s d=%.2f warrior_hp=%.0f grunt_hp=%.0f" % [alive, d, warrior.hp, _g.hp if alive else 0.0])
	_check(warrior_out > 1.0, "(a) warrior leaves its point to chase the grunt", "max distance from point %.2f" % warrior_out)
	_check(grunt_in > 0.5, "(a) grunt leaves its lane toward the warrior", "max approach %.2f" % grunt_in)

	# (b) grunt가 죽은 뒤 전사가 자기 자리로 돌아온다
	await _wait_until(func(): return not _alive(_g), 10.0)
	_check(not _alive(_g), "(b) precondition: the grunt dies", "grunt still alive")
	await _wait_until(func(): return Formation.flat_distance(warrior.global_position, post) < 0.2, 5.0)
	var bd := Formation.flat_distance(warrior.global_position, post)
	_check(bd < 0.2, "(b) warrior walks back to its point after the kill", "d=%.2f" % bd)

	# (c) 성 안 벽 근처 전사는 성 밖 grunt를 쫓지 않고, grunt도 그 전사에게 오지 않는다
	var inner := Vector3(8, 0, -(_half - 2.0))
	warrior.move_to_point(inner)
	await _wait_until(func(): return warrior._path.is_empty() and Formation.flat_distance(warrior.global_position, inner) < 0.05, 15.0)
	_check(Formation.flat_distance(warrior.global_position, inner) < 0.05, "(c) precondition: warrior reached the inside point through the gate", "pos=%s" % warrior.global_position)
	# 성벽 밖 1 m: 전사에서 5 m라 양쪽 aggro 안이다(3 m면 7 m로 grunt aggro 6 밖이라 grunt 쪽 영역 규칙을 시험하지 못한다)
	_g = _spawn("grunt", 0, Vector3(8, 0, -(_half + Balance.WALL_T + 1.0)))
	var whp: float = warrior.hp
	await _seconds(2.0)
	var cd := Formation.flat_distance(warrior.global_position, inner)
	_check(cd < 0.3 and warrior.hp == whp, "(c) inside warrior does not chase the outside grunt", "d=%.2f hp %.0f -> %.0f" % [cd, whp, warrior.hp])
	_check(_alive(_g) and _g._target_hero == null, "(c) outside grunt does not target the inside warrior", "alive=%s target=%s" % [_alive(_g), _g._target_hero if _alive(_g) else null])

	# (d) 성벽 위 궁수는 움직이지 않고 쏘며, grunt는 궁수를 치지 못한다
	_clear_monsters()
	await _frames(1)
	var apos: Vector3 = archer.global_position
	var ahp: float = archer.hp
	_g = _spawn("grunt", 1, Vector3(apos.x + 3.5, 0, apos.z))
	await _seconds(3.0)
	alive = _alive(_g)
	var moved: float = archer.global_position.distance_to(apos)
	_check(moved < 0.05 and archer.hp == ahp, "(d) wall-top archer holds position and takes no damage", "moved=%.2f hp %.0f -> %.0f" % [moved, ahp, archer.hp])
	_check(not alive or _g.hp < _g.hp_max, "(d) wall-top archer shoots the grunt below", "grunt hp %.0f/%.0f" % [_g.hp if alive else 0.0, _g.hp_max if alive else 0.0])

	# (d) 표적이 사거리 밖으로 걸어 나가도 성벽 위 궁수는 따라가지 않는다(성 안 성채로 가는 보스: 궁수에서 멀어진다).
	#     성 안 몬스터는 영역이 같아도 성벽 위 궁수를 치지 못한다
	_clear_monsters()
	await _frames(1)
	var reach: float = archer.def.range + 1.0
	_g = _spawn("epic_boss", 1, Vector3(apos.x - 2.0, 0, apos.z))
	await _wait_until(func(): return not _alive(_g) or Formation.flat_distance(_g.global_position, apos) > reach, 8.0)
	var bd2 := Formation.flat_distance(_g.global_position, apos) if _alive(_g) else 0.0
	moved = archer.global_position.distance_to(apos)
	_check(bd2 > reach and moved < 0.05 and archer.hp == ahp, "(d) wall-top archer does not follow a target walking out of range, and the inside boss cannot hit it",
		"boss %.2f m away, archer moved %.2f to %s, hp %.0f -> %.0f" % [bd2, moved, archer.global_position, ahp, archer.hp])

	# (e) 북쪽 면 소속이지만 동쪽 바깥에 놓인 grunt는 표적이 없으면 동쪽(1) 성문으로 재조준한다
	_clear_monsters()
	await _frames(1)
	_g = _spawn("grunt", 0, Vector3(_half + Balance.WALL_T + 10, 0, 5))
	await _seconds(0.5)
	_check(_alive(_g) and _g.side == 1, "(e) grunt spawned for the north but standing east re-targets the east gate", "alive=%s side=%d" % [_alive(_g), _g.side if _alive(_g) else -1])

	# (f) 부서진 성문: 축에서 벗어난 grunt는 성문 축에 맞춘 뒤 들어간다(성벽을 뚫지 않는다)
	_clear_monsters()
	await _frames(1)
	GameState.damage_gate(0, GameState.gate_hp_max)
	_g = _spawn("grunt", 0, Vector3(8, 0, -(_half + Balance.WALL_T + 1.0)))
	await _wait_until(func(): return not _alive(_g) or Formation.is_inside(_half, _g.global_position), 8.0)
	var entry: Vector3 = _g.global_position if _alive(_g) else Vector3.INF
	_check(Formation.is_inside(_half, entry) and absf(entry.x) < Balance.GATE_W / 2.0,
		"(f) grunt enters the broken north gate through the opening, not the wall", "first inside at %s" % entry)

	# (g) 부서진 성문으로 성 안에 들어가는 표적을 쫓던 지상 영웅(자리는 성 밖)은 문턱에서 멈추고(성 안팎 경계를 넘는 추격 걸음은
	#     딛지 않는다) 표적을 놓은 뒤 자리로 돌아간다. 실제로는 표적이 넘어간 뒤 다음 스캔(≤0.2초)이 먼저 표적을 놓을 수도 있어,
	#     스캔 시점을 테스트가 붙잡는다: 보스는 스캔을 멈춰(영웅과 싸우지 않고) 진로대로 성문으로 들어가고, 영웅은 표적을 잡은 뒤 스캔을 미룬다.
	_clear_monsters()
	await _frames(1)
	var gw = heroes[2]  # 기본 배치: 남(2) 성문 앞 전사
	var gpost: Vector3 = gw.stand_position()
	GameState.damage_gate(2, GameState.gate_hp_max)
	_g = _spawn("epic_boss", 2, gpost + Vector3(0, 0, 4.5))  # 성문 축 위. grunt는 전사 두 방에 죽어 성문까지 못 간다
	_g._scan_cd = INF
	await _wait_until(func(): return gw._target == _g, 2.0)
	_check(gw._target == _g, "(g) precondition: the south gate warrior targets the boss outside", "target=%s" % [gw._target])
	gw._scan_cd = INF
	var gw_in := false
	t = 0.0
	while t < 8.0 and not (gw._target == null and _alive(_g) and Formation.is_inside(_half, _g.global_position)):
		await get_tree().process_frame
		t += get_process_delta_time()
		gw_in = gw_in or Formation.is_inside(_half, gw.global_position)
	_check(not gw_in and gw._target == null and _alive(_g) and Formation.is_inside(_half, _g.global_position),
		"(g) warrior stops at the broken gate's threshold and drops the boss that walked in",
		"warrior went inside=%s pos=%s target=%s boss alive=%s" % [gw_in, gw.global_position, "boss" if gw._target == _g else str(gw._target), _alive(_g)])
	await _wait_until(func(): return gw._path.is_empty() and Formation.flat_distance(gw.global_position, gpost) < 0.05, 5.0)
	var gd := Formation.flat_distance(gw.global_position, gpost)
	_check(gd < 0.2, "(g) warrior walks back to its post", "d=%.2f pos=%s" % [gd, gw.global_position])

	# (h) 성 모서리 근처 밖 자유 위치 전사와 모서리 너머 동쪽 면의 grunt(성문 멀쩡): 둘 사이 직선이 성 모서리를 가로지른다.
	#     grunt는 추격하다 성벽 띠로 들어서지 않고(진로로 동쪽 성문으로 간다), 전사는 그 grunt를 잡지 않아 자리를 지킨다. 매 프레임 확인.
	#     전사: 북쪽 바깥면 2 m 밖, 모서리에서 x로 3 m 안쪽. grunt: 동쪽 바깥면 0.1 m 밖, z는 북쪽 성벽 띠 높이. 둘 사이 4.7 m(양쪽 aggro 안)
	var hpost := Vector3(_half - 1.0, 0, -(outer + 2.0))
	warrior.move_to_point(hpost)
	GameState.refill()  # 성문 복구·몬스터 제거, 영웅은 자리(방금 정한 자유 위치)로 옮겨진다
	await _frames(1)
	_g = _spawn("grunt", 1, Vector3(outer + 0.1, 0, -(_half + 0.5)))
	var g_in := false
	var w_in := false
	var w_out := 0.0
	t = 0.0
	while t < 4.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if _alive(_g):
			g_in = g_in or Formation.is_inside(_half, _g.global_position)
		w_in = w_in or Formation.is_inside(_half, warrior.global_position)
		w_out = maxf(w_out, Formation.flat_distance(warrior.global_position, hpost))
	_check(not g_in and GameState.castle_hp == GameState.castle_hp_max, "(h) grunt chasing across the castle corner never steps inside the wall line",
		"went inside=%s castle hp %.0f" % [g_in, GameState.castle_hp])
	_check(not w_in and w_out < 0.5, "(h) warrior does not chase the grunt across the castle corner",
		"went inside=%s max distance from point %.2f" % [w_in, w_out])

	# (i) 추격 끝에 자리(모서리 근처 북쪽 면 밖)의 이웃 동쪽 면 밖에 남은 전사는 모서리를 가로질러 곧장 가지 않고 성문 경로로 돌아간다.
	#     실제로는 맞서지 않고 면을 따라 걷는 괴물을 쫓을 때만 비결정적으로 생기므로 전사를 그 위치에 옮겨 놓는다. 매 프레임 성벽 띠(성문 폭 밖)에 들어서는지 본다.
	_clear_monsters()
	await _frames(1)
	warrior.global_position = Vector3(_half + Balance.WALL_T + 1.5, 0, -(_half - 2.0))
	var through_wall := false
	t = 0.0
	while t < 15.0 and not (warrior._path.is_empty() and Formation.flat_distance(warrior.global_position, hpost) < 0.05):
		await get_tree().process_frame
		t += get_process_delta_time()
		var p: Vector3 = warrior.global_position
		var ring := maxf(absf(p.x), absf(p.z))
		through_wall = through_wall or (ring >= _half and ring < _half + Balance.WALL_T and minf(absf(p.x), absf(p.z)) >= Balance.GATE_W / 2.0)
	var hd := Formation.flat_distance(warrior.global_position, hpost)
	_check(not through_wall and hd < 0.2, "(i) warrior left beside the castle corner walks home through the gates, not the corner",
		"crossed the wall band=%s d=%.2f pos=%s" % [through_wall, hd, warrior.global_position])

	# (j) 스포너가 만든 grunt를 처치하면 골드 +2, 리필로 사라지면 골드 없음
	_clear_monsters()
	await _frames(1)
	var spawner
	for c in _main.get_children():
		if c.get_script() == SpawnerScript:
			spawner = c
	var gold0: int = Economy.gold
	spawner._spawn({"kind": "grunt", "side": 0, "time": 0.0})
	var kid: Node = _main.get_child(_main.get_child_count() - 1)
	kid.take_damage(1.0e6)
	_check(Economy.gold == gold0 + GameData.kill_gold("grunt", GameState.stage) and GameData.kill_gold("grunt", 1) == 2, "(j) killing a grunt gives GameData.kill_gold (stage 1 = 2)", "gold %d -> %d" % [gold0, Economy.gold])
	spawner._spawn({"kind": "grunt", "side": 0, "time": 0.0})
	GameState.refill()
	await _frames(1)
	_check(Economy.gold == gold0 + GameData.kill_gold("grunt", GameState.stage), "(j) a monster removed by refill gives no gold", "gold %d" % Economy.gold)

	await _skill_cases(heroes)


## 스킬 대표 사례(스펙 §6). 기본 영웅은 멈추고(처리 끔) 시험 영웅 하나씩 더해 본다. 시험 영웅 index는 100+면(면 = index % 4).
func _skill_cases(heroes: Array) -> void:
	for h in heroes:
		if h.post == Formation.POST_FREE:  # 앞 사례가 자유 위치로 옮긴 영웅은 배치 자리로
			h.move_to(h.index % 4, Formation.POST_WALL if h.def.role == "ranged" else Formation.POST_GATE)
		h.set_process(false)
	GameState.refill()  # 모두 자리에 바로 선다(경로 없음), 몬스터 제거
	await _frames(1)
	var north_out := _half + Balance.WALL_T  # 북쪽 성벽 바깥면까지

	# (k) aoe_blast: 이그니스(북 성벽 위 x=-4)의 첫 폭발이 반경 안 보스 셋을 모두 깎는다(보통 공격은 하나만 친다)
	var ig = _add_hero("ignis", 100)
	var c := Vector3(-6, 0, -(north_out + 4.0))
	var bosses := []
	for off in [Vector3.ZERO, Vector3(1.5, 0, 0), Vector3(-1.0, 0, 1.0)]:
		var m = _spawn("epic_boss", 0, c + off)
		m.set_process(false)  # 제자리
		bosses.append(m)
	await _wait_until(func(): return ig._blast_cd > 0.0, 3.0)
	var hurt := 0
	for m in bosses:
		if m.hp < m.hp_max:
			hurt += 1
	_check(ig._blast_cd > 0.0 and hurt == 3, "(k) aoe_blast damages every monster in its radius", "blasted=%s hurt=%d" % [ig._blast_cd > 0.0, hurt])
	_remove_hero(ig)
	_clear_monsters()
	await _frames(1)

	# (l) heal_aura: 루미나(북 성벽 위)가 4초 쿨마다 반경 8 m 안 다친 한스(북 성문 앞, 약 4.7 m)를 최대 HP의 6% 회복
	var lu = _add_hero("lumina", 100)
	var hans = heroes[0]
	hans.take_damage(200.0)
	var hp0: float = hans.hp
	await _wait_until(func(): return hans.hp > hp0, 5.0)
	_check(is_equal_approx(hans.hp - hp0, hans.hp_max * 0.06), "(l) heal_aura heals a nearby ally by c% of its max HP", "hp %.1f -> %.1f" % [hp0, hans.hp])
	_remove_hero(lu)
	GameState.refill()
	await _frames(1)

	# (m) stun: 기절한 몬스터는 걷지 않다가 풀리면 다시 걷는다. 펠릭스(남 성문 앞)는 4번째 공격마다 대상을 기절시킨다
	_g = _spawn("grunt", 1, Vector3(_half + Balance.WALL_T + 15.0, 0, 3.0))  # 동쪽 밖, 영웅들 멀리
	await _frames(2)
	_g.apply_stun(1.0)
	var p0: Vector3 = _g.global_position
	await _seconds(0.8)
	var still := Formation.flat_distance(p0, _g.global_position)
	await _seconds(0.5)
	var after := Formation.flat_distance(p0, _g.global_position)
	_check(still < 0.01 and after > 0.3, "(m) a stunned monster stops, then walks again", "moved %.2f while stunned, %.2f after" % [still, after])
	_clear_monsters()
	await _frames(1)
	var fe = _add_hero("felix", 102)
	_g = _spawn("epic_boss", 2, fe.global_position + Vector3(0, 0, 1.5))
	await _wait_until(func(): return fe._attacks >= 4, 6.0)
	_check(fe._attacks >= 4 and _alive(_g) and _g.is_stunned(), "(m) felix's 4th attack stuns its target", "attacks=%d stunned=%s" % [fe._attacks, _alive(_g) and _g.is_stunned()])
	_remove_hero(fe)
	_clear_monsters()
	await _frames(1)

	# (n) gate_repair: 발두르(서 성문 앞)가 쿨마다 서쪽 성문을 최대치의 3% 회복
	var ba = _add_hero("baldur", 103)
	GameState.damage_gate(3, 100.0)
	var g0: float = GameState.gate_hp[3]
	ba._repair_cd = 0.1  # 첫 쿨(8초)을 기다리지 않는다
	await _wait_until(func(): return GameState.gate_hp[3] > g0, 1.0)
	_check(is_equal_approx(GameState.gate_hp[3] - g0, GameState.gate_hp_max * 0.03), "(n) gate_repair restores b% of the gate", "gate %.1f -> %.1f" % [g0, GameState.gate_hp[3]])
	_remove_hero(ba)
	GameState.refill()
	await _frames(1)

	# (o) slow: 세라핀(북 성벽 위)에게 맞은 grunt는 30% 느리게 걷는다
	var se = _add_hero("seraphine", 100)
	_g = _spawn("grunt", 0, Vector3(-6, 0, -(north_out + 4.0)))
	await _wait_until(func(): return _alive(_g) and _g._slow_t > 0.0, 3.0)
	var base_speed: float = _g._stats.speed
	# process_frame은 각 _process 전에 온다: 이 프레임의 delta(이 뒤에 움직일 몫)부터 센다 — 프레임 간격이 들쭉날쭉해도 맞게
	var q0: Vector3 = _g.global_position
	var t := get_process_delta_time()
	var spent := 0.0
	var moved := 0.0
	while spent < 0.4 and _alive(_g):
		await get_tree().process_frame
		moved = Formation.flat_distance(q0, _g.global_position) if _alive(_g) else moved
		spent = t
		t += get_process_delta_time()
	var v := moved / spent
	_check(v > base_speed * 0.65 and v < base_speed * 0.75, "(o) a slowed monster walks at (1 - a%) speed", "speed %.2f (base %.2f)" % [v, base_speed])
	_remove_hero(se)
	_clear_monsters()


func _add_hero(id: String, idx: int):
	var h = HeroScript.new()
	h.setup(idx, GameData.hero(id), _main.castle, get_tree().get_first_node_in_group("heroes").formation)
	_main.add_child(h)
	return h


func _remove_hero(h) -> void:
	h.formation.release(h.index)
	h.queue_free()


func _alive(m) -> bool:
	return is_instance_valid(m) and m.is_alive()


func _spawn(kind: String, side: int, pos: Vector3):
	var m = MonsterScript.new()
	m.setup(kind, side, 1, _main.castle)
	_main.add_child(m)
	m.global_position = pos
	return m


func _clear_monsters() -> void:
	for m in get_tree().get_nodes_in_group("monsters"):
		m.queue_free()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


## cond가 참이 될 때까지(최대 timeout초) 기다린다.
func _wait_until(cond: Callable, timeout: float) -> void:
	var t := 0.0
	while not cond.call() and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()


func _check(ok: bool, what: String, detail: String) -> void:
	if ok:
		print("AI PASS: " + what)
	else:
		_fails += 1
		print("AI FAIL: %s (%s)" % [what, detail])

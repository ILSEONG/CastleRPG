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
const Fx := preload("res://scripts/fx.gd")
const HpBarsScript := preload("res://scripts/hp_bars.gd")
const DamageNumbersScript := preload("res://scripts/damage_numbers.gd")

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
	var gold0: int = Economy.gold_tenths
	spawner._spawn({"kind": "grunt", "side": 0, "time": 0.0})
	var kid: Node = _main.get_child(_main.get_child_count() - 1)
	kid.take_damage(1.0e6)
	_check(Economy.gold_tenths == gold0 + GameData.kill_gold_tenths("grunt", GameState.stage) and GameData.kill_gold_tenths("grunt", 1) == 20, "(j) killing a grunt gives GameData.kill_gold_tenths (stage 1 = 20 tenths)", "gold %d -> %d" % [gold0, Economy.gold_tenths])
	spawner._spawn({"kind": "grunt", "side": 0, "time": 0.0})
	GameState.refill()
	await _frames(1)
	_check(Economy.gold_tenths == gold0 + GameData.kill_gold_tenths("grunt", GameState.stage), "(j) a monster removed by refill gives no gold", "gold %d" % Economy.gold_tenths)

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
	# 폭발 피해 = 공격력 × 오라 × c%(이그니스 44 × 220% = 96.8). 표적은 같은 프레임 보통 공격도 맞는다 — 나머지 둘이 정확히 폭발 몫
	var blast_d: float = ig.atk * ig._aura_mult() * ig._sk.aoe_blast[2] / 100.0
	var exact := bosses.filter(func(m): return is_equal_approx(m.hp_max - m.hp, blast_d)).size()
	_check(is_equal_approx(blast_d, 96.8) and exact >= 2 and bosses.all(func(m): return m.hp_max - m.hp >= blast_d - 0.01),
		"(k) the blast deals atk x c%% to each monster (%.1f)" % blast_d, "damage=%s" % [bosses.map(func(m): return m.hp_max - m.hp)])
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
	# 자리를 떠나 추격 중(성문 앞에서 3 m)이면 수리하지 않고, 자리로 돌아오면 다시 한다(스펙: 성문 앞에 있을 때만)
	ba.set_process(false)
	ba.global_position = ba.stand_position() + Formation.SIDE_DIR[3] * 3.0
	var g1: float = GameState.gate_hp[3]
	ba._gate_repair()
	_check(not ba.holds_post() and GameState.gate_hp[3] == g1, "(n) a gate hero chasing 3 m off its post does not repair", "gate %.1f -> %.1f" % [g1, GameState.gate_hp[3]])
	ba.global_position = ba.stand_position()
	ba._gate_repair()
	_check(ba.holds_post() and GameState.gate_hp[3] > g1, "(n) back on its post it repairs again", "gate %.1f -> %.1f" % [g1, GameState.gate_hp[3]])
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
	await _frames(1)

	# (p) 22종 전부: 네 명씩(면마다 하나) 보스·grunt와 3초 싸운다 — 모두 한 번 이상 공격하고 스크립트 오류가 없다(오류는 로거가 센다)
	var ids: Array = GameData.heroes().map(func(h): return h.id)
	var idle := []
	for b in range(0, ids.size(), 4):
		var batch := []
		for i in range(b, mini(b + 4, ids.size())):
			var h = _add_hero(ids[i], 200 + i - b)
			batch.append(h)
			var out: Vector3 = Formation.SIDE_DIR[h.side] * 3.0
			_spawn("epic_boss", h.side, Vector3(h.global_position.x, 0, h.global_position.z) + out)
			_spawn("grunt", h.side, Vector3(h.global_position.x, 0, h.global_position.z) + out + Formation.perp(h.side) * 1.5)
		await _seconds(3.0)
		for h in batch:
			if h._attacks == 0:
				idle.append(h.def.id)
			_remove_hero(h)
		_clear_monsters()
		await _frames(1)
	_check(idle.is_empty(), "(p) all 22 heroes fight (attack at least once in 3 s)", "never attacked: %s" % [idle])
	await _skill_application(heroes)
	await _placement_cases()
	await _fx_cap()
	await _damage_numbers()
	await _levelup_case()


## hero.gd가 스킬을 실제로 적용하는 방식(스펙 §3.2). 시험 영웅·몬스터는 처리를 끄고(제자리) 공격 함수를 직접 부른다.
func _skill_application(heroes: Array) -> void:
	_clear_monsters()
	GameState.refill()
	await _frames(1)

	# (q) atk_aura: 반경 안 "다른" 영웅에게만, 여럿이면 가장 큰 것 하나. 공격에 실제로 곱해진다(multishot과 같이 본다)
	var lu = _add_hero("lumina", 300)
	var gk = _add_hero("gork", 301)
	for h in [lu, gk]:
		h.set_process(false)
	lu.global_position = gk.global_position + Vector3(0, 0, 3.0)  # 같은 동쪽 성벽 위 3 m(오라 반경 8 m)
	_check(is_equal_approx(gk._aura_mult(), 1.15) and lu._aura_mult() == 1.0, "(q) atk_aura +b% applies to other heroes in range, not to its owner",
		"gork %.2f lumina %.2f" % [gk._aura_mult(), lu._aura_mult()])
	var strong: Dictionary = GameData.hero("lumina").duplicate(true)
	strong.id = "aura_test"
	strong.skills = {"atk_aura": [8.0, 30.0, 0.0]}
	var lu2 = _add_hero_def(strong, 304)
	lu2.set_process(false)
	lu2.global_position = gk.global_position + Vector3(0, 0, -3.0)
	_check(is_equal_approx(gk._aura_mult(), 1.30) and is_equal_approx(lu._aura_mult(), 1.30), "(q) with two auras in range only the largest counts (+30%, not +45%)",
		"gork %.2f lumina %.2f" % [gk._aura_mult(), lu._aura_mult()])
	lu2.global_position = gk.global_position + Vector3(0, 0, -20.0)
	_check(is_equal_approx(gk._aura_mult(), 1.15), "(q) an aura hero out of its radius gives nothing", "gork %.2f" % gk._aura_mult())
	_remove_hero(lu2)

	# (r) multishot: 고르크(a=2)의 한 번 공격 = 표적 + 사거리 안 가장 가까운 하나. 각자 공격력 × 오라, 먼 몬스터·사거리 밖은 안 맞는다
	var gp := _flat(gk.global_position)
	var ms := []
	for off in [Vector3(2.5, 0, 0), Vector3(3.0, 0, 1.0), Vector3(4.5, 0, -1.0), Vector3(9.0, 0, 0)]:
		ms.append(_still("epic_boss", gp + off))
	await _frames(1)
	gk._target = ms[0]
	gk._attack()
	var a: float = gk.atk * 1.15
	_check(is_equal_approx(_dmg(ms[0]), a) and is_equal_approx(_dmg(ms[1]), a) and _dmg(ms[2]) == 0.0 and _dmg(ms[3]) == 0.0,
		"(r) multishot a=2 hits the target and the nearest other in range, each for atk x aura (%.1f)" % a, "damage=%s" % [ms.map(_dmg)])
	_remove_hero(lu)
	_remove_hero(gk)
	_clear_monsters()
	await _frames(1)

	# (s) chain: 세라핀(3번, 70%, 4 m). A→B→C. B에서 가장 가까운 A(이미 맞음)는 건너뛰고 C, C에서 4 m 안에 새 대상이 없으면(D는 5 m) 멈춘다
	var se = _add_hero("seraphine", 302)
	se.set_process(false)
	var sp := _flat(se.global_position)
	var side_x: Vector3 = Formation.perp(2)
	var ca = _still("epic_boss", sp + Formation.SIDE_DIR[2] * 3.0)
	var cb = _still("epic_boss", ca.global_position + side_x * 2.0)
	var cc = _still("epic_boss", cb.global_position + side_x * 2.5)
	var cdd = _still("epic_boss", cc.global_position + side_x * 5.0)
	await _frames(1)
	se._target = ca
	se._attack()
	var d0: float = se.atk * se._aura_mult()
	_check(is_equal_approx(_dmg(ca), d0) and is_equal_approx(_dmg(cb), d0 * 0.7) and is_equal_approx(_dmg(cc), d0 * 0.49) and _dmg(cdd) == 0.0,
		"(s) chain bounces to the nearest monster not yet hit (x b% each) and stops when none is within c m",
		"damage=%s" % [[_dmg(ca), _dmg(cb), _dmg(cc), _dmg(cdd)]])
	_remove_hero(se)
	_clear_monsters()
	await _frames(1)

	# (t) cleave: 도릭(1.5 m, 50%)이 친 대상 주변 1.5 m 안 다른 몬스터에게 피해의 b%, 밖은 없음
	var dk = _add_hero("dorik", 303)
	dk.set_process(false)
	var t0 := _flat(dk.global_position) + Formation.SIDE_DIR[3] * 1.0
	var pz: Vector3 = Formation.perp(3)
	var tt = _still("epic_boss", t0)
	var n1 = _still("epic_boss", t0 + pz * 1.0)
	var n2 = _still("epic_boss", t0 - pz * 1.4)
	var far = _still("epic_boss", t0 + pz * 2.5)
	await _frames(1)
	dk._target = tt
	dk._attack()
	var dd: float = dk.atk * dk._aura_mult()
	_check(is_equal_approx(_dmg(tt), dd) and is_equal_approx(_dmg(n1), dd * 0.5) and is_equal_approx(_dmg(n2), dd * 0.5) and _dmg(far) == 0.0,
		"(t) cleave deals b% of the hit to other monsters within a m of the target only", "damage=%s" % [[_dmg(tt), _dmg(n1), _dmg(n2), _dmg(far)]])
	_remove_hero(dk)
	_clear_monsters()
	await _frames(1)

	# (u) 폭발이 표적을 죽이면 같은 프레임에 그 시체를 치지 않는다(공격 횟수·쿨 그대로)
	var ig = _add_hero("ignis", 300)
	ig.set_process(false)
	var weak = _still("grunt", _flat(ig.global_position) + Formation.SIDE_DIR[0] * 3.0)
	await _frames(1)
	ig._target = weak
	ig._scan_cd = 1.0
	ig._blast_cd = 0.0
	ig._atk_cd = 0.0
	ig._process(0.016)
	_check(not weak.is_alive() and ig._attacks == 0 and ig._atk_cd <= 0.0 and ig._target == null, "(u) a target killed by the blast is not struck again (no attack, no cooldown)",
		"alive=%s attacks=%d cd=%.2f" % [weak.is_alive(), ig._attacks, ig._atk_cd])
	_remove_hero(ig)
	_clear_monsters()
	await _frames(1)

	# (v) stun은 공격도 멈춘다: 한스 바로 앞 보스(처리 켬)가 기절한 동안 한스를 치지 않고, 풀리면 친다
	var hans = heroes[0]
	var boss = _spawn("epic_boss", 0, _flat(hans.global_position) + Formation.SIDE_DIR[0] * 1.2)
	boss.apply_stun(1.0)
	_g = boss
	await _seconds(0.8)
	var hp_stunned: float = hans.hp
	await _wait_until(func(): return hans.hp < hans.hp_max, 2.0)
	_check(hp_stunned == hans.hp_max and hans.hp < hans.hp_max, "(v) a stunned monster next to a hero does not attack it, and attacks once the stun ends",
		"hp while stunned %.0f, after %.0f / %.0f" % [hp_stunned, hans.hp, hans.hp_max])
	_clear_monsters()
	await _frames(1)

	# (w) poison 마지막 틱은 남은 시간만큼: 10/초 × 0.05초에 0.1초 프레임이면 0.5(1.0 아님), 끝난 뒤엔 없음
	var pm = _still("epic_boss", Vector3(0, 0, -(_half + Balance.WALL_T + 20.0)))
	await _frames(1)
	pm.apply_poison(10.0, 0.05)
	pm._process(0.1)
	var p1: float = _dmg(pm)
	pm._process(0.1)
	_check(is_equal_approx(p1, 0.5) and is_equal_approx(_dmg(pm), 0.5), "(w) the last poison tick only deals the time left (dps x seconds in total)", "after 1 tick %.2f, after 2 %.2f" % [p1, _dmg(pm)])
	_clear_monsters()
	await _frames(1)

	# (x) retire: 그룹에서 빠지고 refilled를 끊는다 — 같은 프레임의 리필이 되살리지 않는다
	var rh = _add_hero("jack", 305)
	await _frames(1)
	rh.retire()
	GameState.refill()
	_check(not rh.is_alive() and not rh.is_in_group("heroes") and not GameState.refilled.is_connected(rh.reset),
		"(x) a retired hero leaves the group and is not revived by a refill in the same frame", "alive=%s group=%s" % [rh.is_alive(), rh.is_in_group("heroes")])
	await _frames(1)


## (y) 기본 자리(면 index % 4의 역할 자리)가 차 있으면 같은 면 다른 자리 → 다른 면 → 다 차면 그 면 성문 앞 바닥.
##     게임 중 다시 만든 영웅이 assert로 죽지 않는다(오류 로거가 센다).
func _placement_cases() -> void:
	var f = Formation.new()
	var hans_def: Dictionary = GameData.hero("hans")
	for i in Formation.capacity(Formation.POST_GATE):
		f.claim(900 + i, 0, Formation.POST_GATE)
	var a = HeroScript.new()
	a.setup(0, hans_def, _main.castle, f)
	for i in Formation.capacity(Formation.POST_WALL):
		f.claim(910 + i, 0, Formation.POST_WALL)  # 한 칸은 a가 쥐고 있다(마지막 claim은 -1)
	var b = HeroScript.new()
	b.setup(4, hans_def, _main.castle, f)
	for s in 4:
		for p in [Formation.POST_GATE, Formation.POST_WALL]:
			for i in Formation.capacity(p):
				f.claim(1000 + s * 100 + p * 10 + i, s, p)
	var c = HeroScript.new()
	c.setup(8, hans_def, _main.castle, f)
	var free_at: Vector3 = Formation.slot_position(_half, 0, Formation.POST_GATE, 0)
	_check(a.side == 0 and a.post == Formation.POST_WALL and f.assignment(0).get("post", -1) == Formation.POST_WALL,
		"(y) default gate post full -> the wall on the same side", "side=%d post=%d" % [a.side, a.post])
	_check(b.side == 1 and b.post == Formation.POST_GATE and f.assignment(4).get("side", -1) == 1,
		"(y) both posts of its side full -> the next side's role post", "side=%d post=%d" % [b.side, b.post])
	_check(c.post == Formation.POST_FREE and c.side == 0 and c.free_pos.distance_to(free_at) < 0.01 and f.assignment(8).is_empty(),
		"(y) every post full -> free spot in front of its own gate", "side=%d post=%d free=%s" % [c.side, c.post, c.free_pos])
	for h in [a, b, c]:
		h.free()

	# 실제 경로: 한스가 자리를 비우고 나머지 셋이 북문 앞(3칸)을 채운 뒤, 방치 모드 배치 변경으로 슬롯 0을 다시 만든다
	GameState.refill()
	await _frames(1)
	var hs := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.is_alive())
	hs.sort_custom(func(x, y): return x.index < y.index)
	hs[0].move_to_point(Vector3(0, 0, -(_half + Balance.WALL_T + 12.0)))
	var moved := true
	for i in [1, 2, 3]:
		moved = hs[i].move_to(0, Formation.POST_GATE) and moved
	_check(moved and GameState.mode == GameState.Mode.IDLE, "(y) precondition: the other three heroes hold the north gate's three slots (idle mode)", "moved=%s" % moved)
	var errors0 := _errors.count
	Economy.heroes["jack"] = 1
	var d: Array = GameState.deploy()
	d[0] = "jack"
	Economy.set_deploy(d)
	await _frames(1)
	var now0 := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.is_alive() and h.index == 0)
	_check(now0.size() == 1 and now0[0].def.id == "jack" and now0[0].side == 0 and now0[0].post == Formation.POST_WALL and _errors.count == errors0,
		"(y) a slot rebuilt mid-game while its gate is full stands on its side's wall (no assert)",
		"heroes=%s errors=%d" % [now0.map(func(h): return [h.def.id, h.side, h.post]), _errors.count - errors0])


## (z) 이펙트 상한: 살아 있는 수를 세어 MAX_LIVE까지만 만들고(넘치면 건너뜀), 사라지면 수가 0으로 돌아온다.
##     HP 바: 살아 있는 유닛마다 8각형 2개(배경·채움)를 한 배열로.
func _fx_cap() -> void:
	await _wait_until(func(): return Fx.live() == 0, 3.0)
	var live0 := Fx.live()
	for i in Fx.MAX_LIVE + 10:
		Fx.heal_ring(_main, Vector3(0, 0, -5.0), 2.0)
	var made := get_tree().get_nodes_in_group(Fx.GROUP).size()
	_check(live0 == 0 and Fx.live() == Fx.MAX_LIVE and made == Fx.MAX_LIVE and Fx.full(_main), "(z) effects stop at MAX_LIVE (counted, extra ones skipped)",
		"before=%d live=%d nodes=%d" % [live0, Fx.live(), made])
	await _wait_until(func(): return Fx.live() == 0, 3.0)
	_check(Fx.live() == 0 and get_tree().get_nodes_in_group(Fx.GROUP).is_empty() and not Fx.full(_main), "(z) the count drops back to 0 as effects free themselves", "live=%d" % Fx.live())
	var bars
	for c in _main.get_children():
		if c.get_script() == HpBarsScript:
			bars = c
	await _frames(2)
	var units := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.is_alive()).size()
	_check(bars.octagons > 0 and bars.octagons <= units * 2 and bars._idx.size() == bars.octagons * 18 and bars._pts.size() == bars.octagons * 8,
		"(z) HP bars: one triangle array, two octagons per unit on screen", "octagons=%d units=%d" % [bars.octagons, units])


## 피해 숫자: 공격하면 종류별 숫자가 생기고(치명타 100% 영웅 = 치명타), 받은 피해·회피·회복도 나온다. 120마리여도 그리기 호출 ≤ 숫자 × 2.
func _damage_numbers() -> void:
	_clear_monsters()
	GameState.refill()
	await _frames(1)
	var dn = DamageNumbersScript.current
	_check(dn != null, "(dn) the damage numbers node is in the world", "current=%s" % dn)
	var K = DamageNumbersScript.Kind
	var plain: Dictionary = GameData.hero("lumina").duplicate(true)
	plain.skills = {}
	var crit_def := plain.duplicate(true)
	crit_def.skills = {"crit": [100.0, 200.0, 0.0]}
	var dodge_def := plain.duplicate(true)
	dodge_def.skills = {"dodge": [100.0]}
	var h = _add_hero_def(plain, 310)
	var hc = _add_hero_def(crit_def, 311)
	var hd = _add_hero_def(dodge_def, 312)
	for x in [h, hc, hd]:
		x.set_process(false)
	var m = _still("grunt", Vector3(0, 0, -(_half + 6.0)))
	dn._list.clear()
	h._target = m
	h._attack()
	var kinds: Array = dn._list.map(func(e): return e.kind)
	_check(kinds == [K.HIT] and dn._list[0].text == str(roundi(h.atk)), "(dn) a plain attack makes one white damage number", "kinds=%s text=%s atk=%s" % [kinds, dn._list[0].text if not dn._list.is_empty() else "-", h.atk])
	dn._list.clear()
	hc._target = m
	hc._attack()
	kinds = dn._list.map(func(e): return e.kind)
	_check(kinds == [K.CRIT] and dn._list[0].text == "%d!" % roundi(hc.atk * 2.0) and DamageNumbersScript.STYLE[K.CRIT][0] == Color(1.0, 0.62, 0.15),
		"(dn) a 100% crit hero makes an orange crit number with '!'", "kinds=%s text=%s" % [kinds, dn._list[0].text if not dn._list.is_empty() else "-"])
	dn._list.clear()
	h.take_damage(10.0, m)
	hd.take_damage(10.0, m)
	h.hp = h.hp_max - 5.0
	h.heal(3.0)
	h.heal(0.0)
	kinds = dn._list.map(func(e): return e.kind)
	_check(kinds == [K.HURT, K.DODGE, K.HEAL] and dn._list.map(func(e): return e.text) == ["10", "회피", "+3"], "(dn) hurt, dodge and heal numbers (a zero heal shows nothing)", "kinds=%s" % [kinds])
	_clear_monsters()
	await _frames(1)
	var crowd := []
	for i in 120:
		crowd.append(_still("grunt", Vector3(-6.0 + (i % 12) * 1.0, 0, -(_half + 6.0) - (i / 12) * 1.0)))
	dn._list.clear()
	for c in crowd:
		c.take_damage(5.0, K.HIT)
	await _frames(2)
	_check(dn._list.size() == 80 and dn.draws <= dn._list.size() * 2 and dn.draws > 0,
		"(dn) 120 hit monsters: pool stays at the cap and draw calls <= numbers x 2", "list=%d draws=%d" % [dn._list.size(), dn.draws])
	for x in [h, hc, hd]:
		_remove_hero(x)
	_clear_monsters()
	await _frames(1)


func _add_hero(id: String, idx: int):
	return _add_hero_def(GameData.hero(id), idx)


func _add_hero_def(def: Dictionary, idx: int):
	var h = HeroScript.new()
	h.setup(idx, def, _main.castle, get_tree().get_first_node_in_group("heroes").formation)
	_main.add_child(h)
	return h


## 처리를 끈(제자리) 몬스터.
func _still(kind: String, pos: Vector3):
	var m = _spawn(kind, Formation.side_of(pos), pos)
	m.set_process(false)
	return m


func _dmg(m) -> float:
	return m.hp_max - m.hp


func _flat(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)


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


## (L) 개정 11 레벨업: 방치 모드에서 오프라인 레벨업(Economy.level_up)하면 그 슬롯 영웅만 다시 만들어지고 HP·공격이
##     기본 × (1 + 0.06 × (L − 1)) × 별 배율이다. 실제 타격 피해도 그 공격력이다(오라 없는 혼자 공격).
func _levelup_case() -> void:
	GameState.refill()
	await _frames(1)
	var slot := GameState.deploy().find("dorik")
	if slot < 0:  # 앞 사례가 배치를 바꿨으면 슬롯 2에 도릭을 둔다
		var d := GameState.deploy()
		d[2] = "dorik"
		Economy.set_deploy(d)
		slot = 2
	await _frames(1)
	Economy.heroes["dorik"] = 3  # 별 2
	Economy.gold_tenths = 1000000
	Economy.res["food"] = 100000
	var before := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.is_alive())
	var ok := Economy.level_up("dorik", 9)  # 1 → 10
	await _frames(1)
	var live := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.is_alive())
	var dorik = live.filter(func(h): return h.index == slot)[0]
	var mult := (1.0 + 0.06 * 9) * 1.2
	var others_kept := live.filter(func(h): return h.index != slot).all(func(h): return before.has(h))
	_check(ok and Economy.level_of("dorik") == 10 and dorik.def.id == "dorik" and not before.has(dorik) and others_kept
		and is_equal_approx(dorik.hp_max, 440.0 * mult) and is_equal_approx(dorik.atk, 30.0 * mult) and is_equal_approx(dorik.hp, dorik.hp_max),
		"(L) a level-up in idle mode rebuilds only that hero with HP/atk = base x (1 + 0.06 x 9) x 1.2",
		"ok=%s hp=%.2f atk=%.2f kept=%s" % [ok, dorik.hp_max, dorik.atk, others_kept])
	for h in live:
		h.set_process(h == dorik)
	var m = _still("epic_boss", dorik.global_position + Formation.SIDE_DIR[dorik.side] * 1.2)
	dorik._sk = {}  # 순수 타격(치명타·처형·연쇄 없음)으로 공격력만 본다
	await _wait_until(func(): return _dmg(m) > 0.0, 3.0)
	_check(is_equal_approx(_dmg(m), dorik.atk), "(L) the leveled hero hits for its leveled attack", "dmg=%.2f atk=%.2f" % [_dmg(m), dorik.atk])
	_clear_monsters()
	await _frames(1)

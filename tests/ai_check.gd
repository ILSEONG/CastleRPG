extends Node
## 헤드리스 AI 체크: 실제 main 씬(오토로드 포함)에서 영웅·몬스터 인식·추격·복귀·영역 규칙을 확인한다.
## 실행: ./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/ai_check.tscn
## 오토로드를 쓰므로 tests/run_tests.gd(-s)에서 preload 금지. 스포너를 멈추고 몬스터를 직접 놓는다.

const Balance := preload("res://scripts/balance.gd")
const Formation := preload("res://scripts/formation.gd")
const MonsterScript := preload("res://scripts/monster.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")

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
	var warrior = heroes[0]  # 기본 배치: 북(0) 성문 앞
	var archer = heroes[1]   # 동(1) 성벽 위
	var warrior_hp: float = Balance.HERO_ROLES.warrior.hp

	# (a) 밖 자유 위치 전사와 5 m 떨어진 grunt가 서로 다가가 교전한다
	var post := Vector3(30, 0, -40)
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
	var reach: float = Balance.HERO_ROLES.archer.range + 1.0
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
	var hpost := Vector3(15, 0, -20)
	warrior.move_to_point(hpost)
	GameState.refill()  # 성문 복구·몬스터 제거, 영웅은 자리(방금 정한 자유 위치)로 옮겨진다
	await _frames(1)
	_g = _spawn("grunt", 1, Vector3(18.1, 0, -16.5))
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

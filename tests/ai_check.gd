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
const SoldierScript := preload("res://scripts/soldier.gd")
const Fx := preload("res://scripts/fx.gd")
const HpBarsScript := preload("res://scripts/hp_bars.gd")
const DamageNumbersScript := preload("res://scripts/damage_numbers.gd")
const ProjectileScript := preload("res://scripts/projectile.gd")
const Art := preload("res://scripts/art.gd")
const MainScript := preload("res://scripts/main.gd")
const HudScript := preload("res://scripts/hud.gd")
const SOLDIER_TIME_SCALE := 4.0  # (S) 병사 사례 동안 게임 시간 배속(걷는 구간이 길다)
const ArenaKit := preload("res://scripts/arena_kit.gd")

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
	Fever.save_path = ""
	Fever.reset()
	GameData._config.fx_shake = "0"  # 테스트에서는 카메라 흔들림을 끈다(개정 17)
	Economy.reset(Time.get_unix_time_from_system())
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(5)
	for c in _main.get_children():
		if c.get_script() == SpawnerScript:
			c.set_process(false)
	_clear_monsters()
	GameState.mode = GameState.Mode.STAGE  # 피해가 들어가는 모드로 시작(방치 모드는 무적 — 개정 12). 방치 사례만 IDLE로 바꾼다
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
	_check(Economy.gold_tenths == gold0 + GameData.kill_gold_tenths("grunt", GameState.stage) and GameData.kill_gold_tenths("grunt", 1) == 100, "(j) killing a grunt gives GameData.kill_gold_tenths (stage 1 = 100 tenths)", "gold %d -> %d" % [gold0, Economy.gold_tenths])
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

	# (k) aoe_blast: 이그니스(북 성벽 위 x=-4)의 첫 폭발이 반경 안 보스 셋을 모두 깎는다(보통 공격은 하나만 친다). 발동 모션(개정 25)의 발동 순간에 터진다
	var ig = _add_hero("ignis", 100)
	var c := Vector3(-6, 0, -(north_out + 4.0))
	var bosses := []
	for off in [Vector3.ZERO, Vector3(1.5, 0, 0), Vector3(-1.0, 0, 1.0)]:
		var m = _spawn("epic_boss", 0, c + off)
		m.set_process(false)  # 제자리
		bosses.append(m)
	await _wait_until(func(): return ig._blast_cd > 0.0 and not ig.is_casting(), 3.0)
	var hurt := 0
	for m in bosses:
		if m.hp < m.hp_max:
			hurt += 1
	_check(ig._blast_cd > 0.0 and hurt == 3, "(k) aoe_blast damages every monster in its radius", "blasted=%s hurt=%d" % [ig._blast_cd > 0.0, hurt])
	# 폭발 피해 = 공격력 × 오라 × c%(이그니스 44 × 220% = 96.8). 표적은 보통 공격도 맞을 수 있다 — 나머지 둘이 정확히 폭발 몫
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
	await _wait_until(func(): return _alive(_g) and _g.is_stunned(), 6.0)  # 기절은 4번째 공격의 타격 순간에(개정 12-2)
	_check(fe._attacks == 4 and _alive(_g) and _g.is_stunned(), "(m) felix's 4th attack stuns its target", "attacks=%d stunned=%s" % [fe._attacks, _alive(_g) and _g.is_stunned()])
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

	# (o) slow: 세라핀(북 성벽 위, ★3 — slow는 스킬 2)에게 맞은 grunt는 30% 느리게 걷는다
	var se = _add_hero("seraphine", 100, 3)
	se.atk = GameData.hero_stats(se.def, 1, 0).atk  # ★3 공격 배율이면 grunt가 한 방에 죽는다 — 공격은 ★0 그대로
	_g = _spawn("grunt", 0, Vector3(-6, 0, -(north_out + 4.0)))
	_g.hp = 60.0  # 표 HP 24는 공격 44 한 방에 죽는다 — 예전 HP로 한 방은 버티게
	_g.hp_max = 60.0
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
	GameState.mode = GameState.Mode.STAGE
	await _fx_cap()
	await _damage_numbers()
	GameState.mode = GameState.Mode.IDLE
	await _levelup_case()
	await _idle_invincible_case()
	await _attack_sync()
	await _soldier_cases()
	await _fever_spawn()
	await _skill_unlock_cases()
	await _hold_ground_case()
	await _group_spawn()
	await _round_cases()
	await _stage_return_cases()
	await _rebuilt_post_case()
	await _growth_cases()
	await _research_cases()
	await _boss_slayer_case()
	await _dungeon_cases()
	await _crowd_cases()
	await _building_cases()  # 월드를 다시 만든다 — 마지막


## hero.gd가 스킬을 실제로 적용하는 방식(스펙 §3.2). 시험 영웅·몬스터는 처리를 끄고(제자리) 공격 함수를 직접 부른다.
func _skill_application(heroes: Array) -> void:
	_clear_monsters()
	GameState.refill()
	await _frames(1)

	# (q) atk_aura: 반경 안 "다른" 영웅에게만, 여럿이면 가장 큰 것 하나. 공격에 실제로 곱해진다(multishot과 같이 본다).
	#     루미나의 오라는 스킬 2 → ★3. 고르크는 ★0(스킬 2 boss_slayer 잠김 — 보스에게도 배율 없음)
	var lu = _add_hero("lumina", 300, 3)
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

	# (r) multishot: 고르크(multishot a=2만 쥐게 한다 — 표의 고르크는 도탄)의 한 번 공격 = 표적 + 사거리 안 가장 가까운 하나.
	# 각자 공격력 × 오라, 먼 몬스터·사거리 밖은 안 맞는다
	gk._sk = {"multishot": [2.0, 0.0, 0.0]}
	gk._skx.set_skills(gk._sk)
	var gp := _flat(gk.global_position)
	var ms := []
	for off in [Vector3(2.5, 0, 0), Vector3(3.0, 0, 1.0), Vector3(4.5, 0, -1.0), Vector3(9.0, 0, 0)]:
		ms.append(_still("epic_boss", gp + off))
	await _frames(1)
	gk._target = ms[0]
	await _attack_now(gk)
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
	await _attack_now(se)
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
	await _attack_now(dk)
	var dd: float = dk.atk * dk._aura_mult()
	_check(is_equal_approx(_dmg(tt), dd) and is_equal_approx(_dmg(n1), dd * 0.5) and is_equal_approx(_dmg(n2), dd * 0.5) and _dmg(far) == 0.0,
		"(t) cleave deals b% of the hit to other monsters within a m of the target only", "damage=%s" % [[_dmg(tt), _dmg(n1), _dmg(n2), _dmg(far)]])
	_remove_hero(dk)
	_clear_monsters()
	await _frames(1)

	# (u) 폭발이 표적을 죽이면 그 시체를 치지 않는다(공격 횟수·쿨 그대로). 폭발은 발동 모션을 시작하고(평타 대신) 모션의 발동 순간에 터진다
	var ig = _add_hero("ignis", 300)
	ig.set_process(false)
	var weak = _still("grunt", _flat(ig.global_position) + Formation.SIDE_DIR[0] * 3.0)
	await _frames(1)
	ig._target = weak
	ig._scan_cd = 1.0
	ig._blast_cd = 0.0
	ig._atk_cd = 0.0
	ig._process(0.016)
	var cast_started: bool = ig.is_casting()
	for i in 30:
		if not ig.is_casting():
			break
		ig._process(0.05)
	_check(cast_started and not weak.is_alive() and ig._attacks == 0 and ig._atk_cd <= 0.0 and ig._target == null, "(u) a target killed by the blast is not struck again (no attack, no cooldown)",
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

	GameState.mode = GameState.Mode.IDLE  # (y) 방치 모드 배치 변경
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
	m.hp_max = 1000.0  # 표 HP 24는 첫 방에 죽는다 — 두 번 맞아도 살아 있게
	m.hp = m.hp_max
	dn._list.clear()
	h._target = m
	await _attack_now(h)
	var kinds: Array = dn._list.map(func(e): return e.kind)
	_check(kinds == [K.HIT] and dn._list[0].text == str(roundi(h.atk)), "(dn) a plain attack makes one white damage number", "kinds=%s text=%s atk=%s" % [kinds, dn._list[0].text if not dn._list.is_empty() else "-", h.atk])
	dn._list.clear()
	hc._target = m
	await _attack_now(hc)
	kinds = dn._list.map(func(e): return e.kind)
	_check(kinds == [K.CRIT, K.BANNER] and dn._list[0].text == "%d!" % roundi(hc.atk * 2.0) and DamageNumbersScript.STYLE[K.CRIT][0] == Color(1.0, 0.62, 0.15)
		and dn._list[1].text == "치명타!",
		"(dn) a 100% crit hero makes an orange crit number with '!' and the 치명타! banner (r17)", "kinds=%s text=%s" % [kinds, dn._list[0].text if not dn._list.is_empty() else "-"])
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


func _add_hero(id: String, idx: int, promotion := 0):
	return _add_hero_def(GameData.hero(id), idx, promotion)


## promotion = 승급(개정 17: 스킬 2는 ★3, 3은 ★5에서 해금).
func _add_hero_def(def: Dictionary, idx: int, promotion := 0):
	var h = HeroScript.new()
	h.setup(idx, def, _main.castle, get_tree().get_first_node_in_group("heroes").formation, promotion)
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
##     기본 × (1 + 0.0315 × (L − 1), 근접 계수) × 승급 배율이다(개정 15). 실제 타격 피해도 그 공격력이다(오라 없는 혼자 공격).
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
	Economy.hero_promotions["dorik"] = 2  # 승급 2(개정 15): × 1.5²
	Economy.gold_tenths = 1000000
	var before := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.is_alive())
	var ok := Economy.level_up("dorik", 9)  # 1 → 10
	await _frames(1)
	var live := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.is_alive())
	var dorik = live.filter(func(h): return h.index == slot)[0]
	var mult := (1.0 + 0.0315 * 9) * 1.69  # 도릭은 근접(hero_level_stat_melee)
	var others_kept := live.filter(func(h): return h.index != slot).all(func(h): return before.has(h))
	_check(ok and Economy.level_of("dorik") == 10 and dorik.def.id == "dorik" and not before.has(dorik) and others_kept
		and is_equal_approx(dorik.hp_max, 396.0 * mult) and is_equal_approx(dorik.atk, 23.0 * mult) and is_equal_approx(dorik.hp, dorik.hp_max),
		"(L) a level-up in idle mode rebuilds only that hero with HP/atk = base x (1 + 0.0315 x 9, melee) x 1.3^2 (promotion 2)",
		"ok=%s hp=%.2f atk=%.2f kept=%s" % [ok, dorik.hp_max, dorik.atk, others_kept])
	for h in live:
		h.set_process(h == dorik)
	var m = _still("epic_boss", dorik.global_position + Formation.SIDE_DIR[dorik.side] * 1.2)
	dorik._sk = {}  # 순수 타격(치명타·처형·연쇄 없음)으로 공격력만 본다
	await _wait_until(func(): return _dmg(m) > 0.0, 3.0)
	_check(is_equal_approx(_dmg(m), dorik.atk), "(L) the leveled hero hits for its leveled attack", "dmg=%.2f atk=%.2f" % [_dmg(m), dorik.atk])
	_clear_monsters()
	await _frames(1)


## (B) 개정 12 건물(오프라인, 실제 완료 경로: 끝난 일꾼을 Economy._process가 완료 → building_done → main).
## 막사 Lv 5 → 영웅은 그대로(개정 13: 막사는 영웅 HP를 올리지 않는다), 연구소 Lv 3 → 영웅도 그대로(개정 24: 연구소 레벨 공격 보너스 없음)
## — 영웅이 그 공격으로 친다.
## 성문 Lv 2 → 성문 최대 HP 800. 성채가 단계(5)를 넘으면 "성이 넓어졌습니다!"와 함께 월드를 다시 만든다 — 새 main(성 내부 24타일, 슬롯 8,
## 성 HP 1800)이고 오토로드 상태(Economy 골드·자원·건물·영웅, GameState 스테이지)는 그대로. 월드가 바뀌므로 마지막 사례.
func _building_cases() -> void:
	_clear_monsters()
	GameState.refill()
	await _frames(1)
	_check(GameState.mode == GameState.Mode.IDLE and Economy.build.is_empty(), "(B) precondition: idle, builder free", "mode=%d build=%s" % [GameState.mode, Economy.build])
	var before := _alive_heroes()
	Economy.levels["barracks"] = 4
	Economy.build = {"id": "barracks", "finish": Economy.time_now() - 1.0}
	await _frames(2)
	var live := _alive_heroes()
	var hp_ok := not live.is_empty()
	for h in live:
		var base := GameData.hero_stats(h.def, Economy.level_of(h.def.id), Economy.promotion_of(h.def.id))
		hp_ok = hp_ok and before.has(h) and is_equal_approx(h.hp_max, base.hp) and is_equal_approx(h.atk, base.atk)
	_check(Economy.building_level("barracks") == 5 and Economy.build.is_empty() and hp_ok, "(B) barracks Lv 5 done in idle: heroes are not rebuilt and keep their HP (rev 13: no barracks HP bonus)",
		"barracks=%d heroes=%s" % [Economy.building_level("barracks"), live.map(func(h): return [h.def.id, h.hp_max, h.atk])])
	Economy.levels["lab"] = 2
	Economy.build = {"id": "lab", "finish": Economy.time_now() - 1.0}
	await _frames(2)
	live = _alive_heroes()
	var atk_ok := not live.is_empty()
	for h in live:
		var base := GameData.hero_stats(h.def, Economy.level_of(h.def.id), Economy.promotion_of(h.def.id))
		atk_ok = atk_ok and before.has(h) and is_equal_approx(h.hp_max, base.hp) and is_equal_approx(h.atk, base.atk)
	_check(Economy.building_level("lab") == 3 and atk_ok, "(B) lab Lv 3 done in idle: hero attack and HP unchanged, heroes not rebuilt (rev 24: the lab level gives no attack bonus)",
		"lab=%d heroes=%s" % [Economy.building_level("lab"), live.map(func(h): return [h.def.id, h.hp_max, h.atk])])
	var hero = live[0]
	for h in live:
		h.set_process(h == hero)
	var m = _still("epic_boss", hero.global_position + Formation.SIDE_DIR[hero.side] * 1.2)
	hero._sk = {}  # 순수 타격으로 공격력만 본다
	await _wait_until(func(): return _dmg(m) > 0.0, 3.0)
	_check(is_equal_approx(_dmg(m), hero.atk) and is_equal_approx(hero.atk, GameData.hero_stats(hero.def, Economy.level_of(hero.def.id), Economy.promotion_of(hero.def.id)).atk),
		"(B) a hero hits for its plain attack (no lab bonus)", "dmg=%.2f atk=%.2f" % [_dmg(m), hero.atk])
	_clear_monsters()
	await _frames(1)
	Economy.build = {"id": "gate", "finish": Economy.time_now() - 1.0}
	await _frames(2)
	_check(Economy.building_level("gate") == 2 and GameState.gate_hp_max == 800.0 and GameState.gate_hp[0] == 800.0, "(B) gate Lv 2 done: gate max HP 800 at once",
		"gate=%d max=%.0f hp=%.0f" % [Economy.building_level("gate"), GameState.gate_hp_max, GameState.gate_hp[0]])
	# 성채 4 → 5: 단계가 바뀌어 월드를 다시 만든다
	var old = _main
	var keep_before := [Economy.gold_tenths, Economy.res.duplicate(), Economy.heroes.duplicate(), Economy.hero_levels.duplicate(), Economy.hero_promotions.duplicate(), GameState.stage, GameState.deploy()]
	var rebuilds0: int = MainScript.rebuilds
	Economy.levels["keep"] = 4
	Economy.build = {"id": "keep", "finish": Economy.time_now() - 1.0}
	var old_id: int = old.get_instance_id()  # 람다가 노드를 캡처하면 해제 뒤 호출마다 엔진 오류 — id로 본다
	await _wait_until(func(): return not is_instance_id_valid(old_id), 3.0)
	await _frames(3)
	var fresh = null
	for c in get_children():
		if c.get_script() == MainScript:
			fresh = c
	_check(not is_instance_valid(old) and fresh != null and MainScript.rebuilds == rebuilds0 + 1, "(B) keep Lv 5 crosses a tier: the world is rebuilt (new main)",
		"old valid=%s fresh=%s rebuilds=%d" % [is_instance_valid(old), fresh, MainScript.rebuilds - rebuilds0])
	if fresh == null:
		return
	_main = fresh
	for c in fresh.get_children():
		if c.get_script() == SpawnerScript:
			c.set_process(false)
	var hud = fresh.get_children().filter(func(c): return c.get_script() == HudScript)[0]
	var deployed: int = GameState.deploy().filter(func(x): return x != null).size()
	_check(fresh.castle.half == 24.0 and GameState.hero_count() == 8 and GameState.deploy().size() == 8 and _alive_heroes().size() == deployed and GameState.castle_hp_max == 1800.0,
		"(B) the new world uses keep 5: interior 24 tiles, 8 slots, castle HP 1800", "half=%.1f slots=%d heroes=%d castle=%.0f" % [fresh.castle.half, GameState.hero_count(), _alive_heroes().size(), GameState.castle_hp_max])
	var keep_after := [Economy.gold_tenths, Economy.res, Economy.heroes, Economy.hero_levels, Economy.hero_promotions, GameState.stage, GameState.deploy().slice(0, 4)]
	_check(keep_after == keep_before and Economy.building_level("keep") == 5 and Economy.building_level("lab") == 3 and GameState.roster == Economy and not Net.is_online(),
		"(B) autoload state carries over the rebuild (gold, resources, heroes, levels, stage, deploy)", "before=%s after=%s" % [keep_before, keep_after])
	_check(hud._toast.visible and hud._toast.text == "성이 넓어졌습니다!", "(B) the new HUD shows '성이 넓어졌습니다!'", "toast=%s '%s'" % [hud._toast.visible, hud._toast.text])
	# 스테이지 중에 단계가 바뀌면(성채 9 → 10): 지금 알리고, 월드는 방치로 돌아올 때 다시 만든다
	hud._toast.visible = false
	GameState.start_stage()
	GameState.auto_continue = false  # 결과 뒤 방치로
	Economy.levels["keep"] = 9
	Economy.build = {"id": "keep", "finish": Economy.time_now() - 1.0}
	await _frames(3)
	_check(is_instance_valid(fresh) and fresh.is_inside_tree() and hud._toast.visible and hud._toast.text == "성이 넓어졌습니다!" and fresh.castle.half == 24.0,
		"(B) a tier change during a stage shows the notice now and keeps the world until idle", "valid=%s toast=%s" % [is_instance_valid(fresh), hud._toast.visible])
	var stage_id: int = fresh.get_instance_id()
	GameState.on_all_monsters_dead()
	await _wait_until(func(): return not is_instance_id_valid(stage_id), GameData.config_num("result_sec") + 3.0)
	await _frames(3)
	var after = get_children().filter(func(c): return c.get_script() == MainScript)
	_check(not is_instance_id_valid(stage_id) and after.size() == 1 and after[0].castle.half == 28.0 and GameState.mode == GameState.Mode.IDLE and GameState.hero_count() == 12,
		"(B) back in idle the world is rebuilt for keep 10 (interior 28 tiles, 12 slots)", "old valid=%s mains=%d" % [is_instance_id_valid(stage_id), after.size()])
	if after.size() == 1:
		_main = after[0]


func _alive_heroes() -> Array:
	var out := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.is_alive())
	out.sort_custom(func(a, b): return a.index < b.index)
	return out


## (I) 개정 12 방치 무적: 방치 모드에서는 몬스터가 성문 앞에서 오래 때려도 성문·성·영웅 HP가 그대로고 몬스터는 쌓인다(상한 이하).
##     영웅의 처리를 꺼 몬스터가 죽지 않게 한다. 같은 상황이 스테이지 모드에서는 피해가 들어간다.
func _idle_invincible_case() -> void:
	_clear_monsters()
	GameState.mode = GameState.Mode.IDLE
	GameState.refill()
	await _frames(2)
	var hs := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.is_alive())
	for h in hs:
		h.set_process(false)  # 때리지 않는 표적
	var hp0 := hs.map(func(h): return h.hp)
	for side in 4:
		var gt: Vector3 = _main.castle.gate_target(side)
		for i in 3:
			_spawn("epic_boss", side, gt + Formation.SIDE_DIR[side] * (1.0 + i) + Formation.perp(side) * (i - 1) * 1.2)
	await _seconds(5.0)
	var mons := get_tree().get_nodes_in_group("monsters").filter(func(m): return m.is_alive())
	var gates_full: bool = GameState.gate_hp.all(func(g): return g == GameState.gate_hp_max)
	_check(gates_full and GameState.castle_hp == GameState.castle_hp_max and hs.map(func(h): return h.hp) == hp0,
		"(I) idle mode: gates, castle and heroes take no damage while monsters hit for 5 s",
		"gates=%s castle=%.0f heroes=%s" % [GameState.gate_hp, GameState.castle_hp, hs.map(func(h): return h.hp)])
	_check(mons.size() == 12 and mons.size() <= int(GameData.config_num("max_live_monsters")), "(I) idle mode: the monsters pile up (alive, below the cap)", "alive=%d" % mons.size())
	var h0 = hs[0]
	h0.take_damage(50.0, mons[0])
	GameState.damage_gate(0, 50.0)
	GameState.damage_castle(50.0)
	_check(h0.hp == hp0[0] and GameState.gate_hp[0] == GameState.gate_hp_max and GameState.castle_hp == GameState.castle_hp_max,
		"(I) idle mode: direct hits on a hero, a gate and the castle do nothing", "hero=%.0f gate=%.0f castle=%.0f" % [h0.hp, GameState.gate_hp[0], GameState.castle_hp])
	GameState.mode = GameState.Mode.STAGE
	await _seconds(5.0)
	var hurt: bool = GameState.gate_hp.any(func(g): return g < GameState.gate_hp_max) or GameState.castle_hp < GameState.castle_hp_max \
		or hs.any(func(h): return h.hp < hp0[hs.find(h)])
	_check(hurt, "(I) stage mode: the same monsters do damage", "gates=%s castle=%.0f heroes=%s" % [GameState.gate_hp, GameState.castle_hp, hs.map(func(h): return h.hp)])
	_clear_monsters()
	GameState.mode = GameState.Mode.IDLE
	GameState.refill()
	for h in hs:
		if is_instance_valid(h):
			h.set_process(true)
	await _frames(2)


## 시험 영웅의 공격 한 번을 끝까지(개정 12-2): 시작 → 곧바로 타격(발사) 순간 → 원거리면 투사체가 다 도착(또는 사라질) 때까지.
func _attack_now(h) -> void:
	h._attack(1.0)
	h._release()
	await _wait_until(func(): return _flying() == 0, 5.0)


## 날고 있는 투사체 수.
func _flying() -> int:
	return _main.get_children().filter(func(c): return c.get_script() == ProjectileScript).size()


## (A) 개정 12-2 §3 공격 동기화: 피해는 모션의 타격 순간(근접)·투사체 도착 순간(원거리)에. 시험 영웅·몬스터는 처리를 끄고
##     휘두름 시간(_tick_swing)을 직접 흘린다(투사체는 실제 프레임으로 난다). 마지막 DPS 사례만 영웅 처리를 켠다.
func _attack_sync() -> void:
	_clear_monsters()
	GameState.refill()
	await _frames(1)
	for x in get_tree().get_nodes_in_group("heroes"):
		x.set_process(false)
	var melee: Dictionary = GameData.hero("hans").duplicate(true)  # 기사 한손 내려치기, 간격 0.8초
	melee.skills = {}
	var h = _add_hero_def(melee, 320)
	h.set_process(false)
	var out: Vector3 = Formation.SIDE_DIR[h.side]
	var m = _still("epic_boss", _flat(h.global_position) + out * 1.2)
	await _frames(1)
	var a: float = h.atk * h._aura_mult()

	# 근접: 간격(0.8초)보다 긴 애니메이션은 빨리 돌고(길이 ≤ 간격 × 0.9), 타격 순간도 같은 비율로 당겨진다. 시작 직후엔 HP 그대로, 타격 순간에 준다
	var anim: String = h._model._spec.anims.attack
	var length: float = h._model._anim.get_animation(anim).length
	var speed := maxf(1.0, length / (0.8 * Art.ATTACK_FIT))
	h._target = m
	h._attack(0.8)
	var at: float = h._swing_left
	_check(anim == "1H_Melee_Attack_Chop" and speed > 1.0 and is_equal_approx(at, length * Art.HIT_FRAC[anim] / speed)
		and is_equal_approx(h._model._anim.get_playing_speed(), speed) and length / speed <= 0.8 * Art.ATTACK_FIT + 0.001,
		"(A) an animation longer than the interval plays faster (length / speed <= interval x 0.9) and its hit moment moves with it",
		"anim=%s len=%.3f speed=%.2f hit=%.3f" % [anim, length, h._model._anim.get_playing_speed(), at])
	h._tick_swing(at - 0.02)
	var before := _dmg(m)
	h._tick_swing(0.04)
	_check(before == 0.0 and is_equal_approx(_dmg(m), a), "(A) melee: HP is unchanged right after the swing starts and drops by atk at the hit moment (%.2f s)" % at,
		"before=%.1f after=%.1f atk=%.1f" % [before, _dmg(m), a])

	# 근접 헛스윙: 타격 순간 대상이 사거리 + 0.6 m 밖이면 피해 없음
	var hp0: float = m.hp
	h._attack(0.8)
	m.global_position += out * 3.0
	h._tick_swing(1.0)
	_check(m.hp == hp0, "(A) melee: a target beyond range + 0.6 m at the hit moment is a miss", "hp %.1f -> %.1f" % [hp0, m.hp])
	m.global_position -= out * 3.0

	# 근접: 타격 전에 대상이 죽으면 피해가 없다(휩쓸기도 없음). 산 대상이면 옆 몬스터가 휩쓸린다(대조)
	h._sk = {"cleave": [2.0, 100.0, 0.0]}
	var n = _still("epic_boss", m.global_position + Formation.perp(h.side) * 1.0)
	await _frames(1)
	h._attack(0.8)
	m.take_damage(1.0e6)
	h._tick_swing(1.0)
	var n_dead := _dmg(n)
	var m2 = _still("epic_boss", _flat(h.global_position) + out * 1.2)
	await _frames(1)
	h._target = m2
	h._attack(0.8)
	h._tick_swing(1.0)
	_check(n_dead == 0.0 and _dmg(n) > 0.0, "(A) melee: a target killed before the hit moment takes no hit and nothing is cleaved (a live one is)",
		"neighbour %.1f then %.1f" % [n_dead, _dmg(n)])
	_clear_monsters()
	await _frames(1)

	# 원거리: 발사 순간 화살이 나가고(30 m/s), 나는 동안 HP 그대로, 도착 순간 줄어든다
	var ranged: Dictionary = GameData.hero("ella").duplicate(true)  # 쇠뇌(2H_Ranged_Shoot)
	ranged.skills = {}
	var r = _add_hero_def(ranged, 321)
	r.set_process(false)
	var rout: Vector3 = Formation.SIDE_DIR[r.side]
	var t = _still("epic_boss", _flat(r.global_position) + rout * 8.0)
	await _frames(1)
	var ra: float = r.atk * r._aura_mult()
	r._target = t
	r._attack(1.0)
	r._tick_swing(r._swing_left - 0.01)
	var pre_release := _flying()
	r._tick_swing(0.02)
	var dist: float = (r.global_position + HeroScript.MUZZLE).distance_to(t.global_position + ProjectileScript.AIM)
	var full_in_flight := _flying() == 1 and _dmg(t) == 0.0
	var flew := 0.0
	while _flying() > 0 and flew < 3.0:
		await get_tree().process_frame
		flew += get_process_delta_time()
		full_in_flight = full_in_flight and (_flying() == 0 or _dmg(t) == 0.0)
	_check(pre_release == 0 and full_in_flight and is_equal_approx(_dmg(t), ra) and flew >= dist / HeroScript.ARROW_SPEED * 0.9 and flew < dist / HeroScript.ARROW_SPEED + 0.3,
		"(A) ranged: the arrow leaves at the release moment, HP stays full in flight and drops on arrival (%.1f m at 30 m/s)" % dist,
		"shots before release=%d full=%s flew %.2f s dmg=%.1f" % [pre_release, full_in_flight, flew, _dmg(t)])

	# 원거리: 도착 전에 대상이 죽으면 투사체는 사라지고 피해가 없다(연쇄도 없음)
	r._sk = {"chain": [3.0, 70.0, 4.0]}
	var t2 = _still("epic_boss", t.global_position + Formation.perp(r.side) * 6.0)
	var n2 = _still("epic_boss", t2.global_position + Formation.perp(r.side) * 1.5)
	await _frames(1)
	r._target = t2
	r._attack(1.0)
	r._tick_swing(1.0)
	await _frames(1)
	var shot := _flying()
	t2.take_damage(1.0e6)
	await _wait_until(func(): return _flying() == 0, 2.0)
	_check(shot == 1 and _flying() == 0 and _dmg(n2) == 0.0 and is_equal_approx(_dmg(t), ra),
		"(A) ranged: if the target dies before arrival the projectile vanishes and hits nothing (no chain)", "shot=%d flying=%d n2=%.1f" % [shot, _flying(), _dmg(n2)])
	_remove_hero(r)
	_clear_monsters()
	await _frames(1)

	# 몬스터도 같다: 성문 HP는 휘두름 시작이 아니라 타격 순간에 준다. 방치 무적(개정 12 §3)과 무관하게 보려고 잠깐 스테이지 모드로 둔다
	var mode0: int = GameState.mode
	GameState.mode = GameState.Mode.STAGE
	var gs := 0
	var g = _still("grunt", _main.castle.gate_target(gs))
	await _frames(1)
	var gate0: float = GameState.gate_hp[gs]
	g._swing(null, gs, _main.castle.gate_target(gs))
	var g_at: float = g._swing_left
	g._tick_swing(g_at - 0.02)
	var gate_mid: float = GameState.gate_hp[gs]
	g._tick_swing(0.04)
	GameState.mode = mode0
	_check(g_at > 0.1 and gate_mid == gate0 and is_equal_approx(gate0 - GameState.gate_hp[gs], g.atk), "(A) monster: the gate loses HP at the swing's hit moment (%.2f s), not at its start" % g_at,
		"gate %.1f -> %.1f -> %.1f atk=%.1f" % [gate0, gate_mid, GameState.gate_hp[gs], g.atk])
	_clear_monsters()
	GameState.refill()
	await _frames(1)

	# DPS 그대로: 오래 돌려도 간격(0.8초)마다 한 번 공격하고, 피해는 그 수만큼(마지막 하나는 아직 타격 전일 수 있다)
	h._sk = {}
	var boss = _still("epic_boss", _flat(h.global_position) + out * 1.2)
	boss.hp_max = 1.0e6
	boss.hp = 1.0e6
	await _frames(1)
	h._attacks = 0
	h._atk_cd = 0.0
	h.set_process(true)
	var ran := 0.0
	while ran < 4.0:
		await get_tree().process_frame
		ran += get_process_delta_time()
	h.set_process(false)
	var hits := roundi(_dmg(boss) / a)
	_check(absf(h._attacks - ran / 0.8) <= 1.0 and (hits == h._attacks or hits == h._attacks - 1) and is_equal_approx(_dmg(boss), hits * a),
		"(A) DPS unchanged: one attack per interval over %.1f s, each one hit for atk" % ran, "attacks=%d hits=%d dmg=%.1f" % [h._attacks, hits, _dmg(boss)])
	_remove_hero(h)
	_clear_monsters()
	await _frames(1)


## (S) 개정 21 병사 인공지능. 영웅 처리는 끄고(제자리, 방어력에는 센다) 스포너는 멈춘 채 실제 모드 전환(start_stage·stop_stage·결과·리필)을 쓴다.
## 걷는 구간이 길어 이 사례 동안 Engine.time_scale = SOLDIER_TIME_SCALE(기다림은 모두 게임 시간). 지휘관은 지원 사례에서만 돈다(다른 사례의 시험 몬스터가 지원을 부르지 않게).
##  - 방치 모드: 배치해도 병사 노드가 없다. 스테이지 시작: 배치 수만큼 광장에서 솟아오르고(T2 = T1 × 2) 역할 자리로 간다 —
##    궁병 성벽 위(y = WALL_H, 병사 성벽 자리), 보병 성문 앞 줄, 기병 순찰 고리
##  - 궁병은 쏘며 자리를 지키고, 성문 앞 몬스터는 보병을 노린다. 보병은 HOLD_RADIUS 밖으로 쫓지 않고 돌아온다. 기병은 돌진했다 순찰로
##  - 지원: 북문에만 큰 무리 → 기병 먼저, 모자란 만큼만 다른 면 보병(최소 집합), 각 면 보병 1명 이상, 조용해지고 3초 뒤 복귀
##  - 타격 동기화(근접 타격 순간·화살 도착 순간), 화면 밖 애니메이션 4프레임마다, 기병 속도 = 보병 × 2, 부서진 성문 → 보병은 안쪽 막는 줄
##  - 연속 진행 클리어: 같은 병사가 스테이지 시작 자리로(HP 가득·지원 해제), 카운트다운 동안 서 있다 다음 스테이지 그대로. 방치로(연속 끔 클리어·패배·중지): 0명
func _soldier_cases() -> void:
	_clear_monsters()
	GameState.mode = GameState.Mode.IDLE
	GameState.refill()
	await _frames(1)
	for x in get_tree().get_nodes_in_group("heroes"):
		x.set_process(false)
	var keep := [Economy.levels.get("houses", 1), GameState.stage, GameState.auto_continue]
	_main.command.set_process(false)
	Economy.levels["houses"] = 13  # 인구 30
	Economy.soldiers = {"infantry:1": 8, "archer:1": 3, "archer:2": 1, "cavalry:1": 4}  # 북 방어력을 낮게(지원 사례: 필요량 구간)
	var sent := Economy.set_soldier_deploy(Economy.soldiers.duplicate())
	await _frames(2)
	_check(sent and _main.soldiers.is_empty() and get_tree().get_nodes_in_group("soldiers").is_empty(),
		"(S) idle mode: a soldier deploy puts no soldier in the world (no 'soldiers' nodes, no formation in front of the keep)", "sent=%s n=%d" % [sent, _main.soldiers.size()])
	GameState.start_stage()
	await _frames(1)
	var ss: Array = _main.soldiers.duplicate()
	var spots: Array = Formation.soldier_spots(ss.map(func(s): return {"type": s.type, "tier": s.tier}))
	var rising := ss.size() == 16 and get_tree().get_nodes_in_group("soldiers").size() == 16
	for i in ss.size():
		rising = rising and ss[i].spawn.is_equal_approx(spots[i]) and ss[i]._rise > 0.0 and ss[i].global_position.y < 0.0 \
			and is_equal_approx(ss[i]._model.scale.x, Art.SOLDIER_SCALE) and (ss[i]._horse != null) == (ss[i].type == "cavalry")
	var dust: int = get_tree().get_nodes_in_group(Fx.GROUP).filter(func(n): return n.get_meta("fx", "") == "dust").size()
	_check(rising and dust > 0, "(S) stage start: all 16 deployed soldiers rise out of the plaza in front of the keep (0.9 size, cavalry on a horse, dust rings)",
		"n=%d dust=%d" % [ss.size(), dust])
	var arc2 = ss.filter(func(s): return s.type == "archer" and s.tier == 2)[0]
	var arc1 = ss.filter(func(s): return s.type == "archer" and s.tier == 1)[0]
	var inf1 = ss.filter(func(s): return s.type == "infantry")[0]
	var inf_n = ss.filter(func(s): return s.type == "infantry" and s.side == 0 and s.slot == 0)[0]
	_check(inf1.hp_max == 320.0 and inf1.atk == 22.0 and arc1.hp_max == 180.0 and arc2.hp_max == 2.0 * arc1.hp_max and arc2.atk == 2.0 * arc1.atk and arc2.side == 0 and arc2.slot == 0,
		"(S) tier 2 stats are twice tier 1 (archer 360 / 36); the highest tier takes the north first", "t2=%.0f/%.0f side %d" % [arc2.hp_max, arc2.atk, arc2.side])
	Engine.time_scale = SOLDIER_TIME_SCALE
	await _wait_until(func(): return ss.all(func(s): return _soldier_home(s)), 60.0)
	var by: Dictionary = {"archer": [], "infantry": [], "cavalry": []}
	for s in ss:
		by[s.type].append(s)
	var on_wall := func(s): return s.is_on_wall() and absf(s.global_position.y - Balance.WALL_H) < 0.01 and s.global_position.distance_to(Formation.soldier_wall_spot(_half, s.side, s.slot)) < 0.06
	var in_row := func(s): return not Formation.is_inside(_half, s.global_position) and s.global_position.distance_to(Formation.gate_row_spot(_half, s.side, s.slot)) < 0.06
	var arch_ok: bool = by.archer.size() == 4 and by.archer.all(on_wall)
	var inf_ok: bool = by.infantry.size() == 8 and by.infantry.all(in_row)
	var cav_ok: bool = by.cavalry.size() == 4 and by.cavalry.all(func(s): return s.patrolling() and absf(_cheb(s.global_position) - Formation.patrol_radius(_half)) < 0.3)
	var sides := [0, 0, 0, 0]
	for s in ss:
		sides[s.side] += 1
	_check(arch_ok and inf_ok and cav_ok and sides == [4, 4, 4, 4],
		"(S) they walk to their role posts: archers on the wall top (y = WALL_H, soldier wall spots), infantry in the gate rows, cavalry on the patrol ring; 4 per side",
		"archers=%s infantry=%s cavalry=%s sides=%s" % [arch_ok, inf_ok, cav_ok, sides])
	# 궁병: 성벽 아래 몬스터를 쏘며 자리를 지킨다
	var arc = by.archer.filter(func(s): return s.side == 0)[0]
	var apos: Vector3 = arc.global_position
	_g = _still("epic_boss", _flat(apos) + Vector3(-1.5, 0, -4.0))
	_g.hp_max = 1.0e6
	_g.hp = 1.0e6
	var saw_arrow := false
	var t := 0.0
	while t < 2.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		saw_arrow = saw_arrow or _flying() > 0
	_check(saw_arrow and _dmg(_g) > 0.0 and arc.global_position.distance_to(apos) < 0.01, "(S) a wall archer shoots monsters below and never leaves its spot",
		"arrow=%s boss dmg=%.0f moved=%.2f" % [saw_arrow, _dmg(_g), arc.global_position.distance_to(apos)])
	_clear_monsters()
	await _frames(1)
	# 성문 앞 몬스터는 그 앞 보병을 노린다(근처에 기병이 없는 면)
	var gate_inf = null
	var best := -1.0
	for s in by.infantry:
		if s.slot == 0 and s.side != 0:
			var spot: Vector3 = s.global_position + Formation.SIDE_DIR[s.side] * 3.0
			var dmin: float = by.cavalry.map(func(c): return Formation.flat_distance(c.global_position, spot)).min()
			if dmin > best:
				best = dmin
				gate_inf = s
	var grunt = _spawn("grunt", gate_inf.side, gate_inf.global_position + Formation.SIDE_DIR[gate_inf.side] * 3.0)
	await _frames(2)
	_check(_alive(grunt) and grunt._target_hero == gate_inf, "(S) a monster in front of a gate goes for the infantry standing there",
		"target=%s nearest cavalry %.1f m" % [grunt._target_hero if _alive(grunt) else null, best])
	_clear_monsters()
	await _frames(1)
	await _wait_until(func(): return ss.all(func(s): return _soldier_home(s)), 15.0)
	# 보병: 자리에서 aggro 안 적에게 다가가지만 HOLD_RADIUS 밖으로는 안 나간다. 적이 멀어지면 머문 뒤 자리로
	var post0: Vector3 = inf_n.post()
	var out: Vector3 = Formation.SIDE_DIR[0]
	_g = _still("epic_boss", post0 + out * 6.8)
	_g.hp_max = 1.0e6
	_g.hp = 1.0e6
	var far := 0.0
	await _wait_until(func(): return _dmg(_g) >= inf_n.atk, 4.0)
	var hit_once: bool = _dmg(_g) >= inf_n.atk
	t = 0.0
	while t < 2.5:  # 몬스터를 바깥으로 끌어낸다(초당 3 m)
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		_g.global_position += out * 3.0 * dt
		far = maxf(far, Formation.flat_distance(inf_n.global_position, post0))
	_check(hit_once and far > 5.0 and far <= SoldierScript.HOLD_RADIUS + 0.1, "(S) infantry engages a monster within aggro of its post but never chases past hold_radius (6 m)",
		"hit=%s max distance from post %.2f" % [hit_once, far])
	_clear_monsters()
	await _wait_until(func(): return inf_n.global_position.distance_to(post0) < 0.06, 6.0)
	_check(inf_n.global_position.distance_to(post0) < 0.06, "(S) with the monster gone it lingers, then walks back to its post", "d=%.2f" % inf_n.global_position.distance_to(post0))
	# 기병: 순찰 중 aggro(10) 안 적에게 돌진했다가 순찰로 돌아간다
	var cav = by.cavalry[0]
	var r: float = Formation.patrol_radius(_half)
	var cpos: Vector3 = cav.global_position
	_g = _still("grunt", cpos + (cpos / _cheb(cpos)).normalized() * 6.0)
	_g.hp_max = 1.0e6
	_g.hp = 1.0e6
	await _wait_until(func(): return _dmg(_g) > 0.0, 4.0)
	var charged: bool = _dmg(_g) > 0.0 and absf(_cheb(cav.global_position) - r) > 1.0 and cav.engaged()
	_clear_monsters()
	await _frames(1)
	await _wait_until(func(): return cav._linger <= 0.0 and cav._path.is_empty() and absf(_cheb(cav.global_position) - r) < 0.3, 8.0)
	_check(charged and cav.patrolling() and absf(_cheb(cav.global_position) - r) < 0.3, "(S) patrolling cavalry charges a monster within 10 m, then returns to its patrol ring",
		"charged=%s ring offset %.2f" % [charged, absf(_cheb(cav.global_position) - r)])
	await _wait_until(func(): return ss.all(func(s): return _soldier_home(s)), 15.0)
	_main.command.set_process(true)
	await _reinforce_case(ss)
	_main.command.set_process(false)
	await _strike_sync(inf1, by.archer[1])
	await _clear_and_stop(ss)
	Engine.time_scale = 1.0
	_main.command.set_process(true)
	Economy.soldiers = {}
	Economy.set_soldier_deploy({})
	Economy.levels["houses"] = keep[0]
	GameState.stage = keep[1]
	GameState.auto_continue = keep[2]
	for x in get_tree().get_nodes_in_group("heroes"):
		x.set_process(true)
	_clear_monsters()
	await _frames(1)


## 사각 거리 max(|x|, |z|) — 순찰 고리(정사각형) 위인지 본다.
func _cheb(p: Vector3) -> float:
	return maxf(absf(p.x), absf(p.z))


## 병사가 자기 자리에 와 있다(등장·경로 끝, 순찰 기병은 고리 위, 나머지는 post()).
func _soldier_home(s) -> bool:
	if not s.is_alive() or s._rise > 0.0 or not s._path.is_empty():
		return false
	if s.patrolling():
		return absf(_cheb(s.global_position) - Formation.patrol_radius(_half)) < 0.3
	return s.global_position.distance_to(s.post()) < 0.06


## 지원: 북문에만 보스 + 졸개 6을 몰아 북을 심각하게 만든다(처리 끈 몬스터, 매 프레임 HP를 채워 위협이 그대로다). 위협은 그 순간 북 방어력 D에서
## 필요량이 "기병 셋 + 보병 셋" 구간(가운데)이 되게 정한다 — 면마다 보병 둘이라 보호 하한(1명 남김)이 걸리는 크기. 판단(decide)을 바로 불러 본다:
## 기병 먼저, 보병은 가까운 순으로 동·서·남 하나씩(둘째 동·서 보병은 하한이 막는다), 필요량을 넘으면 멈춘다(최소 집합).
## 지원이 북에 닿는 동안 더 보내지 않고 각 면 보병 1명 이상. 몬스터를 치우면 3초 조용한 뒤 복귀 지시, 모두 원래 자리로 돌아간다.
func _reinforce_case(ss: Array) -> void:
	const SC := preload("res://scripts/soldier_command.gd")
	var cmd = _main.command
	var d_n: float = cmd.decide().defense[0]  # 몬스터 없음: 방어력만 본다
	var lo := maxf(0.43 * d_n, 3 * 4800.0 + 2 * 7040.0)  # 심각(위협 > D × 1.3)이면 필요량 > 0.43 D. 기병 셋 + 보병 둘보다 크고
	var hi := 3 * 4800.0 + 3 * 7040.0                      # 기병 셋 + 보병 셋 이하
	_check(lo < hi, "(S) reinforce precondition: the north defense (%.0f) leaves room for a need of 3 cavalry + 3 infantry" % d_n, "lo=%.0f hi=%.0f" % [lo, hi])
	var threat := ((lo + hi) / 2.0 + d_n) / SC.NEED
	var gt: Vector3 = Formation.gate_target(_half, 0)
	var mass := []
	for i in 6:
		var g = _still("grunt", gt + Vector3(-3.0 + i * 1.2, 0, -2.0))
		g.atk = 10.0  # 졸개 기본 공격이 바뀌어도(개정 스폰 밸런스) 이 사례의 위협 크기는 고정
		g.hp_max = 300.0  # 전투력 3000(× 초당 10)
		g.hp = 300.0
		mass.append(g)
	var boss = _still("epic_boss", gt + Vector3(0, 0, -4.0))
	boss.hp_max = (threat - 6 * 3000.0) * 1.2 / 20.0
	boss.hp = boss.hp_max
	mass.append(boss)
	var p: Dictionary = cmd.decide()
	var nodes := {}
	for s in ss:
		nodes[s.get_instance_id()] = s
	var sent: Array = p.send.map(func(e): return nodes[e[0]])
	var types: Array = sent.map(func(s): return s.type)
	var powers: Array = sent.map(func(s): return s.power())
	var total: float = powers.reduce(func(a, b): return a + b, 0.0)
	var cands: int = ss.filter(func(s): return s.side != 0 and s.type != "archer").size()
	var inf_order: Array = sent.filter(func(s): return s.type == "infantry").map(func(s): return s.side)
	_check(p.severe == [true, false, false, false] and types == ["cavalry", "cavalry", "cavalry", "infantry", "infantry", "infantry"] and inf_order.size() == 3
		and inf_order[2] == 2 and inf_order.slice(0, 2).all(func(s): return s == 1 or s == 3),
		"(S) reinforce: a mass at the north gate makes only the north severe; the 3 other cavalry go first, then infantry nearest first (east, west, then south)",
		"severe=%s sent=%s infantry sides=%s" % [p.severe, types, inf_order])
	_check(sent.size() < cands and total >= p.need[0] and total - powers[-1] < p.need[0] and sent.all(func(s): return s.reinforce == 0),
		"(S) reinforce: only the minimal set goes (%d of %d candidates; %.0f >= need %.0f, %.0f without the last)" % [sent.size(), cands, total, p.need[0], total - powers[-1]],
		"reinforce=%s" % [sent.map(func(s): return s.reinforce)])
	var floor_ok := true
	var most := 0
	var t := 0.0
	while t < 40.0 and not sent.all(func(s): return s._path.is_empty() and Formation.flat_distance(s.global_position, gt) < 12.0):
		await get_tree().process_frame
		t += get_process_delta_time()
		for m in mass:
			if _alive(m):
				m.hp = m.hp_max
		floor_ok = floor_ok and _infantry_floor(ss)
		most = maxi(most, ss.filter(func(s): return s.reinforce >= 0).size())
	_check(floor_ok and most == sent.size() and sent.all(func(s): return s.reinforce == 0 and Formation.flat_distance(s.global_position, gt) < 12.0),
		"(S) the reinforcements reach the north gate; nobody else is sent and every side keeps at least one infantry the whole time",
		"floor=%s most=%d sent=%d after %.1f s" % [floor_ok, most, sent.size(), t])
	_clear_monsters()
	await _frames(1)
	var early := false
	t = 0.0
	while t < 2.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		early = early or sent.any(func(s): return s.reinforce < 0)
	await _wait_until(func(): return sent.all(func(s): return s.reinforce < 0), 3.0)
	var back: bool = sent.all(func(s): return s.reinforce < 0)
	_check(not early and back, "(S) with the threat gone they stay ~3 s, then are sent home", "early=%s back=%s" % [early, back])
	await _wait_until(func(): return ss.all(func(s): return _soldier_home(s)), 60.0)
	_check(ss.all(func(s): return _soldier_home(s)) and _infantry_floor(ss), "(S) every reinforcement walks back to its own post",
		"not home: %s" % [ss.filter(func(s): return not _soldier_home(s)).map(func(s): return "%s@%d" % [s.type, s.side])])


## 각 면에 자기 자리를 지키는 산 보병이 1명 이상.
func _infantry_floor(ss: Array) -> bool:
	var n := [0, 0, 0, 0]
	for s in ss:
		if s.type == "infantry" and s.is_alive() and s.reinforce < 0:
			n[s.side] += 1
	return n.all(func(k): return k >= 1)


## 타격 동기화(근접 타격 순간·궁병 화살 도착 순간), 화면 밖 애니메이션, 기병 속도 = 보병 × 2, 부서진 성문 → 보병은 안쪽 막는 줄.
func _strike_sync(inf1, arc) -> void:
	Engine.time_scale = 1.0  # 화살 비행을 프레임 단위로 본다
	for s in _main.soldiers:
		s.set_process(false)
	var m = _still("epic_boss", inf1.global_position + Formation.SIDE_DIR[inf1.side] * 1.2)
	await _frames(1)
	inf1._target = m
	inf1._attack()
	var at: float = inf1._swing_left
	inf1._tick_swing(at - 0.02)
	var before := _dmg(m)
	inf1._tick_swing(0.04)
	_check(at > 0.1 and before == 0.0 and is_equal_approx(_dmg(m), inf1.atk), "(S) a melee soldier hits at the motion's hit moment (%.2f s), not at its start" % at,
		"before=%.1f after=%.1f atk=%.1f" % [before, _dmg(m), inf1.atk])
	var hp0: float = m.hp
	arc._target = m
	arc._attack()
	arc._tick_swing(1.0)
	await _frames(1)
	var in_flight: bool = _flying() == 1 and m.hp == hp0
	await _wait_until(func(): return _flying() == 0, 3.0)
	_check(in_flight and is_equal_approx(hp0 - m.hp, arc.atk), "(S) an archer shoots an arrow at the release moment; the monster loses HP only when it lands",
		"flying=%s dmg=%.1f atk=%.1f" % [in_flight, hp0 - m.hp, arc.atk])
	_clear_monsters()
	await _frames(1)
	var counts := []
	var home: Vector3 = inf1.global_position
	for where in [Vector3(0, 0, 0), Vector3(0, 0, 500)]:
		inf1.global_position = where
		var n := 0
		for i in 8:
			n += 1 if inf1._model.tick(0.016) else 0
		counts.append(n)
	inf1.global_position = home
	_check(counts == [8, 2], "(S) on screen a soldier animates every frame, off screen every 4th frame", "advances=%s" % [counts])
	Engine.time_scale = SOLDIER_TIME_SCALE
	inf1._target = null
	arc._target = null
	for s in _main.soldiers:
		s.set_process(true)
	# 속도: 자리 3 m 바깥에서 곧장 돌아오는 거리 — 기병(자기 면 지원 칸으로 보내 자리를 지키게 한 뒤)은 2배
	var cav = _main.soldiers.filter(func(s): return s.type == "cavalry")[0]
	cav.order(cav.side, 9, -100.0)
	for s in [inf1, cav]:
		s._path.clear()
		s.global_position = s.post() + Formation.SIDE_DIR[s.side_now()] * 3.0
	await _seconds(0.25)
	var moved_inf: float = 3.0 - inf1.global_position.distance_to(inf1.post())
	var moved_cav: float = 3.0 - cav.global_position.distance_to(cav.post())
	_check(moved_inf > 0.5 and absf(moved_cav / moved_inf - 2.0) < 0.05, "(S) cavalry walks twice as fast as infantry", "infantry %.2f m, cavalry %.2f m" % [moved_inf, moved_cav])
	cav.order(-1, 0, -100.0)
	# 부서진 성문: 그 면 보병은 안쪽 막는 줄로 물러선다
	var north: Array = _main.soldiers.filter(func(s): return s.type == "infantry" and s.side == 0)
	GameState.damage_gate(0, 1.0e9)
	await _frames(1)
	_check(GameState.is_gate_broken(0) and north.all(func(s): return Formation.is_inside(_half, s.post()) and not s._path.is_empty()),
		"(S) a broken gate sends that side's infantry back to blocking rows inside the gate", "%s" % [north.map(func(s): return s.post())])
	await _wait_until(func(): return north.all(func(s): return _soldier_home(s)), 30.0)
	_check(north.all(func(s): return _soldier_home(s) and Formation.is_inside(_half, s.global_position)), "(S) and they reach those rows", "")


## 스테이지 끝: 연속 진행 클리어면 같은 병사가 스테이지 시작 자리로(죽은 병사도 되살아나 HP 가득, 지원 해제) 카운트다운 동안 서 있다가 다음 스테이지를
## 그대로 시작한다. 방치로 돌아가면(연속 끔 클리어·패배·중지) 0명.
func _clear_and_stop(ss: Array) -> void:
	var a = ss.filter(func(s): return s.type == "infantry")[0]
	var b = ss.filter(func(s): return s.type == "infantry")[1]
	var c = ss.filter(func(s): return s.type == "cavalry")[1]
	a.take_damage(1.0e6)
	b.global_position += Vector3(2, 0, 2)
	b.hp = 1.0
	c.order((c.side + 1) % 4, 7, -100.0)
	var dead: bool = not a.is_alive()
	var ids: Array = ss.map(func(s): return s.get_instance_id())
	GameState.auto_continue = true
	GameState.on_all_monsters_dead()
	GameState.advance(GameData.config_num("result_sec") + 0.01)
	await _frames(1)
	var reset_ok: bool = dead and GameState.mode == GameState.Mode.COUNTDOWN and _main.soldiers.map(func(s): return s.get_instance_id()) == ids
	for s in ss:
		var spot: Vector3 = s._patrol[0] if s.type == "cavalry" else s.post()
		reset_ok = reset_ok and s.is_alive() and s.hp == s.hp_max and s.reinforce < 0 and s._path.is_empty() and s.global_position.distance_to(spot) < 0.01
	_check(reset_ok and not GameState.is_gate_broken(0),
		"(S) continuous clear: at the refill the same soldiers snap back to their stage-start posts (the dead one revived, full HP, reinforcement cleared)",
		"mode=%d revived=%s b hp=%.0f c reinforce=%d" % [GameState.mode, a.is_alive(), b.hp, c.reinforce])
	var at0: Array = ss.map(func(s): return s.global_position)
	await _seconds(0.5)
	var stood: bool = ss.map(func(s): return s.global_position) == at0
	GameState.advance(GameData.config_num("countdown_sec") + 0.01)
	await _frames(1)
	_check(stood and GameState.mode == GameState.Mode.STAGE and _main.soldiers.map(func(s): return s.get_instance_id()) == ids and ss.all(func(s): return s._rise == 0.0),
		"(S) they stand through the countdown and the next stage starts with them in place (no re-spawn)", "stood=%s mode=%d" % [stood, GameState.mode])
	GameState.auto_continue = false
	GameState.on_all_monsters_dead()
	GameState.advance(GameData.config_num("result_sec") + 0.01)
	await _frames(1)
	_check(GameState.mode == GameState.Mode.IDLE and _main.soldiers.is_empty() and get_tree().get_nodes_in_group("soldiers").is_empty(),
		"(S) a clear with continuous play off goes back to idle: no soldiers", "mode=%d n=%d" % [GameState.mode, get_tree().get_nodes_in_group("soldiers").size()])
	await _seconds(0.4)
	_check(ids.all(func(id): return not is_instance_id_valid(id)), "(S) the vanished soldiers are freed after shrinking away (0.3 s)", "")
	GameState.start_stage()
	await _frames(1)
	var n_again := get_tree().get_nodes_in_group("soldiers").size()
	GameState.damage_castle(1.0e9)
	GameState.advance(GameData.config_num("result_sec") + 0.01)
	await _frames(1)
	_check(n_again == 16 and GameState.mode == GameState.Mode.IDLE and get_tree().get_nodes_in_group("soldiers").is_empty(),
		"(S) a defeat goes back to idle: the next stage's soldiers vanish too", "again=%d mode=%d" % [n_again, GameState.mode])
	GameState.start_stage()
	await _frames(1)
	n_again = get_tree().get_nodes_in_group("soldiers").size()
	GameState.stop_stage()
	await _frames(1)
	_check(n_again == 16 and GameState.mode == GameState.Mode.IDLE and get_tree().get_nodes_in_group("soldiers").is_empty() and _main.soldiers.is_empty(),
		"(S) ■ stop goes back to idle: no soldiers", "again=%d" % n_again)


## 개정 14 §3 FEVER 스폰: 방치 스포너는 FEVER 중 같은 시간에 3배(±1 무리) 마리를 내고, 스테이지 모드는 변화가 없다.
func _fever_spawn() -> void:
	var mode0: int = GameState.mode
	var counts := {}
	for k in ["idle", "idle_fever", "stage", "stage_fever"]:
		Fever.reset()
		if k.ends_with("fever"):
			Fever.left = 180.0
		GameState.mode = GameState.Mode.IDLE if k.begins_with("idle") else GameState.Mode.STAGE
		var holder := Node.new()
		add_child(holder)
		var sp = SpawnerScript.new()
		sp.castle = _main.castle
		holder.add_child(sp)  # _ready가 모드의 스케줄을 읽는다
		for i in 400:  # 20 s (FEVER 3배도 상한 120 아래)
			sp._process(0.05)
		counts[k] = sp._live
		holder.queue_free()
		await _frames(1)
	Fever.reset()
	GameState.mode = mode0
	_clear_monsters()
	# 스폰 한 번 = spawn_group(3)마리라 수는 3 단위. 허용 오차: 방치 쪽 스폰 한 번이 끝자락에 들고 안 들고의 3배
	var grp := int(GameData.config_num("spawn_group"))
	var ev := 4 * grp  # 방치 한 번 = 네 면 × 무리
	var whole: bool = counts.idle % ev == 0 and counts.idle_fever % ev == 0
	_check(counts.idle >= ev and whole and absi(counts.idle_fever - 3 * counts.idle) <= ev,
		"(fever) FEVER triples the idle spawn count over the same time (whole events of 4 sides x 3, ±1 event)", str(counts))
	_check(counts.stage == counts.stage_fever and counts.stage > 0, "(fever) stage mode spawns are unchanged by FEVER", str(counts))


## 개정 17 §5: ★0 영웅은 스킬 2를 쓰지 않고(세라핀 slow 없음) ★3이면 쓴다. aoe_blast가 이펙트 노드(파편·고리·섬광)를 만들고 상한을 넘지 않는다.
## 이름 띠(1.5초에 한 번)·발밑 맥동, 기절 별은 기절 동안만, 오라를 받는 영웅 발밑 고리, 테스트에서는 흔들림 끔. 영웅·몬스터는 처리를 끈다.
func _skill_unlock_cases() -> void:
	_clear_monsters()
	GameState.refill()
	await _frames(1)
	for x in get_tree().get_nodes_in_group("heroes"):
		x.set_process(false)
	var dn = DamageNumbersScript.current
	var K = DamageNumbersScript.Kind
	# (U1) 세라핀 ★0: 연쇄만 — 맞아도 느려지지 않는다. ★3: slow가 열려 느려지고 발밑 결정이 남는다
	var s0 = _add_hero("seraphine", 342, 0)
	var s3 = _add_hero("seraphine", 346, 3)
	for h in [s0, s3]:
		h.set_process(false)
	var m0 = _still("epic_boss", _flat(s0.global_position) + Formation.SIDE_DIR[2] * 3.0)
	await _frames(1)
	s0._target = m0
	await _attack_now(s0)
	_check(s0._sk.keys() == ["chain"] and _dmg(m0) > 0.0 and m0._slow_t <= 0.0 and m0.status_fx("slow") == null,
		"(U1) seraphine at ★0 uses only skill 1: her hit does not slow", "skills=%s dmg=%.1f slow=%.2f" % [s0._sk.keys(), _dmg(m0), m0._slow_t])
	var m3 = _still("epic_boss", _flat(s3.global_position) + Formation.SIDE_DIR[2] * 3.0)
	await _frames(1)
	s3._target = m3
	await _attack_now(s3)
	_check(s3._sk.keys() == ["chain", "slow"] and m3._slow_t > 0.0 and m3.status_fx("slow") != null,
		"(U1) at ★3 skill 2 is unlocked: the hit slows and leaves ice crystals at its feet", "skills=%s slow=%.2f" % [s3._sk.keys(), m3._slow_t])
	_remove_hero(s0)
	_remove_hero(s3)
	_clear_monsters()
	await _frames(1)
	await _wait_until(func(): return Fx.live() == 0, 3.0)

	# (U2) 기절 별: 크게, 기절 동안 하나만 남고, 끝나면 사라진다
	var ms = _still("grunt", Vector3(0, 0, -(_half + Balance.WALL_T + 20.0)))
	await _frames(1)
	ms.apply_stun(0.5)
	var star = ms.status_fx("stun")
	ms.apply_stun(0.3)
	var stars: int = ms.get_children().filter(func(c): return c.get_meta("fx", "") == "stun").size()
	ms._process(0.3)
	var kept: bool = star != null and is_instance_valid(star) and not star.is_queued_for_deletion()
	ms._process(0.3)
	await _frames(1)
	_check(kept and stars == 1 and not is_instance_valid(star) and ms._status.is_empty(), "(U2) stun stars stay (one per monster) while stunned and vanish when it ends",
		"kept=%s stars=%d status=%s" % [kept, stars, ms._status.keys()])
	_clear_monsters()
	await _frames(1)

	# (U3) 이그니스(SSR ★0) 폭발: 20면체·충격파 고리·섬광·파편 8~12, 이름 띠 "화염구!"(고유 색)·발밑 맥동, 흔들림 끔. 1.5초 안 두 번째는 띠 없음
	await _wait_until(func(): return Fx.live() == 0, 3.0)
	var ig = _add_hero("ignis", 343, 0)
	ig.set_process(false)
	var mb = _still("epic_boss", _flat(ig.global_position) + Formation.SIDE_DIR[3] * 3.0)
	await _frames(1)
	dn._list.clear()
	ig._blast(mb.global_position)
	var tags := {}
	for n in get_tree().get_nodes_in_group(Fx.GROUP):
		var t: String = n.get_meta("fx", "")
		tags[t] = tags.get(t, 0) + 1
	var banners: Array = dn._list.filter(func(e): return e.kind == K.BANNER)
	_check(tags.get("blast", 0) == 1 and tags.get("shock", 0) == 1 and tags.get("flash", 0) == 1 and tags.get("shard", 0) >= Fx.SHARDS_MIN
		and tags.get("shard", 0) <= Fx.SHARDS_MAX and Fx.live() <= Fx.MAX_LIVE, "(U3) aoe_blast makes an icosahedron, a shockwave ring, a flash and 8-12 shards", str(tags))
	_check(banners.size() == 1 and banners[0].text == "화염구!" and banners[0].bg == Color(ig.def.color) and tags.get("pulse", 0) == 1,
		"(U3) the blast shows ignis's name banner in her color and pulses her foot ring", "banners=%s tags=%s" % [banners.map(func(e): return e.text), tags])
	_check(tags.get("burst", 0) == 1 and tags.get("wave", 0) >= 1 and tags.get("pillar", 0) >= 1 and tags.get("rays", 0) == 1 and tags.get("motes", 0) >= 1,
		"(U3) SSR tier: the blast adds a ground flare, a second shockwave, a light pillar and embers; the activation raises light rays", str(tags))
	var rig = get_viewport().get_camera_3d().get_parent()
	_check(rig.has_method("is_shaking") and not rig.is_shaking() and not GameData.fx_shake(), "(U3) with fx_shake off (tests) the SSR blast does not shake the camera", "")
	ig._blast(mb.global_position)
	_check(dn._list.filter(func(e): return e.kind == K.BANNER).size() == 1, "(U3) a second blast within 1.5 s shows no second banner", "")
	await _wait_until(func(): return Fx.live() == 0, 3.0)
	for i in Fx.MAX_LIVE - 5:
		Fx.heal_ring(_main, Vector3(0, 0, -5.0), 2.0)
	ig._blast(mb.global_position)
	_check(Fx.live() == Fx.MAX_LIVE and get_tree().get_nodes_in_group(Fx.GROUP).size() == Fx.MAX_LIVE, "(U3) a blast near the cap stops at MAX_LIVE (extra shards are skipped)",
		"live=%d" % Fx.live())
	_remove_hero(ig)
	_clear_monsters()
	await _frames(1)

	# (U4) atk_aura 버프 표시: ★0 루미나 곁(오라 잠김)이면 없고, ★3 루미나 곁이면 고르크 발밑에 주황 고리
	var lu0 = _add_hero("lumina", 340, 0)
	var gk = _add_hero("gork", 341, 0)
	var lu3 = _add_hero("lumina", 345, 3)
	for h in [lu0, gk, lu3]:
		h.set_process(false)
	lu0.global_position = gk.global_position + Vector3(0, 0, 3.0)
	lu3.global_position = gk.global_position + Vector3(0, 0, -40.0)
	gk._tick_skills(0.3)
	var off: bool = gk._aura_ring.visible
	lu3.global_position = gk.global_position + Vector3(0, 0, -3.0)
	gk._tick_skills(0.3)
	_check(not off and gk._aura_ring.visible, "(U4) an unlocked atk_aura (lumina ★3) puts an orange ring under the buffed hero; a locked one (★0) does not",
		"locked=%s unlocked=%s" % [off, gk._aura_ring.visible])
	for h in [lu0, gk, lu3]:
		_remove_hero(h)
	await _wait_until(func(): return Fx.live() == 0, 3.0)

	# (U5) 등급 연출: 같은 발동이 R은 고리·빛무리·광선 3겹, SR은 입자까지 4겹, SSR은 빛기둥·파동까지 6겹
	var layers := []
	for t in [0, 1, 2]:
		await _wait_until(func(): return Fx.live() == 0, 3.0)
		var probe := Node3D.new()
		_main.add_child(probe)
		var foot := Fx.foot_ring(Color.WHITE, Color.RED)
		probe.add_child(foot)
		Fx.pulse(probe, foot, Color.RED, t)
		layers.append(Fx.live())
		probe.queue_free()
	await _frames(1)
	_check(layers == [3, 4, 6] and Fx.live() == 0, "(U5) skill activation layers grow with grade: R 3, SR 4, SSR 6 effect nodes", str(layers))
	GameState.refill()
	await _frames(1)

	# (U6) 발동 모션(개정 25): 발렌의 메테오는 쿨이 차면 먼저 Spellcast_Raise 모션 + 기 모으기를 시작하고(평타·이펙트 없음),
	#      모션의 발동 순간(≤ Art.CAST_WINDUP초)에 메테오와 이름 띠가 나온다. 시전 중 기절하면 발동하지 않는다.
	var va = _add_hero("valen", 344, 0)
	va.set_process(false)
	var vt = _still("epic_boss", _flat(va.global_position) + Formation.SIDE_DIR[va.side] * 4.0)
	await _frames(1)
	va._target = vt
	va._skx._cd["meteor"] = 0.0
	va._skx.tick(0.016)
	var tag_n := func(tag: String) -> int:
		return get_tree().get_nodes_in_group(Fx.GROUP).filter(func(n): return n.get_meta("fx", "") == tag and not n.is_queued_for_deletion()).size()
	var casting: bool = va.is_casting()
	var anim: String = va._model._current
	var early: int = tag_n.call("meteor")
	var charged: int = tag_n.call("charge")
	var waited := 0.0
	while va.is_casting() and waited < 2.0:
		va._process(0.05)
		waited += 0.05
	_check(casting and anim == "Spellcast_Raise" and early == 0 and charged == 1 and tag_n.call("meteor") == 1 and va._attacks == 0
		and waited <= Art.CAST_WINDUP + 0.06 and va._skx._cd["meteor"] > 1.0,
		"(U6) an active skill plays its cast motion first and lands at the release moment", "casting=%s anim=%s early=%d charge=%d meteor=%d waited=%.2f cd=%.1f" % [
			casting, anim, early, charged, tag_n.call("meteor"), waited, va._skx._cd["meteor"]])
	await _wait_until(func(): return Fx.live() == 0, 3.0)
	va._skx._cd["meteor"] = 0.0
	va._skx.tick(0.016)
	var cast2: bool = va.is_casting()
	va.apply_stun(0.2)
	var cut: bool = not va.is_casting() and tag_n.call("charge") == 0
	va._stun_t = 0.0
	for i in 20:
		va._process(0.05)
	_check(cast2 and cut and tag_n.call("meteor") == 0, "(U6) a stun during the cast motion cancels the skill", "cast=%s cut=%s meteor=%d" % [cast2, cut, tag_n.call("meteor")])
	_remove_hero(va)
	_clear_monsters()
	await _frames(1)


## (R) 공격 뒤 뒷걸음 없음: 자리 바깥쪽 한 줄로 놓은 제자리 괴물(뒤 괴물일수록 멀다)을 차례로 잡는 동안 자리 쪽으로 물러나지 않고
##     (표적이 죽으면 같은 프레임에 다시 찾는다), 마지막 처치 뒤 RETURN_DELAY(1.5초) 동안 머물다 자리로 돌아간다. 머무는 중에 나타난
##     괴물은 그 자리에서 맞는다. 근접 영웅(북 성문 앞)과 보병(성문 앞 줄, 스테이지 모드) 둘 다.
func _hold_ground_case() -> void:
	_clear_monsters()
	GameState.mode = GameState.Mode.STAGE
	GameState.refill()
	await _frames(1)
	var others := get_tree().get_nodes_in_group("heroes")
	for x in others:
		x.set_process(false)
	var h = _add_hero("hans", 100)  # 북(0) 성문 앞 근접
	await _frames(1)
	var home: Vector3 = h.stand_position()
	var out: Vector3 = Formation.SIDE_DIR[0]
	var r: Dictionary = await _kill_row(h, home, out, [2.6, 4.6, 6.6])
	_check(r.cleared and r.back < 0.05, "(R) a melee hero does not step back toward its post between kills", "cleared=%s back=%.2f m" % [r.cleared, r.back])
	# 머무는 중(0.6초 뒤) 더 바깥에 나타난 괴물: 자리로 가지 않고 그 자리에서 다가가 친다
	var stand := Formation.flat_distance(h.global_position, home)
	var back := 0.0
	var t := 0.0
	while t < 0.6:
		await get_tree().process_frame
		t += get_process_delta_time()
		back = maxf(back, stand - Formation.flat_distance(h.global_position, home))
	_g = _still("grunt", home + out * (stand + 2.5))
	t = 0.0
	while t < 5.0 and _alive(_g):
		await get_tree().process_frame
		t += get_process_delta_time()
		back = maxf(back, stand - Formation.flat_distance(h.global_position, home))
	_check(not _alive(_g) and back < 0.05, "(R) a monster that shows up while the hero lingers is engaged from where it stands", "alive=%s back=%.2f m" % [_alive(_g), back])
	# 마지막 처치 뒤: 1.5초 머문 뒤에야 자리 쪽으로 걷고, 끝내 자리에 선다
	var left: float = await _return_time(h, home, 6.0)
	var hd := Formation.flat_distance(h.global_position, home)
	_check(left >= 1.4 and hd < 0.1, "(R) the hero walks home only after no target has been in range for RETURN_DELAY (1.5 s)", "left after %.2f s, d=%.2f" % [left, hd])
	_remove_hero(h)
	# 보병(개정 21: 스테이지에 등장해 북 성문 앞 줄로 간다): 자리 바깥쪽(북) 한 줄 — 모두 aggro 7·hold_radius 6 안
	GameState.mode = GameState.Mode.IDLE
	Economy.soldiers = {"infantry:1": 1}
	Economy.set_soldier_deploy({"infantry:1": 1})
	GameState.start_stage()
	var s = _main.soldiers[0]
	Engine.time_scale = SOLDIER_TIME_SCALE
	await _wait_until(func(): return s._rise <= 0.0 and s._path.is_empty() and s.global_position.distance_to(s.post()) < 0.06, 40.0)
	Engine.time_scale = 1.0
	var spost: Vector3 = s.post()
	var sdir: Vector3 = Formation.SIDE_DIR[s.side]
	var outside: bool = [2.2, 4.0, 5.8].all(func(d): return not Formation.is_inside(_half, spost + sdir * d))
	r = await _kill_row(s, spost, sdir, [2.2, 4.0, 5.8])
	_check(outside and r.cleared and r.back < 0.05, "(R) an infantry soldier (gate row) does not step back toward its post between kills",
		"outside=%s cleared=%s back=%.2f m" % [outside, r.cleared, r.back])
	left = await _return_time(s, spost, 6.0)
	hd = Formation.flat_distance(s.global_position, spost)
	_check(left >= 1.4 and hd < 0.1, "(R) the soldier walks back only after RETURN_DELAY (1.5 s) without a target", "left after %.2f s, d=%.2f" % [left, hd])
	GameState.stop_stage()
	Economy.set_soldier_deploy({})
	await _frames(2)
	for x in others:
		if is_instance_valid(x):
			x.set_process(true)
	_clear_monsters()
	await _frames(1)


## 제자리 괴물을 home + dir × 거리마다 놓고 다 죽을 때까지(최대 15초) u의 home 거리를 본다.
## back = 첫 처치 뒤, 그때까지 가장 멀리 나간 곳에서 home 쪽으로 돌아온 최대 거리(뒤 괴물이 더 멀어 물러날 까닭이 없다).
func _kill_row(u, home: Vector3, dir: Vector3, dists: Array) -> Dictionary:
	var row := []
	for d in dists:
		row.append(_still("grunt", home + dir * d))
	var peak := 0.0
	var back := 0.0
	var t := 0.0
	while t < 15.0 and row.any(_alive):
		await get_tree().process_frame
		t += get_process_delta_time()
		var d := Formation.flat_distance(u.global_position, home)
		peak = maxf(peak, d)
		if not _alive(row[0]):
			back = maxf(back, peak - d)
	return {"cleared": not row.any(_alive), "back": back}


## 지금 위치에서 home 쪽으로 0.05 m 넘게 다가가기 시작한 초(timeout 안에 안 가면 INF). home에 닿을 때까지(최대 timeout) 기다린다.
func _return_time(u, home: Vector3, timeout: float) -> float:
	var stand := Formation.flat_distance(u.global_position, home)
	var left := INF
	var t := 0.0
	while t < timeout and Formation.flat_distance(u.global_position, home) > 0.05:
		await get_tree().process_frame
		t += get_process_delta_time()
		if left == INF and Formation.flat_distance(u.global_position, home) < stand - 0.05:
			left = t
	return left


## 무리 스폰(스포너): 첫 스폰은 3마리가 한꺼번에 한 면(북)에 나오고(방치는 idle_interval 8초에, 스테이지는 곧바로),
##     옆으로 칸을 나눠 서로 2 m 넘게 떨어진다(겹쳐 나오지 않는다).
func _group_spawn() -> void:
	var mode0: int = GameState.mode
	Fever.reset()
	for k in ["idle", "stage"]:
		_clear_monsters()
		await _frames(1)
		GameState.mode = GameState.Mode.IDLE if k == "idle" else GameState.Mode.STAGE
		var holder := Node.new()
		add_child(holder)
		var sp = SpawnerScript.new()
		sp.castle = _main.castle
		holder.add_child(sp)
		var clock := 0.0
		while sp._live == 0 and clock < 20.0:
			sp._process(0.05)
			clock += 0.05
		var ms: Array = holder.get_children().filter(func(c): return c != sp)
		var side: int = ms[0].side if ms.size() > 0 else -1
		var offs: Array = ms.map(func(m): return m.global_position.dot(Formation.perp(side)))
		offs.sort()
		var gap := INF
		for i in range(1, offs.size()):
			gap = minf(gap, offs[i] - offs[i - 1])
		var near := ms.all(func(m): return Formation.flat_distance(m.global_position, Formation.spawn_center(_half, m.side)) <= Balance.SPAWN_SPREAD + 0.01)
		var sides: Array = ms.map(func(m): return m.side)
		var when_ok := clock >= 7.95 and clock <= 8.11 if k == "idle" else clock <= 0.06
		if k == "idle":  # 네 면 동시 12마리 — 아래 검사는 북쪽 무리만
			var all4: bool = ms.size() == 12 and [0, 1, 2, 3].all(func(sd): return ms.filter(func(m): return m.side == sd).size() == 3)
			_check(all4, "(group) idle: 12 monsters at once, 3 on each of the 4 sides", "n=%d sides=%s" % [ms.size(), ms.map(func(m): return m.side)])
			ms = ms.filter(func(m): return m.side == 0)
			offs = ms.map(func(m): return m.global_position.dot(Formation.perp(0)))
			offs.sort()
			gap = INF
			for i in range(1, offs.size()):
				gap = minf(gap, offs[i] - offs[i - 1])
			sides = ms.map(func(m): return m.side)
			near = ms.all(func(m): return Formation.flat_distance(m.global_position, Formation.spawn_center(_half, m.side)) <= Balance.SPAWN_SPREAD + 0.01)
		_check(ms.size() == 3 and sides == [0, 0, 0] and near and gap >= 1.99 and when_ok,
			"(group) %s: the first spawn is 3 monsters at once on one side, spread sideways >= 2 m apart" % k,
			"n=%d at %.2f s sides=%s near=%s offsets=%s" % [ms.size(), clock, sides, near, offs])
		holder.queue_free()
		await _frames(1)
	GameState.mode = mode0
	_clear_monsters()
	await _frames(1)


## 개정 22 §2 §3: 스테이지 모드 스포너는 라운드 1-1·1-24(g = 1·24)에 보스를 내지 않고 1-25에만 HP × boss_round_mult 보스를 낸다
## (24·25행은 잠시 웨이브 1 × 2로 줄인다 — 수천 마리를 만들지 않게). 스테이지 2(g = 26) 적은 스테이지 1보다 1.08배 빨리 걷는다
## (같은 자리에서 진로로 1초 — 졸개·보스).
func _round_cases() -> void:
	var mode0: int = GameState.mode
	var g0: int = GameState.stage
	var rows: Array = GameData._stages.duplicate(true)
	for i in [23, 24]:
		GameData._stages[i].waves = 1
		GameData._stages[i].wave_size = 2
	var bosses := {}
	var grunts := {}
	for g in [1, 24, 25]:
		_clear_monsters()
		await _frames(1)
		GameState.stage = g
		GameState.mode = GameState.Mode.STAGE
		var holder := Node.new()
		add_child(holder)
		var sp = SpawnerScript.new()
		sp.castle = _main.castle
		holder.add_child(sp)  # _ready가 g의 스테이지 스케줄을 읽는다
		for i in 3000:  # 스케줄 끝까지(몬스터가 살아 있어 전멸 감지는 안 된다)
			if sp._cursor >= sp._events.size():
				break
			sp._process(0.1)
		var ms: Array = holder.get_children().filter(func(c): return c != sp)
		bosses[g] = ms.filter(func(m): return m.kind == "epic_boss").map(func(m): return m.hp_max)
		grunts[g] = ms.filter(func(m): return m.kind == "grunt").size()
		holder.queue_free()
		await _frames(1)
	GameData._stages = rows
	var boss_hp: float = GameData.monster("epic_boss").hp * GameData.stage(25).hp_mult * GameData.config_num("boss_round_mult")
	_check(bosses[1].is_empty() and bosses[24].is_empty() and bosses[25].size() == 1 and is_equal_approx(bosses[25][0], boss_hp) and grunts[1] == 72 and grunts[25] == 6,
		"(round) rounds 1-1 and 1-24 spawn no boss; round 1-25 spawns one boss with hp x boss_round_mult", "bosses=%s grunts=%s want hp %.0f" % [bosses, grunts, boss_hp])
	var moved := {}
	for g in [1, 26]:
		for kind in ["grunt", "epic_boss"]:
			var m = MonsterScript.new()
			m.setup(kind, 0, g, _main.castle)
			_main.add_child(m)
			m.set_process(false)
			var p0 := Vector3(0, 0, -(_half + Balance.WALL_T + 30.0))
			m.global_position = p0
			m._advance(1.0)
			moved["%s@%d" % [kind, g]] = Formation.flat_distance(p0, m.global_position)
			m.queue_free()
	_check(is_equal_approx(moved["grunt@1"], 2.5) and is_equal_approx(moved["grunt@26"] / moved["grunt@1"], 1.08)
		and is_equal_approx(moved["epic_boss@26"] / moved["epic_boss@1"], 1.08),
		"(round) stage 2 (g = 26) grunts and bosses walk 1.08x as far in 1 s as stage 1", str(moved))
	GameState.stage = g0
	GameState.mode = mode0
	_clear_monsters()
	await _frames(1)


## 스테이지 시작 자리 복원: 스테이지 중 옮긴 영웅은 끝(클리어·중지) 뒤 시작 자리로 돌아가고, 방치 중 옮긴 자리는 [진행] 뒤에도 유지된다.
func _stage_return_cases() -> void:
	_clear_monsters()
	GameState.mode = GameState.Mode.IDLE
	GameState.refill()
	await _frames(2)
	var h = _main._slots[0].node
	GameState.start_stage()  # 한 번 돌고 멈춘 뒤(IDLE 진입 직후)에도 방치 이동이 유지되어야 한다
	GameState.stop_stage()
	var start := [h.side, h.post, h.slot]
	# 방치 중 옮김 → [진행] 뒤에도 그대로(start_stage의 리필은 복원하지 않는다)
	_check(h.move_to((h.side + 1) % 4, h.post), "(R0) idle move accepted", "")
	var idle_spot := [h.side, h.post, h.slot]
	h.reset()
	GameState.start_stage()
	_check([h.side, h.post, h.slot] == idle_spot and h.global_position.is_equal_approx(h.stand_position()),
		"(R1) a move made in IDLE sticks through [start]", "now=%s want=%s" % [[h.side, h.post, h.slot], idle_spot])
	# 스테이지 중 다른 성문으로 → 연속 클리어 뒤 시작 자리(= 방치에서 옮긴 자리)로 복귀
	_check(h.move_to((h.side + 2) % 4, h.post), "(R2) mid-stage move accepted", "")
	h.global_position = h.stand_position()
	GameState.auto_continue = true
	GameState.on_all_monsters_dead()
	GameState.advance(GameData.config_num("result_sec") + 0.1)
	_check(GameState.mode == GameState.Mode.COUNTDOWN and [h.side, h.post, h.slot] == idle_spot
		and h.global_position.is_equal_approx(h.stand_position()),
		"(R2) after a continuous clear the hero is back at its stage-start slot", "now=%s want=%s mode=%d" % [[h.side, h.post, h.slot], idle_spot, GameState.mode])
	# 다음 STAGE는 새 기록: 거기서 옮기고 중지 → 그 자리로
	GameState.advance(GameData.config_num("countdown_sec") + 0.1)
	_check(GameState.mode == GameState.Mode.STAGE, "(R3) countdown ends in STAGE", "mode=%d" % GameState.mode)
	_check(h.move_to((h.side + 3) % 4, h.post), "(R3) second stage move accepted", "")
	GameState.stop_stage()
	_check([h.side, h.post, h.slot] == idle_spot and h.global_position.is_equal_approx(h.stand_position()),
		"(R3) after a stop the hero is back at its stage-start slot", "now=%s want=%s" % [[h.side, h.post, h.slot], idle_spot])
	# 기록은 한 번 쓰면 사라진다: 방치 중 옮기고 다시 리필해도 유지
	h.move_to(start[0], start[1])
	GameState.refill()
	_check([h.side, h.post] == [start[0], start[1]], "(R4) the snapshot is consumed: a later refill keeps idle moves", "side=%d post=%d" % [h.side, h.post])
	GameState.mode = GameState.Mode.IDLE


## (R5) 스테이지 중 레벨이 올라(승급·장비도 같은 경로) 그 스테이지를 끝내는 리필에서 다시 만든 영웅도 스테이지 시작 자리로 간다(main 기록은 영웅 id로).
func _rebuilt_post_case() -> void:
	_clear_monsters()
	GameState.mode = GameState.Mode.IDLE
	GameState.refill()
	await _frames(2)
	var h = _main._slots[0].node
	var id: String = h.def.id
	var old_id: int = h.get_instance_id()
	_check(h.move_to((h.side + 1) % 4, h.post), "(R5) precondition: idle move off the default side", "")
	h.reset()
	var start := [h.side, h.post, h.slot]  # 방치 중 옮긴 자리 = 스테이지 시작 자리(기본 자리 index % 4와 다르다)
	GameState.start_stage()
	h.move_to((h.side + 2) % 4, h.post)  # 스테이지 중 다른 성문으로
	Economy.gold_tenths = 10000000
	var leveled := Economy.level_up(id, 1)  # 스테이지 중이라 다음 리필에 다시 만든다
	var kept_now: bool = _main._slots[0].node.get_instance_id() == old_id
	GameState.stop_stage()
	await _frames(1)
	var nh = _main._slots[0].node
	_check(leveled and kept_now and nh.get_instance_id() != old_id and nh.def.id == id and [nh.side, nh.post, nh.slot] == start
		and nh.global_position.is_equal_approx(nh.stand_position()) and _main._formation.assignment(0) == {"side": start[0], "post": start[1], "slot": start[2]},
		"(R5) a hero rebuilt on refill (level up mid-stage) stands at its stage-start post, not the default one",
		"leveled=%s kept=%s rebuilt=%s now=%s want=%s" % [leveled, kept_now, nh.get_instance_id() != old_id, [nh.side, nh.post, nh.slot], start])


## (G) 개정 20 성장의 전투 반영: 성장 레벨(Economy.upgrades → upgrades_changed)이 영웅·병사의 공격·HP·공격 간격·이동·치명타에 곧바로 들어간다.
##     치명타 확률 100%는 표의 per_level을 잠시 키워 주입한다(실제 경로: Economy → upgrade_bonus → refresh_stats → 타격). 신발 이동속도도 같이.
func _growth_cases() -> void:
	_clear_monsters()
	GameState.mode = GameState.Mode.STAGE  # 리필이 영웅을 다시 만들지 않게(장비 변경), 피해가 들어가게
	GameState.refill()
	await _frames(1)
	for x in get_tree().get_nodes_in_group("heroes"):
		x.set_process(false)
	var plain: Dictionary = GameData.hero("hans").duplicate(true)  # 기사(근접), 스킬 없음 — 신발을 끼울 수 있게 id는 한스
	plain.skills = {}
	var h = _add_hero_def(plain, 330)
	h.set_process(false)
	var base := GameData.hero_stats(plain, 1, 0)
	var out: Vector3 = Formation.SIDE_DIR[h.side]
	var m = _still("epic_boss", _flat(h.global_position) + out * 1.2)
	m.hp_max = 1.0e6  # 이 사례의 타격을 다 받아도 죽지 않게
	m.hp = m.hp_max
	await _frames(1)
	h._target = m
	# 공격·HP +100%(Lv 200): 곧바로. HP는 비율을 지킨다(반 깎인 채 강화 → 새 최대의 반)
	h.take_damage(h.hp_max / 2.0)
	Economy.upgrades = {"atk": 200, "hp": 200}
	Economy.upgrades_changed.emit()
	await _attack_now(h)
	_check(is_equal_approx(h.atk, base.atk * 2.0) and is_equal_approx(h.hp_max, base.hp * 2.0) and is_equal_approx(h.hp, base.hp) and is_equal_approx(_dmg(m), base.atk * 2.0 * h._aura_mult()),
		"(G) growth atk/hp +100% apply at once: atk x2 (the hit too), max HP x2 keeping the HP ratio",
		"atk=%.1f hp=%.1f/%.1f dmg=%.1f base=%s" % [h.atk, h.hp, h.hp_max, _dmg(m), base])
	# 공격속도 +25%(Lv 100): 지금 쿨은 그대로, 다음 공격 간격 = 기본 ÷ 1.25
	h._scan_cd = 1.0
	h._atk_cd = 0.0
	h._process(0.0)  # 사거리 안 표적 → 공격, 쿨 = 간격
	var cd0: float = h._atk_cd
	Economy.upgrades["aspd"] = 100
	Economy.upgrades_changed.emit()
	var cd_kept: float = h._atk_cd
	h._atk_cd = 0.0
	h._process(0.0)
	_check(is_equal_approx(cd0, plain.atk_interval) and cd_kept == cd0 and is_equal_approx(h._atk_cd, plain.atk_interval / 1.25),
		"(G) growth aspd +25%: the cooldown running keeps going, the next attack waits base / 1.25", "before=%.3f kept=%.3f next=%.3f" % [cd0, cd_kept, h._atk_cd])
	# 이동속도 +20%(Lv 80): 0.1초에 def.speed × 1.2 × 0.1 m. 신발(+3%)을 끼면 곧바로 × (1 + 0.20 + 0.03)
	Economy.upgrades["mspd"] = 80
	Economy.upgrades_changed.emit()
	var walked := _walk(h, 0.1)
	var item_id: int = Economy.next_item_id + 900
	Economy.bag.append({"id": item_id, "slot": "shoes", "weapon_kind": null, "grade": "N", "level": 1})
	var worn := Economy.equip("hans", "shoes", item_id)
	var walked_shoes := _walk(h, 0.1)
	_check(is_equal_approx(walked, plain.speed * 1.2 * 0.1) and worn and is_equal_approx(walked_shoes, plain.speed * 1.23 * 0.1),
		"(G) growth mspd +20% walks 1.2x as far; shoes add +3% at once (x1.23)", "walked=%.4f shoes=%.4f speed=%.2f" % [walked, walked_shoes, plain.speed])
	Economy.unequip("hans", "shoes")
	Economy.bag = Economy.bag.filter(func(it): return int(it.id) != item_id)
	Economy.items_changed.emit()
	# 치명타 100% 주입(crit_rate per_level 1.0 → Lv 100 = +100%p) + 배율 Lv 100 = +50%p
	var cr := GameData.upgrade_def("crit_rate")
	var per0: float = cr.per_level
	cr.per_level = 1.0
	Economy.upgrades = {"crit_rate": 100, "crit_dmg": 100}
	Economy.upgrades_changed.emit()
	var plain_hits := await _hits(h, m, 5)
	_check(plain_hits.all(func(d): return is_equal_approx(d, base.atk * 2.0 * h._aura_mult())), "(G) 100% growth crit, no crit skill: every hit is base 150% + crit_dmg 50%p = x2.0",
		"hits=%s atk=%.1f" % [plain_hits, base.atk])
	var sk: Dictionary = plain.duplicate(true)
	sk.id = "crit_test"
	sk.skills = {"crit": [25.0, 200.0, 0.0]}
	var c = _add_hero_def(sk, 334)
	c.set_process(false)
	c.global_position = h.global_position  # 같은 표적 사거리 안
	var skill_hits := await _hits(c, m, 5)
	_check(skill_hits.all(func(d): return is_equal_approx(d, base.atk * 2.5 * c._aura_mult())), "(G) 100% crit with a crit skill: skill 200% + crit_dmg 50%p = x2.5, rolled once (never x5)",
		"hits=%s" % [skill_hits])
	# 확률 결합: 스킬 60% + 성장 40%(per_level 0.4) = 100% — 둘 중 하나만 세면 10번 중 빗나간다
	c._sk = {"crit": [60.0, 200.0, 0.0]}
	cr.per_level = 0.4
	Economy.upgrades_changed.emit()
	var sum_hits := await _hits(c, m, 10)
	_check(sum_hits.all(func(d): return is_equal_approx(d, base.atk * 2.5 * c._aura_mult())), "(G) crit chance = skill 60% + growth 40% = 100%: all 10 hits crit", "hits=%s" % [sum_hits])
	cr.per_level = per0
	# 병사: 공격·HP %, 공격 간격 ÷, 이동 × — 만든 뒤 성장이 바뀌어도 곧바로
	Economy.upgrades = {}
	Economy.upgrades_changed.emit()
	var home: Vector3 = Formation.soldier_spots([{"type": "infantry", "tier": 1}])[0]
	var s = SoldierScript.new()
	s.setup("infantry", 1, 0, 0, home, _main.castle)
	_main.add_child(s)
	s.set_process(false)
	s._rise = 0.0  # 등장 연출 생략
	var sb := GameData.soldier_stats("infantry", 1)
	Economy.upgrades = {"atk": 200, "hp": 200, "aspd": 100, "mspd": 80}
	Economy.upgrades_changed.emit()
	s._target = null
	s.global_position = home
	s._path.assign([home + Vector3(0, 0, -3.0)])
	s._process(0.1)  # 경로 한 점 → 걷는다
	var s_walk: float = home.distance_to(s.global_position)
	s._path.clear()
	s._target = m
	s._attack()
	_check(is_equal_approx(s.atk, sb.atk * 2.0) and is_equal_approx(s.hp_max, sb.hp * 2.0) and is_equal_approx(s.hp, s.hp_max) and is_equal_approx(s._atk_cd, sb.atk_interval / 1.25)
		and is_equal_approx(s_walk, sb.speed * 1.2 * 0.1), "(G) soldiers take growth at once too: atk/HP x2, attack interval / 1.25, walk x1.2",
		"atk=%.1f hp=%.1f/%.1f cd=%.3f walk=%.3f" % [s.atk, s.hp, s.hp_max, s._atk_cd, s_walk])
	# 병사 치명타(개정 20 §3: 모든 아군 공격의 기본 치명타): crit_rate 100% 주입 → 타격마다 150% + crit_dmg 50%p = x2.0, 치명타 숫자
	cr.per_level = 1.0
	Economy.upgrades = {"crit_rate": 100, "crit_dmg": 100}
	Economy.upgrades_changed.emit()
	s.global_position = _flat(m.global_position) - out * 0.5
	var dn = DamageNumbersScript.current
	var s_hits := []
	var s_kinds := []
	for i in 5:
		var d0 := _dmg(m)
		dn._list.clear()
		s._target = m
		s._attack()
		s._release()  # 근접 타격 순간
		s_hits.append(_dmg(m) - d0)
		s_kinds.append_array(dn._list.map(func(e): return e.kind))
	cr.per_level = per0
	_check(s_hits.all(func(d): return is_equal_approx(d, sb.atk * 2.0)) and s_kinds.size() == 5 and s_kinds.all(func(k): return k == DamageNumbersScript.Kind.CRIT),
		"(G) a soldier crits with growth crit_rate 100%: every hit x2.0 (base 150% + crit_dmg 50%p) with a crit number", "hits=%s kinds=%s atk=%.1f" % [s_hits, s_kinds, sb.atk])
	s.queue_free()
	Economy.upgrades = {}
	Economy.upgrades_changed.emit()
	_remove_hero(h)
	_remove_hero(c)
	_clear_monsters()
	for x in get_tree().get_nodes_in_group("heroes"):
		x.set_process(true)
	GameState.mode = GameState.Mode.IDLE
	GameState.refill()
	await _frames(2)


## (RS) 개정 24 연구의 전투 반영. 실제 경로: 끝난 연구(research_current)를 Economy._process가 완료 → research_changed·research_done →
##     영웅·병사 refresh_stats(곧바로, HP 비율 유지), main → GameState.apply_levels(true)(성·성문 최대 HP, 지금 HP는 같은 비율).
##     영웅 공격·HP %(같은 효과끼리 더함, 성장과 곱), 비전 연구(스킬 피해 %), 병종 %·정예 %, 성벽 보강. 연구소 레벨만으로는 영웅 공격이 그대로다.
func _research_cases() -> void:
	_clear_monsters()
	GameState.mode = GameState.Mode.STAGE  # 피해·HP가 들어가게
	GameState.refill()
	await _frames(1)
	for x in get_tree().get_nodes_in_group("heroes"):
		x.set_process(false)
	var plain: Dictionary = GameData.hero("hans").duplicate(true)
	plain.id = "research_test"  # 장비 없음
	plain.skills = {}
	var h = _add_hero_def(plain, 337)
	h.set_process(false)
	var base := GameData.hero_stats(plain, 1, 0)
	var m = _still("epic_boss", _flat(h.global_position) + Formation.SIDE_DIR[h.side] * 1.2)
	m.hp_max = 1.0e6
	m.hp = m.hp_max
	await _frames(1)
	# 연구소 레벨만 올리면(연구 없음) 영웅 공격은 그대로
	var lab0: int = Economy.levels.get("lab", 1)
	Economy.levels["lab"] = 20
	Economy.changed.emit()
	h.refresh_stats()
	_check(is_equal_approx(h.atk, base.atk) and is_equal_approx(h.hp_max, base.hp), "(RS) lab Lv 20 alone does not raise hero attack (rev 24)",
		"atk=%.2f base=%.2f" % [h.atk, base.atk])
	Economy.levels["lab"] = lab0
	# 무기 연마 5(+15%) + 전설의 무기 2(+8%) = +23%, 갑옷 단련 Lv 3 → 4 완료(+12%): 끝난 연구를 게으른 완료가 처리한다
	h.take_damage(h.hp_max / 2.0)
	Economy.research_levels = {"hero_weapon": 5, "legend_weapon": 2, "hero_armor": 3}
	Economy.research_current = {"id": "hero_armor", "finish": Economy.time_now() - 1.0}
	await _frames(2)
	h._target = m
	await _attack_now(h)
	_check(Economy.research_level("hero_armor") == 4 and Economy.research_current.is_empty() and is_equal_approx(h.atk, base.atk * 1.23) and is_equal_approx(h.hp_max, base.hp * 1.12)
		and is_equal_approx(h.hp, base.hp * 1.12 / 2.0) and is_equal_approx(_dmg(m), base.atk * 1.23 * h._aura_mult()),
		"(RS) research done: hero attack +23% (weapon 5 x 3 + legend 2 x 4, the hit too), HP +12% keeping the HP ratio",
		"armor=%d atk=%.2f hp=%.1f/%.1f dmg=%.2f base=%s" % [Economy.research_level("hero_armor"), h.atk, h.hp, h.hp_max, _dmg(m), base])
	Economy.upgrades = {"atk": 200}  # 성장 +100%와 곱
	Economy.upgrades_changed.emit()
	_check(is_equal_approx(h.atk, base.atk * 2.0 * 1.23), "(RS) research multiplies with growth: atk x2 x1.23", "atk=%.2f" % h.atk)
	Economy.upgrades = {}
	Economy.upgrades_changed.emit()
	# 비전 연구 5(+20%): 따로 들어가는 스킬 피해(폭발)
	h._sk = {"aoe_blast": [5.0, 3.0, 200.0]}
	var d0 := _dmg(m)
	h._blast(m.global_position)
	var blast0 := _dmg(m) - d0
	Economy.research_levels["arcana"] = 5
	Economy.research_changed.emit()
	d0 = _dmg(m)
	h._blast(m.global_position)
	var blast1 := _dmg(m) - d0
	_check(is_equal_approx(blast0, h.atk * h._aura_mult() * 2.0) and is_equal_approx(blast1, blast0 * 1.2), "(RS) arcana +20%: skill damage (aoe blast) x1.2",
		"blast %.2f -> %.2f" % [blast0, blast1])
	h._sk = {}
	# 병사: 보병 훈련 10(+30%) + 정예 전술 2(+6%) = 보병 x1.36, 궁병은 정예만 x1.06 — 만든 뒤 연구가 바뀌어도 곧바로
	var spots: Array = Formation.soldier_spots([{"type": "infantry", "tier": 1}, {"type": "archer", "tier": 1}])
	var inf = SoldierScript.new()
	inf.setup("infantry", 1, 0, 0, spots[0], _main.castle)
	_main.add_child(inf)
	var arc = SoldierScript.new()
	arc.setup("archer", 1, 0, 0, spots[1], _main.castle)
	_main.add_child(arc)
	for s in [inf, arc]:
		s.set_process(false)
		s._rise = 0.0
	var ib := GameData.soldier_stats("infantry", 1)
	var ab := GameData.soldier_stats("archer", 1)
	Economy.research_levels["inf_drill"] = 10
	Economy.research_levels["elite"] = 2
	Economy.research_changed.emit()
	_check(is_equal_approx(inf.atk, ib.atk * 1.36) and is_equal_approx(inf.hp_max, ib.hp * 1.36) and is_equal_approx(inf.hp, inf.hp_max)
		and is_equal_approx(arc.atk, ab.atk * 1.06) and is_equal_approx(arc.hp_max, ab.hp * 1.06),
		"(RS) soldier research: infantry +30% + elite +6% = x1.36 atk/HP, archers only the elite x1.06",
		"inf atk=%.2f hp=%.1f arc atk=%.2f" % [inf.atk, inf.hp_max, arc.atk])
	inf.global_position = _flat(m.global_position) - Formation.SIDE_DIR[h.side] * 0.5
	d0 = _dmg(m)
	inf._target = m
	inf._attack()
	inf._release()
	_check(is_equal_approx(_dmg(m) - d0, ib.atk * 1.36), "(RS) the infantry hits for its research attack", "dmg=%.2f" % (_dmg(m) - d0))
	inf.queue_free()
	arc.queue_free()
	# 성벽 보강 Lv 1 → 2 완료(+10%): 성 최대 HP가 오르고 지금 HP는 같은 비율
	Economy.research_levels = {"wall_fort": 1}
	Economy.research_changed.emit()
	GameState.apply_levels(true)
	var c_base := GameData.castle_hp_max(GameState.building_level("keep"))
	GameState.castle_hp = GameState.castle_hp_max * 0.5
	Economy.research_current = {"id": "wall_fort", "finish": Economy.time_now() - 1.0}
	await _frames(2)
	_check(Economy.research_level("wall_fort") == 2 and is_equal_approx(GameState.castle_hp_max, c_base * 1.10) and is_equal_approx(GameState.castle_hp, c_base * 1.10 * 0.5),
		"(RS) wall reinforcement Lv 2 done: castle max HP x1.10, current HP the same ratio (half)",
		"max=%.1f hp=%.1f base=%.1f" % [GameState.castle_hp_max, GameState.castle_hp, c_base])
	Economy.research_levels = {}
	Economy.research_current = {}
	Economy.research_changed.emit()
	_remove_hero(h)
	_clear_monsters()
	for x in get_tree().get_nodes_in_group("heroes"):
		x.set_process(true)
	GameState.mode = GameState.Mode.IDLE
	GameState.refill()
	await _frames(2)


## (BS) 거인 사냥(boss_slayer)은 모든 보스에게: 성 대보스·왕고블린·데스나이트(monster.is_boss ← GameData.BOSS_KINDS), 졸개·고블린은 아니다.
##      같은 영웅(스킬은 boss_slayer 50%만, 성장 없음 — 치명타 0)이 종류마다 한 대씩 친다.
func _boss_slayer_case() -> void:
	_clear_monsters()
	Economy.upgrades = {}
	Economy.upgrades_changed.emit()
	await _frames(1)
	for x in get_tree().get_nodes_in_group("heroes"):
		x.set_process(false)
	var def: Dictionary = GameData.hero("hans").duplicate(true)
	def.id = "slayer_test"
	var h = _add_hero_def(def, 335)
	h.set_process(false)
	h._sk = {"boss_slayer": [50.0, 0.0, 0.0]}
	var at: Vector3 = _flat(h.global_position) + Formation.SIDE_DIR[h.side] * 1.2
	var rows := {}
	for r in GameData.dungeon_enemies("gold", 1) + GameData.dungeon_enemies("equip", 1):
		rows[r.kind] = r
	var hits := {}
	var flags := {}
	for kind in ["grunt", "epic_boss", "goblin", "goblin_king", "death_knight"]:
		var m
		if rows.has(kind):
			m = (preload("res://scripts/death_knight.gd") if kind == "death_knight" else MonsterScript).new()
			m.setup_arena(rows[kind])
			_main.add_child(m)
			m.global_position = at
			m.set_process(false)
		else:
			m = _still(kind, at)
		m.hp_max = 1.0e6
		m.hp = m.hp_max
		h._target = m
		await _attack_now(h)
		hits[kind] = _dmg(m)
		flags[kind] = m.is_boss
		m.queue_free()
		await _frames(1)
	var plain: float = hits.grunt
	_check(plain > 0.0 and is_equal_approx(hits.goblin, plain) and ["epic_boss", "goblin_king", "death_knight"].all(func(k): return is_equal_approx(hits[k], plain / 1.1 * 1.5))
		and flags == {"grunt": false, "epic_boss": true, "goblin": false, "goblin_king": true, "death_knight": true},
		"(BS) boss_slayer +50% hits every boss (epic boss, goblin king, death knight via is_boss), normal enemies (grunt, goblin) get a fifth (+10%)", "hits=%s is_boss=%s" % [hits, flags])
	_remove_hero(h)
	for x in get_tree().get_nodes_in_group("heroes"):
		x.set_process(true)
	await _frames(1)


## 영웅이 바깥쪽으로 dt초 걷는 거리(경로 한 점, 처리는 직접 부른다). 걷고 나면 제자리로 되돌린다.
func _walk(h, dt: float) -> float:
	var p0: Vector3 = h.global_position
	h._path.clear()
	h._path.append(p0 + Formation.SIDE_DIR[h.side] * 5.0)
	h._process(dt)
	var d := p0.distance_to(h.global_position)
	h._path.clear()
	h.global_position = p0
	return d


## 영웅 h의 공격 n번(_attack_now) 각각의 피해.
func _hits(h, m, n: int) -> Array:
	var out := []
	for i in n:
		var before := _dmg(m)
		h._target = m
		await _attack_now(h)
		out.append(_dmg(m) - before)
	return out


## (DG) 개정 18 던전(전투는 hero.gd·monster.gd 아레나): 성 월드는 트리 밖(GameState 정지), 방치 모드여도 아레나 영웅은 피해를 받는다.
##  DG1 골드 던전 6명 대 고블린 10 → 5초 뒤 고블린 5 + 왕(16) — 서로 싸우고, 전멸이면 최소 시간 뒤 승리(+4,000·열쇠 −1).
##  DG2 패배: 출전 영웅 전멸 / 제한 시간 — 열쇠는 그대로. DG3 데스나이트 휩쓸기(반경 3 m 공격 × 1.5)·돌진(가장 먼 영웅 기절).
##  DG4 장비를 끼면 아레나 영웅 능력치 = 기본 × 배율 + 장비, 실제 타격 피해도 그 공격력.
func _dungeon_cases() -> void:
	_clear_monsters()
	Economy.debug_win_on = false
	for id in ["arteon", "ignis", "kyle"]:
		Economy.heroes[id] = maxi(1, int(Economy.heroes.get(id, 0)))
	var keys0: int = Economy.dungeon_state("gold").keys
	var gold0: int = Economy.gold_tenths
	var castle_heroes := get_tree().get_nodes_in_group("heroes").size()
	var d = await _enter_dungeon("gold", Economy.default_party("gold"))
	await _frames(2)
	var goblins := _arena_monsters()
	_check(d != null and not _main.is_inside_tree() and GameState.process_mode == Node.PROCESS_MODE_DISABLED and get_tree().get_nodes_in_group("heroes") == d.heroes
		and d.heroes.size() == 6 and goblins.size() == 10 and goblins.all(func(m): return m.kind == "goblin") and d.enemies_left() == 16 and castle_heroes > 0,
		"(DG1) gold dungeon: the castle world leaves the tree (GameState paused), 6 arena heroes vs 10 goblins first (16 in all)",
		"heroes=%d goblins=%d left=%d" % [get_tree().get_nodes_in_group("heroes").size(), goblins.size(), d.enemies_left() if d != null else -1])
	_check(not goblins.is_empty() and goblins.all(func(m): return m.speed() > 0.0 and m.speed() == float(m._stats.speed)),
		"(DG1) arena enemies walk at their dungeon row speed (no stage speed mult, r22)", str(goblins.map(func(m): return m.speed())))
	await _wait_until(func(): return d.clock >= 5.3, 10.0)
	var all := _arena_monsters()
	var dead: int = 16 - d.enemies_left()
	var hurt_m: int = all.filter(func(m): return m.hp < m.hp_max).size() + dead
	var hurt_h: int = d.heroes.filter(func(h): return h.hp < h.hp_max).size()
	_check(d.boss != null and d.boss.kind == "goblin_king" and is_equal_approx(d.boss.hp_max, 1500.0) and all.size() + dead == 16 and hurt_m > 0 and hurt_h > 0
		and d.phase == d.Phase.FIGHT, "(DG1) after 5 s the late 5 goblins and the goblin king arrive; heroes and goblins hurt each other (idle mode does not shield arena heroes)",
		"boss=%s alive=%d dead=%d hurt monsters=%d heroes=%d" % [d.boss, all.size(), dead, hurt_m, hurt_h])
	for m in _arena_monsters():
		m.take_damage(m.hp)
	await _frames(2)
	_check(d.phase == d.Phase.WON and Economy.dungeon_state("gold").keys == keys0, "(DG1) all enemies dead = victory, held until the minimum time (no finish yet)", "phase=%d" % d.phase)
	Economy.current_run.started_at = float(Economy.current_run.started_at) - 15.0  # 실제 경과도 최소 시간만큼
	d.clock = GameData.min_clear_sec("gold") - 0.01
	await _wait_until(func(): return d.phase == d.Phase.RESULT, 3.0)
	_check(d.phase == d.Phase.RESULT and d.result.win and Economy.gold_tenths == gold0 + 40000 and Economy.dungeon_state("gold").keys == keys0 - 1
		and Economy.dungeon_state("gold").best_level >= 1 and d.hud.result_layer.visible, "(DG1) at the minimum time the run finishes as a win: +4,000 gold, one key spent, result screen",
		"phase=%d result=%s gold %d -> %d keys=%d" % [d.phase, d.result, gold0, Economy.gold_tenths, Economy.dungeon_state("gold").keys])
	# DG2 패배: 영웅 전멸
	d = await _enter_dungeon("gold", Economy.default_party("gold"))
	await _frames(2)
	for h in d.heroes:
		while h.is_alive():  # 회피(dodge) 스킬은 무작위로 한 대를 비킨다 — 쓰러질 때까지
			h.take_damage(h.hp_max * 100.0)
	await _frames(2)
	_check(d.phase == d.Phase.RESULT and not d.result.win and d.result.rewards.is_empty() and Economy.dungeon_state("gold").keys == keys0 - 1 and Economy.current_run.is_empty(),
		"(DG2) every hero down = defeat: the run closes, no reward, keys unchanged", "phase=%d result=%s" % [d.phase, d.result])
	# DG2 패배: 제한 시간
	d = await _enter_dungeon("gold", Economy.default_party("gold"))
	await _frames(2)
	d.clock = d.time_limit() - 0.01
	await _frames(3)
	_check(d.phase == d.Phase.RESULT and not d.result.win and d.heroes.any(func(h): return h.is_alive()) and Economy.dungeon_state("gold").keys == keys0 - 1,
		"(DG2) the time limit (120 s) = defeat even with heroes alive", "phase=%d result=%s" % [d.phase, d.result])
	await _dk_cases()
	d = _main._dungeon
	d.leave()
	await _frames(3)
	_check(_main.is_inside_tree() and _main._dungeon == null and GameState.process_mode == Node.PROCESS_MODE_INHERIT and get_viewport().get_camera_3d() == _main.camera
		and get_tree().get_nodes_in_group("heroes").size() == castle_heroes, "(DG) [나가기] puts the castle world back (camera, GameState, castle heroes)", "")


## DG3·DG4: 장비 던전(한스·엘라·도릭·니나 — ★0이라 스킬 1만, 받는 피해를 바꾸는 스킬 없음). 영웅은 처리를 끄고 자리를 놓는다.
func _dk_cases() -> void:
	Economy.bag.append({"id": 9001, "slot": "top", "weapon_kind": null, "grade": "SR", "level": 5})
	Economy.bag.append({"id": 9002, "slot": "weapon", "weapon_kind": "sword", "grade": "R", "level": 3})
	Economy.bag.append({"id": 9003, "slot": "shoes", "weapon_kind": null, "grade": "N", "level": 1})
	var eq_ok: bool = Economy.equip("hans", "top", 9001) and Economy.equip("hans", "weapon", 9002) and Economy.equip("hans", "shoes", 9003)
	var d = await _enter_dungeon("equip", ["hans", "ella", "dorik", "nina"])
	await _frames(2)
	var dk = d.boss
	var hans = d.heroes[0]
	var bare := GameData.hero_stats(hans.def, Economy.level_of("hans"), Economy.promotion_of("hans"), {})
	var top := GameData.item_stats(Economy.item(9001))
	var sword := GameData.item_stats(Economy.item(9002))
	var shoes := GameData.item_stats(Economy.item(9003))
	_check(eq_ok and is_equal_approx(hans.hp_max, bare.hp + top.hp + shoes.hp) and is_equal_approx(hans.atk, bare.atk + sword.atk) and top.hp > 0 and sword.atk > 0,
		"(DG4) equipment adds to the arena hero: HP = base + top + shoes, attack = base + sword", "hp=%.1f want %.1f atk=%.1f want %.1f" % [hans.hp_max, bare.hp + top.hp + shoes.hp, hans.atk, bare.atk + sword.atk])
	# 신발 이동속도 +3%: 성장 이동속도와 같은 한 곳(hero.refresh_stats)에서 — 아레나 영웅도 걷는 거리 × (1 + 성장 + 0.03)
	var want_walk: float = float(hans.def.speed) * (1.0 + Economy.upgrade_bonus().mspd_pct + shoes.speed_pct / 100.0) * 0.1
	var walked := _walk(hans, 0.1)
	_check(shoes.speed_pct == 3.0 and is_equal_approx(walked, want_walk), "(DG4) shoes +3% move speed reach the arena hero (walk x1.03 with no growth)",
		"walked=%.4f want=%.4f speed=%.2f" % [walked, want_walk, float(hans.def.speed)])
	for h in d.heroes:
		h.set_process(false)
	dk.set_process(false)
	var p: Vector3 = dk.global_position
	hans.global_position = p + ArenaKit.RIGHT * 2.0
	hans.set_process(true)  # DG4: 한스 혼자 데스나이트를 친다(오라 없음)
	await _wait_until(func(): return dk.hp < dk.hp_max, 4.0)
	_check(is_equal_approx(dk.hp_max - dk.hp, hans.atk), "(DG4) and the real hit deals that attack", "dmg=%.1f atk=%.1f" % [dk.hp_max - dk.hp, hans.atk])
	hans.set_process(false)
	var spots := [ArenaKit.RIGHT * 2.0, ArenaKit.RIGHT * -2.8, ArenaKit.DOWN * 6.0, ArenaKit.DOWN * 12.0]
	for i in 4:
		d.heroes[i].global_position = p + spots[i]
		d.heroes[i].hp = d.heroes[i].hp_max
	dk._atk_cd = 100.0  # 일반 공격 빼고 패턴만
	dk.charge_cd = 100.0
	dk.sweep_cd = 0.001
	dk.set_process(true)
	await _frames(2)
	dk.set_process(false)
	var lost: Array = d.heroes.map(func(h): return h.hp_max - h.hp)
	var sweep: float = dk.atk * 1.5
	_check(dk.sweeps == 1 and is_equal_approx(lost[0], sweep) and is_equal_approx(lost[1], sweep) and lost[2] == 0.0 and lost[3] == 0.0 and is_equal_approx(dk.atk, 60.0),
		"(DG3) death knight sweep: heroes within 3 m take attack x1.5 (90), farther ones nothing", "sweeps=%d lost=%s" % [dk.sweeps, lost])
	for h in d.heroes:
		h.hp = h.hp_max
	dk.sweep_cd = 100.0
	dk.charge_cd = 0.001
	dk.set_process(true)
	await _wait_until(func(): return dk.charges == 1 and not dk.is_charging(), 3.0)
	dk.set_process(false)
	var far = d.heroes[3]
	_check(dk.charges == 1 and far.is_stunned() and is_equal_approx(far.hp_max - far.hp, dk.atk) and d.heroes.slice(0, 3).all(func(h): return not h.is_stunned())
		and Formation.flat_distance(dk.global_position, far.global_position) <= float(dk._stats.range) + 0.01,
		"(DG3) death knight charge: runs to the farthest hero, hits it and stuns it (others not stunned)",
		"charges=%d stunned=%s lost=%.1f dist=%.2f" % [dk.charges, d.heroes.map(func(h): return h.is_stunned()), far.hp_max - far.hp, Formation.flat_distance(dk.global_position, far.global_position)])
	var stun0: float = far._stun_t
	far.set_process(true)
	await _frames(3)
	far.set_process(false)
	_check(far._stun_t < stun0 and far._attacks == 0, "(DG3) a stunned hero does not act while the stun runs down", "stun %.2f -> %.2f" % [stun0, far._stun_t])
	Economy.unequip("hans", "top")
	Economy.unequip("hans", "weapon")
	Economy.unequip("hans", "shoes")


## 던전 시작(오프라인) → main이 다음 프레임에 장면을 바꾼다. 새 던전 장면(실패면 null).
func _enter_dungeon(type: String, party: Array):
	var before: int = _main._dungeon.get_instance_id() if _main._dungeon != null else 0
	Economy.start_dungeon(type, 1, party)
	await _wait_until(func(): return _main._dungeon != null and _main._dungeon.get_instance_id() != before and _main._dungeon.is_inside_tree(), 2.0)
	return _main._dungeon if _main._dungeon != null and _main._dungeon.get_instance_id() != before else null


func _arena_monsters() -> Array:
	return get_tree().get_nodes_in_group("monsters").filter(func(m): return m.is_alive())


# --- (CR) 겹침 해소(crowd.gd) ---
const Crowd := preload("res://scripts/crowd.gd")
const CROWD_TOL := 0.05  # 겹침 허용: 반지름 합의 5%


## (CR) 유닛은 바닥을 차지한다: 성문에 몰린 무리는 겹치지 않고 문 앞에 퍼져 서고, 밀려서 성벽·닫힌 성문을 넘지 않는다. 성벽 위 궁수는
##      성벽 길 안(중심선 ± 0.55 m)에서만 밀리고 제자리로 돌아간다. 근접 영웅의 피해 속도는 해소를 끈 것과 같다(±10%). 던전 아레나도 겹치지 않는다.
##      해소를 한 번 끄면 같은 겹침 검사가 실패한다(검사가 문다).
func _crowd_cases() -> void:
	_clear_monsters()
	var mode0: int = GameState.mode
	GameState.mode = GameState.Mode.STAGE
	GameState.refill()
	await _frames(1)
	var crowd = _main.get_children().filter(func(c): return c.get_script() == Crowd)[0]
	var heroes := get_tree().get_nodes_in_group("heroes")
	for h in heroes:  # 지상 영웅은 멀리 치워 둔다 — 성문 앞 무리가 영웅이 아니라 성문을 친다(성벽 위 영웅은 그대로 쏜다)
		if not h.is_on_wall():
			h.set_process(false)
			h.global_position = Vector3(-90.0 + 3.0 * h.index, 0, 90.0)
	var gate0: float = GameState.gate_hp[1]
	var r: Dictionary = await _gate_crowd(40, 3.0)
	var ms: Array = r.ms
	var standing: int = ms.filter(func(m): return not m._walking).size()
	var lateral: Array = ms.map(func(m): return Formation.perp(1).dot(m.global_position))
	print("crowd: %d units at the east gate, worst overlap %.1f%%, resolve avg %.2f ms, max %.2f ms per frame" % [r.units, r.worst * 100.0, r.avg_ms, r.max_ms])
	_check(r.worst <= CROWD_TOL, "(CR) after 3 s of 40 grunts on the east gate no two units overlap by more than 5% of their radius sum",
		"worst %.3f %s" % [r.worst, r.what])
	_check(not r.crossed and GameState.gate_hp[1] == gate0 and lateral.max() - lateral.min() > Balance.GATE_W, "(CR) the crowd stays outside the closed gate and spreads wider than the gate (a blob, not a stack)",
		"crossed=%s gate %.0f -> %.0f spread %.1f m" % [r.crossed, gate0, GameState.gate_hp[1], lateral.max() - lateral.min()])
	_check(standing >= 8, "(CR) many of them stand and strike at once along the gate (not one stack)", "standing %d of %d" % [standing, ms.size()])
	crowd.enabled = false
	var off: Dictionary = await _gate_crowd(40, 3.0)
	crowd.enabled = true
	_check(off.worst > CROWD_TOL, "(CR) with the resolver switched off the same check fails (the overlap check bites)", "worst %.3f" % off.worst)
	_clear_monsters()
	await _frames(1)

	# 성벽 위: 동 성벽 원거리 영웅 셋을 한 점에 겹쳐 놓는다 → 성벽 길 안에서만 벌어지고(높이 그대로, 중심선 ± 0.55 m) 서로 비켜 저마다 자리로 돌아간다
	var wall_hs := []
	for k in 3:
		wall_hs.append(_add_hero(["nina", "mira", "echo"][k], 401 + 4 * k))  # 면 1(동), 성벽 위 빈 자리
	await _frames(1)
	var spot: Vector3 = wall_hs[0].stand_position()
	var depth: float = Formation.SIDE_DIR[1].dot(spot)
	for k in wall_hs.size():
		wall_hs[k]._path.clear()
		wall_hs[k].global_position = spot + Formation.perp(1) * 0.01 * k
	var on_wall := true
	var t := 0.0
	while t < 6.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		for h in wall_hs:
			var p: Vector3 = h.global_position
			on_wall = on_wall and absf(p.y - Balance.WALL_H) < 0.01 and absf(Formation.SIDE_DIR[1].dot(p) - depth) <= Formation.WALK_HALF + 0.01
	var home := wall_hs.all(func(h): return h.global_position.distance_to(h.stand_position()) < 0.06 and h.is_on_wall())
	_check(wall_hs.all(func(h): return h.post == Formation.POST_WALL and h.side == 1) and on_wall and home,
		"(CR) wall-top archers piled on one spot stay on the wall walk (height kept, center line +-0.55 m) and get past each other to their own posts",
		"on_wall=%s home=%s pos=%s" % [on_wall, home, wall_hs.map(func(h): return h.global_position)])
	for h in wall_hs:
		_remove_hero(h)
	await _frames(1)

	# 근접 영웅의 피해 속도: 해소를 켜도(무리가 둘러싸도) 끈 것과 ±10% 안
	var on_dmg: float = await _melee_rate(crowd, true)
	var off_dmg: float = await _melee_rate(crowd, false)
	_check(on_dmg > 0.0 and absf(on_dmg / off_dmg - 1.0) <= 0.1, "(CR) a melee hero ringed by grunts deals damage at the same rate with the resolver on (+-10%)",
		"on %.0f off %.0f" % [on_dmg, off_dmg])
	for h in heroes:
		if is_instance_valid(h):
			h.set_process(true)
			h.reset()
	_clear_monsters()
	await _frames(1)

	# 던전 아레나(골드): 영웅 6과 고블린이 싸우는 동안 겹치지 않는다
	var d = await _enter_dungeon("gold", Economy.default_party("gold"))
	var worst := 0.0
	var what := ""
	t = 0.0
	while d != null and t < 6.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > 0.5:
			var o: Array = _overlap(d)
			if o[0] > worst:
				worst = o[0]
				what = o[1]
	var fought: bool = d != null and d.heroes.any(func(h): return h.hp < h.hp_max)
	_check(d != null and fought and worst <= CROWD_TOL, "(CR) dungeon arena: heroes and goblins fight without overlapping (6 s)", "fought=%s worst %.3f %s" % [fought, worst, what])
	if d != null:
		d.give_up()
		await _wait_until(func(): return _main.is_inside_tree(), 2.0)
		await _frames(2)
	GameState.mode = mode0


## 동(1) 성문 앞 3~9 m에 grunt n마리(공격 0·HP 큼 — 성문이 안 부서지고 안 죽는다)를 놓고 sec초. 끝의 가장 큰 겹침, 몬스터, 성 안에 든 적이 있었는지.
func _gate_crowd(n: int, sec: float) -> Dictionary:
	_clear_monsters()
	await _frames(1)
	var ms := []
	for i in n:
		var p: Vector3 = Formation.gate_target(_half, 1) + Formation.SIDE_DIR[1] * (3.0 + (i / 8) * 1.5) + Formation.perp(1) * ((i % 8) - 3.5) * 1.5
		var m = _spawn("grunt", 1, p)
		m.atk = 0.0
		m.hp_max = 1.0e6
		m.hp = 1.0e6
		ms.append(m)
	var crowd = _main.get_children().filter(func(c): return c.get_script() == Crowd)[0]
	var crossed := false
	var t := 0.0
	var usec := []
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()
		crossed = crossed or ms.any(func(m): return Formation.is_inside(_half, m.global_position))
		usec.append(crowd.last_usec)
	var o: Array = _overlap(_main)
	return {"worst": o[0], "what": o[1], "units": o[2], "ms": ms, "crossed": crossed,
		"avg_ms": usec.reduce(func(a, b): return a + b, 0) / 1000.0 / usec.size(), "max_ms": usec.max() / 1000.0}


## parent 아래 살아 있는 유닛(같은 층) 쌍 중 가장 큰 겹침 / 반지름 합. [비율, 그 쌍, 유닛 수]
func _overlap(parent) -> Array:
	var us := get_tree().get_nodes_in_group("crowd").filter(func(u): return u.get_parent() == parent and u.is_alive() and Crowd.level(u.global_position.y) >= 0)
	var worst := 0.0
	var what := ""
	for i in us.size():
		for j in range(i + 1, us.size()):
			var a = us[i]
			var b = us[j]
			if Crowd.level(a.global_position.y) != Crowd.level(b.global_position.y):
				continue
			var s: float = a.radius() + b.radius()
			var o: float = (s - Formation.flat_distance(a.global_position, b.global_position)) / s
			if o > worst:
				worst = o
				what = "%s@%s / %s@%s" % [a.name, _flat(a.global_position), b.name, _flat(b.global_position)]
	return [worst, what, us.size()]


## 북동 벌판의 근접 영웅(한스, 스킬 1 = 흡혈 — 피해는 공격력 그대로) 둘레 3.5 m에 grunt 8(공격 0·HP 큼). 첫 타격부터 7.6초(0.8초 간격 10번) 동안 준 피해.
func _melee_rate(crowd, on: bool) -> float:
	crowd.enabled = on
	_clear_monsters()
	await _frames(1)
	var h = _add_hero("hans", 500)
	await _frames(1)
	var outer := _half + Balance.WALL_T
	var p := Vector3(outer + 12.0, 0, -(outer + 22.0))
	h.move_to_point(p)
	h._path.clear()
	h.global_position = p
	var ms := []
	for k in 8:
		var m = _spawn("grunt", 0, p + Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 8.0) * 3.5)
		m.atk = 0.0
		m.hp_max = 1.0e6
		m.hp = 1.0e6
		ms.append(m)
	var dealt := func(): return ms.reduce(func(acc, m): return acc + _dmg(m), 0.0)
	await _wait_until(func(): return dealt.call() > 0.0, 3.0)
	await _seconds(7.6)
	var total: float = dealt.call()
	_remove_hero(h)
	_clear_monsters()
	crowd.enabled = true
	await _frames(1)
	return total

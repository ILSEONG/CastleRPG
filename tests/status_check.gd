extends Node
## 헤드리스 상태 체크(스킬 100종 몬스터 상태): 실제 main 씬(오토로드 포함)에서 monster.gd의 지속 피해(burn·bleed·curse)·freeze·root·
## vulnerable·weaken·knockback·taunt·has_status·is_controlled와 상태 이펙트(FxStatus — 상태마다 노드 하나, 끝나거나 죽으면 지움, 상한)를 확인한다.
## 실행: ./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/status_check.tscn
## 오토로드를 쓰므로 tests/run_tests.gd(-s)에서 preload 금지. 스포너를 멈추고 몬스터를 직접 놓는다(대부분 처리를 끄고 _process를 직접 흘린다).

const Balance := preload("res://scripts/balance.gd")
const GameData := preload("res://scripts/game_data.gd")
const Formation := preload("res://scripts/formation.gd")
const MonsterScript := preload("res://scripts/monster.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")
const HeroScript := preload("res://scripts/hero.gd")
const Fx := preload("res://scripts/fx.gd")
const FxStatus := preload("res://scripts/fx_status.gd")

const ALL_TAGS := ["slow", "stun", "poison", "burn", "bleed", "curse", "freeze", "root", "vulnerable", "weaken"]
const CONTROL_TAGS := ["slow", "stun", "freeze", "root"]

class ErrorCounter extends Logger:
	var count := 0
	func _log_error(_fn: String, _file: String, _line: int, _code: String, _why: String, _notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1

var _fails := 0
var _errors := ErrorCounter.new()
var _main
var _half := 0.0
var _far := Vector3.ZERO  # 어느 영웅에게서도 먼 성 밖 벌판(모서리 너머)


func _ready() -> void:
	OS.add_logger(_errors)
	Economy.save_path = ""  # 실제 저장 파일을 건드리지 않는다
	Fever.save_path = ""
	Fever.reset()
	GameData._config.fx_shake = "0"
	Economy.reset(Time.get_unix_time_from_system())
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(5)
	for c in _main.get_children():
		if c.get_script() == SpawnerScript:
			c.set_process(false)
	_clear_monsters()
	GameState.mode = GameState.Mode.STAGE  # 피해가 들어가는 모드(방치 모드는 무적)
	_half = _main.castle.half
	_far = Vector3(_half + 40.0, 0, -(_half + 40.0))
	await _frames(1)
	await _run()
	if _errors.count > 0:
		print("STATUS SCRIPT ERRORS %d" % _errors.count)
	_fails += _errors.count
	if _fails > 0:
		print("STATUS FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("STATUS ALL PASSED")
		get_tree().quit(0)


func _run() -> void:
	await _dot_cases()
	await _vulnerable_cases()
	await _weaken_cases()
	await _freeze_cases()
	await _root_cases()
	await _knockback_cases()
	await _taunt_cases()
	await _flag_cases()
	await _death_and_cap_cases()
	await _perf_case()


## (1) 지속 피해: 태그마다 따로(합계 = dps × 초), 다시 걸면 dps·시간 모두 큰 쪽, 태그마다 이펙트 하나, 끝나면 지운다. 모르는 태그 무시.
func _dot_cases() -> void:
	var m = _still("epic_boss", _far)
	await _frames(1)
	m.apply_dot("burn", 10.0, 0.5)
	m.apply_dot("bleed", 4.0, 0.3)
	m.apply_dot("frost", 99.0, 1.0)  # 모르는 태그
	var fb = m.status_fx("burn")
	var fl = m.status_fx("bleed")
	_check(fb != null and fl != null and fb.get_meta("fx", "") == "burn" and fl.get_meta("fx", "") == "bleed" and m.status_fx("curse") == null
		and not m._status.has("frost") and _dmg(m) == 0.0,
		"(1) burn and bleed each get their own visual; an unknown tag does nothing", "status=%s dmg=%.2f" % [m._status.keys(), _dmg(m)])
	_check(m.has_status("burn") and m.has_status("bleed") and not m.has_status("curse"), "(1) has_status reports the active DoT tags", "")
	for i in 4:
		m._process(0.1)
	_check(is_equal_approx(_dmg(m), 10.0 * 0.4 + 4.0 * 0.3), "(1) burn and bleed tick independently, last tick only for the time left", "dmg=%.3f want 5.2" % _dmg(m))
	_check(m.has_status("burn") and not m.has_status("bleed") and m.status_fx("bleed") == null and m.status_fx("burn") == fb,
		"(1) the bleed visual goes when bleed ends, burn keeps its node", "status=%s" % [m._status.keys()])
	var before := _dmg(m)
	m.apply_dot("burn", 5.0, 0.05)  # 약하고 짧은 재적용: dps 10, 남은 0.1초 그대로
	m._process(0.2)
	_check(is_equal_approx(_dmg(m) - before, 1.0) and not m.has_status("burn"), "(1) a weaker shorter re-apply keeps the higher dps and the longer time",
		"dealt %.3f want 1.0" % (_dmg(m) - before))
	m.apply_dot("burn", 10.0, 1.0)
	m.apply_dot("burn", 20.0, 0.3)  # 더 센 재적용: dps 20, 남은 1.0초
	m.apply_dot("curse", 2.0, 1.0)
	var burns: int = _fx_count(m, "burn")
	before = _dmg(m)
	m._process(0.5)
	_check(burns == 1 and is_equal_approx(_dmg(m) - before, 20.0 * 0.5 + 2.0 * 0.5), "(1) re-apply refreshes to the stronger dps with one visual; curse stacks alongside",
		"burn nodes=%d dealt %.3f want 11" % [burns, _dmg(m) - before])
	m._process(0.6)
	await _frames(1)
	_check(m._status.is_empty() and _fx_count(m, "") == 0 and not m.has_status("burn") and not m.has_status("curse"),
		"(1) all DoT visuals are freed once every DoT ends", "status=%s fx=%d" % [m._status.keys(), _fx_count(m, "")])
	var g = _still("grunt", _far + Vector3(3, 0, 0))
	await _frames(1)
	g.apply_dot("bleed", 1000.0, 1.0)
	g._process(0.1)
	g.apply_dot("bleed", 1.0, 1.0)  # 죽은 뒤에는 무시
	_check(not g.is_alive() and g._status.is_empty(), "(1) a DoT can kill; the corpse keeps no status visual and takes no new DoT", "alive=%s status=%s" % [g.is_alive(), g._status.keys()])
	await _clear()


## (2) vulnerable: 받는 피해 × (1 + pct/100)(지속 피해 포함), 더 약한 재적용은 pct를 낮추지 않는다, 끝나면 그대로.
func _vulnerable_cases() -> void:
	var m = _still("epic_boss", _far)
	await _frames(1)
	m.apply_vulnerable(50.0, 0.5)
	m.take_damage(10.0)
	var d1 := _dmg(m)
	m.apply_vulnerable(20.0, 0.2)
	m.take_damage(10.0)
	var d2 := _dmg(m) - d1
	var arrow = m.status_fx("vulnerable")
	_check(is_equal_approx(d1, 15.0) and is_equal_approx(d2, 15.0) and arrow != null and arrow.get_meta("fx", "") == "vulnerable",
		"(2) vulnerable 50% makes a 10 hit deal 15; a weaker re-apply keeps 50%", "first %.2f second %.2f" % [d1, d2])
	_check(arrow != null and arrow.global_position.y > m.bar_height(), "(2) the vulnerable marker floats above the head", "y=%.2f bar=%.2f" % [arrow.global_position.y if arrow else 0.0, m.bar_height()])
	m.apply_dot("curse", 10.0, 0.1)
	var b := _dmg(m)
	m._process(0.1)
	_check(is_equal_approx(_dmg(m) - b, 1.5), "(2) vulnerable also amplifies DoT damage", "dealt %.3f want 1.5" % (_dmg(m) - b))
	m._process(0.5)
	b = _dmg(m)
	m.take_damage(10.0)
	_check(is_equal_approx(_dmg(m) - b, 10.0) and not m.has_status("vulnerable") and m.status_fx("vulnerable") == null,
		"(2) after vulnerable ends damage is normal and the marker is gone", "dealt %.2f" % (_dmg(m) - b))
	await _clear()


## (3) weaken: 주는 피해(hit_damage) × (1 − pct/100) — 성문·성채·영웅 모두. 끝나면 원래대로.
func _weaken_cases() -> void:
	GameState.refill()
	await _frames(1)
	var m = _still("epic_boss", _far)
	await _frames(1)
	var atk: float = m.atk
	m.apply_weaken(40.0, 1.0)
	_check(is_equal_approx(m.hit_damage(), atk * 0.6) and m.status_fx("weaken") != null, "(3) weaken 40% makes the hit damage 60% of atk",
		"hit %.2f atk %.2f" % [m.hit_damage(), atk])
	var g0: float = GameState.gate_hp[0]
	m._swing_side = 0
	m._swing_at = m.global_position
	m._release()
	var c0: float = GameState.castle_hp
	m._swing_side = -1
	m._release()
	_check(is_equal_approx(g0 - GameState.gate_hp[0], atk * 0.6) and is_equal_approx(c0 - GameState.castle_hp, atk * 0.6),
		"(3) a weakened monster deals reduced damage to the gate and the keep", "gate -%.2f keep -%.2f want %.2f" % [g0 - GameState.gate_hp[0], c0 - GameState.castle_hp, atk * 0.6])
	# 영웅: 같은 영웅을 약화 중·아닐 때 한 번씩 쳐 비율을 본다(받는 쪽 피해 감소는 둘 다 같다)
	var hero = _heroes()[0]
	var hm = _still("epic_boss", _flat(hero.global_position) + Formation.SIDE_DIR[hero.side] * 1.2)
	await _frames(1)
	var hp0: float = hero.hp
	hm._swing_side = hm.AT_HERO
	hm._swing_hero = hero
	hm._release()
	var plain: float = hp0 - hero.hp
	hm.apply_weaken(50.0, 1.0)
	hp0 = hero.hp
	hm._swing_side = hm.AT_HERO
	hm._swing_hero = hero
	hm._release()
	var weak: float = hp0 - hero.hp
	_check(plain > 0.0 and is_equal_approx(weak, plain * 0.5), "(3) a weakened monster hits a hero for (1 - pct) of the normal damage", "plain %.2f weak %.2f" % [plain, weak])
	hero.hp = hero.hp_max
	m._process(1.1)
	_check(is_equal_approx(m.hit_damage(), atk) and not m.has_status("weaken") and m.status_fx("weaken") == null, "(3) after weaken ends the hit damage is back to atk",
		"hit %.2f" % m.hit_damage())
	GameState.refill()
	await _clear()


## (4) freeze: 기절로 친다(is_stunned), 이동·공격 멈춤 + 자세 멈춤(모델 처리 끔), 얼음 덩어리, 끝나면 다시 걷는다.
func _freeze_cases() -> void:
	var m = _spawn("grunt", _far)  # 처리 켬: 성문으로 걷는다
	await _seconds(0.3)
	m.apply_freeze(0.5)
	var p0: Vector3 = m.global_position
	var ice = m.status_fx("freeze")
	await _seconds(0.3)
	var still: float = Formation.flat_distance(p0, m.global_position)
	var posed: bool = not m._model.is_processing()
	_check(m.is_stunned() and m.has_status("freeze") and not m.has_status("stun") and m.is_controlled() and ice != null and ice.get_meta("fx", "") == "freeze",
		"(4) freeze counts as stunned and shows the ice block", "status=%s" % [m._status.keys()])
	_check(still < 0.01 and posed, "(4) a frozen monster does not move and its pose is frozen", "moved %.3f model processing=%s" % [still, not posed])
	await _wait_until(func(): return not m.has_status("freeze"), 2.0)
	await _seconds(0.4)
	_check(Formation.flat_distance(p0, m.global_position) > 0.3 and m._model.is_processing() and m.status_fx("freeze") == null and not is_instance_valid(ice),
		"(4) after the freeze ends it walks again, animates, and the ice block is gone", "moved %.3f" % Formation.flat_distance(p0, m.global_position))
	# 성문 영웅 바로 앞 보스: 언 동안 치지 않고 풀리면 친다
	var hero = _heroes()[0]
	hero.hp = hero.hp_max
	var boss = _spawn("epic_boss", _flat(hero.global_position) + Formation.SIDE_DIR[hero.side] * 1.2)
	boss.apply_freeze(1.0)
	await _seconds(0.8)
	var hp_frozen: float = hero.hp
	await _wait_until(func(): return hero.hp < hero.hp_max, 2.0)
	_check(hp_frozen == hero.hp_max and hero.hp < hero.hp_max, "(4) a frozen monster next to a hero does not attack, and attacks once thawed",
		"hp frozen %.0f after %.0f / %.0f" % [hp_frozen, hero.hp, hero.hp_max])
	hero.hp = hero.hp_max
	await _clear()


## (5) root: 걷지 못하지만 기절은 아니다 — 사거리 안이면 친다. 덩굴은 발밑, 끝나면 다시 걷는다. 밀리지 않는다(겹침 해소 무게 INF).
func _root_cases() -> void:
	var m = _spawn("grunt", _far)
	await _seconds(0.3)
	m.apply_root(0.5)
	var p0: Vector3 = m.global_position
	var vines = m.status_fx("root")
	await _seconds(0.3)
	_check(Formation.flat_distance(p0, m.global_position) < 0.01 and m.has_status("root") and not m.is_stunned() and m.is_controlled() and m.push_mass() == INF,
		"(5) a rooted monster stays put without being stunned and cannot be shoved", "moved %.3f" % Formation.flat_distance(p0, m.global_position))
	_check(vines != null and vines.get_meta("fx", "") == "root" and absf(vines.global_position.y - m.global_position.y) < 0.2, "(5) vines sit at the feet", "")
	await _wait_until(func(): return not m.has_status("root"), 2.0)
	await _seconds(0.3)
	_check(Formation.flat_distance(p0, m.global_position) > 0.3 and m.status_fx("root") == null and m.push_mass() < INF, "(5) after the root ends it walks again and the vines are gone", "")
	var hero = _heroes()[0]
	hero.hp = hero.hp_max
	var boss = _spawn("epic_boss", _flat(hero.global_position) + Formation.SIDE_DIR[hero.side] * 1.2)
	boss.apply_root(3.0)
	await _wait_until(func(): return hero.hp < hero.hp_max, 2.5)
	_check(hero.hp < hero.hp_max and boss.has_status("root"), "(5) a rooted monster still attacks a hero in range", "hp %.0f / %.0f" % [hero.hp, hero.hp_max])
	hero.hp = hero.hp_max
	await _clear()


## (6) knockback: from에서 멀어지게 dist(보스 절반)를 0.2초에, 성벽을 넘지 않고(벽을 따라 미끄러짐), 죽었으면 무시. 아레나(castle 없음)는 제한 없음.
func _knockback_cases() -> void:
	var g = _still("grunt", _far)
	var b = _still("epic_boss", _far + Vector3(0, 0, -6))
	await _frames(1)
	for m in [g, b]:
		m._speed = 0.0  # 밀림만 잰다
		m.knockback(m.global_position + Vector3(-1, 0, 0), 2.0)
	var mid: bool = g.has_status("knockback") and g.is_controlled() == false
	for i in 5:
		g._process(0.05)
		b._process(0.05)
	var gd: float = g.global_position.x - _far.x
	var bd: float = b.global_position.x - _far.x
	_check(mid and is_equal_approx(snappedf(gd, 0.001), 2.0) and is_equal_approx(snappedf(bd, 0.001), 1.0) and not g.has_status("knockback"),
		"(6) knockback pushes away from the source by dist over 0.2 s; bosses half", "grunt %.3f boss %.3f" % [gd, bd])
	# 성벽 바깥면 0.4 m 앞(성문에서 비껴): 안쪽으로 밀어도 성 밖에 남는다
	var outer := _half + Balance.WALL_T
	var w = _still("grunt", Vector3(8, 0, -(outer + 0.4)))
	var w2 = _still("grunt", Vector3(-8, 0, -(outer + 0.4)))
	var gate = _still("grunt", Vector3(0, 0, -(outer + 0.4)))  # 성문 바로 앞
	var inn = _still("grunt", Vector3(8, 0, -(_half - 0.5)))  # 성 안 벽 앞
	await _frames(1)
	for m in [w, w2, gate, inn]:
		m._speed = 0.0
	w.knockback(w.global_position + Vector3(0, 0, -1), 3.0)
	w2.knockback(w2.global_position + Vector3(1, 0, -1), 3.0)  # 비스듬히: 벽을 따라 -x로 미끄러진다
	gate.knockback(gate.global_position + Vector3(0, 0, -1), 3.0)
	inn.knockback(inn.global_position + Vector3(0, 0, 1), 3.0)  # 안에서 바깥(−z)으로
	var crossed := 0
	for i in 8:
		for m in [w, w2, gate, inn]:
			var was: bool = Formation.is_inside(_half, m.global_position)
			m._process(0.03)
			crossed += 1 if Formation.is_inside(_half, m.global_position) != was else 0
	_check(crossed == 0 and not Formation.is_inside(_half, w.global_position) and not Formation.is_inside(_half, gate.global_position)
		and Formation.is_inside(_half, inn.global_position),
		"(6) knockback never carries a monster across the castle wall (outside stays out, inside stays in, at the gate too)",
		"crossed=%d w=%s gate=%s inn=%s" % [crossed, w.global_position, gate.global_position, inn.global_position])
	_check(w2.global_position.x < -8.0 - 1.5 and not Formation.is_inside(_half, w2.global_position), "(6) a diagonal push into the wall slides along it",
		"pos=%s" % w2.global_position)
	var dead = _still("grunt", _far + Vector3(6, 0, 0))
	await _frames(1)
	dead.take_damage(1e9)
	var dp: Vector3 = dead.global_position
	dead.knockback(dp + Vector3(-1, 0, 0), 3.0)
	dead._process(0.1)
	_check(dead.global_position == dp and not dead.has_status("knockback"), "(6) a dead monster is not knocked back", "")
	# 아레나: castle 없음 → 성벽 제한 없음
	var a = _still("grunt", Vector3(-8, 0, -(outer + 0.4)))
	await _frames(1)
	a.castle = null
	a._speed = 0.0
	a.knockback(a.global_position + Vector3(0, 0, -1), 3.0)
	for i in 5:
		a._process(0.05)
	_check(Formation.is_inside(_half, a.global_position), "(6) in the arena (no castle) knockback is not limited by walls", "pos=%s" % a.global_position)
	await _clear()


## (7) taunt: 거리 제한 없이 그 영웅만 노린다. 성벽 위·다른 영역 영웅은 무시, 대상이 죽거나 끝나면 곧바로 평소 표적으로.
func _taunt_cases() -> void:
	var heroes := _heroes()
	var near = heroes[0]  # 성문 앞 근접 영웅(성 밖)
	var wall = null
	for h in heroes:
		if h.is_on_wall():
			wall = h
	var far_h = _add_hero("dorik", 301)
	await _frames(1)
	far_h.set_process(false)
	far_h.global_position = _flat(near.global_position) + Formation.SIDE_DIR[near.side] * 14.0 + Formation.perp(near.side) * 6.0
	var inside_h = _add_hero("kyle", 302)
	await _frames(1)
	inside_h.set_process(false)
	inside_h.global_position = Vector3(6, 0, -(_half - 3.0))
	var m = _still("epic_boss", _flat(near.global_position) + Formation.SIDE_DIR[near.side] * 2.0)
	await _frames(1)
	m._process(0.016)
	var first = m._target_hero
	m.taunt(far_h, 0.5)
	var hits := 0
	for i in 15:  # 0.3초: 탐색 주기(0.2초)를 지나도 도발 대상
		m._process(0.02)
		hits += 1 if m._target_hero == far_h else 0
	_check(first == near and hits == 15 and m.has_status("taunt"), "(7) a taunted monster targets the taunting hero beyond aggro, ignoring the nearer one",
		"first=%s hits=%d" % [first, hits])
	m._process(0.25)
	_check(m._target_hero == near and not m.has_status("taunt"), "(7) when the taunt ends the monster rescans and picks the nearest hero again", "target=%s" % m._target_hero)
	if wall != null:
		m.taunt(wall, 1.0)
		m._process(0.02)
		_check(m._target_hero == near and not m.has_status("taunt"), "(7) a wall-top hero cannot taunt", "target=%s" % m._target_hero)
	m.taunt(inside_h, 1.0)
	m._process(0.02)
	_check(m._target_hero == near and not m.has_status("taunt"), "(7) a hero on the other side of the wall cannot taunt", "target=%s" % m._target_hero)
	m.taunt(far_h, 2.0)
	m._process(0.02)
	far_h.take_damage(1e9)
	m._process(0.02)
	_check(not far_h.is_alive() and m._target_hero == near and not m.has_status("taunt"), "(7) the taunt breaks when the taunting hero dies", "target=%s" % m._target_hero)
	for h in [far_h, inside_h]:
		h.formation.release(h.index)
		h.queue_free()
	await _clear()


## (8) has_status·is_controlled: 태그마다 걸기 전 false·건 뒤 true, 군중 제어(slow·stun·freeze·root)만 is_controlled. 기절과 빙결은 따로 끝난다.
func _flag_cases() -> void:
	for tag in ALL_TAGS:
		var m = _still("epic_boss", _far)
		await _frames(1)
		var before: bool = m.has_status(tag) or m.is_controlled()
		_apply(m, tag, 1.0)
		_check(not before and m.has_status(tag) and m.is_controlled() == (tag in CONTROL_TAGS) and m.status_fx(tag) != null,
			"(8) %s: has_status true with a visual, is_controlled %s" % [tag, tag in CONTROL_TAGS], "status=%s" % [m._status.keys()])
		m._process(1.1)
		_check(not m.has_status(tag) and not m.is_controlled() and m._status.is_empty(), "(8) %s ends after its time" % tag, "status=%s" % [m._status.keys()])
		m.queue_free()
	var s = _still("epic_boss", _far)
	await _frames(1)
	s.apply_stun(0.2)
	s.apply_freeze(0.5)
	s._process(0.3)
	_check(s.is_stunned() and not s.has_status("stun") and s.has_status("freeze") and s.status_fx("stun") == null and s.status_fx("freeze") != null,
		"(8) stun and freeze time out separately (still stunned while frozen)", "status=%s" % [s._status.keys()])
	_check(not s.has_status("nonsense"), "(8) unknown tags are never active", "")
	await _clear()


## (9) 죽으면 모든 상태 이펙트를 지운다(언 자세도 풀어 쓰러진다). 이펙트 상한이면 노드 없이 상태만 걸린다. 메시·재질은 공유.
func _death_and_cap_cases() -> void:
	await _wait_until(func(): return Fx.live() == 0, 3.0)
	var m = _still("epic_boss", _far)
	var m2 = _still("epic_boss", _far + Vector3(4, 0, 0))
	await _frames(1)
	for tag in ALL_TAGS:
		_apply(m, tag, 5.0)
	m2.apply_dot("burn", 1.0, 5.0)
	var nodes: Array = m._status.values()
	var all_there: bool = nodes.size() == ALL_TAGS.size() and not nodes.has(null)
	var shared: bool = m2.status_fx("burn").mesh == m.status_fx("burn").mesh and m2.status_fx("burn").material_override == m.status_fx("burn").material_override
	m._process(0.05)
	var iced: bool = not m._model.is_processing()
	m.take_damage(1e9)
	await _frames(1)
	var left := nodes.filter(func(n): return is_instance_valid(n)).size()
	_check(all_there and iced and left == 0 and m._status.is_empty() and m._model.is_processing(),
		"(9) all ten status visuals exist, and all are freed on death (a frozen corpse animates its fall)", "there=%s iced=%s left=%d" % [all_there, iced, left])
	_check(shared, "(9) status meshes and materials are shared between monsters", "")
	var c = _still("epic_boss", _far + Vector3(-4, 0, 0))
	await _frames(1)
	var saved := Fx._live
	Fx._live = Fx.MAX_LIVE
	c.apply_dot("burn", 10.0, 0.2)
	c.apply_freeze(0.2)
	Fx._live = saved
	c._process(0.1)
	_check(c.status_fx("burn") == null and c.status_fx("freeze") == null and c.has_status("burn") and c.is_stunned() and is_equal_approx(_dmg(c), 1.0),
		"(9) at the effect cap the status still applies without a visual", "fx=%s dmg=%.2f" % [c._status.keys(), _dmg(c)])
	c._process(0.2)
	_check(c._status.is_empty(), "(9) a capped (null) status entry is cleared when it ends", "status=%s" % [c._status.keys()])
	await _clear()


## (10) 성능: 몬스터 120마리에 상태 10종을 모두 걸어도 이펙트는 상한 안, _process 한 프레임(120마리)이 가볍다.
func _perf_case() -> void:
	await _wait_until(func(): return Fx.live() == 0, 3.0)
	var ms := []
	for i in 120:
		var m = _still("grunt", _far + Vector3((i % 12) * 1.5, 0, -(i / 12) * 1.5))
		ms.append(m)
	await _frames(1)
	for m in ms:
		m.hp = 1e9
		m.hp_max = 1e9
		for tag in ALL_TAGS:
			if tag != "stun" and tag != "freeze":  # 걷는 경로까지 재려고 정지 상태는 뺀다
				_apply(m, tag, 30.0)
	var t0 := Time.get_ticks_usec()
	for f in 30:
		for m in ms:
			m._process(0.016)
	var per_frame := (Time.get_ticks_usec() - t0) / 30.0
	print("STATUS INFO: 120 monsters with 8 statuses: %.0f us per frame (fx live %d)" % [per_frame, Fx.live()])
	_check(Fx.live() <= Fx.MAX_LIVE, "(10) status visuals respect the effect cap", "live=%d" % Fx.live())
	_check(per_frame < 20000.0, "(10) 120 monsters with statuses process in under 20 ms per frame", "%.0f us" % per_frame)
	await _clear()


func _apply(m, tag: String, sec: float) -> void:
	match tag:
		"slow":
			m.apply_slow(30.0, sec)
		"stun":
			m.apply_stun(sec)
		"poison":
			m.apply_poison(1.0, sec)
		"burn", "bleed", "curse":
			m.apply_dot(tag, 1.0, sec)
		"freeze":
			m.apply_freeze(sec)
		"root":
			m.apply_root(sec)
		"vulnerable":
			m.apply_vulnerable(20.0, sec)
		"weaken":
			m.apply_weaken(20.0, sec)


func _heroes() -> Array:
	var hs := get_tree().get_nodes_in_group("heroes")
	hs.sort_custom(func(a, b): return a.index < b.index)
	return hs


func _add_hero(id: String, idx: int):
	var h = HeroScript.new()
	h.setup(idx, GameData.hero(id), _main.castle, get_tree().get_first_node_in_group("heroes").formation, 0)
	_main.add_child(h)
	return h


## 몬스터 m 자식 중 이펙트 태그 tag인 노드 수(tag "" = 모든 이펙트). 지울 예정인 노드는 빼고.
func _fx_count(m, tag: String) -> int:
	var n := 0
	for c in m.get_children():
		if c.has_meta("fx") and not c.is_queued_for_deletion() and (tag == "" or c.get_meta("fx") == tag):
			n += 1
	return n


## 처리를 끈(제자리) 몬스터.
func _still(kind: String, pos: Vector3):
	var m = _spawn(kind, pos)
	m.set_process(false)
	return m


func _spawn(kind: String, pos: Vector3):
	var m = MonsterScript.new()
	m.setup(kind, Formation.side_of(pos), 1, _main.castle)
	_main.add_child(m)
	m.global_position = pos
	return m


func _dmg(m) -> float:
	return m.hp_max - m.hp


func _flat(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)


func _clear_monsters() -> void:
	for m in get_tree().get_nodes_in_group("monsters"):
		m.queue_free()


## 산 몬스터·시체 모두 지운다.
func _clear() -> void:
	for c in _main.get_children():
		if c.get_script() == MonsterScript:
			c.queue_free()
	await _frames(2)


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
		print("STATUS PASS: " + what)
	else:
		_fails += 1
		print("STATUS FAIL: %s (%s)" % [what, detail])

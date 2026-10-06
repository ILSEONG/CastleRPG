extends Node
## 헤드리스 소환수 체크(scripts/summon.gd): 실제 main 씬(오토로드 포함)에서 소환수의 모양 예산·표적(10 m, 성벽 같은 쪽)·근접/원거리 피해·
## 주인 따라가기·성벽 위 주인·수명·리필·종류별 추가 효과(knockback·apply_root·apply_dot — 그 함수가 있는 몬스터에게만)를 확인한다.
## 실행: ./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/summon_check.tscn
## 오토로드를 쓰므로 tests/run_tests.gd(-s)에서 preload 금지. 스포너를 멈추고 몬스터를 직접 놓는다(대부분 처리를 끈 제자리 몬스터).
## 주인은 대부분 가짜(FakeOwner: 위치·castle만) — 진짜 영웅이 같은 몬스터를 치면 소환수 피해를 가려낼 수 없다.

const Art := preload("res://scripts/art.gd")
const Balance := preload("res://scripts/balance.gd")
const Formation := preload("res://scripts/formation.gd")
const MonsterScript := preload("res://scripts/monster.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")
const SummonScript := preload("res://scripts/summon.gd")
const DamageNumbers := preload("res://scripts/damage_numbers.gd")
const Fx := preload("res://scripts/fx.gd")
const GameData := preload("res://scripts/game_data.gd")

class ErrorCounter extends Logger:
	var count := 0
	func _log_error(_fn: String, _file: String, _line: int, _code: String, _why: String, _notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1


## 가짜 주인: 소환수는 위치·castle·is_alive만 본다.
class FakeOwner extends Node3D:
	var castle
	func is_alive() -> bool:
		return true


## 추가 효과 함수를 가진 가짜 몬스터(monster.gd 새 API 대신): 받은 호출을 적어 둔다. 다른 시스템(체력 바·병사 지휘)이 읽는 필드도 둔다.
class FakeMon extends Node3D:
	var hp := 1000.0
	var hp_max := 1000.0
	var atk := 0.0
	var _stats := {"atk_interval": 1.0}
	var calls: Array = []  # [이름, 인자…]
	func _ready() -> void:
		add_to_group("monsters")
	func is_alive() -> bool:
		return hp > 0.0
	func take_damage(amount: float, kind := 0) -> void:
		hp -= amount
		calls.append(["take_damage", amount, kind])
	func knockback(from: Vector3, dist: float) -> void:
		calls.append(["knockback", from, dist])
	func apply_root(sec: float) -> void:
		calls.append(["apply_root", sec])
	func apply_dot(tag: String, dps: float, sec: float) -> void:
		calls.append(["apply_dot", tag, dps, sec])
	func radius() -> float:
		return 0.4
	func hp_ratio() -> float:
		return hp / hp_max
	func bar_height() -> float:
		return 2.5
	func bar_scale() -> float:
		return 1.0
	func find(name: String) -> Array:
		return calls.filter(func(c): return c[0] == name)


var _fails := 0
var _errors := ErrorCounter.new()
var _main
var _half := 0.0
var _outer := 0.0
var _field := Vector3.ZERO  # 영웅들에게서 먼 성 밖 벌판(북동)
var _m  # 지금 사례의 몬스터(멤버 — 람다가 해제된 노드를 캡처하지 않게)
var _s  # 지금 사례의 소환수


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
	GameState.mode = GameState.Mode.STAGE
	_half = _main.castle.half
	_outer = _half + Balance.WALL_T
	_field = Vector3(_outer + 12.0, 0, -(_outer + 22.0))
	await _run()
	if _errors.count > 0:
		print("SUMMON SCRIPT ERRORS %d" % _errors.count)
	_fails += _errors.count
	if _fails > 0:
		print("SUMMON FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("SUMMON ALL PASSED")
		get_tree().quit(0)


func _run() -> void:
	await _look_case()
	await _meshy_case()
	await _melee_case()
	await _range_and_follow_case()
	await _ranged_case()
	await _wall_side_case()
	await _wall_owner_case()
	await _effects_case()
	await _life_case()
	await _arena_case()
	await _crowd_case()


## (A2) Meshy 모델(SummonScript.MESHY_DIR): 파일이 있는 종류(골렘)는 그 부품 셋 — 몸통 + 양팔 관절이 좌우 대칭·같은 높이, 삼각형 합 5천 이하,
##      영웅과 같은 그림 방식의 텍스처 재질(Fx 정점 색 재질 아님). meshy = false면 코드 모양(Fx 재질)으로 돌아간다.
func _meshy_case() -> void:
	var o = _owner(_field)
	_check(SummonScript.meshy_path("golem") != "", "(A2) the golem has a Meshy model", SummonScript.MESHY_DIR)
	var s = _summon(o, "golem", 5.0, 30.0, _field + Vector3(0, 0, -4))
	await _frames(2)
	var parts: Array = s._parts
	var tris := 0
	var textured := true
	for mi in parts:
		tris += (mi as MeshInstance3D).mesh.get_faces().size() / 3
		var m := (mi as MeshInstance3D).material_override as ShaderMaterial
		textured = textured and m != null and m != Fx.material() and m.get_shader_parameter("use_texture") == true
	_check(parts.size() == 3 and tris > 1000 and tris <= 5000 and textured, "(A2) golem: 3 Meshy parts, 1,000-5,000 triangles, textured",
		"parts=%d tris=%d textured=%s" % [parts.size(), tris, textured])
	if parts.size() == 3:
		var l: Vector3 = parts[1].position
		var r: Vector3 = parts[2].position
		_check(parts[0].position == Vector3.ZERO and l.x < -0.5 and r.x > 0.5 and absf(l.y - r.y) < 0.05 and l.y > 1.2,
			"(A2) golem arms hinge at the shoulders (mirrored, same height)", "l=%s r=%s" % [l, r])
	for k in SummonScript.KINDS:  # 여덟 종류 모두 Meshy: 부품 수 = 코드 모양 부품 수, 몸통은 텍스처, 삼각형 합 5천 이하
		var meshy_parts: Array = SummonScript.parts_of(k, Color.WHITE)
		SummonScript.meshy = false
		var coded: Array = SummonScript.parts_of(k, Color.WHITE)
		SummonScript.meshy = true
		var t := 0
		for p in meshy_parts:
			t += (p[0] as Mesh).get_faces().size() / 3
		_check(SummonScript.meshy_path(k) != "" and meshy_parts.size() == coded.size() and meshy_parts[0][2] == 3 and t <= 5000,
			"(A2) %s: Meshy body, same part count as the coded shape, <= 5,000 triangles" % k,
			"parts=%d coded=%d tris=%d" % [meshy_parts.size(), coded.size(), t])
	SummonScript.meshy = false
	var c = _summon(o, "golem", 5.0, 30.0, _field + Vector3(3, 0, -4))
	await _frames(2)
	_check(c._parts.size() == 3 and c._parts[0].material_override == Fx.material(), "(A2) meshy off: the coded golem", "")
	SummonScript.meshy = true
	_free_summons()
	o.queue_free()


## (A) 모양: 종류마다 MeshInstance3D 1~3개·그림자 없음·그룹 "summons"·등장 연기(fx "summon_puff")·몬스터 표적 아님.
func _look_case() -> void:
	var o = _owner(_field)
	var all := []
	for i in SummonScript.KINDS.size():
		var k: String = SummonScript.KINDS[i]
		all.append(_summon(o, k, 5.0, 30.0, _field + Vector3(-6.0 + 2.0 * i, 0, 0)))
	await _frames(2)
	var puffs := get_tree().get_nodes_in_group("fx").filter(func(n): return n.get_meta("fx", "") == "summon_puff").size()
	for s in all:
		var meshes: Array = s.find_children("*", "MeshInstance3D", true, false)
		var shadows: int = meshes.filter(func(mi): return mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF).size()
		_check(meshes.size() >= 1 and meshes.size() <= 3 and shadows == 0 and s.is_in_group("summons") and s._pivot.visible,
			"(A) %s: 1-3 mesh parts, no shadows, in group 'summons', visible" % s.kind, "meshes=%d shadows=%d" % [meshes.size(), shadows])
		_check(not s.is_in_group("heroes") and not s.is_in_group("crowd") and not s.is_in_group("monsters"),
			"(A) %s: not a hero/crowd/monster (monsters cannot target it)" % s.kind, "groups=%s" % [s.get_groups()])
	_check(puffs == SummonScript.KINDS.size(), "(A) every summon spawns with a puff", "puffs=%d" % puffs)
	_check(all[0].kind == "wolf" and _summon(o, "nope", 1.0, 1.0, _field).kind == "wolf", "(A) unknown kind falls back to wolf", "")
	_free_summons()
	o.queue_free()
	await _frames(2)


## (B) 근접(늑대): 5 m 떨어진 제자리 grunt에게 달려가 0.7초마다 dmg씩 친다(DamageNumbers SKILL).
func _melee_case() -> void:
	var o = _owner(_field)
	_m = _still("grunt", _field + Vector3(5.5, 0, 0))
	var hp0: float = _m.hp
	_s = _summon(o, "wolf", 3.0, 30.0, _field + Vector3(0.5, 0, 0))
	await _seconds(2.2)
	var dealt: float = hp0 - (_m.hp if _alive(_m) else 0.0)
	var d := Formation.flat_distance(_s.global_position, _m.global_position)
	_check(d <= 1.3 + 0.05, "(B) wolf runs up to a monster 5 m away", "d=%.2f" % d)
	_check(_s.hits >= 2 and is_equal_approx(dealt, 3.0 * _s.hits), "(B) wolf hits for exactly dmg each swing (~0.7 s)", "hits=%d dealt=%.1f" % [_s.hits, dealt])
	_check(_s.hits <= 4, "(B) wolf attack interval is ~0.7 s", "hits=%d in 2.2 s" % _s.hits)
	_free_summons()
	_clear_monsters()
	o.queue_free()
	await _frames(2)


## (C) 10 m 밖 몬스터는 무시하고 주인 곁(2~3 m)에 머문다. 주인이 옮겨 가면 따라간다(골렘은 느리지만 따라잡는다).
func _range_and_follow_case() -> void:
	var o = _owner(_field)
	_m = _still("grunt", _field + Vector3(12.5, 0, 0))
	var kinds := ["wolf", "skeleton", "golem", "treant", "hawk", "spirit", "phoenix"]
	for i in kinds.size():
		_summon(o, kinds[i], 3.0, 30.0, _field + Vector3(0, 0, -1.0))
	await _seconds(1.5)
	_check(_m.hp == _m.hp_max, "(C) a monster 12.5 m away is ignored", "hp %.0f/%.0f" % [_m.hp, _m.hp_max])
	for s in _summons():
		var d := Formation.flat_distance(s.global_position, o.global_position)
		_check(d <= 3.2, "(C) %s idles within ~3 m of its owner" % s.kind, "d=%.2f" % d)
	o.global_position = _field + Vector3(-9.0, 0, 3.0)
	await _seconds(4.0)
	for s in _summons():
		var d := Formation.flat_distance(s.global_position, o.global_position)
		_check(d <= 3.2, "(C) %s follows its owner 9 m away" % s.kind, "d=%.2f" % d)
	_free_summons()
	_clear_monsters()
	o.queue_free()
	await _frames(2)


## (D) 원거리: 정령(사거리 6)은 5 m 표적을 제자리에서 쏘고, 포탑은 움직이지 않으며 사거리 9 m 안만 쏜다.
func _ranged_case() -> void:
	var o = _owner(_field)
	_m = _still("epic_boss", _field + Vector3(5.0, 0, 0))
	var hp0: float = _m.hp
	_s = _summon(o, "spirit", 2.0, 30.0, _field)
	await _seconds(2.4)
	var moved := Formation.flat_distance(_s.global_position, _field)
	_check(_s.hits >= 2 and hp0 - _m.hp >= 2.0 * (_s.hits - 1) and moved < 0.3, "(D) spirit shoots a target 5 m away without closing in",
		"hits=%d dealt=%.1f moved=%.2f" % [_s.hits, hp0 - _m.hp, moved])
	_free_summons()
	_clear_monsters()
	await _frames(1)
	var tpos := _field + Vector3(0, 0, 2.0)
	_m = _still("epic_boss", tpos + Vector3(8.5, 0, 0))
	var far = _still("epic_boss", tpos + Vector3(-9.6, 0, 0))
	hp0 = _m.hp
	_s = _summon(o, "turret", 2.0, 30.0, tpos)
	await _seconds(2.5)
	_check(_s.global_position.distance_to(tpos) < 0.01, "(D) turret never moves", "pos=%s" % _s.global_position)
	_check(hp0 - _m.hp >= 2.0 and far.hp == far.hp_max, "(D) turret shoots within 9 m only", "near dealt=%.1f far hp %.0f/%.0f" % [hp0 - _m.hp, far.hp, far.hp_max])
	_free_summons()
	_clear_monsters()
	o.queue_free()
	await _frames(2)


## (E) 성벽 같은 쪽만: 성 밖 소환수는 5.5 m 떨어진 성 안 몬스터를 치지 않고(성벽을 넘지 않는다), 성 안 소환수도 성 밖 몬스터를 치지 않는다.
##     나는 매도 마찬가지. 주인이 성 안으로 들어가면 지상 소환수는 성문으로 돌아 따라 들어간다.
func _wall_side_case() -> void:
	var out_p := Vector3(8, 0, -(_outer + 1.5))
	var in_p := Vector3(8, 0, -(_half - 2.0))
	_heroes_active(false)  # 북 성문 앞 영웅(aggro 8)이 성 밖 몬스터를 치면 소환수 판정이 흐려진다
	var o = _owner(out_p)
	_m = _still("grunt", in_p)
	_summon(o, "wolf", 3.0, 30.0, out_p)
	_summon(o, "hawk", 3.0, 30.0, out_p + Vector3(1.0, 0, 0))
	await _seconds(2.0)
	var outside := _summons().all(func(s): return not Formation.is_inside(_half, s.global_position))
	_check(_m.hp == _m.hp_max and outside, "(E) outside summons ignore a monster just inside the wall", "hp %.0f/%.0f outside=%s" % [_m.hp, _m.hp_max, outside])
	# 주인이 성 안으로: 늑대는 성문으로 돌아 들어간다(곧장 성벽을 지나지 않는다)
	_clear_monsters()
	await _frames(1)
	var wolf = _summons().filter(func(s): return s.kind == "wolf")[0]
	for x in _summons():
		x.hits = 0
	o.global_position = Vector3(6, 0, -(_half - 6.0))
	var max_band := 0.0  # 성벽 띠(half..outer) 안에서 성문 폭 밖으로 간 거리
	var t := 0.0
	while t < 8.0 and Formation.flat_distance(wolf.global_position, o.global_position) > 3.2:
		await get_tree().process_frame
		t += get_process_delta_time()
		var p: Vector3 = wolf.global_position
		var depth := maxf(absf(p.x), absf(p.z))
		if depth > _half and depth < _outer:
			max_band = maxf(max_band, absf(p.x))
	var dw := Formation.flat_distance(wolf.global_position, o.global_position)
	_check(dw <= 3.2 and Formation.is_inside(_half, wolf.global_position), "(E) wolf follows its owner inside through the gate", "d=%.2f pos=%s" % [dw, wolf.global_position])
	_check(max_band < 2.0, "(E) wolf crosses the wall only through the gate opening", "max |x| inside the wall band %.2f" % max_band)
	# 성 안 소환수 ↔ 성 밖 몬스터
	_m = _still("grunt", out_p)
	await _seconds(1.5)
	var where := _summons().map(func(x): return "%s hits=%d at %s" % [x.kind, x.hits, x.global_position])
	_check(_m.hp == _m.hp_max, "(E) inside summons ignore a monster just outside the wall", "hp %.0f/%.0f %s" % [_m.hp, _m.hp_max, where])
	_heroes_active(true)
	_free_summons()
	_clear_monsters()
	o.queue_free()
	await _frames(2)


## (F) 성벽 위 주인(진짜 궁수 영웅): 늑대는 그 면 성벽 바깥 땅으로 내려서고, 포탑은 성벽 위에 남아 성 밖 몬스터를 쏜다(성벽 위는 영역 무관).
func _wall_owner_case() -> void:
	var archer = null
	for h in get_tree().get_nodes_in_group("heroes"):
		if h.is_alive() and h.is_on_wall():
			archer = h
			break
	_check(archer != null, "(F) precondition: a hero stands on the wall", "")
	if archer == null:
		return
	archer.set_process(false)  # 궁수가 같은 몬스터를 쏘지 않게
	var apos: Vector3 = archer.global_position
	var wolf = _summon(archer, "wolf", 3.0, 30.0, apos + Vector3(0.8, 0, 0))
	var tur = _summon(archer, "turret", 3.0, 30.0, apos + Vector3(-0.8, 0, 0))
	await _frames(2)
	_check(wolf.global_position.y < 0.01 and not Formation.is_inside(_half, wolf.global_position) and _summon_hidden_until_settled(wolf),
		"(F) a wolf summoned on the wall drops to the ground outside that wall", "pos=%s" % wolf.global_position)
	_check(tur.global_position.y > Balance.WALL_H / 2.0 and tur._on_wall, "(F) a turret summoned on the wall stays on the wall", "pos=%s" % tur.global_position)
	await _seconds(1.0)
	var dw := Formation.flat_distance(wolf.global_position, wolf._below_wall(apos))
	_check(dw <= 3.2, "(F) the wolf idles below its wall-top owner", "d=%.2f" % dw)
	var s := Formation.side_of(apos)
	_m = _still("grunt", Vector3(apos.x, 0, apos.z) + Formation.SIDE_DIR[s] * 7.0 + Formation.perp(s) * 4.0)
	var hp0: float = _m.hp
	await _seconds(2.0)
	_check(hp0 - _m.hp >= 3.0 or not _alive(_m), "(F) the wall-top turret shoots a monster outside", "dealt=%.1f" % (hp0 - _m.hp))
	archer.set_process(true)
	_free_summons()
	_clear_monsters()
	await _frames(2)


func _summon_hidden_until_settled(s) -> bool:
	return s._settled and s._pivot.visible


## (G) 종류별 추가 효과(가짜 몬스터): 골렘 knockback(자기 위치, 1 m), 트렌트 apply_root(0.5), 불사조 apply_dot("burn", dmg × 0.3, 2) —
##     피해는 dmg 그대로·DamageNumbers.Kind.SKILL. 함수가 없는 진짜 몬스터에게는 오류 없이 피해만(SCRIPT ERROR 수로 확인).
func _effects_case() -> void:
	var o = _owner(_field)
	var want := {"golem": "knockback", "treant": "apply_root", "phoenix": "apply_dot", "skeleton": "", "hawk": ""}
	var mons := {}
	var i := 0
	for k in want:
		var at := _field + Vector3(-12.0 + 6.0 * i, 0, 14.0)
		var fm := FakeMon.new()
		_main.add_child(fm)
		fm.global_position = at + Vector3(1.0, 0, 0)
		mons[k] = fm
		_summon(o, k, 4.0, 30.0, at)
		i += 1
	await _seconds(2.5)
	for k in want:
		var fm = mons[k]
		var dmg_calls: Array = fm.find("take_damage")
		var exact := not dmg_calls.is_empty() and dmg_calls.all(func(c): return c[1] == 4.0 and c[2] == DamageNumbers.Kind.SKILL)
		_check(exact, "(G) %s deals exactly dmg as SKILL damage" % k, "calls=%s" % [dmg_calls])
		var extra: String = want[k]
		var others: Array = fm.calls.filter(func(c): return c[0] != "take_damage" and c[0] != extra)
		_check(others.is_empty(), "(G) %s triggers no other status" % k, "calls=%s" % [others])
		if extra == "":
			continue
		var ex: Array = fm.find(extra)
		var ok := ex.size() == dmg_calls.size() and ex.size() > 0
		match extra:
			"knockback":
				ok = ok and ex.all(func(c): return is_equal_approx(c[2], 1.0))
			"apply_root":
				ok = ok and ex.all(func(c): return is_equal_approx(c[1], 0.5))
			"apply_dot":
				ok = ok and ex.all(func(c): return c[1] == "burn" and is_equal_approx(c[2], 4.0 * 0.3) and is_equal_approx(c[3], 2.0))
		_check(ok, "(G) %s applies %s on every hit" % [k, extra], "calls=%s" % [ex])
	# 진짜 몬스터(새 함수가 없을 수 있다)에게도 오류 없이
	var errs := _errors.count
	_m = _still("grunt", _field + Vector3(0, 0, -6.0))
	for k in ["golem", "treant", "phoenix"]:
		_summon(o, k, 2.0, 30.0, _field + Vector3(0, 0, -7.5))
	await _seconds(2.0)
	_check(_errors.count == errs and _m.hp < _m.hp_max, "(G) golem/treant/phoenix hit a real monster without errors", "errors +%d hp %.0f/%.0f" % [_errors.count - errs, _m.hp, _m.hp_max])
	_free_summons()
	_clear_monsters()
	for fm in mons.values():
		fm.queue_free()
	o.queue_free()
	await _frames(2)


## (H) 수명: sec초 뒤 연기(fx "summon_poof")와 함께 사라진다. 주인이 해제돼도 수명까지 산다. 성 모드는 GameState.refilled에 바로 사라진다.
func _life_case() -> void:
	var o = _owner(_field)
	_s = _summon(o, "skeleton", 1.0, 0.6, _field)
	var t0 := Time.get_ticks_msec()
	await _wait_until(func(): return not is_instance_valid(_s), 3.0)
	var sec := (Time.get_ticks_msec() - t0) / 1000.0
	var poofs := get_tree().get_nodes_in_group("fx").filter(func(n): return n.get_meta("fx", "") == "summon_poof").size()
	_check(not is_instance_valid(_s) and sec > 0.45 and sec < 1.0, "(H) a 0.6 s summon disappears after its lifetime", "after %.2f s" % sec)
	_check(poofs >= 1, "(H) it leaves a poof", "poofs=%d" % poofs)
	_s = _summon(o, "wolf", 1.0, 30.0, _field)
	await _frames(2)
	o.queue_free()
	await _seconds(0.6)
	_check(is_instance_valid(_s) and _s.is_alive(), "(H) the summon outlives its freed owner", "valid=%s" % is_instance_valid(_s))
	GameState.refill()
	await _frames(2)
	_check(not is_instance_valid(_s), "(H) castle-mode summons vanish on GameState.refilled", "valid=%s" % is_instance_valid(_s))
	_free_summons()
	await _frames(2)


## (I) 아레나(주인 castle == null): 영역 제한 없이(성벽 너머도) 10 m 안 가장 가까운 몬스터를 치고, 리필에도 남는다.
func _arena_case() -> void:
	var o = _owner(Vector3(8, 0, -(_outer + 1.5)), true)
	_m = _still("grunt", Vector3(8, 0, -(_half - 1.5)))
	var hp0: float = _m.hp
	_s = _summon(o, "spirit", 2.0, 30.0, o.global_position)
	await _seconds(2.0)
	_check(hp0 - _m.hp >= 2.0 or not _alive(_m), "(I) arena summons ignore the castle region rule", "dealt=%.1f" % (hp0 - _m.hp))
	GameState.refill()
	await _frames(2)
	_check(is_instance_valid(_s), "(I) arena summons do not listen to GameState.refilled", "")
	_free_summons()
	_clear_monsters()
	o.queue_free()
	await _frames(2)


## (J) 10 소환수 + 20 몬스터 3초: 오류 없이, 이펙트 상한 안. 걷는 몬스터는 소환수를 표적으로 삼지 않는다(영웅만).
func _crowd_case() -> void:
	var o = _owner(_field)
	for i in 20:
		_still("grunt", _field + Vector3(6.0 + (i % 5) * 1.2, 0, -3.0 + (i / 5) * 1.5))
	for i in 10:
		_summon(o, SummonScript.KINDS[i % SummonScript.KINDS.size()], 1.0, 30.0, _field + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))
	var walker = _spawn("grunt", 0, _field + Vector3(-4, 0, 0))
	var errs := _errors.count
	var t0 := Time.get_ticks_usec()
	var frames := 0
	var t := 0.0
	var targeted := false
	while t < 3.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		frames += 1
		if _alive(walker) and walker._target_hero != null:
			targeted = true
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, frames)
	print("SUMMON INFO: 10 summons + 20 monsters: %.2f ms/frame over %d frames, fx live %d" % [ms, frames, Fx.live()])
	_check(_errors.count == errs and Fx.live() <= Fx.MAX_LIVE, "(J) 10 summons fight 20 monsters for 3 s without errors", "errors +%d" % (_errors.count - errs))
	_check(not targeted, "(J) a walking monster never targets a summon", "")
	_free_summons()
	_clear_monsters()
	o.queue_free()
	await _frames(2)


# --- 도우미 ---

func _owner(pos: Vector3, arena := false):
	var o := FakeOwner.new()
	o.castle = null if arena else _main.castle
	_main.add_child(o)
	o.global_position = pos
	return o


func _summon(owner_node, kind: String, dmg: float, sec: float, pos: Vector3):
	var s = SummonScript.new()
	s.setup(owner_node, kind, dmg, sec, Color(0.4, 0.6, 0.9))
	_main.add_child(s)
	s.global_position = pos
	return s


func _heroes_active(on: bool) -> void:
	for h in get_tree().get_nodes_in_group("heroes"):
		h.set_process(on)


func _summons() -> Array:
	return get_tree().get_nodes_in_group("summons").filter(func(s): return is_instance_valid(s) and not s.is_queued_for_deletion())


func _free_summons() -> void:
	for s in get_tree().get_nodes_in_group("summons"):
		s.queue_free()


## 처리를 끈(제자리) 몬스터.
func _still(kind: String, pos: Vector3):
	var m = _spawn(kind, Formation.side_of(pos), pos)
	m.set_process(false)
	return m


func _spawn(kind: String, side: int, pos: Vector3):
	var m = MonsterScript.new()
	m.setup(kind, side, 1, _main.castle)
	_main.add_child(m)
	m.global_position = pos
	return m


func _alive(m) -> bool:
	return is_instance_valid(m) and m.is_alive()


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
		print("SUMMON PASS: " + what)
	else:
		_fails += 1
		print("SUMMON FAIL: %s (%s)" % [what, detail])

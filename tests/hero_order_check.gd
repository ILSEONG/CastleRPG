extends Node
## 헤드리스 영웅 명령 체크(사용자 2026-10-14): 실제 main 씬에서
##  (1) 영웅을 고른 채 적을 누르면 공격 명령 — 쫓아가 쓰러뜨리고(성문을 거쳐서도), 빨간 표적 링이 따라다니다 사라지고, 쓰러뜨린 곳에 선다.
##      성벽 위 궁수는 닿는 적이면 자리를 지키며 쏜다. 같은 적을 거듭 눌러도 명령·표시가 그대로다.
##  (2) 같은 쪽을 거듭 눌러도 경로가 흔들리지 않는다 — 지나는 성문이 바뀌지 않고, 지나친 성문 통과 지점으로 돌아서지 않고,
##      성벽 위 같은 자리 근처를 누르면 자리를 옮기지 않는다.
## 실행: godot --headless --path . res://tests/hero_order_check.tscn

const Formation := preload("res://scripts/formation.gd")
const Balance := preload("res://scripts/balance.gd")
const PickerScript := preload("res://scripts/unit_picker.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")
const MonsterScript := preload("res://scripts/monster.gd")
const GameData := preload("res://scripts/game_data.gd")

class ErrorCounter extends Logger:
	var count := 0
	func _log_error(_fn: String, _file: String, _line: int, _code: String, _why: String, _notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1

var _fails := 0
var _errors := ErrorCounter.new()
var _main
var _picker
var _half := 0.0


func _ready() -> void:
	OS.add_logger(_errors)
	Economy.save_path = ""
	Fever.save_path = ""
	Fever.reset()
	GameData._config.fx_shake = "0"
	Economy.reset(Time.get_unix_time_from_system())
	get_window().size = Vector2i(360, 640)
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(5)
	for c in _main.get_children():
		if c.get_script() == PickerScript:
			_picker = c
		elif c.get_script() == SpawnerScript:
			c.set_process(false)
	for m in get_tree().get_nodes_in_group("monsters"):
		m.queue_free()
	await _frames(2)
	var heroes: Array = get_tree().get_nodes_in_group("heroes")
	heroes.sort_custom(func(a, b): return a.index < b.index)
	_half = heroes[0].castle.half
	await _attack_cases(heroes)
	await _route_cases(heroes)
	_fails += _errors.count
	if _errors.count > 0:
		print("ORDER SCRIPT ERRORS %d" % _errors.count)
	print("ORDER FAILED %d" % _fails if _fails > 0 else "ORDER ALL PASSED")
	get_tree().quit(1 if _fails > 0 else 0)


func _attack_cases(heroes: Array) -> void:
	var warrior = heroes[0]  # 북(0) 성문 앞
	var archer = heroes[1]   # 동(1) 성벽 위
	# (a) 성 밖 적: 고른 채 누르면 쫓아가 쓰러뜨린다
	var wp: Vector3 = warrior.global_position
	var m = _monster(wp + Formation.SIDE_DIR[0] * 6.0 + Formation.perp(0) * 4.0)
	await _frames(2)
	_picker._select(warrior)
	await _tap_at(m)
	_check(warrior.focus_target() == m and _picker.selected == warrior, "(a) tapping an enemy with a hero selected orders an attack and keeps the selection")
	var mk = _picker._routes.get(warrior)
	_check(mk != null and is_instance_valid(mk) and mk.target == m, "(a) red target marker follows the enemy")
	await _tap_at(m)
	_check(_picker._routes.get(warrior) == mk and warrior.focus_target() == m, "(a) tapping the same enemy again changes nothing (double tap)")
	await _until(func(): return not m.is_alive(), 900)
	_check(not m.is_alive(), "(a) hero chased and killed the enemy")
	await _frames(3)
	_check(warrior.focus_target() == null and not is_instance_valid(mk), "(a) attack order and marker end when the enemy falls")
	_check(warrior.post == Formation.POST_FREE and Formation.flat_distance(warrior.free_pos, warrior.global_position) < 1.0, "(a) hero holds where it finished the enemy",
		"post %d free %s at %s" % [warrior.post, warrior.free_pos, warrior.global_position])
	# (b) 성 안 적(성 밖 영웅): 성문을 거쳐 간다
	var gi := Formation.gate_inner(_half, 0, Formation.nearest_gate_at(_half, 0, warrior.global_position))
	var m2 = _monster(gi - Formation.SIDE_DIR[0] * 2.0 + Formation.perp(0) * 3.0)
	await _frames(2)
	_picker._select(warrior)
	await _tap_at(m2)
	_check(warrior.focus_target() == m2, "(b) attack order on an enemy inside the castle")
	await _frames(2)
	_check(warrior._path.size() >= 2, "(b) hero routes through the gate (%d points)" % warrior._path.size())
	var crossed := [false]
	await _until(func():
		if not Formation.is_inside(_half, warrior.global_position) and Formation.in_wall_body(_half, warrior.global_position):
			crossed[0] = true
		return not m2.is_alive(), 1500)
	_check(not m2.is_alive() and not crossed[0], "(b) hero reached and killed it without walking through the wall")
	# (c) 성벽 위 궁수: 닿는 적이면 자리를 지키며 쏜다
	var ap: Vector3 = archer.global_position
	var m3 = _monster(Vector3(ap.x, 0.0, ap.z) + Formation.SIDE_DIR[archer.side] * (float(archer.def.range) * 0.5 + 2.0))
	await _frames(2)
	var slot0: int = archer.slot
	_picker._select(archer)
	await _tap_at(m3)
	_check(archer.focus_target() == m3, "(c) wall archer takes the attack order")
	await _until(func(): return not m3.is_alive(), 900)
	_check(not m3.is_alive() and archer.post == Formation.POST_WALL and archer.slot == slot0 and archer.is_on_wall(), "(c) archer shot it from its wall post",
		"post %d slot %d on wall %s" % [archer.post, archer.slot, archer.is_on_wall()])
	# (d) 새 이동 명령이 공격 명령을 끝낸다
	var m4 = _monster(warrior.global_position + Vector3(5, 0, 5))
	await _frames(2)
	_picker._select(warrior)
	await _tap_at(m4)
	_check(warrior.focus_target() == m4, "(d) attack order given")
	warrior.move_to_point(warrior.global_position + Vector3(-3, 0, 0))
	_check(warrior.focus_target() == null, "(d) a move order cancels the attack order")
	m4.queue_free()
	await _frames(2)


func _route_cases(heroes: Array) -> void:
	var h = heroes[2]
	var archer = heroes[3]
	# (e) 성 안 → 성 밖 모서리 근처 도착지(북쪽 면), 다음 탭은 대각선 너머(동쪽 면)로 조금 — 지나는 성문은 그대로
	var gates: Array = Formation.gate_offsets(_half)
	var diag := Formation.SIDE_DIR[0] + Formation.SIDE_DIR[1]
	_place(h, diag * (_half * 0.4))
	var far := _half + Balance.WALL_T + 5.0
	var d1 := diag * far + Formation.SIDE_DIR[0] * 0.4
	h.move_to_point(d1)
	var g1: Vector3 = h._path[0]
	var d2 := diag * far + Formation.SIDE_DIR[1] * 0.4
	var fresh := Formation.route(_half, h.global_position, d2)
	h.move_to_point(d2)
	_check(fresh[0].distance_to(g1) > 1.0, "(e) setup: a fresh route would switch gates", "fresh %s g1 %s" % [fresh[0], g1])
	_check(h._path[0].distance_to(g1) < 0.01 and h._path[h._path.size() - 1].distance_to(d2) < 0.01, "(e) re-tapping across the corner keeps the gate already chosen",
		"first %s was %s" % [h._path[0], g1])
	# (f) 성문 통로 안(안쪽 통과 지점을 지났다)에서 다시 누르면 안쪽 통과 지점으로 돌아서지 않는다
	var at := float(gates[0])
	var gin := Formation.gate_inner(_half, 0, at)
	var gout := Formation.gate_outer(_half, 0, at)
	_place(h, gin.lerp(gout, 0.4))
	h._path.clear()
	var d3 := Formation.SIDE_DIR[0] * far + Formation.perp(0) * (at + 3.0)
	h.move_to_point(d3)
	var first: Vector3 = h._path[0]
	_check((first - h.global_position).dot(gout - gin) > 0.0, "(f) re-plan from inside the gate passage does not step back to the inner gate point",
		"first %s hero %s" % [first, h.global_position])
	# (g) 성벽 위 같은 자리 근처를 다시 누르면 자리를 옮기지 않는다
	await _until(func(): return archer._path.is_empty(), 600)
	var s0: int = archer.slot
	var off := Formation.perp(archer.side).dot(archer.stand_position())
	archer.move_to(archer.side, Formation.POST_WALL, off + 1.0)
	_check(archer.slot == s0, "(g) wall tap 1 m from the current spot keeps the spot")
	archer.move_to(archer.side, Formation.POST_WALL, off - 1.0)
	_check(archer.slot == s0, "(g) wall tap 1 m the other way keeps the spot too")


func _monster(p: Vector3):
	var m = MonsterScript.new()
	m.setup("grunt", 0, 1, heroes_castle())
	_main.add_child(m)
	m.global_position = Vector3(p.x, 0.0, p.z)
	m.set_process(false)  # 제자리(영웅에게 걸어오지 않게)
	return m


func heroes_castle():
	return get_tree().get_nodes_in_group("heroes")[0].castle


func _place(h, p: Vector3) -> void:
	h.global_position = Vector3(p.x, 0.0, p.z)


func _tap_at(m) -> void:
	_picker._pending = _picker.camera.unproject_position(m.global_position + Vector3(0, 0.8, 0))
	await _frames(2)


func _until(cond: Callable, max_frames: int) -> void:
	for i in max_frames:
		if cond.call():
			return
		await _frames(1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame


func _check(cond: bool, what: String, detail := "") -> void:
	if cond:
		print("ORDER PASS: " + what)
	else:
		_fails += 1
		print("ORDER FAIL: %s (%s)" % [what, detail])

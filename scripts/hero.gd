extends Node3D
## 영웅. 배정 성문 바깥 자리에서 사거리 내 몬스터 자동 공격. 사망 시 부활 없음, refilled에서만 복귀.

const Balance := preload("res://scripts/balance.gd")
const Flat := preload("res://scripts/flat.gd")

enum State { IDLE, MOVE, ATTACK, DEAD }

const SCAN_INTERVAL := 0.2

var castle
var index: int = 0
var assigned_side: int = 0
var hp: float = Balance.HERO.hp
var state: int = State.IDLE
var selected := false:
	set(v):
		selected = v
		if _ring != null:
			_ring.visible = v and state != State.DEAD

var _body: MeshInstance3D
var _ring: MeshInstance3D
var _area: Area3D
var _target
var _atk_cd := 0.0
var _scan_cd := 0.0


func _ready() -> void:
	add_to_group("heroes")
	_body = Flat.capsule(0.4, 1.4, Flat.HERO)
	add_child(_body)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.75
	_ring = Flat.mesh(torus, Flat.HERO_SELECTED)
	_ring.position.y = 0.05
	_ring.visible = false
	add_child(_ring)
	_area = Area3D.new()
	_area.collision_layer = 4
	_area.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.6
	shape.height = 1.6
	cs.shape = shape
	cs.position.y = 0.8
	_area.add_child(cs)
	_area.set_meta("hero", self)
	add_child(_area)
	GameState.refilled.connect(reset)
	reset()


func reset() -> void:
	hp = Balance.HERO.hp
	state = State.IDLE
	_target = null
	global_position = stand_position()
	_body.visible = true
	_area.collision_layer = 4
	_ring.visible = selected


func stand_position() -> Vector3:
	return castle.hero_stand_position(assigned_side, index)


func move_to_side(side: int) -> void:
	assigned_side = side
	if state != State.DEAD:
		state = State.MOVE


func take_damage(amount: float) -> void:
	if state == State.DEAD:
		return
	hp = maxf(0.0, hp - amount)
	if hp == 0.0:
		state = State.DEAD
		_body.visible = false
		_ring.visible = false
		_area.collision_layer = 0


func is_alive() -> bool:
	return state != State.DEAD


func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	_atk_cd -= delta
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = SCAN_INTERVAL
		_target = _nearest_monster()
	if _target != null and is_instance_valid(_target) and _target.is_alive():
		state = State.ATTACK
		if _atk_cd <= 0.0:
			_atk_cd = Balance.HERO.atk_interval
			_target.take_damage(Balance.HERO.atk)
		return
	_target = null
	var dest := stand_position()
	if global_position.distance_to(dest) > 0.05:
		state = State.MOVE
		global_position = global_position.move_toward(dest, Balance.HERO.speed * delta)
	else:
		state = State.IDLE


func _nearest_monster():
	var best = null
	var best_d: float = Balance.HERO.range
	for m in get_tree().get_nodes_in_group("monsters"):
		if not m.is_alive():
			continue
		var d: float = global_position.distance_to(m.global_position)
		if d <= best_d:
			best_d = d
			best = m
	return best

extends Node3D
## 영웅. 역할(전사/궁수)별 스탯. 배정 자리(면 · 성문 앞/성벽 위 · 슬롯)로 이동하고, 자리에 서 있을 때만
## 수평 사거리 안 가장 가까운 괴물을 자동 공격한다. 성벽 위에 서 있으면 근접 괴물의 표적이 되지 않는다.
## 사망 시 부활 없음, GameState.refilled에서만 배정 자리로 복귀.

const Balance := preload("res://scripts/balance.gd")
const Flat := preload("res://scripts/flat.gd")
const Formation := preload("res://scripts/formation.gd")

enum State { IDLE, MOVE, ATTACK, DEAD }

const SCAN_INTERVAL := 0.2
const ARRIVE_EPS := 0.05
const TRACER_SEC := 0.15

var castle
var formation
var index: int = 0
var role: String = ""
var side: int = 0
var post: int = Formation.POST_GATE
var slot: int = 0
var hp: float = 0.0
var state: int = State.IDLE
var selected := false:
	set(v):
		selected = v
		if _ring != null:
			_ring.visible = v and state != State.DEAD

var _stats: Dictionary = {}
var _body: MeshInstance3D
var _ring: MeshInstance3D
var _area: Area3D
var _target
var _atk_cd := 0.0
var _scan_cd := 0.0


## add_child 전에 호출. 기본 배치: 면 = index % 4, 전사는 성문 앞, 궁수는 성벽 위.
func setup(p_index: int, p_castle, p_formation) -> void:
	index = p_index
	castle = p_castle
	formation = p_formation
	role = Balance.hero_role(index)
	_stats = Balance.HERO_ROLES[role]
	var default_post := Formation.POST_WALL if role == "archer" else Formation.POST_GATE
	var placed := move_to(index % 4, default_post)
	assert(placed, "no free default slot for hero %d" % index)


func _ready() -> void:
	add_to_group("heroes")
	_body = Flat.capsule(0.45, 1.6, _stats.color)
	add_child(_body)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.6
	torus.outer_radius = 0.8
	_ring = Flat.mesh(torus, Flat.HERO_SELECTED)
	_ring.position.y = 0.05
	_ring.visible = false
	add_child(_ring)
	_area = Area3D.new()
	_area.collision_layer = 4
	_area.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.7
	shape.height = 1.8
	cs.shape = shape
	cs.position.y = 0.9
	_area.add_child(cs)
	_area.set_meta("hero", self)
	add_child(_area)
	GameState.refilled.connect(reset)
	reset()


func reset() -> void:
	hp = _stats.hp
	state = State.IDLE
	_target = null
	global_position = stand_position()
	_body.visible = true
	_area.collision_layer = 4
	_ring.visible = selected


func stand_position() -> Vector3:
	return castle.slot_position(side, post, slot)


## 자리 변경 명령. 목표 자리가 가득 차면 false (현재 자리 유지).
func move_to(p_side: int, p_post: int) -> bool:
	var s: int = formation.claim(index, p_side, p_post)
	if s < 0:
		return false
	side = p_side
	post = p_post
	slot = s
	return true


## 실제 높이로 판정한다 — 오르내리는 중에는 지상 취급.
func is_on_wall() -> bool:
	return global_position.y > Balance.WALL_H / 2.0


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
	var dest := stand_position()
	if global_position.distance_to(dest) > ARRIVE_EPS:
		state = State.MOVE
		_target = null
		global_position = global_position.move_toward(dest, float(_stats.speed) * delta)
		return
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = SCAN_INTERVAL
		_target = _nearest_monster()
	if _target != null and is_instance_valid(_target) and _target.is_alive():
		state = State.ATTACK
		if _atk_cd <= 0.0:
			_atk_cd = _stats.atk_interval
			if role == "archer":
				_fire_tracer(_target.global_position)
			_target.take_damage(_stats.atk)
	else:
		_target = null
		state = State.IDLE


func _nearest_monster():
	var best = null
	var best_d: float = _stats.range
	for m in get_tree().get_nodes_in_group("monsters"):
		if not m.is_alive():
			continue
		var d := Formation.flat_distance(global_position, m.global_position)
		if d <= best_d:
			best_d = d
			best = m
	return best


## 궁수 화살 궤적 (시각 효과만. 피해는 발사 즉시 적용).
func _fire_tracer(to: Vector3) -> void:
	var from := global_position + Vector3(0, 1.3, 0)
	var dest := to + Vector3(0, 0.6, 0)
	if Formation.flat_distance(from, dest) < 0.1:
		return
	var bm := BoxMesh.new()
	bm.size = Vector3(0.1, 0.1, 0.8)
	var arrow := Flat.mesh(bm, Flat.ARROW)
	get_parent().add_child(arrow)
	arrow.global_position = from
	arrow.look_at(dest)
	var tw := arrow.create_tween()
	tw.tween_property(arrow, "global_position", dest, TRACER_SEC)
	tw.tween_callback(arrow.queue_free)

extends Node3D
## 영웅. 역할(전사/궁수)별 스탯. 배정 자리(면 · 성문 앞/성벽 위 · 슬롯)로 이동하고, 자리에 서 있을 때만
## 수평 사거리 안 가장 가까운 괴물을 자동 공격한다. 성벽 위에 서 있으면 근접 괴물의 표적이 되지 않는다.
## 사망 시 부활 없음, GameState.refilled에서만 배정 자리로 복귀.

const Balance := preload("res://scripts/balance.gd")
const Art := preload("res://scripts/art.gd")
const Formation := preload("res://scripts/formation.gd")
const UnitModelScript := preload("res://scripts/unit_model.gd")

enum State { IDLE, MOVE, ATTACK, DEAD }

const SCAN_INTERVAL := 0.2
const ARRIVE_EPS := 0.05
const TRACER_SEC := 0.15
const ARROW_PITCH_FIX := PI / 2.0  # 화살 모델은 길이 축 Y, 촉이 -Y → X축 +90°로 촉을 -Z(look_at 정면)에 맞춘다

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
var _model
var _ring: MeshInstance3D
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
	_model = UnitModelScript.new()
	_model.setup(Art.HERO_MODELS[role])
	add_child(_model)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.6
	torus.outer_radius = 0.8
	_ring = Art.mesh(torus, Art.HERO_SELECTED)
	_ring.position.y = 0.05
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)
	GameState.refilled.connect(reset)
	reset()


func reset() -> void:
	hp = _stats.hp
	state = State.IDLE
	_target = null
	global_position = stand_position()
	_model.reset_pose()
	_model.face(Formation.SIDE_DIR[side])  # 대기 중엔 성 바깥을 본다
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
		_model.play_death()
		_ring.visible = false


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
		_model.face(dest - global_position)
		_model.play_walk()
		global_position = global_position.move_toward(dest, float(_stats.speed) * delta)
		return
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = SCAN_INTERVAL
		_target = _nearest_monster()
	if _target != null and is_instance_valid(_target) and _target.is_alive():
		state = State.ATTACK
		_model.face(_target.global_position - global_position)
		if _atk_cd <= 0.0:
			_atk_cd = _stats.atk_interval
			_model.play_attack()
			if role == "archer":
				_fire_tracer(_target.global_position)
			_target.take_damage(_stats.atk)
	else:
		_target = null
		if state != State.IDLE:
			state = State.IDLE
			_model.play_idle()
			_model.face(Formation.SIDE_DIR[side])  # 대기로 돌아오면 늘 성 바깥을 본다


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


## 궁수 화살 (시각 효과만. 피해는 발사 즉시 적용).
func _fire_tracer(to: Vector3) -> void:
	var from := global_position + Vector3(0, 1.3, 0)
	var dest := to + Vector3(0, 0.8, 0)
	if Formation.flat_distance(from, dest) < 0.1:
		return
	var arrow := Node3D.new()
	var model := Art.instance(Art.ARROW_MODEL)
	model.scale = Vector3.ONE * Art.ARROW_SCALE
	model.rotation.x = ARROW_PITCH_FIX
	arrow.add_child(model)
	get_parent().add_child(arrow)
	arrow.global_position = from
	arrow.look_at(dest)
	var tw := arrow.create_tween()
	tw.tween_property(arrow, "global_position", dest, TRACER_SEC)
	tw.tween_callback(arrow.queue_free)

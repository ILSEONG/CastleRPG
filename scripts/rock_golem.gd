extends "res://scripts/monster.gd"
## 바위 골렘(모집권 던전 보스, 2026-10-06 — 클래시 오브 클랜 골렘 느낌의 우리 디자인): 느리고 단단하며 주먹이 무겁다. monster.gd 아레나 모드
## (일반 공격 — 왼·오른 주먹·발차기 중 무작위, Art "attacks") + 데스나이트처럼 범위 예고(바닥 원이 빨갛게 차오르는 동안 그 자리에 선다 — 다 차는 순간
## 원 안 영웅만 맞는다) 패턴 둘:
## 내려찍기: SLAM_SEC마다 발밑 반경 SLAM_R 원(TELE_SLAM초) + 두 팔 내려찍기 → 원 안 영웅 모두 공격 × SLAM_MULT, 기절 STUN_SEC, 땅 갈라짐.
## 바위 던지기: THROW_SEC마다 가장 먼 영웅 자리에 반경 THROW_R 원(TELE_THROW초, 예고 시작 때 자리) + 던지기 모션 → 바위가 날아가 떨어지며
## 원 안 영웅 모두 공격 × THROW_MULT.
## 쓰러지면 조각(golemite 행)으로 갈라진다 — dungeon.gd가 시체 자리에 낸다. 예고 중에는 상태 시간이 흐르지 않는다(데스나이트와 같다).

const SLAM_SEC := 9.0
const SLAM_R := 3.4
const SLAM_MULT := 1.6
const TELE_SLAM := 1.3
const SLAM_ANIM := "2H_Melee_Attack_Chop"  # 두 주먹을 머리 위로 들었다 내려찍는다
const THROW_SEC := 13.0
const THROW_R := 2.4
const THROW_MULT := 1.2
const TELE_THROW := 1.4
const THROW_ANIM := "Throw"
const THROW_FLY := 0.45  # 바위가 날아가는 시간(예고가 다 차는 순간 떨어진다)
const STUN_SEC := 0.8
const ROCK_COLOR := Color(0.47, 0.44, 0.40)
const DUST_COLOR := Color(0.62, 0.55, 0.45)

var slam_cd := SLAM_SEC * 0.6  # 첫 내려찍기는 조금 빨리
var throw_cd := THROW_SEC
var slams := 0  # 테스트용
var throws := 0

var _tele := ""  # 예고 중인 패턴("slam"·"throw", 없으면 "")
var _tele_t := 0.0
var _tele_node: Node3D
var _throw_at := Vector3.ZERO


func _process(delta: float) -> void:
	if not is_alive():
		if _tele_node != null and is_instance_valid(_tele_node):
			_tele_node.queue_free()
		return
	if _tele != "":
		_tick_tele(delta)
		return
	super._process(delta)
	slam_cd -= delta
	throw_cd -= delta
	if not is_alive() or is_stunned() or _swing_left >= 0.0 or _model.is_busy():  # 휘두르는 중이면 모션이 다 끝난 뒤에 패턴(타격 순간에 끊지 않게)
		return
	if slam_cd <= 0.0 and _hero_near(SLAM_R + 1.0):
		slam()
	elif throw_cd <= 0.0:
		throw_rock()


func _hero_near(r: float) -> bool:
	for h in get_tree().get_nodes_in_group("heroes"):
		if h.is_alive() and Formation.flat_distance(global_position, h.global_position) <= r:
			return true
	return false


## 내려찍기 예고: 발밑 원 + 두 팔 내려찍기(내려치는 순간 = 원이 다 차는 순간).
func slam() -> void:
	slam_cd = SLAM_SEC
	_start_tele("slam", TELE_SLAM)
	_tele_node = Fx.telegraph_circle(get_parent(), global_position, SLAM_R, TELE_SLAM)
	_model.play_cast(SLAM_ANIM, TELE_SLAM)


## 바위 던지기 예고: 가장 먼 살아 있는 영웅 자리(지금)에 원 + 던지기 모션.
func throw_rock() -> void:
	throw_cd = THROW_SEC
	var far = null
	var far_d := -1.0
	for h in get_tree().get_nodes_in_group("heroes"):
		var d := Formation.flat_distance(global_position, h.global_position)
		if h.is_alive() and d > far_d:
			far_d = d
			far = h
	if far == null:
		return
	_throw_at = Vector3(far.global_position.x, 0.0, far.global_position.z)
	_model.face(_throw_at - global_position)
	_start_tele("throw", TELE_THROW)
	_tele_node = Fx.telegraph_circle(get_parent(), _throw_at, THROW_R, TELE_THROW)
	_model.play_cast(THROW_ANIM, TELE_THROW - THROW_FLY)
	get_tree().create_timer(TELE_THROW - THROW_FLY).timeout.connect(_launch_rock)


func _start_tele(kind: String, sec: float) -> void:
	_tele = kind
	_tele_t = sec
	_swing_left = -1.0
	_swing_hero = null


func _tick_tele(delta: float) -> void:
	_tele_t -= delta
	if _tele_t > 0.0:
		return
	var kind := _tele
	_tele = ""
	_tele_node = null
	if kind == "slam":
		_slam_hit()
	else:
		_throw_hit()


## 원이 다 찬 순간: 원 안 영웅 모두 공격 × 1.6 + 기절, 땅 갈라짐·먼지.
func _slam_hit() -> void:
	slams += 1
	var at := Vector3(global_position.x, 0.0, global_position.z)
	Fx.quake(get_parent(), at, SLAM_R, 1)
	Fx.impact(get_parent(), at, DUST_COLOR, SLAM_R * 0.6, 2)
	for h in get_tree().get_nodes_in_group("heroes"):
		if h.is_alive() and Formation.flat_distance(global_position, h.global_position) <= SLAM_R:
			h.take_damage(hit_damage() * SLAM_MULT, self)
			h.apply_stun(STUN_SEC)
	_atk_cd = float(_stats.atk_interval)


## 손에서 바위가 포물선으로 날아가 예고 원 가운데에 떨어진다(그림만 — 피해는 _throw_hit).
func _launch_rock() -> void:
	if not is_alive() or not is_inside_tree():
		return
	var rock := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.55
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 3
	rock.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ROCK_COLOR
	rock.material_override = mat
	get_parent().add_child(rock)
	var from := global_position + Vector3(0, 2.6 * float(_stats.scale) / 2.4, 0)
	rock.global_position = from
	var to := _throw_at
	var tw := rock.create_tween()
	tw.tween_method(func(t: float): rock.global_position = from.lerp(to, t) + Vector3.UP * 6.0 * t * (1.0 - t); rock.rotation.x = t * TAU, 0.0, 1.0, THROW_FLY)
	tw.tween_callback(rock.queue_free)


func _throw_hit() -> void:
	throws += 1
	Fx.impact(get_parent(), _throw_at, DUST_COLOR, THROW_R * 0.7, 1)
	Fx.quake(get_parent(), _throw_at, THROW_R, 0)
	for h in get_tree().get_nodes_in_group("heroes"):
		if h.is_alive() and Formation.flat_distance(_throw_at, h.global_position) <= THROW_R:
			h.take_damage(hit_damage() * THROW_MULT, self)
	_atk_cd = float(_stats.atk_interval)


func is_telegraphing() -> bool:
	return _tele != ""

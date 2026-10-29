extends "res://scripts/monster.gd"
## 광산 오우거(강화석 던전 보스, 2026-10-29 사용자 "적 보스 공격모션이 왤캐 찔끔 찔끔"): 일반 공격만으로는 찌르기·베기가 작아 보여서
## 데스나이트·바위 골렘처럼 큰 패턴 둘을 단다(범위 예고 — 바닥 원이 빨갛게 차오르는 동안 그 자리에 선다, 다 차는 순간 원 안 영웅만 맞는다).
## 회전 베기: SPIN_SEC마다 발밑 반경 SPIN_R 원(TELE_SPIN초) + 양손 도끼 돌기 → 원 안 영웅 모두 공격 × SPIN_MULT.
## 대지 가르기: SLAM_SEC마다 가까운 영웅 쪽 앞(SLAM_AHEAD m)에 반경 SLAM_R 원(TELE_SLAM초) + 도끼 내려찍기 →
## 원 안 영웅 모두 공격 × SLAM_MULT, 기절 STUN_SEC, 땅 갈라짐. 예고 중에는 상태 시간이 흐르지 않는다(데스나이트와 같다).

const SPIN_SEC := 7.0
const SPIN_R := 3.2
const SPIN_MULT := 1.5
const TELE_SPIN := 1.1
const SPIN_ANIM := "2H_Melee_Attack_Spin"
const SLAM_SEC := 11.0
const SLAM_R := 2.6
const SLAM_AHEAD := 2.2
const SLAM_MULT := 2.0
const TELE_SLAM := 1.3
const SLAM_ANIM := "2H_Melee_Attack_Chop"
const STUN_SEC := 0.8
const SPIN_COLOR := Color(0.85, 0.12, 0.08)
const DUST_COLOR := Color(0.50, 0.55, 0.62)  # 수정 광산 바닥 돌가루

var spin_cd := SPIN_SEC * 0.6  # 첫 회전 베기는 조금 빨리
var slam_cd := SLAM_SEC * 0.8
var spins := 0  # 테스트용
var slams := 0

var _tele := ""  # 예고 중인 패턴("spin"·"slam", 없으면 "")
var _tele_t := 0.0
var _tele_node: Node3D
var _slam_at := Vector3.ZERO


func _process(delta: float) -> void:
	if not is_alive():
		if _tele_node != null and is_instance_valid(_tele_node):
			_tele_node.queue_free()
		return
	if _tele != "":
		_tick_tele(delta)
		return
	super._process(delta)
	spin_cd -= delta
	slam_cd -= delta
	if not is_alive() or is_stunned() or _swing_left >= 0.0 or _model.is_busy():  # 휘두르는 중이면 모션이 다 끝난 뒤에 패턴
		return
	var near = _nearest_hero()
	if near == null:
		return
	var d := Formation.flat_distance(global_position, near.global_position)
	if spin_cd <= 0.0 and d <= SPIN_R + 0.5:
		spin()
	elif slam_cd <= 0.0 and d <= SLAM_AHEAD + SLAM_R:
		slam(near)


func _nearest_hero():
	var best = null
	var best_d := INF
	for h in get_tree().get_nodes_in_group("heroes"):
		if not h.is_alive() or h.is_on_wall():
			continue
		var d := Formation.flat_distance(global_position, h.global_position)
		if d < best_d:
			best_d = d
			best = h
	return best


## 회전 베기 예고: 발밑 원 + 돌기 모션(한 바퀴를 다 도는 순간 = 원이 다 차는 순간).
func spin() -> void:
	spin_cd = SPIN_SEC
	_start_tele("spin", TELE_SPIN)
	_tele_node = Fx.telegraph_circle(get_parent(), global_position, SPIN_R, TELE_SPIN)
	_model.play_cast(SPIN_ANIM, TELE_SPIN)


## 대지 가르기 예고: 그 영웅 쪽 앞 원 + 도끼를 머리 위로 들었다 내려찍기.
func slam(h) -> void:
	slam_cd = SLAM_SEC
	var dir: Vector3 = h.global_position - global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.BACK
	_slam_at = Vector3(global_position.x, 0.0, global_position.z) + dir * SLAM_AHEAD
	_model.face(dir)
	_start_tele("slam", TELE_SLAM)
	_tele_node = Fx.telegraph_circle(get_parent(), _slam_at, SLAM_R, TELE_SLAM)
	_model.play_cast(SLAM_ANIM, TELE_SLAM)


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
	if kind == "spin":
		_spin_hit()
	else:
		_slam_hit()


func _spin_hit() -> void:
	spins += 1
	var at := Vector3(global_position.x, 0.0, global_position.z)
	Fx.impact(get_parent(), at, SPIN_COLOR, SPIN_R * 0.7, 1)
	for h in get_tree().get_nodes_in_group("heroes"):
		if h.is_alive() and not h.is_on_wall() and Formation.flat_distance(at, h.global_position) <= SPIN_R:
			h.take_damage(hit_damage() * SPIN_MULT, self)
	_atk_cd = float(_stats.atk_interval)


func _slam_hit() -> void:
	slams += 1
	Fx.quake(get_parent(), _slam_at, SLAM_R, 1)
	Fx.impact(get_parent(), _slam_at, DUST_COLOR, SLAM_R * 0.7, 2)
	Fx.dust(get_parent(), _slam_at)
	for h in get_tree().get_nodes_in_group("heroes"):
		if h.is_alive() and not h.is_on_wall() and Formation.flat_distance(_slam_at, h.global_position) <= SLAM_R:
			h.take_damage(hit_damage() * SLAM_MULT, self)
			h.apply_stun(STUN_SEC)
	_atk_cd = float(_stats.atk_interval)


func is_telegraphing() -> bool:
	return _tele != ""

extends "res://scripts/monster.gd"
## 데스나이트(개정 18 §4, 장비 던전 보스): monster.gd 아레나 모드(일반 공격 — 가로 베기·내려치기 번갈아, Art "attacks") + 패턴 둘.
## 패턴은 범위 예고(개정 26)부터: 바닥에 범위가 먼저 보이고 안이 빨갛게 차오르는 동안(TELE_*) 전용 모션을 하며 그 자리에 선다 —
## 다 차는 순간 그 범위 안에 있는 영웅만 맞는다(그 사이 범위 밖으로 옮기면 피한다).
## 휩쓸기: SWEEP_SEC마다 발밑 반경 SWEEP_R 원 예고(TELE_SWEEP초) + 대검 돌기 모션 → 원 안 영웅 모두에게 공격 × SWEEP_MULT(붉은 폭발).
## 돌진: CHARGE_SEC마다 가장 먼 영웅 쪽으로 너비 CHARGE_W 직선 예고(TELE_CHARGE초, 끝 = 예고 시작 때 그 영웅 자리) + 포효 모션 →
## 그 끝까지 CHARGE_SPEED로 곧게 달리며 길 위(너비 안)와 끝(사거리 안)에 있는 영웅마다 공격 피해 + 기절 STUN_SEC, 끝에서 내려친다.
## 예고·돌진 중에는 상태(독·감속·기절 등) 시간이 흐르지 않는다(보스가 한 번 시작한 패턴은 끝까지). 피해는 hit_damage(weaken 반영),
## 묶이면(root) 돌진을 미룬다. 쓰러지면 예고도 사라진다.

const SWEEP_SEC := 8.0
const SWEEP_R := 3.0
const SWEEP_MULT := 1.5
const TELE_SWEEP := 1.2
const SWEEP_ANIM := "2H_Melee_Attack_Spin"
const SWEEP_FRAC := 0.6  # 돌기 모션에서 대검이 한 바퀴를 다 돈 순간(손 궤적) = 원이 다 차는 순간
const CHARGE_SEC := 15.0
const CHARGE_SPEED := 14.0
const CHARGE_W := 2.2
const TELE_CHARGE := 1.0
const CHARGE_ANIM := "Taunt"  # 포효하며 예고가 차오른다
const RUN_ANIM := "Running_A"
const STUN_SEC := 1.0
const SWEEP_COLOR := Color(0.85, 0.12, 0.08)

var sweep_cd := SWEEP_SEC
var charge_cd := CHARGE_SEC
var sweeps := 0  # 테스트용
var charges := 0

var _tele := ""  # 예고 중인 패턴("sweep"·"charge", 없으면 "")
var _tele_t := 0.0
var _tele_node: Node3D
var _charge_from := Vector3.ZERO
var _charge_end := Vector3.ZERO  # 돌진이 멈추는 곳(예고 끝)
var _charging := false
var _charge_hit := {}  # 이번 돌진에 맞은 영웅 id


func _process(delta: float) -> void:
	if not is_alive():
		if _tele_node != null and is_instance_valid(_tele_node):
			_tele_node.queue_free()
		return
	if _charging:
		_tick_charge(delta)
		return
	if _tele != "":
		_tick_tele(delta)
		return
	super._process(delta)
	sweep_cd -= delta
	charge_cd -= delta
	if not is_alive() or is_stunned() or _swing_left >= 0.0:  # 휘두르는 중이면 다 휘두른 뒤에 패턴
		return
	if sweep_cd <= 0.0:
		sweep()
	elif charge_cd <= 0.0 and _root_t <= 0.0:  # 묶이면 돌진을 미룬다
		charge()


## 휩쓸기 예고 시작: 발밑 원 + 돌기 모션(돌기가 한 바퀴 다 도는 순간 = 원이 다 차는 순간).
func sweep() -> void:
	sweep_cd = SWEEP_SEC
	_start_tele("sweep", TELE_SWEEP)
	_tele_node = Fx.telegraph_circle(get_parent(), global_position, SWEEP_R, TELE_SWEEP)
	_model.play_cast(SWEEP_ANIM, TELE_SWEEP, SWEEP_FRAC)


## 돌진 예고 시작: 가장 먼 살아 있는 영웅 쪽 직선(끝 = 지금 그 영웅 자리) + 포효 모션.
func charge() -> void:
	charge_cd = CHARGE_SEC
	var far = null
	var far_d := -1.0
	for h in get_tree().get_nodes_in_group("heroes"):
		var d := Formation.flat_distance(global_position, h.global_position)
		if h.is_alive() and d > far_d:
			far_d = d
			far = h
	if far == null:
		return
	var to: Vector3 = far.global_position
	_charge_from = Vector3(global_position.x, 0.0, global_position.z)
	var dir := Vector3(to.x, 0.0, to.z) - _charge_from
	if dir.length() < 0.5:
		return
	_charge_end = Vector3(to.x, 0.0, to.z) - dir.normalized() * float(_stats.range) * 0.8  # 그 영웅 바로 앞에서 멈춘다
	_model.face(dir)
	_start_tele("charge", TELE_CHARGE)
	_tele_node = Fx.telegraph_lane(get_parent(), _charge_from, Vector3(to.x, 0.0, to.z) + dir.normalized() * 0.6, CHARGE_W, TELE_CHARGE)
	_model.play_cast(CHARGE_ANIM, TELE_CHARGE * 0.9)


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
	if kind == "sweep":
		_sweep_hit()
	else:
		charges += 1
		_charging = true
		_charge_hit.clear()
		_model.play_loop(RUN_ANIM, 1.4)


## 원이 다 찬 순간: 원 안 살아 있는 영웅 모두 공격 × 1.5.
func _sweep_hit() -> void:
	sweeps += 1
	Fx.blast(get_parent(), global_position, SWEEP_COLOR, SWEEP_R, false, 1, 1)
	for h in get_tree().get_nodes_in_group("heroes"):
		if h.is_alive() and Formation.flat_distance(global_position, h.global_position) <= SWEEP_R:
			h.take_damage(hit_damage() * SWEEP_MULT, self)


## 돌진: 예고 끝까지 곧게 달리며 길 위 영웅을 친다(영웅마다 한 번). 끝에서 내려치고 끝.
func _tick_charge(delta: float) -> void:
	var step := CHARGE_SPEED * delta
	var flat := Vector3(global_position.x, 0.0, global_position.z)
	_model.face(_charge_end - flat)
	var next := flat.move_toward(_charge_end, step)
	global_position = Vector3(next.x, global_position.y, next.z)
	for h in get_tree().get_nodes_in_group("heroes"):
		if not h.is_alive() or _charge_hit.has(h.get_instance_id()):
			continue
		if Formation.flat_distance(global_position, h.global_position) <= CHARGE_W * 0.5 + 0.3:
			_charge_hit[h.get_instance_id()] = true
			h.take_damage(hit_damage(), self)
			h.apply_stun(STUN_SEC)
			Fx.impact(get_parent(), Vector3(h.global_position.x, 0.0, h.global_position.z), SWEEP_COLOR, 0.8, 1)
	if next.distance_to(_charge_end) > 0.01:
		return
	_charging = false
	for h in get_tree().get_nodes_in_group("heroes"):  # 끝의 내려치기: 길 끝(돌진 대상 자리) 사거리 안 영웅
		if h.is_alive() and not _charge_hit.has(h.get_instance_id()) and Formation.flat_distance(global_position, h.global_position) <= float(_stats.range) + SWING_SLACK:
			_charge_hit[h.get_instance_id()] = true
			h.take_damage(hit_damage(), self)
			h.apply_stun(STUN_SEC)
	_atk_cd = float(_stats.atk_interval)
	_model.play_attack(float(_stats.atk_interval))
	Fx.quake(get_parent(), _charge_end, 1.6, 0)


func is_charging() -> bool:
	return _charging


func is_telegraphing() -> bool:
	return _tele != ""


## 돌진 중에는 밀리지 않는다(영웅을 밀쳐 낸다 — 겹침 해소).
func push_mass() -> float:
	return INF if is_charging() else super.push_mass()

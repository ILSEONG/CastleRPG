extends "res://scripts/monster.gd"
## 데스나이트(개정 18 §4, 장비 던전 보스): monster.gd 아레나 모드(일반 공격) + 패턴 둘.
## 휩쓸기: SWEEP_SEC마다 주변 SWEEP_R m 안 영웅 모두에게 공격 × SWEEP_MULT(붉은 충격파).
## 돌진: CHARGE_SEC마다 가장 먼 영웅에게 CHARGE_SPEED로 달려가 공격 피해 + 기절 STUN_SEC. CHARGE_MAX_SEC 안에 못 닿으면 그만둔다.
## 돌진 중에는 상태(독·감속·기절) 시간이 흐르지 않는다.

const SWEEP_SEC := 8.0
const SWEEP_R := 3.0
const SWEEP_MULT := 1.5
const CHARGE_SEC := 15.0
const CHARGE_SPEED := 14.0
const CHARGE_MAX_SEC := 2.0
const STUN_SEC := 1.0
const SWEEP_COLOR := Color(0.85, 0.12, 0.08)

var sweep_cd := SWEEP_SEC
var charge_cd := CHARGE_SEC
var sweeps := 0  # 테스트용
var charges := 0

var _charge_to = null  # 돌진 대상 영웅
var _charge_t := 0.0


func _process(delta: float) -> void:
	if not is_alive():
		return
	if _charge_to != null:
		_tick_charge(delta)
		return
	super._process(delta)
	if not is_alive() or is_stunned():
		return
	sweep_cd -= delta
	charge_cd -= delta
	if sweep_cd <= 0.0:
		sweep()
	elif charge_cd <= 0.0:
		charge()


## 휩쓸기: 반경 안 살아 있는 영웅 모두 공격 × 1.5.
func sweep() -> void:
	sweep_cd = SWEEP_SEC
	sweeps += 1
	_swing_left = -1.0
	_model.play_attack(float(_stats.atk_interval))
	Fx.blast(get_parent(), global_position, SWEEP_COLOR, SWEEP_R)
	for h in get_tree().get_nodes_in_group("heroes"):
		if h.is_alive() and Formation.flat_distance(global_position, h.global_position) <= SWEEP_R:
			h.take_damage(atk * SWEEP_MULT, self)


## 돌진 시작: 가장 먼 살아 있는 영웅.
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
	charges += 1
	_charge_to = far
	_charge_t = CHARGE_MAX_SEC
	_swing_left = -1.0


func _tick_charge(delta: float) -> void:
	_charge_t -= delta
	var h = _charge_to
	if not is_instance_valid(h) or not h.is_alive() or _charge_t <= 0.0:
		_charge_to = null
		return
	var to: Vector3 = h.global_position
	_model.face(to - global_position)
	if Formation.flat_distance(global_position, to) > float(_stats.range):
		_model.play_walk()
		global_position = global_position.move_toward(Vector3(to.x, 0.0, to.z), CHARGE_SPEED * delta)
		return
	_charge_to = null
	_atk_cd = float(_stats.atk_interval)
	_model.play_attack(float(_stats.atk_interval))
	h.take_damage(atk, self)
	h.apply_stun(STUN_SEC)


func is_charging() -> bool:
	return _charge_to != null


## 돌진 중에는 밀리지 않는다(영웅을 밀쳐 낸다 — 겹침 해소).
func push_mass() -> float:
	return INF if is_charging() else super.push_mass()

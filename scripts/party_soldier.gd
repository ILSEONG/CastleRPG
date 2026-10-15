extends "res://scripts/pvp_soldier.gd"
## 파티 퀘스트 병사(거미 여왕, party_battle.gd). 총력전 병사(pvp_soldier.gd) 그대로 — 조종 없이 가까운 적(거미 여왕·거미 부하·알, 그룹 "monsters")을
## 쫓아가 친다 — 에 세 가지를 바꾼다.
## 1) 능력치: 서버가 정한 값(자리의 soldiers [{type, tier, hp, atk}] — 모든 기기가 같은 값).
## 2) 적이 없으면 제자리(home)로 돌아간다(행군 방향으로 끝없이 걷지 않게).
## 3) 실시간 꼭두각시(puppet): 방장이 보낸 위치·체력·동작을 따라 그리기만.
## 4) 똑똑한 AI(조종은 없지만): 거미 알이 있으면 알부터 깨러 가고(party.priority_target), 여왕 범위 예고 안이면 바깥으로 비켜선다(party.escape_from).

var party  # party_battle.gd
var home := Vector3.ZERO
var owner_seat := 0  # 이 병사를 데려온 성주 자리
var puppet := false
var swings := 0
var _p_pos := Vector3.INF
var _p_face := Vector3.ZERO
var _p_walk := false
var _dodge_cd := 0.0
var _escape := Vector3.INF


## add_child 전에(setup 다음). stats = {hp, atk}(없으면 표 값).
func setup_party(stats: Dictionary, seat: int, p_home: Vector3) -> void:
	foes = "monsters"
	owner_seat = seat
	home = p_home
	if stats.has("hp") and float(stats.hp) > 0.0:
		hp_max = float(stats.hp)
		hp = hp_max
	if stats.has("atk") and float(stats.atk) > 0.0:
		atk = float(stats.atk)


func _process(delta: float) -> void:
	if puppet and not _dead:
		_puppet_tick(delta)
		return
	if party != null and not _dead and _knock_t <= 0.0 and _stun_t <= 0.0:
		_dodge_cd -= delta
		if _dodge_cd <= 0.0:
			_dodge_cd = 0.2
			_escape = party.escape_from(global_position, radius())
		if _escape != Vector3.INF:
			_swing = null
			_walk(_escape, delta)
			if Formation.flat_distance(global_position, _escape) < 0.2:
				_escape = Vector3.INF
			return
	var had := _swing != null
	super._process(delta)
	if _swing != null and not had:
		swings += 1


func _find_target():
	if party != null:
		var p = party.priority_target(global_position)
		if p != null:
			return p
	return super._find_target()


## 적이 없을 때: 제자리로(가까우면 서서 기다린다).
func _walk(to: Vector3, delta: float) -> void:
	if current_target() == null and _escape == Vector3.INF:
		if Formation.flat_distance(global_position, home) < 0.6:
			_set_walking(false)
			return
		to = home
	super._walk(to, delta)


# --- 꼭두각시 ---

## [x, z, 방향, 체력 비율, 걷는 중(0/1), 휘두른 횟수]
func puppet_row() -> Array:
	return [snappedf(global_position.x, 0.01), snappedf(global_position.z, 0.01), snappedf(_model.rotation.y, 0.01),
		snappedf(hp_ratio(), 0.001), 1 if _walking else 0, swings]


func puppet_apply(row: Array) -> void:
	if _dead or row.size() < 6:
		return
	var first := _p_pos == Vector3.INF
	_p_pos = Vector3(float(row[0]), 0.0, float(row[1]))
	if first:
		global_position = _p_pos
	_p_face = Vector3(sin(float(row[2])), 0.0, cos(float(row[2])))
	var new_hp := float(row[3]) * hp_max
	if new_hp < hp - 0.5:
		take_damage(hp - new_hp, DamageNumbers.Kind.HURT)
	elif new_hp > hp + 0.5:
		hp = new_hp
	if _dead:
		return
	var walk := int(row[4]) == 1
	if int(row[5]) != swings:
		swings = int(row[5])
		_model.play_attack(float(def.atk_interval))
	elif walk != _p_walk:
		_set_walking(walk)
	_p_walk = walk


func _puppet_tick(delta: float) -> void:
	if _p_pos == Vector3.INF:
		return
	global_position = global_position.lerp(_p_pos, minf(1.0, delta * 12.0))
	if _p_face.length() > 0.1:
		_face(_p_face)

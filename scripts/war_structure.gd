extends Node3D
## 공성전 구조물: 성문(면마다 하나)·성채. 공격 영웅의 표적(그룹 "monsters" — 수비 영웅과 같은 적 그룹)이고 움직이지 않는다.
## 성채는 몸통 하나(hp)와 면마다 치는 자리(proxy — link로 피해를 몸통에 넘긴다)로 나뉜다: 근접 영웅이 성채 외벽 앞에서 친다.
## 상태 효과(slow·stun …)는 받지 않는다(빈 함수). 머리(war_brain)는 구조물을 영웅보다 나중에 노린다(is_structure).

const DamageNumbers := preload("res://scripts/damage_numbers.gd")

signal broken(structure)

var kind := "gate"  # "gate" | "keep"
var side := -1  # 성문 면(성채 몸통 -1, 성채 치는 자리는 그 면)
var hp := 1.0
var hp_max := 1.0
var link  # 성채 치는 자리 → 몸통(피해·체력은 몸통 것)
var is_boss := false
var is_structure := true
var bar_h := 4.6
var _broken := false


func setup(p_kind: String, p_side: int, p_hp_max: float, p_hp: float) -> void:
	kind = p_kind
	side = p_side
	hp_max = maxf(1.0, p_hp_max)
	hp = clampf(p_hp, 0.0, hp_max)
	_broken = hp <= 0.0


func _ready() -> void:
	if not _body()._broken:
		add_to_group("monsters")
		add_to_group("war_structures")


func _body():
	return link if link != null else self


func is_alive() -> bool:
	return not _body()._broken


func hp_ratio() -> float:
	var b = _body()
	return b.hp / b.hp_max


func take_damage(amount: float, kind_shown = 0) -> void:
	var b = _body()
	if b._broken or amount <= 0.0:
		return
	b.hp = maxf(0.0, b.hp - amount)
	DamageNumbers.pop(self, amount, kind_shown if typeof(kind_shown) == TYPE_INT else DamageNumbers.Kind.HIT)
	if b.hp == 0.0:
		b.set_broken()


## 부서짐(피해로, 또는 온라인 꼭두각시가 방장 값을 받을 때). 몸통이면 치는 자리들도 표적에서 빠진다.
func set_broken() -> void:
	if _broken:
		return
	_broken = true
	hp = 0.0
	for n in get_tree().get_nodes_in_group("war_structures"):
		if n == self or n.link == self:
			n.remove_from_group("monsters")
	broken.emit(self)


func set_hp(v: float) -> void:
	var b = _body()
	if v < b.hp - 0.5:
		DamageNumbers.pop(self, b.hp - v, DamageNumbers.Kind.HIT)
	b.hp = clampf(v, 0.0, b.hp_max)
	if b.hp <= 0.0:
		b.set_broken()


func bar_height() -> float:
	return bar_h


func bar_scale() -> float:
	return 2.0


func radius() -> float:
	return 1.5


func is_on_wall() -> bool:
	return false


func apply_slow(_a, _b) -> void:
	pass


func apply_stun(_a) -> void:
	pass


func apply_poison(_a, _b) -> void:
	pass


func apply_dot(_a, _b, _c) -> void:
	pass


func apply_freeze(_a) -> void:
	pass


func apply_root(_a) -> void:
	pass


func apply_vulnerable(_a, _b) -> void:
	pass


func apply_weaken(_a, _b) -> void:
	pass


func knockback(_a, _b) -> void:
	pass


func taunt(_a, _b) -> void:
	pass


func has_status(_t) -> bool:
	return false


func is_controlled() -> bool:
	return false


func is_stunned() -> bool:
	return false

extends Node3D
## 성벽 4면 + 성문 4개 + 중앙 성채. 성문 HP의 진실은 GameState. 여기는 시각화와 위치 제공만.
## side: 0=N(-z) 1=E(+x) 2=S(+z) 3=W(-x)

const Balance := preload("res://scripts/balance.gd")
const Flat := preload("res://scripts/flat.gd")

const SIDE_DIR: Array[Vector3] = [
	Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0),
]
const WALL_H := 1.5
const WALL_T := 0.6
const GATE_W := 2.0

var _gate_meshes: Array = []


func _ready() -> void:
	var half := Balance.CASTLE_SIZE / 2.0
	var seg_len := (Balance.CASTLE_SIZE - GATE_W) / 2.0
	for side in 4:
		var dir := SIDE_DIR[side]
		var perp := _perp(side)
		var center := dir * half
		for s in [-1.0, 1.0]:
			var seg := Flat.box(_wall_size(perp, seg_len), Flat.WALL)
			seg.position += center + perp * s * (GATE_W / 2.0 + seg_len / 2.0)
			add_child(seg)
		var gate := Flat.box(_wall_size(perp, GATE_W), Flat.GATE)
		gate.position += center
		add_child(gate)
		_gate_meshes.append(gate)
		var area := Area3D.new()
		area.collision_layer = 2
		area.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = _wall_size(perp, GATE_W) + Vector3(1.0, 1.0, 1.0)
		cs.shape = shape
		area.add_child(cs)
		area.position = center + Vector3(0, WALL_H / 2.0, 0)
		area.set_meta("side", side)
		add_child(area)
	add_child(Flat.box(Vector3(3, 3, 3), Flat.KEEP))
	GameState.gate_hp_changed.connect(_on_gate_hp_changed)


func gate_position(side: int) -> Vector3:
	return SIDE_DIR[side] * (Balance.CASTLE_SIZE / 2.0)


## 몬스터가 성문을 공격하려고 멈추는 지점 (성문 바로 바깥).
func gate_target(side: int) -> Vector3:
	return gate_position(side) + SIDE_DIR[side] * 0.8


## 성문 바깥 GATE_STAND_OFFSET 지점. 초기 배치는 영웅 i → 성문 i % 4 이므로
## 슬롯 = i / 4 (4명이면 전원 슬롯 0 = 성문 정면 중앙, 8·12명이면 좌우로 1.2씩).
## ponytail: 슬롯이 영웅 index 고정이라, 같은 슬롯 영웅 둘을 같은 성문으로 옮기면 겹친다. 겹침이 문제되면 성문별 점유 슬롯 배정으로 교체.
const STAND_SLOT_OFFSETS := [0.0, -1.2, 1.2]


func hero_stand_position(side: int, hero_index: int) -> Vector3:
	var slot := floori(hero_index / 4.0) % STAND_SLOT_OFFSETS.size()
	return gate_position(side) + SIDE_DIR[side] * Balance.GATE_STAND_OFFSET \
		+ _perp(side) * STAND_SLOT_OFFSETS[slot]


func keep_position() -> Vector3:
	return Vector3.ZERO


func spawn_position(side: int) -> Vector3:
	return SIDE_DIR[side] * Balance.SPAWN_DISTANCE + _perp(side) * randf_range(-3.0, 3.0)


func _perp(side: int) -> Vector3:
	var dir := SIDE_DIR[side]
	return Vector3(-dir.z, 0, dir.x)


func _wall_size(perp: Vector3, length: float) -> Vector3:
	if absf(perp.x) > 0.5:
		return Vector3(length, WALL_H, WALL_T)
	return Vector3(WALL_T, WALL_H, length)


func _on_gate_hp_changed(side: int, hp: float, hp_max: float) -> void:
	var mi: MeshInstance3D = _gate_meshes[side]
	mi.visible = hp > 0.0
	var mat := mi.material_override as StandardMaterial3D
	mat.albedo_color = Flat.GATE.darkened(0.6 * (1.0 - hp / hp_max))

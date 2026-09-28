extends Node3D
## 성벽 4면(두께·높이 있는 벽) + 모서리 탑 + 성문 4개. 성문 HP의 진실은 GameState.
## 여기는 시각화·탭 판정 영역·위치 제공만. 크기는 GameState.keep_level의 내부 크기,
## 위치 계산은 Formation static 함수에 위임한다.
## side: 0=N(-z) 1=E(+x) 2=S(+z) 3=W(-x)

const Balance := preload("res://scripts/balance.gd")
const Flat := preload("res://scripts/flat.gd")
const Formation := preload("res://scripts/formation.gd")

const LAYER_GATE := 2
const LAYER_WALL := 8
const TAP_MARGIN := Vector3(1, 1, 1)  # 탭 판정 박스 여유

var half: float = 0.0
var _gate_meshes: Array = []


func _ready() -> void:
	half = Balance.interior_half(GameState.keep_level)
	var seg_len := half + Balance.WALL_T - Balance.GATE_W / 2.0  # 성문 옆 벽 한 토막 (모서리 바깥까지)
	for side in 4:
		var perp := Formation.perp(side)
		var center := Formation.gate_position(half, side)
		for s in [-1.0, 1.0]:
			var seg_center: Vector3 = center + perp * s * (Balance.GATE_W + seg_len) / 2.0
			var seg_size := _along(perp, seg_len, Balance.WALL_H, Balance.WALL_T)
			var seg := Flat.box(seg_size, Flat.WALL)
			seg.position += seg_center
			add_child(seg)
			_add_tap_area(seg_center, seg_size, LAYER_WALL, side)
		var door := Flat.box(_along(perp, Balance.GATE_W, Balance.WALL_H, Balance.WALL_T * 0.6), Flat.GATE)
		door.position += center
		add_child(door)
		_gate_meshes.append(door)
		_add_tap_area(center, _along(perp, Balance.GATE_W, Balance.WALL_H, Balance.WALL_T), LAYER_GATE, side)
	var c := half + Balance.WALL_T / 2.0
	for corner in [Vector3(c, 0, c), Vector3(-c, 0, c), Vector3(c, 0, -c), Vector3(-c, 0, -c)]:
		var tower := Flat.box(Vector3(Balance.TOWER_SIZE, Balance.TOWER_H, Balance.TOWER_SIZE), Flat.TOWER)
		tower.position += corner
		add_child(tower)
	GameState.gate_hp_changed.connect(_on_gate_hp_changed)


func gate_target(side: int) -> Vector3:
	return Formation.gate_target(half, side)


func keep_target(side: int) -> Vector3:
	return Formation.keep_target(side)


func slot_position(side: int, post: int, slot: int) -> Vector3:
	return Formation.slot_position(half, side, post, slot)


func spawn_position(side: int) -> Vector3:
	return Formation.spawn_center(half, side) \
		+ Formation.perp(side) * randf_range(-Balance.SPAWN_SPREAD, Balance.SPAWN_SPREAD)


## perp 방향 길이 length, 높이 height, 면 방향 두께 thickness 인 박스 크기.
func _along(perp: Vector3, length: float, height: float, thickness: float) -> Vector3:
	if absf(perp.x) > 0.5:
		return Vector3(length, height, thickness)
	return Vector3(thickness, height, length)


func _add_tap_area(ground_center: Vector3, size: Vector3, layer: int, side: int) -> void:
	var area := Area3D.new()
	area.collision_layer = layer
	area.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size + TAP_MARGIN
	cs.shape = shape
	area.add_child(cs)
	area.position = ground_center + Vector3(0, size.y / 2.0, 0)
	area.set_meta("side", side)
	add_child(area)


func _on_gate_hp_changed(side: int, hp: float, hp_max: float) -> void:
	var mi: MeshInstance3D = _gate_meshes[side]
	mi.visible = hp > 0.0
	var mat := mi.material_override as StandardMaterial3D
	mat.albedo_color = Flat.GATE.darkened(0.6 * (1.0 - hp / hp_max))

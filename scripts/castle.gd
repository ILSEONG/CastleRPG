extends Node3D
## 성벽 4면 + 모서리 탑 + 성문 4개 + 계단 8개 (코드로 만든 로우폴리 메시, TownKit). 성문 HP의 진실은 GameState.
## 여기는 시각화·탭 판정 영역·위치 제공만. 크기는 GameState.keep_level의 내부 크기,
## 위치 계산은 Formation static 함수에 위임한다.
## 성벽은 "성문 가장자리 ~ 모서리 탑 가장자리" 구간을 메시 한 토막으로 채운다.
## side: 0=N(-z) 1=E(+x) 2=S(+z) 3=W(-x)

const Balance := preload("res://scripts/balance.gd")
const Art := preload("res://scripts/art.gd")
const Formation := preload("res://scripts/formation.gd")
const TownKit := preload("res://scripts/town_kit.gd")

const LAYER_GATE := 2
const LAYER_WALL := 8
const TAP_MARGIN := Vector3(1, 1, 1)  # 탭 판정 박스 여유

var half: float = 0.0
var _gate_doors: Array = []  # side -> 문짝 MeshInstance3D


func _ready() -> void:
	half = Balance.interior_half(GameState.keep_level)
	var c := half + Balance.WALL_T / 2.0  # 성벽 중심선
	var run := c - Balance.TOWER_SIZE / 2.0 - Balance.GATE_W / 2.0
	var wall_mesh := TownKit.wall_run(run)
	var gate_mesh := TownKit.gatehouse()
	var doors_mesh := TownKit.gate_doors()
	var stairs_mesh := TownKit.stairs()
	for side in 4:
		var dir: Vector3 = Formation.SIDE_DIR[side]
		var perp := Formation.perp(side)
		var center := Formation.gate_position(half, side)
		var facing := Basis(Vector3.UP, atan2(dir.x, dir.z))  # 로컬 +Z가 성 바깥을 보게
		_add_mesh(gate_mesh, Transform3D(facing, center))
		_gate_doors.append(_add_mesh(doors_mesh, Transform3D(facing, center)))
		_add_tap_area(center, _along(perp, Balance.GATE_W, Balance.WALL_H, Balance.WALL_T), LAYER_GATE, side)
		var seg_len := half + Balance.WALL_T - Balance.GATE_W / 2.0
		for s in [-1.0, 1.0]:
			_add_mesh(wall_mesh, Transform3D(facing, center + perp * s * (Balance.GATE_W + run) / 2.0))
			var bottom := Formation.stair_bottom(half, side, s)
			var up := Formation.stair_top(half, side, s) - bottom
			var x := Vector3(up.x, 0, up.z).normalized()  # 로컬 +X: 아랫단 → 윗단
			_add_mesh(stairs_mesh, Transform3D(Basis(x, Vector3.UP, x.cross(Vector3.UP)), bottom))
			var seg_center: Vector3 = center + perp * s * (Balance.GATE_W + seg_len) / 2.0
			_add_tap_area(seg_center, _along(perp, seg_len, Balance.WALL_H, Balance.WALL_T), LAYER_WALL, side)
	var tower_mesh := TownKit.corner_tower()
	for corner in [Vector3(c, 0, c), Vector3(-c, 0, c), Vector3(c, 0, -c), Vector3(-c, 0, -c)]:
		_add_mesh(tower_mesh, Transform3D(Basis.IDENTITY, corner))
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


func _add_mesh(m: Mesh, xf: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = Art.lowpoly_vc_material()
	mi.transform = xf
	add_child(mi)
	return mi


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


func _on_gate_hp_changed(side: int, hp: float, _hp_max: float) -> void:
	_gate_doors[side].visible = hp > 0.0

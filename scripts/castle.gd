extends Node3D
## 성벽 4면 + 모서리 탑 + 성문 4개 (KayKit 모델). 성문 HP의 진실은 GameState.
## 여기는 시각화·탭 판정 영역·위치 제공만. 크기는 GameState.keep_level의 내부 크기,
## 위치 계산은 Formation static 함수에 위임한다.
## 성벽은 wall_straight 조각을 "성문 가장자리 ~ 모서리 탑 가장자리" 구간에 균등 분할로 채운다.
## side: 0=N(-z) 1=E(+x) 2=S(+z) 3=W(-x)

const Balance := preload("res://scripts/balance.gd")
const Art := preload("res://scripts/art.gd")
const Formation := preload("res://scripts/formation.gd")

const LAYER_GATE := 2
const LAYER_WALL := 8
const TAP_MARGIN := Vector3(1, 1, 1)  # 탭 판정 박스 여유

var half: float = 0.0
var _gate_doors: Array = []  # side -> [문짝 Node3D 두 개]


func _ready() -> void:
	half = Balance.interior_half(GameState.keep_level)
	var c := half + Balance.WALL_T / 2.0  # 성벽 중심선
	var run := c - Balance.TOWER_SIZE / 2.0 - Balance.GATE_W / 2.0
	var pieces := maxi(1, roundi(run / Art.WALL_PIECE_TARGET))
	var piece_len := run / pieces
	var sy := Balance.WALL_H / Art.WALL_MODEL_H
	var sz := Balance.WALL_T / Art.WALL_MODEL_T
	for side in 4:
		var dir: Vector3 = Formation.SIDE_DIR[side]
		var perp := Formation.perp(side)
		var center := Formation.gate_position(half, side)
		var yaw := atan2(dir.x, dir.z)  # 모델 정면(+Z)이 성 바깥을 보게
		var gate := _place(Art.GATE_MODEL, center, yaw, Vector3(Balance.GATE_W / Art.WALL_MODEL_LEN, sy, sz))
		var doors: Array = []
		for door_name in Art.GATE_DOORS:
			doors.append(gate.find_child(door_name, true, false))
		_gate_doors.append(doors)
		_add_tap_area(center, _along(perp, Balance.GATE_W, Balance.WALL_H, Balance.WALL_T), LAYER_GATE, side)
		var seg_len := half + Balance.WALL_T - Balance.GATE_W / 2.0
		for s in [-1.0, 1.0]:
			for i in pieces:
				var along: float = Balance.GATE_W / 2.0 + piece_len * (i + 0.5)
				_place(Art.WALL_MODEL, center + perp * s * along, yaw, Vector3(piece_len / Art.WALL_MODEL_LEN, sy, sz))
			var seg_center: Vector3 = center + perp * s * (Balance.GATE_W + seg_len) / 2.0
			_add_tap_area(seg_center, _along(perp, seg_len, Balance.WALL_H, Balance.WALL_T), LAYER_WALL, side)
	for corner in [Vector3(c, 0, c), Vector3(-c, 0, c), Vector3(c, 0, -c), Vector3(-c, 0, -c)]:
		_place(Art.TOWER_MODEL, corner, 0.0, Vector3.ONE * Art.TOWER_SCALE)
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


func _place(path: String, pos: Vector3, yaw: float, scl: Vector3) -> Node3D:
	var n := Art.instance(path)
	n.position = pos
	n.rotation.y = yaw
	n.scale = scl
	add_child(n)
	return n


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
	for door in _gate_doors[side]:
		door.visible = hp > 0.0

extends Node3D
## 성벽 4면 + 모서리 탑 + 면마다 성문(성 내부 단계마다 1·2·3개, Formation.gate_offsets — 내구도는 면마다 하나) + 성문마다 계단 2개 (코드로 만든 로우폴리 메시, TownKit). 성문 HP의 진실은 GameState.
## 여기는 시각화·탭 판정 영역·위치 제공만. 크기는 성채 레벨의 단계 내부 크기(GameData.interior_half, 개정 12) —
## 만들 때 한 번 정한다(단계가 바뀌면 main이 월드를 다시 만든다). 위치 계산은 Formation static 함수에 위임한다.
## 성벽은 "성문 가장자리 ~ 모서리 탑 중심선" 구간을 메시 한 토막으로 채운다(8각 탑과 성벽 모서리 사이에 틈이 없게 탑 안까지).
## side: 0=N(-z) 1=E(+x) 2=S(+z) 3=W(-x)

const Balance := preload("res://scripts/balance.gd")
const GameData := preload("res://scripts/game_data.gd")
const Art := preload("res://scripts/art.gd")
const Formation := preload("res://scripts/formation.gd")
const TownKit := preload("res://scripts/town_kit.gd")

const LAYER_GATE := 2
const LAYER_WALL := 8
const TAP_MARGIN := Vector3(1, 1, 1)  # 탭 판정 박스 여유
const SIDE_TAG_Y := Balance.WALL_H + 2.5  # 문루(기둥 지붕 끝 ~5.3 m) 위 방향 글자 이름표 아랫변 기준점 높이

var half: float = 0.0
var side_anchors: Array = []  # side -> 문루 위 방향 글자(북·동·남·서) 이름표 기준점 — 그리기는 world_tags.gd(화면 공간, 개정 15)
var _gate_doors: Array = []  # side -> [문짝 MeshInstance3D](성문마다)


func _ready() -> void:
	half = GameData.interior_half(GameState.building_level(GameData.KEEP))
	var c := half + Balance.WALL_T / 2.0  # 성벽 중심선
	var offs := Formation.gate_offsets(half)
	var gate_mesh := TownKit.gatehouse()
	var doors_mesh := TownKit.gate_doors()
	var stairs_mesh := TownKit.stairs()
	var walls := {}  # 토막 길이 → 메시
	for side in 4:
		var dir: Vector3 = Formation.SIDE_DIR[side]
		var perp := Formation.perp(side)
		var facing := Basis(Vector3.UP, atan2(dir.x, dir.z))  # 로컬 +Z가 성 바깥을 보게
		side_anchors.append(Formation.gate_position(half, side) + Vector3(0, SIDE_TAG_Y, 0))
		_gate_doors.append([])
		# 성벽 토막: 모서리 탑 중심선 ~ 첫 성문 가장자리, 성문 사이, 마지막 성문 ~ 탑 중심선
		var edges: Array = [-c]
		for at in offs:
			edges.append_array([at - Balance.GATE_W / 2.0, at + Balance.GATE_W / 2.0])
		edges.append(c)
		for i in range(0, edges.size(), 2):
			var a: float = edges[i]
			var b: float = edges[i + 1]
			var run := b - a
			if not walls.has(run):
				walls[run] = TownKit.wall_run(run)
			_add_mesh(walls[run], Transform3D(facing, Formation.gate_position(half, side, (a + b) / 2.0)))
			var ta := maxf(a, -(half + Balance.WALL_T))  # 탭 판정은 성벽 바깥 모서리까지
			var tb := minf(b, half + Balance.WALL_T)
			_add_tap_area(Formation.gate_position(half, side, (ta + tb) / 2.0), _along(perp, tb - ta, Balance.WALL_H, Balance.WALL_T), LAYER_WALL, side)
		for k in offs.size():
			var at: float = offs[k]
			var center := Formation.gate_position(half, side, at)
			_add_mesh(gate_mesh, Transform3D(facing, center))
			_gate_doors[side].append(_add_mesh(doors_mesh, Transform3D(facing, center)))
			_add_tap_area(center, _along(perp, Balance.GATE_W, Balance.WALL_H, Balance.WALL_T), LAYER_GATE, side, at)
			for e in [-1.0, 1.0]:
				var bottom := Formation.stair_bottom(half, side, e, at)
				var up := Formation.stair_top(half, side, e, at) - bottom
				var x := Vector3(up.x, 0, up.z).normalized()  # 로컬 +X: 아랫단 → 윗단
				_add_mesh(stairs_mesh, Transform3D(Basis(x, Vector3.UP, x.cross(Vector3.UP)), bottom))
	var tower_mesh := TownKit.corner_tower()
	for corner in [Vector3(c, 0, c), Vector3(-c, 0, c), Vector3(c, 0, -c), Vector3(-c, 0, -c)]:
		_add_mesh(tower_mesh, Transform3D(Basis.IDENTITY, corner))
	GameState.gate_hp_changed.connect(_on_gate_hp_changed)


## 면 side의 성문(옆 위치 at) 앞 치는 자리.
func gate_target(side: int, at := 0.0) -> Vector3:
	return Formation.gate_target(half, side, at)


func keep_target(side: int) -> Vector3:
	return Formation.keep_target(side)


func slot_position(side: int, post: int, slot: int) -> Vector3:
	return Formation.slot_position(half, side, post, slot)


## 스폰 지점: 면의 성문 하나(무작위 — 성문이 여럿이면 나눠 친다) 앞에서 옆으로 ±SPAWN_SPREAD. 무리(lanes마리)면 그 폭을 lanes칸으로 나눠
## lane번째 칸 가운데 절반 안 — 같이 나온 몬스터가 겹치지 않는다(3마리면 칸 중심 −4·0·4 m, 이웃과 2 m 이상). 같은 무리는 같은 성문(at).
func spawn_position(side: int, lane := 0, lanes := 1, at := NAN) -> Vector3:
	if is_nan(at):
		var offs := Formation.gate_offsets(half)
		at = offs[randi() % offs.size()]
	var w := 2.0 * Balance.SPAWN_SPREAD / maxi(lanes, 1)
	var jitter := w / 2.0 if lanes <= 1 else w / 4.0
	var off := -Balance.SPAWN_SPREAD + w * (lane + 0.5) + randf_range(-jitter, jitter)
	return Formation.spawn_center(half, side, at) + Formation.perp(side) * off


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


func _add_tap_area(ground_center: Vector3, size: Vector3, layer: int, side: int, at := NAN) -> void:
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
	if not is_nan(at):
		area.set_meta("at", at)  # 성문 탭: 그 성문의 옆 위치(그 성문 앞 빈 자리로)
	add_child(area)


## 성문 내구도는 면마다 하나(같은 면 성문끼리 공유): 부서지면 그 면 문짝이 모두 열린다.
func _on_gate_hp_changed(side: int, hp: float, _hp_max: float) -> void:
	for d in _gate_doors[side]:
		d.visible = hp > 0.0

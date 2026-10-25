extends Node3D
## 성벽 4면 + 모서리 탑 + 면마다 성문(성 내부 단계마다 1·2·3개, Formation.gate_offsets — 내구도는 면마다 하나) + 성문마다 계단 2개 (코드로 만든 로우폴리 메시, TownKit). 성문 HP의 진실은 GameState.
## 여기는 시각화·탭 판정 영역·위치 제공만. 크기는 성채 레벨의 단계 내부 크기(GameData.interior_half, 개정 12) —
## 만들 때 한 번 정한다(단계가 바뀌면 main이 월드를 다시 만든다). 위치 계산은 Formation static 함수에 위임한다.
## 성벽은 "성문 가장자리 ~ 모서리 탑 중심선" 구간을 메시 한 토막으로 채운다(8각 탑과 성벽 모서리 사이에 틈이 없게 탑 안까지).
## 성 모습 단계(GameData.castle_look — 성채 Lv 5·10·15·22·30): 문루·모서리 탑 레시피와 성벽 장식(깃발·돌림띠)이 단계마다 웅장해진다.
## 단계는 성 크기와 따로 바뀌므로 메시만 _look 아래에 다시 만든다(탭 판정·위치는 그대로).
## side: 0=N(-z) 1=E(+x) 2=S(+z) 3=W(-x)

const Lang := preload("res://scripts/lang.gd")

const Balance := preload("res://scripts/balance.gd")
const GameData := preload("res://scripts/game_data.gd")
const Art := preload("res://scripts/art.gd")
const Formation := preload("res://scripts/formation.gd")
const TownKit := preload("res://scripts/town_kit.gd")

const LAYER_GATE := 2
const LAYER_WALL := 8
const TAP_MARGIN := Vector3(1, 1, 1)  # 탭 판정 박스 여유
const SIDE_TAG_Y := Balance.WALL_H + 2.5  # 문루(기둥 지붕 끝 ~5.3 m) 위 방향 글자 이름표 아랫변 기준점 높이
static var LOOK_TEXT := Lang.t("castle.look_text")
const LOOK_TEXT_DELAY := 1.8  # 초(HUD 알림 TOAST_SEC 1.6 뒤)

var half: float = 0.0
var side_anchors: Array = []  # side -> 문루 위 방향 글자(북·동·남·서) 이름표 기준점 — 그리기는 world_tags.gd(화면 공간, 개정 15)
var look := 0  # 지금 그린 성 모습 단계(GameData.castle_look)
var _gate_doors: Array = []  # side -> [문짝 MeshInstance3D](성문마다)
var _look: Node3D  # 성 메시 묶음(성 모습 단계가 바뀌면 통째로 다시 만든다)


func _ready() -> void:
	half = GameData.interior_half(GameState.building_level(GameData.KEEP))
	var c := half + Balance.WALL_T / 2.0  # 성벽 중심선
	var offs := Formation.gate_offsets(half)
	for side in 4:
		var perp := Formation.perp(side)
		side_anchors.append(Formation.gate_position(half, side) + Vector3(0, SIDE_TAG_Y, 0))
		var edges := _wall_edges(c, offs)
		for i in range(0, edges.size(), 2):
			var ta := maxf(edges[i], -(half + Balance.WALL_T))  # 탭 판정은 성벽 바깥 모서리까지
			var tb := minf(edges[i + 1], half + Balance.WALL_T)
			_add_tap_area(Formation.gate_position(half, side, (ta + tb) / 2.0), _along(perp, tb - ta, Balance.WALL_H, Balance.WALL_T), LAYER_WALL, side)
		for at in offs:
			_add_tap_area(Formation.gate_position(half, side, at), _along(perp, Balance.GATE_W, Balance.WALL_H, Balance.WALL_T), LAYER_GATE, side, at)
	_build_look(GameData.castle_look(GameState.building_level(GameData.KEEP)))
	GameState.gate_hp_changed.connect(_on_gate_hp_changed)
	Economy.changed.connect(_sync_look)


## 성벽 토막 경계(옆 위치): 모서리 탑 중심선 ~ 첫 성문 가장자리, 성문 사이, 마지막 성문 ~ 탑 중심선 — [a0, b0, a1, b1, …].
static func _wall_edges(c: float, offs: Array) -> Array:
	var edges: Array = [-c]
	for at in offs:
		edges.append_array([at - Balance.GATE_W / 2.0, at + Balance.GATE_W / 2.0])
	edges.append(c)
	return edges


## 성 메시(성벽·문루·문짝·계단·모서리 탑·장식)를 성 모습 단계 lk로 만든다. 문짝은 지금 성문 내구도대로 열고 닫는다.
func _build_look(lk: int) -> void:
	if _look != null:
		_look.queue_free()
	look = lk
	_look = Node3D.new()
	add_child(_look)
	_gate_doors.clear()
	var c := half + Balance.WALL_T / 2.0
	var offs := Formation.gate_offsets(half)
	var gate_mesh := TownKit.gatehouse(lk)
	var doors_mesh := TownKit.gate_doors()
	var stairs_mesh := TownKit.stairs()
	_add_tower_taps(lk)
	var walls := {}  # 토막 길이 → 메시
	for side in 4:
		var dir: Vector3 = Formation.SIDE_DIR[side]
		var facing := Basis(Vector3.UP, atan2(dir.x, dir.z))  # 로컬 +Z가 성 바깥을 보게
		_gate_doors.append([])
		var edges := _wall_edges(c, offs)
		for i in range(0, edges.size(), 2):
			var run: float = edges[i + 1] - edges[i]
			if not walls.has(run):
				walls[run] = TownKit.wall_run(run)
			_add_mesh(walls[run], Transform3D(facing, Formation.gate_position(half, side, (edges[i] + edges[i + 1]) / 2.0)))
		for at in offs:
			var center := Formation.gate_position(half, side, at)
			_add_mesh(gate_mesh, Transform3D(facing, center))
			var door := _add_mesh(doors_mesh, Transform3D(facing, center))
			door.visible = side >= GameState.gate_hp.size() or GameState.gate_hp[side] > 0.0
			_gate_doors[side].append(door)
			for e in [-1.0, 1.0]:
				var bottom := Formation.stair_bottom(half, side, e, at)
				var up := Formation.stair_top(half, side, e, at) - bottom
				var x := Vector3(up.x, 0, up.z).normalized()  # 로컬 +X: 아랫단 → 윗단
				_add_mesh(stairs_mesh, Transform3D(Basis(x, Vector3.UP, x.cross(Vector3.UP)), bottom))
	var tower_mesh := TownKit.corner_tower(lk)
	for corner in [Vector3(c, 0, c), Vector3(-c, 0, c), Vector3(c, 0, -c), Vector3(-c, 0, -c)]:
		_add_mesh(tower_mesh, Transform3D(Basis.IDENTITY, corner))
	var dressing := TownKit.castle_dressing(half, offs, lk)
	if dressing != null:
		_add_mesh(dressing, Transform3D.IDENTITY)


## 성채 레벨이 성 모습 단계를 넘었다(성 크기는 그대로일 때 — 크기가 바뀌면 main이 월드를 다시 만든다): 메시만 새 단계로.
func _sync_look() -> void:
	var lv := GameState.building_level(GameData.KEEP)
	var lk := GameData.castle_look(lv)
	if lk == look or GameData.interior_half(lv) != half:
		return
	var grew := lk > look
	_build_look(lk)
	if grew:  # "성채 Lv N 완료" 알림(buildings.gd) 다음에 띄운다
		get_tree().create_timer(LOOK_TEXT_DELAY).timeout.connect(_look_notice.bind(lk))


## 단계가 그사이 그대로일 때만 알린다(되돌렸으면 조용히 — 성이 해제되면 연결도 끊긴다).
func _look_notice(lk: int) -> void:
	if look == lk:
		Economy.notice.emit(LOOK_TEXT)


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
	_look.add_child(mi)
	return mi


## perp 방향 길이 length, 높이 height, 면 방향 두께 thickness 인 박스 크기.
func _along(perp: Vector3, length: float, height: float, thickness: float) -> Vector3:
	if absf(perp.x) > 0.5:
		return Vector3(length, height, thickness)
	return Vector3(thickness, height, length)


## 모서리 탑 탭 영역(사용자 2026-10-25 성문 위 성벽 탭과 같이): 탑 몸통 + 지붕 절반 높이까지 성벽 탭(LAYER_WALL, "tower") —
## 탑 윗부분을 눌러도 레이가 탑 너머 성 밖 바닥으로 빠지지 않고, 누른 쪽 면의 성벽 위 끝자리로 간다(unit_picker).
## 탑 크기가 성 모습 단계마다 달라 _look 아래에 둔다(단계가 바뀌면 같이 다시 만든다).
func _add_tower_taps(lk: int) -> void:
	var c := half + Balance.WALL_T / 2.0
	var w: float = float(TownKit.LOOK_TOWER_R[lk]) * 2.0
	var h: float = float(TownKit.LOOK_TOWER_H[lk]) + float(TownKit.LOOK_TOWER_ROOF[lk]) * 0.5
	for k in 4:
		var corner: Vector3 = (Formation.SIDE_DIR[k] + Formation.SIDE_DIR[(k + 1) % 4]) * c
		var area := _add_tap_area(corner, Vector3(w, h, w), LAYER_WALL, k, NAN, _look)
		area.set_meta("tower", true)


func _add_tap_area(ground_center: Vector3, size: Vector3, layer: int, side: int, at := NAN, parent: Node = null) -> Area3D:
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
	(parent if parent != null else self).add_child(area)
	return area


## 성문 내구도는 면마다 하나(같은 면 성문끼리 공유): 부서지면 그 면 문짝이 모두 열린다.
func _on_gate_hp_changed(side: int, hp: float, _hp_max: float) -> void:
	for d in _gate_doors[side]:
		d.visible = hp > 0.0

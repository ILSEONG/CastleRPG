extends Node3D
## 성 안 건물(KayKit 모델, 기능 없음 — 서브프로젝트 2)과 성 밖 자연물 장식.
## 건물은 모델 AABB를 재서 부지에 맞는 최대 균일 배율로 놓는다. 자연물은 시드 고정 난수로 흩는다.

const Balance := preload("res://scripts/balance.gd")
const Art := preload("res://scripts/art.gd")
const Formation := preload("res://scripts/formation.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

var half: float = 16.0  # 성 내부 절반 크기. main이 add_child 전에 castle.half로 설정


func _ready() -> void:
	for b in Balance.BUILDINGS:
		_place_building(b)
	_scatter_nature()
	_ring_mountains()


func _place_building(b: Dictionary) -> void:
	var plot := Vector2(b.size.x * Balance.TILE - Art.BUILDING_GAP, b.size.y * Balance.TILE - Art.BUILDING_GAP)
	var center := Vector3((b.cell.x + b.size.x / 2.0) * Balance.TILE, 0, (b.cell.y + b.size.y / 2.0) * Balance.TILE)
	var model := Art.instance(Art.BUILDING_MODELS[b.id])
	var box := Art.model_aabb(model)
	var s := minf(plot.x / box.size.x, plot.y / box.size.z)
	model.scale = Vector3.ONE * s
	model.position = center - Vector3(box.get_center().x, box.position.y, box.get_center().z) * s
	add_child(model)
	var label := Label3D.new()
	label.text = b.name
	label.font = FONT
	label.font_size = 48
	label.outline_size = 12
	label.pixel_size = 0.03
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.modulate = Color(0.18, 0.18, 0.22)
	label.outline_modulate = Color(1, 1, 1, 0.9)
	label.position = center + Vector3(0, box.size.y * s + 1.0, 0)
	add_child(label)


## 성벽 근처·괴물 진입로(두 축)·서로 가까운 자리를 피해 나무·바위를 흩는다.
## 모델 종류별(그 모델의 메시마다) MultiMeshInstance3D 하나로 그린다 — 수백 개여도 그리기 호출 몇 번.
func _scatter_nature() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Art.NATURE_SEED
	var keep_out := half + Balance.WALL_T + Art.NATURE_CASTLE_MARGIN
	var lim := Balance.MAP_HALF - 4.0
	var placed: Array[Vector2] = []
	var by_model := {}  # 모델 경로 -> Array[Transform3D]
	var tries := 0
	while placed.size() < Art.NATURE_COUNT and tries < Art.NATURE_COUNT * 20:
		tries += 1
		var p := Vector2(rng.randf_range(-lim, lim), rng.randf_range(-lim, lim))
		if maxf(absf(p.x), absf(p.y)) < keep_out:
			continue
		if absf(p.x) < Art.LANE_HALF_WIDTH or absf(p.y) < Art.LANE_HALF_WIDTH:
			continue
		var crowded := false
		for q in placed:
			if p.distance_to(q) < Art.NATURE_MIN_GAP:
				crowded = true
				break
		if crowded:
			continue
		placed.append(p)
		var path: String = Art.NATURE_MODELS[rng.randi_range(0, Art.NATURE_MODELS.size() - 1)]
		var s := Art.NATURE_SCALE * rng.randf_range(0.8, 1.2)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * s)
		if not by_model.has(path):
			by_model[path] = []
		by_model[path].append(Transform3D(basis, Vector3(p.x, 0, p.y)))
	for path in by_model:
		_add_multimesh(path, by_model[path])


## 플레이 영역 바깥 띠에 로우폴리 바위 산을 한 바퀴 두르고 육각 받침은 땅에 묻는다(유닛은 들어가지 않는다). 시드 고정, 모델별 MultiMesh.
func _ring_mountains() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Art.BORDER_SEED
	var inner := Balance.MAP_HALF + Art.BORDER_INNER
	var outer := Balance.MAP_HALF + Art.BORDER_OUTER
	var steps := ceili(2.0 * outer / Art.BORDER_SPACING)
	var by_model := {}
	for side in 4:
		var dir: Vector3 = Formation.SIDE_DIR[side]
		var perp := Formation.perp(side)
		for i in steps + 1:
			var along := -outer + i * Art.BORDER_SPACING + rng.randf_range(-4.0, 4.0)
			var pos := dir * rng.randf_range(inner, outer) + perp * along
			var path: String = Art.BORDER_MODELS[rng.randi_range(0, Art.BORDER_MODELS.size() - 1)]
			var s := rng.randf_range(Art.BORDER_SCALE_MIN, Art.BORDER_SCALE_MAX)
			pos.y = -Art.BORDER_SINK * s
			var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * s)
			if not by_model.has(path):
				by_model[path] = []
			by_model[path].append(Transform3D(basis, pos))
	for path in by_model:
		_add_multimesh(path, by_model[path])


func _add_multimesh(path: String, placements: Array) -> void:
	var model := Art.instance(path)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var local := Art.relative_transform(mi, model)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var mesh := mi.mesh.duplicate() as Mesh
		for s in mesh.get_surface_count():
			mesh.surface_set_material(s, mi.get_active_material(s))
		mm.mesh = mesh
		mm.instance_count = placements.size()
		for i in placements.size():
			mm.set_instance_transform(i, placements[i] * local)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
	model.free()

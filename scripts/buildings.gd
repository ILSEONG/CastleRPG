extends Node3D
## 성 안 건물(KayKit 모델, 기능 없음 — 서브프로젝트 2)과 성 밖 자연물 장식.
## 건물은 모델 AABB를 재서 부지에 맞는 최대 균일 배율로 놓는다. 자연물은 시드 고정 난수로 흩는다.

const Balance := preload("res://scripts/balance.gd")
const Art := preload("res://scripts/art.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

var half: float = 16.0  # 성 내부 절반 크기. main이 add_child 전에 castle.half로 설정


func _ready() -> void:
	for b in Balance.BUILDINGS:
		_place_building(b)
	_scatter_nature()


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
	label.modulate = Color(0.18, 0.18, 0.22)
	label.outline_modulate = Color(1, 1, 1, 0.9)
	label.position = center + Vector3(0, box.size.y * s + 1.0, 0)
	add_child(label)


## 성벽 근처·괴물 진입로(두 축)·서로 가까운 자리를 피해 나무·바위를 흩는다.
func _scatter_nature() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Art.NATURE_SEED
	var keep_out := half + Balance.WALL_T + Art.NATURE_CASTLE_MARGIN
	var lim := Balance.MAP_HALF - 4.0
	var placed: Array[Vector2] = []
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
		var n := Art.instance(Art.NATURE_MODELS[rng.randi_range(0, Art.NATURE_MODELS.size() - 1)])
		n.position = Vector3(p.x, 0, p.y)
		n.rotation.y = rng.randf_range(0.0, TAU)
		n.scale = Vector3.ONE * Art.NATURE_SCALE * rng.randf_range(0.8, 1.2)
		add_child(n)

extends Node3D
## 성 안 건물(코드로 만든 로우폴리 메시, 기능 없음 — 서브프로젝트 2)과 성 밖 자연물·테두리 산 장식.
## 건물은 TownKit 레시피를 부지 중심에 그대로 놓는다(레시피가 부지 안에 맞춰져 있다 — 테스트).
## 자연물·산은 시드 고정 변형 몇 개를 시드 고정 난수로 흩고, 변형마다 MultiMesh 하나로 그린다.

const Balance := preload("res://scripts/balance.gd")
const Art := preload("res://scripts/art.gd")
const Formation := preload("res://scripts/formation.gd")
const TownKit := preload("res://scripts/town_kit.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")
const UnitModelScript := preload("res://scripts/unit_model.gd")

const LAYER_TAP := 16  # 건물 탭 판정체 (성문 2, 성벽 8과 별도)
const LAYER_MERCHANT := 32  # 상인·수레 탭 판정체 — picker가 건물보다 먼저 본다(앞쪽 건물 상자에 가리지 않게)

const MOUNTAIN_VARIANTS := 5

var half: float  # 성 내부 절반 크기. 기본값 없음 — main이 add_child 전에 castle.half로 설정
var merchant_label: Label3D  # 상인 이름표: "상인 ×1.3" — 시세가 바뀌면 갱신

var _label_cd := 0.0


func _ready() -> void:
	for b in Balance.BUILDINGS:
		_place_building(b)
	_place_merchant()
	_scatter_nature()
	_ring_mountains()


## 상인 이름표 배율은 정시(오프라인)나 서버 시세 갱신(온라인) 때만 바뀐다 — 1초마다 확인한다.
func _process(delta: float) -> void:
	_label_cd -= delta
	if _label_cd > 0.0:
		return
	_label_cd = 1.0
	var text := "상인 ×%.1f" % Economy.current_rate(Economy.time_now())
	if merchant_label.text != text:
		merchant_label.text = text


func _place_building(b: Dictionary) -> void:
	var center := Vector3((b.cell.x + b.size.x / 2.0) * Balance.TILE, 0, (b.cell.y + b.size.y / 2.0) * Balance.TILE)
	var mi := MeshInstance3D.new()
	mi.mesh = TownKit.building(b.id)
	mi.material_override = Art.lowpoly_vc_material()
	mi.position = center
	add_child(mi)
	var h: float = mi.mesh.get_aabb().end.y
	_add_tap_body(center, Vector3(b.size.x * Balance.TILE, h, b.size.y * Balance.TILE)).set_meta("building", b.id)
	_add_label(b.name, center + Vector3(0, h + 1.0, 0))


## 상인 NPC(대기, 카메라 쪽 +X+Z 대각을 봄) + 수레 + 이름표 + 탭 판정체(상인·수레를 함께 덮음).
func _place_merchant() -> void:
	var npc := UnitModelScript.new()
	npc.setup(Art.MERCHANT_MODEL)
	npc.position = Balance.MERCHANT_POS
	npc.face(Vector3(1, 0, 1))
	add_child(npc)
	var cart := MeshInstance3D.new()
	cart.mesh = TownKit.merchant_cart()
	cart.material_override = Art.lowpoly_vc_material()
	cart.position = Balance.MERCHANT_POS + Balance.MERCHANT_CART_OFFSET
	add_child(cart)
	merchant_label = _add_label("상인", Balance.MERCHANT_POS + Vector3(0, Art.HEAD_HEIGHT + 0.6, 0))
	var r := Vector3(Balance.MERCHANT_RADIUS, Art.HEAD_HEIGHT, Balance.MERCHANT_RADIUS)
	var box := AABB(Balance.MERCHANT_POS - Vector3(r.x, 0, r.z), r * 2.0 * Vector3(1, 0.5, 1))  # 상인 기둥
	box = box.merge(AABB(cart.position + cart.mesh.get_aabb().position, cart.mesh.get_aabb().size))
	_add_tap_body(Vector3(box.get_center().x, 0, box.get_center().z), Vector3(box.size.x, box.end.y, box.size.z), LAYER_MERCHANT).set_meta("merchant", true)


## 탭 판정체: 물리 이동과 무관(마스크 0). 바닥 중심 ground_center, 크기 size.
func _add_tap_body(ground_center: Vector3, size: Vector3, layer := LAYER_TAP) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.position = ground_center + Vector3(0, size.y / 2.0, 0)
	add_child(body)
	return body


func _add_label(text: String, pos: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = FONT
	label.font_size = 48
	label.outline_size = 12
	label.pixel_size = 0.03
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.modulate = Color(0.18, 0.18, 0.22)
	label.outline_modulate = Color(1, 1, 1, 0.9)
	label.position = pos
	add_child(label)
	return label


## 성벽 근처·괴물 진입로(두 축)·서로 가까운 자리를 피해 나무·덤불·바위를 흩는다. 나무 자리는 2~4그루 숲(같은 변형, 회전·크기만 다름).
## 변형마다 MultiMeshInstance3D 하나 — 수백 개여도 그리기 호출 몇 번.
func _scatter_nature() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Art.NATURE_SEED
	var variants: Array[Mesh] = []
	for pair in [[TownKit.tree_pine, 4], [TownKit.tree_round, 3], [TownKit.bush, 2], [TownKit.rock_cluster, 3]]:  # 레시피, 변형 수
		for i in pair[1]:
			variants.append(pair[0].call(rng))
	var trees := 7  # 앞의 변형 7개(침엽수 4 + 활엽수 3)가 나무
	var keep_out := half + Balance.WALL_T + Art.NATURE_CASTLE_MARGIN
	var lim := Balance.MAP_HALF - 4.0
	var placed: Array[Vector2] = []
	var by_variant := {}  # 변형 번호 -> Array[Transform3D]
	var tries := 0
	while placed.size() < Art.NATURE_COUNT and tries < Art.NATURE_COUNT * 20:
		tries += 1
		var p := Vector2(rng.randf_range(-lim, lim), rng.randf_range(-lim, lim))
		if not _nature_spot_ok(p, keep_out):
			continue
		var crowded := false
		for q in placed:
			if p.distance_to(q) < Art.NATURE_MIN_GAP:
				crowded = true
				break
		if crowded:
			continue
		placed.append(p)
		var v := rng.randi_range(0, variants.size() - 1)
		if not by_variant.has(v):
			by_variant[v] = []
		for g in (rng.randi_range(2, 4) if v < trees else 1):
			var q := p if g == 0 else p + Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(2.0, 3.2)
			var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * rng.randf_range(0.85, 1.15))
			if _nature_spot_ok(q, keep_out):
				by_variant[v].append(Transform3D(basis, Vector3(q.x, 0, q.y)))
	for v in by_variant:
		_add_multimesh(variants[v], by_variant[v])


## 플레이 영역 바깥 띠에 로우폴리 산을 한 바퀴 두른다(유닛은 들어가지 않는다). 시드 고정, 변형별 MultiMesh.
func _ring_mountains() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Art.BORDER_SEED
	var variants: Array[Mesh] = []
	for i in MOUNTAIN_VARIANTS:
		variants.append(TownKit.mountain(rng))
	var inner := Balance.MAP_HALF + Art.BORDER_INNER
	var outer := Balance.MAP_HALF + Art.BORDER_OUTER
	var steps := ceili(2.0 * outer / Art.BORDER_SPACING)
	var by_variant := {}
	for side in 4:
		var dir: Vector3 = Formation.SIDE_DIR[side]
		var perp := Formation.perp(side)
		for i in steps + 1:
			var along := -outer + i * Art.BORDER_SPACING + rng.randf_range(-4.0, 4.0)
			var pos := dir * rng.randf_range(inner, outer) + perp * along
			var v := rng.randi_range(0, variants.size() - 1)
			if not by_variant.has(v):
				by_variant[v] = []
			by_variant[v].append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)), pos))
	for v in by_variant:
		_add_multimesh(variants[v], by_variant[v])


func _add_multimesh(mesh: Mesh, placements: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = placements.size()
	for i in placements.size():
		mm.set_instance_transform(i, placements[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Art.lowpoly_vc_material()
	add_child(mmi)


## 자연물 자리 규칙: 성벽 바깥 여유 밖, 괴물 진입로(두 축) 밖.
func _nature_spot_ok(p: Vector2, keep_out: float) -> bool:
	return maxf(absf(p.x), absf(p.y)) >= keep_out and absf(p.x) >= Art.LANE_HALF_WIDTH and absf(p.y) >= Art.LANE_HALF_WIDTH

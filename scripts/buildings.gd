extends Node3D
## 성 안 건물(코드로 만든 로우폴리 메시, 기능 없음 — 서브프로젝트 2)과 성 밖 자연물·테두리 산 장식.
## 건물은 TownKit 레시피를 부지 중심에 그대로 놓는다(레시피가 부지 안에 맞춰져 있다 — 테스트). 부지 자리는 자유 건설(Economy.building_cell, 2026-10-13).
## 자연물·산은 시드 고정 변형 몇 개를 시드 고정 난수로 흩고, 변형마다 MultiMesh 하나로 그린다.
## 건물 레벨업(개정 12 §2.5): 짓는 중인 건물에 로우폴리 비계(기둥 4 + 가로대, 건물 AABB 둘레 — 성문은 문루 넷), 완료되면 비계를 걷고
## 빛 조각(Fx.repair)과 알림 "벌목장 Lv 4 완료". 이름표 "벌목장 Lv 3"·"상인"은 world_tags.gd(화면 공간, 개정 15)가 tag_anchors·merchant_anchor에
## 그린다. 머리 위 진행 막대·남은 시간은 badges.gd(화면 공간, 이름표 위).

const Balance := preload("res://scripts/balance.gd")
const Art := preload("res://scripts/art.gd")
const Formation := preload("res://scripts/formation.gd")
const TownKit := preload("res://scripts/town_kit.gd")
const UnitModelScript := preload("res://scripts/unit_model.gd")
const GameData := preload("res://scripts/game_data.gd")
const MeshKit := preload("res://scripts/mesh_kit.gd")
const Fx := preload("res://scripts/fx.gd")

const LAYER_TAP := 16  # 건물 탭 판정체 (성문 2, 성벽 8과 별도)
const LAYER_MERCHANT := 32  # 상인·수레 탭 판정체 — picker가 건물보다 먼저 본다(앞쪽 건물 상자에 가리지 않게)

const MOUNTAIN_VARIANTS := 5
const SCAFFOLD_MARGIN := 0.35  # 비계 기둥이 건물 AABB 밖으로 떨어진 거리(m)
const SCAFFOLD_POST := 0.28  # 기둥 굵기
const SCAFFOLD_RAIL := 0.14  # 가로대 굵기
const DONE_TEXT := "%s Lv %d 완료"
const TAG_UP := 0.3  # 지붕(메시 AABB 윗면) 위 이 높이가 이름표 아랫변 기준점
const LOT_TAP_H := 1.6  # 공터 탭 판정체 최소 높이(낮은 말뚝만 있어도 누르기 쉽게)
const BUILT_TEXT := "%s 건설 완료"

var half: float  # 성 내부 절반 크기. 기본값 없음 — main이 add_child 전에 castle.half로 설정
var merchant_anchor: Vector3  # 상인 이름표 "상인" 기준점(머리 위) — 시세·남은 시간은 상인을 눌러 여는 거래 창에서 본다
var tag_anchors := {}  # 건물 id → 이름표("이름 Lv N") 기준점: 지붕 가운데 위 TAG_UP
var sites := {}  # 건물 id → [AABB(월드), …] — 비계·진행 막대 자리. 성문은 문루 넷
var scaffold_id := ""  # 지금 비계를 두른 건물 id(없으면 "", 두 일꾼이면 "a,b")
var _built_now := {}  # 방금 공터에서 다 지은 건물 id(building_done 알림 문구)
var lots := {}  # 건물 id → 부지 {mi(메시), body(탭 판정체), center, size, full, lot(지금 공터로 보이는가), cell(지금 칸, 숨김이면 null)}
var hidden := {}  # 자리를 안 잡은 공터 id → true(성 안에 안 보인다 — 이름표도 없다)
var _scaffolds: Array = []
## 자연물·산 MultiMesh마다 {mm, recipe(TownKit 레시피), idx(레시피 안 변형 번호), state(만들기 전 rng 상태), base(기본 메시)}.
## seasons.gd(개정 22)가 같은 rng 상태 + 계절 팔레트로 다시 만든 메시를 갈아 끼운다.
var season_slots: Array = []


func _ready() -> void:
	for b in Balance.BUILDINGS:
		_place_building(b)
	_add_gate_sites()
	_place_merchant()
	_scatter_nature()
	_ring_mountains()
	Economy.changed.connect(_sync_build)
	Economy.changed.connect(_sync_lots)
	Economy.building_done.connect(_on_building_done)
	_sync_build()


func _place_building(b: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	mi.material_override = Art.lowpoly_vc_material()
	add_child(mi)
	lots[b.id] = {"mi": mi, "body": null, "center": Vector3.ZERO, "size": b.size, "full": TownKit.building(b.id), "lot": null, "cell": null}
	_show_lot(b.id)


## 건물 하나를 Economy에 맞춘다: 자리(자유 건설 — Economy.building_cell)와 모습 셋 중 하나 — 자리를 안 잡은 공터는 숨김(목록의 [건물]에서 짓는다),
## 짓는 중인 공터는 흙 바닥 + 말뚝, 다 지은 건물. 탭 판정체·이름표 자리·비계 자리도 그 자리·높이로 다시 만든다.
func _show_lot(id: String) -> void:
	var L: Dictionary = lots[id]
	var placed: bool = Economy.is_placed(id)
	var lot: bool = not Economy.is_built(id)
	var cell = Economy.building_cell(id) if placed else null
	if L.lot == lot and L.cell == cell:
		return
	if L.lot == true and not lot:
		_built_now[id] = true  # 공터 → 다 지음(완료 알림 "건설 완료")
	var moved: bool = L.cell != cell
	L.lot = lot
	L.cell = cell
	var mi: MeshInstance3D = L.mi
	if L.body != null:
		L.body.queue_free()
		L.body = null
	mi.visible = placed
	if not placed:
		hidden[id] = true
		tag_anchors[id] = Vector3.ZERO
		sites[id] = []
		return
	hidden.erase(id)
	var center := Balance.center_of(id)
	L.center = center
	mi.position = center
	var full: Mesh = L.full
	mi.mesh = lot_mesh(L.size) if lot else full
	sites[id] = [AABB(center + full.get_aabb().position, full.get_aabb().size)]  # 공터여도 비계는 다 지은 건물 크기로
	var h := maxf(mi.mesh.get_aabb().end.y, LOT_TAP_H)
	L.body = _add_tap_body(center, Vector3(L.size.x * Balance.TILE, h, L.size.y * Balance.TILE))
	L.body.set_meta("building", id)
	tag_anchors[id] = center + Vector3(0, mi.mesh.get_aabb().end.y + TAG_UP, 0)
	if moved and scaffold_id == id:
		scaffold_id = ""  # 짓는 중에 옮겼다 — 비계를 새 자리에
		_sync_build()


func _sync_lots() -> void:
	for id in lots:
		_show_lot(id)


## 공터(튜토리얼): 흙 바닥 + 네 모서리 말뚝과 줄 + 앞쪽 작은 팻말. size = 부지 칸 수.
static func lot_mesh(size: Vector2i) -> ArrayMesh:
	var k = MeshKit.new()
	var hx := size.x * Balance.TILE / 2.0 - 0.4
	var hz := size.y * Balance.TILE / 2.0 - 0.4
	k.box(Vector3.ZERO, Vector3(hx * 2.0, 0.08, hz * 2.0), TownKit.SOIL)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			k.box(Vector3(sx * hx, 0, sz * hz), Vector3(0.16, 0.7, 0.16), TownKit.WOOD)
		k.box(Vector3(sx * hx, 0.5, 0), Vector3(0.05, 0.05, hz * 2.0), TownKit.LOG_END)
	for sz in [-1.0, 1.0]:
		k.box(Vector3(0, 0.5, sz * hz), Vector3(hx * 2.0, 0.05, 0.05), TownKit.LOG_END)
	k.box(Vector3(0, 0, hz * 0.4), Vector3(0.12, 1.0, 0.12), TownKit.WOOD_DARK)  # 팻말 기둥
	k.box(Vector3(0, 0.75, hz * 0.4), Vector3(0.9, 0.45, 0.08), TownKit.CROP)  # 팻말 판
	return k.commit()


## 상인 NPC(대기, 카메라 쪽 +X+Z 대각을 봄) + 수레 + 이름표 기준점 + 탭 판정체(상인·수레를 함께 덮음).
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
	merchant_anchor = Balance.MERCHANT_POS + Vector3(0, Art.HEAD_HEIGHT + 0.1, 0)
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


## 성벽 근처·괴물 진입로(두 축)·서로 가까운 자리를 피해 나무·덤불·바위를 흩는다. 나무 자리는 2~4그루 숲(같은 변형, 회전·크기만 다름).
## 변형마다 MultiMeshInstance3D 하나 — 수백 개여도 그리기 호출 몇 번.
func _scatter_nature() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Art.NATURE_SEED
	var variants: Array[Mesh] = []
	var info := []  # 변형마다 [레시피, 레시피 안 번호, 만들기 전 rng 상태]
	for pair in [[TownKit.tree_pine, 4], [TownKit.tree_round, 3], [TownKit.bush, 2], [TownKit.rock_cluster, 3]]:  # 레시피, 변형 수
		for i in pair[1]:
			info.append([pair[0], i, rng.state])
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
		_add_season_slot(_add_multimesh(variants[v], by_variant[v]), info[v])


## 플레이 영역 바깥 띠에 로우폴리 산을 한 바퀴 두른다(유닛은 들어가지 않는다). 시드 고정, 변형별 MultiMesh.
func _ring_mountains() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Art.BORDER_SEED
	var variants: Array[Mesh] = []
	var info := []
	for i in MOUNTAIN_VARIANTS:
		info.append([TownKit.mountain, i, rng.state])
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
		_add_season_slot(_add_multimesh(variants[v], by_variant[v]), info[v])


func _add_season_slot(mm: MultiMesh, info: Array) -> void:
	season_slots.append({"mm": mm, "recipe": info[0], "idx": info[1], "state": info[2], "base": mm.mesh})


func _add_multimesh(mesh: Mesh, placements: Array) -> MultiMesh:
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
	return mm


## 자연물 자리 규칙: 성벽 바깥 여유 밖, 괴물 진입로(두 축) 밖.
func _nature_spot_ok(p: Vector2, keep_out: float) -> bool:
	if maxf(absf(p.x), absf(p.y)) < keep_out:
		return false
	for at in Formation.gate_offsets(half):  # 성문마다 괴물 진입로(성문 축) — 성문 옆 위치는 ±로 대칭
		var a := absf(float(at))
		if absf(absf(p.x) - a) < Art.LANE_HALF_WIDTH or absf(absf(p.y) - a) < Art.LANE_HALF_WIDTH:
			return false
	return true


# --- 건물 레벨업 표시(개정 12 §2.5) ---

## 성문 자리: 모든 문루의 AABB(castle.gd와 같은 놓임 — 로컬 +Z가 성 바깥, 면마다 성문 1·2·3개).
func _add_gate_sites() -> void:
	var aabb := TownKit.gatehouse().get_aabb()
	var boxes := []
	for side in 4:
		var dir: Vector3 = Formation.SIDE_DIR[side]
		for at in Formation.gate_offsets(half):
			boxes.append(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), Formation.gate_position(half, side, at)) * aabb)
	sites[GameData.GATE] = boxes


## 비계를 Economy 일꾼에 맞춘다. 짓는 건물이 바뀔 때만 다시 만든다(이름표 "이름 Lv N"은 world_tags가 Economy.changed마다).
func _sync_build() -> void:
	var ids := []  # 2026-10-13: 일꾼마다(두 번째 일꾼까지)
	for job in Economy.build_jobs():
		if sites.has(str(job.id)):
			ids.append(str(job.id))
	var id := ",".join(ids)
	if id == scaffold_id:
		return
	for s in _scaffolds:
		s.queue_free()
	_scaffolds.clear()
	scaffold_id = id
	var boxes := []
	for b in ids:
		boxes.append_array(sites.get(b, []))
	for box in boxes:
		var mi := MeshInstance3D.new()
		mi.mesh = scaffold_mesh(box.size)
		mi.material_override = Art.lowpoly_vc_material()
		mi.position = Vector3(box.get_center().x, box.position.y, box.get_center().z)
		add_child(mi)
		_scaffolds.append(mi)


## 완료: 비계는 changed가 이미 걷었다. 지붕 위·네 모서리에 빛 조각, 알림 "이름 Lv N 완료".
func _on_building_done(id: String, level: int) -> void:
	_sync_build()
	_sync_lots()
	var was_lot := _built_now.has(id)
	_built_now.erase(id)
	for box in sites.get(id, []):
		var top := Vector3(box.get_center().x, box.end.y - 2.0, box.get_center().z)  # Fx.repair는 2 m 위에서 튄다
		Fx.repair(self, top)
		for sx in [-0.5, 0.5]:
			for sz in [-0.5, 0.5]:
				Fx.repair(self, top + Vector3(box.size.x * sx, -box.size.y * 0.4, box.size.z * sz))
	Economy.notice.emit(BUILT_TEXT % GameData.building_def(id).name if was_lot else DONE_TEXT % [GameData.building_def(id).name, level])


## 로우폴리 비계: 크기 size(건물 AABB) 둘레에 각진 나무 기둥 4개 + 세 단 가로대. 바닥 가운데가 원점.
static func scaffold_mesh(size: Vector3) -> ArrayMesh:
	var k = MeshKit.new()
	var hx := size.x / 2.0 + SCAFFOLD_MARGIN
	var hz := size.z / 2.0 + SCAFFOLD_MARGIN
	var h := size.y + 0.4
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			k.box(Vector3(sx * hx, 0, sz * hz), Vector3(SCAFFOLD_POST, h, SCAFFOLD_POST), TownKit.WOOD_DARK)
	for y in [h * 0.33, h * 0.66, h - SCAFFOLD_RAIL]:
		for s in [-1.0, 1.0]:
			k.box(Vector3(0, y, s * hz), Vector3(hx * 2.0 + SCAFFOLD_POST, SCAFFOLD_RAIL, SCAFFOLD_RAIL), TownKit.WOOD)
			k.box(Vector3(s * hx, y, 0), Vector3(SCAFFOLD_RAIL, SCAFFOLD_RAIL, hz * 2.0 + SCAFFOLD_POST), TownKit.WOOD)
	return k.commit()

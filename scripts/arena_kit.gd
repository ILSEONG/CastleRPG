extends RefCounted
## 개정 18 던전 아트(스펙 §3·§4): 무대 — 광활한 평야(골드 던전)·불타는 성 내부(장비 던전)·숲속 옛 사원(모집권 던전·PVP 결투)·
## 용암 협곡 둥지(길드 드래곤)·결투장(PVP 총력전, 둘 다 2026-10-07) — 와 던전 몬스터 코드 부품(고블린 귀·코,
## 왕관, 왕 몽둥이, 데스나이트 눈빛·망토·대검), 장비 드랍 상자·빛기둥. 전부 MeshKit 로우폴리(정점 색) + 공유 재질, 반복물은 MultiMesh,
## 이펙트(불꽃·연기·불씨·빛기둥·눈빛·용암)는 그림자 없음. 오토로드 참조 없음.
## 무대 빌더 반환 = {root: Node3D, heroes: [Vector3], enemies: [Vector3], boss: Vector3, light: 조명 설정} — lighting(light)가 조명 노드를 만든다.
## 화면 기준 자리 spot(u, v): 기본 카메라(요 45°)에서 u+ = 화면 아래(+X+Z 대각선), v+ = 화면 오른쪽. 영웅은 아래, 적은 위.

const Art := preload("res://scripts/art.gd")
const MeshKit := preload("res://scripts/mesh_kit.gd")
const TownKit := preload("res://scripts/town_kit.gd")
const GroundShader := preload("res://shaders/ground_grid.gdshader")
const GlowShader := preload("res://shaders/glow.gdshader")
const SmokeShader := preload("res://shaders/smoke.gdshader")
const LavaShader := preload("res://shaders/lava.gdshader")
const CheerShader := preload("res://shaders/cheer.gdshader")

const DOWN := Vector3(0.70710678, 0, 0.70710678)  # 화면 아래(카메라 쪽)
const RIGHT := Vector3(0.70710678, 0, -0.70710678)  # 화면 오른쪽
const PLAINS_FIGHT_R := 26.0  # 평야: 이 반경 안은 평평한 빈 풀밭(전투 자리) — 나무·바위·언덕은 밖에만
const PLAINS_SEED := 18
const HALL_HALF := 15.0  # 불타는 성: 홀 바닥 30×30 m(홀 좌표 원점 중심)
const HALL_YAW := PI / 4.0  # 홀 좌표 → 월드 회전: 홀 +Z(앞) = 화면 아래, +X = 화면 오른쪽 → spot(u, v) = 홀 (v, u)
const CASTLE_SEED := 19
const TEMPLE_FIGHT_R := 14.0  # 사원 앞뜰: 전투 자리 반경(기둥 줄 x = ±11 안쪽쯤)
const FLOWERS := [Color(0.95, 0.85, 0.35), Color(0.95, 0.95, 0.92), Color(0.86, 0.50, 0.62)]
const TEMPLE_HALF := 14.0  # 앞뜰 판석 반 변(사원 좌표)
const TEMPLE_SEED := 23
const COLUMN_H := 7.0
const LANTERN_H := 1.6
const SANDSTONE := Color(0.80, 0.70, 0.54)
const SANDSTONE_LIGHT := Color(0.88, 0.80, 0.64)
const SANDSTONE_DARK := Color(0.64, 0.55, 0.42)
const STATUE := Color(0.55, 0.60, 0.56)  # 이끼 낀 회녹색 돌
const MOSS := Color(0.40, 0.55, 0.30)
const ROOF_RED := Color(0.66, 0.22, 0.16)
const GOLD_TRIM := Color(0.85, 0.64, 0.20)
const SMOKE_H := 14.0
const PILLAR_H := 7.0

# 팔레트(sRGB). 해를 받는 윗면은 채널 ≤ 0.69(TownKit 규칙), 숯·불은 일부러 밝게.
const STONE := Color(0.42, 0.38, 0.36)
const STONE_DARK := Color(0.30, 0.27, 0.26)
const SOOT := Color(0.20, 0.17, 0.16)
const IRON := Color(0.22, 0.20, 0.21)
const COALS := Color(0.95, 0.42, 0.10)
const BANNER := Color(0.50, 0.10, 0.09)
const GOBLIN_SKIN := Color(0.53, 0.66, 0.25)  # Rogue 살색 × Art.GOBLIN_TINT
const KING_SKIN := Color(0.45, 0.48, 0.19)  # Rogue 살색 × Art.KING_TINT
const GOLD := Color(0.85, 0.62, 0.16)
const DK_STEEL := Color(0.30, 0.29, 0.34)
const DK_RED := Color(0.85, 0.12, 0.08)

# 불타는 성 배치(홀 좌표)
const BRAZIERS := [Vector3(-5, 0, -10), Vector3(5, 0, -10), Vector3(-11, 0, -2), Vector3(11, 0, -2), Vector3(-7, 0, 11), Vector3(7, 0, 11)]
const BRAZIER_H := 1.45  # 화로 불꽃 밑(숯 위)
const FIRES := [[Vector3(-12.5, 0, -12.5), 2.0], [Vector3(12.0, 0, -13.0), 1.7], [Vector3(0, 0.6, -18.0), 2.6],
	[Vector3(-13.0, 0, 9.0), 1.5], [Vector3(12.5, 0, 13.0), 1.6], [Vector3(3, 18.4, -26), 3.2],
	[Vector3(-10.0, 0, 24.0), 1.4], [Vector3(9.0, 0, 30.0), 1.8]]  # [자리, 크기] — 바닥 불·아치 너머·탑 꼭대기·앞마당
const APRON := 26.0  # 홀 앞 깨진 앞마당 길이(m)
const SMOKES := [Vector3(-12.5, 0, -12.5), Vector3(12.0, 0, -13.0), Vector3(0, 0.6, -18.0), Vector3(3, 18.4, -26)]
const TOWERS := [[Vector3(-11, 0, -23), 3.2, 14.0], [Vector3(3, 0, -26), 3.6, 18.0], [Vector3(14, 0, -22), 2.8, 11.0]]  # [자리, 반지름, 높이]

# 길드 드래곤 둥지(lair — 둥지 좌표 = HALL_YAW: x = spot v, z = spot u)
const LAIR_FIGHT_R := 14.0  # 유닛이 중심에서 이만큼 안(crowd·picker)
const LAIR_SIDE := 7.2  # 유닛 중심이 화면 가로(spot v)로 이만큼 안 — 양옆은 용암 강(LAVA_IN)
const LAIR_SEED := 31
const LAIR_DRAGON_U := -5.0  # 드래곤 자리(spot u)
const LAIR_HOARD_U := -17.5  # 보물 더미 가운데(spot u, 드래곤 뒤 = 화면 위)
const LAIR_BACK_WALL := 25.0  # 뒤 절벽(spot u = −이것)
const LAIR_BACK := 34.0  # 강·옆 절벽이 시작하는 뒤(spot u = −이것)
const LAIR_FRONT := 46.0  # 강·옆 절벽이 끝나는 앞(spot u)
const LAVA_IN := 8.2  # 용암 강 안쪽 가장자리(|v|)
const CLIFF_IN := 10.6  # 옆 절벽 밑 안쪽(|v|)
const BASALT := Color(0.36, 0.31, 0.29)
const BASALT_DARK := Color(0.20, 0.17, 0.17)
const ASH := Color(0.42, 0.38, 0.36)
const LAVA := Color(1.0, 0.36, 0.05)
const LAVA_HOT := Color(1.0, 0.66, 0.16)
const LAVA_CRUST := Color(0.40, 0.08, 0.03)
const EMBER_ROCK := Color(0.62, 0.20, 0.07)  # 용암 빛을 받은 절벽 아래
const BONE := Color(0.76, 0.72, 0.62)
const HOARD := Color(0.70, 0.48, 0.12)
const COIN := Color(0.86, 0.66, 0.22)
const GEMS := [Color(0.85, 0.12, 0.20), Color(0.18, 0.45, 0.95), Color(0.15, 0.78, 0.45), Color(0.66, 0.28, 0.90)]

# PVP 총력전 결투장(colosseum — 같은 좌표)
const ARENA_WALL := 9.2  # 옆벽 안쪽 면(|v|)
const ARENA_SIDE := 8.4  # 유닛 중심이 화면 가로로 이만큼 안
const ARENA_END := 22.6  # 끝벽 안쪽 면(|u|) — 유닛은 PVP FIELD_R 원(22) 안
const ARENA_SEED := 37
const STAND_ROW := 1.25  # 관중석 한 단 폭(cheer 셰이더 row)
const STAND_SEAT := 0.9  # 관중 한 칸(cheer 셰이더 seat)
const SAND := Color(0.57, 0.47, 0.34)
const SAND_DARK := Color(0.48, 0.39, 0.28)
const GRASS := Color(0.47, 0.58, 0.36)
const CHALK := Color(0.82, 0.78, 0.68)
const STRAW := Color(0.80, 0.68, 0.36)
const ARENA_STONE := Color(0.58, 0.54, 0.48)
const WOOD := Color(0.48, 0.33, 0.20)
const WOOD_DARK := Color(0.36, 0.24, 0.15)
const TEAM_BLUE := Color(0.22, 0.40, 0.80)
const TEAM_RED := Color(0.80, 0.20, 0.16)
const FAN_SHIRTS := [Color(0.80, 0.72, 0.52), Color(0.45, 0.32, 0.22), Color(0.35, 0.55, 0.30), Color(0.55, 0.35, 0.60), Color(0.85, 0.85, 0.80)]
const SKINS := [Color(0.96, 0.80, 0.66), Color(0.86, 0.66, 0.50), Color(0.62, 0.44, 0.32)]

static var _meshes := {}  # 부품·불꽃·연기·상자·빛기둥 메시(id마다 하나)
static var _mats := {}


## 화면 기준 자리 → 월드 바닥.
static func spot(u: float, v: float) -> Vector3:
	return DOWN * u + RIGHT * v


## 조명 설정(무대 빌더의 light) → WorldEnvironment + 해 + 점광원(최대 3, 그림자 없음)을 담은 노드.
static func lighting(cfg: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Lighting"
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = cfg.background
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = cfg.ambient
	e.ambient_light_energy = cfg.ambient_energy
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = cfg.sun_color
	sun.light_energy = cfg.sun_energy
	sun.shadow_enabled = cfg.shadows
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 160.0
	sun.rotation_degrees = cfg.sun_rot
	root.add_child(sun)
	for o in cfg.omni:  # [위치, 색, 세기, 범위]
		var l := OmniLight3D.new()
		l.position = o[0]
		l.light_color = o[1]
		l.light_energy = o[2]
		l.omni_range = o[3]
		root.add_child(l)
	return root


# --- 골드 던전: 광활한 평야 ---

## 600 m 풀밭 격자(성 전장과 같은 셰이더, 전부 풀밭), 전투 자리 밖 낮은 언덕(각진 둔덕)·바위·나무 숲, 멀리 산 고리(변형마다 MultiMesh). 밝은 낮.
## 영웅 6 = 화면 아래 두 줄. 고블린 15 = 위쪽 세 무리(5마리씩): 앞 10(두 무리)이 먼저, 뒤 5는 왕 옆 무리(스펙 §3: 5초 뒤 5 + 왕). 왕은 맨 뒤.
static func plains() -> Dictionary:
	var root := Node3D.new()
	root.name = "Plains"
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	var mat := ShaderMaterial.new()
	mat.shader = GroundShader
	mat.set_shader_parameter("tile_size", 2.0)
	mat.set_shader_parameter("interior_half", 0.0)  # 포장 없이 전부 풀밭
	mat.set_shader_parameter("grass_a", Color(0.47, 0.58, 0.36))
	mat.set_shader_parameter("grass_b", Color(0.44, 0.55, 0.33))
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.material_override = mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = PLAINS_SEED
	var mounds := []
	for i in 3:
		mounds.append(_mound(rng))
	_scatter(root, mounds, 16, PLAINS_FIGHT_R + 14.0, 100.0, rng, 0.8, 1.4)
	var trees := []
	for f in [TownKit.tree_pine, TownKit.tree_pine, TownKit.tree_round, TownKit.tree_round, TownKit.bush]:
		trees.append(f.call(rng))
	_scatter(root, trees, 70, PLAINS_FIGHT_R + 4.0, 115.0, rng, 0.85, 1.2, 3)
	var rocks := []
	for i in 3:
		rocks.append(TownKit.rock_cluster(rng))
	_scatter(root, rocks, 30, PLAINS_FIGHT_R, 110.0, rng, 0.6, 1.3)
	var peaks := []
	for i in 5:
		peaks.append(TownKit.mountain(rng))
	_scatter(root, peaks, 22, 110.0, 170.0, rng, 1.3, 1.9, 1, 1.1)  # 멀리 산: 화면 위쪽(카메라 반대편) 부채꼴만 — 앞에 있으면 전장을 가린다
	var heroes := []
	for i in 6:
		heroes.append(spot(9.0 + (i / 3) * 2.6, (i % 3 - 1) * 2.8))
	var enemies := []
	for c in [Vector2(-12, -7), Vector2(-13, 6), Vector2(-18, -1)]:
		for o in [Vector2.ZERO, Vector2(1.5, 0), Vector2(-1.5, 0), Vector2(0, 1.5), Vector2(0, -1.5)]:
			enemies.append(spot(c.x + o.x, c.y + o.y))
	return {"root": root, "heroes": heroes, "enemies": enemies, "boss": spot(-22.0, 0.0), "light": {
		"background": Color(0.72, 0.85, 0.96), "ambient": Color(0.80, 0.84, 0.90), "ambient_energy": 0.95,
		"sun_color": Color(1.0, 0.96, 0.86), "sun_energy": 1.2, "sun_rot": Vector3(-52, -40, 0), "shadows": true, "omni": []}}


## 낮은 언덕: 아주 납작하게 누른 각진 20면체(밑면 평평), 풀색 면마다 명암. 반지름 7~12 m, 높이 ≈ 0.37 × 반지름.
static func _mound(rng: RandomNumberGenerator) -> ArrayMesh:
	var k = MeshKit.new()
	var r := rng.randf_range(7.0, 12.0)
	k.rock(Vector3(0, r * 0.05, 0), r, Color(0.47, 0.57, 0.35), rng, 0.28, 0.0)
	return k.commit()


## r_min~r_max 고리(arc < PI면 화면 위쪽 방향 ±arc 부채꼴)에 변형들을 넓이 균등하게 흩는다. grove > 1이면 자리마다 1~grove개를 2~3.5 m 안에 모은다(숲). 변형마다 MultiMesh 하나.
static func _scatter(root: Node3D, variants: Array, count: int, r_min: float, r_max: float, rng: RandomNumberGenerator,
		s_min: float, s_max: float, grove := 1, arc := PI) -> void:
	var by := {}
	for i in count:
		var c := Vector2.from_angle(-0.75 * PI + rng.randf_range(-arc, arc)) * sqrt(rng.randf_range(r_min * r_min, r_max * r_max))
		var v := rng.randi_range(0, variants.size() - 1)
		if not by.has(v):
			by[v] = []
		for g in rng.randi_range(1, grove):
			var p := c if g == 0 else c + Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(2.0, 3.5)
			var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * rng.randf_range(s_min, s_max))
			by[v].append(Transform3D(b, Vector3(p.x, 0, p.y)))
	for v in by:
		root.add_child(_multimesh(variants[v], by[v], Art.lowpoly_vc_material(), true))


# --- 모집권 던전: 숲속 옛 사원 앞뜰 ---

## 사원 좌표(홀과 같은 HALL_YAW: +Z = 화면 아래, +X = 화면 오른쪽 → spot(u, v) = 사원 (v, u)). 사암 판석 앞뜰(가운데 밝은 참배길),
## 양옆 기둥 줄(기둥 다섯 + 위 들보), 뒤쪽 3단 돌계단 위 사당(기둥 넷·붉은 박공지붕·금 장식), 계단 양옆 수호 석상, 참배길 따라 돌등(불꽃),
## 앞뜰 밖 풀밭·숲·먼 산. 돌 부분은 메시 하나, 불꽃은 MultiMesh 하나. 영웅 5(내 4 + 도우미) = 화면 아래 두 줄(3 + 2), 바위 골렘 = 계단 앞.
static func temple() -> Dictionary:
	var root := Node3D.new()
	root.name = "Temple"
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	var mat := ShaderMaterial.new()
	mat.shader = GroundShader
	mat.set_shader_parameter("tile_size", 2.0)
	mat.set_shader_parameter("interior_half", 0.0)
	mat.set_shader_parameter("grass_a", Color(0.42, 0.56, 0.32))
	mat.set_shader_parameter("grass_b", Color(0.39, 0.53, 0.30))
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.material_override = mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = TEMPLE_SEED
	var site := Node3D.new()
	site.rotation.y = HALL_YAW
	root.add_child(site)
	var k = MeshKit.new()
	_temple_floor(k, rng)
	_temple_columns(k)
	_temple_shrine(k)
	var fires := []
	for z in [-8.0, -1.0, 6.0]:
		for x in [-5.0, 5.0]:
			_stone_lantern(k, Vector3(x, 0, z))
			fires.append(Transform3D(Basis().scaled(Vector3.ONE * 0.55), Vector3(x, LANTERN_H, z)))
	for x in [-7.0, 7.0]:
		fires.append(Transform3D(Basis().scaled(Vector3.ONE * 0.8), Vector3(x, 3.1 + 1.45, -20.5)))
		_brazier(k, Vector3(x, 3.1, -20.5))
	var stone := MeshInstance3D.new()
	stone.mesh = k.commit()
	stone.material_override = Art.lowpoly_vc_material()
	site.add_child(stone)
	site.add_child(_multimesh(flame_mesh(), fires, _glow(1.0, 0.0, 0.9), false))
	var trees := []
	for f in [TownKit.tree_pine, TownKit.tree_round, TownKit.tree_round, TownKit.bush]:
		trees.append(f.call(rng))
	_scatter(root, trees, 80, TEMPLE_FIGHT_R + 9.0, 110.0, rng, 0.9, 1.3, 3)
	var peaks := []
	for i in 4:
		peaks.append(TownKit.mountain(rng))
	_scatter(root, peaks, 20, 110.0, 170.0, rng, 1.3, 1.9, 1, 1.1)
	var heroes := []
	for i in 5:
		heroes.append(spot(6.0 + (i / 3) * 2.6, (i % 3 - 1) * 2.8 + (1.4 if i >= 3 else 0.0)))
	var enemies := []
	for o in [Vector2(-7, -3), Vector2(-7, 3), Vector2(-9, 0)]:
		enemies.append(spot(o.x, o.y))
	return {"root": root, "heroes": heroes, "enemies": enemies, "boss": spot(-8.0, 0.0), "light": {
		"background": Color(0.74, 0.86, 0.95), "ambient": Color(0.82, 0.84, 0.88), "ambient_energy": 0.9,
		"sun_color": Color(1.0, 0.95, 0.84), "sun_energy": 1.2, "sun_rot": Vector3(-50, -35, 0), "shadows": true, "omni": []}}


## 초원 위 사원(2026-10-06 사용자 "초원 + 사원"): 앞뜰은 풀밭 — 가운데 4 m 참배길만 밝은 판석으로 이어지고, 사당 앞(z < −12)은 판석 마당,
## 나머지는 풀밭에 흩어진 옛 판석(이끼 낀 것 많음)과 들꽃.
static func _temple_floor(k, rng: RandomNumberGenerator) -> void:
	var h := TEMPLE_HALF
	_flat(k, Vector3(-2.2, 0.005, -h - 9.0), Vector3(2.2, 0.005, h + 1.0), SANDSTONE_DARK.darkened(0.25))
	_flat(k, Vector3(-h - 1.0, 0.005, -h - 9.0), Vector3(h + 1.0, 0.005, -12.0), SANDSTONE_DARK.darkened(0.25))
	for ix in int(h):
		for iz in int(h + 4.0):
			var x0 := -h + ix * 2.0 + 0.07
			var z0 := -h - 8.0 + iz * 2.0 + 0.07
			var path := absf(x0 + 0.93) < 2.1
			var yard := z0 < -12.0
			if not path and not yard and rng.randf() > 0.12:
				continue
			var c := SANDSTONE_LIGHT if path else SANDSTONE.darkened(rng.randf_range(0.0, 0.12))
			if not path and rng.randf() < (0.1 if yard else 0.4):
				c = c.lerp(MOSS, 0.45)
			var y := rng.randf_range(0.02, 0.05)
			k.face([Vector3(x0, y, z0), Vector3(x0 + 1.86, y, z0), Vector3(x0 + 1.86, y, z0 + 1.86), Vector3(x0, y, z0 + 1.86)], Vector3.UP, c)
	for i in 70:  # 들꽃: 참배길 밖 풀밭에 작은 꽃
		var p := Vector3(rng.randf_range(-h - 4.0, h + 4.0), 0, rng.randf_range(-12.0, h + 4.0))
		if absf(p.x) < 2.6:
			continue
		k.pyramid(p, 0.12, 0.28, MOSS.darkened(0.1))
		k.box(p + Vector3(0, 0.26, 0), Vector3(0.16, 0.08, 0.16), FLOWERS[i % FLOWERS.size()])


## 양옆 기둥 줄: x = ±11, z = −14..10에 다섯씩(받침·8각 기둥·머리), 기둥 위 들보. 앞 끝 하나는 부러진 밑동.
static func _temple_columns(k) -> void:
	for sx in [-1.0, 1.0]:
		var x: float = sx * 11.0
		for z in [-14.0, -8.0, -2.0, 4.0, 10.0]:
			var base := Vector3(x, 0, z)
			k.box(base, Vector3(1.8, 0.5, 1.8), SANDSTONE_DARK)
			if z == 10.0 and sx > 0.0:
				k.prism_n(base + Vector3(0, 0.5, 0), 8, 0.64, 0.6, 1.4, SANDSTONE, PI / 8.0)
				continue
			k.prism_n(base + Vector3(0, 0.5, 0), 8, 0.64, 0.56, COLUMN_H - 0.5, SANDSTONE, PI / 8.0)
			k.box(base + Vector3(0, COLUMN_H, 0), Vector3(1.5, 0.4, 1.5), SANDSTONE_DARK)
			k.box(base + Vector3(0, COLUMN_H + 0.4, 0), Vector3(1.8, 0.25, 1.8), GOLD_TRIM)
		var end_z: float = 4.0 if sx > 0.0 else 10.0
		k.box(Vector3(x, COLUMN_H + 0.65, (-14.0 + end_z) / 2.0), Vector3(1.4, 0.7, end_z + 14.0 + 1.6), SANDSTONE_DARK)


## 사당: 3단 돌계단(z = −15부터 뒤로 높아짐) 위 단(높이 3.1), 기둥 넷 + 들보 + 붉은 박공지붕(금 용마루), 안쪽 어두운 문, 계단 양옆 수호 석상.
static func _temple_shrine(k) -> void:
	for i in 3:
		k.box(Vector3(0, i * 1.0, -16.0 - i * 1.6), Vector3(24.0 - i * 2.0, 1.05, 3.6), SANDSTONE_DARK if i % 2 == 0 else SANDSTONE)
	k.box(Vector3(0, 0, -26.0), Vector3(20.0, 3.1, 14.0), SANDSTONE_DARK)
	var top := 3.1
	k.box(Vector3(0, top, -27.0), Vector3(11.0, 4.6, 6.0), SANDSTONE)
	k.box(Vector3(0, top, -23.95), Vector3(3.0, 3.4, 0.1), Color(0.16, 0.12, 0.10))
	for x in [-5.0, -2.2, 2.2, 5.0]:
		k.prism_n(Vector3(x, top, -22.6), 8, 0.42, 0.38, 4.6, SANDSTONE_LIGHT, PI / 8.0)
	k.box(Vector3(0, top + 4.6, -25.0), Vector3(12.4, 0.6, 6.4), GOLD_TRIM)
	k.gable(Vector3(0, top + 5.2, -25.0), Vector3(12.0, 0, 7.0), 3.0, ROOF_RED, 0.6)
	k.box(Vector3(0, top + 8.1, -25.0), Vector3(13.0, 0.3, 0.4), GOLD_TRIM)
	for x in [-7.5, 7.5]:  # 수호 석상: 받침 + 웅크린 몸 + 머리 + 귀
		var b := Vector3(float(x), 0, -13.5)
		k.box(b, Vector3(2.0, 1.0, 2.0), SANDSTONE_DARK)
		k.prism_n(b + Vector3(0, 1.0, 0), 6, 0.85, 0.6, 1.7, STATUE, PI / 6.0)
		k.box(b + Vector3(0, 2.6, 0.25), Vector3(1.1, 0.95, 1.1), STATUE)
		k.box(b + Vector3(0, 2.75, 0.85), Vector3(0.7, 0.45, 0.25), STATUE.darkened(0.12))
		for ex in [-0.4, 0.4]:
			k.pyramid(b + Vector3(ex, 3.55, 0.1), 0.35, 0.5, STATUE)


## 돌등: 받침·기둥·불 담는 집(4면 기둥 + 지붕) — 불꽃 밑 = LANTERN_H.
static func _stone_lantern(k, p: Vector3) -> void:
	k.box(p, Vector3(0.9, 0.3, 0.9), SANDSTONE_DARK)
	k.prism_n(p + Vector3(0, 0.3, 0), 6, 0.22, 0.2, 1.1, SANDSTONE, PI / 6.0)
	k.box(p + Vector3(0, 1.4, 0), Vector3(0.95, 0.15, 0.95), SANDSTONE_DARK)
	for o in [Vector3(-0.38, 0, -0.38), Vector3(0.38, 0, -0.38), Vector3(0.38, 0, 0.38), Vector3(-0.38, 0, 0.38)]:
		k.box(p + o + Vector3(0, 1.55, 0), Vector3(0.14, 0.6, 0.14), SANDSTONE)
	k.pyramid(p + Vector3(0, 2.15, 0), 1.25, 0.55, ROOF_RED)


# --- 장비 던전: 불타는 성 내부 ---

## 홀 좌표(화면에 맞춤, HALL_YAW로 돌려 놓는다): 30×30 m 판석 바닥(앞으로 갈수록 깨지고 어두워짐), 뒤 벽(부서진 아치, 벽기둥, 타는 휘장),
## 낮게 무너진 옆 벽, 기둥 두 줄(앞쪽은 부러진 밑동), 쓰러진 기둥·잔해, 화로 6, 바닥 불, 벽 너머 무너진 탑 셋(꼭대기에 불).
## 돌 부분은 메시 하나(그리기 1회), 불꽃은 MultiMesh 하나(glow 셰이더 TIME 흔들림), 연기 기둥 MultiMesh 하나, 불씨 CPUParticles3D 하나.
## 영웅 4 = 화면 아래 한 줄, 데스나이트 = 아치 앞. 조명: 어두운 붉은 주변광 + 약한 해 + 점광원 3.
static func castle() -> Dictionary:
	var root := Node3D.new()
	root.name = "BurningCastle"
	var hall := Node3D.new()
	hall.rotation.y = HALL_YAW
	root.add_child(hall)
	var rng := RandomNumberGenerator.new()
	rng.seed = CASTLE_SEED
	var k = MeshKit.new()
	_hall_floor(k, rng)
	_hall_walls(k, rng)
	_hall_columns(k, rng)
	var fires := []
	for p in BRAZIERS:
		_brazier(k, p)
		fires.append(Transform3D(Basis(), p + Vector3(0, BRAZIER_H, 0)))
	for f in FIRES:
		if f[0].y < 1.0:
			_fire_bed(k, f[0], f[1], rng)
		fires.append(Transform3D(Basis().scaled(Vector3.ONE * f[1]), f[0]))
	var stone := MeshInstance3D.new()
	stone.mesh = k.commit()
	stone.material_override = Art.lowpoly_vc_material()
	stone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hall.add_child(stone)
	hall.add_child(_multimesh(flame_mesh(), fires, _glow(1.0, 0.0, 0.9), false))
	var smokes := []
	for p in SMOKES:
		smokes.append(Transform3D(Basis(), p))
	hall.add_child(_multimesh(_smoke_mesh(), smokes, _smoke(), false))
	hall.add_child(_embers())
	var hw := Basis(Vector3.UP, HALL_YAW)
	var heroes := []
	for v in [-3.0, -1.0, 1.0, 3.0]:
		heroes.append(spot(7.5, v))
	return {"root": root, "heroes": heroes, "enemies": [], "boss": spot(-6.0, 0.0), "light": {
		"background": Color(0.06, 0.025, 0.02), "ambient": Color(0.45, 0.22, 0.17), "ambient_energy": 0.8,
		"sun_color": Color(1.0, 0.55, 0.35), "sun_energy": 0.55, "sun_rot": Vector3(-55, -30, 0), "shadows": false,
		"omni": [[hw * Vector3(0, 5.5, -8), Color(1.0, 0.42, 0.18), 3.0, 17.0],
			[hw * Vector3(-9, 3.5, 6), Color(1.0, 0.55, 0.22), 2.2, 13.0],
			[hw * Vector3(9, 3.5, 6), Color(1.0, 0.55, 0.22), 2.2, 13.0]]}}


## 판석: 2 m 판석(틈 0.12, 높이·명암 조금씩, 그을린 판석, 빠진 판석, 한 모서리 들린 판석). 홀 앞(z > 15, APRON m)은 점점 깨지고 어두워져
## 어둠 속으로 사라진다(화면 아래가 갑자기 끊기지 않게). 아래에 어두운 줄눈 판, 그 밖은 어둠 판.
static func _hall_floor(k, rng: RandomNumberGenerator) -> void:
	var h := HALL_HALF
	_flat(k, Vector3(-45, -0.02, -45), Vector3(45, -0.02, 60), Color(0.11, 0.08, 0.07))
	_flat(k, Vector3(-h, -0.01, -h), Vector3(h, -0.01, h + APRON), Color(0.17, 0.14, 0.13))
	for ix in 15:
		for iz in int(2.0 * h + APRON) / 2:
			var x0 := -h + ix * 2.0 + 0.06
			var z0 := -h + iz * 2.0 + 0.06
			var front := maxf(0.0, z0 + 2.0 - h) / APRON  # 0 = 홀 안 → 1 = 앞 끝
			if rng.randf() < 0.04 + front * 0.6:
				continue
			var c := SOOT if rng.randf() < 0.12 else STONE.darkened(rng.randf_range(0.0, 0.14) + front * 0.4)
			var y := rng.randf_range(0.02, 0.06)
			var ys := [y, y, y, y]
			if rng.randf() < 0.08:
				ys[rng.randi_range(0, 3)] += rng.randf_range(0.1, 0.22)
			k.face([Vector3(x0, ys[0], z0), Vector3(x0 + 1.88, ys[1], z0), Vector3(x0 + 1.88, ys[2], z0 + 1.88), Vector3(x0, ys[3], z0 + 1.88)], Vector3.UP, c)


## 뒤 벽(z = −15, 두께 1.5, 2 m 칸마다 높이 들쭉날쭉, 가운데 4 m는 부서진 아치), 벽기둥 넷, 타는 휘장 둘, 낮게 무너진 옆 벽(x = ±15),
## 벽 너머 무너진 탑 셋(빛나는 창).
static func _hall_walls(k, rng: RandomNumberGenerator) -> void:
	var h := HALL_HALF
	var tops := [8.5, 9.0, 7.0, 9.5, 8.0, 9.0, 6.0, 0.0, 0.0, 7.5, 5.0, 9.0, 8.5, 9.5, 7.5, 8.0]  # x = −15, −13 … 15 칸, 0 = 아치 자리
	for i in tops.size():
		if tops[i] > 0.0:
			k.box(Vector3(-15.0 + i * 2.0, 0, -h - 0.75), Vector3(2.0, tops[i], 1.5), STONE_DARK)
	for x in [-12.0, -6.0, 6.0, 12.0]:  # 벽기둥: 칸 높이 + 0.4, 홀 쪽으로 0.5 튀어나옴, 위에 주두
		var top: float = tops[int((x + 15.0) / 2.0 + 0.5)] + 0.4
		k.box(Vector3(x, 0, -h + 0.25), Vector3(1.0, top, 0.5), STONE)
		k.box(Vector3(x, top - 0.4, -h + 0.3), Vector3(1.3, 0.4, 0.6), STONE_DARK)
	# 부서진 아치: 안 반지름 2(문설주 높이 5에서 시작), 돌 7개 중 오른쪽 위 셋이 떨어져 나갔다(아래 잔해)
	for i in 7:
		if i in [1, 2, 3]:
			continue
		var a := PI * i / 6.0
		k.xform = Transform3D(Basis(Vector3.BACK, a - PI / 2.0), Vector3(cos(a) * 2.35, 5.0 + sin(a) * 2.35, -h - 0.75))
		k.box(Vector3(0, -0.35, 0), Vector3(1.05, 0.7, 1.6), STONE)
	k.xform = Transform3D.IDENTITY
	for p in [Vector3(1.6, 0, -h + 0.6), Vector3(2.4, 0, -h + 1.4), Vector3(0.9, 0, -h + 1.8)]:
		k.rock(p, rng.randf_range(0.4, 0.7), STONE, rng, 0.6, 0.0)
	k.rock(Vector3(0, 0, -18.0), 1.7, STONE_DARK, rng, 0.4, 0.0)  # 아치 너머 잔해 더미(불 밑)
	for x in [-9.0, 9.0]:  # 타는 휘장: 벽에 붙은 붉은 천, 아래가 찢어지고 그을림
		var y0 := 3.2 + rng.randf_range(0.0, 0.6)
		var z := -h + 0.02
		k.face([Vector3(x - 0.8, 7.6, z), Vector3(x + 0.8, 7.6, z), Vector3(x + 0.8, y0 + 0.5, z), Vector3(x + 0.2, y0, z), Vector3(x - 0.8, y0 + 0.9, z)], Vector3.BACK, BANNER)
		k.face([Vector3(x - 0.8, y0 + 1.3, z + 0.01), Vector3(x + 0.8, y0 + 0.9, z + 0.01), Vector3(x + 0.8, y0 + 0.5, z + 0.01), Vector3(x + 0.2, y0, z + 0.01), Vector3(x - 0.8, y0 + 0.9, z + 0.01)], Vector3.BACK, SOOT)
		k.box(Vector3(x, 7.6, z + 0.05), Vector3(2.0, 0.12, 0.1), IRON)
	for s in [-1.0, 1.0]:  # 옆 벽: 2 m 칸, 높이 0.8~4.5(앞쪽은 낮게), 군데군데 무너져 빔
		for i in 15:
			var z := -h + 1.0 + i * 2.0
			if rng.randf() < 0.25:
				continue
			var top := rng.randf_range(0.8, 4.5) * (0.5 if z > 5.0 else 1.0)
			k.box(Vector3(s * (h + 0.6), 0, z), Vector3(1.2, top, 2.0), STONE_DARK)
	for t in TOWERS:  # 벽 너머 탑: 8각 기둥, 부서진 꼭대기(톱니 몇 개 + 각진 돌), 앞면에 빛나는 창
		var c: Vector3 = t[0]
		var r: float = t[1]
		var top: float = t[2]
		k.prism_n(c, 8, r, r * 0.92, top, STONE_DARK.darkened(0.2), PI / 8.0)
		for j in 5:
			var a := TAU * (j + rng.randf_range(0.0, 0.3)) / 5.0
			k.box(c + Vector3(cos(a), 0, sin(a)) * r * 0.75 + Vector3(0, top, 0), Vector3(0.9, rng.randf_range(0.4, 1.6), 0.9), STONE_DARK)
		k.rock(c + Vector3(rng.randf_range(-1.0, 1.0), top, rng.randf_range(-1.0, 1.0)), r * 0.55, STONE_DARK.darkened(0.1), rng, 0.4)
		for y in [top * 0.45, top * 0.7]:
			k.box(c + Vector3(0, y, r * 0.92), Vector3(0.6, 1.4, 0.12), Color(0.85, 0.35, 0.08))


## 기둥 두 줄(x = ±9): 뒤 둘은 온전(9 m, 주두), 앞으로 갈수록 부러짐(4 m, 1.6 m — 부러진 끝은 각진 돌). 쓰러진 기둥 둘·토막 셋,
## 잔해(돌·깎은 돌 블록)는 가운데 전투 자리(|x| < 7, −11.5 < z < 13) 밖에.
static func _hall_columns(k, rng: RandomNumberGenerator) -> void:
	for s in [-1.0, 1.0]:
		for c in [[-10.0, 9.0], [-3.0, 9.0], [4.0, 4.0], [11.0, 1.6]]:
			var base := Vector3(s * 9.0, 0, c[0])
			var top: float = c[1]
			k.box(base, Vector3(1.7, 0.5, 1.7), STONE_DARK)
			k.prism_n(base + Vector3(0, 0.5, 0), 8, 0.62, 0.58, top - 0.5, STONE, PI / 8.0)
			if top >= 9.0:
				k.box(base + Vector3(0, top, 0), Vector3(1.4, 0.35, 1.4), STONE_DARK)
				k.box(base + Vector3(0, top + 0.35, 0), Vector3(1.7, 0.3, 1.7), STONE)
			else:
				k.rock(base + Vector3(0, top, 0), 0.62, STONE, rng, 0.9)
	_fallen(k, Vector3(5.5, 0, 15.5), 0.25, 6.0)
	_fallen(k, Vector3(-13.5, 0, -6.0), 0.5, 6.5)
	for p in [Vector3(-10.0, 0, 6.5), Vector3(10.5, 0, 1.5), Vector3(-8.0, 0, 13.5)]:
		_fallen(k, p, rng.randf_range(0.0, TAU), 1.1)
	var n := 0
	while n < 56:
		var p := Vector3(rng.randf_range(-14.5, 14.5), 0, rng.randf_range(-14.5, 30.0))
		if absf(p.x) < 7.0 and p.z > -11.5 and p.z < 13.0:
			continue
		n += 1
		if rng.randf() < 0.7:
			k.rock(p + Vector3(0, 0.1, 0), rng.randf_range(0.25, 0.8), STONE.darkened(rng.randf_range(0.0, 0.2)), rng, 0.6, 0.0)
		else:
			k.xform = Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)), p)
			k.box(Vector3.ZERO, Vector3(rng.randf_range(0.6, 1.2), rng.randf_range(0.35, 0.6), rng.randf_range(0.5, 0.9)), STONE)
			k.xform = Transform3D.IDENTITY


## 쓰러진 기둥(또는 토막): start에서 +X를 yaw만큼 돌린 쪽으로 누운 8각 기둥(밑면이 바닥에 닿음).
static func _fallen(k, start: Vector3, yaw: float, length: float) -> void:
	var r := 0.6
	k.xform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, -PI / 2.0), start + Vector3(0, r * cos(PI / 8.0), 0))
	k.prism_n(Vector3.ZERO, 8, r, r, length, STONE, PI / 8.0)
	k.xform = Transform3D.IDENTITY


## 화로: 6각 받침 + 기둥 + 위가 넓은 8각 쇠 그릇 + 빛나는 숯(불꽃 밑 = BRAZIER_H).
static func _brazier(k, p: Vector3) -> void:
	k.prism_n(p, 6, 0.42, 0.36, 0.14, IRON)
	k.prism_n(p + Vector3(0, 0.14, 0), 6, 0.11, 0.11, 0.9, IRON)
	k.prism_n(p + Vector3(0, 1.0, 0), 8, 0.24, 0.62, 0.42, IRON, PI / 8.0)
	k.prism_n(p + Vector3(0, 1.42, 0), 8, 0.56, 0.56, 0.03, COALS, PI / 8.0)


## 바닥 불자리: 숯 원판 + 숯이 된 통나무 셋(크기 s배).
static func _fire_bed(k, p: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	k.prism_n(p, 7, 0.75 * s, 0.6 * s, 0.08, COALS.darkened(0.25))
	for i in 3:
		var yaw := rng.randf_range(0.0, TAU)
		var b := Basis(Vector3.UP, yaw)
		k.xform = Transform3D(b * Basis(Vector3.BACK, -PI / 2.0), p + b * Vector3(-0.6 * s, 0.15 * s, 0))
		k.prism_n(Vector3.ZERO, 5, 0.13 * s, 0.13 * s, 1.2 * s, SOOT)
	k.xform = Transform3D.IDENTITY


## 바닥과 평행한 사각 면(a, b = 맞모서리, 같은 높이).
static func _flat(k, a: Vector3, b: Vector3, color: Color) -> void:
	k.face([a, Vector3(b.x, a.y, a.z), b, Vector3(a.x, a.y, b.z)], Vector3.UP, color)


## 불꽃 한 덩이(밑 원점, 높이 ≈ 1.25): 바깥 주황 원뿔 + 안쪽 밝은 원뿔 둘 + 옆 혀 둘. glow 셰이더가 더하기로 그려 겹친 가운데가 노랗다.
static func flame_mesh() -> ArrayMesh:
	if not _meshes.has("flame"):
		var k = MeshKit.new()
		k.cone(Vector3.ZERO, 6, 0.42, 1.25, Color(1.0, 0.45, 0.08))
		k.cone(Vector3.ZERO, 5, 0.30, 0.95, Color(1.0, 0.62, 0.15), 0.5)
		k.cone(Vector3.ZERO, 4, 0.16, 0.62, Color(1.0, 0.90, 0.55), 0.3)
		k.cone(Vector3(0.24, 0, 0.06), 4, 0.13, 0.6, Color(1.0, 0.50, 0.10), 0.2)
		k.cone(Vector3(-0.2, 0, -0.12), 4, 0.12, 0.5, Color(1.0, 0.50, 0.10), 0.9)
		_meshes.flame = k.commit()
	return _meshes.flame


## 연기 기둥: 위로 갈수록 넓어지는 열린 6각 관(뚜껑 없음, 마디 4 — 셰이더 흔들림이 휘어 보이게).
static func _smoke_mesh() -> ArrayMesh:
	if not _meshes.has("smoke"):
		var k = MeshKit.new()
		var rings := []
		for i in 5:
			rings.append([SMOKE_H * i / 4.0, lerpf(0.9, 2.6, i / 4.0)])
		_tube(k, rings, 6, Color.WHITE)
		_meshes.smoke = k.commit()
	return _meshes.smoke


## 열린 관(옆면만): rings = [[높이, 반지름], …] 아래부터.
static func _tube(k, rings: Array, sides: int, color: Color) -> void:
	for ri in rings.size() - 1:
		var a: Array = rings[ri]
		var b: Array = rings[ri + 1]
		for i in sides:
			var t0 := TAU * i / sides
			var t1 := TAU * (i + 1) / sides
			var d0 := Vector3(cos(t0), 0, sin(t0))
			var d1 := Vector3(cos(t1), 0, sin(t1))
			k.face([d0 * a[1] + Vector3(0, a[0], 0), d1 * a[1] + Vector3(0, a[0], 0), d1 * b[1] + Vector3(0, b[0], 0), d0 * b[1] + Vector3(0, b[0], 0)],
				(d0 + d1) / 2.0, color)


## 불씨: 홀 위로 떠오르는 주황 점(CPUParticles3D 하나 — Compatibility에서 안전), 더하기 섞기, 그림자 없음.
static func _embers() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 80
	p.lifetime = 4.0
	p.preprocess = 4.0
	p.position = Vector3(0, 0.3, 2.0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(14.0, 0.3, 18.0)
	p.direction = Vector3.UP
	p.spread = 35.0
	p.gravity = Vector3(0.25, 0.8, 0.1)
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.6
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	ramp.set_color(1, Color(1.0, 0.25, 0.05, 0.0))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	quad.material = m
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func _multimesh(mesh: Mesh, xforms: Array, mat: Material, shadow: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	if not shadow:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## 더하기 빛 재질(glow 셰이더): 불꽃(flicker 1), 빛기둥(fade = 높이), 눈빛. 값마다 하나를 공유한다.
static func _glow(flicker: float, fade: float, energy: float) -> ShaderMaterial:
	var key := "glow%.2f/%.2f/%.2f" % [flicker, fade, energy]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = GlowShader
		m.set_shader_parameter("flicker", flicker)
		m.set_shader_parameter("fade_height", fade)
		m.set_shader_parameter("energy", energy)
		_mats[key] = m
	return _mats[key]


static func _smoke() -> ShaderMaterial:
	if not _mats.has("smoke"):
		var m := ShaderMaterial.new()
		m.shader = SmokeShader
		m.set_shader_parameter("height", SMOKE_H)
		_mats.smoke = m
	return _mats.smoke


# --- 길드 드래곤: 용암 협곡 둥지(2026-10-07 디자인 보강 3번) ---

## 둥지 좌표(사원·홀과 같은 HALL_YAW: x = 화면 가로 spot v, z = 화면 세로 spot u → spot(u, v) = 둥지 (v, u)). 화면이 세로로 길어 싸움 따라가기
## 카메라(가로 18~26 m)에 양옆이 늘 걸리도록 좁은 협곡이다: 잿빛 현무암 바닥(판 셰이더, 격자선 없이 면 명암만), 양옆 흐르며 빛나는 용암 강(|v| > LAVA_IN)과
## 그 너머 들쭉날쭉한 현무암 절벽, 바닥을 가르는 빛나는 틈(드래곤 자리에서 별 모양으로 퍼짐), 그을린 자국·잿빛 얼룩·자갈, 드래곤 뒤(화면 위) 보물 더미
## (금화 언덕·상자·보석·꽂힌 검·방패), 뒤 절벽에서 쏟아지는 용암 폭포, 영웅 아래(화면 아래) 옛 짐승의 갈비뼈·뿔 달린 해골·작은 용암 웅덩이.
## 돌·뼈·보물은 메시 하나(그림자 없음 — 절벽 그림자가 싸움터를 덮지 않게), 용암은 메시 둘(바닥·폭포, lava 셰이더), 연기 MultiMesh 하나, 불씨 하나.
## 유닛은 LAIR_FIGHT_R 원 안 + 화면 가로 LAIR_SIDE 안(crowd.arena_side). 영웅 6 = 화면 아래 두 줄(평야와 같은 자리), 드래곤 = boss.
static func lair() -> Dictionary:
	var root := Node3D.new()
	root.name = "Lair"
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	var mat := ShaderMaterial.new()
	mat.shader = GroundShader
	mat.set_shader_parameter("tile_size", 2.5)
	mat.set_shader_parameter("interior_half", 0.0)
	mat.set_shader_parameter("grass_a", BASALT)
	mat.set_shader_parameter("grass_b", BASALT.darkened(0.04))
	mat.set_shader_parameter("line_color", Color(0, 0, 0, 0.0))
	mat.set_shader_parameter("facet_variation", 0.10)
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.material_override = mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = LAIR_SEED
	var site := Node3D.new()
	site.rotation.y = HALL_YAW
	root.add_child(site)
	var k = MeshKit.new()  # 돌·뼈·보물(정점 색, 그림자 없음)
	var lava = MeshKit.new()  # 바닥 용암(강·틈·웅덩이)
	var fall = MeshKit.new()  # 용암 폭포
	_lair_floor(k, lava, rng)
	for s in [-1.0, 1.0]:
		_lava_river(k, lava, s, rng)
		_lair_cliffs(k, s, rng)
	_lair_back(k, lava, fall, rng)
	_hoard(k, Vector3(0, 0, LAIR_HOARD_U), rng)
	_ribcage(k, Vector3(-4.0, 0, 18.5), rng)
	_horned_skull(k, Vector3(4.6, 0, 16.5), rng)
	_lava_pool(k, lava, Vector3(1.0, 0, 21.2), 1.9, rng)
	var stone := MeshInstance3D.new()
	stone.mesh = k.commit()
	stone.material_override = Art.lowpoly_vc_material()
	stone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	site.add_child(stone)
	for pair in [[lava, false], [fall, true]]:
		var mi := MeshInstance3D.new()
		mi.mesh = pair[0].commit()
		mi.material_override = _lava(pair[1])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		site.add_child(mi)
	var smokes := []
	for p in [Vector3(-10.5, 0, -6.0), Vector3(10.5, 0, 3.0), Vector3(-10.0, 0, 13.0), Vector3(-4.6, 0, -20.6), Vector3(1.0, 0, 21.2)]:
		smokes.append(Transform3D(Basis().scaled(Vector3.ONE * 0.7), p))
	site.add_child(_multimesh(_smoke_mesh(), smokes, _smoke(), false))
	var embers := _embers()
	embers.position = Vector3(0, 0.3, 0)
	embers.emission_box_extents = Vector3(10.0, 0.3, 26.0)
	site.add_child(embers)
	var heroes := []
	for i in 6:
		heroes.append(spot(9.0 + (i / 3) * 2.6, (i % 3 - 1) * 2.8))
	var hw := Basis(Vector3.UP, HALL_YAW)
	return {"root": root, "heroes": heroes, "enemies": [], "boss": spot(LAIR_DRAGON_U, 0.0), "light": {
		"background": Color(0.10, 0.05, 0.04), "ambient": Color(0.62, 0.46, 0.40), "ambient_energy": 0.85,
		"sun_color": Color(1.0, 0.78, 0.58), "sun_energy": 0.95, "sun_rot": Vector3(-55, -35, 0), "shadows": true,
		"omni": [[hw * Vector3(-9.5, 2.5, -3.0), Color(1.0, 0.45, 0.15), 1.8, 13.0],
			[hw * Vector3(9.5, 2.5, 7.0), Color(1.0, 0.45, 0.15), 1.8, 13.0],
			[hw * Vector3(0.0, 3.5, LAIR_HOARD_U + 2.5), Color(1.0, 0.78, 0.40), 0.8, 10.0]]}}


## 바닥: 잿빛 얼룩·그을린 자국(납작한 다각형), 드래곤 자리에서 별 모양으로 퍼지는 틈 다섯, 강가에서 안쪽으로 뻗는 틈, 자갈·작은 뼈.
static func _lair_floor(k, lava, rng: RandomNumberGenerator) -> void:
	for i in 14:
		_blot(k, Vector3(rng.randf_range(-7.5, 7.5), 0.004, rng.randf_range(-12.0, 24.0)), rng.randf_range(1.2, 2.6), 9, ASH, rng)
	for i in 9:
		_blot(k, Vector3(rng.randf_range(-6.5, 6.5), 0.007, rng.randf_range(-10.0, 22.0)), rng.randf_range(0.7, 1.6), 8, BASALT.darkened(0.18), rng)
	for i in 5:  # 드래곤 자리 둘레 그을린 땅 + 별 모양 틈
		var a := TAU * (i + rng.randf_range(-0.2, 0.2)) / 5.0
		var from := Vector3(cos(a) * 2.2, 0, LAIR_DRAGON_U + sin(a) * 2.2)
		_crack(k, lava, from, a, rng.randf_range(3.5, 6.0), 0.34, rng)
	_blot(k, Vector3(0, 0.006, LAIR_DRAGON_U), 3.4, 11, BASALT.darkened(0.22), rng, 0.2)
	for s in [-1.0, 1.0]:  # 강가에서 안쪽으로
		var z := -14.0 + rng.randf_range(0.0, 3.0)
		while z < 26.0:
			var a: float = (PI if s > 0.0 else 0.0) + rng.randf_range(-0.6, 0.6)
			_crack(k, lava, Vector3(s * (LAVA_IN + 0.2), 0, z), a, rng.randf_range(2.0, 4.5), 0.3, rng)
			z += rng.randf_range(5.0, 8.0)
	for i in 70:  # 자갈
		var p := Vector3(rng.randf_range(-LAVA_IN, LAVA_IN), 0, rng.randf_range(-12.0, 26.0))
		k.rock(p, rng.randf_range(0.08, 0.24), BASALT_DARK if rng.randf() < 0.6 else ASH, rng, 0.6, 0.0)
	for i in 12:  # 작은 뼈: 가장자리·아래쪽
		var x := rng.randf_range(4.5, 7.4) * (1.0 if rng.randf() < 0.5 else -1.0)
		var z := rng.randf_range(-11.0, 24.0)
		if rng.randf() < 0.4:
			x = rng.randf_range(-6.0, 6.0)
			z = rng.randf_range(14.0, 25.0)
		_bone(k, Vector3(x, 0, z), rng.randf_range(0.0, TAU), rng.randf_range(0.6, 1.1))


## 용암 강(s = −1 왼쪽, 1 오른쪽): 안쪽 가장자리는 들쭉날쭉(LAVA_IN 안팎), 바깥은 절벽 밑까지. 가장자리 띠는 식어서 어둡고 가운데가 밝다.
## 가장자리 따라 낮은 현무암 둔덕, 강 위에 떠다니는 검은 껍질 조각.
static func _lava_river(k, lava, s: float, rng: RandomNumberGenerator) -> void:
	var z := -LAIR_BACK
	var x_in := LAVA_IN
	var outer := CLIFF_IN + 3.0
	while z < LAIR_FRONT:
		var z1 := z + rng.randf_range(1.2, 2.0)
		var x1 := LAVA_IN + rng.randf_range(-0.25, 0.35)
		var m0 := x_in + 0.55
		var m1 := x1 + 0.55
		lava.face([Vector3(s * x_in, 0.02, z), Vector3(s * x1, 0.02, z1), Vector3(s * m1, 0.02, z1), Vector3(s * m0, 0.02, z)], Vector3.UP,
			LAVA_CRUST.lerp(LAVA, rng.randf_range(0.45, 0.7)))
		lava.face([Vector3(s * m0, 0.02, z), Vector3(s * m1, 0.02, z1), Vector3(s * outer, 0.02, z1), Vector3(s * outer, 0.02, z)], Vector3.UP,
			LAVA.lerp(LAVA_HOT, rng.randf_range(0.0, 0.7)))
		for b in 2:  # 가장자리 둔덕
			var bz := lerpf(z, z1, rng.randf())
			k.rock(Vector3(s * (lerpf(x_in, x1, 0.5) - rng.randf_range(0.0, 0.35)), 0.0, bz), rng.randf_range(0.25, 0.5), BASALT_DARK, rng, 0.5, 0.0)
		if rng.randf() < 0.35:  # 껍질 조각
			_blot(k, Vector3(s * rng.randf_range(LAVA_IN + 1.0, CLIFF_IN), 0.04, lerpf(z, z1, 0.5)), rng.randf_range(0.25, 0.6), 6, BASALT_DARK.darkened(0.2), rng)
		z = z1
		x_in = x1


## 절벽(s쪽): 안 줄(|v| CLIFF_IN~, 높이 4~9)과 뒤 줄(높이 8~14)의 들쭉날쭉한 현무암 기둥. 강을 향한 아래쪽 면은 용암 빛을 받아 붉다.
static func _lair_cliffs(k, s: float, rng: RandomNumberGenerator) -> void:
	for row in 2:
		var z := -LAIR_BACK + rng.randf_range(0.0, 2.0)
		while z < LAIR_FRONT:
			var r := rng.randf_range(1.8, 2.8) + row * 0.8
			var x := s * (CLIFF_IN + r * 0.5 + row * 4.0 + rng.randf_range(0.0, 1.0))
			_crag(k, Vector3(x, 0, z), r, rng.randf_range(4.0, 9.0) + row * 5.0, rng, Vector3(-s, 0, 0))
			if row == 0 and rng.randf() < 0.5:  # 밑동 바위
				k.rock(Vector3(s * (CLIFF_IN - 0.2), 0, z + rng.randf_range(-1.0, 1.0)), rng.randf_range(0.5, 0.9), BASALT_DARK, rng, 0.6, 0.0)
			z += rng.randf_range(2.6, 3.6) + row * 0.8


## 뒤(화면 위, 보물 더미 너머): 가로지르는 절벽 기둥, 가운데 왼쪽에서 쏟아지는 용암 폭포 → 웅덩이 → 왼쪽 강으로 흐르는 물길, 둘레 뾰족 바위.
static func _lair_back(k, lava, fall, rng: RandomNumberGenerator) -> void:
	var fx := -4.6
	var x := -CLIFF_IN - 2.0
	while x < CLIFF_IN + 2.0:
		if absf(x - fx) > 1.6:
			_crag(k, Vector3(x, 0, -LAIR_BACK_WALL - rng.randf_range(0.5, 2.5)), rng.randf_range(2.2, 3.2), rng.randf_range(8.0, 13.0), rng, Vector3.BACK)
		x += rng.randf_range(2.4, 3.2)
	_crag(k, Vector3(fx, 0, -LAIR_BACK_WALL - 3.4), 3.0, 11.0, rng, Vector3.BACK)  # 폭포 뒤 바위
	var top := 9.5
	var z0 := -LAIR_BACK_WALL - 1.0
	for i in 6:  # 폭포: 위는 좁고 아래로 넓어진다, 앞으로 조금 기운다
		var t0 := i / 6.0
		var t1 := (i + 1) / 6.0
		var w0 := lerpf(0.7, 1.3, t0)
		var w1 := lerpf(0.7, 1.3, t1)
		var y0 := top * (1.0 - t0)
		var y1 := top * (1.0 - t1)
		var za := z0 + 0.9 * t0 * t0
		var zb := z0 + 0.9 * t1 * t1
		fall.face([Vector3(fx - w0, y0, za), Vector3(fx + w0, y0, za), Vector3(fx + w1, y1, zb), Vector3(fx - w1, y1, zb)], Vector3.BACK,
			LAVA.lerp(LAVA_HOT, rng.randf_range(0.2, 0.8)))
	_lava_pool(k, lava, Vector3(fx, 0, -LAIR_BACK_WALL + 1.4), 2.2, rng)
	var path := [Vector3(fx, 0, -LAIR_BACK_WALL + 1.4), Vector3(fx - 1.4, 0, -LAIR_BACK_WALL + 3.4), Vector3(-LAVA_IN + 0.2, 0, -LAIR_BACK_WALL + 5.2), Vector3(-LAVA_IN - 1.0, 0, -LAIR_BACK_WALL + 6.0)]
	for i in path.size() - 1:  # 웅덩이 → 왼쪽 강 물길
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var n := (b - a).cross(Vector3.UP).normalized() * 0.75
		lava.face([a - n + Vector3(0, 0.025, 0), a + n + Vector3(0, 0.025, 0), b + n + Vector3(0, 0.025, 0), b - n + Vector3(0, 0.025, 0)], Vector3.UP, LAVA.lerp(LAVA_HOT, 0.4))
	for i in 10:  # 뾰족 바위
		var p := Vector3(rng.randf_range(-CLIFF_IN, CLIFF_IN), 0, -LAIR_BACK_WALL + rng.randf_range(0.5, 4.0))
		if absf(p.x - fx) < 3.0:
			continue
		k.cone(p, 5, rng.randf_range(0.4, 0.9), rng.randf_range(1.4, 3.4), BASALT_DARK, rng.randf_range(0.0, TAU))


## 들쭉날쭉한 현무암 기둥: 흔든 5~7각 고리 셋 + 꼭짓점(위로 좁아짐). toward = 빛(용암·싸움터)을 향한 쪽 — 그쪽 아래 면은 붉게 달아오른다.
static func _crag(k, base: Vector3, r: float, h: float, rng: RandomNumberGenerator, toward: Vector3) -> void:
	var n := rng.randi_range(5, 7)
	var rings := []
	for ring in [[0.0, 1.0], [0.42, 0.74], [0.8, 0.42]]:
		var row := []
		for i in n:
			var a := TAU * (i + rng.randf_range(-0.25, 0.25)) / n
			var rr: float = r * ring[1] * rng.randf_range(0.8, 1.15)
			var y: float = h * ring[0] * rng.randf_range(0.88, 1.12)
			row.append(base + Vector3(cos(a) * rr, y, sin(a) * rr))
		rings.append(row)
	var apex := base + Vector3(rng.randf_range(-0.25, 0.25) * r, h, rng.randf_range(-0.25, 0.25) * r)
	var tris := []
	for ri in 2:
		for i in n:
			var j := (i + 1) % n
			tris.append([rings[ri][i], rings[ri][j], rings[ri + 1][j]])
			tris.append([rings[ri][i], rings[ri + 1][j], rings[ri + 1][i]])
	for i in n:
		tris.append([rings[2][i], rings[2][(i + 1) % n], apex])
	var below := base - Vector3(0, h, 0)
	for t in tris:
		var c: Vector3 = (t[0] + t[1] + t[2]) / 3.0
		var f := c.y / h
		var col := BASALT_DARK if f < 0.3 else (BASALT if f < 0.75 else ASH)
		var out := Vector3(c.x - base.x, 0, c.z - base.z).normalized()
		var lit := out.dot(toward)
		if lit > 0.1 and c.y < 3.5:
			col = col.lerp(EMBER_ROCK, 0.75 * lit * (1.0 - c.y / 3.5))
		k.face(t, c - below, col.darkened(rng.randf_range(0.0, 0.1)))


## 바닥 틈: from에서 각 a(둥지 xz 평면) 쪽으로 꺾이며 뻗는 빛나는 선(너비 w → 끝 0.06), 밑에 조금 넓은 검은 테두리.
static func _crack(k, lava, from: Vector3, a: float, length: float, w: float, rng: RandomNumberGenerator) -> void:
	var p := Vector3(from.x, 0, from.z)
	var left := length
	var seg := 0
	while left > 0.0 and seg < 8:
		var l := minf(left, rng.randf_range(0.7, 1.3))
		a += rng.randf_range(-0.5, 0.5)
		var q := p + Vector3(cos(a), 0, sin(a)) * l
		var t0 := 1.0 - left / length
		var t1 := 1.0 - (left - l) / length
		var w0 := lerpf(w, 0.06, t0)
		var w1 := lerpf(w, 0.06, t1)
		var n := (q - p).cross(Vector3.UP).normalized()
		var e := 0.12
		k.face([p - n * (w0 + e) + Vector3(0, 0.009, 0), p + n * (w0 + e) + Vector3(0, 0.009, 0), q + n * (w1 + e) + Vector3(0, 0.009, 0), q - n * (w1 + e) + Vector3(0, 0.009, 0)],
			Vector3.UP, BASALT_DARK.darkened(0.45))
		lava.face([p - n * w0 + Vector3(0, 0.016, 0), p + n * w0 + Vector3(0, 0.016, 0), q + n * w1 + Vector3(0, 0.016, 0), q - n * w1 + Vector3(0, 0.016, 0)],
			Vector3.UP, LAVA.lerp(LAVA_HOT, rng.randf_range(0.1, 0.6)))
		p = q
		left -= l
		seg += 1


## 용암 웅덩이: 흔든 다각형(면마다 밝기 조금씩) + 둘레 낮은 현무암 둔덕.
static func _lava_pool(k, lava, c: Vector3, r: float, rng: RandomNumberGenerator) -> void:
	var n := 10
	var pts := []
	for i in n:
		var a := TAU * (i + rng.randf_range(-0.2, 0.2)) / n
		pts.append(c + Vector3(cos(a), 0, sin(a)) * r * rng.randf_range(0.85, 1.15))
	for i in n:
		var j := (i + 1) % n
		lava.face([c + Vector3(0, 0.03, 0), pts[i] + Vector3(0, 0.03, 0), pts[j] + Vector3(0, 0.03, 0)], Vector3.UP, LAVA.lerp(LAVA_HOT, rng.randf_range(0.2, 0.9)))
		k.rock(pts[i] * 1.0 + (pts[i] - c).normalized() * 0.2, rng.randf_range(0.35, 0.6), BASALT_DARK, rng, 0.55, 0.0)


## 바닥 위 납작한 얼룩: c 둘레로 흔든 n각(가운데에서 부채꼴, 조각마다 명암 조금씩).
static func _blot(k, c: Vector3, r: float, n: int, color: Color, rng: RandomNumberGenerator, jitter := 0.3) -> void:
	var pts := []
	for i in n:
		var a := TAU * (i + rng.randf_range(-0.3, 0.3)) / n
		pts.append(c + Vector3(cos(a), 0, sin(a)) * r * rng.randf_range(1.0 - jitter, 1.0 + jitter))
	for i in n:
		k.face([c, pts[i], pts[(i + 1) % n]], Vector3.UP, color.darkened(rng.randf_range(0.0, 0.08)))


## a → b 막대(sides각, 굵기 r0 → r1). k.xform 위에 얹는다.
static func _bar(k, a: Vector3, b: Vector3, r0: float, r1: float, color: Color, sides := 4) -> void:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var keep: Transform3D = k.xform
	k.xform = keep * Transform3D(Basis(x, y, x.cross(y)), a)
	k.prism_n(Vector3.ZERO, sides, r0, r1, d.length(), color)
	k.xform = keep


## 바닥에 누운 뼈 하나(길이 l, 양끝 마디).
static func _bone(k, c: Vector3, yaw: float, l: float) -> void:
	var d := Vector3(cos(yaw), 0, sin(yaw)) * l / 2.0
	_bar(k, c - d + Vector3(0, 0.07, 0), c + d + Vector3(0, 0.07, 0), 0.06, 0.06, BONE)
	for e in [c - d, c + d]:
		k.box(e, Vector3(0.2, 0.15, 0.2), BONE.darkened(0.05))


## 보물 더미(가운데 c): 금화 언덕(큰 것 하나 + 옆·뒤로 작은 것 다섯), 흩어진 금화, 상자 셋(하나는 열려 금이 보인다), 보석, 꽂힌 검, 기댄 방패.
static func _hoard(k, c: Vector3, rng: RandomNumberGenerator) -> void:
	k.rock(c + Vector3(0, -1.1, 0), 3.6, HOARD, rng, 0.62, 0.0)
	for i in 5:  # 옆·뒤로만(앞은 싸움 자리)
		var a := PI + PI * i / 4.0 + rng.randf_range(-0.2, 0.2)
		k.rock(c + Vector3(cos(a), 0, sin(a)) * rng.randf_range(2.8, 3.8) + Vector3(0, -0.5, 0), rng.randf_range(1.1, 1.8), HOARD.lightened(0.05), rng, 0.6, 0.0)
	for i in 110:
		var a := rng.randf_range(0.0, TAU)
		var d := rng.randf_range(3.2, 7.0)
		var p := c + Vector3(cos(a) * d, 0.0, sin(a) * d * 0.8)
		if p.z < c.z - 4.6 and p.x < -2.0:  # 뒤 용암 웅덩이 자리
			continue
		k.xform = Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2)), p)
		k.prism_n(Vector3.ZERO, 6, 0.17, 0.17, 0.05, COIN if rng.randf() < 0.7 else HOARD)
	k.xform = Transform3D.IDENTITY
	_chest(k, c + Vector3(-3.9, 0, 1.6), 0.5, false)
	_chest(k, c + Vector3(3.7, 0, 1.2), -0.4, true)
	_chest(k, c + Vector3(1.8, 0, -3.4), 0.15, false)
	for i in 12:  # 보석: 언덕 위(높이 ≈ 언덕 면)와 둘레
		var a := rng.randf_range(0.0, TAU)
		var d := rng.randf_range(0.5, 2.4) if i < 7 else rng.randf_range(3.5, 5.5)
		var y := maxf(0.05, 1.3 * (1.0 - pow(d / 3.4, 2.0)) - 0.15) if i < 7 else 0.05
		var p := c + Vector3(cos(a) * d, y, sin(a) * d)
		var g: Color = GEMS[i % GEMS.size()]
		var s := rng.randf_range(0.22, 0.34)
		k.prism_n(p, 4, s, 0.0, s * 1.3, g)
		k.xform = Transform3D(Basis(Vector3.RIGHT, PI), p)
		k.prism_n(Vector3.ZERO, 4, s, 0.0, s * 1.0, g.darkened(0.25))
		k.xform = Transform3D.IDENTITY
	k.xform = Transform3D(Basis(Vector3.BACK, 0.25) * Basis(Vector3.RIGHT, -0.2), c + Vector3(0.5, 0.8, 0.4))  # 꽂힌 검
	k.box(Vector3(0, 0, 0), Vector3(0.16, 1.7, 0.05), Color(0.66, 0.68, 0.72))
	k.box(Vector3(0, 1.7, 0), Vector3(0.8, 0.12, 0.14), GOLD)
	k.box(Vector3(0, 1.82, 0), Vector3(0.1, 0.5, 0.1), Color(0.35, 0.15, 0.10))
	k.box(Vector3(0, 2.3, 0), Vector3(0.18, 0.16, 0.18), GOLD)
	k.xform = Transform3D(Basis(Vector3.RIGHT, 1.2), c + Vector3(-2.6, 0.55, 2.2))  # 기댄 방패(앞면이 카메라 쪽)
	k.prism_n(Vector3.ZERO, 8, 0.65, 0.65, 0.08, Color(0.42, 0.44, 0.48), PI / 8.0)
	k.prism_n(Vector3(0, 0.08, 0), 8, 0.5, 0.5, 0.02, Color(0.30, 0.31, 0.35), PI / 8.0)
	k.prism_n(Vector3(0, 0.1, 0), 8, 0.2, 0.14, 0.08, GOLD, PI / 8.0)
	k.xform = Transform3D.IDENTITY


## 보물 상자(바닥 중심 c, yaw): 나무 몸통 + 금 띠 + 뚜껑(열린 것은 뒤로 젖히고 안에 금).
static func _chest(k, c: Vector3, yaw: float, open: bool) -> void:
	var keep: Transform3D = k.xform
	k.xform = Transform3D(Basis(Vector3.UP, yaw), c)
	k.box(Vector3.ZERO, Vector3(1.2, 0.62, 0.78), Color(0.40, 0.24, 0.12))
	for x in [-0.42, 0.42]:
		k.box(Vector3(x, 0, 0), Vector3(0.12, 0.64, 0.8), GOLD)
	if open:
		k.box(Vector3(0, 0.62, 0), Vector3(1.05, 0.08, 0.66), COIN)
		k.xform = k.xform * Transform3D(Basis(Vector3.RIGHT, -1.9), Vector3(0, 0.62, -0.39))  # 뒤 경첩에서 젖힌 뚜껑
		k.box(Vector3(0, 0, 0.4), Vector3(1.24, 0.22, 0.8), Color(0.34, 0.20, 0.10))
	else:
		k.box(Vector3(0, 0.62, 0), Vector3(1.24, 0.24, 0.82), Color(0.34, 0.20, 0.10))
		k.box(Vector3(0, 0.45, 0.39), Vector3(0.2, 0.26, 0.06), GOLD)
	k.xform = keep


## 옛 짐승 갈비뼈(c = 등뼈 가운데, 등뼈는 화면 세로 z — 갈비가 화면에서 아치로 보인다): 마디 등뼈 + 갈비 아치 여섯(뒤로 작아짐, 둘은 부러짐).
static func _ribcage(k, c: Vector3, rng: RandomNumberGenerator) -> void:
	for i in 9:
		k.box(c + Vector3(0, 0, -3.2 + i * 0.8), Vector3(0.36, 0.3, 0.5), BONE.darkened(0.08))
	for i in 6:
		var z := c.z - 2.4 + i * 0.95
		var w := lerpf(1.9, 1.1, i / 5.0)
		var h := lerpf(2.3, 1.3, i / 5.0)
		var broken := i == 2 or i == 4
		var segs := 7
		for j in segs:
			if broken and j >= 4:
				break
			var a0 := PI * j / segs
			var a1 := PI * (j + 1) / segs
			var p0 := Vector3(c.x - cos(a0) * w, sin(a0) * h + 0.15, z)
			var p1 := Vector3(c.x - cos(a1) * w, sin(a1) * h + 0.15, z)
			_bar(k, p0, p1, 0.11, 0.09, BONE.darkened(rng.randf_range(0.0, 0.08)))


## 뿔 달린 큰 해골(바닥 중심 c, 주둥이가 화면 아래 +z): 길쭉한 머리뼈, 검은 눈구멍, 뒤로 휜 뿔 둘, 아래턱 이빨.
static func _horned_skull(k, c: Vector3, rng: RandomNumberGenerator) -> void:
	var keep: Transform3D = k.xform
	k.xform = Transform3D(Basis.from_scale(Vector3(0.95, 0.62, 1.35)), c + Vector3(0, 0.5, 0))
	k.rock(Vector3.ZERO, 1.0, BONE, rng, 1.0, -0.75)
	k.xform = keep
	for x in [-0.42, 0.42]:
		k.box(c + Vector3(x, 0.78, 0.35), Vector3(0.36, 0.26, 0.5), Color(0.12, 0.08, 0.07))
		var root := c + Vector3(x * 1.3, 0.85, -0.6)
		var mid := root + Vector3(x * 1.4, 0.9, -0.55)
		_bar(k, root, mid, 0.22, 0.14, BONE.darkened(0.15), 5)
		_bar(k, mid, mid + Vector3(x * 0.4, 0.55, -0.9), 0.14, 0.02, BONE.darkened(0.2), 5)
	for i in 5:
		k.cone(c + Vector3(-0.5 + i * 0.25, 0.05, 1.05), 4, 0.07, 0.3, BONE.lightened(0.05))


# --- PVP 총력전: 결투장(2026-10-07 디자인 보강 3번) ---

## 결투장 좌표(HALL_YAW: x = 화면 가로 spot v, z = 화면 세로 spot u). 화면 아래(+z) = 내 팀(파랑), 위(−z) = 상대(빨강).
## 모래 바닥(판 셰이더, 면 명암만) 위에: 가운데 분필 원·가운데 줄·엇갈린 두 검, 양 팀 출발 칸(팀 색 테두리), 밟힌 자국·꽂힌 화살·떨어진 방패·지푸라기·돌.
## 양옆(|v| ARENA_WALL~) 낮은 돌벽 + 기둥(깃대·화로), 그 너머 4단 나무 관중석과 관중(cheer 셰이더로 들썩 — 내 쪽 절반은 파랑, 상대 쪽은 빨강 옷이 많다),
## 양 끝(|u| ARENA_END~) 성문(탑 둘·아치·쇠창살·큰 팀 깃발). 벽 쪽은 화면 세로로 서 있어 싸움 따라가기 카메라(가로 20~28 m)의 양옆에 걸린다.
## 돌·나무·바닥 장식은 메시 하나(벽·관중석은 그림자), 관중 메시 하나, 불꽃 MultiMesh 하나. 유닛은 PVP FIELD_R 원 안 + 화면 가로 ARENA_SIDE 안.
static func colosseum() -> Dictionary:
	var root := Node3D.new()
	root.name = "Colosseum"
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	var mat := ShaderMaterial.new()
	mat.shader = GroundShader
	mat.set_shader_parameter("tile_size", 2.0)
	mat.set_shader_parameter("interior_half", 0.0)
	mat.set_shader_parameter("grass_a", GRASS)
	mat.set_shader_parameter("grass_b", GRASS.darkened(0.05))
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.material_override = mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = ARENA_SEED
	var site := Node3D.new()
	site.rotation.y = HALL_YAW
	root.add_child(site)
	var deco = MeshKit.new()  # 바닥 장식(그림자 없음)
	var k = MeshKit.new()  # 벽·관중석·성문(그림자)
	var fans = MeshKit.new()  # 관중
	var fires := []
	_sand(deco, rng)
	_arena_floor(deco, rng)
	for s in [-1.0, 1.0]:
		_arena_side(k, fires, s, rng)
		_stands(k, fans, s, rng)
	var trees := [[], []]
	for e in [-1.0, 1.0]:
		_arena_gate(k, fires, e)
		_camp(k, fires, trees, e, rng)
	var flat := MeshInstance3D.new()
	flat.mesh = deco.commit()
	flat.material_override = Art.lowpoly_vc_material()
	flat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	site.add_child(flat)
	var walls := MeshInstance3D.new()
	walls.mesh = k.commit()
	walls.material_override = Art.lowpoly_vc_material()
	site.add_child(walls)
	var crowd := MeshInstance3D.new()
	crowd.name = "Fans"
	crowd.mesh = fans.commit()
	crowd.material_override = _cheer()
	crowd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	site.add_child(crowd)
	site.add_child(_multimesh(flame_mesh(), fires, _glow(1.0, 0.0, 0.9), false))
	var shapes := [TownKit.tree_pine(rng), TownKit.tree_round(rng)]
	for i in 2:
		site.add_child(_multimesh(shapes[i], trees[i], Art.lowpoly_vc_material(), true))
	var heroes := []
	var enemies := []
	for i in 6:
		heroes.append(spot(16.0 + (i / 3) * 2.6, (i % 3 - 1) * 2.2))
		enemies.append(spot(-16.0 - (i / 3) * 2.6, (i % 3 - 1) * 2.2))
	return {"root": root, "heroes": heroes, "enemies": enemies, "boss": spot(-19.0, 3.3), "light": {
		"background": Color(0.72, 0.85, 0.96), "ambient": Color(0.80, 0.84, 0.90), "ambient_energy": 0.95,
		"sun_color": Color(1.0, 0.95, 0.84), "sun_energy": 1.2, "sun_rot": Vector3(-55, -30, 0), "shadows": true, "omni": []}}


## 모래 바닥(풀밭 위): 벽 안 2 m 칸마다 대각선 두 삼각형(명암 조금씩 — 판 셰이더와 같은 로우폴리 결) + 성문 밖으로 이어지는 흙길.
static func _sand(k, rng: RandomNumberGenerator) -> void:
	var w := ARENA_WALL + 0.2
	var e := ARENA_END + 0.2
	var nx := int(ceil(2.0 * w / 2.0))
	var nz := int(ceil(2.0 * e / 2.0))
	for ix in nx:
		for iz in nz:
			var x0 := -w + 2.0 * w * ix / nx
			var x1 := -w + 2.0 * w * (ix + 1) / nx
			var z0 := -e + 2.0 * e * iz / nz
			var z1 := -e + 2.0 * e * (iz + 1) / nz
			k.face([Vector3(x0, 0.002, z0), Vector3(x1, 0.002, z0), Vector3(x1, 0.002, z1)], Vector3.UP, SAND.darkened(rng.randf_range(-0.04, 0.05)))
			k.face([Vector3(x0, 0.002, z0), Vector3(x1, 0.002, z1), Vector3(x0, 0.002, z1)], Vector3.UP, SAND.darkened(rng.randf_range(-0.04, 0.05)))
	for t in [-1.0, 1.0]:
		var z: float = t * e
		for i in 6:
			var z1: float = z + t * 2.0
			_flat(k, Vector3(-1.9 + rng.randf_range(-0.2, 0.2), 0.002, minf(z, z1)), Vector3(1.9 + rng.randf_range(-0.2, 0.2), 0.002, maxf(z, z1)), SAND_DARK.darkened(rng.randf_range(0.0, 0.06)))
			z = z1


## 모래 바닥 장식: 벽 밑 어두운 띠, 가운데 분필 원·줄·엇갈린 두 검, 팀 출발 칸 테두리, 밟힌 자국, 꽂힌 화살·떨어진 방패·지푸라기·돌.
static func _arena_floor(k, rng: RandomNumberGenerator) -> void:
	var w := ARENA_WALL
	var e := ARENA_END
	for s in [-1.0, 1.0]:
		var z := -e
		while z < e:  # 벽 밑 띠(2 m 조각마다 명암)
			var z1 := minf(e, z + 2.0)
			_flat(k, Vector3(s * (w - 0.9), 0.005, z), Vector3(s * w, 0.005, z1), SAND_DARK.darkened(rng.randf_range(0.0, 0.08)))
			z = z1
		_flat(k, Vector3(-w, 0.005, s * (e - 0.9)), Vector3(w, 0.005, s * e), SAND_DARK)
	var n := 40
	for i in n:  # 가운데 원
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		k.face([d0 * 3.4 + Vector3(0, 0.01, 0), d1 * 3.4 + Vector3(0, 0.01, 0), d1 * 3.72 + Vector3(0, 0.01, 0), d0 * 3.72 + Vector3(0, 0.01, 0)], Vector3.UP, CHALK)
	_flat(k, Vector3(-w + 0.9, 0.01, -0.12), Vector3(-3.72, 0.01, 0.12), CHALK)
	_flat(k, Vector3(3.72, 0.01, -0.12), Vector3(w - 0.9, 0.01, 0.12), CHALK)
	for a in [PI / 4.0, -PI / 4.0]:  # 엇갈린 두 검(분필)
		var b := Basis(Vector3.UP, a)
		_flat_quad(k, b, Vector3(0, 0.012, -0.6), Vector2(0.26, 2.6), CHALK)
		_flat_quad(k, b, Vector3(0, 0.012, 0.85), Vector2(1.0, 0.18), CHALK)
		_flat_quad(k, b, Vector3(0, 0.012, 1.25), Vector2(0.16, 0.6), CHALK)
	for t in [-1.0, 1.0]:  # 팀 출발 칸(내 팀 = +z 파랑)
		var col: Color = (TEAM_BLUE if t > 0.0 else TEAM_RED).lerp(SAND, 0.3)
		var z0: float = t * 12.6
		var z1: float = t * (e - 1.4)
		var lo := minf(z0, z1)
		var hi := maxf(z0, z1)
		_flat(k, Vector3(-6.6, 0.01, lo), Vector3(6.6, 0.01, lo + 0.22), col)
		_flat(k, Vector3(-6.6, 0.01, hi - 0.22), Vector3(6.6, 0.01, hi), col)
		_flat(k, Vector3(-6.6, 0.01, lo), Vector3(-6.38, 0.01, hi), col)
		_flat(k, Vector3(6.38, 0.01, lo), Vector3(6.6, 0.01, hi), col)
	for i in 16:  # 밟힌 자국
		_blot(k, Vector3(rng.randf_range(-w + 1.5, w - 1.5), 0.004, rng.randf_range(-e + 2.0, e - 2.0)), rng.randf_range(0.8, 2.0), 8, SAND_DARK.lerp(SAND, 0.4), rng)
	for i in 22:  # 꽂힌 화살
		var p := Vector3(rng.randf_range(-w + 0.8, w - 0.8), 0, rng.randf_range(-e + 1.0, e - 1.0))
		var tip := p + Vector3(rng.randf_range(-0.2, 0.2), 0.48, rng.randf_range(-0.2, 0.2))
		_bar(k, p, tip, 0.03, 0.03, WOOD, 3)
		k.box(tip - Vector3(0, 0.14, 0), Vector3(0.14, 0.14, 0.03), Color(0.85, 0.83, 0.78))
	for i in 7:  # 떨어진 나무 방패(가운데 팀 색 띠, 쇠 테·손잡이 돌기)
		var p := Vector3(rng.randf_range(-w + 1.0, w - 1.0), 0.0, rng.randf_range(-e + 2.0, e - 2.0))
		var col: Color = TEAM_BLUE if p.z > 0.0 else TEAM_RED
		k.xform = Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis(Vector3.RIGHT, rng.randf_range(-0.15, 0.15)), p)
		k.prism_n(Vector3.ZERO, 8, 0.42, 0.42, 0.05, IRON, PI / 8.0)
		k.prism_n(Vector3(0, 0.05, 0), 8, 0.36, 0.36, 0.02, WOOD, PI / 8.0)
		k.box(Vector3(0, 0.07, 0), Vector3(0.7, 0.01, 0.2), col.darkened(0.15))
		k.prism_n(Vector3(0, 0.07, 0), 6, 0.1, 0.06, 0.06, Color(0.62, 0.62, 0.64))
		k.xform = Transform3D.IDENTITY
	for i in 18:  # 지푸라기
		var p := Vector3(rng.randf_range(-w + 0.6, w - 0.6), 0.02, rng.randf_range(-e + 1.0, e - 1.0))
		for j in 3:
			var a := rng.randf_range(0.0, TAU)
			_bar(k, p, p + Vector3(cos(a) * 0.45, 0.0, sin(a) * 0.45), 0.025, 0.02, STRAW, 3)
	for i in 26:  # 돌
		k.rock(Vector3(rng.randf_range(-w + 0.5, w - 0.5), 0, rng.randf_range(-e + 0.5, e - 0.5)), rng.randf_range(0.08, 0.2), SAND_DARK.darkened(0.2), rng, 0.6, 0.0)


## 바닥과 평행한 직사각형(basis로 돈 중심 c, 크기 sz = (x 폭, z 길이)).
static func _flat_quad(k, b: Basis, c: Vector3, sz: Vector2, color: Color) -> void:
	var hx := sz.x / 2.0
	var hz := sz.y / 2.0
	k.face([b * (c + Vector3(-hx, 0, -hz)), b * (c + Vector3(hx, 0, -hz)), b * (c + Vector3(hx, 0, hz)), b * (c + Vector3(-hx, 0, hz))], Vector3.UP, color)


## 옆벽(s쪽): 4 m 돌 토막(명암 번갈아) + 윗돌, 8 m마다 기둥 — 기둥마다 팀 깃발(벽 쪽 절반 색), 가운데 둘레 기둥엔 화로.
static func _arena_side(k, fires: Array, s: float, rng: RandomNumberGenerator) -> void:
	var x := s * (ARENA_WALL + 0.6)
	var e := ARENA_END + 1.2
	var z := -e
	var i := 0
	while z < e:
		var z1 := minf(e, z + 4.0)
		k.box(Vector3(x, 0, (z + z1) / 2.0), Vector3(1.2, 1.4, z1 - z), ARENA_STONE if i % 2 == 0 else ARENA_STONE.darkened(0.08))
		k.box(Vector3(x, 1.4, (z + z1) / 2.0), Vector3(1.4, 0.22, z1 - z), ARENA_STONE.darkened(0.2))
		z = z1
		i += 1
	for pz in [-18.0, -9.0, 0.0, 9.0, 18.0]:
		var base := Vector3(x, 0, pz)
		k.box(base, Vector3(1.7, 2.3, 1.7), ARENA_STONE.lightened(0.04))
		k.box(base + Vector3(0, 2.3, 0), Vector3(1.9, 0.25, 1.9), ARENA_STONE.darkened(0.2))
		if pz == 0.0:
			_brazier(k, base + Vector3(0, 2.55, 0))
			fires.append(Transform3D(Basis(), base + Vector3(0, 2.55 + BRAZIER_H, 0)))
			continue
		var col: Color = TEAM_BLUE if pz > 0.0 else TEAM_RED
		var pole := base + Vector3(s * 0.4, 2.55, 0)
		k.prism_n(pole, 5, 0.07, 0.07, 3.0, WOOD_DARK)
		k.prism_n(pole + Vector3(0, 3.0, 0), 5, 0.12, 0.0, 0.25, GOLD)
		_flag(k, pole + Vector3(0, 2.9, 0), -s, 1.3, 1.0, col, rng)


## 깃발: 깃대 위 at에서 화면 가로(dir = ±1 → 둥지 x)로 길이 l만큼, 높이 h, 끝이 제비꼬리. 카메라 쪽(+z)을 본다.
static func _flag(k, at: Vector3, dir: float, l: float, h: float, col: Color, rng: RandomNumberGenerator) -> void:
	var sag := rng.randf_range(0.05, 0.15)
	var a := at
	var b := at + Vector3(dir * l, -sag, 0)
	var c := b + Vector3(-dir * 0.3, -h * 0.5, 0)
	var d := b + Vector3(0, -h, 0)
	var e := at + Vector3(0, -h, 0)
	k.face([a, b, c, e], Vector3.BACK, col)
	k.face([e, c, d], Vector3.BACK, col.darkened(0.12))
	k.face([a, b, c, e], Vector3.FORWARD, col.darkened(0.2))
	k.face([e, c, d], Vector3.FORWARD, col.darkened(0.3))
	k.box(at + Vector3(dir * l * 0.5, -h * 0.5 - 0.1, 0.01), Vector3(0.3, 0.3, 0.02), GOLD)


## 관중석(s쪽): 벽 뒤 4단 나무 계단(단마다 0.75 m 높아짐) + 뒤 칸막이, 사람(몸·머리, 넷에 하나는 손을 든다)이 단마다 0.9 m 칸에 72% 앉는다.
## 내 쪽 절반(+z)은 파랑 옷, 상대 쪽은 빨강 옷이 많다. 관중은 fans 메시(cheer 셰이더 — 사람마다 들썩).
static func _stands(k, fans, s: float, rng: RandomNumberGenerator) -> void:
	var x0 := ARENA_WALL + 1.2
	var e := ARENA_END + 1.2
	for t in 4:
		var xa := x0 + t * STAND_ROW
		var top := 0.9 + t * 0.75
		k.box(Vector3(s * (xa + STAND_ROW / 2.0), 0, 0), Vector3(STAND_ROW, top, 2.0 * e), WOOD if t % 2 == 0 else WOOD_DARK)
		k.box(Vector3(s * (xa + 0.12), top, 0), Vector3(0.24, 0.12, 2.0 * e), WOOD_DARK.darkened(0.2))
		var j := 0
		while -e + (j + 0.5) * STAND_SEAT < e:
			var z := -e + (j + 0.5) * STAND_SEAT
			j += 1
			if rng.randf() > 0.72:
				continue
			var team := TEAM_BLUE if z > 0.0 else TEAM_RED
			var shirt: Color = team.lerp(Color.WHITE, rng.randf_range(0.0, 0.2)) if rng.randf() < 0.6 else FAN_SHIRTS[rng.randi_range(0, FAN_SHIRTS.size() - 1)]
			var p := Vector3(s * (xa + STAND_ROW * 0.55 + rng.randf_range(-0.1, 0.1)), top, z)
			fans.box(p, Vector3(0.38, 0.5, 0.3), shirt)
			fans.box(p + Vector3(0, 0.5, 0), Vector3(0.3, 0.3, 0.28), SKINS[rng.randi_range(0, SKINS.size() - 1)])
			if rng.randf() < 0.25:
				var side := rng.randf_range(-1.0, 1.0)
				fans.box(p + Vector3(0.2 * signf(side), 0.38, 0), Vector3(0.1, 0.5, 0.1), shirt)
	var xb := x0 + 4.0 * STAND_ROW
	k.box(Vector3(s * (xb + 0.25), 0, 0), Vector3(0.5, 4.6, 2.0 * e), WOOD_DARK)
	for z in [-16.0, -8.0, 8.0, 16.0]:
		var pole := Vector3(s * (xb + 0.25), 4.6, z)
		k.prism_n(pole, 5, 0.08, 0.08, 2.4, WOOD_DARK)
		_flag(k, pole + Vector3(0, 2.3, 0), -s, 1.1, 0.8, TEAM_BLUE if z > 0.0 else TEAM_RED, rng)


## 팀 진영(성문 밖, e쪽): 흙길 양옆 팀 색 천막 넷(작은 깃발), 모닥불, 통·무기 걸이. 나무 자리는 trees[변형]에 더한다.
static func _camp(k, fires: Array, trees: Array, e: float, rng: RandomNumberGenerator) -> void:
	var col: Color = TEAM_BLUE if e > 0.0 else TEAM_RED
	var z0 := e * (ARENA_END + 4.5)
	for t in [[-4.6, 0.0], [4.6, 0.6], [-9.0, 3.4], [9.2, 3.0]]:
		var p := Vector3(t[0], 0, z0 + e * t[1])
		k.box(p, Vector3(2.6, 1.0, 2.6), Color(0.86, 0.84, 0.78))
		k.pyramid(p + Vector3(0, 1.0, 0), 3.8, 1.8, col)
		k.prism_n(p + Vector3(0, 2.8, 0), 4, 0.05, 0.05, 0.9, WOOD_DARK)
		k.face([p + Vector3(0, 3.7, 0), p + Vector3(0.7, 3.55, 0), p + Vector3(0, 3.35, 0)], Vector3.BACK, col.lightened(0.2))
		k.box(p + Vector3(0, 0, 1.31 * e), Vector3(0.8, 0.9, 0.02), Color(0.20, 0.16, 0.14))
	var fire := Vector3(0.0, 0, z0 + e * 4.0)
	_fire_bed(k, fire, 0.8, rng)
	fires.append(Transform3D(Basis().scaled(Vector3.ONE * 0.8), fire))
	for x in [-2.6, 2.6]:  # 통
		k.prism_n(Vector3(x, 0, z0 - e * 1.2), 8, 0.35, 0.35, 0.8, WOOD, PI / 8.0)
		k.prism_n(Vector3(x, 0.8, z0 - e * 1.2), 8, 0.36, 0.36, 0.06, IRON, PI / 8.0)
	var rack := Vector3(6.8, 0, z0 - e * 1.5)  # 무기 걸이: 가로대 + 기댄 창 넷
	k.box(rack + Vector3(-1.0, 0, 0), Vector3(0.12, 1.2, 0.12), WOOD_DARK)
	k.box(rack + Vector3(1.0, 0, 0), Vector3(0.12, 1.2, 0.12), WOOD_DARK)
	k.box(rack + Vector3(0, 1.0, 0), Vector3(2.2, 0.1, 0.1), WOOD_DARK)
	for i in 4:
		var b := rack + Vector3(-0.75 + i * 0.5, 0, 0.25)
		_bar(k, b, b + Vector3(0, 2.0, -0.3), 0.04, 0.04, WOOD, 3)
		k.cone(b + Vector3(0, 2.0, -0.3), 4, 0.08, 0.3, Color(0.70, 0.72, 0.76))
	for i in 6:
		var p := Vector3(rng.randf_range(10.0, 15.0) * (1.0 if i % 2 == 0 else -1.0), 0, z0 + e * rng.randf_range(2.0, 9.0))
		trees[i % 2].append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)), p))


## 끝 성문(e = −1 위 = 상대 빨강, 1 아래 = 내 팀 파랑): 양쪽 끝벽, 탑 둘(톱니), 아치 위 들보, 어두운 문 안 쇠창살, 들보 앞 큰 팀 깃발, 탑 위 화로.
static func _arena_gate(k, fires: Array, e: float) -> void:
	var z := e * (ARENA_END + 1.2)  # 탑 가운데(안쪽 면 = ARENA_END)
	var col: Color = TEAM_BLUE if e > 0.0 else TEAM_RED
	var span := ARENA_WALL + 1.2
	for sx in [-1.0, 1.0]:
		var xa: float = sx * 4.2
		var xb: float = sx * span
		var wz := e * (ARENA_END + 0.6)
		k.box(Vector3((xa + xb) / 2.0, 0, wz), Vector3(absf(xb - xa), 1.4, 1.2), ARENA_STONE)
		k.box(Vector3((xa + xb) / 2.0, 1.4, wz), Vector3(absf(xb - xa), 0.22, 1.4), ARENA_STONE.darkened(0.2))
		var tx: float = sx * 3.0
		k.box(Vector3(tx, 0, z), Vector3(2.4, 5.2, 2.4), ARENA_STONE.lightened(0.04))
		for m in 4:
			var o: Vector3 = [Vector3(-0.85, 0, -0.85), Vector3(0.85, 0, -0.85), Vector3(0.85, 0, 0.85), Vector3(-0.85, 0, 0.85)][m]
			k.box(Vector3(tx, 5.2, z) + o, Vector3(0.6, 0.6, 0.6), ARENA_STONE.darkened(0.12))
		_brazier(k, Vector3(tx, 5.2, z))
		fires.append(Transform3D(Basis(), Vector3(tx, 5.2 + BRAZIER_H, z)))
	k.box(Vector3(0, 3.6, z), Vector3(3.6, 1.1, 1.6), ARENA_STONE.darkened(0.06))
	k.box(Vector3(0, 0, z), Vector3(3.6, 3.6, 0.3), Color(0.10, 0.08, 0.07))
	for i in 5:
		k.box(Vector3(-1.4 + i * 0.7, 0, z + 0.2), Vector3(0.1, 3.6, 0.1), IRON)
	for y in [1.2, 2.4]:
		k.box(Vector3(0, y, z + 0.2), Vector3(3.6, 0.1, 0.1), IRON)
	var front := z + 0.82  # 카메라 쪽(+z) 면
	k.face([Vector3(-1.1, 4.6, front), Vector3(1.1, 4.6, front), Vector3(1.1, 2.2, front), Vector3(0, 1.6, front), Vector3(-1.1, 2.2, front)], Vector3.BACK, col)
	k.box(Vector3(0, 3.5, front), Vector3(0.6, 0.6, 0.04), GOLD)


static func _lava(fall: bool) -> ShaderMaterial:
	var key := "lava_fall" if fall else "lava"
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = LavaShader
		m.set_shader_parameter("fall", fall)
		m.set_shader_parameter("flow", Vector2(DOWN.x, DOWN.z) * 0.35)  # 화면 아래로 흐른다
		_mats[key] = m
	return _mats[key]


## 관중 재질(cheer 셰이더): 사람 칸(seat·row)과 그 시작점을 _stands와 맞춘다.
static func _cheer() -> ShaderMaterial:
	if not _mats.has("cheer"):
		var m := ShaderMaterial.new()
		m.shader = CheerShader
		m.set_shader_parameter("use_texture", false)
		m.set_shader_parameter("use_vertex_color", true)
		m.set_shader_parameter("seat", STAND_SEAT)
		m.set_shader_parameter("seat_from", -(ARENA_END + 1.2))
		m.set_shader_parameter("row", STAND_ROW)
		m.set_shader_parameter("row_from", ARENA_WALL + 1.2)
		_mats.cheer = m
	return _mats.cheer


# --- 던전 몬스터 코드 부품(Art.MONSTER_MODELS parts) ---

## 뼈 공간 부품 노드. 머리 뼈 공간 = 목 원점, +Y 위, +Z 얼굴 앞(Rogue 얼굴 앞면 z ≈ 0.45, 옆 |x| ≈ 0.5, 정수리 y ≈ 0.95,
## Skeleton_Warrior 투구 얼굴 구멍 y 0.1~0.45 · 이마 z ≈ 0.45). 가슴 뼈 공간 = 등 위쪽 원점(어깨 망토 뒷면 z ≈ −0.36).
## 손 슬롯 공간 = 손잡이 원점, +Y가 무기 끝(KayKit 무기와 같은 규약). 메시는 id마다 공유.
static func part(id: String) -> Node3D:
	if id == "dk_eyes":
		return _dk_eyes()
	if not _meshes.has(id):
		var k = MeshKit.new()
		match id:
			"goblin_face": _goblin_face(k, GOBLIN_SKIN)
			"king_face": _goblin_face(k, KING_SKIN)
			"crown": _crown(k)
			"king_club": _club(k)
			"dk_cape": _cape(k)
			"dk_sword": _greatsword(k)
			_: push_error("unknown part %s" % id)
		_meshes[id] = k.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[id]
	mi.material_override = Art.lowpoly_vc_material()
	return mi


## base → tip 원뿔(sides각, 밑 반지름 r). flat < 1이면 원뿔 축과 옆(X) 방향에 수직인 쪽으로 납작하게(귀가 앞을 보는 넓은 면). k.xform을 쓰고 되돌린다.
static func _spike(k, base: Vector3, tip: Vector3, r: float, flat: float, sides: int, color: Color) -> void:
	var y := tip - base
	var x := y.cross(Vector3.BACK)
	x = Vector3.RIGHT if x.length() < 0.001 else x.normalized()
	var z := x.cross(y).normalized()
	k.xform = Transform3D(Basis(x, y.normalized(), z * flat), base)
	k.cone(Vector3.ZERO, sides, r, y.length(), color, PI / sides)
	k.xform = Transform3D.IDENTITY


## 고블린 얼굴: 옆으로 길게 뻗은 납작한 귀 둘(앞면에 짙은 귓속) + 앞 아래로 굽은 큰 코. 머리 뼈 공간.
static func _goblin_face(k, skin: Color) -> void:
	for s in [-1.0, 1.0]:
		_spike(k, Vector3(s * 0.44, 0.42, -0.02), Vector3(s * 1.02, 0.68, -0.22), 0.17, 0.35, 4, skin)
		_spike(k, Vector3(s * 0.48, 0.42, 0.03), Vector3(s * 0.86, 0.60, -0.10), 0.08, 0.35, 4, skin.darkened(0.35))
	_spike(k, Vector3(0, 0.34, 0.38), Vector3(0, 0.20, 0.70), 0.12, 1.0, 4, skin.darkened(0.1))


## 왕관: 금 8각 띠 + 뾰족한 끝 8개 + 붉은 벨벳 윗면 + 앞 보석. 머리 뼈 공간(정수리 위에 얹힌다).
static func _crown(k) -> void:
	k.prism_n(Vector3(0, 0.78, 0), 8, 0.43, 0.45, 0.2, GOLD, PI / 8.0)
	k.prism_n(Vector3(0, 0.9, 0), 8, 0.4, 0.4, 0.06, Color(0.55, 0.12, 0.12), PI / 8.0)
	for i in 8:
		var a := TAU * i / 8.0
		k.cone(Vector3(cos(a) * 0.4, 0.98, sin(a) * 0.4), 4, 0.08, 0.22, GOLD)
	k.box(Vector3(0, 0.82, 0.44), Vector3(0.12, 0.12, 0.05), DK_RED)


## 왕 몽둥이(손 슬롯 공간, +Y 끝): 굵어지는 나무 자루 + 각진 큰 머리(세로로 긴 20면체) + 쇠 가시 6개. 길이 ≈ 1.45.
static func _club(k) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	k.prism_n(Vector3(0, -0.25, 0), 6, 0.06, 0.08, 1.0, TownKit.WOOD_DARK)
	k.rock(Vector3(0, 0.95, 0), 0.26, TownKit.WOOD, rng, 1.6)
	for i in 6:
		var a := TAU * i / 6.0 + 0.3
		var y := 0.8 + 0.25 * (i % 2)
		var d := Vector3(cos(a), 0.25, sin(a)).normalized()
		_spike(k, Vector3(0, y, 0) + d * 0.18, Vector3(0, y, 0) + d * 0.42, 0.05, 1.0, 4, TownKit.METAL)


## 데스나이트 대검(손 슬롯 공간, +Y 끝): 검은 가죽 손잡이 + 폼멜, 끝이 위로 꺾인 가시 코등이(붉은 보석), 마름모 단면 검은 칼날
## (한쪽 면 밝게) + 가운데 붉은 홈. 길이 ≈ 1.95(× 2.2 ≈ 4.3 m).
static func _greatsword(k) -> void:
	k.prism_n(Vector3(0, -0.38, 0), 6, 0.08, 0.06, 0.1, DK_STEEL)
	k.prism_n(Vector3(0, -0.3, 0), 6, 0.045, 0.05, 0.42, Color(0.16, 0.11, 0.10))
	k.box(Vector3(0, 0.1, 0), Vector3(0.62, 0.1, 0.14), DK_STEEL)
	for s in [-1.0, 1.0]:
		_spike(k, Vector3(s * 0.28, 0.15, 0), Vector3(s * 0.46, 0.34, 0), 0.06, 1.0, 4, DK_STEEL)
	k.box(Vector3(0, 0.12, 0.07), Vector3(0.1, 0.08, 0.02), DK_RED)
	var w := 0.12
	var t := 0.035
	var y0 := 0.2
	var y1 := 1.4
	var tip := Vector3(0, 1.62, 0)
	var e := [Vector3(-w, 0, 0), Vector3(0, 0, t), Vector3(w, 0, 0), Vector3(0, 0, -t)]  # 단면: 왼날, 앞 등, 오른날, 뒤 등
	for i in 4:
		var a: Vector3 = e[i]
		var b: Vector3 = e[(i + 1) % 4]
		var col := DK_STEEL.lightened(0.18) if i % 2 == 0 else DK_STEEL
		var out := (a + b) / 2.0
		k.face([a + Vector3(0, y0, 0), b + Vector3(0, y0, 0), b + Vector3(0, y1, 0), a + Vector3(0, y1, 0)], out, col)
		k.face([a + Vector3(0, y1, 0), b + Vector3(0, y1, 0), tip], out + Vector3(0, 0.05, 0), col)
	for z in [t + 0.002, -t - 0.002]:
		k.face([Vector3(-0.025, 0.3, z), Vector3(0.025, 0.3, z), Vector3(0.012, 1.25, z), Vector3(-0.012, 1.25, z)], Vector3(0, 0, signf(z)), DK_RED)


## 찢어진 검은 망토(가슴 뼈 공간, 등 뒤로 늘어짐): 주름 띠 셋, 아래 끝은 이빨처럼 찢김. 바깥 숯검정, 안쪽 검붉은 색(양면).
static func _cape(k) -> void:
	var top_x := [-0.40, -0.13, 0.13, 0.40]
	var bot_x := [-0.55, -0.18, 0.18, 0.55]
	var top_z := [-0.34, -0.38, -0.34, -0.38]
	var bot_z := [-0.62, -0.70, -0.62, -0.70]
	var tooth := [0.28, 0.12, 0.32]
	var y_top := 0.30
	var y_bot := -0.80
	for i in 3:
		var tl := Vector3(top_x[i], y_top, top_z[i])
		var tr := Vector3(top_x[i + 1], y_top, top_z[i + 1])
		var br := Vector3(bot_x[i + 1], y_bot + 0.06 * (i % 2), bot_z[i + 1])
		var bl := Vector3(bot_x[i], y_bot, bot_z[i])
		var tip := (bl + br) / 2.0 - Vector3(0, tooth[i], 0.03)
		var pts := [tl, tr, br, tip, bl]
		k.face(pts, Vector3(0, 0, -1), Color(0.13, 0.11, 0.14))
		k.face(pts, Vector3(0, 0, 1), Color(0.36, 0.07, 0.07))


## 데스나이트 눈빛(머리 뼈 공간): 투구 얼굴 구멍 안 붉게 빛나는 다이아몬드 둘(빛 계산 없음) + 앞을 보는 더하기 후광 6각판 둘.
static func _dk_eyes() -> Node3D:
	if not _meshes.has("dk_eye_gem"):
		var g = MeshKit.new()
		var halo = MeshKit.new()
		for s in [-1.0, 1.0]:
			var c := Vector3(s * 0.19, 0.40, 0.36)
			g.cone(c, 4, 0.075, 0.06, Color.WHITE, PI / 4.0)
			g.xform = Transform3D(Basis(Vector3.RIGHT, PI), c)
			g.cone(Vector3.ZERO, 4, 0.075, 0.05, Color.WHITE, PI / 4.0)
			g.xform = Transform3D.IDENTITY
			halo.xform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), c + Vector3(0, 0, 0.04))
			halo.prism_n(Vector3.ZERO, 6, 0.12, 0.12, 0.01, Color(1.0, 0.2, 0.08))
		_meshes.dk_eye_gem = g.commit()
		_meshes.dk_eye_halo = halo.commit()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Art.DK_EYES.lightened(0.15)
		_mats.dk_eye = m
	var root := Node3D.new()
	root.name = "DkEyes"
	var gem := MeshInstance3D.new()
	gem.mesh = _meshes.dk_eye_gem
	gem.material_override = _mats.dk_eye
	gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(gem)
	var halo_mi := MeshInstance3D.new()
	halo_mi.mesh = _meshes.dk_eye_halo
	halo_mi.material_override = _glow(0.0, 0.0, 1.0)
	halo_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(halo_mi)
	return root


# --- 장비 드랍(개정 18 §4: 빛기둥 + 등급 색 상자) ---

## 드랍 상자: 등급 색 몸통 + 둥근(반 6각) 뚜껑, 쇠 띠 둘, 금 자물쇠. 원점 = 바닥 가운데, 폭 0.9 m, 높이 ≈ 0.76 m. 그림자 없음.
static func drop_chest(grade: String) -> MeshInstance3D:
	var key := "chest" + grade
	if not _meshes.has(key):
		var col: Color = Art.ITEM_GRADE_COLORS.get(grade, Art.ITEM_GRADE_COLORS.N).darkened(0.2)  # 윗면이 하얗게 날지 않게
		var k = MeshKit.new()
		k.box(Vector3.ZERO, Vector3(0.9, 0.5, 0.6), col.darkened(0.2))
		k.xform = Transform3D(Basis(Vector3.BACK, -PI / 2.0), Vector3(-0.45, 0.5, 0))
		k.prism_n(Vector3.ZERO, 6, 0.3, 0.3, 0.9, col, PI / 6.0)
		for x in [0.15, 0.67]:
			k.prism_n(Vector3(0, x, 0), 6, 0.315, 0.315, 0.08, IRON, PI / 6.0)
		k.xform = Transform3D.IDENTITY
		for x in [-0.26, 0.26]:
			k.box(Vector3(x, 0, 0), Vector3(0.08, 0.51, 0.62), IRON)
		k.box(Vector3(0, 0.3, 0.3), Vector3(0.14, 0.18, 0.05), GOLD)
		_meshes[key] = k.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	mi.material_override = Art.lowpoly_vc_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## 드랍 빛기둥: 등급 색 6각 관 두 겹(바깥 옅게, 안쪽 밝게), 위로 갈수록 사라진다(glow 더하기). 원점 = 바닥, 높이 PILLAR_H. 그림자 없음.
static func light_pillar(grade: String) -> MeshInstance3D:
	var key := "pillar" + grade
	if not _meshes.has(key):
		var col: Color = Art.ITEM_GRADE_COLORS.get(grade, Art.ITEM_GRADE_COLORS.N)
		var k = MeshKit.new()
		_tube(k, [[0.0, 0.7], [PILLAR_H, 0.45]], 6, col.darkened(0.45))
		_tube(k, [[0.0, 0.3], [PILLAR_H, 0.2]], 6, col.lightened(0.35))
		_meshes[key] = k.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	mi.material_override = _glow(0.0, PILLAR_H, 1.2)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

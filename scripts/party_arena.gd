extends RefCounted
## 파티 퀘스트 무대(party_battle.gd). ArenaKit 빌더와 같은 모양 {root, light, seats, boss} — 로우폴리 정점 색, 그림자 없는 장식.
## crypt(): 리치의 무덤 — 어두운 판석 바닥, 둘레에 부서진 기둥·묘비·해골 더미, 뒤에 석관 제단, 청록 영혼불 화로.
## nest(): 거미 여왕의 둥지 — 흙빛 동굴 바닥, 둘레 바위벽, 사방으로 뻗은 거미줄, 알 더미·고치·뼈, 뒤에 여왕의 거대한 거미줄.
## 싸움 자리는 가운데 반경 FIGHT_R 안(장식은 그 밖). 보스는 화면 위(spot u < 0), 성주 자리는 화면 아래.

const Art := preload("res://scripts/art.gd")
const MeshKit := preload("res://scripts/mesh_kit.gd")
const ArenaKit := preload("res://scripts/arena_kit.gd")
const GroundShader := preload("res://shaders/ground_grid.gdshader")

const FIGHT_R := 13.0
const BOSS_U := -6.0
const SEAT_U := 7.0

const CRYPT_STONE := Color(0.34, 0.35, 0.40)
const CRYPT_DARK := Color(0.21, 0.21, 0.26)
const CRYPT_LIGHT := Color(0.47, 0.48, 0.53)
const CRYPT_MOSS := Color(0.27, 0.36, 0.30)
const SOUL := Color(0.35, 1.0, 0.80)
const CURSE := Color(0.62, 0.32, 0.95)

const NEST_DIRT := Color(0.33, 0.27, 0.22)
const NEST_DARK := Color(0.19, 0.15, 0.13)
const NEST_ROCK := Color(0.40, 0.34, 0.30)
const WEB := Color(0.86, 0.86, 0.82)
const EGG := Color(0.88, 0.85, 0.74)
const VENOM := Color(0.55, 0.95, 0.25)


static func spot(u: float, v: float) -> Vector3:
	return ArenaKit.spot(u, v)


## 성주 자리 n개(화면 아래 한 줄, 가운데부터).
static func seat_spots(n: int) -> Array:
	var out := []
	for i in n:
		out.append(spot(SEAT_U, (i - (n - 1) / 2.0) * 3.0))
	return out


static func _ground(a: Color, b: Color) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(240, 240)
	var mat := ShaderMaterial.new()
	mat.shader = GroundShader
	mat.set_shader_parameter("tile_size", 2.0)
	mat.set_shader_parameter("interior_half", 0.0)
	mat.set_shader_parameter("grass_a", a)
	mat.set_shader_parameter("grass_b", b)
	mat.set_shader_parameter("line_color", Color(0, 0, 0, 0.0))
	mat.set_shader_parameter("facet_variation", 0.12)
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.material_override = mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ground


static func _commit(k, parent: Node3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	mi.material_override = Art.lowpoly_vc_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## 빛나는 불꽃 묶음(MultiMesh, 가산 셰이더). 색 = tint(바깥) → 흰빛(심).
static func _flames(parent: Node3D, spots: Array, scale: float, tint: Color) -> void:
	var k = MeshKit.new()
	k.cone(Vector3.ZERO, 6, 0.42, 1.25, tint.darkened(0.2))
	k.cone(Vector3.ZERO, 5, 0.30, 0.95, tint)
	k.cone(Vector3.ZERO, 4, 0.16, 0.62, tint.lerp(Color.WHITE, 0.6), 0.3)
	k.cone(Vector3(0.24, 0, 0.06), 4, 0.13, 0.6, tint.darkened(0.1), 0.2)
	var xf := []
	for p in spots:
		xf.append(Transform3D(Basis().scaled(Vector3.ONE * scale), p))
	parent.add_child(ArenaKit._multimesh(k.commit(), xf, ArenaKit._glow(1.0, 0.0, 0.9), false))


# --- 리치의 무덤 ---

static func crypt() -> Dictionary:
	var root := Node3D.new()
	root.name = "Crypt"
	root.add_child(_ground(CRYPT_STONE, CRYPT_STONE.darkened(0.08)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var site := Node3D.new()
	site.rotation.y = ArenaKit.HALL_YAW  # 사이트 좌표: +z = 화면 아래, +x = 화면 오른쪽
	root.add_child(site)
	var k = MeshKit.new()
	# 바닥: 판석 무늬(어두운 칸·이끼 얼룩), 가운데 소환진(보라 고리 두 겹 + 룬 조각)
	for i in 70:
		var c := Vector3(rng.randf_range(-16, 16), 0.012, rng.randf_range(-16, 16))
		k.box(c, Vector3(rng.randf_range(1.2, 2.0), 0.03, rng.randf_range(1.2, 2.0)), CRYPT_DARK if rng.randf() < 0.5 else CRYPT_LIGHT.darkened(0.12))
	for i in 14:
		ArenaKit._blot(k, Vector3(rng.randf_range(-15, 15), 0.03, rng.randf_range(-15, 15)), rng.randf_range(0.6, 1.4), 7, CRYPT_MOSS, rng)
	_rune_circle(k, Vector3(0, 0.04, BOSS_U), 4.2, rng)
	# 둘레: 부서진 기둥 두 줄, 묘비, 해골 더미, 바위
	for side in [-1.0, 1.0]:
		for z in [-12.0, -6.0, 0.0, 6.0, 12.0]:
			var h := rng.randf_range(2.0, 6.5)
			k.prism_n(Vector3(side * 15.5, 0, z), 6, 0.95, 0.85, h, CRYPT_LIGHT.darkened(rng.randf_range(0.0, 0.15)))
			k.box(Vector3(side * 15.5, 0, z), Vector3(2.4, 0.5, 2.4), CRYPT_DARK)
			if h < 3.5:  # 무너진 기둥 조각
				k.rock(Vector3(side * (14.0 + rng.randf() * 1.5), 0, z + rng.randf_range(-1.5, 1.5)), 0.7, CRYPT_LIGHT.darkened(0.1), rng, 0.6, 0.0)
	for i in 16:
		var a := rng.randf() * TAU
		var r := rng.randf_range(FIGHT_R + 1.5, 19.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if p.z < -10.0 and absf(p.x) < 6.0:
			continue  # 제단 앞은 비운다
		_tombstone(k, p, rng)
	for i in 10:
		var a := rng.randf() * TAU
		var r := rng.randf_range(FIGHT_R + 0.5, 18.0)
		_skull_pile(k, Vector3(cos(a) * r, 0, sin(a) * r), rng)
	for i in 30:
		var a := rng.randf() * TAU
		var r := rng.randf_range(19.0, 34.0)
		ArenaKit._crag(k, Vector3(cos(a) * r, 0, sin(a) * r), rng.randf_range(2.0, 4.0), rng.randf_range(3.0, 8.0), rng, -Vector3(cos(a), 0, sin(a)),
			[CRYPT_DARK.darkened(0.2), CRYPT_DARK, CRYPT_STONE, CURSE.darkened(0.55)])
	for i in 12:
		ArenaKit._bone(k, Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12)), rng.randf() * TAU, rng.randf_range(0.4, 0.8))
	# 뒤: 제단(계단 셋 + 석관 + 뒤 아치)
	var alt := Vector3(0, 0, -17.5)
	for s in 3:
		k.box(alt + Vector3(0, s * 0.35, 0), Vector3(11.0 - s * 2.0, 0.35, 6.0 - s * 1.2), CRYPT_LIGHT.darkened(0.06 * s))
	k.box(alt + Vector3(0, 1.05, 0), Vector3(2.0, 0.9, 3.6), CRYPT_DARK)
	k.box(alt + Vector3(0, 1.95, 0), Vector3(2.3, 0.25, 3.9), CRYPT_STONE)
	for x in [-4.5, 4.5]:
		k.prism_n(alt + Vector3(x, 0, -2.6), 4, 0.8, 0.7, 7.0, CRYPT_STONE, PI / 4.0)
	k.box(alt + Vector3(0, 7.0, -2.6), Vector3(10.6, 1.2, 1.4), CRYPT_STONE)
	k.pyramid(alt + Vector3(0, 8.2, -2.6), 2.0, 1.6, CRYPT_DARK)
	_commit(k, site)
	# 영혼불 화로(청록 불꽃 + 점광원)
	var braziers := [Vector3(-9.5, 0, -11.0), Vector3(9.5, 0, -11.0), Vector3(-12.0, 0, 4.0), Vector3(12.0, 0, 4.0), Vector3(-3.6, 0, -16.0), Vector3(3.6, 0, -16.0)]
	var fk = MeshKit.new()
	var fires := []
	for b in braziers:
		fk.prism_n(b, 6, 0.35, 0.25, 1.0, CRYPT_DARK)
		fk.prism_n(b + Vector3(0, 1.0, 0), 6, 0.55, 0.65, 0.3, CRYPT_STONE)
		fires.append(b + Vector3(0, 1.3, 0))
	_commit(fk, site)
	_flames(site, fires, 0.75, SOUL)
	var mist := _mist(SOUL.darkened(0.3), Vector3(16, 0.2, 16))
	site.add_child(mist)
	var hw := Basis(Vector3.UP, ArenaKit.HALL_YAW)
	return {"root": root, "seats": seat_spots(4), "boss": spot(BOSS_U, 0.0), "light": {
		"background": Color(0.05, 0.06, 0.09), "ambient": Color(0.55, 0.58, 0.72), "ambient_energy": 0.85,
		"sun_color": Color(0.70, 0.78, 1.0), "sun_energy": 0.75, "sun_rot": Vector3(-58, -35, 0), "shadows": true,
		"omni": [[hw * Vector3(-9.5, 2.2, -11.0), SOUL, 1.6, 12.0], [hw * Vector3(9.5, 2.2, -11.0), SOUL, 1.6, 12.0],
			[hw * Vector3(0.0, 3.0, BOSS_U), CURSE, 1.4, 11.0]]}}


static func _rune_circle(k, c: Vector3, r: float, rng: RandomNumberGenerator) -> void:
	for ring in [[r, 0.16], [r * 0.72, 0.1]]:
		var n := 28
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			var p0: Vector3 = c + Vector3(cos(a0), 0, sin(a0)) * ring[0]
			var p1: Vector3 = c + Vector3(cos(a1), 0, sin(a1)) * ring[0]
			var q0: Vector3 = c + Vector3(cos(a0), 0, sin(a0)) * (ring[0] - ring[1])
			var q1: Vector3 = c + Vector3(cos(a1), 0, sin(a1)) * (ring[0] - ring[1])
			k.face([p0, p1, q1, q0], Vector3.UP, CURSE.darkened(0.25))
	for i in 8:  # 룬 조각(고리 사이 작은 각진 패)
		var a := TAU * i / 8.0 + rng.randf_range(-0.05, 0.05)
		var p := c + Vector3(cos(a), 0, sin(a)) * r * 0.86
		k.box(p, Vector3(0.36, 0.02, 0.36), CURSE.darkened(0.1))


static func _tombstone(k, p: Vector3, rng: RandomNumberGenerator) -> void:
	var col := CRYPT_LIGHT.darkened(rng.randf_range(0.0, 0.2))
	var tilt := rng.randf_range(-0.25, 0.25)
	var keep: Transform3D = k.xform
	k.xform = keep * Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, tilt), p)
	k.box(Vector3.ZERO, Vector3(0.9, 1.3, 0.25), col)
	k.prism_n(Vector3(0, 1.3, 0), 6, 0.45, 0.2, 0.3, col)
	k.box(Vector3(0, 0, 0.5), Vector3(1.0, 0.12, 1.4), CRYPT_DARK)
	k.xform = keep


static func _skull_pile(k, p: Vector3, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(3, 6):
		var o := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
		var s := rng.randf_range(0.26, 0.36)
		k.box(p + o + Vector3(0, i * 0.04, 0), Vector3(s, s * 0.9, s), ArenaKit.BONE.darkened(rng.randf_range(0.0, 0.15)))
		k.box(p + o + Vector3(0, i * 0.04 + s * 0.35, s * 0.52), Vector3(s * 0.7, s * 0.18, 0.02), Color(0.08, 0.08, 0.1))  # 눈구멍 줄


## 바닥에 낮게 깔린 안개(입자).
static func _mist(color: Color, box: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 28
	p.lifetime = 5.0
	p.preprocess = 5.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
	p.direction = Vector3(1, 0.1, 0)
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.35
	p.scale_amount_min = 3.0
	p.scale_amount_max = 5.0
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(color, 0.10)
	q.material = m
	p.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.5, Color(1, 1, 1, 1))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	p.color_ramp = g
	return p


# --- 거미 여왕의 둥지 ---

static func nest() -> Dictionary:
	var root := Node3D.new()
	root.name = "Nest"
	root.add_child(_ground(NEST_DIRT, NEST_DIRT.darkened(0.07)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 43
	var site := Node3D.new()
	site.rotation.y = ArenaKit.HALL_YAW
	root.add_child(site)
	var k = MeshKit.new()
	for i in 24:
		ArenaKit._blot(k, Vector3(rng.randf_range(-16, 16), 0.02, rng.randf_range(-16, 16)), rng.randf_range(0.8, 2.0), 7, NEST_DARK if rng.randf() < 0.6 else NEST_ROCK, rng)
	for i in 30:  # 바닥 거미줄 자국(가는 흰 줄)
		var a := rng.randf() * TAU
		var p := Vector3(rng.randf_range(-14, 14), 0.03, rng.randf_range(-14, 14))
		var q := p + Vector3(cos(a), 0, sin(a)) * rng.randf_range(1.5, 3.5)
		_strand(k, p, q, 0.025, WEB.darkened(0.25))
	# 둘레 바위벽(안쪽으로 기운 큰 바위) — 앞(화면 아래)은 낮게
	for i in 40:
		var a := TAU * i / 40.0 + rng.randf_range(-0.05, 0.05)
		var r := rng.randf_range(FIGHT_R + 4.0, FIGHT_R + 8.0)
		var front := sin(a) > 0.5  # +z 쪽(화면 아래)
		ArenaKit._crag(k, Vector3(cos(a) * r, 0, sin(a) * r), rng.randf_range(2.2, 3.6), rng.randf_range(2.0, 3.0) if front else rng.randf_range(5.0, 10.0), rng,
			-Vector3(cos(a), 0, sin(a)), [NEST_DARK.darkened(0.2), NEST_DARK, NEST_ROCK, VENOM.darkened(0.6)])
	# 벽과 벽, 벽과 바닥을 잇는 거미줄
	for i in 26:
		var a := rng.randf() * TAU
		var r0 := FIGHT_R + 4.5
		var top := Vector3(cos(a) * r0, rng.randf_range(2.5, 6.0), sin(a) * r0)
		if sin(a) > 0.5:
			top.y = 2.0
		var b := a + rng.randf_range(-0.5, 0.5)
		var low := Vector3(cos(b) * rng.randf_range(FIGHT_R + 0.5, FIGHT_R + 3.0), 0.05, sin(b) * rng.randf_range(FIGHT_R + 0.5, FIGHT_R + 3.0))
		_strand(k, top, low, 0.04, WEB)
	# 뒤: 여왕의 큰 거미줄(바퀴살 + 나선) 두 벽 사이
	_web_wheel(k, Vector3(0, 6.0, -18.5), 6.5)
	# 알 더미·고치·뼈
	for c in [Vector3(-10.5, 0, -8.0), Vector3(10.5, 0, -6.0), Vector3(-12.0, 0, 6.0), Vector3(11.5, 0, 8.0), Vector3(-5.0, 0, -15.0), Vector3(6.0, 0, -15.5)]:
		_egg_cluster(k, c, rng)
	for i in 8:
		var a := rng.randf() * TAU
		var r := rng.randf_range(FIGHT_R + 0.5, FIGHT_R + 3.5)
		_cocoon(k, Vector3(cos(a) * r, 0, sin(a) * r), rng)
	for i in 14:
		ArenaKit._bone(k, Vector3(rng.randf_range(-13, 13), 0, rng.randf_range(-13, 13)), rng.randf() * TAU, rng.randf_range(0.4, 0.9))
	_commit(k, site)
	var glow := []  # 독 웅덩이 빛(작은 초록 불꽃)
	for c in [Vector3(-12.5, 0, -2.0), Vector3(12.8, 0, 0.0), Vector3(-3.0, 0, -16.5), Vector3(3.5, 0, -16.8)]:
		glow.append(c + Vector3(0, 0.1, 0))
	_flames(site, glow, 0.6, VENOM)
	site.add_child(_mist(VENOM.darkened(0.4), Vector3(16, 0.2, 16)))
	var hw := Basis(Vector3.UP, ArenaKit.HALL_YAW)
	return {"root": root, "seats": seat_spots(3), "boss": spot(BOSS_U, 0.0), "light": {
		"background": Color(0.07, 0.05, 0.04), "ambient": Color(0.66, 0.60, 0.54), "ambient_energy": 0.85,
		"sun_color": Color(0.95, 0.88, 0.75), "sun_energy": 0.8, "sun_rot": Vector3(-60, -35, 0), "shadows": true,
		"omni": [[hw * Vector3(-12.5, 1.5, -2.0), VENOM, 1.5, 10.0], [hw * Vector3(12.8, 1.5, 0.0), VENOM, 1.5, 10.0],
			[hw * Vector3(0.0, 4.0, -15.0), Color(0.9, 0.85, 0.7), 1.0, 12.0]]}}


static func _strand(k, a: Vector3, b: Vector3, r: float, color: Color) -> void:
	ArenaKit._bar(k, a, b, r, r, color, 3)


static func _web_wheel(k, c: Vector3, r: float) -> void:
	var spokes := 12
	var pts := []
	for i in spokes:
		var a := TAU * i / spokes
		var p := c + Vector3(cos(a) * r, sin(a) * r * 0.8, 0)
		p.y = maxf(p.y, 0.1)
		pts.append(p)
		_strand(k, c, p, 0.05, WEB)
	for ring in 6:
		var f := 0.2 + ring * 0.14
		for i in spokes:
			var a: Vector3 = c.lerp(pts[i], f)
			var b: Vector3 = c.lerp(pts[(i + 1) % spokes], f + 0.012)
			_strand(k, a, b, 0.03, WEB.darkened(0.08))


static func _egg_cluster(k, c: Vector3, rng: RandomNumberGenerator) -> void:
	_blot_web(k, c, 1.6, rng)
	for i in rng.randi_range(5, 9):
		var o := Vector3(rng.randf_range(-0.9, 0.9), 0, rng.randf_range(-0.9, 0.9))
		k.rock(c + o + Vector3(0, 0.25, 0), rng.randf_range(0.28, 0.45), EGG.darkened(rng.randf_range(0.0, 0.15)), rng, 1.2, 0.0)


static func _blot_web(k, c: Vector3, r: float, rng: RandomNumberGenerator) -> void:
	ArenaKit._blot(k, c + Vector3(0, 0.025, 0), r, 9, WEB.darkened(0.45), rng, 0.2)


static func _cocoon(k, p: Vector3, rng: RandomNumberGenerator) -> void:
	var keep: Transform3D = k.xform
	k.xform = keep * Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, PI / 2.0 - 0.15), p + Vector3(0, 0.35, 0))
	k.prism_n(Vector3(0, -0.8, 0), 6, 0.1, 0.4, 0.8, WEB.darkened(0.1))
	k.prism_n(Vector3.ZERO, 6, 0.4, 0.12, 0.9, WEB.darkened(0.05))
	k.xform = keep

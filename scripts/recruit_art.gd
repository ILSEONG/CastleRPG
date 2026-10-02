extends RefCounted
## 모집 창 키 아트(개정 23 §5): 이그니스(SSR 화염 대마법사)가 화염구를 쏘는 순간. SceneSnap.snap(KEY, SIZE, build, WARM)으로 한 번 렌더해 캐시한다.
## 장면(build가 root 아래에 만든다): 어두운 그라데이션 배경 판, 각진 원형 단상(+ 빛나는 테두리), 공격 자세(발사 순간 프레임)의 이그니스
## (영웅 외형 = Art.hero_spec → UnitModel, 영웅 외형 작업이 바꾸면 그대로 따른다), 앞쪽 큰 화염 20면체(노란 핵 + 주황 가산 껍질),
## 불꽃 파편, 빛기둥, 불씨, 뒤에서 비추는 림 라이트, 살짝 낮은 각도(올려다보는) 카메라.
## 노드 이름은 테스트가 구조를 본다: Environment, Camera, KeyLight, RimLight, FireLight, Backdrop, Pedestal, PedestalGlow, Pillar,
## Ignis, Fireball(Core·Shell), Shards, Embers.

const Art := preload("res://scripts/art.gd")
const GameData := preload("res://scripts/game_data.gd")
const MeshKit := preload("res://scripts/mesh_kit.gd")
const Fx := preload("res://scripts/fx.gd")
const UnitModelScript := preload("res://scripts/unit_model.gd")

const KEY := "recruit_key_art"
const VIEW := Vector2(632, 300)  # 창 안 표시 크기(논리 px, 창 내용 폭 × 약 300)
const SIZE := Vector2i(1264, 600)  # 2배로 렌더
const WARM := 6  # 찍기 전 프레임(시전 자세·가산 재질이 자리 잡게)
const HERO := "ignis"
const HERO_YAW := 28.0  # 화염구(오른쪽 앞)를 향해 돈다
const FIREBALL_POS := Vector3(1.75, 1.75, 1.0)
const FIREBALL_R := 0.62
const LOOK_AT := Vector3(0.55, 1.45, 0.0)
const CAM_POS := Vector3(0.9, 0.75, 6.4)  # 바라보는 곳보다 낮게 — 영웅적 올려다보기
const CAM_FOV := 34.0
const FIRE := Color(1.0, 0.45, 0.10)
const FIRE_CORE := Color(1.0, 0.86, 0.35)
const SEED := 23


static func build(root: Node3D) -> void:
	_environment(root)
	_lights(root)
	_backdrop(root)
	_pedestal(root)
	_hero(root)
	_fireball(root)
	_particles(root)


static func _environment(root: Node3D) -> void:
	var we := WorldEnvironment.new()
	we.name = "Environment"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.03, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.36, 0.52)
	e.ambient_light_energy = 0.55
	e.glow_enabled = true  # 불꽃 번짐(지원하는 렌더러에서만)
	e.glow_intensity = 0.9
	e.glow_bloom = 0.15
	we.environment = e
	root.add_child(we)
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.fov = CAM_FOV
	cam.near = 0.1
	cam.far = 40.0
	cam.current = true
	root.add_child(cam)
	cam.transform = Transform3D(Basis.looking_at(LOOK_AT - CAM_POS, Vector3.UP), CAM_POS)  # 트리 밖에서도(look_at은 트리 안만)


## 앞 왼쪽 위 차가운 주광 + 뒤 위 주황 림 라이트(윤곽) + 화염구 자리의 불빛.
static func _lights(root: Node3D) -> void:
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_color = Color(0.72, 0.78, 1.0)
	key.light_energy = 0.7
	root.add_child(key)
	key.rotation_degrees = Vector3(-35, -30, 0)
	var rim := OmniLight3D.new()
	rim.name = "RimLight"
	rim.light_color = Color(1.0, 0.55, 0.22)
	rim.light_energy = 7.0
	rim.omni_range = 6.0
	rim.position = Vector3(-0.6, 2.8, -1.8)
	root.add_child(rim)
	var fire := OmniLight3D.new()
	fire.name = "FireLight"
	fire.light_color = FIRE
	fire.light_energy = 5.0
	fire.omni_range = 5.0
	fire.position = FIREBALL_POS
	root.add_child(fire)


## 배경 판: 위 짙은 보라 → 아래 불씨 빨강 세로 그라데이션(빛을 안 받는다).
static func _backdrop(root: Node3D) -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0.06, 0.04, 0.12))
	g.set_color(1, Color(0.42, 0.13, 0.06))
	g.add_point(0.6, Color(0.20, 0.07, 0.12))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex
	var q := QuadMesh.new()
	q.size = Vector2(26, 13)
	var mi := MeshInstance3D.new()
	mi.name = "Backdrop"
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.5, 2.5, -7.0)
	root.add_child(mi)


## 각진 10각 돌 단상 + 위 테두리의 빛나는 고리.
static func _pedestal(root: Node3D) -> void:
	var k = MeshKit.new()
	k.prism_n(Vector3(0, -0.45, 0), 10, 1.75, 1.55, 0.45, Color(0.30, 0.27, 0.33))
	k.prism_n(Vector3(0, -0.75, 0), 10, 2.05, 1.85, 0.3, Color(0.22, 0.20, 0.25), PI / 10.0)
	var mi := MeshInstance3D.new()
	mi.name = "Pedestal"
	mi.mesh = k.commit()
	mi.material_override = Fx.material()
	root.add_child(mi)
	var ring := TorusMesh.new()
	ring.inner_radius = 1.52
	ring.outer_radius = 1.64
	ring.rings = 10
	ring.ring_segments = 4
	var glow := MeshInstance3D.new()
	glow.name = "PedestalGlow"
	glow.mesh = ring
	glow.material_override = _glow(FIRE, 0.9)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow)


## 이그니스: 영웅 외형 그대로(UnitModel). 트리에 들어가면(ready) 공격 애니메이션의 발사 순간으로 멈춘다(manual — 스스로 안 돈다).
static func _hero(root: Node3D) -> void:
	var m = UnitModelScript.new()
	m.name = "Ignis"
	m.manual = true
	m.setup(Art.hero_spec(GameData.hero(HERO)))
	m.rotation_degrees.y = HERO_YAW
	m.ready.connect(func(): _pose(m))
	root.add_child(m)


static func _pose(m) -> void:
	var hit: float = m.play_attack(1.0)  # 처음부터 — 반환 = 발사 순간까지 초
	m.advance(hit)


## 큰 화염 20면체: 노란 핵(빛 안 받음) + 주황 가산 껍질. 빛기둥은 단상 뒤에서 솟는다.
static func _fireball(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var ball := Node3D.new()
	ball.name = "Fireball"
	ball.position = FIREBALL_POS
	root.add_child(ball)
	for part in [["Core", FIRE_CORE, 0.72, 1.0], ["Shell", FIRE, 1.0, 0.75]]:
		var k = MeshKit.new()
		k.rock(Vector3.ZERO, FIREBALL_R * part[2], part[1], rng, 1.0)
		var mi := MeshInstance3D.new()
		mi.name = part[0]
		mi.mesh = k.commit()
		mi.material_override = _glow(part[1], part[3])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ball.add_child(mi)
	var pillar := CylinderMesh.new()
	pillar.top_radius = 0.75
	pillar.bottom_radius = 1.1
	pillar.height = 9.0
	pillar.radial_segments = 8
	pillar.rings = 1
	var pmi := MeshInstance3D.new()
	pmi.name = "Pillar"
	pmi.mesh = pillar
	pmi.material_override = _glow(Color(1.0, 0.62, 0.25), 0.22)
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pmi.position = Vector3(0, 4.2, -1.2)
	root.add_child(pmi)


## 화염구 둘레로 튀는 각진 파편(3각뿔) + 장면에 흩날리는 불씨(작은 20면체). 메시 하나씩(그리기 호출 둘).
static func _particles(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1
	var k = MeshKit.new()
	for i in 12:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-0.4, 1)).normalized()
		var at := FIREBALL_POS + dir * FIREBALL_R * rng.randf_range(1.3, 2.1)
		k.xform = Transform3D(Basis(Vector3.UP.cross(dir).normalized() if absf(dir.y) < 0.99 else Vector3.RIGHT, Vector3.UP.angle_to(dir)), at)
		k.cone(Vector3.ZERO, 3, 0.09, rng.randf_range(0.25, 0.45), FIRE.lerp(FIRE_CORE, rng.randf()))
	var shards := MeshInstance3D.new()
	shards.name = "Shards"
	shards.mesh = k.commit()
	shards.material_override = _glow(Color.WHITE, 0.95, true)
	shards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shards)
	var e = MeshKit.new()
	for i in 28:
		var at := Vector3(rng.randf_range(-3.5, 4.0), rng.randf_range(0.0, 4.2), rng.randf_range(-2.0, 2.0))
		e.rock(at, rng.randf_range(0.03, 0.07), FIRE.lerp(FIRE_CORE, rng.randf()), rng, 1.0)
	var embers := MeshInstance3D.new()
	embers.name = "Embers"
	embers.mesh = e.commit()
	embers.material_override = _glow(Color.WHITE, 0.9, true)
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(embers)


## 빛 안 받는 가산 재질. vertex = 정점 색을 쓴다(MeshKit 메시).
static func _glow(color: Color, alpha: float, vertex := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = vertex
	m.albedo_color = Color(color, alpha)
	return m

extends Node
## 계절(개정 22 §4). 스테이지 S의 계절 = (S − 1) mod 4 → 0 봄, 1 여름, 2 가을, 3 겨울. S = floor((g − 1) / rounds_per_stage) + 1(g = GameState.stage).
## 바꾸는 것: 성 밖 바닥(격자 셰이더 grass_a·grass_b, 겨울은 성 안 가장자리 눈 얼룩 edge_snow), 나무·덤불·산 MultiMesh 메시(같은 rng 상태 +
## 계절 팔레트로 다시 만든 변형 — 처음 쓸 때 만들어 캐시, 여름 = 기본 메시, 바위는 그대로), 하늘·환경광·해 색, 입자 하나(꽃잎·낙엽·눈, 여름 없음).
## 시작: 현재 스테이지 계절로 바로(apply instant). 스테이지가 바뀌면(리필 = 라운드 25 클리어 뒤 다음 라운드 전, 또는 Seasons.set_stage(S))
## 색을 BLEND_SEC 동안 섞고 가운데에 메시를 갈아 끼우며, 화면 가운데 "스테이지 N · 계절" 띠를 띄운다.
## 개발용 `-- --season=N`(웹 `?season=N`, 디버그 빌드만): 그 계절로 시작. 오토로드는 /root에서 찾는다(헤드리스 -s 테스트가 이 파일을 preload).

const Balance := preload("res://scripts/balance.gd")
const GameData := preload("res://scripts/game_data.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

const NAMES := ["봄", "여름", "가을", "겨울"]
const BANNER_TEXT := "스테이지 %d · %s"
const BLEND_SEC := 1.2
const BANNER_SEC := 1.8  # 띠가 다 보이는 시간(나타남·사라짐 제외)
const ROUNDS_PER_STAGE := 25  # 설정 rounds_per_stage가 없을 때
const MAX_PARTICLES := 150
const PARTICLE_AHEAD := 25.0  # 입자 판: 카메라가 보는 바닥 지점에서 카메라 쪽으로 이만큼(성채 지붕 위)
const PARTICLE_LIFE := 7.0

## 계절마다: 바닥 grass_a·grass_b(·edge_snow), 하늘 sky, 환경광 ambient, 해 sun·sun_energy, 레시피 이름 → TownKit 팔레트
## (사전 = 모든 변형, 배열 = 변형 번호 % 크기, 없음 = 기본 메시), 입자(amount·colors·size m·speed m/s·spin, 빈 사전 = 없음).
## 정점 색 윗면은 해를 받아 밝아지므로 채널 ≤ 0.69(town_kit 팔레트 주석).
const PALETTES := [
	{  # 봄: 밝은 연두, 연두 수관 + 분홍 벚꽃 나무, 꽃잎, 따뜻한 흰빛
		"grass_a": Color(0.50, 0.60, 0.36), "grass_b": Color(0.475, 0.575, 0.335),
		"sky": Color(0.88, 0.93, 0.95), "ambient": Color(0.80, 0.81, 0.84), "sun": Color(1.0, 0.97, 0.92), "sun_energy": 1.1,
		"tree_pine": {"leaf": Color(0.44, 0.66, 0.34), "leaf_dark": Color(0.30, 0.52, 0.30)},
		"tree_round": [{"leaf": Color(0.66, 0.42, 0.52)}, {"leaf": Color(0.52, 0.68, 0.32)}, {"leaf": Color(0.68, 0.52, 0.58)}],
		"bush": {"bush": Color(0.36, 0.56, 0.30)},
		"mountain": {"low": Color(0.40, 0.60, 0.34), "snow_line": 0.75},
		"particles": {"amount": 50, "colors": [Color(0.98, 0.72, 0.82), Color(1.0, 0.86, 0.90)], "size": 0.8, "speed": 1.0, "spin": true},
	},
	{  # 여름: 진한 초록(기본 메시·바닥 기본값), 맑음, 밝은 노란빛
		"grass_a": Color(0.441, 0.511, 0.372), "grass_b": Color(0.417, 0.487, 0.347),
		"sky": Color(0.82, 0.90, 0.98), "ambient": Color(0.78, 0.80, 0.86), "sun": Color(1.0, 0.95, 0.82), "sun_energy": 1.15,
		"particles": {},
	},
	{  # 가을: 황갈·주황 풀, 주황·빨강·노랑 수관, 낙엽, 오후 주황빛
		"grass_a": Color(0.56, 0.50, 0.32), "grass_b": Color(0.53, 0.45, 0.29),
		"sky": Color(0.94, 0.88, 0.80), "ambient": Color(0.84, 0.78, 0.72), "sun": Color(1.0, 0.84, 0.64), "sun_energy": 1.05,
		"tree_pine": {"leaf": Color(0.30, 0.48, 0.30), "leaf_dark": Color(0.22, 0.38, 0.26)},
		"tree_round": [{"leaf": Color(0.68, 0.40, 0.16)}, {"leaf": Color(0.62, 0.24, 0.16)}, {"leaf": Color(0.68, 0.56, 0.18)}],
		"bush": {"bush": Color(0.55, 0.32, 0.18)},
		"mountain": {"low": Color(0.56, 0.44, 0.24)},
		"particles": {"amount": 80, "colors": [Color(0.95, 0.55, 0.18), Color(0.85, 0.28, 0.16), Color(0.96, 0.78, 0.25)], "size": 0.9, "speed": 1.3, "spin": true},
	},
	{  # 겨울: 눈 덮인 흰·하늘색, 침엽수 위 눈, 앙상한 활엽수, 눈, 차가운 푸른빛, 산 눈 띠 아래로
		"grass_a": Color(0.66, 0.70, 0.76), "grass_b": Color(0.62, 0.67, 0.73), "edge_snow": 0.6,
		"sky": Color(0.84, 0.89, 0.95), "ambient": Color(0.76, 0.82, 0.92), "sun": Color(0.86, 0.92, 1.0), "sun_energy": 1.0,
		"tree_pine": {"leaf": Color(0.24, 0.42, 0.32), "leaf_dark": Color(0.18, 0.34, 0.28), "snow": true},
		"tree_round": {"bare": true},
		"bush": {"bush": Color(0.60, 0.64, 0.69)},
		"mountain": {"low": Color(0.56, 0.60, 0.64), "rock_line": 0.18, "snow_line": 0.42},
		"particles": {"amount": 150, "colors": [Color(1.0, 1.0, 1.0)], "size": 0.5, "speed": 2.0, "spin": false},
	},
]

static var _live  # 지금 월드의 인스턴스(set_stage가 넘긴다)
static var _cache := {}  # "레시피:번호:rng 상태:계절" → 메시(월드를 다시 만들어도 공유)
static var _particle_mat: StandardMaterial3D
static var _particle_mesh: QuadMesh

var env: Environment
var sun: DirectionalLight3D
var ground: ShaderMaterial
var scenery  # buildings.gd(season_slots)
var camera: Camera3D
var stage := 0  # 지금 계절을 맞춘 스테이지 S
var season := -1
var _tween: Tween
var _particles := CPUParticles3D.new()
var _fit_size := 0.0  # 입자 판을 맞춘 카메라 폭


static func season_of_stage(s: int) -> int:
	return posmod(s - 1, 4)


static func rounds_per_stage() -> int:
	var n := int(GameData.config_num("rounds_per_stage"))
	return n if n > 0 else ROUNDS_PER_STAGE


## 전체 라운드 g → 스테이지 S.
static func stage_of_round(g: int) -> int:
	return floori((maxi(g, 1) - 1) / float(rounds_per_stage())) + 1


## 라운드 로직 훅: 스테이지 S로(같으면 무시). 살아 있는 월드가 없으면 아무 일 없음.
static func set_stage(s: int) -> void:
	if is_instance_valid(_live):
		_live.change_stage(s)


## 계절 팔레트로 다시 만든 변형(캐시). 그 레시피에 팔레트가 없으면(여름·바위) 기본 메시.
static func variant(slot: Dictionary, s: int) -> Mesh:
	var recipe: String = slot.recipe.get_method()
	var pal = PALETTES[s].get(recipe)
	if pal == null:
		return slot.base
	if pal is Array:
		pal = pal[slot.idx % pal.size()]
	var key := "%s:%d:%d:%d" % [recipe, slot.idx, slot.state, s]
	if not _cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.state = slot.state
		_cache[key] = slot.recipe.call(rng, pal)
	return _cache[key]


func _init() -> void:
	_particles.local_coords = false  # 입자는 월드에 남고 판만 카메라를 따라간다
	_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_particles.lifetime = PARTICLE_LIFE
	_particles.preprocess = PARTICLE_LIFE  # 계절이 바뀌자마자 화면이 차 있게
	_particles.direction = Vector3(0.25, -1.0, 0.0)  # 판 기준(화면 아래 + 약간 오른쪽)
	_particles.spread = 20.0
	_particles.gravity = Vector3.ZERO
	var curve := Curve.new()  # 생겨날 때·사라질 때 크기 0 → 투명 없이 튀지 않게
	for p in [Vector2(0, 0), Vector2(0.15, 1), Vector2(0.85, 1), Vector2(1, 0)]:
		curve.add_point(p)
	_particles.scale_amount_curve = curve
	if _particle_mat == null:
		_particle_mat = StandardMaterial3D.new()
		_particle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_particle_mat.vertex_color_use_as_albedo = true
		_particle_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_particle_mat.billboard_keep_scale = true
		_particle_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_particle_mesh = QuadMesh.new()
	_particles.mesh = _particle_mesh
	_particles.material_override = _particle_mat
	_particles.emitting = false
	_particles.visible = false
	add_child(_particles)


func setup(e: Environment, s: DirectionalLight3D, g: ShaderMaterial, sc, cam: Camera3D) -> void:
	env = e
	sun = s
	ground = g
	scenery = sc
	camera = cam


func _ready() -> void:
	_live = self
	var gs = get_node_or_null("/root/GameState")
	stage = stage_of_round(gs.stage) if gs != null else 1
	var start := season_of_stage(stage)
	var dbg := _debug_season()
	if dbg >= 0:
		start = dbg
		print("[season] %d" % dbg)
	apply(start, true)
	if gs != null:
		gs.refilled.connect(func(): change_stage(stage_of_round(gs.stage)))  # 라운드 사이 리필에서 스테이지가 넘어갔으면


## 스테이지 S로 바꾼다: 계절 전환(섞기) + 띠. 같은 S면 무시.
func change_stage(s: int) -> void:
	if s == stage:
		return
	stage = s
	apply(season_of_stage(s))
	if is_inside_tree():
		_show_banner(BANNER_TEXT % [s, NAMES[season]])


## 계절 적용. instant(또는 트리 밖)면 곧바로, 아니면 색은 BLEND_SEC 동안 섞고 메시는 가운데에 갈아 끼운다. 입자는 곧바로.
func apply(s: int, instant := false) -> void:
	season = posmod(s, 4)
	var p: Dictionary = PALETTES[season]
	if _tween != null:
		_tween.kill()
	_set_particles(p.particles)
	var targets := [[ground, "shader_parameter/grass_a", p.grass_a], [ground, "shader_parameter/grass_b", p.grass_b],
		[ground, "shader_parameter/edge_snow", p.get("edge_snow", 0.0)], [env, "background_color", p.sky],
		[env, "ambient_light_color", p.ambient], [sun, "light_color", p.sun], [sun, "light_energy", p.sun_energy]]
	targets = targets.filter(func(t): return t[0] != null)
	if instant or not is_inside_tree():
		for t in targets:
			t[0].set(t[1], t[2])
		_swap_meshes(season)
		return
	_tween = create_tween().set_parallel()
	for t in targets:
		_tween.tween_property(t[0], t[1], t[2], BLEND_SEC)
	_tween.tween_callback(_swap_meshes.bind(season)).set_delay(BLEND_SEC / 2.0)


func _swap_meshes(s: int) -> void:
	if scenery == null:
		return
	for slot in scenery.season_slots:
		slot.mm.mesh = variant(slot, s)


func _set_particles(cfg: Dictionary) -> void:
	_particles.emitting = not cfg.is_empty()
	_particles.visible = not cfg.is_empty()
	if cfg.is_empty():
		return
	_particles.amount = mini(cfg.amount, MAX_PARTICLES)
	var g := Gradient.new()  # 입자마다 무작위 한 색(계단 보간)
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offsets := PackedFloat32Array()
	for i in cfg.colors.size():
		offsets.append(float(i) / cfg.colors.size())
	g.offsets = offsets
	g.colors = PackedColorArray(cfg.colors)
	_particles.color_initial_ramp = g
	_particles.angle_max = 360.0 if cfg.spin else 0.0
	_particles.angular_velocity_min = -120.0 if cfg.spin else 0.0
	_particles.angular_velocity_max = 120.0 if cfg.spin else 0.0
	_fit_particles()
	if is_inside_tree():  # 미리 돌리기(preprocess)는 판을 카메라 앞에 둔 뒤에
		_follow_camera()
		_particles.restart()


## 입자 판 = 화면 크기 상자(카메라 기준). 크기·속도는 카메라 폭(줌)에 비례 — 화면에서 늘 비슷하게 보인다.
func _fit_particles() -> void:
	var cfg: Dictionary = PALETTES[season].particles
	if cfg.is_empty():
		return
	var w := camera.size if camera != null else Balance.CAMERA_SIZE_DEFAULT
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(9, 16)
	var k := w / Balance.CAMERA_SIZE_DEFAULT
	_fit_size = w
	_particles.emission_box_extents = Vector3(w / 2.0, w * vp.y / vp.x / 2.0, 4.0)
	_particles.scale_amount_min = cfg.size * k * 0.7
	_particles.scale_amount_max = cfg.size * k
	_particles.initial_velocity_min = cfg.speed * k * 0.8
	_particles.initial_velocity_max = cfg.speed * k * 1.2


func _process(_delta: float) -> void:
	if camera == null or not _particles.emitting:
		return
	if camera.size != _fit_size:
		_fit_particles()
	_follow_camera()


func _follow_camera() -> void:
	if camera != null:
		_particles.global_transform = camera.global_transform.translated_local(Vector3(0, 0, PARTICLE_AHEAD - camera.position.length()))


## 화면 가운데 가로 띠 "스테이지 N · 계절": 나타남 → BANNER_SEC → 사라짐. 입력은 통과.
func _show_banner(text: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4  # HUD·탭 바(3) 위
	var band := PanelContainer.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM_PANEL, 0.0, 18))
	band.set_anchors_and_offsets_preset(Control.PRESET_HCENTER_WIDE)
	band.grow_vertical = Control.GROW_DIRECTION_BOTH
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 44)
	label.add_theme_color_override("font_color", UiKit.INK)
	band.add_child(label)
	layer.add_child(band)
	add_child(layer)
	band.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(band, "modulate:a", 1.0, 0.25)
	t.tween_interval(BANNER_SEC)
	t.tween_property(band, "modulate:a", 0.0, 0.4)
	t.tween_callback(layer.queue_free)


func _debug_season() -> int:
	var net = get_node_or_null("/root/Net")
	if net == null or not OS.is_debug_build():
		return -1
	var v: String = net.arg_value("season")
	return int(v) if v.is_valid_int() and int(v) >= 0 and int(v) <= 3 else -1

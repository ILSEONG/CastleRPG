extends Node3D
## 월드 조립. 씬 파일은 이것 하나. 나머지는 코드로 생성.
## 개발용 auto-stage: 네이티브는 유저 인자 `-- --auto-stage`, 웹은 URL에 `?auto-stage` → 시작 즉시 스테이지 진행.

const Balance := preload("res://scripts/balance.gd")
const Art := preload("res://scripts/art.gd")
const CastleScript := preload("res://scripts/castle.gd")
const BuildingsScript := preload("res://scripts/buildings.gd")
const CameraRigScript := preload("res://scripts/camera_rig.gd")
const FormationScript := preload("res://scripts/formation.gd")
const HeroScript := preload("res://scripts/hero.gd")
const PickerScript := preload("res://scripts/unit_picker.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")
const HudScript := preload("res://scripts/hud.gd")
const HpBarsScript := preload("res://scripts/hp_bars.gd")
const GroundShader := preload("res://shaders/ground_grid.gdshader")

var camera: Camera3D
var castle


func _ready() -> void:
	_build_environment()
	castle = CastleScript.new()
	add_child(castle)
	_build_ground(castle.half)
	var scenery = BuildingsScript.new()
	scenery.half = castle.half
	add_child(scenery)
	var rig = CameraRigScript.new()
	add_child(rig)
	camera = rig.camera
	var bars = HpBarsScript.new()
	bars.camera = camera
	add_child(bars)
	var formation = FormationScript.new()
	for i in GameState.hero_count():
		var hero = HeroScript.new()
		hero.setup(i, castle, formation)
		add_child(hero)
	var picker = PickerScript.new()
	picker.camera = camera
	add_child(picker)
	var spawner = SpawnerScript.new()
	spawner.castle = castle
	add_child(spawner)
	add_child(HudScript.new())
	if OS.is_debug_build():
		_connect_dev_log()
	if _auto_stage_requested():
		seed(1)  # 스폰 흩어짐 고정 → E2E 로그 재현
		GameState.start_stage()


func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.86, 0.91, 0.96)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.78, 0.80, 0.86)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL  # 분할 없음: 모바일 부담 최소
	sun.directional_shadow_max_distance = 220.0
	add_child(sun)
	sun.rotation_degrees = Vector3(-50, -45, 0)  # 카메라(요 45°) 시선을 가로지르게 → 그림자가 화면 오른쪽 바닥에 드리운다


func _build_ground(interior_half: float) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (Balance.MAP_HALF + Art.BORDER_OUTER + 15.0) * 2.0
	var mat := ShaderMaterial.new()
	mat.shader = GroundShader
	mat.set_shader_parameter("tile_size", Balance.TILE)
	mat.set_shader_parameter("interior_half", interior_half)
	mat.set_shader_parameter("road_half", Balance.TILE)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _connect_dev_log() -> void:
	GameState.mode_changed.connect(func(m): print("[mode] %d stage=%d" % [m, GameState.stage]))
	GameState.stage_cleared.connect(func(s): print("[cleared] %d" % s))
	GameState.stage_failed.connect(func(s): print("[failed] %d" % s))


func _auto_stage_requested() -> bool:
	if OS.get_cmdline_user_args().has("--auto-stage"):
		return true
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("window.location.search")).contains("auto-stage")
	return false

extends Node3D
## 월드 조립. 씬 파일은 이것 하나. 나머지는 코드로 생성.
## 개발용 auto-stage: 네이티브는 유저 인자 `-- --auto-stage`, 웹은 URL에 `?auto-stage` → 시작 즉시 스테이지 진행.

const Balance := preload("res://scripts/balance.gd")
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
		Economy.save_path = ""  # 개발 실행은 실제 저장 파일을 건드리지 않는다
		seed(1)  # 스폰 흩어짐 고정 → E2E 로그 재현
		GameState.start_stage()
	if OS.is_debug_build() and _flag_requested("econ-demo"):
		_econ_demo()


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


## 바닥은 픽셀 셰이더 평면 한 장이라 크기는 공짜 — 카메라가 보여 줄 수 있는 곳을 다 덮는다: 팬 한계 + 최대 줌아웃에서
## 19.5:9 세로 화면이 비추는 바닥 직사각형(가로 반폭 w, 세로는 1/sin(피치)로 늘어난 h)의 대각선 반(요와 무관하게 덮는다).
func _build_ground(interior_half: float) -> void:
	var w := Balance.CAMERA_SIZE_MAX / 2.0
	var h := w * 19.5 / 9.0 / sin(deg_to_rad(-CameraRigScript.PITCH_DEG))
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (Balance.MAP_HALF - CameraRigScript.PAN_LIMIT_MARGIN + Vector2(w, h).length()) * 2.0
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
	return _flag_requested("auto-stage")


## 네이티브는 유저 인자 `-- --flag`, 웹은 URL `?flag`.
func _flag_requested(flag: String) -> bool:
	if OS.get_cmdline_user_args().has("--" + flag):
		return true
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("window.location.search")).contains(flag)
	return false


## 개발용: 저장 안 함, 마지막 수집 30분 전, 자원 각 500, 골드 1234.
func _econ_demo() -> void:
	var now := Time.get_unix_time_from_system()
	Economy.save_path = ""
	Economy.reset(now)
	for b in Economy.last_collect:
		Economy.last_collect[b] = now - 1800.0
	for id in Economy.res:
		Economy.res[id] = 500
	Economy.gold = 1234
	Economy.changed.emit()

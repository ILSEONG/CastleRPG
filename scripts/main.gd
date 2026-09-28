extends Node3D
## 월드 조립. 씬 파일은 이것 하나. 나머지는 코드로 생성.
## 개발용 auto-stage: 네이티브는 유저 인자 `-- --auto-stage`, 웹은 URL에 `?auto-stage` → 시작 즉시 스테이지 진행.

const Balance := preload("res://scripts/balance.gd")
const Flat := preload("res://scripts/flat.gd")
const CastleScript := preload("res://scripts/castle.gd")
const HeroScript := preload("res://scripts/hero.gd")
const PickerScript := preload("res://scripts/unit_picker.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")
const HudScript := preload("res://scripts/hud.gd")

var camera: Camera3D
var castle
var heroes: Array = []


func _ready() -> void:
	_build_world()
	castle = CastleScript.new()
	add_child(castle)
	for i in GameState.hero_count():
		var hero = HeroScript.new()
		hero.castle = castle
		hero.index = i
		hero.assigned_side = i % 4
		add_child(hero)
		heroes.append(hero)
	var picker = PickerScript.new()
	picker.camera = camera
	add_child(picker)
	var spawner = SpawnerScript.new()
	spawner.castle = castle
	add_child(spawner)
	add_child(HudScript.new())
	_connect_dev_log()
	if _auto_stage_requested():
		GameState.start_stage()


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.88, 0.90, 0.94)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = false
	add_child(sun)
	sun.rotation_degrees = Vector3(-55, 35, 0)

	var ground := PlaneMesh.new()
	ground.size = Vector2(60, 60)
	add_child(Flat.mesh(ground, Flat.GROUND))

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = 26.0
	add_child(camera)
	camera.position = Vector3(0, 24, 24)
	camera.look_at(Vector3.ZERO)


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

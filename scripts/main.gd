extends Node3D
## 월드 조립. 씬 파일은 이것 하나. 나머지는 코드로 생성.
## 개발용 유저 인자(-- 뒤): --shot=SECONDS  그 시각에 res://tools/shot.png 저장 후 종료
##                          --auto-stage    시작 즉시 스테이지 진행

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

var _shot_at := -1.0
var _elapsed := 0.0


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
	_apply_dev_args()


func _process(delta: float) -> void:
	if _shot_at < 0.0:
		return
	_elapsed += delta
	if _elapsed >= _shot_at:
		_shot_at = -1.0
		var err := get_viewport().get_texture().get_image().save_png("res://tools/shot.png")
		print("shot saved err=%d" % err)
		get_tree().quit()


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


func _apply_dev_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_at = float(arg.get_slice("=", 1))
		elif arg == "--auto-stage":
			GameState.start_stage()
	GameState.mode_changed.connect(func(m): print("[mode] %d stage=%d" % [m, GameState.stage]))
	GameState.stage_cleared.connect(func(s): print("[cleared] %d" % s))
	GameState.stage_failed.connect(func(s): print("[failed] %d" % s))

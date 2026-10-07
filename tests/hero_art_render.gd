extends Node
## 영웅 일러스트 원본 렌더(개발용, 2026-10-07): 영웅마다 3D 모델을 첫 액티브 스킬 발동 자세(발동 순간 프레임)로 세우고, 살짝 아래에서
## 올려다보는 원근 카메라 + 앞 왼쪽 따뜻한 주광 + 뒤 양옆 영웅 고유 색 역광으로 1024 px 투명 PNG를 찍는다. 머리 뼈의 화면 위치(0~1)를
## faces.json에 적는다. 배경·빛 효과 합성은 dev/hero_art/compose.py가 한다. 화면이 필요하다.
## 실행: xvfb-run -a godot --path . --resolution 1024x1024 res://tests/hero_art_render.tscn -- --dir=/tmp/hero_art [--ids=mira,valen]

const GameData := preload("res://scripts/game_data.gd")
const Art := preload("res://scripts/art.gd")
const HeroSkills := preload("res://scripts/hero_skills.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")
const UnitModelScript := preload("res://scripts/unit_model.gd")

const PX := 1024
const FOV := 30.0
const CAM_YAW := 28.0  # 모델 정면(+Z)에서 오른쪽으로 돈 각 — 3/4 시점
const CAM_PITCH := 7.0  # 아래에서 올려다본다
const SIDE_ON := ["2H_Melee_Attack_Spin", "Jump_Full_Short", "2H_Melee_Attack_Chop", "2H_Melee_Attack_Slice", "1H_Melee_Attack_Jump_Chop"]  # 몸이 옆으로 돌아 얼굴이 안 보이는 모션

var _dir := "/tmp/hero_art"
var _vp: SubViewport
var _cam: Camera3D
var _rims: Array = []


func _ready() -> void:
	if Net.arg_value("dir") != "":
		_dir = Net.arg_value("dir")
	DirAccess.make_dir_recursive_absolute(_dir)
	var ids: Array = []
	if Net.arg_value("ids") != "":
		ids = Array(Net.arg_value("ids").split(","))
	else:
		for h in GameData.heroes():
			ids.append(str(h.id))
	_build_stage()
	var faces := {}
	for id in ids:
		faces[id] = await _render(id)
	var f := FileAccess.open(_dir.path_join("faces.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(faces, "\t"))
	f.close()
	print("rendered ", ids.size(), " to ", _dir)
	get_tree().quit()


func _build_stage() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(PX, PX)
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_8X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.68)
	env.ambient_light_energy = 0.4
	_vp.world_3d = World3D.new()
	_vp.world_3d.environment = env
	add_child(_vp)
	var key := DirectionalLight3D.new()  # 앞 왼쪽 위 따뜻한 주광
	key.light_color = Color(1.0, 0.92, 0.82)
	key.light_energy = 1.1
	key.rotation_degrees = Vector3(-35, -25, 0)
	_vp.add_child(key)
	for side in [-1.0, 1.0]:  # 뒤 양옆 역광(영웅 색)
		var rim := DirectionalLight3D.new()
		rim.light_energy = 1.6
		rim.rotation_degrees = Vector3(-15, 180.0 + side * 60.0, 0)
		_vp.add_child(rim)
		_rims.append(rim)
	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.near = 0.1
	_cam.far = 50.0
	_vp.add_child(_cam)


func _render(id: String) -> Dictionary:
	var h := GameData.hero(id)
	for rim in _rims:
		rim.light_color = Color(h.color).lightened(0.25)
	var spec := Art.hero_spec(h)
	var m = UnitModelScript.new()
	m.setup(spec)
	_vp.add_child(m)
	await get_tree().process_frame
	var ap := m.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var anim: String = HeroSkills.CAST_ANIM.get(str(h.skill1), spec.anims.attack)
	if not ap.has_animation(anim) or SIDE_ON.has(anim):
		anim = spec.anims.attack
	if SIDE_ON.has(anim):
		anim = "Spellcast_Raise" if ap.has_animation("Spellcast_Raise") else spec.anims.idle
	var frac: float = float(Art.CAST_FRAC.get(anim, Art.HIT_FRAC.get(anim, 0.4)))
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	ap.play(anim)
	ap.seek(ap.get_animation(anim).length * frac, true)
	ap.advance(0.0)
	var top := PortraitsScript.model_top(m)
	var dist := (top * 0.62) / tan(deg_to_rad(FOV / 2.0))
	var aim := Vector3(0, top * 0.5, 0)
	var dir := Vector3(sin(deg_to_rad(CAM_YAW)), -sin(deg_to_rad(CAM_PITCH)), cos(deg_to_rad(CAM_YAW))).normalized()
	_cam.position = aim + dir * dist
	_cam.look_at(aim, Vector3.UP)
	for k in 4:
		await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.save_png(_dir.path_join(id + ".png"))
	var head := PortraitsScript.neck_height(m)
	var sk := m.find_children("*", "Skeleton3D", true, false)
	var hp := Vector3(0, head * 1.1, 0)
	if not sk.is_empty():
		var s3 := sk[0] as Skeleton3D
		var bi := s3.find_bone("head")
		if bi >= 0:
			hp = s3.global_transform * s3.get_bone_global_pose(bi).origin + Vector3(0, top * 0.08, 0)
	var sp := _cam.unproject_position(hp) / float(PX)
	_vp.remove_child(m)
	m.queue_free()
	return {"x": sp.x, "y": sp.y, "anim": anim}

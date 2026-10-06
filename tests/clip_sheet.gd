extends Node3D
## 공격 모션 한눈에(2026-10-06): 행 = 모션, 열 = 모션 진행(0~90%) — 영웅·몬스터 스펙으로 모델을 세워 그 순간 자세를 찍는다.
## xvfb-run -a -s "-screen 0 1600x1200x24" godot --path . --rendering-driver opengl3 --resolution 1500x1100 res://tests/clip_sheet.tscn -- --out=FILE.png (--hero=ID | --monster=KIND) [--clips=a,b,c]
const Art := preload("res://scripts/art.gd")
const GameData := preload("res://scripts/game_data.gd")
const UnitModelScript := preload("res://scripts/unit_model.gd")
const FRACS := [0.0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9]
const GAP := 2.0
const ROW := 3.0


func _ready() -> void:
	var out := "user://sheet.png"
	var spec := {}
	var clips: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--hero="):
			spec = Art.hero_spec(GameData.hero(a.substr(7)))
		elif a.begins_with("--monster="):
			spec = Art.monster_spec(a.substr(10))
		elif a.begins_with("--clips="):
			clips = Array(a.substr(8).split(","))
	if clips.is_empty():
		clips = spec.get("attacks", [spec.anims.attack])
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.82, 0.86, 0.80)
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var rows := clips.size()
	for r in rows:
		var lab := Label3D.new()
		lab.text = clips[r]
		lab.font_size = 40
		lab.modulate = Color.BLACK
		lab.position = Vector3(0.0, -r * ROW + 1.0, 0)
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.width = 260
		lab.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		add_child(lab)
		for c in FRACS.size():
			var m = UnitModelScript.new()
			m.manual = true
			m.setup(spec)
			m.position = Vector3(GAP * 1.6 + c * GAP, -r * ROW, 0)
			m.rotation.y = deg_to_rad(-35)
			add_child(m)
			var ap: AnimationPlayer = m._anim
			ap.play(clips[r], 0.0)
			ap.seek(ap.get_animation(clips[r]).length * FRACS[c], true)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(rows * ROW + 0.5, 11.6)
	var mid := Vector3(GAP * 4.4, -(rows - 1) * ROW * 0.5 + 1.0, 0)
	cam.position = mid + Vector3(0, 2.0, 10.0)
	add_child(cam)
	cam.look_at(mid)
	for i in 4:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit(0)

extends Node
## 드래곤 공격 모션 시트(개발용, 화면 필요, 2026-10-07): 할퀴기(오른발)·불 뿜기·날개 바람을 진행 0·0.3·0.45·0.55·0.65·0.9로 옆·앞 비스듬히 찍는다.
## 실행: xvfb-run -a godot --path . --resolution 1200x800 res://tests/dragon_moves.tscn -- --out=/tmp/dragon_moves.png

const DragonModelScript := preload("res://scripts/dragon_model.gd")
const KS := [0.0, 0.3, 0.45, 0.55, 0.65, 0.9]
const ACTS := ["claw", "breath", "gust"]


func _ready() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(300, 260)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var model = DragonModelScript.new()
	model.size = 1.0
	vp.add_child(model)
	model.set_process(false)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	vp.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.85, 0.88, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.72, 0.78)
	vp.add_child(env)
	var floor := MeshInstance3D.new()
	floor.mesh = PlaneMesh.new()
	floor.mesh.size = Vector2(4, 4)
	vp.add_child(floor)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.5
	vp.add_child(cam)
	cam.position = Vector3(float(Net.arg_value("cx")) if Net.arg_value("cx") != "" else 3.0, 1.4, float(Net.arg_value("cz")) if Net.arg_value("cz") != "" else 0.9)
	cam.look_at(Vector3(0, 0.45, 0.1))
	await get_tree().process_frame
	var sheet := Image.create(300 * KS.size(), 260 * ACTS.size(), false, Image.FORMAT_RGB8)
	for r in ACTS.size():
		for c in KS.size():
			model.claw_side = 1.0
			model.pose(1.0, ACTS[r], KS[c])
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(img, Rect2i(0, 0, 300, 260), Vector2i(c * 300, r * 260))
	var out := Net.arg_value("out") if Net.arg_value("out") != "" else "/tmp/dragon_moves.png"
	sheet.save_png(out)
	print("saved ", out)
	get_tree().quit()

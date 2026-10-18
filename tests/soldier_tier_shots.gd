extends Node3D
## 병사 단계별 외형(개발용, 2026-10-18): 병종 하나(--type=, 기본 infantry)의 1~5단계를 같은 조명에 나란히 세워 찍는다.
## 화면이 필요하다. 실행: xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1500x520 res://tests/soldier_tier_shots.tscn -- --type=cavalry --out=/tmp/tiers.png

const SoldierBody := preload("res://scripts/soldier_body.gd")
const GAP := 2.6


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.86, 0.82, 0.72)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment.ambient_light_energy = 0.7
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-35), 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var type := "infantry"
	var out := "/tmp/tiers.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--type="):
			type = a.substr(7)
	for t in range(1, 6):
		var p := Node3D.new()
		p.position = Vector3((t - 3) * GAP, 0, 0)
		p.rotation.y = deg_to_rad(35)
		add_child(p)
		SoldierBody.build(p, type, t)
	var cam := Camera3D.new()
	cam.fov = 32
	cam.position = Vector3(0, 4.2, 10.5) if not OS.get_cmdline_user_args().has("--high") else Vector3(0, 9.0, 8.5)
	add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0))
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("SHOT ", out)
	get_tree().quit()

extends Node3D
## UR 영웅 외형(개발용, 2026-10-29): UR 6명(표에 없으면 아래 UR 표 값으로)을 같은 조명에 나란히 세워 찍는다. --ssr이면 SSR 6명(비교용).
## 화면이 필요하다. 실행: xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1500x600 res://tests/ur_lineup_shots.tscn -- --out=/tmp/ur.png

const Art := preload("res://scripts/art.gd")
const GameData := preload("res://scripts/game_data.gd")
const UnitModelScript := preload("res://scripts/unit_model.gd")
const GAP := 2.0
const UR := [
	{"id": "hyeonmu", "model": "Knight", "gear": "1H_Sword|Badge_Shield", "role": "melee"},
	{"id": "baekho", "model": "Barbarian", "gear": "2H_Axe", "role": "melee"},
	{"id": "yeonhwa", "model": "Rogue", "gear": "Knife|Knife_Offhand", "role": "melee"},
	{"id": "cheongryong", "model": "Rogue_Hooded", "gear": "2H_Crossbow", "role": "ranged"},
	{"id": "chronos", "model": "Mage", "gear": "2H_Staff", "role": "ranged"},
	{"id": "jujak", "model": "Mage", "gear": "Spellbook_open", "role": "ranged"},
]
const SSR := ["arteon", "dante", "kyle", "raven", "valen", "lumina"]


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
	var out := "/tmp/ur.png"
	var ssr := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--ssr":
			ssr = true
	var heroes: Array = []
	for i in 6:
		var h: Dictionary = GameData.hero(SSR[i]) if ssr else GameData.hero(UR[i].id)
		heroes.append(h if not h.is_empty() else UR[i])
	for i in heroes.size():
		var m = UnitModelScript.new()
		m.setup(Art.hero_spec(heroes[i]))
		m.position = Vector3((i - 2.5) * GAP, 0, 0)
		m.rotation.y = deg_to_rad(20)
		add_child(m)
	var cam := Camera3D.new()
	cam.fov = 30
	cam.position = Vector3(0, 2.4, 9.6)
	add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0))
	for i in 40:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("SHOT ", out)
	get_tree().quit()

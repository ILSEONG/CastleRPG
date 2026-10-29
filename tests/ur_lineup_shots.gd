extends Node3D
## UR 영웅 외형(개발용, 2026-10-29): UR 6명(표에 없으면 아래 UR 표 값으로)을 같은 조명에 나란히 세워 찍는다. --ssr이면 SSR 6명(비교용).
## 화면이 필요하다. 실행: xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1500x600 res://tests/ur_lineup_shots.tscn -- --out=/tmp/ur.png
## --ids=a,b(그 영웅만) --close(가까이, 정면) --style=lowpoly|toon|real(그림 방식) --game(본 게임 조명) --yaw=도(몸 돌림)
## --attack=비율(공격 모션의 그 순간에 멈춘다) --ur=band_soft=1,shade=0.2(UR 마감 값 시험)

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
	var ids: Array = []
	var close := false
	var yaw := INF
	var attack := -1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--ssr":
			ssr = true
		elif a.begins_with("--ids="):
			ids = Array(a.substr(6).split(",", false))
		elif a == "--close":
			close = true
		elif a.begins_with("--yaw="):
			yaw = float(a.substr(6))
		elif a.begins_with("--attack="):
			attack = float(a.substr(9))
		elif a.begins_with("--ur="):  # UR 마감 값 시험: 이름=값,이름=값
			for kv in a.substr(5).split(",", false):
				Art.UR_LOOK[kv.get_slice("=", 0)] = float(kv.get_slice("=", 1))
		elif a.begins_with("--style="):
			Art.unit_style = a.substr(8)
		elif a == "--game":
			env.environment.ambient_light_color = Color(0.78, 0.80, 0.86)
			env.environment.ambient_light_energy = 0.9
			sun.light_color = Color(1.0, 0.96, 0.88)
	var heroes: Array = []
	for i in 6:
		if not ids.is_empty() and not (UR[i].id in ids):
			continue
		var h: Dictionary = GameData.hero(SSR[i]) if ssr else GameData.hero(UR[i].id)
		heroes.append(h if not h.is_empty() else UR[i])
	var n := heroes.size()
	var models: Array = []
	for i in n:
		var m = UnitModelScript.new()
		m.setup(Art.hero_spec(heroes[i]))
		m.position = Vector3((i - (n - 1) / 2.0) * GAP, 0, 0)
		m.rotation.y = deg_to_rad(yaw if yaw != INF else (8.0 if close else 20.0))
		add_child(m)
		models.append(m)
	var cam := Camera3D.new()
	cam.fov = 30
	cam.position = Vector3(0, 1.3, 2.4 + 2.2 * n) if close else Vector3(0, 2.4, 9.6)
	add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0))
	for i in 40:
		await get_tree().process_frame
	if attack >= 0.0:
		for m in models:
			var anim_name: String = m._spec.anims.attack
			m._anim.play(anim_name, 0.0)
			m._anim.seek(m._anim.get_animation(anim_name).length * attack, true)
			m._anim.pause()
		for i in 5:
			await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("SHOT ", out)
	get_tree().quit()

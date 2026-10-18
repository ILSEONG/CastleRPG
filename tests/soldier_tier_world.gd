extends Node
## 성 안 병사 대열 스냅샷(개발용, 2026-10-18 병사 단계별 외형): 보병·궁병·기병 1~5단계를 고루 배치하고 성을 찍는다(기본 줌 · 가까이).
## 화면이 필요하다. 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/soldier_tier_world.tscn -- --out=/tmp/tier_world
## 저장 파일은 건드리지 않는다(오프라인, save_path = "").

var _out := "/tmp/tier_world"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	if OS.get_cmdline_user_args().has("--kaykit"):  # 비교용: Meshy 몸을 끈 예전 생김새
		preload("res://scripts/art.gd").meshy_bodies = false
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	var army := {}
	for type in ["infantry", "archer", "cavalry"]:
		for t in range(1, 6):
			army["%s:%d" % [type, t]] = 2 if type != "cavalry" else 1
	Economy.soldiers = army.duplicate()
	Economy.soldier_deployed = army.duplicate()
	var main = preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(90)
	GameState.start_stage()
	await _frames(20)
	print("[tiers] soldiers in world: ", get_tree().get_nodes_in_group("soldiers").size())
	await _snap("castle")
	var rig: Node = null
	for c in main.get_children():
		if c.get_script() != null and c.get_script().resource_path == "res://scripts/camera_rig.gd":
			rig = c
	var c := Vector3.ZERO
	var list := get_tree().get_nodes_in_group("soldiers")
	for n in list:
		c += n.global_position
	rig.pan_to(c / maxf(1.0, list.size()), 0.05)
	rig.zoom_by(0.01)  # 가장 가까이(CAMERA_SIZE_MIN)
	await _frames(10)
	await _snap("near")
	get_tree().quit()


func _snap(name_s: String) -> void:
	await _frames(8)
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, name_s])
	print("saved ", name_s)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

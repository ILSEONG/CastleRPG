extends Node
## 성문 스냅샷(개발용): 성채 레벨 1·9·22(성 내부 20·28·36칸, 면마다 성문 1·2·3개)에서 성 전체와 스테이지 교전을 찍는다.
## 화면이 필요하다. 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/gate_shots.tscn -- --out=/tmp/gates

var _out := "/tmp/gates"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	Economy.save_path = ""
	Fever.save_path = ""
	for lv in [1, 9, 22]:
		Economy.reset(Time.get_unix_time_from_system())
		Economy.levels["keep"] = lv
		var main = preload("res://scenes/main.tscn").instantiate()
		add_child(main)
		await _frames(60)
		var rig = _rig(main)
		rig.zoom_by((main.castle.half * 2.0 + 12.0) * 1.1 / rig.camera.size)
		await _snap("lv%d_castle" % lv)
		GameState.start_stage()
		Engine.time_scale = 3.0
		await get_tree().create_timer(14.0, true, false, true).timeout
		Engine.time_scale = 1.0
		await _snap("lv%d_fight" % lv)
		print("[gates] lv %d half %.0f gates/side %d gate_hp %s" % [lv, main.castle.half, Formation.gates_per_side(main.castle.half), GameState.gate_hp])
		GameState.stop_stage()
		main.queue_free()
		await _frames(10)
	get_tree().quit()


const Balance := preload("res://scripts/balance.gd")
const Formation := preload("res://scripts/formation.gd")


func _rig(main):
	for c in main.get_children():
		if c.get_script() != null and c.get_script().resource_path == "res://scripts/camera_rig.gd":
			return c
	return main.rig


func _snap(name_s: String) -> void:
	await _frames(8)
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, name_s])
	print("saved ", name_s)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

extends Node
## 데스나이트 영상(개정 26): 장비 던전 1단계를 실제로 돌리며 보스 가까이(카메라 크기 SIZE)를 프레임마다 찍는다.
## xvfb-run -a -s "-screen 0 720x1280x24" godot --path . --fixed-fps 30 --rendering-driver opengl3 --resolution 540x960 res://tests/dk_clip.tscn -- --out=DIR [--sec=20] [--size=14] [--from=0]

const GameData := preload("res://scripts/game_data.gd")

var _main


func _ready() -> void:
	var out := ""
	var sec := 20.0
	var size := 14.0
	var from := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--sec="):
			sec = float(a.substr(6))
		elif a.begins_with("--size="):
			size = float(a.substr(7))
		elif a.begins_with("--from="):
			from = float(a.substr(7))
	Economy.save_path = ""
	Fever.save_path = ""
	Fever.reset()
	GameData._config.fx_shake = "1"
	Economy.reset(Time.get_unix_time_from_system())
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	for i in 120:
		await get_tree().process_frame
	Economy.start_dungeon("equip", 1, Economy.default_party("equip"))
	for i in 10:
		await get_tree().process_frame
	var d = _main._dungeon
	var dk = null
	DirAccess.make_dir_recursive_absolute(out)
	var n := 0
	for f in int((from + sec) * 30):
		if dk == null or not is_instance_valid(dk):
			for m in get_tree().get_nodes_in_group("monsters"):
				dk = m
		var cam := get_viewport().get_camera_3d()
		if cam != null and dk != null and is_instance_valid(dk):
			cam.size = size
			var rig = cam.get_parent()
			var vp := get_viewport().get_visible_rect().size
			var at := Vector2(vp.x * 0.5, vp.y * 0.55)
			var o := cam.project_ray_origin(at)
			var dr := cam.project_ray_normal(at)
			var hit := o + dr * (-o.y / dr.y)
			var aim: Vector3 = dk.global_position
			rig.position += Vector3(aim.x - hit.x, 0, aim.z - hit.z) * 0.15
		await RenderingServer.frame_post_draw
		if f >= int(from * 30):
			get_viewport().get_texture().get_image().save_jpg(out.path_join("%04d.jpg" % n), 0.88)
			n += 1
	print("DK frames=%d" % n)
	get_tree().quit(0)

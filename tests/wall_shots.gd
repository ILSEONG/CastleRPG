extends Node
## 성벽 위 길 스냅샷(개발용, 2026-10-23 사용자 "성벽 위 영웅이 위치하는 부분 두께를 좀 두껍게, 터치하기가 불편해"):
## 스테이지를 시작해 영웅·궁병이 성벽에 선 모습을 기본 줌·가까이(남쪽 성벽)에서 찍고, 면마다 성벽 위 길의 화면 폭(px)과
## 성벽 탭 상자에 걸리는 화면 높이(px, 성벽 가운데 세로줄)를 찍는다.
## 화면이 필요하다. 실행: xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 720x1280 res://tests/wall_shots.tscn -- --out=/tmp/walls [--keep=30]
## 저장 파일은 건드리지 않는다(오프라인, save_path = "").

const Balance := preload("res://scripts/balance.gd")
const Formation := preload("res://scripts/formation.gd")

var _out := "/tmp/walls"


func _ready() -> void:
	var keep := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		if a.begins_with("--keep="):  # 성채 레벨(성 모습 단계·성 크기)
			keep = int(a.substr(7))
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	Economy.levels["keep"] = keep
	Economy.soldiers = {"infantry:1": 6, "archer:3": 10}
	Economy.soldier_deployed = Economy.soldiers.duplicate()
	var main = preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(60)
	for i in 3000:  # 첫 로딩 화면이 걷힐 때까지
		if preload("res://scripts/preloader.gd").done:
			break
		await _frames(1)
	await _frames(20)
	GameState.start_stage()
	await get_tree().create_timer(12.0).timeout
	var cam := get_viewport().get_camera_3d()
	var half: float = main.castle.half
	var line := []
	for side in 4:
		var dir: Vector3 = Formation.SIDE_DIR[side]
		var at := Formation.perp(side) * 6.0  # 성문 옆(영웅 자리 ±4·±8 사이)
		var a := cam.unproject_position(dir * half + at + Vector3(0, Balance.WALL_H, 0))
		var b := cam.unproject_position(dir * (half + Balance.WALL_T) + at + Vector3(0, Balance.WALL_H, 0))
		line.append("%s %.0f px" % [["N", "E", "S", "W"][side], a.distance_to(b)])
	print("[walls] WALL_T %.1f m, wall-top width on screen at %.0f m zoom: %s" % [Balance.WALL_T, cam.size, ", ".join(line)])
	var heroes := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.global_position.y > Balance.WALL_H / 2.0)
	print("[walls] heroes on walls: %d, archers on walls: %d" % [heroes.size(), get_tree().get_nodes_in_group("soldiers").filter(func(s): return s.global_position.y > Balance.WALL_H / 2.0).size()])
	await _snap("default")
	var rig: Node = null
	for c in main.get_children():
		if c.get_script() != null and c.get_script().resource_path == "res://scripts/camera_rig.gd":
			rig = c
	if rig != null and not heroes.is_empty():  # 성벽 위 영웅 가까이(영웅 둘레 궁병 포함)
		rig.pan_to(heroes[0].global_position, 0.05)
		rig.zoom_by(20.0 / cam.size)
		await get_tree().create_timer(0.3).timeout
		await _snap("hero_near")
	get_tree().quit()


func _snap(name_s: String) -> void:
	await _frames(6)
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, name_s])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

extends Node
## 헤드리스 성능 측정(통과/실패 없음): 실제 main 씬에 몬스터 120(상한, 죽지 않게) + 병사 64를 놓고 스테이지를 돌려 찍는다 —
## 프레임당 벽시계 시간(스크립트·애니메이션·겹침 해소 — 헤드리스라 GPU 그리기는 빠진다), 겹침 해소 시간(crowd.last_usec),
## 유닛 메시 수(화면 그리기)·그중 그림자를 드리우는 것(그림자 패스에서 한 번 더 그린다)·이번 프레임 애니메이션을 돌린 유닛 수.
## 실행: ./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/perf_check.tscn [-- --monsters=N]

const GameData := preload("res://scripts/game_data.gd")
const MonsterScript := preload("res://scripts/monster.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")
const CrowdScript := preload("res://scripts/crowd.gd")

const MONSTERS := 120
const FRAMES := 600

var _main


func _ready() -> void:
	Engine.max_fps = 0  # 프로젝트 상한(60)을 풀어 프레임 시간을 그대로 잰다
	Economy.save_path = ""
	Fever.save_path = ""
	Fever.reset()
	GameData._config.fx_shake = "0"
	Economy.reset(Time.get_unix_time_from_system())
	Economy.levels["houses"] = 30
	Economy.soldiers = {"infantry:1": 32, "archer:1": 16, "cavalry:1": 16}
	Economy.set_soldier_deploy(Economy.soldiers.duplicate())
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(5)
	var crowd
	for c in _main.get_children():
		if c.get_script() == SpawnerScript:
			c.set_process(false)
		elif c.get_script() == CrowdScript:
			crowd = c
	GameState.start_stage()
	await _frames(30)
	var count := MONSTERS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--monsters="):
			count = int(a.trim_prefix("--monsters="))
	var half: float = _main.castle.half
	var dirs := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]
	for i in count:
		var m = MonsterScript.new()
		m.setup("grunt", i % 4, 1, _main.castle)
		m.hp *= 1000.0  # 측정 동안 죽지 않게
		m.hp_max = m.hp
		_main.add_child(m)
		m.global_position = (dirs[i % 4] as Vector3).rotated(Vector3.UP, randf_range(-0.6, 0.6)) * (half + 6.0 + randf() * 20.0)
	await _frames(60)
	var crowd_us := 0
	var t0 := Time.get_ticks_usec()
	for f in FRAMES:
		await get_tree().process_frame
		crowd_us += crowd.last_usec
	var wall := (Time.get_ticks_usec() - t0) / 1000.0 / FRAMES
	var units := get_tree().get_nodes_in_group("crowd")
	var meshes := 0
	var casters := 0
	for u in units:
		for mi in u.find_children("*", "MeshInstance3D", true, false):
			if mi.is_visible_in_tree():
				meshes += 1
				casters += 1 if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else 0
	print("PERF units: heroes %d, soldiers %d, monsters %d" % [get_tree().get_nodes_in_group("heroes").size(),
		get_tree().get_nodes_in_group("soldiers").size(), get_tree().get_nodes_in_group("monsters").size()])
	print("PERF frame %.2f ms (wall, no GPU), crowd %.2f ms, over %d frames" % [wall, crowd_us / 1000.0 / FRAMES, FRAMES])
	print("PERF unit meshes %d, shadow casters %d (draws ~ meshes + casters)" % [meshes, casters])
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

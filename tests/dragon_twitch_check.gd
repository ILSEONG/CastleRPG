extends Node
## 길드 보스 드래곤 움찔거림 확인(개발용, 2026-10-07): 보스 탭 미리보기 드래곤이 3초 동안 몇 번 새로 만들어지는지(대기 동작이 처음으로 튐),
## 전투 10초 동안 드래곤 모델의 한 프레임 최대 회전 변화·크기 튐 횟수, 공격 중 머리와 노린 영웅 사이 각(AIM)을 찍는다. 저장 파일은 건드리지 않는다.
## 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/dragon_twitch_check.tscn

var _main


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Guild.load_save()
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(60)
	Guild.unlocked = true
	Guild.join(Guild.recommendations()[0])
	var tabs = _find("res://scripts/side_menu.gd")
	tabs.pick("guild")
	var panel = tabs.windows.guild
	panel.tab = "boss"
	panel._rebuild()
	await _frames(10)
	var seen := {}
	var jumps := 0
	var last_t := -1.0
	var t_end := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < t_end:
		Economy.changed.emit()  # 방치 전투 골드처럼 자주 오는 변화
		await get_tree().process_frame
		for m in panel.find_children("*", "Node3D", true, false):
			if m.get_script() != null and m.get_script().resource_path == "res://scripts/dragon_model.gd":
				seen[m.get_instance_id()] = true
				if m._t < last_t:
					jumps += 1
				last_t = m._t
	print("PREVIEW dragons_created=%d idle_restarts=%d" % [seen.size(), jumps])
	panel._start_fight()
	var scene = null
	for i in 120:
		await get_tree().process_frame
		scene = _main._dungeon
		if scene != null:
			break
	if scene == null:
		print("FAIL no boss scene")
		get_tree().quit(1)
		return
	var model = scene.dragon._model
	var prev_yaw: float = model.rotation.y
	var prev_scale: Vector3 = model.scale
	var max_turn := 0.0
	var snaps := 0
	var pops := 0
	var aim := []  # 공격 모션 중 머리(모델 앞 +Z) 방향과 노리는 영웅 방향 사이 각(도) — 2026-10-07 "머리랑 공격방향이 안 맞아"
	t_end = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		var h = scene.dragon._swing_hero
		if model.is_busy() and is_instance_valid(h):
			var fz: Vector3 = model.global_basis.z
			var to: Vector3 = h.global_position - scene.dragon.global_position
			aim.append(absf(rad_to_deg(Vector2(fz.x, fz.z).angle_to(Vector2(to.x, to.z)))))
		var d := absf(angle_difference(prev_yaw, model.rotation.y))
		max_turn = maxf(max_turn, d)
		if d > 0.25:
			snaps += 1
		if not model.scale.is_equal_approx(prev_scale):
			pops += 1
		prev_yaw = model.rotation.y
		prev_scale = model.scale
	print("FIGHT max_turn_per_frame=%.2f rad snaps=%d scale_changes=%d attacks=%d" % [max_turn, snaps, pops, scene.dragon.attacks])
	aim.sort()
	print("AIM frames=%d median_deg=%.0f p90_deg=%.0f" % [aim.size(), aim[aim.size() / 2] if aim.size() > 0 else -1.0, aim[int(aim.size() * 0.9)] if aim.size() > 0 else -1.0])
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _find(path: String) -> Node:
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
	return null

extends Node
## 건물 말풍선 자리 점검(개발용, 2026-10-18 사용자 "말풍선 위치 안바뀌게해"): 자원 건물 전부 말풍선 + 짓는 중인 자원 건물 하나 +
## 훈련 끝난 병영. 카메라를 옮기고(이동·회전·확대·축소) 말풍선 꼬리 끝이 제 건물 기준점에서 얼마나 움직이는지 찍고 스냅샷을 남긴다.
## 화면이 필요하다. 실행: xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 720x1280 res://tests/bubble_shots.tscn -- --out=/tmp/bubbles
## 저장 파일은 건드리지 않는다(오프라인, save_path = "").

const GameData := preload("res://scripts/game_data.gd")
const BadgesScript := preload("res://scripts/badges.gd")
const WorldTagsScript := preload("res://scripts/world_tags.gd")

var _out := "/tmp/bubbles"
var _badges
var _tags
var _camera: Camera3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	var now := Time.get_unix_time_from_system()
	Economy.reset(now)
	Tutorial.state = "skipped"
	Economy.res = {"wood": 900000, "stone": 900000, "food": 900000}
	Economy.gold_tenths = 9000000
	Economy.levels["keep"] = 10  # 자원 건물을 올릴 수 있게(성채 상한)
	var main = preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(60)
	for i in 3000:  # 첫 로딩 화면이 걷힐 때까지
		if preload("res://scripts/preloader.gd").done:
			break
		await _frames(1)
	await _frames(30)
	_badges = _find(main, BadgesScript)
	_tags = _find(main, WorldTagsScript)
	_camera = get_viewport().get_camera_3d()
	now = Economy.time_now()
	for id in _badges._anchors:
		if Economy.yield_of(id) != "":
			Economy.last_collect[id] = now - 3600.0
	for id in _badges.badge_ids(now):  # 짓는 중 + 말풍선(짓기 시작이 수집하므로 다시 쌓인 것으로)
		var why: String = Economy.upgrade_block(id, now)
		if why == "" and Economy.upgrade(id, now):
			Economy.last_collect[id] = now - 3600.0
			print("[bubbles] building ", id)
			break
		print("[bubbles] can't upgrade %s: %s" % [id, why])
	Economy.start_training("barracks", 1)
	Economy.finish_training_now("barracks")
	Economy.changed.emit()
	await _frames(4)
	var rig: Node = _find(main, preload("res://scripts/camera_rig.gd"))
	var p0: Vector3 = rig.position
	var size0 := _camera.size
	var seen := {}  # id → [min offset, max offset]
	var shots := [["default", Vector3.ZERO, 0.0, size0], ["pan_left", Vector3(-14, 0, 0), 0.0, size0], ["pan_right", Vector3(14, 0, 0), 0.0, size0],
		["pan_up", Vector3(0, 0, -10), 0.0, size0], ["yaw", Vector3.ZERO, 35.0, size0], ["zoom_in", Vector3.ZERO, 0.0, 40.0], ["zoom_out", Vector3.ZERO, 0.0, 110.0]]
	for s in shots:
		rig.position = p0 + s[1]
		rig.rotation_degrees.y = s[2]
		rig.zoom_by(s[3] / _camera.size)
		await _frames(6)
		_tags.layout(true)
		var line := []
		for id in _badges.bubble_ids(Economy.time_now()):
			var tip = _tip(id)
			if tip == null:
				continue
			var off: Vector2 = tip - _camera.unproject_position(_anchor_of(id))
			line.append("%s %+d,%+d" % [id, roundi(off.x), roundi(off.y)])
			if s[0] != "zoom_in" and s[0] != "yaw":  # 이동·축소 — 같은 줌·같은 방향이면 같은 자리여야 한다
				var r: Array = seen.get(id, [off, off])
				seen[id] = [Vector2(minf(r[0].x, off.x), minf(r[0].y, off.y)), Vector2(maxf(r[1].x, off.x), maxf(r[1].y, off.y))]
		print("[bubbles] %s: %s" % [s[0], ", ".join(line)])
		await _snap(s[0])
	var worst := 0.0
	for id in seen:
		worst = maxf(worst, (seen[id][1] - seen[id][0]).length())
	print("[bubbles] largest bubble shift over pans + zoom-out: %.1f px (%s)" % [worst, seen])
	get_tree().quit()


## 말풍선 꼬리 끝(흔들림 빼고). 새 코드는 badges.bubble_tip, 예전 코드는 그때 _draw 계산을 따라 한다.
func _tip(id: String):
	if _badges.has_method("bubble_tip"):
		return _badges.bubble_tip(id)
	var at = _tags.top(id)
	if at == null:
		return null
	return at + Vector2(0, -2.0 - (_badges.BUILD_LIFT_PX if Economy.is_building(id) else 0.0))


func _anchor_of(id: String) -> Vector3:
	for t in _tags.tags:
		if t.id == id:
			return t.anchor
	return Vector3.ZERO


func _find(root: Node, script: Script) -> Node:
	for n in root.find_children("*", "", true, false):
		if n.get_script() == script:
			return n
	return null


func _snap(name_s: String) -> void:
	await _frames(4)
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, name_s])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

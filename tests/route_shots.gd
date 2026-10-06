extends Node
## 이동 명령 경로 표시 확인(개발용): 스테이지 중 영웅 둘에게 바닥 이동 명령(하나는 성문을 거쳐 성 밖으로)을 주고 걷는 도중을 찍은 뒤,
## 경로 띠가 줄어들고 도착하면 표시가 사라지는지 본다. 화면이 필요하다.
## 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/route_shots.tscn -- --out=/tmp/route.png

const Formation := preload("res://scripts/formation.gd")

var _main
var _shots: Array = []
var _fail := 0


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	for h in preload("res://scripts/game_data.gd").heroes().slice(0, 5):
		Economy.heroes[h.id] = 1
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(120)
	GameState.start_stage()
	await _frames(240)
	var picker = _main._picker
	var hs: Array = get_tree().get_nodes_in_group("heroes")
	var half: float = hs[0].castle.half
	var a = hs[0]
	var b = hs[1]
	var da: Vector3 = picker._ground_point(Vector2(250, 1000))  # 성 밖 아래쪽(성문을 거친다)
	var db: Vector3 = picker._ground_point(Vector2(470, 640))  # 성 안 마당
	for pair in [[a, da], [b, db]]:
		picker._select(pair[0])
		pair[0].move_to_point(pair[1])
		picker._show_route(pair[0], pair[1])
	await _frames(2)
	var ra = picker._routes[a]
	var n0: int = ra.points().size()
	_check(n0 >= 2, "route shows %d points" % n0)
	_check(get_tree().get_nodes_in_group("heroes").size() == hs.size(), "heroes intact")
	await _frames(40)
	_shots.append(get_viewport().get_texture().get_image())
	var len0 := _len(ra.points())
	await _frames(40)
	_check(is_instance_valid(ra) and _len(ra.points()) < len0, "route shrinks as hero walks")
	_shots.append(get_viewport().get_texture().get_image())
	# 새 명령은 이전 표시를 바꾼다(영웅당 하나)
	var db2 := Vector3(half - 3.0, 0.0, -(half - 3.0))
	b.move_to_point(db2)
	picker._show_route(b, db2)
	await _frames(2)
	_check(get_tree().get_nodes_in_group("heroes").size() > 0 and _count_routes() == 2, "one route per hero (%d)" % _count_routes())
	for i in 1200:
		await get_tree().process_frame
		if not is_instance_valid(ra) and a._path.is_empty():
			break
	_check(not is_instance_valid(ra), "route removed on arrival")
	_shots.append(get_viewport().get_texture().get_image())
	# 영웅을 고른 채 몬스터를 누르면 선택이 풀린다(이동 명령 없음)
	var mon = null
	for m in get_tree().get_nodes_in_group("monsters"):
		var mp: Vector2 = picker.camera.unproject_position(m.global_position + Vector3(0, 0.8, 0))
		if m.is_alive() and get_viewport().get_visible_rect().grow(-80).has_point(mp) and picker._hero_at(mp, picker.HERO_TAP_PX) == null:
			mon = m
			break
	if mon != null:
		picker._select(a)
		var keep: Vector3 = a.free_pos
		picker._pending = picker.camera.unproject_position(mon.global_position + Vector3(0, 0.8, 0))
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(picker.selected == null and a.free_pos == keep, "monster tap clears the hero selection without a move")
	else:
		_check(false, "found an on-screen monster for the monster tap")
	var out := "/tmp/route.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	var w := 540
	var h := 960
	var sheet := Image.create(w * _shots.size(), h, false, Image.FORMAT_RGB8)
	for i in _shots.size():
		var img: Image = _shots[i]
		img.convert(Image.FORMAT_RGB8)
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	sheet.save_png(out)
	print("saved ", out, " failures=", _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _count_routes() -> int:
	var n := 0
	for c in _main.get_children():
		if c.get_script() == preload("res://scripts/route_marker.gd"):
			n += 1
	return n


func _len(pts: Array) -> float:
	var s := 0.0
	for i in pts.size() - 1:
		s += Vector2(pts[i].x - pts[i + 1].x, pts[i].z - pts[i + 1].z).length()
	return s


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

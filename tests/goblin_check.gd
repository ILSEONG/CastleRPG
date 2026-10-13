extends Node
## 황금 고블린 체크 + 화면(개발용, 오프라인): 성 화면에서 감독이 고블린을 내보내고(나오는 간격 5~10분),
## 1) 성 밖 고리를 돌아다니고 성벽 안으로는 안 들어간다, 2) 속도 = 나온 영웅 평균 × 0.85, 3) 맞으면 친 영웅 반대쪽으로 달아난다,
## 4) 잡으면 골드(방치 15분 몫)가 오른다, 5) 시간이 다 되면 바깥으로 달아나 escaped. 화면이 필요하다:
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/goblin_check.tscn -- --out=/tmp/goblin
## --movie면 체크 대신 자막을 단 시연(영상용 — --write-movie와 함께). 마지막 줄이 GOBLIN CHECK PASSED(실패면 종료 코드 1).

const GoldGoblin := preload("res://scripts/gold_goblin.gd")
const Director := preload("res://scripts/goblin_director.gd")
const Formation := preload("res://scripts/formation.gd")
const Balance := preload("res://scripts/balance.gd")
const DamageNumbers := preload("res://scripts/damage_numbers.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

var _out := "/tmp/goblin"
var _fails := 0
var _main
var _dir
var _rig
var _caption: Label


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	Economy.save_path = ""
	Fever.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(60)
	for c in _main.get_children():
		var p: String = c.get_script().resource_path if c.get_script() != null else ""
		if p == "res://scripts/goblin_director.gd":
			_dir = c
		elif p == "res://scripts/camera_rig.gd":
			_rig = c
	_check(_dir != null, "goblin director is in the castle world", "")
	_check(Director.next_at - Time.get_ticks_msec() / 1000.0 >= Director.INTERVAL.x - 60.0 or OS.get_cmdline_user_args().has("--goblin-now"),
		"first goblin waits 5–10 min", "%.0f s" % (Director.next_at - Time.get_ticks_msec() / 1000.0))
	if _fails > 0:
		return _finish()
	if OS.get_cmdline_user_args().has("--movie"):
		await _movie()
		get_tree().quit()
		return
	var g = _dir.spawn()
	if _rig != null:
		_rig.zoom_by(0.45)
	_check(Director.next_at - Time.get_ticks_msec() / 1000.0 >= Director.INTERVAL.x - 1.0, "next goblin 5–10 min after this one", "")
	await _frames(5)
	_check(g.is_in_group("monsters") and g.is_alive(), "goblin is a target for heroes", "")
	var heroes := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.is_alive())
	var avg := 0.0
	for h in heroes:
		avg += float(h._speed)
	avg /= maxf(1.0, heroes.size())
	_check(heroes.size() > 0 and absf(g.speed() - avg * 0.85) < 0.01, "speed = hero average × 0.85", "%.2f vs %.2f (%d heroes)" % [g.speed(), avg * 0.85, heroes.size()])
	# 영웅이 건드리지 않게 무적처럼 HP를 크게 두고 돌아다니는지 본다
	g.hp = 1e12
	g.hp_max = 1e12
	var inside := false
	var path := []
	_follow(g)
	for i in 240:
		await get_tree().process_frame
		if Formation.is_inside(_main.castle.half, g.global_position):
			inside = true
		if i % 30 == 0:
			path.append(g.global_position)
	_check(not inside, "never walks inside the walls", "")
	_check(path[0].distance_to(path[-1]) > 3.0, "wanders around", str(path))
	await _snap("1_wander")
	# 맞으면 반대쪽으로: 가장 가까운 영웅을 고블린 바로 옆에 두고 친다
	var h = heroes[0]
	g._leaving = false
	g._life = 999.0
	g.global_position = _ring(0, 8.0)
	h.global_position = g.global_position + Vector3(2.0, 0, 0)
	h._target = g
	await get_tree().process_frame
	var p0: Vector3 = g.global_position
	g.take_damage(10.0, DamageNumbers.Kind.HIT)
	_check(g._flee_t > 0.0 and g._flee_dir.dot(Vector3(-1, 0, 0)) > 0.95, "hit → flees away from the hitter", str(g._flee_dir))
	for i in 20:
		await get_tree().process_frame
	_check((g.global_position - p0).dot(Vector3(-1, 0, 0)) > 0.3, "moved away from the hitter", "%s → %s" % [p0, g.global_position])
	await _snap("2_flee")
	# 잡기: 골드가 방치 15분 몫만큼 오른다(오프라인)
	var gold := Economy.gold_tenths
	var want := Economy.goblin_gold_tenths(GameState.stage)
	g.hp = 1.0
	g.take_damage(5.0, DamageNumbers.Kind.HIT)
	await _frames(3)
	await _snap("3_caught")
	_check(Economy.gold_tenths - gold >= want and want > 0, "caught → idle gold 15 min", "%d (want %d)" % [Economy.gold_tenths - gold, want])
	_check(_dir.goblin == null, "director cleared", "")
	# 놓치기
	var g2 = _dir.spawn()
	var gone := [false]
	g2.escaped.connect(func(): gone[0] = true)
	g2.hp = 1e12
	g2._life = 0.0
	Engine.time_scale = 4.0
	await get_tree().create_timer(30.0, true, false, true).timeout
	Engine.time_scale = 1.0
	_check(gone[0] and not is_instance_valid(g2), "time up → runs off and escapes", "")
	_finish()


## 시연(영상): 고블린 등장 → 돌아다님 → 영웅에게 맞아 도망 → 잡힘. 자막을 위에 단다.
func _movie() -> void:
	_caption = Label.new()
	_caption.add_theme_font_override("font", FONT)
	_caption.add_theme_font_size_override("font_size", 34)
	_caption.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.05))
	_caption.add_theme_constant_override("outline_size", 10)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.position = Vector2(20, 180)
	_caption.size = Vector2(680, 120)
	var layer := CanvasLayer.new()
	layer.layer = 10
	layer.add_child(_caption)
	add_child(layer)
	_say("황금 고블린: 5~10분마다 성 밖에 나타납니다")
	var g = _dir.spawn()
	g.hp *= 0.35  # 영상 길이에 맞게(잡히는 데 걸리는 시간만 줄인다)
	g.hp_max = g.hp
	g.global_position = _ring(2, 14.0)
	_follow(g)
	await _wait(5.0)
	_say("무작위로 돌아다니다 영웅 쪽으로 가까이 오면…")
	var t := 0.0
	while is_instance_valid(g) and g.is_alive() and t < 40.0:
		if g._flee_t > 0.0 and t > 1.0:
			_say("맞으면 친 영웅 반대쪽으로 달아납니다 (속도는 영웅의 0.85배)")
		t += get_process_delta_time()
		if t > 8.0 and g._flee_t <= 0.0 and g._pause <= 0.0 and randf() < 0.02:
			g._waypoint = _ring(Formation.side_of(g.global_position), 3.0)  # 영웅 쪽으로 다시 다가오게(영상)
			g._has_wp = true
		await get_tree().process_frame
	_say("잡으면 황금 보따리! 골드(방치 15분 몫) + 가끔 가속·다이아")
	await _wait(4.0)


func _say(t: String) -> void:
	if _caption != null and _caption.text != t:
		_caption.text = t


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _ring(side: int, out: float) -> Vector3:
	return Formation.SIDE_DIR[side] * (_main.castle.half + Balance.WALL_T + out)


func _follow(n) -> void:
	if _rig != null:
		_rig.focus_on(n)
		_rig._focus_until = 1e12


func _snap(name_s: String) -> void:
	await _frames(4)
	var path := "%s_%s.png" % [_out, name_s]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(ok: bool, what: String, detail) -> void:
	print("%s %s %s" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		_fails += 1


func _finish() -> void:
	print("GOBLIN CHECK PASSED" if _fails == 0 else "GOBLIN CHECK FAILED (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

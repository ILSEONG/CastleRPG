extends Node3D
## 파티 퀘스트 리치·거미 여왕·새끼 거미 모델 확인(2026-10-15): 트리 안에서 만들어 메서드를 모두 불러 보고(오류·반환값·자세 변화),
## 새끼 거미 60마리(crowd_lod)의 한 프레임 시간을 찍는다. --shot=FILE이면 던전 조명 무대에 셋을 세워 사진을 찍는다.
## 헤드리스: godot --headless --path . res://tests/party_models_check.tscn
## 사진: xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --resolution 1500x900 res://tests/party_models_check.tscn -- --shot=FILE.png
const Art := preload("res://scripts/art.gd")
const ArenaKit := preload("res://scripts/arena_kit.gd")
const UnitModelScript := preload("res://scripts/unit_model.gd")
const SpiderModel := preload("res://scripts/spider_model.gd")

var _fails := 0


class Dummy extends Node:  # "crowd" 무리 수 세기용(monster.gd의 is_alive)
	func is_alive() -> bool:
		return true


func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		printerr("FAIL: " + msg)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
	if shot != "":
		await _shot(shot)
		get_tree().quit(0)
		return
	await _lich()
	await _spider(true)
	await _spider(false)
	await _crowd()
	print("FAILED %d" % _fails if _fails > 0 else "PARTY MODELS OK")
	get_tree().quit(1 if _fails > 0 else 0)


func _lich() -> void:
	var spec := Art.monster_spec("lich")
	check(spec.has("body"), "lich wears its Meshy body")
	var m = UnitModelScript.new()
	m.crowd_lod = true
	m.setup(spec, 2.2)
	add_child(m)
	m.play_walk()
	await _frames(3)
	var hit: float = m.play_attack(1.6)
	check(hit > 0.0 and m.is_busy(), "lich attack returns hit time %.2f" % hit)
	for a in ["Spellcast_Shoot", "Spellcast_Raise", "Spellcast_Long"]:
		var at: float = m.play_cast(a)
		check(at > 0.0 and m._current == a, "lich casts %s (%.2f s)" % [a, at])
		await _frames(2)
	m.play_loop("Spellcasting")
	check(m._current == "Spellcasting", "lich channels Spellcasting")
	m.hit_react(true)
	m.play_death()
	await _frames(3)
	m.queue_free()


func _spider(queen: bool) -> void:
	var s = SpiderModel.new()
	s.queen = queen
	s.size = 3.0 if queen else 0.7
	add_child(s)
	await _frames(2)
	for n in ["Body", "Abdomen", "Head"] + SpiderModel.LEGS:
		check(s._parts.has(n), "%s part %s" % [s.queen, n])
	var tip0: Vector3 = (s._parts.L1 as Node3D).global_transform.basis.get_rotation_quaternion().get_euler()
	s.play_walk()
	s.face(Vector3(1, 0, 0))
	for i in 20:
		s._process(0.05)
	var tip1: Vector3 = (s._parts.L1 as Node3D).global_transform.basis.get_rotation_quaternion().get_euler()
	check(not tip0.is_equal_approx(tip1), "walking moves the legs (%s)" % queen)
	check(absf(s.rotation.y - PI / 2.0) < 0.2, "spider turns toward face() dir")
	s.play_idle()
	var hit: float = s.play_attack(1.5)
	check(hit > 0.0 and s.is_busy(), "spider attack hit time %.2f" % hit)
	for i in 40:
		s._process(0.05)
	check(not s.is_busy(), "attack ends")
	var c: float = s.play_cast("Spellcast_Raise", 0.6)
	check(absf(c - 0.6) < 0.05, "play_cast(at_sec) lands on time (%.2f)" % c)
	s.play_loop("Running_A", 1.5)
	if queen:
		for sk in SpiderModel.SKILLS:
			var t: float = s.play_skill(sk)
			check(t > 0.0 and s.attack_kind == sk and s.is_busy(), "skill %s effect at %.2f" % [sk, t])
			var poses := {}
			for i in 30:
				s._process(t / 20.0)
				poses[str((s._parts.Body as Node3D).transform) + str((s._parts.Abdomen as Node3D).transform)] = true
			check(poses.size() > 5, "skill %s moves the body" % sk)
			var mouth: Vector3 = s.to_local(s.mouth())
			var tail: Vector3 = s.to_local(s.abdomen_tip())
			check(mouth.z > 0.2 and tail.z < -0.2, "%s: mouth in front (%s), abdomen tip behind (%s)" % [sk, mouth, tail])
			for i in 40:
				s._process(0.1)
		check(absf(s.play_skill("web", 1.0) - 1.0) < 0.05, "play_skill(at_sec) lands on time")
	check(s.hit_react(true), "hit_react flashes")
	var y0: float = (s._parts.Body as Node3D).position.y
	s.play_death()
	for i in 30:
		s._process(0.05)
	check((s._parts.Body as Node3D).position.y < y0 - 0.1, "death sinks the body")
	s.reset_pose()
	check(not s.is_busy() and s._act == "", "reset_pose back to idle")
	s.queue_free()
	await _frames(1)


## 새끼 거미 60마리(crowd_lod) + "crowd" 무리 60: 붐비면 자세를 CROWD_EVERY 프레임마다만 계산한다.
func _crowd() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 20, 20)
	add_child(cam)
	cam.look_at(Vector3.ZERO)
	var list := []
	for i in 60:
		var d := Dummy.new()
		d.add_to_group("crowd")
		add_child(d)
		var s = SpiderModel.new()
		s.queen = false
		s.size = 0.7
		s.crowd_lod = true
		s.position = Vector3((i % 10) - 4.5, 0, (i / 10) - 3.0) * 1.2
		add_child(s)
		s.play_walk()
		list.append(s)
	await _frames(5)
	var t0 := Time.get_ticks_usec()
	for f in 30:
		for s in list:
			s._process(1.0 / 60.0)
	var per_frame := (Time.get_ticks_usec() - t0) / 30.0
	print("SPIDERLINGS 60 crowd_lod: %.0f us per frame (script)" % per_frame)
	check(not list[0]._shadows, "crowded spiderlings drop shadows")
	for s in list:
		s.queue_free()
	for d in get_tree().get_nodes_in_group("crowd"):
		d.queue_free()
	await _frames(1)


## 사진: 던전 조명 무대(초원 사원, 밝은 낮) 위에 리치(표 크기 2.2) · 거미 여왕(키 3 m) · 새끼 거미 여럿, 게임처럼 위에서 비스듬히.
func _shot(out: String) -> void:
	var stage: Dictionary = ArenaKit.temple()
	add_child(stage.root)
	add_child(ArenaKit.lighting(stage.light))
	var c: Vector3 = stage.boss
	var lich = UnitModelScript.new()
	lich.setup(Art.monster_spec("lich"), 2.2)
	lich.position = c + Vector3(-2.6, 0, -1.4)
	add_child(lich)
	var q = SpiderModel.new()
	q.size = 3.0
	q.position = c + Vector3(2.4, 0, -0.8)
	add_child(q)
	var kids := []
	for i in 7:
		var s = SpiderModel.new()
		s.queen = false
		s.size = 0.7
		s.position = c + Vector3(-0.6 + (i % 4) * 1.3, 0, 2.6 + (i / 4) * 1.2 + (i % 2) * 0.4)
		add_child(s)
		kids.append(s)
	var cam := Camera3D.new()
	cam.fov = 38.0
	add_child(cam)
	var eye := c + Vector3(0.0, 9.0, 14.0)
	cam.global_transform = Transform3D(Basis.looking_at(c + Vector3(0, 1.2, 0.8) - eye), eye)
	await _frames(4)
	lich.face(Vector3(0.4, 0, 1))
	q.face(Vector3(-0.4, 0, 1))
	for i in kids.size():
		kids[i].face(Vector3(sin(i * 1.3) * 0.6, 0, 1))
		kids[i].play_walk()
	lich.play_cast("Spellcast_Raise")
	await _frames(20)
	q.play_skill("web")
	await _frames(30)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("SHOT ", out)

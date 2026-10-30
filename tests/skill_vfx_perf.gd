extends Node
## 스킬 연출 부하 측정(2026-10-30, 통과/실패 없음): 실제 main 씬 성 밖 벌판에 영웅 8명 + 몬스터 40마리(죽지 않게)를 두고,
## 영웅들의 액티브 스킬 쿨을 계속 비워 "여럿이 동시에 스킬을 쓰는" 최악의 장면을 SEC초 돌린다.
## 프레임 시간(평균·95%), 그리기 호출(평균·최대), 살아 있는 이펙트 수(최대)를 찍는다 — 바꾸기 전후를 같은 기계에서 비교한다.
## 실행(xvfb, GPU 포함): xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 540x960 res://tests/skill_vfx_perf.tscn

const GameData := preload("res://scripts/game_data.gd")
const Formation := preload("res://scripts/formation.gd")
const MonsterScript := preload("res://scripts/monster.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")
const HeroScript := preload("res://scripts/hero.gd")
const Fx := preload("res://scripts/fx.gd")

const HEROES := ["ignis", "nev", "valen", "frieda", "arteon", "grom", "selene", "kyle"]
const MONSTERS := 40
const SEC := 12.0

var _main


func _ready() -> void:
	Engine.max_fps = 0
	Economy.save_path = ""
	Fever.save_path = ""
	Fever.reset()
	GameData._config.fx_shake = "1"
	Economy.reset(Time.get_unix_time_from_system())
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(5)
	for c in _main.get_children():
		if c.get_script() == SpawnerScript:
			c.set_process(false)
	GameState.mode = GameState.Mode.STAGE
	await _frames(120)
	Engine.max_fps = 0
	for m in get_tree().get_nodes_in_group("monsters"):
		m.queue_free()
	var form = get_tree().get_first_node_in_group("heroes").formation
	for h in get_tree().get_nodes_in_group("heroes"):
		h.formation.release(h.index)
		h.queue_free()
	await _frames(3)
	var side := 2
	var base: Vector3 = Formation.SIDE_DIR[side] * (_main.castle.half + 20.0)
	var right := Vector3(Formation.SIDE_DIR[side].z, 0, -Formation.SIDE_DIR[side].x)
	var heroes := []
	for i in HEROES.size():
		var h = HeroScript.new()
		h.setup(side, GameData.hero(HEROES[i]), _main.castle, form, 5, 30)
		_main.add_child(h)
		heroes.append(h)
	await _frames(2)
	for i in heroes.size():
		var h = heroes[i]
		var p: Vector3 = base + right * ((i % 4) - 1.5) * 2.0 + Formation.SIDE_DIR[side] * (-2.0 if i < 4 else 0.0)
		h.move_to_point(p)
		h.global_position = p
		h._path.clear()
	for i in MONSTERS:
		var m = MonsterScript.new()
		m.setup("grunt", side, 1, _main.castle)
		_main.add_child(m)
		m.global_position = base + Formation.SIDE_DIR[side] * (5.0 + (i / 8) * 1.2) + right * ((i % 8) - 3.5) * 1.2
		m.hp_max *= 400.0
		m.hp = m.hp_max
	var rig = get_viewport().get_camera_3d().get_parent()
	rig.position = Vector3(base.x, rig.position.y, base.z) + Formation.SIDE_DIR[side] * 3.0
	await _frames(30)
	var times: Array[float] = []
	var draws: Array[int] = []
	var live_max := 0
	var t0 := Time.get_ticks_usec()
	var last := t0
	while (Time.get_ticks_usec() - t0) / 1e6 < SEC:
		for h in heroes:
			if is_instance_valid(h):
				for k in h._skx._cd:
					h._skx._cd[k] = minf(h._skx._cd[k], 0.0)
				h._blast_cd = 0.0
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		live_max = maxi(live_max, Fx.live())
	times.sort()
	var avg := 0.0
	for t in times:
		avg += t
	avg /= times.size()
	var davg := 0.0
	var dmax := 0
	for d in draws:
		davg += d
		dmax = maxi(dmax, d)
	davg /= draws.size()
	print("VFXPERF frames=%d avg_ms=%.2f p95_ms=%.2f draws_avg=%.0f draws_max=%d fx_live_max=%d" % [times.size(), avg, times[int(times.size() * 0.95)], davg, dmax, live_max])
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

extends Node
## 망루 체크(2026-10-13): 실제 main 씬(오토로드 포함)에서 watchtower.gd가
##  - 짓지 않았으면(공터·건물 표에 없음) 쏘지 않는다,
##  - Lv 5 망루가 사거리 안 몬스터에게 grunt 최대 HP × (base + per_level × 5) / 100 피해를 화살 도착 때 넣는다(피해 숫자 길 = take_damage),
##  - interval초마다 한 발(그 전엔 안 쏜다), 사거리 밖은 안 쏜다, 성문·성벽을 치는 몬스터를 먼저 고른다,
##  - 몬스터가 없으면 안 쏜다
## 를 확인한다. 망루가 아직 Balance.BUILDINGS에 없으면 level_override·pos_override로 세운다.
## 실행: godot --headless --path . res://tests/watchtower_check.tscn
## 화면(화살이 나는 중): xvfb-run -a godot --path . --resolution 720x1280 res://tests/watchtower_check.tscn -- --out=/tmp/watchtower.png

const Balance := preload("res://scripts/balance.gd")
const GameData := preload("res://scripts/game_data.gd")
const MonsterScript := preload("res://scripts/monster.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")
const WatchtowerScript := preload("res://scripts/watchtower.gd")
const PreloaderScript := preload("res://scripts/preloader.gd")

class ErrorCounter extends Logger:
	var count := 0
	func _log_error(_fn: String, _file: String, _line: int, _code: String, _why: String, _notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1

var _fails := 0
var _errors := ErrorCounter.new()
var _main
var _wt
var _known := false  # 망루가 건물 표에 있다(Economy·Balance 경로로 세운다)


func _ready() -> void:
	OS.add_logger(_errors)
	Economy.save_path = ""
	Fever.save_path = ""
	Fever.reset()
	Engine.time_scale = 1.0
	GameData._config.fx_shake = "0"
	Economy.reset(Time.get_unix_time_from_system())
	PreloaderScript.done = true
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(5)
	for c in _main.get_children():
		if c.get_script() == SpawnerScript:
			c.set_process(false)
		if c.get_script() == WatchtowerScript:
			_wt = c
	_clear_monsters()
	_check(_wt != null, "main adds a watchtower node", "")
	if _wt == null:
		_finish()
		return
	_known = not Balance.building(WatchtowerScript.ID).is_empty()
	print("WATCHTOWER known in Balance: ", _known)
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	if out != "":
		await _shot(out)
	else:
		await _run()
	_finish()


func _finish() -> void:
	if _errors.count > 0:
		print("WATCHTOWER SCRIPT ERRORS %d" % _errors.count)
	_fails += _errors.count
	if _fails > 0:
		print("WATCHTOWER FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("WATCHTOWER ALL PASSED")
		get_tree().quit(0)


## 망루를 세운다(level 0 = 허문다/공터).
func _set_tower(level: int) -> void:
	if _known:
		if level <= 0:
			Economy.unbuilt[WatchtowerScript.ID] = true
		else:
			Economy.unbuilt.erase(WatchtowerScript.ID)
			Economy.levels[WatchtowerScript.ID] = level
		_wt.level_override = -1
		_wt.pos_override = null
	else:
		_wt.level_override = level
		_wt.pos_override = Vector3(-8, 0, -8) if level > 0 else null


func _tower_pos() -> Vector3:
	var t: Dictionary = _wt.tower()
	return t.pos if not t.is_empty() else Vector3(-8, 0, -8)


func _run() -> void:
	GameState.mode = GameState.Mode.STAGE
	for h in get_tree().get_nodes_in_group("heroes") + get_tree().get_nodes_in_group("soldiers"):
		h.set_process(false)  # 망루 피해만 보게
	_wt.set_process(false)  # _process를 직접 흘린다(배속과 무관하게 정확한 초)
	var half: float = _main.castle.half

	# 1) 공터: 쏘지 않는다
	_set_tower(0)
	_check(_wt.tower().is_empty(), "unbuilt: no tower", str(_wt.tower()))
	var m = _monster(Vector3(-8, 0, -8) + Vector3(6, 0, 0))
	for i in 10:
		_wt._process(0.5)
	await _frames(5)
	_check(_wt.shots == 0 and is_equal_approx(m.hp, m.hp_max), "unbuilt: no arrows, no damage", "shots %d hp %f/%f" % [_wt.shots, m.hp, m.hp_max])

	# 2) Lv 5: 사거리 안 한 마리 → 바로 한 발, 도착 때 공식 피해
	_set_tower(5)
	var t: Dictionary = _wt.tower()
	_check(not t.is_empty() and int(t.level) == 5, "built Lv 5 tower", str(t))
	var tp := _tower_pos()
	m.global_position = tp + Vector3(12, 0, 3)
	var want := WatchtowerScript.damage(5, GameState.stage)
	var grunt_hp := float(GameData.monster("grunt").hp) * float(GameData.stage(GameState.stage).hp_mult)
	var pct := WatchtowerScript.num("watchtower_grunt_pct_base", 10.0) + WatchtowerScript.num("watchtower_grunt_pct_per_level", 1.0) * 5
	_check(want > 0.0 and is_equal_approx(want, grunt_hp * pct / 100.0), "damage = grunt max HP × (base + per_level × 5)%", "%f vs %f" % [want, grunt_hp * pct / 100.0])
	_wt._process(0.016)
	_check(_wt.shots == 1, "fires at once when an enemy is in range", str(_wt.shots))
	var arrows := _arrows()
	_check(arrows.size() == 1, "one arrow in flight", str(arrows.size()))
	var top := 0.0
	var waited := 0.0
	while is_equal_approx(m.hp, m.hp_max) and waited < 4.0:
		for a in _arrows():
			top = maxf(top, a.global_position.y)
		await get_tree().process_frame
		waited += get_process_delta_time()
	_check(is_equal_approx(m.hp_max - m.hp, want), "arrow lands: hp drops by exactly the formula", "%f vs %f" % [m.hp_max - m.hp, want])
	_check(top >= WatchtowerScript.MUZZLE_Y, "arrow flies in an arc from the tower top", "top y %f" % top)

	# 3) 간격: interval 전엔 안 쏘고, 지나면 한 발
	var iv := WatchtowerScript.interval()
	_wt._process(iv - 0.1)
	_check(_wt.shots == 1, "no second shot before %.1f s" % iv, str(_wt.shots))
	_wt._process(0.15)
	_check(_wt.shots == 2, "second shot after the interval", str(_wt.shots))
	for i in 20:  # 1/60초씩 interval만큼: 딱 한 발 더
		_wt._process(iv / 20.0)
	_check(_wt.shots == 3, "one shot per interval", str(_wt.shots))

	# 4) 사거리 밖: 안 쏜다
	var r := WatchtowerScript.range_m()
	m.global_position = tp + Vector3(r + 3.0, 0, 0)
	_wt._process(iv + 0.1)
	_check(_wt.shots == 3, "no shot beyond %.0f m" % r, str(_wt.shots))

	# 5) 성문을 치는 몬스터 우선: 성 안 가까운 것보다 성문 앞(성 밖, 성벽 띠) 것
	m.global_position = tp + Vector3(2, 0, 0)
	var g = _monster(Vector3(0, 0, half + 2.5))
	if Vector2(g.global_position.x - tp.x, g.global_position.z - tp.z).length() <= r:
		_check(_wt.pick_target(tp) == g, "prefers the enemy at the gate", "")
	g.global_position = Vector3(0, 0, half + 30.0)  # 성문에서 먼 벌판 → 가까운 것
	_check(_wt.pick_target(tp) == m, "otherwise the nearest", "")

	# 6) 몬스터가 없으면 안 쏜다
	_clear_monsters()
	await _frames(2)
	var before: int = _wt.shots
	_wt._process(iv + 0.1)
	_check(_wt.shots == before, "no monsters: no shot", str(_wt.shots))

	# 7) 실제 프레임 + 배속: x2면 1초 남짓에 interval 2초만큼 쏜다
	_set_tower(5)
	var k = _monster(tp + Vector3(8, 0, 0), 1000.0)
	_wt.set_process(true)
	Engine.time_scale = 2.0
	before = _wt.shots
	await get_tree().create_timer(iv * 2.0 + 0.2).timeout  # 게임 초(배속 반영)
	Engine.time_scale = 1.0
	var fired: int = _wt.shots - before
	_check(fired >= 2 and fired <= 3, "real frames: one shot per %.1f game-seconds" % iv, str(fired))
	k.queue_free()
	_set_tower(0)


func _shot(out: String) -> void:
	_set_tower(8)
	var tp := _tower_pos()
	var half: float = _main.castle.half
	for i in 7:
		var p := Vector3(-6.0 + i * 2.0, 0, half + 2.0 + (i % 2))
		var mm = _monster(p, 50.0)
		mm.set_process(i % 2 == 0)
	_wt.set("_cd", 0.0)
	GameData._config["watchtower_interval_sec"] = "0.12"  # 화면에 화살 여럿
	print("tower at ", tp, " half ", half)
	await get_tree().create_timer(1.3).timeout
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out, " shots ", _wt.shots)


func _monster(p: Vector3, hp_mult := 100.0):
	var m = MonsterScript.new()
	m.setup("grunt", 0, GameState.stage, _main.castle, hp_mult)
	_main.add_child(m)
	m.global_position = p
	m.set_process(false)  # 제자리
	return m


func _arrows() -> Array:
	var out := []
	for c in _main.get_children():
		if c is WatchtowerScript.Arrow and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _clear_monsters() -> void:
	for n in get_tree().get_nodes_in_group("monsters"):
		n.remove_from_group("monsters")
		n.queue_free()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(ok: bool, what: String, detail: String) -> void:
	if ok:
		print("WATCHTOWER PASS: " + what)
	else:
		_fails += 1
		print("WATCHTOWER FAIL: %s (%s)" % [what, detail])

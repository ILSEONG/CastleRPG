extends Node
## 전투 통계 체크(2026-11-02 [통계] 버튼): 성 화면 대기(방치)에는 버튼이 숨고, 스테이지를 밀면 배속 버튼 위에 나타나며 영웅별 가한 피해가 쌓이는지,
## 창을 열면 탭(가한 피해·받은 피해·치유량)마다 줄이 나오는지, 골드 던전·PVP 결투에도 버튼이 배속 버튼 위에 있고 값이 쌓이는지(PVP는 [상대 팀] 탭),
## 투사체·독처럼 늦게 들어가는 피해도 쏜 영웅 몫인지 본다. 저장 파일은 건드리지 않는다.
## 실행: godot --headless --path . res://tests/battle_stats_check.tscn
## 화면(창 열림, 성 스테이지 + 던전 + PVP 세 장): xvfb-run -a godot --path . --resolution 720x1280 res://tests/battle_stats_check.tscn -- --out=/tmp/stats.png

const BattleStats := preload("res://scripts/battle_stats.gd")
const PreloaderScript := preload("res://scripts/preloader.gd")
const TMP := "user://battle_stats_check.json"

var _fails := 0
var _main
var _out := ""
var _shots: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	Economy.save_path = ""
	Fever.save_path = ""
	Fever.reset()
	Music.settings_path = TMP
	Music.prefs = {}
	Engine.time_scale = 1.0
	Economy.reset(Time.get_unix_time_from_system())
	for h in preload("res://scripts/game_data.gd").heroes().slice(0, 5):
		Economy.heroes[h.id] = 1
	_unit()
	await _run()
	Engine.time_scale = 1.0
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	if _out != "" and not _shots.is_empty():
		var w := 540
		var h := 960
		var sheet := Image.create(w * _shots.size(), h, false, Image.FORMAT_RGB8)
		for i in _shots.size():
			var im: Image = _shots[i]
			im.convert(Image.FORMAT_RGB8)
			im.resize(w, h)
			sheet.blit_rect(im, Rect2i(0, 0, w, h), Vector2i(i * w, 0))
		sheet.save_png(_out)
		print("saved ", _out)
	if _fails > 0:
		print("BATTLE STATS FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("BATTLE STATS ALL PASSED")
		get_tree().quit(0)


## 집계 규칙만(장면 없이).
func _unit() -> void:
	var HeroScript := preload("res://scripts/hero.gd")
	var a = HeroScript.new()
	a.def = {"id": "a", "name": "A"}
	var b = HeroScript.new()
	b.def = {"id": "b", "name": "B"}
	var m := Node3D.new()
	BattleStats.reset("arena")
	BattleStats.src = a
	BattleStats.dealt(m, 100.0)
	BattleStats.healed(b, 30.0)
	var cap = BattleStats.capture()
	BattleStats.src = null
	BattleStats.dealt(m, 50.0)  # 영웅이 아닌 쪽(병사·망루)은 아무에게도
	BattleStats.run(cap, func(): BattleStats.dealt(m, 7.0))  # 늦게 들어간 피해(투사체·독)는 쏜 영웅에게
	BattleStats.healed(b, 5.0)  # 자연 회복은 자신에게
	BattleStats.taken(b, 40.0)
	var ra: Dictionary = BattleStats.row(a)
	var rb: Dictionary = BattleStats.row(b)
	_check(is_equal_approx(ra.dealt, 107.0) and is_equal_approx(ra.healed, 30.0), "dealt + delayed hit + heal go to the acting hero", str(ra))
	_check(is_equal_approx(rb.healed, 5.0) and is_equal_approx(rb.taken, 40.0) and rb.dealt == 0.0, "self heal and taken", str(rb))
	_check(BattleStats.src == null, "run() restores src", "")
	BattleStats.reset("arena")
	_check(BattleStats.list("arena").is_empty(), "reset clears", "")
	a.free()
	b.free()
	m.free()


func _run() -> void:
	PreloaderScript.done = true
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(5)
	Tutorial.save_path = ""
	Tutorial.state = "done"
	Tutorial.changed.emit()
	await _frames(5)
	var st = _find(_main, "res://scripts/stats_button.gd")
	var sp = _find(_main, "res://scripts/speed_button.gd")
	_check(st != null and sp != null, "castle has the stats button", "")
	if st == null:
		return
	_check(not st.button.visible, "idle (방치): stats button hidden", "")
	GameState.start_stage()
	await _frames(5)
	_check(st.button.visible, "stage: stats button shows", "")
	var r: Rect2 = st.button.get_global_rect()
	var s: Rect2 = sp.button.get_global_rect()
	_check(r.end.y <= s.position.y and absf(r.position.x - s.position.x) < 1.0 and not r.intersects(s), "stats sits above the speed button", "%s %s" % [r, s])
	await _until(func(): return _sum("castle", "dealt") > 0.0, 40.0)
	_check(_sum("castle", "dealt") > 0.0, "stage: heroes dealt damage", str(BattleStats.rows.get("castle", {}).values()))
	await _frames(30)
	_shot()  # 버튼(닫힌 창)
	st.open()
	await _frames(3)
	_check(st.popup.visible and st.list.get_child_count() >= 1, "popup opens with hero rows", str(st.list.get_child_count()))
	_check(st.list.get_child_count() == _main.strip_heroes().size(), "one row per castle hero", "%d vs %d" % [st.list.get_child_count(), _main.strip_heroes().size()])
	var prev := INF
	var sorted := true
	for c in st.list.get_children():
		if c.has_meta("value"):
			sorted = sorted and float(c.get_meta("value")) <= prev
			prev = float(c.get_meta("value"))
	_check(sorted, "rows sorted by value", "")
	for k in ["taken", "healed"]:
		st.kind_buttons[k].pressed.emit()
		await _frames(2)
		_check(st.kind == k and st.list.get_child_count() >= 1, "tab %s" % k, "")
	st.kind_buttons["dealt"].pressed.emit()
	await _frames(20)
	_shot()
	st.close()
	# 성 스테이지는 그대로(던전 동안 멈췄다가 이어진다)

	# 골드 던전
	_main._dev_dungeon("gold")
	await _frames(10)
	var d = _main._dungeon
	var dst = _deep(d, "res://scripts/stats_button.gd") if d != null else null
	var dsp = _deep(d, "res://scripts/speed_button.gd") if d != null else null
	_check(dst != null and dst.button.visible, "dungeon has the stats button", "")
	if dst != null and dsp != null:
		await _frames(3)
		_check(dst.button.get_global_rect().end.y <= dsp.button.get_global_rect().position.y, "dungeon: above the speed button", "")
		await _until(func(): return _sum("arena", "dealt") > 0.0, 40.0)
		_check(_sum("arena", "dealt") > 0.0, "dungeon: heroes dealt damage", "")
		_check(_sum("castle", "dealt") > 0.0, "castle stage stats kept while in a dungeon", "")
		dst.open()
		await _frames(20)
		_check(not dst._team_row.visible, "dungeon: no team tabs", "")
		_shot()
		dst.close()
	_main.leave_dungeon()
	await _frames(5)

	# PVP 결투
	Pvp.save_path = ""
	Pvp.load_save()
	Pvp.fetch()
	var started := Pvp.start("duel", Pvp.default_team("duel"))
	var pb = null
	for i in 30:
		if _main._dungeon != null and _main._dungeon.get_script().resource_path == "res://scripts/pvp_battle.gd":
			pb = _main._dungeon
			break
		await _frames(1)
	_check(started and pb != null, "PVP duel started", "")
	if pb != null:
		await _frames(5)
		var pst = _deep(pb, "res://scripts/stats_button.gd")
		_check(pst != null and pst.button.visible, "PVP has the stats button", "")
		_check(_sum("arena", "dealt") == 0.0, "PVP starts with fresh stats", str(_sum("arena", "dealt")))
		await _until(func(): return _sum("arena", "dealt", 0) > 0.0 and _sum("arena", "dealt", 1) > 0.0, 60.0)
		_check(_sum("arena", "dealt", 0) > 0.0 and _sum("arena", "dealt", 1) > 0.0, "PVP: both teams dealt damage", "%s / %s" % [_sum("arena", "dealt", 0), _sum("arena", "dealt", 1)])
		_check(_sum("arena", "taken", 0) > 0.0, "PVP: my heroes took damage", "")
		if pst != null:
			pst.open()
			await _frames(3)
			_check(pst._team_row.visible, "PVP: team tabs shown", "")
			pst.team_buttons[1].pressed.emit()
			await _frames(2)
			_check(pst.team == 1 and pst.list.get_child_count() >= 1, "PVP: enemy team rows", "")
			pst.team_buttons[0].pressed.emit()
			await _frames(20)
			_shot()
			pst.close()
		_main.leave_dungeon()
		await _frames(3)


func _sum(scope: String, k: String, team := 0) -> float:
	var t := 0.0
	for r in BattleStats.list(scope, team):
		t += float(r[k])
	return t


func _until(f: Callable, sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end and not f.call():
		await get_tree().process_frame


func _shot() -> void:
	if _out != "":
		_shots.append(get_viewport().get_texture().get_image())


func _find(n: Node, path: String) -> Node:
	for c in n.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
	return null


func _deep(n: Node, path: String) -> Node:
	var f = _find(n, path)
	if f != null:
		return f
	for c in n.get_children():
		var g = _deep(c, path)
		if g != null:
			return g
	return null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(ok: bool, what: String, detail: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		_fails += 1
		print("  FAIL ", what, "  ", detail)

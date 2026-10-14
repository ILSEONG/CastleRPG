extends Node
## 기능 창 → 건물 레벨업 체크(사용자 2026-10-14 "연구소 레벨업은 어떻게 해? 지금 연구소 클릭하면 연구만 가능해"):
## 연구소·주점·파견소는 탭하면 기능 창(연구·모집·의뢰)이 바로 열린다. 그 창마다 [<건물> 레벨업 Lv n → n+1 ›]가 있어
## 누르면 기능 창이 닫히고 그 건물 창(비용·시간·선행 조건·[업그레이드]·[가속])이 열리고, 건물 창의 기능 버튼으로 돌아온다.
## 건설 중이면 "레벨업 중 · 남은 시간", 최대 레벨이면 "정보 (최대 레벨)". 공터(안 지은 주점·파견소)면 버튼이 없다.
## 실행: godot --headless --path . res://tests/feature_levelup_check.tscn
## 화면: xvfb-run -a godot --path . --resolution 720x1280 res://tests/feature_levelup_check.tscn -- --out=/tmp/levelup (창마다 png)

const GameData := preload("res://scripts/game_data.gd")
const PreloaderScript := preload("res://scripts/preloader.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")

class ErrorCounter extends Logger:
	var count := 0
	func _log_error(_fn: String, _file: String, _line: int, _code: String, _why: String, _notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1

var _fails := 0
var _errors := ErrorCounter.new()
var _main
var _out := ""


func _ready() -> void:
	OS.add_logger(_errors)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
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
	var bwin = _child("res://scripts/building_panel.gd")
	var rw = _child("res://scripts/research_panel.gd")
	var rec = _child("res://scripts/recruit_panel.gd")
	var dw = _child("res://scripts/dispatch_panel.gd")
	_check(bwin != null and rw != null and rec != null and dw != null, "main has the building, research, recruit and dispatch windows", "")
	if _fails == 0:
		await _run(bwin, rw, rec, dw)
	_finish()


func _run(bwin, rw, rec, dw) -> void:
	for id in [GameData.LAB, GameData.TAVERN, GameData.DISPATCH]:
		Economy.unbuilt.erase(id)
		Economy.levels[id] = 3
	Economy.changed.emit()
	var cases := [[GameData.LAB, rw, "research_button"], [GameData.TAVERN, rec, "recruit_button"], [GameData.DISPATCH, dw, "dispatch_button"]]
	for c in cases:
		var id: String = c[0]
		var win = c[1]
		var name := GameData.building_name(id)
		win.open()
		await _frames(3)
		_check(win.level_button.visible and win.level_button.text == "%s 레벨업 Lv 3 → 4 ›" % name, "%s window shows [%s 레벨업 Lv 3 → 4 ›]" % [id, name],
			"visible=%s text=%s" % [win.level_button.visible, win.level_button.text])
		await _shot("%s_window" % id)
		win.level_button.pressed.emit()
		await _frames(3)
		await _shot("%s_building" % id)
		_check(bwin.is_open() and not win.is_open() and bwin.building_id == id and bwin.upgrade_button.visible and bwin.time_label.visible,
			"%s: the button closes the feature window and opens the building window with cost/time/[업그레이드]" % id,
			"bwin=%s win=%s bid=%s up=%s" % [bwin.is_open(), win.is_open(), bwin.building_id, bwin.upgrade_button.visible])
		var back: Button = bwin.get(c[2])
		_check(back.visible, "%s building window has its feature button back (%s)" % [id, back.text], "")
		bwin.close()
		await _frames(3)
	# 건설 중 / 최대 레벨 / 공터
	_check(bwin.levelup_text(GameData.LAB).begins_with("연구소 레벨업 Lv"), "idle lab text", bwin.levelup_text(GameData.LAB))
	Economy.levels[GameData.LAB] = int(GameData.building_def(GameData.LAB).max_level)
	_check(bwin.levelup_text(GameData.LAB) == "연구소 정보 (최대 레벨) ›", "max-level text", bwin.levelup_text(GameData.LAB))
	Economy.unbuilt[GameData.DISPATCH] = true
	dw.open()
	await _frames(3)
	_check(not dw.level_button.visible, "an unbuilt 파견소 lot has no level-up button", "")
	dw.close()


func _shot(name: String) -> void:
	if _out == "" or DisplayServer.get_name() == "headless":
		return
	await _frames(20)
	DirAccess.make_dir_recursive_absolute(_out)
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])


func _child(path: String) -> Node:
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
	return null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(cond: bool, what: String, detail: String) -> void:
	if cond:
		print("PASS ", what)
	else:
		_fails += 1
		print("FAIL ", what, " — ", detail)


func _finish() -> void:
	_fails += _errors.count
	if _errors.count > 0:
		print("FEATURE LEVELUP SCRIPT ERRORS %d" % _errors.count)
	if _fails > 0:
		print("FEATURE LEVELUP FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("FEATURE LEVELUP ALL PASSED")
		get_tree().quit(0)

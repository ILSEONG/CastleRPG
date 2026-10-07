extends Node
## 설정 창 체크(2026-10-06): 실제 main 씬에서 오른쪽 아래 메뉴 [설정]을 눌러 창을 열고, 배경음악 켬/끔·음량·화면 흔들림·피해 숫자를 바꿔
## 바로 적용되는지(Music·GameData.fx_shake·Prefs), 임시 settings.json에 남는지(다시 읽어도 같은지) 본다. 기기 설정 파일은 건드리지 않는다.
## 실행: godot --headless --path . res://tests/settings_check.tscn
## 화면 한 장: xvfb-run -a godot --path . --resolution 720x1280 res://tests/settings_check.tscn -- --out=/tmp/settings.png

const GameData := preload("res://scripts/game_data.gd")
const Prefs := preload("res://scripts/prefs.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")
const PreloaderScript := preload("res://scripts/preloader.gd")
const TMP := "user://settings_check.json"

var _fails := 0
var _main


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Fever.reset()
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	Music.settings_path = TMP
	Music.prefs = {}
	Music.enabled = true
	Music.set_volume(1.0, false)
	Economy.reset(Time.get_unix_time_from_system())
	await _run()
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	if _fails > 0:
		print("SETTINGS FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("SETTINGS ALL PASSED")
		get_tree().quit(0)


func _run() -> void:
	PreloaderScript.done = true
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(5)
	for c in _main.get_children():
		if c.get_script() == SpawnerScript:
			c.set_process(false)
	var menu = _find("res://scripts/side_menu.gd")
	_check(menu != null, "side menu exists", "")
	if menu == null:
		return
	_check(menu.buttons.has("settings") and not menu.buttons.has("music"), "menu has [설정] instead of [음악]", str(menu.buttons.keys()))
	menu.set_open(true)
	await _frames(2)
	menu.buttons.settings.pressed.emit()
	await _frames(2)
	var w = menu.windows.get("settings")
	_check(w != null and w.is_open(), "[설정] opens the settings window", "")
	_check(not menu.is_open, "menu folds after picking", "")
	if w == null:
		return
	_check(w.music_check.button_pressed and int(w.volume_slider.value) == 100 and w.volume_label.text == "100%", "shows music on at 100%", w.volume_label.text)
	_check(w.shake_check.button_pressed and w.numbers_check.button_pressed, "shake and damage numbers start on", "")
	_check(w.version_label.text == str(ProjectSettings.get_setting("application/config/version")), "shows game version", w.version_label.text)
	_check(w.name_label.text == "오프라인 모드", "offline: account shows offline mode", w.name_label.text)

	# 음량: 슬라이더를 끌면 바로 버스 크기가 바뀌고, 손을 떼면 저장
	w.volume_slider.value = 40
	var bus := AudioServer.get_bus_index(Music.BUS)
	var want := Music.VOLUME_DB + linear_to_db(0.4)
	_check(absf(Music.volume - 0.4) < 0.001 and absf(AudioServer.get_bus_volume_db(bus) - want) < 0.05, "volume slider applies instantly", "%.2f dB" % AudioServer.get_bus_volume_db(bus))
	_check(w.volume_label.text == "40%", "volume label follows", w.volume_label.text)
	w.volume_slider.drag_ended.emit(true)
	_check(absf(float(_file().get("music_volume", -1)) - 0.4) < 0.001, "volume saved on release", str(_file()))
	w.volume_slider.value = 0
	_check(AudioServer.is_bus_mute(bus), "volume 0 mutes the music bus", "")
	w.volume_slider.value = 70
	_check(not AudioServer.is_bus_mute(bus), "volume above 0 unmutes", "")
	w.volume_slider.drag_ended.emit(true)

	# 배경음악 끔/켬
	w.music_check.button_pressed = false
	_check(not Music.enabled and _file().get("music") == false, "music checkbox turns music off and saves", str(_file()))
	w.music_check.button_pressed = true
	_check(Music.enabled and _file().get("music") == true, "music checkbox turns music back on", "")

	# 화면 흔들림 · 피해 숫자
	_check(GameData.fx_shake(), "shake on by default", "")
	w.shake_check.button_pressed = false
	_check(not GameData.fx_shake() and _file().get("shake") == false, "shake off disables fx_shake and saves", str(_file()))
	w.numbers_check.button_pressed = false
	_check(not Prefs.get_bool("damage_numbers") and _file().get("damage_numbers") == false, "damage numbers off saves", "")
	_check(absf(float(_file().get("music_volume", -1)) - 0.7) < 0.001, "other writers keep music_volume", str(_file()))

	# 재시작 흉내: 파일에서 다시 읽는다
	Music.prefs = {}
	Music.volume = 1.0
	Music.enabled = false
	Music.load_settings()
	_check(absf(Music.volume - 0.7) < 0.001 and Music.enabled and not GameData.fx_shake() and not Prefs.get_bool("damage_numbers"), "settings survive a restart", "")
	w.close()
	w.open()
	await _frames(2)
	_check(int(w.volume_slider.value) == 70 and not w.shake_check.button_pressed and not w.numbers_check.button_pressed, "reopened window shows saved values", "")
	w.shake_check.button_pressed = true
	w.numbers_check.button_pressed = true
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	if out != "":
		await _frames(8)
		get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)


func _file() -> Dictionary:
	var json := JSON.new()
	if FileAccess.file_exists(TMP) and json.parse(FileAccess.get_file_as_string(TMP)) == OK and json.data is Dictionary:
		return json.data
	return {}


func _find(path: String) -> Node:
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
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

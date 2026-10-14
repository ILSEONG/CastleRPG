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
const GraphicsScript := preload("res://scripts/graphics.gd")

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

	# 그래픽 품질·프레임·절전 모드(2026-10-12)
	var g = GraphicsScript.current
	_check(g != null, "graphics node exists", "")
	var root := get_tree().root
	var sun: DirectionalLight3D = null
	for n in root.find_children("*", "DirectionalLight3D", true, false):
		if n.shadow_enabled:
			sun = n
	_check(GraphicsScript.quality() == "high" and sun != null and Engine.max_fps == 60, "defaults: high quality, shadows on, 60 fps", str(Engine.max_fps))
	var full := root.scaling_3d_scale
	w.quality_buttons["low"].pressed.emit()
	_check(GraphicsScript.quality() == "low" and _file().get("gfx_quality") == "low", "quality low saved", str(_file()))
	_check(sun != null and not sun.shadow_enabled, "low turns off the sun shadow", "")
	_check(absf(root.scaling_3d_scale - full * 0.65) < 0.01, "low lowers the 3D resolution", "%.2f vs %.2f" % [root.scaling_3d_scale, full])
	var late := DirectionalLight3D.new()
	late.shadow_enabled = true
	add_child(late)
	await _frames(2)
	_check(not late.shadow_enabled, "a light added later (dungeon) also has no shadow", "")
	w.quality_buttons["high"].pressed.emit()
	_check(sun.shadow_enabled and late.shadow_enabled and absf(root.scaling_3d_scale - full) < 0.01, "high restores shadows and resolution", "")
	late.queue_free()
	w.fps_buttons[30].pressed.emit()
	_check(Engine.max_fps == 30 and int(_file().get("gfx_fps", 0)) == 30, "30 fps applies and saves", str(Engine.max_fps))
	w.fps_buttons[60].pressed.emit()
	_check(Engine.max_fps == 60, "back to 60 fps", "")
	w.saver_check.button_pressed = true
	_check(GraphicsScript.saver_enabled() and _file().get("power_saver") == true, "power saver saves", "")
	await get_tree().create_timer(0.5).timeout  # 창을 다시 연 직후 누름 보호(OPEN_GUARD_MS)가 끝나게
	g._idle = GraphicsScript.SAVER_SEC
	await _frames(2)
	_check(g.saver_on and Engine.max_fps == GraphicsScript.SAVER_FPS and g._cover.visible, "idle 1 min: dims and drops fps", str(Engine.max_fps))
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	tap.position = Vector2(360, 640)
	get_viewport().push_input(tap)
	await _frames(3)
	_check(not g.saver_on and Engine.max_fps == 60 and not g._cover.visible, "a tap wakes it", str(Engine.max_fps))
	var up := tap.duplicate()
	up.pressed = false
	get_viewport().push_input(up)
	w.saver_check.button_pressed = false
	await _frames(2)

	# 로그아웃·약관·문의(2026-10-12): 오프라인이면 로그아웃은 숨김, 주소가 비면 준비 중
	_check(not w.logout_button.visible, "offline: no logout", "")
	_check(w.terms_button.visible and w.privacy_button.visible and w.inquiry_button.visible, "terms, privacy, inquiry buttons shown", "")
	w.open_inquiry()  # 오프라인: 문의 창 대신 알림(2026-10-14 — 문의는 게임 안 문의 창, tests/live_ops_online)
	_check(w.visible, "offline inquiry keeps settings open", "")
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	if out != "":
		await _frames(8)
		get_viewport().get_texture().get_image().save_png(out)
		var sc: ScrollContainer = w.body.get_parent().get_parent()
		sc.scroll_vertical = 100000
		await _frames(8)
		get_viewport().get_texture().get_image().save_png(out.replace(".png", "_bottom.png"))
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

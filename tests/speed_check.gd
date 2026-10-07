extends Node
## x1.5 배속 버튼 체크(2026-10-07): 실제 main 씬에서 왼쪽 중하단 버튼을 눌러 바로 1.5배가 되는지, 기기 설정 파일(임시)에만 남는지,
## 다른 UI(탭 바·오른쪽 아래 메뉴·전투 초상화 줄·튜토리얼 카드)와 겹치지 않는지, 던전에도 버튼이 있고 1.5배인지, 길드전은 버튼 없이 1배인지,
## 히트스톱이 끝나도 지금 배율로 돌아오는지, 실제 시각(Economy.time_now)은 배속과 무관한지 본다. 기기 설정 파일은 건드리지 않는다.
## 실행: godot --headless --path . res://tests/speed_check.tscn
## 화면 한 장(전투 중, 켬): xvfb-run -a godot --path . --resolution 720x1280 res://tests/speed_check.tscn -- --out=/tmp/speed.png

const SpeedButton := preload("res://scripts/speed_button.gd")
const CameraRig := preload("res://scripts/camera_rig.gd")
const PreloaderScript := preload("res://scripts/preloader.gd")
const TMP := "user://speed_check.json"

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
	Engine.time_scale = 1.0
	Economy.reset(Time.get_unix_time_from_system())
	for h in preload("res://scripts/game_data.gd").heroes().slice(0, 5):
		Economy.heroes[h.id] = 1
	await _run()
	Engine.time_scale = 1.0
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	if _fails > 0:
		print("SPEED FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("SPEED ALL PASSED")
		get_tree().quit(0)


func _run() -> void:
	PreloaderScript.done = true
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(5)
	Tutorial.save_path = ""
	Tutorial.state = "active"  # 미션 카드가 보이게(버튼이 그 위로 올라가는지)
	Tutorial.step = 3
	await _frames(5)
	var sp = _find("res://scripts/speed_button.gd")
	_check(sp != null, "speed button exists on the castle screen", "")
	if sp == null:
		return
	var b: Button = sp.button
	var vh := get_viewport().get_visible_rect().size.y
	_check(not SpeedButton.is_on() and is_equal_approx(Engine.time_scale, 1.0), "off by default, game at 1x", str(Engine.time_scale))
	var r := b.get_global_rect()
	_check(r.position.x <= 20.0 and r.get_center().y > vh * 0.5 and r.end.y < vh - 104.0, "left, lower half, above the tab bar", str(r))
	var menu = _find("res://scripts/side_menu.gd")
	_check(menu == null or not r.intersects(menu.toggle.get_global_rect()), "does not overlap the bottom-right menu", "")
	var card = _find("res://scripts/tutorial_card.gd")
	await _frames(30)
	r = b.get_global_rect()
	print("card visible=", card.panel.visible if card != null else null, " ", Tutorial.active(), " ", Tutorial.mission().get("title", ""))
	_check(card != null and card.panel.visible and r.end.y <= card.panel.global_position.y, "sits above the tutorial card",
		"%s vs %s" % [r, card.panel.get_global_rect() if card != null else null])
	var tr: Rect2 = menu.toggle.get_global_rect()
	_check(absf(r.end.y - tr.end.y) < 1.0, "same height as the bottom-right [메뉴] button (with the card)", "%s vs %s" % [r, tr])
	var chat = _find("res://scripts/chat_bar.gd")
	if chat != null:
		var cr: Rect2 = chat.button.get_global_rect()
		_check(absf(cr.end.y - tr.end.y) < 1.0 and cr.end.x <= tr.position.x, "chat line on the same line, left of [메뉴]", "%s vs %s" % [cr, tr])
	var hot = _find("res://scripts/hot_deal.gd")
	if hot != null and hot.hud_button != null:
		_check(not hot.hud_button.get_global_rect().intersects(r), "hot-deal button stays above, no overlap", str(hot.hud_button.get_global_rect()))
	Tutorial.state = "done"
	await _frames(5)
	r = b.get_global_rect()
	tr = menu.toggle.get_global_rect()
	_check(absf(r.end.y - tr.end.y) < 1.0, "same height as [메뉴] (no card)", "%s vs %s" % [r, tr])
	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			shot = a.substr(6)
	if shot != "":
		await _frames(8)
		get_viewport().get_texture().get_image().save_png(shot.get_basename() + "_nocard.png")
	Tutorial.state = "active"
	await _frames(5)
	r = b.get_global_rect()
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	if out != "":
		await _frames(8)
		get_viewport().get_texture().get_image().save_png(out.get_basename() + "_idle.png")

	b.pressed.emit()
	_check(SpeedButton.is_on() and is_equal_approx(Engine.time_scale, 1.5), "tap turns x1.5 on instantly", str(Engine.time_scale))
	_check(bool(_file().get("speed_x15", false)), "saved on the device (settings file)", str(_file()))
	_check(b.text == "", "no waiting label on the button", b.text)

	# 실제 시각은 배속과 무관: 0.5 실제 초 동안 Economy.time_now()도 약 0.5초
	var t0 := Economy.time_now()
	var w0 := Time.get_ticks_msec()
	await get_tree().create_timer(0.5, true, false, true).timeout
	var dt_econ := Economy.time_now() - t0
	var dt_real := (Time.get_ticks_msec() - w0) / 1000.0
	_check(absf(dt_econ - dt_real) < 0.2, "wall-clock timers stay real time", "econ %.2f real %.2f" % [dt_econ, dt_real])

	GameState.start_stage()
	await _frames(60)
	var strip = _main._strip
	r = b.get_global_rect()
	_check(strip.visible and not strip.row.get_global_rect().intersects(r), "in battle: above the hero portrait row", "%s vs %s" % [r, strip.row.get_global_rect()])
	_check(sp.visible and b.visible, "visible during the stage battle", "")
	_check(is_equal_approx(Engine.time_scale, 1.5), "battle runs at x1.5", str(Engine.time_scale))

	# 히트스톱이 끝나면 지금 배율로
	Engine.time_scale = 1.5 * CameraRig.STOP_SCALE
	CameraRig._unstop(1.0)
	_check(is_equal_approx(Engine.time_scale, 1.5), "hit-stop ends back at x1.5", str(Engine.time_scale))

	if out != "":
		if not strip.cells.is_empty():
			strip.pick(strip.cells[0].hero)
		await _frames(40)
		get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)

	# 모든 컨텐츠(2026-10-07): 던전에도 같은 버튼이 있고 1.5배, 나와도 1.5배
	_main._dev_dungeon("gold")
	await _frames(10)
	var dsp = _child_with(_main._dungeon, "res://scripts/speed_button.gd")
	_check(_main._dungeon != null and dsp != null and dsp.button.visible, "dungeon has the x1.5 button", "")
	_check(is_equal_approx(Engine.time_scale, 1.5), "dungeon runs at x1.5", str(Engine.time_scale))
	if dsp != null:
		dsp.button.pressed.emit()
		_check(is_equal_approx(Engine.time_scale, 1.0) and not SpeedButton.is_on(), "dungeon button turns it off", str(Engine.time_scale))
		dsp.button.pressed.emit()
		_check(is_equal_approx(Engine.time_scale, 1.5), "and on again", str(Engine.time_scale))
	_main.leave_dungeon()
	await _frames(3)
	_check(is_equal_approx(Engine.time_scale, 1.5), "back on the castle screen: x1.5 again", str(Engine.time_scale))

	# 길드전은 제외(사용자 2026-10-07 "길드전은 아니야"): 켜 둬도 버튼 없이 1배, 나오면 다시 1.5배
	Guild.save_path = ""
	GuildWar.save_path = ""
	Guild.unlocked = true
	Guild.join(Guild.recommendations()[1])
	var now := Economy.time_now()
	GuildWar.fixed_now = GuildWar.battle_at(GuildWar.week_of(preload("res://scripts/game_data.gd").reset_day(now)), -1.0) + 10.0
	GuildWar.fetch()
	await _frames(2)
	GuildWar.enter(GuildWar.default_squad())
	await _frames(20)
	var war = _main._dungeon
	_check(war != null and war.get_script().resource_path == "res://scripts/war_battle.gd", "guild war battle started", str(war))
	if war != null and war.get_script().resource_path == "res://scripts/war_battle.gd":
		_check(_child_with(war, "res://scripts/speed_button.gd") == null and is_equal_approx(Engine.time_scale, 1.0), "guild war: no button, runs at 1x", str(Engine.time_scale))
		if out != "":
			await _frames(30)
			get_viewport().get_texture().get_image().save_png(out.get_basename() + "_war.png")
		_main.leave_dungeon()
		await _frames(3)
		_check(is_equal_approx(Engine.time_scale, 1.5), "after guild war: x1.5 again", str(Engine.time_scale))
	GuildWar.fixed_now = -1.0

	b.pressed.emit()
	_check(not SpeedButton.is_on() and is_equal_approx(Engine.time_scale, 1.0), "tap again turns it off", str(Engine.time_scale))
	_check(not bool(_file().get("speed_x15", true)), "off saved on the device", str(_file()))


func _file() -> Dictionary:
	var json := JSON.new()
	if FileAccess.file_exists(TMP) and json.parse(FileAccess.get_file_as_string(TMP)) == OK and json.data is Dictionary:
		return json.data
	return {}


func _child_with(n: Node, path: String) -> Node:
	if n == null:
		return null
	for c in n.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
	return null


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

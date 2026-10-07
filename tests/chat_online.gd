extends Node
## 온라인 채팅 체크 + 화면(개발용): 로컬 서버(메모리 PGlite, ALLOW_TEST_HOOKS=1)에 게스트로 접속한다. 다른 게스트 하나(HTTP 직접)가
## 전체 채널에 말하면 성 화면 채팅 줄에 보이는지, 줄을 누르면 창이 열리는지, 보내면 내 줄이 바로 보이고 서버 줄로 바뀌는지,
## 2초 안에 또 보내면 알림만 나오고 입력이 남는지, 길드에 들면 [길드] 탭이 생기고 길드 채널이 되는지, 채팅 줄이 배속 버튼·
## 오른쪽 아래 메뉴·탭 바·튜토리얼 카드와 겹치지 않는지 본다.
## 실행: cd server && PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=8790 node src/main.ts &
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/chat_online.tscn -- --api=http://127.0.0.1:8790 --device=/tmp/x/device.json --out=/tmp/chat.png
## 마지막 줄이 CHAT ONLINE PASSED(실패면 종료 코드 1).

var _main
var _bar
var _panel
var _speed
var _menu
var _shots: Array = []
var _fails := 0
var _resp_done := false
var _other_token := ""


func _ready() -> void:
	Fever.save_path = ""
	Guild.save_path = ""
	get_window().size = Vector2i(360, 640)
	var device := Net.arg_value("device")
	_check(Net.is_online() and device != "", "online mode with --api and --device", Net.api_base)
	if _fails > 0:
		return _finish()
	Net.device_path = device
	Net.auth_path = device.get_base_dir().path_join("auth.json")
	DirAccess.remove_absolute(device)
	Net.set_auth("guest")
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_check(await _wait_until(func(): return Net.ready_once and _main.camera != null, 30.0), "world built after connecting", "")
	for c in _main.get_children():
		var p: String = c.get_script().resource_path if c.get_script() != null else ""
		if p == "res://scripts/chat_bar.gd":
			_bar = c
		elif p == "res://scripts/speed_button.gd":
			_speed = c
		elif p == "res://scripts/side_menu.gd":
			_menu = c
	_check(_bar != null and _speed != null and _menu != null, "chat bar, speed button and menu exist", "")
	if _fails > 0:
		return _finish()
	_panel = _bar.panel
	await _wait_until(func(): return preload("res://scripts/preloader.gd").done, 30.0)
	await _frames(30)
	_check(_bar.button.visible, "chat bar shows online", "")
	_layout_checks()

	# 다른 플레이어가 전체 채널에 말한다
	var other: Dictionary = await _raw("POST", "/v1/auth/guest", {"device_id": "chat-check-other-%d" % Time.get_ticks_msec()}, "")
	_other_token = str(other.get("token", ""))
	var said: Dictionary = await _raw("POST", "/v1/chat", {"channel": "all", "text": "안녕하세요! 같이 성 키워요"}, _other_token)
	_check(said.has("msg"), "other player speaks in 전체", str(said))
	Chat.poll()
	_check(await _wait_until(func(): return Chat.latest().get("text", "") == "안녕하세요! 같이 성 키워요", 10.0), "bar's latest line = other player's message", str(Chat.latest()))
	await _snap()  # 1. 성 화면 채팅 줄

	_bar.button.pressed.emit()
	_check(_panel.is_open() and Chat.window_open, "tapping the bar opens the chat window", "")
	_check(not _panel.buttons["tab:guild"].visible, "no 길드 tab outside a guild", "")
	_panel.input.text = "반가워요 :)"
	_panel.send()
	var local: Array = Chat.messages.all.filter(func(m): return m.get("local", false))
	_check(local.size() == 1 and _panel.input.text == "", "my line shows at once, input cleared", str(Chat.messages.all))
	_check(_panel.buttons.send.text == "보내기", "send button label never changes", _panel.buttons.send.text)
	_check(await _wait_until(func(): return Chat.messages.all.filter(func(m): return m.get("local", false)).is_empty(), 10.0), "server confirms my line", "")
	var mine: Dictionary = Chat.messages.all[-1]
	_check(mine.me and int(mine.id) > 0 and mine.text == "반가워요 :)", "my confirmed line is last", str(mine))
	_panel.input.text = "또 보내기"
	_panel.send()
	_check(_panel.input.text == "또 보내기" and _panel.notice_label.text != "", "too fast: notice, input kept", _panel.notice_label.text)
	await _snap()  # 2. 전체 채널

	# 신고: 남의 줄 → 확인 상자 → [신고] → 바로 "신고함", 서버가 받는다
	var theirs: Dictionary = Chat.messages.all.filter(func(m): return not m.me)[-1]
	_panel.ask_report(theirs)
	_check(_panel.is_confirm_open(), "tapping another player's line asks to report", "")
	await _snap()  # 3. 신고 확인
	_panel.buttons.report_ok.pressed.emit()
	_check(not _panel.is_confirm_open() and Chat.reported.has(int(theirs.id)), "report marks the line at once", "")
	var before := int(Net.requested.get("/v1/chat/report", 0))
	_check(before >= 1, "report sent to the server", str(Net.requested))
	await get_tree().create_timer(1.5, true, false, true).timeout
	_check(Chat.reported.has(int(theirs.id)), "server accepted the report (mark stays)", "")
	var own: Dictionary = Chat.messages.all.filter(func(m): return m.me)[-1]
	_panel.ask_report(own)
	_check(not _panel.is_confirm_open(), "my own line cannot be reported", "")

	# 길드에 들면 [길드] 탭
	await _request("/v1/test/stage", {"stage": 37})
	Guild.fetch()
	_check(await _wait_until(func(): return Guild.recommendations().size() == 5, 10.0), "system guilds exist", "")
	Guild.join(Guild.recommendations()[0])
	_check(await _wait_until(func(): return Guild.joined() and not Guild.busy, 10.0), "join a guild", "")
	Chat.poll()
	_check(await _wait_until(func(): return Chat.has_guild, 10.0), "chat sees my guild", "")
	await _frames(4)
	_check(_panel.buttons["tab:guild"].visible, "길드 tab appears", "")
	_panel._pick("guild")
	await get_tree().create_timer(2.2, true, false, true).timeout
	_panel.input.text = "길드원 여러분 오늘 드래곤 잡아요"
	_panel.send()
	_check(await _wait_until(func(): return not Chat.messages.guild.is_empty() and int(Chat.messages.guild[-1].id) > 0, 10.0), "guild message confirmed", str(Chat.messages.guild))
	await _frames(10)
	await _snap()  # 4. 길드 채널
	_panel.buttons.close.pressed.emit()
	_check(not _panel.is_open() and not Chat.window_open, "X closes the window", "")
	await _frames(6)
	_check(Chat.latest().get("ch", "") == "guild", "bar shows the newest line (guild)", str(Chat.latest()))
	await _snap()  # 5. 닫은 뒤 채팅 줄
	_layout_checks()
	# 관리자 [신고] 탭(화면용: 로컬 서버엔 관리자가 없어 목록을 직접 넣는다)
	Economy.admin = true
	_bar.button.pressed.emit()
	await _frames(4)
	_check(_panel.buttons["tab:reports"].visible, "admin sees the 신고 tab", "")
	_panel._pick("reports")
	await get_tree().create_timer(1.0, true, false, true).timeout
	Chat.reports = [{"id": 1, "reporter_name": "조용한궁수", "target_name": "흉포한늑대7", "channel": "all", "at": Time.get_unix_time_from_system(), "message_id": 12,
		"text": "야 *** 진짜", "raw": "야 씨1발 진짜", "context": [{"id": 11, "name": "조용한궁수", "text": "안녕하세요", "raw": null},
		{"id": 12, "name": "흉포한늑대7", "text": "야 *** 진짜", "raw": "야 씨1발 진짜"}, {"id": 13, "name": "조용한궁수", "text": "말 좀 곱게 해요", "raw": null}]}]
	Chat.reports_state = "ok"
	Chat.reports_changed.emit()
	await _frames(10)
	_check(not _panel.input_row.visible, "reports tab hides the input", "")
	await _snap()  # 6. 관리자 신고 목록
	_panel.close()
	Economy.admin = false
	_sheet()
	_finish()


func _layout_checks() -> void:
	var vh := get_viewport().get_visible_rect().size.y
	var r: Rect2 = _bar.button.get_global_rect()
	_check(not r.intersects(_speed.button.get_global_rect()), "bar clear of the x1.5 button", str(r))
	_check(not r.intersects(_menu.toggle.get_global_rect()), "bar clear of the menu button", str(_menu.toggle.get_global_rect()))
	_check(r.end.y <= vh - 104, "bar above the tab bar", str(r))
	var card = _speed.card
	if card != null and card.panel != null and card.panel.visible:
		_check(not r.intersects(card.panel.get_global_rect()), "bar clear of the tutorial card", str(card.panel.get_global_rect()))


func _raw(method: String, path: String, body, token: String) -> Dictionary:
	var h := HTTPRequest.new()
	add_child(h)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	h.request(Net.api_base + path, headers, HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET, JSON.stringify(body) if body != null else "")
	var res: Array = await h.request_completed
	h.queue_free()
	var d = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return d if d is Dictionary else {}


func _finish() -> void:
	if _fails > 0:
		print("CHAT ONLINE FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("CHAT ONLINE PASSED")
		get_tree().quit(0)


func _check(ok: bool, what: String, detail: String) -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + detail))
	if not ok:
		_fails += 1


func _request(path: String, body) -> void:
	_resp_done = false
	Net.send("POST", path, body, func(d):
		Economy.apply_server(d)
		_resp_done = true, func(): _resp_done = true)
	await _wait_until(func(): return _resp_done, 10.0)


func _sheet() -> void:
	var out := "/tmp/chat_online.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var w: int = _shots[0].get_width() / 2
	var h: int = _shots[0].get_height() / 2
	var sheet := Image.create(w * _shots.size(), h, false, Image.FORMAT_RGB8)
	for i in _shots.size():
		var img: Image = _shots[i]
		img.convert(Image.FORMAT_RGB8)
		img.save_png(out.get_basename() + "_%d.png" % (i + 1))
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	sheet.save_png(out)
	print("saved ", out, " shots=", _shots.size())


func _snap() -> void:
	await _frames(8)
	_shots.append(get_viewport().get_texture().get_image())


func _wait_until(cond: Callable, timeout_sec: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while not cond.call():
		if Time.get_ticks_msec() > end:
			return false
		await get_tree().process_frame
	return true


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

extends Node
## 파티 코드 온라인 체크 + 화면(개발용): 로컬 서버(메모리 PGlite, ALLOW_TEST_HOOKS=1)에 게스트 A(이 앱)로 접속하고, 두 번째 성주 B는 HTTP로 흉내 낸다.
## A [파티 만들기] → 코드 → B가 그 코드로 참가 → A 화면에 파티원 2명 → A [파티로 매칭 시작] → (훅으로 바로) AI 성주가 빈자리 → 둘 다 입장 수락
## → A의 전투에 B가 사람 자리로 앉는다. [코드로 참가] 창: 틀린 코드면 이유 한 줄.
## 실행: cd server && PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=8791 node src/main.ts &
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/party_online.tscn -- --api=http://127.0.0.1:8791 --device=/tmp/x/device.json --out=/tmp/party_online
## 마지막 줄이 PARTY ONLINE PASSED(실패면 종료 코드 1).

const BattleScript := preload("res://scripts/party_battle.gd")

var _main
var _fails := 0
var _resp_done := false
var _out := "/tmp/party_online"
var _b_token := ""


func _ready() -> void:
	Fever.save_path = ""
	Guild.save_path = ""
	Party.save_path = ""
	Party.auto_accept = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
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
	Tutorial.state = "skipped"
	await _request("/v1/test/grant_hero", {"hero_id": "hans"})
	await _frames(10)
	# 성주 B(HTTP)
	var g = await _http("POST", "/v1/auth/guest", {"device_id": "partyonlineb%d" % (Time.get_ticks_msec() % 100000000)}, "")
	_b_token = str(g.get("token", ""))
	await _http("POST", "/v1/test/grant_hero", {"hero_id": "hans"}, _b_token)
	_check(_b_token != "", "second lord B signed in", g)

	var tabs = _find("res://scripts/tab_bar.gd")
	tabs.press("dungeon")
	var panel = tabs.windows.dungeon
	panel.set_section("party")
	await _frames(10)
	var view = panel.party_tab
	view.buttons["party:lich"].pressed.emit()
	view.buttons["party:lich"].pressed.emit()
	_check(Party.in_lobby() and view._cards.lich.code.text.contains("······"), "[파티 만들기] shows the party at once (code pending)", view._cards.lich.code.text)
	_check(await _wait_until(func(): return str(Party.lobby().get("code", "")) != "", 10.0), "server gave a party code", Party.lobby())
	var code := str(Party.lobby().code)
	# B가 코드로 참가
	var j = await _http("POST", "/v1/party/lobby/join", {"code": code.to_lower(), "hero": {"id": "hans", "hp": 500, "atk": 40}}, _b_token)
	_check(j.get("party", {}).get("lobby", {}).get("members", []).size() == 2, "B joined by code", j)
	_check(await _wait_until(func(): return Party.lobby().get("members", []).size() == 2, 10.0), "A sees two members (polling)", Party.lobby())
	await _frames(10)
	_check(view._cards.lich.members.text.contains("방장") and view.buttons["start:lich"].text.contains("파티"), "the card lists members and the leader start button", view._cards.lich.members.text)
	await _snap("2_lobby")
	# 코드로 참가 창: 틀린 코드
	view._open_code()
	await _frames(10)
	view.code_panel.input.text = "WRONG9"
	view.code_panel.join()
	view.code_panel.join()
	_check(await _wait_until(func(): return view.code_panel.result_label.text != "", 10.0) and view.code_panel.result_label.text.contains("없습니다"),
		"[코드로 참가] with a wrong code says why", view.code_panel.result_label.text)
	await _snap("3_code_wrong")
	view.code_panel.close()
	# A가 매칭 시작 → 훅으로 바로 AI 성주
	view.buttons["start:lich"].pressed.emit()
	view.buttons["start:lich"].pressed.emit()
	_check(Party.state() == "queued", "leader start: queued at once", Party.queue())
	await _wait_until(func(): return not Party._busy, 10.0)
	var bq = await _http("GET", "/v1/party", null, _b_token)
	_check(str(bq.get("party", {}).get("queue", {}).get("state", "")) == "queued", "B is queued with the party", bq.get("party", {}).get("queue"))
	await _request("/v1/test/party_bots_now", {})
	_check(await _wait_until(func(): return Party.state() == "confirm", 10.0), "A gets the accept window", Party.queue())
	var bc = await _http("GET", "/v1/party", null, _b_token)
	var mid := str(bc.get("party", {}).get("queue", {}).get("match_id", ""))
	_check(mid != "" and mid == str(Party.queue().get("match_id", "")), "A and B are in the same match", [mid, Party.queue().get("match_id")])
	await _snap("4_confirm")
	await _http("POST", "/v1/party/accept", {"match_id": mid, "accept": true}, _b_token)
	Party.accept(true)
	_check(await _wait_until(func(): return _battle() != null, 15.0), "the party battle opens for A", Party.queue())
	var b = _battle()
	if b != null:
		var humans: Array = b.seats.filter(func(s): return not s.get("bot", false))
		_check(humans.size() == 2, "B sits as a human lord in A's battle", b.seats)
		await get_tree().create_timer(3.0).timeout
		await _snap("5_battle")
		b.hud._on_leave()
		await get_tree().create_timer(0.5, true, false, true).timeout
		b.hud._on_leave()
		await _frames(20)
	await _invite_flow()
	_finish()


## 초대: A와 B가 친구 → B가 파티를 만들고 A를 초대 → A 화면에 수락·거절 창 → [수락] → A가 B의 파티에. A의 [초대] 창에 B가 '파티원'.
func _invite_flow() -> void:
	Party.leave_lobby()
	await _frames(10)
	var fa = await _http("GET", "/v1/friends", null, Net.token)
	var fb = await _http("GET", "/v1/friends", null, _b_token)
	await _http("POST", "/v1/friends/request", {"code": str(fa.get("code", ""))}, _b_token)
	var acc = await _http("POST", "/v1/friends/request", {"code": str(fb.get("code", ""))}, Net.token)
	var a_id := ""
	for f in (await _http("GET", "/v1/friends", null, _b_token)).get("friends", []):
		a_id = str(f.get("id", ""))
	_check(acc.get("friends", []).size() == 1 and a_id != "", "A and B are friends", acc)
	await _http("POST", "/v1/party/lobby/create", {"quest": "lich", "diff": 1, "hero": {"id": "hans", "hp": 500, "atk": 40}}, _b_token)
	var inv = await _http("POST", "/v1/party/invite", {"to": a_id}, _b_token)
	_check(inv.get("sent", false) == true, "B invited A (A is online)", inv)
	var ov = Party.get_child(0)
	_check(await _wait_until(func(): return ov.invite_dim.visible, 15.0), "A gets the invite window", Party.invites)
	_check(ov.invite_info.text.contains("리치의 무덤"), "the invite names the quest", ov.invite_info.text)
	await _snap("6_invite")
	ov.invite_accept.pressed.emit()
	ov.invite_accept.pressed.emit()
	_check(not ov.invite_dim.visible, "[수락] closes the window at once", "")
	_check(await _wait_until(func(): return Party.lobby().get("members", []).size() == 2, 10.0), "A joined B's party from the invite", Party.lobby())
	var tabs = _find("res://scripts/tab_bar.gd")
	var view = tabs.windows.dungeon.party_tab
	await _frames(10)
	view._open_invite()
	_check(await _wait_until(func(): return view.invite_panel.buttons.size() == 1, 10.0), "A's [초대] window lists friend B", view.invite_panel.status_label.text)
	var bb: Button = view.invite_panel.buttons.values()[0] if view.invite_panel.buttons.size() > 0 else null
	_check(bb != null and bb.disabled and bb.text == "파티원", "B shows as a party member (not invitable)", bb.text if bb else "")
	await _snap("7_invite_list")
	view.invite_panel.close()


func _battle():
	for c in get_children():
		if c.get_script() == BattleScript and not c.is_queued_for_deletion():
			return c
	return null


func _find(path: String) -> Node:
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
	return null


func _http(method: String, path: String, body, token: String) -> Dictionary:
	var h := HTTPRequest.new()
	add_child(h)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	h.request(Net.api_base + path, headers, HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET, JSON.stringify(body) if body != null else "")
	var r = await h.request_completed
	h.queue_free()
	var d = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
	return d if d is Dictionary else {}


func _request(path: String, body) -> void:
	_resp_done = false
	Net.send("POST", path, body, func(d):
		if d is Dictionary and d.has("version"):
			Economy.apply_server(d)
		if d is Dictionary and d.get("party") is Dictionary:
			Party._take(d)
		_resp_done = true, func(): _resp_done = true)
	await _wait_until(func(): return _resp_done, 10.0)


func _snap(name_s: String) -> void:
	await _frames(8)
	var path := "%s_%s.png" % [_out, name_s]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait_until(cond: Callable, timeout_sec: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while not cond.call():
		if Time.get_ticks_msec() > end:
			return false
		await get_tree().process_frame
	return true


func _check(ok: bool, what: String, detail) -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + str(detail)))
	if not ok:
		_fails += 1


func _finish() -> void:
	print("PARTY ONLINE PASSED" if _fails == 0 else "PARTY ONLINE FAILED %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

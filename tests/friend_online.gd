extends Node
## 온라인 친구 + 모집권 던전 체크(개발용, 2026-10-06): 로컬 서버(메모리 PGlite, ALLOW_TEST_HOOKS=1)에 앱(게스트)과 봇 둘(B·C)이 접속한다.
## 친구가 없으면 도우미 = 시스템 추천 3 → B가 내 코드로 신청 → 친구 창에서 수락, C의 코드로 신청 → C가 수락 → 도우미 = 친구 둘의 영웅 →
## [친구 추가] 탭·추천 [새로고침] → B의 영웅과 출전(HUD "친구" 꼬리표) → 승리 → B는 오늘 다시 못 쓰고 C만 남는다.
## 실행: cd server && PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=8791 node src/main.ts &
##   xvfb-run -a -s "-screen 0 720x1280x24" godot --path . --rendering-driver opengl3 --resolution 720x1280 res://tests/friend_online.tscn -- \
##     --api=http://127.0.0.1:8791 --device=/tmp/x/device.json [--out=DIR]
## 마지막 줄이 FRIEND ONLINE PASSED(실패면 종료 코드 1).

var _main
var _dungeon_panel
var _out := ""
var _fails := 0
var _bots := {}  # "B"·"C" → {token, id}


func _ready() -> void:
	_out = Net.arg_value("out")
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)
	Fever.save_path = ""
	var device := Net.arg_value("device")
	_check(Net.is_online() and device != "", "online mode with --api and --device", Net.api_base)
	if _fails > 0:
		return _finish()
	DirAccess.make_dir_recursive_absolute(device.get_base_dir())
	Net.device_path = device
	Net.auth_path = device.get_base_dir().path_join("auth.json")
	DirAccess.remove_absolute(device)
	Net.set_auth("guest")
	for b in ["B", "C"]:  # 봇 둘: 게스트 로그인(시작 영웅), B는 아르테온도
		var r = await _http("POST", "/v1/auth/guest", {"device_id": "friend-bot-%s-%08x" % [b, randi()]})
		_bots[b] = {"token": r.token, "id": r.player_id}
	await _http("POST", "/v1/test/grant_hero", {"hero_id": "arteon"}, _bots.B.token)
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_check(await _wait_until(func(): return Net.ready_once and _main.camera != null, 30.0), "world built after connecting", "")
	await _frames(20)
	_dungeon_panel = _main.find_children("*", "", true, false).filter(func(n): return n.get_script() == preload("res://scripts/dungeon_panel.gd"))[0]
	var fp = _dungeon_panel.friend_panel

	# 1. 친구 없음 → 시스템 추천 3
	_dungeon_panel.open()
	_dungeon_panel.open_form("ticket")
	await _frames(20)
	var hs: Array = Economy.helper_candidates()
	_check(hs.size() == 3 and hs.all(func(h): return not h.has("friend") and h.key == h.hero_id), "no friends: 3 system helpers", str(hs))
	await _shot("f1_system")

	# 2. B가 내 코드로 신청 → 친구 창에 받은 신청, 추천에 C
	fp.open()
	_check(await _wait_until(func(): return not Economy.friends.is_empty() and not Economy.friends_waiting, 10.0), "friend list loads", "")
	var code: String = Economy.friends.get("code", "")
	_check(code.length() == 8, "my friend code", code)
	await _http("POST", "/v1/friends/request", {"code": code}, _bots.B.token)
	Economy.friends_load()
	_check(await _wait_until(func(): return Economy.friends.get("incoming", []).size() == 1, 10.0), "B's request arrives", str(Economy.friends))
	_check(Economy.friends.recommend.any(func(p): return p.id == _bots.C.id), "C is recommended", str(Economy.friends.recommend))
	await _frames(10)
	_check(fp.tab == "list" and fp._list_page.visible and not fp._add_page.visible and fp.tab_btns.list.text.contains("신청 1"),
		"friend list tab first, request count on the tab", fp.tab_btns.list.text)
	await _shot("f2_incoming")
	# 2b. [친구 추가] 탭: 코드 입력 + 추천 성주, [새로고침]은 목록을 다시 받는다
	fp.pick_tab("add")
	await _frames(10)
	_check(fp._add_page.visible and not fp._list_page.visible and fp.rec_list.get_child_count() >= 1, "add tab shows code input + recommendations", "")
	await _shot("f2b_add_tab")
	fp.refresh_recommend()
	_check(Economy.friends_waiting and fp.refresh_btn.disabled, "refresh fetches again (button disabled while waiting)", "")
	_check(await _wait_until(func(): return not Economy.friends_waiting, 10.0) and not fp.refresh_btn.disabled
		and Economy.friends.recommend.any(func(p): return p.id == _bots.C.id), "refresh done, C still recommended", "")
	fp.pick_tab("list")

	# 3. 수락, C의 코드로 신청 → C가 수락
	Economy.friend_op("accept", {"id": _bots.B.id})
	_check(await _wait_until(func(): return Economy.friends.get("friends", []).size() == 1 and not Economy.friends_waiting, 10.0), "accept B", "")
	var vc = await _http("GET", "/v1/friends", null, _bots.C.token)
	fp.code_edit.text = str(vc.code).to_lower()
	fp.send_code()
	_check(await _wait_until(func(): return Economy.friends.get("outgoing", []).size() == 1 and not Economy.friends_waiting, 10.0), "request C by code", "")
	var me: String = (await _http("GET", "/v1/friends", null, _bots.C.token)).incoming[0].id
	await _http("POST", "/v1/friends/accept", {"id": me}, _bots.C.token)
	Economy.friends_load()
	_check(await _wait_until(func(): return Economy.friends.get("friends", []).size() == 2, 10.0), "2 friends", str(Economy.friends.get("friends")))
	var b_hero = Economy.friends.friends.filter(func(p): return p.id == _bots.B.id)[0].hero
	_check(b_hero is Dictionary and b_hero.hero_id == "arteon", "B lends the strongest hero (arteon)", str(b_hero))
	await _frames(10)
	await _shot("f3_friends")
	fp.close()

	# 4. 도우미 = 친구 둘의 영웅
	Net.refresh()
	_check(await _wait_until(func(): return Economy.helper_candidates().size() == 2 and Economy.helper_candidates().all(func(h): return h.has("friend")), 10.0),
		"helpers are the 2 friends' heroes", str(Economy.helper_candidates()))
	_dungeon_panel.open_form("ticket")
	var bkey: String = "f:" + str(_bots.B.id)
	_dungeon_panel.pick_helper(bkey)
	await _frames(20)
	_check(_dungeon_panel.helper_id == bkey and not _dungeon_panel.party.has("arteon") and _dungeon_panel.party.size() == 4, "pick B's arteon", str(_dungeon_panel.party))
	await _shot("f4_form")

	# 5. 출전 → 승리
	_dungeon_panel.deploy()
	_check(await _wait_until(func(): return _main._dungeon != null, 10.0), "ticket dungeon starts with B's hero", "")
	var d = _main._dungeon
	if d != null:
		_check(d.heroes.size() == 5 and d.heroes[4].helper and d.heroes[4].helper_tag == "친구" and d.heroes[4].def.id == "arteon", "5th hero = friend's arteon", "")
		await _frames(150)
		await _shot("f5_fight")
		await _http("POST", "/v1/test/dungeon_age", {"run_id": d.run.run_id, "seconds": 30}, Net.token)
		d.clock = maxf(d.clock, 21.0)
		d.boss.take_damage(d.boss.hp)
		await _frames(3)
		for m in get_tree().get_nodes_in_group("monsters"):
			m.take_damage(m.hp)
		_check(await _wait_until(func(): return d.phase == d.Phase.RESULT and not d.result.is_empty(), 15.0) and d.result.get("win", false),
			"win", str(d.result))
		_check(await _wait_until(func(): return Economy.dungeon_state("ticket").helpers_used == [bkey], 10.0), "B used today", str(Economy.dungeon_state("ticket")))
		var left: Array = Economy.helper_candidates()
		_check(left.size() == 1 and left[0].key == "f:" + _bots.C.id, "only C is left today", str(left))
		d.leave()
		await _frames(20)
	_finish()


func _finish() -> void:
	if _fails > 0:
		print("FRIEND ONLINE FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("FRIEND ONLINE PASSED")
		get_tree().quit(0)


func _check(ok: bool, what: String, detail: String) -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + detail))
	if not ok:
		_fails += 1


## 앱 큐 밖에서 보내는 요청(봇·테스트 훅). JSON 응답(실패면 {}).
func _http(method: String, path: String, body, token := "") -> Variant:
	var h := HTTPRequest.new()
	add_child(h)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	h.request(Net.api_base + path, headers, HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET, JSON.stringify(body) if body != null else "")
	var r: Array = await h.request_completed
	h.queue_free()
	var data = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
	if int(r[1]) != 200:
		print("  http %s %s -> %d %s" % [method, path, int(r[1]), str(data)])
	return data if data is Dictionary else {}


func _wait_until(cond: Callable, sec: float) -> bool:
	var t := 0.0
	while t < sec:
		if cond.call():
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return cond.call()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	if _out == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))

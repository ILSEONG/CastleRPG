extends Node
## 스크롤 화면 끌기 체크(사용자 2026-10-14 "스크롤이 있는 화면에서 드래그 검토해줘(거래소 처럼)"): 로컬 서버(메모리 PGlite, ALLOW_TEST_HOOKS=1,
## tutorial_new_players=0)에 게스트로 붙어 목록을 길게 채운 뒤(장비·영웅·건물·길드), 스크롤 목록이 있는 창을 하나씩 열고 손가락처럼 끈다.
## 성 전투가 도는 동안처럼 끄는 중에 처치(Economy.changed)를 계속 일으킨다 — 1) 버튼 위에서 천천히 시작해도 목록이 끈 만큼 굴러간다,
## 2) 놓은 뒤에도 그 자리에 남는다(맨 위로 튀지 않는다), 3) 끄는 손가락 밑의 버튼·줄이 눌리지 않는다. 거래소 [판매 등록] 줄은 끌어도 안 골라진다.
## 실행: cd server && PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=8790 node src/main.ts &
##   curl -XPOST localhost:8790/v1/test/config -H 'content-type: application/json' -d '{"key":"tutorial_new_players","value":"0"}'
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/scroll_drag_online.tscn -- --api=http://127.0.0.1:8790 --device=/tmp/x/device.json
## 마지막 줄이 SCROLL DRAG ONLINE PASSED(실패면 종료 코드 1).

const PANELS := ["shop_panel", "mission_panel", "bag_panel", "hero_panel", "research_panel", "soldier_panel", "growth_panel", "pouch_panel",
	"dungeon_panel", "dispatch_panel", "exchange_panel", "friend_panel", "ranking_panel", "guild_panel", "chat_panel", "settings_panel",
	"build_list_panel", "mail_panel", "notice_panel", "inquiry_panel", "merchant_panel", "recruit_panel", "attendance_panel", "admin_panel"]

var _main
var _fails := 0
var _presses := 0
var _resp_done := false
var _seen := {}  # 확인한 ScrollContainer


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
	_check(await _wait_until(func(): return Net.ready_once and _main.camera != null and Net.up, 30.0), "world built after connecting", "")
	if _fails > 0:
		return _finish()
	# 목록을 길게: 건물·자원, 장비 30개, 영웅 여럿, 스테이지(길드·던전), 다이아
	await _request("/v1/test/levels", {"levels": {"dispatch": 30, "keep": 12, "gate": 10, "barracks": 10, "tavern": 10, "lab": 10, "houses": 10, "lumber": 10, "quarry": 10,
		"farm": 10, "archery": 10, "stable": 10}, "res": {"wood": 50000000, "stone": 50000000, "food": 50000000}})
	await _frames(30)
	for c in get_children():
		if "_picker" in c and not c.is_queued_for_deletion():
			_main = c
	await _wait_until(func(): return is_instance_valid(_main) and _main.camera != null, 30.0)
	var grades := []
	for i in 6:
		grades += ["N", "R", "SR", "SSR", "R"]
	await _request("/v1/test/grant_items", {"grades": grades})
	for h in ["arteon", "lumina", "frieda", "ignis", "valen", "pip", "nev", "selene", "thorgar", "tia"]:
		await _request("/v1/test/grant_hero", {"hero_id": h})
	await _request("/v1/test/stage", {"stage": 40})
	await _request("/v1/test/grant_diamonds", {"amount": 100000})
	Guild.fetch()
	await _wait_until(func(): return not Guild.recommendations().is_empty(), 10.0)
	var recs: Array = Guild.recommendations()
	if not recs.is_empty():
		Guild.join(recs[0])
	_check(await _wait_until(func(): return Guild.joined(), 10.0), "joined a guild (guild lists)", "")
	await _frames(60)
	await _fill_lists()
	get_tree().node_added.connect(_on_node_added)
	for n in get_tree().root.find_children("*", "BaseButton", true, false):
		_watch(n)
	for name in PANELS:
		await _panel(name)
	await _exchange_sell()
	await _odds()
	_finish()


## [확률 정보](모집 창 안의 창): 영웅별 확률 목록.
func _odds() -> void:
	var p := _find("recruit_panel")
	if p == null:
		return
	p.open()
	await get_tree().create_timer(0.7).timeout
	p.odds_button.pressed.emit()
	await _frames(20)
	var n := 0
	for sc in _scrolls(p.odds):
		n += await _drag_test("gacha_odds", sc)
	_check(n > 0, "gacha_odds: the odds list scrolls", "")
	p.close()
	await _frames(5)


## 서버 목록을 길게: 다른 성주 10명(채팅 한 줄씩·친구 신청·거래소 판매), 운영자인 나의 공지·우편 12개씩, 문의 5개.
func _fill_lists() -> void:
	Economy.friends_load()
	await _wait_until(func(): return str(Economy.friends.get("code", "")) != "", 10.0)
	var code := str(Economy.friends.get("code", ""))
	for i in 25:
		var login: Dictionary = await _http("POST", "/v1/auth/guest", {"device_id": "scroll-bot-%d-%d" % [i, Time.get_ticks_usec()]}, "")
		var tok := str(login.get("token", ""))
		if tok == "":
			continue
		await _http("POST", "/v1/chat", {"channel": "all", "text": "안녕하세요 성주님들 %d번째 인사입니다" % (i + 1)}, tok)
		if i >= 10:
			continue
		await _http("POST", "/v1/friends/request", {"code": code}, tok)
		var g: Dictionary = await _http("POST", "/v1/test/grant_items", {"grades": ["SR"]}, tok)
		var its: Array = g.get("player", {}).get("items", [])
		if not its.is_empty():
			await _http("POST", "/v1/market/list", {"item_id": int(its[-1].id), "currency": "gold", "price": 1000 + i * 100}, tok)
	await _request("/v1/test/admin", {})
	_resp_done = false
	Net.send("GET", "/v1/player", null, func(d):
		Economy.apply_server(d)
		_resp_done = true, func(): _resp_done = true)
	await _wait_until(func(): return _resp_done, 10.0)
	for i in 12:
		await _request("/v1/admin/notice", {"title": "공지 %d" % (i + 1), "body": "스크롤 확인용 공지입니다"})
		await _request("/v1/admin/mail", {"to": "all", "title": "우편 %d" % (i + 1), "body": "스크롤 확인용 우편입니다", "reward": {"gold": 10}})
	for i in 5:
		await _request("/v1/inquiry", {"key": "scrollq%d%d" % [i, Time.get_ticks_usec() % 100000], "category": "other", "body": "스크롤 확인용 문의 %d" % (i + 1)})
	Economy.friends_load()
	LiveOps.fetch_notices()
	LiveOps.fetch_mail()
	LiveOps.fetch_inquiries()
	Chat.poll()
	await _frames(60)


func _http(method: String, path: String, body, token: String) -> Dictionary:
	var h := HTTPRequest.new()
	add_child(h)
	var headers := PackedStringArray(["content-type: application/json"])
	if token != "":
		headers.append("authorization: Bearer " + token)
	h.request(Net.api_base + path, headers, HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET, JSON.stringify(body) if body != null else "")
	var res: Array = await h.request_completed
	h.queue_free()
	var data = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return data if data is Dictionary else {}


func _panel(name: String) -> void:
	var p := _find(name)
	if p == null:
		print("SKIP %s: not in the scene" % name)
		return
	if not p.has_method("open"):
		print("SKIP %s: no open()" % name)
		return
	p.open()
	await get_tree().create_timer(0.7).timeout  # 창을 연 직후 누름 막기 지나서 + 서버 목록
	await _frames(10)
	# 처치(골드만 바뀜) 10번에 목록을 다시 그리면 끌던 목록이 깜빡이고 버벅인다 — 다시 그린 줄 수를 센다
	_added = 0
	_count_in = p
	for i in 10:
		Economy.changed.emit()
		await get_tree().process_frame
	_count_in = null
	_check(_added == 0, name + ": a kill (gold change) does not rebuild the window", "%d nodes added over 10 kills" % _added)
	var tested := 0
	for sc in _scrolls(p):
		tested += await _drag_test(name, sc)
	if tested == 0:
		var info := []
		for sc in p.find_children("*", "ScrollContainer", true, false):
			info.append([sc.is_visible_in_tree(), sc.get_v_scroll_bar().max_value, sc.get_v_scroll_bar().page, sc.get_h_scroll_bar().max_value, sc.get_h_scroll_bar().page])
		print("NOTE %s: no scrollable list with this account's data %s" % [name, info])
	if p.has_method("close"):
		p.close()
	elif "visible" in p:
		p.visible = false
	await _frames(10)


## 한 목록 끌기: 버튼 위 → 처음 몇 프레임은 데드존 안에서 천천히(그동안 처치로 창이 다시 그려진다) → 길게. 굴러간 양·놓은 뒤·눌린 버튼을 본다.
func _drag_test(name: String, sc: ScrollContainer) -> int:
	if _seen.has(sc):
		return 0
	_seen[sc] = true
	var tested := 0
	for axis in [1, 0]:
		var bar: ScrollBar = sc.get_v_scroll_bar() if axis == 1 else sc.get_h_scroll_bar()
		var mode := sc.vertical_scroll_mode if axis == 1 else sc.horizontal_scroll_mode
		if mode == ScrollContainer.SCROLL_MODE_DISABLED or bar.max_value - bar.page < 10.0:
			continue
		tested += 1
		var label := "%s %s list (%s)" % [name, "vertical" if axis == 1 else "horizontal", sc.get_path().get_name(sc.get_path().get_name_count() - 1)]
		bar.value = 0.0
		await _frames(3)
		var r := sc.get_global_rect().intersection(get_viewport().get_visible_rect())
		var dir := Vector2(0, -1) if axis == 1 else Vector2(-1, 0)
		var span: float = r.size.y if axis == 1 else r.size.x
		var dist: float = minf(span * 0.6, (bar.max_value - bar.page) + 40.0)
		var from := r.get_center() - dir * dist * 0.5
		var before := bar.value
		var p0 := _presses
		await _finger_drag(from, dir, dist)
		var moved := bar.value - before
		var want := minf(dist * 0.6, bar.max_value - bar.page - 1.0)
		_check(moved >= want, label + ": drag scrolls it (rebuilds while dragging)", "moved %.0f want %.0f max %.0f page %.0f" % [moved, want, bar.max_value, bar.page])
		var at_release := bar.value
		for i in 30:  # 놓은 뒤 처치가 계속 나도 그 자리
			Economy.changed.emit()
			await get_tree().process_frame
		_check(bar.value >= at_release - 2.0, label + ": stays scrolled after release", "%.0f -> %.0f" % [at_release, bar.value])
		_check(_presses == p0, label + ": nothing under the finger was pressed", "%d presses" % (_presses - p0))
		bar.value = 0.0
	return tested


## 손가락: 누르고 → 데드존 안에서 1.5 px씩 6프레임(매 프레임 처치) → 남은 거리를 12프레임에 → 놓기.
func _finger_drag(from: Vector2, dir: Vector2, dist: float) -> void:
	var xf := get_viewport().get_final_transform()
	_touch(xf, from, true)
	await _frames(1)
	var pos := from
	for i in 6:
		Economy.changed.emit()
		pos += dir * 1.5
		_move(xf, pos, dir * 1.5)
		await _frames(1)
	var rest := dist - 9.0
	for i in 12:
		Economy.changed.emit()
		pos += dir * rest / 12.0
		_move(xf, pos, dir * rest / 12.0)
		await _frames(1)
	_touch(xf, pos, false)
	await _frames(2)


func _move(xf: Transform2D, at: Vector2, rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = 0
	ev.position = xf * at
	ev.relative = xf.basis_xform(rel)
	Input.parse_input_event(ev)


func _touch(xf: Transform2D, at: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = down
	ev.position = xf * at
	Input.parse_input_event(ev)


## 거래소 [판매 등록]: 줄을 끌어 굴려도 장비가 골라지지 않고, 짧게 누르면 골라진다.
func _exchange_sell() -> void:
	var p := _find("exchange_panel")
	if p == null:
		return
	p.open()
	await get_tree().create_timer(0.7).timeout
	p.pick_tab("sell")
	await _frames(10)
	var sc: ScrollContainer = null
	for s in _scrolls(p):
		sc = s
	if sc == null:
		_check(false, "exchange sell: list", "")
		return
	var bar := sc.get_v_scroll_bar()
	bar.value = 0.0
	await _frames(3)
	var r := sc.get_global_rect()
	await _finger_drag(r.get_center() + Vector2(0, r.size.y * 0.25), Vector2(0, -1), r.size.y * 0.5)
	_check(int(p.picked) == 0, "exchange sell: dragging over a row does not pick it", str(p.picked))
	_check(bar.value > 30.0, "exchange sell: the drag scrolled the list", str(bar.value))
	var row = null
	for k in p.buttons.keys():
		if str(k).begins_with("pick:") and is_instance_valid(p.buttons[k]) and p.buttons[k].get_global_rect().intersection(r).size.y > 40.0:
			row = p.buttons[k]
			break
	if row != null:
		var c: Vector2 = row.get_global_rect().intersection(r).get_center()  # 목록 안에 보이는 부분
		var xf := get_viewport().get_final_transform()
		_touch(xf, c, true)
		await _frames(2)
		_touch(xf, c, false)
		await _frames(3)
		_check(int(p.picked) != 0, "exchange sell: a short tap picks the row", str(p.picked))
	p.close()
	await _frames(5)


func _scrolls(p: Node) -> Array:
	var out := []
	for c in p.find_children("*", "ScrollContainer", true, false):
		if (c as ScrollContainer).is_visible_in_tree():
			out.append(c)
	return out


func _find(name: String) -> Node:
	for n in get_tree().root.find_children("*", "", true, false):
		var s = n.get_script()
		if s != null and s.resource_path.get_file() == name + ".gd":
			return n
	return null


var _added := 0
var _count_in: Node = null


func _on_node_added(n: Node) -> void:
	if _count_in != null and is_instance_valid(_count_in) and _count_in.is_ancestor_of(n):
		_added += 1
	if n is BaseButton:
		_watch(n)


func _watch(b: BaseButton) -> void:
	if not b.pressed.is_connected(_on_any_press):
		b.pressed.connect(_on_any_press)


func _on_any_press() -> void:
	_presses += 1


func _finish() -> void:
	if _fails > 0:
		print("SCROLL DRAG ONLINE FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("SCROLL DRAG ONLINE PASSED")
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

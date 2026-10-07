extends Node
## 온라인 거래소 체크 + 화면(개발용): 로컬 서버(메모리 PGlite, ALLOW_TEST_HOOKS=1)에 게스트로 접속해 오른쪽 아래 [메뉴] → [거래소]를 연다.
## 다른 판매자(HTTP로 만든 두 번째 게스트)가 장비 4개를 골드·다이아로 올려 둔다 → 구매 탭 목록 → 확인 창 → 구매(보관함으로, 골드 −값)
## → 판매 등록(보관함에서 빠짐, 내 판매) → 판매자가 내 판매를 사 감 → 내 판매에 판매 완료 → 대금 받기(값의 90%) → 올렸다 내리기(보관함으로).
## 실행: cd server && PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=8790 node src/main.ts &
##   curl -XPOST localhost:8790/v1/test/config -H 'content-type: application/json' -d '{"key":"tutorial_new_players","value":"0"}'
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/exchange_online.tscn -- --api=http://127.0.0.1:8790 --device=/tmp/x/device.json --out=/tmp/exchange.png
## 마지막 줄이 EXCHANGE ONLINE PASSED(실패면 종료 코드 1).

var _main
var _menu
var _panel
var _shots: Array = []
var _fails := 0
var _resp_done := false
var _seller := ""  # 두 번째 게스트 토큰


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
		if c.get_script() != null and c.get_script().resource_path == "res://scripts/side_menu.gd":
			_menu = c
	_check(_menu != null and _menu.windows.has("exchange"), "menu has 거래소", "")
	if _fails > 0:
		return _finish()
	_panel = _menu.windows.exchange

	# 판매자: 두 번째 게스트, 장비 4개를 골드 2·다이아 2로 올린다
	var login: Dictionary = await _http("POST", "/v1/auth/guest", {"device_id": "exchange-seller-%d" % Time.get_ticks_usec()}, "")
	_seller = str(login.get("token", ""))
	_check(_seller != "", "seller logged in", str(login))
	await _http("POST", "/v1/test/grant_gold", {"amount": 100000}, _seller)
	var granted: Dictionary = await _http("POST", "/v1/test/grant_items", {"grades": ["LR", "UR", "SSR", "SR"]}, _seller)
	var sitems: Array = granted.get("player", {}).get("items", [])
	_check(sitems.size() == 4, "seller has 4 items", str(sitems.size()))
	var prices := [["gold", 12000], ["gold", 3500], ["diamonds", 300], ["diamonds", 40]]
	for i in mini(4, sitems.size()):
		var r: Dictionary = await _http("POST", "/v1/market/list", {"item_id": int(sitems[i].id), "currency": prices[i][0], "price": prices[i][1]}, _seller)
		_check(r.get("market", {}).get("mine", []).size() == i + 1, "seller listed item %d" % (i + 1), str(r))

	# 나: 골드·다이아·장비
	await _request("/v1/test/grant_gold", {"amount": 50000})
	await _request("/v1/test/grant_diamonds", {"amount": 1000})
	await _request("/v1/test/grant_items", {"grades": ["UR", "SSR", "R"]})
	_check(Economy.items().size() >= 3, "I have items to sell", str(Economy.items().size()))
	await _frames(20)

	_menu.toggle.pressed.emit()
	await _frames(10)
	await _snap()  # 1. 메뉴의 [거래소]
	_menu.buttons.exchange.pressed.emit()
	_check(_panel.is_open(), "거래소 opens", "")
	_check(await _wait_until(func(): return _panel.listings.size() == 2, 10.0), "buy tab lists the 2 gold listings", str(_panel.listings.size()))
	await _snap()  # 2. 구매(골드)
	_panel.buttons.cur.pressed.emit()
	_check(await _wait_until(func(): return _panel.currency == "diamonds" and _panel.listings.size() == 2 and str(_panel.listings[0].currency) == "diamonds", 10.0),
		"diamond listings", str(_panel.listings))
	_panel.buttons.cur.pressed.emit()
	_check(await _wait_until(func(): return _panel.currency == "gold" and _panel.listings.size() == 2 and str(_panel.listings[0].currency) == "gold", 10.0), "back to gold", "")
	var cheap: Dictionary = _panel.listings[0]
	_check(int(cheap.price) == 3500, "cheapest first", str(cheap.price))
	var gold0 := Economy.gold
	var bag0 := Economy.items().size()
	_panel.buttons["buy:%d" % int(cheap.id)].pressed.emit()
	await _frames(4)
	_check(_panel.confirm.visible, "buy asks to confirm", "")
	await _snap()  # 3. 확인 창
	_panel.buttons.confirm.pressed.emit()
	_check(_panel.buttons.get("buy:%d" % int(cheap.id)) == null or _panel.buttons["buy:%d" % int(cheap.id)].text == "구매", "buy button keeps its label", "")
	_check(await _wait_until(func(): return Economy.items().size() == bag0 + 1, 10.0), "bought item lands in the bag", "%d -> %d" % [bag0, Economy.items().size()])
	_check(Economy.gold == gold0 - 3500, "gold paid", "%d -> %d" % [gold0, Economy.gold])
	await _wait_until(func(): return _panel.listings.size() == 1, 10.0)
	await _snap()  # 4. 산 뒤

	# 판매 등록
	_panel.pick_tab("sell")
	await _frames(6)
	var mine_item: Dictionary = _panel.sellable_items()[0]
	var mid := int(mine_item.id)
	_panel.picked = mid
	_panel._rebuild()
	_panel.price_edit.text = "20000"
	_panel.price_edit.text_changed.emit("20000")
	await _frames(4)
	await _snap()  # 5. 판매 등록 폼
	var bag1 := Economy.items().size()
	_panel.buttons.list.pressed.emit()
	_check(Economy.items().size() == bag1 - 1 and Economy.item(mid).is_empty(), "listing leaves the bag at once", "")
	_check(await _wait_until(func(): return _mine_ids().size() == 1 and int(_mine_ids()[0]) > 0, 10.0), "server confirmed the listing", str(Economy.market))

	# 판매자가 사 간다
	var browse: Dictionary = await _http("GET", "/v1/market?currency=gold", null, _seller)
	var mine_listing := {}
	for l in browse.get("listings", []):
		if int(l.item.id) == mid:
			mine_listing = l
	_check(not mine_listing.is_empty(), "seller sees my listing", str(browse))
	var bought: Dictionary = await _http("POST", "/v1/market/buy", {"id": int(mine_listing.get("id", 0)), "currency": "gold", "price": 20000}, _seller)
	_check(bought.has("bought"), "seller bought it", str(bought))

	_panel.pick_tab("mine")
	_check(await _wait_until(func(): return _panel.collect_sum().gold == 18000, 10.0), "mine shows 18,000 to collect (10% fee)", str(_panel.collect_sum()))
	Net.refresh()
	_check(await _wait_until(func(): return Economy.market_sold == 1, 10.0), "menu knows a sale is ready", "")
	await _frames(6)
	await _snap()  # 6. 판매 완료
	var gold1 := Economy.gold
	_panel.buttons.collect.pressed.emit()
	_check(Economy.gold == gold1 + 18000, "collect adds gold at once", "%d -> %d" % [gold1, Economy.gold])
	_check(await _wait_until(func(): return Economy._hold == 0, 10.0), "collect confirmed", "")
	_check(Economy.gold == gold1 + 18000 and Economy.market_sold == 0, "gold stays after server answer", "%d" % Economy.gold)

	# 올렸다 내리기
	var it2: Dictionary = _panel.sellable_items()[0]
	_check(_panel.list_item(int(it2.id), "diamonds", 50), "list for diamonds", "")
	_check(await _wait_until(func(): return _mine_ids().size() == 1 and int(_mine_ids()[0]) > 0, 10.0), "listed", "")
	_panel._rebuild()
	await _frames(6)
	await _snap()  # 7. 내 판매(판매 중)
	_panel.buttons["cancel:%d" % int(_mine_ids()[0])].pressed.emit()
	_check(not Economy.item(int(it2.id)).is_empty(), "cancel returns the item at once", "")
	_check(await _wait_until(func(): return Economy._hold == 0, 10.0) and not Economy.item(int(it2.id)).is_empty(), "cancel confirmed", "")
	_sheet()
	_finish()


func _mine_ids() -> Array:
	return Economy.market.get("mine", []).filter(func(l): return str(l.status) == "active").map(func(l): return l.id)


func _finish() -> void:
	if _fails > 0:
		print("EXCHANGE ONLINE FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("EXCHANGE ONLINE PASSED")
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


## 판매자(두 번째 게스트)용 직접 요청 → 응답 JSON(실패면 {}).
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


func _sheet() -> void:
	var out := "/tmp/exchange.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var w: int = _shots[0].get_width() / 2
	var h: int = _shots[0].get_height() / 2
	var cols := 4
	var sheet := Image.create(w * cols, h * ceili(_shots.size() / float(cols)), false, Image.FORMAT_RGB8)
	for i in _shots.size():
		var img: Image = _shots[i]
		img.convert(Image.FORMAT_RGB8)
		img.save_png(out.get_basename() + "_%d.png" % (i + 1))
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
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

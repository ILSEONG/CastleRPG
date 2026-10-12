extends Node
## 운영 도구 온라인 체크 + 화면(2026-10-12): 로컬 서버(메모리 PGlite, ALLOW_TEST_HOOKS=1)에 게스트로 접속한다. 다른 게스트를 관리자로
## 만들어(/v1/test/admin) 공지·모두에게 우편·쿠폰을 만들고, 앱에서 [공지]·[우편] 빨간 점, 공지 창(열면 점이 꺼짐), 우편 [모두 받기]
## (곧바로 다이아가 오르고 서버가 확인), 쿠폰 입력(성공·이미 씀·없는 번호), 점검(503 → 화면 전체 안내, 끄면 저절로 걷힘),
## 강제 업데이트(426 → 업데이트 안내), 관리자 창(내 계정을 관리자로 — 설정 [운영 관리], 네 탭)을 본다.
## 실행: cd server && PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=8790 node src/main.ts &
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/live_ops_online.tscn -- --api=http://127.0.0.1:8790 --device=/tmp/x/device.json --out=/tmp/ops
## 마지막 줄이 LIVE OPS ONLINE PASSED(실패면 종료 코드 1). --out=<폴더>면 화면을 png로 남긴다.

const Prefs := preload("res://scripts/prefs.gd")

var _main
var _menu
var _fails := 0
var _out := ""
var _admin := ""  # 다른 게스트(관리자) 토큰
var _resp_done := false
var _code := "CASTLE%d" % (Time.get_ticks_usec() % 1000000)  # 쿠폰 번호(같은 서버로 다시 돌려도 겹치지 않게)


func _ready() -> void:
	Fever.save_path = ""
	Guild.save_path = ""
	get_window().size = Vector2i(360, 640)
	_out = Net.arg_value("out")
	var device := Net.arg_value("device")
	_check(Net.is_online() and device != "", "online mode with --api and --device", Net.api_base)
	if _fails > 0:
		return _finish()
	Net.device_path = device
	Net.auth_path = device.get_base_dir().path_join("auth.json")
	DirAccess.remove_absolute(device)
	Net.set_auth("guest")
	Prefs.set_value(LiveOps.SEEN_KEY, 0)
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_check(await _wait_until(func(): return Net.ready_once and _main.camera != null, 30.0), "world built after connecting", "")
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == "res://scripts/side_menu.gd":
			_menu = c
	_check(_menu != null and _menu.windows.has("notice") and _menu.windows.has("mail"), "menu has 공지 and 우편", "")
	if _fails > 0:
		return _finish()
	await _wait_until(func(): return preload("res://scripts/preloader.gd").done, 30.0)
	await _frames(20)
	var notice_panel = _menu.windows.notice
	notice_panel.auto_shown = true  # 자동 띄우기는 따로 본다

	# 관리자(다른 게스트)가 공지·우편·쿠폰을 만든다
	var other: Dictionary = await _raw("POST", "/v1/auth/guest", {"device_id": "ops-check-admin-%d" % Time.get_ticks_msec()}, "")
	_admin = str(other.get("token", ""))
	await _raw("POST", "/v1/test/admin", {}, _admin)
	var n1: Dictionary = await _raw("POST", "/v1/admin/notice", {"title": "10월 12일 업데이트 안내", "body": "우편함·쿠폰·공지사항이 생겼어요.\n설정 → 쿠폰 입력에서 쿠폰을 쓸 수 있어요.", "kind": "update"}, _admin)
	_check(n1.has("id"), "admin creates a notice", str(n1))
	await _raw("POST", "/v1/admin/notice", {"title": "출석 이벤트 진행 중", "body": "28일 출석 이벤트에 참여하세요!", "kind": "event", "pinned": true}, _admin)
	var m1: Dictionary = await _raw("POST", "/v1/admin/mail", {"to": "all", "title": "점검 보상", "body": "점검으로 불편을 드려 죄송합니다.", "reward": {"diamonds": 300, "gold": 50000, "tickets": 5}}, _admin)
	_check(m1.has("id"), "admin sends mail to all", str(m1))
	await _raw("POST", "/v1/admin/mail", {"to": "all", "title": "길드전 응원 선물", "body": "", "reward": {"keys_gold": 2, "equip": {"grade": "SSR", "n": 1}}}, _admin)
	var cp: Dictionary = await _raw("POST", "/v1/admin/coupon", {"code": _code, "reward": {"diamonds": 500}}, _admin)
	_check(str(cp.get("code", "")) == _code, "admin creates a coupon", str(cp))

	# 공지
	LiveOps.fetch_notices()
	_check(await _wait_until(func(): return LiveOps.notices.size() == 2, 10.0), "notices arrive", str(LiveOps.notices))
	_check(str(LiveOps.notices[0].title) == "출석 이벤트 진행 중", "pinned notice first", str(LiveOps.notices))
	_menu.set_open(true)
	await _frames(10)
	_check(_menu.dots().has("notice") and _menu.dots().has("toggle"), "unseen notice: red dot on 공지 and 메뉴", str(_menu.dots()))
	_layout_checks()
	await _snap("01_menu")
	_menu.pick("notice")
	await _frames(10)
	_check(notice_panel.is_open() and not LiveOps.has_unseen(), "공지 opens and marks seen", "")
	_check(not _menu.dots().has("notice"), "notice dot gone after opening", str(_menu.dots()))
	notice_panel.toggle(int(LiveOps.notices[1].id))
	await _snap("02_notices")
	notice_panel.close()

	# 우편: 모두 받기 — 곧바로 다이아·골드·모집권, 서버가 확인
	LiveOps.fetch_mail()
	_check(await _wait_until(func(): return LiveOps.mails.size() == 2, 10.0), "two mails arrive", str(LiveOps.mails))
	await _frames(4)
	_check(_menu.dots().has("mail"), "red dot on 우편", str(_menu.dots()))
	_menu.set_open(true)
	_menu.pick("mail")
	var mail_panel = _menu.windows.mail
	await _frames(10)
	_check(mail_panel.is_open() and mail_panel.buttons.has("claim:%d" % int(m1.id)), "mail window lists the mail", "")
	await _snap("03_mail")
	var dia0: int = Economy.diamonds
	var tk0: int = Economy.dia_tickets
	mail_panel.buttons.claim_all.pressed.emit()
	_check(LiveOps.mails.is_empty() and Economy.diamonds == dia0 + 300 and Economy.dia_tickets == tk0 + 5, "모두 받기 applies at once", "%d %d" % [Economy.diamonds, Economy.dia_tickets])
	_check(await _wait_until(func(): return LiveOps.claiming.is_empty(), 10.0), "server confirms the claim", "")
	_check(Economy.diamonds == dia0 + 300, "diamonds stay after the server reply", str(Economy.diamonds))
	await _frames(6)
	_check(not _menu.dots().has("mail"), "mail dot gone", str(_menu.dots()))
	await _snap("04_mail_claimed")
	mail_panel.close()

	# 쿠폰
	var settings = _menu.windows.settings
	settings.open()
	await _frames(6)
	_check(settings.coupon_button.visible and not settings.admin_button.visible, "settings: 쿠폰 입력 shown, 운영 관리 hidden for players", "")
	await _snap("05a_settings_player")
	settings.coupon_button.pressed.emit()
	var coupon = settings.coupon
	await _frames(6)
	_check(coupon.is_open(), "coupon window opens", "")
	coupon.input.text = _code.to_lower().insert(4, "-")
	var dia1: int = Economy.diamonds
	coupon.use()
	_check(coupon.use_button.text == "사용", "use button label never changes", coupon.use_button.text)
	_check(await _wait_until(func(): return coupon.result_label.text != "", 10.0), "coupon result shows", "")
	_check(Economy.diamonds == dia1 + 500 and coupon.result_label.text.contains("다이아 500"), "coupon gives 500 diamonds", coupon.result_label.text)
	await _snap("05_coupon_ok")
	coupon.input.text = _code
	coupon.use()
	await _wait_until(func(): return not LiveOps.redeeming, 10.0)
	_check(coupon.result_label.text == "이미 사용한 쿠폰입니다", "second use refused", coupon.result_label.text)
	coupon.input.text = "NOPE1234"
	coupon.use()
	await _wait_until(func(): return not LiveOps.redeeming, 10.0)
	_check(coupon.result_label.text == "없는 쿠폰 번호입니다", "unknown code refused", coupon.result_label.text)
	await _snap("06_coupon_bad")
	coupon.close()

	# 점검: 관리자가 켜면 다음 요청이 503 → 화면 전체 안내, 끄면 저절로 걷힌다
	var now := Economy.time_now()
	await _raw("POST", "/v1/admin/status", {"maintenance": true, "maintenance_text": "길드전 개선 점검 중이에요. 점검 보상은 우편으로 드려요.", "maintenance_until": now + 5400}, _admin)
	Net.refresh()
	_check(await _wait_until(func(): return LiveOps.overlay.visible and LiveOps.block.get("kind") == "maintenance", 10.0), "maintenance overlay shows", str(LiveOps.block))
	await _snap("07_maintenance")
	await _raw("POST", "/v1/admin/status", {"maintenance": false}, _admin)
	_check(await _wait_until(func(): return not LiveOps.overlay.visible, Net.BLOCK_RETRY_SEC + 10.0), "overlay clears after maintenance ends", "")

	# 강제 업데이트
	await _raw("POST", "/v1/admin/status", {"min_version": "9.0.0", "store_url": "https://play.google.com/store/apps/details?id=com.ilesong.castlerpg"}, _admin)
	Net.refresh()
	_check(await _wait_until(func(): return LiveOps.overlay.visible and LiveOps.block.get("kind") == "update", 10.0), "update overlay shows", str(LiveOps.block))
	_check(LiveOps.overlay.update_button.visible, "update button shown", "")
	await _snap("08_update")
	await _raw("POST", "/v1/admin/status", {"min_version": ""}, _admin)
	LiveOps.block = {}
	LiveOps.block_changed.emit()
	await get_tree().create_timer(Net.BLOCK_RETRY_SEC + 2.0, true, false, true).timeout  # 막혀 있던 요청이 다시 간다

	# 관리자 창(내 계정을 관리자로)
	await _request("/v1/test/admin", {})
	Net.refresh()
	_check(await _wait_until(func(): return Economy.admin, 10.0), "my account is admin now", "")
	settings.open()
	await _frames(6)
	_check(settings.admin_button.visible, "settings shows 운영 관리 for the admin", "")
	await _snap("09_settings")
	settings.admin_button.pressed.emit()
	var admin = settings.admin_panel
	_check(await _wait_until(func(): return admin.is_open() and not admin.ops.is_empty(), 10.0), "admin window loads ops", "")
	await _frames(6)
	await _snap("10_admin_status")
	for t in ["notice", "mail", "coupon"]:
		admin.pick(t)
		await _frames(6)
		await _snap("11_admin_" + t)
	# 관리자 창에서 쿠폰 만들기
	admin.pick("coupon")
	await _frames(2)
	admin.f.c_code.text = "ADM" + _code
	admin.f.c_diamonds.text = "100"
	admin.f.c_max.text = "10"
	admin.buttons.coupon_make.pressed.emit()
	_check(await _wait_until(func(): return admin.ops.get("coupons", []).any(func(c): return c.code == "ADM" + _code), 10.0), "coupon made in the admin window", "")
	# 관리자 창에서 모두에게 우편: 첫 누름은 확인만
	admin.pick("mail")
	await _frames(2)
	admin.f.m_title.text = "관리자 창 우편"
	admin.f.m_gold.text = "1234"
	admin.send_mail()
	_check(admin.f.m_send.text.begins_with("한 번 더"), "mail to all asks once more", admin.f.m_send.text)
	admin.send_mail()
	_check(await _wait_until(func(): return admin.ops.get("mails", []).any(func(m): return m.title == "관리자 창 우편"), 10.0), "mail sent from the admin window", "")
	admin.close()
	_finish()


func _layout_checks() -> void:
	for col: Control in [_menu._col, _menu._col2]:
		var r := col.get_global_rect()
		_check(r.size.y <= 0.0 or r.position.y >= _menu.TOP_LIMIT - 1.0, "menu column stays under the stage card", str(r))
	_check(_menu._split > 0 and _menu.buttons.settings.get_parent() == _menu._col2, "top items move to the second column", str(_menu._split))


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


func _request(path: String, body) -> void:
	_resp_done = false
	Net.send("POST", path, body, func(_d): _resp_done = true, func(): _resp_done = true)
	await _wait_until(func(): return _resp_done, 10.0)


func _finish() -> void:
	if _fails > 0:
		print("LIVE OPS ONLINE FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("LIVE OPS ONLINE PASSED")
		get_tree().quit(0)


func _check(ok: bool, what: String, detail: String) -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + detail))
	if not ok:
		_fails += 1


func _snap(name: String) -> void:
	await _frames(8)
	if _out == "":
		return
	DirAccess.make_dir_recursive_absolute(_out)
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))


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

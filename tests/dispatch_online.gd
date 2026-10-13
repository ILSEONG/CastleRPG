extends Node
## 파견소·황금 고블린 온라인 체크 + 화면(개발용): 로컬 서버(메모리 PGlite, ALLOW_TEST_HOOKS=1)에 게스트로 접속한다.
## 1) 황금 고블린을 잡으면 서버가 보상(방치 골드 15분 몫)을 주고, 곧바로 또 잡으면(4분 30초 안) 되돌린다.
## 2) 파견소(테스트 훅으로 Lv 5) 창: 의뢰 4개 → [보내기] → 영웅 고르기([자동 선택]) → 보내기 → 진행 중 → (훅으로 끝냄) [받기] → 보상,
##    [새로고침](무료) → 시작 안 한 의뢰가 바뀐다, [모두 보내기].
## 실행: cd server && PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=8790 node src/main.ts &
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/dispatch_online.tscn -- --api=http://127.0.0.1:8790 --device=/tmp/x/device.json --out=/tmp/dispatch
## 마지막 줄이 DISPATCH ONLINE PASSED(실패면 종료 코드 1).

const DamageNumbers := preload("res://scripts/damage_numbers.gd")

var _main
var _panel
var _dir
var _fails := 0
var _resp_done := false
var _out := "/tmp/dispatch"


func _ready() -> void:
	Fever.save_path = ""
	Guild.save_path = ""
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
	for c in _main.get_children():
		var p: String = c.get_script().resource_path if c.get_script() != null else ""
		if p == "res://scripts/dispatch_panel.gd":
			_panel = c
		elif p == "res://scripts/goblin_director.gd":
			_dir = c
	_check(_panel != null and _dir != null, "dispatch window + goblin director exist", "")
	if _fails > 0:
		return _finish()

	# 1) 황금 고블린(온라인)
	await _frames(20)
	var got := [{}]
	Economy.goblin_claimed.connect(func(d): got[0] = d)
	var g = _dir.spawn()
	await _frames(5)
	var gold := Economy.gold_tenths
	g.take_damage(g.hp + 1.0, DamageNumbers.Kind.HIT)
	_check(Economy.gold_tenths >= gold + 54_000, "goblin gold shows at once (predicted)", "%d -> %d" % [gold, Economy.gold_tenths])
	_check(await _wait_until(func(): return not got[0].is_empty(), 10.0), "server answered the goblin claim", "")
	_check(int(got[0].get("gold_tenths", 0)) == 54_000 and int(got[0].get("n", 0)) == 1, "server gave 15 min of idle gold", str(got[0]))
	var g2 = _dir.spawn()
	await _frames(5)
	got[0] = {}
	var before := Economy.gold_tenths
	g2.take_damage(g2.hp + 1.0, DamageNumbers.Kind.HIT)
	await _wait_until(func(): return Economy.gold_tenths < before + 1000, 10.0)
	await _frames(10)
	_check(got[0].is_empty() and Economy.gold_tenths < before + 54_000, "second goblin within 4:30 is refused and rolled back", "%d -> %d" % [before, Economy.gold_tenths])

	# 2) 파견소
	_panel.open()
	_check(await _wait_until(func(): return not _panel.loading, 10.0) and _panel.failed == "no_building", "without the building: no_building", _panel.failed)
	await _snap("0_no_building")
	_panel.close()
	await _request("/v1/test/dispatch", {"level": 5})
	await _request("/v1/test/levels", {"levels": {"keep": 6}})
	for h in ["bron", "mira", "torvin", "rian", "echo", "gork", "felix", "hans", "ella", "dorik", "nina", "jack", "arteon", "ignis", "sylvana", "lumina"]:
		await _request("/v1/test/grant_hero", {"hero_id": h})
	await _request("/v1/test/levels", {"levels": {}})
	_panel.open()
	_check(await _loaded(), "dispatch list loads", _panel.failed)
	_check(_panel.list().size() == 4 and _panel.level() == 5, "Lv 5 → 4 requests", "%d / Lv %d" % [_panel.list().size(), _panel.level()])
	await _snap("1_list")
	# 보낼 수 있는 의뢰 하나 고르기
	var target := -1
	for j in _panel.list():
		if _panel.auto_pick(j, {}).size() == int(j.size):
			target = int(j.id)
			break
	_check(target > 0, "some request can be filled by owned heroes", str(_panel.list()))
	if target < 0:
		return _finish()
	var bp = _panel.get_parent().get_children().filter(func(c): return c.get_script() != null and c.get_script().resource_path == "res://scripts/building_panel.gd")[0]
	_panel.close()
	bp.open_building("dispatch")
	await _frames(10)
	_check(bp.dispatch_button.visible, "building window shows [의뢰 보기]", "")
	await _snap("1b_building")
	bp.dispatch_button.pressed.emit()
	_check(await _loaded() and _panel.is_open(), "[의뢰 보기] opens the dispatch window", "")
	_panel.buttons["send:%d" % target].pressed.emit()
	await _frames(6)
	_check(_panel.picking == target and _panel.buttons.has("go"), "picker opens", "")
	_panel.buttons.auto.pressed.emit()
	await _frames(6)
	await _snap("2_pick")
	_check(not _panel.buttons.go.disabled, "auto pick fills the party", str(_panel.chosen))
	_panel.buttons.go.pressed.emit()
	_check(_panel.is_started(_panel.job(target)), "started at once (optimistic)", "")
	_check(await _wait_until(func(): return Economy.dispatch_finishes.size() == 1, 10.0), "server confirmed (player.dispatch has one finish time)", str(Economy.dispatch_finishes))
	await _frames(10)
	await _snap("3_running")
	await _request("/v1/test/dispatch", {"done": true})
	_panel.fetch()
	_check(await _loaded(), "reload after finishing", "")
	_check(_panel.buttons.has("claim:%d" % target), "[받기] shows", str(_panel.buttons.keys()))
	await _snap("4_done")
	var job: Dictionary = _panel.job(target)
	var dia := Economy.diamonds
	var pouches := Economy.pouches.duplicate()
	var sp := Economy.speedups.duplicate()
	var keys_before := Economy.items().size()
	_panel.buttons["claim:%d" % target].pressed.emit()
	await _wait_until(func(): return _panel.job(target).is_empty(), 10.0)
	await _frames(30)
	var r: Dictionary = job.get("reward", {})
	var ok := true
	if r.has("diamonds"):
		ok = Economy.diamonds == dia + int(r.diamonds)
	for k in r:
		if str(k).begins_with("pouch_"):
			ok = ok and Economy.pouch_count(str(k).substr(6)) == int(pouches.get(str(k).substr(6), 0)) + int(r[k])
		if str(k).begins_with("speedup_"):
			ok = ok and int(Economy.speedups.get(str(k).substr(8), 0)) == int(sp.get(str(k).substr(8), 0)) + int(r[k])
	_check(_panel.job(target).is_empty() and ok, "claimed: request removed, reward " + str(r), "dia %d→%d" % [dia, Economy.diamonds])
	# 새로고침(무료)
	var ids_before: Array = _panel.list().filter(func(j): return not _panel.is_started(j)).map(func(j): return int(j.id))
	_panel.buttons.refresh.pressed.emit()
	_check(await _wait_until(func(): return not _panel.list().is_empty() and int(_panel.list()[0].id) not in ids_before, 10.0), "free refresh rerolls open requests", str(ids_before))
	await _frames(10)
	await _snap("5_refreshed")
	_check(_panel.buttons.refresh.text.contains("💎"), "next refresh costs diamonds", _panel.buttons.refresh.text)
	_panel.buttons.send_all.pressed.emit()
	await _frames(20)
	await _snap("6_send_all")
	_finish()


func _loaded() -> bool:
	var ok: bool = await _wait_until(func(): return not _panel.loading and not _panel.data.is_empty(), 10.0)
	await _frames(6)
	return ok


func _request(path: String, body) -> void:
	_resp_done = false
	Net.send("POST", path, body, func(d):
		Economy.apply_server(d)
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
	print("DISPATCH ONLINE PASSED" if _fails == 0 else "DISPATCH ONLINE FAILED %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

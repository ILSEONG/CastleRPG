extends Node
## 첫 접속 실패 안내(사용자 2026-10-23 첫 30분 점검): 서버가 안 닿으면 로딩 화면이 "서버에 연결하는 중…"에 멈춘 듯 보였다.
## 이제 연결 실패가 이어지면 "서버에 연결할 수 없습니다 / 인터넷 연결을 확인해 주세요" + [다시 연결]이 보이고, 누르면 백오프를 기다리지 않고 곧바로 다시 붙는다.
## 실행: 서버를 띄우지 않은 포트로 시작 → 이 장면이 15초 기다리는 동안 바깥에서 그 포트에 서버를 띄운다(dev 스크립트 없이 손으로):
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/connect_retry_online.tscn -- --api=http://127.0.0.1:8899 --device=/tmp/cr/device.json --out=/tmp/cr &
##   sleep 12; (cd server && env -u DATABASE_URL PGLITE_DIR=memory PORT=8899 node src/main.ts &)
## 마지막 줄 CONNECT RETRY PASSED(실패면 종료 코드 1).

const Preloader := preload("res://scripts/preloader.gd")

var _fails := 0


func _ready() -> void:
	var device := Net.arg_value("device")
	var out := Net.arg_value("out")
	DirAccess.make_dir_recursive_absolute(device.get_base_dir())
	DirAccess.remove_absolute(device)
	Net.device_path = device
	Net.auth_path = device.get_base_dir().path_join("auth.json")
	Net.set_auth("guest")
	Tutorial.go_online()
	add_child(load("res://scenes/main.tscn").instantiate())
	await _wait_until(func():
		var p = _find_pre()
		return p != null and p.retry_button != null and p.retry_button.visible, 12.0)
	var pre: Node = _find_pre()  # 람다는 바깥 변수에 대입할 수 없다
	_check(pre != null and pre.retry_button.visible and pre.label.text == Preloader.OFFLINE_TEXT and Net.first_connect_failing(),
		"with no server the loading screen says to check the internet and shows [다시 연결]", pre.label.text if pre != null else "no preloader")
	_save(out, "offline")
	await _wait_until(func(): return _port_open(), 30.0)  # 바깥에서 서버를 띄운다
	await get_tree().create_timer(1.0).timeout
	var t0 := Time.get_ticks_msec()
	var sent: bool = Net.retry_now()
	if not sent:  # 마침 요청이 나가 있는 중이면 끝날 때까지 기다렸다가 누른다
		await _wait_until(func(): return Net.retry_now() or Net.up, 10.0)
	var ok := await _wait_until(func(): return Net.up, 6.0)
	_check(ok and Time.get_ticks_msec() - t0 < 6000, "[다시 연결] reaches the server at once (no backoff wait)", "up=%s after %d ms" % [Net.up, Time.get_ticks_msec() - t0])
	await _wait_until(func(): return pre == null or not is_instance_valid(pre) or not pre.retry_button.visible, 5.0)
	_check(not is_instance_valid(pre) or (not pre.retry_button.visible and pre.label.text != Preloader.OFFLINE_TEXT), "the notice and button go away once connected", "")
	var ready := await _wait_until(func(): return Net.ready_once, 30.0)
	_check(ready, "the game finishes connecting (gamedata + player)", "")
	_save(out, "online")
	print("CONNECT RETRY PASSED" if _fails == 0 else "CONNECT RETRY FAILED %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _port_open() -> bool:
	var t := StreamPeerTCP.new()
	var u := Net.api_base.trim_prefix("http://")
	if t.connect_to_host(u.get_slice(":", 0), int(u.get_slice(":", 1))) != OK:
		return false
	for i in 20:
		t.poll()
		if t.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			t.disconnect_from_host()
			return true
		if t.get_status() == StreamPeerTCP.STATUS_ERROR:
			return false
		OS.delay_msec(10)
	return false


func _find_pre() -> Node:
	for n in get_tree().get_nodes_in_group(Preloader.GROUP):
		return n
	return null


func _save(dir: String, name_s: String) -> void:
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name_s])


func _check(cond: bool, what: String, detail: String) -> void:
	print(("RETRY PASS: " if cond else "RETRY FAIL: ") + what + ("" if cond else " — " + detail))
	if not cond:
		_fails += 1


func _wait_until(cond: Callable, timeout_sec: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while not cond.call():
		if Time.get_ticks_msec() > end:
			return false
		await get_tree().process_frame
	return true

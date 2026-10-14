extends Node
## 푸시 알림 체크(2026-10-12): Notify.plan(언제·무엇을 예약하나 — 건설·훈련·연구·방치·출석·공성전, 켬/끔, 야간 미루기)과
## 가짜 안드로이드 플러그인으로 백그라운드 예약·복귀 취소, 설정 창 [알림] 칸 토글을 본다. 기기 설정 파일은 건드리지 않는다.
## 실행: godot --headless --path . res://tests/notify_check.tscn

const NotifyScript := preload("res://scripts/notify.gd")
const SettingsPanel := preload("res://scripts/settings_panel.gd")
const TMP := "user://notify_check.json"
const KST := 9 * 3600

var _fails := 0


class FakePlugin extends RefCounted:
	var calls: Array = []
	var allowed := true

	func has_permission() -> bool:
		return allowed

	func request_permission() -> void:
		calls.append(["request"])

	func open_settings() -> void:
		calls.append(["settings"])

	func schedule(id: int, title: String, body: String, delay: int) -> void:
		calls.append(["schedule", id, title, body, delay])

	func cancel_all() -> void:
		calls.append(["cancel"])

	func clear_shown() -> void:
		calls.append(["clear"])


func _ready() -> void:
	Economy.save_path = ""
	Music.settings_path = TMP
	Music.prefs = {}
	_plan_checks()
	await _plugin_checks()
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	if _fails > 0:
		print("NOTIFY FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("NOTIFY ALL PASSED")
		get_tree().quit(0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: " + what)


## 한국 시각 (그날 h시 m분) — 2026-10-12(월) 기준.
static func kst(h: float, day_offset := 0) -> float:
	var base := 1791763200.0  # 2026-10-12 00:00 UTC
	return base - KST + (day_offset * 24 + h) * 3600.0


static func by_id(list: Array) -> Dictionary:
	var d := {}
	for n in list:
		d[int(n.id)] = n
	return d


func _all_on() -> Dictionary:
	var o := {}
	for k in NotifyScript.KEYS:
		o[k] = k != "notify_night"
	return o


func _plan_checks() -> void:
	var now := kst(10.0)  # 오전 10시
	var state := {"ready": true, "build": {"id": "keep", "finish": now + 600.0}, "research": {"id": "wood_tech", "finish": now + 3600.0},
		"train": {"barracks": {"count": 30, "finish": now + 120.0}, "archery": {"count": 5, "finish": now + 7200.0}},
		"cap_min": 720.0, "attend_open": true, "war_at": kst(21.0)}
	var p := by_id(NotifyScript.plan(state, now, _all_on()))
	_check(p.has(NotifyScript.ID_BUILD) and is_equal_approx(p[NotifyScript.ID_BUILD].at, now + 600.0), "build at finish")
	_check(str(p.get(NotifyScript.ID_BUILD, {}).get("body", "")).contains("성채"), "build names the building")
	_check(str(p.get(NotifyScript.ID_RESEARCH, {}).get("body", "")).contains("벌목술"), "research names the node")
	_check(p.has(NotifyScript.ID_TRAIN) and p.has(NotifyScript.ID_TRAIN + 1), "one per training queue")
	var bodies := str(p.get(NotifyScript.ID_TRAIN, {}).get("body", "")) + str(p.get(NotifyScript.ID_TRAIN + 1, {}).get("body", ""))
	_check(bodies.contains("보병 30마리") and bodies.contains("궁병 5마리"), "training says soldier + count: " + bodies)
	_check(is_equal_approx(p.get(NotifyScript.ID_IDLE, {}).get("at", 0.0), kst(8.0, 1)), "idle full at 22:00 → next 08:00 (night)")
	_check(is_equal_approx(p.get(NotifyScript.ID_DAILY, {}).get("at", 0.0), kst(12.0)), "attendance open → today 12:00")
	_check(is_equal_approx(p.get(NotifyScript.ID_WAR, {}).get("at", 0.0), kst(21.0) - 600.0), "war 10 min before schedule")

	# 출석을 이미 받았으면 내일 12시
	state.attend_open = false
	p = by_id(NotifyScript.plan(state, now, _all_on()))
	_check(is_equal_approx(p[NotifyScript.ID_DAILY].at, kst(12.0, 1)), "attendance claimed → tomorrow 12:00")

	# 야간: 밤 9시에 내리면 12시간 뒤(아침 9시)는 그대로, 30분 뒤 끝나는 건설(21:30)도 그대로, 23시 끝나는 연구는 다음 날 8시로
	now = kst(21.0)
	state.build = {"id": "keep", "finish": now + 1800.0}
	state.research = {"id": "wood_tech", "finish": kst(23.0)}
	state.train = {}
	state.war_at = kst(23.5)
	p = by_id(NotifyScript.plan(state, now, _all_on()))
	_check(is_equal_approx(p[NotifyScript.ID_BUILD].at, kst(21.5)), "21:30 not quiet")
	_check(is_equal_approx(p[NotifyScript.ID_RESEARCH].at, kst(8.0, 1)), "23:00 → next 08:00")
	_check(is_equal_approx(p[NotifyScript.ID_IDLE].at, kst(9.0, 1)), "idle 09:00 kept")
	_check(is_equal_approx(p[NotifyScript.ID_WAR].at, kst(23.5) - 600.0), "war in quiet hours still 10 min before")
	_check(not p.has(NotifyScript.ID_TRAIN), "no queue → no training notice")
	# 새벽 3시 → 8시
	_check(is_equal_approx(NotifyScript.after_quiet(kst(3.0, 1)), kst(8.0, 1)), "03:00 → 08:00 same day")
	# 야간 알림 켬이면 그대로
	var o := _all_on()
	o.notify_night = true
	p = by_id(NotifyScript.plan(state, now, o))
	_check(is_equal_approx(p[NotifyScript.ID_RESEARCH].at, kst(23.0)), "night on → 23:00 kept")
	_check(p.has(NotifyScript.ID_WAR), "night on → war kept")

	# 끔
	o = _all_on()
	o.notify_timer = false
	p = by_id(NotifyScript.plan(state, now, o))
	_check(not p.has(NotifyScript.ID_BUILD) and not p.has(NotifyScript.ID_RESEARCH) and p.has(NotifyScript.ID_IDLE), "timer off")
	o = _all_on()
	o.notify_idle = false
	o.notify_daily = false
	_check(by_id(NotifyScript.plan(state, now, o)).keys().size() == 3, "idle + daily off → build + research + war only")
	o = _all_on()
	o.notify = false
	_check(NotifyScript.plan(state, now, o).is_empty(), "master off → nothing")
	state.ready = false
	_check(NotifyScript.plan(state, now, _all_on()).is_empty(), "not loaded → nothing")
	# 이미 끝난 타이머는 건너뛴다
	state.ready = true
	state.build = {"id": "keep", "finish": now - 10.0}
	_check(not by_id(NotifyScript.plan(state, now, _all_on())).has(NotifyScript.ID_BUILD), "finished build skipped")


func _plugin_checks() -> void:
	var fake := FakePlugin.new()
	Notify.plugin = fake
	Economy.reset(Time.get_unix_time_from_system())
	Economy.build = {"id": "keep", "finish": Economy.time_now() + 300.0}
	Notify.notification(NOTIFICATION_APPLICATION_PAUSED)
	var sched := fake.calls.filter(func(c): return c[0] == "schedule")
	_check(fake.calls.size() > 0 and fake.calls[0][0] == "cancel", "pause cancels old first")
	_check(sched.any(func(c): return c[1] == NotifyScript.ID_BUILD and absi(c[4] - 300) <= 2), "pause schedules build in ~300 s")
	fake.calls.clear()
	Notify.notification(NOTIFICATION_APPLICATION_RESUMED)
	_check(fake.calls.has(["cancel"]) and fake.calls.has(["clear"]), "resume cancels + clears")

	# 설정 창 [알림] 칸
	var panel = SettingsPanel.new()
	add_child(panel)
	await get_tree().process_frame
	_check(panel.notify_rows != null, "settings shows notify section when supported")
	if panel.notify_rows != null:
		var rows: Dictionary = panel.notify_rows.toggles
		_check(rows.size() == 6, "6 toggles")
		_check(rows.notify.button_pressed and not rows.notify_night.button_pressed, "defaults: on, night off")
		rows.notify_idle.button_pressed = false
		_check(not Notify.enabled("notify_idle") and Music.prefs.get("notify_idle", true) == false, "idle toggle saved")
		rows.notify.button_pressed = false
		_check(rows.notify_timer.disabled, "master off disables the rest")
		fake.allowed = false
		Music.prefs["notify_asked"] = true
		fake.calls.clear()
		rows.notify.button_pressed = true
		_check(fake.calls.has(["settings"]), "turning on while blocked opens system settings")
		_check(panel.notify_rows.section.text.contains("꺼져"), "section says blocked")
	panel.queue_free()
	Notify.plugin = null
	var panel2 = SettingsPanel.new()
	add_child(panel2)
	await get_tree().process_frame
	_check(panel2.notify_rows == null, "no plugin → no section")
	panel2.queue_free()

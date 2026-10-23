extends Node
## 새 성주 첫 30분 흐름(개발용, 사용자 2026-10-23 "실제 폰으로 처음 30분 해 보기"): 새 게스트로 로컬 서버에 접속해 실제 시간으로
## 가이드를 따라간다. 테스트 훅(골드·자원·스테이지 넣기)은 쓰지 않는다 — 처치 골드·건설 시간·전투는 실제 게임이 그대로 흐른다.
## 사람처럼: 미션마다 [바로가기]를 누르고, 할 수 있을 때 버튼과 같은 함수로 목표를 채우고, 끝나면 [보상 받기]. 포커스 설명은 한 칸에 2.5초씩 읽고 넘긴다.
## 미션마다 걸린 시간과 무엇을 기다렸는지(골드 부족·건설 대기·전투 중 등)를 적고, 끝에 표(--out=…md)와 프레임 시간을 남긴다.
## 실행: cd server && env -u DATABASE_URL PGLITE_DIR=memory PORT=8810 node src/main.ts &
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/first30_pace.tscn -- --api=http://127.0.0.1:8810 --device=/tmp/f30/device.json --out=/tmp/f30/pace.md --minutes=30

const MainScript := preload("res://scripts/main.gd")
const PlacementScript := preload("res://scripts/placement.gd")
const CardScript := preload("res://scripts/tutorial_card.gd")
const UiWindowScript := preload("res://scripts/ui_window.gd")
const GameData := preload("res://scripts/game_data.gd")
const Preloader := preload("res://scripts/preloader.gd")

const ACT_GAP := 3.0  # 사람이 한 동작 하는 데 쓰는 초(창 열기·누르기)
const TOUR_STEP_SEC := 2.5

var _main
var _t0 := 0  # 접속 시작(ms)
var _rows: Array = []  # [번호, id, 시작 초, 끝 초, {기다린 이유: 초}]
var _cur := -1
var _wait := {}
var _start_s := 0.0
var _tour_steps := 0
var _tour_sec := 0.0
var _fails := 0
var _clears := 0
var _frame_ms: Array = []
var _notes: Array = []
var _load_ms := 0
var _fever_asks := 0


func _ready() -> void:
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Missions.save_path = ""
	Pvp.save_path = ""
	var device := Net.arg_value("device")
	DirAccess.make_dir_recursive_absolute(device.get_base_dir())
	Net.device_path = device
	Net.auth_path = device.get_base_dir().path_join("auth.json")
	DirAccess.remove_absolute(device)
	Net.set_auth("guest")
	Tutorial.go_online()
	_t0 = Time.get_ticks_msec()
	add_child(preload("res://scenes/main.tscn").instantiate())
	var ok := await _wait_until(func():
		var m = _current_main()
		return Net.ready_once and m != null and m.camera != null and m._picker != null, 60.0)
	_load_ms = Time.get_ticks_msec() - _t0
	if not ok:
		print("PACE world not built")
		get_tree().quit(1)
		return
	_main = _current_main()
	Tutorial.tours_on = true  # 실제 게임처럼 포커스 설명을 띄운다(봇이 읽고 넘긴다)
	Economy.notice.connect(func(s): _notes.append(s))
	GameState.stage_failed.connect(func(_s): _fails += 1)
	GameState.stage_cleared.connect(func(_s): _clears += 1)
	await _wait_until(func(): return not Tutorial.mission().is_empty(), 20.0)
	var minutes := float(Net.arg_value("minutes")) if Net.arg_value("minutes") != "" else 30.0
	var limit_ms := int(minutes * 60000.0)
	while Time.get_ticks_msec() - _t0 < limit_ms and Tutorial.active():
		await _tick()
	_close_row()
	_report(minutes)
	get_tree().quit()


func _process(delta: float) -> void:
	if _t0 > 0:
		_frame_ms.append(delta * 1000.0)


func _now_s() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0


func _tick() -> void:
	_main = _current_main()
	if is_instance_valid(Tutorial.tour_node):  # 포커스 설명: 읽고 넘긴다
		await _real_wait(TOUR_STEP_SEC)
		_tour_sec += TOUR_STEP_SEC
		if is_instance_valid(Tutorial.tour_node):
			_tour_steps += 1
			Tutorial.tour_node.next()
		return
	if _main == null or _main._dungeon != null:
		await _real_wait(1.0)
		return
	var i := Tutorial.step
	var m: Dictionary = Tutorial.mission()
	if i != _cur:
		_close_row()
		_cur = i
		_wait = {}
		_start_s = _now_s()
		await _goto(m)
	if Tutorial.complete():
		await _real_wait(1.5)
		await _close_all()
		var card = _child(CardScript)
		if card != null and card.action_button.visible and card.action_button.text == "보상 받기":
			card.action_button.pressed.emit()
			await _real_wait(1.0)
		return
	var why: String = await _try(m)
	if why != "" and int(_now_s()) % 60 == 0:
		print("PACE WAIT %d %s: %s" % [i + 1, str(m.id), why])
	var t := _now_s()
	await _real_wait(1.0)
	if why != "":
		_wait[why] = float(_wait.get(why, 0.0)) + (_now_s() - t)


func _close_row() -> void:
	if _cur < 0:
		return
	var m: Dictionary = Tutorial.MISSIONS[_cur] if _cur < Tutorial.MISSIONS.size() else {}
	_rows.append([_cur + 1, str(m.get("id", "?")), _start_s, _now_s(), _wait.duplicate()])
	print("PACE ROW %d %s %.0f-%.0f %s" % [_cur + 1, str(m.get("id", "?")), _start_s, _now_s(), str(_wait)])
	_cur = -1


## 카드 [바로가기]를 누른다(전투 시작은 _try가 한다).
func _goto(m: Dictionary) -> void:
	var g: String = Tutorial.goto_of(m)
	if g == "" or g == "stage" or g == "siege_practice":
		return
	await _real_wait(ACT_GAP)
	var card = _child(CardScript)
	if card != null and card.action_button.visible:
		card.action_button.pressed.emit()
	await _frames(10)


## 목표를 채운다. 할 수 없으면 기다리는 이유를 돌려준다("" = 했거나 기다릴 것 없음).
func _try(m: Dictionary) -> String:
	var now := Economy.time_now()
	match str(m.kind):
		"open":
			if str(m.arg) == "keep":
				_main._picker.building_panel.open_building("keep")
			else:
				_main._tutorial_ui.side_menu.pick(str(m.arg))
			return ""
		"build", "level":
			var id := str(m.arg) if str(m.kind) == "build" else str(m.arg[0])
			if Economy.is_building(id):
				if Economy.free_build_due(now, id):
					Economy.free_finish_build(id)
					return ""
				return "건설 대기"
			var placement = _child(PlacementScript)
			var why := Economy.upgrade_block(id, now)
			if why == "not_enough":
				if placement != null and placement.is_active():
					placement.cancel()
				return "자원 부족"
			if why != "":
				return "건설 불가(%s)" % why
			if str(m.kind) == "build" and Economy.unbuilt.has(id):
				if placement != null and not placement.is_active():
					placement.start(id)
					await _frames(3)
				if placement != null and placement.is_active():
					placement.confirm()
			else:
				Economy.upgrade(id, now)
			return ""
		"kill":
			return "처치 대기"
		"collect":
			return "" if Economy.collect("lumber", now) > 0 else "수집할 자원 대기"
		"sell":
			for r in ["wood", "stone", "food"]:
				if int(Economy.res.get(r, 0)) > 0:
					Economy.sell(r, now, mini(50, int(Economy.res.get(r, 0))))
					return ""
			return "팔 자원 없음"
		"attend":
			var ev = _main._tutorial_ui.side_menu.windows.get("event")
			if ev != null and ev.is_open() and ev.can_claim():
				ev.claim()
				return ""
			if ev != null and not ev.is_open():
				_main._tutorial_ui.side_menu.pick("event")
			return "출석 창 대기"
		"pouch":
			for pid in Economy.pouches.keys():
				if Economy.pouch_count(pid) > 0:
					Economy.open_pouch(pid, 1, GameState.stage)
					return ""
			return "주머니 없음"
		"stage":
			if GameState.mode == GameState.Mode.IDLE:
				await _close_all()
				_main._hud.request_stage()
				if _main._hud.fever_confirm.visible:  # FEVER 중이면 끊을지 묻는다 — 사람은 [예]
					_fever_asks += 1
					await _real_wait(ACT_GAP)
					_main._hud._on_fever_confirm(true)
				return ""
			return "전투 중"
		"auto_on":
			var n = _target("hud:auto")
			if n is BaseButton and n.toggle_mode:
				n.button_pressed = true
			elif n != null:
				n.pressed.emit()
			return ""
		"speed_on":
			var n = _target("hud:speed")
			if n != null and not Tutorial._speed_on():
				n.pressed.emit()
			return ""
		"hero_level":
			var h := str(GameData.config_list("starter_heroes")[0])
			if Economy.levelup_block(h, 1) != "":
				return "골드 부족"
			Economy.level_up(h, 1)
			return ""
		"hero_lv":
			var need := int(m.arg[0])
			var lv := int(m.arg[1])
			var ids: Array = Economy.heroes.keys()
			ids.sort_custom(func(a, b): return Economy.level_of(a) > Economy.level_of(b))
			for h in ids.slice(0, need):
				if Economy.level_of(h) < lv:
					if Economy.levelup_block(h, 1) != "":
						return "골드 부족"
					Economy.level_up(h, 1)
					return ""
			return ""
		"mission_claim":
			for mm in Missions.list("daily"):
				if Missions.can_claim(mm):
					Missions.claim(str(mm.id))
					return ""
			Missions.fetch()
			return "일일 미션 대기"
		"growth", "growth_lv":
			var sid := "atk" if str(m.kind) == "growth" else str(m.arg[0])
			if Economy.gold < GameData.upgrade_cost(sid, int(Economy.upgrades.get(sid, 0))):
				return "골드 부족"
			Economy.growth_up(sid, 1)
			return ""
		"gacha":
			Economy.gacha(10, GameData.GACHA_TICKET)
			return "모집 대기"
		"deploy_new":
			var starters: Array = GameData.config_list("starter_heroes").map(func(x): return str(x))
			for h in Economy.heroes:
				if not str(h) in starters:
					var d: Array = Economy.deploy.duplicate()
					d[0] = str(h)
					Economy.set_deploy(d)
					return ""
			return "새 영웅 없음"
		"auto_deploy":
			var hp = _main._tutorial_ui.tabs.windows.get("hero")
			if not hp.is_open():
				_main._tutorial_ui.tabs.press("hero")
				await _frames(5)
			hp.auto_deploy()
			hp.apply()
			return ""
		"shop_free":
			Economy.buy_shop("d_free")
			return ""
		"train":
			if Economy.train_block("barracks", 1) != "":
				return "훈련 불가(%s)" % Economy.train_block("barracks", 1)
			Economy.start_training("barracks", 1)
			return ""
		"soldier_deploy":
			if Economy.training("barracks").ready:
				Economy.collect_training("barracks")
				return ""
			if Economy.training("barracks").count > 0:
				return "훈련 대기"
			Economy.set_soldier_deploy(Economy.auto_deploy())
			return ""
		"dungeon":
			var type := str(m.arg)
			var party: Array = Economy.default_party(type)
			var helper = null
			if type == "ticket":  # 던전 창 편성처럼 첫 도우미 후보를 고른다(창을 열면 GET /v1/dungeon으로 후보를 받는다)
				var dg = _main._tutorial_ui.tabs.windows.get("dungeon")
				if dg != null and not dg.is_open():
					_main._tutorial_ui.tabs.press("dungeon")
				await _real_wait(2.0)
				var hs: Array = Economy.helper_candidates()
				if hs.is_empty():
					return "도우미 후보 없음"
				helper = str(hs[0].get("key", hs[0].get("hero_id", "")))
				party = Economy.default_party("gold").filter(func(x): return x != helper).slice(0, GameData.party_size(type))
				await _close_all()
			if Economy.dungeon_block(type, 1, party, helper) != "":
				return "던전 불가(%s)" % Economy.dungeon_block(type, 1, party, helper)
			Economy.start_dungeon(type, 1, party, "" if helper == null else helper)
			await _wait_until(func(): return _main._dungeon != null, 15.0)
			var t := _now_s()
			await _wait_until(func(): return int(Economy.dungeon_state(type).best_level) >= 1 or _main._dungeon == null, 240.0)
			await _real_wait(3.0)
			if _main._dungeon != null:
				_main.leave_dungeon()
			_wait["던전 전투"] = float(_wait.get("던전 전투", 0.0)) + (_now_s() - t)
			return ""
		"equip":
			for it in Economy.items():
				for h in Economy.deploy:
					if h is String and Economy.equip_block(h, str(it.slot), int(it.id)) == "":
						Economy.equip(h, str(it.slot), int(it.id))
						return ""
			return "장비 없음"
		"research":
			var b := Economy.research_block(Tutorial.RESEARCH_ID)
			if b != "":
				return "연구 불가(%s)" % b
			Economy.start_research(Tutorial.RESEARCH_ID)
			return ""
	return "봇 미지원(%s)" % m.kind


func _report(minutes: float) -> void:
	var lines := ["# 새 성주 첫 %d분 흐름(봇, 실제 시간)" % int(minutes), "",
		"- 접속~성 화면: %.1f초, 로딩 화면 %s" % [_load_ms / 1000.0, str(Preloader.timing)],
		"- 끝낸 가이드 미션: %d개 (지금 %d번 %s)" % [Tutorial.step, Tutorial.step + 1, str(Tutorial.mission().get("id", "-"))],
		"- 스테이지 라운드 클리어 %d번, 실패 %d번, FEVER 중 [진행] 확인 %d번" % [_clears, _fails, _fever_asks],
		"- 포커스 설명: %d칸, 읽는 데 %.0f초" % [_tour_steps, _tour_sec],
		"- 프레임: %s" % _frame_text(),
		"- 알림: %s" % str(_notes.slice(-8)), "",
		"| # | 미션 | 시작 | 걸린 초 | 기다린 것 |", "|---|---|---|---|---|"]
	for r in _rows:
		var w: Array = []
		for k in r[4]:
			if float(r[4][k]) >= 1.0:
				w.append("%s %.0f초" % [k, float(r[4][k])])
		lines.append("| %d | %s | %s | %.0f | %s |" % [r[0], r[1], _clock(r[2]), float(r[3]) - float(r[2]), ", ".join(w)])
	var text := "\n".join(lines)
	print(text)
	var out := Net.arg_value("out")
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(text + "\n")


func _frame_text() -> String:
	if _frame_ms.is_empty():
		return "-"
	var s: Array = _frame_ms.duplicate()
	s.sort()
	var sum := 0.0
	for v in s:
		sum += v
	return "평균 %.1f ms, 95%% %.1f ms (프레임 %d)" % [sum / s.size(), s[int(s.size() * 0.95)], s.size()]


func _clock(sec: float) -> String:
	return "%d:%02d" % [int(sec) / 60, int(sec) % 60]


func _target(key: String):
	var t = Tutorial.ui_targets.get(key)
	return t.node if t != null and is_instance_valid(t.node) else null


func _close_all() -> void:
	var placement = _child(PlacementScript)
	if placement != null and placement.is_active():
		placement.cancel()
	for w in get_tree().get_nodes_in_group(UiWindowScript.GROUP):
		if w.is_open():
			w.close()
	if _main._picker.building_panel.visible:
		_main._picker.building_panel.close()
	await _frames(3)


func _current_main():
	for c in get_children():
		if c.get_script() == MainScript and not c.is_queued_for_deletion():
			return c
	return _main if is_instance_valid(_main) and not _main.is_queued_for_deletion() else null


func _child(script):
	if _main == null:
		return null
	for c in _main.get_children():
		if c.get_script() == script:
			return c
	return null


func _real_wait(sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


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

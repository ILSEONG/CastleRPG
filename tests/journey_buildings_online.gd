extends Node
## 통합 테스트(2026-10-14) — 건물·연구 여정(온라인): 로컬 서버(메모리 PGlite, ALLOW_TEST_HOOKS=1, tutorial_new_players=1 기본값)에 새 게스트로 접속해
## 가이드 공터 첫 건설 → 업그레이드(자동 수집)·선행 조건(✗ 줄 → 그 건물 창)·성채 상한·일꾼·두 번째 일꾼·가속·무료 완료·수집(n번째 채 "lumber#2")
## → 성채 레벨로 여는 새 건물(창고 K3·금광 K4·파견소 K6·대장간 K8·길드 회관 K10·망루 K12)을 [건설] 띠·자리 고르기로 짓고(길·겹침·성벽 거절) 옮기기
## → 연구(시작·취소 환불·연구소 레벨·다이아/무료 즉시 완료·가속·여러 레벨·건축학 보너스가 건설 시간에) 를 버튼과 같은 함수로 하고,
## 동작마다 앱 상태(곧바로 보인 값)와 서버 GET /v1/player를 맞춘다(다르면 예측 버그).
## 실행: cd server && env -u DATABASE_URL PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=8802 node src/main.ts &
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/journey_buildings_online.tscn -- --api=http://127.0.0.1:8802 --device=/tmp/x/device.json --out=/tmp/jb.png
## 마지막 줄이 JOURNEY BUILDINGS ONLINE PASSED(실패면 종료 코드 1).

const EconomyScript := preload("res://scripts/economy.gd")
const GameData := preload("res://scripts/game_data.gd")
const Balance := preload("res://scripts/balance.gd")
const MainScript := preload("res://scripts/main.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")
const BuildListScript := preload("res://scripts/build_list_panel.gd")
const PlacementScript := preload("res://scripts/placement.gd")
const ResearchPanelScript := preload("res://scripts/research_panel.gd")

var _main
var _shots: Array = []
var _fails := 0
var _notes: Array = []
var _resp = null
var _resp_done := false
var _resp_err := ""


func _ready() -> void:
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	get_window().size = Vector2i(360, 640)
	var device := Net.arg_value("device")
	_check(Net.is_online() and device != "", "online mode with --api and --device", Net.api_base)
	if _fails > 0:
		return _finish()
	Net.device_path = device
	Net.auth_path = device.get_base_dir().path_join("auth.json")
	DirAccess.remove_absolute(device)
	Net.set_auth("guest")
	Tutorial.go_online()  # 테스트 장면에서는 Tutorial._start가 건너뛴다 — 실제 게임처럼
	add_child(preload("res://scenes/main.tscn").instantiate())
	if not await _world("world built after connecting (fresh guest)"):
		return _finish()
	Economy.notice.connect(func(s): _notes.append(s))
	await _phase_lots()
	await _phase_new_buildings()
	await _phase_upgrades()
	await _phase_research()
	await _snap()
	_sheet()
	_finish()


# --- 1) 가이드 공터 첫 건설 ---
func _phase_lots() -> void:
	var ok := await _wait_until(func(): return not Tutorial.mission().is_empty(), 10.0)
	_check(ok and Tutorial.active() and Tutorial.mission().id == "look_keep" and Economy.unbuilt.has("lumber") and Economy.unbuilt.has("warehouse")
		and Economy.unbuilt.has("lumber#2") and not Economy.unbuilt.has("keep") and not Economy.unbuilt.has("gate"),
		"(lots) fresh guest: guide mission 1, empty lots (keep·gate built)", "unbuilt=%s m=%s" % [Economy.unbuilt.keys(), Tutorial.mission()])
	await _diff("(lots) start state")
	var tray = _child(BuildListScript)
	var placement = _child(PlacementScript)
	tray.open()
	await _frames(5)
	_check(str(tray.rows.lumber.why) == Tutorial.build_lock_text("lumber") and "2번째" in str(tray.rows.lumber.why),
		"(lots) before its mission the lumber card says which guide mission opens it", str(tray.rows.lumber.why))
	_notes.clear()
	tray._on_pressed("lumber")
	_check(not placement.is_active() and _notes.size() == 1, "(lots) pressing a locked card only shows the reason", str(_notes))
	_check(str(tray.rows.warehouse.why) != "" and "성채 Lv 3" in str(tray.rows.warehouse.why), "(lots) warehouse card: needs keep Lv 3", str(tray.rows.warehouse.why))
	tray.close()
	await _frames(10)
	var panel = _main._picker.building_panel
	panel.open_building("keep")
	await _frames(3)
	panel.close()
	_check(Tutorial.complete(), "(lots) opening the keep window completes guide 1", "")
	var stone0 := int(Economy.res.get("stone", 0))
	var r0: Dictionary = Tutorial.reward(0)
	_check(Tutorial.claim() and int(Economy.res.get("stone", 0)) == stone0 + int(r0.get("stone", 0)), "(lots) claim shows the reward at once", str([r0, Economy.res]))
	_check(await _wait_until(func(): return Tutorial.step == 1 and not Economy.quest_waiting(), 10.0), "(lots) server moved the guide to 2", str(Economy.server_quest))
	await _diff("(lots) after guide reward 1")
	# 벌목장: [건설] 띠 → 카드 → 자리 고르기 → [건설]
	tray.open()
	await _frames(5)
	_check(str(tray.rows.lumber.why) == "", "(lots) the lumber card is buildable now", str(tray.rows.lumber.why))
	tray._on_pressed("lumber")
	await _frames(3)
	_check(placement.is_active() and placement.ok, "(lots) the card starts placement on a free cell", "active=%s ok=%s" % [placement.is_active(), placement.ok])
	var cell: Vector2i = placement.cell
	var res0 := Economy.res.duplicate()
	var cost := GameData.build_cost("lumber", 1)
	var t0 := Economy.time_now()
	placement.confirm()
	_check(Economy.is_building("lumber") and Economy.layout.get("lumber") == cell and int(Economy.res.stone) == int(res0.stone) - int(cost.stone)
		and int(Economy.res.food) == int(res0.food) - int(cost.food) and absf(float(Economy.build_job("lumber").finish) - (t0 + GameData.config_num("lot_build_sec"))) < 1.0,
		"(lots) [건설] starts the lot at once: cost paid, cell kept, lot_build_sec timer", str([Economy.build, Economy.res, cost]))
	await _settle()
	_check(not _notes.has(EconomyScript.ROLLBACK_TEXT) and Economy.is_building("lumber"), "(lots) server accepted the first build", str(_notes))
	await _diff("(lots) lumber lot building")
	_check(await _wait_until(func(): return not Economy.unbuilt.has("lumber"), 15.0), "(lots) the lot finishes after lot_build_sec (client polls)", str(Economy.build))
	await _settle()
	_check(Tutorial.complete(), "(lots) guide 2 (build lumber) complete", "")
	await _diff("(lots) lumber built")
	Tutorial.claim()
	await _wait_until(func(): return Tutorial.step == 2 and not Economy.quest_waiting(), 10.0)
	# 채석장: 공터 건물 창 [건설](기본 자리, cell 없이)
	panel.open_building("quarry")
	await _frames(3)
	_check(panel.upgrade_button.text == panel.BUILD_TEXT and not panel.upgrade_button.disabled, "(lots) quarry lot window: [건설] enabled", panel.reason_label.text)
	panel.upgrade_button.pressed.emit()
	panel.upgrade_button.pressed.emit()  # 빠른 두 번 탭
	_check(Economy.is_building("quarry"), "(lots) quarry builds from its lot window", str(Economy.build))
	await _settle()
	panel.close()
	await _diff("(lots) quarry building (double tap = one build)")
	await _request("/v1/test/build_now", {})
	await _settle()
	_check(not Economy.unbuilt.has("quarry"), "(lots) quarry finished", "")
	await _diff("(lots) quarry built")
	await _snap()


# --- 2) 성채 레벨로 여는 새 건물: [건설] 띠·자리 고르기 ---
func _phase_new_buildings() -> void:
	var big := {"wood": 90000000, "stone": 90000000, "food": 90000000}
	var plan := [["warehouse", 3], ["goldmine", 4], ["dispatch", 6], ["forge", 8], ["guild_hall", 10], ["watchtower", 12]]
	var tray = _child(BuildListScript)
	for row in plan:
		var id: String = row[0]
		var k: int = row[1]
		await _set_levels({"keep": k - 1}, big)
		await _wait_until(func(): return Economy.building_level("keep") == k - 1, 5.0)
		tray = _child(BuildListScript)  # 월드를 다시 만들면 띠도 새것
		var now := Economy.time_now()
		_check(Economy.upgrade_block(id, now) == "keep_cap", "(new) %s locked at keep %d" % [id, k - 1], Economy.upgrade_block(id, now))
		tray.open()
		await _frames(5)
		_check("성채 Lv %d" % k in str(tray.rows[id].why) and tray.rows[id].action_label.text == tray.LOCK_TEXT, "(new) %s card: 잠김 · 성채 Lv %d 필요" % [id, k], str(tray.rows[id].why))
		tray.close()
		await _frames(10)
		var c = Economy.free_cell(id, Vector2i(0, 0))
		var e := await _raw("POST", "/v1/building/upgrade", {"building": id, "cell": [c.x, c.y] if c != null else [6, 6]})
		_check(e == "keep_cap", "(new) server also refuses %s below keep %d" % [id, k], e)
		await _set_levels({"keep": k}, big)
		await _wait_until(func(): return Economy.building_level("keep") == k, 5.0)
		tray = _child(BuildListScript)
		tray.open()
		await _frames(5)
		_check(str(tray.rows[id].why) == "" and tray.rows[id].tag.visible, "(new) at keep %d the %s card is open with NEW" % [k, id], str(tray.rows[id].why))
		tray.close()
		await _frames(10)
		if id == "warehouse":
			await _placement_refusals(id)
		c = Economy.free_cell(id, Vector2i(0, 0))
		_check(c != null, "(new) a free cell for %s exists" % id, "")
		if c == null:
			continue
		var res0 := Economy.res.duplicate()
		var cost := GameData.build_cost(id, 1)
		var t0 := Economy.time_now()
		_check(Economy.build_at(id, c, t0), "(new) build_at %s %s" % [id, c], str(_notes.back() if not _notes.is_empty() else ""))
		var paid := true
		for r in cost:
			paid = paid and int(Economy.res[r]) == int(res0[r]) - int(cost[r])
		_check(Economy.is_building(id) and Economy.layout.get(id) == c and paid
			and absf(float(Economy.build_job(id).finish) - (t0 + Economy._build_sec(id, 1))) < 1.0, "(new) %s starts at once at its cell (cost = Lv 1 cost, time = Lv 1 time)" % id,
			str([Economy.build, cost]))
		await _settle()
		_check(not _notes.has(EconomyScript.ROLLBACK_TEXT) and Economy.is_building(id), "(new) server accepted %s" % id, str(_notes.slice(-3)))
		await _diff("(new) %s building" % id)
		await _request("/v1/test/build_now", {})
		await _settle()
		_check(not Economy.unbuilt.has(id) and Economy.building_level(id) == 1 and Economy.layout.get(id) == c, "(new) %s built at Lv 1 and stays at its cell" % id, str(Economy.layout))
		await _diff("(new) %s built" % id)
	# 옮기기
	var from: Vector2i = Economy.layout.warehouse
	var to = null
	for x in range(-8, 8):
		for y in range(-8, 8):
			var cc := Vector2i(x, y)
			if to == null and cc != from and Economy.place_block("warehouse", cc) == "" and (cc - from).length() > 2.5:
				to = cc
	_check(to != null and Economy.move_building("warehouse", to) and Economy.layout.warehouse == to, "(move) warehouse moves at once", str([from, to]))
	await _settle()
	_check(not _notes.has(EconomyScript.ROLLBACK_TEXT), "(move) server accepted the move", "")
	await _diff("(move) warehouse moved")
	_notes.clear()
	_check(not Economy.move_building("warehouse", Economy.building_cell("lumber")) and _notes.has(Balance.PLACE_TEXT.overlap) and Economy.layout.warehouse == to,
		"(move) onto another building: refused (overlap), nothing changes", str(_notes))
	_check(not Economy.move_building("keep", Vector2i(6, 6)), "(move) the keep cannot move", "")
	var e2 := await _raw("POST", "/v1/building/move", {"building": "warehouse", "cell": [Economy.building_cell("lumber").x, Economy.building_cell("lumber").y]})
	_check(e2 == "overlap", "(move) server refuses the overlap too", e2)
	# 다시 읽기(새로 받은 상태)도 자리를 지킨다
	var lay := Economy.layout.duplicate()
	await _request_get()
	_check(Economy.layout == lay, "(reload) a fresh GET keeps every placed cell", str([lay, Economy.layout]))
	await _snap()


func _placement_refusals(id: String) -> void:
	var m: int = Economy.interior_half_tiles() - Balance.WALL_MARGIN_TILES
	var cases := {"road": Vector2i(-1, 5), "overlap": Economy.building_cell("lumber"), "out": Vector2i(-m - 1, -m - 1)}
	for why in cases:
		var cell: Vector2i = cases[why]
		_check(Economy.place_block(id, cell) == why, "(place) %s at %s → %s" % [id, cell, why], Economy.place_block(id, cell))
		_notes.clear()
		var res0 := Economy.res.duplicate()
		_check(not Economy.build_at(id, cell, Economy.time_now()) and _notes.has(Balance.PLACE_TEXT[why]) and Economy.res == res0 and not Economy.is_building(id)
			and not Economy._waiting.has("build"), "(place) build_at refuses %s with its notice and sends nothing" % why, str(_notes))
		var e := await _raw("POST", "/v1/building/upgrade", {"building": id, "cell": [cell.x, cell.y]})
		_check(e == why, "(place) server refuses %s at %s with %s" % [id, cell, why], e)
	var e3 := await _raw("POST", "/v1/building/upgrade", {"building": id})
	_check(e3 == "no_cell", "(place) server: a new building without a cell → no_cell", e3)


# --- 3) 업그레이드 ---
func _phase_upgrades() -> void:
	var big := {"wood": 90000000, "stone": 90000000, "food": 90000000}
	await _set_levels({"keep": 12, "gate": 5, "lumber": 4, "quarry": 4, "farm": 2, "stable": 3, "houses": 4, "lab": 5, "tavern": 6, "barracks": 6}, big)
	await _wait_until(func(): return Economy.building_level("lumber") == 4 and not Economy.unbuilt.has("farm"), 5.0)
	await _diff("(up) mid-game levels")
	var panel = _main._picker.building_panel
	# 자동 수집: 쌓인 목재가 있는 벌목장을 올리면 먼저 받는다
	await _request("/v1/test/age", {"minutes": 30})
	var now := Economy.time_now()
	var pend := Economy.pending("lumber", now)
	_check(pend > 0, "(up) lumber has wood waiting", str(pend))
	var wood0 := int(Economy.res.wood)
	var cost := Economy.upgrade_cost("lumber")
	panel.open_building("lumber")
	await _frames(3)
	panel.upgrade_button.pressed.emit()
	panel.upgrade_button.pressed.emit()  # 빠른 두 번 탭 = 한 번
	var shown := int(Economy.res.wood)
	_check(Economy.is_building("lumber") and absi(shown - (wood0 + pend - int(cost.wood))) <= Economy.pending("lumber", now + 61) and Economy.pending("lumber", Economy.time_now()) == 0,
		"(up) lumber 4→5 starts; the waiting wood is collected first (shown at once)", "wood %d→%d pend=%d" % [wood0, shown, pend])
	await _settle()
	panel.close()
	_check(not _notes.has(EconomyScript.ROLLBACK_TEXT), "(up) server accepted the upgrade", "")
	await _diff("(up) lumber upgrading after auto-collect")
	# 일꾼이 바쁘다
	panel.open_building("quarry")
	await _frames(3)
	_check(panel.upgrade_button.disabled and EconomyScript.BLOCK_TEXT.builder_busy in panel.reason_label.text, "(up) builder busy: quarry button off with the reason", panel.reason_label.text)
	panel.close()
	_notes.clear()
	_check(not Economy.upgrade("quarry", Economy.time_now()) and _notes.has(EconomyScript.BLOCK_TEXT.builder_busy), "(up) Economy.upgrade → builder busy notice", str(_notes))
	var e := await _raw("POST", "/v1/building/upgrade", {"building": "quarry"})
	_check(e == "builder_busy", "(up) server says builder_busy too", e)
	await _request("/v1/test/build_now", {})
	await _settle()
	_check(Economy.building_level("lumber") == 5, "(up) lumber reached 5", "")
	await _diff("(up) lumber 5")
	# 성채 상한: lumber 12 = keep 12 → 다음 레벨은 성채 13 필요. ✗ 줄 → 성채 창
	await _set_levels({"lumber": 12}, {})
	panel.open_building("lumber")
	await _frames(3)
	var link = _req_button(panel, "성채")
	_check(panel.upgrade_button.disabled and panel.reason_label.text == EconomyScript.BLOCK_TEXT.keep_cap and link != null and "✗" in link.text,
		"(up) keep cap: reason + red ✗ keep line", "%s / %s" % [panel.reason_label.text, _req_texts(panel)])
	if link != null:
		link.pressed.emit()
		await _frames(5)
		_check(panel.visible and panel.building_id == "keep", "(up) the ✗ keep line opens the keep window", panel.building_id)
	panel.close()
	await _frames(3)
	e = await _raw("POST", "/v1/building/upgrade", {"building": "lumber"})
	_check(e == "keep_cap", "(up) server says keep_cap too", e)
	# 선행 조건: 기병 마구간 3→4는 농장 3·보병 막사 3 필요(농장 2)
	panel.open_building("stable")
	await _frames(3)
	link = _req_button(panel, "농장")
	_check(Economy.upgrade_block("stable", Economy.time_now()) == "prereq" and panel.reason_label.text == EconomyScript.BLOCK_TEXT.prereq and link != null and "✗ 농장 Lv 3" in link.text
		and _req_button(panel, "보병 막사") == null, "(up) prereq: red ✗ 농장 Lv 3 line (met lines stay green labels)", str(_req_texts(panel)))
	if link != null:
		link.pressed.emit()
		await _frames(5)
		_check(panel.visible and panel.building_id == "farm", "(up) the ✗ farm line opens the farm window", panel.building_id)
	panel.close()
	e = await _raw("POST", "/v1/building/upgrade", {"building": "stable"})
	_check(e == "prereq", "(up) server says prereq too", e)
	# 두 번째 일꾼 + 가속 + 무료 즉시 완료
	await _request("/v1/test/speedups", {"items": {"builder_1440": 1, "any_5": 1, "build_60": 2, "build_15": 3, "build_5": 3}})
	_check(Economy.use_speedup("builder_1440", 1), "(up) the builder pass hires builder 2", "")
	await _settle()
	await _diff("(up) builder 2 hired")
	_check(Economy.upgrade("tavern", Economy.time_now()), "(up) tavern 6→7 on builder 1", "")
	await _settle()
	_check(Economy.upgrade("houses", Economy.time_now()) and Economy.build_jobs().size() == 2, "(up) houses 4→5 on builder 2 at the same time", str(Economy.build_jobs()))
	await _settle()
	await _diff("(up) two builders")
	var f0 := float(Economy.build_job("tavern").finish)
	_check(Economy.use_speedup("any_5", 1, "build", "tavern") and absf(float(Economy.build_job("tavern").finish) - (f0 - 300.0)) < 1.0, "(up) any_5 on tavern pulls 5 min at once", "")
	await _settle()
	await _diff("(up) tavern after any_5")
	_check(Economy.use_speedup("build_15", 1, "build", "tavern"), "(up) build_15 on tavern", "")
	await _settle()
	var left := Economy.build_left(Economy.time_now(), "tavern")
	var guard := 0
	while left > Economy.free_finish_sec() and guard < 12:  # 남은 시간을 넘지 않는 가장 큰 가속부터
		guard += 1
		for sid in ["build_60", "build_15", "build_5"]:
			if Economy.speedup_count(sid) > 0 and float(Economy.speedup_parse(sid).min) * 60.0 < left - 5.0:
				Economy.use_speedup(sid, 1, "build", "tavern")
				break
		await _settle()
		left = Economy.build_left(Economy.time_now(), "tavern")
	await _diff("(up) tavern after speed-ups")
	panel.open_building("tavern")
	await _frames(3)
	_check(left > 0.0 and left <= Economy.free_finish_sec() and panel.free_build_button.visible, "(up) tavern ≤ 5 min left: [무료 즉시 완료] shows", "left=%s" % left)
	panel.free_build_button.pressed.emit()
	_check(Economy.building_level("tavern") == 7 and not Economy.is_building("tavern"), "(up) free finish: tavern 7 at once", str(Economy.build_jobs()))
	await _settle()
	panel.close()
	_check(not _notes.has(EconomyScript.ROLLBACK_TEXT) and Economy.building_level("tavern") == 7, "(up) server accepted the free finish", "")
	await _diff("(up) tavern 5 (free finish)")
	await _request("/v1/test/build_now", {})
	await _settle()
	await _diff("(up) houses done")
	# 수집 + 2번째 채
	await _set_levels({"keep": 12}, {})
	var c = Economy.free_cell("lumber#2", Vector2i(3, 9))
	var res0 := Economy.res.duplicate()
	var t0 := Economy.time_now()
	_check(c != null and Economy.build_at("lumber#2", c, t0) and int(Economy.res.stone) == int(res0.stone) - int(GameData.build_cost("lumber", 1).stone)
		and absf(float(Economy.build_job("lumber#2").finish) - (t0 + Economy._build_sec("lumber#2", 1))) < 1.0, "(copy) lumber#2 builds: same Lv 1 cost/time as lumber", str(Economy.build))
	await _settle()
	await _diff("(copy) lumber#2 building")
	await _request("/v1/test/build_now", {})
	await _settle()
	_check(not Economy.unbuilt.has("lumber#2"), "(copy) lumber#2 built", "")
	await _request("/v1/test/age", {"minutes": 20})
	for b in ["lumber#2", "farm", "goldmine"]:
		var n := Economy.pending(b, Economy.time_now())
		var r: String = Economy.yield_of(b)
		var before := int(Economy.res.get(r, 0)) if r != "gold" else Economy.gold
		Economy.collect(b, Economy.time_now())
		var after := int(Economy.res.get(r, 0)) if r != "gold" else Economy.gold
		_check(n > 0 and after == before + n, "(collect) %s: +%d %s shown at once" % [b, n, r], "%d→%d" % [before, after])
		await _settle()
		await _diff("(collect) %s" % b)
	await _snap()


# --- 4) 연구 ---
func _phase_research() -> void:
	var big := {"wood": 90000000, "stone": 90000000, "food": 90000000}
	await _set_levels({"lab": 5}, big)
	await _request("/v1/test/grant_gold", {"amount": 50000000})
	await _request("/v1/test/grant_diamonds", {"amount": 5000})
	await _settle()
	var rp = _child(ResearchPanelScript)
	rp.open()
	await _frames(5)
	rp.open_detail("wood_tech")
	await _frames(3)
	var res0 := Economy.res.duplicate()
	var g0 := Economy.gold
	var cost := Economy.research_cost("wood_tech")
	rp.start_button.pressed.emit()
	rp.start_button.pressed.emit()
	_check(str(Economy.research_current.get("id", "")) == "wood_tech" and int(Economy.res.wood) == int(res0.wood) - int(cost.wood) and Economy.gold == g0 - int(cost.gold),
		"(res) start wood_tech: cost paid at once (double tap = once)", str([Economy.research_current, cost]))
	await _settle()
	await _diff("(res) wood_tech started")
	res0 = Economy.res.duplicate()
	var refund := GameData.research_refund(cost)
	rp.cancel_button.pressed.emit()
	_check(Economy.research_current.is_empty() and int(Economy.res.wood) == int(res0.wood) + int(refund.wood), "(res) cancel refunds half at once", str(refund))
	await _settle()
	await _diff("(res) cancelled")
	# 연구소 레벨 조건
	var locked := ""
	for d in GameData.research_defs():
		if int(d.lab_req) > 5 and str(d.req1) == "":
			locked = d.id
			break
	if locked == "":
		for d in GameData.research_defs():
			if int(d.lab_req) > 5:
				locked = d.id
				break
	_notes.clear()
	_check(Economy.research_block(locked) == "locked" and not Economy.start_research(locked) and Economy.research_current.is_empty(), "(res) %s needs a higher lab: locked" % locked, Economy.research_block(locked))
	var e := await _raw("POST", "/v1/research/start", {"id": locked})
	_check(e == "locked", "(res) server says locked too", e)
	# wood_tech·stone_tech를 3까지: 다이아 즉시 완료 / 무료 즉시 완료
	for id in ["wood_tech", "stone_tech"]:
		for i in 3:
			_check(Economy.start_research(id), "(res) start %s Lv %d" % [id, i + 1], Economy.research_block(id))
			await _settle()
			var dia0 := Economy.diamonds
			var dc := Economy.research_dia_cost(Economy.time_now())
			_check(Economy.finish_research_now() and Economy.research_level(id) == i + 1 and Economy.diamonds == dia0 - dc, "(res) finish %s Lv %d now (%d dia)" % [id, i + 1, dc], "")
			await _settle()
			_check(not _notes.has(EconomyScript.ROLLBACK_TEXT), "(res) server accepted the finish", str(_notes.slice(-2)))
			await _diff("(res) %s Lv %d" % [id, i + 1])
	# 건축학(연구 600 s): 다이아로 끝내기 전 가속 아이템으로 당기고 무료 완료
	await _request("/v1/test/speedups", {"items": {"research_5": 3, "build_60": 1}})
	_check(Economy.start_research("construct"), "(res) start construct", Economy.research_block("construct"))
	await _settle()
	var f0 := float(Economy.research_current.finish)
	_check(Economy.use_speedup("research_5", 1, "research") and absf(float(Economy.research_current.finish) - (f0 - 300.0)) < 1.0, "(res) research_5 pulls 5 min at once", "")
	await _settle()
	await _diff("(res) construct after research_5")
	_check(not Economy.use_speedup("build_60", 1, "research"), "(res) a build speed-up cannot be used on research", "")
	var left := Economy.research_left(Economy.time_now())
	if left > Economy.free_finish_sec():
		Economy.use_speedup("research_5", 1, "research")
		await _settle()
	var dia1 := Economy.diamonds
	_check(Economy.research_dia_cost(Economy.time_now()) == 0 and Economy.finish_research_now() and Economy.research_level("construct") == 1 and Economy.diamonds == dia1,
		"(res) ≤ 5 min left: free finish (0 dia)", str(Economy.research_current))
	await _settle()
	await _diff("(res) construct Lv 1")
	# 건축학 보너스 → 건설 시간(서버와 같은 값)
	var pct := float(Economy.research_bonus().build_speed_pct)
	var sec := Economy.upgrade_sec("quarry")
	var base := GameData.build_sec("quarry", Economy.building_level("quarry"))
	var t0 := Economy.time_now()
	_check(pct > 0.0 and sec == roundi(base / (1.0 + pct / 100.0)) and sec < base, "(res) construct shortens build time (%d → %d s)" % [base, sec], str(pct))
	_check(Economy.upgrade("quarry", t0), "(res) quarry upgrade starts", "")
	await _settle()
	var srv := await _server()
	var job = srv.get("build") if srv.get("build") is Dictionary and srv.build.get("id") == "quarry" else srv.get("build2")
	_check(job is Dictionary and absf(float(job.finish) - (t0 + sec)) < 1.5 and absf(float(Economy.build_job("quarry").finish) - float(job.finish)) < 0.01,
		"(res) the server uses the same research-shortened time", str([job, t0 + sec]))
	await _diff("(res) quarry with build-speed research")
	rp.close()


# --- 도구 ---

## 앱 상태와 서버 GET /v1/player(반영하지 않고 읽은 것)를 맞춘다.
func _diff(tag: String) -> void:
	await _settle()
	var p := await _server()
	if p.is_empty():
		_check(false, tag + ": client == server", "no server reply")
		return
	var bad := []
	for r in ["wood", "stone", "food"]:
		if int(Economy.res.get(r, 0)) != int(p.res.get(r, 0)):
			bad.append("res.%s %d/%d" % [r, int(Economy.res.get(r, 0)), int(p.res.get(r, 0))])
	if Economy.gold_tenths != int(p.gold_tenths):
		bad.append("gold_tenths %d/%d" % [Economy.gold_tenths, int(p.gold_tenths)])
	if Economy.diamonds != int(p.diamonds):
		bad.append("diamonds %d/%d" % [Economy.diamonds, int(p.diamonds)])
	if Economy.dia_tickets != int(p.dia_tickets):
		bad.append("tickets %d/%d" % [Economy.dia_tickets, int(p.dia_tickets)])
	for k in GameData.building_keys():
		var sv = p.buildings.get(k, {})
		if int(Economy.levels.get(k, 1)) != int(sv.get("level", 1)):
			bad.append("level.%s %s/%s" % [k, Economy.levels.get(k, 1), sv.get("level", 1)])
		if Economy.yield_of(k) != "" and sv.has("last_collect") and absf(float(Economy.last_collect.get(k, 0)) - float(sv.last_collect)) > 1.0:
			bad.append("last_collect.%s %.1f/%.1f" % [k, float(Economy.last_collect.get(k, 0)), float(sv.last_collect)])
	var su: Array = p.unbuilt.duplicate()
	su.sort()
	var cu: Array = Economy.unbuilt.keys()
	cu.sort()
	if su != cu:
		bad.append("unbuilt %s/%s" % [cu, su])
	for pair in [["build", Economy.build], ["build2", Economy.build2]]:
		var sj = p.get(pair[0])
		var cj: Dictionary = pair[1]
		if (sj == null) != cj.is_empty() or (sj is Dictionary and (str(sj.id) != str(cj.get("id", "")) or absf(float(sj.finish) - float(cj.get("finish", 0))) > 1.5)):
			bad.append("%s %s/%s" % [pair[0], cj, sj])
	if absf(Economy.builder2_until - (float(p.builder2_until) if p.get("builder2_until") != null else 0.0)) > 1.5:
		bad.append("builder2_until %s/%s" % [Economy.builder2_until, p.get("builder2_until")])
	var sl := {}
	for id in p.layout:
		sl[id] = Vector2i(int(p.layout[id][0]), int(p.layout[id][1]))
	if sl != Economy.layout:
		bad.append("layout %s/%s" % [Economy.layout, sl])
	var ss := {}
	for id in p.speedups:
		if int(p.speedups[id]) > 0:
			ss[id] = int(p.speedups[id])
	var cs := {}
	for id in Economy.speedups:
		if int(Economy.speedups[id]) > 0:
			cs[id] = int(Economy.speedups[id])
	if ss != cs:
		bad.append("speedups %s/%s" % [cs, ss])
	var rl := {}
	for id in p.research.levels:
		rl[id] = int(p.research.levels[id])
	if rl != Economy.research_levels:
		bad.append("research %s/%s" % [Economy.research_levels, rl])
	var rc = p.research.current
	if (rc == null) != Economy.research_current.is_empty() or (rc is Dictionary and (str(rc.id) != str(Economy.research_current.get("id", "")) or absf(float(rc.finish) - float(Economy.research_current.get("finish", 0))) > 1.5)):
		bad.append("research_cur %s/%s" % [Economy.research_current, rc])
	if int(p.quest.tut_step) != int(Economy.server_quest.get("tut_step", -1)) or str(p.quest.tut_state) != str(Economy.server_quest.get("tut_state", "")):
		bad.append("quest %s/%s" % [Economy.server_quest, p.quest])
	_check(bad.is_empty(), tag + ": client == server", str(bad))


## 앱이 보낸 요청이 모두 답을 받을 때까지(즉시 반영·응답 대기·예측).
func _settle() -> void:
	await _wait_until(func(): return Economy._hold == 0 and Economy._waiting.is_empty() and Economy._predicts.is_empty() and not Economy.quest_waiting(), 15.0)
	await _frames(3)


## GET /v1/player를 반영하지 않고 읽는다(player 사전).
func _server() -> Dictionary:
	_resp = null
	_resp_done = false
	Net.send("GET", "/v1/player", null, func(d): _resp = d; _resp_done = true, func(): _resp_done = true)
	await _wait_until(func(): return _resp_done, 15.0)
	return _resp.player if _resp is Dictionary and _resp.get("player") is Dictionary else {}


func _request_get() -> void:
	_resp_done = false
	Net.send("GET", "/v1/player", null, func(d):
		Economy.apply_server(d)
		_resp_done = true, func(): _resp_done = true)
	await _wait_until(func(): return _resp_done, 15.0)
	await _frames(3)


## 거절을 기대하는 직접 요청: 오류 코드("" = 받아들였다 — 그 응답은 반영한다).
func _raw(method: String, path: String, body) -> String:
	_resp_done = false
	_resp_err = "?"
	Net.send(method, path, body, func(d):
		_resp_err = ""
		if d.has("player"):
			Economy.apply_server(d)
		_resp_done = true, func():
		_resp_err = Net.last_error
		_resp_done = true, true, true)
	await _wait_until(func(): return _resp_done, 15.0)
	return _resp_err


func _request(path: String, body) -> void:
	_resp_done = false
	Net.send("POST", path, body, func(d):
		Economy.apply_server(d)
		_resp_done = true, func(): _resp_done = true)
	await _wait_until(func(): return _resp_done, 15.0)
	await _frames(3)


## 테스트 훅으로 건물 레벨·자원을 정한다(성채 단계가 바뀌면 main이 월드를 다시 만든다 — 새 main을 잡는다).
func _set_levels(levels: Dictionary, res: Dictionary) -> void:
	var half := Economy.interior_half_tiles()
	await _request("/v1/test/levels", {"levels": levels, "res": res})
	await _frames(10)
	if Economy.interior_half_tiles() != half or not is_instance_valid(_main) or _main.is_queued_for_deletion():
		await _world("world rebuilt at keep %d" % Economy.building_level("keep"))


func _world(what: String) -> bool:
	var ok := await _wait_until(func():
		var m = _current_main()
		return Net.ready_once and m != null and m.camera != null and m._picker != null, 30.0)
	_check(ok, what, "ready=%s up=%s" % [Net.ready_once, Net.up])
	if not ok:
		return false
	_main = _current_main()
	await _frames(3)
	GameData._config.fx_shake = "0"
	for c in _main.get_children():
		if c.get_script() == SpawnerScript:
			c.set_process(false)  # 처치 골드가 서버 골드 비교를 흔들지 않게
	for m in get_tree().get_nodes_in_group("monsters"):
		m.queue_free()
	return true


func _current_main():
	for c in get_children():
		if c.get_script() == MainScript and not c.is_queued_for_deletion():
			return c
	return null


func _child(script):
	for c in _main.get_children():
		if c.get_script() == script:
			return c
	return null


## 건물 창 선행 조건 줄 중 name을 담은 빨간 링크 버튼(✗). 없으면 null.
func _req_button(panel, name: String):
	for c in panel.reqs.get_children():
		if c is Button and not c.is_queued_for_deletion() and name in c.text:
			return c
	return null


func _req_texts(panel) -> Array:
	return panel.reqs.get_children().filter(func(c): return not c.is_queued_for_deletion()).map(func(c): return c.text)


func _finish() -> void:
	if _fails > 0:
		print("JOURNEY BUILDINGS ONLINE FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("JOURNEY BUILDINGS ONLINE PASSED")
		get_tree().quit(0)


func _check(ok: bool, what: String, detail: String) -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + detail))
	if not ok:
		_fails += 1


func _sheet() -> void:
	var out := "/tmp/journey_buildings_online.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	if _shots.is_empty() or _shots[0] == null:
		return
	var w: int = _shots[0].get_width() / 2
	var h: int = _shots[0].get_height() / 2
	var sheet := Image.create(w * _shots.size(), h, false, Image.FORMAT_RGB8)
	for i in _shots.size():
		var img: Image = _shots[i]
		img.convert(Image.FORMAT_RGB8)
		img.save_png(out.get_basename() + "_%d.png" % (i + 1))
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(w * i, 0))
	sheet.save_png(out)


func _snap() -> void:
	await _frames(8)
	_shots.append(get_viewport().get_texture().get_image())


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

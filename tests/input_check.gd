extends Node
## 헤드리스 입력 체크: 실제 main 씬(오토로드 포함)에 입력을 넣어 탭·드래그·핀치 판정을 확인한다.
## 실행: ./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/input_check.tscn
## 오토로드를 쓰므로 tests/run_tests.gd(-s)에서 preload 금지.
## 헤드리스 창은 64×64라 논리 화면이 1280×1280이 되고 Input.parse_input_event 좌표가 20배로 재조정된다 →
## 창을 360×640으로 맞춰 논리 화면을 폰과 같은 720×1280으로 만들고, 마우스는 viewport.push_input(ev, true)(논리 좌표),
## 터치는 엔진의 마우스 에뮬레이션을 거치도록 Input.parse_input_event에 창 좌표(final_transform 적용)로 넣는다.

const Balance := preload("res://scripts/balance.gd")
const Formation := preload("res://scripts/formation.gd")
const GameData := preload("res://scripts/game_data.gd")
const PickerScript := preload("res://scripts/unit_picker.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")
const HudScript := preload("res://scripts/hud.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

class ErrorCounter extends Logger:
	var count := 0
	func _log_error(_fn: String, _file: String, _line: int, _code: String, _why: String, _notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1  # SCRIPT ERROR는 그 테스트 함수만 중단시키므로 여기서 센다

var _fails := 0
var _errors := ErrorCounter.new()
var _main
var _camera: Camera3D
var _picker
var _heroes: Array = []


func _ready() -> void:
	OS.add_logger(_errors)
	Economy.save_path = ""  # 실제 저장 파일을 건드리지 않는다
	Fever.save_path = ""
	Fever.reset()
	GameData._config.fx_shake = "0"  # 테스트에서는 카메라 흔들림을 끈다(개정 17)
	Economy.reset(Time.get_unix_time_from_system())
	get_window().size = Vector2i(360, 640)
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(5)
	_camera = _main.camera
	for c in _main.get_children():
		if c.get_script() == PickerScript:
			_picker = c
		elif c.get_script() == SpawnerScript:
			c.set_process(false)  # 몬스터가 입력 사례에 끼어들지 않게(aggro로 영웅을 끌고 가지 않게)
	for m in get_tree().get_nodes_in_group("monsters"):
		m.queue_free()
	_heroes = get_tree().get_nodes_in_group("heroes")
	_heroes.sort_custom(func(a, b): return a.index < b.index)
	await _run()
	if _errors.count > 0:
		print("INPUT SCRIPT ERRORS %d" % _errors.count)
	_fails += _errors.count
	if _fails > 0:
		print("INPUT FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("INPUT ALL PASSED")
		get_tree().quit(0)


func _run() -> void:
	var warrior = _heroes[0]  # 기본 배치: 북(0) 성문 앞
	var archer = _heroes[1]   # 동(1) 성벽 위
	var archer2 = _heroes[3]  # 서(3) 성벽 위
	print("INPUT INFO: default camera building px (720x1280 logical): %s, gates %s" % [Balance.BUILDINGS.map(func(b): return [b.id, _building_px(b.id)]), range(4).map(func(s): return _gate_px(s))])
	print("INPUT INFO: default camera soldier building roof points that hit the building (long press here; INF = hidden): %s; site centers hit %s" % [
		["barracks", "archery", "stable"].map(func(id): return [id, _roof_px(id)]),
		["barracks", "archery", "stable"].map(func(id): return [id, _picker._pick(_building_px(id), PickerScript.LAYER_TAP).get("collider", self).get_meta("building", "none")])])

	# (a) 마우스 탭 → 영웅 선택
	_picker._select(null)
	await _tap(_hero_px(archer))
	_check(_picker.selected == archer, "(a) mouse tap on a hero selects it", "selected=%s" % [_name(_picker.selected)])

	# (b) 누른 채 12px 넘게 갔다가 제자리로 돌아와 떼기 → 선택도 명령도 아님
	_picker._select(null)
	await _dragback(_hero_px(warrior))
	_check(_picker.selected == null, "(b) drag-and-return on a hero does not select", "selected=%s" % [_name(_picker.selected)])
	await _tap(_hero_px(archer))
	var before := [archer.side, archer.post]
	await _dragback(_gate_px(0))
	_check(_picker.selected == archer and [archer.side, archer.post] == before,
		"(b) drag-and-return on a gate does not order", "selected=%s side/post=%s" % [_name(_picker.selected), [archer.side, archer.post]])

	# (c) 궁수 선택 중 전사가 서 있는 성문 정중앙 탭 → 궁수에게 성문 앞 명령 (F1 회귀)
	_picker._select(null)
	await _tap(_hero_px(archer))
	var gate := _gate_px(0)
	var warrior_d := _hero_px(warrior).distance_to(gate)
	_check(warrior_d <= PickerScript.HERO_TAP_PX, "(c) precondition: warrior within HERO_TAP_PX of the gate center", "d=%.1f" % warrior_d)
	await _tap(gate)
	_check(_picker.selected == archer and archer.side == 0 and archer.post == Formation.POST_GATE,
		"(c) gate tap with an archer selected orders the archer to the gate front (warrior %.1f px away)" % warrior_d,
		"selected=%s archer side/post=%s" % [_name(_picker.selected), [archer.side, archer.post]])

	# (d) 영웅 선택 중 성벽 토막 탭 → 성벽 위 명령
	await _tap(_hero_px(archer2))
	await _tap(_wall_px(2))
	_check(_picker.selected == archer2 and archer2.side == 2 and archer2.post == Formation.POST_WALL,
		"(d) wall tap with a hero selected orders a wall-top move",
		"selected=%s side/post=%s" % [_name(_picker.selected), [archer2.side, archer2.post]])

	# (e) 터치: 누른 중 두 번째 손가락 → 탭 취소. 핀치(벌리기) → camera.size 감소, 선택 없음
	_picker._select(null)
	var p := _hero_px(warrior)
	await _touch(0, p, true)
	await _touch(1, p + Vector2(0, 150), true)
	await _touch(1, p + Vector2(0, 150), false)
	await _touch(0, p, false)
	_check(_picker.selected == null, "(e) second finger during a press cancels the tap", "selected=%s" % [_name(_picker.selected)])
	var size_before := _camera.size
	p = _hero_px(warrior)
	await _touch(0, p, true)
	var q := p + Vector2(0, 150)
	await _touch(1, q, true)
	for i in 5:
		var nq := q + Vector2(0, 40)
		await _drag(1, nq, nq - q)
		q = nq
	await _touch(1, q, false)
	await _touch(0, _hero_px(warrior), false)  # 줌으로 영웅 화면 위치가 바뀌었다 — 그 위에서 뗀다
	_check(_camera.size < size_before and _picker.selected == null, "(e) pinch apart zooms in and does not select",
		"size %.1f -> %.1f selected=%s" % [size_before, _camera.size, _name(_picker.selected)])

	# (f) 전사 선택 중 성 밖 바닥 탭 → 자유 위치(POST_FREE), 3초 뒤 그 지점에 서 있다
	_camera.get_parent().zoom_by(70.0 / _camera.size)  # (e) 핀치로 확대된 줌을 기본(66)보다 조금 넓게 되돌린다 — (f)·(g)의 성 밖 지점이 화면 안에 오게
	var half: float = _main.castle.half
	_picker._select(null)
	await _tap(_hero_px(warrior))
	var field := Vector3(6, 0, -(half + Balance.WALL_T + 8))
	var fp := _camera.unproject_position(field)
	_check(_picker.selected == warrior and _open_ground(fp), "(f) precondition: warrior selected, field point on open ground", "selected=%s px=%s" % [_name(_picker.selected), fp])
	await _tap(fp)
	_check(warrior.post == Formation.POST_FREE, "(f) ground tap with the warrior selected sets a free post", "post=%d" % warrior.post)
	await get_tree().create_timer(3.0).timeout
	var fd := Formation.flat_distance(warrior.global_position, field)
	_check(fd < 0.5, "(f) warrior stands at the tapped field point 3 s later", "d=%.2f pos=%s" % [fd, warrior.global_position])
	GameState.refill()  # 리필은 자유 위치 배정도 유지한다
	await _frames(1)
	fd = Formation.flat_distance(warrior.global_position, field)
	_check(warrior.post == Formation.POST_FREE and fd < 0.1, "(f) refill keeps the free-point assignment", "post=%d d=%.2f" % [warrior.post, fd])

	# (g) 성벽 위 궁수 선택 중 반대편(남쪽) 성 밖 바닥 탭 → 북쪽 계단(landing → 윗단 → 아랫단 → 계단 앞)으로 내려가
	#     안쪽 통로 모서리 둘(계단 쪽 옆)을 돌아 남문 안쪽 지점으로 (성벽도 건물도 뚫지 않음)
	archer.move_to(0, Formation.POST_WALL)
	GameState.refill()  # 리필은 배정을 유지한 채 순간 복귀 → 궁수가 북쪽 성벽 위에 선다
	await _frames(1)
	await _tap(_hero_px(archer))
	var south := Vector3(-10, 0, half + Balance.WALL_T + 12)
	var sp := _camera.unproject_position(south)
	_check(_picker.selected == archer and archer.is_on_wall() and archer.side == 0 and _open_ground(sp),
		"(g) precondition: archer selected on the north wall, south field point on open ground",
		"selected=%s on_wall=%s side=%d px=%s" % [_name(_picker.selected), archer.is_on_wall(), archer.side, sp])
	var ge := 1.0 if Formation.perp(0).dot(archer.global_position) >= 0.0 else -1.0
	var lane := half - Balance.STAIR_W - Formation.GATE_PASS_MARGIN
	var down := [Formation.wall_landing(half, 0, ge), Formation.stair_top(half, 0, ge), Formation.stair_bottom(half, 0, ge), Formation.stair_approach(half, 0, ge),
		(Formation.SIDE_DIR[0] + Formation.perp(0) * ge) * lane, (Formation.SIDE_DIR[2] + Formation.perp(0) * ge) * lane, Formation.gate_inner(half, 2)]
	await _tap(sp)
	_check(archer.post == Formation.POST_FREE and archer._path.slice(0, 7) == down,
		"(g) wall-top archer ordered outside the far side goes down the north stairs, round the lane corners, then to the south gate's inner point",
		"post=%d path=%s" % [archer.post, archer._path])

	# (h) 선택된 영웅을 다시 탭 → 선택 해제
	_picker._select(null)
	await _tap(_hero_px(warrior))
	var was = _picker.selected
	await _tap(_hero_px(warrior))
	_check(was == warrior and _picker.selected == null, "(h) tapping the selected hero again deselects it",
		"first=%s then=%s" % [_name(was), _name(_picker.selected)])

	# (i) 선택된 영웅에서 20px(정밀 12px 밖, 32px 안) 떨어진 바닥 탭 → 그 영웅 재선택이 아니라 바닥 이동
	await _tap(_hero_px(warrior))
	var tp := _hero_px(warrior) + Vector2(0, 20)
	var old_free: Vector3 = warrior.free_pos
	var gp = _picker._ground_point(tp)
	_check(_picker.selected == warrior and _picker._pick(tp, PickerScript.LAYER_GATE | PickerScript.LAYER_WALL).is_empty() and _picker._hero_at(tp, PickerScript.HERO_TAP_PX) == warrior,
		"(i) precondition: warrior selected, tap point is open ground 20 px from it", "selected=%s px=%s" % [_name(_picker.selected), tp])
	await _tap(tp)
	_check(_picker.selected == warrior and Formation.flat_distance(warrior.free_pos, gp) < 0.1 and Formation.flat_distance(old_free, gp) > 1.0,
		"(i) ground tap 20 px from the selected hero moves it there", "selected=%s free_pos=%s ground=%s" % [_name(_picker.selected), warrior.free_pos, gp])

	# (j) 성 안 자유 위치 전사 선택 중 북쪽 성벽 탭 → 경로가 계단 앞 → 아랫단 → 윗단을 지나고, 몇 초 뒤 성벽 위 자리에 선다
	var yard := Vector3(0, 0, -(half - 8.0))  # 북쪽 십자 도로 위(성채와 북쪽 성벽 사이)
	warrior.move_to_point(yard)
	GameState.refill()
	await _frames(1)
	_picker._select(null)
	await _tap(_hero_px(warrior))
	_check(_picker.selected == warrior and Formation.region(half, warrior.global_position) == Formation.REGION_INSIDE,
		"(j) precondition: warrior selected on the ground inside the castle", "selected=%s pos=%s" % [_name(_picker.selected), warrior.global_position])
	await _tap(_wall_px(0))
	var home: Vector3 = warrior.stand_position()
	var je := 1.0 if Formation.perp(0).dot(home) >= 0.0 else -1.0
	var bi: int = warrior._path.find(Formation.stair_bottom(half, 0, je))
	var ti: int = warrior._path.find(Formation.stair_top(half, 0, je))
	var ai: int = warrior._path.find(Formation.stair_approach(half, 0, je))
	_check(warrior.side == 0 and warrior.post == Formation.POST_WALL and ai >= 0 and bi == ai + 1 and ti == bi + 1,
		"(j) wall tap with an inside warrior selected routes up the north stairs (approach, bottom, then top)",
		"side/post=%s path=%s" % [[warrior.side, warrior.post], warrior._path])
	await get_tree().create_timer(8.0).timeout
	var wd: float = warrior.global_position.distance_to(home)
	_check(wd < 0.1 and absf(warrior.global_position.y - Balance.WALL_H) < 0.01,
		"(j) warrior stands at its wall-top slot 8 s later", "d=%.2f pos=%s" % [wd, warrior.global_position])

	# --- 개정 7: 자원 건물·상인 탭, 거래 창 ---
	var badges: Node = null
	var panel: Node = null
	for c in _main.get_children():
		if c.get_script() == preload("res://scripts/badges.gd"):
			badges = c
		elif c.get_script() == preload("res://scripts/merchant_panel.gd"):
			panel = c
	var bwin = _building_win()
	var rig = _camera.get_parent()
	_picker._select(null)
	var now := Time.get_unix_time_from_system()
	Economy.reset(now)

	# (k) 말풍선 조건: 5분 이상 쌓인 자원 건물만 (벌목 10분, 농장 6분 → 2곳, 채석 3분은 제외)
	Economy.last_collect["lumber"] = now - 600.0
	Economy.last_collect["farm"] = now - 360.0
	Economy.last_collect["quarry"] = now - 180.0
	var ids: Array = badges.badge_ids(now)
	ids.sort()
	_check(ids == ["farm", "lumber"], "(k) badges only on resource buildings with >= 5 min pending", "ids=%s" % [ids])

	# (l) 영웅 없이 벌목장 탭 → 목재 +100, "+N" 뜸, 선택 없음 유지. 곧바로 또 탭하면 0이라 pop 없이 건물 창(개정 12 §2.5)
	var lp := _building_px("lumber")
	_check(_picker._pick(lp, PickerScript.LAYER_TAP).get("collider") != null and _picker._pick(lp, PickerScript.LAYER_TAP).collider.get_meta("building", "") == "lumber",
		"(l) precondition: lumber tap point hits the lumber tap body", "px=%s" % lp)
	await _tap(lp)
	_check(Economy.res["wood"] == 100 and badges.last_pop.get("amount", 0) == 100 and badges.last_pop.get("kind", "") == "wood" and _picker.selected == null,
		"(l) lumber tap collects 100 wood and pops +100", "wood=%d pop=%s" % [Economy.res["wood"], badges.last_pop])
	badges.last_pop = {}
	await _tap(lp)
	_check(Economy.res["wood"] == 100 and badges.last_pop.is_empty() and bwin.is_open() and bwin.building_id == "lumber" and _picker.selected == null,
		"(l) a second tap with nothing to collect shows no pop and opens the lumber building window", "wood=%d pop=%s open=%s id=%s" % [Economy.res["wood"], badges.last_pop, bwin.is_open(), bwin.building_id])
	bwin.close()

	# (m) 영웅 선택 중 벌목장 탭 → 수집되고 선택·위치 유지(이동 명령 없음)
	var hero_pre := [warrior.side, warrior.post, warrior.free_pos]
	_picker._select(warrior)
	Economy.last_collect["lumber"] = Time.get_unix_time_from_system() - 600.0
	await _tap(lp)
	_check(_picker.selected == warrior and Economy.res["wood"] == 200 and [warrior.side, warrior.post, warrior.free_pos] == hero_pre,
		"(m) lumber tap with a hero selected collects and keeps the selection without a move", "selected=%s wood=%d" % [_name(_picker.selected), Economy.res["wood"]])

	# (n) 성채 탭(개정 12 §2.5): 영웅 선택 중이어도 건물 창(선택·위치 그대로, 이동 명령 없음) / 없어도 건물 창(선택 없음 유지)
	var gold0: int = Economy.gold
	var kp := _building_px("keep")
	_check(_picker._pick(kp, PickerScript.LAYER_TAP).collider.get_meta("building", "") == "keep" and not _open_hero(kp),
		"(n) precondition: keep tap point hits the keep body, no hero nearby", "px=%s" % kp)
	await _tap(kp)
	_check(bwin.is_open() and bwin.building_id == "keep" and _picker.selected == warrior and [warrior.side, warrior.post, warrior.free_pos] == hero_pre
		and not panel.is_open() and Economy.gold == gold0, "(n) keep tap with a hero selected opens the keep window and keeps the hero (no move)",
		"open=%s id=%s post=%d free=%s" % [bwin.is_open(), bwin.building_id, warrior.post, warrior.free_pos])
	bwin.close()
	_picker._select(null)
	await _tap(kp)
	_check(bwin.is_open() and bwin.building_id == "keep" and _picker.selected == null, "(n) keep tap with no hero selected opens the keep window too", "selected=%s" % _name(_picker.selected))
	bwin.close()

	# (o) 상인 탭 → 창 열림, 선택 유지. 창 안(제목) 탭은 닫지 않는다
	_picker._select(warrior)
	var mp := _camera.unproject_position(Balance.MERCHANT_POS + Vector3(0, 1.0, 0))
	_check(not _picker._pick(mp, PickerScript.LAYER_MERCHANT).is_empty() and not _open_hero(mp),
		"(o) precondition: merchant tap point hits the merchant body", "px=%s" % mp)
	var free_before: Vector3 = warrior.free_pos
	await _tap(mp)
	await _frames(2)
	_check(panel.is_open() and _picker.selected == warrior and warrior.free_pos == free_before,
		"(o) merchant tap opens the trade window and keeps the hero selected", "open=%s selected=%s" % [panel.is_open(), _name(_picker.selected)])
	await _guard_wait()  # 연 직후 보호 시간에는 창 안 누름도 버린다 — 지난 뒤의 창 안 탭을 본다
	await _tap(panel.dialog.get_global_rect().position + Vector2(300, 20))
	_check(panel.is_open(), "(o) tapping inside the dialog does not close it", "open=%s" % panel.is_open())

	# (p) [판매] → 골드 증가·자원 0. 상인 시세와 같은 값
	Economy.res["stone"] = 7
	Economy.gold_tenths = 105  # 10.5골드: 판매가 소수 부분을 지키는지도 본다
	Economy.changed.emit()
	await _frames(2)
	var rate: float = Economy.current_rate("wood", Time.get_unix_time_from_system())
	var expect := Economy.sell_value("wood", 200, rate)
	_check(panel.rate_labels["wood"].text == "×%.1f" % rate and panel._timer_label.text.begins_with("다음 시세까지 "), "(p) trade window row shows that resource's rate and the countdown", "wood=%s timer=%s" % [panel.rate_labels["wood"].text, panel._timer_label.text])
	var bp: Vector2 = panel.sell_buttons["wood"].get_global_rect().get_center()
	await _tap(bp)  # [판매] → 수량 칸이 펼쳐진다. [최대] → [선택 판매]로 전량
	await _tap(panel.qty_max["wood"].get_global_rect().get_center())
	await _tap(panel.sell_selected_button.get_global_rect().get_center())
	_check(Economy.res["wood"] == 0 and Economy.gold_tenths == 105 + expect * 10 and Economy.gold == 10 + expect and Economy.res["stone"] == 7 and panel.is_open(),
		"(p) [sell] on wood zeroes wood and adds floor(200 x price x wood's own rate) whole gold (x10 tenths, 0.5 kept); others stay", "wood=%d tenths=%d expect=%d" % [Economy.res["wood"], Economy.gold_tenths, 105 + expect * 10])
	_check(panel.sell_buttons["wood"].disabled and not panel.sell_buttons["stone"].disabled, "(p) sell button is disabled at 0 holdings only", "")
	await _qty_sell_checks(panel)
	await _multi_sell_checks(panel)
	await _tap(panel.sell_all_button.get_global_rect().get_center())
	_check(Economy.res["stone"] == 0 and Economy.res["food"] == 0 and panel.sell_all_button.disabled, "(p) [sell all] clears everything", "stone=%d" % Economy.res["stone"])

	# (q) 창이 열린 동안 드래그는 카메라를 못 움직이고, 배경(바닥 위) 탭은 영웅을 못 움직이고 창만 닫는다
	var cam_pos: Vector3 = rig.position
	var bg := Vector2(30, 700)
	_check(_open_ground(bg) and panel.dialog.get_global_rect().has_point(bg) == false, "(q) precondition: backdrop point is open ground outside the dialog", "px=%s" % bg)
	var dp: Vector2 = panel.dialog.get_global_rect().position + Vector2(300, 20)  # 창 안에서 시작한 드래그(배경 누름은 닫기)
	_mouse_button(dp, true)
	for i in 6:
		_mouse_motion(dp + Vector2(0, 12) * (i + 1), Vector2(0, 12))
	_mouse_button(dp + Vector2(0, 72), false)
	await _frames(2)
	_check(rig.position == cam_pos and panel.is_open(), "(q) dragging while the window is open does not pan the camera", "pos=%s" % rig.position)
	var hero_state := [warrior.side, warrior.post, warrior.free_pos]
	await get_tree().create_timer(0.45).timeout  # 연 직후 배경 누름 무시 시간(OPEN_GUARD_MS)이 지나게
	await _tap(bg)
	_check(not panel.is_open() and _picker.selected == warrior and [warrior.side, warrior.post, warrior.free_pos] == hero_state,
		"(q) tapping the backdrop over open ground closes the window and does not move the hero", "open=%s state=%s" % [panel.is_open(), [warrior.side, warrior.post, warrior.free_pos]])
	await _tap(bg)
	_check(warrior.free_pos != hero_state[2], "(q) after closing, the same ground tap moves the hero again", "free=%s" % warrior.free_pos)

	# (r) 수레를 탭해도 창이 열린다 — 수레 바퀴·바닥 높이(0.4 m)도 앞쪽 건물 상자보다 상인 판정이 먼저
	_picker._select(null)
	var cp := _camera.unproject_position(Balance.MERCHANT_POS + Balance.MERCHANT_CART_OFFSET + Vector3(0, 0.4, 0))
	_check(not _picker._pick(cp, PickerScript.LAYER_MERCHANT).is_empty() and not _open_hero(cp), "(r) precondition: cart point hits the merchant body", "px=%s" % cp)
	await _tap(cp)
	await _frames(2)
	_check(panel.is_open(), "(r) tapping the cart opens the trade window", "open=%s" % panel.is_open())
	await _tap(bg)  # 더블 탭의 두 번째 누름
	_check(panel.is_open(), "(r) a backdrop press right after opening (double tap) does not close the window", "open=%s" % panel.is_open())
	panel.close()
	await _recruit_and_heroes(rig)


## 개정 10: 주점 탭 → 모집 창 → 1회 모집(오프라인), 창이 열린 동안 뒤 입력 차단.
## 개정 11: 하단 탭 바 4개, 영웅 목록(슬롯·카드 배치·정렬·적용) → 상세 → [레벨업]·[×10]·이전/다음·[배치].
func _recruit_and_heroes(rig) -> void:
	var recruit: Node = null
	var heroes_win: Node = null
	var hud: Node = null
	var tabs: Node = null
	for c in _main.get_children():
		if c.get_script() == preload("res://scripts/recruit_panel.gd"):
			recruit = c
		elif c.get_script() == preload("res://scripts/hero_panel.gd"):
			heroes_win = c
		elif c.get_script() == preload("res://scripts/hud.gd"):
			hud = c
		elif c.get_script() == preload("res://scripts/tab_bar.gd"):
			tabs = c
	_check(not hud.hint.visible, "(hint) hidden in IDLE", "")
	var mode0: int = GameState.mode
	GameState.mode = GameState.Mode.COUNTDOWN
	GameState._timer = 3.0
	GameState.mode_changed.emit(GameState.mode)
	_check(hud.hint.visible and hud.hint.text.contains("스테이지") and hud.hint.text.split("\n").size() == 2 and hud.hint.text.split("\n")[1] != "",
		"(hint) visible with context and tip during the countdown", hud.hint.text)
	GameState.mode = mode0
	GameState.mode_changed.emit(mode0)
	_check(not hud.hint.visible, "(hint) hidden again outside the countdown", "")
	_picker._select(null)
	Economy.gold_tenths = 27005  # 2700.5골드: 10회도 된다 — 연타가 10회를 누르지 않는지 본다
	Economy.rng.seed = 3
	Economy.changed.emit()

	# (s) 주점 탭 → 모집 창. 연타의 두 번째 누름(연 직후 [10회 모집] 자리)은 버린다. [1회 모집] → 골드 300↓, 영웅 +1, 결과 카드 1장 → [확인]
	var tp := _building_px("tavern")
	var hit: Dictionary = _picker._pick(tp, PickerScript.LAYER_TAP)
	_check(not hit.is_empty() and hit.collider.get_meta("building", "") == "tavern" and not _open_hero(tp), "(s) precondition: tavern tap point hits the tavern body", "px=%s" % tp)
	var copies0 := _copies()
	await _tap(tp)
	await _frames(2)
	_check(recruit.is_open() and _picker.selected == null, "(s) tavern tap opens the recruit window", "open=%s" % recruit.is_open())
	_check(not recruit.ten_button.disabled and recruit.is_guarded(), "(s) precondition: [10회 모집] is on at 2700 gold and the window is still in its open guard",
		"ten disabled=%s guarded=%s" % [recruit.ten_button.disabled, recruit.is_guarded()])
	await _tap(recruit.ten_button.get_global_rect().get_center())
	await _frames(2)
	_check(Economy.gold_tenths == 27005 and _copies() == copies0 and not recruit.is_showing_results() and recruit.is_open(),
		"(s) double tap: a press on [10회 모집] right after the window opens is ignored (gold unchanged)",
		"tenths=%d copies=%d->%d results=%s" % [Economy.gold_tenths, copies0, _copies(), recruit.is_showing_results()])
	await _guard_wait()
	Economy.gold_tenths = 3005  # 300.5골드: 1회만 된다
	Economy.changed.emit()
	_check(not recruit.one_button.disabled and recruit.ten_button.disabled and recruit.rates_text() == "SSR 3% · SR 17% · R 80%",
		"(s) rates line; [1회 300] on, [10회 2700] off at 300 gold", "one=%s ten=%s rates=%s" % [recruit.one_button.disabled, recruit.ten_button.disabled, recruit.rates_text()])
	await _tap(recruit.one_button.get_global_rect().get_center())
	await _frames(2)
	_check(Economy.gold_tenths == 5 and Economy.gold == 0 and _copies() == copies0 + 1 and recruit.is_showing_results() and recruit.cards.size() == 1
		and recruit.cards[0].hero_id != "" and int(Economy.heroes.get(recruit.cards[0].hero_id, 0)) >= 1,
		"(s) [1회 모집] takes 300 gold (3000 tenths), adds one hero and shows one result card",
		"tenths=%d copies=%d->%d cards=%d" % [Economy.gold_tenths, copies0, _copies(), recruit.cards.size()])
	await _tap(recruit.confirm_button.get_global_rect().get_center())  # 결과가 막 떴다(오프라인은 곧바로) — 보호 시간
	_check(recruit.is_showing_results(), "(s) a press on [확인] right after the results appear is ignored (results stay up)", "")
	await _guard_wait()
	await _tap(recruit.confirm_button.get_global_rect().get_center())
	_check(recruit.is_open() and not recruit.is_showing_results() and recruit.one_button.disabled, "(s) [확인] goes back; [1회] is off at 0 gold", "")

	# (t) 하단 탭 바(개정 13 §7.1): 탭 4개(영웅·병사·모집·상인, [성] 없음), 건물 탭으로 연 모집 창도 [모집] 선택(올라옴). 창이 열린 동안
	#     끌기는 카메라를 못 움직이고, 탭 바는 창 위에서도 동작한다: [상인] → 모집 창 닫고 거래 창, 같은 탭 다시 → 닫고 선택 없음,
	#     [병사] → 병사 시트(아직 병사 없음), 다시 → 닫힘
	var merchant: Node = null
	for c in _main.get_children():
		if c.get_script() == preload("res://scripts/merchant_panel.gd"):
			merchant = c
	var bar_rect: Rect2 = tabs._bar.get_global_rect()
	var big: Rect2 = hud._button.get_global_rect()
	_check(tabs.buttons.keys() == ["hero", "soldier", "recruit", "merchant"] and tabs.selected == "recruit" and tabs.buttons.recruit.offset_top < tabs.buttons.hero.offset_top,
		"(t) the tab bar has 영웅·병사·모집·상인; the tavern-opened recruit window selects [모집] (raised)", "tabs=%s selected=%s" % [tabs.buttons.keys(), tabs.selected])
	var title: Rect2 = hud._stage_label.get_global_rect()
	_check(is_equal_approx(bar_rect.end.y, 1280.0) and is_equal_approx(bar_rect.size.y, hud.TAB_BAR_H) and big.end.y < 300.0 and big.position.x > title.end.x
		and big.end.x < 600.0 and absf(big.get_center().y - title.get_center().y) < 8.0 and absf(big.size.y - 64.0) < 1.0,
		"(t) the tab bar is the bottom 104 px; the stage button sits at the top, right of the stage title on the same row (64 px tall)",
		"bar=%s button=%s title=%s" % [bar_rect, big, title])
	var cam_pos: Vector3 = rig.position
	var dp: Vector2 = recruit.dialog.get_global_rect().position + Vector2(300, 20)
	_mouse_button(dp, true)
	for i in 6:
		_mouse_motion(dp + Vector2(0, 12) * (i + 1), Vector2(0, 12))
	_mouse_button(dp + Vector2(0, 72), false)
	await _frames(2)
	_check(rig.position == cam_pos, "(t) dragging on the window does not pan the camera", "pos=%s" % rig.position)
	await _guard_wait()
	await _tap(_tab_px(tabs, "merchant"))
	_check(not recruit.is_open() and merchant.is_open() and tabs.selected == "merchant", "(t) [상인] works over the open recruit window: it closes it and opens the trade window",
		"recruit=%s merchant=%s selected=%s" % [recruit.is_open(), merchant.is_open(), tabs.selected])
	await _tap(_tab_px(tabs, "hero"))  # 연 직후 보호 시간: 탭 바 누름도 버린다
	_check(merchant.is_open(), "(t) a tab press right after a window opens is ignored too", "")
	await _guard_wait()
	await _tap(_tab_px(tabs, "merchant"))
	_check(not merchant.is_open() and tabs.selected == "" and _picker.selected == null, "(t) the selected tab again closes its window and no tab is selected (battlefield)", "selected=%s" % tabs.selected)
	await _tap(_tab_px(tabs, "recruit"))
	_check(recruit.is_open() and tabs.selected == "recruit", "(t) [모집] opens the recruit window", "")
	await _guard_wait()
	var soldiers: Node = tabs.windows.soldier
	await _tap(_tab_px(tabs, "soldier"))
	var sheet0: Rect2 = soldiers.dialog.get_global_rect()
	_check(soldiers.is_open() and not recruit.is_open() and tabs.selected == "soldier" and soldiers.empty_label.visible and soldiers.rows.is_empty()
		and soldiers.summary_label.text == "배치 0 / 6 (인구)" and sheet0.end.y <= bar_rect.position.y and sheet0.size.y > 1000.0,
		"(t) [병사] closes the recruit window and opens the soldier sheet above the tab bar (no soldiers yet: 배치 0 / 6, 보유한 병사가 없습니다)",
		"open=%s selected=%s summary=%s sheet=%s" % [soldiers.is_open(), tabs.selected, soldiers.summary_label.text, sheet0])
	await _guard_wait()
	await _tap(_tab_px(tabs, "soldier"))
	_check(not recruit.is_open() and not merchant.is_open() and not heroes_win.is_open() and not soldiers.is_open() and tabs.selected == "" and _picker.selected == null,
		"(t) [병사] again closes it; every window is closed and the press does not reach the battlefield", "selected=%s" % tabs.selected)

	# (t) 탭 바 위 마우스 휠은 카메라 줌으로 새지 않는다
	var zoom0 := _camera.size
	var wheel_at: Vector2 = tabs._bar.get_global_rect().get_center()
	for pressed in [true, false]:
		var we := InputEventMouseButton.new()
		we.button_index = MOUSE_BUTTON_WHEEL_UP
		we.pressed = pressed
		we.position = wheel_at
		we.global_position = wheel_at
		get_viewport().push_input(we, true)
	await _frames(2)
	_check(_camera.size == zoom0, "(t) the mouse wheel over the tab bar does not zoom the camera", "size %.1f -> %.1f" % [zoom0, _camera.size])

	# (u) [영웅] → 영웅 목록 시트(칩 줄 아래 ~ 탭 바 위). 연 직후 누름은 버린다. 슬롯 4칸, 카드 = 보유, 기본 정렬 전투력 ↓,
	#     카드에 Lv·별·전투력·"배치"·▲(레벨업 가능할 때만). [정렬]: 전투력 → 등급 → 레벨 → 전투력
	Economy.heroes["arteon"] = 3  # 승급 1(개정 15), 조각 2
	Economy.hero_shards["arteon"] = 2
	Economy.hero_promotions["arteon"] = 1
	Economy.gold_tenths = 0
	Economy.res["food"] = 0
	Economy.roster_changed.emit()
	await _tap(_tab_px(tabs, "hero"))
	await _frames(2)
	_check(heroes_win.is_open() and heroes_win.is_guarded() and tabs.selected == "hero", "(u) precondition: [영웅] just opened the hero list (open guard)", "")
	await _tap(heroes_win.slot_cards[0].get_global_rect().get_center())  # 연타의 두 번째 누름이 슬롯 카드에 떨어진다
	_check(heroes_win.selected_slot == -1, "(u) a card press right after the hero list opens is ignored", "sel=%d" % heroes_win.selected_slot)
	await _guard_wait()
	var sheet: Rect2 = heroes_win.dialog.get_global_rect()
	_check(sheet.position.y >= hud._chip_row.get_global_rect().end.y and sheet.end.y <= bar_rect.position.y and sheet.size.x > 680.0 and sheet.size.y > 1000.0,
		"(u) the sheet fills the space between the chip row and the tab bar", "sheet=%s" % sheet)
	var world_px := Vector2(30, 700)  # (q)의 바닥 지점 — 시트 안
	var hero_states := get_tree().get_nodes_in_group("heroes").map(func(h): return [h.side, h.post, h.free_pos])
	_picker._select(get_tree().get_nodes_in_group("heroes")[0])
	await _tap(world_px)
	_check(heroes_win.is_open() and sheet.has_point(world_px) and get_tree().get_nodes_in_group("heroes").map(func(h): return [h.side, h.post, h.free_pos]) == hero_states,
		"(u) a tap inside the sheet does not reach the battlefield (no hero move) and keeps the sheet open", "")
	_picker._select(null)
	var keys: Array = heroes_win.hero_cards.keys()
	var powers: Array = keys.map(func(id): return heroes_win.hero_cards[id].power)
	var desc := powers.duplicate()
	desc.sort()
	desc.reverse()
	_check(heroes_win.slot_cards.size() == 4 and keys.size() == Economy.heroes.size() and powers == desc and powers[-1] > 0 and heroes_win.sort_button.text == "정렬: 전투력",
		"(u) 4 slots and every owned hero, sorted by power (highest first)", "keys=%s powers=%s" % [keys, powers])
	var ac = heroes_win.hero_cards.arteon
	_check(ac.level == 1 and ac.stars == 1 and ac.power == GameData.hero_power(GameData.hero("arteon"), 1, 1) and not ac.deployed and heroes_win.hero_cards.hans.deployed
		and not ac.can_level and heroes_win.slot_cards.map(func(c): return c.hero_id) == ["hans", "ella", "dorik", "nina"] and heroes_win.apply_button.disabled,
		"(u) cards show Lv, stars, power and the 배치 badge; no ▲ without gold; [적용] off", "power=%d" % ac.power)
	Economy.gold_tenths = 100000
	Economy.res["food"] = 1000
	Economy.changed.emit()
	_check(heroes_win.hero_cards.arteon.can_level and heroes_win.hero_cards.hans.can_level, "(u) ▲ appears once a level-up is affordable", "")
	var sorts := []
	for i in 3:
		await _tap(heroes_win.sort_button.get_global_rect().get_center())
		sorts.append(heroes_win.sort_mode)
	var by_grade: Array = heroes_win.owned_sorted("grade").map(func(id): return GameData.hero(id).grade)
	_check(sorts == ["grade", "level", "power"] and heroes_win.sort_button.text == "정렬: 전투력" and by_grade[0] == "SSR" and by_grade[-1] == "R",
		"(u) [정렬] cycles power -> grade -> level -> power", "sorts=%s grades=%s" % [sorts, by_grade])
	Economy.gold_tenths = 0
	Economy.res["food"] = 0
	Economy.changed.emit()

	# (v) 슬롯 1 탭 → 아르테온 카드 탭 = 슬롯 1에 배치. 슬롯 2 탭 → 아르테온 카드 탭 = 서로 바꿈
	await _tap(heroes_win.slot_cards[0].get_global_rect().get_center())
	_check(heroes_win.selected_slot == 0 and heroes_win.slot_cards[0].highlight, "(v) slot tap selects the slot", "sel=%d" % heroes_win.selected_slot)
	await _tap(heroes_win.hero_cards.arteon.get_global_rect().get_center())
	_check(heroes_win.work == ["arteon", "ella", "dorik", "nina"] and heroes_win.selected_slot == -1 and not heroes_win.apply_button.disabled,
		"(v) then a hero card tap places it in that slot", "work=%s" % [heroes_win.work])
	await _tap(heroes_win.slot_cards[1].get_global_rect().get_center())
	await _tap(heroes_win.hero_cards.arteon.get_global_rect().get_center())
	_check(heroes_win.work == ["ella", "arteon", "dorik", "nina"], "(v) placing a hero that sits in another slot swaps the two", "work=%s" % [heroes_win.work])
	_check(Economy.deploy == ["hans", "ella", "dorik", "nina"], "(v) nothing is applied before [적용]", "deploy=%s" % [Economy.deploy])

	# (w) [적용] → 배치 저장, 방치 모드라 영웅이 곧바로 바뀐다(아르테온 승급 1: HP × 1.5)
	var pre := get_tree().get_nodes_in_group("heroes")
	pre.sort_custom(func(a, b): return a.index < b.index)
	await _tap(heroes_win.apply_button.get_global_rect().get_center())
	await _frames(2)
	var live := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.is_alive())
	live.sort_custom(func(a, b): return a.index < b.index)
	var ids := live.map(func(h): return h.def.id)
	_check(Economy.deploy == ["ella", "arteon", "dorik", "nina"] and heroes_win.apply_button.disabled and ids == ["ella", "arteon", "dorik", "nina"]
		and is_equal_approx(live[1].hp_max, 1040.0 * 1.5) and live[1].side == 1 and live[1].post == Formation.POST_GATE and hud._toast.visible,
		"(w) [적용] saves the deploy and, in idle mode, swaps the heroes at once (arteon slot 2 at the east gate, promotion x1.5)",
		"deploy=%s ids=%s" % [Economy.deploy, ids])
	_check(not is_instance_valid(pre[0]) and not is_instance_valid(pre[1]) and live[2] == pre[2] and live[3] == pre[3],
		"(w) only the changed slots are rebuilt: slots 1-2 are new heroes, slots 3-4 keep theirs", "")
	await _heroes_detail(heroes_win, tabs, hud, recruit)


## (x) 영웅 상세·레벨업(개정 11, 오프라인): 카드 탭 → 상세(연 직후처럼 보호), 능력치와 다음 레벨 미리보기, 스킬·설명문,
##     [레벨업] → 골드·식량↓·레벨↑·연출, 방치 모드라 그 영웅만 곧바로 새 능력치로, [×10] 실제 횟수·총비용, 비활성 이유,
##     [배치] 문구, [다음]·스와이프, [닫기] → 목록, 배경 탭으로 닫힘.
func _heroes_detail(heroes_win, tabs, hud, recruit) -> void:
	var arteon := GameData.hero("arteon")
	await _tap(heroes_win.hero_cards.arteon.get_global_rect().get_center())
	await _frames(2)
	_check(heroes_win.is_showing_detail() and heroes_win.detail_id == "arteon" and heroes_win.is_guarded() and heroes_win.work == ["ella", "arteon", "dorik", "nina"],
		"(x) a card tap (no slot picked) opens its detail and re-arms the open guard", "detail=%s" % heroes_win.detail_id)
	_check(heroes_win.stat_values[0].text == "1,560" and heroes_win.stat_nexts[0].text == "→ 1,654 (+94)" and heroes_win.stat_values[1].text == "63"
		and heroes_win.stat_nexts[1].text == "→ 67 (+4)" and heroes_win.stat_values[2].text == "0.8초" and heroes_win.stat_nexts[2].text == ""
		and heroes_win.stat_values[4].text == UiKit.commas(GameData.hero_power(arteon, 1, 1)) and heroes_win.level_label.text == "Lv 1 / 30",
		"(x) stats with the promotion bonus x1.5 and the next level in green (HP 1,560 -> 1,654 (+94)); Lv 1 / 30 at promotion 1",
		"hp=%s next=%s atk=%s level=%s" % [heroes_win.stat_values[0].text, heroes_win.stat_nexts[0].text, heroes_win.stat_values[1].text, heroes_win.level_label.text])
	var sk: Array = heroes_win.skill_ui.map(func(u): return u.label.text)  # 개정 17: ★1이면 스킬 1만 열림
	_check(sk[0].contains("6초마다 반경 6m") and sk[1] == "철벽 — ★3에서 해금" and sk[2] == "용기의 오라 — ★5에서 해금" and heroes_win.desc_label.text == arteon.desc
		and heroes_win.title_label.text == "빛의 성기사 아르테온" and heroes_win.grade_label.text.begins_with("SSR"),
		"(x) title, grade, the unlocked skill sentence with numbers, the locked ones with their star, and the description", "skills=%s" % [sk])
	_check(heroes_win.level_button.disabled and heroes_win.ten_button.disabled and heroes_win.reason_label.text == "골드 부족" and heroes_win.deploy_button.text == "배치 중"
		and heroes_win.deploy_button.disabled, "(x) no gold: [레벨업]·[×10] off with the reason; a deployed hero shows 배치 중", "reason=%s" % heroes_win.reason_label.text)
	var c1 := GameData.levelup_cost("SSR", 1)
	Economy.gold_tenths = int(c1.gold) * 10 + 5
	Economy.res["food"] = 0  # 식량 없이도 된다(개정 12)
	Economy.changed.emit()
	await _tap(heroes_win.level_button.get_global_rect().get_center())  # 아직 보호 시간
	_check(Economy.level_of("arteon") == 1, "(x) a press on [레벨업] right after the detail opens is ignored", "")
	await _guard_wait()
	_check(not heroes_win.level_button.disabled and heroes_win._one.gold.text == "120" and not heroes_win._one.has("food") and heroes_win.reason_label.text == "",
		"(x) [레벨업] shows its gold cost inside (120, no food)", "gold=%s" % heroes_win._one.gold.text)
	var pre := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.is_alive())
	pre.sort_custom(func(a, b): return a.index < b.index)
	await _tap(heroes_win.level_button.get_global_rect().get_center())
	await _frames(2)
	var live := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.is_alive())
	live.sort_custom(func(a, b): return a.index < b.index)
	_check(Economy.level_of("arteon") == 2 and Economy.gold_tenths == 5 and Economy.res["food"] == 0 and heroes_win.level_label.text == "Lv 2 / 30"
		and heroes_win.stat_values[0].text == "1,654" and heroes_win.celebrations == 1 and heroes_win.big_card.is_bursting()
		and heroes_win.stat_values[0].get_theme_color("font_color") != HudScript.INK and heroes_win.stat_values[2].get_theme_color("font_color") == HudScript.INK,
		"(x) [레벨업] takes 120 gold (1200 tenths) and no food, Lv 2, light burst, changed stats flash green",
		"level=%d tenths=%d food=%d label=%s" % [Economy.level_of("arteon"), Economy.gold_tenths, Economy.res["food"], heroes_win.level_label.text])
	_check(live.size() == 4 and live[1].def.id == "arteon" and live[1] != pre[1] and is_equal_approx(live[1].hp_max, 1040.0 * 1.06 * 1.5)
		and is_equal_approx(live[1].atk, 42.0 * 1.06 * 1.5) and live[0] == pre[0] and live[2] == pre[2] and live[3] == pre[3],
		"(x) idle mode rebuilds only the leveled hero with HP/atk x(1 + 0.06) x 1.5", "hp=%.1f" % live[1].hp_max)
	var c3 := GameData.levelup_cost("SSR", 2, 3)
	Economy.gold_tenths = int(c3.gold) * 10
	Economy.res["food"] = 0
	Economy.changed.emit()
	_check(heroes_win._ten.title.text == "×10 (3회)" and heroes_win._ten.gold.text == UiKit.commas(c3.gold) and not heroes_win.ten_button.disabled,
		"(x) [×10] shows the affordable count (3) and its total cost", "title=%s gold=%s" % [heroes_win._ten.title.text, heroes_win._ten.gold.text])
	await _tap(heroes_win.ten_button.get_global_rect().get_center())
	await _frames(2)
	_check(Economy.level_of("arteon") == 5 and Economy.gold_tenths == 0 and Economy.res["food"] == 0 and heroes_win.celebrations == 2 and heroes_win.level_label.text == "Lv 5 / 30",
		"(x) [×10] raises 3 levels for the summed cost", "level=%d tenths=%d" % [Economy.level_of("arteon"), Economy.gold_tenths])
	# 이전·다음: [다음]은 목록 순서로 다음 영웅, 오른쪽으로 끌면 이전
	var order: Array = heroes_win.order
	var at := order.find("arteon")
	await _tap(heroes_win.next_button.get_global_rect().get_center())
	var nxt: String = heroes_win.detail_id
	var sp: Vector2 = heroes_win.stat_values[0].get_global_rect().get_center()
	_mouse_button(sp, true)
	for i in 5:
		_mouse_motion(sp + Vector2(40, 0) * (i + 1), Vector2(40, 0))
	_mouse_button(sp + Vector2(200, 0), false)
	await _frames(2)
	_check(order.size() >= 2 and nxt == order[(at + 1) % order.size()] and heroes_win.detail_id == "arteon", "(x) [다음] goes to the next hero in list order, a right swipe back",
		"order=%s next=%s now=%s" % [order, nxt, heroes_win.detail_id])
	heroes_win.show_detail("hans")  # 배치되지 않은 영웅, 빈 슬롯 없음
	_check(heroes_win.deploy_button.text == "빈 슬롯 없음" and heroes_win.deploy_button.disabled, "(x) [배치] with no empty slot is off", "text=%s" % heroes_win.deploy_button.text)
	await _guard_wait()
	await _figures(heroes_win)
	await _promotion_ui(heroes_win, recruit)
	await _skill_unlock_ui(heroes_win)
	await _guard_wait()  # _figures가 창을 다시 열어 0.4초 보호가 다시 걸린다
	await _tap(heroes_win.prev_button.get_parent().get_child(1).get_global_rect().get_center())  # [닫기]
	_check(heroes_win.is_open() and not heroes_win.is_showing_detail() and heroes_win.is_guarded() and heroes_win.hero_cards.arteon.level == 5,
		"(x) [닫기] returns to the list (guarded); the card shows Lv 5", "")
	await _guard_wait()
	await _tap(Vector2(30, 40))  # 위 칩 줄 높이 — 시트 바깥 배경
	_check(not heroes_win.is_open() and tabs.selected == "", "(x) a backdrop tap above the sheet closes it and no tab is selected", "")

	# (y) 늦게 온 모집 결과(온라인): 다른 창이 열려 있으면 그 위로 모집 창을 열지 않고 알림, 다음에 주점 창을 열 때 보여 준다.
	#     아무 창도 없으면 모집 창을 열어 보여 준다.
	var late := [{"hero_id": "jack", "grade": "R", "new": false, "copies": 2, "shards": 1}]
	heroes_win.open()
	recruit._on_gacha_done(late)
	_check(not recruit.is_open() and heroes_win.is_open() and hud._toast.visible and hud._toast.text == recruit.LATE_TEXT,
		"(y) a late gacha result does not open the recruit window over the hero window; a notice says it arrived",
		"recruit=%s heroes=%s toast=%s" % [recruit.is_open(), heroes_win.is_open(), hud._toast.text])
	heroes_win.close()
	recruit.open()
	_check(recruit.is_showing_results() and recruit.cards.size() == 1 and recruit.cards[0].hero_id == "jack", "(y) the next recruit window shows the late result", "")
	recruit.close()
	recruit.open()
	_check(recruit.is_open() and not recruit.is_showing_results(), "(y) the late result is shown once", "")
	recruit.close()
	recruit._on_gacha_done(late)
	_check(recruit.is_showing_results() and recruit.cards[0].hero_id == "jack", "(y) with no other window open, a late result reopens the recruit window", "")
	recruit.close()
	await _guard_wait()
	await _buildings_ui(tabs, hud, recruit)
	await _soldiers_ui(tabs, hud)
	await _soldier_picks()
	await _soldier_figures(tabs)
	await _world_tags()
	await _rotate_ui(hud)
	await _fever_ui(hud)
	await _top_hud(hud)


## (z) 개정 12-2: 상단 스테이지 버튼(탭으로 진행 → 중지 예약 → 예약 취소)과 방향별 성 내구도(성문 막대 탭 → 카메라가 그 성문으로 0.4초,
##     줌 유지, 전장으로 새지 않음). 문루 위 방향 글자. 스테이지를 시작하므로 맨 끝에 둔다.
func _top_hud(hud) -> void:
	var half: float = _main.castle.half
	var rig = _camera.get_parent()
	var wt = _child(preload("res://scripts/world_tags.gd"))
	_check(range(4).map(func(s): return wt.text("gate:%d" % s)) == ["북", "동", "남", "서"]
		and _main.castle.side_anchors.all(func(a): return a.y > Balance.WALL_H + 2.0),
		"(z) direction letters 북·동·남·서 float above the four gatehouses (screen-space tags)", "")
	print("INPUT INFO: stage button %s, title %s, castle bar %s, gate bars %s (720x1280 logical)" % [hud._button.get_global_rect(), hud._stage_label.get_global_rect(),
		hud._castle_bar.get_global_rect(), hud._gate_tiles.map(func(t): return t.get_global_rect())])
	var names: Array = hud._gate_tiles.map(func(t): return t.get_child(0).get_child(1).text)
	var nums: Array = range(4).map(func(s): return hud._hp[s].num.text)
	var full := "%s / %s" % [UiKit.commas(roundi(GameState.gate_hp_max)), UiKit.commas(roundi(GameState.gate_hp_max))]
	_check(names == ["북", "동", "남", "서"] and nums.all(func(s): return s == full) and hud._hp[hud.CASTLE].num.text.contains(" / "),
		"(z) gate bars are named 북·동·남·서 with 'hp / max' inside; the castle bar too", "names=%s nums=%s" % [names, nums])
	var dirs: Array = range(4).map(func(s): return hud.compass_dir(s))
	_check(dirs[0].x > 0.5 and dirs[0].y < -0.5 and dirs[1].x > 0.5 and dirs[1].y > 0.5 and dirs[2].x < -0.5 and dirs[2].y > 0.5 and dirs[3].x < -0.5 and dirs[3].y < -0.5,
		"(z) compass arrows point where each gate is on screen (N up-right, E down-right, S down-left, W up-left)", "dirs=%s" % [dirs])
	# 성문 피해 → 그 막대만 번쩍, 부서지면 회색 "파괴". 방치 무적(개정 12 §3)과 무관하게 보려고 잠깐 스테이지 모드로 둔다
	var mode0: int = GameState.mode
	GameState.mode = GameState.Mode.STAGE
	GameState.damage_gate(2, 10.0)
	var flashing: Array = range(4).map(func(s): return hud._hp[s].flash.visible)
	GameState.damage_gate(3, GameState.gate_hp_max)
	GameState.mode = mode0
	_check(flashing == [false, false, true, false] and hud._hp[3].num.text == "파괴" and hud._gate_bars[3].get_theme_stylebox("background") == UiKit.bar(hud.BROKEN_GREY).fill,
		"(z) a damaged gate's bar flashes (only that one); a broken gate turns grey and reads 파괴", "flash=%s text=%s" % [flashing, hud._hp[3].num.text])
	await get_tree().create_timer(hud.FLASH_SEC + 0.1).timeout
	_check(not hud._hp[2].flash.visible, "(z) the flash fades after 0.3 s", "")
	GameState.refill()

	# 성문 막대 탭 → 카메라가 그 성문으로 부드럽게(0.4초), 줌 그대로. 선택한 영웅은 명령을 받지 않는다(HUD가 누름을 먹는다)
	var warrior = get_tree().get_nodes_in_group("heroes").filter(func(h): return h.is_alive())[0]  # (w)에서 바뀐 영웅일 수 있다
	_picker._select(warrior)
	var state := [warrior.side, warrior.post, warrior.free_pos]
	var zoom0 := _camera.size
	var start: Vector3 = rig.position
	var east := Formation.gate_position(half, 1)
	var dest := Vector3(east.x, start.y, east.z)
	var tile: Rect2 = hud._gate_tiles[1].get_global_rect()
	await _tap(tile.get_center())
	var mid: Vector3 = rig.position
	await get_tree().create_timer(0.5).timeout
	_check(start.distance_to(dest) > 5.0 and mid.distance_to(dest) > 0.5 and rig.position.distance_to(dest) < 0.01 and _camera.size == zoom0,
		"(z) tapping the east gate bar glides the camera to the east gate (centered after 0.4 s, zoom kept)",
		"start=%s mid=%s end=%s dest=%s zoom %.1f -> %.1f" % [start, mid, rig.position, dest, zoom0, _camera.size])
	_check(_picker.selected == warrior and [warrior.side, warrior.post, warrior.free_pos] == state, "(z) the gate bar tap does not reach the battlefield (no hero order)",
		"selected=%s" % _name(_picker.selected))
	_picker._select(null)

	# 상단 버튼: 대기 "▶ 진행" → 탭 = 시작 → "■ 중지" → 탭 = 즉시 중지(같은 스테이지, 대기)
	var bp: Vector2 = hud._button.get_global_rect().get_center()
	var st0: int = GameState.stage
	_check(GameState.mode == GameState.Mode.IDLE and hud._button.text == "▶ 진행" and bp.y < 300.0, "(z) idle: the top button reads ▶ 진행", "text=%s at %s" % [hud._button.text, bp])
	await _tap(bp)
	_check(GameState.mode == GameState.Mode.STAGE and hud._button.text == "■ 중지", "(z) tapping it starts the stage; it now reads ■ 중지", "mode=%d text=%s" % [GameState.mode, hud._button.text])
	await _tap(bp)
	_check(GameState.mode == GameState.Mode.IDLE and GameState.stage == st0 and hud._button.text == "▶ 진행", "(z) tapping again stops at once: idle, same stage, reads ▶ 진행", "mode=%d stage=%d text=%s" % [GameState.mode, GameState.stage, hud._button.text])
	# 연속 진행 체크박스: 진행 버튼 오른쪽, 탭 56px 이상, 탭하면 토글(테스트는 저장 안 함), 720 안에 들어간다
	var cr: Rect2 = hud._auto.get_global_rect()
	_check(cr.position.x >= hud._button.get_global_rect().end.x and cr.size.x >= 56.0 and cr.size.y >= 56.0 and cr.end.x <= 720.0 and hud._fever.get_global_rect().end.x <= hud._button.get_global_rect().position.x,
		"(z) header row: fever, 진행, then the 연속 진행 checkbox, all inside 720 px, tap target >= 56", "auto=%s button=%s" % [cr, hud._button.get_global_rect()])
	_check(GameState.auto_continue and hud._auto.button_pressed, "(z) the checkbox starts checked", "")
	await _tap(cr.get_center())
	_check(not GameState.auto_continue and not hud._auto.button_pressed, "(z) tapping the checkbox unchecks it", "")
	await _tap(cr.get_center())
	_check(GameState.auto_continue and hud._auto.button_pressed, "(z) and checks it again", "")


## 하단 탭 바 탭 id의 가운데(화면 좌표).
func _tab_px(tabs, id: String) -> Vector2:
	return tabs.buttons[id].get_global_rect().get_center()


## 창의 연 직후 보호 시간(OPEN_GUARD_MS)이 지나게.
func _guard_wait() -> void:
	await get_tree().create_timer(0.45).timeout


func _copies() -> int:
	var n := 0
	for id in Economy.heroes:
		n += int(Economy.heroes[id])
	return n


func _check(cond: bool, what: String, detail: String) -> void:
	if cond:
		print("INPUT PASS: " + what)
	else:
		_fails += 1
		print("INPUT FAIL: %s (%s)" % [what, detail])


func _name(h) -> String:
	return "null" if h == null else "hero%d/%s" % [h.index, h.role]


func _hero_px(h) -> Vector2:
	return _camera.unproject_position(h.global_position + Vector3(0, 0.8, 0))


func _gate_px(side: int) -> Vector2:
	var half: float = _main.castle.half
	return _camera.unproject_position(Formation.gate_position(half, side) + Vector3(0, Balance.WALL_H / 2.0, 0))


## 성문 옆 벽 토막(+perp 쪽) 중앙.
func _wall_px(side: int) -> Vector2:
	var half: float = _main.castle.half
	var seg_len := half + Balance.WALL_T - Balance.GATE_W / 2.0
	var p := Formation.gate_position(half, side) + Formation.perp(side) * (Balance.GATE_W + seg_len) / 2.0
	return _camera.unproject_position(p + Vector3(0, Balance.WALL_H / 2.0, 0))


## 화면 안이고 성문·성벽 탭 영역이 아니며 HERO_TAP_PX 안에 영웅이 없는 바닥 탭 지점인지.
func _open_ground(px: Vector2) -> bool:
	return get_viewport().get_visible_rect().has_point(px) \
		and _picker._pick(px, PickerScript.LAYER_GATE | PickerScript.LAYER_WALL).is_empty() \
		and _picker._hero_at(px, PickerScript.HERO_TAP_PX) == null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame


func _mouse_button(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	get_viewport().push_input(ev, true)


func _mouse_motion(pos: Vector2, rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.position = pos
	ev.global_position = pos
	ev.relative = rel
	get_viewport().push_input(ev, true)


func _tap(pos: Vector2) -> void:
	_mouse_button(pos, true)
	_mouse_button(pos, false)
	await _frames(2)


func _dragback(pos: Vector2) -> void:
	_mouse_button(pos, true)
	var cur := pos
	for step in [Vector2(8, 0), Vector2(8, 0), Vector2(8, 0), Vector2(-8, 0), Vector2(-8, 0), Vector2(-8, 0)]:
		cur += step
		_mouse_motion(cur, step)
	_mouse_button(pos, false)
	await _frames(2)


## 터치는 창 좌표로 넣어 엔진이 0번 손가락을 마우스로 에뮬레이트하게 한다.
func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = pressed
	ev.position = get_viewport().get_final_transform() * pos
	Input.parse_input_event(ev)
	await _frames(1)


func _drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var xf := get_viewport().get_final_transform()
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = xf * pos
	ev.relative = xf.basis_xform(rel)
	Input.parse_input_event(ev)
	await _frames(1)


## 건물 부지 중심 약간 위(탭 판정체 안)의 화면 좌표.
func _building_px(id: String) -> Vector2:
	var b := Balance.building(id)
	return _camera.unproject_position(Vector3((b.cell.x + b.size.x / 2.0) * Balance.TILE, 1.0, (b.cell.y + b.size.y / 2.0) * Balance.TILE))


## px 근처(HERO_TAP_PX)에 영웅이 있는지 — 영웅 판정이 건물 탭을 가로채지 않는지 사전 확인용.
func _open_hero(px: Vector2) -> bool:
	return _picker._hero_at(px, PickerScript.HERO_TAP_PX) != null


## 건물 창(building_panel.gd). main 자식에서 찾는다.
func _building_win() -> Node:
	for c in _main.get_children():
		if c.get_script() == preload("res://scripts/building_panel.gd"):
			return c
	return null


## px를 LONG_PRESS_MS보다 길게(0.6초) 누른 채 있다가 뗀다. 누른 채 열린 창(건물 id, 없으면 "")을 돌려준다.
func _long_press(px: Vector2, bwin) -> String:
	_mouse_button(px, true)
	await get_tree().create_timer(0.6).timeout
	await _frames(2)
	var held: String = bwin.building_id if bwin.is_open() else ""
	_mouse_button(px, false)
	await _frames(2)
	return held


## (B) 개정 12 §2.5·§4 건물 창·월드 표시(오프라인): 이름표 "이름 Lv N", 길게 누르기 → 누른 채 건물 창(탭·드래그·핀치와 구분, 주점·성문도),
##     성채 상한 비활성 이유, 성채 [업그레이드] → 자원 감소·일꾼·비계·머리 위 막대·매초 남은 시간, 테스트 훅으로 완료 → 레벨·이름표·비계 제거·
##     빛 조각·알림, 다른 건물은 일꾼이 바빠 비활성. (l)·(n)이 탭으로 여는 건 이미 봤다.
func _buildings_ui(tabs, hud, recruit) -> void:
	var bwin = _building_win()
	var scenery: Node = null
	var badges: Node = null
	for c in _main.get_children():
		if c.get_script() == preload("res://scripts/buildings.gd"):
			scenery = c
		elif c.get_script() == preload("res://scripts/badges.gd"):
			badges = c
	var rig = _camera.get_parent()
	_picker._select(null)
	var now := Time.get_unix_time_from_system()
	Economy.res = {"wood": 0, "stone": 0, "food": 0}
	Economy.last_collect["lumber"] = now - 600.0  # 쌓인 목재 100 — 짧은 탭이면 수집
	Economy.changed.emit()
	badges.last_pop = {}
	var lp := _building_px("lumber")
	var wt = _child(preload("res://scripts/world_tags.gd"))
	_check(Economy.levels.values().all(func(l): return l == 1) and Economy.build.is_empty() and wt.text("lumber") == "벌목장 Lv 1"
		and wt.text("keep") == "성채 Lv 1" and scenery.tag_anchors.size() == Balance.BUILDINGS.size()
		and Balance.BUILDINGS.all(func(b): return wt.text(b.id) == "%s Lv 1" % b.name), "(B) every building's name tag reads '이름 Lv N'",
		"lumber=%s keep=%s" % [wt.text("lumber"), wt.text("keep")])

	# 길게 누르기(0.5초): 누른 채 건물 창이 열리고, 뗀 뒤에도 수집하지 않는다. 창을 닫은 뒤 누르지 않은 마우스 움직임은 카메라를 못 옮긴다
	var held: String = await _long_press(lp, bwin)
	_check(held == "lumber" and bwin.is_open() and Economy.res.wood == 0 and badges.last_pop.is_empty(),
		"(B) a 0.5 s long press on the lumber mill (wood waiting) opens its building window while held; the release collects nothing",
		"held=%s open=%s wood=%d" % [held, bwin.is_open(), Economy.res.wood])
	await _guard_wait()
	var cam0: Vector3 = rig.position
	await _tap(bwin.content.get_child(bwin.content.get_child_count() - 1).get_global_rect().get_center())  # [닫기]
	var hover := InputEventMouseMotion.new()
	hover.position = lp + Vector2(60, 40)
	hover.global_position = hover.position
	hover.relative = Vector2(60, 40)
	get_viewport().push_input(hover, true)
	await _frames(2)
	_check(not bwin.is_open() and rig.position == cam0, "(B) [닫기] closes it; afterwards a mouse move without a press does not pan the camera",
		"open=%s cam %s -> %s" % [bwin.is_open(), cam0, rig.position])
	await _tap(lp)
	_check(Economy.res.wood == 100 and not bwin.is_open() and badges.last_pop.get("amount", 0) == 100, "(B) a short tap on the same mill still collects (+100)", "wood=%d" % Economy.res.wood)
	# 누른 채 12 px 넘게 끌고 0.6초: 카메라 이동이지 건물 창이 아니다
	Economy.last_collect["lumber"] = now - 600.0
	var cam1: Vector3 = rig.position
	_mouse_button(lp, true)
	for i in 3:
		_mouse_motion(lp + Vector2(8, 0) * (i + 1), Vector2(8, 0))
	await get_tree().create_timer(0.6).timeout
	await _frames(2)
	_mouse_button(lp + Vector2(24, 0), false)
	await _frames(2)
	_check(not bwin.is_open() and rig.position != cam1 and Economy.res.wood == 100, "(B) press, drag past 12 px and hold 0.6 s pans the camera and opens nothing",
		"open=%s cam %s -> %s wood=%d" % [bwin.is_open(), cam1, rig.position, Economy.res.wood])
	rig.position = cam1
	await _frames(1)
	# 두 번째 손가락(핀치)이 닿은 누름은 0.6초를 채워도 아무것도 열지 않는다
	await _touch(0, lp, true)
	await _touch(1, lp + Vector2(0, 150), true)
	await get_tree().create_timer(0.6).timeout
	await _frames(2)
	await _touch(1, lp + Vector2(0, 150), false)
	await _touch(0, lp, false)
	_check(not bwin.is_open() and Economy.res.wood == 100, "(B) a held press with a second finger down (pinch) opens nothing and collects nothing",
		"open=%s wood=%d" % [bwin.is_open(), Economy.res.wood])
	# 주점·성문 길게 누르기 → 건물 창(주점 탭은 모집 창, 성문 탭은 영웅 명령이 먼저)
	held = await _long_press(_building_px("tavern"), bwin)
	_check(held == "tavern" and not recruit.is_open(), "(B) a long press on the tavern opens its building window, not the recruit window", "held=%s recruit=%s" % [held, recruit.is_open()])
	bwin.close()
	var gp := _gate_px(1)
	_check(get_viewport().get_visible_rect().has_point(gp), "(B) precondition: the east gate is on screen", "px=%s" % gp)
	held = await _long_press(gp, bwin)
	_check(held == "gate" and bwin.title_label.text == "성문 Lv 1" and bwin.effects.get_child(0).get_child(1).text == "→ 800",
		"(B) a long press on a gate opens the gate window (성문 HP 400 → 800)", "held=%s title=%s" % [held, bwin.title_label.text])
	bwin.close()

	# 성채 상한: 성채 Lv 1이면 벌목장 Lv 2는 막힌다 — ✗ 빨강 줄, 비활성 + 이유. 효과·비용·시간 줄
	Economy.last_collect["lumber"] = Time.get_unix_time_from_system()  # 쌓인 게 없다 — 탭이 건물 창을 연다
	await _tap(lp)
	print("INPUT INFO: lumber window (keep cap) dialog %s, [업그레이드] %s" % [bwin.dialog.get_global_rect(), bwin.upgrade_button.get_global_rect()])
	var eff: HBoxContainer = bwin.effects.get_child(0)
	var req: Label = bwin.reqs.get_child(0)
	_check(bwin.is_open() and bwin.title_label.text == "벌목장 Lv 1" and bwin.desc_label.text != "" and eff.get_child(0).text == "생산 10/분" and eff.get_child(1).text == "→ 20/분"
		and req.text == "✗ 성채 Lv 2 필요" and req.get_theme_color("font_color") == bwin.RED and bwin.upgrade_button.disabled
		and bwin.reason_label.text == Economy.BLOCK_TEXT.keep_cap and bwin.reason_label.visible,
		"(B) lumber window at keep Lv 1: title, 생산 10/분 → 20/분, red '✗ 성채 Lv 2 필요', [업그레이드] off with the keep-cap reason",
		"title=%s eff=%s req=%s reason=%s" % [bwin.title_label.text, [eff.get_child(0).text, eff.get_child(1).text], req.text, bwin.reason_label.text])
	_check(bwin.cost_labels.wood.text == "60" and bwin.cost_labels.wood.get_theme_color("font_color") == HudScript.INK and bwin.cost_labels.stone.text == "80"
		and bwin.cost_labels.stone.get_theme_color("font_color") == bwin.RED and bwin.time_label.text == "건설 시간 00:20" and not bwin._progress_box.visible,
		"(B) cost 60/80/40 with icons (stone short = red, wood 100 ok), 건설 시간 00:20",
		"wood=%s stone=%s time=%s" % [bwin.cost_labels.wood.text, bwin.cost_labels.stone.text, bwin.time_label.text])
	_check(bwin.effect_lines("houses", 1) == [["인구", "6", "8"]] and bwin.effect_lines("barracks", 1) == [["1마리", "3:00:00", "2:30:00"]]
		and bwin.effect_lines("stable", 3) == [["1마리", "2:00:00", "1:30:00"]] and bwin.effect_lines("barracks", 6) == [["1마리", "30:00", "T2 3:00:00"]] and bwin.effect_lines("lab", 2)[0] == ["영웅 공격", "+3%", "+6%"]
		and UiKit.duration(3900) == "1시간 5분" and UiKit.duration(59.2) == "01:00",
		"(B) effect sentences: 인구 6 → 8, soldier buildings 1마리 3:00:00 → 2:30:00 (Lv 6 30:00 → T2 3:00:00), lab +3% → +6%; times mm:ss / h시간 m분",
		"%s %s" % [bwin.effect_lines("barracks", 1), bwin.effect_lines("stable", 3)])
	bwin.close()

	# 성채 [업그레이드]: 자원 300/300/200 감소, 일꾼 = 성채, 비계(기둥 4 + 가로대, AABB 둘레), 머리 위 막대, 창은 진행 막대 + 매초 남은 시간
	Economy.res = {"wood": 1000, "stone": 1000, "food": 1000}
	Economy.changed.emit()
	await _tap(_building_px("keep"))
	var rows: Array = bwin.reqs.get_children().map(func(l): return l.text)
	print("INPUT INFO: keep window (Lv 1, can upgrade) dialog %s, [업그레이드] %s" % [bwin.dialog.get_global_rect(), bwin.upgrade_button.get_global_rect()])
	_check(bwin.building_id == "keep" and rows == ["✓ 성문 Lv 1 필요", "✓ 보병 막사 Lv 1 필요"] and bwin.reqs.get_child(0).get_theme_color("font_color") == bwin.GREEN
		and not bwin.upgrade_button.disabled and not bwin.reason_label.visible and bwin.time_label.text == "건설 시간 01:00"
		and bwin.effects.get_child(1).get_child(0).text == "성 HP 1,000" and bwin.effects.get_child(1).get_child(1).text == "→ 1,200" and bwin.effects.get_child_count() == 2,
		"(B) keep window: green ✓ prerequisites, 성 HP 1,000 → 1,200, no slot/area lines at Lv 1 (they do not change), [업그레이드] on, 01:00", "reqs=%s" % [rows])
	var names := func(lv: int) -> Array: return bwin.effect_lines("keep", lv).map(func(r): return r[0])
	_check(names.call(1) == ["건물 최대", "성 HP"] and bwin.effect_lines("keep", 4).slice(2) == [["영웅 슬롯", "4", "8"], ["성 넓이", "20칸", "24칸"]]
		and names.call(5) == ["건물 최대", "성 HP"] and names.call(9).size() == 4 and names.call(30) == ["건물 최대", "성 HP"],
		"(B) keep slot/area lines only when the next level changes them: Lv 1 none, Lv 4 → 5 영웅 슬롯 4 → 8 and 성 넓이 20칸 → 24칸, Lv 5 none, Lv 9 → 10 both, max level none",
		"Lv1=%s Lv4=%s Lv30=%s" % [names.call(1), bwin.effect_lines("keep", 4), names.call(30)])
	await _guard_wait()
	await _tap(bwin.upgrade_button.get_global_rect().get_center())
	var keep_box: AABB = scenery.sites.keep[0]
	var sc: MeshInstance3D = scenery._scaffolds[0] if scenery._scaffolds.size() == 1 else null
	var sbox := AABB(sc.position + sc.mesh.get_aabb().position, sc.mesh.get_aabb().size) if sc != null else AABB()
	_check(Economy.res == {"wood": 700, "stone": 700, "food": 800} and Economy.is_building("keep") and bwin.upgrade_button.disabled and bwin._progress_box.visible
		and not bwin._cost_row.visible and bwin.left_label.text.begins_with("Lv 1 → 2 건설 중"),
		"(B) [업그레이드] takes 300/300/200, the builder works on the keep; the window swaps cost for a progress bar", "res=%s build=%s" % [Economy.res, Economy.build])
	_check(scenery.scaffold_id == "keep" and sc != null and sbox.encloses(keep_box) and sbox.size.x > keep_box.size.x and badges.build_anchors().size() == 1
		and badges.build_anchors()[0].y > keep_box.end.y, "(B) a scaffold rings the keep's AABB and the progress bar anchor sits above its roof", "scaffold=%s keep=%s" % [sbox, keep_box])
	var t0: String = bwin.left_label.text
	var p0: float = bwin.progress.value
	await get_tree().create_timer(1.1).timeout
	_check(bwin.left_label.text != t0 and bwin.progress.value > p0, "(B) the remaining time and bar tick every second", "%s -> %s" % [t0, bwin.left_label.text])
	bwin.close()
	await _tap(lp)  # 다른 건물: 성채 상한이 먼저
	_check(bwin.building_id == "lumber" and bwin.reason_label.text == Economy.BLOCK_TEXT.keep_cap, "(B) while the keep builds, the lumber mill still shows the keep cap first", bwin.reason_label.text)
	bwin.close()

	# 시간 당기기(테스트 훅) → 성채 Lv 2: 비계 걷힘, 이름표, 빛 조각, 알림
	var fx0: int = get_tree().get_nodes_in_group("fx").size()
	Economy.finish_build_now()
	await _frames(1)
	_check(Economy.building_level("keep") == 2 and Economy.build.is_empty() and scenery.scaffold_id == "" and scenery._scaffolds.is_empty() and badges.build_anchors().is_empty()
		and wt.text("keep") == "성채 Lv 2" and get_tree().get_nodes_in_group("fx").size() >= fx0 + 5 and hud._toast.visible and hud._toast.text == "성채 Lv 2 완료",
		"(B) pulling the time in completes it: keep Lv 2, scaffold gone, tag '성채 Lv 2', light shards, notice '성채 Lv 2 완료'",
		"keep=%d scaffold=%s tag=%s fx=%d->%d toast=%s" % [Economy.building_level("keep"), scenery.scaffold_id, wt.text("keep"), fx0,
			get_tree().get_nodes_in_group("fx").size(), hud._toast.text])

	# 벌목장 업그레이드 → 다른 건물(채석장)은 일꾼이 바빠 비활성(무엇을 짓는지·남은 시간)
	await _tap(lp)
	_check(bwin.building_id == "lumber" and not bwin.upgrade_button.disabled and bwin.reqs.get_child(0).text == "✓ 성채 Lv 2 필요", "(B) at keep Lv 2 the lumber upgrade is on", bwin.reason_label.text)
	await _guard_wait()
	await _tap(bwin.upgrade_button.get_global_rect().get_center())
	_check(Economy.is_building("lumber") and Economy.res.wood == 640 and Economy.res.stone == 620, "(B) the lumber upgrade pays 60/80/40", "res=%s" % [Economy.res])
	bwin.close()
	Economy.last_collect["quarry"] = Time.get_unix_time_from_system()  # 쌓인 석재 없음 — 탭이 건물 창
	await _tap(_building_px("quarry"))
	_check(bwin.building_id == "quarry" and bwin.upgrade_button.disabled and bwin.reason_label.text.begins_with(Economy.BLOCK_TEXT.builder_busy + " (벌목장 00:"),
		"(B) another building is off while the builder works: '다른 건물 건설 중 (벌목장 00:20)'", bwin.reason_label.text)
	bwin.close()
	Economy.finish_build_now()
	await _frames(1)
	_check(Economy.building_level("lumber") == 2 and wt.text("lumber") == "벌목장 Lv 2" and hud._toast.text == "벌목장 Lv 2 완료", "(B) lumber Lv 2 completes with its notice", hud._toast.text)

	# 성문 건설은 네 문루를 모두 두른다
	Economy.build = {"id": "gate", "finish": Economy.time_now() + 45.0}
	Economy.changed.emit()
	_check(scenery._scaffolds.size() == 4 and badges.build_anchors().size() == 4, "(B) a gate upgrade rings all four gatehouses with scaffolds and bars", "n=%d" % scenery._scaffolds.size())
	var errors0: int = _errors.count
	for f in [0.005, 0.02, 0.03, 0.05, 0.08, 0.5, 1.0]:  # 막대 채움이 아주 가늘 때도 다각형이 깨지지 않는다(그리기 오류는 ErrorCounter가 센다)
		Economy.build.finish = Economy.time_now() + 45.0 * (1.0 - f)
		await _frames(2)
	_check(_errors.count == errors0, "(B) the overhead bar draws cleanly from a sliver to full", "errors=%d" % (_errors.count - errors0))
	Economy.build = {}
	Economy.changed.emit()
	print("INPUT INFO: tabs %s (720x1280 logical)" % [tabs.buttons.values().map(func(b): return b.get_global_rect())])


## (S) 개정 13 §6 병사 UI(오프라인) + 사용자 규칙(2026-10-02): [병사] 시트 — 행 순서(강한 순)·[+]·[−]·보유 상한·인구 상한·[적용](방치 모드라
##     곧바로 성채 앞)·[모두 해제]·[자동 배치]·아래 건물 상태 줄 없음·행 [합성 5→1](불가 이유)·성공 연출·배치 자르기·최대 티어·시트 안 탭/끌기는
##     뒤로 안 샌다. 보병 막사 길게 누르기 → 1마리 시간·훈련 칸(합성 칸 없음). 훈련(개정 16 §3): 수량 [+]·[최대]·입력 → 총비용·총시간 →
##     [훈련](자원↓, 진행 막대·월드 막대) → 시간 당기기(테스트 훅) → 완료 칸·병사 말풍선 → 건물 탭 수령(보유↑, 알림) → [취소] 50% 환불.
func _soldiers_ui(tabs, hud) -> void:
	var sw = tabs.windows.soldier
	var bwin = _building_win()
	var badges = _child(preload("res://scripts/badges.gd"))
	var rig = _camera.get_parent()
	_picker._select(null)
	Economy.levels["houses"] = 1  # 인구 6
	Economy.soldiers = {"infantry:1": 5, "archer:1": 3, "cavalry:2": 1, "infantry:2": 4}
	Economy.soldier_deployed = {}
	Economy.soldiers_changed.emit()
	await _tap(_tab_px(tabs, "soldier"))
	await _guard_wait()
	print("INPUT INFO: soldier sheet %s, [+] rows %s, [합성] rows %s, [자동 배치] %s, [적용] %s (720x1280 logical)" % [sw.dialog.get_global_rect(),
		sw.rows.values().map(func(r): return r.plus.get_global_rect()), sw.rows.values().map(func(r): return r.merge.get_global_rect()),
		sw.auto_button.get_global_rect(), sw.apply_button.get_global_rect()])
	var keys: Array = sw.rows.keys()
	_check(sw.is_open() and GameState.mode == GameState.Mode.IDLE and keys == ["infantry:2", "cavalry:2", "infantry:1", "archer:1"] and sw.summary_label.text == "배치 0 / 6 (인구)"
		and sw.rows["archer:1"].have.text == "보유 3" and sw.rows["infantry:1"].minus.disabled and sw.apply_button.disabled and sw.clear_button.disabled and not sw.empty_label.visible,
		"(S) [병사] sheet: rows strongest first (tier, then 보병 -> 기병 -> 궁병), 배치 0 / 6 (인구), 보유 N; [−]·[모두 해제]·[적용] off",
		"keys=%s summary=%s" % [keys, sw.summary_label.text])
	var status: Array = sw.content.find_children("*", "Label", true, false).map(func(l): return l.text).filter(func(t): return t.contains("막사") or t.contains("훈련") or t.contains("다음 "))
	_check(status.is_empty() and not "prod_labels" in sw, "(S) the sheet has no building status lines at the bottom (no '보병 막사 Lv 1 · …', no training lines)", "lines=%s" % [status])
	var inf = sw.rows["infantry:1"]
	await _tap(_center(inf.plus))
	await _tap(_center(inf.plus))
	await _tap(_center(inf.minus))
	_check(sw.work == {"infantry:1": 1} and inf.count.text == "1" and sw.summary_label.text == "배치 1 / 6 (인구)" and not sw.apply_button.disabled and Economy.soldier_deployed.is_empty(),
		"(S) [+] twice then [−] gives 1; [적용] turns on; nothing applied yet", "work=%s" % [sw.work])
	var arc = sw.rows["archer:1"]
	for i in 4:
		await _tap(_center(arc.plus))
	_check(sw.work.get("archer:1", 0) == 3 and arc.plus.disabled and arc.count.text == "3", "(S) [+] stops at the owned count (궁병 T1 보유 3)", "work=%s" % [sw.work])
	await _tap(_center(sw.rows["cavalry:2"].plus))
	await _tap(_center(sw.rows["infantry:2"].plus))
	await _tap(_center(sw.rows["infantry:2"].plus))  # 인구 6 — 눌러도 그대로
	_check(sw.work == {"infantry:1": 1, "archer:1": 3, "cavalry:2": 1, "infantry:2": 1} and sw.summary_label.text == "배치 6 / 6 (인구)"
		and sw.rows.values().all(func(r): return r.plus.disabled) and not sw.rows["infantry:2"].minus.disabled,
		"(S) population cap: at 6 / 6 every [+] is off and a press adds nothing", "work=%s plus=%s" % [sw.work, sw.rows.values().map(func(r): return r.plus.disabled)])
	await _tap(_center(sw.apply_button))
	await _frames(2)
	var front: Array = _main.soldiers.filter(func(s): return is_instance_valid(s))
	var kinds: Array = front.map(func(s): return "%s:%d" % [s.type, s.tier])
	kinds.sort()
	_check(Economy.soldier_deployed == {"infantry:1": 1, "archer:1": 3, "cavalry:2": 1, "infantry:2": 1} and sw.apply_button.disabled
		and kinds == ["archer:1", "archer:1", "archer:1", "cavalry:2", "infantry:1", "infantry:2"] and hud._toast.text == "병사 배치를 적용했습니다",
		"(S) [적용] saves the deploy; idle mode stands those 6 soldiers in front of the keep at once", "deployed=%s kinds=%s toast=%s" % [Economy.soldier_deployed, kinds, hud._toast.text])
	await _tap(_center(sw.clear_button))
	_check(sw.work.is_empty() and sw.summary_label.text == "배치 0 / 6 (인구)" and sw.clear_button.disabled and not sw.apply_button.disabled and Economy.soldier_deployed.size() == 4,
		"(S) [모두 해제] empties the edit only (not applied)", "work=%s" % [sw.work])
	await _tap(_center(sw.auto_button))
	_check(sw.work == {"infantry:2": 4, "cavalry:2": 1, "infantry:1": 1} and sw.work == Economy.auto_deploy() and sw.auto_button.disabled and sw.summary_label.text == "배치 6 / 6 (인구)",
		"(S) [자동 배치] fills strongest first up to the population: 보병 T2 x4, 기병 T2 x1, 보병 T1 x1", "work=%s" % [sw.work])
	await _tap(_center(sw.apply_button))
	await _frames(2)
	_check(Economy.soldier_deployed == {"infantry:2": 4, "cavalry:2": 1, "infantry:1": 1} and _main.soldiers.size() == 6, "(S) and [적용] puts that line-up in front of the keep",
		"deployed=%s n=%d" % [Economy.soldier_deployed, _main.soldiers.size()])
	# 합성은 시트 행에서(사용자 규칙): 보병 T1 5 → [합성 5→1] 켜짐, 보병 T2 4 → 꺼짐 + 이유
	var r1 = sw.rows["infantry:1"]
	var r2 = sw.rows["infantry:2"]
	_check(r1.merge.text == "합성 5→1" and not r1.merge.disabled and not r1.reason.visible and r2.merge.disabled and r2.reason.visible and r2.reason.text == Economy.SOLDIER_TEXT.not_enough
		and sw.rows["archer:1"].merge.disabled, "(S) each row has [합성 5→1]: 보병 T1 (5) on; 보병 T2 (4) and 궁병 T1 (3) off with '병사가 부족합니다'",
		"T1=%s T2=%s why=%s" % [r1.merge.disabled, r2.merge.disabled, r2.reason.text])
	await _tap(_center(r1.merge))
	await _frames(2)
	_check(Economy.soldiers == {"infantry:2": 5, "archer:1": 3, "cavalry:2": 1} and Economy.soldier_deployed == {"infantry:2": 4, "cavalry:2": 1}
		and sw.celebrations == 1 and not sw.rows.has("infantry:1") and not sw.rows["infantry:2"].merge.disabled and sw.rows["infantry:2"].have.text == "보유 5"
		and sw.work == {"infantry:2": 4, "cavalry:2": 1} and _main.soldiers.size() == 5 and hud._toast.text == "보병 T2 합성 완료",
		"(S) [합성] on the 보병 T1 row: 5 → T2 +1, the T1 row goes, the deployed T1 is trimmed (front line 5), T2 now mergeable; success pop + notice '보병 T2 합성 완료'",
		"owned=%s deployed=%s celebrations=%d toast=%s" % [Economy.soldiers, Economy.soldier_deployed, sw.celebrations, hud._toast.text])
	Economy.soldiers["infantry:5"] = 5
	Economy.soldiers_changed.emit()
	await _frames(1)
	_check(sw.rows.has("infantry:5") and sw.rows["infantry:5"].merge.disabled and sw.rows["infantry:5"].reason.text == Economy.SOLDIER_TEXT.max_tier,
		"(S) the top tier (T5) row shows its count but [합성] is off: '최대 티어입니다'", "rows=%s" % [sw.rows.keys()])
	# 시트 안 탭·끌기는 전장으로 새지 않는다(영웅 이동·카메라 이동 없음)
	var hero = get_tree().get_nodes_in_group("heroes").filter(func(h): return h.is_alive())[0]
	var state := [hero.side, hero.post, hero.free_pos]
	var cam0: Vector3 = rig.position
	var inside := Vector2(30, 700)
	_picker._select(hero)
	await _tap(inside)
	_mouse_button(inside, true)
	for i in 6:
		_mouse_motion(inside + Vector2(0, 12) * (i + 1), Vector2(0, 12))
	_mouse_button(inside + Vector2(0, 72), false)
	await _frames(2)
	_check(sw.is_open() and sw.dialog.get_global_rect().has_point(inside) and [hero.side, hero.post, hero.free_pos] == state and rig.position == cam0,
		"(S) a tap or drag inside the sheet reaches neither the hero nor the camera", "open=%s cam %s -> %s" % [sw.is_open(), cam0, rig.position])
	_picker._select(null)
	await _tap(_tab_px(tabs, "soldier"))
	_check(not sw.is_open() and tabs.selected == "", "(S) [병사] again closes the sheet", "")

	# 보병 막사 지붕 길게 누르기 → 건물 창(부지 중심은 바로 앞 주점 상자에 가린다): 1마리 3:00:00 → 2:30:00, 훈련 칸(비었을 때), 합성 칸 없음
	Economy.soldiers = {}
	Economy.soldier_deployed = {}
	Economy.soldiers_changed.emit()
	Economy.res = {"wood": 1000, "stone": 1000, "food": 1000}
	Economy.changed.emit()
	var bp := _roof_px("barracks")
	_check(_picker._pick(bp, PickerScript.LAYER_TAP).get("collider") != null and _picker._pick(bp, PickerScript.LAYER_TAP).collider.get_meta("building", "") == "barracks"
		and not _open_hero(bp), "(S) precondition: the barracks roof point hits the barracks body", "px=%s" % bp)
	var held: String = await _long_press(bp, bwin)
	await _frames(1)
	var eff: HBoxContainer = bwin.effects.get_child(0)
	var q = bwin.qty
	print("INPUT INFO: barracks window dialog %s, qty [+] %s, [최대] %s, [훈련] %s (720x1280 logical)" % [bwin.dialog.get_global_rect(), q.plus.get_global_rect(),
		q.max_button.get_global_rect(), bwin.train_button.get_global_rect()])
	_check(held == "barracks" and bwin.title_label.text == "보병 막사 Lv 1" and eff.get_child(0).text == "1마리 3:00:00" and eff.get_child(1).text == "→ 2:30:00"
		and bwin.train_box.visible and bwin.empty_box.visible and not bwin.run_box.visible and not bwin.done_box.visible and bwin.unit_label.text == "T1 보병 · 1마리 3:00:00"
		and bwin._train_type == "infantry:1" and bwin._unit_icon.is_visible_in_tree() and not "merge_rows" in bwin,
		"(S) a long press on the barracks opens its window: 1마리 3:00:00 → 2:30:00 and the empty training section (infantry figure, 'T1 보병 · 1마리 3:00:00'); no merge section",
		"held=%s title=%s unit=%s" % [held, bwin.title_label.text, bwin.unit_label.text])
	_check(q.value == 1 and q.min_value == 1 and q.max_value == 10 and bwin.train_cost_labels.food.text == "30" and bwin.train_cost_labels.wood.text == "20"
		and not bwin.train_cost_labels.stone.visible and bwin.train_time_label.text == "훈련 시간 3:00:00" and not bwin.train_button.disabled and not bwin.train_reason.visible,
		"(S) the quantity starts at 1 of 1..10 (batch cap): cost 30 food / 20 wood, 훈련 시간 3:00:00, [훈련] on",
		"qty=%d..%d=%d food=%s wood=%s time=%s" % [q.min_value, q.max_value, q.value, bwin.train_cost_labels.food.text, bwin.train_cost_labels.wood.text, bwin.train_time_label.text])
	await _guard_wait()
	await _tap(_center(q.plus))
	await _tap(_center(q.plus))
	_check(q.value == 3 and q.edit.text == "3" and bwin.train_cost_labels.food.text == "90" and bwin.train_time_label.text == "훈련 시간 9:00:00",
		"(S) [+] twice: 3 — cost and time follow (90 food, 9:00:00)", "qty=%d food=%s time=%s" % [q.value, bwin.train_cost_labels.food.text, bwin.train_time_label.text])
	await _tap(_center(q.max_button))
	_check(q.value == 10, "(S) [최대] picks the batch cap (10)", "qty=%d" % q.value)
	q.edit.text = "8"
	q.edit.text_changed.emit("8")
	await _frames(1)
	_check(q.value == 8 and bwin.train_cost_labels.food.text == "240" and bwin.train_cost_labels.wood.text == "160" and bwin.train_time_label.text == "훈련 시간 24:00:00",
		"(S) typing 8: cost 240 food / 160 wood, 훈련 시간 24:00:00", "qty=%d food=%s" % [q.value, bwin.train_cost_labels.food.text])
	await _tap(_center(bwin.train_button))
	await _frames(1)
	var tq := Economy.training("barracks")
	_check(Economy.res == {"wood": 840, "stone": 1000, "food": 760} and tq.count == 8 and not tq.ready and bwin.run_box.visible and not bwin.empty_box.visible
		and (bwin.run_label.text == "T1 보병 ×8 · 남은 24:00:00" or bwin.run_label.text.begins_with("T1 보병 ×8 · 남은 23:59:")) and bwin.train_bar.value < 0.01 and badges.training_ids().bars == ["barracks"]
		and badges.stack_size("barracks", Economy.time_now()).y >= badges.BUILD_LIFT_PX,
		"(S) [훈련]: resources go down at once (food 240 / wood 160), the window shows a progress bar and '보병 ×8 · 남은 24:00:00', a bar joins the barracks tag",
		"res=%s q=%s run=%s" % [Economy.res, tq, bwin.run_label.text])
	var errors0: int = _errors.count
	await _frames(2)  # 월드 막대·이름표 배치가 그려진다
	_check(_errors.count == errors0, "(S) the training bar draws over the barracks tag", "errors=%d" % (_errors.count - errors0))
	Economy.finish_training_now("barracks")  # 테스트 훅: 시간 당기기
	await _frames(2)
	_check(Economy.training("barracks").ready and bwin.done_box.visible and not bwin.run_box.visible and bwin.done_label.text == "T1 보병 ×8 훈련 완료" and not bwin.collect_button.disabled
		and badges.training_ids().ready == ["barracks"] and badges.stack_size("barracks", Economy.time_now()).y >= badges.BUBBLE_BLOCK and _errors.count == errors0,
		"(S) pulled forward: the window shows 'T1 보병 ×8 훈련 완료' + [수령], a soldier bubble floats over the barracks", "q=%s done=%s" % [Economy.training("barracks"), bwin.done_label.text])
	bwin.close()
	await _tap(bp)  # 수령할 게 있으면 탭 = 수령(창은 안 열린다)
	_check(Economy.soldiers == {"infantry:1": 8} and Economy.training("barracks").count == 0 and not bwin.is_open() and hud._toast.text == "보병 +8" and badges.training_ids().ready.is_empty(),
		"(S) a tap on the barracks collects: 보병 +8 owned, the bubble goes, notice '보병 +8', no window", "owned=%s open=%s toast=%s" % [Economy.soldiers, bwin.is_open(), hud._toast.text])
	await _tap(bp)  # 수령할 게 없으면 건물 창
	await _guard_wait()
	_check(bwin.is_open() and bwin.building_id == "barracks" and bwin.empty_box.visible, "(S) with nothing to collect the tap opens the window again (empty section)", "open=%s" % bwin.is_open())
	q.set_value(3)
	await _tap(_center(bwin.train_button))
	await _frames(1)
	_check(Economy.res == {"wood": 780, "stone": 1000, "food": 670} and bwin.run_box.visible and bwin.cancel_button.text == "취소(50% 환불)",
		"(S) a 3-soldier batch (food 90 / wood 60) runs with [취소(50% 환불)]", "res=%s" % [Economy.res])
	await _tap(_center(bwin.cancel_button))
	await _frames(1)
	_check(Economy.res == {"wood": 810, "stone": 1000, "food": 715} and Economy.training("barracks").count == 0 and bwin.empty_box.visible and hud._toast.text == Economy.CANCEL_TEXT
		and Economy.soldiers == {"infantry:1": 8}, "(S) [취소] refunds half (45 food / 30 wood) and empties the queue",
		"res=%s toast=%s" % [Economy.res, hud._toast.text])
	Economy.res = {"wood": 1000, "stone": 0, "food": 1000}
	Economy.changed.emit()
	bwin.close()
	bwin.open_building("stable")
	await _frames(1)
	_check(bwin.title_label.text == "기병 마구간 Lv 1" and bwin._train_type == "cavalry:1" and bwin.unit_label.text == "T1 기병 · 1마리 3:00:00" and bwin.train_button.disabled
		and bwin.train_reason.text == Economy.TRAIN_TEXT.not_enough and bwin.train_cost_labels.stone.get_theme_color("font_color") == bwin.RED,
		"(S) the stable window trains cavalry; no stone -> cost in red, [훈련] off with '자원 부족'", "type=%s why=%s" % [bwin._train_type, bwin.train_reason.text])
	await _barracks_t2_window()
	bwin.close()
	bwin.open_building("lumber")
	await _frames(1)
	_check(not bwin.train_box.visible, "(S) a resource building has no training section", "")
	bwin.close()
	Economy.soldiers = {}
	Economy.soldier_deployed = {}
	Economy.train_queues = {}
	Economy.soldiers_changed.emit()
	Economy.training_changed.emit()
	await _frames(2)


func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


## 건물 지붕(탭 판정체 윗면 0.3 m 아래) 5×5 점을 가운데에 가까운 순으로 보며, 그 건물 판정체가 맞는 첫 화면 좌표 — 부지 중심은 앞 건물
## 상자에 가릴 수 있다(보병 막사는 주점 뒤). 화면 안에 보이는 곳이 없으면 Vector2.INF.
func _roof_px(id: String) -> Vector2:
	var b := Balance.building(id)
	var top := 0.0
	for c in _main.get_children():
		if c.get_script() == preload("res://scripts/buildings.gd"):
			top = c.sites[id][0].end.y
	var offs := []
	for i in 5:
		for j in 5:
			offs.append(Vector2(i - 2, j - 2) / 5.0)
	offs.sort_custom(func(a, c): return a.length() < c.length())
	for o in offs:
		var px := _camera.unproject_position(Vector3((b.cell.x + b.size.x * (0.5 + o.x)) * Balance.TILE, top - 0.3, (b.cell.y + b.size.y * (0.5 + o.y)) * Balance.TILE))
		var hit: Dictionary = _picker._pick(px, PickerScript.LAYER_TAP)
		if get_viewport().get_visible_rect().has_point(px) and not hit.is_empty() and hit.collider.get_meta("building", "") == id:
			return px
	return Vector2.INF


## 개정 14 §4 수량 칸: [판매] → 펼침, [+]·[−]·입력·슬라이더·[최대], 판매 후 보유 감소·골드 증가. stone 7개로 본다(창이 열려 있어야 한다).
func _qty_sell_checks(panel) -> void:
	var stone_btn: Button = panel.sell_buttons["stone"]
	await _tap(stone_btn.get_global_rect().get_center())
	_check(panel.qty_boxes["stone"].visible and not panel.qty_boxes["wood"].visible and panel.qtys["stone"] == 0 and panel.sell_selected_button.disabled,
		"(p2) [sell] expands that row's quantity box (others folded); quantity 0 disables [sell]", "open=%s qty=%d" % [panel.qty_boxes["stone"].visible, panel.qtys["stone"]])
	var plus: Vector2 = panel.qty_plus["stone"].get_global_rect().get_center()
	await _tap(plus)
	await _tap(plus)
	await _tap(plus)
	await _tap(panel.qty_minus["stone"].get_global_rect().get_center())
	_check(panel.qtys["stone"] == 2 and panel.qty_edits["stone"].text == "2" and panel.qty_sliders["stone"].value == 2 and not panel.sell_selected_button.disabled,
		"(p2) [+] x3 then [-] gives 2 (input and slider follow)", "qty=%d text=%s" % [panel.qtys["stone"], panel.qty_edits["stone"].text])
	var edit: LineEdit = panel.qty_edits["stone"]
	edit.text = "99"
	edit.text_changed.emit("99")
	var over: bool = panel.qtys["stone"] == 7 and edit.text == "7"
	edit.text = "abc"
	edit.text_changed.emit("abc")
	var junk: bool = panel.qtys["stone"] == 0 and edit.text == "0"
	edit.text = "-4"
	edit.text_changed.emit("-4")
	_check(over and junk and panel.qtys["stone"] == 0, "(p2) input above holdings becomes holdings; text and negatives become 0", "over=%s junk=%s qty=%d" % [over, junk, panel.qtys["stone"]])
	await _tap(panel.qty_max["stone"].get_global_rect().get_center())
	_check(panel.qtys["stone"] == 7, "(p2) [max] sets the holdings", "qty=%d" % panel.qtys["stone"])
	panel.qty_sliders["stone"].value = 3
	var rate: float = Economy.current_rate("stone", Time.get_unix_time_from_system())
	_check(panel.qtys["stone"] == 3 and panel.qty_gold_labels["stone"].text == "→ %s골드" % HudScript.commas(Economy.sell_value("stone", 3, rate)), "(p2) slider sets 3; label shows floor(3 x price x rate)", "qty=%d label=%s" % [panel.qtys["stone"], panel.qty_gold_labels["stone"].text])
	var q0: int = panel.qtys["stone"]
	var qb = panel.qty_inputs["stone"]  # 수량 입력은 qty_box.gd(개정 16에서 훈련 칸과 같이 쓴다)
	qb._hold_start(1)
	qb._tick_hold(0.3)
	var early: int = panel.qtys["stone"]
	qb._tick_hold(1.0)
	qb._hold_dir = 0
	_check(early == q0 + 1 and panel.qtys["stone"] > early, "(p2) holding [+]: one step at once, no repeat before 0.4 s, then it accelerates", "q0=%d early=%d after=%d" % [q0, early, panel.qtys["stone"]])
	panel._set_qty("stone", 3)
	var gold0: int = Economy.gold_tenths
	await _tap(panel.sell_selected_button.get_global_rect().get_center())
	_check(Economy.res["stone"] == 4 and Economy.gold_tenths == gold0 + Economy.sell_value("stone", 3, rate) * 10 and panel.qty_boxes["stone"].visible,
		"(p2) quantity [sell] sells only that many (holdings drop, gold rises)", "stone=%d gold=%d->%d" % [Economy.res["stone"], gold0, Economy.gold_tenths])
	await _tap(stone_btn.get_global_rect().get_center())  # 다시 누르면 접힌다
	_check(not panel.qty_boxes["stone"].visible and panel.qtys["stone"] == 0, "(p2) tapping [sell] again folds the box", "open=%s" % panel.qty_boxes["stone"].visible)


## (R) 개정 14 §1 꾹 누르고 드래그 = 화면 회전: 0.35초 뒤 회전 대기 표시 → 가로 이동으로 요가 돈다(0.4°/px), 명령 없음. 회전 뒤 탭 판정(벌목장 수집)·나침반 화살이 맞다.
func _rotate_ui(hud) -> void:
	var rig = _camera.get_parent()
	var warrior = get_tree().get_nodes_in_group("heroes").filter(func(h): return h.is_alive())[0]
	_picker._select(warrior)
	var state := [warrior.side, warrior.post, warrior.free_pos]
	var pos0: Vector3 = rig.position
	var size0 := _camera.size
	var yaw0: float = rig.yaw_deg()
	var px := Vector2(360, 640)
	for c in [Vector2(360, 640), Vector2(120, 560), Vector2(600, 560), Vector2(360, 900), Vector2(100, 900), Vector2(620, 900)]:
		if _open_ground(c) and _picker._building_at(c) == "":  # 건물 위면 0.5초에 창이 열린다
			px = c
			break
	_check(_open_ground(px) and _picker._building_at(px) == "", "(R) precondition: the press point is open ground", "px=%s" % px)
	_mouse_button(px, true)
	await get_tree().create_timer(0.2).timeout
	await _frames(2)
	_check(not rig._rotating and not rig._indicator.visible, "(R) still pressed at 0.2 s: not rotating yet", "")
	await get_tree().create_timer(0.3).timeout
	await _frames(2)
	_check(rig._rotating and rig._indicator.visible, "(R) pressed 0.5 s without moving: rotate-ready indicator shown", "rotating=%s" % rig._rotating)
	for i in 5:  # 시간이 지난 뒤의 push_input 움직임은 헤드리스 뷰포트가 버리므로 리그에 직접 넣는다
		var mv := InputEventMouseMotion.new()
		mv.position = px + Vector2(20, 0) * (i + 1)
		mv.relative = Vector2(20, 0)
		rig._unhandled_input(mv)
	_mouse_button(px + Vector2(100, 0), false)
	await _frames(3)
	var yaw1: float = rig.yaw_deg()
	var turned := wrapf(yaw0 - yaw1, -180.0, 180.0)
	_check(absf(turned - 40.0) < 0.5 and rig.position == pos0 and _camera.size == size0 and not rig._rotating and not rig._indicator.visible,
		"(R) hold + 100 px drag turns the yaw 40 degrees (0.4/px), pivot and zoom kept, indicator gone", "yaw %.1f -> %.1f pos=%s size=%.1f" % [yaw0, yaw1, rig.position, _camera.size])
	_check(_picker.selected == warrior and [warrior.side, warrior.post, warrior.free_pos] == state and not _building_win().is_open(),
		"(R) the rotating drag issues no command and opens no window", "selected=%s warrior=%s state %s -> %s win=%s" % [_name(_picker.selected), _name(warrior), state, [warrior.side, warrior.post, warrior.free_pos], _building_win().is_open()])
	# 회전한 뒤 탭 판정: 벌목장 탭이 수집한다. 나침반 화살은 현재 요를 따른다
	_picker._select(null)
	await _frames(2)
	_check(is_equal_approx(hud._compass_yaw, yaw1) and hud.compass_dir(0, yaw1).distance_to(hud.compass_dir(0)) > 0.3,
		"(R) the gate-bar compass follows the camera yaw", "hud=%.1f cam=%.1f" % [hud._compass_yaw, yaw1])
	var now := Time.get_unix_time_from_system()
	Economy.res = {"wood": 0, "stone": 0, "food": 0}
	Economy.last_collect["lumber"] = now - 600.0
	Economy.changed.emit()
	var lp := _building_px("lumber")
	if get_viewport().get_visible_rect().has_point(lp) and not _open_hero(lp):
		var due: int = Economy.pending("lumber", Economy.time_now())
		await _tap(lp)
		_check(due >= 100 and Economy.res.wood >= due, "(R) after rotating, a tap on the lumber mill (at its new screen position) still collects", "wood=%d px=%s" % [Economy.res.wood, lp])
	else:
		print("INPUT INFO: (R) lumber mill off screen after rotation, px=%s" % lp)
	# 움직임 없이 뗀 꾹 누름은 회전 대기만 거치고 요를 그대로 둔다
	var yaw2: float = rig.yaw_deg()
	_mouse_button(px, true)
	await get_tree().create_timer(0.5).timeout
	await _frames(2)
	_mouse_button(px, false)
	await _frames(2)
	_check(is_equal_approx(rig.yaw_deg(), yaw2) and not rig._rotating, "(R) hold and release without moving leaves the yaw alone", "yaw %.1f -> %.1f" % [yaw2, rig.yaw_deg()])
	rig.rotation_degrees.y = 0.0
	await _frames(2)


## 개정 14 §3 FEVER 버튼: [진행] 왼쪽, 미충전 탭은 "몬스터 N마리 더" 알림, 충전 뒤 탭은 FEVER 시작(남은 시간 표시).
func _fever_ui(hud) -> void:
	var fb = hud._fever
	Fever.reset()
	Fever.gauge = 73
	await _frames(2)
	var fr: Rect2 = fb.get_global_rect()
	var br: Rect2 = hud._button.get_global_rect()
	print("INPUT INFO: fever button %s, stage button %s" % [fr, br])
	_check(fr.end.x <= br.position.x and absf(fr.get_center().y - br.get_center().y) < 12.0 and fb.label_text() == "36%",
		"(fever) the button sits left of [진행] on the same row and reads 36%", "fever=%s stage=%s text=%s" % [fr, br, fb.label_text()])
	await _tap(fr.get_center())
	_check(not Fever.active() and Fever.gauge == 73 and hud._toast.visible and hud._toast.text == "몬스터 127마리 더",
		"(fever) tapping an uncharged button only toasts how many more kills", "gauge=%d toast=%s" % [Fever.gauge, hud._toast.text])
	Fever.gauge = Fever.kills_needed()
	await _frames(2)
	_check(fb.label_text() == "FEVER!", "(fever) a full gauge reads FEVER!", fb.label_text())
	await _tap(fr.get_center())
	await _frames(2)
	_check(Fever.active() and Fever.left > 170.0 and Fever.gauge == 0 and fb.label_text() == "3:00" and fb.banner_left > 0.0,
		"(fever) tapping a full button starts FEVER: timer 3:00 on the button, big banner", "left=%.1f text=%s banner=%.2f" % [Fever.left, fb.label_text(), fb.banner_left])
	Fever.left = 119.5
	await _frames(1)
	_check(fb.label_text() == "2:00" or fb.label_text() == "1:59", "(fever) the button shows the time left", fb.label_text())
	Fever.reset()
	await _frames(1)


## (x2) 개정 14 §2 영웅 피규어(헤드리스 — 렌더 없이 자리표시): main에 Portraits 하나, 상세 큰 카드는 보일 때만 실시간 미리보기를 걸고
##      (목록으로 내리면 꺼짐) 가로로 끌면 모델이 돈다 — 이전·다음 스와이프로 새지 않는다. 목록·슬롯 카드는 피규어 칸에 portrait를 그린다.
##      상세(hans)가 보이고 보호 시간이 끝난 상태에서 불러, 같은 상태(hans 상세, 보호 끝)로 돌려놓는다.
func _figures(heroes_win) -> void:
	var P = preload("res://scripts/portraits.gd")
	var p = P.current
	var mine: Array = _main.get_children().filter(func(c): return c.get_script() == P)
	_check(mine.size() == 1 and p == mine[0] and not p.can_render and p.queue.is_empty(), "(x2) main has one Portraits node; headless renders nothing (placeholders only)", "")
	var feet: Vector2 = p._cam.unproject_position(Vector3.ZERO) / Vector2(p._vp.size)  # 미리보기 중이면 LIVE_SIZE(개정 15), 아니면 SIZE
	_check(is_equal_approx(feet.x, 0.5) and absf(feet.y - P.feet_y()) < 0.002, "(x2) the portrait camera puts the model's feet where cards draw the pedestal", "feet=%s feet_y=%.3f" % [feet, P.feet_y()])
	p._show("hero:hans")  # 렌더 직전 단계만(헤드리스): 모델을 띄운 그 프레임에 대기 자세여야 한다
	var skel := p._pivot.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var hand := skel.get_bone_global_pose(skel.find_bone("hand.r")).origin
	var rest := skel.get_bone_global_rest(skel.find_bone("hand.r")).origin
	var gear: Node3D = p._pivot.find_child("2H_Sword", true, false)
	_check(p._pivot.get_child_count() == 1 and hand.y < rest.y - 0.2 and gear != null and not gear.visible,
		"(x2) a figure is in its idle pose (not the T-pose) the frame it is staged, with only its own gear", "hand=%s rest=%s" % [hand, rest])
	p._show("")
	_check(p._pivot.get_child_count() == 0, "(x2) the viewport model is cleared when done", "")
	_check(p.live_key == "hero:hans" and heroes_win.big_card.figure_texture() == P.placeholder("hero:hans"),
		"(x2) the detail's big card runs the live preview of its hero (headless: the placeholder)", "live=%s" % p.live_key)
	var c: Vector2 = heroes_win.big_card.get_global_rect().get_center()
	_mouse_button(c, true)
	for i in 5:
		_mouse_motion(c + Vector2(30, 0) * (i + 1), Vector2(30, 0))
	_mouse_button(c + Vector2(150, 0), false)
	await _frames(2)
	_check(heroes_win.detail_id == "hans" and is_equal_approx(p.yaw, 150.0 * P.TURN_DEG_PER_PX),
		"(x2) a sideways drag on the big card turns the model instead of swiping to the next hero", "detail=%s yaw=%.1f" % [heroes_win.detail_id, p.yaw])
	heroes_win.step(1)
	_check(heroes_win.detail_id != "hans" and p.live_key == "hero:" + heroes_win.detail_id and p.yaw == 0.0, "(x2) [다음] moves the live preview to the next hero, facing front", "live=%s" % p.live_key)
	heroes_win.step(-1)
	heroes_win._show_list(false)
	var slot = heroes_win.slot_cards[0]
	_check(p.live_key == "" and slot.figure_texture() == P.portrait("hero:" + slot.hero_id) and slot.figure_rect().size.x > 50.0,
		"(x2) back to the list the live preview stops; slot cards draw the figure", "live=%s" % p.live_key)
	heroes_win.show_detail("hans")
	_check(p.live_key == "hero:hans", "(x2) reopening the detail resumes the live preview", "live=%s" % p.live_key)
	_check(p._vp.size == Vector2i(P.LIVE_SIZE, P.LIVE_SIZE), "(x2) the live preview renders at LIVE_SIZE (the big card draws the figure large)", "size=%s" % p._vp.size)
	heroes_win.close()
	_check(p.live_key == "" and p._vp.size == Vector2i(P.SIZE, P.SIZE), "(x2) closing the window stops the live preview (snapshots back at SIZE)", "live=%s size=%s" % [p.live_key, p._vp.size])
	heroes_win.open()
	heroes_win.show_detail("hans")
	await _guard_wait()


## (x3) 개정 15 승급(오프라인): 상세 배치(720×1280) — 맨 위 큰 카드에 피규어가 카드 대부분, 그 아래 능력치, 그 아래 [레벨업]·[×10]·[승급],
##      시트 안에 다 들어간다. [승급] 안 "조각 2 / 25"·이유 "조각 부족"·미리보기(×1.5, 최대 레벨 30 → 40). 목록 카드 조각 막대·금색 ⬆.
##      조각이 모이면 [승급] 탭 → 조각 −25, ★ +1(별이 날아와 박힘·금색 빛 조각), HP·공격 × 1.5(초록 반짝임), 최대 레벨 40, 방치 모드라
##      그 영웅만 곧바로 새 능력치. 최대 승급은 "MAX"·"최대 승급". 모집 결과: 중복은 "+1 조각"과 조각 막대, 새 영웅은 NEW(막대 없음).
##      hans 상세·보호 끝 상태에서 불러 같은 상태로 돌려놓는다.
func _promotion_ui(heroes_win, recruit) -> void:
	var arteon := GameData.hero("arteon")
	heroes_win.show_detail("arteon")
	await _unguarded(heroes_win)
	await _frames(2)
	var card: Rect2 = heroes_win.big_card.get_global_rect()
	var fig: Rect2 = heroes_win.big_card.figure_rect()
	var stats: Rect2 = heroes_win.stat_values[0].get_global_rect()
	var stats_end: Rect2 = heroes_win.stat_values[4].get_global_rect()
	var lb: Rect2 = heroes_win.level_button.get_global_rect()
	var tb: Rect2 = heroes_win.ten_button.get_global_rect()
	var pb: Rect2 = heroes_win.promote_button.get_global_rect()
	var sheet: Rect2 = heroes_win.dialog.get_global_rect()
	var nav: Rect2 = heroes_win.next_button.get_global_rect()
	print("INPUT INFO: hero detail card %s figure %s stats %s..%s buttons %s %s %s nav %s sheet %s" % [card, fig, stats, stats_end, lb, tb, pb, nav, sheet])
	_check(card.size.x >= 600.0 and card.size.y >= 380.0 and fig.size.y >= card.size.y * 0.75 and fig.size.x >= 330.0,
		"(x3) the big card spans the sheet width and its figure fills most of it (live figure >= 75% of the card height)", "card=%s figure=%s" % [card, fig])
	_check(card.end.y <= stats.position.y and stats_end.end.y <= lb.position.y and is_equal_approx(lb.position.y, pb.position.y) and lb.end.x <= tb.position.x and tb.end.x <= pb.position.x,
		"(x3) order top to bottom: figure, stats, then [레벨업] [×10] [승급] in one row", "card=%s stats=%s lb=%s tb=%s pb=%s" % [card, stats_end, lb, tb, pb])
	_check(nav.end.y <= sheet.end.y - 12.0 and sheet.end.y <= 1280.0 - 104.0 and heroes_win._detail_view.get_combined_minimum_size().y <= heroes_win.content.size.y + 0.5
		and pb.size.y >= 90.0 and pb.size.x >= 180.0,
		"(x3) the whole detail fits the 720x1280 sheet above the tab bar (buttons >= 90 px tall)", "nav=%s sheet=%s min=%s content=%s" % [nav, sheet, heroes_win._detail_view.get_combined_minimum_size(), heroes_win.content.size])
	_check(heroes_win._promo.line.text == "조각 2 / 25" and heroes_win._promo.title.text == "승급 ★2" and heroes_win.promote_button.disabled and heroes_win.promote_reason.text == "조각 부족"
		and heroes_win.promote_preview.text == "승급하면 HP·공격 → ×1.5 · 최대 레벨 30 → 40\n★3 달성 시 스킬 해금: 철벽" and heroes_win.big_card.stars == 1,
		"(x3) [승급] shows 조각 2 / 25 inside, is off with the reason 조각 부족, and previews x1.5 and max level 30 -> 40",
		"line=%s reason=%s preview=%s" % [heroes_win._promo.line.text, heroes_win.promote_reason.text, heroes_win.promote_preview.text])
	heroes_win._show_list(false)
	var ac = heroes_win.hero_cards.arteon
	_check(ac.shards == 2 and ac.shard_text() == "조각 2 / 25" and not ac.can_promote and ac.stars == 1 and ac.shard_bar_rect().size.x > 100.0
		and heroes_win.slot_cards[1].shard_bar_rect().size.x == 0.0,
		"(x3) list card: one gold star and a shard bar 조각 2 / 25 (no ⬆ yet); slot cards have no bar", "text=%s" % ac.shard_text())
	Economy.hero_shards["arteon"] = 30
	Economy.changed.emit()
	_check(ac.can_promote and ac.shard_text() == "조각 30 / 25" and not ac.can_level, "(x3) with 30 shards the card shows the gold ⬆ (not the green ▲)", "")
	heroes_win.show_detail("arteon")
	await _unguarded(heroes_win)
	_check(not heroes_win.promote_button.disabled and heroes_win._promo.line.text == "조각 30 / 25" and heroes_win.promote_reason.text == "", "(x3) 30 shards: [승급] on", "")
	var lv := Economy.level_of("arteon")
	var hp0: String = heroes_win.stat_values[0].text
	var pre := _alive_heroes()
	await _tap(heroes_win.promote_button.get_global_rect().get_center())
	await _frames(2)
	var mult := 1.0 + 0.06 * (lv - 1)
	var hero = _alive_heroes().filter(func(h): return h.def.id == "arteon")
	_check(Economy.shards_of("arteon") == 5 and Economy.promotion_of("arteon") == 2 and heroes_win.big_card.stars == 2 and heroes_win.big_card.is_promoting()
		and heroes_win.big_card._flying == 1 and heroes_win.promotions_shown == 1 and heroes_win.level_label.text == "Lv %d / 40" % lv
		and heroes_win.stat_values[0].text == UiKit.commas(roundi(1040.0 * mult * 2.25)) and heroes_win.stat_values[0].text != hp0
		and heroes_win.stat_values[0].get_theme_color("font_color") != HudScript.INK and heroes_win._promo.line.text == "조각 5 / 50",
		"(x3) [승급] spends 25 shards: ★2 (a star flies in, gold shards burst), HP x1.5 flashes green, Lv %d / 40, next 조각 5 / 50" % lv,
		"shards=%d promo=%d hp=%s->%s label=%s" % [Economy.shards_of("arteon"), Economy.promotion_of("arteon"), hp0, heroes_win.stat_values[0].text, heroes_win.level_label.text])
	_check(hero.size() == 1 and not pre.has(hero[0]) and is_equal_approx(hero[0].hp_max, 1040.0 * mult * 2.25) and is_equal_approx(hero[0].atk, 42.0 * mult * 2.25),
		"(x3) idle mode rebuilds the promoted hero at once with HP/atk x1.5^2", "hp=%s" % [hero.map(func(h): return h.hp_max)])
	await get_tree().create_timer(1.0).timeout
	_check(not heroes_win.big_card.is_promoting() and heroes_win.big_card._flying == -1, "(x3) the effect ends and the new star stays in place", "")
	await _tap(heroes_win.promote_button.get_global_rect().get_center())
	_check(Economy.promotion_of("arteon") == 2 and heroes_win.promote_button.disabled and heroes_win.promote_reason.text == "조각 부족", "(x3) 5 of 50 shards: [승급] is off again", "")
	Economy.hero_promotions["arteon"] = 5
	Economy.hero_levels["arteon"] = 69  # 가장 큰 숫자(다음 레벨 미리보기 포함)로도 가로가 시트 안에 들어가는지
	Economy.roster_changed.emit()
	await _frames(1)
	var wide: Vector2 = heroes_win._detail_view.get_combined_minimum_size()
	_check(wide.x <= heroes_win.content.size.x + 0.5 and heroes_win.stat_nexts[0].text.begins_with("→ ") and heroes_win.stat_values[0].text.length() >= 6,
		"(x3) the widest stats (★5 Lv 69: HP %s %s) still fit the sheet width" % [heroes_win.stat_values[0].text, heroes_win.stat_nexts[0].text],
		"min=%s content=%s" % [wide, heroes_win.content.size])
	Economy.hero_levels["arteon"] = lv
	Economy.roster_changed.emit()
	_check(heroes_win._promo.line.text == "조각 5 · MAX" and heroes_win.promote_reason.text == "최대 승급" and heroes_win.promote_button.disabled
		and heroes_win.promote_preview.text == "최대 승급 ★5 — HP·공격 ×7.59" and heroes_win.level_label.text == "Lv %d / 70" % lv,
		"(x3) max promotion: MAX inside, reason 최대 승급, x7.59, max level 70", "line=%s preview=%s" % [heroes_win._promo.line.text, heroes_win.promote_preview.text])
	heroes_win._show_list(false)
	_check(heroes_win.hero_cards.arteon.shard_text() == "MAX" and heroes_win.hero_cards.arteon.stars == 5, "(x3) the list card bar reads MAX with five stars", "")
	Economy.hero_promotions["arteon"] = 2
	Economy.roster_changed.emit()
	# 모집 결과: 모든 영웅을 가진 채 1회 모집(오프라인) → 중복 "+1 조각"과 막대. 끝나면 보유를 되돌린다
	var keep := [Economy.heroes.duplicate(), Economy.hero_shards.duplicate(), Economy.gold_tenths]
	for h in GameData.heroes():
		Economy.heroes[h.id] = maxi(1, int(Economy.heroes.get(h.id, 0)))
	Economy.gold_tenths = 3000
	heroes_win.close()
	recruit.open()
	await _unguarded(recruit)
	await _tap(recruit.one_button.get_global_rect().get_center())
	await _frames(2)
	var rc = recruit.cards[0] if recruit.cards.size() == 1 else null
	var got: String = rc.hero_id if rc != null else ""
	print("INPUT INFO: repeat pull %s card shards %d (kept %d, now %d) bar %s size %s cards %d" % [got, rc.shards if rc else -1, int(keep[1].get(got, 0)),
		Economy.shards_of(got), rc.shard_bar_rect() if rc else Rect2(), rc.size if rc else Vector2.ZERO, recruit.cards.size()])
	_check(rc != null and Economy.gold_tenths == 0 and rc.badge == recruit.DUP_TEXT and rc.shards == Economy.shards_of(got) and rc.shards == int(keep[1].get(got, 0)) + 1
		and rc.shard_text() == "조각 %d / %d" % [rc.shards, Economy.promote_cost(got)] and rc.shard_bar_rect().size.x > 50.0,
		"(x3) a repeat pull shows +1 조각 and that hero's shard bar (offline: shards +1)",
		"card=%s badge=%s shards=%d econ=%d kept=%d text=%s need=%d bar=%s size=%s" % [got, rc.badge if rc else "", rc.shards if rc else -1, Economy.shards_of(got),
			int(keep[1].get(got, 0)), rc.shard_text() if rc else "", Economy.promote_cost(got), rc.shard_bar_rect() if rc else Rect2(), rc.size if rc else Vector2.ZERO])
	recruit._on_gacha_done([{"hero_id": "jack", "grade": "R", "new": true, "copies": 1, "shards": 0}])
	_check(recruit.cards[0].badge == "NEW" and recruit.cards[0].shard_bar_rect().size.x == 0.0, "(x3) a new hero shows NEW and no bar", "")
	recruit.close()
	Economy.heroes = keep[0]
	Economy.hero_shards = keep[1]
	Economy.gold_tenths = keep[2]
	Economy.roster_changed.emit()
	Economy.changed.emit()
	await _recruit_repeat(recruit)
	heroes_win.open()
	heroes_win.show_detail("hans")
	await _unguarded(heroes_win)


func _alive_heroes() -> Array:
	return get_tree().get_nodes_in_group("heroes").filter(func(h): return h.is_alive())


## 창의 연 직후 보호 시간이 확실히 지나게(타이머 0.45초 뒤에도 실제 시각으로 아직이면 프레임을 더 기다린다 — 부하에 따라 엇갈린다).
func _unguarded(win) -> void:
	await _guard_wait()
	while win.is_guarded():
		await _frames(1)


## main 자식 중 script인 노드(없으면 null).
func _child(script: Script) -> Node:
	for c in _main.get_children():
		if c.get_script() == script:
			return c
	return null


## (P) 개정 15 병사 건물 탭: 기본 카메라에서 보병 막사·궁병 훈련소·기병 마구간의 보이는 지붕 가운데(메시 AABB 윗면 가운데 0.3 m 아래)를
##     탭하면 그 건물 창 — 레이가 앞 건물(주점·성채) 상자를 먼저 꿰어도 판정체 중심이 탭에 가장 가까운 건물을 고른다. 길게 누르기·부지 중심도 같다.
func _soldier_picks() -> void:
	var bwin = _building_win()
	var rig = _camera.get_parent()
	var scenery = _child(preload("res://scripts/buildings.gd"))
	var cam0 := [rig.position, rig.rotation_degrees.y, _camera.size]
	rig.position = Vector3.ZERO  # 기본 카메라(리그 원점, 요 45°, 줌 66)
	rig.rotation_degrees.y = 0.0
	rig.zoom_by(Balance.CAMERA_SIZE_DEFAULT / _camera.size)
	await _frames(2)
	_picker._select(null)
	var firsts := {}
	for id in ["barracks", "archery", "stable"]:
		var box: AABB = scenery.sites[id][0]
		var px := _camera.unproject_position(Vector3(box.get_center().x, box.end.y - 0.3, box.get_center().z))
		firsts[id] = _picker._pick(px, PickerScript.LAYER_TAP).get("collider", self).get_meta("building", "none")
		_check(get_viewport().get_visible_rect().has_point(px) and not _open_hero(px), "(P) precondition: the %s roof center is on screen, no hero near" % id, "px=%s" % px)
		await _tap(px)
		_check(bwin.is_open() and bwin.building_id == id, "(P) a tap on the %s's visible roof center opens its window (the ray's first box is %s)" % [id, firsts[id]],
			"open=%s id=%s px=%s" % [bwin.is_open(), bwin.building_id, px])
		bwin.close()
		_check(_picker._building_at(px) == id and _picker._building_at(_building_px(id)) == id, "(P) a long press on the %s roof center or site center picks it too" % id,
			"roof=%s site=%s" % [_picker._building_at(px), _picker._building_at(_building_px(id))])
	_check(firsts.keys().any(func(k): return firsts[k] != k), "(P) precondition: a front building's box is the ray's first hit on at least one soldier roof center (the case this fixes)", "first hits=%s" % [firsts])
	for t in ["tavern", "keep", "lumber"]:  # 앞 건물은 그대로 그 건물
		_check(_picker._building_at(_building_px(t)) == t, "(P) the %s site center still picks the %s" % [t, t], _picker._building_at(_building_px(t)))
	rig.position = cam0[0]
	rig.rotation_degrees.y = cam0[1]
	rig.zoom_by(cam0[2] / _camera.size)
	await _frames(2)


## (F) 개정 15 병사 피규어: 병사 칸(시트 행·건물 창 훈련 칸)은 Portraits "soldier:<병종>"을 그리고(헤드리스는 자리표시), 렌더가 끝나면
##     (portrait_ready) 칸을 다시 그린다 — 칸이 사라지면 연결도 끊긴다. 피규어 몸은 월드 병사와 같은 SoldierBody(기병 = 같은 말 메시 + 기사), 대기 자세.
func _soldier_figures(tabs) -> void:
	var P = preload("res://scripts/portraits.gd")
	var SP = preload("res://scripts/soldier_panel.gd")
	var SB = preload("res://scripts/soldier_body.gd")
	var p = P.current
	_check(SP.figure("infantry") == P.portrait("soldier:infantry") and SP.figure("cavalry") == P.placeholder("soldier:cavalry") and p.queue.is_empty(),
		"(F) a soldier cell's figure is Portraits 'soldier:<type>' (headless: the placeholder, nothing queued)", "")
	p._show("soldier:cavalry")
	var kids: Array = p._pivot.get_children()
	var skel := p._pivot.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var hand := skel.get_bone_global_pose(skel.find_bone("hand.r")).origin
	var rest := skel.get_bone_global_rest(skel.find_bone("hand.r")).origin
	_check(kids.size() == 2 and kids[1] is MeshInstance3D and kids[1].mesh == SB._horse_mesh and is_equal_approx(kids[0].position.y, SB.RIDER_Y)
		and is_equal_approx(kids[0].scale.x, preload("res://scripts/art.gd").SOLDIER_SCALE) and hand.y < rest.y - 0.2,
		"(F) the cavalry figure is the world soldier's body: the shared horse mesh with the knight on its back, in the idle pose", "kids=%d hand=%s rest=%s" % [kids.size(), hand, rest])
	var gear := {"soldier:infantry": [["1H_Sword", "Rectangle_Shield"], ["2H_Sword"]], "soldier:archer": [["2H_Crossbow"], ["Knife", "1H_Crossbow"]]}
	for key in gear:
		p._show(key)
		var shown: bool = gear[key][0].all(func(g): return p._pivot.find_child(g, true, false).visible) and gear[key][1].all(func(g): return not p._pivot.find_child(g, true, false).visible)
		_check(p._pivot.get_child_count() == 1 and shown, "(F) %s figure shows only its gear %s" % [key, gear[key][0]], "")
	p._show("")
	# 시트 행 칸: portrait_ready에 다시 그리고, 행이 사라지면 연결이 끊긴다
	var sw = tabs.windows.soldier
	Economy.soldiers = {"infantry:1": 1, "archer:2": 1}
	Economy.soldiers_changed.emit()
	sw.open()
	await _frames(2)
	var icon: Control = sw.rows["infantry:1"].box.get_child(0)
	var linked := func(c: Object) -> bool: return p.portrait_ready.get_connections().any(func(cn): return cn.callable.get_object() == c)
	var draws := [0]
	icon.draw.connect(func(): draws[0] += 1)
	await _frames(2)
	var d0: int = draws[0]
	p.store("soldier:infantry", ImageTexture.create_from_image(P.silhouette(Color.RED)))
	await _frames(2)
	_check(linked.call(icon) and draws[0] > d0 and P.has_portrait("soldier:infantry") and SP.figure("infantry") != P.placeholder("soldier:infantry"),
		"(F) a finished soldier render redraws the cell with the figure", "draws %d -> %d" % [d0, draws[0]])
	var n0: int = p.portrait_ready.get_connections().size()
	Economy.soldiers = {}
	Economy.soldiers_changed.emit()
	await _frames(2)
	_check(not is_instance_valid(icon) and p.portrait_ready.get_connections().size() <= n0 - 2, "(F) cells that go away drop their portrait_ready link",
		"links %d -> %d" % [n0, p.portrait_ready.get_connections().size()])
	sw.close()
	P._cache.erase("soldier:infantry")
	var bwin = _building_win()
	bwin.open_building("barracks")
	await _frames(1)
	_check(linked.call(bwin._unit_icon), "(F) the barracks window's training section uses the same soldier figure cell", "")
	bwin.close()


## (T) 개정 15 화면 공간 이름표(world_tags): 건물 "이름 Lv N"·상인·문루 글자가 Label3D 없이 한 노드에, 글자 ~20 px, 그리기 호출 상한.
##     겹침 피하기: 기본 카메라에서 원래 겹치던 무리(민가·성채·기병 마구간, 주점·궁병 훈련소)도 덩어리끼리 겹치지 않고, 8 px 넘게 밀린
##     덩어리마다 지시선, 안 밀린 태그는 기준점 바로 위. 회전(요 +40°)·확대·축소에서도 같다. 병사 대열(병사 상자)은 덮지 않는다 —
##     벌목장·채석장 말풍선이 떠도(덩어리 = 이름표 + 말풍선). place()는 순수 함수.
func _world_tags() -> void:
	var WT = preload("res://scripts/world_tags.gd")
	var wt = _child(WT)
	var badges = _child(preload("res://scripts/badges.gd"))
	var rig = _camera.get_parent()
	var cam0 := [rig.position, rig.rotation_degrees.y, _camera.size]
	rig.position = Vector3.ZERO  # 기본 카메라
	rig.rotation_degrees.y = 0.0
	rig.zoom_by(Balance.CAMERA_SIZE_DEFAULT / _camera.size)
	var now := Economy.time_now()
	for b in Economy.last_collect:
		Economy.last_collect[b] = now  # 말풍선 없이 시작
	Economy.changed.emit()
	await _frames(2)
	_check(_main.find_children("*", "Label3D", true, false).is_empty() and wt.tags.size() == Balance.BUILDINGS.size() + 1 + 4 and wt.text("merchant") == "상인"
		and wt.text("houses") == "민가 Lv 1" and WT.NAME_SIZE == 20 and wt.rects.size() == wt.tags.size(),
		"(T) one screen-space tag layer: 10 buildings + merchant + 4 gate letters (no Label3D), 20 px names, all on screen at the default camera",
		"tags=%d rects=%d" % [wt.tags.size(), wt.rects.size()])
	var strings := 0
	for t in wt.tags:
		strings += 2 if t.lv != "" else 1
	_check(wt.draw_calls <= 3 + strings and wt.draw_calls <= 3 + 2 * WT.MAX_TAGS, "(T) draw calls are capped: one triangle array, two line batches, at most two strings per tag",
		"calls=%d strings=%d" % [wt.draw_calls, strings])
	_check(_any_overlap(wt.desired, ["houses", "keep", "stable"]) and _any_overlap(wt.desired, ["tavern", "archery"]),
		"(T) precondition: at the default camera the 민가/성채/기병 마구간 and 주점/궁병 훈련소 tags would overlap where they want to sit", "")
	_tags_ok(wt, "default camera")
	print("INPUT INFO: default camera tags (id: tag rect, pushed px): %s" % [wt.tags.map(func(t): return "%s: %s, %d" % [t.id, wt.rects[t.id],
		roundi(wt.desired[t.id].position.y - wt.stacks[t.id].position.y)] if wt.rects.has(t.id) else t.id + ": off")])
	rig.rotation_degrees.y = 40.0
	await _frames(2)
	_tags_ok(wt, "camera yaw +40")
	rig.rotation_degrees.y = 0.0
	rig.zoom_by(30.0 / _camera.size)
	await _frames(2)
	_tags_ok(wt, "zoomed in (30 m)")
	rig.zoom_by(130.0 / _camera.size)
	await _frames(2)
	_tags_ok(wt, "zoomed out (130 m)")
	print("INPUT INFO: zoomed out (130 m) tags pushed px: %s" % [wt.stacks.keys().map(func(id): return [id, roundi(wt.desired[id].position.y - wt.stacks[id].position.y)])])
	# 병사 대열: 30명(인구 30) + 벌목장·채석장 말풍선 — 이름표·말풍선 덩어리가 병사 상자를 덮지 않는다
	rig.zoom_by(Balance.CAMERA_SIZE_DEFAULT / _camera.size)
	Economy.levels["houses"] = 13
	Economy.soldiers = {"infantry:1": 12, "archer:2": 12, "cavalry:1": 6}
	Economy.set_soldier_deploy(Economy.soldiers.duplicate())
	Economy.last_collect["lumber"] = now - 900.0
	Economy.last_collect["quarry"] = now - 900.0
	Economy.changed.emit()
	await _frames(3)
	var lumber_h: float = wt.stacks.lumber.size.y
	_check(wt.obstacles.size() == 30 and _main.soldiers.size() == 30 and lumber_h >= WT.TAG_H + badges.BUBBLE_BLOCK and wt.top("lumber") != null
		and badges.badge_ids(Economy.time_now()).has("lumber"),
		"(T) precondition: 30 soldiers stand in front of the keep; the lumber mill's bubble rides on its tag (stack %.0f px)" % lumber_h, "obstacles=%d" % wt.obstacles.size())
	_check(wt.desired.keys().any(func(id): return wt.obstacles.any(func(o): return wt.desired[id].intersects(o))),
		"(T) precondition: at least one tag stack would cover the soldiers where it wants to sit", "")
	_soldiers_clear(wt, "default camera")
	_tags_ok(wt, "default camera with soldiers")
	var fr: Rect2 = wt.obstacles[0]
	for o in wt.obstacles:
		fr = fr.merge(o)
	print("INPUT INFO: default camera with 30 soldiers: formation box %s; stacks (id: stack, pushed px): %s" % [fr, wt.stacks.keys().map(func(id): return "%s: %s, %d" % [id, wt.stacks[id],
		roundi(wt.desired[id].position.y - wt.stacks[id].position.y)])])
	rig.zoom_by(30.0 / _camera.size)
	await _frames(2)
	_soldiers_clear(wt, "zoomed in (30 m)")
	_tags_ok(wt, "zoomed in with soldiers")
	rig.rotation_degrees.y = -30.0
	await _frames(2)
	_soldiers_clear(wt, "zoomed in, yaw -30")
	# place(): 아래부터 놓고 위로 민다. 장애물은 덜 움직이는 쪽(아래 끝에 걸치면 아래로, 위 끝이면 위로)
	var a := Rect2(0, 100, 50, 20)
	var b := Rect2(10, 90, 50, 20)
	var o := Rect2(-20, 200, 100, 60)
	var got: Array = WT.place([a, b, Rect2(0, 250, 40, 20), Rect2(0, 185, 40, 20)], [o], 3.0)
	_check(got[0] == a and got[1].end.y <= a.position.y - 3.0 and got[1].position.x == b.position.x and got[2].position.y >= o.end.y + 3.0 and got[3].end.y <= o.position.y - 3.0,
		"(T) place(): the lower tag keeps its spot, the upper one goes above it; an obstacle sends a tag to its nearer side", "%s" % [got])
	Economy.soldiers = {}
	Economy.set_soldier_deploy({})
	Economy.levels["houses"] = 1
	Economy.last_collect["lumber"] = now
	Economy.last_collect["quarry"] = now
	Economy.changed.emit()
	rig.position = cam0[0]
	rig.rotation_degrees.y = cam0[1]
	rig.zoom_by(cam0[2] / _camera.size)
	await _frames(2)


## ids 중 둘의 상자가 겹치는지(rects: id → Rect2, 없는 id는 건너뛴다).
func _any_overlap(rects: Dictionary, ids: Array) -> bool:
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if rects.has(ids[i]) and rects.has(ids[j]) and (rects[ids[i]] as Rect2).intersects(rects[ids[j]]):
				return true
	return false


## 이름표 덩어리끼리 겹치지 않고, 8 px 넘게 움직인 덩어리마다 지시선 하나, 안 움직인 태그는 기준점(화면) 바로 위 가운데.
func _tags_ok(wt, what: String) -> void:
	wt.layout(true)
	var ids: Array = wt.stacks.keys()
	var hits := []
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if (wt.stacks[ids[i]] as Rect2).intersects(wt.stacks[ids[j]]):
				hits.append([ids[i], ids[j]])
	var moved := ids.filter(func(id): return absf(wt.stacks[id].position.y - wt.desired[id].position.y) > wt.LEADER_PX)
	var seated := true
	for t in wt.tags:
		if wt.rects.has(t.id) and not moved.has(t.id) and wt.stacks[t.id] == wt.desired[t.id]:
			var p := _camera.unproject_position(t.anchor)
			seated = seated and absf(wt.rects[t.id].get_center().x - p.x) < 0.5 and absf(wt.rects[t.id].end.y - p.y) < 0.5
	_check(ids.size() >= 6 and hits.is_empty() and wt.leaders.size() == moved.size() and seated,
		"(T) %s: %d tag stacks, none overlap; %d moved more than 8 px, each with a leader line; unmoved tags sit on their anchors" % [what, ids.size(), moved.size()],
		"overlaps=%s leaders=%d moved=%s" % [hits, wt.leaders.size(), moved])


## 어느 이름표 덩어리도 병사 상자에 닿지 않는다.
func _soldiers_clear(wt, what: String) -> void:
	wt.layout(true)
	var hits := []
	for id in wt.stacks:
		for o in wt.obstacles:
			if (wt.stacks[id] as Rect2).intersects(o):
				hits.append(id)
				break
	_check(not wt.obstacles.is_empty() and hits.is_empty(), "(T) %s: no tag or bubble covers the soldier formation (%d soldier boxes)" % [what, wt.obstacles.size()], "covering=%s" % [hits])


## (U) 개정 17 §4: 상세 스킬 줄(R 2줄, SSR 3줄) — 잠긴 줄은 회색·자물쇠·"★3에서 해금", 승급 미리보기 둘째 줄에 다음 해금,
##     [승급]으로 ★3이 되면 알림 "스킬 해금! 철벽" + 그 줄이 열려 금색으로 반짝인다. 끝나면 보유·승급을 되돌린다.
func _skill_unlock_ui(heroes_win) -> void:
	var keep := [Economy.heroes.duplicate(), Economy.hero_shards.duplicate(), Economy.hero_promotions.duplicate()]
	var ui: Array = heroes_win.skill_ui
	Economy.hero_promotions["hans"] = 0
	heroes_win.show_detail("hans")
	await _unguarded(heroes_win)
	var shown: Array = ui.filter(func(u): return u.box.visible)
	_check(shown.size() == 2 and not ui[0].lock.visible and ui[1].lock.visible and ui[0].label.text.begins_with("흡혈 — ") and ui[1].label.text == "철벽 — ★3에서 해금"
		and ui[1].label.get_theme_color("font_color") == heroes_win.LOCKED_GRAY and ui[0].label.get_theme_color("font_color") == HudScript.INK,
		"(U) R hans at ★0: two skill rows, the second grey with a lock and ★3에서 해금", "rows=%s" % [shown.map(func(u): return u.label.text)])
	Economy.heroes["ignis"] = maxi(1, int(Economy.heroes.get("ignis", 0)))
	Economy.hero_promotions["ignis"] = 0
	heroes_win.show_detail("ignis")
	_check(ui.all(func(u): return u.box.visible) and ui[1].label.text == "화상 — ★3에서 해금" and ui[2].label.text == "신속 — ★5에서 해금"
		and heroes_win.promote_preview.text.ends_with("\n★3 달성 시 스킬 해금: 화상"),
		"(U) SSR ignis at ★0: three rows (화상 at ★3, 신속 at ★5) and the preview names the next unlock", "rows=%s preview=%s" % [ui.map(func(u): return u.label.text), heroes_win.promote_preview.text])
	var notices := []
	var grab := func(t: String): notices.append(t)
	Economy.notice.connect(grab)
	Economy.hero_shards["arteon"] = GameData.promote_cost(2)
	Economy.hero_promotions["arteon"] = 2
	heroes_win.show_detail("arteon")
	await _unguarded(heroes_win)
	var locked_before: bool = ui[1].lock.visible
	var shown0: int = heroes_win.unlocks_shown
	await _tap(heroes_win.promote_button.get_global_rect().get_center())
	await _frames(2)
	var col: Color = ui[1].label.get_theme_color("font_color")
	_check(locked_before and Economy.promotion_of("arteon") == 3 and notices.has("스킬 해금! 철벽") and heroes_win.unlocks_shown == shown0 + 1 and not ui[1].lock.visible
		and ui[1].label.text.contains("받는 피해를 25% 줄입니다") and col != heroes_win.LOCKED_GRAY and col != HudScript.INK and ui[2].lock.visible
		and heroes_win.promote_preview.text.ends_with("\n★5 달성 시 스킬 해금: 용기의 오라"),
		"(U) [승급] to ★3 unlocks 철벽: notice 스킬 해금! 철벽, the row opens and flashes gold, the preview moves on to ★5",
		"promo=%d notices=%s shown=%d row=%s color=%s preview=%s" % [Economy.promotion_of("arteon"), notices, heroes_win.unlocks_shown, ui[1].label.text, col, heroes_win.promote_preview.text])
	Economy.notice.disconnect(grab)
	Economy.heroes = keep[0]
	Economy.hero_shards = keep[1]
	Economy.hero_promotions = keep[2]
	Economy.roster_changed.emit()
	Economy.changed.emit()
	heroes_win.show_detail("hans")


## (rr) 재모집·자동 모집: [재모집]이 같은 모집을 되풀이, 골드 부족 비활성, 자동이 골드 부족·SSR에서 멈춤, [확인]이 자동을 멈춤, 체크 저장(임시 파일).
func _recruit_repeat(recruit) -> void:
	var keep := [Economy.gold_tenths, Fever.auto_recruit, Fever.auto_next, Fever.save_path]
	recruit.auto_delay = 0.05
	recruit.auto_box.button_pressed = false
	# [재모집]: 10회 결과 → 재모집 → 2700↓. 3300 → 600이 되면 비활성 + 골드 부족
	Economy.gold_tenths = 60000
	Economy.changed.emit()
	recruit.open()
	await _unguarded(recruit)
	recruit._recruit(10)
	await _frames(2)
	_check(recruit.is_showing_results() and Economy.gold == 3300 and recruit.again_button.text == "재모집 2700" and not recruit.again_button.disabled and recruit.cards.size() == 10,
		"(rr) the 10-pull result shows [재모집 2700] enabled", "gold=%d text=%s" % [Economy.gold, recruit.again_button.text])
	await _unguarded(recruit)
	await _tap(recruit.again_button.get_global_rect().get_center())
	await _frames(2)
	_check(Economy.gold == 600 and recruit.cards.size() == 10 and recruit.again_button.disabled and recruit.again_button.text.contains("골드 부족"),
		"(rr) [재모집] repeats the 10-pull (gold -2700) and is disabled with 골드 부족 at 600 gold", "gold=%d text=%s" % [Economy.gold, recruit.again_button.text])
	recruit.close()
	# 시드: 10연차 3번에 SSR이 없는 시드(골드 부족 정지), 1회 두 번째에 SSR이 처음 나오는 시드(SSR 정지)
	var lvl: int = Economy.building_level(GameData.TAVERN)
	var seed_no_ssr := -1
	var seed_ssr2 := -1
	for s in range(1, 400):
		var r := RandomNumberGenerator.new()
		r.seed = s
		var ssr_seen := false
		for i in 3:
			ssr_seen = ssr_seen or Economy.roll_gacha(10, r.randf, lvl).any(func(x): return x.grade == "SSR")
		if not ssr_seen and seed_no_ssr < 0:
			seed_no_ssr = s
		var r2 := RandomNumberGenerator.new()
		r2.seed = s
		var a: bool = Economy.roll_gacha(1, r2.randf, lvl)[0].grade == "SSR"
		var b: bool = Economy.roll_gacha(1, r2.randf, lvl)[0].grade == "SSR"
		if not a and b and seed_ssr2 < 0:
			seed_ssr2 = s
	_check(seed_no_ssr > 0 and seed_ssr2 > 0, "(rr) precondition: found RNG seeds for the auto cases", "no_ssr=%d ssr2=%d" % [seed_no_ssr, seed_ssr2])
	# 자동: 8200골드 = 10회 3번 + 100 → 3번 뽑고 멈춤
	Economy.rng.seed = seed_no_ssr
	Economy.gold_tenths = 82000
	Economy.changed.emit()
	recruit.open()
	await _unguarded(recruit)
	recruit.auto_box.button_pressed = true
	recruit._recruit(10)
	for i in 120:
		await _frames(1)
	_check(Economy.gold == 100 and recruit.again_button.disabled and not recruit.auto_running() and recruit.auto_box.button_pressed,
		"(rr) auto loops 10-pulls until gold is short (8200 -> 100), then stops", "gold=%d running=%s" % [Economy.gold, recruit.auto_running()])
	recruit.close()
	# 자동: 1회 모집 두 번째에서 SSR → 멈추고 SSR 카드 강조, 골드는 남아도 더 안 뽑는다
	Economy.rng.seed = seed_ssr2
	Economy.gold_tenths = 10000
	Economy.changed.emit()
	recruit.open()
	await _unguarded(recruit)
	recruit.auto_box.button_pressed = true
	recruit._recruit(1)
	for i in 120:
		await _frames(1)
	_check(Economy.gold == 400 and not recruit.auto_running() and recruit.cards.size() == 1 and recruit.cards[0].highlight and recruit.is_showing_results()
		and recruit.again_button.text == "재모집 300" and not recruit.again_button.disabled,
		"(rr) auto stops when an SSR is pulled (2nd pull): results stay up, the SSR card is highlighted, [재모집] is manual again",
		"gold=%d running=%s hl=%s" % [Economy.gold, recruit.auto_running(), recruit.cards[0].highlight if recruit.cards.size() == 1 else null])
	recruit.close()
	# [확인]은 자동을 멈추고 체크를 푼다
	Economy.rng.seed = seed_no_ssr
	Economy.gold_tenths = 82000
	Economy.changed.emit()
	recruit.auto_delay = 5.0
	recruit.open()
	await _unguarded(recruit)
	recruit.auto_box.button_pressed = true
	recruit._recruit(10)
	await _frames(2)
	_check(recruit.auto_running() and recruit.again_button.text == "자동 중…", "(rr) while auto runs [재모집] reads 자동 중…", "text=%s" % recruit.again_button.text)
	recruit.confirm_button.pressed.emit()
	recruit.auto_delay = 0.05
	var g0: int = Economy.gold
	for i in 40:
		await _frames(1)
	_check(not recruit.auto_box.button_pressed and not recruit.auto_running() and Economy.gold == g0 and not recruit.is_showing_results(),
		"(rr) [확인] stops auto (box unchecked) and no further pull happens", "gold=%d->%d" % [g0, Economy.gold])
	recruit.close()
	# 체크 저장: 임시 파일, 다른 키는 그대로
	var tmp := "user://test_local_recruit.json"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string(JSON.stringify({"other": 7}))
	f.close()
	Fever.save_path = tmp
	recruit.auto_box.button_pressed = true
	var data = JSON.parse_string(FileAccess.get_file_as_string(tmp))
	Fever.auto_recruit = false
	Fever.load_save()
	_check(data is Dictionary and data.get("auto_recruit") == true and data.get("other") == 7 and Fever.auto_recruit,
		"(rr) the 자동 모집 checkbox persists in local.json (other keys kept) and loads back", "data=%s" % [data])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	Fever.save_path = keep[3]
	Fever.auto_recruit = keep[1]
	Fever.auto_next = keep[2]
	recruit.auto_box.set_pressed_no_signal(false)
	Economy.gold_tenths = keep[0]
	Economy.changed.emit()


## 상인 창: 여러 칸을 동시에 열고 [선택 판매]로 한 번에 판다(판 뒤 수량 0, 칸은 열림). 세 칸이 720x1280 안에 들어간다.
func _multi_sell_checks(panel) -> void:
	Economy.res["wood"] = 30
	Economy.res["stone"] = 4
	Economy.res["food"] = 20
	Economy.changed.emit()
	await _frames(2)
	for id in ["wood", "stone", "food"]:
		await _tap(panel.sell_buttons[id].get_global_rect().get_center())
		await _frames(3)  # 펼친 뒤 레이아웃이 자리 잡는 것을 기다린다
	var all_open: bool = panel.qty_boxes["wood"].visible and panel.qty_boxes["stone"].visible and panel.qty_boxes["food"].visible
	var r: Rect2 = panel.dialog.get_global_rect()
	_check(all_open and r.position.y >= 0.0 and r.end.y <= 1280.0 and panel.sell_selected_button.get_global_rect().end.y <= 1280.0 and panel.sell_selected_button.disabled,
		"(p3) opening another row keeps the others open; three boxes fit 720x1280; [sell selected] disabled at total 0", "open=%s rect=%s qtys=%s" % [all_open, r, panel.qtys])
	panel._set_qty("wood", 10)
	panel._set_qty("stone", 2)
	panel._set_qty("food", 5)
	var now := Time.get_unix_time_from_system()
	var items := {"wood": 10, "stone": 2, "food": 5}
	var gold := 0
	for id in items:
		gold += Economy.sell_value(id, items[id], Economy.current_rate(id, now))
	_check(panel.sell_selected_button.text == "선택 판매 · %s골드" % HudScript.commas(gold) and not panel.sell_selected_button.disabled,
		"(p3) [sell selected] shows the sum of floor(amount x price x each rate)", "text=%s gold=%d" % [panel.sell_selected_button.text, gold])
	var g0: int = Economy.gold_tenths
	await _tap(panel.sell_selected_button.get_global_rect().get_center())
	_check(Economy.res["wood"] == 20 and Economy.res["stone"] == 2 and Economy.res["food"] == 15 and Economy.gold_tenths == g0 + gold * 10,
		"(p3) [sell selected] sells every open box's amount in one action", "wood=%d stone=%d food=%d gold=%d->%d" % [Economy.res["wood"], Economy.res["stone"], Economy.res["food"], g0, Economy.gold_tenths])
	var kept: bool = panel.qty_boxes["wood"].visible and panel.qty_boxes["stone"].visible and panel.qty_boxes["food"].visible
	_check(kept and panel.qtys["wood"] == 0 and panel.qtys["stone"] == 0 and panel.qtys["food"] == 0 and panel.sell_selected_button.disabled,
		"(p3) after selling the amounts reset to 0 and the boxes stay open", "kept=%s" % kept)
	panel._set_qty("wood", 3)
	await _tap(panel.sell_buttons["wood"].get_global_rect().get_center())
	_check(not panel.qty_boxes["wood"].visible and panel.qtys["wood"] == 0 and panel.qty_boxes["stone"].visible and panel.sell_selected_button.disabled,
		"(p3) tapping a row's [sell] again folds only that box and zeroes its amount", "wood_open=%s" % panel.qty_boxes["wood"].visible)
	await _tap(panel.sell_buttons["stone"].get_global_rect().get_center())
	await _tap(panel.sell_buttons["food"].get_global_rect().get_center())


## 개정 19: Lv 7 막사 창은 T2, 1마리 3:00:00, 비용 ×5, 다음 레벨 미리보기를 보여 준다(Lv 6은 "Lv 7 → T2 해금").
func _barracks_t2_window() -> void:
	var bwin = _building_win()
	Economy.res = {"wood": 100000, "stone": 100000, "food": 100000}
	Economy.levels.barracks = 6
	Economy.changed.emit()
	bwin.close()
	bwin.open_building("barracks")
	await _frames(1)
	_check(bwin.unit_label.text == "T1 보병 · 1마리 30:00" and bwin.next_label.visible and bwin.next_label.text == "Lv 7 → T2 해금" and bwin._train_type == "infantry:1",
		"(S) Lv 6 barracks: T1 30:00 and the preview 'Lv 7 → T2 해금'", "unit=%s next=%s" % [bwin.unit_label.text, bwin.next_label.text])
	Economy.levels.barracks = 7
	Economy.changed.emit()
	await _frames(1)
	_check(bwin.unit_label.text == "T2 보병 · 1마리 3:00:00" and bwin._train_type == "infantry:2" and bwin.train_cost_labels.food.text == "150" and bwin.train_cost_labels.wood.text == "100"
		and bwin.train_time_label.text == "훈련 시간 3:00:00" and bwin.next_label.text == "1마리 3:00:00 → 2:30:00" and not bwin.train_button.disabled,
		"(S) Lv 7 barracks: T2 보병 1마리 3:00:00, cost x5 (150 food / 100 wood), preview '1마리 3:00:00 → 2:30:00'",
		"unit=%s food=%s wood=%s next=%s" % [bwin.unit_label.text, bwin.train_cost_labels.food.text, bwin.train_cost_labels.wood.text, bwin.next_label.text])
	Economy.levels.barracks = 1
	Economy.changed.emit()
	await _frames(1)

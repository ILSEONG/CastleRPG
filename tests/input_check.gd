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

	# (l) 영웅 없이 벌목장 탭 → 목재 +100, "+N" 뜸, 선택 없음 유지. 곧바로 또 탭하면 0이라 pop 없음
	var lp := _building_px("lumber")
	_check(_picker._pick(lp, PickerScript.LAYER_TAP).get("collider") != null and _picker._pick(lp, PickerScript.LAYER_TAP).collider.get_meta("building", "") == "lumber",
		"(l) precondition: lumber tap point hits the lumber tap body", "px=%s" % lp)
	await _tap(lp)
	_check(Economy.res["wood"] == 100 and badges.last_pop.get("amount", 0) == 100 and badges.last_pop.get("kind", "") == "wood" and _picker.selected == null,
		"(l) lumber tap collects 100 wood and pops +100", "wood=%d pop=%s" % [Economy.res["wood"], badges.last_pop])
	badges.last_pop = {}
	await _tap(lp)
	_check(Economy.res["wood"] == 100 and badges.last_pop.is_empty(), "(l) second tap collects nothing and shows no pop", "wood=%d pop=%s" % [Economy.res["wood"], badges.last_pop])

	# (m) 영웅 선택 중 벌목장 탭 → 수집되고 선택·위치 유지(이동 명령 없음)
	var hero_pre := [warrior.side, warrior.post, warrior.free_pos]
	_picker._select(warrior)
	Economy.last_collect["lumber"] = Time.get_unix_time_from_system() - 600.0
	await _tap(lp)
	_check(_picker.selected == warrior and Economy.res["wood"] == 200 and [warrior.side, warrior.post, warrior.free_pos] == hero_pre,
		"(m) lumber tap with a hero selected collects and keeps the selection without a move", "selected=%s wood=%d" % [_name(_picker.selected), Economy.res["wood"]])

	# (n) 기능 없는 건물(성채) 탭: 영웅 선택 중이면 바닥 이동 / 없으면 선택 해제 (수집·창 없음)
	var gold0: int = Economy.gold
	var kp := _building_px("keep")
	_check(_picker._pick(kp, PickerScript.LAYER_TAP).collider.get_meta("building", "") == "keep" and not _open_hero(kp),
		"(n) precondition: keep tap point hits the keep body, no hero nearby", "px=%s" % kp)
	await _tap(kp)
	_check(_picker.selected == warrior and warrior.post == Formation.POST_FREE and warrior.free_pos != hero_pre[2] and not panel.is_open() and Economy.gold == gold0,
		"(n) keep tap with a hero selected falls through to a ground move", "post=%d free=%s" % [warrior.post, warrior.free_pos])
	_picker._select(null)
	await _tap(_hero_px(warrior))
	_check(_picker.selected == warrior, "(n) precondition: warrior re-selected", "selected=%s" % _name(_picker.selected))
	_picker._select(null)
	await _tap(kp)
	_check(_picker.selected == null and not panel.is_open(), "(n) keep tap with no hero selected stays deselected", "selected=%s" % _name(_picker.selected))

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
	await _tap(bp)
	_check(Economy.res["wood"] == 0 and Economy.gold_tenths == 105 + expect * 10 and Economy.gold == 10 + expect and Economy.res["stone"] == 7 and panel.is_open(),
		"(p) [sell] on wood zeroes wood and adds floor(200 x price x wood's own rate) whole gold (x10 tenths, 0.5 kept); others stay", "wood=%d tenths=%d expect=%d" % [Economy.res["wood"], Economy.gold_tenths, 105 + expect * 10])
	_check(panel.sell_buttons["wood"].disabled and not panel.sell_buttons["stone"].disabled, "(p) sell button is disabled at 0 holdings only", "")
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


## 개정 10: 주점 탭 → 모집 창 → 1회 모집(오프라인), 창이 열린 동안 뒤 입력 차단, [영웅] → 영웅 창 슬롯·카드 탭 배치·정보·적용.
func _recruit_and_heroes(rig) -> void:
	var recruit: Node = null
	var heroes_win: Node = null
	var hud: Node = null
	for c in _main.get_children():
		if c.get_script() == preload("res://scripts/recruit_panel.gd"):
			recruit = c
		elif c.get_script() == preload("res://scripts/hero_panel.gd"):
			heroes_win = c
		elif c.get_script() == preload("res://scripts/hud.gd"):
			hud = c
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

	# (t) 창이 열린 동안 뒤 입력이 막힌다: 창 안에서 끌어도 카메라 그대로, HUD [영웅] 자리 탭은 배경 탭이라 창만 닫힌다
	var hb: Vector2 = hud.hero_button.get_global_rect().get_center()
	_check(not recruit.dialog.get_global_rect().has_point(hb), "(t) precondition: the [영웅] button is outside the recruit dialog", "px=%s" % hb)
	var cam_pos: Vector3 = rig.position
	var dp: Vector2 = recruit.dialog.get_global_rect().position + Vector2(300, 20)
	_mouse_button(dp, true)
	for i in 6:
		_mouse_motion(dp + Vector2(0, 12) * (i + 1), Vector2(0, 12))
	_mouse_button(dp + Vector2(0, 72), false)
	await _frames(2)
	_check(rig.position == cam_pos, "(t) dragging on the backdrop does not pan the camera", "pos=%s" % rig.position)
	await get_tree().create_timer(0.45).timeout
	await _tap(hb)
	_check(not recruit.is_open() and not heroes_win.is_open(), "(t) a tap on the [영웅] spot while the recruit window is open only closes the window",
		"recruit=%s heroes=%s" % [recruit.is_open(), heroes_win.is_open()])

	# (u) [영웅] → 영웅 창: 슬롯 4칸, 보유 격자(등급 → 이름)
	Economy.heroes["arteon"] = 2  # 별 1
	Economy.roster_changed.emit()
	await _tap(hb)
	await _frames(2)
	_check(heroes_win.is_open() and heroes_win.is_guarded(), "(u) precondition: the hero window just opened (open guard)", "")
	await _tap(heroes_win.slot_cards[0].get_global_rect().get_center())  # 연타의 두 번째 누름이 슬롯 카드에 떨어진다
	_check(heroes_win.selected_slot == -1, "(u) a card press right after the hero window opens is ignored", "sel=%d" % heroes_win.selected_slot)
	await _guard_wait()
	var keys: Array = heroes_win.hero_cards.keys()
	var sorted_ok := true
	for i in range(1, keys.size()):
		var a: Dictionary = GameData.hero(keys[i - 1])
		var b: Dictionary = GameData.hero(keys[i])
		var ra: int = heroes_win.GRADE_RANK[a.grade]
		var rb: int = heroes_win.GRADE_RANK[b.grade]
		sorted_ok = sorted_ok and (ra < rb or (ra == rb and a.name <= b.name))
	_check(heroes_win.is_open() and heroes_win.slot_cards.size() == 4 and keys.size() == Economy.heroes.size() and sorted_ok and GameData.hero(keys[0]).grade == "SSR",
		"(u) [영웅] opens the hero window: 4 slots, owned grid sorted by grade then name", "open=%s slots=%d keys=%s" % [heroes_win.is_open(), heroes_win.slot_cards.size(), keys])
	_check(heroes_win.slot_cards.map(func(c): return c.hero_id) == ["hans", "ella", "dorik", "nina"] and heroes_win.hero_cards.arteon.stars == 1 and heroes_win.apply_button.disabled,
		"(u) slots show the deploy, cards show stars, [적용] off with no change", "")

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

	# (w) [정보]·길게 누르기 → 상세(능력치 별 반영, 스킬 문장, 설명문) → [뒤로]
	await _tap(heroes_win.info_button.get_global_rect().get_center())
	await _frames(2)
	_check(heroes_win.is_showing_detail() and heroes_win._detail_stats.text.contains("HP 1144") and heroes_win._detail_skills.text.contains("6초마다 반경 6m")
		and heroes_win._detail_skills.text.contains("받는 피해를 25% 줄입니다") and heroes_win._detail_desc.text == GameData.hero("arteon").desc,
		"(w) [정보] shows stats with the star bonus, both skill sentences with numbers and the description",
		"stats=%s skills=%s" % [heroes_win._detail_stats.text, heroes_win._detail_skills.text])
	await _tap(heroes_win._detail_view.get_child(heroes_win._detail_view.get_child_count() - 1).get_global_rect().get_center())
	await _frames(2)
	var kp: Vector2 = heroes_win.hero_cards.nina.get_global_rect().get_center()
	_mouse_button(kp, true)
	await get_tree().create_timer(0.6).timeout
	_mouse_button(kp, false)
	await _frames(2)
	_check(heroes_win.is_showing_detail() and heroes_win._detail_title.text.contains(GameData.hero("nina").name) and heroes_win.work == ["ella", "arteon", "dorik", "nina"],
		"(w) a long press on a card opens its detail without placing it", "title=%s" % heroes_win._detail_title.text)
	heroes_win._show_main()
	await _frames(2)

	# (x) [적용] → 배치 저장, 방치 모드라 영웅이 곧바로 바뀐다(아르테온 별 1: HP × 1.1)
	var pre := get_tree().get_nodes_in_group("heroes")
	pre.sort_custom(func(a, b): return a.index < b.index)
	await _tap(heroes_win.apply_button.get_global_rect().get_center())
	await _frames(2)
	var live := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.is_alive())
	live.sort_custom(func(a, b): return a.index < b.index)
	var ids := live.map(func(h): return h.def.id)
	_check(Economy.deploy == ["ella", "arteon", "dorik", "nina"] and heroes_win.apply_button.disabled and ids == ["ella", "arteon", "dorik", "nina"]
		and is_equal_approx(live[1].hp_max, 1040.0 * 1.1) and live[1].side == 1 and live[1].post == Formation.POST_GATE and hud._toast.visible,
		"(x) [적용] saves the deploy and, in idle mode, swaps the heroes at once (arteon slot 2 at the east gate, star bonus)",
		"deploy=%s ids=%s" % [Economy.deploy, ids])
	_check(not is_instance_valid(pre[0]) and not is_instance_valid(pre[1]) and live[2] == pre[2] and live[3] == pre[3],
		"(x) only the changed slots are rebuilt: slots 1-2 are new heroes, slots 3-4 keep theirs", "")
	await get_tree().create_timer(0.45).timeout
	await _tap(Vector2(30, 40))  # 위 칩 줄 높이 — 창 바깥 배경
	_check(not heroes_win.is_open(), "(x) a backdrop tap closes the hero window", "")

	# (y) 늦게 온 모집 결과(온라인): 다른 창이 열려 있으면 그 위로 모집 창을 열지 않고 알림, 다음에 주점 창을 열 때 보여 준다.
	#     아무 창도 없으면 모집 창을 열어 보여 준다.
	var late := [{"hero_id": "jack", "grade": "R", "new": false, "copies": 2}]
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

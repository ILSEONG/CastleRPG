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
	await _tap(bp)  # [판매] → 수량 칸이 펼쳐진다. [최대] → [판매]로 전량
	await _tap(panel.qty_max["wood"].get_global_rect().get_center())
	await _tap(panel.qty_confirms["wood"].get_global_rect().get_center())
	_check(Economy.res["wood"] == 0 and Economy.gold_tenths == 105 + expect * 10 and Economy.gold == 10 + expect and Economy.res["stone"] == 7 and panel.is_open(),
		"(p) [sell] on wood zeroes wood and adds floor(200 x price x wood's own rate) whole gold (x10 tenths, 0.5 kept); others stay", "wood=%d tenths=%d expect=%d" % [Economy.res["wood"], Economy.gold_tenths, 105 + expect * 10])
	_check(panel.sell_buttons["wood"].disabled and not panel.sell_buttons["stone"].disabled, "(p) sell button is disabled at 0 holdings only", "")
	await _qty_sell_checks(panel)
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
	#     [병사] → "병사 준비 중" 빈 시트, 다시 → 닫힘
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
		and big.end.x > 680.0 and absf(big.get_center().y - title.get_center().y) < 8.0 and absf(big.size.y - 64.0) < 1.0,
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
	_check(soldiers.is_open() and not recruit.is_open() and tabs.selected == "soldier" and soldiers.content.get_child(1).text == soldiers.EMPTY_TEXT
		and sheet0.end.y <= bar_rect.position.y and sheet0.size.y > 1000.0, "(t) [병사] closes the recruit window and opens the empty soldier sheet (병사 준비 중) above the tab bar",
		"open=%s selected=%s sheet=%s" % [soldiers.is_open(), tabs.selected, sheet0])
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
	Economy.heroes["arteon"] = 2  # 별 1
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
	_check(ac.level == 1 and ac.stars == 1 and ac.power == GameData.hero_power(GameData.hero("arteon"), 1, 2) and not ac.deployed and heroes_win.hero_cards.hans.deployed
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

	# (w) [적용] → 배치 저장, 방치 모드라 영웅이 곧바로 바뀐다(아르테온 별 1: HP × 1.1)
	var pre := get_tree().get_nodes_in_group("heroes")
	pre.sort_custom(func(a, b): return a.index < b.index)
	await _tap(heroes_win.apply_button.get_global_rect().get_center())
	await _frames(2)
	var live := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.is_alive())
	live.sort_custom(func(a, b): return a.index < b.index)
	var ids := live.map(func(h): return h.def.id)
	_check(Economy.deploy == ["ella", "arteon", "dorik", "nina"] and heroes_win.apply_button.disabled and ids == ["ella", "arteon", "dorik", "nina"]
		and is_equal_approx(live[1].hp_max, 1040.0 * 1.1) and live[1].side == 1 and live[1].post == Formation.POST_GATE and hud._toast.visible,
		"(w) [적용] saves the deploy and, in idle mode, swaps the heroes at once (arteon slot 2 at the east gate, star bonus)",
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
	_check(heroes_win.stat_values[0].text == "1,144" and heroes_win.stat_nexts[0].text == "→ 1,213 (+69)" and heroes_win.stat_values[1].text == "46"
		and heroes_win.stat_nexts[1].text == "→ 49 (+3)" and heroes_win.stat_values[2].text == "0.8초" and heroes_win.stat_nexts[2].text == ""
		and heroes_win.stat_values[4].text == str(GameData.hero_power(arteon, 1, 2)) and heroes_win.level_label.text == "Lv 1 / 30",
		"(x) stats with the star bonus and the next level in green (HP 1,144 -> 1,213 (+69)); Lv 1 / 30 at one star",
		"hp=%s next=%s atk=%s level=%s" % [heroes_win.stat_values[0].text, heroes_win.stat_nexts[0].text, heroes_win.stat_values[1].text, heroes_win.level_label.text])
	_check(heroes_win.skills_label.text.contains("6초마다 반경 6m") and heroes_win.skills_label.text.contains("받는 피해를 25% 줄입니다") and heroes_win.desc_label.text == arteon.desc
		and heroes_win.title_label.text == "빛의 성기사 아르테온" and heroes_win.grade_label.text.begins_with("SSR"),
		"(x) title, grade, both skill sentences with numbers and the description", "")
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
		and heroes_win.stat_values[0].text == "1,213" and heroes_win.celebrations == 1 and heroes_win.big_card.is_bursting()
		and heroes_win.stat_values[0].get_theme_color("font_color") != HudScript.INK and heroes_win.stat_values[2].get_theme_color("font_color") == HudScript.INK,
		"(x) [레벨업] takes 120 gold (1200 tenths) and no food, Lv 2, light burst, changed stats flash green",
		"level=%d tenths=%d food=%d label=%s" % [Economy.level_of("arteon"), Economy.gold_tenths, Economy.res["food"], heroes_win.level_label.text])
	_check(live.size() == 4 and live[1].def.id == "arteon" and live[1] != pre[1] and is_equal_approx(live[1].hp_max, 1040.0 * 1.06 * 1.1)
		and is_equal_approx(live[1].atk, 42.0 * 1.06 * 1.1) and live[0] == pre[0] and live[2] == pre[2] and live[3] == pre[3],
		"(x) idle mode rebuilds only the leveled hero with HP/atk x(1 + 0.06) x 1.1", "hp=%.1f" % live[1].hp_max)
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
	await _tap(heroes_win.prev_button.get_parent().get_child(1).get_global_rect().get_center())  # [닫기]
	_check(heroes_win.is_open() and not heroes_win.is_showing_detail() and heroes_win.is_guarded() and heroes_win.hero_cards.arteon.level == 5,
		"(x) [닫기] returns to the list (guarded); the card shows Lv 5", "")
	await _guard_wait()
	await _tap(Vector2(30, 40))  # 위 칩 줄 높이 — 시트 바깥 배경
	_check(not heroes_win.is_open() and tabs.selected == "", "(x) a backdrop tap above the sheet closes it and no tab is selected", "")

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
	await _guard_wait()
	await _buildings_ui(tabs, hud, recruit)
	await _top_hud(hud)


## (z) 개정 12-2: 상단 스테이지 버튼(탭으로 진행 → 중지 예약 → 예약 취소)과 방향별 성 내구도(성문 막대 탭 → 카메라가 그 성문으로 0.4초,
##     줌 유지, 전장으로 새지 않음). 문루 위 방향 글자. 스테이지를 시작하므로 맨 끝에 둔다.
func _top_hud(hud) -> void:
	var half: float = _main.castle.half
	var rig = _camera.get_parent()
	_check(_main.castle.side_labels.map(func(l): return l.text) == ["북", "동", "남", "서"]
		and _main.castle.side_labels.all(func(l): return l.position.y > Balance.WALL_H + 2.0),
		"(z) direction letters 북·동·남·서 float above the four gatehouses", "")
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

	# 상단 버튼: 대기 "▶ 진행" → 탭 = 스테이지 시작 → "중지 예약" → 탭 = 예약 → "예약 취소" → 탭 = 취소
	var bp: Vector2 = hud._button.get_global_rect().get_center()
	_check(GameState.mode == GameState.Mode.IDLE and hud._button.text == "▶ 진행" and bp.y < 300.0, "(z) idle: the top button reads ▶ 진행", "text=%s at %s" % [hud._button.text, bp])
	await _tap(bp)
	_check(GameState.mode == GameState.Mode.STAGE and hud._button.text == "중지 예약", "(z) tapping it starts the stage; it now reads 중지 예약", "mode=%d text=%s" % [GameState.mode, hud._button.text])
	await _tap(bp)
	_check(GameState.stop_requested and hud._button.text == "예약 취소", "(z) tapping again books the stop; it reads 예약 취소", "text=%s" % hud._button.text)
	await _tap(bp)
	_check(not GameState.stop_requested and hud._button.text == "중지 예약", "(z) and again cancels the booking", "text=%s" % hud._button.text)


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
	_check(Economy.levels.values().all(func(l): return l == 1) and Economy.build.is_empty() and scenery.labels.lumber.text == "벌목장 Lv 1"
		and scenery.labels.keep.text == "성채 Lv 1" and scenery.labels.size() == Balance.BUILDINGS.size(), "(B) every building's name tag reads '이름 Lv N'",
		"lumber=%s keep=%s" % [scenery.labels.lumber.text, scenery.labels.keep.text])

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
	_check(bwin.effect_lines("houses", 1) == [["인구", "6", "8"]] and bwin.effect_lines("barracks", 3).is_empty() and bwin.effect_lines("lab", 2)[0] == ["영웅 공격", "+3%", "+6%"]
		and UiKit.duration(3900) == "1시간 5분" and UiKit.duration(59.2) == "01:00",
		"(B) effect sentences: 인구 6 → 8, barracks none (the soldier UI fills it), lab +3% → +6%; times mm:ss / h시간 m분", "")
	bwin.close()

	# 성채 [업그레이드]: 자원 300/300/200 감소, 일꾼 = 성채, 비계(기둥 4 + 가로대, AABB 둘레), 머리 위 막대, 창은 진행 막대 + 매초 남은 시간
	Economy.res = {"wood": 1000, "stone": 1000, "food": 1000}
	Economy.changed.emit()
	await _tap(_building_px("keep"))
	var rows: Array = bwin.reqs.get_children().map(func(l): return l.text)
	print("INPUT INFO: keep window (Lv 1, can upgrade) dialog %s, [업그레이드] %s" % [bwin.dialog.get_global_rect(), bwin.upgrade_button.get_global_rect()])
	_check(bwin.building_id == "keep" and rows == ["✓ 성문 Lv 1 필요", "✓ 막사 Lv 1 필요"] and bwin.reqs.get_child(0).get_theme_color("font_color") == bwin.GREEN
		and not bwin.upgrade_button.disabled and not bwin.reason_label.visible and bwin.time_label.text == "건설 시간 01:00"
		and bwin.effects.get_child(1).get_child(0).text == "성 HP 1,000" and bwin.effects.get_child(1).get_child(1).text == "→ 1,200" and bwin.effects.get_child(2).get_child_count() == 1,
		"(B) keep window: green ✓ prerequisites, 성 HP 1,000 → 1,200 (unchanged slots show no arrow), [업그레이드] on, 01:00", "reqs=%s" % [rows])
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
		and scenery.labels.keep.text == "성채 Lv 2" and get_tree().get_nodes_in_group("fx").size() >= fx0 + 5 and hud._toast.visible and hud._toast.text == "성채 Lv 2 완료",
		"(B) pulling the time in completes it: keep Lv 2, scaffold gone, tag '성채 Lv 2', light shards, notice '성채 Lv 2 완료'",
		"keep=%d scaffold=%s tag=%s fx=%d->%d toast=%s" % [Economy.building_level("keep"), scenery.scaffold_id, scenery.labels.keep.text, fx0,
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
	_check(Economy.building_level("lumber") == 2 and scenery.labels.lumber.text == "벌목장 Lv 2" and hud._toast.text == "벌목장 Lv 2 완료", "(B) lumber Lv 2 completes with its notice", hud._toast.text)

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


## 개정 14 §4 수량 칸: [판매] → 펼침, [+]·[−]·입력·슬라이더·[최대], 판매 후 보유 감소·골드 증가. stone 7개로 본다(창이 열려 있어야 한다).
func _qty_sell_checks(panel) -> void:
	var stone_btn: Button = panel.sell_buttons["stone"]
	await _tap(stone_btn.get_global_rect().get_center())
	_check(panel.qty_boxes["stone"].visible and not panel.qty_boxes["wood"].visible and panel.qty == 0 and panel.qty_confirms["stone"].disabled,
		"(p2) [sell] expands that row's quantity box (others folded); quantity 0 disables [sell]", "open=%s qty=%d" % [panel.open_res, panel.qty])
	var plus: Vector2 = panel.qty_plus["stone"].get_global_rect().get_center()
	await _tap(plus)
	await _tap(plus)
	await _tap(plus)
	await _tap(panel.qty_minus["stone"].get_global_rect().get_center())
	_check(panel.qty == 2 and panel.qty_edits["stone"].text == "2" and panel.qty_sliders["stone"].value == 2 and not panel.qty_confirms["stone"].disabled,
		"(p2) [+] x3 then [-] gives 2 (input and slider follow)", "qty=%d text=%s" % [panel.qty, panel.qty_edits["stone"].text])
	var edit: LineEdit = panel.qty_edits["stone"]
	edit.text = "99"
	edit.text_changed.emit("99")
	var over: bool = panel.qty == 7 and edit.text == "7"
	edit.text = "abc"
	edit.text_changed.emit("abc")
	var junk: bool = panel.qty == 0 and edit.text == "0"
	edit.text = "-4"
	edit.text_changed.emit("-4")
	_check(over and junk and panel.qty == 0, "(p2) input above holdings becomes holdings; text and negatives become 0", "over=%s junk=%s qty=%d" % [over, junk, panel.qty])
	await _tap(panel.qty_max["stone"].get_global_rect().get_center())
	_check(panel.qty == 7, "(p2) [max] sets the holdings", "qty=%d" % panel.qty)
	panel.qty_sliders["stone"].value = 3
	var rate: float = Economy.current_rate("stone", Time.get_unix_time_from_system())
	_check(panel.qty == 3 and panel.qty_gold_labels["stone"].text == "→ %s골드" % HudScript.commas(Economy.sell_value("stone", 3, rate)), "(p2) slider sets 3; label shows floor(3 x price x rate)", "qty=%d label=%s" % [panel.qty, panel.qty_gold_labels["stone"].text])
	var q0: int = panel.qty
	panel._hold_start(1)
	panel._tick_hold(0.3)
	var early: int = panel.qty
	panel._tick_hold(1.0)
	panel._hold_dir = 0
	_check(early == q0 + 1 and panel.qty > early, "(p2) holding [+]: one step at once, no repeat before 0.4 s, then it accelerates", "q0=%d early=%d after=%d" % [q0, early, panel.qty])
	panel._set_qty(3)
	var gold0: int = Economy.gold_tenths
	await _tap(panel.qty_confirms["stone"].get_global_rect().get_center())
	_check(Economy.res["stone"] == 4 and Economy.gold_tenths == gold0 + Economy.sell_value("stone", 3, rate) * 10 and panel.qty_boxes["stone"].visible,
		"(p2) quantity [sell] sells only that many (holdings drop, gold rises)", "stone=%d gold=%d->%d" % [Economy.res["stone"], gold0, Economy.gold_tenths])
	await _tap(stone_btn.get_global_rect().get_center())  # 다시 누르면 접힌다
	_check(not panel.qty_boxes["stone"].visible and panel.open_res == "", "(p2) tapping [sell] again folds the box", "open=%s" % panel.open_res)

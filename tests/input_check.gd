extends Node
## 헤드리스 입력 체크: 실제 main 씬(오토로드 포함)에 입력을 넣어 탭·드래그·핀치 판정을 확인한다.
## 실행: ./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/input_check.tscn
## 오토로드를 쓰므로 tests/run_tests.gd(-s)에서 preload 금지.
## 헤드리스 창은 64×64라 논리 화면이 1280×1280이 되고 Input.parse_input_event 좌표가 20배로 재조정된다 →
## 창을 360×640으로 맞춰 논리 화면을 폰과 같은 720×1280으로 만들고, 마우스는 viewport.push_input(ev, true)(논리 좌표),
## 터치는 엔진의 마우스 에뮬레이션을 거치도록 Input.parse_input_event에 창 좌표(final_transform 적용)로 넣는다.

const Balance := preload("res://scripts/balance.gd")
const Formation := preload("res://scripts/formation.gd")
const PickerScript := preload("res://scripts/unit_picker.gd")

var _fails := 0
var _main
var _camera: Camera3D
var _picker
var _heroes: Array = []


func _ready() -> void:
	get_window().size = Vector2i(360, 640)
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(5)
	_camera = _main.camera
	for c in _main.get_children():
		if c.get_script() == PickerScript:
			_picker = c
	_heroes = get_tree().get_nodes_in_group("heroes")
	_heroes.sort_custom(func(a, b): return a.index < b.index)
	await _run()
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

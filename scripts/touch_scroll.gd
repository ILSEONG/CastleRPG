extends Node
## 손가락 끌기 스크롤(사용자 2026-10-07 "스크롤이 있는 화면은 스크롤이 안먹혀"): 목록 칸은 대부분 버튼(MOUSE_FILTER_STOP)이라
## 누름을 버튼이 먹고 ScrollContainer까지 올라가지 않는다 — 그래서 버튼 위에서 시작한 끌기는 목록을 못 굴렸다.
## 여기서 화면 입력을 GUI보다 먼저 본다(_input). 누른 자리 맨 위 컨트롤의 조상 중 ScrollContainer가 있고 손가락이 DEADZONE 넘게
## 움직이면 그 목록을 직접 굴린다(그 끌기의 움직임은 GUI로 안 보낸다). 누른 버튼은 NOTIFICATION_SCROLL_BEGIN으로 취소돼
## 손을 떼도 눌리지 않는다. 놓으면 관성으로 조금 더 미끄러진다. 짧게 탭하면 지금처럼 버튼이 눌린다.
## 터치는 emulate_mouse_from_touch로 왼쪽 마우스 이벤트가 되므로 마우스만 본다(PC 마우스 끌기도 같은 동작).

const DEADZONE := 14.0  # 이만큼 움직여야 스크롤(그 전엔 탭)
const FRICTION := 4.0  # 관성 감속(초당 비율)
const MIN_FLING := 60.0  # 이 속도(px/s) 아래면 관성 멈춤
const MAX_FLING := 5000.0

var _press := false
var _start := Vector2.ZERO
var _hit: Control  # 누른 자리 맨 위 컨트롤
var _scroll: ScrollContainer  # 끌고 있는 목록
var _axis := 1  # 0 가로, 1 세로
var _vel := 0.0  # 관성 속도(px/s, 스크롤 값 기준)
var _last_us := 0
var _fling: ScrollContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_fling = null
			_press = true
			_start = event.position
			_scroll = null
			_hit = find_control_at(get_tree().root, event.position)
		else:
			_press = false
			if _scroll != null and is_instance_valid(_scroll):
				_fling = _scroll if absf(_vel) >= MIN_FLING else null
				_last_us = Time.get_ticks_usec()
			_scroll = null
			_hit = null
	elif event is InputEventMouseMotion and _press:
		if _scroll == null:
			var d: Vector2 = event.position - _start
			if d.length() < DEADZONE or _hit == null or not is_instance_valid(_hit):
				return
			_axis = 0 if absf(d.x) > absf(d.y) else 1
			_scroll = scroll_for(_hit, _axis)
			if _scroll == null:
				_hit = null  # 이 누름은 스크롤과 무관(카메라 팬 등) — 다시 찾지 않는다
				return
			_scroll.propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)  # 누른 버튼 취소(떼도 안 눌림)
			_vel = 0.0
			_last_us = Time.get_ticks_usec()
		if not is_instance_valid(_scroll) or not _scroll.is_visible_in_tree():
			_scroll = null
			return
		var rel: float = event.relative.x if _axis == 0 else event.relative.y
		_bar(_scroll, _axis).value -= rel
		var now := Time.get_ticks_usec()
		var dt := maxf(float(now - _last_us) / 1e6, 0.001)
		_last_us = now
		_vel = clampf(lerpf(_vel, -rel / dt, 0.5), -MAX_FLING, MAX_FLING)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _fling == null:
		return
	if not is_instance_valid(_fling) or not _fling.is_visible_in_tree():
		_fling = null
		return
	var now := Time.get_ticks_usec()
	var dt := minf(float(now - _last_us) / 1e6, 0.1)  # 실제 초(배속·히트스톱과 무관)
	_last_us = now
	var bar := _bar(_fling, _axis)
	var before := bar.value
	bar.value += _vel * dt
	_vel *= maxf(0.0, 1.0 - FRICTION * dt)
	if absf(_vel) < MIN_FLING or is_equal_approx(bar.value, before):
		_fling = null


static func _bar(sc: ScrollContainer, axis: int) -> ScrollBar:
	return sc.get_h_scroll_bar() if axis == 0 else sc.get_v_scroll_bar()


## c와 그 조상 중 이 방향으로 굴릴 수 있는 가장 가까운 ScrollContainer(없으면 null).
static func scroll_for(c: Node, axis: int) -> ScrollContainer:
	while c != null:
		if c is ScrollContainer and c.is_visible_in_tree():
			var sc := c as ScrollContainer
			var mode := sc.horizontal_scroll_mode if axis == 0 else sc.vertical_scroll_mode
			var bar := _bar(sc, axis)
			if mode != ScrollContainer.SCROLL_MODE_DISABLED and bar.max_value - bar.page > 0.5:
				return sc
		c = c.get_parent()
	return null


## 화면 좌표 p에서 GUI가 입력을 줄 맨 위 컨트롤(높은 CanvasLayer 먼저, 같은 층에선 나중에 그린 것 먼저 — Godot GUI와 같은 순서).
static func find_control_at(root: Node, p: Vector2) -> Control:
	var tops: Array = []  # [층, 순서, 컨트롤]
	_collect(root, tops)
	tops.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] > b[1]))
	for t in tops:
		var hit := _hit_test(t[2], p)
		if hit != null:
			return hit
	return null


static func _collect(root: Node, out: Array) -> void:
	for c in root.find_children("*", "Control", true, false):  # C++ 탐색(3D 월드를 스크립트로 돌지 않는다), 트리 순서
		if c.get_parent() is Control or not (c as Control).is_visible_in_tree():
			continue
		var cl := (c as Control).get_canvas_layer_node()
		out.append([cl.layer if cl != null else 0, out.size(), c])


static func _hit_test(c: Control, p: Vector2) -> Control:
	if not c.is_visible_in_tree():
		return null
	var xf := c.get_global_transform_with_canvas()
	var local := xf.affine_inverse() * p
	var inside := Rect2(Vector2.ZERO, c.size).has_point(local)
	if c.clip_contents and not inside:
		return null
	for i in range(c.get_child_count() - 1, -1, -1):
		var ch := c.get_child(i)
		if ch is Control:
			var r := _hit_test(ch, p)
			if r != null:
				return r
	if inside and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return c
	return null

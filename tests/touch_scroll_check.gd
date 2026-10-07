extends Node
## 손가락 끌기 스크롤 체크(2026-10-07, scripts/touch_scroll.gd): 버튼으로 채운 목록 위에서 끌면 목록이 굴러가고 누른 버튼은 안 눌리는지,
## 짧게 탭하면 버튼이 눌리는지, 위 창(더 높은 층)이 덮고 있으면 뒤 목록은 안 굴러가는지, 실제 상점 창에서도 굴러가는지 본다.
## 터치는 emulate_mouse_from_touch로 왼쪽 마우스 이벤트가 되므로 마우스 이벤트를 밀어 넣는다.
## 실행: godot --headless --path . res://tests/touch_scroll_check.tscn

var _fails := 0
var _presses := 0


func _ready() -> void:
	Economy.save_path = ""
	get_window().size = Vector2i(360, 640)  # 논리 화면 720×1280(폰과 같게)
	await _frames(2)
	await _synthetic()
	await _real_panels()
	if _fails > 0:
		print("TOUCH SCROLL FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("TOUCH SCROLL ALL PASSED")
		get_tree().quit(0)


func _list(layer: int) -> ScrollContainer:
	var cl := CanvasLayer.new()
	cl.layer = layer
	add_child(cl)
	var sc := ScrollContainer.new()
	sc.position = Vector2(100, 200)
	sc.size = Vector2(400, 500)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cl.add_child(sc)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(box)
	for i in 20:
		var b := Button.new()
		b.text = "item %d" % i
		b.custom_minimum_size = Vector2(0, 90)
		b.pressed.connect(func(): _presses += 1)
		box.add_child(b)
	return sc


func _synthetic() -> void:
	var sc := _list(2)
	await _frames(3)
	var bar := sc.get_v_scroll_bar()
	_check(bar.max_value - bar.page > 100, "list is taller than its box", str(bar.max_value))
	await _drag(Vector2(300, 600), Vector2(0, -300))
	await _frames(2)
	_check(bar.value > 250, "dragging over buttons scrolls the list", str(bar.value))
	_check(_presses == 0, "the button under the finger is not pressed after a drag", str(_presses))
	var v := bar.value
	await _frames(20)
	_check(bar.value > v, "fling keeps it sliding a little after release", "%s -> %s" % [v, bar.value])
	await _tap(Vector2(300, 400))
	_check(_presses == 1, "a short tap still presses the button", str(_presses))
	_check(absf(bar.value - bar.value) < 0.1, "tap stops the fling", "")
	v = bar.value
	await _drag(Vector2(300, 300), Vector2(0, 250))
	_check(bar.value < v - 150, "dragging down scrolls back up", "%s -> %s" % [v, bar.value])
	await _tap(Vector2(300, 400))
	_check(_presses == 2, "next tap after a drag works (no stuck press)", str(_presses))
	# 더 높은 층의 창(전체 화면 배경)이 덮고 있으면 뒤 목록은 그대로
	var top := CanvasLayer.new()
	top.layer = 5
	add_child(top)
	var back := ColorRect.new()
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	top.add_child(back)
	await _frames(2)
	var before := bar.value
	await _drag(Vector2(300, 600), Vector2(0, -300))
	_check(is_equal_approx(bar.value, before), "a window on top blocks scrolling the list behind it", "%s -> %s" % [before, bar.value])
	top.queue_free()
	sc.get_parent().queue_free()
	await _frames(2)


func _real_panels() -> void:
	PreloaderScript.done = true
	var main = preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(8)
	for path in ["res://scripts/shop_panel.gd", "res://scripts/mission_panel.gd"]:
		var p := _find(main, path)
		if p == null:
			_check(false, "found " + path, "")
			continue
		p.open()
		await get_tree().create_timer(0.6).timeout  # 창을 연 직후 누름 막기(OPEN_GUARD_MS) 지나서
		var sc := _visible_scroll(p)
		if sc == null:
			_check(false, path.get_file() + ": has a visible scroll list", "")
			continue
		var bar := sc.get_v_scroll_bar()
		var r := sc.get_global_rect()
		var before := bar.value
		await _drag(r.get_center() + Vector2(0, r.size.y * 0.3), Vector2(0, -r.size.y * 0.5))
		await _frames(2)
		var can := bar.max_value - bar.page > 1.0
		_check(not can or bar.value > minf(before + 20, bar.max_value - bar.page - 1.0), path.get_file() + ": drag scrolls (can=%s)" % can, "%s -> %s / max %s page %s" % [before, bar.value, bar.max_value, bar.page])
		if p.has_method("close"):
			p.close()
		await _frames(5)
	main.queue_free()


const PreloaderScript := preload("res://scripts/preloader.gd")


func _visible_scroll(n: Node) -> ScrollContainer:
	for c in n.find_children("*", "ScrollContainer", true, false):
		if (c as ScrollContainer).is_visible_in_tree() and (c as ScrollContainer).vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			return c
	return null


func _find(main: Node, path: String) -> Node:
	for c in main.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
	return null


## 폰과 같은 길: 손가락(ScreenTouch/ScreenDrag)을 창 좌표로 넣으면 엔진이 왼쪽 마우스 이벤트로 바꿔 준다(input_check와 같은 방식).
func _drag(from: Vector2, by: Vector2) -> void:
	_touch(from, true)
	await _frames(1)
	var steps := 10
	var xf := get_viewport().get_final_transform()
	for i in steps:
		var ev := InputEventScreenDrag.new()
		ev.index = 0
		ev.position = xf * (from + by * float(i + 1) / steps)
		ev.relative = xf.basis_xform(by / steps)
		Input.parse_input_event(ev)
		await _frames(1)
	_touch(from + by, false)
	await _frames(1)


func _tap(at: Vector2) -> void:
	_touch(at, true)
	await _frames(1)
	_touch(at, false)
	await _frames(2)


func _touch(at: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = down
	ev.position = get_viewport().get_final_transform() * at
	Input.parse_input_event(ev)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(ok: bool, what: String, detail: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		_fails += 1
		print("  FAIL ", what, "  ", detail)

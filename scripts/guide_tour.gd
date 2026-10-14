extends CanvasLayer
## 가이드 포커스 설명(사용자 2026-10-13 "둘러보기할 때 화면의 어떤게 어떤역할인지 포커스를 주면서 설명"): 화면을 어둡게 하고 설명할 곳만 밝게 뚫어
## 호박색 테두리를 두르고, 그 옆 말풍선에 설명 한 줄. 화면 어디든 누르면 다음, 오른쪽 위 [건너뛰기]. Tutorial이 띄운다(TOURS).
## 단계 = {at: 가리킬 곳(없으면 가운데 말풍선만), title?, text}. 가리킬 곳(resolve):
##   "ui:<key>" — Tutorial.register_ui로 등록한 버튼 · "<스크립트 이름>:<경로>" — 그 스크립트(res://scripts/<이름>.gd)가 붙은 노드의 변수
##   (점으로 이어서 사전 키·배열 번호, 배열이면 보이는 것 전부를 감싼다) · "war3d:gate:<면>|keep|mine|def:<면>" — 공성 전장의 3D 위치(카메라로 화면에 옮김).
## 못 찾거나 안 보이는 단계는 건너뛴다. pause면 그동안 게임 트리를 멈춘다(공성전 체험 — 이 층만 돈다).

const Lang := preload("res://scripts/lang.gd")

const UiKit := preload("res://scripts/ui_kit.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const DIM := Color(0, 0, 0, 0.62)
const PAD := 8.0
const BUBBLE_W := 600.0
const PULSE_HZ := 1.4
const WORLD_BOX := Vector2(150, 120)  # 3D 한 점을 감쌀 화면 크기
const GUARD_MS := 350  # 단계가 바뀐 직후 연타를 버린다

signal finished(id: String)

var id := ""
var steps: Array = []
var pause := false
var index := -1

var _dim: Control
var _bubble: PanelContainer
var _title: Label
var _text: Label
var _foot: Label
var _skip: Button
var _hole := Rect2()
var _has_hole := false
var _t := 0.0
var _shown_ms := 0
var _was_paused := false


func _ready() -> void:
	layer = 50  # 창(2)·탭(3)·알림 위
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dim = Control.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.draw.connect(_draw_dim)
	_dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			next()
		elif e is InputEventScreenTouch and e.pressed:
			next())
	add_child(_dim)
	_bubble = PanelContainer.new()
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM, 12.0, 16))
	add_child(_bubble)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	_bubble.add_child(box)
	_title = _label(24, UiKit.AMBER.darkened(0.4))
	box.add_child(_title)
	_text = _label(22, UiKit.INK)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(BUBBLE_W - 40.0, 0)
	box.add_child(_text)
	_foot = _label(17, Color(UiKit.INK, 0.6))
	_foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_foot)
	_skip = Button.new()
	_skip.text = Lang.t("guide_tour.ready")
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.add_theme_font_override("font", FONT)
	_skip.add_theme_font_size_override("font_size", 20)
	_skip.custom_minimum_size = Vector2(132, 52)
	_skip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_skip.offset_left = -148
	_skip.offset_right = -16
	_skip.offset_top = 16
	_skip.offset_bottom = 68
	UiKit.apply_button(_skip, Color(0.30, 0.34, 0.46), 10.0)
	_skip.pressed.connect(finish)
	add_child(_skip)
	if pause:
		_was_paused = get_tree().paused
		get_tree().paused = true
	next()


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 다음 단계(가리킬 곳을 못 찾는 단계는 건너뛴다). 끝이면 닫는다.
func next() -> void:
	if index >= 0 and Time.get_ticks_msec() - _shown_ms < GUARD_MS:
		return
	while true:
		index += 1
		if index >= steps.size():
			finish()
			return
		var st: Dictionary = steps[index]
		var at := str(st.get("at", ""))
		if at == "":
			_has_hole = false
			break
		var r = resolve(at, get_tree())
		if r is Rect2:
			_hole = r.grow(PAD)
			_has_hole = true
			break
	_shown_ms = Time.get_ticks_msec()
	var st: Dictionary = steps[index]
	_title.text = str(st.get("title", ""))
	_title.visible = _title.text != ""
	_text.text = str(st.text)
	_foot.text = Lang.t("guide_tour.next") % [index + 1, steps.size()] if index + 1 < steps.size() else Lang.t("guide_tour.next_2") % [index + 1, steps.size()]
	_place_bubble()
	_dim.queue_redraw()


func finish() -> void:
	if is_queued_for_deletion():
		return
	if pause:
		get_tree().paused = _was_paused
		pause = false
	finished.emit(id)
	queue_free()


## finish 없이 사라져도(장면 전환 등) 멈춘 게임을 되돌린다.
func _exit_tree() -> void:
	if pause and is_inside_tree():
		get_tree().paused = _was_paused
		pause = false


func _place_bubble() -> void:
	var vp := get_viewport().get_visible_rect().size
	_bubble.reset_size()
	var w := minf(BUBBLE_W, vp.x - 32.0)
	_bubble.custom_minimum_size = Vector2(w, 0)
	_bubble.size = Vector2(w, 0)
	_bubble.reset_size()
	var h := _bubble.get_combined_minimum_size().y
	var x := (vp.x - w) / 2.0
	var y := (vp.y - h) / 2.0
	if _has_hole:
		x = clampf(_hole.get_center().x - w / 2.0, 16.0, vp.x - w - 16.0)
		if _hole.get_center().y < vp.y * 0.5:
			y = minf(_hole.end.y + 18.0, vp.y - h - 16.0)
		else:
			y = maxf(_hole.position.y - h - 18.0, 84.0)
		if Rect2(x, y, w, h).intersects(_hole):  # 큰 구멍(창 전체 등): 화면 위·아래 끝 중 덜 가리는 쪽
			y = 84.0 if _hole.get_center().y > vp.y * 0.5 else vp.y - h - 16.0
	_bubble.position = Vector2(x, y)


func _process(delta: float) -> void:
	_t += delta
	if index >= 0 and index < steps.size() and _has_hole:
		var r = resolve(str(steps[index].get("at", "")), get_tree())  # 움직이는 대상(3D·스크롤)을 따라간다
		if r is Rect2:
			_hole = r.grow(PAD)
	_dim.queue_redraw()


func _draw_dim() -> void:
	var vp := _dim.size
	if not _has_hole:
		_dim.draw_rect(Rect2(Vector2.ZERO, vp), DIM)
		return
	var h := _hole.intersection(Rect2(Vector2.ZERO, vp))
	_dim.draw_rect(Rect2(0, 0, vp.x, h.position.y), DIM)
	_dim.draw_rect(Rect2(0, h.end.y, vp.x, vp.y - h.end.y), DIM)
	_dim.draw_rect(Rect2(0, h.position.y, h.position.x, h.size.y), DIM)
	_dim.draw_rect(Rect2(h.end.x, h.position.y, vp.x - h.end.x, h.size.y), DIM)
	var pulse := 0.5 + 0.5 * sin(_t * TAU * PULSE_HZ)
	_dim.draw_rect(h, Color(UiKit.AMBER, 0.7 + 0.3 * pulse), false, 4.0 + 2.0 * pulse)


# --- 가리킬 곳 ---

## at → 화면 Rect2(못 찾거나 안 보이면 null).
static func resolve(at: String, tree: SceneTree):
	if at.begins_with("ui:"):
		var tut = tree.root.get_node_or_null("Tutorial")
		var t = tut.ui_targets.get(at.substr(3)) if tut != null else null
		return _rect_of(t.node if t != null else null)
	if at.begins_with("war3d:"):
		return _world_rect(at.substr(6), tree)
	var obj = _walk(at, tree)
	return _rect_of(obj) if obj != null else null


## "<스크립트>:<경로>"가 가리키는 보이는 Control(가이드 카드 화살표용). 없으면 null.
static func resolve_node(at: String, tree: SceneTree):
	var obj = _walk(at, tree)
	if not (obj is Control) or not is_instance_valid(obj) or not obj.is_visible_in_tree() or obj.is_queued_for_deletion():
		return null
	return obj if obj.size.x >= 2.0 and obj.size.y >= 2.0 else null  # 막 만들어 아직 자리를 안 잡은 버튼은 건너뛴다(화살표가 튀지 않게)


static func _walk(at: String, tree: SceneTree):
	var owner_name := at.get_slice(":", 0)
	var path := at.substr(owner_name.length() + 1)
	var obj = find_script_node(tree.root, "res://scripts/%s.gd" % owner_name)
	if obj == null:
		return null
	for seg in path.split(".", false):
		if obj is Dictionary:
			obj = obj.get(seg)
		elif obj is Array:
			obj = obj[int(seg)] if seg.is_valid_int() and int(seg) < obj.size() else null
		elif obj is Object and is_instance_valid(obj):
			obj = obj.get(seg)
		else:
			obj = null
		if obj == null:
			return null
	return obj


## 보이는 Control(또는 그 배열·사전 값들)을 감싸는 화면 Rect2. 없으면 null.
static func _rect_of(v):
	var out = null
	var list: Array = v if v is Array else (v.values() if v is Dictionary else [v])
	for c in list:
		if c is Dictionary:
			c = c.get("button", c.get("card", c.get("cell", c.get("box"))))
		if not (c is Control) or not is_instance_valid(c) or not c.is_visible_in_tree() or c.is_queued_for_deletion():
			continue
		var xf: Transform2D = c.get_global_transform_with_canvas()
		var r := Rect2(xf.origin, c.size * xf.get_scale())
		if r.size.x < 2.0 or r.size.y < 2.0:
			continue
		out = r if out == null else out.merge(r)
	if out != null:
		var vp: Rect2 = list[0].get_viewport().get_visible_rect() if list[0] is Node else Rect2(0, 0, 1e6, 1e6)
		if not out.intersects(vp):
			return null
	return out


static func find_script_node(n: Node, path: String) -> Node:
	var s = n.get_script()
	if s != null and s.resource_path == path:
		return n
	for c in n.get_children():
		var r := find_script_node(c, path)
		if r != null:
			return r
	return null


## 공성 전장(war_battle.gd)의 3D 위치 → 화면: gate:<면> 성문 · keep 성채 · mine 내 영웅들 · def:<면> 그 면 수비 영웅들.
static func _world_rect(what: String, tree: SceneTree):
	var b = find_script_node(tree.root, "res://scripts/war_battle.gd")
	if b == null or b.camera == null:
		return null
	var pts: Array = []
	var kind := what.get_slice(":", 0)
	var side := int(what.get_slice(":", 1)) if what.contains(":") else 0
	match kind:
		"gate":
			var g = b.gate(side)
			if g != null:
				pts.append(g.global_position)
		"keep":
			if b.keep != null:
				pts.append(b.keep.global_position)
		"mine":
			for u in b.my_units():
				if is_instance_valid(u) and u.is_alive():
					pts.append(u.global_position)
		"def":
			for u in b.units(1):
				if is_instance_valid(u) and u.is_alive() and int(u.lane) == side:
					pts.append(u.global_position)
	var out = null
	for p in pts:
		if b.camera.is_position_behind(p):
			continue
		var s: Vector2 = b.camera.unproject_position(p)
		var r := Rect2(s - WORLD_BOX / 2.0, WORLD_BOX)
		out = r if out == null else out.merge(r)
	return out

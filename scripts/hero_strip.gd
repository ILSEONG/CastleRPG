extends CanvasLayer
## 성 전투 하단 영웅 초상화 줄(사용자 2026-10-06: 스테이지를 미는 동안 메뉴 UI를 숨기고 아래에 영웅 초상화, 누르면 그 영웅 선택).
## main이 스테이지 진행 중(스테이지·결과·카운트다운)에만 보이게 한다. 칸 = 등급 색 8각 바탕 + 피규어 + HP 막대, 쓰러지면 흐리게,
## 선택된 영웅은 금색 테두리. 초상화를 누르면 picker로 그 영웅을 고른다(다시 누르면 해제) — 그다음 성문·성벽·바닥 탭은 평소처럼 이동.
## 영웅 목록은 heroes_fn(지금 영웅 노드 배열, 배치 순서)을 매 프레임 읽어 바뀌면(리필 때 다시 만든 영웅) 칸을 다시 만든다.

const UiKit := preload("res://scripts/ui_kit.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")

const FACE_MAX := 84.0
const GAP := 8.0
const SIDE := 16.0
const BOTTOM := 10.0
const HP_GREEN := Color(0.35, 0.8, 0.4)
const SELECT_GOLD := Color(1.0, 0.78, 0.2)

var heroes_fn: Callable  # () -> Array(영웅 노드)
var picker  # unit_picker.gd
var row: HBoxContainer
var cells: Array = []  # [{hero, face: Button, bar, cell}]
var _ids: Array = []


func _ready() -> void:
	layer = 1  # HUD와 같은 층(창은 2 이상이 덮는다)
	row = HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_bottom = -BOTTOM
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(GAP))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)


func _process(_delta: float) -> void:
	if not visible or not heroes_fn.is_valid():
		return
	var hs: Array = heroes_fn.call()
	var ids := hs.map(func(h): return h.get_instance_id())
	if ids != _ids:
		_rebuild(hs, ids)
	for c in cells:
		var h = c.hero
		if not is_instance_valid(h):
			continue
		c.bar.value = h.hp_ratio() * 100.0
		c.cell.modulate.a = 1.0 if h.is_alive() else 0.45
		c.face.queue_redraw()  # 선택 테두리


func _rebuild(hs: Array, ids: Array) -> void:
	_ids = ids
	cells.clear()
	for c in row.get_children():
		row.remove_child(c)
		c.queue_free()
	var vw := 720.0
	if is_inside_tree():
		vw = get_viewport().get_visible_rect().size.x
	var px := minf(FACE_MAX, floorf((vw - SIDE * 2.0 - GAP * maxf(0.0, hs.size() - 1.0)) / maxf(1.0, hs.size())))
	for h in hs:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var face := Button.new()
		face.flat = true
		face.focus_mode = Control.FOCUS_NONE
		face.custom_minimum_size = Vector2(px, px)
		face.draw.connect(_draw_face.bind(face, h))
		face.pressed.connect(pick.bind(h))
		if PortraitsScript.current != null:
			PortraitsScript.current.portrait_ready.connect(face.queue_redraw.unbind(1))
		cell.add_child(face)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(px, 12)
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiKit.apply_bar(bar, HP_GREEN)
		cell.add_child(bar)
		row.add_child(cell)
		cells.append({"hero": h, "face": face, "bar": bar, "cell": cell})


## 초상화 누름: 산 영웅이면 선택(이미 선택돼 있으면 해제). 쓰러진 영웅은 무시.
func pick(h) -> void:
	if picker == null or not is_instance_valid(h) or not h.is_alive():
		return
	picker._select(null if picker.selected == h else h)


func _draw_face(c: Control, h) -> void:
	if not is_instance_valid(h):
		return
	var r := Rect2(Vector2.ZERO, c.size)
	var oct := LowpolyBox.octagon(r.grow(-2.0), r.size.x * 0.2)
	c.draw_colored_polygon(oct, UiKit.GRADE_COLORS.get(h.def.grade, UiKit.STEEL).lightened(0.3))
	c.draw_texture_rect(PortraitsScript.portrait("hero:" + h.def.id), r, false)
	oct.append(oct[0])
	var on: bool = picker != null and picker.selected == h
	c.draw_polyline(oct, SELECT_GOLD if on else UiKit.OUTLINE, 5.0 if on else 2.0, true)

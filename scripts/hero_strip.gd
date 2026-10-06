extends CanvasLayer
## 성 전투 하단 영웅 초상화 줄(사용자 2026-10-06: 스테이지를 미는 동안 메뉴 UI를 숨기고 아래에 영웅 초상화, 누르면 그 영웅 선택).
## main이 스테이지 진행 중(스테이지·결과·카운트다운)에만 보이게 한다. 칸 = 등급 색 8각 바탕 + 피규어 + HP 막대, 쓰러지면 흐리게,
## 선택된 영웅은 금색 테두리. 초상화를 누르면 picker로 그 영웅을 고른다(다시 누르면 해제) — 그다음 성문·성벽·바닥 탭은 평소처럼 이동.
## 영웅 목록은 heroes_fn(지금 영웅 노드 배열, 배치 순서)을 매 프레임 읽어 바뀌면(리필 때 다시 만든 영웅) 칸을 다시 만든다.

const UiKit := preload("res://scripts/ui_kit.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")

const FACE_MAX := 84.0
const GAP := 18.0  # 영웅 칸 사이(쿨 칸이 어느 영웅 것인지 갈리게 넉넉히)
const SIDE := 16.0
const BOTTOM := 10.0
const HP_GREEN := Color(0.35, 0.8, 0.4)
const SELECT_GOLD := Color(1.0, 0.78, 0.2)
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")
const SLOT_FRAC := 0.32  # 쿨 칸 지름 / 초상화 폭
const SLOT_GAP := 0.0
const READY_SEC := 0.5  # 남은 쿨이 이만큼 이하면 준비됨(조건을 기다리는 발동형은 0.5초마다 다시 본다)
const SLOT_READY := Color(1.0, 0.8, 0.28)
const SLOT_FILL := Color(0.55, 0.78, 1.0)
const SLOT_DARK := Color(0.12, 0.14, 0.2, 0.82)
const SLOT_EMPTY := Color(0.12, 0.14, 0.2, 0.28)

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
	var px := fit_px(hs.size(), FACE_MAX, vw - SIDE * 2.0, GAP)
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
		cell.add_child(face_with_slots(face, h, px))
		var bar := ProgressBar.new()
		bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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


## 초상화 양옆 쿨 칸(".O." — 사용자 2026-10-06): [왼쪽 칸][초상화][오른쪽 칸], 칸은 초상화 바깥 아래쪽(초상화를 가리지 않는다).
## 왼쪽 = 첫 액티브, 오른쪽 = 둘째 액티브(칸 순서, hero.active_slots). 준비됨 = 금색 원, 쿨 도는 중 = 어두운 원에 시계 방향으로
## 차오르는 하늘색 + 남은 초, 승급으로 아직 잠김 = 자물쇠, 액티브가 하나뿐(R) = 오른쪽은 흐린 빈 원(자리는 그대로).
## 성·던전·길드전 초상화가 함께 쓴다. 칸은 초상화가 다시 그려질 때(매 프레임) 같이 다시 그린다.
static func face_with_slots(face: Control, h, px: float) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", int(SLOT_GAP))
	var d := slot_px(px)
	var wr: WeakRef = weakref(h)  # 영웅이 먼저 사라져도(리필 때 다시 만든 영웅) 칸이 잡고 있지 않게
	for i in 2:
		var s := Control.new()
		s.custom_minimum_size = Vector2(d, px)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.draw.connect(func(): _draw_slot_at(s, wr.get_ref(), i))
		face.draw.connect(s.queue_redraw)
		box.add_child(s)
	box.add_child(face)
	box.move_child(face, 1)
	return box


static func slot_px(px: float) -> float:
	return roundf(px * SLOT_FRAC)


## n칸이 폭 width(간격 gap)에 들어가는 초상화 크기(최대 max_px). 칸 폭 = 초상화 + 쿨 칸 둘.
static func fit_px(n: int, max_px: float, width: float, gap: float) -> float:
	var k := maxf(1.0, float(n))
	return minf(max_px, floorf(((width - gap * (k - 1.0)) / k - SLOT_GAP * 2.0) / (1.0 + SLOT_FRAC * 2.0)))


static func _draw_slot_at(s: Control, h, i: int) -> void:
	if h == null or not is_instance_valid(h) or not h.has_method("active_slots"):
		return
	var slots: Array = h.active_slots()
	var r := s.size.x / 2.0
	_draw_slot(s, Vector2(r, s.size.y - r - 1.0), r - 1.0, slots[i] if slots.size() > i else {})


static func _draw_slot(c: Control, at: Vector2, r: float, s: Dictionary) -> void:
	if s.is_empty():
		c.draw_circle(at, r, SLOT_EMPTY)
		c.draw_arc(at, r, 0.0, TAU, 24, Color(UiKit.OUTLINE, 0.45), 1.5, true)
		return
	if s.locked:
		c.draw_circle(at, r, SLOT_DARK)
		var w := r * 0.8
		c.draw_arc(at + Vector2(0, -r * 0.12), w * 0.36, PI, TAU, 10, Color(1, 1, 1, 0.75), maxf(2.0, r * 0.13), true)
		c.draw_rect(Rect2(at + Vector2(-w * 0.5, -r * 0.12), Vector2(w, w * 0.72)), Color(1, 1, 1, 0.75))
	elif float(s.left) <= READY_SEC:
		c.draw_circle(at, r, SLOT_READY)
		c.draw_circle(at, r * 0.45, Color(1, 1, 1, 0.55))
	else:
		c.draw_circle(at, r, SLOT_DARK)
		var done := clampf(1.0 - float(s.left) / maxf(0.01, float(s.total)), 0.0, 1.0)
		if done > 0.0:
			var pts := PackedVector2Array([at])
			var n := maxi(2, ceili(24.0 * done))
			for i in n + 1:
				var a := -PI / 2.0 + TAU * done * float(i) / float(n)
				pts.append(at + Vector2(cos(a), sin(a)) * r)
			c.draw_colored_polygon(pts, Color(SLOT_FILL, 0.6))
		var fs := int(r * 1.05)
		var txt := str(ceili(float(s.left)))
		var p := at + Vector2(-r, fs * 0.36)
		c.draw_string_outline(FONT, p, txt, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, 4, Color(0, 0, 0, 0.85))
		c.draw_string(FONT, p, txt, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color.WHITE)
	c.draw_arc(at, r, 0.0, TAU, 24, UiKit.OUTLINE, 1.5, true)

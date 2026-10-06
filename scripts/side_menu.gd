extends CanvasLayer
## 오른쪽 아래 메뉴(2026-10-06): 토글 버튼 하나, 누르면 위로 [미션][랭킹][친구][이벤트] 버튼이 펼쳐진다(다시 누르거나 항목을 고르면 접힌다).
## 자리: 오른쪽 아래, 탭 바 위. 튜토리얼 미션 카드가 보이면 카드 위로 올라간다(겹치지 않게, 매 프레임 맞춘다).
## main.gd가 만들고 windows = {mission, ranking, friend, event}(ui_window 창)를 넣는다. 친구 창은 던전 시트가 만든 것(friend_panel.gd)을 그대로 연다.

const UiKit := preload("res://scripts/ui_kit.gd")
const HudScript := preload("res://scripts/hud.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const ITEMS := [["mission", "미션"], ["ranking", "랭킹"], ["friend", "친구"], ["event", "이벤트"]]
const SIZE := Vector2(84, 84)
const SIDE := 16.0
const GAP := 10.0
const ABOVE := 12.0  # 탭 바·미션 카드 위 여백
const BASE := Color(0.30, 0.34, 0.46)
const GOLD := Color(0.98, 0.76, 0.18)
const OPEN_SEC := 0.14

var windows := {}  # 항목 id → 창(open()/is_open())
var card  # tutorial_card.gd(있으면 그 위로 올린다)
var toggle: Button
var buttons := {}  # 항목 id → Button(테스트용)
var is_open := false

var _col: VBoxContainer
var _dots := {}  # 빨간 점을 그린 버튼 id → true
var _t := 0.0  # 펼침 정도 0..1


func _ready() -> void:
	layer = 1
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", int(GAP))
	_col.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_col)
	for it in ITEMS:
		var b := _make_button(it[0], it[1])
		b.pressed.connect(func(): _pick(it[0]))
		buttons[it[0]] = b
		_col.add_child(b)
	toggle = _make_button("toggle", "메뉴")
	toggle.pressed.connect(func(): set_open(not is_open))
	_col.add_child(toggle)
	set_open(false)


## 출석 이벤트 보상을 오늘 받을 수 있다(서버 /v1/player의 attendance).
func has_dot() -> bool:
	return bool(Economy.attendance.get("can_claim", false))


## 빨간 점을 그릴 버튼: [이벤트](출석 보상)·[미션](받을 미션 보상), 둘 중 하나라도 있으면 [메뉴].
func dots() -> Dictionary:
	var d := {}
	if has_dot():
		d.event = true
	if Missions.ready_count() > 0:
		d.mission = true
	if not d.is_empty():
		d.toggle = true
	return d


func set_open(on: bool) -> void:
	is_open = on
	for id in buttons:
		buttons[id].visible = on
	if on:
		_t = 0.0
	toggle.get_child(0).queue_redraw()


func _pick(id: String) -> void:
	set_open(false)
	var w = windows.get(id)
	if w != null and not w.is_open():
		w.open()


func _process(delta: float) -> void:
	var d := dots()
	if d != _dots:  # 받을 보상(출석·미션)이 있으면 그 버튼과 [메뉴]에 빨간 점
		_dots = d
		toggle.get_child(0).queue_redraw()
		for id in buttons:
			buttons[id].get_child(0).queue_redraw()
	var bottom := float(HudScript.TAB_BAR_H) + ABOVE
	if card != null and card.panel != null and card.panel.visible:
		var vh := get_viewport().get_visible_rect().size.y
		bottom = maxf(bottom, vh - card.panel.global_position.y + ABOVE)
	_col.offset_right = -SIDE
	_col.offset_left = -SIDE - SIZE.x
	_col.offset_bottom = -bottom
	_col.offset_top = -bottom - _col.get_combined_minimum_size().y
	if is_open and _t < 1.0:  # 펼칠 때 아래에서 살짝 올라오며 나타난다
		_t = minf(1.0, _t + delta / OPEN_SEC)
		for i in ITEMS.size():
			var b: Button = buttons[ITEMS[i][0]]
			b.modulate.a = _t
			b.get_child(0).position.y = (1.0 - _t) * 18.0 * (ITEMS.size() - i)


func _make_button(id: String, text: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = SIZE
	UiKit.apply_button(b, UiKit.AMBER if id == "toggle" else BASE, 12.0)
	var face := Control.new()
	face.size = SIZE
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.draw.connect(func(): _draw_face(face, id, text))
	b.add_child(face)
	return b


func _draw_face(c: Control, id: String, text: String) -> void:
	var ctr := Vector2(SIZE.x / 2.0, 34)
	match id:
		"ranking":
			draw_trophy(c, ctr, 44.0)
		"friend":
			draw_friends(c, ctr, 44.0)
		"event":
			draw_gift(c, ctr, 44.0)
		"mission":
			draw_scroll(c, ctr, 44.0)
		_:
			draw_chevron(c, ctr, 30.0, is_open)
			text = "닫기" if is_open else "메뉴"
	if _dots.has(id):
		var dp := Vector2(SIZE.x - 12, 12)
		c.draw_circle(dp, 9.0, Color(0.88, 0.22, 0.2))
		c.draw_arc(dp, 9.0, 0, TAU, 16, Color(0.88, 0.22, 0.2).darkened(0.3), 1.5, true)
	var y := SIZE.y - 10.0
	c.draw_string_outline(FONT, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 20, 5, Color(UiKit.INK, 0.85))
	c.draw_string(FONT, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 20, Color.WHITE)


## 위(펼치기)·아래(접기) 꺾쇠 두 겹.
static func draw_chevron(ci: CanvasItem, ctr: Vector2, s: float, down: bool) -> void:
	var k := 1.0 if down else -1.0  # 꼭짓점 방향(아래 = +)
	for dy: float in [-s * 0.22, s * 0.22]:
		var y: float = ctr.y + dy
		ci.draw_polyline(PackedVector2Array([Vector2(ctr.x - s * 0.45, y - k * s * 0.18), Vector2(ctr.x, y + k * s * 0.18),
			Vector2(ctr.x + s * 0.45, y - k * s * 0.18)]), Color.WHITE, 5.0, true)


## 각진 트로피(컵 + 손잡이 + 받침 + 별). ctr = 컵 가운데, s = 전체 높이.
static func draw_trophy(ci: CanvasItem, ctr: Vector2, s: float) -> void:
	var u := s / 44.0
	var p := func(x: float, y: float) -> Vector2: return ctr + Vector2(x, y) * u
	var dark := GOLD.darkened(0.25)
	ci.draw_polyline(PackedVector2Array([p.call(-11, -14), p.call(-19, -14), p.call(-19, -6), p.call(-10, 0)]), dark, 3.5 * u)
	ci.draw_polyline(PackedVector2Array([p.call(11, -14), p.call(19, -14), p.call(19, -6), p.call(10, 0)]), dark, 3.5 * u)
	ci.draw_colored_polygon(PackedVector2Array([p.call(-13, -18), p.call(0, -18), p.call(0, 6), p.call(-8, 2)]), GOLD.lightened(0.15))
	ci.draw_colored_polygon(PackedVector2Array([p.call(0, -18), p.call(13, -18), p.call(8, 2), p.call(0, 6)]), GOLD)
	ci.draw_colored_polygon(PackedVector2Array([p.call(-3, 6), p.call(3, 6), p.call(4, 12), p.call(-4, 12)]), dark)
	ci.draw_colored_polygon(PackedVector2Array([p.call(-11, 12), p.call(11, 12), p.call(12, 18), p.call(-12, 18)]), GOLD.darkened(0.1))
	var rim := PackedVector2Array([p.call(-13, -18), p.call(13, -18), p.call(8, 2), p.call(0, 6), p.call(-8, 2), p.call(-13, -18)])
	ci.draw_polyline(rim, LowpolyBox.edge_color(GOLD), 1.5 * u, true)
	var star := PackedVector2Array()
	for k in 10:
		var r := (5.5 if k % 2 == 0 else 2.4) * u
		var a := -PI / 2.0 + k * PI / 5.0
		star.append(p.call(0, -8) + Vector2(cos(a), sin(a)) * r)
	ci.draw_colored_polygon(star, Color(1, 1, 1, 0.9))


## 두 사람(뒤 사람 + 앞 사람): 각진 머리 + 어깨.
static func draw_friends(ci: CanvasItem, ctr: Vector2, s: float) -> void:
	var u := s / 44.0
	for f in [[Vector2(8, -3), Color(0.55, 0.78, 0.95)], [Vector2(-6, 1), Color(0.98, 0.84, 0.60)]]:
		var o: Vector2 = ctr + f[0] * u
		var col: Color = f[1]
		var head := PackedVector2Array()
		for k in 6:
			var a := k * TAU / 6.0 + PI / 6.0
			head.append(o + Vector2(0, -9) * u + Vector2(cos(a), sin(a)) * 7.0 * u)
		var body := PackedVector2Array([o + Vector2(-12, 16) * u, o + Vector2(-9, 3) * u, o + Vector2(9, 3) * u, o + Vector2(12, 16) * u])
		ci.draw_colored_polygon(body, col.darkened(0.15))
		ci.draw_colored_polygon(head, col)
		var rim := head.duplicate()
		rim.append(rim[0])
		ci.draw_polyline(rim, LowpolyBox.edge_color(col), 1.5 * u, true)


## 선물 상자(뚜껑 + 리본).
static func draw_gift(ci: CanvasItem, ctr: Vector2, s: float) -> void:
	var u := s / 44.0
	var box := Color(0.86, 0.30, 0.34)
	var p := func(x: float, y: float) -> Vector2: return ctr + Vector2(x, y) * u
	ci.draw_colored_polygon(PackedVector2Array([p.call(-14, -4), p.call(0, -4), p.call(0, 17), p.call(-14, 17)]), box.lightened(0.1))
	ci.draw_colored_polygon(PackedVector2Array([p.call(0, -4), p.call(14, -4), p.call(14, 17), p.call(0, 17)]), box)
	ci.draw_colored_polygon(PackedVector2Array([p.call(-17, -11), p.call(17, -11), p.call(17, -3), p.call(-17, -3)]), box.lightened(0.2))
	ci.draw_colored_polygon(PackedVector2Array([p.call(-3, -11), p.call(3, -11), p.call(3, 17), p.call(-3, 17)]), GOLD)
	ci.draw_colored_polygon(PackedVector2Array([p.call(-2, -11), p.call(-13, -20), p.call(-9, -11)]), GOLD)
	ci.draw_colored_polygon(PackedVector2Array([p.call(2, -11), p.call(13, -20), p.call(9, -11)]), GOLD.darkened(0.1))
	ci.draw_polyline(PackedVector2Array([p.call(-17, -11), p.call(17, -11), p.call(17, -3), p.call(14, -3), p.call(14, 17), p.call(-14, 17),
		p.call(-14, -3), p.call(-17, -3), p.call(-17, -11)]), LowpolyBox.edge_color(box), 1.5 * u, true)


## 미션 두루마리(종이 + 체크 두 줄).
static func draw_scroll(ci: CanvasItem, ctr: Vector2, s: float) -> void:
	var u := s / 44.0
	var p := func(x: float, y: float) -> Vector2: return ctr + Vector2(x, y) * u
	var paper := Color(0.96, 0.90, 0.74)
	var roll := Color(0.80, 0.62, 0.38)
	ci.draw_colored_polygon(PackedVector2Array([p.call(-13, -15), p.call(13, -15), p.call(13, 15), p.call(-13, 15)]), paper)
	ci.draw_colored_polygon(PackedVector2Array([p.call(0, -15), p.call(13, -15), p.call(13, 15), p.call(0, 15)]), paper.darkened(0.06))
	for y in [-17.0, 13.0]:
		ci.draw_colored_polygon(PackedVector2Array([p.call(-16, y), p.call(16, y), p.call(16, y + 5), p.call(-16, y + 5)]), roll)
	ci.draw_polyline(PackedVector2Array([p.call(-13, -15), p.call(13, -15), p.call(13, 15), p.call(-13, 15), p.call(-13, -15)]),
		LowpolyBox.edge_color(paper), 1.5 * u, true)
	var green := Color(0.20, 0.62, 0.32)
	for y in [-6.0, 5.0]:
		ci.draw_polyline(PackedVector2Array([p.call(-9, y), p.call(-6, y + 3), p.call(-1, y - 3)]), green, 2.5 * u, true)
		ci.draw_line(p.call(2, y), p.call(9, y), roll.darkened(0.2), 2.0 * u, true)

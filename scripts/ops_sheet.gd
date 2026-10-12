extends "res://scripts/ui_window.gd"
## 운영 창 공통(2026-10-12: 공지·우편·관리자 시트): 시트 크기(상단 칩 줄 아래 ~ 탭 바 위) + 제목 가운데·오른쪽 위 닫기(X) +
## 굴리는 목록(body). 하위 창은 _build(title)를 부르고 body에 줄을 넣는다.

const SUB := Color(0.16, 0.18, 0.24, 0.62)
const CLOSE_PX := 56.0
const RED := Color(0.88, 0.22, 0.2)

var head: HBoxContainer
var scroll: ScrollContainer
var body: VBoxContainer
var buttons := {}  # 이름 → Button(테스트용)


func _build(title_text: String) -> void:
	_build_window(0, 10)
	dialog.get_parent().color = Color(0, 0, 0, 0.35)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	head = HBoxContainer.new()
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(CLOSE_PX, 0)
	head.add_child(pad)
	var title := _title(title_text)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var x := Button.new()
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(CLOSE_PX, CLOSE_PX)
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiKit.apply_button(x, UiKit.STEEL, 10.0)
	x.pressed.connect(close)
	var face := Control.new()
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.draw.connect(func():
		var c := face.size / 2.0
		var r := CLOSE_PX * 0.2
		for d in [Vector2(r, r), Vector2(r, -r)]:
			face.draw_line(c - d, c + d, Color.WHITE, 5.0, true))
	x.add_child(face)
	head.add_child(x)
	buttons["close"] = x
	content.add_child(head)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	_fit_sheet()


func _fit() -> void:
	_fit_sheet()


func _clear_body() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()


## 흰 카드(안쪽 여백) 하나 — 안의 VBox를 돌려준다.
func _card(color: Color = Color(1, 1, 1, 0.85)) -> VBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.panel(color, 12.0, 16))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	return v


func _wrap(text: String, font_size: int, color: Color = HudScript.INK, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := _label(text, font_size, color, align)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(80, 0)
	return l


## 글 입력 한 줄(관리자·쿠폰).
static func line_edit(placeholder: String, max_len := 0) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	if max_len > 0:
		e.max_length = max_len
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.custom_minimum_size = Vector2(0, 56)
	e.add_theme_font_size_override("font_size", 24)
	e.add_theme_color_override("font_color", HudScript.INK)
	e.add_theme_color_override("font_placeholder_color", SUB)
	e.add_theme_stylebox_override("normal", UiKit.panel(Color.WHITE, 10.0, 12))
	e.add_theme_stylebox_override("focus", UiKit.panel(Color.WHITE, 10.0, 12))
	return e


## 몇 시간 전·며칠 전.
static func ago(unix: float, now: float) -> String:
	var s := maxf(0.0, now - unix)
	if s < 3600:
		return "%d분 전" % maxi(1, int(s / 60))
	if s < 86400:
		return "%d시간 전" % int(s / 3600)
	return "%d일 전" % int(s / 86400)

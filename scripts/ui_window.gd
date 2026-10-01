extends CanvasLayer
## 창 공통(스펙 §5, 상인 거래 창 방식): 어두운 반투명 배경(모든 입력을 먹는다, 탭하면 닫힘) + 가운데 로우폴리 패널.
## 열려 있는 동안 뒤 화면(카메라·탭·HUD)은 입력을 못 받는다 — GUI가 먼저 소비해 _unhandled_input에 안 닿는다.
## 연 직후 OPEN_GUARD_MS 동안은 누름을 전부 버린다(_input) — 연타(더블 탭)의 두 번째 누름이 창을 닫거나, 그 자리의 버튼·카드
## ([10회 모집] 등)를 누르지 않게. 내용이 크게 바뀔 때(모집 결과)도 _arm_guard로 다시 건다.
## 하위 창은 _ready에서 _build_window를 부르고 content(VBox)에 내용을 넣는다. 열 때 할 일은 _on_open에.

const UiKit := preload("res://scripts/ui_kit.gd")
const HudScript := preload("res://scripts/hud.gd")

const DIM := Color(0, 0, 0, 0.55)
const OPEN_GUARD_MS := 400  # 연 직후 이 시간 동안 이 창의 누름(버튼·카드·배경)을 버린다
const GROUP := "ui_windows"
const SHEET_TOP := 76  # 시트 위 끝: 상단 칩 줄(16..64) 아래
const SHEET_SIDE := 8

var dialog: PanelContainer
var content: VBoxContainer

var _opened_ms := 0


func _build_window(width: float, separation := 14) -> void:
	layer = 2  # HUD(1) 위
	visible = false
	add_to_group(GROUP)
	var back := ColorRect.new()
	back.color = DIM
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	back.mouse_force_pass_scroll_events = false  # 휠 줌이 뒤 카메라로 새지 않게
	back.gui_input.connect(_on_back_input)
	add_child(back)
	dialog = PanelContainer.new()
	dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	dialog.custom_minimum_size = Vector2(width, 0)
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP  # 패널 안 탭은 배경으로 새지 않는다
	dialog.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM_DIALOG, 18.0, 24))
	back.add_child(dialog)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", separation)
	dialog.add_child(content)


## 내용(보이는 부분)이 바뀐 뒤 패널을 내용 크기로 줄여 화면 가운데에 다시 둔다(크기 0에서 양쪽으로 자란다).
func _fit() -> void:
	dialog.offset_left = 0.0
	dialog.offset_right = 0.0
	dialog.offset_top = 0.0
	dialog.offset_bottom = 0.0


## 시트(하단 탭 창): 상단 칩 줄 아래부터 탭 바 위까지 채운다(크기 고정 — 내용이 바뀌어도 다시 맞추지 않는다).
func _fit_sheet() -> void:
	dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.offset_left = SHEET_SIDE
	dialog.offset_right = -SHEET_SIDE
	dialog.offset_top = SHEET_TOP
	dialog.offset_bottom = -(HudScript.TAB_BAR_H + 8)


func open() -> void:
	visible = true
	_arm_guard()
	_on_open()


## 지금부터 OPEN_GUARD_MS 동안 누름을 버린다.
func _arm_guard() -> void:
	_opened_ms = Time.get_ticks_msec()


func is_guarded() -> bool:
	return visible and Time.get_ticks_msec() - _opened_ms < OPEN_GUARD_MS


## 보호 중이면 누름(마우스·터치)을 GUI보다 먼저 먹는다 — 버튼은 누름 없이 뗌만 오면 눌리지 않는다.
func _input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed and is_guarded():
		get_viewport().set_input_as_handled()


## 이 창 말고 열린 창이 있는지.
func _another_window_open() -> bool:
	for w in get_tree().get_nodes_in_group(GROUP):
		if w != self and w.visible:
			return true
	return false


func _on_open() -> void:
	pass


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _on_back_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:  # 연 직후 누름은 _input이 이미 버렸다
		close()


func _label(text: String, font_size: int, color: Color = HudScript.INK, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


## 제목: 진한 외곽선(스펙 §4).
func _title(text: String) -> Label:
	var l := _label(text, 40)
	l.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	return l


func _button(text: String, color: Color = HudScript.ACCENT, font_size := 28) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 56)
	b.add_theme_font_size_override("font_size", font_size)
	UiKit.apply_button(b, color, 14.0)
	return b

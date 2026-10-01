extends CanvasLayer
## 창 공통(스펙 §5, 상인 거래 창 방식): 어두운 반투명 배경(모든 입력을 먹는다, 탭하면 닫힘) + 가운데 로우폴리 패널.
## 열려 있는 동안 뒤 화면(카메라·탭·HUD)은 입력을 못 받는다 — GUI가 먼저 소비해 _unhandled_input에 안 닿는다.
## 연 직후 OPEN_GUARD_MS 동안 배경 누름은 닫지 않는다(연타의 두 번째 누름). 하위 창은 _ready에서 _build_window를 부르고
## content(VBox)에 내용을 넣는다. 열 때 할 일은 _on_open에.

const UiKit := preload("res://scripts/ui_kit.gd")
const HudScript := preload("res://scripts/hud.gd")

const DIM := Color(0, 0, 0, 0.55)
const OPEN_GUARD_MS := 400  # 연 직후 이 시간 동안 배경 누름은 닫지 않는다

var dialog: PanelContainer
var content: VBoxContainer

var _opened_ms := 0


func _build_window(width: float, separation := 14) -> void:
	layer = 2  # HUD(1) 위
	visible = false
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


func open() -> void:
	visible = true
	_opened_ms = Time.get_ticks_msec()
	_on_open()


func _on_open() -> void:
	pass


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _on_back_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	# 연타(더블 탭)의 두 번째 누름이 연 창을 바로 닫지 않게 잠깐 무시
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and Time.get_ticks_msec() - _opened_ms > OPEN_GUARD_MS:
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

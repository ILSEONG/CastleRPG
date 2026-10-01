extends CanvasLayer
## 상인 거래 창(스펙 §4): 어두운 반투명 배경(모든 입력을 먹는다, 탭하면 닫힘) + 가운데 둥근 패널.
## 열려 있는 동안 뒤 화면(카메라·탭)은 입력을 못 받는다 — GUI가 먼저 소비해 _unhandled_input에 안 닿는다.
## 시세·남은 시간은 매초, 보유량은 Economy.changed마다 갱신한다.

const Balance := preload("res://scripts/balance.gd")
const HudScript := preload("res://scripts/hud.gd")
const IconsScript := preload("res://scripts/icons.gd")

const DIM := Color(0, 0, 0, 0.55)
const DIALOG_BG := Color(1, 1, 1, 0.97)
const RATE_LOW := Color(0.85, 0.22, 0.2)
const RATE_HIGH := Color(0.15, 0.6, 0.25)
const RATE_JACKPOT := Color(0.9, 0.62, 0.05)
const DIALOG_W := 600
const OPEN_GUARD_MS := 400  # 연 직후 이 시간 동안 배경 누름은 닫지 않는다

var dialog: PanelContainer
var sell_buttons := {}  # 자원 id → [판매] 버튼
var sell_all_button: Button

var _rate_label: Label
var _timer_label: Label
var _amount_labels := {}
var _value_labels := {}
var _last_sec := -1
var _opened_ms := 0


func _ready() -> void:
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
	dialog.custom_minimum_size = Vector2(DIALOG_W, 0)
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP  # 패널 안 탭은 배경으로 새지 않는다
	dialog.add_theme_stylebox_override("panel", HudScript.round_box(DIALOG_BG, 28, 24))
	back.add_child(dialog)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	dialog.add_child(col)

	col.add_child(_label("상인", 40, HudScript.INK, HORIZONTAL_ALIGNMENT_CENTER))
	_rate_label = _label("", 32, HudScript.INK, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_rate_label)
	_timer_label = _label("", 24, HudScript.INK.lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_timer_label)
	for id in Balance.RESOURCES:
		col.add_child(_row(id))
	sell_all_button = _button("전부 판매")
	sell_all_button.pressed.connect(func(): Economy.sell_all(_now()))
	col.add_child(sell_all_button)
	var close_button := _button("닫기", Color(0.55, 0.6, 0.7))
	close_button.pressed.connect(close)
	col.add_child(close_button)
	Economy.changed.connect(func(): if visible: _refresh(_now()))


func _process(_delta: float) -> void:
	if not visible:
		return
	var now := _now()
	if floori(now) != _last_sec:  # 매초. 정시를 넘으면 배율도 여기서 바뀐다
		_refresh(now)


func open() -> void:
	visible = true
	_opened_ms = Time.get_ticks_msec()
	_refresh(_now())


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _now() -> float:
	return Time.get_unix_time_from_system()


func _on_back_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	# 연타(더블 탭)의 두 번째 누름이 연 창을 바로 닫지 않게 잠깐 무시
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and Time.get_ticks_msec() - _opened_ms > OPEN_GUARD_MS:
		close()


func _refresh(now: float) -> void:
	_last_sec = floori(now)
	var rate := Economy.current_rate(now)
	_rate_label.text = "현재 시세 ×%.1f" % rate
	_rate_label.add_theme_color_override("font_color", rate_color(rate))
	var left := floori(Economy.seconds_to_next_rate(now))  # 59:59 → 00:00
	_timer_label.text = "다음 시세까지 %02d:%02d" % [left / 60, left % 60]
	var any := false
	for id in Balance.RESOURCES:
		var amount: int = Economy.res[id]
		_amount_labels[id].text = HudScript.commas(amount)
		_value_labels[id].text = "→ %s골드" % HudScript.commas(Economy.sell_value(id, amount, rate))
		sell_buttons[id].disabled = amount == 0
		any = any or amount > 0
	sell_all_button.disabled = not any


## 1 미만 빨강, 1 기본, 1 초과 초록, 2 금색.
static func rate_color(rate: float) -> Color:
	if rate >= Balance.MERCHANT_JACKPOT_RATE:
		return RATE_JACKPOT
	if rate > 1.0:
		return RATE_HIGH
	if rate < 1.0:
		return RATE_LOW
	return HudScript.INK


func _row(id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var icon = IconsScript.new()
	icon.kind = id
	icon.custom_minimum_size = Vector2(44, 44)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var amount := _label("", 30, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(amount)
	var value := _label("", 28, HudScript.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	value.custom_minimum_size = Vector2(190, 0)
	row.add_child(value)
	var sell := _button("판매")
	sell.custom_minimum_size = Vector2(110, 52)
	sell.pressed.connect(func(): Economy.sell(id, _now()))
	row.add_child(sell)
	_amount_labels[id] = amount
	_value_labels[id] = value
	sell_buttons[id] = sell
	return row


func _label(text: String, font_size: int, color: Color, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, color: Color = HudScript.ACCENT) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 56)
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_stylebox_override("normal", HudScript.round_box(color, HudScript.RADIUS + 6, 0))
	b.add_theme_stylebox_override("hover", HudScript.round_box(color.lightened(0.12), HudScript.RADIUS + 6, 0))
	b.add_theme_stylebox_override("pressed", HudScript.round_box(color.darkened(0.15), HudScript.RADIUS + 6, 0))
	b.add_theme_stylebox_override("disabled", HudScript.round_box(Color(0.6, 0.62, 0.66, 0.8), HudScript.RADIUS + 6, 0))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.7))
	return b

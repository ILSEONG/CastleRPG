extends VBoxContainer
## 수량 칸(개정 14 §4 거래 창에서 떼어 냈다 — 개정 16 병사 건물 훈련 칸도 쓴다): [−] 입력 [+] [최대] / 슬라이더. 값은 min_value..max_value 정수.
## [−]·[+]는 누르고 있으면 HOLD_DELAY 뒤부터 가속(초당 10 → 50). 입력은 규칙에 맞게 고쳐 쓴다(문자·음수는 최소, 넘치면 최대 —
## 빈 칸은 쓰는 중이라 둔다). [최대] = max_value. 값이 바뀌면 value_changed. 범위는 쓰는 창이 set_range로 정한다.

const UiKit := preload("res://scripts/ui_kit.gd")

const HOLD_DELAY := 0.4  # 누르고 있으면 이 시간 뒤부터 가속
const STEEL := Color(0.55, 0.6, 0.7)

signal value_changed(value: int)

var value := 0
var min_value := 0
var max_value := 0
var minus: Button
var plus: Button
var max_button: Button
var edit: LineEdit
var slider: HSlider

var _hold_dir := 0
var _hold_t := 0.0
var _hold_acc := 0.0


func _init() -> void:
	add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	minus = _button("−", 64)
	minus.button_down.connect(func(): _hold_start(-1))
	minus.button_up.connect(func(): _hold_dir = 0)
	edit = LineEdit.new()
	edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.add_theme_font_size_override("font_size", 28)
	edit.custom_minimum_size = Vector2(150, 52)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(_on_edit)
	plus = _button("+", 64)
	plus.button_down.connect(func(): _hold_start(1))
	plus.button_up.connect(func(): _hold_dir = 0)
	max_button = _button("최대", 90)
	max_button.pressed.connect(func(): set_value(max_value))
	for n in [minus, edit, plus, max_button]:
		top.add_child(n)
	add_child(top)
	slider = HSlider.new()
	slider.step = 1
	slider.custom_minimum_size = Vector2(0, 36)
	slider.value_changed.connect(func(v: float): set_value(int(v)))
	add_child(slider)
	_show()


func _process(delta: float) -> void:
	_tick_hold(delta)


## 범위를 바꾸고 값을 그 안으로 자른다(hi < lo면 lo).
func set_range(lo: int, hi: int) -> void:
	min_value = lo
	max_value = maxi(hi, lo)
	set_value(value)


func set_value(n: int) -> void:
	var v := clampi(n, min_value, max_value)
	var moved := v != value
	value = v
	_show()
	if moved:
		value_changed.emit(value)


func _show() -> void:
	if edit.text != str(value) and not (edit.text == "" and value == min_value):
		edit.text = str(value)
	slider.max_value = maxi(max_value, min_value + 1)  # 범위가 한 점이어도 슬라이더가 깨지지 않게
	slider.min_value = min_value
	slider.set_value_no_signal(value)


func _on_edit(text: String) -> void:
	set_value(maxi(text.to_int() if text.is_valid_int() else min_value, min_value))
	if text != str(value) and text != "":  # 규칙에 맞게 고쳐 쓴다(빈 칸은 쓰는 중이라 둔다)
		edit.text = str(value)
		edit.caret_column = edit.text.length()


func _hold_start(dir: int) -> void:
	_hold_dir = dir
	_hold_t = 0.0
	_hold_acc = 0.0
	set_value(value + dir)


## 누르고 있는 동안: 0.4초 뒤부터 초당 10, 시간이 갈수록 50까지. 칸이 숨으면(창 닫힘 — 뗌이 안 온다) 멈춘다.
func _tick_hold(delta: float) -> void:
	if _hold_dir == 0:
		return
	if not is_visible_in_tree():
		_hold_dir = 0
		return
	_hold_t += delta
	if _hold_t < HOLD_DELAY:
		return
	_hold_acc += delta * minf(10.0 + (_hold_t - HOLD_DELAY) * 20.0, 50.0)
	var steps := int(_hold_acc)
	if steps > 0:
		_hold_acc -= steps
		set_value(value + _hold_dir * steps)


func _button(text: String, w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 52)
	b.add_theme_font_size_override("font_size", 28)
	UiKit.apply_button(b, STEEL, 14.0)
	return b

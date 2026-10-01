extends "res://scripts/ui_window.gd"
## 상인 거래 창(스펙 §4). 배경·바깥 탭 닫기·뒤 입력 차단·연 직후 보호는 ui_window.gd.
## 자원마다 자기 시세(행의 ×배율), 위에 다음 시세까지 mm:ss. 시세·남은 시간은 매초, 보유량은 Economy.changed마다 갱신한다.
## 금색(2배) 행의 배율은 반짝인다.

const GameData := preload("res://scripts/game_data.gd")
const IconsScript := preload("res://scripts/icons.gd")

const RATE_LOW := Color(0.85, 0.22, 0.2)
const RATE_HIGH := Color(0.15, 0.6, 0.25)
const RATE_JACKPOT := Color(0.9, 0.62, 0.05)
const DIALOG_W := 600

var sell_buttons := {}  # 자원 id → [판매] 버튼
var sell_all_button: Button

var rate_labels := {}  # 자원 id → 행의 ×배율 라벨

var _timer_label: Label
var _jackpot := {}  # 자원 id → 지금 금색(반짝임)인가
var _amount_labels := {}
var _value_labels := {}
var _last_sec := -1

# 수량 판매(스펙 §4): 한 번에 한 행만 펼친다
const HOLD_DELAY := 0.4  # 누르고 있으면 이 시간 뒤부터 가속(초당 10 → 50)
var qty_boxes := {}  # 자원 id → 수량 칸(VBox)
var qty_edits := {}
var qty_sliders := {}
var qty_gold_labels := {}
var qty_confirms := {}
var qty_minus := {}
var qty_plus := {}
var qty_max := {}
var open_res := ""
var qty := 0
var _hold_dir := 0
var _hold_t := 0.0
var _hold_acc := 0.0


func _ready() -> void:
	_build_window(DIALOG_W)
	var col := content
	col.add_child(_title("상인"))
	_timer_label = _label("", 28, HudScript.INK, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_timer_label)
	for r in GameData.resources():
		var id: String = r.id
		col.add_child(_row(id))
	sell_all_button = _button("전부 판매")
	sell_all_button.pressed.connect(func(): Economy.sell_all(_now()))
	col.add_child(sell_all_button)
	var close_button := _button("닫기", Color(0.55, 0.6, 0.7))
	close_button.pressed.connect(close)
	col.add_child(close_button)
	Economy.changed.connect(func(): if visible: _refresh(_now()))


func _process(delta: float) -> void:
	if not visible:
		return
	_tick_hold(delta)
	var glow := 0.8 + 0.2 * sin(Time.get_ticks_msec() / 150.0)  # 금색 반짝임
	for id in _jackpot:
		rate_labels[id].modulate = Color(glow, glow, glow) if _jackpot[id] else Color.WHITE
	var now := _now()
	if floori(now) != _last_sec:  # 매초. 정시를 넘으면 배율도 여기서 바뀐다
		_refresh(now)


func _on_open() -> void:
	_hold_dir = 0
	_open_qty("")
	_refresh(_now())


func _now() -> float:
	return Economy.time_now()  # 온라인은 서버 보정 시각


func _refresh(now: float) -> void:
	_last_sec = floori(now)
	var left := floori(Economy.seconds_to_next_rate(now))  # 59:59 → 00:00
	_timer_label.text = "다음 시세까지 %02d:%02d" % [left / 60, left % 60]
	var any := false
	for r in GameData.resources():
		var id: String = r.id
		var amount: int = Economy.res[id]
		var rate := Economy.current_rate(id, now)
		rate_labels[id].text = "×%.1f" % rate
		rate_labels[id].add_theme_color_override("font_color", rate_color(rate))
		_jackpot[id] = rate >= GameData.config_num("merchant_jackpot_rate")
		_amount_labels[id].text = HudScript.commas(amount)
		_value_labels[id].text = "→ %s골드" % HudScript.commas(Economy.sell_value(id, amount, rate))
		sell_buttons[id].disabled = amount == 0
		any = any or amount > 0
	sell_all_button.disabled = not any
	if open_res != "" and Economy.res[open_res] == 0:
		_open_qty("")  # 다 팔았으면 접는다
	_refresh_qty(now)


## 1 미만 빨강, 1 기본, 1 초과 초록, 2 금색.
static func rate_color(rate: float) -> Color:
	if rate >= GameData.config_num("merchant_jackpot_rate"):
		return RATE_JACKPOT
	if rate > 1.0:
		return RATE_HIGH
	if rate < 1.0:
		return RATE_LOW
	return HudScript.INK


func _row(id: String) -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	wrap.add_child(_main_row(id))
	wrap.add_child(_qty_box(id))
	return wrap


func _main_row(id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var icon = IconsScript.new()
	icon.kind = id
	icon.custom_minimum_size = Vector2(44, 44)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var amount := _label("", 30, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(amount)
	var rate := _label("", 30, HudScript.INK, HORIZONTAL_ALIGNMENT_CENTER)
	rate.custom_minimum_size = Vector2(80, 0)
	row.add_child(rate)
	var value := _label("", 28, HudScript.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	value.custom_minimum_size = Vector2(170, 0)
	row.add_child(value)
	var sell := _button("판매")
	sell.custom_minimum_size = Vector2(110, 52)
	sell.pressed.connect(func(): _open_qty("" if open_res == id else id))
	row.add_child(sell)
	_amount_labels[id] = amount
	rate_labels[id] = rate
	_value_labels[id] = value
	sell_buttons[id] = sell
	return row



## 수량 칸: [−] 입력 [+] / 슬라이더 / [최대] → N골드 [판매]
func _qty_box(id: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.visible = false
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var minus := _button("−", Color(0.55, 0.6, 0.7))
	minus.custom_minimum_size = Vector2(64, 52)
	minus.button_down.connect(func(): _hold_start(-1))
	minus.button_up.connect(func(): _hold_dir = 0)
	var edit := LineEdit.new()
	edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.add_theme_font_size_override("font_size", 28)
	edit.custom_minimum_size = Vector2(150, 52)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(_on_edit)
	var plus := _button("+", Color(0.55, 0.6, 0.7))
	plus.custom_minimum_size = Vector2(64, 52)
	plus.button_down.connect(func(): _hold_start(1))
	plus.button_up.connect(func(): _hold_dir = 0)
	var mx := _button("최대", Color(0.55, 0.6, 0.7))
	mx.custom_minimum_size = Vector2(90, 52)
	mx.pressed.connect(func(): _set_qty(Economy.res[id]))
	for n in [minus, edit, plus, mx]:
		top.add_child(n)
	box.add_child(top)
	var slider := HSlider.new()
	slider.step = 1
	slider.custom_minimum_size = Vector2(0, 36)
	slider.value_changed.connect(func(v: float): _set_qty(int(v)))
	box.add_child(slider)
	var bottom := HBoxContainer.new()
	var gold := _label("", 28, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	gold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var confirm := _button("판매")
	confirm.custom_minimum_size = Vector2(130, 52)
	confirm.pressed.connect(func(): Economy.sell(id, _now(), qty))
	bottom.add_child(gold)
	bottom.add_child(confirm)
	box.add_child(bottom)
	qty_boxes[id] = box
	qty_edits[id] = edit
	qty_sliders[id] = slider
	qty_gold_labels[id] = gold
	qty_confirms[id] = confirm
	qty_minus[id] = minus
	qty_plus[id] = plus
	qty_max[id] = mx
	return box


## 그 행의 수량 칸을 펼친다(다른 행은 접힌다). ""이면 모두 접는다.
func _open_qty(id: String) -> void:
	open_res = id
	qty = 0
	for k in qty_boxes:
		qty_boxes[k].visible = k == id
	_refresh_qty(_now())
	_fit()


func _set_qty(n: int) -> void:
	if open_res == "":
		return
	qty = clampi(n, 0, Economy.res[open_res])
	_refresh_qty(_now())


func _on_edit(text: String) -> void:
	var n := int(text) if text.is_valid_int() else 0  # 문자·음수는 0, 보유 초과는 보유로(_set_qty)
	_set_qty(maxi(n, 0))
	var edit: LineEdit = qty_edits[open_res]
	if text != str(qty) and text != "":  # 규칙에 맞게 고쳐 쓴다(빈 칸은 쓰는 중이라 둔다)
		edit.text = str(qty)
		edit.caret_column = edit.text.length()


func _refresh_qty(now: float) -> void:
	if open_res == "":
		return
	var have: int = Economy.res[open_res]
	qty = clampi(qty, 0, have)
	var edit: LineEdit = qty_edits[open_res]
	if edit.text != str(qty) and not (edit.text == "" and qty == 0):
		edit.text = str(qty)
	var slider: HSlider = qty_sliders[open_res]
	slider.max_value = maxi(have, 1)
	slider.set_value_no_signal(qty)
	qty_gold_labels[open_res].text = "→ %s골드" % HudScript.commas(Economy.sell_value(open_res, qty, Economy.current_rate(open_res, now)))
	qty_confirms[open_res].disabled = qty == 0


func _hold_start(dir: int) -> void:
	_hold_dir = dir
	_hold_t = 0.0
	_hold_acc = 0.0
	_set_qty(qty + dir)


## 누르고 있는 동안: 0.4초 뒤부터 초당 10, 시간이 갈수록 50까지.
func _tick_hold(delta: float) -> void:
	if _hold_dir == 0:
		return
	_hold_t += delta
	if _hold_t < HOLD_DELAY:
		return
	_hold_acc += delta * minf(10.0 + (_hold_t - HOLD_DELAY) * 20.0, 50.0)
	var steps := int(_hold_acc)
	if steps > 0:
		_hold_acc -= steps
		_set_qty(qty + _hold_dir * steps)

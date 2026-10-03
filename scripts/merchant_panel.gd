extends "res://scripts/ui_window.gd"
## 상인 거래 창(스펙 §4). 배경·바깥 탭 닫기·뒤 입력 차단·연 직후 보호는 ui_window.gd.
## 자원마다 자기 시세(행의 ×배율), 위에 다음 시세까지 mm:ss. 시세·남은 시간은 매초, 보유량은 Economy.changed마다 갱신한다.
## 금색(2배) 행의 배율은 반짝인다.

const GameData := preload("res://scripts/game_data.gd")
const IconsScript := preload("res://scripts/icons.gd")
const QtyBox := preload("res://scripts/qty_box.gd")

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

# 수량 판매(스펙 §4): 행마다 따로 펼친다(여럿 동시에 열 수 있다). [선택 판매]가 열린 칸의 수량을 한 번에 판다.
# 수량 입력은 qty_box.gd(개정 16에서 훈련 칸과 같이 쓰려고 떼어 냈다)
var qty_boxes := {}  # 자원 id → 수량 칸(VBox: 수량 입력 + 골드)
var qty_inputs := {}  # 자원 id → 수량 입력(qty_box.gd)
var qty_edits := {}
var qty_sliders := {}
var qty_gold_labels := {}
var qty_minus := {}
var qty_plus := {}
var qty_max := {}
var sell_selected_button: Button
var qtys: Dictionary:  # 자원 id → 고른 수량(접힌 칸은 0)
	get:
		var d := {}
		for id in qty_inputs:
			d[id] = qty_inputs[id].value if qty_boxes[id].visible else 0
		return d


func _ready() -> void:
	_build_window(DIALOG_W)
	var col := content
	col.add_child(_title("상인"))
	_timer_label = _label("", 28, HudScript.INK, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_timer_label)
	for r in GameData.resources():
		var id: String = r.id
		col.add_child(_row(id))
	sell_selected_button = _button("선택 판매 · 0골드")
	sell_selected_button.pressed.connect(_sell_selected)
	col.add_child(sell_selected_button)
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
	var glow := 0.8 + 0.2 * sin(Time.get_ticks_msec() / 150.0)  # 금색 반짝임
	for id in _jackpot:
		rate_labels[id].modulate = Color(glow, glow, glow) if _jackpot[id] else Color.WHITE
	var now := _now()
	if floori(now) != _last_sec:  # 매초. 정시를 넘으면 배율도 여기서 바뀐다
		_refresh(now)


func _on_open() -> void:
	for id in qty_boxes:
		qty_boxes[id].visible = false
		qty_inputs[id].set_value(0)
	_fit()
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
		_value_labels[id].text = "→ %s골드" % HudScript.commas(Economy.sell_gold(id, amount, rate))
		sell_buttons[id].disabled = amount == 0
		any = any or amount > 0
		if qty_boxes[id].visible and amount == 0:
			_toggle_qty(id)  # 다 팔았으면 접는다
	sell_all_button.disabled = not any
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
	sell.pressed.connect(func(): _toggle_qty(id))
	row.add_child(sell)
	_amount_labels[id] = amount
	rate_labels[id] = rate
	_value_labels[id] = value
	sell_buttons[id] = sell
	return row


## 수량 칸: 수량 입력([−] 입력 [+] [최대] / 슬라이더, 0..보유) / → N골드
func _qty_box(id: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.visible = false
	var q = QtyBox.new()
	q.value_changed.connect(func(_v): _qty_labels(_now()))
	box.add_child(q)
	var gold := _label("", 28, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	box.add_child(gold)
	qty_boxes[id] = box
	qty_inputs[id] = q
	qty_edits[id] = q.edit
	qty_sliders[id] = q.slider
	qty_gold_labels[id] = gold
	qty_minus[id] = q.minus
	qty_plus[id] = q.plus
	qty_max[id] = q.max_button
	return box


## 그 행의 수량 칸을 펼치거나 접는다(다른 행은 그대로). 펼치든 접든 수량은 0.
func _toggle_qty(id: String) -> void:
	qty_boxes[id].visible = not qty_boxes[id].visible
	qty_inputs[id].set_value(0)  # 접힌 칸은 누르고 있던 [+]·[−]도 qty_box가 멈춘다
	_refresh_qty(_now())
	_fit()


func _set_qty(id: String, n: int) -> void:
	if qty_boxes[id].visible:
		qty_inputs[id].set_value(n)


## 열린 칸마다 범위(0..보유)를 맞추고 골드·[선택 판매]를 고친다.
func _refresh_qty(now: float) -> void:
	for id in qty_boxes:
		if qty_boxes[id].visible:
			qty_inputs[id].set_range(0, Economy.res[id])
	_qty_labels(now)


## 열린 칸마다 → N골드, [선택 판매]에 그 합계.
func _qty_labels(now: float) -> void:
	var total_amount := 0
	var total_gold := 0
	for id in qty_boxes:
		if not qty_boxes[id].visible:
			continue
		var q: int = qty_inputs[id].value
		var g := Economy.sell_gold(id, q, Economy.current_rate(id, now))
		qty_gold_labels[id].text = "→ %s골드" % HudScript.commas(g)
		total_amount += q
		total_gold += g
	sell_selected_button.text = "선택 판매 · %s골드" % HudScript.commas(total_gold)
	sell_selected_button.disabled = total_amount == 0


## 열린 칸들의 수량을 한 번에 판다. 판 뒤 수량은 0, 칸은 열어 둔다.
func _sell_selected() -> void:
	var items := []
	for id in qty_boxes:
		if qty_boxes[id].visible and qty_inputs[id].value > 0:
			items.append({"res": id, "amount": qty_inputs[id].value})
	if items.is_empty():
		return
	Economy.sell_many(items, _now())
	for it in items:
		qty_inputs[it.res].set_value(0)
	_refresh(_now())

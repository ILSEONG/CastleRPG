extends "res://scripts/ui_window.gd"
## 상인 거래 창(스펙 §4). 배경·바깥 탭 닫기·뒤 입력 차단·연 직후 보호는 ui_window.gd.
## 시세·남은 시간은 매초, 보유량은 Economy.changed마다 갱신한다.

const GameData := preload("res://scripts/game_data.gd")
const IconsScript := preload("res://scripts/icons.gd")

const RATE_LOW := Color(0.85, 0.22, 0.2)
const RATE_HIGH := Color(0.15, 0.6, 0.25)
const RATE_JACKPOT := Color(0.9, 0.62, 0.05)
const DIALOG_W := 600

var sell_buttons := {}  # 자원 id → [판매] 버튼
var sell_all_button: Button

var _rate_label: Label
var _timer_label: Label
var _amount_labels := {}
var _value_labels := {}
var _last_sec := -1


func _ready() -> void:
	_build_window(DIALOG_W)
	var col := content
	col.add_child(_title("상인"))
	_rate_label = _label("", 32, HudScript.INK, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_rate_label)
	_timer_label = _label("", 24, HudScript.INK.lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER)
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


func _process(_delta: float) -> void:
	if not visible:
		return
	var now := _now()
	if floori(now) != _last_sec:  # 매초. 정시를 넘으면 배율도 여기서 바뀐다
		_refresh(now)


func _on_open() -> void:
	_refresh(_now())


func _now() -> float:
	return Economy.time_now()  # 온라인은 서버 보정 시각


func _refresh(now: float) -> void:
	_last_sec = floori(now)
	var rate := Economy.current_rate(now)
	_rate_label.text = "현재 시세 ×%.1f" % rate
	_rate_label.add_theme_color_override("font_color", rate_color(rate))
	var left := floori(Economy.seconds_to_next_rate(now))  # 59:59 → 00:00
	_timer_label.text = "다음 시세까지 %02d:%02d" % [left / 60, left % 60]
	var any := false
	for r in GameData.resources():
		var id: String = r.id
		var amount: int = Economy.res[id]
		_amount_labels[id].text = HudScript.commas(amount)
		_value_labels[id].text = "→ %s골드" % HudScript.commas(Economy.sell_value(id, amount, rate))
		sell_buttons[id].disabled = amount == 0
		any = any or amount > 0
	sell_all_button.disabled = not any


## 1 미만 빨강, 1 기본, 1 초과 초록, 2 금색.
static func rate_color(rate: float) -> Color:
	if rate >= GameData.config_num("merchant_jackpot_rate"):
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


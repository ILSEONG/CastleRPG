extends "res://scripts/ui_window.gd"
## [성장] 탭 시트(개정 20 §5): 공용 업그레이드 6줄. 위 보유 골드 한 줄, 아래 안내 "성장은 모든 영웅·병사에게 적용됩니다".
## 줄: 아이콘(검·하트·쌍화살표 시계·장화·과녁·폭발 별) · 이름 · "Lv 23 / 200" · 현재 → 다음 효과("+11.5% → +12.0%", 최대면 "(최대)") ·
## [강화 비용](골드 부족·최대 레벨이면 비활성) · [×10](10번 합계 — 10번을 다 못 하면(골드 부족·최대 레벨까지 10 미만) 비활성).
## [강화]는 누르는 순간 한 번, 누르고 있으면 HOLD_DELAY 뒤부터 가속(qty_box와 같은 초당 10 → 50). 강화는 Economy.growth_up
## (오프라인은 곧바로, 온라인은 응답 때 — 응답을 기다리는 동안 길게 누르기는 쉬었다 잇는다). 영웅 시트처럼 칩 줄 아래 ~ 탭 바 위를 채운다.

const GameData := preload("res://scripts/game_data.gd")
const IconsScript := preload("res://scripts/icons.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const QtyBox := preload("res://scripts/qty_box.gd")

const ICONS := {"atk": "sword", "hp": "heart", "aspd": "haste", "mspd": "shoes", "crit_rate": "target", "crit_dmg": "burst"}  # 항목 id → 아이콘
const NOTE := "성장은 모든 영웅·병사에게 적용됩니다"
const WAIT := "응답 대기 중"  # Economy.growth_block의 잠깐 막힘(버튼을 끄지 않는다 — 누르고 있는 동안 뗌을 놓치지 않게)
const TEN := 10
const ICON_PX := 72.0
const GREEN := Color(0.13, 0.50, 0.22)

var rows := {}  # 항목 id → {lv, effect, up: {button, title, gold}, ten: {button, title, gold}}
var gold_label: Label

var _hold_id := ""  # 누르고 있는 [강화]의 항목(없으면 "")
var _hold_t := 0.0
var _hold_acc := 0.0


func _ready() -> void:
	_build_window(0, 10)
	dialog.get_parent().color = Color(0, 0, 0, 0)  # 시트가 화면을 채운다
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_title("성장"))
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 8)
	var coin = IconsScript.new()
	coin.custom_minimum_size = Vector2(34, 34)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(coin)
	gold_label = _label("", 30)
	top.add_child(gold_label)
	content.add_child(top)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)
	for u in GameData.upgrades():
		box.add_child(_row(u))
	content.add_child(_label(NOTE, 22, HudScript.INK.lightened(0.3)))
	_fit()
	Economy.changed.connect(_refresh)
	Economy.upgrades_changed.connect(_refresh)


func _fit() -> void:
	_fit_sheet()


func _on_open() -> void:
	_refresh()


func _process(delta: float) -> void:
	_tick_hold(delta)


## [×10]: 정확히 10번 한 번에. 10번을 다 못 하면 아무것도 하지 않는다(버튼도 꺼져 있다).
func press_ten(id: String) -> void:
	if Economy.growth_block(id, TEN) == "":
		Economy.growth_up(id, TEN)


## [강화] 누름: 곧바로 한 번, 누르고 있으면 _tick_hold가 잇는다.
func _hold_start(id: String) -> void:
	_hold_id = id
	_hold_t = 0.0
	_hold_acc = 0.0
	Economy.growth_up(id)


## 누르고 있는 동안: HOLD_DELAY 뒤부터 초당 10, 시간이 갈수록 50까지(qty_box와 같다). 응답 대기면 쉬고, 골드·최대 레벨로 막히거나
## 시트가 숨으면(뗌이 안 온다) 멈춘다.
func _tick_hold(delta: float) -> void:
	if _hold_id == "":
		return
	var why := Economy.growth_block(_hold_id)
	if not visible or (why != "" and why != WAIT):
		_hold_id = ""
		return
	_hold_t += delta
	if _hold_t < QtyBox.HOLD_DELAY or why == WAIT:
		return
	_hold_acc += delta * minf(10.0 + (_hold_t - QtyBox.HOLD_DELAY) * 20.0, 50.0)
	var n := mini(int(_hold_acc), Economy.upgrade_count_affordable(_hold_id, int(_hold_acc)))
	if n > 0:
		_hold_acc -= n
		Economy.growth_up(_hold_id, n)


func _refresh() -> void:
	if not visible:
		return
	gold_label.text = "보유 골드 %s" % UiKit.commas(Economy.gold)
	var waiting := Economy.upgrades_waiting()
	for id in rows:
		var r: Dictionary = rows[id]
		var u := GameData.upgrade_def(id)
		var lv := Economy.upgrade_level(id)
		var mx := int(u.max_level)
		var unit := "%" if u.unit == "pct" else "%p"
		r.lv.text = "Lv %d / %d" % [lv, mx]
		r.effect.text = effect_text(lv * float(u.per_level), unit) + (" (최대)" if lv >= mx else " → " + effect_text((lv + 1) * float(u.per_level), unit))
		var why := Economy.growth_block(id)
		r.up.title.text = "강화" if lv < mx else "MAX"
		r.up.gold.text = UiKit.commas(GameData.upgrade_cost(id, lv)) if lv < mx else "-"
		r.up.button.disabled = why != "" and why != WAIT
		r.ten.title.text = "×10"
		r.ten.gold.text = UiKit.commas(Economy.upgrade_total_cost(id, TEN)) if lv + TEN <= mx else "-"
		r.ten.button.disabled = Economy.growth_block(id, TEN) != "" or waiting


## 효과 글자: 11.5 → "+11.5%", 12 → "+12.0%", 0.75 → "+0.75%"(소수 첫째 자리는 늘 보인다).
static func effect_text(v: float, unit: String) -> String:
	var s := ("%.2f" % v).rstrip("0")
	if s.ends_with("."):
		s += "0"
	return "+" + s + unit


func _row(u: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_icon(ICONS.get(u.id, "")))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 0)
	info.add_child(_label(u.name, 28, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	var lv := _label("", 22, HudScript.INK.lightened(0.3), HORIZONTAL_ALIGNMENT_LEFT)
	info.add_child(lv)
	var effect := _label("", 22, GREEN, HORIZONTAL_ALIGNMENT_LEFT)
	info.add_child(effect)
	row.add_child(info)
	var up := _cost_button("강화", 124.0)
	up.button.button_down.connect(_hold_start.bind(u.id))
	up.button.button_up.connect(func(): _hold_id = "")
	row.add_child(up.button)
	var ten := _cost_button("×10", 140.0)
	ten.button.pressed.connect(press_ten.bind(u.id))
	row.add_child(ten.button)
	rows[u.id] = {"lv": lv, "effect": effect, "up": up, "ten": ten}
	return row


## 줄 아이콘: 강철색 8각 바탕 + 아이콘(입력 없음).
func _icon(kind: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var r := Rect2(Vector2.ZERO, c.size).grow(-2.0)
		var oct := LowpolyBox.octagon(r, r.size.x * 0.22)
		c.draw_colored_polygon(oct, UiKit.STEEL.lightened(0.55))
		oct.append(oct[0])
		c.draw_polyline(oct, UiKit.OUTLINE, 2.0, true)
		IconsScript.draw_icon(c, kind, c.size / 2.0, c.size.x * 0.78))
	return c


## 비용 버튼(영웅 상세 [레벨업]과 같은 꼴): 위 제목, 아래 [골드 아이콘 숫자](버튼 안, 입력은 버튼이 받는다).
func _cost_button(text: String, w: float) -> Dictionary:
	var b := _button("")
	b.custom_minimum_size = Vector2(w, 96)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var title := _on_button_label(text, 26)
	box.add_child(title)
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 4)
	box.add_child(line)
	var icon = IconsScript.new()
	icon.custom_minimum_size = Vector2(24, 24)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(icon)
	var gold := _on_button_label("", 22)
	line.add_child(gold)
	return {"button": b, "title": title, "gold": gold}


func _on_button_label(text: String, font_size: int) -> Label:
	var l := _label(text, font_size, Color.WHITE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_outline_color", Color(HudScript.INK, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	return l

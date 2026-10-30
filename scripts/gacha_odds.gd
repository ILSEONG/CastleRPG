extends Control
## 모집 확률 안내(출시 필수, 확률형 아이템 표시 — 2026-10-12): 모집 창 [확률 정보]가 연다. 어두운 막 + 크림 창(뒤 탭을 막는다).
## 지금 고른 모집(골드 = 지금 골드 모집 레벨, 다이아 = 다이아·모집권 공통)의 등급 확률, 보장 규칙, 영웅 한 명 한 명의 확률, 골드는 레벨별 표.
## 확률은 서버 뽑기(rules.ts rollGacha·gachaRates)와 같은 식: 등급(주점 보너스 포함)을 정한 뒤 그 등급 영웅 중 균등 → 영웅 확률 = 등급 확률 / 그 등급 영웅 수.
## 보장(10회 SR 이상)으로 바뀌는 장도 그 등급 안에서 균등이다. 확률 값은 바꾸지 않는다 — 보여 주기만.

const Lang := preload("res://scripts/lang.gd")

const GameData := preload("res://scripts/game_data.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

const GRADES := ["UR", "SSR", "SR", "R"]

var title_label: Label
var list: VBoxContainer  # 테스트가 읽는다: 영웅 줄은 meta "hero_id"·"p"
var close_button: Button


## 영웅별 확률 [{id, name, grade, p}](p = 0..1, 표 순서 UR → SSR → SR → R, 그 안은 영웅 표 순서). rates = {ur, ssr, sr}.
## UR 확률이 0(골드 모집)이면 UR 영웅은 빼고 보인다.
static func hero_odds(rates: Dictionary) -> Array:
	var by := {"UR": [], "SSR": [], "SR": [], "R": []}
	for h in GameData.heroes():
		if by.has(str(h.grade)):
			by[str(h.grade)].append(h)
	var ur := float(rates.get("ur", 0.0))
	var gp := {"UR": ur, "SSR": float(rates.ssr), "SR": float(rates.sr), "R": 1.0 - ur - float(rates.ssr) - float(rates.sr)}
	var out := []
	for g in GRADES:
		if g == "UR" and ur <= 0.0:
			continue
		for h in by[g]:
			out.append({"id": h.id, "name": str(h.name), "grade": g, "p": gp[g] / float(by[g].size())})
	return out


## "0.5000%"(소수 넷째 자리까지).
static func pct(p: float) -> String:
	return "%.4f%%" % (p * 100.0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var box := PanelContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 24
	box.offset_right = -24
	box.offset_top = 90
	box.offset_bottom = -110
	box.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM_DIALOG, 14.0, 22))
	add_child(box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	box.add_child(col)
	title_label = _label("", 30)
	col.add_child(title_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	close_button = Button.new()
	close_button.text = Lang.t("gacha_odds.ready")
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(220, 68)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.add_theme_font_size_override("font_size", 26)
	UiKit.apply_button(close_button, UiKit.STEEL, 14.0)
	close_button.pressed.connect(func(): visible = false)
	col.add_child(close_button)


## currency = 골드 또는 다이아(모집권은 다이아와 같다). gold_level = 지금 골드 모집 레벨.
func show_for(currency: String, gold_level: int) -> void:
	for c in list.get_children():
		c.queue_free()
	var dia := currency != GameData.GACHA_GOLD
	var rates := GameData.gacha_rates(GameData.GACHA_DIA if dia else GameData.GACHA_GOLD, gold_level)
	title_label.text = Lang.t("gacha_odds.show_for") + (Lang.t("gacha_odds.show_for_2") if dia else Lang.t("gacha_odds.show_for_3") % gold_level)
	if dia:
		_line("UR %s · SSR %s · SR %s · R %s" % [pct(rates.ur), pct(rates.ssr), pct(rates.sr), pct(1.0 - rates.ur - rates.ssr - rates.sr)], 24, UiKit.INK)
	else:
		_line("SSR %s · SR %s · R %s" % [pct(rates.ssr), pct(rates.sr), pct(1.0 - rates.ssr - rates.sr)], 24, UiKit.INK)
	if dia:
		_line(Lang.t("gacha_odds.show_for_6") % int(GameData.config_num("gacha_10_min_sr")), 20, SUB)
	else:
		_line(Lang.t("gacha_odds.show_for_7") % GameData.GOLD_SSR_FROM, 20, SUB)
	_line(Lang.t("gacha_odds.show_for_8"), 18, SUB)
	var grade := ""
	for o in hero_odds(rates):
		if o.grade != grade:
			grade = o.grade
			var n := hero_odds(rates).filter(func(x): return x.grade == grade).size()
			_line(Lang.t("gacha_odds.show_for_9") % [grade, n, pct(o.p)], 24, UiKit.GRADE_COLORS[grade].darkened(0.25))
		_hero_row(o)
	if not dia:
		_line(Lang.t("gacha_odds.show_for_10"), 24, UiKit.INK)
		for lv in range(1, int(GameData.config_num("gacha_gold_level_max")) + 1):
			var r := GameData.gacha_rates(GameData.GACHA_GOLD, lv)
			var need := GameData.gacha_gold_next(lv)
			var up := Lang.t("gacha_odds.show_for.up") % UiKit.commas(need) if need > 0 else ""
			_line("Lv %d: SSR %s · SR %s · R %s%s" % [lv, pct(r.ssr), pct(r.sr), pct(1.0 - r.ssr - r.sr), up], 18, UiKit.INK if lv == gold_level else SUB)
	visible = true


const SUB := Color(0.25, 0.22, 0.2, 0.8)


func _hero_row(o: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.set_meta("hero_id", o.id)
	row.set_meta("p", o.p)
	var n := _label(o.name, 22, UiKit.INK, HORIZONTAL_ALIGNMENT_LEFT)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(n)
	row.add_child(_label(pct(o.p), 22, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT))
	list.add_child(row)


func _line(text: String, size: int, color: Color) -> void:
	var l := _label(text, size, color, HORIZONTAL_ALIGNMENT_LEFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(l)


func _label(text: String, size: int, color: Color = UiKit.INK, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

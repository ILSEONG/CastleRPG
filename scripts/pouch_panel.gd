extends "res://scripts/ui_window.gd"
## [가방] 시트(오른쪽 아래 메뉴 side_menu.gd [가방]이 연다): 방치 주머니(골드·자원 × 10분·30분·1시간·2시간·4시간·6시간).
## 줄 = 주머니 그림 + 이름 + "보유 n개" + 지금 열면 받는 값(여는 순간의 방치 수입 × 시간 — Economy.pouch_value), 오른쪽 [열기](1개)·[모두].
## 보유한 주머니만, 골드 먼저·짧은 시간 먼저. 주머니는 출석·미션 보상으로 받는다(서버 pouches.ts).
## 아래에 가속 아이템(2026-10-13): 보유 개수만 보이고(건설·연구 창의 [가속]에서 쓴다), 일꾼 고용권만 여기서 [사용].

const Lang := preload("res://scripts/lang.gd")

const IconsScript := preload("res://scripts/icons.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const ShopArt := preload("res://scripts/shop_art.gd")

const SUB := Color(0.16, 0.18, 0.24, 0.62)
const ROW_BG := Color(1, 1, 1, 0.75)
const VALUE := Color(0.13, 0.50, 0.24)
const CLOSE_PX := 56.0
const ICON_PX := 72.0
static var EMPTY_TEXT := Lang.t("pouch_panel.empty_text")
static var SPEEDUP_HEAD := Lang.t("pouch_panel.speedup_head")
static var SPEEDUP_HINT := Lang.t("pouch_panel.speedup_hint")
static var EMPTY_VALUE_TEXT := Lang.t("pouch_panel.empty_value_text")
static var HEAD_TEXT := Lang.t("pouch_panel.head_text")
const GOLD_SACK := Color(0.80, 0.58, 0.26)
const RES_SACK := Color(0.52, 0.62, 0.36)

var body: VBoxContainer
var empty_label: Label
var head_label: Label  # 주머니 안내(주머니가 있을 때만)
var buttons := {}  # 테스트용: "open:<id>", "all:<id>", "close"

var _dirty := true


func _ready() -> void:
	_build_window(0, 10)
	dialog.get_parent().color = Color(0, 0, 0, 0)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()  # 제목 가운데 + 오른쪽 위 닫기(X)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(CLOSE_PX, 0)
	head.add_child(pad)
	var title := _title(Lang.t("pouch_panel.ready"))
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
	head_label = _label(HEAD_TEXT, 20, SUB)
	content.add_child(head_label)
	empty_label = _label(EMPTY_TEXT, 24, SUB)
	content.add_child(empty_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	_fit_sheet()
	Economy.pouches_changed.connect(func(): _dirty = true)
	Economy.speedups_changed.connect(func(): _dirty = true)
	Economy.changed.connect(func(): _dirty = true)  # 스테이지·건물 레벨이 오르면 여는 값도 바뀐다
	Economy.pouch_opened.connect(_on_opened)


func _fit() -> void:
	_fit_sheet()


func _on_open() -> void:
	_rebuild()


func _process(_delta: float) -> void:
	if visible and _dirty:
		_rebuild()


## 보유한 주머니 id(골드 먼저, 짧은 시간 먼저).
static func owned() -> Array:
	return Economy.pouch_ids().filter(func(id): return Economy.pouch_count(id) > 0)


func open_one(id: String) -> void:
	Economy.open_pouch(id, 1, GameState.stage)


func open_all(id: String) -> void:
	Economy.open_pouch(id, mini(Economy.pouch_count(id), 999), GameState.stage)


func _on_opened(o: Dictionary) -> void:
	var name := Economy.pouch_name(str(o.get("id", "")))
	var n := int(o.get("count", 1))
	Economy.notice.emit("%s%s: %s" % [name, (Lang.t("pouch_panel.on_opened") % n) if n > 1 else "", value_text(int(o.get("gold_tenths", 0)), o.get("res", {}))])


## "골드 +12,345" 또는 "목재 +300 · 석재 +150 · 식량 +300"(받을 것이 없으면 "받을 것이 없습니다").
static func value_text(gold_tenths: int, res: Dictionary) -> String:
	var parts: Array = []
	if gold_tenths > 0:
		parts.append(Lang.t("pouch_panel.value_text") + UiKit.commas(gold_tenths / 10))
	for k in [["wood", Lang.t("pouch_panel.value_text_2")], ["stone", Lang.t("pouch_panel.value_text_3")], ["food", Lang.t("pouch_panel.value_text_4")]]:
		if int(res.get(k[0], 0)) > 0:
			parts.append("%s +%s" % [k[1], UiKit.commas(int(res[k[0]]))])
	return " · ".join(parts) if not parts.is_empty() else Lang.t("pouch_panel.value_text_5")


func _rebuild() -> void:
	_dirty = false
	for k in buttons.keys():
		if k != "close":
			buttons.erase(k)
	for c in body.get_children():
		c.queue_free()
	var ids := owned()
	var sp := owned_speedups()
	empty_label.visible = ids.is_empty() and sp.is_empty()
	head_label.visible = not ids.is_empty()
	for id in ids:
		body.add_child(_row(id))
	if not sp.is_empty():
		body.add_child(_label(SPEEDUP_HEAD, 24, HudScript.INK))
		body.add_child(_label(SPEEDUP_HINT, 18, SUB))
		for id in sp:
			body.add_child(_speedup_row(id))


## 보유한 가속 아이템 id(Economy.speedup_ids 순서: 건설 → 연구 → 범용 → 고용권, 짧은 것부터).
static func owned_speedups() -> Array:
	return Economy.speedup_ids().filter(func(id): return Economy.speedup_count(id) > 0)


func _speedup_row(id: String) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.panel(ROW_BG, 12.0, 10))
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	card.add_child(r)
	var t := _label(Economy.speedup_name(id), 22, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(t)
	r.add_child(_label(Lang.t("pouch_panel.speedup_row") % Economy.speedup_count(id), 20, SUB, HORIZONTAL_ALIGNMENT_RIGHT))
	if str(Economy.speedup_parse(id).get("kind", "")) == "builder":
		var use := _button(Lang.t("pouch_panel.speedup_row_2"), UiKit.AMBER, 22)
		use.custom_minimum_size = Vector2(100, 56)
		use.disabled = Economy.speedup_waiting()
		use.pressed.connect(func(): Economy.use_speedup(id, 1))
		r.add_child(use)
		buttons["use:" + id] = use
	return card


func _row(id: String) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.panel(ROW_BG, 12.0, 10))
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	card.add_child(r)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var kind := str(Economy.pouch_parse(id).get("kind", "gold"))
	icon.draw.connect(func(): draw_pouch(icon, icon.size / 2.0, ICON_PX * 0.92, kind))
	r.add_child(icon)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	r.add_child(v)
	var name_row := HBoxContainer.new()
	var t := _label(Economy.pouch_name(id), 24, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.clip_text = true
	name_row.add_child(t)
	name_row.add_child(_label(Lang.t("pouch_panel.row") % Economy.pouch_count(id), 20, SUB, HORIZONTAL_ALIGNMENT_RIGHT))
	v.add_child(name_row)
	var val := Economy.pouch_value(id, GameState.stage)
	var empty := Economy.pouch_empty(id, GameState.stage)
	var vl := _label(EMPTY_VALUE_TEXT if empty else Lang.t("pouch_panel.row_2") + value_text(int(val.gold_tenths), val.res), 18, SUB if empty else VALUE, HORIZONTAL_ALIGNMENT_LEFT)
	vl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(vl)
	var wait := Economy.pouch_waiting()
	var one := _button(Lang.t("pouch_panel.row_3"), UiKit.AMBER, 22)
	one.custom_minimum_size = Vector2(100, 56)
	one.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	one.disabled = wait or empty
	one.pressed.connect(open_one.bind(id))
	r.add_child(one)
	buttons["open:" + id] = one
	Tutorial.register_ui("bag:open", one, func(): return not one.disabled)  # 가이드 「주머니 열기」 화살표
	if Economy.pouch_count(id) > 1:
		var all := _button(Lang.t("pouch_panel.row_4"), UiKit.STEEL, 22)
		all.custom_minimum_size = Vector2(90, 56)
		all.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		all.disabled = wait or empty
		all.pressed.connect(open_all.bind(id))
		r.add_child(all)
		buttons["all:" + id] = all
	return card


## 주머니 그림: 그린 그림(ShopArt pouch_gold·pouch_res — 상점과 같은 그림)이 있으면 그것(painted = false면 늘 벡터 — 오른쪽 아래 메뉴 [가방] 버튼).
## 벡터(로우폴리 자루): 각진 몸통 + 묶은 목 + 위로 벌어진 주둥이, 앞에 골드 동전(골드) 또는 목재(자원). 테두리는 자루 색의 진한 색.
static func draw_pouch(ci: CanvasItem, ctr: Vector2, s: float, kind: String, painted := true) -> void:
	if painted and ShopArt.draw(ci, "pouch_gold" if kind == "gold" else "pouch_res", ctr, s * 0.9):
		return
	var col := GOLD_SACK if kind == "gold" else RES_SACK
	var edge := LowpolyBox.edge_color(col)
	var w := maxf(1.0, s / 28.0)
	var body_pts := PackedVector2Array([ctr + Vector2(-s * 0.16, -s * 0.12), ctr + Vector2(s * 0.16, -s * 0.12), ctr + Vector2(s * 0.36, s * 0.06),
		ctr + Vector2(s * 0.40, s * 0.26), ctr + Vector2(s * 0.28, s * 0.42), ctr + Vector2(-s * 0.28, s * 0.42), ctr + Vector2(-s * 0.40, s * 0.26),
		ctr + Vector2(-s * 0.36, s * 0.06)])
	ci.draw_colored_polygon(body_pts, col)
	ci.draw_colored_polygon(PackedVector2Array([ctr + Vector2(-s * 0.16, -s * 0.12), ctr + Vector2(s * 0.16, -s * 0.12), ctr + Vector2(s * 0.36, s * 0.06),
		ctr + Vector2(-s * 0.36, s * 0.06)]), col.lightened(0.18))
	var loop := body_pts.duplicate()
	loop.append(body_pts[0])
	ci.draw_polyline(loop, edge, w, true)
	var mouth := PackedVector2Array([ctr + Vector2(-s * 0.12, -s * 0.2), ctr + Vector2(-s * 0.26, -s * 0.38), ctr + Vector2(-s * 0.08, -s * 0.32),
		ctr + Vector2(0, -s * 0.42), ctr + Vector2(s * 0.08, -s * 0.32), ctr + Vector2(s * 0.26, -s * 0.38), ctr + Vector2(s * 0.12, -s * 0.2)])
	ci.draw_colored_polygon(mouth, col.lightened(0.08))
	var mloop := mouth.duplicate()
	mloop.append(mouth[0])
	ci.draw_polyline(mloop, edge, w, true)
	var tie := Color(0.78, 0.26, 0.22)
	ci.draw_rect(Rect2(ctr + Vector2(-s * 0.19, -s * 0.2), Vector2(s * 0.38, s * 0.09)), tie)
	ci.draw_rect(Rect2(ctr + Vector2(-s * 0.19, -s * 0.2), Vector2(s * 0.38, s * 0.09)), LowpolyBox.edge_color(tie), false, w)
	IconsScript.draw_icon(ci, "gold" if kind == "gold" else "wood", ctr + Vector2(0, s * 0.18), s * 0.38)

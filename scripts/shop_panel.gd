extends "res://scripts/ui_window.gd"
## [상점] 시트(하단 탭 [상점], 2026-10-07 — 방치형 게임 상점처럼): 위에 보유 다이아·골드, 하위 탭 [일일][주간][다이아].
## 일일·주간 = 상품 카드 2열(그림·이름·내용·남은 횟수 + 가격 버튼). 누르면 곧바로 값이 빠지고 받은 것이 들어온다(Economy.buy_shop —
## 서버 확인은 뒤에서, 거절되면 되돌리고 알린다). 버튼은 기다리는 글자로 바뀌지 않는다. 다 산 상품은 "매진", 무료 선물이 남았으면 탭에 빨간 점.
## 다이아 = 충전 상품 4개(크기별 보석 더미·다이아 수·가격) — 결제 기능이 없어 [준비 중](눌리지 않는다)과 안내 문구.
## 모집 창의 "다이아가 부족합니다 → [이동]"은 이 시트를 [다이아] 탭으로 연다(open_tab).

const IconsScript := preload("res://scripts/icons.gd")
const GameData := preload("res://scripts/game_data.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const ShopItems := preload("res://scripts/shop_items.gd")
const PouchPanel := preload("res://scripts/pouch_panel.gd")
const DungeonPanel := preload("res://scripts/dungeon_panel.gd")
const SideMenu := preload("res://scripts/side_menu.gd")

const GROUP_SHOP := "shop_panel"
const TABS := [["daily", "일일"], ["weekly", "주간"], ["diamond", "다이아"]]
const HEAD := {"daily": "매일 00:00에 초기화", "weekly": "매주 월요일 00:00에 초기화", "diamond": "다이아 충전"}
const PACKS := [{"diamonds": 300, "price": 1200}, {"diamonds": 1000, "price": 3900}, {"diamonds": 3000, "price": 11000}, {"diamonds": 6500, "price": 22000}]
const SOON_TEXT := "준비 중"
const NOTE_TEXT := "결제 기능은 출시 전에 연결됩니다"
const SOLD_TEXT := "매진"
const FREE_TEXT := "무료"
const SHORT_TEXT := {"diamonds": "다이아가 부족합니다", "gold": "골드가 부족합니다"}
const PILE := [Vector2(0, 0), Vector2(-26, 14), Vector2(26, 14), Vector2(0, 26), Vector2(-14, -18), Vector2(14, -18)]  # 보석 더미 자리(가운데 기준)
const SUB := Color(0.16, 0.18, 0.24, 0.62)
const CARD_BG := Color(1, 1, 1, 0.78)
const FREE_BG := Color(0.99, 0.90, 0.62, 0.92)
const SOLD_BG := Color(0.86, 0.87, 0.89, 0.7)
const GIVE := Color(0.13, 0.50, 0.24)
const RED := Color(0.88, 0.22, 0.2)
const CLOSE_PX := 56.0
const CARD_W := 316.0

var tab := "daily"
var body: VBoxContainer
var head_label: Label
var wallet_label: Label
var buttons := {}  # 테스트용: "tab:daily" …, "buy:<id>", "pack:0" …, "close"
var buy_buttons: Array = []  # 다이아 탭 [준비 중] 버튼들
var note: Label

var _sig := ""
var _tick := 0.0


func _ready() -> void:
	_build_window(0, 10)
	add_to_group(GROUP_SHOP)
	dialog.get_parent().color = Color(0, 0, 0, 0)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()  # 제목 가운데 + 오른쪽 위 닫기(X)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(CLOSE_PX, 0)
	head.add_child(pad)
	var title := _title("상점")
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
	wallet_label = _label("", 22, HudScript.INK)
	content.add_child(wallet_label)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for t in TABS:
		var b := _button(t[1], UiKit.STEEL, 24)
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 54)
		b.pressed.connect(func(): _pick(t[0]))
		var dot := Control.new()  # 무료 선물이 남았으면 오른쪽 위 빨간 점
		dot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tid: String = t[0]
		dot.draw.connect(func():
			if Economy.shop_free_left(tid):
				var p := Vector2(dot.size.x - 12, 12)
				dot.draw_circle(p, 9.0, RED)
				dot.draw_arc(p, 9.0, 0, TAU, 16, RED.darkened(0.3), 1.5, true))
		b.add_child(dot)
		tabs.add_child(b)
		buttons["tab:" + t[0]] = b
	content.add_child(tabs)
	head_label = _label("", 20, SUB)
	content.add_child(head_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	_fit_sheet()
	Economy.changed.connect(_on_changed)
	Economy.shop_changed.connect(_on_changed)


func _fit() -> void:
	_fit_sheet()


func _on_open() -> void:
	_rebuild()


## 그 탭으로 연다(모집 창 "다이아가 부족합니다" [이동] → "diamond").
func open_tab(t: String) -> void:
	tab = t
	if is_open():
		_rebuild()
	else:
		open()


func _pick(t: String) -> void:
	tab = t
	_rebuild()


func _on_changed() -> void:
	if visible and _signature() != _sig:
		_rebuild()
	elif visible:
		_wallet()


func _process(delta: float) -> void:
	if not visible:
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 1.0
		_head()
		if _signature() != _sig:  # 리셋 시각이 지났다
			_rebuild()


func _head() -> void:
	if tab == "diamond":
		head_label.text = HEAD[tab]
		return
	var per := Economy.shop_period()
	var hour := GameData.config_num("daily_reset_utc_hour") * 3600.0
	var at: float = (int(per[0]) + 1) * 86400.0 + hour if tab == "daily" else ((int(per[1]) + 1) * 7 - 4) * 86400.0 + hour
	head_label.text = "%s · 남은 시간 %s" % [HEAD[tab], UiKit.duration(maxf(0.0, at - Economy.time_now()))]


func _wallet() -> void:
	wallet_label.text = "보유  다이아 %s  ·  골드 %s" % [UiKit.commas(Economy.diamonds), UiKit.commas(Economy.gold)]


## 보이는 카드의 상태(남은 횟수·살 수 있는지) — 같으면 카드를 다시 만들지 않는다(누르는 도중 버튼이 바뀌지 않게).
func _signature() -> String:
	var parts := [tab]
	for x in ShopItems.of_tab(tab):
		parts.append("%s:%d:%s" % [x.id, Economy.shop_left(x.id), Economy.shop_block(x.id)])
	return "|".join(parts)


func _rebuild() -> void:
	_sig = _signature()
	for k in buttons:
		if k.begins_with("tab:"):
			UiKit.apply_button(buttons[k], UiKit.AMBER if k == "tab:" + tab else UiKit.STEEL, 14.0)
			buttons[k].get_child(0).queue_redraw()
	for k in buttons.keys():
		if k.begins_with("buy:") or k.begins_with("pack:"):
			buttons.erase(k)
	buy_buttons = []
	note = null
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	_head()
	_wallet()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(grid)
	if tab == "diamond":
		for i in PACKS.size():
			grid.add_child(_pack_card(PACKS[i], i))
		note = _label(NOTE_TEXT, 22, Color(HudScript.INK, 0.75))
		body.add_child(note)
		return
	var rows := ShopItems.of_tab(tab)
	var key := {}  # 살 수 있는 것 → 매진, 같은 상태는 표 순서
	for i in rows.size():
		key[rows[i].id] = (1 if Economy.shop_left(rows[i].id) <= 0 else 0) * 1000 + i
	rows.sort_custom(func(a, b): return key[a.id] < key[b.id])
	for x in rows:
		grid.add_child(_card(x))


func _card(x: Dictionary) -> Control:
	var left := Economy.shop_left(x.id)
	var sold := left <= 0
	var free: bool = x.currency == "free"
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UiKit.panel(SOLD_BG if sold else (FREE_BG if free else CARD_BG), 12.0, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var name := _label(x.name, 24, HudScript.INK if not sold else SUB)
	name.clip_text = true
	v.add_child(name)
	var pic := Control.new()
	pic.custom_minimum_size = Vector2(0, 84)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.modulate = Color(1, 1, 1, 0.5) if sold else Color.WHITE
	var icon: String = x.icon
	pic.draw.connect(func(): draw_item_icon(pic, icon, pic.size / 2.0, 70.0))
	v.add_child(pic)
	var give := _label(Missions.reward_text(x.give), 18, GIVE if not sold else SUB)
	give.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	give.custom_minimum_size = Vector2(CARD_W - 24, 0)
	v.add_child(give)
	v.add_child(_label("%s %d/%d" % ["오늘" if x.tab == "daily" else "이번 주", left, int(x.limit)], 18, SUB))
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 58)
	var block := Economy.shop_block(x.id)
	var col: Color = UiKit.STEEL if sold else (UiKit.AMBER if free else (HudScript.ACCENT if block == "" else UiKit.STEEL))
	UiKit.apply_button(b, col, 12.0)
	b.disabled = sold
	var cur: String = x.currency
	var price := int(x.price)
	var face := Control.new()  # 재화 그림 + 가격(무료·매진은 글자만)
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.draw.connect(func(): _draw_price(face, cur, price, sold))
	b.add_child(face)
	b.pressed.connect(_buy.bind(x.id))
	v.add_child(b)
	buttons["buy:" + x.id] = b
	return card


func _draw_price(c: Control, cur: String, price: int, sold: bool) -> void:
	var font := c.get_theme_default_font()
	var text := SOLD_TEXT if sold else (FREE_TEXT if cur == "free" else UiKit.commas(price))
	var fs := 26
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var icon_w := 0.0 if sold or cur == "free" else 34.0
	var x0 := (c.size.x - tw - icon_w) / 2.0
	if icon_w > 0.0:
		IconsScript.draw_icon(c, "diamond" if cur == "diamonds" else "gold", Vector2(x0 + 14.0, c.size.y / 2.0), 28.0)
	var base := Vector2(x0 + icon_w, c.size.y / 2.0 + fs * 0.36)
	var short := not sold and ((cur == "diamonds" and Economy.diamonds < price) or (cur == "gold" and Economy.gold < price))
	c.draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(UiKit.INK, 0.85))
	c.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.62, 0.58) if short else Color.WHITE)


func _buy(id: String) -> void:
	var block := Economy.shop_block(id)
	if block in SHORT_TEXT:
		Economy.notice.emit(SHORT_TEXT[block])
		return
	var x := ShopItems.find(id)
	if Economy.buy_shop(id):
		Economy.notice.emit("구매: " + Missions.reward_text(x.give))


func _pack_card(p: Dictionary, i: int) -> Control:
	var gems := i + 2  # 상품이 클수록 보석이 많다(2..5개)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM, 12.0, 12))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var pile := Control.new()
	pile.custom_minimum_size = Vector2(0, 96)
	pile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pile.draw.connect(func():
		var c := pile.size / 2.0
		for j in range(gems - 1, -1, -1):  # 뒤에서 앞으로(가운데 보석이 맨 앞)
			IconsScript.draw_icon(pile, "diamond", c + PILE[j], 44.0 - j * 2.0))
	box.add_child(pile)
	box.add_child(_label("다이아 %s" % UiKit.commas(p.diamonds), 30))
	box.add_child(_label("%s원" % UiKit.commas(p.price), 24, Color(HudScript.INK, 0.8)))
	var buy := _button(SOON_TEXT, HudScript.ACCENT, 24)
	buy.disabled = true
	box.add_child(buy)
	buy_buttons.append(buy)
	buttons["pack:%d" % i] = buy
	return card


## 상품 그림: gift(선물 상자)·ticket(모집권)·pouch_gold·pouch_res(주머니)·key(던전 입장권)·res_pile(자원 더미).
static func draw_item_icon(ci: Control, icon: String, ctr: Vector2, s: float) -> void:
	match icon:
		"gift":
			SideMenu.draw_gift(ci, ctr, s)
		"pouch_gold":
			PouchPanel.draw_pouch(ci, ctr, s, "gold")
		"pouch_res":
			PouchPanel.draw_pouch(ci, ctr, s, "res")
		"key":
			_draw_key_at(ci, ctr, s)
		"res_pile":
			IconsScript.draw_icon(ci, "wood", ctr + Vector2(-s * 0.28, s * 0.1), s * 0.55)
			IconsScript.draw_icon(ci, "stone", ctr + Vector2(s * 0.28, s * 0.1), s * 0.55)
			IconsScript.draw_icon(ci, "food", ctr + Vector2(0, -s * 0.18), s * 0.55)
		_:
			IconsScript.draw_icon(ci, icon, ctr, s)


## 열쇠(던전 시트 draw_key와 같은 모양): 고리 + 자루 + 이 둘.
static func _draw_key_at(c: CanvasItem, o: Vector2, s: float) -> void:
	var gold: Color = DungeonPanel.KEY_GOLD
	var ring := o + Vector2(-s * 0.22, 0)
	c.draw_circle(ring, s * 0.24, UiKit.INK)
	c.draw_circle(ring, s * 0.19, gold)
	c.draw_circle(ring, s * 0.08, UiKit.INK)
	c.draw_rect(Rect2(o + Vector2(-s * 0.02, -s * 0.07), Vector2(s * 0.5, s * 0.14)), gold)
	for x in [0.3, 0.42]:
		c.draw_rect(Rect2(o + Vector2(s * x - s * 0.05, s * 0.05), Vector2(s * 0.08, s * 0.14)), gold)

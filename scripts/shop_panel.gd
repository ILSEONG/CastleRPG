extends "res://scripts/ui_window.gd"
## [상점] 시트(하단 탭 [상점], 2026-10-07 — 방치형 게임 정석 BM, BM 총괄 Claude): 위에 보유 다이아·골드, 하위 탭(TABS — 다른 창이 탭을 더할 수 있다)
## [패키지][패스][일일][주간][PVP][다이아].
## - 패키지 = 월정액 2종(사면 즉시 다이아 + 30일 매일 [오늘 받기]) + 신규 스타터·일일·주간 특가·성장 지원 패키지(실결제, 기간 한도).
## - 패스 = 성장 패스: 라운드를 깰 때마다 무료 보상(누구나) + 유료 보상(패스 구매자), 단계마다 [받기].
## - 일일·주간 = 다이아로 사는 한정 상품 카드 2열 + 무료 선물(Economy.buy_shop — 누르는 즉시, 서버 확인은 뒤에서, 거절되면 되돌림).
## - 다이아 = 충전 6단계(첫 구매 2배 띠, 이후 보너스).
## 실결제 버튼(₩ 가격)은 Google Play 연결 전이라 누르면 알림만(Economy.iap_buy). 버튼은 기다리는 글자로 바뀌지 않는다.
## 받을 것(무료 선물·월정액 오늘 보상·성장 패스)이 있는 탭에 빨간 점. 모집 창의 "다이아가 부족합니다 → [이동]"은 [다이아] 탭으로 연다(open_tab).
## [PVP] 탭(2026-10-07, PVP 스레드): PVP 코인 상품(PvpRules.SHOP — 서버 pvp.ts SHOP과 같다). 사기는 Pvp.buy(코인·구매 수 곧바로, 거절되면 되돌리고 알림).
## PVP 화면의 [상점]도 이 탭으로 연다(pvp_view.open_shop).
## 그림(디자인 보강 6번): 상품·패키지·다이아 충전·PVP 상품 그림은 Meshy로 그린 아이콘(shop_art.gd), 파일이 없으면 예전 벡터 그림.
const PVP_NOTE := "PVP 코인은 결투·총력전에서 얻어요 (승리 %d · 패배 %d)"

const IconsScript := preload("res://scripts/icons.gd")
const GameData := preload("res://scripts/game_data.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const ShopItems := preload("res://scripts/shop_items.gd")
const IapItems := preload("res://scripts/iap_items.gd")
const PouchPanel := preload("res://scripts/pouch_panel.gd")
const DungeonPanel := preload("res://scripts/dungeon_panel.gd")
const SideMenu := preload("res://scripts/side_menu.gd")
const PvpRules := preload("res://scripts/pvp_rules.gd")
const PvpView := preload("res://scripts/pvp_view.gd")
const ShopArt := preload("res://scripts/shop_art.gd")

const GROUP_SHOP := "shop_panel"
const TABS := [["package", "패키지"], ["pass", "패스"], ["daily", "일일"], ["weekly", "주간"], ["pvp", "PVP"], ["diamond", "다이아"]]
const HEAD := {"package": "월정액·특가 패키지", "pass": "라운드를 깰 때마다 보상 · 패스를 사면 유료 보상도", "daily": "매일 00:00에 초기화",
	"weekly": "매주 월요일 00:00에 초기화", "diamond": "단계마다 첫 구매는 다이아 2배",
	"pvp": "PVP 코인 상점 · 일일 상품은 매일, 주간 상품은 월요일 00:00에 초기화"}
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

var tab := "package"
var body: VBoxContainer
var head_label: Label
var wallet_label: Label
var buttons := {}  # 테스트용: "tab:daily" …, "buy:<id>", "iap:<상품 id>", "monthly:<id>", "growth:<단계>:<free|paid>", "close"
var buy_buttons: Array = []  # 다이아 탭 충전 버튼들
var note: Label
var hot_label: Label  # [패키지] 탭 맨 위 핫딜 카드의 남은 시간(1초마다)
const HOT_BG := Color(1.0, 0.82, 0.74, 0.95)

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
			if tab_dot(tid):
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
	Pvp.changed.connect(_on_changed)


## 그 탭에 받을 것이 있다(빨간 점).
static func tab_dot(t: String) -> bool:
	if t == "daily" or t == "weekly":
		return Economy.shop_free_left(t)
	return Economy.iap_claim_left(cleared()).has(t)


## 깬 마지막 라운드(성장 패스).
static func cleared() -> int:
	return maxi(GameState.stage, Economy.server_stage) - 1


func _fit() -> void:
	_fit_sheet()


func _on_open() -> void:
	_rebuild()


## 그 탭으로 연다(모집 창 "다이아가 부족합니다" [이동] → "diamond").
func open_tab(t: String) -> void:
	tab = t
	if t == "pvp":
		Pvp.fetch_if_stale()
	if is_open():
		_rebuild()
	else:
		open()


func _pick(t: String) -> void:
	tab = t
	if t == "pvp":
		Pvp.fetch_if_stale()
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


func _hot_time() -> void:
	if hot_label != null and is_instance_valid(hot_label):
		hot_label.text = "남은 시간 " + UiKit.duration(maxf(0.0, float(Economy.active_hot().get("until", 0.0)) - Economy.time_now()))


func _head() -> void:
	_hot_time()
	if not tab in ["daily", "weekly"]:
		head_label.text = HEAD.get(tab, "")
		return
	var per := Economy.shop_period()
	var hour := GameData.config_num("daily_reset_utc_hour") * 3600.0
	var at: float = (int(per[0]) + 1) * 86400.0 + hour if tab == "daily" else ((int(per[1]) + 1) * 7 - 4) * 86400.0 + hour
	head_label.text = "%s · 남은 시간 %s" % [HEAD[tab], UiKit.duration(maxf(0.0, at - Economy.time_now()))]


func _wallet() -> void:
	if tab == "pvp":
		wallet_label.text = "보유  PVP 코인 %s" % UiKit.commas(Pvp.coins())
		return
	wallet_label.text = "보유  다이아 %s  ·  골드 %s" % [UiKit.commas(Economy.diamonds), UiKit.commas(Economy.gold)]


## 보이는 카드의 상태(남은 횟수·살 수 있는지) — 같으면 카드를 다시 만들지 않는다(누르는 도중 버튼이 바뀌지 않게).
func _signature() -> String:
	var parts := [tab, str(Economy.iap_view()), cleared(), Economy.diamonds >= 0, str(Economy.active_hot().get("id", ""))]
	if tab == "pvp":
		parts.append(str(Pvp.coins()))
		for x in PvpRules.SHOP:
			parts.append("%s:%d:%s" % [x.id, int(Pvp.shop_item(x.id).get("bought", 0)), Pvp.buy_block(x.id)])
		return "|".join(parts)
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
		if not k.begins_with("tab:") and k != "close":
			buttons.erase(k)
	buy_buttons = []
	note = null
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	_head()
	_wallet()
	match tab:
		"package":
			_build_packages()
			return
		"pass":
			_build_pass()
			return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(grid)
	if tab == "diamond":
		var packs := IapItems.of_kind("diamond")
		for i in packs.size():
			grid.add_child(_pack_card(packs[i], i))
		note = _label(NOTE_TEXT, 20, Color(HudScript.INK, 0.75))
		body.add_child(note)
		return
	if tab == "pvp":
		for x in PvpRules.SHOP:
			grid.add_child(_pvp_card(x))
		note = _label(PVP_NOTE % [PvpRules.COINS_WIN, PvpRules.COINS_LOSS], 22, Color(HudScript.INK, 0.75))
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


## PVP 상품 카드(_card와 같은 모양, 가격 = PVP 코인).
func _pvp_card(x: Dictionary) -> Control:
	var id: String = x.id
	var left := maxi(0, int(x.limit) - int(Pvp.shop_item(id).get("bought", 0)))
	var sold := left <= 0
	var block := Pvp.buy_block(id)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UiKit.panel(SOLD_BG if sold else CARD_BG, 12.0, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var name := _label(PvpRules.SHOP_NAMES.get(id, id), 24, HudScript.INK if not sold else SUB)
	name.clip_text = true
	v.add_child(name)
	var pic := Control.new()
	pic.custom_minimum_size = Vector2(0, 84)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.modulate = Color(1, 1, 1, 0.5) if sold else Color.WHITE
	pic.draw.connect(func(): draw_pvp_item(pic, id, pic.size / 2.0, 70.0))
	v.add_child(pic)
	v.add_child(_label("%s %d/%d" % ["오늘" if x.period == "day" else "이번 주", left, int(x.limit)], 18, SUB))
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 58)
	UiKit.apply_button(b, UiKit.STEEL if sold or block != "" else HudScript.ACCENT, 12.0)
	b.disabled = sold
	var price := int(x.price)
	var face := Control.new()
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.draw.connect(func():
		var font := face.get_theme_default_font()
		var text := SOLD_TEXT if sold else UiKit.commas(price)
		var fs := 26
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var icon_w := 0.0 if sold else 34.0
		var x0 := (face.size.x - tw - icon_w) / 2.0
		if icon_w > 0.0:
			PvpView.draw_coin_at(face, Vector2(x0 + 14.0, face.size.y / 2.0), 28.0)
		var base := Vector2(x0 + icon_w, face.size.y / 2.0 + fs * 0.36)
		face.draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(UiKit.INK, 0.85))
		face.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.62, 0.58) if not sold and Pvp.coins() < price else Color.WHITE))
	b.add_child(face)
	b.pressed.connect(func():
		if Pvp.buy(id) == "":
			Economy.notice.emit("구매: " + str(PvpRules.SHOP_NAMES.get(id, id))))
	v.add_child(b)
	buttons["buy:pvp_" + id] = b
	return card


## PVP 상품 그림: 골드는 자원 아이콘, 다이아·모집권·장비 상자는 그린 그림(ShopArt, 없으면 벡터), 조각 = 보라(SSR은 금색) 보석 조각.
static func draw_pvp_item(c: CanvasItem, id: String, ctr: Vector2, s: float) -> void:
	var o := ctr - Vector2(s, s) / 2.0
	if ShopArt.draw(c, {"dia": "dia_2", "ticket": "ticket", "equip": "chest_equip"}.get(id, ""), ctr, s):
		return
	match id:
		"gold":
			IconsScript.draw_icon(c, "gold", ctr, s)
		"dia":
			IconsScript.draw_icon(c, "diamond", ctr, s)
		"ticket":
			draw_item_icon(c, "ticket", ctr, s)
		"equip":
			c.draw_rect(Rect2(o + Vector2(s * 0.1, s * 0.3), Vector2(s * 0.8, s * 0.58)), Color("9B6B3E"))
			c.draw_rect(Rect2(o + Vector2(s * 0.1, s * 0.3), Vector2(s * 0.8, s * 0.18)), Color("B98250"))
			c.draw_rect(Rect2(o + Vector2(s * 0.44, s * 0.4), Vector2(s * 0.12, s * 0.16)), Color("E2B23A"))
			c.draw_rect(Rect2(o + Vector2(s * 0.1, s * 0.3), Vector2(s * 0.8, s * 0.58)), Color("5E3F22"), false, 2.0)
		_:
			var col := Color("E2B23A") if id == "ssr" else Color("A86BE0")
			for k in 3:
				UiKit.draw_gem(c, o + Vector2(s * (0.3 + 0.2 * k), s * (0.6 - 0.12 * (k % 2))), s * 0.17, col, 5)


func _pack_card(p: Dictionary, i: int) -> Control:
	var gems := mini(i + 1, PILE.size())  # 상품이 클수록 보석이 많다(1..6개)
	var first := Economy.iap_first_bonus(p.id)
	var base := int(p.give.diamonds)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM, 12.0, 12))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var pile := Control.new()
	pile.custom_minimum_size = Vector2(0, 92)
	pile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pile.draw.connect(func():
		var c := pile.size / 2.0
		if not ShopArt.draw(pile, "dia_%d" % gems, c, 80.0):  # 그린 다이아 더미(1개 → 금 상자)
			for j in range(gems - 1, -1, -1):  # 뒤에서 앞으로(가운데 보석이 맨 앞)
				IconsScript.draw_icon(pile, "diamond", c + PILE[j], 44.0 - j * 2.0)
		if first:  # 첫 구매 2배 띠(왼쪽 위)
			_ribbon(pile, "첫 구매 2배"))
	box.add_child(pile)
	box.add_child(_label("다이아 %s" % UiKit.commas(base), 30))
	var extra := base if first else int(p.get("bonus", 0))
	box.add_child(_label(("+%s 보너스" % UiKit.commas(extra)) if extra > 0 else " ", 20, RED if first else GIVE))
	var buy := _krw_button(p.id, int(p.krw))
	box.add_child(buy)
	buy_buttons.append(buy)
	return card


## 실결제 가격 버튼(₩). 누르면 Economy.iap_buy(연결 전이면 알림).
func _krw_button(id: String, krw: int, text := "") -> Button:
	var b := _button(text if text != "" else "₩" + UiKit.commas(krw), HudScript.ACCENT, 24)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 56)
	b.pressed.connect(func(): Economy.iap_buy(id))
	buttons["iap:" + id] = b
	return b


func _ribbon(c: Control, text: String) -> void:
	var font := c.get_theme_default_font()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 18.0
	var pts := PackedVector2Array([Vector2(0, 4), Vector2(w, 4), Vector2(w - 8, 17), Vector2(w, 30), Vector2(0, 30)])
	c.draw_colored_polygon(pts, RED)
	pts.append(pts[0])
	c.draw_polyline(pts, RED.darkened(0.3), 1.5, true)
	c.draw_string(font, Vector2(6, 24), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)


## 가로 카드(그림 · 이름/내용/상태 · 오른쪽 버튼들).
func _wide(icon: String, title: String, lines: Array, side: Array, bg := CARD_BG) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.panel(bg, 12.0, 10))
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	card.add_child(r)
	var pic := Control.new()
	pic.custom_minimum_size = Vector2(84, 84)
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.draw.connect(func(): draw_item_icon(pic, icon, pic.size / 2.0, 66.0))
	r.add_child(pic)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	r.add_child(v)
	v.add_child(_label(title, 24, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	for ln in lines:
		var l := _label(str(ln[0]), 18, ln[1], HORIZONTAL_ALIGNMENT_LEFT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(150, 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	r.add_child(col)
	for c in side:
		col.add_child(c)
	return card


func _build_packages() -> void:
	hot_label = null
	var h := Economy.active_hot()
	if not h.is_empty():  # 떠 있는 핫딜(1시간 한정)이 맨 위
		var hp := IapItems.find(str(h.id))
		var card := _wide(ShopArt.HOT_ICON, "핫딜 · " + str(hp.name), [[Missions.reward_text(hp.give), GIVE], ["가치 %d배" % int(hp.get("value", 1)), RED]],
			[_krw_button(hp.id, int(hp.krw))], HOT_BG)
		hot_label = _label("", 20, RED, HORIZONTAL_ALIGNMENT_LEFT)
		var v: VBoxContainer = card.get_child(0).get_child(1)
		v.add_child(hot_label)
		body.add_child(card)
		_hot_time()
	for p in IapItems.of_kind("monthly"):
		var left := Economy.monthly_left(p.id)
		var lines := [["구매 즉시 " + Missions.reward_text(p.give), GIVE], ["%d일간 매일 %s" % [int(p.days), Missions.reward_text(p.daily)], GIVE]]
		lines.append(["남은 기간 %d일" % left if left > 0 else "총 %s 이상의 가치" % _value_text(p), SUB])
		var side := []
		if left > 0:
			if Economy.can_claim_monthly(p.id):
				var c := _button("오늘 받기", UiKit.AMBER, 22)
				c.focus_mode = Control.FOCUS_NONE
				c.pressed.connect(func(): Economy.claim_monthly(p.id))
				buttons["monthly:" + p.id] = c
				side.append(c)
			else:
				side.append(_label("오늘 받음", 20, SUB))
		if Economy.iap_can_buy(p.id):
			side.append(_krw_button(p.id, int(p.krw), ("연장 ₩" if left > 0 else "₩") + UiKit.commas(int(p.krw))))
		body.add_child(_wide(str(ShopArt.PACK_ICONS.get(p.id, "crown")), p.name, lines, side, FREE_BG if left > 0 else CARD_BG))
	for p in IapItems.of_kind("package"):
		var ok := Economy.iap_can_buy(p.id)
		if p.period == "once" and not ok:
			continue  # 평생 1회 상품은 산 뒤 숨긴다
		var limit: String = {"once": "계정당 1회", "daily": "매일 1회", "weekly": "매주 1회"}.get(p.period, "")
		var side := [_krw_button(p.id, int(p.krw))] if ok else [_label(SOLD_TEXT, 22, SUB)]
		body.add_child(_wide(str(ShopArt.PACK_ICONS.get(p.id, "ticket" if p.give.has("tickets") else "diamond")), p.name, [[Missions.reward_text(p.give), GIVE], [limit, SUB]], side,
			CARD_BG if ok else SOLD_BG))
	note = _label(NOTE_TEXT, 20, Color(HudScript.INK, 0.75))
	body.add_child(note)


## 대략의 다이아 가치(모집권 1장 = 다이아 모집 1회 비용).
func _value_text(p: Dictionary) -> String:
	var per_ticket := int(GameData.config_num("gacha_dia_cost_1"))
	var dia := int(p.give.get("diamonds", 0))
	var d: Dictionary = p.get("daily", {})
	dia += int(p.days) * (int(d.get("diamonds", 0)) + int(d.get("tickets", 0)) * per_ticket)
	return "다이아 %s" % UiKit.commas(dia)


func _build_pass() -> void:
	var owned := Economy.has_pass("pass_growth")
	var p := IapItems.find("pass_growth")
	var side := [_label("구매함", 22, GIVE)] if owned else [_krw_button(p.id, int(p.krw))]
	body.add_child(_wide("crown", "성장 패스", [["라운드를 깰 때마다 무료 보상, 패스가 있으면 유료 보상도 받아요", SUB],
		["산 뒤에는 지난 단계 유료 보상도 받을 수 있어요", SUB]], side, FREE_BG if owned else CARD_BG))
	var c := cleared()
	for i in IapItems.GROWTH.size():
		var t: Dictionary = IapItems.GROWTH[i]
		var card := PanelContainer.new()
		var reached := c >= int(t.round)
		card.add_theme_stylebox_override("panel", UiKit.panel(CARD_BG if reached else SOLD_BG, 10.0, 8))
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		card.add_child(r)
		var lab := _label(GameData.round_label(int(t.round)), 26, HudScript.INK if reached else SUB)
		lab.custom_minimum_size = Vector2(96, 0)
		r.add_child(lab)
		for track in ["free", "paid"]:
			r.add_child(_growth_cell(i, track, t[track], owned))
		body.add_child(card)


func _growth_cell(i: int, track: String, reward: Dictionary, owned: bool) -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	v.add_child(_label(("무료 · " if track == "free" else "패스 · ") + Missions.reward_text(reward), 17, GIVE if track == "free" else Color(0.55, 0.30, 0.70)))
	var done: bool = Economy.iap_view().gp[track].has(i) or Economy.iap_view().gp[track].has(float(i))
	if done:
		v.add_child(_label("받음", 20, SUB))
	elif Economy.can_claim_growth(i, track, cleared()):
		var b := _button("받기", UiKit.AMBER, 20)
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 44)
		b.pressed.connect(func(): Economy.claim_growth(i, track, cleared()))
		buttons["growth:%d:%s" % [i, track]] = b
		v.add_child(b)
	else:
		v.add_child(_label("패스 필요" if track == "paid" and not owned else "잠김", 18, SUB))
	return v


## 상품 그림: 그린 그림(ShopArt — dia_1~6·gift·gift_big·crown·ticket·tickets·chest_equip·key_*·pouch_*·res_pile)이 있으면 그것,
## 없으면 벡터: gift(선물 상자)·ticket(모집권)·pouch_gold·pouch_res(주머니)·key(던전 입장권)·crown·res_pile(자원 더미)·자원 아이콘.
static func draw_item_icon(ci: Control, icon: String, ctr: Vector2, s: float) -> void:
	if ShopArt.draw(ci, icon, ctr, s):
		return
	if icon.begins_with("key_"):
		icon = "key"
	elif icon.begins_with("dia_"):
		icon = "diamond"
	icon = {"gift_big": "gift", "tickets": "ticket", "chest_equip": "gift"}.get(icon, icon)
	match icon:
		"gift":
			SideMenu.draw_gift(ci, ctr, s)
		"pouch_gold":
			PouchPanel.draw_pouch(ci, ctr, s, "gold")
		"pouch_res":
			PouchPanel.draw_pouch(ci, ctr, s, "res")
		"key":
			_draw_key_at(ci, ctr, s)
		"crown":  # 왕관(월정액·패스)
			var u := s / 70.0
			var pts := PackedVector2Array([ctr + Vector2(-28, 16) * u, ctr + Vector2(-30, -14) * u, ctr + Vector2(-14, 0) * u, ctr + Vector2(0, -22) * u,
				ctr + Vector2(14, 0) * u, ctr + Vector2(30, -14) * u, ctr + Vector2(28, 16) * u])
			ci.draw_colored_polygon(pts, Color(0.98, 0.78, 0.22))
			ci.draw_colored_polygon(PackedVector2Array([ctr + Vector2(-28, 16) * u, ctr + Vector2(28, 16) * u, ctr + Vector2(28, 24) * u, ctr + Vector2(-28, 24) * u]),
				Color(0.86, 0.60, 0.14))
			pts.append(pts[0])
			ci.draw_polyline(pts, Color(0.70, 0.48, 0.10), 2.0 * u, true)
			for g in [[Vector2(0, 4), Color(0.86, 0.22, 0.24)], [Vector2(-16, 8), Color(0.30, 0.60, 0.92)], [Vector2(16, 8), Color(0.30, 0.60, 0.92)]]:
				ci.draw_circle(ctr + g[0] * u, 4.5 * u, g[1])
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

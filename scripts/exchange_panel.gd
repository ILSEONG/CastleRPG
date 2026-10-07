extends "res://scripts/ui_window.gd"
## [거래소] 시트(2026-10-07, 오른쪽 아래 메뉴 [거래소], 서버 market.ts): 내 장비를 골드나 다이아로 올리고 다른 플레이어의 장비를 산다.
## 정산 수수료 10%: 산 사람은 올린 값을 내고, 판 사람은 90%(내림)를 받는다. 판매는 48시간(지나면 장비가 보관함으로 돌아온다), 동시에 10개까지.
## 탭 [구매][판매 등록][내 판매]:
## - 구매: 통화(골드·다이아)·부위·등급·정렬(낮은 가격·높은 가격·최신) 순환 버튼 + 남의 판매 줄(장비 칸·이름·능력치 = 보관함과 같은 글자,
##   판매자·남은 시간, 값, [구매]). [구매] → 확인 창 → 서버가 정한다(버튼은 그대로, 결과가 오면 알림 — 이미 팔렸으면 "이미 팔린 장비예요").
## - 판매 등록: 장착하지 않은 보관함 장비 줄을 눌러 고르고, 아래에서 통화·값을 정해 [등록](누르는 즉시 보관함에서 빠지고 내 판매에 들어간다 —
##   서버가 거절하면 되돌리고 알림). 받는 금액(수수료 뺀 값)을 바로 보여 준다.
## - 내 판매: 판매 중(남은 시간, [내리기] — 즉시 보관함으로) · 판매 완료(받을 금액). 위에 [대금 받기](즉시 반영). 받을 대금이 있으면 탭·메뉴에 빨간 점.
## 온라인 전용(오프라인이면 안내 글). 버튼은 기다리는 글자로 바뀌지 않는다.

const GameData := preload("res://scripts/game_data.gd")
const Art := preload("res://scripts/art.gd")
const BagPanel := preload("res://scripts/bag_panel.gd")
const ItemTileScript := preload("res://scripts/item_tile.gd")

const TABS := [["buy", "구매"], ["sell", "판매 등록"], ["mine", "내 판매"]]
const CUR_NAMES := {"gold": "골드", "diamonds": "다이아"}
const SORTS := [["cheap", "낮은 가격"], ["dear", "높은 가격"], ["new", "최신"]]
const FEE_PCT := 10  # 서버 market.ts FEE_PCT와 같다
const MAX_ACTIVE := 10
const PRICE_LIMITS := {"gold": [100, 1000000000], "diamonds": [10, 100000]}
const FAIL_TEXT := {
	"sold_out": "이미 팔린 장비예요", "own_listing": "내 판매는 살 수 없어요", "price_changed": "값이 바뀌었어요 — 목록을 새로 받았어요",
	"bag_full": "보관함이 가득 찼어요", "not_enough_gold": "골드가 부족해요", "not_enough_diamonds": "다이아가 부족해요",
	"too_many_listings": "판매는 동시에 10개까지예요", "equipped": "장착 중인 장비는 올릴 수 없어요",
	"unknown_item": "보관함에 없는 장비예요", "bad_price": "값을 다시 정해 주세요", "already_sold": "이미 팔렸어요 — 대금을 받으세요",
	"not_active": "이미 끝난 판매예요", "nothing_to_collect": "받을 대금이 없어요",
}
const FAIL_DEFAULT := "거래소 응답을 받지 못했어요 — 다시 확인할게요"
const OFFLINE_TEXT := "거래소는 온라인에서 이용할 수 있어요"
const SUB := Color(0.16, 0.18, 0.24, 0.62)
const GOOD := Color(0.13, 0.50, 0.24)
const RED := Color(0.88, 0.22, 0.2)
const ROW_BG := Color(1, 1, 1, 0.78)
const PICK_BG := Color(0.99, 0.90, 0.62, 0.95)
const TILE_PX := 72.0
const CLOSE_PX := 56.0

var tab := "buy"
var currency := "gold"  # 구매 탭 통화
var slot_filter := ""
var grade_filter := ""
var sort_mode := "cheap"
var listings: Array = []  # 구매 탭: 마지막으로 받은 남의 판매
var picked := 0  # 판매 등록: 고른 장비 id(0 = 없음)
var sell_currency := "gold"
var buttons := {}  # 테스트용: "tab:buy" …, "buy:<id>", "cancel:<id>", "collect", "list", "pick:<item id>", "cur:gold", "close"
var price_edit: LineEdit
var wallet_label: Label
var head_label: Label
var body: VBoxContainer
var footer: VBoxContainer
var confirm: PanelContainer

var _confirm_label: Label
var _confirm_ok: Button
var _confirm_listing := {}
var _tick := 0.0
var _fetch_n := 0  # 마지막으로 보낸 목록 요청 번호(늦게 온 옛 응답은 버린다)


func _ready() -> void:
	_build_window(0, 10)
	layer = 4
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(CLOSE_PX, 0)
	head.add_child(pad)
	var title := _title("거래소")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var x := Button.new()  # 다른 창(상점·랭킹)과 같은 ✕ 그림 버튼
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
		var tid: String = t[0]
		b.pressed.connect(func(): pick_tab(tid))
		var dot := Control.new()
		dot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.draw.connect(func():
			if tid == "mine" and Economy.market_sold > 0:
				var p := Vector2(dot.size.x - 12, 12)
				dot.draw_circle(p, 9.0, RED)
				dot.draw_arc(p, 9.0, 0, TAU, 16, RED.darkened(0.3), 1.5, true))
		b.add_child(dot)
		tabs.add_child(b)
		buttons["tab:" + tid] = b
	content.add_child(tabs)
	head_label = _label("", 20, SUB)
	head_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(head_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	footer = VBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	content.add_child(footer)
	_build_confirm()
	_fit_sheet()
	Economy.changed.connect(_on_state)
	Economy.items_changed.connect(_on_state)
	Economy.market_changed.connect(_on_state)


func _fit() -> void:
	_fit_sheet()


func _on_open() -> void:
	confirm.visible = false
	refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_tick += delta
	if _tick >= 1.0:  # 남은 시간 글자
		_tick = 0.0
		for n in get_tree().get_nodes_in_group("exchange_left"):
			if is_instance_valid(n) and n.has_meta("expires"):
				n.text = str(n.get_meta("prefix", "")) + left_text(float(n.get_meta("expires")))


func pick_tab(t: String) -> void:
	tab = t
	confirm.visible = false
	refresh()


## 서버에서 새로 받고 그린다(구매 = 목록, 내 판매 = 내 판매). 판매 등록은 보관함·내 판매 수만 쓴다.
func refresh() -> void:
	_rebuild()
	if not online():
		return
	if tab == "buy":
		fetch_listings()
	else:
		fetch_mine()


static func online() -> bool:
	return Economy.net != null


func fetch_listings() -> void:
	_fetch_n += 1
	var n := _fetch_n
	var q := "/v1/market?currency=%s&sort=%s&slot=%s&grade=%s" % [currency, sort_mode, slot_filter, grade_filter]
	Economy.net.send("GET", q, null, func(d: Dictionary):
		if n == _fetch_n and d.get("listings") is Array:
			listings = d.listings
			if d.get("rules") is Dictionary:
				Economy.market["rules"] = d.rules
			_rebuild())


func fetch_mine() -> void:
	Economy.net.send("GET", "/v1/market/mine", null, func(d: Dictionary):
		if d.get("mine") is Array:
			Economy.market = {"rules": d.get("rules", {}), "mine": d.mine}
			Economy.market_changed.emit())


func _on_state() -> void:
	if visible:
		_rebuild()


# --- 규칙(서버 market.ts와 같다) ---

## 판 사람이 받는 값: 값의 90% 내림.
static func proceeds_of(price: int) -> int:
	return floori(price * (100 - FEE_PCT) / 100.0)


## 내 판매 중 아직 판매 중인 것 수.
static func active_count() -> int:
	var n := 0
	for l in Economy.market.get("mine", []):
		if str(l.get("status")) == "active" and float(l.get("expires_at", 0)) > Economy.time_now():
			n += 1
	return n


## 올릴 수 있는 장비: 보관함에서 장착하지 않은 것(높은 등급 → 최신 순).
static func sellable_items() -> Array:
	var out := Economy.items().filter(func(it): return Economy.item_owner(int(it.id)) == "")
	var rank := func(it): return GameData.EQUIP_GRADES.find(it.grade)
	out.sort_custom(func(a, b): return [-rank.call(a), -int(a.id)] < [-rank.call(b), -int(b.id)])
	return out


## 올리기 막는 이유("" = 됨).
static func list_block(item_id: int, cur: String, price: int) -> String:
	if not online():
		return "offline"
	if Economy.item(item_id).is_empty():
		return "unknown_item"
	if Economy.item_owner(item_id) != "":
		return "equipped"
	var lim: Array = PRICE_LIMITS.get(cur, [1, 0])
	if price < int(lim[0]) or price > int(lim[1]):
		return "bad_price"
	if active_count() >= MAX_ACTIVE:
		return "too_many_listings"
	return ""


# --- 동작 ---

## 올리기: 곧바로 보관함에서 빼고 내 판매에 넣는다(서버가 거절하면 되돌린다).
func list_item(item_id: int, cur: String, price: int) -> bool:
	var why := list_block(item_id, cur, price)
	if why != "":
		Economy.notice.emit(OFFLINE_TEXT if why == "offline" else str(FAIL_TEXT.get(why, FAIL_DEFAULT)))
		return false
	var it := Economy.item(item_id)
	var ok := Economy._instant(func():
		Economy.bag = Economy.bag.filter(func(x): return int(x.id) != item_id)
		var mine: Array = Economy.market.get("mine", []).duplicate()
		mine.push_front({"id": -item_id, "item": it, "currency": cur, "price": price, "proceeds": proceeds_of(price), "status": "active",
			"seller": "", "expires_at": Economy.time_now() + 48 * 3600, "sold_at": null})
		Economy.market["mine"] = mine
		Economy.items_changed.emit()
		Economy.market_changed.emit()
		return true, "/v1/market/list", {"item_id": item_id, "currency": cur, "price": price}, _fail_text)
	if ok:
		picked = 0
		Economy.notice.emit("판매 등록: %s · %s %s" % [BagPanel.item_name(it), UiKit.commas(price), CUR_NAMES[cur]])
	return ok


## 내리기: 곧바로 장비를 보관함으로 돌린다.
func cancel_listing(listing: Dictionary) -> bool:
	if not online():
		return false
	var lid := int(listing.id)
	if lid <= 0:  # 아직 서버가 번호를 안 준 판매(방금 올림)
		return false
	var items := Economy._item_list([listing.get("item", {})])
	return Economy._instant(func():
		Economy.market["mine"] = Economy.market.get("mine", []).filter(func(l): return int(l.id) != lid)
		Economy.bag = Economy.bag + items
		Economy._reindex_items()
		Economy.items_changed.emit()
		Economy.market_changed.emit()
		return true, "/v1/market/cancel", {"id": lid}, _fail_text)


## 대금 받기(팔린 것 전부): 곧바로 골드·다이아를 더한다.
func collect() -> bool:
	if not online():
		return false
	var sum := collect_sum()
	if sum.gold <= 0 and sum.diamonds <= 0:
		return false
	var ok := Economy._instant(func():
		Economy.market["mine"] = Economy.market.get("mine", []).filter(func(l): return str(l.status) != "sold")
		Economy.market_sold = 0
		Economy.gold_tenths += int(sum.gold) * 10
		Economy.diamonds += int(sum.diamonds)
		Economy.market_changed.emit()
		return true, "/v1/market/collect", {}, _fail_text)
	if ok:
		var parts := []
		if sum.gold > 0:
			parts.append("+%s 골드" % UiKit.commas(sum.gold))
		if sum.diamonds > 0:
			parts.append("+%s 다이아" % UiKit.commas(sum.diamonds))
		Economy.notice.emit("판매 대금 " + " · ".join(parts))
	return ok


## 받을 대금 {gold, diamonds}.
static func collect_sum() -> Dictionary:
	var s := {"gold": 0, "diamonds": 0}
	for l in Economy.market.get("mine", []):
		if str(l.get("status")) == "sold":
			s[str(l.currency)] = int(s.get(str(l.currency), 0)) + int(l.proceeds)
	return s


## 사기(서버가 정한다): 결과가 오면 알리고 목록을 새로 받는다.
func buy(listing: Dictionary) -> void:
	if not online() or not Economy.net.up:
		Economy.notice.emit(OFFLINE_TEXT if not online() else Economy.WAIT_TEXT)
		return
	var cur := str(listing.currency)
	var price := int(listing.price)
	var have: int = Economy.gold if cur == "gold" else Economy.diamonds
	if have < price:
		Economy.notice.emit(FAIL_TEXT["not_enough_" + cur])
		return
	if Economy.bag.size() >= int(GameData.config_num("equip_bag_cap")):
		Economy.notice.emit(FAIL_TEXT.bag_full)
		return
	var lid := int(listing.id)
	Economy.net.flush_kills()
	Economy.net.send("POST", "/v1/market/buy", {"id": lid, "currency": cur, "price": price}, func(d: Dictionary):
		Economy.apply_server(d)
		var it := Economy._item_list([listing.get("item", {})])
		Economy.notice.emit("구매 완료: %s — 보관함에 넣었어요" % (BagPanel.item_name(it[0]) if not it.is_empty() else "장비"))
		listings = listings.filter(func(l): return int(l.id) != lid)
		_rebuild()
		if visible and tab == "buy":
			fetch_listings(), func():
		Economy.notice.emit(str(FAIL_TEXT.get(Economy.net.last_error, FAIL_DEFAULT)))
		if visible and tab == "buy":
			fetch_listings()
		Economy.net.refresh(), true, true)


func _fail_text() -> String:
	var code: String = Economy.net.last_error if Economy.net != null else ""
	if Economy.net != null:
		Economy.net.send("GET", "/v1/market/mine", null, func(d: Dictionary):  # 내 판매도 서버 값으로
			if d.get("mine") is Array:
				Economy.market = {"rules": d.get("rules", {}), "mine": d.mine}
				Economy.market_changed.emit())
	return str(FAIL_TEXT.get(code, FAIL_DEFAULT))


# --- 글자 ---

static func left_text(expires: float) -> String:
	var left := maxf(0.0, expires - Economy.time_now())
	var h := int(left) / 3600
	var m := (int(left) % 3600) / 60
	return "남은 시간 %d시간 %d분" % [h, m] if h > 0 else "남은 시간 %d분" % maxi(1, m)


static func price_text(cur: String, n: int) -> String:
	return "%s %s" % [UiKit.commas(n), CUR_NAMES.get(cur, cur)]


# --- 그리기 ---

func _rebuild() -> void:
	if body == null:
		return
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	for c in footer.get_children():
		footer.remove_child(c)
		c.queue_free()
	for k in buttons.keys():
		if not (k.begins_with("tab:") or k == "close" or k == "confirm"):
			buttons.erase(k)
	for t in TABS:
		var b: Button = buttons["tab:" + t[0]]
		UiKit.apply_button(b, UiKit.AMBER if t[0] == tab else UiKit.STEEL, 14.0)
		b.get_child(0).queue_redraw()
	wallet_label.text = "보유  골드 %s · 다이아 %s" % [UiKit.commas(Economy.gold), UiKit.commas(Economy.diamonds)]
	if not online():
		head_label.text = OFFLINE_TEXT
		return
	match tab:
		"buy":
			_build_buy()
		"sell":
			_build_sell()
		_:
			_build_mine()


func _build_buy() -> void:
	head_label.text = "다른 모험가가 올린 장비 · 값을 내면 바로 보관함으로"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var cb := _small("통화: " + CUR_NAMES[currency], func():
		currency = "diamonds" if currency == "gold" else "gold"
		refresh())
	var sb := _small("부위: " + (BagPanel.ITEM_NAMES[slot_filter] if slot_filter != "" else "전체"), func():
		var opts: Array = [""] + GameData.EQUIP_SLOTS
		slot_filter = opts[(opts.find(slot_filter) + 1) % opts.size()]
		refresh())
	var gb := _small("등급: " + (grade_filter if grade_filter != "" else "전체"), func():
		var opts: Array = [""] + GameData.EQUIP_GRADES
		grade_filter = opts[(opts.find(grade_filter) + 1) % opts.size()]
		refresh())
	var names := SORTS.map(func(s): return s[0])
	var ob := _small(SORTS[names.find(sort_mode)][1], func():
		sort_mode = names[(names.find(sort_mode) + 1) % names.size()]
		refresh())
	for b in [cb, sb, gb, ob]:
		row.add_child(b)
	buttons["cur"] = cb
	body.add_child(row)
	if listings.is_empty():
		body.add_child(_label("올라온 장비가 없어요", 24, SUB))
		return
	for l in listings:
		var items := Economy._item_list([l.get("item", {})])
		if items.is_empty():
			continue
		var it: Dictionary = items[0]
		var b := _button("구매", HudScript.ACCENT, 24)
		b.custom_minimum_size = Vector2(120, 56)
		var lr: Dictionary = l
		b.pressed.connect(func(): ask_buy(lr))
		buttons["buy:%d" % int(l.id)] = b
		var sub := "%s · " % str(l.get("seller", ""))
		body.add_child(_item_row(it, sub, float(l.expires_at), price_text(str(l.currency), int(l.price)), b, ROW_BG))


func _build_sell() -> void:
	var n := active_count()
	head_label.text = "판매 중 %d / %d · 판매 기간 48시간 · 정산 수수료 %d%%" % [n, MAX_ACTIVE, FEE_PCT]
	var items := sellable_items()
	if items.is_empty():
		body.add_child(_label("올릴 수 있는 장비가 없어요 (장착 중인 장비는 올릴 수 없어요)", 22, SUB))
	if picked != 0 and Economy.item(picked).is_empty():
		picked = 0
	for it in items:
		var id := int(it.id)
		var row := _item_row(it, "", -1.0, "", null, PICK_BG if id == picked else ROW_BG)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.gui_input.connect(func(e: InputEvent):
			var mb := e as InputEventMouseButton
			if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				picked = 0 if picked == id else id
				_rebuild())
		buttons["pick:%d" % id] = row
		body.add_child(row)
	_build_sell_form()


func _build_sell_form() -> void:
	if picked == 0:
		footer.add_child(_label("올릴 장비를 고르세요", 22, SUB))
		return
	var it := Economy.item(picked)
	footer.add_child(_label(BagPanel.item_name(it) + "  " + BagPanel.stat_text(it), 22, Art.ITEM_GRADE_COLORS[it.grade].darkened(0.35)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for cur in ["gold", "diamonds"]:
		var c: String = cur
		var b := _button(CUR_NAMES[cur], HudScript.ACCENT if sell_currency == cur else UiKit.STEEL, 24)
		b.custom_minimum_size = Vector2(120, 56)
		b.pressed.connect(func():
			sell_currency = c
			_rebuild())
		buttons["cur:" + cur] = b
		row.add_child(b)
	var prev := price_edit.text if price_edit != null and is_instance_valid(price_edit) else ""
	price_edit = LineEdit.new()
	price_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	price_edit.placeholder_text = "값 (%s~%s)" % [UiKit.commas(PRICE_LIMITS[sell_currency][0]), UiKit.commas(PRICE_LIMITS[sell_currency][1])]
	price_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_edit.add_theme_font_size_override("font_size", 26)
	price_edit.custom_minimum_size = Vector2(0, 56)
	price_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_edit.text = prev
	row.add_child(price_edit)
	footer.add_child(row)
	var get_label := _label("", 22, GOOD)
	footer.add_child(get_label)
	var lb := _button("판매 등록", HudScript.ACCENT, 28)
	buttons["list"] = lb
	footer.add_child(lb)
	var upd := func(_t: String):
		var p := price_value()
		get_label.text = "받는 금액 %s (수수료 %d%% %s)" % [price_text(sell_currency, proceeds_of(p)), FEE_PCT, UiKit.commas(p - proceeds_of(p))] if p > 0 else "값을 입력하세요"
		lb.disabled = list_block(picked, sell_currency, p) != ""
	price_edit.text_changed.connect(upd)
	upd.call("")
	lb.pressed.connect(func():
		var p := price_value()
		if list_item(picked, sell_currency, p):
			price_edit.text = ""
			_rebuild())


## 입력한 값(숫자만, 없으면 0).
func price_value() -> int:
	if price_edit == null or not is_instance_valid(price_edit):
		return 0
	var digits := ""
	for ch in price_edit.text:
		if ch >= "0" and ch <= "9":
			digits += ch
	return int(digits.left(12)) if digits != "" else 0


func _build_mine() -> void:
	var mine: Array = Economy.market.get("mine", [])
	var sum := collect_sum()
	head_label.text = "판매 중 %d / %d · 팔리면 값의 %d%%를 받아요" % [active_count(), MAX_ACTIVE, 100 - FEE_PCT]
	if sum.gold > 0 or sum.diamonds > 0:
		var parts := []
		if sum.gold > 0:
			parts.append(price_text("gold", sum.gold))
		if sum.diamonds > 0:
			parts.append(price_text("diamonds", sum.diamonds))
		var cb := _button("대금 받기  " + " · ".join(parts), HudScript.ACCENT, 26)
		cb.pressed.connect(collect)
		buttons["collect"] = cb
		body.add_child(cb)
	var shown := 0
	for l in mine:
		var sold := str(l.get("status")) == "sold"
		if not sold and (str(l.get("status")) != "active" or float(l.get("expires_at", 0)) <= Economy.time_now()):
			continue
		var items := Economy._item_list([l.get("item", {})])
		if items.is_empty():
			continue
		shown += 1
		var lr: Dictionary = l
		var action: Button = null
		if not sold:
			action = _button("내리기", UiKit.STEEL, 24)
			action.custom_minimum_size = Vector2(120, 56)
			action.disabled = int(l.id) <= 0
			action.pressed.connect(func(): cancel_listing(lr))
			buttons["cancel:%d" % int(l.id)] = action
		var tail := "판매 완료 · 받을 금액 %s" % price_text(str(l.currency), int(l.proceeds)) if sold else ""
		body.add_child(_item_row(items[0], tail, -1.0 if sold else float(l.expires_at), price_text(str(l.currency), int(l.price)), action,
			Color(0.86, 0.95, 0.86, 0.9) if sold else ROW_BG))
	if shown == 0:
		body.add_child(_label("판매 중인 장비가 없어요 — [판매 등록]에서 올려 보세요", 22, SUB))


## 장비 줄: 칸 + 이름(등급 색)·능력치 + 보조 글자(남은 시간) + 값 + 버튼.
func _item_row(it: Dictionary, sub: String, expires: float, price: String, action: Button, bg: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.panel(bg, 10.0, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var tile = ItemTileScript.new()
	tile.custom_minimum_size = Vector2(TILE_PX, TILE_PX)
	tile.set_item(BagPanel.item_kind(it), it.grade)
	row.add_child(tile)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 0)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_label(BagPanel.item_name(it), 24, Art.ITEM_GRADE_COLORS[it.grade].darkened(0.35), HORIZONTAL_ALIGNMENT_LEFT))
	info.add_child(BagPanel.stat_box(it, 20))  # 보관함과 같은 능력치 칸(기준보다 높으면 초록, 낮으면 빨강, 특수 능력치 줄)
	if sub != "" or expires > 0.0:
		var s := _label(sub + (left_text(expires) if expires > 0.0 else ""), 18, GOOD if sub.begins_with("판매 완료") else SUB, HORIZONTAL_ALIGNMENT_LEFT)
		if expires > 0.0:
			s.set_meta("expires", expires)
			s.set_meta("prefix", sub)
			s.add_to_group("exchange_left")
		info.add_child(s)
	for c in info.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	if price != "":
		var p := _label(price, 24, HudScript.INK, HORIZONTAL_ALIGNMENT_RIGHT)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(p)
	if action != null:
		action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(action)
	return card


func _small(text: String, f: Callable) -> Button:
	var b := _button(text, UiKit.STEEL, 20)
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 50)
	b.pressed.connect(f)
	return b


# --- 구매 확인 ---

func _build_confirm() -> void:
	confirm = PanelContainer.new()
	confirm.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM_DIALOG, 16.0, 22))
	confirm.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	confirm.grow_horizontal = Control.GROW_DIRECTION_BOTH
	confirm.grow_vertical = Control.GROW_DIRECTION_BOTH
	confirm.custom_minimum_size = Vector2(560, 0)
	confirm.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	confirm.add_child(v)
	_confirm_label = _label("", 26)
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_confirm_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var no := _button("취소", UiKit.STEEL, 26)
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.pressed.connect(func(): confirm.visible = false)
	_confirm_ok = _button("구매", HudScript.ACCENT, 26)
	_confirm_ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_ok.pressed.connect(func():
		confirm.visible = false
		buy(_confirm_listing))
	row.add_child(no)
	row.add_child(_confirm_ok)
	v.add_child(row)
	buttons["confirm"] = _confirm_ok
	dialog.get_parent().add_child(confirm)


## [구매] → 확인 창.
func ask_buy(listing: Dictionary) -> void:
	var items := Economy._item_list([listing.get("item", {})])
	if items.is_empty():
		return
	_confirm_listing = listing
	_confirm_label.text = "%s\n%s\n\n%s에 살까요?" % [BagPanel.item_name(items[0]), BagPanel.stat_text(items[0]), price_text(str(listing.currency), int(listing.price))]
	confirm.visible = true

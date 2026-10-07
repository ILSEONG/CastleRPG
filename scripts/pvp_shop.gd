extends "res://scripts/ui_window.gd"
## PVP 상점 창(PVP 탭·모드 페이지의 [상점]). 위 "PVP 상점" + 내 PVP 코인, 상품 줄마다: 아이콘·이름, "오늘 n / 한도"(주간은 "이번 주"),
## 코인 가격, [구매]. 누르면 곧바로 코인·구매 수가 바뀌고(Pvp.buy — 서버 확인은 뒤에서, 거절되면 되돌리고 알림) 보상은 서버 응답과 함께 들어온다.
## 코인이 모자라거나 한도를 채웠으면 [구매]가 꺼진다(글자는 그대로). [닫기].

const PvpRules := preload("res://scripts/pvp_rules.gd")
const IconsScript := preload("res://scripts/icons.gd")
const PvpView := preload("res://scripts/pvp_view.gd")

const ICON := {"gold": "gold", "dia": "diamond", "ticket": "diamond", "equip": "", "shards": "", "ssr": ""}

var coin_label: Label
var rows := {}  # 상품 id → {limit, buy}


func _ready() -> void:
	_build_window(660, 12)
	layer = 3  # 던전 시트 위
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	content.add_child(head)
	var t := _title("PVP 상점")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var coin := Control.new()
	coin.custom_minimum_size = Vector2(36, 36)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin.draw.connect(PvpView.draw_coin.bind(coin))
	head.add_child(coin)
	coin_label = _label("", 30)
	head.add_child(coin_label)
	for it in PvpRules.SHOP:
		content.add_child(_row(it))
	var note := _label("PVP 코인은 결투·총력전에서 얻어요 (승리 %d · 패배 %d)" % [PvpRules.COINS_WIN, PvpRules.COINS_LOSS], 20, HudScript.INK.lightened(0.3))
	content.add_child(note)
	var close_b := _button("닫기", UiKit.STEEL)
	close_b.pressed.connect(close)
	content.add_child(close_b)
	Pvp.changed.connect(_refresh)
	Economy.changed.connect(_refresh)


func _row(it: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM, 12.0, 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(52, 52)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.draw.connect(_draw_item.bind(icon, str(it.id)))
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(_label(PvpRules.SHOP_NAMES.get(it.id, it.id), 26, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	var limit := _label("", 20, HudScript.INK.lightened(0.3), HORIZONTAL_ALIGNMENT_LEFT)
	col.add_child(limit)
	var buy := _button("%d" % int(it.price), HudScript.ACCENT, 26)
	buy.custom_minimum_size = Vector2(150, 60)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.pressed.connect(func(): Pvp.buy(str(it.id)))
	row.add_child(buy)
	rows[it.id] = {"limit": limit, "buy": buy}
	return panel


func _on_open() -> void:
	Pvp.fetch_if_stale()
	_refresh()


func _refresh() -> void:
	if not visible:
		return
	coin_label.text = UiKit.commas(Pvp.coins())
	for it in PvpRules.SHOP:
		var r: Dictionary = rows[it.id]
		var row := Pvp.shop_item(str(it.id))
		var bought := int(row.get("bought", 0))
		r.limit.text = "%s %d / %d" % ["오늘" if it.period == "day" else "이번 주", bought, int(it.limit)]
		r.buy.text = "코인 %d" % int(it.price)
		r.buy.disabled = Pvp.buy_block(str(it.id)) != ""


## 상품 그림: 골드·다이아는 자원 아이콘, 장비 상자 = 나무 상자, 조각 = 보라(SSR은 금색) 보석 조각.
func _draw_item(c: Control, id: String) -> void:
	var s := c.size
	match id:
		"gold", "dia", "ticket":
			IconsScript.draw_icon(c, "gold" if id == "gold" else "diamond", s / 2.0, minf(s.x, s.y))
			if id == "ticket":
				c.draw_rect(Rect2(s.x * 0.08, s.y * 0.62, s.x * 0.84, s.y * 0.3), Color("E8D9B5"))
				c.draw_rect(Rect2(s.x * 0.08, s.y * 0.62, s.x * 0.84, s.y * 0.3), Color("8A7550"), false, 2.0)
		"equip":
			c.draw_rect(Rect2(s.x * 0.1, s.y * 0.3, s.x * 0.8, s.y * 0.58), Color("9B6B3E"))
			c.draw_rect(Rect2(s.x * 0.1, s.y * 0.3, s.x * 0.8, s.y * 0.18), Color("B98250"))
			c.draw_rect(Rect2(s.x * 0.44, s.y * 0.4, s.x * 0.12, s.y * 0.16), Color("E2B23A"))
			c.draw_rect(Rect2(s.x * 0.1, s.y * 0.3, s.x * 0.8, s.y * 0.58), Color("5E3F22"), false, 2.0)
		_:
			var col := Color("E2B23A") if id == "ssr" else Color("A86BE0")
			for k in 3:
				var o := Vector2(s.x * (0.3 + 0.2 * k), s.y * (0.6 - 0.12 * (k % 2)))
				UiKit.draw_gem(c, o, s.x * 0.17, col, 5)

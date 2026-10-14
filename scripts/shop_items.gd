extends RefCounted
## 상점 상품 표(서버 server/src/shop.ts ITEMS와 같은 값 — 한쪽을 바꾸면 다른 쪽도). 일일·주간 한정 상품을 다이아·골드로 산다(실결제 없음).
## currency: "free"(무료 선물)·"diamonds"·"gold"·"ad"(보상형 광고를 보면 받는다 — 광고 제거 구매자는 바로, 매일 리셋, 기록은 일일과 같은 d). limit = 리셋 기간(일일: 매일 리셋 시각, 주간: 월요일)마다 살 수 있는 횟수.
## give = 보상 키(출석·미션 보상과 같은 규칙: gold·diamonds·tickets·wood·stone·food·keys_<던전>·pouch_<id>).
## icon = 상점 카드 그림(shop_panel.gd draw_item_icon — shop_art.gd의 그린 그림 이름, 없으면 벡터 그림).

const Lang := preload("res://scripts/lang.gd")

static var ITEMS := [
	{"id": "d_free", "tab": "daily", "name": Lang.t("shop_items.items.d_free.name"), "currency": "free", "price": 0, "limit": 1, "give": {"diamonds": 50, "pouch_gold_60": 1}, "icon": "gift"},
	{"id": "d_ticket", "tab": "daily", "name": Lang.t("shop_items.items.d_ticket.name"), "currency": "diamonds", "price": 240, "limit": 1, "give": {"tickets": 1}, "icon": "ticket"},
	{"id": "d_pouch_gold", "tab": "daily", "name": Lang.t("shop_items.items.d_pouch_gold.name"), "currency": "diamonds", "price": 40, "limit": 3, "give": {"pouch_gold_60": 1}, "icon": "pouch_gold"},
	{"id": "d_pouch_res", "tab": "daily", "name": Lang.t("shop_items.items.d_pouch_res.name"), "currency": "diamonds", "price": 40, "limit": 3, "give": {"pouch_res_60": 1}, "icon": "pouch_res"},
	{"id": "d_key_gold", "tab": "daily", "name": Lang.t("shop_items.items.d_key_gold.name"), "currency": "diamonds", "price": 60, "limit": 3, "give": {"keys_gold": 1}, "icon": "key_gold"},
	{"id": "d_key_equip", "tab": "daily", "name": Lang.t("shop_items.items.d_key_equip.name"), "currency": "diamonds", "price": 100, "limit": 2, "give": {"keys_equip": 1}, "icon": "key_equip"},
	{"id": "d_key_ticket", "tab": "daily", "name": Lang.t("shop_items.items.d_key_ticket.name"), "currency": "diamonds", "price": 150, "limit": 1, "give": {"keys_ticket": 1}, "icon": "key_ticket"},
	{"id": "d_res", "tab": "daily", "name": Lang.t("shop_items.items.d_res.name"), "currency": "diamonds", "price": 50, "limit": 3, "give": {"wood": 10000, "stone": 10000, "food": 10000}, "icon": "res_pile"},
	{"id": "d_sp_build", "tab": "daily", "name": Lang.t("shop_items.items.d_sp_build.name"), "currency": "diamonds", "price": 40, "limit": 3, "give": {"speedup_build_60": 1}, "icon": "haste"},
	{"id": "d_sp_research", "tab": "daily", "name": Lang.t("shop_items.items.d_sp_research.name"), "currency": "diamonds", "price": 40, "limit": 3, "give": {"speedup_research_60": 1}, "icon": "flask"},
	{"id": "a_dia", "tab": "ad", "name": Lang.t("shop_items.items.a_dia.name"), "currency": "ad", "price": 0, "limit": 5, "give": {"diamonds": 100}, "icon": "dia_1"},
	{"id": "a_ticket", "tab": "ad", "name": Lang.t("shop_items.items.a_ticket.name"), "currency": "ad", "price": 0, "limit": 2, "give": {"tickets": 1}, "icon": "ticket"},
	{"id": "a_key_gold", "tab": "ad", "name": Lang.t("shop_items.items.a_key_gold.name"), "currency": "ad", "price": 0, "limit": 2, "give": {"keys_gold": 1}, "icon": "key_gold"},
	{"id": "a_key_equip", "tab": "ad", "name": Lang.t("shop_items.items.a_key_equip.name"), "currency": "ad", "price": 0, "limit": 1, "give": {"keys_equip": 1}, "icon": "key_equip"},
	{"id": "a_key_ticket", "tab": "ad", "name": Lang.t("shop_items.items.a_key_ticket.name"), "currency": "ad", "price": 0, "limit": 1, "give": {"keys_ticket": 1}, "icon": "key_ticket"},
	{"id": "a_pouch_gold", "tab": "ad", "name": Lang.t("shop_items.items.a_pouch_gold.name"), "currency": "ad", "price": 0, "limit": 3, "give": {"pouch_gold_60": 1}, "icon": "pouch_gold"},
	{"id": "a_pouch_res", "tab": "ad", "name": Lang.t("shop_items.items.a_pouch_res.name"), "currency": "ad", "price": 0, "limit": 3, "give": {"pouch_res_60": 1}, "icon": "pouch_res"},
	{"id": "a_sp_any", "tab": "ad", "name": Lang.t("shop_items.items.a_sp_any.name"), "currency": "ad", "price": 0, "limit": 3, "give": {"speedup_any_15": 1}, "icon": "haste"},
	{"id": "w_free", "tab": "weekly", "name": Lang.t("shop_items.items.w_free.name"), "currency": "free", "price": 0, "limit": 1, "give": {"diamonds": 150, "tickets": 2}, "icon": "gift_big"},
	{"id": "w_tickets", "tab": "weekly", "name": Lang.t("shop_items.items.w_tickets.name"), "currency": "diamonds", "price": 2400, "limit": 1, "give": {"tickets": 10}, "icon": "tickets"},
	{"id": "w_pouch_gold", "tab": "weekly", "name": Lang.t("shop_items.items.w_pouch_gold.name"), "currency": "diamonds", "price": 200, "limit": 2, "give": {"pouch_gold_360": 1}, "icon": "pouch_gold"},
	{"id": "w_pouch_res", "tab": "weekly", "name": Lang.t("shop_items.items.w_pouch_res.name"), "currency": "diamonds", "price": 200, "limit": 2, "give": {"pouch_res_360": 1}, "icon": "pouch_res"},
	{"id": "w_sp_any", "tab": "weekly", "name": Lang.t("shop_items.items.w_sp_any.name"), "currency": "diamonds", "price": 250, "limit": 3, "give": {"speedup_any_480": 1}, "icon": "haste"},
	{"id": "w_sp_build", "tab": "weekly", "name": Lang.t("shop_items.items.w_sp_build.name"), "currency": "diamonds", "price": 700, "limit": 2, "give": {"speedup_build_1440": 1}, "icon": "haste"},
	{"id": "w_sp_research", "tab": "weekly", "name": Lang.t("shop_items.items.w_sp_research.name"), "currency": "diamonds", "price": 700, "limit": 2, "give": {"speedup_research_1440": 1}, "icon": "flask"},
	{"id": "w_builder", "tab": "weekly", "name": Lang.t("shop_items.items.w_builder.name"), "currency": "diamonds", "price": 1000, "limit": 1, "give": {"speedup_builder_10080": 1}, "icon": "hammer"},
	{"id": "w_res", "tab": "weekly", "name": Lang.t("shop_items.items.w_res.name"), "currency": "diamonds", "price": 300, "limit": 2, "give": {"wood": 100000, "stone": 100000, "food": 100000}, "icon": "res_pile"},
]


static func find(id: String) -> Dictionary:
	for x in ITEMS:
		if x.id == id:
			return x
	return {}


static func of_tab(tab: String) -> Array:
	return ITEMS.filter(func(x): return x.tab == tab)

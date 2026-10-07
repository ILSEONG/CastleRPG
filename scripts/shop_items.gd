extends RefCounted
## 상점 상품 표(서버 server/src/shop.ts ITEMS와 같은 값 — 한쪽을 바꾸면 다른 쪽도). 일일·주간 한정 상품을 다이아·골드로 산다(실결제 없음).
## currency: "free"(무료 선물)·"diamonds"·"gold". limit = 리셋 기간(일일: 매일 리셋 시각, 주간: 월요일)마다 살 수 있는 횟수.
## give = 보상 키(출석·미션 보상과 같은 규칙: gold·diamonds·tickets·wood·stone·food·keys_<던전>·pouch_<id>).
## icon = 상점 카드 그림(shop_panel.gd).

const ITEMS := [
	{"id": "d_free", "tab": "daily", "name": "매일 무료 선물", "currency": "free", "price": 0, "limit": 1, "give": {"diamonds": 50, "pouch_gold_60": 1}, "icon": "gift"},
	{"id": "d_ticket", "tab": "daily", "name": "다이아 모집권 할인", "currency": "diamonds", "price": 240, "limit": 1, "give": {"tickets": 1}, "icon": "ticket"},
	{"id": "d_pouch_gold", "tab": "daily", "name": "골드 주머니(1시간)", "currency": "diamonds", "price": 40, "limit": 3, "give": {"pouch_gold_60": 1}, "icon": "pouch_gold"},
	{"id": "d_pouch_res", "tab": "daily", "name": "자원 주머니(1시간)", "currency": "diamonds", "price": 40, "limit": 3, "give": {"pouch_res_60": 1}, "icon": "pouch_res"},
	{"id": "d_key_gold", "tab": "daily", "name": "골드 던전 입장권", "currency": "diamonds", "price": 60, "limit": 3, "give": {"keys_gold": 1}, "icon": "key"},
	{"id": "d_key_equip", "tab": "daily", "name": "장비 던전 입장권", "currency": "diamonds", "price": 100, "limit": 2, "give": {"keys_equip": 1}, "icon": "key"},
	{"id": "d_key_ticket", "tab": "daily", "name": "모집권 던전 입장권", "currency": "diamonds", "price": 150, "limit": 1, "give": {"keys_ticket": 1}, "icon": "key"},
	{"id": "d_res", "tab": "daily", "name": "자원 꾸러미", "currency": "diamonds", "price": 50, "limit": 3, "give": {"wood": 10000, "stone": 10000, "food": 10000}, "icon": "res_pile"},
	{"id": "w_free", "tab": "weekly", "name": "주간 무료 선물", "currency": "free", "price": 0, "limit": 1, "give": {"diamonds": 150, "tickets": 2}, "icon": "gift"},
	{"id": "w_tickets", "tab": "weekly", "name": "모집권 10장 묶음", "currency": "diamonds", "price": 2400, "limit": 1, "give": {"tickets": 10}, "icon": "ticket"},
	{"id": "w_pouch_gold", "tab": "weekly", "name": "골드 주머니(6시간)", "currency": "diamonds", "price": 200, "limit": 2, "give": {"pouch_gold_360": 1}, "icon": "pouch_gold"},
	{"id": "w_pouch_res", "tab": "weekly", "name": "자원 주머니(6시간)", "currency": "diamonds", "price": 200, "limit": 2, "give": {"pouch_res_360": 1}, "icon": "pouch_res"},
	{"id": "w_res", "tab": "weekly", "name": "큰 자원 꾸러미", "currency": "diamonds", "price": 300, "limit": 2, "give": {"wood": 100000, "stone": 100000, "food": 100000}, "icon": "res_pile"},
]


static func find(id: String) -> Dictionary:
	for x in ITEMS:
		if x.id == id:
			return x
	return {}


static func of_tab(tab: String) -> Array:
	return ITEMS.filter(func(x): return x.tab == tab)

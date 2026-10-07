extends RefCounted
## 결제 상품 표(서버 server/src/iap.ts PRODUCTS·GROWTH와 같은 값 — 한쪽을 바꾸면 다른 쪽도, 단위 테스트 test_iap가 비교한다).
## kind: diamond(충전: 첫 구매는 기본 다이아 2배, 이후 기본 + bonus)·monthly(월정액 days일, 사면 give + 매일 daily)·package(period 기간 한도 limit)·
## pass(성장 패스: GROWTH 유료 보상). krw = 원화 가격. 실결제는 Google Play 연결 전이라 아직 살 수 없다(Economy.iap_buy가 알린다).

const PRODUCTS := [
	{ "id": "dia_1", "kind": "diamond", "name": "다이아 300", "krw": 1200, "give": { "diamonds": 300 }, "bonus": 0 },
	{ "id": "dia_2", "kind": "diamond", "name": "다이아 1,500", "krw": 5900, "give": { "diamonds": 1500 }, "bonus": 150 },
	{ "id": "dia_3", "kind": "diamond", "name": "다이아 3,100", "krw": 12000, "give": { "diamonds": 3100 }, "bonus": 400 },
	{ "id": "dia_4", "kind": "diamond", "name": "다이아 8,600", "krw": 33000, "give": { "diamonds": 8600 }, "bonus": 1400 },
	{ "id": "dia_5", "kind": "diamond", "name": "다이아 15,500", "krw": 59000, "give": { "diamonds": 15500 }, "bonus": 3000 },
	{ "id": "dia_6", "kind": "diamond", "name": "다이아 26,000", "krw": 99000, "give": { "diamonds": 26000 }, "bonus": 6000 },
	{ "id": "monthly", "kind": "monthly", "name": "성주의 월정액", "krw": 4900, "give": { "diamonds": 300 }, "days": 30, "daily": { "diamonds": 100 } },
	{ "id": "monthly_plus", "kind": "monthly", "name": "왕의 월정액", "krw": 14900, "give": { "diamonds": 1000 }, "days": 30, "daily": { "diamonds": 150, "tickets": 1, "pouch_gold_60": 1 } },
	{ "id": "pkg_starter", "kind": "package", "name": "신규 성주 패키지", "krw": 1200, "period": "once", "limit": 1, "give": { "diamonds": 300, "tickets": 10, "pouch_gold_120": 2, "pouch_res_120": 2 } },
	{ "id": "pkg_daily", "kind": "package", "name": "일일 특가 패키지", "krw": 1200, "period": "daily", "limit": 1, "give": { "diamonds": 150, "tickets": 2, "keys_gold": 1 } },
	{ "id": "pkg_weekly", "kind": "package", "name": "주간 특가 패키지", "krw": 5900, "period": "weekly", "limit": 1, "give": { "diamonds": 800, "tickets": 12, "keys_equip": 2 } },
	{ "id": "pkg_growth", "kind": "package", "name": "성장 지원 패키지", "krw": 33000, "period": "once", "limit": 1, "give": { "diamonds": 6000, "tickets": 30, "pouch_gold_360": 3, "pouch_res_360": 3 } },
	{ "id": "pass_growth", "kind": "pass", "name": "성장 패스", "krw": 9900, "give": {} },
]

## 성장 패스 단계: round(깬 라운드)에 닿으면 free(누구나)·paid(패스 구매자).
const GROWTH := [
	{ "round": 10, "free": { "diamonds": 30 }, "paid": { "diamonds": 300 } },
	{ "round": 25, "free": { "tickets": 1 }, "paid": { "diamonds": 300, "tickets": 2 } },
	{ "round": 50, "free": { "diamonds": 50 }, "paid": { "diamonds": 400 } },
	{ "round": 75, "free": { "tickets": 1 }, "paid": { "diamonds": 400, "tickets": 3 } },
	{ "round": 100, "free": { "diamonds": 50 }, "paid": { "diamonds": 500 } },
	{ "round": 150, "free": { "tickets": 1 }, "paid": { "diamonds": 500, "tickets": 3 } },
	{ "round": 200, "free": { "diamonds": 80 }, "paid": { "diamonds": 600 } },
	{ "round": 250, "free": { "tickets": 2 }, "paid": { "diamonds": 600, "tickets": 5 } },
	{ "round": 300, "free": { "diamonds": 100 }, "paid": { "diamonds": 800 } },
	{ "round": 375, "free": { "tickets": 2 }, "paid": { "diamonds": 800, "tickets": 5 } },
	{ "round": 450, "free": { "diamonds": 100 }, "paid": { "diamonds": 1000 } },
	{ "round": 550, "free": { "tickets": 3 }, "paid": { "diamonds": 1000, "tickets": 10 } },
]

const MONTHLY_MAX_DAYS := 180


static func find(id: String) -> Dictionary:
	for p in PRODUCTS:
		if p.id == id:
			return p
	return {}


static func of_kind(kind: String) -> Array:
	return PRODUCTS.filter(func(p): return p.kind == kind)

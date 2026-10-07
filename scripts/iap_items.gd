extends RefCounted
## 결제 상품 표(서버 server/src/iap.ts PRODUCTS·GROWTH와 같은 값 — 한쪽을 바꾸면 다른 쪽도, 단위 테스트 test_iap가 비교한다).
## kind: diamond(충전: 첫 구매는 기본 다이아 2배, 이후 기본 + bonus)·monthly(월정액 days일, 사면 give + 매일 daily)·package(period 기간 한도 limit)·
## pass(성장 패스: GROWTH 유료 보상)·hot(핫딜: 계기에 1시간 뜬 것만 한 번, value = 가치 배수 표시). krw = 원화 가격. 실결제는 Google Play 연결 전이라 아직 살 수 없다(Economy.iap_buy가 알린다).

const PRODUCTS := [
	{ "id": "dia_1", "kind": "diamond", "name": "다이아 300", "krw": 1200, "give": { "diamonds": 300 }, "bonus": 30 },
	{ "id": "dia_2", "kind": "diamond", "name": "다이아 1,500", "krw": 5900, "give": { "diamonds": 1500 }, "bonus": 300 },
	{ "id": "dia_3", "kind": "diamond", "name": "다이아 3,100", "krw": 12000, "give": { "diamonds": 3100 }, "bonus": 800 },
	{ "id": "dia_4", "kind": "diamond", "name": "다이아 8,600", "krw": 33000, "give": { "diamonds": 8600 }, "bonus": 2600 },
	{ "id": "dia_5", "kind": "diamond", "name": "다이아 15,500", "krw": 59000, "give": { "diamonds": 15500 }, "bonus": 5500 },
	{ "id": "dia_6", "kind": "diamond", "name": "다이아 26,000", "krw": 99000, "give": { "diamonds": 26000 }, "bonus": 11000 },
	{ "id": "monthly", "kind": "monthly", "name": "성주의 월정액", "krw": 4900, "give": { "diamonds": 600 }, "days": 30, "daily": { "diamonds": 200 } },
	{ "id": "monthly_plus", "kind": "monthly", "name": "왕의 월정액", "krw": 14900, "give": { "diamonds": 2000 }, "days": 30, "daily": { "diamonds": 300, "tickets": 2, "pouch_gold_120": 1 } },
	{ "id": "pkg_starter", "kind": "package", "name": "신규 성주 패키지", "krw": 1200, "period": "once", "limit": 1, "give": { "diamonds": 600, "tickets": 20, "pouch_gold_120": 3, "pouch_res_120": 3 } },
	{ "id": "pkg_daily", "kind": "package", "name": "일일 특가 패키지", "krw": 1200, "period": "daily", "limit": 1, "give": { "diamonds": 300, "tickets": 4, "keys_gold": 2 } },
	{ "id": "pkg_weekly", "kind": "package", "name": "주간 특가 패키지", "krw": 5900, "period": "weekly", "limit": 1, "give": { "diamonds": 1600, "tickets": 25, "keys_equip": 3 } },
	{ "id": "pkg_growth", "kind": "package", "name": "성장 지원 패키지", "krw": 33000, "period": "once", "limit": 1, "give": { "diamonds": 12000, "tickets": 60, "pouch_gold_360": 5, "pouch_res_360": 5 } },
	{ "id": "hot_boss", "kind": "hot", "name": "보스 격파 기념 특가", "krw": 3300, "value": 10, "give": { "diamonds": 2000, "tickets": 10, "pouch_gold_360": 2 } },
	{ "id": "hot_dia", "kind": "hot", "name": "다이아 긴급 지원", "krw": 5900, "value": 8, "give": { "diamonds": 5000, "tickets": 5 } },
	{ "id": "hot_defeat", "kind": "hot", "name": "패배 극복 특가", "krw": 4900, "value": 10, "give": { "diamonds": 1500, "tickets": 10, "pouch_gold_360": 3, "pouch_res_360": 3 } },
	{ "id": "pass_growth", "kind": "pass", "name": "성장 패스", "krw": 9900, "give": {} },
]

## 성장 패스 단계: round(깬 라운드)에 닿으면 free(누구나)·paid(패스 구매자).
const GROWTH := [
	{ "round": 10, "free": { "diamonds": 60 }, "paid": { "diamonds": 600 } },
	{ "round": 25, "free": { "tickets": 2 }, "paid": { "diamonds": 600, "tickets": 4 } },
	{ "round": 50, "free": { "diamonds": 100 }, "paid": { "diamonds": 800 } },
	{ "round": 75, "free": { "tickets": 2 }, "paid": { "diamonds": 800, "tickets": 6 } },
	{ "round": 100, "free": { "diamonds": 100 }, "paid": { "diamonds": 1000 } },
	{ "round": 150, "free": { "tickets": 2 }, "paid": { "diamonds": 1000, "tickets": 6 } },
	{ "round": 200, "free": { "diamonds": 160 }, "paid": { "diamonds": 1200 } },
	{ "round": 250, "free": { "tickets": 4 }, "paid": { "diamonds": 1200, "tickets": 10 } },
	{ "round": 300, "free": { "diamonds": 200 }, "paid": { "diamonds": 1600 } },
	{ "round": 375, "free": { "tickets": 4 }, "paid": { "diamonds": 1600, "tickets": 10 } },
	{ "round": 450, "free": { "diamonds": 200 }, "paid": { "diamonds": 2000 } },
	{ "round": 550, "free": { "tickets": 6 }, "paid": { "diamonds": 2000, "tickets": 20 } },
]

const MONTHLY_MAX_DAYS := 180

## 핫딜(hot): 계기 → 상품, 뜬 뒤 살 수 있는 시간, 계기마다 다시 뜨기까지 쉬는 시간(초). 보스는 HOT_ROUNDS(1스테이지)마다 한 번. 서버 iap.ts HOT과 같다.
const HOT_SEC := 3600
const HOT := {
	"boss": { "product": "hot_boss", "cool": 6 * 3600 },
	"dia": { "product": "hot_dia", "cool": 24 * 3600 },
	"defeat": { "product": "hot_defeat", "cool": 12 * 3600 },
}
const HOT_ROUNDS := 25


static func find(id: String) -> Dictionary:
	for p in PRODUCTS:
		if p.id == id:
			return p
	return {}


static func of_kind(kind: String) -> Array:
	return PRODUCTS.filter(func(p): return p.kind == kind)

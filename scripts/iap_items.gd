extends RefCounted
## 결제 상품 표(서버 server/src/iap.ts PRODUCTS·GROWTH와 같은 값 — 한쪽을 바꾸면 다른 쪽도, 단위 테스트 test_iap가 비교한다).
## kind: diamond(충전: 첫 구매는 기본 다이아 2배, 이후 기본 + bonus)·monthly(월정액 days일, 사면 give + 매일 daily)·package(period 기간 한도 limit)·
## pass(성장 패스: GROWTH 유료 보상)·hot(핫딜: 계기에 1시간 뜬 것만 한 번, value = 가치 배수 표시). krw = 원화 가격. 실결제는 Economy.iap_buy → StorePay(Google Play·토스, 서버 키가 없으면 알림만).

const PRODUCTS := [
	{ "id": "dia_1", "kind": "diamond", "name": "다이아 900", "krw": 1200, "give": { "diamonds": 900 }, "bonus": 90 },
	{ "id": "dia_2", "kind": "diamond", "name": "다이아 4,500", "krw": 5900, "give": { "diamonds": 4500 }, "bonus": 900 },
	{ "id": "dia_3", "kind": "diamond", "name": "다이아 9,300", "krw": 12000, "give": { "diamonds": 9300 }, "bonus": 2400 },
	{ "id": "dia_4", "kind": "diamond", "name": "다이아 25,800", "krw": 33000, "give": { "diamonds": 25800 }, "bonus": 7800 },
	{ "id": "dia_5", "kind": "diamond", "name": "다이아 46,500", "krw": 59000, "give": { "diamonds": 46500 }, "bonus": 16500 },
	{ "id": "dia_6", "kind": "diamond", "name": "다이아 78,000", "krw": 99000, "give": { "diamonds": 78000 }, "bonus": 33000 },
	{ "id": "monthly", "kind": "monthly", "name": "성주의 월정액", "krw": 4900, "give": { "diamonds": 1500 }, "days": 30, "daily": { "diamonds": 500 } },
	{ "id": "monthly_plus", "kind": "monthly", "name": "왕의 월정액", "krw": 14900, "give": { "diamonds": 5000 }, "days": 30, "daily": { "diamonds": 800, "tickets": 3, "pouch_gold_240": 1 } },
	{ "id": "pkg_starter", "kind": "package", "name": "신규 성주 패키지", "krw": 1200, "period": "once", "limit": 1, "give": { "diamonds": 1500, "tickets": 30, "pouch_gold_120": 5, "pouch_res_120": 5 } },
	{ "id": "pkg_daily", "kind": "package", "name": "일일 특가 패키지", "krw": 1200, "period": "daily", "limit": 1, "give": { "diamonds": 600, "tickets": 8, "keys_gold": 3 } },
	{ "id": "pkg_weekly", "kind": "package", "name": "주간 특가 패키지", "krw": 5900, "period": "weekly", "limit": 1, "give": { "diamonds": 4000, "tickets": 50, "keys_equip": 5 } },
	{ "id": "pkg_growth", "kind": "package", "name": "성장 지원 패키지", "krw": 33000, "period": "once", "limit": 1, "give": { "diamonds": 30000, "tickets": 150, "pouch_gold_360": 10, "pouch_res_360": 10 } },
	{ "id": "hot_boss", "kind": "hot", "name": "보스 격파 기념 특가", "krw": 3300, "value": 10, "give": { "diamonds": 5000, "tickets": 20, "pouch_gold_360": 3 } },
	{ "id": "hot_dia", "kind": "hot", "name": "다이아 긴급 지원", "krw": 5900, "value": 8, "give": { "diamonds": 12000, "tickets": 15 } },
	{ "id": "hot_defeat", "kind": "hot", "name": "패배 극복 특가", "krw": 4900, "value": 10, "give": { "diamonds": 4000, "tickets": 20, "pouch_gold_360": 5, "pouch_res_360": 5 } },
	{ "id": "pass_growth", "kind": "pass", "name": "성장 패스", "krw": 9900, "give": {} },
	{ "id": "no_ads", "kind": "pass", "name": "광고 제거", "krw": 5500, "give": {} },
]

## 성장 패스 단계: round(깬 라운드)에 닿으면 free(누구나)·paid(패스 구매자).
const GROWTH := [
	{ "round": 10, "free": { "diamonds": 60 }, "paid": { "diamonds": 1800 } },
	{ "round": 25, "free": { "tickets": 2 }, "paid": { "diamonds": 1800, "tickets": 12 } },
	{ "round": 50, "free": { "diamonds": 100 }, "paid": { "diamonds": 2400 } },
	{ "round": 75, "free": { "tickets": 2 }, "paid": { "diamonds": 2400, "tickets": 18 } },
	{ "round": 100, "free": { "diamonds": 100 }, "paid": { "diamonds": 3000 } },
	{ "round": 150, "free": { "tickets": 2 }, "paid": { "diamonds": 3000, "tickets": 18 } },
	{ "round": 200, "free": { "diamonds": 160 }, "paid": { "diamonds": 3600 } },
	{ "round": 250, "free": { "tickets": 4 }, "paid": { "diamonds": 3600, "tickets": 30 } },
	{ "round": 300, "free": { "diamonds": 200 }, "paid": { "diamonds": 4800 } },
	{ "round": 375, "free": { "tickets": 4 }, "paid": { "diamonds": 4800, "tickets": 30 } },
	{ "round": 450, "free": { "diamonds": 200 }, "paid": { "diamonds": 6000 } },
	{ "round": 550, "free": { "tickets": 6 }, "paid": { "diamonds": 6000, "tickets": 60 } },
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

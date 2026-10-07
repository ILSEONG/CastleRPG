extends RefCounted
## PVP 수치·규칙 한 곳(오토로드 의존 없음). 서버 server/src/pvp.ts와 같은 값·식이다 — 바꾸려면 둘 다.
## 모드: duel(결투 — 영웅 5 대 5, 내 영웅은 조종, 상대는 AI) · total(총력전 — 영웅 5 + 병사, 양쪽 다 AI). 모드마다 하루 PLAYS판, 포인트·등급 따로.
## 시작에 판 하나를 쓰고 패배(−LOSS)로 먼저 적는다 — 이기면 되돌리고 +win_gain. 코인(PVP 코인)은 두 모드가 함께 번다.

const MODES := ["duel", "total"]
const NAMES := {"duel": "결투", "total": "총력전"}
const BLURB := {"duel": "영웅 5 대 5 · 내 영웅을 직접 조종", "total": "영웅 5 + 병사 대 영웅 5 + 병사 · 자동 전투"}
const TEAM := 5
const PLAYS := 5
const BATTLE_SEC := {"duel": 90.0, "total": 120.0}
const MIN_WIN_SEC := 8.0
const SOLDIER_CAP := 20
const WIN_BASE := 25
const WIN_DIFF_DIV := 20.0
const WIN_DIFF_CAP := 10
const LOSS := 10
const COINS_WIN := 30
const COINS_LOSS := 10
const BOT_POWER := [0.9, 1.05]
const MIN_POWER := 250.0
## [id, 이름, 이 포인트 이상, 색]
const TIERS := [
	["bronze", "브론즈", 0, Color("B0703A")], ["silver", "실버", 200, Color("A9B4C2")], ["gold", "골드", 500, Color("E2B23A")],
	["platinum", "플래티넘", 900, Color("57C3B5")], ["diamond", "다이아몬드", 1400, Color("6FA8F0")], ["master", "마스터", 2000, Color("A86BE0")],
	["challenger", "챌린저", 2700, Color("E8504A")],
]
## PVP 상점(서버 SHOP과 같다). give 키: gold·diamonds·tickets·equip·shards·ssr_shards.
const SHOP := [
	{"id": "gold", "give": {"gold": 30000}, "price": 60, "limit": 3, "period": "day"},
	{"id": "equip", "give": {"equip": 1}, "price": 50, "limit": 3, "period": "day"},
	{"id": "dia", "give": {"diamonds": 50}, "price": 150, "limit": 2, "period": "day"},
	{"id": "ticket", "give": {"tickets": 1}, "price": 250, "limit": 1, "period": "day"},
	{"id": "shards", "give": {"shards": 3}, "price": 200, "limit": 5, "period": "week"},
	{"id": "ssr", "give": {"ssr_shards": 1}, "price": 600, "limit": 2, "period": "week"},
]
const SHOP_NAMES := {"gold": "골드 30,000", "equip": "장비 상자", "dia": "다이아 50", "ticket": "다이아 모집권 1장", "shards": "영웅 조각 3개",
	"ssr": "SSR 영웅 조각 1개"}


## 포인트 → {id, name, min, next(다음 등급 포인트, 없으면 -1), color, index}
static func tier_of(points: int) -> Dictionary:
	var i := 0
	while i + 1 < TIERS.size() and points >= int(TIERS[i + 1][2]):
		i += 1
	return {"id": TIERS[i][0], "name": TIERS[i][1], "min": TIERS[i][2], "next": TIERS[i + 1][2] if i + 1 < TIERS.size() else -1, "color": TIERS[i][3], "index": i}


static func tier_color(id: String) -> Color:
	for t in TIERS:
		if t[0] == id:
			return t[3]
	return TIERS[0][3]


static func win_gain(me: int, opp: int) -> int:
	return WIN_BASE + clampi(roundi((opp - me) / WIN_DIFF_DIV), -WIN_DIFF_CAP, WIN_DIFF_CAP)


static func loss_of(me: int) -> int:
	return mini(LOSS, maxi(0, me))


## 보유 병사 → 총력전 병사(높은 티어부터, 같으면 병종 이름 순, 합 SOLDIER_CAP).
static func pick_soldiers(owned: Dictionary) -> Dictionary:
	var keys: Array = owned.keys().filter(func(k): return int(owned[k]) > 0)
	keys.sort_custom(func(a, b):
		var ta := int(str(a).get_slice(":", 1))
		var tb := int(str(b).get_slice(":", 1))
		return ta > tb or (ta == tb and str(a) < str(b)))
	var out := {}
	var left := SOLDIER_CAP
	for k in keys:
		var n := mini(left, int(owned[k]))
		if n > 0:
			out[k] = n
		left -= n
		if left <= 0:
			break
	return out


static func soldier_count(s: Dictionary) -> int:
	var n := 0
	for k in s:
		n += int(s[k])
	return n

extends RefCounted
## 상점 그림(디자인 보강 6번, 2026-10-07): Meshy로 그린 128 px 아이콘 18개(assets/ui/shop/<이름>.png — dev/meshy/shop_icons.py가 자른다).
## 다이아 더미 dia_1~dia_6(작은 것 → 금 상자), 선물 gift·gift_big, 왕관 crown, 모집권 ticket·tickets(묶음), 장비 상자 chest_equip,
## 던전 입장권 key_gold·key_equip·key_ticket, 주머니 pouch_gold·pouch_res, 자원 더미 res_pile.
## 상점 카드·다이아 충전·PVP 상점·가방 주머니·출석 보상 칸이 쓴다. 그림이 없으면 draw()가 false → 부르는 쪽이 예전 벡터 그림을 그린다.

const DIR := "res://assets/ui/shop/"
const NAMES := ["dia_1", "dia_2", "dia_3", "dia_4", "dia_5", "dia_6", "gift", "gift_big", "crown", "ticket", "tickets", "chest_equip",
	"key_gold", "key_equip", "key_ticket", "pouch_gold", "pouch_res", "res_pile"]
const PACK_ICONS := {"monthly": "dia_2", "monthly_plus": "crown", "pkg_starter": "gift_big", "pkg_daily": "dia_3", "pkg_weekly": "dia_4",
	"pkg_growth": "dia_6"}  # 상점 [패키지] 카드 그림(iap_items id → 그림 이름)
const HOT_ICON := "dia_5"  # 핫딜 카드(금 보물 상자)
const FILL := 1.12  # 벡터 아이콘 크기 s 대비 그림 한 변(물체는 그 92%라 벡터 그림과 비슷한 크기)

static var _tex := {}


## 이름의 그림. 모르는 이름이거나 파일이 없으면 null.
static func texture(name: String) -> Texture2D:
	if not _tex.has(name):
		var path := DIR + name + ".png"
		_tex[name] = load(path) if name in NAMES and ResourceLoader.exists(path) else null
	return _tex[name]


## ctr 가운데에 크기 s(벡터 아이콘과 같은 기준)로 그린다. 그림이 없으면 아무것도 안 그리고 false.
static func draw(ci: CanvasItem, name: String, ctr: Vector2, s: float) -> bool:
	var tex := texture(name)
	if tex == null:
		return false
	var side := s * FILL
	ci.draw_texture_rect(tex, Rect2(ctr - Vector2(side, side) / 2.0, Vector2(side, side)), false)
	return true


## 던전 입장권 보상 키(keys_gold·keys_equip·keys_ticket) → 그림 이름. 열쇠가 아니면 "".
static func key_name(reward: Dictionary) -> String:
	for k in ["gold", "equip", "ticket"]:
		if reward.has("keys_" + k):
			return "key_" + k
	return ""

extends RefCounted
## 맵·성 기하 상수. 몬스터·스테이지·영웅·자원·설정 수치는 data/*.csv(GameData)에 있다.

const Lang := preload("res://scripts/lang.gd")

# --- 맵·성 기하 (개정 2) ---
const TILE := 2.0                     # 격자 타일 한 칸 (미터). 성 내부 넓이는 성채 단계 표(GameData.interior_half, 개정 12)
const WALL_T := 3.0                   # 성벽 두께 (1.5타일 — 사용자 2026-10-23 "성벽 위 영웅이 위치하는 부분 두께를 좀 두껍게, 터치하기가 불편해": 2 → 3 m, 바깥으로)
const WALL_H := 3.0                   # 성벽 높이 = 성벽 위 발판 높이
const GATE_W := 4.0                   # 성문 폭 (2타일)
const TOWER_SIZE := 4.0               # 모서리 탑 한 변(성벽이 두꺼워진 만큼 +1 m — 성벽 위 길 끝 자리는 그대로)
const MAP_HALF := 120.0                # 바닥 절반 크기
const SPAWN_MARGIN := 40.0            # 성벽 바깥면에서 스폰 지점까지
const SPAWN_SPREAD := 6.0             # 스폰 지점 좌우 흩어짐 (±)
const GATE_FRONT_OFFSET := 1.5        # 성벽 바깥면에서 성문 앞 자리까지
const GATE_FRONT_SLOTS := [0.0, -1.6, 1.6]      # 성문 앞 자리 좌우 오프셋
const WALL_TOP_SLOTS := [-4.0, 4.0, -8.0, 8.0]  # 성벽 위 자리 좌우 오프셋 (성문 위는 비움)
const STAIR_W := 2.0      # 계단 폭(성벽 안쪽 면에 붙은 1타일 띠)
const STAIR_GAP := 0.5    # 성문 가장자리 ~ 계단 윗단
const STAIR_RUN := 6.0    # 계단 수평 길이(윗단 → 아랫단, 성문 반대 방향)
const STAIR_STEPS := 8    # 계단 단 수(시각)
const CAMERA_SIZE_DEFAULT := 46.0     # 직교 카메라 가로 폭(미터). 아트 방향: 영웅이 화면에서 ~34 px(720 폭) — 네 성문 전투가 다 보이는 가장 가까운 줌
const CAMERA_SIZE_MIN := 16.0
const CAMERA_SIZE_MAX := 150.0

## 건물 배치 (플레이스홀더). cell = 최소 모서리 타일 좌표, size = 타일 수. 성 중심이 타일 경계 (0,0).
## 레벨 1 내부 타일 범위 -10..9. 성채 외 건물은 벽 쪽 2칸 여유(-8..7: 계단 띠 + 성문 안쪽↔계단 앞 통로)를 두고 십자 도로(-1·0)를 피한다.
static var BUILDINGS := [
	{"id": "keep", "name": Lang.t("balance.buildings.keep.name"), "cell": Vector2i(-2, -2), "size": Vector2i(4, 4)},
	{"id": "barracks", "name": Lang.t("balance.buildings.barracks.name"), "cell": Vector2i(2, -8), "size": Vector2i(3, 3)},
	{"id": "archery", "name": Lang.t("balance.buildings.archery.name"), "cell": Vector2i(5, -8), "size": Vector2i(3, 3)},  # 개정 13 병사 건물
	{"id": "stable", "name": Lang.t("balance.buildings.stable.name"), "cell": Vector2i(-8, -8), "size": Vector2i(3, 3)},
	{"id": "tavern", "name": Lang.t("balance.buildings.tavern.name"), "cell": Vector2i(5, -5), "size": Vector2i(3, 3)},
	{"id": "lab", "name": Lang.t("balance.buildings.lab.name"), "cell": Vector2i(-5, -8), "size": Vector2i(3, 3)},
	{"id": "houses", "name": Lang.t("balance.buildings.houses.name"), "cell": Vector2i(-8, -5), "size": Vector2i(3, 3)},
	{"id": "lumber", "name": Lang.t("balance.buildings.lumber.name"), "cell": Vector2i(2, 5), "size": Vector2i(3, 3)},
	{"id": "quarry", "name": Lang.t("balance.buildings.quarry.name"), "cell": Vector2i(5, 2), "size": Vector2i(3, 3)},
	{"id": "farm", "name": Lang.t("balance.buildings.farm.name"), "cell": Vector2i(-5, 5), "size": Vector2i(3, 3)},
	# 2026-10-13 성채 레벨로 여는 새 건물: 기본 자리 없음(처음 지을 때 [건설]로 자리를 고른다 — 서버 DEFAULT_CELLS에도 없다)
	{"id": "warehouse", "name": Lang.t("balance.buildings.warehouse.name"), "size": Vector2i(3, 3)},
	{"id": "goldmine", "name": Lang.t("balance.buildings.goldmine.name"), "size": Vector2i(3, 3)},
	{"id": "forge", "name": Lang.t("balance.buildings.forge.name"), "size": Vector2i(3, 3)},
	{"id": "guild_hall", "name": Lang.t("balance.buildings.guild_hall.name"), "size": Vector2i(3, 3)},
	{"id": "watchtower", "name": Lang.t("balance.buildings.watchtower.name"), "size": Vector2i(3, 3)},
	{"id": "dispatch", "name": Lang.t("balance.buildings.dispatch.name"), "size": Vector2i(3, 3)},  # 의뢰(파견) — 의뢰 기능은 따로
]

## 상인 자리 (개정 7). 막사·벌목장·채석장 사이 빈 터(십자 도로 밖). 수레는 상인 +X 쪽.
const MERCHANT_POS := Vector3(-5.5, 0, 6.5)  # 성채 정문 앞 왼쪽 — 벌목장·채석장 말풍선과 화면에서 겹치지 않는 자리
const MERCHANT_CART_OFFSET := Vector3(2.0, 0, 0)
const MERCHANT_RADIUS := 0.6


## 자유 건설(사용자 2026-10-13 "건물을 선택하고 내가 원하는 공간에다 건물을 짓는"): 성채(가운데 고정)를 뺀 건물은 성 안 격자 어디에나 짓는다.
## 위 BUILDINGS의 cell은 기본 자리(옛 저장·이미 지은 건물). 지금 자리는 Economy.layout이 정하고 Economy가 active에 맞춘다.
## 자리 규칙(placement_block — 서버 rules.placementBlock과 같다): 성 내부 벽 쪽 2타일(계단 띠 + 성문 안쪽 통로) 밖, 십자 도로(-1·0줄) 밖,
## 상인 자리(KEEP_OUT) 밖, 다른 건물과 겹치지 않음. 영웅·병사·괴물 길은 이 칸들 위로만 다닌다(테스트).
const WALL_MARGIN_TILES := 2
const KEEP_OUT := [Rect2i(-4, 2, 3, 2)]  # 상인·수레 — 타일(병사 광장은 없앴다: 병사는 성채 문으로 나온다 — 사용자 2026-10-18)
const FIXED := ["keep"]  # 옮기거나 새로 놓지 않는 건물
static var PLACE_TEXT := {  # placement_block 이유 → 안내 문구
	"out": Lang.t("balance.place_text.out"),
	"road": Lang.t("balance.place_text.road"),
	"square": Lang.t("balance.place_text.square"),
	"overlap": Lang.t("balance.place_text.overlap"),
	"fixed": Lang.t("balance.place_text.fixed"),
}

static var active := {}  # 건물 id → 지금 칸(지어졌거나 자리를 잡은 건물만). Economy가 맞춘다. 비었고 active_set이 false면 기본 배치
static var active_set := false


## 건물 id의 지금 부지 칸(왼쪽 위 모서리 타일). 자리를 잡지 않았으면 기본 칸.
static func cell_of(id: String) -> Vector2i:
	if active.has(id):
		return active[id]
	return building(id).get("cell", Vector2i.ZERO)


## 건물 id 부지 가운데(월드, y = 0).
static func center_of(id: String) -> Vector3:
	var b := building(id)
	var c := cell_of(id)
	return Vector3((c.x + b.size.x / 2.0) * TILE, 0, (c.y + b.size.y / 2.0) * TILE)


## 지금 성 안에 있는 건물 부지 [{id, cell, size}] — 길 막기(formation.clamp_push)·말풍선 자리. Economy가 맞추기 전(테스트)은 기본 자리가 있는 건물 전부.
## 겹침 해소가 유닛이 밀릴 때마다(전투 중 프레임당 수백 번) 부르므로 active가 바뀔 때만 다시 만든다(전엔 매번 건물 표를 다시 읽어
## 겹침 해소가 3배 무거웠다 — 발열). 돌려준 배열은 고치지 말 것.
static var _plots := []
static var _plots_key := -1


static func plots() -> Array:
	var key := hash([active_set, active])
	if key != _plots_key:
		_plots = _build_plots()
		_plots_key = key
	return _plots


static func _build_plots() -> Array:
	var out := []
	if not active_set:
		for b in BUILDINGS:
			if b.has("cell"):
				out.append({"id": b.id, "cell": b.cell, "size": b.size})
		return out
	for b in entries():
		if active.has(b.id):
			out.append({"id": b.id, "cell": active[b.id], "size": b.size})
	return out


## 모든 건물 항목(BUILDINGS + 자원 건물 2번째 채부터 "lumber#2" …, GameData.building_keys 순서) — 성 안에 세울 수 있는 것 전부.
static func entries() -> Array:
	var out := []
	for k in load("res://scripts/game_data.gd").building_keys():  # game_data.gd가 이 파일을 preload한다 — 순환을 피해 실행 때 읽는다
		var b := building(k)
		if not b.is_empty():
			out.append(b)
	return out


## id 건물을 cell에 둘 수 없는 이유("" = 된다). half_tiles = 성 내부 한 변 타일 수의 절반, others = 다른 건물 id → 칸(자기 자신은 무시).
static func placement_block(id: String, cell: Vector2i, half_tiles: int, others: Dictionary) -> String:
	var b := building(id)
	if b.is_empty() or FIXED.has(id):
		return "fixed"
	return rect_block(Rect2i(cell, b.size), half_tiles, others, id)


## 타일 묶음 r을 쓸 수 없는 이유("" = 된다). 자리 고르기 바닥 칸 표시(placement.gd)는 1×1로 묻는다. skip = 겹침에서 뺄 건물.
static func rect_block(r: Rect2i, half_tiles: int, others: Dictionary, skip := "") -> String:
	var m := half_tiles - WALL_MARGIN_TILES
	if not Rect2i(-m, -m, 2 * m, 2 * m).encloses(r):
		return "out"
	if r.intersects(Rect2i(-1, -half_tiles, 2, 2 * half_tiles)) or r.intersects(Rect2i(-half_tiles, -1, 2 * half_tiles, 2)):
		return "road"
	for k in KEEP_OUT:
		if r.intersects(k):
			return "square"
	for oid in others:
		if oid != skip and r.intersects(Rect2i(others[oid], building(oid).get("size", Vector2i(3, 3)))):  # 모르는 키는 서버 plotSize처럼 3×3
			return "overlap"
	return ""


## 건물 항목. 키 "종류#n"(n번째 채)은 그 종류 항목의 복사본(id = 키, 이름 "벌목장 2", 기본 자리 없음).
static func building(id: String) -> Dictionary:
	var t := id.get_slice("#", 0)
	for b in BUILDINGS:
		if b.id == t:
			if t == id:
				return b
			var c: Dictionary = b.duplicate()
			c.erase("cell")
			c.id = id
			c.name = "%s %s" % [b.name, id.get_slice("#", 1)]
			return c
	return {}

extends RefCounted
## 맵·성 기하 상수. 몬스터·스테이지·영웅·자원·설정 수치는 data/*.csv(GameData)에 있다.

# --- 맵·성 기하 (개정 2) ---
const TILE := 2.0                     # 격자 타일 한 칸 (미터). 성 내부 넓이는 성채 단계 표(GameData.interior_half, 개정 12)
const WALL_T := 2.0                   # 성벽 두께 (1타일)
const WALL_H := 3.0                   # 성벽 높이 = 성벽 위 발판 높이
const GATE_W := 4.0                   # 성문 폭 (2타일)
const TOWER_SIZE := 3.0               # 모서리 탑 한 변
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
const BUILDINGS := [
	{"id": "keep", "name": "성채", "cell": Vector2i(-2, -2), "size": Vector2i(4, 4)},
	{"id": "barracks", "name": "보병 막사", "cell": Vector2i(2, -8), "size": Vector2i(3, 3)},
	{"id": "archery", "name": "궁병 훈련소", "cell": Vector2i(5, -8), "size": Vector2i(3, 3)},  # 개정 13 병사 건물
	{"id": "stable", "name": "기병 마구간", "cell": Vector2i(-8, -8), "size": Vector2i(3, 3)},
	{"id": "tavern", "name": "주점", "cell": Vector2i(5, -5), "size": Vector2i(3, 3)},
	{"id": "lab", "name": "연구소", "cell": Vector2i(-5, -8), "size": Vector2i(3, 3)},
	{"id": "houses", "name": "민가", "cell": Vector2i(-8, -5), "size": Vector2i(3, 3)},
	{"id": "lumber", "name": "벌목장", "cell": Vector2i(2, 5), "size": Vector2i(3, 3)},
	{"id": "quarry", "name": "채석장", "cell": Vector2i(5, 2), "size": Vector2i(3, 3)},
	{"id": "farm", "name": "농장", "cell": Vector2i(-5, 5), "size": Vector2i(3, 3)},
	# 2026-10-13 성채 레벨로 여는 새 건물: 기본 자리 없음(처음 지을 때 [건설]로 자리를 고른다 — 서버 DEFAULT_CELLS에도 없다)
	{"id": "warehouse", "name": "창고", "size": Vector2i(3, 3)},
	{"id": "goldmine", "name": "금광", "size": Vector2i(3, 3)},
	{"id": "forge", "name": "대장간", "size": Vector2i(3, 3)},
	{"id": "guild_hall", "name": "길드 회관", "size": Vector2i(3, 3)},
	{"id": "watchtower", "name": "망루", "size": Vector2i(3, 3)},
]

## 상인 자리 (개정 7). 막사·벌목장·채석장 사이 빈 터(십자 도로 밖). 수레는 상인 +X 쪽.
const MERCHANT_POS := Vector3(-5.5, 0, 6.5)  # 성채 정문 앞 광장 왼쪽 — 벌목장·채석장 말풍선과 화면에서 겹치지 않는 자리
const MERCHANT_CART_OFFSET := Vector3(2.0, 0, 0)
const MERCHANT_RADIUS := 0.6

## 성채 앞 병사 자리(개정 13 §7): 성채 정문(+Z) 앞 광장의 격자 x ∈ SOLDIER_X, z ∈ SOLDIER_Z, 간격 SOLDIER_GAP(11 × 6 = 66칸).
const SOLDIER_X := Vector2(-1.5, 7.5)
const SOLDIER_Z := Vector2(4.6, 9.4)
const SOLDIER_GAP := 0.9


## 자유 건설(사용자 2026-10-13 "건물을 선택하고 내가 원하는 공간에다 건물을 짓는"): 성채(가운데 고정)를 뺀 건물은 성 안 격자 어디에나 짓는다.
## 위 BUILDINGS의 cell은 기본 자리(옛 저장·이미 지은 건물). 지금 자리는 Economy.layout이 정하고 Economy가 active에 맞춘다.
## 자리 규칙(placement_block — 서버 rules.placementBlock과 같다): 성 내부 벽 쪽 2타일(계단 띠 + 성문 안쪽 통로) 밖, 십자 도로(-1·0줄) 밖,
## 성채 앞 병사 광장·상인 자리(KEEP_OUT) 밖, 다른 건물과 겹치지 않음. 영웅·병사·괴물 길은 이 칸들 위로만 다닌다(테스트).
const WALL_MARGIN_TILES := 2
const KEEP_OUT := [Rect2i(-1, 2, 5, 3), Rect2i(-4, 2, 3, 2)]  # 병사 광장(SOLDIER_X·Z + 발밑 0.45 m), 상인·수레 — 타일
const FIXED := ["keep"]  # 옮기거나 새로 놓지 않는 건물
const PLACE_TEXT := {  # placement_block 이유 → 안내 문구
	"out": "성벽에 너무 가깝습니다",
	"road": "길 위에는 지을 수 없습니다",
	"square": "광장에는 지을 수 없습니다",
	"overlap": "다른 건물과 겹칩니다",
	"fixed": "옮길 수 없는 건물입니다",
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
static func plots() -> Array:
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
		if oid != skip and r.intersects(Rect2i(others[oid], building(oid).get("size", Vector2i.ONE))):
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

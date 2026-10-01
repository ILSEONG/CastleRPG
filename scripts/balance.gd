extends RefCounted
## 밸런스 상수와 스케일 함수. 튠은 여기서만.

const CASTLE_HP := 1000.0
const HERO_SLOTS := [4, 8, 12]   # index = keep_level - 1
const MAX_LIVE_MONSTERS := 120
const COUNTDOWN_SEC := 3.0
const RESULT_SEC := 2.0
const WAVE_GAP_SEC := 8.0
const SPAWN_SPACING_SEC := 0.5

const MONSTER := {
	"grunt": {
		"hp": 60.0, "atk": 10.0, "speed": 2.5, "range": 1.2, "atk_interval": 1.0, "aggro": 6.0,
		"scale": 1.0,
	},
	"epic_boss": {
		"hp": 400.0, "atk": 20.0, "speed": 1.8, "range": 1.8, "atk_interval": 1.2, "aggro": 8.0,
		"scale": 1.6,
	},
}

# --- 맵·성 기하 (개정 2) ---
const TILE := 2.0                     # 격자 타일 한 칸 (미터)
const INTERIOR_TILES := [20, 24, 28]  # 성 내부 한 변 타일 수. index = keep_level - 1
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
const CAMERA_SIZE_DEFAULT := 66.0     # 직교 카메라 가로 폭(미터)
const CAMERA_SIZE_MIN := 16.0
const CAMERA_SIZE_MAX := 150.0

const HERO_ROLES := {
	"warrior": {
		"name": "전사", "hp": 400.0, "atk": 30.0, "range": 1.8, "atk_interval": 0.8, "speed": 6.0, "aggro": 8.0,
	},
	"archer": {
		"name": "궁수", "hp": 220.0, "atk": 20.0, "range": 9.0, "atk_interval": 1.0, "speed": 6.0, "aggro": 12.0,
	},
}
const HERO_ROSTER := ["warrior", "archer"]  # 영웅 i의 역할 = HERO_ROSTER[i % 2]

## 건물 배치 (플레이스홀더). cell = 최소 모서리 타일 좌표, size = 타일 수. 성 중심이 타일 경계 (0,0).
## 레벨 1 내부 타일 범위 -10..9. 성채 외 건물은 벽 쪽 2칸 여유(-8..7: 계단 띠 + 성문 안쪽↔계단 앞 통로)를 두고 십자 도로(-1·0)를 피한다.
const BUILDINGS := [
	{"id": "keep", "name": "성채", "cell": Vector2i(-2, -2), "size": Vector2i(4, 4)},
	{"id": "barracks", "name": "막사", "cell": Vector2i(2, -8), "size": Vector2i(3, 3)},
	{"id": "tavern", "name": "주점", "cell": Vector2i(5, -5), "size": Vector2i(3, 3)},
	{"id": "lab", "name": "연구소", "cell": Vector2i(-5, -8), "size": Vector2i(3, 3)},
	{"id": "houses", "name": "민가", "cell": Vector2i(-8, -5), "size": Vector2i(3, 3)},
	{"id": "lumber", "name": "벌목장", "cell": Vector2i(2, 5), "size": Vector2i(3, 3)},
	{"id": "quarry", "name": "채석장", "cell": Vector2i(5, 2), "size": Vector2i(3, 3)},
	{"id": "farm", "name": "농장", "cell": Vector2i(-5, 5), "size": Vector2i(3, 3)},
]

## 상인 자리 (개정 7). 막사·벌목장·채석장 사이 빈 터(십자 도로 밖). 수레는 상인 +X 쪽.
const MERCHANT_POS := Vector3(3.5, 0, 6.5)
const MERCHANT_CART_OFFSET := Vector3(2.0, 0, 0)
const MERCHANT_RADIUS := 0.6


static func gate_hp_max(level: int) -> float:
	return 400.0 * level


static func hero_slots(keep_level: int) -> int:
	return HERO_SLOTS[clampi(keep_level, 1, HERO_SLOTS.size()) - 1]


static func hp_scale(stage: int) -> float:
	return 1.0 + 0.25 * (stage - 1)


static func atk_scale(stage: int) -> float:
	return 1.0 + 0.15 * (stage - 1)


static func idle_interval(_stage: int) -> float:
	return 4.0


static func wave_count(stage: int) -> int:
	return 3 + floori(stage / 3.0)


static func wave_size(stage: int, _wave_index: int) -> int:
	return 6 + 2 * stage


static func interior_half(keep_level: int) -> float:
	return INTERIOR_TILES[clampi(keep_level, 1, INTERIOR_TILES.size()) - 1] * TILE / 2.0


static func hero_role(index: int) -> String:
	return HERO_ROSTER[index % HERO_ROSTER.size()]


static func building(id: String) -> Dictionary:
	for b in BUILDINGS:
		if b.id == id:
			return b
	return {}

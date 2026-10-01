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
const CAMERA_SIZE_DEFAULT := 66.0     # 직교 카메라 가로 폭(미터)
const CAMERA_SIZE_MIN := 16.0
const CAMERA_SIZE_MAX := 150.0

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
const MERCHANT_POS := Vector3(-5.5, 0, 6.5)  # 성채 정문 앞 광장 왼쪽 — 벌목장·채석장 말풍선과 화면에서 겹치지 않는 자리
const MERCHANT_CART_OFFSET := Vector3(2.0, 0, 0)
const MERCHANT_RADIUS := 0.6


static func building(id: String) -> Dictionary:
	for b in BUILDINGS:
		if b.id == id:
			return b
	return {}

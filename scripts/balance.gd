extends RefCounted
## 밸런스 상수와 스케일 함수. 튠은 여기서만.

const CASTLE_HP := 1000.0
const CASTLE_SIZE := 10.0        # 성벽 한 변 (미터)
const GATE_STAND_OFFSET := 1.5   # 성문 바깥 영웅 자리까지 거리
const SPAWN_DISTANCE := 18.0     # 성 중심에서 스폰 지점까지
const HERO_SLOTS := [4, 8, 12]   # index = keep_level - 1
const MAX_LIVE_MONSTERS := 120
const COUNTDOWN_SEC := 3.0
const RESULT_SEC := 2.0
const WAVE_GAP_SEC := 8.0
const SPAWN_SPACING_SEC := 0.5

const HERO := {
	"hp": 300.0, "atk": 25.0, "range": 3.0, "atk_interval": 0.8, "speed": 6.0,
}

const MONSTER := {
	"grunt": {
		"hp": 60.0, "atk": 10.0, "speed": 2.5, "range": 1.2, "atk_interval": 1.0,
		"scale": 1.0, "color": Color(0.85, 0.3, 0.3),
	},
	"epic_boss": {
		"hp": 400.0, "atk": 20.0, "speed": 1.8, "range": 1.8, "atk_interval": 1.2,
		"scale": 2.5, "color": Color(0.6, 0.1, 0.5),
	},
}


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

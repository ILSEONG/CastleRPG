extends RefCounted
## 길드전(공성전) 수치·규칙 한 곳(오토로드 의존 없음). 서버 server/src/guild_war.ts와 같은 값·식이다.
## 기본값은 2026-10-06 사용자에게 제안한 것(바꾸려면 여기와 서버 둘 다): 한 주 한 상대(월요일 리셋에 새 상대), 공성 전투 하루 1번 ·
## 첫 길드원이 들어가면 시작해 BATTLE_SEC초 · 그 사이 누구나 합류, 점수 = 수비 영웅 처치 1 · 성문 20 · 성채 100, 주간 보상(승리·패배).
## 길드원 = 15명(길드 6레벨부터 20명 — 길드 쪽 규칙). 길드원 한 명 = 영웅 4명(공격 분대 / 수비 분대).

const BATTLE_SEC := 600.0
const RESPAWN_SEC := 30.0  # 공격 영웅이 쓰러지면 진영에서 다시 일어나기까지(수비 영웅은 그 주 동안 다시 안 일어난다)
const ATTACK_LIVES := 2  # 공격 영웅 목숨(전투 하나에서 쓰러져도 ATTACK_LIVES - 1번 다시 일어난다). 모두 다 쓰면 전투가 일찍 끝난다
const SQUAD := 4  # 길드원 한 명이 내는 영웅 수
const PTS_KILL := 1
const PTS_GATE := 20
const PTS_KEEP := 100
const REWARD_WIN := {"coins": 300, "diamonds": 100}
const REWARD_LOSE := {"coins": 100, "diamonds": 30}
const GATE_HP_SHARE := 3.0  # 성문 체력 = 그 면 수비 영웅 최대 체력 합 × 이만큼(수비가 셀수록 성문도 단단하다)
const KEEP_HP_SHARE := 6.0  # 성채 체력 = 수비 영웅 전체 최대 체력 합 × 이만큼
const MIN_GATE_HP := 3000.0
const MIN_KEEP_HP := 8000.0
const DEF_HP_MULT := 1.5  # 수성 보너스: 수비 영웅 체력·공격 배율(성벽 뒤에서 싸운다). 앱만 쓴다(서버는 전투를 계산하지 않는다)
const DEF_ATK_MULT := 1.3
const KEEP_LEVEL := 9  # 공성 성 크기(성채 레벨 → GameData.interior_half). 9 = 24칸 단계(단계 표 개편 전 레벨 6과 같은 크기)
const CAMP_D := 24.0  # 공격 진영: 성벽 바깥면에서 이 거리
const SIDE_NAMES := ["북문", "동문", "남문", "서문"]


static func gate_hp_max(lane_hp_sum: float) -> float:
	return maxf(MIN_GATE_HP, roundf(lane_hp_sum * GATE_HP_SHARE))


static func keep_hp_max(all_hp_sum: float) -> float:
	return maxf(MIN_KEEP_HP, roundf(all_hp_sum * KEEP_HP_SHARE))


## 전투 결과 → 점수.
static func points(kills: int, gates: int, keep: bool) -> int:
	return kills * PTS_KILL + gates * PTS_GATE + (PTS_KEEP if keep else 0)


## 수비 분대(길드원 i번째)가 지키는 면: 길드원을 차례로 네 면에 나눈다.
static func lane_of(i: int) -> int:
	return i % 4

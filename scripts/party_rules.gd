extends RefCounted
## 파티 퀘스트 수치(사용자 2026-10-15). 서버 server/src/party.ts와 같다.
## 리치: 성주 4명이 실시간으로 영웅 1명씩(직접 조종) — 보상 반지. 거미 여왕: 성주 3명이 병사 4마리씩(조종 없음) — 보상 목걸이.
## 난이도 4단계(사용자): 보통 = 쉬움 ×10, 어려움 = 보통 ×5, 매우 어려움 = 어려움 ×3 — 적 HP·공격 모두에 곱한다.
## 나머지(보스 기본 능력치·제한 시간·하루 보상 수·등급 확률·AI 성주 대기)는 Claude 기본값(바꿀 수 있다).

const Lang := preload("res://scripts/lang.gd")

const QUESTS := ["lich", "spider"]
static var NAMES := {"lich": "리치의 무덤", "spider": "거미 여왕의 둥지"}
static var BOSS_NAMES := {"lich": "리치", "spider": "거미 여왕"}
const SEATS := {"lich": 4, "spider": 3}
const SOLDIERS_PER := 4
const DIFFS := 4
const DIFF_MULT := [1.0, 10.0, 50.0, 150.0]
static var DIFF_NAMES := ["쉬움", "보통", "어려움", "매우 어려움"]
const DIFF_COLORS := [Color(0.30, 0.62, 0.32), Color(0.24, 0.48, 0.78), Color(0.78, 0.42, 0.16), Color(0.72, 0.16, 0.20)]
const ACCESSORY := {"lich": "ring", "spider": "necklace"}
const BOSS := {"lich": {"hp": 14000.0, "atk": 70.0}, "spider": {"hp": 9000.0, "atk": 40.0}}  # 쉬움 기준
const TIME_LIMIT := {"lich": 180.0, "spider": 180.0}
const MIN_CLEAR_SEC := 2.0  # 서버는 여기에 힘 검사(초당 피해 × 걸린 시간 × 8 ≥ 보스 HP)를 더 본다
const REWARD_CLEARS := 3
const DROP_WEIGHTS := [[50, 35, 13, 2, 0, 0], [20, 35, 30, 12, 3, 0], [5, 20, 35, 28, 10, 2], [0, 5, 25, 40, 22, 8]]  # N R SR SSR UR LR
const CONFIRM_SEC := 15.0
const BOT_WAIT_SEC := 30.0

## 졸개(쉬움 기준 — 난이도 배수를 똑같이 곱한다). 리치: 해골 병사(되살리기 스킬)·영혼 수정(수확 스킬), 거미 여왕: 거미 부하(계속 기어 나온다)·알(부화 전에 깨야 한다).
const MINION := {
	"skeleton": {"hp": 420.0, "atk": 12.0, "speed": 3.2, "range": 1.4, "atk_interval": 1.2, "aggro": 30.0, "scale": 1.0},
	"spiderling": {"hp": 70.0, "atk": 5.0, "speed": 4.6, "range": 1.1, "atk_interval": 0.9, "aggro": 40.0, "scale": 0.55},
	"spider_egg": {"hp": 260.0, "atk": 0.0, "speed": 0.0, "range": 0.1, "atk_interval": 9.0, "aggro": 0.0, "scale": 0.8},
	"soul_crystal": {"hp": 700.0, "atk": 0.0, "speed": 0.0, "range": 0.1, "atk_interval": 9.0, "aggro": 0.0, "scale": 1.0},  # 실제 체력 = 리치 최대 체력 × lich.CRYSTAL_HP
}


static func boss_stats(quest: String, diff: int) -> Dictionary:
	var m: float = DIFF_MULT[clampi(diff, 1, DIFFS) - 1]
	return {"hp": float(BOSS[quest].hp) * m, "atk": float(BOSS[quest].atk) * m}


## 졸개 한 행(monster.setup_arena 모양) — 난이도 배수를 HP·공격에 곱한다.
static func minion_row(kind: String, diff: int) -> Dictionary:
	var m: float = DIFF_MULT[clampi(diff, 1, DIFFS) - 1]
	var row: Dictionary = MINION[kind].duplicate()
	row.kind = kind
	row.hp = float(row.hp) * m
	row.atk = float(row.atk) * m
	return row


## 그 난이도 장신구 등급 확률(%) {등급: %}(0인 등급은 뺀다).
static func drop_odds(diff: int) -> Dictionary:
	const GRADES := ["N", "R", "SR", "SSR", "UR", "LR"]
	var w: Array = DROP_WEIGHTS[clampi(diff, 1, DIFFS) - 1]
	var total := 0.0
	for x in w:
		total += float(x)
	var out := {}
	for i in GRADES.size():
		if float(w[i]) > 0.0:
			out[GRADES[i]] = float(w[i]) * 100.0 / total
	return out

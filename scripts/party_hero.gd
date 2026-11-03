extends "res://scripts/war_hero.gd"
## 파티 퀘스트 영웅(리치, party_battle.gd). 공성전 영웅(war_hero.gd) 그대로 — 성 없이(war_half = 0) 무덤 바닥에서 리치·졸개(그룹 "monsters")와 싸운다 —
## 에 하나를 더한다: 내가 조종하지 않는 영웅(AI 성주·자리를 비운 성주·[자동])은 보스 범위 예고(party.danger) 안에 서 있으면 가장 가까운 바깥으로 비켜선다.
## 사람처럼(2026-11-02 사용자 "AI영웅이 적의 스킬을 무조건 다 피하는거같아"): 범위마다 REACT_MIN~REACT_MAX초 늦게 알아채고, MISS 확률로 아예 못 본다.
## 굴림은 (판 seed, 범위 id, 자리)로 정해져 같은 판을 보는 기기마다 같다.
## 내가 이동·공격 명령을 준 영웅(commanded)은 비키지 않는다 — 플레이어가 직접 피한다. 표적은 영혼 수정이 있으면 수정부터(party.priority_target).

const DODGE_EVERY := 0.2
const REACT_MIN := 0.3
const REACT_MAX := 0.9
const MISS := 0.2

var party  # party_battle.gd
var seat := 0  # 이 영웅을 데려온 성주 자리
var _dodge_cd := 0.0
var _noticed := {}  # 범위 id → 알아채는 clock(못 보면 INF)


func _tick(delta: float) -> void:
	if not puppet and party != null and state != State.DEAD and not commanded:
		_dodge_cd -= delta
		if _dodge_cd <= 0.0:
			_dodge_cd = DODGE_EVERY
			var ready := []
			for id in party.zones_at(global_position, radius()):
				if not _noticed.has(id):
					_noticed[id] = _notice_at(int(id))
				if float(_noticed[id]) <= party.clock:
					ready.append(id)
			var out: Vector3 = party.escape_from(global_position, radius(), ready) if not ready.is_empty() else Vector3.INF
			if out != Vector3.INF:
				_path.clear()
				_path.append(out)
				_target = null
				_swing = null
	super._tick(delta)


func _notice_at(id: int) -> float:
	var r := RandomNumberGenerator.new()
	r.seed = hash([int(party.run.get("seed", 1)), id, seat])
	if r.randf() < MISS:
		return INF
	return float(party.clock) + r.randf_range(REACT_MIN, REACT_MAX)


## 영혼 수정·거미 알이 있으면 그것부터(깨지 않으면 판이 어려워진다).
func _find_target():
	if party != null:
		var p = party.priority_target(global_position)
		if p != null:
			return p
	return super._find_target()

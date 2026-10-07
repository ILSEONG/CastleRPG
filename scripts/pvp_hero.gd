extends "res://scripts/war_hero.gd"
## PVP 영웅(pvp_battle.gd). 공성전 영웅(war_hero.gd) 그대로 — 성 없이(war_half = 0) 들판에서 영웅·병사와 싸운다 — 에 두 가지를 바꾼다.
## 1) 그룹: team 0 = 아군 "heroes"(초록 HP 바·선택) + "pvp0", 적 "pvp1" / team 1 = 아군 "war_def" + "monsters"(빨간 HP 바) + "pvp1", 적 "pvp0".
##    적 그룹에 상대 영웅과 병사(pvp_soldier.gd)가 함께 있어 평타·스킬이 둘 다 맞힌다. 회복·오라는 영웅끼리.
## 2) 스킬 시점: 쿨이 찬 스킬은 battle.brain.cast_ok(이 영웅, 종류)가 좋다고 할 때 쓴다(hero_skills._begin이 묻는다).


## add_child 전에(setup_war 다음).
func setup_pvp() -> void:
	foes = "pvp1" if team == 0 else "pvp0"


func _ready() -> void:
	super._ready()
	add_to_group("pvp%d" % team)


func cast_ok(k: String) -> bool:
	return battle == null or battle.brain.cast_ok(self, k)

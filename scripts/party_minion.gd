extends "res://scripts/monster.gd"
## 파티 퀘스트 졸개(party_battle.gd가 낸다 — 능력치 PartyRules.minion_row × 난이도 배수). 종류마다 생김새만 다르고 싸움은 monster.gd 아레나 그대로.
## skeleton: 리치가 되살린 해골 병사(KayKit 해골 전사). spiderling: 새끼 거미(spider_model.gd, 작게 — 떼로 몰려온다).
## soul_crystal: 리치 영혼 수확의 수정(움직이지 않고 치지도 않는다 — 깨야 한다). spider_egg: 거미 알 주머니(HATCH_SEC 뒤 새끼 거미 HATCH_N마리로 깨어난다).

const SpiderModel := preload("res://scripts/spider_model.gd")
const PropModel := preload("res://scripts/prop_model.gd")

const HATCH_SEC := 8.0
const HATCH_N := 4
const STILL := ["soul_crystal", "spider_egg"]
const RADIUS := {"skeleton": 0.4, "spiderling": 0.42, "soul_crystal": 0.7, "spider_egg": 0.75}
const BAR_H := {"skeleton": 2.0, "spiderling": 0.9, "soul_crystal": 2.6, "spider_egg": 1.5}

var battle  # party_battle.gd
var hatch_left := HATCH_SEC


func _ready() -> void:
	match kind:
		"skeleton":
			look = "skeleton_warrior"
			super._ready()
			Fx.summon_in(get_parent(), global_position, Color(0.35, 1.0, 0.8), 1)
		"spiderling":
			_join()
			_model = SpiderModel.new()
			_model.queen = false
			_model.size = 0.55
			_model.crowd_lod = true
			add_child(_model)
		_:
			_join()
			_model = PropModel.new()
			_model.shape = "crystal" if kind == "soul_crystal" else "egg"
			add_child(_model)


func _join() -> void:
	add_to_group("monsters")
	add_to_group("crowd")


func _process(delta: float) -> void:
	if kind == "spider_egg" and not puppet and is_alive():
		hatch_left -= delta
		_model.pulse = 1.0 + 2.0 * clampf(1.0 - hatch_left / HATCH_SEC, 0.0, 1.0)
		if hatch_left <= 0.0 and battle != null:
			battle.hatch(self, HATCH_N)
			return
	super._process(delta)


func is_still() -> bool:
	return kind in STILL


func push_mass() -> float:
	return INF if is_still() else super.push_mass()


func radius() -> float:
	return float(RADIUS.get(kind, 0.4))


func bar_height() -> float:
	return float(BAR_H.get(kind, 2.0))


func bar_scale() -> float:
	return 0.6 if kind == "spiderling" else 1.0

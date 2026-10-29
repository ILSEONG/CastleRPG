extends RefCounted
## PVP 영웅 머리(pvp_battle.gd — 성 없는 들판). war_hero.gd가 부른다: pick_target(u)·blast_ok(u, m)·think(u), pvp_hero.gd가 cast_ok(u, k).
## 상대 AI(결투의 상대 팀, 총력전은 양쪽)와 결투에서 이동 명령을 받지 않은(자동) 내 영웅이 이 머리로 싸운다.
## 표적(사용자 2026-10-19 "표적 고르기와 역할 전술 AI는 없애줘"): 던전 전투와 같이 가장 가까운 적(영웅·병사)을 쫓아가 친다.
##  점수식(약한 적·팀 집중·치유사·아군 지키기·표적 유지)과 역할 전술(근접 앞줄·추격 포기, 원거리 뒷줄·뒷걸음, 암살자 우회, 탱커 지키기)은 없앴다.
##  이동 명령을 받은 내 영웅만 그 자리에서 aggro 안의 가장 가까운 적(던전·성과 같은 규칙).
## 스킬(cast_ok — 그대로): 광역은 표적 둘레에 적이 둘 이상이거나 표적 영웅이 반 아래일 때·적이 하나 남았을 때, 회복은 다친 아군이 있을 때,
## 방어·도발은 맞고 있을 때·적이 붙었을 때, 제어(기절·빙결·속박)는 영웅에게 — 조건이 안 맞아도 HOLD_MAX초가 지나면 쓴다(아끼다 못 쓰지 않게).

const Formation := preload("res://scripts/formation.gd")

const AOE_R := 3.5
const HOLD_MAX := 6.0
const AOE := ["meteor", "comet", "inferno", "poison_cloud", "blizzard", "tornado", "earthquake", "ground_slam", "frost_nova", "thunder_storm",
	"arrow_rain", "whirlwind", "shockwave", "starfall", "void_rift", "solar_flare", "abyss_hand", "lava_burst", "dragon_breath", "firespread",
	"wide_swing", "spear_sweep", "axe_volley", "volley", "crescent", "war_cry", "ice_spikes", "boomerang",
	"north_tide", "tiger_claw", "fox_fire", "nine_tails", "dragon_arrow", "azure_dragon", "time_stop", "time_collapse"]
const SELF_AOE := ["earthquake", "ground_slam", "whirlwind", "war_cry", "wide_swing", "spear_sweep", "crescent", "north_tide", "nine_tails"]
const DEFENSIVE := ["shield", "bulwark", "parry", "lunar_veil", "blood_rage", "turtle_ward", "tiger_avatar"]
const CONTROL := ["deep_freeze", "frost_chain", "snare", "shield_bash", "hex", "cheap_shot", "taunt"]
const SUPPORT := ["mass_heal", "sanctuary", "shield_ally", "phoenix_wing", "rebirth_flame"]

var battle  # pvp_battle.gd: units(team)
var _held := {}  # 영웅 id·스킬 → 처음 미룬 시각


func _init(p_battle) -> void:
	battle = p_battle


## 전투 시계(게임 초) — 배속·일시 정지와 같이 간다.
func _now() -> float:
	return float(battle.clock) if battle != null and battle.get("clock") != null else Time.get_ticks_msec() / 1000.0


func _alive_foes(u) -> Array:
	return u.get_tree().get_nodes_in_group(u.foes).filter(func(f): return f.is_alive())


func _alive_allies(u) -> Array:
	return battle.units(u.team).filter(func(a): return a.is_alive())


static func is_hero(f) -> bool:
	return f.get("kind") == "hero"


## 가장 가까운 적. 이동 명령을 받은 영웅은 그 자리(free_pos)에서 aggro(사거리가 더 길면 사거리) 안만.
func pick_target(u):
	var reach := INF
	if u.commanded:
		reach = maxf(float(u.def.aggro), float(u.def.range))
	var best = null
	var best_d := INF
	for f in _alive_foes(u):
		if reach < INF and Formation.flat_distance(u.free_pos, f.global_position) > reach:
			continue
		var d := Formation.flat_distance(u.global_position, f.global_position)
		if d < best_d:
			best_d = d
			best = f
	return best


func blast_ok(u, m) -> bool:
	if m == null or not is_instance_valid(m):
		return false
	var r: float = float(u._sk.aoe_blast[1]) if u._sk.has("aoe_blast") else 3.0
	return _near(u, m.global_position, r) >= 2 or m.hp_ratio() < 0.35 or _alive_foes(u).size() <= 1


func _near(u, at: Vector3, r: float) -> int:
	var n := 0
	for f in _alive_foes(u):
		if Formation.flat_distance(at, f.global_position) <= r:
			n += 1
	return n


## 쿨이 찬 스킬 k를 지금 쓸까(hero_skills._begin이 묻는다). 미루기 시작한 지 HOLD_MAX초가 지나면 그냥 쓴다.
func cast_ok(u, k: String) -> bool:
	var ok := _cast_ok(u, k)
	var key := "%d:%s" % [u.uid, k]
	if ok:
		_held.erase(key)
		return true
	var since: float = _held.get(key, -1.0)
	if since < 0.0:
		_held[key] = _now()
		return false
	if _now() - since >= HOLD_MAX:
		_held.erase(key)
		return true
	return false


func _cast_ok(u, k: String) -> bool:
	var t = u.current_target()
	var foes := _alive_foes(u)
	if k in AOE:
		var at: Vector3 = u.global_position if k in SELF_AOE or t == null else t.global_position
		return _near(u, at, AOE_R) >= 2 or foes.size() <= 1 or (t != null and is_hero(t) and t.hp_ratio() < 0.5)
	if k in SUPPORT:
		return _alive_allies(u).any(func(a): return a.hp_ratio() < 0.65)
	if k in DEFENSIVE:
		return u.hp_ratio() < 0.8 or _near(u, u.global_position, 3.0) >= 2
	if k in CONTROL:
		if k == "taunt":
			return _near(u, u.global_position, 5.0) >= 2 or _alive_allies(u).any(func(a): return a.role == "ranged" and a.hp_ratio() < 0.7)
		return t != null and is_hero(t)
	return true


## 0.25초마다: 자동 영웅은 자리에 묶이지 않는다(hold 끔 — 던전처럼 표적을 쫓는다). 이동 명령을 받은 영웅은 그 자리를 지킨다.
func think(u) -> void:
	if u.is_alive() and not u.commanded:
		u.hold = false

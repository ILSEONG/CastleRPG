extends RefCounted
## PVP 영웅 머리(pvp_battle.gd — 성 없는 들판). war_hero.gd가 부른다: pick_target(u)·blast_ok(u, m)·think(u), pvp_hero.gd가 cast_ok(u, k).
## 상대 AI(결투의 상대 팀, 총력전은 양쪽)는 이 머리로 싸우고, 결투에서 내가 이동 명령을 주지 않은 내 영웅도 같은 머리로 자동 전투한다.
## 표적 점수(클수록 먼저) = 처치 가치(초당 피해 ÷ 남은 체력, 체력이 반 아래면 더) × 팀 집중(FOCUS_BONUS — 한 팀이 한 표적을 함께)
##  × 지키기(내 원거리·약한 아군을 치는 적 — 근접은 PEEL_BONUS, 원거리는 절반) × 치유사(HEALER_BONUS) × 영웅(병사보다 HERO_BONUS)
##  × 지금 표적 유지(STICKY) ÷ (1 + 닿는 데 걸리는 초 × TRAVEL_W — 근접은 더 크게). 근접은 가까운 적부터 막고, 원거리는 사거리 안의 약한 적을 끝낸다.
## 자리(think, 0.25초마다):
##  - 원거리: 근접 적이 KITE_R 안에 붙으면 KITE_STEP m 물러난다(우리 근접 쪽으로). 쉬는 자리는 우리 근접 줄 뒤 BACK_D m.
##  - 근접: 쉬는 자리는 우리 원거리와 적 사이(앞줄). 적 근접이 우리 원거리를 노리면 지키기 점수로 그 적에게 간다.
## 스킬(cast_ok): 광역은 표적 둘레에 적이 둘 이상이거나 표적 영웅이 반 아래일 때·적이 하나 남았을 때, 회복은 다친 아군이 있을 때, 방어·도발은
## 맞고 있을 때·적이 붙었을 때, 제어(기절·빙결·속박)는 영웅에게 — 조건이 안 맞아도 HOLD_MAX초가 지나면 쓴다(아끼다 못 쓰지 않게).

const Formation := preload("res://scripts/formation.gd")

const FOCUS_BONUS := 1.6
const PEEL_BONUS := 1.9
const HEALER_BONUS := 1.4
const HERO_BONUS := 1.5
const LOW_HP_BONUS := 1.5
const STICKY := 1.3
const TRAVEL_W := 0.3
const WEAK_ALLY := 0.5
const FOCUS_SEC := 1.0
const KITE_R := 2.6
const KITE_STEP := 3.5
const KITE_CD := 1.4
const BACK_D := 3.5
const AOE_R := 3.5
const HOLD_MAX := 6.0
const HEALS := ["heal_aura", "mass_heal", "sanctuary", "resurrection", "shield_ally", "regen_aura", "battle_hymn", "howl"]
const AOE := ["meteor", "comet", "inferno", "poison_cloud", "blizzard", "tornado", "earthquake", "ground_slam", "frost_nova", "thunder_storm",
	"arrow_rain", "whirlwind", "shockwave", "starfall", "void_rift", "solar_flare", "abyss_hand", "lava_burst", "dragon_breath", "firespread",
	"wide_swing", "spear_sweep", "axe_volley", "volley", "crescent", "war_cry", "ice_spikes", "boomerang"]
const SELF_AOE := ["earthquake", "ground_slam", "whirlwind", "war_cry", "wide_swing", "spear_sweep", "crescent"]
const DEFENSIVE := ["shield", "bulwark", "parry", "lunar_veil", "blood_rage"]
const CONTROL := ["deep_freeze", "frost_chain", "snare", "shield_bash", "hex", "cheap_shot", "taunt"]
const SUPPORT := ["mass_heal", "sanctuary", "shield_ally"]

var battle  # pvp_battle.gd: units(team)
var _focus := {}  # 팀 → [표적, 정한 시각]
var _held := {}  # 영웅 id·스킬 → 처음 미룬 시각


func _init(p_battle) -> void:
	battle = p_battle


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _alive_foes(u) -> Array:
	return u.get_tree().get_nodes_in_group(u.foes).filter(func(f): return f.is_alive())


func _alive_allies(u) -> Array:
	return battle.units(u.team).filter(func(a): return a.is_alive())


static func dps_of(f) -> float:
	var d = f.get("def")
	if d == null:
		return 0.0
	return float(f.atk) / maxf(0.2, float(d.atk_interval))


static func is_healer(f) -> bool:
	var sk = f.get("_sk")
	if sk == null:
		return false
	for k in HEALS:
		if sk.has(k):
			return true
	return false


static func is_hero(f) -> bool:
	return f.get("kind") == "hero"


func pick_target(u):
	var foes := _alive_foes(u)
	if foes.is_empty():
		return null
	var origin: Vector3 = u.stand_position()
	var rng := float(u.def.range)
	var reach := INF
	if u.commanded:  # 이동 명령을 받은 내 영웅: 그 자리에서 aggro 안만
		reach = maxf(float(u.def.aggro), rng)
	var focus = _team_focus(u, foes)
	var cur = u.current_target()
	var best = null
	var best_s := -INF
	for f in foes:
		var d := Formation.flat_distance(u.global_position, f.global_position)
		if Formation.flat_distance(origin, f.global_position) > reach and d > rng + 0.5:
			continue
		var s := _score(u, f, d, focus, cur)
		if s > best_s:
			best_s = s
			best = f
	return best


func _score(u, f, d: float, focus, cur) -> float:
	var s := (dps_of(f) + 1.0) / maxf(1.0, f.hp) * 1000.0
	if f.hp_ratio() < 0.5:
		s *= LOW_HP_BONUS
	if is_hero(f):
		s *= HERO_BONUS
	if f == focus:
		s *= FOCUS_BONUS
	if f == cur:
		s *= STICKY
	if is_healer(f):
		s *= HEALER_BONUS
	var victim = f.current_target() if f.has_method("current_target") else null
	if victim != null and victim != u and victim.get("team") == u.team and (victim.hp_ratio() < WEAK_ALLY or victim.get("role") == "ranged"):
		s *= PEEL_BONUS if u.role == "melee" else (1.0 + (PEEL_BONUS - 1.0) / 2.0)
	var gap := maxf(0.0, d - float(u.def.range))
	var travel := gap / maxf(1.0, float(u.def.speed))
	if u.role == "melee":
		travel *= 1.6
	return s / (1.0 + travel * TRAVEL_W)


## 팀 집중 표적: FOCUS_SEC마다 처치 가치가 가장 큰 적 영웅(없으면 병사).
func _team_focus(u, foes: Array):
	var f: Array = _focus.get(u.team, [null, -INF])
	var now := _now()
	if now - f[1] < FOCUS_SEC and f[0] != null and is_instance_valid(f[0]) and f[0].is_alive():
		return f[0]
	var best = null
	var best_v := -INF
	for c in foes:
		var v := (dps_of(c) + 1.0) / maxf(1.0, c.hp) * (HEALER_BONUS if is_healer(c) else 1.0) * (HERO_BONUS if is_hero(c) else 1.0)
		if v > best_v:
			best_v = v
			best = c
	_focus[u.team] = [best, now]
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


## 0.25초마다: 원거리 뒷걸음, 쉬는 자리(원거리 = 우리 근접 뒤, 근접 = 앞줄).
func think(u) -> void:
	if not u.is_alive():
		return
	if _kite(u):
		return
	if u.commanded:
		return
	var foes := _alive_foes(u)
	if foes.is_empty():
		return
	var enemy_c := _center(foes)
	var allies := _alive_allies(u)
	var melee := allies.filter(func(a): return a.role == "melee")
	var want: Vector3
	if u.role == "ranged" and not melee.is_empty():
		var front := _center(melee)
		var dir := (front - enemy_c)
		dir.y = 0.0
		want = front + (dir.normalized() if dir.length() > 0.1 else -battle.forward(u.team)) * BACK_D
	else:
		want = enemy_c
	want = battle.clamp_field(want)
	if Formation.flat_distance(u.free_pos, want) > 1.5:
		u.set_home(want, u.current_target() == null)


func _kite(u) -> bool:
	if u.role != "ranged" or u.kite_cd > 0.0 or u.is_walking() or u.commanded:
		return false
	var here: Vector3 = u.global_position
	var away := Vector3.ZERO
	var close := 0
	for f in _alive_foes(u):
		if f.get("role") != "melee":
			continue
		var v: Vector3 = here - f.global_position
		v.y = 0.0
		if v.length() < KITE_R:
			away += v.normalized() / maxf(0.3, v.length())
			close += 1
	if close == 0:
		return false
	u.kite_cd = KITE_CD
	var melee := _alive_allies(u).filter(func(a): return a.role == "melee" and a != u)
	if not melee.is_empty():  # 우리 근접 쪽으로 물러나 그 뒤에 숨는다
		var to_front: Vector3 = _center(melee) - here
		to_front.y = 0.0
		away += to_front.normalized() * 0.5
	away.y = 0.0
	if away.length() < 0.01:
		return false
	u.step_to(battle.clamp_field(here + away.normalized() * KITE_STEP))
	return true


static func _center(list: Array) -> Vector3:
	var c := Vector3.ZERO
	for a in list:
		c += a.global_position
	c /= maxf(1.0, list.size())
	c.y = 0.0
	return c

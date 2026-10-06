extends RefCounted
## 공성전 영웅 머리(수비 AI·가상 길드원 공격 AI·플레이어 영웅 자동 전투). war_hero.gd가 부른다:
##  pick_target(u) — 표적 고르기(SCAN마다), blast_ok(u, m) — 광역 폭발 시점, think(u) — 0.25초마다 자리·뒷걸음·진격.
## 표적 점수(클수록 먼저): 처치 가치(초당 피해 ÷ 남은 체력)에
##  × 분대 집중(같은 길드원 4명이 한 표적을 함께 — FOCUS_BONUS) × 지키기(약한 아군을 치고 있는 적 — 근접은 PEEL_BONUS, 원거리 절반)
##  × 치유사(회복·부활 스킬 — HEALER_BONUS) × 지금 표적 유지(STICKY — 표적을 이리저리 바꾸지 않게) ÷ (1 + 닿는 데 걸리는 초 × TRAVEL_W).
## 근접은 다가가야 하므로 거리가 크게 깎이고, 원거리는 사거리 안이면 거리 무관. 성문·성채는 영웅이 하나도 없을 때만.
## 수비: 자기 자리에서 LEASH m 안만 쫓는다(성문을 비우지 않는다). 공격 영웅이 성 안에 들어오면 내 성문이 뚫렸거나 내 면이 조용한 수비가 성채 앞을 막고,
## 내 면에 적이 없으면 공격이 수비보다 많은 옆 면을 도우러 간다(적이 다시 오면 제자리로).
## 원거리 영웅은 근접 적이 KITE_R 안에 붙으면 KITE_STEP m 물러난다(KITE_CD초에 한 번, 묶임·기절 중엔 못 한다).
## 공격(자동): 맡은 면의 성문 앞 수비 영웅을 치러 가고 → 다 쓰러지면 성문 → 부서지면 성 안 성채. 플레이어가 이동 명령을 주면(commanded) 그 자리를 지킨다.

const Formation := preload("res://scripts/formation.gd")
const Balance := preload("res://scripts/balance.gd")

const LEASH := 11.0
const FOCUS_BONUS := 1.6
const PEEL_BONUS := 1.8
const HEALER_BONUS := 1.35
const STICKY := 1.3
const TRAVEL_W := 0.35
const WEAK_ALLY := 0.45
const FOCUS_SEC := 1.0
const KITE_R := 2.4
const KITE_STEP := 3.5
const KITE_CD := 1.6
const GATE_ZONE := 14.0  # 성문 바깥면에서 이 거리 안 수비 영웅 = 그 성문을 지키는 중
const STAGE_D := 9.0  # 공격 자동: 수비가 남은 성문 앞 이 거리에서 모인다(사거리 안으로 들어가며 싸운다)
const HEALS := ["heal_aura", "mass_heal", "sanctuary", "resurrection", "shield_ally", "regen_aura", "battle_hymn", "howl"]

var battle  # war_battle.gd: half, gate(side), keep_spot(side), units(team)
var _focus := {}  # 분대 키 → [표적, 정한 시각]


func _init(p_battle) -> void:
	battle = p_battle


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## u가 지금 칠 수 있는(같은 영역·성을 가로지르지 않는) 산 적 영웅들. structures = 성문·성채 포함.
func _reachable(u, structures: bool) -> Array:
	var out := []
	var half: float = battle.half
	var here: Vector3 = u.global_position
	var inside := Formation.is_inside(half, here)
	for f in u.get_tree().get_nodes_in_group(u.foes):
		if not f.is_alive():
			continue
		var st: bool = f.get("is_structure") == true
		if st != structures:
			continue
		var p: Vector3 = f.global_position
		if not st and Formation.is_inside(half, p) != inside:
			continue
		if not inside and not st and Formation.crosses_castle(half, here, p):
			continue
		out.append(f)
	return out


static func dps_of(f) -> float:
	if f.get("def") == null:
		return 0.0
	return float(f.atk) / maxf(0.2, float(f.def.atk_interval))


static func is_healer(f) -> bool:
	var sk = f.get("_sk")
	if sk == null:
		return false
	for k in HEALS:
		if sk.has(k):
			return true
	return false


## 표적 고르기. 수비는 자리(LEASH), 공격은 머무는 자리(aggro)·지금 위치(사거리) 기준.
func pick_target(u):
	var cands := _reachable(u, false)
	var origin: Vector3 = u.stand_position()
	var reach: float
	if u.team == 1:
		reach = LEASH
	else:
		reach = maxf(float(u.def.aggro), float(u.def.range)) + (4.0 if not u.commanded else 0.0)
	var rng := float(u.def.range)
	var best = null
	var best_s := -INF
	var focus = _squad_focus(u, cands, origin, reach)
	var cur = u.current_target()
	for f in cands:
		var p: Vector3 = f.global_position
		var d := Formation.flat_distance(u.global_position, p)
		if Formation.flat_distance(origin, p) > reach and d > rng + 0.5:
			continue
		var s := _score(u, f, d, focus, cur)
		if s > best_s:
			best_s = s
			best = f
	if best != null:
		return best
	# 영웅이 없으면 구조물(공격만): 가까운 것
	if u.team != 0:
		return null
	var near_d := INF
	for st in _reachable(u, true):
		var d := Formation.flat_distance(u.global_position, st.global_position)
		if (Formation.flat_distance(origin, st.global_position) <= reach + 4.0 or d <= rng + 0.5) and d < near_d:
			near_d = d
			best = st
	return best


func _score(u, f, d: float, focus, cur) -> float:
	var hp: float = maxf(1.0, f.hp)
	var s := (dps_of(f) + 1.0) / hp * 1000.0
	if f == focus:
		s *= FOCUS_BONUS
	if f == cur:
		s *= STICKY
	if is_healer(f):
		s *= HEALER_BONUS
	var victim = f.current_target() if f.has_method("current_target") else null
	if victim != null and victim != u and victim.get("team") == u.team and victim.hp_ratio() < WEAK_ALLY:
		s *= PEEL_BONUS if u.role == "melee" else (1.0 + (PEEL_BONUS - 1.0) / 2.0)
	var gap := maxf(0.0, d - float(u.def.range))
	var travel := gap / maxf(1.0, float(u.def.speed))
	if u.role == "melee":
		travel *= 1.5
	return s / (1.0 + travel * TRAVEL_W)


## 분대(같은 길드원 4명) 집중 표적: FOCUS_SEC마다 처치 가치가 가장 큰 적(분대 자리 근처).
func _squad_focus(u, cands: Array, origin: Vector3, reach: float):
	var key: int = u.team * 100000 + u.squad
	var f: Array = _focus.get(key, [null, -INF])
	var now := _now()
	if now - f[1] < FOCUS_SEC and f[0] != null and is_instance_valid(f[0]) and f[0].is_alive():
		return f[0]
	var best = null
	var best_v := -INF
	for c in cands:
		if Formation.flat_distance(origin, c.global_position) > reach + 3.0:
			continue
		var v := (dps_of(c) + 1.0) / maxf(1.0, c.hp) * (HEALER_BONUS if is_healer(c) else 1.0)
		if v > best_v:
			best_v = v
			best = c
	_focus[key] = [best, now]
	return best


## 광역 폭발: 표적 둘레에 적이 둘 이상, 또는 표적이 거의 쓰러질 때, 또는 근처 적이 그 하나뿐일 때만.
func blast_ok(u, m) -> bool:
	if m == null or not is_instance_valid(m):
		return false
	if m.get("is_structure") == true:
		return true
	var r: float = float(u._sk.aoe_blast[1]) if u._sk.has("aoe_blast") else 3.0
	var n := 0
	var near := 0
	for f in u.get_tree().get_nodes_in_group(u.foes):
		if not f.is_alive() or f.get("is_structure") == true:
			continue
		var d := Formation.flat_distance(m.global_position, f.global_position)
		if d <= r:
			n += 1
		if d <= 12.0:
			near += 1
	return n >= 2 or near <= 1 or m.hp_ratio() < 0.35


## 0.25초마다: 뒷걸음, 자리(수비 재배치·공격 진격), 성벽 너머 자리면 성문 경로.
func think(u) -> void:
	if not u.is_alive():
		return
	if _kite(u):
		return
	if u.team == 1:
		_defend(u)
	elif not u.commanded:
		_advance(u)
	if u.needs_route() and u.current_target() == null:
		u._replan()


func _kite(u) -> bool:
	if u.role != "ranged" or u.kite_cd > 0.0 or u.is_walking() or u.commanded:
		return false
	var here: Vector3 = u.global_position
	var away := Vector3.ZERO
	var close := 0
	for f in _reachable(u, false):
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
	if away.length() < 0.01:
		away = (u.stand_position() - here)
	away.y = 0.0
	if away.length() < 0.01:
		return false
	var inside := Formation.is_inside(battle.half, here)
	var dir := away.normalized()
	var to := here + dir * KITE_STEP
	if Formation.is_inside(battle.half, to) != inside:
		# 성벽에 등을 대고 있으면 성벽을 따라 옆으로 비킨다(위협에서 먼 쪽)
		var t := Formation.perp(Formation.side_of(here))
		var side_sign := 1.0 if t.dot(dir) >= 0.0 else -1.0
		if absf(t.dot(dir)) < 0.05:
			side_sign = 1.0 if (int(u.uid) % 2) == 0 else -1.0
		to = here + t * side_sign * KITE_STEP
		if Formation.is_inside(battle.half, to) != inside:
			return false
	u.step_to(to)
	return true


func _defend(u) -> void:
	_survey()
	var s: int = u.lane
	var spot: int = u.squad * 4 + int(u.uid) % 4
	var want: Vector3 = u.post_pos
	var busy_here: bool = _press[s] > 0
	if _inside > 0 and (not battle.gate(s).is_alive() or not busy_here):
		want = battle.keep_spot(s, spot)  # 성 안에 들어왔다: 내 면이 조용하면(또는 내 성문이 뚫렸으면) 성채 앞을 막는다
	elif not busy_here:
		var k := _help_lane(s)
		if k >= 0:
			want = battle.lane_spot(k, 4.2 if u.role == "melee" else 1.6, 40 + spot)  # 조용한 면 수비는 밀리는 옆 면을 돕는다
	if Formation.flat_distance(u.free_pos, want) > 1.0:
		u.set_home(want, u.current_target() == null)


## 성 둘레 형세(0.5초마다 한 번): 면마다 성 밖 공격 영웅 수(_press)·성 밖 수비 영웅 수(_guard), 성 안 공격 영웅 수(_inside).
var _survey_t := -INF
var _press := [0, 0, 0, 0]
var _guard := [0, 0, 0, 0]
var _inside := 0


func _survey() -> void:
	var now := _now()
	if now - _survey_t < 0.5:
		return
	_survey_t = now
	_press = [0, 0, 0, 0]
	_guard = [0, 0, 0, 0]
	_inside = 0
	for a in battle.units(0):
		if not a.is_alive():
			continue
		if Formation.is_inside(battle.half, a.global_position):
			_inside += 1
		elif _near_wall(a.global_position):
			_press[_side_of(a.global_position)] += 1
	for d in battle.units(1):
		if d.is_alive() and not Formation.is_inside(battle.half, d.global_position):
			_guard[_side_of(d.global_position)] += 1


## 지원 갈 면: 성문이 살아 있고 공격이 수비보다 많은 면 중 가장 밀리는 곳(맞은편은 멀어서 덜 친다). 없으면 -1.
func _help_lane(s: int) -> int:
	var best := -1
	var best_need := 0.0
	for k in 4:
		if k == s or not battle.gate(k).is_alive():
			continue
		var need := float(_press[k] - _guard[k]) * (0.5 if k == (s + 2) % 4 else 1.0)
		if need > best_need:
			best_need = need
			best = k
	return best


func _near_wall(p: Vector3) -> bool:
	return maxf(absf(p.x), absf(p.z)) <= battle.half + Balance.WALL_T + GATE_ZONE + STAGE_D


static func _side_of(p: Vector3) -> int:
	var best := 0
	var best_d := -INF
	for k in 4:
		var d: float = p.dot(Formation.SIDE_DIR[k])
		if d > best_d:
			best_d = d
			best = k
	return best


## 공격 자동 진격: 맡은 면 성문에 수비가 남았으면 그 앞(STAGE_D)에, 없으면 성문 앞, 성문이 부서졌으면 성채.
func _advance(u) -> void:
	var s: int = u.lane
	var spot: int = u.squad * 4 + int(u.uid) % 4
	var want: Vector3
	if not battle.gate(s).is_alive():
		if not battle.keep_alive():
			return
		want = battle.keep_spot(s, spot)
	elif battle.defenders_at(s) > 0:
		want = battle.lane_spot(s, STAGE_D, spot)
	else:
		want = battle.lane_spot(s, 1.6, spot)
	if Formation.flat_distance(u.free_pos, want) > 1.5:
		u.set_home(want, u.current_target() == null)

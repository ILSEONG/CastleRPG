extends Node
## 전술 지휘관(개정 21 §3). 병사 각자가 아니라 이 노드 하나가 1초마다 판단한다 — 계산은 순수 함수(static, 테스트), 적용은 decide.
## 위협 = 면 s 성문 바깥 R_OUT·안쪽 통로 R_IN 안 몬스터 전투력(HP × 초당 피해) 합 × (1 + 1.5 × (1 − 성문 HP 비율)).
## 방어력 = 그 면 영웅(성문 앞·성벽 위)·병사(지원 와 있는 병사 포함) 전투력 합. 심각한 면에는 필요량(위협 × 1.1 − 방어력)만큼만 보낸다:
## 순찰·대기 기병 → 조용한 면 보병 → 여유 있는 면 보병, 같은 순위는 가까운 순(경로 길이). 보내는 면은 자기 위협 × 1.2 방어력과 보병 1명을 남긴다.
## 지원 면이 3초 넘게 조용하거나(위협 < 방어력 × 0.5) 자기 면이 심각해지면 돌아간다. 같은 병사는 4초에 한 번만 다시 배정한다.
## 영웅은 지휘하지 않고 방어력에만 센다. 스테이지 모드에서만 돈다. 오토로드 이름을 쓰지 않는다(run_tests -s가 preload).

const Formation := preload("res://scripts/formation.gd")

const TICK := 1.0
const R_OUT := 14.0  # 성문 공격 지점에서 바깥 몬스터를 세는 반경
const R_IN := 8.0    # 이미 들어온 몬스터: 성문 안쪽 통로 점에서
const GATE_WEIGHT := 1.5  # 부서진 성문(비율 0)은 × 2.5
const SEVERE := 1.3
const MIN_THREAT := 2000.0  # 잔챙이 무시(1스테이지 졸개 하나 ≈ 600, 보스 ≈ 6700)
const LOW_GATE := 0.45
const DROP := 0.15
const DROP_SEC := 5.0
const NEED := 1.1
const FLOOR := 1.2
const CALM := 0.5
const CALM_SEC := 3.0
const REASSIGN_SEC := 4.0

var castle
var last_plan := {}  # 마지막 판단(plan 반환값 — 테스트·디버그)
var _gs  # GameState(오토로드 — 이름 대신 노드로)
var _clock := 0.0  # 스테이지 모드에서만 흐르는 시계(병사 last_order와 같은 기준)
var _acc := 0.0
var _calm := [-1.0, -1.0, -1.0, -1.0]  # 면별 조용한 시간(calm_next)
var _hist := []  # [시각, 면별 성문 HP 비율] 최근 DROP_SEC초


## 전투력 = HP × 초당 피해.
static func power(hp: float, atk: float, interval: float) -> float:
	return hp * atk / interval if interval > 0.0 else 0.0


## 스테이지 시작 역할 자리(§2): 병종마다 티어 높은 병사부터 북·동·남·서 차례로. units = [{type, tier}] → 같은 순서의 {side, slot}
## (slot = 그 면에서 그 병종의 몇 번째).
static func assign_posts(units: Array) -> Array:
	var out := []
	out.resize(units.size())
	var by_type := {}
	for i in units.size():
		if not by_type.has(units[i].type):
			by_type[units[i].type] = []
		by_type[units[i].type].append(i)
	for t in by_type:
		var idx: Array = by_type[t]
		idx.sort_custom(func(a, b): return units[a].tier > units[b].tier or (units[a].tier == units[b].tier and a < b))
		for k in idx.size():
			out[idx[k]] = {"side": k % 4, "slot": int(k / 4.0)}
	return out


## 병사 이동 경로: 기병이 성 밖 → 성 밖이면 순찰 고리로 돈다(성 안에 안 들어간다). 그 밖은 Formation.route(성문·계단).
static func travel(half: float, type: String, from: Vector3, to: Vector3) -> Array[Vector3]:
	if type == "cavalry" and not Formation.is_inside(half, from) and not Formation.is_inside(half, to):
		return Formation.ring_route(half, from, to)
	return Formation.route(half, from, to)


## 면별 위협(몬스터마다 면 하나만 본다 — O(N)). monsters = [{pos, power}], ratio = 면별 성문 HP 비율(0 = 부서짐).
static func threats(half: float, monsters: Array, ratio: Array) -> Array:
	var t := [0.0, 0.0, 0.0, 0.0]
	for m in monsters:
		var s := Formation.side_of(m.pos)
		var inside := Formation.is_inside(half, m.pos)
		var at := Formation.gate_inner(half, s) if inside else Formation.gate_target(half, s)
		if Formation.flat_distance(m.pos, at) <= (R_IN if inside else R_OUT):
			t[s] += m.power
	for s in 4:
		t[s] *= 1.0 + GATE_WEIGHT * (1.0 - ratio[s])
	return t


## 면별 방어력. units = [{side, power}](side = 지금 지키는 면).
static func defenses(units: Array) -> Array:
	var d := [0.0, 0.0, 0.0, 0.0]
	for u in units:
		d[u.side] += u.power
	return d


## 심각: 위협이 방어력 × 1.3을 넘고 잔챙이가 아니거나, 성문 HP 비율 < 0.45이면서 최근 5초에 15% 넘게 줄었다.
static func severe(threat: float, defense: float, ratio: float, drop: float) -> bool:
	return (threat > defense * SEVERE and threat > MIN_THREAT) or (ratio < LOW_GATE and drop > DROP)


static func need(threat: float, defense: float) -> float:
	return threat * NEED - defense


## 조용한 시간(초, −1 = 조용하지 않음): 위협 < 방어력 × 0.5면 처음 본 판단은 0, 그 뒤 dt씩 는다 — 복귀는 "3초 넘게" 조용했을 때만.
static func calm_next(calm: Array, threat: Array, defense: Array, dt: float) -> Array:
	var out := []
	for s in 4:
		out.append((calm[s] + dt if calm[s] >= 0.0 else 0.0) if threat[s] < defense[s] * CALM else -1.0)
	return out


## 지원 보낼 최소 집합: (prio, dist) 순으로 전투력을 더해 n을 넘으면 멈춘다. cands = [{id, type, side(원래 면), power, dist, prio}].
## 보내는 면은 위협 × FLOOR 방어력과 보병 1명(있으면)을 남긴다 — left(면별 방어력)·inf(면별 자리에 있는 보병 수)를 고른 만큼 줄인다.
## 반환 = 고른 id(고른 순서).
static func pick(n: float, target: int, cands: Array, threat: Array, left: Array, inf: Array) -> Array:
	var order := cands.duplicate()
	order.sort_custom(func(a, b): return a.prio < b.prio or (a.prio == b.prio and a.dist < b.dist))
	var out := []
	var acc := 0.0
	for c in order:
		if acc >= n:
			break
		var d: int = c.side
		if d == target or left[d] - c.power < threat[d] * FLOOR or (c.type == "infantry" and inf[d] <= 1):
			continue
		left[d] -= c.power
		if c.type == "infantry":
			inf[d] -= 1
		acc += c.power
		out.append(c.id)
	return out


## 한 번의 판단(순수). s = {half, now, dt, calm[4], monsters: [{pos, power}], ratio[4], drop[4], heroes: [{side, power}],
## soldiers: [{id, type, side, at, power, pos, last, engaged}]}(at = 지금 지키는 면 — 지원 중이면 그 면, last = 마지막 배정 시각).
## 반환 {threat, defense(판단 뒤), severe, calm, need, recall: [id], send: [[id, 면]]}. 복귀가 먼저, 그다음 심각한 면(모자람 큰 순)에 보낸다.
static func plan(s: Dictionary) -> Dictionary:
	var threat := threats(s.half, s.monsters, s.ratio)
	var units: Array = s.heroes.duplicate()
	var by_id := {}
	for u in s.soldiers:
		units.append({"side": u.at, "power": u.power})
		by_id[u.id] = u
	var defense := defenses(units)
	var sev := []
	for i in 4:
		sev.append(severe(threat[i], defense[i], s.ratio[i], s.drop[i]))
	var calm := calm_next(s.calm, threat, defense, s.dt)
	var at := {}  # id → 판단 중 지키는 면
	var recall := []
	for u in s.soldiers:
		at[u.id] = u.at
		if u.at != u.side and s.now - u.last >= REASSIGN_SEC and (sev[u.side] or calm[u.at] >= CALM_SEC):
			recall.append(u.id)
			at[u.id] = u.side
			defense[u.at] -= u.power
			defense[u.side] += u.power
	var inf := [0, 0, 0, 0]
	for u in s.soldiers:
		if u.type == "infantry" and at[u.id] == u.side:
			inf[u.side] += 1
	var order := range(4).filter(func(i): return sev[i])
	order.sort_custom(func(a, b): return threat[a] - defense[a] > threat[b] - defense[b])
	var needs := [0.0, 0.0, 0.0, 0.0]
	var send := []
	for t in order:
		needs[t] = need(threat[t], defense[t])
		if needs[t] <= 0.0:
			continue
		var cands := []
		for u in s.soldiers:
			if at[u.id] != u.side or u.side == t or s.now - u.last < REASSIGN_SEC or recall.has(u.id):
				continue
			var prio := 0
			if u.type == "infantry":
				prio = 1 if threat[u.side] < MIN_THREAT else 2
			elif u.type != "cavalry" or u.engaged:
				continue  # 궁병은 성벽을 지키고, 싸우는 기병은 순찰·대기가 아니다
			var dist := Formation.path_length(u.pos, travel(s.half, u.type, u.pos, Formation.gate_target(s.half, t)))
			cands.append({"id": u.id, "type": u.type, "side": u.side, "power": u.power, "dist": dist, "prio": prio})
		for id in pick(needs[t], t, cands, threat, defense, inf):
			send.append([id, t])
			at[id] = t
			defense[t] += by_id[id].power
	return {"threat": threat, "defense": defense, "severe": sev, "calm": calm, "need": needs, "recall": recall, "send": send}


func _ready() -> void:
	_gs = get_node("/root/GameState")
	_gs.refilled.connect(reset_memory)


## 리필(스테이지 시작·끝): 조용한 시간·성문 기록을 비운다.
func reset_memory() -> void:
	_calm = [-1.0, -1.0, -1.0, -1.0]
	_hist.clear()
	_acc = 0.0
	last_plan = {}


func _process(delta: float) -> void:
	if _gs.mode != _gs.Mode.STAGE:
		return
	_clock += delta
	_acc += delta
	if _acc >= TICK:
		decide(_acc)
		_acc = 0.0


## 장면에서 상태를 모아 plan하고 지시를 적용한다(복귀 → 지원). 지원 칸 = 그 면 자기 보병 수 + 이미 와 있는 지원 수부터.
func decide(dt := TICK) -> Dictionary:
	var half: float = castle.half
	var ratio := []
	for s in 4:
		ratio.append(_gs.gate_hp[s] / _gs.gate_hp_max if _gs.gate_hp_max > 0.0 else 1.0)
	_hist.append([_clock, ratio])
	while _clock - _hist[0][0] > DROP_SEC:
		_hist.pop_front()
	var drop := []
	for s in 4:
		var top := 0.0
		for h in _hist:
			top = maxf(top, h[1][s])
		drop.append(top - ratio[s])
	var monsters := []
	for m in get_tree().get_nodes_in_group("monsters"):
		if m.is_alive():
			monsters.append({"pos": m.global_position, "power": power(m.hp, m.atk, float(m._stats.atk_interval))})
	var heroes := []
	for h in get_tree().get_nodes_in_group("heroes"):
		if h.is_alive() and h.post != Formation.POST_FREE:
			heroes.append({"side": h.side, "power": power(h.hp, h.atk, float(h.def.atk_interval))})
	var nodes := {}
	var soldiers := []
	for u in get_tree().get_nodes_in_group("soldiers"):
		if u.is_alive():
			nodes[u.get_instance_id()] = u
			soldiers.append({"id": u.get_instance_id(), "type": u.type, "side": u.side, "at": u.side_now(), "power": u.power(),
				"pos": u.global_position, "last": u.last_order, "engaged": u.engaged()})
	var p := plan({"half": half, "now": _clock, "dt": dt, "calm": _calm, "monsters": monsters, "ratio": ratio, "drop": drop,
		"heroes": heroes, "soldiers": soldiers})
	_calm = p.calm
	for id in p.recall:
		nodes[id].order(-1, 0, _clock)
	var next := [0, 0, 0, 0]  # 면별 다음 지원 칸(자기 보병 칸 다음부터)
	for u in nodes.values():
		if u.type == "infantry":
			next[u.side] = maxi(next[u.side], u.slot + 1)
	for u in nodes.values():
		if u.reinforce >= 0:
			next[u.reinforce] = maxi(next[u.reinforce], u.rslot + 1)
	for e in p.send:
		nodes[e[0]].order(e[1], next[e[1]], _clock)
		next[e[1]] += 1
	last_plan = p
	return p

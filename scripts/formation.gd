extends RefCounted
## 영웅 배치: 면(side)마다 성문 앞(POST_GATE)·성벽 위(POST_WALL) 슬롯 점유와 위치 계산.
## 씬·오토로드 의존 없음. 위치 함수는 static이고 성 내부 절반 크기(half)를 인자로 받는다.
## side: 0=N(-z) 1=E(+x) 2=S(+z) 3=W(-x)

const Balance := preload("res://scripts/balance.gd")
const GameData := preload("res://scripts/game_data.gd")

const POST_GATE := 0
const POST_WALL := 1
const POST_FREE := 2          # 자유 위치 (슬롯 없음)
const GATE_PASS_MARGIN := 1.0 # 성문 통과 지점·계단 앞 지점이 성벽 바깥면·계단 띠에서 떨어진 거리
const WALK_HALF := 0.55  # 성벽 길: 중심선에서 이만큼 안(성벽 두께 2 m − 몸) — 밀려도 여기를 벗어나지 않는다(clamp_push)
const REGION_OUTSIDE := 0
const REGION_INSIDE := 1
const REGION_WALL := 2    # 성벽 위(계단 윗부분 포함)
const SIDE_DIR: Array[Vector3] = [
	Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0),
]
const SIDE_NAMES := ["북", "동", "남", "서"]  # 면 방향 이름(HUD 성문 막대·문루 글자)

static var _keep_half: float = Balance.building("keep").size.x * Balance.TILE / 2.0  # 성채 외벽 절반 크기. 로드 때 한 번 계산

var _claims := {}  # hero_id -> {"side": int, "post": int, "slot": int}
var castle_half := 0.0  # 성 내부 절반 크기 — 면마다 성문 수(성문 앞 자리 수 = 3 × 성문 수)를 정한다. 성을 만들 때 main이 넣는다(0 = 성문 1개)


## 빈 슬롯 중 가장 앞 번호를 차지하고 돌려준다. 가득 차면 -1 (기존 배정 유지).
## 이미 같은 자리면 그 슬롯 그대로. 다른 자리로 옮기면 이전 슬롯은 자동으로 풀린다.
func claim(hero_id: int, side: int, post: int) -> int:
	var current: Dictionary = _claims.get(hero_id, {})
	if not current.is_empty() and current.side == side and current.post == post:
		return current.slot
	var taken := {}
	for id in _claims:
		var c: Dictionary = _claims[id]
		if c.side == side and c.post == post:
			taken[c.slot] = true
	for slot in capacity(post, gates_per_side(castle_half)):
		if not taken.has(slot):
			_claims[hero_id] = {"side": side, "post": post, "slot": slot}
			return slot
	return -1


## 누른 지점에 가까운 자리: 면 side·post에서 성문 중앙 기준 옆 거리 offset에 가장 가까운 빈 슬롯(자기 슬롯 포함)을 차지하고 돌려준다.
## 같은 면 성벽 위 한쪽에 서 있던 영웅이 반대쪽을 누르면 그쪽 빈 자리로 옮긴다. 가장 가까운 게 자기 슬롯이면 그대로. 가득 차면 -1.
func claim_near(hero_id: int, side: int, post: int, offset: float) -> int:
	var current: Dictionary = _claims.get(hero_id, {})
	var taken := {}
	for id in _claims:
		var c: Dictionary = _claims[id]
		if id != hero_id and c.side == side and c.post == post:
			taken[c.slot] = true
	var offs: Array = gate_front_offsets(castle_half) if post == POST_GATE else wall_top_offsets(castle_half)
	var best := -1
	for slot in offs.size():
		if not taken.has(slot) and (best < 0 or absf(float(offs[slot]) - offset) < absf(float(offs[best]) - offset)):
			best = slot
	if best >= 0:
		_claims[hero_id] = {"side": side, "post": post, "slot": best}
	return best


## 정확한 슬롯으로 되돌린다(스테이지 시작 자리 복원용). 호출 전에 전원 release해 충돌이 없어야 한다.
func restore(hero_id: int, side: int, post: int, slot: int) -> void:
	_claims[hero_id] = {"side": side, "post": post, "slot": slot}


func release(hero_id: int) -> void:
	_claims.erase(hero_id)


func assignment(hero_id: int) -> Dictionary:
	return _claims.get(hero_id, {})


static func capacity(post: int, n := 1) -> int:
	return Balance.GATE_FRONT_SLOTS.size() * n if post == POST_GATE else Balance.WALL_TOP_SLOTS.size()


# --- 성문(개정: 성 내부 단계마다 면마다 성문 하나씩 더 — 20칸 1개, 28칸 2개, 36칸 3개) ---
# 성문 k = 면 안에서 몇 번째(음의 perp 쪽부터). 성문 내구도는 면마다 하나(같은 면 성문끼리 공유 — GameState.gate_hp[side]).
# 성문 중앙의 옆 위치(at) = 면을 n등분한 칸의 가운데: half × (2k + 1 − n) / n — 1개 0, 2개 ±half/2, 3개 0·±2half/3.

## 성 내부 절반 크기 half의 면마다 성문 수.
static func gates_per_side(half: float) -> int:
	return GameData.gates_per_side(half)


static func gate_offset(half: float, k: int, n := 0) -> float:
	if n <= 0:
		n = gates_per_side(half)
	return half * float(2 * k + 1 - n) / float(n)


static func gate_offsets(half: float, n := 0) -> Array:
	if n <= 0:
		n = gates_per_side(half)
	return range(n).map(func(k): return gate_offset(half, k, n))


## 면 side에서 p에 옆으로 가장 가까운 성문 번호 k.
static func nearest_gate(half: float, side: int, p: Vector3) -> int:
	var n := gates_per_side(half)
	var t := perp(side).dot(p)
	var best := 0
	for k in n:
		if absf(gate_offset(half, k, n) - t) < absf(gate_offset(half, best, n) - t):
			best = k
	return best


## p에 가장 가까운 성문의 옆 위치(면 side).
static func nearest_gate_at(half: float, side: int, p: Vector3) -> float:
	return gate_offset(half, nearest_gate(half, side, p))


## 성문 앞 자리의 옆 위치(슬롯 순): 성문마다 GATE_FRONT_SLOTS를 돌아가며 — 슬롯 s는 성문 s % n의 s / n번째 자리.
static func gate_front_offsets(half: float) -> Array:
	var n := gates_per_side(half)
	var out := []
	for s in Balance.GATE_FRONT_SLOTS.size() * n:
		out.append(gate_offset(half, s % n, n) + float(Balance.GATE_FRONT_SLOTS[s / n]))
	return out


## 성벽 위 영웅 자리의 옆 위치(슬롯 순). 성문 1개 성은 WALL_TOP_SLOTS 그대로(±4·±8). 성문 2·3개 성은 성문 옆 4 m —
## 먼저 서로 다른 성문을 하나씩, 성 가운데 쪽부터(계단도 가운데 쪽 것을 써서 모서리 건물 부지를 지나지 않는다):
## 2개(±half/2) = 성문0 안쪽·성문1 안쪽·성문0 바깥·성문1 바깥, 3개(0·±2half/3) = 가운데 −4·오른쪽 안쪽·왼쪽 안쪽·가운데 +4.
## 전투 시뮬 2026-10-07: 예전처럼 가운데 ±4에 서면 성문(±half/2)에서 10 m 이상이라 사거리 8 m 원거리 영웅이 한 발도 못 쐈다.
static func wall_top_offsets(half: float) -> Array:
	var n := gates_per_side(half)
	if n <= 1:
		return Balance.WALL_TOP_SLOTS.duplicate()
	var d := absf(float(Balance.WALL_TOP_SLOTS[0]))
	var g := gate_offsets(half, n)
	if n == 2:
		return [g[0] + d, g[1] - d, g[0] - d, g[1] + d]
	return [g[1] - d, g[2] - d, g[0] + d, g[1] + d]


static func perp(side: int) -> Vector3:
	var dir := SIDE_DIR[side]
	return Vector3(-dir.z, 0, dir.x)


## 성벽 중심선 위의 성문 중앙 (지면). at = 성문의 옆 위치(gate_offset).
static func gate_position(half: float, side: int, at := 0.0) -> Vector3:
	return SIDE_DIR[side] * (half + Balance.WALL_T / 2.0) + perp(side) * at


## 괴물이 성문을 치려고 서는 지점 (성벽 바깥면 바로 앞).
static func gate_target(half: float, side: int, at := 0.0) -> Vector3:
	return SIDE_DIR[side] * (half + Balance.WALL_T + 0.8) + perp(side) * at


static func slot_position(half: float, side: int, post: int, slot: int) -> Vector3:
	var dir := SIDE_DIR[side]
	if post == POST_GATE:
		return dir * (half + Balance.WALL_T + Balance.GATE_FRONT_OFFSET) + perp(side) * float(gate_front_offsets(half)[slot])
	return dir * (half + Balance.WALL_T / 2.0) + perp(side) * float(wall_top_offsets(half)[slot]) \
		+ Vector3(0, Balance.WALL_H, 0)


## 성문이 부서진 뒤 괴물이 성채를 치려고 서는 지점 (성채 외벽 바로 앞).
static func keep_target(side: int) -> Vector3:
	return SIDE_DIR[side] * (_keep_half + 0.8)


static func spawn_center(half: float, side: int, at := 0.0) -> Vector3:
	return SIDE_DIR[side] * (half + Balance.WALL_T + Balance.SPAWN_MARGIN) + perp(side) * at


## p가 바라보는 면 (면 방향과의 내적이 가장 큰 면).
static func side_of(p: Vector3) -> int:
	var best := 0
	var best_d := -INF
	for s in 4:
		var d := SIDE_DIR[s].dot(p)
		if d > best_d:
			best_d = d
			best = s
	return best


## 성문 안쪽 통과 지점. 계단 띠(성벽 안쪽 STAIR_W) 밖이라 여기서 옆으로 가는 지상 구간이 계단을 지나지 않는다.
static func gate_inner(half: float, side: int, at := 0.0) -> Vector3:
	return SIDE_DIR[side] * (half - Balance.STAIR_W - GATE_PASS_MARGIN) + perp(side) * at


static func gate_outer(half: float, side: int, at := 0.0) -> Vector3:
	return SIDE_DIR[side] * (half + Balance.WALL_T + GATE_PASS_MARGIN) + perp(side) * at


static func region(half: float, p: Vector3) -> int:
	if p.y > Balance.WALL_H / 2.0:
		return REGION_WALL
	if maxf(absf(p.x), absf(p.z)) < half + Balance.WALL_T:
		return REGION_INSIDE
	return REGION_OUTSIDE


## 계단: 각 성문 좌우(end = -1/+1)에 하나씩, 성벽 안쪽 면에 붙은 띠에서 성문 쪽으로 올라간다. at = 그 성문의 옆 위치.
static func stair_bottom(half: float, side: int, end: float, at := 0.0) -> Vector3:
	return SIDE_DIR[side] * (half - Balance.STAIR_W / 2.0) \
		+ perp(side) * (at + end * (Balance.GATE_W / 2.0 + Balance.STAIR_GAP + Balance.STAIR_RUN))


static func stair_top(half: float, side: int, end: float, at := 0.0) -> Vector3:
	return SIDE_DIR[side] * (half - Balance.STAIR_W / 2.0) \
		+ perp(side) * (at + end * (Balance.GATE_W / 2.0 + Balance.STAIR_GAP)) + Vector3(0, Balance.WALL_H, 0)


## 계단 윗단에서 성벽 중심선으로 올라선 지점.
static func wall_landing(half: float, side: int, end: float, at := 0.0) -> Vector3:
	return SIDE_DIR[side] * (half + Balance.WALL_T / 2.0) \
		+ perp(side) * (at + end * (Balance.GATE_W / 2.0 + Balance.STAIR_GAP)) + Vector3(0, Balance.WALL_H, 0)


## 계단 아랫단 너머 지상 지점(계단 띠 밖). 지상 구간은 여기까지만 오고, 띠에는 아랫단 너머로만 들어간다.
static func stair_approach(half: float, side: int, end: float, at := 0.0) -> Vector3:
	return SIDE_DIR[side] * (half - Balance.STAIR_W - GATE_PASS_MARGIN) \
		+ perp(side) * (at + end * (Balance.GATE_W / 2.0 + Balance.STAIR_GAP + Balance.STAIR_RUN + GATE_PASS_MARGIN))


## p(성벽 위 또는 지상)에 가장 가까운 계단 [end, at]: 성문 중 옆으로 가장 가까운 것의, p가 있는 쪽 계단.
static func _stair_of(half: float, side: int, p: Vector3) -> Array:
	var at := nearest_gate_at(half, side, p)
	return [1.0 if perp(side).dot(p) >= at else -1.0, at]


## from → to 이동 경로(도착점 포함). 성벽 위는 계단으로만 오르내린다(같은 면 성벽 위끼리는 곧장):
## 오를 때 stair_approach → 아랫단 → 윗단 → landing, 내릴 때 그 역순. 지상 구간은 stair_approach에서 끊기고
## 성 안팎을 오갈 때 성문을 지난다(_ground_route). 다른 면의 안쪽 통로 점끼리는 통로 모서리를 돈다(_lane_corners).
static func route(half: float, from: Vector3, to: Vector3) -> Array[Vector3]:
	var path: Array[Vector3] = []
	var from_wall := region(half, from) == REGION_WALL
	var to_wall := region(half, to) == REGION_WALL
	if from_wall and to_wall and side_of(from) == side_of(to):
		path.append(to)
		return path
	var ground_from := from
	if from_wall:
		var s := side_of(from)
		var st := _stair_of(half, s, from)
		path.append(wall_landing(half, s, st[0], st[1]))
		path.append(stair_top(half, s, st[0], st[1]))
		path.append(stair_bottom(half, s, st[0], st[1]))
		ground_from = stair_approach(half, s, st[0], st[1])
		path.append(ground_from)
	var ground_to := to
	var tail: Array[Vector3] = []
	if to_wall:
		var s2 := side_of(to)
		var st2 := _stair_of(half, s2, to)
		ground_to = stair_approach(half, s2, st2[0], st2[1])
		tail = [stair_bottom(half, s2, st2[0], st2[1]), stair_top(half, s2, st2[0], st2[1]), wall_landing(half, s2, st2[0], st2[1]), to]
	path.append_array(_ground_route(half, ground_from, ground_to))
	path.append_array(tail)
	var out: Array[Vector3] = []
	var prev := from
	for p in path:
		out.append_array(_lane_corners(half, prev, p))
		out.append(p)
		prev = p
	return out


## 서로 다른 면의 안쪽 통로(깊이 l = stair_approach·gate_inner 깊이) 두 점 사이에 통로 모서리를 끼운다 — 가로지르면 건물을 지난다.
## 통로 고리는 모든 부지·계단 띠에서 떨어져 있다(테스트). 마주 보는 면이면 두 점의 옆 방향 합 쪽 모서리 둘을 돈다.
static func _lane_corners(half: float, a: Vector3, b: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var l := half - Balance.STAIR_W - GATE_PASS_MARGIN
	for p in [a, b]:
		if p.y != 0.0 or absf(maxf(absf(p.x), absf(p.z)) - l) > 0.01:
			return out
	var sa := side_of(a)
	var sb := side_of(b)
	if sa == sb:
		return out
	if (sa + 2) % 4 != sb:
		out.append((SIDE_DIR[sa] + SIDE_DIR[sb]) * l)
	else:
		var t := 1.0 if perp(sa).dot(a + b) >= 0.0 else -1.0
		out.append((SIDE_DIR[sa] + perp(sa) * t) * l)
		out.append((SIDE_DIR[sb] + perp(sa) * t) * l)
	return out


## 지상 두 점 사이 경로(도착점 포함). 성 안팎을 오가거나 성을 가로지를 때는 성문을 지난다.
## "안" = 성벽 바깥면 안쪽(crosses_castle과 같은 경계). 문짝 상태와 무관하게 아군은 통과.
static func _ground_route(half: float, from: Vector3, to: Vector3) -> Array[Vector3]:
	var path: Array[Vector3] = []
	var from_in := is_inside(half, from)
	var to_in := is_inside(half, to)
	if from_in and not to_in:
		var s := side_of(to)
		var at := nearest_gate_at(half, s, to)
		path.append(gate_inner(half, s, at))
		path.append(gate_outer(half, s, at))
	elif not from_in and to_in:
		var s := side_of(from)
		var at := nearest_gate_at(half, s, from)
		path.append(gate_outer(half, s, at))
		path.append(gate_inner(half, s, at))
	elif not from_in and not to_in and crosses_castle(half, from, to):
		var a := side_of(from)
		var b := side_of(to)
		var at_a := nearest_gate_at(half, a, from)
		path.append(gate_outer(half, a, at_a))
		path.append(gate_inner(half, a, at_a))
		if b != a:
			var at_b := nearest_gate_at(half, b, to)
			path.append(gate_inner(half, b, at_b))
			path.append(gate_outer(half, b, at_b))
		else:
			var at_b := nearest_gate_at(half, b, to)
			if at_b != at_a:
				path.append(gate_inner(half, b, at_b))
				path.append(gate_outer(half, b, at_b))
	path.append(to)
	return path


static func is_inside(half: float, p: Vector3) -> bool:
	return p.y > Balance.WALL_H / 2.0 or maxf(absf(p.x), absf(p.z)) < half + Balance.WALL_T


## 수평 선분 a→b가 성 바깥 경계 정사각형(±(half + WALL_T))을 지나는지 (슬랩 테스트).
static func crosses_castle(half: float, a: Vector3, b: Vector3) -> bool:
	var r := half + Balance.WALL_T
	var o := Vector2(a.x, a.z)
	var d := Vector2(b.x - a.x, b.z - a.z)
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
		if absf(d[axis]) < 1e-6:
			if absf(o[axis]) > r:
				return false
			continue
		var ta := (-r - o[axis]) / d[axis]
		var tb := (r - o[axis]) / d[axis]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return false
	return true


## 겹침 해소(crowd.gd)의 밀림 from → to를 from의 자리 안으로 되돌린다 — 밀림은 성벽·성문을 넘기지 않는다(드나드는 건 제 걸음으로만).
## 성벽 위: 그 면 성벽 길 안에서만(중심선 ± WALK_HALF — 둘이 나란히 비켜 지나갈 폭, 모서리 탑 앞까지, 높이 그대로. 계단 윗단처럼 길 밖이면 깊이도 그대로).
## 성 밖: 바깥면 밖·맵 안(성문이 닫혔든 부서졌든 밀려 들어가지 않는다).
## 성문 통로(성벽 띠): 성문 폭 안, 바깥면 안쪽. 성 안: 안쪽 면 안, 건물 부지 밖(밖에서 밀려 들어가는 축만 부지 가장자리에 붙인다).
static func clamp_push(half: float, from: Vector3, to: Vector3) -> Vector3:
	var outer := half + Balance.WALL_T
	if region(half, from) == REGION_WALL:
		var s := side_of(from)
		var t := perp(s)
		var lim := half + Balance.WALL_T / 2.0 - Balance.TOWER_SIZE / 2.0
		var mid := half + Balance.WALL_T / 2.0
		var depth := SIDE_DIR[s].dot(from)
		if absf(depth - mid) <= WALK_HALF:
			depth = clampf(SIDE_DIR[s].dot(to), mid - WALK_HALF, mid + WALK_HALF)
		return SIDE_DIR[s] * depth + t * clampf(t.dot(to), -lim, lim) + Vector3(0, from.y, 0)
	if not is_inside(half, from):
		var out := Vector3(clampf(to.x, -Balance.MAP_HALF, Balance.MAP_HALF), to.y, clampf(to.z, -Balance.MAP_HALF, Balance.MAP_HALF))
		if maxf(absf(out.x), absf(out.z)) < outer:
			if absf(from.x) >= absf(from.z):
				out.x = signf(from.x) * outer
			else:
				out.z = signf(from.z) * outer
		return out
	if maxf(absf(from.x), absf(from.z)) >= half:
		var s := side_of(from)
		var t := perp(s)
		var at := nearest_gate_at(half, s, from)
		var p := to + t * (clampf(t.dot(to), at - Balance.GATE_W / 2.0, at + Balance.GATE_W / 2.0) - t.dot(to))
		return p - SIDE_DIR[s] * maxf(0.0, SIDE_DIR[s].dot(p) - (outer - 0.01))
	var lim := half - 0.01
	var out := Vector3(clampf(to.x, -lim, lim), to.y, clampf(to.z, -lim, lim))
	for b in Balance.BUILDINGS:
		var lo := Vector2(b.cell) * Balance.TILE
		var hi := lo + Vector2(b.size) * Balance.TILE
		if out.x > lo.x and out.x < hi.x and out.z > lo.y and out.z < hi.y \
				and not (from.x > lo.x and from.x < hi.x and from.z > lo.y and from.z < hi.y):
			if from.x <= lo.x:
				out.x = lo.x
			elif from.x >= hi.x:
				out.x = hi.x
			if from.z <= lo.y:
				out.z = lo.y
			elif from.z >= hi.y:
				out.z = hi.y
	return out


## 높이를 무시한 수평 거리. 사거리 판정은 전부 이것으로 한다.
static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- 병사 자리(개정 13 §7) ---

## 병종 → 대열 자리: 보병은 앞줄(성문 쪽 z 큰 쪽), 궁병은 뒷줄(성채 쪽), 기병은 양 끝 열. 표에 없는 병종은 보병처럼 앞줄.
const SOLDIER_LINE := {"infantry": "front", "archer": "back", "cavalry": "flank"}
const SOLDIER_FIRST := ["flank", "front", "back"]  # 자리를 고르는 순서 — 기병이 먼저 양 끝을 잡는다


## 격자 크기 Vector2i(열, 줄) = (11, 6): Balance.SOLDIER_X·Z 범위를 SOLDIER_GAP 간격으로.
static func soldier_grid() -> Vector2i:
	return Vector2i(floori((Balance.SOLDIER_X.y - Balance.SOLDIER_X.x) / Balance.SOLDIER_GAP + 0.001) + 1,
		floori((Balance.SOLDIER_Z.y - Balance.SOLDIER_Z.x) / Balance.SOLDIER_GAP + 0.001) + 1)


## 병사 자리(순수 함수). units = [{type, tier}] → 같은 순서의 자리 Vector3(칸이 모자라 못 선 병사는 null, 최대 66칸).
## 같은 병종은 티어 높은 순으로 가운데부터(기병은 양 끝 열의 앞부터) 채운다. 기병은 말이 길어(≈ 1.65 m) 한 줄 건너(0, 2, 4줄) 먼저 선다.
static func soldier_spots(units: Array) -> Array:
	var size := soldier_grid()
	var mid := (size.x - 1) / 2.0
	var out := []
	out.resize(units.size())
	var taken := {}
	for line in SOLDIER_FIRST:
		var mine := range(units.size()).filter(func(i): return SOLDIER_LINE.get(units[i].type, "front") == line)
		mine.sort_custom(func(a, b): return units[a].tier > units[b].tier or (units[a].tier == units[b].tier and a < b))
		var cells := []  # [우선순위, 칸(열, 줄 — 줄 0 = 앞)]
		for c in size.x:
			for r in size.y:
				var key: float
				match line:
					"flank": key = mini(c, size.x - 1 - c) * 1000.0 + (r % 2) * 100.0 + r * 10.0 + c * 0.01
					"back": key = (size.y - 1 - r) * 1000.0 + absf(c - mid) * 10.0 + c * 0.01
					_: key = r * 1000.0 + absf(c - mid) * 10.0 + c * 0.01
				cells.append([key, Vector2i(c, r)])
		cells.sort_custom(func(a, b): return a[0] < b[0])
		var k := 0
		for i in mine:
			while k < cells.size() and taken.has(cells[k][1]):
				k += 1
			if k == cells.size():
				break
			var cell: Vector2i = cells[k][1]
			taken[cell] = true
			out[i] = Vector3(Balance.SOLDIER_X.x + cell.x * Balance.SOLDIER_GAP, 0.0, Balance.SOLDIER_Z.x + (size.y - 1 - cell.y) * Balance.SOLDIER_GAP)
	return out


# --- 병사 역할 자리(개정 21 §2) ---

const SOLDIER_WALL_OFFSETS := [2.5, 6.0, 10.0, 13.0]  # 성벽 위 병사 자리 좌우 거리 — 그 뒤로 3.5 m씩(모서리 탑 앞까지). 영웅 자리 ±4·±8과 엇갈린다
const SOLDIER_WALL_STEP := 3.5
const SOLDIER_WALL_OUT := 0.5  # 성벽 중심선(영웅 자리·계단 윗단 착지점 줄)보다 총안 쪽으로. 넘치면 둘째 줄은 안쪽
const GATE_ROW_FIRST := 3.2  # 보병 첫 줄: 성벽 바깥면에서(영웅 성문 앞 자리 1.5 m보다 바깥)
const GATE_ROW_GAP := 1.6
const GATE_ROWS := [[0.0, -2.4, 2.4], [-1.0, 1.0, -3.2, 3.2]]  # 줄마다 번갈아(가운데부터)
const INNER_ROW_FIRST := 1.0  # 성문이 부서지면: 성벽 안쪽 면에서 막는 첫 줄까지
const INNER_ROWS := [[0.0, -1.2, 1.2], [-0.6, 0.6, -1.8, 1.8]]  # 성문 폭 안(계단 띠 ±2.5 밖은 안 쓴다)
const PATROL_OUT := 7.0  # 기병 순찰 고리 반지름 = half + WALL_T + 이만큼


## 성벽 위 병사 자리 좌우 거리 [+2.5, -2.5, +6, -6, …] — 모서리 탑(중심선 끝 − 탑 반 − 0.5 m) 앞까지.
## 가운데가 아닌 성문 위(성문 중앙 ± 성문 반폭 + 계단 틈 + 0.5 m)는 비운다(가운데 성문 위는 첫 자리 2.5 m가 이미 비운다). 영웅 자리(wall_top_offsets) 1 m 안도 비운다.
static func soldier_wall_offsets(half: float) -> Array:
	var limit := half + Balance.WALL_T / 2.0 - Balance.TOWER_SIZE / 2.0 - 0.5
	var clear := Balance.GATE_W / 2.0 + Balance.STAIR_GAP + 0.5
	var gates_at := gate_offsets(half).filter(func(a): return absf(a) > 0.01)
	var heroes_at := wall_top_offsets(half)
	var out := []
	var d: float = SOLDIER_WALL_OFFSETS[0]
	var i := 0
	while d <= limit:
		if not gates_at.any(func(a): return absf(absf(a) - d) < clear) and not heroes_at.any(func(a): return absf(absf(a) - d) < 1.0):
			out.append_array([d, -d])
		i += 1
		d = SOLDIER_WALL_OFFSETS[i] if i < SOLDIER_WALL_OFFSETS.size() else d + SOLDIER_WALL_STEP
	return out


## 면 side의 k번째 궁병 성벽 자리(y = WALL_H). 칸이 모자라면 둘째 줄(중심선 안쪽)을 쓰고, 그것도 넘치면 다시 첫 줄과 겹친다.
static func soldier_wall_spot(half: float, side: int, k: int) -> Vector3:
	var offs := soldier_wall_offsets(half)
	var row := (k / offs.size()) % 2
	var depth := half + Balance.WALL_T / 2.0 + (SOLDIER_WALL_OUT if row == 0 else -SOLDIER_WALL_OUT)
	return SIDE_DIR[side] * depth + perp(side) * float(offs[k % offs.size()]) + Vector3(0, Balance.WALL_H, 0)


## 면 side의 k번째 보병이 맡는 성문 번호(성문마다 돌아가며 — k % n).
static func gate_row_gate(half: float, k: int) -> int:
	return k % gates_per_side(half)


## 면 side의 k번째 보병 자리: 성문 gate_row_gate(k) 앞 줄(3.2 m 줄 3칸, 4.8 m 줄 4칸, … 번갈아 — 그 성문의 k / n번째).
## inner = 그 성문이 부서져 안쪽 통로 앞을 막는 줄.
static func gate_row_spot(half: float, side: int, k: int, inner := false) -> Vector3:
	var n := gates_per_side(half)
	var at := gate_offset(half, k % n, n)
	k /= n
	var rows: Array = INNER_ROWS if inner else GATE_ROWS
	var r := 0
	while k >= rows[r % 2].size():
		k -= rows[r % 2].size()
		r += 1
	var depth := half - INNER_ROW_FIRST - r * GATE_ROW_GAP if inner else half + Balance.WALL_T + GATE_ROW_FIRST + r * GATE_ROW_GAP
	return SIDE_DIR[side] * depth + perp(side) * (at + float(rows[r % 2][k]))


static func patrol_radius(half: float) -> float:
	return half + Balance.WALL_T + PATROL_OUT


## 기병 순찰 점: 면 side 성문 앞 → 고리 꼭짓점(모서리) → 옆 면(dir = +1 시계 방향, −1 반대) 성문 앞. 이 셋을 오간다.
static func patrol_points(half: float, side: int, dir: int) -> Array[Vector3]:
	var r := patrol_radius(half)
	var next := (side + dir + 4) % 4
	return [SIDE_DIR[side] * r, (SIDE_DIR[side] + SIDE_DIR[next]) * r, SIDE_DIR[next] * r]


## 성 밖 두 점 사이 기병 경로(도착점 포함): 곧장 가면 성을 가로지를 때만 순찰 고리 꼭짓점을 돈다(성 안으로 들어가지 않는다).
static func ring_route(half: float, from: Vector3, to: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if crosses_castle(half, from, to):
		var r := patrol_radius(half)
		var sa := side_of(from)
		var sb := side_of(to)
		if (sa + 2) % 4 != sb:
			out.append((SIDE_DIR[sa] + SIDE_DIR[sb]) * r)
		else:
			var t := 1.0 if perp(sa).dot(from + to) >= 0.0 else -1.0
			out.append((SIDE_DIR[sa] + perp(sa) * t) * r)
			out.append((SIDE_DIR[sb] + perp(sa) * t) * r)
	out.append(to)
	return out


## 등장 자리(성채 정문 앞 광장) → 역할 자리: 광장 가운데 길(x = 0)로 나가 남문 안쪽을 거쳐 route()로 — 건물을 가로지르지 않는다.
## 남쪽 가운데 성문이 없으면(성문 2개) 남쪽 안쪽 통로 가운데로 나가 거기서 route() — 통로를 따라 성문으로 간다.
static func soldier_entry_route(half: float, spot: Vector3, post: Vector3) -> Array[Vector3]:
	var south := gate_inner(half, 2)
	var out: Array[Vector3] = [Vector3(0, 0, spot.z), south]
	out.append_array(route(half, south, post))
	return out


## 경로 길이(from에서 점들을 차례로 잇는 수평 거리 합).
static func path_length(from: Vector3, path: Array) -> float:
	var d := 0.0
	var prev := from
	for p in path:
		d += flat_distance(prev, p)
		prev = p
	return d

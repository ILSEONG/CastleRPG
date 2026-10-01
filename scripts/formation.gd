extends RefCounted
## 영웅 배치: 면(side)마다 성문 앞(POST_GATE)·성벽 위(POST_WALL) 슬롯 점유와 위치 계산.
## 씬·오토로드 의존 없음. 위치 함수는 static이고 성 내부 절반 크기(half)를 인자로 받는다.
## side: 0=N(-z) 1=E(+x) 2=S(+z) 3=W(-x)

const Balance := preload("res://scripts/balance.gd")

const POST_GATE := 0
const POST_WALL := 1
const POST_FREE := 2          # 자유 위치 (슬롯 없음)
const GATE_PASS_MARGIN := 1.0 # 성문 통과 지점·계단 앞 지점이 성벽 바깥면·계단 띠에서 떨어진 거리
const REGION_OUTSIDE := 0
const REGION_INSIDE := 1
const REGION_WALL := 2    # 성벽 위(계단 윗부분 포함)
const SIDE_DIR: Array[Vector3] = [
	Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0),
]
const SIDE_NAMES := ["북", "동", "남", "서"]  # 면 방향 이름(HUD 성문 막대·문루 글자)

static var _keep_half: float = Balance.building("keep").size.x * Balance.TILE / 2.0  # 성채 외벽 절반 크기. 로드 때 한 번 계산

var _claims := {}  # hero_id -> {"side": int, "post": int, "slot": int}


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
	for slot in capacity(post):
		if not taken.has(slot):
			_claims[hero_id] = {"side": side, "post": post, "slot": slot}
			return slot
	return -1


func release(hero_id: int) -> void:
	_claims.erase(hero_id)


func assignment(hero_id: int) -> Dictionary:
	return _claims.get(hero_id, {})


static func capacity(post: int) -> int:
	return Balance.GATE_FRONT_SLOTS.size() if post == POST_GATE else Balance.WALL_TOP_SLOTS.size()


static func perp(side: int) -> Vector3:
	var dir := SIDE_DIR[side]
	return Vector3(-dir.z, 0, dir.x)


## 성벽 중심선 위의 성문 중앙 (지면).
static func gate_position(half: float, side: int) -> Vector3:
	return SIDE_DIR[side] * (half + Balance.WALL_T / 2.0)


## 괴물이 성문을 치려고 서는 지점 (성벽 바깥면 바로 앞).
static func gate_target(half: float, side: int) -> Vector3:
	return SIDE_DIR[side] * (half + Balance.WALL_T + 0.8)


static func slot_position(half: float, side: int, post: int, slot: int) -> Vector3:
	var dir := SIDE_DIR[side]
	if post == POST_GATE:
		return dir * (half + Balance.WALL_T + Balance.GATE_FRONT_OFFSET) \
			+ perp(side) * float(Balance.GATE_FRONT_SLOTS[slot])
	return dir * (half + Balance.WALL_T / 2.0) + perp(side) * float(Balance.WALL_TOP_SLOTS[slot]) \
		+ Vector3(0, Balance.WALL_H, 0)


## 성문이 부서진 뒤 괴물이 성채를 치려고 서는 지점 (성채 외벽 바로 앞).
static func keep_target(side: int) -> Vector3:
	return SIDE_DIR[side] * (_keep_half + 0.8)


static func spawn_center(half: float, side: int) -> Vector3:
	return SIDE_DIR[side] * (half + Balance.WALL_T + Balance.SPAWN_MARGIN)


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
static func gate_inner(half: float, side: int) -> Vector3:
	return SIDE_DIR[side] * (half - Balance.STAIR_W - GATE_PASS_MARGIN)


static func gate_outer(half: float, side: int) -> Vector3:
	return SIDE_DIR[side] * (half + Balance.WALL_T + GATE_PASS_MARGIN)


static func region(half: float, p: Vector3) -> int:
	if p.y > Balance.WALL_H / 2.0:
		return REGION_WALL
	if maxf(absf(p.x), absf(p.z)) < half + Balance.WALL_T:
		return REGION_INSIDE
	return REGION_OUTSIDE


## 계단: 각 면 성문 좌우(end = -1/+1)에 하나씩, 성벽 안쪽 면에 붙은 띠에서 성문 쪽으로 올라간다.
static func stair_bottom(half: float, side: int, end: float) -> Vector3:
	return SIDE_DIR[side] * (half - Balance.STAIR_W / 2.0) \
		+ perp(side) * (end * (Balance.GATE_W / 2.0 + Balance.STAIR_GAP + Balance.STAIR_RUN))


static func stair_top(half: float, side: int, end: float) -> Vector3:
	return SIDE_DIR[side] * (half - Balance.STAIR_W / 2.0) \
		+ perp(side) * (end * (Balance.GATE_W / 2.0 + Balance.STAIR_GAP)) + Vector3(0, Balance.WALL_H, 0)


## 계단 윗단에서 성벽 중심선으로 올라선 지점.
static func wall_landing(half: float, side: int, end: float) -> Vector3:
	return SIDE_DIR[side] * (half + Balance.WALL_T / 2.0) \
		+ perp(side) * (end * (Balance.GATE_W / 2.0 + Balance.STAIR_GAP)) + Vector3(0, Balance.WALL_H, 0)


## 계단 아랫단 너머 지상 지점(계단 띠 밖). 지상 구간은 여기까지만 오고, 띠에는 아랫단 너머로만 들어간다.
static func stair_approach(half: float, side: int, end: float) -> Vector3:
	return SIDE_DIR[side] * (half - Balance.STAIR_W - GATE_PASS_MARGIN) \
		+ perp(side) * (end * (Balance.GATE_W / 2.0 + Balance.STAIR_GAP + Balance.STAIR_RUN + GATE_PASS_MARGIN))


static func _stair_end(side: int, p: Vector3) -> float:
	return 1.0 if perp(side).dot(p) >= 0.0 else -1.0


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
		var e := _stair_end(s, from)
		path.append(wall_landing(half, s, e))
		path.append(stair_top(half, s, e))
		path.append(stair_bottom(half, s, e))
		ground_from = stair_approach(half, s, e)
		path.append(ground_from)
	var ground_to := to
	var tail: Array[Vector3] = []
	if to_wall:
		var s2 := side_of(to)
		var e2 := _stair_end(s2, to)
		ground_to = stair_approach(half, s2, e2)
		tail = [stair_bottom(half, s2, e2), stair_top(half, s2, e2), wall_landing(half, s2, e2), to]
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
		path.append(gate_inner(half, s))
		path.append(gate_outer(half, s))
	elif not from_in and to_in:
		var s := side_of(from)
		path.append(gate_outer(half, s))
		path.append(gate_inner(half, s))
	elif not from_in and not to_in and crosses_castle(half, from, to):
		var a := side_of(from)
		var b := side_of(to)
		path.append(gate_outer(half, a))
		path.append(gate_inner(half, a))
		if b != a:
			path.append(gate_inner(half, b))
			path.append(gate_outer(half, b))
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


## 높이를 무시한 수평 거리. 사거리 판정은 전부 이것으로 한다.
static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

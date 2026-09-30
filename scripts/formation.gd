extends RefCounted
## 영웅 배치: 면(side)마다 성문 앞(POST_GATE)·성벽 위(POST_WALL) 슬롯 점유와 위치 계산.
## 씬·오토로드 의존 없음. 위치 함수는 static이고 성 내부 절반 크기(half)를 인자로 받는다.
## side: 0=N(-z) 1=E(+x) 2=S(+z) 3=W(-x)

const Balance := preload("res://scripts/balance.gd")

const POST_GATE := 0
const POST_WALL := 1
const POST_FREE := 2          # 자유 위치 (슬롯 없음)
const GATE_PASS_MARGIN := 1.0 # 성문 통과 지점이 성벽에서 떨어진 거리
const SIDE_DIR: Array[Vector3] = [
	Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0),
]

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


static func gate_inner(half: float, side: int) -> Vector3:
	return SIDE_DIR[side] * (half - GATE_PASS_MARGIN)


static func gate_outer(half: float, side: int) -> Vector3:
	return SIDE_DIR[side] * (half + Balance.WALL_T + GATE_PASS_MARGIN)


## from → to 이동 경로 (도착점 포함). 성 안팎을 오가거나 성을 가로지를 때는 성문을 지난다.
## "안" = 성벽 위(높이 > WALL_H/2)이거나 성벽 바깥면 안쪽(crosses_castle과 같은 경계). 문짝 상태와 무관하게 아군은 통과.
static func route(half: float, from: Vector3, to: Vector3) -> Array[Vector3]:
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

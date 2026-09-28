extends RefCounted
## 영웅 배치: 면(side)마다 성문 앞(POST_GATE)·성벽 위(POST_WALL) 슬롯 점유와 위치 계산.
## 씬·오토로드 의존 없음. 위치 함수는 static이고 성 내부 절반 크기(half)를 인자로 받는다.
## side: 0=N(-z) 1=E(+x) 2=S(+z) 3=W(-x)

const Balance := preload("res://scripts/balance.gd")

const POST_GATE := 0
const POST_WALL := 1
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


## 높이를 무시한 수평 거리. 사거리 판정은 전부 이것으로 한다.
static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

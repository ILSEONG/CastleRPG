extends Node
## 유닛이 바닥을 차지한다(서로 겹치지 않음). 영웅·병사·몬스터는 _ready에서 "crowd" 그룹에 들고(죽거나 트리를 떠나면 빠진다)
## radius()(몸 반지름 m)와 push_mass()(밀리는 무게)를 낸다. 매 프레임 모든 유닛이 움직인 뒤(process_priority) 이 노드가 한 번:
## 같은 부모(성 월드·던전 장면) 아래 살아 있는 유닛을 공간 해시(CELL m 칸)에 넣어 이웃 쌍을 모으고, PASSES번 돌며 겹친 만큼
## 바닥 평면에서 밀어낸다 — 무게의 역수로 나눈다(자리를 지키거나 싸우는 유닛·덩치 큰 보스는 덜 밀린다).
## 처리가 꺼진 유닛과 push_mass() = INF(돌진하는 데스나이트)는 밀리지 않는다(남은 민다. 둘 다 그러면 그냥 겹친다).
## 같은 층(지상·성벽 위)끼리만 부딪고, 계단을 오르내리거나 땅에서 솟는 중이면 빠진다.
## 밀린 자리는 Formation.clamp_push(성 전장 — 성벽·성문을 넘지 않고, 성벽 위는 성벽을 따라서만, 건물 부지·맵 밖 금지)나
## 아레나 반경(arena_r)으로 되돌린다. 사거리는 그대로 중심 거리 — 근접 사거리는 모두 맞닿는 거리(반지름 합)보다 길다(run_tests).
# ponytail: GDScript 해시(Dictionary) + 가우스-자이델 PASSES번. 유닛 200에 헤드리스 수 ms 안(run_tests가 시간을 찍는다).
# 400을 넘거나 모바일에서 프레임을 먹으면 칸 버킷을 고정 배열로 바꾸거나 GDExtension으로.

const Balance := preload("res://scripts/balance.gd")
const Formation := preload("res://scripts/formation.gd")

const HUMAN_R := 0.45  # 사람 몸(모델 배율 1) — 영웅. 병사는 × SOLDIER_SCALE
const CAVALRY_R := 0.6  # 말 탄 기병(말이 길어 앞뒤로는 조금 겹쳐 보인다)
const MONSTER_R := {"grunt": 0.4, "goblin": 0.35, "epic_boss": 0.5, "goblin_king": 0.47, "death_knight": 0.45}  # × 몬스터 표 scale
const BRACED := 4.0  # 걷는 중이 아니면(자리를 지킴·공격) 무게 ×
const CELL := 2.5  # 해시 칸(m) ≥ 가장 큰 반지름 합 + SLACK
const SLACK := 0.3  # 이웃 쌍: 반지름 합 + 이만큼 안(해소 중 밀려 가까워지는 쌍까지)
const PASSES := 3
const PASS_R := 0.5  # 경로 중간 점·순찰 점은 이만큼 안이면 지나간 것(arrive_r)
const LEVEL_EPS := 0.3
const NEIGHBORS := [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(-1, 1, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0)]  # 자기 칸 + 반쪽 이웃(쌍을 한 번씩)

var half := -1.0  # 성 내부 절반(성 전장). 음수 = 아레나
var arena_r := INF  # 아레나: 중심에서 이 반경 밖으로 밀지 않는다
var enabled := true  # 테스트가 끈다(겹침 검사가 무는지 확인)
var last_usec := 0  # 지난 해소에 걸린 시간(µs)

var _from := PackedVector2Array()
var _lv := PackedInt32Array()
var _prev := {}  # 유닛 → 지난 해소 뒤 바닥 위치(이번 프레임 제 걸음 = 지금 − 이것)


func _init() -> void:
	process_priority = 100  # 유닛들의 _process 뒤


## 밀리는 무게 = 반지름² × (걷는 중이 아니면 BRACED).
static func mass(r: float, braced: bool) -> float:
	return r * r * (BRACED if braced else 1.0)


## 경로 점 도착 거리: 다음 점과 같은 높이로 이어지는 중간 점은 PASS_R 안이면 지나간 것으로 친다 — 그 점에 다른 유닛이 서 있어도
## (성문 통과 지점 바로 앞 성문 영웅 등) 막히지 않는다. 마지막 점(자리)·계단 끝(높이가 바뀌는 점)은 eps 그대로.
static func arrive_r(path: Array, eps: float) -> float:
	return PASS_R if path.size() > 1 and is_equal_approx(path[0].y, path[1].y) else eps


## 층: 0 = 지상, 1 = 성벽 위, -1 = 그 사이(계단·솟는 중 — 부딪지 않음).
static func level(y: float) -> int:
	if absf(y) < LEVEL_EPS:
		return 0
	if absf(y - Balance.WALL_H) < LEVEL_EPS:
		return 1
	return -1


func _process(_delta: float) -> void:
	if not enabled:
		return
	var t0 := Time.get_ticks_usec()
	var units := []
	var p := PackedVector2Array()
	var r := PackedFloat32Array()
	var w := PackedFloat32Array()
	var lv := PackedInt32Array()
	var mv := PackedVector2Array()
	var parent := get_parent()
	for u in get_tree().get_nodes_in_group("crowd"):
		if u.get_parent() != parent or not u.is_alive():
			continue
		var g: Vector3 = u.global_position
		var l := level(g.y)
		if l < 0:
			continue
		var g2 := Vector2(g.x, g.z)
		units.append(u)
		p.append(g2)
		r.append(u.radius())
		w.append(1.0 / u.push_mass() if u.is_processing() else 0.0)  # 1 / INF = 0
		lv.append(l)
		mv.append(g2 - _prev.get(u, g2))
	var q := separate(p, r, w, lv, mv)
	_prev = {}
	for i in units.size():
		var u = units[i]
		_prev[u] = q[i]
		if q[i] != p[i]:
			u.global_position = Vector3(q[i].x, u.global_position.y, q[i].y)
	last_usec = Time.get_ticks_usec() - t0


## 겹침 해소(순수 — run_tests가 직접 부른다). p·r·w·lv·mv = 바닥 위치(x, z)·반지름·무게 역수(0 = 안 밀림)·층·이번 프레임 제 걸음.
## 밀린 뒤 위치.
func separate(p: PackedVector2Array, r: PackedFloat32Array, w: PackedFloat32Array, lv: PackedInt32Array, mv: PackedVector2Array) -> PackedVector2Array:
	var cells := {}
	for i in p.size():
		var k := Vector3i(floori(p[i].x / CELL), floori(p[i].y / CELL), lv[i])
		if cells.has(k):
			cells[k].append(i)
		else:
			cells[k] = [i]
	var pairs := PackedInt32Array()
	for k in cells:
		var a: Array = cells[k]
		for o in NEIGHBORS:
			var b = cells.get(k + o)
			if b == null:
				continue
			for x in a.size():
				var i: int = a[x]
				for y in range(x + 1 if o == Vector3i.ZERO else 0, b.size()):
					var j: int = b[y]
					var reach := r[i] + r[j] + SLACK
					if w[i] + w[j] > 0.0 and p[i].distance_squared_to(p[j]) < reach * reach:
						pairs.append(i)
						pairs.append(j)
	_from = p
	_lv = lv
	var q := p.duplicate()
	for pass_i in PASSES:
		for t in range(0, pairs.size(), 2):
			var i := pairs[t]
			var j := pairs[t + 1]
			var d := q[i] - q[j]
			var need := r[i] + r[j]
			var dd := d.length_squared()
			if dd >= need * need:
				continue
			var dist := sqrt(dd)
			var n := d / dist if dist > 1e-4 else Vector2.from_angle(i * 2.4)  # 같은 자리: 유닛마다 다른 고정 방향(재현)
			var o := (need - dist) / (w[i] + w[j])
			q[i] += (n + _slide(n, mv[i])) * o * w[i]
			q[j] += (_slide(-n, mv[j]) - n) * o * w[j]
		for i in q.size():
			if q[i] != p[i]:
				q[i] = _keep(i, q[i])
	return q


## 상대 쪽으로 걸어 들어갔으면(제 걸음 m이 밀리는 방향 n의 반대) 밀린 만큼 옆으로도 미끄러진다 — 이미 비껴가던 쪽, 정면이면 n의 왼쪽.
## 마주 걷는 둘이나 길목에 선 유닛 뒤의 유닛이 정면으로 막혀 멈추지 않고 돌아간다.
static func _slide(n: Vector2, m: Vector2) -> Vector2:
	if m.dot(n) >= 0.0:
		return Vector2.ZERO
	var t := n.orthogonal()
	return t if t.dot(m) >= 0.0 else -t


## 밀린 자리 to를 유닛 i가 있던 자리 안으로 되돌린다.
func _keep(i: int, to: Vector2) -> Vector2:
	if half < 0.0:
		return to.limit_length(maxf(arena_r, _from[i].length()))
	var y := Balance.WALL_H if _lv[i] == 1 else 0.0
	var v := Formation.clamp_push(half, Vector3(_from[i].x, y, _from[i].y), Vector3(to.x, y, to.y))
	return Vector2(v.x, v.z)

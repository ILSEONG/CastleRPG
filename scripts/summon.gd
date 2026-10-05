extends Node3D
## 소환수(100 스킬 설계 "Summon API"): 영웅 스킬이 불러내는 짧게 사는 아군. 체력이 없고 몬스터의 표적이 되지 않는다(그룹 "summons"만,
## "crowd"·"heroes"엔 넣지 않는다).
## 사용(add_child 전에 setup):
##   var s = SummonScript.new()
##   s.setup(owner_hero, kind, dmg, sec, color)
##   hero.get_parent().add_child(s)
##   s.global_position = hero.global_position + offset
## 종류(KINDS): wolf(빠른 근접)·skeleton(근접)·golem(느리고 큰 근접, 맞히면 1 m 밀침)·treant(근접, 맞히면 0.5초 속박)·
## spirit(떠 있는 원거리 마법탄)·phoenix(나는 원거리 불탄, 맞히면 화상)·hawk(나는 빠른 급강하 근접)·turret(고정 원거리 화살).
## 행동: SCAN_INTERVAL초마다 자기 둘레 SCAN_R m 안 가장 가까운 산 몬스터를 고른다 — 성 모드면 성벽 같은 쪽(Formation.is_inside가 같은)만,
## 성벽 위 포탑은 영역 무관(성벽 위 궁수처럼). 표적이 없으면 주인 곁(FOLLOW_R m)으로 간다 — 다른 영역이면 성문 경로(Formation.route,
## 나는 것은 곧장), 포탑은 제자리. 수명 sec초(주인이 죽어도 남는다)가 끝나면 연기와 함께 사라지고, 성 모드에서는 GameState.refilled에 바로 사라진다.
## 피해 = dmg(쓰는 쪽이 계산해 넘긴다) → m.take_damage(dmg, DamageNumbers.Kind.SKILL). 추가 효과(knockback·apply_root·apply_dot)는
## 몬스터에 그 함수가 있을 때만 부른다.
## 모양: MeshKit 로우폴리 부품 ≤ 3개(MeshInstance3D, 그림자 없음, Fx 공유 재질) — 몸통은 주인 색 섞음, 눈·부리·불꽃 등은 고정 강조색.
## 메시는 (종류, 색)마다 한 번 만들어 캐시한다. 걷기 흔들림·날갯짓·공격 돌진(나는 것은 급강하)은 매 프레임 부품 변환만 바꾼다(할당 없음).
## 성벽 위 주인이 부르면(첫 프레임에 위치가 성벽 높이) 움직이는 소환수는 그 면 성벽 바깥 땅으로 내려선다 — 포탑만 성벽 위에 남는다.

const Balance := preload("res://scripts/balance.gd")
const Formation := preload("res://scripts/formation.gd")
const Fx := preload("res://scripts/fx.gd")
const MeshKit := preload("res://scripts/mesh_kit.gd")
const DamageNumbers := preload("res://scripts/damage_numbers.gd")
const ProjectileScript := preload("res://scripts/projectile.gd")

const GROUP := "summons"
const KINDS := ["wolf", "skeleton", "golem", "treant", "spirit", "phoenix", "hawk", "turret"]
## 종류 → [이동 m/s, 공격 간격 초, 사거리 m, 투사체 모양("" = 근접), 떠 있는 높이 m(0 = 지상), 투사체 속도 m/s]
const STATS := {
	"wolf": [7.0, 0.7, 1.2, "", 0.0, 0.0],
	"skeleton": [4.0, 1.0, 1.2, "", 0.0, 0.0],
	"golem": [2.6, 1.4, 1.4, "", 0.0, 0.0],
	"treant": [3.0, 1.0, 1.3, "", 0.0, 0.0],
	"spirit": [5.0, 1.0, 6.0, "bolt", 1.2, 14.0],
	"phoenix": [6.0, 1.0, 7.0, "bolt", 1.6, 16.0],
	"hawk": [8.0, 0.7, 1.2, "", 1.5, 0.0],
	"turret": [0.0, 1.0, 9.0, "arrow", 0.0, 30.0],
}
const SCAN_INTERVAL := 0.2
const SCAN_R := 10.0  # 표적을 찾는 반경(포탑은 사거리)
const HIT_DELAY := 0.16  # 공격 시작에서 타격(발사) 순간까지
const SWING_SLACK := 0.6  # 근접 타격 순간 사거리 + 이만큼 안이면 맞는다
const LUNGE_SEC := 0.34  # 돌진(급강하) 모션 길이
const FOLLOW_R := 2.3  # 주인에서 이만큼 떨어진 제 자리(각도는 소환수마다)
const FOLLOW_SLACK := 0.9  # 제 자리에서 이만큼 벗어나면 다시 걷는다(주인 2~3 m 안)
const CATCH_UP := 6.0  # 제 자리에서 이만큼 멀면 1.6배로 따라잡는다
const ARRIVE := 0.12
const WALL_DROP := 1.5  # 성벽 위 주인 → 그 면 성벽 바깥면에서 이만큼 밖 땅
const SPAWN_SEC := 0.25  # 등장 시 커지는 시간
const FIRE := Color(1.0, 0.45, 0.1)
const GOLD := Color(1.0, 0.8, 0.22)
const BURN_RATIO := 0.3  # 불사조 화상 초당 피해 = dmg × 이만큼
const BURN_SEC := 2.0
const ROOT_SEC := 0.5
const KNOCK_M := 1.0

static var _meshes := {}  # "종류#색" -> [[메시, 관절 위치, 재질 0 = 정점 색 / 1 = 가산 빛 / 2 = 반투명], …]

var kind := "wolf"
var owner_hero
var castle
var dmg := 0.0
var life := 0.0  # 남은 초
var color := Color.WHITE
var hits := 0  # 맞힌(근접 타격·투사체 발사) 횟수 — 테스트용

var _speed := 0.0
var _interval := 1.0
var _range := 1.2
var _shot := ""
var _shot_speed := 0.0
var _hover := 0.0
var _flies := false
var _on_wall := false  # 성벽 위 포탑
var _settled := false
var _ending := false
var _target
var _swing
var _swing_left := -1.0
var _atk_cd := 0.0
var _scan_cd := 0.0
var _goal := Vector3.ZERO  # 따라갈 제 자리(스캔 때 갱신)
var _goal_ok := false
var _path: Array[Vector3] = []  # 다른 영역의 제 자리로 가는 성문 경로
var _offset := Vector3.ZERO  # 주인 기준 제 자리 방향 × FOLLOW_R
var _age := 0.0
var _phase := 0.0  # 걷기·날갯짓 위상
var _lunge := 1.0  # 돌진 진행(0..1, 1 = 끝)
var _moved := false
var _following := false  # 제 자리로 걷는 중(제 자리에 닿을 때까지 — FOLLOW_SLACK 경계에서 멈칫거리지 않게)
var _walk := 0.0  # 걷기 흔들림 세기(0..1)
var _yaw := 0.0
var _pivot: Node3D
var _parts: Array[MeshInstance3D] = []


## add_child 전에 호출. owner_hero = 부른 영웅(나중에 해제될 수 있다), p_kind = KINDS 중 하나(모르면 wolf), p_dmg = 한 번 피해,
## sec = 수명(초), p_color = 몸통에 섞을 색(주인 고유 색).
func setup(p_owner, p_kind: String, p_dmg: float, sec: float, p_color: Color) -> void:
	owner_hero = p_owner
	kind = p_kind if STATS.has(p_kind) else "wolf"
	dmg = p_dmg
	life = sec
	color = p_color
	castle = p_owner.get("castle") if is_instance_valid(p_owner) else null
	var s: Array = STATS[kind]
	_speed = s[0]
	_interval = s[1]
	_range = s[2]
	_shot = s[3]
	_hover = s[4]
	_shot_speed = s[5]
	_flies = _hover > 0.0
	var a := randf() * TAU
	_offset = Vector3(cos(a), 0.0, sin(a)) * FOLLOW_R
	_phase = randf() * TAU
	_atk_cd = randf() * 0.3  # 여럿이 한꺼번에 치지 않게


func _ready() -> void:
	add_to_group(GROUP)
	_pivot = Node3D.new()
	add_child(_pivot)
	for p in parts_of(kind, color):
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.position = p[1]
		mi.material_override = Fx.soft_material() if p[2] == 2 else (Fx.glow_material() if p[2] == 1 else Fx.material())
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pivot.add_child(mi)
		_parts.append(mi)
	_pivot.visible = false  # 첫 프레임에 자리를 잡은 뒤 보인다(_settle)
	if castle != null:
		GameState.refilled.connect(_on_refilled)


func is_alive() -> bool:
	return not _ending


## 남은 수명을 버리고 지금 사라진다(연기).
func dismiss() -> void:
	if _ending:
		return
	_ending = true
	if is_inside_tree():
		_puff(get_parent(), global_position, _hover, color, false)
	queue_free()


func _on_refilled() -> void:
	_ending = true
	queue_free()


func _process(delta: float) -> void:
	if _ending:
		return
	if not _settled:
		_settle()
	_age += delta
	life -= delta
	if life <= 0.0:
		dismiss()
		return
	_atk_cd -= delta
	_moved = false
	if _swing != null:
		_swing_left -= delta
		if _swing_left <= 0.0:
			_release()
	_scan_cd -= delta
	var lost: bool = _target != null and not (is_instance_valid(_target) and _target.is_alive())
	if _scan_cd <= 0.0 or lost:
		_scan_cd = SCAN_INTERVAL
		_target = _find_target()
		if _target != null:
			_path.clear()
		elif _speed > 0.0:
			_update_goal()
	if _target != null:
		_fight(delta)
	elif _speed > 0.0:
		_follow(delta)
	_animate(delta)


## 첫 프레임: 성벽 높이에 놓였으면(성벽 위 주인) 움직이는 소환수는 그 면 성벽 바깥 땅으로 — 포탑은 성벽 위에 남는다. 그리고 등장 연출.
func _settle() -> void:
	_settled = true
	if castle != null and global_position.y > Balance.WALL_H / 2.0:
		if _speed > 0.0:
			global_position = _below_wall(global_position)
		else:
			_on_wall = true
	_goal = global_position
	_pivot.visible = true
	_puff(get_parent(), global_position, _hover * 0.5, color, true)


## 성벽 위 점 p 아래, 그 면 성벽 바깥면에서 WALL_DROP m 밖 땅.
func _below_wall(p: Vector3) -> Vector3:
	var s := Formation.side_of(p)
	var dir: Vector3 = Formation.SIDE_DIR[s]
	var flat := Vector3(p.x, 0.0, p.z)
	return flat + dir * (castle.half + Balance.WALL_T + WALL_DROP - dir.dot(flat))


## 표적: 둘레 SCAN_R(포탑은 사거리) 안 가장 가까운 산 몬스터. 성 모드 지상은 같은 영역만, 성 밖 지상은 성(모서리)을 가로지르는 직선 추격도 뺀다.
func _find_target():
	var reach := _range if _speed <= 0.0 else SCAN_R
	var here := global_position
	var check_region := castle != null and not _on_wall
	var inside := check_region and Formation.is_inside(castle.half, here)
	var best = null
	var best_d := reach
	for m in get_tree().get_nodes_in_group("monsters"):
		var mp: Vector3 = m.global_position
		var d := Vector2(mp.x - here.x, mp.z - here.z).length()
		if d > best_d or not m.is_alive():
			continue
		if check_region:
			if Formation.is_inside(castle.half, mp) != inside:
				continue
			if not inside and not _flies and Formation.crosses_castle(castle.half, here, mp):
				continue
		best_d = d
		best = m
	return best


## 표적과 싸운다: 사거리 밖이면 다가가고(포탑은 제자리), 안이면 간격마다 공격을 시작한다(타격은 HIT_DELAY초 뒤 _release).
func _fight(delta: float) -> void:
	if not (is_instance_valid(_target) and _target.is_alive()):
		_target = null
		return
	var tp: Vector3 = _target.global_position
	var to := Vector3(tp.x - global_position.x, 0.0, tp.z - global_position.z)
	var d := to.length()
	_face(to)
	if d <= _reach(_target):
		if _atk_cd <= 0.0:
			_atk_cd = _interval
			_swing = _target
			_swing_left = HIT_DELAY
			_lunge = 0.0
		return
	if _speed <= 0.0:
		return
	var next := global_position + to / d * minf(_speed * delta, d - _reach(_target) * 0.85)
	if castle != null and not _flies and Formation.is_inside(castle.half, next) != Formation.is_inside(castle.half, global_position):
		_target = null  # 성벽을 넘는 걸음은 딛지 않는다
		return
	global_position = next
	_moved = true


## 사거리: 근접은 큰 몬스터(보스)일수록 조금 멀리서 닿는다.
func _reach(m) -> float:
	if _shot != "":
		return _range
	return _range + maxf(0.0, m.radius() - 0.4)


func _release() -> void:
	var m = _swing
	_swing = null
	if not (is_instance_valid(m) and m.is_alive()) or not is_inside_tree():
		return
	if _shot == "":
		if Formation.flat_distance(global_position, m.global_position) <= _reach(m) + SWING_SLACK:
			hits += 1
			_hit(m)
		return
	hits += 1
	var p = ProjectileScript.new()
	p.target = m
	p.kind = _shot
	p.speed = _shot_speed
	p.color = FIRE if kind == "phoenix" else color.lightened(0.35)
	p.on_hit = _hit
	get_parent().add_child(p)
	p.global_position = global_position + _muzzle()


## 투사체가 나가는 곳(몸 앞).
func _muzzle() -> Vector3:
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	if kind == "turret":
		return Vector3(0, 0.95, 0) + fwd * 0.6
	return Vector3(0, _hover, 0) + fwd * 0.35


## 한 번 맞힘: 피해 + 종류별 추가 효과(몬스터에 그 함수가 있을 때만) + 작은 불꽃.
func _hit(m) -> void:
	if not (is_instance_valid(m) and m.is_alive()):
		return
	m.take_damage(dmg, DamageNumbers.Kind.SKILL)
	match kind:
		"golem":
			if m.has_method("knockback"):
				m.knockback(global_position, KNOCK_M)
		"treant":
			if m.has_method("apply_root"):
				m.apply_root(ROOT_SEC)
		"phoenix":
			if m.has_method("apply_dot"):
				m.apply_dot("burn", dmg * BURN_RATIO, BURN_SEC)
	if is_inside_tree() and is_instance_valid(m):
		Fx.spark(get_parent(), m.global_position + Vector3(0, 0.8, 0), FIRE if kind == "phoenix" else color.lightened(0.3), 0.5)


## 따라갈 제 자리(스캔 때): 주인(성벽 위면 그 아래 바깥 땅) + 제 방향. 그 자리가 주인과 다른 영역이면 반대쪽, 그래도 다르면 주인 자리.
## 지상 소환수가 제 자리와 다른 영역에 있거나 성 밖에서 성(모서리)을 가로질러야 하면 성문 경로를 짠다(Formation.route).
func _update_goal() -> void:
	if is_instance_valid(owner_hero) and owner_hero.is_inside_tree():
		var anchor: Vector3 = owner_hero.global_position
		if castle != null and Formation.region(castle.half, anchor) == Formation.REGION_WALL:
			anchor = _below_wall(anchor)
		anchor.y = global_position.y
		_goal = anchor + _offset
		if castle != null:
			var in_a := Formation.is_inside(castle.half, anchor)
			if Formation.is_inside(castle.half, _goal) != in_a:
				_goal = anchor - _offset
				if Formation.is_inside(castle.half, _goal) != in_a:
					_goal = anchor
		_goal_ok = true
	if not _goal_ok or _flies or castle == null:
		return
	var here := global_position
	var in_here := Formation.is_inside(castle.half, here)
	if Formation.is_inside(castle.half, _goal) == in_here and (in_here or not Formation.crosses_castle(castle.half, here, _goal)):
		_path.clear()
	elif _path.is_empty() or Formation.flat_distance(_path[_path.size() - 1], _goal) > FOLLOW_SLACK:
		_path = Formation.route(castle.half, global_position, _goal)


func _follow(delta: float) -> void:
	var dest := _goal
	if not _path.is_empty():
		dest = _path[0]
	var to := Vector3(dest.x - global_position.x, 0.0, dest.z - global_position.z)
	var d := to.length()
	if _path.is_empty() and d >= FOLLOW_SLACK:
		_following = true
	if d <= ARRIVE or not (_following or not _path.is_empty()):
		if not _path.is_empty():
			_path.pop_front()
		else:
			_following = false
		return
	var sp := _speed * (1.6 if d > CATCH_UP else 1.0)
	global_position += to / d * minf(sp * delta, d)
	_face(to)
	_moved = true


func _face(dir: Vector3) -> void:
	if dir.length_squared() > 0.0001:
		_yaw = atan2(-dir.x, -dir.z)


# --- 모양·움직임 ---

## 매 프레임 부품 변환만 바꾼다: 등장 크기, 바라보는 방향, 떠 있는 높이·흔들림, 돌진(급강하), 다리·날개·팔.
func _animate(delta: float) -> void:
	_walk = move_toward(_walk, 1.0 if _moved else 0.0, delta * 6.0)
	var walk := _walk
	_phase += delta * (11.0 if walk > 0.5 else 4.0) * (1.4 if kind == "wolf" or kind == "hawk" else 1.0)
	if _lunge < 1.0:
		_lunge = minf(1.0, _lunge + delta / LUNGE_SEC)
	var lunge := sin(PI * _lunge) if _lunge < 1.0 else 0.0
	if kind != "turret":  # 포탑은 받침이 그대로고 머리만 돈다
		_pivot.rotation.y = lerp_angle(_pivot.rotation.y, _yaw, minf(1.0, delta * 12.0))
	var grow := minf(1.0, _age / SPAWN_SEC)
	_pivot.scale = Vector3.ONE * (0.2 + 0.8 * grow * (2.0 - grow))
	var fwd := Vector3(-sin(_pivot.rotation.y), 0.0, -cos(_pivot.rotation.y))
	var bob := absf(sin(_phase)) * 0.06 * walk + sin(_age * 2.2) * 0.015
	var y := _hover + bob
	var reach := 0.35
	if _flies:
		y += sin(_age * 2.6) * 0.12
		if _shot == "":  # 매: 표적으로 급강하
			y -= (_hover - 0.55) * lunge
			reach = 0.7
		else:
			y -= 0.35 * lunge
	_pivot.position = Vector3(0, y, 0) + fwd * (reach * lunge)
	var sw := sin(_phase)
	var chop := _chop(_lunge)
	match kind:
		"wolf":
			_parts[0].rotation.x = -0.06 * lunge
			_parts[1].rotation.x = sw * 0.7 * walk - 0.5 * lunge
			_parts[2].rotation.x = -sw * 0.7 * walk + 0.3 * lunge
		"skeleton":
			_parts[0].rotation.z = sw * 0.05 * walk
			_parts[1].rotation.x = 0.5 + 1.4 * chop - 0.15 * sw * walk  # 칼을 비스듬히 들고 있다가 치켜든 뒤 내리친다
			_parts[2].rotation.z = sw * 0.18 * walk
		"golem":
			_parts[0].rotation.z = sw * 0.06 * walk
			_parts[1].rotation.x = 1.7 * chop + 0.3 * sw * walk
			_parts[2].rotation.x = 1.7 * chop - 0.3 * sw * walk
		"treant":
			_parts[0].rotation.z = sw * 0.07 * walk
			_parts[1].rotation.z = sin(_age * 1.7) * 0.06 + sw * 0.08 * walk
			_parts[2].rotation.x = 1.2 * chop + sin(_age * 1.3) * 0.08
		"spirit":
			_parts[1].rotation.y += delta * 2.5
			_parts[2].scale = Vector3.ONE * (1.0 + 0.12 * sin(_age * 5.0) + 0.4 * lunge)
		"phoenix", "hawk":
			var flap := sin(_age * (9.0 if kind == "hawk" else 7.0)) * 0.55 + 0.1
			if lunge > 0.0 and _shot == "":
				flap = lerpf(flap, -0.9, lunge)  # 급강하: 날개를 접는다
			_parts[1].rotation.z = flap
			_parts[2].rotation.z = -flap
			_parts[0].rotation.x = 0.35 * lunge if _shot == "" else -0.2 * lunge
		"turret":
			_parts[1].rotation.y = lerp_angle(_parts[1].rotation.y, _yaw, minf(1.0, delta * 12.0))
			_parts[1].position = Vector3(0, 0.82, 0) + Vector3(sin(_parts[1].rotation.y), 0.0, cos(_parts[1].rotation.y)) * (0.12 * lunge)
			_pivot.position = Vector3.ZERO


## 내리치기 곡선(근접 팔): 돌진 진행 k(0..1) → 치켜듦 1(k 0.4)까지 올렸다가 타격 순간(HIT_DELAY ≈ k 0.47) 앞 아래(−0.3)로 내리치고 0으로 돌아온다.
static func _chop(k: float) -> float:
	if k >= 1.0:
		return 0.0
	if k < 0.4:
		return sin(k / 0.4 * PI / 2.0)
	if k < 0.55:
		return lerpf(1.0, -0.3, (k - 0.4) / 0.15)
	return lerpf(-0.3, 0.0, (k - 0.55) / 0.45)


## 등장(ring = true: 발밑 주인 색 6각 고리가 퍼지고 연기)·퇴장(연기만) 연출. foot = 발밑, h = 연기 높이. Fx 상한 안에서만.
static func _puff(parent: Node, foot: Vector3, h: float, c: Color, ring: bool) -> void:
	var pos := foot + Vector3(0, h, 0)
	if Fx.full(parent):
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _fx_mesh("puff", c)
	mi.material_override = Fx.material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("fx", "summon_puff" if ring else "summon_poof")
	parent.add_child(mi)
	Fx.track(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.4
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 1.25, 0.18).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mi, "global_position", pos + Vector3(0, 0.35, 0), 0.4)
	tw.tween_property(mi, "scale", Vector3.ONE * 0.05, 0.22).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)
	if not ring or Fx.full(parent):
		return
	var r := MeshInstance3D.new()
	r.mesh = _fx_mesh("ring", c)
	r.material_override = Fx.glow_material()
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.set_meta("fx", "summon_ring")
	parent.add_child(r)
	Fx.track(r)
	r.global_position = foot
	r.scale = Vector3(0.3, 1.0, 0.3)
	var tr := r.create_tween()
	tr.tween_property(r, "scale", Vector3(1.6, 1.0, 1.6), 0.4).set_ease(Tween.EASE_OUT)
	tr.tween_callback(r.queue_free)


static func _fx_mesh(what: String, c: Color) -> Mesh:
	var key := what + c.to_html()
	if not _meshes.has(key):
		var k = MeshKit.new()
		if what == "ring":
			for i in 6:
				var o0 := Vector3(cos(TAU * i / 6.0), 0, sin(TAU * i / 6.0))
				var o1 := Vector3(cos(TAU * (i + 1) / 6.0), 0, sin(TAU * (i + 1) / 6.0))
				k.face([o0 * 0.8 + Vector3(0, 0.05, 0), o0 + Vector3(0, 0.05, 0), o1 + Vector3(0, 0.05, 0), o1 * 0.8 + Vector3(0, 0.05, 0)],
					Vector3.UP, Color(c.lightened(0.3), 0.9))
		else:  # 연기: 둘레에 뭉친 밝은 덩이 6개
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			var smoke := Color(0.92, 0.92, 0.9).lerp(c, 0.25)
			for i in 6:
				var a := TAU * i / 6.0
				k.rock(Vector3(cos(a) * 0.38, 0.15 + 0.12 * (i % 2), sin(a) * 0.38), 0.2, smoke.darkened(0.08 * (i % 3)), rng, 0.9)
			k.rock(Vector3(0, 0.35, 0), 0.24, smoke.lightened(0.2), rng, 0.9)
		_meshes[key] = k.commit()
	return _meshes[key]


## 종류·색의 부품들 [[메시, 관절 위치(피벗 기준), 재질 0/1/2], …](최대 3개). 첫 부품이 몸통. 캐시한다.
static func parts_of(p_kind: String, c: Color) -> Array:
	var key := p_kind + "#" + c.to_html()
	if not _meshes.has(key):
		_meshes[key] = _build(p_kind, c)
	return _meshes[key]


static func _build(p_kind: String, c: Color) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	match p_kind:
		"skeleton":
			return _skeleton(c, rng)
		"golem":
			return _golem(c, rng)
		"treant":
			return _treant(c, rng)
		"spirit":
			return _spirit(c, rng)
		"phoenix":
			return _bird(c, rng, true)
		"hawk":
			return _bird(c, rng, false)
		"turret":
			return _turret(c)
	return _wolf(c)


## 늑대: 몸통(머리·주둥이·귀·꼬리) + 앞다리 쌍 + 뒷다리 쌍(질주하듯 번갈아 휘두른다). 털 = 회색과 주인 색 반반, 눈은 노랑.
static func _wolf(c: Color) -> Array:
	var fur := Color(0.42, 0.42, 0.46).lerp(c, 0.5)
	var dark := fur.darkened(0.35)
	var light := fur.lightened(0.35)
	var k = MeshKit.new()
	k.box(Vector3(0, 0.46, 0.05), Vector3(0.4, 0.34, 0.85), fur)
	k.box(Vector3(0, 0.44, -0.28), Vector3(0.46, 0.46, 0.38), fur.lightened(0.08))  # 가슴(어깨가 높다)
	k.box(Vector3(0, 0.42, -0.22), Vector3(0.3, 0.06, 0.3), light)  # 가슴 흰 털
	k.box(Vector3(0, 0.7, -0.6), Vector3(0.34, 0.3, 0.32), fur)  # 머리
	k.box(Vector3(0, 0.7, -0.88), Vector3(0.18, 0.15, 0.26), light)  # 주둥이
	k.box(Vector3(0, 0.79, -1.0), Vector3(0.08, 0.07, 0.04), Color(0.08, 0.08, 0.08))  # 코
	for sx in [-1.0, 1.0]:
		k.cone(Vector3(sx * 0.1, 1.0, -0.56), 4, 0.075, 0.2, dark, PI / 4.0)  # 귀
		k.box(Vector3(sx * 0.1, 0.87, -0.77), Vector3(0.07, 0.05, 0.02), GOLD)  # 눈
	k.xform = Transform3D(Basis(Vector3.RIGHT, 1.05), Vector3(0, 0.74, 0.44))
	k.box(Vector3.ZERO, Vector3(0.13, 0.42, 0.13), fur)  # 꼬리(뒤 위로)
	k.box(Vector3(0, 0.42, 0), Vector3(0.11, 0.14, 0.11), light)
	var body: Mesh = k.commit()
	return [[body, Vector3.ZERO, 0], [_legs(dark, 0.12, 0.5), Vector3(0, 0.5, -0.28), 0], [_legs(dark, 0.12, 0.5), Vector3(0, 0.5, 0.3), 0]]


## 다리 한 쌍(관절이 원점, 아래로 h m, 좌우 ±x). 발끝은 앞(-Z).
static func _legs(col: Color, x: float, h: float) -> Mesh:
	var k = MeshKit.new()
	for sx in [-1.0, 1.0]:
		k.box(Vector3(sx * x, -h, 0), Vector3(0.11, h, 0.12), col)
		k.box(Vector3(sx * x, -h, -0.04), Vector3(0.13, 0.06, 0.18), col.darkened(0.2))
	return k.commit()


## 해골 병사: 몸통(갈비뼈·두개골·주인 색 눈빛·허리천·둥근 방패) + 칼 든 오른팔(공격 때 내리친다) + 다리(뒤뚱).
static func _skeleton(c: Color, _rng: RandomNumberGenerator) -> Array:
	var bone := Color(0.9, 0.88, 0.8)
	var shade := bone.darkened(0.25)
	var hole := Color(0.12, 0.1, 0.1)
	var k = MeshKit.new()
	k.box(Vector3(0, 0.78, 0), Vector3(0.34, 0.12, 0.18), shade)  # 골반
	k.box(Vector3(0, 0.88, 0.02), Vector3(0.07, 0.42, 0.07), shade)  # 척추
	for i in 3:
		k.box(Vector3(0, 0.98 + i * 0.1, 0), Vector3(0.36 + 0.04 * (i % 2), 0.055, 0.24), bone)  # 갈비뼈
	k.box(Vector3(0, 1.29, 0), Vector3(0.54, 0.07, 0.16), bone)  # 어깨
	k.box(Vector3(0, 1.36, 0), Vector3(0.07, 0.06, 0.07), shade)  # 목
	k.box(Vector3(0, 1.42, -0.01), Vector3(0.32, 0.3, 0.3), bone)  # 두개골
	k.box(Vector3(0, 1.36, -0.04), Vector3(0.24, 0.08, 0.26), shade)  # 턱
	for sx in [-1.0, 1.0]:
		k.box(Vector3(sx * 0.075, 1.5, -0.165), Vector3(0.09, 0.09, 0.02), c.lightened(0.45))  # 눈빛(주인 색)
	k.box(Vector3(0, 1.43, -0.165), Vector3(0.05, 0.05, 0.02), hole)  # 코 구멍
	k.box(Vector3(0, 0.56, -0.1), Vector3(0.26, 0.26, 0.03), c.darkened(0.15))  # 허리천(앞)
	k.box(Vector3(0, 0.78, 0), Vector3(0.38, 0.1, 0.22), c.darkened(0.3))  # 허리띠
	k.box(Vector3(-0.29, 0.9, 0), Vector3(0.07, 0.4, 0.07), bone)  # 왼팔
	k.xform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(-0.36, 1.0, -0.1))  # 방패: 윗면이 앞(-Z)
	k.prism_n(Vector3.ZERO, 8, 0.25, 0.25, 0.05, c, PI / 8.0)
	k.prism_n(Vector3(0, 0.05, 0), 8, 0.08, 0.04, 0.05, Color(0.62, 0.64, 0.68), PI / 8.0)
	var body: Mesh = k.commit()
	var a = MeshKit.new()  # 오른팔 + 칼(관절 = 오른 어깨). 칼끝은 앞(-Z)
	a.box(Vector3(0, -0.42, 0), Vector3(0.07, 0.42, 0.07), bone)
	a.box(Vector3(0, -0.47, -0.08), Vector3(0.06, 0.07, 0.16), Color(0.35, 0.22, 0.12))  # 손잡이
	a.box(Vector3(0, -0.49, -0.17), Vector3(0.24, 0.1, 0.05), GOLD.darkened(0.3))  # 날밑
	a.box(Vector3(0, -0.47, -0.62), Vector3(0.05, 0.08, 0.85), Color(0.74, 0.76, 0.8))  # 칼날
	var arm: Mesh = a.commit()
	var l = MeshKit.new()  # 다리(관절 = 골반)
	for sx in [-1.0, 1.0]:
		l.box(Vector3(sx * 0.1, -0.78, 0), Vector3(0.08, 0.78, 0.08), bone)
		l.box(Vector3(sx * 0.1, -0.42, 0), Vector3(0.11, 0.08, 0.1), shade)  # 무릎
		l.box(Vector3(sx * 0.1, -0.78, -0.05), Vector3(0.12, 0.05, 0.2), shade)
	return [[body, Vector3.ZERO, 0], [arm, Vector3(0.29, 1.3, 0), 0], [l.commit(), Vector3(0, 0.78, 0), 0]]


## 골렘: 큰 바윗덩이 몸통(짧은 다리·낮은 머리·빛나는 눈·주인 색 수정) + 커다란 바위 주먹 두 팔(공격 때 함께 내리친다).
static func _golem(c: Color, rng: RandomNumberGenerator) -> Array:
	var stone := Color(0.52, 0.5, 0.48).lerp(c, 0.22)
	var dark := stone.darkened(0.3)
	var crystal := Color(0.45, 0.85, 1.0).lerp(c, 0.3)
	var k = MeshKit.new()
	for sx in [-1.0, 1.0]:
		k.box(Vector3(sx * 0.34, 0, 0), Vector3(0.4, 0.75, 0.46), dark)  # 다리
	k.rock(Vector3(0, 1.4, 0), 0.78, stone, rng, 0.85)  # 몸통
	k.box(Vector3(0, 1.95, -0.45), Vector3(0.46, 0.38, 0.42), stone.lightened(0.08))  # 머리(어깨 사이 앞)
	k.box(Vector3(0, 2.3, -0.47), Vector3(0.5, 0.08, 0.44), dark)  # 이마
	for sx in [-1.0, 1.0]:
		k.box(Vector3(sx * 0.11, 2.12, -0.675), Vector3(0.11, 0.07, 0.02), Color(1.0, 0.92, 0.45))  # 눈
	k.cone(Vector3(0.38, 1.95, 0.22), 4, 0.14, 0.5, crystal)  # 등 수정(주인 색 섞음)
	k.cone(Vector3(-0.3, 1.95, 0.3), 4, 0.11, 0.36, crystal.darkened(0.15))
	k.cone(Vector3(0.0, 2.0, 0.45), 4, 0.1, 0.3, crystal.lightened(0.15))
	var body: Mesh = k.commit()
	var arms := []
	for sx in [-1.0, 1.0]:
		var a = MeshKit.new()
		a.rock(Vector3(0, -0.25, 0), 0.32, stone.darkened(0.06), rng, 1.0)  # 어깨·윗팔
		a.rock(Vector3(sx * 0.05, -0.85, -0.05), 0.38, stone, rng, 1.0)  # 주먹
		a.box(Vector3(sx * 0.05, -0.62, -0.05), Vector3(0.44, 0.05, 0.44), crystal.darkened(0.1))  # 손목 띠
		arms.append(a.commit())
	return [[body, Vector3.ZERO, 0], [arms[0], Vector3(-0.82, 1.7, 0), 0], [arms[1], Vector3(0.82, 1.7, 0), 0]]


## 나무 정령(트렌트): 줄기 몸통(뿌리 다리·빛나는 눈·입) + 잎 덩이 머리(주인 색 섞음, 흔들린다) + 가지 두 팔(공격 때 휘두른다).
static func _treant(c: Color, rng: RandomNumberGenerator) -> Array:
	var bark := Color(0.45, 0.31, 0.2)
	var dark := bark.darkened(0.3)
	var leaf := Color(0.3, 0.62, 0.25).lerp(c, 0.45)
	var k = MeshKit.new()
	for sx in [-1.0, 1.0]:
		k.prism_n(Vector3(sx * 0.22, 0, 0), 5, 0.22, 0.16, 0.55, dark)  # 뿌리 다리
		k.xform = Transform3D(_aim(Vector3(sx * 0.8, -0.6, -0.3)), Vector3(sx * 0.3, 0.32, -0.12))
		k.box(Vector3.ZERO, Vector3(0.1, 0.42, 0.1), dark)  # 곁뿌리(줄기에서 땅으로)
		k.xform = Transform3D.IDENTITY
	k.prism_n(Vector3(0, 0.45, 0), 6, 0.4, 0.3, 1.4, bark)  # 줄기
	k.prism_n(Vector3(0, 0.45, 0), 6, 0.41, 0.36, 0.25, dark)  # 밑동 테
	for sx in [-1.0, 1.0]:
		k.box(Vector3(sx * 0.13, 1.38, -0.36), Vector3(0.12, 0.08, 0.06), Color(0.85, 1.0, 0.45))  # 눈
	k.box(Vector3(0, 1.12, -0.35), Vector3(0.2, 0.06, 0.05), Color(0.12, 0.08, 0.05))  # 입
	k.box(Vector3(0, 1.6, -0.34), Vector3(0.32, 0.06, 0.05), dark)  # 이마 주름
	var body: Mesh = k.commit()
	var cr = MeshKit.new()  # 잎 머리(관절 = 줄기 꼭대기)
	cr.rock(Vector3(0, 0.38, 0.05), 0.7, leaf, rng, 0.8)
	cr.rock(Vector3(-0.5, 0.18, 0.1), 0.42, leaf.darkened(0.1), rng, 0.85)
	cr.rock(Vector3(0.5, 0.22, 0.0), 0.45, leaf.darkened(0.05), rng, 0.85)
	cr.rock(Vector3(0.05, 0.8, 0.1), 0.42, leaf.lightened(0.12), rng, 0.85)
	var arms = MeshKit.new()  # 가지 두 팔(관절 = 어깨 높이 줄기 가운데)
	for sx in [-1.0, 1.0]:
		var dir := Vector3(sx * 0.85, -0.25, -0.45).normalized()
		var at := Vector3(sx * 0.3, 0, 0)
		arms.xform = Transform3D(_aim(dir), at)
		arms.box(Vector3.ZERO, Vector3(0.14, 0.8, 0.14), bark)
		arms.xform = Transform3D(_aim(Vector3(sx * 0.4, 0.8, -0.2)), at + dir * 0.55)
		arms.box(Vector3.ZERO, Vector3(0.08, 0.35, 0.08), bark.darkened(0.1))  # 잔가지(위로)
		arms.xform = Transform3D.IDENTITY
		arms.rock(at + dir * 0.85, 0.2, leaf, rng, 0.9)  # 손끝 잎
	return [[body, Vector3.ZERO, 0], [cr.commit(), Vector3(0, 1.8, 0), 0], [arms.commit(), Vector3(0, 1.45, 0), 0]]


## 정령: 불꽃 머리가 뾰족한 둥근 몸(검은 눈) + 아래 뒤로 가늘어지는 꼬리, 둘레를 도는 수정 셋, 은은한 반투명 빛 껍질(맥동). 주인 색.
static func _spirit(c: Color, rng: RandomNumberGenerator) -> Array:
	var core := c.lightened(0.15)
	var k = MeshKit.new()  # 불꽃 방울: 아래 둥근 몸(8각 원뿔대 셋) + 위로 뾰족한 불꽃 + 아래 뒤로 꼬리
	k.prism_n(Vector3(0, -0.1, 0), 8, 0.3, 0.27, 0.16, core, PI / 8.0)
	k.prism_n(Vector3(0, 0.06, 0), 8, 0.27, 0.2, 0.12, core.lightened(0.1), PI / 8.0)
	k.cone(Vector3(0, 0.18, 0.02), 8, 0.2, 0.5, c.lightened(0.45), PI / 8.0)  # 불꽃 머리
	k.xform = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, -0.1, 0))
	k.prism_n(Vector3.ZERO, 8, 0.3, 0.16, 0.14, core.darkened(0.05), PI / 8.0)  # 아랫배
	k.xform = Transform3D(_aim(Vector3(0, -1, 0.5)), Vector3(0, -0.22, 0.03))
	k.cone(Vector3.ZERO, 6, 0.15, 0.45, c.darkened(0.08))  # 꼬리(아래 뒤로)
	k.xform = Transform3D.IDENTITY
	for sx in [-1.0, 1.0]:
		k.box(Vector3(sx * 0.1, -0.04, -0.27), Vector3(0.08, 0.13, 0.04), Color(0.08, 0.08, 0.18))  # 눈
		k.box(Vector3(sx * 0.1 - 0.015, 0.04, -0.29), Vector3(0.03, 0.03, 0.02), Color.WHITE)  # 눈빛
	var body: Mesh = k.commit()
	var o = MeshKit.new()  # 도는 수정 셋
	for i in 3:
		var a := TAU * i / 3.0
		var p := Vector3(cos(a) * 0.55, 0.1 * (i - 1), sin(a) * 0.55)
		o.cone(p, 4, 0.07, 0.18, c.lightened(0.6))
		o.xform = Transform3D(Basis(Vector3.RIGHT, PI), p)
		o.cone(Vector3.ZERO, 4, 0.07, 0.14, c.lightened(0.4))
		o.xform = Transform3D.IDENTITY
	var g = MeshKit.new()  # 빛 껍질
	g.rock(Vector3(0, 0.05, 0), 0.55, Color(c.lightened(0.4), 0.3), rng, 1.1)
	return [[body, Vector3.ZERO, 0], [o.commit(), Vector3.ZERO, 0], [g.commit(), Vector3.ZERO, 2]]


## 새(불사조 fire = true / 매): 몸통(머리·부리·꼬리깃, 불사조는 볏과 긴 불꽃 꼬리) + 왼날개 + 오른날개(날갯짓, 급강하 때 접는다).
## 불사조 = 불꽃 주황·금(주인 색 조금), 크다. 매 = 갈색(주인 색 섞음)·흰 머리·노란 부리, 작고 꼬리가 짧다.
static func _bird(c: Color, _rng: RandomNumberGenerator, fire: bool) -> Array:
	var s := 1.0 if fire else 0.72
	var main := Color(1.0, 0.36, 0.1).lerp(c, 0.3) if fire else Color(0.45, 0.31, 0.2).lerp(c, 0.4)
	var head_c := Color(1.0, 0.55, 0.15) if fire else Color(0.95, 0.94, 0.9)
	var beak_c := GOLD if fire else Color(1.0, 0.78, 0.15)
	var tip := GOLD if fire else Color(0.95, 0.94, 0.9)
	var k = MeshKit.new()
	k.xform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0, -0.3 * s))  # 몸통: 앞(-Z)이 굵고 뒤로 가늘다
	k.prism_n(Vector3.ZERO, 6, 0.21 * s, 0.1 * s, 0.75 * s, main)
	k.xform = Transform3D.IDENTITY
	k.box(Vector3(0, 0.02 * s, -0.42 * s), Vector3(0.24 * s, 0.24 * s, 0.24 * s), head_c)  # 머리
	k.xform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0 - (0.35 if not fire else 0.1)), Vector3(0, 0.12 * s, -0.54 * s))
	k.cone(Vector3.ZERO, 4, 0.06 * s, 0.2 * s, beak_c, PI / 4.0)  # 부리(매는 아래로 굽는다)
	k.xform = Transform3D.IDENTITY
	for sx in [-1.0, 1.0]:
		k.box(Vector3(sx * 0.122 * s, 0.13 * s, -0.47 * s), Vector3(0.02, 0.05 * s, 0.06 * s), Color(0.08, 0.06, 0.05))  # 눈
	for i in 3:  # 꼬리깃 부채
		var spread := (i - 1) * (0.35 if fire else 0.3)
		var b := Basis(Vector3.UP, spread) * Basis(Vector3.RIGHT, 1.85 if fire else 1.62)
		k.xform = Transform3D(b, Vector3(0, 0, 0.38 * s))
		var ln := (1.05 if i == 1 else 0.8) if fire else 0.42
		k.box(Vector3.ZERO, Vector3(0.13 * s, ln * s, 0.03), main.darkened(0.1) if fire else main.darkened(0.15))
		k.box(Vector3(0, ln * s * 0.65, 0), Vector3(0.15 * s, ln * s * 0.35, 0.035), tip)  # 깃 끝(불사조 금, 매 흰 띠)
	if fire:
		for i in 3:  # 볏
			k.xform = Transform3D(Basis(Vector3.RIGHT, 0.5 + 0.25 * i), Vector3(0, 0.12 * s, -0.42 * s + 0.06 * i))
			k.cone(Vector3.ZERO, 3, 0.04, 0.3 - 0.05 * i, GOLD if i % 2 == 0 else FIRE)
	k.xform = Transform3D.IDENTITY
	var body: Mesh = k.commit()
	var wings := []
	for sx in [-1.0, 1.0]:
		var w = MeshKit.new()  # 날개(관절 = 어깨, 바깥 ±X로 펼친다)
		var p0 := Vector3(0, 0, -0.16) * s
		var p1 := Vector3(sx * 0.55, 0.06, -0.24) * s
		var p2 := Vector3(sx * 1.15, 0.1, -0.02) * s
		var p3 := Vector3(sx * 0.75, 0.04, 0.24) * s
		var p4 := Vector3(0, 0, 0.18) * s
		w.face([p0, p1, p3, p4], Vector3.UP, main)
		w.face([p1, p2, p3], Vector3.UP, tip if fire else main.darkened(0.2))
		for j in 3:  # 끝깃
			var a := p2.lerp(p3, j / 3.0)
			var b := p2.lerp(p3, (j + 1) / 3.0)
			w.face([a, b, (a + b) / 2.0 + Vector3(sx * 0.12, 0, 0.18) * s], Vector3.UP, FIRE if fire else main.darkened(0.3))
		wings.append(w.commit())
	return [[body, Vector3.ZERO, 0], [wings[0], Vector3(-0.1 * s, 0.06 * s, -0.05 * s), 0], [wings[1], Vector3(0.1 * s, 0.06 * s, -0.05 * s), 0]]


## 포탑(쇠뇌): 다리 셋 받침(주인 색 깃발) + 도는 머리(나무 개머리·쇠 활·화살·주인 색 방패판). 쏠 때 머리가 뒤로 튄다.
static func _turret(c: Color) -> Array:
	var wood := Color(0.55, 0.38, 0.22)
	var metal := Color(0.58, 0.6, 0.65)
	var k = MeshKit.new()
	for i in 3:  # 다리 셋(가운데로 모인다)
		var a := TAU * i / 3.0 + PI / 6.0
		var out := Vector3(cos(a), 0, sin(a))
		k.xform = Transform3D(_aim(Vector3(0, 0.66, 0) - out * 0.29), out * 0.38)
		k.box(Vector3.ZERO, Vector3(0.1, 0.72, 0.1), wood.darkened(0.15))
		k.xform = Transform3D.IDENTITY
		k.box(out * 0.4, Vector3(0.16, 0.06, 0.16), metal.darkened(0.2))  # 발
	k.prism_n(Vector3(0, 0.45, 0), 6, 0.14, 0.12, 0.32, wood)  # 기둥
	k.prism_n(Vector3(0, 0.74, 0), 6, 0.2, 0.2, 0.06, metal)  # 회전판
	k.box(Vector3(0.22, 0.3, 0.12), Vector3(0.03, 1.1, 0.03), wood.darkened(0.3))  # 깃대
	k.face([Vector3(0.22, 1.38, 0.12), Vector3(0.22, 1.1, 0.12), Vector3(0.22, 1.24, 0.5)], Vector3.RIGHT, c)  # 깃발(주인 색)
	var base: Mesh = k.commit()
	var h = MeshKit.new()  # 머리(관절 = 회전판 위). 앞 = -Z
	h.box(Vector3(0, 0, 0.05), Vector3(0.16, 0.14, 0.9), wood)  # 개머리
	h.box(Vector3(0, -0.02, 0.38), Vector3(0.3, 0.2, 0.18), wood.darkened(0.15))  # 손잡이 상자
	for sx in [-1.0, 1.0]:  # 활 팔: 앞에서 좌우 뒤로 젖힌다
		h.xform = Transform3D(_aim(Vector3(sx, 0, 0.35)), Vector3(sx * 0.05, 0.08, -0.32))
		h.box(Vector3.ZERO, Vector3(0.07, 0.7, 0.07), metal)
		h.xform = Transform3D.IDENTITY
	h.box(Vector3(0, 0.14, -0.15), Vector3(0.045, 0.045, 0.7), Color(0.4, 0.28, 0.16))  # 화살대
	h.xform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0, 0.162, -0.5))
	h.cone(Vector3.ZERO, 4, 0.06, 0.14, metal.lightened(0.2), PI / 4.0)  # 화살촉
	h.xform = Transform3D.IDENTITY
	h.box(Vector3(0, -0.12, -0.22), Vector3(0.5, 0.3, 0.05), c)  # 방패판(주인 색)
	h.box(Vector3(0, -0.12, -0.235), Vector3(0.18, 0.3, 0.03), c.darkened(0.3))
	return [[base, Vector3.ZERO, 0], [h.commit(), Vector3(0, 0.82, 0), 0]]


## +Y를 dir 쪽으로 돌리는 회전(부품을 비스듬히 놓을 때 k.xform에).
static func _aim(dir: Vector3) -> Basis:
	var d := dir.normalized()
	var axis := Vector3.UP.cross(d)
	if axis.length() < 0.0001:
		return Basis.IDENTITY if d.y > 0.0 else Basis(Vector3.RIGHT, PI)
	return Basis(axis.normalized(), Vector3.UP.angle_to(d))

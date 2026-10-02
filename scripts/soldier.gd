extends Node3D
## 병사(개정 13 §7, 개정 21). 병종·티어(능력치 = GameData.soldier_stats)와 역할 자리(면 side · 그 면 병종 칸 slot, SoldierCommand.assign_posts)로 만든다.
## 스테이지 동안만 있다(개정 21 §1): main이 스테이지 시작에 성채 정문 앞 광장 자리(spawn, Formation.soldier_spots)에서 RISE_SEC 동안 솟아오르게
## 만들고(먼지 고리), 곧바로 역할 자리로 간다(Formation.soldier_entry_route). 연속 진행 클리어의 리필은 reset(되살아나 자리로 순간 이동),
## 방치로 돌아가면 vanish(VANISH_SEC 동안 작아지며 사라짐).
## 역할(§2): 궁병 = 성벽 위 병사 자리(사거리 안 적을 쏘고 떠나지 않는다), 보병 = 성문 앞 줄(자리에서 aggro 안·같은 영역 적, HOLD_RADIUS 밖으로는
## 쫓지 않는다. 성문이 부서지면 안쪽 막는 줄), 기병 = 순찰 고리에서 맡은 두 성문 사이를 오가며 aggro 안 성 밖 적에게 돌진(성 안에 들어가지 않는다.
## 맡은 성문이 부서지면 그 성문 앞). 지원(SoldierCommand)은 order(면)로 받는다: 그 면 성문 앞 지원 칸에서 보병처럼 지키고, order(-1)이면 원래 자리로.
## 대상이 죽으면 같은 프레임에 다시 찾고(휘두르는 중인 사거리 안 대상은 놓지 않는다), 없으면 RETURN_DELAY초 머문 뒤 자리로(영웅과 같다). 공격은 개정 12-2 타격 동기화(근접 = 모션 타격 순간,
## 궁병 = 그 순간 화살 → 도착 순간 피해). 방치 모드는 무적. hp_bars 인터페이스: is_alive·hp_ratio·bar_height·bar_scale·tier.
# ponytail: 병사 하나 = KayKit 스켈레톤 하나(+ 기병은 말 메시). 상한 64명 + 몬스터 120 + 영웅 12면 모바일 웹은 스켈레톤 수가 한계다 —
# 화면 밖은 OFFSCREEN_EVERY 프레임마다만 애니메이션을 돌린다. 더 필요하면 화면 밖 병사 처리 자체를 건너뛰거나 병종·티어별 대표만 그린다.

const Balance := preload("res://scripts/balance.gd")
const GameData := preload("res://scripts/game_data.gd")
const Art := preload("res://scripts/art.gd")
const Formation := preload("res://scripts/formation.gd")
const SoldierBody := preload("res://scripts/soldier_body.gd")
const SoldierCommand := preload("res://scripts/soldier_command.gd")
const Fx := preload("res://scripts/fx.gd")
const DamageNumbers := preload("res://scripts/damage_numbers.gd")
const ProjectileScript := preload("res://scripts/projectile.gd")
const Crowd := preload("res://scripts/crowd.gd")

const SCAN_INTERVAL := 0.2
const ARRIVE_EPS := 0.05
const SWING_SLACK := 0.6  # 근접 타격 순간 대상이 사거리 + 이만큼 안이면 맞는다(영웅과 같다)
const MUZZLE := Vector3(0, 1.33 * Art.SOLDIER_SCALE, 0)  # 화살이 나가는 높이(모델 1.33 m × 병사 크기)
const ARROW_SPEED := 30.0
const OFFSCREEN_EVERY := 4  # 화면 밖이면 애니메이션을 이 프레임마다 한 번(쌓인 시간만큼)
const RIDER_Y := SoldierBody.RIDER_Y  # 기사 모델 높이(말 등 − 엉덩이) × 병사 크기
const BOB := 0.06  # 말이 걸을 때 위아래 흔들림(m)
const BOB_HZ := 2.5
const HOLD_RADIUS := 6.0  # 자리를 지키는 병사는 자리에서 이만큼 밖으로 쫓지 않는다
const RETURN_DELAY := 1.5  # 교전이 끝나고 이만큼 제자리에 머문 뒤 자리로 돌아간다(영웅과 같다)
const RISE_SEC := 0.4
const RISE_DEPTH := 1.6
const VANISH_SEC := 0.3

var type := ""
var tier := 1
var side := 0  # 원래 면(역할 자리)
var slot := 0  # 원래 면에서 그 병종의 몇 번째
var spawn := Vector3.ZERO  # 등장 자리(광장)
var castle
var stats := {}  # GameData.soldier_stats
var hp := 0.0
var hp_max := 0.0
var atk := 0.0
var reinforce := -1  # 지원 가 있는 면(-1 = 원래 자리)
var rslot := 0  # 지원 면의 성문 앞 칸
var last_order := -INF  # 마지막 배정·복귀 시각(SoldierCommand 시계 — 흔들림 방지)

var _dead := false
var _ranged := false
var _model
var _horse: MeshInstance3D
var _disc: MeshInstance3D
var _target
var _atk_cd := 0.0
var _scan_cd := 0.0
var _swing  # 휘두르는(쏘려는) 공격의 고정 대상. null = 없음
var _swing_left := 0.0
var _walking := false
var _bob_t := 0.0
var _frame := 0
var _anim_acc := 0.0
var _path: Array[Vector3] = []
var _rise := 0.0  # 솟아오르는 남은 초
var _linger := 0.0  # 교전 뒤 제자리에 더 머물 초
var _patrol: Array[Vector3] = []  # 기병 순찰 점 셋(맡은 성문 앞 · 모서리 · 옆 성문 앞)
var _pi := 0
var _pdir := 1
var _bonus := {}  # 성장 효과(Economy.upgrade_bonus) — 치명타 굴림이 쓴다


## add_child 전에 호출.
func setup(p_type: String, p_tier: int, p_side: int, p_slot: int, p_spawn: Vector3, p_castle) -> void:
	type = p_type
	tier = p_tier
	side = p_side
	slot = p_slot
	spawn = p_spawn
	castle = p_castle
	refresh_stats()
	Economy.upgrades_changed.connect(refresh_stats)  # 성장은 곧바로(개정 20)
	_ranged = Art.SOLDIERS[type].role == "ranged"
	if type == "cavalry":  # 같은 면 기병은 번갈아 시계·반시계 방향 — 네 면 사이가 다 덮인다
		_patrol = Formation.patrol_points(castle.half, side, 1 if slot % 2 == 0 else -1)


## 능력치를 다시 읽는 한 곳(개정 20): 병종·티어(GameData.soldier_stats) × 성장 — HP·공격 × (1 + %), stats의 공격 간격 ÷ (1 + 공격속도),
## 이동 × (1 + 이동속도). HP 비율 유지, 다음 공격부터 새 간격.
func refresh_stats() -> void:
	_bonus = Economy.upgrade_bonus()
	var b := _bonus
	var ratio := hp_ratio() if hp_max > 0.0 else 1.0
	stats = GameData.soldier_stats(type, tier)
	stats.atk_interval /= 1.0 + b.aspd_pct
	stats.speed *= 1.0 + b.mspd_pct
	hp_max = stats.hp * (1.0 + b.hp_pct)
	atk = stats.atk * (1.0 + b.atk_pct)
	hp = hp_max * ratio


func _ready() -> void:
	add_to_group("soldiers")
	add_to_group("crowd")  # 겹침 해소(crowd.gd)
	var art: Dictionary = Art.SOLDIERS[type]
	var body := SoldierBody.build(self, type, true)  # 모델 + 기병이면 말(병사 피규어도 같은 것으로 만든다)
	_model = body[0]
	_horse = body[1]
	_disc = Fx.soldier_disc(art.color, 0.75 if _horse != null else 0.42)
	_disc.position.y = 0.02
	add_child(_disc)
	_frame = get_instance_id() % OFFSCREEN_EVERY  # 병사마다 다른 프레임에 갱신(한 프레임에 몰리지 않게)
	GameState.gate_broken.connect(_on_gate_broken)
	_seat(0.0)
	_face(Formation.SIDE_DIR[side])
	global_position = spawn - Vector3(0, RISE_DEPTH, 0)
	_rise = RISE_SEC
	Fx.dust(get_parent(), spawn)


## 연속 진행 클리어의 리필: 되살아나 HP를 채우고 지원을 풀고 스테이지 시작 자리(역할 자리, 기병은 순찰 첫 점)에 선다.
func reset() -> void:
	_dead = false
	hp = hp_max
	reinforce = -1
	last_order = -INF
	_target = null
	_swing = null
	_atk_cd = 0.0
	_linger = 0.0
	_rise = 0.0
	_path.clear()
	_pi = 0
	_pdir = 1
	global_position = post()
	_model.reset_pose()
	_walking = false
	_seat(0.0)
	_face(Formation.SIDE_DIR[side])
	_disc.visible = true
	if _horse != null:
		_horse.visible = true


## 지원 명령(SoldierCommand): s = 지원 갈 면(-1 = 원래 자리로), rs = 그 면 성문 앞 칸, now = 지휘관 시계. 경로를 다시 계산한다.
func order(s: int, rs: int, now: float) -> void:
	reinforce = s
	rslot = rs
	last_order = now
	_replan()


## 지금 지키는 면.
func side_now() -> int:
	return reinforce if reinforce >= 0 else side


## 순찰 중인가(기병, 지원 아님, 맡은 두 성문이 멀쩡함).
func patrolling() -> bool:
	return not _patrol.is_empty() and reinforce < 0 and _broken_patrol_gate() < 0


## 지금 서야 할 자리. 순찰 중 기병은 다음 순찰 점.
func post() -> Vector3:
	var half: float = castle.half
	if reinforce >= 0:
		return Formation.gate_row_spot(half, reinforce, rslot, type != "cavalry" and GameState.is_gate_broken(reinforce))
	match type:
		"archer":
			return Formation.soldier_wall_spot(half, side, slot)
		"cavalry":
			var b := _broken_patrol_gate()
			return Formation.gate_row_spot(half, b, slot) if b >= 0 else _patrol[_pi]
	return Formation.gate_row_spot(half, side, slot, GameState.is_gate_broken(side))


## 싸우는 중(살아 있는 대상이 있다) — 지휘관은 싸우는 기병을 보내지 않는다.
func engaged() -> bool:
	return _target != null and is_instance_valid(_target) and _target.is_alive()


func power() -> float:
	return SoldierCommand.power(hp, atk, float(stats.atk_interval))


## 받는 피해(몬스터가 타격 순간에 부른다). 방치 모드는 무적(개정 12 §3과 같이 0, 숫자 없음).
func take_damage(amount: float, _source = null) -> void:
	if _dead or GameState.mode == GameState.Mode.IDLE:
		return
	hp = maxf(0.0, hp - amount)
	DamageNumbers.pop(self, amount, DamageNumbers.Kind.HURT)
	if hp == 0.0:
		_dead = true
		_swing = null
		_model.play_death()
		_disc.visible = false
		if _horse != null:
			_horse.visible = false
			_model.position.y = 0.0  # 말에서 떨어져 바닥에 눕는다


func is_alive() -> bool:
	return not _dead


## 실제 높이로 판정한다 — 계단을 오르내리는 중에는 지상 취급(몬스터 표적 규칙).
func is_on_wall() -> bool:
	return global_position.y > Balance.WALL_H / 2.0


func hp_ratio() -> float:
	return hp / hp_max if hp_max > 0.0 else 0.0


## 겹침 해소(crowd.gd): 몸 반지름(기병은 말), 밀리는 무게(걷는 중이 아니면 무겁다).
func radius() -> float:
	return Crowd.CAVALRY_R if type == "cavalry" else Crowd.HUMAN_R * Art.CHARACTER_SCALE * Art.SOLDIER_SCALE


func push_mass() -> float:
	return Crowd.mass(radius(), not _walking)


func bar_height() -> float:
	return Art.HEAD_HEIGHT * Art.CHARACTER_SCALE * Art.SOLDIER_SCALE + (RIDER_Y if _horse != null else 0.0)


func bar_scale() -> float:
	return 0.8


## 스테이지가 끝나 방치로(main.clear_soldiers): 표적·바·지휘에서 곧바로 빠지고 VANISH_SEC 동안 작아져 사라진다.
func vanish() -> void:
	_dead = true
	remove_from_group("soldiers")
	set_process(false)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 0.01, VANISH_SEC)
	tw.tween_callback(queue_free)


func _process(delta: float) -> void:
	_animate(delta)
	if _dead or GameState.mode == GameState.Mode.COUNTDOWN:  # 연속 진행 카운트다운: 리필로 돌아온 자리에 서 있는다
		return
	if _rise > 0.0:  # 등장: 아래에서 솟아오른 뒤 역할 자리로
		_rise = maxf(0.0, _rise - delta)
		global_position.y = -RISE_DEPTH * _rise / RISE_SEC
		if _rise == 0.0:
			_path = Formation.soldier_entry_route(castle.half, spawn, post())
		return
	_atk_cd -= delta
	_tick_swing(delta)
	if not _path.is_empty():
		_walk_path(delta)
		return
	_scan_cd -= delta
	if _scan_cd <= 0.0 or (_target != null and not engaged()):  # 대상이 죽으면 같은 프레임에 다시 찾는다
		_scan_cd = SCAN_INTERVAL
		if not _swinging_at(_target):  # 휘두르는 중인 사거리 안 대상은 스캔이 놓치지 않는다(영웅과 같다)
			_target = _find_target()
	if engaged():
		_linger = RETURN_DELAY
		if _fight(delta):
			return
	_target = null
	if _linger > 0.0:  # 싸운 자리에서 잠깐 머문다
		_linger -= delta
		_set_walking(false)
		return
	_go_home(delta)


## 대상과 싸운다. 사거리 안이면 공격, 밖이면 근접은 다가간다(성벽·성 경계를 넘지 않고, 자리를 지키는 병사는 HOLD_RADIUS 안에서만).
## 대상을 놓아야 하면 false.
func _fight(delta: float) -> bool:
	var tpos: Vector3 = _target.global_position
	_face(tpos - global_position)
	if Formation.flat_distance(global_position, tpos) <= float(stats.range):
		_set_walking(false)
		if _atk_cd <= 0.0:
			_attack()
		return true
	if _ranged:
		return false  # 궁병은 자리를 떠나지 않는다
	var next := global_position.move_toward(Vector3(tpos.x, 0.0, tpos.z), float(stats.speed) * delta)
	if Formation.is_inside(castle.half, next) != Formation.is_inside(castle.half, global_position):
		return false
	if not patrolling() and Formation.flat_distance(next, post()) > HOLD_RADIUS:
		_set_walking(false)  # 줄 끝에서 기다린다
		return true
	_set_walking(true)
	global_position = next
	return true


## 표적(가장 가까운 것): 궁병 = 지금 위치에서 사거리 안(영역 무관). 순찰 기병 = 지금 위치에서 aggro 안 성 밖 몬스터.
## 자리를 지키는 병사 = 자리에서 aggro 안·자리와 같은 영역. 성 밖에서 곧장 가면 성을 가로지르는 몬스터는 잡지 않는다.
func _find_target():
	var half: float = castle.half
	var roam := patrolling()
	var origin := global_position if _ranged or roam else post()
	var reach: float = float(stats.range) if _ranged else float(stats.aggro)
	var inside := false if roam else Formation.is_inside(half, origin)
	var best = null
	var best_d := INF
	for m in get_tree().get_nodes_in_group("monsters"):
		if not m.is_alive() or Formation.flat_distance(origin, m.global_position) > reach:
			continue
		if not _ranged:
			if Formation.is_inside(half, m.global_position) != inside:
				continue
			if not inside and Formation.crosses_castle(half, global_position, m.global_position):
				continue
		var d := Formation.flat_distance(global_position, m.global_position)
		if d < best_d:
			best_d = d
			best = m
	return best


## 대상이 없을 때: 순찰 기병은 순찰 점을 오가고(성을 가로지르면 고리로 돌아서), 나머지는 자리로(곧장 못 가면 경로로).
func _go_home(delta: float) -> void:
	var half: float = castle.half
	if patrolling():
		var p: Vector3 = _patrol[_pi]
		if Formation.flat_distance(global_position, p) <= Crowd.PASS_R:  # 옆 면 기병과 같은 점을 쓴다 — 가까이 오면 돈다
			if _pi + _pdir < 0 or _pi + _pdir >= _patrol.size():
				_pdir = -_pdir
			_pi += _pdir
			return
		if Formation.crosses_castle(half, global_position, p):
			_path = Formation.ring_route(half, global_position, p)
			return
		_step_to(p, delta)
		return
	var home := post()
	if global_position.distance_to(home) > ARRIVE_EPS:
		if not is_on_wall() and Formation.route(half, global_position, home).size() == 1:
			_step_to(home, delta)
		else:
			_replan()
		return
	if _walking:
		_set_walking(false)
		_face(Formation.SIDE_DIR[side_now()])


func _step_to(p: Vector3, delta: float) -> void:
	_face(p - global_position)
	_set_walking(true)
	global_position = global_position.move_toward(p, float(stats.speed) * delta)


## 경로 따라 걷기(이동 중엔 적을 무시 — 영웅과 같다).
func _walk_path(delta: float) -> void:
	var wp: Vector3 = _path[0]
	_target = null
	_swing = null
	_step_to(wp, delta)
	if global_position.distance_to(wp) <= Crowd.arrive_r(_path, ARRIVE_EPS):
		_path.pop_front()


## 목적지가 바뀌었다: 경로를 다시 계산한다(등장 중이면 등장이 끝날 때 계산한다).
func _replan() -> void:
	_target = null
	_swing = null
	_linger = 0.0
	if _rise <= 0.0 and is_inside_tree():
		_path = SoldierCommand.travel(castle.half, type, global_position, post())


## 맡은 순찰 성문 중 부서진 것(없으면 -1).
func _broken_patrol_gate() -> int:
	for p in [_patrol[0], _patrol[2]]:
		var s := Formation.side_of(p)
		if GameState.is_gate_broken(s):
			return s
	return -1


## 성문이 부서졌다: 그 면을 지키는 보병(안쪽 막는 줄로)·그 성문을 맡은 기병(그 성문 앞으로)은 경로를 다시 계산한다.
func _on_gate_broken(s: int) -> void:
	if _dead or _ranged:
		return
	if (type != "cavalry" and side_now() == s) or (reinforce < 0 and not _patrol.is_empty() and _broken_patrol_gate() == s):
		_replan()


## m을 휘두르는(쏘려는) 중이고 m이 살아서 사거리 안인가.
func _swinging_at(m) -> bool:
	return m != null and _swing == m and is_instance_valid(m) and m.is_alive() \
		and Formation.flat_distance(global_position, m.global_position) <= float(stats.range)


## 공격 시작(개정 12-2 §3): 대상을 고정하고 모션을 재생한다(간격에 맞춰 빨라질 수 있다). 피해는 타격 순간(_release)에.
func _attack() -> void:
	_atk_cd = float(stats.atk_interval)
	_swing = _target
	_swing_left = _model.play_attack(_atk_cd)


func _tick_swing(delta: float) -> void:
	if _swing == null:
		return
	_swing_left -= delta
	if _swing_left <= 0.0:
		_release()


## 타격(발사) 순간. 고정한 대상이 그새 죽었으면 아무 일도 없다. 근접: 사거리 + SWING_SLACK 안이면 친다(아니면 헛스윙).
## 원거리: 화살(30 m/s, 대상을 따라감) — 피해는 도착 순간.
func _release() -> void:
	var m = _swing
	_swing = null
	if not is_instance_valid(m) or not m.is_alive():
		return
	if not _ranged:
		if Formation.flat_distance(global_position, m.global_position) <= float(stats.range) + SWING_SLACK:
			_hit(m)
		return
	var p = ProjectileScript.new()
	p.target = m
	p.speed = ARROW_SPEED
	p.color = Art.SOLDIERS[type].color
	p.on_hit = _hit
	get_parent().add_child(p)
	p.global_position = global_position + MUZZLE


## 한 번 맞히기(근접 타격 순간·화살 도착). 성장 기본 치명타(개정 20 §3: 확률 crit_rate, 배율 150% + crit_dmg)를 한 번 굴린다.
## 확률 0이면 굴리지 않는다(난수열이 그대로 — E2E 재현).
func _hit(m) -> void:
	var cp := GameData.crit_roll_params(0.0, 0.0, _bonus)
	var crit: bool = cp.rate > 0.0 and randf() < cp.rate
	m.take_damage(atk * (float(cp.mult) if crit else 1.0), DamageNumbers.Kind.CRIT if crit else DamageNumbers.Kind.HIT)


func _set_walking(on: bool) -> void:
	if on == _walking:
		return
	_walking = on
	if on:
		_model.play_walk()
	else:
		_model.play_idle()


func _face(dir: Vector3) -> void:
	_model.face(dir)
	if _horse != null:
		_horse.rotation.y = _model.rotation.y


## 말 탄 기사·말 높이(흔들림 y). 말은 SOLDIER_SCALE로 줄였다.
func _seat(y: float) -> void:
	if _horse != null:
		_horse.position.y = y
		_model.position.y = RIDER_Y + y


## 애니메이션: 화면 안이면 매 프레임, 밖이면 OFFSCREEN_EVERY 프레임마다 쌓인 시간만큼(타격 시점은 _swing_left라 그대로). 말은 걸을 때 흔들린다.
func _animate(delta: float) -> void:
	_frame += 1
	_anim_acc += delta
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.is_position_in_frustum(global_position) or _frame % OFFSCREEN_EVERY == 0:
		_model.advance(_anim_acc)
		_anim_acc = 0.0
	if _horse != null and not _dead:
		_bob_t = _bob_t + delta if _walking else 0.0
		_seat(absf(sin(_bob_t * PI * BOB_HZ)) * BOB)

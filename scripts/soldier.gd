extends Node3D
## 병사(개정 13 §7). 병종·티어(능력치 = GameData.soldier_stats)와 자리(home: 성채 정문 앞 광장 격자, Formation.soldier_spots)로 만든다.
## 방치 모드: 제자리에 서 있고 싸우지 않으며 피해를 받지 않는다(방치는 영웅만 방어). 그 밖의 모드: 성 안(Formation.is_inside)에 들어온
## 몬스터가 자리에서 인식 범위(궁병은 사거리) 안이면 맞서 싸운다(최후 방어선) — 근접은 쫓아가 치고, 궁병은 제자리에서 쏜다.
## 대상이 없으면 자리로 돌아간다. 공격은 개정 12-2 타격 동기화: 모션의 타격 순간(UnitModel.play_attack) 근접 피해, 원거리는 그 순간
## 투사체(projectile.gd)가 나가 도착 순간 피해. 죽으면 GameState.refilled 때 되살아나 제자리로(영구히 죽지 않는다).
## 몬스터도 성 안에서는 병사를 노린다(monster._find_hero). hp_bars 인터페이스: is_alive·hp_ratio·bar_height·bar_scale·tier.
# ponytail: 병사 하나 = KayKit 스켈레톤 하나(+ 기병은 말 메시). 상한 66명 + 몬스터 120 + 영웅 12면 모바일 웹은 스켈레톤 수가 한계다 —
# 화면 밖은 OFFSCREEN_EVERY 프레임마다만 애니메이션을 돌린다. 더 필요하면 화면 밖 병사 처리 자체를 건너뛰거나 병종·티어별 대표만 그린다.

const GameData := preload("res://scripts/game_data.gd")
const Art := preload("res://scripts/art.gd")
const Formation := preload("res://scripts/formation.gd")
const TownKit := preload("res://scripts/town_kit.gd")
const UnitModelScript := preload("res://scripts/unit_model.gd")
const Fx := preload("res://scripts/fx.gd")
const DamageNumbers := preload("res://scripts/damage_numbers.gd")
const ProjectileScript := preload("res://scripts/projectile.gd")

const SCAN_INTERVAL := 0.2
const ARRIVE_EPS := 0.05
const SWING_SLACK := 0.6  # 근접 타격 순간 대상이 사거리 + 이만큼 안이면 맞는다(영웅과 같다)
const MUZZLE := Vector3(0, 1.0, 0)  # 화살이 나가는 높이(병사 크기 0.75)
const ARROW_SPEED := 30.0
const OFFSCREEN_EVERY := 4  # 화면 밖이면 애니메이션을 이 프레임마다 한 번(쌓인 시간만큼)
const RIDER_Y := 0.5  # 기사 모델 높이 = 말 등(TownKit.HORSE_BACK × 0.75 ≈ 0.86) − 기사 엉덩이(KayKit 다리 뿌리 0.41~0.52 × 0.75 ≈ 0.36)
const BOB := 0.06  # 말이 걸을 때 위아래 흔들림(m)
const BOB_HZ := 2.5
const FACE := Vector3(0, 0, 1)  # 서 있을 때 보는 쪽: 남(+Z) 성문

static var _horse_mesh: ArrayMesh  # 말 메시는 하나를 같이 쓴다

var type := ""
var tier := 1
var home := Vector3.ZERO
var castle
var stats := {}  # GameData.soldier_stats
var hp := 0.0
var hp_max := 0.0
var atk := 0.0

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


## add_child 전에 호출.
func setup(p_type: String, p_tier: int, p_home: Vector3, p_castle) -> void:
	type = p_type
	tier = p_tier
	home = p_home
	castle = p_castle
	stats = GameData.soldier_stats(type, tier)
	hp_max = stats.hp
	atk = stats.atk
	_ranged = Art.SOLDIERS[type].role == "ranged"


func _ready() -> void:
	add_to_group("soldiers")
	var art: Dictionary = Art.SOLDIERS[type]
	_model = UnitModelScript.new()
	_model.manual = true
	_model.setup(Art.soldier_spec(type, GameData.soldier(type).model), Art.SOLDIER_SCALE)
	add_child(_model)
	if art.get("horse", false):
		if _horse_mesh == null:
			_horse_mesh = TownKit.horse()
		_horse = MeshInstance3D.new()
		_horse.mesh = _horse_mesh
		_horse.material_override = Art.lowpoly_vc_material()
		_horse.scale = Vector3.ONE * Art.SOLDIER_SCALE  # 말 길이 ≈ 1.65 m — 기병은 두 줄 건너 선다(Formation.soldier_spots)
		add_child(_horse)
	_disc = Fx.soldier_disc(art.color, 0.75 if _horse != null else 0.42)
	_disc.position.y = 0.02
	add_child(_disc)
	_frame = get_instance_id() % OFFSCREEN_EVERY  # 병사마다 다른 프레임에 갱신(한 프레임에 몰리지 않게)
	GameState.refilled.connect(reset)
	reset()


## 리필: 되살아나 HP를 채우고 제자리에 선다.
func reset() -> void:
	_dead = false
	hp = hp_max
	_target = null
	_swing = null
	_atk_cd = 0.0
	global_position = home
	_model.reset_pose()
	_walking = false
	_seat(0.0)
	_face(FACE)
	_disc.visible = true
	if _horse != null:
		_horse.visible = true


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


func is_on_wall() -> bool:
	return false


func hp_ratio() -> float:
	return hp / hp_max if hp_max > 0.0 else 0.0


func bar_height() -> float:
	return Art.HEAD_HEIGHT * Art.CHARACTER_SCALE * Art.SOLDIER_SCALE + (RIDER_Y if _horse != null else 0.0)


func bar_scale() -> float:
	return 0.8


## 배치에서 빠짐(main._sync_soldiers): 표적·바에서 빠지고 프레임 끝에 사라진다. 리필 중이어도 되살아나지 않게 연결을 끊는다.
func retire() -> void:
	_dead = true
	if GameState.refilled.is_connected(reset):
		GameState.refilled.disconnect(reset)
	remove_from_group("soldiers")
	queue_free()


func _process(delta: float) -> void:
	_animate(delta)
	if _dead:
		return
	if GameState.mode == GameState.Mode.IDLE:  # 방치: 제자리, 싸우지 않음
		_swing = null
		_target = null
		global_position = home
		if _walking:
			_set_walking(false)
			_face(FACE)
		return
	_atk_cd -= delta
	_tick_swing(delta)
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = SCAN_INTERVAL
		_target = _find_target()
	if _target != null and is_instance_valid(_target) and _target.is_alive():
		var tpos: Vector3 = _target.global_position
		_face(tpos - global_position)
		if Formation.flat_distance(global_position, tpos) <= float(stats.range):
			_set_walking(false)
			if _atk_cd <= 0.0:
				_atk_cd = float(stats.atk_interval)
				_swing = _target
				_swing_left = _model.play_attack(_atk_cd)
			return
		if _ranged:
			return  # 궁병은 제자리에서 다음 스캔을 기다린다
		var next := global_position.move_toward(Vector3(tpos.x, 0.0, tpos.z), float(stats.speed) * delta)
		if Formation.is_inside(castle.half, next):  # 성 밖으로는 쫓지 않는다
			_set_walking(true)
			global_position = next
			return
	_target = null
	if global_position.distance_to(home) > ARRIVE_EPS:
		_face(home - global_position)
		_set_walking(true)
		global_position = global_position.move_toward(home, float(stats.speed) * delta)
		return
	if _walking:
		_set_walking(false)
		_face(FACE)


## 표적: 성 안의 살아 있는 몬스터 중 자리에서 인식 범위(궁병은 사거리) 안, 지금 위치에서 가장 가까운 것.
func _find_target():
	var reach: float = float(stats.range) if _ranged else float(stats.aggro)
	var best = null
	var best_d := INF
	for m in get_tree().get_nodes_in_group("monsters"):
		if not m.is_alive() or not Formation.is_inside(castle.half, m.global_position) or Formation.flat_distance(home, m.global_position) > reach:
			continue
		var d := Formation.flat_distance(global_position, m.global_position)
		if d < best_d:
			best_d = d
			best = m
	return best


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
			m.take_damage(atk, DamageNumbers.Kind.HIT)
		return
	var p = ProjectileScript.new()
	p.target = m
	p.speed = ARROW_SPEED
	p.color = Art.SOLDIERS[type].color
	p.on_hit = _hit
	get_parent().add_child(p)
	p.global_position = global_position + MUZZLE


func _hit(m) -> void:
	m.take_damage(atk, DamageNumbers.Kind.HIT)


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

extends Node3D
## 괴물(근접). 자기 위치에서 aggro 안·같은 영역(성 안/밖)의 지상 영웅·병사를 쫓아가 치고, 없으면 진로(_advance)로 돌아가 성문·성채를 친다.
## 성벽 위 영웅은 표적으로 삼지 않는다.
## 영웅 스킬 상태: slow(이동 −%), stun(이동·공격 정지), poison(초당 피해) — 이펙트(Fx)는 지속 동안 남는다(개정 17). 영웅을 칠 때 자신을 출처로 넘긴다(thorns 반사 대상).
## 공격은 시작(_swing) 때 대상을 고정하고, 피해는 모션의 타격 순간(_release, 개정 12-2 §3)에 들어간다.
## 개정 18 아레나(던전): setup_arena(던전 적 행) — castle 없음. 거리 제한 없이 가장 가까운 영웅을 쫓고, 없으면 제자리. 자리는 쓰는 쪽이 정한다.

const Balance := preload("res://scripts/balance.gd")
const GameData := preload("res://scripts/game_data.gd")
const Art := preload("res://scripts/art.gd")
const Formation := preload("res://scripts/formation.gd")
const UnitModelScript := preload("res://scripts/unit_model.gd")
const Fx := preload("res://scripts/fx.gd")
const DamageNumbers := preload("res://scripts/damage_numbers.gd")

const SCAN_INTERVAL := 0.2
const SWING_SLACK := 0.6  # 타격 순간 대상(영웅·성문·성 지점)이 사거리 + 이만큼 안이면 맞는다(밖이면 헛스윙)
const AT_HERO := -2  # _swing_side: 영웅을 친다(-1 = 성, 0..3 = 성문 면)

signal died(monster)

var castle
var kind: String = "grunt"
var side: int = 0
var stage: int = 1
var hp: float = 0.0
var hp_max: float = 0.0
var atk: float = 0.0

var _stats: Dictionary = {}
var _speed := 0.0  # 기본 이동속도 × 스테이지 배율(개정 22 §3, setup)
var _model
var _target_hero
var _atk_cd := 0.0
var _scan_cd := 0.0
var _dead := false
var _slow_pct := 0.0
var _slow_t := 0.0
var _stun_t := 0.0
var _poison_dps := 0.0
var _poison_t := 0.0
var _status := {}  # 상태 이펙트 노드 "stun"·"slow"·"poison"(개정 17: 지속 동안 남는다, 상한이면 null) — 상태가 끝나거나 죽으면 지운다
var _swing_left := -1.0  # 타격 순간까지 남은 초(음수 = 휘두르는 중 아님)
var _swing_hero           # 치려는 영웅(_swing_side == AT_HERO일 때)
var _swing_side := -1     # 치려는 것: AT_HERO, 성(-1), 성문 면(0..3)
var _swing_at := Vector3.ZERO  # 성문·성을 칠 때 그 지점


## add_child 전에 호출. p_stage = 전체 라운드 g. hp_mult = 추가 HP 배율(라운드 25 보스 boss_round_mult).
func setup(p_kind: String, p_side: int, p_stage: int, p_castle, hp_mult := 1.0) -> void:
	assert(not GameData.monster(p_kind).is_empty(), "unknown monster kind: " + p_kind)
	kind = p_kind
	side = p_side
	stage = p_stage
	castle = p_castle
	_stats = GameData.monster(kind)
	var st := GameData.stage(stage)
	hp = _stats.hp * st.hp_mult * hp_mult
	hp_max = hp
	atk = _stats.atk * st.atk_mult
	_speed = float(_stats.speed) * GameData.enemy_speed_mult(stage)


## 아레나(개정 18): row = 던전 적 한 행(Economy.dungeon_enemies — kind·hp·atk·speed·range·atk_interval·aggro·scale). add_child 전에.
func setup_arena(row: Dictionary) -> void:
	kind = row.kind
	_stats = row
	hp = float(row.hp)
	hp_max = hp
	atk = float(row.atk)
	_speed = float(row.speed)  # 던전은 스테이지 속도 배율 없음


func _ready() -> void:
	add_to_group("monsters")
	_model = UnitModelScript.new()
	_model.setup(Art.MONSTER_MODELS[kind], float(_stats.scale))
	add_child(_model)
	if castle != null:
		global_position = castle.spawn_position(side)
		GameState.refilled.connect(_vanish)


func is_alive() -> bool:
	return not _dead


func take_damage(amount: float, kind := 0) -> void:  # kind = DamageNumbers.Kind(표시 색)
	if _dead:
		return
	hp = maxf(0.0, hp - amount)
	DamageNumbers.pop(self, amount, kind)
	if hp == 0.0:
		_dead = true
		remove_from_group("monsters")  # 즉시 표적 대상에서 빠진다
		for n in _status.values():  # 상태 이펙트는 시체에 남기지 않는다
			if is_instance_valid(n):
				n.queue_free()
		_status.clear()
		died.emit(self)
		_model.play_death()
		get_tree().create_timer(Art.CORPSE_SEC).timeout.connect(queue_free)


func _process(delta: float) -> void:
	if _dead:
		return
	_slow_t -= delta
	_stun_t -= delta
	if _poison_t > 0.0:
		var dt := minf(delta, _poison_t)  # 마지막 틱은 남은 시간만큼만 — 합계가 dps × 초를 넘지 않는다
		_poison_t -= delta
		take_damage(_poison_dps * dt, DamageNumbers.Kind.POISON)
		if _dead:
			return
	if not _status.is_empty():
		_end_status()
	if _stun_t > 0.0:
		_swing_left = -1.0  # 기절은 휘두르던 공격도 끊는다
		_model.play_idle()
		return
	_atk_cd -= delta
	_tick_swing(delta)
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = SCAN_INTERVAL
		_target_hero = _find_hero()
	if is_instance_valid(_target_hero) and _target_hero.is_alive() and not _target_hero.is_on_wall():  # 배치에서 빠진 영웅은 해제된다
		var hpos: Vector3 = _target_hero.global_position
		_model.face(hpos - global_position)
		if Formation.flat_distance(global_position, hpos) > _stats.range:
			var next := global_position.move_toward(Vector3(hpos.x, 0.0, hpos.z), speed() * delta)
			if castle != null and Formation.is_inside(castle.half, next) != Formation.is_inside(castle.half, global_position):
				_target_hero = null  # 성 안팎 경계(성벽·모서리)를 넘는 걸음은 딛지 않고 진로로 간다
				_advance(delta)
				return
			_model.play_walk()
			global_position = next
		elif _atk_cd <= 0.0:
			_swing(_target_hero, AT_HERO, Vector3.ZERO)
		return
	_target_hero = null
	_advance(delta)


## 진로: 성 밖이면 지금 가장 가까운 면의 성문으로(끌려간 뒤 재조준). 멀쩡하면 성문을 치고,
## 부서졌으면 성문 축에 맞춘 뒤 안쪽 지점을 거쳐 들어간다(성벽을 뚫지 않게). 성 안이면 성채를 친다.
func _advance(delta: float) -> void:
	if castle == null:  # 아레나: 영웅이 없으면 제자리
		_model.play_idle()
		return
	var half: float = castle.half
	var inside := Formation.is_inside(half, global_position)
	if not inside:
		side = Formation.side_of(global_position)
	var dest: Vector3
	var strikes := true
	if inside:
		dest = castle.keep_target(side)
	elif GameState.is_gate_broken(side):
		strikes = false
		var aligned := absf(Formation.perp(side).dot(global_position)) < Balance.GATE_W / 2.0 - 0.5
		dest = Formation.gate_inner(half, side) if aligned else castle.gate_target(side)
	else:
		dest = castle.gate_target(side)
	_model.face(dest - global_position)
	var stop: float = _stats.range if strikes else 0.1
	if Formation.flat_distance(global_position, dest) > stop:
		_model.play_walk()
		global_position = global_position.move_toward(dest, speed() * delta)
	elif strikes and _atk_cd <= 0.0:
		_swing(null, -1 if inside else side, dest)


## 공격 시작(개정 12-2 §3): 대상(what = AT_HERO면 영웅 hero, 성(-1)·성문 면(0..3)이면 그 지점 at)을 고정하고 모션을 재생한다. 피해는 타격 순간(_release)에.
func _swing(hero, what: int, at: Vector3) -> void:
	_atk_cd = _stats.atk_interval
	_swing_hero = hero
	_swing_side = what
	_swing_at = at
	_swing_left = _model.play_attack(float(_stats.atk_interval))


func _tick_swing(delta: float) -> void:
	if _swing_left < 0.0:
		return
	_swing_left -= delta
	if _swing_left <= 0.0:
		_swing_left = -1.0
		_release()


## 타격 순간: 대상이 사거리 + SWING_SLACK 안이면(영웅은 살아 있고 지상일 때만) 피해, 아니면 헛스윙.
## 방치 무적 등 피해 판정은 받는 쪽(영웅 take_damage·GameState damage_*)이 이 순간에 한다.
func _release() -> void:
	var reach: float = float(_stats.range) + SWING_SLACK
	var h = _swing_hero
	_swing_hero = null
	if _swing_side == AT_HERO:
		if is_instance_valid(h) and h.is_alive() and not h.is_on_wall() and Formation.flat_distance(global_position, h.global_position) <= reach:
			h.take_damage(atk, self)
	elif Formation.flat_distance(global_position, _swing_at) <= reach:
		if _swing_side < 0:
			GameState.damage_castle(atk)
		else:
			GameState.damage_gate(_swing_side, atk)


## 지금 이동 속도(스테이지 배율·slow 반영).
func speed() -> float:
	return _speed * (1.0 - _slow_pct / 100.0) if _slow_t > 0.0 else _speed


## slow: 이동 속도 −pct%, sec초(갱신). 발밑 결정은 끝날 때까지.
func apply_slow(pct: float, sec: float) -> void:
	if not _status.has("slow"):
		_status.slow = Fx.slow(self)
	_slow_pct = clampf(pct, 0.0, 100.0)
	_slow_t = sec


## stun: sec초 이동·공격 정지(남은 시간보다 길 때만 늘린다). 머리 위 별은 끝날 때까지.
func apply_stun(sec: float) -> void:
	_stun_t = maxf(_stun_t, sec)
	if not _status.has("stun"):
		_status.stun = Fx.stun(self, bar_height() + 0.3)


## poison: sec초 동안 초당 dps 피해(갱신). 발밑 거품은 끝날 때까지.
func apply_poison(dps: float, sec: float) -> void:
	if not _status.has("poison"):
		_status.poison = Fx.poison(self)
	_poison_dps = dps
	_poison_t = sec


## 끝난 상태(남은 시간 ≤ 0)의 이펙트를 지운다.
func _end_status() -> void:
	for k in _status.keys():
		var left: float = _stun_t if k == "stun" else (_slow_t if k == "slow" else _poison_t)
		if left <= 0.0:
			if is_instance_valid(_status[k]):
				_status[k].queue_free()
			_status.erase(k)


## 상태 이펙트 노드(테스트용): 없으면 null.
func status_fx(k: String):
	var n = _status.get(k)
	return n if is_instance_valid(n) else null


func is_stunned() -> bool:
	return _stun_t > 0.0


## 표적: 자기 위치에서 aggro 안, 같은 영역의 살아 있는 지상 영웅·병사 중 가장 가까운 것(개정 21: 성문 앞 보병·기병, 성 안 병사). 성벽 위 궁병은 못 친다.
func _find_hero():
	var here_inside := castle != null and Formation.is_inside(castle.half, global_position)
	var best = null
	var best_d: float = float(_stats.aggro) if castle != null else INF  # 아레나는 거리 제한 없음
	for group in ["heroes", "soldiers"]:
		for h in get_tree().get_nodes_in_group(group):
			if not h.is_alive() or h.is_on_wall():
				continue
			if castle != null and Formation.is_inside(castle.half, h.global_position) != here_inside:
				continue
			var d := Formation.flat_distance(global_position, h.global_position)
			if d <= best_d:
				best_d = d
				best = h
	return best


func hp_ratio() -> float:
	return hp / hp_max if hp_max > 0.0 else 0.0


func bar_height() -> float:
	return Art.HEAD_HEIGHT * Art.CHARACTER_SCALE * float(_stats.scale)


func bar_scale() -> float:
	return float(_stats.scale)


## 리필로 제거될 때. died를 내지 않으므로 Spawner는 refilled에서 카운트를 0으로 맞춘다.
func _vanish() -> void:
	_dead = true
	queue_free()

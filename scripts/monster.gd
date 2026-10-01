extends Node3D
## 괴물(근접). 자기 위치에서 aggro 안·같은 영역(성 안/밖)의 지상 영웅을 쫓아가 치고, 없으면 진로(_advance)로 돌아가 성문·성채를 친다.
## 성벽 위 영웅은 표적으로 삼지 않는다.
## 영웅 스킬 상태: slow(이동 −%), stun(이동·공격 정지), poison(초당 피해). 영웅을 칠 때 자신을 출처로 넘긴다(thorns 반사 대상).

const Balance := preload("res://scripts/balance.gd")
const GameData := preload("res://scripts/game_data.gd")
const Art := preload("res://scripts/art.gd")
const Formation := preload("res://scripts/formation.gd")
const UnitModelScript := preload("res://scripts/unit_model.gd")
const Fx := preload("res://scripts/fx.gd")

const SCAN_INTERVAL := 0.2

signal died(monster)

var castle
var kind: String = "grunt"
var side: int = 0
var stage: int = 1
var hp: float = 0.0
var hp_max: float = 0.0
var atk: float = 0.0

var _stats: Dictionary = {}
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


## add_child 전에 호출.
func setup(p_kind: String, p_side: int, p_stage: int, p_castle) -> void:
	assert(not GameData.monster(p_kind).is_empty(), "unknown monster kind: " + p_kind)
	kind = p_kind
	side = p_side
	stage = p_stage
	castle = p_castle
	_stats = GameData.monster(kind)
	var st := GameData.stage(stage)
	hp = _stats.hp * st.hp_mult
	hp_max = hp
	atk = _stats.atk * st.atk_mult


func _ready() -> void:
	add_to_group("monsters")
	_model = UnitModelScript.new()
	_model.setup(Art.MONSTER_MODELS[kind], float(_stats.scale))
	add_child(_model)
	global_position = castle.spawn_position(side)
	GameState.refilled.connect(_vanish)


func is_alive() -> bool:
	return not _dead


func take_damage(amount: float) -> void:
	if _dead:
		return
	hp = maxf(0.0, hp - amount)
	if hp == 0.0:
		_dead = true
		remove_from_group("monsters")  # 즉시 표적 대상에서 빠진다
		died.emit(self)
		_model.play_death()
		get_tree().create_timer(Art.CORPSE_SEC).timeout.connect(queue_free)


func _process(delta: float) -> void:
	if _dead:
		return
	_slow_t -= delta
	_stun_t -= delta
	if _poison_t > 0.0:
		_poison_t -= delta
		take_damage(_poison_dps * delta)
		if _dead:
			return
	if _stun_t > 0.0:
		_model.play_idle()
		return
	_atk_cd -= delta
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = SCAN_INTERVAL
		_target_hero = _find_hero()
	if _target_hero != null and _target_hero.is_alive() and not _target_hero.is_on_wall():
		var hpos: Vector3 = _target_hero.global_position
		_model.face(hpos - global_position)
		if Formation.flat_distance(global_position, hpos) > _stats.range:
			var next := global_position.move_toward(Vector3(hpos.x, 0.0, hpos.z), speed() * delta)
			if Formation.is_inside(castle.half, next) != Formation.is_inside(castle.half, global_position):
				_target_hero = null  # 성 안팎 경계(성벽·모서리)를 넘는 걸음은 딛지 않고 진로로 간다
				_advance(delta)
				return
			_model.play_walk()
			global_position = next
		elif _atk_cd <= 0.0:
			_atk_cd = _stats.atk_interval
			_model.play_attack()
			_target_hero.take_damage(atk, self)
		return
	_target_hero = null
	_advance(delta)


## 진로: 성 밖이면 지금 가장 가까운 면의 성문으로(끌려간 뒤 재조준). 멀쩡하면 성문을 치고,
## 부서졌으면 성문 축에 맞춘 뒤 안쪽 지점을 거쳐 들어간다(성벽을 뚫지 않게). 성 안이면 성채를 친다.
func _advance(delta: float) -> void:
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
		_atk_cd = _stats.atk_interval
		_model.play_attack()
		if inside:
			GameState.damage_castle(atk)
		else:
			GameState.damage_gate(side, atk)


## 지금 이동 속도(slow 반영).
func speed() -> float:
	return float(_stats.speed) * (1.0 - _slow_pct / 100.0) if _slow_t > 0.0 else float(_stats.speed)


## slow: 이동 속도 −pct%, sec초(갱신).
func apply_slow(pct: float, sec: float) -> void:
	if _slow_t <= 0.0:
		Fx.slow(self)
	_slow_pct = clampf(pct, 0.0, 100.0)
	_slow_t = sec


## stun: sec초 이동·공격 정지(남은 시간보다 길 때만 늘린다).
func apply_stun(sec: float) -> void:
	_stun_t = maxf(_stun_t, sec)
	Fx.stun(self, bar_height() + 0.3)


## poison: sec초 동안 초당 dps 피해(갱신).
func apply_poison(dps: float, sec: float) -> void:
	if _poison_t <= 0.0:
		Fx.poison(self, bar_height())
	_poison_dps = dps
	_poison_t = sec


func is_stunned() -> bool:
	return _stun_t > 0.0


## 표적: 자기 위치에서 aggro 안, 같은 영역의 살아 있는 지상 영웅 중 가장 가까운 것.
func _find_hero():
	var here_inside := Formation.is_inside(castle.half, global_position)
	var best = null
	var best_d: float = float(_stats.aggro)
	for h in get_tree().get_nodes_in_group("heroes"):
		if not h.is_alive() or h.is_on_wall():
			continue
		if Formation.is_inside(castle.half, h.global_position) != here_inside:
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

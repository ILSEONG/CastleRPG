extends Node3D
## 괴물(근접). 수평 사거리 안 지상 영웅 우선 공격, 없으면 자기 면 성문 앞으로 직진해 성문 공격.
## 성문이 부서졌으면 성채 앞으로 가서 성 HP 공격. 성벽 위 영웅은 표적으로 삼지 않는다.

const Balance := preload("res://scripts/balance.gd")
const Art := preload("res://scripts/art.gd")
const Formation := preload("res://scripts/formation.gd")
const UnitModelScript := preload("res://scripts/unit_model.gd")

const SCAN_INTERVAL := 0.2

signal died(monster)

var castle
var kind: String = "grunt"
var side: int = 0
var stage: int = 1
var hp: float = 0.0
var atk: float = 0.0

var _stats: Dictionary = {}
var _model
var _target_hero
var _atk_cd := 0.0
var _scan_cd := 0.0
var _dead := false


## add_child 전에 호출.
func setup(p_kind: String, p_side: int, p_stage: int, p_castle) -> void:
	assert(Balance.MONSTER.has(p_kind), "unknown monster kind: " + p_kind)
	kind = p_kind
	side = p_side
	stage = p_stage
	castle = p_castle
	_stats = Balance.MONSTER[kind]
	hp = _stats.hp * Balance.hp_scale(stage)
	atk = _stats.atk * Balance.atk_scale(stage)


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
	_atk_cd -= delta
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = SCAN_INTERVAL
		_target_hero = _nearest_hero()
	if _target_hero != null and _target_hero.is_alive() and not _target_hero.is_on_wall():
		_model.face(_target_hero.global_position - global_position)
		if _atk_cd <= 0.0:
			_atk_cd = _stats.atk_interval
			_model.play_attack()
			_target_hero.take_damage(atk)
		return
	_target_hero = null
	var broken: bool = GameState.is_gate_broken(side)
	var dest: Vector3 = castle.keep_target(side) if broken else castle.gate_target(side)
	_model.face(dest - global_position)
	if Formation.flat_distance(global_position, dest) > _stats.range:
		_model.play_walk()
		global_position = global_position.move_toward(dest, _stats.speed * delta)
	elif _atk_cd <= 0.0:
		_atk_cd = _stats.atk_interval
		_model.play_attack()
		if broken:
			GameState.damage_castle(atk)
		else:
			GameState.damage_gate(side, atk)


func _nearest_hero():
	var best = null
	var best_d: float = _stats.range
	for h in get_tree().get_nodes_in_group("heroes"):
		if not h.is_alive() or h.is_on_wall():
			continue
		var d := Formation.flat_distance(global_position, h.global_position)
		if d <= best_d:
			best_d = d
			best = h
	return best


## 리필로 제거될 때. died를 내지 않으므로 Spawner는 refilled에서 카운트를 0으로 맞춘다.
func _vanish() -> void:
	_dead = true
	queue_free()

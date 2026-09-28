extends Node3D
## 괴물. 사거리 내 영웅 우선 공격, 없으면 목표 성문으로 직진. 성문이 부서졌으면 성채로 진입해 성 HP 공격.

const Balance := preload("res://scripts/balance.gd")
const Flat := preload("res://scripts/flat.gd")

const SCAN_INTERVAL := 0.2

signal died(monster)

var castle
var kind: String = "grunt"
var side: int = 0
var stage: int = 1
var hp: float = 0.0
var atk: float = 0.0

var _stats: Dictionary = {}
var _body: MeshInstance3D
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
	var s: float = _stats.scale
	_body = Flat.capsule(0.4 * s, 1.2 * s, _stats.color)
	add_child(_body)
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
		died.emit(self)
		queue_free()


func _process(delta: float) -> void:
	if _dead:
		return
	_atk_cd -= delta
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = SCAN_INTERVAL
		_target_hero = _nearest_hero()
	if _target_hero != null and _target_hero.is_alive():
		if _atk_cd <= 0.0:
			_atk_cd = _stats.atk_interval
			_target_hero.take_damage(atk)
		return
	_target_hero = null
	var broken: bool = GameState.is_gate_broken(side)
	var dest: Vector3 = castle.keep_position() if broken else castle.gate_target(side)
	if global_position.distance_to(dest) > _stats.range:
		global_position = global_position.move_toward(dest, _stats.speed * delta)
	elif _atk_cd <= 0.0:
		_atk_cd = _stats.atk_interval
		if broken:
			GameState.damage_castle(atk)
		else:
			GameState.damage_gate(side, atk)


func _nearest_hero():
	var best = null
	var best_d: float = _stats.range
	for h in get_tree().get_nodes_in_group("heroes"):
		if not h.is_alive():
			continue
		var d: float = global_position.distance_to(h.global_position)
		if d <= best_d:
			best_d = d
			best = h
	return best


## 리필로 제거될 때. died를 내지 않으므로 Spawner는 refilled에서 카운트를 0으로 맞춘다.
func _vanish() -> void:
	_dead = true
	queue_free()

extends Node
## 게임 모드·스테이지·성/성문 HP의 단일 진실. 오토로드 GameState.
## 씬 의존 없음. 테스트에서 .new()로 단독 생성 가능.

const Balance := preload("res://scripts/balance.gd")

enum Mode { IDLE, STAGE, COUNTDOWN, RESULT }

signal mode_changed(mode: int)
signal stage_cleared(stage: int)
signal stage_failed(stage: int)
signal castle_hp_changed(hp: float, hp_max: float)
signal gate_hp_changed(side: int, hp: float, hp_max: float)
signal gate_broken(side: int)
signal refilled

var mode: int = Mode.IDLE
var stage: int = 1
var keep_level: int = 1
var gate_level: int = 1
var castle_hp_max: float = Balance.CASTLE_HP
var castle_hp: float = Balance.CASTLE_HP
var gate_hp_max: float = Balance.gate_hp_max(1)
var gate_hp: Array[float] = []
var stop_requested := false

var _timer := 0.0
var _won := false


func _init() -> void:
	refill()


func _process(delta: float) -> void:
	advance(delta)


func hero_count() -> int:
	return Balance.hero_slots(keep_level)


func start_stage() -> void:
	if mode != Mode.IDLE:
		push_warning("start_stage ignored in mode %d" % mode)
		return
	stop_requested = false
	refill()
	_set_mode(Mode.STAGE)


func stop_after_stage() -> void:
	stop_requested = not stop_requested


func damage_castle(amount: float) -> void:
	if castle_hp <= 0.0:
		return
	castle_hp = maxf(0.0, castle_hp - amount)
	castle_hp_changed.emit(castle_hp, castle_hp_max)
	if castle_hp == 0.0:
		_on_castle_destroyed()


func damage_gate(side: int, amount: float) -> void:
	if gate_hp[side] <= 0.0:
		return
	gate_hp[side] = maxf(0.0, gate_hp[side] - amount)
	gate_hp_changed.emit(side, gate_hp[side], gate_hp_max)
	if gate_hp[side] == 0.0:
		gate_broken.emit(side)


func is_gate_broken(side: int) -> bool:
	return gate_hp[side] <= 0.0


func on_all_monsters_dead() -> void:
	if mode != Mode.STAGE:
		return
	_won = true
	stage_cleared.emit(stage)
	stage += 1
	_set_mode(Mode.RESULT)


## 영웅·성문·성 HP 전부 초기화. 영웅/몬스터 노드는 refilled를 받아 스스로 리셋/제거.
func refill() -> void:
	castle_hp = castle_hp_max
	gate_hp_max = Balance.gate_hp_max(gate_level)
	gate_hp.resize(4)
	gate_hp.fill(gate_hp_max)
	castle_hp_changed.emit(castle_hp, castle_hp_max)
	for side in 4:
		gate_hp_changed.emit(side, gate_hp_max, gate_hp_max)
	refilled.emit()


func advance(delta: float) -> void:
	match mode:
		Mode.RESULT:
			_timer -= delta
			if _timer <= 0.0:
				refill()
				if _won and not stop_requested:
					_set_mode(Mode.COUNTDOWN)
				else:
					_set_mode(Mode.IDLE)
		Mode.COUNTDOWN:
			_timer -= delta
			if _timer <= 0.0:
				_set_mode(Mode.STAGE)


func countdown_left() -> float:
	return maxf(0.0, _timer)


func _on_castle_destroyed() -> void:
	if mode == Mode.STAGE:
		_won = false
		stage_failed.emit(stage)
		_set_mode(Mode.RESULT)
	else:
		refill()


func _set_mode(new_mode: int) -> void:
	mode = new_mode
	match mode:
		Mode.RESULT:
			_timer = Balance.RESULT_SEC
		Mode.COUNTDOWN:
			_timer = Balance.COUNTDOWN_SEC
	mode_changed.emit(mode)

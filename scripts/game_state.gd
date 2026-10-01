extends Node
## 게임 모드·스테이지·성/성문 HP의 단일 진실. 오토로드 GameState.
## 씬 의존 없음. 테스트에서 .new()로 단독 생성 가능.

const GameData := preload("res://scripts/game_data.gd")

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
var castle_hp_max := 0.0  # refill()이 표에서 읽는다
var castle_hp := 0.0
var gate_hp_max := 0.0
var gate_hp: Array[float] = []
var stop_requested := false

var _timer := 0.0
var _won := false


func _init() -> void:
	refill()


func _process(delta: float) -> void:
	advance(delta)


func hero_count() -> int:
	return GameData.hero_slots(keep_level)


# --- 영웅 보유·배치 공급자 (경계) ---
# roster = Economy(보유 copies·배치: 오프라인 저장 또는 서버 player.heroes/deploy). main이 넣는다 — 이 스크립트는
# run_tests(-s, 오토로드 없음)가 preload해서 오토로드 이름을 쓸 수 없다. null이면(로직 테스트) starter_heroes 기본 배치·copies 1.
var roster = null

## 배치 슬롯 i → 영웅 id 또는 null. 길이 = hero_count().
func deploy() -> Array:
	if roster == null:
		return GameData.default_deploy(hero_count())
	return roster.deploy_slots(hero_count())


## 영웅 id의 보유 수(별 계산용).
func hero_copies(hero_id: String) -> int:
	if roster == null:
		return 1
	return maxi(1, int(roster.heroes.get(hero_id, 1)))


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


## 성문 회복(최대치 상한). 부서진 성문은 회복하지 않는다. 실제로 오른 양을 돌려준다.
func repair_gate(side: int, amount: float) -> float:
	if gate_hp[side] <= 0.0 or amount <= 0.0:
		return 0.0
	var before := gate_hp[side]
	gate_hp[side] = minf(gate_hp_max, before + amount)
	if gate_hp[side] > before:
		gate_hp_changed.emit(side, gate_hp[side], gate_hp_max)
	return gate_hp[side] - before


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
	castle_hp_max = GameData.config_num("castle_hp")  # 표가 바뀌었을 수 있어 매번 읽는다
	castle_hp = castle_hp_max
	gate_hp_max = GameData.gate_hp_max(gate_level)
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
			_timer = GameData.config_num("result_sec")
		Mode.COUNTDOWN:
			_timer = GameData.config_num("countdown_sec")
	mode_changed.emit(mode)

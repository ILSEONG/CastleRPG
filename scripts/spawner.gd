extends Node
## WaveDirector 스케줄을 시간에 맞춰 소비해 몬스터를 부모 노드 아래에 생성. 전멸 감지.

const GameData := preload("res://scripts/game_data.gd")
const WaveDirector := preload("res://scripts/wave_director.gd")
const MonsterScript := preload("res://scripts/monster.gd")

var castle

var _events: Array = []
var _cursor := 0
var _clock := 0.0
var _live := 0
var _stage_mode := false


func _ready() -> void:
	GameState.mode_changed.connect(_on_mode_changed)
	GameState.refilled.connect(_on_refilled)
	_on_mode_changed(GameState.mode)


func _process(delta: float) -> void:
	if _events.is_empty():
		return
	_clock += delta
	while _cursor < _events.size() and _events[_cursor].time <= _clock:
		if _live >= GameData.config_num("max_live_monsters"):
			return  # 상한. 스케줄은 지연되고 다음 프레임에 재시도
		_spawn(_events[_cursor])
		_cursor += 1
	if _cursor < _events.size():
		return
	if _stage_mode:
		if _live == 0:
			_events = []
			GameState.on_all_monsters_dead()
	else:
		_load(WaveDirector.build(GameState.stage, WaveDirector.MODE_IDLE), false)


func _on_refilled() -> void:
	_live = 0


func _on_mode_changed(mode: int) -> void:
	if mode == GameState.Mode.IDLE:
		_load(WaveDirector.build(GameState.stage, WaveDirector.MODE_IDLE), false)
	elif mode == GameState.Mode.STAGE:
		_load(WaveDirector.build(GameState.stage, WaveDirector.MODE_STAGE), true)
	else:
		_events = []


func _load(events: Array, stage_mode: bool) -> void:
	_events = events
	_cursor = 0
	_clock = 0.0
	_stage_mode = stage_mode


func _spawn(ev: Dictionary) -> void:
	var m = MonsterScript.new()
	m.setup(ev.kind, ev.side, GameState.stage, castle)
	m.died.connect(_on_monster_died)
	get_parent().add_child(m)
	_live += 1


func _on_monster_died(m) -> void:
	_live = maxi(0, _live - 1)
	Economy.add_gold(GameData.kill_gold(m.kind, m.stage))  # 리필 제거(_vanish)는 died를 안 내므로 골드 없음

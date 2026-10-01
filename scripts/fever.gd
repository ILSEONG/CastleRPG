extends Node
## FEVER 상태(개정 14 §3). 오토로드 Fever. 방치 처치로 게이지(0~fever_kills)를 채우고, 가득 차면 start()로 fever_sec 동안 방치 스폰 배율.
## 앱 로컬 저장(user://local.json). 씬 의존 없음 — 테스트는 .new()로 단독 생성해 save_path를 ""로 둔다.

const GameData := preload("res://scripts/game_data.gd")
const SAVE_EVERY := 5.0

var gauge := 0
var left := 0.0  # 남은 FEVER 초(0이면 꺼짐)
var save_path := "user://local.json"  # ""이면 저장하지 않는다

var _dirty := false
var _save_cd := SAVE_EVERY


func _ready() -> void:
	load_save()


func _process(delta: float) -> void:
	advance(delta)
	if _dirty:
		_save_cd -= delta
		if _save_cd <= 0.0:
			save()


func kills_needed() -> int:
	return maxi(1, int(GameData.config_num("fever_kills")))


func active() -> bool:
	return left > 0.0


func full() -> bool:
	return gauge >= kills_needed()


## 0..1 (버튼 채움 비율)
func ratio() -> float:
	return clampf(float(gauge) / kills_needed(), 0.0, 1.0)


## 방치 스폰 속도 배율(FEVER 중 fever_spawn_mult, 아니면 1).
func mult() -> float:
	return maxf(1.0, GameData.config_num("fever_spawn_mult")) if active() else 1.0


## 처치 한 번. 방치 모드 처치만 세고 FEVER 중엔 차지 않는다.
func add_kill(idle: bool) -> void:
	if not idle or active() or full():
		return
	gauge += 1
	_dirty = true


## 가득 찼고 꺼져 있을 때만 시작. 게이지는 0으로 돌아가 FEVER 뒤에 다시 찬다.
func start() -> bool:
	if not full() or active():
		return false
	left = GameData.config_num("fever_sec")
	gauge = 0
	save()
	return true


func advance(delta: float) -> void:
	if left > 0.0:
		left = maxf(0.0, left - delta)
		_dirty = true


func reset() -> void:
	gauge = 0
	left = 0.0
	_dirty = false


func save() -> void:
	_dirty = false
	_save_cd = SAVE_EVERY
	if save_path == "":
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_warning("fever save failed: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify({"gauge": gauge, "left": left}))
	f.close()


## 없거나 깨진 파일은 0으로 시작한다.
func load_save() -> void:
	reset()
	if save_path == "" or not FileAccess.file_exists(save_path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(save_path)) != OK or not (json.data is Dictionary):
		return
	var g = json.data.get("gauge")
	var l = json.data.get("left")
	if (g is float or g is int) and (l is float or l is int):
		gauge = clampi(int(g), 0, kills_needed())
		left = clampf(float(l), 0.0, GameData.config_num("fever_sec"))

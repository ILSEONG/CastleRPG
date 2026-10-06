extends Node
## 등장 비용 측정(통과/실패 없음): 실제 스테이지를 두 라운드 넘게 돌리며 모델 만들기(Art.instance)에 쓴 시간과
## 33 ms 넘은 프레임 수를 센다. -- --nocache면 PackedScene을 붙잡지 않는 예전 동작.
## 실행: godot --headless --path . res://tests/perf_spawn.tscn [-- --nocache]

const Art := preload("res://scripts/art.gd")

var _main


func _ready() -> void:
	Engine.max_fps = 0
	Art.cache_scenes = not OS.get_cmdline_user_args().has("--nocache")
	Economy.save_path = ""
	Fever.save_path = ""
	Fever.reset()
	Economy.reset(Time.get_unix_time_from_system())
	Economy.soldiers = {"infantry:1": 16, "archer:1": 8, "cavalry:1": 8}
	Economy.set_soldier_deploy(Economy.soldiers.duplicate())
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(30)
	var boot := Art.instance_usec
	GameState.stage = 10
	GameState.start_stage()
	Art.instance_usec = 0
	var slow := 0
	var worst := 0.0
	var rounds := 0
	GameState.refilled.connect(func(): rounds += 1)
	var t := Time.get_ticks_usec()
	for f in 3000:
		var t1 := Time.get_ticks_usec()
		await get_tree().process_frame
		var ms := (Time.get_ticks_usec() - t1) / 1000.0
		worst = maxf(worst, ms)
		slow += 1 if ms > 33.0 else 0
	print("SPAWN cache=%s boot %.0f ms, battle: instance %.0f ms over %.1f s game, refills %d, frames>33ms %d, worst %.0f ms" % [
		Art.cache_scenes, boot / 1000.0, Art.instance_usec / 1000.0, (Time.get_ticks_usec() - t) / 1e6, rounds, slow, worst])
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

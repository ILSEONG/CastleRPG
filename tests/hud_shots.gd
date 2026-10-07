extends Node
## 성 화면 HUD(개발용, 2026-10-07 디자인 보강 7번): 기본 카메라 방치 화면(이름표), 성문 하나가 깎인 스테이지 전투 화면을 찍어
## --dir에 720×1280 PNG로 저장한다. 화면이 필요하다. 저장 파일은 건드리지 않는다.
## 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/hud_shots.tscn -- --dir=/tmp/hud_shots

var _main
var _dir := "/tmp/hud_shots"


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Pvp.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	if Net.arg_value("dir") != "":
		_dir = Net.arg_value("dir")
	DirAccess.make_dir_recursive_absolute(_dir)
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(120)
	_save("castle_idle")
	GameState.start_stage()
	await _wait(2.0)
	GameState.damage_gate(1, GameState.gate_hp_max * 0.4)
	GameState.damage_gate(3, GameState.gate_hp_max)
	await _frames(4)
	_save("castle_stage")
	print("saved to ", _dir)
	get_tree().quit()


func _save(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png("%s/%s.png" % [_dir, name])


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

extends Node
## 스킬 칸·[스킬 AUTO] 화면(개발용, 2026-10-23): 스테이지 중 수동으로 두고 찍은 화면 + 영웅 12명(두 줄) 배치 화면.
## 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/skill_shots.tscn -- --out=/tmp/skill.png

const SkillAuto := preload("res://scripts/skill_auto_button.gd")

var _main


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	for h in preload("res://scripts/game_data.gd").heroes().slice(0, 5):
		Economy.heroes[h.id] = 1
	var was := SkillAuto.is_auto()
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(120)
	GameState.start_stage()
	await _frames(200)
	SkillAuto.set_auto(false)
	var strip = _main._strip
	var hs: Array = strip.heroes_fn.call()
	for h in hs:
		for k in h._skx._cd:
			h._skx._cd[k] = 0.0  # 준비된 칸(수동이면 빛난다)
	hs[1]._skx._cd[hs[1]._skx._cd.keys()[0]] = 5.0 if not hs[1]._skx._cd.is_empty() else 0.0  # 쿨 도는 칸 하나
	await _frames(20)
	var shots := [get_viewport().get_texture().get_image()]
	strip.heroes_fn = func(): return hs + hs + hs  # 12칸(두 줄) 배치 모양
	await _frames(20)
	shots.append(get_viewport().get_texture().get_image())
	SkillAuto.set_auto(was)
	var out := "/tmp/skill.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	var sheet := Image.create(1080, 960, false, Image.FORMAT_RGB8)
	for i in shots.size():
		var im: Image = shots[i]
		im.convert(Image.FORMAT_RGB8)
		im.resize(540, 960)
		sheet.blit_rect(im, Rect2i(0, 0, 540, 960), Vector2i(540 * i, 0))
	sheet.save_png(out)
	print("saved ", out)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

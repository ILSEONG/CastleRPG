extends Node
## 파티 퀘스트 화면 스냅샷(개발용): [파티] 탭, 매칭 띠, 입장 수락 창, 리치 전투(시작·스킬·영혼 수확), 거미 여왕 전투(거미 떼·스킬), 결과.
## 화면이 필요하다. 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/party_shots.tscn -- --out=/tmp/party
## (--out 폴더에 한 장씩 + sheet.png). 저장 파일은 건드리지 않는다(오프라인).

const GameData := preload("res://scripts/game_data.gd")
const BattleScript := preload("res://scripts/party_battle.gd")

var _main
var _out := "/tmp/party"
var _shots: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Party.save_path = ""
	Party.auto_accept = false
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	for h in GameData.heroes():
		Economy.heroes[str(h.id)] = 1
		Economy.hero_levels[str(h.id)] = 25
	Economy.soldiers = {"infantry:2": 8, "archer:2": 8}
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(90)
	var tabs = _find("res://scripts/tab_bar.gd")
	tabs.press("dungeon")
	var panel = tabs.windows.dungeon
	panel.set_section("party")
	await _snap("01_party_tab")
	for quest in ["lich", "spider"]:
		panel.party_tab._start(quest)
		await _frames(20)
		if quest == "lich":
			await _snap("02_matching")
		await get_tree().create_timer(2.6).timeout
		await _snap("03_confirm_" + quest)
		Party.accept(true)
		await _frames(30)
		await get_tree().create_timer(3.0).timeout
		await _snap("04_%s_start" % quest)
		var b = _battle()
		var marks := [9.0, 16.0, 30.0, 55.0] if quest == "lich" else [8.0, 18.0, 35.0, 60.0]
		var i := 0
		for m in marks:
			Engine.time_scale = 4.0
			while b != null and not b.done and b.clock < m:
				await _frames(2)
			Engine.time_scale = 1.0
			if b == null or b.done:
				break
			await _snap("05_%s_%d" % [quest, i])
			i += 1
		Engine.time_scale = 8.0
		while b != null and not b.done:
			await _frames(5)
		Engine.time_scale = 1.0
		await get_tree().create_timer(1.5).timeout
		await _snap("06_%s_result" % quest)
		_main.leave_dungeon()
		await _frames(20)
	var w: int = _shots[0].get_width() / 2
	var h: int = _shots[0].get_height() / 2
	var cols := 5
	var sheet := Image.create(w * cols, h * ((_shots.size() + cols - 1) / cols), false, Image.FORMAT_RGB8)
	for k in _shots.size():
		var img: Image = _shots[k].duplicate()
		img.convert(Image.FORMAT_RGB8)
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((k % cols) * w, (k / cols) * h))
	sheet.save_png(_out + "/sheet.png")
	print("saved ", _out, " shots=", _shots.size())
	get_tree().quit()


func _battle():
	for c in get_children():
		if c.get_script() == BattleScript and not c.is_queued_for_deletion():
			return c
	return null


func _snap(name: String) -> void:
	await _frames(8)
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, name])
	_shots.append(img)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _find(path: String) -> Node:
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
	return null

extends Node
## 싸움 따라가기 카메라 전/후(개발용, 2026-10-07 디자인 보강 2번): 골드·장비·모집권 던전, PVP 결투·총력전, 길드 드래곤을 시작해 SEC초 뒤
## 따라가기(camera_rig.follow)를 켠 화면과, 따라가기를 끄고 예전 고정 줌·가운데로 되돌린 화면을 찍어 위(전)·아래(후)로 붙인다.
## 아레나 영웅끼리 가장 가까운 거리(ally_pad 확인)도 찍는다. 화면이 필요하다. 저장 파일은 건드리지 않는다.
## 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/fight_cam_shots.tscn -- --out=/tmp/fight_cam.png [--sec=6] [--modes=total,dragon]

const GameData := preload("res://scripts/game_data.gd")
const MODES := ["gold", "equip", "ticket", "duel", "total", "dragon"]
var _thumb := Vector2i(360, 640)  # --full이면 720×1280

var _main
var _modes: Array = MODES
var _before: Array = []
var _after: Array = []


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Pvp.save_path = ""
	Pvp.load_save()
	Guild.load_save()
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	for h in GameData.heroes():
		Economy.heroes[str(h.id)] = 1
	Economy.soldiers = {"infantry:2": 8, "archer:1": 10, "cavalry:3": 6}
	var sec := float(Net.arg_value("sec")) if Net.arg_value("sec") != "" else 6.0
	if Net.arg_value("full") != "":
		_thumb = Vector2i(720, 1280)
	if Net.arg_value("modes") != "":
		_modes = Array(Net.arg_value("modes").split(","))
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(90)
	Pvp.fetch()
	Guild.unlocked = true
	Guild.join(Guild.recommendations()[0])
	for m in _modes:
		await _start(m)
		var scene = _main._dungeon
		if scene == null:
			print("FAIL no scene for ", m)
			get_tree().quit(1)
			return
		await get_tree().create_timer(sec).timeout
		var rig = scene.camera.get_parent()
		print("%s: zoom %.1f m (max %.1f, min %.1f), closest heroes %.2f m" % [m, scene.camera.size, rig.follow_max, rig.follow_min, _closest(scene)])
		_after.append(_shot())
		rig.follow_scope = null  # 예전: 고정 줌, 무대 가운데
		if rig.is_punching():
			rig._punch.kill()
		rig.position = Vector3(0, rig.position.y, 0)
		scene.camera.size = rig.follow_max
		rig.zoom_by(1.0)
		await _frames(4)
		_before.append(_shot())
		_main.leave_dungeon()
		Pvp.battle = {}  # 중간에 나온 PVP 판(다음 모드를 시작할 수 있게)
		await _frames(20)
	var sheet := Image.create(_thumb.x * _modes.size(), _thumb.y * 2, false, Image.FORMAT_RGB8)
	for i in _modes.size():
		sheet.blit_rect(_before[i], Rect2i(Vector2i.ZERO, _thumb), Vector2i(i * _thumb.x, 0))
		sheet.blit_rect(_after[i], Rect2i(Vector2i.ZERO, _thumb), Vector2i(i * _thumb.x, _thumb.y))
	var out := Net.arg_value("out") if Net.arg_value("out") != "" else "/tmp/fight_cam.png"
	sheet.save_png(out)
	print("saved ", out)
	get_tree().quit()


func _start(m: String) -> void:
	if m in ["gold", "equip", "ticket"]:
		_main._dev_dungeon(m)
	elif m == "dragon":
		var menu = _find("res://scripts/side_menu.gd")
		menu.pick("guild")
		var panel = menu.windows.guild
		panel.tab = "boss"
		panel._rebuild()
		await _frames(10)
		panel._start_fight()
	else:
		var tabs = _find("res://scripts/tab_bar.gd")
		tabs.press("dungeon")
		var panel = tabs.windows.dungeon
		panel.set_section("pvp")
		panel.pvp.open_mode(m)
		await _frames(3)
		if m == "duel":  # 방어팀 정하기(pvp_shots와 같은 순서)
			panel.pvp._open_picker("team")
			panel.pvp._confirm_pick()
			panel.pvp.open_mode(m)
			await _frames(3)
		panel.pvp._start()
	for i in 300:
		await get_tree().process_frame
		if _main._dungeon != null:
			break
	await _frames(10)


## 아레나에서 살아 있는 아군 영웅끼리 가장 가까운 바닥 거리(m).
func _closest(scene) -> float:
	var hs: Array = []
	for n in get_tree().get_nodes_in_group("crowd"):
		if scene.is_ancestor_of(n) and n.has_method("ally_pad") and n.is_alive() and n.get("team") in [null, 0]:
			hs.append(n)
	var best := INF
	for i in hs.size():
		for j in range(i + 1, hs.size()):
			var a: Vector3 = hs[i].global_position
			var b: Vector3 = hs[j].global_position
			best = minf(best, Vector2(a.x - b.x, a.z - b.z).length())
	return best


func _shot() -> Image:
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.resize(_thumb.x, _thumb.y, Image.INTERPOLATE_LANCZOS)
	return img


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _find(path: String) -> Node:
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
	return null

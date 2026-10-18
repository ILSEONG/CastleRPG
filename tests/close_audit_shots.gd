extends Node
## 창 닫기 점검 스냅샷(개발용, 사용자 2026-10-18 "팝업창 닫는 버튼이 없어"): 실제 main 씬에서 모든 창(ui_windows 무리)을 하나씩 열어
## --dir에 720×1280 PNG로 저장하고, 창마다 눈에 보이는 닫기 버튼(오른쪽 위 X)이 있는지 출력한다. 저장 파일은 건드리지 않는다.
## 실행: xvfb-run -a godot --path . --resolution 720x1280 --rendering-driver opengl3 res://tests/close_audit_shots.tscn -- --dir=/tmp/close_audit

const HEROES := ["arteon", "ignis", "sylvana", "grom", "baldur", "lumina", "kyle", "nev", "luna", "valen"]

var _main
var _dir := "/tmp/close_audit"


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Pvp.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	for id in HEROES:
		Economy.heroes[id] = 1
	Economy.diamonds = 500
	if Net.arg_value("dir") != "":
		_dir = Net.arg_value("dir")
	DirAccess.make_dir_recursive_absolute(_dir)
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(120)
	var missing := []
	for w in get_tree().get_nodes_in_group("ui_windows"):
		var name_s: String = w.get_script().resource_path.get_file().get_basename()
		match name_s:
			"building_panel":
				w.open_building("keep")
			"offline_panel":
				w.show_report({"away_sec": 7380.0, "kills": 1234, "gold_tenths": 56780000})
			_:
				w.open()
		await get_tree().create_timer(0.5).timeout
		await _frames(2)
		if not w.visible:
			print("AUDIT ", name_s, " did not open")
			continue
		_save(name_s)
		var how := _close_kind(w)
		print("AUDIT ", name_s, " close=", how)
		if how == "":
			missing.append(name_s)
		match name_s:
			"hero_panel":
				w.show_detail("arteon")
				await _sub(w, "hero_panel_detail")
			"dungeon_panel":
				for sec in ["pvp", "party"]:
					w.set_section(sec)
					await _sub(w, "dungeon_panel_" + sec)
				w.set_section("dungeon")
				w.open_form("gold")
				await _sub(w, "dungeon_panel_form")
		w.close()
		await _frames(2)
	var odds := _find(_main, "gacha_odds.gd")
	if odds != null:
		odds.call("show_odds") if odds.has_method("show_odds") else null
	print("AUDIT missing x: ", missing)
	print("saved to ", _dir)
	get_tree().quit()


func _sub(w, name_s: String) -> void:
	await get_tree().create_timer(0.4).timeout
	await _frames(2)
	_save(name_s)
	print("AUDIT ", name_s, " close=", _close_kind(w))


## 눈에 보이는 닫기: "x" = 오른쪽 위 X(close_x 또는 buttons.close), "button:<글자>" = 닫기·확인 같은 글자 버튼, "" = 없음.
func _close_kind(w) -> String:
	var x = w.get("close_x")
	if x is Control and x.is_visible_in_tree():
		return "x"
	var bs = w.get("buttons")
	if bs is Dictionary and bs.get("close") is Control and bs.close.is_visible_in_tree():
		return "x"
	var words := ["닫기", "확인", "◀"]
	for b in w.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and (b.text in words):
			return "button:" + b.text
	return ""


func _find(n: Node, file: String) -> Node:
	for c in n.get_children():
		if c.get_script() != null and c.get_script().resource_path.get_file() == file:
			return c
		var r := _find(c, file)
		if r != null:
			return r
	return null


func _save(name_s: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png("%s/%s.png" % [_dir, name_s])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

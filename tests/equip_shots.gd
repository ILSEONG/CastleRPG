extends Node
## 장비 화면 스냅샷(개발용, 2026-10-07 장비 개편): 보관함(능력치 색·특수 능력치 줄), 영웅 상세 장비 합계, 장비 고르기를 한 장으로 붙인다.
## 화면이 필요하다. 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/equip_shots.tscn -- --out=/tmp/equip.png
## 저장 파일은 건드리지 않는다(오프라인, save_path = "").

const SAMPLE := [
	{"slot": "weapon", "weapon_kind": "sword", "grade": "LR", "rolls": {"atk": 112}, "subs": [{"id": "lifesteal", "r": 108}, {"id": "crit_rate", "r": 87}, {"id": "aspd", "r": 100}]},
	{"slot": "top", "weapon_kind": null, "grade": "UR", "rolls": {"hp": 91}, "subs": [{"id": "dmg_reduce", "r": 114}, {"id": "skill_dmg", "r": 95}]},
	{"slot": "shoes", "weapon_kind": null, "grade": "SSR", "rolls": {"hp": 104, "speed_pct": 88}, "subs": [{"id": "crit_dmg", "r": 103}]},
	{"slot": "hat", "weapon_kind": null, "grade": "SR", "rolls": {"hp": 100}, "subs": [{"id": "aspd", "r": 86}]},
	{"slot": "gloves", "weapon_kind": null, "grade": "R", "rolls": {"atk": 115}, "subs": []},
	{"slot": "bottom", "weapon_kind": null, "grade": "N", "rolls": {"hp": 85}, "subs": []},
	{"slot": "pauldron", "weapon_kind": null, "grade": "SR", "rolls": {"hp": 109}, "subs": [{"id": "lifesteal", "r": 92}]},
]

var _main
var _shots: Array = []


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(90)
	for it in SAMPLE:
		var x: Dictionary = it.duplicate(true)
		x.id = Economy.next_item_id
		Economy.next_item_id += 1
		Economy.bag.append(x)
	Economy._reindex_items()
	Economy.equip("hans", "weapon", 1)
	Economy.equip("hans", "top", 2)
	Economy.equip("hans", "shoes", 3)
	Economy.items_changed.emit()
	var bag = _find("res://scripts/bag_panel.gd")
	bag.open_bag()
	await _snap()
	bag.close()
	var hp = _find("res://scripts/hero_panel.gd")
	var tabs = _find("res://scripts/tab_bar.gd")
	tabs.press("hero")
	await _frames(10)
	hp.show_detail("hans")
	await _snap()
	bag.open_pick("hans", "hat")
	await _snap()
	var out := "/tmp/equip.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var w: int = _shots[0].get_width()
	var h: int = _shots[0].get_height()
	var sheet := Image.create(w * _shots.size(), h, false, Image.FORMAT_RGB8)
	for i in _shots.size():
		var img: Image = _shots[i]
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	sheet.save_png(out)
	print("saved ", out, " shots=", _shots.size())
	get_tree().quit()


func _snap() -> void:
	await _frames(10)
	_shots.append(get_viewport().get_texture().get_image())


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _find(path: String) -> Node:
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
	return null

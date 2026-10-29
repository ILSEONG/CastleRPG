extends Node
## UR 모집 연출 시연 영상(개발용, 오프라인, 2026-10-29): 다이아 모집 창 → 1회(UR) → 10회(UR 1·SSR 1·SR 2).
## 결과는 정해 둔 영웅으로 넣는다(확률과 무관). UR 영웅이 표에 없으면 일러스트가 있는 SSR 영웅을 UR 등급으로 보여 준다(연출 확인용).
##   xvfb-run -a godot --path . --resolution 720x1280 --write-movie /tmp/ur.avi --fixed-fps 30 res://tests/ur_reveal_movie.tscn
## 저장 파일은 건드리지 않는다.

const GameData := preload("res://scripts/game_data.gd")
const HeroArt := preload("res://scripts/hero_art.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

var _main
var _caption: Label


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Pvp.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	Economy.diamonds = 50000
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	var layer := CanvasLayer.new()
	layer.layer = 40
	_caption = Label.new()
	_caption.add_theme_font_override("font", FONT)
	_caption.add_theme_font_size_override("font_size", 30)
	_caption.add_theme_color_override("font_color", Color(1.0, 0.95, 0.9))
	_caption.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.05))
	_caption.add_theme_constant_override("outline_size", 10)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.position = Vector2(20, 1150)
	_caption.size = Vector2(680, 110)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_caption)
	add_child(layer)
	await _wait(2.0)
	var by := {"UR": [], "SSR": [], "SR": [], "R": []}
	for h in GameData.heroes():
		if by.has(h.grade):
			by[h.grade].append(str(h.id))
	var arts: Array = by.SSR.filter(func(id): return HeroArt.texture(id) != null)
	var ur: Array = by.UR if not by.UR.is_empty() else arts.slice(0, 2)
	var ssr: String = arts[arts.size() - 1]
	var rp = _find("res://scripts/recruit_panel.gd")
	rp.open()
	rp.set_currency(GameData.GACHA_DIA)
	_say("다이아 모집 — UR")
	await _wait(1.2)
	_say("1회 모집 (UR)")
	rp._count = 1
	rp._cur = GameData.GACHA_DIA
	rp._show_results([_res(ur[0], "UR", true)])
	await _wait(8.0)
	rp._on_confirm()
	await _wait(0.6)
	_say("10회 모집 (UR 1장 · SSR 1장 · SR 2장)")
	rp._count = 10
	var ten := [by.R[0], by.SR[0], by.R[1], ssr, by.R[2], by.R[3], ur[ur.size() - 1], by.SR[1], by.R[4], by.R[5]]
	rp._show_results(ten.map(func(id): return _res(id, "UR" if id == ur[ur.size() - 1] else "", true)))
	await _wait(16.0)
	print("MOVIE ur done")
	get_tree().quit()


func _res(id: String, grade: String, is_new: bool) -> Dictionary:
	return {"hero_id": id, "grade": grade if grade != "" else GameData.hero(id).grade, "new": is_new, "shards": 2}


func _say(t: String) -> void:
	_caption.text = t


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _find(path: String) -> Node:
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
	return null

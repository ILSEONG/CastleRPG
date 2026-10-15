extends Node
## 영웅 모집 연출 시연 영상(개발용, 오프라인): 다이아 모집 창 → 1회(SR) → 10회(SSR 1·SR 2) → 10회(뒷면을 바로 눌러 한꺼번에 열기).
## 결과는 정해 둔 영웅으로 넣는다(확률과 무관). 장면마다 아래에 자막을 단다. 화면이 필요하다(--write-movie와 함께):
##   xvfb-run -a godot --path . --resolution 720x1280 --write-movie /tmp/gacha.avi --fixed-fps 30 res://tests/gacha_movie.tscn
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
	_caption.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
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
	var by := {"SSR": [], "SR": [], "R": []}
	for h in GameData.heroes():
		by[h.grade].append(str(h.id))
	var ssr: String = by.SSR[0]
	for id in by.SSR:  # 일러스트가 있는 SSR
		if HeroArt.texture(id) != null:
			ssr = id
			break
	var rp = _find("res://scripts/recruit_panel.gd")
	rp.open()
	rp.set_currency(GameData.GACHA_DIA)
	_say("영웅 모집 — 다이아 모집")
	await _wait(1.5)
	_say("1회 모집 (SR)")
	rp._count = 1
	rp._cur = GameData.GACHA_DIA
	rp._show_results([_res(by.SR[2], true)])
	await _wait(4.0)
	rp._on_confirm()
	await _wait(0.6)
	_say("10회 모집 (SSR 1장 · SR 2장)")
	rp._count = 10
	var ten := [by.R[0], by.SR[0], by.R[1], by.R[2], by.R[3], ssr, by.R[4], by.SR[1], by.R[5], by.R[6]]
	rp._show_results(ten.map(func(id): return _res(id, id != by.R[3])))
	await _wait(9.0)
	rp._on_confirm()
	await _wait(0.6)
	_say("10회 모집 — 화면을 누르면 바로 넘어가고, 카드를 누르면 모두 열립니다")
	var ten2 := [by.R[7 % by.R.size()], by.R[1], by.SR[3 % by.SR.size()], by.R[2], by.R[4], by.R[5], by.R[0], by.R[3], by.SR[0], by.R[6]]
	rp._show_results(ten2.map(func(id): return _res(id, false)))
	await _wait(0.6)
	_tap(Vector2(360, 640))
	await _wait(0.9)  # 소환진이 걷힌 직후의 보호 시간(연타 방지) 뒤에 카드를 누른다
	if not rp.cards.is_empty():
		_tap(rp._reveals[0].get_global_rect().get_center())
	await _wait(2.0)
	_say("결과 화면에서 바로 [1회 더] · [10회 더] — 같은 재화로 이어서 뽑습니다")
	Economy.diamonds = maxi(Economy.diamonds, 30000)
	Economy.changed.emit()
	await _wait(2.2)
	_tap(rp.again10_button.get_global_rect().get_center())  # 실제 다이아 10회(결과는 확률대로)
	await _wait(1.0)
	_say("[10회 더]를 누르면 다이아 2,700으로 곧바로 10회 더")
	await _wait(6.0)
	print("MOVIE gacha done")
	get_tree().quit()


func _res(id: String, is_new: bool) -> Dictionary:
	return {"hero_id": id, "grade": GameData.hero(id).grade, "new": is_new, "shards": 2}


func _tap(at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		Input.parse_input_event(e)


func _say(t: String) -> void:
	_caption.text = t


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _find(path: String) -> Node:
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
	return null

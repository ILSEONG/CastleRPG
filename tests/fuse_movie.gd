extends Node
## 영웅 합성 시연 영상(개발용, 오프라인, 2026-10-30): 영웅 창 [합성] 탭 → R→SR · SR→SSR · SSR→UR 줄마다 [합성] → [자동 채우기] → [합성]
## → 모집 연출로 결과 → [확인]으로 영웅 창에 돌아온다. 결과는 오프라인 규칙(무작위). 화면이 필요하다(--write-movie와 함께):
##   xvfb-run -a godot --path . --resolution 720x1280 --write-movie /tmp/fuse.avi --fixed-fps 30 res://tests/fuse_movie.tscn
## 저장 파일은 건드리지 않는다.

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
	for p in [["hans", 2, 6], ["ella", 2, 5], ["bron", 2, 12], ["arteon", 2, 6], ["ignis", 2, 5]]:
		Economy.heroes[p[0]] = p[1]
		Economy.hero_shards[p[0]] = p[2]
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
	_caption.position = Vector2(20, 1040)
	_caption.size = Vector2(680, 110)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_caption)
	add_child(layer)
	Economy.changed.emit()
	Economy.roster_changed.emit()
	await _wait(6.0)  # 불러오기 화면이 걷힐 때까지
	var hp = _find("res://scripts/hero_panel.gd")
	var rp = _find("res://scripts/recruit_panel.gd")
	hp.open()
	_say("영웅 창 — 위에 [영웅] · [합성] 탭")
	await _wait(2.0)
	_tap(hp.fuse_tab.get_global_rect().get_center())
	await _wait(0.4)
	_say("[합성] 탭 — 같은 등급 조각 10개로 한 단계 위 영웅 1명")
	await _wait(3.0)
	for g in ["R", "SR", "SSR"]:
		_say("%s 조각 10개 → %s 영웅" % [g, Economy.FUSE_NEXT[g]])
		_tap(hp.fuse_rows[g].button.get_global_rect().get_center())
		await _wait(1.4)
		_tap(hp.fuse.auto_button.get_global_rect().get_center())
		await _wait(1.4)
		_tap(hp.fuse.fuse_button.get_global_rect().get_center())
		await _wait(6.5)
		if rp.visible and rp.confirm_button != null and rp.confirm_button.is_visible_in_tree():
			_tap(rp.confirm_button.get_global_rect().get_center())
		elif rp.visible:
			rp._on_confirm()
		await _wait(1.5)
	_say("[영웅] 탭으로 돌아가면 새 영웅이 목록에")
	_tap(hp.heroes_tab.get_global_rect().get_center())
	await _wait(3.0)
	print("MOVIE fuse done")
	get_tree().quit()


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

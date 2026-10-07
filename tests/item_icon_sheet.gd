extends Node
## 장비 칸 한눈에 보기(개발용, 2026-10-07 장비 디자인): 부위 11종 × 등급 6단계를 실제 크기(72 px)로, 오른쪽에 검 6등급을 두 배(144 px)로 그린다.
## 화면이 필요하다. 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/item_icon_sheet.tscn -- --out=/tmp/items.png
## --t=초 로 LR 흐름·반짝임 시각을 고정한다(기본 1.0).

const Icons := preload("res://scripts/icons.gd")
const BG := Color(0.95, 0.93, 0.88)
const SMALL := 72.0
const BIG := 144.0
const GAP := 12.0

var _t := 1.0


func _ready() -> void:
	var out := "/tmp/items.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--t="):
			_t = float(a.substr(4))
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.draw.connect(_paint.bind(c))
	add_child(c)
	for i in 6:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("saved ", out)
	get_tree().quit()


func _paint(c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), BG)
	var font := ThemeDB.fallback_font
	var grades: Array = ["N", "R", "SR", "SSR", "UR", "LR"]
	var step := SMALL + GAP
	for gi in grades.size():
		var x := 20.0 + gi * step
		c.draw_string(font, Vector2(x, 26), grades[gi], HORIZONTAL_ALIGNMENT_CENTER, SMALL, 20, Color(0.2, 0.18, 0.15))
		for ki in Icons.ITEM_KINDS.size():
			Icons.draw_item(c, Icons.ITEM_KINDS[ki], grades[gi], Vector2(x + SMALL / 2.0, 40.0 + ki * step + SMALL / 2.0), SMALL, _t)
	var bx := 20.0 + grades.size() * step + 8.0
	for gi in grades.size():
		Icons.draw_item(c, "sword" if gi % 2 == 0 else "top", grades[gi], Vector2(bx + BIG / 2.0, 40.0 + gi * (BIG + 6.0) + BIG / 2.0), BIG, _t)

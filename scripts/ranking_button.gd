extends CanvasLayer
## HUD 랭킹 버튼: 오른쪽, 스테이지 패널 바로 아래의 트로피 버튼 → 랭킹 시트(ranking_panel.gd). 온라인에서만 보인다(랭킹은 서버 값).
## main.gd가 만들고 panel을 넣는다. 다른 창이 열려 있으면 그 창이 입력을 먹으므로 따로 막지 않는다.

const UiKit := preload("res://scripts/ui_kit.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const SIZE := Vector2(84, 84)
const TOP := 288.0  # 스테이지 패널(76..~276) 아래
const SIDE := 16.0
const GOLD := Color(0.98, 0.76, 0.18)
const BASE := Color(0.30, 0.34, 0.46)

var panel  # ranking_panel.gd
var button: Button


func _ready() -> void:
	layer = 1
	button = Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.offset_left = -SIDE - SIZE.x
	button.offset_right = -SIDE
	button.offset_top = TOP
	button.offset_bottom = TOP + SIZE.y
	UiKit.apply_button(button, BASE, 12.0)
	button.pressed.connect(_on_pressed)
	add_child(button)
	var face := Control.new()
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.draw.connect(func(): _draw_face(face))
	button.add_child(face)
	visible = Net.is_online()


func _on_pressed() -> void:
	if panel != null and not panel.is_open():
		panel.open()


func _draw_face(c: Control) -> void:
	var ctr := Vector2(c.size.x / 2.0, 34)
	draw_trophy(c, ctr, 44.0)
	var y := c.size.y - 10.0
	c.draw_string_outline(FONT, Vector2(0, y), "랭킹", HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 20, 5, Color(UiKit.INK, 0.85))
	c.draw_string(FONT, Vector2(0, y), "랭킹", HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 20, Color.WHITE)


## 각진 트로피(컵 + 손잡이 + 받침). ctr = 컵 가운데, s = 전체 높이.
static func draw_trophy(ci: CanvasItem, ctr: Vector2, s: float) -> void:
	var u := s / 44.0
	var p := func(x: float, y: float) -> Vector2: return ctr + Vector2(x, y) * u
	var dark := GOLD.darkened(0.25)
	# 손잡이
	ci.draw_polyline(PackedVector2Array([p.call(-11, -14), p.call(-19, -14), p.call(-19, -6), p.call(-10, 0)]), dark, 3.5 * u)
	ci.draw_polyline(PackedVector2Array([p.call(11, -14), p.call(19, -14), p.call(19, -6), p.call(10, 0)]), dark, 3.5 * u)
	# 컵(왼쪽 밝은 면 + 오른쪽 어두운 면)
	ci.draw_colored_polygon(PackedVector2Array([p.call(-13, -18), p.call(0, -18), p.call(0, 6), p.call(-8, 2)]), GOLD.lightened(0.15))
	ci.draw_colored_polygon(PackedVector2Array([p.call(0, -18), p.call(13, -18), p.call(8, 2), p.call(0, 6)]), GOLD)
	# 기둥·받침
	ci.draw_colored_polygon(PackedVector2Array([p.call(-3, 6), p.call(3, 6), p.call(4, 12), p.call(-4, 12)]), dark)
	ci.draw_colored_polygon(PackedVector2Array([p.call(-11, 12), p.call(11, 12), p.call(12, 18), p.call(-12, 18)]), GOLD.darkened(0.1))
	var rim := PackedVector2Array([p.call(-13, -18), p.call(13, -18), p.call(8, 2), p.call(0, 6), p.call(-8, 2), p.call(-13, -18)])
	ci.draw_polyline(rim, LowpolyBox.edge_color(GOLD), 1.5 * u, true)
	# 별
	var star := PackedVector2Array()
	for k in 10:
		var r := (5.5 if k % 2 == 0 else 2.4) * u
		var a := -PI / 2.0 + k * PI / 5.0
		star.append(p.call(0, -8) + Vector2(cos(a), sin(a)) * r)
	ci.draw_colored_polygon(star, Color(1, 1, 1, 0.9))

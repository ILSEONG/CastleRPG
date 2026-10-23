extends CanvasLayer
## [건설] 버튼(처음엔 [건물], 사용자 02:20Z "버튼명을 건물대신 건설이라고해")(사용자 2026-10-13 "1.5배속 밑에 건물 버튼을 하나 둬서, 건물을 선택하고 내가 원하는 공간에다 건물을 짓는 형태"):
## 성 화면 왼쪽 아래, 배속 버튼 자리(오른쪽 아래 [메뉴] 토글과 아래 끝을 맞춘다 — 하단 탭·초상화 줄·가이드 카드보다 위). 배속 버튼은 이 버튼 위로 올라간다.
## 이 버튼은 배속 버튼이 숨거나 바뀌어도 제자리다. 누르면 오른쪽으로 펼쳐지는 건물 목록(build_list_panel.gd, 다시 누르면 접힘). 지을 수 있는 공터가 있으면 오른쪽 위 빨간 점.
## 스테이지를 미는 동안은 main이 숨긴다(_battle_hide).

const Lang := preload("res://scripts/lang.gd")

const UiKit := preload("res://scripts/ui_kit.gd")
const HudScript := preload("res://scripts/hud.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const SIZE := Vector2(84, 84)
const SIDE := 16.0
const ABOVE := 12.0  # 탭 바·초상화 줄·가이드 카드 위 여백
const CENTER_Y := 0.70  # [메뉴]가 없으면 버튼 가운데 = 화면 높이의 이 지점
const COLOR := Color(0.55, 0.40, 0.26)  # 나무색
const DOT_R := 9.0

var card  # tutorial_card.gd(있으면 그 위로)
var strip  # hero_strip.gd(보이면 그 위로)
var menu  # side_menu.gd(그 [메뉴] 토글과 아래 끝을 맞춘다)
var panel  # build_list_panel.gd — 누르면 연다
var button: Button
var _face: Control
var _dot := false


func _ready() -> void:
	layer = 1  # HUD와 같은 층(창은 2 이상이 덮는다)
	button = Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = SIZE
	button.size = SIZE
	button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	UiKit.apply_button(button, COLOR, 12.0)
	_face = Control.new()
	_face.size = SIZE
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.draw.connect(_draw_face)
	button.add_child(_face)
	button.pressed.connect(func(): if panel != null: panel.toggle())
	add_child(button)
	Tutorial.register_ui("build_button", button, func(): return panel == null or not panel.is_open())  # 가이드 화살표(목록이 펼쳐지면 그 카드를 가리킨다)
	Economy.changed.connect(_refresh_dot)
	_refresh_dot()
	_place()


func _process(_delta: float) -> void:
	button.visible = Tutorial.ui_shown("build_button")  # 가이드 중에는 첫 건설 미션까지 숨긴다(초반 단순화 2026-10-23)
	_place()


## 빨간 점: 자리를 안 잡은 공터 중 지금 바로 지을 수 있는 것(가이드 잠금·자원·일꾼)이 있다.
func _refresh_dot() -> void:
	var now := Economy.time_now()
	var on := false
	for id in Economy.unbuilt:
		if not Economy.is_placed(id) and not Tutorial.build_locked(id) and Economy.upgrade_block(id, now) == "":
			on = true
			break
	if on != _dot:
		_dot = on
		_face.queue_redraw()


func _place() -> void:
	var vh := get_viewport().get_visible_rect().size.y
	var bottom := vh * CENTER_Y + SIZE.y / 2.0
	if menu != null and is_instance_valid(menu) and menu.toggle != null and menu.toggle.size.y > 0.0:
		bottom = menu.toggle.global_position.y + menu.toggle.size.y  # [메뉴] 토글과 같은 높이
	var limit := vh - float(HudScript.TAB_BAR_H) - ABOVE
	if strip != null and strip.visible and strip.row != null and strip.row.size.y > 0.0:
		limit = minf(limit, strip.row.global_position.y - ABOVE)
	if card != null and card.panel != null and card.panel.visible:
		limit = minf(limit, card.panel.global_position.y - ABOVE)
	button.position = Vector2(SIDE, minf(bottom, limit) - SIZE.y)


func _draw_face() -> void:
	var ink := Color(UiKit.INK, 0.85)
	var col := Color.WHITE
	# 집 모양: 지붕 삼각형 + 몸통 + 문
	var cx := SIZE.x / 2.0
	var roof := PackedVector2Array([Vector2(cx - 20, 30), Vector2(cx, 13), Vector2(cx + 20, 30)])
	var body := PackedVector2Array([Vector2(cx - 14, 29), Vector2(cx + 14, 29), Vector2(cx + 14, 47), Vector2(cx - 14, 47)])
	for poly in [body, roof]:
		var rim: PackedVector2Array = poly.duplicate()
		rim.append(rim[0])
		_face.draw_polyline(rim, ink, 4.0, true)
		_face.draw_colored_polygon(poly, col)
	_face.draw_rect(Rect2(cx - 4, 36, 8, 11), COLOR.darkened(0.2))
	_face.draw_string_outline(FONT, Vector2(0, 74), Lang.t("build_button.draw_face"), HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 20, 5, ink)
	_face.draw_string(FONT, Vector2(0, 74), Lang.t("build_button.draw_face"), HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 20, col)
	if _dot:
		_face.draw_circle(Vector2(SIZE.x - 8, 8), DOT_R + 2.0, Color.WHITE)
		_face.draw_circle(Vector2(SIZE.x - 8, 8), DOT_R, Color(0.88, 0.22, 0.2))

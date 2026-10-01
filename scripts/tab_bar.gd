extends CanvasLayer
## 하단 탭 바(스펙 §2.3, 개정 13 §7.1): 화면 맨 아래 로우폴리 바 1줄(HudScript.TAB_BAR_H)에 같은 폭 탭 4개 —
## 영웅(영웅 목록)·병사(병사 시트)·모집(주점 창)·상인(거래 창). [성] 탭은 없다 — 전장은 모든 창이 닫힌 기본 상태(선택 없음).
## 탭마다 각진 아이콘 + 글자. 선택된 탭은 호박색 면에 위로 RAISE px 올라오고, 나머지는 강철색이다. 선택은 열린 창을 따른다
## (visibility_changed) — 건물 탭으로 연 창도 그 탭이 선택되고, 창이 닫히면 선택이 없어진다. 이미 선택된 탭을 다시 누르면 그 창을 닫는다.
## 층 3: 창(층 2)의 어두운 배경 위라 창이 열려 있어도 탭 바는 계속 누를 수 있다(창의 연 직후 보호 시간에는 누름이 버려진다).

const UiKit := preload("res://scripts/ui_kit.gd")
const HudScript := preload("res://scripts/hud.gd")
const IconsScript := preload("res://scripts/icons.gd")
const UiWindow := preload("res://scripts/ui_window.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const TABS := [["hero", "영웅"], ["soldier", "병사"], ["recruit", "모집"], ["merchant", "상인"]]
const RAISE := 4.0
const PAD := 8.0  # 바 안 여백·탭 사이 간격의 절반
const ICON_PX := 46.0

var windows := {}  # 탭 id → 창(ui_window). main이 add_child 전에 넣는다
var selected := ""  # 열린 창의 탭(없으면 "")
var buttons := {}  # 탭 id → Button

var _bar: Control


func _ready() -> void:
	layer = 3
	_bar = Panel.new()
	_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.offset_top = -HudScript.TAB_BAR_H
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP  # 탭 사이 틈도 뒤(카메라·창 배경)로 새지 않는다
	_bar.mouse_force_pass_scroll_events = false  # 휠도 카메라 줌으로 새지 않게
	_bar.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM_DIALOG, 0.0, 0, 0.05))
	add_child(_bar)
	for i in TABS.size():
		var id: String = TABS[i][0]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.anchor_left = float(i) / TABS.size()
		b.anchor_right = float(i + 1) / TABS.size()
		b.anchor_bottom = 1.0
		b.pressed.connect(press.bind(id))
		var face := Control.new()  # 아이콘·글자(버튼 상자 위에 그린다)
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.draw.connect(_draw_face.bind(face, i))
		b.add_child(face)
		_bar.add_child(b)
		buttons[id] = b
	for id in windows:
		windows[id].visibility_changed.connect(_refresh)
	_refresh()


## 탭 누름: 그 탭의 창이 닫혀 있으면 다른 창(건물 창 등 탭 밖 창 포함)을 모두 닫고 연다. 열려 있으면 모두 닫는다.
func press(id: String) -> void:
	var w = windows.get(id)
	var open_it: bool = w != null and not w.is_open()
	for x in get_tree().get_nodes_in_group(UiWindow.GROUP):
		if x.is_open():
			x.close()
	if open_it:
		w.open()
	_refresh()


## 선택 = 열린 창의 탭(없으면 ""). 선택은 호박색 + RAISE px 위, 나머지는 강철색.
func _refresh() -> void:
	selected = ""
	for id in windows:
		if windows[id].is_open():
			selected = id
			break
	for id in buttons:
		var b: Button = buttons[id]
		var on: bool = id == selected
		UiKit.apply_button(b, UiKit.AMBER if on else UiKit.STEEL, 12.0)
		b.offset_left = PAD
		b.offset_right = -PAD
		b.offset_top = PAD - (RAISE if on else 0.0)
		b.offset_bottom = -PAD - (RAISE if on else 0.0)


func _draw_face(face: Control, i: int) -> void:
	var c := Vector2(face.size.x / 2.0, face.size.y * 0.4)
	draw_shapes(face, tab_shapes(TABS[i][0]), c, ICON_PX)
	var y := face.size.y - 12.0
	face.draw_string_outline(FONT, Vector2(0, y), TABS[i][1], HORIZONTAL_ALIGNMENT_CENTER, face.size.x, 24, 6, Color(UiKit.INK, 0.85))
	face.draw_string(FONT, Vector2(0, y), TABS[i][1], HORIZONTAL_ALIGNMENT_CENTER, face.size.x, 24, Color.WHITE)


## IconsScript와 같은 형식([단위 좌표 점들, 색, 외곽선 여부])의 도형을 center 중심 size_px 크기로 그린다.
static func draw_shapes(ci: CanvasItem, shapes: Array, center: Vector2, size_px: float) -> void:
	for s in shapes:
		var pts := PackedVector2Array()
		for p in s[0]:
			pts.append(center + p * size_px)
		ci.draw_colored_polygon(pts, s[1])
		if s[2]:
			pts.append(pts[0])
			ci.draw_polyline(pts, IconsScript.OUTLINE, maxf(1.0, size_px / 30.0))


## 탭 아이콘(각진 평면 로우폴리): 영웅 = 방패·병사 = 쇠 투구(둘 다 밝은 왼쪽 면), 모집 = 맥주잔, 상인 = 금화(자원 아이콘).
static func tab_shapes(id: String) -> Array:
	match id:
		"soldier":  # 쇠 투구: 각진 돔(왼쪽 면 밝게) + 챙 + 코 가리개 + 눈 틈 둘
			var dome := [Vector2(-0.38, 0.28), Vector2(-0.36, -0.08), Vector2(-0.22, -0.34), Vector2(0.0, -0.44), Vector2(0.22, -0.34),
				Vector2(0.36, -0.08), Vector2(0.38, 0.28)]
			var slit := Color(0.2, 0.22, 0.28)
			return [
				[dome, Color(0.56, 0.6, 0.68), true],
				[[Vector2(-0.38, 0.28), Vector2(-0.36, -0.08), Vector2(-0.22, -0.34), Vector2(0.0, -0.44), Vector2(0.0, 0.28)], Color(0.78, 0.82, 0.88), false],
				[[Vector2(-0.32, 0.02), Vector2(-0.08, 0.02), Vector2(-0.08, 0.13), Vector2(-0.32, 0.13)], slit, false],
				[[Vector2(0.08, 0.02), Vector2(0.32, 0.02), Vector2(0.32, 0.13), Vector2(0.08, 0.13)], slit, false],
				[[Vector2(-0.05, -0.04), Vector2(0.05, -0.04), Vector2(0.05, 0.36), Vector2(-0.05, 0.36)], Color(0.44, 0.48, 0.56), true],
				[[Vector2(-0.46, 0.28), Vector2(0.46, 0.28), Vector2(0.4, 0.42), Vector2(-0.4, 0.42)], Color(0.46, 0.5, 0.58), true],
				[dome, Color(0, 0, 0, 0), true],
			]
		"hero":
			var rim := [Vector2(-0.38, -0.4), Vector2(0.38, -0.4), Vector2(0.38, 0.02), Vector2(0.0, 0.46), Vector2(-0.38, 0.02)]
			return [
				[rim, Color(0.3, 0.42, 0.66), true],
				[[Vector2(-0.38, -0.4), Vector2(0.0, -0.4), Vector2(0.0, 0.46), Vector2(-0.38, 0.02)], Color(0.45, 0.58, 0.82), false],
				[[Vector2(-0.05, -0.3), Vector2(0.05, -0.3), Vector2(0.05, 0.3), Vector2(-0.05, 0.3)], Color(0.98, 0.84, 0.4), false],
				[[Vector2(-0.24, -0.08), Vector2(0.24, -0.08), Vector2(0.24, 0.02), Vector2(-0.24, 0.02)], Color(0.98, 0.84, 0.4), false],
				[rim, Color(0, 0, 0, 0), true],
			]
		"recruit":
			return [
				[[Vector2(0.14, -0.14), Vector2(0.42, -0.14), Vector2(0.42, 0.26), Vector2(0.14, 0.26), Vector2(0.14, 0.14), Vector2(0.3, 0.14),
					Vector2(0.3, -0.02), Vector2(0.14, -0.02)], Color(0.62, 0.42, 0.2), true],
				[[Vector2(-0.34, -0.22), Vector2(0.18, -0.22), Vector2(0.18, 0.44), Vector2(-0.34, 0.44)], Color(0.95, 0.68, 0.18), true],
				[[Vector2(-0.34, -0.22), Vector2(-0.12, -0.22), Vector2(-0.12, 0.44), Vector2(-0.34, 0.44)], Color(1.0, 0.82, 0.4), false],
				[[Vector2(-0.4, -0.2), Vector2(-0.3, -0.38), Vector2(-0.08, -0.44), Vector2(0.12, -0.38), Vector2(0.24, -0.2)], Color(0.99, 0.97, 0.9), true],
			]
		"merchant":
			return IconsScript.shapes("gold")
	return []

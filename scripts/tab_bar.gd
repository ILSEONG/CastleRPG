extends CanvasLayer
## 하단 탭 바(스펙 §2.3, 개정 13 §7.1, 개정 18 §1): 화면 맨 아래 로우폴리 바 1줄(HudScript.TAB_BAR_H)에 같은 폭 탭 6개 —
## 성장(성장 시트, 개정 20)·영웅(영웅 목록)·병사(병사 시트)·던전(던전 시트)·모집(주점 창)·상점(상점 시트, 2026-10-07 — 길드는 오른쪽 아래 메뉴로 옮겼다).
## 상인은 탭이 없다(성 안 상인 NPC를 탭). [상점]은 받을 무료 선물이 있으면 오른쪽 위에 빨간 점.
## [성] 탭은 없다 — 전장은 모든 창이 닫힌 기본 상태(선택 없음).
## 탭마다 각진 아이콘 + 글자. 선택된 탭은 호박색 면에 위로 RAISE px 올라오고, 나머지는 강철색이다. 선택은 열린 창을 따른다
## (visibility_changed) — 건물 탭으로 연 창도 그 탭이 선택되고, 창이 닫히면 선택이 없어진다. 이미 선택된 탭을 다시 누르면 그 창을 닫는다.
## 층 3: 창(층 2)의 어두운 배경 위라 창이 열려 있어도 탭 바는 계속 누를 수 있다(창의 연 직후 보호 시간에는 누름이 버려진다).

const UiKit := preload("res://scripts/ui_kit.gd")
const HudScript := preload("res://scripts/hud.gd")
const IconsScript := preload("res://scripts/icons.gd")
const UiWindow := preload("res://scripts/ui_window.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const TABS := [["growth", "성장"], ["hero", "영웅"], ["soldier", "병사"], ["dungeon", "던전"], ["recruit", "모집"], ["shop", "상점"]]
const RAISE := 4.0
const PAD := 8.0  # 바 안 여백·탭 사이 간격의 절반
const ICON_PX := 46.0
## 튜토리얼 잠금 자물쇠(각진 고리 + 금색 몸통 + 열쇠 구멍)
const LOCK_SHAPES := [
	[[Vector2(-0.30, -0.02), Vector2(-0.30, -0.28), Vector2(-0.16, -0.44), Vector2(0.16, -0.44), Vector2(0.30, -0.28), Vector2(0.30, -0.02),
		Vector2(0.18, -0.02), Vector2(0.18, -0.24), Vector2(0.10, -0.32), Vector2(-0.10, -0.32), Vector2(-0.18, -0.24), Vector2(-0.18, -0.02)],
		Color(0.62, 0.64, 0.70), true],
	[[Vector2(-0.40, -0.04), Vector2(0.40, -0.04), Vector2(0.40, 0.44), Vector2(-0.40, 0.44)], Color(0.95, 0.72, 0.22), true],
	[[Vector2(-0.06, 0.08), Vector2(0.06, 0.08), Vector2(0.06, 0.30), Vector2(-0.06, 0.30)], Color(0.30, 0.22, 0.14), false],
]

var windows := {}  # 탭 id → 창(ui_window). main이 add_child 전에 넣는다
var selected := ""  # 열린 창의 탭(없으면 "")
var buttons := {}  # 탭 id → Button

var _bar: Control
var _shop_dot := false


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
	Tutorial.changed.connect(_refresh)  # 튜토리얼: 탭은 그 탭을 소개하는 미션에 닿을 때 열린다
	_refresh()


## 탭 누름: 그 탭의 창이 닫혀 있으면 다른 창(건물 창 등 탭 밖 창 포함)을 모두 닫고 연다. 열려 있으면 모두 닫는다.
func press(id: String) -> void:
	if Tutorial.tab_locked(id):
		Tutorial.lock_notice.emit(Tutorial.tab_lock_text(id))
		return
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
		b.modulate = Color(1, 1, 1, 0.45) if Tutorial.tab_locked(id) else Color.WHITE
		for c in b.get_children():
			c.queue_redraw()


func _draw_face(face: Control, i: int) -> void:
	var c := Vector2(face.size.x / 2.0, face.size.y * 0.4)
	draw_shapes(face, tab_shapes(TABS[i][0]), c, ICON_PX)
	if Tutorial.tab_locked(TABS[i][0]):  # 자물쇠(오른쪽 위)
		draw_shapes(face, LOCK_SHAPES, Vector2(face.size.x - 22.0, 22.0), 30.0)
	elif TABS[i][0] == "shop" and _shop_dot:  # 무료 선물
		var dp := Vector2(face.size.x - 16.0, 16.0)
		face.draw_circle(dp, 9.0, Color(0.88, 0.22, 0.2))
		face.draw_arc(dp, 9.0, 0, TAU, 16, Color(0.88, 0.22, 0.2).darkened(0.3), 1.5, true)
	var y := face.size.y - 12.0
	face.draw_string_outline(FONT, Vector2(0, y), TABS[i][1], HORIZONTAL_ALIGNMENT_CENTER, face.size.x, 24, 6, Color(UiKit.INK, 0.85))
	face.draw_string(FONT, Vector2(0, y), TABS[i][1], HORIZONTAL_ALIGNMENT_CENTER, face.size.x, 24, Color.WHITE)


func _process(_delta: float) -> void:
	var d := Economy.shop_free_left("daily") or Economy.shop_free_left("weekly")
	if d != _shop_dot and buttons.has("shop"):
		_shop_dot = d
		buttons.shop.get_child(0).queue_redraw()


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


## 탭 아이콘(각진 평면 로우폴리): 영웅 = 방패·병사 = 쇠 투구(둘 다 밝은 왼쪽 면), 모집 = 맥주잔, 성장 = 오르는 초록 막대 + 금색 화살표,
## 던전 = 돌 아치 문 + 해골.
static func tab_shapes(id: String) -> Array:
	match id:
		"shop":  # 상점 가판대: 빨강·크림 줄무늬 차양(아래 물결) + 나무 가판대(어두운 창) + 앞 판대 + 금화
			var out := []
			for k in 4:
				var x0 := -0.48 + k * 0.24
				out.append([[Vector2(x0 + 0.04, -0.44), Vector2(x0 + 0.28, -0.44), Vector2(x0 + 0.24, -0.14), Vector2(x0 + 0.12, -0.08), Vector2(x0, -0.14)],
					Color(0.86, 0.26, 0.24) if k % 2 == 0 else Color(0.98, 0.92, 0.80), true])
			return [
				[[Vector2(-0.40, -0.14), Vector2(0.40, -0.14), Vector2(0.40, 0.44), Vector2(-0.40, 0.44)], Color(0.62, 0.42, 0.24), true],
				[[Vector2(-0.40, -0.14), Vector2(0.0, -0.14), Vector2(0.0, 0.44), Vector2(-0.40, 0.44)], Color(0.72, 0.52, 0.32), false],
				[[Vector2(-0.28, -0.04), Vector2(0.28, -0.04), Vector2(0.28, 0.16), Vector2(-0.28, 0.16)], Color(0.24, 0.17, 0.14), true],
				[[Vector2(-0.46, 0.16), Vector2(0.46, 0.16), Vector2(0.46, 0.28), Vector2(-0.46, 0.28)], Color(0.80, 0.60, 0.36), true],
			] + out + [
				[IconsScript._ngon(8, 0.15, PI / 8.0).map(func(p): return p + Vector2(0.22, 0.32)), Color(0.95, 0.76, 0.20), true],
			]
		"guild":  # 깃대에 걸린 각진 길드 깃발(왼쪽 면 밝게) + 금색 별
			var flag := [Vector2(-0.26, -0.40), Vector2(0.40, -0.40), Vector2(0.40, 0.16), Vector2(0.07, 0.34), Vector2(-0.26, 0.16)]
			var star := []
			for k in 10:
				var r := 0.15 if k % 2 == 0 else 0.065
				var a := -PI / 2.0 + k * PI / 5.0
				star.append(Vector2(0.07, -0.08) + Vector2(cos(a), sin(a)) * r)
			return [
				[[Vector2(-0.40, -0.46), Vector2(-0.32, -0.46), Vector2(-0.32, 0.46), Vector2(-0.40, 0.46)], Color(0.55, 0.38, 0.22), true],
				[flag, Color(0.56, 0.30, 0.70), true],
				[[flag[0], Vector2(0.07, -0.40), Vector2(0.07, 0.34), flag[4]], Color(0.70, 0.46, 0.84), false],
				[star, Color(0.98, 0.84, 0.36), true],
				[flag, Color(0, 0, 0, 0), true],
			]
		"dungeon":  # 각진 돌 아치(밝은 왼쪽 면) + 어두운 문간 + 해골(눈 둘)
			var arch := [Vector2(-0.44, 0.44), Vector2(-0.44, -0.12), Vector2(-0.3, -0.36), Vector2(0.0, -0.46), Vector2(0.3, -0.36), Vector2(0.44, -0.12),
				Vector2(0.44, 0.44)]
			var door := [Vector2(-0.26, 0.44), Vector2(-0.26, -0.06), Vector2(-0.16, -0.22), Vector2(0.0, -0.28), Vector2(0.16, -0.22), Vector2(0.26, -0.06),
				Vector2(0.26, 0.44)]
			var skull := [Vector2(-0.13, -0.02), Vector2(-0.07, -0.12), Vector2(0.07, -0.12), Vector2(0.13, -0.02), Vector2(0.1, 0.1), Vector2(0.05, 0.16),
				Vector2(-0.05, 0.16), Vector2(-0.1, 0.1)]
			return [
				[arch, Color(0.5, 0.48, 0.5), true],
				[[arch[0], arch[1], arch[2], arch[3], door[3], door[2], door[1], door[0]], Color(0.68, 0.66, 0.66), false],
				[door, Color(0.2, 0.15, 0.17), true],
				[skull, Color(0.95, 0.92, 0.84), true],
				[[Vector2(-0.08, -0.04), Vector2(-0.02, -0.04), Vector2(-0.03, 0.03), Vector2(-0.08, 0.03)], Color(0.2, 0.15, 0.17), false],
				[[Vector2(0.02, -0.04), Vector2(0.08, -0.04), Vector2(0.08, 0.03), Vector2(0.03, 0.03)], Color(0.2, 0.15, 0.17), false],
				[arch, Color(0, 0, 0, 0), true],
			]
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
		"growth":  # 오르는 초록 막대 셋 + 각진 금색 위쪽 화살표
			var bar := Color(0.30, 0.68, 0.34)
			return [
				[[Vector2(-0.42, 0.42), Vector2(-0.20, 0.42), Vector2(-0.20, 0.16), Vector2(-0.42, 0.16)], bar, true],
				[[Vector2(-0.12, 0.42), Vector2(0.10, 0.42), Vector2(0.10, -0.02), Vector2(-0.12, -0.02)], bar, true],
				[[Vector2(0.18, 0.42), Vector2(0.40, 0.42), Vector2(0.40, -0.18), Vector2(0.18, -0.18)], bar, true],
				[[Vector2(-0.375, 0.063), Vector2(0.234, -0.287), Vector2(0.274, -0.217), Vector2(0.40, -0.44), Vector2(0.144, -0.443),
					Vector2(0.184, -0.373), Vector2(-0.425, -0.023)], UiKit.AMBER, true],
			]
	return []

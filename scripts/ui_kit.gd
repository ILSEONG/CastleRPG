extends RefCounted
## 로우폴리 UI 키트(스펙 §4). 모든 함수 정적. 사용 예:
##   const UiKit := preload("res://scripts/ui_kit.gd")
##   panel.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM_PANEL))   # 패널(내용 여백 12)
##   UiKit.apply_button(btn, UiKit.AMBER)                                         # normal/hover/pressed/disabled + 글자색
##   UiKit.apply_bar(progress_bar, UiKit.AMBER)                                   # ProgressBar 배경+채움
##   func _draw(): UiKit.draw_gem(self, Vector2(40, 40), 14, UiKit.GRADE_COLORS.SSR)   # 등급 보석
##   func _draw(): UiKit.draw_facet_card(self, Rect2(0, 0, 120, 160), UiKit.GRADE_COLORS.SR, UiKit.CREAM)
## 같은 인자의 StyleBox는 캐시로 재사용한다(StyleBox는 크기별 지오메트리를 스스로 캐시).
## 보석·카드는 *_geometry가 삼각형 배열(점 3개씩 + 점마다 색)을 돌려준다 — 매 프레임 다시 그리는 쪽은 이것을 캐시해
## canvas_item_add_triangle_array 한 번으로 그린다.

const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const Art := preload("res://scripts/art.gd")

const CREAM := Color("FBF7EE")
const CREAM_PANEL := Color(0.984, 0.969, 0.933, 0.78)  # 반투명 크림(HUD 패널)
const CREAM_DIALOG := Color(0.984, 0.969, 0.933, 0.97)  # 거의 불투명(창)
const AMBER := Color("F9B233")
const STEEL := Color("8C9AB0")
const INK := Color(0.16, 0.18, 0.24)
const OUTLINE := Color(0.16, 0.18, 0.24, 0.9)
const GRADE_COLORS := Art.GRADE_COLORS  # 스펙 §3.1. 값은 Art 한 곳에만 둔다
const PRESS_SHIFT := 2.0  # 눌린 버튼 내용이 아래로 내려가는 px
const BUTTON_PAD_V := 2.0  # 버튼 내용 위·아래 여백. 눌림은 위 + PRESS_SHIFT, 아래 − PRESS_SHIFT(음수는 "기본값"이라 쓰지 않는다)
const CARD_OUTLINE_W := 2.0
const CARD_GEM_R := 12.0  # 카드 위쪽 가운데 등급 보석

static var _cache := {}


## 패널 박스. 내용 여백 margin px.
static func panel(color: Color, chamfer := 10.0, margin := 12, facet := 0.06) -> StyleBox:
	var key := ["p", color, chamfer, margin, facet]
	if not _cache.has(key):
		var b := LowpolyBox.new()
		b.color = color
		b.chamfer = chamfer
		b.facet = facet
		b.seed = hash(color) & 0xffff
		b.set_content_margin_all(margin)
		_cache[key] = b
	return _cache[key]


## 버튼 상태 4종 {normal, hover, pressed, disabled}. pressed는 어둡게 + 내용 2px 아래, disabled는 채도를 뺀다.
## 내용 위·아래 여백 합은 네 상태가 같다(버튼 크기가 상태마다 같고, 가운데 맞춤 글자가 눌림에서 PRESS_SHIFT만큼 내려간다).
static func button_styles(color: Color, chamfer := 12.0) -> Dictionary:
	var key := ["b", color, chamfer]
	if not _cache.has(key):
		var dis := color.lerp(Color(0.6, 0.62, 0.66, color.a), 0.85)
		var st := {"normal": color, "hover": color.lightened(0.12), "pressed": color.darkened(0.15), "disabled": dis}
		var out := {}
		for k in st:
			var b := LowpolyBox.new()
			b.color = st[k]
			b.chamfer = chamfer
			b.facet = 0.07
			b.seed = 7  # 같은 버튼의 상태끼리 면 모양이 같다
			if k == "disabled":
				b.border_color = Color(OUTLINE, 0.5)
			var down := PRESS_SHIFT if k == "pressed" else 0.0
			b.content_margin_top = BUTTON_PAD_V + down
			b.content_margin_bottom = BUTTON_PAD_V - down
			out[k] = b
		_cache[key] = out
	return _cache[key]


## Button에 4상태 박스 + 흰 글자색을 적용한다. focus는 비운다.
static func apply_button(btn: Button, color: Color, chamfer := 12.0) -> void:
	var st := button_styles(color, chamfer)
	for k in st:
		btn.add_theme_stylebox_override(k, st[k])
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		btn.add_theme_color_override(c, Color.WHITE)
	btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.7))
	btn.add_theme_color_override("font_outline_color", Color(INK, 0.85))
	btn.add_theme_constant_override("outline_size", 4)


## 1234567 → "1,234,567"
static func commas(n: int) -> String:
	var s := str(absi(n))
	for i in range(s.length() - 3, 0, -3):
		s = s.insert(i, ",")
	return ("-" if n < 0 else "") + s


## 걸리는·남은 시간(초, 올림): 1시간 미만 "mm:ss", 이상 "h시간 m분"(개정 12 §2.5 — 건물 창·건설 막대).
static func duration(sec: float) -> String:
	var s := maxi(0, ceili(sec))
	if s < 3600:
		return "%02d:%02d" % [s / 60, s % 60]
	return "%d시간 %d분" % [s / 3600, s % 3600 / 60]


## 바 박스 {background, fill}. 채움도 면 분할(4px 깎기).
static func bar(fill_color: Color) -> Dictionary:
	var key := ["r", fill_color]
	if not _cache.has(key):
		var bg := LowpolyBox.new()
		bg.color = Color(0, 0, 0, 0.14)
		bg.chamfer = 4.0
		bg.facet = 0.05
		bg.border_width = 1.5
		bg.border_color = Color(OUTLINE, 0.55)
		var fill := LowpolyBox.new()
		fill.color = fill_color
		fill.chamfer = 4.0
		fill.facet = 0.08
		fill.seed = 11
		fill.border_width = 1.5
		_cache[key] = {"background": bg, "fill": fill}
	return _cache[key]


static func apply_bar(pb: ProgressBar, fill_color: Color) -> void:
	var b := bar(fill_color)
	pb.add_theme_stylebox_override("background", b.background)
	pb.add_theme_stylebox_override("fill", b.fill)


## 등급 보석 배지: center 중심 반지름 r의 n각 보석(부채꼴 면, 왼위가 밝다) + 외곽선. ci는 _draw 중인 CanvasItem.
static func draw_gem(ci: CanvasItem, center: Vector2, r: float, color: Color, sides := 6) -> void:
	var g := gem_geometry(center, r, color, sides)
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), PackedInt32Array(), g[0], g[1])
	ci.draw_polyline(g[2], OUTLINE, gem_outline_width(r), true)


static func gem_outline_width(r: float) -> float:
	return maxf(1.0, r / 7.0)


## 보석 지오메트리 [삼각형 점(3개씩), 점마다 색, 닫힌 외곽선].
static func gem_geometry(center: Vector2, r: float, color: Color, sides := 6) -> Array:
	var ring := PackedVector2Array()
	for i in sides:
		ring.append(center + Vector2.from_angle(-PI / 2.0 + TAU * i / sides) * r)
	var tip := center + Vector2(-r * 0.12, -r * 0.12)  # 살짝 비튼 중심
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in sides:
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % sides]
		var mid := (a + b) * 0.5 - center
		var light := (-mid.x - mid.y) / (r * 1.4)  # 왼위 +, 오른아래 -
		var d := 0.22 * light + 0.06 * (LowpolyBox.hash01(sides, i) - 0.5)
		var col := color.lightened(d) if d >= 0.0 else color.darkened(-d)
		for p in [tip, a, b]:
			pts.append(p)
			cols.append(col)
	var line := ring.duplicate()
	line.append(ring[0])
	return [pts, cols, line]


## 영웅 카드: 등급 색 테두리(두꺼움) + inner_color 면 분할 안쪽 + 위쪽 가운데 등급 보석(grade_color).
## 카드 안쪽 내용(이름·별)은 호출한 쪽이 rect 안에 그린다.
static func draw_facet_card(ci: CanvasItem, rect: Rect2, grade_color: Color, inner_color: Color) -> void:
	var g := facet_card_geometry(rect, grade_color, inner_color)
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), PackedInt32Array(), g[0], g[1])
	ci.draw_polyline(g[2], OUTLINE, CARD_OUTLINE_W, true)
	draw_gem(ci, card_gem_center(rect), CARD_GEM_R, grade_color, 6)


static func card_gem_center(rect: Rect2) -> Vector2:
	return Vector2(rect.get_center().x, rect.position.y + 4.0)


## 카드 바탕 지오메트리 [삼각형 점(3개씩), 점마다 색, 닫힌 외곽선]: 등급 색 8각(부채꼴) 위에 inner_color 면 분할. 보석은 따로.
static func facet_card_geometry(rect: Rect2, grade_color: Color, inner_color: Color) -> Array:
	var outer := LowpolyBox.octagon(rect, 10.0)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var edge := grade_color.darkened(0.1)
	for i in range(1, 7):  # 8각형 부채꼴 6삼각형
		for p in [outer[0], outer[i], outer[i + 1]]:
			pts.append(p)
			cols.append(edge)
	for f in LowpolyBox.faces(rect.grow(-5.0), 7.0, inner_color, 0.05, hash(grade_color) & 0xffff):
		for p in f[0]:
			pts.append(p)
			cols.append(f[1])
	var line := outer.duplicate()
	line.append(outer[0])
	return [pts, cols, line]

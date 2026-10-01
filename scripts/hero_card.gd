extends Button
## 영웅 카드(스펙 §5): 등급 색 테두리 로우폴리 카드 + 위쪽 등급 보석 + 고유 색 6각 + 이름·칭호 + 아래 NEW 또는 별.
## SSR은 금색 면이 반짝인다(면 밝기 순환). hero_id가 ""이면 빈 슬롯 칸. 짧게 누르면 tapped, LONG_PRESS_MS 이상 눌렀다 떼면 long_pressed.
## 입력은 부모로도 넘긴다(MOUSE_FILTER_PASS) — 스크롤 격자 안에서 끌어 스크롤할 수 있게.

const UiKit := preload("res://scripts/ui_kit.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const GameData := preload("res://scripts/game_data.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const LONG_PRESS_MS := 500
const SHIMMER_SPEED := 4.0
const STAR_COLOR := Color("F2B233")
const HIGHLIGHT := Color("F9B233")

signal tapped(card)
signal long_pressed(card)

var hero_id := "":
	set(v):
		hero_id = v
		set_process(v != "" and GameData.hero(v).get("grade", "") == "SSR")  # SSR만 매 프레임 다시 그린다
		queue_redraw()
var badge := ""  # 아래 줄 글자("NEW"). 비면 별
var stars := 0
var corner := ""  # 왼위 작은 글자(슬롯 번호)
var highlight := false  # 고른 슬롯·카드: 호박색 테두리
var empty_text := "빈 칸"

var _down_ms := 0
var _t := 0.0


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_PASS
	button_down.connect(func(): _down_ms = Time.get_ticks_msec())
	pressed.connect(_on_pressed)


func _ready() -> void:
	hero_id = hero_id  # _process가 있으면 엔진이 처리를 켠다 — SSR만 켜 둔다


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _on_pressed() -> void:
	if Time.get_ticks_msec() - _down_ms >= LONG_PRESS_MS:
		long_pressed.emit(self)
	else:
		tapped.emit(self)


## 별 = min(copies − 1, hero_max_stars).
static func stars_of(copies: int) -> int:
	return clampi(copies - 1, 0, int(GameData.config_num("hero_max_stars")))


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var h := GameData.hero(hero_id) if hero_id != "" else {}
	if h.is_empty():
		draw_colored_polygon(LowpolyBox.octagon(r.grow(-3.0), 10.0), Color(UiKit.INK, 0.08))
		_outline(r.grow(-3.0), Color(UiKit.INK, 0.35), 2.0)
		_text(empty_text, size.y * 0.55, 18, Color(UiKit.INK, 0.5))
	else:
		var gc: Color = UiKit.GRADE_COLORS[h.grade]
		var ssr: bool = h.grade == "SSR"
		UiKit.draw_facet_card(self, r, gc, UiKit.CREAM.lerp(gc, 0.18) if ssr else UiKit.CREAM)
		if ssr:  # 금색 면이 차례로 밝아진다
			var fs: Array = LowpolyBox.faces(r.grow(-5.0), 7.0, gc, 0.05, hash(gc) & 0xffff)
			for i in fs.size():
				var a := 0.38 * maxf(0.0, sin(_t * SHIMMER_SPEED - i * 0.8))
				if a > 0.01:
					draw_colored_polygon(fs[i][0], Color(gc.lightened(0.45), a))
		UiKit.draw_gem(self, Vector2(size.x / 2.0, size.y * 0.3), size.x * 0.15, Color(h.color), 6)
		var name_size := clampi(roundi(size.x * 0.17), 14, 24)
		_text(h.name, size.y * 0.6, name_size, UiKit.INK)
		_text(h.title, size.y * 0.6 + name_size * 0.95, maxi(11, name_size - 7), UiKit.INK.lightened(0.3))
		if badge != "":
			_text(badge, size.y - 10.0, name_size - 2, Color("D9480F"), true)
		elif stars > 0:
			_draw_stars(Vector2(size.x / 2.0, size.y - 16.0), minf(9.0, size.x / 14.0))
	if corner != "":
		draw_string_outline(FONT, Vector2(9, 22), corner, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.WHITE)
		draw_string(FONT, Vector2(9, 22), corner, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.INK)
	if highlight:
		_outline(r.grow(1.0), HIGHLIGHT, 5.0)


func _outline(r: Rect2, color: Color, width: float) -> void:
	var line := LowpolyBox.octagon(r, 10.0)
	line.append(line[0])
	draw_polyline(line, color, width, true)


## 가운데 정렬 글자(baseline y).
func _text(text: String, y: float, font_size: int, color: Color, outline := false) -> void:
	if outline:
		draw_string_outline(FONT, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, 5, Color.WHITE)
	draw_string(FONT, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, color)


## 별 stars개(각진 5각 별 다각형, 글꼴과 무관).
func _draw_stars(center: Vector2, r: float) -> void:
	var gap := r * 2.1
	var x0 := center.x - gap * (stars - 1) / 2.0
	for s in stars:
		var c := Vector2(x0 + gap * s, center.y)
		var pts := PackedVector2Array()
		for k in 10:
			pts.append(c + Vector2.from_angle(-PI / 2.0 + PI * k / 5.0) * (r if k % 2 == 0 else r * 0.45))
		draw_colored_polygon(pts, STAR_COLOR)
		pts.append(pts[0])
		draw_polyline(pts, UiKit.OUTLINE, 1.2, true)

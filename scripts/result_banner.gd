extends Control
## 승패 리본 배너(2026-10-07 디자인 보강 4번): 결과 창 맨 위 "승리!"·"패배"·"1-5 클리어" 글자를 각진 리본 위에 얹는다.
## 리본 = 가운데 띠(살짝 아치, 위 절반 밝은 면 · 아래 절반 바탕 면, 칸마다 밝기를 조금씩 달리해 깎은 면처럼) + 양 끝 뒤로 접혀 내려간 꼬리(V자 홈)
## + 접힌 자리 어두운 삼각형. 테두리는 그 면 색의 어두운 톤(UI 규칙), 글자는 흰색 + 띠 색 어두운 외곽선(띠 폭에 맞춰 줄어든다).
## tone "win": 금빛 띠, 뒤로 위쪽 반원 빛살이 천천히 돌고 반짝이가 깜박인다. 크게(1.6배) 나타나 튕기며 제자리로.
## tone "lose": 회청색 띠, 빛살 없음, 위에서 떨어져 내려앉는다(꼬리가 더 처진다). tone "info": 회청색, 작은 글자(오류 문구).
## overhang: 리본 가운데를 위로 이만큼 올려 그린다(창 윗변에 걸치게 — 창 안 여백만큼). 높이(custom_minimum_size)는 그만큼 줄어든다.
## play(text, tone): 글자·색을 바꾸고 등장 연출을 처음부터. text만 바꾸면 연출 없이 그대로. 시간은 실제 초(배속·슬로모션과 무관).

const UiKit := preload("res://scripts/ui_kit.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")

const WIN := Color("E0A526")
const LOSE := Color(0.42, 0.47, 0.58)
const ENTER_SEC := 0.42
const RAYS := 9
const SPARKS := 7
const SEGMENTS := 6

var text := "":
	set(v):
		text = v
		queue_redraw()
var tone := "win":
	set(v):
		tone = v
		queue_redraw()
var font_size := 56:
	set(v):
		font_size = v
		queue_redraw()
var band_h := 86.0:
	set(v):
		band_h = v
		_fit_height()
var overhang := 0.0:
	set(v):
		overhang = v
		_fit_height()
var band_w := 440.0  # 띠 최소 폭(글자가 길면 넓어진다, 컨트롤 폭 + 20까지)
var rays := true  # win일 때 빛살(스테이지 라운드 클리어는 보스 라운드만)
var backdrop := false  # 화면 폭 어두운 띠를 리본 뒤에 깐다(밝은 성 화면 위에서 리본·빛살이 묻히지 않게)

var _t := 10.0  # 등장 뒤 실제 초(처음엔 다 끝난 상태)
var _life := 0.0  # 빛살 회전·반짝이(계속 돈다)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit_height()


func _fit_height() -> void:
	custom_minimum_size.y = maxf(0.0, band_h * 1.4 - overhang)
	queue_redraw()


## 글자·색을 바꾸고 등장 연출을 처음부터.
func play(t: String, tn := "win") -> void:
	text = t
	tone = tn
	_t = 0.0
	visible = true
	queue_redraw()


func is_playing() -> bool:
	return _t < ENTER_SEC


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var real := delta / maxf(Engine.time_scale, 0.01)
	_t += real
	_life += real
	queue_redraw()


func band_color() -> Color:
	return WIN if tone == "win" else LOSE


## 지금 그릴 리본 가운데(로컬 px).
func ribbon_center() -> Vector2:
	return Vector2(size.x / 2.0, band_h * 0.5 + band_h * 0.12 - overhang)


func _draw() -> void:
	if text == "":
		return
	var font := get_theme_font("font", "Label")
	var fs := font_size if tone != "info" else mini(font_size, 34)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var hw := clampf(tw * 0.5 + band_h * 0.75, band_w * 0.5, size.x * 0.5 + 10.0)
	while fs > 18 and tw > (hw - band_h * 0.35) * 2.0:  # 띠 안에 들어가게 줄인다
		fs -= 2
		tw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var c := ribbon_center()
	var k := clampf(_t / ENTER_SEC, 0.0, 1.0)
	var alpha := clampf(_t / 0.12, 0.0, 1.0)
	var win := tone == "win"
	var s := 1.0
	var drop := 0.0
	if win:
		s = lerpf(1.6, 1.0, _ease_out_back(k))
	else:
		drop = -46.0 * (1.0 - _ease_out_bounce(k))
	if backdrop:
		_draw_backdrop(c.y, alpha)
	draw_set_transform(c + Vector2(0, drop), 0.0, Vector2(s, s))
	if win and rays:
		_draw_rays(hw, alpha)
	_draw_ribbon(hw, band_color(), alpha, win)
	var ink := band_color().darkened(0.6)
	var pos := Vector2(-tw / 2.0, font.get_ascent(fs) - font.get_height(fs) / 2.0 + 1.0)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(6, fs / 7), Color(ink, alpha))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, alpha))
	if win:
		_draw_sparks(hw, alpha)
	draw_set_transform(Vector2.ZERO)


## 띠 + 꼬리 + 접힌 자리(리본 가운데가 원점).
func _draw_ribbon(hw: float, col: Color, a: float, win: bool) -> void:
	var h := band_h
	var d := h * (0.26 if win else 0.36)  # 꼬리가 내려간 만큼(지면 더 처진다)
	var tail := h * 0.95
	var line := col.darkened(0.45)
	line.a = a
	for sd in [-1.0, 1.0]:
		var x0: float = sd * hw
		var x1: float = sd * (hw + tail)
		var notch: float = sd * (hw + tail * 0.62)
		var poly := PackedVector2Array([Vector2(x0, -h / 2.0 + d), Vector2(x1, -h / 2.0 + d), Vector2(notch, d), Vector2(x1, h / 2.0 + d), Vector2(x0, h / 2.0 + d)])
		draw_colored_polygon(poly, Color(col.darkened(0.22), a))
		var lit := PackedVector2Array([Vector2(x0, -h / 2.0 + d), Vector2(x1, -h / 2.0 + d), Vector2(lerpf(x1, notch, 0.5), -h / 4.0 + d), Vector2(x0, -h / 4.0 + d)])
		draw_colored_polygon(lit, Color(col.darkened(0.1), a))  # 꼬리 윗면 조금 밝게
		poly.append(poly[0])
		draw_polyline(poly, line, 3.0, true)
		var fold := PackedVector2Array([Vector2(x0 - sd * d, h / 2.0), Vector2(x0, h / 2.0 + d), Vector2(x0, h / 2.0)])
		draw_colored_polygon(fold, Color(col.darkened(0.5), a))
		fold.append(fold[0])
		draw_polyline(fold, line, 2.0, true)
	var arch := h * (0.12 if win else 0.04)
	var top := PackedVector2Array()
	var mid := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in SEGMENTS + 1:
		var x := lerpf(-hw, hw, float(i) / SEGMENTS)
		var lift := arch * (1.0 - pow(x / hw, 2.0))
		top.append(Vector2(x, -h / 2.0 - lift))
		mid.append(Vector2(x, -lift))
		bot.append(Vector2(x, h / 2.0 - lift))
	for i in SEGMENTS:
		var j := 0.04 * (1.0 if i % 2 == 0 else -1.0)
		draw_colored_polygon(PackedVector2Array([top[i], top[i + 1], mid[i + 1], mid[i]]), Color(col.lightened(0.18 + j), a))
		draw_colored_polygon(PackedVector2Array([mid[i], mid[i + 1], bot[i + 1], bot[i]]), Color(col.darkened(0.04 - j), a))
	var trim := PackedVector2Array()  # 띠 위·아래 안쪽 바느질 선
	var trim2 := PackedVector2Array()
	for i in SEGMENTS + 1:
		trim.append(top[i] + Vector2(0, 7))
		trim2.append(bot[i] - Vector2(0, 7))
	draw_polyline(trim, Color(col.lightened(0.45), a * 0.8), 2.0, true)
	draw_polyline(trim2, Color(col.darkened(0.25), a * 0.8), 2.0, true)
	var outline := top.duplicate()
	var rb := bot.duplicate()
	rb.reverse()
	outline.append_array(rb)
	outline.append(outline[0])
	draw_polyline(outline, line, 3.5, true)


## 화면 폭 어두운 띠(가운데 진하고 위아래로 옅어진다). 리본 가운데 높이 cy.
func _draw_backdrop(cy: float, a: float) -> void:
	var half := band_h * 1.5
	var x0 := -size.x  # 넉넉히(화면 밖은 안 보인다)
	var x1 := size.x * 2.0
	var dark := Color(0.06, 0.07, 0.12, 0.55 * a)
	var none := Color(dark, 0.0)
	draw_polygon(PackedVector2Array([Vector2(x0, cy - half), Vector2(x1, cy - half), Vector2(x1, cy), Vector2(x0, cy)]), PackedColorArray([none, none, dark, dark]))
	draw_polygon(PackedVector2Array([Vector2(x0, cy), Vector2(x1, cy), Vector2(x1, cy + half), Vector2(x0, cy + half)]), PackedColorArray([dark, dark, none, none]))


## 리본 뒤 위쪽 반원 빛살(천천히 돈다). 가운데 진하고 끝으로 갈수록 투명.
func _draw_rays(hw: float, a: float) -> void:
	var r0 := band_h * 0.4
	var r1 := hw + band_h * 1.6
	var glow := Color(1.0, 0.92, 0.6, 0.42 * a)
	var clear := Color(1.0, 0.92, 0.6, 0.0)
	var spin := _life * 0.25
	for i in RAYS:
		var ang := lerpf(PI * 1.06, PI * 1.94, (float(i) + 0.5) / RAYS) + sin(spin + i) * 0.05
		var w := 0.07 + 0.03 * LowpolyBox.hash01(i, 3)
		var p0 := Vector2.from_angle(ang) * r0
		var pa := Vector2.from_angle(ang - w) * r1
		var pb := Vector2.from_angle(ang + w) * r1
		draw_polygon(PackedVector2Array([p0, pa, pb]), PackedColorArray([glow, clear, clear]))


## 리본 둘레 네 갈래 반짝이(따로 깜박인다).
func _draw_sparks(hw: float, a: float) -> void:
	for i in SPARKS:
		var u := LowpolyBox.hash01(i, 11) * 2.0 - 1.0
		var side := 1.0 if i % 2 == 0 else -1.0
		var p := Vector2(u * (hw + band_h * 0.6), side * band_h * (0.62 + 0.25 * LowpolyBox.hash01(i, 13)))
		var tw := maxf(0.0, sin(_life * 3.2 + i * 1.9))
		var r := 4.0 + 7.0 * tw
		if r < 5.0:
			continue
		var col := Color(1, 1, 0.85, a * tw)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r * 0.25, -r * 0.25), p + Vector2(r, 0), p + Vector2(r * 0.25, r * 0.25),
			p + Vector2(0, r), p + Vector2(-r * 0.25, r * 0.25), p + Vector2(-r, 0), p + Vector2(-r * 0.25, -r * 0.25)]), col)


static func _ease_out_back(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)


static func _ease_out_bounce(x: float) -> float:
	if x < 1.0 / 2.75:
		return 7.5625 * x * x
	if x < 2.0 / 2.75:
		x -= 1.5 / 2.75
		return 7.5625 * x * x + 0.75
	if x < 2.5 / 2.75:
		x -= 2.25 / 2.75
		return 7.5625 * x * x + 0.9375
	x -= 2.625 / 2.75
	return 7.5625 * x * x + 0.984375

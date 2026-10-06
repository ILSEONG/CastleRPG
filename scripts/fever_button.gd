extends Button
## FEVER 버튼(개정 14 §3): 각진 불꽃 + 아래서 위로 차오르는 빨간 면 게이지 + 퍼센트. 가득 차면 불꽃 일렁임·테두리 맥동·불씨·"FEVER!".
## FEVER 중엔 남은 시간과 계속 타는 불꽃, 화면 가장자리 붉은 빛, 시작 때 가운데 "FEVER!" 큰 글자. 상태는 오토로드 Fever.
## FEVER는 방치 스폰 배속이라 방치(대기) 때만 켤 수 있다. 스테이지 진행 중(스테이지·결과·카운트다운)엔 흐리게 두고 탭은 알림만.

const UiKit := preload("res://scripts/ui_kit.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")

const SIZE := Vector2(64, 64)
const BASE := Color(0.30, 0.12, 0.12)
const RED := Color(0.86, 0.14, 0.10)
const INK := Color(0.16, 0.18, 0.24)
const FIRE_OUT := Color(0.92, 0.22, 0.10)
const FIRE_MID := Color(1.0, 0.55, 0.12)
const FIRE_IN := Color(1.0, 0.88, 0.25)
const BANNER_SEC := 0.8
# 단위 좌표(-0.5..0.5) 불꽃 윤곽. 0·1·7번은 위쪽 꼭짓점이라 일렁인다.
const FLAME := [Vector2(0, -0.5), Vector2(0.2, -0.2), Vector2(0.38, 0.05), Vector2(0.3, 0.38), Vector2(0, 0.5), Vector2(-0.3, 0.38), Vector2(-0.38, 0.05), Vector2(-0.2, -0.2)]

var banner_left := 0.0  # 시작 "FEVER!" 큰 글자 남은 초
var _t := 0.0
var _edge: Control
var _banner: Label


func _ready() -> void:
	custom_minimum_size = SIZE
	focus_mode = Control.FOCUS_NONE
	UiKit.apply_button(self, BASE, 10.0)
	pressed.connect(_on_pressed)
	var layer := CanvasLayer.new()
	add_child(layer)
	_edge = Control.new()
	_edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.draw.connect(_draw_edge)
	layer.add_child(_edge)
	_banner = Label.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.text = "FEVER!"
	_banner.add_theme_font_size_override("font_size", 96)
	_banner.add_theme_color_override("font_color", FIRE_MID)
	_banner.add_theme_color_override("font_outline_color", Color(0.45, 0.06, 0.04))
	_banner.add_theme_constant_override("outline_size", 20)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	layer.add_child(_banner)


func _process(delta: float) -> void:
	_t += delta
	if banner_left > 0.0:
		banner_left -= delta
		_banner.modulate.a = clampf(banner_left / 0.3, 0.0, 1.0)
	_banner.visible = banner_left > 0.0
	_edge.visible = Fever.active()
	if _edge.visible:
		_edge.queue_redraw()
	modulate.a = 0.45 if blocked() and not Fever.active() else 1.0
	queue_redraw()


## 스테이지를 밀고 있는 동안(방치가 아닐 때)은 FEVER를 켤 수 없다.
func blocked() -> bool:
	return GameState.mode != GameState.Mode.IDLE


func _on_pressed() -> void:
	if Fever.active():
		return
	if blocked():
		Economy.notice.emit("스테이지 진행 중엔 FEVER를 쓸 수 없습니다")
		return
	if Fever.start():
		banner_left = BANNER_SEC
	else:
		Economy.notice.emit("몬스터 %d마리 더" % (Fever.kills_needed() - Fever.gauge))


## 버튼 글자: FEVER 중 남은 시간 "2:59", 가득 "FEVER!", 아니면 "73%".
func label_text() -> String:
	if Fever.active():
		return "%d:%02d" % [ceili(Fever.left) / 60, ceili(Fever.left) % 60]
	return "FEVER!" if Fever.full() else "%d%%" % floori(Fever.ratio() * 100.0)


## 버튼에 올라가는 내용: 게이지 면, 불꽃, 글자, 가득/FEVER 중 효과.
func _draw() -> void:
	var hot: bool = (Fever.full() and not blocked()) or Fever.active()
	var inner := Rect2(Vector2.ZERO, size).grow(-6.0)
	if not Fever.active():
		var h := inner.size.y * Fever.ratio()
		if h > 0.5:
			var a := Vector2(inner.position.x, inner.end.y - h)
			var b := Vector2(inner.end.x, inner.end.y - h)
			var c := inner.end
			var d := Vector2(inner.position.x, inner.end.y)
			draw_colored_polygon(PackedVector2Array([a, b, d]), RED.lightened(0.1))  # 두 면: 위쪽 밝게, 아래쪽 어둡게
			draw_colored_polygon(PackedVector2Array([b, c, d]), RED.darkened(0.2))
	if hot:
		var pulse := 0.5 + 0.5 * sin(_t * 7.0)
		var pts := LowpolyBox.octagon(Rect2(Vector2.ZERO, size).grow(-1.5), 10.0)
		pts.append(pts[0])
		draw_polyline(pts, Color(1.0, 0.6, 0.15, 0.45 + 0.55 * pulse), 3.0)
		for i in 5:  # 불씨 삼각형이 위로 떠오르며 사라진다
			var ph := fposmod(_t * 0.8 + i * 0.2, 1.0)
			var p := Vector2(size.x * 0.5 + sin(i * 2.3) * 18.0, size.y - 14.0 - ph * (size.y - 18.0))
			var r := 3.5 * (1.0 - ph) + 1.0
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, r), p + Vector2(-r, r)]), Color(FIRE_IN, 1.0 - ph))
	_draw_flame(Vector2(size.x * 0.5, 24.0), 36.0, hot)
	var text := label_text()
	var font := get_theme_default_font()
	var fs := 15
	var pos := Vector2(0, size.y - 9.0)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, 5, Color(INK, 0.9))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color.WHITE)


## 각진 불꽃: 바깥(빨강) 두 면 + 가운데(주황) + 안쪽(노랑). hot이면 위쪽 꼭짓점이 사인으로 일렁인다.
func _draw_flame(center: Vector2, px: float, hot: bool) -> void:
	var amp := 0.05 if hot else 0.0
	var pts := PackedVector2Array()
	for i in FLAME.size():
		var p: Vector2 = FLAME[i]
		if i in [0, 1, 7]:
			p.x += sin(_t * 9.0 + i * 1.7) * amp * 2.0
			p.y += sin(_t * 6.0 + i) * amp
		pts.append(center + p * px)
	var mid := center + Vector2(0, 0.1) * px
	draw_colored_polygon(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[4], mid]), FIRE_OUT.lightened(0.08))  # 오른쪽 면
	draw_colored_polygon(PackedVector2Array([pts[0], mid, pts[4], pts[5], pts[6], pts[7]]), FIRE_OUT.darkened(0.12))  # 왼쪽 면
	draw_colored_polygon(PackedVector2Array([center + Vector2(0.02, -0.28) * px, center + Vector2(0.2, 0.08) * px, center + Vector2(0.14, 0.34) * px,
		center + Vector2(-0.14, 0.34) * px, center + Vector2(-0.2, 0.08) * px]), FIRE_MID)
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -0.05) * px, center + Vector2(0.11, 0.2) * px, center + Vector2(0, 0.36) * px,
		center + Vector2(-0.11, 0.2) * px]), FIRE_IN)
	pts.append(pts[0])
	draw_polyline(pts, Color(INK, 0.8), 1.5)


## FEVER 중 화면 가장자리의 얇은 붉은 면 띠(맥동).
func _draw_edge() -> void:
	var s := _edge.size
	var w := 26.0 + 8.0 * sin(_t * 4.0)
	var c := Color(0.95, 0.12, 0.06, 0.28 + 0.12 * sin(_t * 4.0))
	var clear := Color(c, 0.0)
	var cols := PackedColorArray([c, c, clear, clear])
	_edge.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x - w, w), Vector2(w, w)]), cols)
	_edge.draw_polygon(PackedVector2Array([Vector2(0, s.y), Vector2(s.x, s.y), Vector2(s.x - w, s.y - w), Vector2(w, s.y - w)]), cols)
	_edge.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(0, s.y), Vector2(w, s.y - w), Vector2(w, w)]), cols)
	_edge.draw_polygon(PackedVector2Array([Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(s.x - w, s.y - w), Vector2(s.x - w, w)]), cols)

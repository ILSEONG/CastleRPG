extends Control
## 로딩 스피너(사용자 2026-11-05 "인게임 내에서 로딩이 걸리는 부분은 스피너처리를 해"): 원신·리니지M·RoK처럼 서버를 기다리는 동안 도는 고리.
## 두 가지로 쓴다.
## 1) Spinner.mark(label): 창 안의 「불러오는 중…」 같은 안내 글 바로 왼쪽에 작은 고리를 붙인다. 붙일 때의 글과 같은 동안만 보이고 돈다
##    (같은 라벨이 결과 글로 바뀌면 저절로 숨는다).
## 2) 화면 가운데 고리(busy_spinner.gd): 버튼을 누르고 서버 답을 기다려야 화면이 넘어가는 곳(던전 입장·길드 가입/창설/보스·길드전·결제 확인·
##    거래소 목록). Spinner.hold(key, true/false)로 직접 걸 수도 있다. 짧은 기다림(0.25초 미만)은 깜빡이지 않게 띄우지 않는다.
## 고리는 흰 몸 + 진한 테두리(밝은 바닥에서도 보인다, 금색 없음). 실제 시간으로 돈다(배속·히트스톱과 무관).

const UiKit := preload("res://scripts/ui_kit.gd")

const TURN_SEC := 0.9  # 한 바퀴
const ARC := 0.72  # 고리 길이(바퀴 비율)
const GAP := 8.0  # 글과의 사이

static var _holds := {}  # key → 건 실제 시각(초)

var ring_color := Color(1, 1, 1, 0.95)
var ink := Color(UiKit.INK, 0.85)
var watch: Label  # mark: 이 라벨의 글이 want와 같을 때만
var want := ""
var also: Array = []  # mark(label, px, more): 이 글들일 때도 보인다


## 가운데 고리를 건다/푼다(같은 key는 한 번만 센다).
static func hold(key: String, on: bool) -> void:
	if on:
		if not _holds.has(key):
			_holds[key] = Time.get_ticks_msec() / 1000.0
	else:
		_holds.erase(key)


## 걸린 것 중 가장 오래된 것이 걸린 지 몇 초인가(없으면 -1).
static func held_for() -> float:
	if _holds.is_empty():
		return -1.0
	var now := Time.get_ticks_msec() / 1000.0
	for k in _holds.keys():  # 답이 끝내 안 온 것(창을 닫았다 등)은 15초 뒤 놓는다
		if now - float(_holds[k]) > 15.0:
			_holds.erase(k)
	if _holds.is_empty():
		return -1.0
	var oldest := now
	for k in _holds:
		oldest = minf(oldest, float(_holds[k]))
	return now - oldest


## 라벨 왼쪽에 작은 고리(지름 px, 기본은 글 크기쯤). 같은 라벨에 두 번 붙이지 않는다. 고리를 돌려준다.
static func mark(label: Label, px := 0.0, more: Array = []) -> Control:
	if label == null:
		return null
	for c in label.get_children():
		if c.get_script() == load("res://scripts/spinner.gd"):
			c.want = label.text
			return c
	var s = load("res://scripts/spinner.gd").new()
	var fs := label.get_theme_font_size("font_size")
	var d := px if px > 0.0 else clampf(fs * 1.1, 18.0, 40.0)
	s.size = Vector2(d, d)
	s.custom_minimum_size = Vector2.ZERO
	s.watch = label
	s.want = label.text
	s.also = more
	s.ring_color = label.get_theme_color("font_color")
	s.ring_color.a = maxf(s.ring_color.a, 0.9)
	label.add_child(s)
	return s


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if watch != null:
		top_level = false
		set_anchors_preset(Control.PRESET_TOP_LEFT)


func _process(_delta: float) -> void:
	if watch != null:
		if not is_instance_valid(watch):
			queue_free()
			return
		visible = (watch.text == want or also.has(watch.text)) and watch.is_visible_in_tree()
		if not visible:
			return
		_place_by_label()
	if is_visible_in_tree():
		queue_redraw()


## 라벨 글 바로 왼쪽, 세로 가운데. 가운데 정렬이면 글 폭만큼 안쪽에서 시작한다(글은 그대로, 고리는 그 왼쪽 여백에).
func _place_by_label() -> void:
	var font := watch.get_theme_font("font")
	var fs := watch.get_theme_font_size("font_size")
	var w := watch.size.x
	var lines := watch.get_line_count()
	var tw := font.get_string_size(watch.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if lines <= 1 else w
	tw = minf(tw, w)
	var x0 := 0.0
	match watch.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_FILL:
			x0 = (w - tw) / 2.0
		HORIZONTAL_ALIGNMENT_RIGHT:
			x0 = w - tw
	var x := x0 - GAP - size.x
	if x < 0.0:  # 왼쪽에 자리가 없으면(글이 꽉 찬 줄) 글 위 가운데
		position = Vector2((w - size.x) / 2.0, -size.y - 4.0)
	else:
		position = Vector2(x, (watch.size.y - size.y) / 2.0)


func _draw() -> void:
	var r := minf(size.x, size.y) / 2.0
	var c := size / 2.0
	var th := maxf(3.0, r * 0.26)
	var t := float(Time.get_ticks_msec() % int(TURN_SEC * 1000.0)) / (TURN_SEC * 1000.0)
	var a0 := t * TAU
	# 숨 쉬듯 늘었다 줄어드는 고리(머티리얼·스피너 흔한 모양)
	var arc := TAU * (ARC * (0.75 + 0.25 * sin(t * TAU)))
	var pts := 28
	draw_arc(c, r - th / 2.0, 0.0, TAU, 40, Color(ink, 0.25), th, true)  # 옅은 바탕 고리
	draw_arc(c, r - th / 2.0, a0, a0 + arc, pts, ink, th + 3.0, true)
	draw_arc(c, r - th / 2.0, a0, a0 + arc, pts, ring_color, th, true)
	var head := c + Vector2.from_angle(a0 + arc) * (r - th / 2.0)
	draw_circle(head, th * 0.75, ring_color)

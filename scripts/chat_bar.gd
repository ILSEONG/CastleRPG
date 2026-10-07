extends CanvasLayer
## 성 화면 채팅 줄(사용자 2026-10-07): x1.5 배속 버튼 오른쪽, 그 버튼과 아래 끝을 맞춘 반투명 줄 하나(배속 버튼이 [메뉴]와 같은 높이라 이 줄도 같은 높이). 가장 최근 메시지
## "[전체] 닉네임: 내용"을 한 줄로 보이고, 누르면 채팅 창(chat_panel.gd)이 열린다. 배속 버튼이 탭 바·초상화 줄·튜토리얼 카드 위로
## 올라가면 같이 올라간다(매 프레임 맞춘다). 오른쪽 끝은 오른쪽 아래 [메뉴] 버튼보다 왼쪽에서 멈춘다. 오프라인이면 숨는다.

const UiKit := preload("res://scripts/ui_kit.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const HEIGHT := 56.0
const GAP := 12.0  # 배속 버튼과 사이
const RIGHT := 128.0  # 화면 오른쪽 끝에서 이만큼 비운다([메뉴] 버튼 자리)
const BG := Color(0.12, 0.14, 0.20, 0.62)
const CH_NAMES := {"all": "전체", "guild": "길드"}
const CH_COLORS := {"all": Color(0.98, 0.80, 0.42), "guild": Color(0.56, 0.86, 0.56)}

var speed  # speed_button.gd(그 오른쪽, 아래 끝 맞춤)
var panel  # chat_panel.gd
var button: Button
var _face: Control


func _ready() -> void:
	layer = 1  # HUD와 같은 층(창은 2 이상이 덮는다)
	button = Button.new()
	button.focus_mode = Control.FOCUS_NONE
	var box := UiKit.panel(BG, 12.0, 8)
	for s in ["normal", "hover", "focus"]:
		button.add_theme_stylebox_override(s, box)
	button.add_theme_stylebox_override("pressed", UiKit.panel(Color(BG, 0.8), 12.0, 8))
	button.pressed.connect(_open)
	_face = Control.new()
	_face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.clip_contents = true
	_face.draw.connect(_draw_face)
	button.add_child(_face)
	add_child(button)
	Chat.changed.connect(_face.queue_redraw)
	_place()


func _open() -> void:
	if panel != null:
		panel.open()


func _process(_delta: float) -> void:
	button.visible = Chat.online()
	_place()


func _place() -> void:
	var vp := get_viewport().get_visible_rect().size
	var left := 16.0
	var bottom := vp.y * 0.70 + 42.0
	if speed != null and speed.button != null:
		left = speed.button.position.x + speed.button.size.x + GAP
		bottom = speed.button.position.y + speed.button.size.y
	var w := maxf(vp.x - RIGHT - left, 160.0)
	var r := Rect2(Vector2(left, bottom - HEIGHT), Vector2(w, HEIGHT))
	if button.position != r.position or button.size != r.size:
		button.position = r.position
		button.size = r.size
		_face.queue_redraw()


func _draw_face() -> void:
	var sz := _face.size
	var cy := sz.y / 2.0
	# 말풍선 아이콘
	var c := Vector2(28, cy - 2)
	_face.draw_circle(c, 15.0, Color(1, 1, 1, 0.92))
	_face.draw_colored_polygon(PackedVector2Array([c + Vector2(-9, 9), c + Vector2(-15, 19), c + Vector2(1, 13)]), Color(1, 1, 1, 0.92))
	for k in 3:
		_face.draw_circle(c + Vector2(-7 + k * 7, 0), 2.4, Color(BG, 1.0))
	var x := 54.0
	var room := sz.x - x - 10.0
	var m := Chat.latest()
	if m.is_empty():
		_face.draw_string(FONT, Vector2(x, cy + 8), "채팅", HORIZONTAL_ALIGNMENT_LEFT, room, 22, Color(1, 1, 1, 0.8))
		return
	var tag := "[%s]" % CH_NAMES.get(m.ch, "")
	_face.draw_string(FONT, Vector2(x, cy + 8), tag, HORIZONTAL_ALIGNMENT_LEFT, room, 20, CH_COLORS.get(m.ch, Color.WHITE))
	x += FONT.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 6.0
	var line := "%s: %s" % [m.name, m.text]
	var fit := _ellipsize(line, sz.x - x - 10.0, 21)
	_face.draw_string(FONT, Vector2(x, cy + 8), fit, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color.WHITE)


## 너비를 넘으면 뒤를 자르고 "…"를 붙인다.
static func _ellipsize(s: String, width: float, size: int) -> String:
	if width <= 0.0:
		return ""
	if FONT.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
		return s
	var lo := 0
	var hi := s.length()
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if FONT.get_string_size(s.substr(0, mid) + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
			lo = mid
		else:
			hi = mid - 1
	return s.substr(0, lo) + "…"

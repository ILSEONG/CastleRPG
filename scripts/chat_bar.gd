extends CanvasLayer
## 성 화면 미니 채팅(2026-10-13, 사용자: 제우스: 오만의 신 같은 채팅 UX, 두루마리 컨셉 유지): 국산 MMORPG식 — 왼쪽 아래 반투명 양피지 상자에
## 최근 LINES줄 "시:분 [전체] 닉네임: 내용"(먹색 글씨, 채널 머리표 색: 전체 갈색·길드 초록·시스템 주황, 내 이름 금갈색). 누르면 채팅 창(chat_panel.gd)이 왼쪽에서 열린다.
## 자리: x1.5 배속 버튼 오른쪽, 아래 끝은 그 버튼(= [메뉴])과 맞추고 위로 자란다. 배속 버튼이 탭 바·초상화 줄·가이드 카드 위로
## 올라가면 같이 올라간다(매 프레임 맞춘다). 오른쪽 끝은 [메뉴] 버튼보다 왼쪽에서 멈춘다. 오프라인이면 숨는다.

const Lang := preload("res://scripts/lang.gd")

const UiKit := preload("res://scripts/ui_kit.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const LINES := 3
const LINE_H := 28.0
const PAD := 8.0
const HEIGHT := LINES * LINE_H + PAD * 2.0
const FONT_SIZE := 19
const GAP := 12.0  # 배속 버튼과 사이
const RIGHT := 128.0  # 화면 오른쪽 끝에서 이만큼 비운다([메뉴] 버튼 자리)
const BG := Color(0.953, 0.886, 0.737, 0.86)  # 양피지(ScrollBox.PAPER) 반투명
static var CH_NAMES := {"all": Lang.t("chat_bar.ch_names.all"), "guild": Lang.t("chat_bar.ch_names.guild"), "system": Lang.t("chat_bar.ch_names.system")}
const ChatPanel := preload("res://scripts/chat_panel.gd")
const CH_COLORS := ChatPanel.CH_COLORS
const NAME_COLOR := ChatPanel.NAME_COLOR
const ME_COLOR := ChatPanel.ME_COLOR
const TEXT_COLOR := ChatPanel.TEXT
const TIME_COLOR := ChatPanel.SUB
const TIME_SIZE := 16

var speed  # speed_button.gd(그 오른쪽, 아래 끝 맞춤)
var panel  # chat_panel.gd
var button: Button
var _face: Control


func _ready() -> void:
	layer = 1  # HUD와 같은 층(창은 2 이상이 덮는다)
	button = Button.new()
	button.focus_mode = Control.FOCUS_NONE
	var box := UiKit.panel(BG, 10.0, 8, 0.03)
	for s in ["normal", "hover", "focus"]:
		button.add_theme_stylebox_override(s, box)
	button.add_theme_stylebox_override("pressed", UiKit.panel(BG.darkened(0.12), 10.0, 8, 0.03))
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
	# 왼쪽 위 작은 말풍선
	var c := Vector2(20, PAD + LINE_H / 2.0)
	var ic := Color(0.48, 0.34, 0.18)  # 말풍선(갈색)
	_face.draw_circle(c, 10.0, ic)
	_face.draw_colored_polygon(PackedVector2Array([c + Vector2(-6, 6), c + Vector2(-10, 13), c + Vector2(1, 9)]), ic)
	for k in 3:
		_face.draw_circle(c + Vector2(-4.5 + k * 4.5, 0), 1.6, Color(BG, 1.0))
	var x0 := 38.0
	var lines: Array = Chat.recent(LINES)
	if lines.is_empty():
		_face.draw_string(FONT, Vector2(x0, PAD + LINE_H - 8), Lang.t("chat_bar.draw_face"), HORIZONTAL_ALIGNMENT_LEFT, sz.x - x0 - 8, FONT_SIZE, TIME_COLOR)
		return
	var row0 := LINES - lines.size()  # 줄이 모자라면 아래부터 채운다
	for k in lines.size():
		_draw_line(lines[k], x0, PAD + (row0 + k + 1) * LINE_H - 8.0, sz.x - 8.0)


## 한 줄: 시:분 [채널] 이름: 내용(넘치면 …). 시스템 줄은 이름 없이 주황 글씨, 안내 줄은 시각 없이.
func _draw_line(m: Dictionary, x: float, y: float, right: float) -> void:
	var hm := ChatPanel.clock(float(m.get("at", 0)))
	if hm != "":
		_face.draw_string(FONT, Vector2(x, y), hm, HORIZONTAL_ALIGNMENT_LEFT, -1, TIME_SIZE, TIME_COLOR)
		x += FONT.get_string_size(hm, HORIZONTAL_ALIGNMENT_LEFT, -1, TIME_SIZE).x + 6.0
	var ch: String = m.get("ch", "all")
	var tag := "[%s]" % CH_NAMES.get(ch, "")
	var tc: Color = CH_COLORS.get(ch, Color.WHITE)
	_outlined(tag, x, y, tc)
	x += FONT.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 5.0
	if ch == "system":
		_outlined(_ellipsize(str(m.text), right - x, FONT_SIZE), x, y, tc)
		return
	var nm := "%s:" % m.name
	_outlined(nm, x, y, ME_COLOR if m.get("me", false) else NAME_COLOR)
	x += FONT.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 5.0
	_outlined(_ellipsize(str(m.text), right - x, FONT_SIZE), x, y, TEXT_COLOR)


func _outlined(t: String, x: float, y: float, col: Color) -> void:
	if t == "":
		return
	_face.draw_string(FONT, Vector2(x, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)


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

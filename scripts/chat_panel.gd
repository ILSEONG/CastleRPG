extends "res://scripts/ui_window.gd"
## 채팅 창(사용자 2026-10-07): 성 화면 채팅 줄(chat_bar.gd)을 누르면 열린다. 하위 탭 [전체][길드](길드는 길드원일 때만).
## 줄 = 닉네임 + 내용(내 줄은 노란 바탕). 아래 입력 칸(최대 100자) + [보내기]. 보내면 내 줄이 바로 보이고, 서버가 거절하면 지우고
## 입력 칸 위에 짧은 알림을 낸다(버튼 글자는 바뀌지 않는다). 상태·폴링은 오토로드 Chat(chat.gd).
## 휴대폰 키보드가 올라오면 창 아래 끝을 키보드 위로 올린다.

const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const SUB := Color(0.16, 0.18, 0.24, 0.62)
const ME_BG := Color(0.98, 0.84, 0.50, 0.9)
const ROW_BG := Color(1, 1, 1, 0.75)
const NAME_COLOR := Color(0.20, 0.36, 0.66)
const ME_NAME_COLOR := Color(0.70, 0.34, 0.06)
const NOTICE_SEC := 2.5
const CLOSE_PX := 56.0

var tab := "all"
var buttons := {}  # 테스트용: "tab:all" "tab:guild" "send" "close"
var input: LineEdit
var list: VBoxContainer
var scroll: ScrollContainer
var notice_label: Label
var _notice_left := 0.0
var _shown := -1  # 마지막으로 그린 줄 수(+탭) 지문 — 바뀌었을 때만 다시 그린다
var _bottom := 0.0  # 키보드가 없을 때 창 아래 오프셋


func _ready() -> void:
	_build_window(0, 10)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(CLOSE_PX, 0)
	head.add_child(pad)
	var title := _title("채팅")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var x := Button.new()
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(CLOSE_PX, CLOSE_PX)
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiKit.apply_button(x, UiKit.STEEL, 10.0)
	x.pressed.connect(close)
	var face := Control.new()
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.draw.connect(func():
		var c := face.size / 2.0
		var r := CLOSE_PX * 0.2
		for d in [Vector2(r, r), Vector2(r, -r)]:
			face.draw_line(c - d, c + d, Color.WHITE, 5.0, true))
	x.add_child(face)
	head.add_child(x)
	buttons["close"] = x
	content.add_child(head)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for t in [["all", "전체"], ["guild", "길드"]]:
		var b := _button(t[1], UiKit.STEEL, 24)
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 54)
		b.pressed.connect(func(): _pick(t[0]))
		tabs.add_child(b)
		buttons["tab:" + t[0]] = b
	content.add_child(tabs)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	notice_label = _label("", 20, Color(0.80, 0.20, 0.16))
	notice_label.modulate.a = 0.0
	content.add_child(notice_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	input = LineEdit.new()
	input.max_length = Chat.MAX_LEN
	input.placeholder_text = "메시지 입력 (최대 %d자)" % Chat.MAX_LEN
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(0, 60)
	input.add_theme_font_size_override("font_size", 24)
	input.add_theme_color_override("font_color", HudScript.INK)
	input.add_theme_color_override("font_placeholder_color", SUB)
	input.add_theme_stylebox_override("normal", UiKit.panel(Color.WHITE, 10.0, 12))
	input.add_theme_stylebox_override("focus", UiKit.panel(Color.WHITE, 10.0, 12))
	input.text_submitted.connect(func(_t): send())
	row.add_child(input)
	var sb := _button("보내기", UiKit.AMBER, 24)
	sb.focus_mode = Control.FOCUS_NONE
	sb.custom_minimum_size = Vector2(120, 60)
	sb.pressed.connect(send)
	row.add_child(sb)
	buttons["send"] = sb
	content.add_child(row)
	_fit_sheet()
	_bottom = dialog.offset_bottom
	Chat.changed.connect(_on_changed)
	Chat.notice.connect(show_notice)


func _fit() -> void:
	_fit_sheet()


func _on_open() -> void:
	if tab == "guild" and not Chat.has_guild:
		tab = "all"
	Chat.set_window_open(true)
	_shown = -1
	_rebuild()


func close() -> void:
	super.close()
	Chat.set_window_open(false)
	input.release_focus()
	DisplayServer.virtual_keyboard_hide()


func _pick(t: String) -> void:
	tab = t
	_shown = -1
	_rebuild()


## [보내기]·엔터: 보냈으면 입력 칸을 비운다(바로 거절이면 그대로 둔다 — 알림만).
func send() -> void:
	if Chat.send(tab, input.text):
		input.text = ""


func show_notice(text: String) -> void:
	notice_label.text = text
	notice_label.modulate.a = 1.0
	_notice_left = NOTICE_SEC


func _process(delta: float) -> void:
	if not visible:
		return
	if _notice_left > 0.0:
		_notice_left -= delta / maxf(Engine.time_scale, 0.01)
		notice_label.modulate.a = clampf(_notice_left / 0.5, 0.0, 1.0)
	# 휴대폰 키보드: 화면 픽셀 → 뷰포트 단위로 바꿔 창 아래 끝을 그 위로
	var kb := float(DisplayServer.virtual_keyboard_get_height()) if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0.0  # 키보드 없는 기기는 매 프레임 경고
	var win := float(DisplayServer.window_get_size().y)
	var lift := 0.0
	if kb > 0.0 and win > 0.0:
		lift = kb * get_viewport().get_visible_rect().size.y / win + 8.0
	dialog.offset_bottom = minf(_bottom, -lift) if lift > 0.0 else _bottom


func _on_changed() -> void:
	if visible:
		_rebuild()


func _rebuild() -> void:
	buttons["tab:guild"].visible = Chat.has_guild
	if tab == "guild" and not Chat.has_guild:
		tab = "all"
	for k in buttons:
		if k.begins_with("tab:"):
			UiKit.apply_button(buttons[k], UiKit.AMBER if k == "tab:" + tab else UiKit.STEEL, 14.0)
	var xs: Array = Chat.messages[tab]
	var stamp := xs.size() * 1000003 + (Chat.last_id(tab) % 1000003) + (7 if tab == "guild" else 0)
	for m in xs:
		if m.get("local", false):
			stamp += int(-m.id) * 31
	if stamp == _shown:
		return
	_shown = stamp
	for c in list.get_children():
		c.queue_free()
	if not Net.is_online():
		list.add_child(_label("채팅은 서버에 접속했을 때 쓸 수 있어요", 24, SUB))
		return
	if xs.is_empty():
		var empty := "아직 메시지가 없어요. 첫 인사를 남겨 보세요!" if tab == "all" else "길드원에게 첫 인사를 남겨 보세요!"
		list.add_child(_label(empty, 24, SUB))
	if tab == "guild" and Chat.guild_name != "":
		list.add_child(_label("길드 " + Chat.guild_name, 20, SUB))
		list.move_child(list.get_child(list.get_child_count() - 1), 0)
	for m in xs:
		list.add_child(_line(m))
	_scroll_end()  # 새 줄이 오면 맨 아래로


func _scroll_end() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _line(m: Dictionary) -> Control:
	var mine: bool = m.get("me", false)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.panel(ME_BG if mine else ROW_BG, 10.0, 10))
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("normal_font", FONT)
	l.add_theme_font_override("bold_font", FONT)
	l.add_theme_font_size_override("normal_font_size", 22)
	l.add_theme_font_size_override("bold_font_size", 22)
	l.add_theme_color_override("default_color", HudScript.INK)
	var nc := ME_NAME_COLOR if mine else NAME_COLOR
	l.text = "[color=#%s]%s[/color]  %s" % [nc.to_html(false), _esc(str(m.name)), _esc(str(m.text))]
	p.add_child(l)
	return p


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")

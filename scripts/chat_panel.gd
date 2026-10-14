extends "res://scripts/ui_window.gd"
## 채팅 창(2026-10-13 개편, 사용자: "제우스: 오만의 신처럼" → "두루마리 컨셉은 유지, 제우스의 UX만"): 국산 MMORPG식 배치 —
## 화면 왼쪽을 덮는 두루마리(UiKit.scroll) 창이 왼쪽에서 밀려 나오고,
## 오른쪽은 게임 화면이 비친다(누르면 닫힘). 창 왼쪽에 세로 채널 탭 [전체][길드][시스템](+관리자 [신고]), 오른쪽에 채널 이름·닫기(◀),
## 줄 목록, 아래 입력 줄(보낼 채널 칩 · 입력 칸 · [전송]).
## [전체] 탭은 전체·길드·시스템 줄을 시각순으로 모아 보여 주고(줄마다 시:분(한국 시각) + [전체]·[길드]·[시스템] 머리표 색), 보낼 채널은 칩을 눌러 전체 ↔ 길드로 바꾼다.
## [길드] 탭은 길드만(길드원일 때만 보인다), [시스템] 탭은 안내·거절·신고 알림(이 기기에서만, 입력 줄 없음).
## 보내면 내 줄이 바로 보이고(대기 표시 없음), 서버가 거절하면 지우고 [시스템] 줄 + 입력 줄 위 붉은 알림. 버튼 글자는 바뀌지 않는다.
## 남의 줄을 누르면(끌지 않고) 신고 확인 상자(두루마리) → [신고]는 바로 "(신고함)" 표시(거절되면 되돌림).
## 관리자(Economy.admin)는 [신고] 탭에서 신고 목록(신고한 사람 → 신고된 사람, 메시지 원문, 당시 앞뒤 채팅)을 본다.
## 휴대폰 키보드가 올라오면 창 아래 끝을 키보드 위로 올린다. 상태·폴링은 오토로드 Chat(chat.gd).

const Lang := preload("res://scripts/lang.gd")

const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const RAIL_BG := Color(0.89, 0.80, 0.62, 1.0)  # 세로 탭 줄(양피지보다 진하게)
const TAB_OFF := Color(0.62, 0.47, 0.30)  # 가죽 갈색
const TAB_ON := UiKit.AMBER  # 고른 탭
const FIELD_BG := Color(0.99, 0.96, 0.89, 1.0)
const SUB := Color(0.16, 0.18, 0.24, 0.58)  # 흐린 먹색(시각·안내)
const TEXT := Color(0.16, 0.18, 0.24)  # 먹색(HudScript.INK)
const NAME_COLOR := Color(0.14, 0.33, 0.60)
const ME_COLOR := Color(0.70, 0.40, 0.04)
const REPORTED := Color(0.78, 0.20, 0.16)
static var CH_NAMES := {"all": Lang.t("chat_panel.ch_names.all"), "guild": Lang.t("chat_panel.ch_names.guild"), "system": Lang.t("chat_panel.ch_names.system")}
const CH_COLORS := {"all": Color(0.45, 0.32, 0.18), "guild": Color(0.16, 0.48, 0.22), "system": Color(0.74, 0.40, 0.02)}
static var TABS := [["all", Lang.t("chat_panel.tabs")], ["guild", Lang.t("chat_panel.tabs_2")], ["system", Lang.t("chat_panel.tabs_3")], ["reports", Lang.t("chat_panel.tabs_4")]]
static var TAB_TITLES := {"all": Lang.t("chat_panel.tab_titles.all"), "guild": Lang.t("chat_panel.tab_titles.guild"), "system": Lang.t("chat_panel.tab_titles.system"), "reports": Lang.t("chat_panel.tab_titles.reports")}
const WIDTH_FRAC := 0.86  # 화면 너비 중 창 너비
const MAX_W := 660.0
const RAIL_W := 104.0
const SLIDE_SEC := 0.18
const NOTICE_SEC := 2.5
const LINE_FONT := 21

var tab := "all"
var send_ch := "all"  # [전체] 탭에서 보낼 채널(칩으로 전체 ↔ 길드)
var buttons := {}  # 테스트용: "tab:all" "tab:guild" "tab:system" "tab:reports" "send" "close" "channel" "report_ok" "report_cancel"
var confirm_box: PanelContainer  # 신고 확인 상자
var confirm_label: Label
var input_row: HBoxContainer
var input: LineEdit
var list: VBoxContainer
var scroll: ScrollContainer
var notice_label: Label
var title_label: Label
var _confirm_id := 0
var _press_at := Vector2.ZERO
var _notice_left := 0.0
var _shown := -1  # 마지막으로 그린 줄 지문 — 바뀌었을 때만 다시 그린다
var _bottom := 0.0  # 키보드가 없을 때 창 아래 오프셋
var _slide: Tween


func _ready() -> void:
	_build_window(0, 0)
	_sheet = true  # 두루마리 펼침 대신 왼쪽에서 밀려 나온다(_on_open)
	dialog.get_parent().color = Color(0, 0, 0, 0.22)  # 오른쪽 게임 화면이 비친다
	dialog.add_theme_stylebox_override("panel", UiKit.scroll())
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	content.add_child(body)
	body.add_child(_build_rail())
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 8)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 12)
	for side in ["right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 0)
	pad.add_child(main)
	body.add_child(pad)
	main.add_child(_build_head())
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	notice_label = _label("", 19, REPORTED, HORIZONTAL_ALIGNMENT_LEFT)
	notice_label.modulate.a = 0.0
	main.add_child(notice_label)
	main.add_child(_build_input())
	_place()
	_build_confirm()
	Chat.changed.connect(_on_changed)
	Chat.notice.connect(show_notice)
	Chat.reports_changed.connect(func():
		if visible and tab == "reports":
			_rebuild())
	get_viewport().size_changed.connect(_place)


## 왼쪽 세로 채널 탭.
func _build_rail() -> Control:
	var rail := PanelContainer.new()
	rail.custom_minimum_size = Vector2(RAIL_W, 0)
	rail.add_theme_stylebox_override("panel", UiKit.panel(RAIL_BG, 10.0, 8, 0.02))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	rail.add_child(v)
	for t in TABS:
		var b := _button(t[1], TAB_OFF, 22)
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 64)
		b.pressed.connect(func(): _pick(t[0]))
		v.add_child(b)
		buttons["tab:" + t[0]] = b
	return rail


## 위: 채널 이름(왼쪽) + 닫기(◀, 오른쪽).
func _build_head() -> Control:
	var head := HBoxContainer.new()
	title_label = _label(Lang.t("chat_panel.build_head"), 26, TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	var x := Button.new()
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(56, 52)
	UiKit.apply_button(x, TAB_OFF, 10.0)
	x.pressed.connect(close)
	var face := Control.new()
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.draw.connect(func():  # ◀ 접기
		var c := face.size / 2.0
		face.draw_colored_polygon(PackedVector2Array([c + Vector2(-9, 0), c + Vector2(7, -11), c + Vector2(7, 11)]), TEXT))
	x.add_child(face)
	head.add_child(x)
	buttons["close"] = x
	return head


## 아래: 보낼 채널 칩 · 입력 칸 · [전송].
func _build_input() -> Control:
	var row := HBoxContainer.new()
	input_row = row
	row.add_theme_constant_override("separation", 6)
	var chip := _button(Lang.t("chat_panel.build_input"), TAB_OFF, 20)
	chip.focus_mode = Control.FOCUS_NONE
	chip.custom_minimum_size = Vector2(76, 58)
	chip.pressed.connect(_toggle_channel)
	row.add_child(chip)
	buttons["channel"] = chip
	input = LineEdit.new()
	input.max_length = Chat.MAX_LEN
	input.placeholder_text = Lang.t("chat_panel.build_input_2") % Chat.MAX_LEN
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(0, 58)
	input.add_theme_font_size_override("font_size", 22)
	input.add_theme_color_override("font_color", TEXT)
	input.add_theme_color_override("caret_color", TEXT)
	input.add_theme_color_override("font_placeholder_color", Color(SUB, 0.6))
	var field := UiKit.panel(FIELD_BG, 8.0, 12, 0.02)
	input.add_theme_stylebox_override("normal", field)
	input.add_theme_stylebox_override("focus", field)
	input.text_submitted.connect(func(_t): send())
	row.add_child(input)
	var sb := _button(Lang.t("chat_panel.build_input_3"), UiKit.AMBER, 22)
	sb.focus_mode = Control.FOCUS_NONE
	sb.custom_minimum_size = Vector2(92, 58)
	sb.pressed.connect(send)
	row.add_child(sb)
	buttons["send"] = sb
	return row


## 창 자리: 왼쪽 끝부터 화면 너비의 WIDTH_FRAC(최대 MAX_W), 위 칩 줄 아래부터 탭 바 위까지.
func _place() -> void:
	var vw := get_viewport().get_visible_rect().size.x
	dialog.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	dialog.anchor_right = 0.0
	dialog.offset_left = 0.0
	dialog.offset_right = minf(vw * WIDTH_FRAC, MAX_W)
	dialog.offset_top = SHEET_TOP
	dialog.offset_bottom = -(HudScript.TAB_BAR_H + 8)
	_bottom = dialog.offset_bottom


func _fit() -> void:
	_place()


## 신고 확인 상자: 가운데 두루마리, 다른 곳을 누르지 못하게 어두운 막 위에.
func _build_confirm() -> void:
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.35)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.visible = false
	veil.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close_confirm())
	dialog.get_parent().add_child(veil)
	confirm_box = PanelContainer.new()
	confirm_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	confirm_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	confirm_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	confirm_box.custom_minimum_size = Vector2(520, 0)
	confirm_box.mouse_filter = Control.MOUSE_FILTER_STOP
	confirm_box.add_theme_stylebox_override("panel", UiKit.scroll(true))
	veil.add_child(confirm_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	confirm_box.add_child(v)
	v.add_child(_label(Lang.t("chat_panel.build_confirm"), 28))
	confirm_label = _label("", 22, Color(HudScript.INK, 0.7))
	confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_label.custom_minimum_size = Vector2(470, 0)
	v.add_child(confirm_label)
	v.add_child(_label(Lang.t("chat_panel.build_confirm_2"), 18, Color(HudScript.INK, 0.62)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var no := _button(Lang.t("chat_panel.build_confirm_3"), UiKit.STEEL, 24)
	var yes := _button(Lang.t("chat_panel.build_confirm_4"), Color(0.86, 0.32, 0.26), 24)
	for b in [no, yes]:
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(b)
	no.pressed.connect(_close_confirm)
	yes.pressed.connect(func():
		var id := _confirm_id
		_close_confirm()
		Chat.report(id))
	buttons["report_cancel"] = no
	buttons["report_ok"] = yes
	v.add_child(h)


## 남의 줄을 눌렀다: 확인 상자.
func ask_report(m: Dictionary) -> void:
	if m.get("me", false) or m.get("sys", false) or int(m.get("id", 0)) <= 0 or Chat.reported.has(int(m.id)):
		return
	_confirm_id = int(m.id)
	confirm_label.text = "%s: %s" % [m.name, m.text]
	confirm_box.get_parent().visible = true


func _close_confirm() -> void:
	confirm_box.get_parent().visible = false
	_confirm_id = 0


func is_confirm_open() -> bool:
	return confirm_box.get_parent().visible


func _on_open() -> void:
	if tab == "guild" and not Chat.has_guild:
		tab = "all"
	Chat.set_window_open(true)
	_shown = -1
	_place()
	_rebuild()
	# 왼쪽에서 밀려 나온다(누름 보호 시간 안에 끝난다)
	if _slide != null:
		_slide.kill()
	dialog.position.x = -dialog.size.x
	_slide = create_tween()
	_slide.tween_property(dialog, "position:x", 0.0, SLIDE_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func close() -> void:
	super.close()
	Chat.set_window_open(false)
	_close_confirm()
	input.release_focus()
	DisplayServer.virtual_keyboard_hide()


func _pick(t: String) -> void:
	tab = t
	_shown = -1
	if t == "reports":
		Chat.fetch_reports()
	_rebuild()


## 보낼 채널: [길드] 탭은 길드, [전체] 탭은 칩으로 고른 채널(길드원이 아니면 전체).
func target_channel() -> String:
	if tab == "guild":
		return "guild"
	return send_ch if Chat.has_guild else "all"


func _toggle_channel() -> void:
	if tab == "guild" or not Chat.has_guild:
		return
	send_ch = "guild" if send_ch == "all" else "all"
	_refresh_chip()


func _refresh_chip() -> void:
	var ch := target_channel()
	var chip: Button = buttons.channel
	chip.text = CH_NAMES[ch]
	UiKit.apply_button(chip, Color(0.22, 0.42, 0.26) if ch == "guild" else TAB_OFF, 12.0)


## [전송]·엔터: 보냈으면 입력 칸을 비운다(바로 거절이면 그대로 둔다 — 알림만).
func send() -> void:
	if Chat.send(target_channel(), input.text):
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
	if visible and tab != "reports":  # 신고 목록은 받을 때만 다시 그린다(스크롤 유지)
		_rebuild()


func _rebuild() -> void:
	buttons["tab:guild"].visible = Chat.has_guild
	buttons["tab:reports"].visible = Economy.admin
	if tab == "guild" and not Chat.has_guild or tab == "reports" and not Economy.admin:
		tab = "all"
	for k in buttons:
		if k.begins_with("tab:"):
			UiKit.apply_button(buttons[k], TAB_ON if k == "tab:" + tab else TAB_OFF, 12.0)
	title_label.text = TAB_TITLES[tab] + ((" · " + Chat.guild_name) if tab == "guild" and Chat.guild_name != "" else "")
	input_row.visible = tab == "all" or tab == "guild"
	_refresh_chip()
	if tab == "reports":
		_rebuild_reports()
		return
	var xs: Array = Chat.view(tab)
	var stamp := xs.size() * 1000003 + Chat.reported.size() * 7919 + (TABS.find(tab) + 1) * 13
	for m in xs:
		stamp += int(m.id) * 31 + (17 if m.get("local", false) else 0)
	if stamp == _shown:
		return
	# 맨 아래로 따라갈지: 새로 열었거나 탭을 바꿨거나(_shown -1), 맨 아래 근처를 보고 있었거나, 내가 보낸 줄. 위로 올려 옛 줄을 읽는 중
	# (끄는 중 포함)에는 남의 새 줄이 와도 그 자리에 둔다(2026-10-14 스크롤 끌기 점검 — 읽던 자리가 맨 아래로 튀었다)
	var bar := scroll.get_v_scroll_bar()
	var follow: bool = _shown == -1 or bar.max_value - bar.page - bar.value < 120.0 \
		or (not xs.is_empty() and xs[-1].get("local", false))
	_shown = stamp
	for c in list.get_children():
		list.remove_child(c)  # 바로 빼야 옛 줄+새 줄이 한 프레임 겹쳐 높이가 튀지 않는다(읽던 자리가 유지된다)
		c.queue_free()
	if not Net.is_online():
		list.add_child(_label(Lang.t("chat_panel.rebuild"), 22, SUB))
		return
	if xs.is_empty():
		list.add_child(_label(Lang.t("chat_panel.rebuild_2") if tab == "guild" else Lang.t("chat_panel.rebuild_3"), 22, SUB))
	for m in xs:
		list.add_child(_line(m))
	if follow:
		_scroll_end()  # 새 줄이 오면 맨 아래로(맨 아래를 보고 있을 때만)


func _scroll_end() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


## 한 줄: [채널] 이름: 내용(시스템은 노란 글씨만). 줄 바탕은 없고 누를 때만 신고 확인.
func _line(m: Dictionary) -> Control:
	var mine: bool = m.get("me", false)
	var ch: String = m.get("ch", "all")
	var p := MarginContainer.new()
	p.add_theme_constant_override("margin_top", 3)
	p.add_theme_constant_override("margin_bottom", 3)
	if not mine and not m.get("sys", false) and int(m.get("id", 0)) > 0:  # 남의 줄: 누르면(끌지 않고) 신고 확인
		p.mouse_filter = Control.MOUSE_FILTER_PASS
		p.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
				if e.pressed:
					_press_at = e.global_position
				elif e.global_position.distance_to(_press_at) < 16.0:
					ask_report(m))
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("normal_font", FONT)
	l.add_theme_font_size_override("normal_font_size", LINE_FONT)
	l.add_theme_color_override("default_color", TEXT)
	var hm := clock(float(m.get("at", 0)))
	var tag := ("[font_size=%d][color=#%s]%s[/color][/font_size] " % [LINE_FONT - 4, SUB.to_html(true), hm] if hm != "" else "")
	tag += "[color=#%s][lb]%s][/color] " % [CH_COLORS.get(ch, TEXT).to_html(false), CH_NAMES.get(ch, "")]
	if ch == "system":
		l.text = tag + "[color=#%s]%s[/color]" % [CH_COLORS.system.to_html(false), _esc(str(m.text))]
	else:
		var nc := ME_COLOR if mine else NAME_COLOR
		l.text = tag + "[color=#%s]%s:[/color] %s" % [nc.to_html(false), _esc(str(m.name)), _esc(str(m.text))]
		if Chat.reported.has(int(m.get("id", 0))):
			l.text += Lang.t("chat_panel.line") % REPORTED.to_html(false)
	p.add_child(l)
	return p


## 관리자 [신고] 탭: 최근 신고(신고한 사람 → 신고된 사람, 시각, 메시지 원문, 당시 앞뒤 채팅 — 신고된 줄은 빨갛게).
func _rebuild_reports() -> void:
	_shown = -1
	for c in list.get_children():
		c.queue_free()
	if Chat.reports.is_empty():
		var msg := Lang.t("chat_panel.rebuild_reports.msg") if Chat.reports_state == "failed" else (Lang.t("chat_panel.rebuild_reports") if Chat.reports_state == "ok" else Lang.t("chat_panel.rebuild_reports_2"))
		list.add_child(_label(msg, 22, SUB))
		return
	for r in Chat.reports:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UiKit.panel(FIELD_BG, 8.0, 12, 0.02))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		p.add_child(v)
		var when := Time.get_datetime_string_from_unix_time(int(float(r.get("at", 0)) + 9 * 3600), true)  # 한국 시각
		var head := _label("%s → %s  ·  %s  ·  %s" % [r.get("reporter_name", ""), r.get("target_name", ""), Lang.t("chat_panel.rebuild_reports_3") if r.get("channel") == "all" else Lang.t("chat_panel.rebuild_reports_4"), when], 18, SUB, HORIZONTAL_ALIGNMENT_LEFT)
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(head)
		var said := str(r.get("raw")) if r.get("raw") != null else str(r.get("text", ""))
		var main := _label(Lang.t("chat_panel.rebuild_reports_5") + said, 21, REPORTED, HORIZONTAL_ALIGNMENT_LEFT)
		main.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(main)
		for c in r.get("context", []):
			var t := str(c.get("raw")) if c.get("raw") != null else str(c.get("text", ""))
			var hit := int(c.get("id", 0)) == int(r.get("message_id", -1))
			var cl := _label("%s: %s" % [c.get("name", ""), t], 18, REPORTED if hit else TEXT, HORIZONTAL_ALIGNMENT_LEFT)
			cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(cl)
		list.add_child(p)


## 시:분(한국 시각, "09:05"). at이 0(안내 줄)이면 "".
static func clock(at: float) -> String:
	if at <= 0.0:
		return ""
	var d := Time.get_datetime_dict_from_unix_time(int(at) + 9 * 3600)
	return "%02d:%02d" % [d.hour, d.minute]


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")

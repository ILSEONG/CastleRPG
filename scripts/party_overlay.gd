extends CanvasLayer
## 파티 퀘스트 매칭 표시(Party 오토로드가 붙인다 — 어느 화면에서든 보인다, 사용자 2026-10-15).
## 대기 중: 화면 위 띠 "리치의 무덤 · 쉬움 매칭 중 0:12" + "n초 뒤 AI 성주가 빈자리를 채웁니다" + [취소].
## 자리가 차면: 입장 수락 창(양피지 두루마리) — 성주마다 이름·출전·수락 여부, 남은 초 막대, [입장 수락] [거절], [자동 수락] 체크.
##   모두 수락하면 전투가 열린다(Party.battle_started). 내가 수락했으면 버튼이 꺼지고 "다른 성주를 기다립니다".
## 받은 파티 초대(친구·길드원이 [초대]): 수락·거절 창 "○○님이 리치의 무덤 · 쉬움 파티에 초대했습니다" + 남은 초 + [거절] [수락].
##   대기·확인 중에는 띄우지 않는다(끝나면 남은 초대가 뜬다). 수락하면 그 파티에 들어간다(Party.accept_invite).
## 버튼은 누르는 즉시 반영(Party가 앱 값을 먼저 바꾼다) — 빠른 두 번 탭도 한 번만 보낸다(Party.accept가 이미 수락했으면 무시).

const Lang := preload("res://scripts/lang.gd")

const GameData := preload("res://scripts/game_data.gd")
const UiKit := preload("res://scripts/ui_kit.gd")
const HudScript := preload("res://scripts/hud.gd")
const PartyRules := preload("res://scripts/party_rules.gd")

const GREEN := Color(0.20, 0.55, 0.25)
const GREY := Color(0.45, 0.47, 0.52)

var bar: PanelContainer
var bar_text: Label
var bar_sub: Label
var cancel_button: Button
var dim: ColorRect
var title: Label
var info: Label
var seat_box: VBoxContainer
var timer_bar: ProgressBar
var timer_label: Label
var accept_button: Button
var decline_button: Button
var auto_box: Button

var invite_dim: ColorRect
var invite_info: Label
var invite_timer: Label
var invite_accept: Button
var invite_decline: Button
var _invite := {}  # 지금 띄운 초대

var _match := ""
var _seats_key := ""
var _confirm_end := 0.0
var _confirm_len := 1.0


func _ready() -> void:
	layer = 30
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_bar(root)
	_build_confirm(root)
	_build_invite(root)
	Party.changed.connect(refresh)
	Party.invites_changed.connect(refresh)
	refresh()


func _build_bar(root: Control) -> void:
	bar = PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.offset_top = 150
	bar.custom_minimum_size = Vector2(560, 0)
	bar.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM_DIALOG, 14.0, 12))
	root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	bar_text = _label("", 24, HudScript.INK)
	col.add_child(bar_text)
	bar_sub = _label("", 18, GREY)
	col.add_child(bar_sub)
	cancel_button = _button(Lang.t("party_overlay.build_bar"), UiKit.STEEL, 24)
	cancel_button.custom_minimum_size = Vector2(110, 56)
	cancel_button.pressed.connect(func(): Party.cancel())
	row.add_child(cancel_button)


func _build_confirm(root: Control) -> void:
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(640, 0)
	panel.add_theme_stylebox_override("panel", UiKit.scroll())
	dim.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	title = _label(Lang.t("party_overlay.build_confirm"), 36, HudScript.INK)
	box.add_child(title)
	info = _label("", 24, HudScript.INK)
	box.add_child(info)
	seat_box = VBoxContainer.new()
	seat_box.add_theme_constant_override("separation", 6)
	box.add_child(seat_box)
	timer_label = _label("", 22, HudScript.INK)
	box.add_child(timer_label)
	timer_bar = ProgressBar.new()
	timer_bar.custom_minimum_size = Vector2(0, 16)
	timer_bar.show_percentage = false
	UiKit.apply_bar(timer_bar, UiKit.AMBER)
	box.add_child(timer_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	decline_button = _button(Lang.t("party_overlay.build_confirm_2"), UiKit.STEEL, 26)
	decline_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	decline_button.pressed.connect(func(): Party.accept(false))
	row.add_child(decline_button)
	accept_button = _button(Lang.t("party_overlay.build_confirm_3"), HudScript.ACCENT, 28)
	accept_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accept_button.size_flags_stretch_ratio = 1.6
	accept_button.pressed.connect(func(): Party.accept(true))
	row.add_child(accept_button)
	auto_box = UiKit.checkbox(Lang.t("party_overlay.build_confirm_4"))
	auto_box.custom_minimum_size = Vector2(300, 64)
	auto_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	auto_box.toggled.connect(func(on): Party.set_auto_accept(on))
	box.add_child(auto_box)


func _build_invite(root: Control) -> void:
	invite_dim = ColorRect.new()
	invite_dim.color = Color(0, 0, 0, 0.45)
	invite_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	invite_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	invite_dim.visible = false
	root.add_child(invite_dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(600, 0)
	panel.add_theme_stylebox_override("panel", UiKit.scroll())
	invite_dim.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(_label(Lang.t("party_overlay.build_invite"), 36, HudScript.INK))
	invite_info = _label("", 24, HudScript.INK)
	invite_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	invite_info.custom_minimum_size = Vector2(540, 0)
	box.add_child(invite_info)
	invite_timer = _label("", 20, GREY)
	box.add_child(invite_timer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	invite_decline = _button(Lang.t("party_overlay.build_invite_2"), UiKit.STEEL, 26)
	invite_decline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	invite_decline.pressed.connect(func():
		if not _invite.is_empty():
			Party.decline_invite(_invite))
	row.add_child(invite_decline)
	invite_accept = _button(Lang.t("party_overlay.build_invite_3"), HudScript.ACCENT, 28)
	invite_accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	invite_accept.size_flags_stretch_ratio = 1.6
	invite_accept.pressed.connect(func():
		if not _invite.is_empty():
			Party.accept_invite(_invite))
	row.add_child(invite_accept)


func _refresh_invite(st: String) -> void:
	var list: Array = Party.invites.filter(func(i): return float(i.get("until", 0.0)) > _now())
	_invite = list[-1] if st == "idle" and not list.is_empty() else {}
	invite_dim.visible = not _invite.is_empty()
	if _invite.is_empty():
		return
	var quest := str(_invite.get("quest", "lich"))
	_tick_invite()
	invite_info.text = Lang.t("party_overlay.refresh_invite") % [str(_invite.get("name", "")), PartyRules.NAMES.get(quest, ""),
		PartyRules.DIFF_NAMES[clampi(int(_invite.get("diff", 1)), 1, 4) - 1]]


func refresh() -> void:
	var q: Dictionary = Party.queue()
	var st := str(q.get("state", "idle"))
	_refresh_invite(st)
	bar.visible = st == "queued"
	dim.visible = st == "confirm"
	if st == "queued":
		_tick_bar(q)  # 시계가 든 같은 문구로 바로 바꾼다(시계 없는 문구를 한 프레임 보이면 띠 폭이 바뀌어 깜빡인다 — 사용자 2026-10-18)
	if st != "confirm":
		_match = ""
		_seats_key = ""
		return
	var id := str(q.get("match_id", ""))
	if id != _match:
		_match = id
		_confirm_len = maxf(1.0, float(q.get("left", PartyRules.CONFIRM_SEC)))
		_confirm_end = _now() + _confirm_len
	var quest := str(q.get("quest", "lich"))
	info.text = "%s · %s" % [PartyRules.NAMES.get(quest, ""), PartyRules.DIFF_NAMES[clampi(int(q.get("diff", 1)), 1, 4) - 1]]
	var key := str(q.get("seats", []))
	if key != _seats_key:  # 같은 자리 표면 다시 만들지 않는다(묻기마다 다시 만들면 깜빡인다)
		_seats_key = key
		for c in seat_box.get_children():
			c.queue_free()
		for s in q.get("seats", []):
			seat_box.add_child(_seat_row(s))
	var mine: bool = q.get("accepted", false)
	accept_button.disabled = mine
	accept_button.text = Lang.t("party_overlay.refresh_2") if mine else Lang.t("party_overlay.refresh_3")
	decline_button.visible = not mine
	_tick_confirm()
	auto_box.set_pressed_no_signal(Party.auto_accept)
	auto_box.queue_redraw()


func _seat_row(s: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name := str(s.get("name", ""))
	if s.get("me", false):
		name += "" if name == Lang.t("party_overlay.seat_row") else Lang.t("party_overlay.seat_row_2")
	elif s.get("bot", false):
		name += " (AI)"
	var nl := _label(name, 22, HudScript.INK)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nl.custom_minimum_size = Vector2(200, 0)
	nl.clip_text = true
	row.add_child(nl)
	var what := ""
	var h = s.get("hero")
	if h is Dictionary:
		what = "%s Lv %d" % [GameData.hero(str(h.get("hero", ""))).get("name", "?"), int(h.get("level", 1))]
	var so = s.get("soldiers")
	if so is Array and not so.is_empty():
		var top := 0
		for x in so:
			top = maxi(top, int(x.get("tier", 1)))
		what = Lang.t("party_overlay.seat_row_3") % [so.size(), top]
	var wl := _label(what, 20, GREY)
	wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wl.clip_text = true
	row.add_child(wl)
	var ok: bool = s.get("accepted", false)
	row.add_child(_label(Lang.t("party_overlay.seat_row_4") if ok else Lang.t("party_overlay.seat_row_5"), 22, GREEN if ok else GREY))
	return row


func _process(_delta: float) -> void:
	var q: Dictionary = Party.queue()
	if not _invite.is_empty():
		var left := float(_invite.get("until", 0.0)) - _now()
		if left <= 0.0:
			refresh()  # 시간이 지난 초대는 닫는다(다음 초대가 있으면 그것)
		else:
			_tick_invite()
	match str(q.get("state", "")):
		"queued":
			_tick_bar(q)
		"confirm":
			_tick_confirm()


## 대기 띠 글(이름·난이도·기다린 시간, AI 성주까지 남은 초). 글이 같으면 건드리지 않는다.
func _tick_bar(q: Dictionary) -> void:
	var waited := maxf(0.0, _now() - float(q.get("since", _now())))
	var t: String = Lang.t("party_overlay.process") % [PartyRules.NAMES.get(str(q.get("quest", "")), ""), PartyRules.DIFF_NAMES[clampi(int(q.get("diff", 1)), 1, 4) - 1], UiKit.clock(waited)]
	if bar_text.text != t:
		bar_text.text = t
	var bot_in := ceili(PartyRules.BOT_WAIT_SEC - waited)
	var sub: String = Lang.t("party_overlay.process_2") % bot_in if bot_in > 0 else Lang.t("party_overlay.process_3")
	if bar_sub.text != sub:
		bar_sub.text = sub


func _tick_confirm() -> void:
	var left := maxf(0.0, _confirm_end - _now())
	timer_bar.value = left / _confirm_len * 100.0
	var t: String = Lang.t("party_overlay.process_4") % ceili(left)
	if timer_label.text != t:
		timer_label.text = t


func _tick_invite() -> void:
	var t: String = Lang.t("party_overlay.process_5") % ceili(maxf(0.0, float(_invite.get("until", 0.0)) - _now()))
	if invite_timer.text != t:
		invite_timer.text = t

func _now() -> float:
	return Party._now()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, color: Color, size := 26) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 60)
	b.add_theme_font_size_override("font_size", size)
	UiKit.apply_button(b, color, 12.0)
	return b

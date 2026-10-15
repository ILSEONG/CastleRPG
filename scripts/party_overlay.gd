extends CanvasLayer
## 파티 퀘스트 매칭 표시(Party 오토로드가 붙인다 — 어느 화면에서든 보인다, 사용자 2026-10-15).
## 대기 중: 화면 위 띠 "리치의 무덤 · 쉬움 매칭 중 0:12" + "n초 뒤 AI 성주가 빈자리를 채웁니다" + [취소].
## 자리가 차면: 입장 수락 창(양피지 두루마리) — 성주마다 이름·출전·수락 여부, 남은 초 막대, [입장 수락] [거절], [자동 수락] 체크.
##   모두 수락하면 전투가 열린다(Party.battle_started). 내가 수락했으면 버튼이 꺼지고 "다른 성주를 기다립니다".
## 버튼은 누르는 즉시 반영(Party가 앱 값을 먼저 바꾼다) — 빠른 두 번 탭도 한 번만 보낸다(Party.accept가 이미 수락했으면 무시).

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

var _match := ""
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
	Party.changed.connect(refresh)
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
	cancel_button = _button("취소", UiKit.STEEL, 24)
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
	title = _label("파티가 모였습니다!", 36, HudScript.INK)
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
	decline_button = _button("거절", UiKit.STEEL, 26)
	decline_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	decline_button.pressed.connect(func(): Party.accept(false))
	row.add_child(decline_button)
	accept_button = _button("입장 수락", HudScript.ACCENT, 28)
	accept_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accept_button.size_flags_stretch_ratio = 1.6
	accept_button.pressed.connect(func(): Party.accept(true))
	row.add_child(accept_button)
	auto_box = UiKit.checkbox("다음부터 자동 수락")
	auto_box.custom_minimum_size = Vector2(300, 64)
	auto_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	auto_box.toggled.connect(func(on): Party.set_auto_accept(on))
	box.add_child(auto_box)


func refresh() -> void:
	var q: Dictionary = Party.queue()
	var st := str(q.get("state", "idle"))
	bar.visible = st == "queued"
	dim.visible = st == "confirm"
	if st == "queued":
		bar_text.text = "%s · %s 매칭 중" % [PartyRules.NAMES.get(str(q.get("quest", "")), ""), PartyRules.DIFF_NAMES[clampi(int(q.get("diff", 1)), 1, 4) - 1]]
	if st != "confirm":
		_match = ""
		return
	var id := str(q.get("match_id", ""))
	if id != _match:
		_match = id
		_confirm_len = maxf(1.0, float(q.get("left", PartyRules.CONFIRM_SEC)))
		_confirm_end = _now() + _confirm_len
	var quest := str(q.get("quest", "lich"))
	info.text = "%s · %s" % [PartyRules.NAMES.get(quest, ""), PartyRules.DIFF_NAMES[clampi(int(q.get("diff", 1)), 1, 4) - 1]]
	for c in seat_box.get_children():
		c.queue_free()
	for s in q.get("seats", []):
		seat_box.add_child(_seat_row(s))
	var mine: bool = q.get("accepted", false)
	accept_button.disabled = mine
	accept_button.text = "다른 성주를 기다립니다" if mine else "입장 수락"
	decline_button.visible = not mine
	auto_box.set_pressed_no_signal(Party.auto_accept)
	auto_box.queue_redraw()


func _seat_row(s: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name := str(s.get("name", ""))
	if s.get("me", false):
		name += "" if name == "나" else " (나)"
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
		what = "병사 %d마리 (최고 T%d)" % [so.size(), top]
	var wl := _label(what, 20, GREY)
	wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wl.clip_text = true
	row.add_child(wl)
	var ok: bool = s.get("accepted", false)
	row.add_child(_label("수락" if ok else "대기", 22, GREEN if ok else GREY))
	return row


func _process(_delta: float) -> void:
	var q: Dictionary = Party.queue()
	match str(q.get("state", "")):
		"queued":
			var waited := maxf(0.0, _now() - float(q.get("since", _now())))
			bar_text.text = "%s · %s 매칭 중 %s" % [PartyRules.NAMES.get(str(q.get("quest", "")), ""), PartyRules.DIFF_NAMES[clampi(int(q.get("diff", 1)), 1, 4) - 1], UiKit.clock(waited)]
			var bot_in := ceili(PartyRules.BOT_WAIT_SEC - waited)
			bar_sub.text = "%d초 뒤 AI 성주가 빈자리를 채웁니다" % bot_in if bot_in > 0 else "AI 성주를 부르고 있습니다"
		"confirm":
			var left := maxf(0.0, _confirm_end - _now())
			timer_bar.value = left / _confirm_len * 100.0
			timer_label.text = "%d초 안에 모두 수락하면 시작합니다" % ceili(left)


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

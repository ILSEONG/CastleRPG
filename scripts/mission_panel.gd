extends "res://scripts/ui_window.gd"
## [미션] 시트(오른쪽 아래 메뉴 side_menu.gd [미션]이 연다). 하위 탭 [일일][주간][반복] — 받을 보상이 있는 탭에 빨간 점.
## 줄 = 미션 제목 + 진행 막대(n / 목표) + 보상, 오른쪽에 [받기](완료)·[이동](바로가기 — 창을 닫고 Tutorial.goto_requested)·"완료"(받음).
## 받을 수 있는 줄이 위, 받은 줄이 아래. 일일·주간은 위에 초기화까지 남은 시간. 진행·보상은 Missions(오토로드).

const LowpolyBox := preload("res://scripts/lowpoly_box.gd")

const SUB := Color(0.16, 0.18, 0.24, 0.62)
const ROW_BG := Color(1, 1, 1, 0.75)
const READY_BG := Color(0.99, 0.90, 0.62, 0.92)
const DONE_BG := Color(0.86, 0.87, 0.89, 0.7)
const REWARD := Color(0.13, 0.50, 0.24)
const RED := Color(0.88, 0.22, 0.2)
const CLOSE_PX := 56.0
const HEAD := {"daily": "매일 00:00에 초기화", "weekly": "매주 월요일 00:00에 초기화",
	"repeat": "받을 때마다 목표가 커지고 계속 받을 수 있어요"}

var tab := "daily"
var body: VBoxContainer
var head_label: Label
var buttons := {}  # 테스트용: "tab:daily" …, "claim:<id>", "go:<id>", "close"

var _dirty := true
var _tick := 0.0
var _rb_cd := 0.0


func _ready() -> void:
	_build_window(0, 10)
	dialog.get_parent().color = Color(0, 0, 0, 0)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()  # 제목 가운데 + 오른쪽 위 닫기(X)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(CLOSE_PX, 0)
	head.add_child(pad)
	var title := _title("미션")
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
	for t in Missions.TYPES:
		var b := _button(t[1], UiKit.STEEL, 24)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 54)
		b.pressed.connect(func(): _pick(t[0]))
		var dot := Control.new()  # 받을 보상이 있으면 오른쪽 위 빨간 점
		dot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var type: String = t[0]
		dot.draw.connect(func():
			if Missions.ready_count(type) > 0:
				var p := Vector2(dot.size.x - 12, 12)
				dot.draw_circle(p, 9.0, RED)
				dot.draw_arc(p, 9.0, 0, TAU, 16, RED.darkened(0.3), 1.5, true))
		b.add_child(dot)
		tabs.add_child(b)
		buttons["tab:" + t[0]] = b
	content.add_child(tabs)
	head_label = _label("", 20, SUB)
	content.add_child(head_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	_fit_sheet()
	Missions.changed.connect(func(): _dirty = true)


func _fit() -> void:
	_fit_sheet()


func _on_open() -> void:
	Missions.roll()
	if Missions.net != null and not Missions._fetched:
		Missions.fetch()
	_rebuild()


func _pick(t: String) -> void:
	tab = t
	_rebuild()


func _process(delta: float) -> void:
	if not visible:
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 1.0
		_head()
	_rb_cd -= delta
	if _dirty and _rb_cd <= 0.0:  # 처치마다 진행이 바뀐다 — 다시 그리기는 몰아서
		_rb_cd = 0.3
		_rebuild()


func _head() -> void:
	var left := 0.0
	if tab == "daily":
		left = Missions.next_day_at() - Missions.now_t()
	elif tab == "weekly":
		left = Missions.next_week_at() - Missions.now_t()
	head_label.text = HEAD[tab] if tab == "repeat" else "%s · 남은 시간 %s" % [HEAD[tab], UiKit.duration(maxf(0.0, left))]


func _rebuild() -> void:
	_dirty = false
	for k in buttons:
		if k.begins_with("tab:"):
			UiKit.apply_button(buttons[k], UiKit.AMBER if k == "tab:" + tab else UiKit.STEEL, 14.0)
			buttons[k].get_child(0).queue_redraw()
	for k in buttons.keys():
		if k.begins_with("claim:") or k.begins_with("go:"):
			buttons.erase(k)
	for c in body.get_children():
		c.queue_free()
	_head()
	var rows := Missions.list(tab)
	var order := func(m: Dictionary) -> int:
		return 0 if Missions.can_claim(m) else (2 if Missions.is_claimed(m) else 1)
	rows.sort_custom(func(a, b): return order.call(a) < order.call(b))
	for m in rows:
		body.add_child(_row(m))


func _row(m: Dictionary) -> Control:
	var done := Missions.is_claimed(m)
	var ok := Missions.can_claim(m)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.panel(READY_BG if ok else (DONE_BG if done else ROW_BG), 12.0, 10))
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	card.add_child(r)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	r.add_child(v)
	var name_row := HBoxContainer.new()
	var t := _label(Missions.title(m), 24, HudScript.INK if not done else SUB, HORIZONTAL_ALIGNMENT_LEFT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.clip_text = true
	name_row.add_child(t)
	if m.type == "repeat" and Missions.times(m.id) > 0:
		name_row.add_child(_label("%d회 받음" % Missions.times(m.id), 18, SUB, HORIZONTAL_ALIGNMENT_RIGHT))
	v.add_child(name_row)
	var goal := Missions.target(m)
	var have := mini(Missions.progress(m), goal)
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 8)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 18)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = goal
	bar.value = goal if done else have
	UiKit.apply_bar(bar, UiKit.AMBER if not done else UiKit.STEEL)
	bar_row.add_child(bar)
	var n := _label("%s / %s" % [UiKit.commas(goal if done else have), UiKit.commas(goal)], 18, SUB, HORIZONTAL_ALIGNMENT_RIGHT)
	n.custom_minimum_size = Vector2(120, 0)
	bar_row.add_child(n)
	v.add_child(bar_row)
	var rw := _label("보상: " + Missions.reward_text(m.reward), 18, REWARD if not done else SUB, HORIZONTAL_ALIGNMENT_LEFT)
	rw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(rw)
	var side := Control.new()
	side.custom_minimum_size = Vector2(120, 0)
	r.add_child(side)
	if done:
		var l := _label("완료", 24, SUB)
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		side.add_child(l)
		return card
	var b: Button
	if ok:
		b = _button("받기" if Missions.waiting != m.id else "…", UiKit.AMBER, 24)
		b.disabled = Missions.waiting != ""
		b.pressed.connect(func(): Missions.claim(m.id))
		buttons["claim:" + m.id] = b
	elif Missions.goto_of(m) != "":
		b = _button("이동", UiKit.STEEL, 24)
		b.pressed.connect(func():
			close()
			Tutorial.goto_requested.emit(Missions.goto_of(m)))
		buttons["go:" + m.id] = b
	if b != null:
		b.focus_mode = Control.FOCUS_NONE
		b.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		b.custom_minimum_size = Vector2(110, 56)
		b.grow_horizontal = Control.GROW_DIRECTION_BOTH
		b.grow_vertical = Control.GROW_DIRECTION_BOTH
		side.add_child(b)
	return card

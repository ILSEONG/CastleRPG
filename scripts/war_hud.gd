extends CanvasLayer
## 공성전 전투 화면. 위 패널: "공성전 · 상대 길드", 남은 시간, [나가기] / 이번 전투 점수·처치·부순 성문 / 성문 4(북·동·남·서)·성채 체력 막대 /
## 연결 상태 한 줄(혼자·방장·참가 중·연결 끊김). 아래: 내 영웅 4 띠(피규어 + HP, 누르면 그 영웅 선택, 쓰러지면 흐리게 + 부활 초) + [자동 진격].
## 가운데 알림(성문 파괴·성채 함락). 끝나면 결과 패널(점수·처치·성문·성채 + [나가기]).

const UiKit := preload("res://scripts/ui_kit.gd")
const MainHud := preload("res://scripts/hud.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const WarRules := preload("res://scripts/war_rules.gd")

const FACE_PX := 92.0
const GATE_RED := Color(0.86, 0.32, 0.22)
const KEEP_RED := Color(0.72, 0.16, 0.14)
const HP_GREEN := Color(0.35, 0.8, 0.4)
const WIN_GOLD := Color("C8901A")

var battle  # war_battle.gd
var title_label: Label
var time_label: Label
var score_label: Label
var role_label: Label
var gate_bars: Array = []
var keep_bar: ProgressBar
var strip: Array = []  # [{hero, face, bar, cell}]
var auto_button: Button
var banner: Label
var result_layer: Control
var result_title: Label
var result_body: Label
var status_text := ""  # war_net이 쓴다(연결 상태)

var _flash_left := 0.0


func _ready() -> void:
	layer = 1
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_top(root)
	_build_strip(root)
	banner = _label("", 54, Color.WHITE)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.offset_top = 380
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.add_theme_color_override("font_outline_color", MainHud.INK)
	banner.add_theme_constant_override("outline_size", 12)
	banner.visible = false
	root.add_child(banner)
	_build_result(root)
	battle.score_changed.connect(_update)
	_update()


func _build_top(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 16
	panel.offset_right = -16
	panel.offset_top = 16
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UiKit.panel(MainHud.PANEL_BG, 14.0, 14))
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	title_label = _label("공성전 · %s" % str(battle.plan.get("enemy_name", "상대 길드")), 30, MainHud.INK)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)
	time_label = _label("", 30, MainHud.INK)
	row.add_child(time_label)
	var leave := _button("나가기", UiKit.STEEL)
	leave.pressed.connect(func(): battle.leave())
	row.add_child(leave)
	score_label = _label("", 24, MainHud.INK)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(score_label)
	var bars := HBoxContainer.new()
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.add_theme_constant_override("separation", 8)
	box.add_child(bars)
	for i in 4:
		bars.add_child(_bar_cell(WarRules.SIDE_NAMES[i], GATE_RED, gate_bars))
	var keep_list := []
	bars.add_child(_bar_cell("성채", KEEP_RED, keep_list))
	keep_bar = keep_list[0]
	role_label = _label("", 20, MainHud.INK.lightened(0.25))
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(role_label)


func _bar_cell(text: String, color: Color, out: Array) -> Control:
	var cell := VBoxContainer.new()
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_constant_override("separation", 2)
	cell.add_child(_label(text, 20, MainHud.INK))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 16)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.apply_bar(bar, color)
	cell.add_child(bar)
	out.append(bar)
	return cell


func _build_strip(root: Control) -> void:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.offset_bottom = -20
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)
	auto_button = _button("자동 진격", MainHud.ACCENT)
	auto_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	auto_button.pressed.connect(func(): battle.set_auto())
	col.add_child(auto_button)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	for h in battle.my_units():
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		var face := Button.new()
		face.flat = true
		face.custom_minimum_size = Vector2(FACE_PX, FACE_PX)
		face.draw.connect(_draw_face.bind(face, h.def))
		face.pressed.connect(_pick.bind(h))
		if PortraitsScript.current != null:
			PortraitsScript.current.portrait_ready.connect(face.queue_redraw.unbind(1))
		cell.add_child(face)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(FACE_PX, 14)
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiKit.apply_bar(bar, HP_GREEN)
		cell.add_child(bar)
		row.add_child(cell)
		strip.append({"hero": h, "face": face, "bar": bar, "cell": cell})


func _pick(h) -> void:
	if h.is_alive() and battle.picker != null:
		battle.picker._select(h)


func _draw_face(c: Control, def: Dictionary) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	var oct := LowpolyBox.octagon(r.grow(-2.0), r.size.x * 0.2)
	c.draw_colored_polygon(oct, UiKit.GRADE_COLORS.get(def.grade, UiKit.STEEL).lightened(0.3))
	oct.append(oct[0])
	c.draw_polyline(oct, UiKit.OUTLINE, 2.0, true)
	c.draw_texture_rect(PortraitsScript.portrait("hero:" + def.id), r, false)


func _build_result(root: Control) -> void:
	result_layer = ColorRect.new()
	result_layer.color = Color(0, 0, 0, 0.45)
	result_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	result_layer.visible = false
	root.add_child(result_layer)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(620, 0)
	panel.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM_DIALOG, 18.0, 24))
	result_layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	result_title = _label("공성 종료", 52, WIN_GOLD)
	result_title.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	result_title.add_theme_constant_override("outline_size", 8)
	box.add_child(result_title)
	result_body = _label("", 28, MainHud.INK)
	box.add_child(result_body)
	var out := _button("나가기", MainHud.ACCENT)
	out.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	out.pressed.connect(func(): battle.leave())
	box.add_child(out)


func show_result(r: Dictionary) -> void:
	result_title.text = "성채 함락!" if r.get("keep_broken", false) else "공성 종료"
	result_body.text = "이번 전투 %d점\n수비 영웅 처치 %d · 성문 파괴 %d%s" % [int(r.points), int(r.kills), int(r.gates_broken),
		" · 성채 함락" if r.get("keep_broken", false) else ""]
	result_layer.visible = true


func flash(text: String) -> void:
	banner.text = text
	banner.visible = true
	_flash_left = 1.8


func refresh_role() -> void:
	_update()


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			banner.visible = false
	time_label.text = UiKit.clock(battle.time_left())
	for i in 4:
		gate_bars[i].value = battle.gates[i].hp_ratio() * 100.0
	keep_bar.value = battle.keep.hp_ratio() * 100.0
	for s in strip:
		var h = s.hero
		s.bar.value = h.hp_ratio() * 100.0
		s.cell.modulate.a = 1.0 if h.is_alive() else 0.45


func _update() -> void:
	score_label.text = "이번 전투 %d점 · 처치 %d · 성문 %d/4" % [battle.points_now(), battle.kills, battle.gates_broken()]
	var r := {"solo": "혼자 공격 중 (길드원 영웅은 자동)", "host": "길드원과 함께 · 이 기기가 전투를 진행 중", "puppet": "길드원과 함께 공격 중"}
	role_label.text = status_text if status_text != "" else str(r.get(battle.role, ""))


func set_status(text: String) -> void:
	status_text = text
	_update()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 56)
	b.add_theme_font_size_override("font_size", 26)
	UiKit.apply_button(b, color, 12.0)
	return b

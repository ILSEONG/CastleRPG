extends CanvasLayer
## PVP 전투 화면(pvp_battle.gd). 위 패널: "결투 · 상대 이름 (등급)", 남은 시간, [나가기](두 번 눌러야 포기 — 패배) / 내 팀·상대 팀 영웅 체력 막대와
## 남은 영웅 수. 결투면 아래: [자동] + 내 영웅 5 띠(피규어 + HP + 스킬 쿨, 누르면 그 영웅 선택, 쓰러지면 흐리게). 가운데 알림 띠.
## 끝나면 결과 패널: 승리/패배, 포인트 증감·지금 등급, PVP 코인, [확인](나가기).

const UiKit := preload("res://scripts/ui_kit.gd")
const MainHud := preload("res://scripts/hud.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")
const HeroStrip := preload("res://scripts/hero_strip.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const PvpRules := preload("res://scripts/pvp_rules.gd")

const FACE_PX := 92.0
const HP_GREEN := Color(0.35, 0.8, 0.4)
const HP_RED := Color(0.86, 0.3, 0.24)
const SELECT_GOLD := Color(1.0, 0.78, 0.2)
const WIN_GOLD := Color("C8901A")
const LOSE_GRAY := Color(0.42, 0.45, 0.52)
const ARM_SEC := 2.5

var battle  # pvp_battle.gd
var time_label: Label
var my_bar: ProgressBar
var foe_bar: ProgressBar
var my_count: Label
var foe_count: Label
var leave_button: Button
var strip: Array = []  # [{hero, face, bar, cell}]
var banner: Label
var result_layer: Control
var result_title: Label
var result_body: Label

var _flash_left := 0.0
var _armed := 0.0


func _ready() -> void:
	layer = 1
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_top(root)
	if battle.mode == "duel":
		_build_strip(root)
	banner = _label("", 54, Color.WHITE)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.offset_top = 360
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.add_theme_color_override("font_outline_color", MainHud.INK)
	banner.add_theme_constant_override("outline_size", 12)
	banner.visible = false
	root.add_child(banner)
	_build_result(root)
	refresh()


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
	var opp: Dictionary = battle.run.get("opponent", {})
	var tier: Dictionary = PvpRules.tier_of(int(opp.get("points", 0)))
	var title := _label("%s · %s (%s)" % [PvpRules.NAMES.get(battle.mode, "PVP"), str(opp.get("name", "상대")), tier.name], 28, MainHud.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	row.add_child(title)
	time_label = _label("", 30, MainHud.INK)
	row.add_child(time_label)
	leave_button = _button("나가기", UiKit.STEEL)
	leave_button.pressed.connect(_on_leave)
	row.add_child(leave_button)
	var bars := HBoxContainer.new()
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.add_theme_constant_override("separation", 12)
	box.add_child(bars)
	var mine := _bar_cell("내 팀", HP_GREEN)
	my_bar = mine[0]
	my_count = mine[1]
	bars.add_child(mine[2])
	var foe := _bar_cell("상대 팀", HP_RED)
	foe_bar = foe[0]
	foe_count = foe[1]
	bars.add_child(foe[2])


func _bar_cell(text: String, color: Color) -> Array:
	var cell := VBoxContainer.new()
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(head)
	var name := _label(text, 20, MainHud.INK)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name)
	var count := _label("", 20, MainHud.INK)
	head.add_child(count)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 16)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.apply_bar(bar, color)
	cell.add_child(bar)
	return [bar, count, cell]


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
	var auto := _button("자동 전투", MainHud.ACCENT)
	auto.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	auto.pressed.connect(func(): battle.set_auto())
	col.add_child(auto)
	col.add_child(_label("영웅을 눌러 고르고 바닥을 눌러 옮기세요", 20, Color.WHITE))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(HeroStrip.GAP))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	var px := HeroStrip.fit_px(battle.my_units().size(), FACE_PX, 688.0, HeroStrip.GAP)
	for h in battle.my_units():
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		var face := Button.new()
		face.flat = true
		face.custom_minimum_size = Vector2(px, px)
		face.draw.connect(_draw_face.bind(face, h.def, h))
		face.pressed.connect(_pick.bind(h))
		if PortraitsScript.current != null:
			PortraitsScript.current.portrait_ready.connect(face.queue_redraw.unbind(1))
		cell.add_child(HeroStrip.face_with_slots(face, h, px))
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(px, 14)
		bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiKit.apply_bar(bar, HP_GREEN)
		cell.add_child(bar)
		row.add_child(cell)
		strip.append({"hero": h, "face": face, "bar": bar, "cell": cell})


func _pick(h) -> void:
	if h.is_alive() and battle.picker != null:
		battle.picker._select(h)


func _draw_face(c: Control, def: Dictionary, h = null) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	var oct := LowpolyBox.octagon(r.grow(-2.0), r.size.x * 0.2)
	c.draw_colored_polygon(oct, UiKit.GRADE_COLORS.get(def.grade, UiKit.STEEL).lightened(0.3))
	c.draw_texture_rect(PortraitsScript.portrait("hero:" + def.id), r, false)
	oct.append(oct[0])
	var on: bool = h != null and battle != null and battle.picker != null and battle.picker.selected == h
	c.draw_polyline(oct, SELECT_GOLD if on else UiKit.OUTLINE, 5.0 if on else 2.0, true)


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
	result_title = _label("", 60, WIN_GOLD)
	result_title.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	result_title.add_theme_constant_override("outline_size", 8)
	box.add_child(result_title)
	result_body = _label("", 28, MainHud.INK)
	box.add_child(result_body)
	var ok := _button("확인", MainHud.ACCENT)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func(): battle.leave())
	box.add_child(ok)


func show_result(r: Dictionary) -> void:
	var win: bool = r.get("win", false)
	result_title.text = "승리!" if win else "패배"
	result_title.add_theme_color_override("font_color", WIN_GOLD if win else LOSE_GRAY)
	var why := ""
	match str(r.get("reason", "")):
		"time":
			why = "시간 종료 — 남은 체력으로 판정\n"
		"forfeit":
			why = "전투를 포기했습니다\n"
	var pts := Pvp.points(battle.mode)
	var tier: Dictionary = PvpRules.tier_of(pts)
	var d := int(r.get("delta", 0))
	result_body.text = "%s포인트 %s%d → %d (%s)\nPVP 코인 +%d" % [why, "+" if d >= 0 else "", d, pts, tier.name, int(r.get("coins", 0))]
	result_layer.visible = true
	leave_button.visible = false


func flash(text: String, sec := 1.8) -> void:
	banner.text = text
	banner.visible = true
	_flash_left = sec


func _on_leave() -> void:
	if battle.phase == battle.Phase.RESULT:
		battle.leave()
		return
	if _armed > 0.0:
		battle.forfeit()
		return
	_armed = ARM_SEC
	leave_button.text = "포기?"
	flash("한 번 더 누르면 포기합니다 (패배)", ARM_SEC)


func refresh() -> void:
	my_count.text = "영웅 %d / %d" % [battle.alive(0), battle.units(0).size()]
	foe_count.text = "영웅 %d / %d" % [battle.alive(1), battle.units(1).size()]


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			banner.visible = false
	if _armed > 0.0:
		_armed -= delta
		if _armed <= 0.0:
			leave_button.text = "나가기"
	time_label.text = UiKit.clock(battle.time_left())
	my_bar.value = battle.team_hp_ratio(0) * 100.0
	foe_bar.value = battle.team_hp_ratio(1) * 100.0
	refresh()
	for s in strip:
		var h = s.hero
		s.bar.value = h.hp_ratio() * 100.0
		s.cell.modulate.a = 1.0 if h.is_alive() else 0.45
		s.face.queue_redraw()


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

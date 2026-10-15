extends CanvasLayer
## 파티 퀘스트 전투 화면(party_battle.gd). 위 패널: "리치의 무덤 · 어려움", 남은 시간, [나가기](두 번 눌러야 포기 — 이 성주만 패배) / 보스 체력 막대.
## 왼쪽: 성주 목록(이름 + AI 표시, 리치 = 영웅 체력 막대, 거미 여왕 = 남은 병사 수). 리치면 아래: [자동] + 안내, 내 영웅이 쓰러지면 부활까지 남은 초.
## 가운데 알림 띠. 끝나면 결과 패널: 승리/패배, 보상 장신구(등급 칸 + 이름) 또는 "오늘 보상을 모두 받았습니다", [확인](나가기).

const Lang := preload("res://scripts/lang.gd")

const UiKit := preload("res://scripts/ui_kit.gd")
const MainHud := preload("res://scripts/hud.gd")
const ResultBanner := preload("res://scripts/result_banner.gd")
const ItemTileScript := preload("res://scripts/item_tile.gd")
const ItemText := preload("res://scripts/item_text.gd")
const PartyRules := preload("res://scripts/party_rules.gd")

const HP_GREEN := Color(0.35, 0.8, 0.4)
const HP_RED := Color(0.86, 0.3, 0.24)
const ARM_SEC := 2.5
const ARM_GAP_MS := 300
static var SLOT_NAMES := {"ring": Lang.t("party_hud.slot_names.ring"), "necklace": Lang.t("party_hud.slot_names.necklace")}

var battle  # party_battle.gd
var time_label: Label
var boss_bar: ProgressBar
var boss_pct: Label
var leave_button: Button
var banner: Label
var revive_label: Label
var rows: Array = []  # [{seat, bar, count}]
var result_layer: Control
var result_title
var result_body: Label
var result_items: HBoxContainer

var _flash_left := 0.0
var _armed := 0.0
var _armed_ms := 0


func _ready() -> void:
	layer = 1
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_top(root)
	_build_seats(root)
	if battle.quest == "lich":
		_build_bottom(root)
	banner = _label("", 40, Color.WHITE)  # 화면 폭 안에서 줄바꿈(긴 보스 대사가 잘리지 않게), 자리 표(420~) 위
	banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	banner.offset_left = 24
	banner.offset_right = -24
	banner.offset_top = 300
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	var title := _label("%s · %s" % [PartyRules.NAMES.get(battle.quest, ""), PartyRules.DIFF_NAMES[battle.diff - 1]], 28, MainHud.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	row.add_child(title)
	time_label = _label("", 30, MainHud.INK)
	row.add_child(time_label)
	leave_button = _button(Lang.t("party_hud.build_top"), UiKit.STEEL)
	leave_button.pressed.connect(_on_leave)
	row.add_child(leave_button)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	var name := _label(PartyRules.BOSS_NAMES.get(battle.quest, ""), 22, MainHud.INK)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name)
	boss_pct = _label("", 22, MainHud.INK)
	head.add_child(boss_pct)
	boss_bar = ProgressBar.new()
	boss_bar.custom_minimum_size = Vector2(0, 20)
	boss_bar.show_percentage = false
	boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.apply_bar(boss_bar, HP_RED)
	box.add_child(boss_bar)


func _build_seats(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 16
	panel.offset_top = 420  # SSR 컷인 띠(화면 왼쪽 위 ~200–400) 아래
	panel.custom_minimum_size = Vector2(230, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UiKit.panel(Color(MainHud.PANEL_BG, 0.85), 12.0, 10))
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	for i in battle.seats.size():
		var s: Dictionary = battle.seats[i]
		var head := HBoxContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(head)
		var who := str(s.get("name", ""))
		if i == battle.me:
			who += "" if who == Lang.t("party_hud.build_seats") else Lang.t("party_hud.build_seats_2")
		elif s.get("bot", false):
			who += " (AI)"
		if battle.quest == "spider":  # 이 성주 병사의 옷 색(PartyRules.SEAT_COLORS)
			var dot := Panel.new()
			dot.custom_minimum_size = Vector2(16, 16)
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var c: Color = PartyRules.SEAT_COLORS[i % PartyRules.SEAT_COLORS.size()]
			dot.add_theme_stylebox_override("panel", UiKit.panel(c, 4.0, 0))
			head.add_child(dot)
		var nl := _label(who, 18, Color(0.12, 0.40, 0.78) if i == battle.me else MainHud.INK)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.clip_text = true
		nl.custom_minimum_size = Vector2(150, 0)
		head.add_child(nl)
		var count := _label("", 18, MainHud.INK)
		head.add_child(count)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 10)
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiKit.apply_bar(bar, HP_GREEN)
		box.add_child(bar)
		rows.append({"seat": i, "bar": bar, "count": count})


func _build_bottom(root: Control) -> void:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.offset_bottom = -24
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)
	revive_label = _label("", 26, Color(1.0, 0.75, 0.6))
	revive_label.add_theme_color_override("font_outline_color", MainHud.INK)
	revive_label.add_theme_constant_override("outline_size", 8)
	col.add_child(revive_label)
	var auto := _button(Lang.t("party_hud.build_bottom"), MainHud.ACCENT)
	auto.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	auto.pressed.connect(func(): battle.set_auto())
	col.add_child(auto)
	var hint := _label(Lang.t("party_hud.build_bottom_2"), 20, Color.WHITE)
	hint.add_theme_color_override("font_outline_color", MainHud.INK)
	hint.add_theme_constant_override("outline_size", 6)
	col.add_child(hint)


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
	panel.add_theme_stylebox_override("panel", UiKit.scroll())
	result_layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	result_title = ResultBanner.new()
	result_title.overhang = 40.0
	box.add_child(result_title)
	result_items = HBoxContainer.new()
	result_items.alignment = BoxContainer.ALIGNMENT_CENTER
	result_items.add_theme_constant_override("separation", 12)
	box.add_child(result_items)
	result_body = _label("", 26, MainHud.INK)
	result_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_body.custom_minimum_size = Vector2(540, 0)
	box.add_child(result_body)
	var ok := _button(Lang.t("party_hud.build_result"), MainHud.ACCENT)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func(): battle.leave())
	box.add_child(ok)


func show_result(r: Dictionary) -> void:
	var win: bool = r.get("win", false)
	result_title.play(Lang.t("party_hud.show_result") if win else Lang.t("party_hud.show_result_2"), "win" if win else "lose")
	for c in result_items.get_children():
		c.queue_free()
	var lines := []
	match str(r.get("reason", "")):
		"time":
			lines.append(Lang.t("party_hud.show_result_3"))
		"wipe":
			lines.append(Lang.t("party_hud.show_result_4"))
		"forfeit":
			lines.append(Lang.t("party_hud.show_result_5"))
	if r.get("pending", false):
		lines.append(Lang.t("party_hud.show_result_6"))
	else:
		var items: Array = r.get("rewards", {}).get("items", []) if r.get("rewards") is Dictionary else []
		for it in items:
			var tile = ItemTileScript.new()
			tile.custom_minimum_size = Vector2(96, 96)
			tile.set_item(str(it.get("slot", "")), str(it.get("grade", "N")))
			result_items.add_child(tile)
			var stats := []
			for p in ItemText.stat_parts(it):
				stats.append(str(p[0]))
			lines.append(Lang.t("party_hud.show_result_7") % [str(it.get("grade", "")), SLOT_NAMES.get(str(it.get("slot", "")), ""), " ".join(stats)])
		if r.get("no_reward", false):
			lines.append(Lang.t("party_hud.show_result_8"))
		elif win and items.is_empty() and r.has("error"):
			lines.append(Lang.t("party_hud.show_result_9"))
		elif not win and r.get("claimed_win", false):
			lines.append(Lang.t("party_hud.show_result_10"))
	result_body.text = "\n".join(lines)
	result_layer.visible = true
	leave_button.visible = false


func flash(text: String, sec := 1.8, color := Color.WHITE) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", color)
	banner.visible = true
	_flash_left = sec


func _on_leave() -> void:
	if battle.phase == battle.Phase.RESULT:
		battle.leave()
		return
	if _armed > 0.0 and Time.get_ticks_msec() - _armed_ms < ARM_SEC * 1000.0:  # 실제 시간(슬로모션·배속 무관)
		if Time.get_ticks_msec() - _armed_ms < ARM_GAP_MS:
			return
		battle.forfeit()
		return
	_armed = ARM_SEC
	_armed_ms = Time.get_ticks_msec()
	leave_button.text = Lang.t("party_hud.on_leave")
	flash(Lang.t("party_hud.on_leave_2"), ARM_SEC)


func refresh() -> void:
	for r in rows:
		var i: int = r.seat
		if battle.quest == "lich":
			var h = battle.heroes[i] if i < battle.heroes.size() else null
			r.bar.value = h.hp_ratio() * 100.0 if h != null and h.is_alive() else 0.0
			r.count.text = "" if h == null or h.is_alive() else Lang.t("party_hud.refresh")
		else:
			var mine: Array = battle.soldiers.filter(func(s): return s.owner_seat == i)
			var alive := mine.filter(func(s): return s.is_alive())
			var hp := 0.0
			for s in alive:
				hp += s.hp_ratio()
			r.bar.value = hp / maxf(1.0, mine.size()) * 100.0
			r.count.text = "%d/%d" % [alive.size(), mine.size()]


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			banner.visible = false
	if _armed > 0.0 and Time.get_ticks_msec() - _armed_ms >= ARM_SEC * 1000.0:
		_armed = 0.0
		leave_button.text = Lang.t("party_hud.process")
	time_label.text = UiKit.clock(battle.time_left())
	var ratio: float = battle.boss_hp_ratio()
	boss_bar.value = ratio * 100.0
	boss_pct.text = "%d%%" % ceili(ratio * 100.0)
	refresh()
	if revive_label != null:
		var mine: Array = battle.my_units()
		var left := -1.0
		if not mine.is_empty() and not mine[0].is_alive():
			left = battle.revive_left(mine[0])
		revive_label.visible = left >= 0.0
		if left >= 0.0:
			revive_label.text = Lang.t("party_hud.process_2") % ceili(left)


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

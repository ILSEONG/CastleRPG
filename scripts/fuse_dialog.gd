extends Control
## SSR 조각 합성 창(2026-10-29 사용자 "SSR을 10개 합성하면 UR 하나 나오게 해"): 모집 창 다이아 탭 [SSR 조각 합성]이 연다. 어두운 막 + 크림 창.
## 가진 SSR 영웅(조각이 있는 영웅만) 줄마다 이름·보유 조각·[−] 넣을 수 [+]. 위에 "넣은 조각 n / 10", 아래 [자동 채우기] [합성] [닫기].
## [자동 채우기] = Economy.fuse_autofill(★5까지 쓰고 남는 조각부터). [합성]은 합이 Economy.fuse_cost()일 때만 — Economy.fuse_ur가 결과를
## gacha_done으로 보내면 모집 창이 뒤집기 연출로 보여 준다(fused(picks)를 받은 모집 창이 부른다).

const Lang := preload("res://scripts/lang.gd")

const GameData := preload("res://scripts/game_data.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

signal fused(picks: Dictionary)  # [합성]: 이 묶음으로 합성(모집 창이 Economy.fuse_ur를 부르고 결과를 기다린다)

const SUB := Color(0.25, 0.22, 0.2, 0.8)

var title_label: Label
var count_label: Label
var empty_label: Label
var list: VBoxContainer  # 테스트가 읽는다: 줄은 meta "hero_id"
var auto_button: Button
var fuse_button: Button
var close_button: Button
var picks := {}  # 영웅 id → 넣을 조각 수


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var box := PanelContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 24
	box.offset_right = -24
	box.offset_top = 140
	box.offset_bottom = -160
	box.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM_DIALOG, 14.0, 22))
	add_child(box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	box.add_child(col)
	title_label = _label(Lang.t("fuse_dialog.ready"), 32)
	col.add_child(title_label)
	col.add_child(_label(Lang.t("fuse_dialog.ready_2") % Economy.fuse_cost(), 20, SUB))
	count_label = _label("", 28, UiKit.GRADE_COLORS.UR.darkened(0.2))
	col.add_child(count_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	empty_label = _label(Lang.t("fuse_dialog.ready_3"), 22, SUB)
	col.add_child(empty_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	auto_button = _button(Lang.t("fuse_dialog.ready_4"), UiKit.STEEL)
	auto_button.pressed.connect(_on_auto)
	row.add_child(auto_button)
	fuse_button = _button(Lang.t("fuse_dialog.ready_5"), UiKit.GRADE_COLORS.UR)
	fuse_button.pressed.connect(_on_fuse)
	row.add_child(fuse_button)
	close_button = _button(Lang.t("fuse_dialog.ready_6"), UiKit.STEEL)
	close_button.pressed.connect(func(): visible = false)
	row.add_child(close_button)


func _label(text: String, font_size: int, color: Color = UiKit.INK) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, color: Color, font_size := 24) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 68)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", font_size)
	UiKit.apply_button(b, color, 14.0)
	return b


## 연다: 넣은 조각은 비우고 목록을 다시 만든다.
func open() -> void:
	picks = {}
	_rebuild()
	visible = true


## 조각이 있는 가진 SSR 영웅(영웅 표 순서).
func candidates() -> Array:
	return GameData.heroes().filter(func(h): return h.grade == "SSR" and int(Economy.heroes.get(h.id, 0)) >= 1 and Economy.shards_of(h.id) > 0).map(func(h): return h.id)


func total() -> int:
	var t := 0
	for id in picks:
		t += int(picks[id])
	return t


## id의 넣을 수를 d만큼(0..보유 조각, 합은 fuse_cost까지).
func bump(id: String, d: int) -> void:
	var cur := int(picks.get(id, 0))
	var n := clampi(cur + d, 0, mini(Economy.shards_of(id), cur + Economy.fuse_cost() - total()))
	if n > 0:
		picks[id] = n
	else:
		picks.erase(id)
	_rebuild()


func _on_auto() -> void:
	picks = Economy.fuse_autofill()
	_rebuild()


func _on_fuse() -> void:
	if not Economy.fuse_ok(picks):
		return
	visible = false
	fused.emit(picks.duplicate())


func _rebuild() -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	var ids := candidates()
	empty_label.visible = ids.is_empty()
	for id in ids:
		var h := GameData.hero(id)
		var row := HBoxContainer.new()
		row.set_meta("hero_id", id)
		row.add_theme_constant_override("separation", 8)
		list.add_child(row)
		var name_l := _label(Lang.t("fuse_dialog.rebuild") % [h.name, Economy.shards_of(id)], 22)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		var minus := _button("−", UiKit.STEEL, 26)
		minus.custom_minimum_size = Vector2(64, 56)
		minus.size_flags_horizontal = Control.SIZE_SHRINK_END
		minus.pressed.connect(bump.bind(id, -1))
		row.add_child(minus)
		var n_l := _label(str(int(picks.get(id, 0))), 26)
		n_l.custom_minimum_size = Vector2(48, 0)
		row.add_child(n_l)
		var plus := _button("+", UiKit.STEEL, 26)
		plus.custom_minimum_size = Vector2(64, 56)
		plus.size_flags_horizontal = Control.SIZE_SHRINK_END
		plus.pressed.connect(bump.bind(id, 1))
		row.add_child(plus)
	count_label.text = Lang.t("fuse_dialog.rebuild_2") % [total(), Economy.fuse_cost()]
	fuse_button.disabled = not Economy.fuse_ok(picks)
	auto_button.disabled = ids.is_empty()

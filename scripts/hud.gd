extends CanvasLayer
## HUD. GameState 시그널만 구독. 게임 오브젝트 직접 참조 없음.

const INK := Color(0.16, 0.18, 0.24)
const PANEL_BG := Color(1, 1, 1, 0.72)
const BAR_BG := Color(0, 0, 0, 0.12)
const ACCENT := Color(0.98, 0.70, 0.20)
const RADIUS := 14
const IconsScript := preload("res://scripts/icons.gd")

var _stage_label: Label
var _castle_bar: ProgressBar
var _gate_bars: Array = []
var _center: Label
var _button: Button
var _chips := {}  # 아이콘 kind(gold·wood·stone·food) → 숫자 Label


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_chips(root)

	var top := VBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 8)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 16
	panel.offset_right = -16
	panel.offset_top = 76  # 상단 칩 줄(16..64) 아래
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", round_box(PANEL_BG, RADIUS, 12))
	root.add_child(panel)
	panel.add_child(top)
	_stage_label = Label.new()
	_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_label.add_theme_font_size_override("font_size", 36)
	_stage_label.add_theme_color_override("font_color", INK)
	top.add_child(_stage_label)
	_castle_bar = _bar(Color(0.95, 0.75, 0.2))
	top.add_child(_castle_bar)
	var gates := HBoxContainer.new()
	gates.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(gates)
	for side in 4:
		var b := _bar(Color(0.55, 0.6, 0.7))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gates.add_child(b)
		_gate_bars.append(b)

	_center = Label.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_center.grow_vertical = Control.GROW_DIRECTION_BOTH
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.add_theme_font_size_override("font_size", 72)
	_center.add_theme_color_override("font_color", Color.WHITE)
	_center.add_theme_color_override("font_outline_color", Color(INK, 0.85))
	_center.add_theme_constant_override("outline_size", 18)
	root.add_child(_center)

	_button = Button.new()
	_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_button.offset_left = 32
	_button.offset_right = -32
	_button.offset_top = -120
	_button.offset_bottom = -32
	_button.add_theme_font_size_override("font_size", 28)
	_button.pressed.connect(_on_button)
	_button.add_theme_stylebox_override("normal", round_box(ACCENT, RADIUS + 6, 0))
	_button.add_theme_stylebox_override("hover", round_box(ACCENT.lightened(0.12), RADIUS + 6, 0))
	_button.add_theme_stylebox_override("pressed", round_box(ACCENT.darkened(0.15), RADIUS + 6, 0))
	_button.add_theme_stylebox_override("disabled", round_box(Color(0.6, 0.62, 0.66, 0.8), RADIUS + 6, 0))
	_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_button.add_theme_color_override("font_color", Color.WHITE)
	_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	_button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.7))
	root.add_child(_button)

	GameState.mode_changed.connect(_on_mode_changed)
	GameState.castle_hp_changed.connect(_on_castle_hp)
	GameState.gate_hp_changed.connect(_on_gate_hp)
	GameState.stage_cleared.connect(_on_cleared)
	GameState.stage_failed.connect(_on_failed)
	_on_castle_hp(GameState.castle_hp, GameState.castle_hp_max)
	for side in 4:
		_on_gate_hp(side, GameState.gate_hp[side], GameState.gate_hp_max)
	_on_mode_changed(GameState.mode)


func _process(_delta: float) -> void:
	if GameState.mode == GameState.Mode.COUNTDOWN:
		_center.text = str(ceili(GameState.countdown_left()))


func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(0, 16)
	b.show_percentage = false
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_theme_stylebox_override("fill", round_box(color, 8, 0))
	b.add_theme_stylebox_override("background", round_box(BAR_BG, 8, 0))
	return b


static func round_box(color: Color, radius: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


func _on_castle_hp(hp: float, hp_max: float) -> void:
	_castle_bar.max_value = hp_max
	_castle_bar.value = hp


func _on_gate_hp(side: int, hp: float, hp_max: float) -> void:
	_gate_bars[side].max_value = hp_max
	_gate_bars[side].value = hp


func _on_cleared(stage: int) -> void:
	_center.text = "스테이지 %d 클리어" % stage


func _on_failed(_stage: int) -> void:
	_center.text = "패배"


func _on_mode_changed(mode: int) -> void:
	_stage_label.text = "스테이지 %d" % GameState.stage
	if mode == GameState.Mode.IDLE or mode == GameState.Mode.STAGE:
		_center.text = ""
	_refresh_button()


func _refresh_button() -> void:
	if GameState.mode == GameState.Mode.IDLE:
		_button.text = "스테이지 진행"
		_button.disabled = false
	elif GameState.mode == GameState.Mode.RESULT:
		_button.disabled = true
	else:
		_button.text = "중지 예약됨 (취소)" if GameState.stop_requested else "이번 스테이지 후 중지"
		_button.disabled = false


func _on_button() -> void:
	if GameState.mode == GameState.Mode.IDLE:
		GameState.start_stage()
	else:
		GameState.stop_after_stage()
		_refresh_button()


## 맨 위 둥근 칩 4개: 골드·목재·석재·식량(아이콘 + 쉼표 숫자). 입력은 통과시킨다.
func _build_chips(root: Control) -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	row.offset_left = 16
	row.offset_right = -16
	row.offset_top = 16
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	for kind in IconsScript.KINDS:
		var chip := PanelContainer.new()
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_theme_stylebox_override("panel", round_box(PANEL_BG, 24, 8))
		row.add_child(chip)
		var inner := HBoxContainer.new()
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_theme_constant_override("separation", 6)
		chip.add_child(inner)
		var icon = IconsScript.new()
		icon.kind = kind
		icon.custom_minimum_size = Vector2(32, 32)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(icon)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.clip_text = true
		label.add_theme_font_size_override("font_size", 24)
		label.add_theme_color_override("font_color", INK)
		inner.add_child(label)
		_chips[kind] = label
	Economy.changed.connect(_refresh_chips)
	_refresh_chips()


func _refresh_chips() -> void:
	_chips["gold"].text = commas(Economy.gold)
	for id in Economy.res:
		_chips[id].text = commas(Economy.res[id])


## 1234567 → "1,234,567"
static func commas(n: int) -> String:
	var s := str(absi(n))
	for i in range(s.length() - 3, 0, -3):
		s = s.insert(i, ",")
	return ("-" if n < 0 else "") + s

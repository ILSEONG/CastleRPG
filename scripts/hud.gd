extends CanvasLayer
## HUD. GameState 시그널만 구독. 게임 오브젝트 직접 참조 없음.

var _stage_label: Label
var _castle_bar: ProgressBar
var _gate_bars: Array = []
var _center: Label
var _button: Button


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 16
	root.add_child(top)
	_stage_label = Label.new()
	_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_label.add_theme_font_size_override("font_size", 36)
	top.add_child(_stage_label)
	_castle_bar = _bar(Color(0.95, 0.75, 0.2))
	top.add_child(_castle_bar)
	var gates := HBoxContainer.new()
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
	root.add_child(_center)

	_button = Button.new()
	_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_button.offset_left = 32
	_button.offset_right = -32
	_button.offset_top = -120
	_button.offset_bottom = -32
	_button.add_theme_font_size_override("font_size", 28)
	_button.pressed.connect(_on_button)
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
	b.custom_minimum_size = Vector2(0, 18)
	b.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	b.add_theme_stylebox_override("fill", fill)
	return b


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

extends CanvasLayer
## HUD. GameState·Economy·Net 시그널만 구독. 게임 오브젝트 직접 참조 없음.

const INK := Color(0.16, 0.18, 0.24)
const PANEL_BG := Color(0.984, 0.969, 0.933, 0.78)  # UiKit.CREAM_PANEL
const BAR_BG := Color(0, 0, 0, 0.12)
const ACCENT := Color(0.98, 0.70, 0.20)
const RADIUS := 14
const TOAST_SEC := 1.6
const IconsScript := preload("res://scripts/icons.gd")
const UiKit := preload("res://scripts/ui_kit.gd")
const HexButtonScript := preload("res://scripts/hex_button.gd")
const HERO_BUTTON := 104  # [영웅] 6각 버튼 한 변(px). 아래 큰 버튼 위 왼쪽

var hero_panel  # 영웅 창(hero_panel.gd). main이 넣는다
var hero_button: Button

var _stage_label: Label
var _castle_bar: ProgressBar
var _gate_bars: Array = []
var _center: Label
var _button: Button
var _chips := {}  # 아이콘 kind(gold·wood·stone·food) → 숫자 Label
var _chip_row: Control
var _banner: Control  # 온라인 띠(아래 버튼 위): 끊김 "서버 연결 중…" + 웹 비영구 저장소 경고
var _link_label: Label
var _storage_label: Label
var _toast: Label  # 짧은 알림("연결 대기 중")
var _toast_left := 0.0


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
	panel.add_theme_stylebox_override("panel", UiKit.panel(PANEL_BG, 12.0, 12))
	root.add_child(panel)
	panel.add_child(top)
	_stage_label = Label.new()
	_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_label.add_theme_font_size_override("font_size", 36)
	_stage_label.add_theme_color_override("font_color", INK)
	_stage_label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))  # 제목: 외곽선
	_stage_label.add_theme_constant_override("outline_size", 6)
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
	UiKit.apply_button(_button, ACCENT, 18.0)
	root.add_child(_button)
	hero_button = HexButtonScript.new()
	hero_button.label = "영웅"
	hero_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hero_button.offset_left = 32
	hero_button.offset_right = 32 + HERO_BUTTON
	hero_button.offset_top = -132 - HERO_BUTTON  # 큰 버튼(-120..-32) 위 12px
	hero_button.offset_bottom = -132
	hero_button.pressed.connect(func(): if hero_panel != null: hero_panel.open())
	root.add_child(hero_button)
	_build_link_ui()

	GameState.mode_changed.connect(_on_mode_changed)
	GameState.castle_hp_changed.connect(_on_castle_hp)
	GameState.gate_hp_changed.connect(_on_gate_hp)
	GameState.stage_cleared.connect(_on_cleared)
	GameState.stage_failed.connect(_on_failed)
	_on_castle_hp(GameState.castle_hp, GameState.castle_hp_max)
	for side in 4:
		_on_gate_hp(side, GameState.gate_hp[side], GameState.gate_hp_max)
	_on_mode_changed(GameState.mode)


func _process(delta: float) -> void:
	if GameState.mode == GameState.Mode.COUNTDOWN:
		_center.text = str(ceili(GameState.countdown_left()))
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.modulate.a = clampf(_toast_left / 0.4, 0.0, 1.0)  # 마지막 0.4초에 사라진다
		_toast.visible = _toast_left > 0.0


func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(0, 16)
	b.show_percentage = false
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.apply_bar(b, color)
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
	_chip_row = row
	for kind in IconsScript.KINDS:
		var chip := PanelContainer.new()
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_theme_stylebox_override("panel", UiKit.panel(PANEL_BG, 10.0, 8))
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


## 온라인 알림: 아래 버튼 바로 위 띠(상단 자원 칩을 가리지 않는다) — 끊기면 "서버 연결 중…", 웹 저장소가 영구가 아니면
## 경고 한 줄(게임은 계속). 끊긴 동안 수집·판매 탭은 띠 위 짧은 알림. 거래 창(층 2) 위 층 3, 입력은 통과.
func _build_link_ui() -> void:
	var top := CanvasLayer.new()
	top.layer = 3
	add_child(top)
	var band := PanelContainer.new()
	band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	band.offset_left = 32
	band.offset_right = -32
	band.offset_top = -132  # 아래 버튼(-120..-32) 위 12px에서
	band.offset_bottom = -132
	band.grow_vertical = Control.GROW_DIRECTION_BEGIN  # 내용 높이만큼 위로 자란다
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_theme_stylebox_override("panel", UiKit.panel(Color(INK, 0.86), 10.0, 10, 0.05))
	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(lines)
	_link_label = _band_label("서버 연결 중…", 26)
	lines.add_child(_link_label)
	_storage_label = _band_label(Net.STORAGE_TEXT, 20)
	_storage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.add_child(_storage_label)
	top.add_child(band)
	_banner = band
	_update_band()
	Net.connected.connect(_update_band)
	Net.disconnected.connect(_update_band)
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -320
	_toast.offset_right = 320
	_toast.offset_top = -330  # 띠(버튼 위 -132에서 위로 두 줄까지) 위
	_toast.offset_bottom = -280
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 32)
	_toast.add_theme_color_override("font_color", Color.WHITE)
	_toast.add_theme_color_override("font_outline_color", Color(INK, 0.85))
	_toast.add_theme_constant_override("outline_size", 14)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	top.add_child(_toast)
	Economy.notice.connect(_on_notice)


func _band_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	return l


func _update_band() -> void:
	_link_label.visible = Net.is_online() and not Net.up
	_storage_label.visible = Net.is_online() and not Net.storage_persistent
	_banner.visible = _link_label.visible or _storage_label.visible


func _on_notice(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast.visible = true
	_toast_left = TOAST_SEC


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

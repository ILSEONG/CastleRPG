extends CanvasLayer
## HUD. GameState·Economy·Net 시그널만 구독. 게임 오브젝트 직접 참조 없음(성문 막대 탭은 gate_tapped로 알리고 main이 카메라를 옮긴다).
## 상단 스테이지 패널(개정 12-2): 첫 줄 왼쪽 "스테이지 N"(_title_box — 방치 무적 표시가 그 옆에 붙는다), 오른쪽 진행 버튼.
## 그 아래 성 막대("성" + 숫자)와 성문 막대 4개(2×2: 나침반 삼각형 + 북·동·남·서 + 숫자, 피해 때 테두리 번쩍임, 부서지면 회색 "파괴").
## 하단에는 탭 바만 있다(끊김 띠·알림은 그 위).

const INK := Color(0.16, 0.18, 0.24)
const PANEL_BG := Color(0.984, 0.969, 0.933, 0.78)  # UiKit.CREAM_PANEL
const ACCENT := Color(0.98, 0.70, 0.20)
const TOAST_SEC := 1.6
const IconsScript := preload("res://scripts/icons.gd")
const UiKit := preload("res://scripts/ui_kit.gd")
const Formation := preload("res://scripts/formation.gd")
const CameraRig := preload("res://scripts/camera_rig.gd")
const TAB_BAR_H := 104  # 하단 탭 바 높이(tab_bar.gd, 개정 11 §2.3)
const STAGE_BUTTON := Vector2(196, 64)  # 상단 스테이지 버튼(개정 12-2 §1)
const BAND_BOTTOM := -(TAB_BAR_H + 12)  # 끊김 띠는 탭 바 위 12px에서 위로 자란다
const BAR_H := 24
const CASTLE_COLOR := Color(0.95, 0.75, 0.2)
const GATE_COLOR := Color(0.55, 0.6, 0.7)
const BROKEN_GREY := Color(0.40, 0.40, 0.43)
const FLASH_RED := Color(0.95, 0.18, 0.12)
const FLASH_SEC := 0.3
const CASTLE := -1  # _hp 키: 성(성문은 면 0..3)

signal gate_tapped(side: int)

var _stage_label: Label
var _title_box: HBoxContainer  # 첫 줄 왼쪽: 스테이지 글자 + (개정 12 §3) 방치 무적 표시 자리
var _castle_bar: ProgressBar
var _gate_bars: Array = []
var _gate_tiles: Array = []  # side -> 성문 막대 줄(탭하면 gate_tapped)
var _hp := {}  # CASTLE·면 → {bar, num, flash: 테두리 번쩍임 Control, left: 남은 번쩍임 초, last: 지난 HP}
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
	var head := HBoxContainer.new()  # 첫 줄: 왼쪽 스테이지 글자(+ 방치 무적 표시), 오른쪽 진행 버튼
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(head)
	_title_box = HBoxContainer.new()
	_title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_box.add_theme_constant_override("separation", 8)
	head.add_child(_title_box)
	_stage_label = Label.new()
	_stage_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stage_label.add_theme_font_size_override("font_size", 36)
	_stage_label.add_theme_color_override("font_color", INK)
	_stage_label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))  # 제목: 외곽선
	_stage_label.add_theme_constant_override("outline_size", 6)
	_title_box.add_child(_stage_label)
	_button = Button.new()
	_button.custom_minimum_size = STAGE_BUTTON
	_button.focus_mode = Control.FOCUS_NONE
	_button.add_theme_font_size_override("font_size", 28)
	_button.pressed.connect(_on_button)
	UiKit.apply_button(_button, UiKit.AMBER, 14.0)
	head.add_child(_button)
	var castle_row := HBoxContainer.new()
	castle_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	castle_row.add_theme_constant_override("separation", 6)
	top.add_child(castle_row)
	var castle_name := _side_name("성")
	castle_name.custom_minimum_size.x = 52  # 성문 줄의 나침반 + 글자 폭에 맞춘다
	castle_row.add_child(castle_name)
	_castle_bar = _hp_bar(CASTLE, CASTLE_COLOR)
	castle_row.add_child(_castle_bar)
	var gates := GridContainer.new()
	gates.columns = 2
	gates.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gates.add_theme_constant_override("h_separation", 12)
	gates.add_theme_constant_override("v_separation", 6)
	top.add_child(gates)
	for side in 4:
		var tile := _gate_tile(side)
		gates.add_child(tile)
		_gate_tiles.append(tile)
		_gate_bars.append(_hp[side].bar)

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
	for e in _hp.values():
		if e.left > 0.0:
			e.left -= delta
			e.flash.modulate.a = clampf(e.left / FLASH_SEC, 0.0, 1.0)
			e.flash.visible = e.left > 0.0


## HP 막대(키 CASTLE 또는 면): 안에 "1,200 / 1,600" 숫자(작게, 외곽선), 위에 피해 때 번쩍이는 빨간 테두리.
func _hp_bar(key: int, color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(0, BAR_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.show_percentage = false
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.apply_bar(b, color)
	var num := Label.new()
	num.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num.add_theme_font_size_override("font_size", 15)
	num.add_theme_color_override("font_color", Color.WHITE)
	num.add_theme_color_override("font_outline_color", Color(INK, 0.9))
	num.add_theme_constant_override("outline_size", 5)
	b.add_child(num)
	var flash := Control.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.visible = false
	flash.draw.connect(func():
		var pts := UiKit.LowpolyBox.octagon(Rect2(Vector2.ZERO, flash.size), 4.0)
		pts.append(pts[0])
		flash.draw_polyline(pts, FLASH_RED, 3.0))
	b.add_child(flash)
	_hp[key] = {"bar": b, "num": num, "flash": flash, "left": 0.0, "last": -1.0, "color": color}
	return b


## 성문 한 칸(탭 → gate_tapped): 나침반 삼각형(화면에서 그 성문 쪽) + 방향 글자 + HP 막대.
func _gate_tile(side: int) -> Button:
	var tile := Button.new()
	tile.flat = true
	tile.focus_mode = Control.FOCUS_NONE
	tile.custom_minimum_size = Vector2(0, BAR_H + 8)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.pressed.connect(func(): gate_tapped.emit(side))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	tile.add_child(row)
	var arrow := Control.new()
	arrow.custom_minimum_size = Vector2(22, 22)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.draw.connect(_draw_compass.bind(arrow, compass_dir(side)))
	row.add_child(arrow)
	row.add_child(_side_name(Formation.SIDE_NAMES[side]))
	row.add_child(_hp_bar(side, GATE_COLOR))
	return tile


func _side_name(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", INK)
	return l


## 면 side의 성문이 화면에서 성 가운데로부터 놓인 방향(단위 벡터, 화면 y 아래 +). 카메라 요는 고정(CameraRig.YAW_DEG).
static func compass_dir(side: int) -> Vector2:
	var yaw := deg_to_rad(CameraRig.YAW_DEG)
	var d: Vector3 = Formation.SIDE_DIR[side]
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var ahead := Vector3(-sin(yaw), 0, -cos(yaw))  # 화면 위쪽이 보는 바닥 방향
	return Vector2(d.dot(right), -d.dot(ahead)).normalized()


## 각진 나침반 화살: dir을 가리키는 삼각형, 왼쪽 반은 밝게·오른쪽 반은 어둡게(면 분할).
func _draw_compass(ci: Control, dir: Vector2) -> void:
	var c := ci.size / 2.0
	var r := minf(c.x, c.y)
	var n := Vector2(-dir.y, dir.x)
	var tip := c + dir * r
	var back := c - dir * r * 0.55
	var a := back + n * r * 0.75
	var b := back - n * r * 0.75
	ci.draw_colored_polygon(PackedVector2Array([tip, a, c - dir * r * 0.25]), ACCENT.lightened(0.15))
	ci.draw_colored_polygon(PackedVector2Array([tip, c - dir * r * 0.25, b]), ACCENT.darkened(0.2))
	ci.draw_polyline(PackedVector2Array([tip, a, c - dir * r * 0.25, b, tip]), Color(INK, 0.85), 1.5)


func _on_castle_hp(hp: float, hp_max: float) -> void:
	_set_hp(CASTLE, hp, hp_max)


func _on_gate_hp(side: int, hp: float, hp_max: float) -> void:
	_set_hp(side, hp, hp_max)


## 막대 값·숫자. 줄면(피해) 테두리가 FLASH_SEC 동안 빨갛게 번쩍인다. 성문이 0이면 막대 전체가 회색이고 "파괴".
func _set_hp(key: int, hp: float, hp_max: float) -> void:
	var e: Dictionary = _hp[key]
	var b: ProgressBar = e.bar
	b.max_value = hp_max
	b.value = hp
	if e.last >= 0.0 and hp < e.last:
		e.left = FLASH_SEC
		e.flash.modulate.a = 1.0
		e.flash.visible = true
	e.last = hp
	var broken := key != CASTLE and hp <= 0.0
	e.num.text = "파괴" if broken else "%s / %s" % [UiKit.commas(ceili(hp)), UiKit.commas(roundi(hp_max))]
	b.add_theme_stylebox_override("background", UiKit.bar(BROKEN_GREY).fill if broken else UiKit.bar(e.color).background)


func _on_cleared(stage: int) -> void:
	_center.text = "스테이지 %d 클리어" % stage


func _on_failed(_stage: int) -> void:
	_center.text = "패배"


func _on_mode_changed(mode: int) -> void:
	_stage_label.text = "스테이지 %d" % GameState.stage
	if mode == GameState.Mode.IDLE or mode == GameState.Mode.STAGE:
		_center.text = ""
	_refresh_button()


## 대기 "▶ 진행" → 스테이지 시작. 진행 중 "중지 예약"(이번 스테이지 후 중지) ↔ "예약 취소". 결과 중엔 끈다.
func _refresh_button() -> void:
	if GameState.mode == GameState.Mode.IDLE:
		_button.text = "▶ 진행"
		_button.disabled = false
	elif GameState.mode == GameState.Mode.RESULT:
		_button.disabled = true
	else:
		_button.text = "예약 취소" if GameState.stop_requested else "중지 예약"
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


## 온라인 알림: 탭 바 바로 위 띠(상단 자원 칩·스테이지 패널·탭 바를 가리지 않는다) — 끊기면 "서버 연결 중…", 웹 저장소가 영구가 아니면
## 경고 한 줄(게임은 계속). 끊긴 동안 수집·판매 탭은 띠 위 짧은 알림. 거래 창(층 2) 위 층 3, 입력은 통과.
func _build_link_ui() -> void:
	var top := CanvasLayer.new()
	top.layer = 3
	add_child(top)
	var band := PanelContainer.new()
	band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	band.offset_left = 32
	band.offset_right = -32
	band.offset_top = BAND_BOTTOM  # 탭 바 위 12px에서
	band.offset_bottom = BAND_BOTTOM
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
	_toast.offset_top = BAND_BOTTOM - 198  # 띠(탭 바 위에서 위로 두 줄까지) 위
	_toast.offset_bottom = BAND_BOTTOM - 148
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
	return UiKit.commas(n)

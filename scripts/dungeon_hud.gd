extends CanvasLayer
## 던전 전투 화면(개정 18 §8). 위 패널: 던전 이름·단계, 남은 시간, [포기](싸우는 중만), 보스 큰 HP 막대(이름·숫자 — 나오기 전엔 "남은 적 n").
## 아래: 출전 영웅 띠(피규어 + HP 막대, 쓰러지면 흐리게). 가운데 띠("승리!"·"결과 확인 중…")와 짧은 알림(Economy.notice — 성 HUD는 트리 밖).
## 결과 화면(show_result): 어두운 배경 + 가운데 패널 — "승리!"/"패배"(실패면 그 이유), 던전·단계, 보상(골드 / 장비 칸: 등급 테두리·이름·Lv,
## 패배면 "보상 없음 · 열쇠는 그대로"), [나가기]·[다시]·[다음 단계](이겼고 최고 + 1 이하일 때), 체크 둘 "현재 단계 자동 반복"·
## "다음 단계 자동 도전"(서로 배타, Fever.dungeon_auto), 자동 상태 한 줄("2초 뒤 자동 도전"·"자동 도전을 멈췄습니다").

const UiKit := preload("res://scripts/ui_kit.gd")
const MainHud := preload("res://scripts/hud.gd")
const GameData := preload("res://scripts/game_data.gd")
const IconsScript := preload("res://scripts/icons.gd")
const ItemTileScript := preload("res://scripts/item_tile.gd")
const BagPanel := preload("res://scripts/bag_panel.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const NAMES := {"gold": "골드 던전", "equip": "장비 던전"}
const BOSS_NAMES := {"goblin_king": "왕고블린", "death_knight": "데스나이트"}
const FACE_PX := 96.0
const TILE_PX := 96.0
const TOAST_SEC := 1.6
const WIN_GOLD := Color("C8901A")
const LOSS_RED := Color(0.78, 0.22, 0.18)
const BOSS_RED := Color(0.86, 0.24, 0.2)
const HP_GREEN := Color(0.35, 0.8, 0.4)

var dungeon  # dungeon.gd
var title_label: Label
var time_label: Label
var give_up_button: Button
var boss_label: Label
var boss_bar: ProgressBar
var banner: Label
var toast: Label
var strip: Array = []  # [{hero, face, bar}]
var result_layer: Control  # 결과 화면(어두운 배경 + 패널)
var result_title: Label
var result_sub: Label
var reward_box: HBoxContainer
var reward_tiles: Array = []  # 장비 칸(테스트용)
var gold_label: Label  # 골드 보상 글자(없으면 null)
var next_button: Button
var again_button: Button
var exit_button: Button
var auto_next_box: Button
var auto_repeat_box: Button
var auto_label: Label

var _toast_left := 0.0


func _ready() -> void:
	layer = 1
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 빈 곳은 카메라(회전·줌)로
	add_child(root)
	_build_top(root)
	_build_strip(root)
	banner = Label.new()
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.offset_top = 360
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 64)
	banner.add_theme_color_override("font_color", Color.WHITE)
	banner.add_theme_color_override("font_outline_color", MainHud.INK)
	banner.add_theme_constant_override("outline_size", 12)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(banner)
	toast = Label.new()
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast.offset_top = 300
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 28)
	toast.add_theme_color_override("font_color", Color.WHITE)
	toast.add_theme_color_override("font_outline_color", MainHud.INK)
	toast.add_theme_constant_override("outline_size", 8)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.visible = false
	root.add_child(toast)
	_build_result(root)
	Economy.notice.connect(_on_notice)
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
	title_label = _label("", 32, MainHud.INK)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)
	time_label = _label("", 32, MainHud.INK)
	row.add_child(time_label)
	give_up_button = Button.new()
	give_up_button.text = "포기"
	give_up_button.custom_minimum_size = Vector2(110, 56)
	give_up_button.add_theme_font_size_override("font_size", 26)
	UiKit.apply_button(give_up_button, UiKit.STEEL, 12.0)
	give_up_button.pressed.connect(func(): dungeon.give_up())
	row.add_child(give_up_button)
	boss_label = _label("", 22, MainHud.INK)
	box.add_child(boss_label)
	boss_bar = ProgressBar.new()
	boss_bar.custom_minimum_size = Vector2(0, 26)
	boss_bar.show_percentage = false
	boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.apply_bar(boss_bar, BOSS_RED)
	box.add_child(boss_bar)


func _build_strip(root: Control) -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_bottom = -20
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(row)
	for h in dungeon.heroes:
		var cell := VBoxContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_theme_constant_override("separation", 4)
		var face := Control.new()
		face.custom_minimum_size = Vector2(FACE_PX, FACE_PX)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.draw.connect(_draw_face.bind(face, h.def))
		if PortraitsScript.current != null:  # 피규어 렌더가 끝나면 다시 그린다
			PortraitsScript.current.portrait_ready.connect(face.queue_redraw.unbind(1))
		cell.add_child(face)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(FACE_PX, 14)
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiKit.apply_bar(bar, HP_GREEN)
		cell.add_child(bar)
		row.add_child(cell)
		strip.append({"hero": h, "face": face, "bar": bar})


## 피규어 칸: 등급 색 8각 바탕 + 피규어(렌더 전엔 자리표시).
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
	result_layer.mouse_filter = Control.MOUSE_FILTER_STOP  # 결과 화면에서는 뒤 카메라를 막는다
	result_layer.visible = false
	root.add_child(result_layer)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(668, 0)
	panel.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM_DIALOG, 18.0, 24))
	result_layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	result_title = _label("", 56, WIN_GOLD)
	result_title.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	result_title.add_theme_constant_override("outline_size", 8)
	box.add_child(result_title)
	result_sub = _label("", 26, MainHud.INK)
	box.add_child(result_sub)
	reward_box = HBoxContainer.new()
	reward_box.alignment = BoxContainer.ALIGNMENT_CENTER
	reward_box.add_theme_constant_override("separation", 8)
	reward_box.custom_minimum_size = Vector2(0, 150)
	box.add_child(reward_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	next_button = _button("다음 단계", MainHud.ACCENT)
	next_button.pressed.connect(func(): dungeon.next_level())
	again_button = _button("다시", UiKit.AMBER)
	again_button.pressed.connect(func(): dungeon.retry())
	exit_button = _button("나가기", UiKit.STEEL)
	exit_button.pressed.connect(func(): dungeon.leave())
	for b in [exit_button, again_button, next_button]:  # 왼쪽부터 나가기·다시·다음 단계(사용자 요청)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	var checks := HBoxContainer.new()
	checks.alignment = BoxContainer.ALIGNMENT_CENTER
	checks.add_theme_constant_override("separation", 16)
	box.add_child(checks)
	auto_next_box = _checkbox("다음 단계 자동 도전")
	auto_next_box.toggled.connect(_on_auto.bind("next"))
	auto_repeat_box = _checkbox("현재 단계 자동 반복")
	auto_repeat_box.toggled.connect(_on_auto.bind("repeat"))
	checks.add_child(auto_repeat_box)  # 왼쪽 현재 단계 자동 반복, 오른쪽 다음 단계 자동 도전(사용자 요청)
	checks.add_child(auto_next_box)
	auto_label = _label("", 22, MainHud.INK.lightened(0.25))
	box.add_child(auto_label)


## 결과 화면을 채워 보인다(dungeon.result·run).
func show_result() -> void:
	var res: Dictionary = dungeon.result
	var win: bool = res.get("win", false)
	var err := str(res.get("error", ""))
	result_title.text = "승리!" if win else ("패배" if err == "" else Economy.DUNGEON_TEXT.get(err, Economy.DUNGEON_FAIL_TEXT))
	result_title.add_theme_color_override("font_color", WIN_GOLD if win else LOSS_RED)
	result_title.add_theme_font_size_override("font_size", 56 if err == "" else 32)
	result_sub.text = "%s %d단계" % [NAMES.get(dungeon.run.type, ""), int(dungeon.run.level)]
	for c in reward_box.get_children():
		reward_box.remove_child(c)
		c.queue_free()
	reward_tiles.clear()
	gold_label = null
	var rw: Dictionary = res.get("rewards", {})
	if rw.has("gold_tenths"):
		var icon = IconsScript.new()
		icon.kind = "gold"
		icon.custom_minimum_size = Vector2(72, 72)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		reward_box.add_child(icon)
		gold_label = _label("+%s 골드" % UiKit.commas(floori(rw.gold_tenths / 10.0)), 40, WIN_GOLD.darkened(0.2))
		reward_box.add_child(gold_label)
	for it in rw.get("items", []):
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		cell.custom_minimum_size = Vector2(118, 0)
		var tile = ItemTileScript.new()
		tile.custom_minimum_size = Vector2(TILE_PX, TILE_PX)
		tile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tile.set_item(BagPanel.item_kind(it), it.grade)
		cell.add_child(tile)
		cell.add_child(_label("%s %s" % [it.grade, BagPanel.ITEM_NAMES.get(BagPanel.item_kind(it), "")], 18, MainHud.INK))
		cell.add_child(_label("Lv %d" % int(it.level), 16, MainHud.INK.lightened(0.3)))
		reward_box.add_child(cell)
		reward_tiles.append(tile)
	if not win:
		reward_box.add_child(_label("보상 없음 · 열쇠는 그대로", 26, MainHud.INK.lightened(0.25)))
	result_layer.visible = true
	refresh_result()


## 버튼·체크·자동 상태 줄.
func refresh_result() -> void:
	if not result_layer.visible:
		return
	next_button.visible = dungeon.can_next()
	for b in [next_button, again_button]:
		b.disabled = dungeon.starting
	auto_next_box.set_pressed_no_signal(Fever.dungeon_auto == "next")
	auto_repeat_box.set_pressed_no_signal(Fever.dungeon_auto == "repeat")
	for b in [auto_next_box, auto_repeat_box]:
		b.get_child(0).queue_redraw()  # 체크 상자 그림(set_pressed_no_signal은 toggled를 안 낸다)
	_update_auto_label()


func _update_auto_label() -> void:
	if Fever.dungeon_auto == "":
		auto_label.text = ""
	elif dungeon.auto_halted:
		auto_label.text = "자동 도전을 멈췄습니다"
	elif dungeon.starting:
		auto_label.text = "다음 도전 시작 중…"
	elif dungeon.auto_left >= 0.0:
		auto_label.text = "%d초 뒤 자동 도전" % ceili(dungeon.auto_left)
	else:
		auto_label.text = ""


## 체크 둘은 배타: 하나를 켜면 다른 하나는 꺼진다. 끄면 자동 없음.
func _on_auto(on: bool, mode: String) -> void:
	dungeon.set_auto(mode if on else "")


func _process(delta: float) -> void:
	_update()
	if _toast_left > 0.0:
		_toast_left -= delta
		toast.modulate.a = clampf(_toast_left / 0.4, 0.0, 1.0)
		toast.visible = _toast_left > 0.0


func _update() -> void:
	var d = dungeon
	title_label.text = "%s %d단계" % [NAMES.get(d.run.type, ""), int(d.run.level)]
	time_label.text = UiKit.clock(maxf(0.0, d.time_limit() - d.clock))
	give_up_button.visible = d.phase == d.Phase.FIGHT
	var b = d.boss
	boss_bar.visible = b != null
	if b != null:
		boss_bar.value = b.hp_ratio() * 100.0
		boss_label.text = "%s  %s / %s · 남은 적 %d" % [BOSS_NAMES.get(b.kind, b.kind), UiKit.commas(ceili(b.hp)), UiKit.commas(roundi(b.hp_max)), d.enemies_left()]
	else:
		boss_label.text = "남은 적 %d" % d.enemies_left()
	if d.phase == d.Phase.WON or d.phase == d.Phase.LOOT:
		banner.text = "승리!"
	elif d.phase == d.Phase.REPORT:
		banner.text = "결과 확인 중…"
	else:
		banner.text = ""
	for s in strip:
		s.bar.value = s.hero.hp_ratio() * 100.0
		s.face.modulate.a = 1.0 if s.hero.is_alive() else 0.35
	if result_layer.visible:
		_update_auto_label()


func _on_notice(text: String) -> void:
	toast.text = text
	toast.modulate.a = 1.0
	toast.visible = true
	_toast_left = TOAST_SEC


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 72)
	b.add_theme_font_size_override("font_size", 28)
	UiKit.apply_button(b, color, 14.0)
	return b


## UiKit 체크박스, 글자 칸만 넓힌다(긴 이름).
func _checkbox(text: String) -> Button:
	var b := UiKit.checkbox(text)
	b.custom_minimum_size = Vector2(290, 64)
	var l: Label = b.get_child(1)
	l.size = Vector2(244, 64)
	return b

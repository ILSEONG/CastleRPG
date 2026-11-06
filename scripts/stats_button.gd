extends CanvasLayer
## [통계] 버튼 + 전투 통계 창(사용자 2026-11-02 "스테이지를 밀때, 각 던전, PVP 등 방치할때 제외하고 왼쪽 하단에 통계버튼을 만들어줘
## 통계는 가한 피해량, 받은 피해량, 치유량을 볼 수 있게"). 값은 battle_stats.gd가 모은다.
## 참고한 게임: AFK 아레나(전투 통계 — 탭마다 영웅별 막대·수치, 양 팀), 세븐나이츠 키우기(전투 정보 — 영웅별 피해 막대),
## 로스트아크(피해 미터 — 몫 %). 우리 판: 탭 [가한 피해][받은 피해][치유량], 줄 = 초상화 + 이름 + 막대(그 탭 1등 대비) + 수치 + 팀 몫 %,
## 큰 값 순. 상대 영웅이 있는 전투(PVP·길드전)는 [우리 팀][상대 팀]. 창이 열려 있어도 전투는 그대로 흐르고 값은 실시간으로 바뀐다.
## 자리: 왼쪽 아래 배속 버튼 바로 위(성 화면은 [핫딜]이 떠 있으면 그 위). 배속 버튼이 없는 전투(길드전·파티)는 배속 버튼 자리.
## 성 화면(castle = true): 대기(방치) 중에는 숨긴다(배속 버튼과 같은 규칙) — 스테이지가 시작될 때마다 통계를 비운다.
## 전투 장면(던전·PVP·드래곤·길드전·파티): 장면이 열릴 때 비운다.
## 스타일: 플랫 양피지 두루마리 창(UiKit.scroll), 금색 강조 없음.

const UiKit := preload("res://scripts/ui_kit.gd")
const Lang := preload("res://scripts/lang.gd")
const BattleStats := preload("res://scripts/battle_stats.gd")
const SpeedScript := preload("res://scripts/speed_button.gd")
const AutoScript := preload("res://scripts/skill_auto_button.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const SIZE := Vector2(84, 84)
const SIDE := 16.0
const GAP := 12.0
const BOTTOM_GAP := 20.0
const COLOR := Color(0.30, 0.34, 0.46)  # 배속 버튼(끔)과 같은 강철색
const KINDS := ["dealt", "taken", "healed"]
const BAR_COLORS := {"dealt": Color(0.82, 0.33, 0.27), "taken": Color(0.36, 0.50, 0.72), "healed": Color(0.33, 0.66, 0.36)}
const ROW_H := 72.0
const MARGIN_Y := 120.0
const REFRESH := 0.3  # 창이 열려 있을 때 다시 그리는 간격(실제 초)

var castle := false
var speed  # speed_button.gd(그 위로)
var hot  # hot_deal.gd(성 화면 — 떠 있으면 그 위로)
var button: Button
var popup: Control  # 창(어두운 막 + 두루마리)
var list: VBoxContainer  # 테스트가 읽는다: 줄마다 meta "hero_id"·"value"
var total_label: Label
var kind := "dealt"
var team := 0
var kind_buttons := {}
var team_buttons := {}
var _team_row: HBoxContainer
var _layer: CanvasLayer
var _face: Control
var _box: PanelContainer  # 두루마리(줄 수에 맞춰 높이, 화면 가운데)
var _shown_ver := -1
var _refresh_t := 0.0
var _looks := 0
var _auto


func _ready() -> void:
	layer = 1
	button = Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = SIZE
	button.size = SIZE
	UiKit.apply_button(button, COLOR, 12.0)
	_face = Control.new()
	_face.size = SIZE
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.draw.connect(_draw_face)
	button.add_child(_face)
	button.pressed.connect(open)
	add_child(button)
	_build_popup()
	if castle:
		var gs := get_node_or_null("/root/GameState")
		if gs != null and not gs.mode_changed.is_connected(_on_mode):
			gs.mode_changed.connect(_on_mode)
	_place()
	_sync_visible()


func _enter_tree() -> void:
	if not castle:
		BattleStats.reset("arena")  # 전투 장면마다 새로(다음 도전도 새 장면)


func _on_mode(mode: int) -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs != null and mode == gs.Mode.STAGE:
		BattleStats.reset("castle")  # 스테이지마다 새로
		_shown_ver = -1
	if gs != null and mode == gs.Mode.IDLE:
		close()


func scope() -> String:
	return "castle" if castle else "arena"


func _process(delta: float) -> void:
	_sync_visible()
	_place()
	if popup.visible:
		_refresh_t -= delta / maxf(0.01, Engine.time_scale)
		if _refresh_t <= 0.0 and _shown_ver != BattleStats.version:
			_refresh_t = REFRESH
			refresh()


## 성 화면은 배속 버튼이 보일 때만(대기·방치 중 숨김, 가이드 초반 숨김과 같다). 전투 장면은 늘.
func _sync_visible() -> void:
	var on := true
	if castle:
		on = speed != null and is_instance_valid(speed) and speed.button != null and speed.button.visible
	button.visible = on
	if not on and popup.visible:
		close()


func _place() -> void:
	var vh := get_viewport().get_visible_rect().size.y
	var top: float
	if speed != null and is_instance_valid(speed) and speed.button != null:
		top = speed.button.position.y
		if castle and hot != null and is_instance_valid(hot) and hot.hud_button != null and hot.hud_button.visible:
			top = hot.hud_button.position.y  # [핫딜] 위
		button.position = Vector2(SIDE, top - GAP - SIZE.y)
		return
	var a = _battle_auto()  # 배속 버튼이 없는 전투: 배속 버튼 자리(오른쪽 [스킬 AUTO]와 같은 높이)
	var ab: float = a.button.position.y + a.button.size.y if a != null and a.button.visible else vh - BOTTOM_GAP
	button.position = Vector2(SIDE, ab - SIZE.y)


func _battle_auto():
	if _auto != null and is_instance_valid(_auto):
		return _auto
	var p := get_parent()
	if p != null and _looks < 30:
		_looks += 1
		_auto = _find_script(p, AutoScript)
		if speed == null:
			speed = _find_script(p, SpeedScript)
	return _auto


func _find_script(n: Node, s: Script):
	for c in n.get_children():
		if c.get_script() == s:
			return c
		var f = _find_script(c, s)
		if f != null:
			return f
	return null


func _draw_face() -> void:
	var ink := Color(UiKit.INK, 0.85)
	var col := Color(0.86, 0.89, 0.95)
	# 막대그래프 그림(막대 셋)
	var base_y := 38.0
	var w := 10.0
	var hs := [12.0, 22.0, 17.0]
	for k in 3:
		var x := SIZE.x / 2.0 - w * 1.5 - 3.0 + k * (w + 3.0)
		var r := Rect2(x, base_y - hs[k], w, hs[k])
		_face.draw_rect(r.grow(2.0), ink)
		_face.draw_rect(r, col)
	_face.draw_string_outline(FONT, Vector2(0, 68), Lang.t("stats_button.draw_face"), HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 20, 5, ink)
	_face.draw_string(FONT, Vector2(0, 68), Lang.t("stats_button.draw_face"), HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 20, col)


# --- 창 ---

func _build_popup() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 6  # HUD·초상화 줄 위
	add_child(_layer)
	popup = Control.new()
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	popup.visible = false
	_layer.add_child(popup)
	var dim := Button.new()  # 바깥을 누르면 닫힌다
	dim.flat = true
	dim.focus_mode = Control.FOCUS_NONE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	for st in ["normal", "hover", "pressed", "focus"]:
		dim.add_theme_stylebox_override(st, sb)
	dim.pressed.connect(close)
	popup.add_child(dim)
	var box := PanelContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 20
	box.offset_right = -20
	_box = box
	box.add_theme_stylebox_override("panel", UiKit.scroll())
	popup.add_child(box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	box.add_child(col)
	var title := _label(Lang.t("stats_button.build_popup"), 30)
	col.add_child(title)
	_team_row = HBoxContainer.new()
	_team_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_team_row.add_theme_constant_override("separation", 8)
	col.add_child(_team_row)
	for t in [0, 1]:
		var b := _tab_button(Lang.t("stats_button.build_popup_2") if t == 0 else Lang.t("stats_button.build_popup_3"))
		b.pressed.connect(func(): team = t; _shown_ver = -1; refresh())
		team_buttons[t] = b
		_team_row.add_child(b)
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	col.add_child(tabs)
	var names := {"dealt": Lang.t("stats_button.build_popup.dealt"), "taken": Lang.t("stats_button.build_popup.taken"), "healed": Lang.t("stats_button.build_popup.healed")}
	for k in KINDS:
		var b := _tab_button(names[k])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): kind = k; _shown_ver = -1; refresh())
		kind_buttons[k] = b
		tabs.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	total_label = _label("", 22)
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(total_label)
	UiKit.corner_x(box, close)  # 오른쪽 위 닫기 X(2026-11-05, [닫기] 대신)


func _tab_button(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 56)
	b.add_theme_font_size_override("font_size", 22)
	return b


func _label(t: String, size: int, color: Color = UiKit.INK) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func open() -> void:
	if not button.visible:
		return
	_enroll()
	team = 0
	popup.visible = true
	_shown_ver = -1
	refresh()


func close() -> void:
	if popup != null:
		popup.visible = false


## 지금 장면의 영웅을 0으로라도 넣는다(조종하는 기기 쪽 영웅만 — 파티·길드전의 남의 꼭두각시는 이 기기에서 싸우지 않는다).
func _enroll() -> void:
	for g in ["heroes", "pvp1", "war_def"]:
		for h in get_tree().get_nodes_in_group(g):
			if BattleStats.is_hero(h) and BattleStats.scope_of(h) == scope() and h.get("puppet") != true and h.is_inside_tree():
				BattleStats.enroll(h)


func refresh() -> void:
	_shown_ver = BattleStats.version
	var both := BattleStats.has_team(scope(), 1)
	_team_row.visible = both
	if not both:
		team = 0
	for t in team_buttons:
		UiKit.apply_button(team_buttons[t], UiKit.STEEL if t == team else Color(0.62, 0.58, 0.50), 12.0)
	for k in kind_buttons:
		UiKit.apply_button(kind_buttons[k], BAR_COLORS[k].darkened(0.1) if k == kind else Color(0.62, 0.58, 0.50), 12.0)
	var rows := BattleStats.list(scope(), team)
	rows.sort_custom(func(a, b): return float(a[kind]) > float(b[kind]) or (float(a[kind]) == float(b[kind]) and int(a.order) < int(b.order)))
	var top := 0.0
	var sum := 0.0
	for r in rows:
		top = maxf(top, float(r[kind]))
		sum += float(r[kind])
	for c in list.get_children():
		c.queue_free()
	if rows.is_empty():
		list.add_child(_label(Lang.t("stats_button.refresh"), 22, Color(UiKit.INK, 0.6)))
	for r in rows:
		list.add_child(_row(r, float(r[kind]), top, sum))
	total_label.text = Lang.t("stats_button.refresh_2") % UiKit.commas(int(round(sum)))
	_fit(maxi(1, rows.size()))


## 줄 수에 맞는 높이로 화면 가운데(위아래 MARGIN_Y는 늘 비운다 — 줄이 많으면 목록이 스크롤).
func _fit(n: int) -> void:
	var vh := popup.get_viewport_rect().size.y
	var want := 330.0 + (90.0 if _team_row.visible else 0.0) + n * (ROW_H + 6.0)
	var h := minf(want, vh - 2.0 * MARGIN_Y)
	_box.offset_top = (vh - h) / 2.0
	_box.offset_bottom = -(vh - h) / 2.0


func _row(r: Dictionary, v: float, top: float, sum: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, ROW_H)
	c.set_meta("hero_id", str(r.hero_id))
	c.set_meta("value", v)
	var dead := false
	var n = r.node.get_ref() if r.node is WeakRef else null
	if n != null and n.has_method("is_alive"):
		dead = not n.is_alive()
	c.draw.connect(_draw_row.bind(c, r, v, top, sum, dead))
	return c


func _draw_row(c: Control, r: Dictionary, v: float, top: float, sum: float, dead: bool) -> void:
	var w := c.size.x
	var face := Rect2(Vector2(2, 4), Vector2(ROW_H - 8, ROW_H - 8))
	var oct := LowpolyBox.octagon(face, face.size.x * 0.2)
	PortraitsScript.draw_face(c, str(r.hero_id), oct, face)
	if dead:
		c.draw_colored_polygon(oct, Color(0.1, 0.1, 0.12, 0.45))
	var rim := oct.duplicate()
	rim.append(rim[0])
	c.draw_polyline(rim, UiKit.OUTLINE, 2.0, true)
	var x0 := face.end.x + 10.0
	var ink := UiKit.INK
	c.draw_string(FONT, Vector2(x0, 28), str(r.name), HORIZONTAL_ALIGNMENT_LEFT, w * 0.45, 22, ink)
	var pct := v / sum * 100.0 if sum > 0.0 else 0.0
	c.draw_string(FONT, Vector2(x0, 28), "%s  (%d%%)" % [UiKit.commas(int(round(v))), int(round(pct))], HORIZONTAL_ALIGNMENT_RIGHT, w - x0 - 6.0, 22, ink)
	var bar := Rect2(x0, 40, w - x0 - 6.0, 18)
	c.draw_rect(bar, Color(0.55, 0.47, 0.36, 0.25))
	if top > 0.0 and v > 0.0:
		c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * v / top, bar.size.y)), BAR_COLORS[kind])
	c.draw_rect(bar, Color(UiKit.INK, 0.5), false, 1.5)

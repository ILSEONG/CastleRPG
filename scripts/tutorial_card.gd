extends CanvasLayer
## 튜토리얼 미션 카드(HUD 층, 하단 탭 바 바로 위 가로 띠). 왼쪽: "튜토리얼 n/27" + 미션 제목, 설명 두 줄, 보상 한 줄. 오른쪽 버튼 —
## 끝났으면 호박색 [보상 받기](살짝 맥동), 아니면 강철색 [바로가기](Tutorial.goto_current → main이 건물 창·탭·상인·전투를 연다).
## 제목 줄을 누르면 설명·보상을 접는다(접으면 한 줄). 건물 미션이면 그 건물 이름표 위에 통통 튀는 호박색 화살표를 그린다(tags.stacks).
## 튜토리얼이 아니면(끝남·건너뜀) 숨는다.

const UiKit := preload("res://scripts/ui_kit.gd")
const HudScript := preload("res://scripts/hud.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const SIDE := 12.0
const GAP_ABOVE_TABS := 12.0
const BUTTON_W := 168.0
const ARROW := Vector2(30, 26)  # 화살표 폭·높이(px)
const BOUNCE_PX := 8.0
const BOUNCE_HZ := 1.6

var tags  # world_tags.gd(건물 이름표 덩어리 자리). main이 넣는다
var panel: PanelContainer
var step_label: Label
var title_label: Label
var desc_label: Label
var reward_label: Label
var action_button: Button

var _collapsed := false
var _arrow: Control
var _t := 0.0


func _ready() -> void:
	layer = 1  # HUD와 같은 층(창은 2)
	_arrow = Control.new()
	_arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.draw.connect(_draw_arrow)
	add_child(_arrow)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = SIDE
	panel.offset_right = -SIDE
	panel.offset_bottom = -(HudScript.TAB_BAR_H + GAP_ABOVE_TABS)
	panel.offset_top = panel.offset_bottom
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN  # 내용 높이만큼 위로 자란다
	panel.mouse_filter = Control.MOUSE_FILTER_STOP  # 카드 위 탭이 뒤 월드로 새지 않게
	panel.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM_DIALOG, 12.0, 12))
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	head.gui_input.connect(_on_head_input)
	col.add_child(head)
	step_label = _label(18, UiKit.AMBER.darkened(0.35))
	step_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(step_label)
	title_label = _label(26, UiKit.INK)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(title_label)
	desc_label = _label(18, Color(UiKit.INK, 0.8))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(200, 0)
	col.add_child(desc_label)
	reward_label = _label(18, Color(0.13, 0.50, 0.24))
	reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(reward_label)
	action_button = Button.new()
	action_button.focus_mode = Control.FOCUS_NONE
	action_button.custom_minimum_size = Vector2(BUTTON_W, 64)
	action_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	action_button.add_theme_font_size_override("font_size", 24)
	action_button.pressed.connect(_on_action)
	row.add_child(action_button)
	Tutorial.changed.connect(_refresh)
	_refresh()


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _refresh() -> void:
	var m: Dictionary = Tutorial.mission()
	panel.visible = not m.is_empty()
	if m.is_empty():
		_arrow.queue_redraw()
		return
	var done: bool = Tutorial.complete()
	step_label.text = ("반복 퀘스트 %d" % (Tutorial.rep_n + 1)) if Tutorial.repeating() else "튜토리얼 %d/%d" % [Tutorial.step + 1, Tutorial.MISSIONS.size()]
	var prog: String = Tutorial.progress_text()
	title_label.text = ("✓ " if done else "") + str(m.title) + ("  " + prog if prog != "" else "")
	desc_label.text = str(m.desc)
	reward_label.text = "보상: " + Tutorial.reward_text(Tutorial.repeat_reward(m) if Tutorial.repeating() else Tutorial.reward(Tutorial.step))
	desc_label.visible = not _collapsed
	reward_label.visible = not _collapsed
	action_button.text = "보상 받기" if done else "바로가기"
	action_button.disabled = (not done and str(m.get("goto", "")) == "") or (done and Tutorial.econ != null and Tutorial.econ.quest_waiting())
	UiKit.apply_button(action_button, UiKit.AMBER if done else UiKit.STEEL, 12.0)
	panel.offset_top = panel.offset_bottom  # 높이 0에서 내용만큼 위로 자란다(grow BEGIN) — 접으면 다시 줄어든다


func _on_action() -> void:
	if Tutorial.complete():
		if Tutorial.claim() and Tutorial.online:
			_refresh()  # 응답 전 버튼을 끈다(응답이 오면 Tutorial.changed가 다시 그린다)
	else:
		Tutorial.goto_current()


func _on_head_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_collapsed = not _collapsed
		_refresh()


func _process(delta: float) -> void:
	_t += delta
	if panel.visible and Tutorial.complete():  # 보상 받기 맥동
		action_button.scale = Vector2.ONE * (1.0 + 0.04 * sin(_t * TAU * BOUNCE_HZ))
		action_button.pivot_offset = action_button.size / 2.0
	else:
		action_button.scale = Vector2.ONE
	_arrow.queue_redraw()
	var prog: String = Tutorial.progress_text() if panel.visible else ""
	if prog != "" and not title_label.text.ends_with(prog):
		_refresh()  # 처치 수가 올랐다


## 건물 미션: 그 건물 이름표 덩어리 위에 아래를 가리키는 호박색 화살표(통통 튄다).
func _draw_arrow() -> void:
	if tags == null or not panel.visible:
		return
	var id: String = Tutorial.target_building()
	if id == "":
		return
	if id == "gate":
		id = "gate:2"  # 남쪽(카메라 쪽) 문루 이름표
	tags.layout()
	var s = tags.stacks.get(id)
	if s == null:
		return
	var tip := Vector2(s.get_center().x, s.position.y - 6.0 - absf(sin(_t * PI * BOUNCE_HZ)) * BOUNCE_PX)
	var pts := PackedVector2Array([tip, tip + Vector2(-ARROW.x / 2.0, -ARROW.y), tip + Vector2(-ARROW.x / 5.0, -ARROW.y),
		tip + Vector2(-ARROW.x / 5.0, -ARROW.y * 1.8), tip + Vector2(ARROW.x / 5.0, -ARROW.y * 1.8), tip + Vector2(ARROW.x / 5.0, -ARROW.y),
		tip + Vector2(ARROW.x / 2.0, -ARROW.y)])
	_arrow.draw_colored_polygon(pts, UiKit.AMBER)
	pts.append(pts[0])
	_arrow.draw_polyline(pts, UiKit.OUTLINE, 2.0)

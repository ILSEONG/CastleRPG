extends CanvasLayer
## 튜토리얼 미션 카드(HUD 층, 하단 탭 바 바로 위 가로 띠). 왼쪽: "튜토리얼 n/27" + 미션 제목, 설명 두 줄, 보상 한 줄. 오른쪽 버튼 —
## 끝났으면 호박색 [보상 받기](살짝 맥동), 아니면 강철색 [바로가기](Tutorial.goto_current → main이 건물 창·탭·상인·전투를 연다).
## 설명·보상은 늘 보인다(사용자 2026-10-06: 접기 없음). 건물 미션이면 그 건물 이름표 위에 통통 튀는 호박색 화살표를 그린다(tags.stacks).
## 버튼 미션(탭·메뉴·HUD·창 안 버튼)이면 그 버튼(Tutorial.point_target) 테두리를 두르고 화살표로 가리킨다. 화살표는 그 버튼과 같은 층에 그려서
## 위 층의 창이 덮으면 함께 가려진다.
## 튜토리얼이 아니면(끝남·건너뜀) 숨는다. 스테이지를 미는 동안(스테이지·결과·카운트다운 — main._set_battle_ui와 같은 때)도 카드와
## 화살표를 숨기고 방치로 돌아오면 다시 보인다(사용자 2026-10-18 "스테이지 밀때는 가이드 안보이게해줘"). 미션 진행은 그동안에도 센다.

const Lang := preload("res://scripts/lang.gd")

const UiKit := preload("res://scripts/ui_kit.gd")
const HudScript := preload("res://scripts/hud.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const SIDE := 12.0
const GAP_ABOVE_TABS := 12.0
const BUTTON_W := 168.0
const ARROW := Vector2(30, 26)  # 화살표 폭·높이(px)
const BOUNCE_PX := 8.0
const BOUNCE_HZ := 1.6
const TARGET_SETTLE_FRAMES := 2  # 가리킬 버튼이 바뀐 뒤 이만큼은 지난 자리(새 버튼이 컨테이너 자리를 잡는 동안)
const CLAIM_GUARD_MS := 400  # [보상 받기] 뒤 이 시간 동안 카드 버튼 누름을 버린다(ui_window OPEN_GUARD_MS와 같은 값)

var tags  # world_tags.gd(건물 이름표 덩어리 자리). main이 넣는다
var build_button  # build_button.gd — 자리를 안 잡은 공터 미션이면 화살표가 이 버튼을 가리킨다(자유 건설)
var panel: PanelContainer
var step_label: Label
var title_label: Label
var desc_label: Label
var reward_label: Label
var action_button: Button

var _arrow: Control
var _pointer: Control  # 버튼 화살표(가리키는 버튼의 CanvasLayer로 옮겨 다닌다)
var _t := 0.0
var _claimed_ms := -100000  # 마지막으로 [보상 받기]를 누른 때
var _last_rect := Rect2()  # 화살표가 마지막으로 가리킨 자리(_draw_pointer)
var _target_id := 0  # 화살표가 가리키는 버튼(인스턴스 id)과 그 버튼을 처음 가리킨 프레임
var _target_since := 0
var tabs  # tab_bar.gd — 탭 바가 숨어 있으면(가이드 첫 전투 전) 카드가 그 자리까지 내려간다


func _ready() -> void:
	layer = 1  # HUD와 같은 층(창은 2)
	_arrow = Control.new()
	_arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.draw.connect(_draw_arrow)
	add_child(_arrow)
	_make_pointer()
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
	GameState.mode_changed.connect(func(_m): _refresh())  # 스테이지를 미는 동안은 카드·화살표를 숨긴다
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
	panel.visible = not m.is_empty() and GameState.mode == GameState.Mode.IDLE
	if not panel.visible:
		_arrow.queue_redraw()
		return
	var done: bool = Tutorial.complete()
	step_label.text = Lang.t("tutorial_card.guide_no") % Tutorial.guide_number()  # 「가이드 퀘스트 12」 — 반복 퀘스트도 번호가 이어진다(메이플스토리 키우기식, 2026-10-29)
	var prog: String = Tutorial.progress_text()
	title_label.text = ("✓ " if done else "") + str(m.title) + ("  " + prog if prog != "" else "")
	desc_label.text = Tutorial.mission_desc(m)
	reward_label.text = Lang.t("tutorial_card.refresh_3") + Tutorial.reward_text(Tutorial.repeat_reward(m) if Tutorial.repeating() else Tutorial.reward(Tutorial.step))
	action_button.text = Lang.t("tutorial_card.refresh_4") if done else Tutorial.action_label(m)
	action_button.visible = done or Tutorial.action_shown(m)
	action_button.disabled = done and Tutorial.claim_blocked()
	UiKit.apply_button(action_button, UiKit.AMBER if done else UiKit.STEEL, 12.0)
	panel.offset_top = panel.offset_bottom  # 높이 0에서 내용만큼 위로 자란다(grow BEGIN)


## [보상 받기]는 누르는 즉시 다음 미션으로 넘어간다(2026-10-16) — 빠른 두 번 탭의 두 번째가 바뀐 카드(다음 미션의 [보상 받기]·[바로가기])를
## 누르지 않게 CLAIM_GUARD_MS 동안은 버린다.
func _on_action() -> void:
	if Time.get_ticks_msec() - _claimed_ms < CLAIM_GUARD_MS:
		return
	if Tutorial.complete():
		if Tutorial.claim():
			_claimed_ms = Time.get_ticks_msec()
	else:
		Tutorial.goto_current()


func _process(delta: float) -> void:
	_t += delta
	var bottom := -(GAP_ABOVE_TABS + (0.0 if tabs != null and not tabs.bar_shown() else float(HudScript.TAB_BAR_H)))
	if panel.offset_bottom != bottom:
		panel.offset_bottom = bottom
		panel.offset_top = bottom  # 높이 0에서 내용만큼 위로 다시 자란다
	if panel.visible and Tutorial.complete():  # 보상 받기 맥동
		action_button.scale = Vector2.ONE * (1.0 + 0.04 * sin(_t * TAU * BOUNCE_HZ))
		action_button.pivot_offset = action_button.size / 2.0
	else:
		action_button.scale = Vector2.ONE
	_arrow.queue_redraw()
	_place_pointer()
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
	var s = null
	if id != "gate:2" and not Economy.is_placed(id):  # 자리를 안 잡은 공터(자유 건설): [건설] 버튼·목록 카드는 _draw_pointer가 가리킨다
		return
	else:
		tags.layout()
		s = tags.stacks.get(id)
	if s == null:
		return
	var tip := Vector2(s.get_center().x, s.position.y - 6.0 - absf(sin(_t * PI * BOUNCE_HZ)) * BOUNCE_PX)
	var pts := PackedVector2Array([tip, tip + Vector2(-ARROW.x / 2.0, -ARROW.y), tip + Vector2(-ARROW.x / 5.0, -ARROW.y),
		tip + Vector2(-ARROW.x / 5.0, -ARROW.y * 1.8), tip + Vector2(ARROW.x / 5.0, -ARROW.y * 1.8), tip + Vector2(ARROW.x / 5.0, -ARROW.y),
		tip + Vector2(ARROW.x / 2.0, -ARROW.y)])
	_arrow.draw_colored_polygon(pts, UiKit.AMBER)
	pts.append(pts[0])
	_arrow.draw_polyline(pts, UiKit.OUTLINE, 2.0)


## 가리킬 버튼의 CanvasLayer로 화살표 Control을 옮긴다(창이 덮으면 같이 가려지게).
func _make_pointer() -> void:
	_pointer = Control.new()
	_pointer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer.z_index = 100  # 같은 층의 다른 UI 위
	_pointer.draw.connect(_draw_pointer)
	add_child(_pointer)


func _place_pointer() -> void:
	if not is_instance_valid(_pointer):  # 옮겨 간 층(길드 창 등)이 닫히며 같이 지워졌다 — 새로 만든다(지워진 화살표를 만지면 출시 빌드가 튕긴다, 2026-10-13)
		_make_pointer()
	var target: Control = Tutorial.point_target() if panel.visible else null
	var home: Node = self
	if target != null:
		var n: Node = target.get_parent()
		while n != null and not (n is CanvasLayer):
			n = n.get_parent()
		if n != null:
			home = n
	if _pointer.get_parent() != home:
		_pointer.get_parent().remove_child(_pointer)
		home.add_child(_pointer)
	_pointer.queue_redraw()


## 버튼 미션: 버튼에 호박색 테두리 + 통통 튀는 화살표(버튼이 화면 위쪽이면 아래에서 위로, 아니면 위에서 아래로 가리킨다).
func _draw_pointer() -> void:
	var target: Control = Tutorial.point_target() if panel.visible else null
	if target == null:
		_last_rect = Rect2()
		_target_id = 0
		return
	# 가리킬 버튼이 막 바뀌었으면(창이 줄을 다시 만들었다) 컨테이너가 새 버튼 자리를 잡기 전이라 줄 맨 왼쪽 위에 있다 — 두 프레임 동안은
	# 지난 자리를 그대로 그린다(사용자 2026-10-16 "화살표가 고정되지않아": 가방 [열기] 화살표가 처치마다 아이콘 자리로 튀었다).
	var frame := Engine.get_process_frames()
	if target.get_instance_id() != _target_id:
		_target_id = target.get_instance_id()
		_target_since = frame
	var r: Rect2
	if frame - _target_since < TARGET_SETTLE_FRAMES:
		if _last_rect.size == Vector2.ZERO:
			return
		r = _last_rect
	else:
		var inv := _pointer.get_global_transform_with_canvas().affine_inverse()
		r = Rect2(inv * target.get_global_transform_with_canvas().origin, target.size * target.get_global_transform_with_canvas().get_scale())
		_last_rect = r
	var pulse := 0.5 + 0.5 * sin(_t * TAU * BOUNCE_HZ)
	_pointer.draw_rect(r.grow(4.0), Color(UiKit.AMBER, 0.55 + 0.45 * pulse), false, 4.0)
	var up := r.get_center().y < _pointer.size.y * 0.3  # 위쪽 버튼: 아래에서 위를 가리킨다
	var bob := absf(sin(_t * PI * BOUNCE_HZ)) * BOUNCE_PX
	var dir := -1.0 if up else 1.0  # 화살 끝이 향하는 쪽(1 = 아래)
	var tip := Vector2(r.get_center().x, (r.end.y + 8.0 + bob) if up else (r.position.y - 8.0 - bob))
	var w := ARROW.x
	var h := ARROW.y * -dir
	var pts := PackedVector2Array([tip, tip + Vector2(-w / 2.0, h), tip + Vector2(-w / 5.0, h),
		tip + Vector2(-w / 5.0, h * 1.8), tip + Vector2(w / 5.0, h * 1.8), tip + Vector2(w / 5.0, h),
		tip + Vector2(w / 2.0, h)])
	_pointer.draw_colored_polygon(pts, UiKit.AMBER)
	pts.append(pts[0])
	_pointer.draw_polyline(pts, UiKit.OUTLINE, 2.0)


func _exit_tree() -> void:
	if is_instance_valid(_pointer) and _pointer.get_parent() != self:
		_pointer.queue_free()  # 다른 층으로 옮겨 간 화살표는 카드와 함께 치운다

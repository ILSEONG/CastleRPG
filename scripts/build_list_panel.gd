extends CanvasLayer
## 건설 펼침 목록(사용자 2026-10-13 "건물 버튼을 누르면 그 자리에서 우측으로 쫘라락 펼쳐지면서 건물 생김새 등이 나와야지"):
## [건설] 버튼 오른쪽에서 두루마리 띠가 오른쪽으로 펼쳐지고(OPEN_SEC), 건물 카드가 왼쪽부터 차례로 튀어나온다(CARD_STAGGER).
## 카드 = 건물 3D 생김새(성 화면과 같은 로우폴리 메시·조명, 한 번 그린다) + 이름 + 상태(미건설 비용·Lv N·건설 중) + 아래 띠([건설]·[이동]·[보기]).
## 못 지으면(가이드 잠금·다른 건물 건설 중·자원 부족) 카드를 흐리게 하고 이유 한 줄 — 눌러도 이유 알림만. 카드가 넘치면 옆으로 끈다(TouchScroll).
## 카드를 누르면 띠를 접고 자리 고르기(placement.gd). 띠 밖을 누르거나 [건설] 버튼을 다시 누르면 접힌다. 펼친 동안 미니 채팅(hide_while_open)은 숨긴다.

const GameData := preload("res://scripts/game_data.gd")
const Balance := preload("res://scripts/balance.gd")
const TownKit := preload("res://scripts/town_kit.gd")
const Art := preload("res://scripts/art.gd")
const UiKit := preload("res://scripts/ui_kit.gd")
const HudScript := preload("res://scripts/hud.gd")
const IconsScript := preload("res://scripts/icons.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const CARD := Vector2(168, 270)
const PREVIEW := Vector2i(152, 112)
const TRAY_H := 336.0
const GAP := 8.0  # [건설] 버튼 ↔ 띠
const RIGHT := 8.0
const OPEN_SEC := 0.28
const CLOSE_SEC := 0.14
const CARD_STAGGER := 0.035
const CARD_POP := 0.2
const RED := Color(0.78, 0.22, 0.18)
const BUILD_TEXT := "건설"
const MOVE_TEXT := "이동"
const VIEW_TEXT := "보기"
const CAM_ROT := Vector3(-30, 45, 0)  # 성 화면 카메라와 비슷한 3/4 시점

var placement  # placement.gd — main이 넣는다
var building_panel  # building_panel.gd — 짓는 중인 공터 [보기]
var anchor  # build_button.gd — 띠가 그 오른쪽에서 펼쳐진다
var hide_while_open: Array = []  # 펼친 동안 숨기는 것(미니 채팅)
var rows := {}  # 건물 id → {card, status, costs, action, reason, button(= card), why}
var tray: PanelContainer

var _catcher: Control
var _scroll: ScrollContainer
var _list: HBoxContainer
var _tween: Tween
var _opening := 0  # 펼치기 차례(기다리는 사이 접혔으면 그 펼치기는 버린다)
var _hidden := []  # 펼치며 숨긴 것(접을 때 되돌린다)


func _ready() -> void:
	layer = 2  # HUD(1) 위, 하단 탭(3) 아래
	visible = false
	_catcher = Control.new()
	_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_catcher.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(_catcher)
	tray = PanelContainer.new()
	tray.mouse_filter = Control.MOUSE_FILTER_STOP
	tray.add_theme_stylebox_override("panel", UiKit.scroll(true))
	tray.clip_contents = true
	add_child(tray)
	_scroll = ScrollContainer.new()
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	tray.add_child(_scroll)
	_list = HBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_scroll.add_child(_list)
	for b in Balance.BUILDINGS:
		if not Balance.FIXED.has(b.id):
			_add_card(b.id)
	Economy.changed.connect(func(): if visible: _refresh())


func _add_card(id: String) -> void:
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = CARD
	card.add_theme_stylebox_override("normal", UiKit.panel(UiKit.CREAM, 10.0, 6))
	card.add_theme_stylebox_override("hover", UiKit.panel(UiKit.CREAM, 10.0, 6))
	card.add_theme_stylebox_override("pressed", UiKit.panel(UiKit.CREAM.darkened(0.08), 10.0, 6))
	card.add_theme_stylebox_override("disabled", UiKit.panel(UiKit.CREAM, 10.0, 6))
	card.pressed.connect(_on_pressed.bind(id))
	_list.add_child(card)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8
	box.offset_right = -8
	box.offset_top = 6
	box.offset_bottom = -6
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	box.add_child(_preview(id))
	box.add_child(_label(GameData.building_def(id).name, 22, HudScript.INK))
	var status := _label("", 16, HudScript.INK.lightened(0.3))
	box.add_child(status)
	var costs := GridContainer.new()
	costs.columns = 2
	costs.add_theme_constant_override("h_separation", 6)
	costs.add_theme_constant_override("v_separation", 0)
	costs.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	costs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(costs)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)
	var reason := _label("", 14, RED)
	reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(reason)
	var action := PanelContainer.new()
	action.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action.custom_minimum_size = Vector2(0, 34)
	var action_label := _label(BUILD_TEXT, 20, Color.WHITE)
	action_label.add_theme_color_override("font_outline_color", Color(UiKit.INK, 0.6))
	action_label.add_theme_constant_override("outline_size", 4)
	action.add_child(action_label)
	box.add_child(action)
	Tutorial.register_ui("build:" + id, card, is_open)  # 가이드 화살표: 펼친 목록의 그 건물 카드
	rows[id] = {"card": card, "button": card, "status": status, "costs": costs, "action": action, "action_label": action_label, "reason": reason, "why": ""}


## 건물 3D 생김새: 카드마다 작은 SubViewport(게임 월드와 따로, 투명 배경)에 TownKit 메시를 성 화면 시점으로 한 번 그린다.
func _preview(id: String) -> Control:
	var holder := SubViewportContainer.new()
	holder.custom_minimum_size = Vector2(PREVIEW)
	holder.stretch = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.size = PREVIEW
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	holder.add_child(vp)
	var env := Environment.new()  # portraits.gd·main과 같은 주변광
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.80, 0.86)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.1
	sun.rotation_degrees = Vector3(-50, 30, 0)
	vp.add_child(sun)
	var mesh: Mesh = TownKit.building(id)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Art.lowpoly_vc_material()
	vp.add_child(mi)
	var box := mesh.get_aabb()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.rotation_degrees = CAM_ROT
	cam.size = maxf(box.size.length() * 0.78, 2.0)
	cam.position = box.get_center() + cam.basis.z * 20.0
	cam.near = 0.1
	cam.far = 60.0
	vp.add_child(cam)
	return holder


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func is_open() -> bool:
	return visible


## 펼친다: 띠가 [건설] 버튼 오른쪽에서 오른쪽으로 자라고, 카드가 차례로 튀어나온다.
func open() -> void:
	if placement != null and placement.is_active():
		placement.cancel()
	_refresh()
	_layout()
	visible = true
	_hidden = []
	for n in hide_while_open:
		if is_instance_valid(n) and n.visible:
			n.visible = false
			_hidden.append(n)
	_scroll.scroll_horizontal = 0
	if _tween != null:
		_tween.kill()
	tray.pivot_offset = Vector2(0, tray.size.y)
	tray.scale = Vector2(0.02, 1.0)
	tray.modulate.a = 1.0
	for c in _list.get_children():
		c.modulate.a = 0.0
	_opening += 1
	var my := _opening
	await get_tree().process_frame  # 처음 펼칠 때 3D 미리보기가 그려지며 한 번 끊긴다 — 그 뒤에 움직여야 쫘라락이 보인다
	await get_tree().process_frame
	if my != _opening or not visible:
		return
	var target: String = Tutorial.target_building()  # 가이드 건설 미션: 그 건물 카드가 보이게 민다(화살표가 그 카드를 가리킨다)
	if rows.has(target):
		_scroll.ensure_control_visible(rows[target].card)
	_tween = create_tween()
	_tween.tween_property(tray, "scale", Vector2.ONE, OPEN_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var i := 0
	for c in _list.get_children():
		c.modulate.a = 0.0
		c.scale = Vector2(0.6, 0.6)
		c.pivot_offset = CARD / 2.0
		var at := OPEN_SEC * 0.35 + i * CARD_STAGGER
		_tween.parallel().tween_property(c, "modulate:a", 1.0, CARD_POP).set_delay(at)
		_tween.parallel().tween_property(c, "scale", Vector2.ONE, CARD_POP).set_delay(at).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		i += 1


## 접는다(왼쪽으로 말려 들어간다).
func close() -> void:
	if not visible:
		return
	_opening += 1
	if _tween != null:
		_tween.kill()
	for n in _hidden:
		if is_instance_valid(n):
			n.visible = true
	_hidden = []
	_tween = create_tween()
	_tween.tween_property(tray, "scale", Vector2(0.02, 1.0), CLOSE_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func(): visible = false)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## 띠 자리: [건설] 버튼 오른쪽 GAP부터 화면 오른쪽 끝 RIGHT까지, 아래 끝은 버튼 아래 끝.
func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var left := 104.0
	var bottom := vp.y - float(HudScript.TAB_BAR_H) - 12.0
	if anchor != null and anchor.button != null:
		left = anchor.button.position.x + anchor.button.size.x + GAP
		bottom = anchor.button.position.y + anchor.button.size.y
	tray.position = Vector2(left, bottom - TRAY_H)
	tray.size = Vector2(vp.x - RIGHT - left, TRAY_H)
	tray.custom_minimum_size = tray.size


func _process(_delta: float) -> void:
	if visible and (_tween == null or not _tween.is_running()):
		_layout()


func _refresh() -> void:
	var now := Economy.time_now()
	for id in rows:
		var r: Dictionary = rows[id]
		var why := ""
		var color := UiKit.AMBER
		for c in r.costs.get_children():
			c.queue_free()
		if Economy.is_built(id):
			r.status.text = "Lv %d" % Economy.building_level(id)
			r.action_label.text = MOVE_TEXT
			color = UiKit.STEEL
		elif Economy.is_placed(id):
			r.status.text = "건설 중" if Economy.is_building(id) else "공터"
			r.action_label.text = VIEW_TEXT
			color = UiKit.STEEL
		else:
			r.status.text = "미건설 · " + UiKit.duration(Economy.upgrade_sec(id))
			r.action_label.text = BUILD_TEXT
			var cost := Economy.upgrade_cost(id)
			for k in GameData.BUILD_RES:
				var need := int(cost.get(k, 0))
				if need <= 0:
					continue
				var cell := HBoxContainer.new()
				cell.add_theme_constant_override("separation", 2)
				cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var icon = IconsScript.new()
				icon.kind = k
				icon.custom_minimum_size = Vector2(18, 18)
				icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
				cell.add_child(icon)
				cell.add_child(_label(UiKit.commas(need), 15, RED if int(Economy.res.get(k, 0)) < need else HudScript.INK))
				r.costs.add_child(cell)
			if Tutorial.build_locked(id):
				why = Tutorial.build_lock_text(id)
			else:
				var block := Economy.upgrade_block(id, now)
				why = Economy.BLOCK_TEXT.get(block, "")
				if block == "builder_busy":
					why += " (%s)" % GameData.building_def(str(Economy.build.id)).name
		r.why = why
		r.reason.text = why
		r.reason.visible = why != ""
		r.costs.visible = why == "" or not Economy.is_placed(id)
		r.action.add_theme_stylebox_override("panel", UiKit.panel(color.darkened(0.25) if why != "" else color, 8.0, 2))
		r.card.modulate = Color(1, 1, 1, 0.62) if why != "" else Color.WHITE
		r.card.self_modulate = Color.WHITE


## 카드: 지은 건물 → 옮기기, 짓는 중인 공터 → 건물 창, 미건설 → 짓기(못 지으면 이유 알림만).
func _on_pressed(id: String) -> void:
	var why: String = rows[id].why
	if why != "":
		Economy.notice.emit(why)
		return
	if not Economy.is_built(id) and Economy.is_placed(id):
		close()
		if building_panel != null:
			building_panel.open_building(id)
		return
	close()
	placement.start(id)

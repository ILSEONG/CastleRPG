extends Node3D
## 자리 고르기(사용자 2026-10-13 "건물을 선택하고 내가 원하는 공간에다 건물을 짓는 형태"): 건물 목록 창의 [건설]·[이동]이 start(id)로 연다.
## 성 안에 반투명 건물 + 부지 판(놓을 수 있으면 초록, 아니면 빨강)을 띄우고, 건물을 끌거나 성 안 다른 곳을 누르면 그 칸으로 옮긴다(2 m 격자에 붙는다).
## 건물 밖에서 끌면 카메라가 움직인다(핀치 줌도 그대로). 아래 막대: 이름, 안내 또는 못 짓는 이유, 공터면 건설 비용·시간, [취소] [건설]/[여기로 이동].
## 자리 규칙은 Economy.place_block(= Balance.placement_block, 서버와 같다). 짓기는 Economy.build_at, 옮기기는 Economy.move_building.
## 고르는 동안 영웅·건물 탭(unit_picker)은 쉬고, 스테이지가 시작되면 그만둔다. 옮기는 건물은 원래 자리에서 잠깐 숨긴다.

const Lang := preload("res://scripts/lang.gd")

const Balance := preload("res://scripts/balance.gd")
const GameData := preload("res://scripts/game_data.gd")
const TownKit := preload("res://scripts/town_kit.gd")
const UiKit := preload("res://scripts/ui_kit.gd")
const HudScript := preload("res://scripts/hud.gd")
const IconsScript := preload("res://scripts/icons.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const OK_COLOR := Color(0.25, 0.85, 0.35, 0.55)
const FLOOR_OK := Color(0.3, 0.9, 0.4, 0.28)  # 바닥 칸: 지을 수 있는 칸
const FLOOR_BAD := Color(0.9, 0.3, 0.25, 0.22)  # 성벽 옆 통로·십자 길·광장(영웅·병사·괴물이 다니는 곳 — 화면엔 그냥 돌바닥이라 칸으로 보여 준다)
const BAD_COLOR := Color(0.95, 0.25, 0.2, 0.55)
const GREEN := Color(0.13, 0.58, 0.24)
const RED := Color(0.78, 0.22, 0.18)
const GHOST_ALPHA := 0.72
const TAP_PX := 14.0  # 이보다 덜 움직이고 떼면 탭(그 자리로 옮긴다)
const GRAB_PAD := 1.0  # 부지보다 이만큼(m) 넓게 잡아도 건물을 끈다
const PAN_SEC := 0.35
static var HINT := Lang.t("placement.hint")
static var OK_TEXT := Lang.t("placement.ok_text")
static var NO_SPACE_TEXT := Lang.t("placement.no_space_text")
static var WAITING_TEXT := Lang.t("placement.waiting_text")

var camera: Camera3D
var rig  # camera_rig.gd(시작할 때 그 자리로 카메라를 옮긴다)
var picker  # unit_picker.gd(고르는 동안 쉰다)
var scenery  # buildings.gd(옮기는 건물을 잠깐 숨긴다)

var building_id := ""  # 지금 고르는 건물("" = 쉬는 중)
var cell := Vector2i.ZERO
var moving := false  # 이미 지은 건물 옮기기(아니면 공터 짓기)
var ok := false  # 지금 칸에 놓을 수 있다

var bar: PanelContainer
var title_label: Label
var hint_label: Label
var cost_row: HBoxContainer
var confirm_button: Button
var cancel_button: Button

var _layer: CanvasLayer
var _ghost: MeshInstance3D
var _plate: MeshInstance3D
var _plate_mat: StandardMaterial3D
var _floor: MeshInstance3D  # 고르는 동안 성 안 바닥 칸(초록 = 지을 수 있음, 빨강 = 길·통로·광장)
var _press := Vector2.INF  # 누른 화면 위치(건물 밖에서 눌렀을 때만 — 탭 판정)
var _grab := false  # 건물을 잡고 끄는 중
var _grab_off := Vector3.ZERO  # 잡은 점 → 부지 가운데


func _ready() -> void:
	_ghost = MeshInstance3D.new()
	var gm := StandardMaterial3D.new()
	gm.vertex_color_use_as_albedo = true
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(1, 1, 1, GHOST_ALPHA)
	_ghost.material_override = gm
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)
	_plate = MeshInstance3D.new()
	_plate_mat = StandardMaterial3D.new()
	_plate_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plate_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_plate.material_override = _plate_mat
	_plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plate.visible = false
	add_child(_plate)
	_floor = MeshInstance3D.new()
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.vertex_color_use_as_albedo = true
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_floor.material_override = fm
	_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_floor.visible = false
	add_child(_floor)
	_build_bar()
	GameState.mode_changed.connect(func(m): if m != GameState.Mode.IDLE: cancel())
	Economy.notice.connect(_on_notice)
	Economy.build_rejected.connect(_on_rejected)
	Economy.changed.connect(func(): if is_active(): _update())  # 자원·일꾼·연결이 바뀌면 안내와 [건설]을 다시 맞춘다


func _build_bar() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 4  # HUD·하단 탭(3) 위 — 고르는 동안 탭은 가린다
	_layer.visible = false
	add_child(_layer)
	bar = PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 8
	bar.offset_right = -8
	bar.offset_bottom = -8
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM_DIALOG, 12.0, 16))
	_layer.add_child(bar)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	bar.add_child(box)
	title_label = _label(32, HudScript.INK)
	box.add_child(title_label)
	hint_label = _label(24, GREEN)
	box.add_child(hint_label)
	cost_row = HBoxContainer.new()
	cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cost_row.add_theme_constant_override("separation", 6)
	box.add_child(cost_row)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	cancel_button = _button(Lang.t("placement.build_bar"), UiKit.STEEL)
	cancel_button.pressed.connect(cancel)
	buttons.add_child(cancel_button)
	confirm_button = _button(Lang.t("placement.build_bar_2"), UiKit.AMBER)
	confirm_button.pressed.connect(confirm)
	buttons.add_child(confirm_button)


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 72)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 30)
	UiKit.apply_button(b, color, 14.0)
	return b


func is_active() -> bool:
	return building_id != ""


## 건물 id 자리 고르기를 시작한다. 지은 건물이면 옮기기(지금 자리부터), 아니면 공터 짓기(기본 자리에서 가장 가까운 빈 칸부터).
func start(id: String) -> bool:
	if Balance.building(id).is_empty() or Balance.FIXED.has(id):
		return false
	if is_active():
		cancel()
	moving = Economy.is_built(id)
	var from := Economy.building_cell(id)
	var c = from if moving else Economy.free_cell(id, from)
	if c == null:
		Economy.notice.emit(NO_SPACE_TEXT)
		return false
	building_id = id
	cell = c
	var full: Mesh = TownKit.building(id, GameData.castle_look(Economy.building_level(GameData.KEEP)))
	_ghost.mesh = full
	var b := Balance.building(id)
	var pm := BoxMesh.new()
	pm.size = Vector3(b.size.x * Balance.TILE - 0.1, 0.06, b.size.y * Balance.TILE - 0.1)
	_plate.mesh = pm
	_ghost.visible = true
	_plate.visible = true
	_floor.mesh = _floor_mesh(id)
	_floor.visible = true
	if moving and scenery != null and scenery.lots.has(id):
		scenery.lots[id].mi.visible = false
	_set_picker(false)
	title_label.text = "%s %s" % [GameData.building_name(id), Lang.t("placement.start") if moving else Lang.t("placement.start_2")]
	confirm_button.text = Lang.t("placement.start_3") if moving else Lang.t("placement.start_2")
	_fill_cost()
	_layer.visible = true
	_update()
	if rig != null:
		rig.pan_to(Balance.center_of(id) if moving else _center(), PAN_SEC)
	return true


## 성 안 바닥 칸 표시: 타일마다 Balance.rect_block(1×1) — 빈 칸은 초록, 길·통로·광장은 빨강, 다른 건물 밑은 비운다(건물이 보인다).
## 건물은 초록 칸 안에 부지(3×3)가 다 들어가야 놓인다.
func _floor_mesh(id: String) -> ArrayMesh:
	var half := Economy.interior_half_tiles()
	var others: Dictionary = Economy.placed_cells(id)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pad := 0.08
	var t := Balance.TILE
	for x in range(-half, half):
		for y in range(-half, half):
			var why := Balance.rect_block(Rect2i(x, y, 1, 1), half, others)
			if why == "overlap":
				continue
			st.set_color(FLOOR_OK if why == "" else FLOOR_BAD)
			var a := Vector3(x * t + pad, 0.03, y * t + pad)
			var b := Vector3((x + 1) * t - pad, 0.03, (y + 1) * t - pad)
			for v in [a, Vector3(b.x, 0.03, a.z), b, a, b, Vector3(a.x, 0.03, b.z)]:
				st.add_vertex(v)
	return st.commit()


func cancel() -> void:
	if not is_active():
		return
	_end()


## [건설]/[여기로 이동]: 지금 칸에 짓기 시작하거나 옮긴다. 되면 그만둔다(안 되면 이유 알림, 그대로 고른다).
func confirm() -> void:
	if not is_active() or not ok:
		return
	var done: bool = Economy.move_building(building_id, cell) if moving else Economy.build_at(building_id, cell, Economy.time_now())
	if done:
		_end()
	elif hint_label.get_theme_color("font_color") != RED:  # 알림 없이 안 됐다 — 아무 일 없는 것처럼 두지 않는다
		hint_label.text = Economy.BUILD_FAIL_TEXT
		hint_label.add_theme_color_override("font_color", RED)


func _end() -> void:
	if moving and scenery != null and scenery.lots.has(building_id):
		scenery.lots[building_id].mi.visible = Economy.is_placed(building_id)
	building_id = ""
	_grab = false
	_press = Vector2.INF
	_ghost.visible = false
	_plate.visible = false
	_floor.visible = false
	_layer.visible = false
	_set_picker(true)


func _set_picker(on: bool) -> void:
	if picker != null and is_instance_valid(picker):
		picker.set_process_input(on)
		picker.set_process_unhandled_input(on)


func _fill_cost() -> void:
	for c in cost_row.get_children():
		c.queue_free()
	cost_row.visible = not moving
	if moving:
		return
	var cost := Economy.upgrade_cost(building_id)
	for k in GameData.BUILD_RES:
		var need := int(cost.get(k, 0))
		if need <= 0:
			continue
		var icon = IconsScript.new()
		icon.kind = k
		icon.custom_minimum_size = Vector2(32, 32)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cost_row.add_child(icon)
		cost_row.add_child(_label(26, HudScript.INK))
		(cost_row.get_child(cost_row.get_child_count() - 1) as Label).text = UiKit.commas(need) + "  "
	var t := _label(26, HudScript.INK)
	t.text = Lang.t("placement.fill_cost") + UiKit.duration(Economy.upgrade_sec(building_id))
	cost_row.add_child(t)


## 부지 가운데(월드).
func _center() -> Vector3:
	var b := Balance.building(building_id)
	return Vector3((cell.x + b.size.x / 2.0) * Balance.TILE, 0, (cell.y + b.size.y / 2.0) * Balance.TILE)


## 칸을 바꿨다: 반투명 건물·판 자리와 색, 안내 문구, 버튼.
func _update() -> void:
	var why: String = Economy.place_block(building_id, cell)
	if moving and cell == Economy.building_cell(building_id):
		why = ""  # 제자리(겹침 검사는 자기를 빼고 한다)
	ok = why == "" and not (moving and cell == Economy.building_cell(building_id))
	var c := _center()
	_ghost.position = c
	_plate.position = c + Vector3(0, 0.04, 0)
	_plate_mat.albedo_color = OK_COLOR if why == "" else BAD_COLOR
	var stop := _build_stop() if why == "" else ""  # 자리는 되지만 지금 짓기가 안 되는 이유(자원·일꾼·연결 — 누르면 서버도 거절한다)
	if why != "":
		hint_label.text = Balance.PLACE_TEXT.get(why, "")
		hint_label.add_theme_color_override("font_color", RED)
	elif stop != "":
		hint_label.text = stop
		hint_label.add_theme_color_override("font_color", RED)
	else:
		hint_label.text = HINT if moving and not ok else OK_TEXT
		hint_label.add_theme_color_override("font_color", GREEN)
	ok = ok and stop == ""
	confirm_button.disabled = not ok


## 공터 짓기: 자리 말고 짓기를 막는 것(Economy.upgrade와 같은 검사). 옮기기는 무료라 없다. 응답 대기 중("waiting")은 버튼만 잠깐 막는다.
func _build_stop() -> String:
	if moving:
		return ""
	if Economy.build_waiting():
		return WAITING_TEXT
	if Tutorial.build_locked(building_id):
		return Tutorial.build_lock_text(building_id)
	var block := Economy.upgrade_block(building_id, Economy.time_now())
	if block != "":
		return Economy.BLOCK_TEXT.get(block, Economy.BUILD_FAIL_TEXT)
	if Economy.net != null and not Economy.net.up:
		return Economy.WAIT_TEXT
	return ""


## 서버가 공터 짓기를 거절했다(이미 되돌림): 그 자리로 자리 고르기를 다시 열고 막대에 서버가 말한 이유를 보인다.
func _on_rejected(id: String, at: Variant, text: String) -> void:
	if is_active() or GameState.mode != GameState.Mode.IDLE or not Economy.unbuilt.has(id):
		return
	if not start(id):
		return
	if at is Vector2i:
		cell = at
		_update()
	hint_label.text = text
	hint_label.add_theme_color_override("font_color", RED)


## 고르는 동안 알림(서버 거절·연결 대기 등)은 아래 막대가 HUD 알림 자리를 가리므로 막대 안내 줄에 빨갛게 띄운다.
func _on_notice(text: String) -> void:
	if not is_active() or text == "":
		return
	hint_label.text = text
	hint_label.add_theme_color_override("font_color", RED)


## 화면 점 → 땅(y = 0) 위 점. 못 닿으면 null.
func _ground(screen: Vector2):
	if camera == null:
		return null
	return Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))


## 부지 가운데 p(월드)에 가장 가까운 칸으로.
func _move_to(p: Vector3) -> void:
	var b := Balance.building(building_id)
	var m: int = Economy.interior_half_tiles()
	var c := Vector2i(roundi(p.x / Balance.TILE - b.size.x / 2.0), roundi(p.z / Balance.TILE - b.size.y / 2.0))
	c = Vector2i(clampi(c.x, -m, m - b.size.x), clampi(c.y, -m, m - b.size.y))  # 성 밖으로는 안 나간다
	if c != cell:
		cell = c
		_update()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active():
		return
	if event.is_action_pressed("ui_cancel"):
		cancel()
		get_viewport().set_input_as_handled()
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			var g = _ground(mb.position)
			var b := Balance.building(building_id)
			var rect := Rect2(Vector2(cell) * Balance.TILE, Vector2(b.size) * Balance.TILE).grow(GRAB_PAD)
			if g != null and rect.has_point(Vector2(g.x, g.z)):
				_grab = true
				_grab_off = _center() - g
				get_viewport().set_input_as_handled()  # 카메라가 끌리지 않는다
			else:
				_press = mb.position
		else:
			if _grab:
				_grab = false
				get_viewport().set_input_as_handled()
			elif _press != Vector2.INF and mb.position.distance_to(_press) <= TAP_PX:
				var g = _ground(mb.position)
				if g != null:
					_move_to(g)
			_press = Vector2.INF
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _grab:
		var g = _ground(mm.position)
		if g != null:
			_move_to(g + _grab_off)
		get_viewport().set_input_as_handled()

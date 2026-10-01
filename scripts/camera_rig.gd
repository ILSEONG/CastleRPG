extends Node3D
## 쿼터뷰 직교 카메라 리그. 리그 위치 = 화면 중앙이 바라보는 바닥 지점.
## 한 손가락/마우스 드래그로 이동(DRAG_THRESHOLD_PX 넘으면 드래그 확정), 휠·두 손가락 핀치로 줌. pan_to = 지점으로 부드럽게 이동(HUD 성문 막대 탭).
## 한 손가락 터치 팬은 emulate_mouse_from_touch로 들어온다(0번 손가락 → 마우스 이벤트) —
## pan_pixels는 InputEventScreenDrag에서는 호출되지 않고 InputEventMouseMotion 쪽에서만 호출된다.
## 입력을 소비하지 않는다 — 탭 판정(UnitPicker)도 같은 이벤트를 본다.

const Balance := preload("res://scripts/balance.gd")

const PITCH_DEG := -35.0
const YAW_DEG := 45.0
const DISTANCE := 100.0
const DRAG_THRESHOLD_PX := 12.0
const ZOOM_STEP := 1.1
const PAN_LIMIT_MARGIN := 20.0
const HOLD_SEC := 0.35  # 이만큼 덜 움직이고 누르면 회전 대기(개정 14 §1)
const ROTATE_DEG_PER_PX := 0.4
const INDICATOR_COLOR := Color("ffd23f")
const INDICATOR_SEC := 0.3

var camera: Camera3D

var _press_ms := 0
var _rotating := false  # 꾹 누름 회전 대기·회전 중
var _indicator: Control  # 회전 표시(원 위 화살 둘)
var _press_pos: Vector2 = Vector2.INF
var _dragging := false
var _touches := {}  # 터치 index -> 화면 위치 (핀치용)
var _pan: Tween  # pan_to 진행 중(손으로 끌면 멈춘다)


func _ready() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = Balance.CAMERA_SIZE_DEFAULT
	camera.near = 1.0
	camera.rotation_degrees = Vector3(PITCH_DEG, YAW_DEG, 0)
	add_child(camera)
	_fit_depth()
	var layer := CanvasLayer.new()
	add_child(layer)
	_indicator = Control.new()
	_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_indicator.visible = false
	_indicator.draw.connect(_draw_indicator)
	layer.add_child(_indicator)


## 누른 시간·움직인 거리 → "tap"(아직 미정) / "hold"(회전 대기) / "pan"(이미 드래그).
static func hold_state(held_sec: float, moved_px: float) -> String:
	if moved_px > DRAG_THRESHOLD_PX:
		return "pan"
	return "hold" if held_sec >= HOLD_SEC else "tap"


## 화면상 카메라 요(도). 기본 YAW_DEG, 회전하면 변한다.
func yaw_deg() -> float:
	return rad_to_deg(camera.global_rotation.y)


func _process(_delta: float) -> void:
	if _press_pos == Vector2.INF or _dragging or _rotating or _touches.size() >= 2:
		return
	if hold_state((Time.get_ticks_msec() - _press_ms) / 1000.0, 0.0) == "hold":
		_rotating = true
		_indicator.position = _press_pos
		_indicator.scale = Vector2.ONE * 0.3
		_indicator.visible = true
		_indicator.queue_redraw()
		create_tween().tween_property(_indicator, "scale", Vector2.ONE, INDICATOR_SEC)


func _draw_indicator() -> void:
	var ring := PackedVector2Array()
	for i in 8:
		ring.append(Vector2.from_angle(TAU * i / 8.0) * 34.0)
	ring.append(ring[0])
	_indicator.draw_polyline(ring, INDICATOR_COLOR, 3.0)
	for s in [-1.0, 1.0]:  # 좌우 화살
		var x: float = s * 52.0
		_indicator.draw_colored_polygon(PackedVector2Array([Vector2(x + s * 14.0, 0), Vector2(x - s * 6.0, -12), Vector2(x - s * 6.0, 12)]), INDICATOR_COLOR)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _touches.size() >= 2 and _touches.has(sd.index):
			_pinch(sd)
		if _touches.has(sd.index):
			_touches[sd.index] = sd.position
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_by(1.0 / ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_by(ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_press_pos = mb.position if mb.pressed else Vector2.INF
			_press_ms = Time.get_ticks_msec()
			_dragging = false
			_stop_rotate()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _press_pos == Vector2.INF or _touches.size() >= 2:
			return
		if _rotating:
			rotate_yaw(-mm.relative.x * ROTATE_DEG_PER_PX)  # 손가락 방향으로 바닥이 돈다
			return
		if not _dragging and mm.position.distance_to(_press_pos) > DRAG_THRESHOLD_PX:
			_dragging = true
		if _dragging:
			pan_pixels(mm.relative)


## 포커스를 잃으면 손 뗌 이벤트가 안 올 수 있다 — 누름·드래그·터치 상태를 버린다.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_touches.clear()
		_press_pos = Vector2.INF
		_dragging = false
		_stop_rotate()


func _stop_rotate() -> void:
	_rotating = false
	_indicator.visible = false


## 화면 중심 지면 점(리그 위치) 둘레로 요만 돌린다. 피치·줌·위치는 그대로, 제한 없음.
func rotate_yaw(deg: float) -> void:
	rotation_degrees.y = wrapf(rotation_degrees.y + deg, -180.0, 180.0)


## 화면 가운데가 바닥 지점 target(높이 무시)을 보도록 sec초 동안 부드럽게 옮긴다(개정 12-2 §2). 줌은 그대로, 팬 한계 안.
func pan_to(target: Vector3, sec: float) -> void:
	if _pan != null:
		_pan.kill()
	var limit := Balance.MAP_HALF - PAN_LIMIT_MARGIN
	var dest := Vector3(clampf(target.x, -limit, limit), position.y, clampf(target.z, -limit, limit))
	_pan = create_tween()
	_pan.tween_property(self, "position", dest, sec).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 화면 픽셀 이동량만큼 바닥이 손가락을 따라오게 리그를 옮긴다.
func pan_pixels(rel: Vector2) -> void:
	if _pan != null:
		_pan.kill()  # 손이 이긴다
	var world_per_px := camera.size / get_viewport().get_visible_rect().size.x
	var right := camera.global_basis.x
	right.y = 0.0
	right = right.normalized()
	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var ground_stretch := 1.0 / sin(deg_to_rad(-PITCH_DEG))  # 화면 세로 1px이 바닥에서 늘어나는 비율
	position += -right * rel.x * world_per_px + forward * rel.y * world_per_px * ground_stretch
	var limit := Balance.MAP_HALF - PAN_LIMIT_MARGIN
	position.x = clampf(position.x, -limit, limit)
	position.z = clampf(position.z, -limit, limit)


## factor < 1 이면 확대.
func zoom_by(factor: float) -> void:
	camera.size = clampf(camera.size * factor, Balance.CAMERA_SIZE_MIN, Balance.CAMERA_SIZE_MAX)
	_fit_depth()


## 줌에 맞춰 카메라를 뒤로 빼고 far를 늘린다 — 직교 카메라라 그림은 같고 바닥이 near/far 밖으로 잘리지 않는다.
func _fit_depth() -> void:
	var vp := get_viewport().get_visible_rect().size
	var spread := camera.size * vp.y / vp.x * 0.5 / tan(deg_to_rad(-PITCH_DEG)) + 20.0  # 화면 절반이 덮는 바닥 깊이 + 키 큰 물체 여유
	camera.position = camera.basis.z * maxf(DISTANCE, spread)
	camera.far = camera.position.length() + spread


func _pinch(sd: InputEventScreenDrag) -> void:
	var other_pos := Vector2.INF
	for i in _touches:
		if i != sd.index:
			other_pos = _touches[i]
			break
	var prev_pos: Vector2 = _touches[sd.index]
	var old_d := prev_pos.distance_to(other_pos)
	var new_d := sd.position.distance_to(other_pos)
	if old_d > 1.0 and new_d > 1.0:
		zoom_by(old_d / new_d)

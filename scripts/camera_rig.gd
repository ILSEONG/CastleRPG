extends Node3D
## 쿼터뷰 직교 카메라 리그. 리그 위치 = 화면 중앙이 바라보는 바닥 지점.
## 한 손가락/마우스 드래그로 이동(DRAG_THRESHOLD_PX 넘으면 드래그 확정), 휠·두 손가락 핀치로 줌.
## 입력을 소비하지 않는다 — 탭 판정(UnitPicker)도 같은 이벤트를 본다.

const Balance := preload("res://scripts/balance.gd")

const PITCH_DEG := -35.0
const YAW_DEG := 45.0
const DISTANCE := 100.0
const DRAG_THRESHOLD_PX := 12.0
const ZOOM_STEP := 1.1
const PAN_LIMIT_MARGIN := 20.0

var camera: Camera3D

var _press_pos: Vector2 = Vector2.INF
var _dragging := false
var _touches := {}  # 터치 index -> 화면 위치 (핀치용)


func _ready() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = Balance.CAMERA_SIZE_DEFAULT
	camera.near = 1.0
	camera.far = 300.0
	camera.rotation_degrees = Vector3(PITCH_DEG, YAW_DEG, 0)
	camera.position = camera.basis.z * DISTANCE
	add_child(camera)


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
			_dragging = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _press_pos == Vector2.INF or _touches.size() >= 2:
			return
		if not _dragging and mm.position.distance_to(_press_pos) > DRAG_THRESHOLD_PX:
			_dragging = true
		if _dragging:
			pan_pixels(mm.relative)


## 화면 픽셀 이동량만큼 바닥이 손가락을 따라오게 리그를 옮긴다.
func pan_pixels(rel: Vector2) -> void:
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

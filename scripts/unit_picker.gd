extends Node
## 탭 → 카메라 레이캐스트 → 영웅 선택 / 선택 영웅을 성문 앞(성문 탭) 또는 성벽 위(성벽 탭)로 이동.
## 드래그(카메라 이동)와 구분: 누른 곳과 뗀 곳이 TAP_MAX_PX 이내일 때만 탭.
## 입력을 소비하지 않는다 — 카메라 리그도 같은 이벤트를 본다.
## 터치는 emulate_mouse_from_touch로 마우스 이벤트가 되므로 마우스만 처리.

const Formation := preload("res://scripts/formation.gd")

const LAYER_GATE := 2
const LAYER_HERO := 4
const LAYER_WALL := 8
const TAP_MAX_PX := 12.0

var camera: Camera3D
var selected

var _press_pos: Vector2 = Vector2.INF
var _pending: Vector2 = Vector2.INF


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_press_pos = mb.position
	elif _press_pos != Vector2.INF:
		if mb.position.distance_to(_press_pos) <= TAP_MAX_PX:
			_pending = mb.position
		_press_pos = Vector2.INF


func _physics_process(_delta: float) -> void:
	if _pending == Vector2.INF:
		return
	var screen_pos := _pending
	_pending = Vector2.INF
	# 영웅을 먼저 쏜다: 성문·성벽 탭 박스(여유 1m)가 그 앞이나 위에 선 영웅을 가리기 때문.
	var hit := _pick(screen_pos, LAYER_HERO)
	if not hit.is_empty():
		_select(hit.collider.get_meta("hero"))
		return
	hit = _pick(screen_pos, LAYER_GATE)
	if not hit.is_empty():
		_order(hit.collider.get_meta("side"), Formation.POST_GATE)
		return
	hit = _pick(screen_pos, LAYER_WALL)
	if not hit.is_empty():
		_order(hit.collider.get_meta("side"), Formation.POST_WALL)
		return
	_select(null)


func _order(side: int, post: int) -> void:
	if selected != null and selected.is_alive():
		selected.move_to(side, post)
	else:
		_select(null)


func _pick(screen_pos: Vector2, layer_mask: int) -> Dictionary:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 400.0
	var q := PhysicsRayQueryParameters3D.create(from, to, layer_mask)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	return camera.get_world_3d().direct_space_state.intersect_ray(q)


func _select(hero) -> void:
	if selected != null and is_instance_valid(selected):
		selected.selected = false
	selected = hero
	if selected != null:
		selected.selected = true

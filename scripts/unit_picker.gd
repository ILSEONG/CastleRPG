extends Node
## 탭 → 카메라 레이캐스트 → 영웅 선택 / 선택 영웅을 성문으로 이동.
## 터치는 프로젝트 기본값(emulate_mouse_from_touch)으로 마우스 이벤트가 되므로 마우스만 처리.

const LAYER_GATE := 2
const LAYER_HERO := 4

var camera: Camera3D
var selected

var _pending: Vector2 = Vector2.INF


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pending = event.position
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if _pending == Vector2.INF:
		return
	# 영웅을 먼저 쏴본다: 성문 탭 판정 박스가(탭 여유를 위해 확대되어) 성문 바로
	# 바깥에 선 영웅과 카메라 시야에서 겹쳐, 레이어를 합쳐서 한 번에 쏘면 더 가까운
	# 성문 박스가 뒤의 영웅을 가려버린다. 영웅 레이어를 우선 검사해 항상 영웅이 이긴다.
	var screen_pos := _pending
	_pending = Vector2.INF
	var hero_hit := _pick(screen_pos, LAYER_HERO)
	if not hero_hit.is_empty():
		var area: Area3D = hero_hit.collider
		_select(area.get_meta("hero"))
		return
	var gate_hit := _pick(screen_pos, LAYER_GATE)
	if gate_hit.is_empty():
		_select(null)
		return
	var gate_area: Area3D = gate_hit.collider
	if selected != null and selected.is_alive():
		selected.move_to_side(gate_area.get_meta("side"))
	else:
		_select(null)


func _pick(screen_pos: Vector2, layer_mask: int) -> Dictionary:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 200.0
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

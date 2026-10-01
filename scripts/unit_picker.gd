extends Node
## 탭 → 영웅은 화면 좌표로, 성문·성벽은 카메라 레이캐스트로, 바닥은 y=0 평면과의 교점으로 판정 →
## 영웅 선택 / 선택 영웅을 성문 앞(성문 탭)·성벽 위(성벽 탭)·바닥 지점(그 외)으로 이동.
## 판정: 선택된 산 영웅이 없으면 HERO_TAP_PX 안 영웅 선택 → 상인·자원 건물 → 선택 해제. 있으면
## HERO_TAP_PRECISE_PX 안 영웅(선택된 영웅 자신이면 해제, 아니면 그 영웅 선택) → 성문 → 성벽 →
## HERO_TAP_PX 안 다른 영웅 선택 → 상인·자원 건물 → 바닥 자유 이동 순 (성문 앞 전사가 성문 탭을 가로채지 않게).
## 드래그(카메라 이동)와 구분: 누른 뒤 뗄 때까지 TAP_MAX_PX 넘게 움직이지 않고 두 번째 손가락도 없을 때만 탭.
## 상인 탭은 거래 창을 열고, 자원 건물 탭은 수집(+N)한다 — 둘 다 영웅 선택은 건드리지 않는다. 기능 없는 건물 탭은 무시(다음 판정).
## 입력을 소비하지 않는다 — 카메라 리그도 같은 이벤트를 본다(거래 창이 열려 있으면 GUI가 먼저 먹어 둘 다 못 받는다).
## 터치는 emulate_mouse_from_touch로 마우스 이벤트가 되므로 마우스만 처리.

const Formation := preload("res://scripts/formation.gd")
const Balance := preload("res://scripts/balance.gd")
const Art := preload("res://scripts/art.gd")

const LAYER_GATE := 2
const LAYER_WALL := 8
const LAYER_TAP := 16  # 건물 탭 판정체(buildings.gd)
const LAYER_MERCHANT := 32  # 상인·수레 탭 판정체 — 건물보다 먼저 본다(앞쪽 벌목장·채석장 상자에 가리지 않게)
const TAP_MAX_PX := 12.0
const HERO_TAP_PX := 32.0  # 화면(논리 720px 폭 기준)에서 영웅 중심까지 이 거리 안이면 그 영웅. 줌과 무관
const HERO_TAP_PRECISE_PX := 12.0  # 영웅 선택 중에는 이만큼 가까워야 성문·성벽보다 영웅이 먼저
const GROUND_MARGIN := 4.0   # 바닥 명령 지점을 맵 가장자리에서 이만큼 안으로 자른다
const MARKER_SEC := 0.5

var camera: Camera3D
var selected
var badges  # 수집 "+N" 표시(badges.gd)
var panel   # 상인 거래 창(merchant_panel.gd)

var _press_pos: Vector2 = Vector2.INF
var _pending: Vector2 = Vector2.INF


func _ready() -> void:
	Economy.collected.connect(_on_collected)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).index >= 1:
			_press_pos = Vector2.INF  # 두 번째 손가락 = 핀치. 이번 누름은 탭이 아니다
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _press_pos != Vector2.INF and mm.position.distance_to(_press_pos) > TAP_MAX_PX:
			_press_pos = Vector2.INF  # 드래그로 확정. 되돌아와 떼도 탭이 아니다
		return
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_press_pos = mb.position
	elif _press_pos != Vector2.INF:
		_pending = mb.position
		_press_pos = Vector2.INF


func _physics_process(_delta: float) -> void:
	if _pending == Vector2.INF:
		return
	var screen_pos := _pending
	_pending = Vector2.INF
	# 영웅은 화면 좌표로 판정하므로 성문·성벽 탭 박스(여유 1m)에 가려질 일이 없다.
	if selected == null or not selected.is_alive():
		var tapped = _hero_at(screen_pos, HERO_TAP_PX)
		if tapped == null and _tap_object(screen_pos):
			return  # 상인·자원 건물: 선택은 그대로(없으면 없는 채)
		_select(tapped)
		return
	var hero = _hero_at(screen_pos, HERO_TAP_PRECISE_PX)
	if hero != null:
		_select(null if hero == selected else hero)  # 선택된 영웅을 다시 누르면 해제
		return
	var hit := _pick(screen_pos, LAYER_GATE)
	if not hit.is_empty():
		selected.move_to(hit.collider.get_meta("side"), Formation.POST_GATE)
		return
	hit = _pick(screen_pos, LAYER_WALL)
	if not hit.is_empty():
		selected.move_to(hit.collider.get_meta("side"), Formation.POST_WALL)
		return
	hero = _hero_at(screen_pos, HERO_TAP_PX)
	if hero != null and hero != selected:
		_select(hero)
		return
	if _tap_object(screen_pos):
		return  # 영웅 선택 유지
	var ground = _ground_point(screen_pos)
	if ground == null:
		_select(null)
		return
	selected.move_to_point(ground)
	_show_marker(ground)


func _pick(screen_pos: Vector2, layer_mask: int) -> Dictionary:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * camera.far
	var q := PhysicsRayQueryParameters3D.create(from, to, layer_mask)
	q.collide_with_areas = true
	q.collide_with_bodies = true  # 성문·성벽은 Area, 건물·상인 탭 판정체는 Body — 레이어 마스크로 가른다
	return camera.get_world_3d().direct_space_state.intersect_ray(q)


## 상인(레이어 32) → 자원 건물(레이어 16) 탭. 처리했으면 true. 기능 없는 건물은 적중을 무시(false)해 다음 판정으로 넘긴다.
func _tap_object(screen_pos: Vector2) -> bool:
	if not _pick(screen_pos, LAYER_MERCHANT).is_empty():
		panel.open()
		return true
	var hit := _pick(screen_pos, LAYER_TAP)
	if hit.is_empty():
		return false
	var id: String = hit.collider.get_meta("building", "")
	var res_id: String = Economy.res_of(id)
	if res_id == "":
		return false
	Economy.collect(id, Economy.time_now())  # "+N"은 collected 시그널로(온라인은 응답이 왔을 때)
	return true


## 수집 결과 "+N". 오프라인은 탭 즉시, 온라인은 서버 응답의 amount로.
func _on_collected(building_id: String, res_id: String, amount: int) -> void:
	badges.pop(badges.anchor(building_id), res_id, amount)


## 탭 위치의 바닥(y=0) 지점, 맵 안으로 자름. 바닥을 못 맞히면 null.
func _ground_point(screen_pos: Vector2):
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))
	if hit == null:
		return null
	var lim := Balance.MAP_HALF - GROUND_MARGIN
	return Vector3(clampf(hit.x, -lim, lim), 0.0, clampf(hit.z, -lim, lim))


## 바닥 명령 지점에 노란 링이 커지며 사라진다.
func _show_marker(p: Vector3) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.7
	var ring := Art.mesh(torus, Art.HERO_SELECTED)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(ring)
	ring.global_position = p + Vector3(0, 0.05, 0)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3.ONE * 1.8, MARKER_SEC)
	tw.tween_callback(ring.queue_free)


## 탭 위치에서 화면상 가장 가까운 살아 있는 영웅 (radius_px 이내). 없으면 null.
func _hero_at(screen_pos: Vector2, radius_px: float):
	var best = null
	var best_d := radius_px
	for h in get_tree().get_nodes_in_group("heroes"):
		if not h.is_alive():
			continue
		var d := camera.unproject_position(h.global_position + Vector3(0, 0.8, 0)).distance_to(screen_pos)
		if d <= best_d:
			best_d = d
			best = h
	return best


func _select(hero) -> void:
	if selected != null and is_instance_valid(selected):
		selected.selected = false
	selected = hero
	if selected != null:
		selected.selected = true

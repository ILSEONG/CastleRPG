extends Node
## 탭 → 영웅은 화면 좌표로, 성문·성벽은 카메라 레이캐스트로, 바닥은 y=0 평면과의 교점으로 판정 →
## 영웅 선택 / 선택 영웅을 성문 앞(성문 탭)·성벽 위(성벽 탭)·바닥 지점(그 외)으로 이동.
## 판정: 선택된 산 영웅이 없으면 HERO_TAP_PX 안 영웅 선택 → 상인·건물·성문(창) → 선택 해제. 있으면
## HERO_TAP_PRECISE_PX 안 영웅(선택된 영웅 자신이면 해제, 아니면 그 영웅 선택) → 성문 → 성벽 →
## HERO_TAP_PX 안 다른 영웅 선택 → 상인·건물(창) → 바닥 자유 이동 순 (성문 앞 전사가 성문 탭을 가로채지 않게).
## 드래그(카메라 이동)와 구분: 누른 뒤 뗄 때까지 TAP_MAX_PX 넘게 움직이지 않고 두 번째 손가락도 없을 때만 탭.
## 상인 탭은 거래 창, 주점 탭은 모집 창, 자원 건물 탭은 쌓인 게 있으면 수집(+N)·없으면 건물 창, 그 밖의 건물 탭은 건물 창(개정 12 §2.5).
## 성문 탭은 선택된 영웅이 있으면 그 영웅의 성문 명령이 먼저이고, 없으면 성문 건물 창. 모두 영웅 선택은 건드리지 않는다.
## 길게 누르기(LONG_PRESS_MS, 같은 탭 조건: 움직이지 않고 두 번째 손가락 없음): 건물·성문이면 누른 채로 건물 창을 열고 그 누름은 탭이
## 되지 않는다(주점·자원 건물도 건물 창). 건물이 아니면(바닥·영웅·상인) 아무 일 없이 뗄 때 보통 탭이다.
## 입력을 소비하지 않는다 — 카메라 리그도 같은 이벤트를 본다(거래 창이 열려 있으면 GUI가 먼저 먹어 둘 다 못 받는다).
## 터치는 emulate_mouse_from_touch로 마우스 이벤트가 되므로 마우스만 처리.

const Formation := preload("res://scripts/formation.gd")
const Balance := preload("res://scripts/balance.gd")
const Art := preload("res://scripts/art.gd")
const GameData := preload("res://scripts/game_data.gd")

const LAYER_GATE := 2
const LAYER_WALL := 8
const LAYER_TAP := 16  # 건물 탭 판정체(buildings.gd)
const LAYER_MERCHANT := 32  # 상인·수레 탭 판정체 — 건물보다 먼저 본다(앞쪽 벌목장·채석장 상자에 가리지 않게)
const TAP_MAX_PX := 12.0
const HERO_TAP_PX := 32.0  # 화면(논리 720px 폭 기준)에서 영웅 중심까지 이 거리 안이면 그 영웅. 줌과 무관
const HERO_TAP_PRECISE_PX := 12.0  # 영웅 선택 중에는 이만큼 가까워야 성문·성벽보다 영웅이 먼저
const GROUND_MARGIN := 4.0   # 바닥 명령 지점을 맵 가장자리에서 이만큼 안으로 자른다
const MARKER_SEC := 0.5
const LONG_PRESS_MS := 500

var camera: Camera3D
var selected
var badges  # 수집 "+N" 표시(badges.gd)
var panel   # 상인 거래 창(merchant_panel.gd)
var recruit  # 주점 모집 창(recruit_panel.gd)
var building_panel  # 건물 창(building_panel.gd)

var _press_pos: Vector2 = Vector2.INF
var _pending: Vector2 = Vector2.INF
var _press_yaw := 0.0  # 누른 순간 카메라 요(회전했는지 판정)
var _press_ms := -1 # 누른 시각(길게 누르기를 아직 안 본 누름). 봤거나 누름이 아니면 -1


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
		_press_ms = Time.get_ticks_msec()
		_press_yaw = camera.global_rotation.y
	elif _press_pos != Vector2.INF:
		if is_equal_approx(_press_yaw, camera.global_rotation.y):  # 꾹 누르고 회전했으면 명령 없음(개정 14 §1)
			_pending = mb.position
		_press_pos = Vector2.INF


func _physics_process(_delta: float) -> void:
	if _press_pos != Vector2.INF and _press_ms >= 0 and Time.get_ticks_msec() - _press_ms >= LONG_PRESS_MS:
		_press_ms = -1
		var id := _building_at(_press_pos)
		if id != "":
			_press_pos = Vector2.INF  # 뗄 때 탭이 아니다
			building_panel.open_building(id)
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


## 상인(레이어 32) → 건물(레이어 16) → 성문(레이어 2, 선택된 영웅이 없을 때만 여기 온다) 탭. 처리했으면 true.
func _tap_object(screen_pos: Vector2) -> bool:
	if not _pick(screen_pos, LAYER_MERCHANT).is_empty():
		panel.open()
		return true
	var hit := _pick(screen_pos, LAYER_TAP)
	var id: String = hit.collider.get_meta("building", "") if not hit.is_empty() else ""
	if id == "tavern" and recruit != null:
		recruit.open()
		return true
	if id != "" and Economy.res_of(id) != "" and Economy.pending(id, Economy.time_now()) > 0:
		Economy.collect(id, Economy.time_now())  # "+N"은 collected 시그널로(온라인은 응답이 왔을 때)
		return true
	if id == "" and not _pick(screen_pos, LAYER_GATE).is_empty():
		id = GameData.GATE
	if id == "":
		return false
	building_panel.open_building(id)
	return true


## 길게 누른 자리의 건물 id(성문은 "gate"). 상인·건물 아닌 곳이면 "".
func _building_at(screen_pos: Vector2) -> String:
	if not _pick(screen_pos, LAYER_MERCHANT).is_empty():
		return ""  # 상인은 건물이 아니다 — 뒤쪽 건물 상자가 대신 잡히지 않게
	var hit := _pick(screen_pos, LAYER_TAP)
	if not hit.is_empty():
		return hit.collider.get_meta("building", "")
	return GameData.GATE if not _pick(screen_pos, LAYER_GATE).is_empty() else ""


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

extends Node
## 탭 → 영웅은 화면 좌표로, 성문·성벽은 카메라 레이캐스트로, 바닥은 y=0 평면과의 교점으로 판정 →
## 영웅 선택 / 선택 영웅을 성문 앞(성문 탭)·성벽 위(성벽 탭 — 누른 지점에 가장 가까운 빈 자리, 같은 면 좌↔우도)·바닥 지점(그 외)으로 이동.
## 판정: 선택된 산 영웅이 없으면 HERO_TAP_PX 안 영웅 선택 → 상인·건물·성문(창) → 선택 해제. 있으면
## HERO_TAP_PRECISE_PX 안 영웅(선택된 영웅 자신이면 해제, 아니면 그 영웅 선택) → 성문 → 성벽 →
## FOE_TAP_PX 안 적(공격 명령 — 그 적을 쫓아가 쓰러질 때까지 친다, 사용자 2026-10-14) → HERO_TAP_PX 안 다른 영웅 선택 → 상인·건물(창 + 선택 해제) → 바닥 자유 이동 순 (성문 앞 전사가 성문 탭을 가로채지 않게).
## 영웅을 고른 채 UI(버튼·창 등 GUI가 먹는 곳)를 누르면 선택을 푼다 — 그 누름으로 선택이 바뀌었으면(초상화 줄) 그대로.
## 드래그(카메라 이동)와 구분: 누른 뒤 뗄 때까지 TAP_MAX_PX 넘게 움직이지 않고 두 번째 손가락도 없을 때만 탭.
## 상인 탭은 거래 창, 주점 탭은 모집 창, 자원 건물 탭은 쌓인 게 있으면 수집(+N)·없으면 건물 창, 병사 건물 탭은 훈련이 끝났으면 수령
## (개정 16, 알림 "보병 +n")·아니면 건물 창, 연구소 탭은 플라스크 말풍선이 떠 있으면 연구 창(개정 24)·아니면 건물 창, 그 밖의 건물 탭은 건물 창(개정 12 §2.5).
## 건물은 레이가 꿴 판정체 중 화면 중심이 탭에 가장 가까운 것(_building_hit, 개정 15 — 앞 건물 상자가 뒤 병사 건물 지붕을 가리지 않게).
## 성문 탭은 선택된 영웅이 있으면 그 영웅의 성문 명령이 먼저이고, 없으면 성문 건물 창. 모두 영웅 선택은 건드리지 않는다.
## 길게 누르기(LONG_PRESS_MS, 같은 탭 조건: 움직이지 않고 두 번째 손가락 없음): 건물·성문이면 누른 채로 건물 창을 열고 그 누름은 탭이
## 되지 않는다(주점·자원 건물도 건물 창). 건물이 아니면(바닥·영웅·상인) 아무 일 없이 뗄 때 보통 탭이다.
## 입력을 소비하지 않는다 — 카메라 리그도 같은 이벤트를 본다(거래 창이 열려 있으면 GUI가 먼저 먹어 둘 다 못 받는다).
## 터치는 emulate_mouse_from_touch로 마우스 이벤트가 되므로 마우스만 처리.
## 던전(arena_r > 0): 성문·성벽·건물·상인이 없다 — 영웅 선택과 바닥 이동만(같은 탭 규칙), 바닥 지점은 중심에서 arena_r 안으로 자른다.

const Formation := preload("res://scripts/formation.gd")
const Balance := preload("res://scripts/balance.gd")
const Art := preload("res://scripts/art.gd")
const GameData := preload("res://scripts/game_data.gd")
const RouteMarker := preload("res://scripts/route_marker.gd")
const Crowd := preload("res://scripts/crowd.gd")

const LAYER_GATE := 2
const LAYER_WALL := 8
const LAYER_TAP := 16  # 건물 탭 판정체(buildings.gd)
const LAYER_MERCHANT := 32  # 상인·수레 탭 판정체 — 건물보다 먼저 본다(앞쪽 벌목장·채석장 상자에 가리지 않게)
const TAP_MAX_PX := 12.0
const HERO_TAP_PX := 32.0  # 화면(논리 720px 폭 기준)에서 영웅 중심까지 이 거리 안이면 그 영웅. 줌과 무관
const HERO_TAP_PRECISE_PX := 12.0  # 영웅 선택 중에는 이만큼 가까워야 성문·성벽보다 영웅이 먼저
const FOE_TAP_PX := 24.0  # 영웅 선택 중 적 중심에서 이 안(+ 큰 적은 몸 반지름)을 누르면 공격 명령(바닥 이동 아님)
const GROUND_MARGIN := 4.0   # 바닥 명령 지점을 맵 가장자리에서 이만큼 안으로 자른다
const LONG_PRESS_MS := 500
const MAX_TAP_HITS := 4  # 한 탭 레이가 꿰어 보는 건물 판정체 수(_building_hit)
const TAG_TAP_PAD := 6.0  # 말풍선 탭 여유(논리 px)

var camera: Camera3D
var selected
var badges  # 수집 "+N" 표시(badges.gd)
var panel   # 상인 거래 창(merchant_panel.gd)
var recruit  # 주점 모집 창(recruit_panel.gd)
var building_panel  # 건물 창(building_panel.gd)
var research  # 연구 창(research_panel.gd, 개정 24) — 연구소 말풍선 탭
var dispatch  # 파견소 창(dispatch_panel.gd, 2026-10-13) — 파견소 말풍선 탭
var arena_r := 0.0  # > 0이면 던전: 영웅 선택·바닥 이동만, 바닥 지점은 이 반경 안
var arena_side := INF  # 아레나: 바닥 지점은 화면 가로(spot v)로 이만큼 안(양옆이 막힌 무대)

var _press_pos: Vector2 = Vector2.INF
var _pending: Vector2 = Vector2.INF
var _press_yaw := 0.0  # 누른 순간 카메라 요(회전했는지 판정)
var _press_ms := -1 # 누른 시각(길게 누르기를 아직 안 본 누름). 봤거나 누름이 아니면 -1
var _gui_tap := false  # 이번 누름을 GUI가 먹었다(_unhandled_input에 오지 않았다)
var _gui_sel  # 누른 순간의 선택 영웅
var _gui_check := false  # 뗐다 — 다음 물리 프레임에 GUI 누름이면 선택 해제
var _routes := {}  # 영웅 → 이동 경로 표시(route_marker.gd). 영웅마다 하나, 새 명령이면 바꾼다


func _ready() -> void:
	Economy.collected.connect(_on_collected)


func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_gui_tap = true  # _unhandled_input까지 오면 지운다
		_gui_sel = selected
	elif _gui_tap:
		_gui_check = true


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
		_gui_tap = false
		_press_pos = mb.position
		_press_ms = Time.get_ticks_msec()
		_press_yaw = camera.global_rotation.y
	elif _press_pos != Vector2.INF:
		if is_equal_approx(_press_yaw, camera.global_rotation.y):  # 꾹 누르고 회전했으면 명령 없음(개정 14 §1)
			_pending = mb.position
		_press_pos = Vector2.INF


func _physics_process(_delta: float) -> void:
	if _gui_check:
		_gui_check = false
		if _gui_tap and selected != null and selected == _gui_sel:
			_select(null)  # UI를 눌렀다(초상화로 다른 영웅을 고른 게 아니면)
		_gui_tap = false
	if arena_r <= 0.0 and not stage_running() and _press_pos != Vector2.INF and _press_ms >= 0 and Time.get_ticks_msec() - _press_ms >= LONG_PRESS_MS:
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
		if tapped == null and arena_r <= 0.0 and _tap_object(screen_pos):
			return  # 상인·자원 건물: 선택은 그대로(없으면 없는 채)
		_select(tapped)
		return
	var hero = _hero_at(screen_pos, HERO_TAP_PRECISE_PX)
	if hero != null:
		_select(null if hero == selected else hero)  # 선택된 영웅을 다시 누르면 해제
		return
	var foe = _foe_at(screen_pos, FOE_TAP_PX)
	if foe != null:
		selected.attack_unit(foe)  # 같은 적을 거듭 누르면 영웅 쪽에서 무시한다
		_show_target(selected, foe)
		return
	if arena_r <= 0.0:
		var hit := _pick(screen_pos, LAYER_GATE)
		if not hit.is_empty():
			var gside: int = hit.collider.get_meta("side")
			if selected.move_to(gside, Formation.POST_GATE, float(hit.collider.get_meta("at", 0.0))):  # 누른 성문 앞 빈 자리(가까운 순)
				_show_route(selected, selected.stand_position())
			return
		hit = _pick(screen_pos, LAYER_WALL)
		if not hit.is_empty():
			var wside: int = hit.collider.get_meta("side")
			if selected.move_to(wside, Formation.POST_WALL, Formation.perp(wside).dot(hit.position)):  # 누른 쪽에 가까운 빈 자리
				_show_route(selected, selected.stand_position())
			return
	hero = _hero_at(screen_pos, HERO_TAP_PX)
	if hero != null and hero != selected:
		_select(hero)
		return
	if arena_r <= 0.0 and _tap_object(screen_pos):
		_select(null)  # 상인·건물을 눌렀다
		return
	var ground = _ground_point(screen_pos)
	if ground == null:
		_select(null)
		return
	selected.move_to_point(ground)
	_show_route(selected, ground)


func _pick(screen_pos: Vector2, layer_mask: int) -> Dictionary:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * camera.far
	var q := PhysicsRayQueryParameters3D.create(from, to, layer_mask)
	q.collide_with_areas = true
	q.collide_with_bodies = true  # 성문·성벽은 Area, 건물·상인 탭 판정체는 Body — 레이어 마스크로 가른다
	return camera.get_world_3d().direct_space_state.intersect_ray(q)


## 탭 위치의 건물 id(없으면 ""). 레이가 건물 판정체(부지 상자) 여럿을 꿰면 — 기본 카메라에서 앞 건물(주점·성채) 상자가 뒤 병사 건물
## 지붕까지 덮는다 — 판정체 중심(상자 가운데)의 화면 위치가 탭에 가장 가까운 건물을 고른다(개정 15). 앞 건물 앞면을 누르면 그 건물이 더 가깝다.
func _building_hit(screen_pos: Vector2) -> String:
	var from := camera.project_ray_origin(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(screen_pos) * camera.far, LAYER_TAP)
	var space := camera.get_world_3d().direct_space_state
	var skip: Array[RID] = []
	var best := ""
	var best_d := INF
	for i in MAX_TAP_HITS:
		q.exclude = skip
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var d := camera.unproject_position(hit.collider.global_position).distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = hit.collider.get_meta("building", "")
		skip.append(hit.rid)
	return best


## 화면 공간 말풍선(자원·훈련 완료·연구 플라스크 — 이름표 덩어리 맨 위 BUBBLE_BLOCK)을 누른 건물 id. 말풍선은 건물에서 떠 있어
## 레이로는 뒤 건물이 잡힌다 — 그 건물로 본다. 이름표 자체는 보지 않는다(다른 건물·바닥 탭을 가리지 않게). 없으면 "".
func _bubble_hit(screen_pos: Vector2) -> String:
	var tags = badges.tags if badges != null else null
	if tags == null or not badges.visible:  # 전투 중 숨긴 말풍선은 누를 수 없다
		return ""
	tags.layout()
	for id in badges.bubble_ids(Economy.time_now()):
		var s: Rect2 = tags.stacks.get(id, Rect2())
		if s.size.y > 0.0 and Rect2(s.position, Vector2(s.size.x, badges.BUBBLE_BLOCK)).grow(TAG_TAP_PAD).has_point(screen_pos):
			return id
	return ""


## 말풍선(화면 공간) → 상인(레이어 32) → 건물(레이어 16) → 성문(레이어 2, 선택된 영웅이 없을 때만 여기 온다) 탭. 처리했으면 true.
func _tap_object(screen_pos: Vector2) -> bool:
	if not _pick(screen_pos, LAYER_MERCHANT).is_empty() and (stage_running() or _bubble_hit(screen_pos) == ""):
		panel.open()
		return true
	if stage_running():
		return false  # 스테이지를 미는 동안 건물·말풍선·성문은 탭이 안 된다(사용자 2026-10-18) — 탭은 영웅 고르기로
	var id := _bubble_hit(screen_pos)
	if id == "":
		id = _building_hit(screen_pos)
	if id != "" and not Economy.is_built(id):  # 튜토리얼 공터: 짓기 창
		building_panel.open_building(id)
		return true
	if id == "tavern" and recruit != null:
		recruit.open()
		return true
	if id != "" and Economy.yield_of(id) != "" and Economy.pending(id, Economy.time_now()) > 0:
		Economy.collect(id, Economy.time_now())  # "+N"은 collected 시그널로(온라인은 응답이 왔을 때)
		return true
	if id != "" and Economy.training(id).ready:
		Economy.collect_training(id)  # 알림 "보병 +n"(온라인은 응답이 왔을 때)
		return true
	if id == GameData.LAB and research != null and badges.research_bubble():
		research.open()  # 개정 24: 플라스크 말풍선이 떠 있으면 곧바로 연구 창
		return true
	if id == GameData.DISPATCH and dispatch != null and badges.dispatch_bubble(Economy.time_now()):
		dispatch.open()  # 2026-10-13: 금화 자루 말풍선이 떠 있으면 곧바로 파견소 창
		return true
	if id == "" and not _pick(screen_pos, LAYER_GATE).is_empty():
		id = GameData.GATE
	if id == "":
		return false
	building_panel.open_building(id)
	return true


## 스테이지 전투 중(성 화면에서 스테이지를 미는 동안). 이때는 건물 탭·길게 누르기가 아무것도 열지 않는다.
static func stage_running() -> bool:
	return GameState.mode == GameState.Mode.STAGE or GameState.mode == GameState.Mode.COUNTDOWN


## 길게 누른 자리의 건물 id(성문은 "gate"). 상인·건물 아닌 곳이면 "".
func _building_at(screen_pos: Vector2) -> String:
	if not _pick(screen_pos, LAYER_MERCHANT).is_empty():
		return ""  # 상인은 건물이 아니다 — 뒤쪽 건물 상자가 대신 잡히지 않게
	var id := _building_hit(screen_pos)
	if id != "":
		return id
	return GameData.GATE if not _pick(screen_pos, LAYER_GATE).is_empty() else ""


## 수집 결과 "+N". 오프라인은 탭 즉시, 온라인은 서버 응답의 amount로.
func _on_collected(building_id: String, res_id: String, amount: int) -> void:
	if badges == null:
		return  # 던전 피커
	badges.pop(badges.anchor(building_id), res_id, amount)


## 탭 위치의 바닥(y=0) 지점, 맵 안으로 자름. 바닥을 못 맞히면 null.
func _ground_point(screen_pos: Vector2):
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))
	if hit == null:
		return null
	if arena_r > 0.0:
		var flat := Crowd.keep_side(Vector2(hit.x, hit.z).limit_length(arena_r), arena_side)
		return Vector3(flat.x, 0.0, flat.y)
	var lim := Balance.MAP_HALF - GROUND_MARGIN
	return Vector3(clampf(hit.x, -lim, lim), 0.0, clampf(hit.z, -lim, lim))


## 이동 명령의 경로와 도착지를 영웅이 도착할 때까지 띄운다(route_marker.gd). 같은 영웅의 이전 표시는 지운다.
func _show_route(hero, dest: Vector3) -> void:
	_show_marker(hero, dest, null)


## 공격 명령 표시: 영웅 → 표적 점선 + 표적 발밑 빨간 링(표적이 쓰러지거나 새 명령이면 사라진다).
func _show_target(hero, foe) -> void:
	if hero.has_method("focus_target") and hero.focus_target() != foe and hero.get("puppet") != true:
		return  # 명령을 받지 않았다(배치 중 등)
	_show_marker(hero, foe.global_position, foe)


func _show_marker(hero, dest: Vector3, foe) -> void:
	var old = _routes.get(hero)
	if old != null and is_instance_valid(old) and not old.is_queued_for_deletion():
		if old.target == foe and (foe != null or Vector2(old.dest.x - dest.x, old.dest.z - dest.z).length() < 0.01):
			return  # 같은 명령을 거듭 눌렀다: 표시 그대로(깜빡이지 않게)
		old.queue_free()
	var m := RouteMarker.new()
	m.name = "Route"
	m.setup(hero, dest, foe)
	get_parent().add_child(m)
	_routes[hero] = m
	for h in _routes.keys():  # 사라진 영웅·표시 정리
		if not is_instance_valid(h) or not is_instance_valid(_routes[h]):
			_routes.erase(h)


## 탭 위치에서 화면상 가장 가까운 살아 있는 영웅 (radius_px 이내). 없으면 null.
func _hero_at(screen_pos: Vector2, radius_px: float):
	var best = null
	var best_d := radius_px
	for h in get_tree().get_nodes_in_group("heroes"):
		if not h.is_alive() or h.get("mine") == false:  # 공성전: 다른 길드원 영웅은 고를 수 없다
			continue
		var d := camera.unproject_position(h.global_position + Vector3(0, 0.8, 0)).distance_to(screen_pos)
		if d <= best_d:
			best_d = d
			best = h
	return best


## 탭 위치에서 화면상 가장 가까운, 선택 영웅의 살아 있는 적(영웅의 적 그룹 — 성·던전은 괴물, PVP는 상대 영웅·병사, 공성전은 수비 영웅).
## radius_px에 큰 적(보스·드래곤)은 화면상 몸 반지름을 더한다. 공성전 성문·성채는 적이 아니다(누르면 바닥 이동). 없으면 null.
func _foe_at(screen_pos: Vector2, radius_px: float):
	var group: String = selected.get("foes") if selected != null and selected.get("foes") != null else "monsters"
	var right := camera.global_transform.basis.x
	var best = null
	var best_d := INF
	for m in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(m) or not m.is_inside_tree() or m.get("is_structure") == true or not (m is Node3D):
			continue
		if m.has_method("is_alive") and not m.is_alive():
			continue
		if not m.is_visible_in_tree() or camera.is_position_behind(m.global_position):
			continue
		var c := camera.unproject_position(m.global_position + Vector3(0, 0.8, 0))
		var r := radius_px
		var hr := float(m.hit_radius()) if m.has_method("hit_radius") else 0.0
		if hr > 0.0:
			r += camera.unproject_position(m.global_position + Vector3(0, 0.8, 0) + right * hr).distance_to(c)
		var d := c.distance_to(screen_pos)
		if d <= r and d < best_d:
			best_d = d
			best = m
	return best


func _select(hero) -> void:
	if selected != null and is_instance_valid(selected):
		selected.selected = false
	selected = hero
	if selected != null:
		selected.selected = true

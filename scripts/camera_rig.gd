extends Node3D
## 쿼터뷰 직교 카메라 리그. 리그 위치 = 화면 중앙이 바라보는 바닥 지점.
## 한 손가락/마우스 드래그로 이동(DRAG_THRESHOLD_PX 넘으면 드래그 확정), 휠·두 손가락 핀치로 줌. pan_to = 지점으로 부드럽게 이동(HUD 성문 막대 탭).
## 한 손가락 터치 팬은 emulate_mouse_from_touch로 들어온다(0번 손가락 → 마우스 이벤트) —
## pan_pixels는 InputEventScreenDrag에서는 호출되지 않고 InputEventMouseMotion 쪽에서만 호출된다.
## 입력을 소비하지 않는다 — 탭 판정(UnitPicker)도 같은 이벤트를 본다.

const Balance := preload("res://scripts/balance.gd")
const GameData := preload("res://scripts/game_data.gd")

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
const PUNCH_ZOOM := 0.93  # 큰 스킬(SSR 발동) 때 잠깐 당기는 줌 배율
const PUNCH_IN_SEC := 0.12
const PUNCH_OUT_SEC := 0.45
const PUNCH_GAP := 2.0  # 당김 최소 간격(초) — 잦으면 어지럽다
const KICK_SEC := 0.22  # 스킬 타격 흔들림(개정 26) 길이
const KICK_AMP_MAX := 0.7
const FLASH_GAP := 0.35  # 화면 섬광 최소 간격(초)
const FLASH_SEC := 0.2
const STOP_SCALE := 0.06  # 히트스톱 동안 게임 시간 배율
const STOP_MAX := 0.1  # 히트스톱 최대 길이(실제 초)
const STOP_GAP := 0.6  # 히트스톱 최소 간격(실제 초) — 잦으면 끊겨 보인다
const SLOW_SCALE := 0.3  # 결정타 슬로모션 동안 게임 시간 배율
const SLOW_SEC := 0.9  # 결정타 슬로모션 길이(실제 초)
# 싸움 따라가기(2026-10-07 디자인 보강 2번, follow): 던전·PVP·길드 드래곤에서 살아 있는 유닛 무리를 화면 가운데에 두고, 무리가 들어오는
# 가장 가까운 줌(follow_min ~ follow_max)으로 부드럽게 당긴다 — 영웅이 화면에서 더 크게 보인다. 손으로 끌거나 줌하면 잠깐 쉰다.
const FOLLOW_PAUSE_SEC := 3.0  # 손으로 움직인 뒤 이만큼 따라가기를 쉰다
const FOLLOW_MOVE_RATE := 2.5  # 위치를 따라가는 빠르기(1/초)
const FOLLOW_OUT_RATE := 3.0  # 무리가 화면 밖으로 퍼질 때 줌을 빼는 빠르기(1/초)
const FOLLOW_IN_RATE := 0.8  # 모였을 때 줌을 당기는 빠르기(1/초) — 천천히
const FOLLOW_MARGIN := 2.5  # 무리 둘레 여유(m)
const FOLLOW_TALL := 3.0  # 유닛 발에서 HP 바까지 높이(m). 큰 유닛은 메타 "frame_h"로 준다
const FOLLOW_BOSS_TALL := 4.5
const FOLLOW_TOP_PX := 170.0  # 화면 위 HUD가 덮는 높이(px, 가로 720 기준) — 무리를 그 아래에 둔다
const FOLLOW_BOTTOM_PX := 150.0  # 화면 아래 영웅 띠가 덮는 높이
const FOLLOW_GROUPS := ["crowd", "monsters"]

var camera: Camera3D

var _press_ms := 0
var _rotating := false  # 꾹 누름 회전 대기·회전 중
var _indicator: Control  # 회전 표시(원 위 화살 둘)
var _press_pos: Vector2 = Vector2.INF
var _dragging := false
var _touches := {}  # 터치 index -> 화면 위치 (핀치용)
var _pan: Tween  # pan_to 진행 중(손으로 끌면 멈춘다)
var _shake: Tween  # 흔드는 중(개정 17)
var _punch: Tween  # 당김 중
var _punch_base := 0.0  # 당기기 전 줌(손으로 줌하면 이 값 기준으로 바뀐다)
var _punch_at := -INF
var _flash_rect: ColorRect
var _flash_tw: Tween
var _flash_at := -INF
var _shake_amp := 0.0  # 지금 흔들림의 처음 진폭(더 센 타격이 오면 덮는다)
static var _stop_at := -INF  # 리그가 히트스톱 중에 사라져도 되돌림 타이머가 리그를 건드리지 않게 정적
static var _stopping := false
static var _gen := 0  # 멈춤/슬로모션 차례 — 늦게 끝난 이전 타이머가 새 슬로모션을 되돌리지 않게
static var _slow := false  # 결정타 슬로모션 중
var follow_scope: Node  # 이 노드 아래 유닛만 따라간다(null = 따라가지 않음)
var follow_min := 0.0
var follow_max := 0.0
var _follow_hold := -INF  # 이 시각(초)까지 따라가기 쉼
var _follow_snap := false  # 다음 프레임에 곧바로 맞춘다(처음)


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
	var flash_layer := CanvasLayer.new()  # 화면 섬광(2026-10-07): 3D 위, HUD 아래
	flash_layer.layer = 0
	add_child(flash_layer)
	_flash_rect = ColorRect.new()
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.visible = false
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flash_rect.material = add
	flash_layer.add_child(_flash_rect)


## 누른 시간·움직인 거리 → "tap"(아직 미정) / "hold"(회전 대기) / "pan"(이미 드래그).
static func hold_state(held_sec: float, moved_px: float) -> String:
	if moved_px > DRAG_THRESHOLD_PX:
		return "pan"
	return "hold" if held_sec >= HOLD_SEC else "tap"


## 화면상 카메라 요(도). 기본 YAW_DEG, 회전하면 변한다.
func yaw_deg() -> float:
	return rad_to_deg(camera.global_rotation.y)


func _process(delta: float) -> void:
	_follow_step(delta)
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
			hold_follow()
			zoom_by(1.0 / ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			hold_follow()
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
			hold_follow()
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


## 카메라 흔들림(개정 17 §3, 폭발): sec초 동안 화면 평면으로 최대 amp m, 점점 줄어 0으로. 흔드는 중이면 겹치지 않는다(합치지 않음).
## 위치·줌 대신 카메라 h_offset·v_offset만 쓴다 — 팬·회전과 다투지 않는다.
func shake(sec: float, amp: float) -> void:
	if _shake != null and _shake.is_running():
		return
	_shake_amp = amp
	_shake = create_tween()
	_shake.tween_method(_shake_at.bind(amp), 1.0, 0.0, sec)


func _shake_at(k: float, amp: float) -> void:
	camera.h_offset = randf_range(-amp, amp) * k
	camera.v_offset = randf_range(-amp, amp) * k


## 스킬 타격감(개정 26): at이 화면 안이면 흔들림 amp m(지금 흔들림보다 셀 때만 덮는다, KICK_AMP_MAX까지)과
## 히트스톱 stop초(게임 시간을 STOP_SCALE배로 — 실제 시간 기준, STOP_GAP초에 한 번). 흔들림 설정(fx_shake)을 끄면 둘 다 없다.
func kick(at: Vector3, amp: float, stop := 0.0) -> void:
	if not GameData.fx_shake() or not camera.is_position_in_frustum(at):
		return
	amp = minf(amp, KICK_AMP_MAX)
	if _shake == null or not _shake.is_running() or amp > _shake_amp * 0.6:
		if _shake != null:
			_shake.kill()
		_shake_amp = amp
		_shake = create_tween()
		_shake.tween_method(_shake_at.bind(amp), 1.0, 0.0, KICK_SEC).set_ease(Tween.EASE_OUT)
		_shake.tween_callback(func(): camera.h_offset = 0.0; camera.v_offset = 0.0)
	var now := Time.get_ticks_msec() / 1000.0
	if stop > 0.0 and not _stopping and now - _stop_at >= STOP_GAP and Engine.time_scale > STOP_SCALE:
		_stop_at = now
		_stopping = true
		var was := Engine.time_scale
		Engine.time_scale = was * STOP_SCALE
		_gen += 1
		get_tree().create_timer(minf(stop, STOP_MAX), true, false, true).timeout.connect(Callable(get_script(), "_unstop").bind(was, _gen))


## 결정타 슬로모션(2026-10-07 전투 재미): PVP 마지막 처치·보스 처치 순간 게임 시간을 SLOW_SCALE배로 SLOW_SEC 실제 초 + 줌 당김.
## 히트스톱과 같은 되돌림(_unstop — 배속 버튼 배율로). 결정타의 히트스톱 중이면 그 히트스톱을 이어받는다(되돌릴 배율은 히트스톱 전 배율).
func slowmo() -> void:
	if _slow:
		return
	var was := Engine.time_scale
	if _stopping:  # 히트스톱 중 — 지금 배율은 이미 줄어든 값
		var managed: float = load("res://scripts/speed_button.gd").base
		was = managed if managed > 0.0 else 1.0
	_stopping = true
	_slow = true
	_stop_at = Time.get_ticks_msec() / 1000.0
	Engine.time_scale = was * SLOW_SCALE
	_gen += 1
	get_tree().create_timer(SLOW_SEC, true, false, true).timeout.connect(Callable(get_script(), "_unstop").bind(was, _gen))
	if GameData.fx_shake():
		punch()


## 지금 화면 카메라의 리그(없으면 null) — 장면 어디서든 slowmo를 부를 때.
static func of(node: Node):
	var cam := node.get_viewport().get_camera_3d() if node.is_inside_tree() else null
	return cam.get_parent() if cam != null and cam.get_parent().has_method("slowmo") else null


static func _unstop(was: float, gen := -1) -> void:
	if gen >= 0 and gen != _gen:  # 뒤에 시작한 멈춤/슬로모션이 있다 — 그쪽이 되돌린다
		return
	_stopping = false
	_slow = false
	var managed: float = load("res://scripts/speed_button.gd").base  # 배속 버튼이 배율을 맡았으면(히트스톱 중 켬/끔·던전 입장) 지금 배율로
	Engine.time_scale = managed if managed > 0.0 else was


## 큰 타격 순간 화면 전체가 color로 잠깐(FLASH_SEC) 밝아진다(더하기 섞기, 세기 strength 0~1). at이 화면 안이고 흔들림 설정이 켜졌을 때만,
## FLASH_GAP초에 한 번(겹치면 더 센 쪽).
func flash(at: Vector3, color: Color, strength: float) -> void:
	if _flash_rect == null or not GameData.fx_shake() or not camera.is_position_in_frustum(at):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _flash_at < FLASH_GAP and strength <= _flash_rect.color.a:
		return
	_flash_at = now
	if _flash_tw != null:
		_flash_tw.kill()
	_flash_rect.visible = true
	_flash_rect.color = Color(color, strength)
	_flash_tw = create_tween().set_ignore_time_scale(true)
	_flash_tw.tween_property(_flash_rect, "color:a", 0.0, FLASH_SEC).set_ease(Tween.EASE_OUT)
	_flash_tw.tween_callback(func(): _flash_rect.visible = false)


func is_shaking() -> bool:
	return _shake != null and _shake.is_running()


## factor < 1 이면 확대. 당김 중이면 당김을 멈추고 당기기 전 줌을 기준으로 바꾼다(손이 이긴다).
func zoom_by(factor: float) -> void:
	if is_punching():
		_punch.kill()
		camera.size = _punch_base
	camera.size = clampf(camera.size * factor, Balance.CAMERA_SIZE_MIN, Balance.CAMERA_SIZE_MAX)
	_fit_depth()


## 큰 순간 강조(아트 방향 §4 — SSR 스킬 발동): 화면 안의 at 쪽은 그대로 두고 줌만 PUNCH_ZOOM배로 잠깐 당겼다가 되돌린다.
## PUNCH_GAP초에 한 번, 흔드는 설정(fx_shake)을 끄면 부르는 쪽이 부르지 않는다. 팬·회전과 다투지 않는다(줌만).
func punch() -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if is_punching() or now - _punch_at < PUNCH_GAP:
		return false
	_punch_at = now
	_punch_base = camera.size
	_punch = create_tween()
	_punch.tween_method(_punch_size, 1.0, PUNCH_ZOOM, PUNCH_IN_SEC).set_ease(Tween.EASE_OUT)
	_punch.tween_method(_punch_size, PUNCH_ZOOM, 1.0, PUNCH_OUT_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return true


func _punch_size(k: float) -> void:
	camera.size = _punch_base * k


func is_punching() -> bool:
	return _punch != null and _punch.is_running()


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
		hold_follow()
		zoom_by(old_d / new_d)


## 싸움 따라가기를 켠다(scope 아래 살아 있는 유닛 무리, 줌 min_size~max_size m). 첫 프레임은 곧바로 맞춘다.
func follow(scope: Node, min_size: float, max_size: float) -> void:
	follow_scope = scope
	follow_min = min_size
	follow_max = max_size
	_follow_snap = true


## 손으로 끌거나 줌했다 — FOLLOW_PAUSE_SEC 동안 따라가지 않는다.
func hold_follow() -> void:
	_follow_hold = Time.get_ticks_msec() / 1000.0 + FOLLOW_PAUSE_SEC


## 따라갈 목표 [바닥 점, 줌]. 유닛이 없으면 []. 화면 위 HUD·아래 띠를 뺀 곳 가운데에 무리를 둔다.
func follow_target() -> Array:
	if follow_scope == null or not is_instance_valid(follow_scope):
		return []
	var pts := []
	var seen := {}
	for g in FOLLOW_GROUPS:
		for n in get_tree().get_nodes_in_group(g):
			if seen.has(n) or not (n is Node3D) or not follow_scope.is_ancestor_of(n) or not n.is_visible_in_tree():
				continue
			seen[n] = true
			var hp = n.get("hp")
			if hp != null and float(hp) <= 0.0:
				continue
			pts.append([n.global_position, n.get_meta("frame_h", FOLLOW_BOSS_TALL if n.get("is_boss") == true else FOLLOW_TALL)])
	var at := position
	at.y = 0.0
	var out := frame(pts, camera.global_basis.x, camera.global_basis.y, get_viewport().get_visible_rect().size, at, follow_min, follow_max)
	if not out.is_empty():
		out[0].y = position.y
	return out


## 순수 계산(run_tests): pts = [[발 위치, 키 m], …], r·u = 화면 오른쪽·위 방향(월드), vp = 화면 크기, at = 지금 리그 바닥 점.
## 무리(발~HP 바 + 여유)가 HUD 아래·띠 위 쓸 수 있는 곳에 들어오는 가장 가까운 줌(min_size~max_size)과 그 가운데를 보는 바닥 점.
static func frame(pts: Array, r: Vector3, u: Vector3, vp: Vector2, at: Vector3, min_size: float, max_size: float) -> Array:
	if pts.is_empty():
		return []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in pts:
		var p: Vector3 = q[0]
		var sx := p.dot(r)
		var sy := p.dot(u)
		lo = Vector2(minf(lo.x, sx), minf(lo.y, sy))
		hi = Vector2(maxf(hi.x, sx), maxf(hi.y, sy + float(q[1]) * u.y))
	var usable_px := maxf(vp.y - FOLLOW_TOP_PX - FOLLOW_BOTTOM_PX, vp.x)
	var need := maxf(hi.x - lo.x + FOLLOW_MARGIN * 2.0, (hi.y - lo.y + FOLLOW_MARGIN * 2.0) * vp.x / usable_px)
	var size := clampf(need, min_size, max_size)
	var c := (lo + hi) / 2.0
	var cy := c.y + (FOLLOW_TOP_PX - FOLLOW_BOTTOM_PX) / 2.0 * size / vp.x  # 쓸 수 있는 곳의 가운데 = 화면 가운데보다 아래
	var uh := Vector3(u.x, 0.0, u.z)
	var dest := at + r * (c.x - at.dot(r)) + uh / uh.length_squared() * (cy - at.dot(u))
	var limit := Balance.MAP_HALF - PAN_LIMIT_MARGIN
	return [Vector3(clampf(dest.x, -limit, limit), 0.0, clampf(dest.z, -limit, limit)), size]


func _follow_step(delta: float) -> void:
	if follow_scope == null or Time.get_ticks_msec() / 1000.0 < _follow_hold or (_pan != null and _pan.is_running()):
		return
	var tgt := follow_target()
	if tgt.is_empty():
		return
	var size: float = tgt[1]
	if _follow_snap:
		_follow_snap = false
		position = tgt[0]
		if not is_punching():
			camera.size = size
			_fit_depth()
		return
	position = position.lerp(tgt[0], 1.0 - exp(-FOLLOW_MOVE_RATE * delta))
	if not is_punching():
		var rate := FOLLOW_OUT_RATE if size > camera.size else FOLLOW_IN_RATE
		camera.size = lerpf(camera.size, size, 1.0 - exp(-rate * delta))
		_fit_depth()

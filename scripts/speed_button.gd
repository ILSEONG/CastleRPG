extends CanvasLayer
## x1.5 배속 버튼(사용자 2026-10-07): 성 화면(방치·스테이지 진행) 왼쪽 중하단. 누르면 바로 켬/끔 — 켜면 게임 시간(Engine.time_scale)이 1.5배.
## 켬/끔은 기기에만 남긴다(Prefs "speed_x15", 기본 끔 — 서버·DB에 보내지 않는다).
## 모든 컨텐츠(사용자 2026-10-07 "모든 컨텐츠에 1.5배", 길드전은 제외 "길드전은 아니야"): 성 화면(main)과 던전·PVP·길드 보스 장면
## (main._enter_dungeon이 하나씩 붙인다)에 같은 버튼이 있고 같은 설정을 쓴다. 서버는 실제 경과와 견주는 검사를 1.5배까지 받아 준다
## (rules.MAX_GAME_SPEED). 길드전 장면에는 버튼이 없어 늘 1배.
## 방치 전투도 제외(사용자 2026-10-07 "방치전투때도 아니야"): 성 화면 버튼(castle = true)은 스테이지를 미는 동안(스테이지·결과·카운트다운)만
## 빠르게 하고, 대기(방치)로 돌아오면 켜 둔 채로 1배. 대기(방치) 중에는 버튼을 숨긴다(사용자 2026-10-13 "방치모드일때는 빼줘" —
## 자리 계산은 계속해서 채팅 줄·[핫딜]이 따라오는 자리는 그대로).
## x2(사용자 2026-10-13 "1.5를 한번더 누르면 2배"): 누를 때마다 x1 → x1.5 → x2 → x1. 설정 "speed_level"(1·1.5·2), 예전 "speed_x15" 켬은 x1.5로 읽는다.
## 건물·훈련·연구·방치 수입·초기화는 실제 시각(Economy.time_now)이라 배속과 무관.
## 자리: 왼쪽 아래, 오른쪽 아래 [메뉴] 토글 버튼과 같은 높이(사용자 2026-10-07 "메뉴 버튼과 같은 높이") — 메뉴가 없으면 화면 높이 CENTER_Y 지점.
## 단 하단 영웅 초상화 줄·튜토리얼 카드보다 위(매 프레임 맞춘다). 채팅 줄과 [핫딜] 버튼은 이 버튼을 따라온다.

const UiKit := preload("res://scripts/ui_kit.gd")
const Prefs := preload("res://scripts/prefs.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")
const HudScript := preload("res://scripts/hud.gd")

const SPEED := 1.5
const LEVELS := [1.0, 1.5, 2.0]  # 누를 때마다 다음 단계(서버 rules.MAX_GAME_SPEED = 마지막 값)
const PREF_KEY := "speed_level"
const OLD_KEY := "speed_x15"  # 2026-10-07판 켬/끔(켬이면 x1.5)
const X2_COLOR := Color(0.93, 0.42, 0.18)  # x2: 주황빛 빨강(x1.5 호박색보다 진하게)
const SIZE := Vector2(84, 84)
const SIDE := 16.0
const ABOVE := 12.0  # 탭 바·초상화 줄·미션 카드 위 여백
const CENTER_Y := 0.70  # 버튼 가운데 = 화면 높이의 이 지점(왼쪽 중하단)
const OFF_COLOR := Color(0.30, 0.34, 0.46)  # 오른쪽 아래 메뉴 버튼과 같은 강철색

## 히트스톱(camera_rig)이 끝날 때 되돌릴 배율. 0이면 이 버튼이 손대지 않았다(히트스톱은 시작 전 배율로 되돌린다).
static var base := 0.0
static var _live := 0  # 트리에 있는 배속 버튼 수(월드를 다시 만들 때 새 버튼이 먼저 들어와도 끄지 않게)
static var _idle := false  # 성 화면이 대기(방치) 중 — 이때는 1배

var castle := false  # 성 화면 버튼(main): 방치 중엔 1배
var card  # tutorial_card.gd(있으면 그 위로)
var strip  # hero_strip.gd(보이면 그 위로)
var menu  # side_menu.gd(그 [메뉴] 토글과 아래 끝을 맞춘다)
var below  # build_button.gd(성 화면 [건물] 버튼 — 보이면 그 위로, 2026-10-13)
var button: Button
var _face: Control


static func is_on() -> bool:
	return level() > 1.0


## 고른 배율(1·1.5·2, 기기 설정).
static func level() -> float:
	var m := Prefs._music()
	var v = m.prefs.get(PREF_KEY, null) if m != null else null
	if v == null:
		return SPEED if Prefs.get_bool(OLD_KEY, false) else 1.0
	var f := float(v)
	for l in LEVELS:
		if is_equal_approx(f, l):
			return l
	return 1.0


## 다음 단계(x1 → x1.5 → x2 → x1).
static func next_level(cur: float) -> float:
	var i := LEVELS.find(cur)
	return LEVELS[(i + 1) % LEVELS.size()] if i >= 0 else LEVELS[1]


## 지금 배율(버튼이 트리에 있고 방치 중이 아니면 고른 배율).
static func speed() -> float:
	return level() if _live > 0 and not _idle else 1.0


static func _apply() -> void:
	var s := speed()
	if _live > 0 and s > 1.0:
		base = s
		Engine.time_scale = s
	elif base > 0.0:  # 켰다가 껐거나 성 화면을 떠났다 — 손댄 적이 있을 때만 1배로(테스트가 정한 배율은 건드리지 않는다)
		base = 1.0
		Engine.time_scale = 1.0


func _ready() -> void:
	layer = 1  # HUD와 같은 층(창은 2 이상이 덮는다)
	button = Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = SIZE
	button.size = SIZE
	button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_face = Control.new()
	_face.size = SIZE
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.draw.connect(_draw_face)
	button.add_child(_face)
	button.pressed.connect(toggle)
	add_child(button)
	var tut := get_node_or_null("/root/Tutorial") if castle else null  # tutorial.gd가 이 스크립트를 preload한다(자동 로드 이름을 직접 쓰지 않는다)
	if tut != null:
		tut.register_ui("hud:speed", button)  # 가이드 화살표
	_refresh()
	_place()
	_sync_visible()


func _enter_tree() -> void:
	_live += 1
	if castle:
		var gs := get_node_or_null("/root/GameState")
		if gs != null:
			_idle = gs.mode == gs.Mode.IDLE
			if not gs.mode_changed.is_connected(_on_mode):
				gs.mode_changed.connect(_on_mode)
	_apply()
	_sync_visible()
	_refresh()  # 다른 장면의 버튼에서 바꿨을 수 있다


func _exit_tree() -> void:
	_live -= 1
	if castle:
		_idle = false  # 던전·PVP·드래곤은 방치와 상관없다
	_apply()


func _on_mode(mode: int) -> void:
	if not is_inside_tree():
		return
	var gs := get_node_or_null("/root/GameState")
	_idle = gs != null and mode == gs.Mode.IDLE
	_apply()
	_sync_visible()


## 성 화면 버튼은 대기(방치) 중 숨긴다.
func _sync_visible() -> void:
	if button != null:
		button.visible = not (castle and _idle)


## 다음 단계로(x1 → x1.5 → x2 → x1) — 바로 적용, 기기에만 저장.
func toggle() -> void:
	set_level(next_level(level()))


func set_level(l: float) -> void:
	Prefs.set_value(PREF_KEY, l)
	_apply()
	_refresh()


## 켬(x1.5)/끔(x1).
func set_on(on: bool) -> void:
	set_level(SPEED if on else 1.0)


func _refresh() -> void:
	if button == null:
		return
	var l := level()
	UiKit.apply_button(button, X2_COLOR if l >= 2.0 else (UiKit.AMBER if l > 1.0 else OFF_COLOR), 12.0)
	_face.queue_redraw()


func _process(_delta: float) -> void:
	_place()


func _place() -> void:
	var vh := get_viewport().get_visible_rect().size.y
	var bottom := vh * CENTER_Y + SIZE.y / 2.0  # 버튼 아래 끝(위에서 잰 y)
	if menu != null and is_instance_valid(menu) and menu.toggle != null and menu.toggle.size.y > 0.0:
		bottom = menu.toggle.global_position.y + menu.toggle.size.y  # [메뉴] 토글과 같은 높이
	var limit := vh - float(HudScript.TAB_BAR_H) - ABOVE
	if strip != null and strip.visible and strip.row != null and strip.row.size.y > 0.0:
		limit = minf(limit, strip.row.global_position.y - ABOVE)
	if card != null and card.panel != null and card.panel.visible:
		limit = minf(limit, card.panel.global_position.y - ABOVE)
	bottom = minf(bottom, limit)
	if below != null and is_instance_valid(below) and below.visible and below.button != null:
		bottom = minf(bottom, below.button.position.y - ABOVE)  # [건물] 버튼 위
	button.position = Vector2(SIDE, bottom - SIZE.y)


func _draw_face() -> void:
	var l := level()
	var on := l > 1.0
	var ink := Color(UiKit.INK, 0.85)
	var col := Color.WHITE if on else Color(0.86, 0.89, 0.95)
	# 빨리 감기 삼각형 두 개
	var cy := 26.0
	var w := 13.0
	var h := 9.0
	for k in 2:
		var x := SIZE.x / 2.0 - w * 0.5 + k * w  # 두 삼각형(가로 2w)의 가운데 = 버튼 가운데
		var tri := PackedVector2Array([Vector2(x - w * 0.5, cy - h), Vector2(x + w * 0.5, cy), Vector2(x - w * 0.5, cy + h)])
		var rim := tri.duplicate()
		rim.append(rim[0])
		draw_poly(tri, rim, col)
	_text("x2" if l >= 2.0 else "x1.5", 50.0, 22, col, ink)
	_text("ON" if on else "OFF", 74.0, 16, col if on else Color(col, 0.75), ink)


func draw_poly(tri: PackedVector2Array, rim: PackedVector2Array, col: Color) -> void:
	_face.draw_polyline(rim, Color(UiKit.INK, 0.85), 4.0, true)
	_face.draw_colored_polygon(tri, col)


func _text(t: String, y: float, size: int, col: Color, ink: Color) -> void:
	_face.draw_string_outline(FONT, Vector2(0, y), t, HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, size, 5, ink)
	_face.draw_string(FONT, Vector2(0, y), t, HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, size, col)

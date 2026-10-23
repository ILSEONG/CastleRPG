extends CanvasLayer
## 스킬 자동/수동 버튼(사용자 2026-10-23, 블레이드 키우기·세븐나이츠 키우기처럼): 하단 영웅 초상화 줄 오른쪽 위. 누르면 바로 켬/끔.
## 켬(기본) = 지금처럼 액티브 스킬이 쿨이 차면 저절로 나간다. 끔 = 쿨이 찬 스킬은 초상화 위 스킬 칸에서 기다리고(금빛으로 빛난다),
## 칸을 누르면 그 영웅이 바로 쓴다(hero.request_skill). 패시브·확률 스킬은 늘 저절로.
## 성 스테이지·던전·PVP 결투가 같은 설정을 쓴다(기기에만 저장 — Prefs "skill_auto"). 길드전·총력전·길드 보스·파티는 늘 자동(버튼 없음).
## 자리: 오른쪽, 초상화 줄(row) 위 — 배속 버튼(왼쪽)과 마주 본다. 줄이 안 보이면 버튼도 숨긴다.

const Lang := preload("res://scripts/lang.gd")

const UiKit := preload("res://scripts/ui_kit.gd")
const Prefs := preload("res://scripts/prefs.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const PREF_KEY := "skill_auto"
const SIZE := Vector2(84, 84)
const SIDE := 16.0
const ABOVE := 12.0
const ON_COLOR := Color(0.27, 0.62, 0.36)  # 자동: 초록
const OFF_COLOR := Color(0.30, 0.34, 0.46)  # 수동: 배속 끔과 같은 강철색

var row: Control  # 초상화 줄(그 위에 둔다). 숨겨져 있으면 버튼도 숨김
var button: Button
var _face: Control


## 스킬 자동인가(기본 켬).
static func is_auto() -> bool:
	return Prefs.get_bool(PREF_KEY, true)


static func set_auto(on: bool) -> void:
	Prefs.set_value(PREF_KEY, on)


func _ready() -> void:
	layer = 1
	button = Button.new()
	button.name = "SkillAuto"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = SIZE
	button.size = SIZE
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS  # 누르는 순간 바뀐다
	_face = Control.new()
	_face.size = SIZE
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.draw.connect(_draw_face)
	button.add_child(_face)
	button.pressed.connect(toggle)
	add_child(button)
	_refresh()
	_place()


func toggle() -> void:
	set_auto(not is_auto())
	_refresh()


func _refresh() -> void:
	UiKit.apply_button(button, ON_COLOR if is_auto() else OFF_COLOR, 12.0)
	_face.queue_redraw()


func _process(_delta: float) -> void:
	_place()


func _place() -> void:
	var shown: bool = row != null and is_instance_valid(row) and row.is_visible_in_tree() and row.size.y > 0.0
	button.visible = shown
	if not shown:
		return
	var vw := get_viewport().get_visible_rect().size.x
	button.position = Vector2(vw - SIDE - SIZE.x, row.global_position.y - ABOVE - SIZE.y)
	if not _face.has_meta("auto") or _face.get_meta("auto") != is_auto():  # 다른 장면의 버튼에서 바꿨을 수 있다
		_face.set_meta("auto", is_auto())
		_refresh()


func _draw_face() -> void:
	var on := is_auto()
	var ink := Color(UiKit.INK, 0.85)
	var col := Color.WHITE if on else Color(0.86, 0.89, 0.95)
	_text(Lang.t("skill_auto_button.draw_face"), 30.0, 20, col, ink)
	_text("AUTO", 54.0, 21, col, ink)
	_text("ON" if on else "OFF", 76.0, 16, col if on else Color(col, 0.75), ink)


func _text(t: String, y: float, size: int, col: Color, ink: Color) -> void:
	_face.draw_string_outline(FONT, Vector2(0, y), t, HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, size, 5, ink)
	_face.draw_string(FONT, Vector2(0, y), t, HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, size, col)

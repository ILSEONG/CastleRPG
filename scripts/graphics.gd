extends CanvasLayer
## 그래픽·배터리 설정(2026-10-12, 설정 창 [화면]). main이 하나 만든다(current). 값은 기기 설정(Prefs, user://settings.json)에 남는다.
## - 품질 gfx_quality: high(그림자 켬, 3D 해상도 그대로) · mid(그림자 켬, 3D 해상도 ×0.8) · low(그림자 끔, 3D 해상도 ×0.65).
##   그림자는 장면의 DirectionalLight3D마다 끈다(나중에 생기는 던전·길드 장면 조명도 node_added로). 원래 켜져 있던 조명만 다시 켠다.
## - 프레임 gfx_fps: 60 또는 30(Engine.max_fps).
## - 절전 모드 power_saver(기본 끔): SAVER_SEC초 동안 화면을 만지지 않으면 화면을 어둡게 덮고 프레임을 SAVER_FPS로 낮춘다.
##   게임은 그대로 돈다. 아무 곳이나 누르면 돌아온다(그 누름은 게임에 전달하지 않는다).

const Prefs := preload("res://scripts/prefs.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const QUALITIES := ["high", "mid", "low"]
const QUALITY_NAMES := {"high": "높음", "mid": "보통", "low": "낮음"}
const RENDER_FACTOR := {"high": 1.0, "mid": 0.8, "low": 0.65}
const FPS_CHOICES := [60, 30]
const SAVER_SEC := 60.0
const SAVER_FPS := 10
const SAVER_TEXT := "절전 모드\n화면을 누르면 돌아갑니다"
const ORIG_SHADOW := "gfx_orig_shadow"  # 조명 메타: 원래 그림자 켬?

static var current = null

var saver_on := false  # 지금 절전 화면이 덮여 있다
var _idle := 0.0
var _cover: ColorRect


static func quality() -> String:
	var q := Prefs.get_str("gfx_quality", "high")
	return q if q in QUALITIES else "high"


static func fps() -> int:
	var f := int(Prefs.get_float("gfx_fps", 60.0))
	return f if f in FPS_CHOICES else 60


static func shadows() -> bool:
	return quality() != "low"


## 3D 해상도 배율(main.scale_3d_for에 곱한다).
static func render_factor() -> float:
	return RENDER_FACTOR[quality()]


static func saver_enabled() -> bool:
	return Prefs.get_bool("power_saver", false)


func _ready() -> void:
	current = self
	layer = 50  # 창·HUD 위
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cover = ColorRect.new()
	_cover.color = Color(0, 0, 0, 0.86)
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_cover.visible = false
	_cover.gui_input.connect(func(e: InputEvent):  # _input을 다른 노드가 먼저 먹어도 덮개가 받는다
		if saver_on and e.is_pressed():
			wake())
	var l := Label.new()
	l.text = SAVER_TEXT
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", 32)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	_cover.add_child(l)
	add_child(_cover)
	get_tree().node_added.connect(_on_node_added)
	apply()


func _exit_tree() -> void:
	if current == self:
		current = null


## 지금 설정을 모두 다시 적용한다(설정 창이 바꿀 때마다 부른다).
func apply() -> void:
	Engine.max_fps = SAVER_FPS if saver_on else fps()
	var on := shadows()
	for n in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		_shadow(n, on)
	var main := get_parent()
	if main != null and main.has_method("apply_render_scale"):
		main.apply_render_scale()
	if saver_on and not saver_enabled():
		wake()


func _on_node_added(n: Node) -> void:
	if n is DirectionalLight3D:
		_shadow.call_deferred(n, shadows())  # 만든 쪽이 shadow_enabled를 정한 뒤에


func _shadow(light: DirectionalLight3D, on: bool) -> void:
	if not is_instance_valid(light):
		return
	if not light.has_meta(ORIG_SHADOW):
		light.set_meta(ORIG_SHADOW, light.shadow_enabled)
	light.shadow_enabled = on and bool(light.get_meta(ORIG_SHADOW))


func _process(delta: float) -> void:
	if saver_on or not saver_enabled():
		_idle = 0.0
		return
	_idle += delta / maxf(Engine.time_scale, 0.01)  # 배속·히트스톱과 상관없이 실제 시간
	if _idle >= SAVER_SEC:
		sleep()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey or event is InputEventScreenDrag or event is InputEventMouseMotion:
		_idle = 0.0
		if saver_on and event.is_pressed():
			wake()
			get_viewport().set_input_as_handled()
		elif saver_on:
			get_viewport().set_input_as_handled()


## 절전 화면을 덮는다.
func sleep() -> void:
	saver_on = true
	_cover.visible = true
	Engine.max_fps = SAVER_FPS


## 절전 화면을 걷는다.
func wake() -> void:
	saver_on = false
	_idle = 0.0
	_cover.visible = false
	_cover.gui_input.connect(func(e: InputEvent):  # _input을 다른 노드가 먼저 먹어도 덮개가 받는다
		if saver_on and e.is_pressed():
			wake())
	Engine.max_fps = fps()

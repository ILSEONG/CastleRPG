extends Control
## 보상형 광고 재생(상점 [광고] 탭, 2026-10-12): play(done)으로 열고, 끝까지 보면 done.call()로 보상을 받게 한다. 중간에 [닫기]면 보상 없음.
## 광고 네트워크(Google Play = AdMob, 앱인토스 = 토스 광고)가 아직 연결되지 않아 지금은 SECONDS초짜리 시험 화면이다 —
## 연결하면 play()에서 그 SDK의 보상형 광고를 띄우고 보상 콜백에서 done.call()을 부르면 된다(서버는 body.ad = true를 받는다).
## 광고 제거(Economy.ad_free) 구매자는 이 창을 거치지 않는다(shop_panel._buy).

const UiKit := preload("res://scripts/ui_kit.gd")

const SECONDS := 5.0
static var instant := false  # 테스트: 곧바로 끝까지 본 것으로

var _done: Callable
var _left := 0.0
var title_label: Label
var time_label: Label
var bar: ProgressBar
var close_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	col.custom_minimum_size = Vector2(560, 0)
	col.position -= Vector2(280, 160)
	col.add_theme_constant_override("separation", 18)
	add_child(col)
	title_label = _label("광고", 40, Color.WHITE)
	col.add_child(title_label)
	col.add_child(_label("광고 연결 전 시험 화면입니다", 22, Color(1, 1, 1, 0.7)))
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 22)
	bar.show_percentage = false
	bar.max_value = SECONDS
	col.add_child(bar)
	time_label = _label("", 26, Color(1, 0.93, 0.6))
	col.add_child(time_label)
	close_button = Button.new()
	close_button.text = "닫기"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(200, 64)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.add_theme_font_size_override("font_size", 24)
	UiKit.apply_button(close_button, UiKit.STEEL, 12.0)
	close_button.pressed.connect(func(): visible = false)
	col.add_child(close_button)


## 광고를 띄운다. 끝까지 보면 done.call().
func play(done: Callable) -> void:
	if instant:
		done.call()
		return
	_done = done
	_left = SECONDS
	_tick()
	visible = true


func _process(delta: float) -> void:
	if not visible:
		return
	_left -= delta
	if _left <= 0.0:
		visible = false
		_done.call()
		return
	_tick()


func _tick() -> void:
	bar.value = SECONDS - _left
	time_label.text = "%d초 뒤 보상을 받습니다 · 닫으면 보상이 없습니다" % ceili(_left)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

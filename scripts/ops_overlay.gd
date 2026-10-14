extends CanvasLayer
## 점검·강제 업데이트 안내(2026-10-12, LiveOps가 만든다). 화면 전체를 덮어 뒤 화면 입력을 모두 막는다(로딩·로그인 화면 위에도).
## 점검: "서버 점검 중" + 관리자가 적은 안내 + 끝나는 예정 시각. 서버가 다시 답하면 LiveOps.on_ok가 걷는다(Net이 계속 다시 묻는다).
## 업데이트: "업데이트가 필요합니다" + [업데이트] — 스토어 주소(관리자가 정한 것, 없으면 Google Play 앱 페이지)를 연다. 웹(앱인토스)은 새로 고침.

const Lang := preload("res://scripts/lang.gd")

const UiKit := preload("res://scripts/ui_kit.gd")
const HudScript := preload("res://scripts/hud.gd")

const PLAY_URL := "https://play.google.com/store/apps/details?id=com.ilesong.castlerpg"
const SUB := Color(0.16, 0.18, 0.24, 0.7)

var panel: PanelContainer
var title_label: Label
var text_label: Label
var time_label: Label
var update_button: Button
var _store_at := -10.0  # 마지막으로 스토어를 연 때(실제 초) — 빠른 두 번 누름이 스토어·새로고침을 두 번 하지 않게


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var back := ColorRect.new()
	back.color = Color(0.05, 0.06, 0.09, 0.82)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(back)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(560, 0)
	panel.add_theme_stylebox_override("panel", UiKit.scroll())  # 두루마리 창
	back.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	title_label = _label("", 38)
	title_label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	title_label.add_theme_constant_override("outline_size", 6)
	box.add_child(title_label)
	text_label = _label("", 26)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size = Vector2(500, 0)
	box.add_child(text_label)
	time_label = _label("", 24, SUB)
	box.add_child(time_label)
	update_button = Button.new()
	update_button.text = Lang.t("ops_overlay.ready")
	update_button.custom_minimum_size = Vector2(0, 64)
	update_button.add_theme_font_size_override("font_size", 28)
	UiKit.apply_button(update_button, HudScript.ACCENT, 14.0)
	update_button.pressed.connect(open_store)
	box.add_child(update_button)
	LiveOps.block_changed.connect(_refresh)
	_refresh()


func _label(text: String, size: int, color: Color = HudScript.INK) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _refresh() -> void:
	var b: Dictionary = LiveOps.block
	visible = not b.is_empty()
	if not visible:
		return
	var update := str(b.get("kind", "")) == "update"
	title_label.text = Lang.t("ops_overlay.refresh") if update else Lang.t("ops_overlay.refresh_2")
	if update:
		text_label.text = Lang.t("ops_overlay.refresh_3")
		time_label.text = Lang.t("ops_overlay.refresh_4") % [LiveOps.app_version(), str(b.get("min_version", ""))]
	else:
		var t := str(b.get("text", ""))
		text_label.text = t if t != "" else Lang.t("ops_overlay.refresh_5")
		var until := float(b.get("until", 0.0))
		time_label.text = (Lang.t("ops_overlay.refresh_6") % clock_text(until) if until > 0.0 else "") + Lang.t("ops_overlay.refresh_7")
	update_button.visible = update
	panel.offset_left = 0
	panel.offset_right = 0
	panel.offset_top = 0
	panel.offset_bottom = 0


## 유닉스 초 → 이 기기 시간대의 "10월 12일 14:30".
static func clock_text(unix: float) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var d := Time.get_datetime_dict_from_unix_time(int(unix) + bias * 60)
	return Lang.t("ops_overlay.clock_text") % [d.month, d.day, d.hour, d.minute]


func open_store() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _store_at < 1.5:
		return
	_store_at = now
	if OS.has_feature("web"):
		var loc = JavaScriptBridge.get_interface("location")
		if loc != null:
			loc.reload()
		return
	var url := str(LiveOps.block.get("store_url", ""))
	OS.shell_open(url if url != "" else PLAY_URL)

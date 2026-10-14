extends "res://scripts/ui_window.gd"
## 쿠폰 입력 창(2026-10-12, 설정 창 [쿠폰 입력]). 번호를 넣고 [사용] → LiveOps.redeem(POST /v1/coupon). 결과(받은 보상 또는 거절 이유)를
## 창 안 한 줄로 보인다. 대소문자·띄어쓰기·하이픈은 서버가 무시한다. 화면 키보드가 올라오면 창을 그 위로 올린다.

const Lang := preload("res://scripts/lang.gd")

const OpsSheet := preload("res://scripts/ops_sheet.gd")
const OK_INK := Color(0.20, 0.52, 0.26)
const BAD_INK := Color(0.80, 0.22, 0.18)

var input: LineEdit
var result_label: Label
var use_button: Button


func _ready() -> void:
	_build_window(560, 14)
	content.add_child(_title(Lang.t("coupon_panel.ready")))
	var hint := _label(Lang.t("coupon_panel.ready_2"), 22, Color(0.16, 0.18, 0.24, 0.62))
	content.add_child(hint)
	input = OpsSheet.line_edit(Lang.t("coupon_panel.ready_3"), 24)
	input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	input.text_submitted.connect(func(_t): use())
	content.add_child(input)
	result_label = _label("", 22)
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.custom_minimum_size = Vector2(500, 0)
	content.add_child(result_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var close_button := _button(Lang.t("coupon_panel.ready_4"), UiKit.STEEL)
	close_button.custom_minimum_size.x = 160
	close_button.pressed.connect(close)
	row.add_child(close_button)
	use_button = _button(Lang.t("coupon_panel.ready_5"))
	use_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	use_button.pressed.connect(use)
	row.add_child(use_button)
	content.add_child(row)


func _on_open() -> void:
	input.text = ""
	result_label.text = ""
	_fit()


func close() -> void:
	DisplayServer.virtual_keyboard_hide()
	input.release_focus()
	super.close()


func use() -> void:
	if LiveOps.redeeming:
		return
	result_label.text = ""
	use_button.disabled = true
	LiveOps.redeem(input.text, _on_result)


func _on_result(ok: bool, text: String) -> void:
	use_button.disabled = false
	result_label.text = text
	result_label.add_theme_color_override("font_color", OK_INK if ok else BAD_INK)
	if ok:
		input.text = ""
		Economy.notice.emit(text)
	_fit()


func _process(_delta: float) -> void:
	if not visible:
		return
	var kb := float(DisplayServer.virtual_keyboard_get_height()) if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0.0
	if kb > 0.0:  # 키보드 높이(픽셀) → 화면 좌표, 창 아래가 키보드 위에 오게
		var scale := get_viewport().get_visible_rect().size.y / float(DisplayServer.window_get_size().y)
		var lift := maxf(0.0, dialog.size.y / 2.0 + kb * scale - get_viewport().get_visible_rect().size.y / 2.0 + 16.0)
		dialog.offset_top = -lift
		dialog.offset_bottom = -lift
	elif dialog.offset_top != 0.0:
		_fit()

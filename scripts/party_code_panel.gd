extends "res://scripts/ui_window.gd"
## 파티 코드 입력 창(사용자 2026-10-15 "파티코드 있어서 파티를 구성할수잇어"): [파티] 탭 [코드로 참가] → 코드를 넣고 [참가] → Party.join_lobby.
## 결과(거절 이유)는 창 안 한 줄. 참가하면 닫는다. 대소문자·띄어쓰기·하이픈은 무시. 화면 키보드가 올라오면 창을 그 위로 올린다.
## [참가]는 누르는 즉시 꺼지고(빠른 두 번 탭도 한 번만) 서버 답을 받으면 다시 켜진다.

const Lang := preload("res://scripts/lang.gd")

const OpsSheet := preload("res://scripts/ops_sheet.gd")
const BAD_INK := Color(0.80, 0.22, 0.18)

var input: LineEdit
var result_label: Label
var join_button: Button


func _ready() -> void:
	_build_window(560, 14)
	layer = 3  # 던전 시트(2) 위
	content.add_child(_title(Lang.t("party_code_panel.ready")))
	content.add_child(_label(Lang.t("party_code_panel.ready_2"), 22, Color(0.16, 0.18, 0.24, 0.62)))
	input = OpsSheet.line_edit(Lang.t("party_code_panel.ready_3"), 8)
	input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	input.text_submitted.connect(func(_t): join())
	content.add_child(input)
	result_label = _label("", 22, BAD_INK)
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.custom_minimum_size = Vector2(500, 0)
	content.add_child(result_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var close_button := _button(Lang.t("party_code_panel.ready_4"), UiKit.STEEL)
	close_button.custom_minimum_size.x = 160
	close_button.pressed.connect(close)
	row.add_child(close_button)
	join_button = _button(Lang.t("party_code_panel.ready_5"))
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_button.pressed.connect(join)
	row.add_child(join_button)
	content.add_child(row)


func _on_open() -> void:
	input.text = ""
	result_label.text = ""
	join_button.disabled = false
	_fit()


func close() -> void:
	DisplayServer.virtual_keyboard_hide()
	input.release_focus()
	super.close()


func join() -> void:
	if join_button.disabled:
		return
	result_label.text = ""
	join_button.disabled = true
	Party.join_lobby(input.text, _on_result)


func _on_result(ok: bool, text: String) -> void:
	join_button.disabled = false
	if ok:
		close()
		return
	result_label.text = text
	_fit()


func _process(_delta: float) -> void:
	if not visible:
		return
	var kb := float(DisplayServer.virtual_keyboard_get_height()) if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0.0
	if kb > 0.0:
		var scale := get_viewport().get_visible_rect().size.y / float(DisplayServer.window_get_size().y)
		var lift := maxf(0.0, dialog.size.y / 2.0 + kb * scale - get_viewport().get_visible_rect().size.y / 2.0 + 16.0)
		dialog.offset_top = -lift
		dialog.offset_bottom = -lift
	elif dialog.offset_top != 0.0:
		_fit()

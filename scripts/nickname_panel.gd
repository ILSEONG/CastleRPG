extends "res://scripts/ui_window.gd"
## 닉네임 변경 창(2026-11-05, 설정 창 닉네임 줄 [변경]). 첫 변경은 무료, 그 뒤는 다이아(서버 game_config nickname_change_dia, 기본 3,000).
## 규칙(서버 names.ts와 같다): 2~8자, 한글·영문·숫자만. 금칙어·운영자 사칭·이미 쓰는 이름은 서버가 거절한다(→ 되돌리고 알림).
## [변경]은 기다리지 않는다: 길이·글자를 여기서 바로 보고, 괜찮으면 Economy.change_nickname이 바로 바꿔 보이고 창을 닫는다.

const Lang := preload("res://scripts/lang.gd")

const OpsSheet := preload("res://scripts/ops_sheet.gd")
const MIN_LEN := 2
const MAX_LEN := 8
const NAME_RE := "^[\uac00-\ud7a3A-Za-z0-9]+$"  # 한글 음절·영문·숫자(서버 names.ts NAME_RE)
const BAD_INK := Color(0.80, 0.22, 0.18)
const SUB := Color(0.16, 0.18, 0.24, 0.62)

var current_label: Label
var price_label: Label
var input: LineEdit
var error_label: Label
var change_button: Button


func _ready() -> void:
	_build_window(560, 14)
	content.add_child(_title(Lang.t("nickname_panel.ready")))
	current_label = _label("", 24)
	content.add_child(current_label)
	input = OpsSheet.line_edit(Lang.t("nickname_panel.ready_2"), MAX_LEN)
	input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	input.text_submitted.connect(func(_t): submit())
	input.text_changed.connect(func(_t): error_label.text = "")
	content.add_child(input)
	content.add_child(_label(Lang.t("nickname_panel.ready_3"), 20, SUB))
	price_label = _label("", 22)
	content.add_child(price_label)
	error_label = _label("", 22, BAD_INK)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.custom_minimum_size = Vector2(500, 0)
	content.add_child(error_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var cancel := _button(Lang.t("nickname_panel.ready_4"), UiKit.STEEL)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(close)
	row.add_child(cancel)
	change_button = _button(Lang.t("nickname_panel.ready_5"))
	change_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	change_button.pressed.connect(submit)
	row.add_child(change_button)
	content.add_child(row)


func _on_open() -> void:
	input.text = ""
	error_label.text = ""
	current_label.text = Lang.t("nickname_panel.on_open") % str(Economy.nickname.get("name", "-"))
	var price := int(Economy.nickname.get("price", 0))
	price_label.text = Lang.t("nickname_panel.on_open_2") if price <= 0 else Lang.t("nickname_panel.on_open_3") % [UiKit.commas(price), UiKit.commas(Economy.diamonds)]
	price_label.add_theme_color_override("font_color", BAD_INK if price > Economy.diamonds else HudScript.INK)
	_fit()


## 길이·글자 검사(서버 names.ts check와 같은 규칙). 괜찮으면 "".
static func check(name: String) -> String:
	if name.length() < MIN_LEN or name.length() > MAX_LEN:
		return Lang.t("nickname_panel.check")
	var re := RegEx.create_from_string(NAME_RE)
	if re.search(name) == null:
		return Lang.t("nickname_panel.check_3")
	return ""


func submit() -> void:
	var name := input.text.strip_edges()
	var why := check(name)
	if why == "" and name.to_lower() == str(Economy.nickname.get("name", "")).to_lower():
		why = Lang.t("nickname_panel.submit")
	if why != "":
		error_label.text = why
		_fit()
		return
	if Economy.change_nickname(name):
		close()
		Economy.notice.emit(Lang.t("nickname_panel.submit_2") % name)


func close() -> void:
	DisplayServer.virtual_keyboard_hide()
	input.release_focus()
	super.close()


func _process(_delta: float) -> void:
	if not visible:
		return
	var kb := float(DisplayServer.virtual_keyboard_get_height()) if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0.0
	if kb > 0.0:  # 키보드 위로 창을 올린다(coupon_panel.gd와 같다)
		var scale := get_viewport().get_visible_rect().size.y / float(DisplayServer.window_get_size().y)
		var lift := maxf(0.0, dialog.size.y / 2.0 + kb * scale - get_viewport().get_visible_rect().size.y / 2.0 + 16.0)
		dialog.offset_top = -lift
		dialog.offset_bottom = -lift
	elif dialog.offset_top != 0.0:
		_fit()

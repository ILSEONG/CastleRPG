extends "res://scripts/ui_window.gd"
## 설정 창(2026-10-06, 오른쪽 아래 메뉴 [설정] — 예전 [음악] 켬/끔 버튼 자리). 바꾸면 바로 적용되고 기기에 저장된다(서버 요청 없음).
## 사운드: 배경음악 켬/끔 + 크기 슬라이더(Music.enabled·volume), 효과음 켬/끔 + 크기 슬라이더(SoundFx.enabled·volume, 2026-10-07).
## 화면: 화면 흔들림(Prefs shake — 카메라 흔들림·히트스톱·SSR 줌), 피해 숫자 표시(Prefs damage_numbers).
## 계정: 닉네임·친구 코드([복사])·로그인 방식(온라인, 친구 목록 응답 Economy.friends에서). 오프라인이면 "오프라인 모드".
## 계정 삭제(온라인, Google Play 계정 삭제 정책): 두 번 눌러 확인 → POST /v1/account/delete → 저장한 로그인·기기 id를 지우고 처음부터(Net.forget_account).
## 정보: 게임 버전(프로젝트 설정 application/config/version).

const Prefs := preload("res://scripts/prefs.gd")

const TITLE := "설정"
const WIDTH := 600.0
const SUB := Color(0.16, 0.18, 0.24, 0.62)
const LOGIN_NAMES := {"guest": "게스트", "google": "Google", "kakao": "카카오", "naver": "네이버", "toss": "토스"}
const DELETE_ARM_SEC := 4.0  # [계정 삭제]를 한 번 누른 뒤 확인을 기다리는 시간

var music_check: Button
var volume_slider: HSlider
var volume_label: Label
var sfx_check: Button
var sfx_slider: HSlider
var sfx_label: Label
var shake_check: Button
var numbers_check: Button
var name_label: Label
var code_label: Label
var login_label: Label
var copy_button: Button
var version_label: Label
var delete_button: Button
var _delete_armed := 0.0
var _deleting := false


func _ready() -> void:
	_build_window(WIDTH, 10)
	content.add_child(_title(TITLE))

	content.add_child(_section("사운드"))
	music_check = _toggle_row("배경음악", func(on: bool): Music.set_enabled(on))
	volume_slider = _slider_row("배경음악 음량")
	volume_label = volume_slider.get_parent().get_child(2)
	volume_slider.value_changed.connect(func(v: float):
		Music.set_volume(v / 100.0, false)  # 끄는 동안 바로 들린다
		volume_label.text = "%d%%" % int(v))
	volume_slider.drag_ended.connect(func(_changed): Music.save_settings())
	sfx_check = _toggle_row("효과음", func(on: bool): SoundFx.set_enabled(on))
	sfx_slider = _slider_row("효과음 음량")
	sfx_label = sfx_slider.get_parent().get_child(2)
	sfx_slider.value_changed.connect(func(v: float):
		SoundFx.set_volume(v / 100.0, false)
		sfx_label.text = "%d%%" % int(v))
	sfx_slider.drag_ended.connect(func(_changed):
		SoundFx.set_volume(sfx_slider.value / 100.0)
		SoundFx.emit_sound("click"))  # 손을 떼면 저장하고 크기를 들려 준다

	content.add_child(_section("화면"))
	shake_check = _toggle_row("화면 흔들림", func(on: bool): Prefs.set_value("shake", on))
	numbers_check = _toggle_row("피해 숫자 표시", func(on: bool): Prefs.set_value("damage_numbers", on))

	content.add_child(_section("계정"))
	name_label = _info_row("닉네임")
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 12)
	code_row.add_child(_row_label("친구 코드"))
	code_label = _label("", 26, HudScript.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(code_label)
	copy_button = _button("복사", UiKit.STEEL, 22)
	copy_button.custom_minimum_size = Vector2(88, 48)
	copy_button.pressed.connect(copy_code)
	code_row.add_child(copy_button)
	content.add_child(code_row)
	login_label = _info_row("로그인")
	delete_button = _button("계정 삭제", UiKit.STEEL, 22)
	delete_button.custom_minimum_size = Vector2(0, 56)
	delete_button.pressed.connect(press_delete)
	content.add_child(delete_button)

	content.add_child(_section("정보"))
	version_label = _info_row("게임 버전")

	var close_button := _button("닫기", UiKit.STEEL)
	close_button.pressed.connect(close)
	content.add_child(close_button)
	Economy.friends_changed.connect(_refresh)
	_refresh()


func _on_open() -> void:
	if Net.is_online() and str(Economy.friends.get("code", "")) == "":
		Economy.friends_load()  # 로딩 때 못 받았으면 지금(받는 동안은 "…")
	_refresh()


## 지금 값으로 다시 보인다(토글 신호는 막고).
func _refresh() -> void:
	for c in [music_check, shake_check, numbers_check, volume_slider, sfx_check, sfx_slider]:
		c.set_block_signals(true)
	music_check.button_pressed = Music.enabled
	sfx_check.button_pressed = SoundFx.enabled
	sfx_slider.value = roundf(SoundFx.volume * 100.0)
	shake_check.button_pressed = Prefs.get_bool("shake")
	numbers_check.button_pressed = Prefs.get_bool("damage_numbers")
	volume_slider.value = roundf(Music.volume * 100.0)
	for c in [music_check, shake_check, numbers_check, volume_slider, sfx_check, sfx_slider]:
		c.set_block_signals(false)
		if c is Button:
			for k in c.get_children():
				if k is Control:
					k.queue_redraw()
	volume_label.text = "%d%%" % int(volume_slider.value)
	sfx_label.text = "%d%%" % int(sfx_slider.value)
	var online := Net.is_online()
	var code := str(Economy.friends.get("code", ""))
	name_label.text = str(Economy.friends.get("name", "…")) if online else "오프라인 모드"
	code_label.text = code if code != "" else ("…" if online else "-")
	copy_button.visible = code != ""
	login_label.text = LOGIN_NAMES.get(Net.auth_mode, "-") if online else "-"
	version_label.text = str(ProjectSettings.get_setting("application/config/version", ""))
	delete_button.visible = online
	_style_delete()


func _process(delta: float) -> void:
	if _delete_armed > 0.0:
		_delete_armed -= delta
		if _delete_armed <= 0.0:
			_style_delete()


## [계정 삭제]: 첫 번째는 확인을 묻고(빨간 "한 번 더 누르면 계정이 삭제됩니다"), 4초 안에 다시 누르면 서버에서 지운다. 되돌릴 수 없다.
func press_delete() -> void:
	if _deleting or not Net.is_online():
		return
	if _delete_armed <= 0.0:
		_delete_armed = DELETE_ARM_SEC
		_style_delete()
		return
	_delete_armed = 0.0
	_deleting = true
	Net.send("POST", "/v1/account/delete", {"confirm": "delete"}, func(_d): Net.forget_account(),
		func():
			_deleting = false
			_style_delete()
			Economy.notice.emit("계정을 삭제하지 못했습니다. 다시 시도해 주세요"))


func _style_delete() -> void:
	var armed := _delete_armed > 0.0
	delete_button.text = "한 번 더 누르면 계정이 삭제됩니다" if armed else "계정 삭제"
	UiKit.apply_button(delete_button, Color(0.85, 0.27, 0.22) if armed else UiKit.STEEL, 12.0)


func copy_code() -> void:
	var code := str(Economy.friends.get("code", ""))
	if code != "":
		DisplayServer.clipboard_set(code)
		Economy.notice.emit("친구 코드를 복사했습니다")


## [이름 | 슬라이더 0..100 | "n%"] 한 줄. 반환 = 슬라이더(줄의 1번 자식, 글자 = 2번 자식).
func _slider_row(text: String) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_row_label(text))
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 1
	s.custom_minimum_size = Vector2(0, 48)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)
	var l := _label("", 24, HudScript.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	l.custom_minimum_size = Vector2(76, 0)
	row.add_child(l)
	content.add_child(row)
	return s


func _section(text: String) -> Label:
	var l := _label(text, 26, SUB, HORIZONTAL_ALIGNMENT_LEFT)
	l.custom_minimum_size = Vector2(0, 40)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return l


func _row_label(text: String) -> Label:
	var l := _label(text, 26, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	l.custom_minimum_size = Vector2(170, 52)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## 이름 + 오른쪽 체크박스(켬/끔). 누르면 on_change(켬?)를 바로 부른다.
func _toggle_row(text: String, on_change: Callable) -> Button:
	var row := HBoxContainer.new()
	var l := _row_label(text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var b := UiKit.checkbox("켬")
	b.custom_minimum_size = Vector2(110, 64)
	b.toggled.connect(on_change)
	row.add_child(b)
	content.add_child(row)
	return b


## 이름 + 오른쪽 값 글자. 값 Label을 돌려준다.
func _info_row(text: String) -> Label:
	var row := HBoxContainer.new()
	row.add_child(_row_label(text))
	var v := _label("", 26, HudScript.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(v)
	content.add_child(row)
	return v

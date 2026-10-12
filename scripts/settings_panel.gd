extends "res://scripts/ui_window.gd"
## 설정 창(2026-10-06, 오른쪽 아래 메뉴 [설정] — 예전 [음악] 켬/끔 버튼 자리). 바꾸면 바로 적용되고 기기에 저장된다(서버 요청 없음).
## 사운드: 배경음악 켬/끔 + 크기 슬라이더(Music.enabled·volume), 효과음 켬/끔 + 크기 슬라이더(SoundFx.enabled·volume, 2026-10-07).
## 화면: 화면 흔들림(Prefs shake — 카메라 흔들림·히트스톱·SSR 줌), 피해 숫자 표시(Prefs damage_numbers).
## 알림(안드로이드만, 2026-10-12): 푸시 알림 전체·종류별·야간 켬/끔 — notify_settings.gd, 예약은 Notify(notify.gd).
## 계정: 닉네임·친구 코드([복사])·로그인 방식(온라인, 친구 목록 응답 Economy.friends에서). 오프라인이면 "오프라인 모드".
## 계정 삭제(온라인, Google Play 계정 삭제 정책): 두 번 눌러 확인 → POST /v1/account/delete → 저장한 로그인·기기 id를 지우고 처음부터(Net.forget_account).
## 화면(2026-10-12): 그래픽 품질 높음/보통/낮음·프레임 60/30·절전 모드(graphics.gd — 바로 적용).
## 계정(2026-10-12): [로그아웃·계정 전환](앱인토스 빌드 제외, 두 번 눌러 확인) → 서버 세션을 지우고 다시 열면 로그인 화면(Net.logout + Net.restart).
## 계정 연결(2026-10-12, Google Play 빌드·온라인): [Google]·[카카오]·[네이버] — 지금 계정(게스트 포함)에 그 로그인을 붙인다(account_link.gd).
##   연결된 것은 "✓", 결과·안내는 그 아래 한 줄.
## 정보·지원: 게임 버전, [이용약관]·[개인정보처리방침](브라우저로 연다), [문의하기](메일 앱 — 받는 주소·플레이어 정보가 채워진다).
##   주소는 support_links.gd 상수(출시 작업이 채운다). 비어 있으면 "준비 중" 알림.
## 줄이 많아 가운데는 세로 스크롤(body), 제목과 [닫기]는 고정.
## 정보: 게임 버전(프로젝트 설정 application/config/version).
## 로그인 줄 [쿠폰 입력](온라인) → 쿠폰 창(coupon_panel.gd), 버전 줄 [운영 관리](슈퍼관리자만) → 관리자 창(admin_panel.gd: 공지·점검·업데이트·우편·쿠폰).

const Prefs := preload("res://scripts/prefs.gd")
const GraphicsScript := preload("res://scripts/graphics.gd")
const Links := preload("res://scripts/support_links.gd")
const ReleasePlatform := preload("res://scripts/release_platform.gd")
const NotifySettings := preload("res://scripts/notify_settings.gd")
const AccountLinkScript := preload("res://scripts/account_link.gd")

const TITLE := "설정"
const WIDTH := 600.0
const SUB := Color(0.16, 0.18, 0.24, 0.62)
const LOGIN_NAMES := {"guest": "게스트", "google": "Google", "kakao": "카카오", "naver": "네이버", "toss": "토스"}
const SCROLL_H := 820.0  # 가운데 스크롤 높이(제목·[닫기] 제외)
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
var coupon_button: Button
var admin_button: Button
var coupon  # 쿠폰 입력 창(coupon_panel.gd) — main이 넣는다
var admin_panel  # 운영 관리 창(admin_panel.gd, 슈퍼관리자만) — main이 넣는다
var _delete_armed := 0.0
var _deleting := false
var body: VBoxContainer  # 스크롤 안 줄들
var quality_buttons := {}  # 품질 id → Button
var fps_buttons := {}  # 프레임 → Button
var saver_check: Button
var logout_button: Button
var _logout_armed := 0.0
var terms_button: Button
var privacy_button: Button
var inquiry_button: Button
var notify_rows: RefCounted  # [알림] 칸(notify_settings.gd), 알림을 못 띄우는 빌드면 null
var account_link: Node  # account_link.gd
var link_row: HBoxContainer
var link_buttons := {}  # provider → Button
var link_label: Label


func _ready() -> void:
	_build_window(WIDTH, 10)
	content.add_child(_title(TITLE))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, SCROLL_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var pad := MarginContainer.new()  # 오른쪽 스크롤 막대와 글자가 겹치지 않게
	pad.add_theme_constant_override("margin_right", 18)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pad)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(body)

	body.add_child(_section("사운드"))
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

	body.add_child(_section("화면"))
	quality_buttons = _choice_row("그래픽 품질", GraphicsScript.QUALITIES.map(func(q): return [q, GraphicsScript.QUALITY_NAMES[q]]),
		func(q): _set_gfx("gfx_quality", q))
	fps_buttons = _choice_row("프레임", GraphicsScript.FPS_CHOICES.map(func(f): return [f, "%d" % f]), func(f): _set_gfx("gfx_fps", f))
	saver_check = _toggle_row("절전 모드", func(on: bool): _set_gfx("power_saver", on))
	var saver_hint := _label("1분간 조작이 없으면 화면을 어둡게 하고 프레임을 낮춥니다", 20, SUB, HORIZONTAL_ALIGNMENT_LEFT)
	saver_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(saver_hint)
	shake_check = _toggle_row("화면 흔들림", func(on: bool): Prefs.set_value("shake", on))
	numbers_check = _toggle_row("피해 숫자 표시", func(on: bool): Prefs.set_value("damage_numbers", on))
	notify_rows = NotifySettings.add_to(self)  # 푸시 알림 켬/끔(안드로이드만)

	body.add_child(_section("계정"))
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
	body.add_child(code_row)
	login_label = _info_row("로그인")
	account_link = AccountLinkScript.new()
	add_child(account_link)
	account_link.changed.connect(_refresh)
	link_row = HBoxContainer.new()
	link_row.add_theme_constant_override("separation", 8)
	link_row.add_child(_row_label("계정 연결"))
	for provider in AccountLinkScript.PROVIDERS:
		var b := _button(AccountLinkScript.NAMES[provider], UiKit.STEEL, 22)
		b.custom_minimum_size = Vector2(0, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): account_link.start(provider))
		link_buttons[provider] = b
		link_row.add_child(b)
	body.add_child(link_row)
	link_label = _label("", 20, SUB, HORIZONTAL_ALIGNMENT_LEFT)
	link_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(link_label)
	logout_button = _button("로그아웃 · 계정 전환", UiKit.STEEL, 22)
	logout_button.custom_minimum_size = Vector2(0, 56)
	logout_button.pressed.connect(press_logout)
	body.add_child(logout_button)
	coupon_button = _button("쿠폰 입력", UiKit.STEEL, 22)  # 쿠폰(2026-10-12, LiveOps): 로그인 줄 오른쪽(창 높이를 늘리지 않게)
	coupon_button.custom_minimum_size = Vector2(150, 48)
	coupon_button.pressed.connect(func():
		if coupon != null:
			close()
			coupon.open())
	login_label.get_parent().add_child(coupon_button)
	delete_button = _button("계정 삭제", UiKit.STEEL, 22)
	delete_button.custom_minimum_size = Vector2(0, 56)
	delete_button.pressed.connect(press_delete)
	body.add_child(delete_button)

	body.add_child(_section("정보 · 지원"))
	version_label = _info_row("게임 버전")
	var docs := HBoxContainer.new()
	docs.add_theme_constant_override("separation", 10)
	terms_button = _button("이용약관", UiKit.STEEL, 22)
	privacy_button = _button("개인정보처리방침", UiKit.STEEL, 22)
	for b in [terms_button, privacy_button]:
		b.custom_minimum_size = Vector2(0, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		docs.add_child(b)
	terms_button.pressed.connect(func(): open_link(Links.TERMS_URL))
	privacy_button.pressed.connect(func(): open_link(Links.PRIVACY_URL))
	body.add_child(docs)
	inquiry_button = _button("문의하기", UiKit.STEEL, 22)
	inquiry_button.custom_minimum_size = Vector2(0, 56)
	inquiry_button.pressed.connect(open_inquiry)
	body.add_child(inquiry_button)
	admin_button = _button("운영 관리", UiKit.AMBER, 22)  # 공지·점검·우편·쿠폰 만들기(슈퍼관리자만 보인다) — 버전 줄 오른쪽
	admin_button.custom_minimum_size = Vector2(150, 48)
	admin_button.pressed.connect(func():
		if admin_panel != null:
			close()
			admin_panel.open())
	version_label.get_parent().add_child(admin_button)

	var close_button := _button("닫기", UiKit.STEEL)
	close_button.pressed.connect(close)
	content.add_child(close_button)
	Economy.friends_changed.connect(_refresh)
	_refresh()


func _on_open() -> void:
	if Net.is_online() and str(Economy.friends.get("code", "")) == "":
		Economy.friends_load()  # 로딩 때 못 받았으면 지금(받는 동안은 "…")
	if Net.is_online() and not ReleasePlatform.is_toss():
		account_link.load_links()
	_refresh()
	if notify_rows != null:
		notify_rows.refresh()


## 지금 값으로 다시 보인다(토글 신호는 막고).
func _refresh() -> void:
	for c in [music_check, shake_check, numbers_check, volume_slider, sfx_check, sfx_slider, saver_check]:
		c.set_block_signals(true)
	music_check.button_pressed = Music.enabled
	sfx_check.button_pressed = SoundFx.enabled
	sfx_slider.value = roundf(SoundFx.volume * 100.0)
	shake_check.button_pressed = Prefs.get_bool("shake")
	numbers_check.button_pressed = Prefs.get_bool("damage_numbers")
	saver_check.button_pressed = GraphicsScript.saver_enabled()
	volume_slider.value = roundf(Music.volume * 100.0)
	for c in [music_check, shake_check, numbers_check, volume_slider, sfx_check, sfx_slider, saver_check]:
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
	logout_button.visible = online and not ReleasePlatform.is_toss()  # 앱인토스는 로그인 화면이 없다(토스 계정으로 바로 시작)
	coupon_button.visible = online
	admin_button.visible = online and Economy.admin
	_style_delete()
	_style_logout()
	_style_links(online)
	_style_choices(quality_buttons, GraphicsScript.quality())
	_style_choices(fps_buttons, GraphicsScript.fps())


func _process(delta: float) -> void:
	if _delete_armed > 0.0:
		_delete_armed -= delta
		if _delete_armed <= 0.0:
			_style_delete()
	if _logout_armed > 0.0:
		_logout_armed -= delta
		if _logout_armed <= 0.0:
			_style_logout()


## 그래픽 설정 하나를 저장하고 바로 적용한다.
func _set_gfx(key: String, value) -> void:
	Prefs.set_value(key, value)
	if GraphicsScript.current != null:
		GraphicsScript.current.apply()
	_style_choices(quality_buttons, GraphicsScript.quality())
	_style_choices(fps_buttons, GraphicsScript.fps())


## [로그아웃 · 계정 전환]: 첫 번째는 확인을 묻고, DELETE_ARM_SEC초 안에 다시 누르면 로그아웃 뒤 다시 연다(다음 실행은 로그인 화면).
## 서버 세션 지우기는 응답을 기다리지 않는다(Net.logout). 진행은 계정에 그대로 남는다.
func press_logout() -> void:
	if not Net.is_online() or ReleasePlatform.is_toss():
		return
	if _logout_armed <= 0.0:
		_logout_armed = DELETE_ARM_SEC
		_style_logout()
		return
	_logout_armed = 0.0
	Net.logout()
	Economy.notice.emit("로그아웃했습니다. 게임을 다시 열면 로그인 화면이 나옵니다")
	await get_tree().create_timer(1.5).timeout
	Net.restart.call()


func _style_logout() -> void:
	var armed := _logout_armed > 0.0
	logout_button.text = "한 번 더 누르면 로그아웃합니다" if armed else "로그아웃 · 계정 전환"
	UiKit.apply_button(logout_button, UiKit.AMBER if armed else UiKit.STEEL, 12.0)


## 계정 연결 줄: 연결된 로그인은 "✓"(누를 수 없음). 게스트면 연결을 권하는 안내.
func _style_links(online: bool) -> void:
	var show := online and not ReleasePlatform.is_toss()
	link_row.visible = show
	link_label.visible = show
	for provider in link_buttons:
		var b: Button = link_buttons[provider]
		var linked: bool = account_link.is_linked(provider)
		b.text = AccountLinkScript.NAMES[provider] + (" ✓" if linked else "")
		b.disabled = linked
		UiKit.apply_button(b, UiKit.AMBER if account_link.pending == provider else UiKit.STEEL, 12.0)
	if account_link.message != "":
		link_label.text = account_link.message
	elif Net.auth_mode == "guest":
		link_label.text = "게스트 계정은 기기를 바꾸거나 앱을 지우면 찾을 수 없습니다. 연결해 두면 진행이 그대로 남습니다"
	else:
		link_label.text = "다른 로그인도 연결해 두면 어느 쪽으로든 들어올 수 있습니다"


## 웹 주소를 브라우저로 연다. 비어 있으면 준비 중 알림.
func open_link(url: String) -> void:
	if url == "":
		Economy.notice.emit(Links.NOT_READY)
		return
	OS.shell_open(url)


## [문의하기]: 메일 앱을 받는 주소 + 제목 + 플레이어 정보(닉네임·친구 코드·로그인·버전·기기)를 채워 연다. 주소가 비어 있으면 준비 중 알림.
func open_inquiry() -> void:
	if Links.SUPPORT_EMAIL == "":
		Economy.notice.emit(Links.NOT_READY)
		return
	OS.shell_open(inquiry_url())


func inquiry_url() -> String:
	var info := "\n\n----\n닉네임: %s\n친구 코드: %s\n로그인: %s\n버전: %s (%s)\n기기: %s %s" % [
		str(Economy.friends.get("name", "-")), str(Economy.friends.get("code", "-")), LOGIN_NAMES.get(Net.auth_mode, "-"),
		str(ProjectSettings.get_setting("application/config/version", "")), ReleasePlatform.current(), OS.get_name(), OS.get_model_name()]
	return "mailto:%s?subject=%s&body=%s" % [Links.SUPPORT_EMAIL, "[CastleRPG] 문의".uri_encode(), ("문의 내용을 적어 주세요." + info).uri_encode()]


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
	body.add_child(row)
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
	body.add_child(row)
	return b


## 이름 + 오른쪽 값 글자. 값 Label을 돌려준다.
func _info_row(text: String) -> Label:
	var row := HBoxContainer.new()
	row.add_child(_row_label(text))
	var v := _label("", 26, HudScript.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(v)
	body.add_child(row)
	return v


## [이름 | 선택지 버튼들] 한 줄. 고른 버튼은 금색. on_pick(id)를 바로 부른다. 반환 = id → Button.
func _choice_row(text: String, options: Array, on_pick: Callable) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := _row_label(text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var out := {}
	for o in options:
		var b := _button(o[1], UiKit.STEEL, 22)
		b.custom_minimum_size = Vector2(96, 52)
		b.focus_mode = Control.FOCUS_NONE
		var id = o[0]
		b.pressed.connect(func(): on_pick.call(id))
		row.add_child(b)
		out[id] = b
	body.add_child(row)
	return out


func _style_choices(buttons: Dictionary, picked) -> void:
	for id in buttons:
		UiKit.apply_button(buttons[id], UiKit.AMBER if id == picked else UiKit.STEEL, 12.0)

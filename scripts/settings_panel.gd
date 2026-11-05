extends "res://scripts/ui_window.gd"
## 설정 창(2026-10-06, 오른쪽 아래 메뉴 [설정] — 예전 [음악] 켬/끔 버튼 자리). 바꾸면 바로 적용되고 기기에 저장된다(서버 요청 없음).
## 사운드: 배경음악 켬/끔 + 크기 슬라이더(Music.enabled·volume), 효과음 켬/끔 + 크기 슬라이더(SoundFx.enabled·volume, 2026-10-07).
## 화면: 화면 흔들림(Prefs shake — 카메라 흔들림·히트스톱·SSR 줌), 피해 숫자 표시(Prefs damage_numbers),
## 스킬 이름 띠 표시(Prefs skill_banner)·크기(Prefs skill_banner_size: s/m/l/xl).
## 알림(안드로이드만, 2026-10-12): 푸시 알림 전체·종류별·야간 켬/끔 — notify_settings.gd, 예약은 Notify(notify.gd).
## 계정: 닉네임·친구 코드([복사])·로그인 방식(온라인, 친구 목록 응답 Economy.friends에서). 오프라인이면 "오프라인 모드".
## 계정 삭제(온라인, Google Play 계정 삭제 정책): 두 번 눌러 확인 → POST /v1/account/delete → 저장한 로그인·기기 id를 지우고 처음부터(Net.forget_account).
## 화면(2026-10-12): 그래픽 품질 높음/보통/낮음·프레임 60/30·절전 모드(graphics.gd — 바로 적용).
## 계정(2026-10-12): [로그아웃·계정 전환](앱인토스 빌드 제외, 두 번 눌러 확인) → 서버 세션을 지우고 다시 열면 로그인 화면(Net.logout + Net.restart).
## 계정 연결(2026-10-12, Google Play 빌드·온라인): [Google]·[카카오]·[네이버] — 지금 계정(게스트 포함)에 그 로그인을 붙인다(account_link.gd).
##   연결된 것은 "✓", 결과·안내는 그 아래 한 줄.
## 정보·지원: 게임 버전, [이용약관]·[개인정보처리방침](브라우저로 연다), [문의하기](게임 안 문의 창 — 플레이어 정보가 저절로 붙는다).
##   주소는 support_links.gd 상수(출시 작업이 채운다). 비어 있으면 "준비 중" 알림.
## 줄이 많아 가운데는 세로 스크롤(body), 제목과 [닫기]는 고정.
## 정보: 게임 버전(프로젝트 설정 application/config/version).
## 닉네임 줄 [변경](온라인, 2026-11-05) → 닉네임 변경 창(nickname_panel.gd). 줄은 이름 칸 + 같은 너비 세 칸 격자(_grid_row).
## [쿠폰 입력](온라인) → 쿠폰 창(coupon_panel.gd), 버전 줄 [운영 관리](슈퍼관리자만) → 관리자 창(admin_panel.gd: 공지·점검·업데이트·우편·쿠폰).

const Lang := preload("res://scripts/lang.gd")

const Prefs := preload("res://scripts/prefs.gd")
const GraphicsScript := preload("res://scripts/graphics.gd")
const Links := preload("res://scripts/support_links.gd")
const ReleasePlatform := preload("res://scripts/release_platform.gd")
const NotifySettings := preload("res://scripts/notify_settings.gd")
const AccountLinkScript := preload("res://scripts/account_link.gd")
const DamageNumbersScript := preload("res://scripts/damage_numbers.gd")

static var TITLE := Lang.t("settings_panel.title")
const WIDTH := 600.0
const SUB := Color(0.16, 0.18, 0.24, 0.62)
static var LOGIN_NAMES := {"guest": Lang.t("settings_panel.login_names.guest"), "google": "Google", "kakao": Lang.t("settings_panel.login_names.kakao"), "naver": Lang.t("settings_panel.login_names.naver"), "toss": Lang.t("settings_panel.login_names.toss")}
const SCROLL_H := 820.0  # 가운데 스크롤 높이(제목·[닫기] 제외)
const DELETE_ARM_SEC := 4.0  # [계정 삭제]를 한 번 누른 뒤 확인을 기다리는 시간
const LABEL_W := 180.0  # 줄 이름 칸 너비(그 오른쪽은 같은 너비 세 칸)
const SLOT_GAP := 8.0  # 칸 사이
const CONFIRM_GAP_SEC := 0.4  # 확인 누름은 첫 누름 뒤 이만큼 지나야 받는다 — 빠른 두 번 누름(실수)이 곧바로 삭제·로그아웃하지 않게

var music_check: Button
var volume_slider: HSlider
var volume_label: Label
var sfx_check: Button
var sfx_slider: HSlider
var sfx_label: Label
var shake_check: Button
var numbers_check: Button
var banner_check: Button  # 스킬 이름 띠(머리 위) 켬/끔
var banner_size_buttons := {}  # 띠 크기 id → Button
var name_label: Label
var code_label: Label
var login_label: Label
var copy_button: Button
var version_label: Label
var delete_button: Button
var coupon_button: Button
var admin_button: Button
var coupon  # 쿠폰 입력 창(coupon_panel.gd) — main이 넣는다
var inquiry  # 문의 창(inquiry_panel.gd) — main이 넣는다
var nickname_panel  # 닉네임 변경 창(nickname_panel.gd) — main이 넣는다
var rename_button: Button
var _slider_value: Label
var admin_panel  # 운영 관리 창(admin_panel.gd, 슈퍼관리자만) — main이 넣는다
var _delete_armed := 0.0
var _deleting := false
var body: VBoxContainer  # 스크롤 안 줄들
var quality_buttons := {}  # 품질 id → Button
var fps_buttons := {}  # 프레임 → Button
var saver_check: Button
var logout_button: Button
var _logout_armed := 0.0
var _logging_out := false
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

	body.add_child(_section(Lang.t("settings_panel.ready")))
	music_check = _toggle_row(Lang.t("settings_panel.ready_2"), func(on: bool): Music.set_enabled(on))
	volume_slider = _slider_row(Lang.t("settings_panel.ready_3"))
	volume_label = _slider_value
	volume_slider.value_changed.connect(func(v: float):
		Music.set_volume(v / 100.0, false)  # 끄는 동안 바로 들린다
		volume_label.text = "%d%%" % int(v))
	volume_slider.drag_ended.connect(func(_changed): Music.save_settings())
	sfx_check = _toggle_row(Lang.t("settings_panel.ready_4"), func(on: bool): SoundFx.set_enabled(on))
	sfx_slider = _slider_row(Lang.t("settings_panel.ready_5"))
	sfx_label = _slider_value
	sfx_slider.value_changed.connect(func(v: float):
		SoundFx.set_volume(v / 100.0, false)
		sfx_label.text = "%d%%" % int(v))
	sfx_slider.drag_ended.connect(func(_changed):
		SoundFx.set_volume(sfx_slider.value / 100.0)
		SoundFx.emit_sound("click"))  # 손을 떼면 저장하고 크기를 들려 준다

	body.add_child(_section(Lang.t("settings_panel.ready_6")))
	quality_buttons = _choice_row(Lang.t("settings_panel.ready_7"), GraphicsScript.QUALITIES.map(func(q): return [q, GraphicsScript.QUALITY_NAMES[q]]),
		func(q): _set_gfx("gfx_quality", q))
	fps_buttons = _choice_row(Lang.t("settings_panel.ready_8"), GraphicsScript.FPS_CHOICES.map(func(f): return [f, "%d" % f]), func(f): _set_gfx("gfx_fps", f))
	saver_check = _toggle_row(Lang.t("settings_panel.ready_9"), func(on: bool): _set_gfx("power_saver", on))
	_note(Lang.t("settings_panel.ready_10"))
	shake_check = _toggle_row(Lang.t("settings_panel.ready_11"), func(on: bool): Prefs.set_value("shake", on))
	numbers_check = _toggle_row(Lang.t("settings_panel.ready_12"), func(on: bool): Prefs.set_value("damage_numbers", on))
	# 2026-11-02 사용자: 영웅 머리 위 스킬 이름 띠를 켜고 끄고 크기를 고른다(DamageNumbers가 그릴 때마다 읽는다 — 바로 적용)
	banner_check = _toggle_row(Lang.t("settings_panel.skill_banner"), func(on: bool): Prefs.set_value("skill_banner", on))
	banner_size_buttons = _choice_row(Lang.t("settings_panel.skill_banner_size"),
		[["s", Lang.t("settings_panel.banner_size_s")], ["m", Lang.t("settings_panel.banner_size_m")], ["l", Lang.t("settings_panel.banner_size_l")]], func(z):
			Prefs.set_value("skill_banner_size", z)
			_style_choices(banner_size_buttons, DamageNumbersScript.banner_size_id()))
	notify_rows = NotifySettings.add_to(self)  # 푸시 알림 켬/끔(안드로이드만)

	body.add_child(_section(Lang.t("settings_panel.ready_13")))
	rename_button = _slot_button(Lang.t("settings_panel.ready_29"))  # 닉네임 변경(2026-11-05): 첫 번은 무료, 그 뒤는 다이아(nickname_panel.gd)
	rename_button.pressed.connect(open_rename)
	name_label = _info_row(Lang.t("settings_panel.ready_14"), rename_button)
	copy_button = _slot_button(Lang.t("settings_panel.ready_16"))
	copy_button.pressed.connect(copy_code)
	code_label = _info_row(Lang.t("settings_panel.ready_15"), copy_button)
	login_label = _info_row(Lang.t("settings_panel.ready_17"))
	account_link = AccountLinkScript.new()
	add_child(account_link)
	account_link.changed.connect(_refresh)
	link_row = _grid_row(Lang.t("settings_panel.ready_18"))
	for provider in AccountLinkScript.PROVIDERS:
		var b := _slot_button(AccountLinkScript.NAMES[provider])
		b.pressed.connect(func(): account_link.start(provider))
		link_buttons[provider] = b
		_slot(link_row, 1, b)
	link_label = _note("")
	logout_button = _action_button(Lang.t("settings_panel.ready_19"))
	logout_button.pressed.connect(press_logout)
	delete_button = _action_button(Lang.t("settings_panel.ready_21"))
	delete_button.pressed.connect(press_delete)
	body.add_child(_action_grid([logout_button, delete_button]))

	body.add_child(_section(Lang.t("settings_panel.ready_22")))
	admin_button = _slot_button(Lang.t("settings_panel.ready_27"), UiKit.AMBER)  # 공지·점검·우편·쿠폰 만들기(슈퍼관리자만 보인다) — 버전 줄 오른쪽
	admin_button.pressed.connect(func():
		if admin_panel != null:
			close()
			admin_panel.open())
	version_label = _info_row(Lang.t("settings_panel.ready_23"), admin_button)
	terms_button = _action_button(Lang.t("settings_panel.ready_24"))
	terms_button.pressed.connect(func(): open_link(Links.TERMS_URL))
	privacy_button = _action_button(Lang.t("settings_panel.ready_25"))
	privacy_button.pressed.connect(func(): open_link(Links.PRIVACY_URL))
	inquiry_button = _action_button(Lang.t("settings_panel.ready_26"))
	inquiry_button.pressed.connect(open_inquiry)
	coupon_button = _action_button(Lang.t("settings_panel.ready_20"))  # 쿠폰(2026-10-12, LiveOps)
	coupon_button.pressed.connect(func():
		if coupon != null:
			close()
			coupon.open())
	body.add_child(_action_grid([terms_button, privacy_button, inquiry_button, coupon_button]))

	var close_button := _button(Lang.t("settings_panel.ready_28"), UiKit.STEEL)
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
	for c in [music_check, shake_check, numbers_check, banner_check, volume_slider, sfx_check, sfx_slider, saver_check]:
		c.set_block_signals(true)
	music_check.button_pressed = Music.enabled
	sfx_check.button_pressed = SoundFx.enabled
	sfx_slider.value = roundf(SoundFx.volume * 100.0)
	shake_check.button_pressed = Prefs.get_bool("shake")
	numbers_check.button_pressed = Prefs.get_bool("damage_numbers")
	banner_check.button_pressed = Prefs.get_bool("skill_banner")
	saver_check.button_pressed = GraphicsScript.saver_enabled()
	volume_slider.value = roundf(Music.volume * 100.0)
	for c in [music_check, shake_check, numbers_check, banner_check, volume_slider, sfx_check, sfx_slider, saver_check]:
		c.set_block_signals(false)
		if c is Button:
			_style_toggle(c)
	volume_label.text = "%d%%" % int(volume_slider.value)
	sfx_label.text = "%d%%" % int(sfx_slider.value)
	var online := Net.is_online()
	var code := str(Economy.friends.get("code", ""))
	name_label.text = str(Economy.nickname.get("name", Economy.friends.get("name", "…"))) if online else Lang.t("settings_panel.refresh")
	rename_button.visible = online and not Economy.nickname.is_empty()
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
	_style_choices(banner_size_buttons, DamageNumbersScript.banner_size_id())


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
	if _logging_out or not Net.is_online() or ReleasePlatform.is_toss():
		return
	if _logout_armed <= 0.0:
		_logout_armed = DELETE_ARM_SEC
		_style_logout()
		return
	if _logout_armed > DELETE_ARM_SEC - CONFIRM_GAP_SEC:
		return  # 첫 누름과 같은 두 번 누름 — 확인으로 치지 않는다
	_logout_armed = 0.0
	_logging_out = true  # 다시 열 때까지 또 누르지 못하게(로그아웃·재시작이 두 번 돌지 않게)
	Net.logout()
	Economy.notice.emit(Lang.t("settings_panel.press_logout"))
	await get_tree().create_timer(1.5).timeout
	Net.restart.call()


func _style_logout() -> void:
	var armed := _logout_armed > 0.0
	logout_button.text = Lang.t("settings_panel.style_logout") if armed else Lang.t("settings_panel.style_logout_2")
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
		link_label.text = Lang.t("settings_panel.style_links")
	else:
		link_label.text = Lang.t("settings_panel.style_links_2")


## 웹 주소를 브라우저로 연다. 비어 있으면 준비 중 알림.
func open_link(url: String) -> void:
	if url == "":
		Economy.notice.emit(Links.NOT_READY)
		return
	OS.shell_open(url)


## [문의하기](2026-10-14): 게임 안 문의 창(inquiry_panel.gd — 문의 표, 답변은 우편). 온라인이 아니면 알림.
func open_inquiry() -> void:
	if inquiry == null or not Net.is_online():
		Economy.notice.emit(Lang.t("settings_panel.open_inquiry"))
		return
	close()
	inquiry.open()


## [계정 삭제]: 첫 번째는 확인을 묻고(빨간 "한 번 더 누르면 계정이 삭제됩니다"), 4초 안에 다시 누르면 서버에서 지운다. 되돌릴 수 없다.
func press_delete() -> void:
	if _deleting or not Net.is_online():
		return
	if _delete_armed <= 0.0:
		_delete_armed = DELETE_ARM_SEC
		_style_delete()
		return
	if _delete_armed > DELETE_ARM_SEC - CONFIRM_GAP_SEC:
		return  # 첫 누름과 같은 두 번 누름 — 확인으로 치지 않는다
	_delete_armed = 0.0
	_deleting = true
	Net.send("POST", "/v1/account/delete", {"confirm": "delete"}, func(_d): Net.forget_account(),
		func():
			_deleting = false
			_style_delete()
			Economy.notice.emit(Lang.t("settings_panel.press_delete")))


func _style_delete() -> void:
	var armed := _delete_armed > 0.0
	delete_button.text = Lang.t("settings_panel.style_delete") if armed else Lang.t("settings_panel.style_delete_2")
	UiKit.apply_button(delete_button, Color(0.85, 0.27, 0.22) if armed else UiKit.STEEL, 12.0)


## [변경](닉네임 줄): 닉네임 변경 창을 연다(첫 번은 무료, 그 뒤 다이아).
func open_rename() -> void:
	if nickname_panel == null or Economy.nickname.is_empty():
		return
	close()
	nickname_panel.open()


func copy_code() -> void:
	var code := str(Economy.friends.get("code", ""))
	if code != "":
		DisplayServer.clipboard_set(code)
		Economy.notice.emit(Lang.t("settings_panel.copy_code"))


## 줄 모양(2026-11-05 "오와열"): 모든 줄 = [이름 LABEL_W | 칸 | 칸 | 칸]. 세 칸은 같은 너비라 선택 버튼·켬/끔·값·[변경]·[복사]가
## 줄마다 같은 세로줄에 선다. 켬/끔은 언제나 셋째 칸, 선택지는 오른쪽 끝부터, 값은 첫째 칸 왼쪽부터.
## 아래 [로그아웃]·[계정 삭제]·[이용약관]… 같은 동작 버튼은 창 너비 2열(_action_grid).
func _grid_row(text: String, free_label := false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.add_child(_row_label(text, free_label))
	body.add_child(row)
	return row


## row에 칸 span개 너비의 자리를 붙이고 c(없으면 빈 자리)를 넣는다. 칸마다 왼쪽 SLOT_GAP 여백 — span 2의 끝은 둘째 칸 끝과 같다.
func _slot(row: HBoxContainer, span: int, c: Control = null) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", int(SLOT_GAP))
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.size_flags_stretch_ratio = float(span)
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if c != null:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		m.add_child(c)
	row.add_child(m)
	return m


## 칸 하나를 채우는 버튼(글자가 길어도 칸 너비를 바꾸지 않게 자른다).
func _slot_button(text: String, color := UiKit.STEEL) -> Button:
	var b := _button(text, color, 22)
	b.custom_minimum_size = Vector2(0, 52)
	b.clip_text = true
	b.focus_mode = Control.FOCUS_NONE
	return b


## 창 너비 2열 동작 버튼.
func _action_button(text: String) -> Button:
	var b := _button(text, UiKit.STEEL, 22)
	b.custom_minimum_size = Vector2(0, 56)
	b.clip_text = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _action_grid(buttons: Array) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	for b in buttons:
		g.add_child(b)
	return g


## 이름 칸 아래 줄(첫째 칸 왼쪽에 맞춘 작은 안내 글).
func _note(text: String) -> Label:
	var l := _label(text, 20, SUB, HORIZONTAL_ALIGNMENT_LEFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = LABEL_W + SLOT_GAP
	l.add_theme_stylebox_override("normal", sb)
	body.add_child(l)
	return l


## [이름 | 슬라이더(칸 둘) | "n%"] 한 줄. 반환 = 슬라이더(글자 = _slider_value).
func _slider_row(text: String) -> HSlider:
	var row := _grid_row(text)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 1
	s.custom_minimum_size = Vector2(0, 48)
	s.focus_mode = Control.FOCUS_NONE
	_slot(row, 2, s)
	_slider_value = _label("", 24, HudScript.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_slot(row, 1, _slider_value)
	return s


func _section(text: String) -> Label:
	var l := _label(text, 26, SUB, HORIZONTAL_ALIGNMENT_LEFT)
	l.custom_minimum_size = Vector2(0, 40)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return l


## 줄 이름. free = 글자가 길면 빈 칸 위로 넘어가도 된다(켬/끔 줄 — 첫째·둘째 칸이 비어 있다): 이름 칸 너비는 그대로.
func _row_label(text: String, free := false) -> Control:
	var l := _label(text, 24, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if not free:
		l.custom_minimum_size = Vector2(LABEL_W, 52)
		l.clip_text = true
		return l
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(LABEL_W, 52)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2.ZERO
	l.size = Vector2(LABEL_W * 3.0, 52)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(l)
	return holder


## 이름 + 셋째 칸 켬/끔 버튼(켬 = 주황, 끔 = 회색). 누르면 on_change(켬?)를 바로 부른다.
func _toggle_row(text: String, on_change: Callable) -> Button:
	var row := _grid_row(text, true)
	_slot(row, 2)
	var b := _slot_button("")
	b.toggle_mode = true
	b.toggled.connect(func(on: bool):
		_style_toggle(b)
		on_change.call(on))
	_slot(row, 1, b)
	_style_toggle(b)
	return b


func _style_toggle(b: Button) -> void:
	b.text = Lang.t("settings_panel.toggle_row") if b.button_pressed else Lang.t("settings_panel.style_toggle")
	UiKit.apply_button(b, UiKit.AMBER if b.button_pressed else UiKit.STEEL, 12.0)


## 이름 + 값 글자(첫째·둘째 칸) + 셋째 칸 action(없으면 빈 칸). 값 Label을 돌려준다.
func _info_row(text: String, action: Button = null) -> Label:
	var row := _grid_row(text)
	var v := _label("", 24, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.custom_minimum_size = Vector2(0, 52)
	v.clip_text = true
	_slot(row, 2, v)
	_slot(row, 1, action)
	return v


## [이름 | 선택지 버튼들(오른쪽 칸부터)] 한 줄. 고른 버튼은 주황. on_pick(id)를 바로 부른다. 반환 = id → Button.
func _choice_row(text: String, options: Array, on_pick: Callable) -> Dictionary:
	var row := _grid_row(text)
	if options.size() < 3:
		_slot(row, 3 - options.size())
	var out := {}
	for o in options:
		var b := _slot_button(o[1])
		var id = o[0]
		b.pressed.connect(func(): on_pick.call(id))
		_slot(row, 1, b)
		out[id] = b
	return out


func _style_choices(buttons: Dictionary, picked) -> void:
	for id in buttons:
		UiKit.apply_button(buttons[id], UiKit.AMBER if id == picked else UiKit.STEEL, 12.0)

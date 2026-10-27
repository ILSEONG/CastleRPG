extends Control
## 보상형 광고 재생(상점 [광고] 탭, 2026-10-12): play(done)으로 열고, 끝까지 보면 done.call()로 보상을 받게 한다. 중간에 [닫기]면 보상 없음.
## 안드로이드 APK: CastleAds 플러그인(AdMob 보상형 광고, ID는 scripts/ad_config.gd — 지금은 Google 테스트 ID)을 띄우고,
## 끝까지 봐서 보상 콜백이 왔을 때만 done.call(표)(서버는 body.ad = true와 표를 받는다). 불러오지 못하면 보상 없이 안내만 한다.
## 표(2026-10-22): 띄우기 전에 Economy.ad_start로 받아 광고의 서버 확인(SSV) custom_data로 넘긴다 — AdMob이 게임 서버에 직접 "끝까지 봤다"를 알린다.
## 플러그인이 없는 곳(PC, 앱인토스 — 토스 광고 미연결)은 SECONDS초짜리 시험 화면이다.
## 광고 제거(Economy.ad_free) 구매자는 이 창을 거치지 않는다(shop_panel._buy).

const Lang := preload("res://scripts/lang.gd")

const UiKit := preload("res://scripts/ui_kit.gd")
const AdConfig := preload("res://scripts/ad_config.gd")

const SECONDS := 5.0
static var instant := false  # 테스트: 곧바로 끝까지 본 것으로

var _done: Callable
var _left := 0.0
var _ads: Object  # CastleAds 싱글턴(안드로이드 APK에서만)
var _waiting := false  # 실제 광고: 불러오는 중이거나 화면에 떠 있음
var _token := ""  # 이번 광고의 서버 확인 표(Economy.ad_start)
var title_label: Label
var sub_label: Label
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
	title_label = _label(Lang.t("ad_player.ready"), 40, Color.WHITE)
	col.add_child(title_label)
	sub_label = _label(Lang.t("ad_player.ready_2"), 22, Color(1, 1, 1, 0.7))
	col.add_child(sub_label)
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 22)
	bar.show_percentage = false
	bar.max_value = SECONDS
	col.add_child(bar)
	time_label = _label("", 26, Color(1, 0.93, 0.6))
	col.add_child(time_label)
	close_button = Button.new()
	close_button.text = Lang.t("ad_player.ready_3")
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(200, 64)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.add_theme_font_size_override("font_size", 24)
	UiKit.apply_button(close_button, UiKit.STEEL, 12.0)
	close_button.pressed.connect(_close)
	col.add_child(close_button)
	if Engine.has_singleton("CastleAds"):
		_ads = Engine.get_singleton("CastleAds")
		_ads.connect("ad_loaded", _on_ad_loaded)
		_ads.connect("ad_closed", _on_ad_closed)
		_ads.initialize()
		_ads.load(AdConfig.ANDROID_REWARDED_ID)  # 미리 불러 두면 누르자마자 뜬다


## 광고를 띄운다. 끝까지 보면 done.call(표) — 표는 실제 광고의 서버 확인 값(시험 화면·실패면 "").
func play(done: Callable) -> void:
	if visible:
		return  # 이미 재생 중(빠른 두 번 누름) — 같은 광고를 다시 시작하지 않는다
	if instant:
		done.call("")
		return
	_done = done
	if _ads != null:
		_play_real()
		return
	_left = SECONDS
	_tick()
	visible = true


## 실제 광고: 불러 둔 게 있으면 곧바로 띄우고, 없으면 "불러오는 중" 화면에서 기다린다.
func _play_real() -> void:
	_waiting = true
	_token = ""
	sub_label.text = Lang.t("ad_player.play_real")
	time_label.text = Lang.t("ad_player.play_real_2")
	bar.visible = false
	visible = true
	Economy.ad_start(_on_token)


func _on_token(token: String) -> void:
	if not _waiting:
		return  # 표를 받는 사이 [닫기]
	_token = token
	_ads.setSsv(token)
	if _ads.isLoaded():
		_ads.show()
	else:
		_ads.load(AdConfig.ANDROID_REWARDED_ID)


func _on_ad_loaded(ok: bool, error: String) -> void:
	if not _waiting:
		return  # 미리 불러 두기만 한 것
	if ok:
		_ads.show()
		return
	_waiting = false
	# AdMob 오류 번호(앞의 "3:No fill." 중 3)를 같이 보여 준다 — 폰 로그 없이 원인을 알 수 있게(0 내부, 1 잘못된 요청, 2 네트워크, 3 광고 없음)
	var code := error.get_slice(":", 0)
	sub_label.text = Lang.t("ad_player.on_ad_loaded") + (" (%s)" % code if code != "" else "")
	time_label.text = Lang.t("ad_player.on_ad_loaded_2")


func _on_ad_closed(earned: bool) -> void:
	_waiting = false
	visible = false
	_ads.load(AdConfig.ANDROID_REWARDED_ID)  # 다음 광고를 미리 불러 둔다
	if earned and _done.is_valid():
		_done.call(_token)


func _close() -> void:
	_waiting = false
	visible = false


func _process(delta: float) -> void:
	if not visible or _ads != null:
		return
	_left -= delta
	if _left <= 0.0:
		visible = false
		_done.call("")
		return
	_tick()


func _tick() -> void:
	bar.value = SECONDS - _left
	time_label.text = Lang.t("ad_player.tick") % ceili(_left)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

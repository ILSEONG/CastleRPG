extends "res://scripts/ui_window.gd"
## 핫딜(BM 2026-10-07, 사용자 "핫딜 결제도 구현해줘"): 보스 격파(25라운드마다)·다이아 부족·패배 때 1시간 한정 특가가 뜬다(Economy.hot_offer).
## 뜨면 이 창(가운데 특가 카드 + 남은 시간 + ₩ 구매)이 열린다 — 전투 중(스테이지·카운트다운·결과)이면 대기(방치)로 돌아왔을 때.
## 떠 있는 동안 성 화면 왼쪽(배속 버튼 위)에 [핫딜 59:59] 버튼이 남아 다시 열 수 있다. 사기는 다른 결제 상품과 같은 Economy.iap_buy(₩).
## 튜토리얼 중에는 띄우지 않는다(계기를 보내지 않음).

const IapItems := preload("res://scripts/iap_items.gd")
const IconsScript := preload("res://scripts/icons.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const RED := Color(0.86, 0.22, 0.18)
const GIVE := Color(0.16, 0.5, 0.22)
const BTN_SIZE := Vector2(84, 84)
const SIDE := 16.0
const GAP := 12.0

var speed  # speed_button.gd(있으면 그 위에 핫딜 버튼)
var hud_layer: CanvasLayer  # 성 화면 버튼 층(HUD와 같은 1)
var hud_button: Button
var buy_button: Button
var name_label: Label
var give_label: Label
var time_label: Label
var _badge: Control
var _face: Control
var _pending := false  # 떴는데 전투 중이라 아직 안 열었다
var _shown_id := ""
var _boss_wait := 0  # 깬 보스 라운드 — 서버가 알면 핫딜 계기를 보낸다


func _ready() -> void:
	_build_window(600, 14)
	layer = 3  # 모집 창 등 다른 창(2) 위 — 다이아 부족 핫딜은 모집 창 위에 뜬다
	var head := _label("핫딜 · 1시간 한정 특가", 26, RED)
	content.add_child(head)
	_badge = Control.new()
	_badge.custom_minimum_size = Vector2(0, 150)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.draw.connect(_draw_badge)
	content.add_child(_badge)
	name_label = _title("")
	content.add_child(name_label)
	give_label = _label("", 24, GIVE)
	give_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	give_label.custom_minimum_size = Vector2(540, 0)
	content.add_child(give_label)
	time_label = _label("", 24, HudScript.INK)
	content.add_child(time_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	content.add_child(row)
	buy_button = _button("", HudScript.ACCENT, 28)
	buy_button.focus_mode = Control.FOCUS_NONE
	buy_button.custom_minimum_size = Vector2(260, 76)
	buy_button.pressed.connect(func():
		var h := Economy.active_hot()
		if not h.is_empty():
			Economy.iap_buy(str(h.id)))
	row.add_child(buy_button)
	var later := _button("나중에", UiKit.STEEL, 26)
	later.focus_mode = Control.FOCUS_NONE
	later.custom_minimum_size = Vector2(180, 76)
	later.pressed.connect(close)
	row.add_child(later)
	var note := _label("결제 기능은 출시 전에 연결됩니다", 18, Color(HudScript.INK, 0.7))
	content.add_child(note)
	_build_hud_button()
	Economy.hot_offered.connect(_on_offered)
	Economy.shop_changed.connect(_sync)
	GameState.mode_changed.connect(func(_m): _maybe_open())
	GameState.stage_cleared.connect(_on_cleared)
	GameState.stage_failed.connect(func(_s): _trigger("defeat"))


func _build_hud_button() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 1
	hud_layer.name = "HotDealButton"
	get_parent().add_child.call_deferred(hud_layer)  # 창(이 CanvasLayer)이 숨어도 보이게 형제로
	hud_button = Button.new()
	hud_button.focus_mode = Control.FOCUS_NONE
	hud_button.custom_minimum_size = BTN_SIZE
	hud_button.size = BTN_SIZE
	UiKit.apply_button(hud_button, RED, 12.0)
	_face = Control.new()
	_face.size = BTN_SIZE
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.draw.connect(_draw_face)
	hud_button.add_child(_face)
	hud_button.pressed.connect(open)
	hud_button.visible = false
	hud_layer.add_child(hud_button)


## 깬 마지막 라운드(서버와 같은 기준).
static func cleared() -> int:
	return maxi(GameState.stage, Economy.server_stage) - 1


func _trigger(trigger: String) -> void:
	if Tutorial.active():
		return
	Economy.hot_offer(trigger, cleared())


## 보스 라운드(25·50·…)를 깼다: 서버가 그 라운드를 깬 것으로 안 뒤(server_stage)에 보낸다(서버는 자기 기록으로 확인한다).
func _on_cleared(stage: int) -> void:
	if stage % IapItems.HOT_ROUNDS != 0:
		return
	if Economy.net == null:
		if not Tutorial.active():
			Economy.hot_offer("boss", stage)
		return
	_boss_wait = stage


## 다이아 부족(모집 창 "다이아가 부족합니다")에서 부른다.
func short_of_diamonds() -> void:
	_trigger("dia")


func _on_offered(_hot: Dictionary) -> void:
	_pending = true
	_sync()
	_maybe_open()


## 전투 중(스테이지·카운트다운·결과)이 아니면 연다. 다이아 부족 핫딜은 대기 중에 뜨니 곧바로.
func _maybe_open() -> void:
	if not _pending or GameState.mode != GameState.Mode.IDLE:
		return
	_pending = false
	if not Economy.active_hot().is_empty():
		open()


func _on_open() -> void:
	_sync()


func _sync() -> void:
	var h := Economy.active_hot()
	hud_button.visible = not h.is_empty()
	if h.is_empty():
		if visible:
			close()
		return
	var p := IapItems.find(str(h.id))
	if _shown_id != str(h.id):
		_shown_id = str(h.id)
		name_label.text = p.name
		give_label.text = Missions.reward_text(p.give)
		buy_button.text = "₩" + UiKit.commas(int(p.krw))
		_badge.queue_redraw()
	_tick()


func _tick() -> void:
	var h := Economy.active_hot()
	var left := maxf(0.0, float(h.get("until", 0.0)) - Economy.time_now())
	time_label.text = "남은 시간 " + UiKit.duration(left)
	_face.queue_redraw()


var _t := 0.0


func _process(delta: float) -> void:
	_place()
	if _boss_wait > 0 and Economy.server_stage - 1 >= _boss_wait:
		_boss_wait = 0
		_trigger("boss")
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	var on := not Economy.active_hot().is_empty()
	if on != hud_button.visible:
		_sync()
	elif on:
		_tick()


## 성 화면 왼쪽: 배속 버튼 바로 위(배속 버튼이 없으면 같은 높이 규칙). 성 월드가 트리에서 빠지면(던전 등) 숨긴다.
func _place() -> void:
	if speed != null and is_instance_valid(speed) and speed.button != null:
		hud_layer.visible = speed.is_inside_tree()
		hud_button.position = speed.button.position - Vector2(0, BTN_SIZE.y + GAP)
	else:
		var vh := get_viewport().get_visible_rect().size.y
		hud_button.position = Vector2(SIDE, vh * 0.70 - BTN_SIZE.y * 1.5 - GAP)


func _left_text() -> String:
	var left := int(maxf(0.0, float(Economy.active_hot().get("until", 0.0)) - Economy.time_now()))
	return "%02d:%02d" % [left / 60, left % 60]


func _draw_face() -> void:
	var ink := Color(UiKit.INK, 0.85)
	IconsScript.draw_icon(_face, "diamond", Vector2(BTN_SIZE.x / 2.0, 24.0), 30.0)
	_text(_face, "핫딜", 54.0, 20, Color.WHITE, ink)
	_text(_face, _left_text(), 76.0, 16, Color(1, 0.93, 0.6), ink)


func _text(c: Control, t: String, y: float, size: int, col: Color, ink: Color) -> void:
	c.draw_string_outline(FONT, Vector2(0, y), t, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, size, 5, ink)
	c.draw_string(FONT, Vector2(0, y), t, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, size, col)


## 가운데 보석 더미 + "가치 N배" 별 딱지.
func _draw_badge() -> void:
	var p := IapItems.find(_shown_id)
	if p.is_empty():
		return
	var c := _badge.size / 2.0
	for j in [Vector2(-40, 18), Vector2(40, 18), Vector2(0, 30), Vector2(0, -6)]:
		IconsScript.draw_icon(_badge, "diamond", c + j, 58.0)
	var o := c + Vector2(150, -30)
	var pts := PackedVector2Array()
	for k in 24:
		var a := TAU * k / 24.0
		pts.append(o + Vector2(cos(a), sin(a)) * (58.0 if k % 2 == 0 else 46.0))
	_badge.draw_colored_polygon(pts, RED)
	_text_at(_badge, "가치", o + Vector2(0, -6), 18)
	_text_at(_badge, "%d배" % int(p.get("value", 1)), o + Vector2(0, 20), 26)


func _text_at(c: Control, t: String, at: Vector2, size: int) -> void:
	var ink := Color(RED.darkened(0.5), 0.9)
	c.draw_string_outline(FONT, at - Vector2(60, 0), t, HORIZONTAL_ALIGNMENT_CENTER, 120, size, 5, ink)
	c.draw_string(FONT, at - Vector2(60, 0), t, HORIZONTAL_ALIGNMENT_CENTER, 120, size, Color.WHITE)

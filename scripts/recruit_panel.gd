extends "res://scripts/ui_window.gd"
## 주점 모집 창(스펙 §5, 주점 탭으로 연다): 제목, 확률 한 줄, [1회 모집 300] [10회 모집 2700(SR 이상 1장 보장)]
## (골드가 모자라거나 응답을 기다리는 중이면 비활성), 결과 화면(카드 1장 또는 10장 5 × 2: 등급 테두리·보석·이름·칭호·
## NEW 또는 별, SSR은 반짝임) + [확인]. 모집은 Economy.gacha, 결과는 Economy.gacha_done — 온라인 응답이 창을 닫은 뒤에
## 와도 다시 열어 보여 준다(결과를 놓치지 않게).

const GameData := preload("res://scripts/game_data.gd")
const EconomyScript := preload("res://scripts/economy.gd")
const Skills := preload("res://scripts/skills.gd")
const HeroCardScript := preload("res://scripts/hero_card.gd")

const DIALOG_W := 680
const CARD_SIZE := Vector2(118, 160)

var one_button: Button
var ten_button: Button
var confirm_button: Button
var cards: Array = []  # 지금 보이는 결과 카드

var _pick_view: VBoxContainer
var _result_view: VBoxContainer
var _grid: GridContainer
var _waiting := false


func _ready() -> void:
	_build_window(DIALOG_W)
	content.add_child(_title("주점 · 영웅 모집"))
	_pick_view = VBoxContainer.new()
	_pick_view.add_theme_constant_override("separation", 14)
	content.add_child(_pick_view)
	_pick_view.add_child(_label(rates_text(), 28))
	one_button = _button("1회 모집 %d" % EconomyScript.gacha_cost(1))
	one_button.pressed.connect(_recruit.bind(1))
	_pick_view.add_child(one_button)
	ten_button = _button("10회 모집 %d\n(SR 이상 %d장 보장)" % [EconomyScript.gacha_cost(10), int(GameData.config_num("gacha_10_min_sr"))], HudScript.ACCENT, 26)
	ten_button.custom_minimum_size = Vector2(0, 92)
	ten_button.pressed.connect(_recruit.bind(10))
	_pick_view.add_child(ten_button)
	var close_button := _button("닫기", UiKit.STEEL)
	close_button.pressed.connect(close)
	_pick_view.add_child(close_button)

	_result_view = VBoxContainer.new()
	_result_view.add_theme_constant_override("separation", 16)
	_result_view.visible = false
	content.add_child(_result_view)
	var center := CenterContainer.new()
	_result_view.add_child(center)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 12)
	center.add_child(_grid)
	confirm_button = _button("확인")
	confirm_button.pressed.connect(_show_pick)
	_result_view.add_child(confirm_button)
	Economy.changed.connect(func(): if visible: _refresh())
	Economy.gacha_done.connect(_on_gacha_done)


func _on_open() -> void:
	_show_pick()


func is_showing_results() -> bool:
	return visible and _result_view.visible


## "SSR 3% · SR 17% · R 80%"(설정 값에서).
static func rates_text() -> String:
	var ssr := GameData.config_num("gacha_rate_ssr")
	var sr := GameData.config_num("gacha_rate_sr")
	return "SSR %s%% · SR %s%% · R %s%%" % [Skills.num_text(ssr * 100.0), Skills.num_text(sr * 100.0), Skills.num_text((1.0 - ssr - sr) * 100.0)]


func _recruit(count: int) -> void:
	if _waiting:
		return  # 응답 전 재탭
	_waiting = true  # 오프라인은 gacha 안에서 바로 gacha_done이 온다 — 그 전에 둔다
	_refresh()
	if not Economy.gacha(count):
		_waiting = false
		_refresh()


func _on_gacha_done(results: Array) -> void:
	_waiting = false
	if results.is_empty():
		_refresh()
		return
	if not visible:
		open()
	for c in cards:
		_grid.remove_child(c)
		c.queue_free()
	cards.clear()
	_grid.columns = mini(5, results.size())
	for r in results:
		var card = HeroCardScript.new()
		card.custom_minimum_size = CARD_SIZE
		card.hero_id = r.hero_id
		card.badge = "NEW" if r.new else ""
		card.stars = HeroCardScript.stars_of(int(r.copies))
		_grid.add_child(card)
		cards.append(card)
	_pick_view.visible = false
	_result_view.visible = true
	_fit()


func _show_pick() -> void:
	_result_view.visible = false
	_pick_view.visible = true
	_fit()
	_refresh()


func _refresh() -> void:
	one_button.disabled = _waiting or Economy.gold < EconomyScript.gacha_cost(1)
	ten_button.disabled = _waiting or Economy.gold < EconomyScript.gacha_cost(10)

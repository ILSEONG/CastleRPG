extends "res://scripts/ui_window.gd"
## 주점 모집 창(스펙 §5, 주점 탭으로 연다): 제목, 확률 한 줄, [1회 모집 300] [10회 모집 2700(SR 이상 1장 보장)]
## (골드가 모자라거나 응답을 기다리는 중이면 비활성), 결과 화면(카드 1장 또는 10장 5 × 2: 등급 테두리·보석·피규어(개정 14)·이름·칭호·
## 새 영웅은 "NEW", 중복은 "+1 조각"과 그 영웅의 조각 막대(개정 15), SSR은 반짝임) + [확인]. 모집은 Economy.gacha, 결과는 Economy.gacha_done — 온라인 응답이 창을 닫은 뒤에
## 와도 다시 열어 보여 준다(결과를 놓치지 않게). 다른 창(영웅·거래)이 열려 있으면 그 위로 열지 않고 알림만 띄우고,
## 결과는 다음에 주점 창을 열 때 보여 준다. 결과 화면이 뜨면 연 직후처럼 보호 시간을 다시 건다([확인] 연타 방지).

const GameData := preload("res://scripts/game_data.gd")
const EconomyScript := preload("res://scripts/economy.gd")
const Skills := preload("res://scripts/skills.gd")
const HeroCardScript := preload("res://scripts/hero_card.gd")

const DIALOG_W := 680
const CARD_SIZE := Vector2(118, 180)
const LATE_TEXT := "모집 결과 도착 — 주점에서 확인하세요"
const DUP_TEXT := "+1 조각"  # 이미 가진 영웅(개정 15)

var one_button: Button
var ten_button: Button
var confirm_button: Button
var cards: Array = []  # 지금 보이는 결과 카드

var _pick_view: VBoxContainer
var _result_view: VBoxContainer
var _grid: GridContainer
var _waiting := false
var _late: Array = []  # 다른 창이 열려 있어 못 보여 준 결과(다음에 열 때)
var _rates_label: Label


func _ready() -> void:
	_build_window(DIALOG_W)
	content.add_child(_title("주점 · 영웅 모집"))
	_pick_view = VBoxContainer.new()
	_pick_view.add_theme_constant_override("separation", 14)
	content.add_child(_pick_view)
	_rates_label = _label(rates_text(), 28)
	_pick_view.add_child(_rates_label)
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
	_rates_label.text = rates_text()  # 주점 레벨이 올랐을 수 있다
	if _late.is_empty():
		_show_pick()
		return
	var r := _late
	_late = []
	_show_results(r)


func is_showing_results() -> bool:
	return visible and _result_view.visible


## "SSR 3% · SR 17% · R 80%"(설정 값 + 주점 레벨 보너스, 개정 12).
static func rates_text() -> String:
	var rates: Dictionary = Economy.gacha_rates()
	var ssr: float = rates.ssr
	var sr: float = rates.sr
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
		if _another_window_open():  # 그 창 위로 겹쳐 열지 않는다(어둠이 겹치고 층 순서에 따라 결과가 가려진다)
			_late = results
			Economy.notice.emit(LATE_TEXT)
			return
		open()
	_show_results(results)


## 결과 카드 1장 또는 10장(5 × 2) + [확인]. 보호 시간을 다시 건다.
func _show_results(results: Array) -> void:
	for c in cards:
		_grid.remove_child(c)
		c.queue_free()
	cards.clear()
	_grid.columns = mini(5, results.size())
	for r in results:
		var card = HeroCardScript.new()
		card.custom_minimum_size = CARD_SIZE
		card.hero_id = r.hero_id
		card.stars = Economy.promotion_of(r.hero_id)
		if r.new:
			card.badge = "NEW"
		else:  # 개정 15: 중복은 "+1 조각"과 그 장까지의 조각 막대
			card.badge = DUP_TEXT
			card.badge_color = HeroCardScript.BAR_FILL.darkened(0.2)
			card.shards = int(r.get("shards", 0))
			card.shard_need = Economy.promote_cost(r.hero_id)
		_grid.add_child(card)
		cards.append(card)
	_pick_view.visible = false
	_result_view.visible = true
	_fit()
	_arm_guard()


func _show_pick() -> void:
	_result_view.visible = false
	_pick_view.visible = true
	_fit()
	_refresh()


func _refresh() -> void:
	one_button.disabled = _waiting or Economy.gold < EconomyScript.gacha_cost(1)
	ten_button.disabled = _waiting or Economy.gold < EconomyScript.gacha_cost(10)

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
const AUTO_DELAY := 1.2  # 결과를 보여 준 뒤 다음 자동 모집까지 초
const SSR_TEXT := "SSR 등장 — 자동 모집을 멈췄습니다"
var one_button: Button
var ten_button: Button
var confirm_button: Button
var again_button: Button  # [재모집 N] — 자동 중엔 "자동 중…"
var auto_box: Button  # 자동 모집 체크박스(Fever.auto_recruit에 저장)
var auto_delay := AUTO_DELAY  # 테스트가 줄인다
var cards: Array = []  # 지금 보이는 결과 카드

var _pick_view: VBoxContainer
var _result_view: VBoxContainer
var _grid: GridContainer
var _waiting := false
var _count := 1  # 마지막 모집 장수([재모집]·자동이 되풀이한다)
var _halted := false  # 골드 부족·SSR·실패·창 닫힘으로 자동이 멈춤(체크는 그대로, 다음에 직접 모집하면 다시 돈다)
var _auto_left := 0.0  # 다음 자동 모집까지 남은 초
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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_result_view.add_child(row)
	again_button = _button("재모집", UiKit.AMBER)
	again_button.custom_minimum_size = Vector2(0, 72)
	again_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again_button.pressed.connect(_again)
	row.add_child(again_button)
	confirm_button = _button("확인")
	confirm_button.custom_minimum_size = Vector2(0, 72)
	confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_button.pressed.connect(_on_confirm)
	row.add_child(confirm_button)
	auto_box = UiKit.checkbox("자동 모집")
	auto_box.set_pressed_no_signal(Fever.auto_recruit)
	auto_box.toggled.connect(_on_auto_toggled)
	_result_view.add_child(auto_box)
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
	_count = count
	_halted = false
	_auto_left = 0.0
	_waiting = true  # 오프라인은 gacha 안에서 바로 gacha_done이 온다 — 그 전에 둔다
	_refresh()
	if not Economy.gacha(count):
		_halted = true
		_waiting = false
		_refresh()


func _on_gacha_done(results: Array) -> void:
	_waiting = false
	if results.is_empty():
		_halted = true  # 온라인 실패(알림은 Economy가 띄운다) — 자동을 멈춘다
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
	var stop := auto_running() and results.any(func(r): return r.grade == "SSR")
	if stop:  # 안전: 자동 중 SSR이 나오면 멈추고 그 카드를 강조(반짝임은 카드가 이미 낸다)
		_halted = true
		Economy.notice.emit(SSR_TEXT)
	for i in results.size():
		cards[i].highlight = stop and results[i].grade == "SSR"
	_auto_left = auto_delay
	_pick_view.visible = false
	_result_view.visible = true
	_fit()
	_arm_guard()
	_refresh()


func _show_pick() -> void:
	_result_view.visible = false
	_pick_view.visible = true
	_fit()
	_refresh()


func auto_running() -> bool:
	return auto_box.button_pressed and not _halted


func _again() -> void:
	if not _waiting and not again_button.disabled:
		_recruit(_count)


## [확인]: 자동이 돌고 있었다면 멈추고(체크도 푼다) 결과 화면을 닫는다.
func _on_confirm() -> void:
	if auto_running():
		auto_box.button_pressed = false
	_halted = true
	_show_pick()


func _on_auto_toggled(on: bool) -> void:
	Fever.auto_recruit = on
	Fever.save()  # save_path가 ""이면(테스트) 쓰지 않는다
	_halted = false
	_auto_left = auto_delay
	_refresh()


func close() -> void:
	_halted = true
	super.close()


## 자동 모집: 결과를 보여 준 지 auto_delay초 뒤 같은 모집을 되풀이. 골드가 모자라면 멈춘다.
func _process(delta: float) -> void:
	if not (visible and _result_view.visible and auto_running() and not _waiting):
		return
	_auto_left -= delta
	if _auto_left > 0.0:
		return
	if Economy.gold < EconomyScript.gacha_cost(_count):
		_halted = true
		_refresh()
		return
	_recruit(_count)


func _refresh() -> void:
	one_button.disabled = _waiting or Economy.gold < EconomyScript.gacha_cost(1)
	ten_button.disabled = _waiting or Economy.gold < EconomyScript.gacha_cost(10)
	var cost := EconomyScript.gacha_cost(_count)
	var short := Economy.gold < cost
	if auto_running() and not short:
		again_button.text = "자동 중…"
	else:
		again_button.text = "재모집 %d" % cost + ("\n골드 부족" if short else "")
	again_button.disabled = _waiting or short or auto_running()

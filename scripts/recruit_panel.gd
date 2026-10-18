extends "res://scripts/ui_window.gd"
## 영웅 모집 창(스펙 §5, 개정 23: 골드·다이아 모집, 주점 탭으로 연다): 위 가운데 키 아트(이그니스가 화염구를 쏘는 순간 — 움직이지 않는
## 정지 그림 + 가장자리 비네트 + 외곽선 제목 "영웅 모집"), 그 아래 탭 [골드 모집] [다이아 모집].
## 골드 탭: 레벨 배지 "골드 모집 Lv n", 진행 막대 + "다음 레벨까지 a/b", 다음 레벨 확률·비용 미리보기, 확률 한 줄, [1회 3,000] [10회 30,000](10회 = 1회 × 10, 보장 없음).
## 다이아 탭: 보유(보석 아이콘 + 수), 확률 한 줄, 천장 "SSR 확정까지 n회", [1회 다이아 300] [10회 다이아 2,700 · SR 이상 1장].
## 다이아 모집권이 그 장수만큼 있으면 그 버튼은 모집권 버튼([1회 모집권 1장] [10회 모집권 10장 · SR 이상 1장])으로 바뀌고 모집권을 쓴다(버튼마다 따로).
## 다이아 버튼은 다이아가 모자라도 눌린다: 누르면 "다이아가 부족합니다 — 상점으로 이동할까요?" 창, [이동]이면 다이아 상점을 연다(사용자 요청 2026-10-06).
## 골드가 모자라거나 응답을 기다리는 중이면 모집 버튼은 비활성. 결과 화면(카드 1장 또는 10장 5 × 2: 등급 테두리·보석·피규어(개정 14)·이름·칭호·
## 새 영웅은 "NEW", 중복은 "+1 조각"과 그 영웅의 조각 막대(개정 15), SSR은 반짝임) + [재모집]·[확인]·자동 모집(개정 17) — 마지막에 뽑은 재화로 되풀이한다.
## 자동 모집은 골드만(현금 재화 자동 소모 방지): 다이아로 뽑은 결과 화면에는 자동 체크가 없다.
## 모집은 Economy.gacha(count, currency), 결과는 Economy.gacha_done — 온라인 응답이 창을 닫은 뒤에 와도 다시 열어 보여 준다(결과를 놓치지 않게).
## 다른 창(영웅·거래)이 열려 있으면 그 위로 열지 않고 알림만 띄우고, 결과는 다음에 주점 창을 열 때 보여 준다. 결과 화면이 뜨면 연 직후처럼
## 보호 시간을 다시 건다([확인] 연타 방지).

const Lang := preload("res://scripts/lang.gd")

const GameData := preload("res://scripts/game_data.gd")
const Skills := preload("res://scripts/skills.gd")
const HeroCardScript := preload("res://scripts/hero_card.gd")
const IconsScript := preload("res://scripts/icons.gd")
const SceneSnap := preload("res://scripts/scene_snap.gd")
const RecruitArt := preload("res://scripts/recruit_art.gd")
const RecruitBanner := preload("res://scripts/recruit_banner.gd")
const CardReveal := preload("res://scripts/card_reveal.gd")
const SummonStage := preload("res://scripts/summon_stage.gd")
const GachaOdds := preload("res://scripts/gacha_odds.gd")

const DIALOG_W := 680
const CARD_SIZE := Vector2(118, 180)
const GOLD := GameData.GACHA_GOLD
const DIA := GameData.GACHA_DIA
const TICKET := GameData.GACHA_TICKET  # 다이아 모집권(튜토리얼 보상): 다이아 탭에서 장당 1회
static var TITLE := Lang.t("recruit_panel.title")
static var LATE_TEXT := Lang.t("recruit_panel.late_text")
static var DUP_TEXT := Lang.t("recruit_panel.dup_text")  # 이미 가진 영웅(개정 15)
const AUTO_DELAY := 1.2  # 결과를 보여 준 뒤 다음 자동 모집까지 초
static var SSR_TEXT := Lang.t("recruit_panel.ssr_text")
const REVEAL_ONE := 0.15  # 1회: 소환진이 걷힌 뒤 뒤집기까지(SR·SSR은 등급 빛이 다 모일 때까지 — CardReveal.begin)
const REVEAL_FIRST := 0.12  # 10회: 소환진이 걷힌 뒤 첫 카드
const REVEAL_STEP := 0.07  # 10회: 카드 사이(R·SR 먼저 왼쪽 위부터, SSR은 맨 끝에 무지개빛을 모았다가 하나씩)
const SSR_GAP := 0.6  # 10회: SSR 카드끼리 사이
const ONE_SCALE := 1.5  # 1회 결과 카드는 이만큼 크게
var gold_tab: Button
var dia_tab: Button
var one_button: Button
var ten_button: Button
var confirm_button: Button
var again_button: Button  # [1회 더] — 결과 화면에서 바로 이어 뽑기(2026-10-15 사용자 "연속뽑기 기능이 왜 없어"). 자동 중엔 "자동 모집 중"
var again10_button: Button  # [10회 더]
var auto_box: Button  # 자동 모집 체크박스(Fever.auto_recruit에 저장). 골드 결과에서만 보인다
var auto_delay := AUTO_DELAY  # 테스트가 줄인다
var cards: Array = []  # 지금 보이는 결과 카드(hero_card — 저마다 뒤집기 연출 card_reveal 안에 있다)
var currency := GOLD  # 고른 탭
var level_label: Label
var progress_bar: ProgressBar
var progress_label: Label
var preview_label: Label
var rates_label: Label
var dia_label: Label  # 다이아 보유
var pity_label: Label
var ticket_label: Label  # "다이아 모집권 n장"(있을 때만)
var odds_button: Button  # [확률 정보] — 영웅별 확률 안내(gacha_odds.gd)
var odds: Control  # 확률 안내 창
var shop_ask: Control  # "다이아가 부족합니다" 확인 창(어두운 막 + 크림 창)
var art: TextureRect  # 예전 3D 키 아트(처음 열 때 SceneSnap으로 렌더) — 일러스트 배너가 없을 때만 보인다
var banner: Control  # SSR 일러스트 배너(recruit_banner.gd)
var shop  # 상점 시트(shop_panel.gd, main이 넣는다) — [이동]이 [다이아] 탭으로 연다
var hot  # 핫딜(hot_deal.gd, main이 넣는다) — 다이아가 부족하면 다이아 긴급 지원 핫딜 계기

var _art_box: Control
var _btn_gems: Array = []  # [1회]·[10회] 앞 보석(다이아 탭만)
var _pick_view: VBoxContainer
var _result_view: VBoxContainer
var _gold_box: VBoxContainer
var _dia_box: VBoxContainer
var _grid: GridContainer
var _waiting := false
var _count := 1  # 마지막 모집 장수([재모집]·자동이 되풀이한다)
var _cur := GOLD  # 마지막 모집 재화
var _halted := false  # 재화 부족·SSR·실패·창 닫힘으로 자동이 멈춤(체크는 그대로, 다음에 직접 모집하면 다시 돈다)
var _auto_left := 0.0  # 다음 자동 모집까지 남은 초
var _late: Array = []  # 다른 창이 열려 있어 못 보여 준 결과(다음에 열 때)
var _reveals: Array = []  # 결과 카드마다 뒤집기 연출(card_reveal.gd, 그리드의 자식)
var stage  # 소환 연출 막(summon_stage.gd — 소환진 + SSR 일러스트 화면, 창 맨 위)
var _no_splash := false  # [건너뛰기]: 이번 결과는 SSR 화면도 건너뛴다


func _ready() -> void:
	_build_window(DIALOG_W)
	content.add_child(_build_art())
	_pick_view = VBoxContainer.new()
	_pick_view.add_theme_constant_override("separation", 12)
	content.add_child(_pick_view)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	_pick_view.add_child(tabs)
	gold_tab = _tab(Lang.t("recruit_panel.ready"), GOLD, tabs)
	dia_tab = _tab(Lang.t("recruit_panel.ready_2"), DIA, tabs)

	_gold_box = VBoxContainer.new()
	_gold_box.add_theme_constant_override("separation", 6)
	_pick_view.add_child(_gold_box)
	level_label = _label("", 32)
	_gold_box.add_child(level_label)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(0, 22)
	progress_bar.show_percentage = false
	UiKit.apply_bar(progress_bar, UiKit.AMBER)
	_gold_box.add_child(progress_bar)
	progress_label = _label("", 22)
	_gold_box.add_child(progress_label)
	preview_label = _label("", 20, Color(HudScript.INK, 0.75))
	_gold_box.add_child(preview_label)

	_dia_box = VBoxContainer.new()
	_dia_box.add_theme_constant_override("separation", 6)
	_pick_view.add_child(_dia_box)
	var have := HBoxContainer.new()
	have.alignment = BoxContainer.ALIGNMENT_CENTER
	have.add_theme_constant_override("separation", 8)
	_dia_box.add_child(have)
	have.add_child(_gem(36))
	dia_label = _label("", 32)
	have.add_child(dia_label)
	pity_label = _label("", 24, UiKit.GRADE_COLORS.SSR.darkened(0.25))
	_dia_box.add_child(pity_label)
	ticket_label = _label("", 26, UiKit.GRADE_COLORS.SR.darkened(0.2))  # 다이아 모집권: 다이아 대신 장당 1회(확률·천장은 다이아 모집과 같다)
	_dia_box.add_child(ticket_label)

	var rates_row := HBoxContainer.new()
	rates_row.alignment = BoxContainer.ALIGNMENT_CENTER
	rates_row.add_theme_constant_override("separation", 12)
	_pick_view.add_child(rates_row)
	rates_label = _label("", 26)
	rates_row.add_child(rates_label)
	odds_button = _button(Lang.t("recruit_panel.ready_3"), UiKit.STEEL, 20)
	odds_button.focus_mode = Control.FOCUS_NONE
	odds_button.custom_minimum_size = Vector2(130, 44)
	odds_button.pressed.connect(func(): odds.show_for(currency, Economy.gacha_state().gold_level))
	rates_row.add_child(odds_button)
	one_button = _button("")
	one_button.pressed.connect(_pull.bind(1))
	_pick_view.add_child(one_button)
	ten_button = _button("", HudScript.ACCENT, 26)
	ten_button.custom_minimum_size = Vector2(0, 72)
	ten_button.pressed.connect(_pull.bind(10))
	_pick_view.add_child(ten_button)
	for b in [one_button, ten_button]:
		var icon := _gem(30)  # 다이아 탭에서만 보이는 버튼 앞 보석(세로 가운데)
		icon.anchor_top = 0.5
		icon.anchor_bottom = 0.5
		icon.offset_left = 18
		icon.offset_right = 48
		icon.offset_top = -15
		icon.offset_bottom = 15
		b.add_child(icon)
		_btn_gems.append(icon)
	var close_button := _button(Lang.t("recruit_panel.ready_4"), UiKit.STEEL)
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
	again_button = _button("", UiKit.AMBER, 24)
	again10_button = _button("", HudScript.ACCENT, 24)
	for b in [again_button, again10_button]:
		b.custom_minimum_size = Vector2(0, 84)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	again_button.pressed.connect(_again.bind(1))
	again10_button.pressed.connect(_again.bind(10))
	confirm_button = _button(Lang.t("recruit_panel.ready_6"), UiKit.STEEL, 24)
	confirm_button.custom_minimum_size = Vector2(132, 84)
	confirm_button.pressed.connect(_on_confirm)
	row.add_child(confirm_button)
	auto_box = UiKit.checkbox(Lang.t("recruit_panel.ready_7"))
	auto_box.set_pressed_no_signal(Fever.auto_recruit)
	auto_box.toggled.connect(_on_auto_toggled)
	_result_view.add_child(auto_box)
	_build_shop_ask()
	odds = GachaOdds.new()
	add_child(odds)
	stage = SummonStage.new()  # 맨 위(확률 창·상점 확인 창 위)
	stage.intro_done.connect(_start_flips)
	stage.skip_all.connect(_skip_all)
	stage.splash_done.connect(_arm_guard)  # 걷힌 직후 연타가 밑의 [확인]을 누르지 않게
	add_child(stage)
	Economy.changed.connect(func(): if visible: _refresh())
	Economy.gacha_done.connect(_on_gacha_done)
	set_currency(GOLD)


## "다이아가 부족합니다 — 상점으로 이동할까요?" [이동] [취소]. 모집 창 위 어두운 막(뒤 탭을 막는다).
func _build_shop_ask() -> void:
	shop_ask = ColorRect.new()
	shop_ask.color = Color(0, 0, 0, 0.45)
	shop_ask.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_ask.mouse_filter = Control.MOUSE_FILTER_STOP
	shop_ask.visible = false
	add_child(shop_ask)
	var box := PanelContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_stylebox_override("panel", UiKit.scroll())
	shop_ask.add_child(box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	box.add_child(col)
	col.add_child(_label(Lang.t("recruit_panel.build_shop_ask"), 32))
	col.add_child(_label(Lang.t("recruit_panel.build_shop_ask_2"), 24, HudScript.INK.lightened(0.2)))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	col.add_child(row)
	for pair in [[Lang.t("recruit_panel.build_shop_ask_3"), UiKit.GRADE_COLORS.SR, true], [Lang.t("recruit_panel.build_shop_ask_4"), UiKit.STEEL, false]]:
		var b := _button(pair[0], pair[1], 28)
		b.custom_minimum_size = Vector2(200, 72)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_shop_ask.bind(pair[2]))
		row.add_child(b)


func _on_shop_ask(go: bool) -> void:
	shop_ask.visible = false
	_arm_guard()  # [취소] 밑의 [1회]·[10회]를 더블 탭의 두 번째 누름이 누르지 않게
	if go and shop != null:
		close()  # 모집 창을 닫고 상점 시트(하단 탭 [상점])의 [다이아] 탭
		shop.open_tab("diamond")


## 키 아트 자리: 창 내용 폭 × RecruitArt.VIEW.y에 정지 그림(채워 덮고 넘치는 쪽은 잘라 낸다). 위에 가장자리 비네트와 외곽선 제목.
func _build_art() -> Control:
	_art_box = Control.new()
	_art_box.custom_minimum_size = RecruitArt.VIEW
	_art_box.clip_contents = true
	art = TextureRect.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_box.add_child(art)
	banner = RecruitBanner.new()
	banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art_box.add_child(banner)
	var g := Gradient.new()  # 가운데 투명 → 가장자리 어둡게
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0.04, 0.02, 0.06, 0.78))
	g.add_point(0.55, Color(0, 0, 0, 0))
	var vt := GradientTexture2D.new()
	vt.gradient = g
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.5)
	vt.fill_to = Vector2(1.0, 1.0)
	var vignette := TextureRect.new()
	vignette.texture = vt
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_box.add_child(vignette)
	var title := _label(TITLE, 40, Color.WHITE)
	title.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	title.offset_top = -62
	title.offset_bottom = -10
	title.add_theme_color_override("font_outline_color", Color(HudScript.INK, 0.95))
	title.add_theme_constant_override("outline_size", 10)
	_art_box.add_child(title)
	return _art_box


func _tab(text: String, id: String, row: HBoxContainer) -> Button:
	var b := _button(text, UiKit.STEEL, 26)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 60)
	b.pressed.connect(set_currency.bind(id))
	row.add_child(b)
	return b


func _gem(px: float) -> Control:
	var g = IconsScript.new()
	g.kind = "diamond"
	g.custom_minimum_size = Vector2(px, px)
	g.size = Vector2(px, px)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


## 탭 고르기: 골드·다이아. 고른 탭은 호박색, 다른 탭은 강철색.
func set_currency(id: String) -> void:
	currency = id
	UiKit.apply_button(gold_tab, UiKit.AMBER if id == GOLD else UiKit.STEEL, 14.0)
	UiKit.apply_button(dia_tab, UiKit.AMBER if id == DIA else UiKit.STEEL, 14.0)
	_gold_box.visible = id == GOLD
	_dia_box.visible = id == DIA
	if visible:
		_fit()
	_refresh()


func _on_open() -> void:
	# 보통은 로딩 화면(preloader)이 미리 렌더해 캐시에 있다. 없으면 요청 — 그동안·헤드리스는 자리표시 그러데이션, 끝나면 _process가 바꿔 끼운다
	art.texture = SceneSnap.snap(RecruitArt.KEY, RecruitArt.SIZE, RecruitArt.build, RecruitArt.WARM)
	banner.visible = banner.has_art()
	art.visible = not banner.visible
	if _late.is_empty():
		_show_pick()
		return
	var r := _late
	_late = []
	_show_results(r)


func is_showing_results() -> bool:
	return visible and _result_view.visible


## "SSR 3% · SR 17% · R 80%"(그 재화의 지금 확률 — 골드 모집 레벨·주점 보너스 포함).
static func rates_text(cur := GOLD) -> String:
	return _rates_line(Economy.gacha_rates(cur))


static func _rates_line(rates: Dictionary) -> String:
	var ssr: float = rates.ssr
	var sr: float = rates.sr
	if ssr <= 0.0:  # 골드 모집 Lv 1~2(SSR은 GameData.GOLD_SSR_FROM부터)
		return Lang.t("recruit_panel.rates_line") % [GameData.GOLD_SSR_FROM, Skills.num_text(sr * 100.0), Skills.num_text((1.0 - sr) * 100.0)]
	return "SSR %s%% · SR %s%% · R %s%%" % [Skills.num_text(ssr * 100.0), Skills.num_text(sr * 100.0), Skills.num_text((1.0 - ssr - sr) * 100.0)]


## 이 장수를 무엇으로 뽑나: 골드 탭은 골드. 다이아(모집권 포함)는 모집권이 count장 이상이면 모집권, 아니면 다이아.
func pull_currency(count: int, base := "") -> String:
	var b := currency if base == "" else base
	if b == GOLD:
		return GOLD
	return TICKET if Economy.dia_tickets >= count else DIA


## [1회]·[10회]·다이아 [재모집]: 모집권이 있으면 모집권, 다이아가 모자라면 상점 이동 확인 창.
func _pull(count: int, base := "") -> void:
	if _waiting:
		return
	var cur := pull_currency(count, base)
	if cur == DIA and Economy.diamonds < Economy.gacha_cost(DIA, count):
		shop_ask.visible = true
		if hot != null:
			hot.short_of_diamonds()
		return
	_recruit(count, cur)


func _recruit(count: int, cur := "") -> void:
	if _waiting:
		return  # 응답 전 재탭
	_count = count
	_cur = currency if cur == "" else cur
	_halted = false
	_auto_left = 0.0
	_waiting = true  # 오프라인은 gacha 안에서 바로 gacha_done이 온다 — 그 전에 둔다
	_refresh()
	if not Economy.gacha(count, _cur):
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


## 결과 카드 1장(ONE_SCALE배 크게) 또는 10장(5 × 2) + [확인]. 보호 시간을 다시 건다. 먼저 화면 전체에 소환진(summon_stage — 최고 등급 빛 예고)이
## 돌고, 걷히면 뒷면 카드가 차례로 뒤집힌다(_start_flips). SSR 카드가 펴지면 SSR 일러스트 화면. 아무 카드나 누르면 남은 카드가 한꺼번에 뒤집히고,
## [건너뛰기]는 SSR 화면까지 건너뛴다. 자동 모집 중엔 소환진 없이 바로 뒤집는다.
func _show_results(results: Array) -> void:
	for h in _reveals:
		_grid.remove_child(h)
		h.queue_free()
	_reveals.clear()
	cards.clear()
	_grid.columns = mini(5, results.size())
	var fast := auto_running()
	var one := results.size() == 1
	_no_splash = false
	for i in results.size():
		var r: Dictionary = results[i]
		var card = HeroCardScript.new()
		card.hero_id = r.hero_id
		card.hide_title = true  # 작은 결과 카드: 칭호는 빼고 그림을 더 보인다
		card.stars = Economy.promotion_of(r.hero_id)
		if r.new:
			card.badge = "NEW"
		else:  # 개정 15: 중복은 "+1 조각"과 그 장까지의 조각 막대
			card.badge = DUP_TEXT
			card.badge_color = HeroCardScript.BAR_FILL.darkened(0.2)
			card.shards = int(r.get("shards", 0))
			card.shard_need = Economy.promote_cost(r.hero_id)
		var holder = CardReveal.new()
		holder.custom_minimum_size = CARD_SIZE * (ONE_SCALE if one else 1.0)
		holder.setup(card, String(r.grade), 0.0 if fast else -1.0)  # 소환진이 걷히면 _start_flips가 차례를 준다
		holder.skip_requested.connect(reveal_all)
		holder.revealed.connect(_on_card_revealed.bind(r))
		_grid.add_child(holder)
		_reveals.append(holder)
		cards.append(card)
	var stop := auto_running() and results.any(func(r): return r.grade == "SSR")
	if stop:  # 안전: 자동 중 SSR이 나오면 멈추고 그 카드를 강조(반짝임은 카드가 이미 낸다)
		_halted = true
		Economy.notice.emit(SSR_TEXT)
	for i in results.size():
		cards[i].highlight = stop and results[i].grade == "SSR"
	_auto_left = auto_delay
	if fast:
		stage.stop()
	else:
		var best := "SSR" if results.any(func(x): return x.grade == "SSR") else ("SR" if results.any(func(x): return x.grade == "SR") else "R")
		stage.play(best, results.size())
	auto_box.visible = _cur == GOLD  # 자동 모집은 골드만
	_pick_view.visible = false
	_result_view.visible = true
	_fit()
	_arm_guard()
	_refresh()


## 남은 결과 카드를 지금 다 뒤집는다(뒷면 카드를 누르면).
func reveal_all() -> void:
	for h in _reveals:
		h.reveal_now()


## 소환진이 걷혔다: R·SR 카드는 왼쪽 위부터 REVEAL_STEP 간격, SSR 카드는 그 뒤에 무지개빛을 모았다가 하나씩(SSR_GAP).
func _start_flips() -> void:
	_arm_guard()  # 소환진이 걷힌 직후 연타가 밑의 [확인]·[재모집]을 누르지 않게
	var at := REVEAL_ONE if _reveals.size() == 1 else REVEAL_FIRST
	for h in _reveals:
		if h.grade != "SSR":
			h.begin(at)
			at += REVEAL_STEP
	for h in _reveals:
		if h.grade == "SSR":
			h.begin(at + h.tease_sec())
			at += h.tease_sec() + SSR_GAP


## [건너뛰기]: 카드를 모두 바로 열고 SSR 화면도 띄우지 않는다.
func _skip_all() -> void:
	_no_splash = true
	reveal_all()


## 카드가 펴졌다: SSR이면 일러스트 화면(건너뛰기를 누르지 않았으면).
func _on_card_revealed(_holder, r: Dictionary) -> void:
	if r.grade == "SSR" and not _no_splash and visible:
		stage.splash(String(r.hero_id), bool(r.get("new", false)))


func _show_pick() -> void:
	if stage != null:
		stage.stop()
	_result_view.visible = false
	_pick_view.visible = true
	_fit()
	_refresh()


## 자동 모집이 도는 중(골드 결과에서만).
func auto_running() -> bool:
	return auto_box.button_pressed and not _halted and _cur == GOLD


## [1회 더]·[10회 더]: 방금 뽑은 재화(골드 / 다이아·모집권)로 n회 더. 모집권이 모자라면 다이아, 다이아가 모자라면 상점 이동 창.
## 참고: 원신·니케·에픽세븐의 결과 화면 [1회 더]·[10회 더](연속 뽑기).
func _again(n: int) -> void:
	var b: Button = again_button if n == 1 else again10_button
	if not _waiting and not b.disabled:
		_pull(n, GOLD if _cur == GOLD else DIA)


## [확인]: 자동이 돌고 있었다면 멈추고(체크도 푼다) 결과 화면을 닫는다.
func _on_confirm() -> void:
	if auto_running():
		auto_box.button_pressed = false
	_halted = true
	_show_pick()
	_arm_guard()  # 결과 화면 [확인] 자리에 뜨는 [10회 모집]을 더블 탭의 두 번째 누름이 누르지 않게


func _on_auto_toggled(on: bool) -> void:
	Fever.auto_recruit = on
	Fever.save()  # save_path가 ""이면(테스트) 쓰지 않는다
	_halted = false
	_auto_left = auto_delay
	_refresh()


func close() -> void:
	_halted = true
	if shop_ask != null:
		shop_ask.visible = false
	if stage != null:
		stage.stop()
	super.close()


## 키 아트 렌더가 끝나면 바꿔 끼운다(정지 그림 — 움직이지 않는다, 사용자 요청). 자동 모집: 결과를 보여 준 지 auto_delay초 뒤
## 같은 모집을 되풀이. 골드가 모자라면 멈춘다.
func _process(delta: float) -> void:
	if visible:
		var shot := SceneSnap.cached(RecruitArt.KEY)
		if shot != null and art.texture != shot:
			art.texture = shot  # 렌더가 끝났다
	if not (visible and _result_view.visible and auto_running() and not _waiting):
		return
	_auto_left -= delta
	if _auto_left > 0.0:
		return
	if Economy.wallet(_cur) < Economy.gacha_cost(_cur, _count):
		_halted = true
		_refresh()
		return
	_recruit(_count, _cur)


func _refresh() -> void:
	var st: Dictionary = Economy.gacha_state()
	var lv: int = st.gold_level
	level_label.text = Lang.t("recruit_panel.refresh") % lv
	var maxed: bool = st.gold_next <= 0
	progress_bar.max_value = 1 if maxed else st.gold_next
	progress_bar.value = 1 if maxed else st.gold_pulls
	progress_label.text = Lang.t("recruit_panel.refresh_2") if maxed else Lang.t("recruit_panel.refresh_3") % [st.gold_pulls, st.gold_next]
	preview_label.visible = not maxed
	if not maxed:
		var nr := GameData.gacha_rates(GOLD, lv + 1)
		preview_label.text = Lang.t("recruit_panel.refresh_4") % [lv + 1, Skills.num_text(nr.ssr * 100.0), Skills.num_text(nr.sr * 100.0),
			UiKit.commas(GameData.gacha_cost(GOLD, 1, lv + 1))]
	dia_label.text = Lang.t("recruit_panel.refresh_5") % UiKit.commas(Economy.diamonds)
	pity_label.text = Lang.t("recruit_panel.refresh_6") % st.pity_left
	var tk := Economy.dia_tickets
	var tk_shown := tk > 0 and currency == DIA
	if ticket_label.visible != tk_shown:
		ticket_label.visible = tk_shown
		if visible:
			_fit()
	ticket_label.text = Lang.t("recruit_panel.refresh_7") % tk
	rates_label.text = rates_text(currency)
	for i in 2:
		var b: Button = [one_button, ten_button][i]
		var n: int = [1, 10][i]
		var cur := pull_currency(n)
		var unit: String = {DIA: Lang.t("recruit_panel.refresh_8"), TICKET: Lang.t("recruit_panel.refresh_9")}.get(cur, "")
		var pad := "      " if cur == DIA else ""  # 버튼 앞 보석 자리(다이아일 때만)
		var cost := Economy.gacha_cost(cur, n)
		b.text = Lang.t("recruit_panel.refresh_10") % [pad, n, unit, ((Lang.t("recruit_panel.refresh_11") % cost) if cur == TICKET else UiKit.commas(cost))]
		if n == 10 and cur != GOLD:  # SR 이상 보장은 다이아(모집권 포함) 10연차만
			b.text += Lang.t("recruit_panel.refresh_12") % int(GameData.config_num("gacha_10_min_sr"))
		_btn_gems[i].visible = cur == DIA
		if b.get_meta("cur", GOLD) != cur:  # 모집권 버튼은 SR 색
			b.set_meta("cur", cur)
			UiKit.apply_button(b, UiKit.GRADE_COLORS.SR if cur == TICKET else HudScript.ACCENT, 14.0)
		# 골드는 모자라면 끈다. 다이아는 눌러서 상점 이동 창을 띄운다
		b.disabled = cur == GOLD and Economy.wallet(GOLD) < cost  # 응답을 기다리는 동안에도 모양은 그대로(재탭은 _pull이 무시)
	for i in 2:
		var b: Button = [again_button, again10_button][i]
		var n: int = [1, 10][i]
		var again_cur := pull_currency(n, GOLD if _cur == GOLD else DIA)
		var cost := Economy.gacha_cost(again_cur, n)
		var short := Economy.wallet(again_cur) < cost
		var head := Lang.t("recruit_panel.refresh.head") % n
		if auto_running() and n == _count and not short:
			b.text = Lang.t("recruit_panel.refresh_13")
		elif again_cur == TICKET:
			b.text = head + "\n" + Lang.t("recruit_panel.refresh_18") % cost
		elif short:
			b.text = head + (Lang.t("recruit_panel.refresh_16") if again_cur == DIA else Lang.t("recruit_panel.refresh_17"))
		else:
			b.text = head + "\n" + (Lang.t("recruit_panel.refresh_8") if again_cur == DIA else "") + UiKit.commas(cost)
		b.disabled = (short and again_cur == GOLD) or auto_running()

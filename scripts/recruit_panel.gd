extends "res://scripts/ui_window.gd"
## 영웅 모집 창(스펙 §5, 개정 23: 골드·다이아 모집, 주점 탭으로 연다): 위 가운데 키 아트(이그니스가 화염구를 쏘는 순간 — 움직이지 않는
## 정지 그림 + 가장자리 비네트 + 외곽선 제목 "영웅 모집"), 그 아래 탭 [골드 모집] [다이아 모집].
## 골드 탭: 레벨 배지 "골드 모집 Lv n", 진행 막대 + "다음 레벨까지 a/b", 다음 레벨 확률·비용 미리보기, 확률 한 줄, [1회 3,000] [10회 30,000](10회 = 1회 × 10, 보장 없음).
## 다이아 탭: 보유(보석 아이콘 + 수), 확률 한 줄, 천장 "SSR 확정까지 n회", [1회 다이아 300] [10회 다이아 2,700 · SR 이상 1장], [다이아 상점].
## 재화가 모자라거나 응답을 기다리는 중이면 모집 버튼은 비활성. 결과 화면(카드 1장 또는 10장 5 × 2: 등급 테두리·보석·피규어(개정 14)·이름·칭호·
## 새 영웅은 "NEW", 중복은 "+1 조각"과 그 영웅의 조각 막대(개정 15), SSR은 반짝임) + [재모집]·[확인]·자동 모집(개정 17) — 마지막에 뽑은 재화로 되풀이한다.
## 자동 모집은 골드만(현금 재화 자동 소모 방지): 다이아로 뽑은 결과 화면에는 자동 체크가 없다.
## 모집은 Economy.gacha(count, currency), 결과는 Economy.gacha_done — 온라인 응답이 창을 닫은 뒤에 와도 다시 열어 보여 준다(결과를 놓치지 않게).
## 다른 창(영웅·거래)이 열려 있으면 그 위로 열지 않고 알림만 띄우고, 결과는 다음에 주점 창을 열 때 보여 준다. 결과 화면이 뜨면 연 직후처럼
## 보호 시간을 다시 건다([확인] 연타 방지).

const GameData := preload("res://scripts/game_data.gd")
const Skills := preload("res://scripts/skills.gd")
const HeroCardScript := preload("res://scripts/hero_card.gd")
const IconsScript := preload("res://scripts/icons.gd")
const SceneSnap := preload("res://scripts/scene_snap.gd")
const RecruitArt := preload("res://scripts/recruit_art.gd")
const DiamondShopScript := preload("res://scripts/diamond_shop.gd")

const DIALOG_W := 680
const CARD_SIZE := Vector2(118, 180)
const GOLD := GameData.GACHA_GOLD
const DIA := GameData.GACHA_DIA
const TITLE := "영웅 모집"
const LATE_TEXT := "모집 결과 도착 — 주점에서 확인하세요"
const DUP_TEXT := "+1 조각"  # 이미 가진 영웅(개정 15)
const AUTO_DELAY := 1.2  # 결과를 보여 준 뒤 다음 자동 모집까지 초
const SSR_TEXT := "SSR 등장 — 자동 모집을 멈췄습니다"
var gold_tab: Button
var dia_tab: Button
var one_button: Button
var ten_button: Button
var shop_button: Button
var confirm_button: Button
var again_button: Button  # [재모집 N] — 자동 중엔 "자동 중…"
var auto_box: Button  # 자동 모집 체크박스(Fever.auto_recruit에 저장). 골드 결과에서만 보인다
var auto_delay := AUTO_DELAY  # 테스트가 줄인다
var cards: Array = []  # 지금 보이는 결과 카드
var currency := GOLD  # 고른 탭
var level_label: Label
var progress_bar: ProgressBar
var progress_label: Label
var preview_label: Label
var rates_label: Label
var dia_label: Label  # 다이아 보유
var pity_label: Label
var art: TextureRect  # 키 아트(처음 열 때 SceneSnap으로 렌더)
var shop  # 다이아 상점 창

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


func _ready() -> void:
	_build_window(DIALOG_W)
	content.add_child(_build_art())
	_pick_view = VBoxContainer.new()
	_pick_view.add_theme_constant_override("separation", 12)
	content.add_child(_pick_view)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	_pick_view.add_child(tabs)
	gold_tab = _tab("골드 모집", GOLD, tabs)
	dia_tab = _tab("다이아 모집", DIA, tabs)

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

	rates_label = _label("", 26)
	_pick_view.add_child(rates_label)
	one_button = _button("")
	one_button.pressed.connect(_recruit.bind(1))
	_pick_view.add_child(one_button)
	ten_button = _button("", HudScript.ACCENT, 26)
	ten_button.custom_minimum_size = Vector2(0, 72)
	ten_button.pressed.connect(_recruit.bind(10))
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
	shop_button = _button("다이아 상점", UiKit.GRADE_COLORS.SR, 26)
	shop_button.pressed.connect(func(): shop.open())
	_pick_view.add_child(shop_button)
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
	shop = DiamondShopScript.new()
	add_child(shop)
	Economy.changed.connect(func(): if visible: _refresh())
	Economy.gacha_done.connect(_on_gacha_done)
	set_currency(GOLD)


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
	shop_button.visible = id == DIA
	for g in _btn_gems:
		g.visible = id == DIA
	if visible:
		_fit()
	_refresh()


func _on_open() -> void:
	# 보통은 로딩 화면(preloader)이 미리 렌더해 캐시에 있다. 없으면 요청 — 그동안·헤드리스는 자리표시 그러데이션, 끝나면 _process가 바꿔 끼운다
	art.texture = SceneSnap.snap(RecruitArt.KEY, RecruitArt.SIZE, RecruitArt.build, RecruitArt.WARM)
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
	return "SSR %s%% · SR %s%% · R %s%%" % [Skills.num_text(ssr * 100.0), Skills.num_text(sr * 100.0), Skills.num_text((1.0 - ssr - sr) * 100.0)]


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
	auto_box.visible = _cur == GOLD  # 자동 모집은 골드만
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


## 자동 모집이 도는 중(골드 결과에서만).
func auto_running() -> bool:
	return auto_box.button_pressed and not _halted and _cur == GOLD


func _again() -> void:
	if not _waiting and not again_button.disabled:
		_recruit(_count, _cur)


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
	if shop != null:
		shop.close()
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
	level_label.text = "골드 모집 Lv %d" % lv
	var maxed: bool = st.gold_next <= 0
	progress_bar.max_value = 1 if maxed else st.gold_next
	progress_bar.value = 1 if maxed else st.gold_pulls
	progress_label.text = "최대 레벨" if maxed else "다음 레벨까지 %d/%d" % [st.gold_pulls, st.gold_next]
	preview_label.visible = not maxed
	if not maxed:
		var nr := GameData.gacha_rates(GOLD, lv + 1, Economy.building_level(GameData.TAVERN))
		preview_label.text = "Lv %d: SSR %s%% · SR %s%% · 1회 %s" % [lv + 1, Skills.num_text(nr.ssr * 100.0), Skills.num_text(nr.sr * 100.0),
			UiKit.commas(GameData.gacha_cost(GOLD, 1, lv + 1))]
	dia_label.text = "보유 %s" % UiKit.commas(Economy.diamonds)
	pity_label.text = "SSR 확정까지 %d회" % st.pity_left
	rates_label.text = rates_text(currency)
	var unit := "다이아 " if currency == DIA else ""
	var pad := "      " if currency == DIA else ""  # 버튼 앞 보석 자리
	one_button.text = "%s1회 %s%s" % [pad, unit, UiKit.commas(Economy.gacha_cost(currency, 1))]
	ten_button.text = "%s10회 %s%s" % [pad, unit, UiKit.commas(Economy.gacha_cost(currency, 10))]
	if currency == DIA:  # SR 이상 보장은 다이아 10연차만
		ten_button.text += " · SR 이상 %d장" % int(GameData.config_num("gacha_10_min_sr"))
	var have := Economy.wallet(currency)
	one_button.disabled = _waiting or have < Economy.gacha_cost(currency, 1)
	ten_button.disabled = _waiting or have < Economy.gacha_cost(currency, 10)
	var cost := Economy.gacha_cost(_cur, _count)
	var short := Economy.wallet(_cur) < cost
	if auto_running() and not short:
		again_button.text = "자동 중…"
	else:
		again_button.text = "재모집 %s%s" % ["다이아 " if _cur == DIA else "", UiKit.commas(cost)] + (("\n다이아 부족" if _cur == DIA else "\n골드 부족") if short else "")
	again_button.disabled = _waiting or short or auto_running()

extends VBoxContainer
## 던전 시트의 [PVP] 탭 내용(dungeon_panel이 붙인다). 세 화면을 같은 자리에서 바꾼다:
## - 홈: 위 "PVP 코인 n" + [상점], 모드 카드 둘(결투·총력전 — 등급 배지·포인트·다음 등급까지 막대·오늘 남은 도전, [입장]).
## - 모드 메인 페이지: [뒤로] 제목 [상점] / 내 등급 카드(배지·포인트·전적·남은 도전·초기화까지) / 상대 카드(이름·등급·전투력·영웅 5, 총력전은 병사 수) /
##   출전 영웅 5 [팀 바꾸기] / 방어팀 5 [방어팀 설정](총력전은 방어 병사 = 보유 병사 중 높은 티어 20명) / [전투 시작 n/5].
## - 팀 고르기(출전·방어 같은 화면): 슬롯 5 + 보유 영웅 격자(전투력 순) + [자동 편성] [뒤로] [확인]. 방어팀 [확인]은 곧바로 저장(Pvp.set_defense).
## 버튼은 누르는 즉시 반영된다(Pvp가 앱 값을 먼저 바꾸고 서버 확인은 뒤에서) — 기다리는 글자가 없다. 막히면 버튼을 끄고 빨간 이유 한 줄.

const GameData := preload("res://scripts/game_data.gd")
const UiKit := preload("res://scripts/ui_kit.gd")
const HudScript := preload("res://scripts/hud.gd")
const PvpRules := preload("res://scripts/pvp_rules.gd")
const HeroCardScript := preload("res://scripts/hero_card.gd")
const ShopScript := preload("res://scripts/pvp_shop.gd")

const RED := Color(0.78, 0.22, 0.18)
const MINI := Vector2(108, 136)
const SLOT := Vector2(108, 136)
const GRID_CARD := Vector2(150, 184)

var shop  # pvp_shop.gd 창(이 화면이 만든다 — 부모 창에 붙인다)
var page := ""  # "" = 홈, 아니면 모드
var picking := ""  # "" | "team" | "defense"
var team := {}  # 모드 → 출전 영웅 id(이번 실행 동안 기억)
var pick: Array = []  # 고르는 중인 영웅
var buttons := {}  # 테스트용 "start", "enter:duel", "shop", "defense" …

var _home: VBoxContainer
var _page: VBoxContainer
var _picker: VBoxContainer
var _coin_label: Label
var _cards := {}  # 모드 → {badge, tier, points, bar, plays, enter}
var _p := {}  # 모드 페이지 위젯
var _pick_slots: Array = []
var _pick_cards := {}
var _pick_grid: GridContainer
var _pick_title: Label
var _pick_reason: Label
var _pick_ok: Button
var _tick := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_home()
	_build_page()
	_build_picker()
	Pvp.changed.connect(refresh)
	Economy.roster_changed.connect(refresh)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			Pvp.fetch_if_stale()
			refresh())


## 부모 창이 연 뒤 붙인다(창 레이어 위에 상점 창).
func attach_shop(parent: Node) -> void:
	shop = ShopScript.new()
	parent.add_child(shop)


func show_home() -> void:
	page = ""
	picking = ""
	refresh()


func open_mode(mode: String) -> void:
	page = mode
	picking = ""
	if not team.has(mode) or team[mode].size() != PvpRules.TEAM:
		team[mode] = Pvp.default_team(mode)
	refresh()


# --- 홈 ---

func _build_home() -> void:
	_home = VBoxContainer.new()
	_home.add_theme_constant_override("separation", 12)
	_home.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_home)
	_home.add_child(_coin_row(func(l): _coin_label = l))
	for m in PvpRules.MODES:
		_home.add_child(_mode_card(m))
	var note := _label("모드마다 하루 %d번 · 이기면 포인트와 PVP 코인, 지면 포인트가 조금 줄어요" % PvpRules.PLAYS, 20, HudScript.INK.lightened(0.3))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_home.add_child(note)


func _coin_row(keep: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var coin := Control.new()
	coin.custom_minimum_size = Vector2(36, 36)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin.draw.connect(draw_coin.bind(coin))
	row.add_child(coin)
	var l := _label("", 28, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	keep.call(l)
	var b := _button("상점", UiKit.AMBER, 24)
	b.custom_minimum_size = Vector2(120, 52)
	b.pressed.connect(func(): shop.open())
	row.add_child(b)
	buttons["shop"] = b
	return row


func _mode_card(m: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM, 14.0, 14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(120, 140)
	badge.draw.connect(func(): draw_badge(badge, str(_tier_id(m))))
	row.add_child(badge)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	col.add_child(_label(PvpRules.NAMES[m], 34, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	var blurb := _label(PvpRules.BLURB[m], 20, HudScript.INK.lightened(0.3), HORIZONTAL_ALIGNMENT_LEFT)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(blurb)
	var tier := _label("", 24, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	col.add_child(tier)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 14)
	bar.show_percentage = false
	UiKit.apply_bar(bar, UiKit.AMBER)
	col.add_child(bar)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	col.add_child(foot)
	var plays := _label("", 22, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	plays.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plays.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(plays)
	var enter := _button("입장", HudScript.ACCENT, 26)
	enter.custom_minimum_size = Vector2(140, 60)
	enter.pressed.connect(open_mode.bind(m))
	foot.add_child(enter)
	buttons["enter:" + m] = enter
	_cards[m] = {"badge": badge, "tier": tier, "bar": bar, "plays": plays}
	return panel


func _tier_id(m: String) -> String:
	return str(PvpRules.tier_of(Pvp.points(m)).id)


# --- 모드 메인 페이지 ---

func _build_page() -> void:
	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation", 10)
	_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.visible = false
	add_child(_page)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_page.add_child(head)
	var back := _button("◀ 뒤로", UiKit.STEEL, 22)
	back.custom_minimum_size = Vector2(120, 52)
	back.pressed.connect(show_home)
	head.add_child(back)
	_p.title = _label("", 36, HudScript.INK)
	_p.title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_p.title)
	var sb := _button("상점", UiKit.AMBER, 22)
	sb.custom_minimum_size = Vector2(120, 52)
	sb.pressed.connect(func(): shop.open())
	head.add_child(sb)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	# 내 등급
	var me := PanelContainer.new()
	me.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM, 14.0, 12))
	body.add_child(me)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 14)
	me.add_child(mrow)
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(120, 140)
	badge.draw.connect(func(): draw_badge(badge, _tier_id(page) if page != "" else "bronze"))
	mrow.add_child(badge)
	_p.badge = badge
	var mcol := VBoxContainer.new()
	mcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mrow.add_child(mcol)
	_p.tier = _label("", 30, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	mcol.add_child(_p.tier)
	_p.bar = ProgressBar.new()
	_p.bar.custom_minimum_size = Vector2(0, 14)
	_p.bar.show_percentage = false
	UiKit.apply_bar(_p.bar, UiKit.AMBER)
	mcol.add_child(_p.bar)
	_p.record = _label("", 22, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	mcol.add_child(_p.record)
	_p.plays = _label("", 22, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	mcol.add_child(_p.plays)
	# 상대
	var opp := PanelContainer.new()
	opp.add_theme_stylebox_override("panel", UiKit.panel(Color("F3E6E2"), 14.0, 12))
	body.add_child(opp)
	var ocol := VBoxContainer.new()
	ocol.add_theme_constant_override("separation", 6)
	opp.add_child(ocol)
	_p.opp_name = _label("", 28, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	ocol.add_child(_p.opp_name)
	_p.opp_info = _label("", 22, HudScript.INK.lightened(0.2), HORIZONTAL_ALIGNMENT_LEFT)
	ocol.add_child(_p.opp_info)
	_p.opp_row = _card_row()
	ocol.add_child(_p.opp_row.get_parent())
	# 출전
	body.add_child(_section("출전 영웅", "팀 바꾸기", func(): _open_picker("team")))
	_p.team_row = _card_row()
	body.add_child(_p.team_row.get_parent())
	_p.team_info = _label("", 20, HudScript.INK.lightened(0.3), HORIZONTAL_ALIGNMENT_LEFT)
	body.add_child(_p.team_info)
	# 방어
	body.add_child(_section("방어팀", "방어팀 설정", func(): _open_picker("defense")))
	_p.def_row = _card_row()
	body.add_child(_p.def_row.get_parent())
	_p.def_info = _label("", 20, HudScript.INK.lightened(0.3), HORIZONTAL_ALIGNMENT_LEFT)
	_p.def_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_p.def_info)
	_p.reason = _label("", 22, RED)
	_page.add_child(_p.reason)
	_p.start = _button("전투 시작", HudScript.ACCENT, 32)
	_p.start.custom_minimum_size = Vector2(0, 76)
	_p.start.pressed.connect(_start)
	_page.add_child(_p.start)
	buttons["start"] = _p.start


func _section(text: String, button: String, f: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := _label(text, 26, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	var b := _button(button, UiKit.STEEL, 22)
	b.custom_minimum_size = Vector2(170, 50)
	b.pressed.connect(f)
	row.add_child(b)
	buttons[button] = b
	return row


## 카드 5장 줄(가운데 정렬). 반환 = 카드를 넣는 HBox(부모 = CenterContainer).
func _card_row() -> HBoxContainer:
	var c := CenterContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	c.add_child(row)
	for i in PvpRules.TEAM:
		var card = HeroCardScript.new()
		card.custom_minimum_size = MINI
		row.add_child(card)
	return row


func _fill_row(row: HBoxContainer, heroes: Array) -> void:
	for i in row.get_child_count():
		var c = row.get_child(i)
		var h = heroes[i] if i < heroes.size() else null
		if h is Dictionary:
			c.hero_id = str(h.get("hero", ""))
			c.level = int(h.get("level", 0))
			c.stars = int(h.get("promotion", 0))
			c.power = 0
		elif h is String:
			c.hero_id = h
			c.level = Economy.level_of(h)
			c.stars = Economy.promotion_of(h)
			c.power = 0
		else:
			c.hero_id = ""
			c.level = 0
			c.stars = 0
		c.queue_redraw()


func _start() -> void:
	if page == "":
		return
	Pvp.start(page, team.get(page, []))
	refresh()


# --- 팀 고르기 ---

func _build_picker() -> void:
	_picker = VBoxContainer.new()
	_picker.add_theme_constant_override("separation", 10)
	_picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_picker.visible = false
	add_child(_picker)
	_pick_title = _label("", 34, HudScript.INK)
	_picker.add_child(_pick_title)
	_picker.add_child(_label("영웅을 눌러 넣고 빼세요", 22, HudScript.INK.lightened(0.3)))
	var sc := CenterContainer.new()
	_picker.add_child(sc)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 6)
	sc.add_child(srow)
	for i in PvpRules.TEAM:
		var card = HeroCardScript.new()
		card.custom_minimum_size = SLOT
		card.corner = str(i + 1)
		card.tapped.connect(func(_c):
			if i < pick.size():
				pick.remove_at(i)
			_refresh_picker())
		srow.add_child(card)
		_pick_slots.append(card)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_picker.add_child(scroll)
	var gc := CenterContainer.new()
	gc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(gc)
	_pick_grid = GridContainer.new()
	_pick_grid.columns = 4
	_pick_grid.add_theme_constant_override("h_separation", 10)
	_pick_grid.add_theme_constant_override("v_separation", 10)
	gc.add_child(_pick_grid)
	_pick_reason = _label("", 22, RED)
	_picker.add_child(_pick_reason)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_picker.add_child(row)
	var back := _button("뒤로", UiKit.STEEL)
	back.pressed.connect(func():
		picking = ""
		refresh())
	var auto := _button("자동 편성", UiKit.STEEL)
	auto.pressed.connect(func():
		pick = Pvp.owned_heroes().slice(0, PvpRules.TEAM)
		_refresh_picker())
	_pick_ok = _button("확인")
	_pick_ok.pressed.connect(_confirm_pick)
	buttons["pick_ok"] = _pick_ok
	for b in [back, auto, _pick_ok]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)


func _open_picker(kind: String) -> void:
	picking = kind
	pick = (team.get(page, []) if kind == "team" else Pvp.defense(page)).duplicate()
	pick = pick.filter(func(id): return int(Economy.heroes.get(id, 0)) >= 1)
	if pick.is_empty():
		pick = Pvp.default_team(page)
	refresh()


func _confirm_pick() -> void:
	if pick.size() != PvpRules.TEAM:
		return
	if picking == "team":
		team[page] = pick.duplicate()
	else:
		Pvp.set_defense(page, pick.duplicate())
	picking = ""
	refresh()


func _refresh_picker() -> void:
	_pick_title.text = "%s %s" % [PvpRules.NAMES.get(page, ""), "출전 영웅" if picking == "team" else "방어팀"]
	var ids := Pvp.owned_heroes()
	if ids != _pick_cards.keys():
		for c in _pick_cards.values():
			_pick_grid.remove_child(c)
			c.queue_free()
		_pick_cards.clear()
		for id in ids:
			var card = HeroCardScript.new()
			card.custom_minimum_size = GRID_CARD
			card.hero_id = id
			card.tapped.connect(func(_c):
				if pick.has(id):
					pick.erase(id)
				elif pick.size() < PvpRules.TEAM:
					pick.append(id)
				_refresh_picker())
			_pick_grid.add_child(card)
			_pick_cards[id] = card
	for i in _pick_slots.size():
		var c = _pick_slots[i]
		c.hero_id = pick[i] if i < pick.size() else ""
		c.stars = Economy.promotion_of(pick[i]) if i < pick.size() else 0
		c.queue_redraw()
	for id in _pick_cards:
		var c = _pick_cards[id]
		c.stars = Economy.promotion_of(id)
		c.level = Economy.level_of(id)
		c.power = Pvp.hero_power(id)
		c.highlight = pick.has(id)
		c.queue_redraw()
	var ok := pick.size() == PvpRules.TEAM
	_pick_ok.disabled = not ok
	_pick_reason.text = "%d / %d명 · 전투력 %s" % [pick.size(), PvpRules.TEAM, UiKit.commas(Pvp.team_power(pick))]
	_pick_reason.add_theme_color_override("font_color", HudScript.INK if ok else RED)


# --- 갱신 ---

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 1.0
		if page != "" and picking == "":
			_p.plays.text = _plays_text(page)


func _plays_text(m: String) -> String:
	var left := Pvp.plays_left(m)
	var t := "오늘 남은 도전 %d / %d" % [left, PvpRules.PLAYS]
	var nr := float(Pvp.view.get("next_reset", 0.0))
	if nr > 0.0:
		t += " · 초기화 %s" % UiKit.clock(maxf(0.0, nr - Pvp.now_t()))
	return t


func refresh() -> void:
	if not is_inside_tree():
		return
	_home.visible = page == ""
	_page.visible = page != "" and picking == ""
	_picker.visible = page != "" and picking != ""
	if _coin_label != null:
		_coin_label.text = "PVP 코인 %s" % UiKit.commas(Pvp.coins())
	if page == "":
		for m in _cards:
			var c: Dictionary = _cards[m]
			var pts := Pvp.points(m)
			var t := PvpRules.tier_of(pts)
			c.tier.text = "%s · %s점" % [t.name, UiKit.commas(pts)]
			c.bar.value = _tier_progress(pts) * 100.0
			c.plays.text = "오늘 %d / %d" % [Pvp.plays_left(m), PvpRules.PLAYS]
			c.badge.queue_redraw()
		return
	if picking != "":
		_refresh_picker()
		return
	var mv := Pvp.mode_view(page)
	var pts := Pvp.points(page)
	var t := PvpRules.tier_of(pts)
	_p.title.text = PvpRules.NAMES[page]
	_p.tier.text = "%s · %s점" % [t.name, UiKit.commas(pts)]
	_p.bar.value = _tier_progress(pts) * 100.0
	_p.record.text = "%d승 %d패%s" % [int(mv.get("wins", 0)), int(mv.get("losses", 0)),
		"" if int(t.next) < 0 else " · 다음 등급까지 %s점" % UiKit.commas(int(t.next) - pts)]
	_p.plays.text = _plays_text(page)
	_p.badge.queue_redraw()
	var o := Pvp.opponent(page)
	if o.is_empty():
		_p.opp_name.text = "상대를 찾는 중"
		_p.opp_info.text = ""
		_fill_row(_p.opp_row, [])
	else:
		var ot := PvpRules.tier_of(int(o.get("points", 0)))
		_p.opp_name.text = "상대 · %s" % str(o.get("name", ""))
		var info := "%s %s점 · 전투력 %s" % [ot.name, UiKit.commas(int(o.get("points", 0))), UiKit.commas(int(o.get("power", 0)))]
		if page == "total":
			info += " · 병사 %d명" % PvpRules.soldier_count(o.get("soldiers", {}))
		_p.opp_info.text = info
		_fill_row(_p.opp_row, o.get("heroes", []))
	var tm: Array = team.get(page, [])
	tm = tm.filter(func(id): return int(Economy.heroes.get(id, 0)) >= 1)
	team[page] = tm
	_fill_row(_p.team_row, tm)
	var soldiers := Pvp.my_soldiers()
	_p.team_info.text = "전투력 %s%s" % [UiKit.commas(Pvp.team_power(tm)),
		(" · 병사 %d명 (보유 병사 중 높은 티어 %d명까지)" % [PvpRules.soldier_count(soldiers), PvpRules.SOLDIER_CAP]) if page == "total" else ""]
	var d := Pvp.defense(page)
	_fill_row(_p.def_row, d)
	if d.is_empty():
		_p.def_info.text = "아직 방어팀이 없어요 — 처음 출전한 팀이 방어팀이 됩니다"
	else:
		_p.def_info.text = "다른 성주가 이 팀과 싸워요 (상대 AI가 조종)%s" % \
			(" · 방어 병사 %d명" % PvpRules.soldier_count(mv.get("soldiers", {})) if page == "total" else "")
	var why := Pvp.start_block(page, tm)
	_p.start.disabled = why != ""
	_p.start.text = "전투 시작 (%d/%d)" % [Pvp.plays_left(page), PvpRules.PLAYS]
	_p.reason.text = why
	_p.reason.visible = why != ""


## 지금 등급 안에서 다음 등급까지 진행(0..1, 최고 등급은 1).
static func _tier_progress(pts: int) -> float:
	var t := PvpRules.tier_of(pts)
	if int(t.next) < 0:
		return 1.0
	return clampf(float(pts - int(t.min)) / float(int(t.next) - int(t.min)), 0.0, 1.0)


# --- 그림 ---

## 등급 배지: 등급 색 방패(로우폴리 면) + 위 보석(등급이 높을수록 면이 많다) + 아래 이름.
static func draw_badge(c: Control, tier_id: String) -> void:
	var col := PvpRules.tier_color(tier_id)
	var idx := 0
	var name := ""
	for i in PvpRules.TIERS.size():
		if PvpRules.TIERS[i][0] == tier_id:
			idx = i
			name = PvpRules.TIERS[i][1]
	var w := c.size.x
	var h := c.size.y - 30.0
	var cx := w / 2.0
	var top := 6.0
	var pts := PackedVector2Array([Vector2(cx - w * 0.38, top + h * 0.12), Vector2(cx, top), Vector2(cx + w * 0.38, top + h * 0.12),
		Vector2(cx + w * 0.34, top + h * 0.62), Vector2(cx, top + h * 0.95), Vector2(cx - w * 0.34, top + h * 0.62)])
	c.draw_colored_polygon(pts, col.darkened(0.25))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(Vector2(cx, top + h * 0.48) + (p - Vector2(cx, top + h * 0.48)) * 0.82)
	c.draw_colored_polygon(inner, col)
	c.draw_colored_polygon(PackedVector2Array([inner[0], inner[1], Vector2(cx, top + h * 0.48), inner[5]]), col.lightened(0.18))  # 밝은 면
	var ring := pts.duplicate()
	ring.append(pts[0])
	c.draw_polyline(ring, col.darkened(0.5), 2.5, true)
	UiKit.draw_gem(c, Vector2(cx, top + h * 0.46), w * 0.13, Color.WHITE.lerp(col, 0.35), 4 + idx)
	var font := ThemeDB.fallback_font
	var fs := 20
	var tw := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	c.draw_string(font, Vector2(cx - tw / 2.0, c.size.y - 6.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudScript.INK)


## PVP 코인: 은청색 동전 + 엇갈린 칼 둘.
static func draw_coin(c: Control) -> void:
	var s := minf(c.size.x, c.size.y)
	var o := c.size / 2.0
	var base := Color("7FA7D9")
	c.draw_circle(o, s * 0.48, base.darkened(0.45))
	c.draw_circle(o, s * 0.42, base)
	c.draw_circle(o + Vector2(-s * 0.06, -s * 0.06), s * 0.3, base.lightened(0.15))
	for sgn in [-1.0, 1.0]:
		var a := o + Vector2(-s * 0.22 * sgn, s * 0.22)
		var b := o + Vector2(s * 0.2 * sgn, -s * 0.2)
		c.draw_line(a, b, Color.WHITE, s * 0.08, true)
		var g := a.lerp(b, 0.25)
		var n := (b - a).normalized().orthogonal() * s * 0.1
		c.draw_line(g - n, g + n, Color("4A5C7A"), s * 0.07, true)


func _label(text: String, size: int, color: Color = HudScript.INK, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, color: Color = HudScript.ACCENT, font_size := 28) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 56)
	b.add_theme_font_size_override("font_size", font_size)
	UiKit.apply_button(b, color, 14.0)
	return b

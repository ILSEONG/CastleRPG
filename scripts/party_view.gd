extends VBoxContainer
## 던전 시트의 [파티] 탭 내용(dungeon_panel이 붙인다, 사용자 2026-10-15). 다른 성주와 함께 보스를 잡는 파티 퀘스트 둘.
## 맨 위: 안내 한 줄 + [자동 수락] 체크(켜 두면 매칭이 잡히는 즉시 입장 수락 — Party.auto_accept).
## 퀘스트 카드(리치의 무덤·거미 여왕의 둥지): 이름·인원·방식, 보상 장신구와 오늘 남은 보상, 난이도 4칸(못 깬 다음 난이도는 잠김),
## 고른 난이도의 장신구 등급 확률, 출전(리치 = 영웅 1명 ◀ ▶로 고르기, 거미 여왕 = 병사 4마리 — 높은 티어부터), [매칭 시작].
## 매칭 중이면 버튼이 "매칭 중"으로 꺼지고(대기 띠·입장 수락 창은 party_overlay.gd가 어느 화면에서든 띄운다), 막히면 빨간 이유 한 줄.

const Lang := preload("res://scripts/lang.gd")

const GameData := preload("res://scripts/game_data.gd")
const UiKit := preload("res://scripts/ui_kit.gd")
const HudScript := preload("res://scripts/hud.gd")
const PartyRules := preload("res://scripts/party_rules.gd")
const ItemTileScript := preload("res://scripts/item_tile.gd")

const RED := Color(0.78, 0.22, 0.18)
static var INFO := {"lich": Lang.t("party_view.info.lich"), "spider": Lang.t("party_view.info.spider")}
static var BLURB := {"lich": Lang.t("party_view.blurb.lich"),
	"spider": Lang.t("party_view.blurb.spider")}
static var REWARD := {"lich": Lang.t("party_view.reward.lich"), "spider": Lang.t("party_view.reward.spider")}

var diff := {}  # 퀘스트 → 고른 난이도
var hero_i := 0  # 리치 출전 영웅(owned_heroes 순번)
var buttons := {}  # 테스트용 "start:lich", "diff:lich:2", "auto" …
var auto_box: Button
var _cards := {}  # 퀘스트 → {diffs: [Button], odds, left, pick, reason, start}


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	add_child(top)
	var intro := _label(Lang.t("party_view.ready"), 22, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(intro)
	auto_box = UiKit.checkbox(Lang.t("party_view.ready_2"))
	auto_box.custom_minimum_size = Vector2(190, 64)
	auto_box.button_pressed = Party.auto_accept
	auto_box.toggled.connect(func(on): Party.set_auto_accept(on))
	top.add_child(auto_box)
	buttons["auto"] = auto_box
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 14)
	scroll.add_child(list)
	for q in PartyRules.QUESTS:
		diff[q] = Party.last_diff(q)
		list.add_child(_card(q))
	var owned: Array = Party.owned_heroes()
	hero_i = maxi(0, owned.find(Party.pick_hero()))
	Party.changed.connect(refresh)
	Economy.roster_changed.connect(refresh)
	Economy.changed.connect(refresh)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			Party.fetch()
			refresh())
	refresh()


func _card(q: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel(Color(1, 1, 1, 0.55), 14.0, 14))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	var tile = ItemTileScript.new()
	tile.custom_minimum_size = Vector2(84, 84)
	tile.set_item(PartyRules.ACCESSORY[q], "SSR")
	head.add_child(tile)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	names.add_child(_label(PartyRules.NAMES[q], 32, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	names.add_child(_label(INFO[q], 20, Color(0.35, 0.37, 0.42), HORIZONTAL_ALIGNMENT_LEFT))
	var left := _label("", 20, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	names.add_child(left)
	var blurb := _label(BLURB[q], 20, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(blurb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var diffs := []
	for d in range(1, PartyRules.DIFFS + 1):
		var b := _button(PartyRules.DIFF_NAMES[d - 1], UiKit.STEEL, 22)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 52)
		b.pressed.connect(_pick_diff.bind(q, d))
		row.add_child(b)
		diffs.append(b)
		buttons["diff:%s:%d" % [q, d]] = b
	var odds := _label("", 20, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(odds)
	var pick_row := HBoxContainer.new()
	pick_row.add_theme_constant_override("separation", 6)
	box.add_child(pick_row)
	var pick := _label("", 22, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if q == "lich":
		var prev := _button("◀", UiKit.STEEL, 24)
		prev.custom_minimum_size = Vector2(64, 52)
		prev.pressed.connect(_step_hero.bind(-1))
		pick_row.add_child(prev)
		pick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pick_row.add_child(pick)
		var next := _button("▶", UiKit.STEEL, 24)
		next.custom_minimum_size = Vector2(64, 52)
		next.pressed.connect(_step_hero.bind(1))
		pick_row.add_child(next)
		buttons["hero_next"] = next
	else:
		pick_row.add_child(pick)
	var reason := _label("", 20, RED)
	reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(reason)
	var start := _button(Lang.t("party_view.card"), HudScript.ACCENT, 28)
	start.pressed.connect(_start.bind(q))
	box.add_child(start)
	buttons["start:" + q] = start
	_cards[q] = {"diffs": diffs, "odds": odds, "left": left, "pick": pick, "reason": reason, "start": start}
	return panel


func _pick_diff(q: String, d: int) -> void:
	if not Party.unlocked(q, d):
		Economy.notice.emit(Lang.t("party_view.pick_diff") % PartyRules.DIFF_NAMES[d - 2])
		return
	diff[q] = d
	refresh()


func _step_hero(d: int) -> void:
	var owned: Array = Party.owned_heroes()
	if owned.is_empty():
		return
	hero_i = posmod(hero_i + d, owned.size())
	refresh()


func _hero() -> String:
	var owned: Array = Party.owned_heroes()
	return str(owned[clampi(hero_i, 0, owned.size() - 1)]) if not owned.is_empty() else ""


func _start(q: String) -> void:
	var soldiers: Array = Party.pick_soldiers() if q == "spider" else []
	var h := _hero() if q == "lich" else ""
	if not Party.start_queue(q, int(diff[q]), h, soldiers):
		var why := Party.queue_block(q, int(diff[q]), h, soldiers)
		if why != "":
			Economy.notice.emit(why)
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	if auto_box != null and auto_box.button_pressed != Party.auto_accept:
		auto_box.set_pressed_no_signal(Party.auto_accept)
		auto_box.queue_redraw()
	var st := Party.state()
	var busy_q := str(Party.queue().get("quest", ""))
	for q in _cards:
		var c: Dictionary = _cards[q]
		var d := int(diff[q])
		if not Party.unlocked(q, d):
			d = mini(Party.best(q) + 1, PartyRules.DIFFS)
			diff[q] = d
		for i in c.diffs.size():
			var b: Button = c.diffs[i]
			var lv: int = i + 1
			var open := Party.unlocked(q, lv)
			b.text = PartyRules.DIFF_NAMES[i] if open else Lang.t("party_view.refresh") % PartyRules.DIFF_NAMES[i]
			UiKit.apply_button(b, PartyRules.DIFF_COLORS[i] if lv == d else (UiKit.STEEL if open else UiKit.STEEL.darkened(0.3)), 12.0)
		var odds := PartyRules.drop_odds(d)
		var parts := []
		for g in odds:
			parts.append("%s %s%%" % [g, _pct(float(odds[g]))])
		c.odds.text = Lang.t("party_view.refresh_2") % [REWARD[q], " · ".join(parts)]
		c.left.text = Lang.t("party_view.refresh_3") % [REWARD[q], Party.clears_left(q), PartyRules.REWARD_CLEARS]
		var soldiers: Array = []
		if q == "lich":
			var h := _hero()
			var def := GameData.hero(h)
			c.pick.text = Lang.t("party_view.refresh_4") % [def.get("name", "-"), Economy.level_of(h)] if not def.is_empty() else Lang.t("party_view.refresh_5")
		else:
			soldiers = Party.pick_soldiers()
			var counts := {}
			for s in soldiers:
				var k := "%s T%d" % [GameData.soldier(str(s.type)).get("name", str(s.type)), int(s.tier)]
				counts[k] = int(counts.get(k, 0)) + 1
			var names := []
			for k in counts:
				names.append("%s ×%d" % [k, counts[k]])
			c.pick.text = Lang.t("party_view.refresh_6") % (", ".join(names) if not names.is_empty() else Lang.t("party_view.refresh_7"))
		var why := ""
		if st == "idle":
			why = Party.queue_block(q, d, _hero() if q == "lich" else "", soldiers)
		c.reason.text = why
		c.reason.visible = why != ""
		var start: Button = c.start
		if st != "idle" and busy_q == q:
			start.text = Lang.t("party_view.refresh_8")
			start.disabled = true
		else:
			start.text = Lang.t("party_view.refresh_9")
			start.disabled = st != "idle" or why != ""


static func _pct(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


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

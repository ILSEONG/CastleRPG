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
var panels := {}  # 퀘스트 → 카드(가이드 포커스 설명이 가리킨다)
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
	var join := _button(Lang.t("party_view.ready_3"), UiKit.STEEL, 22)
	join.custom_minimum_size = Vector2(150, 56)
	join.pressed.connect(_open_code)
	top.add_child(join)
	buttons["join_code"] = join
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
	panels[q] = panel
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
	# 파티(코드): 이 퀘스트 파티에 있으면 코드·파티원·빈자리
	var lobby_box := PanelContainer.new()
	lobby_box.add_theme_stylebox_override("panel", UiKit.panel(Color(0.93, 0.88, 0.74, 0.9), 10.0, 10))
	box.add_child(lobby_box)
	var lb := VBoxContainer.new()
	lb.add_theme_constant_override("separation", 4)
	lobby_box.add_child(lb)
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	lb.add_child(code_row)
	var code_label := _label("", 26, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(code_label)
	var copy := _button(Lang.t("party_view.card_2"), UiKit.STEEL, 20)
	copy.custom_minimum_size = Vector2(90, 44)
	copy.pressed.connect(_copy_code)
	code_row.add_child(copy)
	var inv := _button(Lang.t("party_view.card_4"), HudScript.ACCENT, 20)
	inv.custom_minimum_size = Vector2(90, 44)
	inv.pressed.connect(_open_invite)
	code_row.add_child(inv)
	buttons["invite:" + q] = inv
	var members := _label("", 20, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	members.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lb.add_child(members)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	box.add_child(row2)
	var party_b := _button(Lang.t("party_view.card_3"), UiKit.STEEL, 24)
	party_b.custom_minimum_size = Vector2(200, 56)
	party_b.pressed.connect(_party_button.bind(q))
	row2.add_child(party_b)
	buttons["party:" + q] = party_b
	var start := _button(Lang.t("party_view.card"), HudScript.ACCENT, 28)
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.pressed.connect(_start.bind(q))
	row2.add_child(start)
	buttons["start:" + q] = start
	_cards[q] = {"diffs": diffs, "odds": odds, "left": left, "pick": pick, "row": pick_row, "reason": reason, "start": start,
		"lobby": lobby_box, "code": code_label, "copy": copy, "invite": inv, "members": members, "party": party_b}
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
	if _my_lobby("lich"):
		Party.update_lobby_pick(_hero())


func _hero() -> String:
	var owned: Array = Party.owned_heroes()
	return str(owned[clampi(hero_i, 0, owned.size() - 1)]) if not owned.is_empty() else ""


func _start(q: String) -> void:
	var soldiers: Array = Party.pick_soldiers() if q == "spider" else []
	var h := _hero() if q == "lich" else ""
	if _my_lobby(q):  # 파티 방장: 파티원과 함께 매칭
		var w := Party.start_lobby(int(diff[q]))
		if w != "":
			Economy.notice.emit(w)
		refresh()
		return
	if not Party.start_queue(q, int(diff[q]), h, soldiers):
		var why := Party.queue_block(q, int(diff[q]), h, soldiers)
		if why != "":
			Economy.notice.emit(why)
	refresh()


func _my_lobby(q: String) -> bool:
	return Party.in_lobby() and str(Party.lobby().get("quest", "")) == q


## [파티 만들기] · 파티 안이면 [파티 나가기].
var _party_ms := -100000


func _party_button(q: String) -> void:
	if Time.get_ticks_msec() - _party_ms < 500:  # 빠른 두 번 탭: 만들자마자 나가지 않게
		return
	_party_ms = Time.get_ticks_msec()
	if _my_lobby(q):
		Party.leave_lobby()
	else:
		var w := Party.create_lobby(q, int(diff[q]), _hero() if q == "lich" else "", Party.pick_soldiers() if q == "spider" else [])
		if w != "":
			Economy.notice.emit(w)
	refresh()


func _copy_code() -> void:
	var code := str(Party.lobby().get("code", ""))
	if code != "":
		DisplayServer.clipboard_set(code)
		Economy.notice.emit(Lang.t("party_view.copy_code"))


var code_panel  # party_code_panel.gd(처음 누를 때 만든다)
var invite_panel  # party_invite_panel.gd(처음 누를 때 만든다)


func _open_invite() -> void:
	if not Party.online():
		Economy.notice.emit(Lang.t("party_view.open_invite"))
		return
	if invite_panel == null:
		invite_panel = preload("res://scripts/party_invite_panel.gd").new()
		get_tree().root.add_child(invite_panel)
	invite_panel.open()


func _open_code() -> void:
	if code_panel == null:
		code_panel = preload("res://scripts/party_code_panel.gd").new()
		get_tree().root.add_child(code_panel)
	code_panel.open()


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
			b.disabled = _my_lobby(q) and not Party.lobby_leader()  # 파티원: 난이도는 방장이 정한다
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
			why = Party.queue_block(q, d, _hero() if q == "lich" else "", soldiers, _my_lobby(q))
		c.reason.text = why
		c.reason.visible = why != ""
		var mine := _my_lobby(q)
		var leader := mine and Party.lobby_leader()
		if mine and not leader and st == "idle":
			why = ""
		c.reason.text = why
		c.reason.visible = why != ""
		var start: Button = c.start
		if st != "idle" and busy_q == q:
			start.text = Lang.t("party_view.refresh_8")
			start.disabled = true
		elif mine and not leader:
			start.text = Lang.t("party_view.refresh_10")
			start.disabled = true
		else:
			start.text = Lang.t("party_view.refresh_11") if leader else Lang.t("party_view.refresh_9")
			start.disabled = st != "idle" or why != ""
		# 파티(코드)
		var pb: Button = c.party
		pb.text = Lang.t("party_view.refresh_12") if mine else Lang.t("party_view.refresh_13")
		pb.disabled = (not mine and (st != "idle" or (Party.in_lobby() and not mine))) or (mine and st == "confirm")
		c.lobby.visible = mine
		if mine:
			var l := Party.lobby()
			var code := str(l.get("code", ""))
			c.code.text = Lang.t("party_view.refresh_14") % (code if code != "" else "······")
			c.copy.disabled = code == ""
			c.invite.disabled = code == "" or st != "idle" or l.get("members", []).size() >= int(l.get("size", 4))
			var lines := []
			for m in l.get("members", []):
				var who := str(m.get("name", ""))
				if m.get("me", false) and who != Lang.t("party_view.refresh_15"):
					who += Lang.t("party_view.refresh_16")
				if m.get("leader", false):
					who += Lang.t("party_view.refresh_17")
				var what := ""
				var h = m.get("hero")
				if h is Dictionary:
					what = "%s Lv %d" % [GameData.hero(str(h.get("hero", ""))).get("name", "?"), int(h.get("level", 1))]
				var so = m.get("soldiers")
				if so is Array and not so.is_empty():
					var top := 0
					for x in so:
						top = maxi(top, int(x.get("tier", 1)))
					what = Lang.t("party_view.refresh_18") % [so.size(), top]
				lines.append("%s  —  %s" % [who, what] if what != "" else who)
			var empty: int = int(l.get("size", PartyRules.SEATS[q])) - (l.get("members", []) as Array).size()
			if empty > 0:
				lines.append(Lang.t("party_view.refresh_19") % [empty, int(PartyRules.BOT_WAIT_SEC)])
			if not leader:
				lines.append(Lang.t("party_view.refresh_20"))
			c.members.text = "\n".join(lines)


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

extends RefCounted
## 길드 창 [길드전] 하위 탭 내용(guild_panel.gd가 build(창)을 부른다 — 창의 _card·_label·_button을 쓴다). 값은 GuildWar.war.
## 위에서부터: 이번 주 상대(문장·이름·전투력)와 점수(우리 : 상대), 상대 성(성문 4개·성채 체력 막대, 수비 영웅 처치 수),
## 이번 주 공성전(공성 시각 — 길드원이 요일·시를 고른다, 상태·남은 시간) + [공격 분대][수비 분대] 고르기 + 영웅 격자(보유 영웅, 전투력 순, 4명) + [공성 시작/전투 합류] 또는 [수비 영웅 저장],
## 지난 주 보상([보상 받기]), 규칙 한 장.

const WarRules := preload("res://scripts/war_rules.gd")
const GameData := preload("res://scripts/game_data.gd")
const UiKit := preload("res://scripts/ui_kit.gd")
const MainHud := preload("res://scripts/hud.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")

const SUB := Color(0.16, 0.18, 0.24, 0.62)
const RED := Color(0.80, 0.26, 0.22)
const GREEN := Color(0.13, 0.50, 0.22)
const BLUE := Color(0.22, 0.42, 0.78)


static func build(p) -> void:
	if not GuildWar.changed.is_connected(p._on_changed):
		GuildWar.changed.connect(p._on_changed)
	GuildWar.fetch_if_stale()
	var w: Dictionary = GuildWar.war
	if w.is_empty():
		var c = p._card()
		c.get_child(0).add_child(p._label("길드전 정보를 불러오는 중입니다", 24, SUB))
		p.body.add_child(c)
		return
	var sel := _sel(p)
	_enemy_card(p, w)
	_castle_card(p, w)
	_battle_card(p, w, sel)
	if w.get("claim") is Dictionary:
		_claim_card(p, w.claim)
	_rules_card(p)


## 고르는 중인 분대(창에 둔다): {mode, attack [], defense []}.
static func _sel(p) -> Dictionary:
	if not p.has_meta("war_sel"):
		var d: Array = GuildWar.defense()
		p.set_meta("war_sel", {"mode": "attack", "attack": GuildWar.default_squad(), "defense": d.duplicate() if d.size() == WarRules.SQUAD else GuildWar.default_squad()})
	return p.get_meta("war_sel")


static func _enemy_card(p, w: Dictionary) -> void:
	var c = p._card()
	var v: VBoxContainer = c.get_child(0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(p._emblem_box(int(w.enemy.emblem), 84))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(p._label("이번 주 상대  %s" % w.enemy.name, 28, MainHud.INK, HORIZONTAL_ALIGNMENT_LEFT))
	info.add_child(p._label("길드원 %d명 · 전투력 %s" % [int(w.enemy.members), UiKit.commas(int(w.enemy.power))], 20, SUB, HORIZONTAL_ALIGNMENT_LEFT))
	row.add_child(info)
	v.add_child(row)
	var score := HBoxContainer.new()
	score.alignment = BoxContainer.ALIGNMENT_CENTER
	score.add_theme_constant_override("separation", 18)
	score.add_child(p._label("우리 %d" % int(w.points), 40, BLUE))
	score.add_child(p._label(":", 40, SUB))
	score.add_child(p._label("%d 상대" % int(w.enemy_points), 40, RED))
	v.add_child(score)
	var left := maxf(0.0, float(w.get("week_ends", 0.0)) - GuildWar.now_t())
	v.add_child(p._label("주간 결산까지 %s · 상대 점수는 우리 공성 시간이 끝나면 나옵니다" % UiKit.duration(left), 19, SUB))
	p.body.add_child(c)


static func _castle_card(p, w: Dictionary) -> void:
	var c = p._card()
	var v: VBoxContainer = c.get_child(0)
	var cs: Dictionary = w.castle
	v.add_child(p._label("상대 성 · 수비 영웅 처치 %d / %d" % [int(cs.kills), int(cs.defenders)], 24, MainHud.INK, HORIZONTAL_ALIGNMENT_LEFT))
	for i in 4:
		v.add_child(_bar_row(p, WarRules.SIDE_NAMES[i], float(cs.gates[i].hp), float(cs.gates[i].max), UiKit.AMBER))
	v.add_child(_bar_row(p, "성채", float(cs.keep.hp), float(cs.keep.max), RED))
	p.body.add_child(c)


static func _bar_row(p, name_s: String, hp: float, mx: float, color: Color) -> Control:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	var l = p._label(name_s, 21, MainHud.INK, HORIZONTAL_ALIGNMENT_LEFT)
	l.custom_minimum_size = Vector2(70, 0)
	r.add_child(l)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 26)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = maxf(1.0, mx)
	bar.value = maxf(0.0, hp)
	UiKit.apply_bar(bar, color)
	var t = p._label("파괴" if hp <= 0.0 else "%s / %s" % [UiKit.commas(int(hp)), UiKit.commas(int(mx))], 17, Color.WHITE)
	t.add_theme_color_override("font_outline_color", Color(MainHud.INK, 0.85))
	t.add_theme_constant_override("outline_size", 5)
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(t)
	r.add_child(bar)
	return r


static func _battle_card(p, w: Dictionary, sel: Dictionary) -> void:
	var c = p._card()
	var v: VBoxContainer = c.get_child(0)
	var b: Dictionary = w.get("battle", {})
	var state := str(b.get("state", "ready"))
	var sch: Dictionary = w.get("schedule", {})
	var at := float(sch.get("at", 0.0))
	var head := ""
	match state:
		"live":
			var left := maxf(0.0, float(b.get("ends_at", 0.0)) - GuildWar.now_t())
			head = "공성전 진행 중 · 남은 시간 %s" % UiKit.clock(left)
			if b.has("joined"):
				head += " · 참가 %d명" % int(b.joined)
		"done":
			head = "이번 주 공성전은 끝났습니다 · 다음 주에 다시"
		_:
			head = "이번 주 공성 %s · %s 뒤 %d분 동안 열립니다" % [GuildWar.at_text(at), UiKit.duration(maxf(0.0, at - GuildWar.now_t())),
				roundi(WarRules.BATTLE_SEC / 60.0)]
	v.add_child(p._label(head, 22, MainHud.INK))
	if state != "live" and GuildWar.online() and Economy.admin:  # 슈퍼관리자: 시각을 기다리지 않고 바로(끝났으면 새 성으로 다시)
		v.add_child(p._label("관리자: [공성 시작]으로 지금 바로 열 수 있어요", 18, SUB))
	var who := ("%s님이 정한 시각" % str(sch.by)) if sch.get("set", false) and str(sch.get("by", "")) != "" else "길드원이 정하지 않으면 토요일 21:00"
	v.add_child(p._label(who, 18, SUB))
	if sch.get("can_change", false):
		_schedule_picker(p, v, at)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	for m in [["attack", "공격 분대"], ["defense", "수비 분대"]]:
		var mb = p._button(m[1], UiKit.AMBER if sel.mode == m[0] else UiKit.STEEL, 24)
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mb.pressed.connect(func():
			sel.mode = m[0]
			p._rebuild())
		modes.add_child(mb)
		p.buttons["war_mode:" + m[0]] = mb
	v.add_child(modes)
	var picked: Array = sel[sel.mode]
	v.add_child(p._label(("직접 조종할 영웅 4명을 고르세요" if sel.mode == "attack" else "우리 성을 지킬 영웅 4명(수비 AI)을 고르세요") + "  %d/%d" % [picked.size(), WarRules.SQUAD], 19, SUB))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for id in GuildWar.owned_heroes():
		grid.add_child(_tile(p, str(id), picked))
	v.add_child(grid)
	var act
	if sel.mode == "attack":
		var why := GuildWar.enter_block(picked)
		act = p._button("전투 합류" if state == "live" else "공성 시작", UiKit.AMBER, 30)
		act.disabled = why != ""
		act.pressed.connect(func(): GuildWar.enter(picked.duplicate()))
		if why != "" and not GuildWar.busy:
			v.add_child(p._label(why, 19, RED))
	else:
		var same: bool = picked == GuildWar.defense()
		act = p._button("저장됨" if same else "수비 영웅 저장", UiKit.AMBER, 30)
		act.disabled = same or picked.size() != WarRules.SQUAD or GuildWar.busy
		act.pressed.connect(func(): GuildWar.set_defense(picked.duplicate()))
	act.custom_minimum_size = Vector2(0, 72)
	v.add_child(act)
	p.buttons["war_act"] = act
	p.body.add_child(c)


## 공성 시각 고르기: 요일 7칸 + [−] 시 [+] + [시각 정하기]. 고르는 값은 창에 둔다(war_at).
static func _schedule_picker(p, v: VBoxContainer, at: float) -> void:
	if not p.has_meta("war_at"):
		var d := GameData.reset_day(at)
		p.set_meta("war_at", {"day": GuildWar.day_in_week(d), "hour": roundi((at - GameData.reset_at(d)) / 3600.0)})
	var pick: Dictionary = p.get_meta("war_at")
	var days := HBoxContainer.new()
	days.add_theme_constant_override("separation", 4)
	for i in 7:
		var db = p._button(WarRules.DAY_NAMES[i], UiKit.AMBER if int(pick.day) == i else UiKit.STEEL, 20)
		db.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		db.custom_minimum_size = Vector2(0, 50)
		db.pressed.connect(func():
			pick.day = i
			p._rebuild())
		days.add_child(db)
		p.buttons["war_day:%d" % i] = db
	v.add_child(days)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	for step in [-1, 1]:
		var hb = p._button("−" if step < 0 else "+", UiKit.STEEL, 26)
		hb.custom_minimum_size = Vector2(64, 54)
		hb.pressed.connect(func():
			pick.hour = posmod(int(pick.hour) + step, 24)
			p._rebuild())
		p.buttons["war_hour:%d" % step] = hb
		if step < 0:
			row.add_child(hb)
			row.add_child(p._label("%s요일 %02d:00" % [WarRules.DAY_NAMES[int(pick.day)], int(pick.hour)], 26, MainHud.INK))
		else:
			row.add_child(hb)
	var why := GuildWar.schedule_block(int(pick.day), int(pick.hour))
	var same := absf(GuildWar.pick_at(int(GuildWar.war.get("week", 0)), int(pick.day), int(pick.hour)) - at) < 1.0
	var sb = p._button("시각 정하기", UiKit.AMBER, 22)
	sb.custom_minimum_size = Vector2(170, 54)
	sb.disabled = why != "" or same
	sb.pressed.connect(func():
		if GuildWar.set_schedule(int(pick.day), int(pick.hour)):
			p.remove_meta("war_at"))
	row.add_child(sb)
	p.buttons["war_schedule"] = sb
	v.add_child(row)
	if why != "" and not same and not GuildWar.busy:
		v.add_child(p._label(why, 18, RED))


static func _tile(p, id: String, picked: Array) -> Control:
	var def := GameData.hero(id)
	var on := picked.has(id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(128, 150)
	UiKit.apply_button(b, UiKit.AMBER if on else Color(1, 1, 1, 0.9), 10.0)
	b.pressed.connect(func():
		if on:
			picked.erase(id)
		elif picked.size() < WarRules.SQUAD:
			picked.append(id)
		p._rebuild())
	var face := Control.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.position = Vector2(22, 6)
	face.size = Vector2(84, 84)
	face.draw.connect(func():
		var r := Rect2(Vector2.ZERO, face.size)
		var oct := LowpolyBox.octagon(r.grow(-2.0), r.size.x * 0.2)
		face.draw_colored_polygon(oct, UiKit.GRADE_COLORS.get(def.grade, UiKit.STEEL).lightened(0.3))
		face.draw_texture_rect(PortraitsScript.portrait("hero:" + id), r, false))
	b.add_child(face)
	var n = p._label(str(def.get("name", id)), 19, MainHud.INK)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.position = Vector2(0, 92)
	n.size = Vector2(128, 26)
	b.add_child(n)
	var pw = p._label(UiKit.commas(GuildWar.hero_power(id)), 16, SUB)
	pw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pw.position = Vector2(0, 118)
	pw.size = Vector2(128, 24)
	b.add_child(pw)
	if on:
		var k = p._label(str(picked.find(id) + 1), 22, Color.WHITE)
		k.add_theme_color_override("font_outline_color", Color(MainHud.INK, 0.9))
		k.add_theme_constant_override("outline_size", 6)
		k.mouse_filter = Control.MOUSE_FILTER_IGNORE
		k.position = Vector2(6, 2)
		b.add_child(k)
	p.buttons["war_hero:" + id] = b
	return b


static func _claim_card(p, cl: Dictionary) -> void:
	var c = p._card(Color(1.0, 0.97, 0.85, 0.9))
	var v: VBoxContainer = c.get_child(0)
	v.add_child(p._label("지난 주 길드전 %s  %d : %d" % ["승리!" if cl.win else "패배", int(cl.points), int(cl.enemy_points)], 26, GREEN if cl.win else RED))
	var rw: Dictionary = cl.reward
	var b = p._button("보상 받기  길드 코인 %d · 다이아 %d" % [int(rw.coins), int(rw.diamonds)], UiKit.AMBER, 24)
	b.disabled = GuildWar.busy
	b.pressed.connect(func(): GuildWar.claim())
	v.add_child(b)
	p.buttons["war_claim"] = b
	p.body.add_child(c)


static func _rules_card(p) -> void:
	var c = p._card()
	var v: VBoxContainer = c.get_child(0)
	v.add_child(p._label("공성전 규칙", 24, MainHud.INK, HORIZONTAL_ALIGNMENT_LEFT))
	for t in ["길드원 모두가 한 전투에 함께 들어가 각자 영웅 4명을 직접 조종합니다. 자리에 없는 길드원 분대는 자동으로 진격합니다.",
			"공성전은 한 주에 한 번, 길드원이 정한 시각에 %d분 동안 열립니다. 아무도 정하지 않으면 토요일 21:00입니다." % roundi(WarRules.BATTLE_SEC / 60.0),
			"상대 성은 상대 길드원이 고른 수비 영웅이 지킵니다.",
			"점수: 수비 영웅 처치 %d점 · 성문 파괴 %d점 · 성채 최대 체력의 %d%%를 깎을 때마다 1점" % [WarRules.PTS_KILL, WarRules.PTS_GATE, roundi(WarRules.KEEP_STEP * 100.0)],
			"공격 영웅은 쓰러지면 %d초 뒤 진영에서 다시 일어납니다(목숨 %d개). 모두 목숨을 다 쓰면 전투가 끝납니다." % [roundi(WarRules.RESPAWN_SEC), WarRules.ATTACK_LIVES],
			"수비 영웅은 성벽 앞에서 싸워 체력 ×%s · 공격력 ×%s 수성 보너스를 받습니다." % [str(WarRules.DEF_HP_MULT), str(WarRules.DEF_ATK_MULT)],
			"주간 보상: 승리 길드 코인 %d · 다이아 %d / 패배 길드 코인 %d · 다이아 %d" % [WarRules.REWARD_WIN.coins, WarRules.REWARD_WIN.diamonds,
				WarRules.REWARD_LOSE.coins, WarRules.REWARD_LOSE.diamonds]]:
		var l = p._label("· " + t, 18, SUB, HORIZONTAL_ALIGNMENT_LEFT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	p.body.add_child(c)

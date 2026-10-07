extends "res://scripts/ui_window.gd"
## [길드] 탭 시트. 상태(Guild 오토로드)에 따라 화면이 셋이다:
## - 잠김: 1-10 라운드 클리어 안내(온라인이면 "온라인 길드는 준비 중").
## - 미가입: 추천 길드 5개(문장·이름·Lv·인원·공지·[가입]) + [새로고침] + 창설(이름 입력·문장 고르기·[창설 골드 500,000]).
## - 가입: 머리(문장·이름·Lv·경험치 막대·길드 코인) + 버프 한 줄 + 하위 탭 [홈][보스][상점][길드원].
##   홈 = 공지·출석(출석 인원 막대 + 5/10/15/20명 상자)·기부 3종·활동 기록·[길드 탈퇴](두 번 눌러 확인).
##   보스 = 드래곤(Meshy 모델 미리보기)·길드 누적 HP 막대·남은 도전·[도전] → 실제 전투 장면(guild_boss.gd: 영웅이 40초 동안 드래곤과 싸운다) → 결과(등급·보상).
##   길드전 = 공성전(war_panel.gd, 상태는 GuildWar 오토로드).
##   상점 = 길드 코인 상품(일일·주간 한도). 길드원 = 오늘 기여도 순(나 포함): 직위·이름·전투력·출석·마지막 활동.
## 내용은 Guild.changed 때 다시 만든다(스크롤 위치는 지킨다).

const GuildScript := preload("res://scripts/guild.gd")
const GameData := preload("res://scripts/game_data.gd")
const IconsScript := preload("res://scripts/icons.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const DragonModelScript := preload("res://scripts/dragon_model.gd")
const WarPanel := preload("res://scripts/war_panel.gd")

const SUBTABS := [["home", "홈"], ["boss", "보스"], ["war", "길드전"], ["shop", "상점"], ["members", "길드원"]]
const EMBLEM_COLORS := [Color(0.80, 0.22, 0.20), Color(0.22, 0.42, 0.78), Color(0.24, 0.60, 0.32), Color(0.56, 0.30, 0.70),
	Color(0.92, 0.62, 0.16), Color(0.18, 0.55, 0.60), Color(0.35, 0.36, 0.42), Color(0.86, 0.40, 0.58)]
const GREEN := Color(0.13, 0.50, 0.22)
const RED := Color(0.80, 0.26, 0.22)
const COIN_COLOR := Color(0.52, 0.40, 0.78)
const SUB := Color(0.16, 0.18, 0.24, 0.62)
const LEAVE_CONFIRM_SEC := 3.0
const GRADE_COLORS := {"SSS": Color(0.92, 0.22, 0.25), "SS": Color(0.98, 0.45, 0.10), "S": Color(0.95, 0.62, 0.10), "A": Color(0.80, 0.30, 0.70), "B": Color(0.25, 0.50, 0.85)}


## 판 등급 색: + · −를 뗀 글자(SSS·SS·S·A·B)로.
static func grade_color(g: String) -> Color:
	return GRADE_COLORS.get(g.trim_suffix("+").trim_suffix("-"), Color(0.5, 0.5, 0.55))

var tab := "home"
var body: VBoxContainer  # 다시 만드는 내용
var scroll: ScrollContainer
var name_edit: LineEdit
var emblem_pick := 0
var buttons := {}  # 테스트·연출용: "attend", "donate:gold", "boss", "buy:dia", "join:0", "create", "leave", "tab:boss", "box:0" …

var _dirty := false
var _leave_armed := 0.0
var _create_name := ""
var _refetch := 0.0
var _dragon_box: SubViewportContainer  # 보스 탭 드래곤 미리보기 — 다시 만들기(골드가 오를 때마다 등) 사이에도 같은 것을 써서 대기 동작이 처음으로 튀지 않는다

const REFETCH_SEC := 30.0  # 온라인: 창이 열려 있는 동안 이 간격으로 길드 값을 다시 받는다


func _ready() -> void:
	_build_window(0, 10)
	dialog.get_parent().color = Color(0, 0, 0, 0)  # 시트가 화면을 채운다
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_title("길드"))
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	_fit_sheet()
	Guild.changed.connect(_on_changed)
	Economy.changed.connect(_on_econ_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_dragon_box) and _dragon_box.get_parent() == null:
		_dragon_box.free()


func _fit() -> void:
	_fit_sheet()


func _on_open() -> void:
	Guild.check_unlock()
	if Guild.online():
		Guild.fetch()  # 온라인: 길드원 활동·출석 인원을 새로 받는다
		_refetch = REFETCH_SEC
	elif Guild.joined():
		Guild.tick(Guild.now_t())
	_rebuild()


func _on_changed() -> void:
	if visible:
		_dirty = true


func _on_econ_changed() -> void:
	if visible and tab != "members":  # 골드·다이아로 버튼 활성이 바뀐다
		_dirty = true


func _process(delta: float) -> void:
	if not visible:
		return
	if Guild.online():
		_refetch -= delta
		if _refetch <= 0.0:
			_refetch = REFETCH_SEC
			Guild.fetch()
	if _leave_armed > 0.0:
		_leave_armed -= delta
		if _leave_armed <= 0.0:
			_dirty = true
	if _dirty:
		_dirty = false
		_rebuild()


# --- 다시 만들기 ---

func _rebuild() -> void:
	var keep := scroll.scroll_vertical
	if name_edit != null and is_instance_valid(name_edit):
		_create_name = name_edit.text
	buttons.clear()
	name_edit = null
	if is_instance_valid(_dragon_box) and _dragon_box.get_parent() != null:
		_dragon_box.get_parent().remove_child(_dragon_box)
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	if Guild.online() and Guild.remote.is_empty():
		_center_note("길드 정보를 불러오는 중입니다", "서버에 연결되면 바로 보여요")
	elif not Guild.is_unlocked():
		_center_note("1-10 라운드를 클리어하면 길드가 열립니다", "길드에 가입하면 출석·기부 보상, 길드 버프, 길드 보스가 열려요")
	elif not Guild.joined():
		_build_join()
	else:
		_build_joined()
	scroll.set_deferred("scroll_vertical", keep)


func _center_note(head: String, sub: String) -> void:
	var box := _card()
	var v := box.get_child(0)
	var lock := Control.new()
	lock.custom_minimum_size = Vector2(0, 140)
	lock.draw.connect(func(): draw_emblem(lock, lock.size / 2.0, 120.0, 6))
	v.add_child(lock)
	var h := _label(head, 28)
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(h)
	var s := _label(sub, 22, SUB)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(s)
	body.add_child(box)


# --- 미가입 ---

func _build_join() -> void:
	var intro := _label("길드에 가입하면 매일 출석·기부 보상과 영웅 능력치 버프, 길드 보스에 도전할 수 있어요.", 22, SUB)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(intro)
	body.add_child(_coin_line())
	var head := HBoxContainer.new()
	var t := _label("추천 길드", 30, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var refresh := _button("새로고침", UiKit.STEEL, 22)
	refresh.custom_minimum_size = Vector2(130, 48)
	refresh.pressed.connect(Guild.refresh_recommendations)
	head.add_child(refresh)
	body.add_child(head)
	var recs := Guild.recommendations()
	for i in recs.size():
		body.add_child(_rec_row(recs[i], i))
	body.add_child(_create_card())


func _rec_row(rec: Dictionary, i: int) -> Control:
	var card := _card()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.get_child(0).add_child(row)
	row.add_child(_emblem_box(int(rec.emblem), 76))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	info.add_child(_label(rec.name, 28, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	info.add_child(_label("Lv %d · 길드원 %d/%d · 평균 전투력 %s" % [rec.level, rec.count, int(rec.get("capacity", GuildScript.capacity(int(rec.level)))), UiKit.commas(rec.power)], 20, SUB, HORIZONTAL_ALIGNMENT_LEFT))
	var n := _label(rec.notice, 20, GREEN, HORIZONTAL_ALIGNMENT_LEFT)
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.clip_text = true
	info.add_child(n)
	row.add_child(info)
	var b := _button("가입", UiKit.AMBER, 24)
	b.custom_minimum_size = Vector2(104, 64)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func():
		if Guild.join(rec):
			tab = "home"
			Economy.notice.emit("%s에 가입했습니다!" % rec.name))
	row.add_child(b)
	buttons["join:%d" % i] = b
	return card


func _create_card() -> Control:
	var card := _card()
	var v: VBoxContainer = card.get_child(0)
	v.add_child(_label("길드 창설", 28, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	var s := _label("직접 길드를 만들면 길드장이 됩니다. 가입 신청한 길드원이 시간이 지나며 들어와요.", 20, SUB, HORIZONTAL_ALIGNMENT_LEFT)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(s)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "길드 이름(2~8글자)"
	name_edit.max_length = 8
	name_edit.text = _create_name
	name_edit.custom_minimum_size = Vector2(0, 56)
	name_edit.add_theme_font_size_override("font_size", 26)
	name_edit.text_changed.connect(func(_t): _refresh_create())
	v.add_child(name_edit)
	var picks := HBoxContainer.new()
	picks.alignment = BoxContainer.ALIGNMENT_CENTER
	picks.add_theme_constant_override("separation", 6)
	for i in GuildScript.EMBLEMS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(70, 70)
		b.focus_mode = Control.FOCUS_NONE
		UiKit.apply_button(b, UiKit.AMBER if i == emblem_pick else Color(1, 1, 1, 0.6), 10.0)
		var face := Control.new()
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.draw.connect(func(): draw_emblem(face, face.size / 2.0, 52.0, i))
		b.add_child(face)
		b.pressed.connect(func():
			emblem_pick = i
			_dirty = true)
		picks.add_child(b)
	v.add_child(picks)
	var c := _button("창설  골드 %s" % UiKit.commas(GuildScript.CREATE_GOLD), UiKit.AMBER, 26)
	c.pressed.connect(func():
		var n := name_edit.text
		if Guild.create(n, emblem_pick):
			_create_name = ""
			tab = "home"
			Economy.notice.emit("길드 「%s」를 창설했습니다!" % n.strip_edges())
		else:
			Economy.notice.emit(Guild.create_block(n)))
	v.add_child(c)
	buttons["create"] = c
	_refresh_create()
	return card


func _refresh_create() -> void:
	if buttons.has("create") and name_edit != null:
		var why := Guild.create_block(name_edit.text)
		buttons.create.disabled = why != "" and why != "길드 이름은 2~8글자입니다"  # 이름은 눌렀을 때 알려 준다


# --- 가입 ---

func _build_joined() -> void:
	var g: Dictionary = Guild.guild
	var head := _card()
	var hv: VBoxContainer = head.get_child(0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	hv.add_child(row)
	row.add_child(_emblem_box(int(g.emblem), 96))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	info.add_child(_label(g.name, 32, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	info.add_child(_label("Lv %d · 길드원 %d/%d" % [g.level, Guild.members_now().size() + 1, int(g.get("capacity", GuildScript.capacity(int(g.level))))], 22, SUB, HORIZONTAL_ALIGNMENT_LEFT))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 26)
	bar.show_percentage = false
	UiKit.apply_bar(bar, UiKit.AMBER)
	var need := GuildScript.exp_need(int(g.level))
	bar.max_value = need
	bar.value = int(g.exp)
	var bl := _label("%s / %s" % [UiKit.commas(int(g.exp)), UiKit.commas(need)], 18, HudScript.INK)
	bl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(bl)
	info.add_child(bar)
	row.add_child(info)
	hv.add_child(_label("길드 버프  영웅 공격력 +%d%% · 체력 +%d%%" % [roundi(Guild.buff_pct()), roundi(Guild.buff_pct())], 24, GREEN))
	body.add_child(head)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	for t in SUBTABS:
		var b := _button(t[1], UiKit.AMBER if tab == t[0] else UiKit.STEEL, 24)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 54)
		b.pressed.connect(func():
			tab = t[0]
			scroll.scroll_vertical = 0
			_rebuild())
		tabs.add_child(b)
		buttons["tab:" + t[0]] = b
	body.add_child(tabs)
	match tab:
		"boss":
			_build_boss()
		"war":
			WarPanel.build(self)  # 길드전(공성전) — war_panel.gd
		"shop":
			_build_shop()
		"members":
			_build_members()
		_:
			_build_home()


func _build_home() -> void:
	var g: Dictionary = Guild.guild
	var note := _card()
	var nv: VBoxContainer = note.get_child(0)
	nv.add_child(_label("공지", 24, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	var nt := _label(g.notice, 22, SUB, HORIZONTAL_ALIGNMENT_LEFT)
	nt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nv.add_child(nt)
	body.add_child(note)
	# 출석
	var att := _card()
	var av: VBoxContainer = att.get_child(0)
	var ar := HBoxContainer.new()
	var at := VBoxContainer.new()
	at.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	at.add_child(_label("길드 출석", 28, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	at.add_child(_label("골드 +%s · 길드 코인 +%d · 경험치 +%d" % [UiKit.commas(GuildScript.ATTEND_REWARD.gold), GuildScript.ATTEND_REWARD.coins,
		GuildScript.ATTEND_EXP], 20, SUB, HORIZONTAL_ALIGNMENT_LEFT))
	ar.add_child(at)
	var done: bool = Guild.me.get("attended", false)
	var ab := _button("출석 완료" if done else "출석하기", UiKit.STEEL if done else UiKit.AMBER, 24)
	ab.custom_minimum_size = Vector2(150, 64)
	ab.disabled = done
	ab.pressed.connect(func(): Guild.attend())
	ar.add_child(ab)
	buttons["attend"] = ab
	av.add_child(ar)
	var cnt := Guild.attend_count()
	var top: int = GuildScript.ATTEND_BOXES[-1][0]
	av.add_child(_label("오늘 출석 인원 %d명" % cnt, 22, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(0, 18)
	pb.show_percentage = false
	pb.max_value = top
	pb.value = mini(cnt, top)
	UiKit.apply_bar(pb, GREEN.lightened(0.2))
	av.add_child(pb)
	var boxes := HBoxContainer.new()
	boxes.add_theme_constant_override("separation", 8)
	for i in GuildScript.ATTEND_BOXES.size():
		var st := Guild.box_state(i)
		var give: Dictionary = GuildScript.ATTEND_BOXES[i][1]
		var b := _button("", UiKit.AMBER if st == "ready" else (UiKit.STEEL if st == "claimed" else Color(1, 1, 1, 0.7)), 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 92)
		b.disabled = st != "ready"
		var face := VBoxContainer.new()
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		face.alignment = BoxContainer.ALIGNMENT_CENTER
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.add_theme_constant_override("separation", 0)
		var chest := Control.new()
		chest.custom_minimum_size = Vector2(0, 40)
		chest.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chest.draw.connect(func(): draw_chest(chest, chest.size / 2.0, 40.0, st == "claimed"))
		face.add_child(chest)
		var lab := "%d명" % GuildScript.ATTEND_BOXES[i][0] if st != "claimed" else "받음"
		face.add_child(_small(lab, 18, HudScript.INK))
		var gtext := ("다이아 %d" % give.diamonds) if give.has("diamonds") else ("코인 %d" % give.coins)
		face.add_child(_small(gtext, 15, SUB))
		b.add_child(face)
		b.pressed.connect(func():
			var ok := Guild.claim_box(i)
			if ok:
				Economy.notice.emit("출석 상자: " + _give_text(give)))
		boxes.add_child(b)
		buttons["box:%d" % i] = b
	av.add_child(boxes)
	body.add_child(att)
	# 기부
	var don := _card()
	var dv: VBoxContainer = don.get_child(0)
	dv.add_child(_label("길드 기부", 28, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	for kind in GuildScript.DONATION_ORDER:
		var d: Dictionary = GuildScript.DONATIONS[kind]
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 10)
		var ic := Control.new()
		ic.custom_minimum_size = Vector2(56, 56)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var icon_kind := "gold" if int(d.gold) > 0 else "diamond"
		ic.draw.connect(func(): IconsScript.draw_icon(ic, icon_kind, ic.size / 2.0, ic.size.x * (0.8 if kind != "royal" else 0.95)))
		r.add_child(ic)
		var dvv := VBoxContainer.new()
		dvv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dvv.add_theme_constant_override("separation", 0)
		dvv.add_child(_label(d.name, 24, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
		dvv.add_child(_label("경험치 +%d · 코인 +%d" % [d.exp, d.coins], 19, GREEN, HORIZONTAL_ALIGNMENT_LEFT))
		dvv.add_child(_label("오늘 %d/%d회" % [Guild.donations_left(kind), d.daily], 18, SUB, HORIZONTAL_ALIGNMENT_LEFT))
		r.add_child(dvv)
		var cost := ("골드 %s" % UiKit.commas(d.gold)) if int(d.gold) > 0 else ("다이아 %d" % d.diamonds)
		var why := Guild.donate_block(kind)
		var b := _button(cost, UiKit.AMBER, 21)
		b.custom_minimum_size = Vector2(170, 60)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.disabled = why != ""
		b.pressed.connect(func():
			if Guild.donate(kind):
				Economy.notice.emit("%s 완료! 길드 코인 +%d" % [d.name, d.coins]))
		r.add_child(b)
		buttons["donate:" + kind] = b
		dv.add_child(r)
	body.add_child(don)
	# 활동 기록
	var lg := _card()
	var lv: VBoxContainer = lg.get_child(0)
	lv.add_child(_label("활동 기록", 26, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	var logs: Array = g.log.duplicate()
	logs.reverse()
	if logs.is_empty():
		lv.add_child(_label("아직 기록이 없습니다", 20, SUB, HORIZONTAL_ALIGNMENT_LEFT))
	for e in logs.slice(0, 8):
		var l := _label("%s  %s" % [ago(Guild.now_t() - float(e.t)), e.text], 19, SUB, HORIZONTAL_ALIGNMENT_LEFT)
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.clip_text = true
		lv.add_child(l)
	body.add_child(lg)
	var leave := _button("한 번 더 누르면 탈퇴합니다" if _leave_armed > 0.0 else "길드 탈퇴", RED if _leave_armed > 0.0 else UiKit.STEEL, 22)
	leave.custom_minimum_size = Vector2(0, 52)
	leave.pressed.connect(func():
		if _leave_armed > 0.0:
			_leave_armed = 0.0
			Guild.leave()
			Economy.notice.emit("길드를 탈퇴했습니다. 길드 코인은 그대로 남아요")
		else:
			_leave_armed = LEAVE_CONFIRM_SEC
			_rebuild())
	body.add_child(leave)
	buttons["leave"] = leave
	var reset := _label("매일 00:00 초기화 · 남은 시간 %s" % UiKit.clock(Guild.reset_in()), 18, SUB)
	body.add_child(reset)


func _build_boss() -> void:
	var card := _card()
	var v: VBoxContainer = card.get_child(0)
	v.add_child(_label(GuildScript.boss_name(1), 30))
	if not is_instance_valid(_dragon_box):
		_dragon_box = dragon_view(Vector2(560, 300))
	v.add_child(_dragon_box)
	var desc := _label("하루 %d번 도전. 매 판 Lv 1에서 시작해 쓰러뜨릴 때마다 레벨이 오릅니다. 준 피해가 점수이고, 길드원 점수의 합이 길드 점수예요." % GuildScript.BOSS_TRIES, 18, SUB)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)
	var sc := HBoxContainer.new()
	sc.alignment = BoxContainer.ALIGNMENT_CENTER
	sc.add_theme_constant_override("separation", 28)
	sc.add_child(_label("내 점수 %s" % UiKit.commas(int(Guild.me.get("boss_total", 0))), 26, HudScript.ACCENT.darkened(0.2)))
	sc.add_child(_label("길드 점수 %s" % UiKit.commas(int(Guild.boss_score())), 26, GREEN))
	v.add_child(sc)
	var tries := GuildScript.BOSS_TRIES - int(Guild.me.get("boss_tries", 0))
	var best := float(Guild.me.get("boss_best", 0))
	v.add_child(_label("내 팀 초당 피해 %s · 오늘 최고 %s%s" % [UiKit.commas(roundi(Guild.team_dps())), UiKit.commas(int(best)),
		(" (Lv %d)" % GuildScript.boss_reach(best)) if best > 0.0 else ""], 22))
	var why := Guild.boss_block()
	var b := _button("도전  (%d/%d)" % [tries, GuildScript.BOSS_TRIES] if why == "" or tries > 0 else "내일 다시 도전", UiKit.AMBER, 30)
	b.custom_minimum_size = Vector2(0, 72)
	b.disabled = why != ""
	b.pressed.connect(_start_fight)
	v.add_child(b)
	buttons["boss"] = b
	if why != "" and tries > 0 and not Guild.busy:  # 응답을 기다리는 잠깐은 이유를 띄우지 않는다
		v.add_child(_label(why, 20, RED))
	body.add_child(card)
	# 등급표
	var gc := _card()
	var gv: VBoxContainer = gc.get_child(0)
	gv.add_child(_label("판 등급 보상(도달한 드래곤 레벨)", 24, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	for gr in GuildScript.BOSS_GRADES:
		var r := HBoxContainer.new()
		var gl := _label(gr[0], 26, grade_color(gr[0]))
		gl.custom_minimum_size = Vector2(72, 0)
		r.add_child(gl)
		var cond := _label(("Lv %d 이상" % int(gr[1])) if int(gr[1]) > 1 else "참여", 20, SUB, HORIZONTAL_ALIGNMENT_LEFT)
		cond.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(cond)
		r.add_child(_label("코인 %d · 골드 %s" % [gr[2], UiKit.commas(gr[3])], 20, HudScript.INK, HORIZONTAL_ALIGNMENT_RIGHT))
		gv.add_child(r)
	body.add_child(gc)
	# 오늘 피해 순위
	var rk := _card()
	var rv: VBoxContainer = rk.get_child(0)
	rv.add_child(_label("오늘 점수 순위", 24, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	var list := []
	for m in Guild.members_now():
		if float(m.dmg) > 0.0:
			list.append([m.name, float(m.dmg), false])
	if float(Guild.me.get("boss_total", 0.0)) > 0.0:
		list.append([GuildScript.MY_NAME, float(Guild.me.boss_total), true])
	list.sort_custom(func(a, b2): return a[1] > b2[1])
	if list.is_empty():
		rv.add_child(_label("아직 아무도 도전하지 않았어요", 20, SUB, HORIZONTAL_ALIGNMENT_LEFT))
	for i in mini(list.size(), 10):
		var r := HBoxContainer.new()
		var c := HudScript.ACCENT.darkened(0.2) if list[i][2] else HudScript.INK
		var nl := _label("%d. %s" % [i + 1, list[i][0]], 21, c, HORIZONTAL_ALIGNMENT_LEFT)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(nl)
		r.add_child(_label(UiKit.commas(int(list[i][1])), 21, c, HORIZONTAL_ALIGNMENT_RIGHT))
		rv.add_child(r)
	body.add_child(rk)


func _build_shop() -> void:
	body.add_child(_coin_line())
	for it in GuildScript.SHOP:
		var card := _card()
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 12)
		card.get_child(0).add_child(r)
		var ic := Control.new()
		ic.custom_minimum_size = Vector2(72, 72)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var give: Dictionary = it.give
		ic.draw.connect(func(): _draw_give_icon(ic, give))
		r.add_child(ic)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 0)
		v.add_child(_label(it.name, 26, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
		var desc := "보유 영웅 중 무작위 조각 %d개" % give.shards if give.has("shards") else ("보유 SSR 영웅 무작위 조각 1개" if give.has("ssr_shards") else _give_text(give))
		if give.has("equip"):
			desc = "장비 1개, 장비 던전 최고 단계(%d단계)의 등급 확률, 부위·능력치 무작위" % maxi(1, int(Economy.dungeons.get("equip", {}).get("best_level", 0)))
		var dl := _label(desc, 19, SUB, HORIZONTAL_ALIGNMENT_LEFT)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # 긴 설명(장비 상자)이 창을 화면보다 넓히지 않게 줄바꿈
		v.add_child(dl)
		v.add_child(_label("%s %d/%d" % ["오늘" if it.period == "day" else "이번 주", Guild.shop_left(it.id), it.limit], 19, GREEN, HORIZONTAL_ALIGNMENT_LEFT))
		r.add_child(v)
		var b := _button("", UiKit.AMBER, 22)
		b.custom_minimum_size = Vector2(140, 64)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var face := HBoxContainer.new()
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		face.alignment = BoxContainer.ALIGNMENT_CENTER
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var coin := Control.new()
		coin.custom_minimum_size = Vector2(30, 30)
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		coin.draw.connect(func(): draw_coin(coin, coin.size / 2.0, 28.0))
		face.add_child(coin)
		face.add_child(_small(" %d" % it.price, 24, Color.WHITE, true))
		b.add_child(face)
		b.disabled = Guild.buy_block(it.id) != ""
		var id: String = it.id
		b.pressed.connect(func():
			var got := Guild.buy(id)
			if got != "":
				Economy.notice.emit(got))
		r.add_child(b)
		buttons["buy:" + id] = b
		body.add_child(card)
	body.add_child(_label("일일 상품은 매일 00:00, 주간 상품은 매주 초기화됩니다", 18, SUB))


func _build_members() -> void:
	var now := Guild.now_t()
	var list := []
	var me := {"name": GuildScript.MY_NAME, "role": GuildScript.ROLES[0] if Guild.guild.mine else GuildScript.ROLES[3], "power": Guild.my_power(),
		"contrib": int(Guild.me.get("contrib", 0)), "att": Guild.me.get("attended", false), "last": now, "me": true}
	list.append(me)
	for m in Guild.members_now(now):
		list.append(m)
	list.sort_custom(func(a, b): return int(a.contrib) > int(b.contrib) or (int(a.contrib) == int(b.contrib) and int(a.power) > int(b.power)))
	body.add_child(_label("길드원 %d명 · 오늘 기여도 순" % list.size(), 22, SUB))
	for m in list:
		var card := _card(UiKit.AMBER.lightened(0.7) if m.get("me", false) else Color(1, 1, 1, 0.75))
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 10)
		card.get_child(0).add_child(r)
		var role := _label(m.role, 18, Color.WHITE)
		role.custom_minimum_size = Vector2(92, 40)
		role.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		role.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var rc := COIN_COLOR if m.role == GuildScript.ROLES[0] else (UiKit.AMBER.darkened(0.15) if m.role == GuildScript.ROLES[1] else
			(GREEN if m.role == GuildScript.ROLES[2] else UiKit.STEEL))
		role.add_theme_stylebox_override("normal", UiKit.panel(rc, 8.0, 4))
		r.add_child(role)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 0)
		v.add_child(_label(m.name, 24, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
		var seen := "접속 중" if m.get("me", false) or now - float(m.last) < 600.0 else (ago(now - float(m.last)) if float(m.last) > 0.0 else "오늘 미접속")
		v.add_child(_label("전투력 %s · %s" % [UiKit.commas(int(m.power)), seen], 18, SUB, HORIZONTAL_ALIGNMENT_LEFT))
		r.add_child(v)
		var rv := VBoxContainer.new()
		rv.add_theme_constant_override("separation", 0)
		rv.add_child(_label("기여 %d" % int(m.contrib), 22, HudScript.INK, HORIZONTAL_ALIGNMENT_RIGHT))
		rv.add_child(_label("출석" if m.att else "미출석", 18, GREEN if m.att else SUB, HORIZONTAL_ALIGNMENT_RIGHT))
		r.add_child(rv)
		body.add_child(card)


# --- 보스 전투 ---

## [도전]: 실제 전투 시작(Guild.start_boss → boss_started → main이 드래곤 전투 장면을 연다). 결과는 그 장면이 띄운다.
func _start_fight() -> void:
	if not Guild.start_boss():
		Economy.notice.emit(Guild.boss_block())


## 보스 탭 드래곤 미리보기: 자기 3D 세계(SubViewport)에 드래곤 모델(대기 동작) + 조명 + 카메라.
static func dragon_view(px: Vector2) -> SubViewportContainer:
	var box := SubViewportContainer.new()
	box.stretch = true
	box.custom_minimum_size = px
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.size = Vector2i(px)
	box.add_child(vp)
	var model = DragonModelScript.new()
	model.size = 1.0
	model.rotation.y = 0.55
	vp.add_child(model)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.1
	vp.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.72, 0.78)
	env.environment.ambient_light_energy = 0.9
	vp.add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.45
	cam.position = Vector3(0, 0.62, 3.0)
	cam.rotation_degrees = Vector3(-8, 0, 0)
	vp.add_child(cam)
	return box


# --- 그림(각진 로우폴리 평면) ---

## 길드 문장: 각진 방패(왼쪽 면 밝게) + 가운데 상징(i에 따라 별·검·왕관·나무·달·불꽃·탑·하트).
static func draw_emblem(ci: CanvasItem, c: Vector2, size: float, i: int) -> void:
	var s := size / 2.0
	var col: Color = EMBLEM_COLORS[posmod(i, EMBLEM_COLORS.size())]
	var shield := PackedVector2Array([c + Vector2(-0.8, -0.85) * s, c + Vector2(0.8, -0.85) * s, c + Vector2(0.8, 0.05) * s, c + Vector2(0.0, 0.92) * s,
		c + Vector2(-0.8, 0.05) * s])
	ci.draw_colored_polygon(shield, col)
	ci.draw_colored_polygon(PackedVector2Array([shield[0], c + Vector2(0, -0.85) * s, c + Vector2(0, 0.92) * s, shield[4]]), col.lightened(0.22))
	var rim := shield.duplicate()
	rim.append(rim[0])
	ci.draw_polyline(rim, IconsScript.OUTLINE, maxf(1.5, size / 30.0), true)
	var gold := Color(0.98, 0.84, 0.36)
	var sym := PackedVector2Array()
	match posmod(i, 8):
		0:  # 별
			for k in 10:
				var r := (0.42 if k % 2 == 0 else 0.18) * s
				var a := -PI / 2.0 + k * PI / 5.0
				sym.append(c + Vector2(cos(a), sin(a)) * r + Vector2(0, -0.02 * s))
		1:  # 검
			sym = PackedVector2Array([c + Vector2(0, -0.6) * s, c + Vector2(0.09, -0.45) * s, c + Vector2(0.09, 0.2) * s, c + Vector2(0.3, 0.2) * s,
				c + Vector2(0.3, 0.3) * s, c + Vector2(0.07, 0.3) * s, c + Vector2(0.07, 0.55) * s, c + Vector2(-0.07, 0.55) * s, c + Vector2(-0.07, 0.3) * s,
				c + Vector2(-0.3, 0.3) * s, c + Vector2(-0.3, 0.2) * s, c + Vector2(-0.09, 0.2) * s, c + Vector2(-0.09, -0.45) * s])
		2:  # 왕관
			sym = PackedVector2Array([c + Vector2(-0.45, 0.3) * s, c + Vector2(-0.45, -0.3) * s, c + Vector2(-0.22, 0.0) * s, c + Vector2(0, -0.42) * s,
				c + Vector2(0.22, 0.0) * s, c + Vector2(0.45, -0.3) * s, c + Vector2(0.45, 0.3) * s])
		3:  # 나무
			sym = PackedVector2Array([c + Vector2(0, -0.55) * s, c + Vector2(0.42, 0.1) * s, c + Vector2(0.1, 0.1) * s, c + Vector2(0.1, 0.5) * s,
				c + Vector2(-0.1, 0.5) * s, c + Vector2(-0.1, 0.1) * s, c + Vector2(-0.42, 0.1) * s])
		4:  # 초승달
			for k in 9:
				var a := PI * 0.3 + k * PI * 1.4 / 8.0
				sym.append(c + Vector2(cos(a), sin(a)) * 0.45 * s)
			for k in 9:
				var a := PI * 1.7 - k * PI * 1.4 / 8.0
				sym.append(c + Vector2(0.18, 0) * s + Vector2(cos(a), sin(a)) * 0.34 * s)
		5:  # 불꽃
			sym = PackedVector2Array([c + Vector2(0, -0.6) * s, c + Vector2(0.18, -0.25) * s, c + Vector2(0.38, -0.1) * s, c + Vector2(0.32, 0.3) * s,
				c + Vector2(0, 0.5) * s, c + Vector2(-0.32, 0.3) * s, c + Vector2(-0.38, -0.05) * s, c + Vector2(-0.15, 0.0) * s])
		6:  # 성탑
			sym = PackedVector2Array([c + Vector2(-0.4, 0.5) * s, c + Vector2(-0.4, -0.45) * s, c + Vector2(-0.22, -0.45) * s, c + Vector2(-0.22, -0.3) * s,
				c + Vector2(-0.08, -0.3) * s, c + Vector2(-0.08, -0.45) * s, c + Vector2(0.08, -0.45) * s, c + Vector2(0.08, -0.3) * s,
				c + Vector2(0.22, -0.3) * s, c + Vector2(0.22, -0.45) * s, c + Vector2(0.4, -0.45) * s, c + Vector2(0.4, 0.5) * s])
		7:  # 하트
			sym = PackedVector2Array([c + Vector2(0, 0.5) * s, c + Vector2(-0.45, 0.0) * s, c + Vector2(-0.45, -0.25) * s, c + Vector2(-0.25, -0.42) * s,
				c + Vector2(0, -0.22) * s, c + Vector2(0.25, -0.42) * s, c + Vector2(0.45, -0.25) * s, c + Vector2(0.45, 0.0) * s])
	if sym.size() >= 3:
		ci.draw_colored_polygon(sym, gold)
		sym.append(sym[0])
		ci.draw_polyline(sym, Color(IconsScript.OUTLINE, 0.7), maxf(1.0, size / 45.0), true)


## 길드 코인: 보라 8각 + 안쪽 작은 방패.
static func draw_coin(ci: CanvasItem, c: Vector2, size: float) -> void:
	var pts := PackedVector2Array()
	var inner := PackedVector2Array()
	for k in 8:
		var a := PI / 8.0 + k * PI / 4.0
		pts.append(c + Vector2(cos(a), sin(a)) * size * 0.48)
		inner.append(c + Vector2(cos(a), sin(a)) * size * 0.36)
	ci.draw_colored_polygon(pts, COIN_COLOR.darkened(0.2))
	ci.draw_colored_polygon(inner, COIN_COLOR.lightened(0.15))
	var sh := PackedVector2Array([c + Vector2(-0.16, -0.18) * size, c + Vector2(0.16, -0.18) * size, c + Vector2(0.16, 0.02) * size,
		c + Vector2(0, 0.2) * size, c + Vector2(-0.16, 0.02) * size])
	ci.draw_colored_polygon(sh, Color(0.98, 0.86, 0.45))
	pts.append(pts[0])
	ci.draw_polyline(pts, IconsScript.OUTLINE, maxf(1.0, size / 22.0), true)


## 보물 상자(출석 상자). opened면 뚜껑이 열리고 흐리다.
static func draw_chest(ci: CanvasItem, c: Vector2, size: float, opened: bool) -> void:
	var s := size / 2.0
	var a := 0.5 if opened else 1.0
	var wood := Color(0.62, 0.38, 0.18, a)
	var band := Color(0.96, 0.78, 0.30, a)
	var box := PackedVector2Array([c + Vector2(-0.8, -0.1) * s, c + Vector2(0.8, -0.1) * s, c + Vector2(0.8, 0.7) * s, c + Vector2(-0.8, 0.7) * s])
	ci.draw_colored_polygon(box, wood)
	var lid := PackedVector2Array([c + Vector2(-0.8, -0.1) * s, c + Vector2(-0.6, -0.6) * s, c + Vector2(0.6, -0.6) * s, c + Vector2(0.8, -0.1) * s])
	if opened:
		lid = PackedVector2Array([c + Vector2(-0.8, -0.1) * s, c + Vector2(-0.9, -0.75) * s, c + Vector2(0.5, -0.85) * s, c + Vector2(0.6, -0.2) * s])
	ci.draw_colored_polygon(lid, wood.lightened(0.15))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.12, -0.2) * s, c + Vector2(0.12, -0.2) * s, c + Vector2(0.12, 0.25) * s,
		c + Vector2(-0.12, 0.25) * s]), band)
	box.append(box[0])
	ci.draw_polyline(box, Color(IconsScript.OUTLINE, a), 1.5, true)


func _draw_give_icon(ci: Control, give: Dictionary) -> void:
	var c := ci.size / 2.0
	if give.has("diamonds"):
		IconsScript.draw_icon(ci, "diamond", c, ci.size.x * 0.9)
	elif give.has("gold"):
		IconsScript.draw_icon(ci, "gold", c, ci.size.x * 0.9)
	elif give.has("food"):
		IconsScript.draw_icon(ci, "food", c, ci.size.x * 0.9)
	elif give.has("equip"):
		draw_chest(ci, c + Vector2(0, 2), ci.size.x * 0.9, false)
	else:  # 조각: 등급 보석 위 작은 별
		UiKit.draw_gem(ci, c, ci.size.x * 0.36, UiKit.GRADE_COLORS.SSR if give.has("ssr_shards") else UiKit.GRADE_COLORS.SR, 6)


# --- 작은 도우미 ---

func _card(color := Color(1, 1, 1, 0.75)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.panel(color, 12.0, 14))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	return p


func _emblem_box(i: int, px: float) -> Control:
	var e := Control.new()
	e.custom_minimum_size = Vector2(px, px)
	e.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	e.mouse_filter = Control.MOUSE_FILTER_IGNORE
	e.draw.connect(func(): draw_emblem(e, e.size / 2.0, px * 0.92, i))
	return e


func _coin_line() -> Control:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	var c := Control.new()
	c.custom_minimum_size = Vector2(36, 36)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.draw.connect(func(): draw_coin(c, c.size / 2.0, 34.0))
	h.add_child(c)
	h.add_child(_label(" 길드 코인 %s" % UiKit.commas(Guild.coins), 28))
	return h


func _small(text: String, fs: int, color: Color, outline := false) -> Label:
	var l := _label(text, fs, color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if outline:
		l.add_theme_color_override("font_outline_color", Color(HudScript.INK, 0.85))
		l.add_theme_constant_override("outline_size", 5)
	return l


static func _give_text(give: Dictionary) -> String:
	var parts := []
	if give.has("gold"):
		parts.append("골드 %s" % UiKit.commas(give.gold))
	if give.has("diamonds"):
		parts.append("다이아 %d" % give.diamonds)
	if give.has("food"):
		parts.append("식량 %d" % give.food)
	if give.has("coins"):
		parts.append("길드 코인 %d" % give.coins)
	return " · ".join(parts)


## 지난 시간: "방금", "12분 전", "3시간 전", "2일 전".
static func ago(sec: float) -> String:
	if sec < 60.0:
		return "방금"
	if sec < 3600.0:
		return "%d분 전" % int(sec / 60.0)
	if sec < 86400.0:
		return "%d시간 전" % int(sec / 3600.0)
	return "%d일 전" % int(sec / 86400.0)

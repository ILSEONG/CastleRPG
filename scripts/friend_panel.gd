extends "res://scripts/ui_window.gd"
## 친구 창(2026-10-06, 모집권 던전 도우미 — 온라인만). 던전 시트의 모집권 던전 카드 [친구]·편성 화면 [친구 관리]가 연다.
## 위: 내 이름·친구 코드 [복사], 탭 둘 [친구 목록][친구 추가].
## 친구 목록: 빌려주는 영웅(친구가 모집권 던전에서 데려가는 내 영웅 — 기본은 가장 강한 영웅) [바꾸기] → 내 영웅 줄에서 탭,
##   목록(스크롤): 받은 신청 [수락][거절], 친구 n / 상한(영웅·레벨·전투력, 오늘 함께했으면 표시) [삭제], 보낸 신청 [취소].
## 친구 추가: 친구 코드 입력 + [신청], 추천 성주(최근 접속, 서버가 무작위로 고른다) [새로고침] → 새로 받기, [신청].
## 다이아 선물(2026-11-05, 쿠키런·서머너즈 워의 친구 하트 보내기처럼): 친구 목록 위 줄 "보낸 선물 n / 1,500 · 받은 선물 n / 1,500" + [모두 보내기](한 번 더 눌러 확인),
##   친구 줄마다 [💎50](오늘 보냈으면 '보냄', 그 친구가 오늘 1,500개를 다 받았으면 '받기 마감'), 오늘 나에게 보낸 친구 표시. 친구 한 명 하루 50개, 보내기·받기 각각 하루 1,500개(서버가 지킨다).
## 친구 요청은 Economy.friend_op, 목록은 Economy.friends(응답이 오면 friends_changed로 다시 그린다).
## 오프라인이면 안내 한 줄만.

const Lang := preload("res://scripts/lang.gd")

const HeroCardScript := preload("res://scripts/hero_card.gd")
const GameData := preload("res://scripts/game_data.gd")

const FACE_SIZE := Vector2(84, 104)
const PICK_SIZE := Vector2(96, 118)
const LIST_H := 560.0
const SUB := Color(0.38, 0.40, 0.46)
const RED := Color(0.78, 0.22, 0.18)
const GREEN := Color(0.30, 0.62, 0.34)

var code_label: Label
var hero_card
var hero_label: Label
var pick_scroll: ScrollContainer
var pick_row: HBoxContainer
var code_edit: LineEdit
var list: VBoxContainer
var rec_list: VBoxContainer
var refresh_btn: Button
var offline_label: Label
var tab := "list"  # "list"(친구 목록) · "add"(친구 추가)
var tab_btns := {}
var _top: VBoxContainer
var _list_page: VBoxContainer
var _add_page: VBoxContainer
var gift_label: Label
var gift_all_btn: Button
var _gift_all_armed := false  # [모두 보내기]를 한 번 눌렀다(한 번 더 누르면 보낸다)
var _optimistic = null  # 곧바로 바꿔 보인 친구 목록(응답 전). 서버 응답은 새 사전으로 바꾸니, 응답 뒤에도 이 사전 그대로면 거절된 것
var _snapshot := {}  # 그 직전 목록(거절되면 되돌린다)


func _ready() -> void:
	_build_window(680, 10)
	layer = 4  # 던전 시트(2)·탭 바 위
	content.add_child(_title(Lang.t("friend_panel.ready")))
	offline_label = _label(Economy.FRIEND_OFFLINE_TEXT, 24, SUB)
	content.add_child(offline_label)
	_top = VBoxContainer.new()
	_top.add_theme_constant_override("separation", 8)
	content.add_child(_top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_top.add_child(row)
	code_label = _label("", 24, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(code_label)
	var copy := _button(Lang.t("friend_panel.ready_2"), UiKit.STEEL, 22)
	copy.custom_minimum_size = Vector2(96, 48)
	copy.pressed.connect(copy_code)
	row.add_child(copy)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	_top.add_child(tabs)
	for t in [["list", Lang.t("friend_panel.ready_3")], ["add", Lang.t("friend_panel.ready_4")]]:
		var b := _button(t[1], UiKit.STEEL, 24)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 54)
		b.pressed.connect(pick_tab.bind(t[0]))
		tabs.add_child(b)
		tab_btns[t[0]] = b
	_list_page = VBoxContainer.new()
	_list_page.add_theme_constant_override("separation", 8)
	_top.add_child(_list_page)
	_add_page = VBoxContainer.new()
	_add_page.add_theme_constant_override("separation", 8)
	_top.add_child(_add_page)
	var lend := HBoxContainer.new()
	lend.add_theme_constant_override("separation", 10)
	_list_page.add_child(lend)
	hero_card = HeroCardScript.new()
	hero_card.custom_minimum_size = FACE_SIZE
	hero_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lend.add_child(hero_card)
	hero_label = _label("", 21, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	hero_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hero_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lend.add_child(hero_label)
	var change := _button(Lang.t("friend_panel.ready_5"), UiKit.STEEL, 22)
	change.custom_minimum_size = Vector2(110, 48)
	change.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	change.pressed.connect(func(): pick_scroll.visible = not pick_scroll.visible; _fit())
	lend.add_child(change)
	pick_scroll = ScrollContainer.new()  # 빌려줄 영웅 고르기: [자동] + 내 영웅(전투력 순)
	pick_scroll.custom_minimum_size = Vector2(0, PICK_SIZE.y + 14)
	pick_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pick_scroll.visible = false
	_list_page.add_child(pick_scroll)
	pick_row = HBoxContainer.new()
	pick_row.add_theme_constant_override("separation", 6)
	pick_scroll.add_child(pick_row)
	var add := HBoxContainer.new()
	add.add_theme_constant_override("separation", 8)
	_add_page.add_child(add)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = Lang.t("friend_panel.ready_6")
	code_edit.max_length = 8
	code_edit.custom_minimum_size = Vector2(0, 56)
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_edit.add_theme_font_size_override("font_size", 26)
	code_edit.text_submitted.connect(func(_t): send_code())
	add.add_child(code_edit)
	var send := _button(Lang.t("friend_panel.ready_7"), HudScript.ACCENT, 24)
	send.custom_minimum_size = Vector2(110, 56)
	send.pressed.connect(send_code)
	add.add_child(send)
	var rec_head := HBoxContainer.new()
	rec_head.add_theme_constant_override("separation", 8)
	_add_page.add_child(rec_head)
	var rec_title := _label(Lang.t("friend_panel.ready_8"), 24, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	rec_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rec_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rec_head.add_child(rec_title)
	refresh_btn = _button(Lang.t("friend_panel.ready_9"), UiKit.STEEL, 22)
	refresh_btn.custom_minimum_size = Vector2(130, 48)
	refresh_btn.pressed.connect(refresh_recommend)
	rec_head.add_child(refresh_btn)
	var gift_row := HBoxContainer.new()
	gift_row.add_theme_constant_override("separation", 8)
	_list_page.add_child(gift_row)
	gift_label = _label("", 21, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	gift_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gift_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gift_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gift_row.add_child(gift_label)
	gift_all_btn = _button("", HudScript.ACCENT, 21)
	gift_all_btn.custom_minimum_size = Vector2(170, 48)
	gift_all_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gift_all_btn.pressed.connect(gift_all)
	gift_row.add_child(gift_all_btn)
	list = _scroll_list(_list_page, LIST_H - 56)
	rec_list = _scroll_list(_add_page, LIST_H - 8)  # 두 탭 창 높이를 맞춘다
	_add_close_x()  # 오른쪽 위 닫기(사용자 2026-11-05 "닫기 버튼 대신 일괄적으로 우측 상단에 x")
	Economy.friends_changed.connect(_on_friends_changed)


func _scroll_list(parent: Control, h: float) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)
	return v


func _on_open() -> void:
	pick_scroll.visible = false
	_gift_all_armed = false
	tab = "list"
	Economy.friends_load()
	_refresh()


func _on_friends_changed() -> void:
	if _optimistic != null and not Economy.friends_waiting:
		if is_same(Economy.friends, _optimistic):  # 거절·끊김: 곧바로 바꾼 것을 되돌린다(알림은 Economy가 띄웠다)
			Economy.friends = _snapshot
		_optimistic = null
		_snapshot = {}
	_refresh()


## 친구 요청을 곧바로 반영해 보이고(local이 목록 사본을 고친다) Economy.friend_op로 보낸다. 응답이 오면 서버 목록으로, 거절되면 되돌린다.
## 응답 전에는 Economy.friends_waiting이라 같은 요청이 두 번 나가지 않는다.
func _op(op: String, body: Dictionary, local: Callable) -> void:
	if Economy.net == null or Economy.friends_waiting or not Economy.net.up or Economy.friends.is_empty():
		Economy.friend_op(op, body)  # 알림(오프라인·끊김)은 그쪽이 띄운다
		return
	var snap: Dictionary = Economy.friends
	var f: Dictionary = snap.duplicate(true)
	local.call(f)
	Economy.friends = f
	if Economy.friend_op(op, body):  # friends_changed → 곧바로 다시 그린다
		_optimistic = f
		_snapshot = snap
	else:
		Economy.friends = snap


func _person_op(op: String, id: String) -> void:
	var local := func(f: Dictionary):
		var drop := func(k: String) -> Dictionary:
			var hit := {}
			var keep := []
			for x in f.get(k, []):
				if x is Dictionary and str(x.get("id", "")) == id:
					hit = x
				else:
					keep.append(x)
			f[k] = keep
			return hit
		if op == "accept":
			var p: Dictionary = drop.call("incoming")
			if not p.is_empty():
				f["friends"] = f.get("friends", []) + [p]
		elif op == "request":
			var p: Dictionary = drop.call("recommend")
			if not p.is_empty():
				f["outgoing"] = f.get("outgoing", []) + [p]
		else:  # remove: 삭제·거절·취소
			drop.call("incoming")
			drop.call("friends")
			drop.call("outgoing")
	_op(op, {"id": id}, local)


func _hero_op(id) -> void:
	var local := func(f: Dictionary):
		f["hero_chosen"] = id
		if id is String:
			f["hero"] = {"hero_id": id, "level": Economy.level_of(id), "promotion": Economy.promotion_of(id)}
	_op("hero", {"hero_id": id}, local)


## 오늘 아직 선물을 안 보냈고 받을 한도가 남은 친구 id들(목록 순서)
func _gift_targets(f: Dictionary) -> Array:
	var sent: Array = f.get("gift", {}).get("sent_to", [])
	var full: Array = f.get("gift", {}).get("full", [])  # 오늘 받을 한도(1,500개)를 다 받은 친구
	return f.get("friends", []).map(func(p): return str(p.get("id", ""))).filter(func(id): return id != "" and not sent.has(id) and not full.has(id))


## 한 친구에게 선물: 곧바로 '보냄'으로 바꿔 보이고 보낸다(거절되면 되돌린다).
func gift_one(id: String) -> void:
	_op("gift", {"id": id}, func(f: Dictionary):
		var g: Dictionary = f.get("gift", {})
		g["sent_to"] = g.get("sent_to", []) + [id]
		g["sent"] = int(g.get("sent", 0)) + int(g.get("per", 100))
		f["gift"] = g)


## [모두 보내기]: 첫 탭은 확인(보낼 명수·다이아를 버튼에 보인다), 두 번째 탭에 보낸다.
func gift_all() -> void:
	if not _gift_all_armed:
		_gift_all_armed = true
		_refresh()
		return
	_gift_all_armed = false
	var n := _gift_all_count(Economy.friends)
	_op("gift", {"all": true}, func(f: Dictionary):
		var g: Dictionary = f.get("gift", {})
		var ids := _gift_targets(f).slice(0, n)
		g["sent_to"] = g.get("sent_to", []) + ids
		g["sent"] = int(g.get("sent", 0)) + ids.size() * int(g.get("per", 100))
		f["gift"] = g)


## 모두 보내기로 보낼 명수: 안 보낸 친구 중 남은 하루 한도·가진 다이아만큼(서버와 같은 셈)
func _gift_all_count(f: Dictionary) -> int:
	var g: Dictionary = f.get("gift", {})
	var per: int = max(1, int(g.get("per", 100)))
	var room: int = (int(g.get("cap", 1500)) - int(g.get("sent", 0))) / per
	return max(0, mini(_gift_targets(f).size(), mini(room, int(Economy.diamonds) / per)))


func pick_tab(t: String) -> void:
	tab = t
	pick_scroll.visible = false
	_refresh()


## 추천 성주 새로 받기: 친구 목록 전체를 다시 받는다(서버가 추천을 매번 무작위로 고른다).
func refresh_recommend() -> void:
	if Economy.net == null or Economy.friends_waiting:
		return
	Economy.friends_load()
	_refresh()


func copy_code() -> void:
	var code := str(Economy.friends.get("code", ""))
	if code != "":
		DisplayServer.clipboard_set(code)
		Economy.notice.emit(Lang.t("friend_panel.copy_code"))


func send_code() -> void:
	var code := code_edit.text.strip_edges().to_upper()
	if code.length() != 8:
		Economy.notice.emit(Economy.FRIEND_TEXT.bad_request)
		return
	if Economy.friend_op("request", {"code": code}):
		code_edit.text = ""


func _refresh() -> void:
	if not is_inside_tree():
		return
	var online: bool = Economy.net != null
	offline_label.visible = not online
	_top.visible = online
	if not online:
		_fit()
		return
	var f: Dictionary = Economy.friends
	code_label.text = Lang.t("friend_panel.refresh") % [f.get("name", "…"), f.get("code", "…")] if not f.is_empty() else Lang.t("friend_panel.refresh_2")
	if f.is_empty():
		preload("res://scripts/spinner.gd").mark(code_label)  # 받는 중: 로딩 고리
	var h = f.get("hero")
	hero_card.hero_id = h.hero_id if h is Dictionary else ""
	hero_card.stars = int(h.promotion) if h is Dictionary else 0
	hero_card.queue_redraw()
	hero_label.text = (Lang.t("friend_panel.refresh_3") % [GameData.hero(h.hero_id).get("name", h.hero_id), int(h.level),
		"" if f.get("hero_chosen") is String else Lang.t("friend_panel.refresh_4")]) if h is Dictionary else Lang.t("friend_panel.refresh_5")
	_fill_picks(f)
	for k in tab_btns:
		UiKit.apply_button(tab_btns[k], UiKit.AMBER if k == tab else UiKit.STEEL, 14.0)
	var n_in: int = f.get("incoming", []).size()
	tab_btns.list.text = Lang.t("friend_panel.refresh_6") if n_in == 0 else Lang.t("friend_panel.refresh_7") % n_in
	_list_page.visible = tab == "list"
	_add_page.visible = tab == "add"
	refresh_btn.disabled = Economy.friends_waiting
	for v in [list, rec_list]:
		for c in v.get_children():
			v.remove_child(c)
			c.queue_free()
	if f.is_empty():
		_fit()
		return
	var gift: Dictionary = f.get("gift", {})
	var per := int(gift.get("per", 50))
	var gift_sent: Array = gift.get("sent_to", [])
	var gift_got: Array = gift.get("received_from", [])
	var gift_full: bool = int(gift.get("sent", 0)) + per > int(gift.get("cap", 1500))
	var cap_s := UiKit.commas(int(gift.get("cap", 1500)))
	gift_label.text = Lang.t("friend_panel.gift_today") % [UiKit.commas(int(gift.get("sent", 0))), cap_s, UiKit.commas(int(gift.get("received", 0))), cap_s]
	var n_all := _gift_all_count(f)
	if n_all == 0:
		_gift_all_armed = false
	gift_all_btn.text = Lang.t("friend_panel.gift_all_ok") % [n_all, UiKit.commas(n_all * per)] if _gift_all_armed else Lang.t("friend_panel.gift_all")
	UiKit.apply_button(gift_all_btn, UiKit.AMBER if _gift_all_armed else HudScript.ACCENT, 14.0)
	gift_all_btn.disabled = Economy.friends_waiting or n_all == 0
	var used: Array = f.get("used_today", [])
	_section(list, Lang.t("friend_panel.refresh_8"), f.get("incoming", []), func(p, row): _add_btn(row, Lang.t("friend_panel.refresh_9"), HudScript.ACCENT, "accept", p.id); _add_btn(row, Lang.t("friend_panel.refresh_10"), UiKit.STEEL, "remove", p.id))
	var fr: Array = f.get("friends", [])
	_section(list, Lang.t("friend_panel.refresh_11") % [fr.size(), int(f.get("cap", 30))], fr, func(p, row):
		_gift_btn(row, p.id, per, gift_sent.has(p.id), gift_full, gift.get("full", []).has(p.id))
		_add_btn(row, Lang.t("friend_panel.refresh_12"), UiKit.STEEL, "remove", p.id),
		Lang.t("friend_panel.refresh_13"), used, gift_got)
	_section(list, Lang.t("friend_panel.refresh_14"), f.get("outgoing", []), func(p, row): _add_btn(row, Lang.t("friend_panel.refresh_15"), UiKit.STEEL, "remove", p.id))
	_section(rec_list, "", f.get("recommend", []), func(p, row): _add_btn(row, Lang.t("friend_panel.refresh_16"), HudScript.ACCENT, "request", p.id),
		Lang.t("friend_panel.refresh_17"))
	_fit()


## 빌려줄 영웅 고르기 줄: [자동](가장 강한 영웅) + 내 영웅 카드(고른 것은 체크 — 초록 테두리 + 체크 배지).
func _fill_picks(f: Dictionary) -> void:
	for c in pick_row.get_children():
		pick_row.remove_child(c)
		c.queue_free()
	var auto := _button(Lang.t("friend_panel.fill_picks"), UiKit.AMBER if not (f.get("hero_chosen") is String) else UiKit.STEEL, 22)
	auto.custom_minimum_size = Vector2(90, PICK_SIZE.y)
	auto.pressed.connect(func(): _hero_op(null))
	pick_row.add_child(auto)
	var ids: Array = Economy.heroes.keys().filter(func(id): return int(Economy.heroes[id]) >= 1 and not GameData.hero(id).is_empty())
	var pw := {}
	for id in ids:
		pw[id] = GameData.hero_power(GameData.hero(id), Economy.level_of(id), Economy.promotion_of(id))
	ids.sort_custom(func(a, b): return pw[a] > pw[b])
	for id in ids:
		var card = HeroCardScript.new()
		card.custom_minimum_size = PICK_SIZE
		card.hero_id = id
		card.level = Economy.level_of(id)
		card.stars = Economy.promotion_of(id)
		card.checked = f.get("hero_chosen") == id
		card.tapped.connect(func(_c): _hero_op(id))
		pick_row.add_child(card)


## 한 묶음(into 목록에): 머리 줄(title이 비면 생략) + 사람 줄(영웅 얼굴·이름·영웅 정보 + buttons(p, row)이 붙이는 버튼). 비었으면 empty 안내(없으면 묶음째 숨김).
func _section(into: VBoxContainer, title: String, people: Array, buttons: Callable, empty := "", used: Array = [], gifted: Array = []) -> void:
	if people.is_empty() and empty == "":
		return
	if title != "":
		into.add_child(_label(title, 24, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	if people.is_empty():
		var e := _label(empty, 20, SUB, HORIZONTAL_ALIGNMENT_LEFT)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		into.add_child(e)
	for p in people:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		into.add_child(row)
		var h = p.get("hero")
		var face = HeroCardScript.new()
		face.custom_minimum_size = FACE_SIZE
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.hero_id = h.hero_id if h is Dictionary else ""
		face.stars = int(h.promotion) if h is Dictionary else 0
		row.add_child(face)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(info)
		info.add_child(_label(str(p.get("name", "")), 24, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
		var sub := Lang.t("friend_panel.section.sub") % [GameData.hero(h.hero_id).get("name", h.hero_id), int(h.level), int(h.power)] if h is Dictionary else Lang.t("friend_panel.section.sub_2")
		info.add_child(_label(sub, 19, SUB, HORIZONTAL_ALIGNMENT_LEFT))
		if used.has(p.id):
			info.add_child(_label(Lang.t("friend_panel.section"), 18, GREEN, HORIZONTAL_ALIGNMENT_LEFT))
		if gifted.has(p.id):
			info.add_child(_label(Lang.t("friend_panel.gift_got"), 18, GREEN, HORIZONTAL_ALIGNMENT_LEFT))
		buttons.call(p, row)


func _add_btn(row: HBoxContainer, text: String, color: Color, op: String, id: String) -> void:
	var b := _button(text, color, 22)
	b.custom_minimum_size = Vector2(88, 52)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = Economy.friends_waiting
	b.pressed.connect(func(): _person_op(op, id))
	row.add_child(b)


## 친구 줄 [💎50] — 오늘 보냈으면 '보냄', 그 친구가 오늘 1,500개를 다 받았으면 '받기 마감', 내 보낼 한도를 다 썼으면 꺼짐.
func _gift_btn(row: HBoxContainer, id: String, per: int, sent: bool, full: bool, their_full := false) -> void:
	var text := Lang.t("friend_panel.gift_done") if sent else (Lang.t("friend_panel.gift_their_full") if their_full else Lang.t("friend_panel.gift_one") % per)
	var b := _button(text, UiKit.STEEL if sent or their_full else HudScript.ACCENT, 21)
	b.custom_minimum_size = Vector2(96, 52)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = sent or full or their_full or Economy.friends_waiting
	b.pressed.connect(func(): gift_one(id))
	row.add_child(b)


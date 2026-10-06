extends "res://scripts/ui_window.gd"
## 친구 창(2026-10-06, 모집권 던전 도우미 — 온라인만). 던전 시트의 모집권 던전 카드 [친구]·편성 화면 [친구 관리]가 연다.
## 위: 내 이름·친구 코드 [복사], 탭 둘 [친구 목록][친구 추가].
## 친구 목록: 빌려주는 영웅(친구가 모집권 던전에서 데려가는 내 영웅 — 기본은 가장 강한 영웅) [바꾸기] → 내 영웅 줄에서 탭,
##   목록(스크롤): 받은 신청 [수락][거절], 친구 n / 상한(영웅·레벨·전투력, 오늘 함께했으면 표시) [삭제], 보낸 신청 [취소].
## 친구 추가: 친구 코드 입력 + [신청], 추천 성주(최근 접속, 서버가 무작위로 고른다) [새로고침] → 새로 받기, [신청].
## 친구 요청은 Economy.friend_op, 목록은 Economy.friends(응답이 오면 friends_changed로 다시 그린다).
## 오프라인이면 안내 한 줄만.

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


func _ready() -> void:
	_build_window(680, 10)
	layer = 4  # 던전 시트(2)·탭 바 위
	content.add_child(_title("친구"))
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
	var copy := _button("복사", UiKit.STEEL, 22)
	copy.custom_minimum_size = Vector2(96, 48)
	copy.pressed.connect(copy_code)
	row.add_child(copy)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	_top.add_child(tabs)
	for t in [["list", "친구 목록"], ["add", "친구 추가"]]:
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
	var change := _button("바꾸기", UiKit.STEEL, 22)
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
	code_edit.placeholder_text = "친구 코드 8자리"
	code_edit.max_length = 8
	code_edit.custom_minimum_size = Vector2(0, 56)
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_edit.add_theme_font_size_override("font_size", 26)
	code_edit.text_submitted.connect(func(_t): send_code())
	add.add_child(code_edit)
	var send := _button("신청", HudScript.ACCENT, 24)
	send.custom_minimum_size = Vector2(110, 56)
	send.pressed.connect(send_code)
	add.add_child(send)
	var rec_head := HBoxContainer.new()
	rec_head.add_theme_constant_override("separation", 8)
	_add_page.add_child(rec_head)
	var rec_title := _label("추천 성주", 24, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	rec_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rec_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rec_head.add_child(rec_title)
	refresh_btn = _button("새로고침", UiKit.STEEL, 22)
	refresh_btn.custom_minimum_size = Vector2(130, 48)
	refresh_btn.pressed.connect(refresh_recommend)
	rec_head.add_child(refresh_btn)
	list = _scroll_list(_list_page, LIST_H)
	rec_list = _scroll_list(_add_page, LIST_H - 8)  # 두 탭 창 높이를 맞춘다
	var close_b := _button("닫기", UiKit.STEEL)
	close_b.pressed.connect(close)
	content.add_child(close_b)
	Economy.friends_changed.connect(_refresh)


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
	tab = "list"
	Economy.friends_load()
	_refresh()


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
		Economy.notice.emit("친구 코드를 복사했습니다")


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
	code_label.text = "%s · 친구 코드 %s" % [f.get("name", "…"), f.get("code", "…")] if not f.is_empty() else "친구 목록을 받는 중…"
	var h = f.get("hero")
	hero_card.hero_id = h.hero_id if h is Dictionary else ""
	hero_card.stars = int(h.promotion) if h is Dictionary else 0
	hero_card.queue_redraw()
	hero_label.text = ("빌려주는 영웅: %s Lv %d%s\n친구가 모집권 던전에 데려갑니다" % [GameData.hero(h.hero_id).get("name", h.hero_id), int(h.level),
		"" if f.get("hero_chosen") is String else " (가장 강한 영웅)"]) if h is Dictionary else "빌려줄 영웅이 없습니다"
	_fill_picks(f)
	for k in tab_btns:
		UiKit.apply_button(tab_btns[k], UiKit.AMBER if k == tab else UiKit.STEEL, 14.0)
	var n_in: int = f.get("incoming", []).size()
	tab_btns.list.text = "친구 목록" if n_in == 0 else "친구 목록 (신청 %d)" % n_in
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
	var used: Array = f.get("used_today", [])
	_section(list, "받은 신청", f.get("incoming", []), func(p, row): _add_btn(row, "수락", HudScript.ACCENT, "accept", p.id); _add_btn(row, "거절", UiKit.STEEL, "remove", p.id))
	var fr: Array = f.get("friends", [])
	_section(list, "친구 %d / %d명" % [fr.size(), int(f.get("cap", 30))], fr, func(p, row): _add_btn(row, "삭제", UiKit.STEEL, "remove", p.id),
		"아직 친구가 없어요. 친구 코드를 주고받거나 [친구 추가] 탭의 추천 성주에게 신청해 보세요.", used)
	_section(list, "보낸 신청", f.get("outgoing", []), func(p, row): _add_btn(row, "취소", UiKit.STEEL, "remove", p.id))
	_section(rec_list, "", f.get("recommend", []), func(p, row): _add_btn(row, "신청", HudScript.ACCENT, "request", p.id),
		"지금 추천할 성주가 없어요. 잠시 뒤 [새로고침]을 눌러 보세요.")
	_fit()


## 빌려줄 영웅 고르기 줄: [자동](가장 강한 영웅) + 내 영웅 카드(고른 것은 호박색 테두리).
func _fill_picks(f: Dictionary) -> void:
	for c in pick_row.get_children():
		pick_row.remove_child(c)
		c.queue_free()
	var auto := _button("자동", UiKit.AMBER if not (f.get("hero_chosen") is String) else UiKit.STEEL, 22)
	auto.custom_minimum_size = Vector2(90, PICK_SIZE.y)
	auto.pressed.connect(func(): Economy.friend_op("hero", {"hero_id": null}))
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
		card.highlight = f.get("hero_chosen") == id
		card.tapped.connect(func(_c): Economy.friend_op("hero", {"hero_id": id}))
		pick_row.add_child(card)


## 한 묶음(into 목록에): 머리 줄(title이 비면 생략) + 사람 줄(영웅 얼굴·이름·영웅 정보 + buttons(p, row)이 붙이는 버튼). 비었으면 empty 안내(없으면 묶음째 숨김).
func _section(into: VBoxContainer, title: String, people: Array, buttons: Callable, empty := "", used: Array = []) -> void:
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
		var sub := "%s Lv %d · 전투력 %d" % [GameData.hero(h.hero_id).get("name", h.hero_id), int(h.level), int(h.power)] if h is Dictionary else "영웅 없음"
		info.add_child(_label(sub, 19, SUB, HORIZONTAL_ALIGNMENT_LEFT))
		if used.has(p.id):
			info.add_child(_label("오늘 함께했어요 · 내일 다시", 18, GREEN, HORIZONTAL_ALIGNMENT_LEFT))
		buttons.call(p, row)


func _add_btn(row: HBoxContainer, text: String, color: Color, op: String, id: String) -> void:
	var b := _button(text, color, 22)
	b.custom_minimum_size = Vector2(88, 52)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = Economy.friends_waiting
	b.pressed.connect(func(): Economy.friend_op(op, {"id": id}))
	row.add_child(b)

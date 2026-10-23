extends CanvasLayer
## 오른쪽 아래 메뉴(2026-10-06): 토글 버튼 하나, 누르면 위로 [설정][가방][미션][랭킹][친구][이벤트] 버튼이 펼쳐진다(다시 누르거나 항목을 고르면 접힌다).
## [설정]은 설정 창(settings_panel.gd: 배경음악 켬/끔·음량, 화면, 계정, 버전)을 연다 — 예전 [음악] 켬/끔 버튼 자리.
## 자리: 오른쪽 아래, 탭 바 위. 튜토리얼 미션 카드가 보이면 카드 위로 올라간다(겹치지 않게, 매 프레임 맞춘다).
## [거래소](2026-10-07, exchange_panel.gd)는 [길드] 바로 위 — 가이드를 마치면 열리고(그 전엔 흐리게 + 자물쇠), 받을 판매 대금이 있으면 빨간 점.
## [길드](2026-10-07, 하단 탭에서 옮김)는 맨 아래(토글 바로 위). 튜토리얼 길드 미션 전에는 흐리게 + 자물쇠, 누르면 잠금 토스트(하단 탭과 같은 규칙).
## 길드 미션 중이면 [길드]와 [메뉴]에 빨간 점(어디를 누를지).
## [공지]·[우편](2026-10-12, 온라인 운영 도구 LiveOps): 공지사항 창·우편함 창. 안 본 공지·받을 우편이 있으면 빨간 점.
## main.gd가 만들고 windows = {settings, notice, mail, bag(방치 주머니), mission, ranking, friend, event, guild}(ui_window 창)를 넣는다. 친구 창은 던전 시트가 만든 것(friend_panel.gd)을 그대로 연다.

const Lang := preload("res://scripts/lang.gd")

const UiKit := preload("res://scripts/ui_kit.gd")
const HudScript := preload("res://scripts/hud.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const PouchPanel := preload("res://scripts/pouch_panel.gd")
const TabBarScript := preload("res://scripts/tab_bar.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

static var ITEMS := [["settings", Lang.t("side_menu.items")], ["notice", Lang.t("side_menu.items_2")], ["mail", Lang.t("side_menu.items_3")], ["bag", Lang.t("side_menu.items_4")], ["mission", Lang.t("side_menu.items_5")], ["ranking", Lang.t("side_menu.items_6")], ["friend", Lang.t("side_menu.items_7")], ["event", Lang.t("side_menu.items_8")], ["exchange", Lang.t("side_menu.items_9")],
	["guild", Lang.t("side_menu.items_10")]]
const LOCKABLE := ["exchange", "guild"]  # 가이드 잠금(Tutorial.tab_locked)이 있는 항목
const SIZE := Vector2(84, 84)
const SIDE := 16.0
const GAP := 10.0
const ABOVE := 12.0  # 탭 바·미션 카드 위 여백
const BASE := Color(0.30, 0.34, 0.46)
const GOLD := Color(0.98, 0.76, 0.18)
const OPEN_SEC := 0.14
const TOP_LIMIT := 206.0  # 펼친 줄이 이보다 위로 올라가면(상단 스테이지 카드와 겹침) 위쪽 항목을 왼쪽 둘째 줄로 옮긴다

var windows := {}  # 항목 id → 창(open()/is_open())
var card  # tutorial_card.gd(있으면 그 위로 올린다)
var toggle: Button
var buttons := {}  # 항목 id → Button(테스트용)
var is_open := false

var _col: VBoxContainer
var _col2: VBoxContainer  # 넘친 위쪽 항목(왼쪽 둘째 줄, 아래를 [메뉴] 바로 위 항목에 맞춘다)
var _split := 0  # _col2로 옮긴 항목 수(ITEMS 앞에서부터)
var _dots := {}  # 빨간 점을 그린 버튼 id → true
var _t := 0.0  # 펼침 정도 0..1
var _locked := {}  # 잠겨 흐리게 그린 항목 id → true
var _shown_sig := "?"  # 가이드 중 보이는 항목 id들(_shown_ids — 초반 단순화 2026-10-23). 처음엔 어느 것과도 다르게


func _ready() -> void:
	layer = 1
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", int(GAP))
	_col.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_col)
	_col2 = VBoxContainer.new()
	_col2.add_theme_constant_override("separation", int(GAP))
	_col2.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_col2.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_col2.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_col2)
	for it in ITEMS:
		var b := _make_button(it[0], it[1])
		b.pressed.connect(func(): pick(it[0]))
		buttons[it[0]] = b
		_col.add_child(b)
	toggle = _make_button("toggle", Lang.t("side_menu.ready"))
	toggle.pressed.connect(func(): set_open(not is_open))
	_col.add_child(toggle)
	Tutorial.register_ui("menu", toggle, func(): return not is_open)  # 가이드 화살표: 접혀 있으면 [메뉴], 펼치면 그 항목
	for id in buttons:
		var b: Button = buttons[id]
		Tutorial.register_ui("menu:" + id, b, func(): return is_open and _t > 0.9 and not (windows.has(id) and windows[id].is_open()))
	set_open(false)


## 출석 이벤트 보상을 오늘 받을 수 있다(서버 /v1/player의 attendance).
func has_dot() -> bool:
	return bool(Economy.attendance.get("can_claim", false))


## 빨간 점을 그릴 버튼: [이벤트](출석 보상)·[미션](받을 미션 보상), 둘 중 하나라도 있으면 [메뉴].
func dots() -> Dictionary:
	var d := {}
	if has_dot():
		d.event = true
	if Missions.ready_count() > 0:
		d.mission = true
	if LiveOps.mail_count() > 0:
		d.mail = true
	if LiveOps.has_unseen():
		d.notice = true
	if guild_mission():
		d.guild = true
	if Economy.market_sold > 0 and not Tutorial.tab_locked("exchange"):  # 거래소: 팔린 장비 대금
		d.exchange = true
	for id in d.keys():  # 가이드 중 숨긴 항목의 점은 [메뉴]에도 올리지 않는다
		if not Tutorial.ui_shown("menu:" + str(id)):
			d.erase(id)
	if not d.is_empty():
		d.toggle = true
	return d


## 튜토리얼 지금 미션이 길드 가입이다(아직 완료 전) — [길드]·[메뉴]에 빨간 점.
func guild_mission() -> bool:
	var m: Dictionary = Tutorial.mission()
	return Tutorial.active() and not m.is_empty() and str(m.get("goto", "")) == "tab:guild" and not Tutorial.complete()


## 보이는 항목(ITEMS 순서): 가이드 중에는 그 기능을 쓰는 미션이 올 때까지 숨긴다(Tutorial.ui_shown "menu:<id>" — 설정·공지·우편은 늘).
func _shown_ids() -> Array:
	var out := []
	for it in ITEMS:
		if Tutorial.ui_shown("menu:" + it[0]):
			out.append(it[0])
	return out


func set_open(on: bool) -> void:
	is_open = on
	var shown := _shown_ids()
	_shown_sig = ",".join(shown)
	for id in buttons:
		buttons[id].visible = on and id in shown
	if on:
		_t = 0.0
	toggle.get_child(0).queue_redraw()


## 항목 고르기(버튼·튜토리얼 [바로가기]).
func pick(id: String) -> void:
	if Tutorial.tab_locked(id):  # 길드·거래소: 가이드에서 열리기 전(하단 탭과 같은 잠금 토스트)
		Tutorial.lock_notice.emit(Tutorial.tab_lock_text(id))
		return
	set_open(false)
	var w = windows.get(id)
	if w != null and not w.is_open():
		w.open()


func _process(delta: float) -> void:
	if ",".join(_shown_ids()) != _shown_sig:  # 가이드가 새 항목을 열었다
		set_open(is_open)
		_split = -1
	var d := dots()
	for id in LOCKABLE:
		var locked := Tutorial.tab_locked(id)
		if locked != _locked.has(id) and buttons.has(id):  # 가이드 잠금: 상자·그림을 흐리게(자물쇠는 _draw_face)
			if locked:
				_locked[id] = true
			else:
				_locked.erase(id)
			buttons[id].self_modulate = Color(1, 1, 1, 0.45) if locked else Color.WHITE
			buttons[id].get_child(0).self_modulate = Color(1, 1, 1, 0.6) if locked else Color.WHITE
			buttons[id].get_child(0).queue_redraw()
	if d != _dots:  # 받을 보상(출석·미션)이 있으면 그 버튼과 [메뉴]에 빨간 점
		_dots = d
		toggle.get_child(0).queue_redraw()
		for id in buttons:
			buttons[id].get_child(0).queue_redraw()
	var bottom := float(HudScript.TAB_BAR_H) + ABOVE
	if card != null and card.panel != null and card.panel.visible:
		var vh := get_viewport().get_visible_rect().size.y
		bottom = maxf(bottom, vh - card.panel.global_position.y + ABOVE)
	var vh2 := get_viewport().get_visible_rect().size.y
	var fits := maxi(2, int((vh2 - bottom - TOP_LIMIT + GAP) / (SIZE.y + GAP)))
	var shown_n := _shown_sig.count(",") + 1 if _shown_sig != "" else 0
	var split := clampi(shown_n + 1 - fits, 0, maxi(0, shown_n - 1))
	if split != _split:
		_set_split(split)
	_col.offset_right = -SIDE
	_col.offset_left = -SIDE - SIZE.x
	_col.offset_bottom = -bottom
	_col.offset_top = -bottom - _col.get_combined_minimum_size().y
	var b2 := bottom + SIZE.y + GAP
	_col2.offset_right = -SIDE - SIZE.x - GAP
	_col2.offset_left = -SIDE - 2.0 * SIZE.x - GAP
	_col2.offset_bottom = -b2
	_col2.offset_top = -b2 - _col2.get_combined_minimum_size().y
	if is_open and _t < 1.0:  # 펼칠 때 아래에서 살짝 올라오며 나타난다
		_t = minf(1.0, _t + delta / OPEN_SEC)
		for i in ITEMS.size():
			var b: Button = buttons[ITEMS[i][0]]
			b.modulate.a = _t
			b.get_child(0).position.y = (1.0 - _t) * 18.0 * (ITEMS.size() - i)


## 보이는 항목 중 위쪽 n개를 왼쪽 둘째 줄로(나머지와 [메뉴]는 오른쪽 줄). 순서는 ITEMS 그대로. 숨긴 항목은 오른쪽 줄 맨 위에 둔다(안 보인다).
func _set_split(n: int) -> void:
	_split = n
	var shown := _shown_ids()
	var order := []  # 오른쪽 줄 순서: 숨긴 항목 → 보이는 항목 중 n번째부터
	var left := []
	for it in ITEMS:
		var k := shown.find(it[0])
		if k < 0:
			order.push_front(it[0])
		elif k < n:
			left.append(it[0])
		else:
			order.append(it[0])
	for id in left + order:
		var b: Button = buttons[id]
		var want: VBoxContainer = _col2 if id in left else _col
		if b.get_parent() != want:
			b.get_parent().remove_child(b)
			want.add_child(b)
	for i in left.size():
		_col2.move_child(buttons[left[i]], i)
	for i in order.size():
		_col.move_child(buttons[order[i]], i)
	_col.move_child(toggle, _col.get_child_count() - 1)


func _make_button(id: String, text: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = SIZE
	UiKit.apply_button(b, UiKit.AMBER if id == "toggle" else BASE, 12.0)
	var face := Control.new()
	face.size = SIZE
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.draw.connect(func(): _draw_face(face, id, text))
	b.add_child(face)
	return b


func _draw_face(c: Control, id: String, text: String) -> void:
	var ctr := Vector2(SIZE.x / 2.0, 34)
	match id:
		"ranking":
			draw_trophy(c, ctr, 44.0)
		"friend":
			draw_friends(c, ctr, 44.0)
		"event":
			draw_gift(c, ctr, 44.0)
		"mission":
			draw_scroll(c, ctr, 44.0)
		"bag":
			PouchPanel.draw_pouch(c, ctr, 46.0, "gold", false)  # 메뉴 버튼은 벡터 아이콘끼리 맞춘다
		"guild":
			TabBarScript.draw_shapes(c, TabBarScript.tab_shapes("guild"), ctr, 44.0)
			if Tutorial.tab_locked("guild"):
				TabBarScript.draw_shapes(c, TabBarScript.LOCK_SHAPES, Vector2(SIZE.x - 18, 18), 26.0)
		"exchange":
			draw_scales(c, ctr, 44.0)
			if Tutorial.tab_locked("exchange"):
				TabBarScript.draw_shapes(c, TabBarScript.LOCK_SHAPES, Vector2(SIZE.x - 18, 18), 26.0)
		"settings":
			draw_gear(c, ctr, 44.0)
		"notice":
			draw_megaphone(c, ctr, 44.0)
		"mail":
			draw_envelope(c, ctr, 44.0)
		_:
			draw_chevron(c, ctr, 30.0, is_open)
			text = Lang.t("side_menu.draw_face") if is_open else Lang.t("side_menu.draw_face_2")
	if _dots.has(id):
		var dp := Vector2(SIZE.x - 12, 12)
		c.draw_circle(dp, 9.0, Color(0.88, 0.22, 0.2))
		c.draw_arc(dp, 9.0, 0, TAU, 16, Color(0.88, 0.22, 0.2).darkened(0.3), 1.5, true)
	var y := SIZE.y - 10.0
	c.draw_string_outline(FONT, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 20, 5, Color(UiKit.INK, 0.85))
	c.draw_string(FONT, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 20, Color.WHITE)


## 확성기(공지): 나팔 + 손잡이 + 소리 줄 두 개.
static func draw_megaphone(ci: CanvasItem, ctr: Vector2, s: float) -> void:
	var u := s / 44.0
	var p := func(x: float, y: float) -> Vector2: return ctr + Vector2(x, y) * u
	var red := Color(0.90, 0.36, 0.30)
	var cream := Color(0.98, 0.93, 0.82)
	ci.draw_colored_polygon(PackedVector2Array([p.call(-6, 4), p.call(-2, 4), p.call(0, 13), p.call(-4, 13)]), Color(0.45, 0.47, 0.55))
	ci.draw_colored_polygon(PackedVector2Array([p.call(-15, -5), p.call(-8, -5), p.call(-8, 5), p.call(-15, 5)]), cream)
	var horn := PackedVector2Array([p.call(-8, -5), p.call(8, -15), p.call(8, 15), p.call(-8, 5)])
	ci.draw_colored_polygon(horn, red)
	ci.draw_colored_polygon(PackedVector2Array([p.call(0, -10), p.call(8, -15), p.call(8, 15), p.call(0, 10)]), red.darkened(0.12))
	var rim := horn.duplicate()
	rim.append(rim[0])
	ci.draw_polyline(rim, LowpolyBox.edge_color(red), 1.5 * u, true)
	for k in [[-8.0, 12.0], [0.0, 15.0], [8.0, 12.0]]:
		ci.draw_line(p.call(11, k[0] * 0.9), p.call(k[1] + 4.0, k[0] * 1.4), Color.WHITE, 2.5 * u, true)


## 편지 봉투(우편): 봉투 + 접힌 뚜껑 + 금색 봉인.
static func draw_envelope(ci: CanvasItem, ctr: Vector2, s: float) -> void:
	var u := s / 44.0
	var p := func(x: float, y: float) -> Vector2: return ctr + Vector2(x, y) * u
	var paper := Color(0.97, 0.94, 0.86)
	var env := PackedVector2Array([p.call(-17, -11), p.call(17, -11), p.call(17, 12), p.call(-17, 12)])
	ci.draw_colored_polygon(env, paper)
	ci.draw_colored_polygon(PackedVector2Array([p.call(-17, 12), p.call(0, -1), p.call(17, 12)]), paper.darkened(0.08))
	ci.draw_colored_polygon(PackedVector2Array([p.call(-17, -11), p.call(17, -11), p.call(0, 3)]), paper.darkened(0.15))
	var rim := env.duplicate()
	rim.append(rim[0])
	ci.draw_polyline(rim, LowpolyBox.edge_color(paper), 1.5 * u, true)
	ci.draw_polyline(PackedVector2Array([p.call(-17, -11), p.call(0, 3), p.call(17, -11)]), LowpolyBox.edge_color(paper), 1.5 * u, true)
	ci.draw_circle(p.call(0, 2), 4.5 * u, GOLD)
	ci.draw_arc(p.call(0, 2), 4.5 * u, 0, TAU, 12, LowpolyBox.edge_color(GOLD), 1.2 * u, true)


## 각진 톱니바퀴(톱니 8개 + 가운데 구멍).
static func draw_gear(ci: CanvasItem, ctr: Vector2, s: float) -> void:
	var u := s / 44.0
	var col := Color(0.86, 0.89, 0.95)
	var pts := PackedVector2Array()
	for k in 8:
		var a := k * TAU / 8.0
		for d: float in [-0.30, -0.17, 0.17, 0.30]:  # 톱니 하나 = 바깥 두 점 + 안쪽 두 점
			var r := (13.0 if absf(d) > 0.2 else 18.0) * u
			pts.append(ctr + Vector2(cos(a + d), sin(a + d)) * r)
	ci.draw_colored_polygon(pts, col)
	var rim := pts.duplicate()
	rim.append(rim[0])
	ci.draw_polyline(rim, LowpolyBox.edge_color(col), 1.5 * u, true)
	var hole := PackedVector2Array()
	for k in 6:
		var a := k * TAU / 6.0
		hole.append(ctr + Vector2(cos(a), sin(a)) * 6.0 * u)
	ci.draw_colored_polygon(hole, BASE)
	hole.append(hole[0])
	ci.draw_polyline(hole, LowpolyBox.edge_color(col), 1.5 * u, true)


## 위(펼치기)·아래(접기) 꺾쇠 두 겹.
static func draw_chevron(ci: CanvasItem, ctr: Vector2, s: float, down: bool) -> void:
	var k := 1.0 if down else -1.0  # 꼭짓점 방향(아래 = +)
	for dy: float in [-s * 0.22, s * 0.22]:
		var y: float = ctr.y + dy
		ci.draw_polyline(PackedVector2Array([Vector2(ctr.x - s * 0.45, y - k * s * 0.18), Vector2(ctr.x, y + k * s * 0.18),
			Vector2(ctr.x + s * 0.45, y - k * s * 0.18)]), Color.WHITE, 5.0, true)


## 각진 트로피(컵 + 손잡이 + 받침 + 별). ctr = 컵 가운데, s = 전체 높이.
static func draw_trophy(ci: CanvasItem, ctr: Vector2, s: float) -> void:
	var u := s / 44.0
	var p := func(x: float, y: float) -> Vector2: return ctr + Vector2(x, y) * u
	var dark := GOLD.darkened(0.25)
	ci.draw_polyline(PackedVector2Array([p.call(-11, -14), p.call(-19, -14), p.call(-19, -6), p.call(-10, 0)]), dark, 3.5 * u)
	ci.draw_polyline(PackedVector2Array([p.call(11, -14), p.call(19, -14), p.call(19, -6), p.call(10, 0)]), dark, 3.5 * u)
	ci.draw_colored_polygon(PackedVector2Array([p.call(-13, -18), p.call(0, -18), p.call(0, 6), p.call(-8, 2)]), GOLD.lightened(0.15))
	ci.draw_colored_polygon(PackedVector2Array([p.call(0, -18), p.call(13, -18), p.call(8, 2), p.call(0, 6)]), GOLD)
	ci.draw_colored_polygon(PackedVector2Array([p.call(-3, 6), p.call(3, 6), p.call(4, 12), p.call(-4, 12)]), dark)
	ci.draw_colored_polygon(PackedVector2Array([p.call(-11, 12), p.call(11, 12), p.call(12, 18), p.call(-12, 18)]), GOLD.darkened(0.1))
	var rim := PackedVector2Array([p.call(-13, -18), p.call(13, -18), p.call(8, 2), p.call(0, 6), p.call(-8, 2), p.call(-13, -18)])
	ci.draw_polyline(rim, LowpolyBox.edge_color(GOLD), 1.5 * u, true)
	var star := PackedVector2Array()
	for k in 10:
		var r := (5.5 if k % 2 == 0 else 2.4) * u
		var a := -PI / 2.0 + k * PI / 5.0
		star.append(p.call(0, -8) + Vector2(cos(a), sin(a)) * r)
	ci.draw_colored_polygon(star, Color(1, 1, 1, 0.9))


## 두 사람(뒤 사람 + 앞 사람): 각진 머리 + 어깨.
static func draw_friends(ci: CanvasItem, ctr: Vector2, s: float) -> void:
	var u := s / 44.0
	for f in [[Vector2(8, -3), Color(0.55, 0.78, 0.95)], [Vector2(-6, 1), Color(0.98, 0.84, 0.60)]]:
		var o: Vector2 = ctr + f[0] * u
		var col: Color = f[1]
		var head := PackedVector2Array()
		for k in 6:
			var a := k * TAU / 6.0 + PI / 6.0
			head.append(o + Vector2(0, -9) * u + Vector2(cos(a), sin(a)) * 7.0 * u)
		var body := PackedVector2Array([o + Vector2(-12, 16) * u, o + Vector2(-9, 3) * u, o + Vector2(9, 3) * u, o + Vector2(12, 16) * u])
		ci.draw_colored_polygon(body, col.darkened(0.15))
		ci.draw_colored_polygon(head, col)
		var rim := head.duplicate()
		rim.append(rim[0])
		ci.draw_polyline(rim, LowpolyBox.edge_color(col), 1.5 * u, true)


## 선물 상자(뚜껑 + 리본).
static func draw_gift(ci: CanvasItem, ctr: Vector2, s: float) -> void:
	var u := s / 44.0
	var box := Color(0.86, 0.30, 0.34)
	var p := func(x: float, y: float) -> Vector2: return ctr + Vector2(x, y) * u
	ci.draw_colored_polygon(PackedVector2Array([p.call(-14, -4), p.call(0, -4), p.call(0, 17), p.call(-14, 17)]), box.lightened(0.1))
	ci.draw_colored_polygon(PackedVector2Array([p.call(0, -4), p.call(14, -4), p.call(14, 17), p.call(0, 17)]), box)
	ci.draw_colored_polygon(PackedVector2Array([p.call(-17, -11), p.call(17, -11), p.call(17, -3), p.call(-17, -3)]), box.lightened(0.2))
	ci.draw_colored_polygon(PackedVector2Array([p.call(-3, -11), p.call(3, -11), p.call(3, 17), p.call(-3, 17)]), GOLD)
	ci.draw_colored_polygon(PackedVector2Array([p.call(-2, -11), p.call(-13, -20), p.call(-9, -11)]), GOLD)
	ci.draw_colored_polygon(PackedVector2Array([p.call(2, -11), p.call(13, -20), p.call(9, -11)]), GOLD.darkened(0.1))
	ci.draw_polyline(PackedVector2Array([p.call(-17, -11), p.call(17, -11), p.call(17, -3), p.call(14, -3), p.call(14, 17), p.call(-14, 17),
		p.call(-14, -3), p.call(-17, -3), p.call(-17, -11)]), LowpolyBox.edge_color(box), 1.5 * u, true)


## 미션 두루마리(종이 + 체크 두 줄).
static func draw_scroll(ci: CanvasItem, ctr: Vector2, s: float) -> void:
	var u := s / 44.0
	var p := func(x: float, y: float) -> Vector2: return ctr + Vector2(x, y) * u
	var paper := Color(0.96, 0.90, 0.74)
	var roll := Color(0.80, 0.62, 0.38)
	ci.draw_colored_polygon(PackedVector2Array([p.call(-13, -15), p.call(13, -15), p.call(13, 15), p.call(-13, 15)]), paper)
	ci.draw_colored_polygon(PackedVector2Array([p.call(0, -15), p.call(13, -15), p.call(13, 15), p.call(0, 15)]), paper.darkened(0.06))
	for y in [-17.0, 13.0]:
		ci.draw_colored_polygon(PackedVector2Array([p.call(-16, y), p.call(16, y), p.call(16, y + 5), p.call(-16, y + 5)]), roll)
	ci.draw_polyline(PackedVector2Array([p.call(-13, -15), p.call(13, -15), p.call(13, 15), p.call(-13, 15), p.call(-13, -15)]),
		LowpolyBox.edge_color(paper), 1.5 * u, true)
	var green := Color(0.20, 0.62, 0.32)
	for y in [-6.0, 5.0]:
		ci.draw_polyline(PackedVector2Array([p.call(-9, y), p.call(-6, y + 3), p.call(-1, y - 3)]), green, 2.5 * u, true)
		ci.draw_line(p.call(2, y), p.call(9, y), roll.darkened(0.2), 2.0 * u, true)


## 저울(거래소): 기둥 + 가로대 + 양쪽 접시(왼쪽 금화, 오른쪽 보석).
static func draw_scales(ci: CanvasItem, ctr: Vector2, s: float) -> void:
	var u := s / 44.0
	var p := func(x: float, y: float) -> Vector2: return ctr + Vector2(x, y) * u
	var wood := Color(0.80, 0.62, 0.38)
	var metal := Color(0.86, 0.89, 0.95)
	ci.draw_colored_polygon(PackedVector2Array([p.call(-2, -14), p.call(2, -14), p.call(3, 14), p.call(-3, 14)]), wood)
	ci.draw_colored_polygon(PackedVector2Array([p.call(-10, 14), p.call(10, 14), p.call(12, 19), p.call(-12, 19)]), wood.darkened(0.15))
	ci.draw_line(p.call(-17, -12), p.call(17, -12), metal, 3.0 * u, true)
	ci.draw_circle(p.call(0, -15), 3.0 * u, GOLD)
	for side in [-1.0, 1.0]:
		var x: float = 14.0 * side
		ci.draw_line(p.call(x, -12), p.call(x - 6, 2), metal, 1.5 * u, true)
		ci.draw_line(p.call(x, -12), p.call(x + 6, 2), metal, 1.5 * u, true)
		var pan := PackedVector2Array([p.call(x - 9, 2), p.call(x + 9, 2), p.call(x + 5, 7), p.call(x - 5, 7)])
		ci.draw_colored_polygon(pan, metal.darkened(0.1))
		var rim := pan.duplicate()
		rim.append(rim[0])
		ci.draw_polyline(rim, LowpolyBox.edge_color(metal), 1.2 * u, true)
	ci.draw_circle(p.call(-14, -1), 4.0 * u, GOLD)
	ci.draw_arc(p.call(-14, -1), 4.0 * u, 0, TAU, 12, LowpolyBox.edge_color(GOLD), 1.2 * u, true)
	var gem := PackedVector2Array([p.call(14, -6), p.call(18, -2), p.call(14, 2), p.call(10, -2)])
	ci.draw_colored_polygon(gem, Color(0.40, 0.75, 0.98))

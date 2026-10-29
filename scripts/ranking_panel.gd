extends "res://scripts/ui_window.gd"
## [랭킹] 시트(온라인 전용, 서버 GET /v1/ranking/:board — server/src/ranking.ts). 오른쪽 아래 메뉴(side_menu.gd) [랭킹]이 연다.
## 하위 탭 [스테이지][전투력][길드]. 오른쪽 위 [X]나 바깥(배경) 탭으로 닫는다.
## 목록 = 상위 50(1~3위 메달, 길드는 보상 순위까지 100), 맨 아래 고정 줄 = 내 순위(길드 보드는 내 길드). 받은 목록은 보드마다 CACHE_SEC 동안 다시 쓴다.
## 길드 보드(2026-10-29) = 이번 주 드래곤 보스 길드 총 피해량 순 + 주간 보상 카드(서버 season: 남은 시간·순위 구간·상자 확률).

const Lang := preload("res://scripts/lang.gd")

const GameData := preload("res://scripts/game_data.gd")
const GuildPanel := preload("res://scripts/guild_panel.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

static var SUBTABS := [["stage", Lang.t("ranking_panel.subtabs")], ["power", Lang.t("ranking_panel.subtabs_2")], ["guild", Lang.t("ranking_panel.subtabs_3")]]
static var HEAD := {
	"stage": Lang.t("ranking_panel.head.stage"),
	"power": Lang.t("ranking_panel.head.power"),
	"guild": Lang.t("ranking_panel.head.guild"),
}
const MEDALS := [Color(0.98, 0.76, 0.18), Color(0.74, 0.78, 0.84), Color(0.80, 0.52, 0.28)]
const SUB := Color(0.16, 0.18, 0.24, 0.62)
const ME_BG := Color(0.98, 0.80, 0.42, 0.85)
const ROW_BG := Color(1, 1, 1, 0.75)
const CACHE_SEC := 30.0
const CLOSE_PX := 56.0  # 오른쪽 위 닫기 버튼

var tab := "stage"
var body: VBoxContainer
var scroll: ScrollContainer
var me_box: VBoxContainer  # 아래 고정 줄
var buttons := {}  # 테스트용: "tab:stage" …
var data := {}  # 보드 → 서버 응답
var _got := {}  # 보드 → 받은 시각(ms)
var _loading := {}  # 보드 → 요청 중
var _failed := {}  # 보드 → 마지막 요청 실패


func _ready() -> void:
	Net.booted.connect(_on_booted)  # 로딩 화면이 미리 받은 보드 셋 — 열자마자 보인다(CACHE_SEC이 지나면 열 때 새로 받는다)
	_on_booted(Net.boot)
	_build_window(0, 10)
	dialog.get_parent().color = Color(0, 0, 0, 0)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()  # 제목 가운데 + 오른쪽 위 닫기(X)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(CLOSE_PX, 0)
	head.add_child(pad)
	var title := _title(Lang.t("ranking_panel.ready"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var x := Button.new()
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(CLOSE_PX, CLOSE_PX)
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiKit.apply_button(x, UiKit.STEEL, 10.0)
	x.pressed.connect(close)
	var face := Control.new()
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.draw.connect(func():
		var c := face.size / 2.0
		var r := CLOSE_PX * 0.2
		for d in [Vector2(r, r), Vector2(r, -r)]:
			face.draw_line(c - d, c + d, Color.WHITE, 5.0, true))
	x.add_child(face)
	head.add_child(x)
	buttons["close"] = x
	content.add_child(head)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for t in SUBTABS:
		var b := _button(t[1], UiKit.STEEL, 24)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 54)
		b.pressed.connect(func(): _pick(t[0]))
		tabs.add_child(b)
		buttons["tab:" + t[0]] = b
	content.add_child(tabs)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	me_box = VBoxContainer.new()
	me_box.add_theme_constant_override("separation", 4)
	content.add_child(me_box)
	_fit_sheet()


func _fit() -> void:
	_fit_sheet()


func board() -> String:
	return tab


func _on_open() -> void:
	_show()


func _pick(t: String) -> void:
	tab = t
	_show()


## 보이는 보드를 그린다(없거나 오래됐으면 받으러 간다).
func _show() -> void:
	var b := board()
	if not _loading.get(b, false) and (not data.has(b) or Time.get_ticks_msec() - int(_got.get(b, 0)) > CACHE_SEC * 1000.0):
		fetch(b)
	_rebuild()


func fetch(b: String) -> void:
	if not Net.is_online() or not Net.up:
		_failed[b] = true
		return
	_loading[b] = true
	_failed[b] = false
	Net.send("GET", "/v1/ranking/" + b, null, func(d): _on_data(b, d), func(): _on_fail(b))


func _on_booted(d: Dictionary) -> void:
	for t in SUBTABS:
		var v = d.get("ranking_" + t[0])
		if v is Dictionary and not _loading.get(t[0], false):
			data[t[0]] = v
			_got[t[0]] = Time.get_ticks_msec()


func _on_data(b: String, d: Dictionary) -> void:
	_loading[b] = false
	data[b] = d
	_got[b] = Time.get_ticks_msec()
	if visible and b == board():
		_rebuild()


func _on_fail(b: String) -> void:
	_loading[b] = false
	_failed[b] = true
	if visible and b == board():
		_rebuild()


func _rebuild() -> void:
	for k in buttons:
		if k.begins_with("tab:"):
			UiKit.apply_button(buttons[k], UiKit.AMBER if k == "tab:" + tab else UiKit.STEEL, 14.0)
	for c in body.get_children():
		c.queue_free()
	for c in me_box.get_children():
		c.queue_free()
	var b := board()
	body.add_child(_label(HEAD[b], 20, SUB))
	var d: Dictionary = data.get(b, {})
	if b == "guild" and d.get("season") is Dictionary:
		body.add_child(_season_card(d.season))
	if d.is_empty():
		var msg := Lang.t("ranking_panel.rebuild.msg")
		if not Net.is_online():
			msg = Lang.t("ranking_panel.rebuild")
		elif _failed.get(b, false):
			msg = Lang.t("ranking_panel.rebuild_2")
		body.add_child(_spacer(40))
		body.add_child(_label(msg, 26, SUB))
		return
	var top: Array = d.get("top", [])
	if top.is_empty():
		body.add_child(_spacer(40))
		body.add_child(_label(Lang.t("ranking_panel.rebuild_3"), 26, SUB))
	for e in top:
		body.add_child(_row(e, b))
	var me = d.get("me")
	me_box.add_child(_label(Lang.t("ranking_panel.rebuild_4") if b == "guild" else Lang.t("ranking_panel.rebuild_5"), 20, SUB, HORIZONTAL_ALIGNMENT_LEFT))
	if me is Dictionary:
		me_box.add_child(_row(me, b))
	else:
		var why := (Lang.t("ranking_panel.rebuild.why") if not (d.get("season") is Dictionary and d.season.get("in_guild", false)) else Lang.t("ranking_panel.rebuild_8")) if b == "guild" else (Lang.t("ranking_panel.rebuild_6") if b == "power" else Lang.t("ranking_panel.rebuild_7"))
		var card := _card(ROW_BG)
		card.get_child(0).add_child(_label(why, 22, SUB))
		me_box.add_child(card)


func _row(e: Dictionary, b: String) -> Control:
	var mine: bool = e.get("me", false)
	var card := _card(ME_BG if mine else ROW_BG)
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	card.get_child(0).add_child(r)
	r.add_child(_medal(int(e.rank)))
	if b == "guild":
		var em := Control.new()
		em.custom_minimum_size = Vector2(52, 52)
		em.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		em.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ei := int(e.get("emblem", 0))
		em.draw.connect(func(): GuildPanel.draw_emblem(em, em.size / 2.0, 48.0, ei))
		r.add_child(em)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	var nl := _label(str(e.name), 24, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	nl.clip_text = true
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(nl)
	if mine:
		var tag := _label(Lang.t("ranking_panel.row") if b == "guild" else Lang.t("ranking_panel.row_2"), 16, Color.WHITE)
		tag.custom_minimum_size = Vector2(0, 26)
		tag.add_theme_stylebox_override("normal", UiKit.panel(Color(0.85, 0.42, 0.12), 6.0, 4))
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_row.add_child(tag)
	v.add_child(name_row)
	var sub := ""
	if b == "guild":
		sub = Lang.t("ranking_panel.row_5") % [int(e.get("level", 1)), int(e.get("members", 0))]
	elif e.has("guild"):
		sub = Lang.t("ranking_panel.row_4") + str(e.guild)
	if sub != "":
		v.add_child(_label(sub, 18, SUB, HORIZONTAL_ALIGNMENT_LEFT))
	r.add_child(v)
	var val := _label(value_text(b, int(e.value)), 26, HudScript.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(val)
	return card


static func value_text(b: String, v: int) -> String:
	match b:
		"stage":
			return GameData.round_label(v)
		_:
			return UiKit.commas(v)  # 전투력, 길드 = 이번 주 드래곤 피해


## 길드 랭킹 주간 보상 카드: 남은 시간 + 순위 구간별 상자(등급 확률).
func _season_card(season: Dictionary) -> Control:
	var card := _card(ROW_BG)
	var v: VBoxContainer = card.get_child(0)
	v.add_theme_constant_override("separation", 2)
	var left := maxi(0, int(float(season.get("ends_at", 0)) - (Time.get_unix_time_from_system() + Economy.clock_offset)))
	v.add_child(_label(Lang.t("ranking_panel.season_card"), 22, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	v.add_child(_label(Lang.t("ranking_panel.season_card_2") % [left / 86400, left % 86400 / 3600, left % 3600 / 60], 18, SUB, HORIZONTAL_ALIGNMENT_LEFT))
	var boxes: Dictionary = season.get("boxes", {}) if season.get("boxes") is Dictionary else {}
	for band in season.get("rewards", []):
		var from := int(band.get("from", 1))
		var to := int(band.get("to", 1))
		var where := (Lang.t("ranking_panel.season_card_3") % from) if from == to else (Lang.t("ranking_panel.season_card_4") % [from, to])
		for k in band.get("reward", {}):
			var id := str(k).trim_prefix(LiveOps.BOX_PREFIX)
			var odds: Array = []
			var w: Dictionary = boxes.get(id, {}) if boxes.get(id) is Dictionary else {}
			for g in w:
				var pct := float(w[g])
				odds.append("%s %s%%" % [g, str(int(pct)) if pct == floorf(pct) else String.num(pct, 2)])
			var line := _label(Lang.t("ranking_panel.season_card_5") % [where, LiveOps.BOX_NAMES.get(id, id), int(band.reward[k])], 20, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
			v.add_child(line)
			if not odds.is_empty():
				v.add_child(_label("    " + " · ".join(odds), 16, SUB, HORIZONTAL_ALIGNMENT_LEFT))
	return card


## 순위: 1~3위는 메달(각진 원 + 리본), 그 밖은 숫자.
func _medal(rank: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(56, 52)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func(): _draw_medal(c, rank))
	return c


func _draw_medal(c: Control, rank: int) -> void:
	var ctr := c.size / 2.0
	var font: Font = FONT
	if rank <= 3:
		var col: Color = MEDALS[rank - 1]
		var rib := Color(0.80, 0.24, 0.22) if rank == 1 else Color(0.24, 0.42, 0.76)
		c.draw_colored_polygon(PackedVector2Array([ctr + Vector2(-14, -4), ctr + Vector2(-4, -4), ctr + Vector2(-10, 24), ctr + Vector2(-16, 18)]), rib)
		c.draw_colored_polygon(PackedVector2Array([ctr + Vector2(4, -4), ctr + Vector2(14, -4), ctr + Vector2(16, 18), ctr + Vector2(10, 24)]), rib.darkened(0.15))
		var pts := PackedVector2Array()
		for k in 8:
			var a := -PI / 2.0 + k * TAU / 8.0 + TAU / 16.0
			pts.append(ctr + Vector2(0, -4) + Vector2(cos(a), sin(a)) * 18.0)
		c.draw_colored_polygon(pts, col)
		var hi := PackedVector2Array([pts[6], pts[7], pts[0], ctr + Vector2(0, -4)])
		c.draw_colored_polygon(hi, col.lightened(0.25))
		var rim := pts.duplicate()
		rim.append(rim[0])
		c.draw_polyline(rim, LowpolyBox.edge_color(col), 2.0, true)
		c.draw_string(font, Vector2(0, ctr.y + 4), str(rank), HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 22, HudScript.INK)
	else:
		c.draw_string(font, Vector2(0, ctr.y + 9), str(rank), HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 26 if rank < 100 else 20, HudScript.INK)


func _card(color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.panel(color, 12.0, 10))
	var v := VBoxContainer.new()
	p.add_child(v)
	return p


func _spacer(h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s

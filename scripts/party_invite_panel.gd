extends "res://scripts/ui_window.gd"
## 파티 초대 창(사용자 2026-10-15 "그냥 초대도되고"): 파티 카드 [초대] → 친구·길드원 목록(접속 중 먼저) → 사람마다 [초대].
## 접속 중이 아닌 사람은 버튼이 꺼져 있다. [초대]는 누르는 즉시 '초대함'으로 바뀌고(빠른 두 번 탭도 한 번만) 서버가 거절하면 되돌리고 이유를 보인다.
## 이미 파티에 있는 사람은 '파티원'. 받은 사람에게는 수락·거절 창이 뜬다(party_overlay.gd).

const Lang := preload("res://scripts/lang.gd")

const SOFT_INK := Color(0.16, 0.18, 0.24, 0.62)
const BAD_INK := Color(0.80, 0.22, 0.18)
const ONLINE := Color(0.20, 0.55, 0.25)

var list: VBoxContainer
var scroll: ScrollContainer
var status_label: Label
var buttons := {}  # 플레이어 id → [초대] 버튼(테스트)
var _sent := {}  # 이번에 초대한 id
var _ask := 0


func _ready() -> void:
	_build_window(600, 12)
	layer = 3  # 던전 시트(2) 위
	content.add_child(_title(Lang.t("party_invite_panel.ready")))
	content.add_child(_label(Lang.t("party_invite_panel.ready_2"), 22, SOFT_INK))
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	status_label = _label("", 22, BAD_INK)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(540, 0)
	content.add_child(status_label)
	var close_button := _button(Lang.t("party_invite_panel.ready_3"), UiKit.STEEL)
	close_button.pressed.connect(close)
	content.add_child(close_button)


func _on_open() -> void:
	_sent = {}
	status_label.text = ""
	_show([])
	status_label.text = Lang.t("party_invite_panel.on_open")
	status_label.add_theme_color_override("font_color", SOFT_INK)
	_ask += 1
	var ask := _ask
	Party.invitable(func(people):
		if ask != _ask or not is_inside_tree():
			return
		if people == null:
			_status(Lang.t("party_invite_panel.on_open_2"), BAD_INK)
			return
		_status("" if not people.is_empty() else Lang.t("party_invite_panel.on_open_3"), SOFT_INK)
		_show(people))
	_fit()


func _status(text: String, color: Color) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", color)
	_fit()


func _show(people: Array) -> void:
	for c in list.get_children():
		c.queue_free()
	buttons = {}
	for p in people:
		list.add_child(_row(p))


func _row(p: Dictionary) -> Control:
	var id := str(p.get("id", ""))
	var on: bool = p.get("online", false)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(14, 14)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel", UiKit.panel(ONLINE if on else Color(0.6, 0.6, 0.6), 7.0, 0))
	row.add_child(dot)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	var name := _label(str(p.get("name", "")), 24, HudScript.INK)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name.clip_text = true
	col.add_child(name)
	var tags := []
	if p.get("friend", false):
		tags.append(Lang.t("party_invite_panel.row"))
	if p.get("guild", false):
		tags.append(Lang.t("party_invite_panel.row_2"))
	var sub := _label("%s · %s" % [" · ".join(tags), Lang.t("party_invite_panel.row_3") if on else Lang.t("party_invite_panel.row_4")], 18, SOFT_INK)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(sub)
	var b := _button(Lang.t("party_invite_panel.row_5"))
	b.custom_minimum_size = Vector2(130, 52)
	b.add_theme_font_size_override("font_size", 22)
	if p.get("member", false):
		b.text = Lang.t("party_invite_panel.row_6")
		b.disabled = true
	elif p.get("locked", false):  # 가이드에서 아직 파티 던전에 닿지 않은 성주
		b.text = Lang.t("party_invite_panel.row_7")
		b.disabled = true
	elif not on:
		b.disabled = true
	b.pressed.connect(_invite.bind(id, b))
	row.add_child(b)
	buttons[id] = b
	return row


func _invite(id: String, b: Button) -> void:
	if b.disabled or _sent.has(id):
		return
	_sent[id] = true
	b.disabled = true
	b.text = Lang.t("party_invite_panel.invite")
	status_label.text = ""
	Party.invite(id, func(ok, text):
		if ok or not is_instance_valid(b):
			return
		_sent.erase(id)
		b.disabled = false
		b.text = Lang.t("party_invite_panel.invite_2")
		_status(text, BAD_INK))

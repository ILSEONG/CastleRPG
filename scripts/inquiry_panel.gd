extends "res://scripts/ops_sheet.gd"
## 문의 창(2026-10-14, 설정 창 [문의하기]). 문의 이메일 대신 게임 안에서 보낸다(LiveOps.send_inquiry → POST /v1/inquiry, 서버 inquiry.ts).
## 위: 분류(계정·로그인 / 결제·상점 / 버그·오류 / 건의 / 기타) + 내용 + [보내기]. 닉네임·로그인·버전·기기는 저절로 붙는다(아래 안내 줄).
## 아래: 내 문의 목록 — 분류·상태(답변 대기 / 답변 완료 / 종료)·보낸 때, 답변이 있으면 그 글. 답변은 우편([문의 답변])으로도 온다.
## [보내기]는 곧바로 목록에 들어가고 칸이 비워진다. 서버가 거절하면 목록에서 빠지고 쓴 글이 칸에 돌아온다.

const CATEGORIES := [["account", "계정·로그인"], ["payment", "결제·상점"], ["bug", "버그·오류"], ["suggest", "건의"], ["other", "기타"]]
const STATUS := {"open": ["답변 대기", Color(0.86, 0.55, 0.16)], "answered": ["답변 완료", Color(0.30, 0.60, 0.36)], "closed": ["종료", Color(0.50, 0.52, 0.58)]}
const MAX_LEN := 1000

var category := "bug"
var input: TextEdit
var send_button: Button
var cat_buttons := {}
var list: VBoxContainer
var _sig := ""


func _ready() -> void:
	_build("문의하기")
	var v := _card(Color(1.0, 0.97, 0.88, 0.95))
	var cats := GridContainer.new()
	cats.columns = 3
	cats.add_theme_constant_override("h_separation", 6)
	cats.add_theme_constant_override("v_separation", 6)
	for c in CATEGORIES:
		var b := _button(c[1], UiKit.STEEL, 22)
		b.custom_minimum_size = Vector2(0, 50)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): pick(c[0]))
		cats.add_child(b)
		cat_buttons[c[0]] = b
		buttons["cat:" + c[0]] = b
	v.add_child(cats)
	input = TextEdit.new()
	input.placeholder_text = "무엇이 궁금하거나 불편하셨나요? 자세히 적어 주시면 빨리 도와드릴 수 있어요"
	input.custom_minimum_size = Vector2(0, 200)
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.add_theme_font_size_override("font_size", 23)
	input.add_theme_color_override("font_color", HudScript.INK)
	input.add_theme_color_override("font_placeholder_color", SUB)
	input.add_theme_stylebox_override("normal", UiKit.panel(Color.WHITE, 10.0, 12))
	input.add_theme_stylebox_override("focus", UiKit.panel(Color.WHITE, 10.0, 12))
	input.text_changed.connect(func():
		if input.text.length() > MAX_LEN:
			input.text = input.text.left(MAX_LEN)
			input.set_caret_line(input.get_line_count() - 1)
			input.set_caret_column(input.get_line(input.get_line_count() - 1).length()))
	v.add_child(input)
	v.add_child(_wrap("닉네임·친구 코드·로그인 방식·게임 버전·기기 정보가 함께 전달됩니다. 답변은 우편으로 알려 드려요.", 20, SUB))
	send_button = _button("보내기", HudScript.ACCENT, 24)
	send_button.custom_minimum_size = Vector2(0, 56)
	send_button.pressed.connect(send)
	v.add_child(send_button)
	buttons["send"] = send_button
	body.add_child(_label("내 문의", 26, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	body.add_child(list)
	LiveOps.changed.connect(func():
		if visible:
			_rebuild())
	LiveOps.inquiry_failed.connect(_on_failed)
	pick(category)


func _on_open() -> void:
	LiveOps.fetch_inquiries()
	_sig = ""
	_rebuild()


func close() -> void:
	DisplayServer.virtual_keyboard_hide()
	input.release_focus()
	super.close()


func pick(c: String) -> void:
	category = c
	for k in cat_buttons:
		UiKit.apply_button(cat_buttons[k], HudScript.ACCENT if k == c else UiKit.STEEL, 10.0)


func send() -> void:
	if LiveOps.send_inquiry(category, input.text):
		input.text = ""
		input.release_focus()
		DisplayServer.virtual_keyboard_hide()
		scroll.scroll_vertical = 0


## 못 보냈으면 쓴 글을 되돌린다(그사이 새로 쓴 글이 있으면 그대로 둔다).
func _on_failed(c: String, text: String) -> void:
	if input.text.strip_edges() == "":
		input.text = text
		pick(c)


func _rebuild() -> void:
	var sig := str(LiveOps.inquiries.map(func(q): return [q.get("id"), q.get("status"), q.get("answer", "")])) + str(Net.is_online())
	if sig == _sig:
		return
	_sig = sig
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	if LiveOps.inquiries.is_empty():
		list.add_child(_wrap("보낸 문의가 없어요" if Net.is_online() else "문의는 온라인에서만 보낼 수 있어요", 24, SUB, HORIZONTAL_ALIGNMENT_CENTER))
		return
	var now := Economy.time_now()
	var names := {}
	for c in CATEGORIES:
		names[c[0]] = c[1]
	for q in LiveOps.inquiries:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiKit.panel(Color(1, 1, 1, 0.85), 12.0, 16))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(card)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		card.add_child(v)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var st: Array = STATUS.get(str(q.get("status", "open")), STATUS.open)
		var tag := PanelContainer.new()
		tag.add_theme_stylebox_override("panel", UiKit.panel(st[1], 8.0, 6))
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tag.add_child(_label(st[0], 20, Color.WHITE))
		row.add_child(tag)
		row.add_child(_wrap(str(names.get(str(q.get("category", "")), "문의")), 24))
		row.add_child(_label(ago(float(q.get("at", now)), now), 20, SUB, HORIZONTAL_ALIGNMENT_RIGHT))
		v.add_child(row)
		v.add_child(_wrap(str(q.get("body", "")), 22))
		var a := str(q.get("answer", ""))
		if a != "":
			var ans := PanelContainer.new()
			ans.add_theme_stylebox_override("panel", UiKit.panel(Color(0.90, 0.96, 0.90, 1.0), 10.0, 12))
			var av := VBoxContainer.new()
			av.add_child(_label("운영자 답변", 20, Color(0.20, 0.45, 0.24)))
			av.add_child(_wrap(a, 22))
			ans.add_child(av)
			v.add_child(ans)

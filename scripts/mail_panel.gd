extends "res://scripts/ops_sheet.gd"
## 우편함 창(2026-10-12, 오른쪽 아래 메뉴 [우편]). 운영자가 보낸 우편(점검 보상·문의 보상 등, LiveOps.mails — GET /v1/mail)을
## 새것 순으로 보인다. 줄 = 제목·보낸 때·남은 기간, 본문, 보상 한 줄, [받기]. 위 [모두 받기]는 한 번에 전부.
## 받기는 곧바로 반영된다(LiveOps.claim — 목록에서 빠지고 재화가 바로 오른다, 서버가 거절하면 되돌린다).

var claim_all: Button
var count_label: Label
var _sig := ""


func _ready() -> void:
	_build("우편함")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	count_label = _label("", 22, SUB, HORIZONTAL_ALIGNMENT_LEFT)
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(count_label)
	claim_all = _button("모두 받기", HudScript.ACCENT, 24)
	claim_all.custom_minimum_size = Vector2(180, 54)
	claim_all.pressed.connect(func(): LiveOps.claim())
	row.add_child(claim_all)
	buttons["claim_all"] = claim_all
	content.add_child(row)
	content.move_child(row, 1)
	LiveOps.changed.connect(func():
		if visible:
			_rebuild())
	_rebuild()


func _on_open() -> void:
	LiveOps.fetch_mail()
	_sig = ""
	_rebuild()


func _rebuild() -> void:
	var sig := str(LiveOps.mails.map(func(m): return m.id))
	count_label.text = "받을 우편 %d개" % LiveOps.mails.size() if not LiveOps.mails.is_empty() else ""
	claim_all.disabled = LiveOps.mails.is_empty()
	claim_all.modulate.a = 0.5 if LiveOps.mails.is_empty() else 1.0
	if sig == _sig:
		return
	_sig = sig
	_clear_body()
	if LiveOps.mails.is_empty():
		body.add_child(_wrap("받을 우편이 없습니다" if Net.is_online() else "우편함은 온라인에서만 쓸 수 있습니다", 26, SUB, HORIZONTAL_ALIGNMENT_CENTER))
		return
	var now := Economy.time_now()
	for m in LiveOps.mails:
		var id := int(m.id)
		var v := _card()
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 10)
		top.add_child(_wrap(str(m.title), 28))
		var left := ""
		if m.get("expires") != null:
			var d := (float(m.expires) - now) / 86400.0
			left = "%d일 남음" % ceili(d) if d >= 1.0 else "%d시간 남음" % maxi(1, ceili(d * 24.0))
		top.add_child(_label(ago(float(m.get("at", now)), now) + ("" if left == "" else "\n" + left), 20, SUB, HORIZONTAL_ALIGNMENT_RIGHT))
		v.add_child(top)
		if str(m.get("body", "")) != "":
			v.add_child(_wrap(str(m.body), 23))
		var bottom := HBoxContainer.new()
		bottom.add_theme_constant_override("separation", 10)
		var rw = m.get("reward")
		var text := LiveOps.reward_text(rw) if rw is Dictionary else ""
		bottom.add_child(_wrap("보상: " + text if text != "" else "보상 없음", 23, Color(0.55, 0.36, 0.08) if text != "" else SUB))
		var b := _button("받기" if text != "" else "확인", HudScript.ACCENT if text != "" else UiKit.STEEL, 24)
		b.custom_minimum_size = Vector2(120, 54)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func(): LiveOps.claim([id]))
		bottom.add_child(b)
		buttons["claim:%d" % id] = b
		v.add_child(bottom)

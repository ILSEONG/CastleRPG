extends "res://scripts/ops_sheet.gd"
## 공지사항 창(2026-10-12, 오른쪽 아래 메뉴 [공지]). 서버 공지(LiveOps.notices — GET /v1/notices, 관리자 창에서 쓴다)를
## 고정 먼저·새것 순으로 보인다. 줄 = [종류 꼬리표] 제목 · 날짜, 누르면 본문을 펼치고 접는다(처음엔 맨 위 하나만 펼친다).
## 열면 본 것으로 저장한다(LiveOps.mark_seen — [공지] 빨간 점과 성 화면 자동 띄우기가 꺼진다).
## 새 공지가 있으면 로딩이 끝난 뒤 한 번 저절로 열린다(_process). 가이드 중인 새 성주는 첫 미션(1-1)을 마친 뒤부터.

static var KINDS := {"notice": [Lang.t("notice_panel.kinds"), Color(0.33, 0.47, 0.72)], "event": [Lang.t("notice_panel.kinds_2"), Color(0.86, 0.45, 0.20)],
	"update": [Lang.t("notice_panel.kinds_3"), Color(0.30, 0.60, 0.36)], "maintenance": [Lang.t("notice_panel.kinds_4"), Color(0.62, 0.38, 0.78)]}

const PreloaderScript := preload("res://scripts/preloader.gd")
const AUTO_DELAY_SEC := 1.5  # 로딩 화면이 걷히고 이만큼 뒤(다른 창이 없을 때) 새 공지를 띄운다

var open_ids := {}  # 펼친 공지 id → true
var auto_shown := false  # 이번 실행에서 새 공지로 한 번 띄웠다
var _sig := ""
var _auto_t := 0.0


func _ready() -> void:
	_build(Lang.t("notice_panel.ready"))
	LiveOps.changed.connect(func():
		if visible:
			_rebuild())
	_rebuild()


## 새 공지(안 본 것)가 있으면 성 화면이 뜬 뒤 한 번 띄운다 — 로딩이 끝나고, 방치 중이고, 다른 창(방치 보상 개요 등)이 없을 때.
func _process(delta: float) -> void:
	if auto_shown or visible:
		return
	if not (PreloaderScript.done and Net.ready_once and LiveOps.notices_loaded and GameState.mode == GameState.Mode.IDLE) or _another_window_open() \
			or not Tutorial.ui_shown("notice_auto"):  # 가이드 중이면 1-1 클리어(첫 미션) 뒤부터(초반 단순화 2026-10-23)
		_auto_t = 0.0
		return
	_auto_t += delta
	if _auto_t < AUTO_DELAY_SEC:
		return
	auto_shown = true
	if LiveOps.has_unseen():
		open()


func _on_open() -> void:
	open_ids = {}
	if not LiveOps.notices.is_empty():
		open_ids[int(LiveOps.notices[0].id)] = true
	LiveOps.fetch_notices()
	LiveOps.mark_seen()
	_sig = ""
	_rebuild()


func _rebuild() -> void:
	var sig := str(LiveOps.notices.map(func(n): return [n.id, n.title, n.get("body", ""), n.get("pinned", false)])) + str(open_ids.keys())
	if sig == _sig:
		return
	_sig = sig
	_clear_body()
	if LiveOps.notices.is_empty():
		body.add_child(_wrap(Lang.t("notice_panel.rebuild") if Net.is_online() else Lang.t("notice_panel.rebuild_2"), 26, SUB, HORIZONTAL_ALIGNMENT_CENTER))
		return
	var now := Economy.time_now()
	for n in LiveOps.notices:
		var id := int(n.id)
		var v := _card(Color(1.0, 0.96, 0.84, 0.95) if n.get("pinned", false) else Color(1, 1, 1, 0.85))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var k: Array = KINDS.get(str(n.get("kind", "notice")), KINDS.notice)
		var tag := PanelContainer.new()
		tag.add_theme_stylebox_override("panel", UiKit.panel(k[1], 8.0, 6))
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tag.add_child(_label((Lang.t("notice_panel.rebuild_3") if n.get("pinned", false) else "") + k[0], 20, Color.WHITE))
		row.add_child(tag)
		var t := _wrap(str(n.title), 26)
		row.add_child(t)
		row.add_child(_label(ago(float(n.get("at", now)), now), 20, SUB, HORIZONTAL_ALIGNMENT_RIGHT))
		v.add_child(row)
		var b := str(n.get("body", ""))
		if open_ids.has(id) and b != "":
			v.add_child(_wrap(b, 24))
		var tap := Button.new()  # 카드 전체를 누르면 펼치기·접기(투명 단추)
		tap.flat = true
		tap.focus_mode = Control.FOCUS_NONE
		tap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tap.pressed.connect(func(): toggle(id))
		v.get_parent().add_child(tap)
		buttons["notice:%d" % id] = tap


func toggle(id: int) -> void:
	if open_ids.has(id):
		open_ids.erase(id)
	else:
		open_ids[id] = true
	_rebuild()

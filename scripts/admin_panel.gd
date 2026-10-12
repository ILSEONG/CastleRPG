extends "res://scripts/ops_sheet.gd"
## 관리자 창(2026-10-12, 슈퍼관리자만 — 설정 창 [운영 관리]). 서버 운영 도구(server/src/live_ops.ts /v1/admin/*)를 DB를 만지지 않고 쓴다.
## 탭 넷:
##  상태 — 점검 켜기/끄기(안내 문구·끝나는 예정 분), 최소 버전·스토어 주소(낮은 앱은 업데이트 안내만 보인다).
##  공지 — 제목·본문·종류·고정으로 등록, 목록에서 [수정]·[숨기기]/[보이기].
##  우편 — 받는 사람(all = 모두, 아니면 친구 코드)·제목·본문·보상·기간(일)·새 계정도 받기로 보내기, 목록(받은 사람 수)에서 [회수].
##  쿠폰 — 코드·보상·최대 사용 수(빈칸 = 무제한)·기간(일, 빈칸 = 무기한)·메모로 만들기, 목록(사용 수)에서 [끄기]/[켜기].
## 모두에게 영향을 주는 버튼(점검 켜기·모두에게 보내기)은 한 번 더 눌러야 실행된다(4초 안).
## 보상 = 골드·다이아·다이아 모집권·목재·석재·식량·던전 열쇠 셋·영웅(+장 수)·장비(등급 + 개수) — 넣는 값 그대로(서버가 범위를 본다).

const GameData := preload("res://scripts/game_data.gd")
const TABS := [["status", "상태"], ["notice", "공지"], ["mail", "우편"], ["coupon", "쿠폰"]]
const KIND_ITEMS := [["notice", "공지"], ["event", "이벤트"], ["update", "업데이트"], ["maintenance", "점검"]]
const REWARD_FIELDS := [["gold", "골드"], ["diamonds", "다이아"], ["tickets", "모집권"], ["wood", "목재"], ["stone", "석재"], ["food", "식량"],
	["keys_gold", "골드 열쇠"], ["keys_equip", "장비 열쇠"], ["keys_ticket", "모집권 열쇠"]]
const GRADES := ["N", "R", "SR", "SSR", "UR", "LR"]
const ARM_SEC := 4.0

var tab := "status"
var ops := {}  # GET /v1/admin/ops 응답
var f := {}  # 입력 칸(이름 → LineEdit·TextEdit·OptionButton·Button)
var editing_notice := 0  # 수정 중인 공지 id(0 = 새 공지)
var _armed := ""  # 한 번 누른 위험 버튼 이름
var _armed_button: Button
var _armed_text := ""
var _armed_left := 0.0


func _ready() -> void:
	_build("운영 관리")
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for t in TABS:
		var b := _button(t[1], UiKit.STEEL, 24)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 54)
		b.pressed.connect(func(): pick(t[0]))
		tabs.add_child(b)
		buttons["tab:" + t[0]] = b
	content.add_child(tabs)
	content.move_child(tabs, 1)
	_rebuild()


func _on_open() -> void:
	fetch()
	_rebuild()


func pick(t: String) -> void:
	tab = t
	editing_notice = 0
	_disarm()
	_rebuild()


func fetch() -> void:
	if Net.up:
		Net.send("GET", "/v1/admin/ops", null, func(d: Dictionary):
			ops = d
			_rebuild(), func(): Economy.notice.emit("운영 정보를 받지 못했습니다(관리자만 쓸 수 있습니다)"))


func _process(delta: float) -> void:
	if _armed_left > 0.0:
		_armed_left -= delta
		if _armed_left <= 0.0:
			_disarm()


## 위험한 버튼: 첫 번째 누름은 그 버튼 글을 확인 문구로 바꾸고(입력은 그대로), ARM_SEC 안에 다시 누르면 true.
func _confirm(name: String, b: Button, ask: String) -> bool:
	if _armed == name and _armed_button == b:
		_disarm()
		return true
	_disarm()
	_armed = name
	_armed_button = b
	_armed_text = b.text
	_armed_left = ARM_SEC
	b.text = ask
	return false


func _disarm() -> void:
	if _armed_button != null and is_instance_valid(_armed_button):
		_armed_button.text = _armed_text
	_armed = ""
	_armed_button = null
	_armed_left = 0.0


func _rebuild() -> void:
	_disarm()
	for t in TABS:
		UiKit.apply_button(buttons["tab:" + t[0]], HudScript.ACCENT if t[0] == tab else UiKit.STEEL, 12.0)
	_clear_body()
	f = {}
	match tab:
		"status":
			_build_status()
		"notice":
			_build_notice()
		"mail":
			_build_mail()
		"coupon":
			_build_coupon()


# --- 상태 ---

func _build_status() -> void:
	var st: Dictionary = ops.get("status", {})
	var m: Dictionary = st.get("maintenance", {})
	var on := bool(m.get("on", false))
	var v := _card(Color(1.0, 0.90, 0.88, 0.95) if on else Color(1, 1, 1, 0.85))
	v.add_child(_label("점검 모드: " + ("켜짐 — 관리자 말고는 접속이 막혀 있습니다" if on else "꺼짐"), 26, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	f.mt_text = line_edit("안내 문구(비우면 기본 문구)", 300)
	f.mt_text.text = str(m.get("text", ""))
	v.add_child(f.mt_text)
	f.mt_min = line_edit("끝나는 예정: 지금부터 몇 분 뒤(비우면 없음)", 6)
	v.add_child(f.mt_min)
	if m.get("until") != null and float(m.until) > 0.0:
		v.add_child(_label("지금 예정: " + preload("res://scripts/ops_overlay.gd").clock_text(float(m.until)), 22, SUB, HORIZONTAL_ALIGNMENT_LEFT))
	var b := _button("점검 시작" if not on else "점검 끝내기", Color(0.85, 0.27, 0.22) if not on else HudScript.ACCENT, 24)
	b.pressed.connect(func():
		if on:
			_save_status({"maintenance": false})
		elif _confirm("mt_on", b, "한 번 더 누르면 점검을 시작합니다"):
			_save_status(_maint_body(true)))
	v.add_child(b)
	buttons["maintenance"] = b
	if on:
		var u := _button("안내 문구·예정 시각만 바꾸기", UiKit.STEEL, 22)
		u.pressed.connect(func(): _save_status(_maint_body(true)))
		v.add_child(u)

	var w := _card()
	w.add_child(_label("강제 업데이트", 26, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	w.add_child(_wrap("이 버전보다 낮은 앱은 접속하면 업데이트 안내만 보입니다. 지금 이 앱 버전: %s" % LiveOps.app_version(), 22, SUB))
	f.min_version = line_edit("최소 버전(예: 0.2.2, 비우면 끔)", 20)
	f.min_version.text = str(st.get("min_version", ""))
	w.add_child(f.min_version)
	f.store_url = line_edit("스토어 주소(비우면 Google Play 앱 페이지)", 300)
	f.store_url.text = str(st.get("store_url", ""))
	w.add_child(f.store_url)
	var s := _button("업데이트 설정 저장", HudScript.ACCENT, 24)
	s.pressed.connect(func(): _save_status({"min_version": f.min_version.text.strip_edges(), "store_url": f.store_url.text.strip_edges()}))
	w.add_child(s)
	buttons["save_version"] = s


func _maint_body(on: bool) -> Dictionary:
	var d := {"maintenance": on, "maintenance_text": f.mt_text.text.strip_edges()}
	var mins: String = f.mt_min.text.strip_edges()
	if mins.is_valid_int() and int(mins) > 0:
		d.maintenance_until = Economy.time_now() + int(mins) * 60
	elif mins == "":
		d.maintenance_until = null
	return d


func _save_status(d: Dictionary) -> void:
	_post("/v1/admin/status", d, "저장했습니다")


# --- 공지 ---

func _build_notice() -> void:
	var v := _card()
	v.add_child(_label("공지 수정 (#%d)" % editing_notice if editing_notice else "새 공지", 26, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	f.n_title = line_edit("제목", 60)
	v.add_child(f.n_title)
	f.n_body = _text_edit("본문")
	v.add_child(f.n_body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	f.n_kind = _option(KIND_ITEMS.map(func(k): return k[1]))
	row.add_child(f.n_kind)
	f.n_pinned = UiKit.checkbox("고정")
	f.n_pinned.custom_minimum_size = Vector2(130, 56)
	row.add_child(f.n_pinned)
	v.add_child(row)
	if editing_notice:
		for n in ops.get("notices", []):
			if int(n.id) == editing_notice:
				f.n_title.text = str(n.title)
				f.n_body.text = str(n.get("body", ""))
				f.n_kind.select(maxi(0, KIND_ITEMS.map(func(k): return k[0]).find(str(n.get("kind", "notice")))))
				f.n_pinned.button_pressed = bool(n.get("pinned", false))
	var b := _button("수정 저장" if editing_notice else "공지 등록", HudScript.ACCENT, 24)
	b.pressed.connect(func():
		var d := {"title": f.n_title.text.strip_edges(), "body": f.n_body.text.strip_edges(), "kind": KIND_ITEMS[f.n_kind.selected][0],
			"pinned": f.n_pinned.button_pressed}
		if editing_notice:
			d.id = editing_notice
		editing_notice = 0
		_post("/v1/admin/notice", d, "공지를 저장했습니다", func(): LiveOps.fetch_notices()))
	v.add_child(b)
	buttons["notice_save"] = b
	for n in ops.get("notices", []):
		var c := _card(Color(0.92, 0.92, 0.92, 0.85) if n.get("hidden", false) else Color(1, 1, 1, 0.85))
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		r.add_child(_wrap(("[숨김] " if n.get("hidden", false) else "") + ("[고정] " if n.get("pinned", false) else "") + str(n.title), 23))
		var e := _button("수정", UiKit.STEEL, 20)
		e.custom_minimum_size = Vector2(84, 48)
		var id := int(n.id)
		e.pressed.connect(func():
			editing_notice = id
			_rebuild())
		r.add_child(e)
		var h := _button("보이기" if n.get("hidden", false) else "숨기기", UiKit.STEEL, 20)
		h.custom_minimum_size = Vector2(96, 48)
		var nn: Dictionary = n
		h.pressed.connect(func():
			_post("/v1/admin/notice", {"id": id, "title": str(nn.title), "body": str(nn.get("body", "")), "kind": str(nn.get("kind", "notice")),
				"pinned": bool(nn.get("pinned", false)), "hidden": not bool(nn.get("hidden", false))}, "바꿨습니다", func(): LiveOps.fetch_notices()))
		r.add_child(h)
		c.add_child(r)


# --- 우편 ---

func _build_mail() -> void:
	var v := _card()
	v.add_child(_label("우편 보내기", 26, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	f.m_to = line_edit("받는 사람: all(모두) 또는 친구 코드 8자리", 8)
	f.m_to.text = "all"
	v.add_child(f.m_to)
	f.m_title = line_edit("제목(예: 점검 보상)", 60)
	v.add_child(f.m_title)
	f.m_body = _text_edit("본문")
	v.add_child(f.m_body)
	_reward_editor(v, "m_")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	f.m_days = line_edit("받을 기간(일, 기본 30)", 4)
	row.add_child(f.m_days)
	f.m_new = UiKit.checkbox("새 계정도")
	f.m_new.custom_minimum_size = Vector2(170, 56)
	row.add_child(f.m_new)
	v.add_child(row)
	var b := _button("보내기", HudScript.ACCENT, 24)
	b.pressed.connect(send_mail)
	v.add_child(b)
	buttons["mail_send"] = b
	f.m_send = b
	for m in ops.get("mails", []):
		var c := _card(Color(0.92, 0.92, 0.92, 0.85) if m.get("deleted", false) else Color(1, 1, 1, 0.85))
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		var to := "모두" if str(m.get("to", "all")) == "all" else str(m.to)
		var rw = m.get("reward")
		r.add_child(_wrap("%s%s → %s · 받은 사람 %d\n%s" % ["[회수] " if m.get("deleted", false) else "", str(m.title), to, int(m.get("claims", 0)),
			LiveOps.reward_text(rw) if rw is Dictionary else ""], 21))
		if not m.get("deleted", false):
			var d := _button("회수", UiKit.STEEL, 20)
			d.custom_minimum_size = Vector2(84, 48)
			var id := int(m.id)
			d.pressed.connect(func():
				if _confirm("mail_del:%d" % id, d, "확인"):
					_post("/v1/admin/mail/delete", {"id": id}, "우편을 회수했습니다(아직 안 받은 사람만)"))
			r.add_child(d)
		c.add_child(r)


func send_mail() -> void:
	var to: String = f.m_to.text.strip_edges()
	var d := {"to": to, "title": f.m_title.text.strip_edges(), "body": f.m_body.text.strip_edges(), "reward": _reward_of("m_"),
		"new_players": f.m_new.button_pressed}
	var days: String = f.m_days.text.strip_edges()
	if days.is_valid_int():
		d.expires_days = int(days)
	if to.to_lower() == "all" and not _confirm("mail_send", f.m_send, "한 번 더 누르면 모두에게 보냅니다"):
		return
	_post("/v1/admin/mail", d, "우편을 보냈습니다")


# --- 쿠폰 ---

func _build_coupon() -> void:
	var v := _card()
	v.add_child(_label("쿠폰 만들기", 26, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
	f.c_code = line_edit("쿠폰 번호(영문·숫자 4~20자)", 20)
	v.add_child(f.c_code)
	_reward_editor(v, "c_")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	f.c_max = line_edit("전체 사용 수(빈칸 = 무제한)", 8)
	row.add_child(f.c_max)
	f.c_days = line_edit("기간(일, 빈칸 = 무기한)", 4)
	row.add_child(f.c_days)
	v.add_child(row)
	f.c_note = line_edit("메모(나만 보임)", 100)
	v.add_child(f.c_note)
	var b := _button("쿠폰 만들기", HudScript.ACCENT, 24)
	b.pressed.connect(func():
		var d := {"code": f.c_code.text.strip_edges().to_upper(), "reward": _reward_of("c_"), "note": f.c_note.text.strip_edges()}
		var mx: String = f.c_max.text.strip_edges()
		if mx.is_valid_int() and int(mx) > 0:
			d.max_uses = int(mx)
		var days: String = f.c_days.text.strip_edges()
		if days.is_valid_int() and int(days) > 0:
			d.expires_at = Economy.time_now() + int(days) * 86400
		_post("/v1/admin/coupon", d, "쿠폰을 만들었습니다"))
	v.add_child(b)
	buttons["coupon_make"] = b
	v.add_child(_wrap("한 계정은 한 쿠폰을 한 번만 쓸 수 있습니다. 플레이어는 설정 → [쿠폰 입력]에서 씁니다.", 20, SUB))
	for cp in ops.get("coupons", []):
		var c := _card(Color(0.92, 0.92, 0.92, 0.85) if cp.get("disabled", false) else Color(1, 1, 1, 0.85))
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		var lim := "무제한" if cp.get("max_uses") == null else str(int(cp.max_uses))
		var till := "" if cp.get("expires") == null else " · %s까지" % preload("res://scripts/ops_overlay.gd").clock_text(float(cp.expires))
		var rw = cp.get("reward")
		r.add_child(_wrap("%s%s · 사용 %d / %s%s%s\n%s" % ["[꺼짐] " if cp.get("disabled", false) else "", str(cp.code), int(cp.get("uses", 0)), lim, till,
			"" if str(cp.get("note", "")) == "" else " · " + str(cp.note), LiveOps.reward_text(rw) if rw is Dictionary else ""], 21))
		var t := _button("켜기" if cp.get("disabled", false) else "끄기", UiKit.STEEL, 20)
		t.custom_minimum_size = Vector2(84, 48)
		var code := str(cp.code)
		var off := not bool(cp.get("disabled", false))
		t.pressed.connect(func(): _post("/v1/admin/coupon/disable", {"code": code, "disabled": off}, "바꿨습니다"))
		r.add_child(t)
		c.add_child(r)


# --- 보상 입력 ---

func _reward_editor(v: VBoxContainer, p: String) -> void:
	v.add_child(_label("보상(빈칸 = 없음)", 22, SUB, HORIZONTAL_ALIGNMENT_LEFT))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for k in REWARD_FIELDS:
		var e := line_edit(k[1], 13)
		e.custom_minimum_size = Vector2(0, 52)
		e.add_theme_font_size_override("font_size", 22)
		grid.add_child(e)
		f[p + k[0]] = e
	v.add_child(grid)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var heroes: Array = ["영웅 없음"]
	for h in GameData.heroes():
		heroes.append("%s %s" % [h.get("grade", ""), h.get("name", h.id)])
	f[p + "hero"] = _option(heroes)
	row.add_child(f[p + "hero"])
	f[p + "hero_n"] = line_edit("장 수", 4)
	f[p + "hero_n"].custom_minimum_size = Vector2(110, 52)
	f[p + "hero_n"].size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(f[p + "hero_n"])
	v.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	f[p + "equip"] = _option(["장비 없음"] + GRADES.map(func(g): return g + " 장비"))
	row2.add_child(f[p + "equip"])
	f[p + "equip_n"] = line_edit("개수", 3)
	f[p + "equip_n"].custom_minimum_size = Vector2(110, 52)
	f[p + "equip_n"].size_flags_horizontal = Control.SIZE_SHRINK_END
	row2.add_child(f[p + "equip_n"])
	v.add_child(row2)


func _reward_of(p: String) -> Dictionary:
	var r := {}
	for k in REWARD_FIELDS:
		var t: String = f[p + k[0]].text.strip_edges().replace(",", "")
		if t.is_valid_int() and int(t) > 0:
			r[k[0]] = int(t)
	var hi: int = f[p + "hero"].selected
	if hi > 0:
		r.hero = str(GameData.heroes()[hi - 1].id)
		var n: String = f[p + "hero_n"].text.strip_edges()
		if n.is_valid_int() and int(n) > 1:
			r.hero_n = int(n)
	var ei: int = f[p + "equip"].selected
	if ei > 0:
		var n2: String = f[p + "equip_n"].text.strip_edges()
		r.equip = {"grade": GRADES[ei - 1], "n": int(n2) if n2.is_valid_int() and int(n2) > 0 else 1}
	return r


# --- 공통 ---

func _post(path: String, d: Dictionary, ok_text: String, after := Callable()) -> void:
	if not Net.up:
		Economy.notice.emit("서버에 연결된 뒤 다시 해 주세요")
		return
	Net.send("POST", path, d, func(_r: Dictionary):
		Economy.notice.emit(ok_text)
		if after.is_valid():
			after.call()
		fetch(),
		func(): Economy.notice.emit("실패했습니다: %s" % (Net.last_error if Net.last_error != "" else "서버 응답 없음")))


func _text_edit(placeholder: String) -> TextEdit:
	var t := TextEdit.new()
	t.placeholder_text = placeholder
	t.custom_minimum_size = Vector2(0, 150)
	t.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", HudScript.INK)
	t.add_theme_color_override("font_placeholder_color", SUB)
	t.add_theme_stylebox_override("normal", UiKit.panel(Color.WHITE, 10.0, 12))
	t.add_theme_stylebox_override("focus", UiKit.panel(Color.WHITE, 10.0, 12))
	return t


func _option(items: Array) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.select(0)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.custom_minimum_size = Vector2(0, 52)
	o.add_theme_font_size_override("font_size", 22)
	o.get_popup().add_theme_font_size_override("font_size", 26)
	return o

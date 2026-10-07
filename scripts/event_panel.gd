extends "res://scripts/ui_window.gd"
## 이벤트 창(오른쪽 아래 메뉴 [이벤트]) = 28일 출석 이벤트(온라인 전용, 서버 server/src/attendance.ts).
## 열 때 GET /v1/attendance로 보상 표·진행을 받는다. 7 × 4 칸(1..28일차): 받은 칸은 흐리게 + 체크, 오늘 받을 칸은 금색 테두리,
## 7·14·21·28일차는 큰 보상(옅은 금색 바탕). 칸을 누르면 아래 설명 줄에 그 날 보상을 풀어 쓴다.
## [오늘의 보상 받기] → POST /v1/attendance/claim {day}(once — 재전송하지 않는다) → 응답을 Economy.apply_server로 반영.
## 하루 = 서버 일일 리셋(00:00 KST) 기준 한 번. 오프라인이면 "온라인에서만" 안내.

const IconsScript := preload("res://scripts/icons.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")
const GameData := preload("res://scripts/game_data.gd")
const GuildPanel := preload("res://scripts/guild_panel.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const PouchPanel := preload("res://scripts/pouch_panel.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const TITLE := "28일 출석 이벤트"
const COLS := 7
const CELL := Vector2(86, 118)
const GAP := 6
const BIG_DAYS := [7, 14, 21, 28]
const CELL_BG := Color(1, 1, 1, 0.8)
const BIG_BG := Color(1.0, 0.93, 0.70)
const TODAY := Color(0.98, 0.70, 0.12)
const DONE_INK := Color(0.30, 0.62, 0.32)
const SUB := Color(0.16, 0.18, 0.24, 0.62)
const TICKET := Color(0.61, 0.42, 0.84)  # 다이아 모집권(SR 보라)
const KEY_NAMES := {"gold": "골드 던전 열쇠", "equip": "장비 던전 열쇠", "ticket": "모집권 던전 열쇠"}
const FAIL_TEXT := {"claimed": "오늘은 이미 받았어요", "finished": "모든 출석 보상을 받았어요", "stale": "출석 정보가 바뀌었어요. 다시 열어 주세요"}

var data := {}  # 서버 응답 {n, days, can_claim, next_reset, rewards}
var loading := false
var claiming := false
var failed := false
var selected := -1  # 설명 줄에 보일 칸(0부터), -1이면 다음 받을 칸
var grid: GridContainer
var info: Label
var progress: Label
var claim_button: Button
var cells: Array = []  # 칸 Button(테스트용)


func _ready() -> void:
	Net.booted.connect(_on_booted)  # 로딩 화면이 미리 받은 출석 표 — 열자마자 보인다(열 때 다시 받아 새로 고친다)
	if Net.boot.get("attendance") is Dictionary:
		data = Net.boot.attendance
	_build_window(COLS * CELL.x + (COLS - 1) * GAP + 48, 12)
	content.add_child(_title(TITLE))
	progress = _label("", 24, SUB)
	content.add_child(progress)
	grid = GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(grid)
	info = _label("", 24)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(0, 64)
	content.add_child(info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var close_button := _button("닫기", UiKit.STEEL)
	close_button.custom_minimum_size.x = 160
	close_button.pressed.connect(close)
	row.add_child(close_button)
	claim_button = _button("오늘의 보상 받기")
	claim_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	claim_button.pressed.connect(claim)
	row.add_child(claim_button)
	content.add_child(row)
	if PortraitsScript.current != null:
		PortraitsScript.current.portrait_ready.connect(func(_k): _redraw_cells())
	_rebuild()


func _on_open() -> void:
	selected = -1
	fetch()
	_rebuild()


func fetch() -> void:
	if not Net.is_online() or not Net.up:
		failed = true
		return
	loading = true
	failed = false
	Net.send("GET", "/v1/attendance", null, _on_data, _on_fail)


func _on_booted(d: Dictionary) -> void:
	if d.get("attendance") is Dictionary and d.attendance.get("rewards") is Array:
		data = d.attendance
		if visible:
			_rebuild()


func _on_data(d: Dictionary) -> void:
	loading = false
	if d.get("rewards") is Array:
		data = d
	_rebuild()


func _on_fail() -> void:
	loading = false
	failed = true
	_rebuild()


func claimed_n() -> int:
	return int(data.get("n", 0))


func can_claim() -> bool:
	return bool(data.get("can_claim", false)) and not claiming


## 오늘 칸 받기: 응답을 기다리지 않고 곧바로 받은 것으로 보이고(골드·자원·다이아·모집권·주머니도 — 열쇠·장비·영웅은 응답 때)
## 서버에 보낸다(서버가 날짜·순서를 다시 본다). 거절되면 되돌리고 알린다.
func claim() -> void:
	if not can_claim() or not Net.up:
		return
	var day := claimed_n() + 1
	var rewards: Array = data.get("rewards", [])
	var reward = rewards[day - 1] if day - 1 < rewards.size() else {}
	var key := "attendance:%d" % day
	claiming = true  # 응답 전(화면은 이미 받은 것으로 보인다)
	Economy.predict_reward(key, reward if reward is Dictionary else {})
	data.n = day
	data.can_claim = false
	selected = day - 1
	Economy.notice.emit("%d일차 출석 보상을 받았어요!" % day)
	Net.send("POST", "/v1/attendance/claim", {"day": day}, _on_claimed.bind(key), _on_claim_failed.bind(key, day), true, true)
	_rebuild()


func _on_claimed(d: Dictionary, key: String) -> void:
	claiming = false
	Economy.settle(key)
	Economy.apply_server(d)
	_rebuild()


func _on_claim_failed(key: String, day: int) -> void:
	claiming = false
	Economy.unpredict(key)
	if claimed_n() == day:
		data.n = day - 1
		data.can_claim = true
	Economy.notice.emit(FAIL_TEXT.get(Net.last_error, "보상을 받지 못했어요. 잠시 뒤 다시 시도해 주세요"))
	Net.refresh()
	fetch()
	_rebuild()


func _rebuild() -> void:
	for c in grid.get_children():
		c.queue_free()
	cells.clear()
	var rewards: Array = data.get("rewards", [])
	if rewards.is_empty():
		progress.text = ""
		info.text = "온라인에서만 참여할 수 있어요" if not Net.is_online() else ("출석 정보를 불러오는 중…" if loading or not failed else "연결이 끊겨 불러오지 못했어요")
		claim_button.disabled = true
		claim_button.text = "오늘의 보상 받기"
		_fit()
		return
	var n := claimed_n()
	for i in rewards.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.flat = true
		b.custom_minimum_size = CELL
		var face := Control.new()
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var idx: int = i
		face.draw.connect(func(): _draw_cell(face, idx, rewards[idx], n))
		b.add_child(face)
		b.pressed.connect(func():
			selected = idx
			_update_info())
		grid.add_child(b)
		cells.append(b)
	progress.text = "출석 %d / %d일 · 하루 한 번, 날짜가 이어지지 않아도 돼요" % [n, rewards.size()]
	if n >= rewards.size():
		claim_button.text = "모두 받았어요"
	elif can_claim():
		claim_button.text = "%d일차 보상 받기" % (n + 1)
	else:
		claim_button.text = "내일 다시 와 주세요"
	claim_button.disabled = not can_claim() or not Net.up
	_update_info()
	_fit()


func _redraw_cells() -> void:
	for b in cells:
		b.get_child(0).queue_redraw()


func _update_info() -> void:
	var rewards: Array = data.get("rewards", [])
	if rewards.is_empty():
		return
	var i := selected if selected >= 0 else mini(claimed_n(), rewards.size() - 1)
	var head := "%d일차" % (i + 1)
	if i < claimed_n():
		head += "(받음)"
	elif i == claimed_n() and can_claim():
		head += "(오늘)"
	info.text = head + ": " + reward_text(rewards[i])
	_redraw_cells()


## 보상 풀어 쓰기: "골드 10,000", "SR 장비 상자 + 다이아 모집권 5장" …
static func reward_text(r: Dictionary) -> String:
	var parts: Array = []
	if r.has("hero"):
		var h := GameData.hero(str(r.hero))
		parts.append("%s 영웅 %s(%s)" % [h.get("grade", ""), h.get("name", str(r.hero)), h.get("title", "")] if not h.is_empty() else "영웅 " + str(r.hero))
	if r.get("equip") is Dictionary:
		parts.append("%s 장비 상자(부위·능력치 무작위)" % r.equip.get("grade", ""))
	if r.has("gold"):
		parts.append("골드 " + UiKit.commas(int(r.gold)))
	if r.has("diamonds"):
		parts.append("다이아 " + UiKit.commas(int(r.diamonds)))
	if r.has("wood") and int(r.get("wood", 0)) == int(r.get("stone", -1)) and int(r.wood) == int(r.get("food", -1)):
		parts.append("목재·석재·식량 각 " + UiKit.commas(int(r.wood)))
	else:
		for k in [["wood", "목재"], ["stone", "석재"], ["food", "식량"]]:
			if r.has(k[0]):
				parts.append("%s %s" % [k[1], UiKit.commas(int(r[k[0]]))])
	for t in KEY_NAMES:
		if r.has("keys_" + t):
			parts.append("%s %d개" % [KEY_NAMES[t], int(r["keys_" + t])])
	if r.has("tickets"):
		parts.append("다이아 모집권 %d장" % int(r.tickets))
	var pz := Economy.pouches_in(r)
	for id in Economy.pouch_ids():
		if pz.has(id):
			parts.append(Economy.pouch_name(id) + ("" if int(pz[id]) == 1 else " %d개" % int(pz[id])))
	return " + ".join(parts)


## 칸 안 짧은 글: 주 보상 하나 + (있으면) 둘째 줄.
static func cell_lines(r: Dictionary) -> Array:
	var lines: Array = []
	if r.has("hero"):
		lines.append(str(GameData.hero(str(r.hero)).get("name", r.hero)))
	if r.get("equip") is Dictionary:
		lines.append("%s 장비" % r.equip.get("grade", ""))
	if r.has("gold"):
		lines.append(short_num(int(r.gold)))
	if r.has("diamonds"):
		lines.append(str(int(r.diamonds)))
	if r.has("wood"):
		lines.append("각 " + short_num(int(r.wood)))
	for t in KEY_NAMES:
		if r.has("keys_" + t):
			lines.append("x%d" % int(r["keys_" + t]))
	if r.has("tickets"):
		lines.append(("모집권 %d" if lines.size() > 0 else "x%d") % int(r.tickets))
	var pz := Economy.pouches_in(r)
	if pz.size() == 1:
		var id: String = pz.keys()[0]
		var m := int(Economy.pouch_parse(id).min)
		lines.append("주머니 " + (("%d시간" % (m / 60)) if m >= 60 else ("%d분" % m)))
	elif pz.size() > 1:
		lines.append("주머니 %d개" % pz.size())
	return lines


## 10000 → "1만", 15000 → "1.5만", 500 → "500".
static func short_num(v: int) -> String:
	if v >= 10000:
		var m := v / 10000.0
		return ("%d만" % int(m)) if is_equal_approx(m, roundf(m)) else ("%.1f만" % m)
	return UiKit.commas(v)


func _draw_cell(c: Control, i: int, r: Dictionary, n: int) -> void:
	var day := i + 1
	var rect := Rect2(Vector2.ZERO, c.size)
	var done := i < n
	var today := i == n and bool(data.get("can_claim", false))
	var big := day in BIG_DAYS
	var bg := BIG_BG if big else CELL_BG
	var oct := LowpolyBox.octagon(rect.grow(-1), 8.0)
	c.draw_colored_polygon(oct, bg)
	var edge := TODAY if today else LowpolyBox.edge_color(bg)
	var line := oct.duplicate()
	line.append(oct[0])
	c.draw_polyline(line, edge, 4.0 if today else (3.0 if i == selected else 1.5), true)
	if i == selected and not today:
		c.draw_polyline(line, Color(UiKit.INK, 0.5), 3.0, true)
	c.draw_string(FONT, Vector2(0, 22), "%d일" % day, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 18, TODAY.darkened(0.35) if big else SUB)
	var ctr := Vector2(c.size.x / 2.0, 56)
	_draw_reward_icon(c, r, ctr, 42.0)
	var pz := Economy.pouches_in(r)
	if not pz.is_empty() and r.size() > pz.size():  # 다른 보상과 함께 주는 주머니: 그림 오른쪽 위에 작은 주머니
		PouchPanel.draw_pouch(c, ctr + Vector2(26, -14), 26.0, str(Economy.pouch_parse(pz.keys()[0]).kind))
	var lines := cell_lines(r)
	var y := 96.0
	for k in mini(lines.size(), 2):
		c.draw_string(FONT, Vector2(0, y + k * 17), str(lines[k]), HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 17 if k == 0 else 14, UiKit.INK if k == 0 else SUB)
	if done:
		c.draw_colored_polygon(oct, Color(1, 1, 1, 0.55))
		var m := c.size / 2.0 + Vector2(0, -4)
		c.draw_polyline(PackedVector2Array([m + Vector2(-18, 0), m + Vector2(-5, 13), m + Vector2(20, -14)]), DONE_INK, 7.0, true)


## 보상 그림: 영웅 피규어 > 장비 상자 > 골드·다이아·자원 > 열쇠 > 모집권.
static func _draw_reward_icon(c: Control, r: Dictionary, ctr: Vector2, s: float) -> void:
	if r.has("hero"):
		var grade := str(GameData.hero(str(r.hero)).get("grade", "SR"))
		var col: Color = UiKit.GRADE_COLORS.get(grade, UiKit.GRADE_COLORS.SR)
		var tex := PortraitsScript.portrait("hero:" + str(r.hero))
		UiKit.draw_gem(c, ctr + Vector2(0, 2), s * 0.62, col.lightened(0.25), 8)
		var size := Vector2(s * 1.35, s * 1.35)
		c.draw_texture_rect(tex, Rect2(ctr - size / 2.0 + Vector2(0, -6), size), false)
		return
	if r.get("equip") is Dictionary:
		GuildPanel.draw_chest(c, ctr + Vector2(0, 2), s, false)
		var col: Color = UiKit.GRADE_COLORS.get(str(r.equip.get("grade", "SR")), UiKit.GRADE_COLORS.SR)
		UiKit.draw_gem(c, ctr + Vector2(s * 0.42, -s * 0.36), s * 0.2, col, 6)
		return
	if r.has("gold"):
		IconsScript.draw_icon(c, "gold", ctr, s)
	elif r.has("diamonds"):
		IconsScript.draw_icon(c, "diamond", ctr, s)
	elif r.has("wood"):
		IconsScript.draw_icon(c, "wood", ctr + Vector2(-s * 0.3, s * 0.12), s * 0.6)
		IconsScript.draw_icon(c, "stone", ctr + Vector2(s * 0.3, s * 0.12), s * 0.6)
		IconsScript.draw_icon(c, "food", ctr + Vector2(0, -s * 0.22), s * 0.6)
	elif r.has("keys_gold") or r.has("keys_equip") or r.has("keys_ticket"):
		draw_key(c, ctr, s, r)
	elif r.has("tickets"):
		draw_ticket(c, ctr, s)
	else:
		var pz := Economy.pouches_in(r)
		if not pz.is_empty():
			PouchPanel.draw_pouch(c, ctr, s * 1.1, str(Economy.pouch_parse(pz.keys()[0]).kind))


## 던전 열쇠(종류마다 고리 색): 고리 + 자루 + 이 둘.
static func draw_key(ci: CanvasItem, ctr: Vector2, s: float, r: Dictionary) -> void:
	var gold := Color(0.95, 0.72, 0.2)
	var ring_col := gold if r.has("keys_gold") else (Color(0.55, 0.62, 0.74) if r.has("keys_equip") else TICKET)
	var ring := ctr + Vector2(-s * 0.22, 0)
	ci.draw_circle(ring, s * 0.24, LowpolyBox.edge_color(ring_col))
	ci.draw_circle(ring, s * 0.19, ring_col)
	ci.draw_circle(ring, s * 0.08, Color(1, 1, 1, 0.9))
	ci.draw_rect(Rect2(ctr + Vector2(-s * 0.02, -s * 0.07), Vector2(s * 0.5, s * 0.14)), gold)
	for x in [0.3, 0.42]:
		ci.draw_rect(Rect2(ctr + Vector2(s * x - s * 0.05, s * 0.05), Vector2(s * 0.08, s * 0.14)), gold)


## 다이아 모집권: 보라 표(양옆 홈) + 가운데 다이아.
static func draw_ticket(ci: CanvasItem, ctr: Vector2, s: float) -> void:
	var w := s * 0.5
	var h := s * 0.32
	var nt := s * 0.08
	var pts := PackedVector2Array([ctr + Vector2(-w, -h), ctr + Vector2(w, -h), ctr + Vector2(w, -nt), ctr + Vector2(w - nt, 0), ctr + Vector2(w, nt),
		ctr + Vector2(w, h), ctr + Vector2(-w, h), ctr + Vector2(-w, nt), ctr + Vector2(-w + nt, 0), ctr + Vector2(-w, -nt)])
	ci.draw_colored_polygon(pts, TICKET)
	ci.draw_colored_polygon(PackedVector2Array([ctr + Vector2(-w, -h), ctr + Vector2(w, -h), ctr + Vector2(w, -h * 0.4), ctr + Vector2(-w, -h * 0.4)]), TICKET.lightened(0.18))
	pts.append(pts[0])
	ci.draw_polyline(pts, LowpolyBox.edge_color(TICKET), maxf(1.0, s / 26.0), true)
	IconsScript.draw_icon(ci, "diamond", ctr, s * 0.42)

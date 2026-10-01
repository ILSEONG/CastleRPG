extends "res://scripts/ui_window.gd"
## 영웅 목록 시트(스펙 §2.4, 하단 탭 [영웅]): 상단 칩 줄과 탭 바 사이를 채운다. 뒤 입력은 막고(전체 화면 배경), 탭 바는 위 층이라 계속 쓴다.
## 위: 배치 슬롯(GameState.hero_count칸, 개정 10 영웅 창 그대로) — 슬롯을 탭하고 영웅 카드를 탭하면 그 슬롯에 놓는다(다른 슬롯에
## 있던 영웅이면 서로 바꾼다). 바뀐 배치는 [적용] → Economy.set_deploy(다음 리필 때, 방치 모드면 곧바로).
## [정렬]: 전투력 → 등급 → 레벨(누를 때마다). 보유 영웅 3열 스크롤 격자: 등급 테두리·보석·피규어·이름·Lv·별·전투력·"배치"·레벨업 가능 ▲.
## 개정 14 §2: 카드의 육각 보석 자리에 영웅 피규어(Portraits). 상세 큰 카드는 실시간 피규어 — 가로로 끌면 돌고, 스와이프(이전·다음)는 카드 밖에서.
## 카드를 탭하면 상세(슬롯을 고른 중이면 배치). 슬롯 카드를 길게 누르면 그 영웅 상세.
## 상세(스펙 §2.5): 큰 카드 + "칭호 이름"·등급·"Lv N / 최대" 막대, 능력치(HP·공격·공격 간격·사거리·전투력) 옆 다음 레벨 값,
## 스킬 설명, 설명문, [레벨업](비용 아이콘·숫자)·[×10](실제 횟수·총비용)·[배치], 못 하면 이유 한 줄. 성공하면 빛 조각·레벨 튀어 오름·
## 바뀐 숫자 초록 반짝임. [이전]·[다음]·좌우 스와이프로 목록 순서대로, [닫기]는 목록으로.
## 목록 ↔ 상세 전환 때 연 직후처럼 보호 시간을 다시 건다(카드 연타가 그 자리의 [레벨업]을 누르지 않게).

const GameData := preload("res://scripts/game_data.gd")
const Skills := preload("res://scripts/skills.gd")
const HeroCardScript := preload("res://scripts/hero_card.gd")
const IconsScript := preload("res://scripts/icons.gd")

const SLOT_SIZE := Vector2(140, 150)
const CARD_SIZE := Vector2(200, 240)
const GRID_COLUMNS := 3
const BIG_CARD := Vector2(190, 240)
const GRADE_RANK := {"SSR": 0, "SR": 1, "R": 2}
const SORTS := ["power", "grade", "level"]
const SORT_NAMES := {"power": "전투력", "grade": "등급", "level": "레벨"}
const HINT := "슬롯을 누른 뒤 영웅을 고르세요"
const GREEN := Color(0.13, 0.58, 0.24)
const REASON_COLOR := Color(0.78, 0.22, 0.18)
const SWIPE_PX := 80.0
const TEN := 10
const STAT_NAMES := ["HP", "공격", "공격 간격", "사거리", "전투력"]

var slot_cards: Array = []
var hero_cards := {}  # 영웅 id → 보유 격자 카드(정렬 순서)
var apply_button: Button
var sort_button: Button
var work: Array = []  # 편집 중인 배치(슬롯 i → 영웅 id 또는 null)
var selected_slot := -1
var sort_mode := "power"
var detail_id := ""
var order: Array = []  # 이전·다음 순서(상세를 열 때의 목록 순서)
var big_card
var title_label: Label
var grade_label: Label
var level_label: Label
var level_bar: ProgressBar
var stat_values: Array = []  # 능력치 값 Label(STAT_NAMES 순서)
var stat_nexts: Array = []   # 다음 레벨 값 Label(초록)
var skills_label: Label
var desc_label: Label
var level_button: Button
var ten_button: Button
var deploy_button: Button
var reason_label: Label
var prev_button: Button
var next_button: Button
var celebrations := 0  # 성공 연출 횟수(테스트용)

var _list_view: VBoxContainer
var _detail_view: VBoxContainer
var _slot_grid: GridContainer
var _hero_grid: GridContainer
var _one := {}  # [레벨업] 버튼 안 {title, gold} Label
var _ten := {}
var _before: Array = []  # 레벨업을 누를 때의 능력치 글자(바뀐 것만 반짝인다)
var _swipe_from := Vector2.INF


func _ready() -> void:
	_build_window(0, 10)
	dialog.get_parent().color = Color(0, 0, 0, 0)  # 시트가 화면을 채운다 — 어둡게 할 곳이 없다(위 칩 줄은 그대로 보인다)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_list()
	_build_detail()
	_fit()
	Economy.roster_changed.connect(_refresh)
	Economy.changed.connect(_refresh)
	Economy.leveled.connect(_on_leveled)


## 시트(ui_window._fit_sheet): 내용이 바뀌어도 크기를 다시 맞추지 않는다.
func _fit() -> void:
	_fit_sheet()


func _build_list() -> void:
	_list_view = VBoxContainer.new()
	_list_view.add_theme_constant_override("separation", 10)
	_list_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_list_view)
	_list_view.add_child(_title("영웅"))
	var slots_center := CenterContainer.new()
	_list_view.add_child(slots_center)
	_slot_grid = GridContainer.new()
	_slot_grid.columns = 4
	_slot_grid.add_theme_constant_override("h_separation", 12)
	slots_center.add_child(_slot_grid)
	_list_view.add_child(_label(HINT, 22, HudScript.INK.lightened(0.3)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_list_view.add_child(row)
	sort_button = _button("", UiKit.STEEL, 26)
	sort_button.pressed.connect(cycle_sort)
	apply_button = _button("적용")
	apply_button.pressed.connect(apply)
	for b in [sort_button, apply_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_view.add_child(scroll)
	var grid_center := CenterContainer.new()
	grid_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_center)
	_hero_grid = GridContainer.new()
	_hero_grid.columns = GRID_COLUMNS
	_hero_grid.add_theme_constant_override("h_separation", 12)
	_hero_grid.add_theme_constant_override("v_separation", 12)
	grid_center.add_child(_hero_grid)


func _build_detail() -> void:
	_detail_view = VBoxContainer.new()
	_detail_view.add_theme_constant_override("separation", 10)
	_detail_view.visible = false
	_detail_view.gui_input.connect(_on_detail_input)  # 좌우 스와이프
	content.add_child(_detail_view)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	_detail_view.add_child(top)
	big_card = HeroCardScript.new()
	big_card.custom_minimum_size = BIG_CARD
	big_card.live = true  # 개정 14 §2: 실시간 피규어(대기 애니메이션), 끌어서 돌린다
	top.add_child(big_card)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 8)
	top.add_child(info)
	title_label = _label("", 32, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	title_label.add_theme_color_override("font_outline_color", HudScript.INK)
	title_label.add_theme_constant_override("outline_size", 6)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(title_label)
	grade_label = _label("", 26, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	info.add_child(grade_label)
	level_label = _label("", 34, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	info.add_child(level_label)
	level_bar = ProgressBar.new()
	level_bar.custom_minimum_size = Vector2(0, 22)
	level_bar.show_percentage = false
	level_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.apply_bar(level_bar, UiKit.AMBER)
	info.add_child(level_bar)
	var stats := GridContainer.new()
	stats.columns = 3
	stats.add_theme_constant_override("h_separation", 18)
	stats.add_theme_constant_override("v_separation", 4)
	_detail_view.add_child(stats)
	for n in STAT_NAMES:
		stats.add_child(_label(n, 26, HudScript.INK.lightened(0.25), HORIZONTAL_ALIGNMENT_LEFT))
		var v := _label("", 26, HudScript.INK, HORIZONTAL_ALIGNMENT_RIGHT)
		v.custom_minimum_size = Vector2(150, 0)
		stats.add_child(v)
		stat_values.append(v)
		var nx := _label("", 24, GREEN, HORIZONTAL_ALIGNMENT_LEFT)
		stats.add_child(nx)
		stat_nexts.append(nx)
	skills_label = _wrap_label(22, HudScript.INK)
	_detail_view.add_child(skills_label)
	desc_label = _wrap_label(20, HudScript.INK.lightened(0.3))
	_detail_view.add_child(desc_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_detail_view.add_child(row)
	_one = _cost_button("레벨업")
	level_button = _one.button
	level_button.pressed.connect(_press_level.bind(false))
	_ten = _cost_button("×10")
	ten_button = _ten.button
	ten_button.pressed.connect(_press_level.bind(true))
	deploy_button = _button("배치", UiKit.STEEL, 26)
	deploy_button.custom_minimum_size = Vector2(150, 96)
	deploy_button.pressed.connect(deploy_here)
	for b in [level_button, ten_button, deploy_button]:
		row.add_child(b)
	reason_label = _label("", 22, REASON_COLOR)
	_detail_view.add_child(reason_label)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 12)
	_detail_view.add_child(nav)
	prev_button = _button("< 이전", UiKit.STEEL)
	prev_button.pressed.connect(step.bind(-1))
	var close_button := _button("닫기", UiKit.STEEL)
	close_button.pressed.connect(_show_list)
	next_button = _button("다음 >", UiKit.STEEL)
	next_button.pressed.connect(step.bind(1))
	for b in [prev_button, close_button, next_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nav.add_child(b)


## 비용 버튼: 위 제목, 아래 [골드 아이콘 숫자](버튼 안, 입력은 버튼이 받는다).
func _cost_button(text: String) -> Dictionary:
	var b := _button("")
	b.custom_minimum_size = Vector2(0, 96)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var title := _on_button_label(text, 28)
	box.add_child(title)
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 4)
	box.add_child(line)
	var out := {"button": b, "title": title}
	for kind in ["gold"]:
		var icon = IconsScript.new()
		icon.kind = kind
		icon.custom_minimum_size = Vector2(26, 26)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(icon)
		var l := _on_button_label("", 22)
		line.add_child(l)
		out[kind] = l
	return out


func _on_button_label(text: String, font_size: int) -> Label:
	var l := _label(text, font_size, Color.WHITE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_outline_color", Color(HudScript.INK, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	return l


func _wrap_label(font_size: int, color: Color) -> Label:
	var l := _label("", font_size, color, HORIZONTAL_ALIGNMENT_LEFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(600, 0)
	return l


func _on_open() -> void:
	work = GameState.deploy()
	selected_slot = -1
	_show_list(false)


func is_showing_detail() -> bool:
	return visible and _detail_view.visible


# --- 목록 ---

## 보유 영웅 id(표에 있는 것만), mode 순: power = 전투력 ↓, grade = 등급(SSR 먼저) → 이름, level = 레벨 ↓ → 전투력 ↓. 같으면 이름.
func owned_sorted(mode := sort_mode) -> Array:
	var ids := Economy.heroes.keys().filter(func(id): return int(Economy.heroes[id]) >= 1 and not GameData.hero(id).is_empty())
	var key := {}
	for id in ids:
		var h := GameData.hero(id)
		var p := GameData.hero_power(h, Economy.level_of(id), int(Economy.heroes[id]), Economy.levels)
		match mode:
			"grade": key[id] = [GRADE_RANK[h.grade], h.name]
			"level": key[id] = [-Economy.level_of(id), -p, h.name]
			_: key[id] = [-p, GRADE_RANK[h.grade], h.name]
	ids.sort_custom(func(a, b): return key[a] < key[b])
	return ids


func cycle_sort() -> void:
	sort_mode = SORTS[(SORTS.find(sort_mode) + 1) % SORTS.size()]
	_rebuild()


func tap_slot(i: int) -> void:
	selected_slot = -1 if selected_slot == i else i
	_rebuild()


## 영웅 카드 탭: 고른 슬롯이 있으면 거기에 놓는다(다른 슬롯에 있으면 서로 바꾼다). 없으면 상세.
func tap_hero(id: String) -> void:
	if selected_slot < 0:
		show_detail(id)
		return
	var s := selected_slot
	var j := work.find(id)
	var prev = work[s]
	work[s] = id
	if j >= 0 and j != s:
		work[j] = prev
	selected_slot = -1
	_rebuild()


func apply() -> void:
	Economy.set_deploy(work)
	if GameState.deploy() == work:
		var later := "" if GameState.mode == GameState.Mode.IDLE else " — 다음 스테이지부터"
		Economy.notice.emit("배치를 적용했습니다" + later)
	_rebuild()


func _show_list(guard := true) -> void:
	_detail_view.visible = false
	_list_view.visible = true
	_rebuild()
	if guard:
		_arm_guard()


func _refresh() -> void:
	if not visible:
		return
	if _detail_view.visible:
		_refresh_detail()
	else:
		_rebuild()


## 슬롯·보유 카드를 work·보유·정렬에 맞춘다(순서가 바뀌었을 때만 카드를 다시 만든다).
func _rebuild() -> void:
	if work.size() != GameState.hero_count():
		work = GameState.deploy()
	if slot_cards.size() != work.size():
		for c in slot_cards:
			_slot_grid.remove_child(c)
			c.queue_free()
		slot_cards.clear()
		for i in work.size():
			var card = HeroCardScript.new()
			card.custom_minimum_size = SLOT_SIZE
			card.tapped.connect(func(_c): tap_slot(i))
			card.long_pressed.connect(func(_c): if work[i] != null: show_detail(work[i]))
			_slot_grid.add_child(card)
			slot_cards.append(card)
	var ids := owned_sorted()
	if ids != hero_cards.keys():
		for c in hero_cards.values():
			_hero_grid.remove_child(c)
			c.queue_free()
		hero_cards.clear()
		for id in ids:
			var card = HeroCardScript.new()
			card.custom_minimum_size = CARD_SIZE
			card.hero_id = id
			card.tapped.connect(func(_c): tap_hero(id))
			_hero_grid.add_child(card)
			hero_cards[id] = card
	var deployed := GameState.deploy()
	for i in slot_cards.size():
		var c = slot_cards[i]
		var id = work[i]
		c.hero_id = id if id != null else ""
		c.stars = GameData.stars(int(Economy.heroes.get(id, 1))) if id != null else 0
		c.corner = str(i + 1)
		c.highlight = i == selected_slot
		c.queue_redraw()
	for id in hero_cards:
		var c = hero_cards[id]
		var copies := int(Economy.heroes[id])
		c.stars = GameData.stars(copies)
		c.level = Economy.level_of(id)
		c.power = GameData.hero_power(GameData.hero(id), c.level, copies, Economy.levels)
		c.deployed = deployed.has(id)
		c.can_level = Economy.levelup_block(id) == ""
		c.queue_redraw()
	sort_button.text = "정렬: " + SORT_NAMES[sort_mode]
	apply_button.disabled = work == GameState.deploy()


# --- 상세 ---

func show_detail(id: String) -> void:
	if GameData.hero(id).is_empty():
		return
	detail_id = id
	order = owned_sorted()
	_list_view.visible = false
	_detail_view.visible = true
	_refresh_detail()
	_arm_guard()


## 목록 순서로 이전(-1)·다음(+1) 영웅(끝에서 돈다).
func step(d: int) -> void:
	if order.size() < 2:
		return
	detail_id = order[(order.find(detail_id) + d + order.size()) % order.size()]
	_refresh_detail()


## [배치]: 지금 배치의 첫 빈 슬롯에 넣고 곧바로 적용한다(이미 배치돼 있으면 비활성 "배치 중").
func deploy_here() -> void:
	var d := GameState.deploy()
	var i := d.find(null)
	if i < 0 or d.has(detail_id):
		return
	d[i] = detail_id
	work = d.duplicate()
	apply()


func _press_level(ten: bool) -> void:
	_before = stat_values.map(func(l): return l.text)
	Economy.level_up(detail_id, Economy.levelup_affordable(detail_id, TEN) if ten else 1)


## 성공 연출: 큰 카드 빛 조각, 레벨 글자 튀어 오름, 바뀐 능력치 숫자 초록 반짝임.
func _on_leveled(id: String, _level: int) -> void:
	if not is_showing_detail() or id != detail_id:
		return
	_refresh_detail()
	celebrations += 1
	big_card.burst()
	level_label.pivot_offset = level_label.size / 2.0
	var tw := level_label.create_tween()
	tw.tween_property(level_label, "scale", Vector2.ONE * 1.35, 0.12)
	tw.tween_property(level_label, "scale", Vector2.ONE, 0.18)
	for i in stat_values.size():
		var l: Label = stat_values[i]
		if i < _before.size() and l.text != _before[i]:
			l.add_theme_color_override("font_color", GREEN)
			l.create_tween().tween_property(l, "theme_override_colors/font_color", HudScript.INK, 0.6)


func _refresh_detail() -> void:
	var id := detail_id
	var h := GameData.hero(id)
	if h.is_empty() or int(Economy.heroes.get(id, 0)) < 1:
		return
	var copies := int(Economy.heroes[id])
	var lv := Economy.level_of(id)
	var mx := GameData.max_level(copies)
	big_card.hero_id = id
	big_card.stars = GameData.stars(copies)
	big_card.queue_redraw()
	title_label.text = "%s %s" % [h.title, h.name]
	title_label.add_theme_color_override("font_color", UiKit.GRADE_COLORS[h.grade].lightened(0.15))
	grade_label.text = "%s · %s" % [h.grade, "근접" if h.role == "melee" else "원거리"]
	level_label.text = "Lv %d / %d" % [lv, mx]
	level_bar.max_value = mx
	level_bar.value = lv
	var now := GameData.hero_stats(h, lv, copies, Economy.levels)  # 연구소 보너스 포함(개정 12, 개정 13: 막사 보너스 없음)
	var nxt := GameData.hero_stats(h, lv + 1, copies, Economy.levels)
	var grow := lv < mx
	var rows := [
		[roundi(now.hp), roundi(nxt.hp)], [roundi(now.atk), roundi(nxt.atk)], null, null,
		[GameData.hero_power(h, lv, copies, Economy.levels), GameData.hero_power(h, lv + 1, copies, Economy.levels)]]
	for i in rows.size():
		var r = rows[i]
		if r == null:
			stat_values[i].text = Skills.num_text(h.atk_interval) + "초" if i == 2 else Skills.num_text(h.range) + "m"
			stat_nexts[i].text = ""
		else:
			stat_values[i].text = UiKit.commas(r[0])
			stat_nexts[i].text = "→ %s (+%s)" % [UiKit.commas(r[1]), UiKit.commas(r[1] - r[0])] if grow else ""
	skills_label.text = "\n".join(skill_lines(h))
	desc_label.text = h.desc
	var waiting: bool = Economy.levelup_waiting()
	var why := Economy.levelup_block(id)
	_set_cost(_one, "레벨업", 1 if grow else 0, h.grade, lv)
	level_button.disabled = why != "" or waiting
	var n := Economy.levelup_affordable(id, TEN)
	var shown := n if n > 0 else mini(TEN, mx - lv)
	_set_cost(_ten, "×10 (%d회)" % shown if shown > 0 else "×10", shown, h.grade, lv)
	ten_button.disabled = n == 0 or waiting
	reason_label.text = why
	var d := GameState.deploy()
	deploy_button.text = "배치 중" if d.has(id) else ("빈 슬롯 없음" if not d.has(null) else "배치")
	deploy_button.disabled = d.has(id) or not d.has(null)
	prev_button.disabled = order.size() < 2
	next_button.disabled = order.size() < 2


func _set_cost(btn: Dictionary, title: String, count: int, grade: String, lv: int) -> void:
	btn.title.text = title
	var cost := GameData.levelup_cost(grade, lv, count)
	btn.gold.text = UiKit.commas(cost.gold) if count > 0 else "-"


## 좌우 스와이프(빈 곳에서 SWIPE_PX 넘게 가로로 끌었다 뗌) → 이전·다음.
func _on_detail_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_swipe_from = mb.position
	elif _swipe_from != Vector2.INF:
		var d := mb.position - _swipe_from
		_swipe_from = Vector2.INF
		if absf(d.x) > SWIPE_PX and absf(d.x) > absf(d.y):
			step(-1 if d.x > 0.0 else 1)


## 스킬 두 개(있는 만큼): "이름 — 숫자를 넣은 설명".
static func skill_lines(h: Dictionary) -> Array:
	var out := []
	for kind in h.skills:
		out.append("%s — %s" % [Skills.NAMES.get(kind, kind), Skills.describe(kind, h.skills[kind])])
	return out

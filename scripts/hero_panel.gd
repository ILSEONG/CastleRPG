extends "res://scripts/ui_window.gd"
## 영웅 목록 시트(스펙 §2.4, 하단 탭 [영웅]): 상단 칩 줄과 탭 바 사이를 채운다. 뒤 입력은 막고(전체 화면 배경), 탭 바는 위 층이라 계속 쓴다.
## 위: 배치 슬롯(GameState.hero_count칸, 개정 10 영웅 창 그대로) — 슬롯을 탭하고 영웅 카드를 탭하면 그 슬롯에 놓는다(다른 슬롯에
## 있던 영웅이면 서로 바꾼다). 바뀐 배치는 [적용] → Economy.set_deploy(다음 리필 때, 방치 모드면 곧바로).
## [정렬]: 전투력 → 등급 → 레벨(누를 때마다). 보유 영웅 3열 스크롤 격자: 등급 테두리·보석·피규어·이름·Lv·금색 별(승급)·전투력·"배치"·
## 레벨업 가능 초록 ▲·승급 가능 금색 ⬆·조각 막대 "조각 3 / 5"(최대 승급 "MAX", 개정 15).
## 개정 14 §2: 카드의 육각 보석 자리에 영웅 피규어(Portraits). 상세 큰 카드는 실시간 피규어 — 가로로 끌면 돌고, 스와이프(이전·다음)는 카드 밖에서.
## 카드를 탭하면 상세(슬롯을 고른 중이면 배치). 슬롯 카드를 길게 누르면 그 영웅 상세.
## 상세(스펙 §2.5, 개정 15 배치): 맨 위 큰 카드(피규어가 카드 대부분 — 남는 높이를 받는다) → "칭호 이름"·등급 + [배치] → "Lv N / 최대" 막대 →
## 능력치 2열(HP·공격·공격 간격·사거리·전투력, 옆에 다음 레벨 값) → 승급 미리보기 한 줄 → 스킬·설명문(넘치면 스크롤) →
## [레벨업](비용)·[×10](실제 횟수·총비용)·[승급]("조각 12 / 25") → 버튼마다 못 하는 이유 → [이전]·[닫기]·[다음].
## 레벨업 성공: 빛 조각·레벨 튀어 오름·바뀐 숫자 초록 반짝임. 승급 성공: 금색 빛 조각이 피규어 주위로 퍼지고 별 하나가 날아와 박히고
## 바뀐 숫자 초록 반짝임. [이전]·[다음]·좌우 스와이프로 목록 순서대로, [닫기]는 목록으로.
## 목록 ↔ 상세 전환 때 연 직후처럼 보호 시간을 다시 건다(카드 연타가 그 자리의 [레벨업]을 누르지 않게).
## 개정 17: 스킬 줄은 칸마다 하나(SSR·SR 3, R 2). 잠긴 칸은 회색·자물쇠·"★3에서 해금", 승급 미리보기 둘째 줄에 다음 해금
## ("★3 달성 시 스킬 해금: 화상"), 승급으로 열리면 알림 "스킬 해금! 화상" + 그 줄 금색 반짝임.

const GameData := preload("res://scripts/game_data.gd")
const Skills := preload("res://scripts/skills.gd")
const HeroCardScript := preload("res://scripts/hero_card.gd")
const IconsScript := preload("res://scripts/icons.gd")

const SLOT_SIZE := Vector2(140, 150)
const CARD_SIZE := Vector2(200, 240)
const GRID_COLUMNS := 3
const BIG_CARD_MIN_H := 380.0  # 큰 카드 최소 높이(남는 높이는 카드가 3, 스킬·설명 칸이 1 비율로 받는다)
const INFO_MIN_H := 110.0  # 스킬·설명 칸 최소 높이(넘치면 스크롤)
const PROMOTE_COLOR := Color("8A5CC8")  # [승급] 버튼(SR 보라 — [레벨업] 호박색과 구분)
const PREVIEW_COLOR := Color("8A5A0B")  # 승급 미리보기 글자(진한 금색)
const GRADE_RANK := {"SSR": 0, "SR": 1, "R": 2}
const SORTS := ["power", "grade", "level"]
const SORT_NAMES := {"power": "전투력", "grade": "등급", "level": "레벨"}
const HINT := "슬롯을 누른 뒤 영웅을 고르세요"
const GREEN := Color(0.13, 0.58, 0.24)
const REASON_COLOR := Color(0.78, 0.22, 0.18)
const SWIPE_PX := 80.0
const TEN := 10
const STAT_NAMES := ["HP", "공격", "공격 간격", "사거리", "전투력"]
const LOCKED_GRAY := Color(0.55, 0.55, 0.58)  # 잠긴 스킬 줄
const UNLOCK_GOLD := Color("C8901A")  # 해금 반짝임

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
var skill_ui: Array = []  # 스킬 칸마다 {box, lock, label}(개정 17)
var desc_label: Label
var level_button: Button
var ten_button: Button
var deploy_button: Button
var promote_button: Button
var promote_preview: Label  # 승급 미리보기 "승급하면 HP·공격 → ×1.5 · 최대 레벨 30 → 40"(최대면 "최대 승급 ★5 — HP·공격 ×7.59")
var reason_label: Label  # [레벨업] 못 하는 이유
var promote_reason: Label  # [승급] 못 하는 이유("조각 부족"·"최대 승급")
var prev_button: Button
var next_button: Button
var celebrations := 0  # 성공 연출 횟수(테스트용)
var promotions_shown := 0  # 승급 성공 연출 횟수(테스트용)
var unlocks_shown := 0  # 스킬 해금 반짝임 횟수(테스트용)

var _list_view: VBoxContainer
var _detail_view: VBoxContainer
var _slot_grid: GridContainer
var _hero_grid: GridContainer
var _one := {}  # [레벨업] 버튼 안 {title, gold} Label
var _ten := {}
var _promo := {}  # [승급] 버튼 안 {title, line} Label
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
	Economy.promoted.connect(_on_promoted)


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
	_detail_view.add_theme_constant_override("separation", 8)
	_detail_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_view.visible = false
	_detail_view.gui_input.connect(_on_detail_input)  # 좌우 스와이프
	content.add_child(_detail_view)
	# 맨 위: 큰 카드(남는 높이를 받아 피규어를 키운다 — 개정 15 사용자 요청)
	big_card = HeroCardScript.new()
	big_card.custom_minimum_size = Vector2(0, BIG_CARD_MIN_H)
	big_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	big_card.size_flags_stretch_ratio = 3.0
	big_card.live = true  # 개정 14 §2: 실시간 피규어(대기 애니메이션), 끌어서 돌린다
	_detail_view.add_child(big_card)
	# 이름·등급 + [배치]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_detail_view.add_child(head)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 0)
	head.add_child(names)
	title_label = _label("", 30, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	title_label.add_theme_color_override("font_outline_color", HudScript.INK)
	title_label.add_theme_constant_override("outline_size", 6)
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	names.add_child(title_label)
	grade_label = _label("", 22, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	names.add_child(grade_label)
	deploy_button = _button("배치", UiKit.STEEL, 24)
	deploy_button.custom_minimum_size = Vector2(170, 64)
	deploy_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	deploy_button.pressed.connect(deploy_here)
	head.add_child(deploy_button)
	# Lv N / 최대 + 막대
	var lv_row := HBoxContainer.new()
	lv_row.add_theme_constant_override("separation", 12)
	_detail_view.add_child(lv_row)
	level_label = _label("", 28, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	level_label.custom_minimum_size = Vector2(170, 0)
	lv_row.add_child(level_label)
	level_bar = ProgressBar.new()
	level_bar.custom_minimum_size = Vector2(0, 20)
	level_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	level_bar.show_percentage = false
	level_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.apply_bar(level_bar, UiKit.AMBER)
	lv_row.add_child(level_bar)
	# 능력치 2열(이름 · 값 · 다음 레벨) × 3줄
	var stats := GridContainer.new()
	stats.columns = 6
	stats.add_theme_constant_override("h_separation", 10)
	stats.add_theme_constant_override("v_separation", 2)
	_detail_view.add_child(stats)
	for n in STAT_NAMES:
		stats.add_child(_label(n, 22, HudScript.INK.lightened(0.25), HORIZONTAL_ALIGNMENT_LEFT))
		var v := _label("", 24, HudScript.INK, HORIZONTAL_ALIGNMENT_RIGHT)
		v.custom_minimum_size = Vector2(76, 0)
		stats.add_child(v)
		stat_values.append(v)
		var nx := _label("", 20, GREEN, HORIZONTAL_ALIGNMENT_LEFT)
		nx.custom_minimum_size = Vector2(130, 0)
		stats.add_child(nx)
		stat_nexts.append(nx)
	promote_preview = _label("", 22, PREVIEW_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
	promote_preview.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_detail_view.add_child(promote_preview)
	# 스킬·설명문(넘치면 스크롤)
	var info := ScrollContainer.new()
	info.custom_minimum_size = Vector2(0, INFO_MIN_H)
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_view.add_child(info)
	var info_box := VBoxContainer.new()
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_box.add_theme_constant_override("separation", 4)
	info.add_child(info_box)
	for i in GameData.HERO_SKILL_COLS.size():
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		info_box.add_child(box)
		var lock := Control.new()
		lock.custom_minimum_size = Vector2(22, 26)
		lock.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock.draw.connect(_draw_lock.bind(lock))
		box.add_child(lock)
		var l := _wrap_label(21, HudScript.INK)
		l.custom_minimum_size.x = 570.0  # 자물쇠 칸만큼 좁게(설명문 600과 같은 폭)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(l)
		skill_ui.append({"box": box, "lock": lock, "label": l})
	desc_label = _wrap_label(19, HudScript.INK.lightened(0.3))
	info_box.add_child(desc_label)
	# [레벨업] [×10] [승급], 아래 칸마다 못 하는 이유
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_detail_view.add_child(row)
	_one = _cost_button("레벨업")
	level_button = _one.button
	level_button.pressed.connect(_press_level.bind(false))
	_ten = _cost_button("×10")
	ten_button = _ten.button
	ten_button.pressed.connect(_press_level.bind(true))
	_promo = _promote_button()
	promote_button = _promo.button
	promote_button.pressed.connect(_press_promote)
	for b in [level_button, ten_button, promote_button]:
		row.add_child(b)
	var why_row := HBoxContainer.new()
	why_row.add_theme_constant_override("separation", 10)
	_detail_view.add_child(why_row)
	reason_label = _label("", 20, REASON_COLOR)
	promote_reason = _label("", 20, REASON_COLOR)
	for l in [reason_label, _label("", 20), promote_reason]:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		why_row.add_child(l)
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


## [승급] 버튼(개정 15): 위 "승급 ★p→p+1", 아래 "조각 12 / 25"(버튼 안, 입력은 버튼이 받는다).
func _promote_button() -> Dictionary:
	var b := _button("", PROMOTE_COLOR)
	b.custom_minimum_size = Vector2(0, 96)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var title := _on_button_label("승급", 28)
	box.add_child(title)
	var line := _on_button_label("", 22)
	box.add_child(line)
	return {"button": b, "title": title, "line": line}


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
		var p := GameData.hero_power(h, Economy.level_of(id), Economy.promotion_of(id), Economy.levels)
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
		c.stars = Economy.promotion_of(id) if id != null else 0
		c.corner = str(i + 1)
		c.highlight = i == selected_slot
		c.queue_redraw()
	for id in hero_cards:
		var c = hero_cards[id]
		var pr := Economy.promotion_of(id)
		c.stars = pr
		c.level = Economy.level_of(id)
		c.power = GameData.hero_power(GameData.hero(id), c.level, pr, Economy.levels)
		c.deployed = deployed.has(id)
		c.can_level = Economy.levelup_block(id) == ""
		c.shards = Economy.shards_of(id)  # 개정 15: 조각 막대·금색 ⬆
		c.shard_need = Economy.promote_cost(id)
		c.can_promote = Economy.promote_block(id) == ""
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


## [승급](개정 15): 오프라인은 곧바로, 온라인은 응답에 promoted. 못 하면 Economy가 알림.
func _press_promote() -> void:
	_before = stat_values.map(func(l): return l.text)
	Economy.promote(detail_id)


## 승급 성공 연출: 큰 카드 금색 빛 조각 + 별 하나가 날아와 박힘, 최대 레벨 글자 튀어 오름, 바뀐 능력치 숫자 초록 반짝임.
## 이 승급으로 열린 스킬(개정 17)은 알림 "스킬 해금! 이름"(상세를 안 보고 있어도) + 그 줄 금색 반짝임.
func _on_promoted(id: String, promotion: int) -> void:
	var rows := skill_rows(GameData.hero(id), promotion) if not GameData.hero(id).is_empty() else []
	var opened := range(rows.size()).filter(func(i): return rows[i].star == promotion and promotion > 0)
	for i in opened:
		Economy.notice.emit("스킬 해금! " + rows[i].name)
	if not is_showing_detail() or id != detail_id:
		return
	_refresh_detail()
	promotions_shown += 1
	big_card.promote_fx()
	_pop(level_label)
	_flash_changed()
	for i in opened:
		var l: Label = skill_ui[i].label
		l.add_theme_color_override("font_color", UNLOCK_GOLD)
		l.create_tween().tween_property(l, "theme_override_colors/font_color", HudScript.INK, 0.9)
		_pop(l)
		unlocks_shown += 1


## 글자를 잠깐 키웠다 되돌린다.
func _pop(l: Label) -> void:
	l.pivot_offset = l.size / 2.0
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE * 1.35, 0.12)
	tw.tween_property(l, "scale", Vector2.ONE, 0.18)


## 누르기 전(_before)과 글자가 달라진 능력치만 초록으로 반짝인다.
func _flash_changed() -> void:
	for i in stat_values.size():
		var l: Label = stat_values[i]
		if i < _before.size() and l.text != _before[i]:
			l.add_theme_color_override("font_color", GREEN)
			l.create_tween().tween_property(l, "theme_override_colors/font_color", HudScript.INK, 0.6)


## 성공 연출: 큰 카드 빛 조각, 레벨 글자 튀어 오름, 바뀐 능력치 숫자 초록 반짝임.
func _on_leveled(id: String, _level: int) -> void:
	if not is_showing_detail() or id != detail_id:
		return
	_refresh_detail()
	celebrations += 1
	big_card.burst()
	_pop(level_label)
	_flash_changed()


func _refresh_detail() -> void:
	var id := detail_id
	var h := GameData.hero(id)
	if h.is_empty() or int(Economy.heroes.get(id, 0)) < 1:
		return
	var pr := Economy.promotion_of(id)
	var lv := Economy.level_of(id)
	var mx := GameData.max_level(pr)
	big_card.hero_id = id
	big_card.stars = pr
	big_card.queue_redraw()
	title_label.text = "%s %s" % [h.title, h.name]
	title_label.add_theme_color_override("font_color", UiKit.GRADE_COLORS[h.grade].lightened(0.15))
	grade_label.text = "%s · %s" % [h.grade, "근접" if h.role == "melee" else "원거리"]
	level_label.text = "Lv %d / %d" % [lv, mx]
	level_bar.max_value = mx
	level_bar.value = lv
	var now := GameData.hero_stats(h, lv, pr, Economy.levels)  # 연구소 보너스 포함(개정 12, 개정 13: 막사 보너스 없음)
	var nxt := GameData.hero_stats(h, lv + 1, pr, Economy.levels)
	var grow := lv < mx
	var rows := [
		[roundi(now.hp), roundi(nxt.hp)], [roundi(now.atk), roundi(nxt.atk)], null, null,
		[GameData.hero_power(h, lv, pr, Economy.levels), GameData.hero_power(h, lv + 1, pr, Economy.levels)]]
	for i in rows.size():
		var r = rows[i]
		if r == null:
			stat_values[i].text = Skills.num_text(h.atk_interval) + "초" if i == 2 else Skills.num_text(h.range) + "m"
			stat_nexts[i].text = ""
		else:
			stat_values[i].text = UiKit.commas(r[0])
			stat_nexts[i].text = "→ %s (+%s)" % [UiKit.commas(r[1]), UiKit.commas(r[1] - r[0])] if grow else ""
	var sk_rows := skill_rows(h, pr)
	for i in skill_ui.size():
		var ui: Dictionary = skill_ui[i]
		ui.box.visible = i < sk_rows.size()
		if i < sk_rows.size():
			ui.label.text = sk_rows[i].text
			ui.lock.visible = sk_rows[i].locked
			ui.label.add_theme_color_override("font_color", LOCKED_GRAY if sk_rows[i].locked else HudScript.INK)
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
	# 승급(개정 15): 버튼 안 "조각 12 / 25"(최대면 "MAX"), 미리보기 한 줄, 못 하는 이유
	var need := Economy.promote_cost(id)
	var pwhy := Economy.promote_block(id)
	_promo.title.text = "승급" if need <= 0 else "승급 ★%d" % (pr + 1)
	_promo.line.text = "조각 %d / %d" % [Economy.shards_of(id), need] if need > 0 else "조각 %d · MAX" % Economy.shards_of(id)
	promote_button.disabled = pwhy != ""
	promote_reason.text = Economy.PROMOTE_TEXT.get(pwhy, "") if pwhy != "waiting" else ""
	if need > 0:
		promote_preview.text = "승급하면 HP·공격 → ×%s · 최대 레벨 %d → %d" % [Skills.num_text(GameData.config_num("promote_mult")), mx, GameData.max_level(pr + 1)]
		var next := sk_rows.filter(func(r): return r.locked)
		if not next.is_empty():  # 개정 17: 다음 해금
			promote_preview.text += "\n★%d 달성 시 스킬 해금: %s" % [next[0].star, next[0].name]
	else:
		promote_preview.text = "최대 승급 ★%d — HP·공격 ×%s" % [pr, Skills.num_text(GameData.promote_mult(pr))]
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


## 스킬 줄(칸 순서, 개정 17): {kind, name, star(해금 승급), locked, text}. 해금 = "이름 — 숫자를 넣은 설명", 잠김 = "이름 — ★3에서 해금".
static func skill_rows(h: Dictionary, promotion: int) -> Array:
	var out := []
	var kinds: Array = h.skills.keys()
	for i in kinds.size():
		var star := GameData.skill_unlock_star(i)
		var nm := Skills.name_of(kinds[i], h.id)
		var locked := promotion < star
		out.append({"kind": kinds[i], "name": nm, "star": star, "locked": locked,
			"text": "%s — %s" % [nm, "★%d에서 해금" % star if locked else Skills.describe(kinds[i], h.skills[kinds[i]])]})
	return out


## 자물쇠(잠긴 스킬 줄): 고리 + 몸통.
func _draw_lock(c: Control) -> void:
	c.draw_arc(Vector2(11, 12), 6.0, PI, TAU, 10, LOCKED_GRAY, 3.0)
	c.draw_rect(Rect2(3, 12, 16, 12), LOCKED_GRAY)
	c.draw_rect(Rect2(10, 16, 2, 4), Color.WHITE)

extends "res://scripts/ui_window.gd"
## 영웅 창(스펙 §5, HUD [영웅]으로 연다): 위 배치 슬롯(GameState.hero_count칸) + 아래 보유 영웅 격자(등급 → 이름, 별)
## + [정보]·[적용]·[닫기]. 슬롯을 탭하고 영웅 카드를 탭하면 그 슬롯에 놓는다(같은 영웅이 다른 슬롯에 있으면 서로 바꾼다).
## 바뀐 배치는 [적용]을 누를 때 Economy.set_deploy(온라인 /v1/deploy, 오프라인 저장) — 다음 리필 때 영웅이 바뀌고,
## 방치 모드면 곧바로(main). 카드를 길게 누르거나 [정보]를 누르면 상세: 능력치(별 반영), 스킬 두 개의 한국어 설명, 설명문.

const GameData := preload("res://scripts/game_data.gd")
const Skills := preload("res://scripts/skills.gd")
const HeroCardScript := preload("res://scripts/hero_card.gd")

const DIALOG_W := 680
const SLOT_SIZE := Vector2(132, 168)
const CARD_SIZE := Vector2(96, 128)
const GRID_COLUMNS := 6
const GRID_H := 560.0  # 보유 격자 보이는 높이: 6 × 4줄 = 24장(넘치면 스크롤)
const GRADE_RANK := {"SSR": 0, "SR": 1, "R": 2}
const HINT := "슬롯을 누른 뒤 영웅을 고르세요"

var slot_cards: Array = []
var hero_cards := {}  # 영웅 id → 보유 격자 카드
var info_button: Button
var apply_button: Button
var work: Array = []  # 편집 중인 배치(슬롯 i → 영웅 id 또는 null)
var selected_slot := -1
var focus := ""  # [정보]가 보여 줄 영웅

var _main_view: VBoxContainer
var _detail_view: VBoxContainer
var _slot_grid: GridContainer
var _hero_grid: GridContainer
var _detail_title: Label
var _detail_stats: Label
var _detail_skills: Label
var _detail_desc: Label


func _ready() -> void:
	_build_window(DIALOG_W, 12)
	content.add_child(_title("영웅"))
	_main_view = VBoxContainer.new()
	_main_view.add_theme_constant_override("separation", 12)
	content.add_child(_main_view)
	var slots_center := CenterContainer.new()
	_main_view.add_child(slots_center)
	_slot_grid = GridContainer.new()
	_slot_grid.columns = 4
	_slot_grid.add_theme_constant_override("h_separation", 12)
	_slot_grid.add_theme_constant_override("v_separation", 12)
	slots_center.add_child(_slot_grid)
	_main_view.add_child(_label(HINT, 22, HudScript.INK.lightened(0.3)))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, GRID_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_main_view.add_child(scroll)
	var grid_center := CenterContainer.new()
	grid_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_center)
	_hero_grid = GridContainer.new()
	_hero_grid.columns = GRID_COLUMNS
	_hero_grid.add_theme_constant_override("h_separation", 6)
	_hero_grid.add_theme_constant_override("v_separation", 10)
	grid_center.add_child(_hero_grid)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_main_view.add_child(row)
	info_button = _button("정보", UiKit.STEEL)
	info_button.pressed.connect(func(): if focus != "": show_detail(focus))
	apply_button = _button("적용")
	apply_button.pressed.connect(apply)
	var close_button := _button("닫기", UiKit.STEEL)
	close_button.pressed.connect(close)
	for b in [info_button, apply_button, close_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)

	_detail_view = VBoxContainer.new()
	_detail_view.add_theme_constant_override("separation", 14)
	_detail_view.visible = false
	content.add_child(_detail_view)
	_detail_title = _label("", 32)
	_detail_title.add_theme_color_override("font_outline_color", HudScript.INK)
	_detail_title.add_theme_constant_override("outline_size", 6)
	_detail_view.add_child(_detail_title)
	_detail_stats = _wrap_label(26)
	_detail_view.add_child(_detail_stats)
	_detail_skills = _wrap_label(24)
	_detail_view.add_child(_detail_skills)
	_detail_desc = _wrap_label(22)
	_detail_desc.add_theme_color_override("font_color", HudScript.INK.lightened(0.3))
	_detail_view.add_child(_detail_desc)
	var back := _button("뒤로", UiKit.STEEL)
	back.pressed.connect(_show_main)
	_detail_view.add_child(back)
	Economy.roster_changed.connect(func(): if visible: _rebuild())


func _on_open() -> void:
	work = GameState.deploy()
	selected_slot = -1
	focus = ""
	_show_main()


## 보유 영웅 id: 등급(SSR → SR → R) → 이름 순. 표에 없는 영웅은 뺀다.
static func owned_sorted(heroes: Dictionary) -> Array:
	var ids := heroes.keys().filter(func(id): return int(heroes[id]) >= 1 and not GameData.hero(id).is_empty())
	ids.sort_custom(func(a, b):
		var ga: int = GRADE_RANK[GameData.hero(a).grade]
		var gb: int = GRADE_RANK[GameData.hero(b).grade]
		return ga < gb if ga != gb else GameData.hero(a).name < GameData.hero(b).name)
	return ids


func tap_slot(i: int) -> void:
	selected_slot = -1 if selected_slot == i else i
	if work[i] != null:
		focus = work[i]
	_rebuild()


## 영웅 카드 탭: 고른 슬롯이 있으면 거기에 놓는다(다른 슬롯에 있으면 서로 바꾼다).
func tap_hero(id: String) -> void:
	focus = id
	if selected_slot >= 0:
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


func show_detail(id: String) -> void:
	var h := GameData.hero(id)
	if h.is_empty():
		return
	var copies := int(Economy.heroes.get(id, 1))
	var stars := HeroCardScript.stars_of(copies)
	var mult := GameData.star_mult(copies)
	_detail_title.text = "[%s] %s %s" % [h.grade, h.title, h.name]
	_detail_title.add_theme_color_override("font_color", UiKit.GRADE_COLORS[h.grade].lightened(0.15))
	_detail_stats.text = "보유 %d (별 %d)\nHP %s · 공격 %s\n사거리 %sm · 공격 간격 %s초" % [copies, stars,
		Skills.num_text(roundf(h.hp * mult)), Skills.num_text(roundf(h.atk * mult)), Skills.num_text(h.range), Skills.num_text(h.atk_interval)]
	_detail_skills.text = "\n".join(skill_lines(h))
	_detail_desc.text = h.desc
	_main_view.visible = false
	_detail_view.visible = true
	_fit()


## 스킬 두 개(있는 만큼): "이름 — 숫자를 넣은 설명".
static func skill_lines(h: Dictionary) -> Array:
	var out := []
	for kind in h.skills:
		out.append("%s — %s" % [Skills.NAMES.get(kind, kind), Skills.describe(kind, h.skills[kind])])
	return out


func is_showing_detail() -> bool:
	return visible and _detail_view.visible


func _show_main() -> void:
	_detail_view.visible = false
	_main_view.visible = true
	_rebuild()
	_fit()


## 슬롯·보유 카드를 work·보유에 맞춘다(보유 목록이 바뀌었을 때만 카드를 다시 만든다).
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
	var ids := owned_sorted(Economy.heroes)
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
			card.long_pressed.connect(func(_c): show_detail(id))
			_hero_grid.add_child(card)
			hero_cards[id] = card
	for i in slot_cards.size():
		var c = slot_cards[i]
		var id = work[i]
		c.hero_id = id if id != null else ""
		c.stars = HeroCardScript.stars_of(int(Economy.heroes.get(id, 1))) if id != null else 0
		c.corner = str(i + 1)
		c.highlight = i == selected_slot
		c.queue_redraw()
	for id in hero_cards:
		var c = hero_cards[id]
		var at := work.find(id)
		c.stars = HeroCardScript.stars_of(int(Economy.heroes[id]))
		c.corner = str(at + 1) if at >= 0 else ""
		c.highlight = id == focus
		c.queue_redraw()
	apply_button.disabled = work == GameState.deploy()
	info_button.disabled = focus == ""


func _wrap_label(font_size: int) -> Label:
	var l := _label("", font_size, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(DIALOG_W - 48, 0)
	return l

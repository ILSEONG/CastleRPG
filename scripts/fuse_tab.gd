extends VBoxContainer
## 영웅 창 [합성] 탭(2026-11-02 사용자 "처음 선택한 영웅이 합성대상 영웅의 등급으로 정해지는거야, 합성이 있는 다른게임 참고해서 Ui도 다시 만들어").
## 세븐나이츠 키우기·AFK 아레나의 영웅 합성처럼 위에 합성대(첫 영웅 큰 카드 → 결과 등급 "?" 카드), 가운데 "넣은 조각 n / 10" 막대와
## [비우기] [자동 채우기] [합성], 아래에 조각이 있는 영웅 카드 격자. 카드를 누르면 조각 1개를 넣는다(길게 누르면 1개 뺀다).
## 처음 넣은 영웅의 등급이 합성 등급이 되고(R → SR, SR → SSR, SSR → UR), 다른 등급 카드는 흐려져 넣을 수 없다. 다 빼면 등급이 풀린다.
## [합성]은 합이 Economy.fuse_cost()일 때만 — fused(picks)를 받은 영웅 창이 모집 창으로 결과 연출을 넘긴다.

const Lang := preload("res://scripts/lang.gd")
const GameData := preload("res://scripts/game_data.gd")
const UiKit := preload("res://scripts/ui_kit.gd")
const HeroCardScript := preload("res://scripts/hero_card.gd")

signal fused(picks: Dictionary)

const SUB := Color(0.25, 0.22, 0.2, 0.8)
const CARD := Vector2(150, 180)
const BIG := Vector2(170, 204)
const DIM := Color(1, 1, 1, 0.35)
const GRADE_ORDER := {"R": 0, "SR": 1, "SSR": 2}

var picks := {}  # 영웅 id → 넣은 조각 수
var order: Array = []  # 넣은 순서(첫 영웅 = order[0])
var grade := ""  # 합성 등급(첫 영웅의 등급). "" = 아직 안 골랐다
var cards := {}  # 영웅 id → 격자 카드
var main_card  # 합성대 첫 영웅 카드
var result_box: PanelContainer
var result_label: Label
var hint_label: Label
var count_label: Label
var bar: ProgressBar
var empty_label: Label
var clear_button: Button
var auto_button: Button
var fuse_button: Button
var _grid: GridContainer


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var stage := PanelContainer.new()
	stage.add_theme_stylebox_override("panel", UiKit.panel(Color(0.42, 0.33, 0.26, 0.16), 14.0, 14))
	add_child(stage)
	var stage_col := VBoxContainer.new()
	stage_col.add_theme_constant_override("separation", 8)
	stage.add_child(stage_col)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	stage_col.add_child(row)
	main_card = HeroCardScript.new()
	main_card.custom_minimum_size = BIG
	main_card.empty_text = Lang.t("fuse_tab.pick")
	main_card.tapped.connect(func(_c): clear())
	row.add_child(main_card)
	var arrow := _label("→", 54, UiKit.INK.lightened(0.25))
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(arrow)
	result_box = PanelContainer.new()
	result_box.custom_minimum_size = BIG
	row.add_child(result_box)
	result_label = _label("?", 48, Color.WHITE)
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.add_theme_color_override("font_outline_color", Color(UiKit.INK, 0.9))
	result_label.add_theme_constant_override("outline_size", 8)
	result_box.add_child(result_label)
	hint_label = _label("", 22, SUB)
	stage_col.add_child(hint_label)
	count_label = _label("", 26)
	stage_col.add_child(count_label)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 18)
	stage_col.add_child(bar)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	stage_col.add_child(buttons)
	clear_button = _button(Lang.t("fuse_tab.clear"), UiKit.STEEL)
	clear_button.pressed.connect(clear)
	auto_button = _button(Lang.t("fuse_tab.auto"), UiKit.STEEL)
	auto_button.pressed.connect(autofill)
	fuse_button = _button(Lang.t("fuse_tab.fuse"), UiKit.AMBER)
	fuse_button.pressed.connect(_on_fuse)
	for b in [clear_button, auto_button, fuse_button]:
		buttons.add_child(b)
	add_child(_label(Lang.t("fuse_tab.grid_hint"), 20, SUB))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	center.add_child(_grid)
	empty_label = _label(Lang.t("fuse_tab.empty"), 22, SUB)
	add_child(empty_label)


func _label(text: String, font_size: int, color: Color = UiKit.INK) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 64)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 24)
	UiKit.apply_button(b, color, 14.0)
	return b


## 조각이 있는 가진 R·SR·SSR 영웅(등급 낮은 순 → 조각 많은 순 → 표 순서). UR은 합성 재료가 아니다.
func candidates() -> Array:
	var file := GameData.heroes().map(func(h): return h.id)
	var ids: Array = GameData.heroes().filter(func(h): return GRADE_ORDER.has(h.grade) and int(Economy.heroes.get(h.id, 0)) >= 1 and Economy.shards_of(h.id) > 0).map(func(h): return h.id)
	ids.sort_custom(func(a, b): return [GRADE_ORDER[GameData.hero(a).grade], -Economy.shards_of(a), file.find(a)] < [GRADE_ORDER[GameData.hero(b).grade], -Economy.shards_of(b), file.find(b)])
	return ids


func total() -> int:
	var t := 0
	for id in picks:
		t += int(picks[id])
	return t


## 카드 누름: 조각 1개 넣기. 첫 영웅이면 그 등급이 합성 등급이 된다. 다른 등급이면 알림만.
func add(id: String) -> void:
	var g: String = GameData.hero(id).get("grade", "")
	if grade != "" and g != grade:
		Economy.notice.emit(Lang.t("fuse_tab.other_grade") % grade)
		return
	if total() >= Economy.fuse_cost() or int(picks.get(id, 0)) >= Economy.shards_of(id):
		return
	if grade == "":
		grade = g
	if not picks.has(id):
		order.append(id)
	picks[id] = int(picks.get(id, 0)) + 1
	refresh()


## 길게 누름: 조각 1개 빼기. 다 빼면 그 영웅이 빠지고, 아무것도 없으면 등급이 풀린다.
func remove(id: String) -> void:
	if not picks.has(id):
		return
	picks[id] = int(picks[id]) - 1
	if picks[id] <= 0:
		picks.erase(id)
		order.erase(id)
	if picks.is_empty():
		grade = ""
	refresh()


func clear() -> void:
	picks = {}
	order = []
	grade = ""
	refresh()


## [자동 채우기]: 합성 등급(없으면 조각이 가장 많은 등급 — 같으면 낮은 등급)으로 ★5까지 쓰고 남는 조각부터 채운다(Economy.fuse_autofill).
## 먼저 고른 영웅의 조각은 그대로 두고 나머지만 채운다.
func autofill() -> void:
	var g := grade
	if g == "":
		var best := -1
		for k in ["R", "SR", "SSR"]:
			if Economy.grade_shards(k) > best:
				best = Economy.grade_shards(k)
				g = k
	var fill: Dictionary = Economy.fuse_autofill(g)
	if fill.is_empty():
		return
	grade = g
	var need := Economy.fuse_cost() - total()
	for id in fill:  # 이미 넣은 영웅 먼저 늘린다(첫 영웅이 그대로 합성대에 남게)
		if need <= 0:
			break
		var room := Economy.shards_of(id) - int(picks.get(id, 0))
		var n := mini(room, need)
		if n > 0:
			if not picks.has(id):
				order.append(id)
			picks[id] = int(picks.get(id, 0)) + n
			need -= n
	refresh()


func _on_fuse() -> void:
	if not Economy.fuse_ok(picks):
		return
	var p := picks.duplicate()
	clear()
	fused.emit(p)


## 격자(가진 영웅·조각이 바뀌었을 때만 다시 만든다)와 합성대·막대·버튼을 맞춘다. 넣은 조각이 이제 보유보다 많으면 줄인다.
func refresh() -> void:
	for id in picks.keys():
		var n := mini(int(picks[id]), Economy.shards_of(id))
		if n <= 0 or int(Economy.heroes.get(id, 0)) < 1:
			picks.erase(id)
			order.erase(id)
		else:
			picks[id] = n
	if picks.is_empty():
		grade = ""
	var ids := candidates()
	if ids != cards.keys():
		for c in _grid.get_children():
			_grid.remove_child(c)
			c.queue_free()
		cards.clear()
		for id in ids:
			var card = HeroCardScript.new()
			card.custom_minimum_size = CARD
			card.hero_id = id
			card.hide_title = true
			card.tapped.connect(func(_c): add(id))
			card.long_pressed.connect(func(_c): remove(id))
			_grid.add_child(card)
			cards[id] = card
	for id in cards:
		var c = cards[id]
		var n := int(picks.get(id, 0))
		c.stars = Economy.promotion_of(id)
		c.shards = Economy.shards_of(id)
		c.shard_need = Economy.promote_cost(id)
		c.checked = n > 0
		c.corner = "+%d" % n if n > 0 else ""
		c.modulate = DIM if grade != "" and GameData.hero(id).grade != grade else Color.WHITE
		c.queue_redraw()
	empty_label.visible = ids.is_empty()
	var first: String = order[0] if not order.is_empty() else ""
	main_card.hero_id = first
	main_card.stars = Economy.promotion_of(first) if first != "" else 0
	main_card.queue_redraw()
	var to: String = Economy.FUSE_NEXT.get(grade, "")
	var col: Color = UiKit.GRADE_COLORS.get(to, UiKit.STEEL)
	result_box.add_theme_stylebox_override("panel", UiKit.panel(col.darkened(0.15), 12.0, 8))
	result_label.text = "%s\n?" % to if to != "" else "?"
	hint_label.text = Lang.t("fuse_tab.hint_on") % [grade, Economy.fuse_cost(), to] if to != "" else Lang.t("fuse_tab.hint_off") % Economy.fuse_cost()
	count_label.text = Lang.t("fuse_tab.count") % [total(), Economy.fuse_cost()]
	bar.max_value = Economy.fuse_cost()
	bar.value = total()
	fuse_button.disabled = not Economy.fuse_ok(picks)
	UiKit.apply_button(fuse_button, col if to != "" else UiKit.AMBER, 14.0)
	clear_button.disabled = picks.is_empty()
	auto_button.disabled = ids.is_empty() or total() >= Economy.fuse_cost()

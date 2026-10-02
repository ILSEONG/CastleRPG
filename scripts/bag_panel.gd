extends "res://scripts/ui_window.gd"
## 장비 목록 창(개정 18 §8). 두 쓰임:
## - 보관함(던전 탭 [보관함] → open_bag): 제목 "보관함 n / 상한", [부위]·[등급]·[정렬] 순환 버튼, 장비 줄 목록 — 줄 오른쪽 체크로 여러 개 고름
##   (장착 중은 못 고름, "장착: 이름"), 아래 "n개 선택 · +골드"와 [판매](Economy.sell_items).
## - 장비 고르기(영웅 상세 장비 칸 → open_pick(영웅, 부위)): 그 부위(무기는 그 영웅 무기 종류만) 장비 줄마다 [장착], 위에 지금 낀 장비와
##   [해제]. 장착·해제하면 닫는다.
## 줄 = 장비 칸(item_tile, 등급 테두리) + "SR 모자 Lv 3" + 능력치 + 장착 표시. 층 4(탭 바 위) — 닫을 때까지 뒤 창은 그대로 있다.
# ponytail: 바뀔 때마다 줄을 전부 다시 만든다(상한 300줄). 느려지면 줄 재사용.

const GameData := preload("res://scripts/game_data.gd")
const Art := preload("res://scripts/art.gd")
const ItemTileScript := preload("res://scripts/item_tile.gd")

const ITEM_NAMES := {"weapon": "무기", "hat": "모자", "top": "상의", "bottom": "하의", "shoes": "신발", "pauldron": "견장", "gloves": "장갑",
	"sword": "검", "axe": "도끼", "staff": "지팡이", "crossbow": "석궁", "dagger": "단검"}
const SORTS := ["grade", "level", "new"]
const SORT_NAMES := {"grade": "등급", "level": "레벨", "new": "최신"}
const TILE_PX := 72.0
const EMPTY_TEXT := "장비가 없습니다"
const OWNER_COLOR := Color(0.2, 0.42, 0.75)

var mode := "bag"  # "bag" | "pick"
var hero_id := ""  # pick: 장착할 영웅
var slot := ""  # pick: 부위
var slot_filter := ""  # bag: "" = 전체, 아니면 GameData.EQUIP_SLOTS 하나
var grade_filter := ""  # bag: "" = 전체
var sort_mode := "grade"
var selected := {}  # bag: 고른 장비 id → true
var rows := {}  # 장비 id → {box, check(bag) 또는 equip(pick) 버튼}
var title_label: Label
var current_label: Label  # pick: 지금 낀 장비
var unequip_button: Button
var slot_button: Button
var grade_button: Button
var sort_button: Button
var sum_label: Label
var sell_button: Button
var empty_label: Label

var _pick_row: HBoxContainer
var _filter_row: HBoxContainer
var _sell_row: HBoxContainer
var _list: VBoxContainer


func _ready() -> void:
	_build_window(0, 10)
	layer = 4  # 영웅·던전 시트와 탭 바 위
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	title_label = _title("")
	content.add_child(title_label)
	_pick_row = HBoxContainer.new()
	_pick_row.add_theme_constant_override("separation", 10)
	content.add_child(_pick_row)
	current_label = _label("", 24, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	current_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	current_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pick_row.add_child(current_label)
	unequip_button = _button("해제", UiKit.STEEL, 26)
	unequip_button.custom_minimum_size = Vector2(140, 56)
	unequip_button.pressed.connect(unequip)
	_pick_row.add_child(unequip_button)
	_filter_row = HBoxContainer.new()
	_filter_row.add_theme_constant_override("separation", 8)
	content.add_child(_filter_row)
	slot_button = _button("", UiKit.STEEL, 22)
	slot_button.pressed.connect(cycle_slot)
	grade_button = _button("", UiKit.STEEL, 22)
	grade_button.pressed.connect(cycle_grade)
	sort_button = _button("", UiKit.STEEL, 22)
	sort_button.pressed.connect(cycle_sort)
	for b in [slot_button, grade_button, sort_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_filter_row.add_child(b)
	empty_label = _label(EMPTY_TEXT, 26, HudScript.INK.lightened(0.3))
	content.add_child(empty_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_sell_row = HBoxContainer.new()
	_sell_row.add_theme_constant_override("separation", 10)
	content.add_child(_sell_row)
	sum_label = _label("", 24, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	sum_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sell_row.add_child(sum_label)
	sell_button = _button("판매")
	sell_button.custom_minimum_size = Vector2(160, 56)
	sell_button.pressed.connect(sell)
	_sell_row.add_child(sell_button)
	var close_button := _button("닫기", UiKit.STEEL)
	close_button.pressed.connect(close)
	content.add_child(close_button)
	_fit_sheet()
	Economy.items_changed.connect(_refresh)


## 보관함 시트를 연다(고른 것·필터는 비운다).
func open_bag() -> void:
	mode = "bag"
	selected = {}
	open()


## 영웅 hero의 부위 s 장비 고르기를 연다.
func open_pick(hero: String, s: String) -> void:
	mode = "pick"
	hero_id = hero
	slot = s
	open()


func _on_open() -> void:
	_refresh()


func cycle_slot() -> void:
	var opts: Array = [""] + GameData.EQUIP_SLOTS
	slot_filter = opts[(opts.find(slot_filter) + 1) % opts.size()]
	_refresh()


func cycle_grade() -> void:
	var opts: Array = [""] + GameData.EQUIP_GRADES
	grade_filter = opts[(opts.find(grade_filter) + 1) % opts.size()]
	_refresh()


func cycle_sort() -> void:
	sort_mode = SORTS[(SORTS.find(sort_mode) + 1) % SORTS.size()]
	_refresh()


## 보관함 줄 체크(장착 중은 무시).
func toggle(id: int) -> void:
	if Economy.item_owner(id) != "":
		return
	if selected.has(id):
		selected.erase(id)
	else:
		selected[id] = true
	_refresh()


func sell() -> void:
	var ids := selected.keys()
	var g := Economy.sell_items(ids)
	if g > 0:
		Economy.notice.emit("장비 %d개 판매 +%s 골드" % [ids.size(), UiKit.commas(g)])
	selected = {}
	_refresh()


func equip(id: int) -> void:
	if Economy.equip(hero_id, slot, id):
		close()


func unequip() -> void:
	if Economy.unequip(hero_id, slot):
		close()


## 지금 보여 줄 장비(사본): bag = 필터·정렬, pick = 그 부위·무기 종류만(등급 → 레벨 순).
func shown_items() -> Array:
	var out := Economy.items()
	if mode == "pick":
		var kind := GameData.weapon_of(str(GameData.hero(hero_id).get("model", "")))
		out = out.filter(func(it): return it.slot == slot and (slot != "weapon" or it.weapon_kind == kind))
	else:
		out = out.filter(func(it): return (slot_filter == "" or it.slot == slot_filter) and (grade_filter == "" or it.grade == grade_filter))
	var rank := func(it): return GameData.EQUIP_GRADES.find(it.grade)
	match (sort_mode if mode == "bag" else "grade"):
		"level": out.sort_custom(func(a, b): return [-a.level, -rank.call(a), -a.id] < [-b.level, -rank.call(b), -b.id])
		"new": out.sort_custom(func(a, b): return a.id > b.id)
		_: out.sort_custom(func(a, b): return [-rank.call(a), -a.level, -a.id] < [-rank.call(b), -b.level, -b.id])
	return out


func _refresh() -> void:
	if not visible:
		return
	var pick := mode == "pick"
	for id in selected.keys():  # 팔렸거나 장착된 것은 고름에서 뺀다
		if Economy.item(id).is_empty() or Economy.item_owner(id) != "":
			selected.erase(id)
	_pick_row.visible = pick
	_filter_row.visible = not pick
	_sell_row.visible = not pick
	if pick:
		var cur: Dictionary = Economy.hero_equipment(hero_id).get(slot, {})
		title_label.text = "%s · %s" % [GameData.hero(hero_id).get("name", ""), ITEM_NAMES.get(slot, slot)]
		current_label.text = "지금: " + (item_name(cur) + "  " + stat_text(cur) if not cur.is_empty() else "없음")
		unequip_button.disabled = cur.is_empty() or Economy.equip_block(hero_id, slot, int(cur.get("id", 0))) == "waiting"
	else:
		title_label.text = "보관함 %d / %d" % [Economy.bag.size(), int(GameData.config_num("equip_bag_cap"))]
		slot_button.text = "부위: " + (ITEM_NAMES[slot_filter] if slot_filter != "" else "전체")
		grade_button.text = "등급: " + (grade_filter if grade_filter != "" else "전체")
		sort_button.text = "정렬: " + SORT_NAMES[sort_mode]
		var g := 0
		for id in selected:
			g += GameData.item_sell_value(Economy.item(id))
		sum_label.text = "%d개 선택 · +%s 골드" % [selected.size(), UiKit.commas(g)]
		sell_button.disabled = Economy.sell_block(selected.keys()) != ""
	_rebuild(shown_items())


func _rebuild(items: Array) -> void:
	for r in rows.values():
		_list.remove_child(r.box)
		r.box.queue_free()
	rows.clear()
	empty_label.visible = items.is_empty()
	for it in items:
		var id: int = it.id
		var owner := Economy.item_owner(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var tile = ItemTileScript.new()
		tile.custom_minimum_size = Vector2(TILE_PX, TILE_PX)
		tile.set_item(item_kind(it), it.grade)
		row.add_child(tile)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		info.add_theme_constant_override("separation", 0)
		var nm := _label(item_name(it), 26, Art.ITEM_GRADE_COLORS[it.grade].darkened(0.35), HORIZONTAL_ALIGNMENT_LEFT)
		info.add_child(nm)
		info.add_child(_label(stat_text(it), 20, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
		if owner != "":
			info.add_child(_label("장착: " + str(GameData.hero(owner).get("name", owner)), 18, OWNER_COLOR, HORIZONTAL_ALIGNMENT_LEFT))
		row.add_child(info)
		var r := {"box": row}
		if mode == "pick":
			var mine := owner == hero_id
			var b := _button("장착 중" if mine else "장착", UiKit.STEEL if mine else HudScript.ACCENT, 24)
			b.custom_minimum_size = Vector2(130, 56)
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			b.disabled = mine or Economy.equip_block(hero_id, slot, id) != ""
			b.pressed.connect(equip.bind(id))
			row.add_child(b)
			r.equip = b
		else:
			var c := UiKit.checkbox("")
			c.custom_minimum_size = Vector2(64, 64)
			c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			c.set_pressed_no_signal(selected.has(id))
			c.disabled = owner != ""
			c.toggled.connect(func(_on): toggle(id))
			row.add_child(c)
			r.check = c
		_list.add_child(row)
		rows[id] = r


# --- 장비 글자(던전 결과·영웅 상세도 쓴다) ---

## 아이콘 kind: 무기는 종류(sword…), 방어구는 부위.
static func item_kind(it: Dictionary) -> String:
	return str(it.weapon_kind) if it.get("slot") == "weapon" else str(it.get("slot", ""))


## "SR 모자 Lv 3"
static func item_name(it: Dictionary) -> String:
	return "%s %s Lv %d" % [it.grade, ITEM_NAMES.get(item_kind(it), "?"), int(it.level)]


## "HP +120" · "공격 +35" · 신발은 "HP +40 · 이동 +3%"
static func stat_text(it: Dictionary) -> String:
	var s := GameData.item_stats(it)
	var parts := []
	if s.hp > 0:
		parts.append("HP +%s" % UiKit.commas(s.hp))
	if s.atk > 0:
		parts.append("공격 +%s" % UiKit.commas(s.atk))
	if s.speed_pct > 0.0:
		parts.append("이동 +%d%%" % roundi(s.speed_pct))
	return " · ".join(parts)

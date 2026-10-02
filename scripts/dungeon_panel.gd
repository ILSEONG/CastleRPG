extends "res://scripts/ui_window.gd"
## [던전] 탭 시트(개정 18 §8). 카드 둘(종류마다 같은 모양):
## - 골드 던전: 평야 그림 띠, 열쇠 n / 10, "다음 지급 hh:mm:ss · 최고 n단계", 그 단계 보상 골드, ◀ n단계 ▶, [도전]
## - 장비 던전: 불타는 성 띠, 열쇠 n / 3, 그 밑 "열쇠가 없으면 골드로 도전 (동전) 현재 골드 / 추가 도전 비용"(모자라면 현재 골드가 빨강),
##   그 단계 등급 확률 요약, ◀ n단계 ▶, [도전]
## 그림 띠: 던전 3D 장면 스냅샷(dungeon_snaps + scene_snap — 시트를 처음 열 때 한 장씩 렌더, 캐시)을 깎은 모서리 틀에 넣는다(움직이지 않는다).
## 스냅샷이 오기 전·헤드리스는 평면 그림(_draw_flat_band).
## 단계는 1 ~ 최고 + 1(처음엔 최고 + 1). [도전]이 안 되면(Economy.dungeon_block — 기본 편성으로) 비활성 + 빨간 이유.
## 아래 [보관함 n / 상한] → bag_panel.open_bag.
## [도전] → 출전 편성(같은 시트): 슬롯 6(골드)·4(장비) + 보유 영웅 피규어 격자(전투력 순, 출전 중은 호박색 테두리). 영웅 카드 탭 = 넣기·빼기,
## 슬롯 탭 = 빼기. [자동 편성](Economy.default_party), [출전](편성을 Fever.dungeon_party에 저장 → Economy.start_dungeon), [뒤로].
## 처음 편성 = 저장된 편성(보유·인원이 맞으면), 아니면 기본 편성. 도전이 시작되면(dungeon_started) 카드 화면으로 돌아간다 — 장면은 main이 바꾼다.

const GameData := preload("res://scripts/game_data.gd")
const Skills := preload("res://scripts/skills.gd")
const HeroCardScript := preload("res://scripts/hero_card.gd")
const IconsScript := preload("res://scripts/icons.gd")
const SceneSnap := preload("res://scripts/scene_snap.gd")
const DungeonSnaps := preload("res://scripts/dungeon_snaps.gd")

const TYPES := ["gold", "equip"]
const NAMES := {"gold": "골드 던전", "equip": "장비 던전"}
const BAND_H := 180.0  # 720 화면 띠 628×180 = DungeonSnaps.SIZE의 반(다른 비율이면 스냅샷을 잘라 채운다)
const BAND_CHAMFER := 12.0
const SNAP_KEY := "dungeon_band:%s"
const SLOT_SIZE := Vector2(98, 124)
const CARD_SIZE := Vector2(150, 184)
const GRID_COLUMNS := 4
const RED := Color(0.78, 0.22, 0.18)
const KEY_GOLD := Color(0.95, 0.72, 0.2)

var bag  # 보관함 창(bag_panel). main이 넣는다
var cards := {}  # 종류 → {keys, info, reward, level, prev, next, go, reason}(장비는 + gold, cost)
var bands := {}  # 종류 → 그림 띠 Control
var levels := {}  # 종류 → 고른 단계
var bag_button: Button
var form_type := ""  # 편성 중인 던전(카드 화면이면 "")
var party: Array = []  # 편성 중인 영웅 id(순서 = 슬롯)
var slot_cards: Array = []
var hero_cards := {}  # 영웅 id → 격자 카드(전투력 순)
var form_title: Label
var form_reason: Label
var back_button: Button
var auto_button: Button
var go_button: Button

var _list_view: VBoxContainer
var _form_view: VBoxContainer
var _slot_grid: GridContainer
var _hero_grid: GridContainer
var _tick := 0.0


func _ready() -> void:
	_build_window(0, 10)
	dialog.get_parent().color = Color(0, 0, 0, 0)  # 시트가 화면을 채운다
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_list()
	_build_form()
	_fit_sheet()
	Economy.dungeons_changed.connect(_refresh)
	Economy.changed.connect(_refresh)
	Economy.items_changed.connect(_refresh)
	Economy.roster_changed.connect(_refresh)
	Economy.dungeon_started.connect(_on_dungeon_started)


func _build_list() -> void:
	_list_view = VBoxContainer.new()
	_list_view.add_theme_constant_override("separation", 12)
	_list_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_list_view)
	_list_view.add_child(_title("던전"))
	for t in TYPES:
		_list_view.add_child(_build_card(t))
	bag_button = _button("", UiKit.STEEL, 26)
	bag_button.pressed.connect(func(): bag.open_bag())
	_list_view.add_child(bag_button)


func _build_card(t: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM, 14.0, 14))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var band := Control.new()
	band.custom_minimum_size = Vector2(0, BAND_H)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # 2배 스냅샷을 줄여 그린다
	band.draw.connect(_draw_band.bind(band, t))
	box.add_child(band)
	bands[t] = band
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var nm := _label(NAMES[t], 30, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	var key := Control.new()
	key.custom_minimum_size = Vector2(34, 34)
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.draw.connect(draw_key.bind(key))
	head.add_child(key)
	var keys := _label("", 28)
	head.add_child(keys)
	var money := {}
	if t == "equip":  # 열쇠 밑: 골드 추가 도전 — (동전) 현재 골드 / 비용
		var row_g := HBoxContainer.new()
		row_g.add_theme_constant_override("separation", 8)
		box.add_child(row_g)
		var note := _label("열쇠가 없으면 골드로 도전", 20, HudScript.INK.lightened(0.3), HORIZONTAL_ALIGNMENT_LEFT)
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row_g.add_child(note)
		var coin = IconsScript.new()
		coin.custom_minimum_size = Vector2(34, 34)
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row_g.add_child(coin)
		money = {"gold": _label("", 28), "cost": _label("", 28)}
		row_g.add_child(money.gold)
		row_g.add_child(money.cost)
	var info := _label("", 20, HudScript.INK.lightened(0.2), HORIZONTAL_ALIGNMENT_LEFT)
	box.add_child(info)
	var reward := _label("", 21, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	box.add_child(reward)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var prev := _button("◀", UiKit.STEEL, 26)
	prev.custom_minimum_size = Vector2(64, 64)
	prev.pressed.connect(step_level.bind(t, -1))
	var level := _label("", 28)
	level.custom_minimum_size = Vector2(120, 0)
	level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var next := _button("▶", UiKit.STEEL, 26)
	next.custom_minimum_size = Vector2(64, 64)
	next.pressed.connect(step_level.bind(t, 1))
	var go := _button("도전")
	go.custom_minimum_size = Vector2(0, 64)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(open_form.bind(t))
	for c in [prev, level, next, go]:
		row.add_child(c)
	var reason := _label("", 20, RED)
	box.add_child(reason)
	cards[t] = {"keys": keys, "info": info, "reward": reward, "level": level, "prev": prev, "next": next, "go": go, "reason": reason}
	cards[t].merge(money)
	return panel


func _build_form() -> void:
	_form_view = VBoxContainer.new()
	_form_view.add_theme_constant_override("separation", 10)
	_form_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_form_view.visible = false
	content.add_child(_form_view)
	form_title = _title("")
	_form_view.add_child(form_title)
	_form_view.add_child(_label("영웅을 눌러 넣고 빼세요", 22, HudScript.INK.lightened(0.3)))
	var slots_center := CenterContainer.new()
	_form_view.add_child(slots_center)
	_slot_grid = GridContainer.new()
	_slot_grid.add_theme_constant_override("h_separation", 6)
	slots_center.add_child(_slot_grid)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_form_view.add_child(scroll)
	var grid_center := CenterContainer.new()
	grid_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_center)
	_hero_grid = GridContainer.new()
	_hero_grid.columns = GRID_COLUMNS
	_hero_grid.add_theme_constant_override("h_separation", 10)
	_hero_grid.add_theme_constant_override("v_separation", 10)
	grid_center.add_child(_hero_grid)
	form_reason = _label("", 22, RED)
	_form_view.add_child(form_reason)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_form_view.add_child(row)
	back_button = _button("뒤로", UiKit.STEEL)
	back_button.pressed.connect(_show_list)
	auto_button = _button("자동 편성", UiKit.STEEL)
	auto_button.pressed.connect(auto_party)
	go_button = _button("출전")
	go_button.pressed.connect(deploy)
	for b in [back_button, auto_button, go_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)


func _on_open() -> void:
	_show_list(false)
	# ponytail: 키가 종류뿐 — 띠의 영웅은 처음 연 때의 편성 앞 셋, 실행 중 편성이 바뀌어도 그대로. 따라가야 하면 키에 id를 넣는다.
	for t in TYPES:  # 처음 열 때 띠 스냅샷 요청(이미 있거나 대기 중이면 아무 일 없음, 헤드리스는 자리표시만)
		SceneSnap.snap(SNAP_KEY % t, DungeonSnaps.SIZE, DungeonSnaps.build.bind(t, Economy.default_party(t)), DungeonSnaps.WARM)
	if not SceneSnap.node().snap_ready.is_connected(_on_snap_ready):
		SceneSnap.node().snap_ready.connect(_on_snap_ready)


## 스냅샷이 오면 그 띠만 한 번 다시 그린다(배경은 움직이지 않는다 — 사용자 요청).
func _on_snap_ready(key: String) -> void:
	for t in bands:
		if key == SNAP_KEY % t:
			bands[t].queue_redraw()


func _process(delta: float) -> void:
	if not visible or _form_view.visible:
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 1.0  # "다음 지급" 초 단위
		_refresh()


func is_showing_form() -> bool:
	return visible and _form_view.visible


func level_of(t: String) -> int:
	var mx: int = Economy.dungeon_state(t).max_level
	return clampi(int(levels.get(t, mx)), 1, mx)


func step_level(t: String, d: int) -> void:
	levels[t] = clampi(level_of(t) + d, 1, Economy.dungeon_state(t).max_level)
	_refresh()


func _show_list(guard := true) -> void:
	form_type = ""
	_form_view.visible = false
	_list_view.visible = true
	_refresh()
	if guard:
		_arm_guard()


func _on_dungeon_started(run: Dictionary) -> void:
	if not run.is_empty() and visible:
		_show_list(false)


## "N 60% · R 30% · SR 9% · SSR 1%"(가중치 0은 뺀다).
static func odds_text(weights: Dictionary) -> String:
	var total := 0.0
	for g in weights:
		total += float(weights[g])
	var parts := []
	for g in GameData.EQUIP_GRADES:
		if float(weights.get(g, 0.0)) > 0.0 and total > 0.0:
			parts.append("%s %s%%" % [g, Skills.num_text(float(weights[g]) * 100.0 / total)])
	return " · ".join(parts)


func _refresh() -> void:
	if not visible:
		return
	if _form_view.visible:
		_refresh_form()
		return
	for t in TYPES:
		var st := Economy.dungeon_state(t)
		var lv := level_of(t)
		levels[t] = lv
		var c: Dictionary = cards[t]
		c.keys.text = "%d / %d" % [st.keys, st.key_cap]
		c.info.text = "다음 지급 %s · 최고 %d단계" % [UiKit.clock(st.reset_in), st.best_level]
		var rw := Economy.dungeon_reward(t, lv)
		if t == "gold":
			c.reward.text = "보상 %s 골드" % UiKit.commas(rw.gold)
		else:
			c.reward.text = "장비 %d개 · %s" % [rw.count, odds_text(rw.weights)]
			c.gold.text = UiKit.commas(Economy.gold)
			c.gold.add_theme_color_override("font_color", RED if Economy.gold < int(st.extra_cost) else HudScript.INK)
			c.cost.text = "/ %s" % UiKit.commas(st.extra_cost)
		c.level.text = "%d단계" % lv
		c.prev.disabled = lv <= 1
		c.next.disabled = lv >= int(st.max_level)
		var why := Economy.dungeon_block(t, lv, Economy.default_party(t))
		c.go.disabled = why != ""
		c.reason.text = Economy.DUNGEON_TEXT.get(why, "") if why != "waiting" else ""
		c.reason.visible = c.reason.text != ""
	bag_button.text = "보관함 %d / %d" % [Economy.bag.size(), int(GameData.config_num("equip_bag_cap"))]


# --- 출전 편성 ---

## [도전]: 그 던전의 편성 화면(저장된 편성이 맞으면 그것, 아니면 기본 편성).
func open_form(t: String) -> void:
	form_type = t
	var saved: Array = Fever.dungeon_party.get(t, [])
	party = saved.duplicate() if _party_ok(t, saved) else Economy.default_party(t)
	_list_view.visible = false
	_form_view.visible = true
	_refresh_form()
	_arm_guard()


func _party_ok(t: String, p: Array) -> bool:
	if p.size() != GameData.party_size(t):
		return false
	for i in p.size():
		if p.find(p[i]) != i or int(Economy.heroes.get(p[i], 0)) < 1 or GameData.hero(p[i]).is_empty():
			return false
	return true


## 보유 영웅 id, 전투력(장비 포함) 높은 순 — 같으면 표 순서.
func owned_by_power() -> Array:
	var ids := Economy.heroes.keys().filter(func(id): return int(Economy.heroes[id]) >= 1 and not GameData.hero(id).is_empty())
	var power := {}
	for id in ids:
		power[id] = GameData.hero_power(GameData.hero(id), Economy.level_of(id), Economy.promotion_of(id), Economy.levels)
	var order: Array = GameData.heroes().map(func(h): return h.id)
	ids.sort_custom(func(a, b): return power[a] > power[b] or (power[a] == power[b] and order.find(a) < order.find(b)))
	return ids


## 영웅 카드 탭: 출전 중이면 빼고, 아니면 빈 슬롯에 넣는다(가득 차면 그대로).
func tap_hero(id: String) -> void:
	if party.has(id):
		party.erase(id)
	elif party.size() < GameData.party_size(form_type):
		party.append(id)
	_refresh_form()


func tap_slot(i: int) -> void:
	if i < party.size():
		party.remove_at(i)
	_refresh_form()


func auto_party() -> void:
	party = Economy.default_party(form_type)
	_refresh_form()


## [출전]: 편성을 저장(user://local.json)하고 도전 시작 — 장면 전환은 main(dungeon_started).
func deploy() -> void:
	Fever.dungeon_party[form_type] = party.duplicate()
	Fever.save()
	Economy.start_dungeon(form_type, level_of(form_type), party.duplicate())
	_refresh_form()


func _refresh_form() -> void:
	if form_type == "":
		return
	var size := GameData.party_size(form_type)
	party = party.filter(func(id): return int(Economy.heroes.get(id, 0)) >= 1)
	if slot_cards.size() != size:
		for c in slot_cards:
			_slot_grid.remove_child(c)
			c.queue_free()
		slot_cards.clear()
		_slot_grid.columns = size
		for i in size:
			var card = HeroCardScript.new()
			card.custom_minimum_size = SLOT_SIZE
			card.corner = str(i + 1)
			card.tapped.connect(func(_c): tap_slot(i))
			_slot_grid.add_child(card)
			slot_cards.append(card)
	var ids := owned_by_power()
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
	for i in slot_cards.size():
		var c = slot_cards[i]
		c.hero_id = party[i] if i < party.size() else ""
		c.stars = Economy.promotion_of(party[i]) if i < party.size() else 0
		c.queue_redraw()
	for id in hero_cards:
		var c = hero_cards[id]
		c.stars = Economy.promotion_of(id)
		c.level = Economy.level_of(id)
		c.power = GameData.hero_power(GameData.hero(id), c.level, c.stars, Economy.levels)
		c.highlight = party.has(id)
		c.queue_redraw()
	var lv := level_of(form_type)
	form_title.text = "%s %d단계 출전" % [NAMES[form_type], lv]
	var why := Economy.dungeon_block(form_type, lv, party)
	go_button.disabled = why != ""
	form_reason.text = "출전 %d / %d명" % [party.size(), size] if why in ["", "bad_party", "waiting"] else Economy.DUNGEON_TEXT.get(why, "")
	form_reason.add_theme_color_override("font_color", HudScript.INK if why == "" else RED)
	auto_button.disabled = party == Economy.default_party(form_type)


# --- 그림 ---

## 열쇠: 고리 + 자루 + 이 둘(금색, 진한 테두리).
static func draw_key(c: Control) -> void:
	var s := minf(c.size.x, c.size.y)
	var o := c.size / 2.0
	var ring := o + Vector2(-s * 0.22, 0)
	c.draw_circle(ring, s * 0.24, UiKit.INK)
	c.draw_circle(ring, s * 0.19, KEY_GOLD)
	c.draw_circle(ring, s * 0.08, UiKit.INK)
	c.draw_rect(Rect2(o + Vector2(-s * 0.02, -s * 0.07), Vector2(s * 0.5, s * 0.14)), KEY_GOLD)
	for x in [0.3, 0.42]:
		c.draw_rect(Rect2(o + Vector2(s * x - s * 0.05, s * 0.05), Vector2(s * 0.08, s * 0.14)), KEY_GOLD)


## 카드 그림 띠: 깎은 모서리(8각) 틀 안에 스냅샷(가운데를 잘라 고정) — 없으면 평면 그림 + 모서리를 카드 색으로 덮는다.
## 위쪽 옅은 그림자 그러데이션, 안쪽 흰 빛 선, 진한 외곽선.
func _draw_band(c: Control, t: String) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	var oct := UiKit.LowpolyBox.octagon(r, BAND_CHAMFER)
	var tex := SceneSnap.cached(SNAP_KEY % t)
	if tex != null:
		var k := (c.size.x / c.size.y) / (float(tex.get_width()) / tex.get_height())  # 띠 비율 ÷ 그림 비율 — 늘이지 않고 잘라 채운다
		var uv := Vector2(1.0, 1.0 / k) if k > 1.0 else Vector2(k, 1.0)
		var src := Rect2((Vector2.ONE - uv) * 0.5, uv)  # 0..1 UV, 가운데 고정
		var uvs := PackedVector2Array()
		for p in oct:
			uvs.append(src.position + p / c.size * src.size)
		c.draw_colored_polygon(oct, Color.WHITE, uvs, tex)
	else:
		_draw_flat_band(c, t)
		for i in [0, 2, 4, 6]:  # 모서리 삼각형을 카드 바탕으로 덮는다
			var corner := Vector2(r.end.x if i in [2, 4] else 0.0, r.end.y if i in [4, 6] else 0.0)
			c.draw_colored_polygon(PackedVector2Array([corner, oct[i], oct[(i + 7) % 8]]), UiKit.CREAM)
	var g := c.size.y * 0.45
	var shade := Color(0, 0, 0, 0.3)
	var mid := Color(shade, shade.a * (1.0 - BAND_CHAMFER / g))
	c.draw_polygon(PackedVector2Array([oct[0], oct[1], oct[2], Vector2(c.size.x, g), Vector2(0, g), oct[7]]),
		PackedColorArray([shade, shade, mid, Color(shade, 0.0), Color(shade, 0.0), mid]))
	var inner := UiKit.LowpolyBox.octagon(r.grow(-2.5), BAND_CHAMFER - 1.0)
	inner.append(inner[0])
	c.draw_polyline(inner, Color(1, 1, 1, 0.35), 1.5, true)
	oct.append(oct[0])
	c.draw_polyline(oct, UiKit.OUTLINE, 2.5, true)


## 평면 그림(스냅샷 전 자리표시): 골드 = 평야(하늘·먼 산·풀 언덕·나무), 장비 = 불타는 성(붉은 하늘·성 실루엣·불꽃).
func _draw_flat_band(c: Control, t: String) -> void:
	var w := c.size.x
	var h := c.size.y
	var r := Rect2(Vector2.ZERO, c.size)
	if t == "gold":
		c.draw_rect(r, Color(0.66, 0.83, 0.96))
		c.draw_rect(Rect2(0, h * 0.45, w, h * 0.55), Color(0.78, 0.89, 0.97))
		for i in 6:  # 먼 산
			var x := w * (i / 5.0)
			c.draw_colored_polygon(PackedVector2Array([Vector2(maxf(x - w * 0.14, 0.0), h * 0.62), Vector2(x, h * (0.2 + 0.08 * (i % 2))), Vector2(minf(x + w * 0.14, w), h * 0.62)]),  # 양끝 산은 띠 안에서 자른다
				Color(0.56, 0.64, 0.74) if i % 2 == 0 else Color(0.62, 0.70, 0.80))
		c.draw_colored_polygon(PackedVector2Array([Vector2(0, h * 0.62), Vector2(w * 0.3, h * 0.5), Vector2(w * 0.65, h * 0.6), Vector2(w, h * 0.48),
			Vector2(w, h), Vector2(0, h)]), Color(0.47, 0.62, 0.33))
		c.draw_colored_polygon(PackedVector2Array([Vector2(0, h * 0.8), Vector2(w * 0.4, h * 0.7), Vector2(w, h * 0.82), Vector2(w, h), Vector2(0, h)]),
			Color(0.42, 0.56, 0.29))
		for x in [0.12, 0.2, 0.78, 0.86, 0.93]:  # 나무
			var b := Vector2(w * x, h * 0.66)
			c.draw_colored_polygon(PackedVector2Array([b + Vector2(-12, 4), b + Vector2(0, -26), b + Vector2(12, 4)]), Color(0.24, 0.44, 0.26))
	else:
		c.draw_rect(r, Color(0.16, 0.05, 0.04))
		c.draw_rect(Rect2(0, h * 0.5, w, h * 0.5), Color(0.36, 0.1, 0.05))
		var wall := Color(0.13, 0.1, 0.1)
		c.draw_rect(Rect2(w * 0.2, h * 0.45, w * 0.6, h * 0.55), wall)
		for x in [0.18, 0.46, 0.74]:  # 탑 + 흉벽
			c.draw_rect(Rect2(w * x, h * 0.2, w * 0.08, h * 0.8), wall)
			for k in 3:
				c.draw_rect(Rect2(w * x + k * w * 0.03, h * 0.14, w * 0.02, h * 0.07), wall)
			c.draw_rect(Rect2(w * x + w * 0.03, h * 0.36, w * 0.02, h * 0.1), Color(1.0, 0.55, 0.15))  # 불 켜진 창
		for x in [0.08, 0.32, 0.6, 0.9]:  # 불꽃
			var b := Vector2(w * x, h)
			c.draw_colored_polygon(PackedVector2Array([b + Vector2(-22, 0), b + Vector2(-6, -h * 0.55), b + Vector2(4, -h * 0.3), b + Vector2(14, -h * 0.7),
				b + Vector2(24, 0)]), Color(0.95, 0.42, 0.1))
			c.draw_colored_polygon(PackedVector2Array([b + Vector2(-10, 0), b + Vector2(2, -h * 0.35), b + Vector2(12, 0)]), Color(1.0, 0.8, 0.3))

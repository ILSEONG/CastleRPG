extends "res://scripts/ui_window.gd"
## 연구 창(개정 24 §5): 연구소 테크트리. 전체 높이 시트(던전 시트와 같은 ui_kit 스타일) — 건물 창 연구소 [연구]·연구소 말풍선 탭이 연다.
## 위: 제목 "연구소 Lv N" + "연구 속도 +X%", 진행 중 연구 막대(아이콘 · "벌목술 Lv 3" · 진행률 · 남은 시간, 옆 [💎 N 즉시 완료] [취소]) —
##   없으면 "진행 중인 연구 없음 — 연구할 기술을 고르세요".
## 분야 탭 [경제] [군사] [영웅] → 트리(세로 스크롤): 단(tier)마다 한 줄, 줄 왼쪽에 단 표시(연구소 Lv이 모자라면 자물쇠 + "연구소 Lv 6").
##   노드 카드 = 아이콘 · 이름 · "Lv 3/10" · 작은 레벨 막대 · 상태 글자. 상태: 잠김(흐림 + 자물쇠) / 연구 가능 / 연구 중(빛나는 테두리 + 남은 시간) /
##   최대(금 테두리 + MAX). 선행 연결선: 조건을 채우면 금색, 아니면 회색(카드 뒤에 그린다).
## 카드 탭 → 노드 상세(아래에서 뜨는 창): 큰 아이콘·이름·설명, 효과 "현재 +10% → 다음 +15%", 조건 ✓/✗, 비용(보유/필요, 모자라면 빨강), 시간,
##   [연구](막히면 비활성 + 이유 한 줄). 진행 중인 노드면 진행 막대 + [💎 즉시 완료] [취소].
## 아이콘(사용자 규칙: 바로 알아보게): 보병·궁병·기병 훈련은 실제 병사 3D 초상(SoldierPanel.unit_icon), 나머지는 Icons 로우폴리 그림(ICONS).
## 규칙·상태는 전부 Economy 연구 API다. Economy.changed·research_changed마다, 열려 있는 동안 매초 다시 그린다.

const GameData := preload("res://scripts/game_data.gd")
const EconomyScript := preload("res://scripts/economy.gd")
const IconsScript := preload("res://scripts/icons.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const SoldierPanel := preload("res://scripts/soldier_panel.gd")
const Skills := preload("res://scripts/skills.gd")

const BRANCH_NAMES := {"economy": "경제", "military": "군사", "hero": "영웅"}
const BRANCH_TINT := {"economy": Color(0.98, 0.88, 0.62), "military": Color(0.95, 0.76, 0.72), "hero": Color(0.76, 0.84, 0.98)}  # 아이콘 바탕
## 노드 → 아이콘(Icons kind). 없는 노드(서버가 더한 노드)는 효과로(EFFECT_ICONS), 그것도 없으면 플라스크.
const ICONS := {"wood_tech": "wood", "stone_tech": "stone", "food_tech": "food", "construct": "hammer", "commerce": "scales", "plunder": "coin_bag",
	"method": "flask", "abundance": "res_pile", "wall_fort": "wall", "gate_fort": "gate", "drill_manual": "book", "logistics": "cart", "barracks_ext": "tent",
	"elite": "elite", "hero_weapon": "sword", "hero_armor": "top", "arcana": "orb", "legend_weapon": "glow_sword", "legend_armor": "heart_shield"}
const EFFECT_ICONS := {"wood_pct": "wood", "stone_pct": "stone", "food_pct": "food", "res_pct": "res_pile", "build_speed_pct": "hammer",
	"research_speed_pct": "flask", "sell_pct": "scales", "kill_gold_pct": "coin_bag", "castle_hp_pct": "wall", "gate_hp_pct": "gate",
	"train_speed_pct": "book", "train_cost_pct": "cart", "pop_add": "tent", "soldier_pct": "elite", "hero_atk_pct": "sword", "hero_hp_pct": "top",
	"skill_pct": "orb"}
const SOLDIER_EFFECTS := {"inf_pct": "infantry", "arc_pct": "archer", "cav_pct": "cavalry"}  # 이 효과의 노드는 실제 병사 초상
const EFFECT_NAMES := {"wood_pct": "목재 생산", "stone_pct": "석재 생산", "food_pct": "식량 생산", "res_pct": "모든 자원 생산",
	"build_speed_pct": "건설 속도", "research_speed_pct": "연구 속도", "sell_pct": "판매 금액", "kill_gold_pct": "처치 골드",
	"inf_pct": "보병 공격·체력", "arc_pct": "궁병 공격·체력", "cav_pct": "기병 공격·체력", "soldier_pct": "모든 병사 공격·체력",
	"castle_hp_pct": "성 최대 체력", "gate_hp_pct": "성문 최대 체력", "train_speed_pct": "훈련 속도", "train_cost_pct": "훈련 비용",
	"pop_add": "인구", "hero_atk_pct": "영웅 공격력", "hero_hp_pct": "영웅 체력", "skill_pct": "영웅 스킬 피해"}
const EFFECT_DESC := {"wood_pct": "벌목장의 목재 생산량이 늘어납니다.", "stone_pct": "채석장의 석재 생산량이 늘어납니다.",
	"food_pct": "농장의 식량 생산량이 늘어납니다.", "res_pct": "모든 자원 생산량이 늘어납니다.", "build_speed_pct": "건물 건설 시간이 줄어듭니다.",
	"research_speed_pct": "연구 시간이 줄어듭니다.", "sell_pct": "상인에게 자원을 더 비싸게 팝니다.", "kill_gold_pct": "몬스터 처치 골드가 늘어납니다.",
	"inf_pct": "보병의 공격력과 체력이 오릅니다.", "arc_pct": "궁병의 공격력과 체력이 오릅니다.", "cav_pct": "기병의 공격력과 체력이 오릅니다.",
	"soldier_pct": "모든 병사의 공격력과 체력이 오릅니다.", "castle_hp_pct": "성의 최대 체력이 오릅니다.", "gate_hp_pct": "성문의 최대 체력이 오릅니다.",
	"train_speed_pct": "병사 훈련 시간이 줄어듭니다.", "train_cost_pct": "병사 훈련 비용이 줄어듭니다.", "pop_add": "인구(병사 배치 상한)가 늘어납니다.",
	"hero_atk_pct": "모든 영웅의 공격력이 오릅니다.", "hero_hp_pct": "모든 영웅의 체력이 오릅니다.", "skill_pct": "영웅 스킬의 추가 피해가 늘어납니다."}
const IDLE_TEXT := "진행 중인 연구 없음 — 연구할 기술을 고르세요"
const AVAILABLE_TEXT := "연구 가능"
const CARD_SIZE := Vector2(158, 178)
const CARD_ICON_PX := 64.0
const DETAIL_ICON_PX := 112.0
const CUR_ICON_PX := 64.0
const TIER_W := 84.0
const LINK_W := 4.0
const LINK_DROP := 14.0  # 연결선 가로 마디: 대상 카드 윗변보다 이만큼 위
const LINK_GOLD := Color(0.96, 0.74, 0.20)
const LINK_GRAY := Color(0.62, 0.64, 0.68)
const MAX_GOLD := Color(0.95, 0.72, 0.16)
const GREEN := Color(0.13, 0.55, 0.24)
const RED := Color(0.78, 0.22, 0.18)

var branch := "economy"
var branch_buttons := {}  # 분야 → 탭 버튼
var cards := {}  # 노드 id → {button, face, box, name, lv, bar, state, lock}(지금 분야만)
var tier_marks := {}  # 단 → {lock(Control), need(Label)}(지금 분야만)
var title_label: Label
var speed_label: Label
var cur_panel: PanelContainer
var cur_row: HBoxContainer
var cur_name: Label
var cur_bar: ProgressBar
var cur_left: Label
var dia_button: Button
var cancel_button: Button
var idle_label: Label
var tree: VBoxContainer  # 단 줄들(연결선은 여기 뒤에 그린다)
var close_button: Button
# 노드 상세(아래에서 뜨는 창)
var detail: Control
var detail_id := ""
var detail_name: Label
var detail_desc: Label
var detail_effect: Label
var detail_reqs: VBoxContainer
var detail_cost := {}  # 자원 id → Label("보유/필요")
var detail_time: Label
var detail_reason: Label
var start_button: Button
var detail_run: VBoxContainer
var detail_bar: ProgressBar
var detail_left: Label
var detail_dia: Button
var detail_cancel: Button

var _cur_icon_id := ""  # 진행 중 막대 아이콘을 만든 노드
var _cur_icon_box: Control
var _detail_icon_box: Control
var _detail_icon_id := ""
var _cost_grid: GridContainer
var _scroll: ScrollContainer
var _last_sec := -1


func _ready() -> void:
	_build_window(0, 10)
	dialog.get_parent().color = Color(0, 0, 0, 0)  # 시트가 화면을 채운다
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	title_label = _title("")
	content.add_child(title_label)
	speed_label = _label("", 24, GREEN)
	content.add_child(speed_label)
	_build_current()
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	content.add_child(tabs)
	for b in GameData.RESEARCH_BRANCHES:
		var t := _button(BRANCH_NAMES.get(b, b), UiKit.STEEL, 26)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.custom_minimum_size = Vector2(0, 60)
		t.pressed.connect(set_branch.bind(b))
		tabs.add_child(t)
		branch_buttons[b] = t
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(_scroll)
	tree = VBoxContainer.new()
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.add_theme_constant_override("separation", 22)
	tree.draw.connect(_draw_links)
	_scroll.add_child(tree)
	close_button = _button("닫기", UiKit.STEEL)
	close_button.pressed.connect(close)
	content.add_child(close_button)
	_fit_sheet()
	_build_detail()
	Economy.changed.connect(func(): if visible: _refresh())
	Economy.research_changed.connect(func(): if visible: _refresh())
	set_branch(branch)


## 진행 중 연구 막대(위): 아이콘 · 이름 · 진행 막대 · 남은 시간, 오른쪽 [다이아 즉시 완료] [취소]. 없으면 안내 한 줄.
func _build_current() -> void:
	cur_panel = PanelContainer.new()
	cur_panel.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM, 14.0, 12))
	content.add_child(cur_panel)
	var both := VBoxContainer.new()
	cur_panel.add_child(both)
	cur_row = HBoxContainer.new()
	cur_row.add_theme_constant_override("separation", 10)
	both.add_child(cur_row)
	_cur_icon_box = CenterContainer.new()
	_cur_icon_box.custom_minimum_size = Vector2(CUR_ICON_PX, CUR_ICON_PX)
	cur_row.add_child(_cur_icon_box)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 4)
	cur_row.add_child(mid)
	cur_name = _label("", 26, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	mid.add_child(cur_name)
	cur_bar = _bar(18)
	mid.add_child(cur_bar)
	cur_left = _label("", 20, HudScript.INK.lightened(0.25), HORIZONTAL_ALIGNMENT_LEFT)
	mid.add_child(cur_left)
	var btns := VBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	cur_row.add_child(btns)
	dia_button = _dia_button(22)
	dia_button.custom_minimum_size = Vector2(196, 52)
	dia_button.pressed.connect(func(): Economy.finish_research_now())
	btns.add_child(dia_button)
	cancel_button = _button("취소", UiKit.STEEL, 22)
	cancel_button.custom_minimum_size = Vector2(196, 44)
	cancel_button.pressed.connect(func(): Economy.cancel_research())
	btns.add_child(cancel_button)
	idle_label = _label(IDLE_TEXT, 22, HudScript.INK.lightened(0.25))
	idle_label.custom_minimum_size = Vector2(0, 48)
	idle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	both.add_child(idle_label)


## 노드 상세: 어두운 배경(탭하면 닫힘) + 아래에 붙은 패널. 창(층 2) 안에서 시트 위에 그린다.
func _build_detail() -> void:
	detail = ColorRect.new()
	detail.color = Color(0, 0, 0, 0.45)
	detail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	detail.mouse_filter = Control.MOUSE_FILTER_STOP
	detail.visible = false
	detail.gui_input.connect(func(e: InputEvent):
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			close_detail())
	add_child(detail)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = SHEET_SIDE
	panel.offset_right = -SHEET_SIDE
	panel.offset_bottom = -(HudScript.TAB_BAR_H + 8)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM_DIALOG, 18.0, 20))
	detail.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	box.add_child(head)
	_detail_icon_box = CenterContainer.new()
	_detail_icon_box.custom_minimum_size = Vector2(DETAIL_ICON_PX, DETAIL_ICON_PX)
	head.add_child(_detail_icon_box)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(info)
	detail_name = _title("")
	detail_name.add_theme_font_size_override("font_size", 34)
	detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.add_child(detail_name)
	detail_desc = _label("", 22, HudScript.INK.lightened(0.25), HORIZONTAL_ALIGNMENT_LEFT)
	detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(detail_desc)
	detail_effect = _label("", 26, GREEN)
	box.add_child(detail_effect)
	detail_reqs = VBoxContainer.new()
	box.add_child(detail_reqs)
	_cost_grid = GridContainer.new()
	_cost_grid.columns = 4
	_cost_grid.add_theme_constant_override("h_separation", 8)
	var cost_center := CenterContainer.new()
	cost_center.add_child(_cost_grid)
	box.add_child(cost_center)
	for r in GameData.RESEARCH_RES:
		var icon = IconsScript.new()
		icon.kind = r
		icon.custom_minimum_size = Vector2(34, 34)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_cost_grid.add_child(icon)
		var l := _label("", 24, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
		l.custom_minimum_size = Vector2(196, 0)
		_cost_grid.add_child(l)
		detail_cost[r] = l
	detail_time = _label("", 24)
	box.add_child(detail_time)
	detail_reason = _label("", 22, RED)
	box.add_child(detail_reason)
	start_button = _button("연구", GREEN)
	start_button.custom_minimum_size = Vector2(0, 64)
	start_button.pressed.connect(func(): Economy.start_research(detail_id))
	box.add_child(start_button)
	detail_run = VBoxContainer.new()
	detail_run.add_theme_constant_override("separation", 6)
	box.add_child(detail_run)
	detail_bar = _bar(22)
	detail_run.add_child(detail_bar)
	detail_left = _label("", 22)
	detail_run.add_child(detail_left)
	var run_btns := HBoxContainer.new()
	run_btns.add_theme_constant_override("separation", 10)
	detail_run.add_child(run_btns)
	detail_dia = _dia_button(24)
	detail_dia.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_dia.pressed.connect(func(): Economy.finish_research_now())
	run_btns.add_child(detail_dia)
	detail_cancel = _button("취소", UiKit.STEEL, 24)
	detail_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_cancel.pressed.connect(func(): Economy.cancel_research())
	run_btns.add_child(detail_cancel)
	var close_detail_button := _button("닫기", UiKit.STEEL)
	close_detail_button.pressed.connect(close_detail)
	box.add_child(close_detail_button)


## 다이아 버튼: 왼쪽 보석 아이콘 + "N 즉시 완료"(글자는 보석 자리만큼 오른쪽으로).
func _dia_button(font_size: int) -> Button:
	var b := _button("", UiKit.GRADE_COLORS.SR, font_size)
	var gem = IconsScript.new()
	gem.kind = "diamond"
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gem.anchor_top = 0.5
	gem.anchor_bottom = 0.5
	gem.offset_left = 10
	gem.offset_right = 40
	gem.offset_top = -15
	gem.offset_bottom = 15
	b.add_child(gem)
	return b


func _bar(h: float) -> ProgressBar:
	var p := ProgressBar.new()
	p.custom_minimum_size = Vector2(0, h)
	p.show_percentage = false
	p.max_value = 1.0
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.apply_bar(p, UiKit.AMBER)
	return p


func _on_open() -> void:
	close_detail()
	_refresh()


func close() -> void:
	close_detail()
	super.close()


## 분야 탭: 고른 탭은 호박색, 트리를 그 분야 노드로 다시 만든다.
func set_branch(b: String) -> void:
	branch = b
	for k in branch_buttons:
		UiKit.apply_button(branch_buttons[k], UiKit.AMBER if k == b else UiKit.STEEL, 14.0)
	_rebuild_tree()
	_scroll.scroll_vertical = 0
	_refresh()


## 지금 분야의 노드(파일 순서)를 단 → [노드] 로 나눈다(단 오름차순).
static func tiers_of(b: String) -> Dictionary:
	var out := {}
	for d in GameData.research_defs():
		if d.branch == b:
			var t := int(d.tier)
			if not out.has(t):
				out[t] = []
			out[t].append(d)
	var keys := out.keys()
	keys.sort()
	var sorted := {}
	for k in keys:
		sorted[k] = out[k]
	return sorted


func _rebuild_tree() -> void:
	for c in tree.get_children():
		tree.remove_child(c)
		c.queue_free()
	cards = {}
	tier_marks = {}
	var tiers := tiers_of(branch)
	for t in tiers:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		tree.add_child(row)
		var mark := VBoxContainer.new()
		mark.custom_minimum_size = Vector2(TIER_W, 0)
		mark.alignment = BoxContainer.ALIGNMENT_CENTER
		mark.add_theme_constant_override("separation", 2)
		row.add_child(mark)
		mark.add_child(_label("%d단" % t, 28))
		var lock := Control.new()
		lock.custom_minimum_size = Vector2(TIER_W, 30)
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock.draw.connect(func(): draw_lock(lock, Vector2(TIER_W / 2.0, 15.0), 26.0))
		mark.add_child(lock)
		var need := _label("", 18, RED)
		need.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		need.custom_minimum_size = Vector2(TIER_W, 0)
		mark.add_child(need)
		tier_marks[t] = {"lock": lock, "need": need, "lab": tiers[t].map(func(d): return int(d.lab_req)).min()}
		var line := HBoxContainer.new()
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		line.add_theme_constant_override("separation", 12)
		row.add_child(line)
		for d in tiers[t]:
			line.add_child(_card(d))


## 노드 카드 하나: 바탕·테두리(face, 상태 색) 위에 아이콘·이름·Lv·막대·상태, 맨 위 자물쇠(잠김만). 누르면 상세.
func _card(d: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = CARD_SIZE
	b.focus_mode = Control.FOCUS_NONE
	for k in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	b.pressed.connect(open_detail.bind(d.id))
	var face := Control.new()
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.draw.connect(_draw_card.bind(face, d.id))
	b.add_child(face)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8
	box.offset_right = -8
	box.offset_top = 8
	box.offset_bottom = -6
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	b.add_child(box)
	var icon := node_icon(d.id, CARD_ICON_PX)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var nm := _label(d.name, 21)
	box.add_child(nm)
	var lv := _label("", 18, HudScript.INK.lightened(0.2))
	box.add_child(lv)
	var bar := _bar(10)
	box.add_child(bar)
	var state := _label("", 17)
	box.add_child(state)
	var lock := Control.new()
	lock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.draw.connect(func(): draw_lock(lock, Vector2(lock.size.x - 24.0, 24.0), 28.0))
	b.add_child(lock)
	cards[d.id] = {"button": b, "face": face, "box": box, "name": nm, "lv": lv, "bar": bar, "state": state, "lock": lock}
	return b


## 카드 상태: "running"(연구 중) / "max"(최대) / "locked"(연구소·선행 미충족) / "open"(연구 가능 — 자원·다른 연구는 상세가 말한다).
static func card_state(id: String) -> String:
	var d := GameData.research_def(id)
	if str(Economy.research_current.get("id", "")) == id:
		return "running"
	if Economy.research_level(id) >= int(d.get("max_level", 0)):
		return "max"
	if not GameData.research_unlocked(d, Economy.research_levels, Economy.building_level(GameData.LAB)):
		return "locked"
	return "open"


## 카드 바탕(각진 8각) + 상태 테두리: 연구 가능 = 진한 외곽, 잠김 = 회색, 연구 중 = 호박색이 숨 쉬듯 빛난다, 최대 = 두꺼운 금 테두리.
func _draw_card(face: Control, id: String) -> void:
	var st := card_state(id)
	var r := Rect2(Vector2.ZERO, face.size).grow(-3.0)
	var oct := LowpolyBox.octagon(r, 14.0)
	var fill: Color = {"open": UiKit.CREAM, "locked": Color(0.86, 0.86, 0.87), "running": Color(1.0, 0.97, 0.88), "max": Color(1.0, 0.95, 0.80)}[st]
	face.draw_colored_polygon(oct, fill)
	var ring := oct.duplicate()
	ring.append(oct[0])
	match st:
		"running":
			var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 0.8)
			face.draw_polyline(ring, Color(UiKit.AMBER, 0.25 + 0.35 * k), 10.0, true)
			face.draw_polyline(ring, UiKit.AMBER.lightened(0.15 * k), 4.0, true)
		"max":
			face.draw_polyline(ring, MAX_GOLD, 5.0, true)
		"locked":
			face.draw_polyline(ring, Color(UiKit.OUTLINE, 0.35), 2.0, true)
		_:
			face.draw_polyline(ring, UiKit.OUTLINE, 2.0, true)


## 자물쇠: center 중심 한 변 s — 쇠 고리(반원) + 금 몸통 + 열쇠 구멍.
static func draw_lock(ci: CanvasItem, center: Vector2, s: float) -> void:
	var body := Rect2(center + Vector2(-0.42, -0.05) * s, Vector2(0.84, 0.58) * s)
	var arc := PackedVector2Array()
	for i in 9:
		arc.append(Vector2(center.x, body.position.y) + Vector2.from_angle(PI + PI * i / 8.0) * 0.26 * s)
	ci.draw_polyline(arc, UiKit.OUTLINE, 0.2 * s + 2.0, true)
	ci.draw_polyline(arc, Color(0.66, 0.70, 0.77), 0.2 * s, true)
	var oct := LowpolyBox.octagon(body, 0.1 * s)
	ci.draw_colored_polygon(oct, Color(0.95, 0.74, 0.22))
	oct.append(oct[0])
	ci.draw_polyline(oct, UiKit.OUTLINE, maxf(1.5, s / 16.0), true)
	var hole := body.get_center()
	ci.draw_circle(hole + Vector2(0, -0.06 * s), 0.08 * s, UiKit.OUTLINE)
	ci.draw_rect(Rect2(hole + Vector2(-0.03, -0.04) * s, Vector2(0.06, 0.18) * s), UiKit.OUTLINE)


## 선행 연결선(카드 뒤): 선행 카드 아랫변 가운데 → 대상 카드 윗변 위 LINK_DROP에서 꺾어 → 대상 윗변 가운데. 조건을 채우면 금색, 아니면 회색.
## 다른 분야 선행은 그리지 않는다(상세 조건이 말한다).
func _draw_links() -> void:
	var inv := tree.get_global_transform().affine_inverse()
	for id in cards:
		var d := GameData.research_def(id)
		for rq in GameData.RESEARCH_REQS:
			var p: String = d[rq[0]]
			if p == "" or not cards.has(p):
				continue
			var ar: Rect2 = cards[p].button.get_global_rect()
			var br: Rect2 = cards[id].button.get_global_rect()
			var a: Vector2 = inv * Vector2(ar.get_center().x, ar.end.y - 4.0)
			var b: Vector2 = inv * Vector2(br.get_center().x, br.position.y + 4.0)
			var y := b.y - LINK_DROP - 4.0
			var pts := PackedVector2Array([a, Vector2(a.x, y), Vector2(b.x, y), b])
			var ok := Economy.research_level(p) >= int(d[rq[1]])
			tree.draw_polyline(pts, Color(UiKit.OUTLINE, 0.45), LINK_W + 3.0, true)
			tree.draw_polyline(pts, LINK_GOLD if ok else LINK_GRAY, LINK_W, true)


func _process(_delta: float) -> void:
	if not visible:
		return
	tree.queue_redraw()  # 연결선(카드 자리가 레이아웃 뒤에 정해진다) — 선 몇 개라 가볍다
	var cur := str(Economy.research_current.get("id", ""))
	if cards.has(cur):
		cards[cur].face.queue_redraw()  # 연구 중 테두리가 빛난다
	var sec := floori(Economy.time_now())
	if sec != _last_sec:
		_refresh()


func _refresh() -> void:
	if not visible:
		return
	var now := Economy.time_now()
	_last_sec = floori(now)
	var lab := Economy.building_level(GameData.LAB)
	title_label.text = "연구소 Lv %d" % lab
	speed_label.text = "연구 속도 +%s%%" % Skills.num_text(Economy.research_speed() * 100.0)
	_refresh_current(now)
	for t in tier_marks:
		var locked: bool = lab < int(tier_marks[t].lab)
		tier_marks[t].lock.visible = locked
		tier_marks[t].need.text = "연구소 Lv %d 필요" % int(tier_marks[t].lab) if locked else ""
		tier_marks[t].need.visible = locked
	for id in cards:
		_refresh_card(id, now)
	if detail.visible:
		_refresh_detail(now)


func _refresh_current(now: float) -> void:
	var cur := str(Economy.research_current.get("id", ""))
	cur_row.visible = cur != ""
	idle_label.visible = cur == ""
	if cur == "":
		return
	if cur != _cur_icon_id:
		_cur_icon_id = cur
		_swap_icon(_cur_icon_box, cur, CUR_ICON_PX)
	cur_name.text = "%s Lv %d" % [GameData.research_def(cur).get("name", cur), Economy.research_level(cur) + 1]
	cur_bar.value = Economy.research_progress(now)
	cur_left.text = "남은 시간 " + UiKit.duration(Economy.research_left(now))
	var dia := Economy.research_dia_cost(now)
	dia_button.text = "      %d 즉시 완료" % dia
	dia_button.disabled = Economy.diamonds < dia or Economy.research_waiting()
	cancel_button.disabled = Economy.research_waiting()


func _refresh_card(id: String, now: float) -> void:
	var c: Dictionary = cards[id]
	var d := GameData.research_def(id)
	var st := card_state(id)
	var lv := Economy.research_level(id)
	c.lv.text = "Lv %d/%d" % [lv, int(d.max_level)]
	c.bar.value = float(lv) / maxf(1.0, float(d.max_level))
	var dim := Color(1, 1, 1, 0.5) if st == "locked" else Color.WHITE
	c.box.modulate = dim
	c.lock.visible = st == "locked"
	match st:
		"running":
			c.state.text = UiKit.duration(Economy.research_left(now))
			c.state.add_theme_color_override("font_color", UiKit.AMBER.darkened(0.35))
		"max":
			c.state.text = "MAX"
			c.state.add_theme_color_override("font_color", MAX_GOLD.darkened(0.25))
		_:
			c.state.text = AVAILABLE_TEXT if Economy.research_block(id) == "" else ""
			c.state.add_theme_color_override("font_color", GREEN)
	c.face.queue_redraw()


# --- 노드 상세 ---

## 카드 탭: 그 노드 상세를 아래에서 띄운다(연 직후 보호 시간 — 연타가 배경을 눌러 닫지 않게).
func open_detail(id: String) -> void:
	if GameData.research_def(id).is_empty():
		return
	detail_id = id
	if _detail_icon_id != id:
		_detail_icon_id = id
		_swap_icon(_detail_icon_box, id, DETAIL_ICON_PX)
	detail.visible = true
	_arm_guard()
	_refresh_detail(Economy.time_now())


func close_detail() -> void:
	if detail != null:
		detail.visible = false


func is_detail_open() -> bool:
	return visible and detail.visible


func _refresh_detail(now: float) -> void:
	var id := detail_id
	var d := GameData.research_def(id)
	var lv := Economy.research_level(id)
	var mx := int(d.max_level)
	var running := str(Economy.research_current.get("id", "")) == id
	detail_name.text = "%s Lv %d/%d" % [d.name, lv, mx]
	detail_desc.text = EFFECT_DESC.get(d.effect, "")
	var now_v := effect_value(d.effect, lv * float(d.per_level))
	detail_effect.text = "%s  현재 %s" % [EFFECT_NAMES.get(d.effect, d.effect), now_v] + (" (최대)" if lv >= mx else " → 다음 " + effect_value(d.effect, (lv + 1) * float(d.per_level)))
	_clear(detail_reqs)
	for r in Economy.research_requirements(id):
		var what: String = "연구소" if r.kind == "lab" else str(GameData.research_def(r.id).get("name", r.id))
		var text := "%s %s Lv %d 필요" % ["✓" if r.ok else "✗", what, int(r.need)] + ("" if r.ok else " (현재 %d)" % int(r.have))
		detail_reqs.add_child(_label(text, 24, GREEN if r.ok else RED))
	var cost := Economy.research_cost(id)
	var have := {"wood": int(Economy.res.get("wood", 0)), "stone": int(Economy.res.get("stone", 0)), "food": int(Economy.res.get("food", 0)), "gold": Economy.gold}
	for r in detail_cost:
		var need := int(cost.get(r, 0))
		var l: Label = detail_cost[r]
		l.text = "%s/%s" % [UiKit.commas(have[r]), UiKit.commas(need)]
		l.add_theme_color_override("font_color", RED if have[r] < need else HudScript.INK)
		var shown := need > 0
		l.visible = shown
		_cost_grid.get_child(l.get_index() - 1).visible = shown  # 아이콘
	var open_lv := lv < mx and not running
	_cost_grid.get_parent().visible = open_lv and not cost.is_empty()
	detail_time.text = "연구 시간 " + UiKit.duration(Economy.research_sec(id))
	detail_time.visible = open_lv
	var why := Economy.research_block(id)
	var reason: String = EconomyScript.RESEARCH_TEXT.get(why, "") if why != "waiting" else ""
	if why == "research_busy":  # 무엇을 연구 중인지·남은 시간도
		var cur := str(Economy.research_current.id)
		reason += " (%s %s)" % [GameData.research_def(cur).get("name", cur), UiKit.duration(Economy.research_left(now))]
	detail_reason.text = reason
	detail_reason.visible = reason != "" and not running
	start_button.visible = not running
	start_button.disabled = why != ""
	detail_run.visible = running
	if running:
		detail_bar.value = Economy.research_progress(now)
		detail_left.text = "Lv %d → %d 연구 중 · 남은 시간 %s" % [lv, lv + 1, UiKit.duration(Economy.research_left(now))]
		var dia := Economy.research_dia_cost(now)
		detail_dia.text = "      %d 즉시 완료" % dia
		detail_dia.disabled = Economy.diamonds < dia or Economy.research_waiting()
		detail_cancel.disabled = Economy.research_waiting()


## 효과 값 글자: % 효과는 "+15%"(훈련 비용은 "-4%"), 인구는 "+2명".
static func effect_value(effect: String, v: float) -> String:
	if effect == "pop_add":
		return "+%d명" % int(v)
	return "%s%s%%" % ["-" if effect == "train_cost_pct" else "+", Skills.num_text(v)]


# --- 아이콘 ---

## 노드 아이콘 kind(Icons): 노드 id → 효과 → 플라스크. 병사 노드는 ""(초상을 쓴다 — soldier_of_node).
static func icon_kind(id: String) -> String:
	if soldier_of_node(id) != "":
		return ""
	var d := GameData.research_def(id)
	return ICONS.get(id, EFFECT_ICONS.get(str(d.get("effect", "")), "flask"))


## 보병·궁병·기병 훈련 노드면 그 병종 id, 아니면 "".
static func soldier_of_node(id: String) -> String:
	return SOLDIER_EFFECTS.get(str(GameData.research_def(id).get("effect", "")), "")


## 노드 아이콘 칸(px): 병사 노드는 실제 병사 3D 초상(SoldierPanel.unit_icon, 갈매기 없음), 나머지는 분야 색 8각 바탕 + 로우폴리 그림.
static func node_icon(id: String, px: float) -> Control:
	var soldier := soldier_of_node(id)
	if soldier != "":
		var u := SoldierPanel.unit_icon(soldier, 0, px)
		u.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		return u
	var c := Control.new()
	c.custom_minimum_size = Vector2(px, px)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kind := icon_kind(id)
	var tint: Color = BRANCH_TINT.get(str(GameData.research_def(id).get("branch", "")), UiKit.STEEL.lightened(0.55))
	c.draw.connect(func():
		var r := Rect2(Vector2.ZERO, c.size).grow(-2.0)
		var oct := LowpolyBox.octagon(r, r.size.x * 0.22)
		c.draw_colored_polygon(oct, tint)
		oct.append(oct[0])
		c.draw_polyline(oct, UiKit.OUTLINE, 2.0, true)
		IconsScript.draw_icon(c, kind, c.size / 2.0, c.size.x * 0.8))
	return c


## 칸(box)의 아이콘을 노드 id 것으로 바꿔 끼운다.
func _swap_icon(box: Control, id: String, px: float) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	box.add_child(node_icon(id, px))


## 줄을 지우고 곧바로 뺀다(queue_free만 하면 이번 프레임 크기 계산에 남는다).
func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()

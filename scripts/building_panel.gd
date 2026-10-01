extends "res://scripts/ui_window.gd"
## 건물 창(개정 12 §2.5): 건물을 탭하거나 길게 누르면 연다(unit_picker → open_building). 제목 "이름 Lv N" + 설명 한 줄,
## 효과 지금 → 다음 레벨(건물별 문장 — effect_lines), 선행 조건 ✓ 초록 / ✗ 빨강, 비용(자원 아이콘, 쓸 수 있는 양보다 많으면 빨강)과
## 건설 시간("mm:ss" 또는 "h시간 m분"), [업그레이드](못 하면 비활성 + 이유 한 줄). 이 건물을 짓는 중이면 비용 대신 진행 막대 + 남은 시간.
## 규칙·상태는 전부 Economy 건물 API(upgrade_block·requirements·upgrade_cost·upgrade_sec·upgrade·build_left·build_progress)다.
## Economy.changed·soldiers_changed마다, 그리고 열려 있는 동안 매초 갱신한다.
## 병사 건물(개정 13 §4·§5): 효과 "1마리 3:00:00 → 2:51:00", 업그레이드 위에 병사 칸 — "다음 보병까지 2:41:10"(매 프레임 글자만),
## 티어 1..보유한 가장 높은 티어 행(병종 그림 + 갈매기, "T1 보유 7", [합성 5→1], 못 하면 빨간 이유 — Economy.merge_block).
## 합성이 반영되면(윗 티어 수가 늘면) 그 행이 튀어 오르고 초록으로 반짝이며 알림 "보병 T2 합성 완료".

const GameData := preload("res://scripts/game_data.gd")
const EconomyScript := preload("res://scripts/economy.gd")
const IconsScript := preload("res://scripts/icons.gd")
const Skills := preload("res://scripts/skills.gd")
const SoldierPanel := preload("res://scripts/soldier_panel.gd")

const DIALOG_W := 640
const GREEN := Color(0.13, 0.58, 0.24)
const RED := Color(0.78, 0.22, 0.18)
const UPGRADE_TEXT := "업그레이드"
const MERGE_ICON_PX := 52.0
const DESC := {  # 설명 한 줄(건물 표에 설명 열이 없다)
	"keep": "성의 중심. 다른 건물의 최대 레벨을 정합니다.",
	"gate": "네 성문이 함께 쓰는 레벨입니다.",
	"barracks": "보병을 기르고 같은 티어끼리 합성합니다.",
	"archery": "궁병을 기르고 같은 티어끼리 합성합니다.",
	"stable": "기병을 기르고 같은 티어끼리 합성합니다.",
	"tavern": "영웅을 모집합니다.",
	"lab": "영웅의 공격을 연구합니다.",
	"houses": "주민이 사는 집. 인구가 병사 배치 상한입니다.",
	"lumber": "목재를 생산합니다.",
	"quarry": "석재를 생산합니다.",
	"farm": "식량을 생산합니다.",
}

var building_id := ""
var title_label: Label
var desc_label: Label
var effects: VBoxContainer  # 효과 줄: HBox[지금(검정), → 다음(초록)]
var reqs: VBoxContainer  # 선행 조건 줄 Label
var cost_labels := {}  # 자원 id → 비용 숫자 Label(아이콘과 한 칸)
var time_label: Label
var progress: ProgressBar
var left_label: Label
var reason_label: Label
var upgrade_button: Button
var soldier_box: VBoxContainer  # 병사 건물 칸(병사 건물일 때만 보인다)
var next_label: Label  # "다음 보병까지 2:41:10"
var merge_rows: Array = []  # 티어 1..최대 → {box, icon, have, button, reason}
var celebrations := 0  # 합성 성공 연출 횟수(테스트용)

var _merge_type := ""  # merge_rows를 만든 병종
var _merge_watch := []  # [윗 티어 키, 누를 때 수] — 그 수가 늘면 합성 성공 연출
var _reqs_title: Label
var _cost_row: HBoxContainer
var _progress_box: VBoxContainer
var _last_key := Vector2i(-1, -1)


func _ready() -> void:
	_build_window(DIALOG_W, 12)
	title_label = _title("")
	content.add_child(title_label)
	desc_label = _label("", 24, HudScript.INK.lightened(0.3))
	content.add_child(desc_label)
	effects = VBoxContainer.new()
	content.add_child(effects)
	_reqs_title = _label("선행 조건", 22, HudScript.INK.lightened(0.3))
	content.add_child(_reqs_title)
	reqs = VBoxContainer.new()
	content.add_child(reqs)
	_cost_row = HBoxContainer.new()
	_cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cost_row.add_theme_constant_override("separation", 8)
	content.add_child(_cost_row)
	for r in GameData.BUILD_RES:
		var icon = IconsScript.new()
		icon.kind = r
		icon.custom_minimum_size = Vector2(36, 36)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_cost_row.add_child(icon)
		var l := _label("", 28, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
		l.custom_minimum_size = Vector2(90, 0)
		_cost_row.add_child(l)
		cost_labels[r] = l
	time_label = _label("", 26)
	content.add_child(time_label)
	_progress_box = VBoxContainer.new()
	content.add_child(_progress_box)
	progress = ProgressBar.new()
	progress.custom_minimum_size = Vector2(0, 26)
	progress.show_percentage = false
	progress.max_value = 1.0
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.apply_bar(progress, UiKit.AMBER)
	_progress_box.add_child(progress)
	left_label = _label("", 26)
	_progress_box.add_child(left_label)
	reason_label = _label("", 24, RED)
	content.add_child(reason_label)
	soldier_box = VBoxContainer.new()
	soldier_box.add_theme_constant_override("separation", 6)
	content.add_child(soldier_box)
	next_label = _label("", 26)
	soldier_box.add_child(next_label)
	upgrade_button = _button(UPGRADE_TEXT)
	upgrade_button.pressed.connect(func(): Economy.upgrade(building_id, Economy.time_now()))
	content.add_child(upgrade_button)
	var close_button := _button("닫기", UiKit.STEEL)
	close_button.pressed.connect(close)
	content.add_child(close_button)
	Economy.changed.connect(func(): if visible: _refresh())
	Economy.soldiers_changed.connect(func(): if visible: _refresh())


## id 건물 창을 연다(건물 표에 없는 id면 열지 않는다).
func open_building(id: String) -> void:
	if GameData.building_def(id).is_empty():
		return
	building_id = id
	_merge_watch = []
	open()


func _on_open() -> void:
	_refresh()


func _process(_delta: float) -> void:
	if not visible:
		return
	if _tick_key(Economy.time_now()) != _last_key:
		_refresh()
	if soldier_box.visible:
		next_label.text = next_text(building_id)


## "다음 보병까지 2:41:10"(남은 0초는 "곧" — 온라인은 서버가 만들 때까지 0에 머문다).
func next_text(id: String) -> String:
	var p := Economy.soldier_production(id)
	var left: float = p.next_in_sec
	return "다음 %s까지 %s" % [GameData.soldier(p.type).name, UiKit.clock(left) if left > 0.0 else "곧"]


## [합성](티어 tier → tier + 1). 윗 티어 수가 늘면(오프라인 곧바로, 온라인 응답 때) _refresh가 연출한다.
func merge(tier: int) -> void:
	var up := EconomyScript.soldier_key(_merge_type, tier + 1)
	_merge_watch = [up, int(Economy.soldiers.get(up, 0))]
	Economy.merge_soldiers(_merge_type, tier)


## 매초 갱신 기준: 시계 초(이유·쌓이는 자원)와 남은 초(끝나는 시각의 소수점에 맞춰 바뀐다) — 둘 중 하나가 바뀌면 다시 그린다.
func _tick_key(now: float) -> Vector2i:
	return Vector2i(floori(now), ceili(Economy.build_left(now)))


func _refresh() -> void:
	var now := Economy.time_now()
	_last_key = _tick_key(now)
	var id := building_id
	var d := GameData.building_def(id)
	var lv := Economy.building_level(id)
	var maxed := lv >= int(d.max_level)
	var building: bool = Economy.is_building(id)
	title_label.text = "%s Lv %d" % [d.name, lv]
	desc_label.text = DESC.get(id, "")
	_clear(effects)
	for row in effect_lines(id, lv):
		var line := HBoxContainer.new()
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		line.add_theme_constant_override("separation", 10)
		line.add_child(_label("%s %s" % [row[0], row[1]], 28))
		if not maxed and row[2] != row[1]:
			line.add_child(_label("→ " + row[2], 28, GREEN))
		effects.add_child(line)
	_clear(reqs)
	var rq := Economy.requirements(id)
	for r in rq:
		var bname: String = GameData.building_def(r.id).name
		reqs.add_child(_label("%s %s Lv %d 필요" % ["✓" if r.ok else "✗", bname, int(r.need)], 26, GREEN if r.ok else RED))
	_reqs_title.visible = not rq.is_empty()
	var cost := Economy.upgrade_cost(id)
	var res_id := Economy.res_of(id)
	for r in cost_labels:
		var need := int(cost.get(r, 0))
		var have := int(Economy.res.get(r, 0)) + (Economy.pending(id, now) if r == res_id else 0)  # 시작할 때 자동 수집분까지(upgrade_block과 같다)
		cost_labels[r].text = UiKit.commas(need)
		cost_labels[r].add_theme_color_override("font_color", RED if have < need else HudScript.INK)
		var shown := need > 0
		cost_labels[r].visible = shown
		_cost_row.get_child(cost_labels[r].get_index() - 1).visible = shown  # 아이콘
	_cost_row.visible = not maxed and not building
	time_label.text = "건설 시간 " + UiKit.duration(Economy.upgrade_sec(id))
	time_label.visible = not maxed and not building
	_progress_box.visible = building
	progress.value = Economy.build_progress(now)
	left_label.text = "Lv %d → %d 건설 중 · 남은 시간 %s" % [lv, lv + 1, UiKit.duration(Economy.build_left(now))]
	var why := Economy.upgrade_block(id, now)
	var reason: String = Economy.BLOCK_TEXT.get(why, "")
	if why == "builder_busy":  # 무엇을 짓는지·남은 시간도
		reason += " (%s %s)" % [GameData.building_def(str(Economy.build.id)).name, UiKit.duration(Economy.build_left(now))]
	reason_label.text = reason
	reason_label.visible = reason != "" and why != "in_progress"  # 짓는 중은 진행 막대가 말한다
	upgrade_button.disabled = why != ""
	_refresh_soldiers(GameData.soldier_of_building(id))
	_fit()


## 병사 칸: 티어 1..보유한 가장 높은 티어(최소 1) 행 — "T1 보유 7", [합성 5→1], 못 하면 빨간 이유. 행은 병종이 바뀔 때만 다시 만든다.
func _refresh_soldiers(type: String) -> void:
	soldier_box.visible = type != ""
	if type == "":
		return
	if type != _merge_type:
		_build_merge_rows(type)
	next_label.text = next_text(building_id)
	var owned := Economy.soldier_counts()
	var top := 1
	for t in range(1, merge_rows.size() + 1):
		if int(owned.get(EconomyScript.soldier_key(type, t), 0)) > 0:
			top = t
	for i in merge_rows.size():
		var t := i + 1
		var r: Dictionary = merge_rows[i]
		var why := Economy.merge_block(type, t)
		r.box.visible = t <= top
		r.have.text = "T%d 보유 %d" % [t, int(owned.get(EconomyScript.soldier_key(type, t), 0))]
		r.button.disabled = why != ""
		r.reason.text = EconomyScript.SOLDIER_TEXT.get(why, "")
	if not _merge_watch.is_empty() and int(owned.get(_merge_watch[0], 0)) > _merge_watch[1]:
		var up: int = EconomyScript.parse_soldier_key(_merge_watch[0])[1]
		_merge_watch = []
		_celebrate(type, up)


func _build_merge_rows(type: String) -> void:
	_merge_type = type
	for r in merge_rows:
		soldier_box.remove_child(r.box)
		r.box.queue_free()
	merge_rows.clear()
	var n := int(GameData.config_num("soldier_merge_count"))
	for t in range(1, int(GameData.config_num("soldier_max_tier")) + 1):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var icon := SoldierPanel.unit_icon(type, t, MERGE_ICON_PX)
		row.add_child(icon)
		var have := _label("", 26, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
		have.custom_minimum_size = Vector2(150, 0)
		have.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(have)
		var b := _button("합성 %d→1" % n, HudScript.ACCENT, 24)
		b.custom_minimum_size = Vector2(160, 52)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(merge.bind(t))
		row.add_child(b)
		var reason := _label("", 20, RED, HORIZONTAL_ALIGNMENT_LEFT)
		reason.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reason.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(reason)
		soldier_box.add_child(row)
		merge_rows.append({"box": row, "icon": icon, "have": have, "button": b, "reason": reason})


## 합성 성공 연출: 새 티어 행의 그림이 튀어 오르고 "T2 보유 N"이 초록으로 반짝인다 + 알림.
func _celebrate(type: String, tier: int) -> void:
	celebrations += 1
	var r: Dictionary = merge_rows[tier - 1]
	var icon: Control = r.icon
	icon.pivot_offset = icon.size / 2.0
	var tw := icon.create_tween()
	tw.tween_property(icon, "scale", Vector2.ONE * 1.35, 0.12)
	tw.tween_property(icon, "scale", Vector2.ONE, 0.18)
	var have: Label = r.have
	have.add_theme_color_override("font_color", GREEN)
	have.create_tween().tween_property(have, "theme_override_colors/font_color", HudScript.INK, 0.6)
	Economy.notice.emit("%s T%d 합성 완료" % [GameData.soldier(type).name, tier])


## 효과 줄(건물별 문장 템플릿) [[이름, 지금 값, 다음 레벨 값], …]. 값이 같으면 창은 지금 값만, 최대 레벨이면 다음을 안 쓴다.
## 병사 건물은 한 마리 생산 시간(개정 13 §4) — 막사의 영웅 HP 보너스는 개정 13 §2에서 없어져 쓰지 않는다.
static func effect_lines(id: String, lv: int) -> Array:
	var n := lv + 1
	var res := GameData.resource_of_building(id)
	if res != "":
		return [["생산", "%d/분" % EconomyScript.rate_per_min(res, lv), "%d/분" % EconomyScript.rate_per_min(res, n)]]
	if GameData.soldier_of_building(id) != "":
		return [["1마리", UiKit.clock(GameData.soldier_unit_sec(lv)), UiKit.clock(GameData.soldier_unit_sec(n))]]
	match id:
		"keep":
			return [["건물 최대", "Lv %d" % lv, "Lv %d" % n],
				["성 HP", UiKit.commas(roundi(GameData.castle_hp_max(lv))), UiKit.commas(roundi(GameData.castle_hp_max(n)))],
				["영웅 슬롯", str(GameData.hero_slots(lv)), str(GameData.hero_slots(n))],
				["성 넓이", "%d칸" % GameData.interior_tiles(lv), "%d칸" % GameData.interior_tiles(n)]]
		"gate":
			return [["성문 HP", UiKit.commas(roundi(GameData.gate_hp_max(lv))), UiKit.commas(roundi(GameData.gate_hp_max(n)))]]
		"lab":
			return [["영웅 공격", _pct(GameData.lab_atk_bonus(lv), "+"), _pct(GameData.lab_atk_bonus(n), "+")]]
		"houses":
			return [["인구", str(GameData.population(lv)), str(GameData.population(n))]]
		"tavern":
			var a := GameData.gacha_rates(lv)
			var b := GameData.gacha_rates(n)
			return [["SSR 확률", _pct(a.ssr), _pct(b.ssr)], ["SR 확률", _pct(a.sr), _pct(b.sr)]]
	return []


static func _pct(v: float, prefix := "") -> String:
	return "%s%s%%" % [prefix, Skills.num_text(v * 100.0)]


## 줄을 지우고 곧바로 뺀다(queue_free만 하면 이번 프레임 크기 계산에 남아 창이 줄지 않는다).
func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()

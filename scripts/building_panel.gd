extends "res://scripts/ui_window.gd"
## 건물 창(개정 12 §2.5): 건물을 탭하거나 길게 누르면 연다(unit_picker → open_building). 제목 "이름 Lv N" + 설명 한 줄,
## 효과 지금 → 다음 레벨(건물별 문장 — effect_lines), 선행 조건 ✓ 초록 / ✗ 빨강, 비용(자원 아이콘, 쓸 수 있는 양보다 많으면 빨강)과
## 건설 시간("mm:ss" 또는 "h시간 m분"), [업그레이드](못 하면 비활성 + 이유 한 줄). 이 건물을 짓는 중이면 비용 대신 진행 막대 + 남은 시간.
## 규칙·상태는 전부 Economy 건물 API(upgrade_block·requirements·upgrade_cost·upgrade_sec·upgrade·build_left·build_progress)다.
## Economy.changed마다, 그리고 열려 있는 동안 매초 갱신한다.

const GameData := preload("res://scripts/game_data.gd")
const EconomyScript := preload("res://scripts/economy.gd")
const IconsScript := preload("res://scripts/icons.gd")
const Skills := preload("res://scripts/skills.gd")

const DIALOG_W := 640
const GREEN := Color(0.13, 0.58, 0.24)
const RED := Color(0.78, 0.22, 0.18)
const UPGRADE_TEXT := "업그레이드"
const DESC := {  # 설명 한 줄(건물 표에 설명 열이 없다)
	"keep": "성의 중심. 다른 건물의 최대 레벨을 정합니다.",
	"gate": "네 성문이 함께 쓰는 레벨입니다.",
	"barracks": "병사를 기르는 막사입니다.",
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
	upgrade_button = _button(UPGRADE_TEXT)
	upgrade_button.pressed.connect(func(): Economy.upgrade(building_id, Economy.time_now()))
	content.add_child(upgrade_button)
	var close_button := _button("닫기", UiKit.STEEL)
	close_button.pressed.connect(close)
	content.add_child(close_button)
	Economy.changed.connect(func(): if visible: _refresh())


## id 건물 창을 연다(건물 표에 없는 id면 열지 않는다).
func open_building(id: String) -> void:
	if GameData.building_def(id).is_empty():
		return
	building_id = id
	open()


func _on_open() -> void:
	_refresh()


func _process(_delta: float) -> void:
	if visible and _tick_key(Economy.time_now()) != _last_key:
		_refresh()


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
	_fit()


## 효과 줄(건물별 문장 템플릿) [[이름, 지금 값, 다음 레벨 값], …]. 값이 같으면 창은 지금 값만, 최대 레벨이면 다음을 안 쓴다.
## 병사 건물(막사 등)의 생산 문장은 병사 UI 작업(S2)이 채운다 — 막사의 영웅 HP 보너스는 개정 13 §2에서 없어져 쓰지 않는다.
static func effect_lines(id: String, lv: int) -> Array:
	var n := lv + 1
	var res := GameData.resource_of_building(id)
	if res != "":
		return [["생산", "%d/분" % EconomyScript.rate_per_min(res, lv), "%d/분" % EconomyScript.rate_per_min(res, n)]]
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

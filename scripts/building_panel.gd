extends "res://scripts/ui_window.gd"
## 건물 창(개정 12 §2.5): 건물을 탭하거나 길게 누르면 연다(unit_picker → open_building). 제목 "이름 Lv N" + 설명 한 줄,
## 효과 지금 → 다음 레벨(건물별 문장 — effect_lines), 선행 조건 ✓ 초록 / ✗ 빨강, 비용(자원 아이콘, 쓸 수 있는 양보다 많으면 빨강)과
## 건설 시간("mm:ss" 또는 "h시간 m분"), [업그레이드](못 하면 비활성 + 이유 한 줄). 이 건물을 짓는 중이면 비용 대신 진행 막대 + 남은 시간.
## 규칙·상태는 전부 Economy 건물 API(upgrade_block·requirements·upgrade_cost·upgrade_sec·upgrade·build_left·build_progress)다.
## Economy.changed·training_changed마다, 그리고 열려 있는 동안 매초 갱신한다.
## 병사 건물(개정 16 §3 — 합성은 [병사] 탭으로 옮겼다): 효과 "1마리 3:00:00 → 2:51:00", 설명 아래 훈련 칸(Economy 훈련 API) 셋 중 하나 —
##   비었을 때: 병종 피규어 + "1마리 2:51:00", 수량 입력(qty_box.gd, 1..min(묶음 상한, 자원으로 되는 수)), 총비용(아이콘, 모자라면 빨강),
##   총시간, [훈련](못 하면 비활성 + 이유) / 훈련 중: 진행 막대, "보병 ×8 · 남은 12:34:56", [취소(50% 환불)] / 완료: "보병 ×8 훈련 완료", [수령].
## 성채 효과(사용자 규칙 2026-10-02): 영웅 슬롯·성 넓이 줄은 다음 레벨에서 그 값이 바뀔 때(단계 경계)만 쓴다.
## 연구소(개정 24 §1): 설명 아래 큰 [연구](research_panel을 연다), 효과 "연구 속도 +0% → +2%". 효과 값(생산·인구·성/성문 HP·1마리 시간)은
## 지금 연구 효과를 넣어 보인다(Economy.research_bonus).

const GameData := preload("res://scripts/game_data.gd")
const EconomyScript := preload("res://scripts/economy.gd")
const IconsScript := preload("res://scripts/icons.gd")
const Skills := preload("res://scripts/skills.gd")
const SoldierPanel := preload("res://scripts/soldier_panel.gd")
const QtyBox := preload("res://scripts/qty_box.gd")
const SpeedupList := preload("res://scripts/speedup_list.gd")

const DIALOG_W := 640
signal goto_building(id: String)  # 못 채운 선행 조건 줄을 눌렀다: 창을 닫고 그 건물로(main이 카메라를 옮기고 그 건물 창을 연다, 사용자 2026-10-13)

const GREEN := Color(0.13, 0.58, 0.24)
const RED := Color(0.78, 0.22, 0.18)
const UPGRADE_TEXT := "업그레이드"
const BUILD_TEXT := "건설"  # 튜토리얼 공터
const TRAIN_ICON_PX := 72.0
const RESEARCH_TEXT := "연구"
const DISPATCH_TEXT := "의뢰 보기"
const RECRUIT_TEXT := "영웅 모집"
const CANCEL_TEXT := "취소(50% 환불)"
const FREE_TEXT := "무료 즉시 완료"  # 남은 시간 5분 이하(Economy.free_finish_sec)
const SPEEDUP_TEXT := "가속"  # 2026-10-13: 가속 아이템 목록을 펼친다
const TIERED_KEEP := ["영웅 슬롯", "성 넓이", "면마다 성문"]  # 성채 효과 중 다음 레벨에서 바뀔 때만 쓰는 줄
const DESC := {  # 설명 한 줄(건물 표에 설명 열이 없다)
	"keep": "성의 중심. 다른 건물의 최대 레벨을 정합니다.",
	"gate": "네 성문이 함께 쓰는 레벨입니다.",
	"barracks": "보병을 훈련합니다.",
	"archery": "궁병을 훈련합니다.",
	"stable": "기병을 훈련합니다.",
	"tavern": "영웅을 모집합니다.",
	"lab": "기술을 연구합니다. 레벨이 오르면 상위 연구가 열리고 연구 속도가 빨라집니다.",
	"houses": "주민이 사는 집. 인구만큼 병사를 배치할 수 있습니다.",
	"lumber": "목재를 생산합니다.",
	"quarry": "석재를 생산합니다.",
	"farm": "식량을 생산합니다.",
	"warehouse": "자원과 금광이 쌓이는 최대 시간을 늘립니다.",
	"goldmine": "골드를 생산합니다. 눌러서 받으세요.",
	"forge": "장비 던전에서 장비가 하나 더 나올 확률을 줍니다.",
	"guild_hall": "길드에 가입하면 길드원 도움으로 건설·연구 시간이 줄어듭니다.",
	"watchtower": "전투 중 성 밖 몬스터에게 화살을 쏩니다.",
	"dispatch": "영웅을 의뢰에 보내 보상을 받습니다. 레벨이 오르면 하루 의뢰 수와 높은 희귀도 확률이 오르고 파견 시간이 줄어듭니다.",
}

const ACT_GUARD_MS := 400
const ACT_GUARD_PX := 60.0
var _act_ms := -100000  # 마지막 동작(_acted) 시각과 그 누름 자리
var _act_pos := Vector2.INF
var _press_pos := Vector2.INF  # 마지막 누름 자리·시각(버튼은 뗄 때 눌리므로 그 누름이 방금이었을 때만 쓴다)
var _press_ms := -100000
var building_id := ""
var research  # 연구 창(research_panel.gd, 개정 24). main이 넣는다
var dispatch  # 파견소 창(dispatch_panel.gd, 2026-10-13). main이 넣는다
var recruit  # 모집 창(recruit_panel.gd). main이 넣는다 — 주점 [영웅 모집](2026-10-14)
var title_label: Label
var desc_label: Label
var research_button: Button  # 연구소만: [연구] → 연구 창
var dispatch_button: Button  # 파견소만: [의뢰 보기] → 파견소 창
var recruit_button: Button  # 주점만: [영웅 모집] → 모집 창
var effects: VBoxContainer  # 효과 줄: HBox[지금(검정), → 다음(초록)]
var reqs: VBoxContainer  # 선행 조건 줄 Label
var cost_labels := {}  # 자원 id → 비용 숫자 Label(아이콘과 한 칸)
var time_label: Label
var progress: ProgressBar
var left_label: Label
var reason_label: Label
var upgrade_button: Button
var free_build_button: Button  # 건설 중 · 남은 5분 이하: [무료 즉시 완료]
var speedup_button: Button  # 건설 중: [가속] → 가속 아이템 목록(speedup_list.gd)
var speedups: VBoxContainer  # 가속 아이템 목록(펼쳤을 때만 보인다)
var builder_label: Label  # 두 번째 일꾼 고용 중이면 남은 기한
var free_train_button: Button  # 훈련 중 · 남은 5분 이하: [무료 즉시 완료]
# 훈련 칸(병사 건물일 때만 보인다, 개정 16)
var train_box: VBoxContainer
var empty_box: VBoxContainer  # 비었을 때
var unit_label: Label  # "T2 보병 · 1마리 3:00:00"
var next_label: Label  # 다음 레벨 미리보기 "Lv 7 → T2 해금" 또는 "1마리 2:30:00 → 2:00:00"(개정 19)
var qty  # 수량 입력(qty_box.gd)
var train_cost_labels := {}  # 자원 id → 총비용 숫자 Label
var train_time_label: Label  # "훈련 시간 23:00:00"
var train_button: Button
var train_reason: Label
var run_box: VBoxContainer  # 훈련 중
var train_bar: ProgressBar
var run_label: Label  # "보병 ×8 · 남은 12:34:56"
var cancel_button: Button
var done_box: VBoxContainer  # 완료
var done_label: Label  # "보병 ×8 훈련 완료"
var collect_button: Button

var _train_type := ""  # 훈련 칸 피규어를 만든 "병종:티어"
var _unit_icon: Control
var _train_cost_row: HBoxContainer
var _reqs_title: Label
var _cost_row: HBoxContainer
var _progress_box: VBoxContainer
var _last_key := Vector2i(-1, -1)


func _ready() -> void:
	_build_window(DIALOG_W, 12)
	title_label = _title("")
	content.add_child(title_label)
	desc_label = _label("", 24, HudScript.INK.lightened(0.3))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(DIALOG_W - 48, 0)
	content.add_child(desc_label)
	research_button = _button(RESEARCH_TEXT, UiKit.GRADE_COLORS.SR, 32)
	research_button.custom_minimum_size = Vector2(0, 84)
	research_button.pressed.connect(open_research)
	content.add_child(research_button)
	dispatch_button = _button(DISPATCH_TEXT, UiKit.GRADE_COLORS.SR, 32)
	dispatch_button.custom_minimum_size = Vector2(0, 84)
	dispatch_button.pressed.connect(open_dispatch)
	content.add_child(dispatch_button)
	recruit_button = _button(RECRUIT_TEXT, UiKit.GRADE_COLORS.SR, 32)
	recruit_button.custom_minimum_size = Vector2(0, 84)
	recruit_button.pressed.connect(open_recruit)
	content.add_child(recruit_button)
	_build_train_box()
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
	free_build_button = _button(FREE_TEXT, GREEN)  # 남은 5분 이하면 무료 즉시 완료(사용자 2026-10-06)
	free_build_button.pressed.connect(func(): _acted(Economy.free_finish_build(building_id)))
	_progress_box.add_child(free_build_button)
	speedup_button = _button(SPEEDUP_TEXT, UiKit.AMBER)
	speedup_button.pressed.connect(func():
		speedups.visible = not speedups.visible
		_refresh())
	_progress_box.add_child(speedup_button)
	speedups = SpeedupList.new()
	speedups.used.connect(_acted.bind(true))
	speedups.visible = false
	_progress_box.add_child(speedups)
	builder_label = _label("", 22, HudScript.INK.lightened(0.3))
	content.add_child(builder_label)
	reason_label = _label("", 24, RED)
	content.add_child(reason_label)
	upgrade_button = _button(UPGRADE_TEXT)
	upgrade_button.pressed.connect(func(): _acted(Economy.upgrade(building_id, Economy.time_now())))
	content.add_child(upgrade_button)
	var close_button := _button("닫기", UiKit.STEEL)
	close_button.pressed.connect(close)
	content.add_child(close_button)
	Economy.changed.connect(func(): if visible: _refresh())
	Economy.training_changed.connect(func(): if visible: _refresh())
	Economy.research_changed.connect(func(): if visible: _refresh())  # 개정 24: 연구 효과(생산·인구·HP·훈련)
	Economy.speedups_changed.connect(func(): if visible: _refresh())


## id 건물 창을 연다(건물 표에 없는 id면 열지 않는다).
func open_building(id: String) -> void:
	if GameData.building_def(id).is_empty():
		return
	if Tutorial.build_locked(id):  # 첫 건축은 그 튜토리얼 미션에서(창은 열지 않고 몇 번째 미션인지 토스트)
		Tutorial.lock_notice.emit(Tutorial.build_lock_text(id))
		return
	building_id = id
	speedups.visible = false
	open()


func _on_open() -> void:
	_refresh()
	Tutorial.note("open", 1, building_id)  # 튜토리얼 "성채 살펴보기"


## 파견소 [의뢰 보기]: 이 창을 닫고 파견소 창을 연다.
func open_dispatch() -> void:
	if dispatch == null:
		return
	close()
	dispatch.open()


## 주점 [영웅 모집]: 이 창을 닫고 모집 창을 연다.
func open_recruit() -> void:
	if recruit == null:
		return
	close()
	recruit.open()


## 기능 창(연구·모집·파견소)에서 건물 창으로 가는 버튼 글자(사용자 2026-10-14 "연구소 레벨업은 어떻게 해?").
## 건설 중이면 남은 시간, 최대 레벨이면 "정보", 아니면 "Lv n → n+1 레벨업".
static func levelup_text(id: String) -> String:
	var name := GameData.building_name(id)
	var lv := Economy.building_level(id)
	if Economy.is_building(id):
		return "%s 레벨업 중 · %s ›" % [name, UiKit.duration(Economy.build_left(Economy.time_now(), id))]
	if lv >= int(GameData.building_def(id).get("max_level", 0)):
		return "%s 정보 (최대 레벨) ›" % name
	return "%s 레벨업 Lv %d → %d ›" % [name, lv, lv + 1]


## 연구소 [연구]: 이 창을 닫고 연구 창을 연다.
func open_research() -> void:
	if research == null:
		return
	close()
	research.open()


func _process(_delta: float) -> void:
	if not visible:
		return
	if _tick_key(Economy.time_now()) != _last_key:
		_refresh()


## 매초 갱신 기준: 시계 초(이유·쌓이는 자원·훈련 남은 시간)와 건설 남은 초(끝나는 시각의 소수점에 맞춰 바뀐다) — 둘 중 하나가 바뀌면 다시 그린다.
func _tick_key(now: float) -> Vector2i:
	return Vector2i(floori(now), ceili(Economy.build_left(now, building_id)))


func _refresh() -> void:
	var now := Economy.time_now()
	_last_key = _tick_key(now)
	var id := building_id
	var d := GameData.building_def(id)
	var lv := Economy.building_level(id)
	var maxed := lv >= int(d.max_level)
	var building: bool = Economy.is_building(id)
	var lot := not Economy.is_built(id)  # 튜토리얼 공터: 짓기(0 → 1)
	title_label.text = "%s · 공터" % GameData.building_name(id) if lot else "%s Lv %d" % [GameData.building_name(id), lv]
	desc_label.text = DESC.get(GameData.type_of(id), "")
	research_button.visible = id == GameData.LAB and not lot
	dispatch_button.visible = GameData.type_of(id) == GameData.DISPATCH and not lot
	recruit_button.visible = id == GameData.TAVERN and not lot and recruit != null
	upgrade_button.text = BUILD_TEXT if lot else UPGRADE_TEXT
	_clear(effects)
	for row in (effect_lines(id, 1) if lot else []):
		effects.add_child(_label("지으면 %s %s" % [row[0], row[1]], 28, GREEN))
	for row in ([] if lot else effect_lines(id, lv)):
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
		var bname: String = GameData.building_name(r.id)
		var text := "%s %s Lv %d 필요" % ["✓" if r.ok else "✗", bname, int(r.need)]
		reqs.add_child(_label(text, 26, GREEN) if r.ok else _req_link(text + "  ›", str(r.id)))
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
	free_build_button.visible = building and Economy.can_free_build(now, id)
	speedup_button.visible = building and not free_build_button.visible
	speedup_button.text = SPEEDUP_TEXT + (" ▲" if speedups.visible else " ▼")
	speedups.visible = speedups.visible and speedup_button.visible
	if speedups.visible:
		speedups.target = "build"
		speedups.building = id
		speedups.refresh()
	progress.value = Economy.build_progress(now, id)
	left_label.text = ("건설 중 · 남은 시간 %s" % UiKit.duration(Economy.build_left(now, id))) if lot \
		else "Lv %d → %d 건설 중 · 남은 시간 %s" % [lv, lv + 1, UiKit.duration(Economy.build_left(now, id))]
	var why := Economy.upgrade_block(id, now)
	var reason: String = Economy.BLOCK_TEXT.get(why, "")
	if why == "builder_busy":  # 무엇을 짓는지·남은 시간도(일꾼마다)
		reason += " (%s)" % ", ".join(Economy.build_jobs().map(func(j): return "%s %s" % [GameData.building_name(str(j.id)), UiKit.duration(Economy.build_left(now, str(j.id)))]))
	builder_label.text = ("두 번째 일꾼 남은 기간 %s" % UiKit.duration(Economy.builder2_until - now)) if Economy.builder2_active(now) else ""
	builder_label.visible = builder_label.text != ""
	reason_label.text = reason
	reason_label.visible = reason != "" and why != "in_progress"  # 짓는 중은 진행 막대가 말한다
	upgrade_button.disabled = why != ""
	_refresh_training("" if lot else GameData.soldier_of_building(id))
	_fit()


## 건설·훈련 동작이 됐으면 누름 보호를 다시 건다: 칸이 바뀌어(업그레이드 → 즉시 완료·가속, 훈련 → 취소, 수령 → 훈련) 더블 탭의
## 두 번째 누름이 그 자리에 새로 뜬 다른 버튼을 누르지 않게.
func _acted(ok: bool) -> void:
	if ok:
		_act_ms = Time.get_ticks_msec()
		_act_pos = _press_pos if _act_ms - _press_ms < 1500 else Vector2.INF


## 동작 직후 ACT_GUARD_MS 안에 같은 자리(ACT_GUARD_PX 안)를 다시 누르면 GUI보다 먼저 먹는다(다른 자리 누름은 그대로).
func _input(event: InputEvent) -> void:
	super._input(event)
	if not visible or not ((event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed):
		return
	if Time.get_ticks_msec() - _act_ms < ACT_GUARD_MS and event.position.distance_to(_act_pos) < ACT_GUARD_PX:
		get_viewport().set_input_as_handled()
		return
	_press_pos = event.position
	_press_ms = Time.get_ticks_msec()


## 훈련 칸(개정 16): 비었을 때 / 훈련 중 / 완료 셋 중 하나만 보인다.
func _build_train_box() -> void:
	train_box = VBoxContainer.new()
	train_box.add_theme_constant_override("separation", 8)
	content.add_child(train_box)
	empty_box = VBoxContainer.new()
	empty_box.add_theme_constant_override("separation", 8)
	train_box.add_child(empty_box)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 12)
	head.name = "Head"
	empty_box.add_child(head)
	unit_label = _label("", 28)
	unit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(unit_label)
	next_label = _label("", 24, GREEN)
	empty_box.add_child(next_label)
	qty = QtyBox.new()
	qty.value_changed.connect(func(_v): if visible: _refresh())
	empty_box.add_child(qty)
	_train_cost_row = HBoxContainer.new()
	_train_cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_train_cost_row.add_theme_constant_override("separation", 8)
	empty_box.add_child(_train_cost_row)
	for r in GameData.BUILD_RES:
		var icon = IconsScript.new()
		icon.kind = r
		icon.custom_minimum_size = Vector2(36, 36)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_train_cost_row.add_child(icon)
		var l := _label("", 28, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
		l.custom_minimum_size = Vector2(90, 0)
		_train_cost_row.add_child(l)
		train_cost_labels[r] = l
	train_time_label = _label("", 26)
	empty_box.add_child(train_time_label)
	train_button = _button("훈련", GREEN)
	train_button.pressed.connect(func(): _acted(Economy.start_training(building_id, qty.value)))
	empty_box.add_child(train_button)
	train_reason = _label("", 24, RED)
	empty_box.add_child(train_reason)
	run_box = VBoxContainer.new()
	run_box.add_theme_constant_override("separation", 8)
	train_box.add_child(run_box)
	train_bar = ProgressBar.new()
	train_bar.custom_minimum_size = Vector2(0, 26)
	train_bar.show_percentage = false
	train_bar.max_value = 1.0
	train_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.apply_bar(train_bar, UiKit.AMBER)
	run_box.add_child(train_bar)
	run_label = _label("", 26)
	run_box.add_child(run_label)
	free_train_button = _button(FREE_TEXT, GREEN)
	free_train_button.pressed.connect(func(): _acted(Economy.free_finish_training(building_id)))
	run_box.add_child(free_train_button)
	cancel_button = _button(CANCEL_TEXT, UiKit.STEEL)
	cancel_button.pressed.connect(func(): _acted(Economy.cancel_training(building_id)))
	run_box.add_child(cancel_button)
	done_box = VBoxContainer.new()
	done_box.add_theme_constant_override("separation", 8)
	train_box.add_child(done_box)
	done_label = _label("", 28, GREEN)
	done_box.add_child(done_label)
	collect_button = _button("수령", GREEN)
	collect_button.pressed.connect(func(): _acted(Economy.collect_training(building_id)))
	done_box.add_child(collect_button)


## 훈련 칸 갱신. 수량 범위 = 1..min(묶음 상한, 지금 자원으로 되는 수)(되는 수가 0이면 1 — 비용이 빨갛고 [훈련]이 꺼진다).
func _refresh_training(type: String) -> void:
	train_box.visible = type != ""
	if type == "":
		return
	var id := building_id
	var q := Economy.training(id)
	var tier: int = q.tier if q.count > 0 else Economy.train_tier(id)  # 진행 중 묶음은 시작할 때 티어(개정 19)
	if "%s:%d" % [type, tier] != _train_type:  # 병종 피규어 + 티어 갈매기(렌더가 끝나면 다시 그린다 — SoldierPanel.unit_icon)
		_train_type = "%s:%d" % [type, tier]
		if _unit_icon != null:
			_unit_icon.queue_free()
		_unit_icon = SoldierPanel.unit_icon(type, tier, TRAIN_ICON_PX)
		var head: HBoxContainer = empty_box.get_node("Head")
		head.add_child(_unit_icon)
		head.move_child(_unit_icon, 0)
	var nm: String = GameData.soldier(type).name
	empty_box.visible = q.count == 0
	run_box.visible = q.count > 0 and not q.ready
	done_box.visible = q.count > 0 and q.ready
	if q.count > 0:
		var left := maxf(0.0, float(q.finish) - Economy.time_now())
		train_bar.value = Economy.train_progress(id)
		run_label.text = "T%d %s ×%d · 남은 %s" % [tier, nm, q.count, UiKit.clock(left)]
		done_label.text = "T%d %s ×%d 훈련 완료" % [tier, nm, q.count]
		free_train_button.visible = Economy.can_free_train(id)
		cancel_button.disabled = Economy.training_waiting(id, "cancel")
		collect_button.disabled = Economy.training_waiting(id, "collect")
		return
	qty.set_range(1, maxi(1, mini(Economy.train_max(id), _affordable(type, tier))))
	qty.visible = Economy.train_max(id) > 1  # 훈련은 1마리씩(사용자 2026-10-06) — 수량 고르기 없음
	var n: int = qty.value
	var lv := Economy.building_level(id)
	unit_label.text = "T%d %s · 1마리 %s" % [tier, nm, UiKit.clock(Economy.train_time(id, 1))]
	next_label.text = train_preview(id, lv)
	next_label.visible = next_label.text != ""
	var cost := Economy.train_cost_now(type, n, tier)
	for r in train_cost_labels:
		var need := int(cost.get(r, 0))
		train_cost_labels[r].text = UiKit.commas(need)
		train_cost_labels[r].add_theme_color_override("font_color", RED if int(Economy.res.get(r, 0)) < need else HudScript.INK)
		train_cost_labels[r].visible = need > 0
		_train_cost_row.get_child(train_cost_labels[r].get_index() - 1).visible = need > 0  # 아이콘
	_train_cost_row.visible = not cost.is_empty()
	train_time_label.text = "훈련 시간 " + UiKit.clock(Economy.train_time(id, n))
	var why := Economy.train_block(id, n)
	train_button.disabled = why != ""
	train_reason.text = EconomyScript.TRAIN_TEXT.get(why, "")
	train_reason.visible = why != ""


## 다음 레벨 미리보기(개정 19): 티어가 바뀌면 "Lv 7 → T2 해금", 아니면 "1마리 2:30:00 → 2:00:00", 최대 레벨이면 "".
static func train_preview(id: String, lv: int) -> String:
	if lv >= int(GameData.building_def(id).get("max_level", 0)):
		return ""
	if GameData.train_tier(lv + 1) > GameData.train_tier(lv):
		return "Lv %d → T%d 해금" % [lv + 1, GameData.train_tier(lv + 1)]
	var k := 1.0 + float(Economy.research_bonus().train_speed_pct) / 100.0  # 개정 24 훈련 교범
	return "1마리 %s → %s" % [UiKit.clock(GameData.soldier_unit_sec(lv) / k), UiKit.clock(GameData.soldier_unit_sec(lv + 1) / k)]


## 지금 자원으로 훈련할 수 있는 수(무료면 아주 큰 수).
static func _affordable(type: String, tier := 1) -> int:
	var n := 1 << 30
	var one := GameData.train_unit_cost(type, tier)
	for r in one:
		if int(one[r]) > 0:
			n = mini(n, int(Economy.res.get(r, 0)) / int(one[r]))
	return n


## 효과 줄(건물별 문장 템플릿) [[이름, 지금 값, 다음 레벨 값], …]. 값이 같으면 창은 지금 값만, 최대 레벨이면 다음을 안 쓴다.
## 병사 건물은 1마리 훈련 시간(개정 16) — 막사의 영웅 HP 보너스는 개정 13 §2에서 없어져 쓰지 않는다.
## 성채의 영웅 슬롯·성 넓이 줄은 다음 레벨에서 값이 바뀔 때만(단계 경계 — keep_slot_tiers·keep_interior_tiers) 넣는다. 최대 레벨이면 다음이 없어 둘 다 빠진다.
static func effect_lines(id: String, lv: int) -> Array:
	var n := lv + 1
	var rb: Dictionary = Economy.research_bonus()  # 개정 24: 지금 연구 효과를 넣은 값
	var res := GameData.resource_of_building(id)
	if res != "":
		var pct := Economy.res_pct(res)
		return [["생산", "%d/분" % EconomyScript.rate_per_min(res, lv, pct), "%d/분" % EconomyScript.rate_per_min(res, n, pct)]]
	if GameData.soldier_of_building(id) != "":
		var k := 1.0 + float(rb.train_speed_pct) / 100.0
		var tn := GameData.train_tier(n)
		var next_unit := UiKit.clock(GameData.soldier_unit_sec(n) / k)
		return [["1마리", UiKit.clock(GameData.soldier_unit_sec(lv) / k), ("T%d " % tn if tn > GameData.train_tier(lv) else "") + next_unit]]  # 티어가 바뀌면 "T2 3:00:00"
	match GameData.type_of(id):
		"warehouse":  # 2026-10-13 새 건물
			return [["쌓이는 시간", UiKit.duration(GameData.accum_cap_min(lv) * 60.0), UiKit.duration(GameData.accum_cap_min(n) * 60.0)]]
		"goldmine":
			return [["골드 생산", "%s/분" % UiKit.commas(GameData.goldmine_per_min(lv)), "%s/분" % UiKit.commas(GameData.goldmine_per_min(n))]]
		"forge":
			return [["장비 추가 확률", _pct(GameData.forge_extra_p(lv)), _pct(GameData.forge_extra_p(n))]]
		"guild_hall":
			return [["길드 도움", "%d회" % GameData.guild_helps(lv), "%d회" % GameData.guild_helps(n)]]
		"watchtower":
			var p0 := GameData.config_num("watchtower_grunt_pct_base")
			var p1 := GameData.config_num("watchtower_grunt_pct_per_level")
			return [["화살 피해", "졸개 HP %s%%" % Skills.num_text(p0 + p1 * lv), "졸개 HP %s%%" % Skills.num_text(p0 + p1 * n)]]
		"keep":
			var hp := 1.0 + float(rb.castle_hp_pct) / 100.0
			var rows := [["건물 최대", "Lv %d" % lv, "Lv %d" % n],
				["성 HP", UiKit.commas(roundi(GameData.castle_hp_max(lv) * hp)), UiKit.commas(roundi(GameData.castle_hp_max(n) * hp))],
				["영웅 슬롯", str(GameData.hero_slots(lv)), str(GameData.hero_slots(n))],
				["성 넓이", "%d칸" % GameData.interior_tiles(lv), "%d칸" % GameData.interior_tiles(n)],
				["면마다 성문", "%d개" % GameData.gates_at(lv), "%d개" % GameData.gates_at(n)]]
			var maxed := lv >= int(GameData.building_def("keep").get("max_level", 0))
			return rows.filter(func(r): return not r[0] in TIERED_KEEP or (r[1] != r[2] and not maxed))
		"gate":
			var hp := 1.0 + float(rb.gate_hp_pct) / 100.0
			return [["성문 HP", UiKit.commas(roundi(GameData.gate_hp_max(lv) * hp)), UiKit.commas(roundi(GameData.gate_hp_max(n) * hp))]]
		"lab":  # 연구소 몫의 연구 속도만(연구 방법론은 연구 창 위에 합쳐 보인다)
			return [["연구 속도", _pct(GameData.research_speed({}, lv), "+"), _pct(GameData.research_speed({}, n), "+")]]
		"houses":
			var add := int(rb.pop_add)
			return [["인구", str(GameData.population(lv) + add), str(GameData.population(n) + add)]]
		"dispatch":
			var DP := preload("res://scripts/dispatch_panel.gd")
			return [["하루 의뢰", "%d개" % DP.slots(lv), "%d개" % DP.slots(n)],
				["SR·SSR 확률", "%s%% · %s%%" % [DP._pct(DP.odds(lv)[2]), DP._pct(DP.odds(lv)[3])], "%s%% · %s%%" % [DP._pct(DP.odds(n)[2]), DP._pct(DP.odds(n)[3])]],
				["파견 시간", "%d%%" % roundi(DP.time_mult(lv) * 100.0), "%d%%" % roundi(DP.time_mult(n) * 100.0)]]
		"tavern":
			var a := GameData.gacha_rates(GameData.GACHA_GOLD, 1, lv)  # 골드 Lv 1 기준(주점 보너스만 보인다)
			var b := GameData.gacha_rates(GameData.GACHA_GOLD, 1, n)
			return [["SSR 확률", _pct(a.ssr), _pct(b.ssr)], ["SR 확률", _pct(a.sr), _pct(b.sr)]]
	return []


static func _pct(v: float, prefix := "") -> String:
	return "%s%s%%" % [prefix, Skills.num_text(v * 100.0)]


## 줄을 지우고 곧바로 뺀다(queue_free만 하면 이번 프레임 크기 계산에 남아 창이 줄지 않는다).
func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


## 못 채운 선행 조건 줄: 빨간 글자 버튼 — 누르면 창을 닫고 그 건물로 간다(goto_building).
func _req_link(text: String, bid: String) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 26)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, RED)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func():
		close()
		goto_building.emit(bid))
	return b

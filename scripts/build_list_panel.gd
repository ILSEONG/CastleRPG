extends "res://scripts/ui_window.gd"
## 건물 목록 창(사용자 2026-10-13, [건물] 버튼이 연다): 성채를 뺀 건물마다 한 줄 — 이름, 상태(Lv N · 아직 짓지 않음 · 건설 중),
## 아직 짓지 않은 건물은 건설 비용(자원 아이콘, 모자라면 빨강)과 [건설], 지은 건물은 [이동]. 못 지으면 버튼을 끄고 아래에 이유 한 줄
## (가이드 잠금 · 다른 건물 건설 중 · 자원 부족). [건설]·[이동]은 창을 닫고 자리 고르기(placement.gd)를 시작한다.

const GameData := preload("res://scripts/game_data.gd")
const Balance := preload("res://scripts/balance.gd")
const IconsScript := preload("res://scripts/icons.gd")

const DIALOG_W := 660
const GREEN := Color(0.13, 0.58, 0.24)
const RED := Color(0.78, 0.22, 0.18)
const BUILD_TEXT := "건설"
const MOVE_TEXT := "이동"
const VIEW_TEXT := "보기"

var placement  # placement.gd — main이 넣는다
var building_panel  # building_panel.gd — 짓는 중인 공터 [보기]
var rows := {}  # 건물 id → {status, costs(HBox), button, reason}


func _ready() -> void:
	_build_window(DIALOG_W, 8)
	content.add_child(_title("건물"))
	var hint := _label("건물을 고르고 성 안 원하는 자리에 짓습니다", 22, HudScript.INK.lightened(0.3))
	content.add_child(hint)
	for b in Balance.BUILDINGS:
		if Balance.FIXED.has(b.id):
			continue
		_add_row(b.id)
	var close_button := _button("닫기", UiKit.STEEL)
	close_button.pressed.connect(close)
	content.add_child(close_button)
	Economy.changed.connect(func(): if visible: _refresh())


func _add_row(id: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var name_label := _label(GameData.building_def(id).name, 28, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	name_label.custom_minimum_size = Vector2(170, 0)
	line.add_child(name_label)
	var status := _label("", 22, HudScript.INK.lightened(0.3), HORIZONTAL_ALIGNMENT_LEFT)
	status.custom_minimum_size = Vector2(110, 0)
	line.add_child(status)
	var costs := HBoxContainer.new()
	costs.add_theme_constant_override("separation", 4)
	costs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(costs)
	var btn := _button(BUILD_TEXT, UiKit.AMBER, 26)
	btn.custom_minimum_size = Vector2(110, 56)
	btn.pressed.connect(_on_pressed.bind(id))
	line.add_child(btn)
	box.add_child(line)
	var reason := _label("", 20, RED, HORIZONTAL_ALIGNMENT_RIGHT)
	box.add_child(reason)
	content.add_child(box)
	rows[id] = {"status": status, "costs": costs, "button": btn, "reason": reason}


func _on_open() -> void:
	_refresh()


func _refresh() -> void:
	var now := Economy.time_now()
	for id in rows:
		var r: Dictionary = rows[id]
		var built: bool = Economy.is_built(id)
		var placed: bool = Economy.is_placed(id)
		var btn: Button = r.button
		var why := ""
		for c in r.costs.get_children():
			c.queue_free()
		if built:
			r.status.text = "Lv %d" % Economy.building_level(id)
			btn.text = MOVE_TEXT
			UiKit.apply_button(btn, UiKit.STEEL, 14.0)
		elif placed:  # 짓기 시작한 공터
			r.status.text = "건설 중" if Economy.is_building(id) else "공터"
			btn.text = VIEW_TEXT
			UiKit.apply_button(btn, UiKit.STEEL, 14.0)
		else:
			r.status.text = "미건설"
			btn.text = BUILD_TEXT
			UiKit.apply_button(btn, UiKit.AMBER, 14.0)
			var cost := Economy.upgrade_cost(id)
			for k in GameData.BUILD_RES:
				var need := int(cost.get(k, 0))
				if need <= 0:
					continue
				var icon = IconsScript.new()
				icon.kind = k
				icon.custom_minimum_size = Vector2(26, 26)
				icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				r.costs.add_child(icon)
				r.costs.add_child(_label(UiKit.commas(need), 20, RED if int(Economy.res.get(k, 0)) < need else HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
			if Tutorial.build_locked(id):
				why = Tutorial.build_lock_text(id)
			else:
				var block := Economy.upgrade_block(id, now)
				why = Economy.BLOCK_TEXT.get(block, "")
				if block == "builder_busy":
					why += " (%s)" % GameData.building_def(str(Economy.build.id)).name
		btn.disabled = why != ""
		r.reason.text = why
		r.reason.visible = why != ""
	_fit()


func _on_pressed(id: String) -> void:
	if Economy.is_built(id):
		close()
		placement.start(id)
	elif Economy.is_placed(id):
		close()
		if building_panel != null:
			building_panel.open_building(id)
	else:
		close()
		placement.start(id)

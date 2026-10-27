extends CanvasLayer
## 성 전투 하단 영웅 초상화 줄(사용자 2026-10-06: 스테이지를 미는 동안 메뉴 UI를 숨기고 아래에 영웅 초상화, 누르면 그 영웅 선택).
## main이 스테이지 진행 중(스테이지·결과·카운트다운)에만 보이게 한다. 칸 = 등급 색 8각 바탕 + 피규어 + HP 막대, 쓰러지면 흐리게,
## 선택된 영웅은 금색 테두리. 초상화를 누르면 picker로 그 영웅을 고른다(다시 누르면 해제) — 그다음 성문·성벽·바닥 탭은 평소처럼 이동.
## 영웅 목록은 heroes_fn(지금 영웅 노드 배열, 배치 순서)을 매 프레임 읽어 바뀌면(리필 때 다시 만든 영웅) 칸을 다시 만든다.

const UiKit := preload("res://scripts/ui_kit.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const SkillIcons := preload("res://scripts/skill_icons.gd")
const CameraRig := preload("res://scripts/camera_rig.gd")
const PickerScript := preload("res://scripts/unit_picker.gd")
const SkillAuto := preload("res://scripts/skill_auto_button.gd")

const FACE_MAX := 84.0
const GAP := 18.0  # 영웅 칸 사이(쿨 칸이 어느 영웅 것인지 갈리게 넉넉히)
const SIDE := 16.0
const BOTTOM := 10.0
const HP_GREEN := Color(0.35, 0.8, 0.4)
const SELECT_GOLD := Color(1.0, 0.78, 0.2)
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")
const SLOT_MAX := 60.0  # 스킬 칸 지름 상한(논리 px). 칸 = 열 폭의 반(누르는 곳), 지름 = 그 − SLOT_PAD
const SLOT_PAD := 6.0
const SLOT_TALL := 10.0  # 스킬 칸 버튼 높이 = 지름 + 이만큼(위아래 누르는 여유)
const PER_ROW := 6  # 한 줄 최대 영웅 수 — 넘으면 두 줄(성 배치 최대 12)
const TWO_ROW_FACE := 64.0  # 두 줄일 때 초상화 상한(화면을 덜 가리게)
const READY_GLOW_A := 0.55  # 수동: 준비된 칸 바깥 빛(속성 색 밝게) 투명도
const REQ_RING := Color(1.0, 1.0, 1.0, 0.95)  # 눌러서 쓰려는 중
const READY_SEC := 0.5  # 남은 쿨이 이만큼 이하면 준비됨(조건을 기다리는 발동형은 0.5초마다 다시 본다)
const READY_LIGHT := 0.55  # 준비된 칸 테 = 속성 색을 이만큼 밝게(2026-10-25 그린 아이콘 — 금색 테 대신)
const SLOT_DARK := Color(0.12, 0.14, 0.2, 0.82)
const SLOT_EMPTY := Color(0.12, 0.14, 0.2, 0.28)

var heroes_fn: Callable  # () -> Array(영웅 노드)
var picker  # unit_picker.gd
var row: VBoxContainer
var cells: Array = []  # [{hero, face: Button, bar, cell}]
var _ids: Array = []


func _ready() -> void:
	layer = 1  # HUD와 같은 층(창은 2 이상이 덮는다)
	row = VBoxContainer.new()  # 줄(HBox)들 — 영웅이 PER_ROW 넘으면 두 줄
	row.add_theme_constant_override("separation", 6)
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_bottom = -BOTTOM
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)


func _process(_delta: float) -> void:
	if not visible or not heroes_fn.is_valid():
		return
	var hs: Array = heroes_fn.call()
	var ids := hs.map(func(h): return h.get_instance_id())
	if ids != _ids:
		_rebuild(hs, ids)
	for c in cells:
		var h = c.hero
		if not is_instance_valid(h):
			continue
		c.bar.value = h.hp_ratio() * 100.0
		c.cell.modulate.a = 1.0 if h.is_alive() else 0.45
		c.face.queue_redraw()  # 선택 테두리


func _rebuild(hs: Array, ids: Array) -> void:
	_ids = ids
	cells.clear()
	for c in row.get_children():
		row.remove_child(c)
		c.queue_free()
	var vw := 720.0
	if is_inside_tree():
		vw = get_viewport().get_visible_rect().size.x
	var lay := layout(hs.size(), FACE_MAX, vw - SIDE * 2.0, GAP)
	var px: float = lay.face
	var line: HBoxContainer
	for i in hs.size():
		var h = hs[i]
		if i % int(lay.per_row) == 0:
			line = HBoxContainer.new()
			line.alignment = BoxContainer.ALIGNMENT_CENTER
			line.add_theme_constant_override("separation", int(GAP))
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(line)
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var face := Button.new()
		face.flat = true
		face.focus_mode = Control.FOCUS_NONE
		face.custom_minimum_size = Vector2(px, px)
		face.draw.connect(_draw_face.bind(face, h))
		face.pressed.connect(pick.bind(h))
		if PortraitsScript.current != null:
			PortraitsScript.current.portrait_ready.connect(face.queue_redraw.unbind(1))
		cell.add_child(face_with_slots(face, h, px, lay.col))
		var bar := ProgressBar.new()
		bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		bar.custom_minimum_size = Vector2(px, 12)
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiKit.apply_bar(bar, HP_GREEN)
		cell.add_child(bar)
		line.add_child(cell)
		cells.append({"hero": h, "face": face, "bar": bar, "cell": cell})


## 초상화 누름: 산 영웅이면 선택(이미 선택돼 있으면 해제) + 화면을 그 영웅으로(사용자 2026-10-11). 쓰러진 영웅은 무시.
func pick(h) -> void:
	if picker == null or not is_instance_valid(h) or not h.is_alive():
		return
	picker._select(null if picker.selected == h else h)
	CameraRig.focus_hero(self, h)


func _draw_face(c: Control, h) -> void:
	if not is_instance_valid(h):
		return
	var r := Rect2(Vector2.ZERO, c.size)
	var oct := LowpolyBox.octagon(r.grow(-2.0), r.size.x * 0.2)
	PortraitsScript.draw_face(c, h.def.id, oct, r)  # 등급 색 바탕 + 흉상(디자인 보강 5번)
	oct.append(oct[0])
	var on: bool = picker != null and picker.selected == h
	c.draw_polyline(oct, SELECT_GOLD if on else UiKit.OUTLINE, 5.0 if on else 2.0, true)


## 초상화 위 스킬 칸(사용자 2026-10-23 "스킬 버튼이 너무 작을 수 있으니 검토" — 예전엔 초상화 양옆 아래 지름 ~24 px 그림뿐이었다):
## [첫 액티브][둘째 액티브]를 초상화 위에 나란히, 칸마다 열 폭의 반 × (지름 + SLOT_TALL)을 누를 수 있다(지름은 열 폭에 맞춰 최대 SLOT_MAX).
## 칸 = 스킬 그림(skill_icons.gd). 준비됨 = 그림 + 속성 색 밝은 테(스킬 수동이면 바깥 빛), 쿨 = 남은 몫만큼 어둡게 덮고 시계 방향으로 걷힘 + 남은 초,
## 승급으로 잠김 = 자물쇠, 액티브가 하나뿐(R) = 오른쪽은 작은 흐린 점, 눌러서 쓰려는 중 = 흰 고리.
## 칸을 누르면 그 영웅이 그 스킬을 쓴다(hero.request_skill — [스킬 AUTO]를 끈 수동일 때 쓰는 길, 켜져 있어도 준비된 칸은 바로 쓴다).
## 누를 수 있는 건 내 편 영웅(hero.manual_ok — 공성전·총력전은 그림만). 칸을 눌러도 고른 영웅은 그대로(unit_picker.keep_select).
## 성·던전·PVP·길드전 초상화가 함께 쓴다. col_w = 열 폭(layout), 0이면 초상화 폭. 칸은 초상화가 다시 그려질 때(매 프레임) 같이 다시 그린다.
static func face_with_slots(face: Control, h, px: float, col_w := 0.0) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	var w := maxf(px, col_w)
	var d := slot_px(w)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 0)
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(line)
	var wr: WeakRef = weakref(h)  # 영웅이 먼저 사라져도(리필 때 다시 만든 영웅) 칸이 잡고 있지 않게
	var tappable: bool = h.has_method("manual_ok") and h.manual_ok()
	for i in 2:
		var s := Button.new()
		s.name = "Skill%d" % i
		s.flat = true
		s.focus_mode = Control.FOCUS_NONE
		s.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS  # 누르는 순간
		s.custom_minimum_size = Vector2(floorf(w / 2.0), d + SLOT_TALL)
		s.mouse_filter = Control.MOUSE_FILTER_STOP if tappable else Control.MOUSE_FILTER_IGNORE
		s.set_meta("slot_r", d / 2.0)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # 그린 스킬 아이콘(128 px)을 작게 그려도 거칠지 않게
		s.draw.connect(func(): _draw_slot_at(s, wr.get_ref(), i))
		s.pressed.connect(func(): tap_slot(wr.get_ref(), i))
		face.draw.connect(s.queue_redraw)
		line.add_child(s)
	face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(face)
	return box


## 스킬 칸 누름: 그 칸 액티브를 쓰게 한다. 고른 영웅은 풀지 않는다.
static func tap_slot(h, i: int) -> bool:
	PickerScript.keep_select = true
	if h == null or not is_instance_valid(h) or not h.has_method("request_skill"):
		return false
	var slots: Array = h.active_slots()
	if slots.size() <= i:
		return false
	return h.request_skill(String(slots[i].kind))


## 열 폭 w에서 스킬 칸 지름.
static func slot_px(w: float) -> float:
	return clampf(floorf(w / 2.0) - SLOT_PAD, 16.0, SLOT_MAX)


## n명 배치: {per_row(한 줄 영웅 수), rows, col(열 폭), face(초상화 크기, 최대 max_px)}. 폭 width, 열 사이 gap.
static func layout(n: int, max_px: float, width: float, gap: float) -> Dictionary:
	var k := maxi(1, n)
	var rows := 1 if k <= PER_ROW else ceili(float(k) / PER_ROW)
	var per := ceili(float(k) / rows)
	var col := floorf((width - gap * (per - 1)) / per)
	var face := minf(max_px, col - 8.0)
	if rows > 1:
		face = minf(face, TWO_ROW_FACE)
	return {"per_row": per, "rows": rows, "col": col, "face": face}


## n칸이 한 줄 폭 width(간격 gap)에 들어가는 초상화 크기(최대 max_px) — 한 줄짜리 띠(던전·PVP·길드전)용.
static func fit_px(n: int, max_px: float, width: float, gap: float) -> float:
	return layout(n, max_px, width, gap).face


## 한 줄짜리 띠의 열 폭.
static func col_px(n: int, width: float, gap: float) -> float:
	var k := maxf(1.0, float(n))
	return floorf((width - gap * (k - 1.0)) / k)


static func _draw_slot_at(s: Control, h, i: int) -> void:
	if h == null or not is_instance_valid(h) or not h.has_method("active_slots"):
		return
	var slots: Array = h.active_slots()
	var r: float = s.get_meta("slot_r", s.size.y / 2.0)
	var manual: bool = h.has_method("manual_skills") and h.manual_skills()
	_draw_slot(s, s.size / 2.0, r - 1.0, slots[i] if slots.size() > i else {}, manual)


static func _draw_slot(c: Control, at: Vector2, r: float, s: Dictionary, manual := false) -> void:
	if s.is_empty():  # 액티브가 하나뿐(R): 작은 흐린 점만(큰 빈 원이 누를 칸처럼 보이지 않게)
		c.draw_circle(at, r * 0.25, SLOT_EMPTY)
		return
	var kind := String(s.get("kind", ""))
	if s.locked:  # 회색으로 누른 스킬 그림 + 어둡게 + 자물쇠
		SkillIcons.draw_badge(c, kind, at, r, true)
		c.draw_circle(at, r, Color(0.08, 0.09, 0.12, 0.45))
		var w := r * 0.8
		c.draw_arc(at + Vector2(0, -r * 0.12), w * 0.36, PI, TAU, 10, Color(1, 1, 1, 0.9), maxf(2.0, r * 0.13), true)
		c.draw_rect(Rect2(at + Vector2(-w * 0.5, -r * 0.12), Vector2(w, w * 0.72)), Color(1, 1, 1, 0.9))
		c.draw_arc(at, r, 0.0, TAU, 24, UiKit.OUTLINE, 1.5, true)
		return
	var ready := float(s.left) <= READY_SEC
	if ready and manual:  # 수동: 준비된 칸은 바깥으로 빛이 맥동한다(눌러 쓰라는 표시)
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 1.2)
		c.draw_circle(at, r + 3.0 + 2.0 * pulse, Color(SkillIcons.bg_of(kind).lightened(READY_LIGHT), READY_GLOW_A * (0.5 + 0.5 * pulse)))
	SkillIcons.draw_badge(c, kind, at, r)
	if s.get("req", false):  # 눌러서 쓰려는 중: 흰 고리
		c.draw_arc(at, r + 1.0, 0.0, TAU, 28, REQ_RING, maxf(3.0, r * 0.14), true)
	elif ready:  # 준비됨: 그림 그대로 + 속성 색 밝은 테
		c.draw_arc(at, r - 1.0, 0.0, TAU, 24, SkillIcons.bg_of(kind).lightened(READY_LIGHT), maxf(2.0, r * 0.16), true)
	else:  # 쿨: 남은 몫을 어둡게 덮고(시계 방향으로 걷힌다) 남은 초
		var done := clampf(1.0 - float(s.left) / maxf(0.01, float(s.total)), 0.0, 1.0)
		var pts := PackedVector2Array([at])
		var n := maxi(2, ceili(24.0 * (1.0 - done)))
		for i in n + 1:
			var a := -PI / 2.0 + TAU * done + TAU * (1.0 - done) * float(i) / float(n)
			pts.append(at + Vector2(cos(a), sin(a)) * r)
		c.draw_colored_polygon(pts, SLOT_DARK)
		var fs := int(r * 1.05)
		var txt := str(ceili(float(s.left)))
		var p := at + Vector2(-r, fs * 0.36)
		c.draw_string_outline(FONT, p, txt, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, 4, Color(0, 0, 0, 0.85))
		c.draw_string(FONT, p, txt, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color.WHITE)
	c.draw_arc(at, r, 0.0, TAU, 24, UiKit.OUTLINE, 1.5, true)

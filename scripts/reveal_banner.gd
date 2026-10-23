extends CanvasLayer
## 「새 기능」 띠(초반 단순화 2026-10-23): 가이드 중 숨겨 둔 버튼·탭·메뉴가 처음 나타나면(Tutorial.ui_revealed)
## 화면 가운데 위에 "새 기능: 영웅 · 상점" 띠가 한 번 지나가고, 나타난 버튼이 톡 튀어나온다(가이드 화살표 대상 Tutorial.ui_targets).
## 같은 순간에 여럿이 나타나면(예: 1-1 보상 → [영웅]·[상점]) 한 띠에 모은다. 재화 칩·상점 빨간 점·공지 자동 열림은 띠 없이 나타난다.
## 메뉴 항목은 접힌 [메뉴] 버튼이 튀어나온다. 상인(3D)은 띠만.

const Lang := preload("res://scripts/lang.gd")

const UiKit := preload("res://scripts/ui_kit.gd")
const TabBarScript := preload("res://scripts/tab_bar.gd")
const SideMenuScript := preload("res://scripts/side_menu.gd")

const Y := 0.24  # 띠 가운데 = 화면 높이의 이 지점(상단 스테이지 패널 아래, 잠금 알림 0.3보다 위)
const HOLD_SEC := 2.4
const FADE_SEC := 0.4
const GATHER_SEC := 0.15  # 이만큼 안에 나타난 것은 한 띠로
const SILENT := ["chip:wood", "chip:stone", "chip:food", "shop_dot", "notice_auto"]

var band: PanelContainer
var label: Label
var _pending: Array = []
var _gather := 0.0
var _left := 0.0


func _ready() -> void:
	layer = 3  # 창(2) 위 — 창을 연 채로 보상을 받아도 보인다(눌림은 통과)
	band = PanelContainer.new()
	band.anchor_left = 0.5
	band.anchor_right = 0.5
	band.anchor_top = Y
	band.anchor_bottom = Y
	band.grow_horizontal = Control.GROW_DIRECTION_BOTH
	band.grow_vertical = Control.GROW_DIRECTION_BOTH
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_theme_stylebox_override("panel", UiKit.panel(Color(UiKit.INK, 0.9), 14.0, 18, 0.05))
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(label)
	band.visible = false
	add_child(band)
	Tutorial.ui_revealed.connect(_on_revealed)


func _on_revealed(key: String) -> void:
	if key in SILENT or key in _pending:
		return
	_pending.append(key)
	_gather = GATHER_SEC


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)  # 배속과 무관하게 같은 시간
	if not _pending.is_empty():
		_gather -= real
		if _gather <= 0.0:
			_flush()
	if _left > 0.0:
		_left -= real
		band.modulate.a = clampf(_left / FADE_SEC, 0.0, 1.0)
		band.visible = _left > 0.0


func _flush() -> void:
	var names: Array = []
	for k in _pending:
		var n := name_of(k)
		if n != "" and not n in names:
			names.append(n)
		_pop(k)
	_pending.clear()
	if names.is_empty():
		return
	show_text(Lang.t("reveal_banner.flush") % " · ".join(names))


func show_text(text: String) -> void:
	label.text = text
	var sz := band.get_combined_minimum_size()
	band.offset_left = -sz.x / 2.0
	band.offset_right = sz.x / 2.0
	band.offset_top = -sz.y / 2.0
	band.offset_bottom = sz.y / 2.0
	band.pivot_offset = sz / 2.0
	band.modulate.a = 1.0
	band.visible = true
	_left = HOLD_SEC + FADE_SEC
	band.scale = Vector2(0.6, 0.6)
	create_tween().tween_property(band, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 띠에 쓸 이름(탭·메뉴는 그 버튼 글자를 그대로).
static func name_of(key: String) -> String:
	var id := key.get_slice(":", 1)
	if key.begins_with("tab:"):
		for t in TabBarScript.TABS:
			if t[0] == id:
				return str(t[1])
	if key.begins_with("menu:"):
		for it in SideMenuScript.ITEMS:
			if it[0] == id:
				return str(it[1])
	match key:
		"hud:auto": return Lang.t("hud.ready")
		"hud:speed": return speed_name()
		"hud:fever": return "FEVER"
		"build_button": return Lang.t("build_button.draw_face")
		"merchant": return Lang.t("world_tags.sync")
		"chat": return Lang.t("chat_bar.draw_face")
	return ""


static func speed_name() -> String:
	return Lang.t("reveal_banner.speed_name")


## 나타난 버튼을 톡 튀게(가운데 기준으로 커졌다 돌아온다). 메뉴 항목은 접힌 [메뉴] 버튼을.
func _pop(key: String) -> void:
	var k := "menu" if key.begins_with("menu:") else key
	var t = Tutorial.ui_targets.get(k, null)
	if t == null or not is_instance_valid(t.node):
		return
	var node: Control = t.node
	node.pivot_offset = node.size / 2.0
	var tw := node.create_tween()
	for i in 2:
		tw.tween_property(node, "scale", Vector2(1.25, 1.25), 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(node, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

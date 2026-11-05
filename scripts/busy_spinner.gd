extends CanvasLayer
## 화면 가운데 로딩 고리(사용자 2026-11-05 "인게임 내에서 로딩이 걸리는 부분은 스피너처리를 해"). main이 하나 붙인다.
## 버튼을 누른 뒤 서버 답이 와야 다음 화면이 나오는 동안 띄운다 — 바로 반영(낙관적 처리)하는 동작은 기다림이 없어 띄우지 않는다.
##  · 던전 입장(Economy._waiting "dungeon") · 길드 가입·창설·탈퇴·보스 시작/끝(Guild._locked) · 길드전 요청(GuildWar.busy)
##  · 결제 확인(StorePay._sent) · 그 밖에 Spinner.hold(key, on)로 건 것(거래소 목록 등)
## 0.25초(실제 시간)가 넘게 이어질 때만 보인다(빠른 응답은 깜빡이지 않게). 터치는 막지 않는다(겹쳐 누르기는 각 기능이 막는다).

const Spinner := preload("res://scripts/spinner.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

const SHOW_AFTER := 0.25
const BOX := 104.0
const RING := 60.0

var box: Panel
var ring: Control
var _since := -1.0  # 기다림이 시작된 실제 시각(초), 없으면 -1


func _ready() -> void:
	layer = 60  # 창(2~)·띠 위
	box = Panel.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size = Vector2(BOX, BOX)
	box.add_theme_stylebox_override("panel", UiKit.panel(Color(0.08, 0.1, 0.16, 0.78), 22.0, 0, 0.0))
	add_child(box)
	ring = Spinner.new()
	ring.size = Vector2(RING, RING)
	ring.position = Vector2((BOX - RING) / 2.0, (BOX - RING) / 2.0)
	box.add_child(ring)
	box.visible = false


## 지금 서버 답을 기다리느라 화면이 멈춰 있나.
static func waiting(tree: SceneTree) -> bool:
	if Spinner.held_for() >= 0.0:
		return true
	var root := tree.root
	var econ = root.get_node_or_null("Economy")
	if econ != null and econ.get("_waiting") is Dictionary and econ._waiting.has("dungeon"):
		return true
	var guild = root.get_node_or_null("Guild")
	if guild != null and guild.get("_locked") == true:
		return true
	var war = root.get_node_or_null("GuildWar")
	if war != null and war.get("busy") == true:
		return true
	var pay = root.get_node_or_null("StorePay")
	if pay != null and pay.get("_sent") is Dictionary:  # 되찾기(_quiet)는 조용히 — 사용자가 누른 결제 확인만
		for tok in pay._sent:
			if not (pay.get("_quiet") is Dictionary and pay._quiet.has(tok)):
				return true
	return false


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if waiting(get_tree()):
		if _since < 0.0:
			_since = now
	else:
		_since = -1.0
	var on := _since >= 0.0 and now - _since >= SHOW_AFTER
	box.visible = on
	if on:
		var vs := get_viewport().get_visible_rect().size
		box.position = (vs - box.size) / 2.0

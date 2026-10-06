extends Node3D
## 길드 보스 실제 전투 장면: 배치 영웅이 run.sec초(20초) 동안 드래곤(dragon.gd)과 싸운다. main이 던전처럼 성 월드를 떼어 두고 붙인다
## (Guild.boss_started → main._enter_dungeon(run, 이 스크립트)) — [확인]으로 main.leave_dungeon.
## 무대는 골드 던전과 같은 평야(ArenaKit.plains — 붉은 드래곤이 잘 보인다), 영웅·스킬·피해 숫자도 던전과 같다(hero.gd 아레나). 드래곤은 매 판 Lv 1로 나오고,
## 0이 되면 그 레벨 처치(배너) 뒤 같은 판에서 다음 레벨 HP로 찬다(공격력도 오른다). 시간이 다 되면 드래곤이 받은 피해 합(dragon.dealt = 판 점수)을
## Guild.finish_boss로 내고 결과(boss_done: 등급·코인·골드·도달 레벨)를 띄운다. 온라인은 서버가 피해를 받아 등급·보상을 정한다(상한은 서버 guild.ts BOSS_DMG_CAP).

const GameData := preload("res://scripts/game_data.gd")
const ArenaKit := preload("res://scripts/arena_kit.gd")
const HeroScript := preload("res://scripts/hero.gd")
const DragonScript := preload("res://scripts/dragon.gd")
const CameraRigScript := preload("res://scripts/camera_rig.gd")
const HpBarsScript := preload("res://scripts/hp_bars.gd")
const DamageNumbersScript := preload("res://scripts/damage_numbers.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")
const PickerScript := preload("res://scripts/unit_picker.gd")
const GuildScript := preload("res://scripts/guild.gd")
const MainHud := preload("res://scripts/hud.gd")
const GuildPanel := preload("res://scripts/guild_panel.gd")
const UiKit := preload("res://scripts/ui_kit.gd")
const Fx := preload("res://scripts/fx.gd")

enum Phase { INTRO, FIGHT, REPORT, RESULT }

const CAMERA_SIZE := 26.0
const DRAGON_U := -5.0  # 드래곤 자리(평야 spot u — 영웅은 u 9~11.6)
const INTRO_SEC := 1.2  # 시작 배너("드래곤 출현!") 동안 영웅·드래곤이 움직이지 않는다
const WAIT_SEC := 20.0  # 결과 응답을 이만큼 못 받으면 [확인]만 띄운다
const GOLD := Color("C8901A")

var run := {}  # {run_id, sec, level, hp, max}
var main  # 돌아갈 성 월드(main.gd). 없으면(테스트) 스스로 사라진다
var phase := Phase.INTRO
var clock := 0.0  # 전투 시계(초, 인트로 뒤부터)
var heroes: Array = []
var dragon
var result := {}
var camera: Camera3D
var kills := 0  # 이번 전투에서 처치한 단계 수(연출)

var _intro := INTRO_SEC
var _wait := 0.0
var _leaving := false
var _wiped := false
var _hud: CanvasLayer
var _title: Label
var _time: Label
var _hp_bar: ProgressBar
var _hp_text: Label
var _dmg: Label
var _banner: Label
var _banner_t := 0.0
var _result_layer: ColorRect
var _result_box: VBoxContainer


func _ready() -> void:
	var stage: Dictionary = ArenaKit.plains()
	add_child(ArenaKit.lighting(stage.light))
	add_child(stage.root)
	var crowd = preload("res://scripts/crowd.gd").new()
	crowd.arena_r = ArenaKit.PLAINS_FIGHT_R
	add_child(crowd)
	add_child(PortraitsScript.new())
	var rig = CameraRigScript.new()
	add_child(rig)
	camera = rig.camera
	camera.size = CAMERA_SIZE
	rig.zoom_by(1.0)
	camera.make_current()
	var bars = HpBarsScript.new()
	bars.camera = camera
	add_child(bars)
	var numbers = DamageNumbersScript.new()
	numbers.camera = camera
	add_child(numbers)
	var ids := party()
	for i in ids.size():
		var def := GameData.hero(str(ids[i]))
		if def.is_empty():
			continue
		var h = HeroScript.new()
		h.setup(i, def, null, null, Economy.promotion_of(def.id), Economy.level_of(def.id))
		h.free_pos = stage.heroes[i % stage.heroes.size()]
		h.idle_dir = -ArenaKit.DOWN
		add_child(h)
		heroes.append(h)
	var picker = PickerScript.new()  # 영웅 탭 선택 → 바닥 탭 이동(던전과 같은 조작)
	picker.camera = camera
	picker.arena_r = ArenaKit.PLAINS_FIGHT_R - 1.0
	add_child(picker)
	dragon = DragonScript.new()
	dragon.setup_boss(int(run.get("level", 1)), float(run.get("hp", GuildScript.boss_max(int(run.get("level", 1))))))
	dragon.position = ArenaKit.spot(DRAGON_U, 0.0)
	dragon.rotation.y = atan2(ArenaKit.DOWN.x, ArenaKit.DOWN.z)  # 영웅 쪽(화면 아래)
	dragon.level_cleared.connect(_on_level_cleared)
	add_child(dragon)
	_build_hud()
	Guild.boss_done.connect(_on_done)
	_set_active(false)
	_show_banner("드래곤 출현!", INTRO_SEC + 0.3)
	print("[guild boss] level %d hp %d heroes %d" % [dragon.level, int(dragon.hp), heroes.size()])


## 출전 영웅: 성 배치 칸(GameState.hero_count) 순서대로 — 서버 teamDps와 같은 영웅.
static func party() -> Array:
	var out := []
	for id in Economy.deploy_slots(GameState.hero_count()):
		if id != null:
			out.append(id)
	return out


func fight_sec() -> float:
	return float(run.get("sec", GuildScript.BOSS_FIGHT_SEC))


func time_left() -> float:
	return maxf(0.0, fight_sec() - clock)


func _set_active(on: bool) -> void:
	for h in heroes:
		h.set_process(on)
	dragon.set_process(on)


func _process(delta: float) -> void:
	_banner_t -= delta
	_banner.visible = _banner_t > 0.0
	match phase:
		Phase.INTRO:
			_intro -= delta
			if _intro <= 0.0:
				phase = Phase.FIGHT
				_set_active(true)
		Phase.FIGHT:
			clock += delta
			if not _wiped and not heroes.any(func(h): return h.is_alive()):
				_wiped = true  # 전멸해도 시간은 끝까지 흐른다(서버는 전투 시간이 지나야 결과를 받는다)
				_show_banner("전멸!", 1.6)
			if clock >= fight_sec():
				_report()
		Phase.REPORT:
			_wait += delta
			if _wait > WAIT_SEC:
				_on_done({"error": "timeout"})
	_update_hud()


func _report() -> void:
	phase = Phase.REPORT
	_set_active(false)
	dragon.closed = true
	_show_banner("전투 종료", 1.0)
	Guild.finish_boss(str(run.get("run_id", "")), dragon.dealt)


func _on_level_cleared(lv: int) -> void:
	kills += 1
	_show_banner("드래곤 Lv %d 처치!" % lv, 1.4)
	Fx.kick(self, dragon.global_position, 0.6, 0.12)


func _on_done(res: Dictionary) -> void:
	if phase != Phase.REPORT or _leaving:
		return
	phase = Phase.RESULT
	result = res
	_show_result()


# --- HUD ---

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 1
	add_child(_hud)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 16
	panel.offset_right = -16
	panel.offset_top = 16
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UiKit.panel(MainHud.PANEL_BG, 14.0, 14))
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	_title = _label("", 32, MainHud.INK)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(_title)
	_time = _label("", 32, MainHud.INK)
	row.add_child(_time)
	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(0, 30)
	_hp_bar.show_percentage = false
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.apply_bar(_hp_bar, GuildPanel.RED)
	_hp_text = _label("", 19, Color.WHITE)
	_hp_text.add_theme_color_override("font_outline_color", Color(MainHud.INK, 0.85))
	_hp_text.add_theme_constant_override("outline_size", 5)
	_hp_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_bar.add_child(_hp_text)
	box.add_child(_hp_bar)
	_dmg = _label("", 26, MainHud.INK)
	box.add_child(_dmg)
	_banner = _label("", 60, Color.WHITE)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_top = 330
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.add_theme_color_override("font_outline_color", MainHud.INK)
	_banner.add_theme_constant_override("outline_size", 12)
	root.add_child(_banner)
	_result_layer = ColorRect.new()
	_result_layer.color = Color(0, 0, 0, 0.5)
	_result_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_layer.visible = false
	root.add_child(_result_layer)
	var rp := PanelContainer.new()
	rp.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	rp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	rp.grow_vertical = Control.GROW_DIRECTION_BOTH
	rp.custom_minimum_size = Vector2(620, 0)
	rp.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM_DIALOG, 18.0, 24))
	_result_layer.add_child(rp)
	_result_box = VBoxContainer.new()
	_result_box.add_theme_constant_override("separation", 14)
	rp.add_child(_result_box)


func _update_hud() -> void:
	_title.text = "Lv %d  %s" % [dragon.level, GuildScript.boss_name(dragon.level)]
	_time.text = "%.1f초" % time_left() if phase != Phase.INTRO else "%d초" % roundi(fight_sec())
	_hp_bar.max_value = dragon.hp_max
	_hp_bar.value = maxf(0.0, dragon.hp)
	_hp_text.text = "%s / %s" % [UiKit.commas(int(dragon.hp)), UiKit.commas(int(dragon.hp_max))]
	_dmg.text = "총 피해 %s" % UiKit.commas(int(dragon.dealt))


func _show_banner(text: String, sec: float) -> void:
	_banner.text = text
	_banner_t = sec
	_banner.visible = true


func _show_result() -> void:
	for c in _result_box.get_children():
		c.queue_free()
	if result.has("error") or not result.has("grade"):
		_result_box.add_child(_label("결과를 받지 못했습니다", 40, GuildPanel.RED))
		_result_box.add_child(_label("총 피해 %s · 길드 탭에서 다시 확인하세요" % UiKit.commas(int(dragon.dealt)), 24, MainHud.INK, true))
	else:
		var grade := str(result.grade)
		var head := _label(grade, 96, GuildPanel.GRADE_COLORS.get(grade, GOLD))
		head.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
		head.add_theme_constant_override("outline_size", 10)
		_result_box.add_child(head)
		_result_box.add_child(_label("드래곤 Lv %d 도달 · 점수 %s" % [int(result.get("level", 1)), UiKit.commas(int(result.dmg))], 32, MainHud.INK))
		if float(result.get("sent", result.dmg)) > float(result.dmg) + 0.5:
			_result_box.add_child(_label("(이번 도전 인정 한도까지)", 20, GuildPanel.SUB))
		_result_box.add_child(_label("길드 코인 +%d · 골드 +%s" % [int(result.coins), UiKit.commas(int(result.gold))], 28, GOLD.darkened(0.15)))
		if result.has("total"):
			_result_box.add_child(_label("오늘 내 점수 %s · 길드 점수에 더해집니다" % UiKit.commas(int(result.total)), 24, GuildPanel.GREEN, true))
	var ok := Button.new()
	ok.text = "확인"
	ok.custom_minimum_size = Vector2(0, 76)
	ok.add_theme_font_size_override("font_size", 30)
	UiKit.apply_button(ok, MainHud.ACCENT, 14.0)
	ok.pressed.connect(leave)
	_result_box.add_child(ok)
	_result_layer.visible = true


func _label(text: String, fs: int, color: Color, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(560, 0)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 앱이 전투 중에 끝나면(트리가 이 노드를 지운다) 트리 밖에 둔 성 월드도 지운다(누수 방지 — dungeon.gd와 같다).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(main) and main._dungeon == self and not main.is_inside_tree():
		main.free()


## [확인]: 성 전장으로 돌아간다(길드 창은 그대로 열려 있다).
func leave() -> void:
	if _leaving:
		return
	_leaving = true
	if main != null:
		main.leave_dungeon.call_deferred()
	else:
		queue_free()

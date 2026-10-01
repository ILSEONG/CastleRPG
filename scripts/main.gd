extends Node3D
## 월드 조립. 씬 파일은 이것 하나. 나머지는 코드로 생성.
## 개발용 auto-stage: 네이티브는 유저 인자 `-- --auto-stage`, 웹은 URL에 `?auto-stage` → 시작 즉시 스테이지 진행.
## 온라인 모드(Net.is_online())면 "서버 연결 중…" 화면을 띄우고 접속(로그인·gamedata·player)을 마친 뒤 월드를 만든다 —
## 영웅·몬스터·스테이지가 서버 값으로 시작한다. 오프라인은 바로 만든다.
## 영웅은 배치(GameState.deploy·hero_copies·hero_level)대로 만들고, 배치·별·레벨이 바뀌면 다음 리필 때(방치 모드면 곧바로) 바뀐 슬롯만 다시 만든다.
## 개발용 `-- --heroes=id1,id2`(웹 `?heroes=id1,id2`): 디버그·오프라인에서만 그 영웅들을 주고 이번 실행의 배치로 쓴다(저장 안 함).
## 건물 완료(개정 12, Economy.building_done): 성채·성문 → 성·성문 최대 HP(GameState.apply_levels), 막사·연구소 → 영웅 능력치(방치면 곧바로,
## 아니면 다음 리필). 성채가 단계를 넘어 성 내부·영웅 슬롯이 바뀌면 "성이 넓어졌습니다!" 알림 후 다음 방치 시점(지금 방치면 즉시)에
## 월드를 다시 만든다(씬 다시 읽기 — 상태는 오토로드 Economy·GameState·Net에 있어 그대로 이어진다).

const Balance := preload("res://scripts/balance.gd")
const GameData := preload("res://scripts/game_data.gd")
const CastleScript := preload("res://scripts/castle.gd")
const BuildingsScript := preload("res://scripts/buildings.gd")
const CameraRigScript := preload("res://scripts/camera_rig.gd")
const FormationScript := preload("res://scripts/formation.gd")
const HeroScript := preload("res://scripts/hero.gd")
const PickerScript := preload("res://scripts/unit_picker.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")
const HudScript := preload("res://scripts/hud.gd")
const UiKit := preload("res://scripts/ui_kit.gd")
const HpBarsScript := preload("res://scripts/hp_bars.gd")
const DamageNumbersScript := preload("res://scripts/damage_numbers.gd")
const BadgesScript := preload("res://scripts/badges.gd")
const MerchantPanelScript := preload("res://scripts/merchant_panel.gd")
const RecruitPanelScript := preload("res://scripts/recruit_panel.gd")
const HeroPanelScript := preload("res://scripts/hero_panel.gd")
const TabBarScript := preload("res://scripts/tab_bar.gd")
const GroundShader := preload("res://shaders/ground_grid.gdshader")
const EXPANDED_TEXT := "성이 넓어졌습니다!"

static var rebuilds := 0  # 월드를 다시 만든 횟수(성채 단계 변경). 개발용 1회 설정(econ-demo·--heroes·auto-stage)은 첫 월드에서만
static var _expanded_notice := false  # 방치 중 단계가 바뀌어 곧바로 다시 만들었다 — 새 월드에서 알린다(옛 HUD는 사라진다)

var camera: Camera3D
var castle

var _formation
var _picker
var _slots := {}  # 배치 슬롯 i → {node: 영웅, key: [영웅 id, copies, level, 막사, 연구소]}(만들 때 값)
var _built_slots := 0  # 이 월드를 만들 때의 영웅 슬롯 수(성채 단계)
var _expand_pending := false  # 성채 단계가 바뀌어 다음 방치 시점에 월드를 다시 만든다


func _ready() -> void:
	GameState.roster = Economy  # 영웅 보유·배치·건물 레벨 공급자
	if Net.is_online() and not Net.ready_once:
		await _wait_for_server()
	_build_world()


func _build_world() -> void:
	_build_environment()
	castle = CastleScript.new()
	add_child(castle)
	_build_ground(castle.half)
	var scenery = BuildingsScript.new()
	scenery.half = castle.half
	add_child(scenery)
	var rig = CameraRigScript.new()
	add_child(rig)
	camera = rig.camera
	var bars = HpBarsScript.new()
	bars.camera = camera
	add_child(bars)
	var numbers = DamageNumbersScript.new()
	numbers.camera = camera
	add_child(numbers)
	var badges = BadgesScript.new()
	badges.camera = camera
	add_child(badges)
	_formation = FormationScript.new()
	if rebuilds == 0 and OS.is_debug_build() and _flag_requested("econ-demo") and not Net.is_online():
		_econ_demo()  # --heroes보다 먼저: Economy.reset이 개발용 영웅 보유·배치를 지우지 않게
	if rebuilds == 0:
		_apply_dev_heroes()
	_built_slots = GameState.hero_count()
	_sync_heroes()
	var picker = PickerScript.new()
	picker.camera = camera
	picker.badges = badges
	add_child(picker)
	_picker = picker
	var spawner = SpawnerScript.new()
	spawner.castle = castle
	add_child(spawner)
	var hud = HudScript.new()
	add_child(hud)
	var panel = MerchantPanelScript.new()
	add_child(panel)
	picker.panel = panel
	var recruit = RecruitPanelScript.new()
	add_child(recruit)
	picker.recruit = recruit
	var hero_panel = HeroPanelScript.new()
	add_child(hero_panel)
	var tabs = TabBarScript.new()  # 하단 탭 바(개정 11): 성·영웅·모집·상인
	tabs.windows = {"hero": hero_panel, "recruit": recruit, "merchant": panel}
	add_child(tabs)
	GameState.refilled.connect(_sync_heroes)  # 다음 리필(스테이지 사이) 때 배치·별·막사·연구소 반영
	Economy.roster_changed.connect(_on_roster_changed)
	Economy.building_done.connect(_on_building_done)
	GameState.mode_changed.connect(_on_mode_changed)
	if OS.is_debug_build() and rebuilds == 0:
		_connect_dev_log()  # 람다(오토로드 시그널)라 다시 만든 월드에서 또 붙이면 두 번 찍힌다
	if _expanded_notice:
		_expanded_notice = false
		Economy.notice.emit(EXPANDED_TEXT)
	if rebuilds == 0 and _auto_stage_requested():
		Economy.save_path = ""  # 개발 실행은 실제 저장 파일을 건드리지 않는다
		seed(1)  # 스폰 흩어짐 고정 → E2E 로그 재현
		GameState.start_stage()


## 접속 화면(HUD 스타일: 하늘색 바탕 + 둥근 흰 패널). 첫 접속을 마치면 치운다. 실패는 Net이 계속 다시 시도한다.
## 웹 저장소가 영구가 아니면 경고 한 줄을 더한다(접속은 그대로 진행).
func _wait_for_server() -> void:
	var layer := CanvasLayer.new()
	var back := ColorRect.new()
	back.color = Color(0.86, 0.91, 0.96)  # 월드 배경색
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(back)
	var box := PanelContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_stylebox_override("panel", UiKit.panel(HudScript.PANEL_BG, 16.0, 28))
	back.add_child(box)
	var lines := VBoxContainer.new()
	box.add_child(lines)
	var label := Label.new()
	label.text = "서버 연결 중…"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_color", HudScript.INK)
	lines.add_child(label)
	if not Net.storage_persistent:
		var warn := Label.new()
		warn.text = Net.STORAGE_TEXT
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.custom_minimum_size = Vector2(520, 0)
		warn.add_theme_font_size_override("font_size", 22)
		warn.add_theme_color_override("font_color", HudScript.INK)
		lines.add_child(warn)
	add_child(layer)
	Net.start()
	if not Net.ready_once:
		await Net.connected
	layer.queue_free()


## 배치(GameState.deploy)·별(copies)·레벨을 만들어 둔 영웅에 맞춘다. 바뀐 슬롯만 빼고 다시 만든다(나머지는 그대로).
func _sync_heroes() -> void:
	var deploy: Array = GameState.deploy()  # 슬롯 i → 영웅 id 또는 null(빈 슬롯)
	for i in _slots.keys():
		if i >= deploy.size():
			_retire(i)
	for i in deploy.size():
		var id = deploy[i]
		var key := [id, GameState.hero_copies(id) if id != null else 0, GameState.hero_level(id) if id != null else 0,
			GameState.building_level(GameData.BARRACKS), GameState.building_level(GameData.LAB)]
		if _slots.has(i) and _slots[i].key == key:
			continue
		_retire(i)
		if id == null or GameData.hero(id).is_empty():
			continue
		var hero = HeroScript.new()
		hero.setup(i, GameData.hero(id), castle, _formation, key[1], key[2])
		add_child(hero)
		_slots[i] = {"node": hero, "key": key}


func _retire(i: int) -> void:
	if not _slots.has(i):
		return
	var h = _slots[i].node
	_slots.erase(i)
	if _picker != null and _picker.selected == h:
		_picker._select(null)
	h.retire()


## 방치 모드(대기)면 배치·별 변경을 곧바로 반영한다. 스테이지 중이면 다음 리필 때.
## 바뀐 슬롯의 영웅은 새로 만들어 HP가 가득 찬다(방치 모드의 공짜 회복이지만 해는 없다 — 스테이지 중에는 리필까지 기다린다).
func _on_roster_changed() -> void:
	if GameState.mode == GameState.Mode.IDLE:
		_sync_heroes()


## 건설 완료(개정 12): 성채·성문 → 최대 HP. 막사·연구소 → 영웅 능력치(방치면 곧바로 다시 만들고, 아니면 다음 리필에 _sync_heroes가 key로
## 알아챈다). 성채가 단계를 넘어 성 내부·슬롯 수가 이 월드와 달라지면 월드를 다시 만든다(_expand).
func _on_building_done(id: String, level: int) -> void:
	if id == GameData.KEEP or id == GameData.GATE:
		GameState.apply_levels()
	if (id == GameData.BARRACKS or id == GameData.LAB) and GameState.mode == GameState.Mode.IDLE:
		_sync_heroes()
	if id == GameData.KEEP and (GameData.interior_half(level) != castle.half or GameData.hero_slots(level) != _built_slots):
		_expand()


## 성이 넓어졌다: 방치면 곧바로 다시 만들고 새 월드에서 알린다. 아니면 지금 알리고 방치로 돌아올 때(_on_mode_changed) 다시 만든다.
func _expand() -> void:
	if _expand_pending:
		return
	_expand_pending = true
	if GameState.mode == GameState.Mode.IDLE:
		_expanded_notice = true
		_rebuild_world.call_deferred()
	else:
		Economy.notice.emit(EXPANDED_TEXT)


func _on_mode_changed(mode: int) -> void:
	if _expand_pending and mode == GameState.Mode.IDLE:
		_rebuild_world.call_deferred()


## 월드를 다시 만든다(씬 다시 읽기). 상태는 오토로드(Economy·GameState·Net)에 있어 그대로 이어지고, 새 main이 그 레벨로 성·영웅을 만든다.
## 테스트 하네스처럼 main이 현재 씬이 아니라 자식으로 붙어 있으면 같은 자리에서 새 인스턴스로 바꿔 끼운다.
func _rebuild_world() -> void:
	if not _expand_pending or not is_inside_tree():
		return  # 이미 다시 만드는 중(같은 프레임에 두 번 불림)
	_expand_pending = false
	rebuilds += 1
	var tree := get_tree()
	if tree.current_scene == self:
		tree.reload_current_scene()
		return
	var parent := get_parent()
	var fresh = load(scene_file_path).instantiate()
	parent.remove_child(self)
	queue_free()
	parent.add_child(fresh)


## 개발용 --heroes=id1,id2(웹 ?heroes=): 디버그·오프라인에서만. 모르는 id는 경고하고 건너뛴다. 저장 파일은 쓰지 않는다.
func _apply_dev_heroes() -> void:
	var arg := Net.arg_value("heroes")
	if arg != "" and OS.is_debug_build() and not Net.is_online():
		print("[heroes] %s" % [Economy.grant_dev_heroes(Array(arg.split(",", false)))])


func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.86, 0.91, 0.96)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.78, 0.80, 0.86)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL  # 분할 없음: 모바일 부담 최소
	sun.directional_shadow_max_distance = 220.0
	add_child(sun)
	sun.rotation_degrees = Vector3(-50, -45, 0)  # 카메라(요 45°) 시선을 가로지르게 → 그림자가 화면 오른쪽 바닥에 드리운다


## 바닥은 픽셀 셰이더 평면 한 장이라 크기는 공짜 — 카메라가 보여 줄 수 있는 곳을 다 덮는다: 팬 한계 + 최대 줌아웃에서
## 19.5:9 세로 화면이 비추는 바닥 직사각형(가로 반폭 w, 세로는 1/sin(피치)로 늘어난 h)의 대각선 반(요와 무관하게 덮는다).
func _build_ground(interior_half: float) -> void:
	var w := Balance.CAMERA_SIZE_MAX / 2.0
	var h := w * 19.5 / 9.0 / sin(deg_to_rad(-CameraRigScript.PITCH_DEG))
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (Balance.MAP_HALF - CameraRigScript.PAN_LIMIT_MARGIN + Vector2(w, h).length()) * 2.0
	var mat := ShaderMaterial.new()
	mat.shader = GroundShader
	mat.set_shader_parameter("tile_size", Balance.TILE)
	mat.set_shader_parameter("interior_half", interior_half)
	mat.set_shader_parameter("road_half", Balance.TILE)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _connect_dev_log() -> void:
	GameState.mode_changed.connect(func(m): print("[mode] %d stage=%d" % [m, GameState.stage]))
	GameState.stage_cleared.connect(func(s): print("[cleared] %d" % s))
	GameState.stage_failed.connect(func(s): print("[failed] %d" % s))


func _auto_stage_requested() -> bool:
	return _flag_requested("auto-stage")


## 네이티브는 유저 인자 `-- --flag`, 웹은 URL `?flag`.
func _flag_requested(flag: String) -> bool:
	if OS.get_cmdline_user_args().has("--" + flag):
		return true
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("window.location.search")).contains(flag)
	return false


## 개발용: 저장 안 함, 마지막 수집 30분 전, 자원 각 500, 골드 9999(10연차 확인용). 영웅을 만들기 전(_build_world 앞부분)에
## 불러 --heroes(_apply_dev_heroes)가 그 뒤에 보유·배치를 덮게 한다.
func _econ_demo() -> void:
	var now := Time.get_unix_time_from_system()
	Economy.save_path = ""
	Economy.reset(now)
	for b in Economy.last_collect:
		Economy.last_collect[b] = now - 1800.0
	for id in Economy.res:
		Economy.res[id] = 500
	Economy.gold = 9999
	Economy.changed.emit()
	print("[econ-demo] gold 9999, resources 500")

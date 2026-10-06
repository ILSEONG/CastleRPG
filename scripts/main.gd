extends Node3D
## 월드 조립. 씬 파일은 이것 하나. 나머지는 코드로 생성.
## 개발용 auto-stage: 네이티브는 유저 인자 `-- --auto-stage`, 웹은 URL에 `?auto-stage` → 시작 즉시 스테이지 진행.
## 온라인 모드(Net.is_online())면 저장한 로그인 방식(Net.load_auth)이 없을 때 로그인 화면(login_screen.gd — Google·카카오·네이버·게스트)을
## 먼저 띄우고, 그다음 로딩 화면(preloader.gd, 서버 연결 단계)을 띄우고 접속(로그인·gamedata·player)을 마친 뒤 월드를 만든다 — 같은 로딩 화면이
## 이어서 리소스를 불러온다(로딩 화면은 하나). 접속 중 저장한 소셜 세션이
## 거절되면 로그인 화면으로 돌아간다) —
## 영웅·몬스터·스테이지가 서버 값으로 시작한다. 오프라인은 바로 만든다.
## 영웅은 배치(GameState.deploy·hero_promotion·hero_level)대로 만들고, 배치·승급(별)·레벨이 바뀌면 다음 리필 때(방치 모드면 곧바로) 바뀐 슬롯만 다시 만든다.
## 개발용 `-- --heroes=id1,id2`(웹 `?heroes=id1,id2`): 디버그·오프라인에서만 그 영웅들을 주고 이번 실행의 배치로 쓴다(저장 안 함).
## 개발용 `-- --debug-win`(웹 `?debug-win`, 개정 18): 디버그 빌드에서 Economy.debug_win_on — 던전 장면이 도전을 곧바로 승리로 끝낸다(Economy.debug_win).
## 개발용 `-- --season=N`(웹 `?season=N`, N 0~3, 개정 22): 디버그 빌드에서 그 계절로 시작(seasons.gd).
## 건물 완료(개정 12, Economy.building_done): 성채·성문 → 성·성문 최대 HP(GameState.apply_levels). 연구 완료(개정 24, Economy.research_done) →
## 성·성문 최대 HP(같은 비율로, apply_levels(true)) — 영웅·병사 능력치는 각자 research_changed로 곧바로 다시 읽는다. 성채가 단계를 넘어 성 내부·영웅 슬롯이 바뀌면 "성이 넓어졌습니다!" 알림 후 다음 방치 시점(지금 방치면 즉시)에
## 월드를 다시 만든다(씬 다시 읽기 — 상태는 오토로드 Economy·GameState·Net에 있어 그대로 이어진다).
## 병사(개정 21 §1): 방치 모드에는 없다. 스테이지가 시작되면(GameState.Mode.STAGE) 병사 배치(Economy.soldier_deploy)대로 성채 정문 앞
## 광장(Formation.soldier_spots)에 등장시키고 역할 자리(SoldierCommand.assign_posts)로 보낸다. 리필 때는 스테이지 시작 자리로 되돌리고
## (연속 진행이면 그대로 다음 스테이지 — 배치가 바뀌었으면 그때 다시 만든다), 방치로 돌아가면 사라진다. 지원 판단은 SoldierCommand 하나.
## 던전(개정 18): Economy.dungeon_started → 이 월드를 트리에서 떼어 두고 던전 장면(dungeon.gd)을 붙인다(_enter_dungeon), [나가기] → leave_dungeon.
## 개발용 `-- --dungeon=gold|equip|ticket`(웹 `?dungeon=`): 디버그·오프라인에서 곧바로 그 던전 1단계(_dev_dungeon).

const Balance := preload("res://scripts/balance.gd")
const GameData := preload("res://scripts/game_data.gd")
const Art := preload("res://scripts/art.gd")
const CastleScript := preload("res://scripts/castle.gd")
const BuildingsScript := preload("res://scripts/buildings.gd")
const CameraRigScript := preload("res://scripts/camera_rig.gd")
const FormationScript := preload("res://scripts/formation.gd")
const HeroScript := preload("res://scripts/hero.gd")
const SoldierScript := preload("res://scripts/soldier.gd")
const SoldierCommandScript := preload("res://scripts/soldier_command.gd")
const PickerScript := preload("res://scripts/unit_picker.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")
const HudScript := preload("res://scripts/hud.gd")
const UiKit := preload("res://scripts/ui_kit.gd")
const HpBarsScript := preload("res://scripts/hp_bars.gd")
const DamageNumbersScript := preload("res://scripts/damage_numbers.gd")
const BadgesScript := preload("res://scripts/badges.gd")
const WorldTagsScript := preload("res://scripts/world_tags.gd")
const MerchantPanelScript := preload("res://scripts/merchant_panel.gd")
const RecruitPanelScript := preload("res://scripts/recruit_panel.gd")
const HeroPanelScript := preload("res://scripts/hero_panel.gd")
const TabBarScript := preload("res://scripts/tab_bar.gd")
const BuildingPanelScript := preload("res://scripts/building_panel.gd")
const SoldierPanelScript := preload("res://scripts/soldier_panel.gd")
const GrowthPanelScript := preload("res://scripts/growth_panel.gd")
const ResearchPanelScript := preload("res://scripts/research_panel.gd")
const OfflinePanelScript := preload("res://scripts/offline_panel.gd")
const LoginScreenScript := preload("res://scripts/login_screen.gd")
const PreloaderScript := preload("res://scripts/preloader.gd")
var _loading = null  # 로딩 화면(온라인: 서버 연결부터, 첫 월드에서 begin()으로 이어서 불러온다)
const GroundShader := preload("res://shaders/ground_grid.gdshader")
const SeasonsScript := preload("res://scripts/seasons.gd")
const GATE_PAN_SEC := 0.4  # HUD 성문 막대 탭 → 카메라가 그 성문으로 옮겨 가는 시간
const EXPANDED_TEXT := "성이 넓어졌습니다!"

static var rebuilds := 0  # 월드를 다시 만든 횟수(성채 단계 변경). 개발용 1회 설정(econ-demo·--heroes·auto-stage)은 첫 월드에서만
static var _expanded_notice := false
static var _scaling_hooked := false  # 3D 해상도 맞추기를 루트 창 크기 변화에 한 번만 잇는다
const RENDER_3D_WIDTH := 720.0  # 3D는 가로 이만큼(논리 화면 폭)의 픽셀로 그린다 — 고해상도 폰의 픽셀 부담을 줄인다(UI는 원래 해상도)
const RENDER_3D_MIN := 0.5  # 방치 중 단계가 바뀌어 곧바로 다시 만들었다 — 새 월드에서 알린다(옛 HUD는 사라진다)

var camera: Camera3D
var castle

var _formation
var _hero_snap := {}  # 스테이지 시작 때 영웅 자리: 영웅 id → {side, post, slot, free_pos}(다시 만든 영웅도 찾게 id로)
var _picker
var _slots := {}  # 배치 슬롯 i → {node: 영웅, key: [영웅 id, 승급, level, 장비]}(만들 때 값)
var soldiers: Array = []  # 이번 스테이지 병사 노드(개정 21 — 스테이지 동안만)
var command  # 전술 지휘관(soldier_command.gd)
var _soldier_key = null  # 병사를 만들 때의 배치(연속 진행 중 바뀌면 다음 스테이지에 다시 만든다)
var _built_slots := 0  # 이 월드를 만들 때의 영웅 슬롯 수(성채 단계)
var _expand_pending := false  # 성채 단계가 바뀌어 다음 방치 시점에 월드를 다시 만든다
var _env: Environment  # 계절(개정 22)이 하늘·빛·바닥 색을 바꾼다
var _sun: DirectionalLight3D
var _ground_mat: ShaderMaterial
var _dungeon = null  # 던전 장면(개정 18, 던전 중에만). 그동안 이 노드는 트리 밖
var _host: Node = null  # 던전 동안 이 노드와 던전 장면의 부모
var _tutorial_ui := {}  # 튜토리얼 [바로가기]가 여는 것: rig·building(건물 창)·tabs·merchant(상인 창)·recruit(모집 창)


func _ready() -> void:
	_hook_3d_scaling()
	GameState.roster = Economy  # 영웅 보유·배치·건물 레벨 공급자
	if OS.is_debug_build() and not Net.is_online() and Net.arg_value("arena") != "":
		add_child(preload("res://scripts/arena_preview.gd").new())  # 개발용 던전 무대 미리보기(--arena=plains|castle, 개정 18)
		return
	if OS.is_debug_build() and not Net.is_online() and _flag_requested("lineup"):
		add_child(preload("res://scripts/hero_lineup.gd").new())  # 개발용 영웅 생김새 줄 세우기(--lineup, 개정 23)
		return
	if Net.is_online() and not Net.ready_once:
		await _connect_online()
	_build_world()


func _build_world() -> void:
	_build_environment()
	add_child(preload("res://scripts/portraits.gd").new())  # 영웅 피규어(개정 14 §2) — 카드(창)보다 먼저
	castle = CastleScript.new()
	add_child(castle)
	var crowd = preload("res://scripts/crowd.gd").new()  # 유닛 겹침 해소(성벽·성문·건물 부지 안 넘김)
	crowd.half = castle.half
	add_child(crowd)
	_build_ground(castle.half)
	var scenery = BuildingsScript.new()
	scenery.half = castle.half
	add_child(scenery)
	var rig = CameraRigScript.new()
	add_child(rig)
	camera = rig.camera
	var seasons = SeasonsScript.new()  # 개정 22 §4: 스테이지마다 계절(시작은 현재 스테이지 계절로 바로)
	seasons.setup(_env, _sun, _ground_mat, scenery, camera)
	add_child(seasons)
	var tags = WorldTagsScript.new()  # 건물·상인·문루 이름표(개정 15, 화면 공간) — HP 바·말풍선보다 아래 캔버스
	tags.camera = camera
	tags.scenery = scenery
	tags.castle = castle
	add_child(tags)
	var bars = HpBarsScript.new()
	bars.camera = camera
	add_child(bars)
	var numbers = DamageNumbersScript.new()
	numbers.camera = camera
	add_child(numbers)
	var badges = BadgesScript.new()
	badges.camera = camera
	badges.scenery = scenery  # 건설 진행 막대 자리
	badges.tags = tags  # 막대·말풍선은 이름표 위에 쌓는다
	tags.badges = badges  # 이름표 덩어리 = 이름표 + 막대·말풍선
	add_child(badges)
	_formation = FormationScript.new()
	if rebuilds == 0 and OS.is_debug_build() and _flag_requested("econ-demo") and not Net.is_online():
		_econ_demo()  # --heroes보다 먼저: Economy.reset이 개발용 영웅 보유·배치를 지우지 않게
	if rebuilds == 0:
		_apply_dev_heroes()
		Economy.debug_win_on = OS.is_debug_build() and _flag_requested("debug-win")  # 개정 18 테스트 훅: 던전 즉시 승리(Economy.debug_win)
	_built_slots = GameState.hero_count()
	_sync_heroes()
	command = SoldierCommandScript.new()
	command.castle = castle
	add_child(command)
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
	hud.gate_tapped.connect(func(side): rig.pan_to(FormationScript.gate_position(castle.half, side), GATE_PAN_SEC))  # 성문 막대 탭(개정 12-2 §2)
	var panel = MerchantPanelScript.new()
	add_child(panel)
	picker.panel = panel
	var recruit = RecruitPanelScript.new()
	add_child(recruit)
	picker.recruit = recruit
	var hero_panel = HeroPanelScript.new()
	add_child(hero_panel)
	var building_panel = BuildingPanelScript.new()  # 건물 창(개정 12 §2.5): 건물 탭·길게 누르기
	add_child(building_panel)
	picker.building_panel = building_panel
	var research_panel = ResearchPanelScript.new()  # 연구 창(개정 24): 연구소 건물 창 [연구]·플라스크 말풍선
	add_child(research_panel)
	building_panel.research = research_panel
	picker.research = research_panel
	var soldier_panel = SoldierPanelScript.new()
	add_child(soldier_panel)
	var growth_panel = GrowthPanelScript.new()  # 성장 시트(개정 20 §5)
	add_child(growth_panel)
	var bag = preload("res://scripts/bag_panel.gd").new()  # 개정 18 보관함·장비 고르기(층 4)
	var dungeon_panel = preload("res://scripts/dungeon_panel.gd").new()
	dungeon_panel.bag = bag
	hero_panel.bag = bag
	add_child(dungeon_panel)
	var guild_panel = preload("res://scripts/guild_panel.gd").new()  # 길드 시트
	add_child(guild_panel)
	var tabs = TabBarScript.new()  # 하단 탭 바(개정 18 §1): 성장·영웅·병사·던전·모집·길드(상인은 NPC 탭)
	tabs.windows = {"growth": growth_panel, "hero": hero_panel, "soldier": soldier_panel, "dungeon": dungeon_panel, "recruit": recruit, "guild": guild_panel}
	add_child(tabs)
	var card = preload("res://scripts/tutorial_card.gd").new()  # 튜토리얼 미션 카드(새 게임만, 탭 바 위)
	card.tags = tags
	add_child(card)
	_tutorial_ui = {"rig": rig, "building": building_panel, "tabs": tabs, "merchant": panel, "recruit": recruit}
	if not Tutorial.goto_requested.is_connected(_tutorial_goto):
		Tutorial.goto_requested.connect(_tutorial_goto)
	add_child(bag)
	add_child(OfflinePanelScript.new())  # 방치 보상 개요(앱을 껐다 켜면 — Economy.offline_reported)
	if not PreloaderScript.done:  # 첫 로딩 화면: 리소스·피규어·배너를 다 준비한 뒤 걷힌다(자리표시가 보였다 바뀌지 않게)
		if _loading != null and is_instance_valid(_loading):
			_loading.begin()  # 온라인: 서버 연결부터 보이던 같은 화면으로 이어서
		else:
			add_child(PreloaderScript.new())
	GameState.mode_changed.connect(_on_mode_for_snapshot)
	GameState.refilled.connect(_on_refilled)  # 스테이지 시작 자리 복원(영웅 id로, 다시 만든 영웅도) + 배치·승급·레벨·장비 반영
	GameState.refilled.connect(_reset_soldiers)
	Economy.roster_changed.connect(_on_roster_changed)
	Economy.building_done.connect(_on_building_done)
	Economy.research_done.connect(_on_research_done)
	Economy.dungeon_started.connect(_on_dungeon_started)
	GameState.mode_changed.connect(_on_mode_changed)
	if OS.is_debug_build() and rebuilds == 0:
		_connect_dev_log()  # 람다(오토로드 시그널)라 다시 만든 월드에서 또 붙이면 두 번 찍힌다
	if _expanded_notice:
		_expanded_notice = false
		Economy.notice.emit(EXPANDED_TEXT)
	if rebuilds == 0 and _auto_stage_requested():
		Economy.save_path = ""  # 개발 실행은 실제 저장 파일을 건드리지 않는다
		Fever.save_path = ""
		GameState.auto_continue = true  # 저장된 체크 해제 상태와 무관하게 E2E는 연속
		seed(1)  # 스폰 흩어짐 고정 → E2E 로그 재현
		GameState.start_stage()
	if rebuilds == 0 and OS.is_debug_build() and not Net.is_online() and Net.arg_value("dungeon") in GameData.DUNGEON_TYPES:
		_dev_dungeon(Net.arg_value("dungeon"))
	elif rebuilds == 0 and not _auto_stage_requested():
		Economy.claims_open = true
		Economy.claim_offline(GameState.stage)  # 앱을 켰다: 끈 동안의 방치 처치 골드(× offline_gold_mult) 정산 → 개요 창


## 튜토리얼 미션 카드 [바로가기](Tutorial.goto_requested): building:<id>(카메라를 그 건물로 옮기고 건물 창) · tab:<id>(하단 탭) ·
## merchant(상인 창) · recruit(모집 창 다이아 탭) · stage(방치 중이면 전투 시작).
func _tutorial_goto(target: String) -> void:
	if _tutorial_ui.is_empty() or not is_inside_tree():
		return
	var kind := target.get_slice(":", 0)
	var arg := target.get_slice(":", 1)
	match kind:
		"building":
			var b := Balance.building(arg)
			if not b.is_empty():
				_tutorial_ui.rig.pan_to(Vector3((b.cell.x + b.size.x / 2.0) * Balance.TILE, 0, (b.cell.y + b.size.y / 2.0) * Balance.TILE), GATE_PAN_SEC)
			elif arg == GameData.GATE:
				_tutorial_ui.rig.pan_to(FormationScript.gate_position(castle.half, 2), GATE_PAN_SEC)
			_tutorial_ui.building.open_building(arg)
		"tab":
			if not _tutorial_ui.tabs.windows[arg].is_open():
				_tutorial_ui.tabs.press(arg)
		"merchant":
			_tutorial_ui.merchant.open()
		"recruit":
			_tutorial_ui.recruit.set_currency(GameData.GACHA_DIA)
			if not _tutorial_ui.recruit.is_open():
				_tutorial_ui.tabs.press("recruit")
		"stage":
			if GameState.mode == GameState.Mode.IDLE:
				GameState.start_stage()


## 개발용 `-- --dungeon=gold|equip`(웹 `?dungeon=`, 디버그·오프라인): 저장 안 함, 출전 인원만큼 영웅을 채워(표 순서) 곧바로 1단계 던전.
## `--debug-win`과 함께면 결과 화면까지 바로 간다(캡처용).
func _dev_dungeon(type: String) -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	var need := GameData.party_size(type) + (1 if type == "ticket" else 0)  # 모집권 던전: 도우미가 내 영웅과 겹쳐도 4명이 남게
	for h in GameData.heroes():
		if Economy.heroes.size() >= need:
			break
		Economy.heroes[h.id] = maxi(1, int(Economy.heroes.get(h.id, 0)))
	var hs: Array = Economy.helper_candidates() if type == "ticket" else []  # 모집권 던전: 첫 도우미 후보
	var helper: String = hs[0].hero_id if not hs.is_empty() else ""
	var party: Array = Economy.default_party(type)
	if helper != "":
		party = Economy.default_party("gold").filter(func(x): return x != helper).slice(0, GameData.party_size(type))
	Economy.start_dungeon(type, 1, party, helper)


# --- 던전 장면 전환(개정 18 §9): 성 월드(이 노드)를 트리에서 떼어 두고 던전 장면을 같은 부모에 붙인다. 오토로드는 그대로,
# GameState 처리를 멈춰 성 스테이지 흐름(결과·카운트다운 타이머)도 멈춘다. 방치 진행(수집·훈련)은 시각 기반이라 그대로 흐른다.
# 돌아오면 다시 붙이고 카메라·GameState를 되돌린다(스테이지 중이었으면 그 자리에서 이어진다).

func _on_dungeon_started(run: Dictionary) -> void:
	if not run.is_empty():
		_enter_dungeon.call_deferred(run)  # 버튼 입력 처리 중에 트리를 바꾸지 않게


func _enter_dungeon(run: Dictionary) -> void:
	var d = preload("res://scripts/dungeon.gd").new()
	d.run = run
	d.main = self
	if _dungeon != null:  # 결과 화면에서 다음 도전: 던전 장면만 새로
		_host.remove_child(_dungeon)
		_dungeon.queue_free()
	elif is_inside_tree():
		_host = get_parent()
		GameState.process_mode = Node.PROCESS_MODE_DISABLED
		_host.remove_child(self)
	else:
		return
	_dungeon = d
	_host.add_child(d)


func leave_dungeon() -> void:
	if _dungeon == null:
		return
	_host.remove_child(_dungeon)
	_dungeon.queue_free()
	_dungeon = null
	_host.add_child(self)
	GameState.process_mode = Node.PROCESS_MODE_INHERIT
	camera.make_current()
	_on_mode_changed(GameState.mode)  # 던전 동안 성이 넓어졌으면 지금 다시 만든다


## 접속 화면(HUD 스타일: 하늘색 바탕 + 둥근 흰 패널). 첫 접속을 마치면 치운다. 실패는 Net이 계속 다시 시도한다.
## 웹 저장소가 영구가 아니면 경고 한 줄을 더한다(접속은 그대로 진행).
## 3D 해상도: 루트 뷰포트 3D를 가로 RENDER_3D_WIDTH 픽셀 정도로 그리고 늘려 보인다(쌍선형, Compatibility 렌더러도 된다).
## 1080×2400 폰이면 0.67배 — 바닥 셰이더·로우폴리 법선·그림자 필터 같은 픽셀 일이 2배 넘게 준다. UI(캔버스)는 원래 해상도 그대로.
## 던전 장면도 같은 루트 뷰포트라 함께 적용된다. 창 크기가 바뀌면(웹 창 조절) 다시 맞춘다. 카툰 외곽선 두께도 이 3D 높이에 맞춘다.
func _hook_3d_scaling() -> void:
	var root := get_tree().root
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = scale_3d_for(root.size.x)
	Art.toon_view_height(root.size.y * root.scaling_3d_scale)  # 카툰 외곽선 두께(3D 픽셀)
	if not _scaling_hooked:
		_scaling_hooked = true
		root.size_changed.connect(func():
			root.scaling_3d_scale = scale_3d_for(root.size.x)
			Art.toon_view_height(root.size.y * root.scaling_3d_scale))


## 창 가로 픽셀 → 3D 배율(RENDER_3D_MIN..1).
static func scale_3d_for(width_px: int) -> float:
	return clampf(RENDER_3D_WIDTH / maxf(1.0, width_px), RENDER_3D_MIN, 1.0)


## 로그인(필요하면 로그인 화면) → 접속. 저장한 소셜 세션이 거절되면(Net.session_lost) 로그인 화면부터 다시.
func _connect_online() -> void:
	Economy.claims_open = false  # 첫 월드에서 연다(_build_world)
	Net.load_auth()
	while true:
		if not Net.has_credentials():
			var screen = LoginScreenScript.new()
			add_child(screen)
			await screen.logged_in
			screen.queue_free()
		if await _wait_for_server():
			return


signal _server_waited(ok: bool)


## 로딩 화면(서버 연결 단계)을 띄우고 접속을 기다린다. 접속했으면 true(화면은 남아 월드를 만들 때 이어서 불러온다),
## 세션이 거절됐으면 false(화면을 걷고 로그인 화면으로).
func _wait_for_server() -> bool:
	if _loading == null or not is_instance_valid(_loading):
		_loading = PreloaderScript.new()
		_loading.connecting = true
		add_child(_loading)
	var up := func(): _server_waited.emit(true)
	var lost := func(): _server_waited.emit(false)
	Net.connected.connect(up)
	Net.session_lost.connect(lost)
	Net.start()
	var ok: bool = true if Net.ready_once else await _server_waited
	Net.connected.disconnect(up)
	Net.session_lost.disconnect(lost)
	if not ok and is_instance_valid(_loading):
		_loading.queue_free()
		_loading = null
	return ok


## 배치(GameState.deploy)·승급·레벨을 만들어 둔 영웅에 맞춘다. 바뀐 슬롯만 빼고 다시 만든다(나머지는 그대로).
## snap(리필 때 스테이지 시작 자리, 영웅 id → 자리)에 있는 영웅을 다시 만들면 그 자리에 세운다.
func _sync_heroes(snap := {}) -> void:
	var deploy: Array = GameState.deploy()  # 슬롯 i → 영웅 id 또는 null(빈 슬롯)
	for i in _slots.keys():
		if i >= deploy.size():
			_retire(i)
	for i in deploy.size():
		var id = deploy[i]
		var key := [id, GameState.hero_promotion(id) if id != null else 0, GameState.hero_level(id) if id != null else 0,
			Economy.equipment_bonus(id) if id != null else {}]  # 개정 18: 장비가 바뀌면 다시 만든다
		if _slots.has(i) and _slots[i].key == key:
			continue
		_retire(i)
		if id == null or GameData.hero(id).is_empty():
			continue
		var hero = HeroScript.new()
		hero.setup(i, GameData.hero(id), castle, _formation, key[1], key[2])
		if snap.has(id):
			_put_post(hero, snap[id])  # 스테이지 중 레벨·승급·장비가 바뀌어 다시 만든 영웅도 시작 자리로
		add_child(hero)
		_slots[i] = {"node": hero, "key": key}


## 스테이지 시작 때 영웅 자리 기록, 그 스테이지를 끝내는 리필에서 복원(start_stage의 리필은 기록이 없어 건너뜀).
func _on_mode_for_snapshot(mode: int) -> void:
	if mode != GameState.Mode.STAGE:
		return
	_hero_snap.clear()
	for i in _slots:
		var h = _slots[i].node
		_hero_snap[h.def.id] = {"side": h.side, "post": h.post, "slot": h.slot, "free_pos": h.free_pos}


## 리필: 기록이 있으면(스테이지를 끝내는 리필) 남은 영웅을 시작 자리로 되돌린 뒤 바뀐 슬롯을 다시 만든다 — 다시 만든 영웅도 같은 기록으로.
func _on_refilled() -> void:
	var snap := _hero_snap
	_hero_snap = {}
	_restore_hero_posts(snap)
	_sync_heroes(snap)


func _restore_hero_posts(snap: Dictionary) -> void:
	var back := []
	for i in _slots:
		var h = _slots[i].node
		if snap.has(h.def.id):
			_formation.release(i)  # 전부 먼저 풀어야 서로 바꾼 칸도 겹치지 않는다
			back.append(h)
	for h in back:
		_put_post(h, snap[h.def.id])
		h.reset()  # 자리로 순간이동 + 체력 회복


## 영웅 h에 스테이지 시작 자리 e를 준다. 다른 영웅이 그 칸을 쥐고 있으면(그 사이 배치가 바뀌었다) 지금 자리 그대로.
func _put_post(h, e: Dictionary) -> void:
	if e.post != FormationScript.POST_FREE:
		for j in _slots:
			var a: Dictionary = _formation.assignment(j)
			if j != h.index and a.get("side") == e.side and a.get("post") == e.post and a.get("slot") == e.slot:
				return
		_formation.restore(h.index, e.side, e.post, e.slot)
	else:
		_formation.release(h.index)
	h.side = e.side
	h.post = e.post
	h.slot = e.slot
	h.free_pos = e.free_pos


func _retire(i: int) -> void:
	if not _slots.has(i):
		return
	var h = _slots[i].node
	_slots.erase(i)
	if _picker != null and _picker.selected == h:
		_picker._select(null)
	h.retire()


## 스테이지 시작: 병사 배치(Economy.soldier_deploy)대로 광장에 등장시킨다. 연속 진행으로 이미 서 있고 배치도 같으면 그대로 둔다.
func spawn_soldiers() -> void:
	var d: Dictionary = Economy.soldier_deploy()
	if not soldiers.is_empty() and d == _soldier_key:
		return
	clear_soldiers()
	_soldier_key = d
	var units := []
	for k in d:
		var p: Array = Economy.parse_soldier_key(k)
		if not p.is_empty():
			for i in int(d[k]):
				units.append({"type": p[0], "tier": p[1]})
	var spots: Array = FormationScript.soldier_spots(units)
	var posts: Array = SoldierCommandScript.assign_posts(units)
	for i in units.size():
		if spots[i] == null:
			continue  # 66칸을 넘는 배치(인구 상한이 막는다)
		var s = SoldierScript.new()
		s.setup(units[i].type, units[i].tier, posts[i].side, posts[i].slot, spots[i], castle)
		add_child(s)
		soldiers.append(s)


## 방치로 돌아감: 병사가 사라진다.
func clear_soldiers() -> void:
	for s in soldiers:
		if is_instance_valid(s):
			s.vanish()
	soldiers.clear()


## 리필: 스테이지 시작 자리로 되돌린다(연속 진행 클리어면 그대로 다음 스테이지까지 서 있고, 방치로 가면 곧이어 사라진다).
func _reset_soldiers() -> void:
	for s in soldiers:
		if is_instance_valid(s):
			s.reset()


## 방치 모드(대기)면 배치·승급·레벨 변경을 곧바로 반영한다. 스테이지 중이면 다음 리필 때.
## 바뀐 슬롯의 영웅은 새로 만들어 HP가 가득 찬다(방치 모드의 공짜 회복이지만 해는 없다 — 스테이지 중에는 리필까지 기다린다).
func _on_roster_changed() -> void:
	if GameState.mode == GameState.Mode.IDLE:
		_sync_heroes()


## 건설 완료(개정 12): 성채·성문 → 최대 HP(개정 13: 막사는 영웅 HP를 올리지 않는다, 개정 24: 연구소는 영웅 공격을 올리지 않는다).
## 성채가 단계를 넘어 성 내부·슬롯 수가 이 월드와 달라지면 월드를 다시 만든다(_expand).
func _on_building_done(id: String, level: int) -> void:
	if id == GameData.KEEP or id == GameData.GATE:
		GameState.apply_levels()
	if id == GameData.KEEP and (GameData.interior_half(level) != castle.half or GameData.hero_slots(level) != _built_slots):
		_expand()


## 연구 완료(개정 24 §2): 성벽·성문 보강은 최대 HP를 올리고 지금 HP는 같은 비율로(다른 연구면 그대로 — 비율 1).
func _on_research_done(_id: String, _level: int) -> void:
	GameState.apply_levels(true)


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
	if mode == GameState.Mode.STAGE:
		spawn_soldiers()
	elif mode == GameState.Mode.IDLE:
		clear_soldiers()
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
	_env = e
	var sun := DirectionalLight3D.new()
	_sun = sun
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
	_ground_mat = mat
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


## 개발용: 저장 안 함, 마지막 수집 30분 전, 자원 각 500, 골드 30,000(10연차 확인용), 다이아 3,000(개정 23). 영웅을 만들기 전(_build_world 앞부분)에
## 불러 --heroes(_apply_dev_heroes)가 그 뒤에 보유·배치를 덮게 한다.
func _econ_demo() -> void:
	var now := Time.get_unix_time_from_system()
	Economy.save_path = ""
	Economy.reset(now)
	for b in Economy.last_collect:
		Economy.last_collect[b] = now - 1800.0
	for id in Economy.res:
		Economy.res[id] = 500
	Economy.gold = 30000  # 10연차(골드 Lv 1 27,000) 한 번
	Economy.diamonds = 3000  # 개정 23: 다이아 모집·상점 캡처용(실결제 전)
	Economy.soldiers = {"infantry:1": 7, "infantry:2": 2, "archer:1": 5, "cavalry:1": 3}  # 병사 탭·[합성] 캡처용(훈련은 1마리 3시간)
	Economy.hero_shards = {"hans": 7, "ella": 3}  # 승급 캡처용(개정 15): 한스는 승급 가능(7 / 5), 엘라는 3 / 5
	Economy.hero_promotions = {"nina": 2}  # 금색 별 2개
	Economy.changed.emit()
	Economy.soldiers_changed.emit()
	Economy.roster_changed.emit()
	print("[econ-demo] gold 30000, diamonds 3000, resources 500, soldiers 17, shards hans 7 / ella 3, nina promotion 2")

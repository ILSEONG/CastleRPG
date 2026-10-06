extends CanvasLayer
## 첫 로딩 화면(하나뿐): 게임이 처음 보이기 전에 정적 리소스를 한 번에 준비해, 배너·그림·피규어가 자리표시로 보였다가 바뀌지 않게 한다.
## 온라인이면 서버 연결 단계부터 같은 화면이다(connecting — main이 접속 전에 붙이고, 막대 앞 CONNECT_SHARE를 로그인·gamedata·player
## 응답에 맞춰 채운다). 월드를 만들면 main이 begin()을 불러 같은 화면·같은 막대로 이어서 불러온다. 오프라인은 main이 첫 월드를 만든 직후
## 붙이고 곧바로 불러온다(월드 위를 덮고 입력을 막는다). 불러오기 순서:
##  1) res://assets 아래 리소스 전부(모델 glb·gltf, 텍스처, 글꼴)를 스레드로 불러 _keep에 쥔다 — 처음 쓰는 순간 디스크에서 읽지 않게.
##  2) 피규어(Portraits): 모든 영웅 "hero:<id>"와 병종 "soldier:<id>" — 영웅·병사 카드, 말풍선, 던전 HUD가 쓴다.
##  3) 장면 스냅샷(SceneSnap): 던전 카드 띠 둘(골드·장비, 지금 출전 편성 — dungeon_panel과 같은 키), 모집 창 키 아트.
## 렌더링(2·3)은 처음 그릴 때 셰이더도 컴파일되어 그 뒤 첫 등장 모델이 멈칫하지 않는다. 다 되면(또는 TIMEOUT_SEC) 걷히고 finished.
## 헤드리스(렌더러 없음 — 테스트)는 아무것도 덮지 않고 곧바로 끝낸다(그림은 어차피 자리표시).

const GameData := preload("res://scripts/game_data.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")
const SceneSnap := preload("res://scripts/scene_snap.gd")
const DungeonSnaps := preload("res://scripts/dungeon_snaps.gd")
const RecruitArt := preload("res://scripts/recruit_art.gd")

signal finished

const SPLASH := preload("res://assets/ui/splash.png")
const ROOT := "res://assets"
const EXTS := ["glb", "gltf", "png", "jpg", "webp", "otf", "ttf"]
const TIMEOUT_SEC := 20.0
const FADE_SEC := 0.25
const DUNGEON_TYPES := ["gold", "equip"]  # dungeon_panel.TYPES
const DUNGEON_KEY := "dungeon_band:%s"  # dungeon_panel.SNAP_KEY
const CONNECT_TEXT := "서버에 연결하는 중…"
const LOAD_TEXT := "게임 데이터를 불러오는 중…"
const CONNECT_SHARE := 0.3  # 온라인: 막대에서 서버 연결 몫(나머지가 불러오기)
## 앱 아이콘 느낌(splash 그림과 같은 색): 글자는 흰색에 따뜻한 갈색 테두리, 막대는 크림 바탕·지붕 파랑 채움, 테두리는 각 색의 어두운 쪽
const TEXT_EDGE := Color(0.55, 0.27, 0.07)
const BAR_BACK := Color(1.0, 0.97, 0.9, 0.9)
const BAR_BACK_EDGE := Color(0.72, 0.42, 0.16)
const BAR_FILL := Color(0.25, 0.47, 0.8)
const BAR_FILL_EDGE := Color(0.14, 0.29, 0.54)

static var _keep: Array = []  # 불러 둔 리소스(쥐고 있어야 캐시에 남는다)
static var done := false  # 이번 실행에서 한 번 끝냈다(월드를 다시 만들 때는 다시 하지 않는다)

var bar: ProgressBar
var label: Label
var connecting := false  # add_child 전에 true: 서버 연결 단계부터 보이고, begin()을 부를 때까지 불러오지 않는다

var _started := false
var _base := 0.0  # 불러오기가 시작된 막대 비율(연결 몫)
var _steps := 0  # 서버 연결: 지난 단계 수(로그인·gamedata·player)
var _step_t := 0.0  # 그 단계에서 기다린 초(막대가 다음 단계 쪽으로 조금씩 나아간다)

var _paths: Array = []
var _loading: Array = []  # 아직 스레드로 불러오는 경로
var _portraits: Array = []
var _snaps: Array = []
var _t := 0.0
var _retry := 1.0
var _closing := false


func _ready() -> void:
	layer = 20
	if done or DisplayServer.get_name() == "headless":
		if not connecting:
			_finish.call_deferred(true)
		return
	_build_ui()
	if connecting:
		label.text = CONNECT_TEXT
		return
	begin()


## 불러오기 시작(연결 단계였으면 같은 화면·막대를 이어서). 이미 했으면 아무 일 없다. 헤드리스는 곧바로 끝낸다.
func begin() -> void:
	if _started or _closing:
		return
	_started = true
	if done or bar == null:
		_finish.call_deferred(true)
		return
	if connecting:  # 연결 몫은 다 찼다(월드를 만들 때 부른다)
		bar.value = maxf(bar.value, 100.0 * CONNECT_SHARE)
	_base = bar.value / 100.0
	label.text = LOAD_TEXT
	_paths = resource_paths(ROOT)
	for p in _paths:
		if ResourceLoader.load_threaded_request(p) == OK:
			_loading.append(p)
	for h in GameData.heroes():
		_portraits.append("hero:" + str(h.id))
	for s in GameData.soldiers():
		_portraits.append("soldier:" + str(s.id))
	for k in _portraits:
		PortraitsScript.portrait(k)  # 렌더를 줄 세운다(한 프레임에 하나)
	for t in DUNGEON_TYPES:
		_snaps.append(DUNGEON_KEY % t)
		SceneSnap.snap(DUNGEON_KEY % t, DungeonSnaps.SIZE, DungeonSnaps.build.bind(t, Economy.default_party(t)), DungeonSnaps.WARM)
	_snaps.append(RecruitArt.KEY)
	SceneSnap.snap(RecruitArt.KEY, RecruitArt.SIZE, RecruitArt.build, RecruitArt.WARM)


## dir 아래 리소스 경로 전부(하위 폴더 포함, EXTS만). 내보낸 빌드에서도 원래 이름으로 나온다(ResourceLoader.list_directory).
static func resource_paths(dir: String) -> Array:
	var out := []
	for name in ResourceLoader.list_directory(dir):
		var p := dir.path_join(name.trim_suffix("/"))
		if name.ends_with("/"):
			out.append_array(resource_paths(p))
		elif name.get_extension().to_lower() in EXTS:
			out.append(p)
	return out


func _process(delta: float) -> void:
	if _closing or bar == null:
		return
	if not _started:
		_connect_progress(delta)
		return
	_t += delta
	for p in _loading.duplicate():
		var st := ResourceLoader.load_threaded_get_status(p)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_keep.append(ResourceLoader.load_threaded_get(p))
			_loading.erase(p)
		elif st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_loading.erase(p)  # 못 불러온 것은 건너뛴다(쓰는 곳이 그때 다시 load한다)
	_retry -= delta
	if _retry <= 0.0:  # 못 그린 그림(빈 결과)은 다시 줄 세운다 — 이미 줄에 있으면 아무 일 없다
		_retry = 1.0
		for k in _portraits:
			PortraitsScript.portrait(k)
		for t in DUNGEON_TYPES:
			SceneSnap.snap(DUNGEON_KEY % t, DungeonSnaps.SIZE, DungeonSnaps.build.bind(t, Economy.default_party(t)), DungeonSnaps.WARM)
		SceneSnap.snap(RecruitArt.KEY, RecruitArt.SIZE, RecruitArt.build, RecruitArt.WARM)
	var total := _paths.size() + _portraits.size() + _snaps.size()
	var left := _loading.size() + _portraits.filter(func(k): return not PortraitsScript.has_portrait(k)).size() \
		+ _snaps.filter(func(k): return SceneSnap.cached(k) == null).size()
	bar.value = 100.0 * (_base + (1.0 - _base) * (total - left) / maxf(1.0, total))
	if left == 0 or _t >= TIMEOUT_SEC:
		if left > 0:
			push_warning("preloader: %d items not ready after %.0f s; showing the game anyway" % [left, TIMEOUT_SEC])
		_finish(false)


## 서버 연결 단계 막대: 로그인·gamedata·player 응답마다 CONNECT_SHARE의 1/3씩, 기다리는 동안은 다음 단계 쪽으로 조금씩(넘지 않게).
func _connect_progress(delta: float) -> void:
	var steps := int(Net.logins > 0) + int(Net.gamedata_version != "") + int(Net.ready_once)
	if steps != _steps:
		_steps = steps
		_step_t = 0.0
	_step_t += delta
	var creep := 0.8 * (1.0 - exp(-_step_t / 2.0)) if steps < 3 else 0.0
	bar.value = maxf(bar.value, 100.0 * CONNECT_SHARE * (steps + creep) / 3.0)


func _finish(instant: bool) -> void:
	_closing = true
	done = true
	if instant:
		finished.emit()
		queue_free()
		return
	bar.value = 100.0
	var root: Control = get_child(0)
	var tw := create_tween()
	tw.tween_property(root, "modulate:a", 0.0, FADE_SEC)
	tw.tween_callback(func():
		finished.emit()
		queue_free())


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP  # 다 될 때까지 뒤 화면 입력을 막는다
	add_child(root)
	var bg := TextureRect.new()
	bg.texture = SPLASH
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_bottom = -160
	box.add_theme_constant_override("separation", 12)
	root.add_child(box)
	label = Label.new()
	label.text = "게임 데이터를 불러오는 중…"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", TEXT_EDGE)
	label.add_theme_constant_override("outline_size", 6)
	box.add_child(label)
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(520, 30)
	bar.show_percentage = false
	var back := StyleBoxFlat.new()
	back.bg_color = BAR_BACK
	back.set_corner_radius_all(15)
	back.border_color = BAR_BACK_EDGE
	back.set_border_width_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = BAR_FILL
	fill.set_corner_radius_all(15)
	fill.border_color = BAR_FILL_EDGE
	fill.set_border_width_all(3)
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	box.add_child(bar)
	if Net.is_online() and not Net.storage_persistent:  # 웹 사생활 모드 등: 진행이 저장되지 않을 수 있다
		var warn := Label.new()
		warn.text = Net.STORAGE_TEXT
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.custom_minimum_size = Vector2(520, 0)
		warn.add_theme_font_size_override("font_size", 20)
		warn.add_theme_color_override("font_color", Color.WHITE)
		warn.add_theme_color_override("font_outline_color", TEXT_EDGE)
		warn.add_theme_constant_override("outline_size", 6)
		box.add_child(warn)

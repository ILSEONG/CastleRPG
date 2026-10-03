extends CanvasLayer
## 첫 로딩 화면: 게임이 처음 보이기 전에 정적 리소스를 한 번에 준비해, 배너·그림·피규어가 자리표시로 보였다가 바뀌지 않게 한다.
## main이 첫 월드를 만든 직후 붙인다(월드 위를 덮고 입력을 막는다). 순서:
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
const UiKit := preload("res://scripts/ui_kit.gd")

signal finished

const SPLASH := preload("res://assets/ui/splash.png")
const ROOT := "res://assets"
const EXTS := ["glb", "gltf", "png", "jpg", "webp", "otf", "ttf"]
const TIMEOUT_SEC := 20.0
const FADE_SEC := 0.25
const DUNGEON_TYPES := ["gold", "equip"]  # dungeon_panel.TYPES
const DUNGEON_KEY := "dungeon_band:%s"  # dungeon_panel.SNAP_KEY

static var _keep: Array = []  # 불러 둔 리소스(쥐고 있어야 캐시에 남는다)
static var done := false  # 이번 실행에서 한 번 끝냈다(월드를 다시 만들 때는 다시 하지 않는다)

var bar: ProgressBar
var label: Label

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
		_finish.call_deferred(true)
		return
	_build_ui()
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
	if _closing:
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
	bar.value = 100.0 * (total - left) / maxf(1.0, total)
	if left == 0 or _t >= TIMEOUT_SEC:
		if left > 0:
			push_warning("preloader: %d items not ready after %.0f s; showing the game anyway" % [left, TIMEOUT_SEC])
		_finish(false)


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
	label.add_theme_color_override("font_outline_color", UiKit.INK)
	label.add_theme_constant_override("outline_size", 8)
	box.add_child(label)
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(520, 26)
	bar.show_percentage = false
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.1, 0.12, 0.18, 0.75)
	back.set_corner_radius_all(13)
	back.border_color = Color(1, 1, 1, 0.85)
	back.set_border_width_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.78, 0.25)
	fill.set_corner_radius_all(11)
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	box.add_child(bar)

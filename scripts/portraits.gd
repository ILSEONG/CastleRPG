extends Node
## 영웅 피규어(개정 14 §2): 숨긴 SubViewport 하나(정사각 SIZE px, 투명 배경)에서 모델(gear 포함, 대기 자세 첫 프레임,
## 살짝 왼쪽 위 3/4 시점, main과 같은 조명·로우폴리 재질)을 키마다 한 번 렌더링해 ImageTexture로 캐시한다.
## 키 = "hero:<영웅 id>" 또는 "soldier:<병종>"(개정 15: 보병 = 기사 + 칼·방패, 궁병 = 두건 도적 + 쇠뇌, 기병 = 로우폴리 말 + 기사 —
## 월드 병사와 같은 SoldierBody.build로 만든다). "bust:<영웅 id>"(디자인 보강 5번) = 같은 모델의 흉상: 머리 뼈(목) 높이에 맞춰
## 가슴께~머리 위만 조금 더 정면에서 찍어 얼굴이 늘 같은 자리(FACE_Y)에 크게 온다 — 목록·모집 카드와 전투 초상화(draw_face)가 쓴다.
## portrait(key)는 바로 돌려준다: 캐시가 있으면 그것, 없으면 자리표시(등급 색 실루엣)를 주고 렌더를 큐에 넣는다 → 끝나면
## portrait_ready(key)(Node에 이미 ready 시그널이 있어 이 이름이다). 큐는 한 프레임에 하나: 모델을 띄우고 대기 자세를 곧바로 적용
## (AnimationPlayer.advance(0) — 안 하면 이 프레임은 T자 기본 자세) + UPDATE_ONCE → 그 프레임 RenderingServer.frame_post_draw에서
## get_texture().get_image()로 읽는다.
## 살아 있는 미리보기(상세 큰 카드): set_live(key) 동안 같은 SubViewport를 LIVE_SIZE로 키워 매 프레임 그리고(UPDATE_ALWAYS, 대기 애니메이션 ×
## LIVE_ANIM_SPEED) 큐는 쉰다.
## turn(px)로 모델을 돌린다. 카드는 live_texture()(ViewportTexture)를 직접 그린다 — SubViewportContainer도 안에서 같은 일을 하므로
## 공유 뷰포트를 컨테이너 자식으로 옮기거나 입력을 3D로 넘길 필요가 없다.
## 헤드리스(렌더러 없음): 렌더·읽기를 건너뛰고 자리표시만 쓴다(frame_post_draw가 오지 않고 get_image는 오류를 낸다).
## main 아래 노드 하나. 다른 스크립트는 정적 portrait()와 current로 쓴다. 캐시는 정적이라 월드를 다시 만들어도 남는다.
# ponytail: 캐시는 키만 본다 — 원격 표(apply_remote)가 영웅 gear를 바꾸면 다음 실행까지 옛 그림. 그럴 일이 생기면 그때 _cache.clear().

const Art := preload("res://scripts/art.gd")
const GameData := preload("res://scripts/game_data.gd")
const UnitModelScript := preload("res://scripts/unit_model.gd")
const SoldierBody := preload("res://scripts/soldier_body.gd")

const SIZE := 256
const LIVE_SIZE := 512  # 실시간 미리보기 해상도 — 상세 큰 카드가 피규어를 400px 안팎으로 그린다(개정 15). 스냅샷은 SIZE
const VIEW_SIZE := 3.5  # 직교 카메라 세로 폭(m): 키 2.2(도적)~3.0m(마법사 모자) 모델과 앞으로 뻗은 무기가 여유 있게 들어간다
const LOOK_AT := Vector3(0, 1.3, 0)
const CAM_ROT := Vector3(-18, -30, 0)  # 살짝 위·왼쪽에서 본 3/4 시점(모델 정면 +Z). 직교 — 로우폴리 셰이더 법선 규약과 같다
const SUN_ROT := Vector3(-50, -110, 0)  # main처럼 해가 화면 왼쪽 위에서(카메라 요 기준 main과 비슷한 각), 정면도 조금 밝게
const TURN_DEG_PER_PX := 0.6
const LIVE_ANIM_SPEED := 0.6  # 미리보기 대기 애니메이션 속도 배율
const PLACEHOLDER_PX := 64
const BUST_LO := 0.68  # 흉상(디자인 보강 5번): 머리 뼈(목) 높이의 이 배(가슴께)부터
const BUST_HI := 1.62  # 이 배(머리 위 — 높은 모자는 잘린다)까지. 머리가 늘 그림 세로 ~0.43에 온다(FACE_Y)
const BUST_ROT := Vector3(-10, -20, 0)  # 흉상은 조금 더 정면에서
const FACE_Y := 0.43  # 흉상 그림에서 얼굴 가운데가 오는 세로 비율(카드가 이 높이를 가운데 두고 자른다)
const NEUTRAL := Color("8C9AB0")  # 등급 없는 키(병사) 자리표시

signal portrait_ready(key: String)

static var current  # 지금 월드의 Portraits(트리에 있을 때). 없으면 portrait()는 자리표시만
static var _cache := {}  # 키 → ImageTexture
static var _placeholders := {}  # 색 → ImageTexture

var can_render := DisplayServer.get_name() != "headless"
var queue: Array = []  # 렌더 대기 키(앞에서부터)
var live_key := ""  # 실시간 미리보기 중인 키
var yaw := 0.0  # 미리보기 모델 회전(도)

var _vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D
var _shown := ""  # 지금 뷰포트에 띄운 모델의 키
var _pending := ""  # 그리기를 요청했다 — frame_post_draw에서 읽는다


func _init() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var env := Environment.new()  # main._build_environment와 같은 주변광
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.80, 0.86)
	env.ambient_light_energy = 0.9
	_vp.world_3d = World3D.new()  # 게임 월드와 따로
	_vp.world_3d.environment = env
	add_child(_vp)
	var sun := DirectionalLight3D.new()  # main의 해와 같은 색·세기, 그림자 없음(바닥이 없다)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.1
	sun.rotation_degrees = SUN_ROT
	_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = VIEW_SIZE
	_cam.rotation_degrees = CAM_ROT
	_cam.position = LOOK_AT + _cam.basis.z * 10.0
	_cam.near = 0.1
	_cam.far = 30.0
	_vp.add_child(_cam)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


func _ready() -> void:
	if can_render:
		RenderingServer.frame_post_draw.connect(_on_drawn)


## 키의 그림: 렌더한 것이 있으면 그것, 없으면 자리표시를 주고 렌더를 요청한다(끝나면 portrait_ready).
static func portrait(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	if current != null:
		current.request(key)
	return placeholder(key)


## 8각(또는 아무 볼록 다각형) 얼굴 칸에 흉상(디자인 보강 5번 — 전투 초상화 줄·길드전 수비 칸): 위가 밝은 등급 색 바탕 위에
## 흉상을 칸 모양 안에만 그린다(UV로 — 정사각 그림의 어깨가 깎인 모서리 밖으로 나오지 않게). r = 그림을 펼칠 정사각 칸.
static func draw_face(c: CanvasItem, hero_id: String, poly: PackedVector2Array, r: Rect2) -> void:
	var gc: Color = Art.GRADE_COLORS.get(GameData.hero(hero_id).get("grade", ""), NEUTRAL)
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	for p in poly:
		var v := (p - r.position) / r.size
		cols.append(gc.lightened(0.55).lerp(gc.lightened(0.12), clampf(v.y, 0.0, 1.0)))
		uvs.append(v)
	c.draw_polygon(poly, cols)
	c.draw_polygon(poly, PackedColorArray([Color.WHITE]), uvs, portrait("bust:" + hero_id))


static func has_portrait(key: String) -> bool:
	return _cache.has(key)


## 키 → UnitModel 스펙(병사는 월드 병사와 같은 Art.soldier_spec). 모르는 키는 {}(자리표시만).
static func spec_of(key: String) -> Dictionary:
	var h := _hero_of(key)
	if not h.is_empty():
		return Art.hero_spec(h)
	var s := _soldier_of(key)
	return Art.soldier_spec(s.id, s.model) if not s.is_empty() else {}


## 자리표시: 등급 색(병사는 NEUTRAL) 반투명 실루엣. 색마다 하나를 공유한다.
static func placeholder(key: String) -> Texture2D:
	var c: Color = Art.GRADE_COLORS.get(_hero_of(key).get("grade", ""), NEUTRAL)
	var bust := key.begins_with("bust:")
	var k := [c, bust]
	if not _placeholders.has(k):
		_placeholders[k] = ImageTexture.create_from_image(bust_silhouette(c) if bust else silhouette(c))
	return _placeholders[k]


## 각진 머리(8각) + 몸통(6각) 실루엣. 발이 피규어와 같은 높이(feet_y)에 서서 받침과 맞는다.
static func silhouette(c: Color) -> Image:
	var n := PLACEHOLDER_PX
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var feet := feet_y()
	var head := PackedVector2Array()
	for i in 8:
		head.append(Vector2(0.5, feet - 0.5) + Vector2.from_angle(TAU * i / 8.0 + PI / 8.0) * 0.14)
	var body := PackedVector2Array([Vector2(0.36, feet - 0.36), Vector2(0.64, feet - 0.36), Vector2(0.66, feet - 0.16),
		Vector2(0.6, feet), Vector2(0.4, feet), Vector2(0.34, feet - 0.16)])
	var fill := Color(c, 0.55)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / n
			if Geometry2D.is_point_in_polygon(p, head) or Geometry2D.is_point_in_polygon(p, body):
				img.set_pixel(x, y, fill)
	return img


## 흉상 자리표시: 큰 각진 머리 + 아래 끝까지 닿는 어깨(흉상 그림처럼 아래가 잘린다).
static func bust_silhouette(c: Color) -> Image:
	var n := PLACEHOLDER_PX
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var head := PackedVector2Array()
	for i in 8:
		head.append(Vector2(0.5, 0.4) + Vector2.from_angle(TAU * i / 8.0 + PI / 8.0) * 0.26)
	var body := PackedVector2Array([Vector2(0.3, 0.7), Vector2(0.7, 0.7), Vector2(0.86, 0.86), Vector2(0.9, 1.0), Vector2(0.1, 1.0), Vector2(0.14, 0.86)])
	var fill := Color(c, 0.55)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / n
			if Geometry2D.is_point_in_polygon(p, head) or Geometry2D.is_point_in_polygon(p, body):
				img.set_pixel(x, y, fill)
	return img


## 모델 원점(발)이 그림 세로 몇 비율에 오는지: 직교 투영이라 0.5 + 바라보는 점 높이 × cos(피치) / 세로 폭.
static func feet_y() -> float:
	return 0.5 + LOOK_AT.y * cos(deg_to_rad(-CAM_ROT.x)) / VIEW_SIZE


static func _hero_of(key: String) -> Dictionary:
	for p in ["hero:", "bust:"]:
		if key.begins_with(p):
			return GameData.hero(key.trim_prefix(p))
	return {}


## "soldier:<병종>" → 병종 행(앱이 그릴 수 있는 병종만). 아니면 {}.
static func _soldier_of(key: String) -> Dictionary:
	if not key.begins_with("soldier:"):
		return {}
	var s := GameData.soldier(key.trim_prefix("soldier:"))
	return s if not s.is_empty() and Art.SOLDIERS.has(s.id) else {}


## 렌더 요청(렌더러가 있고 모델이 있는 키만, 한 번씩).
func request(key: String) -> void:
	if can_render and not _cache.has(key) and not queue.has(key) and key != _pending and not spec_of(key).is_empty():
		queue.append(key)


## 렌더 결과를 캐시에 두고 알린다.
func store(key: String, tex: Texture2D) -> void:
	_cache[key] = tex
	queue.erase(key)
	portrait_ready.emit(key)


## 실시간 미리보기를 건다(""면 내린다). 그동안 큐는 쉰다 — 읽기 직전이던 키는 다시 줄 앞에 둔다.
func set_live(key: String) -> void:
	if key == live_key:
		return
	live_key = key
	yaw = 0.0
	_pivot.rotation_degrees.y = 0.0
	_vp.size = Vector2i(LIVE_SIZE, LIVE_SIZE) if key != "" else Vector2i(SIZE, SIZE)  # 큐 스냅샷은 미리보기가 쉴 때만 — 늘 SIZE
	if not can_render:
		return
	if _pending != "":
		queue.push_front(_pending)
		_pending = ""
	_show(key)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if key != "" else SubViewport.UPDATE_DISABLED


## 미리보기 모델을 가로 끌기 px만큼 돌린다.
func turn(px: float) -> void:
	yaw = fmod(yaw + px * TURN_DEG_PER_PX, 360.0)
	_pivot.rotation_degrees.y = yaw


## 상세 큰 카드가 그릴 것: 미리보기 중이고 렌더러가 있으면 SubViewport 그대로(매 프레임 바뀐다), 아니면 portrait(key).
func live_texture(key: String) -> Texture2D:
	return _vp.get_texture() if can_render and key == live_key else portrait(key)


func _process(_delta: float) -> void:
	if live_key != "" or _pending != "" or queue.is_empty():
		return
	_pending = queue.pop_front()
	_show(_pending)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _on_drawn() -> void:
	if _pending == "":
		return
	var key := _pending
	_pending = ""
	var img := _vp.get_texture().get_image()
	if queue.is_empty():
		_show("")  # 다 그렸다 — 보이지 않는 애니메이션을 돌리지 않게 치운다
	if img == null or img.is_empty() or img.is_invisible():
		return  # 못 그렸다(빈 그림) — 빈 피규어를 굳히지 않고 자리표시 유지. 카드가 다시 그릴 때 다시 요청한다
	img.convert(Image.FORMAT_RGBA8)
	img.fix_alpha_edges()  # 투명 테두리 색을 이웃 색으로 — 줄여 그릴 때 검은 테두리가 생기지 않게
	img.generate_mipmaps()  # 목록·슬롯 카드는 1/2~1/5 크기로 그린다
	store(key, ImageTexture.create_from_image(img))


## 뷰포트 모델을 키의 모델로 바꾼다(""면 비운다).
func _show(key: String) -> void:
	if key == _shown:
		return
	_shown = key
	for c in _pivot.get_children():
		_pivot.remove_child(c)
		c.queue_free()
	var spec := spec_of(key)
	if spec.is_empty():
		return
	var m
	if key.begins_with("soldier:"):
		m = SoldierBody.build(_pivot, key.trim_prefix("soldier:"))[0]  # 월드 병사와 같은 몸(기병은 말 + 기사)
	else:
		m = UnitModelScript.new()
		m.setup(spec)
		_pivot.add_child(m)
	var ap := m.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	ap.advance(0.0)  # 대기 첫 프레임을 지금 적용
	ap.speed_scale = LIVE_ANIM_SPEED  # 미리보기는 천천히(스냅샷은 첫 프레임이라 상관없다)
	_frame(key, m)


## 카메라: 전신(hero:·soldier:)은 고정 틀, 흉상(bust:)은 그 모델 키에 맞춰 가슴께~머리 위를 채운다(키 2.2~3.0m라 모델마다 다르다).
func _frame(key: String, m: Node3D) -> void:
	var bust := key.begins_with("bust:")
	_cam.rotation_degrees = BUST_ROT if bust else CAM_ROT
	if not bust:
		_cam.size = VIEW_SIZE
		_cam.position = LOOK_AT + _cam.basis.z * 10.0
		return
	var neck := neck_height(m)
	var lo := neck * BUST_LO
	var hi := neck * BUST_HI
	_cam.size = (hi - lo) * cos(deg_to_rad(-BUST_ROT.x))
	_cam.position = Vector3(0.0, (lo + hi) / 2.0, 0.0) + _cam.basis.z * 10.0


## 머리 뼈(목) 높이(m). 뼈가 없으면 모델 키의 0.6.
static func neck_height(m: Node3D) -> float:
	var sk := m.find_children("*", "Skeleton3D", true, false)
	if not sk.is_empty():
		var s3 := sk[0] as Skeleton3D
		var bi := s3.find_bone("head")
		if bi >= 0:
			return (s3.global_transform * s3.get_bone_global_pose(bi).origin).y
	return model_top(m) * 0.6


## 모델 맨 위 높이(m, 보이는 메시의 경계 상자 — 대기 자세가 아니라 기본 자세 기준).
static func model_top(m: Node3D) -> float:
	var top := 0.0
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		if mi.is_visible_in_tree() and mi.mesh != null:
			var box: AABB = mi.global_transform * mi.get_aabb()
			top = maxf(top, box.end.y)
	return top if top > 0.5 else 2.4

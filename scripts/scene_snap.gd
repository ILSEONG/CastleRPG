extends Node
## 3D 장면 스냅샷(범용): 키마다 숨긴 SubViewport(따로 만든 World3D, 불투명)에 장면을 한 번 렌더링해 ImageTexture로 캐시하고 뷰포트는 버린다.
## 던전 탭 카드 그림 띠(dungeon_snaps.gd), 모집 창 삽화 등이 쓴다. 읽기는 portraits.gd와 같은 방식(뷰포트를 그리게 두고 그 프레임
## RenderingServer.frame_post_draw에서 get_texture().get_image()) — Compatibility·WebGL에서 된다.
##
## API: snap(key, size, build, warm_frames := 2) -> Texture2D(정적)
##   - 캐시에 있으면 그 그림, 없으면 렌더를 큐에 넣고 자리표시(placeholder())를 돌려준다. 끝나면 node().snap_ready(key).
##   - build(root: Node3D): 장면 노드·카메라·조명·환경(WorldEnvironment)을 root에 넣는다. root가 뷰포트 안(트리 안)에 들어간 뒤 부르므로
##     look_at 같은 트리 안 함수도 된다. 뷰포트의 첫 카메라가 쓰인다.
##   - warm_frames: 찍기 전에 그만큼 프레임을 돌린다(애니메이션 자세·파티클·스킬 이펙트가 화면에 나오게). 0이면 첫 프레임을 찍는다.
##   - 큐는 한 번에 하나(장면 만들기는 프레임마다 많아야 하나). 같은 키는 한 번만 렌더링한다.
## 예:
##   const SceneSnap := preload("res://scripts/scene_snap.gd")
##   func _build_scene(root: Node3D) -> void:
##   	root.add_child(ArenaKit.lighting(cfg))  # 환경·조명
##   	var cam := Camera3D.new()
##   	root.add_child(cam)
##   	cam.look_at_from_position(Vector3(0, 2, 6), Vector3(0, 1, 0))
##   	root.add_child(hero_casting_fx)
##   SceneSnap.node().snap_ready.connect(func(k): if k == "recruit:hero": queue_redraw())
##   var tex := SceneSnap.snap("recruit:hero", Vector2i(1024, 512), _build_scene, 8)  # 8프레임 데운 뒤 찍는다(이펙트가 보이게)
## 헤드리스(렌더러 없음): 큐에 넣지 않고 자리표시만. 노드는 node()가 처음 불릴 때 SceneTree 루트에 붙인다(월드·던전 장면을 바꿔도 남는다).
## 캐시는 정적(키만 본다 — 내용이 바뀌는 장면은 키를 바꾼다).

const Self := preload("res://scripts/scene_snap.gd")
const DEFAULT_WARM := 2

signal snap_ready(key: String)

static var current  # 공유 노드(node())
static var _cache := {}  # 키 → ImageTexture
static var _placeholder: ImageTexture

var can_render := DisplayServer.get_name() != "headless"
var queue: Array = []  # 대기 [{key, size, build, warm}](앞에서부터)
var busy := ""  # 지금 렌더링 중인 키

var _vp: SubViewport
var _left := 0  # 찍기 전에 남은 프레임


## 캐시된 그림, 없으면 렌더를 요청하고 자리표시.
static func snap(key: String, size: Vector2i, build: Callable, warm_frames := DEFAULT_WARM) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	node().request(key, size, build, warm_frames)
	return placeholder()


## 캐시된 그림, 없으면 null(요청하지 않는다 — 매 프레임 그리는 쪽용).
static func cached(key: String) -> Texture2D:
	return _cache.get(key)


## 공유 노드(없으면 만들어 SceneTree 루트에 붙인다 — 붙이기는 지연 호출).
static func node() -> Node:
	if current == null or not is_instance_valid(current):
		current = Self.new()
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(current)
	return current


## 자리표시: 위가 어두운 회청색 세로 그러데이션(늘려 그린다). 하나를 공유한다.
static func placeholder() -> Texture2D:
	if _placeholder == null:
		var img := Image.create_empty(1, 16, false, Image.FORMAT_RGBA8)
		for y in 16:
			img.set_pixel(0, y, Color(0.30, 0.34, 0.42).lerp(Color(0.55, 0.60, 0.68), y / 15.0))
		_placeholder = ImageTexture.create_from_image(img)
	return _placeholder


func _exit_tree() -> void:
	if current == self:
		current = null


func _ready() -> void:
	if can_render:
		RenderingServer.frame_post_draw.connect(_on_drawn)


## 렌더 요청(렌더러가 있을 때, 키마다 한 번).
func request(key: String, size: Vector2i, build: Callable, warm_frames := DEFAULT_WARM) -> void:
	if not can_render or _cache.has(key) or key == busy or queue.any(func(q): return q.key == key):
		return
	queue.append({"key": key, "size": size, "build": build, "warm": maxi(0, warm_frames)})


## 결과를 캐시에 두고 알린다.
func store(key: String, tex: Texture2D) -> void:
	_cache[key] = tex
	snap_ready.emit(key)


func _process(_delta: float) -> void:
	if busy != "" or queue.is_empty():
		return
	var q: Dictionary = queue.pop_front()
	busy = q.key
	_left = q.warm
	_vp = SubViewport.new()
	_vp.size = q.size
	_vp.world_3d = World3D.new()  # 게임 월드와 따로
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS  # 데우는 동안 매 프레임
	add_child(_vp)
	var root := Node3D.new()
	_vp.add_child(root)
	q.build.call(root)


func _on_drawn() -> void:
	if busy == "":
		return
	if _left > 0:
		_left -= 1
		return
	var key := busy
	var img := _vp.get_texture().get_image()
	busy = ""
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.queue_free()
	_vp = null
	if img == null or img.is_empty():
		return  # 못 그렸다 — 자리표시 유지, 다음 snap(key)에서 다시 요청
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()  # 띠·삽화는 줄여 그린다
	store(key, ImageTexture.create_from_image(img))

extends RefCounted
## 범용 3D 스냅(개정 23 모집 키 아트용 최소판 — 던전 배너 작업의 scene_snap이 main에 오면 그것을 쓴다).
## snap(key, size, build)는 바로 텍스처를 돌려준다: 캐시에 있으면 그것, 없으면 자리표시(어두운 세로 그라데이션, size 비율)를 주고,
## 렌더러가 있으면 숨은 SubViewport(자기 World3D)에 build(root: Node3D)로 장면을 만들어 WARMUP_FRAMES 프레임 뒤 한 번 읽어
## 같은 ImageTexture에 덮어쓴다(쓰는 쪽은 다시 받을 필요가 없다). 헤드리스(렌더러 없음)는 자리표시만.

const WARMUP_FRAMES := 4  # 셰이더 컴파일·애니메이션 자세가 자리 잡을 프레임
const PLACEHOLDER_DIV := 8  # 자리표시 = size / 8(비율만 맞춘다)
const TOP := Color(0.09, 0.06, 0.14)
const BOTTOM := Color(0.36, 0.13, 0.07)

static var _cache := {}  # 키 → ImageTexture


static func snap(key: String, size: Vector2i, build: Callable) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var tex := ImageTexture.create_from_image(placeholder(size))
	_cache[key] = tex
	if DisplayServer.get_name() != "headless":
		_render(tex, size, build)
	return tex


## 어두운 보라 → 불씨 빨강 세로 그라데이션.
static func placeholder(size: Vector2i) -> Image:
	var w := maxi(1, size.x / PLACEHOLDER_DIV)
	var h := maxi(2, size.y / PLACEHOLDER_DIV)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		img.fill_rect(Rect2i(0, y, w, 1), TOP.lerp(BOTTOM, float(y) / (h - 1)))
	return img


static func _render(tex: ImageTexture, size: Vector2i, build: Callable) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var root := Node3D.new()
	vp.add_child(root)
	build.call(root)
	tree.root.add_child.call_deferred(vp)  # 창 _ready 중에 불려도 된다
	for i in WARMUP_FRAMES:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img != null and not img.is_empty():
		img.generate_mipmaps()
		tex.set_image(img)

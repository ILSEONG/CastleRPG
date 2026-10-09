extends RefCounted
## 영웅 일러스트(2026-10-07, 사용자 요청): assets/ui/heroes/<id>.jpg — 사용자가 ChatGPT로 만든 그림(영웅 모델 컨셉 + 화풍 참조,
## 지시문 묶음은 프로젝트 파일 design/illustrations/chatgpt_pack)을 dev/hero_art/ingest.py로 640 px 정사각으로 잘라 손실 압축으로 넣는다.
## 그림이 있으면 HeroCard가 3D 흉상 대신 카드 안을 이 그림으로 꽉 채우고(목록·배치 슬롯·모집·던전·PVP·친구 고르기),
## 상세 큰 카드는 일러스트를 먼저 보여 주고 [3D] 칩으로 실시간 모델과 바꾼다. 전투 초상화 줄·길드전 수비 칸(Portraits.draw_face)과
## 이벤트 보상 칸도 얼굴 쪽으로 당겨 자른 그림(2026-10-08 "일러스트 구진거 더 찾아봐"). 그림이 없는 영웅은 3D 흉상.
## FOCUS = 그림에서 얼굴 가운데(0~1). 자를 때 얼굴이 창 가운데 위쪽(face_at)에 오게 맞춘다.

const DIR := "res://assets/ui/heroes/"
const FACE_AT := 0.3  # 자른 창 세로에서 얼굴 가운데가 올 비율
const FOCUS := {
	"arteon": Vector2(0.58, 0.19),
	"ignis": Vector2(0.60, 0.23),
	"sylvana": Vector2(0.64, 0.17),
	"grom": Vector2(0.56, 0.23),
	"seraphine": Vector2(0.56, 0.18),
	"kyle": Vector2(0.58, 0.19),
	"baldur": Vector2(0.62, 0.21),
	"lumina": Vector2(0.52, 0.21),
	"harald": Vector2(0.56, 0.26),
	"nev": Vector2(0.42, 0.25),
	"bron": Vector2(0.52, 0.27),
	"mira": Vector2(0.56, 0.23),
	"torvin": Vector2(0.62, 0.28),
	"rian": Vector2(0.56, 0.21),
	"echo": Vector2(0.46, 0.23),
	"gork": Vector2(0.58, 0.25),
	"felix": Vector2(0.62, 0.25),
	"hans": Vector2(0.55, 0.15),
	"ella": Vector2(0.56, 0.14),
	"dorik": Vector2(0.56, 0.17),
	"nina": Vector2(0.48, 0.22),
	"jack": Vector2(0.56, 0.28),
	"valen": Vector2(0.48, 0.15),
	"frieda": Vector2(0.52, 0.19),
	"morgana": Vector2(0.54, 0.23),
	"thorgar": Vector2(0.52, 0.23),
	"raven": Vector2(0.58, 0.24),
	"gaia": Vector2(0.52, 0.22),
	"dante": Vector2(0.53, 0.22),
	"kaz": Vector2(0.60, 0.21),
	"luna": Vector2(0.48, 0.23),
	"orin": Vector2(0.56, 0.26),
	"selene": Vector2(0.58, 0.24),
	"pip": Vector2(0.50, 0.24),
	"grit": Vector2(0.54, 0.24),
	"tia": Vector2(0.60, 0.22),
}

static var enabled := true  # false면 그림이 있어도 예전 흉상(테스트·비교용)
static var _cache := {}  # id → Texture2D 또는 null(없음)


## 영웅 일러스트. 없거나 꺼져 있으면 null.
static func texture(id: String) -> Texture2D:
	if not enabled or id == "":
		return null
	if not _cache.has(id):
		var path := DIR + id + ".jpg"
		_cache[id] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _cache[id]


## 그림을 전부 미리 불러 둔다(게임은 로딩 화면 Preloader가 assets 아래를 미리 불러 같은 일을 한다 — 로딩 화면 없이 도는 테스트용).
static func warm() -> void:
	for id in FOCUS:
		texture(id)


static func has_art(id: String) -> bool:
	return texture(id) != null


static func focus(id: String) -> Vector2:
	return FOCUS.get(id, Vector2(0.5, 0.3))


## 그림(tex 크기)에서 창(win 크기)을 꽉 채울 부분: 비율을 창에 맞추고, 얼굴(focus)이 가로 가운데·세로 face_at에 오게 옮긴 뒤 그림 안으로 민다.
## zoom > 1이면 그만큼 얼굴 쪽으로 당겨 좁게 자른다(전투 초상화 같은 작은 얼굴 칸).
static func region(tex: Vector2, win: Vector2, face: Vector2, face_at := FACE_AT, zoom := 1.0) -> Rect2:
	if tex.x <= 0.0 or tex.y <= 0.0 or win.x <= 0.0 or win.y <= 0.0:
		return Rect2(Vector2.ZERO, tex)
	var aspect := win.x / win.y
	var sz := Vector2(tex.x, tex.x / aspect)
	if sz.y > tex.y:
		sz = Vector2(tex.y * aspect, tex.y)
	sz /= maxf(zoom, 1.0)
	var pos := Vector2(face.x * tex.x - sz.x * 0.5, face.y * tex.y - sz.y * face_at)
	pos.x = clampf(pos.x, 0.0, tex.x - sz.x)
	pos.y = clampf(pos.y, 0.0, tex.y - sz.y)
	return Rect2(pos, sz)


## 다각형 poly(창 r 안)를 그림으로 채운다 — UV는 region을 창 r에 맞춘 좌표라 모서리 깎인 모양대로 잘린다.
static func draw_in(ci: CanvasItem, id: String, poly: PackedVector2Array, r: Rect2, face_at := FACE_AT, zoom := 1.0) -> bool:
	var tex := texture(id)
	if tex == null or r.size.x <= 0.0 or r.size.y <= 0.0:
		return false
	var ts := tex.get_size()
	var reg := region(ts, r.size, focus(id), face_at, zoom)
	var uvs := PackedVector2Array()
	for p in poly:
		var k := (p - r.position) / r.size
		uvs.append((reg.position + k * reg.size) / ts)
	ci.draw_colored_polygon(poly, Color.WHITE, uvs, tex)
	return true

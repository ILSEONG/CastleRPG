extends RefCounted
## 던전 탭 카드 띠의 그림(사용자가 ChatGPT로 그린 일러스트, 2026-10-09). assets/ui/dungeons/<종류>.jpg — 1256×360(띠 628×180의 2배).
## 원본 1536×1024에서 주인공이 든 가운데 가로 띠를 잘라 넣었다(원본·다른 안 = project-files design/dungeon_banners/received).
## 그림이 있는 종류는 3D 장면 스냅샷(dungeon_snaps)을 찍지 않는다. 오토로드 참조 없음.

const DIR := "res://assets/ui/dungeons/"

static var enabled := true  # false면 그림이 있어도 예전 3D 스냅샷(비교용)
static var _cache := {}  # 종류 → Texture2D 또는 null(없음)


## 던전 띠 그림. 없으면 null(→ 스냅샷·평면 그림).
static func texture(t: String) -> Texture2D:
	if not enabled:
		return null
	if not _cache.has(t):
		var path := DIR + t + ".jpg"
		_cache[t] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _cache[t]


static func has_art(t: String) -> bool:
	return enabled and ResourceLoader.exists(DIR + t + ".jpg")

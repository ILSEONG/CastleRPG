extends Control
## 모집 창 위 배너(2026-10-08, 사용자 "영웅모집은 너무 못생긴거 아니야?"): 예전 3D 장면 대신 SSR 영웅 일러스트 셋을 비스듬한 칸에 나란히 —
## 가운데 칸은 밝게, 양옆은 조금 어둡게, 칸 사이 금색 사선, 아래는 제목 자리로 어둡게. 정지 그림(움직이지 않는다, 사용자 요청).
## 그림이 하나라도 없으면(HeroArt 꺼짐 등) has_art()가 false — 모집 창이 예전 3D 키 아트를 대신 보여 준다.

const HeroArt := preload("res://scripts/hero_art.gd")

const IDS := ["kyle", "arteon", "seraphine"]  # 왼쪽 · 가운데 · 오른쪽
const SLANT := 64.0  # 칸 사이 사선이 위아래로 벌어지는 폭
const SPLIT := [0.34, 0.66]  # 사선 가운데의 가로 비율
const SIDE_DIM := Color(0.05, 0.03, 0.09, 0.38)
const GOLD := Color("F2C14E")
const FACE_AT := 0.34


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func has_art() -> bool:
	return IDS.all(func(id): return HeroArt.has_art(id))


## 칸 i의 다각형(위 두 점이 오른쪽으로 SLANT/2, 아래 두 점이 왼쪽으로 SLANT/2 밀린 평행사변형, 양 끝 칸은 창 가장자리까지).
func panel(i: int) -> PackedVector2Array:
	var w := size.x
	var h := size.y
	var xs := [0.0]
	for f in SPLIT:
		xs.append(w * f)
	xs.append(w)
	var half := SLANT * 0.5
	var l: float = xs[i]
	var r: float = xs[i + 1]
	var lt := l + (half if i > 0 else 0.0)
	var lb := l - (half if i > 0 else 0.0)
	var rt := r + (half if i < IDS.size() - 1 else 0.0)
	var rb := r - (half if i < IDS.size() - 1 else 0.0)
	return PackedVector2Array([Vector2(lt, 0), Vector2(rt, 0), Vector2(rb, h), Vector2(lb, h)])


static func _bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.04, 0.1))
	for i in IDS.size():
		var poly := panel(i)
		HeroArt.draw_in(self, IDS[i], poly, _bounds(poly), FACE_AT)
		if i != 1:
			draw_colored_polygon(poly, SIDE_DIM)
	# 아래 절반: 투명 → 어둡게(제목 자리)
	var y0 := size.y * 0.5
	var top := Color(0.05, 0.03, 0.09, 0.0)
	var bot := Color(0.05, 0.03, 0.09, 0.82)
	draw_polygon(PackedVector2Array([Vector2(0, y0), Vector2(size.x, y0), Vector2(size.x, size.y), Vector2(0, size.y)]),
		PackedColorArray([top, top, bot, bot]))
	# 칸 사이 금색 사선(어두운 테두리 위에 금색)
	for i in range(1, IDS.size()):
		var p := panel(i)
		draw_line(p[0], p[3], Color(0.1, 0.06, 0.02, 0.9), 9.0, true)
		draw_line(p[0], p[3], GOLD, 4.0, true)
	# 위아래 금색 띠
	draw_rect(Rect2(0, 0, size.x, 4), GOLD)
	draw_rect(Rect2(0, size.y - 4, size.x, 4), GOLD.darkened(0.25))

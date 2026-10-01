extends Control
## 자원 아이콘(골드·목재·석재·식량): 평면 로우폴리 — 각진 다각형, 면마다 단색, 밝은 면 하나, 얇은 진한 외곽.
## 도형은 단위 좌표(-0.5..0.5)로 정의하고 draw_icon이 크기를 곱한다 → 어느 크기에서도 같은 모양. 오토로드 참조 없음.

const KINDS := ["gold", "wood", "stone", "food"]
const OUTLINE := Color(0.16, 0.11, 0.07)

var kind := "gold":
	set(v):
		kind = v
		queue_redraw()


func _draw() -> void:
	draw_icon(self, kind, size / 2.0, minf(size.x, size.y))


## ci(_draw 안의 CanvasItem)에 center 중심, 한 변 size 픽셀 안에 kind 아이콘을 그린다.
static func draw_icon(ci: CanvasItem, kind_name: String, center: Vector2, size_px: float) -> void:
	var line_w := maxf(1.0, size_px / 32.0)
	for shape in shapes(kind_name):
		var pts := PackedVector2Array()
		for p in shape[0]:
			pts.append(center + p * size_px)
		ci.draw_colored_polygon(pts, shape[1])
		if shape[2]:
			pts.append(pts[0])
			ci.draw_polyline(pts, OUTLINE, line_w)


## 그리는 순서대로 [점 배열(단위 좌표), 색, 외곽선 여부]. 모르는 kind는 빈 배열.
static func shapes(kind_name: String) -> Array:
	match kind_name:
		"gold":
			return [
				[_ngon(8, 0.46, PI / 8.0), Color(0.78, 0.55, 0.10), true],
				[_ngon(8, 0.34, PI / 8.0), Color(0.95, 0.76, 0.20), true],
				[[Vector2(-0.22, -0.12), Vector2(-0.08, -0.24), Vector2(0.02, -0.2), Vector2(-0.14, -0.02)], Color(1.0, 0.92, 0.55), false],
			]
		"wood":
			return [
				[_ngon(10, 0.46, 0.0), Color(0.38, 0.25, 0.14), true],
				[_ngon(10, 0.37, 0.0), Color(0.78, 0.60, 0.38), false],
				[_ngon(8, 0.27, 0.2), Color(0.66, 0.47, 0.28), false],
				[_ngon(8, 0.19, 0.0), Color(0.80, 0.63, 0.40), false],
				[_ngon(6, 0.09, 0.0), Color(0.62, 0.43, 0.25), false],
			]
		"stone":
			var a := Vector2(-0.46, 0.18)
			var b := Vector2(-0.30, -0.26)
			var c := Vector2(0.10, -0.42)
			var d := Vector2(0.42, -0.10)
			var e := Vector2(0.46, 0.30)
			var f := Vector2(0.0, 0.42)
			var g := Vector2(-0.32, 0.36)
			var m := Vector2(0.0, 0.0)
			return [
				[[a, b, m, f, g], Color(0.44, 0.44, 0.48), false],
				[[d, e, f, m], Color(0.56, 0.56, 0.60), false],
				[[b, c, d, m], Color(0.72, 0.72, 0.76), false],
				[[a, b, c, d, e, f, g], Color(0, 0, 0, 0), true],
			]
		"food":  # 밥그릇(사용자 요청: 이삭은 화살·칼처럼 보인다) — 각진 고봉밥 + 그릇 + 받침
			var rice := Color(0.97, 0.95, 0.88)
			return [
				# 고봉밥: 각진 반원(면 3개 명암)
				[[Vector2(-0.38, 0.02), Vector2(-0.30, -0.22), Vector2(-0.10, -0.36), Vector2(0.10, -0.36), Vector2(0.30, -0.22), Vector2(0.38, 0.02)], rice, true],
				[[Vector2(-0.30, -0.22), Vector2(-0.10, -0.36), Vector2(0.02, -0.12), Vector2(-0.22, -0.04)], Color(1.0, 1.0, 0.97), false],
				[[Vector2(0.10, -0.36), Vector2(0.30, -0.22), Vector2(0.38, 0.02), Vector2(0.14, -0.04)], Color(0.88, 0.85, 0.76), false],
				# 밥알 몇 개(작은 마름모)
				[[Vector2(-0.16, -0.20), Vector2(-0.12, -0.24), Vector2(-0.08, -0.20), Vector2(-0.12, -0.16)], Color(0.80, 0.77, 0.68), false],
				[[Vector2(0.10, -0.14), Vector2(0.14, -0.18), Vector2(0.18, -0.14), Vector2(0.14, -0.10)], Color(0.80, 0.77, 0.68), false],
				# 그릇: 위가 넓은 사다리꼴(청자색) + 밝은 왼쪽 면
				[[Vector2(-0.46, 0.0), Vector2(0.46, 0.0), Vector2(0.30, 0.34), Vector2(-0.30, 0.34)], Color(0.30, 0.52, 0.62), true],
				[[Vector2(-0.46, 0.0), Vector2(-0.06, 0.0), Vector2(-0.10, 0.34), Vector2(-0.30, 0.34)], Color(0.42, 0.66, 0.76), false],
				[[Vector2(-0.46, 0.0), Vector2(0.46, 0.0), Vector2(0.44, 0.06), Vector2(-0.44, 0.06)], Color(0.22, 0.40, 0.48), false],
				# 받침
				[[Vector2(-0.18, 0.34), Vector2(0.18, 0.34), Vector2(0.22, 0.46), Vector2(-0.22, 0.46)], Color(0.24, 0.42, 0.50), true],
			]
	return []


## 정 n각형(원점 중심, 반지름 r, 시작각 rot).
static func _ngon(n: int, r: float, rot: float) -> Array:
	var pts := []
	for i in n:
		pts.append(Vector2.from_angle(rot + TAU * i / n) * r)
	return pts


## from → to 선분을 두께 2*half_w로 만든 사각형.
static func _quad(from: Vector2, to: Vector2, half_w: float) -> Array:
	var n := (to - from).normalized().orthogonal() * half_w
	return [from + n, to + n, to - n, from - n]

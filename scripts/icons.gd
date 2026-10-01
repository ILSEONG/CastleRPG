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
		"food":  # 밀 이삭 하나: 기운 줄기 + 좌우로 엇갈린 낟알 4쌍 + 꼭대기 낟알 + 잎 하나(사용자 요청: 곡물답게)
			var straw := Color(0.66, 0.54, 0.24)
			var base := Vector2(-0.18, 0.46)
			var tip := Vector2(0.16, -0.46)
			var u := (tip - base).normalized()
			var n := u.orthogonal()
			var length := base.distance_to(tip)
			var out := [
				[_quad(base, base + u * length * 0.46, 0.036), straw, true],
				[[base + u * length * 0.16, base + u * length * 0.24 + n * 0.20, base + u * length * 0.30 + n * 0.17, base + u * length * 0.21], straw.darkened(0.12), true],
			]
			for t in [0.44, 0.56, 0.68, 0.80]:
				var c: Vector2 = base + u * length * t
				for side in [-1.0, 1.0]:
					var d := u.rotated(-side * 0.5)
					out.append_array(_kernel(c + n * side * 0.085, d, 0.21, 0.12))
			out.append_array(_kernel(base + u * length * 0.89, u, 0.2, 0.12))
			return out
		"shield":  # 방치 무적 표시(개정 12). KINDS(자원 칩)에는 넣지 않는다
			var top_l := Vector2(-0.36, -0.40)
			var top_r := Vector2(0.36, -0.40)
			var mid_l := Vector2(-0.38, 0.06)
			var mid_r := Vector2(0.38, 0.06)
			var tip := Vector2(0.0, 0.48)
			var top_c := Vector2(0.0, -0.46)
			return [
				[[top_l, top_c, top_r, mid_r, tip, mid_l], Color(0.36, 0.52, 0.78), true],
				[[Vector2(-0.26, -0.30), top_c + Vector2(0, 0.08), Vector2(0.0, 0.30), Vector2(-0.28, 0.02)], Color(0.62, 0.78, 0.96), false],
				[[top_c + Vector2(0, 0.08), Vector2(0.26, -0.30), Vector2(0.28, 0.02), Vector2(0.0, 0.30)], Color(0.24, 0.38, 0.64), false],
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

## 낟알: center 중심, dir 방향 길이 len·폭 w의 마름모 + 왼쪽 반 밝은 면 → [본체, 하이라이트] 두 도형.
static func _kernel(center: Vector2, dir: Vector2, len: float, w: float) -> Array:
	var d := dir.normalized() * len * 0.5
	var p := dir.normalized().orthogonal() * w * 0.5
	var body := [center - d, center + p, center + d, center - p]
	return [[body, Color(0.86, 0.66, 0.20), true], [[center - d, center + p, center + d], Color(0.98, 0.84, 0.42), false]]

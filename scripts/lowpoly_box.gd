extends StyleBox
## 로우폴리 박스(스펙 §4): 모서리를 깎은 8각 다각형을 삼각형 면 16개로 채운다.
## 면마다 위치 해시로 밝기 ±facet, 왼위 면일수록 밝게(왼위 광원). 진한 외곽선 + 윗변 밝은 띠.
## 같은 (속성, 크기)면 항상 같은 폴리곤(결정적). 크기가 같으면 지오메트리를 재사용한다 → 매 프레임 그려도 가볍다.
## StyleBox 스크립트의 _draw(to_canvas_item: RID, rect: Rect2)는 RenderingServer로 해당 canvas item에 직접 그린다
## (rect는 그 item의 로컬 좌표). 삼각형은 canvas_item_add_triangle_array 한 번, 외곽선은 add_polyline 한 번.

const FACES := 16  # 변 8 × 2등분

@export var color := Color(0.98, 0.97, 0.93):
	set(v):
		color = v
		_dirty()
@export var chamfer := 10.0:
	set(v):
		chamfer = v
		_dirty()
@export var facet := 0.06:
	set(v):
		facet = v
		_dirty()
@export var border_color := Color(0.16, 0.18, 0.24, 0.9):
	set(v):
		border_color = v
		_dirty()
@export var border_width := 2.0:
	set(v):
		border_width = v
		_dirty()
@export var seed := 1:
	set(v):
		seed = v
		_dirty()

var _size := Vector2(-1, -1)
var _idx := PackedInt32Array()
var _pts := PackedVector2Array()
var _cols := PackedColorArray()
var _line := PackedVector2Array()
var _line_cols := PackedColorArray()


func _dirty() -> void:
	_size = Vector2(-1, -1)
	emit_changed()


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if rect.size.x < 2.0 or rect.size.y < 2.0:
		return
	if rect.size != _size:
		_build(rect.size)
	RenderingServer.canvas_item_add_set_transform(to_canvas_item, Transform2D(0.0, rect.position))
	RenderingServer.canvas_item_add_triangle_array(to_canvas_item, _idx, _pts, _cols)
	if border_width > 0.0:
		RenderingServer.canvas_item_add_polyline(to_canvas_item, _line, _line_cols, border_width, true)
	RenderingServer.canvas_item_add_set_transform(to_canvas_item, Transform2D.IDENTITY)


## 크기 s 박스의 지오메트리(원점 기준)를 만든다.
func _build(s: Vector2) -> void:
	var r := Rect2(Vector2.ZERO, s).grow(-border_width * 0.5)
	_pts = PackedVector2Array()
	_cols = PackedColorArray()
	_idx = PackedInt32Array()
	for f in faces(r, chamfer, color, facet, seed):
		for p in f[0]:
			_idx.append(_pts.size())
			_pts.append(p)
			_cols.append(f[1])
	# 윗변 밝은 띠: 사각형 하나(삼각형 둘)
	var b := band(r, chamfer)
	var bc := Color(1, 1, 1, 0.32 * color.a)
	for i in [0, 1, 2, 0, 2, 3]:
		_idx.append(_pts.size())
		_pts.append(b[i])
		_cols.append(bc)
	_line = octagon(r, chamfer)
	_line.append(_line[0])
	_line_cols = PackedColorArray()
	for _i in _line.size():
		_line_cols.append(border_color)
	_size = s


## 모서리를 깎은 8각형(시계 방향, 윗변 왼쪽 점부터). chamfer는 짧은 변의 절반까지로 제한.
static func octagon(r: Rect2, chamfer_px: float) -> PackedVector2Array:
	var c := clampf(chamfer_px, 0.0, minf(r.size.x, r.size.y) * 0.5)
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	return PackedVector2Array([
		Vector2(x0 + c, y0), Vector2(x1 - c, y0), Vector2(x1, y0 + c), Vector2(x1, y1 - c),
		Vector2(x1 - c, y1), Vector2(x0 + c, y1), Vector2(x0, y1 - c), Vector2(x0, y0 + c)])


## 윗변 띠 사각형 4점.
static func band(r: Rect2, chamfer_px: float) -> PackedVector2Array:
	var o := octagon(r, chamfer_px)
	var h := clampf(r.size.y * 0.18, 1.0, 4.0)
	return PackedVector2Array([o[0], o[1], o[1] + Vector2(-1.5, h), o[0] + Vector2(1.5, h)])


## 결정적 정수 해시 → 0..1
static func hash01(a: int, b: int) -> float:
	var h: int = (a * 73856093) ^ (b * 19349663) ^ 0x5bd1e995
	h = ((h >> 13) ^ h) * 1274126177
	h = (h ^ (h >> 16)) & 0xffff
	return float(h) / 65535.0


## 면 목록 [[PackedVector2Array(삼각형 3점), Color], …] — 항상 FACES개. 부채꼴(비튼 중심) × 변 2등분.
static func faces(r: Rect2, chamfer_px: float, base: Color, facet_amt: float, seed_v: int) -> Array:
	var o := octagon(r, chamfer_px)
	var ctr := r.get_center() + Vector2((hash01(seed_v, 101) - 0.5) * r.size.x * 0.16, (hash01(seed_v, 102) - 0.5) * r.size.y * 0.3)
	var out := []
	for i in 8:
		var a: Vector2 = o[i]
		var b: Vector2 = o[(i + 1) % 8]
		var m := a.lerp(b, 0.4 + hash01(seed_v, 200 + i) * 0.2)
		for k in 2:
			var tri := PackedVector2Array([ctr, a, m]) if k == 0 else PackedVector2Array([ctr, m, b])
			out.append([tri, shade(base, tri, r, facet_amt, seed_v, i * 2 + k)])
	return out


## 면 하나의 색: 왼위 광원 + 위치 해시.
static func shade(base: Color, tri: PackedVector2Array, r: Rect2, facet_amt: float, seed_v: int, face_i: int) -> Color:
	var g := (tri[0] + tri[1] + tri[2]) / 3.0
	var t := ((g.x - r.position.x) / maxf(r.size.x, 1.0) + (g.y - r.position.y) / maxf(r.size.y, 1.0)) * 0.5
	var light := (0.5 - t) * 2.0  # 왼위 +1, 오른아래 -1
	var d := facet_amt * (0.6 * light + 0.8 * (hash01(seed_v, 300 + face_i) * 2.0 - 1.0))
	return base.lightened(d) if d >= 0.0 else base.darkened(-d)

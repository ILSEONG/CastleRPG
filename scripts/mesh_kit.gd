extends RefCounted
## 로우폴리 메시 도구: 삼각형마다 정점을 따로 둬 면마다 단색·각진 음영(정점 색, 텍스처 없음).
## 사용: var k = MeshKit.new(); k.xform = Transform3D(...); k.box(...); ...; var mesh := k.commit()
## 면 감기: 각 면을 "바깥 방향(outward)"과 함께 넘기면 Godot 앞면 규약에 맞게 자동으로 정렬한다.
## 오토로드 참조 없음 → 헤드리스 테스트 가능.

## Godot 앞면 = 바깥에서 볼 때 시계 방향. 캡처에서 면이 사라지면(컬링) 이 값을 뒤집는다.
const CLOCKWISE_FRONT := true

var xform := Transform3D.IDENTITY
var _st := SurfaceTool.new()
var _tris := 0


func _init() -> void:
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


func triangle_count() -> int:
	return _tris


## 볼록 다각형 한 면(꼭짓점 순서 무관하게 둘레 순서로). outward = 면이 바라볼 방향(로컬).
func face(points: Array, outward: Vector3, color: Color) -> void:
	for i in range(1, points.size() - 1):
		var a: Vector3 = points[0]
		var b: Vector3 = points[i]
		var c: Vector3 = points[i + 1]
		var ccw_out := (b - a).cross(c - a).dot(outward) > 0.0
		if ccw_out == CLOCKWISE_FRONT:
			var t := b
			b = c
			c = t
		for v in [a, b, c]:
			_st.set_color(color)
			_st.add_vertex(xform * v)
		_tris += 1


## 바닥 중심 base, 크기 size인 상자. 바닥면은 기본 생략(땅에 붙는 물체).
func box(base: Vector3, size: Vector3, color: Color, with_bottom := false) -> void:
	var h := Vector3(size.x / 2.0, 0, size.z / 2.0)
	var y0 := base.y
	var y1 := base.y + size.y
	var p := [
		Vector3(base.x - h.x, y0, base.z - h.z), Vector3(base.x + h.x, y0, base.z - h.z),
		Vector3(base.x + h.x, y0, base.z + h.z), Vector3(base.x - h.x, y0, base.z + h.z),
	]
	var q := []
	for v in p:
		q.append(Vector3(v.x, y1, v.z))
	face(q, Vector3.UP, color)
	if with_bottom:
		face(p, Vector3.DOWN, color)
	for i in 4:
		var j := (i + 1) % 4
		var mid: Vector3 = (p[i] + p[j]) / 2.0 - base
		face([p[i], p[j], q[j], q[i]], Vector3(mid.x, 0, mid.z), color)


## 박공지붕: 바닥 중심 base, 가로 size.x(용마루 방향 X), 깊이 size.z, 높이 height. 처마 overhang.
func gable(base: Vector3, size: Vector3, height: float, color: Color, overhang := 0.25) -> void:
	var hx := size.x / 2.0 + overhang
	var hz := size.z / 2.0 + overhang
	var ridge_a := base + Vector3(-hx, height, 0)
	var ridge_b := base + Vector3(hx, height, 0)
	var e := [base + Vector3(-hx, 0, -hz), base + Vector3(hx, 0, -hz), base + Vector3(hx, 0, hz), base + Vector3(-hx, 0, hz)]
	face([e[0], e[1], ridge_b, ridge_a], Vector3(0, hz, -height), color)
	face([e[3], e[2], ridge_b, ridge_a], Vector3(0, hz, height), color)
	face([e[0], e[3], ridge_a], Vector3.LEFT, color.darkened(0.08))
	face([e[1], e[2], ridge_b], Vector3.RIGHT, color.darkened(0.08))


## n각 원뿔대(원기둥: r_top == r_bottom, 원뿔: r_top == 0). 바닥 중심 base. 윗면 포함.
func prism_n(base: Vector3, sides: int, r_bottom: float, r_top: float, height: float, color: Color, rot := 0.0) -> void:
	var bottom := []
	var top := []
	for i in sides:
		var a := rot + TAU * i / sides
		bottom.append(base + Vector3(cos(a) * r_bottom, 0, sin(a) * r_bottom))
		top.append(base + Vector3(cos(a) * r_top, height, sin(a) * r_top))
	for i in sides:
		var j := (i + 1) % sides
		var mid: Vector3 = (bottom[i] + bottom[j]) / 2.0 - base
		if r_top > 0.0:
			face([bottom[i], bottom[j], top[j], top[i]], Vector3(mid.x, 0, mid.z), color)
		else:
			face([bottom[i], bottom[j], base + Vector3(0, height, 0)], Vector3(mid.x, r_bottom / height, mid.z), color)
	if r_top > 0.0:
		face(top, Vector3.UP, color)


func cone(base: Vector3, sides: int, radius: float, height: float, color: Color, rot := 0.0) -> void:
	prism_n(base, sides, radius, 0.0, height, color, rot)


func pyramid(base: Vector3, size: float, height: float, color: Color) -> void:
	prism_n(base, 4, size * 0.7071, 0.0, height, color, PI / 4.0)


## 각진 바위: 20면체를 rng로 흔든다. 중심 center, 반지름 radius, 세로 납작함 squash.
## floor_y 아래로 내려간 꼭짓점은 그 높이로 올린다(땅에 앉은 평평한 밑면).
func rock(center: Vector3, radius: float, color: Color, rng: RandomNumberGenerator, squash := 0.7, floor_y := -INF) -> void:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	var f := [[0,11,5],[0,5,1],[0,1,7],[0,7,10],[0,10,11],[1,5,9],[5,11,4],[11,10,2],[10,7,6],[7,1,8],
		[3,9,4],[3,4,2],[3,2,6],[3,6,8],[3,8,9],[4,9,5],[2,4,11],[6,2,10],[8,6,7],[9,8,1]]
	var pts := []
	for p in v:
		var n: Vector3 = p.normalized() * radius * rng.randf_range(0.8, 1.15)
		pts.append(center + Vector3(n.x, maxf(n.y * squash, floor_y - center.y), n.z))
	for tri_i in f:
		var a: Vector3 = pts[tri_i[0]]
		var b: Vector3 = pts[tri_i[1]]
		var c: Vector3 = pts[tri_i[2]]
		face([a, b, c], (a + b + c) / 3.0 - center, color.darkened(rng.randf_range(0.0, 0.12)))


func commit() -> ArrayMesh:
	_st.generate_normals()
	return _st.commit()

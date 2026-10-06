extends Node3D
## 이동 명령 표시: 영웅이 지금 서 있는 곳 → 남은 경로(hero._path) → 도착지를 바닥에 노란 점선으로 잇고, 도착지에 링을 띄운다.
## 점선 마디는 도착지에서부터 재므로 땅에 붙어 있다(영웅이 걸어도 흐르지 않고 뒤쪽부터 사라진다).
## 영웅이 걸어가면 띠가 줄어들고, 도착하면(또는 새 명령·복귀로 경로가 바뀌거나 쓰러지면) 스스로 사라진다.
## unit_picker가 명령마다 영웅당 하나씩 만든다(이전 것은 지운다). 공성전 꼭두각시(puppet)는 경로를 걷지 않으므로 도착지까지 곧은 선.

const Art := preload("res://scripts/art.gd")

const WIDTH := 0.55  # 띠 폭
const EDGE := 0.18   # 띠·링 가장자리(진한 색) 두께 — 풀밭에서도 보이게
const LIFT := 0.06   # 바닥 위로 띄우는 높이(z-파이팅 방지)
const EDGE_COLOR := Color(0.55, 0.38, 0.02, 0.75)
const ARRIVE_R := 0.45  # 도착지와 이 거리 안이면 도착
const PULSE_HZ := 1.6
const DASH := 0.9  # 점선 한 마디 길이
const GAP := 0.9  # 마디 사이 빈칸

var hero
var dest := Vector3.ZERO

var _line: MeshInstance3D
var _mesh := ImmediateMesh.new()
var _edge_mesh := ImmediateMesh.new()
var _ring: MeshInstance3D
var _t := 0.0


func setup(p_hero, p_dest: Vector3) -> void:
	hero = p_hero
	dest = p_dest


func _ready() -> void:
	top_level = true
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(Art.HERO_SELECTED, 0.85)
	_line = MeshInstance3D.new()
	_line.name = "RouteLine"
	_line.mesh = _mesh
	_line.material_override = mat
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)
	var edge := MeshInstance3D.new()
	edge.name = "RouteEdge"
	edge.mesh = _edge_mesh
	var emat := mat.duplicate() as StandardMaterial3D
	emat.albedo_color = EDGE_COLOR
	emat.render_priority = -1
	edge.material_override = emat
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(edge)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.7
	torus.outer_radius = 1.0
	torus.rings = 24
	_ring = MeshInstance3D.new()
	_ring.name = "RouteDest"
	_ring.mesh = torus
	var rmat := mat.duplicate() as StandardMaterial3D
	rmat.albedo_color = Art.HERO_SELECTED
	_ring.material_override = rmat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	var back := TorusMesh.new()
	back.inner_radius = 0.7 - EDGE
	back.outer_radius = 1.0 + EDGE
	back.rings = 24
	var ring_edge := MeshInstance3D.new()
	ring_edge.mesh = back
	ring_edge.material_override = emat
	ring_edge.scale = Vector3(1.0, 0.5, 1.0)  # 납작하게: 노란 링 아래로만 깔린다
	ring_edge.position.y = -0.04
	ring_edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.add_child(ring_edge)
	_ring.position = dest + Vector3(0, LIFT, 0)
	_update()


func _process(delta: float) -> void:
	_t += delta
	_ring.scale = Vector3.ONE * (1.0 + 0.12 * sin(_t * TAU * PULSE_HZ))
	_update()


## 남은 경로 점들(영웅 위치부터 도착지까지). 표시를 끝낼 때면 빈 배열.
func points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if hero == null or not is_instance_valid(hero) or not hero.is_alive():
		return out
	var pos: Vector3 = hero.global_position
	if Vector2(pos.x - dest.x, pos.z - dest.z).length() <= ARRIVE_R:
		return out
	var path: Array = hero._path
	var puppet: bool = hero.get("puppet") == true
	if not path.is_empty():
		var last: Vector3 = path[path.size() - 1]
		if Vector2(last.x - dest.x, last.z - dest.z).length() > ARRIVE_R:
			return out  # 다른 명령·복귀로 경로가 바뀌었다
	elif not puppet:
		return out  # 걷기를 마쳤다(도착)
	out.append(pos)
	if puppet or path.is_empty():
		out.append(dest)
	else:
		for p in path:
			out.append(p)
	return out


func _update() -> void:
	var pts := points()
	if pts.size() < 2:
		queue_free()
		return
	var dashes := _dashes(pts)
	_strips(_mesh, dashes, WIDTH, 0.0, LIFT)
	_strips(_edge_mesh, dashes, WIDTH + EDGE * 2.0, EDGE, LIFT - 0.02)


## 경로를 점선 마디(각각 점들의 배열)로 자른다. 도착지에서 거꾸로 DASH·GAP을 번갈아 잰다(도착 링 바로 앞은 빈칸).
static func _dashes(pts: Array[Vector3]) -> Array:
	var rev: Array[Vector3] = pts.duplicate()
	rev.reverse()
	var out := []
	var cur: Array[Vector3] = []
	var on := false
	var left := GAP  # 지금 상태(빈칸/마디)에서 남은 길이
	for i in rev.size() - 1:
		var a: Vector3 = rev[i]
		var b: Vector3 = rev[i + 1]
		var seg := Vector2(b.x - a.x, b.z - a.z).length()
		var t := 0.0
		while seg - t > left:
			t += left
			var p := a.lerp(b, t / seg)
			if on:
				cur.append(p)
				out.append(cur)
				cur = []
			else:
				cur = [p]
			on = not on
			left = DASH if on else GAP
		left -= seg - t
		if on:
			cur.append(b)
	if on and cur.size() >= 2:
		out.append(cur)
	return out


static func _strips(mesh: ImmediateMesh, dashes: Array, w: float, ext: float, lift: float) -> void:
	var verts: Array[Vector3] = []
	for d in dashes:
		_strip(verts, d, w, ext, lift)
	mesh.clear_surfaces()
	if verts.is_empty():
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in verts:
		mesh.surface_add_vertex(v)
	mesh.surface_end()


## 점들을 잇는 바닥 띠(폭 w, 높이 lift)의 삼각형을 verts에 붙인다. 꺾이는 곳에 빈틈이 없게 각 토막을 반 폭만큼 늘이고,
## 양 끝은 ext만큼 더 늘인다(가장자리 띠가 노란 마디를 감싸게).
static func _strip(verts: Array[Vector3], pts: Array, w: float, ext: float, lift: float) -> void:
	var up := Vector3(0, lift, 0)
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
		if d.length() < 0.01:
			continue
		var dir := d.normalized()
		var side := Vector3(-dir.z, 0.0, dir.x) * (w / 2.0)
		if i > 0:
			a -= dir * (w / 2.0)
		else:
			a -= dir * ext
		if i == pts.size() - 2:
			b += dir * ext
		var a0 := a + up - side
		var a1 := a + up + side
		var b0 := b + up - side
		var b1 := b + up + side
		verts.append_array([a0, b0, b1, a0, b1, a1])

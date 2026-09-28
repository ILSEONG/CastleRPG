extends RefCounted
## 단색 플랫 메시 헬퍼와 팔레트. 모든 플레이스홀더 지오메트리는 여기로.

const WALL := Color(0.86, 0.84, 0.78)
const TOWER := Color(0.78, 0.76, 0.70)
const GATE := Color(0.55, 0.38, 0.22)
const HERO_SELECTED := Color(1.0, 0.9, 0.2)
const ARROW := Color(0.30, 0.22, 0.14)


static func mesh(m: Mesh, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mi.mesh = m
	mi.material_override = mat
	return mi


## 바닥이 y=0에 닿는 박스.
static func box(size: Vector3, color: Color) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := mesh(bm, color)
	mi.position.y = size.y / 2.0
	return mi


## 바닥이 y=0에 닿는 캡슐. height는 전체 높이.
static func capsule(radius: float, height: float, color: Color) -> MeshInstance3D:
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = height
	var mi := mesh(cm, color)
	mi.position.y = height / 2.0
	return mi

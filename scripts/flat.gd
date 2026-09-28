extends RefCounted
## 단색 플랫 메시 헬퍼와 팔레트. 모든 플레이스홀더 지오메트리는 여기로.

const GROUND := Color(0.72, 0.80, 0.62)
const WALL := Color(0.80, 0.78, 0.72)
const GATE := Color(0.55, 0.38, 0.22)
const KEEP := Color(0.62, 0.64, 0.72)
const HERO := Color(0.25, 0.55, 0.95)
const HERO_SELECTED := Color(1.0, 0.9, 0.2)


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

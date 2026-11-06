extends RefCounted
## Meshy 손그림 소품(맵 새로 만들기 2026-11-06, dev/meshy/map_props.py → dev/meshy_decimate.py → assets/models/meshy/props/<이름>.glb).
## 소품 메시는 바닥(y = 0)에 앉고 가로 가운데가 원점, 키가 HEIGHT[이름] m가 되게 정점을 옮겨 구운 ArrayMesh(표면 재질 = 질감)다 —
## MultiMesh에 그대로 넣는다(material_override 없이: 메시에 "prop" 메타). 참고: Rise of Kingdoms·Lords Mobile 맵 소품.
## TownKit 레시피와 같은 이름(tree_pine·tree_round·bush·rock_cluster)이라 계절(seasons.gd PALETTES)이 같은 팔레트로 바꿔 부른다:
## 침엽수 snow → 눈 덮인 침엽수, 활엽수 bare → 앙상한 나무, 잎색이 분홍 → 벚꽃, 주황·빨강 → 단풍.

const DIR := "res://assets/models/meshy/props/"
const HEIGHT := {
	"pine": 7.0, "snow_pine": 7.0, "oak": 5.6, "autumn_oak": 5.6, "blossom": 5.2, "bare_tree": 5.2, "bush": 1.6, "flower_bush": 1.2,
	"rock_big": 2.4, "rock_small": 0.8, "cliff": 9.0, "gold_ore": 1.6, "mine_cart": 1.7, "crystal": 2.4, "ruin_column": 1.6,
	"lion_statue": 3.4, "stone_lantern": 2.4, "broken_pillar": 5.0, "brazier": 1.6, "rubble": 1.5, "obsidian": 8.0, "treasure": 2.6,
	"tombstone": 1.6, "web_tree": 4.5, "egg_sacs": 1.3,
}

static var _cache := {}


## 이름 소품 메시(키 height m, 없으면 HEIGHT). 처음 부를 때 glb를 읽어 굽고 캐시한다.
static func mesh(name: String, height := -1.0) -> ArrayMesh:
	var h: float = height if height > 0.0 else HEIGHT.get(name, 2.0)
	var key := "%s@%.2f" % [name, h]
	if _cache.has(key):
		return _cache[key]
	var scene: Node = (load(DIR + name + ".glb") as PackedScene).instantiate()
	var src: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
	var xf: Transform3D = Transform3D.IDENTITY
	var n: Node = src
	while n != scene and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	var aabb: AABB = xf * src.mesh.get_aabb()
	var s := h / maxf(aabb.size.y, 0.001)
	var c := aabb.get_center()
	var fit := Transform3D(Basis().scaled(Vector3.ONE * s), Vector3(-c.x * s, -aabb.position.y * s, -c.z * s)) * xf
	var out := ArrayMesh.new()
	for i in src.mesh.get_surface_count():
		var arr: Array = src.mesh.surface_get_arrays(i)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for j in vs.size():
			vs[j] = fit * vs[j]
		arr[Mesh.ARRAY_VERTEX] = vs
		if arr[Mesh.ARRAY_NORMAL] != null:
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for j in ns.size():
				ns[j] = (fit.basis * ns[j]).normalized()
			arr[Mesh.ARRAY_NORMAL] = ns
		arr[Mesh.ARRAY_TANGENT] = null
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var m: Material = src.get_active_material(i)
		if m is BaseMaterial3D:
			m = m.duplicate()
			m.roughness = 1.0
			m.metallic = 0.0
			m.metallic_specular = 0.2
		out.surface_set_material(i, m)
	out.set_meta("prop", true)
	scene.free()
	_cache[key] = out
	return out


## 레시피(TownKit과 같은 이름·인자): 계절 팔레트 pal에 따라 모델을 고른다. rng는 크기만 조금 흔든다(같은 상태면 같은 메시).
static func tree_pine(rng: RandomNumberGenerator, pal := {}) -> ArrayMesh:
	var h := rng.randf_range(6.0, 8.0)
	return mesh("snow_pine" if pal.get("snow", false) else "pine", snappedf(h, 0.5))


static func tree_round(rng: RandomNumberGenerator, pal := {}) -> ArrayMesh:
	var h := snappedf(rng.randf_range(4.8, 6.2), 0.4)
	if pal.get("bare", false):
		return mesh("bare_tree", h)
	var leaf: Color = pal.get("leaf", Color(0.36, 0.60, 0.34))
	if leaf.r > leaf.g and leaf.b > 0.4:
		return mesh("blossom", h)
	if leaf.r > leaf.g:
		return mesh("autumn_oak", h)
	return mesh("oak", h)


static func bush(rng: RandomNumberGenerator, _pal := {}) -> ArrayMesh:
	return mesh("flower_bush" if rng.randf() < 0.4 else "bush")


static func rock_cluster(rng: RandomNumberGenerator, _pal := {}) -> ArrayMesh:
	return mesh("rock_big", snappedf(rng.randf_range(1.8, 2.8), 0.5)) if rng.randf() < 0.7 else mesh("rock_small", 0.8)


## 재질 색을 tint로 곱한 사본(같은 메시 배열 공유).
static func tinted(name: String, tint: Color) -> ArrayMesh:
	var key := "%s#%s" % [name, tint.to_html()]
	if _cache.has(key):
		return _cache[key]
	var src := mesh(name)
	var out: ArrayMesh = src.duplicate()
	for i in out.get_surface_count():
		var m: Material = out.surface_get_material(i)
		if m is BaseMaterial3D:
			m = m.duplicate()
			m.albedo_color = m.albedo_color * tint
			out.surface_set_material(i, m)
	out.set_meta("prop", true)
	_cache[key] = out
	return out

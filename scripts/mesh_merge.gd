extends RefCounted
## 캐릭터 메시 합치기(그리기 호출 줄이기): KayKit 모델은 몸이 부위마다 스킨 메시(팔·다리·몸·머리 6~9개, 같은 스켈레톤·같은 Skin)이고
## 모자·망토·무기·코드 부품은 뼈 부착(BoneAttachment3D) 아래 단단한 메시다. 캐릭터 하나가 10개 안팎의 그리기라 유닛이 많으면
## 모바일 GPU가 그리기 호출에서 막힌다. merge()는 보이는 메시를 스킨 메시 하나(재질마다 표면 하나)로 합친다:
##  - 스킨 부위: 정점 배열을 그대로 잇는다(같은 Skin — 뼈 번호가 같다).
##  - 단단한 부위: 뼈 rest 공간으로 옮기고(rest × 부착 안 변환) 그 뼈에 가중치 1로 묶는다(Skin에 bind = rest⁻¹를 더한다) —
##    움직이는 뼈를 그대로 따라간다(pose × rest⁻¹ × rest × 부착 변환 = pose × 부착 변환, 부착과 같다).
## 합친 메시는 원래 메시처럼 자동 LOD를 만든다(ImporterMesh.generate_lods). 합친 메시·Skin은 키(UnitModel 스펙)마다 한 번 만들어 같은 모습의 유닛이 공유한다. 원래 메시 노드와 빈 부착 노드는 지운다.
## 합치지 않는 것: 숨긴 메시, 그림자 설정이 기본이 아닌 메시(빛 부품 등), material_overlay, 삼각형이 아닌 표면, 8가중치 표면,
## 다른 Skin·변환을 가진 스킨 메시, 뼈 부착 밖 메시 — 그대로 남아 따로 그려진다.

const Art := preload("res://scripts/art.gd")

const ARRAYS := [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]

static var _cache := {}  # 키 → {mesh: ArrayMesh, skin: Skin}
static var enabled := true  # 테스트·비교용으로 끌 수 있다


## model 안 스켈레톤의 메시를 합친다(트리 밖에서도 된다). 합칠 것이 둘 미만이면 아무것도 안 한다. 합쳤으면 true.
static func merge(model: Node3D, key: String) -> bool:
	if not enabled:
		return false
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return false
	var skel := skels[0] as Skeleton3D
	var parts := _parts(model, skel)
	if parts.size() < 2:
		return false
	var built = _cache.get(key)
	if built == null:
		built = _build(skel, parts)
		if built == null:
			return false
		_cache[key] = built
	var mi := MeshInstance3D.new()
	mi.name = "Merged"
	mi.mesh = built.mesh
	mi.skin = built.skin
	skel.add_child(mi)
	mi.skeleton = NodePath("..")
	for p in parts:
		p.get_parent().remove_child(p)
		p.queue_free()
	for c in skel.get_children():  # 비게 된 뼈 부착은 매 프레임 따라 움직일 필요가 없다
		if c is BoneAttachment3D and c.get_child_count() == 0:
			skel.remove_child(c)
			c.queue_free()
	return true


## 합칠 메시들(스킨 부위 먼저, 노드 순서). 같은 Skin을 쓰는 스킨 부위가 하나도 없으면 [].
static func _parts(model: Node3D, skel: Skeleton3D) -> Array:
	var skin: Skin = null
	var skinned := []
	var rigid := []
	for n in skel.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not _shown(mi, model) or mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
				or mi.material_overlay != null or not _plain_surfaces(mi):
			continue
		if mi.skin != null:
			if mi.get_parent() != skel or not mi.transform.is_equal_approx(Transform3D.IDENTITY) or (skin != null and mi.skin != skin):
				continue
			skin = mi.skin
			skinned.append(mi)
		elif _bone_of(mi, skel) >= 0:
			rigid.append(mi)
	return [] if skin == null else skinned + rigid


static func _shown(n: Node, root: Node) -> bool:
	while n != null and n != root:
		if n is Node3D and not (n as Node3D).visible:
			return false
		n = n.get_parent()
	return true


static func _plain_surfaces(mi: MeshInstance3D) -> bool:
	for s in mi.mesh.get_surface_count():
		if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES or mi.mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS \
				or mi.get_active_material(s) == null:
			return false
	return true


## 단단한 메시가 매달린 뼈 번호(가장 가까운 BoneAttachment3D의 bone_name). 없으면 -1.
static func _bone_of(mi: Node, skel: Skeleton3D) -> int:
	var n := mi.get_parent()
	while n != null and n != skel:
		if n is BoneAttachment3D:
			return skel.find_bone((n as BoneAttachment3D).bone_name)
		n = n.get_parent()
	return -1


static func _attachment_of(mi: Node, skel: Skeleton3D) -> Node3D:
	var n := mi.get_parent()
	while n != null and n != skel:
		if n is BoneAttachment3D:
			return n
		n = n.get_parent()
	return null


## 합친 ArrayMesh(재질·배열 구성마다 표면 하나)와 Skin(원래 bind + 단단한 부위마다 bind 하나).
static func _build(skel: Skeleton3D, parts: Array) -> Variant:
	var base: Skin = parts[0].skin
	var skin: Skin = base.duplicate()
	var named := base.get_bind_count() > 0 and base.get_bind_name(0) != &""
	var groups := {}  # 재질 id|배열 구성 → {mat, arrays}
	var order := []
	for p in parts:
		var mi := p as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var bind := -1
		if mi.skin == null:
			var b := _bone_of(mi, skel)
			var rest := skel.get_bone_global_rest(b)
			xf = rest * Art.relative_transform(mi, _attachment_of(mi, skel))
			bind = skin.get_bind_count()
			if named:
				skin.add_named_bind(skel.get_bone_name(b), rest.affine_inverse())
			else:
				skin.add_bind(b, rest.affine_inverse())
		for s in mi.mesh.get_surface_count():
			var a: Array = mi.mesh.surface_get_arrays(s)
			if bind >= 0:
				a = _rigid(a, xf, bind)
			var mat := mi.get_active_material(s)
			var sig := ""
			for k in ARRAYS:
				sig += "1" if a[k] != null else "0"
			var gk := "%d|%s" % [mat.get_instance_id(), sig]
			if not groups.has(gk):
				groups[gk] = {"mat": mat, "arrays": _empty(a)}
				order.append(gk)
			_append(groups[gk].arrays, a)
	# 원래 glb 메시는 가져올 때 자동 LOD가 있어 멀리 있는 유닛은 적은 삼각형으로 그린다 — 합친 메시도 LOD를 만든다(가져오기와 같은
	# 법선 합치기 각 60°). 안 그러면 그리기 호출은 줄어도 그리는 삼각형이 두 배가 된다. LOD 생성이 없는 빌드면 LOD 없이 그대로.
	var im := ImporterMesh.new()
	for gk in order:
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, groups[gk].arrays, [], {}, groups[gk].mat)
	im.generate_lods(60.0, 25.0, [])
	return {"mesh": im.get_mesh(), "skin": skin}


## 단단한 표면 → 스킨 표면: 정점·법선·접선을 xf로 옮기고 모든 정점을 bind 하나에 가중치 1로 묶는다.
static func _rigid(src: Array, xf: Transform3D, bind: int) -> Array:
	var a := src.duplicate()
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var out := PackedVector3Array()
	out.resize(v.size())
	for i in v.size():
		out[i] = xf * v[i]
	a[Mesh.ARRAY_VERTEX] = out
	var nb := xf.basis.inverse().transposed()
	if a[Mesh.ARRAY_NORMAL] != null:
		var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var on := PackedVector3Array()
		on.resize(n.size())
		for i in n.size():
			on[i] = (nb * n[i]).normalized()
		a[Mesh.ARRAY_NORMAL] = on
	if a[Mesh.ARRAY_TANGENT] != null:
		var t: PackedFloat32Array = a[Mesh.ARRAY_TANGENT]
		var ot := t.duplicate()
		for i in t.size() / 4:
			var d := (xf.basis * Vector3(t[i * 4], t[i * 4 + 1], t[i * 4 + 2])).normalized()
			ot[i * 4] = d.x
			ot[i * 4 + 1] = d.y
			ot[i * 4 + 2] = d.z
		a[Mesh.ARRAY_TANGENT] = ot
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	bones.resize(v.size() * 4)
	weights.resize(v.size() * 4)
	for i in v.size():
		bones[i * 4] = bind
		weights[i * 4] = 1.0
	a[Mesh.ARRAY_BONES] = bones
	a[Mesh.ARRAY_WEIGHTS] = weights
	return a


## 같은 구성의 빈 배열 묶음.
static func _empty(a: Array) -> Array:
	var e := []
	e.resize(Mesh.ARRAY_MAX)
	for k in ARRAYS + [Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		if a[k] != null:
			e[k] = (a[k] as Variant).duplicate()
			e[k].resize(0)
	e[Mesh.ARRAY_INDEX] = PackedInt32Array()
	return e


## dst 끝에 src를 잇는다(인덱스는 정점 수만큼 밀고, 없으면 0..n-1).
static func _append(dst: Array, src: Array) -> void:
	var base: int = (dst[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var n: int = (src[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for k in ARRAYS + [Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		if dst[k] != null:
			var x = dst[k]  # 꾸러미 배열은 값 — 꺼내서 늘리고 다시 넣는다
			x.append_array(src[k])
			dst[k] = x
	var idx: PackedInt32Array = dst[Mesh.ARRAY_INDEX]
	if src[Mesh.ARRAY_INDEX] != null:
		for i in src[Mesh.ARRAY_INDEX]:
			idx.append(base + i)
	else:
		for i in n:
			idx.append(base + i)
	dst[Mesh.ARRAY_INDEX] = idx

extends RefCounted
## 코드로 만든 캐릭터 몸(시제품): KayKit 뼈대(다섯 모델·해골 공통 41뼈)에 부위 조각을 뼈마다 단단하게 붙인다 — 애니메이션·무기·타격 시점은
## KayKit 그대로, 몸·머리·옷·갑옷만 새로 그린다. KayKit 몸 메시(팔·다리·몸·머리·투구·망토)는 숨기고 손 무기(handslot 아래)는 둔다.
## 조각은 휴식 자세(T자) 스켈레톤 공간 좌표로 그린다: 발바닥 y 0, 얼굴 앞 +Z, 캐릭터 왼쪽 +X. 뼈 원점 — hips 0.41, spine 0.60,
## chest 0.97, head 1.24, 어깨(upperarm) ±0.21·1.11, 팔꿈치 ±0.45, 손목 ±0.71, 손 ±0.79, 엉덩이(upperleg) ±0.17·0.52, 무릎 0.29,
## 발목 0.15, 발가락 z 0.10. 얼굴 = HEAD_C 중심 타원체(KayKit 머리와 같은 크기 — 큰 머리 2.5등신).
## 뼈마다 MeshKit 하나에 휴식 변환의 역을 곱해 굽는다(BoneAttachment3D가 그 뼈를 따라간다). 같은 재질이라 MeshMerge가 스킨 메시 하나로 합친다.
## 몸마다 뼈 → 메시를 한 번 만들어 공유한다. 오토로드 참조 없음.

const Art := preload("res://scripts/art.gd")
const MeshKit := preload("res://scripts/mesh_kit.gd")

const BODIES := ["arteon", "luna", "hans", "grunt"]
const HEAD_C := Vector3(0, 1.72, 0.04)
const HEAD_R := Vector3(0.44, 0.43, 0.42)
const SKIN := Color("FFD2B0")
const EYE := Color("2B2A44")

static var enabled := true  # 끄면 스펙에 body가 있어도 KayKit 몸 그대로(비교·테스트)
static var _cache := {}  # 몸 id → {뼈 이름: ArrayMesh}


## 뼈마다 조각을 모으는 도구: on(뼈, 지역 변환)이 그 뼈의 MeshKit을 돌려주고 xform을 (휴식⁻¹ × 지역)으로 맞춘다 —
## 그 뒤 도형 좌표는 지역 공간(기본 = 스켈레톤 공간).
class Rig:
	const MeshKit := preload("res://scripts/mesh_kit.gd")
	var skel: Skeleton3D
	var kits := {}

	func _init(s: Skeleton3D) -> void:
		skel = s

	func on(bone: String, local := Transform3D.IDENTITY):
		if not kits.has(bone):
			kits[bone] = MeshKit.new()
		var k = kits[bone]
		k.xform = skel.get_bone_global_rest(skel.find_bone(bone)).affine_inverse() * local
		return k

	func commit() -> Dictionary:
		var out := {}
		for b in kits:
			out[b] = kits[b].commit()
		return out


static func has_body(id: String) -> bool:
	return BODIES.has(id)


## 몸 id의 뼈 이름 → 메시(한 번 만들어 공유).
static func meshes(skel: Skeleton3D, body: String) -> Dictionary:
	if not _cache.has(body):
		var r := Rig.new(skel)
		match body:
			"arteon": _arteon(r)
			"luna": _luna(r)
			"hans": _hans(r)
			"grunt": _grunt(r)
		_cache[body] = r.commit()
	return _cache[body]


## KayKit 모델의 몸 메시를 숨기고 body 조각을 뼈마다 붙인다(UnitModel.dress가 부품·재질보다 먼저 부른다).
static func dress(model: Node3D, skel: Skeleton3D, body: String) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if not str(mi.get_parent().name).begins_with("handslot"):
			mi.visible = false
	var parts := meshes(skel, body)
	for bone in parts:
		var slot := BoneAttachment3D.new()
		slot.name = "body_" + bone
		slot.bone_name = bone
		skel.add_child(slot)
		var mi := MeshInstance3D.new()
		mi.name = body + "_" + bone
		mi.mesh = parts[bone]
		mi.material_override = Art.lowpoly_vc_material()
		slot.add_child(mi)


# --- 도형(좌표 = 지역 공간). 면 방향은 단면 돌림 방향으로 정한다(v = u × 축이라 축이 어디를 향해도 같다) ---

## 축 d에 수직인 단면 축 [u, v].
static func _frame(d: Vector3) -> Array:
	d = d.normalized()
	var u := Vector3.RIGHT if absf(d.y) >= 0.7 else Vector3.UP
	u = (u - d * u.dot(d)).normalized()
	return [u, u.cross(d)]


## 타원 n각 단면(반지름 0이면 점 하나 — 뾰족한 끝).
static func _ring(c: Vector3, u: Vector3, v: Vector3, r: Vector2, n: int, rot: float) -> Array:
	if r.x < 0.0005 and r.y < 0.0005:
		return [c]
	var pts := []
	for i in n:
		var t := rot + TAU * i / n
		pts.append(c + u * cos(t) * r.x + v * sin(t) * r.y)
	return pts


## 단면 고리들을 차례로 잇는다. color = 색 하나 또는 띠마다 색. 양 끝(점이 아니면)은 막는다.
static func _loft(k, rings: Array, color, closed := true) -> void:
	for b in rings.size() - 1:
		var col: Color = color[mini(b, color.size() - 1)] if color is Array else color
		var p: Array = rings[b]
		var q: Array = rings[b + 1]
		var m := maxi(p.size(), q.size())
		for i in (m if closed else m - 1):
			var j := (i + 1) % m
			var a: Vector3 = p[i % p.size()]
			var bb: Vector3 = p[j % p.size()]
			var c: Vector3 = q[j % q.size()]
			var d: Vector3 = q[i % q.size()]
			var out := (d - bb).cross(c - a)
			if p.size() == 1:
				k.face([a, c, d], out, col)
			elif q.size() == 1:
				k.face([a, bb, c], out, col)
			else:
				k.face([a, bb, c, d], out, col)
	if not closed:
		return
	var first: Array = rings[0]
	var last: Array = rings[-1]
	var c0 := _centroid(first)
	var c1 := _centroid(last)
	if first.size() > 2:
		k.face(first, c0 - _centroid(rings[1]), color[0] if color is Array else color)
	if last.size() > 2:
		k.face(last, c1 - _centroid(rings[-2]), color[-1] if color is Array else color)


static func _centroid(pts: Array) -> Vector3:
	var s := Vector3.ZERO
	for p in pts:
		s += p
	return s / pts.size()


## 덩어리: path = 단면 중심(차례로), radii = 단면 반지름(Vector2 — 세로 축이면 (x, z), 가로 팔이면 (y, z), 앞뒤 축이면 (y, x)), n각.
static func _tube(k, path: Array, radii: Array, n: int, color, rot := 0.0) -> void:
	var f := _frame(path[-1] - path[0])
	var rings := []
	for i in path.size():
		rings.append(_ring(path[i], f[0], f[1], radii[i], n, rot))
	_loft(k, rings, color)


## 타원체: 중심 c, 반지름 r, n각 × rings단. lat0~lat1(도)만 — 0~90이면 위 반구(바닥을 막은 돔).
static func _ball(k, c: Vector3, r: Vector3, n: int, rings: int, color, lat0 := -90.0, lat1 := 90.0, rot := 0.0) -> void:
	var path := []
	var radii := []
	for i in rings + 1:
		var lat := deg_to_rad(lerpf(lat0, lat1, float(i) / rings))
		path.append(c + Vector3(0, sin(lat) * r.y, 0))
		radii.append(Vector2(cos(lat) * r.x, cos(lat) * r.z))
	_tube(k, path, radii, n, color, rot)


## 세로 축 둘레의 일부(a0~a1 도 — 0 = +X, 90 = 앞 +Z)만 두른 두께 thick 껍데기: 투구 옆·뒤, 머리카락, 두건, 어깨 망토, 갈비뼈.
## path = 단면 중심(아래 → 위), radii = 바깥 반지름(x, z). jag = 아래 끝을 한 칸씩 이만큼 내려 톱니(누더기·머리끝).
static func _shell(k, path: Array, radii: Array, a0: float, a1: float, n: int, thick: float, color: Color, inner: Color, jag := 0.0) -> void:
	var outer := []
	var inn := []
	for i in path.size():
		var o := []
		var w := []
		var rr: Vector2 = radii[i]
		for s in n + 1:
			var t := deg_to_rad(lerpf(a0, a1, float(s) / n))
			var c: Vector3 = path[i] - Vector3(0, jag * (s % 2) if i == 0 else 0.0, 0)
			o.append(c + Vector3(cos(t) * rr.x, 0, sin(t) * rr.y))
			w.append(c + Vector3(cos(t) * maxf(rr.x - thick, 0.0), 0, sin(t) * maxf(rr.y - thick, 0.0)))
		outer.append(o)
		w.reverse()
		inn.append(w)
	_loft(k, outer, color, false)
	_loft(k, inn, inner, false)
	var down: Vector3 = path[0] - path[1]
	var up: Vector3 = path[-1] - path[-2]
	for s in n:
		var r := n - s  # 안쪽 고리는 거꾸로 담았다
		k.face([outer[0][s], outer[0][s + 1], inn[0][r - 1], inn[0][r]], down, inner)
		if radii[-1].x > thick:
			k.face([outer[-1][s], outer[-1][s + 1], inn[-1][r - 1], inn[-1][r]], up, color)
	var t0 := deg_to_rad(a0)
	var t1 := deg_to_rad(a1)
	for i in path.size() - 1:
		k.face([outer[i][0], outer[i + 1][0], inn[i + 1][n], inn[i][n]], Vector3(sin(t0), 0, -cos(t0)), inner)
		k.face([outer[i][n], outer[i + 1][n], inn[i + 1][0], inn[i][0]], Vector3(-sin(t1), 0, cos(t1)), inner)


## 볼록 다각형 판(둘레 순서, 대략 평면) — 면 법선을 hint 쪽으로 두고 두께 thick(가운데 기준). back = 뒷면 색.
static func _plate(k, outline: Array, hint: Vector3, thick: float, color: Color, back = null) -> void:
	var nrm := Vector3.ZERO
	for i in outline.size():  # Newell
		var a: Vector3 = outline[i]
		var b: Vector3 = outline[(i + 1) % outline.size()]
		nrm += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
	nrm = nrm.normalized()
	if nrm.dot(hint) < 0.0:
		nrm = -nrm
	var h := nrm * thick / 2.0
	var front := []
	var rear := []
	for p in outline:
		front.append(p + h)
		rear.append(p - h)
	k.face(front, nrm, color)
	k.face(rear, -nrm, back if back != null else color)
	var c := _centroid(outline)
	for i in outline.size():
		var j := (i + 1) % outline.size()
		var mid: Vector3 = (outline[i] + outline[j]) / 2.0 - c
		k.face([front[i], front[j], rear[j], rear[i]], mid - nrm * mid.dot(nrm), color)


## 상자: 중심 center, 크기 size, 돌림 basis.
static func _box(k, center: Vector3, size: Vector3, color: Color, basis := Basis.IDENTITY) -> void:
	var hx := basis.x * size.x / 2.0
	var hy := basis.y * size.y / 2.0
	_plate(k, [center - hx - hy, center + hx - hy, center + hx + hy, center - hx + hy], basis.z, size.z, color)


## 잎(깃털·날개깃·칼날): a → b, 폭 w, 면 방향 face_dir 쪽.
static func _leaf(k, a: Vector3, b: Vector3, w: float, thick: float, face_dir: Vector3, color: Color) -> void:
	var d := b - a
	var nrm := (face_dir - d.normalized() * face_dir.dot(d.normalized())).normalized()
	var side := d.cross(nrm).normalized() * w / 2.0
	_plate(k, [a, a + d * 0.4 + side, b, a + d * 0.4 - side], nrm, thick, color)


## 등 망토(가슴 뼈): 세 판(가운데 + 앞으로 감싼 양옆)으로 굽힌 천 + 아래 끝단(trim). 위 폭 tw·아래 폭 bw(반폭), 위 y0·z0 → 아래 y1·z1.
static func _cape(k, y0: float, z0: float, tw: float, y1: float, z1: float, bw: float, color: Color, trim: Color) -> void:
	var fs := [-1.0, -0.34, 0.34, 1.0]
	var top := []
	var bot := []
	var hem := []
	for f in fs:
		var bend: float = 0.13 * f * f
		top.append(Vector3(f * tw, y0, z0 + bend * 0.6))
		bot.append(Vector3(f * bw, y1, z1 + bend))
		hem.append(Vector3(f * bw * 1.01, y1 + 0.08, z1 + bend - 0.01))
	for i in 3:
		_plate(k, [top[i], top[i + 1], bot[i + 1], bot[i]], Vector3.FORWARD, 0.05, color, color.darkened(0.3))
		_plate(k, [hem[i], hem[i + 1], bot[i + 1] + Vector3(0, -0.01, -0.012), bot[i] + Vector3(0, -0.01, -0.012)], Vector3.FORWARD, 0.07, trim)


## 얼굴 위 점: 얼굴 타원체 표면(x, y)에서 off만큼 앞.
static func _on_face(x: float, y: float, off: float) -> Vector3:
	var q := 1.0 - pow(x / HEAD_R.x, 2.0) - pow((y - HEAD_C.y) / HEAD_R.y, 2.0)
	return Vector3(x, y, HEAD_C.z + HEAD_R.z * sqrt(maxf(q, 0.0)) * 0.97 + off)


static func _mirror(v: Vector3, s: float) -> Vector3:
	return Vector3(v.x * s, v.y, v.z)


# --- 공통 부위 ---

## 머리 공통(머리 뼈): 목, 얼굴, 큰 눈(빛점), 눈썹(brow가 null이면 없음), 입, 볼 홍조, 속눈썹(lashes).
static func _head(r, skin: Color, eye: Color, brow, mouth := true, lashes := false) -> void:
	var h = r.on("head")
	_tube(h, [Vector3(0, 1.18, 0), Vector3(0, 1.42, 0.01)], [Vector2(0.15, 0.14), Vector2(0.15, 0.14)], 8, skin)
	_ball(h, HEAD_C, HEAD_R, 12, 6, skin)
	for s in [-1.0, 1.0]:
		var e := _on_face(s * 0.165, 1.655, 0.0)
		_tube(h, [e - Vector3(0, 0, 0.07), e + Vector3(0, 0, 0.03)], [Vector2(0.088, 0.058), Vector2(0.084, 0.054)], 8, eye)
		var g := e + Vector3(0.025, 0.035, 0.0)
		_tube(h, [g, g + Vector3(0, 0, 0.045)], [Vector2(0.028, 0.024), Vector2(0.026, 0.022)], 6, Color.WHITE)
		if brow != null:
			_box(h, _on_face(s * 0.17, 1.785, 0.0), Vector3(0.13, 0.035, 0.05), brow, Basis(Vector3.BACK, s * 0.12))
		if lashes:
			_box(h, _on_face(s * 0.225, 1.72, 0.01), Vector3(0.07, 0.03, 0.04), eye, Basis(Vector3.BACK, s * 0.5))
		var b := _on_face(s * 0.27, 1.555, -0.012)
		_tube(h, [b, b + Vector3(s * 0.008, 0, 0.03)], [Vector2(0.032, 0.055), Vector2(0.03, 0.05)], 6, skin.lerp(Color("FF8A8A"), 0.45))
	if mouth:
		_box(h, _on_face(0.0, 1.5, -0.005), Vector3(0.08, 0.022, 0.04), Color("8A3A34"))


## 팔 공통(T자: 어깨 ±0.21 → 팔꿈치 ±0.45 → 손목 ±0.71 → 손 ±0.79, 높이 1.107): 위팔, 팔꿈치(null이면 없음), 아래팔(손목 쪽이 굵다),
## 소매 끝(null이면 없음), 주먹. fore_flare = 손목 쪽 반지름 배율(무희 소매).
static func _arms(r, upper: Color, elbow, fore: Color, cuff, hand: Color, w := 1.0, fore_flare := 1.0) -> void:
	var y := 1.107
	for s in [-1.0, 1.0]:
		var side := ".l" if s > 0 else ".r"
		_tube(r.on("upperarm" + side), [Vector3(s * 0.24, y, 0), Vector3(s * 0.47, y, -0.005)],
			[Vector2(0.12, 0.12) * w, Vector2(0.105, 0.105) * w], 8, upper)
		var la = r.on("lowerarm" + side)
		if elbow != null:
			_ball(la, Vector3(s * 0.455, y, -0.012), Vector3(0.12, 0.12, 0.12) * w, 8, 4, elbow)
		_tube(la, [Vector3(s * 0.45, y, -0.012), Vector3(s * 0.7, y, 0)], [Vector2(0.1, 0.1) * w, Vector2(0.118, 0.118) * w * fore_flare], 8, fore)
		if cuff != null:
			_tube(la, [Vector3(s * 0.645, y, 0), Vector3(s * 0.72, y, 0)], [Vector2(0.132, 0.132) * w * fore_flare, Vector2(0.138, 0.138) * w * fore_flare], 8, cuff)
		_ball(r.on("hand" + side), Vector3(s * 0.81, y - 0.02, 0.0), Vector3(0.1, 0.115, 0.115) * w, 8, 4, hand)


## 다리 공통(엉덩이 ±0.17·0.52 → 무릎 0.29 → 발목 0.15): 허벅지, 무릎(null이면 없음), 정강이, 장화 목(cuff, null이면 없음), 발(뒤꿈치 → 발끝).
static func _legs(r, thigh: Color, knee, shin: Color, cuff, boot: Color, toe: Color, w := 1.0) -> void:
	for s in [-1.0, 1.0]:
		var side := ".l" if s > 0 else ".r"
		var x: float = s * 0.171
		_tube(r.on("upperleg" + side), [Vector3(x, 0.6, 0), Vector3(x, 0.28, 0.005)], [Vector2(0.125, 0.13) * w, Vector2(0.108, 0.112) * w], 8, thigh)
		var ll = r.on("lowerleg" + side)
		if knee != null:
			_ball(ll, Vector3(x, 0.29, 0.035), Vector3(0.115, 0.1, 0.105) * w, 8, 4, knee)
		_tube(ll, [Vector3(x, 0.3, 0.0), Vector3(x, 0.11, -0.012)], [Vector2(0.098, 0.102) * w, Vector2(0.108, 0.112) * w], 8, shin)
		if cuff != null:
			_tube(ll, [Vector3(x, 0.15, -0.012), Vector3(x, 0.245, -0.008)], [Vector2(0.125, 0.13) * w, Vector2(0.13, 0.135) * w], 8, cuff)
		_tube(r.on("foot" + side), [Vector3(x, 0.085, -0.13), Vector3(x, 0.092, 0.0), Vector3(x, 0.07, 0.15), Vector3(x, 0.048, 0.22)],
			[Vector2(0.085, 0.1), Vector2(0.092, 0.115), Vector2(0.07, 0.11), Vector2(0.034, 0.075)], 8, [boot, boot, toe])


## 앞이 열린 머리카락(옆·뒤, 머리끝 톱니) + 정수리 돔 + 앞머리 가닥. bottom = 뒷머리 끝 높이, bangs = 앞머리 가닥 x 위치들.
static func _hair(h, color: Color, bottom: float, open_deg: float, bangs: Array, bang_len := 0.13) -> void:
	_ball(h, Vector3(0, 1.79, -0.02), Vector3(0.485, 0.44, 0.485), 12, 4, color, 0.0, 90.0)
	_shell(h, [Vector3(0, bottom, -0.04), Vector3(0, (bottom + 1.8) / 2.0, -0.03), Vector3(0, 1.8, -0.02)],
		[Vector2(0.47, 0.47), Vector2(0.5, 0.5), Vector2(0.49, 0.49)], 90.0 + open_deg, 450.0 - open_deg, 12, 0.07, color, color.darkened(0.3), 0.06)
	for x in bangs:
		var top := _on_face(x, 1.84, 0.02)
		var tip := _on_face(x * 1.08, 1.84 - bang_len, 0.035)
		_plate(h, [top + Vector3(-0.1, 0, 0), top + Vector3(0.1, 0, 0), tip], Vector3.BACK, 0.05, color)


# --- 아르테온(빛의 성기사, SSR): 상아 판금·금 장식·금빛 망토, 앞이 열린 투구에 흰 날개 ---

static func _arteon(r) -> void:
	var ivory := Color("E6DDC8")
	var ivory_d := ivory.darkened(0.12)
	var gold := Color("E8B530")
	var navy := Color("3E4F86")
	var cape := Color("E0A630")
	var leather := Color("7A5232")
	var white := Color("FBFAF6")
	_head(r, SKIN, EYE, null)
	var h = r.on("head")
	_ball(h, Vector3(0, 1.86, -0.01), Vector3(0.5, 0.42, 0.49), 12, 4, ivory, 0.0, 90.0)
	_tube(h, [Vector3(0, 1.81, -0.01), Vector3(0, 1.9, -0.01)], [Vector2(0.52, 0.51), Vector2(0.52, 0.51)], 12, gold)
	_shell(h, [Vector3(0, 1.4, -0.03), Vector3(0, 1.62, -0.02), Vector3(0, 1.84, -0.01)], [Vector2(0.43, 0.42), Vector2(0.5, 0.49), Vector2(0.51, 0.5)],
		138.0, 402.0, 12, 0.07, ivory, ivory.darkened(0.35))
	_box(h, _on_face(0.0, 1.76, 0.0), Vector3(0.075, 0.17, 0.06), gold)
	for x in [-0.27, -0.14, 0.14, 0.27]:  # 투구 아래로 삐져나온 금발
		var top := _on_face(x, 1.83, 0.0)
		_plate(h, [top + Vector3(-0.075, 0, 0), top + Vector3(0.075, 0, 0), _on_face(x * 1.12, 1.73, 0.03)], Vector3.BACK, 0.045, Color("F2CF6A"))
	_plate(h, [Vector3(0, 2.2, 0.3), Vector3(0, 2.38, 0.08), Vector3(0, 2.36, -0.22), Vector3(0, 2.14, -0.46)], Vector3.RIGHT, 0.07, gold)
	for s in [-1.0, 1.0]:  # 투구 옆 흰 날개(깃 넷, 금 뿌리)
		var root := Vector3(s * 0.47, 1.98, -0.06)
		var tips := [Vector3(s * 0.74, 2.48, -0.22), Vector3(s * 0.9, 2.32, -0.36), Vector3(s * 0.95, 2.1, -0.44), Vector3(s * 0.86, 1.9, -0.46)]
		for i in tips.size():
			_leaf(h, root, tips[i], 0.22 - 0.025 * i, 0.06, Vector3(s, 0, 0.8), white.darkened(0.05 * i))
		_ball(h, root, Vector3(0.09, 0.1, 0.09), 6, 3, gold)
	var c = r.on("chest")
	_tube(c, [Vector3(0, 0.84, 0), Vector3(0, 0.98, 0.01), Vector3(0, 1.14, 0.01), Vector3(0, 1.27, 0), Vector3(0, 1.33, 0)],
		[Vector2(0.35, 0.25), Vector2(0.42, 0.3), Vector2(0.44, 0.31), Vector2(0.38, 0.27), Vector2(0.24, 0.2)], 8, ivory, PI / 8.0)
	_tube(c, [Vector3(0, 1.25, 0), Vector3(0, 1.36, 0)], [Vector2(0.28, 0.23), Vector2(0.22, 0.19)], 8, gold, PI / 8.0)
	_tube(c, [Vector3(0, 0.83, 0), Vector3(0, 0.88, 0.005)], [Vector2(0.36, 0.26), Vector2(0.38, 0.275)], 8, gold, PI / 8.0)
	_box(c, Vector3(0, 1.06, 0.29), Vector3(0.05, 0.36, 0.03), ivory.lightened(0.35))
	_plate(c, [Vector3(0, 1.19, 0.3), Vector3(0.1, 1.06, 0.3), Vector3(0, 0.93, 0.3), Vector3(-0.1, 1.06, 0.3)], Vector3.BACK, 0.04, gold)
	_plate(c, [Vector3(0, 1.11, 0.325), Vector3(0.045, 1.06, 0.325), Vector3(0, 1.01, 0.325), Vector3(-0.045, 1.06, 0.325)], Vector3.BACK, 0.03, Color("5AB4F0"))
	_cape(c, 1.28, -0.25, 0.33, 0.34, -0.47, 0.5, cape, white)
	_plate(c, [Vector3(0, 1.0, -0.425), Vector3(0.1, 0.86, -0.445), Vector3(0, 0.72, -0.465), Vector3(-0.1, 0.86, -0.445)], Vector3.FORWARD, 0.04, white)
	for s in [-1.0, 1.0]:  # 어깨 판(두 겹 돔, 금 테)
		var p = r.on("chest", Transform3D(Basis(Vector3.BACK, -s * 0.55), Vector3(s * 0.42, 1.17, 0.0)))
		_tube(p, [Vector3(0, -0.04, 0), Vector3(0, 0.02, 0)], [Vector2(0.27, 0.25), Vector2(0.27, 0.25)], 8, gold, PI / 8.0)
		_ball(p, Vector3(0, 0.01, 0), Vector3(0.25, 0.17, 0.23), 8, 3, ivory, 0.0, 90.0, PI / 8.0)
		_ball(p, Vector3(0, 0.1, 0), Vector3(0.16, 0.12, 0.15), 8, 2, ivory.lightened(0.3), 0.0, 90.0, PI / 8.0)
	var sp = r.on("spine")
	_tube(sp, [Vector3(0, 0.55, 0), Vector3(0, 0.68, 0), Vector3(0, 0.69, 0), Vector3(0, 0.79, 0), Vector3(0, 0.8, 0), Vector3(0, 0.92, 0)],
		[Vector2(0.31, 0.235), Vector2(0.335, 0.252), Vector2(0.32, 0.24), Vector2(0.34, 0.255), Vector2(0.33, 0.248), Vector2(0.36, 0.265)], 8,
		[ivory_d, ivory_d, ivory, ivory, ivory], PI / 8.0)
	var hp = r.on("hips")
	_tube(hp, [Vector3(0, 0.36, 0), Vector3(0, 0.5, 0), Vector3(0, 0.6, 0)], [Vector2(0.27, 0.2), Vector2(0.31, 0.23), Vector2(0.31, 0.23)], 8, navy, PI / 8.0)
	_tube(hp, [Vector3(0, 0.53, 0), Vector3(0, 0.625, 0)], [Vector2(0.35, 0.265), Vector2(0.35, 0.265)], 8, leather, PI / 8.0)
	_box(hp, Vector3(0, 0.578, 0.255), Vector3(0.14, 0.12, 0.05), gold)
	for s in [-1.0, 1.0]:  # 허리판(앞 둘, 옆 둘) + 금 끝단
		_plate(hp, [Vector3(s * 0.05, 0.54, 0.25), Vector3(s * 0.28, 0.54, 0.21), Vector3(s * 0.3, 0.37, 0.26), Vector3(s * 0.06, 0.37, 0.3)],
			Vector3.BACK, 0.04, ivory)
		_plate(hp, [Vector3(s * 0.06, 0.4, 0.302), Vector3(s * 0.3, 0.4, 0.262), Vector3(s * 0.3, 0.36, 0.27), Vector3(s * 0.06, 0.36, 0.31)],
			Vector3.BACK, 0.05, gold)
		_plate(hp, [Vector3(s * 0.335, 0.54, 0.13), Vector3(s * 0.335, 0.54, -0.13), Vector3(s * 0.39, 0.38, -0.15), Vector3(s * 0.39, 0.38, 0.15)],
			Vector3(s, 0, 0), 0.04, ivory_d)
	_arms(r, navy, ivory, ivory, gold, leather)
	_legs(r, navy, ivory, ivory, gold, ivory, gold)


# --- 루나(달빛 무희, SR): 연보라 옷·흰 목도리, 남색 긴 머리(묶음)·은 초승달 머리띠, 무희 소매 ---

static func _luna(r) -> void:
	var lav := Color("B9A8FF")
	var deep := Color("7A6AB8")
	var white := Color("F0EEFF")
	var indigo := Color("4A3E70")
	var hair := Color("33336E")
	var silver := Color("E4E4F0")
	_head(r, Color("FFDCC6"), Color("3A2E6A"), null, true, true)
	var h = r.on("head")
	_hair(h, hair, 1.3, 50.0, [-0.3, -0.15, 0.0, 0.15, 0.3])
	_tube(h, [Vector3(0, 1.66, -0.46), Vector3(0, 1.42, -0.62), Vector3(0, 1.1, -0.62), Vector3(0, 0.82, -0.52), Vector3(0, 0.66, -0.46)],
		[Vector2(0.15, 0.13), Vector2(0.2, 0.17), Vector2(0.17, 0.15), Vector2(0.1, 0.09), Vector2(0, 0)], 8, hair)
	_tube(h, [Vector3(0, 1.62, -0.44), Vector3(0, 1.7, -0.5)], [Vector2(0.13, 0.12), Vector2(0.13, 0.12)], 8, silver)
	var m = r.on("head", Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 2.0, 0.42)))  # 이마 위 초승달(지역 y = 앞)
	_shell(m, [Vector3(0, -0.025, 0), Vector3(0, 0.025, 0)], [Vector2(0.14, 0.14), Vector2(0.14, 0.14)], -60.0, 240.0, 10, 0.055, silver, silver.darkened(0.2))
	var c = r.on("chest")
	_tube(c, [Vector3(0, 0.84, 0), Vector3(0, 1.0, 0.02), Vector3(0, 1.16, 0.01), Vector3(0, 1.28, 0), Vector3(0, 1.33, 0)],
		[Vector2(0.28, 0.22), Vector2(0.34, 0.27), Vector2(0.37, 0.27), Vector2(0.31, 0.23), Vector2(0.19, 0.16)], 10, lav)
	_tube(c, [Vector3(0, 1.22, 0), Vector3(0, 1.34, 0)], [Vector2(0.3, 0.25), Vector2(0.21, 0.18)], 10, white)
	_plate(c, [Vector3(0, 1.12, 0.29), Vector3(0.05, 1.05, 0.29), Vector3(0, 0.98, 0.29), Vector3(-0.05, 1.05, 0.29)], Vector3.BACK, 0.04, silver)
	for s in [-1.0, 1.0]:  # 목도리 끝 둘(뒤로 날린다)
		_plate(c, [Vector3(s * 0.04, 1.3, -0.2), Vector3(s * 0.16, 1.28, -0.2), Vector3(s * 0.34, 0.78, -0.56), Vector3(s * 0.22, 0.74, -0.52)],
			Vector3.FORWARD, 0.04, white, white.darkened(0.25))
	var sp = r.on("spine")
	_tube(sp, [Vector3(0, 0.56, 0), Vector3(0, 0.9, 0.01)], [Vector2(0.25, 0.2), Vector2(0.29, 0.23)], 10, lav)
	_tube(sp, [Vector3(0, 0.6, 0), Vector3(0, 0.71, 0)], [Vector2(0.28, 0.225), Vector2(0.28, 0.225)], 10, indigo)
	for s in [-1.0, 1.0]:  # 허리끈 매듭(뒤)
		_plate(sp, [Vector3(0, 0.66, -0.23), Vector3(s * 0.2, 0.74, -0.3), Vector3(s * 0.22, 0.6, -0.3)], Vector3.FORWARD, 0.05, indigo)
		_plate(sp, [Vector3(s * 0.03, 0.64, -0.24), Vector3(s * 0.09, 0.62, -0.26), Vector3(s * 0.16, 0.4, -0.36), Vector3(s * 0.08, 0.4, -0.34)],
			Vector3.FORWARD, 0.04, deep)
	var hp = r.on("hips")
	_tube(hp, [Vector3(0, 0.3, 0), Vector3(0, 0.345, 0), Vector3(0, 0.5, 0), Vector3(0, 0.64, 0)],
		[Vector2(0.47, 0.39), Vector2(0.46, 0.38), Vector2(0.37, 0.3), Vector2(0.29, 0.23)], 12, [white, lav, lav])
	_arms(r, Color("FFDCC6"), null, deep, white, Color("FFDCC6"), 0.88, 1.35)
	_legs(r, indigo, null, white, silver, white, indigo, 0.9)


# --- 한스(민병대 검사, R): 누빔 가죽 갑옷·검붉은 반망토·쇠 챙모자, 갈색 짧은 머리 ---

static func _hans(r) -> void:
	var leather := Color("8E6E4E")
	var quilt := Color("7A5C3E")
	var dark := Color("5A4430")
	var red := Color("8A2E2A")
	var cream := Color("D8C8A0")
	var belt := Color("4A3626")
	var iron := Color("8E949C")
	var hair := Color("7A4E2A")
	var pants := Color("5E5446")
	_head(r, SKIN, EYE, hair.darkened(0.25))
	var h = r.on("head")
	_shell(h, [Vector3(0, 1.5, -0.04), Vector3(0, 1.68, -0.03), Vector3(0, 1.86, -0.02)], [Vector2(0.47, 0.47), Vector2(0.495, 0.495), Vector2(0.49, 0.49)],
		145.0, 395.0, 12, 0.07, hair, hair.darkened(0.3), 0.05)
	_tube(h, [Vector3(0, 1.83, -0.01), Vector3(0, 1.88, -0.01), Vector3(0, 1.98, -0.01)], [Vector2(0.8, 0.8), Vector2(0.76, 0.76), Vector2(0.52, 0.52)], 12, iron)
	_tube(h, [Vector3(0, 1.97, -0.01), Vector3(0, 2.04, -0.01)], [Vector2(0.53, 0.53), Vector2(0.53, 0.53)], 12, belt)
	_ball(h, Vector3(0, 2.02, -0.01), Vector3(0.52, 0.34, 0.52), 12, 3, iron.lightened(0.1), 0.0, 90.0)
	var c = r.on("chest")
	_tube(c, [Vector3(0, 0.84, 0), Vector3(0, 0.94, 0.01), Vector3(0, 1.04, 0.01), Vector3(0, 1.14, 0.01), Vector3(0, 1.24, 0), Vector3(0, 1.33, 0)],
		[Vector2(0.37, 0.27), Vector2(0.4, 0.29), Vector2(0.42, 0.3), Vector2(0.42, 0.3), Vector2(0.37, 0.27), Vector2(0.23, 0.19)], 8,
		[leather, quilt, leather, quilt, leather], PI / 8.0)
	_tube(c, [Vector3(0, 1.25, 0), Vector3(0, 1.36, 0)], [Vector2(0.27, 0.23), Vector2(0.21, 0.18)], 8, cream, PI / 8.0)
	_box(c, Vector3(0.0, 1.06, 0.295), Vector3(0.09, 0.62, 0.04), belt, Basis(Vector3.BACK, 0.72))
	_box(c, Vector3(0.0, 1.06, 0.31), Vector3(0.07, 0.07, 0.04), iron)
	_shell(c, [Vector3(0, 1.02, -0.02), Vector3(0, 1.36, 0)], [Vector2(0.48, 0.36), Vector2(0.27, 0.23)], 160.0, 380.0, 10, 0.06, red, red.darkened(0.35), 0.06)
	_cape(c, 1.2, -0.27, 0.3, 0.56, -0.4, 0.4, red, red.darkened(0.3))
	var sp = r.on("spine")
	_tube(sp, [Vector3(0, 0.55, 0), Vector3(0, 0.66, 0), Vector3(0, 0.78, 0), Vector3(0, 0.9, 0)],
		[Vector2(0.34, 0.255), Vector2(0.35, 0.26), Vector2(0.355, 0.265), Vector2(0.37, 0.27)], 8, [quilt, leather, quilt], PI / 8.0)
	var hp = r.on("hips")
	_tube(hp, [Vector3(0, 0.34, 0), Vector3(0, 0.44, 0), Vector3(0, 0.54, 0), Vector3(0, 0.62, 0)],
		[Vector2(0.38, 0.3), Vector2(0.37, 0.29), Vector2(0.35, 0.27), Vector2(0.34, 0.26)], 8, [leather, quilt, leather], PI / 8.0)
	_tube(hp, [Vector3(0, 0.55, 0), Vector3(0, 0.63, 0)], [Vector2(0.36, 0.275), Vector2(0.36, 0.275)], 8, belt, PI / 8.0)
	_box(hp, Vector3(0, 0.59, 0.27), Vector3(0.13, 0.1, 0.05), iron)
	_arms(r, leather, null, dark, belt, SKIN)
	_legs(r, pants, null, pants, belt, belt, belt.darkened(0.2))


# --- 해골 졸개(grunt): 뼈 몸(갈비뼈 사이로 어두운 속), 녹슨 쇠 투구, 붉은 눈빛·붉은 목 천(적 표시), 어깨 누더기, 가죽 허리천 ---

static func _grunt(r) -> void:
	var bone := Color("E8DFC8")
	var bone_d := Color("C2B593")
	var hole := Color("2A1E2A")
	var glow := Color("FF4A2E")
	var rust := Color("7A6458")
	var cloth := Color("4A3E58")
	var rag := Color("B03A2E")
	var leather := Color("5A4232")
	var h = r.on("head")
	_tube(h, [Vector3(0, 1.2, 0), Vector3(0, 1.42, 0)], [Vector2(0.075, 0.075), Vector2(0.075, 0.075)], 6, bone_d)
	_ball(h, Vector3(0, 1.79, -0.01), Vector3(0.43, 0.41, 0.43), 10, 5, bone)
	_tube(h, [Vector3(0, 1.47, 0.07), Vector3(0, 1.64, 0.09)], [Vector2(0.27, 0.25), Vector2(0.34, 0.29)], 8, bone, PI / 8.0)
	_tube(h, [Vector3(0, 1.33, 0.1), Vector3(0, 1.44, 0.12)], [Vector2(0.2, 0.19), Vector2(0.25, 0.22)], 8, bone_d, PI / 8.0)
	for i in 4:
		_box(h, Vector3(-0.105 + 0.07 * i, 1.505, 0.355), Vector3(0.05, 0.08, 0.04), Color.WHITE)
	for s in [-1.0, 1.0]:
		_tube(h, [Vector3(s * 0.155, 1.7, 0.3), Vector3(s * 0.155, 1.7, 0.42)], [Vector2(0.11, 0.095), Vector2(0.115, 0.1)], 7, hole)
		_tube(h, [Vector3(s * 0.155, 1.69, 0.4), Vector3(s * 0.155, 1.69, 0.445)], [Vector2(0.05, 0.044), Vector2(0.044, 0.038)], 6, glow)
	_plate(h, [Vector3(-0.045, 1.585, 0.405), Vector3(0.045, 1.585, 0.405), Vector3(0, 1.655, 0.41)], Vector3.BACK, 0.03, hole)
	_tube(h, [Vector3(0, 1.86, -0.01), Vector3(0, 1.96, -0.02)], [Vector2(0.45, 0.45), Vector2(0.43, 0.43)], 10, rag)  # 붉은 머리띠 + 뒤 매듭
	for s in [-1.0, 1.0]:
		_plate(h, [Vector3(s * 0.03, 1.93, -0.43), Vector3(s * 0.1, 1.95, -0.43), Vector3(s * 0.3, 1.64, -0.6), Vector3(s * 0.2, 1.6, -0.56)], Vector3.FORWARD, 0.04, rag)
	_box(h, Vector3(0.17, 2.08, 0.3), Vector3(0.03, 0.16, 0.03), hole, Basis(Vector3.BACK, 0.5) * Basis(Vector3.RIGHT, -0.7))  # 금 간 자국
	var c = r.on("chest")
	_tube(c, [Vector3(0, 0.86, -0.04), Vector3(0, 1.28, -0.04)], [Vector2(0.21, 0.15), Vector2(0.24, 0.17)], 8, hole, PI / 8.0)  # 갈비뼈 안 어둠
	_tube(c, [Vector3(0, 0.85, -0.17), Vector3(0, 1.3, -0.15)], [Vector2(0.07, 0.07), Vector2(0.07, 0.07)], 6, bone_d)
	for y in [0.88, 0.99, 1.1]:
		var w := 0.31 if y > 0.95 else 0.27
		_shell(c, [Vector3(0, y, -0.03), Vector3(0, y + 0.065, -0.03)], [Vector2(w, w * 0.78), Vector2(w, w * 0.78)], 112.0, 428.0, 10, 0.055, bone, bone_d)
	_box(c, Vector3(0, 1.02, 0.205), Vector3(0.085, 0.3, 0.05), bone)
	_tube(c, [Vector3(-0.32, 1.235, 0.02), Vector3(0.32, 1.235, 0.02)], [Vector2(0.05, 0.05), Vector2(0.05, 0.05)], 6, bone_d)
	for s in [-1.0, 1.0]:
		_ball(c, Vector3(s * 0.32, 1.16, 0.0), Vector3(0.11, 0.11, 0.11), 6, 3, bone_d)
	_shell(c, [Vector3(0, 1.08, -0.04), Vector3(0, 1.22, -0.02), Vector3(0, 1.34, 0)], [Vector2(0.42, 0.33), Vector2(0.39, 0.3), Vector2(0.22, 0.2)],
		170.0, 370.0, 10, 0.06, cloth, cloth.darkened(0.4), 0.09)
	_plate(c, [Vector3(-0.3, 1.2, -0.3), Vector3(0.3, 1.2, -0.3), Vector3(0.36, 0.62, -0.4), Vector3(0.0, 0.52, -0.42), Vector3(-0.36, 0.62, -0.4)],
		Vector3.FORWARD, 0.04, cloth, cloth.darkened(0.4))
	_tube(c, [Vector3(0, 1.25, 0.0), Vector3(0, 1.35, 0.0)], [Vector2(0.24, 0.21), Vector2(0.19, 0.17)], 8, rag)
	_plate(c, [Vector3(0.05, 1.28, 0.18), Vector3(0.15, 1.26, 0.17), Vector3(0.22, 1.02, 0.27), Vector3(0.12, 0.99, 0.27)], Vector3.BACK, 0.04, rag)
	var sp = r.on("spine")
	_tube(sp, [Vector3(0, 0.52, -0.06), Vector3(0, 0.9, -0.12)], [Vector2(0.07, 0.07), Vector2(0.07, 0.07)], 6, bone_d)
	for y in [0.62, 0.72, 0.82]:
		var z: float = -0.08 - (y - 0.5) * 0.12
		_tube(sp, [Vector3(0, y, z), Vector3(0, y + 0.05, z)], [Vector2(0.11, 0.1), Vector2(0.11, 0.1)], 6, bone)
	var hp = r.on("hips")
	_tube(hp, [Vector3(0, 0.38, 0), Vector3(0, 0.46, 0), Vector3(0, 0.56, -0.02)], [Vector2(0.18, 0.12), Vector2(0.27, 0.16), Vector2(0.24, 0.14)], 8, bone, PI / 8.0)
	_tube(hp, [Vector3(0, 0.5, 0), Vector3(0, 0.58, 0)], [Vector2(0.3, 0.2), Vector2(0.3, 0.2)], 8, leather, PI / 8.0)
	_box(hp, Vector3(0, 0.54, 0.2), Vector3(0.12, 0.1, 0.05), rust)
	for z in [1.0, -1.0]:  # 앞뒤 누더기 허리천
		_plate(hp, [Vector3(-0.16, 0.52, z * 0.19), Vector3(0.16, 0.52, z * 0.19), Vector3(0.12, 0.28, z * 0.23), Vector3(0.0, 0.22, z * 0.24),
			Vector3(-0.14, 0.29, z * 0.23)], Vector3(0, 0, z), 0.04, leather.lightened(0.1))
	_arms(r, bone, bone_d, bone, null, bone_d, 0.62)
	_legs(r, bone, bone_d, bone, null, bone_d, bone_d, 0.66)

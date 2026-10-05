extends RefCounted
## 몬스터 상태 이펙트(스킬 100종): burn(주황 불꽃 조각)·bleed(떨어지는 붉은 방울)·curse(머리 둘레 검보라 연기),
## freeze(몸을 감싼 반투명 얼음 덩어리)·root(발밑 덩굴)·vulnerable(머리 위 보라 내림 화살 + 고리)·weaken(허리 회색 고리 + 내림 꺾쇠).
## 상태마다 MeshInstance3D 하나(조각 여럿을 메시 하나에 담는다). 메시는 종류마다 한 번 만들어 캐시하고 재질은 Fx 공유 재질
## (정점 색 / 반투명)을 쓴다. 생성은 Fx._spawn이라 이펙트 상한(Fx.MAX_LIVE)·track을 같이 쓴다 — 상한이면 null(상태는 그대로 걸린다).
## 지속 동안 남는다 — 지우는 건 monster.gd(상태가 끝나거나 죽을 때). 움직임은 노드에 묶인 트윈 하나(노드와 함께 해제)라 매 프레임 할당이 없다.
## 오토로드 참조 없음.

const Fx := preload("res://scripts/fx.gd")
const MeshKit := preload("res://scripts/mesh_kit.gd")

const KINDS := ["burn", "bleed", "curse", "freeze", "root", "vulnerable", "weaken"]
const BURN := Color(1.0, 0.5, 0.1)
const BURN_CORE := Color(1.0, 0.85, 0.3)
const BLEED := Color(0.78, 0.06, 0.08)
const CURSE := Color(0.42, 0.16, 0.58)
const ICE := Color(0.62, 0.88, 1.0)
const VINE := Color(0.3, 0.55, 0.2)
const VULN := Color(0.75, 0.3, 1.0)
const WEAK := Color(0.6, 0.6, 0.62)
const BODY_R := 0.4  # 메시 크기 1이 감싸는 몸 반지름(grunt)

static var _meshes := {}


## kind 이펙트를 target 자식으로 붙인다(월드 축 그대로 — 몬스터 노드는 돌지 않고 모델만 돈다).
## height = 발에서 머리(HP 막대)까지 m, size = 몸 배율(몬스터 표 scale), width = 몸 반지름 m(겹침 해소 radius — 몸을 감싸는 것들의
## 가로 배율 = max(size, width / BODY_R): 뚱뚱한 보스도 감싼다. 얼음 덩어리는 세로도 같이). 상한이거나 모르는 종류면 null.
static func attach(target: Node3D, kind: String, height: float, size: float, width := 0.0) -> MeshInstance3D:
	var y := 0.0
	var mat: Material = null
	match kind:
		"burn":
			y = height * 0.4
		"bleed":
			y = height * 0.55
		"curse":
			y = height * 0.62
			mat = Fx.soft_material()
		"freeze":
			mat = Fx.soft_material()
		"root":
			y = 0.02
		"vulnerable":
			y = height + 0.5 * size
		"weaken":
			y = height * 0.3
		_:
			return null
	var mi := Fx._spawn(target, mesh(kind), target.global_position + Vector3(0, y, 0), kind, mat)
	if mi == null:
		return null
	var wide := maxf(size, width / BODY_R)
	match kind:
		"vulnerable":
			mi.scale = Vector3.ONE * size
		"freeze":
			mi.scale = Vector3.ONE * wide
		_:
			mi.scale = Vector3(wide, size, wide)
	var s := mi.scale
	match kind:
		"burn":  # 불꽃이 위아래로 일렁인다
			var tw := mi.create_tween().set_loops()
			tw.tween_property(mi, "scale", Vector3(s.x * 1.08, s.y * 1.3, s.z * 1.08), 0.14)
			tw.tween_property(mi, "scale", Vector3(s.x * 0.95, s.y * 0.85, s.z * 0.95), 0.14)
		"bleed":  # 방울이 떨어지고 다시 처음부터
			mi.create_tween().set_loops().tween_property(mi, "position:y", y - 0.45 * size, 0.5).from(y)
		"curse":  # 연기가 천천히 돈다
			mi.create_tween().set_loops().tween_property(mi, "rotation:y", TAU, 2.4).from(0.0)
		"freeze", "root":  # 한 번 자라 나온다
			mi.scale = Vector3(s.x * 0.6, s.y * 0.3, s.z * 0.6)
			mi.create_tween().tween_property(mi, "scale", s, 0.15).set_ease(Tween.EASE_OUT)
		"vulnerable":  # 화살이 아래로 콕콕
			var tv := mi.create_tween().set_loops()
			tv.tween_property(mi, "position:y", y - 0.15 * size, 0.3)
			tv.tween_property(mi, "position:y", y, 0.3)
		"weaken":
			mi.create_tween().set_loops().tween_property(mi, "rotation:y", -TAU, 3.0).from(0.0)
	return mi


## 종류별 메시(캐시). 크기 1 = 키 ~2.2 m 몸(몬스터 표 scale 1).
static func mesh(kind: String) -> Mesh:
	if not _meshes.has(kind):
		_meshes[kind] = _build(kind)
	return _meshes[kind]


static func _build(kind: String) -> ArrayMesh:
	var k = MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	match kind:
		"burn":  # 몸 둘레 불꽃 조각 8개(바깥 주황 뿔 + 안쪽 노랑 작은 뿔, 높이 제각각)
			for i in 8:
				var a := TAU * i / 8.0 + rng.randf() * 0.4
				var r := rng.randf_range(0.45, 0.6)
				var o := Vector3(cos(a) * r, rng.randf_range(-0.6, 0.6), sin(a) * r)
				var h := rng.randf_range(0.4, 0.7)
				k.cone(o, 4, 0.15, h, BURN if i % 2 == 0 else BURN.darkened(0.2), a)
				k.cone(o + Vector3(0, 0.03, 0), 3, 0.08, h * 0.6, BURN_CORE, a)
		"bleed":  # 몸 둘레 붉은 방울 6개(위 짧은 뿔 + 아래 긴 뿔 = 물방울, 높이 엇갈림)
			for i in 6:
				var a := TAU * i / 6.0 + 0.4
				var o := Vector3(cos(a) * 0.55, 0.22 * (i % 3), sin(a) * 0.55)
				k.cone(o, 4, 0.1, 0.16, BLEED.lightened(0.2), a)
				k.cone(o, 4, 0.1, -0.2, BLEED, a)
		"curse":  # 연기 줄기 3개: 머리 둘레에서 나선으로 오르며 가늘고 옅어지는 띠(교차 두 장) + 끝의 작은 덩이
			for w in 3:
				var a0 := TAU * w / 3.0
				var prev := Vector3(cos(a0), 0, sin(a0)) * 0.62
				for seg in 5:
					var a := a0 + (seg + 1) * 0.55
					var r := 0.62 - (seg + 1) * 0.08
					var next := Vector3(cos(a) * r, (seg + 1) * 0.2, sin(a) * r)
					Fx._ribbon(k, prev, next, 0.13 - seg * 0.02, Color(CURSE.lightened(seg * 0.08), 0.9 - seg * 0.14))
					prev = next
				k.rock(Vector3(cos(a0), 0, sin(a0)) * 0.62, 0.12, Color(CURSE.darkened(0.3), 0.9), rng, 1.0)
		"freeze":  # 반투명 얼음 6각 기둥(몸을 감싼다) + 밑둘레 얼음 가시 5개
			k.prism_n(Vector3.ZERO, 6, 0.7, 0.62, 2.6, Color(ICE, 0.42), PI / 6.0)
			for i in 5:
				var a := TAU * i / 5.0 + 0.3
				k.cone(Vector3(cos(a) * 0.68, 0, sin(a) * 0.68), 4, 0.13, rng.randf_range(0.45, 0.75), Color(ICE.lightened(0.3), 0.85), a)
		"root":  # 발밑 덩굴: 어두운 초록 6각 고리 + 안쪽으로 휜 가는 덩굴 6개(두 마디) + 잎
			Fx._hex_ring(k, 0.36, 0.55, 0.05, VINE.darkened(0.3))
			for i in 6:
				var a := TAU * i / 6.0
				var out := Vector3(cos(a), 0, sin(a))
				var base := out * 0.5
				var axis := out.cross(Vector3.UP).normalized()
				k.xform = Transform3D(Basis(axis, 0.35), base)
				k.cone(Vector3.ZERO, 3, 0.06, 0.4, VINE, a)
				k.xform = Transform3D(Basis(axis, 0.9), base + Vector3(0, 0.3, 0) - out * 0.12)
				k.cone(Vector3.ZERO, 3, 0.04, 0.32, VINE.lightened(0.15), a)
				k.xform = Transform3D.IDENTITY
				k.face([base + Vector3(0, 0.18, 0), base + out * 0.12 + Vector3(0, 0.25, 0), base + out * 0.2 + Vector3(0, 0.16, 0),
					base + out * 0.1 + Vector3(0, 0.1, 0)], axis, VINE.lightened(0.3))
		"vulnerable":  # 보라 내림 화살(굵은 기둥 + 아래 뾰족 촉) + 그 아래 납작 고리
			k.box(Vector3(0, 0.12, 0), Vector3(0.12, 0.3, 0.12), VULN)
			k.prism_n(Vector3(0, 0.12, 0), 4, 0.22, 0.0, -0.3, VULN.darkened(0.1), PI / 4.0)
			_cap(k, Vector3(0, 0.12, 0), 4, 0.22, PI / 4.0, VULN)
			Fx._hex_ring(k, 0.26, 0.36, 0.04, VULN.lightened(0.2))
		"weaken":  # 허리 회색 6각 고리(진하고 옅은 두 겹) + 둘레 내림 꺾쇠 4개(두 단)
			Fx._hex_ring(k, 0.66, 0.8, 0.06, WEAK)
			Fx._hex_ring(k, 0.58, 0.66, 0.04, WEAK.darkened(0.35))
			for i in 4:
				var a := TAU * i / 4.0 + PI / 4.0
				var o := Vector3(cos(a) * 0.74, 0.0, sin(a) * 0.74)
				for step in 2:
					var b := o + Vector3(0, 0.22 + step * 0.22, 0)
					k.prism_n(b, 4, 0.15, 0.0, -0.2, WEAK.darkened(0.3 - step * 0.15), a)
					_cap(k, b, 4, 0.15, a, WEAK.lightened(0.15))
	return k.commit()


## 아래로 뾰족한 뿔(prism_n 높이 음수)의 열린 윗면을 덮는다.
static func _cap(k, base: Vector3, sides: int, r: float, rot: float, color: Color) -> void:
	var pts := []
	for i in sides:
		var a := rot + TAU * i / sides
		pts.append(base + Vector3(cos(a) * r, 0, sin(a) * r))
	k.face(pts, Vector3.UP, color)

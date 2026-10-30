extends RefCounted
## 태생 UR 영웅 전용 스킬 이펙트(2026-10-29 사용자 "스킬도 존나 멋져야해"): 사신(四神) + 시간 + 불새.
## Fx의 겹(빛무리·파동·입자·가산 재질)에 UR만의 모양을 더한다 — 거북 등껍질 돔, 물기둥 고리, 호랑이 발톱 세 줄,
## 여우불 구슬, 아홉 꼬리 참격, 휘감는 용, 시계 문자판, 안으로 빨려드는 붕괴, 날개 편 불새.
## 메시는 Fx와 같은 MeshKit 로우폴리(면마다 단색), 모양마다 한 번 만들어 캐시한다. 동시 수 상한은 Fx를 따른다.

const Fx := preload("res://scripts/fx.gd")
const MeshKit := preload("res://scripts/mesh_kit.gd")

static var _meshes := {}


static func _mesh(kind: String, color: Color) -> Mesh:
	var key := kind + color.to_html()
	if not _meshes.has(key):
		_meshes[key] = _build(kind, color)
	return _meshes[key]


static func _build(kind: String, color: Color) -> ArrayMesh:
	var k = MeshKit.new()
	match kind:
		"shell":  # 거북 등껍질 돔: 6각 판 3단(가운데로 갈수록 밝고 옅다) + 판 사이 진한 띠, 반지름 1 높이 0.8
			var rings := [[1.0, 0.0], [0.82, 0.36], [0.5, 0.66], [0.0, 0.8]]
			for i in 3:
				var r0: float = rings[i][0]
				var y0: float = rings[i][1]
				var r1: float = rings[i + 1][0]
				var y1: float = rings[i + 1][1]
				for s in 8:
					var a0 := TAU * s / 8.0 + 0.2 * i
					var a1 := TAU * (s + 1) / 8.0 + 0.2 * i
					var p0 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
					var p1 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
					var q0 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
					var q1 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
					var c := Color(color.lightened(0.12 * i + (0.1 if s % 2 == 0 else 0.0)), 0.7 - 0.12 * i)
					if r1 > 0.0:
						k.face([p0, p1, q1, q0], (p0 + p1) / 2.0, c)
					else:
						k.face([p0, p1, q0], (p0 + p1) / 2.0 + Vector3.UP * 0.5, c)
					k.face([p0, p0 + Vector3(0, 0.04, 0), q0 + Vector3(0, 0.04, 0), q0], Vector3(-sin(a0), 0, cos(a0)), Color(color.darkened(0.35), 0.8))
		"claw":  # 호랑이 발톱 자국 한 줄(XZ 평면, 앞 -Z로 길이 1): 가운데 굵고 양 끝이 뾰족한 휜 띠
			var pts := []
			for i in 9:
				var t := i / 8.0
				pts.append(Vector3(sin(t * PI) * 0.12, 0, -t))
			for i in 8:
				var w0: float = sin(i / 8.0 * PI) * 0.09 + 0.005
				var w1: float = sin((i + 1) / 8.0 * PI) * 0.09 + 0.005
				var a: Vector3 = pts[i]
				var b: Vector3 = pts[i + 1]
				k.face([a + Vector3(-w0, 0, 0), a + Vector3(w0, 0, 0), b + Vector3(w1, 0, 0), b + Vector3(-w1, 0, 0)], Vector3.UP, color)
		"tail":  # 여우 꼬리 참격(XZ 평면): 바깥 반지름 1의 120° 초승달, 끝이 불꽃처럼 갈라진다
			var n := 10
			for i in n:
				var a0 := -PI / 3.0 + 2.0 * PI / 3.0 * i / n
				var a1 := -PI / 3.0 + 2.0 * PI / 3.0 * (i + 1) / n
				var th0: float = sin(float(i) / n * PI) * 0.35 + 0.02
				var th1: float = sin(float(i + 1) / n * PI) * 0.35 + 0.02
				var c := Color(color.lightened(0.25 * float(i) / n), 0.9 - 0.5 * float(i) / n)
				k.face([Vector3(cos(a0), 0, sin(a0)), Vector3(cos(a1), 0, sin(a1)),
					Vector3(cos(a1), 0, sin(a1)) * (1.0 - th1), Vector3(cos(a0), 0, sin(a0)) * (1.0 - th0)], Vector3.UP, c)
		"helix":  # 용 몸통 나선(앞 -Z로 길이 1, 반지름 0.35, 두 바퀴): 마디마다 마름모 비늘
			var steps := 24
			for i in steps:
				var t0 := float(i) / steps
				var t1 := float(i + 1) / steps
				var p0 := Vector3(cos(t0 * TAU * 2.0) * 0.35, sin(t0 * TAU * 2.0) * 0.35, -t0)
				var p1 := Vector3(cos(t1 * TAU * 2.0) * 0.35, sin(t1 * TAU * 2.0) * 0.35, -t1)
				var w := 0.07 + 0.05 * sin(t0 * PI)
				var c := Color(color.lightened(0.2 if i % 2 == 0 else 0.0), 0.85)
				Fx._ribbon(k, p0, p1, w, c)
		"coil":  # 휘감는 용(XZ 위 고리): 반지름 1 둘레를 위아래로 넘실대는 몸통 + 머리 쪽 뿔
			var segs := 28
			for i in segs:
				var a0 := TAU * i / segs * 0.92
				var a1 := TAU * (i + 1) / segs * 0.92
				var p0 := Vector3(cos(a0), 0.35 + sin(a0 * 3.0) * 0.25, sin(a0))
				var p1 := Vector3(cos(a1), 0.35 + sin(a1 * 3.0) * 0.25, sin(a1))
				var w := 0.03 + 0.09 * float(i) / segs
				Fx._ribbon(k, p0, p1, w, Color(color.lightened(0.25 if i % 3 == 0 else 0.0), 0.9))
			var head := Vector3(cos(TAU * 0.92), 0.35 + sin(TAU * 0.92 * 3.0) * 0.25, sin(TAU * 0.92))
			k.xform = Transform3D(Basis(), head)
			Fx._diamond(k, 0.16, 0.12, color.lightened(0.35))
			k.xform = Transform3D(Basis().rotated(Vector3.FORWARD, 0.5), head + Vector3(0, 0.1, 0))
			k.cone(Vector3.ZERO, 3, 0.04, 0.28, color.lightened(0.5))
			k.xform = Transform3D.IDENTITY
		"clock":  # 시계 문자판(XZ 평면, 반지름 1): 바깥 띠 + 12 눈금(3·6·9·12는 길게) + 안쪽 옅은 원판
			for i in 32:
				var a0 := TAU * i / 32.0
				var a1 := TAU * (i + 1) / 32.0
				var o0 := Vector3(cos(a0), 0, sin(a0))
				var o1 := Vector3(cos(a1), 0, sin(a1))
				k.face([o0 * 0.92, o0, o1, o1 * 0.92], Vector3.UP, Color(color, 0.9))
				k.face([o0 * 0.8, o0 * 0.84, o1 * 0.84, o1 * 0.8], Vector3.UP, Color(color, 0.45))
				k.face([Vector3.ZERO, o0 * 0.8, o1 * 0.8], Vector3.UP, Color(color.darkened(0.3), 0.18))
			for i in 12:
				var a := TAU * i / 12.0
				var d := Vector3(cos(a), 0, sin(a))
				var side := Vector3(-d.z, 0, d.x) * (0.035 if i % 3 == 0 else 0.02)
				var inner := 0.62 if i % 3 == 0 else 0.72
				k.face([d * inner - side, d * inner + side, d * 0.88 + side, d * 0.88 - side], Vector3.UP, color.lightened(0.4))
		"hand":  # 시곗바늘(XZ, 가운데에서 +X로 길이 1): 뾰족한 마름모
			k.face([Vector3(0, 0, -0.05), Vector3(1.0, 0, 0), Vector3(0, 0, 0.05), Vector3(-0.12, 0, 0)], Vector3.UP, color)
		"wings":  # 날개 편 불새(XZ 위, 몸 앞 -Z, 폭 2): 깃 다섯 장씩 + 몸 + 긴 꼬리깃
			for side in [-1.0, 1.0]:
				for f in 5:
					var root := Vector3(0.12 * side, 0, -0.1 + 0.06 * f)
					var tip := Vector3((0.55 + 0.45 * (1.0 - f / 4.0)) * side, 0.15 - 0.04 * f, 0.15 + 0.12 * f)
					var c := Color(color.lerp(Color(1.0, 0.85, 0.35), 0.25 * (1.0 - f / 4.0)), 0.9)
					var w := Vector3(0, 0, 0.09)
					k.face([root - w, tip, root + w], Vector3.UP, c)
			k.xform = Transform3D(Basis(), Vector3(0, 0, -0.05))
			Fx._diamond(k, 0.12, 0.08, color.lightened(0.3))
			k.xform = Transform3D.IDENTITY
			for t in 3:
				var ang := (t - 1) * 0.25
				var tip := Vector3(sin(ang) * 0.9, -0.05, 0.9 + 0.2 * (1 - absi(t - 1)))
				k.face([Vector3(-0.05, 0, 0.1), tip, Vector3(0.05, 0, 0.1)], Vector3.UP, Color(color.darkened(0.1), 0.75))
		"sigil":  # UR 마법진 바깥 겹(XZ, 반지름 1): 굵은 테 + 안쪽 가는 테 + 룬 눈금 24개(길고 짧게) + 테 위 마름모 8개
			for i in 48:
				var a0 := TAU * i / 48.0
				var a1 := TAU * (i + 1) / 48.0
				var o0 := Vector3(cos(a0), 0, sin(a0))
				var o1 := Vector3(cos(a1), 0, sin(a1))
				k.face([o0 * 0.93, o0, o1, o1 * 0.93], Vector3.UP, Color(color, 0.95))
				k.face([o0 * 0.72, o0 * 0.75, o1 * 0.75, o1 * 0.72], Vector3.UP, Color(color, 0.8))
				k.face([o0 * 0.75, o0 * 0.93, o1 * 0.93, o1 * 0.75], Vector3.UP, Color(color.darkened(0.2), 0.16))
			for i in 24:
				var a := TAU * (i + 0.5) / 24.0
				var d := Vector3(cos(a), 0, sin(a))
				var sd := Vector3(-d.z, 0, d.x) * 0.018
				var r0 := 0.78 if i % 2 == 0 else 0.83
				k.face([d * r0 - sd, d * r0 + sd, d * 0.9 + sd, d * 0.9 - sd], Vector3.UP, color.lightened(0.35))
			for i in 8:
				var a := TAU * i / 8.0
				var d := Vector3(cos(a), 0, sin(a))
				var sd := Vector3(-d.z, 0, d.x)
				k.face([d * 0.86, d * 0.965 + sd * 0.06, d * 1.07, d * 0.965 - sd * 0.06], Vector3.UP, color.lightened(0.5))
		"sigil_star":  # UR 마법진 안쪽 겹(XZ, 반지름 0.7): 겹친 두 사각형 = 8각 별 + 가운데 작은 테
			for sq in 2:
				for i in 4:
					var a0 := TAU * i / 4.0 + PI / 4.0 * sq
					var a1 := TAU * (i + 1) / 4.0 + PI / 4.0 * sq
					var p0 := Vector3(cos(a0), 0, sin(a0)) * 0.7
					var p1 := Vector3(cos(a1), 0, sin(a1)) * 0.7
					var n := (p1 - p0).normalized().cross(Vector3.UP) * 0.022
					k.face([p0 - n, p0 + n, p1 + n, p1 - n], Vector3.UP, Color(color.lightened(0.2), 0.95))
			for i in 24:
				var a0 := TAU * i / 24.0
				var a1 := TAU * (i + 1) / 24.0
				var o0 := Vector3(cos(a0), 0, sin(a0))
				var o1 := Vector3(cos(a1), 0, sin(a1))
				k.face([o0 * 0.22, o0 * 0.26, o1 * 0.26, o1 * 0.22], Vector3.UP, color.lightened(0.4))
				k.face([Vector3.ZERO, o0 * 0.22, o1 * 0.22], Vector3.UP, Color(color.lightened(0.3), 0.35))
		"heart":  # 매혹 하트(XY 평면, 카메라를 보게): 두 마름모 + 아래 삼각
			k.face([Vector3(0, -0.5, 0), Vector3(0.5, 0.1, 0), Vector3(0.25, 0.4, 0), Vector3(0, 0.2, 0)], Vector3.BACK, color)
			k.face([Vector3(0, -0.5, 0), Vector3(0, 0.2, 0), Vector3(-0.25, 0.4, 0), Vector3(-0.5, 0.1, 0)], Vector3.BACK, color)
	return k.commit()


## 모양 하나: 진한 반투명 겹(밝은 풀밭 위에서도 제 색이 보이게) + 그 위 가산 빛 겹(자식, 함께 움직이고 함께 옅어진다).
## glow = false면 반투명 겹만, mat을 주면 그 재질 한 겹만.
static func _put(parent: Node, kind: String, color: Color, pos: Vector3, tag: String, mat: Material = null, glow := true) -> MeshInstance3D:
	if mat != null:
		return Fx._spawn(parent, _mesh(kind, color), pos, tag, mat)
	var mi := Fx._spawn(parent, _mesh(kind, color.darkened(0.2)), pos, tag, Fx.soft_material())
	if mi != null and glow:
		var g := MeshInstance3D.new()
		g.mesh = _mesh(kind, color.lightened(0.3))
		g.material_override = Fx.glow_material()
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.position = Vector3(0, 0.02, 0)
		g.scale = Vector3.ONE * 0.92
		mi.add_child(g)
	return mi


## 겹 둘 다 delay초 뒤 sec초에 옅게.
static func _fade(mi: MeshInstance3D, sec: float, delay := 0.0) -> void:
	Fx._fade(mi, sec, delay)
	for c in mi.get_children():
		if c is GeometryInstance3D:
			Fx._fade(c, sec, delay)


# --- UR 공통 연출(2026-10-30 사용자 "스킬이 이펙트가 더 화려해야해": 원신 원소폭발·니케 버스트·세븐나이츠 키우기 궁극기처럼 마법진 + 빛기둥 + 섬광) ---

## 바닥 UR 마법진: 바깥 겹과 별 겹이 반대로 돌며 r까지 펼쳐지고 sec초 머문 뒤 옅어진다.
static func sigil(parent: Node, pos: Vector3, color: Color, r: float, sec: float) -> void:
	for layer in 2:
		var mi := _put(parent, "sigil" if layer == 0 else "sigil_star", color, pos + Vector3(0, 0.05 + 0.01 * layer, 0), "ur_sigil")
		if mi == null:
			return
		var spin := (1.0 if layer == 0 else -1.6) * sec * 0.9
		mi.scale = Vector3(r * 0.2, 1.0, r * 0.2)
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3(r, 1.0, r), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(mi, "rotation:y", spin, sec + 0.3)
		tw.tween_interval(maxf(0.0, sec - 0.22))
		tw.tween_property(mi, "scale", Vector3(r * 1.15, 1.0, r * 1.15), 0.3)
		tw.tween_callback(mi.queue_free)
		_fade(mi, 0.3, sec)


## UR 스킬 발동 순간(시전자): 발밑 마법진 + 하늘로 솟는 고유색 빛기둥 + 사방으로 튀는 빛줄기·떠오르는 빛 조각.
## ult(궁극기)면 마법진이 더 크고 오래 가며, 하늘에서 빛줄기가 내리꽂히고 화면이 번쩍·흔들린다.
static func cast(hero: Node3D, color: Color, ult: bool) -> void:
	if hero == null or not hero.is_inside_tree():
		return
	var w := hero.get_parent()
	var at := Vector3(hero.global_position.x, 0, hero.global_position.z)
	var r := 3.2 if ult else 2.2
	sigil(w, at, color, r, 1.4 if ult else 0.8)
	Fx._surge(w, Fx._mesh("pillar", color.lightened(0.2)), at, "ur_cast_pillar", 1.1 if ult else 0.8, 7.0 if ult else 4.5, 0.7 if ult else 0.5)
	Fx._surge(w, Fx._mesh("rays", color.lightened(0.3)), at, "ur_cast_rays", r * 0.7, 2.2, 0.55)
	Fx.halo(w, at + Vector3(0, 1.3, 0), color.lightened(0.25), r * 1.6, 0.6, 1.4, "ur_cast_glow")
	var sp := Fx._burst(w, at + Vector3(0, 1.0, 0), color.lightened(0.45), "spark", 26 if ult else 16, 0.55, "ur_cast_sparks")
	if sp != null:
		sp.direction = Vector3.UP
		sp.spread = 75.0
		sp.initial_velocity_min = 6.0
		sp.initial_velocity_max = 12.0
		sp.scale_amount_min = 1.4
		sp.scale_amount_max = 2.4
	Fx._motes(w, at, color.lightened(0.35), r * 0.8, 3.0, 1.0)
	if ult:
		Fx._wave(w, at, color.lightened(0.3), r * 1.8, 0.45)
		Fx._wave(w, at, color, r * 2.4, 0.55, 0.12)
		Fx.lightning(w, [at + Vector3(0, Fx.SKY_H, 0), at + Vector3(0.6, 4.0, -0.4), at + Vector3(0, 0.3, 0)], color.lightened(0.4), 2)
		Fx.screen_flash(w, at, color, 0.16)
		Fx.kick(w, at, Fx.KICK_AMP[1], 0.0)


## UR 큰 타격 자리: 마법진 + 별 섬광 + 빛기둥 + 파편처럼 튀는 빛줄기 + 고리 두 겹.
static func burst(parent: Node, pos: Vector3, color: Color, r: float) -> void:
	sigil(parent, pos, color, r, 0.5)
	Fx.flare_burst(parent, pos, color, r * 0.8, 2)
	Fx._surge(parent, Fx._mesh("pillar", color.lightened(0.2)), pos, "ur_burst_pillar", r * 0.4, 5.0, 0.55)
	Fx._wave(parent, pos, color.lightened(0.3), r * 1.6, 0.4)
	Fx._wave(parent, pos, color, r * 2.1, 0.5, 0.1)


# --- 현무 ---

## 현무 결계: 시전자 둘레에 6각 판 거북 등껍질 돔이 솟아(반지름 r) sec초 머문다 + 바닥 물결 + 오르는 물방울.
static func shell_dome(parent: Node, pos: Vector3, color: Color, r: float, sec: float) -> void:
	var dr := minf(r, 2.4)  # 돔은 현무를 감싸는 크기, 결계 범위(r)는 바닥 파동으로
	var dome := _put(parent, "shell", color.darkened(0.25), pos + Vector3(0, 0.02, 0), "ur_shell")
	if dome != null:
		dome.scale = Vector3(dr * 0.2, 0.05, dr * 0.2)
		var tw := dome.create_tween()
		tw.tween_property(dome, "scale", Vector3(dr, dr * 0.85, dr), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(dome, "rotation:y", 0.6, sec)
		tw.tween_interval(maxf(0.1, sec - 0.6))
		tw.tween_property(dome, "scale", Vector3(dr * 1.15, 0.05, dr * 1.15), 0.3).set_ease(Tween.EASE_IN)
		tw.tween_callback(dome.queue_free)
		_fade(dome, 0.3, sec - 0.3)
	Fx._wave(parent, pos, color, r * 1.2, 0.5)
	Fx._wave(parent, pos, color.lightened(0.3), r * 1.5, 0.6, 0.15)
	Fx.halo(parent, pos + Vector3(0, 1.0, 0), color.lightened(0.2), r * 2.0, 0.6, 1.2, "ur_shell_halo")
	Fx._motes(parent, pos, color.lightened(0.35), r * 0.8, 2.4, 1.0)
	sigil(parent, pos, color.lightened(0.15), r, sec)
	for i in 6:  # 돔 둘레로 물기둥 여섯이 솟는다
		var a := TAU * i / 6.0
		Fx._surge(parent, Fx._mesh("pillar", color.lightened(0.2)), pos + Vector3(cos(a), 0, sin(a)) * (dr + 0.6), "ur_shell_pillar", 0.45, 3.0, 0.6, Fx.soft_material())
	var sp := Fx._burst(parent, pos + Vector3(0, 0.3, 0), color.lightened(0.5), "spark", 20, 0.7, "ur_shell_spray")
	if sp != null:
		sp.direction = Vector3.UP
		sp.spread = 50.0
		sp.initial_velocity_min = 4.0
		sp.initial_velocity_max = 8.0
		sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		sp.emission_ring_axis = Vector3.UP
		sp.emission_ring_radius = dr
		sp.emission_ring_inner_radius = dr * 0.8
		sp.emission_ring_height = 0.1


## 북해 해일: 가운데서 바깥으로 물기둥이 세 겹 고리로 차례로 치솟고(반지름 r), 물보라·파동·흔들림.
static func tide(parent: Node, pos: Vector3, color: Color, r: float) -> void:
	Fx.quake(parent, pos, r, 2)
	for ring in 3:
		var rr := r * (0.35 + 0.32 * ring)
		var n := 5 + ring * 3
		for i in n:
			var a := TAU * i / n + ring * 0.4
			var at := pos + Vector3(cos(a), 0, sin(a)) * rr
			var delay := 0.12 * ring
			var cb := func():
				Fx._surge(parent, Fx._mesh("pillar", color), at, "ur_tide_pillar", 0.7, 3.2 - 0.5 * ring, 0.55, Fx.soft_material())
			if delay <= 0.0:
				cb.call()
			else:
				parent.get_tree().create_timer(delay, false).timeout.connect(func(): if is_instance_valid(parent): cb.call())
		Fx._wave(parent, pos, color.lightened(0.15 * ring), rr * 1.3, 0.4, 0.12 * ring)
	var sp := Fx._burst(parent, pos + Vector3(0, 0.4, 0), color.lightened(0.45), "spark", 30, 0.8, "ur_tide_spray")
	if sp != null:
		sp.direction = Vector3.UP
		sp.spread = 60.0
		sp.initial_velocity_min = 4.0
		sp.initial_velocity_max = 8.0
		sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		sp.emission_sphere_radius = r * 0.6
	Fx.halo(parent, pos + Vector3(0, 1.2, 0), color, r * 2.4, 0.6, 1.3, "ur_tide_glow")
	sigil(parent, pos, color.lightened(0.15), r * 1.1, 0.9)
	Fx._surge(parent, Fx._mesh("pillar", color.lightened(0.3)), pos, "ur_tide_core", 1.6, 7.0, 0.8, Fx.soft_material())
	var sp2 := Fx._burst(parent, pos + Vector3(0, 2.5, 0), color.lightened(0.35), "spark", 30, 1.0, "ur_tide_rain")
	if sp2 != null:  # 치솟은 물이 사방으로 쏟아진다
		sp2.direction = Vector3.UP
		sp2.spread = 80.0
		sp2.gravity = Vector3(0, -14.0, 0)
		sp2.initial_velocity_min = r * 1.5
		sp2.initial_velocity_max = r * 2.6
	Fx.screen_flash(parent, pos, color.lerp(Color(1, 1, 1), 0.3), 0.18)


# --- 백호 ---

## 백호 참격: 앞쪽으로 커다란 발톱 자국 세 줄이 길이 length만큼 그어지고(가산 흰 빛) 끝에 번개 불꽃.
static func claws(parent: Node, from: Vector3, dir: Vector3, length: float, color: Color, flip := false) -> void:
	var yaw := atan2(-dir.x, -dir.z)
	var side := Vector3(-dir.z, 0, dir.x)
	for i in 3:
		var off := side * (i - 1) * 0.45 * (length / 4.0)
		var mi := _put(parent, "claw", color, from + off + Vector3(0, 0.7, 0), "ur_claw")
		if mi == null:
			break
		mi.rotation = Vector3(0, yaw, (0.5 if flip else -0.5))
		mi.scale = Vector3(2.2, 1.0, 0.2)
		var tw := mi.create_tween()
		tw.tween_interval(0.03 * i)
		tw.tween_property(mi, "scale", Vector3(2.2, 1.0, length * 1.1), 0.1).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.2)
		tw.tween_callback(mi.queue_free)
		_fade(mi, 0.18, 0.2)
	var sp := Fx._burst(parent, from + dir * length * 0.6 + Vector3(0, 0.8, 0), color.lightened(0.5), "spark", 14, 0.35, "ur_claw_sparks")
	if sp != null:
		sp.direction = dir
		sp.spread = 40.0
		sp.initial_velocity_min = 7.0
		sp.initial_velocity_max = 13.0
	Fx.spark(parent, from + dir * length * 0.8 + Vector3(0, 0.8, 0), color.lightened(0.4), 1.0)
	Fx.halo(parent, from + dir * length * 0.5 + Vector3(0, 0.8, 0), color, length * 0.9, 0.3, 1.2, "ur_claw_glow")


## 백호 현신: 흰 번개가 몸을 감고, 발밑 빛 고리·기둥이 sec초 이어진다. 포효 파동 두 겹.
static func tiger_avatar(hero: Node3D, color: Color, sec: float) -> void:
	var w := hero.get_parent()
	var at := hero.global_position
	Fx.golden_tint(hero, Color(0.45, 0.7, 1.0), sec)
	for i in int(sec / 0.6):  # 현신 동안 흰 번개가 몸을 타고 오른다
		hero.get_tree().create_timer(0.6 * (i + 1), false).timeout.connect(func():
			if is_instance_valid(hero) and hero.is_inside_tree() and hero.is_alive():
				var p: Vector3 = hero.global_position
				var a := randf() * TAU
				Fx.lightning(hero.get_parent(), [p + Vector3(cos(a) * 0.5, 1.7, sin(a) * 0.5), p + Vector3(cos(a + 1.5) * 0.4, 0.4, sin(a + 1.5) * 0.4)], color, 0)
				Fx.halo(hero, p + Vector3(0, 1.0, 0), Color(0.5, 0.75, 1.0), 1.6, 0.3, 1.2, "ur_tiger_pulse"))
	Fx._wave(w, at, Color(0.45, 0.7, 1.0), 3.5, 0.35)
	Fx._wave(w, at, color, 4.5, 0.45, 0.1)
	Fx.halo(w, at + Vector3(0, 1.0, 0), Color(0.5, 0.75, 1.0), 3.5, 0.5, 1.3, "ur_tiger_roar")
	for i in 4:
		var a := TAU * i / 4.0
		Fx.lightning(w, [at + Vector3(cos(a), 1.6, sin(a)) * 0.9, at + Vector3(cos(a + 0.6) * 0.4, 0.5, sin(a + 0.6) * 0.4)], color, 1)
	for i in 5:  # 둘레에 하늘 번개가 차례로 내리꽂힌다
		var a := TAU * i / 5.0 + randf() * 0.4
		var p := at + Vector3(cos(a), 0, sin(a)) * 3.0
		hero.get_tree().create_timer(0.07 * i, false).timeout.connect(func():
			if is_instance_valid(w):
				Fx.lightning(w, [p + Vector3(0, Fx.SKY_H, 0), p + Vector3(0.5, 4.0, 0.3), p], Color(0.6, 0.8, 1.0), 2)
				Fx.impact(w, p, Color(0.5, 0.75, 1.0), 0.6, -1, 0.3))
	Fx._surge(w, Fx._mesh("pillar", Color(0.6, 0.8, 1.0)), at, "ur_tiger_pillar", 1.6, 6.0, 0.7)


# --- 연화 ---

## 매혹: 머리 위에 분홍 하트가 튀어나와 sec초 머문다(대상 자식).
static func charm(target: Node3D, color: Color, height: float, sec: float) -> void:
	var mi := _put(target, "heart", color, target.global_position + Vector3(0, height, 0), "ur_charm", Fx.soft_material())
	if mi == null:
		return
	Fx._face_camera(mi)
	mi.scale = Vector3.ONE * 0.1
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 0.7, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(0.1, sec - 0.3))
	tw.tween_property(mi, "scale", Vector3.ONE * 0.05, 0.15)
	tw.tween_callback(mi.queue_free)


## 아홉 꼬리 한 번: 시전자 둘레를 꼬리 모양 참격이 angle 쪽에서 반 바퀴 휘감는다(반지름 r).
static func tail_sweep(parent: Node, pos: Vector3, color: Color, r: float, angle: float) -> void:
	var mi := _put(parent, "tail", color, pos + Vector3(0, 0.7, 0), "ur_tail")
	if mi == null:
		return
	mi.rotation = Vector3(randf_range(-0.25, 0.25), angle, randf_range(-0.25, 0.25))
	mi.scale = Vector3(r * 0.6, 1.6, r * 0.6)
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3(r * 1.25, 1.6, r * 1.25), 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "rotation:y", angle + 2.4, 0.3)
	tw.chain().tween_callback(mi.queue_free)
	_fade(mi, 0.14, 0.16)
	var fl := Fx._burst(parent, pos + Vector3(cos(-angle) * r * 0.8, 0.8, sin(-angle) * r * 0.8), color.lightened(0.3), "ember", 8, 0.6, "ur_tail_fire", Fx.glow_material())
	if fl != null:  # 꼬리 끝에서 여우불이 흩날린다
		fl.direction = Vector3.UP
		fl.spread = 90.0
		fl.initial_velocity_min = 1.5
		fl.initial_velocity_max = 3.5


## 구미호 해방 마무리: 분홍 여우불이 사방으로 터지고 바닥에 꽃잎 같은 섬광.
static func fox_bloom(parent: Node, pos: Vector3, color: Color, r: float) -> void:
	Fx.nova(parent, pos, color, r, 2)
	var sp := Fx._burst(parent, pos + Vector3(0, 0.8, 0), color.lightened(0.3), "ember", 36, 1.0, "ur_fox_bloom", Fx.glow_material())
	if sp != null:
		sp.direction = Vector3.UP
		sp.spread = 100.0
		sp.gravity = Vector3(0, 1.0, 0)
		sp.initial_velocity_min = 2.0
		sp.initial_velocity_max = 5.0
	burst(parent, pos, color, r)
	for i in 9:  # 아홉 갈래 여우불 기둥
		var a := TAU * i / 9.0
		Fx._surge(parent, Fx._mesh("pillar", color.lightened(0.15)), pos + Vector3(cos(a), 0, sin(a)) * r * 0.75, "ur_fox_pillar", 0.4, 3.5, 0.6, Fx.fire_material())
	Fx.screen_flash(parent, pos, color.lerp(Color(1, 1, 1), 0.3), 0.2)


## 여우불 구슬: 시전자 둘레에 구슬 n개가 sec초 돌다가 사라진다(날아가는 구슬은 투사체가 맡는다).
static func fox_orbs(hero: Node3D, color: Color, n: int, sec: float) -> void:
	var w := hero.get_parent()
	for i in n:
		var g := Fx.halo(w, hero.global_position + Vector3(0, 1.4, 0), color.lightened(0.3), 0.9, 0.0, 1.0, "ur_fox_orb")
		if g == null:
			return
		var a0 := TAU * i / n
		var tw := g.create_tween()
		tw.tween_method(func(t: float):
			if is_instance_valid(hero):
				var a := a0 + t * TAU * 1.5
				g.global_position = hero.global_position + Vector3(cos(a) * 1.3, 1.4 + 0.3 * sin(a * 2.0), sin(a) * 1.3), 0.0, 1.0, sec)
		tw.tween_callback(g.queue_free)


# --- 청룡 ---

## 청룡시: from → to로 푸른 용 몸통 나선이 뻗고(가산 빛), 지나간 자리에 물보라, 끝에 물기둥.
static func dragon_arrow(parent: Node, from: Vector3, to: Vector3, color: Color) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.1:
		return
	var mi := _put(parent, "helix", color, from, "ur_dragon_arrow")
	if mi != null:
		mi.look_at(to, Vector3.UP)
		mi.scale = Vector3(3.2, 3.2, 0.05)
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3(3.2, 3.2, length), 0.18).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(mi, "rotation:z", mi.rotation.z + 3.0, 0.6)
		tw.tween_callback(mi.queue_free)
		_fade(mi, 0.3, 0.3)
	var m2 := _put(parent, "helix", color.lightened(0.3), from, "ur_dragon_arrow")
	if m2 != null:  # 반대로 감기는 두 번째 몸통(두 마리 용이 얽혀 나간다)
		m2.look_at(to, Vector3.UP)
		m2.rotation.z += PI
		m2.scale = Vector3(2.0, 2.0, 0.05)
		var t2 := m2.create_tween()
		t2.tween_property(m2, "scale", Vector3(2.0, 2.0, length), 0.22).set_ease(Tween.EASE_OUT)
		t2.parallel().tween_property(m2, "rotation:z", m2.rotation.z - 3.0, 0.6)
		t2.tween_callback(m2.queue_free)
		_fade(m2, 0.3, 0.3)
	Fx.breath(parent, from, (to - from).normalized(), length, color.lightened(0.1), 1)
	Fx.pierce(parent, from, to, color.lightened(0.3), 2)
	for i in 4:
		var at := from.lerp(to, (i + 1) / 5.0)
		Fx.splash(parent, Vector3(at.x, 0, at.z), color, 1.2)
	Fx._surge(parent, Fx._mesh("pillar", color), Vector3(to.x, 0, to.z), "ur_dragon_end", 1.0, 3.5, 0.5, Fx.soft_material())
	Fx.halo(parent, to, color.lightened(0.3), 3.0, 0.4, 1.3, "ur_dragon_glow")
	burst(parent, Vector3(to.x, 0, to.z), color, 1.8)


## 청룡 강림: 대상 자리 둘레를 푸른 용이 sec초 동안 휘감아 돌고(반지름 r), 바닥 물빛 지대가 깔린다.
static func dragon_coil(parent: Node, pos: Vector3, color: Color, r: float, sec: float) -> void:
	Fx.zone(parent, pos, color, r, sec, "blizzard", 2)
	sigil(parent, pos, color.lightened(0.1), r * 1.15, sec)
	var dive := _put(parent, "helix", color.lightened(0.2), pos + Vector3(0, 12.0, 0), "ur_coil_dive")
	if dive != null:  # 하늘에서 용이 내리꽂힌다
		dive.look_at(pos, Vector3.FORWARD)
		dive.scale = Vector3(3.0, 3.0, 0.05)
		var td := dive.create_tween()
		td.tween_property(dive, "scale", Vector3(3.0, 3.0, 12.0), 0.25).set_ease(Tween.EASE_IN)
		td.parallel().tween_property(dive, "rotation:z", 4.0, 0.5)
		td.tween_callback(dive.queue_free)
		_fade(dive, 0.25, 0.25)
	Fx.impact(parent, pos, color, r * 0.4, 2, 0.6)
	var rain := Fx._stream(parent, pos + Vector3(0, 6.0, 0), color.lightened(0.4), "spark", 40.0, 0.5, sec, "ur_coil_rain")
	if rain != null:  # 용이 부르는 비
		rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		rain.emission_box_extents = Vector3(r, 0.2, r)
		rain.direction = Vector3.DOWN
		rain.spread = 5.0
		rain.gravity = Vector3(0, -20.0, 0)
		rain.initial_velocity_min = 8.0
		rain.initial_velocity_max = 12.0
	for layer in 3:
		var mi := _put(parent, "coil", color.lightened(0.15 * layer), pos + Vector3(0, 0.2 + 0.7 * layer, 0), "ur_coil")
		if mi == null:
			break
		mi.scale = Vector3(r * 0.3, 1.5, r * 0.3)
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3(r, 1.8 + 0.4 * layer, r) * (1.0 - 0.15 * layer), 0.3).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(mi, "rotation:y", (TAU if layer != 1 else -TAU) * sec / 1.2, sec)
		tw.tween_property(mi, "scale", Vector3(r * 0.2, 4.0, r * 0.2), 0.25).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)
	Fx.halo(parent, pos + Vector3(0, 1.0, 0), color, r * 2.2, sec, 1.1, "ur_coil_glow")


# --- 크로노스 ---

## 시계 문자판: 바닥에 문자판이 펼쳐지고 두 바늘이 거꾸로 돈다(sec초, 반지름 r). 문자판은 아주 천천히 돈다.
static func clock(parent: Node, pos: Vector3, color: Color, r: float, sec: float, reverse := true) -> void:
	var face := _put(parent, "clock", color, pos + Vector3(0, 0.06, 0), "ur_clock")
	if face == null:
		return
	face.scale = Vector3(0.1, 1.0, 0.1)
	var tw := face.create_tween()
	tw.tween_property(face, "scale", Vector3(r, 1.0, r), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(face, "rotation:y", 0.4 if reverse else -0.4, sec)
	tw.tween_callback(face.queue_free)
	_fade(face, 0.3, maxf(0.0, sec - 0.3))
	for i in 2:
		var hand := _put(parent, "hand", color.lightened(0.2), pos + Vector3(0, 0.09 + 0.01 * i, 0), "ur_clock_hand")
		if hand == null:
			break
		var len := r * (0.85 if i == 0 else 0.55)
		hand.scale = Vector3(len, 1.0, len * 1.4)
		var turns := (3.0 if i == 0 else 0.5) * (1.0 if reverse else -1.0)
		var th := hand.create_tween()
		th.tween_property(hand, "rotation:y", TAU * turns, sec)
		th.tween_callback(hand.queue_free)
		_fade(hand, 0.3, maxf(0.0, sec - 0.3))
	Fx.halo(parent, pos + Vector3(0, 0.4, 0), color, r * 2.2, 0.5, 1.2, "ur_clock_glow")
	sigil(parent, pos, color.lightened(0.1), r * 1.2, sec)
	var sky := _put(parent, "clock", color.lightened(0.15), pos + Vector3(0, 3.6, 0), "ur_clock_sky")
	if sky != null:  # 공중에 선 커다란 시계(카메라를 본다), 거꾸로 돌며 sec초 머문다
		var cam := sky.get_viewport().get_camera_3d()
		if cam != null:
			sky.look_at(cam.global_position, Vector3.UP)
			sky.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
		sky.scale = Vector3.ONE * 0.1
		var ts := sky.create_tween()
		ts.tween_property(sky, "scale", Vector3(r * 0.75, 1.0, r * 0.75), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		ts.tween_interval(maxf(0.1, sec - 0.5))
		ts.tween_property(sky, "scale", Vector3(r * 1.1, 1.0, r * 1.1), 0.25)
		ts.tween_callback(sky.queue_free)
		_fade(sky, 0.25, maxf(0.0, sec - 0.25))
	var shards := Fx._burst(parent, pos + Vector3(0, 1.2, 0), color.lightened(0.45), "mote", 26, sec, "ur_clock_frozen")
	if shards != null:  # 멈춘 시간 속에 떠 있는 빛 조각
		shards.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		shards.emission_sphere_radius = r * 0.8
		shards.gravity = Vector3.ZERO
		shards.initial_velocity_min = 0.0
		shards.initial_velocity_max = 0.3
		shards.explosiveness = 1.0
		shards.scale_amount_min = 1.5
		shards.scale_amount_max = 3.0


## 시간 역행: 대상 둘레에서 빛 조각이 위에서 아래로 감겨 내려앉는다(되감기).
static func rewind(target: Node3D, color: Color) -> void:
	var w := target.get_parent()
	Fx._motes(w, target.global_position + Vector3(0, 2.0, 0), color.lightened(0.3), 0.7, -1.8, 0.7)
	Fx.halo(w, target.global_position + Vector3(0, 0.9, 0), color, 1.8, 0.5, 0.7, "ur_rewind")


## 시간 붕괴: 바깥 고리가 sec초 동안 안으로 빨려들고(파동 거꾸로), 가운데 균열이 커지다가 터진다(폭발은 부르는 쪽이 sec 뒤에).
static func collapse(parent: Node, pos: Vector3, color: Color, r: float, sec: float) -> void:
	Fx.rift(parent, pos, color, r, 2)
	clock(parent, pos, color.lightened(0.2), r * 1.1, sec, false)
	for i in 3:
		var mi := Fx._spawn(parent, Fx._mesh("shock", color.lightened(0.2 * i)), pos + Vector3(0, 0.08, 0), "ur_collapse_ring", Fx.glow_material())
		if mi == null:
			break
		mi.scale = Vector3(r * 1.6, 1.0, r * 1.6)
		var tw := mi.create_tween()
		tw.tween_interval(sec / 3.0 * i)
		tw.tween_property(mi, "scale", Vector3(0.1, 1.0, 0.1), sec / 3.0 * (3 - i)).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		tw.tween_callback(mi.queue_free)
	var suck := Fx._burst(parent, pos + Vector3(0, 0.6, 0), color.lightened(0.4), "mote", 30, sec, "ur_collapse_suck")
	if suck != null:
		suck.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		suck.emission_sphere_radius = r * 1.3
		suck.gravity = Vector3.ZERO
		suck.radial_accel_min = -r * 3.0
		suck.radial_accel_max = -r * 2.0
		suck.explosiveness = 0.3


# --- 주작 ---

## 불새: from → to로 날개 편 불새가 날아가며(sec초) 불티를 흘리고, 도착하면 불꽃이 터진다.
static func phoenix(parent: Node, from: Vector3, to: Vector3, color: Color, sec: float, size := 4.4) -> void:
	var bird := _put(parent, "wings", color, from, "ur_phoenix")
	if bird == null:
		Fx.blast(parent, Vector3(to.x, 0, to.z), color, 2.0, false, 2)
		return
	var flat := Vector3(to.x - from.x, 0, to.z - from.z)
	if flat.length() > 0.01:
		bird.look_at(from + flat, Vector3.UP)
	bird.scale = Vector3.ONE * size
	Fx.halo(bird, from, color.lightened(0.3), size * 1.4, 0.0)
	var trail := Fx._stream(bird, from, color.lightened(0.2), "ember", 90.0, 0.8, sec, "ur_phoenix_trail")
	if trail != null:
		trail.spread = 40.0
		trail.gravity = Vector3(0, 0.5, 0)
		trail.scale_amount_min = 1.5
		trail.scale_amount_max = 3.0
	var tw := bird.create_tween()
	tw.tween_method(func(t: float):
		bird.global_position = from.lerp(to, t) + Vector3(0, sin(t * PI) * 1.5, 0)
		bird.scale = Vector3(size, size, size) * (1.0 + 0.12 * sin(t * TAU * 3.0)), 0.0, 1.0, sec)
	tw.tween_callback(func():
		var g := Vector3(to.x, 0, to.z)
		Fx.blast(parent, g, color, 2.6, false, 2, 2)
		Fx._surge(parent, Fx._mesh("pillar", color), g, "ur_phoenix_pillar", 1.4, 5.5, 0.7, Fx.fire_material())
		Fx._wave(parent, g, color.lightened(0.3), 4.5, 0.45)
		bird.queue_free())


## 환생의 불꽃: 대상 발밑에서 불기둥이 솟고 머리 위로 날개 빛무리가 펼쳐진다.
static func rebirth(target: Node3D, color: Color) -> void:
	var w := target.get_parent()
	var at: Vector3 = Vector3(target.global_position.x, 0, target.global_position.z)
	Fx._surge(w, Fx._mesh("pillar", color), at, "ur_rebirth_pillar", 1.2, 4.5, 0.8, Fx.fire_material())
	var wings := _put(w, "wings", color.lightened(0.2), at + Vector3(0, 2.2, 0), "ur_rebirth_wings")
	if wings != null:
		wings.rotation.x = -PI / 2.0
		var cam := wings.get_viewport().get_camera_3d()
		if cam != null:
			wings.rotation.y = cam.global_rotation.y
		wings.scale = Vector3.ONE * 0.3
		var tw := wings.create_tween()
		tw.tween_property(wings, "scale", Vector3.ONE * 2.2, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.4)
		tw.tween_callback(wings.queue_free)
		_fade(wings, 0.3, 0.4)
	Fx.heal_ring(w, at, 1.6, 2)
	Fx.halo(w, at + Vector3(0, 1.2, 0), color, 3.2, 0.8, 1.3, "ur_rebirth_glow")

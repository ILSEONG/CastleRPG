extends RefCounted
## 영웅 시각(스펙 §3.4): 발밑 6각 링, 투사체 모양(마법 20면체·도끼·화살 — 나는 건 projectile.gd), 스킬 이펙트. 전부 MeshKit 로우폴리 메시 +
## 공유 정점 색 재질 하나(양면, 그림자 없음). 이펙트는 짧게(≤0.6초) 살고 스스로 해제되며, 동시 수는 MAX_LIVE까지만.
## 메시는 (종류, 색)마다 한 번 만들어 캐시한다. 오토로드 참조 없음.
## 상한은 살아 있는 수를 세어 본다(track이 더하고 트리에서 빠질 때 뺀다) — 생성마다 그룹 배열을 만들지 않는다.

const Art := preload("res://scripts/art.gd")
const MeshKit := preload("res://scripts/mesh_kit.gd")

const MAX_LIVE := 48  # 동시에 살아 있는 이펙트·투사체 모양 상한(넘으면 그 이펙트는 건너뛴다)
const GROUP := "fx"
const ARROW_PITCH_FIX := PI / 2.0  # 화살 모델은 길이 축 Y, 촉이 -Y → X축 +90°로 촉을 -Z(look_at 정면)에 맞춘다
const HEAL_GREEN := Color(0.40, 0.85, 0.45)
const STUN_YELLOW := Color(1.0, 0.85, 0.2)
const SLOW_BLUE := Color(0.55, 0.85, 1.0)
const POISON_GREEN := Color(0.45, 0.80, 0.25)
const REPAIR_GOLD := Color(0.95, 0.75, 0.25)
const AXE_WOOD := Color(0.55, 0.38, 0.24)
const AXE_METAL := Color(0.62, 0.64, 0.68)

static var _meshes := {}
static var _live := 0  # 지금 살아 있는 이펙트·투사체 수
static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = Art.LOWPOLY_DOUBLE_SHADER
		_material.set_shader_parameter("use_texture", false)
		_material.set_shader_parameter("use_vertex_color", true)
	return _material


## 발밑 링: 바깥 6각 고리 = 등급 색, 안쪽 고리 = 고유 색. 선택 링(토러스 0.6~0.8)보다 작다.
static func foot_ring(grade_color: Color, color: Color) -> MeshInstance3D:
	var key := "ring" + grade_color.to_html() + color.to_html()
	if not _meshes.has(key):
		var k = MeshKit.new()
		_hex_ring(k, 0.42, 0.55, 0.05, grade_color)
		_hex_ring(k, 0.30, 0.42, 0.04, color)
		_meshes[key] = k.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## 병사 발밑 원판(개정 13 §7): 병종 색 8각 원판 + 진한 테두리(영웅 6각 고리와 구분). radius = 바깥 반지름(기병은 말 길이만큼 크게).
static func soldier_disc(color: Color, radius := 0.45) -> MeshInstance3D:
	var key := "disc%s%.2f" % [color.to_html(), radius]
	if not _meshes.has(key):
		var k = MeshKit.new()
		k.prism_n(Vector3.ZERO, 8, radius, radius, 0.04, color.darkened(0.3), PI / 8.0)
		k.prism_n(Vector3.ZERO, 8, radius * 0.8, radius * 0.8, 0.05, color, PI / 8.0)
		_meshes[key] = k.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## 투사체 모양(projectile.gd가 부른다): "bolt" = 고유 색 20면체(마법), "axe" = 도끼, "arrow" = 화살 모델. 투사체 노드 proj(정면 -Z)의
## 자식으로 붙이고 상한 수에 넣는다. 상한이면 붙이지 않고 null(투사체는 모양 없이 난다).
static func dress_projectile(proj: Node3D, kind: String, color: Color) -> Node3D:
	if full(proj):
		return null
	var look: Node3D
	if kind == "arrow":
		look = Art.instance(Art.ARROW_MODEL)
		look.scale = Vector3.ONE * Art.ARROW_SCALE
		look.rotation.x = ARROW_PITCH_FIX
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh(kind, color if kind == "bolt" else Color.WHITE)
		mi.material_override = material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		look = mi
	proj.add_child(look)
	track(look)
	return look


## aoe_blast: 고유 색 20면체가 반경까지 커졌다가 사라진다.
static func blast(parent: Node, pos: Vector3, color: Color, radius: float) -> void:
	var mi := _spawn(parent, _mesh("blast", color), pos + Vector3(0, 0.5, 0))
	if mi != null:
		mi.scale = Vector3.ONE * 0.3
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3.ONE * radius, 0.3).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.15)
		tw.tween_callback(mi.queue_free)


## heal_aura: 초록 6각 고리가 반경까지 퍼진다.
static func heal_ring(parent: Node, pos: Vector3, radius: float) -> void:
	var mi := _spawn(parent, _mesh("heal"), pos + Vector3(0, 0.1, 0))
	if mi != null:
		mi.scale = Vector3.ONE * 0.2
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), 0.5).set_ease(Tween.EASE_OUT)
		tw.tween_callback(mi.queue_free)


## chain: 점들을 잇는 각진 번개 선(구간마다 3번 꺾임). 메시는 매번 만든다(0.3초만 산다).
static func lightning(parent: Node, points: Array, color: Color) -> void:
	if points.size() < 2 or full(parent):
		return
	var k = MeshKit.new()
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var side := (b - a).cross(Vector3.UP).normalized() * 0.35
		var prev := a
		for j in range(1, 5):
			var p := a.lerp(b, j / 4.0)
			if j < 4:
				p += side if j % 2 == 1 else -side
			_ribbon(k, prev, p, 0.09, color)
			prev = p
	var mi := _spawn(parent, k.commit(), Vector3.ZERO)
	if mi != null:
		var tw := mi.create_tween()
		tw.tween_interval(0.3)
		tw.tween_callback(mi.queue_free)


## stun: 대상 머리 위 노란 각진 별 3개가 돈다. target을 따라간다(자식).
static func stun(target: Node3D, height: float) -> void:
	var mi := _spawn(target, _mesh("stun"), target.global_position + Vector3(0, height, 0))
	if mi != null:
		var tw := mi.create_tween()
		tw.tween_property(mi, "rotation:y", TAU, 0.6)
		tw.tween_callback(mi.queue_free)


## slow: 대상 발밑 하늘색 결정.
static func slow(target: Node3D) -> void:
	_pop(target, _mesh("slow"), target.global_position, Vector3.ZERO)


## poison: 대상 위 초록 작은 거품 2개가 떠오른다.
static func poison(target: Node3D, height: float) -> void:
	_pop(target, _mesh("poison"), target.global_position + Vector3(0, height, 0), Vector3(0, 0.5, 0))


## gate_repair: 성문에 금색 각진 조각들이 반짝이며 떠오른다.
static func repair(parent: Node, pos: Vector3) -> void:
	_pop(parent, _mesh("repair"), pos + Vector3(0, 2.0, 0), Vector3(0, 0.8, 0))


# --- 내부 ---

## 이펙트 상한에 찼거나 parent가 트리 밖이면 true.
static func full(parent: Node) -> bool:
	return parent == null or not parent.is_inside_tree() or _live >= MAX_LIVE


## 트리에 넣은 이펙트 노드를 상한 수에 넣는다. 트리에서 빠질 때(queue_free·부모 해제) 저절로 빠진다. 투사체 모양도 쓴다.
static func track(node: Node) -> void:
	node.add_to_group(GROUP)
	_live += 1
	node.tree_exiting.connect(func(): _live -= 1, CONNECT_ONE_SHOT)


static func live() -> int:
	return _live


static func _mesh(kind: String, color := Color.WHITE) -> Mesh:
	var key := kind + color.to_html()
	if not _meshes.has(key):
		_meshes[key] = _build(kind, color)
	return _meshes[key]


static func _build(kind: String, color: Color) -> ArrayMesh:
	var k = MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	match kind:
		"bolt":
			k.rock(Vector3.ZERO, 0.22, color, rng, 1.0)
		"blast":
			k.rock(Vector3.ZERO, 1.0, color, rng, 1.0)
		"axe":
			k.box(Vector3(0, 0, -0.35), Vector3(0.07, 0.07, 0.7), AXE_WOOD)
			k.box(Vector3(0, -0.12, 0.25), Vector3(0.05, 0.26, 0.24), AXE_METAL)
		"heal":
			_hex_ring(k, 0.85, 1.0, 0.08, HEAL_GREEN)
		"slow":
			for i in 3:
				var a := TAU * i / 3.0
				k.cone(Vector3(cos(a), 0, sin(a)) * 0.45, 4, 0.12, 0.45, SLOW_BLUE)
		"poison":
			k.rock(Vector3(0.2, 0, 0), 0.13, POISON_GREEN, rng, 1.0)
			k.rock(Vector3(-0.15, 0.25, 0.1), 0.09, POISON_GREEN, rng, 1.0)
		"repair":
			for i in 5:
				var a := TAU * i / 5.0
				k.pyramid(Vector3(cos(a) * 0.9, 0.3 * (i % 2), sin(a) * 0.9), 0.25, 0.35, REPAIR_GOLD)
		"stun":  # 각진 별 3개(납작한 6각 별 = 삼각형 둘)를 머리 위 고리에
			for i in 3:
				var c := Vector3(cos(TAU * i / 3.0), 0, sin(TAU * i / 3.0)) * 0.4
				for flip in [0.0, PI]:
					var pts := []
					for j in 3:
						var a: float = flip + TAU * j / 3.0 + PI / 2.0
						pts.append(c + Vector3(cos(a), sin(a), 0) * 0.14)
					k.face(pts, Vector3.BACK, STUN_YELLOW)
	return k.commit()


## 이펙트 노드 하나를 parent 아래 월드 위치 pos에 놓는다. 상한이면 null.
static func _spawn(parent: Node, m: Mesh, pos: Vector3) -> MeshInstance3D:
	if full(parent):
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	track(mi)
	mi.global_position = pos
	return mi


## 작게 튀어나와(0.5초) rise만큼 떠오르고 사라지는 이펙트.
static func _pop(parent: Node, m: Mesh, pos: Vector3, rise: Vector3) -> void:
	var mi := _spawn(parent, m, pos)
	if mi == null:
		return
	mi.scale = Vector3.ONE * 0.3
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE, 0.15)
	tw.tween_property(mi, "global_position", pos + rise, 0.5)
	tw.chain().tween_callback(mi.queue_free)


static func _hex_ring(k, r_in: float, r_out: float, h: float, color: Color) -> void:
	for i in 6:
		var o0 := Vector3(cos(TAU * i / 6.0), 0, sin(TAU * i / 6.0))
		var o1 := Vector3(cos(TAU * (i + 1) / 6.0), 0, sin(TAU * (i + 1) / 6.0))
		var top := Vector3(0, h, 0)
		k.face([o0 * r_in + top, o0 * r_out + top, o1 * r_out + top, o1 * r_in + top], Vector3.UP, color)
		k.face([o0 * r_out, o1 * r_out, o1 * r_out + top, o0 * r_out + top], o0 + o1, color.darkened(0.15))


## a→b 띠: 가로·세로로 교차한 두 장(어느 각도에서도 보인다).
static func _ribbon(k, a: Vector3, b: Vector3, w: float, color: Color) -> void:
	var d := (b - a).normalized()
	var flat := d.cross(Vector3.UP).normalized() * w
	if flat.length() < 0.001:
		flat = Vector3(w, 0, 0)
	var up := d.cross(flat).normalized() * w
	k.face([a - flat, a + flat, b + flat, b - flat], up, color)
	k.face([a - up, a + up, b + up, b - up], flat, color)

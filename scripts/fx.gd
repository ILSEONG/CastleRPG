extends RefCounted
## 영웅 시각(스펙 §3.4): 발밑 6각 링, 투사체 모양(마법 20면체·도끼·화살 — 나는 건 projectile.gd), 스킬 이펙트. 전부 MeshKit 로우폴리 메시 +
## 공유 재질 둘(정점 색 양면 / 가산 색 섬광, 그림자 없음). 이펙트는 짧게 살고 스스로 해제되며, 동시 수는 MAX_LIVE까지만.
## 상태 이펙트(stun·slow·poison)는 지속 동안 남는다 — 지우는 건 monster.gd(상태가 끝날 때).
## 메시는 (종류, 색)마다 한 번 만들어 캐시한다. 오토로드 참조 없음.
## 상한은 살아 있는 수를 세어 본다(track이 더하고 트리에서 빠질 때 뺀다) — 생성마다 그룹 배열을 만들지 않는다.
## 개정 17 §3: 폭발(충격파 고리·파편·섬광·흔들림), 이중선 번개 + 불꽃, 치유 십자, 치명타 별, 처형 X, 수리 망치, 투사체 꼬리, 발동 맥동.
## 등급 연출: 스킬 이펙트는 영웅 등급의 단계 tier(R 0 · SR 1 · SSR 2)를 받아 크기가 TIER_SCALE배가 되고, 단계가 오를수록 겹이 는다 —
## 발동: 빛 광선(모두) + 떠오르는 입자(SR+) + 빛기둥·두 번째 파동(SSR). 폭발·치유·번개·휩쓸기·기절·처형·수리도 같은 식.
## 겹마다 노드 하나(입자·광선 여럿을 메시 하나에 담는다)라 상한·성능 부담은 겹 수만큼만 는다.

const Art := preload("res://scripts/art.gd")
const MeshKit := preload("res://scripts/mesh_kit.gd")
const AddShader := preload("res://shaders/fx_add.gdshader")
const SoftShader := preload("res://shaders/fx_soft.gdshader")
const HaloShader := preload("res://shaders/fx_halo.gdshader")

const MAX_LIVE := 64  # 동시에 살아 있는 이펙트·투사체 모양 상한(넘으면 그 이펙트는 건너뛴다)
const GROUP := "fx"
const ARROW_PITCH_FIX := PI / 2.0  # 화살 모델은 길이 축 Y, 촉이 -Y → X축 +90°로 촉을 -Z(look_at 정면)에 맞춘다
const HEAL_GREEN := Color(0.40, 0.85, 0.45)
const STUN_YELLOW := Color(1.0, 0.85, 0.2)
const SLOW_BLUE := Color(0.55, 0.85, 1.0)
const POISON_GREEN := Color(0.45, 0.80, 0.25)
const REPAIR_GOLD := Color(0.95, 0.75, 0.25)
const CRIT_ORANGE := Color(1.0, 0.62, 0.15)
const SLASH_RED := Color(0.9, 0.12, 0.1)
const AURA_ORANGE := Color(1.0, 0.55, 0.15)
const DUST := Color(0.72, 0.62, 0.48)
const AXE_WOOD := Color(0.55, 0.38, 0.24)
const AXE_METAL := Color(0.62, 0.64, 0.68)
const SHARDS_MIN := 8
const SHARDS_MAX := 12
const STUN_SCALE := 1.7  # 개정 17: 기절 별을 크게
const SHAKE_SEC := 0.15
const SHAKE_AMP := 0.25
const KICK_AMP := [0.1, 0.22, 0.38]  # impact power → 흔들림(m)
const KICK_STOP := [0.0, 0.045, 0.07]  # impact power → 히트스톱(실제 초)
const SKY_H := 9.0  # 번개가 떨어지기 시작하는 높이(땅에서 m)
const BOLT_HIT_Y := 0.8  # 번개 맞은 지점(hero HIT_HEIGHT)에서 땅까지
const TIER := {"R": 0, "SR": 1, "SSR": 2}  # 등급 → 연출 단계
const TIER_SCALE := [1.0, 1.3, 1.65]  # 단계 → 스킬 이펙트 크기 배율

static var _meshes := {}
static var _live := 0  # 지금 살아 있는 이펙트·투사체 수
static var _material: ShaderMaterial
static var _glow: ShaderMaterial
static var _soft: ShaderMaterial
static var _fire: ShaderMaterial
static var _smoke: ShaderMaterial
static var _halo: ShaderMaterial
static var _quad: QuadMesh


## 등급의 연출 단계(모르는 등급은 0).
static func tier_of(grade: String) -> int:
	return int(TIER.get(grade, 0))


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = Art.LOWPOLY_DOUBLE_SHADER
		_material.set_shader_parameter("use_texture", false)
		_material.set_shader_parameter("use_vertex_color", true)
	return _material


## 가산 색 재질(섬광·번개 바깥 빛·발동 고리·입자). 하나를 공유한다 — 노드마다 fade(인스턴스 값)로 따로 사라진다(_fade).
static func glow_material() -> ShaderMaterial:
	if _glow == null:
		_glow = _fx_mat(AddShader, 1.15)
	return _glow


## 반투명 색 재질(빛기둥·휩쓸기 궤적·지대): 가산과 달리 밝은 바닥에서도 고유 색이 하얗게 날아가지 않는다. 정점 알파 × fade. 하나를 공유한다.
static func soft_material() -> ShaderMaterial:
	if _soft == null:
		_soft = _fx_mat(SoftShader, 1.0)
		_soft.set_shader_parameter("rim", 0.6)
	return _soft


## 불꽃 혀(화염 지대): 반투명 + 높이에 비례해 출렁인다(셰이더 flicker) — 가산이면 밝은 풀밭 위에서 하얗게 날아간다. 하나를 공유한다.
static func fire_material() -> ShaderMaterial:
	if _fire == null:
		_fire = _fx_mat(SoftShader, 1.1)
		_fire.set_shader_parameter("flicker", 1.0)
	return _fire


## 연기·먼지(입자): 반투명, 밝기 그대로. 하나를 공유한다.
static func smoke_material() -> ShaderMaterial:
	if _smoke == null:
		_smoke = _fx_mat(SoftShader, 1.0)
	return _smoke


static func _fx_mat(shader: Shader, boost: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("boost", boost)
	return m


## 발밑 링: 바깥 6각 고리 = 등급 색, 안쪽 고리 = 고유 색. 선택 링(토러스 0.6~0.8)보다 작다.
static func foot_ring(grade_color: Color, color: Color) -> MeshInstance3D:
	var key := "ring" + grade_color.to_html() + color.to_html()
	if not _meshes.has(key):
		var k = MeshKit.new()
		_hex_ring(k, 0.42, 0.55, 0.05, grade_color)
		_hex_ring(k, 0.30, 0.42, 0.04, color)
		_meshes[key] = k.commit()
	return _static(_meshes[key])


## atk_aura 버프 표시(개정 17): 받는 영웅 발밑의 은은한 주황 고리(영웅 자식, 늘 있다 — 상한에 넣지 않는다).
static func aura_ring() -> MeshInstance3D:
	return _static(_mesh("aura"))


## 병사 발밑 원판(개정 13 §7): 병종 색 8각 원판 + 진한 테두리(영웅 6각 고리와 구분). radius = 바깥 반지름(기병은 말 길이만큼 크게).
static func soldier_disc(color: Color, radius := 0.45) -> MeshInstance3D:
	var key := "disc%s%.2f" % [color.to_html(), radius]
	if not _meshes.has(key):
		var k = MeshKit.new()
		k.prism_n(Vector3.ZERO, 8, radius, radius, 0.04, color.darkened(0.3), PI / 8.0)
		k.prism_n(Vector3.ZERO, 8, radius * 0.8, radius * 0.8, 0.05, color, PI / 8.0)
		_meshes[key] = k.commit()
	return _static(_meshes[key])


## 투사체 모양(projectile.gd가 부른다): "bolt" = 고유 색 20면체(마법), "axe" = 도끼, "arrow" = 화살 모델. 투사체 노드 proj(정면 -Z)의
## 자식으로 붙이고 상한 수에 넣는다. 상한이면 붙이지 않고 null(투사체는 모양 없이 난다).
## tail(multishot, 개정 17) = 뒤에 고유 색 짧은 리본 3마디. 마법탄은 빛무리 + 불티 꼬리(입자)를 함께 단다(개정 25, 상한 안에서만).
static func dress_projectile(proj: Node3D, kind: String, color: Color, tail := false) -> Node3D:
	if full(proj):
		return null
	var look: Node3D
	if kind == "arrow":
		look = Art.instance(Art.ARROW_MODEL)
		look.scale = Vector3.ONE * Art.ARROW_SCALE
		look.rotation.x = ARROW_PITCH_FIX
	else:
		look = _static(_mesh(kind, color if kind == "bolt" else Color.WHITE))
	proj.add_child(look)
	track(look)
	if kind == "bolt":  # 마법탄(개정 25): 빛무리를 두르고 불티 꼬리를 흘린다
		halo(proj, proj.global_position, color.lightened(0.3), 1.0, 0.0)
		var trail := _stream(proj, proj.global_position, color.lightened(0.2), "ember", 30.0, 0.3, 30.0, "bolt_trail")
		if trail != null:
			trail.gravity = Vector3.ZERO
			trail.spread = 15.0
			trail.initial_velocity_max = 0.6
			trail.scale_amount_min = 1.2
			trail.scale_amount_max = 2.0
	if tail and not full(proj):
		var t := _static(_mesh("tail", color))
		proj.add_child(t)
		track(t)
	return look


## aoe_blast(개정 25): 고유 색 불덩이(가산)가 반경 쪽으로 부풀며 옅어지고, 하얀 심이 번쩍, 뒤에 빛무리가 번진다. 바닥 충격파 고리가 퍼지며 옅어지고,
## 각진 파편 SHARDS_MIN~MAX개가 포물선으로 튀고, 빛 불똥(입자)이 사방으로 흩어지고 연기 덩이가 피어오른다. 바닥엔 방사 섬광(burst).
## shake = 카메라를 약하게 흔든다(SSR, 설정 fx_shake — 호출자가 정한다). power = impact 세기(−1이면 SSR 1, 아니면 0 — 메테오는 더 세게 준다).
## tier 1+: 두 번째 충격파(wave)가 반경 1.35배까지. tier 2: 가운데 빛기둥(pillar)과 떠오르는 불티(motes). 단계마다 불똥이 늘어난다.
static func blast(parent: Node, pos: Vector3, color: Color, radius: float, shake := false, tier := 0, power := -1) -> void:
	impact(parent, pos, color, radius * 0.55, (1 if tier >= 2 else 0) if power < 0 else power)  # 타격 섬광·흔들림(개정 26)
	var hot := color.lightened(0.35)
	var mi := _spawn(parent, _mesh("blast", hot), pos + Vector3(0, 0.6, 0), "blast", soft_material())  # 불덩이(반투명 — 밝은 바닥에서도 제 색): 커지며 옅어진다
	if mi != null:
		mi.scale = Vector3.ONE * 0.3
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3.ONE * radius * 0.6, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.parallel().tween_property(mi, "rotation", Vector3(0.6, 1.2, 0.3), 0.4)
		tw.tween_property(mi, "scale", Vector3.ONE * radius * 0.7, 0.18)
		tw.tween_callback(mi.queue_free)
		_fade(mi, 0.3, 0.1)
	var ring := _spawn(parent, _mesh("shock", color.lightened(0.3)), pos + Vector3(0, 0.05, 0), "shock", glow_material())
	if ring != null:
		ring.scale = Vector3(0.3, 1.0, 0.3)
		var tr := ring.create_tween()
		tr.tween_property(ring, "scale", Vector3(radius * 1.15, 1.0, radius * 1.15), 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tr.tween_callback(ring.queue_free)
		_fade(ring, 0.25, 0.15)
	var flash := _spawn(parent, _mesh("flash", Color(1.0, 0.95, 0.8)), pos + Vector3(0, 0.6, 0), "flash", glow_material())  # 하얀 심: 0.12초 번쩍
	if flash != null:
		flash.scale = Vector3.ONE * radius * 0.3
		var tf := flash.create_tween()
		tf.tween_property(flash, "scale", Vector3.ONE * radius * 0.55, 0.12)
		tf.tween_callback(flash.queue_free)
		_fade(flash, 0.1, 0.02)
	halo(parent, pos + Vector3(0, 0.8, 0), hot, radius * 2.6, 0.45, 1.2, "blast_glow")
	var n := randi_range(SHARDS_MIN, SHARDS_MAX)
	for i in n:
		var s := _spawn(parent, _mesh("shard", color), pos + Vector3(0, 0.5, 0), "shard")
		if s == null:
			break
		var dir := Vector3.FORWARD.rotated(Vector3.UP, TAU * (i + randf() * 0.6) / n)
		var to := pos + dir * radius * randf_range(0.6, 1.1)
		var from := s.global_position
		var h := randf_range(1.0, 2.2)
		var spin := Vector3(randf(), randf(), randf()) * 9.0
		var ts := s.create_tween()
		ts.tween_method(func(t: float): _arc(s, from, to, h, spin, t), 0.0, 1.0, randf_range(0.45, 0.6))
		ts.tween_callback(s.queue_free)
	var sp := _burst(parent, pos + Vector3(0, 0.6, 0), hot, "spark", 14 + 6 * tier, 0.45, "blast_sparks")
	if sp != null:
		sp.initial_velocity_min = radius * 2.0
		sp.initial_velocity_max = radius * 3.6
	var sm := _burst(parent, pos + Vector3(0, 0.4, 0), color.lerp(Color(0.55, 0.52, 0.5), 0.7), "smoke", 6 + 2 * tier, 0.9, "blast_smoke")
	if sm != null:
		sm.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		sm.emission_sphere_radius = radius * 0.4
		sm.scale_amount_min = radius * 0.4
		sm.scale_amount_max = radius * 0.7
	_flare(parent, _mesh("burst", color), pos + Vector3(0, 0.08, 0), "burst", radius * 1.15, 0.4)
	if tier >= 1:
		_wave(parent, pos, color, radius * 1.35, 0.45, 0.12)
	if tier >= 2:
		_surge(parent, _mesh("pillar", color), pos, "pillar", radius * 0.4, radius * 2.2, 0.55, soft_material())
		_motes(parent, pos, color.lightened(0.2), radius * 0.8, 2.4, 0.8)
	if shake:
		shake_camera(parent)


## 병사 등장(개정 21 §1): 발밑에서 작은 흙빛 6각 고리가 퍼지며 사라진다(0.4초).
static func dust(parent: Node, pos: Vector3) -> void:
	var mi := _spawn(parent, _mesh("shock", DUST), pos + Vector3(0, 0.05, 0), "dust")
	if mi != null:
		mi.scale = Vector3.ONE * 0.3
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3.ONE * 0.9, 0.4).set_ease(Tween.EASE_OUT)
		tw.tween_callback(mi.queue_free)


## heal_aura: 초록 6각 고리가 반경까지 퍼지며 옅어지고, 반경 안에서 초록 빛 조각(입자)이 떠오른다. tier 1+: 뒤따르는 두 번째 고리(heal2).
## tier 2: 시전자 자리 초록 빛기둥.
static func heal_ring(parent: Node, pos: Vector3, radius: float, tier := 0) -> void:
	var mi := _spawn(parent, _mesh("heal"), pos + Vector3(0, 0.1, 0), "heal", glow_material())
	if mi != null:
		mi.scale = Vector3.ONE * 0.2
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_callback(mi.queue_free)
		_fade(mi, 0.3, 0.2)
	_motes(parent, pos, HEAL_GREEN.lightened(0.35), radius * 0.85, 1.8, 0.9)
	if tier >= 1:
		var m2 := _spawn(parent, _mesh("heal"), pos + Vector3(0, 0.12, 0), "heal2", glow_material())
		if m2 != null:
			m2.scale = Vector3.ONE * 0.05
			var t2 := m2.create_tween()
			t2.tween_interval(0.15)
			t2.tween_property(m2, "scale", Vector3(radius * 0.8, 1.0, radius * 0.8), 0.45).set_ease(Tween.EASE_OUT)
			t2.tween_callback(m2.queue_free)
			_fade(m2, 0.25, 0.35)
	if tier >= 2:
		_surge(parent, _mesh("pillar", HEAL_GREEN), pos, "pillar", 1.1, 5.0, 0.6, soft_material())


## 회복받은 영웅: 머리 위로 각진 초록 십자 3개가 떠오르고 몸이 초록 빛무리로 한 번 빛난다(영웅을 따라간다).
static func heal_cross(target: Node3D) -> void:
	_pop(target, _mesh("cross"), target.global_position + Vector3(0, 1.4, 0), Vector3(0, 0.9, 0), "cross", 0.7)
	halo(target, target.global_position + Vector3(0, 1.0, 0), HEAL_GREEN, 1.6, 0.5, 1.3, "heal_glow")


## chain: 맞는 지점마다 하늘(SKY_H m 위)에서 각진 번개가 내리꽂힌다 — 7~9번 꺾이며 아래로 갈수록 덜 흔들리고, 중간에서 곁가지가
## 갈라진다(tier 1+면 둘). 반투명 고유 색 바깥 빛 + 가는 하얀 심을 한 메시씩(노드 둘, 가산)에 담아 번쩍·꺼짐·번쩍으로 깜빡이다 옅어진다(0.32초).
## 땅에 닿는 곳마다 별 불꽃(+ 불똥) + 빛무리 + 바닥 방사 섬광(tier 1+면 파동도). tier: 굵기·불꽃이 TIER_SCALE배. points = 맞은 지점(HIT_HEIGHT 높이).
static func lightning(parent: Node, points: Array, color: Color, tier := 0) -> void:
	if points.is_empty() or full(parent):
		return
	var glow = MeshKit.new()
	var core = MeshKit.new()
	var sc: float = TIER_SCALE[tier]
	for hit in points:
		var ground: Vector3 = hit - Vector3(0, BOLT_HIT_Y, 0)
		var top := ground + Vector3(randf_range(-0.8, 0.8), SKY_H, randf_range(-0.8, 0.8))
		var bends := randi_range(7, 9)
		var prev := top
		var path := [top]
		for j in range(1, bends + 2):
			var f := float(j) / (bends + 1)
			var p := top.lerp(ground, f)
			if j <= bends:
				var jitter := 0.55 * (1.0 - f * 0.6)
				p += Vector3(randf_range(-jitter, jitter), 0, randf_range(-jitter, jitter))
			_ribbon(glow, prev, p, 0.2 * sc, Color(color, 0.55))
			_ribbon(core, prev, p, 0.05 * sc, Color(1.0, 1.0, 1.0).lerp(color, 0.25))
			path.append(p)
			prev = p
		for k in 1 + mini(tier, 1):  # 곁가지: 위쪽 마디에서 비스듬히 아래로 3마디
			var bp: Vector3 = path[randi_range(2, 4)]
			var dir := Vector3(randf_range(-1, 1), -1.4, randf_range(-1, 1)).normalized()
			for _m in 3:
				var q := bp + dir * randf_range(0.5, 0.8) + Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2))
				_ribbon(glow, bp, q, 0.1 * sc, Color(color, 0.45))
				_ribbon(core, bp, q, 0.03 * sc, Color(1.0, 1.0, 1.0).lerp(color, 0.3))
				bp = q
	for mk in [glow, core]:
		var mi := _spawn(parent, mk.commit(), Vector3.ZERO, "lightning", glow_material())
		if mi != null:
			var tw := mi.create_tween()
			tw.tween_interval(0.07)
			tw.tween_callback(func(): mi.visible = false)
			tw.tween_interval(0.04)
			tw.tween_callback(func(): mi.visible = true)
			tw.tween_interval(0.21)
			tw.tween_callback(mi.queue_free)
			_fade(mi, 0.18, 0.14)
	var first := true
	for hit in points:
		var ground: Vector3 = hit - Vector3(0, BOLT_HIT_Y, 0)
		spark(parent, hit, color.lightened(0.4), 0.6 * sc)
		if first:  # 첫 낙뢰만 타격 섬광·흔들림(사슬 번개가 화면을 계속 흔들지 않게)
			impact(parent, ground, color, 0.7 * sc, 1 if tier >= 1 else 0, BOLT_HIT_Y)
			first = false
		halo(parent, hit, color.lightened(0.3), 2.2 * sc, 0.3, 1.3, "bolt_glow")
		_flare(parent, _mesh("burst", color), ground + Vector3(0, 0.06, 0), "bolt_flare", 1.0 * sc, 0.3)
		if tier >= 1:
			_wave(parent, ground, color.lightened(0.3), 1.2 * sc, 0.3, 0.0, "zap")


## 각진 8각 별 불꽃(카메라를 본다): 0.2초 튀어나왔다 사라지고, 빛 불똥 몇 개가 튄다. crit은 크게(size 1), chain 맞은 지점은 작게.
static func spark(parent: Node, pos: Vector3, color: Color, size: float) -> void:
	var mi := _spawn(parent, _mesh("star", color), pos, "spark")
	if mi == null:
		return
	_face_camera(mi)
	mi.scale = Vector3.ONE * size * 0.4
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * size * 1.2, 0.08)
	tw.tween_property(mi, "scale", Vector3.ONE * size * 0.2, 0.12)
	tw.tween_callback(mi.queue_free)
	var sp := _burst(parent, pos, color, "spark", int(6 + 6 * size), 0.3, "spark_bits")
	if sp != null:
		sp.initial_velocity_min = 3.0 * size + 1.0
		sp.initial_velocity_max = 6.0 * size + 2.0
		sp.scale_amount_min = 0.6 * size + 0.3
		sp.scale_amount_max = 1.0 * size + 0.5


## execute·boss_slayer: 맞은 지점에 붉은 X 베기 자국(가산, 카메라를 본다) + 붉은 빛무리 0.3초. tier만큼 크고, tier 1+면 붉은 별 불꽃,
## tier 2면 바닥 붉은 방사 섬광.
static func slash(parent: Node, pos: Vector3, tier := 0) -> void:
	var sc: float = TIER_SCALE[tier]
	var mi := _spawn(parent, _mesh("slash"), pos, "slash", glow_material())
	if mi == null:
		return
	_face_camera(mi)
	mi.scale = Vector3.ONE * 0.5 * sc
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 1.1 * sc, 0.08)
	tw.tween_interval(0.17)
	tw.tween_property(mi, "scale", Vector3(1.1, 0.05, 1.1) * sc, 0.05)
	tw.tween_callback(mi.queue_free)
	halo(parent, pos, SLASH_RED, 1.6 * sc, 0.3, 1.2, "slash_glow")
	impact(parent, pos - Vector3(0, 0.75, 0), SLASH_RED, 0.6 * sc, 0, 0.75)
	if tier >= 1:
		spark(parent, pos, SLASH_RED.lightened(0.3), 0.8 * sc)
	if tier >= 2:
		_flare(parent, _mesh("burst", SLASH_RED), pos - Vector3(0, 0.75, 0), "burst", 1.6, 0.3)


## cleave: 대상 발밑에서 고유 색 초승달 궤적(가산, 끝이 옅다)이 휩쓸기 반경까지 돌며 퍼지고 옅어진다(0.28초). tier만큼 넓게 번지고, tier 2면 바닥 파동.
static func cleave(parent: Node, pos: Vector3, color: Color, radius: float, tier := 0) -> void:
	var sc: float = TIER_SCALE[tier]
	var mi := _spawn(parent, _mesh("crescent", color.lightened(0.15)), pos + Vector3(0, 0.25, 0), "cleave", glow_material())
	if mi != null:
		mi.rotation.y = randf() * TAU
		mi.scale = Vector3.ONE * 0.4
		var tw := mi.create_tween().set_parallel()
		tw.tween_property(mi, "scale", Vector3(radius * sc * 0.9, 1.0, radius * sc * 0.9), 0.2).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "rotation:y", mi.rotation.y + 2.2, 0.28).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(mi, "scale", Vector3(radius * sc, 0.05, radius * sc), 0.08)
		tw.chain().tween_callback(mi.queue_free)
		_fade(mi, 0.16, 0.18)
	impact(parent, pos, color, radius * 0.3, -1, 0.5)
	if tier >= 2:
		_wave(parent, pos, color, radius * 1.1, 0.3, 0.05)


## stun이 걸린 순간: 맞은 자리에 노란 별 불꽃 + 바닥 노란 파동(tier만큼 크게).
static func stun_hit(parent: Node, pos: Vector3, tier := 0) -> void:
	var sc: float = TIER_SCALE[tier]
	spark(parent, pos, STUN_YELLOW, 0.7 * sc)
	_wave(parent, pos - Vector3(0, 0.75, 0), STUN_YELLOW, 1.2 * sc, 0.3, 0.0, "zap")


## stun: 대상 머리 위 노란 각진 별 3개가 빙글 돈다(크게, 개정 17). 기절 동안 남는다 — 대상(monster.gd)이 끝날 때 지운다. 상한이면 null.
static func stun(target: Node3D, height: float) -> Node3D:
	var mi := _spawn(target, _mesh("stun"), target.global_position + Vector3(0, height, 0), "stun")
	if mi != null:
		mi.scale = Vector3.ONE * STUN_SCALE
		mi.create_tween().set_loops().tween_property(mi, "rotation:y", TAU, 0.6).from(0.0)
	return mi


## slow: 대상 발밑 하늘색 결정. 지속 동안 남는다(대상이 지운다).
static func slow(target: Node3D) -> Node3D:
	return _spawn(target, _mesh("slow"), target.global_position, "slow")


## poison: 대상 발밑 초록 거품이 오르내린다. 지속 동안 남는다(대상이 지운다).
static func poison(target: Node3D) -> Node3D:
	var mi := _spawn(target, _mesh("poison"), target.global_position, "poison")
	if mi != null:
		var tw := mi.create_tween().set_loops()
		tw.tween_property(mi, "position:y", 0.25, 0.4).from(0.0)
		tw.tween_property(mi, "position:y", 0.0, 0.4)
	return mi


## gate_repair: 성문 위 금색 망치가 휘둘러 반짝이고, 금빛 조각 4개가 위로 오른다. tier만큼 크고, tier 1+면 금빛 입자가 떠오른다.
static func repair(parent: Node, pos: Vector3, tier := 0) -> void:
	var sc: float = TIER_SCALE[tier]
	if tier >= 1:
		_motes(parent, pos, REPAIR_GOLD.lightened(0.3), 1.6 * sc, 2.0, 0.8)
	var mi := _spawn(parent, _mesh("hammer"), pos + Vector3(0, 2.6, 0), "hammer")
	if mi != null:
		_face_camera(mi)
		mi.scale = Vector3.ONE * 0.4
		var tw := mi.create_tween().set_parallel()
		tw.tween_property(mi, "scale", Vector3.ONE * 1.4 * sc, 0.15)
		tw.tween_property(mi, "rotation:z", mi.rotation.z - 1.2, 0.35).set_trans(Tween.TRANS_BACK)
		tw.chain().tween_callback(mi.queue_free)
	_pop(parent, _mesh("repair"), pos + Vector3(0, 1.6, 0), Vector3(0, 1.2, 0), "repair", 0.6)


## 스킬 발동(개정 17·25): 발밑 링 foot이 한 번 커졌다 돌아오고, 가산 색 고리가 번쩍 퍼지며 옅어지고, 몸이 고유 색 빛무리로 빛난다(hero를 따라간다).
## 등급 연출: 고리는 TIER_SCALE배 넓게, 발밑에서 고유 색 광선(rays, 가산)이 솟는다. tier 1+: 떠오르는 빛 조각. tier 2: 빛기둥 + 두 번째 파동.
static func pulse(hero: Node3D, foot: Node3D, color: Color, tier := 0) -> void:
	var sc: float = TIER_SCALE[tier]
	var tw := foot.create_tween()
	tw.tween_property(foot, "scale", Vector3.ONE * (1.5 + 0.25 * tier), 0.1)
	tw.tween_property(foot, "scale", Vector3.ONE, 0.25)
	var at := hero.global_position
	var mi := _spawn(hero, _mesh("glow_ring", color), at + Vector3(0, 0.06, 0), "pulse", glow_material())
	if mi != null:
		mi.scale = Vector3.ONE * 0.6
		var t2 := mi.create_tween()
		t2.tween_property(mi, "scale", Vector3.ONE * 2.2 * sc, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t2.tween_callback(mi.queue_free)
		_fade(mi, 0.2, 0.15)
	halo(hero, at + Vector3(0, 1.0, 0), color.lightened(0.2), 2.4 * sc, 0.4, 1.3, "pulse_glow")
	_surge(hero, _mesh("rays", color), at, "rays", 0.9 * sc, 1.3 * sc, 0.5, glow_material())
	if tier >= 1:
		_motes(hero, at, color.lightened(0.15), 0.9 * sc, 2.2, 0.8)
	if tier >= 2:
		_surge(hero, _mesh("pillar", color), at, "pillar", 1.0, 6.0, 0.55, soft_material())
		_wave(hero, at, color, 3.2, 0.45, 0.1)


## 카메라 흔들림(SHAKE_SEC초, 진폭 SHAKE_AMP m): node의 뷰포트 카메라 리그(camera_rig.shake)에 맡긴다. 리그가 없으면 아무 일도 없다.
static func shake_camera(node: Node) -> void:
	if node == null or not node.is_inside_tree():
		return
	var cam := node.get_viewport().get_camera_3d()
	if cam != null and cam.get_parent().has_method("shake"):
		cam.get_parent().shake(SHAKE_SEC, SHAKE_AMP)




## 타격 순간(개정 26 — 타격감): 하얀 심이 터지는 가시 섬광(카메라를 본다, 0.05초 커졌다 0.12초에 꺼진다) + 하얀 빛무리 +
## 바닥 집중선(바깥으로 튀며 옅어진다) + 빠른 하얀 불똥. 그리고 kick(흔들림·히트스톱, 화면 안이고 흔들림 설정이 켜졌을 때만).
## ground = 바닥 지점, 섬광은 그 h m 위. size ≈ 반경(m). power: 0 = 가벼운 타격(흔들림 작게, 히트스톱 없음), 1 = 큰 스킬, 2 = 아주 큰 스킬(가장 세게), 음수 = 그림만(흔들지 않는다).
static func impact(parent: Node, ground: Vector3, color: Color, size: float, power := 1, h := 0.7) -> void:
	var pos := ground + Vector3(0, h, 0)
	var hot := Color(1, 1, 1).lerp(color, 0.35)
	var mi := _spawn(parent, _mesh("impact", hot), pos, "impact", glow_material())
	if mi != null:
		_face_camera(mi)
		mi.rotate_object_local(Vector3.BACK, randf() * TAU)
		mi.scale = Vector3.ONE * size * 0.5
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3.ONE * size * 1.35, 0.05).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3(size * 1.6, size * 0.15, size * 1.6), 0.12).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)
		_fade(mi, 0.1, 0.06)
	halo(parent, pos, hot, size * 2.4, 0.2, 1.5, "impact_glow")
	var ln := _spawn(parent, _mesh("speed", color), ground + Vector3(0, 0.08, 0), "impact_lines", glow_material())
	if ln != null:
		ln.rotation.y = randf() * TAU
		ln.scale = Vector3(size * 0.6, 1.0, size * 0.6)
		var tl := ln.create_tween()
		tl.tween_property(ln, "scale", Vector3(size * 2.0, 1.0, size * 2.0), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tl.tween_callback(ln.queue_free)
		_fade(ln, 0.18, 0.07)
	var sp := _burst(parent, pos, hot, "spark", 8 + 4 * power, 0.28, "impact_sparks")
	if sp != null:
		sp.initial_velocity_min = 5.0 + size * 2.0
		sp.initial_velocity_max = 9.0 + size * 3.0
		sp.scale_amount_min = 1.0
		sp.scale_amount_max = 1.6
	if power >= 0:
		kick(parent, ground, KICK_AMP[mini(power, 2)], KICK_STOP[mini(power, 2)])


## 화면 흔들림 amp m + 히트스톱 stop초(camera_rig.kick — at이 화면 안이고 흔들림 설정이 켜졌을 때만). 리그가 없으면 아무 일도 없다.
static func kick(node: Node, at: Vector3, amp: float, stop := 0.0) -> void:
	if node == null or not node.is_inside_tree():
		return
	var cam := node.get_viewport().get_camera_3d()
	if cam != null and cam.get_parent().has_method("kick"):
		cam.get_parent().kick(at, amp, stop)

# --- 스킬 100종 확장 이펙트(hero_skills.gd가 부른다). 겹마다 노드 하나, 상한(MAX_LIVE) 안에서만 ---

## 둘레 폭발(서리 폭발·함성·도발): 바닥 방사 섬광 + 파동(tier 1+면 두 겹) + 빛무리 + 바닥을 따라 둥글게 퍼지는 빛줄기 + 떠오르는 빛 조각.
static func nova(parent: Node, pos: Vector3, color: Color, radius: float, tier := 0) -> void:
	_flare(parent, _mesh("burst", color), pos + Vector3(0, 0.08, 0), "burst", radius, 0.35)
	impact(parent, pos, color, radius * 0.35, 0, 0.5)
	_wave(parent, pos, color, radius, 0.35)
	if tier >= 1:
		_wave(parent, pos, color.lightened(0.3), radius * 1.25, 0.45, 0.1)
	halo(parent, pos + Vector3(0, 0.6, 0), color, radius * 1.6, 0.35, 1.3, "nova_glow")
	var sp := _burst(parent, pos + Vector3(0, 0.3, 0), color.lightened(0.3), "spark", 14 + 6 * tier, 0.4, "nova_sparks")
	if sp != null:  # 바닥을 따라 둥글게 퍼지는 빛줄기
		sp.direction = Vector3.RIGHT
		sp.spread = 180.0
		sp.flatness = 0.85
		sp.gravity = Vector3.ZERO
		sp.initial_velocity_min = radius * 2.2
		sp.initial_velocity_max = radius * 3.0
		sp.damping_min = radius * 3.0
		sp.damping_max = radius * 4.0
	_motes(parent, pos, color.lightened(0.2), radius * 0.7, 1.6 + 0.4 * tier, 0.6)


## 메테오·혜성: 하늘(왼쪽 위)에서 빛무리를 두르고 불티 꼬리(입자)를 끌며 도는 바위가 sec초에 떨어져 폭발(blast)한다.
static func meteor(parent: Node, pos: Vector3, color: Color, radius: float, tier: int, sec: float) -> void:
	var from := pos + Vector3(-3.0, 11.0, 2.5)
	var mi := _spawn(parent, _mesh("blast", color), from, "meteor")
	if mi == null:
		blast(parent, pos, color, radius, false, tier)
		return
	mi.scale = Vector3.ONE * 0.55 * TIER_SCALE[tier]
	var tail := _static(_mesh("tail", color.lightened(0.3)))
	tail.material_override = glow_material()
	tail.scale = Vector3(3.0, 3.0, 4.0)
	mi.add_child(tail)
	halo(mi, from, color.lightened(0.3), 2.4 * TIER_SCALE[tier], 0.0)  # 바위와 함께 지워진다
	var trail := _stream(mi, from, color.lightened(0.2), "ember", 40.0, 0.45, sec, "meteor_trail")  # 바위를 따라가며 월드에 흘린다
	if trail != null:
		trail.spread = 25.0
		trail.gravity = Vector3.ZERO
		trail.scale_amount_min = 1.5
		trail.scale_amount_max = 3.0
	mi.look_at(pos + Vector3(0, 0.5, 0), Vector3.UP)
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", pos + Vector3(0, 0.5, 0), sec).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(mi, "rotation:z", 6.0, sec)
	tw.tween_callback(func():
		blast(parent, pos, color, radius, false, tier, 2 if tier >= 2 else 1)
		mi.queue_free())


## 바닥 지대(화염 지대·독구름·눈보라·회오리·성역, 개정 25): 반투명 6각 바닥 + 테두리가 튀어나와 sec초 머물다 옅어지고, 테두리에서 파동이 한 번 퍼진다.
## 0.5초마다 _zone_puff, 그리고 지대마다 쉬지 않고 뿜는 입자 하나: 화염 지대 = 출렁이는 불꽃 혀(fire_material) + 불티,
## 눈보라 = 비스듬히 내리는 눈송이, 독구름 = 피어오르는 초록 연기 + 거품, 회오리 = 도는 깔때기 + 감겨 오르는 돌 조각, 성역 = 떠오르는 빛 조각.
static func zone(parent: Node, pos: Vector3, color: Color, radius: float, sec: float, style: String, tier := 0) -> void:
	var mi := _spawn(parent, _mesh("zone", color), pos + Vector3(0, 0.06, 0), "zone", soft_material())
	if mi == null:
		return
	mi.scale = Vector3(0.2, 1.0, 0.2)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	var n := int(sec / 0.5)
	for i in n:
		tw.tween_callback(_zone_puff.bind(parent, pos, color, radius, style, tier))
		tw.tween_interval(0.5)
	tw.tween_property(mi, "scale", Vector3(radius * 1.08, 1.0, radius * 1.08), 0.25)
	tw.tween_callback(mi.queue_free)
	_fade(mi, 0.25, 0.25 + n * 0.5)
	_wave(parent, pos, color.lightened(0.2), radius * 1.05, 0.3, 0.0, "zone_wave")
	match style:
		"tornado":
			var f := _spawn(parent, _mesh("funnel", color), pos, "funnel", soft_material())
			if f != null:
				f.scale = Vector3(radius * 0.2, 0.4, radius * 0.2)
				var tf := f.create_tween().set_parallel()
				tf.tween_property(f, "scale", Vector3(radius * 0.6, 3.2, radius * 0.6), 0.3).set_ease(Tween.EASE_OUT)
				tf.tween_property(f, "rotation:y", TAU * sec * 1.5, sec)
				tf.chain().tween_callback(f.queue_free)
				_fade(f, 0.3, sec - 0.3)
			var dust := _stream(parent, pos + Vector3(0, 0.3, 0), DUST, "chunk", 10.0, 0.9, sec, "zone_stream")
			if dust != null:
				dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
				dust.emission_ring_axis = Vector3.UP
				dust.emission_ring_radius = radius * 0.5
				dust.emission_ring_inner_radius = radius * 0.3
				dust.emission_ring_height = 0.2
				dust.gravity = Vector3(0, 2.0, 0)
				dust.orbit_velocity_min = 0.8
				dust.orbit_velocity_max = 1.2
				dust.initial_velocity_min = 1.0
				dust.initial_velocity_max = 2.0
		"inferno":
			var fl := _spawn(parent, _mesh("flames", color), pos, "flames", fire_material())
			if fl != null:
				fl.scale = Vector3(radius * 0.85, 0.05, radius * 0.85)
				var tf := fl.create_tween()
				tf.tween_property(fl, "scale", Vector3(radius * 0.85, 1.0 + 0.35 * tier, radius * 0.85), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
				tf.tween_interval(maxf(sec - 0.5, 0.0))
				tf.tween_property(fl, "scale", Vector3(radius * 0.9, 0.05, radius * 0.9), 0.25)
				tf.tween_callback(fl.queue_free)
			_zone_stream(parent, pos, color.lightened(0.25), radius, sec, "ember", 18.0)
		"blizzard":
			var sn := _zone_stream(parent, pos + Vector3(0, 3.0, 0), Color.WHITE, radius, sec, "flake", 30.0)
			if sn != null:
				sn.lifetime = 1.4
				sn.initial_velocity_min = 1.6
				sn.initial_velocity_max = 2.4
				sn.gravity = Vector3(1.2, -1.2, 0.6)
				sn.scale_amount_min = 1.3
				sn.scale_amount_max = 2.2
		"poison_cloud":
			var pc := _zone_stream(parent, pos + Vector3(0, 0.3, 0), color, radius, sec, "smoke", 6.0)
			if pc != null:
				pc.scale_amount_min = 1.2
				pc.scale_amount_max = 2.0
			_zone_stream(parent, pos, color.lightened(0.3), radius, sec, "mote", 10.0)
		"sanctuary":
			_zone_stream(parent, pos, color.lightened(0.3), radius, sec, "mote", 14.0)


## 지대 안에서 sec초 동안 뿜는 입자(반경 radius 원판에서): 초당 rate개.
static func _zone_stream(parent: Node, pos: Vector3, color: Color, radius: float, sec: float, kind: String, rate: float) -> CPUParticles3D:
	var p := _stream(parent, pos + Vector3(0, 0.1, 0), color, kind, rate, 1.0, sec, "zone_stream")
	if p != null:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(radius * 0.7, 0.1, radius * 0.7)
	return p


## 지대가 0.5초마다 피우는 것: 성역 = 빛 광선, 눈보라 = 서리 파동, 화염 지대 = 열기 빛무리, 그 밖 = 떠오르는 빛 조각.
static func _zone_puff(parent: Node, pos: Vector3, color: Color, radius: float, style: String, tier: int) -> void:
	match style:
		"sanctuary":
			_surge(parent, _mesh("rays", color), pos, "rays", radius * 0.8, 1.6, 0.5, glow_material())
		"blizzard":
			_wave(parent, pos, Color(0.85, 0.95, 1.0), radius * 0.9, 0.5, 0.0, "frost")
		"inferno":
			halo(parent, pos + Vector3(0, 0.5, 0), color, radius * 2.0, 0.5, 1.1, "heat")
		_:
			_motes(parent, pos, color.lightened(0.15), radius * 0.9, 1.4 + 0.3 * tier, 0.6)


## 지진·대지 강타: 갈라진 바닥 + 흙빛 파동 두 겹(옅어진다) + 튀어 오르는 돌 조각(입자) + 둘레에 피어오르는 흙먼지.
static func quake(parent: Node, pos: Vector3, radius: float, tier := 0) -> void:
	var mi := _spawn(parent, _mesh("cracks", DUST.darkened(0.45)), pos + Vector3(0, 0.05, 0), "cracks")
	if mi != null:
		mi.rotation.y = randf() * TAU
		mi.scale = Vector3(0.3, 1.0, 0.3)
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), 0.12)
		tw.tween_interval(0.5)
		tw.tween_property(mi, "scale", Vector3(radius, 0.01, radius), 0.2)
		tw.tween_callback(mi.queue_free)
	impact(parent, pos, DUST.lightened(0.5), radius * 0.5, 2 if tier >= 2 else 1, 0.3)
	_wave(parent, pos, DUST, radius, 0.35, 0.0, "quake")
	_wave(parent, pos, DUST.lightened(0.2), radius * (1.15 + 0.15 * tier), 0.45, 0.12, "quake")
	var ch := _burst(parent, pos + Vector3(0, 0.2, 0), DUST.darkened(0.25), "chunk", 10 + 4 * tier, 0.8, "quake_rocks")
	if ch != null:
		ch.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		ch.emission_sphere_radius = radius * 0.6
		ch.scale_amount_min = 1.0
		ch.scale_amount_max = 2.2
	var sm := _burst(parent, pos + Vector3(0, 0.2, 0), DUST.lightened(0.15), "smoke", 8 + 2 * tier, 0.9, "quake_dust")
	if sm != null:
		sm.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		sm.emission_ring_axis = Vector3.UP
		sm.emission_ring_radius = radius * 0.8
		sm.emission_ring_inner_radius = radius * 0.4
		sm.emission_ring_height = 0.1
		sm.scale_amount_min = 1.4
		sm.scale_amount_max = 2.4


## 회오리 베기: 영웅을 따라 도는 초승달 한 바퀴(가산, 0.3초 끝에 옅어진다) + 발 둘레 흙먼지.
static func whirl(hero: Node3D, radius: float, color: Color) -> void:
	var mi := _spawn(hero, _mesh("crescent", color.lightened(0.15)), hero.global_position + Vector3(0, 0.6, 0), "whirl", glow_material())
	if mi == null:
		return
	mi.scale = Vector3(radius, 1.0, radius)
	var tw := mi.create_tween()
	tw.tween_property(mi, "rotation:y", mi.rotation.y - TAU, 0.3)
	tw.tween_callback(mi.queue_free)
	_fade(mi, 0.12, 0.18)
	var sp := _burst(hero.get_parent(), hero.global_position + Vector3(0, 0.6, 0), color.lightened(0.4), "spark", 14, 0.35, "whirl_sparks")
	if sp != null:  # 칼끝에서 바깥으로 튀는 불똥(개정 26)
		sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		sp.emission_ring_axis = Vector3.UP
		sp.emission_ring_radius = radius * 0.9
		sp.emission_ring_inner_radius = radius * 0.7
		sp.emission_ring_height = 0.2
		sp.direction = Vector3.RIGHT
		sp.flatness = 0.8
		sp.gravity = Vector3(0, -4.0, 0)
		sp.radial_accel_min = 8.0
		sp.radial_accel_max = 14.0
		sp.initial_velocity_min = 1.0
		sp.initial_velocity_max = 3.0
	var d := _burst(hero.get_parent(), hero.global_position + Vector3(0, 0.15, 0), DUST.lightened(0.2), "smoke", 5, 0.5, "whirl_dust")
	if d != null:
		d.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		d.emission_ring_axis = Vector3.UP
		d.emission_ring_radius = radius * 0.8
		d.emission_ring_inner_radius = radius * 0.5
		d.emission_ring_height = 0.1


## 일직선 스킬: shockwave = 바닥을 미끄러지는 빛 화살촉 띠 + 흙먼지, spear_throw = 날아가는 창, ice_spikes = 줄지어 솟는 얼음 가시 + 서리 김·얼음 조각.
static func line(parent: Node, from: Vector3, to: Vector3, color: Color, style: String, tier := 0) -> void:
	var dir := Vector3(to.x - from.x, 0, to.z - from.z)
	var length := dir.length()
	if length < 0.1:
		return
	dir /= length
	var sc: float = TIER_SCALE[tier]
	match style:
		"spear_throw":
			var mi := _spawn(parent, _mesh("spear"), from + Vector3(0, 1.2, 0), "spear")
			if mi != null:
				mi.look_at(mi.global_position + dir, Vector3.UP)
				mi.scale = Vector3.ONE * sc
				var tw := mi.create_tween()
				tw.tween_property(mi, "global_position", to + Vector3(0, 0.9, 0), 0.25)
				tw.tween_callback(func():
					spark(parent, to + Vector3(0, 0.9, 0), color.lightened(0.4), 0.7 * sc)
					impact(parent, to, color, 0.5 * sc, 0, 0.9)
					mi.queue_free())
			streak(parent, from + Vector3(0, 1.0, 0), to + Vector3(0, 0.9, 0), color)
		"ice_spikes":
			var n := clampi(int(length / 0.9), 2, 8)
			for i in n:
				var at := from + dir * (length * (i + 1) / n)
				var mi := _spawn(parent, _mesh("spike", color), at, "spike")
				if mi == null:
					break
				mi.rotation.y = randf() * TAU
				mi.scale = Vector3(sc, 0.05, sc)
				var tw := mi.create_tween()
				tw.tween_interval(0.04 * i)
				tw.tween_property(mi, "scale", Vector3(sc, sc * randf_range(0.8, 1.3), sc), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw.tween_interval(0.5)
				tw.tween_property(mi, "scale", Vector3(sc, 0.02, sc), 0.15)
				tw.tween_callback(mi.queue_free)
			impact(parent, from + dir * 1.0, color, 0.6 * sc, 1 if tier >= 1 else 0, 0.4)
			var mist := _burst(parent, from.lerp(to, 0.5) + Vector3(0, 0.2, 0), Color(0.85, 0.95, 1.0), "smoke", 8, 0.8, "frost_mist")
			if mist != null:  # 가시 줄을 따라 피는 서리 김
				mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
				mist.emission_box_extents = Vector3(0.4, 0.1, 0.4) + Vector3(absf(dir.x), 0, absf(dir.z)) * length * 0.45
				mist.scale_amount_min = 1.0
				mist.scale_amount_max = 1.8
			var bits := _burst(parent, from.lerp(to, 0.5) + Vector3(0, 0.5, 0), color.lightened(0.4), "spark", 12, 0.4, "ice_bits")
			if bits != null:
				bits.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
				bits.emission_box_extents = Vector3(absf(dir.x), 0, absf(dir.z)) * length * 0.45
				bits.direction = Vector3.UP
				bits.spread = 50.0
		_:
			var mi := _spawn(parent, _mesh("dart", color), from + Vector3(0, 0.15, 0), "shock_line", glow_material())
			if mi != null:
				mi.look_at(mi.global_position + dir, Vector3.UP)
				mi.scale = Vector3(1.6 * sc, 1.0, 0.1)
				var tw := mi.create_tween()
				tw.tween_property(mi, "scale", Vector3(1.6 * sc, 1.0, length), 0.22).set_ease(Tween.EASE_OUT)
				tw.tween_property(mi, "scale", Vector3(0.05, 1.0, length), 0.15)
				tw.tween_callback(mi.queue_free)
				_fade(mi, 0.18, 0.2)
			var d := _burst(parent, from.lerp(to, 0.5) + Vector3(0, 0.1, 0), DUST.lightened(0.2), "smoke", 8, 0.6, "shock_dust")
			if d != null:
				d.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
				d.emission_box_extents = Vector3(0.3, 0.05, 0.3) + Vector3(absf(dir.x), 0, absf(dir.z)) * length * 0.45
			_wave(parent, to, color, 1.2 * sc, 0.3, 0.18)
			impact(parent, from + dir * 0.8, color, 0.6 * sc, 0, 0.4)


## 용의 숨결: 앞으로 퍼지는 불 부채꼴(반투명, 옅어진다) + 입에서 뿜어 나가는 불덩이(입자) + 끝에 남는 연기.
static func breath(parent: Node, from: Vector3, dir: Vector3, length: float, color: Color, tier := 0) -> void:
	var mi := _spawn(parent, _mesh("fan", color), from, "breath", soft_material())
	if mi != null:
		mi.look_at(from + dir, Vector3.UP)
		mi.scale = Vector3(0.2, 1.0, 0.2)
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3(length, 1.0 + 0.3 * tier, length), 0.2).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.25)
		tw.tween_property(mi, "scale", Vector3(length * 1.05, 0.05, length * 1.05), 0.15)
		tw.tween_callback(mi.queue_free)
		_fade(mi, 0.3, 0.3)
	var fire := _burst(parent, from, color.lightened(0.3), "ember", 28 + 8 * tier, length / 9.0 + 0.2, "breath_fire")
	if fire != null:  # 입에서 앞으로 뿜어 나가는 불덩이
		fire.direction = dir
		fire.spread = 30.0
		fire.gravity = Vector3(0, 1.5, 0)
		fire.initial_velocity_min = length * 1.4
		fire.initial_velocity_max = length * 2.0
		fire.damping_min = length * 0.6
		fire.damping_max = length * 1.0
		fire.explosiveness = 0.6
		fire.scale_amount_min = 2.5
		fire.scale_amount_max = 4.5
	var sm := _burst(parent, Vector3(from.x, 0.4, from.z) + dir * length * 0.6, Color(0.3, 0.28, 0.27), "smoke", 6, 0.9, "breath_smoke")
	if sm != null:
		sm.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		sm.emission_sphere_radius = length * 0.25
		sm.scale_amount_min = 1.2
		sm.scale_amount_max = 2.0


## 별똥별: 빛무리를 두르고 빛 꼬리(입자)를 끄는 별이 하늘에서 sec초에 떨어져 불꽃·빛무리·방사 섬광.
static func star_drop(parent: Node, pos: Vector3, color: Color, tier: int, sec: float) -> void:
	var from := pos + Vector3(2.5, 10.0, -1.5)
	var mi := _spawn(parent, _mesh("star", color.lightened(0.3)), from, "star_drop", glow_material())
	if mi == null:
		return
	_face_camera(mi)
	mi.scale = Vector3.ONE * 1.4 * TIER_SCALE[tier]
	halo(mi, from, color.lightened(0.2), 1.6, 0.0)
	var trail := _stream(mi, from, color.lightened(0.4), "mote", 50.0, 0.35, sec, "star_trail")
	if trail != null:
		trail.gravity = Vector3.ZERO
		trail.spread = 10.0
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", pos + Vector3(0, 0.6, 0), sec).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		spark(parent, pos + Vector3(0, 0.6, 0), color.lightened(0.4), 0.9 * TIER_SCALE[tier])
		impact(parent, pos, color, 0.9 * TIER_SCALE[tier], 1 if tier >= 1 else 0, 0.6)
		halo(parent, pos + Vector3(0, 0.6, 0), color.lightened(0.2), 2.4 * TIER_SCALE[tier], 0.35, 1.3, "star_glow")
		_flare(parent, _mesh("burst", color), pos + Vector3(0, 0.06, 0), "burst", 1.4 * TIER_SCALE[tier], 0.3)
		mi.queue_free())


## 화살비: 하늘에서 화살 다발(메시 하나)이 반경 radius로 꽂힌다(0.18초) + 바닥 흙먼지 파동·먼지 덩이.
static func arrows(parent: Node, pos: Vector3, radius: float, color: Color) -> void:
	var mi := _spawn(parent, _mesh("volley", color), pos + Vector3(0, 7.0, 0), "arrows")
	if mi == null:
		return
	mi.rotation.y = randf() * TAU
	mi.scale = Vector3(radius, 1.0, radius)
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", pos, 0.18).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		_wave(parent, pos, DUST, radius, 0.25, 0.0, "quake")
		impact(parent, pos, DUST.lightened(0.5), radius * 0.4, 0, 0.3)
		var d := _burst(parent, pos + Vector3(0, 0.1, 0), DUST.lightened(0.2), "smoke", 7, 0.6, "arrow_dust")
		if d != null:
			d.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			d.emission_box_extents = Vector3(radius * 0.7, 0.05, radius * 0.7)
		mi.queue_free())


## 심판의 빛: 하늘에서 내리꽂는 넓은 빛기둥 + 하얀 심 기둥(가산) + 빛무리 + 바닥 섬광 + 파동 + 떠오르는 빛 조각.
static func beam(parent: Node, pos: Vector3, color: Color, tier := 0) -> void:
	var sc: float = TIER_SCALE[tier]
	_surge(parent, _mesh("pillar", color), pos, "beam", 1.0 * sc, 9.0, 0.55, soft_material())
	_surge(parent, _mesh("pillar", Color(1.0, 1.0, 0.9)), pos, "beam_core", 0.4 * sc, 9.0, 0.45, glow_material())
	halo(parent, pos + Vector3(0, 0.6, 0), color.lightened(0.3), 3.0 * sc, 0.5, 1.3, "beam_glow")
	impact(parent, pos, color, 1.1 * sc, 2 if tier >= 2 else 1, 0.6)
	_flare(parent, _mesh("burst", color), pos + Vector3(0, 0.08, 0), "burst", 1.8 * sc, 0.4)
	_wave(parent, pos, color.lightened(0.3), 2.2 * sc, 0.4)
	_motes(parent, pos, color.lightened(0.3), 1.2 * sc, 2.6, 0.7)


## 그림자 습격: 보랏빛 어둠이 터지고(방사 섬광 + 검보라 연기) 표적에 베기 자국.
static func shadow(parent: Node, pos: Vector3) -> void:
	var dark := Color(0.35, 0.15, 0.5)
	_flare(parent, _mesh("burst", dark), Vector3(pos.x, 0.06, pos.z), "burst", 1.6, 0.35)
	slash_mark(parent, pos, dark.lightened(0.3))
	impact(parent, Vector3(pos.x, 0.0, pos.z), dark.lightened(0.5), 0.7, 0, pos.y)
	spark(parent, pos, dark.lightened(0.5), 1.0)
	var sm := _burst(parent, pos, Color(0.22, 0.12, 0.3), "smoke", 8, 0.6, "shadow_smoke")
	if sm != null:
		sm.initial_velocity_min = 1.0
		sm.initial_velocity_max = 2.2
		sm.spread = 180.0


## 공허 균열: 소용돌이치며 오그라드는 어두운 바닥 + 둘레에서 가운데로 빨려 드는 빛줄기 + 오그라드는 빛무리 + 보랏빛 입자.
static func rift(parent: Node, pos: Vector3, color: Color, radius: float, tier := 0) -> void:
	var mi := _spawn(parent, _mesh("zone", color.darkened(0.3)), pos + Vector3(0, 0.06, 0), "rift", soft_material())
	if mi != null:
		mi.scale = Vector3(radius * 1.2, 1.0, radius * 1.2)
		var tw := mi.create_tween().set_parallel()
		tw.tween_property(mi, "rotation:y", -TAU, 0.9)
		tw.tween_property(mi, "scale", Vector3(0.05, 1.0, 0.05), 0.9).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(mi.queue_free)
	var pull := _burst(parent, pos + Vector3(0, 0.4, 0), color.lightened(0.3), "spark", 18 + 6 * tier, 0.6, "rift_pull")
	if pull != null:  # 둘레에서 가운데로 빨려 드는 빛줄기
		pull.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		pull.emission_ring_axis = Vector3.UP
		pull.emission_ring_radius = radius * 1.1
		pull.emission_ring_inner_radius = radius * 0.8
		pull.emission_ring_height = 0.3
		pull.gravity = Vector3.ZERO
		pull.initial_velocity_min = 0.0
		pull.initial_velocity_max = 0.0
		pull.radial_accel_min = -radius * 6.0
		pull.radial_accel_max = -radius * 4.0
		pull.orbit_velocity_min = 0.3
		pull.orbit_velocity_max = 0.5
		pull.explosiveness = 0.5
	halo(parent, pos + Vector3(0, 0.3, 0), color, radius * 1.4, 0.9, 0.3, "rift_glow")
	impact(parent, pos, color.lightened(0.3), radius * 0.45, 1, 0.4)
	_motes(parent, pos, color.lightened(0.2), radius, 1.8 + 0.4 * tier, 0.8)


## 태양 섬광: 공중에서 커다란 빛덩이가 번쩍(+ 큰 빛무리·사방으로 튀는 빛줄기) + 바닥 방사 섬광 + 광선.
static func flare_burst(parent: Node, pos: Vector3, color: Color, radius: float, tier := 0) -> void:
	var mi := _spawn(parent, _mesh("flash", color), pos + Vector3(0, 1.4, 0), "sun", soft_material())
	if mi != null:
		mi.scale = Vector3.ONE * radius * 0.2
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3.ONE * radius * 0.5, 0.15)
		tw.tween_property(mi, "scale", Vector3.ONE * 0.05, 0.15)
		tw.tween_callback(mi.queue_free)
	halo(parent, pos + Vector3(0, 1.4, 0), color, radius * 2.0, 0.45, 1.2, "sun_glow")
	impact(parent, pos, color, radius * 0.6, 2 if tier >= 2 else 1, 1.4)
	var sp := _burst(parent, pos + Vector3(0, 1.4, 0), color.lightened(0.4), "spark", 16 + 6 * tier, 0.45, "sun_sparks")
	if sp != null:
		sp.initial_velocity_min = radius * 2.0
		sp.initial_velocity_max = radius * 3.0
		sp.gravity = Vector3(0, -2.0, 0)
	_flare(parent, _mesh("burst", color), pos + Vector3(0, 0.08, 0), "burst", radius * 1.1, 0.4)
	_surge(parent, _mesh("rays", color), pos, "rays", radius * 0.8, 1.4 * TIER_SCALE[tier], 0.5, glow_material())


## 심연의 손: 바닥에서 검보라 손톱들이 솟아 잠시 붙잡고 가라앉는다.
static func hands(parent: Node, pos: Vector3, radius: float, color: Color) -> void:
	var mi := _spawn(parent, _mesh("claws", color.darkened(0.2)), pos + Vector3(0, -1.0, 0), "hands")
	if mi == null:
		return
	mi.scale = Vector3(radius, 1.0, radius)
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", pos, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.7)
	tw.tween_property(mi, "global_position", pos + Vector3(0, -1.2, 0), 0.25)
	tw.tween_callback(mi.queue_free)


## 보호막: 대상을 감싸는 반투명 6각 돔(대상 자식, 지우는 건 부르는 쪽). 상한이면 null.
static func barrier(target: Node3D, color: Color) -> Node3D:
	var mi := _spawn(target, _mesh("dome", color), target.global_position, "barrier", soft_material())
	if mi != null:
		mi.scale = Vector3.ONE * 0.3
		mi.create_tween().tween_property(mi, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK)
	return mi


## 금강불괴: sec초 동안 금빛 돔.
static func golden(target: Node3D, sec: float) -> void:
	var mi := barrier(target, REPAIR_GOLD)
	if mi != null:
		var tw := mi.create_tween()
		tw.tween_interval(sec)
		tw.tween_callback(mi.queue_free)


## 방패 막기: 대상 앞 흰 별 불꽃.
static func block(target: Node3D) -> void:
	spark(target, target.global_position + Vector3(0, 1.0, 0), Color(0.9, 0.95, 1.0), 0.6)


## 강화(전투 찬가): 대상 위로 오르는 붉은 화살표 셋.
static func buff(target: Node3D, color: Color) -> void:
	_pop(target, _mesh("chevrons", color), target.global_position + Vector3(0, 1.2, 0), Vector3(0, 1.0, 0), "buff", 0.7)


## 영혼 수확: 처치 자리에서 빛 구슬이 영웅에게 날아든다(0.4초).
static func soul(parent: Node, from: Vector3, hero: Node3D) -> void:
	var mi := _spawn(parent, _mesh("bolt", Color(0.85, 0.8, 1.0)), from, "soul", glow_material())
	if mi == null:
		return
	var tw := mi.create_tween()
	tw.tween_method(func(t: float):
		if is_instance_valid(hero):
			mi.global_position = from.lerp(hero.global_position + Vector3(0, 1.0, 0), t) + Vector3(0, sin(t * PI) * 1.2, 0), 0.0, 1.0, 0.4)
	tw.tween_callback(mi.queue_free)


## 연속 공격·반격·그림자: 고유 색 사선 베기 자국 하나(카메라를 본다, 0.2초, 끝에 옅어진다).
static func slash_mark(parent: Node, pos: Vector3, color: Color) -> void:
	var mi := _spawn(parent, _mesh("slice", color), pos, "slice", glow_material())
	if mi == null:
		return
	_face_camera(mi)
	mi.scale = Vector3.ONE * 0.4
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 1.2, 0.08)
	tw.tween_property(mi, "scale", Vector3(1.2, 0.05, 1.2), 0.12)
	tw.tween_callback(mi.queue_free)
	_fade(mi, 0.1, 0.1)


## 파편 튀기기·들불: 맞은 자리 작은 방사 섬광 + 파동.
static func splash(parent: Node, pos: Vector3, color: Color, radius: float) -> void:
	_flare(parent, _mesh("burst", color), Vector3(pos.x, 0.08, pos.z), "burst", radius * 0.9, 0.25)
	_wave(parent, Vector3(pos.x, 0, pos.z), color, radius, 0.25)


## 관통·도탄·창 꼬리: a→b 곧은 빛 띠(고유 색 바깥 + 하얀 심, 0.2초에 옅어진다). 메시는 매번 만든다.
static func streak(parent: Node, a: Vector3, b: Vector3, color: Color) -> void:
	if full(parent):
		return
	var k = MeshKit.new()
	_ribbon(k, a, b, 0.12, Color(color.lightened(0.3), 0.6))
	_ribbon(k, a, b, 0.04, Color(1.0, 1.0, 1.0).lerp(color, 0.3))
	var mi := _spawn(parent, k.commit(), Vector3.ZERO, "streak", glow_material())
	if mi != null:
		var tw := mi.create_tween()
		tw.tween_interval(0.2)
		tw.tween_callback(mi.queue_free)
		_fade(mi, 0.15, 0.05)


## 부활(부활의 기도·불굴): 금빛 기둥 + 금빛 빛무리 + 떠오르는 입자 + 치유 고리.
static func revive(target: Node3D) -> void:
	var at := target.global_position
	_surge(target, _mesh("pillar", REPAIR_GOLD), at, "revive", 1.0, 6.0, 0.6, soft_material())
	halo(target, at + Vector3(0, 1.0, 0), REPAIR_GOLD, 2.6, 0.6, 1.3, "revive_glow")
	_motes(target, at, REPAIR_GOLD.lightened(0.3), 1.0, 2.2, 0.8)
	heal_ring(target.get_parent(), at, 1.6)


## 스킬 기 모으기(개정 25 발동 모션): 시전자 앞 가슴 높이에 고유 색 빛무리가 sec초에 걸쳐 커지고, 둘레에서 빛 조각이 빨려 들며,
## 발밑에 옅은 고리가 오그라든다. 모션의 발동 순간(sec 뒤)에 맞춰 끝난다 — 그 순간 스킬 이펙트와 이름 띠(pulse)가 이어받는다.
## 영웅을 따라간다(hero 자식). sec이 아주 짧으면(근접 평타형 모션) 빛무리만. tier만큼 크고 조각이 많다.
static func charge(hero: Node3D, color: Color, tier: int, sec: float) -> void:
	if sec <= 0.05:
		return
	var sc: float = TIER_SCALE[tier]
	var at := hero.global_position + Vector3(0, 1.3, 0)
	var g := halo(hero, at, color.lightened(0.25), 0.4, 0.0, 1.0, "charge")
	if g != null:
		var tw := g.create_tween()
		tw.tween_property(g, "scale", Vector3.ONE * 1.6 * sc, sec).set_ease(Tween.EASE_IN)
		tw.tween_callback(g.queue_free)
	if sec < 0.2:
		return
	var p := _burst(hero, at, color.lightened(0.1), "spark", 10 + 5 * tier, sec, "charge_in")
	if p != null:
		p.local_coords = true  # 영웅을 따라 모인다
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
		p.emission_sphere_radius = 1.1 * sc
		p.gravity = Vector3.ZERO
		p.initial_velocity_min = 0.0
		p.initial_velocity_max = 0.0
		p.radial_accel_min = -9.0 * sc / sec
		p.radial_accel_max = -6.0 * sc / sec
		p.explosiveness = 0.4
		p.lifetime = sec
	var ring := _spawn(hero, _mesh("glow_ring", color), hero.global_position + Vector3(0, 0.06, 0), "charge_ring", glow_material())
	if ring != null:
		ring.scale = Vector3.ONE * 2.4 * sc
		var tr := ring.create_tween()
		tr.tween_property(ring, "scale", Vector3.ONE * 0.6, sec).set_ease(Tween.EASE_IN)
		tr.tween_callback(ring.queue_free)


# --- 내부 ---

## 발밑에서 솟는 겹(광선·빛기둥 — 재질 mat, 없으면 가산 빛): 가로 w·세로 h까지 튀어 오른 뒤 가늘어지며 더 높이 흩어지고 옅어진다(sec초).
static func _surge(parent: Node, m: Mesh, pos: Vector3, tag: String, w: float, h: float, sec: float, mat: Material = null) -> void:
	var mi := _spawn(parent, m, pos + Vector3(0, 0.05, 0), tag, mat if mat != null else glow_material())
	if mi == null:
		return
	mi.scale = Vector3(w * 0.4, 0.05, w * 0.4)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(w, h, w), sec * 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(mi, "scale", Vector3(w * 0.05, h * 1.3, w * 0.05), sec * 0.65).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)
	_fade(mi, sec * 0.55, sec * 0.45)


## 떠오르는 빛 입자 한 무리(입자 노드 하나, 가산 빛): 반경 r 원판에서 한꺼번에 피어 rise m 오르며 작아지고 옅어진다(sec초).
## rise < 0이면 내려앉는다(눈). mat = 연기 재질 등(없으면 가산 빛).
static func _motes(parent: Node, pos: Vector3, color: Color, r: float, rise: float, sec: float, mat: Material = null) -> void:
	var p := _burst(parent, pos + Vector3(0, 0.2, 0), color, "mote", 18, sec, "motes", mat)
	if p == null:
		return
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(r * 0.75, 0.4, r * 0.75)
	p.direction = Vector3.UP if rise >= 0.0 else Vector3.DOWN
	p.spread = 12.0
	p.gravity = Vector3.ZERO
	var v := absf(rise) / sec
	p.initial_velocity_min = v * 0.7
	p.initial_velocity_max = v * 1.4
	p.damping_min = v * 0.5
	p.damping_max = v * 0.8
	p.explosiveness = 0.7
	p.angular_velocity_min = -180.0
	p.angular_velocity_max = 180.0


## 바닥 6각 파동(가산 빛 충격파): delay초 뒤 radius까지 sec초에 퍼지며 뒤쪽 절반에서 옅어진다.
static func _wave(parent: Node, pos: Vector3, color: Color, radius: float, sec: float, delay := 0.0, tag := "wave") -> void:
	var mi := _spawn(parent, _mesh("shock", color), pos + Vector3(0, 0.07, 0), tag, glow_material())
	if mi == null:
		return
	mi.scale = Vector3(0.2, 1.0, 0.2)
	var tw := mi.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), sec).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(mi.queue_free)
	_fade(mi, sec * 0.6, delay + sec * 0.4)


## 바닥에 납작하게 번지는 방사 섬광(가산 빛): radius까지 빠르게 커지며 돌다가 가운데로 사그라들며 옅어진다(sec초).
static func _flare(parent: Node, m: Mesh, pos: Vector3, tag: String, radius: float, sec: float) -> void:
	var mi := _spawn(parent, m, pos, tag, glow_material())
	if mi == null:
		return
	mi.rotation.y = randf() * TAU
	mi.scale = Vector3(0.3, 1.0, 0.3)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), sec * 0.4).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mi, "rotation:y", mi.rotation.y + 0.6, sec)
	tw.tween_property(mi, "scale", Vector3(radius * 0.2, 1.0, radius * 0.2), sec * 0.6).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)
	_fade(mi, sec * 0.6, sec * 0.4)


## 빛무리(개정 25): 카메라를 보는 부드러운 빛 원(fx_halo 셰이더, 사각형 하나) — 각진 이펙트 뒤에 깔려 "빛난다".
## size(지름 m)까지 커졌다가 grow배로 퍼지며 sec초에 사라진다. parent를 따라간다(영웅·투사체에 붙이면 함께 움직인다).
static func halo(parent: Node, pos: Vector3, color: Color, size: float, sec: float, grow := 1.4, tag := "halo") -> MeshInstance3D:
	if _halo == null:
		_halo = ShaderMaterial.new()
		_halo.shader = HaloShader
		_quad = QuadMesh.new()
	var mi := _spawn(parent, _quad, pos, tag, _halo)
	if mi == null:
		return null
	mi.set_instance_shader_parameter("tint", color)
	mi.scale = Vector3.ONE * size * 0.5
	if sec > 0.0:
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3.ONE * size, sec * 0.2).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3.ONE * size * grow, sec * 0.8)
		tw.parallel().tween_method(func(v: float): mi.set_instance_shader_parameter("fade", v), 1.0, 0.0, sec * 0.8)
		tw.tween_callback(mi.queue_free)
	return mi


## 공유 재질(가산·반투명) 노드를 delay초 뒤 sec초에 걸쳐 옅게(인스턴스 fade 1 → 0). 지우는 건 노드의 다른 트윈.
static func _fade(mi: GeometryInstance3D, sec: float, delay := 0.0) -> void:
	var tw := mi.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_method(func(v: float): mi.set_instance_shader_parameter("fade", v), 1.0, 0.0, maxf(sec, 0.01))


## 입자 한 번(CPUParticles3D 하나 = 그리기 한 번, Compatibility·모바일에서 안전 — arena_kit 불씨와 같은 방식). 상한이면 null.
## kind = 모양·움직임의 기본값: "spark"(속도 방향으로 늘어난 빛 조각, 중력), "mote"(작은 빛 조각), "ember"(떠오르는 불티),
## "smoke"(커지며 옅어지는 반투명 덩이), "chunk"(돌 조각, 로우폴리 재질, 중력), "flake"(눈송이). 부르는 쪽이 방향·속도를 덧붙인다.
## 불티·연기는 반투명(밝은 풀밭 위에서도 주황·초록이 제 색), 빛 조각·불똥·눈은 가산.
## 색은 color에서 끝으로 갈수록 투명(color_ramp). 한 번 다 뿜고 수명(life)이 끝나면 스스로 지운다. parent를 따라가지 않는다(local_coords 끔).
static func _burst(parent: Node, pos: Vector3, color: Color, kind: String, amount: int, life: float, tag := "", mat: Material = null, hold := 0.0) -> CPUParticles3D:
	if full(parent):
		return null
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.lifetime_randomness = 0.35
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.mesh = _mesh("p_" + kind)
	p.material_override = mat if mat != null else (material() if kind == "chunk" else (smoke_material() if kind in ["smoke", "ember"] else glow_material()))
	p.color = color
	var ramp := Gradient.new()
	if kind == "smoke":
		ramp.set_color(0, Color(1, 1, 1, 0.0))
		ramp.add_point(0.15, Color(1, 1, 1, 0.42))
		ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0.0))
	else:
		ramp.set_color(0, Color(1.25, 1.25, 1.25, 1.0))
		ramp.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = ramp
	var curve := Curve.new()
	if kind == "smoke":
		curve.add_point(Vector2(0, 0.4))
		curve.add_point(Vector2(1, 1.0))
	else:
		curve.add_point(Vector2(0, 1.0))
		curve.add_point(Vector2(0.6, 0.8))
		curve.add_point(Vector2(1, 0.0))
	p.scale_amount_curve = curve
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	p.spread = 180.0
	match kind:
		"spark":
			p.particle_flag_align_y = true
			p.gravity = Vector3(0, -9.0, 0)
			p.initial_velocity_min = 4.0
			p.initial_velocity_max = 8.0
			p.damping_min = 2.0
			p.damping_max = 4.0
		"ember":
			p.direction = Vector3.UP
			p.spread = 40.0
			p.gravity = Vector3(0, 1.5, 0)
			p.initial_velocity_min = 0.6
			p.initial_velocity_max = 2.0
		"smoke":
			p.direction = Vector3.UP
			p.spread = 60.0
			p.gravity = Vector3(0, 0.8, 0)
			p.initial_velocity_min = 0.4
			p.initial_velocity_max = 1.2
			p.damping_min = 0.5
			p.damping_max = 1.0
			p.angle_min = 0.0
			p.angle_max = 360.0
		"chunk":
			p.direction = Vector3.UP
			p.spread = 50.0
			p.gravity = Vector3(0, -14.0, 0)
			p.initial_velocity_min = 3.0
			p.initial_velocity_max = 6.5
			p.angular_velocity_min = -400.0
			p.angular_velocity_max = 400.0
			p.particle_flag_rotate_y = true
		"flake":
			p.direction = Vector3.DOWN
			p.spread = 20.0
			p.gravity = Vector3(0.6, -1.0, 0.3)
			p.initial_velocity_min = 1.0
			p.initial_velocity_max = 2.0
			p.angular_velocity_min = -120.0
			p.angular_velocity_max = 120.0
	p.set_meta("fx", tag if tag != "" else kind)
	parent.add_child(p)
	track(p)
	p.global_position = pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(hold + life * 1.4 + 0.1)
	tw.tween_callback(p.queue_free)
	return p


## 오래 뿜는 입자(지대의 불티·눈·거품): sec초 동안 뿜고, 다 사라지면 지운다. 반환은 _burst와 같다.
static func _stream(parent: Node, pos: Vector3, color: Color, kind: String, rate: float, life: float, sec: float, tag := "") -> CPUParticles3D:
	var p := _burst(parent, pos, color, kind, int(ceil(rate * life)), life, tag, null, sec)
	if p == null:
		return null
	p.one_shot = false
	p.explosiveness = 0.0
	var tw := p.create_tween()
	tw.tween_interval(sec)
	tw.tween_callback(func(): p.emitting = false)
	return p


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
		"flash":
			k.rock(Vector3.ZERO, 1.0, color, rng, 0.6)
		"shock":  # 납작한 6각 충격파 고리
			_hex_ring(k, 0.82, 1.0, 0.04, color)
		"shard":  # 각진 파편(3각뿔)
			k.cone(Vector3(0, -0.12, 0), 3, 0.14, 0.3, color)
		"axe":
			k.box(Vector3(0, 0, -0.35), Vector3(0.07, 0.07, 0.7), AXE_WOOD)
			k.box(Vector3(0, -0.12, 0.25), Vector3(0.05, 0.26, 0.24), AXE_METAL)
		"heal":
			_hex_ring(k, 0.85, 1.0, 0.08, HEAL_GREEN)
		"cross":  # 각진 십자 3개(크기·높이 다르게)
			for c in [[Vector3(-0.3, 0, 0), 0.22], [Vector3(0.28, 0.25, 0.1), 0.17], [Vector3(0.0, 0.5, -0.15), 0.13]]:
				var o: Vector3 = c[0]
				var s: float = c[1]
				k.box(o + Vector3(0, -s, 0), Vector3(s * 0.7, s * 2.0, s * 0.7), HEAL_GREEN.lightened(0.25))
				k.box(o + Vector3(0, -s * 0.35, 0), Vector3(s * 2.0, s * 0.7, s * 0.7), HEAL_GREEN.lightened(0.25))
		"slow":
			for i in 3:
				var a := TAU * i / 3.0
				k.cone(Vector3(cos(a), 0, sin(a)) * 0.45, 4, 0.12, 0.45, SLOW_BLUE)
		"poison":  # 발밑 거품
			k.rock(Vector3(0.3, 0.12, 0), 0.13, POISON_GREEN, rng, 1.0)
			k.rock(Vector3(-0.25, 0.2, 0.15), 0.09, POISON_GREEN, rng, 1.0)
			k.rock(Vector3(0.0, 0.15, -0.3), 0.1, POISON_GREEN.lightened(0.2), rng, 1.0)
		"repair":  # 금빛 조각 4개
			for i in 4:
				var a := TAU * i / 4.0 + PI / 4.0
				k.pyramid(Vector3(cos(a) * 0.8, 0.3 * (i % 2), sin(a) * 0.8), 0.25, 0.35, REPAIR_GOLD)
		"hammer":  # 금색 망치(손잡이 + 머리)
			k.box(Vector3(0, -0.45, 0), Vector3(0.08, 0.6, 0.08), REPAIR_GOLD.darkened(0.3))
			k.box(Vector3(0, 0.1, 0), Vector3(0.42, 0.2, 0.2), REPAIR_GOLD)
		"stun":  # 각진 별 3개(납작한 6각 별 = 삼각형 둘)를 머리 위 고리에
			for i in 3:
				var c := Vector3(cos(TAU * i / 3.0), 0, sin(TAU * i / 3.0)) * 0.4
				for flip in [0.0, PI]:
					var pts := []
					for j in 3:
						var a: float = flip + TAU * j / 3.0 + PI / 2.0
						pts.append(c + Vector3(cos(a), sin(a), 0) * 0.14)
					k.face(pts, Vector3.BACK, STUN_YELLOW)
		"star":  # 납작한 8각 별(XY 평면, 카메라를 보게 돌린다). 안쪽은 밝게
			for i in 16:
				var r0 := 0.5 if i % 2 == 0 else 0.2
				var r1 := 0.2 if i % 2 == 0 else 0.5
				var a0 := TAU * i / 16.0
				var a1 := TAU * (i + 1) / 16.0
				k.face([Vector3.ZERO, Vector3(cos(a0), sin(a0), 0) * r0, Vector3(cos(a1), sin(a1), 0) * r1], Vector3.BACK, color)
			for i in 8:
				k.face([Vector3.ZERO, Vector3(cos(TAU * i / 8.0), sin(TAU * i / 8.0), 0) * 0.16, Vector3(cos(TAU * (i + 1) / 8.0), sin(TAU * (i + 1) / 8.0), 0) * 0.16],
					Vector3.BACK, color.lightened(0.6))
		"impact":  # 타격 섬광(개정 26): 길고 짧은 가는 가시 10개 + 하얀 심(XY 평면, 카메라를 보게 돌린다, 반지름 1)
			for i in 10:
				var a := TAU * i / 10.0 + rng.randf_range(-0.12, 0.12)
				var tip := 1.0 if i % 2 == 0 else rng.randf_range(0.5, 0.7)
				var w := 0.09
				k.face([Vector3(cos(a - w), sin(a - w), 0) * 0.14, Vector3(cos(a), sin(a), 0) * tip, Vector3(cos(a + w), sin(a + w), 0) * 0.14],
					Vector3.BACK, color.lightened(0.3) if i % 2 == 0 else color)
			for i in 8:
				k.face([Vector3.ZERO, Vector3(cos(TAU * i / 8.0), sin(TAU * i / 8.0), 0) * 0.22, Vector3(cos(TAU * (i + 1) / 8.0), sin(TAU * (i + 1) / 8.0), 0) * 0.22],
					Vector3.BACK, Color(1, 1, 1).lerp(color, 0.15))
		"speed":  # 바닥 집중선(개정 26): 반지름 0.45~1 사이 가는 쐐기 16개, 길이 제각각(XZ 평면)
			for i in 16:
				var a := TAU * i / 16.0 + rng.randf_range(-0.1, 0.1)
				var r0 := rng.randf_range(0.4, 0.6)
				var w := 0.035
				k.face([Vector3(cos(a - w), 0, sin(a - w)) * r0, Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.85, 1.0), Vector3(cos(a + w), 0, sin(a + w)) * r0],
					Vector3.UP, Color(color.lightened(0.4), 0.9))
		"slash":  # X 베기 자국(XY 평면, 끝이 뾰족한 두 줄)
			for d in [Vector2(1, 1), Vector2(1, -1)]:
				var u := Vector3(d.x, d.y, 0).normalized() * 0.6
				var w := Vector3(-d.y, d.x, 0).normalized() * 0.08
				k.face([-u, w, u, -w], Vector3.BACK, SLASH_RED)
		"glow_ring":
			_hex_ring(k, 0.40, 0.62, 0.02, color)
		"aura":
			_hex_ring(k, 0.60, 0.70, 0.03, AURA_ORANGE)
		"rays":  # 발동 광선: 반지름 1 둘레의 가는 3각뿔 12개(높이 제각각, 1 안팎)
			for i in 12:
				var a := TAU * i / 12.0 + rng.randf() * 0.3
				var r := rng.randf_range(0.55, 1.0)
				k.cone(Vector3(cos(a) * r, 0, sin(a) * r), 3, 0.08, rng.randf_range(0.5, 1.0), Color(color if i % 2 == 0 else color.lightened(0.4), 0.85))
		"pillar":  # 빛기둥: 위로 좁아지고 옅어지는 6각 기둥 옆면 4마디(높이 1, 반지름 1 → 0.55, 알파 0.6 → 0.15)
			for seg in 4:
				var y0 := seg * 0.25
				var r0 := lerpf(1.0, 0.55, seg / 4.0)
				var r1 := lerpf(1.0, 0.55, (seg + 1) / 4.0)
				var c := Color(color.lightened(0.15 * seg), 0.6 - 0.15 * seg)
				for i in 6:
					var o0 := Vector3(cos(TAU * i / 6.0), 0, sin(TAU * i / 6.0))
					var o1 := Vector3(cos(TAU * (i + 1) / 6.0), 0, sin(TAU * (i + 1) / 6.0))
					k.face([o0 * r0 + Vector3(0, y0, 0), o1 * r0 + Vector3(0, y0, 0), o1 * r1 + Vector3(0, y0 + 0.25, 0), o0 * r1 + Vector3(0, y0 + 0.25, 0)], o0 + o1, c)
		"motes":  # 빛 입자 16개: 반지름 1 원판 안, 높이 0~0.8에 흩어진 작은 4각뿔
			for i in 16:
				var a := rng.randf() * TAU
				var r := sqrt(rng.randf())
				k.cone(Vector3(cos(a) * r, rng.randf() * 0.8, sin(a) * r), 4, 0.07, 0.18, color.lightened(rng.randf() * 0.3))
		"burst":  # 바닥 방사 섬광: 가운데 6각 + 길고 짧은 뾰족 날 12개(XZ 평면, 반지름 1)
			for i in 12:
				var a := TAU * i / 12.0
				var tip := 1.0 if i % 2 == 0 else 0.62
				var w := 0.16
				k.face([Vector3(cos(a - w), 0, sin(a - w)) * 0.22, Vector3(cos(a), 0, sin(a)) * tip, Vector3(cos(a + w), 0, sin(a + w)) * 0.22],
					Vector3.UP, color if i % 2 == 0 else color.darkened(0.2))
			for i in 6:
				k.face([Vector3.ZERO, Vector3(cos(TAU * i / 6.0), 0, sin(TAU * i / 6.0)) * 0.24, Vector3(cos(TAU * (i + 1) / 6.0), 0, sin(TAU * (i + 1) / 6.0)) * 0.24],
					Vector3.UP, color.lightened(0.5))
		"crescent":  # 휩쓸기 궤적: 200° 초승달(XZ 평면, 바깥 반지름 1, 양 끝이 가늘고 옅다)
			var seg := 10
			for i in seg:
				var t0 := float(i) / seg
				var t1 := float(i + 1) / seg
				var a0 := deg_to_rad(-100.0 + 200.0 * t0)
				var a1 := deg_to_rad(-100.0 + 200.0 * t1)
				var w0 := 0.45 * sin(PI * t0)
				var w1 := 0.45 * sin(PI * t1)
				var mid := sin(PI * (t0 + t1) / 2.0)
				k.face([Vector3(cos(a0), 0, sin(a0)) * (1.0 - w0), Vector3(cos(a0), 0, sin(a0)), Vector3(cos(a1), 0, sin(a1)), Vector3(cos(a1), 0, sin(a1)) * (1.0 - w1)],
					Vector3.UP, Color(color.lightened(0.25 * mid), 0.25 + 0.6 * mid))
		"zone":  # 바닥 지대: 반투명 6각 바닥(알파 0.28) + 진한 테두리(XZ, 반지름 1)
			for i in 6:
				var o0 := Vector3(cos(TAU * i / 6.0), 0, sin(TAU * i / 6.0))
				var o1 := Vector3(cos(TAU * (i + 1) / 6.0), 0, sin(TAU * (i + 1) / 6.0))
				k.face([Vector3.ZERO, o0 * 0.88, o1 * 0.88], Vector3.UP, Color(color, 0.28))
				k.face([o0 * 0.88, o0, o1, o1 * 0.88], Vector3.UP, Color(color.lightened(0.2), 0.8))
		"funnel":  # 회오리 깔때기: 아래가 좁은 6각 옆면 3마디(높이 1), 위로 옅어진다
			for seg in 3:
				var r0 := 0.15 + 0.3 * seg
				var r1 := r0 + 0.3
				var c := Color(color.lightened(0.1 * seg), 0.5 - 0.12 * seg)
				for i in 6:
					var a0 := TAU * i / 6.0 + seg * 0.4
					var a1 := TAU * (i + 1) / 6.0 + seg * 0.4
					k.face([Vector3(cos(a0) * r0, seg / 3.0, sin(a0) * r0), Vector3(cos(a1) * r0, seg / 3.0, sin(a1) * r0),
						Vector3(cos(a1) * r1, (seg + 1) / 3.0, sin(a1) * r1), Vector3(cos(a0) * r1, (seg + 1) / 3.0, sin(a0) * r1)],
						Vector3(cos(a0), 0, sin(a0)), c)
		"cracks":  # 갈라진 바닥: 가운데서 뻗는 꺾인 금 7줄(XZ, 반지름 1)
			for i in 7:
				var a := TAU * i / 7.0 + rng.randf() * 0.4
				var prev := Vector3.ZERO
				for j in 3:
					var r := (j + 1) / 3.0
					var p := Vector3(cos(a + rng.randf_range(-0.3, 0.3)) * r, 0, sin(a + rng.randf_range(-0.3, 0.3)) * r)
					var side := (p - prev).cross(Vector3.UP).normalized() * (0.06 * (1.0 - j * 0.25))
					k.face([prev - side, prev + side, p + side * 0.5, p - side * 0.5], Vector3.UP, color)
					prev = p
		"dart":  # 충격파 띠: 앞(-Z)으로 길이 1, 폭 1의 납작한 화살촉 마름모
			k.face([Vector3(0, 0, 0), Vector3(0.5, 0, -0.75), Vector3(0, 0, -1.0), Vector3(-0.5, 0, -0.75)], Vector3.UP, color)
			k.face([Vector3(0, 0, -0.1), Vector3(0.25, 0, -0.7), Vector3(0, 0, -0.95), Vector3(-0.25, 0, -0.7)], Vector3.UP, color.lightened(0.5))
		"spear":  # 창: 나무 자루 + 쇠 촉(앞 -Z)
			k.box(Vector3(0, -0.04, 0.5), Vector3(0.08, 0.08, 1.6), AXE_WOOD)
			k.cone(Vector3(0, 0, -0.3), 4, 0.12, 0.45, AXE_METAL)
		"spike":  # 얼음 가시: 굵은 4각뿔 하나 + 작은 둘
			k.cone(Vector3.ZERO, 4, 0.28, 1.1, color)
			k.cone(Vector3(0.25, 0, 0.1), 4, 0.14, 0.6, color.lightened(0.3))
			k.cone(Vector3(-0.2, 0, -0.15), 4, 0.12, 0.5, color.lightened(0.2))
		"fan":  # 용의 숨결 부채꼴: 앞(-Z) 70°, 반지름 1, 끝으로 갈수록 옅다(XZ 위 약간 높이)
			for i in 8:
				var a0 := deg_to_rad(-35.0 + 70.0 * i / 8.0)
				var a1 := deg_to_rad(-35.0 + 70.0 * (i + 1) / 8.0)
				var d0 := Vector3(sin(a0), 0, -cos(a0))
				var d1 := Vector3(sin(a1), 0, -cos(a1))
				k.face([Vector3.ZERO, d0 * 0.5, d1 * 0.5], Vector3.UP, Color(color.lightened(0.4), 0.85))
				k.face([d0 * 0.5, d0, d1, d1 * 0.5], Vector3.UP, Color(color, 0.45))
		"volley":  # 화살비: 반지름 1 원판 위 화살 14개(아래로 비스듬, 높이 0~1.6)
			for i in 14:
				var a := rng.randf() * TAU
				var r := sqrt(rng.randf())
				var base := Vector3(cos(a) * r, rng.randf() * 1.6, sin(a) * r)
				_ribbon(k, base + Vector3(0.15, 0.9, 0), base, 0.035, AXE_WOOD)
				k.cone(base - Vector3(0, 0.15, 0), 3, 0.05, 0.15, AXE_METAL)
		"dome":  # 보호막 돔: 6각 반구(2단, 높이 1.9 반지름 0.85), 위로 옅다
			for ring in 2:
				var y0 := ring * 0.95
				var y1 := y0 + 0.95
				var r0 := 0.85 if ring == 0 else 0.8
				var r1 := 0.8 if ring == 0 else 0.0
				for i in 6:
					var o0 := Vector3(cos(TAU * i / 6.0), 0, sin(TAU * i / 6.0))
					var o1 := Vector3(cos(TAU * (i + 1) / 6.0), 0, sin(TAU * (i + 1) / 6.0))
					var c := Color(color.lightened(0.2 * ring), 0.3 - 0.08 * ring)
					if r1 > 0.0:
						k.face([o0 * r0 + Vector3(0, y0, 0), o1 * r0 + Vector3(0, y0, 0), o1 * r1 + Vector3(0, y1, 0), o0 * r1 + Vector3(0, y1, 0)], o0 + o1, c)
					else:
						k.face([o0 * r0 + Vector3(0, y0, 0), o1 * r0 + Vector3(0, y0, 0), Vector3(0, y1, 0)], o0 + o1 + Vector3.UP, c)
		"claws":  # 심연의 손: 둘레 6개 휜 손톱(바깥으로 기운 4각뿔 두 마디)
			for i in 6:
				var a := TAU * i / 6.0 + rng.randf() * 0.3
				var o := Vector3(cos(a), 0, sin(a)) * 0.75
				k.cone(o, 4, 0.14, 0.9, color)
				k.cone(o * 1.15 + Vector3(0, 0.7, 0), 4, 0.08, 0.5, color.lightened(0.25))
			k.cone(Vector3.ZERO, 5, 0.22, 1.2, color.darkened(0.2))
		"chevrons":  # 위쪽 화살표 셋(XY 평면, 카메라 무관하게 세로로 선다)
			for i in 3:
				var y := i * 0.28
				k.face([Vector3(-0.3, y, 0), Vector3(0, y + 0.22, 0), Vector3(0, y + 0.34, 0), Vector3(-0.3, y + 0.12, 0)], Vector3.BACK, color)
				k.face([Vector3(0, y + 0.22, 0), Vector3(0.3, y, 0), Vector3(0.3, y + 0.12, 0), Vector3(0, y + 0.34, 0)], Vector3.BACK, color.lightened(0.2))
		"slice":  # 사선 베기 한 줄(XY 평면, 가운데 굵고 끝이 뾰족)
			var u := Vector3(1, 0.7, 0).normalized() * 0.7
			var w := Vector3(-0.7, 1, 0).normalized() * 0.07
			k.face([-u, w, u, -w], Vector3.BACK, color)
		"p_spark":  # 입자: 세로(Y)로 긴 마름모 — align_y로 날아가는 쪽을 향해 빛줄기처럼 보인다
			_diamond(k, 0.07, 0.4, Color.WHITE)
		"p_mote":  # 입자: 작은 빛 조각(마름모)
			_diamond(k, 0.1, 0.15, Color.WHITE)
		"p_ember":
			_diamond(k, 0.09, 0.13, Color.WHITE)
		"p_flake":  # 눈송이: 납작한 6각 별(가로 띠 셋)
			for i in 3:
				var d := Vector3(cos(PI * i / 3.0), sin(PI * i / 3.0), 0) * 0.16
				var w := Vector3(-d.y, d.x, 0).normalized() * 0.035
				k.face([-d - w, -d + w, d + w, d - w], Vector3.BACK, Color.WHITE)
		"p_smoke":  # 연기 덩이: 각진 바위(반지름 0.3)
			k.rock(Vector3.ZERO, 0.45, Color.WHITE, rng, 0.85)
		"p_chunk":  # 돌 조각
			k.rock(Vector3.ZERO, 0.2, Color.WHITE, rng, 0.8)
		"flames":  # 불꽃 혀 9개(반지름 1 원판 안, 높이 제각각): 아래 노란 4각 기둥 + 위 붉은 뿔(끝이 옅다)
			for i in 9:
				var a := TAU * i / 9.0 + rng.randf() * 0.5
				var r := 0.2 + 0.7 * sqrt(rng.randf())
				var o := Vector3(cos(a) * r, 0, sin(a) * r)
				var h := rng.randf_range(0.5, 1.0)
				var w := rng.randf_range(0.12, 0.2)
				k.prism_n(o, 4, w, w * 0.75, h * 0.4, Color(1.0, 0.78, 0.2, 0.95), a)
				k.cone(o + Vector3(0, h * 0.4, 0), 4, w * 0.75, h * 0.6, Color(color, 0.85), a)
		"tail":  # 투사체 뒤(+Z) 리본 3마디, 끝으로 갈수록 가늘고 어둡게
			for i in 3:
				_ribbon(k, Vector3(0, 0, 0.1 + i * 0.35), Vector3(0, 0, 0.45 + i * 0.35), 0.12 - i * 0.035, color.darkened(i * 0.2))
	return k.commit()


## 상한에 넣지 않는 늘 있는 메시 노드(공유 재질, 그림자 없음).
static func _static(m: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## 이펙트 노드 하나를 parent 아래 월드 위치 pos에 놓는다. 상한이면 null. tag = 메타 "fx"(테스트가 종류를 센다), mat = 재질(없으면 공유 정점 색).
static func _spawn(parent: Node, m: Mesh, pos: Vector3, tag := "", mat: Material = null) -> MeshInstance3D:
	if full(parent):
		return null
	var mi := _static(m)
	if mat != null:
		mi.material_override = mat
	mi.set_meta("fx", tag)
	parent.add_child(mi)
	track(mi)
	mi.global_position = pos
	return mi


## 작게 튀어나와 rise만큼 떠오르고(sec초) 사라지는 이펙트.
static func _pop(parent: Node, m: Mesh, pos: Vector3, rise: Vector3, tag := "", sec := 0.5) -> void:
	var mi := _spawn(parent, m, pos, tag)
	if mi == null:
		return
	mi.scale = Vector3.ONE * 0.3
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE, 0.15)
	tw.tween_property(mi, "global_position", pos + rise, sec)
	tw.chain().tween_callback(mi.queue_free)


## 파편 궤적: from → to 직선 + 높이 h 포물선(t = 0..1), 돌면서.
static func _arc(mi: Node3D, from: Vector3, to: Vector3, h: float, spin: Vector3, t: float) -> void:
	mi.global_position = from.lerp(to, t) + Vector3(0, 4.0 * h * t * (1.0 - t), 0)
	mi.rotation = spin * t


## 납작한(XY 평면) 이펙트가 카메라를 보게 한다(배율은 호출자가 뒤에 정한다).
static func _face_camera(mi: Node3D) -> void:
	var cam := mi.get_viewport().get_camera_3d()
	if cam != null:
		mi.global_basis = cam.global_basis.orthonormalized()


static func _hex_ring(k, r_in: float, r_out: float, h: float, color: Color) -> void:
	for i in 6:
		var o0 := Vector3(cos(TAU * i / 6.0), 0, sin(TAU * i / 6.0))
		var o1 := Vector3(cos(TAU * (i + 1) / 6.0), 0, sin(TAU * (i + 1) / 6.0))
		var top := Vector3(0, h, 0)
		k.face([o0 * r_in + top, o0 * r_out + top, o1 * r_out + top, o1 * r_in + top], Vector3.UP, color)
		k.face([o0 * r_out, o1 * r_out, o1 * r_out + top, o0 * r_out + top], o0 + o1, color.darkened(0.15))


## 마름모(팔면체): 가로 반지름 rx, 세로 반지름 ry.
static func _diamond(k, rx: float, ry: float, color: Color) -> void:
	var top := Vector3(0, ry, 0)
	var bot := Vector3(0, -ry, 0)
	for i in 4:
		var o0 := Vector3(cos(TAU * i / 4.0), 0, sin(TAU * i / 4.0)) * rx
		var o1 := Vector3(cos(TAU * (i + 1) / 4.0), 0, sin(TAU * (i + 1) / 4.0)) * rx
		k.face([o0, o1, top], o0 + o1 + Vector3.UP * rx, color)
		k.face([o0, o1, bot], o0 + o1 - Vector3.UP * rx, color)


## a→b 띠: 가로·세로로 교차한 두 장(어느 각도에서도 보인다).
static func _ribbon(k, a: Vector3, b: Vector3, w: float, color: Color) -> void:
	var d := (b - a).normalized()
	var flat := d.cross(Vector3.UP).normalized() * w
	if flat.length() < 0.001:
		flat = Vector3(w, 0, 0)
	var up := d.cross(flat).normalized() * w
	k.face([a - flat, a + flat, b + flat, b - flat], up, color)
	k.face([a - up, a + up, b + up, b - up], flat, color)

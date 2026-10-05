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
const SKY_H := 9.0  # 번개가 떨어지기 시작하는 높이(땅에서 m)
const BOLT_HIT_Y := 0.8  # 번개 맞은 지점(hero HIT_HEIGHT)에서 땅까지
const TIER := {"R": 0, "SR": 1, "SSR": 2}  # 등급 → 연출 단계
const TIER_SCALE := [1.0, 1.3, 1.65]  # 단계 → 스킬 이펙트 크기 배율

static var _meshes := {}
static var _live := 0  # 지금 살아 있는 이펙트·투사체 수
static var _material: ShaderMaterial
static var _glow: StandardMaterial3D
static var _soft: StandardMaterial3D


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


## 가산 색 재질(섬광·번개 바깥 빛·발동 고리). 하나를 공유한다.
static func glow_material() -> StandardMaterial3D:
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_glow.vertex_color_use_as_albedo = true
		_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # 정점 알파로 끝이 옅어진다(알파 1이면 그대로 가산)
		_glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _glow


## 반투명 색 재질(빛기둥·휩쓸기 궤적): 가산과 달리 밝은 바닥에서도 고유 색이 하얗게 날아가지 않는다. 정점 알파로 옅어진다. 하나를 공유한다.
static func soft_material() -> StandardMaterial3D:
	if _soft == null:
		_soft = StandardMaterial3D.new()
		_soft.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_soft.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_soft.vertex_color_use_as_albedo = true
		_soft.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _soft


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
## tail(multishot, 개정 17) = 뒤에 고유 색 짧은 리본 3마디.
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
	if tail and not full(proj):
		var t := _static(_mesh("tail", color))
		proj.add_child(t)
		track(t)
	return look


## aoe_blast: 고유 색 20면체가 반경까지 커지고, 바닥 충격파 고리·각진 파편 SHARDS_MIN~MAX개·0.15초 가산 섬광이 함께 퍼진다.
## shake = 카메라를 약하게 흔든다(SSR, 설정 fx_shake — 호출자가 정한다). 바닥엔 가산 빛 방사 섬광(burst)이 반경보다 조금 넓게 번진다.
## tier 1+: 두 번째 충격파(wave)가 반경 1.35배까지. tier 2: 가운데 빛기둥(pillar)과 떠오르는 불티(motes).
static func blast(parent: Node, pos: Vector3, color: Color, radius: float, shake := false, tier := 0) -> void:
	var mi := _spawn(parent, _mesh("blast", color), pos + Vector3(0, 0.5, 0), "blast")
	if mi != null:
		mi.scale = Vector3.ONE * 0.3
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3.ONE * radius, 0.3).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.15)
		tw.tween_callback(mi.queue_free)
	var ring := _spawn(parent, _mesh("shock", color.lightened(0.3)), pos + Vector3(0, 0.05, 0), "shock")
	if ring != null:
		ring.scale = Vector3(0.3, 1.0, 0.3)
		var tr := ring.create_tween()
		tr.tween_property(ring, "scale", Vector3(radius * 1.1, 1.0, radius * 1.1), 0.35).set_ease(Tween.EASE_OUT)
		tr.tween_callback(ring.queue_free)
	var flash := _spawn(parent, _mesh("flash", color.lightened(0.5)), pos + Vector3(0, 0.6, 0), "flash", glow_material())
	if flash != null:
		flash.scale = Vector3.ONE * radius * 0.5
		var tf := flash.create_tween()
		tf.tween_property(flash, "scale", Vector3.ONE * radius * 0.9, 0.15)
		tf.tween_callback(flash.queue_free)
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


## heal_aura: 초록 6각 고리가 반경까지 퍼지고, 반경 안에서 초록 빛 입자가 떠오른다. tier 1+: 뒤따르는 두 번째 고리(heal2).
## tier 2: 시전자 자리 초록 빛기둥.
static func heal_ring(parent: Node, pos: Vector3, radius: float, tier := 0) -> void:
	var mi := _spawn(parent, _mesh("heal"), pos + Vector3(0, 0.1, 0), "heal")
	if mi != null:
		mi.scale = Vector3.ONE * 0.2
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), 0.5).set_ease(Tween.EASE_OUT)
		tw.tween_callback(mi.queue_free)
	_motes(parent, pos, HEAL_GREEN.lightened(0.35), radius * 0.85, 1.8, 0.9)
	if tier >= 1:
		var m2 := _spawn(parent, _mesh("heal"), pos + Vector3(0, 0.12, 0), "heal2", glow_material())
		if m2 != null:
			m2.scale = Vector3.ONE * 0.05
			var t2 := m2.create_tween()
			t2.tween_interval(0.15)
			t2.tween_property(m2, "scale", Vector3(radius * 0.8, 1.0, radius * 0.8), 0.45).set_ease(Tween.EASE_OUT)
			t2.tween_callback(m2.queue_free)
	if tier >= 2:
		_surge(parent, _mesh("pillar", HEAL_GREEN), pos, "pillar", 1.1, 5.0, 0.6, soft_material())


## heal_aura로 회복받은 영웅: 머리 위로 각진 초록 십자 3개가 떠오른다(영웅을 따라간다).
static func heal_cross(target: Node3D) -> void:
	_pop(target, _mesh("cross"), target.global_position + Vector3(0, 1.4, 0), Vector3(0, 0.9, 0), "cross", 0.7)


## chain: 맞는 지점마다 하늘(SKY_H m 위)에서 각진 번개가 내리꽂힌다 — 7~9번 꺾이며 아래로 갈수록 덜 흔들리고, 중간에서 곁가지가
## 갈라진다(tier 1+면 둘). 굵은 가산 빛 + 가는 밝은 심을 한 메시씩(노드 둘)에 담아 번쩍·꺼짐·번쩍으로 깜빡이다 사라진다(0.32초).
## 땅에 닿는 곳마다 별 불꽃 + 바닥 방사 섬광(tier 1+면 파동도). tier: 굵기·불꽃이 TIER_SCALE배. points = 맞은 지점(HIT_HEIGHT 높이).
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
			_ribbon(glow, prev, p, 0.22 * sc, color.darkened(0.3))
			_ribbon(core, prev, p, 0.06 * sc, color.lightened(0.75))
			path.append(p)
			prev = p
		for k in 1 + mini(tier, 1):  # 곁가지: 위쪽 마디에서 비스듬히 아래로 3마디
			var bp: Vector3 = path[randi_range(2, 4)]
			var dir := Vector3(randf_range(-1, 1), -1.4, randf_range(-1, 1)).normalized()
			for _m in 3:
				var q := bp + dir * randf_range(0.5, 0.8) + Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2))
				_ribbon(glow, bp, q, 0.12 * sc, color.darkened(0.3))
				_ribbon(core, bp, q, 0.035 * sc, color.lightened(0.75))
				bp = q
	for mk in [[glow, glow_material()], [core, null]]:
		var mi := _spawn(parent, mk[0].commit(), Vector3.ZERO, "lightning", mk[1])
		if mi != null:
			var tw := mi.create_tween()
			tw.tween_interval(0.07)
			tw.tween_callback(func(): mi.visible = false)
			tw.tween_interval(0.04)
			tw.tween_callback(func(): mi.visible = true)
			tw.tween_interval(0.21)
			tw.tween_callback(mi.queue_free)
	for hit in points:
		var ground: Vector3 = hit - Vector3(0, BOLT_HIT_Y, 0)
		spark(parent, hit, color.lightened(0.4), 0.6 * sc)
		_flare(parent, _mesh("burst", color), ground + Vector3(0, 0.06, 0), "bolt_flare", 1.0 * sc, 0.3)
		if tier >= 1:
			_wave(parent, ground, color.lightened(0.3), 1.2 * sc, 0.3, 0.0, "zap")


## 각진 8각 별 불꽃(카메라를 본다): 0.2초 튀어나왔다 사라진다. crit은 크게(size 1), chain 맞은 지점은 작게.
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


## execute·boss_slayer: 맞은 지점에 붉은 X 베기 자국(각진 두 줄, 카메라를 본다) 0.3초. tier만큼 크고, tier 1+면 붉은 별 불꽃,
## tier 2면 바닥 붉은 방사 섬광.
static func slash(parent: Node, pos: Vector3, tier := 0) -> void:
	var sc: float = TIER_SCALE[tier]
	var mi := _spawn(parent, _mesh("slash"), pos, "slash")
	if mi == null:
		return
	_face_camera(mi)
	mi.scale = Vector3.ONE * 0.5 * sc
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 1.1 * sc, 0.08)
	tw.tween_interval(0.17)
	tw.tween_property(mi, "scale", Vector3(1.1, 0.05, 1.1) * sc, 0.05)
	tw.tween_callback(mi.queue_free)
	if tier >= 1:
		spark(parent, pos, SLASH_RED.lightened(0.3), 0.8 * sc)
	if tier >= 2:
		_flare(parent, _mesh("burst", SLASH_RED), pos - Vector3(0, 0.75, 0), "burst", 1.6, 0.3)


## cleave: 대상 발밑에서 고유 색 초승달 궤적(반투명, 끝이 옅다)이 휩쓸기 반경까지 돌며 퍼진다(0.28초). tier만큼 넓게 번지고, tier 2면 바닥 파동.
static func cleave(parent: Node, pos: Vector3, color: Color, radius: float, tier := 0) -> void:
	var sc: float = TIER_SCALE[tier]
	var mi := _spawn(parent, _mesh("crescent", color), pos + Vector3(0, 0.25, 0), "cleave", soft_material())
	if mi != null:
		mi.rotation.y = randf() * TAU
		mi.scale = Vector3.ONE * 0.4
		var tw := mi.create_tween().set_parallel()
		tw.tween_property(mi, "scale", Vector3(radius * sc * 0.9, 1.0, radius * sc * 0.9), 0.2).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "rotation:y", mi.rotation.y + 2.2, 0.28)
		tw.chain().tween_property(mi, "scale", Vector3(radius * sc, 0.05, radius * sc), 0.08)
		tw.chain().tween_callback(mi.queue_free)
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


## 스킬 발동(개정 17): 발밑 링 foot이 한 번 커졌다 돌아오고, 가산 색 고리가 번쩍 퍼진다(hero를 따라간다).
## 등급 연출: 고리는 TIER_SCALE배 넓게, 발밑에서 고유 색 광선(rays, 반투명)이 솟는다. tier 1+: 떠오르는 빛 입자. tier 2: 빛기둥 + 두 번째 파동.
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
		t2.tween_property(mi, "scale", Vector3.ONE * 2.2 * sc, 0.35).set_ease(Tween.EASE_OUT)
		t2.tween_callback(mi.queue_free)
	_surge(hero, _mesh("rays", color), at, "rays", 0.9 * sc, 1.3 * sc, 0.5, soft_material())
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


# --- 내부 ---

## 발밑에서 솟는 겹(광선·빛기둥 — 재질 mat, 없으면 가산 빛): 가로 w·세로 h까지 튀어 오른 뒤 가늘어지며 더 높이 흩어진다(sec초).
static func _surge(parent: Node, m: Mesh, pos: Vector3, tag: String, w: float, h: float, sec: float, mat: Material = null) -> void:
	var mi := _spawn(parent, m, pos + Vector3(0, 0.05, 0), tag, mat if mat != null else glow_material())
	if mi == null:
		return
	mi.scale = Vector3(w * 0.4, 0.05, w * 0.4)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(w, h, w), sec * 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(mi, "scale", Vector3(w * 0.05, h * 1.3, w * 0.05), sec * 0.65).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)


## 떠오르는 빛 입자 한 무리(메시 하나, 가산 빛): 반경 r에 흩어져 rise m 오르며 줄어든다(sec초, 천천히 돈다).
static func _motes(parent: Node, pos: Vector3, color: Color, r: float, rise: float, sec: float) -> void:
	var mi := _spawn(parent, _mesh("motes", color), pos + Vector3(0, 0.2, 0), "motes", glow_material())
	if mi == null:
		return
	mi.scale = Vector3(r, 1.0, r) * 0.6
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3(r, 1.0, r), sec * 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "global_position", pos + Vector3(0, 0.2 + rise, 0), sec).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "rotation:y", 1.5, sec)
	tw.chain().tween_property(mi, "scale", Vector3(r, 0.1, r) * 0.2, sec * 0.25)
	tw.chain().tween_callback(mi.queue_free)


## 바닥 6각 파동(가산 빛 충격파): delay초 뒤 radius까지 sec초에 퍼진다.
static func _wave(parent: Node, pos: Vector3, color: Color, radius: float, sec: float, delay := 0.0, tag := "wave") -> void:
	var mi := _spawn(parent, _mesh("shock", color), pos + Vector3(0, 0.07, 0), tag, glow_material())
	if mi == null:
		return
	mi.scale = Vector3(0.2, 1.0, 0.2)
	var tw := mi.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), sec).set_ease(Tween.EASE_OUT)
	tw.tween_callback(mi.queue_free)


## 바닥에 납작하게 번지는 방사 섬광(가산 빛): radius까지 빠르게 커지며 돌다가 가운데로 사그라든다(sec초).
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


## a→b 띠: 가로·세로로 교차한 두 장(어느 각도에서도 보인다).
static func _ribbon(k, a: Vector3, b: Vector3, w: float, color: Color) -> void:
	var d := (b - a).normalized()
	var flat := d.cross(Vector3.UP).normalized() * w
	if flat.length() < 0.001:
		flat = Vector3(w, 0, 0)
	var up := d.cross(flat).normalized() * w
	k.face([a - flat, a + flat, b + flat, b - flat], up, color)
	k.face([a - up, a + up, b + up, b - up], flat, color)

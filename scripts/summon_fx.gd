extends Node2D
## 소환 연출의 빛·입자·카메라(2026-11-03 사용자 "유성 소환 이상한데, 이거 유명한 게임들 참고해서 만든거 맞아?"):
## 앞 버전은 순서만 빌리고 납작한 도형으로 그려 싸 보였다. 이번엔 화면 모습을 따라간다.
## - 원신 기원: 밤하늘을 가르는 유성 — 빛나는 머리(겹 빛 번짐) + 길게 남는 꼬리 + 흩날리는 불티, 떨어진 자리에서 빛이 터진다.
## - 붕괴: 스타레일 워프: 별빛이 화면 밖으로 빨려 나가는 터널(앞으로 나아가는 느낌) + 카메라가 천천히 밀고 들어간다.
## - 명일방주 헤드헌팅·니케 모집: 착지 순간 충격파 고리 + 위로 솟는 빛기둥, 등급이 오를 때마다 다시 터지며 색이 바뀐다.
## 빛 번짐은 부드러운 원형 그라데이션 그림을 더하기 섞기(ADD)로 겹쳐 낸다(블룸 같은 효과, 후처리 없음 — 모바일 발열).
## 입자는 CPUParticles2D(몇백 개 이하). 카메라 = 이 노드의 위치·배율(밀고 들어가기·유성 따라가기·흔들림).
## 색은 summon_stage가 매 프레임 준다(R 파랑 · SR 보라 · SSR 무지개 · UR 불꽃 — 금색 없음).

const STARS := 90
const TRAIL := 26  # 유성 꼬리 점 수

var stage  # summon_stage.gd(색·시간)
var vs := Vector2(720, 1280)

var _glow_tex: Texture2D
var _ring_tex: Texture2D
var _beam_tex: Texture2D
var _dot_tex: Texture2D
var _add := CanvasItemMaterial.new()

var _tunnel: CPUParticles2D  # 별빛 터널
var _trail: Line2D  # 유성 꼬리(번짐)
var _trail_core: Line2D  # 유성 꼬리(속)
var _head_glow: Sprite2D
var _head_core: Sprite2D
var _sparks: CPUParticles2D  # 유성 불티
var _burst: CPUParticles2D  # 착지·등급 오름 폭발
var _motes: CPUParticles2D  # 빛 조각(오른다)
var _embers: CPUParticles2D  # UR 불씨
var _ring: Sprite2D  # 충격파
var _ring_t := 9.0
var _pillar: Sprite2D
var _pillar_glow: Sprite2D
var _core_glow: Sprite2D  # 착지 자리 큰 빛
var _core: Sprite2D
var _ground: Sprite2D  # 바닥 빛(납작한 타원)
var _history: Array = []  # 유성 머리 지나온 자리
var _landed := false
# 더 화려하게(2026-11-03 사용자 "방향성은 좋은데 좀 더 화려하게"):
# 원신 5성 기원의 갈라지는 빛살·가로 렌즈 플레어, 스타레일 워프의 함께 떨어지는 작은 유성들,
# 명일방주·니케의 2중 충격파와 흩어지는 파편, 빛기둥을 감고 오르는 나선 빛.
const RAYS := 14
var _rays_tex: Texture2D
var _rays_a: Sprite2D  # 빛살(시계 방향)
var _rays_b: Sprite2D  # 빛살(반대)
var _flare: Sprite2D  # 가로 렌즈 플레어
var _cross_h: Sprite2D  # 십자 반짝임
var _cross_v: Sprite2D
var _ring2: Sprite2D  # 늦게 따라오는 둘째 충격파
var _shards: CPUParticles2D  # 길게 날아가는 파편
var _spiral: CPUParticles2D  # 빛기둥을 감고 오르는 빛
var _mini: Array = []  # 함께 떨어지는 작은 유성 [{line, head, hist, from, delay}]
var _flare_t := 9.0


func _init() -> void:
	_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_tex = _radial([0.0, 0.18, 0.45, 1.0], [1.0, 0.55, 0.16, 0.0], 128)
	_ring_tex = _radial([0.0, 0.72, 0.86, 0.93, 1.0], [0.0, 0.0, 0.9, 0.35, 0.0], 256)
	_dot_tex = _radial([0.0, 0.35, 1.0], [1.0, 0.45, 0.0], 32)
	# 빛기둥: 가로는 가운데가 밝고, 세로는 위로 갈수록 흐려진다(아래 끝은 짧게 흐림 — 바닥 빛에 묻힌다)
	var img := Image.create(64, 256, false, Image.FORMAT_RGBA8)
	for y in 256:
		var v := float(y) / 255.0  # 0 위 … 1 아래
		var va := smoothstep(0.0, 0.7, v) * (1.0 - smoothstep(0.93, 1.0, v))
		for x in 64:
			var u := absf(float(x) / 63.0 - 0.5) * 2.0
			var ha := pow(1.0 - u, 2.2)
			img.set_pixel(x, y, Color(1, 1, 1, ha * va))
	_beam_tex = ImageTexture.create_from_image(img)

	# 빛살: 각도마다 가늘게 밝고 바깥으로 흐려진다
	var rimg := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in 256:
		for x in 256:
			var d := Vector2(x - 127.5, y - 127.5) / 127.5
			var r := d.length()
			var ang := d.angle()
			var w := pow(absf(cos(ang * RAYS * 0.5)), 18.0) + 0.6 * pow(absf(cos(ang * RAYS * 0.5 + 0.9)), 40.0)
			var a := clampf(w * pow(maxf(1.0 - r, 0.0), 1.3) * smoothstep(0.0, 0.12, r), 0.0, 1.0)
			rimg.set_pixel(x, y, Color(1, 1, 1, a))
	_rays_tex = ImageTexture.create_from_image(rimg)

	_tunnel = _particles(180, 1.1, _dot_tex)
	_tunnel.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_tunnel.emission_sphere_radius = 40.0
	_tunnel.direction = Vector2.RIGHT
	_tunnel.spread = 180.0
	_tunnel.initial_velocity_min = 260.0
	_tunnel.initial_velocity_max = 620.0
	_tunnel.linear_accel_min = 600.0  # 바깥으로 갈수록 빨라진다(워프)
	_tunnel.linear_accel_max = 1200.0
	_tunnel.scale_amount_min = 0.25
	_tunnel.scale_amount_max = 0.7
	_tunnel.scale_amount_curve = _curve([0.0, 0.2, 1.0], [0.2, 0.8, 1.6])
	_tunnel.particle_flag_align_y = true  # 속도 방향으로 길쭉하게(별줄기)
	_tunnel.color_ramp = _fade([0.0, 0.25, 0.85, 1.0], [0.0, 0.9, 0.7, 0.0])

	_ground = _sprite(_glow_tex)
	_rays_a = _sprite(_rays_tex)
	_rays_b = _sprite(_rays_tex)
	_pillar_glow = _sprite(_beam_tex)
	_pillar = _sprite(_beam_tex)
	_core_glow = _sprite(_glow_tex)
	_core = _sprite(_glow_tex)
	_ring = _sprite(_ring_tex)
	_ring2 = _sprite(_ring_tex)
	_flare = _sprite(_glow_tex)
	_cross_h = _sprite(_glow_tex)
	_cross_v = _sprite(_glow_tex)

	for i in 4:
		var ln := Line2D.new()
		ln.material = _add
		ln.width = 14.0
		ln.begin_cap_mode = Line2D.LINE_CAP_ROUND
		ln.width_curve = _curve([0.0, 1.0], [1.0, 0.0])
		add_child(ln)
		var hd := _sprite(_glow_tex)
		var side := -1.0 if i % 2 == 0 else 1.0
		_mini.append({"line": ln, "head": hd, "hist": [],
			"from": Vector2(0.5 + side * (0.35 + 0.18 * i), -(0.08 + 0.07 * i)),  # 화면 비율
			"delay": 0.15 + 0.12 * i})

	_trail = Line2D.new()
	_trail.material = _add
	_trail.width = 46.0
	_trail.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.width_curve = _curve([0.0, 1.0], [1.0, 0.0])
	add_child(_trail)
	_trail_core = Line2D.new()
	_trail_core.material = _add
	_trail_core.width = 12.0
	_trail_core.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail_core.width_curve = _curve([0.0, 1.0], [1.0, 0.0])
	add_child(_trail_core)

	_sparks = _particles(90, 0.7, _dot_tex)
	_sparks.local_coords = false
	_sparks.spread = 40.0
	_sparks.initial_velocity_min = 40.0
	_sparks.initial_velocity_max = 160.0
	_sparks.gravity = Vector2(0, 90)
	_sparks.damping_min = 30.0
	_sparks.damping_max = 60.0
	_sparks.scale_amount_min = 0.2
	_sparks.scale_amount_max = 0.55
	_sparks.color_ramp = _fade([0.0, 0.1, 1.0], [0.0, 1.0, 0.0])

	_head_glow = _sprite(_glow_tex)
	_head_core = _sprite(_glow_tex)

	_burst = _particles(160, 1.0, _dot_tex)
	_burst.one_shot = true
	_burst.explosiveness = 1.0
	_burst.emitting = false
	_burst.spread = 180.0
	_burst.initial_velocity_min = 220.0
	_burst.initial_velocity_max = 760.0
	_burst.damping_min = 380.0
	_burst.damping_max = 700.0
	_burst.gravity = Vector2(0, 160)
	_burst.scale_amount_min = 0.3
	_burst.scale_amount_max = 0.9
	_burst.particle_flag_align_y = true
	_burst.scale_amount_curve = _curve([0.0, 1.0], [1.0, 0.2])
	_burst.color_ramp = _fade([0.0, 0.05, 0.6, 1.0], [0.0, 1.0, 0.7, 0.0])

	_shards = _particles(70, 1.4, _dot_tex)
	_shards.one_shot = true
	_shards.explosiveness = 0.95
	_shards.emitting = false
	_shards.spread = 180.0
	_shards.initial_velocity_min = 500.0
	_shards.initial_velocity_max = 1300.0
	_shards.damping_min = 300.0
	_shards.damping_max = 600.0
	_shards.gravity = Vector2(0, 420)
	_shards.scale_amount_min = 0.5
	_shards.scale_amount_max = 1.3
	_shards.particle_flag_align_y = true
	_shards.angular_velocity_min = 0.0
	_shards.scale_amount_curve = _curve([0.0, 1.0], [1.6, 0.3])
	_shards.color_ramp = _fade([0.0, 0.04, 0.7, 1.0], [0.0, 1.0, 0.8, 0.0])

	_spiral = _particles(90, 1.8, _dot_tex)
	_spiral.local_coords = true
	_spiral.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
	_spiral.emission_sphere_radius = 70.0
	_spiral.direction = Vector2.UP
	_spiral.spread = 10.0
	_spiral.initial_velocity_min = 260.0
	_spiral.initial_velocity_max = 420.0
	_spiral.orbit_velocity_min = 0.35
	_spiral.orbit_velocity_max = 0.6
	_spiral.radial_accel_min = -40.0
	_spiral.radial_accel_max = -10.0
	_spiral.scale_amount_min = 0.3
	_spiral.scale_amount_max = 0.7
	_spiral.emitting = false
	_spiral.color_ramp = _fade([0.0, 0.15, 0.7, 1.0], [0.0, 1.0, 0.7, 0.0])

	_motes = _particles(90, 2.6, _dot_tex)
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_motes.emission_rect_extents = Vector2(260, 60)
	_motes.direction = Vector2.UP
	_motes.spread = 12.0
	_motes.initial_velocity_min = 40.0
	_motes.initial_velocity_max = 140.0
	_motes.scale_amount_min = 0.15
	_motes.scale_amount_max = 0.5
	_motes.color_ramp = _fade([0.0, 0.2, 0.7, 1.0], [0.0, 0.9, 0.6, 0.0])

	_embers = _particles(120, 2.0, _dot_tex)
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_embers.emission_rect_extents = Vector2(400, 20)
	_embers.direction = Vector2.UP
	_embers.spread = 25.0
	_embers.initial_velocity_min = 200.0
	_embers.initial_velocity_max = 520.0
	_embers.scale_amount_min = 0.2
	_embers.scale_amount_max = 0.6
	_embers.emitting = false
	_embers.color_ramp = _fade([0.0, 0.1, 0.7, 1.0], [0.0, 1.0, 0.8, 0.0])


## 소환 시작: 모두 처음으로.
func reset() -> void:
	_history.clear()
	_landed = false
	_ring_t = 9.0
	for p in [_sparks, _motes, _tunnel, _embers, _burst, _shards, _spiral]:
		p.restart()
		p.emitting = false
	_tunnel.emitting = true
	_trail.clear_points()
	_trail_core.clear_points()
	_flare_t = 9.0
	for m in _mini:
		m.hist = []
		m.line.clear_points()
	visible = true


func stop() -> void:
	visible = false
	for p in [_sparks, _motes, _tunnel, _embers, _burst, _shards, _spiral]:
		p.emitting = false


## 터진다(착지·등급이 오를 때): 입자 폭발 + 충격파. power 1 = 착지, 더 크면 더 크게.
func burst(power: float) -> void:
	_burst.restart()
	_burst.amount = int(clampf(160.0 * power, 100.0, 400.0))
	_burst.initial_velocity_max = 600.0 + 260.0 * power
	_burst.emitting = true
	_shards.restart()
	_shards.amount = int(clampf(40.0 * power, 30.0, 120.0))
	_shards.emitting = true
	_ring_t = 0.0
	_flare_t = 0.0
	_ring.set_meta("power", power)


## 한 프레임. t = 소환 시각, base = 기준 길이, length = 전체 길이, fall = 유성이 닿는 시각, out = 걷힘(0..1),
## rank = 지금 빛 등급(0 R .. 3 UR), col(i) = 지금 등급 빛(i = 0..1로 섞는 위치).
func tick(delta: float, t: float, base: float, length: float, fall: float, out: float, rank: int, col: Callable, shake: float) -> void:
	var c := Vector2(vs.x * 0.5, vs.y * 0.5)
	var land := Vector2(vs.x * 0.5, vs.y * 0.5)
	var fade := 1.0 - out
	var k := clampf(t / base, 0.0, 1.0)
	var c0: Color = col.call(0.0)
	var c1: Color = col.call(0.5)
	# 카메라: 천천히 밀고 들어가고(스타레일), 유성이 떨어지는 동안엔 유성 쪽으로 살짝, 터질 때 흔들림
	var zoom := 1.0 + 0.1 * ease(k, 0.6) + 0.25 * out
	var f := clampf(t / fall, 0.0, 1.0)
	var start := Vector2(vs.x * 1.05, -vs.y * 0.12)
	var head := start.lerp(land, ease(f, 2.0))  # 천천히 나타나 빨라지며 떨어진다
	var look := (head - c) * 0.12 * (1.0 - f) if t < fall else Vector2.ZERO
	var jolt := Vector2(sin(t * 71.0), cos(t * 53.0)) * 14.0 * shake
	scale = Vector2(zoom, zoom)
	position = c - c * zoom - look * zoom + jolt
	# 별빛 터널
	_tunnel.position = c
	_tunnel.color = Color(c0.lerp(Color.WHITE, 0.6), 0.9 * fade)
	_tunnel.speed_scale = 0.8 + 1.2 * k
	# 유성
	var flying := t < fall
	_head_glow.visible = flying
	_head_core.visible = flying
	_sparks.emitting = flying
	if flying:
		_history.push_front(head)
		if _history.size() > TRAIL:
			_history.pop_back()
		_trail.points = PackedVector2Array(_history)
		_trail_core.points = PackedVector2Array(_history)
		_trail.gradient = _line_grad(c0, 0.55)
		_trail_core.gradient = _line_grad(Color.WHITE.lerp(c1, 0.2), 1.0)
		_place(_head_glow, head, 2.6 + 0.6 * sin(t * 30.0), c0, 0.9)
		_place(_head_core, head, 0.9, Color.WHITE, 1.0)
		_sparks.position = head
		_sparks.direction = (start - land).normalized()
		_sparks.color = c1.lerp(Color.WHITE, 0.4)
	else:
		if not _landed:
			_landed = true
			burst(1.0)
			_motes.emitting = true
		for i in 4:  # 꼬리가 착지 자리로 빨려 들어가며 사라진다
			if not _history.is_empty():
				_history.pop_back()
			_trail.points = PackedVector2Array(_history)
			_trail_core.points = PackedVector2Array(_history)
	# 함께 떨어지는 작은 유성(워프 별똥별): 큰 유성보다 조금 늦게 출발해 같은 자리로 모인다
	for m in _mini:
		var mf: float = clampf((t - m.delay) / maxf(fall - m.delay * 0.5, 0.05), 0.0, 1.0)
		var on: bool = t >= m.delay and mf < 1.0
		m.head.visible = on
		if on:
			var mp: Vector2 = (m.from * vs).lerp(land, ease(mf, 2.0))
			m.hist.push_front(mp)
			if m.hist.size() > 16:
				m.hist.pop_back()
			_place(m.head, mp, 1.1, c1.lerp(Color.WHITE, 0.3), 0.9)
		elif not m.hist.is_empty():
			m.hist.pop_back()
			if not m.hist.is_empty():
				m.hist.pop_back()
		m.line.points = PackedVector2Array(m.hist)
		m.line.gradient = _line_grad(c1.lerp(Color.WHITE, 0.2), 0.8)
	# 착지 뒤: 바닥 빛 · 큰 빛 · 빛기둥
	var open := ease(clampf((t - fall) / maxf(length - fall, 0.01), 0.0, 1.0), 0.4) if not flying else 0.0
	var pulse := 1.0 + 0.06 * sin(t * 9.0)
	_ground.visible = not flying
	_core.visible = not flying
	_core_glow.visible = not flying
	_pillar.visible = not flying
	_pillar_glow.visible = not flying
	if not flying:
		_ground.position = land + Vector2(0, 30)
		_ground.scale = Vector2(9.0, 1.6) * (0.4 + 0.6 * open) * (1.0 + out)
		_ground.modulate = Color(col.call(0.25), 0.55 * fade)
		_place(_core_glow, land, (4.5 + 3.5 * open) * pulse * (1.0 + 2.0 * out), col.call(0.5), 0.85 * fade)
		_place(_core, land, (1.4 + 0.8 * open) * pulse * (1.0 + out), Color.WHITE.lerp(c1, 0.15), fade)
		var ph := vs.y * 1.3 * ease(clampf((t - fall) * 3.0, 0.0, 1.0), 0.4)  # 바닥에서 위로 솟는다
		var pw := (0.4 + 2.2 * open) * (1.0 + 3.0 * out)
		_pillar_glow.position = land + Vector2(0, 40.0 - ph * 0.5)
		_pillar_glow.scale = Vector2(pw * 3.0, ph / 256.0)
		_pillar_glow.modulate = Color(col.call(0.75), 0.5 * fade)
		_pillar.position = _pillar_glow.position
		_pillar.scale = Vector2(pw, _pillar_glow.scale.y)
		_pillar.modulate = Color(Color.WHITE.lerp(c1, 0.3), 0.9 * fade)
	# 빛살 · 렌즈 플레어 · 십자 반짝임 · 나선 빛
	for r in [_rays_a, _rays_b]:
		r.visible = not flying
	_spiral.emitting = not flying and out < 0.6
	_spiral.position = land + Vector2(0, 40)
	_spiral.color = c1.lerp(Color.WHITE, 0.3)
	if not flying:
		var rs := (3.0 + 5.0 * open) * (1.0 + 1.5 * out) * pulse
		_rays_a.position = land
		_rays_a.rotation = t * 0.35
		_rays_a.scale = Vector2(rs, rs)
		_rays_a.modulate = Color(col.call(0.4), 0.6 * fade)
		_rays_b.position = land
		_rays_b.rotation = -t * 0.22 + 0.11
		_rays_b.scale = Vector2(rs, rs) * 0.8
		_rays_b.modulate = Color(col.call(0.85).lerp(Color.WHITE, 0.3), 0.45 * fade)
	_flare_t += delta
	var fl := 1.0 / (1.0 + _flare_t * 6.0)  # 터진 순간 크게, 곧 은은하게 남는다
	var flw := 0.0 if flying else (0.25 + 0.75 * fl)
	_flare.visible = flw > 0.0
	_flare.position = land
	_flare.scale = Vector2(9.0 + 10.0 * fl, 0.22 + 0.25 * fl)
	_flare.modulate = Color(c0.lerp(Color.WHITE, 0.5), flw * fade)
	var tw := 0.75 + 0.25 * sin(t * 13.0)
	for cr in [_cross_h, _cross_v]:
		cr.visible = not flying
		cr.position = land
		cr.rotation = 0.25 * sin(t * 1.7)
	_cross_h.scale = Vector2(4.5 * tw * (1.0 + fl), 0.12)
	_cross_v.scale = Vector2(0.12, 4.5 * tw * (1.0 + fl))
	_cross_h.modulate = Color(1, 1, 1, 0.9 * fade)
	_cross_v.modulate = Color(1, 1, 1, 0.9 * fade)
	_motes.position = land + Vector2(0, 80)
	_motes.color = c1.lerp(Color.WHITE, 0.3)
	_burst.position = land
	_burst.color = c1.lerp(Color.WHITE, 0.35)
	# 무지개(SSR)·불꽃(UR)은 입자마다 다른 빛
	var ramp: Gradient = null
	if rank >= 2:
		ramp = Gradient.new()
		var cs := PackedColorArray()
		var os := PackedFloat32Array()
		for i in 6:
			os.append(i / 5.0)
			cs.append(col.call(i / 6.0))
		ramp.offsets = os
		ramp.colors = cs
	_shards.position = land
	_shards.color = c1.lerp(Color.WHITE, 0.25)
	for pp in [_burst, _motes, _sparks, _shards, _spiral]:
		pp.color_initial_ramp = ramp
		if ramp != null:
			pp.color = Color.WHITE
	# 충격파
	_ring_t += delta
	var rk := _ring_t / 0.55
	_ring.visible = rk < 1.0
	if rk < 1.0:
		var pw2: float = _ring.get_meta("power", 1.0)
		_place(_ring, land, (1.0 + 7.0 * ease(rk, 0.35)) * (0.8 + 0.3 * pw2), c1.lerp(Color.WHITE, 0.5), (1.0 - rk) * fade)
	var rk2 := (_ring_t - 0.12) / 0.8
	_ring2.visible = rk2 > 0.0 and rk2 < 1.0
	if _ring2.visible:
		var pw3: float = _ring.get_meta("power", 1.0)
		_place(_ring2, land, (0.6 + 10.0 * ease(rk2, 0.4)) * (0.8 + 0.3 * pw3), col.call(0.7), 0.7 * (1.0 - rk2) * fade)
	# UR 불씨
	_embers.emitting = rank >= 3 and out < 1.0
	_embers.position = Vector2(c.x, vs.y + 40.0)
	_embers.color = col.call(0.2)


func _place(s: Sprite2D, at: Vector2, size: float, color: Color, a: float) -> void:
	s.position = at
	s.scale = Vector2(size, size)
	s.modulate = Color(color, a)


func _sprite(tex: Texture2D) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.material = _add
	add_child(s)
	return s


func _particles(n: int, life: float, tex: Texture2D) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = n
	p.lifetime = life
	p.texture = tex
	p.material = _add
	p.local_coords = false
	p.gravity = Vector2.ZERO
	add_child(p)
	return p


static func _radial(offs: Array, alphas: Array, px: int) -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offs)
	var cs := PackedColorArray()
	for a in alphas:
		cs.append(Color(1, 1, 1, a))
	g.colors = cs
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = px
	t.height = px
	return t


static func _fade(offs: Array, alphas: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offs)
	var cs := PackedColorArray()
	for a in alphas:
		cs.append(Color(1, 1, 1, a))
	g.colors = cs
	return g


static func _curve(xs: Array, ys: Array) -> Curve:
	var cv := Curve.new()
	cv.max_value = 4.0
	for i in xs.size():
		cv.add_point(Vector2(xs[i], ys[i]))
	return cv


static func _line_grad(c: Color, a: float) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	g.colors = PackedColorArray([Color(c, a), Color(c, a * 0.6), Color(c, 0.0)])
	return g

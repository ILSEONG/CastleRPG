extends "res://scripts/monster.gd"
## 길드 보스 드래곤(guild_boss.gd 장면). monster.gd 아레나 모드 그대로(영웅 스킬 상태·지속 피해·피해 숫자) + 다른 점:
## - 모델은 dragon_model.gd(부품을 코드로 움직인다). 제자리에 서서(speed 0, 사거리가 무대 전체) 가장 가까운 영웅 쪽을 보고
##   앞발 할퀴기·불 뿜기·날개 바람을 차례로 한다. 공격력 = ATK_BASE × ATK_GROWTH^(단계 − 1)(atk_of), 맞은 영웅은 그만큼 체력이 깎인다
##   (영웅 방어 스킬·weaken 반영 — hit_damage). 쓰러진 영웅은 남은 시간 동안 못 친다.
## - 쓰러지지 않는다: HP가 0이 되면 그 단계를 처치한 것(level_cleared) — 다음 단계 최대 HP로 차오르고 남은 피해는 넘긴다(서버 bossOf와 같다).
## - 받은 피해 합(dealt)이 이번 도전 피해다. 넉백·겹침 밀림 없음.
## 몸 반지름 reach_r만큼 영웅 사거리가 늘어난다(hit_radius — 근접 영웅이 큰 몸 바깥에서 친다).

const DragonModelScript := preload("res://scripts/dragon_model.gd")
const GuildScript := preload("res://scripts/guild.gd")

const SIZE := 6.5  # 키(m) — 영웅(2.2 m)의 세 배쯤
const REACH_R := 2.8  # 몸 반지름(m): 영웅은 이만큼 더 멀리서 친다
const ATK_INTERVAL := 2.6
const FIRE := Color(1.0, 0.45, 0.12)
const ATK_BASE := 60.0  # 1단계 공격력(사용자 선택, 데스나이트 1단계와 같다)
const ATK_GROWTH := 1.12  # 보스 단계마다 공격력 ×(장비 던전 적 공격 성장과 같다)
const GUST_MULT := 0.5  # 날개 바람은 모두에게 공격력의 절반
const BREATH_DEG := 35.0  # 불 뿜기 부채꼴 반각

signal level_cleared(level: int)

var level := 1
var dealt := 0.0  # 이번 전투에서 받은 피해 합
var attacks := 0  # 테스트용
var closed := false  # 전투가 끝났다(날아오던 투사체 피해는 세지 않는다)
var _charge: MeshInstance3D  # 불 뿜기 전 입에 모이는 불빛(입을 따라간다, 타격 순간에 지운다)
var _charge_t := 0.0
var _charge_len := 1.0


## add_child 전에. p_level = 지금 보스 단계, p_hp = 남은 HP.
func setup_boss(p_level: int, p_hp: float) -> void:
	level = maxi(1, p_level)
	setup_arena({"kind": "dragon", "hp": maxf(1.0, p_hp), "atk": atk_of(level), "speed": 0.0, "range": 60.0, "atk_interval": ATK_INTERVAL,
		"aggro": 60.0, "scale": SIZE / 2.2})
	hp_max = GuildScript.boss_max(level)
	is_boss = true
	_atk_cd = 1.2  # 첫 공격은 잠깐 뒤


func _ready() -> void:
	add_to_group("monsters")
	_model = DragonModelScript.new()
	_model.size = SIZE
	add_child(_model)


## 보스 단계 → 공격력.
static func atk_of(p_level: int) -> float:
	return roundf(ATK_BASE * pow(ATK_GROWTH, maxi(p_level, 1) - 1))


func take_damage(amount: float, kind := 0) -> void:
	if _dead or closed or amount <= 0.0:
		return
	if _vuln_t > 0.0:
		amount *= 1.0 + _vuln_pct / 100.0
	dealt += amount
	hp -= amount
	DamageNumbers.pop(self, amount, kind)
	if kind != DamageNumbers.Kind.POISON:
		_model.hit_react(kind == DamageNumbers.Kind.SKILL or kind == DamageNumbers.Kind.CRIT)
	while hp <= 0.0:
		level_cleared.emit(level)
		level += 1
		atk = atk_of(level)
		hp_max = GuildScript.boss_max(level)
		hp += hp_max


func knockback(_from: Vector3, _dist: float) -> void:
	pass


func push_mass() -> float:
	return INF


func radius() -> float:
	return REACH_R


func hit_radius() -> float:
	return REACH_R


func bar_height() -> float:
	return SIZE * 1.05


func bar_scale() -> float:
	return 3.0


func _process(delta: float) -> void:
	super(delta)
	if is_instance_valid(_charge):
		if _swing_left < 0.0 or _dead:  # 기절 등으로 휘두르기가 끊겼다
			_end_charge()
		else:
			_charge_t += delta
			_charge.global_position = _model.mouth()
			_charge.scale = Vector3.ONE * lerpf(0.6, 3.2, clampf(_charge_t / _charge_len, 0.0, 1.0))


## 공격 시작: 모션 + 젖히는 동안의 예고 연출(2026-10-07 — 공격이 약해 보인다는 말에): 불 뿜기 = 입에 불빛이 모인다, 날개 바람 = 발밑 흙먼지가 인다.
func _swing(hero, what: int, at: Vector3) -> void:
	super(hero, what, at)
	var parent := get_parent()
	match str(_model.attack_kind):
		"breath":
			_end_charge()
			_charge = Fx.halo(parent, _model.mouth(), FIRE.lightened(0.25), 1.0, 0.0, 1.0, "dragon_charge")
			_charge_t = 0.0
			_charge_len = maxf(0.1, _swing_left)
		"gust":
			Fx.dust(parent, global_position)
			var d := Fx._burst(parent, global_position + Vector3(0, 0.3, 0), Fx.DUST.lightened(0.15), "smoke", 10, 1.0, "gust_lift")
			if d != null:
				d.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
				d.emission_ring_axis = Vector3.UP
				d.emission_ring_radius = REACH_R * 1.4
				d.emission_ring_inner_radius = REACH_R
				d.emission_ring_height = 0.1
				d.direction = Vector3.UP
				d.initial_velocity_min = 2.0
				d.initial_velocity_max = 4.0
				d.scale_amount_min = 1.5
				d.scale_amount_max = 2.6


func _end_charge() -> void:
	if is_instance_valid(_charge):
		_charge.queue_free()
	_charge = null


## 타격 순간: 할퀴기 = 노린 영웅 한 명, 불 뿜기 = 입 앞 부채꼴(BREATH_DEG) 안 모두에게 공격력만큼, 날개 바람 = 모두에게 GUST_MULT배.
func _release() -> void:
	attacks += 1
	var h = _swing_hero
	_swing_hero = null
	var at: Vector3 = h.global_position if is_instance_valid(h) else global_position + Vector3.FORWARD.rotated(Vector3.UP, rotation.y) * 4.0
	var parent := get_parent()
	match str(_model.attack_kind):
		"breath":
			var m: Vector3 = _model.mouth()
			_end_charge()
			Fx.flare_burst(parent, m - Vector3(0, 1.4, 0), FIRE, 1.6, 1)  # 입에서 터지는 불빛(타격감)
			var dir := (at + Vector3(0, 0.6, 0) - m)
			var length := dir.length() + 2.5
			Fx.breath(parent, m, dir.normalized(), length, FIRE, 2)
			for i in 2:  # 길게 뿜는다: 이어지는 불줄기 두 번 더(그림만 — 피해는 이번 한 번)
				get_tree().create_timer(0.14 * (i + 1), false).timeout.connect(func():
					if is_instance_valid(self) and not closed:
						var mm: Vector3 = _model.mouth()
						Fx.breath(parent, mm, dir.normalized(), length, FIRE.lightened(0.1 * i), 1))
			var flat := Vector2(dir.x, dir.z).normalized()
			for x in _alive_heroes():
				var d := Vector2(x.global_position.x - m.x, x.global_position.z - m.z)
				if d.length() <= length and (d.length() < 0.5 or rad_to_deg(flat.angle_to(d.normalized())) <= BREATH_DEG):
					_hurt(x, 1.0)
					Fx.blast(parent, Vector3(x.global_position.x, 0.0, x.global_position.z), FIRE, 1.4, false, 1, -1)
			Fx.kick(parent, at, 0.3, 0.05)
		"gust":
			var g := global_position
			var fz: Vector3 = _model.global_basis.z
			Fx.quake(parent, g + Vector3(fz.x, 0.0, fz.z).normalized() * 1.5, REACH_R * 1.3, 2)  # 쿵 내려앉음(가장 센 흔들림)
			var ring := Fx._burst(parent, g + Vector3(0, 0.4, 0), Fx.DUST.lightened(0.1), "smoke", 26, 0.9, "gust_ring")  # 흙먼지 고리가 바깥으로 휩쓸려 퍼진다
			if ring != null:
				ring.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
				ring.emission_ring_axis = Vector3.UP
				ring.emission_ring_radius = REACH_R
				ring.emission_ring_inner_radius = REACH_R * 0.8
				ring.emission_ring_height = 0.1
				ring.direction = Vector3.ZERO
				ring.spread = 180.0
				ring.radial_accel_min = 18.0
				ring.radial_accel_max = 26.0
				ring.scale_amount_min = 2.0
				ring.scale_amount_max = 3.2
			for x in _alive_heroes():
				var p: Vector3 = x.global_position
				Fx.streak(parent, g + Vector3(0, 1.2, 0) + (p - g).normalized() * REACH_R, p + Vector3(0, 0.9, 0), Color(0.95, 0.93, 0.85))
				Fx.impact(parent, Vector3(p.x, 0.0, p.z), Color(0.9, 0.85, 0.7), 1.0, -1)
				Fx.dust(parent, p)
				_hurt(x, GUST_MULT)
		_:
			_claw_fx(parent, at)
			if is_instance_valid(h) and h.is_alive():
				_hurt(h, 1.0)


## 할퀴기 타격: 대상 위에 대각선 발톱 자국 셋(카메라를 보는 큰 베기 자국, 불빛) + 붉은 베기 섬광 + 바닥 균열·돌 조각 + 큰 타격 섬광·흔들림.
func _claw_fx(parent: Node, at: Vector3) -> void:
	var ground := Vector3(at.x, 0.0, at.z)
	var cam := get_viewport().get_camera_3d()
	var right := cam.global_basis.x if cam != null else Vector3.RIGHT
	for i in 3:
		var mi := Fx._spawn(parent, Fx._mesh("slice", Color(1.0, 0.32, 0.08)), ground + Vector3(0, 1.8, 0) + right * (float(i) - 1.0) * 1.1,
			"claw_mark", Fx.soft_material())  # 반투명(밝은 풀밭 위에서도 붉은 주황이 제 색)
		if mi == null:
			break
		Fx._face_camera(mi)
		mi.scale = Vector3(1.0, 0.6, 1.0)
		var tw := mi.create_tween()
		tw.tween_interval(0.03 * i)
		tw.tween_property(mi, "scale", Vector3(4.2, 3.8, 4.2), 0.07).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.16)
		tw.tween_property(mi, "scale", Vector3(4.5, 0.05, 4.5), 0.12)
		tw.tween_callback(mi.queue_free)
		Fx._fade(mi, 0.14, 0.24)
	Fx.slash(parent, ground + Vector3(0, 1.2, 0), 2)
	Fx.quake(parent, ground, 2.0, 1)
	Fx.impact(parent, ground, FIRE, 1.6, 1)


func _alive_heroes() -> Array:
	return get_tree().get_nodes_in_group("heroes").filter(func(x): return x.is_alive())


func _hurt(hero, mult: float) -> void:
	hero.take_damage(hit_damage() * mult, self)

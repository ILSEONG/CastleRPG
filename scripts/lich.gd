extends "res://scripts/monster.gd"
## 리치(파티 퀘스트 보스, 2026-10-15 사용자 "리치의 모델링과 스킬의 퀄리티를 좋게 — 스킬은 5가지"). monster.gd 아레나 모드(평타 = 영혼 탄·지팡이 베기)에
## 스킬 다섯. 범위 스킬은 바닥 예고(Fx.telegraph_*)가 먼저 보이고, 다 차는 순간 그 안에 있는 영웅만 맞는다(옮기면 피한다).
## 1) 영혼 화살: BOLT_SEC마다 영웅 BOLT_N명에게 유도 영혼탄(공격 × BOLT_MULT, 피할 수 없음).
## 2) 죽음의 고리: RING_SEC마다 리치 둘레 반경 RING_R 예고(RING_TELE초) → 보라 폭발(공격 × RING_MULT, 밀쳐 냄).
## 3) 해골 소환: RAISE_SEC마다 리치 둘레에 해골 병사 RAISE_N마리(PartyRules.MINION.skeleton × 난이도 배수).
## 4) 저주의 장판: CURSE_SEC마다 영웅 CURSE_N명 발밑 예고 → 독 늪 CURSE_LAST초(안에 있으면 초당 공격 × CURSE_DPS, 받는 피해 +CURSE_VULN%).
## 5) 영혼 수확: 체력이 HARVEST_AT(50%·20%) 밑으로 처음 내려가면 무적 보호막 + 영혼 수정 CRYSTALS개(각 최대 체력 × CRYSTAL_HP).
##    HARVEST_SEC초 안에 수정을 모두 깨면 막이 깨지고 리치가 BREAK_STUN초 기절 + 받는 피해 +BREAK_VULN%. 못 깨면 남은 수정마다 영웅 모두에게
##    공격 × HARVEST_MULT 피해, 리치는 최대 체력 × HEAL_PER 회복.
## 판단·피해는 방장 기기만(party_battle.role == "host"). 연출은 event(…)로 남기면 꼭두각시 기기가 play_event로 똑같이 그린다.

const BOLT_SEC := 7.0
const BOLT_N := 3
const BOLT_MULT := 0.9
const RING_SEC := 13.0
const RING_R := 5.5
const RING_TELE := 1.6
const RING_MULT := 2.4
const RAISE_SEC := 19.0
const RAISE_N := 4
const CURSE_SEC := 10.0
const CURSE_N := 2
const CURSE_R := 2.6
const CURSE_TELE := 1.2
const CURSE_LAST := 5.0
const CURSE_DPS := 0.4
const CURSE_VULN := 20.0
const HARVEST_AT := [0.5, 0.2]
const HARVEST_SEC := 12.0
const CRYSTALS := 3
const CRYSTAL_HP := 0.05
const CRYSTAL_R := 7.0
const HARVEST_MULT := 1.6
const HEAL_PER := 0.08
const BREAK_STUN := 4.0
const BREAK_VULN := 30.0

const SOUL := Color(0.35, 1.0, 0.80)
const CURSE := Color(0.62, 0.32, 0.95)
const DEATH := Color(0.55, 0.15, 0.85)

var battle  # party_battle.gd
var bolt_cd := 4.0
var ring_cd := 10.0
var raise_cd := 14.0
var curse_cd := 7.0
var harvest_left := 0.0  # > 0: 영혼 수확 중(무적)
var casts := {}  # 스킬별 쓴 횟수(테스트)

var _harvest_i := 0
var _crystals: Array = []
var _shield: Node3D
var _tele := ""
var _tele_t := 0.0
var _curse_spots: Array = []
var _zones: Array = []  # [위치, 남은 초]
var _block_fx := 0.0


func _ready() -> void:
	super._ready()
	is_boss = true


func radius() -> float:
	return 0.55 * float(_stats.scale)


func hit_radius() -> float:
	return 0.6


## 수확 중에는 무적(막에 막힌다).
func take_damage(amount: float, kind := 0) -> void:
	if harvest_left > 0.0 and not puppet:
		if _block_fx <= 0.0:
			_block_fx = 0.4
			Fx.block(self)
		return
	super.take_damage(amount, kind)
	if not puppet and is_alive():
		_check_harvest()


func _process(delta: float) -> void:
	if not is_alive():
		_clear_shield()
		return
	_block_fx -= delta
	if puppet:
		super._process(delta)
		return
	_tick_zones(delta)
	if harvest_left > 0.0:
		_tick_harvest(delta)
		return
	if _tele != "":
		_tick_tele(delta)
		return
	super._process(delta)
	bolt_cd -= delta
	ring_cd -= delta
	raise_cd -= delta
	curse_cd -= delta
	if not is_alive() or is_stunned() or _swing_left >= 0.0 or _model.is_busy():
		return
	if ring_cd <= 0.0 and _near_heroes(RING_R + 1.5) > 0:
		ring()
	elif curse_cd <= 0.0:
		curse()
	elif bolt_cd <= 0.0:
		bolts()
	elif raise_cd <= 0.0:
		raise_dead()


func _heroes() -> Array:
	return battle.player_units() if battle != null else get_tree().get_nodes_in_group("heroes").filter(func(h): return h.is_alive())


func _near_heroes(r: float) -> int:
	return _heroes().filter(func(h): return Formation.flat_distance(global_position, h.global_position) <= r).size()


func _rng() -> RandomNumberGenerator:
	return battle.rng if battle != null else RandomNumberGenerator.new()


func _event(ev: Array) -> void:
	if battle != null:
		battle.event(uid, ev)


# --- 1) 영혼 화살 ---

func bolts() -> void:
	bolt_cd = BOLT_SEC
	var list := _heroes()
	list.shuffle()
	var uids := []
	for h in list.slice(0, BOLT_N):
		uids.append(int(h.uid))
	if uids.is_empty():
		return
	casts.bolt = int(casts.get("bolt", 0)) + 1
	_event(["bolt", uids])
	play_event(["bolt", uids])


func _fire_bolt(target) -> void:
	if not is_instance_valid(target) or not target.is_alive():
		return
	var p = preload("res://scripts/projectile.gd").new()
	p.target = target
	p.speed = 13.0
	p.kind = "bolt"
	p.color = SOUL
	p.big = true
	if not puppet:
		var dmg := hit_damage() * BOLT_MULT
		p.on_hit = func(t):
			if is_instance_valid(t) and t.is_alive():
				t.take_damage(dmg, self)
			Fx.spark(t.get_parent(), t.global_position + Vector3(0, 0.9, 0), SOUL, 0.9)
	else:
		p.on_hit = func(t): Fx.spark(t.get_parent(), t.global_position + Vector3(0, 0.9, 0), SOUL, 0.9)
	get_parent().add_child(p)
	p.global_position = global_position + Vector3(0, 2.6, 0)


# --- 2) 죽음의 고리 ---

func ring() -> void:
	ring_cd = RING_SEC
	casts.ring = int(casts.get("ring", 0)) + 1
	_start_tele("ring", RING_TELE)
	if battle != null:
		battle.danger(global_position, RING_R, RING_TELE)
	_event(["ring"])
	play_event(["ring"])


func _ring_hit() -> void:
	_event(["ring_hit"])
	play_event(["ring_hit"])
	for h in _heroes():
		if Formation.flat_distance(global_position, h.global_position) <= RING_R:
			h.take_damage(hit_damage() * RING_MULT, self)
			h.knockback(global_position, 2.5)


# --- 3) 해골 소환 ---

func raise_dead() -> void:
	raise_cd = RAISE_SEC
	casts.raise = int(casts.get("raise", 0)) + 1
	_model.play_cast("Spellcast_Raise", 0.9)
	_event(["raise"])
	if battle == null:
		return
	for i in RAISE_N:
		var a := TAU * i / RAISE_N + _rng().randf_range(-0.3, 0.3)
		var p := global_position + Vector3(cos(a), 0, sin(a)) * 3.2
		battle.spawn_minion("skeleton", battle.clamp_field(p))


# --- 4) 저주의 장판 ---

func curse() -> void:
	curse_cd = CURSE_SEC
	var list := _heroes()
	list.shuffle()
	_curse_spots.clear()
	var flat := []
	for h in list.slice(0, CURSE_N):
		var p: Vector3 = h.global_position
		_curse_spots.append(Vector3(p.x, 0, p.z))
		flat.append_array([snappedf(p.x, 0.01), snappedf(p.z, 0.01)])
		if battle != null:
			battle.danger(p, CURSE_R, CURSE_TELE + CURSE_LAST)
	if _curse_spots.is_empty():
		return
	casts.curse = int(casts.get("curse", 0)) + 1
	_start_tele("curse", CURSE_TELE)
	_event(["curse", flat])
	play_event(["curse", flat])


func _curse_land() -> void:
	for p in _curse_spots:
		_zones.append([p, CURSE_LAST, 0.0])


func _tick_zones(delta: float) -> void:
	for z in _zones.duplicate():
		z[1] -= delta
		z[2] -= delta
		if z[1] <= 0.0:
			_zones.erase(z)
			continue
		if z[2] > 0.0:
			continue
		z[2] = 0.5  # 0.5초마다 한 번
		for h in _heroes():
			if Formation.flat_distance(z[0], h.global_position) <= CURSE_R:
				h.take_damage(atk * CURSE_DPS * 0.5, DamageNumbers.Kind.POISON)
				h.apply_vulnerable(CURSE_VULN, 1.0)


# --- 5) 영혼 수확 ---

func _check_harvest() -> void:
	if _harvest_i >= HARVEST_AT.size() or harvest_left > 0.0:
		return
	if hp_ratio() <= float(HARVEST_AT[_harvest_i]):
		_harvest_i += 1
		harvest()


func harvest() -> void:
	casts.harvest = int(casts.get("harvest", 0)) + 1
	harvest_left = HARVEST_SEC
	_tele = ""
	_swing_left = -1.0
	_crystals.clear()
	if battle != null:
		var c: Vector3 = battle.field_center()
		for i in CRYSTALS:
			var a := TAU * i / CRYSTALS + PI / 2.0
			var m = battle.spawn_minion("soul_crystal", battle.clamp_field(c + Vector3(cos(a), 0, sin(a)) * CRYSTAL_R), hp_max * CRYSTAL_HP)
			if m != null:
				_crystals.append(m)
		battle.boss_line("harvest")
	_event(["harvest", 1])
	play_event(["harvest", 1])


func _tick_harvest(delta: float) -> void:
	harvest_left -= delta
	_model.play_loop("Spellcasting", 1.0)
	_crystals = _crystals.filter(func(m): return is_instance_valid(m) and m.is_alive())
	if _crystals.is_empty():
		harvest_left = 0.0
		_event(["harvest", 0])
		play_event(["harvest", 0])
		apply_stun(BREAK_STUN)
		apply_vulnerable(BREAK_VULN, BREAK_STUN + 2.0)
		if battle != null:
			battle.boss_line("harvest_broken")
		return
	if harvest_left > 0.0:
		return
	var n := _crystals.size()
	for m in _crystals:
		m.take_damage(m.hp, DamageNumbers.Kind.HIT)
	_crystals.clear()
	_event(["harvest", 2])
	play_event(["harvest", 2])
	for h in _heroes():
		h.take_damage(hit_damage() * HARVEST_MULT * n, self)
	hp = minf(hp_max, hp + hp_max * HEAL_PER * n)
	DamageNumbers.pop(self, hp_max * HEAL_PER * n, DamageNumbers.Kind.HEAL)
	_model.play_idle()


# --- 예고 ---

func _start_tele(kind: String, sec: float) -> void:
	_tele = kind
	_tele_t = sec
	_swing_left = -1.0
	_swing_hero = null


func _tick_tele(delta: float) -> void:
	_tele_t -= delta
	if _tele_t > 0.0:
		return
	var k := _tele
	_tele = ""
	if k == "ring":
		_ring_hit()
	elif k == "curse":
		_curse_land()


func is_telegraphing() -> bool:
	return _tele != "" or harvest_left > 0.0


# --- 연출(방장·꼭두각시 똑같이) ---

func play_event(ev: Array) -> void:
	if ev.is_empty() or not is_inside_tree():
		return
	var par := get_parent()
	match str(ev[0]):
		"bolt":
			_model.play_cast("Spellcast_Shoot", 0.5)
			Fx.halo(par, global_position + Vector3(0, 2.6, 0), SOUL, 2.2, 0.4)
			for id in ev[1]:
				var t = battle.unit_by_uid(int(id)) if battle != null else null
				if t != null:
					_fire_bolt(t)
		"ring":
			_model.play_cast("Spellcast_Long", RING_TELE, 0.85)
			Fx.telegraph_circle(par, global_position, RING_R, RING_TELE)
			Fx.charge(self, DEATH, 2, RING_TELE)
		"ring_hit":
			Fx.nova(par, global_position, DEATH, RING_R, 2)
			Fx.quake(par, global_position, RING_R * 0.6, 1)
			Fx.kick(par, global_position, 0.3, 0.05)
		"raise":
			_model.play_cast("Spellcast_Raise", 0.9)
			Fx.halo(par, global_position + Vector3(0, 1.4, 0), SOUL, 3.2, 0.6)
		"curse":
			_model.play_cast("Spellcast_Shoot", CURSE_TELE * 0.8)
			var flat: Array = ev[1]
			for i in range(0, flat.size() - 1, 2):
				var p := Vector3(float(flat[i]), 0, float(flat[i + 1]))
				Fx.telegraph_circle(par, p, CURSE_R, CURSE_TELE)
				var par_id := par.get_instance_id()
				get_tree().create_timer(CURSE_TELE, false).timeout.connect(func():
					var pn = instance_from_id(par_id)
					if is_instance_valid(pn):
						Fx.zone(pn, p, CURSE, CURSE_R, CURSE_LAST, "poison_cloud", 1))
		"harvest":
			match int(ev[1]):
				1:
					_clear_shield()
					_shield = Fx.barrier(self, SOUL)
					if _shield != null:
						_shield.scale = Vector3.ONE * 2.6
					Fx.flare_burst(par, global_position, SOUL, 4.0, 2)
				0:
					_clear_shield()
					Fx.blast(par, global_position, SOUL, 3.5, true, 2, 2)
					Fx.stun_hit(par, global_position + Vector3(0, bar_height(), 0), 2)
				2:
					_clear_shield()
					Fx.nova(par, global_position, DEATH, 18.0, 2)
					Fx.screen_flash(self, global_position, DEATH, 0.5)
					Fx.shake_camera(self)


func _clear_shield() -> void:
	if _shield != null and is_instance_valid(_shield):
		_shield.queue_free()
	_shield = null


## 크고 무겁다: 수확·예고 중에는 밀리지 않는다.
func push_mass() -> float:
	return INF if is_telegraphing() else super.push_mass()

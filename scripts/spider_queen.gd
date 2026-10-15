extends "res://scripts/monster.gd"
## 거미 여왕(파티 퀘스트 보스, 2026-10-15 사용자 "거미여왕의 스킬 퀄리티도 좋게 — 스킬은 4가지, 거미 부하가 엄청 많아").
## monster.gd 아레나 모드(평타 = 물기·앞다리 내려찍기, spider_model.gd)에 스킬 넷. 거미 부하는 party_battle이 둥지 가장자리에서 쉬지 않고 내보낸다.
## 1) 거미줄 발사: WEB_SEC마다 병사 WEB_N마리에게 거미줄 덩이(공격 × WEB_MULT) — 맞으면 WEB_ROOT초 묶이고 느려진다.
## 2) 독니 돌진: LUNGE_SEC마다 병사가 가장 많이 모인 곳에 반경 LUNGE_R 예고(LUNGE_TELE초) → 그리로 뛰어올라 내려찍는다(공격 × LUNGE_MULT + 독).
## 3) 알 낳기: BROOD_SEC마다 둘레에 알 주머니 BROOD_N개(party_minion — HATCH_SEC 안에 깨지 않으면 새끼 거미 4마리씩).
## 4) 산성 비: ACID_SEC마다 병사들 위로 산 덩이 ACID_N개 — 바닥 예고(ACID_TELE초) 뒤 떨어져 공격 × ACID_MULT, 받는 피해 +ACID_VULN%.
## 판단·피해는 방장 기기만. 연출은 event(…)로 남기면 꼭두각시 기기가 play_event로 똑같이 그린다.

const SpiderModel := preload("res://scripts/spider_model.gd")

const WEB_SEC := 9.0
const WEB_N := 2
const WEB_MULT := 0.6
const WEB_ROOT := 3.0
const LUNGE_SEC := 13.0
const LUNGE_R := 3.5
const LUNGE_TELE := 1.2
const LUNGE_MULT := 2.2
const LUNGE_POISON := 0.3  # 초당 공격 × 이것, 4초
const LUNGE_AIR := 0.4
const BROOD_SEC := 16.0
const BROOD_N := 3
const ACID_SEC := 20.0
const ACID_N := 6
const ACID_R := 2.2
const ACID_TELE := 1.6
const ACID_MULT := 1.3
const ACID_VULN := 20.0
const SIZE := 2.4  # 키(m)

const WEB := Color(0.92, 0.92, 0.88)
const VENOM := Color(0.55, 0.95, 0.25)

var battle  # party_battle.gd
var web_cd := 4.0
var lunge_cd := 8.0
var brood_cd := 11.0
var acid_cd := 15.0
var casts := {}

var _tele := ""
var _tele_t := 0.0
var _lunge_to := Vector3.ZERO
var _lunge_from := Vector3.ZERO
var _air := -1.0
var _acid_spots: Array = []


func _ready() -> void:
	add_to_group("monsters")
	add_to_group("crowd")
	_model = SpiderModel.new()
	_model.queen = true
	_model.size = SIZE
	add_child(_model)
	is_boss = true
	Sfx.play("boss_roar")


func radius() -> float:
	return 1.3


func hit_radius() -> float:
	return 1.1


func bar_height() -> float:
	return SIZE + 0.4


func bar_scale() -> float:
	return 1.8


func _process(delta: float) -> void:
	if not is_alive() or puppet:
		super._process(delta)
		return
	if _air >= 0.0:
		_tick_air(delta)
		return
	if _tele != "":
		_tick_tele(delta)
		return
	super._process(delta)
	web_cd -= delta
	lunge_cd -= delta
	brood_cd -= delta
	acid_cd -= delta
	if not is_alive() or is_stunned() or _swing_left >= 0.0 or _model.is_busy():
		return
	if lunge_cd <= 0.0 and _root_t <= 0.0:
		lunge()
	elif acid_cd <= 0.0:
		acid()
	elif web_cd <= 0.0:
		web()
	elif brood_cd <= 0.0:
		brood()


func _units() -> Array:
	return battle.player_units() if battle != null else get_tree().get_nodes_in_group("soldiers").filter(func(s): return s.is_alive())


func _event(ev: Array) -> void:
	if battle != null:
		battle.event(uid, ev)


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
	match k:
		"lunge":
			_air = 0.0
			_lunge_from = Vector3(global_position.x, 0, global_position.z)
		"acid":
			_acid_land()


func is_telegraphing() -> bool:
	return _tele != "" or _air >= 0.0


func push_mass() -> float:
	return INF if is_telegraphing() else super.push_mass()


# --- 1) 거미줄 발사 ---

func web() -> void:
	web_cd = WEB_SEC
	var list := _units()
	list.shuffle()
	var uids := []
	for u in list.slice(0, WEB_N):
		uids.append(int(u.uid))
	if uids.is_empty():
		return
	casts.web = int(casts.get("web", 0)) + 1
	_event(["web", uids])
	play_event(["web", uids])


func _shoot_web(target, delay: float) -> void:
	var tid: int = target.get_instance_id()  # 잡힌 값이 판 끝에 지워져도 오류가 안 나게 id로 잡는다
	get_tree().create_timer(delay, false).timeout.connect(func():
		var tgt = instance_from_id(tid)
		if not is_instance_valid(tgt) or not tgt.is_alive() or not is_alive():
			return
		var p = preload("res://scripts/projectile.gd").new()
		p.target = tgt
		p.speed = 16.0
		p.kind = "bolt"
		p.color = WEB
		var host := not puppet
		var dmg := hit_damage() * WEB_MULT
		p.on_hit = func(t):
			Fx.vines(t.get_parent(), t.global_position, 1.1, WEB, WEB_ROOT)
			if host and is_instance_valid(t) and t.is_alive():
				t.take_damage(dmg, self)
				t.apply_root(WEB_ROOT)
				t.apply_slow(40.0, WEB_ROOT + 1.0)
		get_parent().add_child(p)
		p.global_position = _model.mouth())


# --- 2) 독니 돌진 ---

func lunge() -> void:
	lunge_cd = LUNGE_SEC
	var best = null
	var best_n := -1
	for u in _units():
		var n := 0
		for o in _units():
			if Formation.flat_distance(u.global_position, o.global_position) <= LUNGE_R:
				n += 1
		if n > best_n:
			best_n = n
			best = u
	if best == null:
		return
	casts.lunge = int(casts.get("lunge", 0)) + 1
	var p: Vector3 = best.global_position
	_lunge_to = battle.clamp_field(Vector3(p.x, 0, p.z)) if battle != null else Vector3(p.x, 0, p.z)
	_start_tele("lunge", LUNGE_TELE)
	if battle != null:
		battle.danger(_lunge_to, LUNGE_R, LUNGE_TELE + LUNGE_AIR)
	var ev := ["lunge", snappedf(_lunge_to.x, 0.01), snappedf(_lunge_to.z, 0.01)]
	_event(ev)
	play_event(ev)


func _tick_air(delta: float) -> void:
	_air += delta
	var t := clampf(_air / LUNGE_AIR, 0.0, 1.0)
	var flat := _lunge_from.lerp(_lunge_to, t)
	global_position = Vector3(flat.x, sin(t * PI) * 2.6, flat.z)
	if t < 1.0:
		return
	_air = -1.0
	global_position = _lunge_to
	_event(["land"])
	play_event(["land"])
	for u in _units():
		if Formation.flat_distance(_lunge_to, u.global_position) <= LUNGE_R:
			u.take_damage(hit_damage() * LUNGE_MULT, self)
			u.apply_poison(atk * LUNGE_POISON, 4.0)
			u.knockback(_lunge_to, 1.5)
	_atk_cd = float(_stats.atk_interval)


# --- 3) 알 낳기 ---

func brood() -> void:
	brood_cd = BROOD_SEC
	casts.brood = int(casts.get("brood", 0)) + 1
	_event(["brood"])
	play_event(["brood"])
	if battle == null:
		return
	var back: Vector3 = -battle.toward_seats()
	for i in BROOD_N:
		var a := (i - (BROOD_N - 1) / 2.0) * 0.9
		var dir: Vector3 = back.rotated(Vector3.UP, a + PI)  # 여왕 앞쪽(병사 쪽)으로 부채꼴
		var p: Vector3 = global_position + dir * battle.rng.randf_range(3.0, 5.0)
		battle.spawn_minion("spider_egg", battle.clamp_field(p))


# --- 4) 산성 비 ---

func acid() -> void:
	acid_cd = ACID_SEC
	var list := _units()
	if list.is_empty():
		return
	casts.acid = int(casts.get("acid", 0)) + 1
	_acid_spots.clear()
	var flat := []
	var rng: RandomNumberGenerator = battle.rng if battle != null else RandomNumberGenerator.new()
	list.shuffle()
	for i in ACID_N:
		var u = list[i % list.size()]  # 먼저 한 마리씩 겨누고, 남는 덩이는 다시 돌며 둘레에 흩는다
		var j := Vector3(rng.randf_range(-1.8, 1.8), 0, rng.randf_range(-1.8, 1.8)) if i >= list.size() else Vector3.ZERO
		var p: Vector3 = u.global_position + j
		p.y = 0.0
		_acid_spots.append(p)
		flat.append_array([snappedf(p.x, 0.01), snappedf(p.z, 0.01)])
		if battle != null:
			battle.danger(p, ACID_R, ACID_TELE)
	_start_tele("acid", ACID_TELE)
	var ev := ["acid", flat]
	_event(ev)
	play_event(ev)


func _acid_land() -> void:
	for u in _units():
		for p in _acid_spots:
			if Formation.flat_distance(p, u.global_position) <= ACID_R:
				u.take_damage(hit_damage() * ACID_MULT, self)
				u.apply_vulnerable(ACID_VULN, 4.0)
				break


# --- 연출 ---

func play_event(ev: Array) -> void:
	if ev.is_empty() or not is_inside_tree():
		return
	var par := get_parent()
	match str(ev[0]):
		"web":
			var at: float = _model.play_skill("web")
			var i := 0
			for id in ev[1]:
				var t = battle.unit_by_uid(int(id)) if battle != null else null
				if t != null:
					_model.face(t.global_position - global_position)
					_shoot_web(t, at + i * 0.15)
				i += 1
		"lunge":
			var p := Vector3(float(ev[1]), 0, float(ev[2]))
			_model.face(p - global_position)
			_model.play_skill("lunge", LUNGE_TELE)
			Fx.telegraph_circle(par, p, LUNGE_R, LUNGE_TELE + LUNGE_AIR)
			Fx.charge(self, VENOM, 1, LUNGE_TELE)
		"land":
			Fx.blast(par, global_position, VENOM, LUNGE_R, true, 2, 2)
			Fx.quake(par, global_position, LUNGE_R, 1)
			Fx.zone(par, global_position, VENOM, LUNGE_R * 0.8, 3.0, "poison_cloud", 1)
			Fx.kick(par, global_position, 0.35, 0.06)
		"brood":
			_model.play_skill("brood")
			Fx.splash(par, _model.abdomen_tip(), VENOM, 1.4)
			Fx.halo(par, _model.abdomen_tip(), VENOM, 2.4, 0.6)
		"acid":
			_model.play_skill("acid", 0.5)
			Fx.spark(par, _model.abdomen_tip(), VENOM, 1.4)
			var flat: Array = ev[1]
			for k in range(0, flat.size() - 1, 2):
				var p2 := Vector3(float(flat[k]), 0, float(flat[k + 1]))
				Fx.telegraph_circle(par, p2, ACID_R, ACID_TELE)
				var fall := 0.6
				var par_id := par.get_instance_id()
				get_tree().create_timer(maxf(0.05, ACID_TELE - fall), false).timeout.connect(func():
					var pn = instance_from_id(par_id)
					if is_instance_valid(pn):
						Fx.meteor(pn, p2, VENOM, ACID_R, 1, fall))

extends Node3D
## 총력전 병사(PVP, pvp_battle.gd). 성 병사(soldier.gd)와 같은 모델(SoldierBody)·능력치(GameData.soldier_stats — 병종·티어 기본값, 양쪽 똑같이)로
## 들판에서 싸운다: SCAN_INTERVAL초마다 가까운 적(영웅·병사, 영웅은 조금 더 노린다)을 골라 쫓아가 치고(근접 = 모션 타격 순간, 궁병 = 화살 도착 순간),
## 없으면 상대 진영 쪽으로 걷는다. 영웅 스킬이 거는 상태(둔화·중독·화상·빙결·속박·취약·약화·넉백·도발)를 받는다(war_hero와 같은 규칙, 짧게).
## 그룹: team 0 = "soldiers"(하늘색 HP 바)·"pvp0", team 1 = "monsters"(빨간 HP 바)·"pvp1" — 영웅의 아군 그룹(heroes·war_def)에는 넣지 않는다
## (회복·오라는 영웅끼리). 적 그룹 foes = "pvp1"/"pvp0".

const Art := preload("res://scripts/art.gd")
const GameData := preload("res://scripts/game_data.gd")
const Formation := preload("res://scripts/formation.gd")
const SoldierBody := preload("res://scripts/soldier_body.gd")
const Fx := preload("res://scripts/fx.gd")
const FxStatus := preload("res://scripts/fx_status.gd")
const DamageNumbers := preload("res://scripts/damage_numbers.gd")
const ProjectileScript := preload("res://scripts/projectile.gd")
const Crowd := preload("res://scripts/crowd.gd")

signal fell(unit)

const SCAN_INTERVAL := 0.25
const SWING_SLACK := 0.6
const MUZZLE := Vector3(0, 1.33 * Art.SOLDIER_SCALE, 0)
const ARROW_SPEED := 30.0
const HERO_PULL := 3.0  # 영웅은 이만큼(m) 더 가깝게 친다
const KNOCK_SEC := 0.2
const CORPSE_SEC := 1.8
const DOT_TAGS := ["burn", "bleed", "curse"]

var team := 0
var type := "infantry"
var tier := 1
var uid := 0
var foes := "pvp1"
var def := {}  # {atk_interval, range, speed, aggro} — war_brain·pvp_brain이 dps를 읽는다
var role := "melee"
var hp := 0.0
var hp_max := 0.0
var atk := 0.0
var is_boss := false
var kind := "soldier"
var march_dir := Vector3.FORWARD  # 적이 없을 때 걷는 쪽

var _model
var _horse: MeshInstance3D
var _disc: MeshInstance3D
var _dead := false
var _fell_sent := false
var _target
var _swing
var _swing_left := 0.0
var _atk_cd := 0.0
var _scan_cd := 0.0
var _walking := false
var _corpse_t := 0.0
var _speed := 0.0
var _stun_t := 0.0
var _stun_fx: Node3D
var _slow_pct := 0.0
var _slow_t := 0.0
var _poison_dps := 0.0
var _poison_t := 0.0
var _dot_dps := PackedFloat64Array([0.0, 0.0, 0.0])
var _dot_t := PackedFloat64Array([0.0, 0.0, 0.0])
var _root_t := 0.0
var _vuln_pct := 0.0
var _vuln_t := 0.0
var _weak_pct := 0.0
var _weak_t := 0.0
var _knock_v := Vector3.ZERO
var _knock_t := 0.0
var _taunt_by
var _taunt_t := 0.0
var _status := {}


## add_child 전에.
func setup(p_type: String, p_tier: int, p_team: int, p_uid: int) -> void:
	type = p_type
	tier = p_tier
	team = p_team
	uid = p_uid
	foes = "pvp1" if team == 0 else "pvp0"
	var s := GameData.soldier_stats(type, tier)
	hp_max = float(s.hp)
	hp = hp_max
	atk = float(s.atk)
	_speed = float(s.speed)
	def = {"atk_interval": float(s.atk_interval), "range": float(s.range), "speed": float(s.speed), "aggro": float(s.aggro)}
	role = str(Art.SOLDIERS[type].role)
	_atk_cd = randf() * 0.4


func _ready() -> void:
	add_to_group("crowd")
	add_to_group("pvp%d" % team)
	add_to_group("soldiers" if team == 0 else "monsters")
	var body := SoldierBody.build(self, type, true)
	_model = body[0]
	_horse = body[1]
	_disc = Fx.soldier_disc(Art.SOLDIERS[type].color if team == 0 else Color(0.85, 0.25, 0.2), 0.75 if _horse != null else 0.42)
	_disc.position.y = 0.02
	add_child(_disc)
	if _horse != null:
		_model.position.y = SoldierBody.RIDER_Y
	_face(march_dir)
	_model.play_idle()


func is_alive() -> bool:
	return not _dead


func hp_ratio() -> float:
	return hp / hp_max if hp_max > 0.0 else 0.0


func radius() -> float:
	return Crowd.CAVALRY_R if type == "cavalry" else Crowd.HUMAN_R * Art.CHARACTER_SCALE * Art.SOLDIER_SCALE


func hit_radius() -> float:
	return 0.0


func push_mass() -> float:
	return Crowd.mass(radius(), not _walking)


func bar_height() -> float:
	return Art.HEAD_HEIGHT * Art.CHARACTER_SCALE * Art.SOLDIER_SCALE + (SoldierBody.RIDER_Y if _horse != null else 0.0)


func bar_scale() -> float:
	return 0.7


func is_on_wall() -> bool:
	return false


func current_target():
	return _target if _target != null and is_instance_valid(_target) and _target.is_alive() else null


func _process(delta: float) -> void:
	if _dead:
		if _model.visible:
			_corpse_t += delta
			if _corpse_t >= CORPSE_SEC:
				_model.visible = false
				_model.set_process(false)
				if _horse != null:
					_horse.visible = false
		return
	_tick_status(delta)
	if _dead:
		return
	if _knock_t > 0.0:
		var dt := minf(delta, _knock_t)
		_knock_t -= delta
		global_position += _knock_v * dt
		return
	if _stun_t > 0.0:
		_stun_t -= delta
		if _stun_t <= 0.0 and is_instance_valid(_stun_fx):
			_stun_fx.queue_free()
		return
	_atk_cd -= delta
	if _swing != null:
		_swing_left -= delta
		if _swing_left <= 0.0:
			_release()
	if _taunt_t > 0.0 and is_instance_valid(_taunt_by) and _taunt_by.is_alive():
		_target = _taunt_by
	_scan_cd -= delta
	var lost: bool = _target != null and not (is_instance_valid(_target) and _target.is_alive())
	if (_scan_cd <= 0.0 or lost) and _swing == null and _taunt_t <= 0.0:
		_scan_cd = SCAN_INTERVAL
		_target = _find_target()
	var t = current_target()
	if t == null:
		_walk(global_position + march_dir * 4.0, delta)
		return
	var tp: Vector3 = t.global_position
	var d := Formation.flat_distance(global_position, tp)
	_face(tp - global_position)
	if d <= float(def.range):
		_set_walking(false)
		if _atk_cd <= 0.0 and _swing == null:
			_atk_cd = float(def.atk_interval)
			_swing = t
			_swing_left = _model.play_attack(_atk_cd)
		return
	if _swing == null:
		_walk(tp, delta)


func _walk(to: Vector3, delta: float) -> void:
	if _root_t > 0.0:
		_set_walking(false)
		return
	var sp := _speed * ((1.0 - _slow_pct / 100.0) if _slow_t > 0.0 else 1.0)
	var flat := Vector3(to.x, global_position.y, to.z)
	_face(flat - global_position)
	global_position = global_position.move_toward(flat, sp * delta)
	_set_walking(true)


## 가까운 적(영웅은 HERO_PULL m 더 가깝게 친다).
func _find_target():
	var best = null
	var best_d := INF
	for f in get_tree().get_nodes_in_group(foes):
		if not f.is_alive():
			continue
		var d := Formation.flat_distance(global_position, f.global_position)
		if f.get("kind") == "hero":
			d -= HERO_PULL
		if d < best_d:
			best_d = d
			best = f
	return best


func _release() -> void:
	var m = _swing
	_swing = null
	if not is_instance_valid(m) or not m.is_alive():
		return
	if role != "ranged":
		if Formation.flat_distance(global_position, m.global_position) <= float(def.range) + SWING_SLACK:
			_hit(m)
		return
	var p = ProjectileScript.new()
	p.target = m
	p.speed = ARROW_SPEED
	p.color = Art.SOLDIERS[type].color
	p.on_hit = _hit
	get_parent().add_child(p)
	p.global_position = global_position + MUZZLE


func _hit(m) -> void:
	if not is_instance_valid(m) or not m.is_alive() or _dead:
		return
	var a := atk * ((1.0 - _weak_pct / 100.0) if _weak_t > 0.0 else 1.0)
	if team == 0:
		m.take_damage(a, DamageNumbers.Kind.HIT)
	else:
		m.take_damage(a, self)


func _set_walking(on: bool) -> void:
	if on == _walking:
		return
	_walking = on
	if on:
		_model.play_walk()
	else:
		_model.play_idle()


func _face(dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	_model.face(dir)
	if _horse != null:
		_horse.rotation.y = _model.rotation.y


# --- 받는 피해·상태 ---

func take_damage(amount: float, source = null) -> void:
	if _dead:
		return
	var shown := DamageNumbers.Kind.HURT if team == 0 else DamageNumbers.Kind.HIT
	if typeof(source) == TYPE_INT:
		if team == 1:
			shown = source
		elif source == DamageNumbers.Kind.POISON:
			shown = source
	if _vuln_t > 0.0:
		amount *= 1.0 + _vuln_pct / 100.0
	hp = maxf(0.0, hp - amount)
	DamageNumbers.pop(self, amount, shown)
	if hp <= 0.0:
		die()


func die() -> void:
	if _dead:
		return
	_dead = true
	hp = 0.0
	_swing = null
	_model.play_death()
	_disc.visible = false
	if _horse != null:
		_model.position.y = 0.0
	_clear_status()
	if not _fell_sent:
		_fell_sent = true
		fell.emit(self)


func _tick_status(delta: float) -> void:
	_slow_t -= delta
	_root_t -= delta
	_vuln_t -= delta
	_weak_t -= delta
	_taunt_t -= delta
	if _poison_t > 0.0:
		var dt := minf(delta, _poison_t)
		_poison_t -= delta
		take_damage(_poison_dps * dt, DamageNumbers.Kind.POISON)
	for i in 3:
		if _dot_t[i] > 0.0 and not _dead:
			var dt := minf(delta, _dot_t[i])
			_dot_t[i] -= delta
			take_damage(_dot_dps[i] * dt, DamageNumbers.Kind.POISON)
	if not _status.is_empty():
		for k in _status.keys():
			if _left(k) <= 0.0:
				if is_instance_valid(_status[k]):
					_status[k].queue_free()
				_status.erase(k)


func _clear_status() -> void:
	for n in _status.values():
		if is_instance_valid(n):
			n.queue_free()
	_status.clear()
	if is_instance_valid(_stun_fx):
		_stun_fx.queue_free()
	_slow_t = 0.0
	_poison_t = 0.0
	_dot_t = PackedFloat64Array([0.0, 0.0, 0.0])
	_root_t = 0.0
	_vuln_t = 0.0
	_weak_t = 0.0
	_knock_t = 0.0
	_taunt_t = 0.0
	_stun_t = 0.0


func _left(k: String) -> float:
	match k:
		"slow":
			return _slow_t
		"poison":
			return _poison_t
		"burn":
			return _dot_t[0]
		"bleed":
			return _dot_t[1]
		"curse":
			return _dot_t[2]
		"root":
			return _root_t
		"vulnerable":
			return _vuln_t
		"weaken":
			return _weak_t
	return 0.0


func _show(k: String) -> void:
	if not _status.has(k) and is_inside_tree():
		_status[k] = FxStatus.attach(self, k, bar_height(), 0.8, radius())


func apply_slow(pct: float, sec: float) -> void:
	if _dead:
		return
	_slow_pct = clampf(pct, 0.0, 100.0)
	_slow_t = sec
	_show("slow")


func apply_poison(dps: float, sec: float) -> void:
	if _dead:
		return
	_poison_dps = dps
	_poison_t = sec
	_show("poison")


func apply_dot(tag: String, dps: float, sec: float) -> void:
	var i := DOT_TAGS.find(tag)
	if i < 0 or _dead:
		return
	_dot_dps[i] = maxf(_dot_dps[i], dps) if _dot_t[i] > 0.0 else dps
	_dot_t[i] = maxf(_dot_t[i], sec)
	_show(tag)


func apply_stun(sec: float) -> void:
	if _dead:
		return
	_stun_t = maxf(_stun_t, sec)
	_swing = null
	if not is_instance_valid(_stun_fx) and is_inside_tree():
		_stun_fx = Fx.stun(self, bar_height() + 0.3)


func apply_freeze(sec: float) -> void:
	apply_stun(sec)


func apply_root(sec: float) -> void:
	if _dead:
		return
	_root_t = maxf(_root_t, sec)
	_show("root")


func apply_vulnerable(pct: float, sec: float) -> void:
	if _dead:
		return
	_vuln_pct = maxf(_vuln_pct, pct) if _vuln_t > 0.0 else maxf(0.0, pct)
	_vuln_t = maxf(_vuln_t, sec)
	_show("vulnerable")


func apply_weaken(pct: float, sec: float) -> void:
	if _dead:
		return
	_weak_pct = clampf(maxf(_weak_pct, pct) if _weak_t > 0.0 else pct, 0.0, 100.0)
	_weak_t = maxf(_weak_t, sec)
	_show("weaken")


func knockback(from: Vector3, dist: float) -> void:
	if _dead or dist <= 0.0:
		return
	var d := Vector3(global_position.x - from.x, 0.0, global_position.z - from.z)
	if d.length() < 0.001:
		d = Vector3.BACK
	_knock_v = d.normalized() * (dist / KNOCK_SEC)
	_knock_t = KNOCK_SEC
	_swing = null


func taunt(by, sec: float) -> void:
	if _dead or not is_instance_valid(by) or not by.is_alive():
		return
	_taunt_by = by
	_taunt_t = sec
	_target = by


func has_status(tag: String) -> bool:
	match tag:
		"stun", "freeze":
			return _stun_t > 0.0
		"taunt":
			return _taunt_t > 0.0
		"knockback":
			return _knock_t > 0.0
	return _left(tag) > 0.0


func is_controlled() -> bool:
	return _slow_t > 0.0 or _stun_t > 0.0 or _root_t > 0.0


func is_stunned() -> bool:
	return _stun_t > 0.0


func status_fx(k: String):
	var n = _status.get(k)
	return n if is_instance_valid(n) else null

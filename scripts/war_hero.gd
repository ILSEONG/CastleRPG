extends "res://scripts/hero.gd"
## 공성전 영웅(길드전). hero.gd 아레나 영웅(castle = null) 그대로에 세 가지를 더한다.
## 1) 편: team 0 = 공격(그룹 "heroes", 적 "monsters"), team 1 = 수비(아군 그룹 "war_def" + 표적 그룹 "monsters", 적 "heroes") — 영웅끼리 싸운다. 그래서 몬스터가 받던
##    상태(slow·poison·burn/bleed/curse·freeze·root·vulnerable·weaken·knockback·taunt)를 영웅도 받는다(monster.gd와 같은 규칙, 이펙트 FxStatus).
## 2) 성: war_half(공성 성 내부 절반) 안팎을 오갈 때 성문을 지난다(Formation.route) — 표적도 같은 영역(성 안/밖)만, 성을 가로지르는 추격은 안 한다.
## 3) 머리: 표적 고르기·aoe_blast 시점·뒷걸음(카이팅)·목표(성문·성채) 진격은 war_brain.gd(battle.brain). 플레이어 영웅은 이동 명령을 받으면
##    (commanded) 그 자리를 지키고, battle.set_auto로 다시 자동 진격.
## 능력치: stats = {hp, atk}를 주면 그 값(상대 길드원의 수비 영웅 — 내 성장·연구·장비와 무관), 없으면 내 영웅(hero.refresh_stats).
## 온라인 동시 전투(war_net.gd): 방장 기기만 판단하고(이 스크립트 그대로), 다른 기기의 영웅은 puppet — 방장이 보낸 위치·체력·동작을 따라 그리기만 한다.

const FxStatus := preload("res://scripts/fx_status.gd")
const DOT_TAGS := ["burn", "bleed", "curse"]
const KNOCK_SEC := 0.2
const PUPPET_LERP := 12.0  # 꼭두각시 위치 따라잡기(1/초)

signal fell(unit)  # 쓰러짐(점수·부활 대기)

var team := 0
var uid := 0  # 전투 안 고유 번호(온라인 동기화)
var owner_id := ""  # 조종하는 길드원(플레이어 id, 가상 길드원은 "v:<n>", 수비는 "d:<n>")
var squad := 0  # 같은 길드원의 4명 = 한 분대(집중 공격 대상 공유)
var lane := 0  # 맡은 면(성문 0..3)
var post_slot := 0  # 수비: 면 안 자리 순번(성채·지원 자리 고를 때)
var post_pos := Vector3.ZERO  # 수비: 지키는 자리 / 공격: 진영 자리
var war_half := 0.0
var battle  # war_battle.gd(brain·목표 위치)
var commanded := false  # 플레이어가 이동 명령을 내렸다(자동 진격 멈춤)
var mine := false  # 이 기기의 플레이어 영웅(선택·조종 가능)
var puppet := false  # 온라인: 방장이 아닌 기기 — 따라 그리기만
var is_boss := false  # 거인 사냥(boss_slayer) 대상 아님
var kind := "hero"
var fixed_stats := {}
var kite_cd := 0.0
var think_cd := 0.0
var falls := 0  # 이 전투에서 쓰러진 횟수(공격 영웅 목숨, WarRules.ATTACK_LIVES)
var _corpse_t := 0.0  # 쓰러진 뒤 이만큼 지나면 모델을 감추고 애니메이션을 멈춘다(성능)

const CORPSE_SEC := 1.8
const WarRulesH := preload("res://scripts/war_rules.gd")

var _base_atk := 0.0
var _base_speed := 0.0
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
var _fell_sent := false
# 꼭두각시(온라인)
var _p_pos := Vector3.ZERO
var _p_face := Vector3.ZERO
var _p_state := -1
var _p_swings := 0


## add_child 전에. stats = {hp, atk}(없으면 내 영웅 능력치). 팀에 맞춰 그룹을 정한다.
func setup_war(p_uid: int, p_def: Dictionary, p_team: int, level: int, promotion: int, stats := {}) -> void:
	uid = p_uid
	team = p_team
	fixed_stats = stats
	if team == 1:
		allies = "war_def"  # 회복·오라·부활은 수비 영웅끼리(성문·성채는 "monsters"에만 있다)
		foes = "heroes"
	setup(p_uid, p_def, null, null, promotion, level)


func _ready() -> void:
	super._ready()
	_p_pos = global_position
	_model.crowd_lod = true  # 영웅 160명: 붐비면 애니메이션 간헐 갱신·그림자 끔(몬스터와 같다)
	if team == 1:
		add_to_group("monsters")  # 공격 영웅의 표적(적 그룹) · 빨간 HP 바


func refresh_stats() -> void:
	if fixed_stats.is_empty():
		super.refresh_stats()
	else:
		var ratio := hp_ratio() if hp_max > 0.0 else 1.0
		hp_max = float(fixed_stats.hp)
		atk = float(fixed_stats.atk)
		_skill_mult = 1.0
		_aspd = 1.0
		_speed = float(def.speed)
		_gear_lifesteal = 0.0
		_gear_dmg_reduce = 0.0
		var b: Dictionary = Economy.upgrade_bonus().duplicate()
		for k in b:
			b[k] = 0.0
		_bonus = b
		hp = hp_max * ratio
	_base_atk = atk
	_base_speed = _speed


func _process(delta: float) -> void:
	if state == State.DEAD:
		_tick_corpse(delta)
	if puppet:
		_puppet_tick(delta)
		return
	if state == State.DEAD:
		_send_fell()
		return
	_tick_status(delta)
	if state == State.DEAD:
		_send_fell()
		return
	if _knock_t > 0.0:
		_tick_knock(delta)
		return
	_speed = _base_speed * (1.0 - _slow_pct / 100.0) if _slow_t > 0.0 else _base_speed
	atk = (_base_atk * (1.0 - _weak_pct / 100.0) if _weak_t > 0.0 else _base_atk) * gate_top_mult()
	if _taunt_t > 0.0 and is_instance_valid(_taunt_by) and _taunt_by.is_alive() and _same_region(_taunt_by.global_position):
		_target = _taunt_by
	think_cd -= delta
	kite_cd -= delta
	if think_cd <= 0.0 and battle != null and not is_stunned():
		think_cd = 0.25
		battle.brain.think(self)
	var before := global_position
	super._process(delta)
	if _root_t > 0.0:
		global_position = Vector3(before.x, global_position.y, before.z)
	if state == State.DEAD:
		_send_fell()


func _tick_corpse(delta: float) -> void:
	if _model.visible:
		_corpse_t += delta
		if _corpse_t >= CORPSE_SEC:
			_model.visible = false
			_model.set_process(false)


func _show_body() -> void:
	_corpse_t = 0.0
	_model.visible = true
	_model.set_process(true)


func _send_fell() -> void:
	if not _fell_sent:
		_fell_sent = true
		fell.emit(self)


## 표적은 머리가 고른다(같은 영역·가로지르지 않음·점수). 머리가 없으면(테스트) 아레나 기본.
func _find_target():
	if battle == null:
		return super._find_target()
	return battle.brain.pick_target(self)


func _blast_ok(m) -> bool:
	return battle == null or battle.brain.blast_ok(self, m)


## 성문 위 원거리 수비 영웅 피해 배율(WarRules.GATE_TOP_MULT): 성벽 위, 성문 가운데에서 GATE_TOP_R 안. 그 밖은 1.
func gate_top_mult() -> float:
	if team != 1 or role != "ranged" or war_half <= 0.0 or not is_on_wall():
		return 1.0
	var s := Formation.side_of(global_position)
	if absf(Formation.perp(s).dot(global_position) - Formation.nearest_gate_at(war_half, s, global_position)) > WarRulesH.GATE_TOP_R:
		return 1.0
	return WarRulesH.GATE_TOP_MULT


## 성 안팎·성벽 위아래를 오가면 성문·계단 경로(Formation.route).
func _replan() -> void:
	if not is_inside_tree():
		return
	_target = null
	if war_half > 0.0:
		_path = Formation.route(war_half, global_position, stand_position())
	else:
		_path = [stand_position()]


## 지금 걸어가는 경로가 없고 자리가 성벽 너머면 성문으로 돌아간다(hero는 아레나에서 곧장 걷는다).
func needs_route() -> bool:
	if war_half <= 0.0 or not _path.is_empty():
		return false
	var home := stand_position()
	return Formation.is_inside(war_half, global_position) != Formation.is_inside(war_half, home) \
		or (global_position.y > Balance.WALL_H / 2.0) != (home.y > Balance.WALL_H / 2.0)


## 닿을 수 있는 자리: 성벽 위 영웅은 어디든(사거리 안), 성벽 위 표적은 원거리만, 지상끼리는 같은 영역(성 안/밖).
func _same_region(p: Vector3) -> bool:
	if war_half <= 0.0 or is_on_wall():
		return true
	if p.y > Balance.WALL_H / 2.0:
		return role == "ranged"
	return Formation.is_inside(war_half, global_position) == Formation.is_inside(war_half, p)


## 영웅 사거리에 더하는 몸 반지름(hero._reach): 영웅은 0.
func hit_radius() -> float:
	return 0.0


func is_walking() -> bool:
	return not _path.is_empty()


func current_target():
	return _target if _target != null and is_instance_valid(_target) and _target.is_alive() else null


## 다른 위치로 잠깐 물러난다(자리는 그대로 — 위협이 지나면 돌아온다).
func step_to(p: Vector3) -> void:
	if war_half > 0.0:
		_path = Formation.route(war_half, global_position, Vector3(p.x, 0.0, p.z))
	else:
		_path = [Vector3(p.x, 0.0, p.z)]
	_swing = null
	_target = null


## 지키는(머무는) 자리를 바꾼다(자동 진격·수비 재배치). 지금 걷는 중이 아니면 곧장 간다.
func set_home(p: Vector3, go := true) -> void:
	post = Formation.POST_FREE
	free_pos = Vector3(p.x, Balance.WALL_H if p.y > Balance.WALL_H / 2.0 else 0.0, p.z)  # 성벽 위 자리는 높이 그대로
	hold = true
	if go:
		_replan()


## 플레이어 이동 명령(unit_picker): 자동 진격을 멈추고 그 자리를 지킨다.
func move_to_point(p: Vector3) -> void:
	if battle != null and battle.deploying:
		battle.deploy_unit(self, p)  # 배치 중: 걸어가지 않고 그 자리에 선다
		return
	commanded = true
	set_home(p)


# --- 받는 피해·상태(monster.gd와 같은 규칙) ---

## source가 숫자면 피해 숫자 종류(DamageNumbers.Kind), 노드면 때린 쪽(가시 반사). 수비 영웅은 맞을 때 공격 쪽 색(치명·스킬)으로 뜬다.
func take_damage(amount: float, source = null) -> void:
	if state == State.DEAD or puppet:
		return
	var shown := DamageNumbers.Kind.HURT
	if typeof(source) == TYPE_INT:
		shown = source
		source = null
	if team == 0 and shown != DamageNumbers.Kind.POISON:
		shown = DamageNumbers.Kind.HURT
	if _vuln_t > 0.0:
		amount *= 1.0 + _vuln_pct / 100.0
	var roll := randf()  # 회피 먼저(hero.gd와 같다): 피한 공격은 보호막도 깎지 않는다
	if _sk.has("dodge") and roll < _sk.dodge[0] / 100.0:
		DamageNumbers.pop(self, 0.0, DamageNumbers.Kind.DODGE)
		return
	amount = _skx.incoming(amount, source)
	if amount <= 0.0:
		return
	var r := Skills.incoming(_sk, amount, roll)
	if r.x <= 0.0:
		DamageNumbers.pop(self, 0.0, DamageNumbers.Kind.DODGE)
		return
	hp = maxf(0.0, hp - r.x)
	DamageNumbers.pop(self, r.x, shown)
	if shown != DamageNumbers.Kind.POISON and hp > 0.0:
		_model.hit_react(shown == DamageNumbers.Kind.SKILL or shown == DamageNumbers.Kind.CRIT)
	var back := maxf(r.y, atk * _sk.thorns[0] / 100.0) if _sk.has("thorns") else r.y
	if back > 0.0 and source != null and is_instance_valid(source) and source.is_alive():
		source.take_damage(back * _skill_mult, DamageNumbers.Kind.SKILL)
	if hp == 0.0 and _skx.try_revive():
		return
	if hp == 0.0:
		die()
		return
	_skx.after_hurt(source)


func die() -> void:
	if state == State.DEAD:
		return
	hp = 0.0
	state = State.DEAD
	_cancel_cast()
	_model.play_death()
	_ring.visible = false
	_foot.visible = false
	_aura_ring.visible = false
	_clear_status()
	_send_fell()


func revive(pct: float) -> void:
	var was_dead := state == State.DEAD
	super.revive(pct)
	if was_dead and state != State.DEAD:
		_fell_sent = false
		_show_body()


## 진영에서 다시 일어난다(공격 영웅 부활).
func respawn(at: Vector3) -> void:
	_clear_status()
	_fell_sent = false
	hp = hp_max
	state = State.IDLE
	_stun_t = 0.0
	_target = null
	_swing = null
	_path.clear()
	global_position = at
	_show_body()
	_model.reset_pose()
	_foot.visible = true
	_ring.visible = selected
	_skx.reset()


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
		if _dot_t[i] > 0.0 and state != State.DEAD:
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
	_slow_t = 0.0
	_poison_t = 0.0
	_dot_t = PackedFloat64Array([0.0, 0.0, 0.0])
	_root_t = 0.0
	_vuln_t = 0.0
	_weak_t = 0.0
	_knock_t = 0.0
	_taunt_t = 0.0


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
	if not _status.has(k):
		_status[k] = FxStatus.attach(self, k, bar_height(), 1.0, radius())


func apply_slow(pct: float, sec: float) -> void:
	if state == State.DEAD:
		return
	_slow_pct = clampf(pct, 0.0, 100.0)
	_slow_t = sec
	_show("slow")


func apply_poison(dps: float, sec: float) -> void:
	if state == State.DEAD:
		return
	_poison_dps = dps
	_poison_t = sec
	_show("poison")


func apply_dot(tag: String, dps: float, sec: float) -> void:
	var i := DOT_TAGS.find(tag)
	if i < 0 or state == State.DEAD:
		return
	if _dot_t[i] > 0.0:
		_dot_dps[i] = maxf(_dot_dps[i], dps)
		_dot_t[i] = maxf(_dot_t[i], sec)
	else:
		_dot_dps[i] = dps
		_dot_t[i] = sec
	_show(tag)


## 빙결 = 기절(hero.apply_stun — 머리 위 별).
func apply_freeze(sec: float) -> void:
	apply_stun(sec)


func apply_root(sec: float) -> void:
	if state == State.DEAD:
		return
	_root_t = maxf(_root_t, sec)
	_show("root")


func apply_vulnerable(pct: float, sec: float) -> void:
	if state == State.DEAD:
		return
	_vuln_pct = maxf(_vuln_pct, pct) if _vuln_t > 0.0 else maxf(0.0, pct)
	_vuln_t = maxf(_vuln_t, sec)
	_show("vulnerable")


func apply_weaken(pct: float, sec: float) -> void:
	if state == State.DEAD:
		return
	_weak_pct = clampf(maxf(_weak_pct, pct) if _weak_t > 0.0 else pct, 0.0, 100.0)
	_weak_t = maxf(_weak_t, sec)
	_show("weaken")


func knockback(from: Vector3, dist: float) -> void:
	if state == State.DEAD or dist <= 0.0:
		return
	var d := Vector3(global_position.x - from.x, 0.0, global_position.z - from.z)
	if d.length() < 0.001:
		d = Vector3.BACK
	_knock_v = d.normalized() * (dist / KNOCK_SEC)
	_knock_t = KNOCK_SEC
	_swing = null


func _tick_knock(delta: float) -> void:
	var dt := minf(delta, _knock_t)
	_knock_t -= delta
	var step := _knock_v * dt
	if war_half <= 0.0 or Formation.is_inside(war_half, global_position + step) == Formation.is_inside(war_half, global_position):
		global_position += step
	else:
		_knock_t = 0.0  # 성벽에 막힌다


func taunt(by, sec: float) -> void:
	if state == State.DEAD or not is_instance_valid(by) or not by.is_alive():
		return
	_taunt_by = by
	_taunt_t = sec
	_target = by


func has_status(tag: String) -> bool:
	match tag:
		"stun", "freeze":
			return is_stunned()
		"taunt":
			return _taunt_t > 0.0
		"knockback":
			return _knock_t > 0.0
	return _left(tag) > 0.0


func is_controlled() -> bool:
	return _slow_t > 0.0 or is_stunned() or _root_t > 0.0


func status_fx(k: String):
	var n = _status.get(k)
	return n if is_instance_valid(n) else null


# --- 온라인 꼭두각시 ---

## 방장이 보낸 한 줄: [x, z, 방향(라디안), 체력 비율, 상태, 휘두른 횟수].
## 꼭두각시: 방장 스냅샷이 오기 전·배치 중 내가 옮긴 자리에 그대로 선다(스냅샷 전 기본값 (0,0,0) = 성 한가운데로 끌려가지 않게).
func puppet_hold(p: Vector3) -> void:
	_p_pos = p
	global_position = p


func puppet_apply(row: Array) -> void:
	_p_pos = Vector3(float(row[0]), float(row[6]) if row.size() > 6 else 0.0, float(row[1]))  # [6] = 높이(성벽 위)
	_p_face = Vector3(sin(float(row[2])), 0.0, cos(float(row[2])))
	var new_hp := float(row[3]) * hp_max
	if new_hp < hp - 0.5:
		DamageNumbers.pop(self, hp - new_hp, DamageNumbers.Kind.HURT if team == 0 else DamageNumbers.Kind.HIT)
	elif new_hp > hp + 0.5 and hp > 0.0:
		DamageNumbers.pop(self, new_hp - hp, DamageNumbers.Kind.HEAL)
	hp = new_hp
	var st := int(row[4])
	var swings := int(row[5])
	if st == State.DEAD and state != State.DEAD:
		state = State.DEAD
		_model.play_death()
		_foot.visible = false
		_ring.visible = false
		_send_fell()
	elif st != State.DEAD and state == State.DEAD:
		state = st
		_fell_sent = false
		global_position = _p_pos
		_show_body()
		_model.reset_pose()
		_foot.visible = true
	elif st != State.DEAD:
		if swings != _p_swings:
			_model.play_attack(float(def.atk_interval))
		elif st != _p_state:
			if st == State.MOVE:
				_model.play_walk()
			elif st == State.IDLE:
				_model.play_idle()
		state = st
	_p_swings = swings
	_p_state = st


func puppet_row() -> Array:
	return [snappedf(global_position.x, 0.01), snappedf(global_position.z, 0.01), snappedf(_model.rotation.y, 0.01),
		snappedf(hp_ratio(), 0.001), state, _attacks, snappedf(global_position.y, 0.01)]


func _puppet_tick(delta: float) -> void:
	if state == State.DEAD:
		return
	global_position = global_position.lerp(_p_pos, minf(1.0, delta * PUPPET_LERP))
	if _p_face.length() > 0.1:
		_model.face(_p_face)


## 바닥 차지 반지름(crowd.gd): 몸 + 여유 — 공성 영웅은 서로 조금 떨어져 서서 겹쳐 보이지 않는다(사거리·피격 판정은 radius 그대로).
func space() -> float:
	return radius() + WarRulesH.SPACE_PAD

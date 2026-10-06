extends Node3D
## 괴물(근접). 자기 위치에서 aggro 안·같은 영역(성 안/밖)의 지상 영웅·병사를 쫓아가 치고, 없으면 진로(_advance)로 돌아가 성문·성채를 친다.
## 성벽 위 영웅은 표적으로 삼지 않는다.
## 영웅 스킬 상태: slow(이동 −%), stun(이동·공격 정지), poison(초당 피해) — 이펙트(Fx)는 지속 동안 남는다(개정 17). 영웅을 칠 때 자신을 출처로 넘긴다(thorns 반사 대상).
## 스킬 100종 상태(이펙트 FxStatus): 지속 피해 burn·bleed·curse(태그마다 따로), freeze(기절처럼 정지 + 자세 멈춤), root(이동만 막힘 — 공격은 한다),
## vulnerable(받는 피해 +%), weaken(주는 피해 −% — 영웅·병사·성문·성채 모두), knockback(밀려남 — 성벽을 넘지 않는다), taunt(그 영웅만 노린다).
## 상태 이펙트는 상태마다 노드 하나(_status), 상태가 끝나거나 죽으면 지운다.
## 공격은 시작(_swing) 때 대상을 고정하고, 피해는 모션의 타격 순간(_release, 개정 12-2 §3)에 들어간다.
## 개정 18 아레나(던전): setup_arena(던전 적 행) — castle 없음. 거리 제한 없이 가장 가까운 영웅을 쫓고, 없으면 제자리. 자리는 쓰는 쪽이 정한다.

const Balance := preload("res://scripts/balance.gd")
const GameData := preload("res://scripts/game_data.gd")
const Art := preload("res://scripts/art.gd")
const Formation := preload("res://scripts/formation.gd")
const UnitModelScript := preload("res://scripts/unit_model.gd")
const Fx := preload("res://scripts/fx.gd")
const DamageNumbers := preload("res://scripts/damage_numbers.gd")
const Crowd := preload("res://scripts/crowd.gd")
const FxStatus := preload("res://scripts/fx_status.gd")

const SCAN_INTERVAL := 0.2
const SWING_SLACK := 0.6  # 타격 순간 대상(영웅·성문·성 지점)이 사거리 + 이만큼 안이면 맞는다(밖이면 헛스윙)
const AT_HERO := -2  # _swing_side: 영웅을 친다(-1 = 성, 0..3 = 성문 면)
const DOT_TAGS := ["burn", "bleed", "curse"]  # apply_dot 태그(인덱스 = _dot_dps·_dot_t 칸)
const KNOCK_SEC := 0.2  # 밀려나는 시간(이동·공격 멈춤)

signal died(monster)

var castle
var kind: String = "grunt"
var look := ""  # 생김새(Art.MONSTER_MODELS 키, 비면 kind) — 성 방어 적은 라운드마다 바뀐다(GameData.enemy_look), 능력치는 kind
var side: int = 0
var stage: int = 1
var hp: float = 0.0
var hp_max: float = 0.0
var atk: float = 0.0
var is_boss := false  # 보스(GameData.BOSS_KINDS — 성 대보스·왕고블린·데스나이트): 거인 사냥(boss_slayer) 대상

var _stats: Dictionary = {}
var _speed := 0.0  # 기본 이동속도 × 스테이지 배율(개정 22 §3, setup)
var _model
var _target_hero
var _atk_cd := 0.0
var _scan_cd := 0.0
var _dead := false
var _slow_pct := 0.0
var _slow_t := 0.0
var _stun_t := 0.0
var _poison_dps := 0.0
var _poison_t := 0.0
var _dot_dps := PackedFloat64Array([0.0, 0.0, 0.0])  # DOT_TAGS 칸마다 초당 피해
var _dot_t := PackedFloat64Array([0.0, 0.0, 0.0])  # DOT_TAGS 칸마다 남은 초
var _freeze_t := 0.0
var _iced := false  # 얼어서 모델 애니메이션을 멈춰 둔 상태
var _root_t := 0.0
var _vuln_pct := 0.0
var _vuln_t := 0.0
var _weak_pct := 0.0
var _weak_t := 0.0
var _knock_v := Vector3.ZERO  # 밀려나는 속도(m/초, 수평)
var _knock_t := 0.0
var _taunt_hero  # 도발한 영웅(_taunt_t 동안 이것만 노린다)
var _taunt_t := 0.0
var _status := {}  # 상태 이펙트 노드(slow·stun·poison·burn·bleed·curse·freeze·root·vulnerable·weaken — 지속 동안 남는다, 상한이면 null) — 상태가 끝나거나 죽으면 지운다
var _swing_left := -1.0  # 타격 순간까지 남은 초(음수 = 휘두르는 중 아님)
var _swing_hero           # 치려는 영웅(_swing_side == AT_HERO일 때)
var _swing_side := -1     # 치려는 것: AT_HERO, 성(-1), 성문 면(0..3)
var _swing_at := Vector3.ZERO  # 성문·성을 칠 때 그 지점
var _walking := false  # 이번 프레임에 걸었다(겹침 해소 무게)


## add_child 전에 호출. p_stage = 전체 라운드 g. hp_mult = 추가 HP 배율(라운드 25 보스 boss_round_mult). p_look = 생김새(비면 kind).
func setup(p_kind: String, p_side: int, p_stage: int, p_castle, hp_mult := 1.0, p_look := "") -> void:
	assert(not GameData.monster(p_kind).is_empty(), "unknown monster kind: " + p_kind)
	kind = p_kind
	look = p_look
	is_boss = kind in GameData.BOSS_KINDS
	side = p_side
	stage = p_stage
	castle = p_castle
	_stats = GameData.monster(kind)
	var st := GameData.stage(stage)
	hp = _stats.hp * st.hp_mult * hp_mult
	hp_max = hp
	atk = _stats.atk * st.atk_mult
	_speed = float(_stats.speed) * GameData.enemy_speed_mult(stage)


## 아레나(개정 18): row = 던전 적 한 행(Economy.dungeon_enemies — kind·hp·atk·speed·range·atk_interval·aggro·scale). add_child 전에.
func setup_arena(row: Dictionary) -> void:
	kind = row.kind
	is_boss = kind in GameData.BOSS_KINDS
	_stats = row
	hp = float(row.hp)
	hp_max = hp
	atk = float(row.atk)
	_speed = float(row.speed)  # 던전은 스테이지 속도 배율 없음


func _ready() -> void:
	add_to_group("monsters")
	add_to_group("crowd")  # 겹침 해소(crowd.gd)
	_model = UnitModelScript.new()
	_model.crowd_lod = true  # 화면 밖·붐빌 때 애니메이션 간헐 갱신, 붐비면 그림자 끔
	_model.setup(Art.monster_spec(look if look != "" else kind), float(_stats.scale))
	add_child(_model)
	if castle != null:
		global_position = castle.spawn_position(side)
		GameState.refilled.connect(_vanish)


func is_alive() -> bool:
	return not _dead


func take_damage(amount: float, kind := 0) -> void:  # kind = DamageNumbers.Kind(표시 색)
	if _dead:
		return
	if _vuln_t > 0.0:
		amount *= 1.0 + _vuln_pct / 100.0
	hp = maxf(0.0, hp - amount)
	DamageNumbers.pop(self, amount, kind)
	if kind != DamageNumbers.Kind.POISON and hp > 0.0:  # 피격 번쩍임·찌그러짐(개정 26, 지속 피해 틱은 빼고)
		_model.hit_react(kind == DamageNumbers.Kind.SKILL or kind == DamageNumbers.Kind.CRIT)
	if hp == 0.0:
		_dead = true
		remove_from_group("monsters")  # 즉시 표적 대상에서 빠진다
		for n in _status.values():  # 상태 이펙트는 시체에 남기지 않는다
			if is_instance_valid(n):
				n.queue_free()
		_status.clear()
		if _iced:  # 얼어 멈춘 자세에서 쓰러지게 애니메이션을 다시 돌린다
			_iced = false
			_model.set_process(true)
		died.emit(self)
		_model.play_death()
		get_tree().create_timer(Art.CORPSE_SEC).timeout.connect(queue_free)


func _process(delta: float) -> void:
	if _dead:
		return
	_walking = false
	_slow_t -= delta
	_stun_t -= delta
	_freeze_t -= delta
	_root_t -= delta
	_vuln_t -= delta
	_weak_t -= delta
	_taunt_t -= delta
	if _poison_t > 0.0:
		var dt := minf(delta, _poison_t)  # 마지막 틱은 남은 시간만큼만 — 합계가 dps × 초를 넘지 않는다
		_poison_t -= delta
		take_damage(_poison_dps * dt, DamageNumbers.Kind.POISON)
		if _dead:
			return
	for i in 3:  # 지속 피해 태그마다(독과 같은 규칙)
		if _dot_t[i] > 0.0:
			var dt := minf(delta, _dot_t[i])
			_dot_t[i] -= delta
			take_damage(_dot_dps[i] * dt, DamageNumbers.Kind.POISON)
			if _dead:
				return
	if not _status.is_empty():
		_end_status()
	if _knock_t > 0.0:
		_tick_knock(delta)
	if is_stunned():
		_swing_left = -1.0  # 기절·빙결은 휘두르던 공격도 끊는다
		if _freeze_t > 0.0:
			_ice(true)  # 언 자세 그대로
		else:
			_ice(false)
			_model.play_idle()
		return
	if _iced:
		_ice(false)
	if _knock_t > 0.0:
		return  # 밀려나는 동안은 걷지도 치지도 않는다(휘두르던 공격은 _tick_knock이 끊었다)
	_atk_cd -= delta
	_tick_swing(delta)
	_scan_cd -= delta
	if _taunt_t > 0.0 and _taunt_ok(_taunt_hero):
		_target_hero = _taunt_hero  # 도발: 탐색 없이 그 영웅
	else:
		if _taunt_hero != null:  # 도발이 끝났거나 대상이 무효 → 곧바로 다시 찾는다
			_taunt_hero = null
			_taunt_t = 0.0
			_scan_cd = 0.0
		if _scan_cd <= 0.0:
			_scan_cd = SCAN_INTERVAL
			_target_hero = _find_hero()
	if is_instance_valid(_target_hero) and _target_hero.is_alive() and not _target_hero.is_on_wall():  # 배치에서 빠진 영웅은 해제된다
		var hpos: Vector3 = _target_hero.global_position
		_model.face(hpos - global_position)
		if Formation.flat_distance(global_position, hpos) > _stats.range:
			if _root_t > 0.0:  # 묶임: 제자리(사거리 안에 오면 친다)
				_model.play_idle()
				return
			var next := global_position.move_toward(Vector3(hpos.x, 0.0, hpos.z), speed() * delta)
			if castle != null and Formation.is_inside(castle.half, next) != Formation.is_inside(castle.half, global_position):
				_target_hero = null  # 성 안팎 경계(성벽·모서리)를 넘는 걸음은 딛지 않고 진로로 간다
				_advance(delta)
				return
			_model.play_walk()
			_walking = true
			global_position = next
		elif _atk_cd <= 0.0:
			_swing(_target_hero, AT_HERO, Vector3.ZERO)
		return
	_target_hero = null
	_advance(delta)


## 진로: 성 밖이면 지금 가장 가까운 면의 성문으로(끌려간 뒤 재조준). 멀쩡하면 성문을 치고,
## 부서졌으면 성문 축에 맞춘 뒤 안쪽 지점을 거쳐 들어간다(성벽을 뚫지 않게). 성 안이면 성채를 친다.
func _advance(delta: float) -> void:
	if castle == null:  # 아레나: 영웅이 없으면 제자리
		_model.play_idle()
		return
	var half: float = castle.half
	var inside := Formation.is_inside(half, global_position)
	if not inside:
		side = Formation.side_of(global_position)
	var dest: Vector3
	var strikes := true
	if inside:
		dest = _spread(castle.keep_target(side), Formation._keep_half)
	elif GameState.is_gate_broken(side):
		strikes = false
		var aligned := absf(Formation.perp(side).dot(global_position)) < Balance.GATE_W / 2.0 - 0.5
		dest = Formation.gate_inner(half, side) if aligned else castle.gate_target(side)
	else:
		dest = _spread(castle.gate_target(side), Balance.GATE_W / 2.0)
	_model.face(dest - global_position)
	var stop: float = _stats.range if strikes else 0.1
	if Formation.flat_distance(global_position, dest) > stop:
		if _root_t > 0.0:  # 묶임: 제자리
			_model.play_idle()
			return
		_model.play_walk()
		_walking = true
		global_position = global_position.move_toward(dest, speed() * delta)
	elif strikes and _atk_cd <= 0.0:
		_swing(null, -1 if inside else side, dest)


## 성문·성채를 치는 지점 p를 그 면을 따라(±w) 자기 쪽으로 옮긴다 — 무리가 한 점에 몰리지 않고 문·외벽 폭에 퍼져 선다(겹침 해소).
func _spread(p: Vector3, w: float) -> Vector3:
	var t := Formation.perp(side)
	return p + t * clampf(t.dot(global_position - p), -w, w)


## 공격 시작(개정 12-2 §3): 대상(what = AT_HERO면 영웅 hero, 성(-1)·성문 면(0..3)이면 그 지점 at)을 고정하고 모션을 재생한다. 피해는 타격 순간(_release)에.
func _swing(hero, what: int, at: Vector3) -> void:
	_atk_cd = _stats.atk_interval
	_swing_hero = hero
	_swing_side = what
	_swing_at = at
	_swing_left = _model.play_attack(float(_stats.atk_interval))


func _tick_swing(delta: float) -> void:
	if _swing_left < 0.0:
		return
	_swing_left -= delta
	if _swing_left <= 0.0:
		_swing_left = -1.0
		_release()


## 타격 순간: 대상이 사거리 + SWING_SLACK 안이면(영웅은 살아 있고 지상일 때만) 피해, 아니면 헛스윙.
## 방치 무적 등 피해 판정은 받는 쪽(영웅 take_damage·GameState damage_*)이 이 순간에 한다.
func _release() -> void:
	var reach: float = float(_stats.range) + SWING_SLACK
	var h = _swing_hero
	_swing_hero = null
	if _swing_side == AT_HERO:
		if is_instance_valid(h) and h.is_alive() and not h.is_on_wall() and Formation.flat_distance(global_position, h.global_position) <= reach:
			h.take_damage(hit_damage(), self)
	elif Formation.flat_distance(global_position, _swing_at) <= reach:
		if _swing_side < 0:
			GameState.damage_castle(hit_damage())
		else:
			GameState.damage_gate(_swing_side, hit_damage())


## 지금 한 번 칠 때 피해(공격력, weaken 중이면 × (1 − pct/100)). 영웅·병사·성문·성채 모두 이 값을 받는다.
func hit_damage() -> float:
	return atk * (1.0 - _weak_pct / 100.0) if _weak_t > 0.0 else atk


## 지금 이동 속도(스테이지 배율·slow 반영).
func speed() -> float:
	return _speed * (1.0 - _slow_pct / 100.0) if _slow_t > 0.0 else _speed


## slow: 이동 속도 −pct%, sec초(갱신). 발밑 결정은 끝날 때까지.
func apply_slow(pct: float, sec: float) -> void:
	if not _status.has("slow"):
		_status.slow = Fx.slow(self)
	_slow_pct = clampf(pct, 0.0, 100.0)
	_slow_t = sec


## stun: sec초 이동·공격 정지(남은 시간보다 길 때만 늘린다). 머리 위 별은 끝날 때까지.
func apply_stun(sec: float) -> void:
	_stun_t = maxf(_stun_t, sec)
	if not _status.has("stun"):
		_status.stun = Fx.stun(self, bar_height() + 0.3)


## poison: sec초 동안 초당 dps 피해(갱신). 발밑 거품은 끝날 때까지.
func apply_poison(dps: float, sec: float) -> void:
	if not _status.has("poison"):
		_status.poison = Fx.poison(self)
	_poison_dps = dps
	_poison_t = sec


## 지속 피해: tag("burn"·"bleed"·"curse")마다 따로, sec초 동안 초당 dps(다시 걸면 dps·남은 시간 모두 큰 쪽). 모르는 태그는 무시.
## 숫자는 독과 같은 묶음(DamageNumbers.Kind.POISON). 이펙트는 태그마다 끝날 때까지.
func apply_dot(tag: String, dps: float, sec: float) -> void:
	var i := DOT_TAGS.find(tag)
	if i < 0 or _dead:
		return
	if _dot_t[i] > 0.0:
		_dot_dps[i] = maxf(_dot_dps[i], dps)
		_dot_t[i] = maxf(_dot_t[i], sec)
	else:
		_dot_dps[i] = dps
		_dot_t[i] = sec
	_show(tag)


## freeze: sec초 이동·공격 정지(기절로 친다 — is_stunned), 자세도 멈춘다. 남은 시간보다 길 때만 늘린다. 얼음 덩어리는 끝날 때까지.
func apply_freeze(sec: float) -> void:
	if _dead:
		return
	_freeze_t = maxf(_freeze_t, sec)
	_show("freeze")


## root: sec초 제자리(공격은 사거리 안이면 한다). 남은 시간보다 길 때만 늘린다. 발밑 덩굴은 끝날 때까지.
func apply_root(sec: float) -> void:
	if _dead:
		return
	_root_t = maxf(_root_t, sec)
	_show("root")


## vulnerable: sec초 동안 받는 피해(모든 출처, 지속 피해 포함) × (1 + pct/100). 다시 걸면 pct·남은 시간 모두 큰 쪽. 머리 위 보라 화살표.
func apply_vulnerable(pct: float, sec: float) -> void:
	if _dead:
		return
	_vuln_pct = maxf(_vuln_pct, pct) if _vuln_t > 0.0 else maxf(0.0, pct)
	_vuln_t = maxf(_vuln_t, sec)
	_show("vulnerable")


## weaken: sec초 동안 주는 피해 × (1 − pct/100)(hit_damage). 다시 걸면 pct·남은 시간 모두 큰 쪽. 허리 회색 고리.
func apply_weaken(pct: float, sec: float) -> void:
	if _dead:
		return
	_weak_pct = clampf(maxf(_weak_pct, pct) if _weak_t > 0.0 else pct, 0.0, 100.0)
	_weak_t = maxf(_weak_t, sec)
	_show("weaken")


## knockback: from에서 멀어지는 수평 방향으로 dist m(보스는 절반)를 KNOCK_SEC초에 걸쳐 밀린다(그동안 이동·공격 멈춤, 휘두르던 공격은 끊김).
## 성 모드에선 성 안팎(Formation.is_inside — 성벽 두께 포함)이 바뀌는 걸음은 딛지 않는다(축 하나로 미끄러지거나 멈춤). 아레나(castle 없음)는 제한 없음.
## 같은 자리(from = 자기 위치)면 성 중심에서 멀어지는 쪽. 죽었으면 무시.
func knockback(from: Vector3, dist: float) -> void:
	if _dead or dist <= 0.0:
		return
	var d := Vector3(global_position.x - from.x, 0.0, global_position.z - from.z)
	if d.length() < 0.001:
		d = Vector3(global_position.x, 0.0, global_position.z)
		if d.length() < 0.001:
			d = Vector3.BACK
	if is_boss:
		dist *= 0.5
	_knock_v = d.normalized() * (dist / KNOCK_SEC)
	_knock_t = KNOCK_SEC
	_swing_left = -1.0


func _tick_knock(delta: float) -> void:
	var dt := minf(delta, _knock_t)  # 마지막 프레임은 남은 시간만큼 — 합계가 dist를 넘지 않는다
	_knock_t -= delta
	_swing_left = -1.0
	var step := _knock_v * dt
	var here := global_position
	if castle == null:
		global_position = here + step
		return
	var half: float = castle.half
	var inside := Formation.is_inside(half, here)
	if Formation.is_inside(half, here + step) == inside:
		global_position = here + step
		return
	# 벽에 막히면 벽을 따라 한 축으로 미끄러진다(할당 없이 둘을 차례로)
	var sx := Vector3(step.x, 0.0, 0.0)
	var sz := Vector3(0.0, 0.0, step.z)
	if absf(step.x) > 0.0001 and Formation.is_inside(half, here + sx) == inside:
		global_position = here + sx
	elif absf(step.z) > 0.0001 and Formation.is_inside(half, here + sz) == inside:
		global_position = here + sz
	else:
		_knock_t = 0.0  # 어느 쪽도 막혔다(벽에 정면) — 그 자리에서 멈춘다


## taunt: sec초 동안 hero만 노린다(탐색 무시, 거리 제한 없음). 대상이 죽거나 성벽 위·다른 영역(성 안/밖)이면 풀리고 평소대로 찾는다.
func taunt(hero, sec: float) -> void:
	if _dead or not _taunt_ok(hero):
		return
	_taunt_hero = hero
	_taunt_t = sec
	_target_hero = hero


func _taunt_ok(h) -> bool:
	if not is_instance_valid(h) or not h.is_alive() or h.is_on_wall():
		return false
	return castle == null or Formation.is_inside(castle.half, h.global_position) == Formation.is_inside(castle.half, global_position)


## 상태가 걸려 있는가. tag: slow·stun·poison·burn·bleed·curse·freeze·root·vulnerable·weaken(+ taunt·knockback). 모르는 태그는 false.
func has_status(tag: String) -> bool:
	match tag:
		"slow":
			return _slow_t > 0.0
		"stun":
			return _stun_t > 0.0
		"poison":
			return _poison_t > 0.0
		"burn":
			return _dot_t[0] > 0.0
		"bleed":
			return _dot_t[1] > 0.0
		"curse":
			return _dot_t[2] > 0.0
		"freeze":
			return _freeze_t > 0.0
		"root":
			return _root_t > 0.0
		"vulnerable":
			return _vuln_t > 0.0
		"weaken":
			return _weak_t > 0.0
		"taunt":
			return _taunt_t > 0.0 and _taunt_hero != null
		"knockback":
			return _knock_t > 0.0
	return false


## 군중 제어(slow·stun·freeze·root) 중인가.
func is_controlled() -> bool:
	return _slow_t > 0.0 or is_stunned() or _root_t > 0.0


## 상태 이펙트가 없으면 붙인다(이미 있거나 상한이라 null이어도 다시 만들지 않는다 — 기존 slow·stun·poison과 같은 규칙).
func _show(k: String) -> void:
	if not _status.has(k):
		_status[k] = FxStatus.attach(self, k, bar_height(), float(_stats.scale), radius())


## 얼어 자세를 멈춘다/푼다(모델 애니메이션 처리 끄고 켬).
func _ice(on: bool) -> void:
	if _iced == on:
		return
	_iced = on
	_model.set_process(not on)


## 상태 k의 남은 초(≤ 0이면 끝).
func _left(k: String) -> float:
	match k:
		"stun":
			return _stun_t
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
		"freeze":
			return _freeze_t
		"root":
			return _root_t
		"vulnerable":
			return _vuln_t
		"weaken":
			return _weak_t
	return 0.0


## 끝난 상태(남은 시간 ≤ 0)의 이펙트를 지운다.
func _end_status() -> void:
	for k in _status.keys():
		if _left(k) <= 0.0:
			if is_instance_valid(_status[k]):
				_status[k].queue_free()
			_status.erase(k)


## 상태 이펙트 노드(테스트용): 없으면 null.
func status_fx(k: String):
	var n = _status.get(k)
	return n if is_instance_valid(n) else null


## 기절 또는 빙결(이동·공격 정지).
func is_stunned() -> bool:
	return _stun_t > 0.0 or _freeze_t > 0.0


## 표적: 자기 위치에서 aggro 안, 같은 영역의 살아 있는 지상 영웅·병사 중 가장 가까운 것(개정 21: 성문 앞 보병·기병, 성 안 병사). 성벽 위 궁병은 못 친다.
func _find_hero():
	var here_inside := castle != null and Formation.is_inside(castle.half, global_position)
	var best = null
	var best_d: float = float(_stats.aggro) if castle != null else INF  # 아레나는 거리 제한 없음
	var here := global_position
	for group in ["heroes", "soldiers"]:
		for h in get_tree().get_nodes_in_group(group):
			var hp: Vector3 = h.global_position
			var d := Vector2(hp.x - here.x, hp.z - here.z).length()  # = flat_distance. 거리 먼저 — 대부분 여기서 걸러진다
			if d > best_d or not h.is_alive() or h.is_on_wall():
				continue
			if castle != null and Formation.is_inside(castle.half, hp) != here_inside:
				continue
			best_d = d
			best = h
	return best


## 영웅 사거리에 더하는 몸 반지름(m). 보통 괴물은 0(중심 거리 그대로), 큰 보스(드래곤)는 몸 바깥에서 맞게 크다.
func hit_radius() -> float:
	return 0.0


func hp_ratio() -> float:
	return hp / hp_max if hp_max > 0.0 else 0.0


## 겹침 해소(crowd.gd): 몸 반지름(종류별 × 표 scale — 보스는 크다), 밀리는 무게(걷는 중이 아니면 — 싸우는 중 — 무겁다).
func radius() -> float:
	return Crowd.MONSTER_R.get(kind, 0.4) * float(_stats.scale)


## 묶이거나 얼었으면 밀리지 않는다(INF — 그 자리에 박힌 장애물).
func push_mass() -> float:
	if _root_t > 0.0 or _freeze_t > 0.0:
		return INF
	return Crowd.mass(radius(), not _walking)


func bar_height() -> float:
	return Art.HEAD_HEIGHT * Art.CHARACTER_SCALE * float(_stats.scale)


func bar_scale() -> float:
	return float(_stats.scale)


## 리필로 제거될 때. died를 내지 않으므로 Spawner는 refilled에서 카운트를 0으로 맞춘다.
func _vanish() -> void:
	_dead = true
	queue_free()

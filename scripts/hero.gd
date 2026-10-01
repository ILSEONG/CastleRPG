extends Node3D
## 영웅. 정의(heroes.csv 한 행: 역할·능력치·스킬 둘)와 배치 슬롯 index로 만든다. 배정 자리(면 · 성문 앞/성벽 위 · 슬롯,
## 또는 자유 위치)로 성문을 거쳐 이동한다(이동 중엔 적 무시).
## 지상에서는 자리 기준 aggro 안·같은 영역(성 안/밖)의 괴물을 쫓아가 치고 자리로 돌아오며, 성벽 위에서는 움직이지 않고
## 사거리 안 괴물을 쏜다. 성벽 위에 서 있으면 근접 괴물의 표적이 되지 않는다.
## 사망 시 부활 없음, GameState.refilled에서만 배정 자리로 복귀.
## 스킬(스펙 §3.2): 수식은 Skills(순수 함수), 적용은 여기 — 공격(_attack·_release·_strike·_chain·_cleave·_blast), 쿨 스킬(_tick_skills),
## 받는 피해(take_damage). 몬스터 상태(slow·stun·poison)는 monster.gd.

const Balance := preload("res://scripts/balance.gd")
const GameData := preload("res://scripts/game_data.gd")
const Art := preload("res://scripts/art.gd")
const Formation := preload("res://scripts/formation.gd")
const UnitModelScript := preload("res://scripts/unit_model.gd")
const Skills := preload("res://scripts/skills.gd")
const Fx := preload("res://scripts/fx.gd")
const DamageNumbers := preload("res://scripts/damage_numbers.gd")
const ProjectileScript := preload("res://scripts/projectile.gd")

enum State { IDLE, MOVE, ATTACK, DEAD }

const SCAN_INTERVAL := 0.2
const ARRIVE_EPS := 0.05
const HIT_HEIGHT := Vector3(0, 0.8, 0)
const HOLD_EPS := 0.5  # 이만큼 안이면 자기 자리를 지키고 있다(gate_repair)
const SWING_SLACK := 0.6  # 근접 타격 순간 대상이 사거리 + 이만큼 안이면 맞는다(밖이면 헛스윙)
const MUZZLE := Vector3(0, 1.3, 0)  # 투사체가 나가는 높이
## 모델 → 투사체 [모양, 속도 m/s](개정 12-2 §3). 없으면 화살.
const SHOTS := {"Mage": ["bolt", 18.0], "Barbarian": ["axe", 20.0]}
const ARROW_SPEED := 30.0

var castle
var formation
var index: int = 0
var def: Dictionary = {}  # 영웅 정의(GameData.hero 행)
var role: String = ""
var side: int = 0
var post: int = Formation.POST_GATE
var slot: int = 0
var free_pos := Vector3.ZERO  # post == POST_FREE일 때 서는 곳
var _path: Array[Vector3] = []
var hp: float = 0.0
var hp_max: float = 0.0  # 레벨·별 반영
var atk: float = 0.0     # 레벨·별 반영(오라 전)
var state: int = State.IDLE
var selected := false:
	set(v):
		selected = v
		if _ring != null:
			_ring.visible = v and state != State.DEAD

var _sk: Dictionary = {}  # def.skills
var _color := Color.WHITE
var _model
var _ring: MeshInstance3D
var _foot: MeshInstance3D
var _target
var _atk_cd := 0.0
var _scan_cd := 0.0
var _attacks := 0      # 공격 횟수(stun N번째)
var _swing             # 휘두르는(쏘려는) 중인 공격의 고정 대상. null = 없음
var _swing_left := 0.0  # 타격(발사) 순간까지 남은 초
var _heal_cd := 0.0
var _repair_cd := 0.0
var _blast_cd := 0.0


## add_child 전에 호출. 기본 배치: 면 = index % 4, melee는 성문 앞, ranged는 성벽 위(차 있으면 _place_default).
## copies = 보유 수(별), level = 영웅 레벨. HP·공격 = 기본 × 레벨 배율 × 별 배율(GameData.hero_stats).
func setup(p_index: int, p_def: Dictionary, p_castle, p_formation, copies := 1, level := 1) -> void:
	index = p_index
	def = p_def
	castle = p_castle
	formation = p_formation
	role = def.role
	_sk = def.skills
	_color = Color(def.color)
	var st := GameData.hero_stats(def, level, copies)
	hp_max = st.hp
	atk = st.atk
	_place_default()


## 기본 자리(면 index % 4의 역할 자리). 게임 중 다시 만든 영웅(배치·별 변경)은 다른 영웅들이 옮겨 와 그 자리가 차 있을 수 있다 —
## 같은 면 다른 자리 → 다른 면들(역할 자리 먼저) → 그래도 다 차면 그 면 성문 앞 바닥(자유 위치)에 선다.
func _place_default() -> void:
	var home := index % 4
	var first := Formation.POST_WALL if role == "ranged" else Formation.POST_GATE
	var second := Formation.POST_GATE if first == Formation.POST_WALL else Formation.POST_WALL
	for k in 4:
		for p in [first, second]:
			if move_to((home + k) % 4, p):
				return
	move_to_point(Formation.slot_position(castle.half, home, Formation.POST_GATE, 0))


func _ready() -> void:
	add_to_group("heroes")
	_model = UnitModelScript.new()
	_model.setup(Art.hero_spec(def))
	add_child(_model)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.6
	torus.outer_radius = 0.8
	_ring = Art.mesh(torus, Art.HERO_SELECTED)
	_ring.position.y = 0.05
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)
	_foot = Fx.foot_ring(Art.GRADE_COLORS[def.grade], _color)
	_foot.position.y = 0.02
	add_child(_foot)
	GameState.refilled.connect(reset)
	reset()


func reset() -> void:
	hp = hp_max
	state = State.IDLE
	_target = null
	_swing = null
	_attacks = 0
	_heal_cd = _sk.heal_aura[0] if _sk.has("heal_aura") else 0.0
	_repair_cd = _sk.gate_repair[0] if _sk.has("gate_repair") else 0.0
	_blast_cd = 0.0
	global_position = stand_position()
	_path.clear()
	_model.reset_pose()
	_model.face(Formation.SIDE_DIR[side])  # 대기 중엔 성 바깥을 본다
	_ring.visible = selected
	_foot.visible = true


func stand_position() -> Vector3:
	if post == Formation.POST_FREE:
		return free_pos
	return castle.slot_position(side, post, slot)


## 자리 변경 명령. 목표 자리가 가득 차면 false (현재 자리 유지).
func move_to(p_side: int, p_post: int) -> bool:
	var s: int = formation.claim(index, p_side, p_post)
	if s < 0:
		return false
	side = p_side
	post = p_post
	slot = s
	_replan()
	return true


## 자유 이동 명령: 슬롯을 비우고 바닥 지점 p에 선다. 대기 방향은 가장 가까운 면의 바깥.
func move_to_point(p: Vector3) -> void:
	formation.release(index)
	post = Formation.POST_FREE
	free_pos = Vector3(p.x, 0.0, p.z)
	side = Formation.side_of(free_pos)
	_replan()


func _replan() -> void:
	if is_inside_tree():
		_path = Formation.route(castle.half, global_position, stand_position())


## 실제 높이로 판정한다 — 오르내리는 중에는 지상 취급.
func is_on_wall() -> bool:
	return global_position.y > Balance.WALL_H / 2.0


## 받는 피해: dodge → dmg_reduce → thorns(source = 때린 몬스터에게 되돌림).
func take_damage(amount: float, source = null) -> void:
	if state == State.DEAD:
		return
	var r := Skills.incoming(_sk, amount, randf())
	if r.x <= 0.0:
		DamageNumbers.pop(self, 0.0, DamageNumbers.Kind.DODGE)
		return
	hp = maxf(0.0, hp - r.x)
	DamageNumbers.pop(self, r.x, DamageNumbers.Kind.HURT)
	if r.y > 0.0 and source != null and is_instance_valid(source) and source.is_alive():
		source.take_damage(r.y, DamageNumbers.Kind.SKILL)
	if hp == 0.0:
		state = State.DEAD
		_model.play_death()
		_ring.visible = false
		_foot.visible = false


## 회복(최대 HP 상한). 실제로 오른 양.
func heal(amount: float) -> float:
	if state == State.DEAD:
		return 0.0
	var gain := minf(hp_max - hp, maxf(0.0, amount))
	hp += gain
	DamageNumbers.pop(self, gain, DamageNumbers.Kind.HEAL)
	return gain


func is_alive() -> bool:
	return state != State.DEAD


## 배정된 성문 앞·성벽 위 자리에 서 있는가(자유 위치·이동 중·추격 중이면 false).
func holds_post() -> bool:
	return post != Formation.POST_FREE and _path.is_empty() and global_position.distance_to(stand_position()) <= HOLD_EPS


## 배치에서 빠짐(main._sync_heroes): 죽은 것으로 두어 표적·오라·바에서 빠지고, 자리를 풀고, 프레임 끝에 사라진다.
## 리필 중에 빠지면(_sync_heroes가 이 영웅의 reset보다 먼저 불린다) reset이 되살리지 않게 연결을 끊고 그룹에서도 뺀다.
func retire() -> void:
	state = State.DEAD
	if GameState.refilled.is_connected(reset):
		GameState.refilled.disconnect(reset)
	remove_from_group("heroes")
	formation.release(index)
	queue_free()


func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	_atk_cd -= delta
	_tick_skills(delta)
	_tick_swing(delta)
	if not _path.is_empty():
		var wp: Vector3 = _path[0]
		state = State.MOVE
		_target = null
		_swing = null  # 이동 명령은 휘두르던 공격을 거둔다
		_model.face(wp - global_position)
		_model.play_walk()
		global_position = global_position.move_toward(wp, float(def.speed) * delta)
		if global_position.distance_to(wp) <= ARRIVE_EPS:
			_path.pop_front()
		return
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = SCAN_INTERVAL
		_target = _find_target()
	# 성벽 위 영웅은 쫓지 않는다: 스캔 사이에 사거리를 벗어난 표적은 놓는다(안 그러면 성벽 높이로 떠서 따라간다).
	if _target != null and is_instance_valid(_target) and _target.is_alive() \
			and (not is_on_wall() or Formation.flat_distance(global_position, _target.global_position) <= float(def.range)):
		var tpos: Vector3 = _target.global_position
		_model.face(tpos - global_position)
		if Formation.flat_distance(global_position, tpos) <= float(def.range):
			state = State.ATTACK
			if _sk.has("aoe_blast") and _blast_cd <= 0.0:
				_blast(tpos)
				if not _target.is_alive():
					_target = null  # 폭발이 죽인 표적은 치지 않는다(공격·쿨을 아끼고, 시체에서 투사체·연쇄가 나가지 않게)
					return
			if _atk_cd <= 0.0:
				_atk_cd = Skills.interval(_sk, float(def.atk_interval), hp_ratio())
				_attack(_atk_cd)
			return
		# 추격: 지상 영웅만 여기 온다(위 조건). 성 안팎 경계(성벽·모서리)를 넘는 걸음은 딛지 않고 표적을 놓는다(아래에서 자리로).
		var next := global_position.move_toward(Vector3(tpos.x, global_position.y, tpos.z), float(def.speed) * delta)
		if Formation.is_inside(castle.half, next) == Formation.is_inside(castle.half, global_position):
			state = State.MOVE
			_model.play_walk()
			global_position = next
			return
	_target = null
	var home := stand_position()
	if global_position.distance_to(home) > ARRIVE_EPS:
		if not is_on_wall() and Formation.route(castle.half, global_position, home).size() == 1:
			# 추격 뒤 복귀: 곧장 갈 수 있으면(같은 영역, 성 모서리를 가로지르지 않음) 곧장(도중에 새 표적을 만나면 다시 교전)
			state = State.MOVE
			_model.face(home - global_position)
			_model.play_walk()
			global_position = global_position.move_toward(home, float(def.speed) * delta)
			return
		_replan()  # 다른 영역이거나 성을 가로지르면 성문 경로로
		return
	if state != State.IDLE:
		state = State.IDLE
		_model.play_idle()
		_model.face(Formation.SIDE_DIR[side])


## 표적: 지상 영웅은 자기 자리에서 aggro 안·자리와 같은 영역(자기도 그 영역에 있을 때만), 성벽 위 영웅은 지금 위치에서 사거리 안(영역 무관). 가장 가까운 것.
## ponytail: 추격은 직선이다 — 성(모서리)을 가로질러야 닿는 표적은 포기한다(모서리 너머 괴물과는 안 싸운다). 필요하면 추격에도 route() 사용.
func _find_target():
	var on_wall := is_on_wall()
	var origin := global_position if on_wall else stand_position()
	var reach: float = float(def.range) if on_wall else float(def.aggro)
	var here_inside := Formation.is_inside(castle.half, origin)  # 지상 영웅의 영역은 자리 기준(추격 중 성벽을 넘어가도 바뀌지 않는다)
	if Formation.is_inside(castle.half, global_position) != here_inside:
		return null  # 자리 반대편(성벽 너머)에 와 있으면 아무것도 잡지 않고 성문 경로로 돌아간다 — 성벽을 가로지르는 추격 방지
	var best = null
	var best_d := INF
	for m in get_tree().get_nodes_in_group("monsters"):
		if not m.is_alive():
			continue
		if not on_wall and Formation.is_inside(castle.half, m.global_position) != here_inside:
			continue
		if Formation.flat_distance(origin, m.global_position) > reach:
			continue
		if not here_inside and Formation.crosses_castle(castle.half, global_position, m.global_position):
			continue  # 성 밖에서 직선 추격이 성(모서리)을 가로지르는 표적은 잡지 않는다
		var d := Formation.flat_distance(global_position, m.global_position)
		if d < best_d:
			best_d = d
			best = m
	return best


# --- 스킬 ---

## 쿨 스킬: heal_aura(반경 안 아군 회복), gate_repair(자기 면 성문 회복), aoe_blast 쿨 감소(발사는 교전 중에만).
func _tick_skills(delta: float) -> void:
	_blast_cd -= delta
	if _sk.has("heal_aura"):
		_heal_cd -= delta
		if _heal_cd <= 0.0:
			_heal_cd = _sk.heal_aura[0]
			_heal_aura()
	if _sk.has("gate_repair"):
		_repair_cd -= delta
		if _repair_cd <= 0.0:
			_repair_cd = _sk.gate_repair[0]
			_gate_repair()


func _heal_aura() -> void:
	var radius: float = _sk.heal_aura[1]
	var healed := false
	for h in get_tree().get_nodes_in_group("heroes"):
		if h.is_alive() and Formation.flat_distance(global_position, h.global_position) <= radius:
			healed = h.heal(h.hp_max * _sk.heal_aura[2] / 100.0) > 0.0 or healed
	if healed:
		Fx.heal_ring(get_parent(), global_position, radius)


## 자기 면 성문 앞이나 같은 면 성벽 위 자리에 서 있을 때만(이동·추격 중이면 아님). 부서진 성문은 GameState가 거른다.
func _gate_repair() -> void:
	if not holds_post():
		return
	if GameState.repair_gate(side, GameState.gate_hp_max * _sk.gate_repair[1] / 100.0) > 0.0:
		Fx.repair(get_parent(), Formation.gate_position(castle.half, side))


## 공격 시작(개정 12-2 §3): 대상을 고정하고 모션을 재생한다(간격 interval에 맞춰 빨라질 수 있다). 피해는 모션의 타격 순간(_release)에.
func _attack(interval: float) -> void:
	_attacks += 1
	_swing = _target
	_swing_left = _model.play_attack(interval)


func _tick_swing(delta: float) -> void:
	if _swing == null:
		return
	_swing_left -= delta
	if _swing_left <= 0.0:
		_release()


## 타격(발사) 순간. 공격력 = atk × 오라. 고정한 대상이 그새 죽었으면 아무 일도 없다.
## 근접: 대상이 사거리 + SWING_SLACK 안이면 친다(아니면 헛스윙). 원거리: 대상(multishot이면 사거리 안 가까운 몬스터 여럿)에게 투사체 —
## 피해는 도착 순간(_strike).
func _release() -> void:
	var m = _swing
	_swing = null
	if not is_instance_valid(m) or not m.is_alive():
		return
	var a := atk * _aura_mult()
	if role != "ranged":
		if Formation.flat_distance(global_position, m.global_position) <= float(def.range) + SWING_SLACK:
			_strike(m, a, true, _attacks)
		return
	var targets := [m]
	if _sk.has("multishot"):
		targets.append_array(_nearest_others(m, global_position, float(def.range), int(_sk.multishot[0]) - 1))
	var shot: Array = SHOTS.get(def.model, ["arrow", ARROW_SPEED])
	for i in targets.size():
		var p = ProjectileScript.new()
		p.target = targets[i]
		p.kind = shot[0]
		p.speed = shot[1]
		p.color = _color
		p.on_hit = _strike.bind(a, i == 0, _attacks)
		get_parent().add_child(p)
		p.global_position = global_position + MUZZLE


## 한 대상 타격: crit·execute·boss_slayer 배율 → 피해 → slow·poison. 첫 대상만 stun(attack_no번째 공격)·lifesteal·cleave·chain.
func _strike(m, a: float, primary: bool, attack_no: int) -> void:
	var roll := randf()
	var d := Skills.damage(_sk, a, roll, m.hp_ratio(), m.kind == "epic_boss")
	m.take_damage(d, DamageNumbers.Kind.CRIT if _sk.has("crit") and roll < _sk.crit[0] / 100.0 else DamageNumbers.Kind.HIT)
	_on_hit(m, a)
	if not primary:
		return
	if Skills.stuns(_sk, attack_no) and m.is_alive():
		m.apply_stun(_sk.stun[1])
	if _sk.has("lifesteal"):
		heal(d * _sk.lifesteal[0] / 100.0)
	if _sk.has("cleave") and role == "melee":
		for o in _nearest_others(m, m.global_position, _sk.cleave[0], 1000):
			o.take_damage(d * _sk.cleave[1] / 100.0, DamageNumbers.Kind.SKILL)
	if _sk.has("chain"):
		_chain(m, d, a)


func _on_hit(m, a: float) -> void:
	if not m.is_alive():
		return
	if _sk.has("slow"):
		m.apply_slow(_sk.slow[0], _sk.slow[1])
	if _sk.has("poison"):
		m.apply_poison(a * _sk.poison[0] / 100.0, _sk.poison[1])


## chain: 맞은 대상에서 c m 안 가장 가까운(아직 안 맞은) 몬스터로 a번, 매번 피해 × b/100.
func _chain(first, d: float, a: float) -> void:
	var hit := [first]
	var pts := [first.global_position + HIT_HEIGHT]
	var cur = first
	for dmg in Skills.chain_damages(_sk, d):
		var next = null
		for o in _nearest_others(cur, cur.global_position, _sk.chain[2], 1000):
			if not hit.has(o):
				next = o
				break
		if next == null:
			break
		hit.append(next)
		pts.append(next.global_position + HIT_HEIGHT)
		next.take_damage(dmg, DamageNumbers.Kind.SKILL)
		_on_hit(next, a)
		cur = next
	Fx.lightning(get_parent(), pts, _color)


## aoe_blast: 대상 위치 반경 안 모든 몬스터에게 공격력 × c%.
func _blast(center: Vector3) -> void:
	_blast_cd = _sk.aoe_blast[0]
	var dmg: float = atk * _aura_mult() * _sk.aoe_blast[2] / 100.0
	for m in get_tree().get_nodes_in_group("monsters"):
		if m.is_alive() and Formation.flat_distance(center, m.global_position) <= _sk.aoe_blast[1]:
			m.take_damage(dmg, DamageNumbers.Kind.SKILL)
	Fx.blast(get_parent(), center, _color, _sk.aoe_blast[1])


## from 주변 radius 안 살아 있는 몬스터(exclude 빼고) 가까운 순 최대 n마리. 지상 영웅은 자기 영역(성 안/밖)만.
func _nearest_others(exclude, from: Vector3, radius: float, n: int) -> Array:
	var out := []
	var ground := not is_on_wall()
	var here_inside := Formation.is_inside(castle.half, global_position)
	for m in get_tree().get_nodes_in_group("monsters"):
		if m == exclude or not m.is_alive() or Formation.flat_distance(from, m.global_position) > radius:
			continue
		if ground and Formation.is_inside(castle.half, m.global_position) != here_inside:
			continue
		out.append(m)
	out.sort_custom(func(p, q): return Formation.flat_distance(from, p.global_position) < Formation.flat_distance(from, q.global_position))
	return out.slice(0, n)


## atk_aura: 반경 안 다른 영웅들의 오라 중 가장 큰 것 하나.
func _aura_mult() -> float:
	var best := 0.0
	for h in get_tree().get_nodes_in_group("heroes"):
		var hs: Dictionary = h.def.skills
		if h != self and h.is_alive() and hs.has("atk_aura") \
				and Formation.flat_distance(h.global_position, global_position) <= hs.atk_aura[0]:
			best = maxf(best, hs.atk_aura[1])
	return Skills.aura_mult(best)


func hp_ratio() -> float:
	return hp / hp_max if hp_max > 0.0 else 0.0


func bar_height() -> float:
	return Art.HEAD_HEIGHT * Art.CHARACTER_SCALE


func bar_scale() -> float:
	return 1.0

extends Node3D
## 영웅. 정의(heroes.csv 한 행: 역할·능력치·스킬 둘)와 배치 슬롯 index로 만든다. 배정 자리(면 · 성문 앞/성벽 위 · 슬롯,
## 또는 자유 위치)로 성문을 거쳐 이동한다(이동 중엔 적 무시).
## 지상에서는 자리 기준 aggro 안·같은 영역(성 안/밖)의 괴물을 쫓아가 치고 자리로 돌아오며, 성벽 위에서는 움직이지 않고
## 사거리 안 괴물을 쏜다. 성벽 위에 서 있으면 근접 괴물의 표적이 되지 않는다.
## 사망 시 부활 없음, GameState.refilled에서만 배정 자리로 복귀.
## 스킬(스펙 §3.2): 수식은 Skills(순수 함수), 적용은 여기 — 공격(_attack·_release·_strike·_chain·_cleave·_blast), 쿨 스킬(_tick_skills),
## 받는 피해(take_damage). 몬스터 상태(slow·stun·poison)는 monster.gd.
## 개정 17: 쓰는 스킬은 승급으로 해금된 것만(GameData.active_skills — 스킬 2는 ★3, 3은 ★5). 쿨·확률 스킬이 터지면 머리 위 이름 띠 +
## 발밑 링 맥동(_announce, 같은 영웅은 BANNER_GAP초에 한 번). 오라를 받는 동안 발밑 주황 고리.
## 개정 18 아레나(던전): castle·formation = null로 setup하고 add_child 전에 free_pos·idle_dir을 넣는다. 성 전용 로직(자리·성문·
## 계단·영역·리필·방치 무적)은 건너뛰고 거리 제한 없이 가장 가까운 괴물과 싸운다. 기절(apply_stun)은 데스나이트 돌진.

const Balance := preload("res://scripts/balance.gd")
const GameData := preload("res://scripts/game_data.gd")
const Art := preload("res://scripts/art.gd")
const Formation := preload("res://scripts/formation.gd")
const UnitModelScript := preload("res://scripts/unit_model.gd")
const Skills := preload("res://scripts/skills.gd")
const Fx := preload("res://scripts/fx.gd")
const DamageNumbers := preload("res://scripts/damage_numbers.gd")
const ProjectileScript := preload("res://scripts/projectile.gd")
const Crowd := preload("res://scripts/crowd.gd")
const HeroSkillsScript := preload("res://scripts/hero_skills.gd")

enum State { IDLE, MOVE, ATTACK, DEAD }

const SCAN_INTERVAL := 0.2
const RETURN_DELAY := 1.5  # 교전이 끝나고 이만큼 제자리에 머문 뒤 자리로 돌아간다(그새 오는 괴물과 바로 싸운다)
const ARRIVE_EPS := 0.05
const HIT_HEIGHT := Vector3(0, 0.8, 0)
const HOLD_EPS := 0.5  # 이만큼 안이면 자기 자리를 지키고 있다(gate_repair)
const SWING_SLACK := 0.6  # 근접 타격 순간 대상이 사거리 + 이만큼 안이면 맞는다(밖이면 헛스윙)
const MUZZLE := Vector3(0, 1.3, 0)  # 투사체가 나가는 높이
## 모델 → 투사체 [모양, 속도 m/s](개정 12-2 §3). 없으면 화살.
const SHOTS := {"Mage": ["bolt", 18.0], "Barbarian": ["axe", 20.0]}
const ARROW_SPEED := 30.0
const BANNER_GAP := 1.5  # 같은 영웅의 스킬 이름 띠 최소 간격(초)
const AURA_SCAN := 0.25  # 오라 고리 표시를 다시 보는 간격(초)
const CAST_RECOVER := 0.3  # 발동 순간 뒤 이만큼 더 제자리에서 모션을 마저 한다(초) — 곧바로 평타 모션이 덮지 않게

var castle
var formation
var index: int = 0
var def: Dictionary = {}  # 영웅 정의(GameData.hero 행)
var role: String = ""
var side: int = 0
var post: int = Formation.POST_GATE
var slot: int = 0
var free_pos := Vector3.ZERO  # post == POST_FREE일 때 서는 곳
var idle_dir := Vector3.FORWARD  # 아레나 대기 방향(성에서는 면 바깥)
var _path: Array[Vector3] = []
var hp: float = 0.0
var hp_max: float = 0.0  # 레벨·승급·장비·성장 반영(refresh_stats)
var atk: float = 0.0     # 레벨·승급·장비·성장 반영(오라 전)
var state: int = State.IDLE
var selected := false:
	set(v):
		selected = v
		if _ring != null:
			_ring.visible = v and state != State.DEAD

var _sk: Dictionary = {}  # 쓰는 스킬 = def.skills 중 승급으로 해금된 것(개정 17)
var _color := Color.WHITE
var _model
var _ring: MeshInstance3D
var _foot: MeshInstance3D
var _tier := 0  # 연출 단계(Fx.tier_of 등급): 높을수록 스킬 이펙트가 크고 화려하다
var _aura_ring: MeshInstance3D  # atk_aura를 받는 중 표시
var _aura_cd := 0.0
var _banner_at := -INF  # 마지막 이름 띠 시각(초)
var _target
var _atk_cd := 0.0
var _scan_cd := 0.0
var _linger := 0.0     # 교전 뒤 제자리에 더 머물 초(0 이하 = 자리로 돌아간다)
var _attacks := 0      # 공격 횟수(stun N번째)
var _swing             # 휘두르는(쏘려는) 중인 공격의 고정 대상. null = 없음
var _swing_left := 0.0  # 타격(발사) 순간까지 남은 초
var _heal_cd := 0.0
var _repair_cd := 0.0
var _blast_cd := 0.0
var _level := 1
var _promotion := 0
var _bonus := {}  # 성장 효과(Economy.upgrade_bonus) — 치명타 굴림이 쓴다
var _aspd := 1.0  # 공격 간격 나눗수 = 1 + 성장 공격속도
var _speed := 0.0  # 이동 속도 = def.speed × (1 + 성장 이동속도 + 신발 %)
var _skill_mult := 1.0  # 스킬 피해 배율 = 1 + 연구 비전 연구 %(개정 24) — 따로 들어가는 스킬 피해(가르기·연쇄·폭발·독·가시)에 곱한다
var _stun_t := 0.0  # 기절 남은 초
var _skx  # 스킬 100종 확장(hero_skills.gd) — 새 종류의 발동·타격·처치·방어·오라
var _stun_fx: Node3D
var _cast_fn := Callable()  # 발동 모션 중인 스킬(개정 25): 모션의 발동 순간에 부른다. 비었으면 시전 중 아님
var _cast_left := 0.0  # 발동 순간까지 남은 초
var _cast_t := 0.0  # 시전 자세 남은 초(발동 순간 + CAST_RECOVER) — 이 동안 평타·추격을 쉬고 제자리에 선다(이동 명령은 예외)


## add_child 전에 호출. 기본 배치: 면 = index % 4, melee는 성문 앞, ranged는 성벽 위(차 있으면 _place_default).
## promotion = 승급 단계(개정 15), level = 영웅 레벨. 능력치는 refresh_stats.
func setup(p_index: int, p_def: Dictionary, p_castle, p_formation, promotion := 0, level := 1) -> void:
	index = p_index
	def = p_def
	castle = p_castle
	formation = p_formation
	role = def.role
	_sk = GameData.active_skills(def, promotion)
	_skx = HeroSkillsScript.new(self)
	_skx.set_skills(_sk)
	_color = Color(def.color)
	_tier = Fx.tier_of(str(def.grade))
	_level = level
	_promotion = promotion
	refresh_stats()
	_place_default()


## 기본 자리(면 index % 4의 역할 자리). 게임 중 다시 만든 영웅(배치·승급·레벨 변경)은 다른 영웅들이 옮겨 와 그 자리가 차 있을 수 있다 —
## 같은 면 다른 자리 → 다른 면들(역할 자리 먼저) → 그래도 다 차면 그 면 성문 앞 바닥(자유 위치)에 선다.
func _place_default() -> void:
	if castle == null:
		post = Formation.POST_FREE  # 아레나: 쓰는 쪽이 free_pos를 정한다
		return
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
	add_to_group("crowd")  # 겹침 해소(crowd.gd)
	_model = UnitModelScript.new()
	_model.lod = true  # 화면 밖이면 애니메이션 간헐 갱신(화면 안은 매 프레임, 그림자 늘)
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
	_aura_ring = Fx.aura_ring()
	_aura_ring.position.y = 0.03
	_aura_ring.visible = false
	add_child(_aura_ring)
	if castle != null:
		GameState.refilled.connect(reset)
	Economy.upgrades_changed.connect(refresh_stats)  # 성장·장비·연구는 곧바로(개정 20·24)
	Economy.items_changed.connect(refresh_stats)
	Economy.research_changed.connect(refresh_stats)
	Guild.buff_changed.connect(refresh_stats)  # 길드 레벨 버프
	reset()


func reset() -> void:
	hp = hp_max
	state = State.IDLE
	_target = null
	_swing = null
	_linger = 0.0
	_attacks = 0
	_cancel_cast()
	_heal_cd = _sk.heal_aura[0] if _sk.has("heal_aura") else 0.0
	_repair_cd = _sk.gate_repair[0] if _sk.has("gate_repair") else 0.0
	_blast_cd = 0.0
	_skx.reset()
	global_position = stand_position()
	_path.clear()
	_model.reset_pose()
	_model.face(Formation.SIDE_DIR[side] if castle != null else idle_dir)  # 대기 중엔 성 바깥(아레나는 적 쪽)을 본다
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


## 받는 피해: dodge → dmg_reduce → thorns(source = 때린 몬스터에게 되돌림). 방치 모드는 무적(개정 12): 숫자·가시 없이 0.
func take_damage(amount: float, source = null) -> void:
	if state == State.DEAD or (castle != null and GameState.mode == GameState.Mode.IDLE):
		return
	amount = _skx.incoming(amount)  # 금강불괴·광전사·수호의 오라·요새화·돌 피부·방패 막기·보호막
	if amount <= 0.0:
		return
	var r := Skills.incoming(_sk, amount, randf())
	if r.x <= 0.0:
		DamageNumbers.pop(self, 0.0, DamageNumbers.Kind.DODGE)
		return
	hp = maxf(0.0, hp - r.x)
	DamageNumbers.pop(self, r.x, DamageNumbers.Kind.HURT)
	if r.y > 0.0 and source != null and is_instance_valid(source) and source.is_alive():
		source.take_damage(r.y * _skill_mult, DamageNumbers.Kind.SKILL)
	if hp == 0.0 and _skx.try_revive():  # 불굴: 쓰러지는 대신 다시 일어난다
		return
	if hp == 0.0:
		state = State.DEAD
		_cancel_cast()
		_model.play_death()
		_ring.visible = false
		_foot.visible = false
		_aura_ring.visible = false
		return
	_skx.after_hurt(source)  # 반격·재기·금강불괴


## 되살아남(부활의 기도): 쓰러진 영웅이 최대 HP의 pct%로 그 자리에서 일어난다.
func revive(pct: float) -> void:
	if state != State.DEAD or not is_inside_tree():
		return
	state = State.IDLE
	hp = maxf(1.0, hp_max * pct / 100.0)
	_model.reset_pose()
	_foot.visible = true
	_ring.visible = selected
	Fx.revive(self)


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


## 기절(개정 18): sec초 이동·공격 정지(남은 시간보다 길 때만 늘린다). 머리 위 별은 끝날 때까지.
func apply_stun(sec: float) -> void:
	if state == State.DEAD:
		return
	_stun_t = maxf(_stun_t, sec)
	_swing = null
	_cancel_cast()  # 기절은 시전을 끊는다(스킬은 쿨만 돈다)
	if not is_instance_valid(_stun_fx):
		_stun_fx = Fx.stun(self, bar_height() + 0.3)


func is_stunned() -> bool:
	return _stun_t > 0.0


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
	remove_from_group("crowd")
	formation.release(index)
	queue_free()


func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	if _stun_t > 0.0:  # 기절(개정 18)
		_stun_t -= delta
		if _stun_t <= 0.0 and is_instance_valid(_stun_fx):
			_stun_fx.queue_free()
		return
	_atk_cd -= delta
	_tick_skills(delta)
	_tick_swing(delta)
	_tick_cast(delta)
	if not _path.is_empty():
		var wp: Vector3 = _path[0]
		state = State.MOVE
		_target = null
		_swing = null  # 이동 명령은 휘두르던 공격을 거둔다
		_linger = 0.0
		_model.face(wp - global_position)
		_model.play_walk()
		global_position = global_position.move_toward(wp, _speed * delta)
		if global_position.distance_to(wp) <= Crowd.arrive_r(_path, ARRIVE_EPS):
			_path.pop_front()
		return
	if _cast_t > 0.0:  # 시전 자세: 제자리에서 표적을 보며 모션을 마친다(평타·추격·복귀 없음)
		if _target != null and is_instance_valid(_target) and _target.is_alive():
			_model.face(_target.global_position - global_position)
		return
	_scan_cd -= delta
	# 표적이 죽거나 사라지면 다음 스캔을 기다리지 않고 이 프레임에 다시 찾는다(기다리는 동안 자리 쪽으로 물러나지 않게).
	# 휘두르는 중인 사거리 안 표적은 스캔이 놓쳐도(aggro 경계 등) 그대로 둔다.
	var lost: bool = _target != null and not (is_instance_valid(_target) and _target.is_alive())
	if _scan_cd <= 0.0 or lost:
		_scan_cd = SCAN_INTERVAL
		if not _swinging_at(_target):
			_target = _find_target()
	# 성벽 위 영웅은 쫓지 않는다: 스캔 사이에 사거리를 벗어난 표적은 놓는다(안 그러면 성벽 높이로 떠서 따라간다).
	if _target != null and is_instance_valid(_target) and _target.is_alive() \
			and (not is_on_wall() or Formation.flat_distance(global_position, _target.global_position) <= float(def.range)):
		_linger = RETURN_DELAY
		var tpos: Vector3 = _target.global_position
		_model.face(tpos - global_position)
		if Formation.flat_distance(global_position, tpos) <= float(def.range):
			state = State.ATTACK
			if _sk.has("aoe_blast") and _blast_cd <= 0.0 and _swing == null:
				_blast_cd = _sk.aoe_blast[0]
				begin_cast(HeroSkillsScript.cast_anim("aoe_blast", def), _cast_blast.bind(_target))  # 모션의 발동 순간에 터진다
				return
			if _atk_cd <= 0.0:
				_atk_cd = Skills.interval(_sk, float(def.atk_interval) / _aspd, hp_ratio()) / _skx.speed_mult()
				_attack(_atk_cd)
			return
		# 추격: 지상 영웅만 여기 온다(위 조건). 성 안팎 경계(성벽·모서리)를 넘는 걸음은 딛지 않고 표적을 놓는다(아래에서 자리로).
		var next := global_position.move_toward(Vector3(tpos.x, global_position.y, tpos.z), _speed * delta)
		if castle == null or Formation.is_inside(castle.half, next) == Formation.is_inside(castle.half, global_position):
			state = State.MOVE
			_model.play_walk()
			global_position = next
			return
	_target = null
	_linger -= delta
	var home := stand_position()
	if global_position.distance_to(home) > ARRIVE_EPS:
		if _linger > 0.0:
			# 교전 뒤 잠시 제자리(스캔은 계속): 곧장 돌아서면 다음 괴물이 올 때마다 공격 → 뒷걸음 → 앞걸음을 되풀이한다
			if state == State.MOVE:
				_model.play_idle()  # 공격 모션은 끝날 때 스스로 대기로 돌아간다
			state = State.IDLE
			return
		if not is_on_wall() and (castle == null or Formation.route(castle.half, global_position, home).size() == 1):
			# 추격 뒤 복귀: 곧장 갈 수 있으면(같은 영역, 성 모서리를 가로지르지 않음) 곧장(도중에 새 표적을 만나면 다시 교전)
			state = State.MOVE
			_model.face(home - global_position)
			_model.play_walk()
			global_position = global_position.move_toward(home, _speed * delta)
			return
		_replan()  # 다른 영역이거나 성을 가로지르면 성문 경로로
		return
	if state != State.IDLE:
		state = State.IDLE
		_model.play_idle()
		_model.face(Formation.SIDE_DIR[side] if castle != null else idle_dir)


## 표적: 지상 영웅은 자기 자리에서 aggro 안·자리와 같은 영역(자기도 그 영역에 있을 때만), 성벽 위 영웅은 지금 위치에서 사거리 안(영역 무관). 가장 가까운 것.
## ponytail: 추격은 직선이다 — 성(모서리)을 가로질러야 닿는 표적은 포기한다(모서리 너머 괴물과는 안 싸운다). 필요하면 추격에도 route() 사용.
func _find_target():
	if castle == null:  # 아레나: 거리·영역 제한 없이 가장 가까운 괴물
		var near := _nearest_others(null, global_position, INF, 1)
		return near[0] if not near.is_empty() else null
	var on_wall := is_on_wall()
	var origin := global_position if on_wall else stand_position()
	var reach: float = float(def.range) if on_wall else float(def.aggro)
	var here_inside := Formation.is_inside(castle.half, origin)  # 지상 영웅의 영역은 자리 기준(추격 중 성벽을 넘어가도 바뀌지 않는다)
	if Formation.is_inside(castle.half, global_position) != here_inside:
		return null  # 자리 반대편(성벽 너머)에 와 있으면 아무것도 잡지 않고 성문 경로로 돌아간다 — 성벽을 가로지르는 추격 방지
	var best = null
	var best_d := INF
	var here := global_position
	for m in get_tree().get_nodes_in_group("monsters"):
		var mp: Vector3 = m.global_position
		if Vector2(mp.x - origin.x, mp.z - origin.z).length() > reach or not m.is_alive():  # 거리 먼저(= flat_distance)
			continue
		if not on_wall and Formation.is_inside(castle.half, mp) != here_inside:
			continue
		if not here_inside and Formation.crosses_castle(castle.half, here, mp):
			continue  # 성 밖에서 직선 추격이 성(모서리)을 가로지르는 표적은 잡지 않는다
		var d := Formation.flat_distance(here, mp)
		if d < best_d:
			best_d = d
			best = m
	return best


## m을 휘두르는(쏘려는) 중이고 m이 살아서 사거리 안인가 — 그 사이 스캔이 표적을 바꾸거나 놓지 않는다.
func _swinging_at(m) -> bool:
	return m != null and _swing == m and is_instance_valid(m) and m.is_alive() \
		and Formation.flat_distance(global_position, m.global_position) <= float(def.range)


# --- 스킬 ---

## 쿨 스킬: heal_aura(반경 안 아군 회복), gate_repair(자기 면 성문 회복), aoe_blast 쿨 감소(발사는 교전 중에만).
func _tick_skills(delta: float) -> void:
	_skx.tick(delta)
	_blast_cd -= delta
	_aura_cd -= delta
	if _aura_cd <= 0.0:
		_aura_cd = AURA_SCAN
		_aura_ring.visible = _aura_mult() > 1.0
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
		if h.is_alive() and Formation.flat_distance(global_position, h.global_position) <= radius \
				and h.heal(h.hp_max * _sk.heal_aura[2] / 100.0) > 0.0:
			healed = true
			Fx.heal_cross(h)
	if healed:
		Fx.heal_ring(get_parent(), global_position, radius, _tier)
		_announce("heal_aura")


## 자기 면 성문 앞이나 같은 면 성벽 위 자리에 서 있을 때만(이동·추격 중이면 아님). 부서진 성문은 GameState가 거른다.
func _gate_repair() -> void:
	if not holds_post():
		return
	if GameState.repair_gate(side, GameState.gate_hp_max * _sk.gate_repair[1] / 100.0) > 0.0:
		Fx.repair(get_parent(), Formation.gate_position(castle.half, side), _tier)
		_announce("gate_repair")


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
		p.tail = _sk.has("multishot")
		p.on_hit = _strike.bind(a, i == 0, _attacks)
		get_parent().add_child(p)
		p.global_position = global_position + MUZZLE


## 한 대상 타격: crit·execute·boss_slayer 배율 → 피해 → slow·poison. 첫 대상만 stun(attack_no번째 공격)·lifesteal·cleave·chain.
## 연출(개정 17): crit = 큰 별 불꽃, execute·boss_slayer = 붉은 X, crit·execute·stun = 이름 띠. stun = 노란 불꽃·파동, cleave = 초승달 궤적
## (등급 단계 _tier만큼 크고 겹이 많다).
func _strike(m, a: float, primary: bool, attack_no: int) -> void:
	var ratio: float = m.hp_ratio()
	var boss: bool = m.is_boss  # 성 대보스·왕고블린·데스나이트(monster.is_boss)
	# 치명타(개정 20 §3): 스킬 확률·배율 + 성장을 합쳐(crit_roll_params) 한 번만 굴린다. Skills.damage엔 빗나가는 굴림 1.0 — 두 번 세지 않게
	var has_crit := _sk.has("crit")
	var cp := GameData.crit_roll_params(_sk.crit[0] / 100.0 if has_crit else 0.0, _sk.crit[1] / 100.0 if has_crit else 0.0, _bonus)
	var crit: bool = randf() < cp.rate
	var was := HeroSkillsScript.snap(m)  # 처치 효과가 볼 상태(죽으면 지워진다)
	var d: float = Skills.damage(_sk, a, 1.0, ratio, boss) * (float(cp.mult) if crit else 1.0) * _skx.damage_mult(m, attack_no, primary)
	var execute: bool = _sk.has("execute") and ratio <= _sk.execute[0] / 100.0
	var at: Vector3 = m.global_position + HIT_HEIGHT
	m.take_damage(d, DamageNumbers.Kind.CRIT if crit else DamageNumbers.Kind.HIT)
	if crit:
		Fx.spark(get_parent(), at, Fx.CRIT_ORANGE, 1.0)
		if has_crit:
			_announce("crit")  # 이름 띠는 치명타 스킬만(성장 기본 치명타는 숫자·불꽃만)
	if execute or (boss and _sk.has("boss_slayer")):
		Fx.slash(get_parent(), at, _tier)
		if execute:
			_announce("execute")
	_on_hit(m, a)
	_skx.on_hit(m, d, primary, attack_no, was)  # 새 타격·처치 효과(화상·빙결·관통·도탄 …)
	if not primary:
		return
	if Skills.stuns(_sk, attack_no) and m.is_alive():
		m.apply_stun(_sk.stun[1])
		Fx.stun_hit(get_parent(), at, _tier)
		_announce("stun")
	if _sk.has("lifesteal"):
		heal(d * _sk.lifesteal[0] / 100.0)
	if _sk.has("cleave") and role == "melee":
		Fx.cleave(get_parent(), m.global_position, _color, _sk.cleave[0], _tier)
		for o in _nearest_others(m, m.global_position, _sk.cleave[0], 1000):
			o.take_damage(d * _sk.cleave[1] / 100.0 * _skill_mult, DamageNumbers.Kind.SKILL)
	if _sk.has("chain"):
		_chain(m, d, a)


func _on_hit(m, a: float) -> void:
	if not m.is_alive():
		return
	if _sk.has("slow"):
		m.apply_slow(_sk.slow[0], _sk.slow[1])
	if _sk.has("poison"):
		m.apply_poison(a * _sk.poison[0] / 100.0 * _skill_mult, _sk.poison[1])


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
		next.take_damage(dmg * _skill_mult, DamageNumbers.Kind.SKILL)
		_on_hit(next, a)
		cur = next
	Fx.lightning(get_parent(), pts, _color, _tier)


## aoe_blast 발동 순간(개정 25): 모션을 시작할 때의 표적이 살아 있으면 그 자리, 아니면 지금 표적 자리에 터뜨린다(둘 다 없으면 헛 시전).
## 폭발이 죽인 표적은 놓는다(시체에 평타·투사체·연쇄가 나가지 않게).
func _cast_blast(m) -> void:
	if not (m != null and is_instance_valid(m) and m.is_alive()):
		m = _target
	if m == null or not is_instance_valid(m) or not m.is_alive():
		return
	_blast(m.global_position)
	if not m.is_alive() and _target == m:
		_target = null


## 발동 모션(개정 25): anim을 재생하고 기 모으기(Fx.charge)를 띄운 뒤, 모션의 발동 순간에 fn을 부른다. 그동안(+CAST_RECOVER) 평타·추격을 쉰다.
## 이미 시전 중이거나 평타를 휘두르는 중이거나 기절·쓰러짐이면 시작하지 않고 false — 쓰는 쪽이 곧 다시 본다.
func begin_cast(anim: String, fn: Callable) -> bool:
	if _cast_fn.is_valid() or _swing != null or state == State.DEAD or is_stunned() or not is_inside_tree():
		return false
	var wind: float = _model.play_cast(anim)
	_cast_fn = fn
	_cast_left = wind
	_cast_t = wind + CAST_RECOVER
	Fx.charge(self, _color, _tier, wind)
	return true


func is_casting() -> bool:
	return _cast_fn.is_valid()


func _tick_cast(delta: float) -> void:
	_cast_t -= delta
	if not _cast_fn.is_valid():
		return
	_cast_left -= delta
	if _cast_left <= 0.0:
		var fn := _cast_fn
		_cast_fn = Callable()
		fn.call()


## 시전을 거둔다(기절·쓰러짐·리필): 발동하지 않고, 기 모으기 이펙트도 지운다.
func _cancel_cast() -> void:
	if not _cast_fn.is_valid() and _cast_t <= 0.0:
		return
	_cast_fn = Callable()
	_cast_t = 0.0
	for c in get_children():
		if c.has_meta("fx") and str(c.get_meta("fx")).begins_with("charge"):
			c.queue_free()


## aoe_blast: 대상 위치 반경 안 모든 몬스터에게 공격력 × c%.
func _blast(center: Vector3) -> void:
	_blast_cd = _sk.aoe_blast[0]
	var dmg: float = atk * _aura_mult() * _skx.atk_mult() * _sk.aoe_blast[2] / 100.0 * _skill_mult
	for m in get_tree().get_nodes_in_group("monsters"):
		if m.is_alive() and Formation.flat_distance(center, m.global_position) <= _sk.aoe_blast[1]:
			m.take_damage(dmg, DamageNumbers.Kind.SKILL)
	Fx.blast(get_parent(), center, _color, _sk.aoe_blast[1], def.grade == "SSR" and GameData.fx_shake(), _tier)  # SSR이면 카메라를 약하게 흔든다
	_announce("aoe_blast")


## from 주변 radius 안 살아 있는 몬스터(exclude 빼고) 가까운 순 최대 n마리. 지상 영웅은 자기 영역(성 안/밖)만.
func _nearest_others(exclude, from: Vector3, radius: float, n: int) -> Array:
	var out := []
	var ground := not is_on_wall() and castle != null  # 아레나는 영역이 없다
	var here_inside := ground and Formation.is_inside(castle.half, global_position)
	for m in get_tree().get_nodes_in_group("monsters"):
		if m == exclude or not m.is_alive() or Formation.flat_distance(from, m.global_position) > radius:
			continue
		if ground and Formation.is_inside(castle.half, m.global_position) != here_inside:
			continue
		out.append(m)
	out.sort_custom(func(p, q): return Formation.flat_distance(from, p.global_position) < Formation.flat_distance(from, q.global_position))
	return out.slice(0, n)


## 스킬 발동 표시(개정 17 §3): 머리 위 이름 띠(고유 색, 0.8초) + 발밑 링 맥동. 같은 영웅은 BANNER_GAP초에 한 번.
func _announce(kind: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _banner_at < BANNER_GAP or not is_inside_tree():
		return
	_banner_at = now
	DamageNumbers.banner(self, Skills.name_of(kind, def.id) + "!", _color)
	Fx.pulse(self, _foot, _color, _tier)
	if _tier >= 2 and GameData.fx_shake():  # SSR 발동: 화면이 잠깐 당겨진다(아트 방향 §4, 흔들림 설정을 따른다)
		var cam := get_viewport().get_camera_3d()
		if cam != null and cam.get_parent().has_method("punch") and _on_screen(cam):
			cam.get_parent().punch()


## 화면 안에 보이는가(머리 높이 지점이 뷰포트 안).
func _on_screen(cam: Camera3D) -> bool:
	return get_viewport().get_visible_rect().has_point(cam.unproject_position(global_position + HIT_HEIGHT))


## atk_aura: 반경 안 다른 영웅들의 오라(해금된 것만) 중 가장 큰 것 하나.
func _aura_mult() -> float:
	var best := 0.0
	for h in get_tree().get_nodes_in_group("heroes"):
		var hs: Dictionary = h._sk
		if h != self and h.is_alive() and hs.has("atk_aura") \
				and Formation.flat_distance(h.global_position, global_position) <= hs.atk_aura[0]:
			best = maxf(best, hs.atk_aura[1])
	return Skills.aura_mult(best)


## 최종 능력치를 다시 읽는 한 곳(개정 20): HP·공격 = hero_stats(기본 × 레벨 × 승급 + 장비) × (1 + 성장 %) × (1 + 연구 %, 개정 24),
## × (1 + 길드 버프 %), 공격 간격 ÷ (1 + 성장 공격속도), 이동 × (1 + 성장 이동속도 + 신발 %), 스킬 피해 × (1 + 연구 비전 %). 성장·장비·연구·길드가 바뀌면 곧바로 —
## HP 비율 유지, 다음 공격부터 새 간격.
func refresh_stats() -> void:
	_bonus = Economy.upgrade_bonus()
	var r: Dictionary = Economy.research_bonus()
	var ratio := hp_ratio() if hp_max > 0.0 else 1.0
	var st := GameData.hero_stats(def, _level, _promotion)
	var g: float = 1.0 + Guild.buff_pct() / 100.0
	hp_max = st.hp * (1.0 + _bonus.hp_pct) * (1.0 + r.hero_hp_pct / 100.0) * g
	atk = st.atk * (1.0 + _bonus.atk_pct) * (1.0 + r.hero_atk_pct / 100.0) * g
	_skill_mult = 1.0 + r.skill_pct / 100.0
	hp = hp_max * ratio
	_aspd = 1.0 + _bonus.aspd_pct
	var shoes: float = Economy.equipment_bonus(str(def.get("id", ""))).get("speed_pct", 0.0)
	_speed = float(def.speed) * (1.0 + _bonus.mspd_pct + shoes / 100.0)


func hp_ratio() -> float:
	return hp / hp_max if hp_max > 0.0 else 0.0


## 겹침 해소(crowd.gd): 몸 반지름, 밀리는 무게(걷는 중이 아니면 — 자리를 지키거나 싸우는 중 — 무겁다).
func radius() -> float:
	return Crowd.HUMAN_R * Art.CHARACTER_SCALE


func push_mass() -> float:
	return Crowd.mass(radius(), state != State.MOVE)


func bar_height() -> float:
	return Art.HEAD_HEIGHT * Art.CHARACTER_SCALE


func bar_scale() -> float:
	return 1.0

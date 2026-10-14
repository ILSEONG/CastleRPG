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

const Lang := preload("res://scripts/lang.gd")

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
const Sfx := preload("res://scripts/sfx.gd")

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
const BANNER_GAP := 1.5  # 같은 영웅의 스킬 이름 띠(또는 확률 패시브 그림) 최소 간격(초)
const NAMED_PASSIVES := ["revive", "invincible", "second_wind"]  # 한 판에 한 번쯤 터지는 패시브 — 확률 패시브와 달리 이름 띠
const AURA_SCAN := 0.25  # 오라 고리 표시를 다시 보는 간격(초)
const CAST_RECOVER := 0.3  # 발동 순간 뒤 이만큼 더 제자리에서 모션을 마저 한다(초) — 곧바로 평타 모션이 덮지 않게
const ARENA_PAD := 0.2  # 던전·드래곤 아레나: 영웅끼리 몸 둘레 여유(m, ally_pad) — 둘 합 1.3 m 떨어져 선다
const KEEP_SLOT_R := 1.5  # 같은 성문·성벽을 거듭 누를 때 지금 자리에서 이만큼 안을 누르면 자리를 바꾸지 않는다(2026-10-14 우왕좌왕)
const KEEP_ROUTE_SLACK := 4.0  # 지금 경로의 도착지만 바꾼 길이 새로 짠 길보다 이만큼(m) 안쪽으로만 길면 지금 경로를 지킨다
const ON_LINE_R := 0.6  # 새 경로 첫 구간 선에서 이만큼 안이고 그 구간 가운데에 있으면 첫 점은 이미 지나쳤다
const FOCUS_REPLAN := 0.5  # 공격 명령: 걷는 중 표적을 다시 보는 간격(초)
const FOCUS_DRIFT := 1.5  # 공격 명령: 표적이 경로 끝에서 이만큼 움직였으면 경로를 다시 짠다

var castle
var formation
var index: int = 0
var def: Dictionary = {}  # 영웅 정의(GameData.hero 행)
var role: String = ""
var side: int = 0
var post: int = Formation.POST_GATE
var slot: int = 0
var free_pos := Vector3.ZERO  # post == POST_FREE일 때 서는 곳
var hold := false  # 아레나: 이동 명령을 받았다 — 표적은 free_pos에서 aggro 안(성 영웅처럼). false면 거리 제한 없이 가장 가까운 적
var idle_dir := Vector3.FORWARD  # 아레나 대기 방향(성에서는 면 바깥)
var allies := "heroes"  # 아군 그룹(회복·오라·부활 대상). 공성전 수비 영웅은 "war_def"(war_hero.gd)
var foes := "monsters"  # 적 그룹(표적·스킬 피해 대상). 공성전 수비 영웅은 "heroes"
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
var _banner_kind := ""  # 마지막 이름 띠 스킬(궁극기가 같은 스킬 간격까지 건너뛰지 않게)
var _proc_at := -INF  # 마지막 확률 패시브 그림 시각(초)
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
var helper := false  # 모집권 던전 도우미(내 영웅이 아님): 내 장비를 끼지 않는다 — setup 전에 켠다
var helper_tag := Lang.t("hero.helper_tag")  # HUD 얼굴 위 꼬리표(친구 영웅이면 "친구")
var _bonus := {}  # 성장 효과(Economy.upgrade_bonus) — 치명타 굴림이 쓴다
var _aspd := 1.0  # 공격 간격 나눗수 = 1 + 성장 공격속도
var _speed := 0.0  # 이동 속도 = def.speed × (1 + 성장 이동속도 + 신발 %)
var _gear_lifesteal := 0.0  # 장비 특수 능력치(2026-10-07): 평타 피해의 흡혈 비율
var _gear_dmg_reduce := 0.0  # 장비 특수 능력치: 받는 피해 감소 비율(상한 GameData.DMG_REDUCE_CAP)
var _skill_mult := 1.0  # 스킬 피해 배율 = 1 + 연구 비전 연구 %(개정 24) — 따로 들어가는 스킬 피해(가르기·연쇄·폭발·독·가시)에 곱한다
var _stun_t := 0.0  # 기절 남은 초
var _skx  # 스킬 100종 확장(hero_skills.gd) — 새 종류의 발동·타격·처치·방어·오라
var _stun_fx: Node3D
var _cast_fn := Callable()  # 발동 모션 중인 스킬(개정 25): 모션의 발동 순간에 부른다. 비었으면 시전 중 아님
var _cast_left := 0.0  # 발동 순간까지 남은 초
var _cast_style := "attack"  # 발동 순간 연출 종류(hero_skills.cast_style, 2026-10-13)
var _focus  # 공격 명령 표적(2026-10-14, unit_picker): 쓰러지거나 새 명령이 올 때까지 이것만 쫓아가 친다
var _focus_cd := 0.0  # 걷는 중 표적을 다시 볼 때까지 남은 초
var _focus_moved := false  # 표적을 쫓느라 자리를 떠났다 — 쓰러뜨린 곳에 선다
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
	add_to_group(allies)
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
	_focus = null
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


## 하단 초상화 쿨 칸(사용자 2026-10-06): 정의의 액티브 스킬을 칸 순서대로(잠긴 것 포함) → [{kind, locked, total, left}].
## left = 다음 발동까지 남은 초(0..total). 영웅마다 액티브 수가 달라(R은 하나) 칸 수는 표에서 읽는다.
func active_slots() -> Array:
	var out := []
	var skills: Dictionary = def.get("skills", {})
	for k in skills:
		if not HeroSkillsScript.is_active(k):
			continue
		var total := float(skills[k][0])
		var locked := not _sk.has(k)
		var left := 0.0
		if not locked:
			match k:
				"heal_aura":
					left = _heal_cd
				"gate_repair":
					left = _repair_cd
				"aoe_blast":
					left = _blast_cd
				_:
					left = _skx.cd_left(k)
		out.append({"kind": k, "locked": locked, "total": total, "left": clampf(left, 0.0, total)})
	return out


func stand_position() -> Vector3:
	if post == Formation.POST_FREE:
		return free_pos
	return castle.slot_position(side, post, slot)


## 자리 변경 명령. 목표 자리가 가득 차면 false (현재 자리 유지).
## near(성문 중앙 기준 옆 거리)를 주면 그 지점에 가장 가까운 빈 슬롯 — 같은 자리 안에서도 옮긴다(성벽 위 좌↔우).
func move_to(p_side: int, p_post: int, near := NAN) -> bool:
	if p_side == side and p_post == post and not is_nan(near) and int(formation.assignment(index).get("slot", -1)) == slot \
			and absf(Formation.perp(side).dot(stand_position()) - near) <= KEEP_SLOT_R:
		_focus = null
		_replan_stable()  # 같은 자리 근처를 다시 눌렀다: 자리는 그대로(옆 자리로 오가지 않게)
		return true
	var s: int = formation.claim(index, p_side, p_post) if is_nan(near) else formation.claim_near(index, p_side, p_post, near)
	if s < 0:
		return false
	side = p_side
	post = p_post
	slot = s
	_focus = null
	_replan_stable()
	return true


## 자유 이동 명령: 슬롯을 비우고 바닥 지점 p에 선다. 대기 방향은 가장 가까운 면의 바깥.
## 아레나(던전)에서는 그 뒤로 그 지점에서 aggro 안의 적만 노린다(hold) — 안 그러면 도착하자마자 가장 가까운 적에게 다시 달려간다.
func move_to_point(p: Vector3) -> void:
	_focus = null
	_set_free(p)
	_replan_stable()


## 자유 위치 p에 서게 한다(경로는 쓰는 쪽이). 슬롯을 비운다.
func _set_free(p: Vector3) -> void:
	if formation != null:
		formation.release(index)
	post = Formation.POST_FREE
	free_pos = Vector3(p.x, 0.0, p.z)
	if castle != null:
		side = Formation.side_of(free_pos)
	else:
		hold = true


## 플레이어 명령의 경로(사용자 2026-10-14 "이동하려는 쪽을 계속 누르면 루트가 시시각각 바뀌며 우왕좌왕"):
## (1) 지금 걷는 경로의 도착지만 새 자리로 바꾼 길(마지막 구간을 곧장 갈 수 있을 때)이 새로 짠 길보다 KEEP_ROUTE_SLACK 넘게 길지 않으면
##     그 길을 쓴다 — 성 모서리 근처를 거듭 누를 때 지나는 성문이 이쪽저쪽으로 바뀌지 않는다.
## (2) 아니면 새로 짠 길에서 이미 지나친 앞 점(성문 통과 지점 등 — 지나가는 반경 안에서 떼어 냈다)을 뺀다 — 왔던 쪽으로 돌아서지 않는다.
func _replan_stable() -> void:
	if not is_inside_tree():
		return
	var old: Array[Vector3] = _path.duplicate()
	_replan()
	if _path.is_empty():
		return
	var dest: Vector3 = _path[_path.size() - 1]
	if old.size() >= 2 and Crowd.level(global_position.y) != -1:
		var keep: Array[Vector3] = old.slice(0, old.size() - 1)
		var leg := _route_between(keep[keep.size() - 1], dest)
		keep.append(dest)
		if leg.size() == 1 and Formation.path_length(global_position, keep) <= Formation.path_length(global_position, _path) + KEEP_ROUTE_SLACK:
			_path = keep
			return
	_path = _skip_passed(_path)


## from → to 경로(도착점 포함). 성은 성문·계단(Formation.route), 아레나는 곧장. 공성전(war_hero)이 덮어쓴다.
func _route_between(from: Vector3, to: Vector3) -> Array[Vector3]:
	if castle == null:
		var out: Array[Vector3] = [to]
		return out
	return Formation.route(castle.half, from, to)


## 지금 위치 → to 경로.
func _route_to(to: Vector3) -> Array[Vector3]:
	return _route_between(global_position, to)


## 경로 앞 점 중 이미 지나친 것(영웅이 그 점 → 다음 점 구간 위, 가운데에 있다)을 뺀다. 높이가 바뀌는 점(계단)은 빼지 않는다.
func _skip_passed(p: Array[Vector3]) -> Array[Vector3]:
	var here := global_position
	while p.size() >= 2:
		var a: Vector3 = p[0]
		var b: Vector3 = p[1]
		if absf(a.y - here.y) > 0.05 or absf(b.y - a.y) > 0.05:
			break
		var ab := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var ah := Vector3(here.x - a.x, 0.0, here.z - a.z)
		var len2 := ab.length_squared()
		if len2 < 0.0001:
			break
		var t := ab.dot(ah) / len2
		if t <= 0.0 or t >= 1.0 or (ah - ab * t).length() > ON_LINE_R:
			break
		p.pop_front()
	return p


# --- 공격 명령(사용자 2026-10-14 "영웅으로 적 유닛 클릭하면 타겟팅") ---

## 영웅을 고른 채 적을 누르면(unit_picker): 그 적에게 가서 쓰러질 때까지 그것만 친다(새 이동·공격 명령이 오면 그만).
## 지금 자리에서 닿으면(성벽 위 원거리 등) 자리를 지키며 치고, 아니면 자리를 떠나 쫓아가 쓰러뜨린 곳에 선다(자유 위치).
## 같은 적을 거듭 눌러도 아무것도 바꾸지 않는다(빠른 연타).
func attack_unit(m) -> void:
	if m == null or not is_instance_valid(m) or not m.is_alive() or m == _focus or state == State.DEAD:
		return
	_focus = m
	_focus_moved = false
	_focus_cd = 0.0
	_target = m
	_linger = 0.0
	if _swing != null and _swing != m:
		_swing = null  # 다른 적을 휘두르던 공격은 거둔다 — 곧바로 새 표적으로


## 지금 쫓는 공격 명령 표적(없으면 null).
func focus_target():
	return _focus if _focus_ok() else null


func _focus_ok() -> bool:
	return _focus != null and is_instance_valid(_focus) and _focus.is_inside_tree() and _focus.is_alive()


## 표적이 쓰러졌다(사라졌다): 쫓느라 자리를 떠났으면 지금 선 곳을 자리로 삼는다(되돌아 걷지 않는다).
func _end_focus() -> void:
	_focus = null
	if _focus_moved and Crowd.level(global_position.y) == 0:
		_set_free(global_position)
		_path.clear()
	_focus_moved = false


## 표적 쪽으로 걸어갈 바닥 지점. 공성전은 성벽 몸·성채를 피한 자리(war_hero).
func _focus_dest(fp: Vector3) -> Vector3:
	return Vector3(fp.x, 0.0, fp.z)


func _can_hit(fp: Vector3) -> bool:
	return Formation.flat_distance(global_position, fp) <= _reach(_focus) and sees(global_position, fp)


## 바닥에서 표적까지 곧장 쫓을 수 있나(같은 영역, 성문·계단·성채를 돌 일 없음).
func _straight_to(fp: Vector3) -> bool:
	return not is_on_wall() and Crowd.level(global_position.y) == 0 and _route_to(_focus_dest(fp)).size() == 1


## 표적 쪽 경로를 짠다(성문·계단을 거쳐서). 자리를 떠난다.
func _go_focus(fp: Vector3) -> void:
	var dest := _focus_dest(fp)
	_set_free(dest)
	_focus_moved = true
	_path = _skip_passed(_route_to(dest))


## 걷는 중 표적 확인: 닿거나 곧장 쫓을 수 있으면 걷기를 멈추고(계단 중간은 마저), 표적이 경로 끝에서 멀어졌으면 다시 짠다.
func _focus_walk() -> void:
	if not _focus_ok():
		_end_focus()
		return
	if Crowd.level(global_position.y) == -1:
		return
	var fp: Vector3 = _focus.global_position
	if _can_hit(fp) or _straight_to(fp):
		_path.clear()
		return
	if Formation.flat_distance(_path[_path.size() - 1], _focus_dest(fp)) > FOCUS_DRIFT:
		_go_focus(fp)


func _replan() -> void:
	if not is_inside_tree():
		return
	if castle == null:
		_path = [stand_position()]  # 아레나: 곧장
		_target = null
		return
	_path = Formation.route(castle.half, global_position, stand_position())


## 실제 높이로 판정한다 — 오르내리는 중에는 지상 취급.
## 자리로 돌아가려면 경로(성문·계단)가 필요한가 — 아레나 영웅은 곧장(공성 영웅 war_hero가 덮어쓴다).
## 추격 한 걸음 next를 디딜 수 있나: 성 모드는 성 안팎이 바뀌지 않고 성벽 몸(성문 통로 밖)으로 들어가지 않을 때. 아레나는 언제나.
func _can_step(next: Vector3) -> bool:
	if castle == null:
		return true
	return Formation.is_inside(castle.half, next) == Formation.is_inside(castle.half, global_position) \
		and (Formation.in_wall_body(castle.half, global_position) or not Formation.in_wall_body(castle.half, next))


## 곧장 쫓다 막혔을 때 돌아가는 길을 짤 수 있으면 짠다(공성전). 기본은 없음 — 표적을 놓는다.
func _detour(_tpos: Vector3) -> bool:
	return false


## 막힌 걸음은 한 축으로 미끄러진다(성벽 면·성문 기둥을 따라 — 표적이 성문 통로에 있어도 비스듬히 막혀 서 있지 않게). 다 막히면 제자리.
func _slide(next: Vector3) -> Vector3:
	if _can_step(next):
		return next
	var here := global_position
	var sx := Vector3(next.x, next.y, here.z)
	if absf(next.x - here.x) > 0.0001 and _can_step(sx):
		return sx
	var sz := Vector3(here.x, next.y, next.z)
	if absf(next.z - here.z) > 0.0001 and _can_step(sz):
		return sz
	return here


## a에서 b가 트여 있나(공격·광역·연쇄가 닿나). 기본은 언제나 — 공성전(war_hero)은 성벽이 막는다.
func sees(_a: Vector3, _b: Vector3) -> bool:
	return true


func needs_route() -> bool:
	return false


func is_on_wall() -> bool:
	return global_position.y > Balance.WALL_H / 2.0


## 받는 피해: dodge → dmg_reduce → thorns(source = 때린 몬스터에게 되돌림). 방치 모드는 무적(개정 12): 숫자·가시 없이 0.
func take_damage(amount: float, source = null) -> void:
	if state == State.DEAD or (castle != null and GameState.mode == GameState.Mode.IDLE):
		return
	# 회피를 먼저 굴린다(2026-10-07): 피한 공격은 보호막도 깎지 않는다. 같은 굴림을 Skills.incoming에 넘겨 두 번 피하지 않게
	var roll := randf()
	if _sk.has("dodge") and roll < _sk.dodge[0] / 100.0:
		DamageNumbers.pop(self, 0.0, DamageNumbers.Kind.DODGE)
		return
	amount = _skx.incoming(amount, source, _gear_dmg_reduce)  # 받아치기·방벽·금강불괴·광전사·수호의 오라·요새화·돌 피부·방패 막기·장비 피해 감소·보호막
	if amount <= 0.0:
		return
	var r := Skills.incoming(_sk, amount, roll)
	if r.x <= 0.0:
		DamageNumbers.pop(self, 0.0, DamageNumbers.Kind.DODGE)
		return
	hp = maxf(0.0, hp - r.x)
	DamageNumbers.pop(self, r.x, DamageNumbers.Kind.HURT)
	var back := maxf(r.y, atk * _sk.thorns[0] / 100.0) if _sk.has("thorns") else r.y  # 가시: 받은 피해 %와 공격력 % 중 큰 것
	if back > 0.0 and source != null and is_instance_valid(source) and source.is_alive():
		source.take_damage(back * _skill_mult, DamageNumbers.Kind.SKILL)
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
## 준 피해에 비례한 회복(흡혈·흡수)의 배율 — PVP는 체력 배율만큼(체력만 늘고 피해는 그대로라 흡혈이 약해지지 않게).
func dmg_heal_mult() -> float:
	return 1.0


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
	remove_from_group(allies)
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
	if _focus != null and not _path.is_empty():
		_focus_cd -= delta
		if _focus_cd <= 0.0:
			_focus_cd = FOCUS_REPLAN
			_focus_walk()
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
			if wp.y == 0.0 or is_equal_approx(wp.y, Balance.WALL_H):
				global_position.y = wp.y  # 계단 끝을 일찍 지나쳐도(지나가는 반경) 바닥·성벽 높이에 딛는다 — 다음 구간 내내 떠서 걷지 않게
		return
	if _cast_t > 0.0:  # 시전 자세: 제자리에서 표적을 보며 모션을 마친다(평타·추격·복귀 없음)
		if _target != null and is_instance_valid(_target) and _target.is_alive():
			_model.face(_target.global_position - global_position)
		return
	_scan_cd -= delta
	if _focus != null:
		if not _focus_ok():
			_end_focus()
		else:
			_target = _focus
			var fp: Vector3 = _focus.global_position
			if not _can_hit(fp):
				if not _straight_to(fp):
					_go_focus(fp)  # 성문·계단을 거쳐서 — 다음 프레임부터 걷는다
					return
				if not _focus_moved:
					_set_free(_focus_dest(fp))  # 곧장 쫓는다: 자리를 떠난다
					_focus_moved = true
	# 표적이 죽거나 사라지면 다음 스캔을 기다리지 않고 이 프레임에 다시 찾는다(기다리는 동안 자리 쪽으로 물러나지 않게).
	# 휘두르는 중인 사거리 안 표적은 스캔이 놓쳐도(aggro 경계 등) 그대로 둔다.
	var lost: bool = _target != null and not (is_instance_valid(_target) and _target.is_alive())
	if _focus == null and (_scan_cd <= 0.0 or lost):
		_scan_cd = SCAN_INTERVAL
		if not _swinging_at(_target):
			_target = _find_target()
	# 성벽 위 영웅은 쫓지 않는다: 스캔 사이에 사거리를 벗어난 표적은 놓는다(안 그러면 성벽 높이로 떠서 따라간다).
	if _target != null and is_instance_valid(_target) and _target.is_alive() \
			and (not is_on_wall() or Formation.flat_distance(global_position, _target.global_position) <= _reach(_target)):
		_linger = RETURN_DELAY
		var tpos: Vector3 = _target.global_position
		_model.face(tpos - global_position)
		if Formation.flat_distance(global_position, tpos) <= _reach(_target) and sees(global_position, tpos):  # 성벽 너머면 트인 데까지 다가간다
			state = State.ATTACK
			if _sk.has("aoe_blast") and _blast_cd <= 0.0 and _swing == null and _blast_ok(_target):
				_blast_cd = _sk.aoe_blast[0]
				begin_cast(HeroSkillsScript.cast_anim("aoe_blast", def), _cast_blast.bind(_target), "aoe_blast")  # 모션의 발동 순간에 터진다
				return
			if _atk_cd <= 0.0:
				_atk_cd = Skills.interval(_sk, float(def.atk_interval) / _aspd, hp_ratio()) / _skx.speed_mult()
				_attack(_atk_cd)
			return
		# 추격: 지상 영웅만 여기 온다(위 조건). 성 안팎 경계(성벽·모서리)를 넘는 걸음은 딛지 않고 표적을 놓는다(아래에서 자리로).
		var next := _slide(global_position.move_toward(Vector3(tpos.x, global_position.y, tpos.z), _speed * delta))
		if Formation.flat_distance(next, global_position) > _speed * delta * 0.3:
			state = State.MOVE
			_model.play_walk()
			global_position = next
			return
		if _detour(tpos):
			return  # 막혔으면(성채·성문 기둥) 돌아가는 길로 — 다 걸은 뒤 다시 표적을 찾는다
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
		if not is_on_wall() and ((castle == null and not needs_route()) or (castle != null and Formation.route(castle.half, global_position, home).size() == 1)):
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
	if castle == null:  # 아레나: 거리·영역 제한 없이 가장 가까운 괴물(이동 명령 뒤에는 그 자리에서 aggro 안)
		if hold:
			var best = null
			var best_d := INF
			for m in get_tree().get_nodes_in_group(foes):
				if not m.is_alive() or Formation.flat_distance(free_pos, m.global_position) > maxf(float(def.aggro), float(def.range)):
					continue
				var d := Formation.flat_distance(global_position, m.global_position)
				if d < best_d:
					best_d = d
					best = m
			return best
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
	for m in get_tree().get_nodes_in_group(foes):
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
		and Formation.flat_distance(global_position, m.global_position) <= _reach(m)


## 사거리(중심 거리): def.range + 표적 몸 반지름(큰 보스 — 드래곤 hit_radius, 보통 괴물은 0).
func _reach(m) -> float:
	return float(def.range) + float(m.hit_radius())


# --- 스킬 ---

## 쿨 스킬: heal_aura(반경 안 아군 회복), gate_repair(자기 면 성문 회복), aoe_blast 쿨 감소(발사는 교전 중에만).
func _tick_skills(delta: float) -> void:
	_skx.tick(delta)
	_blast_cd -= delta
	_aura_cd -= delta
	if _aura_cd <= 0.0:
		_aura_cd = AURA_SCAN
		_aura_ring.visible = _aura_mult() > 1.0
	if _sk.has("heal_aura"):  # 다친 아군이 있을 때만 발동 모션(개정 26) → 발동 순간에 회복. 모션을 못 시작하면 곧 다시
		_heal_cd -= delta
		if _heal_cd <= 0.0:
			_heal_cd = _sk.heal_aura[0]
			if _anyone_hurt(_sk.heal_aura[1]) and not begin_cast(HeroSkillsScript.cast_anim("heal_aura", def), _heal_aura, "heal_aura"):
				_heal_cd = HeroSkillsScript.CAST_WAIT
	if _sk.has("gate_repair"):
		_repair_cd -= delta
		if _repair_cd <= 0.0:
			_repair_cd = _sk.gate_repair[0]
			if castle != null and holds_post() and GameState.gate_hp[side] > 0.0 and GameState.gate_hp[side] < GameState.gate_hp_max \
					and not begin_cast(HeroSkillsScript.cast_anim("gate_repair", def), _gate_repair, "gate_repair"):
				_repair_cd = HeroSkillsScript.CAST_WAIT


## 반경 안에 다친(체력이 다 차지 않은) 살아 있는 영웅이 있는가.
func _anyone_hurt(radius: float) -> bool:
	for h in get_tree().get_nodes_in_group(allies):
		if h.is_alive() and h.hp < h.hp_max and Formation.flat_distance(global_position, h.global_position) <= radius:
			return true
	return false


func _heal_aura() -> void:
	var radius: float = _sk.heal_aura[1]
	var healed := false
	for h in get_tree().get_nodes_in_group(allies):
		if h.is_alive() and Formation.flat_distance(global_position, h.global_position) <= radius \
				and h.heal(h.hp_max * _sk.heal_aura[2] / 100.0) > 0.0:
			healed = true
			Fx.heal_cross(h)
	if healed:
		Fx.heal_ring(get_parent(), global_position, radius, _tier)
		Sfx.skill("heal_aura", self)
		_announce("heal_aura")


## 자기 면 성문 앞이나 같은 면 성벽 위 자리에 서 있을 때만(이동·추격 중이면 아님). 부서진 성문은 GameState가 거른다.
func _gate_repair() -> void:
	if not holds_post():
		return
	if GameState.repair_gate(side, GameState.gate_hp_max * _sk.gate_repair[1] / 100.0) > 0.0:
		Fx.repair(get_parent(), Formation.gate_position(castle.half, side, Formation.nearest_gate_at(castle.half, side, global_position)), _tier)
		Sfx.skill("gate_repair", self)
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
		Sfx.at("swing", self)
		if Formation.flat_distance(global_position, m.global_position) <= _reach(m) + SWING_SLACK and sees(global_position, m.global_position):
			_strike(m, a, true, _attacks)
		return
	if not sees(global_position, m.global_position):
		return  # 성벽 너머(공성전)는 쏘지 않는다
	var targets := [m]
	if _sk.has("multishot"):
		targets.append_array(_nearest_others(m, global_position, float(def.range), int(_sk.multishot[0]) - 1))
	var shot: Array = SHOTS.get(def.model, ["arrow", ARROW_SPEED])
	Sfx.shot(shot[0], self)
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
		heal(d * _sk.lifesteal[0] / 100.0 * dmg_heal_mult())
	if _gear_lifesteal > 0.0:
		heal(d * _gear_lifesteal * dmg_heal_mult())
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
		if Skills.BURN_POISON.has(def.id):
			m.apply_dot("burn", a * _sk.poison[0] / 100.0 * _skill_mult, _sk.poison[1])
		else:
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


## aoe_blast를 지금 표적에 쓸까(공성전 AI가 덮어써 무리가 모였을 때만 쓴다). 기본은 쿨이 차면 곧바로.
func _blast_ok(_m) -> bool:
	return true


## aoe_blast 발동 순간(개정 25): 모션을 시작할 때의 표적이 살아 있으면 그 자리, 아니면 지금 표적 자리에 터뜨린다(둘 다 없으면 헛 시전).
## 폭발이 죽인 표적은 놓는다(시체에 평타·투사체·연쇄가 나가지 않게).
func _cast_blast(m) -> void:
	if not (m != null and is_instance_valid(m) and m.is_alive()):
		m = _target
	if m == null or not is_instance_valid(m) or not m.is_alive():
		return
	_blast(m.global_position)
	Sfx.skill("aoe_blast", self)
	if not m.is_alive() and _target == m:
		_target = null


## 발동 모션(개정 25): anim을 재생하고 기 모으기(Fx.charge)를 띄운 뒤, 모션의 발동 순간에 fn을 부른다. 그동안(+CAST_RECOVER) 평타·추격을 쉰다.
## 이미 시전 중이거나 평타를 휘두르는 중이거나 기절·쓰러짐이면 시작하지 않고 false — 쓰는 쪽이 곧 다시 본다.
func begin_cast(anim: String, fn: Callable, kind := "") -> bool:
	if _cast_fn.is_valid() or _swing != null or state == State.DEAD or is_stunned() or not is_inside_tree():
		return false
	var wind: float = _model.play_cast(anim)
	_cast_fn = fn
	_cast_style = HeroSkillsScript.cast_style(kind)
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
		Fx.release(self, _color, _tier, _cast_style)  # 발동 순간 빛 터짐(2026-10-07, 2026-10-13 스킬 종류별)
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
	for m in get_tree().get_nodes_in_group(foes):
		if m.is_alive() and Formation.flat_distance(center, m.global_position) <= _sk.aoe_blast[1] and sees(center, m.global_position):
			m.take_damage(dmg, DamageNumbers.Kind.SKILL)
	Fx.blast(get_parent(), center, _color, _sk.aoe_blast[1], def.grade == "SSR" and GameData.fx_shake(), _tier)  # SSR이면 카메라를 약하게 흔든다
	_announce("aoe_blast")


## from 주변 radius 안 살아 있는 몬스터(exclude 빼고) 가까운 순 최대 n마리. 지상 영웅은 자기 영역(성 안/밖)만.
func _nearest_others(exclude, from: Vector3, radius: float, n: int) -> Array:
	var out := []
	var ground := not is_on_wall() and castle != null  # 아레나는 영역이 없다
	var here_inside := ground and Formation.is_inside(castle.half, global_position)
	for m in get_tree().get_nodes_in_group(foes):
		if m == exclude or not m.is_alive() or Formation.flat_distance(from, m.global_position) > radius:
			continue
		if ground and Formation.is_inside(castle.half, m.global_position) != here_inside:
			continue
		if not sees(from, m.global_position):
			continue
		out.append(m)
	out.sort_custom(func(p, q): return Formation.flat_distance(from, p.global_position) < Formation.flat_distance(from, q.global_position))
	return out.slice(0, n)


## 스킬 발동 표시(개정 17 §3, 2026-10-12 개편): 머리 위 표시 + 발밑 링 맥동. 액티브·한 판 한 번 패시브(NAMED_PASSIVES)는 이름 띠,
## 확률 패시브는 이름 없이 스킬 그림만 — 둘은 따로 BANNER_GAP초에 한 번(확률 패시브가 액티브 이름을 가리지 않게).
## 우리 편 SSR은 발동 스킬마다 화면 컷인도 띄운다 — 궁극기(해금된 가장 높은 칸의 액티브)는 늘, 다른 발동 스킬은 DamageNumbers가 영웅마다
## 간격을 둔다(2026-10-14 "다 나오는게 맞아"). 궁극기는 다른 스킬 이름 띠의 간격(BANNER_GAP)에 막히지 않는다(바로 뒤에 써도 빠지지 않게 — 같은 스킬끼리는 막힌다).
## 상대 팀(team 1)은 작은 띠.
func _announce(kind: String) -> void:
	if not is_inside_tree():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var named := HeroSkillsScript.is_active(kind) or kind in NAMED_PASSIVES
	var enemy: bool = get("team") == 1
	var ssr: bool = not enemy and def.get("grade", "") == "SSR"
	var ult: bool = named and ssr and kind == _ult_kind()
	if named:
		if now - _banner_at < BANNER_GAP and (not ult or kind == _banner_kind):
			return
		_banner_at = now
		_banner_kind = kind
	else:
		if now - _proc_at < BANNER_GAP:
			return
		_proc_at = now
	var label := Skills.name_of(kind, def.id)
	DamageNumbers.banner(self, kind, label if named else "", _color, enemy)
	if ssr and HeroSkillsScript.is_active(kind):
		DamageNumbers.cutin(str(def.id), label, str(def.get("name", "")), _color, kind, ult)
	Fx.pulse(self, _foot, _color, _tier, named, ult)
	if _tier >= 2 and GameData.fx_shake():  # SSR 발동: 화면이 잠깐 당겨진다(아트 방향 §4, 흔들림 설정을 따른다)
		var cam := get_viewport().get_camera_3d()
		if cam != null and cam.get_parent().has_method("punch") and _on_screen(cam):
			cam.get_parent().punch()


## 궁극기 = 해금된 칸 중 가장 높은 칸의 액티브(SSR ★0이면 첫 스킬, ★5면 셋째 스킬). 없으면 "".
func _ult_kind() -> String:
	var kinds: Array = def.get("skills", {}).keys()
	for i in range(kinds.size() - 1, -1, -1):
		if _sk.has(kinds[i]) and HeroSkillsScript.is_active(kinds[i]):
			return kinds[i]
	return ""


## 화면 안에 보이는가(머리 높이 지점이 뷰포트 안).
func _on_screen(cam: Camera3D) -> bool:
	return get_viewport().get_visible_rect().has_point(cam.unproject_position(global_position + HIT_HEIGHT))


## atk_aura: 반경 안 다른 영웅들의 오라(해금된 것만) 중 가장 큰 것 하나.
func _aura_mult() -> float:
	var best := 0.0
	for h in get_tree().get_nodes_in_group(allies):
		var hs: Dictionary = h._sk
		if h != self and h.is_alive() and hs.has("atk_aura") \
				and Formation.flat_distance(h.global_position, global_position) <= hs.atk_aura[0]:
			best = maxf(best, hs.atk_aura[1])
	return Skills.aura_mult(best)


## 최종 능력치를 다시 읽는 한 곳(개정 20): HP·공격 = hero_stats(기본 × 레벨 × 승급 + 장비) × (1 + 성장 %) × (1 + 연구 %, 개정 24),
## × (1 + 길드 버프 %), 공격 간격 ÷ (1 + 성장 공격속도 + 장비 공격 속도), 이동 × (1 + 성장 이동속도 + 신발 %), 스킬 피해 × (1 + 연구 비전 % + 장비 스킬 피해 %),
## 치명타 = 성장 + 장비, 장비 흡혈·받는 피해 감소. 성장·장비·연구·길드가 바뀌면 곧바로 —
## HP 비율 유지, 다음 공격부터 새 간격.
func refresh_stats() -> void:
	_bonus = Economy.upgrade_bonus().duplicate()
	var r: Dictionary = Economy.research_bonus()
	var ratio := hp_ratio() if hp_max > 0.0 else 1.0
	var st := GameData.hero_stats(def, _level, _promotion, {} if helper else null)
	var gear: Dictionary = GameData.equip_total([]) if helper else Economy.equipment_bonus(str(def.get("id", "")))
	var g: float = 1.0 + Guild.buff_pct() / 100.0
	hp_max = st.hp * (1.0 + _bonus.hp_pct) * (1.0 + r.hero_hp_pct / 100.0) * g
	atk = st.atk * (1.0 + _bonus.atk_pct) * (1.0 + r.hero_atk_pct / 100.0) * g
	_skill_mult = 1.0 + r.skill_pct / 100.0 + gear.skill_dmg / 100.0
	hp = hp_max * ratio
	# 장비 특수 능력치(2026-10-07): 치명타 확률·피해는 성장 값에 더하고(crit_roll_params), 공격 속도는 성장 공격속도에 더한다
	_bonus.crit_rate = float(_bonus.get("crit_rate", 0.0)) + gear.crit_rate / 100.0
	_bonus.crit_dmg = float(_bonus.get("crit_dmg", 0.0)) + gear.crit_dmg / 100.0
	_gear_lifesteal = gear.lifesteal / 100.0
	_gear_dmg_reduce = minf(gear.dmg_reduce, GameData.DMG_REDUCE_CAP) / 100.0
	_aspd = 1.0 + _bonus.aspd_pct + gear.aspd / 100.0
	_speed = float(def.speed) * (1.0 + _bonus.mspd_pct + gear.speed_pct / 100.0)


func hp_ratio() -> float:
	return hp / hp_max if hp_max > 0.0 else 0.0


## 겹침 해소(crowd.gd): 몸 반지름, 밀리는 무게(걷는 중이 아니면 — 자리를 지키거나 싸우는 중 — 무겁다).
func radius() -> float:
	return Crowd.HUMAN_R * Art.CHARACTER_SCALE


## 던전·드래곤 아레나(성 없음): 영웅끼리만 ARENA_PAD씩 더 떨어진다(crowd.gd) — 싸움을 따라 당긴 카메라에서 한 덩어리로 겹쳐 보이지 않게.
## 적과의 맞닿는 거리는 그대로(근접 사거리 여유가 골렘 상대 0.15 m뿐). 공성·PVP 영웅(space가 있음)은 이미 몸 둘레 여유가 있어 뺀다.
func ally_pad() -> float:
	return ARENA_PAD if castle == null and not has_method("space") else 0.0


func push_mass() -> float:
	return Crowd.mass(radius(), state != State.MOVE)


func bar_height() -> float:
	return Art.HEAD_HEIGHT * Art.CHARACTER_SCALE


func bar_scale() -> float:
	return 1.0

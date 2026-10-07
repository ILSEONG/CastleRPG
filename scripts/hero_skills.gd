extends RefCounted
## 스킬 100종 확장의 적용(Skills 표의 새 종류 — 원래 19종 heal_aura … gate_repair는 hero.gd에 그대로). 영웅 하나에 하나.
## hero.gd가 고리마다 부른다:
##  tick(쿨 발동·오라·재생·지속 효과) · atk_mult/damage_mult(타격 배율) · on_hit(맞힌 뒤 효과) · on_kill(처치 효과) ·
##  speed_mult(공격 속도) · incoming(받는 피해 조정) · after_hurt(반격·재기·금강불괴) · try_revive(불굴) · reset(리필).
## 발동형은 쿨이 차면 조건(교전 중 표적, 반경 안 적, 다친 아군 …)이 맞을 때 쓰고 이름 띠를 띄운다(hero._announce).
## 피해 = 공격력 × 오라 × 강화 배율 × %/100 × 연구 스킬 배율(hero._skill_mult). 몬스터 상태는 monster.gd(apply_dot·apply_freeze …),
## 소환수는 summon.gd, 이펙트는 Fx(tier = 영웅 등급 연출 단계).

const Art := preload("res://scripts/art.gd")
const Formation := preload("res://scripts/formation.gd")
const Fx := preload("res://scripts/fx.gd")
const DamageNumbers := preload("res://scripts/damage_numbers.gd")
const ProjectileScript := preload("res://scripts/projectile.gd")
const Sfx := preload("res://scripts/sfx.gd")

## 발동형(쿨 a초). 처음엔 쿨의 FIRST_CD배만 기다린다(교전이 시작되면 곧 쓴다).
const BULWARK_TAUNT_R := 4.0  # 방벽 도발 반경(m)
const ACTIVE := ["meteor", "inferno", "earthquake", "ground_slam", "blizzard", "tornado", "thunder_storm", "arrow_rain", "poison_cloud",
	"frost_nova", "whirlwind", "war_cry", "shockwave", "spear_throw", "ice_spikes", "dragon_breath", "starfall", "sky_bolt", "comet",
	"holy_smite", "shadow_strike", "void_rift", "solar_flare", "abyss_hand", "lava_burst", "sanctuary", "mass_heal", "resurrection",
	"battle_hymn", "shield_ally", "shield", "taunt", "summon_wolf", "summon_skeleton", "summon_golem", "summon_treant", "summon_spirit",
	"summon_phoenix", "summon_hawk", "summon_turret",
	# 2026-10-06 스킬 재구성: 패시브에서 바뀐 액티브
	"ignite", "piercing_shot", "blood_rage", "frost_chain", "rend", "bulwark", "crushing_blow", "sunder", "shield_bash", "snare",
	"blade_flurry", "parry", "fire_bolt", "firespread", "axe_volley", "boomerang", "spear_sweep", "drain_slash", "volley", "wide_swing",
	"cheap_shot", "crescent", "lunar_veil", "howl", "deep_freeze", "hex"]
## 확률 발동 패시브(2026-10-06): 예전 액티브의 효과를 평타(주 대상)에 a% 확률로 붙인다 — 화염 지대·회오리·태양 섬광·얼음 가시·용암 분출
const PROCS := ["scorch", "gale", "solar_spark", "frost_spike", "magma"]
## 소환 종류 → [summon.gd 종류, 마리 수]
const SUMMONS := {"summon_wolf": ["wolf", 2], "summon_skeleton": ["skeleton", 2], "summon_golem": ["golem", 1], "summon_treant": ["treant", 1],
	"summon_spirit": ["spirit", 1], "summon_phoenix": ["phoenix", 1], "summon_hawk": ["hawk", 1], "summon_turret": ["turret", 1]}
const HIT := Vector3(0, 0.8, 0)  # hero.HIT_HEIGHT
const MUZZLE := Vector3(0, 1.3, 0)  # hero.MUZZLE
const SHOTS := {"Mage": ["bolt", 18.0], "Barbarian": ["axe", 20.0]}  # hero.SHOTS(없으면 화살 30 m/s)
const FIRST_CD := 0.4
## 쿨이 도는 발동형인데 hero.gd가 직접 돌리는 셋(원래 19종에서).
const HERO_ACTIVE := ["heal_aura", "gate_repair", "aoe_blast"]
const CAST_WAIT := 0.1  # 쿨이 찼는데 영웅이 휘두르는·시전하는 중이면 이만큼 뒤에 다시 본다
## 발동 모션(개정 25): 발동형 → KayKit 모션(모든 영웅 모델에 같은 이름이 있다). 발동 순간은 Art.CAST_FRAC. 없으면 그 영웅의 평타 모션.
## 하늘에 손을 드는 주문(낙하·광선·소환·회복) = Spellcast_Raise, 바닥 지대·균열 = Spellcast_Long, 앞으로 쏘는 주문 = Spellcast_Shoot,
## 함성·도발·찬가 = Cheer, 회오리 = 2H 돌기, 지진 = 뛰어 내려찍기, 대지 강타 = 2H 내려치기, 창 = 던지기, 돌진·그림자 = 찌르기, 방패 = 막기·물건 쓰기.
const CAST_ANIM := {
	"meteor": "Spellcast_Raise", "comet": "Spellcast_Raise", "starfall": "Spellcast_Raise", "sky_bolt": "Spellcast_Raise",
	"thunder_storm": "Spellcast_Raise", "holy_smite": "Spellcast_Raise", "solar_flare": "Spellcast_Raise", "sanctuary": "Spellcast_Raise",
	"mass_heal": "Spellcast_Raise", "resurrection": "Spellcast_Raise", "summon_wolf": "Spellcast_Raise", "summon_skeleton": "Spellcast_Raise",
	"summon_golem": "Spellcast_Raise", "summon_treant": "Spellcast_Raise", "summon_spirit": "Spellcast_Raise", "summon_phoenix": "Spellcast_Raise",
	"summon_hawk": "Spellcast_Raise", "summon_turret": "Use_Item",
	"inferno": "Spellcast_Long", "poison_cloud": "Spellcast_Long", "blizzard": "Spellcast_Long", "tornado": "Spellcast_Long",
	"void_rift": "Spellcast_Long", "abyss_hand": "Spellcast_Long",
	"aoe_blast": "Spellcast_Shoot", "frost_nova": "Spellcast_Shoot", "ice_spikes": "Spellcast_Shoot", "lava_burst": "Spellcast_Shoot",
	"dragon_breath": "Spellcast_Shoot",
	"war_cry": "Cheer", "taunt": "Cheer", "battle_hymn": "Cheer",
	"whirlwind": "2H_Melee_Attack_Spin", "earthquake": "Jump_Full_Short", "ground_slam": "2H_Melee_Attack_Chop", "spear_throw": "Throw",
	"shockwave": "1H_Melee_Attack_Stab", "shadow_strike": "1H_Melee_Attack_Stab", "shield": "Block", "shield_ally": "Use_Item",
	"arrow_rain": "Spellcast_Raise", "heal_aura": "Spellcast_Raise", "gate_repair": "Use_Item",  # 개정 26: 빠져 있던 셋(화살비·치유의 오라·성문 수리)
	# 2026-10-06 새 액티브(관통 사격·연발 사격은 그 영웅의 평타 사격 모션)
	"ignite": "Spellcast_Shoot", "frost_chain": "Spellcast_Shoot", "fire_bolt": "Spellcast_Shoot", "lunar_veil": "Spellcast_Raise",
	"deep_freeze": "Spellcast_Raise", "firespread": "Spellcast_Long", "hex": "Spellcast_Long", "blood_rage": "Cheer", "howl": "Cheer",
	"bulwark": "Block", "parry": "Block", "shield_bash": "Block_Attack", "snare": "Throw", "axe_volley": "Throw", "boomerang": "Throw",
	"rend": "Dualwield_Melee_Attack_Slice", "crescent": "Dualwield_Melee_Attack_Slice", "blade_flurry": "Dualwield_Melee_Attack_Stab",
	"crushing_blow": "2H_Melee_Attack_Chop", "sunder": "2H_Melee_Attack_Slice", "spear_sweep": "2H_Melee_Attack_Slice",
	"drain_slash": "1H_Melee_Attack_Slice_Diagonal", "wide_swing": "1H_Melee_Attack_Slice_Horizontal", "cheap_shot": "1H_Melee_Attack_Stab",
}
const RETRY := 0.5  # 조건이 안 맞아 못 쓴 발동형은 이만큼 뒤에 다시 본다(매 프레임 찾지 않게)
const AURA_SCAN := 0.25
const BURN_PCT := 15.0  # 메테오·용의 숨결이 남기는 화상(초당 공격력 %, 3초)
const HARVEST_MAX := 5
const HARVEST_SEC := 5.0
const BRAWL_R := 3.0
const FIRE := Color(1.0, 0.45, 0.12)
const ICE := Color(0.6, 0.9, 1.0)
const POISON := Color(0.5, 0.85, 0.25)
const HOLY := Color(1.0, 0.9, 0.45)
const VOID := Color(0.55, 0.3, 0.85)
const EARTH := Color(0.62, 0.48, 0.32)
const STORM := Color(0.7, 0.85, 1.0)
const BLOOD := Color(0.85, 0.12, 0.15)
const STEEL := Color(0.75, 0.82, 0.95)
const MOON := Color(0.75, 0.8, 1.0)
const WILD := Color(0.85, 0.65, 0.3)
const CURSE := Color(0.45, 0.75, 0.3)

var h  # 영웅(hero.gd) — 이 객체를 가진 노드
var sk: Dictionary = {}
var barrier := 0.0  # 보호막(받는 피해를 먼저 흡수)
var hymn_pct := 0.0  # 전투 찬가로 받은 공격력 %
var _hymn_t := 0.0
var _cd := {}
var _barrier_fx: Node3D
var _harvest: Array[float] = []  # 영혼 수확 겹 남은 초
var _lust_t := 0.0
var _frenzy_m
var _frenzy_n := 0
var _focus_m
var _focus_t := 0.0
var _revived := false
var _wind_cd := 0.0
var _inv_cd := 0.0
var _inv_t := 0.0
var _regen_acc := 0.0
var _aura_cd := 0.0
var _haste_aura := 0.0
var _guard_aura := 0.0
var _regen_aura := 0.0
var _rage_t := 0.0  # 피의 격노 남은 초
var _wall_t := 0.0  # 방벽 남은 초
var _parry_t := 0.0  # 받아치기 남은 초
var _wall_fx: Node3D


func _init(hero) -> void:
	h = hero


## k가 쿨이 도는 발동형(액티브)인가 — 하단 초상화 쿨 칸이 쓴다.
static func is_active(k: String) -> bool:
	return k in ACTIVE or k in HERO_ACTIVE


## 발동형 k의 다음 발동까지 남은 초(없으면 0).
func cd_left(k: String) -> float:
	return float(_cd.get(k, 0.0))


## 해금된 스킬이 바뀌면(setup) 다시 넣는다.
func set_skills(p_sk: Dictionary) -> void:
	sk = p_sk
	reset()


## 리필·처음: 쿨·겹·보호막·불굴을 처음으로.
func reset() -> void:
	_cd.clear()
	for k in ACTIVE:
		if sk.has(k):
			_cd[k] = float(sk[k][0]) * FIRST_CD
	_clear_barrier()
	hymn_pct = 0.0
	_hymn_t = 0.0
	_harvest.clear()
	_lust_t = 0.0
	_frenzy_m = null
	_frenzy_n = 0
	_focus_m = null
	_focus_t = 0.0
	_revived = false
	_wind_cd = 0.0
	_inv_cd = 0.0
	_inv_t = 0.0
	_regen_acc = 0.0
	_rage_t = 0.0
	_parry_t = 0.0
	_end_wall()


# --- 매 프레임 ---

func tick(delta: float) -> void:
	_lust_t -= delta
	_wind_cd -= delta
	_inv_cd -= delta
	_inv_t -= delta
	_hymn_t -= delta
	_rage_t -= delta
	_parry_t -= delta
	if _wall_t > 0.0:
		_wall_t -= delta
		if _wall_t <= 0.0:
			_end_wall()
	if _hymn_t <= 0.0:
		hymn_pct = 0.0
	for i in range(_harvest.size() - 1, -1, -1):
		_harvest[i] -= delta
		if _harvest[i] <= 0.0:
			_harvest.remove_at(i)
	_aura_cd -= delta
	if _aura_cd <= 0.0:
		_aura_cd = AURA_SCAN
		_scan_auras()
	_tick_regen(delta)
	if _focus_m != null:
		_focus_t += delta
	for k in _cd:
		_cd[k] -= delta
		if _cd[k] <= 0.0:
			_cd[k] = _begin(k)


## 쿨이 찬 발동형 k(개정 25): 조건이 맞으면(_cast 미리 보기) 영웅이 발동 모션을 시작하고, 모션의 발동 순간에 실제로 쓴다 — 그때 조건이
## 깨졌으면(표적이 죽었다 등) RETRY 뒤 다시. 반환 = 다음에 볼 때까지 초(쿨 / RETRY / 영웅이 바쁘면 CAST_WAIT).
func _begin(k: String) -> float:
	if not _cast(k, true):
		return RETRY
	if h.has_method("cast_ok") and not h.cast_ok(k):  # PVP 영웅: 머리(pvp_brain)가 좋은 때를 고른다
		return RETRY
	if not h.begin_cast(cast_anim(k, h.def), func():
			_retarget()
			if _cast(k):
				Sfx.skill(k, h)
			else:
				_cd[k] = minf(_cd[k], RETRY)):
		return CAST_WAIT
	return float(sk[k][0])


## 발동 순간에 표적이 그새 쓰러졌으면(다른 영웅이 끝냈다) 새 표적을 잡는다 — 안 그러면 모션만 하고 불발한다
## (전투 시뮬 2026-10-07: 성 스테이지 성벽 원거리 스킬의 90% 이상이 이렇게 불발했다).
## 표적이 살아 있어도 모션 중에 사거리 밖으로 걸어 나갔으면(PVP 상대 영웅) 사거리 안의 다른 적에게 쓴다 — 성 밖 아레나만(성은 성벽 너머를 고르지 않게).
## (전투 시뮬 2026-10-07: 결투 근접 스킬 — 흡혈 베기·분쇄 일격·찢기 — 의 20~50%가 이렇게 불발했다.)
func _retarget() -> void:
	var t = h._target
	if t == null or not is_instance_valid(t) or not t.is_alive():
		h._target = h._find_target()
	if h.castle != null or _combat_target() != null:
		return
	var best = null
	var best_d := INF
	for m in _near_monsters(h.global_position, float(h.def.range) + 0.5):
		var d: float = Formation.flat_distance(h.global_position, m.global_position)
		if d <= h._reach(m) + 0.5 and d < best_d:
			best_d = d
			best = m
	if best != null:
		h._target = best


## 발동형 k를 쓸 때의 모션 이름(영웅 정의 hero_def — 모르는 종류는 그 영웅의 평타 모션).
static func cast_anim(k: String, hero_def: Dictionary) -> String:
	return CAST_ANIM.get(k, Art.hero_spec(hero_def).anims.attack)


## 재생(자기 regen + 받는 생명의 오라): 1초마다 한 번에 회복한다(숫자가 매 프레임 뜨지 않게).
func _tick_regen(delta: float) -> void:
	var pct: float = (float(sk.regen[0]) if sk.has("regen") else 0.0) + _regen_aura
	if pct <= 0.0 or not h.is_alive():
		_regen_acc = 0.0
		return
	_regen_acc += delta
	if _regen_acc >= 1.0:
		_regen_acc -= 1.0
		if h.hp < h.hp_max:
			h.heal(h.hp_max * pct / 100.0)


## 받는 오라(질풍·수호·생명): 반경 안 영웅(자신 포함)들 것 중 가장 큰 것 하나씩.
func _scan_auras() -> void:
	_haste_aura = 0.0
	_guard_aura = 0.0
	_regen_aura = 0.0
	for o in h.get_tree().get_nodes_in_group(h.allies):
		if not o.is_alive():
			continue
		var os: Dictionary = o._sk
		var d := Formation.flat_distance(h.global_position, o.global_position)
		if os.has("haste_aura") and d <= float(os.haste_aura[0]):
			_haste_aura = maxf(_haste_aura, float(os.haste_aura[1]))
		if os.has("guard_aura") and d <= float(os.guard_aura[0]):
			_guard_aura = maxf(_guard_aura, float(os.guard_aura[1]))
		if os.has("regen_aura") and d <= float(os.regen_aura[0]):
			_regen_aura = maxf(_regen_aura, float(os.regen_aura[1]))


# --- 공격 ---

## 공격 속도 배율(간격 ÷): 질풍의 오라 + 광란 겹 + 피의 갈망.
func speed_mult() -> float:
	var m := 1.0 + _haste_aura / 100.0
	if sk.has("frenzy"):
		m += float(sk.frenzy[0]) / 100.0 * _frenzy_n
	if sk.has("bloodlust") and _lust_t > 0.0:
		m += float(sk.bloodlust[0]) / 100.0
	if sk.has("blood_rage") and _rage_t > 0.0:
		m += float(sk.blood_rage[2]) / 100.0
	return m


## 표적과 무관한 공격력 배율: 광전사 · 배수진 · 영혼 수확 겹 · 전투 찬가. 스킬 피해에도 곱한다.
func atk_mult() -> float:
	var m := 1.0 + hymn_pct / 100.0
	if sk.has("berserker"):
		m *= 1.0 + float(sk.berserker[0]) / 100.0
	if sk.has("last_stand") and h.hp_ratio() <= float(sk.last_stand[0]) / 100.0:
		m *= 1.0 + float(sk.last_stand[1]) / 100.0
	if sk.has("soul_harvest"):
		m *= 1.0 + float(sk.soul_harvest[1]) / 100.0 * _harvest.size()
	return m


## 한 타격의 배율(atk_mult × 표적 조건): 강타(N번째) · 약점 포착 · 화염 숙련 · 기선 제압 · 집중 · 저격 · 난전.
func damage_mult(m, attack_no: int, primary: bool) -> float:
	var x := atk_mult()
	if primary and sk.has("heavy_blow") and attack_no % int(sk.heavy_blow[0]) == 0:
		x *= float(sk.heavy_blow[1]) / 100.0
	if sk.has("opportunist") and m.is_controlled():
		x *= 1.0 + float(sk.opportunist[0]) / 100.0
	if sk.has("pyromancy") and m.has_status("burn"):
		x *= 1.0 + float(sk.pyromancy[0]) / 100.0
	if sk.has("first_strike") and m.hp_ratio() >= 0.9:
		x *= 1.0 + float(sk.first_strike[0]) / 100.0
	if sk.has("focus") and m == _focus_m:
		x *= 1.0 + minf(float(sk.focus[0]) * _focus_t, float(sk.focus[1])) / 100.0
	if sk.has("sharpshooter") and Formation.flat_distance(h.global_position, m.global_position) > float(h.def.range) * 0.5:
		x *= 1.0 + float(sk.sharpshooter[0]) / 100.0
	if sk.has("brawler"):
		var n := _near_monsters(h.global_position, BRAWL_R).size()
		x *= 1.0 + minf(float(sk.brawler[0]) * n, float(sk.brawler[1])) / 100.0
	return x


## 처치 효과가 볼 표적 상태(피해 전에 — 죽으면 상태가 지워진다). bit 1 = 느려짐·빙결, 2 = 불탐.
static func snap(m) -> int:
	return (1 if m.has_status("slow") or m.has_status("freeze") else 0) | (2 if m.has_status("burn") else 0)


## 맞힌 뒤(hero._strike가 피해를 준 다음): 타격 효과. d = 이번 피해, was = snap(피해 전).
func on_hit(m, d: float, primary: bool, attack_no: int, was: int) -> void:
	if primary:
		_track_target(m)
	if not m.is_alive():
		on_kill(m, was)
		return
	var a := _atk()
	if _roll("burn_hit"):
		m.apply_dot("burn", a * float(sk.burn_hit[1]) / 100.0 * h._skill_mult, float(sk.burn_hit[2]))
	if _roll("bleed_hit"):
		m.apply_dot("bleed", a * float(sk.bleed_hit[1]) / 100.0 * h._skill_mult, float(sk.bleed_hit[2]))
	if _roll("curse_hit"):
		m.apply_dot("curse", a * float(sk.curse_hit[1]) / 100.0 * h._skill_mult, float(sk.curse_hit[2]))
	if _roll("freeze_hit"):
		m.apply_freeze(float(sk.freeze_hit[1]))
		_announce("freeze_hit")
	if _roll("root_hit"):
		m.apply_root(float(sk.root_hit[1]))
	if _roll("armor_break"):
		m.apply_vulnerable(float(sk.armor_break[1]), float(sk.armor_break[2]))
	if _roll("weaken_hit"):
		m.apply_weaken(float(sk.weaken_hit[1]), float(sk.weaken_hit[2]))
	if sk.has("hunter_mark"):
		m.apply_vulnerable(float(sk.hunter_mark[0]), float(sk.hunter_mark[1]))
	if _roll("knockback_hit"):
		m.knockback(h.global_position, float(sk.knockback_hit[1]))
	if primary and sk.has("heavy_blow") and attack_no % int(sk.heavy_blow[0]) == 0:
		m.knockback(h.global_position, float(sk.heavy_blow[2]))
		Fx.dust(_world(), m.global_position)
		_announce("heavy_blow")
	if _roll("shock_hit"):
		Fx.lightning(_world(), [m.global_position + HIT], STORM, h._tier)
		_hit(m, a * float(sk.shock_hit[1]) / 100.0 * h._skill_mult)
		_announce("shock_hit")
	if not primary:
		return
	for pk in PROCS:
		if _roll(pk):
			_proc(pk, m)
	if sk.has("splash"):
		for o in _near_monsters(m.global_position, float(sk.splash[0]), m):
			_hit(o, d * float(sk.splash[1]) / 100.0 * h._skill_mult)
		Fx.splash(_world(), m.global_position, h._color, float(sk.splash[0]))
	if sk.has("pierce"):
		var dir: Vector3 = _flat(m.global_position - h.global_position).normalized()
		var from: Vector3 = m.global_position
		for o in _line_monsters(from, dir, float(sk.pierce[0]), 1.0, m):
			_hit(o, d * float(sk.pierce[1]) / 100.0 * h._skill_mult)
		Fx.streak(_world(), from + HIT, from + dir * float(sk.pierce[0]) + HIT, h._color)
	if sk.has("ricochet"):
		_ricochet(m, d)
	if sk.has("echo_strike") and attack_no % int(sk.echo_strike[0]) == 0:
		var r := float(sk.echo_strike[1])
		for o in _near_monsters(m.global_position, r):
			_hit(o, a * float(sk.echo_strike[2]) / 100.0 * h._skill_mult)
		Fx.nova(_world(), m.global_position, h._color, r, h._tier)
		_announce("echo_strike")
	if sk.has("double_strike") and m.is_alive() and randf() < float(sk.double_strike[0]) / 100.0:
		var mref: WeakRef = weakref(m)  # 몬스터 노드를 직접 담지 않는다 — 그새 지워지면 람다가 지워진 노드를 넘기며 오류를 낸다
		h.get_tree().create_timer(0.12).timeout.connect(func():
			var mm = mref.get_ref()
			if mm != null and mm.is_alive() and is_instance_valid(h) and h.is_alive():
				var w := snap(mm)
				mm.take_damage(d, DamageNumbers.Kind.HIT)
				Fx.slash_mark(_world(), mm.global_position + HIT, h._color)
				if not mm.is_alive():
					on_kill(mm, w))
	if sk.has("barrage") and h.role == "ranged" and randf() < float(sk.barrage[0]) / 100.0:
		_barrage(m, int(sk.barrage[1]))


## 확률 발동 패시브(평타 주 대상 m): 불바다 = 화염 지대, 돌개바람 = 회오리, 서리 가시 = 얼음 가시, 햇빛 파편·끓는 늪 = 그 자리 폭발.
func _proc(k: String, m) -> void:
	var p: Array = sk[k]
	match k:
		"scorch":
			_zone("inferno", p, _flat(m.global_position))
		"gale":
			_zone("tornado", p, _flat(m.global_position))
		"frost_spike":
			_line_shot(k, m, float(p[1]), _atk() * float(p[2]) / 100.0 * h._skill_mult)
		_:
			_spot(k, _flat(m.global_position), float(p[1]), float(p[2]), _atk())
	Sfx.skill(k, m)
	_announce(k)


## 처치 효과. m = 방금 죽은 적, was = snap(죽기 전).
func on_kill(m, was: int) -> void:
	var at: Vector3 = m.global_position
	var a := _atk()
	if sk.has("corpse_explosion"):
		var r := float(sk.corpse_explosion[0])
		Fx.blast(_world(), at, VOID, r, false, 0)
		for o in _near_monsters(at, r):
			_hit(o, a * float(sk.corpse_explosion[1]) / 100.0 * h._skill_mult)
	if sk.has("soul_harvest"):
		h.heal(h.hp_max * float(sk.soul_harvest[0]) / 100.0)
		if _harvest.size() >= HARVEST_MAX:
			_harvest.remove_at(0)
		_harvest.append(HARVEST_SEC)
		Fx.soul(_world(), at + HIT, h)
	if sk.has("bloodlust"):
		_lust_t = float(sk.bloodlust[1])
	if sk.has("frost_shatter") and was & 1:
		var r2 := float(sk.frost_shatter[0])
		Fx.nova(_world(), at, ICE, r2, h._tier)
		for o in _near_monsters(at, r2):
			_hit(o, a * float(sk.frost_shatter[1]) / 100.0 * h._skill_mult)
		_announce("frost_shatter")
	if sk.has("wildfire") and was & 2:
		var r3 := float(sk.wildfire[0])
		Fx.splash(_world(), at, FIRE, r3)
		for o in _near_monsters(at, r3):
			o.apply_dot("burn", a * float(sk.wildfire[1]) / 100.0 * h._skill_mult, 3.0)


# --- 받는 피해 ---

## 받는 피해 조정(Skills.incoming의 철벽·가시 앞에): 금강불괴 → 광전사·수호의 오라·요새화 → 돌 피부 → 방패 막기 → reduce(장비 피해 감소) → 보호막.
## source = 때린 적(받아치기 반격 대상, 없으면 null). 2026-10-07: 보호막은 모든 감소가 끝난 피해만 흡수한다(전에는 장비 감소 전 피해를 흡수해 빨리 닳았다).
func incoming(amount: float, source = null, reduce := 0.0) -> float:
	if _inv_t > 0.0:
		return 0.0
	if _parry_t > 0.0:  # 받아치기: 막고 되받아친다
		Fx.block(h)
		if source != null and is_instance_valid(source) and source.has_method("is_alive") and source.is_alive():
			_hit(source, _atk() * float(sk.parry[2]) / 100.0 * h._skill_mult)
			Fx.slash_mark(_world(), source.global_position + HIT, STEEL)
		return 0.0
	var x := amount
	if _wall_t > 0.0:
		x *= 1.0 - float(sk.bulwark[2]) / 100.0
	if sk.has("berserker"):
		x *= 1.0 + float(sk.berserker[1]) / 100.0
	x *= 1.0 - _guard_aura / 100.0
	if sk.has("fortify") and h.holds_post():
		x *= 1.0 - float(sk.fortify[0]) / 100.0
	if sk.has("stoneskin"):
		x *= 1.0 - float(sk.stoneskin[0]) / 100.0  # 2026-10-06: 고정 % 감소(최대 HP %를 빼던 식은 몬스터 공격이 작아 늘 −80%였다)
	if sk.has("block") and randf() < float(sk.block[0]) / 100.0:
		x *= 1.0 - float(sk.block[1]) / 100.0
		Fx.block(h)
	x *= 1.0 - reduce
	if barrier > 0.0:
		var soak := minf(barrier, x)
		barrier -= soak
		x -= soak
		if barrier <= 0.0:
			_clear_barrier()
	return x


## 맞은 뒤(살아 있으면): 반격 · 재기 · 금강불괴.
func after_hurt(source) -> void:
	if sk.has("counter") and source != null and is_instance_valid(source) and source.is_alive() \
			and randf() < float(sk.counter[0]) / 100.0:
		var w := snap(source)
		_hit(source, _atk() * float(sk.counter[1]) / 100.0 * h._skill_mult, w)
		Fx.slash_mark(_world(), source.global_position + HIT, h._color)
		_announce("counter")
	if sk.has("second_wind") and _wind_cd <= 0.0 and h.hp_ratio() < float(sk.second_wind[0]) / 100.0:
		_wind_cd = float(sk.second_wind[2])
		h.heal(h.hp_max * float(sk.second_wind[1]) / 100.0)
		Fx.heal_ring(_world(), h.global_position, 1.5, h._tier)
		_announce("second_wind")
	if sk.has("invincible") and _inv_cd <= 0.0 and h.hp_ratio() < float(sk.invincible[0]) / 100.0:
		_inv_cd = float(sk.invincible[2])
		_inv_t = float(sk.invincible[1])
		Fx.golden(h, _inv_t)
		_announce("invincible")


## 쓰러질 때(HP 0): 불굴이 남아 있으면 그 자리에서 최대 HP의 a%로 버틴다(true — 쓰러지지 않는다).
func try_revive() -> bool:
	if not sk.has("revive") or _revived:
		return false
	_revived = true
	h.hp = maxf(1.0, h.hp_max * float(sk.revive[0]) / 100.0)
	Fx.revive(h)
	_announce("revive")
	return true


## 보호막 더하기(수호 축복·보호막). 최대 HP를 넘지 않는다.
func add_barrier(amount: float) -> void:
	if amount <= 0.0 or not h.is_alive():
		return
	barrier = minf(h.hp_max, barrier + amount)
	if not is_instance_valid(_barrier_fx):
		_barrier_fx = Fx.barrier(h, HOLY)


func _end_wall() -> void:
	_wall_t = 0.0
	if is_instance_valid(_wall_fx):
		_wall_fx.queue_free()
	_wall_fx = null


func _clear_barrier() -> void:
	barrier = 0.0
	if is_instance_valid(_barrier_fx):
		_barrier_fx.queue_free()
	_barrier_fx = null


## 전투 찬가 받기.
func add_hymn(pct: float, sec: float) -> void:
	hymn_pct = maxf(hymn_pct, pct)
	_hymn_t = maxf(_hymn_t, sec)
	Fx.buff(h, Color(1.0, 0.4, 0.25))


# --- 발동형 ---

## 쿨이 찬 발동형 k를 쓴다. 조건이 안 맞으면 false(RETRY 뒤에 다시). dry = 조건만 보고 쓰지 않는다(발동 모션을 시작해도 되는가).
func _cast(k: String, dry := false) -> bool:
	if not h.is_alive() or h.is_stunned() or not h.is_inside_tree():
		return false
	var p: Array = sk[k]
	var a := _atk()
	var t = _combat_target()
	var here: Vector3 = h.global_position
	var w := _world()
	var tier: int = h._tier
	match k:
		"meteor", "comet":
			var tgt = t if k == "meteor" else _strongest(_reach())
			if tgt == null:
				return false
			if dry:
				return true
			var at: Vector3 = _flat(tgt.global_position)
			var r := float(p[1])
			var dmg: float = a * float(p[2]) / 100.0 * h._skill_mult
			Fx.meteor(w, at, FIRE if k == "meteor" else Color(0.55, 0.8, 1.0), r, tier, 0.55)
			_later(0.55, func():
				for o in _near_monsters(at, r):
					_hit(o, dmg)
					if k == "meteor" and o.is_alive():
						o.apply_dot("burn", a * BURN_PCT / 100.0 * h._skill_mult, 3.0))
		"inferno", "poison_cloud", "blizzard", "tornado":
			if t == null:
				return false
			if dry:
				return true
			_zone(k, p, _flat(t.global_position))
		"sanctuary":
			if _hurt_allies(here, float(p[1])).is_empty():
				return false
			if dry:
				return true
			_zone(k, p, _flat(here))
		"earthquake", "ground_slam", "frost_nova", "war_cry", "taunt":
			var r := float(p[1])
			var c: Vector3 = _flat(t.global_position) if k == "frost_nova" and t != null else here  # 서리 폭발은 공격 대상 자리(사거리 8m 마법사)
			var near := _near_monsters(c, r)
			if near.is_empty():
				return false
			if dry:
				return true
			match k:
				"earthquake":
					Fx.quake(w, here, r, tier)
					for o in near:
						_hit(o, a * float(p[2]) / 100.0 * h._skill_mult)
						if o.is_alive():
							o.apply_stun(1.0)
				"ground_slam":
					Fx.quake(w, here, r, maxi(0, tier - 1))
					for o in near:
						_hit(o, a * float(p[2]) / 100.0 * h._skill_mult)
						if o.is_alive():
							o.knockback(here, 1.0)  # 근접 사거리(1.8m) 안에 남게
				"frost_nova":
					Fx.nova(w, c, ICE, r, tier)
					for o in near:
						_hit(o, a * 0.8 * h._skill_mult)
						if o.is_alive():
							o.apply_freeze(float(p[2]))
				"war_cry":
					Fx.nova(w, here, Color(1.0, 0.3, 0.2), r, tier)
					for o in near:
						o.apply_weaken(float(p[2]), 4.0)
				"taunt":
					Fx.nova(w, here, Color(1.0, 0.55, 0.1), r, tier)
					for o in near:
						o.taunt(h, float(p[2]))
		"whirlwind":
			var r := float(p[1])
			if _near_monsters(here, r).is_empty():
				return false
			if dry:
				return true
			for i in 3:
				_later(0.3 * i, func():
					if not h.is_alive():
						return
					Fx.whirl(h, r, h._color)
					for o in _near_monsters(h.global_position, r):
						_hit(o, a * float(p[2]) / 100.0 * h._skill_mult))
		"shockwave", "spear_throw", "ice_spikes", "dragon_breath":
			if t == null:
				return false
			if dry:
				return true
			var dir: Vector3 = _flat(t.global_position - here).normalized()
			if dir == Vector3.ZERO:
				dir = Vector3.FORWARD
			var length := float(p[1])
			var dmg: float = a * float(p[2]) / 100.0 * h._skill_mult
			var hits: Array
			if k == "dragon_breath":
				hits = _cone_monsters(here, dir, length, deg_to_rad(35.0))
				Fx.breath(w, here + Vector3(0, 0.9, 0), dir, length, FIRE, tier)
			else:
				hits = _line_monsters(here, dir, length, 1.6 if k == "shockwave" else (1.0 if k == "spear_throw" else 1.4))
				Fx.line(w, here, here + dir * length, h._color if k != "ice_spikes" else ICE, k, tier)
			for o in hits:
				_hit(o, dmg)
				if o.is_alive():
					if k == "ice_spikes":
						o.apply_freeze(0.8)
					elif k == "dragon_breath":
						o.apply_dot("burn", a * BURN_PCT / 100.0 * h._skill_mult, 3.0)
		"starfall", "sky_bolt":
			var pool := _near_monsters(here, _reach())
			if pool.is_empty():
				return false
			if dry:
				return true
			pool.shuffle()
			var dmg: float = a * float(p[2]) / 100.0 * h._skill_mult
			for o in pool.slice(0, int(p[1])):
				if k == "starfall":
					Fx.star_drop(w, _flat(o.global_position), h._color, tier, 0.35)
					var oref: WeakRef = weakref(o)
					_later(0.35, func():
						var oo = oref.get_ref()
						if oo != null and oo.is_alive():
							_hit(oo, dmg))
				else:
					Fx.lightning(w, [o.global_position + HIT], STORM, tier)
					_hit(o, dmg)
					if o.is_alive():
						o.apply_stun(0.3)
		"thunder_storm", "arrow_rain":
			if t == null:
				return false
			if dry:
				return true
			var at: Vector3 = _flat(t.global_position)
			var r := float(p[1])
			var dmg: float = a * float(p[2]) / 100.0 * h._skill_mult
			var n := 5 if k == "thunder_storm" else 3
			for i in n:
				_later((0.5 if k == "thunder_storm" else 0.3) * i, func():
					if k == "thunder_storm":
						var pt := at + Vector3(randf_range(-r, r), 0, randf_range(-r, r)) * 0.8
						Fx.lightning(w, [pt + HIT], STORM, tier)
						for o in _near_monsters(pt, 1.6):
							_hit(o, dmg)
					else:
						Fx.arrows(w, at, r, h._color)
						for o in _near_monsters(at, r):
							_hit(o, dmg))
		"holy_smite":
			var tgt = _strongest(_reach())
			if tgt == null:
				return false
			if dry:
				return true
			Fx.beam(w, _flat(tgt.global_position), HOLY, tier)
			var before: float = tgt.hp
			_hit(tgt, a * float(p[1]) / 100.0 * h._skill_mult)
			var dealt: float = before - (tgt.hp if tgt.is_alive() else 0.0)
			var ally = _weakest_ally(INF)
			if ally != null:
				ally.heal(dealt * float(p[2]) / 100.0)
				Fx.heal_cross(ally)
		"shadow_strike":
			var tgt = _frailest(maxf(float(h.def.aggro), _reach()) + 2.0)
			if tgt == null:
				return false
			if dry:
				return true
			Fx.shadow(w, tgt.global_position + HIT)
			_hit(tgt, a * float(p[1]) / 100.0 * h._skill_mult)
		"void_rift", "solar_flare", "abyss_hand", "lava_burst":
			if t == null:
				return false
			if dry:
				return true
			var at: Vector3 = _flat(t.global_position)
			var r := float(p[1])
			var hits := _near_monsters(at, r)
			match k:
				"void_rift":
					Fx.rift(w, at, VOID, r, tier)
					for o in hits:
						_hit(o, a * 0.6 * h._skill_mult)
						if o.is_alive():
							o.apply_vulnerable(float(p[2]), 5.0)
				"solar_flare":
					Fx.flare_burst(w, at, HOLY, r, tier)
					for o in hits:
						_hit(o, a * float(p[2]) / 100.0 * h._skill_mult)
						if o.is_alive():
							o.apply_weaken(30.0, 3.0)
				"abyss_hand":
					Fx.hands(w, at, r, VOID)
					for o in hits:
						_hit(o, a * 0.5 * h._skill_mult)
						if o.is_alive():
							o.apply_root(float(p[2]))
				"lava_burst":
					Fx.blast(w, at, FIRE, r, false, tier)
					for o in hits:
						_hit(o, a * float(p[2]) / 100.0 * h._skill_mult)
						if o.is_alive():
							o.knockback(at, 2.0)
		"mass_heal":
			var hurt := _hurt_allies(here, INF)
			if hurt.is_empty():
				return false
			if dry:
				return true
			for o in h.get_tree().get_nodes_in_group(h.allies):
				if o.is_alive():
					o.heal(o.hp_max * float(p[1]) / 100.0)
					Fx.heal_ring(_world(), o.global_position, 1.2, 0)
					Fx.heal_cross(o)
		"resurrection":
			var dead = null
			for o in h.get_tree().get_nodes_in_group(h.allies):
				if not o.is_alive() and o.has_method("revive") and o.is_inside_tree():
					dead = o
					break
			if dead == null:
				return false
			if dry:
				return true
			dead.revive(float(p[1]))
		"battle_hymn":
			if t == null:
				return false
			if dry:
				return true
			for o in h.get_tree().get_nodes_in_group(h.allies):
				if o.is_alive() and o.get("_skx") != null:
					o._skx.add_hymn(float(p[1]), float(p[2]))
		"shield_ally":
			var ally = _weakest_ally(INF)
			if ally == null or ally.get("_skx") == null:
				return false
			if dry:
				return true
			ally._skx.add_barrier(ally.hp_max * float(p[1]) / 100.0)
		"shield":
			if t == null and h.hp >= h.hp_max:
				return false
			if dry:
				return true
			add_barrier(h.hp_max * float(p[1]) / 100.0)
		# --- 2026-10-06 새 액티브 ---
		"ignite", "deep_freeze", "axe_volley":  # 사거리 안 적 최대 b마리(아직 그 상태가 아닌 적부터)
			var pool := _near_monsters(here, _reach())
			if pool.is_empty():
				return false
			if dry:
				return true
			pool.shuffle()
			var st: String = {"ignite": "burn", "deep_freeze": "freeze", "axe_volley": ""}[k]
			if st != "":
				pool.sort_custom(func(x, y): return int(x.has_status(st)) < int(y.has_status(st)))
			var i := 0
			for o in pool.slice(0, int(p[1])):
				match k:
					"ignite":
						Fx.streak(w, here + MUZZLE, o.global_position + HIT, FIRE)
						Fx.blast(w, _flat(o.global_position), FIRE, 0.9, false, 0)
						o.apply_dot("burn", a * float(p[2]) / 100.0 * h._skill_mult, 3.0)
					"deep_freeze":
						Fx.nova(w, _flat(o.global_position), ICE, 1.1, tier)
						Fx.line(w, _flat(o.global_position) - Vector3(0.5, 0, 0), _flat(o.global_position) + Vector3(0.5, 0, 0), ICE, "ice_spikes", 0)
						o.apply_freeze(float(p[2]))
					"axe_volley":
						_shoot(o, "axe", 20.0, a * float(p[2]) / 100.0 * h._skill_mult, 0.07 * i, _axe_land)
				i += 1
		"piercing_shot", "boomerang":
			if t == null:
				return false
			if dry:
				return true
			_line_shot(k, t, float(p[1]), a * float(p[2]) / 100.0 * h._skill_mult)
		"blood_rage", "bulwark", "parry":  # 자기 강화 b초(교전 중에만)
			if t == null:
				return false
			if dry:
				return true
			match k:
				"blood_rage":
					_rage_t = float(p[1])
					Fx.nova(w, here, BLOOD, 2.0, tier)
					Fx.buff(h, BLOOD)
					Fx.golden_tint(h, BLOOD, float(p[1]))
				"bulwark":
					_end_wall()
					_wall_t = float(p[1])
					_wall_fx = Fx.barrier(h, STEEL)
					Fx.nova(w, here, STEEL, BULWARK_TAUNT_R, tier)
					for o in _near_monsters(here, BULWARK_TAUNT_R):  # 2026-10-06 밸런스: 방벽 동안 주변 적이 발두르를 노린다(탱커 역할)
						o.taunt(h, float(p[1]))
				"parry":
					_parry_t = float(p[1])
					Fx.golden_tint(h, STEEL, float(p[1]))
					Fx.block(h)
		"frost_chain":
			if t == null:
				return false
			if dry:
				return true
			var dmg: float = a * float(p[2]) / 100.0 * h._skill_mult
			var hit := [t]
			var cur = t
			for i in int(p[1]):
				var nxt = null
				for o in _near_monsters(cur.global_position, 5.0, cur):
					if not hit.has(o):
						nxt = o
						break
				if nxt == null:
					break
				hit.append(nxt)
				cur = nxt
			var pts := [here + MUZZLE]
			for o in hit:
				pts.append(o.global_position + HIT)
			Fx.lightning(w, pts, ICE, tier)
			for o in hit:
				_hit(o, dmg)
				if is_instance_valid(o) and o.is_alive():
					o.apply_slow(40.0, 2.0)
		"rend", "crushing_blow", "drain_slash", "cheap_shot", "blade_flurry":  # 대상 한 명
			if t == null:
				return false
			if dry:
				return true
			var at: Vector3 = t.global_position
			match k:
				"rend":
					Fx.slash_mark(w, at + HIT + Vector3(0.15, 0.1, 0), BLOOD)
					_later(0.08, func(): Fx.slash_mark(w, at + HIT - Vector3(0.15, 0.1, 0), BLOOD))
					Fx.impact(w, _flat(at), BLOOD, 0.8, 1, 0.8)
					_hit(t, a * float(p[1]) / 100.0 * h._skill_mult)
					if is_instance_valid(t) and t.is_alive():
						t.apply_dot("bleed", a * float(p[2]) / 100.0 * h._skill_mult, 3.0)
				"crushing_blow":
					Fx.impact(w, _flat(at), EARTH, 1.4, 2, 0.6)
					Fx.dust(w, _flat(at))
					Fx.quake(w, _flat(at), 1.6, 0)
					_hit(t, a * float(p[1]) / 100.0 * h._skill_mult)
					if is_instance_valid(t) and t.is_alive():
						t.knockback(here, float(p[2]))
				"drain_slash":
					Fx.slash_mark(w, at + HIT, BLOOD)
					Fx.impact(w, _flat(at), BLOOD, 0.7, 0, 0.8)
					var before: float = t.hp
					_hit(t, a * float(p[1]) / 100.0 * h._skill_mult)
					var dealt: float = before - (t.hp if is_instance_valid(t) and t.is_alive() else 0.0)
					if dealt > 0.0 and h.heal(dealt * float(p[2]) / 100.0) > 0.0:
						Fx.heal_cross(h)
						Fx.soul(w, at + HIT, h)
				"cheap_shot":
					Fx.slash_mark(w, at + HIT, h._color)
					Fx.stun_hit(w, at + HIT, tier)
					_hit(t, a * float(p[1]) / 100.0 * h._skill_mult)
					if is_instance_valid(t) and t.is_alive():
						t.apply_stun(float(p[2]))
				"blade_flurry":
					var tref: WeakRef = weakref(t)
					var dmg: float = a * float(p[2]) / 100.0 * h._skill_mult
					for i in int(p[1]):
						_later(0.1 * i, func():
							var tt = tref.get_ref()
							if tt == null or not tt.is_alive():
								return
							var off := Vector3(randf_range(-0.3, 0.3), randf_range(-0.2, 0.3), randf_range(-0.3, 0.3))
							Fx.slash_mark(_world(), tt.global_position + HIT + off, h._color)
							_hit(tt, dmg))
		"sunder", "shield_bash", "wide_swing", "howl":  # 자기 주변 반경 b
			var r := float(p[1])
			var near := _hurt_allies(here, r) if k == "howl" else _near_monsters(here, r)
			if near.is_empty():
				return false
			if dry:
				return true
			match k:
				"sunder":
					Fx.cleave(w, here, Color(1.0, 0.45, 0.2), r, tier)
					Fx.dust(w, here)
					for o in near:
						_hit(o, a * h._skill_mult)
						if o.is_alive():
							o.apply_vulnerable(float(p[2]), 4.0)
				"shield_bash":
					Fx.nova(w, here, STEEL, r, tier)
					Fx.block(h)
					for o in near:
						_hit(o, a * float(p[2]) / 100.0 * h._skill_mult)
						if o.is_alive():
							Fx.stun_hit(w, o.global_position + HIT, 0)
							o.knockback(here, 1.0)
							o.apply_stun(1.0)
				"wide_swing":
					Fx.cleave(w, here, h._color, r, tier)
					for o in near:
						_hit(o, a * float(p[2]) / 100.0 * h._skill_mult)
				"howl":
					Fx.nova(w, here, WILD, r, tier)
					Fx.heal_ring(w, here, 1.5, tier)
					for o in near:
						o.heal(o.hp_max * float(p[2]) / 100.0)
						Fx.heal_cross(o)
		"spear_sweep", "crescent":  # 앞쪽 부채꼴 길이 b
			if t == null:
				return false
			if dry:
				return true
			var dir: Vector3 = _flat(t.global_position - here).normalized()
			if dir == Vector3.ZERO:
				dir = Vector3.FORWARD
			var length := float(p[1])
			var dmg: float = a * float(p[2]) / 100.0 * h._skill_mult
			if k == "crescent":
				Fx.crescent_wave(w, here, dir, length, MOON, tier)
			else:
				Fx.cleave(w, here + dir * 0.8, h._color, length, tier)
			for o in _cone_monsters(here, dir, length, deg_to_rad(60.0 if k == "spear_sweep" else 45.0)):
				_hit(o, dmg)
				if k == "spear_sweep" and o.is_alive():
					o.knockback(here, 1.0)
		"snare", "firespread", "lunar_veil", "hex":  # 대상 자리 반경 b
			if t == null:
				return false
			if dry:
				return true
			_spot(k, _flat(t.global_position), float(p[1]), float(p[2]), a)
		"fire_bolt":
			if t == null:
				return false
			if dry:
				return true
			var dmg: float = a * float(p[1]) / 100.0 * h._skill_mult
			var burn: float = a * float(p[2]) / 100.0 * h._skill_mult
			var after := func(m):
				Fx.blast(_world(), _flat(m.global_position), FIRE, 1.2, false, 0)
				if m.is_alive():
					m.apply_dot("burn", burn, 3.0)
			_shoot(t, "bolt", 18.0, dmg, 0.0, after, FIRE)
		"volley":
			if t == null:
				return false
			if dry:
				return true
			var shot: Array = SHOTS.get(h.def.model, ["arrow", 30.0])
			for i in int(p[1]):
				_shoot(t, shot[0], shot[1], a * float(p[2]) / 100.0 * h._skill_mult, 0.1 * i, Callable(), h._color, true)
		_:
			if not SUMMONS.has(k) or t == null:
				return false
			if dry:
				return true
			_summon(k, a * float(p[1]) / 100.0 * h._skill_mult, float(p[2]))
	_announce(k)
	return true


## 도끼 세례가 꽂힌 자리.
func _axe_land(m) -> void:
	Fx.impact(_world(), _flat(m.global_position), h._color, 0.6, 0, 0.7)


## 투사체 하나(delay초 뒤, 대상을 따라간다): 맞으면 dmg 스킬 피해 → after(맞은 적).
func _shoot(target, kind: String, speed: float, dmg: float, delay: float, after := Callable(), color := Color(0, 0, 0, 0), tail := false) -> void:
	var tref: WeakRef = weakref(target)
	var col: Color = h._color if color.a == 0.0 else color
	_later(delay, func():
		var tt = tref.get_ref()
		if tt == null or not tt.is_alive() or not h.is_alive():
			return
		var pr = ProjectileScript.new()
		pr.target = tt
		pr.kind = kind
		pr.speed = speed
		pr.color = col
		pr.tail = tail
		pr.on_hit = func(m):
			if is_instance_valid(m) and m.is_alive():
				_hit(m, dmg)
				if after.is_valid() and is_instance_valid(m):
					after.call(m)
		_world().add_child(pr)
		pr.global_position = h.global_position + MUZZLE)


## 일직선 스킬(대상 쪽 길이 length): 관통 사격 = 빛 화살, 회전 도끼 = 갔다 돌아오는 도끼 + 밀침, 서리 가시 = 얼음 가시 + 빙결.
func _line_shot(k: String, t, length: float, dmg: float) -> void:
	var here: Vector3 = h.global_position
	var dir: Vector3 = _flat(t.global_position - here).normalized()
	if dir == Vector3.ZERO:
		dir = Vector3.FORWARD
	var w := _world()
	var end := here + dir * length
	var hits := _line_monsters(here, dir, length, 1.4 if k != "piercing_shot" else 1.2)
	match k:
		"piercing_shot":
			Fx.fly(w, "dart", h._color, here + MUZZLE, end + MUZZLE, 0.18)
			for o in hits:
				Fx.spark(w, o.global_position + HIT, h._color.lightened(0.3), 0.6)
		"boomerang":
			Fx.fly(w, "axe", h._color, here + MUZZLE, end + Vector3(0, 1.0, 0), 0.3, Vector3(0, 0, TAU * 3.0), true)
		"frost_spike":
			Fx.line(w, here, end, ICE, "ice_spikes", h._tier)
	for o in hits:
		_hit(o, dmg)
		if o.is_alive():
			match k:
				"boomerang":
					o.knockback(here, 1.5)
				"frost_spike":
					o.apply_freeze(0.8)


## 대상 자리 반경 r 효과(c = 표의 세 번째 숫자): 덫 · 들불 번지기 · 달빛 장막 · 역병의 저주 · 햇빛 파편 · 끓는 늪.
func _spot(k: String, at: Vector3, r: float, c: float, a: float) -> void:
	var w := _world()
	var tier: int = h._tier
	var hits := _near_monsters(at, r)
	var m: float = h._skill_mult
	match k:
		"snare":
			Fx.hands(w, at, r, Color(0.55, 0.42, 0.25))
			Fx.dust(w, at)
			for o in hits:
				_hit(o, a * 0.5 * m)
				if o.is_alive():
					o.apply_root(c)
		"firespread":
			Fx.blast(w, at, FIRE, r, false, tier)
			Fx.splash(w, at, FIRE, r * 1.2)
			for o in hits:
				_hit(o, a * c / 100.0 * m)
				if o.is_alive():
					o.apply_dot("burn", a * 0.15 * m, 3.0)
		"lunar_veil":
			Fx.beam(w, at, MOON, tier)
			Fx.nova(w, at, MOON, r, tier)
			for o in hits:
				_hit(o, a * 0.8 * m)
				if o.is_alive():
					o.apply_weaken(c, 3.0)
		"hex":
			Fx.zone(w, at, CURSE, r, 1.2, "poison_cloud", tier)
			for o in hits:
				o.apply_dot("curse", a * c / 100.0 * m, 4.0)
		"solar_spark":
			Fx.flare_burst(w, at, HOLY, r, tier)
			for o in hits:
				_hit(o, a * c / 100.0 * m)
				if o.is_alive():
					o.apply_weaken(30.0, 3.0)
		"magma":
			Fx.blast(w, at, FIRE, r, false, tier)
			for o in hits:
				_hit(o, a * c / 100.0 * m)
				if o.is_alive():
					o.knockback(at, 2.0)


## 바닥 지대(화염 지대·독구름·눈보라·회오리·성역): 0.5초마다 안의 적(성역은 아군)에게.
func _zone(k: String, p: Array, center: Vector3) -> void:
	var r := float(p[1])
	var a := _atk()
	var sec: float = {"inferno": 3.0, "poison_cloud": 4.0, "blizzard": 2.0, "tornado": 3.0, "sanctuary": 3.0}[k]
	var col: Color = {"inferno": FIRE, "poison_cloud": POISON, "blizzard": ICE, "tornado": Color(0.85, 0.95, 0.9), "sanctuary": HOLY}[k]
	Fx.zone(_world(), center, col, r, sec, k, h._tier)
	var gap := 1.0 if k == "sanctuary" else 0.5
	var ticks := int(round(sec / gap))
	for i in ticks:
		_later(gap * (i + 1), _zone_tick.bind(k, center, r, float(p[2]), a, gap))


## 지대 한 틱: 성역 = 안의 다친 아군 회복, 독구름 = 중독, 눈보라 = 피해 + 둔화, 화염 지대·회오리 = 초당 c% × 간격 (+ 화상 / 둔화).
func _zone_tick(k: String, center: Vector3, r: float, c: float, a: float, gap: float) -> void:
	match k:
		"sanctuary":
			for o in _hurt_allies(center, r):
				o.heal(o.hp_max * c / 100.0)
		"poison_cloud":
			for o in _near_monsters(center, r):
				o.apply_poison(a * c / 100.0 * h._skill_mult, 1.0)
		"blizzard":
			for o in _near_monsters(center, r):
				_hit(o, a * c / 100.0 * h._skill_mult)
				if o.is_alive():
					o.apply_slow(40.0, 1.0)
		_:
			for o in _near_monsters(center, r):
				_hit(o, a * c / 100.0 * gap * h._skill_mult)
				if o.is_alive():
					if k == "inferno":
						o.apply_dot("burn", a * 0.05 * h._skill_mult, 1.0)
					else:
						o.apply_slow(50.0, 0.6)


func _summon(k: String, dmg: float, sec: float) -> void:
	var script = load("res://scripts/summon.gd")
	if script == null:
		return
	var spec: Array = SUMMONS[k]
	for i in int(spec[1]):
		var s = script.new()
		s.setup(h, spec[0], dmg, sec, h._color)
		_world().add_child(s)
		var ang: float = TAU * (float(i) / spec[1]) + randf() * 0.5
		s.global_position = _flat(h.global_position) + Vector3(cos(ang), 0, sin(ang)) * 1.2


## 연사: 대상에게 화살 n발을 더(각각 피해 50%) — 맞으면 원래 타격 효과는 없다(숫자만).
func _barrage(m, n: int) -> void:
	var shot: Array = SHOTS.get(h.def.model, ["arrow", 30.0])
	var d: float = h.atk * h._aura_mult() * 0.5 * damage_mult(m, 0, false)  # atk_mult는 damage_mult에 이미 있다
	var mref: WeakRef = weakref(m)  # 지워진 노드를 람다가 담고 있지 않게
	for i in n:
		_later(0.08 * (i + 1), func():
			var mm = mref.get_ref()
			if not (mm != null and mm.is_alive() and is_instance_valid(h) and h.is_alive()):
				return
			var pr = ProjectileScript.new()
			pr.target = mm
			pr.kind = shot[0]
			pr.speed = shot[1]
			pr.color = h._color
			pr.on_hit = func(target):
				if is_instance_valid(target) and target.is_alive():
					_hit(target, d)
			_world().add_child(pr)
			pr.global_position = h.global_position + MUZZLE)


## 도탄: 가까운 다른 적으로 a번(5 m 안), 매번 피해 × b/100.
func _ricochet(first, d: float) -> void:
	var hit := [first]
	var cur = first
	var dmg: float = d
	for i in int(sk.ricochet[0]):
		var next = null
		for o in _near_monsters(cur.global_position, 5.0, cur):
			if not hit.has(o):
				next = o
				break
		if next == null:
			break
		dmg *= float(sk.ricochet[1]) / 100.0
		Fx.streak(_world(), cur.global_position + HIT, next.global_position + HIT, h._color)
		_hit(next, dmg * h._skill_mult)
		hit.append(next)
		cur = next


# --- 도우미 ---

## 스킬 피해 한 번(숫자 색 SKILL). 죽이면 처치 효과.
func _hit(m, dmg: float, was := -1) -> void:
	if not is_instance_valid(m) or not m.is_alive() or dmg <= 0.0:
		return
	var w := snap(m) if was < 0 else was
	m.take_damage(dmg, DamageNumbers.Kind.SKILL)
	if not m.is_alive():
		on_kill(m, w)


## 오라·강화를 넣은 지금 공격력.
func _atk() -> float:
	return h.atk * h._aura_mult() * atk_mult()


func _roll(k: String) -> bool:
	return sk.has(k) and randf() < float(sk[k][0]) / 100.0


func _announce(k: String) -> void:
	h._announce(k)


func _world() -> Node:
	return h.get_parent()


## 교전 중인 표적(살아 있고 사거리 안), 없으면 null.
func _combat_target():
	var t = h._target
	if t == null or not is_instance_valid(t) or not t.is_alive():
		return null
	return t if Formation.flat_distance(h.global_position, t.global_position) <= h._reach(t) + 0.5 else null


## 발동 사거리: 원거리는 사거리, 근접은 aggro.
func _reach() -> float:
	return float(h.def.range) if h.role == "ranged" else float(h.def.aggro)


func _strongest(r: float):
	var best = null
	for m in _near_monsters(h.global_position, r):
		if best == null or m.hp > best.hp:
			best = m
	return best


func _frailest(r: float):
	var best = null
	for m in _near_monsters(h.global_position, r):
		if best == null or m.hp_ratio() < best.hp_ratio():
			best = m
	return best


## HP 비율이 가장 낮은 다친 아군(자신 포함), 없으면 null.
func _weakest_ally(r: float):
	var best = null
	for o in _hurt_allies(h.global_position, r):
		if best == null or o.hp_ratio() < best.hp_ratio():
			best = o
	return best


func _hurt_allies(at: Vector3, r: float) -> Array:
	var out := []
	for o in h.get_tree().get_nodes_in_group(h.allies):
		if o.is_alive() and o.hp < o.hp_max and Formation.flat_distance(at, o.global_position) <= r:
			out.append(o)
	return out


func _near_monsters(at: Vector3, r: float, exclude = null) -> Array:
	var out := []
	for m in h.get_tree().get_nodes_in_group(h.foes):
		if m != exclude and m.is_alive():
			var mp: Vector3 = m.global_position
			var d := Vector2(mp.x - at.x, mp.z - at.z).length()
			if d <= r or d <= r + m.hit_radius():  # 큰 보스(드래곤)는 몸 바깥이 범위에 닿으면
				out.append(m)
	return out


## from에서 dir로 길이 length, 폭 width(양쪽 width/2) 띠 안의 적.
func _line_monsters(from: Vector3, dir: Vector3, length: float, width: float, exclude = null) -> Array:
	var out := []
	for m in h.get_tree().get_nodes_in_group(h.foes):
		if m == exclude or not m.is_alive():
			continue
		var v := _flat(m.global_position - from)
		var along := v.dot(dir)
		if along >= 0.0 and along <= length and (v - dir * along).length() <= width / 2.0 + m.radius() * 0.5:
			out.append(m)
	return out


## from에서 dir 쪽 반각 half 부채꼴, 길이 length 안의 적.
func _cone_monsters(from: Vector3, dir: Vector3, length: float, half: float) -> Array:
	var out := []
	for m in h.get_tree().get_nodes_in_group(h.foes):
		if not m.is_alive():
			continue
		var v := _flat(m.global_position - from)
		if v.length() <= length and (v.length() < 0.5 or v.normalized().angle_to(dir) <= half):
			out.append(m)
	return out


## 같은 표적을 연달아 치는지(광란 겹·집중 시간).
func _track_target(m) -> void:
	if m != _frenzy_m:
		_frenzy_m = m
		_frenzy_n = 0
	elif sk.has("frenzy"):
		_frenzy_n = mini(_frenzy_n + 1, int(sk.frenzy[1]))
	if m != _focus_m:
		_focus_m = m
		_focus_t = 0.0


func _later(sec: float, f: Callable) -> void:
	if sec <= 0.0:
		f.call()
		return
	h.get_tree().create_timer(sec, false).timeout.connect(func():
		if is_instance_valid(h) and h.is_inside_tree():
			f.call())


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)

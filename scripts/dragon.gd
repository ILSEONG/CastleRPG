extends "res://scripts/monster.gd"
## 길드 보스 드래곤(guild_boss.gd 장면). monster.gd 아레나 모드 그대로(영웅 스킬 상태·지속 피해·피해 숫자) + 다른 점:
## - 모델은 dragon_model.gd(부품을 코드로 움직인다). 제자리에 서서(speed 0, 사거리가 무대 전체) 가장 가까운 영웅 쪽을 보고
##   물기·불 뿜기·날개 바람을 차례로 한다. 공격력 = ATK_BASE × ATK_GROWTH^(단계 − 1)(atk_of), 맞은 영웅은 그만큼 체력이 깎인다
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
const ATK_BASE := 60.0  # 1단계 공격력(데스나이트 1단계와 같다) — 사용자 선택 대기(40·60·100)
const ATK_GROWTH := 1.12  # 보스 단계마다 공격력 ×(장비 던전 적 공격 성장과 같다)
const GUST_MULT := 0.5  # 날개 바람은 모두에게 공격력의 절반
const BREATH_DEG := 35.0  # 불 뿜기 부채꼴 반각

signal level_cleared(level: int)

var level := 1
var dealt := 0.0  # 이번 전투에서 받은 피해 합
var attacks := 0  # 테스트용
var closed := false  # 전투가 끝났다(날아오던 투사체 피해는 세지 않는다)


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


## 타격 순간: 물기 = 노린 영웅 한 명, 불 뿜기 = 입 앞 부채꼴(BREATH_DEG) 안 모두에게 공격력만큼, 날개 바람 = 모두에게 GUST_MULT배.
func _release() -> void:
	attacks += 1
	var h = _swing_hero
	_swing_hero = null
	var at: Vector3 = h.global_position if is_instance_valid(h) else global_position + Vector3.FORWARD.rotated(Vector3.UP, rotation.y) * 4.0
	var parent := get_parent()
	match str(_model.attack_kind):
		"breath":
			var m: Vector3 = _model.mouth()
			var dir := (at + Vector3(0, 0.6, 0) - m)
			var length := dir.length() + 1.5
			Fx.breath(parent, m, dir.normalized(), length, FIRE, 2)
			Fx.kick(parent, at, 0.25)
			var flat := Vector2(dir.x, dir.z).normalized()
			for x in _alive_heroes():
				var d := Vector2(x.global_position.x - m.x, x.global_position.z - m.z)
				if d.length() <= length and (d.length() < 0.5 or rad_to_deg(flat.angle_to(d.normalized())) <= BREATH_DEG):
					_hurt(x, 1.0)
		"gust":
			Fx.dust(parent, at)
			Fx.impact(parent, Vector3(at.x, 0.0, at.z), Color(0.9, 0.85, 0.7), 1.4, 1)
			for x in _alive_heroes():
				_hurt(x, GUST_MULT)
		_:
			Fx.impact(parent, Vector3(at.x, 0.0, at.z), FIRE, 1.2, 1)
			if is_instance_valid(h) and h.is_alive():
				_hurt(h, 1.0)


func _alive_heroes() -> Array:
	return get_tree().get_nodes_in_group("heroes").filter(func(x): return x.is_alive())


func _hurt(hero, mult: float) -> void:
	hero.take_damage(hit_damage() * mult, self)

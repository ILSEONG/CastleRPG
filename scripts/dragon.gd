extends "res://scripts/monster.gd"
## 길드 보스 드래곤(guild_boss.gd 장면). monster.gd 아레나 모드 그대로(영웅 스킬 상태·지속 피해·피해 숫자) + 다른 점:
## - 모델은 dragon_model.gd(부품을 코드로 움직인다). 제자리에 서서(speed 0, 사거리가 무대 전체) 가장 가까운 영웅 쪽을 보고
##   물기·불 뿜기·날개 바람을 차례로 한다. 길드 보스 피해 규칙에는 보스가 영웅에게 주는 피해가 없어서 공격은 연출만이다(영웅 HP는 그대로).
## - 쓰러지지 않는다: HP가 0이 되면 그 단계를 처치한 것(level_cleared) — 다음 단계 최대 HP로 차오르고 남은 피해는 넘긴다(서버 bossOf와 같다).
## - 받은 피해 합(dealt)이 이번 도전 피해다. 넉백·겹침 밀림 없음.
## 몸 반지름 reach_r만큼 영웅 사거리가 늘어난다(hit_radius — 근접 영웅이 큰 몸 바깥에서 친다).

const DragonModelScript := preload("res://scripts/dragon_model.gd")
const GuildScript := preload("res://scripts/guild.gd")

const SIZE := 6.5  # 키(m) — 영웅(2.2 m)의 세 배쯤
const REACH_R := 2.8  # 몸 반지름(m): 영웅은 이만큼 더 멀리서 친다
const ATK_INTERVAL := 2.6
const FIRE := Color(1.0, 0.45, 0.12)

signal level_cleared(level: int)

var level := 1
var dealt := 0.0  # 이번 전투에서 받은 피해 합
var attacks := 0  # 테스트용
var closed := false  # 전투가 끝났다(날아오던 투사체 피해는 세지 않는다)


## add_child 전에. p_level = 지금 보스 단계, p_hp = 남은 HP.
func setup_boss(p_level: int, p_hp: float) -> void:
	level = maxi(1, p_level)
	setup_arena({"kind": "dragon", "hp": maxf(1.0, p_hp), "atk": 0.0, "speed": 0.0, "range": 60.0, "atk_interval": ATK_INTERVAL,
		"aggro": 60.0, "scale": SIZE / 2.2})
	hp_max = GuildScript.boss_max(level)
	is_boss = true
	_atk_cd = 1.2  # 첫 공격은 잠깐 뒤


func _ready() -> void:
	add_to_group("monsters")
	_model = DragonModelScript.new()
	_model.size = SIZE
	add_child(_model)


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


## 타격 순간: 연출만(불 뿜기 = 입에서 영웅 쪽으로 불길, 물기·날개 바람 = 영웅 발밑 충격). 영웅 HP는 그대로.
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
			Fx.breath(parent, m, dir.normalized(), dir.length() + 1.5, FIRE, 2)
			Fx.kick(parent, at, 0.25)
		"gust":
			Fx.dust(parent, at)
			Fx.impact(parent, Vector3(at.x, 0.0, at.z), Color(0.9, 0.85, 0.7), 1.4, 1)
		_:
			Fx.impact(parent, Vector3(at.x, 0.0, at.z), FIRE, 1.2, 1)

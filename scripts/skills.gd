extends RefCounted
## 영웅 스킬(스펙 §3.2) 종류 표와 순수 수식. 노드·오토로드 참조 없음 → 헤드리스 테스트 가능.
## sk = 영웅 정의의 skills 사전 {종류: [a, b, c]} (GameData가 만든다). 빈 칸은 0.

## 종류 → 필요한 숫자 수(a, b, c 앞에서부터). 이 표에 없는 종류는 GameData가 거부한다.
const KINDS := {
	"heal_aura": 3, "atk_aura": 2, "dmg_reduce": 1, "dodge": 1, "thorns": 1, "lifesteal": 1, "haste": 1, "rage": 1,
	"crit": 2, "execute": 2, "boss_slayer": 1, "cleave": 2, "multishot": 1, "chain": 3, "aoe_blast": 3, "slow": 2,
	"stun": 2, "poison": 2, "gate_repair": 2,
}


## 공격 간격: haste a% → 간격 ÷ (1 + a/100). rage a% → 잃은 HP 비율만큼 속도 +a% (둘 다 있으면 더한다).
static func interval(sk: Dictionary, base: float, hp_ratio: float) -> float:
	var speed := 1.0
	if sk.has("haste"):
		speed += sk.haste[0] / 100.0
	if sk.has("rage"):
		speed += sk.rage[0] / 100.0 * clampf(1.0 - hp_ratio, 0.0, 1.0)
	return base / speed


## 한 대상에게 주는 피해. roll = [0,1) 난수(crit 판정). target_ratio = 대상 HP 비율.
static func damage(sk: Dictionary, atk: float, roll: float, target_ratio: float, boss: bool) -> float:
	var d := atk
	if sk.has("crit") and roll < sk.crit[0] / 100.0:
		d *= sk.crit[1] / 100.0
	if sk.has("execute") and target_ratio <= sk.execute[0] / 100.0:
		d *= 1.0 + sk.execute[1] / 100.0
	if boss and sk.has("boss_slayer"):
		d *= 1.0 + sk.boss_slayer[0] / 100.0
	return d


## 영웅이 받는 피해: dodge → dmg_reduce → thorns 순. 반환 Vector2(받은 피해, 공격자에게 되돌릴 피해). roll = dodge 판정 난수.
static func incoming(sk: Dictionary, amount: float, roll: float) -> Vector2:
	if sk.has("dodge") and roll < sk.dodge[0] / 100.0:
		return Vector2.ZERO
	var taken := amount
	if sk.has("dmg_reduce"):
		taken *= maxf(0.0, 1.0 - sk.dmg_reduce[0] / 100.0)
	var back := 0.0
	if sk.has("thorns"):
		back = taken * sk.thorns[0] / 100.0
	return Vector2(taken, back)


## chain: 튕길 때마다 피해 × b/100. 반환 = 튕김 1..a번째 피해.
static func chain_damages(sk: Dictionary, hit: float) -> Array[float]:
	var out: Array[float] = []
	if not sk.has("chain"):
		return out
	var d := hit
	for i in int(sk.chain[0]):
		d *= sk.chain[1] / 100.0
		out.append(d)
	return out


## stun: n번째 공격(1부터 센 번호)이 기절 공격인가.
static func stuns(sk: Dictionary, attack_no: int) -> bool:
	return sk.has("stun") and int(sk.stun[0]) > 0 and attack_no % int(sk.stun[0]) == 0


## atk_aura: 주변 영웅들의 오라 % 중 가장 큰 것 하나 → 공격력 배율.
static func aura_mult(best_pct: float) -> float:
	return 1.0 + maxf(0.0, best_pct) / 100.0

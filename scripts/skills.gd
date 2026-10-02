extends RefCounted
## 영웅 스킬(스펙 §3.2) 종류 표와 순수 수식. 노드·오토로드 참조 없음 → 헤드리스 테스트 가능.
## sk = 영웅 정의의 skills 사전 {종류: [a, b, c]} (GameData가 만든다). 빈 칸은 0.

## 종류 → 필요한 숫자 수(a, b, c 앞에서부터). 이 표에 없는 종류는 GameData가 거부한다.
const KINDS := {
	"heal_aura": 3, "atk_aura": 2, "dmg_reduce": 1, "dodge": 1, "thorns": 1, "lifesteal": 1, "haste": 1, "rage": 1,
	"crit": 2, "execute": 2, "boss_slayer": 1, "cleave": 2, "multishot": 1, "chain": 3, "aoe_blast": 3, "slow": 2,
	"stun": 2, "poison": 2, "gate_repair": 2,
}


## 종류 → 숫자(a, b, c 앞에서부터)의 허용 범위(GameData가 표를 읽을 때 본다). 개수는 KINDS와 같다.
## pos = 0보다 큼(쿨 0이면 매 프레임, 반경 0이면 무의미), nonneg = 0 이상, pct = 0..100, int1 = 1 이상 정수(multishot 0이면
## slice(0, -1), stun 2.5면 int로 잘려 2번째마다), mult = 100 이상(치명타 배수가 피해를 줄이지 않게).
const RULES := {
	"heal_aura": ["pos", "pos", "nonneg"], "atk_aura": ["pos", "nonneg"], "dmg_reduce": ["pct"], "dodge": ["pct"],
	"thorns": ["nonneg"], "lifesteal": ["nonneg"], "haste": ["nonneg"], "rage": ["nonneg"], "crit": ["pct", "mult"],
	"execute": ["pct", "nonneg"], "boss_slayer": ["nonneg"], "cleave": ["pos", "nonneg"], "multishot": ["int1"],
	"chain": ["int1", "pct", "pos"], "aoe_blast": ["pos", "pos", "nonneg"], "slow": ["pct", "pos"], "stun": ["int1", "pos"],
	"poison": ["nonneg", "pos"], "gate_repair": ["pos", "nonneg"],
}
const RULE_TEXT := {"pos": "greater than 0", "nonneg": "0 or more", "pct": "in 0..100", "int1": "an integer of 1 or more", "mult": "100 or more"}

## 종류 → 한국어 이름(영웅 창 상세).
const NAMES := {
	"heal_aura": "치유의 기도", "atk_aura": "용기의 오라", "dmg_reduce": "철벽", "dodge": "회피", "thorns": "가시 갑옷",
	"lifesteal": "흡혈", "haste": "신속", "rage": "광분", "crit": "치명타", "execute": "마무리 일격", "boss_slayer": "거인 사냥",
	"cleave": "휩쓸기", "multishot": "다중 사격", "chain": "연쇄", "aoe_blast": "폭발", "slow": "둔화", "stun": "기절",
	"poison": "독", "gate_repair": "성문 수리",
}

## 영웅별 이름(개정 17 §2 표의 괄호·§3 예시): 영웅 id → {종류: 이름}. 없으면 NAMES.
const HERO_NAMES := {"ignis": {"poison": "화상", "aoe_blast": "화염구"}}


## 스킬 이름(영웅별 이름이 있으면 그것).
static func name_of(kind: String, hero_id := "") -> String:
	return HERO_NAMES.get(hero_id, {}).get(kind, NAMES.get(kind, kind))


## 종류 → 설명 틀. {a}·{b}·{c} = 숫자, {bx} = b / 100(배수). 스펙 §3.2 표의 효과를 그대로 문장으로.
const TEXTS := {
	"heal_aura": "{a}초마다 반경 {b}m 안 아군 영웅(자신 포함)의 HP를 각자 최대 HP의 {c}%만큼 회복합니다.",
	"atk_aura": "반경 {a}m 안 다른 영웅의 공격력을 {b}% 올립니다(여럿이면 가장 큰 것 하나).",
	"dmg_reduce": "받는 피해를 {a}% 줄입니다.",
	"dodge": "{a}% 확률로 피해를 피합니다.",
	"thorns": "받은 피해의 {a}%를 공격한 적에게 되돌려 줍니다.",
	"lifesteal": "준 피해의 {a}%만큼 HP를 회복합니다.",
	"haste": "공격 속도가 {a}% 빨라집니다.",
	"rage": "잃은 HP 비율만큼 공격 속도가 빨라집니다(최대 {a}%).",
	"crit": "{a}% 확률로 {bx}배 피해를 줍니다.",
	"execute": "HP가 {a}% 이하인 적에게 피해를 {b}% 더 줍니다.",
	"boss_slayer": "보스에게 주는 피해가 {a}% 늘어납니다.",
	"cleave": "근접 공격 때 대상 주변 {a}m 안 다른 적에게 피해의 {b}%를 줍니다.",
	"multishot": "사거리 안 가까운 적 {a}마리를 동시에 공격합니다.",
	"chain": "맞은 적에서 {c}m 안 가장 가까운 다른 적으로 {a}번 튕기며, 튕길 때마다 피해가 {b}%가 됩니다.",
	"aoe_blast": "{a}초마다 대상 위치에 폭발을 일으켜 반경 {b}m 안 모든 적에게 공격력의 {c}% 피해를 줍니다.",
	"slow": "맞은 적의 이동 속도를 {b}초 동안 {a}% 늦춥니다.",
	"stun": "{a}번째 공격마다 대상을 {b}초 동안 기절시킵니다.",
	"poison": "맞은 적이 {b}초 동안 매초 공격력의 {a}% 독 피해를 입습니다.",
	"gate_repair": "{a}초마다 자기 면 성문 HP를 최대치의 {b}% 수리합니다(성문 앞이나 같은 면 성벽 위, 부서진 성문 제외).",
}


## 스킬 한 줄 설명(숫자 포함). nums = [a, b, c].
static func describe(kind: String, nums: Array) -> String:
	var t: String = TEXTS.get(kind, "")
	for i in 3:
		t = t.replace("{%s}" % "abc"[i], num_text(float(nums[i]) if i < nums.size() else 0.0))
	return t.replace("{bx}", num_text(float(nums[1]) / 100.0 if nums.size() > 1 else 0.0))


## 범위(RULES)를 벗어난 첫 숫자의 번호(0 = a), 다 맞으면 -1.
static func bad_num(kind: String, nums: Array) -> int:
	var rules: Array = RULES.get(kind, [])
	for i in rules.size():
		var v := float(nums[i])
		var ok := false
		match rules[i]:
			"pos": ok = v > 0.0
			"nonneg": ok = v >= 0.0
			"pct": ok = v >= 0.0 and v <= 100.0
			"int1": ok = v >= 1.0 and v == floorf(v)
			"mult": ok = v >= 100.0
		if not ok:
			return i
	return -1


## 3.5 → "3.5", 6.0 → "6", 0.8 → "0.8"(소수 둘째 자리까지).
static func num_text(v: float) -> String:
	var s := "%.2f" % v
	return s.rstrip("0").rstrip(".")


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

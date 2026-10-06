extends RefCounted
## 영웅 스킬(스펙 §3.2) 종류 표와 순수 수식. 노드·오토로드 참조 없음 → 헤드리스 테스트 가능.
## sk = 영웅 정의의 skills 사전 {종류: [a, b, c]} (GameData가 만든다). 빈 칸은 0.

## 종류 → 필요한 숫자 수(a, b, c 앞에서부터). 이 표에 없는 종류는 GameData가 거부한다.
const KINDS := {
	"heal_aura": 3, "atk_aura": 2, "dmg_reduce": 1, "dodge": 1, "thorns": 1, "lifesteal": 1, "haste": 1, "rage": 1,
	"crit": 2, "execute": 2, "boss_slayer": 1, "cleave": 2, "multishot": 1, "chain": 3, "aoe_blast": 3, "slow": 2,
	"stun": 2, "poison": 2, "gate_repair": 2,
	# 스킬 100종 확장(영웅 36명 × 고유 스킬): 광역 발동·지원·소환·타격 효과·처치 효과·피해 강화·방어·오라 — 적용은 hero_skills.gd
	"meteor": 3, "inferno": 3, "earthquake": 3, "ground_slam": 3, "blizzard": 3, "tornado": 3, "thunder_storm": 3, "arrow_rain": 3,
	"poison_cloud": 3, "frost_nova": 3, "whirlwind": 3, "war_cry": 3, "shockwave": 3, "spear_throw": 3, "ice_spikes": 3, "dragon_breath": 3,
	"starfall": 3, "sky_bolt": 3, "comet": 3, "holy_smite": 3, "shadow_strike": 2, "void_rift": 3, "solar_flare": 3, "abyss_hand": 3,
	"lava_burst": 3, "sanctuary": 3, "mass_heal": 2, "resurrection": 2, "battle_hymn": 3, "shield_ally": 2, "shield": 2, "taunt": 3,
	"summon_wolf": 3, "summon_skeleton": 3, "summon_golem": 3, "summon_treant": 3, "summon_spirit": 3, "summon_phoenix": 3, "summon_hawk": 3,
	"summon_turret": 3, "burn_hit": 3, "bleed_hit": 3, "curse_hit": 3, "freeze_hit": 2, "root_hit": 2, "shock_hit": 2, "knockback_hit": 2,
	"armor_break": 3, "weaken_hit": 3, "hunter_mark": 2, "double_strike": 1, "barrage": 2, "splash": 2, "pierce": 2, "ricochet": 2,
	"echo_strike": 3, "heavy_blow": 3, "corpse_explosion": 2, "soul_harvest": 2, "bloodlust": 2, "frost_shatter": 2, "wildfire": 2,
	"frenzy": 2, "last_stand": 2, "opportunist": 1, "pyromancy": 1, "first_strike": 1, "focus": 2, "sharpshooter": 1, "brawler": 2,
	"berserker": 2, "regen": 1, "revive": 1, "block": 2, "fortify": 1, "second_wind": 3, "invincible": 3, "stoneskin": 1, "counter": 2,
	"haste_aura": 2, "guard_aura": 2, "regen_aura": 2,
	# 2026-10-06 스킬 재구성(SSR·SR 액티브 2 + 패시브 1, R 액티브 1 + 패시브 1): 패시브에서 바뀐 액티브 · 액티브에서 바뀐 확률 발동 패시브
	"ignite": 3, "piercing_shot": 3, "blood_rage": 3, "frost_chain": 3, "rend": 3, "bulwark": 3, "crushing_blow": 3, "sunder": 3,
	"shield_bash": 3, "snare": 3, "blade_flurry": 3, "parry": 3, "fire_bolt": 3, "firespread": 3, "axe_volley": 3, "boomerang": 3,
	"spear_sweep": 3, "drain_slash": 3, "volley": 3, "wide_swing": 3, "cheap_shot": 3, "crescent": 3, "lunar_veil": 3, "howl": 3,
	"deep_freeze": 3, "hex": 3, "scorch": 3, "gale": 3, "solar_spark": 3, "frost_spike": 3, "magma": 3,
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
	"meteor": ["pos", "pos", "nonneg"], "inferno": ["pos", "pos", "nonneg"], "earthquake": ["pos", "pos", "nonneg"],
	"ground_slam": ["pos", "pos", "nonneg"], "blizzard": ["pos", "pos", "nonneg"], "tornado": ["pos", "pos", "nonneg"],
	"thunder_storm": ["pos", "pos", "nonneg"], "arrow_rain": ["pos", "pos", "nonneg"], "poison_cloud": ["pos", "pos", "nonneg"],
	"frost_nova": ["pos", "pos", "pos"], "whirlwind": ["pos", "pos", "nonneg"], "war_cry": ["pos", "pos", "pct"],
	"shockwave": ["pos", "pos", "nonneg"], "spear_throw": ["pos", "pos", "nonneg"], "ice_spikes": ["pos", "pos", "nonneg"],
	"dragon_breath": ["pos", "pos", "nonneg"], "starfall": ["pos", "int1", "nonneg"], "sky_bolt": ["pos", "int1", "nonneg"],
	"comet": ["pos", "pos", "nonneg"], "holy_smite": ["pos", "nonneg", "nonneg"], "shadow_strike": ["pos", "nonneg"],
	"void_rift": ["pos", "pos", "pct"], "solar_flare": ["pos", "pos", "nonneg"], "abyss_hand": ["pos", "pos", "pos"],
	"lava_burst": ["pos", "pos", "nonneg"], "sanctuary": ["pos", "pos", "nonneg"], "mass_heal": ["pos", "nonneg"],
	"resurrection": ["pos", "pct"], "battle_hymn": ["pos", "nonneg", "pos"], "shield_ally": ["pos", "nonneg"], "shield": ["pos", "nonneg"],
	"taunt": ["pos", "pos", "pos"], "summon_wolf": ["pos", "nonneg", "pos"], "summon_skeleton": ["pos", "nonneg", "pos"],
	"summon_golem": ["pos", "nonneg", "pos"], "summon_treant": ["pos", "nonneg", "pos"], "summon_spirit": ["pos", "nonneg", "pos"],
	"summon_phoenix": ["pos", "nonneg", "pos"], "summon_hawk": ["pos", "nonneg", "pos"], "summon_turret": ["pos", "nonneg", "pos"],
	"burn_hit": ["pct", "nonneg", "pos"], "bleed_hit": ["pct", "nonneg", "pos"], "curse_hit": ["pct", "nonneg", "pos"],
	"freeze_hit": ["pct", "pos"], "root_hit": ["pct", "pos"], "shock_hit": ["pct", "nonneg"], "knockback_hit": ["pct", "pos"],
	"armor_break": ["pct", "pct", "pos"], "weaken_hit": ["pct", "pct", "pos"], "hunter_mark": ["pct", "pos"], "double_strike": ["pct"],
	"barrage": ["pct", "int1"], "splash": ["pos", "nonneg"], "pierce": ["pos", "nonneg"], "ricochet": ["int1", "pct"],
	"echo_strike": ["int1", "pos", "nonneg"], "heavy_blow": ["int1", "mult", "nonneg"], "corpse_explosion": ["pos", "nonneg"],
	"soul_harvest": ["nonneg", "nonneg"], "bloodlust": ["nonneg", "pos"], "frost_shatter": ["pos", "nonneg"], "wildfire": ["pos", "nonneg"],
	"frenzy": ["nonneg", "int1"], "last_stand": ["pct", "nonneg"], "opportunist": ["nonneg"], "pyromancy": ["nonneg"],
	"first_strike": ["nonneg"], "focus": ["nonneg", "nonneg"], "sharpshooter": ["nonneg"], "brawler": ["nonneg", "nonneg"],
	"berserker": ["nonneg", "nonneg"], "regen": ["nonneg"], "revive": ["pct"], "block": ["pct", "pct"], "fortify": ["pct"],
	"second_wind": ["pct", "nonneg", "pos"], "invincible": ["pct", "pos", "pos"], "stoneskin": ["pct"], "counter": ["pct", "nonneg"],
	"haste_aura": ["pos", "nonneg"], "guard_aura": ["pos", "pct"], "regen_aura": ["pos", "nonneg"],
	"ignite": ["pos", "int1", "nonneg"], "piercing_shot": ["pos", "pos", "nonneg"], "blood_rage": ["pos", "pos", "nonneg"],
	"frost_chain": ["pos", "int1", "nonneg"], "rend": ["pos", "nonneg", "nonneg"], "bulwark": ["pos", "pos", "pct"],
	"crushing_blow": ["pos", "nonneg", "nonneg"], "sunder": ["pos", "pos", "pct"], "shield_bash": ["pos", "pos", "nonneg"],
	"snare": ["pos", "pos", "pos"], "blade_flurry": ["pos", "int1", "nonneg"], "parry": ["pos", "pos", "nonneg"],
	"fire_bolt": ["pos", "nonneg", "nonneg"], "firespread": ["pos", "pos", "nonneg"], "axe_volley": ["pos", "int1", "nonneg"],
	"boomerang": ["pos", "pos", "nonneg"], "spear_sweep": ["pos", "pos", "nonneg"], "drain_slash": ["pos", "nonneg", "nonneg"],
	"volley": ["pos", "int1", "nonneg"], "wide_swing": ["pos", "pos", "nonneg"], "cheap_shot": ["pos", "nonneg", "pos"],
	"crescent": ["pos", "pos", "nonneg"], "lunar_veil": ["pos", "pos", "pct"], "howl": ["pos", "pos", "nonneg"],
	"deep_freeze": ["pos", "int1", "pos"], "hex": ["pos", "pos", "nonneg"], "scorch": ["pct", "pos", "nonneg"],
	"gale": ["pct", "pos", "nonneg"], "solar_spark": ["pct", "pos", "nonneg"], "frost_spike": ["pct", "pos", "nonneg"],
	"magma": ["pct", "pos", "nonneg"],
}
const RULE_TEXT := {"pos": "greater than 0", "nonneg": "0 or more", "pct": "in 0..100", "int1": "an integer of 1 or more", "mult": "100 or more"}

## 종류 → 한국어 이름(영웅 창 상세).
const NAMES := {
	"heal_aura": "치유의 기도", "atk_aura": "용기의 오라", "dmg_reduce": "철벽", "dodge": "회피", "thorns": "가시 갑옷",
	"lifesteal": "흡혈", "haste": "신속", "rage": "광분", "crit": "치명타", "execute": "마무리 일격", "boss_slayer": "거인 사냥",
	"cleave": "휩쓸기", "multishot": "다중 사격", "chain": "연쇄", "aoe_blast": "폭발", "slow": "둔화", "stun": "기절",
	"poison": "독", "gate_repair": "성문 수리",
	"meteor": "메테오", "inferno": "화염 지대", "earthquake": "지진", "ground_slam": "대지 강타", "blizzard": "눈보라",
	"tornado": "회오리바람", "thunder_storm": "뇌우", "arrow_rain": "화살비", "poison_cloud": "독구름",
	"frost_nova": "서리 폭발", "whirlwind": "회오리 베기", "war_cry": "전투 함성", "shockwave": "충격파", "spear_throw": "창 투척",
	"ice_spikes": "얼음 가시", "dragon_breath": "용의 숨결", "starfall": "별똥별", "sky_bolt": "낙뢰", "comet": "혜성",
	"holy_smite": "심판의 빛", "shadow_strike": "그림자 습격", "void_rift": "공허 균열", "solar_flare": "태양 섬광",
	"abyss_hand": "심연의 손", "lava_burst": "용암 분출", "sanctuary": "성역", "mass_heal": "대치유",
	"resurrection": "부활의 기도", "battle_hymn": "전투 찬가", "shield_ally": "수호 축복", "shield": "보호막", "taunt": "도발",
	"summon_wolf": "늑대 소환", "summon_skeleton": "해골 병사", "summon_golem": "골렘 소환", "summon_treant": "나무 정령",
	"summon_spirit": "정령 소환", "summon_phoenix": "불사조", "summon_hawk": "매 부르기", "summon_turret": "포탑 설치",
	"burn_hit": "화상 타격", "bleed_hit": "출혈", "curse_hit": "저주", "freeze_hit": "빙결", "root_hit": "속박",
	"shock_hit": "감전", "knockback_hit": "밀쳐내기", "armor_break": "갑옷 파괴", "weaken_hit": "약화",
	"hunter_mark": "사냥꾼의 표식", "double_strike": "연속 공격", "barrage": "연사", "splash": "파편 튀기기", "pierce": "관통",
	"ricochet": "도탄", "echo_strike": "메아리 베기", "heavy_blow": "강타", "corpse_explosion": "시체 폭발",
	"soul_harvest": "영혼 수확", "bloodlust": "피의 갈망", "frost_shatter": "얼음 파편", "wildfire": "들불", "frenzy": "광란",
	"last_stand": "배수진", "opportunist": "약점 포착", "pyromancy": "화염 숙련", "first_strike": "기선 제압", "focus": "집중",
	"sharpshooter": "저격", "brawler": "난전", "berserker": "광전사", "regen": "재생", "revive": "불굴", "block": "방패 막기",
	"fortify": "요새화", "second_wind": "재기", "invincible": "금강불괴", "stoneskin": "돌 피부", "counter": "반격",
	"haste_aura": "질풍의 오라", "guard_aura": "수호의 오라", "regen_aura": "생명의 오라",
	"ignite": "점화", "piercing_shot": "관통 사격", "blood_rage": "피의 격노", "frost_chain": "서리 사슬", "rend": "난도질", "bulwark": "방벽",
	"crushing_blow": "분쇄 일격", "sunder": "갑옷 가르기", "shield_bash": "방패 밀치기", "snare": "덫", "blade_flurry": "칼날 난무", "parry": "받아치기",
	"fire_bolt": "화염탄", "firespread": "들불 번지기", "axe_volley": "도끼 세례", "boomerang": "회전 도끼", "spear_sweep": "창 휩쓸기",
	"drain_slash": "흡혈 베기", "volley": "연발 사격", "wide_swing": "크게 휘두르기", "cheap_shot": "급소 찌르기", "crescent": "초승달 베기",
	"lunar_veil": "달빛 장막", "howl": "야성의 포효", "deep_freeze": "급속 냉동", "hex": "역병의 저주", "scorch": "불바다", "gale": "돌개바람",
	"solar_spark": "햇빛 파편", "frost_spike": "서리 가시", "magma": "끓는 늪",
}

## 영웅별 이름(개정 17 §2 표의 괄호·§3 예시): 영웅 id → {종류: 이름}. 없으면 NAMES.
const HERO_NAMES := {"ignis": {"poison": "화상", "aoe_blast": "화염구"}}
const BURN_POISON := ["ignis"]  # 이 영웅들의 poison은 화상(burn 도트)으로 들어간다 — 화염 숙련 등 화상 연계에 걸린다
const BOSS_SLAYER_OTHERS := 0.2  # 거인 사냥: 보스가 아닌 적에게는 1/5(2026-10-06 밸런스)


## 스킬 이름(영웅별 이름이 있으면 그것).
static func name_of(kind: String, hero_id := "") -> String:
	return HERO_NAMES.get(hero_id, {}).get(kind, NAMES.get(kind, kind))


## 종류 → 설명 틀. {a}·{b}·{c} = 숫자, {bx} = b / 100(배수). 스펙 §3.2 표의 효과를 그대로 문장으로.
const TEXTS := {
	"heal_aura": "{a}초마다 반경 {b}m 안 아군 영웅(자신 포함)의 HP를 각자 최대 HP의 {c}%만큼 회복합니다.",
	"atk_aura": "반경 {a}m 안 다른 영웅의 공격력을 {b}% 올립니다(여럿이면 가장 큰 것 하나).",
	"dmg_reduce": "받는 피해를 {a}% 줄입니다.",
	"dodge": "{a}% 확률로 피해를 피합니다.",
	"thorns": "맞으면 받은 피해의 {a}%와 공격력의 {a}% 중 큰 만큼 공격한 적에게 되돌려 줍니다.",
	"lifesteal": "준 피해의 {a}%만큼 HP를 회복합니다.",
	"haste": "공격 속도가 {a}% 빨라집니다.",
	"rage": "잃은 HP 비율만큼 공격 속도가 빨라집니다(최대 {a}%).",
	"crit": "{a}% 확률로 {bx}배 피해를 줍니다.",
	"execute": "HP가 {a}% 이하인 적에게 피해를 {b}% 더 줍니다.",
	"boss_slayer": "보스에게 주는 피해가 {a}% 늘어납니다(다른 적에게는 그 1/5).",
	"cleave": "근접 공격 때 대상 주변 {a}m 안 다른 적에게 피해의 {b}%를 줍니다.",
	"multishot": "사거리 안 가까운 적 {a}마리를 동시에 공격합니다.",
	"chain": "맞은 적에서 {c}m 안 가장 가까운 다른 적으로 {a}번 튕기며, 튕길 때마다 피해가 {b}%가 됩니다.",
	"aoe_blast": "{a}초마다 대상 위치에 폭발을 일으켜 반경 {b}m 안 모든 적에게 공격력의 {c}% 피해를 줍니다.",
	"slow": "맞은 적의 이동 속도를 {b}초 동안 {a}% 늦춥니다.",
	"stun": "{a}번째 공격마다 대상을 {b}초 동안 기절시킵니다.",
	"poison": "맞은 적이 {b}초 동안 매초 공격력의 {a}% 독 피해를 입습니다.",
	"gate_repair": "{a}초마다 자기 면 성문 HP를 최대치의 {b}% 수리합니다(성문 앞이나 같은 면 성벽 위, 부서진 성문 제외).",
	"meteor": "{a}초마다 대상 위치에 운석을 떨어뜨려 반경 {b}m 안 적에게 공격력의 {c}% 피해를 주고 불태웁니다.",
	"inferno": "{a}초마다 대상 위치 반경 {b}m를 3초 동안 불태워 안의 적에게 매초 공격력의 {c}% 피해를 줍니다.",
	"earthquake": "{a}초마다 땅을 흔들어 반경 {b}m 안 적에게 공격력의 {c}% 피해를 주고 1초 기절시킵니다.",
	"ground_slam": "{a}초마다 땅을 내리쳐 반경 {b}m 안 적에게 공격력의 {c}% 피해를 주고 밀쳐냅니다.",
	"blizzard": "{a}초마다 대상 위치 반경 {b}m에 눈보라를 일으켜 2초 동안 4번, 공격력의 {c}% 피해를 주고 늦춥니다.",
	"tornado": "{a}초마다 대상 위치에 회오리를 일으켜 3초 동안 반경 {b}m 안 적에게 매초 공격력의 {c}% 피해를 주고 늦춥니다.",
	"thunder_storm": "{a}초마다 대상 위치 반경 {b}m에 번개를 5번 내리쳐 각각 맞은 곳 주변 적에게 공격력의 {c}% 피해를 줍니다.",
	"arrow_rain": "{a}초마다 대상 위치 반경 {b}m에 화살비를 3번 퍼부어 각각 공격력의 {c}% 피해를 줍니다.",
	"poison_cloud": "{a}초마다 대상 위치 반경 {b}m에 4초 동안 독구름을 깔아 안의 적을 매초 공격력의 {c}% 독에 중독시킵니다.",
	"frost_nova": "{a}초마다 주변 반경 {b}m 적에게 공격력의 80% 피해를 주고 {c}초 동안 얼립니다.",
	"whirlwind": "{a}초마다 제자리에서 세 바퀴 돌며 반경 {b}m 안 적에게 각각 공격력의 {c}% 피해를 줍니다.",
	"war_cry": "{a}초마다 함성을 질러 반경 {b}m 안 적의 공격력을 4초 동안 {c}% 낮춥니다.",
	"shockwave": "{a}초마다 대상 쪽으로 길이 {b}m 충격파를 날려 닿는 적에게 공격력의 {c}% 피해를 줍니다.",
	"spear_throw": "{a}초마다 대상 쪽으로 창을 던져 길이 {b}m 일직선의 적을 꿰뚫어 공격력의 {c}% 피해를 줍니다.",
	"ice_spikes": "{a}초마다 대상 쪽으로 길이 {b}m 얼음 가시를 솟게 해 공격력의 {c}% 피해를 주고 0.8초 얼립니다.",
	"dragon_breath": "{a}초마다 대상 쪽 {b}m 부채꼴에 불을 뿜어 공격력의 {c}% 피해를 주고 불태웁니다.",
	"starfall": "{a}초마다 사거리 안 적 최대 {b}마리에게 별똥별을 떨어뜨려 각각 공격력의 {c}% 피해를 줍니다.",
	"sky_bolt": "{a}초마다 사거리 안 적 최대 {b}마리에게 하늘에서 번개를 내리쳐 공격력의 {c}% 피해를 주고 잠깐 기절시킵니다.",
	"comet": "{a}초마다 사거리 안에서 HP가 가장 많은 적에게 혜성을 떨어뜨려 반경 {b}m 안 적에게 공격력의 {c}% 피해를 줍니다.",
	"holy_smite": "{a}초마다 사거리 안에서 HP가 가장 많은 적에게 빛기둥을 내려 공격력의 {b}% 피해를 주고, 준 피해의 {c}%만큼 가장 다친 아군을 치유합니다.",
	"shadow_strike": "{a}초마다 주변에서 HP 비율이 가장 낮은 적의 그림자에서 나타나 공격력의 {b}% 피해를 줍니다.",
	"void_rift": "{a}초마다 대상 위치 반경 {b}m에 균열을 열어 공격력의 60% 피해를 주고 5초 동안 받는 피해를 {c}% 늘립니다.",
	"solar_flare": "{a}초마다 대상 위치 반경 {b}m에 섬광을 터뜨려 공격력의 {c}% 피해를 주고 3초 동안 공격력을 30% 낮춥니다.",
	"abyss_hand": "{a}초마다 대상 위치 반경 {b}m 안 적을 {c}초 동안 붙잡고 공격력의 50% 피해를 줍니다.",
	"lava_burst": "{a}초마다 대상 위치 반경 {b}m에 용암을 뿜어 공격력의 {c}% 피해를 주고 밀쳐냅니다.",
	"sanctuary": "{a}초마다 3초 동안 반경 {b}m 성역을 펼쳐 안의 아군 영웅을 매초 최대 HP의 {c}% 회복합니다.",
	"mass_heal": "{a}초마다 모든 아군 영웅의 HP를 각자 최대 HP의 {b}% 회복합니다.",
	"resurrection": "{a}초마다 쓰러진 아군 영웅 하나를 최대 HP의 {b}%로 되살립니다.",
	"battle_hymn": "{a}초마다 모든 아군 영웅의 공격력을 {c}초 동안 {b}% 올립니다.",
	"shield_ally": "{a}초마다 가장 다친 아군 영웅에게 최대 HP의 {b}% 보호막을 씌웁니다.",
	"shield": "{a}초마다 자신에게 최대 HP의 {b}% 보호막을 씌웁니다.",
	"taunt": "{a}초마다 반경 {b}m 안 적이 {c}초 동안 자신만 노리게 합니다.",
	"summon_wolf": "{a}초마다 늑대 두 마리를 {c}초 동안 불러 공격력의 {b}% 피해로 싸우게 합니다.",
	"summon_skeleton": "{a}초마다 해골 병사 두 기를 {c}초 동안 일으켜 공격력의 {b}% 피해로 싸우게 합니다.",
	"summon_golem": "{a}초마다 골렘을 {c}초 동안 불러 공격력의 {b}% 피해로 적을 밀쳐내게 합니다.",
	"summon_treant": "{a}초마다 나무 정령을 {c}초 동안 불러 공격력의 {b}% 피해로 적을 붙잡게 합니다.",
	"summon_spirit": "{a}초마다 정령을 {c}초 동안 불러 공격력의 {b}% 마력탄을 쏘게 합니다.",
	"summon_phoenix": "{a}초마다 불사조를 {c}초 동안 불러 공격력의 {b}% 불꽃으로 적을 불태우게 합니다.",
	"summon_hawk": "{a}초마다 매를 {c}초 동안 불러 공격력의 {b}% 피해로 적을 덮치게 합니다.",
	"summon_turret": "{a}초마다 포탑을 {c}초 동안 세워 공격력의 {b}% 화살을 쏘게 합니다.",
	"burn_hit": "공격이 {a}% 확률로 적을 {c}초 동안 불태워 매초 공격력의 {b}% 피해를 줍니다.",
	"bleed_hit": "공격이 {a}% 확률로 {c}초 동안 출혈을 일으켜 매초 공격력의 {b}% 피해를 줍니다.",
	"curse_hit": "공격이 {a}% 확률로 {c}초 동안 저주를 걸어 매초 공격력의 {b}% 피해를 줍니다.",
	"freeze_hit": "공격이 {a}% 확률로 적을 {b}초 동안 얼립니다.",
	"root_hit": "공격이 {a}% 확률로 적을 {b}초 동안 묶어 움직이지 못하게 합니다.",
	"shock_hit": "공격이 {a}% 확률로 대상에게 번개를 떨어뜨려 공격력의 {b}% 피해를 더 줍니다.",
	"knockback_hit": "공격이 {a}% 확률로 적을 {b}m 밀쳐냅니다.",
	"armor_break": "공격이 {a}% 확률로 적이 {c}초 동안 받는 피해를 {b}% 늘립니다.",
	"weaken_hit": "공격이 {a}% 확률로 적의 공격력을 {c}초 동안 {b}% 낮춥니다.",
	"hunter_mark": "맞은 적에게 표식을 남겨 {b}초 동안 받는 피해를 {a}% 늘립니다.",
	"double_strike": "공격이 {a}% 확률로 한 번 더 들어갑니다.",
	"barrage": "공격이 {a}% 확률로 화살 {b}발을 더 쏩니다(각각 피해 50%).",
	"splash": "맞은 적 주변 {a}m 안 다른 적에게 피해의 {b}%를 줍니다.",
	"pierce": "대상 뒤 {a}m 안 일직선의 적에게도 피해의 {b}%를 줍니다.",
	"ricochet": "맞힌 뒤 가까운 다른 적에게 {a}번 튕기며, 튕길 때마다 피해가 {b}%가 됩니다.",
	"echo_strike": "{a}번째 공격마다 대상 주변 반경 {b}m에 충격파를 일으켜 공격력의 {c}% 피해를 줍니다.",
	"heavy_blow": "{a}번째 공격마다 {bx}배 피해를 주고 대상을 {c}m 밀쳐냅니다.",
	"corpse_explosion": "처치한 적이 터져 반경 {a}m 안 적에게 공격력의 {b}% 피해를 줍니다.",
	"soul_harvest": "적을 처치하면 최대 HP의 {a}%를 회복하고 5초 동안 공격력이 {b}% 오릅니다(5번까지 겹침).",
	"bloodlust": "적을 처치하면 {b}초 동안 공격 속도가 {a}% 빨라집니다.",
	"frost_shatter": "느려지거나 얼어 있던 적을 처치하면 얼음이 터져 반경 {a}m 안 적에게 공격력의 {b}% 피해를 줍니다.",
	"wildfire": "불타던 적을 처치하면 반경 {a}m 안 적에게 불이 옮겨 붙어 3초 동안 매초 공격력의 {b}% 피해를 줍니다.",
	"frenzy": "같은 적을 연달아 칠 때마다 공격 속도가 {a}%씩 빨라집니다(최대 {b}번).",
	"last_stand": "HP가 {a}% 이하이면 공격력이 {b}% 오릅니다.",
	"opportunist": "느려지거나 기절·빙결·속박된 적에게 피해를 {a}% 더 줍니다.",
	"pyromancy": "불타는 적에게 피해를 {a}% 더 줍니다.",
	"first_strike": "HP가 90% 이상인 적에게 피해를 {a}% 더 줍니다.",
	"focus": "같은 적을 공격하는 동안 1초마다 피해가 {a}%씩 늘어납니다(최대 {b}%).",
	"sharpshooter": "사거리 절반보다 먼 적에게 피해를 {a}% 더 줍니다.",
	"brawler": "주변 3m 안 적 하나마다 피해가 {a}% 늘어납니다(최대 {b}%).",
	"berserker": "공격력이 {a}% 오르지만 받는 피해가 {b}% 늘어납니다.",
	"regen": "매초 최대 HP의 {a}%를 회복합니다.",
	"revive": "쓰러지면 한 번, 최대 HP의 {a}%로 다시 일어납니다(리필마다 다시 생깁니다).",
	"block": "{a}% 확률로 받는 피해를 {b}% 막습니다.",
	"fortify": "자기 자리를 지키는 동안 받는 피해를 {a}% 줄입니다.",
	"second_wind": "HP가 {a}% 아래로 떨어지면 최대 HP의 {b}%를 회복합니다({c}초에 한 번).",
	"invincible": "HP가 {a}% 아래로 떨어지면 {b}초 동안 피해를 받지 않습니다({c}초에 한 번).",
	"stoneskin": "받는 피해가 {a}% 줄어듭니다.",
	"counter": "맞으면 {a}% 확률로 공격한 적에게 공격력의 {b}% 피해로 반격합니다.",
	"haste_aura": "반경 {a}m 안 아군 영웅(자신 포함)의 공격 속도가 {b}% 빨라집니다(여럿이면 가장 큰 것 하나).",
	"guard_aura": "반경 {a}m 안 아군 영웅(자신 포함)이 받는 피해가 {b}% 줄어듭니다(여럿이면 가장 큰 것 하나).",
	"regen_aura": "반경 {a}m 안 아군 영웅(자신 포함)이 매초 최대 HP의 {b}%를 회복합니다(여럿이면 가장 큰 것 하나).",	"ignite": "{a}초마다 사거리 안 적 최대 {b}마리에게 불을 붙여 3초 동안 매초 공격력의 {c}% 화상 피해를 줍니다.",
	"piercing_shot": "{a}초마다 대상 쪽으로 길이 {b}m를 꿰뚫는 화살을 쏘아 닿는 적 모두에게 공격력의 {c}% 피해를 줍니다.",
	"blood_rage": "{a}초마다 포효하며 {b}초 동안 공격 속도가 {c}% 빨라집니다.",
	"frost_chain": "{a}초마다 대상에게 얼음 번개를 쏘아 가까운 적으로 {b}번 튕기며, 맞은 적마다 공격력의 {c}% 피해를 주고 2초 동안 40% 늦춥니다.",
	"rend": "{a}초마다 대상을 난도질해 공격력의 {b}% 피해를 주고 3초 동안 매초 공격력의 {c}% 출혈 피해를 줍니다.",
	"bulwark": "{a}초마다 방패를 세워 {b}초 동안 받는 피해를 {c}% 줄이고, 주변 적이 자신을 노리게 합니다.",
	"crushing_blow": "{a}초마다 대상에게 공격력의 {b}% 일격을 내리치고 {c}m 밀쳐냅니다.",
	"sunder": "{a}초마다 주변 반경 {b}m 적을 베어 공격력의 100% 피해를 주고 4초 동안 받는 피해를 {c}% 늘립니다.",
	"shield_bash": "{a}초마다 방패로 주변 반경 {b}m 적을 밀쳐 공격력의 {c}% 피해를 주고 1초 기절시킵니다.",
	"snare": "{a}초마다 대상 위치에 덫을 던져 반경 {b}m 적에게 공격력의 50% 피해를 주고 {c}초 동안 묶습니다.",
	"blade_flurry": "{a}초마다 대상을 {b}번 연달아 베어 각각 공격력의 {c}% 피해를 줍니다.",
	"parry": "{a}초마다 {b}초 동안 받는 공격을 모두 막고, 막을 때마다 공격한 적에게 공격력의 {c}% 피해로 반격합니다.",
	"fire_bolt": "{a}초마다 대상에게 화염탄을 쏘아 공격력의 {b}% 피해를 주고 3초 동안 매초 공격력의 {c}% 화상 피해를 줍니다.",
	"firespread": "{a}초마다 대상 위치 반경 {b}m에 불길을 번지게 해 공격력의 {c}% 피해를 주고 3초 동안 매초 공격력의 15% 화상 피해를 줍니다.",
	"axe_volley": "{a}초마다 사거리 안 적 최대 {b}마리에게 도끼를 던져 각각 공격력의 {c}% 피해를 줍니다.",
	"boomerang": "{a}초마다 대상 쪽으로 길이 {b}m 회전 도끼를 던져 닿는 적에게 공격력의 {c}% 피해를 주고 1.5m 밀쳐냅니다.",
	"spear_sweep": "{a}초마다 창을 크게 휘둘러 앞쪽 {b}m 부채꼴 적에게 공격력의 {c}% 피해를 주고 1m 밀쳐냅니다.",
	"drain_slash": "{a}초마다 대상을 베어 공격력의 {b}% 피해를 주고 준 피해의 {c}%만큼 HP를 회복합니다.",
	"volley": "{a}초마다 대상에게 화살 {b}발을 연달아 쏘아 각각 공격력의 {c}% 피해를 줍니다.",
	"wide_swing": "{a}초마다 도끼를 크게 휘둘러 주변 반경 {b}m 적에게 공격력의 {c}% 피해를 줍니다.",
	"cheap_shot": "{a}초마다 대상의 급소를 찔러 공격력의 {b}% 피해를 주고 {c}초 기절시킵니다.",
	"crescent": "{a}초마다 앞쪽 {b}m 부채꼴에 초승달 참격을 날려 공격력의 {c}% 피해를 줍니다.",
	"lunar_veil": "{a}초마다 대상 위치 반경 {b}m에 달빛을 내려 공격력의 80% 피해를 주고 3초 동안 공격력을 {c}% 낮춥니다.",
	"howl": "{a}초마다 포효해 반경 {b}m 안 아군 영웅(자신 포함)의 HP를 최대 HP의 {c}%만큼 회복합니다.",
	"deep_freeze": "{a}초마다 사거리 안 적 최대 {b}마리를 {c}초 동안 얼립니다.",
	"hex": "{a}초마다 대상 위치 반경 {b}m 적에게 4초 동안 저주를 걸어 매초 공격력의 {c}% 피해를 줍니다.",
	"scorch": "공격이 {a}% 확률로 맞은 자리 반경 {b}m를 3초 동안 불태워 안의 적에게 매초 공격력의 {c}% 피해를 줍니다.",
	"gale": "공격이 {a}% 확률로 맞은 자리에 회오리를 일으켜 3초 동안 반경 {b}m 안 적에게 매초 공격력의 {c}% 피해를 주고 늦춥니다.",
	"solar_spark": "공격이 {a}% 확률로 맞은 자리에 섬광을 터뜨려 반경 {b}m 적에게 공격력의 {c}% 피해를 주고 3초 동안 공격력을 30% 낮춥니다.",
	"frost_spike": "공격이 {a}% 확률로 대상 쪽으로 길이 {b}m 얼음 가시를 솟게 해 공격력의 {c}% 피해를 주고 0.8초 얼립니다.",
	"magma": "공격이 {a}% 확률로 맞은 자리에 용암을 뿜어 반경 {b}m 적에게 공격력의 {c}% 피해를 주고 밀쳐냅니다.",
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
	if sk.has("boss_slayer"):
		d *= 1.0 + sk.boss_slayer[0] / 100.0 * (1.0 if boss else BOSS_SLAYER_OTHERS)
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

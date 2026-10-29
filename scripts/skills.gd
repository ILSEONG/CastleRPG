extends RefCounted
## 영웅 스킬(스펙 §3.2) 종류 표와 순수 수식. 노드·오토로드 참조 없음 → 헤드리스 테스트 가능.
## sk = 영웅 정의의 skills 사전 {종류: [a, b, c]} (GameData가 만든다). 빈 칸은 0.

const Lang := preload("res://scripts/lang.gd")

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
	# 2026-10-29 태생 UR 전용(영웅마다 액티브 · 패시브 · 궁극기) — 적용은 hero_skills.gd _cast_ur·_ur_hit
	"turtle_ward": 3, "black_shell": 2, "north_tide": 3, "tiger_claw": 3, "tiger_fury": 3, "tiger_avatar": 3, "fox_fire": 3, "fox_charm": 3, "nine_tails": 3, "dragon_arrow": 3, "azure_tide": 3, "azure_dragon": 3, "time_stop": 3, "time_haste": 1, "time_collapse": 3, "phoenix_wing": 3, "phoenix_blessing": 2, "rebirth_flame": 3,
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
	"turtle_ward": ["pos", "pos", "nonneg"],
	"black_shell": ["pct", "nonneg"],
	"north_tide": ["pos", "pos", "nonneg"],
	"tiger_claw": ["pos", "pos", "nonneg"],
	"tiger_fury": ["int1", "pos", "nonneg"],
	"tiger_avatar": ["pos", "pos", "nonneg"],
	"fox_fire": ["pos", "int1", "nonneg"],
	"fox_charm": ["pct", "pos", "pct"],
	"nine_tails": ["pos", "pos", "nonneg"],
	"dragon_arrow": ["pos", "pos", "nonneg"],
	"azure_tide": ["nonneg", "pct", "pos"],
	"azure_dragon": ["pos", "pos", "nonneg"],
	"time_stop": ["pos", "pos", "pos"],
	"time_haste": ["nonneg"],
	"time_collapse": ["pos", "pos", "nonneg"],
	"phoenix_wing": ["pos", "nonneg", "nonneg"],
	"phoenix_blessing": ["nonneg", "pos"],
	"rebirth_flame": ["pos", "pct", "pct"],
}
const RULE_TEXT := {"pos": "greater than 0", "nonneg": "0 or more", "pct": "in 0..100", "int1": "an integer of 1 or more", "mult": "100 or more"}

## 종류 → 한국어 이름(영웅 창 상세).
static var NAMES := {
	"heal_aura": Lang.t("skills.names.heal_aura"), "atk_aura": Lang.t("skills.names.atk_aura"), "dmg_reduce": Lang.t("skills.names.dmg_reduce"), "dodge": Lang.t("skills.names.dodge"), "thorns": Lang.t("skills.names.thorns"),
	"lifesteal": Lang.t("skills.names.lifesteal"), "haste": Lang.t("skills.names.haste"), "rage": Lang.t("skills.names.rage"), "crit": Lang.t("skills.names.crit"), "execute": Lang.t("skills.names.execute"), "boss_slayer": Lang.t("skills.names.boss_slayer"),
	"cleave": Lang.t("skills.names.cleave"), "multishot": Lang.t("skills.names.multishot"), "chain": Lang.t("skills.names.chain"), "aoe_blast": Lang.t("skills.names.aoe_blast"), "slow": Lang.t("skills.names.slow"), "stun": Lang.t("skills.names.stun"),
	"poison": Lang.t("skills.names.poison"), "gate_repair": Lang.t("skills.names.gate_repair"),
	"meteor": Lang.t("skills.names.meteor"), "inferno": Lang.t("skills.names.inferno"), "earthquake": Lang.t("skills.names.earthquake"), "ground_slam": Lang.t("skills.names.ground_slam"), "blizzard": Lang.t("skills.names.blizzard"),
	"tornado": Lang.t("skills.names.tornado"), "thunder_storm": Lang.t("skills.names.thunder_storm"), "arrow_rain": Lang.t("skills.names.arrow_rain"), "poison_cloud": Lang.t("skills.names.poison_cloud"),
	"frost_nova": Lang.t("skills.names.frost_nova"), "whirlwind": Lang.t("skills.names.whirlwind"), "war_cry": Lang.t("skills.names.war_cry"), "shockwave": Lang.t("skills.names.shockwave"), "spear_throw": Lang.t("skills.names.spear_throw"),
	"ice_spikes": Lang.t("skills.names.ice_spikes"), "dragon_breath": Lang.t("skills.names.dragon_breath"), "starfall": Lang.t("skills.names.starfall"), "sky_bolt": Lang.t("skills.names.sky_bolt"), "comet": Lang.t("skills.names.comet"),
	"holy_smite": Lang.t("skills.names.holy_smite"), "shadow_strike": Lang.t("skills.names.shadow_strike"), "void_rift": Lang.t("skills.names.void_rift"), "solar_flare": Lang.t("skills.names.solar_flare"),
	"abyss_hand": Lang.t("skills.names.abyss_hand"), "lava_burst": Lang.t("skills.names.lava_burst"), "sanctuary": Lang.t("skills.names.sanctuary"), "mass_heal": Lang.t("skills.names.mass_heal"),
	"resurrection": Lang.t("skills.names.resurrection"), "battle_hymn": Lang.t("skills.names.battle_hymn"), "shield_ally": Lang.t("skills.names.shield_ally"), "shield": Lang.t("skills.names.shield"), "taunt": Lang.t("skills.names.taunt"),
	"summon_wolf": Lang.t("skills.names.summon_wolf"), "summon_skeleton": Lang.t("skills.names.summon_skeleton"), "summon_golem": Lang.t("skills.names.summon_golem"), "summon_treant": Lang.t("skills.names.summon_treant"),
	"summon_spirit": Lang.t("skills.names.summon_spirit"), "summon_phoenix": Lang.t("skills.names.summon_phoenix"), "summon_hawk": Lang.t("skills.names.summon_hawk"), "summon_turret": Lang.t("skills.names.summon_turret"),
	"burn_hit": Lang.t("skills.names.burn_hit"), "bleed_hit": Lang.t("skills.names.bleed_hit"), "curse_hit": Lang.t("skills.names.curse_hit"), "freeze_hit": Lang.t("skills.names.freeze_hit"), "root_hit": Lang.t("skills.names.root_hit"),
	"shock_hit": Lang.t("skills.names.shock_hit"), "knockback_hit": Lang.t("skills.names.knockback_hit"), "armor_break": Lang.t("skills.names.armor_break"), "weaken_hit": Lang.t("skills.names.weaken_hit"),
	"hunter_mark": Lang.t("skills.names.hunter_mark"), "double_strike": Lang.t("skills.names.double_strike"), "barrage": Lang.t("skills.names.barrage"), "splash": Lang.t("skills.names.splash"), "pierce": Lang.t("skills.names.pierce"),
	"ricochet": Lang.t("skills.names.ricochet"), "echo_strike": Lang.t("skills.names.echo_strike"), "heavy_blow": Lang.t("skills.names.heavy_blow"), "corpse_explosion": Lang.t("skills.names.corpse_explosion"),
	"soul_harvest": Lang.t("skills.names.soul_harvest"), "bloodlust": Lang.t("skills.names.bloodlust"), "frost_shatter": Lang.t("skills.names.frost_shatter"), "wildfire": Lang.t("skills.names.wildfire"), "frenzy": Lang.t("skills.names.frenzy"),
	"last_stand": Lang.t("skills.names.last_stand"), "opportunist": Lang.t("skills.names.opportunist"), "pyromancy": Lang.t("skills.names.pyromancy"), "first_strike": Lang.t("skills.names.first_strike"), "focus": Lang.t("skills.names.focus"),
	"sharpshooter": Lang.t("skills.names.sharpshooter"), "brawler": Lang.t("skills.names.brawler"), "berserker": Lang.t("skills.names.berserker"), "regen": Lang.t("skills.names.regen"), "revive": Lang.t("skills.names.revive"), "block": Lang.t("skills.names.block"),
	"fortify": Lang.t("skills.names.fortify"), "second_wind": Lang.t("skills.names.second_wind"), "invincible": Lang.t("skills.names.invincible"), "stoneskin": Lang.t("skills.names.stoneskin"), "counter": Lang.t("skills.names.counter"),
	"haste_aura": Lang.t("skills.names.haste_aura"), "guard_aura": Lang.t("skills.names.guard_aura"), "regen_aura": Lang.t("skills.names.regen_aura"),
	"ignite": Lang.t("skills.names.ignite"), "piercing_shot": Lang.t("skills.names.piercing_shot"), "blood_rage": Lang.t("skills.names.blood_rage"), "frost_chain": Lang.t("skills.names.frost_chain"), "rend": Lang.t("skills.names.rend"), "bulwark": Lang.t("skills.names.bulwark"),
	"crushing_blow": Lang.t("skills.names.crushing_blow"), "sunder": Lang.t("skills.names.sunder"), "shield_bash": Lang.t("skills.names.shield_bash"), "snare": Lang.t("skills.names.snare"), "blade_flurry": Lang.t("skills.names.blade_flurry"), "parry": Lang.t("skills.names.parry"),
	"fire_bolt": Lang.t("skills.names.fire_bolt"), "firespread": Lang.t("skills.names.firespread"), "axe_volley": Lang.t("skills.names.axe_volley"), "boomerang": Lang.t("skills.names.boomerang"), "spear_sweep": Lang.t("skills.names.spear_sweep"),
	"drain_slash": Lang.t("skills.names.drain_slash"), "volley": Lang.t("skills.names.volley"), "wide_swing": Lang.t("skills.names.wide_swing"), "cheap_shot": Lang.t("skills.names.cheap_shot"), "crescent": Lang.t("skills.names.crescent"),
	"lunar_veil": Lang.t("skills.names.lunar_veil"), "howl": Lang.t("skills.names.howl"), "deep_freeze": Lang.t("skills.names.deep_freeze"), "hex": Lang.t("skills.names.hex"), "scorch": Lang.t("skills.names.scorch"), "gale": Lang.t("skills.names.gale"),
	"solar_spark": Lang.t("skills.names.solar_spark"), "frost_spike": Lang.t("skills.names.frost_spike"), "magma": Lang.t("skills.names.magma"),
	"turtle_ward": Lang.t("skills.names.turtle_ward"), "black_shell": Lang.t("skills.names.black_shell"), "north_tide": Lang.t("skills.names.north_tide"), "tiger_claw": Lang.t("skills.names.tiger_claw"), "tiger_fury": Lang.t("skills.names.tiger_fury"), "tiger_avatar": Lang.t("skills.names.tiger_avatar"), "fox_fire": Lang.t("skills.names.fox_fire"), "fox_charm": Lang.t("skills.names.fox_charm"), "nine_tails": Lang.t("skills.names.nine_tails"), "dragon_arrow": Lang.t("skills.names.dragon_arrow"), "azure_tide": Lang.t("skills.names.azure_tide"), "azure_dragon": Lang.t("skills.names.azure_dragon"), "time_stop": Lang.t("skills.names.time_stop"), "time_haste": Lang.t("skills.names.time_haste"), "time_collapse": Lang.t("skills.names.time_collapse"), "phoenix_wing": Lang.t("skills.names.phoenix_wing"), "phoenix_blessing": Lang.t("skills.names.phoenix_blessing"), "rebirth_flame": Lang.t("skills.names.rebirth_flame"),
}

## 영웅별 이름(개정 17 §2 표의 괄호·§3 예시): 영웅 id → {종류: 이름}. 없으면 NAMES.
static var HERO_NAMES := {"ignis": {"poison": Lang.t("skills.hero_names.poison"), "aoe_blast": Lang.t("skills.hero_names.aoe_blast")}}
const BURN_POISON := ["ignis"]  # 이 영웅들의 poison은 화상(burn 도트)으로 들어간다 — 화염 숙련 등 화상 연계에 걸린다
const BOSS_SLAYER_OTHERS := 0.2  # 거인 사냥: 보스가 아닌 적에게는 1/5(2026-10-06 밸런스)


## 스킬 이름(영웅별 이름이 있으면 그것).
static func name_of(kind: String, hero_id := "") -> String:
	return HERO_NAMES.get(hero_id, {}).get(kind, NAMES.get(kind, kind))


## 종류 → 설명 틀. {a}·{b}·{c} = 숫자, {bx} = b / 100(배수). 스펙 §3.2 표의 효과를 그대로 문장으로.
static var TEXTS := {
	"heal_aura": Lang.t("skills.texts.heal_aura"),
	"atk_aura": Lang.t("skills.texts.atk_aura"),
	"dmg_reduce": Lang.t("skills.texts.dmg_reduce"),
	"dodge": Lang.t("skills.texts.dodge"),
	"thorns": Lang.t("skills.texts.thorns"),
	"lifesteal": Lang.t("skills.texts.lifesteal"),
	"haste": Lang.t("skills.texts.haste"),
	"rage": Lang.t("skills.texts.rage"),
	"crit": Lang.t("skills.texts.crit"),
	"execute": Lang.t("skills.texts.execute"),
	"boss_slayer": Lang.t("skills.texts.boss_slayer"),
	"cleave": Lang.t("skills.texts.cleave"),
	"multishot": Lang.t("skills.texts.multishot"),
	"chain": Lang.t("skills.texts.chain"),
	"aoe_blast": Lang.t("skills.texts.aoe_blast"),
	"slow": Lang.t("skills.texts.slow"),
	"stun": Lang.t("skills.texts.stun"),
	"poison": Lang.t("skills.texts.poison"),
	"gate_repair": Lang.t("skills.texts.gate_repair"),
	"meteor": Lang.t("skills.texts.meteor"),
	"inferno": Lang.t("skills.texts.inferno"),
	"earthquake": Lang.t("skills.texts.earthquake"),
	"ground_slam": Lang.t("skills.texts.ground_slam"),
	"blizzard": Lang.t("skills.texts.blizzard"),
	"tornado": Lang.t("skills.texts.tornado"),
	"thunder_storm": Lang.t("skills.texts.thunder_storm"),
	"arrow_rain": Lang.t("skills.texts.arrow_rain"),
	"poison_cloud": Lang.t("skills.texts.poison_cloud"),
	"frost_nova": Lang.t("skills.texts.frost_nova"),
	"whirlwind": Lang.t("skills.texts.whirlwind"),
	"war_cry": Lang.t("skills.texts.war_cry"),
	"shockwave": Lang.t("skills.texts.shockwave"),
	"spear_throw": Lang.t("skills.texts.spear_throw"),
	"ice_spikes": Lang.t("skills.texts.ice_spikes"),
	"dragon_breath": Lang.t("skills.texts.dragon_breath"),
	"starfall": Lang.t("skills.texts.starfall"),
	"sky_bolt": Lang.t("skills.texts.sky_bolt"),
	"comet": Lang.t("skills.texts.comet"),
	"holy_smite": Lang.t("skills.texts.holy_smite"),
	"shadow_strike": Lang.t("skills.texts.shadow_strike"),
	"void_rift": Lang.t("skills.texts.void_rift"),
	"solar_flare": Lang.t("skills.texts.solar_flare"),
	"abyss_hand": Lang.t("skills.texts.abyss_hand"),
	"lava_burst": Lang.t("skills.texts.lava_burst"),
	"sanctuary": Lang.t("skills.texts.sanctuary"),
	"mass_heal": Lang.t("skills.texts.mass_heal"),
	"resurrection": Lang.t("skills.texts.resurrection"),
	"battle_hymn": Lang.t("skills.texts.battle_hymn"),
	"shield_ally": Lang.t("skills.texts.shield_ally"),
	"shield": Lang.t("skills.texts.shield"),
	"taunt": Lang.t("skills.texts.taunt"),
	"summon_wolf": Lang.t("skills.texts.summon_wolf"),
	"summon_skeleton": Lang.t("skills.texts.summon_skeleton"),
	"summon_golem": Lang.t("skills.texts.summon_golem"),
	"summon_treant": Lang.t("skills.texts.summon_treant"),
	"summon_spirit": Lang.t("skills.texts.summon_spirit"),
	"summon_phoenix": Lang.t("skills.texts.summon_phoenix"),
	"summon_hawk": Lang.t("skills.texts.summon_hawk"),
	"summon_turret": Lang.t("skills.texts.summon_turret"),
	"burn_hit": Lang.t("skills.texts.burn_hit"),
	"bleed_hit": Lang.t("skills.texts.bleed_hit"),
	"curse_hit": Lang.t("skills.texts.curse_hit"),
	"freeze_hit": Lang.t("skills.texts.freeze_hit"),
	"root_hit": Lang.t("skills.texts.root_hit"),
	"shock_hit": Lang.t("skills.texts.shock_hit"),
	"knockback_hit": Lang.t("skills.texts.knockback_hit"),
	"armor_break": Lang.t("skills.texts.armor_break"),
	"weaken_hit": Lang.t("skills.texts.weaken_hit"),
	"hunter_mark": Lang.t("skills.texts.hunter_mark"),
	"double_strike": Lang.t("skills.texts.double_strike"),
	"barrage": Lang.t("skills.texts.barrage"),
	"splash": Lang.t("skills.texts.splash"),
	"pierce": Lang.t("skills.texts.pierce"),
	"ricochet": Lang.t("skills.texts.ricochet"),
	"echo_strike": Lang.t("skills.texts.echo_strike"),
	"heavy_blow": Lang.t("skills.texts.heavy_blow"),
	"corpse_explosion": Lang.t("skills.texts.corpse_explosion"),
	"soul_harvest": Lang.t("skills.texts.soul_harvest"),
	"bloodlust": Lang.t("skills.texts.bloodlust"),
	"frost_shatter": Lang.t("skills.texts.frost_shatter"),
	"wildfire": Lang.t("skills.texts.wildfire"),
	"frenzy": Lang.t("skills.texts.frenzy"),
	"last_stand": Lang.t("skills.texts.last_stand"),
	"opportunist": Lang.t("skills.texts.opportunist"),
	"pyromancy": Lang.t("skills.texts.pyromancy"),
	"first_strike": Lang.t("skills.texts.first_strike"),
	"focus": Lang.t("skills.texts.focus"),
	"sharpshooter": Lang.t("skills.texts.sharpshooter"),
	"brawler": Lang.t("skills.texts.brawler"),
	"berserker": Lang.t("skills.texts.berserker"),
	"regen": Lang.t("skills.texts.regen"),
	"revive": Lang.t("skills.texts.revive"),
	"block": Lang.t("skills.texts.block"),
	"fortify": Lang.t("skills.texts.fortify"),
	"second_wind": Lang.t("skills.texts.second_wind"),
	"invincible": Lang.t("skills.texts.invincible"),
	"stoneskin": Lang.t("skills.texts.stoneskin"),
	"counter": Lang.t("skills.texts.counter"),
	"haste_aura": Lang.t("skills.texts.haste_aura"),
	"guard_aura": Lang.t("skills.texts.guard_aura"),
	"regen_aura": Lang.t("skills.texts.regen_aura"),	"ignite": Lang.t("skills.texts.ignite"),
	"piercing_shot": Lang.t("skills.texts.piercing_shot"),
	"blood_rage": Lang.t("skills.texts.blood_rage"),
	"frost_chain": Lang.t("skills.texts.frost_chain"),
	"rend": Lang.t("skills.texts.rend"),
	"bulwark": Lang.t("skills.texts.bulwark"),
	"crushing_blow": Lang.t("skills.texts.crushing_blow"),
	"sunder": Lang.t("skills.texts.sunder"),
	"shield_bash": Lang.t("skills.texts.shield_bash"),
	"snare": Lang.t("skills.texts.snare"),
	"blade_flurry": Lang.t("skills.texts.blade_flurry"),
	"parry": Lang.t("skills.texts.parry"),
	"fire_bolt": Lang.t("skills.texts.fire_bolt"),
	"firespread": Lang.t("skills.texts.firespread"),
	"axe_volley": Lang.t("skills.texts.axe_volley"),
	"boomerang": Lang.t("skills.texts.boomerang"),
	"spear_sweep": Lang.t("skills.texts.spear_sweep"),
	"drain_slash": Lang.t("skills.texts.drain_slash"),
	"volley": Lang.t("skills.texts.volley"),
	"wide_swing": Lang.t("skills.texts.wide_swing"),
	"cheap_shot": Lang.t("skills.texts.cheap_shot"),
	"crescent": Lang.t("skills.texts.crescent"),
	"lunar_veil": Lang.t("skills.texts.lunar_veil"),
	"howl": Lang.t("skills.texts.howl"),
	"deep_freeze": Lang.t("skills.texts.deep_freeze"),
	"hex": Lang.t("skills.texts.hex"),
	"scorch": Lang.t("skills.texts.scorch"),
	"gale": Lang.t("skills.texts.gale"),
	"solar_spark": Lang.t("skills.texts.solar_spark"),
	"frost_spike": Lang.t("skills.texts.frost_spike"),
	"magma": Lang.t("skills.texts.magma"),
	"turtle_ward": Lang.t("skills.texts.turtle_ward"),
	"black_shell": Lang.t("skills.texts.black_shell"),
	"north_tide": Lang.t("skills.texts.north_tide"),
	"tiger_claw": Lang.t("skills.texts.tiger_claw"),
	"tiger_fury": Lang.t("skills.texts.tiger_fury"),
	"tiger_avatar": Lang.t("skills.texts.tiger_avatar"),
	"fox_fire": Lang.t("skills.texts.fox_fire"),
	"fox_charm": Lang.t("skills.texts.fox_charm"),
	"nine_tails": Lang.t("skills.texts.nine_tails"),
	"dragon_arrow": Lang.t("skills.texts.dragon_arrow"),
	"azure_tide": Lang.t("skills.texts.azure_tide"),
	"azure_dragon": Lang.t("skills.texts.azure_dragon"),
	"time_stop": Lang.t("skills.texts.time_stop"),
	"time_haste": Lang.t("skills.texts.time_haste"),
	"time_collapse": Lang.t("skills.texts.time_collapse"),
	"phoenix_wing": Lang.t("skills.texts.phoenix_wing"),
	"phoenix_blessing": Lang.t("skills.texts.phoenix_blessing"),
	"rebirth_flame": Lang.t("skills.texts.rebirth_flame"),
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

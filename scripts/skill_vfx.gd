extends RefCounted
## 스킬 연출 4단계(2026-10-30 "스킬 이펙트 상용 수준으로"): 모든 액티브·확률 발동 스킬이 같은 뼈대로 이어진다 —
##   1) 준비 windup  : 발밑 마법진(셰이더 문양)이 안에서 바깥으로 그려지고, 몸·무기가 속성 색으로 달아오르며, 속성마다 다른 "모이는" 겹
##                     (화염 = 감아 오르는 불꽃 띠, 얼음 = 솟는 결정, 번개 = 튀는 전류, 검술 = 검기 응축, 암흑 = 검은 구슬 응축, 신성 = 내려오는 빛 …).
##   2) 발동 release : 마법진이 번쩍 닫히고 속성 섬광·순간 광원(풀링한 OmniLight 둘)·근접은 앞으로 내딛기(모델만 — 판정 위치 그대로) + 잔상.
##   3) 타격 hit     : 맞은 몸이 속성 색으로 번쩍(UnitModel 덧그림 색) + 속성 파편(불티·얼음 조각·전류·검흔·보라 균열…).
##                     한 번 시전의 첫 타격은 속성 충격파 고리 + (궁극기면) 히트스톱·짧은 흔들림·광원.
##   4) 잔상 linger  : 첫 타격 자리에서 속성대로 흩어진다(연기·불티 / 서리 안개·눈 / 남은 전류 / 검은 연기 / 금빛 입자 / 초록 빛 …).
## 스킬 몸통 이펙트(운석·눈보라·번개 등, fx.gd·ur_fx.gd)는 그대로 그 사이에 들어간다 — 이 파일은 앞뒤와 타격을 잇는다.
## 판정·데미지·쿨타임·발동 순간은 건드리지 않는다(그림만).
##
## 모바일: 메시는 종류마다 한 번 만들어 캐시, 재질은 속성 무관 몇 개만 공유(색 = 정점 색·인스턴스 값). 메시 노드는 풀에서 꺼내 쓰고 돌려준다(POOL_MAX).
## 전부 Fx 상한(MAX_LIVE)에 함께 센다. 이펙트가 붐비면(BUSY) 타격 파편·잔상을 건너뛰고, 그래픽 "낮음"이면 광원·잔상을 끈다.
## 한 프레임 타격 파편은 HITS_PER_FRAME개까지(광역기가 수십 마리를 쳐도 파편이 폭주하지 않게).

const Fx := preload("res://scripts/fx.gd")
const MeshKit := preload("res://scripts/mesh_kit.gd")
const Graphics := preload("res://scripts/graphics.gd")
const SigilShader := preload("res://shaders/fx_sigil.gdshader")
const ToonShader := preload("res://shaders/fx_toon.gdshader")
const ToonTopShader := preload("res://shaders/fx_toon_top.gdshader")
const SlashShader := preload("res://shaders/fx_slash.gdshader")

const POOL_MAX := 64
const BUSY := 0.6  # Fx.live()가 MAX_LIVE의 이만큼을 넘으면 곁가지(준비 겹·타격 파편·잔상)를 줄인다
const RESERVE := 0.85  # 이 위로는 SkillVfx가 노드를 띄우지 않는다 — 남은 몫은 스킬 몸통(운석·번개 등 판정이 보이는 그림)에 남긴다
const HITS_PER_FRAME := 4
const LIGHTS := 2  # 순간 광원 풀(Compatibility 렌더러는 광원마다 맞는 물체를 한 번 더 그린다 — 둘, 짧게)
const LIGHT_RANGE := 7.0
const ULT_STOP := 0.08  # 궁극기 첫 타격 히트스톱(실제 초, camera_rig가 STOP_GAP으로 간격을 둔다)
const ROCK := Color(0.55, 0.45, 0.35)
const BLADE_GLOW := Color(0.18, 0.85, 1.0)  # 검기 기본 색(푸른 검광)  # 대지 준비: 떠오르는 돌조각 색
const ULT_KICK := 0.3  # 궁극기 첫 타격 흔들림(m) — 화면이 읽히게 작게

## 속성 팔레트: c = 몸 색(에너지 셰이더가 가장자리·심을 여기서 만든다), c2 = 불똥·입자 색, smoke = 잔상 연기 색(a = 진하기),
## sides = 마법진 별 꼭짓점, spin = 마법진 도는 빠르기(라디안/초).
const PAL := {
	"fire": {"c": Color(1.0, 0.42, 0.08), "c2": Color(1.0, 0.78, 0.25), "smoke": Color(0.28, 0.22, 0.2, 0.55), "sides": 6, "spin": 1.6},
	"ice": {"c": Color(0.42, 0.8, 1.0), "c2": Color(0.85, 0.97, 1.0), "smoke": Color(0.88, 0.95, 1.0, 0.45), "sides": 6, "spin": 0.7},
	"lightning": {"c": Color(0.5, 0.68, 1.0), "c2": Color(0.85, 0.93, 1.0), "smoke": Color(0.45, 0.5, 0.75, 0.3), "sides": 5, "spin": 3.0},
	"blade": {"c": Color(0.62, 0.85, 1.0), "c2": Color(0.95, 0.98, 1.0), "smoke": Color(0.75, 0.7, 0.62, 0.35), "sides": 4, "spin": 2.2},
	"dark": {"c": Color(0.5, 0.16, 0.85), "c2": Color(0.85, 0.45, 1.0), "smoke": Color(0.12, 0.06, 0.18, 0.6), "sides": 5, "spin": -1.2},
	"holy": {"c": Color(1.0, 0.8, 0.3), "c2": Color(1.0, 0.95, 0.7), "smoke": Color(1.0, 0.92, 0.65, 0.3), "sides": 8, "spin": 0.9},
	"heal": {"c": Color(0.4, 0.95, 0.5), "c2": Color(0.85, 1.0, 0.7), "smoke": Color(0.75, 1.0, 0.75, 0.3), "sides": 6, "spin": 0.6},
	"earth": {"c": Color(0.85, 0.52, 0.22), "c2": Color(1.0, 0.8, 0.5), "smoke": Color(0.62, 0.52, 0.4, 0.55), "sides": 4, "spin": 0.5},
	"poison": {"c": Color(0.5, 0.88, 0.18), "c2": Color(0.8, 1.0, 0.4), "smoke": Color(0.35, 0.5, 0.15, 0.45), "sides": 5, "spin": -0.8},
	"wind": {"c": Color(0.55, 0.95, 0.82), "c2": Color(0.9, 1.0, 0.95), "smoke": Color(0.85, 0.95, 0.9, 0.3), "sides": 3, "spin": 3.5},
	"water": {"c": Color(0.22, 0.62, 1.0), "c2": Color(0.75, 0.92, 1.0), "smoke": Color(0.8, 0.92, 1.0, 0.4), "sides": 6, "spin": 1.0},
	"rage": {"c": Color(0.95, 0.16, 0.1), "c2": Color(1.0, 0.55, 0.3), "smoke": Color(0.3, 0.08, 0.06, 0.45), "sides": 3, "spin": 2.5},
	"guard": {"c": Color(0.5, 0.72, 1.0), "c2": Color(0.9, 0.95, 1.0), "smoke": Color(0.8, 0.88, 1.0, 0.3), "sides": 6, "spin": 0.8},
	"moon": {"c": Color(0.7, 0.75, 1.0), "c2": Color(0.92, 0.94, 1.0), "smoke": Color(0.7, 0.72, 0.95, 0.3), "sides": 7, "spin": 0.8},
	"arcane": {"c": Color(0.4, 0.82, 1.0), "c2": Color(0.85, 0.97, 1.0), "smoke": Color(0.5, 0.75, 0.95, 0.3), "sides": 12, "spin": -1.5},
	"shot": {"c": Color(0.95, 0.8, 0.45), "c2": Color(1.0, 0.95, 0.75), "smoke": Color(0.7, 0.62, 0.5, 0.35), "sides": 4, "spin": 2.0},
	"beast": {"c": Color(0.85, 0.6, 0.3), "c2": Color(1.0, 0.85, 0.55), "smoke": Color(0.55, 0.45, 0.32, 0.4), "sides": 3, "spin": 1.8},
}

## 스킬 → 속성(같은 속성도 스킬마다 몸통 연출이 다르다 — 이 표는 앞뒤·타격의 성격만 정한다). 없는 스킬은 "shot".
const ELEMENT := {
	# 화염
	"meteor": "fire", "inferno": "fire", "ignite": "fire", "fire_bolt": "fire", "firespread": "fire", "lava_burst": "fire",
	"dragon_breath": "fire", "aoe_blast": "fire", "scorch": "fire", "magma": "fire", "summon_phoenix": "fire",
	"phoenix_wing": "fire", "rebirth_flame": "fire", "fox_fire": "fire", "nine_tails": "fire",
	# 얼음
	"blizzard": "ice", "frost_nova": "ice", "ice_spikes": "ice", "frost_chain": "ice", "deep_freeze": "ice", "frost_spike": "ice",
	# 번개
	"thunder_storm": "lightning", "sky_bolt": "lightning", "tiger_avatar": "lightning",
	# 검술(베기·찌르기·휩쓸기)
	"whirlwind": "blade", "rend": "blade", "blade_flurry": "blade", "crescent": "blade", "wide_swing": "blade", "cheap_shot": "blade",
	"sunder": "blade", "spear_sweep": "blade", "shockwave": "blade", "tiger_claw": "blade", "parry": "blade",
	# 암흑
	"shadow_strike": "dark", "void_rift": "dark", "abyss_hand": "dark", "drain_slash": "dark", "summon_skeleton": "dark",
	# 신성
	"holy_smite": "holy", "solar_flare": "holy", "starfall": "holy", "solar_spark": "holy", "battle_hymn": "holy", "summon_spirit": "holy",
	# 회복
	"heal_aura": "heal", "mass_heal": "heal", "sanctuary": "heal", "resurrection": "heal", "gate_repair": "heal",
	# 대지
	"earthquake": "earth", "ground_slam": "earth", "crushing_blow": "earth", "summon_golem": "earth", "shield_bash": "earth",
	# 독·자연
	"poison_cloud": "poison", "snare": "poison", "summon_treant": "poison", "hex": "poison",  # 역병의 저주(초록 독구름)
	# 바람
	"tornado": "wind", "gale": "wind", "boomerang": "wind", "summon_hawk": "wind",
	# 물(현무·청룡)
	"turtle_ward": "water", "north_tide": "water", "dragon_arrow": "water", "azure_dragon": "water",
	# 투지·수호
	"war_cry": "rage", "blood_rage": "rage", "taunt": "guard", "shield": "guard", "shield_ally": "guard", "bulwark": "guard",
	# 달·시간
	"lunar_veil": "moon", "comet": "arcane", "time_stop": "arcane", "time_collapse": "arcane",
	# 사격·투척·짐승
	"arrow_rain": "shot", "piercing_shot": "shot", "volley": "shot", "spear_throw": "shot", "axe_volley": "shot", "summon_turret": "shot",
	"howl": "beast", "summon_wolf": "beast",
}
## 같은 속성이지만 색이 다른 스킬(영웅 고유 빛): 몸 색만 바꾼다.
const TINT := {"fox_fire": Color(1.0, 0.4, 0.62), "nine_tails": Color(1.0, 0.4, 0.62), "comet": Color(0.55, 0.8, 1.0),
	"tiger_avatar": Color(0.75, 0.88, 1.0), "tiger_claw": Color(0.75, 0.9, 1.0), "drain_slash": Color(0.75, 0.12, 0.3),
	"gate_repair": Color(0.95, 0.75, 0.25)}
## 시전 준비 겹(속성 고유 "모이는" 모양)이 따로 있는 속성. 나머지는 마법진 + 빨려 드는 입자만.
const SELF_STYLES := ["heal", "guard", "rage", "beast"]  # 발동이 자기 몸에서 퍼지는 속성(앞으로 내딛지 않는다)

static var _pool: Array[MeshInstance3D] = []
static var _holder: Node3D  # 쉬는 풀 노드를 숨겨 두는 곳(루트 아래, 숨김) — 트리 안에 있어야 게임이 끝날 때 함께 지워진다
static var _meshes := {}
static var _sigil_mat: ShaderMaterial
static var _toon_mats := {}
static var _slash_mat: ShaderMaterial
static var _boom_ms := -1000
static var _boom_at := Vector3.ZERO
static var _plane: PlaneMesh
static var _lights: Array[OmniLight3D] = []
static var _light_i := 0
static var _hit_frame := -1
static var _hit_n := 0


# --- 표 ---

static func element_of(kind: String) -> String:
	return str(ELEMENT.get(kind, "shot"))


## 속성 kind의 몸 색(스킬 고유 색이 있으면 그것).
static func color_of(kind: String) -> Color:
	if TINT.has(kind):
		return TINT[kind]
	return PAL[element_of(kind)].c


static func pal(kind: String) -> Dictionary:
	return PAL[element_of(kind)]


## 이 영웅의 궁극기(SSR·UR의 해금된 가장 높은 칸 액티브 — 컷인과 같은 기준)인가. R·SR은 궁극기 연출(히트스톱·흔들림)이 없다.
static func is_ult(hero, kind: String) -> bool:
	if hero == null or kind == "" or not hero.has_method("_ult_kind"):
		return false
	return str(hero.def.get("grade", "")) in ["SSR", "UR"] and hero._ult_kind() == kind


static func _busy() -> bool:
	return Fx.live() > int(Fx.MAX_LIVE * BUSY)


static func _low() -> bool:
	return Graphics.quality() == "low"


# --- 1) 준비 ---

## 발동 모션이 시작될 때(hero.begin_cast): sec초 뒤 발동 순간에 맞춰 다 모인다. 영웅을 따라간다(영웅 자식, 메타 "charge…" — 시전이 끊기면 hero가 지운다).
static func windup(hero: Node3D, kind: String, sec: float) -> void:
	if hero == null or not hero.is_inside_tree():
		return
	var e := element_of(kind)
	var p: Dictionary = PAL[e]
	var col := color_of(kind)
	var tier: int = hero._tier
	var sc: float = Fx.TIER_SCALE[tier]
	var ult := is_ult(hero, kind)
	var at := hero.global_position
	var model = hero.get("_model")
	if model != null and model.has_method("charge_glow"):
		model.charge_glow(col.lerp(Color.WHITE, 0.25), maxf(sec, 0.08))  # 몸·무기가 달아오른다 → 발동 순간 번쩍
	if sec <= 0.05:
		return
	var r := (1.5 if not ult else 2.2) * sc  # 2026-10-30 참고 그림: 몸보다 넉넉히 큰 마법진
	sigil(hero, at + Vector3(0, 0.04, 0), col, r, sec, int(p.sides), float(p.spin), "charge_sigil")
	if ult and not _low():  # 궁극기: 몸 둘레를 기울어 감아 도는 빛줄기 둘(참고 그림의 감기는 빛 띠)
		for i in 2:
			blade_arc(hero.get_parent(), at + Vector3(0, 0.9 + 0.3 * i, 0), randf() * TAU, (0.9 + 0.2 * i) * sc, Color(p.c2).lerp(col, 0.4), maxf(sec, 0.15), 0.45 * (1 - 2 * i), true, false)
	if not _busy() or ult:  # 붐비면 마법진·몸 발광만(궁극기는 늘 다)
		_gather(hero, at, e, col, Color(p.c2), sc, sec, ult)


## 속성 고유의 "모이는" 겹 + 빨려 드는 입자(가슴 높이로).
static func _gather(hero: Node3D, at: Vector3, e: String, col: Color, c2: Color, sc: float, sec: float, ult: bool) -> void:
	var chest := at + Vector3(0, 1.2, 0)
	match e:
		"fire", "rage":
			var sw := _take(hero, _mesh("swirl"), _flame_mat(), at, col, "charge_swirl")
			if sw != null:  # 발밑에서 감아 오르는 불꽃 띠: 좁아지며 빨리 돈다
				sw.scale = Vector3(1.3, 0.4, 1.3) * sc
				var tw := _tw(sw)
				tw.tween_property(sw, "scale", Vector3(0.55, 1.15, 0.55) * sc, sec).set_ease(Tween.EASE_IN)
				tw.parallel().tween_property(sw, "rotation:y", TAU * 1.6, sec).set_ease(Tween.EASE_IN)
				tw.parallel().tween_method(_fader(sw), 0.4, 1.0, sec * 0.5)
				tw.tween_callback(_give.bind(sw))
		"ice":
			for i in 3 + int(ult) * 2:  # 둘레에 얼음 결정이 솟는다
				var a := TAU * i / (3.0 + int(ult) * 2.0) + randf() * 0.4
				var pos := at + Vector3(cos(a), 0, sin(a)) * 0.9 * sc
				var cr := _take(hero, _mesh("crystal"), _smooth_mat(), pos, col, "charge_crystal")
				if cr == null:
					break
				cr.rotation = Vector3(randf_range(-0.35, 0.35), randf() * TAU, randf_range(-0.35, 0.35))
				cr.scale = Vector3(0.6, 0.05, 0.6) * sc
				var tw := _tw(cr)
				tw.tween_interval(sec * 0.15 * i / 3.0)
				tw.tween_property(cr, "scale", Vector3(0.6, 1.0, 0.6) * sc * randf_range(0.7, 1.1), sec * 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
				tw.tween_interval(sec * 0.25)
				tw.tween_method(_fader(cr), 1.0, 0.0, 0.18)
				tw.tween_callback(_give.bind(cr))
		"lightning":
			for i in 2 + int(ult):  # 몸 둘레에서 전류가 튀다 꺼진다(매번 다른 모양)
				var bolt := _take(hero, _bolt_mesh(randi() % 6), _arc_mat(), chest + Vector3(randf_range(-0.6, 0.6), randf_range(-0.6, 0.3), randf_range(-0.6, 0.6)) * sc, col, "charge_arc")
				if bolt == null:
					break
				bolt.scale = Vector3.ONE * 0.22 * sc
				bolt.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
				var tw := _tw(bolt)
				tw.tween_interval(sec * (0.15 + 0.3 * i))
				tw.tween_callback(func(): bolt.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU))
				tw.tween_interval(sec * 0.2)
				tw.tween_method(_fader(bolt), 1.0, 0.0, 0.08)
				tw.tween_callback(_give.bind(bolt))
		"dark", "arcane", "moon":
			var orb := _take(hero, _mesh("orb"), _energy_mat(), chest, col.darkened(0.3) if e == "dark" else col, "charge_orb")
			if orb != null:  # 일렁이던 검은 기운이 가슴 앞 작은 구슬로 응축된다
				orb.scale = Vector3.ONE * 0.85 * sc
				var tw := _tw(orb)
				tw.tween_property(orb, "scale", Vector3.ONE * 0.35 * sc, sec).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
				tw.parallel().tween_property(orb, "rotation", Vector3(1.5, 3.0, 0.7), sec)
				tw.parallel().tween_method(_fader(orb), 0.3, 1.0, sec * 0.6)
				tw.tween_callback(_give.bind(orb))
		"holy":
			var beam := _take(hero, _mesh("beam"), _smooth_mat(), at, col, "charge_beam")
			if beam != null:  # 하늘에서 가는 빛이 내려와 굵어진다
				beam.scale = Vector3(0.15, 0.2, 0.15) * sc
				beam.position.y = 4.0
				var tw := _tw(beam)
				tw.tween_property(beam, "scale", Vector3(0.55, 1.0, 0.55) * sc, sec).set_ease(Tween.EASE_OUT)
				tw.parallel().tween_property(beam, "position:y", 0.0, sec * 0.5).set_ease(Tween.EASE_OUT)
				tw.parallel().tween_method(_fader(beam), 0.2, 0.85, sec)
				tw.tween_callback(_give.bind(beam))
		"heal", "water", "poison", "wind":
			var rg := _take(hero, _mesh("ring"), _smooth_mat(), at + Vector3(0, 0.06, 0), col, "charge_ring")
			if rg != null:  # 발밑 오라가 바깥에서 안으로 조여든다
				rg.scale = Vector3(1.8, 1.0, 1.8) * sc
				var tw := _tw(rg)
				tw.tween_property(rg, "scale", Vector3(0.7, 1.0, 0.7) * sc, sec).set_ease(Tween.EASE_IN)
				tw.parallel().tween_property(rg, "rotation:y", TAU * 0.5, sec)
				tw.tween_callback(_give.bind(rg))
		"earth":
			var rk := Fx._burst(hero, at + Vector3(0, 0.1, 0), ROCK, "chunk", int(6 * sc), sec + 0.2, "charge_rocks")
			if rk != null:  # 발밑 돌조각이 땅에서 떠오른다(대지의 힘을 끌어올린다)
				rk.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
				rk.emission_ring_radius = 1.0 * sc
				rk.emission_ring_inner_radius = 0.5 * sc
				rk.emission_ring_height = 0.1
				rk.emission_ring_axis = Vector3.UP
				rk.gravity = Vector3(0, 1.2, 0)
				rk.initial_velocity_min = 0.4
				rk.initial_velocity_max = 1.0
				rk.explosiveness = 0.7
			var rg2 := _take(hero, _mesh("ring"), _energy_mat(), at + Vector3(0, 0.06, 0), col, "charge_ring")
			if rg2 != null:
				rg2.scale = Vector3(1.6, 1.0, 1.6) * sc
				var tw := _tw(rg2)
				tw.tween_property(rg2, "scale", Vector3(0.6, 1.0, 0.6) * sc, sec).set_ease(Tween.EASE_IN)
				tw.tween_callback(_give.bind(rg2))
		"blade", "shot", "guard", "beast":
			var sl := _take(hero, _mesh("crescent"), _arc_mat(), chest, col, "charge_edge")
			if sl != null:  # 몸 앞에 검기가 겹겹이 모여 날이 선다
				sl.scale = Vector3.ONE * 1.3 * sc
				sl.rotation = Vector3(PI / 2.0, randf() * TAU, 0)
				var tw := _tw(sl)
				tw.tween_property(sl, "scale", Vector3.ONE * 0.5 * sc, sec).set_ease(Tween.EASE_IN)
				tw.parallel().tween_property(sl, "rotation:y", sl.rotation.y + TAU, sec)
				tw.parallel().tween_method(_fader(sl), 0.2, 1.0, sec * 0.7)
				tw.tween_callback(_give.bind(sl))
	if sec < 0.18:
		return
	var pt := Fx._burst(hero, chest, c2, "spark", int((8 + 6 * int(ult)) * sc), sec, "charge_in")
	if pt != null:  # 둘레의 빛 조각이 가슴으로 빨려 든다
		pt.local_coords = true
		pt.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
		pt.emission_sphere_radius = 1.3 * sc
		pt.gravity = Vector3.ZERO
		pt.initial_velocity_min = 0.0
		pt.initial_velocity_max = 0.0
		pt.radial_accel_min = -11.0 * sc / sec
		pt.radial_accel_max = -7.0 * sc / sec
		pt.explosiveness = 0.5
		pt.lifetime = sec


# --- 2) 발동 ---

## 발동 순간(hero._tick_cast): 마법진이 번쩍 닫히고, 속성 섬광 + 순간 광원, 근접은 앞으로 내딛는다(모델만) + 잔상.
## style = HeroSkills.cast_style(공격·강화·회복·소환·수리).
static func release(hero: Node3D, kind: String, style: String) -> void:
	if hero == null or not hero.is_inside_tree():
		return
	var e := element_of(kind)
	var p: Dictionary = PAL[e]
	var col := color_of(kind)
	var tier: int = hero._tier
	var sc: float = Fx.TIER_SCALE[tier]
	var ult := is_ult(hero, kind)
	var parent := hero.get_parent()
	var at := hero.global_position
	for c in hero.get_children():  # 준비 마법진: 크게 번쩍이며 닫힌다
		if c.has_meta("fx") and str(c.get_meta("fx")) == "charge_sigil":
			c.set_meta("fx", "sigil_close")
			var tw := _tw(c)
			tw.tween_property(c, "scale", c.scale * 1.25, 0.08).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_method(_sigil_fader(c), 1.0, 0.0, 0.32)
			tw.tween_callback(_give.bind(c))
	var model = hero.get("_model")
	if model != null and model.has_method("release_glow"):
		model.release_glow()
	Fx.halo(parent, at + Vector3(0, 1.2, 0), col.lightened(0.25), (1.5 + 0.6 * int(ult)) * sc, 0.22, 1.5, "release_glow")
	if ult:  # 순간 광원은 궁극기만(광원은 비춘 물체를 한 번 더 그린다 — 모바일 부담)
		light(parent, at + Vector3(0, 1.4, 0), col, 2.2, 0.22)
	match style:
		"buff", "heal", "repair":
			_self_burst(parent, at, e, col, Color(p.c2), sc, ult)
		"summon":
			_ring_wave(parent, at, col, 1.8 * sc, 0.4)
		_:
			if e in SELF_STYLES:
				_self_burst(parent, at, e, col, Color(p.c2), sc, ult)
			elif hero.get("role") == "melee":
				_lunge(hero, col, sc)
			else:
				_muzzle(hero, parent, e, col, Color(p.c2), sc)
	if ult and e != "heal":  # 궁극기: 발밑에서 짧은 충격 고리가 터진다(발동 무게감)
		_ring_wave(parent, at, col, 2.4 * sc, 0.35)


## 원거리 발동: 손끝(가슴 앞) 속성 섬광 + 앞쪽으로 튀는 불똥.
static func _muzzle(hero: Node3D, parent: Node, e: String, col: Color, c2: Color, sc: float) -> void:
	var fwd := _forward(hero)
	var pos := hero.global_position + Vector3(0, 1.25, 0) + fwd * 0.5
	var orb := _take(parent, _mesh("orb"), _flame_mat() if e == "fire" else _energy_mat(), pos, col, "muzzle")
	if orb != null:
		orb.scale = Vector3.ONE * 0.12 * sc
		var tw := _tw(orb)
		tw.tween_property(orb, "scale", Vector3.ONE * 0.38 * sc, 0.08).set_ease(Tween.EASE_OUT)
		tw.tween_method(_fader(orb), 1.0, 0.0, 0.18)
		tw.parallel().tween_property(orb, "scale", Vector3.ONE * 0.5 * sc, 0.18)
		tw.tween_callback(_give.bind(orb))
	var sp := Fx._burst(parent, pos, c2, "spark", 8, 0.3, "muzzle_sparks")
	if sp != null:
		sp.direction = fwd
		sp.spread = 35.0
		sp.initial_velocity_min = 5.0
		sp.initial_velocity_max = 9.0


## 근접 발동: 모델이 앞으로 0.45 m 내딛었다 돌아온다(영웅 위치·판정은 그대로) + 내딛은 길에 검기 잔상.
static func _lunge(hero: Node3D, col: Color, sc: float) -> void:
	var model = hero.get("_model")
	var fwd := _forward(hero)
	if model is Node3D and not model.has_meta("lunging"):
		model.set_meta("lunging", true)
		var base: Vector3 = model.position
		var off := hero.global_basis.inverse() * (fwd * 0.45)
		var tw: Tween = model.create_tween()
		tw.tween_property(model, "position", base + off, 0.06).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_interval(0.08)
		tw.tween_property(model, "position", base, 0.2).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(func(): model.remove_meta("lunging"))
	blade_arc(hero.get_parent(), hero.global_position + Vector3(0, 0.8, 0), atan2(fwd.x, fwd.z) + PI * 0.6, 1.7 * sc, col, 0.14, randf_range(-0.35, 0.35))  # 휘두르는 검기
	var trail := _take(hero.get_parent(), _mesh("streak"), _arc_mat(), hero.global_position + Vector3(0, 0.9, 0), col, "afterimage")
	if trail != null:  # 잔상: 지나온 자리에 늘어진 빛 띠
		trail.look_at(trail.global_position + fwd, Vector3.UP)
		trail.scale = Vector3(0.6, 0.6, 0.4) * sc
		var tw2 := _tw(trail)
		tw2.tween_property(trail, "scale", Vector3(0.5, 0.5, 1.6) * sc, 0.1).set_ease(Tween.EASE_OUT)
		tw2.tween_method(_fader(trail), 1.0, 0.0, 0.25)
		tw2.tween_callback(_give.bind(trail))


## 자기 몸에서 퍼지는 발동(회복·강화·함성): 속성 고리가 퍼지고 빛 입자가 떠오른다.
static func _self_burst(parent: Node, at: Vector3, e: String, col: Color, c2: Color, sc: float, ult: bool) -> void:
	_ring_wave(parent, at, col, (2.0 + 0.8 * int(ult)) * sc, 0.45)
	var up := Fx._burst(parent, at + Vector3(0, 0.3, 0), c2, "mote", int(12 * sc), 0.9, "release_rise")
	if up != null:
		up.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		up.emission_ring_radius = 0.9 * sc
		up.emission_ring_inner_radius = 0.3
		up.emission_ring_height = 0.1
		up.emission_ring_axis = Vector3.UP
		up.direction = Vector3.UP
		up.spread = 12.0
		up.gravity = Vector3(0, 1.5, 0)
		up.initial_velocity_min = 1.5
		up.initial_velocity_max = 3.0
	if e in ["rage", "guard"]:
		var sw := _take(parent, _mesh("swirl"), _flame_mat() if e == "rage" else _arc_mat(), at, col, "release_swirl")
		if sw != null:
			sw.scale = Vector3(0.6, 0.6, 0.6) * sc
			var tw := _tw(sw)
			tw.tween_property(sw, "scale", Vector3(1.0, 1.4, 1.0) * sc, 0.3).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(sw, "rotation:y", -TAU, 0.45)
			tw.parallel().tween_method(_fader(sw), 1.0, 0.0, 0.45)
			tw.tween_callback(_give.bind(sw))


# --- 3) 타격 ---

## 스킬이 몸을 맞힌 순간(HeroSkills._hit·hero._blast): 맞은 몸이 속성 색으로 번쩍 + 속성 파편.
## first = 이 시전의 첫 타격 → 속성 충격파 고리 + (궁극기면) 히트스톱·흔들림·광원 + 잔상을 그 자리에.
## power: 0 = 확률 발동 패시브(작게), 1 = 액티브, 2 = 궁극기.
static func hit(target: Node3D, kind: String, power: int, first: bool) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var e := element_of(kind)
	var p: Dictionary = PAL[e]
	var col := color_of(kind)
	var model = target.get("_model")
	if model != null and model.has_method("tint_flash"):
		model.tint_flash(Color.from_hsv(col.h, maxf(col.s, 0.65), 1.0))  # 속성 색으로 번쩍(하얗게 뭉개지지 않게)
	var parent := target.get_parent()
	var ground := Vector3(target.global_position.x, 0.0, target.global_position.z)
	if first:
		_first_hit(parent, ground, e, col, Color(p.c2), power)
	var f := Engine.get_process_frames()
	if f != _hit_frame:
		_hit_frame = f
		_hit_n = 0
	if _hit_n >= HITS_PER_FRAME or _busy():
		return
	_hit_n += 1
	_shard(parent, ground + Vector3(0, 0.8, 0), e, col, Color(p.c2), power)


## 맞은 자리 속성 파편(작게, 0.3초 안팎).
static func _shard(parent: Node, pos: Vector3, e: String, col: Color, c2: Color, power: int) -> void:
	var k := 0.8 + 0.25 * power
	match e:
		"fire", "rage":
			var em := Fx._burst(parent, pos, c2, "ember", int(6 * k), 0.6, "hit_ember")
			if em != null:
				em.initial_velocity_min = 1.5
				em.initial_velocity_max = 3.5
				em.spread = 70.0
		"ice", "water":
			var ch := Fx._burst(parent, pos, c2, "spark", int(7 * k), 0.4, "hit_ice")
			if ch != null:
				ch.mesh = _mesh("shardlet")
				ch.particle_flag_align_y = false
				ch.angular_velocity_min = -500.0
				ch.angular_velocity_max = 500.0
				ch.particle_flag_rotate_y = true
		"lightning":
			var b := _take(parent, _bolt_mesh(randi() % 6), _arc_mat(), pos, col, "hit_zap")
			if b != null:
				b.scale = Vector3.ONE * 0.28 * k
				b.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
				var tw := _tw(b)
				tw.tween_interval(0.05)
				tw.tween_callback(func(): b.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU))
				tw.tween_interval(0.05)
				tw.tween_method(_fader(b), 1.0, 0.0, 0.08)
				tw.tween_callback(_give.bind(b))
		"blade", "beast", "guard":  # 맞은 자리를 화면 쪽으로 긋는 작은 검기
			blade_face(parent, pos, 0.75 * k, col)
		"shot", "earth":
			Fx.slash_mark(parent, pos, col.lightened(0.3), 0.55 * k)
		"dark":
			var o := _take(parent, _mesh("crack"), _energy_mat(), pos, col, "hit_crack")
			if o != null:
				_face(o)
				o.rotate_object_local(Vector3.BACK, randf() * TAU)
				o.scale = Vector3.ONE * 0.3 * k
				var tw := _tw(o)
				tw.tween_property(o, "scale", Vector3.ONE * 0.9 * k, 0.1).set_ease(Tween.EASE_OUT)
				tw.tween_method(_fader(o), 1.0, 0.0, 0.25)
				tw.tween_callback(_give.bind(o))
		_:
			var sp := Fx._burst(parent, pos, c2, "mote", int(6 * k), 0.5, "hit_mote")
			if sp != null:
				sp.initial_velocity_min = 1.0
				sp.initial_velocity_max = 2.5


## 첫 타격: 속성 충격 고리 + 궁극기면 히트스톱·짧은 흔들림·광원. 잔상은 조금 뒤 그 자리에서.
static func _first_hit(parent: Node, ground: Vector3, e: String, col: Color, c2: Color, power: int) -> void:
	explosion(parent, ground, e, col, c2, power)
	if power >= 1:
		_ring_wave(parent, ground, col, 1.6 + 0.8 * power, 0.32)
	if power >= 2:
		Fx.kick(parent, ground, ULT_KICK, ULT_STOP)
		light(parent, ground + Vector3(0, 1.5, 0), col, 2.6, 0.25)
	if _low():
		return
	var tree := parent.get_tree() if parent != null and parent.is_inside_tree() else null
	if tree == null:
		return
	var wp: WeakRef = weakref(parent)  # 월드가 그새 사라지면(던전 나가기 등) 잔상을 건너뛴다
	tree.create_timer(0.15, false).timeout.connect(func():
		var pp = wp.get_ref()
		if pp != null and pp.is_inside_tree():
			linger(pp, ground, e, col, c2, 0.8 + 0.4 * power))


## 타격 폭발(2026-10-30 사용자 참고 그림 "스킬은 못해도 이정도 임팩트는"): 만화풍 셀 셰이딩 폭발을 맞은 자리에 터뜨린다.
## 겹: ① 불덩이 무리(진한 테두리 → 몸 → 밝은 띠 → 하얀 심, 0.07초에 팡 부풀었다 위로 피며 연기 색으로 식어 구멍 나듯 사라진다)
## ② 솟구치는 불기둥(액티브·궁극기) ③ 끊긴 빛 조각으로 된 충격파 고리(빠르게 퍼진다) ④ 흙먼지 줄기 고리(느리게 퍼진다) ⑤ 튀는 돌 파편.
## 속성 색은 팔레트(c 몸, c2 밝은 띠) — 화염은 참고 그림 그대로 주황·노랑, 얼음은 파랑·하양 등. power: 0 확률 발동(작게) · 1 액티브 · 2 궁극기.
static func explosion(parent: Node, ground: Vector3, e: String, col: Color, c2: Color, power: int) -> void:
	var thin := e in ["blade", "shot", "wind", "guard"]  # 베기·사격: 불덩이를 줄이고 고리를 살린다
	# 식는 색: 불·흙·어둠·독은 짙은 연기(참고 그림처럼 갈색으로 식는다), 나머지는 밝은 색으로 흩어진다(얼음·빛·검기가 지저분한 갈색이 되지 않게)
	var smoke := Color(PAL[e].smoke as Color, 1.0).lerp(col, 0.25) if e in ["fire", "rage", "earth", "dark", "poison", "beast"] else c2.lerp(Color.WHITE, 0.3)
	var n := 0 if thin else (3 if power <= 0 else (5 if power == 1 else 7))
	if thin:  # 베기·사격: 불덩이 대신 맞은 자리를 엇갈려 긋는 큰 검기 둘(참고 그림의 검기) + 충격파 고리
		for i in 2:
			blade_face(parent, ground + Vector3(0, 0.8, 0), (1.1 + 0.3 * power) * (1.0 - 0.2 * i), col, 0.1 + 0.04 * i)
	var s: float = [0.6, 1.0, 1.4][clampi(power, 0, 2)] * (0.75 if thin else 1.0)
	boom(parent, ground, col, c2, smoke, s, n, power >= 1 and not thin, 2 if power >= 2 else 1, power >= 1, 1.5 if thin else 1.0)


## 툰 폭발 본체(Fx.blast도 이것을 쓴다): s = 크기(1 ≈ 불덩이 0.75 m·고리 2.2 m), n = 불덩이 수, jet = 불기둥, rings = 충격파 고리 수,
## dust = 흙먼지 고리·돌 파편, ring_k = 고리 크기 배수. 같은 자리(2 m 안)에 같은 순간(0.1초 안) 두 번 터지면 뒤엣것은 건너뛴다.
static func boom(parent: Node, ground: Vector3, col: Color, c2: Color, smoke: Color, s: float, n: int, jet: bool, rings: int, dust: bool, ring_k := 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var now := Time.get_ticks_msec()
	if now - _boom_ms < 100 and _boom_at.distance_to(ground) < maxf(2.0, s * 1.5):
		return
	_boom_ms = now
	_boom_at = ground
	if _busy():
		n = mini(n, 3)
	for i in n:  # ① 불덩이 무리
		var a := TAU * (i + randf() * 0.5) / maxf(n - 1, 1)
		var off := Vector3(cos(a), 0, sin(a)) * s * (0.0 if i == 0 else randf_range(0.5, 0.85))
		var b := _take(parent, _mesh("blob"), _toon_mat(1.0), ground + off + Vector3(0, s * (0.75 if i == 0 else randf_range(0.4, 1.2)), 0), Color.WHITE, "boom_blob")
		if b == null:
			break
		var r := s * (0.85 if i == 0 else randf_range(0.5, 0.72))
		b.set_instance_shader_parameter("tint", col)
		b.set_instance_shader_parameter("hot", c2)
		b.scale = Vector3.ONE * r * 0.2
		b.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
		var tw := _tw(b)
		tw.tween_interval(0.012 * i)
		tw.tween_property(b, "scale", Vector3.ONE * r * 1.15, 0.07).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
		tw.tween_property(b, "scale", Vector3.ONE * r * 1.35, 0.4).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(b, "position", b.position + off * 0.35 + Vector3(0, s * 0.6, 0), 0.4).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_method(func(v: float):  # 식는다: 몸 → 연기 색, 밝은 띠 → 몸 색
			if is_instance_valid(b):
				b.set_instance_shader_parameter("tint", col.lerp(smoke, v))
				b.set_instance_shader_parameter("hot", c2.lerp(col, v)), 0.0, 1.0, 0.3).set_delay(0.08)
		tw.parallel().tween_method(_fader(b), 1.0, 0.0, 0.3).set_delay(0.12).set_ease(Tween.EASE_IN)
		tw.tween_callback(_give.bind(b))
	if jet:  # ② 불기둥: 바닥에서 위로 솟구쳤다 가늘어지며 사라진다
		var j := _take(parent, _mesh("blob"), _toon_mat(1.0), ground + Vector3(0, s * 0.3, 0), Color.WHITE, "boom_jet")
		if j != null:
			j.set_instance_shader_parameter("tint", col.lerp(Color(0.85, 0.08, 0.05), 0.35) if col.r > 0.8 and col.b < 0.3 else col)  # 불꽃은 더 붉게
			j.set_instance_shader_parameter("hot", c2)
			j.scale = Vector3(0.3, 0.4, 0.3) * s
			var tw := _tw(j)
			tw.tween_property(j, "scale", Vector3(0.55 * s, 1.9 * s, 0.55 * s), 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
			tw.parallel().tween_property(j, "position", j.position + Vector3(0, 1.5 * s, 0), 0.1).set_ease(Tween.EASE_OUT)
			tw.tween_property(j, "scale", Vector3(0.15 * s, 2.3 * s, 0.15 * s), 0.25).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(j, "position", j.position + Vector3(0, 2.2 * s, 0), 0.25)
			tw.parallel().tween_method(_fader(j), 1.0, 0.0, 0.25).set_ease(Tween.EASE_IN)
			tw.tween_callback(_give.bind(j))
	for k in rings:  # ③ 충격파 고리(끊긴 빛 조각, 안쪽이 하얗게 탄다)
		var rg := _take(parent, _mesh("segring"), _toon_mat(0.0), ground + Vector3(0, 0.12 + 0.05 * k, 0), Color.WHITE, "boom_ring")
		if rg == null:
			break
		rg.set_instance_shader_parameter("tint", col)
		rg.set_instance_shader_parameter("hot", c2)
		rg.rotation.y = randf() * TAU
		rg.scale = Vector3(0.3, 1.0, 0.3) * s
		var rr := s * (2.2 + 0.9 * k) * ring_k
		var tw := _tw(rg)
		tw.tween_interval(0.07 * k)
		tw.tween_property(rg, "scale", Vector3(rr, 1.0, rr), 0.26).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
		tw.parallel().tween_property(rg, "rotation:y", rg.rotation.y + 0.5, 0.36)
		tw.parallel().tween_method(_fader(rg), 1.0, 0.0, 0.26).set_delay(0.1).set_ease(Tween.EASE_IN)
		tw.tween_callback(_give.bind(rg))
	if not dust or _low():
		return
	var d := _take(parent, _mesh("dustring"), _toon_mat(0.0), ground + Vector3(0, 0.06, 0), Color.WHITE, "boom_dust")
	if d != null:  # ④ 흙먼지 줄기 고리(갈색, 느리게)
		d.set_instance_shader_parameter("tint", Color(0.45, 0.3, 0.18, 0.95))
		d.set_instance_shader_parameter("hot", Color(0.72, 0.55, 0.36, 0.95))
		d.rotation.y = randf() * TAU
		d.scale = Vector3(0.5, 1.0, 0.5) * s
		var tw := _tw(d)
		tw.tween_property(d, "scale", Vector3(2.0, 1.0, 2.0) * s, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.parallel().tween_method(_fader(d), 1.0, 0.0, 0.35).set_delay(0.15).set_ease(Tween.EASE_IN)
		tw.tween_callback(_give.bind(d))
	if _busy():
		return
	var rk := Fx._burst(parent, ground + Vector3(0, 0.3, 0), Color(0.36, 0.26, 0.18), "spark", int(6 + 5 * s), 0.7, "boom_rock")
	if rk != null:  # ⑤ 돌 파편(작은 각진 조각이 튀어 올랐다 떨어진다)
		rk.mesh = _mesh("shardlet")
		rk.particle_flag_align_y = false
		rk.particle_flag_rotate_y = true
		rk.angular_velocity_min = -600.0
		rk.angular_velocity_max = 600.0
		rk.direction = Vector3.UP
		rk.spread = 55.0
		rk.gravity = Vector3(0, -16.0, 0)
		rk.initial_velocity_min = 4.0 * s
		rk.initial_velocity_max = 7.5 * s
		rk.scale_amount_min = 1.2
		rk.scale_amount_max = 2.2


# --- 4) 잔상 ---

## 타격이 끝난 자리에서 속성대로 흩어지는 잔상(연기·불티·서리 안개·남은 전류·검은 연기·빛 입자). r ≈ 퍼지는 반경(m).
static func linger(parent: Node, ground: Vector3, e: String, col: Color, c2: Color, r: float) -> void:
	if _busy() or _low():
		return
	var p: Dictionary = PAL[e]
	var smoke_c: Color = p.smoke
	var sm := Fx._burst(parent, ground + Vector3(0, 0.3, 0), Color(smoke_c, 1.0), "smoke", 4 + int(r * 2.0), 1.1, "linger_smoke")
	if sm != null:  # 옅은 연기·안개 덩이(속성 색)가 피어오르며 흩어진다
		sm.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		sm.emission_sphere_radius = r * 0.5
		sm.scale_amount_min = 0.8 * r
		sm.scale_amount_max = 1.4 * r
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 0.0))
		ramp.add_point(0.2, Color(1, 1, 1, smoke_c.a))
		ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0.0))
		sm.color_ramp = ramp
	match e:
		"fire", "rage":
			var em := Fx._burst(parent, ground + Vector3(0, 0.4, 0), c2, "ember", int(8 * r), 1.3, "linger_ember")
			if em != null:  # 불티가 열기를 타고 천천히 오른다
				em.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
				em.emission_sphere_radius = r * 0.6
				em.explosiveness = 0.6
				em.gravity = Vector3(0, 2.2, 0)
		"ice", "water":
			var fl := Fx._burst(parent, ground + Vector3(0, 1.6, 0), c2, "flake", int(8 * r), 1.4, "linger_flake")
			if fl != null:
				fl.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
				fl.emission_sphere_radius = r * 0.8
				fl.explosiveness = 0.5
			var fr := _take(parent, _mesh("ring"), _smooth_mat(), ground + Vector3(0, 0.04, 0), Color(c2, 0.7), "linger_frost")
			if fr != null:  # 바닥에 서리가 번졌다 녹는다
				fr.scale = Vector3(r * 0.6, 1, r * 0.6)
				var tw := _tw(fr)
				tw.tween_property(fr, "scale", Vector3(r * 1.3, 1, r * 1.3), 0.4).set_ease(Tween.EASE_OUT)
				tw.tween_method(_fader(fr), 1.0, 0.0, 0.9)
				tw.tween_callback(_give.bind(fr))
		"lightning":
			for i in 2:  # 남은 전류가 바닥에서 두어 번 튄다
				var b := _take(parent, _bolt_mesh(randi() % 6), _arc_mat(), ground + Vector3(randf_range(-r, r) * 0.5, 0.25, randf_range(-r, r) * 0.5), col, "linger_zap")
				if b == null:
					break
				b.scale = Vector3.ONE * 0.25
				b.rotation = Vector3(PI / 2.0 + randf_range(-0.3, 0.3), randf() * TAU, 0)
				b.visible = false
				var tw := _tw(b)
				tw.tween_interval(0.12 + 0.22 * i)
				tw.tween_callback(func(): b.visible = true)
				tw.tween_interval(0.06)
				tw.tween_method(_fader(b), 1.0, 0.0, 0.08)
				tw.tween_callback(_give.bind(b))
		"dark":
			var w := Fx._burst(parent, ground + Vector3(0, 0.3, 0), c2, "mote", int(8 * r), 1.0, "linger_wisp")
			if w != null:
				w.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
				w.emission_sphere_radius = r * 0.6
				w.gravity = Vector3(0, 1.8, 0)
				w.initial_velocity_max = 0.6
		_:
			var m := Fx._burst(parent, ground + Vector3(0, 0.3, 0), c2, "mote", int(6 * r), 1.0, "linger_mote")
			if m != null:
				m.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
				m.emission_sphere_radius = r * 0.6
				m.gravity = Vector3(0, 1.2, 0)
				m.initial_velocity_max = 0.8


# --- 스킬 고유 몸통 ---

## 뇌우(thunder_storm): 범위 바닥에 번개 마법진(오각 별, 빠르게 돈다)이 낙뢰 동안 깔려 범위를 보여 주고, 하늘엔 어두운 구름 덩이가 피어
## 소용돌이친다(연기 입자 — 단단한 판처럼 보이지 않게). sec = 낙뢰가 이어지는 초.
static func storm_cloud(parent: Node, pos: Vector3, r: float, sec: float) -> void:
	var p: Dictionary = PAL.lightning
	var sg := sigil(parent, pos + Vector3(0, 0.05, 0), Color(p.c), r * 1.05, 0.25, int(p.sides), float(p.spin), "storm_sigil")
	if sg != null:
		var tw := _tw(sg)
		tw.tween_method(func(v: float): sg.set_instance_shader_parameter("grow", v), 0.0, 1.0, 0.25).set_ease(Tween.EASE_OUT)
		tw.tween_interval(maxf(sec - 0.25, 0.1))
		tw.tween_method(_sigil_fader(sg), 1.0, 0.0, 0.4)
		tw.tween_callback(_give.bind(sg))
	if _low():
		return
	var cl := Fx._stream(parent, pos + Vector3(0, 6.0, 0), Color(0.24, 0.27, 0.42), "smoke", 6.0, 1.4, sec, "storm_cloud")
	if cl != null:
		cl.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		cl.emission_sphere_radius = r * 0.7
		cl.direction = Vector3.RIGHT
		cl.spread = 180.0
		cl.gravity = Vector3.ZERO
		cl.initial_velocity_min = 0.3
		cl.initial_velocity_max = 0.8
		cl.orbit_velocity_min = 0.08
		cl.orbit_velocity_max = 0.15
		cl.scale_amount_min = r * 0.45
		cl.scale_amount_max = r * 0.75
		cl.preprocess = 0.6


# --- 검기 ---

## 검기 궤적(2026-10-30 사용자 참고 그림): center 둘레를 반지름 r로 휘어 도는 넓은 빛 띠 — 바깥 날은 하얀 심 + 가는 검은 테두리,
## 안쪽으로 갈수록 투명, 꼬리는 가늘어지며 머리를 따라 사라진다. yaw = 궤적이 시작하는 방향(라디안, +Y 축), tilt = 기울기(대각 베기),
## sec = 머리가 끝까지 도는 시간. ring = 거의 한 바퀴(회오리). 뒤따르는 가는 궤적 하나가 조금 바깥에서 한 박자 늦게 돈다.
static func blade_arc(parent: Node, center: Vector3, yaw: float, r: float, col: Color, sec := 0.16, tilt := 0.0, ring := false, thin := true) -> MeshInstance3D:
	var main: MeshInstance3D = null
	# 색: 진하고 밝은 색은 그대로(화염 베기 등), 흙빛·옅은 영웅 색은 푸른 검광(참고 그림) — 밝은 풀밭에서 흐린 색은 갈색 띠로 보인다
	var tc := col if col.s >= 0.75 and col.v >= 0.8 else BLADE_GLOW
	for k in (2 if thin and not _busy() else 1):
		var mi := _take(parent, _mesh("blade_ring" if ring else "blade") if k == 0 else _mesh("blade_thin"), _slash_material(), center, Color.WHITE, "blade_arc")
		if mi == null:
			break
		mi.rotation = Vector3(tilt, yaw, 0)
		var rr := r * (1.0 if k == 0 else 1.12)
		mi.scale = Vector3(rr, 1.0, rr)
		mi.set_instance_shader_parameter("tint", tc)
		mi.set_instance_shader_parameter("head", 0.0)
		var tw := _tw(mi)
		tw.tween_interval(0.035 * k)
		tw.tween_method(_header(mi), 0.0, 1.0, sec).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(mi, "rotation:y", yaw - 0.35, sec + 0.12).set_ease(Tween.EASE_OUT)
		tw.tween_method(_header(mi), 1.0, 1.8, 0.16)  # 꼬리가 머리를 따라 빠진다
		tw.parallel().tween_method(_fader(mi), 1.0, 0.0, 0.16).set_ease(Tween.EASE_IN)
		tw.tween_callback(_give.bind(mi))
		if k == 0:
			main = mi
	return main


## 화면 쪽을 보는 검기(맞은 자리·기본 베기): pos 둘레 반지름 r, 방향 아무렇게나(대각선 베기처럼).
static func blade_face(parent: Node, pos: Vector3, r: float, col: Color, sec := 0.1) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var cam := parent.get_viewport().get_camera_3d()
	var mi := blade_arc(parent, pos, 0.0, r, col, sec, 0.0, false, false)
	if mi == null or cam == null:
		return
	var b := cam.global_basis.orthonormalized() * Basis(Vector3.RIGHT, PI / 2.0) * Basis(Vector3.UP, randf() * TAU)
	mi.global_basis = b.scaled(Vector3(r, 1.0, r))
	var tw := _tw(mi)  # 화면 쪽 궤적은 돌리지 않는다(기울기를 지킨다)
	tw.tween_method(_header(mi), 0.0, 1.0, sec).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_method(_header(mi), 1.0, 1.8, 0.14)
	tw.parallel().tween_method(_fader(mi), 1.0, 0.0, 0.14).set_ease(Tween.EASE_IN)
	tw.tween_callback(_give.bind(mi))


static func _header(mi: GeometryInstance3D) -> Callable:
	return func(v: float):
		if is_instance_valid(mi):
			mi.set_instance_shader_parameter("head", v)


static func _slash_material() -> ShaderMaterial:
	if _slash_mat == null:
		_slash_mat = ShaderMaterial.new()
		_slash_mat.shader = SlashShader
	return _slash_mat


# --- 공용 조각 ---

## 바닥 마법진(셰이더 문양, 그리기 한 번): sec초에 걸쳐 안에서 바깥으로 그려진다. 반환 노드는 tag 메타를 단다(풀 노드).
static func sigil(parent: Node, pos: Vector3, color: Color, r: float, sec: float, sides := 6, spin := 1.0, tag := "sigil") -> MeshInstance3D:
	if _plane == null:
		_plane = PlaneMesh.new()
		_plane.size = Vector2(2, 2)
	var mi := _take(parent, _plane, _sigil_material(), pos, Color.WHITE, tag)
	if mi == null:
		return null
	mi.scale = Vector3.ONE * r
	mi.set_instance_shader_parameter("tint", Color(color.lightened(0.1), 0.95))
	mi.set_instance_shader_parameter("sides", float(sides))
	mi.set_instance_shader_parameter("spin", spin)
	mi.set_instance_shader_parameter("grow", 0.0)
	mi.set_instance_shader_parameter("fade", 1.0)
	var tw := _tw(mi)
	tw.tween_method(func(v: float): mi.set_instance_shader_parameter("grow", v), 0.0, 1.0, maxf(sec * 0.7, 0.05)).set_ease(Tween.EASE_OUT)
	tw.tween_interval(sec * 0.3 + 1.5)  # 발동이 닫는다(release). 시전이 끊겨 아무도 닫지 않으면 이 뒤 저절로 사라진다
	tw.tween_method(_sigil_fader(mi), 1.0, 0.0, 0.3)
	tw.tween_callback(_give.bind(mi))
	return mi


## 바닥 충격 고리(에너지 셰이더): 0 → r m로 sec초에 퍼지며 갉아먹히듯 사라진다.
static func _ring_wave(parent: Node, ground: Vector3, col: Color, r: float, sec: float) -> void:
	var rg := _take(parent, _mesh("ring"), _energy_mat(), ground + Vector3(0, 0.07, 0), col, "shock_ring")
	if rg == null:
		return
	rg.scale = Vector3(0.25, 1.0, 0.25)
	var tw := _tw(rg)
	tw.tween_property(rg, "scale", Vector3(r, 1.0, r), sec).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_method(_fader(rg), 1.0, 0.0, sec).set_ease(Tween.EASE_IN)
	tw.tween_callback(_give.bind(rg))


## 순간 광원: pos에 col 빛이 energy만큼 켜졌다 sec초에 꺼진다. 풀(LIGHTS개)을 돌려 쓴다. 그래픽 "낮음"이면 없다.
static func light(parent: Node, pos: Vector3, col: Color, energy: float, sec: float) -> void:
	if parent == null or not parent.is_inside_tree() or _low():
		return
	var l: OmniLight3D = null
	for i in LIGHTS:
		var j := (_light_i + i) % LIGHTS
		if j >= _lights.size():
			_lights.append(null)
		var c = _lights[j]
		if c == null or not is_instance_valid(c):
			c = OmniLight3D.new()
			c.shadow_enabled = false
			c.omni_range = LIGHT_RANGE
			c.omni_attenuation = 1.6
			c.light_specular = 0.0
			c.visible = false
			_lights[j] = c
		if not c.visible:
			l = c
			_light_i = j + 1
			break
	if l == null:
		return  # 둘 다 켜져 있다 — 이번 빛은 건너뛴다
	if l.get_parent() != parent:
		if l.get_parent() != null:
			l.get_parent().remove_child(l)
		parent.add_child(l)
	l.global_position = pos
	l.light_color = col.lerp(Color.WHITE, 0.2)
	l.light_energy = energy
	l.visible = true
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, sec).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): l.visible = false)


static func _forward(hero: Node3D) -> Vector3:
	var t = hero.get("_target")
	if t != null and is_instance_valid(t) and t is Node3D:
		var d: Vector3 = t.global_position - hero.global_position
		d.y = 0.0
		if d.length() > 0.05:
			return d.normalized()
	var model = hero.get("_model")
	var f: Vector3 = model.global_basis.z if model is Node3D else Vector3.FORWARD
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


static func _face(mi: Node3D) -> void:
	var cam := mi.get_viewport().get_camera_3d()
	if cam != null:
		mi.global_basis = cam.global_basis


# --- 재질 ---

static func _energy_mat() -> ShaderMaterial:
	return Fx.energy_material("energy")


static func _flame_mat() -> ShaderMaterial:
	return Fx.energy_material("flame")


static func _arc_mat() -> ShaderMaterial:
	return Fx.energy_material("arc")


static func _smooth_mat() -> ShaderMaterial:
	return Fx.energy_material("smooth")


## 툰 폭발 재질: shade 1 = 덩어리(깊이 검사 없이 유닛 위에), 0 = 판(바닥 고리, 유닛 뒤로 숨는다).
static func _toon_mat(shade: float) -> ShaderMaterial:
	if not _toon_mats.has(shade):
		var m := ShaderMaterial.new()
		m.shader = ToonTopShader if shade > 0.5 else ToonShader
		m.set_shader_parameter("shade", shade)
		_toon_mats[shade] = m
	return _toon_mats[shade]


static func _sigil_material() -> ShaderMaterial:
	if _sigil_mat == null:
		_sigil_mat = ShaderMaterial.new()
		_sigil_mat.shader = SigilShader
	return _sigil_mat


# --- 풀 ---

## 풀에서 메시 노드를 꺼내 parent에 붙인다(정점 색이 없는 메시는 color를 인스턴스 값 대신 메시 색으로 — 메시가 색을 갖는다).
## Fx 상한이면 null. 꺼낸 노드는 Fx.track으로 센다(돌려주면 트리에서 빠지며 빠진다).
static func _take(parent: Node, m: Mesh, mat: Material, pos: Vector3, col: Color, tag: String) -> MeshInstance3D:
	if Fx.full(parent) or Fx.live() >= int(Fx.MAX_LIVE * RESERVE):
		return null
	var mi: MeshInstance3D = null
	while not _pool.is_empty() and mi == null:
		var c = _pool.pop_back()
		if is_instance_valid(c) and (c.get_parent() == null or c.get_parent() == _holder):
			mi = c
			if c.get_parent() != null:
				_holder.remove_child(c)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.mesh = _tinted(m, col) if col != Color.WHITE else m
	mi.material_override = mat
	mi.transform = Transform3D.IDENTITY
	mi.visible = true
	mi.set_meta("fx", tag)
	parent.add_child(mi)
	Fx.track(mi)
	mi.global_position = pos
	if mat != _sigil_mat:
		mi.set_instance_shader_parameter("fade", 1.0)
	return mi


## 노드 하나에 트윈 하나(돌려줄 때 남은 트윈을 끊는다).
static func _tw(mi: Node) -> Tween:
	if mi.has_meta("tw"):
		var old = mi.get_meta("tw")
		if old is Tween and old.is_valid():
			old.kill()
	var tw := mi.create_tween()
	mi.set_meta("tw", tw)
	return tw


static func _give(mi: Node) -> void:
	if not is_instance_valid(mi):
		return
	if mi.has_meta("tw"):
		mi.remove_meta("tw")
	var p := mi.get_parent()
	if _pool.size() >= POOL_MAX or not mi is MeshInstance3D or p == null or not mi.is_inside_tree():
		mi.queue_free()
		return
	if _holder == null or not is_instance_valid(_holder) or not _holder.is_inside_tree():
		_holder = Node3D.new()
		_holder.name = "SkillVfxPool"
		_holder.visible = false
		mi.get_tree().root.add_child.call_deferred(_holder)
	mi.remove_from_group(Fx.GROUP)
	p.remove_child(mi)
	_holder.add_child(mi)  # 숨은 곳(아직 트리에 붙기 전이어도 자식으로 둔다 — 붙을 때 함께 들어간다)
	_pool.append(mi)


static func _fader(mi: GeometryInstance3D) -> Callable:
	return func(v: float):
		if is_instance_valid(mi):
			mi.set_instance_shader_parameter("fade", v)


static func _sigil_fader(mi: Node) -> Callable:
	return func(v: float):
		if is_instance_valid(mi) and mi is GeometryInstance3D:
			mi.set_instance_shader_parameter("fade", v)


# --- 메시(종류마다 한 번, 색마다 한 벌 — 에너지 셰이더는 정점 색에서 그라데이션을 만든다) ---

static func _mesh(kind: String) -> Mesh:
	if not _meshes.has(kind):
		_meshes[kind] = _build(kind)
	return _meshes[kind]


## 흰 메시 m의 정점 색을 col로 바꾼 한 벌(캐시).
static func _tinted(m: Mesh, col: Color) -> Mesh:
	var key := "%d|%s" % [m.get_instance_id(), col.to_html()]
	if _meshes.has(key):
		return _meshes[key]
	var out := ArrayMesh.new()
	for s in m.get_surface_count():
		var arr: Array = m.surface_get_arrays(s)
		var n: int = arr[Mesh.ARRAY_VERTEX].size()
		var cols := PackedColorArray()
		cols.resize(n)
		var src = arr[Mesh.ARRAY_COLOR]
		for i in n:
			var a: float = src[i].a if src != null and src.size() == n else 1.0
			cols[i] = Color(col.r, col.g, col.b, a * col.a)
		arr[Mesh.ARRAY_COLOR] = cols
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_meshes[key] = out
	return out


static func _build(kind: String) -> Mesh:
	match kind:
		"orb":  # 로우폴리 구(면이 각져 심 밝기가 면마다 다르다)
			var s := SphereMesh.new()
			s.radius = 1.0
			s.height = 2.0
			s.radial_segments = 10
			s.rings = 6
			return _flat(s)
		"blob":  # 툰 폭발 덩어리: 매끈한 구(셀 셰이딩 띠가 둥글게 끊긴다)
			var sp := SphereMesh.new()
			sp.radius = 1.0
			sp.height = 2.0
			sp.radial_segments = 16
			sp.rings = 8
			var st := SurfaceTool.new()
			st.create_from(sp, 0)
			var arr := st.commit_to_arrays()
			var cols := PackedColorArray()
			cols.resize(arr[Mesh.ARRAY_VERTEX].size())
			cols.fill(Color.WHITE)
			arr[Mesh.ARRAY_COLOR] = cols
			var out := ArrayMesh.new()
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			return out
		"segring", "dustring":  # 충격파 고리(굵은 빛 조각 10개, 사이가 조금씩 끊긴다) / 흙먼지 고리(바깥으로 뻗는 짧은 줄기 22개)
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var ring := kind == "segring"
			var n := 10 if ring else 22
			for i in n:
				var c := TAU * (i + randf_range(-0.2, 0.2)) / n
				var half := (TAU / n) * (randf_range(0.36, 0.46) if ring else randf_range(0.07, 0.13))
				var r_in := randf_range(0.62, 0.7) if ring else randf_range(0.5, 0.7)
				var r_out := randf_range(0.96, 1.04) if ring else randf_range(0.92, 1.08)
				var steps := 4 if ring else 1
				for q in steps:  # 안쪽 가장자리 r=1(하얗게), 바깥 r=0(속성 색) · 조각 양끝은 가늘다
					var t0 := float(q) / steps
					var t1 := float(q + 1) / steps
					var a0 := c - half + 2.0 * half * t0
					var a1 := c - half + 2.0 * half * t1
					var w0 := sin(PI * t0) if ring else 1.0
					var w1 := sin(PI * t1) if ring else 1.0
					var m0 := lerpf(r_out, r_in, 0.15 + 0.85 * w0)
					var m1 := lerpf(r_out, r_in, 0.15 + 0.85 * w1)
					var d0 := Vector3(cos(a0), 0, sin(a0))
					var d1 := Vector3(cos(a1), 0, sin(a1))
					var g_in := 1.0 if ring else 0.0
					var g_out := 0.0 if ring else 0.9
					for v in [[d0 * m0, g_in], [d1 * m1, g_in], [d1 * r_out, g_out], [d0 * m0, g_in], [d1 * r_out, g_out], [d0 * r_out, g_out]]:
						st.set_normal(Vector3.UP)
						st.set_color(Color(v[1], v[1], v[1], 1.0))
						st.add_vertex(v[0])
			return st.commit()
		"blade", "blade_ring", "blade_thin":  # 검기 띠(xz 평면, 반지름 1): 꼬리(각 0) → 머리(각 arc). 정점 색 r = 폭(0 안 ~ 1 바깥 날), g = 길이(0 꼬리 ~ 1 머리)
			var arc := deg_to_rad(340.0 if kind == "blade_ring" else 210.0)
			var steps := 40 if kind == "blade_ring" else 28
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in steps:
				var quad := []
				for t: float in [float(i) / steps, float(i + 1) / steps]:
					var w: float = 0.05 if kind == "blade_thin" else 0.05 + 0.4 * smoothstep(0.0, 0.75, t) * (1.0 - 0.5 * smoothstep(0.93, 1.0, t))
					var ro: float = 0.88 + 0.12 * t  # 꼬리 쪽이 안으로 감긴다
					var d := Vector3(sin(arc * t), 0, cos(arc * t))
					quad.append([d * ro, d * (ro - w), t])
				for v in [[quad[0][0], 1.0, quad[0][2]], [quad[1][0], 1.0, quad[1][2]], [quad[1][1], 0.0, quad[1][2]],
						[quad[0][0], 1.0, quad[0][2]], [quad[1][1], 0.0, quad[1][2]], [quad[0][1], 0.0, quad[0][2]]]:
					st.set_normal(Vector3.UP)
					st.set_color(Color(v[1], v[2], 0.0, 1.0))
					st.add_vertex(v[0])
			return st.commit()
		"swirl":  # 감아 오르는 띠 셋(반지름 1, 높이 2, 1.25바퀴) — 위로 갈수록 좁고 옅다
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for b in 3:
				var steps := 18
				for i in steps:
					var t0 := float(i) / steps
					var t1 := float(i + 1) / steps
					_helix_quad(st, t0, t1, TAU * b / 3.0)
			st.generate_normals()
			return st.commit()
		"ring":  # 평평한 고리(안쪽 가장자리가 투명 — 부드럽게 번진다)
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var n := 28
			for i in n:
				var a0 := TAU * i / n
				var a1 := TAU * (i + 1) / n
				var i0 := Vector3(cos(a0), 0, sin(a0)) * 0.62
				var i1 := Vector3(cos(a1), 0, sin(a1)) * 0.62
				var o0 := Vector3(cos(a0), 0, sin(a0))
				var o1 := Vector3(cos(a1), 0, sin(a1))
				var m0 := (i0 + o0) * 0.5 + Vector3(0, 0.06, 0)
				var m1 := (i1 + o1) * 0.5 + Vector3(0, 0.06, 0)
				_quad(st, i0, i1, m1, m0, 0.0, 0.0, 1.0, 1.0)
				_quad(st, m0, m1, o1, o0, 1.0, 1.0, 0.35, 0.35)
			st.generate_normals()
			return st.commit()
		"crescent":  # 초승달 검기(가운데 두껍고 양끝이 가늘고 투명), 반지름 1, xz 평면
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var n := 14
			var arc := deg_to_rad(160.0)
			for i in n:
				var t0 := float(i) / n
				var t1 := float(i + 1) / n
				var a0 := -arc / 2.0 + arc * t0
				var a1 := -arc / 2.0 + arc * t1
				var w0 := sin(PI * t0) * 0.32
				var w1 := sin(PI * t1) * 0.32
				var al0 := sin(PI * t0)
				var al1 := sin(PI * t1)
				var d0 := Vector3(sin(a0), 0, -cos(a0))
				var d1 := Vector3(sin(a1), 0, -cos(a1))
				_quad(st, d0 * (1.0 - w0), d1 * (1.0 - w1), d1, d0, al0, al1, al1, al0, Vector3(0, 0.04, 0))
			st.generate_normals()
			return st.commit()
		"streak":  # 잔상 띠: -Z 쪽으로 늘어지며 투명해지는 납작한 마름모 두 장(십자)
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for ax in [Vector3.RIGHT, Vector3.UP]:
				var a: Vector3 = ax * 0.35
				_quad(st, -a, a, a * 0.2 + Vector3(0, 0, 1.0), -a * 0.2 + Vector3(0, 0, 1.0), 1.0, 1.0, 0.0, 0.0)
			st.generate_normals()
			return st.commit()
		"crystal":  # 얼음 결정: 5각 뾰족 기둥(밑 0.2, 높이 1.1)
			var k = MeshKit.new()
			k.prism_n(Vector3.ZERO, 5, 0.18, 0.2, 0.7, Color.WHITE)
			k.cone(Vector3(0, 0.7, 0), 5, 0.2, 0.4, Color.WHITE)
			return k.commit()
		"shardlet":  # 얼음 파편 입자(작은 사면체)
			var k = MeshKit.new()
			k.cone(Vector3.ZERO, 3, 0.06, 0.16, Color.WHITE)
			return k.commit()
		"beam":  # 빛기둥: 반지름 1 열린 원기둥(위로 갈수록 투명), 높이 6
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var n := 10
			for i in n:
				var a0 := TAU * i / n
				var a1 := TAU * (i + 1) / n
				var b0 := Vector3(cos(a0), 0, sin(a0))
				var b1 := Vector3(cos(a1), 0, sin(a1))
				_quad(st, b0, b1, b1 + Vector3(0, 3, 0), b0 + Vector3(0, 3, 0), 0.9, 0.9, 0.6, 0.6)
				_quad(st, b0 + Vector3(0, 3, 0), b1 + Vector3(0, 3, 0), b1 * 0.8 + Vector3(0, 6, 0), b0 * 0.8 + Vector3(0, 6, 0), 0.6, 0.6, 0.0, 0.0)
			st.generate_normals()
			return st.commit()
		"crack":  # 보라 균열: 가운데서 뻗는 가시 6개(납작, 카메라를 본다)
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in 6:
				var a := TAU * i / 6.0 + randf_range(-0.3, 0.3)
				var l := randf_range(0.7, 1.0)
				var d := Vector3(cos(a), sin(a), 0)
				var s := Vector3(-d.y, d.x, 0) * 0.12
				_tri(st, s, -s, d * l, 1.0, 1.0, 0.2)
			st.generate_normals()
			return st.commit()
	return BoxMesh.new()


## 번개 조각(길이 ~4, -Y로 뻗는 들쭉날쭉한 줄기 + 곁가지 둘): 서로 직각인 두 장이라 어느 쪽에서 봐도 보인다. 여섯 가지 모양을 캐시.
static func _bolt_mesh(v: int) -> Mesh:
	var key := "bolt%d" % v
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (v + 1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3.ZERO]
	for i in 7:
		pts.append(Vector3(rng.randf_range(-0.45, 0.45), -0.6 * (i + 1), rng.randf_range(-0.45, 0.45)))
	_jag(st, pts, 0.16)
	for b in 2:
		var s: Vector3 = pts[rng.randi_range(1, 4)]
		var br := [s]
		var d := Vector3(rng.randf_range(-1, 1), -1.0, rng.randf_range(-1, 1)).normalized()
		for i in 3:
			s = s + d * rng.randf_range(0.35, 0.55) + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
			br.append(s)
		_jag(st, br, 0.08)
	st.generate_normals()
	var m := st.commit()
	_meshes[key] = m
	return m


static func _jag(st: SurfaceTool, pts: Array, w: float) -> void:
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var t := 1.0 - float(i) / pts.size() * 0.5  # 끝으로 갈수록 가늘게
		for ax in [Vector3.RIGHT, Vector3.BACK]:
			var o: Vector3 = ax * w * t
			_quad(st, a - o, a + o, b + o * 0.8, b - o * 0.8, 1.0, 1.0, 1.0, 1.0)


static func _helix_quad(st: SurfaceTool, t0: float, t1: float, phase: float) -> void:
	var turns := TAU * 1.25
	var h := 2.0
	var p := []
	for t in [t0, t1]:
		var a: float = phase + turns * t
		var r: float = 1.0 - 0.45 * t
		var y: float = h * t
		var w: float = 0.42 * (1.0 - t * 0.6)
		var d := Vector3(cos(a), 0, sin(a)) * r
		p.append([d + Vector3(0, y, 0), d + Vector3(0, y + w, 0), 1.0 - t])
	_quad(st, p[0][0], p[1][0], p[1][1], p[0][1], p[0][2], p[1][2], p[1][2] * 0.3, p[0][2] * 0.3)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, aa: float, ab: float, ac: float, ad: float, off := Vector3.ZERO) -> void:
	_tri(st, a, b, c, aa, ab, ac, off)
	_tri(st, a, c, d, aa, ac, ad, off)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, aa: float, ab: float, ac: float, off := Vector3.ZERO) -> void:
	st.set_color(Color(1, 1, 1, aa))
	st.add_vertex(a + off)
	st.set_color(Color(1, 1, 1, ab))
	st.add_vertex(b + off)
	st.set_color(Color(1, 1, 1, ac))
	st.add_vertex(c + off)


## 기본 도형 → 정점 색(흰색)을 가진 각진(면마다 법선) 메시.
static func _flat(prim: PrimitiveMesh) -> Mesh:
	var st := SurfaceTool.new()
	st.create_from(prim, 0)
	st.deindex()
	var arr := st.commit_to_arrays()
	var n: int = arr[Mesh.ARRAY_VERTEX].size()
	var cols := PackedColorArray()
	cols.resize(n)
	cols.fill(Color.WHITE)
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_NORMAL] = null
	arr[Mesh.ARRAY_TANGENT] = null
	var st2 := SurfaceTool.new()
	st2.create_from_arrays(arr)
	st2.generate_normals()
	return st2.commit()

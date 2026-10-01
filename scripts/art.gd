extends RefCounted
## 아트 설정과 헬퍼 (구 flat.gd 흡수). 단색 메시 헬퍼, 로우폴리 재질, KayKit(CC0) 캐릭터·무기·화살 경로·애니메이션 표.
## 건물·성·자연물·산은 코드로 만든 메시(TownKit). 자연물·테두리 상수는 배치 규칙만.
## 모델 출처·라이선스: assets/models/LICENSE-KayKit.txt, 다시 받기: dev/fetch-assets.sh
## 오토로드 참조 없음 → 헤드리스 테스트에서 preload 가능.

const HERO_SELECTED := Color(1.0, 0.9, 0.2)

const CHARACTER_SCALE := 1.0      # KayKit 캐릭터 키 약 2.2m
const HEAD_HEIGHT := 2.5          # 캐릭터 모델 발에서 HP 바까지 높이(모델 단위, 배율 곱하기 전)
const CORPSE_SEC := 1.6           # 몬스터 사망 후 제거까지(초). Death_C_Skeletons(~2.0초)는 ~1.6초에 쓰러짐이 끝나므로, 애니메이션 꼬리가 끝나기 전 쓰러진 자세에서 제거한다. 사망 애니메이션 길이 이하여야 함(테스트)
const BUILDING_GAP := 0.6         # 건물 부지 가장자리 여유(m)
const ARROW_SCALE := 1.2
const NATURE_COUNT := 180
const NATURE_SEED := 7
const NATURE_MIN_GAP := 5.0
const NATURE_CASTLE_MARGIN := 6.0  # 성벽 바깥면에서 이 거리 안에는 자연물 없음
const LANE_HALF_WIDTH := 9.0       # 괴물 진입로(두 축) 양옆 이 거리 안에는 자연물 없음
const LOWPOLY_SHADER := preload("res://shaders/lowpoly.gdshader")
const LOWPOLY_DOUBLE_SHADER := preload("res://shaders/lowpoly_double.gdshader")  # 원본이 양면(CULL_DISABLED)인 재질용
const BORDER_INNER := 12.0        # 플레이 영역 가장자리(MAP_HALF)에서 테두리 띠 안쪽까지
const BORDER_OUTER := 40.0        # 테두리 띠 바깥쪽까지
const BORDER_SPACING := 22.0      # 테두리 산 간격(m)
const BORDER_SEED := 11

const CHAR_DIR := "res://assets/models/characters/"
const PROP_DIR := "res://assets/models/props/"

## 영웅 모델(heroes.csv `model`). gear = 손 부착물(handslot_l/r 자식) 전체 — 영웅의 gear 열에 있는 것만 보이고 나머지는 숨긴다.
## 모자·투구·망토는 부착물이 아니라 늘 보인다. 이름은 각 GLB를 열어 확인한 실제 노드 이름. 애니메이션 이름은 다섯 모델 공통.
const HERO_ANIMS := {"idle": "Idle", "walk": "Walking_A", "death": "Death_A"}
const HERO_MODELS := {
	"Knight": {"scene": CHAR_DIR + "Knight.glb",
		"gear": ["1H_Sword_Offhand", "Badge_Shield", "Rectangle_Shield", "Round_Shield", "Spike_Shield", "1H_Sword", "2H_Sword"]},
	"Barbarian": {"scene": CHAR_DIR + "Barbarian.glb",
		"gear": ["1H_Axe_Offhand", "Barbarian_Round_Shield", "1H_Axe", "2H_Axe", "Mug"]},
	"Mage": {"scene": CHAR_DIR + "Mage.glb", "gear": ["Spellbook", "Spellbook_open", "1H_Wand", "2H_Staff"]},
	"Rogue": {"scene": CHAR_DIR + "Rogue.glb", "gear": ["Knife_Offhand", "1H_Crossbow", "2H_Crossbow", "Knife", "Throwable"]},
	"Rogue_Hooded": {"scene": CHAR_DIR + "Rogue_Hooded.glb", "gear": ["Knife_Offhand", "1H_Crossbow", "2H_Crossbow", "Knife", "Throwable"]},
}
const GRADE_COLORS := {"R": Color("#8FA3B8"), "SR": Color("#9B6CD6"), "SSR": Color("#F2B233")}

## 상인 NPC: 두건 없는 Rogue, 무기·투척물 숨김(Cape는 망토라 유지). attack/death는 UnitModel 계약상 채움(쓰지 않음).
const MERCHANT_MODEL := {
	"scene": CHAR_DIR + "Rogue.glb",
	"hide": ["Knife_Offhand", "1H_Crossbow", "2H_Crossbow", "Knife", "Throwable"],
	"anims": {"idle": "Idle", "walk": "Walking_A", "attack": "2H_Ranged_Shoot", "death": "Death_A"},
}

const MONSTER_MODELS := {
	"grunt": {
		"scene": CHAR_DIR + "Skeleton_Minion.glb",
		"hide": [],
		"weapon": PROP_DIR + "Skeleton_Blade.gltf",
		"anims": {"idle": "Idle_Combat", "walk": "Walking_D_Skeletons", "attack": "1H_Melee_Attack_Chop", "death": "Death_C_Skeletons"},
	},
	"epic_boss": {
		"scene": CHAR_DIR + "Skeleton_Warrior.glb",
		"hide": [],
		"weapon": PROP_DIR + "Skeleton_Axe.gltf",
		"anims": {"idle": "Idle_Combat", "walk": "Walking_D_Skeletons", "attack": "2H_Melee_Attack_Chop", "death": "Death_C_Skeletons"},
	},
}
const WEAPON_BONE := "handslot.r"

## 공격 애니메이션 → 타격(근접)·발사(원거리) 순간 = 길이 × 이 비율(개정 12-2 §3). GLB를 헤드리스로 재생해 무기 손(handslot) 궤적에서
## 정했다: 근접 = 무기 끝 최고 속도~멈춤 사이(대상에 닿는 순간), 쌍검 = 첫 칼(오른손)이 가장 앞으로 뻗은 순간, 투척 = 손 최고 속도(놓는 순간),
## 쇠뇌 = 조준이 끝나고 반동이 시작되는 순간, 마법 = 지팡이·완드를 앞으로 다 뻗은 순간. 같은 이름 애니메이션은 모델마다 같다(길이·궤적 동일).
const HIT_FRAC := {
	"1H_Melee_Attack_Chop": 0.56, "2H_Melee_Attack_Chop": 0.52, "Dualwield_Melee_Attack_Chop": 0.38, "Throw": 0.54,
	"1H_Ranged_Shoot": 0.26, "2H_Ranged_Shoot": 0.26, "Spellcast_Shoot": 0.30,
}
const ATTACK_FIT := 0.9  # 공격 간격이 짧으면 애니메이션을 빨리 돌려 길이 ≤ 간격 × 이 값

const ARROW_MODEL := PROP_DIR + "arrow.gltf"

## 병사(개정 13 §7): 병종 id(soldiers.csv) → 무기(gear, 영웅 열과 같은 "a|b"), 역할(공격 애니메이션·투사체), 발밑 원판 색, 말(기병).
## 모델은 soldiers.csv `model`. 영웅보다 작게(SOLDIER_SCALE) 그려 구분한다.
const SOLDIERS := {
	"infantry": {"gear": "1H_Sword|Rectangle_Shield", "role": "melee", "color": Color("#C0504D")},
	"archer": {"gear": "2H_Crossbow", "role": "ranged", "color": Color("#6AA84F")},
	"cavalry": {"gear": "1H_Sword", "role": "melee", "color": Color("#4F81BD"), "horse": true},
}
const SOLDIER_SCALE := 0.9  # 개정 15: 0.75는 성채 앞 대열이 너무 작아 보였다(격자 0.9 m 간격 그대로)
const SOLDIER_BAR := Color(0.45, 0.78, 0.98)  # 병사 HP 바(하늘색)


## 병종 → UnitModel 스펙(hero_spec과 같은 규칙). 말 탄 병사는 걷지 않고 대기 동작 그대로(말이 걷는다).
static func soldier_spec(type: String, model: String) -> Dictionary:
	var a: Dictionary = SOLDIERS[type]
	var spec := hero_spec({"model": model, "gear": a.gear, "role": a.role})
	if a.get("horse", false):
		spec.anims.walk = spec.anims.idle
	return spec

## 영웅 정의(GameData.hero) → UnitModel 스펙: gear만 보이고, 공격 애니메이션은 역할·모델·주무기로 고른다.
static func hero_spec(h: Dictionary) -> Dictionary:
	var m: Dictionary = HERO_MODELS[h.model]
	var gear: PackedStringArray = h.gear.split("|")
	var anims := HERO_ANIMS.duplicate()
	anims.attack = _attack_anim(h.model, gear, h.role)
	return {"scene": m.scene, "hide": m.gear.filter(func(g): return not gear.has(g)), "anims": anims}


static func _attack_anim(model: String, gear: PackedStringArray, role: String) -> String:
	if role == "ranged":
		match model:
			"Mage": return "Spellcast_Shoot"
			"Barbarian": return "Throw"
		return "1H_Ranged_Shoot" if gear[0].begins_with("1H") else "2H_Ranged_Shoot"
	if gear.size() > 1 and gear[1].ends_with("_Offhand"):
		return "Dualwield_Melee_Attack_Chop"
	return "2H_Melee_Attack_Chop" if gear[0].begins_with("2H") else "1H_Melee_Attack_Chop"


static var _lowpoly_cache := {}  # 원본 재질 -> 로우폴리 재질 (같은 원본은 하나를 공유)
static var _vc_material: ShaderMaterial


## 코드로 만든 로우폴리 메시(정점 색)용 공유 재질.
static func lowpoly_vc_material() -> ShaderMaterial:
	if _vc_material == null:
		_vc_material = ShaderMaterial.new()
		_vc_material.shader = LOWPOLY_SHADER
		_vc_material.set_shader_parameter("use_texture", false)
		_vc_material.set_shader_parameter("use_vertex_color", true)
	return _vc_material


static func mesh(m: Mesh, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mi.mesh = m
	mi.material_override = mat
	return mi


## 원본 재질의 알베도(텍스처·색)를 쓰는 로우폴리 재질. 원본이 양면이면 양면 변형. 발광·투명 재질(해골 눈 등)은 원본 그대로.
static func lowpoly_material(src: Material) -> Material:
	var base := src as BaseMaterial3D
	if base == null or base.emission_enabled or base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return src
	if _lowpoly_cache.has(src):
		return _lowpoly_cache[src]
	var m := ShaderMaterial.new()
	m.shader = LOWPOLY_DOUBLE_SHADER if base.cull_mode == BaseMaterial3D.CULL_DISABLED else LOWPOLY_SHADER
	m.set_shader_parameter("albedo_color", base.albedo_color)
	m.set_shader_parameter("use_texture", base.albedo_texture != null)
	if base.albedo_texture != null:
		m.set_shader_parameter("albedo_tex", base.albedo_texture)
	_lowpoly_cache[src] = m
	return m


## 모델의 모든 표면 재질을 로우폴리 재질로 바꾼다.
static func apply_lowpoly(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			if src != null:
				mi.set_surface_override_material(i, lowpoly_material(src))


## 모든 모델은 여기서 만든다 — 로우폴리 변환이 한 곳에서 적용된다.
static func instance(path: String) -> Node3D:
	var n := (load(path) as PackedScene).instantiate() as Node3D
	apply_lowpoly(n)
	return n


## node의 root 기준 변환 (root 자신의 변환 제외). 트리에 없어도 된다.
static func relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != root:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## 모델 루트 기준 AABB (모든 MeshInstance3D 합, 루트 자신의 변환 제외). 트리에 없어도 된다.
static func model_aabb(root: Node3D) -> AABB:
	var box_sum := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var b := relative_transform(mi, root) * mi.get_aabb()
		box_sum = b if first else box_sum.merge(b)
		first = false
	return box_sum

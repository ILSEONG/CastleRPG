extends RefCounted
## 아트 설정과 헬퍼 (구 flat.gd 흡수). 단색 메시 헬퍼, KayKit(CC0) 모델 경로·배율·애니메이션 표.
## 모델 출처·라이선스: assets/models/LICENSE-KayKit.txt, 다시 받기: dev/fetch-assets.sh
## 오토로드 참조 없음 → 헤드리스 테스트에서 preload 가능.

const HERO_SELECTED := Color(1.0, 0.9, 0.2)

const CHARACTER_SCALE := 1.0      # KayKit 캐릭터 키 약 2.2m
const HEAD_HEIGHT := 2.5          # 캐릭터 모델 발에서 HP 바까지 높이(모델 단위, 배율 곱하기 전)
const CORPSE_SEC := 1.6           # 몬스터 사망 후 제거까지(초). Death_C_Skeletons(~2.0초)는 ~1.6초에 쓰러짐이 끝나므로, 애니메이션 꼬리가 끝나기 전 쓰러진 자세에서 제거한다. 사망 애니메이션 길이 이하여야 함(테스트)
const BUILDING_GAP := 0.6         # 건물 부지 가장자리 여유(m)
const WALL_MODEL_LEN := 2.0       # wall_straight 모델 치수(모델 단위): 길이·높이·두께
const WALL_MODEL_H := 1.1
const WALL_MODEL_T := 0.8
const WALL_PIECE_TARGET := 5.0    # 성벽 조각 목표 길이(m). 구간을 이 근처 길이로 균등 분할
const TOWER_SCALE := 3.2
const ARROW_SCALE := 1.2
const NATURE_SCALE := 3.0
const NATURE_COUNT := 180
const NATURE_SEED := 7
const NATURE_MIN_GAP := 5.0
const NATURE_CASTLE_MARGIN := 6.0  # 성벽 바깥면에서 이 거리 안에는 자연물 없음
const LANE_HALF_WIDTH := 9.0       # 괴물 진입로(두 축) 양옆 이 거리 안에는 자연물 없음

const CHAR_DIR := "res://assets/models/characters/"
const PROP_DIR := "res://assets/models/props/"
const HEX_DIR := "res://assets/models/hex/"

const HERO_MODELS := {
	"warrior": {
		"scene": CHAR_DIR + "Knight.glb",
		"hide": ["1H_Sword_Offhand", "Badge_Shield", "Rectangle_Shield", "Spike_Shield", "2H_Sword"],
		"anims": {"idle": "Idle", "walk": "Walking_A", "attack": "1H_Melee_Attack_Chop", "death": "Death_A"},
	},
	"archer": {
		"scene": CHAR_DIR + "Rogue_Hooded.glb",
		"hide": ["Knife_Offhand", "1H_Crossbow", "Knife", "Throwable"],
		"anims": {"idle": "Idle", "walk": "Walking_A", "attack": "2H_Ranged_Shoot", "death": "Death_A"},
	},
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

const BUILDING_MODELS := {
	"keep": HEX_DIR + "building_castle_blue.gltf",
	"barracks": HEX_DIR + "building_barracks_blue.gltf",
	"tavern": HEX_DIR + "building_tavern_blue.gltf",
	"lab": HEX_DIR + "building_blacksmith_blue.gltf",
	"houses": HEX_DIR + "building_home_B_blue.gltf",
	"lumber": HEX_DIR + "building_lumbermill_blue.gltf",
	"quarry": HEX_DIR + "building_mine_blue.gltf",
	"farm": HEX_DIR + "building_windmill_blue.gltf",
}
const WALL_MODEL := HEX_DIR + "wall_straight.gltf"
const GATE_MODEL := HEX_DIR + "wall_straight_gate.gltf"
const GATE_DOORS := ["wall_straight_gate_door_left", "wall_straight_gate_door_right"]
const TOWER_MODEL := HEX_DIR + "building_tower_A_blue.gltf"
const ARROW_MODEL := PROP_DIR + "arrow.gltf"
const NATURE_MODELS := [
	HEX_DIR + "trees_A_medium.gltf", HEX_DIR + "trees_B_large.gltf",
	HEX_DIR + "tree_single_A.gltf", HEX_DIR + "tree_single_B.gltf",
	HEX_DIR + "rock_single_A.gltf", HEX_DIR + "rock_single_C.gltf", HEX_DIR + "rock_single_E.gltf",
]


static func mesh(m: Mesh, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mi.mesh = m
	mi.material_override = mat
	return mi


static func instance(path: String) -> Node3D:
	return (load(path) as PackedScene).instantiate()


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

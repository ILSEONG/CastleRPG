# CastleRPG 에셋 적용 구현 계획 (개정 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 플레이스홀더 박스·캡슐을 KayKit CC0 모델(캐릭터 애니메이션, 건물, 성벽, 자연물)로 바꾸고 그림자·HUD 스타일로 완성도를 올린다. 규칙·밸런스·입력은 그대로.

**Architecture:** 모델 경로·배율·애니메이션 표는 순수 스크립트 `art.gd`(구 `flat.gd` 흡수)에 둔다. 캐릭터는 `unit_model.gd` 래퍼 하나가 인스턴스·부착물·애니메이션·방향을 맡고, hero/monster는 상태에 맞는 재생 함수만 부른다. 성벽은 모델 조각을 구간 길이에 맞춰 균등 반복, 건물은 AABB로 부지에 맞춘다.

**Tech Stack:** Godot 4.7.2 GDScript (Compatibility), KayKit glTF/GLB (CC0).

**Spec:** `docs/superpowers/specs/2026-09-30-castlerpg-asset-pass-design.md` (개정 2 spec보다 우선)

## Global Constraints

- Godot 실행 파일: `./tools/Godot_v4.7.2-stable_win64_console.exe` (Git Bash, 프로젝트 루트)
- **창 금지**: Godot는 항상 `--headless`. 브라우저 창도 열지 않는다. 화면 확인은 `node dev/webshot.mjs`(헤드리스 Chromium)만. 서버는 Bash `run_in_background`로 `npm --prefix dev run serve`, 끝나면 PowerShell `Stop-Process -Id (Get-NetTCPConnection -LocalPort 8060 -State Listen).OwningProcess -Force`. 웹 캡처는 한 번에 하나씩
- webshot: `--url`, `--out`, `--wait ms`, `--size WxH`, `--click x,y[,ms]`, `--drag x1,y1,x2,y2[,ms]`, `--wheel x,y,dy[,ms]`, `--dragback x,y,dx,dy[,ms]`, `--until TEXT[,ms]`(페이지 콘솔에 TEXT가 찍힐 때까지 대기). 좌표는 CSS px(뷰포트 360×640), PNG는 2배. URL `?auto-stage`면 시작 즉시 스테이지
- 캡처 PNG는 `.superpowers/sdd/2026-09-30-castlerpg-asset-pass/`에 저장. Read가 EBADF면 `C:\Users\CIS\AppData\Local\Temp\claude\c--CastleRPG\34234939-4d72-4fe9-a2d8-370bd90c98b7\scratchpad\`로 복사해서 읽는다. 본 것을 있는 그대로 적는다(애매한 픽셀을 기대와 일치한다고 쓰지 않는다)
- `class_name` 금지. 스크립트 간 참조는 `const X := preload("res://...")`. 다른 스크립트의 노드를 담는 변수는 타입 없이
- 오토로드 enum을 `match` 패턴에 쓰지 않는다(`game_state.gd` 내부만 허용)
- 물리 바디 없음. `Area3D`는 성문(레이어 2)·성벽(레이어 8) 탭 판정 전용. 영웅은 화면 거리로 고른다
- 규칙·밸런스·입력 동작을 바꾸지 않는다(이 계획이 명시한 시각 항목 제외)
- 로직 테스트: `./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd` → `ALL PASSED`, 종료 0. `-s`는 오토로드가 없다 → `GameState`를 참조하는 스크립트를 테스트에서 preload 금지 (`art.gd`는 순수라 가능)
- 입력 체크: `./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/input_check.tscn` → `INPUT ALL PASSED`, 종료 0
- 엔드투엔드: `./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --fixed-fps 60 --quit-after 9000 -- --auto-stage 2>&1 | grep -E "^\[(mode|cleared|failed)\]|SCRIPT ERROR"` → `[cleared] 1` 다음 `[mode] 1 stage=2`, `SCRIPT ERROR` 없음
- 새 `.gd`·에셋 → `./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --editor --quit`로 `*.uid`·`*.import` 생성 후 함께 커밋
- 웹 빌드 `bash dev/build-web.sh`
- 스크립트 15개 이내(테스트 제외)
- `python`은 동작하지 않는 스텁
- 들여쓰기 탭, 줄끝 LF. 커밋 메시지 끝: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

---

### Task 1: 에셋 받기 + art.gd + 에셋 계약 테스트

**Files:**
- Create: `dev/fetch-assets.sh`, `assets/models/**` (스크립트가 받음), `assets/models/LICENSE-KayKit.txt`
- Create: `scripts/art.gd`
- Delete: `scripts/flat.gd` (+ `.uid`)
- Modify: `scripts/castle.gd`, `scripts/buildings.gd`, `scripts/hero.gd`, `scripts/monster.gd` — `Flat` → `Art` 이름만 바꿈(동작 변화 없음)
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Produces `art.gd`(RefCounted, 순수): 상수 `HERO_SELECTED`, `WALL`, `TOWER`, `GATE`, `ARROW`(임시 — 이후 태스크가 안 쓰게 되면 삭제), `CHARACTER_SCALE`, `CORPSE_SEC`, `BUILDING_GAP`, `WALL_MODEL_LEN/H/T`, `WALL_PIECE_TARGET`, `TOWER_SCALE`, `ARROW_SCALE`, `NATURE_*`, `LANE_HALF_WIDTH`, `HERO_MODELS`, `MONSTER_MODELS`, `BUILDING_MODELS`, `WALL_MODEL`, `GATE_MODEL`, `GATE_DOORS`, `TOWER_MODEL`, `ARROW_MODEL`, `NATURE_MODELS`; static `mesh(m, color) -> MeshInstance3D`, `box(size, color)`, `capsule(r, h, color)`, `instance(path) -> Node3D`, `model_aabb(root: Node3D) -> AABB`
- 캐릭터 스펙 딕셔너리 형식: `{"scene": String, "hide": Array[String], "weapon": String(선택), "anims": {"idle","walk","attack","death": String}}`

- [ ] **Step 1: dev/fetch-assets.sh 작성**

```bash
#!/usr/bin/env bash
# KayKit(CC0) 에셋을 고정 커밋에서 받아 assets/models/ 아래에 둔다. 다시 실행해도 같은 결과.
# 출처: https://github.com/KayKit-Game-Assets (Kay Lousberg, CC0 — 표기 의무 없음)
set -euo pipefail
cd "$(dirname "$0")/.."
RAW=https://raw.githubusercontent.com/KayKit-Game-Assets
ADV_REPO="KayKit-Character-Pack-Adventures-1.0/672074b73ba276876a19e8816ecdc5241817ab47"
SKE_REPO="KayKit-Character-Pack-Skeletons-1.0/15b62b9bad122f72926c10fb14d622c73819fa54"
HEX_REPO="KayKit-Medieval-Hexagon-Pack-1.0/84fa4e91af6a88989be7c99e0891cede11f2ca38"
ADV="$RAW/$ADV_REPO/addons/kaykit_character_pack_adventures"
SKE="$RAW/$SKE_REPO/addons/kaykit_character_pack_skeletons"
HEX="$RAW/$HEX_REPO/addons/kaykit_medieval_hexagon_pack/Assets/gltf"
C=assets/models/characters
P=assets/models/props
H=assets/models/hex

get() { mkdir -p "$(dirname "$2")"; curl -sfL -o "$2" "$1" || { echo "download failed: $1" >&2; exit 1; }; }

for f in Knight Rogue_Hooded; do get "$ADV/Characters/gltf/$f.glb" "$C/$f.glb"; done
for f in Skeleton_Minion Skeleton_Warrior; do get "$SKE/Characters/gltf/$f.glb" "$C/$f.glb"; done
for f in arrow.gltf arrow.bin rogue_texture.png; do get "$ADV/Assets/gltf/$f" "$P/$f"; done
for f in Skeleton_Blade.gltf Skeleton_Blade.bin Skeleton_Axe.gltf Skeleton_Axe.bin skeleton_texture.png; do
	get "$SKE/Assets/gltf/$f" "$P/$f"
done
for f in castle barracks tavern blacksmith home_B lumbermill mine windmill tower_A; do
	for e in gltf bin; do get "$HEX/buildings/blue/building_${f}_blue.$e" "$H/building_${f}_blue.$e"; done
done
for f in wall_straight wall_straight_gate; do
	for e in gltf bin; do get "$HEX/buildings/neutral/$f.$e" "$H/$f.$e"; done
done
for f in trees_A_medium trees_B_large tree_single_A tree_single_B rock_single_A rock_single_C rock_single_E; do
	for e in gltf bin; do get "$HEX/decoration/nature/$f.$e" "$H/$f.$e"; done
done
get "$HEX/buildings/blue/hexagons_medieval.png" "$H/hexagons_medieval.png"

{
	for repo in "$ADV_REPO" "$SKE_REPO" "$HEX_REPO"; do
		echo "===== https://github.com/KayKit-Game-Assets/${repo%%/*} @ ${repo##*/}"
		curl -sfL "$RAW/$repo/LICENSE.txt"
		echo
	done
} > assets/models/LICENSE-KayKit.txt
echo "ok: $(find assets/models -type f | wc -l) files"
```

- [ ] **Step 2: 받기 + 같은 팔레트 텍스처 확인**

```bash
bash dev/fetch-assets.sh
du -sh assets/models
B=https://raw.githubusercontent.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0/84fa4e91af6a88989be7c99e0891cede11f2ca38/addons/kaykit_medieval_hexagon_pack/Assets/gltf
for d in buildings/neutral decoration/nature; do curl -sfL "$B/$d/hexagons_medieval.png" | md5sum; done; md5sum assets/models/hex/hexagons_medieval.png
```
Expected: `ok: N files`(약 50개), 약 20MB. 세 md5가 같다(건물·성벽·자연물이 같은 팔레트 텍스처 한 장을 공유). 다르면 보고하고 멈춘다.

- [ ] **Step 3: scripts/art.gd 작성**

```gdscript
extends RefCounted
## 아트 설정과 헬퍼 (구 flat.gd 흡수). 단색 메시 헬퍼, KayKit(CC0) 모델 경로·배율·애니메이션 표.
## 모델 출처·라이선스: assets/models/LICENSE-KayKit.txt, 다시 받기: dev/fetch-assets.sh
## 오토로드 참조 없음 → 헤드리스 테스트에서 preload 가능.

const HERO_SELECTED := Color(1.0, 0.9, 0.2)
# 아래 넷은 플레이스홀더용. Task 2·3에서 안 쓰게 되면 삭제.
const WALL := Color(0.86, 0.84, 0.78)
const TOWER := Color(0.78, 0.76, 0.70)
const GATE := Color(0.55, 0.38, 0.22)
const ARROW := Color(0.30, 0.22, 0.14)

const CHARACTER_SCALE := 0.75     # KayKit 캐릭터 키 약 2.2 → 약 1.65m
const CORPSE_SEC := 1.6           # 몬스터 사망 애니메이션 뒤 제거까지
const BUILDING_GAP := 0.6         # 건물 부지 가장자리 여유(m)
const WALL_MODEL_LEN := 2.0       # wall_straight 모델 치수(모델 단위): 길이·높이·두께
const WALL_MODEL_H := 1.1
const WALL_MODEL_T := 0.8
const WALL_PIECE_TARGET := 5.0    # 성벽 조각 목표 길이(m). 구간을 이 근처 길이로 균등 분할
const TOWER_SCALE := 3.2
const ARROW_SCALE := 1.2
const NATURE_SCALE := 3.0
const NATURE_COUNT := 60
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


## 바닥이 y=0에 닿는 박스. (플레이스홀더용 — Task 3 뒤 안 쓰면 삭제)
static func box(size: Vector3, color: Color) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := mesh(bm, color)
	mi.position.y = size.y / 2.0
	return mi


## 바닥이 y=0에 닿는 캡슐. (플레이스홀더용 — Task 2 뒤 안 쓰면 삭제)
static func capsule(radius: float, height: float, color: Color) -> MeshInstance3D:
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = height
	var mi := mesh(cm, color)
	mi.position.y = height / 2.0
	return mi


static func instance(path: String) -> Node3D:
	return (load(path) as PackedScene).instantiate()


## 모델 루트 기준 AABB (모든 MeshInstance3D 합, 루트 자신의 변환 제외). 트리에 없어도 된다.
static func model_aabb(root: Node3D) -> AABB:
	var box_sum := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b := xf * mi.get_aabb()
		box_sum = b if first else box_sum.merge(b)
		first = false
	return box_sum
```

- [ ] **Step 4: Flat → Art 이름 바꾸기, flat.gd 삭제**

`scripts/castle.gd`, `scripts/buildings.gd`, `scripts/hero.gd`, `scripts/monster.gd`에서 `const Flat := preload("res://scripts/flat.gd")`를 `const Art := preload("res://scripts/art.gd")`로, 본문의 `Flat.`을 `Art.`으로 바꾼다. 그 뒤:
```bash
git rm scripts/flat.gd scripts/flat.gd.uid
grep -rn "Flat\b\|flat.gd" scripts tests   # 0건
```

- [ ] **Step 5: 에셋 계약 테스트 추가 — tests/run_tests.gd**

상단 상수에 추가:
```gdscript
const Art := preload("res://scripts/art.gd")
```
`_init()` 호출 목록 끝(결과 출력 앞)에 추가:
```gdscript
	test_art_assets()
```
파일 끝에 추가:
```gdscript
func test_art_assets() -> void:
	var specs := {}
	specs.merge(Art.HERO_MODELS)
	specs.merge(Art.MONSTER_MODELS)
	for key in Balance.HERO_ROLES:
		check(Art.HERO_MODELS.has(key), "hero role %s has a model" % key)
	for key in Balance.MONSTER:
		check(Art.MONSTER_MODELS.has(key), "monster %s has a model" % key)
	for key in specs:
		var spec: Dictionary = specs[key]
		check(ResourceLoader.exists(spec.scene), "%s model exists" % key)
		if not ResourceLoader.exists(spec.scene):
			continue
		var root: Node = (load(spec.scene) as PackedScene).instantiate()
		var players := root.find_children("*", "AnimationPlayer", true, false)
		check(players.size() == 1, "%s has one AnimationPlayer" % key)
		if players.size() == 1:
			var ap: AnimationPlayer = players[0]
			for anim in spec.anims.values():
				check(ap.has_animation(anim), "%s has animation %s" % [key, anim])
		for mesh_name in spec.hide:
			check(root.find_child(mesh_name, true, false) != null, "%s has mesh %s to hide" % [key, mesh_name])
		if spec.has("weapon"):
			check(ResourceLoader.exists(spec.weapon), "%s weapon exists" % key)
			var skels := root.find_children("*", "Skeleton3D", true, false)
			check(skels.size() == 1 and (skels[0] as Skeleton3D).find_bone(Art.WEAPON_BONE) >= 0, "%s has bone %s" % [key, Art.WEAPON_BONE])
		root.free()
	for b in Balance.BUILDINGS:
		check(Art.BUILDING_MODELS.has(b.id) and ResourceLoader.exists(Art.BUILDING_MODELS[b.id]), "building %s has a model" % b.id)
	for path in [Art.WALL_MODEL, Art.GATE_MODEL, Art.TOWER_MODEL, Art.ARROW_MODEL] + Art.NATURE_MODELS:
		check(ResourceLoader.exists(path), "model exists: %s" % path)
	var gate: Node = (load(Art.GATE_MODEL) as PackedScene).instantiate()
	for door in Art.GATE_DOORS:
		check(gate.find_child(door, true, false) != null, "gate model has %s" % door)
	var wall: Node3D = (load(Art.WALL_MODEL) as PackedScene).instantiate()
	var wb := Art.model_aabb(wall)
	check(absf(wb.size.x - Art.WALL_MODEL_LEN) < 0.05 and absf(wb.size.y - Art.WALL_MODEL_H) < 0.05 and absf(wb.size.z - Art.WALL_MODEL_T) < 0.05, "wall model size matches Art constants: %s" % wb.size)
	gate.free()
	wall.free()
```

- [ ] **Step 6: 임포트 → RED/GREEN 확인**

1) 에셋을 받기 전에 테스트를 추가했다면 RED(모델 없음)를 보고서에 남긴다. 2) 임포트:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --editor --quit 2>&1 | grep -E "ERROR" | head
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd; echo "exit=$?"
```
Expected: `ALL PASSED`, 0. 실패하는 계약이 있으면(애니메이션 이름, 노드 이름이 임포트 뒤 달라짐 등) 실제 이름을 찾아 `art.gd` 표를 고친다 — 모델 파일은 고치지 않는다.

- [ ] **Step 7: 입력 체크 + 엔드투엔드 (동작 무변화 확인)**

Global Constraints의 두 명령. Expected: `INPUT ALL PASSED`, 스테이지 1→2.

- [ ] **Step 8: 커밋**

```bash
git add dev/fetch-assets.sh assets/models scripts tests
git status --short
git commit -m "feat: fetch KayKit CC0 models and add art config with asset contract test

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 캐릭터 모델 — 영웅·몬스터 애니메이션, 화살 모델

**Files:**
- Create: `scripts/unit_model.gd`
- Modify: `scripts/hero.gd`, `scripts/monster.gd`, `scripts/balance.gd`, `scripts/art.gd`, `tests/run_tests.gd`

**Interfaces:**
- Consumes: `Art.HERO_MODELS/MONSTER_MODELS`, `Art.CHARACTER_SCALE`, `Art.WEAPON_BONE`, `Art.CORPSE_SEC`, `Art.ARROW_MODEL`, `Art.ARROW_SCALE`, `Art.instance`
- Produces `unit_model.gd`(Node3D): `setup(spec: Dictionary, extra_scale := 1.0)`(add_child 전), `play_idle()`, `play_walk()`, `play_attack()`, `play_death()`, `reset_pose()`, `face(dir: Vector3)`

- [ ] **Step 1: scripts/unit_model.gd 작성**

```gdscript
extends Node3D
## 캐릭터 모델 래퍼: KayKit 모델 인스턴스, 안 쓰는 부착물 숨김, 무기 부착, 애니메이션 재생, 방향.
## spec = Art.HERO_MODELS[role] 또는 Art.MONSTER_MODELS[kind]. KayKit 모델 정면은 +Z.

const Art := preload("res://scripts/art.gd")

var _spec: Dictionary = {}
var _anim: AnimationPlayer
var _current := ""


## add_child 전에 호출.
func setup(spec: Dictionary, extra_scale := 1.0) -> void:
	_spec = spec
	scale = Vector3.ONE * Art.CHARACTER_SCALE * extra_scale


func _ready() -> void:
	var model := Art.instance(_spec.scene)
	add_child(model)
	for mesh_name in _spec.hide:
		var n := model.find_child(mesh_name, true, false) as Node3D
		if n != null:
			n.visible = false
	if _spec.has("weapon"):
		var skel := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var slot := BoneAttachment3D.new()
		slot.bone_name = Art.WEAPON_BONE
		skel.add_child(slot)
		slot.add_child(Art.instance(_spec.weapon))
	_anim = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for anim_name in [_spec.anims.idle, _spec.anims.walk]:
		_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR  # 공유 리소스라 한 번 바꾸면 전부 적용
	_anim.animation_finished.connect(_on_finished)
	play_idle()


func play_idle() -> void:
	_play(_spec.anims.idle)


func play_walk() -> void:
	_play(_spec.anims.walk)


## 공격 때마다 처음부터. 끝나면 대기로 돌아간다.
func play_attack() -> void:
	_current = _spec.anims.attack
	_anim.play(_current, 0.1)
	_anim.seek(0.0, true)


## 사망 애니메이션은 반복하지 않으므로 마지막 자세(쓰러짐)로 멈춘다.
func play_death() -> void:
	_play(_spec.anims.death)


## 리필 때: 사망 자세에서 대기로 즉시 복귀.
func reset_pose() -> void:
	_current = ""
	play_idle()


## 수평 방향 dir 쪽을 본다.
func face(dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() < 0.001:
		return
	rotation.y = atan2(dir.x, dir.z)


func _play(anim_name: String) -> void:
	if _current == anim_name:
		return
	_current = anim_name
	_anim.play(anim_name, 0.15)


func _on_finished(anim_name: StringName) -> void:
	if anim_name == _spec.anims.attack and _current == _spec.anims.attack:
		_current = ""
		play_idle()
```

- [ ] **Step 2: scripts/hero.gd 수정**

- 상단 상수에 `const UnitModelScript := preload("res://scripts/unit_model.gd")` 추가.
- `var _body: MeshInstance3D` → `var _model` (타입 없음).
- `_ready()`의 `_body = Art.capsule(...)` 두 줄을 다음으로 교체:
```gdscript
	_model = UnitModelScript.new()
	_model.setup(Art.HERO_MODELS[role])
	add_child(_model)
```
- `reset()`의 `_body.visible = true`를 `_model.reset_pose()`로 교체.
- `take_damage()`의 `_body.visible = false`를 `_model.play_death()`로 교체 (쓰러진 채 남는다).
- `_process()`를 다음으로 교체:
```gdscript
func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	_atk_cd -= delta
	var dest := stand_position()
	if global_position.distance_to(dest) > ARRIVE_EPS:
		state = State.MOVE
		_target = null
		_model.face(dest - global_position)
		_model.play_walk()
		global_position = global_position.move_toward(dest, float(_stats.speed) * delta)
		return
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = SCAN_INTERVAL
		_target = _nearest_monster()
	if _target != null and is_instance_valid(_target) and _target.is_alive():
		state = State.ATTACK
		_model.face(_target.global_position - global_position)
		if _atk_cd <= 0.0:
			_atk_cd = _stats.atk_interval
			_model.play_attack()
			if role == "archer":
				_fire_tracer(_target.global_position)
			_target.take_damage(_stats.atk)
	else:
		_target = null
		if state != State.IDLE:
			state = State.IDLE
			_model.play_idle()
```
- `_fire_tracer()`를 다음으로 교체 (화살 모델. 모델의 길이 축이 어느 쪽인지는 Step 6 캡처로 확인하고, 촉이 표적을 향하도록 `ARROW_YAW_FIX`(라디안, 기본 0)를 조정한다):
```gdscript
## 궁수 화살 (시각 효과만. 피해는 발사 즉시 적용).
func _fire_tracer(to: Vector3) -> void:
	var from := global_position + Vector3(0, 1.3, 0)
	var dest := to + Vector3(0, 0.8, 0)
	if Formation.flat_distance(from, dest) < 0.1:
		return
	var arrow := Node3D.new()
	var model := Art.instance(Art.ARROW_MODEL)
	model.scale = Vector3.ONE * Art.ARROW_SCALE
	model.rotation.y = ARROW_YAW_FIX
	arrow.add_child(model)
	get_parent().add_child(arrow)
	arrow.global_position = from
	arrow.look_at(dest)
	var tw := arrow.create_tween()
	tw.tween_property(arrow, "global_position", dest, TRACER_SEC)
	tw.tween_callback(arrow.queue_free)
```
그리고 상수 블록에 `const ARROW_YAW_FIX := 0.0  # 화살 모델 길이 축을 -Z(look_at 정면)에 맞추는 보정` 추가.

- [ ] **Step 3: scripts/monster.gd 수정**

- 상단 상수에 `const UnitModelScript := preload("res://scripts/unit_model.gd")` 추가.
- `var _body: MeshInstance3D` → `var _model`.
- `_ready()`의 캡슐 두 줄(`var s: float = _stats.scale` 포함)을 교체:
```gdscript
	_model = UnitModelScript.new()
	_model.setup(Art.MONSTER_MODELS[kind], float(_stats.scale))
	add_child(_model)
```
- `take_damage()`의 사망 분기를 교체:
```gdscript
	if hp == 0.0:
		_dead = true
		remove_from_group("monsters")  # 즉시 표적 대상에서 빠진다
		died.emit(self)
		_model.play_death()
		get_tree().create_timer(Art.CORPSE_SEC).timeout.connect(queue_free)
```
- `_process()`에서: 영웅 공격 분기는 `_model.face(_target_hero.global_position - global_position)` 후 공격 시 `_model.play_attack()`; 이동 분기는 `_model.face(dest - global_position)` + `_model.play_walk()`; 성문/성채 공격 분기는 `_model.face(dest - global_position)` + 타격 시 `_model.play_attack()`. 전체 교체본:
```gdscript
func _process(delta: float) -> void:
	if _dead:
		return
	_atk_cd -= delta
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = SCAN_INTERVAL
		_target_hero = _nearest_hero()
	if _target_hero != null and _target_hero.is_alive() and not _target_hero.is_on_wall():
		_model.face(_target_hero.global_position - global_position)
		if _atk_cd <= 0.0:
			_atk_cd = _stats.atk_interval
			_model.play_attack()
			_target_hero.take_damage(atk)
		return
	_target_hero = null
	var broken: bool = GameState.is_gate_broken(side)
	var dest: Vector3 = castle.keep_target(side) if broken else castle.gate_target(side)
	_model.face(dest - global_position)
	if Formation.flat_distance(global_position, dest) > _stats.range:
		_model.play_walk()
		global_position = global_position.move_toward(dest, _stats.speed * delta)
	elif _atk_cd <= 0.0:
		_atk_cd = _stats.atk_interval
		_model.play_attack()
		if broken:
			GameState.damage_castle(atk)
		else:
			GameState.damage_gate(side, atk)
```
(이동이 멈춘 뒤 다음 타격 전까지는 공격 애니메이션이 끝나 자동으로 대기로 돌아간다.)

- [ ] **Step 4: balance.gd·art.gd 정리 + 테스트 갱신**

- `balance.gd`: `MONSTER`의 두 `"color"` 항목과 `HERO_ROLES`의 두 `"color"` 항목 삭제. `epic_boss`의 `"scale": 2.5` → `1.6`(모델 기준 보스 크기).
- `art.gd`: `capsule()` 함수와 `ARROW` 색 상수 삭제(`grep -rn "Art.capsule\|Art.ARROW\b" scripts` 0건 확인 후).
- `tests/run_tests.gd`: 몬스터 키 목록에서 `"color"` 삭제(`["hp", "atk", "speed", "range", "atk_interval", "scale"]`), 역할 키 목록에서 `"color"` 삭제(`["name", "hp", "atk", "range", "atk_interval", "speed"]`).

- [ ] **Step 5: uid 생성 + 테스트 + 입력 체크 + 엔드투엔드**

`--editor --quit` 한 번 후 Global Constraints의 세 명령. Expected: 전부 통과, 스테이지 1→2.

- [ ] **Step 6: 웹 캡처로 확인**

`bash dev/build-web.sh`, 서버 실행 후 차례로:
```bash
W=.superpowers/sdd/2026-09-30-castlerpg-asset-pass
node dev/webshot.mjs --url "http://localhost:8060/?auto-stage" --out $W/t2-battle.png --wait 3000 --until "[mode] 1,14000" --wheel 180,320,-300 --wheel 180,320,-300 --wheel 180,320,-300
node dev/webshot.mjs --url "http://localhost:8060/?auto-stage" --out $W/t2-boss.png --wait 3000 --until "[cleared] 1,0"
```
두 번째 캡처는 클리어 직후라 보스가 이미 죽었을 수 있다 — 보스를 보려면 첫 번째와 같은 방식으로 `--until "[mode] 1,<보스 등장 시각 ms>"`를 엔드투엔드 로그로 가늠해 맞춘다(보스는 마지막 웨이브 뒤 약 36초에 스폰, 성까지 약 12초).
Read. Expected: 기사(칼·둥근 방패)가 성문 앞, 두건 쓴 궁수(석궁)가 성벽 위, 칼 든 해골이 걸어오고, 교전 중 공격 자세·쓰러진 해골·화살 모델이 보인다. 해골·영웅이 이동 방향을 보고 있다. 화살 촉이 표적 쪽이 아니면 `ARROW_YAW_FIX`를 `PI` 또는 `±PI/2`로 고쳐 다시 캡처. 캐릭터가 바닥에 묻히거나 떠 있으면 원인(모델 원점)을 확인해 `unit_model.gd`에서 보정하고 보고서에 적는다. 서버 종료.

- [ ] **Step 7: 커밋**

```bash
git add scripts tests
git commit -m "feat: animated KayKit heroes and skeletons with weapons and arrow model

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 성·건물·자연물 모델

**Files:**
- Modify (전체 교체): `scripts/castle.gd`, `scripts/buildings.gd`
- Modify: `scripts/main.gd` (buildings에 `half` 전달), `scripts/balance.gd`(`TOWER_H`, `BUILDINGS`의 `height`·`color` 삭제), `scripts/art.gd`(플레이스홀더 색·`box()` 삭제)

**Interfaces:**
- Consumes: `Art.WALL_MODEL/GATE_MODEL/GATE_DOORS/TOWER_MODEL/TOWER_SCALE/WALL_MODEL_*/WALL_PIECE_TARGET/BUILDING_MODELS/BUILDING_GAP/NATURE_*/LANE_HALF_WIDTH`, `Art.instance`, `Art.model_aabb`
- Produces: castle 공개 API 그대로(`half`, `gate_target`, `keep_target`, `slot_position`, `spawn_position`), 탭 영역 그대로(성문 2, 성벽 8). buildings: `var half: float`(add_child 전에 설정)

- [ ] **Step 1: scripts/castle.gd 전체 교체**

```gdscript
extends Node3D
## 성벽 4면 + 모서리 탑 + 성문 4개 (KayKit 모델). 성문 HP의 진실은 GameState.
## 여기는 시각화·탭 판정 영역·위치 제공만. 크기는 GameState.keep_level의 내부 크기,
## 위치 계산은 Formation static 함수에 위임한다.
## 성벽은 wall_straight 조각을 "성문 가장자리 ~ 모서리 탑 가장자리" 구간에 균등 분할로 채운다.
## side: 0=N(-z) 1=E(+x) 2=S(+z) 3=W(-x)

const Balance := preload("res://scripts/balance.gd")
const Art := preload("res://scripts/art.gd")
const Formation := preload("res://scripts/formation.gd")

const LAYER_GATE := 2
const LAYER_WALL := 8
const TAP_MARGIN := Vector3(1, 1, 1)  # 탭 판정 박스 여유

var half: float = 0.0
var _gate_doors: Array = []  # side -> [문짝 Node3D 두 개]


func _ready() -> void:
	half = Balance.interior_half(GameState.keep_level)
	var c := half + Balance.WALL_T / 2.0  # 성벽 중심선
	var run := c - Balance.TOWER_SIZE / 2.0 - Balance.GATE_W / 2.0
	var pieces := maxi(1, roundi(run / Art.WALL_PIECE_TARGET))
	var piece_len := run / pieces
	var sy := Balance.WALL_H / Art.WALL_MODEL_H
	var sz := Balance.WALL_T / Art.WALL_MODEL_T
	for side in 4:
		var dir: Vector3 = Formation.SIDE_DIR[side]
		var perp := Formation.perp(side)
		var center := Formation.gate_position(half, side)
		var yaw := atan2(dir.x, dir.z)  # 모델 정면(+Z)이 성 바깥을 보게
		var gate := _place(Art.GATE_MODEL, center, yaw, Vector3(Balance.GATE_W / Art.WALL_MODEL_LEN, sy, sz))
		var doors: Array = []
		for door_name in Art.GATE_DOORS:
			doors.append(gate.find_child(door_name, true, false))
		_gate_doors.append(doors)
		_add_tap_area(center, _along(perp, Balance.GATE_W, Balance.WALL_H, Balance.WALL_T), LAYER_GATE, side)
		var seg_len := half + Balance.WALL_T - Balance.GATE_W / 2.0
		for s in [-1.0, 1.0]:
			for i in pieces:
				var along: float = Balance.GATE_W / 2.0 + piece_len * (i + 0.5)
				_place(Art.WALL_MODEL, center + perp * s * along, yaw, Vector3(piece_len / Art.WALL_MODEL_LEN, sy, sz))
			var seg_center: Vector3 = center + perp * s * (Balance.GATE_W + seg_len) / 2.0
			_add_tap_area(seg_center, _along(perp, seg_len, Balance.WALL_H, Balance.WALL_T), LAYER_WALL, side)
	for corner in [Vector3(c, 0, c), Vector3(-c, 0, c), Vector3(c, 0, -c), Vector3(-c, 0, -c)]:
		_place(Art.TOWER_MODEL, corner, 0.0, Vector3.ONE * Art.TOWER_SCALE)
	GameState.gate_hp_changed.connect(_on_gate_hp_changed)


func gate_target(side: int) -> Vector3:
	return Formation.gate_target(half, side)


func keep_target(side: int) -> Vector3:
	return Formation.keep_target(side)


func slot_position(side: int, post: int, slot: int) -> Vector3:
	return Formation.slot_position(half, side, post, slot)


func spawn_position(side: int) -> Vector3:
	return Formation.spawn_center(half, side) \
		+ Formation.perp(side) * randf_range(-Balance.SPAWN_SPREAD, Balance.SPAWN_SPREAD)


func _place(path: String, pos: Vector3, yaw: float, scl: Vector3) -> Node3D:
	var n := Art.instance(path)
	n.position = pos
	n.rotation.y = yaw
	n.scale = scl
	add_child(n)
	return n


## perp 방향 길이 length, 높이 height, 면 방향 두께 thickness 인 박스 크기.
func _along(perp: Vector3, length: float, height: float, thickness: float) -> Vector3:
	if absf(perp.x) > 0.5:
		return Vector3(length, height, thickness)
	return Vector3(thickness, height, length)


func _add_tap_area(ground_center: Vector3, size: Vector3, layer: int, side: int) -> void:
	var area := Area3D.new()
	area.collision_layer = layer
	area.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size + TAP_MARGIN
	cs.shape = shape
	area.add_child(cs)
	area.position = ground_center + Vector3(0, size.y / 2.0, 0)
	area.set_meta("side", side)
	add_child(area)


func _on_gate_hp_changed(side: int, hp: float, _hp_max: float) -> void:
	for door in _gate_doors[side]:
		door.visible = hp > 0.0
```

- [ ] **Step 2: scripts/buildings.gd 전체 교체**

```gdscript
extends Node3D
## 성 안 건물(KayKit 모델, 기능 없음 — 서브프로젝트 2)과 성 밖 자연물 장식.
## 건물은 모델 AABB를 재서 부지에 맞는 최대 균일 배율로 놓는다. 자연물은 시드 고정 난수로 흩는다.

const Balance := preload("res://scripts/balance.gd")
const Art := preload("res://scripts/art.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

var half: float = 16.0  # 성 내부 절반 크기. main이 add_child 전에 castle.half로 설정


func _ready() -> void:
	for b in Balance.BUILDINGS:
		_place_building(b)
	_scatter_nature()


func _place_building(b: Dictionary) -> void:
	var plot := Vector2(b.size.x * Balance.TILE - Art.BUILDING_GAP, b.size.y * Balance.TILE - Art.BUILDING_GAP)
	var center := Vector3((b.cell.x + b.size.x / 2.0) * Balance.TILE, 0, (b.cell.y + b.size.y / 2.0) * Balance.TILE)
	var model := Art.instance(Art.BUILDING_MODELS[b.id])
	var box := Art.model_aabb(model)
	var s := minf(plot.x / box.size.x, plot.y / box.size.z)
	model.scale = Vector3.ONE * s
	model.position = center - Vector3(box.get_center().x, box.position.y, box.get_center().z) * s
	add_child(model)
	var label := Label3D.new()
	label.text = b.name
	label.font = FONT
	label.font_size = 48
	label.outline_size = 12
	label.pixel_size = 0.03
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(0.18, 0.18, 0.22)
	label.outline_modulate = Color(1, 1, 1, 0.9)
	label.position = center + Vector3(0, box.size.y * s + 1.0, 0)
	add_child(label)


## 성벽 근처·괴물 진입로(두 축)·서로 가까운 자리를 피해 나무·바위를 흩는다.
func _scatter_nature() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Art.NATURE_SEED
	var keep_out := half + Balance.WALL_T + Art.NATURE_CASTLE_MARGIN
	var lim := Balance.MAP_HALF - 4.0
	var placed: Array[Vector2] = []
	var tries := 0
	while placed.size() < Art.NATURE_COUNT and tries < Art.NATURE_COUNT * 20:
		tries += 1
		var p := Vector2(rng.randf_range(-lim, lim), rng.randf_range(-lim, lim))
		if maxf(absf(p.x), absf(p.y)) < keep_out:
			continue
		if absf(p.x) < Art.LANE_HALF_WIDTH or absf(p.y) < Art.LANE_HALF_WIDTH:
			continue
		var crowded := false
		for q in placed:
			if p.distance_to(q) < Art.NATURE_MIN_GAP:
				crowded = true
				break
		if crowded:
			continue
		placed.append(p)
		var n := Art.instance(Art.NATURE_MODELS[rng.randi_range(0, Art.NATURE_MODELS.size() - 1)])
		n.position = Vector3(p.x, 0, p.y)
		n.rotation.y = rng.randf_range(0.0, TAU)
		n.scale = Vector3.ONE * Art.NATURE_SCALE * rng.randf_range(0.8, 1.2)
		add_child(n)
```

- [ ] **Step 3: scripts/main.gd — buildings에 half 전달**

`add_child(BuildingsScript.new())`를 교체:
```gdscript
	var scenery = BuildingsScript.new()
	scenery.half = castle.half
	add_child(scenery)
```

- [ ] **Step 4: 쓰지 않게 된 것 삭제**

- `balance.gd`: `const TOWER_H := 4.5` 줄, `BUILDINGS` 각 항목의 `"height": ..., "color": ...` 키 삭제. (`TOWER_SIZE`는 성벽 구간 계산에 계속 쓴다.)
- `art.gd`: `box()` 함수, `WALL`·`TOWER`·`GATE` 색 상수와 그 위 주석 삭제.
- 확인: `grep -rn "TOWER_H\|b.height\|b.color\|Art.box\|Art.WALL\b\|Art.TOWER\b\|Art.GATE\b" scripts tests` → 0건.

- [ ] **Step 5: 테스트 + 입력 체크 + 엔드투엔드**

세 명령. Expected: 전부 통과(입력 체크는 성문·성벽 탭 영역이 그대로이므로 통과해야 한다).

- [ ] **Step 6: 웹 캡처로 확인**

빌드·서버 후:
```bash
W=.superpowers/sdd/2026-09-30-castlerpg-asset-pass
node dev/webshot.mjs --out $W/t3-overview.png --wait 6000
node dev/webshot.mjs --out $W/t3-zoom.png --wait 6000 --wheel 180,320,-300 --wheel 180,320,-300 --wheel 180,320,-300
node dev/webshot.mjs --out $W/t3-outside.png --wait 6000 --drag 180,320,300,200
```
Read. Expected: 모델 성벽이 네 면에 끊김 없이 이어지고(조각 사이 틈·겹침 확인), 성문 아치와 문짝, 모서리 탑 4개, 건물 8채가 부지 안에(서로·도로·성벽과 겹치지 않음) 이름표와 함께, 성 밖에 나무·바위가 네 진입로를 비워 두고 흩어져 있다. 성벽 윗면 높이에 궁수가 서 있다(묻히거나 떠 있지 않음). 문제가 보이면 원인을 찾아 고친다 — 조정 가능한 값은 `art.gd`의 배율·간격 상수와 `Balance.TOWER_SIZE`; 규칙 값(`WALL_H`, `WALL_T`, `GATE_W`, 슬롯)은 바꾸지 않는다. 서버 종료.

- [ ] **Step 7: 커밋**

```bash
git add scripts
git commit -m "feat: KayKit castle walls, gates, towers, buildings and nature scatter

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 그림자·HUD 스타일 + 최종 확인

**Files:**
- Modify: `scripts/main.gd` (조명), `scripts/hud.gd` (스타일)
- Modify: `docs/superpowers/specs/2026-09-30-castlerpg-asset-pass-design.md` (조정값 반영)

- [ ] **Step 1: scripts/main.gd `_build_environment()` 교체**

```gdscript
func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.86, 0.91, 0.96)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.78, 0.80, 0.86)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL  # 분할 없음: 모바일 부담 최소
	sun.directional_shadow_max_distance = 220.0
	add_child(sun)
	sun.rotation_degrees = Vector3(-55, 35, 0)
```

- [ ] **Step 2: scripts/hud.gd 스타일**

상단 상수 블록(파일 머리 주석 아래)에 추가:
```gdscript
const INK := Color(0.16, 0.18, 0.24)
const PANEL_BG := Color(1, 1, 1, 0.72)
const BAR_BG := Color(0, 0, 0, 0.12)
const ACCENT := Color(0.98, 0.70, 0.20)
const RADIUS := 14
```
`_ready()`에서 `var top := VBoxContainer.new()` 부분을 둥근 패널로 감싼다 — `root.add_child(top)` 대신:
```gdscript
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 16
	panel.offset_right = -16
	panel.offset_top = 16
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _round(PANEL_BG, RADIUS, 12))
	root.add_child(panel)
	panel.add_child(top)
```
(그리고 `top`의 앵커·오프셋 네 줄은 삭제 — 패널이 배치를 맡는다. `top.add_theme_constant_override("separation", 8)` 추가.)
`_stage_label`에 `add_theme_color_override("font_color", INK)` 추가.
`_center`에:
```gdscript
	_center.add_theme_color_override("font_color", Color.WHITE)
	_center.add_theme_color_override("font_outline_color", Color(INK, 0.85))
	_center.add_theme_constant_override("outline_size", 18)
```
`_button`에:
```gdscript
	_button.add_theme_stylebox_override("normal", _round(ACCENT, RADIUS + 6, 0))
	_button.add_theme_stylebox_override("hover", _round(ACCENT.lightened(0.12), RADIUS + 6, 0))
	_button.add_theme_stylebox_override("pressed", _round(ACCENT.darkened(0.15), RADIUS + 6, 0))
	_button.add_theme_stylebox_override("disabled", _round(Color(0.6, 0.62, 0.66, 0.8), RADIUS + 6, 0))
	_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_button.add_theme_color_override("font_color", Color.WHITE)
	_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	_button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.7))
```
`_bar()`에서 fill을 둥글게 하고 바탕 추가:
```gdscript
	b.custom_minimum_size = Vector2(0, 16)
	b.add_theme_stylebox_override("fill", _round(color, 8, 0))
	b.add_theme_stylebox_override("background", _round(BAR_BG, 8, 0))
```
(기존 `var fill := StyleBoxFlat.new()` 세 줄 대체.)
헬퍼 추가:
```gdscript
func _round(color: Color, radius: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s
```

- [ ] **Step 3: 테스트 + 입력 체크 + 엔드투엔드 + 패배 복귀**

세 명령 + 패배 복귀(`HERO_ROLES` 두 `atk`를 임시 1.0 → `[failed] 1` → `[mode] 0 stage=1` 확인 → 되돌리고 `git diff scripts/balance.gd` 비었는지 확인).

- [ ] **Step 4: 최종 웹 캡처**

빌드·서버 후 차례로:
```bash
W=.superpowers/sdd/2026-09-30-castlerpg-asset-pass
node dev/webshot.mjs --out $W/t4-idle.png --wait 6000
node dev/webshot.mjs --url "http://localhost:8060/?auto-stage" --out $W/t4-battle.png --wait 3000 --until "[mode] 1,16000" --wheel 180,320,-300 --wheel 180,320,-300
node dev/webshot.mjs --url "http://localhost:8060/?auto-stage" --out $W/t4-clear.png --wait 3000 --until "[cleared] 1,600"
```
Read. Expected: 그림자(건물·성벽·캐릭터 아래), 둥근 상단 패널과 둥근 체력바, 호박색 둥근 버튼, 전투 중 애니메이션, 클리어 배너 외곽선. 그림자 여드름(줄무늬)·끊김이 보이면 `sun.shadow_bias`/`shadow_normal_bias`를 조정하고 보고서에 적는다. 콘솔 `[pageerror]` 없음. 서버 종료.

- [ ] **Step 5: 문서·완료 기준**

spec 개정 3의 값 중 태스크에서 조정한 것(배율, 화살 보정, 그림자 설정 등)을 실제 값으로 고친다.
```bash
ls scripts/*.gd | wc -l   # 15 이하
du -sh export/web/index.pck   # 보고서에 기록 (참고)
```

- [ ] **Step 6: 커밋**

```bash
git add scripts docs
git commit -m "feat: sun shadows and rounded HUD styling for the asset pass

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 자체 검토

- **Spec 커버리지:** §1 출처·받기(T1), §2 매핑(T1 표, T2 캐릭터, T3 건물·성벽·자연물), §3 크기·배치(T2 배율·방향, T3 성벽 분할·탑·건물 맞춤·자연물 규칙), §4 동작(T2 사망·공격·화살, T3 문짝), §5 분위기(T4), §6 구조(T1 art, T2 unit_model, T2·T3 삭제), §7 테스트(T1 계약 테스트, 각 태스크 세 명령, 캡처), §8 완료(T4)
- **플레이스홀더:** 없음. 캡처 좌표·대기 시간은 방법을 명시. `ARROW_YAW_FIX`는 캡처로 정하는 보정값이며 기본값과 후보를 명시
- **이름 일관성:** `Art.HERO_MODELS[role]`·`MONSTER_MODELS[kind]` 키 = `Balance.HERO_ROLES`·`MONSTER` 키(T1 테스트가 검증). `UnitModel.setup/play_*/reset_pose/face` T2 정의 → hero·monster T2 사용. castle 공개 API 불변(T3) → spawner·monster·hero·picker·input_check 영향 없음. buildings `half` T3 정의 → main T3 설정
- **태스크 간 상태:** T1 뒤 게임 그대로(이름만 바뀜). T2 뒤 캐릭터 모델 + 플레이스홀더 성. T3 뒤 전부 모델. T4 조명·HUD

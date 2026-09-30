# CastleRPG 개정 5 구현 계획: 로우폴리 스타일 · 상호 인식 전투

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 모든 모델을 각진 로우폴리 음영으로 바꾸고 바닥을 삼각형 면으로, 맵 테두리에 로우폴리 산을 두르며, 영웅과 몬스터가 인식 반경 안에서 서로 쫓아가 싸우게 한다.

**Architecture:** 로우폴리는 셰이더 하나(`lowpoly.gdshader`)와 `Art.instance()` 한 지점 변환으로 전 모델에 적용. 인식 전투는 hero/monster의 표적 탐색·이동 분기만 바꾸고, 영역(성 안/밖) 판정은 `Formation.is_inside()`로 통일. 검증은 실제 씬을 도는 헤드리스 `tests/ai_check.tscn`.

**Tech Stack:** Godot 4.7.2 GDScript (Compatibility), KayKit CC0.

**Spec:** `docs/superpowers/specs/2026-09-30-castlerpg-lowpoly-aggro-design.md` (앞 개정보다 우선)

## Global Constraints

- Godot: `./tools/Godot_v4.7.2-stable_win64_console.exe` (Git Bash, 프로젝트 루트)
- **창 금지**: Godot는 항상 `--headless`. 브라우저 창 금지. 화면 확인은 `node dev/webshot.mjs`만(`--url`, `--out`, `--wait`, `--click`, `--drag`, `--wheel x,y,dy[,ms]`, `--until TEXT[,ms]`; CSS px, 뷰포트 360×640, PNG 2배; `?auto-stage`). 포트 8060 서버(pid 2492)가 `export/web`을 서빙 중 — `bash dev/build-web.sh`로 갱신만, 새 서버 금지, pid 2492 종료 금지. 캡처는 한 번에 하나
- 캡처 PNG는 `.superpowers/sdd/2026-09-30-castlerpg-lowpoly-aggro/`. Read가 EBADF면 `C:\Users\CIS\AppData\Local\Temp\claude\c--CastleRPG\34234939-4d72-4fe9-a2d8-370bd90c98b7\scratchpad\`로 복사해 읽는다. 본 것만 적는다
- `class_name` 금지, `const X := preload(...)`. 다른 스크립트 노드 변수는 타입 없이. 오토로드 enum을 `match` 패턴에 쓰지 않는다
- 물리 바디 없음. `Area3D`는 성문(2)·성벽(8) 탭 전용
- 로직 테스트 `--headless --path . -s tests/run_tests.gd` → `ALL PASSED`(스크립트 오류도 실패로 센다). 입력 체크 `--headless --path . res://tests/input_check.tscn` → `INPUT ALL PASSED`. 엔드투엔드 `--headless --path . --fixed-fps 60 --quit-after 9000 -- --auto-stage 2>&1 | grep -E "^\[(mode|cleared|failed)\]|SCRIPT ERROR"` → `[cleared] 1` 다음 `[mode] 1 stage=2`
- 새 `.gd`·`.gdshader`·에셋 → `--headless --path . --editor --quit`로 `*.uid`·`*.import` 생성 후 커밋
- 스크립트 16개 이내(테스트 제외). `python`은 스텁. 탭 들여쓰기, LF. 커밋 끝: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

---

### Task 1: 로우폴리 스타일

**Files:**
- Create: `shaders/lowpoly.gdshader`
- Modify: `scripts/art.gd`, `scripts/buildings.gd`, `scripts/main.gd`, `shaders/ground_grid.gdshader`, `dev/fetch-assets.sh`, `tests/run_tests.gd`
- Add assets: 산·언덕 6종 (`dev/fetch-assets.sh` 재실행)

**Interfaces:**
- Produces `Art.lowpoly_material(src: Material) -> Material`, `Art.apply_lowpoly(root: Node)`, `Art.instance()`가 변환 적용, `Art.BORDER_*` 상수·`BORDER_MODELS`

- [ ] **Step 1: 에셋 추가 받기**

`dev/fetch-assets.sh`의 자연물 루프 목록에 `mountain_A_grass_trees mountain_B_grass mountain_C_grass_trees hills_A_trees hills_B_trees hills_C_trees`를 추가하고 실행:
```bash
bash dev/fetch-assets.sh && ls assets/models/hex | grep -E "mountain|hills"
```

- [ ] **Step 2: shaders/lowpoly.gdshader 작성**

```glsl
shader_type spatial;

// 로우폴리 스타일: 원본 알베도(텍스처·색)는 그대로 쓰고, 법선은 화면 미분으로 면마다 하나 → 각진 면 음영.
// 앞면은 항상 카메라를 향하므로(뒷면 컬링) 법선을 카메라 쪽으로 맞춘다 — 화면 y축 방향 규약과 무관.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_texture = true;

void fragment() {
	vec4 c = albedo_color;
	if (use_texture) {
		c *= texture(albedo_tex, UV);
	}
	ALBEDO = c.rgb;
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, -VERTEX) < 0.0) {
		n = -n;
	}
	NORMAL = n;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
```

- [ ] **Step 3: art.gd — 로우폴리 변환, instance()가 적용, 테두리 상수**

상수 블록에 추가:
```gdscript
const LOWPOLY_SHADER := preload("res://shaders/lowpoly.gdshader")
const BORDER_INNER := 12.0        # 플레이 영역 가장자리(MAP_HALF)에서 테두리 띠 안쪽까지
const BORDER_OUTER := 40.0        # 테두리 띠 바깥쪽까지
const BORDER_SPACING := 22.0      # 테두리 산 간격(m)
const BORDER_SCALE_MIN := 10.0
const BORDER_SCALE_MAX := 14.0
const BORDER_SEED := 11
```
`NATURE_MODELS` 아래에:
```gdscript
const BORDER_MODELS := [
	HEX_DIR + "mountain_A_grass_trees.gltf", HEX_DIR + "mountain_B_grass.gltf", HEX_DIR + "mountain_C_grass_trees.gltf",
	HEX_DIR + "hills_A_trees.gltf", HEX_DIR + "hills_B_trees.gltf", HEX_DIR + "hills_C_trees.gltf",
]

static var _lowpoly_cache := {}  # 원본 재질 -> 로우폴리 재질 (같은 원본은 하나를 공유)
```
함수 추가, `instance()` 교체:
```gdscript
## 원본 재질의 알베도(텍스처·색)를 쓰는 로우폴리 재질. 발광·투명 재질(해골 눈 등)은 원본 그대로.
static func lowpoly_material(src: Material) -> Material:
	var base := src as BaseMaterial3D
	if base == null or base.emission_enabled or base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return src
	if _lowpoly_cache.has(src):
		return _lowpoly_cache[src]
	var m := ShaderMaterial.new()
	m.shader = LOWPOLY_SHADER
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
```
(`test_art_assets`는 `load().instantiate()`로 원본을 검사하므로 영향 없음.)

- [ ] **Step 4: buildings.gd — MultiMesh 재질 변환 + 테두리 산**

상단 상수에 `const Formation := preload("res://scripts/formation.gd")` 추가.
`_add_multimesh()`에서 `mm.mesh = mi.mesh`를 교체 — 표면 재질(로우폴리 변환 결과)을 담은 메시 사본을 쓴다(MultiMesh는 MeshInstance3D의 표면 재질 덮어쓰기를 모른다):
```gdscript
		var mesh := mi.mesh.duplicate() as Mesh
		for s in mesh.get_surface_count():
			mesh.surface_set_material(s, mi.get_active_material(s))
		mm.mesh = mesh
```
`_ready()`에 `_ring_mountains()` 호출 추가(자연물 다음). 함수:
```gdscript
## 플레이 영역 바깥 띠에 로우폴리 산·언덕을 한 바퀴 두른다(유닛은 들어가지 않는다). 시드 고정, 모델별 MultiMesh.
func _ring_mountains() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Art.BORDER_SEED
	var inner := Balance.MAP_HALF + Art.BORDER_INNER
	var outer := Balance.MAP_HALF + Art.BORDER_OUTER
	var steps := ceili(2.0 * outer / Art.BORDER_SPACING)
	var by_model := {}
	for side in 4:
		var dir: Vector3 = Formation.SIDE_DIR[side]
		var perp := Formation.perp(side)
		for i in steps + 1:
			var along := -outer + i * Art.BORDER_SPACING + rng.randf_range(-4.0, 4.0)
			var pos := dir * rng.randf_range(inner, outer) + perp * along
			var path: String = Art.BORDER_MODELS[rng.randi_range(0, Art.BORDER_MODELS.size() - 1)]
			var s := rng.randf_range(Art.BORDER_SCALE_MIN, Art.BORDER_SCALE_MAX)
			var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * s)
			if not by_model.has(path):
				by_model[path] = []
			by_model[path].append(Transform3D(basis, pos))
	for path in by_model:
		_add_multimesh(path, by_model[path])
```

- [ ] **Step 5: main.gd — 바닥 평면을 테두리까지**

`_build_ground()`의 평면 크기를 `Balance.MAP_HALF * 2.0`에서 `(Balance.MAP_HALF + Art.BORDER_OUTER + 15.0) * 2.0`로(main.gd에 `const Art := preload("res://scripts/art.gd")`가 없으면 추가).

- [ ] **Step 6: ground_grid.gdshader — 삼각형 면 명암**

uniform 추가: `uniform float facet_variation = 0.07;  // 타일을 대각선으로 나눈 두 삼각형의 명암 차이 폭`
`fragment()`에서 `base` 계산 직후(격자선 섞기 전)에:
```glsl
	// 로우폴리: 타일마다 대각선으로 나눈 두 삼각형에 서로 다른 명암
	vec2 cell = floor(p);
	float upper = step(fract(p).x, fract(p).y);
	float h = fract(sin(dot(cell + upper * vec2(0.37, 0.71), vec2(12.9898, 78.233))) * 43758.5453);
	base *= 1.0 + facet_variation * (h * 2.0 - 1.0);
```
캡처를 보고 체커(`grass_a/b` 교대)와 삼각형 명암이 함께 너무 요란하면 체커 두 색을 가깝게 하거나 `facet_variation`을 조정하고 값을 보고한다.

- [ ] **Step 7: 테스트 — tests/run_tests.gd**

`test_art_assets`의 존재 검사 목록에 `+ Art.BORDER_MODELS` 추가. 새 테스트(목록에 등록):
```gdscript
func test_lowpoly_conversion() -> void:
	for path in [Art.HERO_MODELS.warrior.scene, Art.MONSTER_MODELS.grunt.scene, Art.WALL_MODEL, Art.BUILDING_MODELS.keep]:
		var root: Node = Art.instance(path)
		var surfaces := 0
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				surfaces += 1
				var mat := mi.get_active_material(i)
				var ok := (mat is ShaderMaterial and (mat as ShaderMaterial).shader == Art.LOWPOLY_SHADER) \
					or (mat is BaseMaterial3D and ((mat as BaseMaterial3D).emission_enabled or (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED))
				check(ok, "%s surface %s/%d is low-poly (or an emissive/transparent exception)" % [path, mi.name, i])
		check(surfaces > 0, "%s has surfaces" % path)
		root.free()
	var a: Node = Art.instance(Art.WALL_MODEL)
	var b: Node = Art.instance(Art.WALL_MODEL)
	var ma: Material = (a.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).get_active_material(0)
	var mb: Material = (b.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).get_active_material(0)
	check(ma == mb, "same source material shares one low-poly material")
	a.free()
	b.free()
```
RED(변환 전 실패) 확인 → 구현 → GREEN.

- [ ] **Step 8: 임포트 + 세 명령**

`--editor --quit` 후 테스트·입력 체크·엔드투엔드.

- [ ] **Step 9: 웹 캡처**

`bash dev/build-web.sh` 후:
```bash
W=.superpowers/sdd/2026-09-30-castlerpg-lowpoly-aggro
node dev/webshot.mjs --out $W/t1-default.png --wait 6000
node dev/webshot.mjs --out $W/t1-close.png --wait 6000 --wheel 180,320,-300 --wheel 180,320,-300 --wheel 180,320,-300 --wheel 180,320,-300 --wheel 180,320,-300
node dev/webshot.mjs --out $W/t1-zoomout.png --wait 6000 --wheel 180,320,300 --wheel 180,320,300 --wheel 180,320,300 --wheel 180,320,300 --wheel 180,320,300 --wheel 180,320,300 --wheel 180,320,300 --wheel 180,320,300
```
Read. Expected: 가까이서 건물·성벽·캐릭터·나무 표면이 면 단위로 끊긴 명암(각진 면), 바닥 타일이 삼각형 두 개로 나뉜 명암, 줌아웃에서 맵을 둘러싼 산·언덕 띠. 면이 뒤집혀 까맣게 보이거나 텍스처가 사라진 모델이 있으면 원인을 찾아 고친다(예: 셰이더 법선, 텍스처 누락, 해골 눈 발광 유지). 본 것만 적는다.

- [ ] **Step 10: 커밋**

```bash
git add dev/fetch-assets.sh assets/models shaders scripts tests
git commit -m "feat: low-poly look (faceted shading, triangle tiles, mountain border)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 영웅·몬스터 상호 인식 전투

**Files:**
- Modify: `scripts/balance.gd`, `scripts/formation.gd`, `scripts/hero.gd`, `scripts/monster.gd`, `tests/run_tests.gd`, `tests/input_check.gd`
- Create: `tests/ai_check.tscn`, `tests/ai_check.gd`

**Interfaces:**
- Produces: `Balance.HERO_ROLES[*].aggro`, `Balance.MONSTER[*].aggro`; `Formation.is_inside(half, p) -> bool`(기존 `_is_inside` 공개, 호출부 모두 교체)

- [ ] **Step 1: balance.gd·formation.gd**

`HERO_ROLES`: 전사 `"aggro": 8.0`, 궁수 `"aggro": 12.0`. `MONSTER`: grunt `"aggro": 6.0`, epic_boss `"aggro": 8.0`.
`formation.gd`: `_is_inside` → `is_inside` (정의와 `route()` 안 호출 모두). `tests/run_tests.gd` 키 목록에 `"aggro"` 추가(역할·몬스터), `is_inside` 경계 테스트 추가:
```gdscript
	var half := Balance.interior_half(1)
	check(FormationScript.is_inside(half, Vector3(0, 0, -(half + Balance.WALL_T - 0.1))), "just inside the outer wall face counts as inside")
	check(not FormationScript.is_inside(half, Vector3(0, 0, -(half + Balance.WALL_T + 0.1))), "just outside the outer wall face counts as outside")
	check(FormationScript.is_inside(half, Vector3(0, Balance.WALL_H, -(half + Balance.WALL_T / 2.0))), "wall top counts as inside")
```
(기존 테스트 함수 하나에 넣거나 새 `test_is_inside()`로.)

- [ ] **Step 2: hero.gd — 인식·추격·복귀**

`_process()`에서 경로 분기 뒤 부분(현재 `if global_position.distance_to(stand_position()) > ARRIVE_EPS: _replan()` 부터 끝까지)을 교체:
```gdscript
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = SCAN_INTERVAL
		_target = _find_target()
	if _target != null and is_instance_valid(_target) and _target.is_alive():
		var tpos: Vector3 = _target.global_position
		_model.face(tpos - global_position)
		if Formation.flat_distance(global_position, tpos) > float(_stats.range):
			# 추격: 지상 영웅만 여기 온다(성벽 위 영웅의 표적은 늘 사거리 안).
			state = State.MOVE
			_model.play_walk()
			global_position = global_position.move_toward(Vector3(tpos.x, global_position.y, tpos.z), float(_stats.speed) * delta)
			return
		state = State.ATTACK
		if _atk_cd <= 0.0:
			_atk_cd = _stats.atk_interval
			_model.play_attack()
			if role == "archer":
				_fire_tracer(tpos)
			_target.take_damage(_stats.atk)
		return
	_target = null
	var home := stand_position()
	if global_position.distance_to(home) > ARRIVE_EPS:
		if not is_on_wall() and Formation.is_inside(castle.half, global_position) == Formation.is_inside(castle.half, home):
			# 추격 뒤 복귀: 같은 영역이면 곧장(도중에 새 표적을 만나면 다시 교전)
			state = State.MOVE
			_model.face(home - global_position)
			_model.play_walk()
			global_position = global_position.move_toward(home, float(_stats.speed) * delta)
			return
		_replan()  # 다른 영역이면 성문 경로로
		return
	if state != State.IDLE:
		state = State.IDLE
		_model.play_idle()
		_model.face(Formation.SIDE_DIR[side])
```
`_nearest_monster()`를 교체:
```gdscript
## 표적: 지상 영웅은 자기 자리에서 aggro 안·같은 영역, 성벽 위 영웅은 지금 위치에서 사거리 안(영역 무관). 가장 가까운 것.
## ponytail: 추격은 직선이다. 성벽 모서리 근처 자유 위치에서는 모서리를 스칠 수 있다 — 문제되면 추격에도 route() 사용.
func _find_target():
	var on_wall := is_on_wall()
	var origin := global_position if on_wall else stand_position()
	var reach: float = float(_stats.range) if on_wall else float(_stats.aggro)
	var here_inside := Formation.is_inside(castle.half, global_position)
	var best = null
	var best_d := INF
	for m in get_tree().get_nodes_in_group("monsters"):
		if not m.is_alive():
			continue
		if not on_wall and Formation.is_inside(castle.half, m.global_position) != here_inside:
			continue
		if Formation.flat_distance(origin, m.global_position) > reach:
			continue
		var d := Formation.flat_distance(global_position, m.global_position)
		if d < best_d:
			best_d = d
			best = m
	return best
```

- [ ] **Step 3: monster.gd — 인식·추격·진로 복귀**

`_process()` 교체, `_nearest_hero()`를 `_find_hero()`로 교체, `_advance()` 추가:
```gdscript
func _process(delta: float) -> void:
	if _dead:
		return
	_atk_cd -= delta
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = SCAN_INTERVAL
		_target_hero = _find_hero()
	if _target_hero != null and _target_hero.is_alive() and not _target_hero.is_on_wall():
		var hpos: Vector3 = _target_hero.global_position
		_model.face(hpos - global_position)
		if Formation.flat_distance(global_position, hpos) > _stats.range:
			_model.play_walk()
			global_position = global_position.move_toward(Vector3(hpos.x, 0.0, hpos.z), _stats.speed * delta)
		elif _atk_cd <= 0.0:
			_atk_cd = _stats.atk_interval
			_model.play_attack()
			_target_hero.take_damage(atk)
		return
	_target_hero = null
	_advance(delta)


## 진로: 성 밖이면 지금 가장 가까운 면의 성문으로(끌려간 뒤 재조준). 멀쩡하면 성문을 치고,
## 부서졌으면 성문 축에 맞춘 뒤 안쪽 지점을 거쳐 들어간다(성벽을 뚫지 않게). 성 안이면 성채를 친다.
func _advance(delta: float) -> void:
	var half: float = castle.half
	var inside := Formation.is_inside(half, global_position)
	if not inside:
		side = Formation.side_of(global_position)
	var dest: Vector3
	var strikes := true
	if inside:
		dest = castle.keep_target(side)
	elif GameState.is_gate_broken(side):
		strikes = false
		var aligned := absf(Formation.perp(side).dot(global_position)) < Balance.GATE_W / 2.0 - 0.5
		dest = Formation.gate_inner(half, side) if aligned else castle.gate_target(side)
	else:
		dest = castle.gate_target(side)
	_model.face(dest - global_position)
	var stop: float = _stats.range if strikes else 0.1
	if Formation.flat_distance(global_position, dest) > stop:
		_model.play_walk()
		global_position = global_position.move_toward(dest, _stats.speed * delta)
	elif strikes and _atk_cd <= 0.0:
		_atk_cd = _stats.atk_interval
		_model.play_attack()
		if inside:
			GameState.damage_castle(atk)
		else:
			GameState.damage_gate(side, atk)


## 표적: 자기 위치에서 aggro 안, 같은 영역의 살아 있는 지상 영웅 중 가장 가까운 것.
func _find_hero():
	var here_inside := Formation.is_inside(castle.half, global_position)
	var best = null
	var best_d: float = float(_stats.aggro)
	for h in get_tree().get_nodes_in_group("heroes"):
		if not h.is_alive() or h.is_on_wall():
			continue
		if Formation.is_inside(castle.half, h.global_position) != here_inside:
			continue
		var d := Formation.flat_distance(global_position, h.global_position)
		if d <= best_d:
			best_d = d
			best = h
	return best
```
(부서진 성문으로 들어가는 동안 `move_toward(gate_inner)`가 목표에 닿으면 다음 프레임부터 `inside`라 성채로 간다.)

- [ ] **Step 4: tests/ai_check.tscn + tests/ai_check.gd**

`tests/ai_check.tscn`: 루트 `Node` + 스크립트 `res://tests/ai_check.gd` (input_check.tscn과 같은 형식).
`tests/ai_check.gd` — spec §4의 (a)~(e)를 구현한다. 뼈대:
```gdscript
extends Node
## 헤드리스 AI 체크: 실제 main 씬(오토로드 포함)에서 영웅·몬스터 인식·추격·복귀·영역 규칙을 확인한다.
## 실행: ./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/ai_check.tscn
## 오토로드를 쓰므로 tests/run_tests.gd(-s)에서 preload 금지. 스포너를 멈추고 몬스터를 직접 놓는다.

const Balance := preload("res://scripts/balance.gd")
const Formation := preload("res://scripts/formation.gd")
const MonsterScript := preload("res://scripts/monster.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")

class ErrorCounter extends Logger:
	var count := 0
	func _log_error(_fn: String, _file: String, _line: int, _code: String, _why: String, _notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1

var _fails := 0
var _errors := ErrorCounter.new()
var _main
var _half := 0.0


func _ready() -> void:
	OS.add_logger(_errors)
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(5)
	for c in _main.get_children():
		if c.get_script() == SpawnerScript:
			c.set_process(false)
	_clear_monsters()
	_half = _main.castle.half
	await _run()
	_fails += _errors.count
	if _fails > 0:
		print("AI FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("AI ALL PASSED")
		get_tree().quit(0)


func _spawn(kind: String, side: int, pos: Vector3):
	var m = MonsterScript.new()
	m.setup(kind, side, 1, _main.castle)
	_main.add_child(m)
	m.global_position = pos
	return m


func _clear_monsters() -> void:
	for m in get_tree().get_nodes_in_group("monsters"):
		m.queue_free()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


## cond가 참이 될 때까지(최대 timeout초) 기다린다.
func _wait_until(cond: Callable, timeout: float) -> void:
	var t := 0.0
	while not cond.call() and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()


func _check(ok: bool, what: String, detail: String) -> void:
	if ok:
		print("AI PASS: " + what)
	else:
		_fails += 1
		print("AI FAIL: %s (%s)" % [what, detail])
```
`_run()` 사례(기본 배치: 영웅0 전사 북 성문 앞, 1 궁수 동 성벽 위, 2 전사 남 성문 앞, 3 궁수 서 성벽 위):
- (a) 전사0을 `move_to_point(Vector3(30, 0, -40))`로 보내 도착을 기다린 뒤, `_spawn("grunt", 0, 그 지점 + (5,0,0))`. 2초 뒤: grunt가 살아 있으면 둘의 수평 거리 ≤ 2.0, 그리고 전사 HP < 최대 또는 grunt HP < `hp_max`(또는 grunt가 이미 죽음).
- (b) grunt가 죽을 때까지(≤10초) 기다린 뒤 전사가 자기 지점 0.2m 안으로(≤5초) 돌아온다.
- (c) 전사0을 성 안 `Vector3(8, 0, -(half - 2))`로 보내 도착(성문 경유, ≤15초) 후, 성 밖 `Vector3(8, 0, -(half + WALL_T + 3))`에 grunt. 2초 뒤 전사는 자기 지점 0.3m 안, grunt의 `_target_hero == null`.
- (d) 몬스터 정리 후 동쪽 성벽 위 궁수1 위치의 수평 좌표 + (3.5, 0, 0)에 grunt(side 1). 3초 뒤 궁수 위치 불변(0.05 안)·HP 불변, grunt HP 감소(또는 죽음).
- (e) 몬스터 정리 후 `_spawn("grunt", 0, Vector3(half + WALL_T + 10, 0, 5))`(북 소속, 동쪽 밖). 0.5초 뒤 `side == 1`.
각 사례는 기능을 일부러 망가뜨려(예: 영웅 추격 분기 제거, 몬스터 aggro 0, 영역 조건 제거, side 재조준 제거) 실패하는지 확인하고 되돌린 것을 보고한다. 필요하면 지점을 조정하되(다른 영웅·진입로와 겹침 등) 이유를 적는다.

- [ ] **Step 5: input_check — 스포너 정지**

`tests/input_check.gd` `_ready()`에서 main 인스턴스 후 몇 프레임 기다린 다음, ai_check와 같은 방식으로 스포너 `set_process(false)` + 몬스터 정리(몬스터가 입력 사례에 끼어들지 않게). 사례 (a)~(i) 전부 통과.

- [ ] **Step 6: uid 생성 + 로직·입력·AI 체크 + 엔드투엔드 + 패배 복귀**

`--editor --quit` 후:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/ai_check.tscn; echo "exit=$?"
```
→ `AI ALL PASSED`, 0. 나머지 세 명령 + 패배 복귀(`HERO_ROLES` 두 `atk` 임시 1.0 → `[failed] 1` → `[mode] 0 stage=1`, 되돌린 뒤 `git diff scripts/balance.gd`에 aggro 추가 외 변화 없음). 스테이지 1이 실패하면 원인을 로그로 확인하고, 밸런스 문제면 `aggro` 값만 조정해(다른 스탯 금지) spec §2에 반영.

- [ ] **Step 7: 웹 캡처**

`bash dev/build-web.sh` 후:
```bash
W=.superpowers/sdd/2026-09-30-castlerpg-lowpoly-aggro
node dev/webshot.mjs --url "http://localhost:8060/?auto-stage" --out $W/t2-battle.png --wait 3000 --until "[mode] 1,22000" --wheel 180,320,-300 --wheel 180,320,-300 --wheel 180,320,-300
```
Read. Expected: 성문 앞 전사가 성문에서 조금 나와 해골과 붙어 싸우는 모습, HP 바. 본 것만 적는다.

- [ ] **Step 8: 커밋**

```bash
git add scripts tests docs
git commit -m "feat: heroes and monsters notice each other within aggro range and fight

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 자체 검토

- **Spec 커버리지:** §1 면 음영(T1 셰이더·변환·MultiMesh), 바닥 삼각형(T1 Step 6), 테두리(T1 Step 1·4·5); §2 aggro(T2 Step 1~3), 영역 규칙(`is_inside`), 성벽 위 예외, 몬스터 재조준·부서진 성문 경유; §4 테스트(T1 Step 7, T2 Step 1·4·5·6), 캡처(T1 Step 9, T2 Step 7)
- **이름 일관성:** `Art.LOWPOLY_SHADER/lowpoly_material/apply_lowpoly/instance` T1; `Formation.is_inside` T2 (정의·route·hero·monster·테스트); `aggro` 키 T2 balance → hero·monster·테스트

# CastleRPG 개정 4 구현 계획: 맵 확장 · 영웅 자유 이동 · 머리 위 HP 바

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 바깥 맵을 240m로 넓히고, 선택한 영웅을 바닥 탭으로 어디든(성문 경유 경로로) 옮기고, 모든 유닛 머리 위에 실시간 HP 바를 띄운다.

**Architecture:** 경로는 순수 `Formation.route()`(테스트)로, 영웅은 경로 지점을 차례로 따라간다. HP 바는 Node2D 하나가 두 그룹을 돌며 화면 공간에 한 번에 그린다. 자연물은 모델별 MultiMesh.

**Tech Stack:** Godot 4.7.2 GDScript (Compatibility).

**Spec:** `docs/superpowers/specs/2026-09-30-castlerpg-map-move-hpbar-design.md` (앞 개정보다 우선)

## Global Constraints

- Godot: `./tools/Godot_v4.7.2-stable_win64_console.exe` (Git Bash, 프로젝트 루트)
- **창 금지**: Godot는 항상 `--headless`. 브라우저 창 금지. 화면 확인은 `node dev/webshot.mjs`만(`--url`, `--out`, `--wait`, `--click x,y[,ms]`, `--drag`, `--wheel x,y,dy[,ms]`, `--dragback`, `--until TEXT[,ms]`; CSS px, 뷰포트 360×640, PNG 2배; `?auto-stage`). 포트 8060 서버(pid 2492)가 이미 `export/web`을 서빙 중 — `bash dev/build-web.sh`로 갱신만 하고, 새 서버를 띄우거나 pid 2492를 끄지 않는다. 캡처는 한 번에 하나
- 캡처 PNG는 `.superpowers/sdd/2026-09-30-castlerpg-map-move-hpbar/`. Read가 EBADF면 `C:\Users\CIS\AppData\Local\Temp\claude\c--CastleRPG\34234939-4d72-4fe9-a2d8-370bd90c98b7\scratchpad\`로 복사해서 읽는다. 본 것만 적는다
- `class_name` 금지, `const X := preload(...)`. 다른 스크립트의 노드를 담는 변수는 타입 없이. 오토로드 enum을 `match` 패턴에 쓰지 않는다
- 물리 바디 없음. `Area3D`는 성문(2)·성벽(8) 탭 전용. 영웅은 화면 거리로 고른다
- 이 계획이 명시한 것 외에 규칙·밸런스를 바꾸지 않는다
- 로직 테스트 `--headless --path . -s tests/run_tests.gd` → `ALL PASSED`(`-s`는 오토로드 없음 → `GameState` 참조 스크립트 preload 금지). 입력 체크 `--headless --path . res://tests/input_check.tscn` → `INPUT ALL PASSED`. 엔드투엔드 `--headless --path . --fixed-fps 60 --quit-after 9000 -- --auto-stage 2>&1 | grep -E "^\[(mode|cleared|failed)\]|SCRIPT ERROR"` → `[cleared] 1` 다음 `[mode] 1 stage=2`
- 새 `.gd` → `--headless --path . --editor --quit`로 `*.uid` 생성 후 커밋
- 스크립트 16개 이내(테스트 제외)
- `python`은 스텁. 탭 들여쓰기, LF. 커밋 끝: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

---

### Task 1: 맵 확장 + 자연물 MultiMesh

**Files:**
- Modify: `scripts/balance.gd`, `scripts/art.gd`, `scripts/buildings.gd`

**Interfaces:**
- Produces: `Art.relative_transform(node: Node3D, root: Node3D) -> Transform3D` (model_aabb와 공유), `Art.HEAD_HEIGHT` (Task 3에서 사용)

- [ ] **Step 1: 상수 변경**

`balance.gd`: `MAP_HALF := 70.0` → `120.0`, `SPAWN_MARGIN := 22.0` → `40.0`, `CAMERA_SIZE_MAX := 90.0` → `150.0` (주석 유지).
`art.gd`: `NATURE_COUNT := 60` → `180`. 상수 블록에 추가:
```gdscript
const HEAD_HEIGHT := 2.5          # 캐릭터 모델 발에서 HP 바까지 높이(모델 단위, 배율 곱하기 전)
```

- [ ] **Step 2: art.gd — relative_transform 추출, model_aabb가 사용**

`model_aabb()` 위에 추가하고 `model_aabb` 안의 변환 누적 루프를 이 함수 호출로 바꾼다:
```gdscript
## node의 root 기준 변환 (root 자신의 변환 제외). 트리에 없어도 된다.
static func relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != root:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func model_aabb(root: Node3D) -> AABB:
	var box_sum := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var b := relative_transform(mi, root) * mi.get_aabb()
		box_sum = b if first else box_sum.merge(b)
		first = false
	return box_sum
```

- [ ] **Step 3: buildings.gd — 자연물을 모델별 MultiMesh로**

`_scatter_nature()`를 교체하고 `_add_multimesh()`를 추가:
```gdscript
## 성벽 근처·괴물 진입로(두 축)·서로 가까운 자리를 피해 나무·바위를 흩는다.
## 모델 종류별(그 모델의 메시마다) MultiMeshInstance3D 하나로 그린다 — 수백 개여도 그리기 호출 몇 번.
func _scatter_nature() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Art.NATURE_SEED
	var keep_out := half + Balance.WALL_T + Art.NATURE_CASTLE_MARGIN
	var lim := Balance.MAP_HALF - 4.0
	var placed: Array[Vector2] = []
	var by_model := {}  # 모델 경로 -> Array[Transform3D]
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
		var path: String = Art.NATURE_MODELS[rng.randi_range(0, Art.NATURE_MODELS.size() - 1)]
		var s := Art.NATURE_SCALE * rng.randf_range(0.8, 1.2)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * s)
		if not by_model.has(path):
			by_model[path] = []
		by_model[path].append(Transform3D(basis, Vector3(p.x, 0, p.y)))
	for path in by_model:
		_add_multimesh(path, by_model[path])


func _add_multimesh(path: String, placements: Array) -> void:
	var model := Art.instance(path)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var local := Art.relative_transform(mi, model)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mi.mesh
		mm.instance_count = placements.size()
		for i in placements.size():
			mm.set_instance_transform(i, placements[i] * local)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
	model.free()
```
(`rng` 호출 순서가 바뀌므로 배치 모양은 이전과 달라진다 — 괜찮다. 시드 고정이라 매번 같다.)

- [ ] **Step 4: 테스트 + 입력 체크 + 엔드투엔드**

세 명령. Expected: 전부 통과(스폰이 멀어져 스테이지 시간이 늘어도 9000프레임 안에 `[mode] 1 stage=2`). 안 되면 몇 프레임에 클리어되는지 로그로 확인하고 보고(프레임 한도를 늘리는 건 컨트롤러 결정).

- [ ] **Step 5: 웹 캡처**

`bash dev/build-web.sh` 후:
```bash
W=.superpowers/sdd/2026-09-30-castlerpg-map-move-hpbar
node dev/webshot.mjs --out $W/t1-zoomout.png --wait 6000 --wheel 180,320,300 --wheel 180,320,300 --wheel 180,320,300 --wheel 180,320,300 --wheel 180,320,300
node dev/webshot.mjs --out $W/t1-default.png --wait 6000
```
Read. Expected: 줌아웃에서 성 주변으로 훨씬 넓은 들판, 숲·바위가 넓게 흩어져 있고 네 진입로가 비어 있음, 맵 가장자리 확인. 기본 줌은 이전과 비슷(성 전체). 자연물이 공중에 떠 있거나 묻혀 있지 않은지(MultiMesh 변환 확인) — 문제면 원인을 찾아 고친다.

- [ ] **Step 6: 커밋**

```bash
git add scripts
git commit -m "feat: larger outer map with instanced nature scatter

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 영웅 자유 이동 (성문 경유 경로)

**Files:**
- Modify: `scripts/formation.gd`, `scripts/hero.gd`, `scripts/unit_picker.gd`, `tests/run_tests.gd`, `tests/input_check.gd`

**Interfaces:**
- Produces `formation.gd`: `POST_FREE := 2`, `GATE_PASS_MARGIN := 1.0`, static `side_of(p: Vector3) -> int`, `gate_inner(half, side) -> Vector3`, `gate_outer(half, side) -> Vector3`, `route(half, from, to) -> Array[Vector3]` (도착점 포함)
- Produces `hero.gd`: `free_pos: Vector3`, `move_to_point(p: Vector3)`; `move_to()`도 경로를 다시 계산
- Produces `unit_picker.gd`: 선택 토글, 바닥 명령, 명령 링

- [ ] **Step 1: 실패하는 테스트 — tests/run_tests.gd**

`_init()` 목록 끝(결과 출력 앞)에 `test_route()` 추가, 파일 끝에:
```gdscript
func test_route() -> void:
	var half := Balance.interior_half(1)
	var F = FormationScript
	check(F.side_of(Vector3(0, 0, -30)) == 0 and F.side_of(Vector3(30, 0, 1)) == 1 and F.side_of(Vector3(2, 0, 30)) == 2 and F.side_of(Vector3(-30, 0, 0)) == 3, "side_of picks the facing side")
	for side in 4:
		var dir: Vector3 = F.SIDE_DIR[side]
		check(dir.dot(F.gate_inner(half, side)) < half, "gate inner point inside the walls, side %d" % side)
		check(dir.dot(F.gate_outer(half, side)) > half + Balance.WALL_T, "gate outer point outside the walls, side %d" % side)
	var inside_a := Vector3(-6, 0, -6)
	var inside_b := Vector3(6, 0, 6)
	check(F.route(half, inside_a, inside_b) == [inside_b], "inside to inside goes straight")
	var out_n := Vector3(5, 0, -40)
	var r: Array = F.route(half, inside_a, out_n)
	check(r == [F.gate_inner(half, 0), F.gate_outer(half, 0), out_n], "inside to outside leaves through the destination's gate: %s" % [r])
	r = F.route(half, out_n, inside_a)
	check(r == [F.gate_outer(half, 0), F.gate_inner(half, 0), inside_a], "outside to inside enters through the start's gate: %s" % [r])
	var out_s := Vector3(-5, 0, 40)
	r = F.route(half, out_n, out_s)
	check(r == [F.gate_outer(half, 0), F.gate_inner(half, 0), F.gate_inner(half, 2), F.gate_outer(half, 2), out_s], "outside across the castle goes gate to gate: %s" % [r])
	var out_n2 := Vector3(-25, 0, -40)
	check(F.route(half, out_n, out_n2) == [out_n2], "outside to outside on the same side goes straight")
	var gate_n := F.slot_position(half, 0, F.POST_GATE, 0)
	var gate_e := F.slot_position(half, 1, F.POST_GATE, 0)
	r = F.route(half, gate_n, gate_e)
	check(r.size() == 5 and r[0] == F.gate_outer(half, 0) and r[3] == F.gate_outer(half, 1), "adjacent gate fronts route through both gates: %s" % [r])
	var wall_e := F.slot_position(half, 1, F.POST_WALL, 0)
	r = F.route(half, wall_e, out_s)
	check(r == [F.gate_inner(half, 2), F.gate_outer(half, 2), out_s], "wall top to outside leaves through a gate: %s" % [r])
	r = F.route(half, out_s, wall_e)
	check(r == [F.gate_outer(half, 2), F.gate_inner(half, 2), wall_e], "outside to wall top enters through a gate: %s" % [r])
```
Run → RED(`side_of` 없음). 실제 출력을 보고서에.

- [ ] **Step 2: formation.gd 추가**

상수 블록(`POST_WALL` 다음)에:
```gdscript
const POST_FREE := 2          # 자유 위치 (슬롯 없음)
const GATE_PASS_MARGIN := 1.0 # 성문 통과 지점이 성벽에서 떨어진 거리
```
파일 끝(`flat_distance` 앞)에:
```gdscript
## p가 바라보는 면 (면 방향과의 내적이 가장 큰 면).
static func side_of(p: Vector3) -> int:
	var best := 0
	var best_d := -INF
	for s in 4:
		var d := SIDE_DIR[s].dot(p)
		if d > best_d:
			best_d = d
			best = s
	return best


static func gate_inner(half: float, side: int) -> Vector3:
	return SIDE_DIR[side] * (half - GATE_PASS_MARGIN)


static func gate_outer(half: float, side: int) -> Vector3:
	return SIDE_DIR[side] * (half + Balance.WALL_T + GATE_PASS_MARGIN)


## from → to 이동 경로 (도착점 포함). 성 안팎을 오가거나 성을 가로지를 때는 성문을 지난다.
## "안" = 성벽 위(높이 > WALL_H/2)이거나 성벽 중심선 안쪽. 문짝 상태와 무관하게 아군은 통과.
static func route(half: float, from: Vector3, to: Vector3) -> Array[Vector3]:
	var path: Array[Vector3] = []
	var from_in := _is_inside(half, from)
	var to_in := _is_inside(half, to)
	if from_in and not to_in:
		var s := side_of(to)
		path.append(gate_inner(half, s))
		path.append(gate_outer(half, s))
	elif not from_in and to_in:
		var s := side_of(from)
		path.append(gate_outer(half, s))
		path.append(gate_inner(half, s))
	elif not from_in and not to_in and _crosses_castle(half, from, to):
		var a := side_of(from)
		var b := side_of(to)
		path.append(gate_outer(half, a))
		path.append(gate_inner(half, a))
		if b != a:
			path.append(gate_inner(half, b))
			path.append(gate_outer(half, b))
	path.append(to)
	return path


static func _is_inside(half: float, p: Vector3) -> bool:
	return p.y > Balance.WALL_H / 2.0 or maxf(absf(p.x), absf(p.z)) < half + Balance.WALL_T / 2.0


## 수평 선분 a→b가 성 바깥 경계 정사각형(±(half + WALL_T))을 지나는지 (슬랩 테스트).
static func _crosses_castle(half: float, a: Vector3, b: Vector3) -> bool:
	var r := half + Balance.WALL_T
	var o := Vector2(a.x, a.z)
	var d := Vector2(b.x - a.x, b.z - a.z)
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
		if absf(d[axis]) < 1e-6:
			if absf(o[axis]) > r:
				return false
			continue
		var ta := (-r - o[axis]) / d[axis]
		var tb := (r - o[axis]) / d[axis]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return false
	return true
```
Run → GREEN.

- [ ] **Step 3: hero.gd — 자유 위치와 경로 따라 이동**

멤버 추가(`var slot` 다음):
```gdscript
var free_pos := Vector3.ZERO  # post == POST_FREE일 때 서는 곳
var _path: Array[Vector3] = []
```
`stand_position()` 교체:
```gdscript
func stand_position() -> Vector3:
	if post == Formation.POST_FREE:
		return free_pos
	return castle.slot_position(side, post, slot)
```
`move_to()`의 `return true` 앞에 `_replan()` 추가. 새 함수:
```gdscript
## 자유 이동 명령: 슬롯을 비우고 바닥 지점 p에 선다. 대기 방향은 가장 가까운 면의 바깥.
func move_to_point(p: Vector3) -> void:
	formation.release(index)
	post = Formation.POST_FREE
	free_pos = Vector3(p.x, 0.0, p.z)
	side = Formation.side_of(free_pos)
	_replan()


func _replan() -> void:
	if is_inside_tree():
		_path = Formation.route(castle.half, global_position, stand_position())
```
`reset()`에 `_path.clear()` 추가(순간 복귀 후 남은 경로 없음).
`_process()`에서 `var dest := stand_position()` 블록(이동 분기)을 경로 추종으로 교체:
```gdscript
	if not _path.is_empty():
		var wp: Vector3 = _path[0]
		state = State.MOVE
		_target = null
		_model.face(wp - global_position)
		_model.play_walk()
		global_position = global_position.move_toward(wp, float(_stats.speed) * delta)
		if global_position.distance_to(wp) <= ARRIVE_EPS:
			_path.pop_front()
		return
	if global_position.distance_to(stand_position()) > ARRIVE_EPS:
		_replan()  # 경로 없이 자리에서 벗어나 있으면(예: 명령 직후 첫 프레임) 다시 계산
		return
```
(그 아래 탐색·공격·대기 분기는 그대로.)

- [ ] **Step 4: unit_picker.gd — 선택 토글, 바닥 명령, 명령 링**

상단 상수에 추가:
```gdscript
const Balance := preload("res://scripts/balance.gd")
const Art := preload("res://scripts/art.gd")
const GROUND_MARGIN := 4.0   # 바닥 명령 지점을 맵 가장자리에서 이만큼 안으로 자른다
const MARKER_SEC := 0.5
```
`_physics_process()`의 선택된 영웅 분기(`var hero = _hero_at(screen_pos, HERO_TAP_PRECISE_PX)`부터 끝까지)를 교체:
```gdscript
	var hero = _hero_at(screen_pos, HERO_TAP_PRECISE_PX)
	if hero != null:
		_select(null if hero == selected else hero)  # 선택된 영웅을 다시 누르면 해제
		return
	var hit := _pick(screen_pos, LAYER_GATE)
	if not hit.is_empty():
		selected.move_to(hit.collider.get_meta("side"), Formation.POST_GATE)
		return
	hit = _pick(screen_pos, LAYER_WALL)
	if not hit.is_empty():
		selected.move_to(hit.collider.get_meta("side"), Formation.POST_WALL)
		return
	hero = _hero_at(screen_pos, HERO_TAP_PX)
	if hero != null:
		_select(hero)
		return
	var ground = _ground_point(screen_pos)
	if ground == null:
		_select(null)
		return
	selected.move_to_point(ground)
	_show_marker(ground)
```
함수 추가:
```gdscript
## 탭 위치의 바닥(y=0) 지점, 맵 안으로 자름. 바닥을 못 맞히면 null.
func _ground_point(screen_pos: Vector2):
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))
	if hit == null:
		return null
	var lim := Balance.MAP_HALF - GROUND_MARGIN
	return Vector3(clampf(hit.x, -lim, lim), 0.0, clampf(hit.z, -lim, lim))


## 바닥 명령 지점에 노란 링이 커지며 사라진다.
func _show_marker(p: Vector3) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.7
	var ring := Art.mesh(torus, Art.HERO_SELECTED)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(ring)
	ring.global_position = p + Vector3(0, 0.05, 0)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3.ONE * 1.8, MARKER_SEC)
	tw.tween_callback(ring.queue_free)
```
머리 주석의 판정 순서 설명을 spec §2의 순서(토글, 성문, 성벽, 32px 영웅, 바닥)로 고친다.

- [ ] **Step 5: 입력 체크 사례 추가 — tests/input_check.gd**

`_run()` 끝((e) 다음)에 추가하고 필요한 헬퍼를 넣는다(월드 지점의 화면 좌표는 `_camera.unproject_position(p)`; 몇 초 대기는 `await get_tree().create_timer(sec).timeout`):
- (f) 전사(h0, 북 성문 앞)를 선택하고 성 밖 바닥 `Vector3(6, 0, -(half + WALL_T + 8))`를 탭 → `warrior.post == Formation.POST_FREE`, 3초 뒤 그 지점과의 수평 거리 < 0.5. 탭 지점이 성문·성벽 탭 영역이나 다른 영웅 32px 안이 아닌지 먼저 확인(아니면 지점을 옮긴다)
- (g) 성벽 위 궁수를 선택하고 성 밖 남쪽 바닥 `Vector3(-10, 0, half + WALL_T + 12)`를 탭 → 탭 직후 `archer._path[0]`이 `Formation.gate_inner(half, 2)`와 같다(성문 경유)
- (h) 영웅을 선택하고 같은 영웅을 다시 탭 → `_picker.selected == null`
각 사례를 먼저 망가뜨려(예: 토글 줄 제거, 바닥 명령 제거) 실패하는지 확인하고 되돌린 것을 보고서에 적는다.

- [ ] **Step 6: uid 없음(새 스크립트 없음) → 테스트 + 입력 체크 + 엔드투엔드**

세 명령. Expected: 전부 통과.

- [ ] **Step 7: 웹 캡처 — 이동 확인**

`bash dev/build-web.sh` 후 `t2-base.png`(기본 줌)에서 전사 좌표를 읽고, 전사 선택 → 성 밖 빈 들판 탭 → 3초 대기 → 캡처:
```bash
W=.superpowers/sdd/2026-09-30-castlerpg-map-move-hpbar
node dev/webshot.mjs --out $W/t2-base.png --wait 6000
node dev/webshot.mjs --out $W/t2-moved.png --wait 6000 --click WX,WY,300 --click FX,FY,3500
```
(`WX,WY` 전사, `FX,FY` 성 밖 들판; CSS px = PNG px / 2.) Expected: 전사가 성 밖 들판 지점에 서 있고 선택 링. 궁수를 반대편 성 밖으로 보내는 캡처도 하나(`t2-archer-out.png`): 궁수가 성문을 지나 밖에 있는지(성벽을 뚫고 지나가지 않았는지는 경로 테스트가 보장). 본 것만 적는다.

- [ ] **Step 8: 커밋**

```bash
git add scripts tests
git commit -m "feat: move heroes anywhere by tapping the ground, routed through gates

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 머리 위 HP 바 + 최종 확인

**Files:**
- Create: `scripts/hp_bars.gd`
- Modify: `scripts/hero.gd`, `scripts/monster.gd`, `scripts/main.gd`
- Modify: spec(조정값 반영 시)

**Interfaces:**
- Consumes: 그룹 `"heroes"`, `"monsters"`; `Art.HEAD_HEIGHT`, `Art.CHARACTER_SCALE`
- Produces: 영웅·몬스터 `hp_ratio() -> float`, `bar_height() -> float`, `bar_scale() -> float`; `hp_bars.gd`(Node2D) `var camera: Camera3D`

- [ ] **Step 1: scripts/hp_bars.gd 작성**

```gdscript
extends Node2D
## 유닛 머리 위 실시간 HP 바(아군·적군). 매 프레임 두 그룹을 돌며 화면 공간에 한 번에 그린다 —
## 유닛마다 노드를 두지 않아 몬스터가 많아도 가볍다. HUD(CanvasLayer)보다 아래 캔버스에 그려진다.
## 유닛 인터페이스: is_alive(), hp_ratio(), bar_height(), bar_scale().

const BAR_W := 34.0           # 논리 px(720 폭 기준). 줌과 무관
const BAR_H := 5.0
const BORDER := 1.5
const SCREEN_MARGIN := 40.0   # 화면 밖 이만큼까지는 그린다(가장자리 걸친 유닛)
const HERO_COLOR := Color(0.35, 0.85, 0.40)
const MONSTER_COLOR := Color(0.92, 0.28, 0.22)
const BACK := Color(0, 0, 0, 0.55)

var camera: Camera3D


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if camera == null:
		return
	var view := get_viewport_rect().grow(SCREEN_MARGIN)
	_draw_group("heroes", HERO_COLOR, view)
	_draw_group("monsters", MONSTER_COLOR, view)


func _draw_group(group: String, color: Color, view: Rect2) -> void:
	for u in get_tree().get_nodes_in_group(group):
		if not u.is_alive():
			continue
		var p := camera.unproject_position(u.global_position + Vector3(0, u.bar_height(), 0))
		if not view.has_point(p):
			continue
		var w: float = BAR_W * u.bar_scale()
		var top_left := p - Vector2(w / 2.0, BAR_H / 2.0)
		draw_rect(Rect2(top_left - Vector2(BORDER, BORDER), Vector2(w + BORDER * 2.0, BAR_H + BORDER * 2.0)), BACK)
		draw_rect(Rect2(top_left, Vector2(w * clampf(u.hp_ratio(), 0.0, 1.0), BAR_H)), color)
```

- [ ] **Step 2: hero.gd·monster.gd — HP 바 인터페이스**

`hero.gd` 끝에:
```gdscript
func hp_ratio() -> float:
	return hp / float(_stats.hp)


func bar_height() -> float:
	return Art.HEAD_HEIGHT * Art.CHARACTER_SCALE


func bar_scale() -> float:
	return 1.0
```
`monster.gd`: 멤버 `var hp_max: float = 0.0` 추가, `setup()`의 `hp = ...` 다음 줄에 `hp_max = hp`. 끝에:
```gdscript
func hp_ratio() -> float:
	return hp / hp_max if hp_max > 0.0 else 0.0


func bar_height() -> float:
	return Art.HEAD_HEIGHT * Art.CHARACTER_SCALE * float(_stats.scale)


func bar_scale() -> float:
	return float(_stats.scale)
```

- [ ] **Step 3: main.gd — HP 바 추가**

상단 상수에 `const HpBarsScript := preload("res://scripts/hp_bars.gd")`. `camera = rig.camera` 다음에:
```gdscript
	var bars = HpBarsScript.new()
	bars.camera = camera
	add_child(bars)
```

- [ ] **Step 4: uid 생성 + 세 명령 + 패배 복귀**

`--editor --quit` 후 테스트·입력 체크·엔드투엔드. 패배 복귀(`HERO_ROLES` 두 `atk` 임시 1.0 → `[failed] 1` → `[mode] 0 stage=1` → 되돌리고 `git diff scripts/balance.gd` 비었는지).

- [ ] **Step 5: 최종 웹 캡처**

`bash dev/build-web.sh` 후 차례로:
```bash
W=.superpowers/sdd/2026-09-30-castlerpg-map-move-hpbar
node dev/webshot.mjs --out $W/t3-idle.png --wait 6000
node dev/webshot.mjs --url "http://localhost:8060/?auto-stage" --out $W/t3-battle.png --wait 3000 --until "[mode] 1,24000" --wheel 180,320,-300 --wheel 180,320,-300 --wheel 180,320,-300
node dev/webshot.mjs --url "http://localhost:8060/?auto-stage" --out $W/t3-clear.png --wait 3000 --until "[cleared] 1,600"
```
보스가 보이는 캡처가 필요하면 엔드투엔드 로그로 보스 도달 시각을 가늠해 `--until "[mode] 1,<ms>"`를 맞춘다.
Read. Expected: 영웅 머리 위 초록 바, 해골 머리 위 빨간 바, 맞은 해골은 바가 줄어 있음, 보스 바가 더 길다, 쓰러진 영웅·무너지는 해골에는 바 없음, HUD 패널이 바 위에 그려짐. 바가 머리와 너무 떨어지거나 겹치면 `Art.HEAD_HEIGHT`를 조정하고 보고. 본 것만 적는다.

- [ ] **Step 6: spec 동기화 + 완료 점검**

조정한 값이 있으면 spec 개정 4에 반영. `ls scripts/*.gd | wc -l` → 16 이하.

- [ ] **Step 7: 커밋**

```bash
git add scripts docs
git commit -m "feat: live HP bars above heroes and monsters

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 자체 검토

- **Spec 커버리지:** §1 맵(T1 상수·MultiMesh), §2 이동(T2 route·영웅·피커·링, 리필 유지는 `reset()`이 `stand_position()`을 쓰므로 자동), §3 HP 바(T3), §4 구조(T1~T3), §5 테스트(T2 route·입력 사례, 각 태스크 세 명령·캡처), §6 완료(T3)
- **플레이스홀더:** 없음. 캡처 좌표는 방법 명시
- **이름 일관성:** `Formation.POST_FREE/side_of/gate_inner/gate_outer/route` T2 정의 → hero·테스트 사용. `move_to_point` T2 → picker. `hp_ratio/bar_height/bar_scale` T3 정의 → hp_bars. `Art.HEAD_HEIGHT` T1 정의 → T3 사용. `Art.relative_transform` T1 정의·사용

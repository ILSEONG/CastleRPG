# CastleRPG 개정 6 구현 계획: 로우폴리 메시 · 성벽 계단 · 성 1.25배

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 성을 1.25배로 키우고, 각 면 성문 좌우 계단으로만 성벽 위에 오르게 하고, 성·건물·자연물·산을 코드로 만든 로우폴리 메시(면마다 단색, 각진 음영)로 바꾼다.

**Architecture:** 계단·영역·경로는 순수 `Formation`(테스트). 메시는 `mesh_kit.gd`(도형 도구)와 `town_kit.gd`(레시피)가 만들고, `castle.gd`·`buildings.gd`는 레시피 메시를 배치만 한다. 재질은 기존 로우폴리 셰이더에 정점 색을 켠 공유 재질 하나.

**Tech Stack:** Godot 4.7.2 GDScript (Compatibility + WebGL).

**Spec:** `docs/superpowers/specs/2026-10-01-castlerpg-lowpoly-mesh-stairs-design.md` (앞 개정보다 우선)

## Global Constraints

- Godot: `./tools/Godot_v4.7.2-stable_win64_console.exe` (Git Bash, 프로젝트 루트)
- **창 금지**: Godot는 항상 `--headless`. 브라우저 창 금지. 화면 확인은 `node dev/webshot.mjs`만(`--url`, `--out`, `--wait`, `--click`, `--drag`, `--wheel x,y,dy[,ms]`, `--until TEXT[,ms]`; CSS px, 뷰포트 360×640, PNG 2배; `?auto-stage`). 포트 8060에 컨트롤러가 띄운 숨김 서버가 `export/web`을 서빙 중 — `bash dev/build-web.sh`로 갱신만, 새 서버 금지, 8060 프로세스 종료 금지. 캡처는 한 번에 하나
- 캡처 PNG는 `.superpowers/sdd/2026-10-01-castlerpg-lowpoly-mesh-stairs/`. Read가 EBADF면 `C:\Users\CIS\AppData\Local\Temp\claude\c--CastleRPG\34234939-4d72-4fe9-a2d8-370bd90c98b7\scratchpad\`로 복사해 읽는다. 본 것만 적는다
- `class_name` 금지, `const X := preload(...)`. 다른 스크립트 노드 변수는 타입 없이. 오토로드 enum을 `match` 패턴에 쓰지 않는다
- 물리 바디 없음. `Area3D`는 성문(2)·성벽(8) 탭 전용
- 검증 명령: 로직 `--headless --path . -s tests/run_tests.gd` → `ALL PASSED`; 입력 `--headless --path . res://tests/input_check.tscn` → `INPUT ALL PASSED`; AI `--headless --path . res://tests/ai_check.tscn` → `AI ALL PASSED`; 엔드투엔드 `--headless --path . --fixed-fps 60 --quit-after 9000 -- --auto-stage 2>&1 | grep -E "^\[(mode|cleared|failed)\]|SCRIPT ERROR"` → `[cleared] 1` 다음 `[mode] 1 stage=2`
- 새 `.gd` → `--headless --path . --editor --quit`로 `*.uid` 생성 후 커밋. 지운 에셋은 `.import`도 함께 지운다
- 스크립트 18개 이내(테스트 제외). `python`은 스텁. 탭 들여쓰기, LF(`git stash` 금지 — CRLF로 바뀐 적 있음). 커밋 끝: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- 새 검사를 추가하면 기능을 일부러 망가뜨려 실패하는지 확인하고 되돌린 것을 보고한다

---

### Task 1: 성 1.25배 + 건물 재배치 + 계단 경로(로직)

**Files:** Modify `scripts/balance.gd`, `scripts/formation.gd`, `tests/run_tests.gd`, `tests/input_check.gd`, `tests/ai_check.gd`

**Interfaces:**
- Produces `Balance.STAIR_W/STAIR_GAP/STAIR_RUN/STAIR_STEPS`; `Formation.REGION_OUTSIDE/INSIDE/WALL`, `region(half, p) -> int`, `stair_bottom/stair_top/wall_landing(half, side, end: float) -> Vector3`, `route()`가 계단을 쓴다

- [ ] **Step 1: balance.gd**

`INTERIOR_TILES := [16, 20, 24]` → `[20, 24, 28]`. `CAMERA_SIZE_DEFAULT := 56.0` → `66.0`. 기하 상수 블록에 추가:
```gdscript
const STAIR_W := 2.0      # 계단 폭(성벽 안쪽 면에 붙은 1타일 띠)
const STAIR_GAP := 0.5    # 성문 가장자리 ~ 계단 윗단
const STAIR_RUN := 6.0    # 계단 수평 길이(윗단 → 아랫단, 성문 반대 방향)
const STAIR_STEPS := 8    # 계단 단 수(시각)
```
`BUILDINGS`의 cell을 spec §3 표대로 바꾼다(keep 그대로).

- [ ] **Step 2: 실패하는 테스트 — tests/run_tests.gd**

`test_stairs_and_wall_routes()` 추가(목록 등록):
```gdscript
func test_stairs_and_wall_routes() -> void:
	var F = FormationScript
	var half := Balance.interior_half(1)
	check(half == 20.0, "interior half is 20m at keep level 1 (1.25x)")
	for side in 4:
		var dir: Vector3 = F.SIDE_DIR[side]
		var pp: Vector3 = F.perp(side)
		for e in [-1.0, 1.0]:
			var top: Vector3 = F.stair_top(half, side, e)
			var bot: Vector3 = F.stair_bottom(half, side, e)
			var land: Vector3 = F.wall_landing(half, side, e)
			check(is_equal_approx(top.y, Balance.WALL_H) and bot.y == 0.0 and is_equal_approx(land.y, Balance.WALL_H), "stair heights side %d end %d" % [side, e])
			check(dir.dot(top) < half and dir.dot(bot) < half and dir.dot(top) > half - Balance.STAIR_W, "stairs sit in the strip inside the wall")
			check(absf(pp.dot(top)) > Balance.GATE_W / 2.0 and absf(pp.dot(bot)) > absf(pp.dot(top)), "stairs beside the gate, climbing toward it")
			check(F.region(half, land) == F.REGION_WALL and F.region(half, bot) == F.REGION_INSIDE, "landing is wall top, bottom is inside ground")
	var wall_n := F.slot_position(half, 0, F.POST_WALL, 1)   # 북쪽 성벽 위, +옆
	var inside := Vector3(6, 0, 6)
	var r: Array = F.route(half, inside, wall_n)
	var e_n := 1.0 if F.perp(0).dot(wall_n) >= 0.0 else -1.0
	check(r.size() >= 4 and r[-4] == F.stair_bottom(half, 0, e_n) and r[-3] == F.stair_top(half, 0, e_n) and r[-2] == F.wall_landing(half, 0, e_n) and r[-1] == wall_n, "inside to wall top climbs the stairs: %s" % [r])
	var out_s := Vector3(-5, 0, 45)
	r = F.route(half, wall_n, out_s)
	check(r[0] == F.wall_landing(half, 0, e_n) and r[1] == F.stair_top(half, 0, e_n) and r[2] == F.stair_bottom(half, 0, e_n), "wall top to outside goes down the stairs first: %s" % [r])
	check(r.has(F.gate_inner(half, 2)) and r.has(F.gate_outer(half, 2)) and r[-1] == out_s, "then leaves through a gate")
	var wall_n2 := F.slot_position(half, 0, F.POST_WALL, 0)
	check(F.route(half, wall_n, wall_n2) == [wall_n2], "same-side wall top walks straight")
	var wall_e := F.slot_position(half, 1, F.POST_WALL, 0)
	r = F.route(half, wall_n, wall_e)
	var e_e := 1.0 if F.perp(1).dot(wall_e) >= 0.0 else -1.0
	check(r[2] == F.stair_bottom(half, 0, e_n) and r[-4] == F.stair_bottom(half, 1, e_e) and r[-1] == wall_e, "wall top to another side's wall top goes down and up: %s" % [r])
	var out_n := Vector3(5, 0, -45)
	r = F.route(half, out_n, wall_n)
	check(r[0] == F.gate_outer(half, 0) and r[1] == F.gate_inner(half, 0) and r[-4] == F.stair_bottom(half, 0, e_n), "outside to wall top enters a gate then climbs: %s" % [r])
	# 어떤 구간도 성벽 띠를 곧장 오르내리지 않는다: 높이가 바뀌는 구간은 계단 윗단↔아랫단, 윗단↔landing 뿐
	for pair in [[inside, wall_n], [wall_n, out_s], [wall_n, wall_e], [out_n, wall_n]]:
		var pts: Array = [pair[0]] + F.route(half, pair[0], pair[1])
		for i in range(1, pts.size()):
			var a: Vector3 = pts[i - 1]
			var b: Vector3 = pts[i]
			if absf(a.y - b.y) > 0.01:
				var ok := false
				for s in 4:
					for e in [-1.0, 1.0]:
						var st: Vector3 = F.stair_top(half, s, e)
						var sb: Vector3 = F.stair_bottom(half, s, e)
						if (a.is_equal_approx(st) and b.is_equal_approx(sb)) or (a.is_equal_approx(sb) and b.is_equal_approx(st)):
							ok = true
				check(ok, "height changes only on a stair flight (%s -> %s)" % [a, b])
```
기존 테스트 중 half=16을 가정한 값(`interior_half(1) == 16.0`, route 사례 좌표 등)을 새 크기에 맞게 고친다. RED 확인.

- [ ] **Step 3: formation.gd — 영역·계단·경로**

상수에 추가:
```gdscript
const REGION_OUTSIDE := 0
const REGION_INSIDE := 1
const REGION_WALL := 2    # 성벽 위(계단 윗부분 포함)
```
함수 추가:
```gdscript
static func region(half: float, p: Vector3) -> int:
	if p.y > Balance.WALL_H / 2.0:
		return REGION_WALL
	if maxf(absf(p.x), absf(p.z)) < half + Balance.WALL_T:
		return REGION_INSIDE
	return REGION_OUTSIDE


## 계단: 각 면 성문 좌우(end = -1/+1)에 하나씩, 성벽 안쪽 면에 붙은 띠에서 성문 쪽으로 올라간다.
static func stair_bottom(half: float, side: int, end: float) -> Vector3:
	return SIDE_DIR[side] * (half - Balance.STAIR_W / 2.0) \
		+ perp(side) * (end * (Balance.GATE_W / 2.0 + Balance.STAIR_GAP + Balance.STAIR_RUN))


static func stair_top(half: float, side: int, end: float) -> Vector3:
	return SIDE_DIR[side] * (half - Balance.STAIR_W / 2.0) \
		+ perp(side) * (end * (Balance.GATE_W / 2.0 + Balance.STAIR_GAP)) + Vector3(0, Balance.WALL_H, 0)


## 계단 윗단에서 성벽 중심선으로 올라선 지점.
static func wall_landing(half: float, side: int, end: float) -> Vector3:
	return SIDE_DIR[side] * (half + Balance.WALL_T / 2.0) \
		+ perp(side) * (end * (Balance.GATE_W / 2.0 + Balance.STAIR_GAP)) + Vector3(0, Balance.WALL_H, 0)


static func _stair_end(side: int, p: Vector3) -> float:
	return 1.0 if perp(side).dot(p) >= 0.0 else -1.0
```
기존 `route()`의 본문을 `_ground_route(half, from, to)`로 이름만 바꿔 두고(지상 두 점 사이 — 성 안/밖/성문 규칙), 새 `route()`:
```gdscript
## from → to 이동 경로(도착점 포함). 성벽 위는 계단으로만 오르내린다(같은 면 성벽 위끼리는 곧장).
## 지상 구간은 성 안팎을 오갈 때 성문을 지난다(_ground_route).
static func route(half: float, from: Vector3, to: Vector3) -> Array[Vector3]:
	var path: Array[Vector3] = []
	var from_wall := region(half, from) == REGION_WALL
	var to_wall := region(half, to) == REGION_WALL
	if from_wall and to_wall and side_of(from) == side_of(to):
		path.append(to)
		return path
	var ground_from := from
	if from_wall:
		var s := side_of(from)
		var e := _stair_end(s, from)
		path.append(wall_landing(half, s, e))
		path.append(stair_top(half, s, e))
		ground_from = stair_bottom(half, s, e)
		path.append(ground_from)
	var ground_to := to
	var tail: Array[Vector3] = []
	if to_wall:
		var s2 := side_of(to)
		var e2 := _stair_end(s2, to)
		ground_to = stair_bottom(half, s2, e2)
		tail = [stair_top(half, s2, e2), wall_landing(half, s2, e2), to]
	path.append_array(_ground_route(half, ground_from, ground_to))
	path.append_array(tail)
	return path
```
(`_ground_route`의 첫 점이 `ground_from`과 같을 일은 없다 — 도착점만 끝에 붙는다.) `is_inside()`, `crosses_castle()`는 그대로. 영웅의 "추격 후 복귀는 route가 한 구간일 때만 곧장" 규칙은 새 route로 그대로 동작한다.

- [ ] **Step 4: 테스트 좌표 갱신 (input_check, ai_check)**

`half`가 16에서 20으로 바뀌었다. 하드코딩된 좌표(예: ai_check (a) `Vector3(30, 0, -40)`, (h) `(15,0,-20)`·`(18.1,0,-16.5)`, (i) 등)를 `half` 기준으로 다시 잡아 각 사례의 의도(밖/안/모서리/성문 축)가 유지되게 한다. 입력 체크에 사례 추가: 성 안 자유 위치 전사를 선택 → 북쪽 성벽 탭 → 경로에 `stair_bottom`·`stair_top`이 들어 있고 몇 초 뒤 성벽 위(y≈WALL_H) 자리에 도착. 모든 사례가 망가뜨리면 실패하는지 확인.

- [ ] **Step 5: 검증 + 커밋**

로직·입력·AI·엔드투엔드(스테이지 1→2). 커밋: `feat: castle 1.25x with stair-only wall access (routing and layout)`.

---

### Task 2: 메시 도구 + 로우폴리 성(성벽·문루·탑·계단)

**Files:** Create `scripts/mesh_kit.gd`, `scripts/town_kit.gd`; Modify `shaders/lowpoly.gdshaderinc`, `scripts/art.gd`, `scripts/castle.gd`, `tests/run_tests.gd`, `dev/fetch-assets.sh`; Delete KayKit `wall_straight*`, `building_tower_A_blue*` (+`.import`)

**Interfaces:**
- Produces `MeshKit`(RefCounted): `xform: Transform3D`, `tri/quad/box/gable/pyramid/prism_n(원기둥·원뿔대)/cone/rock`, `commit() -> ArrayMesh`, `triangle_count()`
- Produces `Art.lowpoly_vc_material() -> ShaderMaterial` (공유)
- Produces `TownKit` static: `wall_run(length) -> ArrayMesh`, `gatehouse() -> ArrayMesh`, `gate_doors() -> ArrayMesh`, `corner_tower() -> ArrayMesh`, `stairs() -> ArrayMesh`. 로컬 규약: 길이 방향 +X(가운데 기준), 두께 방향 Z(+Z = 성 바깥), 바닥 y=0

- [ ] **Step 1: 셰이더 정점 색**

`lowpoly.gdshaderinc`에 `uniform bool use_vertex_color = false;` 추가, `fragment()`에서 `if (use_texture) {...}` 다음에:
```glsl
	if (use_vertex_color) {
		// 정점 색은 sRGB로 적는다(팔레트 그대로). 셰이더 조명은 선형이라 변환한다.
		vec3 v = COLOR.rgb;
		c.rgb *= mix(pow((v + 0.055) / 1.055, vec3(2.4)), v / 12.92, step(v, vec3(0.04045)));
	}
```
`art.gd`에:
```gdscript
static var _vc_material: ShaderMaterial

## 코드로 만든 로우폴리 메시(정점 색)용 공유 재질.
static func lowpoly_vc_material() -> ShaderMaterial:
	if _vc_material == null:
		_vc_material = ShaderMaterial.new()
		_vc_material.shader = LOWPOLY_SHADER
		_vc_material.set_shader_parameter("use_texture", false)
		_vc_material.set_shader_parameter("use_vertex_color", true)
	return _vc_material
```
캡처에서 색이 팔레트보다 너무 어둡거나 밝으면 변환 유무를 확인해 고치고 보고한다.

- [ ] **Step 2: scripts/mesh_kit.gd**

```gdscript
extends RefCounted
## 로우폴리 메시 도구: 삼각형마다 정점을 따로 둬 면마다 단색·각진 음영(정점 색, 텍스처 없음).
## 사용: var k = MeshKit.new(); k.xform = Transform3D(...); k.box(...); ...; var mesh := k.commit()
## 면 감기: 각 면을 "바깥 방향(outward)"과 함께 넘기면 Godot 앞면 규약에 맞게 자동으로 정렬한다.
## 오토로드 참조 없음 → 헤드리스 테스트 가능.

## Godot 앞면 = 바깥에서 볼 때 시계 방향. 캡처에서 면이 사라지면(컬링) 이 값을 뒤집는다.
const CLOCKWISE_FRONT := true

var xform := Transform3D.IDENTITY
var _st := SurfaceTool.new()
var _tris := 0


func _init() -> void:
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


func triangle_count() -> int:
	return _tris


## 볼록 다각형 한 면(꼭짓점 순서 무관하게 둘레 순서로). outward = 면이 바라볼 방향(로컬).
func face(points: Array, outward: Vector3, color: Color) -> void:
	for i in range(1, points.size() - 1):
		var a: Vector3 = points[0]
		var b: Vector3 = points[i]
		var c: Vector3 = points[i + 1]
		var ccw_out := (b - a).cross(c - a).dot(outward) > 0.0
		if ccw_out == CLOCKWISE_FRONT:
			var t := b
			b = c
			c = t
		for v in [a, b, c]:
			_st.set_color(color)
			_st.add_vertex(xform * v)
		_tris += 1


## 바닥 중심 base, 크기 size인 상자. 바닥면은 기본 생략(땅에 붙는 물체).
func box(base: Vector3, size: Vector3, color: Color, with_bottom := false) -> void:
	var h := Vector3(size.x / 2.0, 0, size.z / 2.0)
	var y0 := base.y
	var y1 := base.y + size.y
	var p := [
		Vector3(base.x - h.x, y0, base.z - h.z), Vector3(base.x + h.x, y0, base.z - h.z),
		Vector3(base.x + h.x, y0, base.z + h.z), Vector3(base.x - h.x, y0, base.z + h.z),
	]
	var q := []
	for v in p:
		q.append(Vector3(v.x, y1, v.z))
	face(q, Vector3.UP, color)
	if with_bottom:
		face(p, Vector3.DOWN, color)
	for i in 4:
		var j := (i + 1) % 4
		var mid: Vector3 = (p[i] + p[j]) / 2.0 - base
		face([p[i], p[j], q[j], q[i]], Vector3(mid.x, 0, mid.z), color)


## 박공지붕: 바닥 중심 base, 가로 size.x(용마루 방향 X), 깊이 size.z, 높이 height. 처마 overhang.
func gable(base: Vector3, size: Vector3, height: float, color: Color, overhang := 0.25) -> void:
	var hx := size.x / 2.0 + overhang
	var hz := size.z / 2.0 + overhang
	var ridge_a := base + Vector3(-hx, height, 0)
	var ridge_b := base + Vector3(hx, height, 0)
	var e := [base + Vector3(-hx, 0, -hz), base + Vector3(hx, 0, -hz), base + Vector3(hx, 0, hz), base + Vector3(-hx, 0, hz)]
	face([e[0], e[1], ridge_b, ridge_a], Vector3(0, hz, -height), color)
	face([e[3], e[2], ridge_b, ridge_a], Vector3(0, hz, height), color)
	face([e[0], e[3], ridge_a], Vector3.LEFT, color.darkened(0.08))
	face([e[1], e[2], ridge_b], Vector3.RIGHT, color.darkened(0.08))


## n각 원뿔대(원기둥: r_top == r_bottom, 원뿔: r_top == 0). 바닥 중심 base. 윗면 포함.
func prism_n(base: Vector3, sides: int, r_bottom: float, r_top: float, height: float, color: Color, rot := 0.0) -> void:
	var bottom := []
	var top := []
	for i in sides:
		var a := rot + TAU * i / sides
		bottom.append(base + Vector3(cos(a) * r_bottom, 0, sin(a) * r_bottom))
		top.append(base + Vector3(cos(a) * r_top, height, sin(a) * r_top))
	for i in sides:
		var j := (i + 1) % sides
		var mid: Vector3 = (bottom[i] + bottom[j]) / 2.0 - base
		if r_top > 0.0:
			face([bottom[i], bottom[j], top[j], top[i]], Vector3(mid.x, 0, mid.z), color)
		else:
			face([bottom[i], bottom[j], base + Vector3(0, height, 0)], Vector3(mid.x, r_bottom / height, mid.z), color)
	if r_top > 0.0:
		face(top, Vector3.UP, color)


func cone(base: Vector3, sides: int, radius: float, height: float, color: Color, rot := 0.0) -> void:
	prism_n(base, sides, radius, 0.0, height, color, rot)


func pyramid(base: Vector3, size: float, height: float, color: Color) -> void:
	prism_n(base, 4, size * 0.7071, 0.0, height, color, PI / 4.0)


## 각진 바위: 20면체를 rng로 흔든다. 중심 center, 반지름 radius, 세로 납작함 squash.
func rock(center: Vector3, radius: float, color: Color, rng: RandomNumberGenerator, squash := 0.7) -> void:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	var f := [[0,11,5],[0,5,1],[0,1,7],[0,7,10],[0,10,11],[1,5,9],[5,11,4],[11,10,2],[10,7,6],[7,1,8],
		[3,9,4],[3,4,2],[3,2,6],[3,6,8],[3,8,9],[4,9,5],[2,4,11],[6,2,10],[8,6,7],[9,8,1]]
	var pts := []
	for p in v:
		var n: Vector3 = p.normalized() * radius * rng.randf_range(0.8, 1.15)
		pts.append(center + Vector3(n.x, n.y * squash, n.z))
	for tri_i in f:
		var a: Vector3 = pts[tri_i[0]]
		var b: Vector3 = pts[tri_i[1]]
		var c: Vector3 = pts[tri_i[2]]
		face([a, b, c], (a + b + c) / 3.0 - center, color.darkened(rng.randf_range(0.0, 0.12)))


func commit() -> ArrayMesh:
	_st.generate_normals()
	return _st.commit()
```

- [ ] **Step 3: scripts/town_kit.gd — 성 부품**

팔레트 상수(밝은 톤): `STONE := Color(0.82, 0.80, 0.76)`, `STONE_DARK := Color(0.66, 0.64, 0.61)`, `WOOD := Color(0.55, 0.38, 0.24)`, `ROOF_BLUE := Color(0.33, 0.52, 0.80)`, `ROOF_RED := Color(0.78, 0.33, 0.28)`, `ROOF_ORANGE := Color(0.90, 0.56, 0.28)`, `ROOF_PURPLE := Color(0.55, 0.42, 0.72)`, `PLASTER := Color(0.95, 0.92, 0.84)`, `LEAF := Color(0.40, 0.68, 0.38)`, `LEAF_DARK := Color(0.28, 0.52, 0.32)`, `ROCK := Color(0.62, 0.62, 0.64)`, `SNOW := Color(0.96, 0.97, 0.99)`, `CROP := Color(0.92, 0.80, 0.38)`, `FLAG := Color(0.88, 0.30, 0.28)`.
성 부품(로컬 규약: 길이 +X 가운데 기준, 두께 Z, +Z = 성 바깥, 바닥 y=0; 크기는 `Balance.WALL_T/WALL_H/GATE_W/TOWER_SIZE/STAIR_*`):
```gdscript
extends RefCounted
## 로우폴리 레시피: 성 부품·건물·자연물·산 메시를 만든다(MeshKit). 오토로드 참조 없음.
const Balance := preload("res://scripts/balance.gd")
const MeshKit := preload("res://scripts/mesh_kit.gd")
# (팔레트 상수)

## 성벽 한 토막: 몸통 + 바깥쪽 가장자리 톱니(1m 간격, 0.6m 높이) + 안쪽 낮은 난간.
static func wall_run(length: float) -> ArrayMesh:
	var k = MeshKit.new()
	k.box(Vector3.ZERO, Vector3(length, Balance.WALL_H, Balance.WALL_T), STONE)
	var n := maxi(1, floori(length / 1.0))
	var step := length / n
	for i in n:
		if i % 2 == 0:
			var x := -length / 2.0 + step * (i + 0.5)
			k.box(Vector3(x, Balance.WALL_H, Balance.WALL_T / 2.0 - 0.2), Vector3(step, 0.6, 0.4), STONE_DARK)
	k.box(Vector3(0, Balance.WALL_H, -Balance.WALL_T / 2.0 + 0.1), Vector3(length, 0.25, 0.2), STONE_DARK)
	return k.commit()
```
나머지(같은 파일, 같은 규약)를 만든다 — 크기는 괄호 안 값을 기준으로 캡처를 보며 다듬는다:
- `gatehouse()`: 성문 좌우 두 기둥 탑(각 1.2×(WALL_H+1.2)×(WALL_T+0.6), STONE) + 성문 위 통로 다리(GATE_W×0.6×WALL_T, 높이 WALL_H−0.6에서 시작, 위면이 WALL_H) + 기둥 탑 위 작은 파란 피라미드 지붕. 아래(0~WALL_H−0.6)는 비워 통로가 열려 있게.
- `gate_doors()`: 나무 문짝 두 짝(각 GATE_W/2−0.05 × (WALL_H−0.7) × 0.3, WOOD, 가로 띠 STONE_DARK 두 줄). 파괴 시 이 메시만 숨긴다.
- `corner_tower()`: 8각 기둥(반지름 TOWER_SIZE/2+0.2, 높이 WALL_H+2) + 윗단 톱니(8개 작은 박스) + 8각 원뿔 파란 지붕(높이 2.5) + 작은 깃발.
- `stairs()`: 로컬 규약이 다르다 — 길이 방향 +X로 올라간다: x=0에서 높이 0, x=STAIR_RUN에서 높이 WALL_H. 폭 Z=STAIR_W. `STAIR_STEPS`개 단을 박스로 쌓는다(단 i: x 구간 [i, i+1]×run/steps, 높이 (i+1)×WALL_H/steps, 바닥부터 채움). 가장자리 난간은 선택.

- [ ] **Step 4: castle.gd — 레시피 배치**

KayKit 인스턴스(`_place` + `Art.*_MODEL`)를 MeshInstance3D + `TownKit` 메시로 교체(재질 `Art.lowpoly_vc_material()`):
- 면마다: 문루(성문 중앙, yaw = atan2(dir.x, dir.z) — +Z가 바깥), 문짝(별도 MeshInstance3D, `_gate_doors[side]`), 성문 좌우 성벽 두 토막(각각 "성문 가장자리 ~ 모서리 탑 가장자리" 길이 한 메시), 계단 두 개(성벽 안쪽 띠, `Formation.stair_bottom/top` 사이: 로컬 +X가 아랫단→윗단 방향이 되게 회전, 폭 방향은 성벽 안쪽 면에 붙게).
- 네 모서리 탑.
- 탭 영역·공개 API·HP 문짝 토글은 그대로(`_on_gate_hp_changed`는 문짝 MeshInstance3D 하나 visible 토글로 단순화).
- 계단 캡처 확인: 계단 윗단이 성벽 위와 이어지고 아랫단이 땅에 닿는다. 영웅이 계단을 오를 때 발이 단에 대략 맞는다(경로는 직선 경사라 단보다 살짝 뜨거나 묻힐 수 있음 — 과하면 보고).

- [ ] **Step 5: 에셋·설정 정리 + 테스트**

`art.gd`에서 `WALL_MODEL`, `GATE_MODEL`, `GATE_DOORS`, `TOWER_MODEL`, `WALL_MODEL_LEN/H/T`, `WALL_PIECE_TARGET`, `TOWER_SCALE` 삭제(참조 0 확인). `dev/fetch-assets.sh`에서 `wall_straight*`, `tower_A` 받기 줄 삭제, 해당 파일·`.import` 삭제. `test_art_assets`의 해당 검사 삭제. 새 테스트:
```gdscript
func test_mesh_kit() -> void:
	var k = MeshKitScript.new()
	k.box(Vector3.ZERO, Vector3(2, 1, 3), Color.RED)
	check(k.triangle_count() == 10, "box without bottom = 5 faces = 10 triangles")
	var m: ArrayMesh = k.commit()
	var arrays := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	check(verts.size() == 30 and cols.size() == 30 and cols[0] == Color.RED, "unshared vertices with vertex colours")
	var aabb := m.get_aabb()
	check(aabb.position.is_equal_approx(Vector3(-1, 0, -1.5)) and aabb.size.is_equal_approx(Vector3(2, 1, 3)), "box bounds")
	# 감기: 모든 삼각형이 같은 규약(바깥 기준)으로 감겨 있다
	var center := Vector3(0, 0.5, 0)
	var consistent := true
	for i in range(0, verts.size(), 3):
		var a := verts[i]
		var b := verts[i + 1]
		var c := verts[i + 2]
		var out := (a + b + c) / 3.0 - center
		var ccw_out := (b - a).cross(c - a).dot(out) > 0.0
		if ccw_out == MeshKitScript.CLOCKWISE_FRONT:
			consistent = false
	check(consistent, "every box triangle wound front-facing outward")


func test_castle_parts() -> void:
	for pair in [["wall_run", TownKitScript.wall_run(10.0)], ["gatehouse", TownKitScript.gatehouse()], ["gate_doors", TownKitScript.gate_doors()], ["corner_tower", TownKitScript.corner_tower()], ["stairs", TownKitScript.stairs()]]:
		var m: ArrayMesh = pair[1]
		check(m.get_surface_count() == 1 and m.get_aabb().size.length() > 0.5, "%s has one non-empty surface" % pair[0])
	var st: AABB = TownKitScript.stairs().get_aabb()
	check(is_equal_approx(st.size.x, Balance.STAIR_RUN) and is_equal_approx(st.end.y, Balance.WALL_H) and is_equal_approx(st.size.z, Balance.STAIR_W), "stairs span run x wall height x stair width: %s" % st)
```
(`const MeshKitScript := preload("res://scripts/mesh_kit.gd")`, `const TownKitScript := preload("res://scripts/town_kit.gd")`.)

- [ ] **Step 6: 검증 + 캡처 + 커밋**

`--editor --quit` 후 네 가지 검증. `bash dev/build-web.sh` 후 캡처: 기본 줌 전경, 성문·계단 확대(휠 5단), 성 모서리 탑 확대. 확인: 성벽·톱니·문루·문짝·탑·계단이 각진 단색 면으로 보이고, 면이 빠지거나 뒤집힌 곳이 없다(있으면 `CLOCKWISE_FRONT`/면 방향 수정), 계단 윗단이 성벽 위와 이어진다. 커밋: `feat: procedural low-poly castle (walls, gatehouses, towers, stairs)`.

---

### Task 3: 로우폴리 건물 8종 · 자연물 · 산

**Files:** Modify `scripts/town_kit.gd`, `scripts/buildings.gd`, `scripts/art.gd`, `dev/fetch-assets.sh`, `tests/run_tests.gd`; Delete 남은 KayKit 헥스 에셋(+`.import`, `hexagons_medieval.png` 포함)

**Interfaces:**
- Produces `TownKit.building(id: String) -> ArrayMesh`(부지 중심 로컬, 바닥 y=0, 부지 크기 = size×TILE − BUILDING_GAP 안), `tree_pine(rng)`, `tree_round(rng)`, `bush(rng)`, `rock_cluster(rng)`, `mountain(rng)` → ArrayMesh

- [ ] **Step 1: 건물 레시피 (spec §4)**

`static func building(id: String) -> ArrayMesh`가 id별 레시피를 호출한다. 예시(성채):
```gdscript
static func _keep() -> ArrayMesh:
	var k = MeshKit.new()
	k.box(Vector3.ZERO, Vector3(5.6, 4.0, 5.6), STONE)                       # 본체
	k.box(Vector3(0, 4.0, 0), Vector3(5.9, 0.3, 5.9), STONE_DARK)           # 처마 띠
	for c in [Vector3(-2.6, 0, -2.6), Vector3(2.6, 0, -2.6), Vector3(2.6, 0, 2.6), Vector3(-2.6, 0, 2.6)]:
		k.prism_n(c, 6, 1.0, 1.0, 5.5, STONE)                               # 모서리 6각 탑
		k.cone(c + Vector3(0, 5.5, 0), 6, 1.25, 2.0, ROOF_BLUE)
	k.prism_n(Vector3(0, 4.0, 0), 8, 1.7, 1.7, 4.5, STONE)                  # 가운데 탑
	k.cone(Vector3(0, 8.5, 0), 8, 2.0, 3.0, ROOF_BLUE)
	k.box(Vector3(0, 11.5, 0), Vector3(0.12, 1.6, 0.12), WOOD)              # 깃대
	k.box(Vector3(0.45, 12.5, 0), Vector3(0.8, 0.5, 0.05), FLAG)
	k.box(Vector3(0, 0, 2.85), Vector3(1.4, 2.2, 0.15), WOOD)               # 문
	return k.commit()
```
나머지 7종을 spec §4 표대로 같은 방식으로 만든다(부지 6m 안: x·z 범위 ±2.7). 면 수는 적게(원기둥 5~8각), 색은 팔레트로. 건물마다 성격이 한눈에 보이는 실루엣 하나를 둔다(막사 = 긴 빨간 지붕 + 깃대, 주점 = 2층 흰 벽 + 주황 지붕 + 통, 연구소 = 8각 탑 + 보라 원뿔, 민가 = 작은 집 여러 채, 벌목장 = 헛간 + 통나무 더미, 채석장 = 바위 더미 + 석재 블록 + 기중기, 농장 = 헛간 + 밭고랑 + 작은 풍차).

- [ ] **Step 2: 자연물·산 레시피**

- `tree_pine(rng)`: 줄기(5각, WOOD) + 원뿔 3층(6~7각, LEAF/LEAF_DARK, 위로 갈수록 작게, 높이 5~7m).
- `tree_round(rng)`: 줄기 + `rock()`으로 만든 각진 둥근 수관(LEAF, squash 0.9, 반지름 1.6~2.2).
- `bush(rng)`: 작은 각진 덩어리 2~3개(LEAF_DARK).
- `rock_cluster(rng)`: 바위 2~4개(ROCK).
- `mountain(rng)`: 7~9각 원뿔을 흔든 산(반지름 14~20, 높이 16~26). 면 색은 높이로 정한다: 아래 1/3 LEAF_DARK, 가운데 ROCK, 꼭대기 SNOW. 면마다 한 색(면 중심 높이 기준). 꼭짓점을 반지름·높이 방향으로 흔들어 각지게. 필요하면 봉우리 2개를 붙인 변형.

- [ ] **Step 3: buildings.gd 교체**

- 건물: `TownKit.building(b.id)` → MeshInstance3D(재질 `Art.lowpoly_vc_material()`)를 부지 중심에. 이름표 높이 = 메시 AABB 위 + 1m.
- 자연물: 종류별 변형 몇 개(예: 침엽수 4, 활엽수 3, 덤불 2, 바위 3)를 시드 고정으로 만들고, 기존 배치 규칙(성벽 여유·진입로·간격·개수)으로 흩어 변형별 MultiMesh로 그린다(`_add_multimesh`를 경로 대신 메시를 받게 바꾸거나 `_add_mesh_multimesh(mesh, placements)` 추가; 재질은 MultiMeshInstance3D의 `material_override`).
- 산: 변형 4~5개, 기존 테두리 배치 규칙(띠·간격·임의 회전)으로 MultiMesh. 묻기(sink) 불필요 — 바닥이 평평하다.
- `art.gd`: `BUILDING_MODELS`, `NATURE_MODELS`, `BORDER_MODELS`, `NATURE_SCALE`, `BORDER_SCALE_*`, `BORDER_SINK`, `HEX_DIR` 등 KayKit 헥스 관련 삭제(배치 규칙 상수는 남긴다). `LOWPOLY_*`·캐릭터·무기·화살은 유지.
- `dev/fetch-assets.sh`에서 헥스 팩 받기 전부 삭제(라이선스 파일의 헥스 팩 블록도), 헥스 파일·`.import` 삭제.

- [ ] **Step 4: 테스트**

`test_art_assets`에서 헥스 관련 검사 삭제. 새 테스트:
```gdscript
func test_town_recipes() -> void:
	for b in Balance.BUILDINGS:
		var m: ArrayMesh = TownKitScript.building(b.id)
		var box := m.get_aabb()
		var plot := Vector2(b.size.x * Balance.TILE - Art.BUILDING_GAP, b.size.y * Balance.TILE - Art.BUILDING_GAP)
		check(box.size.x <= plot.x + 0.01 and box.size.z <= plot.y + 0.01, "%s fits its plot: %s vs %s" % [b.id, box.size, plot])
		check(absf(box.position.y) < 0.01 and box.size.y > 1.0, "%s stands on the ground" % b.id)
		check(absf(box.get_center().x) < 0.6 and absf(box.get_center().z) < 0.6, "%s centred on its plot" % b.id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for f in [TownKitScript.tree_pine, TownKitScript.tree_round, TownKitScript.bush, TownKitScript.rock_cluster, TownKitScript.mountain]:
		var m: ArrayMesh = f.call(rng)
		check(m.get_surface_count() == 1 and m.get_aabb().position.y > -0.3, "%s is one surface resting near the ground" % f.get_method())
```
(`Art`에 `BUILDING_GAP`이 남아 있어야 한다.) 기존 로우폴리 변환 테스트의 헥스 모델 참조 제거.

- [ ] **Step 5: 검증 + 캡처 + 커밋**

`--editor --quit` 후 네 가지 검증 + 패배 복귀. `bash dev/build-web.sh` 후 캡처:
- 기본 줌 전경
- 건물 근접(휠 5단 + 드래그로 성 안 여러 곳)
- 줌아웃(나무·산)
- `?auto-stage` 전투
- 궁수를 다른 면 성벽으로 보내 계단을 오르는 순간(성벽 탭 후 1~2초)
본 것만 적는다. 어색한 레시피(크기·색·실루엣)는 고친다.
- 커밋: `feat: procedural low-poly buildings, trees, rocks and mountains`
- 웹 pck 크기를 보고한다. 헥스 에셋이 빠져 줄어야 한다.

---

## 자체 검토

- **Spec 커버리지:**
  - §1 메시: T2 도구·셰이더·성, T3 건물·자연물·산·에셋 삭제
  - §2 계단: T1 로직·경로·테스트, T2 계단 메시·배치
  - §3 크기·배치·카메라: T1
  - §4 레시피: T3
  - §6 테스트: T1 경로, T2 도구·부품, T3 레시피, 각 태스크 검증·캡처
- **이름 일관성:**
  - `Formation.region/stair_*/wall_landing/route`: T1 정의 → T2 castle(계단 배치)
  - `MeshKit` API: T2 정의 → T3 레시피
  - `TownKit` 성 부품: T2, 건물·자연물·산: T3
  - `Art.lowpoly_vc_material`: T2 정의 → T2·T3 사용
- **알려진 한계:** 계단 오르기는 직선 경사라 발이 단에 딱 맞지 않을 수 있다(시각만). 캐릭터는 KayKit 유지.

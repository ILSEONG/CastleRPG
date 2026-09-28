# CastleRPG MVP 개정 2 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** MVP를 쿼터뷰·격자 타일·큰 성(건물 8종 자리)·성벽 위 전투로 바꾸고, 창을 띄우지 않는 웹 미리보기(헤드리스 캡처 + VSCode Simple Browser)로 확인한다.

**Architecture:** 기존 구조(씬 1개, 전부 코드 생성, `GameState` 오토로드가 상태의 진실) 유지. 자리 슬롯과 위치 계산은 순수 스크립트 `formation.gd`로 분리해 헤드리스 테스트한다. 바닥은 월드 좌표 격자 셰이더 1장. 화면 확인은 웹 익스포트를 로컬 서빙하고 Playwright 헤드리스 Chromium으로 캡처한다.

**Tech Stack:** Godot 4.7.2 (GDScript, Compatibility), Node 24 + Playwright + http-server (개발 도구만), Pretendard 폰트(OFL).

**Spec:** `docs/superpowers/specs/2026-09-28-castlerpg-mvp-rev2-design.md` (v1 spec보다 우선)

## Global Constraints

- Godot 실행 파일: `./tools/Godot_v4.7.2-stable_win64_console.exe` (Git Bash, 프로젝트 루트에서). export 템플릿은 설치돼 있다.
- **창 금지**: Godot는 항상 `--headless`로만 실행한다. 브라우저 창도 열지 않는다. 화면 확인은 `node dev/webshot.mjs`(헤드리스 Chromium)로만 한다
- `class_name` 금지. 스크립트 간 참조는 `const X := preload("res://...")`
- 다른 스크립트의 노드를 담는 변수는 타입 없이(`var castle`)
- 오토로드 enum을 `match` 패턴에 쓰지 않는다(`game_state.gd` 내부만 허용)
- 물리 바디 없음. `Area3D`는 탭 판정 전용: 성문 레이어 2, 영웅 4, 성벽 8
- 타깃 탐색 0.2초 주기. 몬스터 동시 상한 120. 사거리 판정은 전부 `Formation.flat_distance`(수평 거리)
- 화면 720×1280 세로, stretch `canvas_items`, aspect `expand`, 렌더러 `gl_compatibility`
- 테스트: `./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd` → 마지막 줄 `ALL PASSED`, 종료 코드 0. `-s` 스크립트는 오토로드를 못 쓴다 → `GameState`를 참조하는 스크립트는 테스트에서 preload 금지
- 스모크: `./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --fixed-fps 60 --quit-after 900 -- --auto-stage 2>&1 | grep -c "SCRIPT ERROR"` → `0`
- 새 `.gd`·에셋을 만들면 `./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --editor --quit`를 한 번 돌려 `*.uid`·`*.import`를 생성하고 함께 커밋한다
- 웹 빌드 `bash dev/build-web.sh` → 서빙 `npm --prefix dev run serve` (백그라운드, 포트 8060) → 캡처 `node dev/webshot.mjs --out <경로> ...`. 작업이 끝나면 8060 서버를 종료한다(PowerShell: `Stop-Process -Id (Get-NetTCPConnection -LocalPort 8060 -State Listen).OwningProcess -Force`)
- 캡처 PNG는 `.superpowers/sdd/2026-09-28-castlerpg-mvp-rev2/` 아래에 저장하고 Read 도구로 연다(git 무시 폴더)
- `python` 명령은 동작하지 않는 스텁이다. 쓰지 않는다
- 들여쓰기 탭, 줄끝 LF
- 커밋 메시지 끝: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## 파일 구조 (개정 후)

| 파일 | 책임 |
|---|---|
| `project.godot` | 설정, 오토로드, 기본 폰트 |
| `export_presets.cfg` | "Web" 익스포트 프리셋 |
| `assets/fonts/Pretendard-SemiBold.otf`, `OFL.txt` | 한글 폰트와 라이선스 |
| `shaders/ground_grid.gdshader` | 격자 타일 바닥 |
| `scripts/balance.gd` | 밸런스·기하 상수, 건물 배치, 역할 스탯 |
| `scripts/formation.gd` | 자리 슬롯 점유 + 위치 계산 (순수) |
| `scripts/flat.gd` | 단색 메시 헬퍼 + 팔레트 |
| `scripts/wave_director.gd` | 스폰 스케줄 (변경 없음) |
| `scripts/game_state.gd` | 오토로드 상태머신 (변경 없음) |
| `scripts/castle.gd` | 성벽·탑·성문 메시, 탭 영역, 위치 API |
| `scripts/buildings.gd` | 건물 플레이스홀더 + 이름표 |
| `scripts/camera_rig.gd` | 쿼터뷰 카메라, 드래그·줌 |
| `scripts/hero.gd` | 영웅 역할·자리·전투 |
| `scripts/monster.gd` | 몬스터 |
| `scripts/spawner.gd` | 스폰 (변경 없음) |
| `scripts/unit_picker.gd` | 탭 판정 → 선택/이동 명령 |
| `scripts/hud.gd` | HUD |
| `scripts/main.gd` | 월드 조립, 개발용 auto-stage |
| `dev/package.json`, `dev/build-web.sh`, `dev/webshot.mjs`, `dev/.gdignore` | 웹 빌드·서빙·헤드리스 캡처 |
| `tests/run_tests.gd` | 헤드리스 테스트 |

---

### Task 1: 웹 미리보기 파이프라인 + 한글 폰트

**Files:**
- Create: `assets/fonts/Pretendard-SemiBold.otf`, `assets/fonts/OFL.txt` (다운로드)
- Create: `export_presets.cfg`
- Create: `dev/.gdignore`, `dev/package.json`, `dev/build-web.sh`, `dev/webshot.mjs`
- Modify: `project.godot` (기본 폰트)
- Modify: `.gitignore`
- Modify: `scripts/main.gd` (전체 교체: `--shot` 삭제, 웹 `?auto-stage` 지원, 로그 연결을 시작 전에)

**Interfaces:**
- Produces: `bash dev/build-web.sh` → `export/web/index.html`. `npm --prefix dev run serve` → `http://localhost:8060`. `node dev/webshot.mjs --out P [--url U] [--wait MS] [--size WxH] [--click x,y[,ms]]...` → PNG (deviceScaleFactor 2), 콘솔 로그 stdout. 클릭 좌표는 CSS 픽셀(기본 뷰포트 360×640). Task 4가 `--drag`, `--wheel`을 추가한다
- Produces: `main.gd`의 `_auto_stage_requested()` — 네이티브 `-- --auto-stage` 또는 웹 URL에 `auto-stage` 포함 시 true

- [ ] **Step 1: 폰트 다운로드**

```bash
mkdir -p assets/fonts
curl -sL -o assets/fonts/Pretendard-SemiBold.otf https://cdn.jsdelivr.net/npm/pretendard@1.3.9/dist/public/static/Pretendard-SemiBold.otf
curl -sL -o assets/fonts/OFL.txt https://cdn.jsdelivr.net/npm/pretendard@1.3.9/dist/LICENSE.txt
ls -la assets/fonts; head -c 4 assets/fonts/Pretendard-SemiBold.otf; echo; head -3 assets/fonts/OFL.txt
```
Expected: otf 약 1.5MB, 첫 4바이트 `OTTO`, OFL.txt 첫 줄에 Copyright 문구.

- [ ] **Step 2: project.godot에 기본 폰트 추가**

`[display]` 섹션과 `[rendering]` 섹션 사이에 추가:
```ini
[gui]

theme/custom_font="res://assets/fonts/Pretendard-SemiBold.otf"

```

- [ ] **Step 3: export_presets.cfg 작성 (프로젝트 루트)**

```ini
[preset.0]

name="Web"
platform="Web"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="export/web/index.html"

[preset.0.options]

variant/thread_support=false
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
progressive_web_app/enabled=false
```

- [ ] **Step 4: dev 도구 작성**

`dev/.gdignore` — 빈 파일 (Godot가 `dev/node_modules`를 스캔·임포트하지 않게).

`dev/package.json`:
```json
{
  "name": "castlerpg-dev",
  "private": true,
  "type": "module",
  "scripts": {
    "serve": "http-server ../export/web -p 8060 -c-1 -s"
  },
  "devDependencies": {
    "http-server": "^14.1.1",
    "playwright": "^1.63.0"
  }
}
```

`dev/build-web.sh`:
```bash
#!/usr/bin/env bash
# 웹 빌드 → export/web/index.html. 창을 띄우지 않는다(--headless).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=./tools/Godot_v4.7.2-stable_win64_console.exe
mkdir -p export/web
touch export/.gdignore   # 빌드 산출물을 Godot가 리소스로 임포트하지 않게
"$GODOT" --headless --quiet --path . --import
"$GODOT" --headless --quiet --path . --export-debug "Web" export/web/index.html
ls -la export/web/index.html export/web/index.pck
```

`dev/webshot.mjs`:
```js
// 헤드리스 Chromium으로 웹 빌드를 열어 스크린샷을 저장한다. 창을 띄우지 않는다.
// 사용: node dev/webshot.mjs --out shot.png [--url http://localhost:8060/] [--wait 5000] [--size 360x640]
//                            [--click x,y[,ms]]...
// 좌표는 CSS 픽셀(뷰포트 기준). 동작은 인자 순서대로 실행하고, 각 동작 뒤 ms(기본 500) 대기.
// 페이지 콘솔 로그와 에러를 stdout에 출력한다.
import { chromium } from 'playwright';

const args = process.argv.slice(2);
const opt = { url: 'http://localhost:8060/', out: 'shot.png', wait: 5000, size: '360x640', actions: [] };
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  const v = args[i + 1];
  if (a === '--url') { opt.url = v; i++; }
  else if (a === '--out') { opt.out = v; i++; }
  else if (a === '--wait') { opt.wait = Number(v); i++; }
  else if (a === '--size') { opt.size = v; i++; }
  else if (a === '--click') { opt.actions.push({ type: 'click', nums: v.split(',').map(Number) }); i++; }
  else { console.error(`unknown arg: ${a}`); process.exit(2); }
}

const [width, height] = opt.size.split('x').map(Number);
const browser = await chromium.launch({
  headless: true,
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
});
const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 2 });
const logs = [];
page.on('console', (m) => logs.push(`[${m.type()}] ${m.text()}`));
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));
await page.goto(opt.url);
await page.waitForTimeout(opt.wait);
for (const act of opt.actions) {
  if (act.type === 'click') {
    const [x, y, ms = 500] = act.nums;
    await page.mouse.click(x, y);
    await page.waitForTimeout(ms);
  }
}
await page.screenshot({ path: opt.out });
console.log(logs.join('\n'));
await browser.close();
```

`.gitignore`에 한 줄 추가:
```
dev/node_modules/
```

- [ ] **Step 5: 의존성 설치**

```bash
npm --prefix dev install
(cd dev && npx playwright install chromium-headless-shell)
```
Expected: 오류 없음. 브라우저는 사용자 프로필의 ms-playwright 캐시에 설치된다(창 없음).

- [ ] **Step 6: scripts/main.gd 전체 교체**

```gdscript
extends Node3D
## 월드 조립. 씬 파일은 이것 하나. 나머지는 코드로 생성.
## 개발용 auto-stage: 네이티브는 유저 인자 `-- --auto-stage`, 웹은 URL에 `?auto-stage` → 시작 즉시 스테이지 진행.

const Balance := preload("res://scripts/balance.gd")
const Flat := preload("res://scripts/flat.gd")
const CastleScript := preload("res://scripts/castle.gd")
const HeroScript := preload("res://scripts/hero.gd")
const PickerScript := preload("res://scripts/unit_picker.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")
const HudScript := preload("res://scripts/hud.gd")

var camera: Camera3D
var castle
var heroes: Array = []


func _ready() -> void:
	_build_world()
	castle = CastleScript.new()
	add_child(castle)
	for i in GameState.hero_count():
		var hero = HeroScript.new()
		hero.castle = castle
		hero.index = i
		hero.assigned_side = i % 4
		add_child(hero)
		heroes.append(hero)
	var picker = PickerScript.new()
	picker.camera = camera
	add_child(picker)
	var spawner = SpawnerScript.new()
	spawner.castle = castle
	add_child(spawner)
	add_child(HudScript.new())
	_connect_dev_log()
	if _auto_stage_requested():
		GameState.start_stage()


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.88, 0.90, 0.94)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = false
	add_child(sun)
	sun.rotation_degrees = Vector3(-55, 35, 0)

	var ground := PlaneMesh.new()
	ground.size = Vector2(60, 60)
	add_child(Flat.mesh(ground, Flat.GROUND))

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = 26.0
	add_child(camera)
	camera.position = Vector3(0, 24, 24)
	camera.look_at(Vector3.ZERO)


func _connect_dev_log() -> void:
	GameState.mode_changed.connect(func(m): print("[mode] %d stage=%d" % [m, GameState.stage]))
	GameState.stage_cleared.connect(func(s): print("[cleared] %d" % s))
	GameState.stage_failed.connect(func(s): print("[failed] %d" % s))


func _auto_stage_requested() -> bool:
	if OS.get_cmdline_user_args().has("--auto-stage"):
		return true
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("window.location.search")).contains("auto-stage")
	return false
```

- [ ] **Step 7: 임포트 + 테스트 + 스모크**

```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --editor --quit 2>&1 | grep -E "ERROR" ; ls assets/fonts
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd; echo "exit=$?"
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --fixed-fps 60 --quit-after 900 -- --auto-stage 2>&1 | grep -E "SCRIPT ERROR|^\[mode\]"
```
Expected: `assets/fonts/Pretendard-SemiBold.otf.import` 생성. `ALL PASSED`, `exit=0`. 스모크 출력에 `[mode] 1 stage=1`이 있고(로그 연결이 시작보다 먼저라 첫 줄이 찍힌다) `SCRIPT ERROR` 없음.

- [ ] **Step 8: 웹 빌드 + 서빙 + 헤드리스 캡처**

```bash
bash dev/build-web.sh
```
Expected: `export/web/index.html`, `index.pck` 존재.

서버는 Bash 도구의 `run_in_background`로 띄운다: `npm --prefix dev run serve`

```bash
W=.superpowers/sdd/2026-09-28-castlerpg-mvp-rev2
node dev/webshot.mjs --out $W/t1-idle.png --wait 5000
node dev/webshot.mjs --url "http://localhost:8060/?auto-stage" --out $W/t1-stage.png --wait 8000
```
Read 두 PNG. Expected: `t1-idle.png` — 상단 "스테이지 1"이 한글로 정상 표시(네모 아님), 하단 버튼 "스테이지 진행". `t1-stage.png` — 버튼 "이번 스테이지 후 중지", 몬스터가 접근 중. 콘솔 로그에 `[pageerror]` 없음.

서버 종료: `Stop-Process -Id (Get-NetTCPConnection -LocalPort 8060 -State Listen).OwningProcess -Force` (PowerShell)

- [ ] **Step 9: 커밋**

```bash
git add assets export_presets.cfg dev/.gdignore dev/package.json dev/package-lock.json dev/build-web.sh dev/webshot.mjs .gitignore project.godot scripts/main.gd
git status --short   # dev/node_modules, export/ 가 목록에 없어야 한다
git commit -m "feat: headless web preview pipeline and bundled Korean font

Web export preset, build/serve/screenshot tools under dev/, Pretendard
as the default theme font so Korean renders on web and mobile. The
windowed --shot flag is gone; auto-stage also works via ?auto-stage.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 기하·배치 데이터 + Formation (순수 로직, 테스트)

**Files:**
- Modify: `scripts/balance.gd` (상수·함수 추가만. 기존 것은 Task 3에서 정리)
- Create: `scripts/formation.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Produces `Balance` 추가: `TILE`, `INTERIOR_TILES`, `WALL_T`, `WALL_H`, `GATE_W`, `TOWER_SIZE`, `TOWER_H`, `MAP_HALF`, `SPAWN_MARGIN`, `SPAWN_SPREAD`, `GATE_FRONT_OFFSET`, `GATE_FRONT_SLOTS`, `WALL_TOP_SLOTS`, `CAMERA_SIZE_DEFAULT`, `CAMERA_SIZE_MIN`, `CAMERA_SIZE_MAX`, `HERO_ROLES`, `HERO_ROSTER`, `BUILDINGS`; `interior_half(keep_level: int) -> float`, `hero_role(index: int) -> String`, `building(id: String) -> Dictionary`
- Produces `formation.gd` (RefCounted): 상수 `POST_GATE := 0`, `POST_WALL := 1`, `SIDE_DIR: Array[Vector3]`; 인스턴스 `claim(hero_id: int, side: int, post: int) -> int`(가득 차면 -1), `release(hero_id: int)`, `assignment(hero_id: int) -> Dictionary`(`{side, post, slot}` 또는 빈 딕셔너리); static `capacity(post) -> int`, `perp(side) -> Vector3`, `gate_position(half, side)`, `gate_target(half, side)`, `slot_position(half, side, post, slot)`, `keep_target(side)`, `spawn_center(half, side)`, `flat_distance(a, b) -> float`

- [ ] **Step 1: 실패하는 테스트 추가 — tests/run_tests.gd**

상단 상수에 추가:
```gdscript
const FormationScript := preload("res://scripts/formation.gd")
```

`_init()` 호출 목록의 `test_gamestate_hero_count()` 다음에 추가:
```gdscript
	test_layout_tables()
	test_building_layout()
	test_formation_claims()
	test_formation_positions()
```

파일 끝에 추가:
```gdscript
func test_layout_tables() -> void:
	check(Balance.interior_half(1) == 16.0, "interior half is 16m at keep level 1")
	check(Balance.interior_half(2) > Balance.interior_half(1), "interior grows at keep level 2")
	check(Balance.interior_half(3) > Balance.interior_half(2), "interior grows at keep level 3")
	check(Balance.interior_half(99) == Balance.interior_half(3), "interior clamps beyond table")
	check(Balance.hero_role(0) == "warrior" and Balance.hero_role(1) == "archer", "roster starts warrior, archer")
	check(Balance.hero_role(2) == "warrior" and Balance.hero_role(3) == "archer", "roster alternates")
	for role in Balance.HERO_ROLES:
		for key in ["name", "hp", "atk", "range", "atk_interval", "speed", "color"]:
			check(Balance.HERO_ROLES[role].has(key), "role %s has %s" % [role, key])
	check(Balance.HERO_ROLES.archer.range > Balance.HERO_ROLES.warrior.range, "archer outranges warrior")


func test_building_layout() -> void:
	var half_tiles := floori(Balance.INTERIOR_TILES[0] / 2.0)
	var allowed := Rect2i(-half_tiles + 1, -half_tiles + 1, 2 * half_tiles - 2, 2 * half_tiles - 2)
	var road_ns := Rect2i(-1, -half_tiles, 2, 2 * half_tiles)
	var road_ew := Rect2i(-half_tiles, -1, 2 * half_tiles, 2)
	var placed: Array = []
	var ids := {}
	for b in Balance.BUILDINGS:
		var r := Rect2i(b.cell, b.size)
		check(allowed.encloses(r), "%s inside level-1 interior with 1-tile wall margin" % b.id)
		if b.id != "keep":
			check(not r.intersects(road_ns) and not r.intersects(road_ew), "%s stays off the cross roads" % b.id)
		for other in placed:
			check(not r.intersects(other), "%s overlaps no other building" % b.id)
		placed.append(r)
		ids[b.id] = true
	for id in ["keep", "barracks", "tavern", "lab", "houses", "lumber", "quarry", "farm"]:
		check(ids.has(id), "building %s present" % id)
	var keep := Balance.building("keep")
	check(Rect2i(keep.cell, keep.size).get_center() == Vector2i(0, 0), "keep centered on the crossroads")
	check(Balance.building("nope").is_empty(), "unknown building id gives empty dict")


func test_formation_claims() -> void:
	var f = FormationScript.new()
	var gate: int = FormationScript.POST_GATE
	var wall: int = FormationScript.POST_WALL
	check(f.claim(0, 0, gate) == 0, "first gate claim gets slot 0")
	check(f.claim(1, 0, gate) == 1, "second gate claim gets slot 1")
	check(f.claim(2, 0, gate) == 2, "third gate claim gets slot 2")
	check(f.claim(3, 0, gate) == -1, "gate post full at capacity 3")
	check(f.assignment(3).is_empty(), "failed claim leaves hero unassigned")
	check(f.claim(1, 0, gate) == 1, "re-claiming own post keeps the slot")
	check(f.claim(1, 0, wall) == 0, "moving to the wall claims wall slot 0")
	check(f.claim(3, 0, gate) == 1, "slot freed by the move is reusable")
	f.release(0)
	check(f.claim(4, 0, gate) == 0, "released slot is reusable")
	check(f.claim(5, 2, gate) == 0, "other side is independent")
	var a: Dictionary = f.assignment(1)
	check(a.side == 0 and a.post == wall and a.slot == 0, "assignment reports side, post and slot")
	check(FormationScript.capacity(gate) == Balance.GATE_FRONT_SLOTS.size(), "gate capacity from balance")
	check(FormationScript.capacity(wall) == Balance.WALL_TOP_SLOTS.size(), "wall capacity from balance")


func test_formation_positions() -> void:
	var half := Balance.interior_half(1)
	var outer := half + Balance.WALL_T
	var seen := {}
	for side in 4:
		var dir: Vector3 = FormationScript.SIDE_DIR[side]
		check(dir.dot(FormationScript.gate_position(half, side)) == half + Balance.WALL_T / 2.0, "gate on wall centerline, side %d" % side)
		check(dir.dot(FormationScript.gate_target(half, side)) > outer, "gate target outside the wall face, side %d" % side)
		check(dir.dot(FormationScript.spawn_center(half, side)) > outer + 10.0, "spawn far outside, side %d" % side)
		for slot in FormationScript.capacity(FormationScript.POST_GATE):
			var p: Vector3 = FormationScript.slot_position(half, side, FormationScript.POST_GATE, slot)
			check(p.y == 0.0 and dir.dot(p) > outer, "gate slot on the ground outside the wall (side %d slot %d)" % [side, slot])
			seen[p] = true
		for slot in FormationScript.capacity(FormationScript.POST_WALL):
			var p: Vector3 = FormationScript.slot_position(half, side, FormationScript.POST_WALL, slot)
			check(p.y == Balance.WALL_H, "wall slot on the wall top (side %d slot %d)" % [side, slot])
			check(absf(dir.dot(p) - (half + Balance.WALL_T / 2.0)) < 0.001, "wall slot on the wall centerline")
			check(absf(FormationScript.perp(side).dot(p)) > Balance.GATE_W / 2.0, "wall slot beside the gate, not above it")
			seen[p] = true
	check(seen.size() == 4 * (Balance.GATE_FRONT_SLOTS.size() + Balance.WALL_TOP_SLOTS.size()), "all slot positions distinct")
	var keep := Balance.building("keep")
	var keep_half: float = keep.size.x * Balance.TILE / 2.0
	for side in 4:
		var k: Vector3 = FormationScript.keep_target(side)
		check(FormationScript.SIDE_DIR[side].dot(k) > keep_half, "keep target outside the keep footprint, side %d" % side)
	check(is_equal_approx(FormationScript.flat_distance(Vector3(0, 3, 0), Vector3(3, 0, 4)), 5.0), "flat distance ignores height")
```

- [ ] **Step 2: 테스트 실행 → 실패 확인**

Run: `./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd; echo "exit=$?"`
Expected: `formation.gd` 없음 또는 `Balance.interior_half` 없음 파스 오류, `exit` 0 아님. 실제 출력을 보고서에 붙인다.

- [ ] **Step 3: scripts/balance.gd에 추가 (기존 내용 아래, `const MONSTER` 블록 다음)**

```gdscript
# --- 맵·성 기하 (개정 2) ---
const TILE := 2.0                     # 격자 타일 한 칸 (미터)
const INTERIOR_TILES := [16, 20, 24]  # 성 내부 한 변 타일 수. index = keep_level - 1
const WALL_T := 2.0                   # 성벽 두께 (1타일)
const WALL_H := 3.0                   # 성벽 높이 = 성벽 위 발판 높이
const GATE_W := 4.0                   # 성문 폭 (2타일)
const TOWER_SIZE := 3.0               # 모서리 탑 한 변
const TOWER_H := 4.5
const MAP_HALF := 70.0                # 바닥 절반 크기
const SPAWN_MARGIN := 22.0            # 성벽 바깥면에서 스폰 지점까지
const SPAWN_SPREAD := 6.0             # 스폰 지점 좌우 흩어짐 (±)
const GATE_FRONT_OFFSET := 1.5        # 성벽 바깥면에서 성문 앞 자리까지
const GATE_FRONT_SLOTS := [0.0, -1.6, 1.6]      # 성문 앞 자리 좌우 오프셋
const WALL_TOP_SLOTS := [-4.0, 4.0, -8.0, 8.0]  # 성벽 위 자리 좌우 오프셋 (성문 위는 비움)
const CAMERA_SIZE_DEFAULT := 44.0     # 직교 카메라 가로 폭(미터)
const CAMERA_SIZE_MIN := 16.0
const CAMERA_SIZE_MAX := 90.0

const HERO_ROLES := {
	"warrior": {
		"name": "전사", "hp": 400.0, "atk": 30.0, "range": 1.8, "atk_interval": 0.8, "speed": 6.0,
		"color": Color(0.25, 0.55, 0.95),
	},
	"archer": {
		"name": "궁수", "hp": 220.0, "atk": 20.0, "range": 9.0, "atk_interval": 1.0, "speed": 6.0,
		"color": Color(0.30, 0.72, 0.45),
	},
}
const HERO_ROSTER := ["warrior", "archer"]  # 영웅 i의 역할 = HERO_ROSTER[i % 2]

## 건물 배치 (플레이스홀더). cell = 최소 모서리 타일 좌표, size = 타일 수. 성 중심이 타일 경계 (0,0).
## 레벨 1 내부 타일 범위 -8..7. 성채 외 건물은 벽 쪽 1칸 여유(-7..6)를 두고 십자 도로(-1·0)를 피한다.
const BUILDINGS := [
	{"id": "keep", "name": "성채", "cell": Vector2i(-2, -2), "size": Vector2i(4, 4), "height": 6.0, "color": Color(0.62, 0.64, 0.72)},
	{"id": "barracks", "name": "막사", "cell": Vector2i(1, -7), "size": Vector2i(3, 3), "height": 2.4, "color": Color(0.72, 0.48, 0.42)},
	{"id": "tavern", "name": "주점", "cell": Vector2i(4, -4), "size": Vector2i(3, 3), "height": 2.4, "color": Color(0.80, 0.62, 0.38)},
	{"id": "lab", "name": "연구소", "cell": Vector2i(-4, -7), "size": Vector2i(3, 3), "height": 2.8, "color": Color(0.52, 0.56, 0.80)},
	{"id": "houses", "name": "민가", "cell": Vector2i(-7, -4), "size": Vector2i(3, 3), "height": 2.0, "color": Color(0.86, 0.74, 0.58)},
	{"id": "lumber", "name": "벌목장", "cell": Vector2i(1, 4), "size": Vector2i(3, 3), "height": 1.8, "color": Color(0.55, 0.42, 0.28)},
	{"id": "quarry", "name": "채석장", "cell": Vector2i(4, 1), "size": Vector2i(3, 3), "height": 1.6, "color": Color(0.60, 0.60, 0.60)},
	{"id": "farm", "name": "농장", "cell": Vector2i(-4, 4), "size": Vector2i(3, 3), "height": 1.0, "color": Color(0.78, 0.74, 0.40)},
]
```

파일 끝(기존 static 함수들 다음)에 추가:
```gdscript
static func interior_half(keep_level: int) -> float:
	return INTERIOR_TILES[clampi(keep_level, 1, INTERIOR_TILES.size()) - 1] * TILE / 2.0


static func hero_role(index: int) -> String:
	return HERO_ROSTER[index % HERO_ROSTER.size()]


static func building(id: String) -> Dictionary:
	for b in BUILDINGS:
		if b.id == id:
			return b
	return {}
```

- [ ] **Step 4: scripts/formation.gd 작성**

```gdscript
extends RefCounted
## 영웅 배치: 면(side)마다 성문 앞(POST_GATE)·성벽 위(POST_WALL) 슬롯 점유와 위치 계산.
## 씬·오토로드 의존 없음. 위치 함수는 static이고 성 내부 절반 크기(half)를 인자로 받는다.
## side: 0=N(-z) 1=E(+x) 2=S(+z) 3=W(-x)

const Balance := preload("res://scripts/balance.gd")

const POST_GATE := 0
const POST_WALL := 1
const SIDE_DIR: Array[Vector3] = [
	Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0),
]

var _claims := {}  # hero_id -> {"side": int, "post": int, "slot": int}


## 빈 슬롯 중 가장 앞 번호를 차지하고 돌려준다. 가득 차면 -1 (기존 배정 유지).
## 이미 같은 자리면 그 슬롯 그대로. 다른 자리로 옮기면 이전 슬롯은 자동으로 풀린다.
func claim(hero_id: int, side: int, post: int) -> int:
	var current: Dictionary = _claims.get(hero_id, {})
	if not current.is_empty() and current.side == side and current.post == post:
		return current.slot
	var taken := {}
	for id in _claims:
		var c: Dictionary = _claims[id]
		if c.side == side and c.post == post:
			taken[c.slot] = true
	for slot in capacity(post):
		if not taken.has(slot):
			_claims[hero_id] = {"side": side, "post": post, "slot": slot}
			return slot
	return -1


func release(hero_id: int) -> void:
	_claims.erase(hero_id)


func assignment(hero_id: int) -> Dictionary:
	return _claims.get(hero_id, {})


static func capacity(post: int) -> int:
	return Balance.GATE_FRONT_SLOTS.size() if post == POST_GATE else Balance.WALL_TOP_SLOTS.size()


static func perp(side: int) -> Vector3:
	var dir := SIDE_DIR[side]
	return Vector3(-dir.z, 0, dir.x)


## 성벽 중심선 위의 성문 중앙 (지면).
static func gate_position(half: float, side: int) -> Vector3:
	return SIDE_DIR[side] * (half + Balance.WALL_T / 2.0)


## 괴물이 성문을 치려고 서는 지점 (성벽 바깥면 바로 앞).
static func gate_target(half: float, side: int) -> Vector3:
	return SIDE_DIR[side] * (half + Balance.WALL_T + 0.8)


static func slot_position(half: float, side: int, post: int, slot: int) -> Vector3:
	var dir := SIDE_DIR[side]
	if post == POST_GATE:
		return dir * (half + Balance.WALL_T + Balance.GATE_FRONT_OFFSET) \
			+ perp(side) * float(Balance.GATE_FRONT_SLOTS[slot])
	return dir * (half + Balance.WALL_T / 2.0) + perp(side) * float(Balance.WALL_TOP_SLOTS[slot]) \
		+ Vector3(0, Balance.WALL_H, 0)


## 성문이 부서진 뒤 괴물이 성채를 치려고 서는 지점 (성채 외벽 바로 앞).
static func keep_target(side: int) -> Vector3:
	var keep: Dictionary = Balance.building("keep")
	var keep_half: float = keep.size.x * Balance.TILE / 2.0
	return SIDE_DIR[side] * (keep_half + 0.8)


static func spawn_center(half: float, side: int) -> Vector3:
	return SIDE_DIR[side] * (half + Balance.WALL_T + Balance.SPAWN_MARGIN)


## 높이를 무시한 수평 거리. 사거리 판정은 전부 이것으로 한다.
static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
```

- [ ] **Step 5: uid 생성 + 테스트 통과 확인**

```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --editor --quit 2>&1 | grep -E "ERROR"; ls scripts/formation.gd.uid
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd; echo "exit=$?"
```
Expected: uid 파일 존재, `ALL PASSED`, `exit=0`.

- [ ] **Step 6: 스모크 (게임이 여전히 도는지 — 이 태스크는 추가만 했으므로 변화 없어야 함)**

Run: 스모크 명령 (Global Constraints). Expected: `0`

- [ ] **Step 7: 커밋**

```bash
git add scripts/balance.gd scripts/formation.gd scripts/formation.gd.uid tests/run_tests.gd
git commit -m "feat: map geometry, building layout, hero roles and formation slots

Pure data and logic for revision 2, covered by headless tests: interior
size per keep level, eight-building layout rules, warrior/archer roles,
gate-front and wall-top slot claiming, and all position math.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 새 전장 — 격자 바닥, 큰 성, 건물, 쿼터뷰, 역할·성벽 전투

**Files:**
- Create: `shaders/ground_grid.gdshader`
- Create: `scripts/buildings.gd`
- Create: `scripts/camera_rig.gd` (시점만. 입력은 Task 4)
- Modify (전체 교체): `scripts/castle.gd`, `scripts/hero.gd`, `scripts/monster.gd`, `scripts/unit_picker.gd`, `scripts/main.gd`, `scripts/flat.gd`
- Modify: `scripts/balance.gd` (구 상수 삭제)

**Interfaces:**
- Consumes (Task 2): `Balance` 기하·역할·건물 상수와 함수, `formation.gd`의 `POST_GATE/POST_WALL/SIDE_DIR`, `claim`, static 위치 함수, `flat_distance`
- Consumes (기존): `GameState.keep_level`, `gate_hp_changed`, `refilled`, `is_gate_broken`, `damage_gate`, `damage_castle`, `hero_count()`; spawner는 `castle.spawn_position(side)`만 쓴다 (monster가 호출)
- Produces `castle.gd`: `var half: float`(`_ready`에서 설정), `gate_target(side)`, `keep_target(side)`, `slot_position(side, post, slot)`, `spawn_position(side)`. 성문 탭 영역 레이어 2, 성벽 탭 영역 레이어 8, 둘 다 메타 `"side"`
- Produces `hero.gd`: `setup(index, castle, formation)`(add_child 전), `move_to(side, post) -> bool`, `is_on_wall() -> bool`, `is_alive()`, `take_damage(amount)`, `selected`, `role`, `side`, `post`, `slot`. 영웅 탭 영역 레이어 4, 메타 `"hero"`
- Produces `monster.gd`: 기존 API 유지 (`setup`, `died`, `is_alive`, `take_damage`)
- Produces `camera_rig.gd`(Node3D): `var camera: Camera3D`(`_ready`에서 생성). 리그 위치 = 화면 중앙이 보는 바닥 지점
- Produces `unit_picker.gd`: 뗄 때 12px 이내면 탭. 영웅 → 선택, 성문 → `move_to(side, POST_GATE)`, 성벽 → `move_to(side, POST_WALL)`. 입력을 소비하지 않는다

- [ ] **Step 1: shaders/ground_grid.gdshader 작성**

```glsl
shader_type spatial;
render_mode unshaded;

// 월드 좌표 기준 격자 타일 바닥. 성 안은 포장 타일 + 십자 도로, 성 밖은 잔디 체커.
uniform float tile_size = 2.0;
uniform float interior_half = 16.0;
uniform float road_half = 2.0;
uniform vec4 grass_a : source_color = vec4(0.73, 0.84, 0.60, 1.0);
uniform vec4 grass_b : source_color = vec4(0.69, 0.80, 0.56, 1.0);
uniform vec4 paved_a : source_color = vec4(0.88, 0.85, 0.78, 1.0);
uniform vec4 paved_b : source_color = vec4(0.84, 0.81, 0.74, 1.0);
uniform vec4 road : source_color = vec4(0.78, 0.72, 0.62, 1.0);
uniform vec4 line_color : source_color = vec4(0.0, 0.0, 0.0, 0.12);
uniform float line_width = 0.03;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz / tile_size;
	float checker = mod(floor(p.x) + floor(p.y), 2.0);
	vec2 a = abs(world_pos.xz);
	vec3 base;
	if (max(a.x, a.y) < interior_half) {
		base = (min(a.x, a.y) < road_half) ? road.rgb : mix(paved_a.rgb, paved_b.rgb, checker);
	} else {
		base = mix(grass_a.rgb, grass_b.rgb, checker);
	}
	vec2 to_line = 0.5 - abs(fract(p) - 0.5);  // 격자선에서 0
	vec2 aa = fwidth(p);
	vec2 on_line = 1.0 - smoothstep(vec2(line_width), vec2(line_width) + aa, to_line);
	float line = max(on_line.x, on_line.y);
	ALBEDO = mix(base, line_color.rgb, line * line_color.a);
}
```

- [ ] **Step 2: scripts/flat.gd 전체 교체 (쓰지 않는 색 삭제, 탑·화살 색 추가)**

```gdscript
extends RefCounted
## 단색 플랫 메시 헬퍼와 팔레트. 모든 플레이스홀더 지오메트리는 여기로.

const WALL := Color(0.86, 0.84, 0.78)
const TOWER := Color(0.78, 0.76, 0.70)
const GATE := Color(0.55, 0.38, 0.22)
const HERO_SELECTED := Color(1.0, 0.9, 0.2)
const ARROW := Color(0.30, 0.22, 0.14)


static func mesh(m: Mesh, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mi.mesh = m
	mi.material_override = mat
	return mi


## 바닥이 y=0에 닿는 박스.
static func box(size: Vector3, color: Color) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := mesh(bm, color)
	mi.position.y = size.y / 2.0
	return mi


## 바닥이 y=0에 닿는 캡슐. height는 전체 높이.
static func capsule(radius: float, height: float, color: Color) -> MeshInstance3D:
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = height
	var mi := mesh(cm, color)
	mi.position.y = height / 2.0
	return mi
```

- [ ] **Step 3: scripts/castle.gd 전체 교체**

```gdscript
extends Node3D
## 성벽 4면(두께·높이 있는 벽) + 모서리 탑 + 성문 4개. 성문 HP의 진실은 GameState.
## 여기는 시각화·탭 판정 영역·위치 제공만. 크기는 GameState.keep_level의 내부 크기,
## 위치 계산은 Formation static 함수에 위임한다.
## side: 0=N(-z) 1=E(+x) 2=S(+z) 3=W(-x)

const Balance := preload("res://scripts/balance.gd")
const Flat := preload("res://scripts/flat.gd")
const Formation := preload("res://scripts/formation.gd")

const LAYER_GATE := 2
const LAYER_WALL := 8
const TAP_MARGIN := Vector3(1, 1, 1)  # 탭 판정 박스 여유

var half: float = 0.0
var _gate_meshes: Array = []


func _ready() -> void:
	half = Balance.interior_half(GameState.keep_level)
	var seg_len := half + Balance.WALL_T - Balance.GATE_W / 2.0  # 성문 옆 벽 한 토막 (모서리 바깥까지)
	for side in 4:
		var dir: Vector3 = Formation.SIDE_DIR[side]
		var perp := Formation.perp(side)
		var center := dir * (half + Balance.WALL_T / 2.0)
		for s in [-1.0, 1.0]:
			var seg_center: Vector3 = center + perp * s * (Balance.GATE_W + seg_len) / 2.0
			var seg_size := _along(perp, seg_len, Balance.WALL_H, Balance.WALL_T)
			var seg := Flat.box(seg_size, Flat.WALL)
			seg.position += seg_center
			add_child(seg)
			_add_tap_area(seg_center, seg_size, LAYER_WALL, side)
		var door := Flat.box(_along(perp, Balance.GATE_W, Balance.WALL_H, Balance.WALL_T * 0.6), Flat.GATE)
		door.position += center
		add_child(door)
		_gate_meshes.append(door)
		_add_tap_area(center, _along(perp, Balance.GATE_W, Balance.WALL_H, Balance.WALL_T), LAYER_GATE, side)
	var c := half + Balance.WALL_T / 2.0
	for corner in [Vector3(c, 0, c), Vector3(-c, 0, c), Vector3(c, 0, -c), Vector3(-c, 0, -c)]:
		var tower := Flat.box(Vector3(Balance.TOWER_SIZE, Balance.TOWER_H, Balance.TOWER_SIZE), Flat.TOWER)
		tower.position += corner
		add_child(tower)
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


func _on_gate_hp_changed(side: int, hp: float, hp_max: float) -> void:
	var mi: MeshInstance3D = _gate_meshes[side]
	mi.visible = hp > 0.0
	var mat := mi.material_override as StandardMaterial3D
	mat.albedo_color = Flat.GATE.darkened(0.6 * (1.0 - hp / hp_max))
```

- [ ] **Step 4: scripts/buildings.gd 작성**

```gdscript
extends Node3D
## 성 안 건물 플레이스홀더 (Balance.BUILDINGS). 기능 없음 — 크기·배치 확인용.
## 건물 기능(자원·업그레이드)은 서브프로젝트 2.

const Balance := preload("res://scripts/balance.gd")
const Flat := preload("res://scripts/flat.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const GAP := 0.4  # 타일 경계와 건물 벽 사이 여유 (격자선이 보이게)


func _ready() -> void:
	for b in Balance.BUILDINGS:
		var size := Vector3(b.size.x * Balance.TILE - GAP, b.height, b.size.y * Balance.TILE - GAP)
		var center := Vector3((b.cell.x + b.size.x / 2.0) * Balance.TILE, 0, (b.cell.y + b.size.y / 2.0) * Balance.TILE)
		var box := Flat.box(size, b.color)
		box.position += center
		add_child(box)
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
		label.position = center + Vector3(0, b.height + 1.2, 0)
		add_child(label)
```

- [ ] **Step 5: scripts/camera_rig.gd 작성 (시점만)**

```gdscript
extends Node3D
## 쿼터뷰 직교 카메라 리그. 리그 위치 = 화면 중앙이 바라보는 바닥 지점.
## 드래그 이동·줌 입력은 Task 4에서 추가.

const Balance := preload("res://scripts/balance.gd")

const PITCH_DEG := -35.0
const YAW_DEG := 45.0
const DISTANCE := 100.0

var camera: Camera3D


func _ready() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = Balance.CAMERA_SIZE_DEFAULT
	camera.near = 1.0
	camera.far = 300.0
	camera.rotation_degrees = Vector3(PITCH_DEG, YAW_DEG, 0)
	camera.position = camera.basis.z * DISTANCE
	add_child(camera)
```

- [ ] **Step 6: scripts/hero.gd 전체 교체**

```gdscript
extends Node3D
## 영웅. 역할(전사/궁수)별 스탯. 배정 자리(면 · 성문 앞/성벽 위 · 슬롯)로 이동하고, 자리에 서 있을 때만
## 수평 사거리 안 가장 가까운 괴물을 자동 공격한다. 성벽 위에 서 있으면 근접 괴물의 표적이 되지 않는다.
## 사망 시 부활 없음, GameState.refilled에서만 배정 자리로 복귀.

const Balance := preload("res://scripts/balance.gd")
const Flat := preload("res://scripts/flat.gd")
const Formation := preload("res://scripts/formation.gd")

enum State { IDLE, MOVE, ATTACK, DEAD }

const SCAN_INTERVAL := 0.2
const ARRIVE_EPS := 0.05
const TRACER_SEC := 0.15

var castle
var formation
var index: int = 0
var role: String = ""
var side: int = 0
var post: int = Formation.POST_GATE
var slot: int = 0
var hp: float = 0.0
var state: int = State.IDLE
var selected := false:
	set(v):
		selected = v
		if _ring != null:
			_ring.visible = v and state != State.DEAD

var _stats: Dictionary = {}
var _body: MeshInstance3D
var _ring: MeshInstance3D
var _area: Area3D
var _target
var _atk_cd := 0.0
var _scan_cd := 0.0


## add_child 전에 호출. 기본 배치: 면 = index % 4, 전사는 성문 앞, 궁수는 성벽 위.
func setup(p_index: int, p_castle, p_formation) -> void:
	index = p_index
	castle = p_castle
	formation = p_formation
	role = Balance.hero_role(index)
	_stats = Balance.HERO_ROLES[role]
	var default_post := Formation.POST_WALL if role == "archer" else Formation.POST_GATE
	var placed := move_to(index % 4, default_post)
	assert(placed, "no free default slot for hero %d" % index)


func _ready() -> void:
	add_to_group("heroes")
	_body = Flat.capsule(0.45, 1.6, _stats.color)
	add_child(_body)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.6
	torus.outer_radius = 0.8
	_ring = Flat.mesh(torus, Flat.HERO_SELECTED)
	_ring.position.y = 0.05
	_ring.visible = false
	add_child(_ring)
	_area = Area3D.new()
	_area.collision_layer = 4
	_area.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.7
	shape.height = 1.8
	cs.shape = shape
	cs.position.y = 0.9
	_area.add_child(cs)
	_area.set_meta("hero", self)
	add_child(_area)
	GameState.refilled.connect(reset)
	reset()


func reset() -> void:
	hp = _stats.hp
	state = State.IDLE
	_target = null
	global_position = stand_position()
	_body.visible = true
	_area.collision_layer = 4
	_ring.visible = selected


func stand_position() -> Vector3:
	return castle.slot_position(side, post, slot)


## 자리 변경 명령. 목표 자리가 가득 차면 false (현재 자리 유지).
func move_to(p_side: int, p_post: int) -> bool:
	var s: int = formation.claim(index, p_side, p_post)
	if s < 0:
		return false
	side = p_side
	post = p_post
	slot = s
	return true


## 실제 높이로 판정한다 — 오르내리는 중에는 지상 취급.
func is_on_wall() -> bool:
	return global_position.y > Balance.WALL_H / 2.0


func take_damage(amount: float) -> void:
	if state == State.DEAD:
		return
	hp = maxf(0.0, hp - amount)
	if hp == 0.0:
		state = State.DEAD
		_body.visible = false
		_ring.visible = false
		_area.collision_layer = 0


func is_alive() -> bool:
	return state != State.DEAD


func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	_atk_cd -= delta
	var dest := stand_position()
	if global_position.distance_to(dest) > ARRIVE_EPS:
		state = State.MOVE
		_target = null
		global_position = global_position.move_toward(dest, float(_stats.speed) * delta)
		return
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = SCAN_INTERVAL
		_target = _nearest_monster()
	if _target != null and is_instance_valid(_target) and _target.is_alive():
		state = State.ATTACK
		if _atk_cd <= 0.0:
			_atk_cd = _stats.atk_interval
			if role == "archer":
				_fire_tracer(_target.global_position)
			_target.take_damage(_stats.atk)
	else:
		_target = null
		state = State.IDLE


func _nearest_monster():
	var best = null
	var best_d: float = _stats.range
	for m in get_tree().get_nodes_in_group("monsters"):
		if not m.is_alive():
			continue
		var d := Formation.flat_distance(global_position, m.global_position)
		if d <= best_d:
			best_d = d
			best = m
	return best


## 궁수 화살 궤적 (시각 효과만. 피해는 발사 즉시 적용).
func _fire_tracer(to: Vector3) -> void:
	var from := global_position + Vector3(0, 1.3, 0)
	var dest := to + Vector3(0, 0.6, 0)
	if Formation.flat_distance(from, dest) < 0.1:
		return
	var bm := BoxMesh.new()
	bm.size = Vector3(0.1, 0.1, 0.8)
	var arrow := Flat.mesh(bm, Flat.ARROW)
	get_parent().add_child(arrow)
	arrow.global_position = from
	arrow.look_at(dest)
	var tw := arrow.create_tween()
	tw.tween_property(arrow, "global_position", dest, TRACER_SEC)
	tw.tween_callback(arrow.queue_free)
```

- [ ] **Step 7: scripts/monster.gd 전체 교체**

```gdscript
extends Node3D
## 괴물(근접). 수평 사거리 안 지상 영웅 우선 공격, 없으면 자기 면 성문 앞으로 직진해 성문 공격.
## 성문이 부서졌으면 성채 앞으로 가서 성 HP 공격. 성벽 위 영웅은 표적으로 삼지 않는다.

const Balance := preload("res://scripts/balance.gd")
const Flat := preload("res://scripts/flat.gd")
const Formation := preload("res://scripts/formation.gd")

const SCAN_INTERVAL := 0.2

signal died(monster)

var castle
var kind: String = "grunt"
var side: int = 0
var stage: int = 1
var hp: float = 0.0
var atk: float = 0.0

var _stats: Dictionary = {}
var _body: MeshInstance3D
var _target_hero
var _atk_cd := 0.0
var _scan_cd := 0.0
var _dead := false


## add_child 전에 호출.
func setup(p_kind: String, p_side: int, p_stage: int, p_castle) -> void:
	assert(Balance.MONSTER.has(p_kind), "unknown monster kind: " + p_kind)
	kind = p_kind
	side = p_side
	stage = p_stage
	castle = p_castle
	_stats = Balance.MONSTER[kind]
	hp = _stats.hp * Balance.hp_scale(stage)
	atk = _stats.atk * Balance.atk_scale(stage)


func _ready() -> void:
	add_to_group("monsters")
	var s: float = _stats.scale
	_body = Flat.capsule(0.4 * s, 1.2 * s, _stats.color)
	add_child(_body)
	global_position = castle.spawn_position(side)
	GameState.refilled.connect(_vanish)


func is_alive() -> bool:
	return not _dead


func take_damage(amount: float) -> void:
	if _dead:
		return
	hp = maxf(0.0, hp - amount)
	if hp == 0.0:
		_dead = true
		died.emit(self)
		queue_free()


func _process(delta: float) -> void:
	if _dead:
		return
	_atk_cd -= delta
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = SCAN_INTERVAL
		_target_hero = _nearest_hero()
	if _target_hero != null and _target_hero.is_alive() and not _target_hero.is_on_wall():
		if _atk_cd <= 0.0:
			_atk_cd = _stats.atk_interval
			_target_hero.take_damage(atk)
		return
	_target_hero = null
	var broken: bool = GameState.is_gate_broken(side)
	var dest: Vector3 = castle.keep_target(side) if broken else castle.gate_target(side)
	if Formation.flat_distance(global_position, dest) > _stats.range:
		global_position = global_position.move_toward(dest, _stats.speed * delta)
	elif _atk_cd <= 0.0:
		_atk_cd = _stats.atk_interval
		if broken:
			GameState.damage_castle(atk)
		else:
			GameState.damage_gate(side, atk)


func _nearest_hero():
	var best = null
	var best_d: float = _stats.range
	for h in get_tree().get_nodes_in_group("heroes"):
		if not h.is_alive() or h.is_on_wall():
			continue
		var d := Formation.flat_distance(global_position, h.global_position)
		if d <= best_d:
			best_d = d
			best = h
	return best


## 리필로 제거될 때. died를 내지 않으므로 Spawner는 refilled에서 카운트를 0으로 맞춘다.
func _vanish() -> void:
	_dead = true
	queue_free()
```

- [ ] **Step 8: scripts/unit_picker.gd 전체 교체**

```gdscript
extends Node
## 탭 → 카메라 레이캐스트 → 영웅 선택 / 선택 영웅을 성문 앞(성문 탭) 또는 성벽 위(성벽 탭)로 이동.
## 드래그(카메라 이동)와 구분: 누른 곳과 뗀 곳이 TAP_MAX_PX 이내일 때만 탭.
## 입력을 소비하지 않는다 — 카메라 리그도 같은 이벤트를 본다.
## 터치는 emulate_mouse_from_touch로 마우스 이벤트가 되므로 마우스만 처리.

const Formation := preload("res://scripts/formation.gd")

const LAYER_GATE := 2
const LAYER_HERO := 4
const LAYER_WALL := 8
const TAP_MAX_PX := 12.0

var camera: Camera3D
var selected

var _press_pos: Vector2 = Vector2.INF
var _pending: Vector2 = Vector2.INF


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_press_pos = mb.position
	elif _press_pos != Vector2.INF:
		if mb.position.distance_to(_press_pos) <= TAP_MAX_PX:
			_pending = mb.position
		_press_pos = Vector2.INF


func _physics_process(_delta: float) -> void:
	if _pending == Vector2.INF:
		return
	var screen_pos := _pending
	_pending = Vector2.INF
	# 영웅을 먼저 쏜다: 성문·성벽 탭 박스(여유 1m)가 그 앞이나 위에 선 영웅을 가리기 때문.
	var hit := _pick(screen_pos, LAYER_HERO)
	if not hit.is_empty():
		_select(hit.collider.get_meta("hero"))
		return
	hit = _pick(screen_pos, LAYER_GATE)
	if not hit.is_empty():
		_order(hit.collider.get_meta("side"), Formation.POST_GATE)
		return
	hit = _pick(screen_pos, LAYER_WALL)
	if not hit.is_empty():
		_order(hit.collider.get_meta("side"), Formation.POST_WALL)
		return
	_select(null)


func _order(side: int, post: int) -> void:
	if selected != null and selected.is_alive():
		selected.move_to(side, post)
	else:
		_select(null)


func _pick(screen_pos: Vector2, layer_mask: int) -> Dictionary:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 400.0
	var q := PhysicsRayQueryParameters3D.create(from, to, layer_mask)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	return camera.get_world_3d().direct_space_state.intersect_ray(q)


func _select(hero) -> void:
	if selected != null and is_instance_valid(selected):
		selected.selected = false
	selected = hero
	if selected != null:
		selected.selected = true
```

- [ ] **Step 9: scripts/main.gd 전체 교체**

```gdscript
extends Node3D
## 월드 조립. 씬 파일은 이것 하나. 나머지는 코드로 생성.
## 개발용 auto-stage: 네이티브는 유저 인자 `-- --auto-stage`, 웹은 URL에 `?auto-stage` → 시작 즉시 스테이지 진행.

const Balance := preload("res://scripts/balance.gd")
const CastleScript := preload("res://scripts/castle.gd")
const BuildingsScript := preload("res://scripts/buildings.gd")
const CameraRigScript := preload("res://scripts/camera_rig.gd")
const FormationScript := preload("res://scripts/formation.gd")
const HeroScript := preload("res://scripts/hero.gd")
const PickerScript := preload("res://scripts/unit_picker.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")
const HudScript := preload("res://scripts/hud.gd")
const GroundShader := preload("res://shaders/ground_grid.gdshader")

var camera: Camera3D
var castle
var formation
var heroes: Array = []


func _ready() -> void:
	_build_environment()
	castle = CastleScript.new()
	add_child(castle)
	_build_ground(castle.half)
	add_child(BuildingsScript.new())
	var rig = CameraRigScript.new()
	add_child(rig)
	camera = rig.camera
	formation = FormationScript.new()
	for i in GameState.hero_count():
		var hero = HeroScript.new()
		hero.setup(i, castle, formation)
		add_child(hero)
		heroes.append(hero)
	var picker = PickerScript.new()
	picker.camera = camera
	add_child(picker)
	var spawner = SpawnerScript.new()
	spawner.castle = castle
	add_child(spawner)
	add_child(HudScript.new())
	_connect_dev_log()
	if _auto_stage_requested():
		GameState.start_stage()


func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.88, 0.90, 0.94)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = false
	add_child(sun)
	sun.rotation_degrees = Vector3(-55, 35, 0)


func _build_ground(interior_half: float) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(Balance.MAP_HALF * 2.0, Balance.MAP_HALF * 2.0)
	var mat := ShaderMaterial.new()
	mat.shader = GroundShader
	mat.set_shader_parameter("tile_size", Balance.TILE)
	mat.set_shader_parameter("interior_half", interior_half)
	mat.set_shader_parameter("road_half", Balance.TILE)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	add_child(mi)


func _connect_dev_log() -> void:
	GameState.mode_changed.connect(func(m): print("[mode] %d stage=%d" % [m, GameState.stage]))
	GameState.stage_cleared.connect(func(s): print("[cleared] %d" % s))
	GameState.stage_failed.connect(func(s): print("[failed] %d" % s))


func _auto_stage_requested() -> bool:
	if OS.get_cmdline_user_args().has("--auto-stage"):
		return true
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("window.location.search")).contains("auto-stage")
	return false
```

- [ ] **Step 10: scripts/balance.gd에서 쓰지 않게 된 구 상수 삭제**

삭제할 줄 (다른 곳에서 더 이상 참조하지 않음 — `grep -rn "CASTLE_SIZE\|GATE_STAND_OFFSET\|SPAWN_DISTANCE\|Balance.HERO\b" scripts tests`로 0건 확인 후 삭제):
```gdscript
const CASTLE_SIZE := 10.0        # 성벽 한 변 (미터)
const GATE_STAND_OFFSET := 1.5   # 성문 바깥 영웅 자리까지 거리
const SPAWN_DISTANCE := 18.0     # 성 중심에서 스폰 지점까지
```
그리고 `const HERO := {...}` 블록 전체(3줄).

- [ ] **Step 11: uid 생성 + 테스트 + 스모크**

```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --editor --quit 2>&1 | grep -E "ERROR"
ls scripts/buildings.gd.uid scripts/camera_rig.gd.uid shaders/
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd; echo "exit=$?"
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --fixed-fps 60 --quit-after 1800 2>&1 | grep -cE "SCRIPT ERROR|ERROR"
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --fixed-fps 60 --quit-after 1800 -- --auto-stage 2>&1 | grep -cE "SCRIPT ERROR|ERROR"
```
Expected: uid 파일 존재(셰이더도 `.gdshader.uid`가 생기면 커밋), `ALL PASSED`, 두 스모크 모두 `0`.

- [ ] **Step 12: 웹 캡처로 화면 확인**

```bash
bash dev/build-web.sh
```
서버(`npm --prefix dev run serve`)를 백그라운드로 띄운 뒤:
```bash
W=.superpowers/sdd/2026-09-28-castlerpg-mvp-rev2
node dev/webshot.mjs --out $W/t3-idle.png --wait 5000
node dev/webshot.mjs --url "http://localhost:8060/?auto-stage" --out $W/t3-stage.png --wait 15000
```
Read 두 PNG. Expected `t3-idle.png`: 45° 돌아간 마름모 모양 성, 잔디 체커 격자 바닥, 성 안 포장 타일과 십자 도로, 모서리 탑 4개, 한글 이름표 달린 건물 8개(성채가 중앙에서 가장 큼), 파란 전사 2명이 두 성문 바로 바깥에, 초록 궁수 2명이 다른 두 면 성벽 위에. `t3-stage.png`: 사방에서 빨간 몬스터가 성문으로 접근, 전사 근처 교전, 궁수 쪽에 화살(짧은 갈색 막대)이 보일 수 있음. 콘솔에 `[pageerror]` 없음.

화면이 기대와 다르면(성이 잘림, 이름표가 안 보임, 바닥 격자 없음 등) 원인을 찾아 고친다 — 이름표 크기(`pixel_size`)나 카메라 기본 크기(`CAMERA_SIZE_DEFAULT`) 조정은 허용, 조정값은 보고서에 적는다.

서버 종료 (Global Constraints 명령).

- [ ] **Step 13: 커밋**

```bash
git add shaders scripts
git status --short
git commit -m "feat: quarter-view battlefield with grid tiles, big castle and wall-top combat

Ground grid shader, thick walls with corner towers sized by keep level,
eight labeled placeholder buildings, a quarter-view camera rig, hero
roles on gate-front and wall-top slots, archers with arrow tracers, and
melee monsters that cannot reach heroes standing on the walls.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 카메라 드래그·줌 + HUD 입력 통과

**Files:**
- Modify: `scripts/camera_rig.gd` (입력 추가)
- Modify: `scripts/hud.gd` (컨테이너·바 마우스 무시)
- Modify: `dev/webshot.mjs` (`--drag`, `--wheel` 동작 추가)
- Modify: `scripts/unit_picker.gd` (드래그·핀치 중 탭 취소 — Task 3 리뷰 지적)
- Modify: `scripts/hero.gd` (탭 판정 반경 확대 — 모바일 손가락 크기)

**Interfaces:**
- Consumes: `Balance.CAMERA_SIZE_MIN/MAX`, `MAP_HALF`
- Produces `camera_rig.gd`: `pan_pixels(rel: Vector2)`, `zoom_by(factor: float)`. `_unhandled_input`에서 마우스 드래그(12px 넘으면 드래그 확정)·휠·두 손가락 핀치 처리. 입력을 소비하지 않는다
- Produces `webshot.mjs`: `--drag x1,y1,x2,y2[,ms]`, `--wheel x,y,dy[,ms]`, `--dragback x,y,dx,dy[,ms]` (인자 순서대로 실행)

- [ ] **Step 1: scripts/camera_rig.gd 전체 교체**

```gdscript
extends Node3D
## 쿼터뷰 직교 카메라 리그. 리그 위치 = 화면 중앙이 바라보는 바닥 지점.
## 한 손가락/마우스 드래그로 이동(DRAG_THRESHOLD_PX 넘으면 드래그 확정), 휠·두 손가락 핀치로 줌.
## 입력을 소비하지 않는다 — 탭 판정(UnitPicker)도 같은 이벤트를 본다.

const Balance := preload("res://scripts/balance.gd")

const PITCH_DEG := -35.0
const YAW_DEG := 45.0
const DISTANCE := 100.0
const DRAG_THRESHOLD_PX := 12.0
const ZOOM_STEP := 1.1
const PAN_LIMIT_MARGIN := 20.0

var camera: Camera3D

var _press_pos: Vector2 = Vector2.INF
var _dragging := false
var _touches := {}  # 터치 index -> 화면 위치 (핀치용)


func _ready() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = Balance.CAMERA_SIZE_DEFAULT
	camera.near = 1.0
	camera.far = 300.0
	camera.rotation_degrees = Vector3(PITCH_DEG, YAW_DEG, 0)
	camera.position = camera.basis.z * DISTANCE
	add_child(camera)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _touches.size() >= 2 and _touches.has(sd.index):
			_pinch(sd)
		if _touches.has(sd.index):
			_touches[sd.index] = sd.position
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_by(1.0 / ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_by(ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_press_pos = mb.position if mb.pressed else Vector2.INF
			_dragging = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _press_pos == Vector2.INF or _touches.size() >= 2:
			return
		if not _dragging and mm.position.distance_to(_press_pos) > DRAG_THRESHOLD_PX:
			_dragging = true
		if _dragging:
			pan_pixels(mm.relative)


## 화면 픽셀 이동량만큼 바닥이 손가락을 따라오게 리그를 옮긴다.
func pan_pixels(rel: Vector2) -> void:
	var world_per_px := camera.size / get_viewport().get_visible_rect().size.x
	var right := camera.global_basis.x
	right.y = 0.0
	right = right.normalized()
	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var ground_stretch := 1.0 / sin(deg_to_rad(-PITCH_DEG))  # 화면 세로 1px이 바닥에서 늘어나는 비율
	position += -right * rel.x * world_per_px + forward * rel.y * world_per_px * ground_stretch
	var limit := Balance.MAP_HALF - PAN_LIMIT_MARGIN
	position.x = clampf(position.x, -limit, limit)
	position.z = clampf(position.z, -limit, limit)


## factor < 1 이면 확대.
func zoom_by(factor: float) -> void:
	camera.size = clampf(camera.size * factor, Balance.CAMERA_SIZE_MIN, Balance.CAMERA_SIZE_MAX)


func _pinch(sd: InputEventScreenDrag) -> void:
	var other_pos := Vector2.INF
	for i in _touches:
		if i != sd.index:
			other_pos = _touches[i]
			break
	var prev_pos: Vector2 = _touches[sd.index]
	var old_d := prev_pos.distance_to(other_pos)
	var new_d := sd.position.distance_to(other_pos)
	if old_d > 1.0 and new_d > 1.0:
		zoom_by(old_d / new_d)
```

- [ ] **Step 2: scripts/hud.gd 수정 — 드래그가 HUD 위에서 시작해도 카메라로 전달되게**

`_ready()`에서 `root.add_child(top)` 바로 앞에 추가:
```gdscript
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
```
`var gates := HBoxContainer.new()` 바로 다음 줄에 추가:
```gdscript
	gates.mouse_filter = Control.MOUSE_FILTER_IGNORE
```
`_bar()`에서 `b.show_percentage = false` 다음 줄에 추가:
```gdscript
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
```

- [ ] **Step 3: dev/webshot.mjs에 드래그·휠 추가**

사용법 주석 둘째 줄을 교체:
```js
//                            [--click x,y[,ms]]... [--drag x1,y1,x2,y2[,ms]]... [--wheel x,y,dy[,ms]]... [--dragback x,y,dx,dy[,ms]]...
```
인자 파싱의 `--click` 분기 다음에 추가:
```js
  else if (a === '--drag') { opt.actions.push({ type: 'drag', nums: v.split(',').map(Number) }); i++; }
  else if (a === '--wheel') { opt.actions.push({ type: 'wheel', nums: v.split(',').map(Number) }); i++; }
  else if (a === '--dragback') { opt.actions.push({ type: 'dragback', nums: v.split(',').map(Number) }); i++; }
```
동작 루프의 `click` 분기 다음에 추가:
```js
  else if (act.type === 'drag') {
    const [x1, y1, x2, y2, ms = 500] = act.nums;
    await page.mouse.move(x1, y1);
    await page.mouse.down();
    await page.mouse.move(x2, y2, { steps: 12 });
    await page.mouse.up();
    await page.waitForTimeout(ms);
  } else if (act.type === 'wheel') {
    const [x, y, dy, ms = 500] = act.nums;
    await page.mouse.move(x, y);
    await page.mouse.wheel(0, dy);
    await page.waitForTimeout(ms);
  } else if (act.type === 'dragback') {
    // 한 번 누른 채 (dx,dy)만큼 갔다가 제자리로 돌아와 뗀다 — 탭으로 오인되면 안 되는 동작
    const [x, y, dx, dy, ms = 500] = act.nums;
    await page.mouse.move(x, y);
    await page.mouse.down();
    await page.mouse.move(x + dx, y + dy, { steps: 8 });
    await page.mouse.move(x, y, { steps: 8 });
    await page.mouse.up();
    await page.waitForTimeout(ms);
  }
```
(`if (act.type === 'click') { ... }` 블록 뒤에 `else if`로 이어 붙인다.)

- [ ] **Step 3a: scripts/unit_picker.gd — 드래그·핀치면 탭 취소**

현재는 누른 곳과 뗀 곳만 비교해서, 멀리 끌었다가 제자리로 돌아와 떼거나 핀치 후 첫 손가락을 떼면 탭으로 처리된다(의도치 않은 이동 명령). 이동 중 한 번이라도 `TAP_MAX_PX`를 넘으면 그 누름은 탭이 아니고, 두 번째 손가락이 닿아도 탭이 아니다.

`_unhandled_input` 전체를 교체:
```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).index >= 1:
			_press_pos = Vector2.INF  # 두 번째 손가락 = 핀치. 이번 누름은 탭이 아니다
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _press_pos != Vector2.INF and mm.position.distance_to(_press_pos) > TAP_MAX_PX:
			_press_pos = Vector2.INF  # 드래그로 확정. 되돌아와 떼도 탭이 아니다
		return
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_press_pos = mb.position
	elif _press_pos != Vector2.INF:
		_pending = mb.position
		_press_pos = Vector2.INF
```
파일 머리 주석의 "누른 곳과 뗀 곳이 TAP_MAX_PX 이내일 때만 탭" 줄을 "누른 뒤 뗄 때까지 TAP_MAX_PX 넘게 움직이지 않고 두 번째 손가락도 없을 때만 탭"으로 바꾼다.

- [ ] **Step 3b: scripts/hero.gd — 탭 판정 반경 확대**

기본 줌에서 영웅이 화면에서 20px 안팎이라 손가락으로 누르기 어렵다. 판정 캡슐만 키운다(보이는 몸은 그대로).

상수 블록(`const TRACER_SEC := 0.15` 다음)에 추가:
```gdscript
const TAP_RADIUS := 1.4  # 탭 판정 캡슐 반경(m). 몸(0.45m)보다 크게 — 손가락 크기
const TAP_HEIGHT := 2.6
```
`_ready()`의 판정 캡슐 부분을 교체:
```gdscript
	shape.radius = TAP_RADIUS
	shape.height = TAP_HEIGHT
	cs.shape = shape
	cs.position.y = TAP_HEIGHT / 2.0
```
(기존 `shape.radius = 0.7`, `shape.height = 1.8`, `cs.shape = shape`, `cs.position.y = 0.9` 네 줄을 대체.)

- [ ] **Step 4: 테스트 + 스모크**

Run: 테스트 명령과 스모크 명령 (Global Constraints). Expected: `ALL PASSED`, `0`.

- [ ] **Step 5: 웹 캡처로 입력 확인**

`bash dev/build-web.sh`, 서버 백그라운드 실행 후:
```bash
W=.superpowers/sdd/2026-09-28-castlerpg-mvp-rev2
node dev/webshot.mjs --out $W/t4-base.png --wait 5000
node dev/webshot.mjs --out $W/t4-drag.png --wait 5000 --drag 180,320,80,420
node dev/webshot.mjs --out $W/t4-zoomin.png --wait 5000 --wheel 180,320,-300 --wheel 180,320,-300
node dev/webshot.mjs --out $W/t4-zoomout.png --wait 5000 --wheel 180,320,300 --wheel 180,320,300
node dev/webshot.mjs --out $W/t4-hud-drag.png --wait 5000 --drag 180,40,80,140
```
Read 다섯 장. Expected: `drag` — 성이 기준보다 왼쪽 아래로 이동(손가락을 따라감). `zoomin` — 성이 더 크게. `zoomout` — 더 작게, 맵 가장자리가 보일 수 있음. `hud-drag` — HUD 위(상단 바 영역)에서 시작한 드래그도 화면을 이동시킨다. 콘솔에 `[pageerror]` 없음.

탭과 드래그 구분 확인: `t4-base.png`에서 한 궁수(초록)의 화면 좌표(CSS px = PNG 픽셀 / 2)와 다른 면 성문의 좌표를 읽고,
```bash
node dev/webshot.mjs --out $W/t4-tap-move.png --wait 5000 --click AX,AY,300 --click GX,GY,3000
node dev/webshot.mjs --out $W/t4-drag-no-select.png --wait 5000 --drag AX,AY,AX+40,AY+40
node dev/webshot.mjs --out $W/t4-dragback-no-order.png --wait 5000 --click AX,AY,300 --dragback GX,GY,80,0,3000
```
(`AX,AY`=궁수, `GX,GY`=성문, 숫자로 바꿔 넣는다.) Expected: `tap-move` — 그 궁수가 목표 성문 바로 바깥에 서 있고 발밑에 노란 링. `drag-no-select` — 화면만 이동하고 노란 링 없음. `dragback-no-order` — 궁수는 선택(노란 링)됐지만 원래 성벽 자리에 그대로(성문으로 가지 않음).

서버 종료.

- [ ] **Step 6: 커밋**

```bash
git add scripts/camera_rig.gd scripts/hud.gd scripts/unit_picker.gd scripts/hero.gd dev/webshot.mjs
git commit -m "feat: camera drag pan, wheel and pinch zoom; HUD passes drags through

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 엔드투엔드 밸런스 + 최종 화면 확인 + 문서

**Files:**
- Modify (필요 시): `scripts/balance.gd`, `docs/superpowers/specs/2026-09-28-castlerpg-mvp-rev2-design.md` §5
- Modify: `docs/superpowers/specs/2026-09-28-castlerpg-mvp-design.md` §9 실행 방법 줄

**Interfaces:**
- Consumes: 모든 이전 태스크. 개발 로그 `[mode] N stage=S`, `[cleared] S`, `[failed] S` (N: 0 IDLE, 1 STAGE, 2 COUNTDOWN, 3 RESULT)

- [ ] **Step 1: 헤드리스 엔드투엔드 — 스테이지 1 → 2**

```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --fixed-fps 60 --quit-after 9000 -- --auto-stage 2>&1 | grep -E "^\[(mode|cleared|failed)\]|SCRIPT ERROR"
```
Expected: `[mode] 1 stage=1` → `[cleared] 1` → `[mode] 3 stage=2` → `[mode] 2 stage=2` → `[mode] 1 stage=2`. `SCRIPT ERROR` 없음.

`[failed] 1`이 나오면: 먼저 원인을 확인한다(어느 성문이 부서졌는지, 보스가 어느 면에서 나왔는지, 영웅이 죽었는지 — 임시 print를 넣고 확인 후 반드시 제거). 헤드리스 진행은 영웅을 움직이지 않으므로 기본 배치(성문 앞 전사 2, 성벽 위 궁수 2)로 스테이지 1이 클리어돼야 한다. 원인이 밸런스면 `balance.gd`의 `HERO_ROLES`, `epic_boss`, `gate_hp_max` 중 원인에 맞는 값을 조정하고 spec 개정 2 §5 표와 v1 spec §6 해당 줄을 같은 커밋에서 갱신한다. 원인이 로직 버그면 버그를 고친다. 통과할 때까지 반복.

- [ ] **Step 2: 패배 → 방치 복귀 확인**

`balance.gd`의 `HERO_ROLES`에서 전사·궁수 `atk`를 임시로 `1.0`으로 바꾸고 Step 1 명령 실행. Expected: `[failed] 1` → `[mode] 3 stage=1` → `[mode] 0 stage=1`. 확인 후 값을 되돌리고 `git diff scripts/balance.gd`가 Step 1에서 의도한 변경만 남았는지 확인.

- [ ] **Step 3: 테스트 + 스모크 재실행**

Expected: `ALL PASSED`, `0`.

- [ ] **Step 4: 최종 웹 캡처**

`bash dev/build-web.sh`, 서버 백그라운드 실행 후:
```bash
W=.superpowers/sdd/2026-09-28-castlerpg-mvp-rev2
node dev/webshot.mjs --out $W/t5-idle.png --wait 5000
node dev/webshot.mjs --url "http://localhost:8060/?auto-stage" --out $W/t5-battle.png --wait 20000
node dev/webshot.mjs --url "http://localhost:8060/?auto-stage" --out $W/t5-zoom-battle.png --wait 20000 --wheel 180,320,-300 --wheel 180,320,-300
```
Step 1 로그로 클리어 시각을 가늠해 클리어 배너 구간을 찍는다(웹은 실시간이므로 `--wait`를 클리어 시각 + 1초로):
```bash
node dev/webshot.mjs --url "http://localhost:8060/?auto-stage" --out $W/t5-clear.png --wait <ms>
```
Read 전부. Expected: spec 개정 2 §9의 화면 항목 전부 — 쿼터뷰 마름모 성, 격자·도로, 이름표 건물 8개, 성문 앞 전사·성벽 위 궁수, 전투 중 몬스터와 화살, 줌, 한글 정상, 클리어 배너 또는 카운트다운. 캡처 설명을 보고서에 적는다.

서버 종료.

- [ ] **Step 5: 문서**

`docs/superpowers/specs/2026-09-28-castlerpg-mvp-design.md` §9의 `- 실행 방법:`으로 시작하는 줄을 다음으로 교체:
```markdown
- 실행 방법: 개정 2 §8 참고 (창을 띄우지 않는다. 웹 빌드 → VSCode Simple Browser)
```
같은 파일 §9의 `- 수동: 데스크톱 실행...` 줄을 삭제.

`docs/superpowers/specs/2026-09-28-castlerpg-mvp-rev2-design.md` §3의 `줌(직교 크기) 16~90, 기본 44.`를 실제 값(`Balance.CAMERA_SIZE_DEFAULT`, Task 3에서 56으로 조정 — 레벨 1 성 전체가 보이게)으로 고치고, §6 탭 규칙을 "누른 뒤 뗄 때까지 12px 넘게 움직이지 않고 두 번째 손가락도 없으면 탭"으로 고친다.
같은 spec §6·§7에서 영웅 탭 판정을 "화면에서 탭 위치와 가장 가까운 살아 있는 영웅(32 논리 px 이내), 물리 판정 영역 없음"으로, 탭 판정 레이어 줄을 "성문 2, 성벽 8"로 고친다 (Task 4 수정 라운드 결정).

- [ ] **Step 6: 완료 기준 점검 (spec 개정 2 §9)**

```bash
ls scripts/*.gd | wc -l      # 15 이하
ls scenes/*.tscn | wc -l     # 1
git status --short           # 깨끗하거나 이번 태스크 변경만
```

- [ ] **Step 7: 커밋**

```bash
git add scripts/balance.gd docs
git commit -m "test: end-to-end stage loop verified on the revision-2 battlefield

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
(밸런스 변경이 있었다면 제목을 `balance: ...`로 하고 무엇을 왜 바꿨는지 본문에 적는다.)

---

## 자체 검토

- **Spec 커버리지 (개정 2):** §1 시점(T3 리그, T4 입력), 격자(T3 셰이더), 성 크기·레벨별(T2 데이터, T3 성), 건물 8종(T2 배치 규칙·테스트, T3 표시), 역할·자리(T2 Formation, T3 영웅), 성벽 위 규칙(T3 영웅·몬스터), 탭 구분·성벽 탭(T3 피커), 폰트(T1), 창 금지 미리보기(T1 도구, 전 태스크 확인). §6 카메라·HUD 입력(T4). §8 명령(T1, T4). §9 완료 기준(T5)
- **플레이스홀더:** 없음. Task 4 Step 5와 Task 5 Step 4의 좌표·대기 시간은 실행 중 캡처에서 읽어 채우는 값이며 방법을 명시했다
- **이름 일관성:** `Formation.POST_GATE/POST_WALL`, `claim`, `slot_position(half, side, post, slot)` T2 → castle 래퍼 `slot_position(side, post, slot)` T3 → hero `stand_position()` T3. `castle.gate_target/keep_target/spawn_position` T3 → monster T3. `hero.move_to(side, post)`, `is_on_wall()` T3 → picker·monster T3. `camera_rig.camera` T3 → main. 레이어 2/4/8 castle·hero·picker 일치
- **태스크 간 동작 상태:** T1 후 기존 게임 그대로 동작(웹에서도). T2는 추가만. T3 후 새 전장 동작(카메라 고정). T4 후 입력. T5 밸런스·검증

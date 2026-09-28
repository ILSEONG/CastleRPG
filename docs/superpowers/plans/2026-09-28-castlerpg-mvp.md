# CastleRPG MVP 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 성문 4개짜리 성을 영웅 4명으로 지키는 코어 루프(방치 스폰 → 스테이지 웨이브 → 에픽 보스 → 리필 → 3초 카운트 → 다음 스테이지)를 Godot 4.7.2에서 끝까지 돌아가게 만든다.

**Architecture:** 씬 파일은 `scenes/main.tscn` 하나. 모든 오브젝트는 GDScript가 코드로 생성한다(플레이스홀더 박스·캡슐). 상태의 단일 진실은 오토로드 `GameState`이고, HUD·영웅·몬스터·스포너는 그 시그널만 구독한다. 순수 로직(`balance.gd`, `wave_director.gd`, `game_state.gd`)은 씬 없이 `.new()`로 만들 수 있어 헤드리스 테스트가 된다.

**Tech Stack:** Godot 4.7.2 stable (실행 파일 `tools/Godot_v4.7.2-stable_win64_console.exe`, git 제외), GDScript, Compatibility 렌더러. 외부 라이브러리·에셋 없음.

## Global Constraints

- Godot 4.7.2 stable. 실행은 항상 `./tools/Godot_v4.7.2-stable_win64_console.exe --path .` (Git Bash 기준, 프로젝트 루트에서)
- 화면 720×1280 세로, stretch `canvas_items`, aspect `expand`, 렌더러 `gl_compatibility`
- `class_name` 사용 금지. 스크립트 간 참조는 `const X := preload("res://scripts/x.gd")`. 이유: 헤드리스 CLI 실행에서 글로벌 클래스 캐시 없이도 동작해야 함
- 물리 바디 없음. 유닛 이동은 `global_position` 직접 갱신. `Area3D`는 탭 판정용으로만 (성문 레이어 2, 영웅 레이어 4)
- 몬스터 동시 상한 `MAX_LIVE_MONSTERS = 120`. 타깃 탐색 주기 0.2초
- 다른 스크립트의 노드를 담는 변수는 타입 없이 선언(`var castle`). 이유: `Node3D` 타입으로 두면 커스텀 메서드 호출마다 UNSAFE_METHOD_ACCESS 경고
- 오토로드 enum을 `match` 패턴에 쓰지 않는다(`GameState.Mode.IDLE`은 `if/elif`로). `game_state.gd` 내부에서는 `match mode:` 사용 가능
- 외부 에셋 0개. 스크립트 12개 이내(테스트 제외), 씬 1개
- 커밋 메시지 끝에 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- 테스트 실행: `./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd` → 마지막 줄 `ALL PASSED`, 종료 코드 0
- 스모크 실행: `./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --fixed-fps 60 --quit-after 900 -- --auto-stage 2>&1 | grep -c "SCRIPT ERROR"` → `0`
- 스크린샷 확인: `./tools/Godot_v4.7.2-stable_win64_console.exe --path . --resolution 540x960 -- --shot=SECONDS` → `tools/shot.png` 생성 후 자동 종료. Read 도구로 PNG를 열어 눈으로 확인

## 파일 구조

| 파일 | 책임 |
|---|---|
| `project.godot` | 설정, 오토로드 `GameState` |
| `scenes/main.tscn` | 유일한 씬. `Node3D` + `main.gd` |
| `scripts/balance.gd` | 밸런스 상수·스케일 함수 (static) |
| `scripts/flat.gd` | 단색 메시 헬퍼 + 팔레트 상수 (static) |
| `scripts/wave_director.gd` | 스폰 스케줄 생성 (static, 순수 로직) |
| `scripts/game_state.gd` | 오토로드. 모드·스테이지·성/성문 HP·시그널 |
| `scripts/castle.gd` | 성벽·성문·성채 메시, 성문 `Area3D`, 위치 제공 |
| `scripts/hero.gd` | 영웅 상태머신, 자동 공격, 선택 링 |
| `scripts/monster.gd` | 몬스터 상태머신 (영웅 → 성문 → 성채) |
| `scripts/spawner.gd` | 스케줄 소비, 몬스터 생성, 전멸 감지 |
| `scripts/unit_picker.gd` | 탭 레이캐스트 → 선택/이동 |
| `scripts/hud.gd` | 라벨·HP 바·버튼·카운트다운·배너 |
| `scripts/main.gd` | 월드 조립, 개발용 `--shot`, `--auto-stage` |
| `tests/run_tests.gd` | 헤드리스 테스트 러너 |

---

### Task 1: 프로젝트 골격 + Balance + 테스트 러너

**Files:**
- Create: `project.godot`
- Create: `scenes/main.tscn`
- Create: `scripts/main.gd` (임시. Task 5에서 교체)
- Create: `scripts/balance.gd`
- Create: `tests/run_tests.gd`

**Interfaces:**
- Produces: `Balance` (preload) — 상수 `CASTLE_HP: float`, `CASTLE_SIZE: float`, `GATE_STAND_OFFSET: float`, `SPAWN_DISTANCE: float`, `HERO_SLOTS: Array`, `MAX_LIVE_MONSTERS: int`, `COUNTDOWN_SEC: float`, `RESULT_SEC: float`, `WAVE_GAP_SEC: float`, `SPAWN_SPACING_SEC: float`, `HERO: Dictionary`, `MONSTER: Dictionary`; static 함수 `gate_hp_max(level: int) -> float`, `hero_slots(keep_level: int) -> int`, `hp_scale(stage: int) -> float`, `atk_scale(stage: int) -> float`, `idle_interval(stage: int) -> float`, `wave_count(stage: int) -> int`, `wave_size(stage: int, wave_index: int) -> int`
- Produces: 테스트 러너의 `check(cond: bool, msg: String)` 패턴. 이후 태스크는 이 파일에 `test_*` 함수를 추가하고 `_init()`의 호출 목록에 넣는다

- [ ] **Step 1: project.godot 작성**

```ini
; Engine configuration file.
; It's best edited using the editor UI and not directly,
; since the parameters that go here are not all obvious.

config_version=5

[application]

config/name="CastleRPG"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")

[autoload]

GameState="*res://scripts/game_state.gd"

[display]

window/size/viewport_width=720
window/size/viewport_height=1280
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
window/handheld/orientation=1

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
```

주의: `[autoload]`가 아직 없는 `game_state.gd`를 가리킨다. Task 3까지는 실행 시 "autoload not found" 오류가 뜬다. Task 1·2는 `-s` 테스트만 돌리므로 무시하고 진행하되, 오류를 없애기 위해 이 태스크에서 빈 스텁 `scripts/game_state.gd`도 만든다(Step 4).

- [ ] **Step 2: scenes/main.tscn 작성**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/main.gd" id="1"]

[node name="Main" type="Node3D"]
script = ExtResource("1")
```

- [ ] **Step 3: 임시 scripts/main.gd 작성**

```gdscript
extends Node3D


func _ready() -> void:
	print("CastleRPG main ready")
```

- [ ] **Step 4: 스텁 scripts/game_state.gd 작성**

```gdscript
extends Node
## Task 3에서 구현. 오토로드 경로가 깨지지 않게 하는 스텁.
```

- [ ] **Step 5: 실패하는 테스트 작성 — tests/run_tests.gd**

```gdscript
extends SceneTree
## 순수 로직 헤드리스 테스트.
## 실행: ./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd

const Balance := preload("res://scripts/balance.gd")

var _fails := 0


func _init() -> void:
	test_balance_monotonic()
	test_balance_tables()
	if _fails > 0:
		printerr("FAILED %d" % _fails)
	else:
		print("ALL PASSED")
	quit(1 if _fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		printerr("FAIL: " + msg)


func test_balance_monotonic() -> void:
	for stage in range(1, 20):
		check(Balance.hp_scale(stage + 1) >= Balance.hp_scale(stage), "hp_scale monotonic at %d" % stage)
		check(Balance.atk_scale(stage + 1) >= Balance.atk_scale(stage), "atk_scale monotonic at %d" % stage)
		check(Balance.wave_count(stage + 1) >= Balance.wave_count(stage), "wave_count monotonic at %d" % stage)
		check(Balance.wave_size(stage + 1, 0) >= Balance.wave_size(stage, 0), "wave_size monotonic at %d" % stage)


func test_balance_tables() -> void:
	check(Balance.hero_slots(1) == 4, "keep level 1 gives 4 heroes")
	check(Balance.hero_slots(2) == 8, "keep level 2 gives 8 heroes")
	check(Balance.hero_slots(3) == 12, "keep level 3 gives 12 heroes")
	check(Balance.hero_slots(99) == 12, "keep level beyond table clamps to last")
	check(Balance.gate_hp_max(1) == 400.0, "gate hp at level 1")
	check(Balance.gate_hp_max(2) > Balance.gate_hp_max(1), "gate hp grows with level")
	check(Balance.MONSTER.has("grunt") and Balance.MONSTER.has("epic_boss"), "monster table has grunt and epic_boss")
	for kind in Balance.MONSTER:
		for key in ["hp", "atk", "speed", "range", "atk_interval", "scale", "color"]:
			check(Balance.MONSTER[kind].has(key), "monster %s has %s" % [kind, key])
```

- [ ] **Step 6: 테스트 실행 → 실패 확인**

Run:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd; echo "exit=$?"
```
Expected: `res://scripts/balance.gd` 로드 실패 오류(파일 없음) 또는 파스 오류. 종료 코드 0이 아님.

- [ ] **Step 7: scripts/balance.gd 작성**

```gdscript
extends RefCounted
## 밸런스 상수와 스케일 함수. 튠은 여기서만.

const CASTLE_HP := 1000.0
const CASTLE_SIZE := 10.0        # 성벽 한 변 (미터)
const GATE_STAND_OFFSET := 1.5   # 성문 바깥 영웅 자리까지 거리
const SPAWN_DISTANCE := 18.0     # 성 중심에서 스폰 지점까지
const HERO_SLOTS := [4, 8, 12]   # index = keep_level - 1
const MAX_LIVE_MONSTERS := 120
const COUNTDOWN_SEC := 3.0
const RESULT_SEC := 2.0
const WAVE_GAP_SEC := 8.0
const SPAWN_SPACING_SEC := 0.5

const HERO := {
	"hp": 300.0, "atk": 25.0, "range": 3.0, "atk_interval": 0.8, "speed": 6.0,
}

const MONSTER := {
	"grunt": {
		"hp": 60.0, "atk": 10.0, "speed": 2.5, "range": 1.2, "atk_interval": 1.0,
		"scale": 1.0, "color": Color(0.85, 0.3, 0.3),
	},
	"epic_boss": {
		"hp": 400.0, "atk": 20.0, "speed": 1.8, "range": 1.8, "atk_interval": 1.2,
		"scale": 2.5, "color": Color(0.6, 0.1, 0.5),
	},
}


static func gate_hp_max(level: int) -> float:
	return 400.0 * level


static func hero_slots(keep_level: int) -> int:
	return HERO_SLOTS[clampi(keep_level, 1, HERO_SLOTS.size()) - 1]


static func hp_scale(stage: int) -> float:
	return 1.0 + 0.25 * (stage - 1)


static func atk_scale(stage: int) -> float:
	return 1.0 + 0.15 * (stage - 1)


static func idle_interval(_stage: int) -> float:
	return 4.0


static func wave_count(stage: int) -> int:
	return 3 + floori(stage / 3.0)


static func wave_size(stage: int, _wave_index: int) -> int:
	return 6 + 2 * stage
```

- [ ] **Step 8: 에디터 임포트 1회 실행 (`.godot/` 생성)**

Run:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --import 2>&1 | tail -5; echo "exit=$?"
```
Expected: 종료 코드 0. `.godot/` 폴더 생성. 첫 실행이라 에디터 설정 생성 메시지가 나올 수 있음.

- [ ] **Step 9: 테스트 실행 → 통과 확인**

Run:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd; echo "exit=$?"
```
Expected: 마지막 줄 `ALL PASSED`, `exit=0`.

- [ ] **Step 10: 커밋**

```bash
git add project.godot scenes scripts tests
git commit -m "feat: project skeleton, balance table, headless test runner

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: WaveDirector (스폰 스케줄, 순수 로직)

**Files:**
- Create: `scripts/wave_director.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Consumes: `Balance.idle_interval`, `wave_count`, `wave_size`, `SPAWN_SPACING_SEC`, `WAVE_GAP_SEC`
- Produces: `WaveDirector` (preload) — 상수 `MODE_IDLE := 0`, `MODE_STAGE := 1`; `static func build(stage: int, mode: int) -> Array`. 각 원소는 `{"time": float, "kind": String, "side": int}`, `time` 오름차순. `MODE_IDLE`은 한 사이클(4마리, 면 0→3 순환)만 돌려주고 호출자가 반복한다. `MODE_STAGE`는 전체 웨이브 + 마지막 `epic_boss` 1마리.

- [ ] **Step 1: 실패하는 테스트 추가 — tests/run_tests.gd**

파일 상단 `const Balance` 아래에 추가:
```gdscript
const WaveDirector := preload("res://scripts/wave_director.gd")
```

`_init()`의 `test_balance_tables()` 다음 줄에 추가:
```gdscript
	test_wave_stage_ends_with_boss()
	test_wave_total_monotonic()
	test_wave_idle_cycle()
```

파일 끝에 추가:
```gdscript
func test_wave_stage_ends_with_boss() -> void:
	var ev := WaveDirector.build(1, WaveDirector.MODE_STAGE)
	check(ev.size() > 1, "stage schedule has events")
	check(ev[-1].kind == "epic_boss", "last event is epic_boss")
	for i in range(1, ev.size()):
		check(ev[i].time >= ev[i - 1].time, "events sorted at %d" % i)
	var bosses := ev.filter(func(e): return e.kind == "epic_boss").size()
	check(bosses == 1, "exactly one boss")
	for e in ev:
		check(e.side >= 0 and e.side <= 3, "side in range")


func test_wave_total_monotonic() -> void:
	var prev := 0
	for stage in range(1, 11):
		var n := WaveDirector.build(stage, WaveDirector.MODE_STAGE).size()
		check(n >= prev, "spawn count non-decreasing at stage %d" % stage)
		prev = n


func test_wave_idle_cycle() -> void:
	var ev := WaveDirector.build(1, WaveDirector.MODE_IDLE)
	check(ev.size() == 4, "idle cycle spawns 4")
	check(ev[0].time > 0.0, "first idle spawn is not at t=0")
	var sides: Array = ev.map(func(e): return e.side)
	check(sides == [0, 1, 2, 3], "idle sides rotate 0..3")
	for e in ev:
		check(e.kind == "grunt", "idle spawns grunts only")
```

- [ ] **Step 2: 테스트 실행 → 실패 확인**

Run:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd; echo "exit=$?"
```
Expected: `wave_director.gd` 없음 오류. `exit` 0이 아님.

- [ ] **Step 3: scripts/wave_director.gd 작성**

```gdscript
extends RefCounted
## 스폰 스케줄 생성. 씬 의존 없음.

const Balance := preload("res://scripts/balance.gd")

const MODE_IDLE := 0
const MODE_STAGE := 1


## 반환: [{time: float, kind: String, side: int}] 시간 오름차순.
## MODE_IDLE은 한 사이클(4마리)만. Spawner가 소진되면 다시 build()한다.
static func build(stage: int, mode: int) -> Array:
	var events: Array = []
	if mode == MODE_IDLE:
		var interval := Balance.idle_interval(stage)
		for side in 4:
			events.append({"time": interval * (side + 1), "kind": "grunt", "side": side})
		return events
	var t := 0.0
	for w in Balance.wave_count(stage):
		var size := Balance.wave_size(stage, w)
		for i in size:
			events.append({"time": t + i * Balance.SPAWN_SPACING_SEC, "kind": "grunt", "side": i % 4})
		t += size * Balance.SPAWN_SPACING_SEC + Balance.WAVE_GAP_SEC
	var rng := RandomNumberGenerator.new()
	rng.seed = stage
	events.append({"time": t, "kind": "epic_boss", "side": rng.randi_range(0, 3)})
	return events
```

- [ ] **Step 4: 테스트 실행 → 통과 확인**

Run:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd; echo "exit=$?"
```
Expected: `ALL PASSED`, `exit=0`.

- [ ] **Step 5: 커밋**

```bash
git add scripts/wave_director.gd tests/run_tests.gd
git commit -m "feat: wave director builds idle and stage spawn schedules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: GameState (모드·스테이지·HP, 오토로드)

**Files:**
- Modify: `scripts/game_state.gd` (스텁 교체)
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Consumes: `Balance.CASTLE_HP`, `gate_hp_max`, `hero_slots`, `COUNTDOWN_SEC`, `RESULT_SEC`
- Produces (오토로드 `GameState`, 또는 테스트에서 `preload("res://scripts/game_state.gd").new()`):
  - `enum Mode { IDLE, STAGE, COUNTDOWN, RESULT }`
  - 변수 `mode: int`, `stage: int`, `keep_level: int`, `gate_level: int`, `castle_hp: float`, `castle_hp_max: float`, `gate_hp: Array[float]`(크기 4), `gate_hp_max: float`, `stop_requested: bool`
  - 시그널 `mode_changed(mode: int)`, `stage_cleared(stage: int)`, `stage_failed(stage: int)`, `castle_hp_changed(hp: float, hp_max: float)`, `gate_hp_changed(side: int, hp: float, hp_max: float)`, `gate_broken(side: int)`, `refilled`
  - 메서드 `hero_count() -> int`, `start_stage()`, `stop_after_stage()`(토글), `damage_castle(amount: float)`, `damage_gate(side: int, amount: float)`, `is_gate_broken(side: int) -> bool`, `on_all_monsters_dead()`, `refill()`, `advance(delta: float)`, `countdown_left() -> float`
- 전이 규칙: `IDLE →start_stage→ STAGE`. `STAGE →on_all_monsters_dead→ RESULT(승, stage+1)`. `STAGE →castle_hp 0→ RESULT(패)`. `RESULT` 2초 후 `refill()` 다음 승이고 `stop_requested` 아니면 `COUNTDOWN`, 아니면 `IDLE`. `COUNTDOWN` 3초 후 `STAGE`. `IDLE`에서 castle_hp 0 → 즉시 `refill()`, 모드 유지.
- `start_stage()`는 시작 전에 `refill()`을 호출한다(방치 중 입은 피해·사망 영웅 초기화).

- [ ] **Step 1: 실패하는 테스트 추가 — tests/run_tests.gd**

상단 상수에 추가:
```gdscript
const GameStateScript := preload("res://scripts/game_state.gd")
```

`_init()` 호출 목록 끝에 추가:
```gdscript
	test_gamestate_win_loop()
	test_gamestate_fail_keeps_stage()
	test_gamestate_stop_after_stage()
	test_gamestate_gate_broken_once()
	test_gamestate_idle_castle_break_refills()
	test_gamestate_hero_count()
```

파일 끝에 추가:
```gdscript
func test_gamestate_win_loop() -> void:
	var gs = GameStateScript.new()
	var modes: Array = []
	gs.mode_changed.connect(func(m): modes.append(m))
	check(gs.mode == gs.Mode.IDLE, "starts idle")
	gs.start_stage()
	check(gs.mode == gs.Mode.STAGE, "stage after start")
	gs.on_all_monsters_dead()
	check(gs.stage == 2, "stage incremented on clear")
	check(gs.mode == gs.Mode.RESULT, "result after clear")
	gs.advance(Balance.RESULT_SEC + 0.01)
	check(gs.mode == gs.Mode.COUNTDOWN, "countdown after result")
	check(gs.countdown_left() > 2.9, "countdown starts near 3s")
	gs.advance(Balance.COUNTDOWN_SEC + 0.01)
	check(gs.mode == gs.Mode.STAGE, "stage after countdown")
	check(modes == [gs.Mode.STAGE, gs.Mode.RESULT, gs.Mode.COUNTDOWN, gs.Mode.STAGE], "transition order %s" % [modes])
	gs.free()


func test_gamestate_fail_keeps_stage() -> void:
	var gs = GameStateScript.new()
	var failed: Array = []
	gs.stage_failed.connect(func(s): failed.append(s))
	gs.stage = 5
	gs.start_stage()
	gs.damage_castle(Balance.CASTLE_HP + 1.0)
	check(gs.castle_hp == 0.0, "castle hp clamps at 0")
	check(gs.mode == gs.Mode.RESULT, "result after castle destroyed")
	check(failed == [5], "stage_failed emitted with stage 5")
	gs.damage_castle(50.0)
	check(gs.mode == gs.Mode.RESULT, "extra damage after destruction ignored")
	gs.advance(Balance.RESULT_SEC + 0.01)
	check(gs.mode == gs.Mode.IDLE, "idle after fail")
	check(gs.stage == 5, "stage kept on fail")
	check(gs.castle_hp == gs.castle_hp_max, "castle healed after fail")
	gs.free()


func test_gamestate_stop_after_stage() -> void:
	var gs = GameStateScript.new()
	gs.start_stage()
	gs.stop_after_stage()
	check(gs.stop_requested, "stop requested")
	gs.stop_after_stage()
	check(not gs.stop_requested, "stop toggled off")
	gs.stop_after_stage()
	gs.on_all_monsters_dead()
	gs.advance(Balance.RESULT_SEC + 0.01)
	check(gs.mode == gs.Mode.IDLE, "idle when stop requested after clear")
	check(gs.stage == 2, "stage still incremented")
	gs.free()


func test_gamestate_gate_broken_once() -> void:
	var gs = GameStateScript.new()
	var broken: Array = []
	gs.gate_broken.connect(func(s): broken.append(s))
	gs.damage_gate(2, gs.gate_hp_max * 0.5)
	check(not gs.is_gate_broken(2), "half damage does not break gate")
	gs.damage_gate(2, gs.gate_hp_max)
	gs.damage_gate(2, 10.0)
	check(gs.is_gate_broken(2), "gate broken")
	check(gs.gate_hp[2] == 0.0, "gate hp clamps at 0")
	check(broken == [2], "gate_broken emitted exactly once, got %s" % [broken])
	check(not gs.is_gate_broken(0), "other gates untouched")
	gs.refill()
	check(gs.gate_hp[2] == gs.gate_hp_max, "gate restored on refill")
	gs.free()


func test_gamestate_idle_castle_break_refills() -> void:
	var gs = GameStateScript.new()
	var refills := [0]
	gs.refilled.connect(func(): refills[0] += 1)
	gs.damage_gate(1, 9999.0)
	gs.damage_castle(9999.0)
	check(gs.mode == gs.Mode.IDLE, "idle mode kept")
	check(gs.castle_hp == gs.castle_hp_max, "castle healed immediately in idle")
	check(not gs.is_gate_broken(1), "gates restored in idle refill")
	check(refills[0] == 1, "refilled emitted once")
	gs.free()


func test_gamestate_hero_count() -> void:
	var gs = GameStateScript.new()
	check(gs.hero_count() == 4, "4 heroes at keep level 1")
	gs.keep_level = 2
	check(gs.hero_count() == 8, "8 heroes at keep level 2")
	gs.free()
```

- [ ] **Step 2: 테스트 실행 → 실패 확인**

Run:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd; echo "exit=$?"
```
Expected: `Invalid call. Nonexistent function 'start_stage'` 류 오류 또는 `FAIL:` 줄들. `exit` 0이 아님.

- [ ] **Step 3: scripts/game_state.gd 구현 (스텁 전체 교체)**

```gdscript
extends Node
## 게임 모드·스테이지·성/성문 HP의 단일 진실. 오토로드 GameState.
## 씬 의존 없음. 테스트에서 .new()로 단독 생성 가능.

const Balance := preload("res://scripts/balance.gd")

enum Mode { IDLE, STAGE, COUNTDOWN, RESULT }

signal mode_changed(mode: int)
signal stage_cleared(stage: int)
signal stage_failed(stage: int)
signal castle_hp_changed(hp: float, hp_max: float)
signal gate_hp_changed(side: int, hp: float, hp_max: float)
signal gate_broken(side: int)
signal refilled

var mode: int = Mode.IDLE
var stage: int = 1
var keep_level: int = 1
var gate_level: int = 1
var castle_hp_max: float = Balance.CASTLE_HP
var castle_hp: float = Balance.CASTLE_HP
var gate_hp_max: float = Balance.gate_hp_max(1)
var gate_hp: Array[float] = []
var stop_requested := false

var _timer := 0.0
var _won := false


func _init() -> void:
	refill()


func _process(delta: float) -> void:
	advance(delta)


func hero_count() -> int:
	return Balance.hero_slots(keep_level)


func start_stage() -> void:
	if mode != Mode.IDLE:
		push_warning("start_stage ignored in mode %d" % mode)
		return
	stop_requested = false
	refill()
	_set_mode(Mode.STAGE)


func stop_after_stage() -> void:
	stop_requested = not stop_requested


func damage_castle(amount: float) -> void:
	if castle_hp <= 0.0:
		return
	castle_hp = maxf(0.0, castle_hp - amount)
	castle_hp_changed.emit(castle_hp, castle_hp_max)
	if castle_hp == 0.0:
		_on_castle_destroyed()


func damage_gate(side: int, amount: float) -> void:
	if gate_hp[side] <= 0.0:
		return
	gate_hp[side] = maxf(0.0, gate_hp[side] - amount)
	gate_hp_changed.emit(side, gate_hp[side], gate_hp_max)
	if gate_hp[side] == 0.0:
		gate_broken.emit(side)


func is_gate_broken(side: int) -> bool:
	return gate_hp[side] <= 0.0


func on_all_monsters_dead() -> void:
	if mode != Mode.STAGE:
		return
	_won = true
	stage_cleared.emit(stage)
	stage += 1
	_set_mode(Mode.RESULT)


## 영웅·성문·성 HP 전부 초기화. 영웅/몬스터 노드는 refilled를 받아 스스로 리셋/제거.
func refill() -> void:
	castle_hp = castle_hp_max
	gate_hp_max = Balance.gate_hp_max(gate_level)
	gate_hp.resize(4)
	gate_hp.fill(gate_hp_max)
	castle_hp_changed.emit(castle_hp, castle_hp_max)
	for side in 4:
		gate_hp_changed.emit(side, gate_hp_max, gate_hp_max)
	refilled.emit()


func advance(delta: float) -> void:
	match mode:
		Mode.RESULT:
			_timer -= delta
			if _timer <= 0.0:
				refill()
				if _won and not stop_requested:
					_set_mode(Mode.COUNTDOWN)
				else:
					_set_mode(Mode.IDLE)
		Mode.COUNTDOWN:
			_timer -= delta
			if _timer <= 0.0:
				_set_mode(Mode.STAGE)


func countdown_left() -> float:
	return maxf(0.0, _timer)


func _on_castle_destroyed() -> void:
	if mode == Mode.STAGE:
		_won = false
		stage_failed.emit(stage)
		_set_mode(Mode.RESULT)
	else:
		refill()


func _set_mode(new_mode: int) -> void:
	mode = new_mode
	match mode:
		Mode.RESULT:
			_timer = Balance.RESULT_SEC
		Mode.COUNTDOWN:
			_timer = Balance.COUNTDOWN_SEC
	mode_changed.emit(mode)
```

- [ ] **Step 4: 테스트 실행 → 통과 확인**

Run:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd; echo "exit=$?"
```
Expected: `ALL PASSED`, `exit=0`.

- [ ] **Step 5: 오토로드 로드 스모크**

Run:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --quit-after 5 2>&1 | grep -E "SCRIPT ERROR|CastleRPG main ready"
```
Expected: `CastleRPG main ready` 출력, `SCRIPT ERROR` 없음.

- [ ] **Step 6: 커밋**

```bash
git add scripts/game_state.gd tests/run_tests.gd
git commit -m "feat: game state machine with stage flow, gate and castle hp

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Flat 헬퍼 + Castle + 월드 조립 + 스크린샷 플래그

**Files:**
- Create: `scripts/flat.gd`
- Create: `scripts/castle.gd`
- Modify: `scripts/main.gd` (임시본 전체 교체)

**Interfaces:**
- Consumes: `Balance.CASTLE_SIZE`, `GATE_STAND_OFFSET`, `SPAWN_DISTANCE`; `GameState.gate_hp_changed`
- Produces `Flat` (preload, static): 팔레트 상수 `GROUND`, `WALL`, `GATE`, `KEEP`, `HERO`, `HERO_SELECTED: Color`; `mesh(m: Mesh, color: Color) -> MeshInstance3D`, `box(size: Vector3, color: Color) -> MeshInstance3D`(바닥이 y=0에 닿게 y 오프셋), `capsule(radius: float, height: float, color: Color) -> MeshInstance3D`(동일)
- Produces `castle.gd`(Node3D): side 규약 `0=N(-z) 1=E(+x) 2=S(+z) 3=W(-x)`. 상수 `SIDE_DIR: Array[Vector3]`. 메서드 `gate_position(side: int) -> Vector3`, `gate_target(side: int) -> Vector3`(몬스터가 멈추는 성문 바깥 지점), `hero_stand_position(side: int, hero_index: int) -> Vector3`, `keep_position() -> Vector3`, `spawn_position(side: int) -> Vector3`(perp 방향 ±3 랜덤 지터). 성문 `Area3D`는 `collision_layer = 2`, 메타 `"side": int`
- Produces `main.gd`: `var camera: Camera3D`, `var castle`, `var heroes: Array`. 유저 인자 `--shot=SECONDS`(그 시각에 `res://tools/shot.png` 저장 후 종료), `--auto-stage`(`_ready` 끝에서 `GameState.start_stage()`)

- [ ] **Step 1: scripts/flat.gd 작성**

```gdscript
extends RefCounted
## 단색 플랫 메시 헬퍼와 팔레트. 모든 플레이스홀더 지오메트리는 여기로.

const GROUND := Color(0.72, 0.80, 0.62)
const WALL := Color(0.80, 0.78, 0.72)
const GATE := Color(0.55, 0.38, 0.22)
const KEEP := Color(0.62, 0.64, 0.72)
const HERO := Color(0.25, 0.55, 0.95)
const HERO_SELECTED := Color(1.0, 0.9, 0.2)


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

- [ ] **Step 2: scripts/castle.gd 작성**

```gdscript
extends Node3D
## 성벽 4면 + 성문 4개 + 중앙 성채. 성문 HP의 진실은 GameState. 여기는 시각화와 위치 제공만.
## side: 0=N(-z) 1=E(+x) 2=S(+z) 3=W(-x)

const Balance := preload("res://scripts/balance.gd")
const Flat := preload("res://scripts/flat.gd")

const SIDE_DIR: Array[Vector3] = [
	Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0),
]
const WALL_H := 1.5
const WALL_T := 0.6
const GATE_W := 2.0

var _gate_meshes: Array = []


func _ready() -> void:
	var half := Balance.CASTLE_SIZE / 2.0
	var seg_len := (Balance.CASTLE_SIZE - GATE_W) / 2.0
	for side in 4:
		var dir := SIDE_DIR[side]
		var perp := _perp(side)
		var center := dir * half
		for s in [-1.0, 1.0]:
			var seg := Flat.box(_wall_size(perp, seg_len), Flat.WALL)
			seg.position += center + perp * s * (GATE_W / 2.0 + seg_len / 2.0)
			add_child(seg)
		var gate := Flat.box(_wall_size(perp, GATE_W), Flat.GATE)
		gate.position += center
		add_child(gate)
		_gate_meshes.append(gate)
		var area := Area3D.new()
		area.collision_layer = 2
		area.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = _wall_size(perp, GATE_W) + Vector3(1.0, 1.0, 1.0)
		cs.shape = shape
		area.add_child(cs)
		area.position = center + Vector3(0, WALL_H / 2.0, 0)
		area.set_meta("side", side)
		add_child(area)
	add_child(Flat.box(Vector3(3, 3, 3), Flat.KEEP))
	GameState.gate_hp_changed.connect(_on_gate_hp_changed)


func gate_position(side: int) -> Vector3:
	return SIDE_DIR[side] * (Balance.CASTLE_SIZE / 2.0)


## 몬스터가 성문을 공격하려고 멈추는 지점 (성문 바로 바깥).
func gate_target(side: int) -> Vector3:
	return gate_position(side) + SIDE_DIR[side] * 0.8


## 성문 바깥 GATE_STAND_OFFSET 지점. 초기 배치는 영웅 i → 성문 i % 4 이므로
## 슬롯 = i / 4 (4명이면 전원 슬롯 0 = 성문 정면 중앙, 8·12명이면 좌우로 1.2씩).
## ponytail: 슬롯이 영웅 index 고정이라, 같은 슬롯 영웅 둘을 같은 성문으로 옮기면 겹친다. 겹침이 문제되면 성문별 점유 슬롯 배정으로 교체.
const STAND_SLOT_OFFSETS := [0.0, -1.2, 1.2]


func hero_stand_position(side: int, hero_index: int) -> Vector3:
	var slot := floori(hero_index / 4.0) % STAND_SLOT_OFFSETS.size()
	return gate_position(side) + SIDE_DIR[side] * Balance.GATE_STAND_OFFSET \
		+ _perp(side) * STAND_SLOT_OFFSETS[slot]


func keep_position() -> Vector3:
	return Vector3.ZERO


func spawn_position(side: int) -> Vector3:
	return SIDE_DIR[side] * Balance.SPAWN_DISTANCE + _perp(side) * randf_range(-3.0, 3.0)


func _perp(side: int) -> Vector3:
	var dir := SIDE_DIR[side]
	return Vector3(-dir.z, 0, dir.x)


func _wall_size(perp: Vector3, length: float) -> Vector3:
	if absf(perp.x) > 0.5:
		return Vector3(length, WALL_H, WALL_T)
	return Vector3(WALL_T, WALL_H, length)


func _on_gate_hp_changed(side: int, hp: float, hp_max: float) -> void:
	var mi: MeshInstance3D = _gate_meshes[side]
	mi.visible = hp > 0.0
	var mat := mi.material_override as StandardMaterial3D
	mat.albedo_color = Flat.GATE.darkened(0.6 * (1.0 - hp / hp_max))
```

- [ ] **Step 3: scripts/main.gd 전체 교체**

```gdscript
extends Node3D
## 월드 조립. 씬 파일은 이것 하나. 나머지는 코드로 생성.
## 개발용 유저 인자(-- 뒤): --shot=SECONDS  그 시각에 res://tools/shot.png 저장 후 종료
##                          --auto-stage    시작 즉시 스테이지 진행

const Balance := preload("res://scripts/balance.gd")
const Flat := preload("res://scripts/flat.gd")
const CastleScript := preload("res://scripts/castle.gd")

var camera: Camera3D
var castle
var heroes: Array = []

var _shot_at := -1.0
var _elapsed := 0.0


func _ready() -> void:
	_build_world()
	castle = CastleScript.new()
	add_child(castle)
	_apply_dev_args()


func _process(delta: float) -> void:
	if _shot_at < 0.0:
		return
	_elapsed += delta
	if _elapsed >= _shot_at:
		_shot_at = -1.0
		var err := get_viewport().get_texture().get_image().save_png("res://tools/shot.png")
		print("shot saved err=%d" % err)
		get_tree().quit()


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


func _apply_dev_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_at = float(arg.get_slice("=", 1))
		elif arg == "--auto-stage":
			GameState.start_stage()
```

- [ ] **Step 4: 헤드리스 스모크**

Run:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --quit-after 30 2>&1 | grep -c "SCRIPT ERROR"
```
Expected: `0`

- [ ] **Step 5: 스크린샷으로 육안 확인**

Run:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --path . --resolution 540x960 -- --shot=1.0 2>&1 | grep -E "shot saved|SCRIPT ERROR"; ls -la tools/shot.png
```
Expected: `shot saved err=0`, 파일 존재. Read 도구로 `tools/shot.png`를 열어 확인: 연한 배경, 초록 바닥, 중앙에 회색 성채 박스, 사각 성벽 4면, 각 면 중앙 갈색 성문, 45° 위에서 내려보는 아이소 구도. 성 전체가 화면 안에 들어오고 성 바깥에 여유 공간이 보여야 한다. 성이 잘리면 `camera.size`를 키운다.

- [ ] **Step 6: 커밋**

```bash
git add scripts/flat.gd scripts/castle.gd scripts/main.gd
git commit -m "feat: flat mesh helper, castle geometry, world setup with dev screenshot flag

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Hero + UnitPicker (탭 선택·성문 이동)

**Files:**
- Create: `scripts/hero.gd`
- Create: `scripts/unit_picker.gd`
- Modify: `scripts/main.gd`

**Interfaces:**
- Consumes: `Balance.HERO`, `castle.hero_stand_position(side, index)`, `GameState.refilled`, `GameState.hero_count()`, 그룹 `"monsters"`의 노드가 가진 `is_alive() -> bool`, `take_damage(amount: float)`(Task 6에서 구현. 그 전까지 그룹이 비어 있으니 호출되지 않음)
- Produces `hero.gd`(Node3D, 그룹 `"heroes"`): 변수 `castle`, `index: int`, `assigned_side: int`, `hp: float`, `state: int`, `selected: bool`(setter가 링 표시); `enum State { IDLE, MOVE, ATTACK, DEAD }`; 메서드 `reset()`, `stand_position() -> Vector3`, `move_to_side(side: int)`, `take_damage(amount: float)`, `is_alive() -> bool`. 탭 판정 `Area3D`는 `collision_layer = 4`(살아 있을 때) / `0`(사망), 메타 `"hero": self`
- Produces `unit_picker.gd`(Node): 변수 `camera: Camera3D`, `selected`. 좌클릭(터치 에뮬레이션 포함) 위치를 저장하고 `_physics_process`에서 레이캐스트. 영웅 히트 → 선택. 성문 히트 + 선택 영웅 살아 있음 → `move_to_side`. 그 외 → 선택 해제

- [ ] **Step 1: scripts/hero.gd 작성**

```gdscript
extends Node3D
## 영웅. 배정 성문 바깥 자리에서 사거리 내 몬스터 자동 공격. 사망 시 부활 없음, refilled에서만 복귀.

const Balance := preload("res://scripts/balance.gd")
const Flat := preload("res://scripts/flat.gd")

enum State { IDLE, MOVE, ATTACK, DEAD }

const SCAN_INTERVAL := 0.2

var castle
var index: int = 0
var assigned_side: int = 0
var hp: float = Balance.HERO.hp
var state: int = State.IDLE
var selected := false:
	set(v):
		selected = v
		if _ring != null:
			_ring.visible = v and state != State.DEAD

var _body: MeshInstance3D
var _ring: MeshInstance3D
var _area: Area3D
var _target
var _atk_cd := 0.0
var _scan_cd := 0.0


func _ready() -> void:
	add_to_group("heroes")
	_body = Flat.capsule(0.4, 1.4, Flat.HERO)
	add_child(_body)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.75
	_ring = Flat.mesh(torus, Flat.HERO_SELECTED)
	_ring.position.y = 0.05
	_ring.visible = false
	add_child(_ring)
	_area = Area3D.new()
	_area.collision_layer = 4
	_area.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.6
	shape.height = 1.6
	cs.shape = shape
	cs.position.y = 0.8
	_area.add_child(cs)
	_area.set_meta("hero", self)
	add_child(_area)
	GameState.refilled.connect(reset)
	reset()


func reset() -> void:
	hp = Balance.HERO.hp
	state = State.IDLE
	_target = null
	global_position = stand_position()
	_body.visible = true
	_area.collision_layer = 4
	_ring.visible = selected


func stand_position() -> Vector3:
	return castle.hero_stand_position(assigned_side, index)


func move_to_side(side: int) -> void:
	assigned_side = side
	if state != State.DEAD:
		state = State.MOVE


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
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = SCAN_INTERVAL
		_target = _nearest_monster()
	if _target != null and is_instance_valid(_target) and _target.is_alive():
		state = State.ATTACK
		if _atk_cd <= 0.0:
			_atk_cd = Balance.HERO.atk_interval
			_target.take_damage(Balance.HERO.atk)
		return
	_target = null
	var dest := stand_position()
	if global_position.distance_to(dest) > 0.05:
		state = State.MOVE
		global_position = global_position.move_toward(dest, Balance.HERO.speed * delta)
	else:
		state = State.IDLE


func _nearest_monster():
	var best = null
	var best_d: float = Balance.HERO.range
	for m in get_tree().get_nodes_in_group("monsters"):
		if not m.is_alive():
			continue
		var d: float = global_position.distance_to(m.global_position)
		if d <= best_d:
			best_d = d
			best = m
	return best
```

- [ ] **Step 2: scripts/unit_picker.gd 작성**

```gdscript
extends Node
## 탭 → 카메라 레이캐스트 → 영웅 선택 / 선택 영웅을 성문으로 이동.
## 터치는 프로젝트 기본값(emulate_mouse_from_touch)으로 마우스 이벤트가 되므로 마우스만 처리.

const LAYER_GATE := 2
const LAYER_HERO := 4

var camera: Camera3D
var selected

var _pending: Vector2 = Vector2.INF


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pending = event.position
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if _pending == Vector2.INF:
		return
	var hit := _pick(_pending)
	_pending = Vector2.INF
	if hit.is_empty():
		_select(null)
		return
	var area: Area3D = hit.collider
	if area.has_meta("hero"):
		_select(area.get_meta("hero"))
	elif area.has_meta("side") and selected != null and selected.is_alive():
		selected.move_to_side(area.get_meta("side"))
	else:
		_select(null)


func _pick(screen_pos: Vector2) -> Dictionary:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 200.0
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_GATE | LAYER_HERO)
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

- [ ] **Step 3: main.gd에 영웅·피커 추가**

상단 상수에 추가:
```gdscript
const HeroScript := preload("res://scripts/hero.gd")
const PickerScript := preload("res://scripts/unit_picker.gd")
```

`_ready()`를 다음으로 교체:
```gdscript
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
	_apply_dev_args()
```

- [ ] **Step 4: 헤드리스 스모크**

Run:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --quit-after 30 2>&1 | grep -c "SCRIPT ERROR"
```
Expected: `0`

- [ ] **Step 5: 스크린샷 확인**

Run:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --path . --resolution 540x960 -- --shot=1.0 2>&1 | grep -E "shot saved|SCRIPT ERROR"
```
Read `tools/shot.png`. Expected: 파란 캡슐 4개가 각 성문 바깥에 하나씩 서 있다. 선택 링은 보이지 않는다.

- [ ] **Step 6: 수동 확인 (창 실행)**

Run:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --path . --resolution 540x960
```
확인: 영웅 클릭 → 발밑 노란 링. 다른 성문 클릭 → 영웅이 그 성문으로 걸어감. 빈 곳 클릭 → 링 사라짐. 창을 닫아 종료. (에이전트 실행 환경에서 클릭이 불가능하면 이 단계는 건너뛰고 사용자에게 확인 요청으로 남긴다.)

- [ ] **Step 7: 커밋**

```bash
git add scripts/hero.gd scripts/unit_picker.gd scripts/main.gd
git commit -m "feat: heroes with auto-attack state machine and tap-to-place picker

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Monster + Spawner (방치 스폰, 전투 성립)

**Files:**
- Create: `scripts/monster.gd`
- Create: `scripts/spawner.gd`
- Modify: `scripts/main.gd`

**Interfaces:**
- Consumes: `Balance.MONSTER`, `hp_scale`, `atk_scale`, `MAX_LIVE_MONSTERS`; `WaveDirector.build`, `MODE_IDLE`, `MODE_STAGE`; `castle.spawn_position`, `gate_target`, `keep_position`; `GameState.is_gate_broken`, `damage_gate`, `damage_castle`, `on_all_monsters_dead`, `mode_changed`, `refilled`, `stage`, `mode`, `Mode`; 그룹 `"heroes"`의 `is_alive()`, `take_damage(amount)`
- Produces `monster.gd`(Node3D, 그룹 `"monsters"`): `signal died(monster)`; `setup(kind: String, side: int, stage: int, castle) -> void`(add_child 전에 호출); `is_alive() -> bool`; `take_damage(amount: float)`. refilled 수신 시 `_dead = true` 후 `queue_free`(died는 내지 않음)
- Produces `spawner.gd`(Node): 변수 `castle`. 부모 노드 아래에 몬스터를 add_child. 스테이지 스케줄 소진 + 살아 있는 몬스터 0 → `GameState.on_all_monsters_dead()`

- [ ] **Step 1: scripts/monster.gd 작성**

```gdscript
extends Node3D
## 괴물. 사거리 내 영웅 우선 공격, 없으면 목표 성문으로 직진. 성문이 부서졌으면 성채로 진입해 성 HP 공격.

const Balance := preload("res://scripts/balance.gd")
const Flat := preload("res://scripts/flat.gd")

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
	if _target_hero != null and _target_hero.is_alive():
		if _atk_cd <= 0.0:
			_atk_cd = _stats.atk_interval
			_target_hero.take_damage(atk)
		return
	_target_hero = null
	var broken: bool = GameState.is_gate_broken(side)
	var dest: Vector3 = castle.keep_position() if broken else castle.gate_target(side)
	if global_position.distance_to(dest) > _stats.range:
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
		if not h.is_alive():
			continue
		var d: float = global_position.distance_to(h.global_position)
		if d <= best_d:
			best_d = d
			best = h
	return best


## 리필로 제거될 때. died를 내지 않으므로 Spawner는 refilled에서 카운트를 0으로 맞춘다.
func _vanish() -> void:
	_dead = true
	queue_free()
```

- [ ] **Step 2: scripts/spawner.gd 작성**

```gdscript
extends Node
## WaveDirector 스케줄을 시간에 맞춰 소비해 몬스터를 부모 노드 아래에 생성. 전멸 감지.

const Balance := preload("res://scripts/balance.gd")
const WaveDirector := preload("res://scripts/wave_director.gd")
const MonsterScript := preload("res://scripts/monster.gd")

var castle

var _events: Array = []
var _cursor := 0
var _clock := 0.0
var _live := 0
var _stage_mode := false


func _ready() -> void:
	GameState.mode_changed.connect(_on_mode_changed)
	GameState.refilled.connect(_on_refilled)
	_on_mode_changed(GameState.mode)


func _process(delta: float) -> void:
	if _events.is_empty():
		return
	_clock += delta
	while _cursor < _events.size() and _events[_cursor].time <= _clock:
		if _live >= Balance.MAX_LIVE_MONSTERS:
			return  # 상한. 스케줄은 지연되고 다음 프레임에 재시도
		_spawn(_events[_cursor])
		_cursor += 1
	if _cursor < _events.size():
		return
	if _stage_mode:
		if _live == 0:
			_events = []
			GameState.on_all_monsters_dead()
	else:
		_load(WaveDirector.build(GameState.stage, WaveDirector.MODE_IDLE), false)


func _on_refilled() -> void:
	_live = 0


func _on_mode_changed(mode: int) -> void:
	if mode == GameState.Mode.IDLE:
		_load(WaveDirector.build(GameState.stage, WaveDirector.MODE_IDLE), false)
	elif mode == GameState.Mode.STAGE:
		_load(WaveDirector.build(GameState.stage, WaveDirector.MODE_STAGE), true)
	else:
		_events = []


func _load(events: Array, stage_mode: bool) -> void:
	_events = events
	_cursor = 0
	_clock = 0.0
	_stage_mode = stage_mode


func _spawn(ev: Dictionary) -> void:
	var m = MonsterScript.new()
	m.setup(ev.kind, ev.side, GameState.stage, castle)
	m.died.connect(_on_monster_died)
	get_parent().add_child(m)
	_live += 1


func _on_monster_died(_m) -> void:
	_live = maxi(0, _live - 1)
```

- [ ] **Step 3: main.gd에 스포너 추가**

상단 상수에 추가:
```gdscript
const SpawnerScript := preload("res://scripts/spawner.gd")
```

`_ready()`에서 `add_child(picker)` 다음, `_apply_dev_args()` 앞에 추가:
```gdscript
	var spawner = SpawnerScript.new()
	spawner.castle = castle
	add_child(spawner)
```

- [ ] **Step 4: 헤드리스 스모크 (방치 15초 + 스테이지 15초)**

Run:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --fixed-fps 60 --quit-after 900 2>&1 | grep -c "SCRIPT ERROR"
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --fixed-fps 60 --quit-after 900 -- --auto-stage 2>&1 | grep -c "SCRIPT ERROR"
```
Expected: 둘 다 `0`

- [ ] **Step 5: 스크린샷 확인 (방치 12초 시점)**

Run:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --path . --resolution 540x960 -- --shot=12.0 2>&1 | grep -E "shot saved|SCRIPT ERROR"
```
Read `tools/shot.png`. Expected: 빨간 캡슐 몬스터가 성 바깥에서 성문 쪽으로 접근 중이거나 성문 앞에 서 있다(방치 스폰은 4초마다 1마리, 12초면 최대 3마리). 영웅이 사거리 안 몬스터를 공격하므로 일부는 이미 죽어 없을 수 있다.

- [ ] **Step 6: 스크린샷 확인 (스테이지 6초 시점)**

Run:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --path . --resolution 540x960 -- --auto-stage --shot=6.0 2>&1 | grep -E "shot saved|SCRIPT ERROR"
```
Read `tools/shot.png`. Expected: 사방에서 여러 마리(첫 웨이브 8마리 중 다수)가 성문으로 몰려오는 장면.

- [ ] **Step 7: 커밋**

```bash
git add scripts/monster.gd scripts/spawner.gd scripts/main.gd
git commit -m "feat: monsters attack heroes, gates and keep; spawner drives wave schedules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: HUD + 엔드투엔드 스테이지 루프 검증

**Files:**
- Create: `scripts/hud.gd`
- Modify: `scripts/main.gd`
- Modify: `docs/superpowers/specs/2026-09-28-castlerpg-mvp-design.md` (실행 방법 1줄 추가)

**Interfaces:**
- Consumes: `GameState.mode_changed`, `castle_hp_changed`, `gate_hp_changed`, `stage_cleared`, `stage_failed`, `stage`, `mode`, `Mode`, `stop_requested`, `castle_hp`, `castle_hp_max`, `gate_hp`, `gate_hp_max`, `countdown_left()`, `start_stage()`, `stop_after_stage()`
- Produces `hud.gd`(CanvasLayer): 게임 오브젝트 참조 없음. 위: 스테이지 라벨, 성 HP 바, 성문 HP 바 4개(N E S W 순). 중앙: 카운트다운/배너. 아래: 버튼 하나

- [ ] **Step 1: scripts/hud.gd 작성**

```gdscript
extends CanvasLayer
## HUD. GameState 시그널만 구독. 게임 오브젝트 직접 참조 없음.

var _stage_label: Label
var _castle_bar: ProgressBar
var _gate_bars: Array = []
var _center: Label
var _button: Button


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 16
	root.add_child(top)
	_stage_label = Label.new()
	_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_label.add_theme_font_size_override("font_size", 36)
	top.add_child(_stage_label)
	_castle_bar = _bar(Color(0.95, 0.75, 0.2))
	top.add_child(_castle_bar)
	var gates := HBoxContainer.new()
	top.add_child(gates)
	for side in 4:
		var b := _bar(Color(0.55, 0.6, 0.7))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gates.add_child(b)
		_gate_bars.append(b)

	_center = Label.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_center.grow_vertical = Control.GROW_DIRECTION_BOTH
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.add_theme_font_size_override("font_size", 72)
	root.add_child(_center)

	_button = Button.new()
	_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_button.offset_left = 32
	_button.offset_right = -32
	_button.offset_top = -120
	_button.offset_bottom = -32
	_button.add_theme_font_size_override("font_size", 28)
	_button.pressed.connect(_on_button)
	root.add_child(_button)

	GameState.mode_changed.connect(_on_mode_changed)
	GameState.castle_hp_changed.connect(_on_castle_hp)
	GameState.gate_hp_changed.connect(_on_gate_hp)
	GameState.stage_cleared.connect(_on_cleared)
	GameState.stage_failed.connect(_on_failed)
	_on_castle_hp(GameState.castle_hp, GameState.castle_hp_max)
	for side in 4:
		_on_gate_hp(side, GameState.gate_hp[side], GameState.gate_hp_max)
	_on_mode_changed(GameState.mode)


func _process(_delta: float) -> void:
	if GameState.mode == GameState.Mode.COUNTDOWN:
		_center.text = str(ceili(GameState.countdown_left()))


func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(0, 18)
	b.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	b.add_theme_stylebox_override("fill", fill)
	return b


func _on_castle_hp(hp: float, hp_max: float) -> void:
	_castle_bar.max_value = hp_max
	_castle_bar.value = hp


func _on_gate_hp(side: int, hp: float, hp_max: float) -> void:
	_gate_bars[side].max_value = hp_max
	_gate_bars[side].value = hp


func _on_cleared(stage: int) -> void:
	_center.text = "스테이지 %d 클리어" % stage


func _on_failed(_stage: int) -> void:
	_center.text = "패배"


func _on_mode_changed(mode: int) -> void:
	_stage_label.text = "스테이지 %d" % GameState.stage
	if mode == GameState.Mode.IDLE or mode == GameState.Mode.STAGE:
		_center.text = ""
	_refresh_button()


func _refresh_button() -> void:
	if GameState.mode == GameState.Mode.IDLE:
		_button.text = "스테이지 진행"
		_button.disabled = false
	elif GameState.mode == GameState.Mode.RESULT:
		_button.disabled = true
	else:
		_button.text = "중지 예약됨 (취소)" if GameState.stop_requested else "이번 스테이지 후 중지"
		_button.disabled = false


func _on_button() -> void:
	if GameState.mode == GameState.Mode.IDLE:
		GameState.start_stage()
	else:
		GameState.stop_after_stage()
		_refresh_button()
```

- [ ] **Step 2: main.gd에 HUD 추가**

상단 상수에 추가:
```gdscript
const HudScript := preload("res://scripts/hud.gd")
```

`_ready()`에서 `add_child(spawner)` 다음, `_apply_dev_args()` 앞에 추가:
```gdscript
	add_child(HudScript.new())
```

- [ ] **Step 3: 헤드리스 엔드투엔드 스모크 (스테이지 1 클리어까지 충분한 시간)**

스테이지 1 스케줄: 웨이브 3개 × 8마리, 웨이브 간 8초, 보스까지 약 36초 + 전투. 90초 시뮬레이션.

Run:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --fixed-fps 60 --quit-after 5400 -- --auto-stage 2>&1 | grep -cE "SCRIPT ERROR|ERROR"
```
Expected: `0`

- [ ] **Step 4: 스테이지 전이 로그로 확인**

`scripts/main.gd`의 `_apply_dev_args()` 끝에 임시가 아닌 개발 로그를 추가한다(항상 켜져 있어도 무해):
```gdscript
	GameState.mode_changed.connect(func(m): print("[mode] %d stage=%d" % [m, GameState.stage]))
	GameState.stage_cleared.connect(func(s): print("[cleared] %d" % s))
	GameState.stage_failed.connect(func(s): print("[failed] %d" % s))
```

Run:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --fixed-fps 60 --quit-after 5400 -- --auto-stage 2>&1 | grep -E "^\[(mode|cleared|failed)\]"
```
Expected: `[mode] 1 stage=1` 다음 `[cleared] 1` 또는 `[failed] 1`, 이어서 `[mode] 3 ...`(RESULT) → `[mode] 2 ...`(COUNTDOWN, 승리 시) → `[mode] 1 stage=2`. 헤드리스 자동 진행은 영웅을 움직이지 않으므로 스테이지 1은 성문마다 영웅 1명이 혼자 막아 클리어돼야 한다. `[failed] 1`이 나오면 먼저 원인을 로그로 확인한다(어느 성문이 뚫렸는지, 보스가 영웅을 이겼는지 — 필요하면 임시 print 추가 후 제거). 원인이 밸런스면 `balance.gd`의 `epic_boss` 수치나 `HERO` 수치를 조정해 스테이지 1이 클리어되게 하고, 바꾼 값을 spec §6에 같은 커밋으로 반영한다. 원인이 로직 버그면 버그를 고친다. `[cleared] 1` 다음 `[mode] 1 stage=2`가 보여야 통과.

- [ ] **Step 5: 스크린샷 확인 (HUD)**

Run:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --path . --resolution 540x960 -- --shot=1.0 2>&1 | grep -E "shot saved|SCRIPT ERROR"
```
Read `tools/shot.png`. Expected: 상단 "스테이지 1" 라벨, 노란 성 HP 바, 회청색 성문 바 4개, 하단 "스테이지 진행" 버튼. 한글이 네모로 보이면 시스템 폰트 폴백 실패이므로 사용자에게 알리고 다음 서브프로젝트(UI)에서 Noto Sans KR을 넣는다. 게임 로직 완료 기준에는 영향 없음.

- [ ] **Step 6: 스크린샷 확인 (카운트다운 또는 결과 배너)**

Run:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --path . --resolution 540x960 --fixed-fps 60 -- --auto-stage --shot=60.0 2>&1 | grep -E "shot saved|SCRIPT ERROR|^\[(mode|cleared|failed)\]"
```
로그로 클리어 시각을 보고 `--shot=` 값을 클리어 직후(배너 2초 구간) 또는 카운트다운 구간으로 맞춰 다시 실행. Read `tools/shot.png`. Expected: 중앙에 "스테이지 1 클리어" 또는 큰 숫자 3/2/1, 라벨 "스테이지 2", 버튼 "이번 스테이지 후 중지".

- [ ] **Step 7: 테스트 전체 재실행**

Run:
```bash
./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd; echo "exit=$?"
```
Expected: `ALL PASSED`, `exit=0`

- [ ] **Step 8: spec에 실행 방법 추가**

`docs/superpowers/specs/2026-09-28-castlerpg-mvp-design.md`의 "## 9. 테스트" 섹션 끝에 추가:
```markdown
- 실행 방법: 프로젝트 루트에서 `./tools/Godot_v4.7.2-stable_win64_console.exe --path .` (창 실행), 에디터는 `--editor` 추가. 개발 플래그는 `--` 뒤에 `--shot=SECONDS`, `--auto-stage`
```

- [ ] **Step 9: 커밋**

```bash
git add scripts/hud.gd scripts/main.gd scripts/balance.gd docs/superpowers/specs/2026-09-28-castlerpg-mvp-design.md
git commit -m "feat: HUD with hp bars, stage button, countdown and result banner

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 10: 완료 기준 점검 (spec §10)**

- 테스트·스모크 통과 (Step 3, 7)
- 스테이지 1→2 연속 진행 로그 확인 (Step 4)
- 패배→방치 복귀: `balance.gd`에서 임시로 `HERO.atk`를 1.0으로 바꾸고 Step 4 명령 재실행 → `[failed] 1` 다음 `[mode] 3` → `[mode] 0 stage=1` 확인 후 값 되돌리기. 되돌린 뒤 `git diff --stat`이 비어 있어야 한다
- 세로·Compatibility 설정: `grep -E "gl_compatibility|viewport_width=720|orientation=1" project.godot` 3줄
- 스크립트 수: `ls scripts/*.gd | wc -l` → 12 이하

---

## 자체 검토 결과

- **Spec 커버리지:** §2 포함 항목 전부 태스크에 대응. 카메라·세로(T4), 성문 4개 HP·성 HP·파괴 시 진입(T3·T6), 영웅 4명·탭 배치·자동 공격·부활 없음(T5), 방치 스폰(T6), 스테이지 웨이브·보스(T2·T6), 리필·카운트다운·자동 연쇄·중지 토글·패배 복귀(T3·T7), HUD(T7), 헤드리스 테스트(T1~T3), 스모크(T4~T7). §8 성능: 상한 120(T6), 탐색 0.2초(T5·T6), 물리 없음(전체), 그림자 끔(T4)
- **플레이스홀더:** 없음. 모든 코드 스텝에 전체 코드 포함
- **타입·이름 일관성:** `castle.hero_stand_position(side, index)` T4 정의 → T5 사용. `gate_target`, `keep_position`, `spawn_position` T4 → T6. `is_alive`/`take_damage` 영웅·몬스터 양쪽 동일 시그니처. `GameState.Mode` 비교는 전부 `if/elif`. `WaveDirector.MODE_IDLE/MODE_STAGE` T2 → T6. 이벤트 키 `time/kind/side` T2 → T6
- **알려진 한계(의도):** 영웅 8명 이상일 때 자리 겹침(`ponytail:` 주석). 한글 폰트는 시스템 폴백 의존. 세이브 없음

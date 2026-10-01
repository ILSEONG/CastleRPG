# 작업 B1 보고 — 건물 레벨업: 데이터·서버·앱 상태·효과

- 워크트리: `C:\CastleRPG\.claude\worktrees\agent-ac291fdef5dd54deb`, 브랜치 `worktree-agent-ac291fdef5dd54deb`
- main `14af22f`을 이 브랜치에 병합해 두었다 — main으로 충돌 없이 합칠 수 있다.
- 상태: 완료. 로직·입력·AI·E2E·서버·통합 전부 통과(병합 뒤 다시 돌림).
- 공유 경로(`C:\CastleRPG\.superpowers\...`)는 워크트리 격리로 쓸 수 없어 워크트리 안 같은 상대 경로에 썼다(커밋 포함).

## 커밋

| 커밋 | 내용 |
|---|---|
| a5b4e23 | 서버: 007, building_defs 시드, 게으른 완료, `POST /v1/building/upgrade`, 플레이어 응답 buildings·build, gamedata buildings, 주점 확률·성채 단계 슬롯, `POST /v1/test/build_now`, 서버 테스트 |
| dff2756 | 컨트롤러 지시 반영: 민가 = 인구(`pop_base` 6 + `pop_per_house` 2 × (L−1)), `player.population`, 축적 상한은 `accum_cap_min` 고정 |
| 6fd6f13 | 앱: GameData 건물 표·단계 표·효과 공식, Economy 건물 상태·업그레이드·save v4, GameState 성/성문 HP·슬롯, 영웅 막사·연구소 곱, 주점 모집 확률, main 월드 다시 만들기, 로직 테스트 |
| 36c2686 | AI 체크: 막사·연구소 반영, 성문 HP, 성채 단계 → 월드 다시 만들기(오토로드 상태 유지) |
| 335b370 | 통합 체크: 서버 업그레이드 → build_now → 완료 → 재접속 복원, 재전송 금지, 409 알림, 자동 수집 |
| 0d96af2 | server/README API 문서 |
| 3206891 | main 병합(Q·개정 12-2). 충돌 6개 해결 — 아래 "병합" |

## 1. 데이터

- `data/buildings.csv`(스펙 §2.2 표 그대로) + `.import`(keep). 서버 `building_defs`(마이그레이션 007, 시드 TABLES에 추가, gamedata `buildings`).
- `data/config.csv`: `hero_slots` 삭제. 추가 9개 — `castle_hp_per_level`(200), `keep_slot_tiers`(`1:4|5:8|10:12`), `keep_interior_tiers`(`1:20|5:24|10:28`), `pop_base`(6), `pop_per_house`(2), `barracks_hp_per_level`(0.03), `lab_atk_per_level`(0.03), `tavern_ssr_per_level`(0.001), `tavern_sr_per_level`(0.003). (`accum_cap_per_house`는 지시대로 넣지 않음.) Q 병합 뒤 config는 40키.
- `Balance.INTERIOR_TILES`·`Balance.interior_half` 삭제 → `GameData.interior_tiles/interior_half(keep_level)`(단계 표). 호출부(castle.gd, run_tests) 전부 바꿈. 같은 값이 두 곳에 없다.
- 검증(앱 GameData `_check_buildings` = 서버 `seed.checkBuildings`): 최대 레벨 ≥ 1 정수, 비용 0 이상 정수, base_sec > 0, req1·req2는 표 안, keep·gate 필수, 자원 건물은 건물 표에, 비용 자원(wood·stone·food)은 자원 표에, 효과 설정 ≥ 0(주점 증가분 ≤ 1, 인구는 정수), 단계 표 `레벨:값|…`(1부터 오름차순, 값 정수 ≥ 1). 앱만: 배치(Balance.BUILDINGS)에 없는 건물(성문 제외) 거부, 성 내부 20타일 미만 거부.
- 비용·시간: `round(값 × 1.35^(L−1))`, `round(base_sec × 1.5^(L−1))`. 서버·앱 모두 거듭제곱을 **곱셈 n번**으로 계산(`grown`/`_grown`) — JS와 Godot의 pow 구현 차이로 .5 경계 반올림이 갈리지 않게. 같은 표를 양쪽 테스트가 확인(성채 10→11 = 4468/4468/2979·2307초, 성문 2→3 = 337.5→338·67.5→68 등).

## 2. 서버

- 007: `building_defs`(ord 포함), `player_state.build_id text`, `build_finish timestamptz`, 기존 플레이어 keep/gate 행 = keep_level/gate_level. 나머지 건물 행은 요청 때(`ENSURE_ROWS_SQL`) 레벨 1로, keep/gate는 player_state 레벨로 채운다(시드 전이어도 안전). 새 플레이어는 로그인 때 모든 건물 행.
- 게으른 완료: `loadPlayer`(모든 플레이어 요청이 지남)에서 `build_finish ≤ now`면 `COMPLETE_SQL` 한 문장(version 가드 + build_id 가드): 레벨 +1, keep/gate면 player_state 레벨도, 일꾼 비움, economy_log `build_done`(`{building, from, to, finish}`). 지면 다시 읽는다.
- `POST /v1/building/upgrade {building}`: 400 `unknown_building` → 409 `max_level` → `keep_cap` → `prereq` → `builder_busy` → `not_enough`(rules.upgradeBlock). 자원 건물은 먼저 collectStep(남은 초 유지)으로 자동 수집하고 그 양까지 비용에 쓴다. 수집·차감·일꾼·로그(`build_start`)는 commit 한 문장(version 가드). 응답 = 플레이어 응답 + `build: {id, finish}`.
- 플레이어 응답 추가: `player.buildings`(건물 표 전부 `{level}`, 자원 건물은 `last_collect`도), `player.build`(`{id, finish}`|null), `player.population`. `keep_level`·`gate_level`은 유지(완료 때 같이 오름).
- 효과: `heroSlots` = `keep_slot_tiers`(배치 길이 확장은 view의 null 채우기 + /v1/deploy 길이 검사), 모집 확률 `gachaRates(config, 주점)`, 인구 `population(config, 민가)`.
- `POST /v1/test/build_now`(ALLOW_TEST_HOOKS만): 진행 중 건설의 finish = 지금, 같은 응답이 완료를 반영.
- 테스트 `server/test/buildings.test.ts`(14건): 공식, 단계 표, 검사 순서, 새 플레이어·중복 409, 게으른 완료(시계 주입, 다른 요청도 완료), 자동 수집, 선행·상한·최대, 원자성 2건(업그레이드 경합, 완료 경합), 주점·민가(인구) 효과, 배치 길이 확장(실제 업그레이드 + build_now), build_now 404/401, 007 업그레이드, 시드 검증 14가지. 서버 78건 통과.

## 3. 앱 상태 — UI(B2)용 API (전부 `Economy` 한 곳)

### 상태·시그널

```gdscript
var levels: Dictionary          # 건물 id → 레벨(건물 표 9개 전부)
var build: Dictionary           # 일꾼 {id: String, finish: float(유닉스 초, 보정 시각)}, 쉬면 {}
signal build_started(building_id: String, finish: float)   # 건설 시작(온라인은 응답이 왔을 때)
signal building_done(building_id: String, level: int)      # 건설 완료(새 레벨). 온라인은 서버 응답에서 레벨이 오른 걸 봤을 때(첫 접속 반영은 제외)
signal changed / signal notice(text: String)               # 기존 — 자원·레벨·일꾼이 바뀌면 changed, 거부 이유는 notice
const BLOCK_TEXT := {...}       # 이유 코드 → 문구
const BUILD_FAIL_TEXT := "건설 결과를 받지 못했습니다 — 건물 상태를 다시 확인합니다"
```

### 함수

```gdscript
func building_level(id: String) -> int
func upgrade_block(id: String, now: float) -> String    # "" = 가능. now = Economy.time_now(). 자원 건물은 자동 수집분(pending)까지 본다
func upgrade_cost(id: String) -> Dictionary             # 다음 레벨 {wood, stone, food}(최대면 {})
func upgrade_sec(id: String) -> int                     # 다음 레벨 건설 시간(초, 최대면 0)
func requirements(id: String) -> Array                  # [{id, need, have, ok}] — 성채가 아니면 성채 상한(need = 목표 레벨) 먼저, 그다음 req1·req2(need = 목표 − 1). 최대면 []
func upgrade(id: String, now: float) -> bool            # 시작(오프라인 즉시 차감·자동 수집·저장 / 온라인 once 요청). 안 되면 notice만
func is_building(id: String) -> bool
func build_left(now: float) -> float                    # 남은 초(쉬면 0)
func build_progress(now: float) -> float                # 0..1(전체 = 지금 레벨의 건설 시간)
func population() -> int                                # 민가 인구(6 + 2 × (L−1))
func gacha_rates() -> Dictionary                        # {ssr, sr} 주점 반영
func complete_due(now: float) -> void                   # 게으른 완료(_process가 매 프레임 부른다 — UI는 안 불러도 된다)
func finish_build_now() -> void                         # 테스트 훅: 오프라인은 지금 완료, 온라인은 POST /v1/test/build_now
static func upgrade_block_for(id, levels, build_id, have) -> String   # 같은 판단의 순수 함수(테스트용)
```

### 불가 이유 코드(검사 순서)

| 코드 | 뜻 | BLOCK_TEXT |
|---|---|---|
| `unknown` | 표에 없는 건물 | 알 수 없는 건물 |
| `max_level` | 최대 레벨 | 최대 레벨 |
| `keep_cap` | 성채 제외, 목표 레벨 > 성채 레벨 | 성채 레벨이 부족합니다 |
| `prereq` | req1·req2 레벨 < 목표 − 1 | 선행 조건 미충족 |
| `in_progress` | 바로 이 건물을 짓는 중(앱만) | 건설 중 |
| `builder_busy` | 다른 건물을 짓는 중 | 다른 건물 건설 중 |
| `not_enough` | 자원 부족 | 자원 부족 |
| `waiting` | 온라인 응답 대기(앱만) | 응답 대기 중 |

서버 409 코드(`max_level`·`keep_cap`·`prereq`·`builder_busy`·`not_enough`)는 같은 이름이라 실패 알림이 `BLOCK_TEXT[net.last_error]`로 나온다(`unknown_building`·연결 실패는 BUILD_FAIL_TEXT).

### 그 밖의 공용 함수

- GameData(정적): `buildings()`, `building_def(id)`, `build_cost(id, level)`, `build_sec(id, level)`, `parse_tiers(s)`, `tier_value(key, level)`, `hero_slots(keep)`, `interior_tiles(keep)`, `interior_half(keep)`, `castle_hp_max(keep)`, `gate_hp_max(gate)`, `population(houses)`, `barracks_hp_bonus(L)`, `lab_atk_bonus(L)`, `gacha_rates(tavern)`, `hero_stats(def, level, copies, buildings := {})`, `hero_power(def, level, copies, buildings := {})`. 상수 `KEEP·GATE·BARRACKS·LAB·HOUSES·TAVERN`, `BUILD_RES`.
- GameState: `building_level(id)`, `building_levels()`, `apply_levels()`, `hero_count()`(성채 단계).

### 동작 규칙

- 오프라인 save v4: `levels`(9개)·`build`(`{id, finish}`|null). v3 → v4: 자원 건물 레벨은 그대로, 나머지(keep·gate 포함) 1, 일꾼 없음. (스펙의 "keep/gate는 GameState 값" — 오프라인 GameState.keep_level/gate_level은 저장된 적이 없어 늘 1이라 같은 결과.) 불러올 때 꺼진 동안 끝난 건설을 완료한다.
- 온라인: 상태는 apply_server(`buildings` 전부·`build`)로만. 업그레이드는 once(재전송 금지) — 실패면 알림 + `/v1/player`. 끝나는 시각(보정 시각)이 지나면 2초마다 `/v1/player`로 서버 완료를 받는다.
- `Net._on_first_player`는 더 이상 GameState.keep_level/gate_level을 쓰지 않는다(GameState가 roster=Economy에서 읽는다).

## 4. 효과 연결

- 성 HP = 1000 + 200 × (성채 − 1), 성문 HP = 400 × 성문(GameState.refill. 완료 때 `apply_levels`가 최대·현재 HP를 늘어난 만큼 올림, 부서진 성문은 그대로).
- 영웅 HP × (1 + 막사 보너스), 공격 × (1 + 연구소 보너스): `GameData.hero_stats`의 곱 하나(hero.gd·hero_panel 전투력·상세 수치가 같은 함수). main `_slots` key에 막사·연구소 레벨 — 방치면 곧바로 다시 만들고, 아니면 다음 리필.
- 모집 확률(오프라인 roll_gacha·모집 창 확률 줄), 인구(`population()`, 병사는 다음 개정).
- 성채 단계: `_on_building_done("keep")`에서 성 내부·슬롯 수가 지금 월드와 다르면 — 방치면 곧바로 월드를 다시 만들고 새 HUD에 "성이 넓어졌습니다!", 아니면 지금 알리고 방치로 돌아올 때 다시 만든다. 다시 만들기 = `reload_current_scene()`(main이 현재 씬일 때), 테스트 하네스처럼 자식이면 같은 자리에 새 인스턴스. 개발용 1회 설정(econ-demo·--heroes·auto-stage·dev 로그)은 첫 월드에서만(`main.rebuilds`).

## 5. 검증

- 서버 `npm --prefix server test` 78/78, 로직 ALL PASSED, 입력 INPUT ALL PASSED, AI AI ALL PASSED(B 사례 11개), E2E `[cleared] 1` → `[mode] 1 stage=2`, 통합 ONLINE ALL PASSED(r·s·t·u·p2). 8790 리슨 없음 확인.
- 증명(깨서 실패 확인 후 복구): 서버 keep_cap 제거 → 3건 실패, prereq 완화 → 2건, builder_busy 제거 → 3건(원자성 포함), commit version 가드 제거 → 업그레이드 원자성 1건, 완료 가드 제거 → 완료 원자성 1건. 앱 keep_cap → 2건, prereq·builder → 5건. 전부 복구, 트리 깨끗.

## 6. 병합(main `14af22f`)

충돌 6개 — 모두 인접 줄: config 키 목록(app·server: Q의 식량 키 삭제 + 이 작업의 hero_slots 삭제·건물 키), gamedata config 수(40), main.gd 상수, run_tests/ai_check 호출 목록과 끝에 붙인 함수(둘 다 유지, 건물 AI 사례는 월드를 다시 만들어 마지막). 병합 뒤 전체 다시 통과.

## 7. 우려·다음 작업에 넘길 것

- 개정 13(main에 있는 soldiers 스펙)은 막사의 영웅 HP 보너스를 없앤다: `GameData.hero_stats`의 막사 곱, `barracks_hp_per_level` 키(config·`BUILDING_NUM_KEYS`·서버 `CONFIG_BUILDING_NUM`), main `_slots` key의 막사 레벨만 지우면 된다. 인구 이름(`pop_base`·`pop_per_house`·`player.population`·`population()`)과 save v4 → v5 흐름은 개정 13과 맞다.
- 건물 이름은 `buildings.csv`의 name과 `Balance.BUILDINGS`의 name 두 곳에 있다(이름표는 아직 Balance 값). B2가 이름표 "벌목장 Lv 3"을 만들 때 `GameData.building_def(id).name` 하나로 모으는 게 좋다.
- 모집 창 확률 줄은 열 때마다 갱신(`_on_open`). 건물 창·[성] 탭·비계·완료 알림 "벌목장 Lv 4 완료"는 B2 몫 — `building_done`을 받아 띄우면 된다(Economy는 완료 알림을 내지 않는다).
- 성채 단계를 넘어 월드를 다시 만들 때 HUD 상태(열린 창 등)는 새로 시작한다. 오토로드(Economy·GameState·Net) 상태는 AI 체크로 유지 확인.
- Neon: 007 마이그레이션 + 시드(건물 표, `hero_slots` 삭제, 새 설정 9개)를 새 서버와 함께 올려야 한다(컨트롤러 몫, 접속 안 함).

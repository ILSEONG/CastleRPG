# CastleRPG MVP 설계 (서브프로젝트 1: 코어 루프)

작성일: 2026-09-28
엔진: Godot 4.7.2 stable (GDScript). 실행 파일은 `tools/`에 두고 git에서 제외한다.
출시 타깃: 모바일(Android 우선, iOS 후속). 개발·테스트는 Windows 데스크톱에서 한다.

## 1. 목표

성 방어 방치형 게임의 코어 루프 하나를 끝까지 돌아가게 만든다.
영웅을 성문에 배치하고, 괴물이 밀려오고, 스테이지를 밀면 보스가 나오고, 클리어하면 리셋 후 다음 스테이지로 이어진다.
그래픽은 단색 플랫 플레이스홀더로 한다. 이후 서브프로젝트에서 건물·병사·챕터·에셋을 얹는다.

## 2. 범위

### 포함
- 3D 아이소메트릭 고정 카메라(직교 투영), 세로 화면(9:16)
- 성: 정사각 성벽 4면, 각 면 중앙에 성문 1개(북·동·남·서). 성문마다 HP, 성 자체 HP. 성 HP 0 = 패배. 다른 건물은 HP 없음
- 성문 파괴 → 그 면 괴물이 성 안으로 들어와 성(중앙 성채)을 직접 공격
- 영웅 수는 성채 레벨 표 `[4, 8, 12]`로 결정. MVP는 성채 레벨 1 고정 → 4명. 탭으로 선택, 성문 탭으로 이동 배치. 자동 공격
- 영웅 사망 시 부활 없음. 리필 이벤트까지 사망 상태 유지
- 방치 모드: 사방에서 약한 괴물이 일정 간격으로 계속 스폰
- 스테이지 모드: 웨이브가 강해지고 마지막에 에픽 보스 등장
- 클리어 → 리필 → 3초 카운트 → 다음 스테이지 자동 시작
- 리필 = 영웅 전원 부활·HP 전회복·자리 복귀, 성문 HP 전회복, 성 HP 전회복, 남은 괴물 제거. 발생 시점: 방치→스테이지 시작, 클리어, 패배, 방치 중 성 HP 0
- 패배(성 HP 0) → 방치 모드 복귀, 스테이지 번호 유지(재도전)
- HUD: 스테이지 번호, 성 HP 바, 스테이지 진행/중지 버튼, 카운트다운, 결과 배너
- 순수 로직 헤드리스 테스트 1개 파일

### 제외 (이후 서브프로젝트)
- 성 내부 영역, 건물 8종, 자원, 업그레이드, 성채 레벨
- 병사, 성벽 위/성문 밖 전술 배치
- 챕터, 레전드 보스
- 세이브/로드, 오프라인 방치 보상
- CC0 에셋(KayKit/Kenney) 교체, 완더버그 스타일 UI 폴리시
- Android/iOS 익스포트 템플릿 설정 (프로젝트 설정만 모바일 기준으로 맞춘다)

## 3. 핵심 결정

| 항목 | 결정 | 이유 |
|---|---|---|
| 렌더러 | Compatibility (OpenGL ES 3) | 저사양 안드로이드까지 커버, 웹 익스포트 가능, 플랫 셰이딩에 충분 |
| 화면 | 세로 720×1280, stretch `canvas_items`, aspect `expand` | 모바일 방치형 표준. 성이 정사각형이라 세로에 잘 맞음 |
| 입력 | `emulate_mouse_from_touch` 기본값 유지, 마우스 이벤트 하나로 처리 | 데스크톱·모바일 코드 경로 하나 |
| 유닛 구조 | `Node3D` + 소형 상태머신, 이동은 `global_position` 보간 (접근 A) | 물리 바디 불필요. 수백 유닛까지 충분. 코드 최소 |
| 탭 판정 | 영웅·성문에만 `Area3D` (레이어 3·2), 카메라 레이캐스트 | 몬스터·바닥은 판정 대상 아님 |
| 길찾기 | 네브메시 없음. 괴물은 가장 가까운 성문으로 직진 | 사방에서 직진 진입하는 구조라 필요 없음 |
| 데이터 | 밸런스 상수는 `scripts/balance.gd` 한 파일 | 튠 노브를 한 곳에 |
| 테스트 | `godot --headless -s tests/run_tests.gd` | 프레임워크 없음. 순수 로직만 assert |

## 4. 구조

```
project.godot
scenes/
  main.tscn        # 유일한 씬. Node3D + main.gd. 나머지 오브젝트는 전부 코드로 생성
scripts/
  main.gd          # 카메라, 조명, 바닥, Castle, 영웅, Spawner, Picker, HUD 생성. 개발용 --shot/--auto-stage 플래그
  flat.gd          # 단색 플랫 메시 헬퍼 (box, capsule, mesh) + 팔레트 상수
  game_state.gd    # 오토로드. 모드·스테이지·성 HP·시그널
  balance.gd       # 상수 및 스케일 함수
  wave_director.gd # RefCounted. 스폰 스케줄 생성 (순수 로직)
  spawner.gd       # WaveDirector 스케줄을 시간에 맞춰 실행, 몬스터 인스턴스화
  castle.gd        # 성문 위치 제공, 피격
  hero.gd
  monster.gd
  unit_picker.gd   # 탭 → 레이캐스트 → 영웅 선택 / 성문 지정
  hud.gd
tests/
  run_tests.gd     # SceneTree 확장, assert, 종료 코드 반환
```

### 4.1 GameState (오토로드)
- `mode`: `IDLE | STAGE | COUNTDOWN | RESULT`
- `stage: int` (1부터), `castle_hp`, `castle_hp_max`
- 시그널: `mode_changed(mode)`, `stage_cleared(stage)`, `stage_failed(stage)`, `castle_hp_changed(hp, max)`
- `keep_level: int` (MVP 고정 1), `gate_hp: Array[float]` 크기 4, `gate_hp_max`
- 시그널 추가: `gate_hp_changed(side, hp, max)`, `gate_broken(side)`, `refilled`
- 메서드: `start_stage()`, `stop_after_stage()`, `damage_castle(amount)`, `damage_gate(side, amount)`, `on_all_monsters_dead()`, `refill()`, `advance(delta)`, `hero_count() -> int`
- `damage_gate`는 HP 0 도달 시 `gate_broken(side)`를 한 번만 낸다. 파괴된 성문에 추가 피해는 무시
- `refill()`은 영웅·성문·성 HP를 전부 초기화하고 `refilled`를 낸다. 영웅·몬스터 노드는 이 시그널을 받아 스스로 리셋/제거한다
- 카운트다운·결과 배너 시간은 `Timer` 노드 대신 `advance(delta)` 누적으로 진행한다. `_process`가 `advance`를 호출한다. 테스트에서 `advance(3.0)`으로 전이를 검증하기 위함
- 씬 의존 없음. `load("res://scripts/game_state.gd").new()`로 단독 인스턴스화 가능해야 한다
- 전이:
  - `IDLE` → 버튼 → `STAGE`
  - `STAGE` → 보스 포함 전멸 → `RESULT`(승) → 리셋 → `COUNTDOWN`(3초) → `STAGE`(stage+1). 중지 예약이 있으면 `COUNTDOWN` 대신 `IDLE`
  - `STAGE` → 성 HP 0 → `RESULT`(패) → 2초 후 `IDLE`, 성 HP 전회복, 몬스터 전부 제거, 영웅 리셋
  - `IDLE`에서 성 HP 0 → 성 HP 전회복, 몬스터 제거, 영웅 리셋 (패배 배너 없음)

### 4.2 WaveDirector (순수 로직)
- 입력: `stage: int`, `mode`
- 출력: `Array[SpawnEvent]` — `{time: float, kind: String, side: int}` 시간순 정렬
- 방치: `interval = Balance.idle_interval(stage)` 마다 `grunt` 1마리, 면은 순환
- 스테이지: 웨이브 `n = Balance.wave_count(stage)`개, 웨이브마다 `Balance.wave_size(stage, i)` 마리를 4면에 분배. 마지막 웨이브 종료 후 `epic_boss` 1마리, 면은 랜덤 시드 = stage
- 씬 의존 없음. 테스트 대상

### 4.3 Spawner
- `GameState.mode_changed`를 받아 스케줄을 새로 받고 타이머로 소비
- 살아 있는 몬스터 수 상한 120. 상한이면 스폰 이벤트를 지연
- 몬스터가 죽으면 카운트 감소. 스테이지 모드에서 스케줄 소진 + 살아 있는 몬스터 0 → `GameState.on_all_monsters_dead()`

### 4.4 Castle
- 성벽 한 변 길이 `Balance.CASTLE_SIZE`, 성문 4개는 `Marker3D` 자식. `gate_position(side) -> Vector3`
- 성문마다 `Area3D`(충돌 레이어 2)로 탭 판정
- 성문 HP는 `GameState.gate_hp`가 진실. Castle은 `gate_hp_changed`를 받아 색을 어둡게, `gate_broken`을 받아 성문 메시를 숨기고 `is_gate_broken(side)`를 노출
- 성 중앙 `Marker3D`(성채 위치)를 `keep_position() -> Vector3`로 제공. 파괴된 성문을 통과한 괴물의 목표점

### 4.5 Hero
- 스탯: `hp, atk, range, atk_interval, speed` — `Balance.HERO`에서 로드
- 상태: `IDLE | MOVE | ATTACK | DEAD`
- `assigned_side`: 배치 성문. 성문 위치에서 바깥으로 1.5 유닛 지점을 "자리"로 삼는다
- 0.2초마다 사거리 내 가장 가까운 몬스터 탐색. 있으면 `ATTACK`, 없고 자리에서 벗어났으면 `MOVE`
- 죽으면 `DEAD`. 메시 숨김, 탭 판정 끔, 행동 없음. `GameState.refilled`를 받을 때만 자리에서 HP 전회복으로 복귀. 부활 타이머 없음
- 영웅 수는 `GameState.hero_count()`. main이 시작 시 그 수만큼 인스턴스화하고 4개 성문에 순환 배치
- 선택 시 발밑에 링 표시

### 4.6 Monster
- 스탯: `Balance.MONSTER[kind]`에 스테이지 스케일 곱
- 우선순위: 사거리 안에 영웅 있음 → 공격. 없음 → 목표 성문으로 이동. 성문 도달 → 성문 멀쩡하면 `GameState.damage_gate` 주기 공격, 파괴됐으면 `Castle.keep_position()`으로 이동 → 도달 시 `GameState.damage_castle` 주기 공격
- `GameState.refilled`를 받으면 `queue_free`
- 죽으면 `queue_free`, Spawner에 통지
- 보스: 스케일 2.5배, HP·공격 배수. 색 구분

### 4.7 UnitPicker
- `_unhandled_input`에서 마우스 좌클릭(터치 에뮬레이트) 위치로 카메라 레이캐스트
- 레이어 3(영웅) 맞음 → 선택. 레이어 2(성문) 맞음 + 선택된 영웅 있음 → `assigned_side` 변경. 그 외 → 선택 해제

### 4.8 HUD
- 위: 스테이지 번호, 성 HP 바
- 아래: 버튼 하나. `IDLE`에선 "스테이지 진행", `STAGE/COUNTDOWN`에선 "이번 스테이지 후 중지"(토글)
- 중앙: 카운트다운 숫자, 승/패 배너 2초

## 5. 데이터 흐름

1. 버튼 → `GameState.start_stage()` → `mode_changed(STAGE)`
2. Spawner가 `WaveDirector.build(stage, STAGE)`로 스케줄 받아 타이머 소비 → `monster.gd` 인스턴스
3. 몬스터 이동/공격, 영웅 자동 공격. 성 피격은 `GameState.damage_castle`
4. 마지막 몬스터 사망 → Spawner → `GameState.on_all_monsters_dead()` → `RESULT` → 리셋 → `COUNTDOWN` → `STAGE`
5. HUD는 GameState 시그널만 구독. 게임 오브젝트를 직접 참조하지 않는다

## 6. 밸런스 초기값 (`balance.gd`)

- 성 HP 1000, 성문 HP 400 (각각). 성문은 서브프로젝트 2에서 성채·채석장·벌목장처럼 레벨업 대상이 되므로 `Balance.gate_hp_max(level)` 함수로 두고 MVP는 레벨 1
- 영웅 슬롯: 성채 레벨별 `[4, 8, 12]`. MVP 성채 레벨 1
- 영웅: hp 300, atk 25, range 3.0, atk_interval 0.8, speed 6
- grunt: hp 60, atk 10, speed 2.5, 성 공격 간격 1.0
- epic_boss: hp 400, atk 20, speed 1.8 (스테이지 1 보스는 영웅 1명이 혼자 이길 수 있어야 한다. 헤드리스 자동 진행은 영웅을 움직이지 않기 때문)
- 스테이지 스케일: hp ×(1 + 0.25·(stage−1)), atk ×(1 + 0.15·(stage−1))
- 방치 스폰 간격 4초. 스테이지 웨이브 수 3 + stage/3, 웨이브 크기 6 + 2·stage, 웨이브 간격 8초
- 전부 튠 대상. 숫자는 첫 실행용

## 7. 오류 처리

- 네트워크·파일 IO 없음. 실패 지점은 데이터 누락과 잘못된 상태 전이
- `Balance.MONSTER[kind]` 없는 kind는 `assert`로 즉시 실패 (개발 중 발견)
- 상태 전이는 `GameState` 안에서만 일어난다. 허용되지 않은 전이는 무시하고 `push_warning`
- 성 HP·유닛 HP는 0 미만으로 내려가지 않게 `maxi` 처리

## 8. 성능 (모바일)

- 몬스터 동시 120 상한
- 타깃 탐색은 0.2초 주기. 매 프레임 거리 계산 금지
- 물리 없음: 유닛은 `global_position` 직접 이동. 몬스터는 성문까지의 거리로 정지 판단. 성벽 통과는 목표가 항상 성문 바깥 지점이므로 발생하지 않는다
- 단일 `DirectionalLight3D`, 그림자 끔. 머티리얼은 `StandardMaterial3D` 단색

## 9. 테스트

- `tests/run_tests.gd`: `SceneTree`를 확장. `godot --headless -s tests/run_tests.gd`로 실행. 실패 시 종료 코드 1
  - WaveDirector: stage 1 스테이지 스케줄이 시간순이고 마지막 이벤트가 `epic_boss`
  - WaveDirector: stage가 커지면 총 스폰 수가 줄지 않는다
  - Balance: 스케일 함수가 stage에 대해 단조 증가
  - GameState: `IDLE → STAGE → RESULT → COUNTDOWN → STAGE` 전이, 패배 시 `IDLE` 복귀와 stage 유지
  - GameState: `damage_gate`가 HP 0에서 `gate_broken`을 정확히 한 번 내고, 이후 피해는 무시. `refill()` 후 성문·성 HP 최대치 복원
  - GameState: `hero_count()`가 성채 레벨 1에서 4
- 스모크: `godot --headless --fixed-fps 60 --quit-after 900 -- --auto-stage`가 `SCRIPT ERROR` 없이 종료
- 수동: 데스크톱 실행. 영웅 이동, 스테이지 1 클리어, 카운트다운, 스테이지 2 진입 확인
- 실행 방법: 프로젝트 루트에서 `./tools/Godot_v4.7.2-stable_win64_console.exe --path .` (창 실행), 에디터는 `--editor` 추가. 개발 플래그는 `--` 뒤에 `--shot=SECONDS`, `--auto-stage`

## 10. 완료 기준

- 위 테스트·스모크 통과
- 데스크톱에서 스테이지 1→2 연속 진행과 패배→방치 복귀가 동작
- 프로젝트 설정이 세로·Compatibility·모바일 기준
- 스크립트 12개 이내(테스트 제외), 씬 파일 1개, 외부 에셋 0개

# CastleRPG 개정 9: 온라인 서버 + Neon DB

작성일: 2026-10-01
기반: 개정 2~8. 충돌 시 이 문서가 우선한다.
계기: 사용자. "이 게임은 결국 온라인 모바일 앱으로 출시하고 Neon DB를 쓴다. DB로 관리해야 할 항목은 전부 DB로 관리해 줘."
사용자 지시에 따라 묻지 않고 진행한다. 결정은 이 문서에 적는다.

## 1. 구조

```
Godot 앱 (Android/iOS/웹)  ──HTTPS JSON──▶  API 서버 (Node 24 + Hono, TypeScript)  ──▶  Neon Postgres
```

- **앱은 DB에 직접 붙지 않는다.** DB 접속 문자열이 앱에 들어가면 누구나 꺼내서 모든 플레이어 데이터를 읽고 쓸 수 있다. 접속 정보는 서버 환경 변수(`DATABASE_URL`)에만 둔다.
- **서버가 권위를 가진다.** 서버가 하는 일은 다음과 같다.
  - 시간: 수집 축적, 시세 시간 칸
  - 수집량·판매 골드·처치 골드 계산
  - 진행도 저장
  - 앱은 표시와 입력만 맡는다. 그래서 기기 시계 조작이 통하지 않는다(개정 7의 알려진 한계가 풀린다).
- **서버 코드**: 저장소 `server/`.
  - TypeScript는 Node 24 타입 제거로 빌드 없이 실행한다(지울 수 있는 문법만).
  - 웹 프레임워크는 Hono(+ `@hono/node-server`)다. Node·Vercel·Cloudflare·Fly 어디든 올릴 수 있다.
  - DB 드라이버: 운영은 `@neondatabase/serverless`(HTTP)다. `DATABASE_URL`이 없으면 개발·테스트용으로 `@electric-sql/pglite`(WASM Postgres)를 쓴다. 파일(`server/.data/`)이나 메모리에 둔다.
  - 그래서 로컬에 Postgres를 설치하지 않아도 되고, 테스트도 외부 서비스 없이 돈다.
  - 쿼리 함수는 하나다: `query(text, params) -> rows`. 두 드라이버가 같은 함수를 구현한다.
  - `server/.gdignore`를 둬서 Godot가 이 폴더를 무시하게 한다.

## 2. DB로 관리하는 것 / 앱에 남는 것

| 구분 | 항목 | 위치 |
|---|---|---|
| 기획 데이터(읽기 전용, 라이브 조정) | 몬스터 기본값, 스테이지 배율·웨이브, 영웅 직업 능력치, 자원(생산·단가), 게임 설정값(성/성문 HP, 영웅 슬롯·순서, 웨이브 타이밍, 축적 상한, 말풍선 분, 시세 분포, 처치 속도 상한) | DB 표 `monsters`, `stages`, `hero_roles`, `resources`, `game_config` |
| 플레이어 데이터 | 계정(게스트), 골드, 자원 보유량, 건물 레벨·마지막 수집 시각, 현재 스테이지, 성채·성문 레벨 | `players`, `player_state`, `player_resources`, `player_buildings` |
| 감사 기록 | 수집·판매·처치 골드·스테이지 클리어 이력(부정 탐지·CS용) | `economy_log` |
| 앱에 남음 | 맵·성 기하, 건물 배치, 카메라, UI, 모델·애니메이션, 탭 판정 | `Balance`(클라이언트 상수) |

- 기하·배치는 렌더링과 한 몸이라 앱 업데이트와 같이 바뀐다. 그래서 DB에 두지 않는다.
- `data/*.csv`는 두 가지 역할을 한다.
  - DB 초기값(시드): `npm --prefix server run seed`가 넣는다.
  - 앱 내장 기본값: 오프라인 개발 모드와 테스트에서 쓴다.
- 운영 중 수정은 DB에서 한다(Neon 콘솔 SQL 편집기 등). 앱은 접속할 때마다 `/v1/gamedata`로 받는다.
- CSV를 DB와 맞추는 것은 시드할 때뿐이다. DB가 진실이다.

새 CSV(이 개정에서 추가, 형식은 기존 표와 같다. 첫 열이 키, 헤더 이름으로 찾는다):
- `data/heroes.csv`: `id,name,hp,atk,range,atk_interval,speed,aggro`
- `data/resources.csv`: `id,name,building,per_min,price`
- `data/config.csv`: `key,value`. 값은 숫자이거나 `|`로 구분한 목록이다(`hero_slots` = `4|8|12`, `hero_roster` = `warrior|archer`).
  - 키: `castle_hp`, `gate_hp_per_level`, `hero_slots`, `hero_roster`, `max_live_monsters`, `countdown_sec`, `result_sec`, `wave_gap_sec`, `spawn_spacing_sec`, `accum_cap_min`, `badge_min`, `merchant_jackpot_p`, `merchant_jackpot_rate`, `merchant_rate_min`, `merchant_rate_max`, `merchant_rate_step`, `merchant_low_high_ratio`, `kill_rate_cap`(서버 전용, 초당 처치 상한)

## 3. DB 스키마 (`server/migrations/*.sql`, 순서대로 적용, `schema_migrations`로 기록)

```sql
-- 기획 데이터
create table monsters (id text primary key, hp real not null, atk real not null, speed real not null, range real not null,
  atk_interval real not null, aggro real not null, scale real not null, gold integer not null);
create table stages (stage integer primary key check (stage >= 1), hp_mult real not null, atk_mult real not null, gold_mult real not null,
  waves integer not null, wave_size integer not null, idle_interval real not null);
create table hero_roles (id text primary key, name text not null, hp real not null, atk real not null, range real not null,
  atk_interval real not null, speed real not null, aggro real not null);
create table resources (id text primary key, name text not null, building text not null unique, per_min integer not null, price integer not null);
create table game_config (key text primary key, value text not null);
-- 플레이어
create table players (id uuid primary key default gen_random_uuid(), device_id text not null unique,
  created_at timestamptz not null default now(), last_seen timestamptz not null default now());
create table player_state (player_id uuid primary key references players(id) on delete cascade,
  gold bigint not null default 0 check (gold >= 0), stage integer not null default 1, keep_level integer not null default 1,
  gate_level integer not null default 1, last_kill_report timestamptz not null default now(), version integer not null default 0);
create table player_resources (player_id uuid references players(id) on delete cascade, res text not null,
  amount bigint not null default 0 check (amount >= 0), primary key (player_id, res));
create table player_buildings (player_id uuid references players(id) on delete cascade, building text not null,
  level integer not null default 1, last_collect timestamptz not null default now(), primary key (player_id, building));
create table economy_log (id bigserial primary key, player_id uuid not null references players(id) on delete cascade,
  kind text not null, detail jsonb not null, at timestamptz not null default now());
create index on economy_log (player_id, at);
```

- 새 플레이어는 `player_state` 1행, `resources`의 자원마다 `player_resources` 1행, 자원 건물마다 `player_buildings` 1행(last_collect = 지금)으로 만든다.
- **동시성**: 같은 플레이어의 요청이 겹쳐도 두 번 수집되거나 골드가 꼬이지 않아야 한다.
  - 각 변경은 한 문장(CTE)으로 원자적으로 하거나, `player_state.version` 비교 후 갱신(낙관적 잠금, 충돌 시 재시도 3회, 실패하면 409)으로 한다.
  - Neon HTTP 드라이버는 대화형 트랜잭션이 없다. 그래서 둘 중 하나로 구현한다(구현자 판단, 테스트로 증명).

## 4. API (`/v1`, JSON, UTF-8)

- **공통**:
  - `/v1/auth/guest`, `/v1/gamedata`, `/v1/health`를 뺀 모든 요청은 `Authorization: Bearer <JWT>`가 필요하다.
  - JWT는 HS256, `JWT_SECRET` 환경 변수, 30일 만료, `sub` = player id.
  - 오류는 `{"error": "<code>", "message": "..."}` 형식에 상태 코드 400(잘못된 입력), 401(토큰), 404, 409(경합), 500을 쓴다.
  - 플레이어 응답은 항상 다음을 포함한다.
    - `server_now`(유닉스 초, float)
    - `player`: `{gold, res: {wood, stone, food}, stage, keep_level, gate_level, buildings: {lumber: {level, last_collect}, ...}}`(last_collect는 유닉스 초)
    - `merchant`: `{rate, next_change}`
- 엔드포인트:
  - `GET /v1/health` → `{ok: true, server_now}`
  - `POST /v1/auth/guest` `{device_id}`
    - device_id는 16~128자 `[A-Za-z0-9-]`다.
    - 플레이어를 찾거나 만들고, last_seen을 갱신한다. → `{token, player_id}`
  - `GET /v1/gamedata` → `{version, monsters: [...], stages: [...], heroes: [...], resources: [...], config: {key: value(문자열)}}`
    - 행은 CSV 열 이름과 같은 키를 쓴다.
    - version은 내용 해시다(`ETag`도 같이 준다).
  - `GET /v1/player` → 플레이어 응답
  - `POST /v1/collect` `{building}`
    - 개정 7 §2 규칙을 서버 시간으로 적용한다: 분 내림, 상한, 남은 초 유지, 음수 경과는 지금으로.
    - → 플레이어 응답 + `amount`
    - 자원 건물이 아니면 400이다.
  - `POST /v1/sell` `{res}`
    - res는 자원 id 또는 `"all"`이다. 현재 시세로 판다.
    - → 플레이어 응답 + `gold_gained`, `rate`
  - `POST /v1/kills` `{stage, kills: {<monster id>: count}}`
    - 골드는 Σ count × kill_gold(id, stage)이고, 개정 8의 연장 규칙을 그대로 쓴다.
    - 타당성 검사:
      - stage는 1 이상, `player.stage` 이하다(넘으면 player.stage로 자른다).
      - 모르는 몬스터 id는 400이다.
      - 총 처치 수 상한 = ceil(지난 보고 이후 초 × kill_rate_cap) + 20이다. 넘는 만큼 버리고 로그에 `clamped: true`를 남긴다.
    - last_kill_report를 갱신한다. → 플레이어 응답 + `gold_gained`
  - `POST /v1/stage/clear` `{stage}`
    - stage == player.stage면 +1이고, 아니면 변화 없이 현재 상태를 준다(중복·재전송 안전). → 플레이어 응답
  - `POST /v1/test/age` `{minutes}`
    - `ALLOW_TEST_HOOKS=1`일 때만 존재한다.
    - 그 플레이어 건물의 last_collect를 minutes분 앞당긴다. 통합 테스트용이다.
- **시세**:
  - 서버가 시간 칸(유닉스 초 / 3600 내림)으로 결정적으로 계산한다. 분포는 개정 7 §3과 같고, 값은 config에서 읽는다.
  - 결정적 32비트 난수(mulberry32 등, 시드 = 시간 칸)를 쓴다.
  - 앱 오프라인 모드의 값과 같을 필요는 없다(온라인에서는 서버 값만 표시).
- **CORS**: `CORS_ORIGINS` 환경 변수(쉼표 목록)로 정한다. 비어 있으면 `*`다. 웹 미리보기(8060)가 로컬 서버(8787)를 부를 수 있어야 한다.
- **시작 조건**: `DATABASE_URL`이 있는데 `JWT_SECRET`이 없으면 시작을 거부한다. 개발 모드(`DATABASE_URL` 없음)는 고정 개발 비밀을 쓰고 경고를 출력한다.

## 5. 서버 명령 (`server/package.json`)

- `npm --prefix server run dev`
  - 포트 8787에서 시작한다(`PORT`로 바꿀 수 있다).
  - `DATABASE_URL`이 없으면 `server/.data/dev`의 PGlite를 쓴다(git 제외).
  - 시작할 때 마이그레이션을 적용하고, 기획 표가 비어 있으면 `data/*.csv`로 시드한다.
- `npm --prefix server test`: `node --test`, 메모리 PGlite. 외부 서비스가 없다.
- `npm --prefix server run migrate` / `run seed`: `DATABASE_URL`(Neon)에 적용한다.
  - seed는 `data/*.csv`로 기획 표를 덮어쓴다(upsert). 표에서 사라진 키는 지운다.
- `server/.env.example`: `DATABASE_URL`, `JWT_SECRET`, `CORS_ORIGINS`, `PORT`, `ALLOW_TEST_HOOKS`. `.env`는 git 제외다.

## 6. 앱 (Godot)

- **API 주소**:
  - 프로젝트 설정 `castle/api_base_url`(기본 "")
  - 데스크톱 `-- --api=<url>`
  - 웹 `?api=<url>`
  - 셋 다 비어 있으면 **오프라인 모드**다: 지금 동작 그대로(내장 CSV, `user://save.json`). 개발과 테스트용이다.
  - 출시 빌드는 설정으로 주소를 넣는다(온라인 전용).
- **기획 데이터 확장**: `GameData`에 다음을 더한다.
  - `heroes()`, `hero(id)`, `resources()`, `resource(id)`, `config_num(key) -> float`, `config_list(key) -> Array`
  - `apply_remote(payload)`: `/v1/gamedata` 응답으로 표를 교체한다. 같은 검증을 하고, 실패하면 내장 값을 유지하고 오류를 낸다.
  - `Balance`에서 `CASTLE_HP`, `HERO_SLOTS`, `MAX_LIVE_MONSTERS`, `COUNTDOWN_SEC`, `RESULT_SEC`, `WAVE_GAP_SEC`, `SPAWN_SPACING_SEC`, `RESOURCES`, `ACCUM_CAP_MIN`, `BADGE_MIN`, `MERCHANT_*`, `HERO_ROLES`, `HERO_ROSTER`, `gate_hp_max`, `hero_slots`, `hero_role`를 지우고, 호출부는 GameData를 쓴다.
- **온라인 접속**(신규 `scripts/net.gd`, 오토로드 `Net`):
  - 기기 id: `user://device.json`(처음 실행 때 무작위 128비트 hex)
  - 순서: 게스트 로그인, gamedata, player
  - 401이면 다시 로그인한다.
  - 응답마다 `server_now − 로컬 시각`으로 시계 차이를 맞춘다.
  - HTTPRequest를 쓰고, 요청은 한 번에 하나(큐)다.
  - 실패하면 2·4·8초(최대 15초) 간격으로 다시 시도한다.
- **시작 흐름**(main): 온라인 모드면 월드를 만들기 전에 "서버 연결 중…" 화면을 띄운다. 접속(gamedata + player)을 마치면 월드를 만든다. 그래서 영웅·몬스터·스테이지가 서버 값으로 시작한다. 오프라인 모드는 지금처럼 바로 만든다.
- **Economy 온라인 모드**:
  - 상태(골드·자원·건물·스테이지)는 서버 응답으로만 바꾼다.
  - `collect` / `sell` / `sell_all`은 요청을 보내고 응답이 오면 반영한다(`changed`). 응답 전 같은 건물 탭은 무시한다.
  - 말풍선·쌓인 양 표시·시세 남은 시간은 서버 보정 시각과 서버가 준 last_collect·merchant로 계산한다.
  - 처치 골드:
    - 로컬에 몬스터 종류·스테이지별 개수로 모아 둔다.
    - 10초마다, 그리고 스테이지 클리어 때 `/v1/kills`로 보낸다.
    - 표시 골드 = 서버 골드 + 아직 안 보낸 처치의 예상 골드다.
  - 스테이지 클리어 때 `/v1/stage/clear`를 보낸다. 시작할 때 GameState.stage를 서버 stage로 둔다.
  - 연결이 끊기면 상단에 "서버 연결 중…" 띠를 띄운다. 전투는 계속하고, 수집·판매 탭은 "연결 대기 중" 알림만 보이고 아무것도 하지 않는다. 처치는 쌓아 뒀다가 다시 연결되면 보낸다.
  - 상인 이름표·거래 창 배율은 서버 merchant를 쓴다. next_change가 지나면 `/v1/player`로 갱신한다.
  - 오프라인 모드의 로컬 규칙(개정 7)은 개발·테스트용으로 남긴다.
- **보안**: 앱에 DB 정보나 JWT 비밀이 없다. 토큰은 메모리에만 둔다. 기기 id가 게스트 계정의 열쇠다(계정 연동은 범위 밖).

## 7. 테스트

- **서버**(`npm --prefix server test`, 메모리 PGlite):
  - 마이그레이션·시드(CSV 행 수와 DB 행 수가 같다)
  - 게스트 로그인 멱등(같은 device_id면 같은 player)
  - JWT 없음/위조는 401
  - 수집 규칙 전부(테스트 시계 주입)
  - 동시 수집 2건은 한 번만 수집된다
  - 판매·시세 분포(표본 20만 칸에서 2.0 비율 5% ± 0.5%, P(0.5)/P(1.5) = 3 ± 0.3)
  - 처치 골드 계산과 상한 자르기
  - 스테이지 클리어 멱등
  - gamedata version이 내용이 바뀌면 바뀐다
  - `ALLOW_TEST_HOOKS`가 없으면 `/v1/test/age`는 404
  - 플레이어 간 격리(A 토큰으로 B 상태를 바꿀 수 없다)
- **앱 로직**(`run_tests.gd`): 새 CSV 읽기, `apply_remote` 교체·검증 실패 시 유지, config 목록 파싱, Balance에서 옮긴 값이 이전 상수와 같다.
- **앱 기존 체크**: 로직·입력·AI·E2E 전부 통과(오프라인 모드, 동작 불변).
- **통합**(`bash dev/online-check.sh`):
  1. 메모리 PGlite + `ALLOW_TEST_HOOKS=1`로 서버를 띄운다(포트 8790).
  2. `res://tests/online_check.tscn -- --api=http://127.0.0.1:8790`을 헤드리스로 돌린다:
     - 접속 후 월드가 만들어진다
     - 처치 골드가 서버로 들어간다
     - `test/age` 후 벌목장 탭으로 서버 수집이 된다
     - 판매가 된다
     - 스테이지 클리어가 저장된다
  3. 두 번째 실행(같은 device_id)에서 골드·자원·스테이지가 복원된다.
  4. 서버를 끈다.
- **웹 캡처**(컨트롤러): `?api=http://localhost:8787`로 로컬 서버에 붙은 상태를 확인한다.

## 8. 배포 (사용자 몫, 문서화만)

- Neon 프로젝트를 만들고 접속 문자열(`sslmode=require`)을 준비한다. 서버 환경에 `DATABASE_URL`, `JWT_SECRET`(32바이트 이상 무작위)을 넣는다. `npm --prefix server run migrate && npm --prefix server run seed`를 실행한 뒤 서버를 올린다.
- 앱 설정 `castle/api_base_url`에 서버 주소를 넣는다.
- 절차는 `server/README.md`에 적는다. 호스팅(Fly.io·Vercel·Cloudflare 등)은 사용자가 고른다.

## 9. 범위 밖

계정 연동(Google/Apple), 결제, 랭킹, 요청 속도 제한, 관리자 도구, 오프라인 진행분 병합, 영웅 데이터 저장(영웅 성장 시스템이 생길 때).

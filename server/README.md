# CastleRPG API 서버

Godot 앱과 Neon Postgres 사이의 권위 서버다(개정 9 스펙 `docs/superpowers/specs/2026-10-01-castlerpg-online-neon-design.md`).
시간, 수집량, 판매·처치 골드, 진행도는 서버가 정한다. 앱은 DB에 직접 붙지 않는다.

- Node 24 + Hono(`@hono/node-server`). TypeScript는 Node 타입 제거로 빌드 없이 실행한다. 그래서 지울 수 있는 문법만 쓴다(enum·namespace·parameter properties 금지).
- DB 드라이버
  - `DATABASE_URL`이 있으면 `@neondatabase/serverless`(HTTP)를 쓴다.
  - 없으면 `@electric-sql/pglite`(WASM Postgres)를 쓴다. 로컬에 Postgres를 설치할 필요가 없다.
- 쿼리 함수는 `query(text, params) -> rows` 하나다(`src/db.ts`).

## 파일

| 파일 | 내용 |
|---|---|
| `src/main.ts` | 서버를 시작한다. 개발 모드면 마이그레이션을 적용하고, 기획 표가 비어 있으면 시드한다. |
| `src/env.ts` | 환경 변수 → 설정(`readEnv`). 위험한 조합이면 시작을 거부한다(아래 표). |
| `src/app.ts` | Hono 앱 팩토리 `createApp({query, now, jwtSecret, allowTestHooks, corsOrigins})`. 엔드포인트 전부가 여기 있다. |
| `src/rules.ts` | 경제 규칙(순수 함수, 시간 인자): 수집, 시세, 판매, 스테이지 연장, 처치 골드·상한. |
| `src/db.ts` | Neon/PGlite `query`·`batch`(한 트랜잭션), 마이그레이션 러너(`schema_migrations`). |
| `src/seed.ts` | `data/*.csv`를 검증하고 기획 표 전부를 한 트랜잭션으로 upsert한다. 사라진 키는 지운다. |
| `src/cli.ts` | `npm run migrate` / `npm run seed`. |
| `migrations/*.sql` | 이름순으로 적용된다. 파일 하나가 한 트랜잭션이다. |
| `test/*.test.ts` | `node --test`, 메모리 PGlite. |

## 로컬 실행

```bash
npm --prefix server install
npm --prefix server run dev        # http://127.0.0.1:8787
curl http://127.0.0.1:8787/v1/health
```

- `DATABASE_URL`이 없으면 개발 모드다.
  - DB는 `server/.data/dev`(PGlite 파일, git 제외)에 둔다. `PGLITE_DIR=memory`면 메모리에 두며, 서버를 끄면 사라진다.
  - JWT는 고정 개발 비밀로 서명하고, 시작할 때 경고를 출력한다.
  - 기본으로 `127.0.0.1`에서만 듣는다. 바꾸려면 `HOST`를 쓴다.
- 시작할 때 마이그레이션을 적용한다. 기획 표가 하나라도 비어 있으면 `data/*.csv`로 시드한다.
  - CSV를 고친 뒤 개발 DB에 다시 넣으려면 `npm --prefix server run seed`를 실행한다.
- 통합 테스트용 서버 예시:

  ```bash
  cd server
  PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=8790 node src/main.ts
  ```

  - Windows에서 `npm run dev`를 백그라운드로 띄우고 npm만 죽이면, 자식 `node`가 포트를 쥔 채 남는다.
  - 스크립트에서는 `node src/main.ts`를 직접 띄워서 그 PID를 끈다.

환경 변수(`.env.example` 참고. `server/.env`는 `npm run dev/migrate/seed`가 읽고, git에서 제외된다):

| 이름 | 뜻 |
|---|---|
| `DATABASE_URL` | Neon 접속 문자열. 비우면 개발 모드다. |
| `JWT_SECRET` | HS256 비밀. `DATABASE_URL`이 있는데 비었거나 32자 미만이면 **시작을 거부한다**. |
| `CORS_ORIGINS` | 허용할 출처(쉼표 목록). 비우면 `*`다. **운영에서는 웹 빌드 출처로 정한다.** |
| `PORT` | 기본 8787이다. |
| `ALLOW_TEST_HOOKS` | `1`이면 `POST /v1/test/age`(수집 시각·훈련 끝나는 시각 당기기) 같은 테스트 훅이 생긴다. `DATABASE_URL`과 같이 있으면 **시작을 거부한다**. |
| `HOST` | (선택) 듣는 주소. 기본은 개발 `127.0.0.1`, 운영 `0.0.0.0`이다. 고정 개발 비밀(`JWT_SECRET` 없음)인데 루프백(`127.x`, `localhost`, `::1`)이 아니면 **시작을 거부한다**. |
| `PGLITE_DIR` | (선택) 개발 PGlite 위치. `memory`면 메모리다. |

## 테스트

```bash
npm --prefix server test
```

- 외부 서비스 없이 메모리 PGlite로 돈다. HTTP는 Hono `app.request()`로 부르므로 포트가 필요 없다. 시계는 주입한다.
- 검사 항목:
  - 마이그레이션·시드
  - CSV 규칙과 오류 위치
  - 게스트 로그인 멱등
  - JWT 401
  - 수집 규칙
  - 동시 수집·판매·같은 seq 처치·모집
  - 시작 영웅(시드 전 DB면 스펙 기본값), 모집(비용·409·결과·10연차 보장·확률 표본), 배치 검증, 마이그레이션 003~005
  - 시드의 모집 설정 검증(비용·보장 수 0 이상 정수, 확률 0..1·합 ≤ 1, 등급마다 영웅 하나 이상)
  - 409
  - 시세 분포
  - 처치 골드·토큰 버킷(같은 순간 50연타)·처치 멱등(seq)
  - 스테이지 클리어 멱등·최소 간격(같은 순간 300연타)
  - 입력 상한·`__proto__` 키·본문 16 KB(413)
  - 시작 거부 조건(`readEnv`)
  - 시드 원자성
  - gamedata version
  - 테스트 훅 404
  - 플레이어 격리
  - 연구(`test/research.test.ts`): 비용·시간 공식, 잠금·바쁨·부족 409, 취소 환불, 다이아 즉시 완료, 자동 완료, 서버 권위 효과, 원자성, 마이그레이션 016, 시드 검증

## API 요약 (스펙 §4)

모든 요청과 응답은 JSON이다. 시각은 유닉스 초(float)다. 오류는 `{"error": "<code>", "message": "..."}` 형식에 400·401·404·409·413·500을 쓴다.
`/v1/*` 요청 본문은 16 KB까지다. 넘으면 읽기 전에 413 `payload_too_large`다.

| 요청 | 인증 | 응답 |
|---|---|---|
| `GET /v1/health` | - | `{ok, server_now}` |
| `POST /v1/auth/guest {device_id}` | - | `{token, player_id}`. device_id는 16~128자 `[A-Za-z0-9-]`, 토큰은 30일 유효 |
| `GET /v1/gamedata` | - | `{version, monsters, stages, heroes, resources, buildings, soldiers, upgrades, dungeons, equip_drop, research, config}`. `ETag` = `"version"`이고, `If-None-Match`가 맞으면 304 |
| `GET /v1/player` | Bearer | 플레이어 응답 |
| `POST /v1/collect {building}` | Bearer | 플레이어 응답 + `amount` |
| `POST /v1/sell {res}` | Bearer | 플레이어 응답 + `gold_gained`, `rate`. res는 자원 id 또는 `"all"` |
| `POST /v1/kills {seq, stage, kills}` | Bearer | 플레이어 응답 + `gold_gained` |
| `POST /v1/stage/clear {stage}` | Bearer | 플레이어 응답 + `cleared` |
| `POST /v1/building/upgrade {building}` | Bearer | 플레이어 응답 + `build: {id, finish}`. 모르는 건물은 400 `unknown_building`, 아니면 409 `max_level` / `keep_cap` / `prereq` / `builder_busy` / `not_enough`(이 순서로 검사) |
| `POST /v1/test/build_now` | Bearer | 플레이어 응답. `ALLOW_TEST_HOOKS=1`일 때만 있다. 진행 중 건설의 끝나는 시각을 지금으로(같은 응답이 완료를 반영) |
| `POST /v1/gacha {count}` | Bearer | 플레이어 응답 + `results: [{hero_id, grade, new, copies, shards}]`. count는 1 또는 10. 골드가 모자라면 409 `not_enough_gold` |
| `POST /v1/deploy {deploy}` | Bearer | 플레이어 응답. deploy = [영웅 id 또는 null, …], 길이 = 슬롯 수, 보유한 영웅만, 중복 금지. 아니면 400 `bad_deploy` |
| `POST /v1/hero/levelup {hero_id, count}` | Bearer | 플레이어 응답 + `level`. count는 1..100 정수. 보유하지 않은 영웅은 404 `not_owned`, 최대 레벨을 넘으면 409 `max_level`, 골드가 모자라면 409 `not_enough_gold` |
| `POST /v1/hero/promote {hero_id}` | Bearer | 플레이어 응답 + `promotion`(새 승급). 보유하지 않은 영웅은 404 `not_owned`, 최대 승급(5)이면 409 `max_promotion`, 조각이 모자라면 409 `not_enough_shards`(이 순서로 검사) |
| `POST /v1/test/shards {hero_id, shards}` | Bearer | 플레이어 응답. `ALLOW_TEST_HOOKS=1`일 때만 있다. 보유 영웅의 조각 수를 정한다(서버 모집은 암호학적 난수라 통합 테스트가 중복을 만들 수 없다) |
| `POST /v1/soldiers/merge {type, tier}` | Bearer | 플레이어 응답 + `merged: {type, tier}`(새 티어). 모르는 병종은 400 `unknown_soldier`, tier는 1 이상 정수(아니면 400). 최대 티어면 409 `max_tier`, `soldier_merge_count`마리보다 적으면 409 `not_enough` |
| `POST /v1/soldiers/train {building, count}` | Bearer | 플레이어 응답 + `training: {building, count, finish}`. 병사 건물이 아니면 400 `not_soldier_building`, count가 1..묶음 상한이 아니면 400. 대기열이 진행 중이면 409 `training`, 끝났는데 수령 전이면 409 `ready_to_collect`, 자원이 모자라면 409 `not_enough`(개정 16) |
| `POST /v1/soldiers/collect {building}` | Bearer | 플레이어 응답 + `collected: {type, count}`. 비었으면 409 `empty`, 아직이면 409 `not_ready`. 멱등(두 번째는 409 `empty`) |
| `POST /v1/soldiers/cancel {building}` | Bearer | 플레이어 응답 + `refund: {자원: 수}`(비용의 50%, 내림). 비었으면 409 `empty`, 이미 끝났으면 409 `ready_to_collect` |
| `POST /v1/soldiers/deploy {deploy}` | Bearer | 플레이어 응답. deploy = `{"병종:티어": 수}`(0 이상 정수). 키 형식·보유 이하·합계 ≤ 인구가 아니면 400 `bad_deploy`. 멱등 |
| `POST /v1/research/start {id}` | Bearer | 플레이어 응답(`research.current = {id, finish}`). 모르는 노드는 404 `unknown_research`, 아니면 409 `research_busy` / `max_level` / `locked` / `not_enough_resources` / `not_enough_gold`(이 순서로 검사, 개정 24) |
| `POST /v1/research/cancel` | Bearer | 플레이어 응답 + `refund: {wood, stone, food, gold}`(그 레벨 비용 × `research_cancel_refund`, 내림). 진행 중이 아니면 409 `no_research` |
| `POST /v1/research/finish` | Bearer | 플레이어 응답 + `diamonds_spent`(= max(1, ⌈남은 초 / 60⌉ × `research_dia_per_min`)). 진행 중이 아니면 409 `no_research`, 다이아가 모자라면 409 `not_enough_diamonds` |
| `POST /v1/test/age {minutes}` | Bearer | 플레이어 응답. `ALLOW_TEST_HOOKS=1`일 때만 있다. minutes는 0..100000 정수. 모든 건물의 `last_collect`(자원 수집)와 훈련 끝나는 시각(`train_finish`), 연구 끝나는 시각(`research_finish`)을 당긴다 |

플레이어 응답은 다음과 같다.

```
{server_now, player: {gold_tenths, gold, res: {wood, stone, food}, stage, keep_level, gate_level, kill_seq,
 buildings: {keep: {level}, gate: {level}, ..., lumber: {level, last_collect}, quarry: ..., farm: ..., barracks: {level}, archery: ..., stable: ...},
 build: {id, finish} | null, population, heroes: {hero_id: {copies, level, shards, promotion}}, deploy: [hero_id | null, ...],
 soldiers: {"infantry:1": n, ...}, soldier_deploy: {"infantry:1": n, ...},
 training: {barracks: {count, finish} | null, archery: ..., stable: ...},
 research: {levels: {id: L}, current: {id, finish} | null}},
 merchant: {rates: {wood, stone, food}, next_change}}
```

- 입력 상한(넘으면 400): `stage` 1..1,000,000 정수, 처치 수(몬스터 한 종류) 0..10,000 정수, `seq` 0..2147483647 정수.
- 처치 보고 번호 `seq`(멱등)
  - 앱은 보고마다 `seq`를 1씩 올린다. 서버는 마지막으로 반영한 번호를 `player_state.kill_seq`에 두고, 플레이어 응답 `player.kill_seq`로 알려 준다.
  - `seq <= kill_seq`면(응답 유실 뒤 재전송, 늦게 온 옛 요청) 아무것도 바꾸지 않고 현재 상태 + `gold_gained: 0`을 준다.
  - 크면 반영하고 `kill_seq = seq`로 둔다. version 비교와 같은 문장이라, 같은 seq 두 건이 겹쳐도 한 번만 들어간다.
- 처치 상한(토큰 버킷)
  - `W = kill_burst_sec`(기본 60), `rate = kill_rate_cap`(초당).
  - `lkr_eff = max(last_kill_report, now − W)`, 상한 `cap = max(0, ceil((now − lkr_eff) × rate))`.
  - 인정한 처치 `kept`개만큼만 시각을 옮긴다: `last_kill_report = lkr_eff + kept / rate`.
  - 그래서 같은 순간 여러 번 보내도 합쳐서 버킷(`W × rate`, 기본 300) 이상은 못 얻고, 오래 쉬어도 한 번에 버킷까지만 받는다.
  - 넘는 만큼은 **싼 몬스터부터 인정**하고, 비싼 몬스터를 먼저 버린다.
  - 버린 일이 있으면 `economy_log`에 `clamped: true`를 남긴다.
- 스테이지 클리어
  - `stage == player.stage`이고 지난 클리어(새 계정은 가입) 이후 `waves × wave_size / kill_rate_cap`초(그 스테이지 행, 연장 규칙)가 지났으면 +1, `cleared: true`.
  - 아니면(중복·재전송·앞지름·너무 빠름) 200 + 상태 그대로 + `cleared: false`다. 앱은 `player.stage`를 진실로 쓴다.
  - 앱은 `cleared: false`를 다시 보내지 않는다. 보낸 클리어가 전부 답을 받았는데 앱 스테이지가 서버와 다르면, 다음 스테이지 경계(결과가 끝날 때·스테이지 시작)에서 서버 값으로 맞춘다. 스테이지 도중에는 바꾸지 않는다.
- 시세는 시간 칸(`floor(유닉스 초 / 3600)`)을 시드로 한 mulberry32로 결정적으로 계산한다. 분포 값은 `game_config`에서 읽는다.
- 건물(개정 12, 마이그레이션 007: `building_defs` = `data/buildings.csv`, `player_state.build_id`·`build_finish`, 모든 건물의 `player_buildings` 행)
  - L → L+1 비용(목재·석재·식량) = round(값 × 1.35^(L−1)), 시간(초) = round(`base_sec` × 1.5^(L−1)). 성채를 뺀 건물은 목표 레벨 ≤ 성채 레벨, 선행 `req1`·`req2` ≥ 목표 − 1. 일꾼은 1명.
  - 자원 건물은 시작할 때 먼저 자동 수집(수집 규칙 그대로)하고 그 양까지 비용에 쓴다. 수집·차감·일꾼·`economy_log`(`build_start`)는 version 가드 한 문장이다.
  - 게으른 완료: 플레이어 상태를 읽는 모든 요청이 먼저 `build_finish ≤ 지금`인 건설을 완료한다(레벨 +1, 성채·성문이면 `keep_level`·`gate_level`도, 일꾼 비움, `build_done` 로그 — version 가드 한 문장). 앱은 업그레이드를 다시 보내지 않는다.
  - 효과: 영웅 슬롯 = `keep_slot_tiers`(성채 단계 `레벨:값|…`), 성 HP = `castle_hp` + `castle_hp_per_level` × (성채 − 1), 인구(`player.population`) = `pop_base` + `pop_per_house` × (민가 − 1) + 연구 `pop_add`, 모집 확률 + 주점 × `tavern_ssr_per_level`·`tavern_sr_per_level`. 성 내부(`keep_interior_tiers`)·성문 HP는 앱이 쓴다. 연구소 레벨은 연구 잠금·속도만 정한다(개정 24, 영웅 공격 보너스 `lab_atk_per_level`은 없앴다).
  - Neon: 007 마이그레이션과 시드(건물 표, 설정 `hero_slots` 삭제·건물 설정 9개)를 새 서버와 같이 올린다.
- 병사(개정 13, 마이그레이션 008: `soldier_defs` = `data/soldiers.csv`, `player_soldiers(type, tier, count ≥ 0)`, `player_state.soldier_deploy`, 기존 플레이어에게 `archery`·`stable` 행(레벨 1), 막사 포함 병사 건물 생산 시각 = 지금)
  - 개정 16: 자동 생산은 없다(시간이 흘러도 보유는 그대로). 병사 건물(`soldiers.csv`의 `building`)마다 훈련 대기열 하나(마이그레이션 010: `player_buildings.train_count`·`train_finish`, 비면 0·null — 제약 `train_queue`).
  - 훈련 시작(개정 19): 건물 레벨이 정한 티어 t = min(최대, 1 + ⌊(L−1)/k⌋)(k = `train_base_min`/`train_step_min`) n마리(1..`train_batch_base` + `train_batch_per_level` × (L−1)), 비용 = `train_cost_<병종>`("자원:수|…", "0"이면 무료) × `train_cost_tier_mult`^(t−1) × n을 바로 뺀다. 끝나는 시각 = 지금 + n × 1마리 시간((`train_base_min` − `train_step_min` × ((L−1) mod k)) 분). 레벨이 올라도 진행 중인 묶음은 티어(`train_tier`)·끝나는 시각 그대로다. 수령은 그 티어에 더한다.
  - 수령: 끝났으면 보유 += n, 대기열 비움. 취소: 진행 중이면 비용의 50%(자원마다 내림) 환불. 차감·대기열·보유·`economy_log`(`train_start`·`train_collect`·`train_cancel`)는 version 가드 한 문장이다. 앱은 시작·취소를 다시 보내지 않는다(수령은 멱등이라 다시 보내도 된다).
  - Neon: 010 마이그레이션과 시드(설정 `train_*` 5개)를 새 서버와 같이 올린다.
  - 합성: 티어 t `soldier_merge_count`마리 → t+1 한 마리(HP·공격 × `soldier_tier_mult`, 앱이 계산). 배치는 보유로 자른다. 보유·배치·`economy_log`(`soldier_merge`)는 version 가드 한 문장이다. 앱은 합성을 다시 보내지 않는다.
  - 막사는 영웅 HP를 올리지 않는다(`barracks_hp_per_level` 삭제).
  - Neon: 008 마이그레이션과 시드(병종 표, 건물 표 2행·막사 이름, 설정 `soldier_*` 5개 추가·`barracks_hp_per_level` 삭제)를 새 서버와 같이 올린다.
- 연구 테크트리(개정 24, 마이그레이션 016: `research_defs` = `data/research.csv`, `player_research(id, level ≥ 0)`, `player_state.research_id`·`research_finish`(둘 다 null이거나 둘 다 값), 연구 설정 5개 기본값, `lab_atk_per_level` 삭제)
  - 한 번에 하나(건설 일꾼과 따로). 시작 조건: 진행 중 없음 → 최대 레벨 아님 → 연구소 Lv ≥ `lab_req`·선행 `req1`·`req2` ≥ `req1_lv`·`req2_lv` → 자원·골드.
  - n → n+1 비용 = round(값 × `research_cost_growth`^n)(자원·골드, 시작할 때 전부 뺀다), 시간 = round(`base_sec` × `research_time_growth`^n ÷ (1 + 속도)), 속도 = `research_speed_pct`/100 + `lab_research_speed_per_level` × (연구소 − 1). 거듭제곱은 곱셈 n번(앱과 같은 반올림).
  - 게으른 완료: 플레이어 상태를 읽는 모든 요청이 먼저 `research_finish ≤ 지금`인 연구를 완료한다(레벨 +1, 진행 비움, `research` 로그 `done` — version 가드 한 문장). 차감·환불·다이아·진행·레벨·`economy_log`(`research`: `start`·`cancel`·`finish`·`done`)도 version 가드 한 문장이다. 앱은 연구 요청을 다시 보내지 않는다.
  - 효과 합계 = 노드마다 레벨(0..`max_level`) × `per_level`을 effect별로 더한다(`rules.researchBonus`). 서버가 쓰는 효과(b = 합계):
    - 생산: 분당 = floor(`per_min` × 레벨 × (100 + `<자원>_pct` + `res_pct`) / 100), 수집량 = 분 수 × 분당(`/v1/collect`, 업그레이드 자동 수집)
    - 건설 시간 = round(기존 ÷ (1 + `build_speed_pct`/100))
    - 판매 = 자원마다 floor(기존 × (100 + `sell_pct`) / 100)
    - 처치 골드 = 처치 1회 tenths마다 floor(기존 × (100 + `kill_gold_pct`) / 100)
    - 훈련 시간 = n × 1마리 시간 ÷ (1 + `train_speed_pct`/100)(반올림 없음), 훈련 비용 = 자원마다 round(기존 × (100 − `train_cost_pct`) / 100)(0인 자원은 뺀다, 취소 환불도 이 비용의 절반)
    - 인구 + floor(`pop_add`)
    - 병종·영웅·스킬·성·성문 효과는 앱(전투)만 쓴다.
  - Neon: 016 마이그레이션과 시드(연구 표, 설정 5개 추가·`lab_atk_per_level` 삭제)를 새 서버와 같이 올린다.
- 영웅(개정 10)
  - 새 플레이어는 `starter_heroes`를 copies 1로 받고, 배치는 그 순서다. 마이그레이션 005는 기존 플레이어에게 같은 것을 채운다.
  - 응답 `deploy`의 길이는 슬롯 수(`keep_slot_tiers`의 성채 단계 값)다. 표에서 빠진 영웅은 `heroes`·`deploy`에서 거른다.
  - 모집: 가능 조건은 `floor(gold_tenths / 10) ≥ 비용`이고 `비용 × 10`을 뺀다. 장마다 등급(SSR `gacha_rate_ssr`, SR `gacha_rate_sr`, 나머지 R)을 정하고 그 등급 안에서 균등하게 뽑는다. 다이아 10연차에 SR 이상이 `gacha_10_min_sr`장보다 적으면 뒤에서부터 R을 SR로 바꾼다(골드 10연차는 보장 없음, 비용은 1회 × 10). 난수는 암호학적 난수(`randomBytes`)다.
  - 골드 차감·copies 증가·`economy_log`(`gacha`)는 version 가드 한 문장이다. 같은 순간 두 번 보내도 골드가 1회분이면 하나는 409다. 앱은 모집을 다시 보내지 않는다.
- 영웅 승급(개정 15, 마이그레이션 009 `player_heroes.shards`·`promotion`, 기존 행은 조각 = copies − 1·승급 0)
  - 모집에서 이미 가진 영웅이 다시 나오면 copies +1, 조각 +1이다(새 영웅은 조각 0).
  - 승급 p → p+1에 조각 `promote_shards`의 p번째(`5|25|50|100|200`)를 쓴다. 최대 승급은 5다. 능력치 배율 `promote_mult`^p는 앱이 계산한다.
  - 조각 차감·승급 +1·`economy_log`(`promote`)는 version 가드 한 문장이다. 같은 순간 두 번 보내도 조각이 1회분이면 하나는 409다. 앱은 승급을 다시 보내지 않는다.
  - Neon: 009 마이그레이션(시드 전에도 승급 설정 기본값을 넣는다)과 시드(설정 `promote_shards`·`promote_mult`·`hero_max_level_per_promotion` 추가, 옛 별 설정 3개(별 보너스·최대 별·별당 최대 레벨)는 시드가 지운다)를 새 서버와 같이 올린다.
- 영웅 레벨업(개정 11, 마이그레이션 006 `player_heroes.level`)
  - 최대 레벨 = `hero_max_level_base` + `hero_max_level_per_promotion` × 승급(개정 15).
  - L → L+1 비용: 골드(정수) = round(`levelup_gold_<등급>` × 1.12^(L−1)), 식량 = `levelup_food_<등급>` × L. count번이면 그 합이다. 골드는 `floor(gold_tenths / 10)`로 판정하고 × 10을 뺀다.
  - 골드·식량 차감, 레벨 증가, `economy_log`(`levelup`)는 version 가드 한 문장이다. 앱은 레벨업을 다시 보내지 않는다(실패하면 알림 + 상태 새로 받기).
  - Neon: 006 마이그레이션과 시드(레벨업 설정 9개)를 새 서버와 같이 올린다.

## 동시성

같은 플레이어의 요청이 겹쳐도 두 번 수집되거나 골드가 꼬이지 않는다. Neon HTTP 드라이버에는 대화형 트랜잭션이 없다. 그래서 변경은 다음 순서로 한다.

1. 플레이어 상태와 `player_state.version`을 읽고, 규칙으로 변경을 계산한다.
2. **한 문장(CTE)**으로 쓴다.
   - 먼저 `update player_state ... set version = version + 1 where player_id = $1 and version = $읽은값 returning player_id`를 한다.
   - 자원·건물·골드 갱신과 `economy_log` 기록은 그 결과 행이 있을 때만 적용된다(`where player_id = (select player_id from s)`).
3. 갱신된 행이 없으면 다른 요청이 먼저 바꾼 것이다. 다시 읽고 다시 계산한다(재시도 3회). 그래도 안 되면 409를 준다.

테스트(`test/concurrency.test.ts`)는 다음을 확인한다.

- 두 요청이 같은 version을 읽도록 쿼리를 붙잡아 둔다. 그래도 수집과 판매는 한 번만 일어난다.
- 쓰기 직전마다 다른 쓰기가 끼어들면 4번 시도한 뒤 409를 주고, 아무것도 바뀌지 않는다.

## Neon 배포 (사용자 몫)

1. [Neon](https://neon.tech)에서 프로젝트를 만든다. 접속 문자열을 복사한다(`postgresql://...?sslmode=require`).
2. JWT 비밀을 만든다(32바이트 이상 무작위).

   ```bash
   node -e "console.log(require('node:crypto').randomBytes(48).toString('base64url'))"
   ```

3. 마이그레이션과 시드를 적용한다. Neon 접속 정보는 `server/.env.neon`에 둔다(git 제외). `server/.env`에는 두지 않는다. `npm run dev`가 `.env`를 읽기 때문에, 거기 두면 로컬 개발 서버가 운영 DB에 쓴다.

   ```bash
   # server/.env.neon
   # DATABASE_URL=postgresql://...?sslmode=require
   # JWT_SECRET=<위에서 만든 값>
   npm --prefix server run neon:migrate
   npm --prefix server run neon:seed
   npm --prefix server run neon:start   # Neon에 붙은 서버를 로컬에서 띄운다(확인용, PORT로 포트 지정)
   ```

   - 2026-10-01: 프로젝트 Neon DB(`ep-divine-credit-azirouja`, ap-southeast-1, PostgreSQL 18)에 001·002를 적용하고 시드했다. API 전 경로와 게임 접속을 확인했고, 시험 계정은 지웠다.

   - **개정 10 올리기(003~005)는 마이그레이션·시드·새 서버 배포를 한 번에 한다.**
     - 003은 `player_state.gold`를 `gold_tenths`로 바꾸고, 004는 `hero_roles`를 지운다. 그래서 개정 9 서버는 마이그레이션이 적용되는 순간부터 깨진다.
     - 순서: 옛 서버를 멈춘다(또는 잠깐 끊기는 것을 받아들인다) → `neon:migrate` → `neon:seed` → 새 서버를 배포한다. 시드까지 끝나야 새 서버가 영웅 표·모집 설정을 읽는다.
     - 파일마다 한 트랜잭션이라 중간에 실패하면 그 파일은 적용되지 않는다. 001+002 DB에 실제 행이 있을 때 003~005로 올리는 경우는 `test/seed.test.ts`로 확인했다.
     - 시드 전에 새 서버가 떠도 새 플레이어는 스펙 기본 시작 영웅(`hans|ella|dorik|nina`)을 받는다(마이그레이션 005와 같은 기본값).

   - seed는 `data/*.csv`로 기획 표를 덮어쓴다. CSV에서 사라진 키는 DB에서 지운다.
   - CSV에 오류가 있으면 파일·줄·열을 출력하고, 아무것도 쓰지 않는다.
   - 운영 중 수치 조정은 Neon 콘솔 SQL 편집기에서 한다. DB가 진실이다. 다시 시드하면 CSV 값으로 덮어써진다.
4. 호스팅(Fly.io, Render, Railway, VPS 등 Node 24를 돌리는 곳)에 `server/`를 올린다.
   - 환경 변수 `DATABASE_URL`, `JWT_SECRET`, `CORS_ORIGINS`(웹 빌드 출처), `PORT`를 설정한다.
   - 실행 명령은 `node src/main.ts`다(작업 디렉터리 `server/`). 운영 모드는 시작할 때 마이그레이션·시드를 하지 않는다. 3단계로 먼저 적용한다.
   - Vercel·Cloudflare Workers처럼 Node 서버가 아닌 곳은 `src/app.ts`의 `createApp`을 그 플랫폼 진입점에 연결해야 한다. 지금 코드는 `node:fs`·`node:crypto`를 쓰므로 그 플랫폼의 Node 호환 모드가 필요하다(확인하지 않음).
5. 앱 프로젝트 설정 `castle/api_base_url`에 서버 주소(`https://...`)를 넣고 **릴리스로** 빌드한다(`--export-release`).

   ```bash
   ./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Web" export/web/index.html
   ```

   - 릴리스 빌드는 `--api=<url>`(네이티브)·`?api=<url>`(웹)을 무시하고 설정 주소만 쓴다.
   - 디버그 빌드는 이 인자를 받는다. 그래서 디버그 빌드를 배포하면 `?api=https://다른-서버` 링크 하나로 기기 id(게스트 계정 열쇠)가 남의 서버로 간다.
   - `dev/build-web.sh`는 개발용 디버그 빌드(`--export-debug`)다. 배포에 쓰지 않는다.

## 비밀 관리

- `DATABASE_URL`과 `JWT_SECRET`은 서버 환경 변수에만 둔다. 앱, 저장소, 로그, 스크린숏에 넣지 않는다.
  - DB 접속 문자열이 앱에 들어가면 누구나 모든 플레이어 데이터를 읽고 쓸 수 있다.
- `server/.env`는 git에서 제외된다. `.env.example`에는 자리표시자만 둔다.
- 운영에서는 `CORS_ORIGINS`를 웹 빌드 출처로 정한다. 인증이 Bearer 헤더라 `*`여도 CSRF 위험은 없지만, 다른 사이트의 브라우저 코드가 API를 부르지 못하게 한다.
- `JWT_SECRET`을 바꾸면 기존 토큰이 전부 401이 된다. 앱은 다시 게스트 로그인하므로 데이터는 그대로다(기기 id가 계정 열쇠).
- 접속 문자열이 새면 Neon 콘솔에서 DB 역할 비밀번호를 재설정한다.
- 시작 거부 조건(`src/env.ts`):
  - `DATABASE_URL`이 있는데 `JWT_SECRET`이 없거나 32자 미만이다.
  - `DATABASE_URL`과 `ALLOW_TEST_HOOKS=1`이 같이 있다. 켜면 누구나 자기 건물 시계를 앞당길 수 있다.
  - 고정 개발 비밀(`JWT_SECRET` 없음)인데 `HOST`가 루프백이 아니다.

## 알려진 한계

- **같은 기기 id로 두 곳에서 동시에 하면 한쪽 처치 골드가 사라진다.**
  - `seq`는 플레이어마다 하나다. 웹은 탭끼리 IndexedDB를 같이 쓰므로, 두 번째 탭도 같은 기기 id(같은 플레이어)로 로그인한다.
  - 두 번째 탭의 `seq`는 보통 서버 `kill_seq` 이하라서, 그 탭의 처치 보고는 재전송으로 취급되고 골드 0이다.
  - 이번 개정에서는 고치지 않는다. 고친다면 세션마다 `seq` 공간을 따로 두는 계약 변경이 필요하다.
- 웹에서 브라우저 저장소가 영구가 아니면(사생활 모드, IndexedDB 차단) 기기 id가 남지 않는다. 다음 방문은 새 게스트 계정이다.
  - 앱은 이때 경고 로그를 남기고, 접속 화면과 화면 아래 띠에 "브라우저 저장소가 꺼져 있어 진행이 저장되지 않을 수 있습니다"를 한 줄 보인다. 게임은 계속된다.

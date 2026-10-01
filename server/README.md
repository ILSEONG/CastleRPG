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
| `src/main.ts` | 환경 변수를 읽고 서버를 시작한다. 개발 모드면 마이그레이션을 적용하고, 기획 표가 비어 있으면 시드한다. |
| `src/app.ts` | Hono 앱 팩토리 `createApp({query, now, jwtSecret, allowTestHooks, corsOrigins})`. 엔드포인트 전부가 여기 있다. |
| `src/rules.ts` | 경제 규칙(순수 함수, 시간 인자): 수집, 시세, 판매, 스테이지 연장, 처치 골드·상한. |
| `src/db.ts` | Neon/PGlite `query`, 마이그레이션 러너(`schema_migrations`). |
| `src/seed.ts` | `data/*.csv`를 검증하고 기획 표에 upsert한다. 사라진 키는 지운다. |
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
| `JWT_SECRET` | HS256 비밀. `DATABASE_URL`이 있는데 비어 있으면 **시작을 거부한다**. |
| `CORS_ORIGINS` | 허용할 출처(쉼표 목록). 비우면 `*`다. |
| `PORT` | 기본 8787이다. |
| `ALLOW_TEST_HOOKS` | `1`이면 `POST /v1/test/age`가 생긴다. 운영에서는 비워 둔다. |
| `HOST` | (선택) 듣는 주소. 기본은 개발 `127.0.0.1`, 운영 `0.0.0.0`이다. |
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
  - 동시 수집·판매
  - 409
  - 시세 분포
  - 처치 골드·상한
  - 스테이지 클리어 멱등
  - gamedata version
  - 테스트 훅 404
  - 플레이어 격리

## API 요약 (스펙 §4)

모든 요청과 응답은 JSON이다. 시각은 유닉스 초(float)다. 오류는 `{"error": "<code>", "message": "..."}` 형식에 400·401·404·409·500을 쓴다.

| 요청 | 인증 | 응답 |
|---|---|---|
| `GET /v1/health` | - | `{ok, server_now}` |
| `POST /v1/auth/guest {device_id}` | - | `{token, player_id}`. device_id는 16~128자 `[A-Za-z0-9-]`, 토큰은 30일 유효 |
| `GET /v1/gamedata` | - | `{version, monsters, stages, heroes, resources, config}`. `ETag` = `"version"`이고, `If-None-Match`가 맞으면 304 |
| `GET /v1/player` | Bearer | 플레이어 응답 |
| `POST /v1/collect {building}` | Bearer | 플레이어 응답 + `amount` |
| `POST /v1/sell {res}` | Bearer | 플레이어 응답 + `gold_gained`, `rate`. res는 자원 id 또는 `"all"` |
| `POST /v1/kills {stage, kills}` | Bearer | 플레이어 응답 + `gold_gained` |
| `POST /v1/stage/clear {stage}` | Bearer | 플레이어 응답 |
| `POST /v1/test/age {minutes}` | Bearer | 플레이어 응답. `ALLOW_TEST_HOOKS=1`일 때만 있다 |

플레이어 응답은 다음과 같다.

```
{server_now, player: {gold, res: {wood, stone, food}, stage, keep_level, gate_level,
 buildings: {lumber: {level, last_collect}, quarry: ..., farm: ...}}, merchant: {rate, next_change}}
```

- 처치 상한
  - 총 처치 수 상한은 `ceil(지난 보고 이후 초 × kill_rate_cap) + 20`이다.
  - 넘는 만큼은 **싼 몬스터부터 인정**하고, 비싼 몬스터를 먼저 버린다.
  - 버린 일이 있으면 `economy_log`에 `clamped: true`를 남긴다.
- 시세는 시간 칸(`floor(유닉스 초 / 3600)`)을 시드로 한 mulberry32로 결정적으로 계산한다. 분포 값은 `game_config`에서 읽는다.

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

3. 마이그레이션과 시드를 적용한다. 로컬 `server/.env`에 `DATABASE_URL`을 넣거나, 셸 환경 변수로 준다.

   ```bash
   npm --prefix server run migrate
   npm --prefix server run seed
   ```

   - seed는 `data/*.csv`로 기획 표를 덮어쓴다. CSV에서 사라진 키는 DB에서 지운다.
   - CSV에 오류가 있으면 파일·줄·열을 출력하고, 아무것도 쓰지 않는다.
   - 운영 중 수치 조정은 Neon 콘솔 SQL 편집기에서 한다. DB가 진실이다. 다시 시드하면 CSV 값으로 덮어써진다.
4. 호스팅(Fly.io, Render, Railway, VPS 등 Node 24를 돌리는 곳)에 `server/`를 올린다.
   - 환경 변수 `DATABASE_URL`, `JWT_SECRET`, `CORS_ORIGINS`(웹 빌드 출처), `PORT`를 설정한다.
   - 실행 명령은 `node src/main.ts`다(작업 디렉터리 `server/`). 운영 모드는 시작할 때 마이그레이션·시드를 하지 않는다. 3단계로 먼저 적용한다.
   - Vercel·Cloudflare Workers처럼 Node 서버가 아닌 곳은 `src/app.ts`의 `createApp`을 그 플랫폼 진입점에 연결해야 한다. 지금 코드는 `node:fs`·`node:crypto`를 쓰므로 그 플랫폼의 Node 호환 모드가 필요하다(확인하지 않음).
5. 앱 프로젝트 설정 `castle/api_base_url`에 서버 주소(`https://...`)를 넣고 빌드한다.

## 비밀 관리

- `DATABASE_URL`과 `JWT_SECRET`은 서버 환경 변수에만 둔다. 앱, 저장소, 로그, 스크린숏에 넣지 않는다.
  - DB 접속 문자열이 앱에 들어가면 누구나 모든 플레이어 데이터를 읽고 쓸 수 있다.
- `server/.env`는 git에서 제외된다. `.env.example`에는 자리표시자만 둔다.
- `JWT_SECRET`을 바꾸면 기존 토큰이 전부 401이 된다. 앱은 다시 게스트 로그인하므로 데이터는 그대로다(기기 id가 계정 열쇠).
- 접속 문자열이 새면 Neon 콘솔에서 DB 역할 비밀번호를 재설정한다.
- 운영에서는 `ALLOW_TEST_HOOKS`를 켜지 않는다. 켜면 누구나 자기 건물 시계를 앞당길 수 있다.

# CastleRPG 개정 8: 몬스터·스테이지 데이터 표

작성일: 2026-10-01
기반: 개정 2~7. 충돌 시 이 문서가 우선한다.
계기: 사용자 질문. "스테이지별로 적 유닛의 체력, 공격력, 뱉는 골드 등도 달라야 하지 않나? 관리는 DB로 하는 게 맞지 않나?"

## 1. 결정: DB 대신 데이터 표(CSV)

- **지금**: HP·공격력은 `Balance.hp_scale/atk_scale` 공식(스테이지당 +25%/+15%)으로 오르고, 처치 골드는 고정이다. 수치가 코드 공식 안에 있어서 기획 조정이 불편하다.
- **SQLite 같은 DB를 쓰지 않는 이유**:
  - 웹 빌드는 GDExtension을 못 쓴다("no GDExtension support"). 그래서 SQLite 플러그인이 웹에서 돌지 않는다.
  - 오프라인 싱글 게임의 읽기 전용 밸런스 값에는 DB가 과하다.
- **업계 표준**: 기획 표(스프레드시트)를 CSV로 두고 게임이 시작할 때 읽는다. 엑셀이나 구글 시트로 열어 고치고, git에서 줄 단위 변경이 보인다.
- **나중**: 서버가 생기면 같은 표를 원격 설정으로 덮어써서 앱 업데이트 없이 수치를 바꾼다. 그때도 표 형식은 그대로다.

## 2. 표

`data/monsters.csv`: 몬스터 종류별 기본값(스테이지 1).

| 열 | 뜻 |
|---|---|
| id | grunt, epic_boss |
| hp, atk, speed, range, atk_interval, aggro, scale | 기존 `Balance.MONSTER` 값 그대로 |
| gold | 처치 골드 기본값 (grunt 2, epic_boss 50) |

`data/stages.csv`: 스테이지별 배율과 웨이브.

| 열 | 뜻 |
|---|---|
| stage | 1부터 빠짐없이 오름차순 |
| hp_mult, atk_mult, gold_mult | 몬스터 기본값에 곱한다 |
| waves, wave_size | 스테이지 모드 웨이브 수, 웨이브당 졸개 수 |
| idle_interval | 방치 모드 스폰 간격(초) |

- 1~30행은 지금 공식으로 채운다(동작 불변).
  - hp_mult = 1 + 0.25(s−1)
  - atk_mult = 1 + 0.15(s−1)
  - waves = 3 + floor(s/3)
  - wave_size = 6 + 2s
  - idle_interval = 4
  - gold_mult = 1 + 0.2(s−1)은 신규다.
- 마지막 행 너머의 스테이지는 마지막 10행의 평균 기울기로 직선 연장한다(정수 열은 반올림). 몇 행마다 한 칸씩 오르는 열(waves)도 고르게 이어진다. 방치형이라 스테이지 끝이 없다.
- 처치 골드 = round(gold × gold_mult)이고, 최소 1이다.

## 3. 코드

- 신규 `scripts/game_data.gd`(정적, 처음 쓸 때 한 번 읽고 캐시):
  - `monster(id) -> Dictionary`
  - `stage(n) -> Dictionary`: 연장 포함, 키는 표 열 이름
  - `kill_gold(id, stage) -> int`
  - CSV 처리:
    - 헤더 이름으로 열을 찾는다(열 순서 무관).
    - 엑셀이 붙이는 UTF-8 BOM과 빈 줄을 무시한다.
    - 숫자로 바꾸지 못하는 칸, 빠진 열, stage가 1부터 이어지지 않는 경우는 `push_error`로 어느 파일·행·열인지 알린다.
- `Balance`에서 `MONSTER`와 `hp_scale`, `atk_scale`, `wave_count`, `wave_size`, `idle_interval`을 지운다. 같은 값이 두 곳에 있지 않게 하려는 것이다. 호출부(monster, spawner, wave_director, 테스트)는 GameData를 쓴다.
- CSV 임포트:
  - Godot는 .csv를 번역 파일로 임포트한다. 그래서 `data/*.csv.import`를 `importer="keep"`로 둔다.
  - 내보내기 `include_filter`에 `data/*.csv`를 넣어 웹·모바일 빌드에 원본 파일이 들어가게 한다.

## 4. 테스트

- **로직**:
  - 표를 읽는다.
  - 1~30행 값이 이전 공식과 같다(gold 제외).
  - 31행 이상은 직선 연장이다.
  - kill_gold는 반올림하고 최소 1이다.
  - BOM·빈 줄·열 순서가 바뀐 CSV(임시 파일)도 같은 결과를 낸다.
  - 깨진 표는 오류를 알린다(오류 수를 세어 확인).
- **AI 체크**: 처치 골드는 `GameData.kill_gold("grunt", stage)`와 같다(스테이지 1 = 2).
- **엔드투엔드**: 스테이지 1→2(기존).
- **내보내기 확인**: `--export-pack`으로 pck를 만들어 `--main-pack`으로 헤드리스 실행한다. 표가 읽히고 스테이지가 클리어되면 성공이다. 웹 빌드에서 몬스터가 나오는지도 확인한다(컨트롤러 캡처).

## 5. 범위 밖

몬스터 새 종류, 스테이지별 보스 종류, 챕터·레전드 보스, 원격 설정.

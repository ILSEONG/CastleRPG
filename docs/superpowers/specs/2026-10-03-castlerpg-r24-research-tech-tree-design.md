# CastleRPG 개정 24: 연구소 테크트리

작성일: 2026-10-03
기반: 개정 12(건물)·13(병사)·16/19(훈련)·20(성장)·23(다이아). 충돌 시 이 문서가 우선한다. 사용자 지시에 따라 묻지 않고 진행한다.

계기(사용자): "연구소는 연구 테크트리를 연구하는 건물이야. 다른 SLG 게임을 참고해서 적절하게 만들어봐"

참고한 SLG 공통 규칙(라이즈 오브 킹덤즈 아카데미, 로드 모바일 연구소, 화이트아웃 서바이벌 연구센터)은 다음과 같다.
- 분야별 트리(경제 / 군사 / …)
- 노드마다 여러 레벨(효과가 쌓인다)
- 선행 노드 레벨과 연구소 레벨로 잠금을 푼다
- 자원과 시간을 쓴다
- 한 번에 하나만 연구한다(건설 일꾼과 따로)
- 시간이 지나면 자동 완료된다
- 유료 재화로 즉시 완료할 수 있다
- 취소하면 일부를 돌려준다

## 1. 연구소의 역할 변경

- **연구소 레벨이 영웅 공격을 직접 올리던 보너스(`lab_atk_per_level`, 개정 12)는 없앤다.** 그 효과는 연구 "무기 연마"·"전설의 무기"로 옮긴다.
- 연구소 레벨이 하는 일은 두 가지다.
  - 상위 연구를 연다: 노드마다 `lab_req`가 있다.
  - 연구 속도를 올린다: 레벨당 +2%다(`lab_research_speed_per_level` 0.02 × (L−1)). Lv30이면 +58%다.
- 건물 창 연구소 설명: "기술을 연구합니다. 레벨이 오르면 상위 연구가 열리고 연구 속도가 빨라집니다."
- 건물 창에 **[연구]** 버튼을 크게 두고, 누르면 연구 창이 열린다.
- HUD 팁 "연구소 레벨이 오르면 영웅 공격력이 강해집니다"는 "연구소에서 기술을 연구하면 영웅·병사·경제가 강해집니다"로 바꾼다.

## 2. 테크트리 (기획 표 `data/research.csv` = DB `research_defs`)

```csv
id,branch,tier,name,effect,per_level,max_level,lab_req,req1,req1_lv,req2,req2_lv,wood,stone,food,gold,base_sec
wood_tech,economy,1,벌목술,wood_pct,5,10,1,,,,,120,80,100,0,60
stone_tech,economy,1,채석술,stone_pct,5,10,1,,,,,120,80,100,0,60
food_tech,economy,1,농경술,food_pct,5,10,1,,,,,120,80,100,0,60
construct,economy,2,건축학,build_speed_pct,3,10,3,wood_tech,3,stone_tech,3,400,300,350,500,300
commerce,economy,2,상업,sell_pct,3,10,3,food_tech,3,,,400,300,350,500,300
plunder,economy,3,전리품 수집,kill_gold_pct,5,10,6,commerce,5,,,900,700,800,2000,900
method,economy,3,연구 방법론,research_speed_pct,3,10,6,construct,5,,,900,700,800,2000,900
abundance,economy,4,풍요,res_pct,3,10,12,plunder,5,method,5,2000,1600,1800,6000,1800
inf_drill,military,1,보병 훈련,inf_pct,3,10,1,,,,,120,80,100,0,60
arc_drill,military,1,궁병 훈련,arc_pct,3,10,1,,,,,120,80,100,0,60
cav_drill,military,1,기병 훈련,cav_pct,3,10,1,,,,,120,80,100,0,60
wall_fort,military,2,성벽 보강,castle_hp_pct,5,10,3,inf_drill,3,,,400,300,350,500,300
gate_fort,military,2,성문 보강,gate_hp_pct,5,10,3,arc_drill,3,,,400,300,350,500,300
drill_manual,military,3,훈련 교범,train_speed_pct,3,10,6,inf_drill,5,cav_drill,5,900,700,800,2000,900
logistics,military,3,보급술,train_cost_pct,2,10,6,arc_drill,5,,,900,700,800,2000,900
barracks_ext,military,4,병영 확장,pop_add,1,5,10,drill_manual,5,logistics,5,2000,1600,1800,6000,1800
elite,military,5,정예 전술,soldier_pct,3,10,15,barracks_ext,3,wall_fort,5,4000,3000,3500,15000,3600
hero_weapon,hero,1,무기 연마,hero_atk_pct,3,10,1,,,,,120,80,100,0,60
hero_armor,hero,1,갑옷 단련,hero_hp_pct,3,10,1,,,,,120,80,100,0,60
arcana,hero,2,비전 연구,skill_pct,4,10,5,hero_weapon,5,hero_armor,5,900,700,800,2000,900
legend_weapon,hero,3,전설의 무기,hero_atk_pct,4,10,15,arcana,5,,,4000,3000,3500,15000,3600
legend_armor,hero,3,불굴의 의지,hero_hp_pct,4,10,15,arcana,5,,,4000,3000,3500,15000,3600
```

- 분야: economy = **경제**, military = **군사**, hero = **영웅**. 탭 순서도 이대로다.
- 선행 조건: 연구소 Lv ≥ `lab_req`, req1 Lv ≥ `req1_lv`, req2 Lv ≥ `req2_lv`. 빈 칸은 조건이 없다.
- 비용(현재 레벨 n → n+1, n은 0부터): 자원 r마다 round(값 × `research_cost_growth`^n)이다. `research_cost_growth`는 1.3이다.
  - 곱셈 순서는 GameData._grown과 같은 반복 곱셈이다(서버와 반올림 일치).
- 시간: round(base_sec × `research_time_growth`^n ÷ (1 + 연구 속도))이다. `research_time_growth`는 1.35다.
  - 연구 속도 = research_speed_pct/100 + 연구소 보너스
  - 예: 벌목술 1레벨은 60초, 10레벨은 약 15분이다. 정예 전술 10레벨은 약 15시간이다(보너스 없이).
- 효과는 노드 레벨 × per_level이다. 같은 effect를 쓰는 노드끼리는 더한다(예: hero_atk_pct = 무기 연마 + 전설의 무기).

### 효과 키와 적용

| effect | 단위 | 적용 | 권위 |
|---|---|---|---|
| wood_pct / stone_pct / food_pct, res_pct | % | 분당 생산 = floor(per_min × L × (1 + (해당 자원% + res_pct)/100)) | 서버(수집) + 앱(표시·오프라인) |
| build_speed_pct | % | 건설 시간 = round(기존 ÷ (1 + b/100)) | 서버 + 앱 |
| research_speed_pct | % | 위 시간 공식 | 서버 + 앱 |
| sell_pct | % | 상인 판매 금액 × (1 + b/100), 내림 | 서버 + 앱 |
| kill_gold_pct | % | 처치 골드 × (1 + b/100), 골드 1/10 단위에서 내림 | 서버 + 앱 |
| inf_pct / arc_pct / cav_pct, soldier_pct | % | 그 병종 공격·HP × (1 + (병종% + soldier_pct)/100), 성장(개정 20)과 곱 | 앱(전투) |
| train_speed_pct | % | 훈련 시간 ÷ (1 + b/100) | 서버 + 앱 |
| train_cost_pct | % | 훈련 비용 × (1 − b/100), 반올림 | 서버 + 앱 |
| pop_add | 명 | 인구 + n | 서버 + 앱 |
| castle_hp_pct / gate_hp_pct | % | 성 / 성문 최대 HP × (1 + b/100) | 앱 |
| hero_atk_pct / hero_hp_pct | % | 영웅 공격 / HP × (1 + b/100), 성장과 곱(연구소 레벨 보너스 대체) | 앱 |
| skill_pct | % | 영웅 스킬 피해 × (1 + b/100) | 앱 |

- 효과 합계는 GameData의 순수 함수 하나 `research_bonus(levels) -> {effect: 합}`로 둔다. 서버 rules에도 같은 함수를 둔다.
- 능력치를 다시 읽는 공용 지점(개정 20 hero.gd·soldier.gd·GameState.apply_levels)에 넣는다.
- 연구 완료는 즉시 반영한다. 방치 모드든 스테이지 중이든 다음 계산부터 적용한다. 성·성문 HP는 최대치만 올리고, 현재 HP는 같은 비율로 올린다.

## 3. 진행 규칙

- 연구는 **한 번에 하나**다. 건설 일꾼과는 따로 돈다(동시에 가능하다).
- 시작 조건:
  - 진행 중인 연구가 없다
  - 노드가 최대 레벨이 아니다
  - 연구소 레벨과 선행 조건을 채웠다
  - 자원과 골드가 충분하다
  - 비용은 시작할 때 전부 차감한다
- 완료: 끝나는 시각이 지나면 자동 완료된다. 서버는 다음 요청 때 처리한다(건설 완료와 같은 방식). 앱은 알림 "연구 완료: 벌목술 Lv 3"을 띄운다.
- 취소: 그 레벨 비용의 50%(`research_cancel_refund`, 자원마다 내림)를 돌려준다.
- **즉시 완료(다이아)**: 비용 = max(1, ceil(남은 초 ÷ 60) × `research_dia_per_min`)이다. `research_dia_per_min`은 1이다.
  - 버튼은 "💎 N 즉시 완료"다. 다이아가 부족하면 비활성이다.
- 설정 키를 새로 둔다(config.csv, 서버 검증):
  - `research_cost_growth` 1.3
  - `research_time_growth` 1.35
  - `lab_research_speed_per_level` 0.02
  - `research_cancel_refund` 0.5
  - `research_dia_per_min` 1
- `lab_atk_per_level`은 지운다.

## 4. 서버

- 마이그레이션 **016**:
  - `research_defs`: 열 = csv, ord = 파일 순서, seed가 넣는다. 검증은 다음과 같다.
    - 알려진 branch·effect만
    - 숫자는 0 이상
    - max_level ≥ 1
    - req는 표 안의 id여야 하고, req_lv ≤ 그 노드의 max_level
  - `player_research(player_id, id, level ≥ 0, pk)`
  - `player_state.research_id text`, `research_finish timestamptz`
- 경로:
  - `POST /v1/research/start {id}`
    - 404 `unknown_research`
    - 409 `research_busy` / `max_level` / `locked` / `not_enough_resources` / `not_enough_gold`
  - `POST /v1/research/cancel` → 409 `no_research`
  - `POST /v1/research/finish` → 409 `no_research` / `not_enough_diamonds`
  - 모두 원자적이다(버전 가드 한 문장). 로그 `research`(action, id, level)를 남긴다.
- 자동 완료: 플레이어 상태를 읽는 모든 경로에서 끝난 연구를 반영한다(건설 COMPLETE와 같은 방식).
- 플레이어 응답: `research: {levels: {id: L}, current: {id, finish} | null}`. gamedata에 `research` 행을 더한다.
- 서버 권위 효과를 수집·건설 시간·판매·처치 골드·훈련 시간·비용·인구 계산에 반영한다.
- 테스트:
  - 비용·시간 공식(연구소 보너스·연구 속도 포함), 잠금(연구소·선행), 바쁨 409, 부족 409
  - 취소 환불, 다이아 즉시 완료 비용, 자동 완료
  - 효과 반영: 수집량, 건설 시간, 판매가, 처치 골드, 훈련 시간·비용, 인구
  - 원자성, 마이그레이션, 시드 검증

## 5. 앱

- GameData:
  - `research_defs()`, `research_def(id)`, `research_cost(id, level)`, `research_sec(id, level, speed)`
  - `research_bonus(levels)`, `research_block(id, levels, lab_level, have)`
- Economy:
  - 상태 `research_levels`, `research_current`
  - `start_research(id)`, `cancel_research()`, `finish_research_now()`
  - `research_left(now)`, `research_progress(now)`, `research_dia_cost(now)`
  - 시그널 `research_changed`, `research_done(id, level)`
  - 온라인은 재전송하지 않는다. 오프라인은 같은 규칙을 따르고, save 다음 버전(**v12**)에 저장한다.
- 오프라인 처리도 서버 권위 효과를 같은 공식으로 반영한다.

### 연구 창(`scripts/research_panel.gd`)

전체 높이 시트다. 던전 시트와 같은 ui_kit 스타일을 쓴다.

- **위**:
  - 제목 "연구소 Lv N"과 "연구 속도 +X%"
  - 진행 중 연구 막대: 아이콘, 이름 "벌목술 Lv 3", 남은 시간, 진행률
  - 막대 옆 버튼: [💎 N 즉시 완료] [취소]
  - 진행 중인 연구가 없으면 "진행 중인 연구 없음 — 연구할 기술을 고르세요"
- **분야 탭**: [경제] [군사] [영웅]
- **트리**: 세로 스크롤로 보여 준다.
  - 단(tier)마다 한 줄이고, 줄 왼쪽에 단 표시가 있다. 연구소 Lv이 모자란 단은 자물쇠와 "연구소 Lv 6 필요"를 보여 준다.
  - 노드 카드에는 아이콘, 이름, "Lv 3/10", 작은 진행 막대(레벨 비율)가 있다.
  - 선행 노드와 이어지는 연결선을 그린다. 조건을 채우면 금색, 아니면 회색이다.
  - 카드 상태:
    - 잠김: 흐림 + 자물쇠
    - 연구 가능
    - 연구 중: 빛나는 테두리 + 남은 시간
    - 최대: 금 테두리 + "MAX"
- **노드 상세**(카드를 누르면 아래에서 뜨는 창):
  - 큰 아이콘, 이름, 한 줄 설명
  - 효과 "현재 +10% → 다음 +15%"
  - 조건 목록: ✓/✗로 연구소 Lv, 선행 노드 Lv을 보여 준다
  - 비용: 자원 아이콘마다 "보유/필요"이고, 부족하면 빨강이다
  - 시간
  - [연구] 버튼: 막힌 이유가 있으면 비활성이고, 그 이유를 한 줄로 보여 준다
  - 진행 중인 노드면 진행 막대와 [💎 즉시 완료] [취소]를 보여 준다
- **아이콘**은 바로 알아보게 만든다(사용자 규칙).
  - 보병·궁병·기병 훈련 노드: **실제 병사 3D 초상**(portraits.gd)
  - 나머지: 로우폴리 그림. 각 아이콘은 다음과 같다.

    | 노드 | 아이콘 |
    |---|---|
    | 벌목술 | 통나무 |
    | 채석술 | 돌 |
    | 농경술 | 밥그릇·밀 |
    | 건축학 | 망치 |
    | 상업 | 저울 |
    | 전리품 | 금화 자루 |
    | 연구 방법론 | 플라스크 |
    | 풍요 | 자원 더미 |
    | 성벽 | 성벽 |
    | 성문 | 성문 |
    | 훈련 교범 | 책 |
    | 보급술 | 수레 |
    | 병영 확장 | 막사 |
    | 정예 전술 | 교차한 검 + 별 |
    | 무기 연마 | 검 |
    | 갑옷 단련 | 흉갑 |
    | 비전 연구 | 마법 구슬 |
    | 전설의 무기 | 빛나는 검 |
    | 불굴의 의지 | 하트 방패 |
- **월드**: 연구가 비어 있고 시작 가능한 노드가 있으면 연구소 위에 작은 플라스크 말풍선을 띄운다. 건설 말풍선과 같은 방식으로 하고, 탭하면 연구 창이 열린다.

### 테스트(앱)

- 로직: 비용·시간·보너스 공식, 잠금, 취소 환불, 즉시 완료 비용, 효과 적용(생산·판매·훈련·인구·HP), save v11 → v12 이전
- AI 체크:
  - 연구 영웅 공격·병종 공격·성 HP가 전투 수치에 반영된다
  - 연구소 레벨만 올려서는 영웅 공격이 오르지 않는다
- 입력 체크:
  - 연구소 건물 창 [연구] → 연구 창
  - 노드 탭 → 상세 → [연구]로 자원이 줄고 진행이 시작된다
  - 두 번째 연구는 막힌다(이유 표시)
  - 다이아 즉시 완료로 Lv이 오른다
  - 취소하면 환불된다
  - 잠긴 노드는 [연구]가 비활성이다
  - 분야 탭 전환
- 통합(online-check): 서버 연구 시작·완료·재접속 복원

## 6. 구현 메모 (스펙이 열어 둔 부분 — 구현하며 정했다)

- **곱셈 순서(서버·앱 반올림 일치)**: 연구 % 효과는 정수 v에 `floor(v × (100 + b) / 100)`로 건다(GameData.pct_floor, 서버 `Math.floor(... * (100 + b) / 100)`).
  - 생산: 분당 생산 = floor(per_min × L × (100 + %) / 100), 수집량 = 분 × 분당 생산.
  - 판매: 자원마다 기존 판매 골드에 건다(여러 자원 판매는 자원마다 내림한 뒤 더한다).
  - 처치 골드: 처치 1회의 tenths에 건다(서버 처치 상한 정렬도 그 값으로).
  - 훈련 비용: 묶음 전체 자원마다 round(v × (100 − b) / 100), 0이 되면 뺀다. 훈련 시간은 반올림하지 않는다.
- **영웅 연구 %**: hero.gd refresh_stats에서 (기본 × 레벨 × 승급 + 장비) × (1 + 성장 %) × (1 + 연구 %)로 곱한다(성장과 같은 자리). `GameData.hero_stats`는 연구·연구소를 모른다 — 영웅 목록 전투력도 성장처럼 연구를 넣지 않는다.
- **비전 연구(skill_pct)**: 따로 들어가는 스킬 피해 — 가르기, 연쇄, 폭발, 독, 가시 반사 — 에 곱한다. 처형·거인 사냥·치명타처럼 기본 타격의 배율은 건드리지 않는다.
- **성·성문 HP**: 건설 완료는 예전처럼 늘어난 만큼 더하고, 연구 완료는 같은 비율로 올린다(`GameState.apply_levels(by_ratio)`, main이 `research_done`에서 부른다). 부서진 성문은 그대로다.
- **이유 코드 순서**: 404 unknown_research → research_busy → max_level → locked → not_enough_resources → not_enough_gold. 앱도 같고(상세 창 이유 줄), 진행 중이면 "다른 연구가 진행 중입니다 (벌목술 12:34)"처럼 무엇이 도는지 붙인다.
- **취소 환불**: 골드도 50%(내림)를 돌려준다. 환불은 지금 표·설정의 비용으로 센다(훈련 취소와 같다, ponytail 메모).
- **게으른 완료**: 서버는 건설 완료 다음에 연구 완료를 본다. 완료 전에 쌓인 생산분도 새 %로 거둔다(수집 시점 기준). 앱은 오프라인이면 `complete_due`에서 끝내고, 온라인이면 끝나는 시각이 지난 뒤 2초마다 /v1/player를 다시 받는다(건설과 같다).
- **진행 막대**: 시작 시각을 따로 두지 않는다. 전체 시간은 지금 레벨·지금 속도의 연구 시간이라, 진행 중에 연구소가 오르면 막대가 조금 앞으로 간다(끝나는 시각은 그대로).
- **다이아 비용 표시**: 앱은 보정 시각으로 남은 초를 세서 버튼에 쓴다. 실제 비용은 서버가 그 순간 다시 센다.
- **표 검증 추가**: base_sec > 0(0이면 막대가 0으로 나뉜다). 선행 칸은 노드·레벨이 둘 다 비거나 둘 다 있어야 한다. 서버 DB도 `research_id`·`research_finish`가 함께 null이거나 함께 값이다. 비용·tier·lab_req·req_lv는 정수다. 설정은 성장 ≥ 1, 연구소 속도 ≥ 0, 환불 0..1, 다이아/분은 0 이상 정수다.
- **표에 없는 노드**(서버가 나중에 더한 노드): 아이콘은 효과로 고르고(EFFECT_ICONS), 그것도 없으면 플라스크다. 다른 분야의 선행 노드는 연결선을 그리지 않고 상세의 조건 목록만 보여 준다.
- **연구 창**: 탭 시트가 아니라 [닫기]가 맨 아래에 있다. 카드 상태 글자 "연구 가능"은 지금 바로 시작할 수 있을 때만(자원·다른 연구까지 본다) 쓴다. 상세의 비용 칸은 0인 자원을 숨긴다. 다이아 버튼은 보석 아이콘 + "N 즉시 완료"다.
- **월드 말풍선**: 말풍선이 떠 있을 때 연구소를 탭하면 곧바로 연구 창, 아니면 건물 창(큰 [연구])이다.
- **건물 창 효과 값**: 지금 연구를 넣어 보인다(생산 /분, 인구, 성·성문 HP, 병사 1마리 훈련 시간). 연구소 줄은 연구소 몫의 연구 속도만 보인다("연구 속도 +2% → +4%"), 연구 방법론까지 합친 값은 연구 창 위에 있다.
- **저장 v12**: `research {levels, current}`. v11 이하는 연구 없음(연구소 레벨 공격 보너스는 옮기지 않는다).

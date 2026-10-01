# CastleRPG 개정 10: 적 성장률 · 골드 소수점 · 주점 영웅 모집(22종) · 로우폴리 UI

작성일: 2026-10-01
기반: 개정 2~9. 충돌 시 이 문서가 우선한다. 사용자 지시에 따라 묻지 않고 진행하며, 결정은 이 문서에 적는다.
계기: 사용자 요청.
1. 적 HP·공격력은 스테이지당 10%, 골드는 20%씩 오른다.
2. 골드는 소수점 첫째 자리까지 합산한다. UI 표기와 실제 교환은 정수다.
3. 주점에서 영웅을 뽑는다. SSR 10종, SR 7종, R 5종이고 영웅마다 개성이 확실하다. 등급마다 스펙이 다르다.
4. 모든 UI에 로우폴리 메시 느낌을 살린다.

## 1. 적 성장률 (기획 표 `data/stages.csv` = DB `stages`)

- 1스테이지 기준 직선 증가다(지금 표와 같은 방식).
  - `hp_mult = 1 + 0.10 × (s − 1)`
  - `atk_mult = 1 + 0.10 × (s − 1)`
  - `gold_mult = 1 + 0.20 × (s − 1)`(변화 없음)
- waves, wave_size, idle_interval은 그대로다. 1~30행을 다시 채우고, 31 이상은 개정 8 연장 규칙을 그대로 따른다.
- 복리(×1.1씩)가 아니다. 복리는 100스테이지에서 HP가 약 1.25만 배가 되어 영웅 성장 없이는 진행이 불가능하다. 사용자가 원하면 표만 바꾸면 된다.

## 2. 골드 소수점

- 골드는 **0.1 단위 정수(tenths)** 로 저장·계산한다. 부동소수 오차를 없애기 위해서다.
  - DB `player_state.gold`를 `gold_tenths bigint`로 바꾼다(마이그레이션 003: 이름 변경 + 기존 값 × 10).
  - 앱 오프라인 저장(`user://save.json`)은 version 2로 올리고 `gold_tenths`를 쓴다. version 1은 × 10으로 옮긴다.
- 처치 골드(tenths) = max(1, round(gold × gold_mult × 10)). 예: 2스테이지 졸개 = 2 × 1.2 = 2.4골드(24).
  - 서버 `/v1/kills`는 tenths로 더한다.
  - 앱의 미전송 예상분도 tenths로 센다.
- 표시: 모든 UI는 floor(gold_tenths / 10)의 정수만 보여 준다. 소수점은 보이지 않는다.
- 교환(정수):
  - 상인 판매로 얻는 골드는 floor(수량 × 단가 × 배율)인 정수다(지금과 같다). tenths에는 × 10으로 더한다.
  - 영웅 모집 비용도 정수다. 가능 조건은 floor(gold_tenths / 10) ≥ 비용이고, 차감은 비용 × 10이다. 소수 부분은 남는다.
- API 플레이어 응답 `player`:
  - `gold_tenths`(정수)와 `gold`(= floor(gold_tenths / 10), 정수)를 같이 준다.
  - `/v1/kills` 응답은 `gold_gained_tenths`다.
  - `/v1/sell`의 `gold_gained`는 정수 골드다.

## 3. 영웅 (기획 표 `data/heroes.csv` = DB `heroes`, 22종)

### 3.1 공통 규칙

- 등급 배율(HP·공격력): R ×1.0, SR ×1.4, SSR ×2.0. 아래 표의 수치는 등급과 성향을 이미 반영한 최종 기본값이다.
- 역할(role): `melee`(근접, 기본 배치는 성문 앞), `ranged`(원거리, 기본 배치는 성벽 위).
- 성향 보정은 다음과 같고, 표에 이미 들어 있다.
  - tank: HP ×1.3, 공격 ×0.7, 속도 5
  - bruiser: HP ×1.1
  - assassin: HP ×0.8, 공격 ×1.35, 공격 간격 ×0.8, 속도 7
  - support: 공격 ×0.6
  - caster: HP ×0.9, 공격 ×1.1, 간격 ×1.2, 사거리 8
  - marksman: 사거리 11
- 별(중복): 같은 영웅을 또 뽑으면 copies +1이고, 별 = min(copies − 1, `hero_max_stars`(5))이다. HP·공격력 × (1 + `hero_star_bonus`(0.1) × 별)이다.
- 등급 색:
  - R `#8FA3B8`(강철)
  - SR `#9B6CD6`(보라)
  - SSR `#F2B233`(금)
  - 카드 테두리, 보석 배지, 영웅 발밑 링에 쓴다.
- 영웅 고유 색(`color`)은 발밑 링 안쪽, 투사체, 스킬 이펙트에 쓴다.
- 모델: KayKit Adventurers 5종(Knight, Barbarian, Mage, Rogue, Rogue_Hooded)이다. Barbarian·Mage를 새로 받는다.
  - `gear`는 GLB 안에서 **보여 줄** 부착물 노드 이름 목록(`|` 구분)이고, 나머지 부착물은 숨긴다.
  - 표의 이름은 의도다. 구현자는 GLB를 열어 실제 노드 이름으로 고친다(예: Mage의 지팡이 노드 이름).
- 시작 영웅: `starter_heroes` = `hans|ella|dorik|nina`(R 4종, 근접 2·원거리 2). 새 플레이어는 이 넷을 copies 1로 갖고, 배치 슬롯 0~3에 둔다.

### 3.2 스킬 종류 (열 `skill1, s1a, s1b, s1c, skill2, s2a, s2b, s2c`. 빈 칸 = 없음)

| 종류 | a | b | c | 효과 |
|---|---|---|---|---|
| heal_aura | 쿨(초) | 반경(m) | % | 쿨마다 반경 안 아군 영웅(자신 포함)을 각자 최대 HP의 c% 회복 |
| atk_aura | 반경 | % | | 반경 안 다른 영웅 공격력 +b%(여러 개면 가장 큰 것 하나) |
| dmg_reduce | % | | | 받는 피해 −a% |
| dodge | % | | | a% 확률로 피해 무시 |
| thorns | % | | | 받은 피해의 a%를 공격한 몬스터에게 되돌림 |
| lifesteal | % | | | 준 피해의 a%만큼 자신 회복 |
| haste | % | | | 공격 속도 +a%(간격 ÷ (1 + a/100)) |
| rage | % | | | 잃은 HP 비율만큼 공격 속도 최대 +a% |
| crit | % 확률 | 배수 % | | a% 확률로 피해 × b/100 |
| execute | 기준 HP % | 추가 % | | 대상 HP가 a% 이하이면 피해 +b% |
| boss_slayer | % | | | epic_boss에게 피해 +a% |
| cleave | 반경 | % | | 근접 타격 시 대상 주변 반경 안 다른 몬스터에게 피해의 b% |
| multishot | 대상 수 | | | 원거리 공격이 사거리 안 가까운 몬스터 a마리에게 동시에 |
| chain | 튕김 수 | 감쇠 % | 튕김 거리 | 맞은 대상에서 가장 가까운 다른 몬스터로 a번 튕긴다. 매번 피해 × b/100 |
| aoe_blast | 쿨 | 반경 | % | 쿨마다 현재 대상 위치에 폭발, 반경 안 모든 몬스터에게 공격력의 c% |
| slow | % | 초 | | 맞은 몬스터 이동 속도 −a%, b초(갱신) |
| stun | N번째 | 초 | | N번째 공격마다 대상 b초 기절(이동·공격 정지) |
| poison | %/초 | 초 | | 맞은 몬스터가 b초 동안 매초 공격력의 a% 피해(갱신) |
| gate_repair | 쿨 | % | | 쿨마다 자기 면 성문 HP를 최대치의 b% 회복(성문 앞이나 같은 면 성벽 위에 있을 때만, 부서진 성문은 제외) |

- 몬스터 쪽에 상태(slow, stun, poison)와 피해 출처(thorns 반사 대상)를 처리한다.
- 영웅 쪽은 피해를 받을 때 dodge → dmg_reduce → thorns 순으로 적용한다.

### 3.3 영웅 표 (`data/heroes.csv` 그대로)

```csv
id,name,title,grade,role,archetype,model,gear,color,hp,atk,range,atk_interval,speed,aggro,skill1,s1a,s1b,s1c,skill2,s2a,s2b,s2c,desc
arteon,아르테온,빛의 성기사,SSR,melee,tank,Knight,1H_Sword|Badge_Shield,#F5D76E,1040,42,1.8,0.8,5,8,heal_aura,6,6,8,dmg_reduce,25,,,성문 앞을 지키며 주변 영웅을 빛으로 치유하는 불굴의 기사
ignis,이그니스,화염 대마법사,SSR,ranged,caster,Mage,2H_Staff,#E8553A,396,44,8,1.2,6,12,aoe_blast,5,3.5,220,,,,,몰려오는 무리 한가운데 거대한 화염구를 떨어뜨린다
sylvana,실바나,바람의 명사수,SSR,ranged,marksman,Rogue_Hooded,2H_Crossbow,#5FBF6A,440,40,11,1.0,6,12,multishot,3,,,crit,25,200,,바람을 읽어 세 발을 동시에 날리고 급소를 꿰뚫는다
grom,그롬,대지의 광전사,SSR,melee,bruiser,Barbarian,2H_Axe,#A0522D,880,60,1.8,0.8,6,8,cleave,2.5,80,,rage,80,,,다칠수록 거세지는 도끼질로 주변을 쓸어버린다
seraphine,세라핀,서리 마녀,SSR,ranged,caster,Mage,1H_Wand,#7FC8F0,396,44,8,1.2,6,12,chain,3,70,4,slow,30,2,,얼음 번개가 적 사이를 튕기며 발을 묶는다
kyle,카일,그림자 암살자,SSR,melee,assassin,Rogue,Knife|Knife_Offhand,#5A4E7A,640,81,1.8,0.64,7,9,crit,40,250,,execute,30,100,,빈틈을 노려 치명타를 꽂고 약해진 적을 확실히 끝낸다
baldur,발두르,철벽 수문장,SSR,melee,tank,Knight,1H_Sword|Spike_Shield,#8C9AA8,1040,42,1.8,0.8,5,8,gate_repair,8,3,,thorns,30,,,성문을 수리하며 버티고 때린 자에게 가시로 되갚는다
lumina,루미나,성녀,SSR,ranged,support,Mage,Spellbook_open,#F7E9A0,440,24,9,1.0,6,12,heal_aura,4,8,6,atk_aura,8,15,,기도로 아군을 치유하고 곁의 영웅에게 힘을 불어넣는다
harald,하랄드,용사냥꾼,SSR,melee,bruiser,Barbarian,2H_Sword,#C0392B,880,60,1.8,0.8,6,8,boss_slayer,150,,,cleave,1.8,50,,거대한 적일수록 눈을 빛내는 전설의 사냥꾼
nev,네브,천둥 궁수,SSR,ranged,marksman,Rogue_Hooded,1H_Crossbow,#F1C40F,440,40,11,1.0,6,12,chain,4,60,4,stun,5,1,,천둥을 실은 화살이 적을 연쇄로 감전시켜 멈춰 세운다
bron,브론,방패병 대장,SR,melee,tank,Knight,1H_Sword|Rectangle_Shield,#7F8C8D,728,29,1.8,0.8,5,8,dmg_reduce,30,,,thorns,15,,,큰 방패로 공격을 받아내는 노련한 대장
mira,미라,독화살 사냥꾼,SR,ranged,marksman,Rogue_Hooded,2H_Crossbow,#6B8E23,308,28,11,1.0,6,12,poison,30,4,,,,,,독을 바른 화살로 적을 서서히 쓰러뜨린다
torvin,토르빈,전투 사제,SR,melee,support,Knight,1H_Sword|Badge_Shield,#D4AC0D,560,25,1.8,0.8,6,8,heal_aura,8,5,5,,,,,싸우면서도 기도를 멈추지 않는 사제
rian,리안,쌍검사,SR,melee,assassin,Rogue,Knife|Knife_Offhand,#48C9B0,448,57,1.8,0.64,7,9,haste,30,,,dodge,15,,,두 자루 검으로 눈보다 빠르게 벤다
echo,에코,견습 화염술사,SR,ranged,caster,Mage,1H_Wand,#F39C12,277,31,8,1.2,6,12,aoe_blast,7,2.5,140,,,,,아직 서툴지만 불꽃만큼은 진짜인 마법사
gork,고르크,도끼 투척꾼,SR,ranged,bruiser,Barbarian,1H_Axe|1H_Axe_Offhand,#935116,370,28,6,1.0,6,10,multishot,2,,,,,,,양손 도끼를 짧은 거리에서 두 적에게 던진다
felix,펠릭스,기사단 창병,SR,melee,bruiser,Knight,2H_Sword,#2E86C1,616,42,1.8,0.8,6,8,stun,4,0.8,,,,,,묵직한 일격으로 적을 잠시 멈춰 세운다
hans,한스,민병대 검사,R,melee,bruiser,Knight,1H_Sword,#95A5A6,440,30,1.8,0.8,6,8,lifesteal,10,,,,,,,마을을 지키려 칼을 든 성실한 민병
ella,엘라,마을 궁수,R,ranged,marksman,Rogue_Hooded,2H_Crossbow,#82E0AA,220,20,11,1.0,6,12,crit,15,150,,,,,,가끔 놀라운 한 발을 꽂는 사냥꾼의 딸
dorik,도릭,나무꾼 전사,R,melee,bruiser,Barbarian,1H_Axe,#A04000,440,30,1.8,0.8,6,8,cleave,1.5,50,,,,,,나무 베던 솜씨로 두셋을 함께 벤다
nina,니나,견습 치유사,R,ranged,support,Mage,2H_Staff,#A9DFBF,220,12,9,1.0,6,12,heal_aura,10,4,4,,,,,서툴지만 다친 동료를 지나치지 못한다
jack,잭,떠돌이 도적,R,melee,assassin,Rogue,Knife,#616A6B,320,40,1.8,0.64,7,9,dodge,20,,,,,,,날렵하게 몸을 피하며 틈을 노린다
```


### 3.4 시각 개성

- 발밑 링은 로우폴리 6각 고리다. 바깥은 등급 색, 안쪽은 고유 색이다. 선택 링(노랑)과 겹치지 않게 조금 작게 만든다.
- 투사체:
  - 궁수류(Rogue_Hooded·gork)는 기존 화살이다. gork는 회전하는 도끼 메시다.
  - 마법사류는 고유 색의 저면체 구체(20면체)다.
- 이펙트는 전부 로우폴리 메시이고, 0.3~0.6초 안에 사라진다. 그림자 없음, 공유 재질.
  - aoe_blast: 고유 색 20면체가 커지며 사라진다.
  - chain: 대상 사이 각진 번개 선(3~4 꺾임)
  - heal_aura: 초록 6각 고리가 퍼진다.
  - stun: 대상 머리 위에 노란 별 3개(각진 삼각 별)
  - slow: 대상 발밑에 하늘색 결정
  - poison: 대상 위에 초록 작은 거품 2개
  - gate_repair: 성문에 금색 망치 반짝임(작은 각진 조각)
- 이름표: 선택된 영웅에게만 "칭호 이름"(등급 색)을 머리 위에 표시한다(화면 공간).

### 3.5 배치

- 슬롯 수는 hero_slots(keep_level)이다(지금 4).
- 슬롯 i의 영웅은 면 i % 4에 놓이고, 역할로 기본 자리가 정해진다: melee는 POST_GATE, ranged는 POST_WALL.
- 지금의 "index → warrior/archer 번갈아" 규칙과 `hero_roster` 설정은 없앤다.
- 빈 슬롯이면 그 슬롯 영웅은 없다.

### 3.6 모집 (주점)

- 주점 건물을 탭하면 모집 창이 열린다(상인처럼 판정체를 둔다). 주점은 기능 건물이 된다.
- 설정(`data/config.csv` = DB `game_config`):

| 키 | 값 |
|---|---|
| gacha_cost_1 | 300 |
| gacha_cost_10 | 2700 |
| gacha_rate_ssr | 0.03 |
| gacha_rate_sr | 0.17 |
| gacha_10_min_sr | 1 |
| hero_max_stars | 5 |
| hero_star_bonus | 0.1 |
| starter_heroes | hans\|ella\|dorik\|nina |

  - R 확률은 나머지(0.80)다.
  - `gacha_10_min_sr`: 10연차에 SR 이상이 없으면 마지막 1장을 SR 중 무작위로 바꾼다.
- 등급을 정한 뒤, 그 등급 안에서 균등하게 뽑는다.
- 온라인에서는 서버가 뽑는다(암호학적 난수). 오프라인 개발 모드는 앱이 같은 규칙으로 뽑는다.

### 3.7 DB·API (서버)

- 마이그레이션 004: `hero_roles` 표를 지우고 `heroes` 표를 만든다. 열은 위 CSV 그대로이고, 숫자 열은 real, `ord`는 정렬용이다. seed는 heroes.csv에서 넣는다.
- 마이그레이션 005:
  - `player_heroes (player_id, hero_id, copies integer not null default 1 check (copies >= 1), primary key(player_id, hero_id))`
  - `player_state.deploy jsonb not null default '[]'`
  - 기존 플레이어에게는 시작 영웅과 배치를 채운다.
- 새 플레이어는 시작 영웅 4종(copies 1)을 갖고, deploy = 시작 영웅 순서다.
- 플레이어 응답에 다음을 더한다.
  - `player.heroes: {hero_id: copies}`
  - `player.deploy: [hero_id 또는 null, …]`(길이 = 슬롯 수)
- `/v1/gamedata`의 heroes 행은 위 열 전부다. config는 문자열 값 그대로다.
- `POST /v1/gacha {count: 1 | 10}`:
  - 골드가 부족하면 409 `not_enough_gold`다.
  - 성공하면 플레이어 응답 + `results: [{hero_id, grade, new: bool, copies}]`이다.
  - economy_log에 `gacha`를 남긴다.
  - 원자성: version 가드 한 문장 또는 기존 낙관적 잠금이다.
- `POST /v1/deploy {deploy: [hero_id 또는 null, …]}`:
  - 길이 = 슬롯 수, 보유한 영웅만, 중복 금지(null은 여러 개 가능)다. 아니면 400이다.
  - → 플레이어 응답
- 오프라인 개발 모드는 `user://save.json` version 2에 heroes·deploy를 저장한다.

## 4. 로우폴리 UI

모든 UI(상단 칩, 스테이지 패널, HP 바, 버튼, 거래 창, 연결 화면·띠, 알림, 모집 창, 영웅 창)를 하나의 키트로 그린다.

- `scripts/lowpoly_box.gd`(`extends StyleBox`, `_draw` 재정의):
  - 모서리를 깎은 8각 다각형이다(`chamfer` px).
  - 안을 삼각형 면 여러 개로 채운다. 꼭짓점 하나를 살짝 비튼 중심으로 부채꼴 분할하고, 각 변을 2~3등분해서 면 8~16개를 만든다.
  - 면마다 기본색을 위치 해시로 ±`facet`만큼 밝게/어둡게 하고, 왼쪽 위 면일수록 밝게 한다(빛 방향, 3D와 같은 왼위 광원).
  - 진한 외곽선(1.5~2px), 위쪽 가장자리에 밝은 띠 하나(돌 결정의 윗면 느낌)를 둔다.
  - 속성: `color`, `chamfer`, `facet`, `border_color`, `border_width`, `seed`
- `scripts/ui_kit.gd`(정적):
  - `panel(color)`, `button_styles(color)` → normal/hover/pressed/disabled. pressed는 어둡게 + 내용 2px 아래, disabled는 채도를 뺀다.
  - `bar(fill_color)` → 배경과 채움 박스. 채움도 면 분할한다.
  - `draw_gem(ci, center, r, color, sides := 6)`: 등급 보석 배지
  - `draw_facet_card(...)`: 영웅 카드. 등급 색 테두리, 위쪽에 등급 보석
  - 글꼴은 Pretendard 그대로다. 제목에는 진한 외곽선을 둔다.
- 색은 지금 팔레트(밝고 채도 낮음)를 유지한다.
  - 패널: 반투명 크림 `#FBF7EE` 계열
  - 강조 버튼: 호박색 `#F9B233`
  - 보조: 강철 `#8C9AB0`
- 성능: 박스마다 면 수는 고정이고, 해시는 결정적이다. 매 프레임 다시 그려도 가볍게 한다. 같은 크기 StyleBox는 재사용한다.

## 5. UI 배치 (새 창)

- **HUD 하단**: 기존 큰 버튼 위 왼쪽에 [영웅] 버튼(로우폴리 6각)을 둔다. 탭하면 영웅 창이 열린다.
- **모집 창**(주점 탭):
  - 제목 "주점 · 영웅 모집"
  - 확률 한 줄 "SSR 3% · SR 17% · R 80%"
  - [1회 모집 300] [10회 모집 2700(SR 이상 1장 보장)]. 골드가 부족하면 비활성이다.
  - 결과 화면: 카드가 1장 또는 10장(5 × 2) 펼쳐진다. 카드는 등급 색 테두리 로우폴리 카드이고, 등급 보석, 이름, 칭호, NEW 또는 ★ 수를 보여 준다. SSR 카드는 금색 면이 반짝인다(면 밝기 순환).
  - [확인]
- **영웅 창**:
  - 위: 배치 슬롯 4칸
  - 아래: 보유 영웅 격자. 정렬은 등급 → 이름이고, 카드에 별을 표시한다.
  - 슬롯을 탭하고 영웅 카드를 탭하면 배치된다. 같은 영웅이 다른 슬롯에 있으면 서로 바꾼다.
  - 카드를 길게 누르거나 [정보]를 누르면 상세가 열린다: 능력치(HP, 공격, 사거리, 공격 간격), 스킬 두 개의 한국어 설명(숫자 포함), 설명문.
  - 변경은 [적용]을 누를 때 서버 `/v1/deploy`로 보낸다(오프라인은 저장).
  - 적용하면 다음 리필(스테이지 사이) 때 영웅이 바뀐다. 방치 모드에서는 즉시 다시 배치한다.
- 모든 창은 기존 거래 창처럼 동작한다: 뒤 입력 차단, 바깥 탭으로 닫기, 연 직후 0.4초 보호.

## 6. 테스트

- **서버**:
  - 처치 tenths 합산(2스테이지 졸개 24)
  - 판매는 정수 × 10
  - 모집: 비용 차감 tenths, 부족하면 409, 10연차 SR 보장(표본), 확률(10만 회 표본 SSR 3% ± 0.4%, SR 17% ± 0.8%), 중복은 copies +1
  - 배치 검증(길이, 보유, 중복)
  - 새 플레이어 시작 영웅
  - 마이그레이션 003~005(001·002만 적용된 DB에서 올리기)
- **앱 로직**:
  - stages 새 배율
  - 처치 tenths, 표시 floor, 저장 v1 → v2 이전
  - heroes.csv 22행 검증(등급 10/7/5, 스킬 종류 알려진 것만, 모델 존재)
  - 스킬 수식 단위 테스트(crit, execute, chain 감쇠, rage, haste, dmg_reduce/dodge/thorns 순서)
  - lowpoly_box의 면 수와 결정성
  - 오프라인 모집 확률·보장
- **AI 체크**: 스킬 대표 사례.
  - aoe_blast가 반경 안 여러 마리를 깎는다
  - heal_aura가 아군을 회복한다
  - stun이면 몬스터가 멈춘다
  - gate_repair가 성문 HP를 올린다
  - slow면 이동이 느려진다
  - 배치 슬롯 i가 면 i % 4·역할 자리에 놓인다
- **입력 체크**:
  - 주점 탭으로 모집 창이 열리고, 1회 모집하면 골드가 줄고 영웅이 는다(오프라인)
  - 영웅 창에서 슬롯·카드 탭으로 배치하고 적용한다
  - 창이 열린 동안 뒤 입력이 막힌다
- **통합**(`dev/online-check.sh`):
  - 서버 모집(1회)으로 골드가 줄고 영웅이 생긴다
  - 배치가 저장되고 재접속하면 복원된다
  - 처치 tenths가 반영된다
- **웹 캡처(컨트롤러)**: 로우폴리 UI 전경, 모집 결과 10장, 영웅 창, SSR 스킬 이펙트(이그니스 화염구, 네브 연쇄 번개), 영웅 발밑 링.
- **Neon**: 003~005 마이그레이션과 시드를 적용한다(컨트롤러).

## 7. 범위 밖

영웅 레벨업·장비, 천장(누적 보장), 유료 재화, 영웅 상세 3D 미리보기, 병사.

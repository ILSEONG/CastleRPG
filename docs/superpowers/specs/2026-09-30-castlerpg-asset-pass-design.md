# CastleRPG 에셋 적용 설계 (개정 3)

작성일: 2026-09-30
기반: `2026-09-28-castlerpg-mvp-rev2-design.md` (개정 2). 충돌 시 이 문서가 우선한다.
계기: 사용자 요청 — "에셋 좀 써서 퀄리티 좀 높여봐". 게임 규칙·밸런스·입력은 바꾸지 않는다. 보이는 것만 바꾼다.

## 1. 에셋 출처 (전부 CC0, 표기 의무 없음)

KayKit (Kay Lousberg) GitHub 저장소, 커밋 고정:

| 팩 | 커밋 | 쓰는 것 |
|---|---|---|
| Character Pack Adventures 1.0 | `672074b73ba276876a19e8816ecdc5241817ab47` | Knight.glb, Rogue_Hooded.glb, arrow.gltf(+bin, rogue_texture.png) |
| Character Pack Skeletons 1.0 | `15b62b9bad122f72926c10fb14d622c73819fa54` | Skeleton_Minion.glb, Skeleton_Warrior.glb, Skeleton_Blade.gltf, Skeleton_Axe.gltf(+bin, skeleton_texture.png) |
| Medieval Hexagon Pack 1.0 | `84fa4e91af6a88989be7c99e0891cede11f2ca38` | 파랑 건물 9종, wall_straight, wall_straight_gate, 자연물 7종, hexagons_medieval.png |

받기: `bash dev/fetch-assets.sh` (고정 커밋에서 받아 `assets/models/` 아래에 둔다). 받은 파일은 커밋한다(약 20MB). 라이선스 원문은 `assets/models/LICENSE-KayKit.txt`.

## 2. 매핑

| 대상 | 모델 | 보이는 부착물 | 애니메이션 (대기 / 걷기 / 공격 / 사망) |
|---|---|---|---|
| 전사 | Knight | 1H_Sword, Round_Shield, 투구·망토 | Idle / Walking_A / 1H_Melee_Attack_Chop / Death_A |
| 궁수 | Rogue_Hooded | 2H_Crossbow, 두건·망토 | Idle / Walking_A / 2H_Ranged_Shoot / Death_A |
| grunt | Skeleton_Minion + Skeleton_Blade(오른손 `handslot.r`) | — | Idle_Combat / Walking_D_Skeletons / 1H_Melee_Attack_Chop / Death_C_Skeletons |
| epic_boss | Skeleton_Warrior + Skeleton_Axe(오른손) | 투구 | Idle_Combat / Walking_D_Skeletons / 2H_Melee_Attack_Chop / Death_C_Skeletons |

| 건물 id | 모델 |
|---|---|
| keep 성채 | building_castle_blue |
| barracks 막사 | building_barracks_blue |
| tavern 주점 | building_tavern_blue |
| lab 연구소 | building_blacksmith_blue |
| houses 민가 | building_home_B_blue |
| lumber 벌목장 | building_lumbermill_blue |
| quarry 채석장 | building_mine_blue |
| farm 농장 | building_windmill_blue |

성벽 = wall_straight 반복, 성문 = wall_straight_gate (문짝 `wall_straight_gate_door_left/right`), 모서리 탑 = building_tower_A_blue.
자연물 = trees_A_medium, trees_B_large, tree_single_A, tree_single_B, rock_single_A, rock_single_C, rock_single_E. 궁수 화살 = arrow.

## 3. 크기와 배치 규칙

- 캐릭터: 모델 키 약 2.2 → 배율 1.0 (약 2.2m). 보스는 추가로 `Balance.MONSTER.epic_boss.scale` = 1.6.
- 캐릭터 정면은 모델 +Z. 이동 중엔 이동 방향, 공격 중엔 표적을 본다(수평 회전만).
- 건물: 모델 AABB를 재서 부지(타일 크기 − 여유 0.6m)에 맞는 최대 균일 배율, 바닥 y=0, 부지 중앙. 이름표는 지붕 위 1m.
- 성벽: 모델 한 조각은 길이 2·높이 1.1·두께 0.8 단위. 높이·두께는 `WALL_H`(3m)·`WALL_T`(2m)에 맞춰 늘리고, 길이는 "성문 가장자리 ~ 모서리 탑 가장자리" 구간을 약 5m 조각으로 균등 분할해 채운다. 성문 조각은 폭 `GATE_W`(4m). 모델 정면(+Z)이 성 바깥을 본다.
- 모서리 탑: 성벽 중심선 모서리에 배율 3.2.
- 자연물: 시드 고정 난수로 60개. 성벽 바깥면에서 6m 안, 괴물 진입로(두 축에서 ±9m), 서로 5m 안은 피한다. 배율 3.0 × (0.8~1.2), 임의 회전.

## 4. 동작 변화 (시각만)

- 영웅 사망: 사망 애니메이션 후 그 자리에 쓰러진 채 남는다(리필 때 일어나 대기). 선택 링은 숨김. 판정·규칙은 개정 2 그대로.
- 몬스터 사망: `died`는 즉시(스포너 집계 그대로), 표적 대상에서 즉시 빠지고, 사망 애니메이션 1.6초 뒤 제거. 리필 때는 즉시 제거.
- 공격할 때마다 공격 애니메이션을 처음부터 재생하고, 끝나면 대기로 돌아간다.
- 성문 파괴: 문짝 두 개가 사라진다. 리필 때 다시 보인다.
- 궁수 화살: 박스 대신 화살 모델, 촉이 표적을 향한다.

## 5. 분위기

- 태양광: 약간 따뜻한 빛(색 (1.0, 0.96, 0.88), 에너지 1.1), 회전 `(-50°, -45°, 0)` — 카메라 요(45°)와 직각으로 화면 왼쪽에서 빛이 들어와 그림자가 물체 오른쪽 바닥에 드리운다(요 135°는 성채 그림자가 건물·이름표 쪽을 덮어 탈락). 주변광 색 (0.78, 0.80, 0.86) × 0.9.
- 그림자: 직교 모드(분할 없음, 모바일 부담 최소), 최대 거리 220, 바이어스 기본값(여드름·떠 보임 없음). 그림자 맵 2048(`rendering/lights_and_shadows/directional_shadow/size` — 휴대폰 웹은 `.mobile` 기본값을 안 받아 4096이 되므로 명시).
- 바닥 셰이더는 빛·그림자를 받는다(`unshaded` 아님, `ROUGHNESS` 1, `SPECULAR` 0). 잔디·포장·도로 색은 빛을 받은 결과가 이전 무광 바닥과 같은 밝기가 되도록 낮췄다.
- 그림자를 드리우지 않는 것: 바닥, 영웅 선택 링, 건물 이름표(`Label3D`).
- HUD: 상단을 둥근 반투명 흰 패널로 묶고, 체력바는 둥근 모서리와 옅은 바탕, 버튼은 둥근 강조색(호박색) + 눌림·비활성 상태, 가운데 문구는 외곽선.

## 6. 구조 변경

- `scripts/flat.gd` 삭제 → `scripts/art.gd`(팔레트, 단색 메시 헬퍼, 모델 경로·배율·애니메이션 표, `instance()`, `model_aabb()`). 순수 스크립트(오토로드 참조 없음) → 헤드리스 테스트 가능.
- `scripts/unit_model.gd` 신규: 캐릭터 모델 래퍼(인스턴스, 부착물 숨김, 무기 부착, 애니메이션, 방향).
- `scripts/buildings.gd`: 건물 모델 + 자연물 장식. `castle.gd`: 모델 성벽·성문·탑. `hero.gd`, `monster.gd`: 캡슐 → UnitModel. `main.gd`: 그림자. `hud.gd`: 스타일.
- `Balance.HERO_ROLES`·`MONSTER`의 `color` 삭제(더 이상 안 씀). `Balance.TOWER_H` 삭제.
- 스크립트 수 15개 유지(flat 삭제, art·unit_model 추가).

## 7. 테스트와 확인 (창 금지, 개정 2 §8 그대로)

- 로직 테스트에 에셋 계약 테스트 추가: 모든 모델 경로 존재, 캐릭터마다 AnimationPlayer 하나와 지정 애니메이션 4개 존재, 숨길 메시 이름 존재, 스켈레톤에 `handslot.r` 뼈 존재, 성문 모델에 문짝 노드 존재, 건물 표에 8개 id 전부.
- 입력 헤드리스 체크, 엔드투엔드(스테이지 1→2), 패배 복귀 그대로 통과.
- 웹 캡처: 전경(모델 성벽·탑·건물·나무), 전투 확대(걷는 해골, 칼 휘두르는 전사, 석궁 쏘는 궁수와 화살), 보스, 클리어 배너.

## 8. 완료 기준

- 위 테스트·체크·캡처 전부
- 웹 빌드가 로드되고 콘솔에 `[pageerror]` 없음
- 스크립트 15개 이내, 씬 1개(테스트 씬 제외), 외부 에셋 = 폰트 1개 + KayKit 모델(§1)

# Meshy 에셋 생성 규칙

Meshy MCP(`.mcp.json`의 `meshy`, 공식 `@meshy-ai/meshy-mcp-server`)로 3D 에셋을 만들 때의 규칙.
API 키는 저장소에 두지 않는다 — 실행 환경의 환경 변수 `MESHY_API_KEY`에서 읽는다.

## 받기
- 형식: **GLB**(텍스처 포함 한 파일). 다른 형식은 필요할 때만.
- 저장 위치: 원본은 `assets/models/meshy/<분류>/<id>.glb`
  - 분류: `heroes`(영웅 id — heroes.csv), `monsters`(몬스터 kind — Art.MONSTER_MODELS 키), `props`(소품)
  - 예: `assets/models/meshy/heroes/arteon.glb`, `assets/models/meshy/monsters/grunt.glb`
- 받을 때마다 `assets/models/meshy/CREDITS.md`에 한 줄 기록(파일, 날짜, 작업 id, 입력, 플랜).
- 크레딧: 생성 전에 잔액과 예상 비용을 확인하고, 사용자가 시키지 않은 대량 생성은 하지 않는다.

## 게임에 넣기(캐릭터)
- 게임의 애니메이션·무기·타격 시점은 KayKit 뼈대(41뼈) 기준이다. Meshy 자동 리깅 뼈대는 쓰지 않고,
  T자세 메시를 KayKit 휴식 자세에 맞춘 뒤 KayKit 몸 가중치를 옮겨 스킨 메시로 만든다(크기·방향 맞춤 → 삼각형 줄이기 → 가중치 옮기기).
- 삼각형 예산: 영웅·몬스터 하나 5천 이하(KayKit 4.6~5.7천과 비슷하게).
- 입력 이미지는 T자세 정면 컨셉(팔 수평, 빈손, 무기 없음). 영웅은 아르테온 컨셉(`characters/arteon/concept_tpose.png`, 큰 머리의
  로우폴리 각진 면)을 참조 이미지로 image-to-image(nano-banana-2)에 넣어 그림체·비율·자세를 맞춘다.

## 영웅 파이프라인(지금 쓰는 것)
1. 컨셉: image-to-image, 참조 = 아르테온 컨셉, 프롬프트 = 같은 그림체 + 영웅 생김새(Art.HERO_LOOKS 주석) + 빈손 T자세.
2. 3D: image-to-3d, 텍스처, `pose_mode: t-pose`(`dev/meshy_heroes.py model`). SSR = `meshy-7` + `should_remesh`, `topology: triangle`,
   `target_polycount: 4500`(30 크레딧). SR·R = `model_type: smart-topology`, `meshy-t2`(15 크레딧, 4~4.6천 삼각형).
3. 몸 만들기: `python3 dev/meshy_fit.py assets/models/characters/<model>.glb <meshy>.glb assets/models/meshy/heroes/<id>.glb`
   (numpy·Pillow). 발~팔 높이로 크기를 맞추고 손끝이 KayKit 손끝에 오게 팔만 늘이거나 줄인 뒤, 가까운 KayKit 몸 정점(스킨 부위 +
   모자·망토는 붙은 뼈 하나)의 가중치를 옮기고(좌우 섞지 않음) 메시 위에서 고르게 편다. 출력 = KayKit 뼈대·Skin(같은 bind) +
   스킨 메시 `MeshyBody` 하나 + 1024 JPEG 텍스처. 애니메이션·무기는 넣지 않는다(게임이 KayKit 모델 것을 쓴다).
   팔을 내리거나 A자세로 나온 메시(팔 폭 ÷ 키 < 0.7이거나 팔이 아래로 처짐, `--unpose`로 강제)는 KayKit 팔을 같은 각도로 내린
   몸에 맞는 각도·크기를 찾아 그 자세에서 가중치를 옮긴 뒤 T자세로 되돌린다. 그래도 어긋나면(손이 몸통에 붙은 경우) 다시 생성한다.
4. 게임: `Art.hero_spec`이 `MESHY_HERO_DIR/<id>.glb`가 있으면 `spec.body`를 넣고, `UnitModel.dress`가 KayKit 몸(손 슬롯 무기 밖 메시)을
   숨긴 뒤 `MeshyBody`를 같은 Skin으로 스켈레톤에 단다. 팔레트는 무기에만, 머리·가슴 부품은 빼고 손 부품만 단다.
   `Art.meshy_bodies = false`면 KayKit 생김새. 검사: tests/run_tests.gd `test_meshy_bodies`.

## 소환수
소환수(scripts/summon.gd)는 KayKit 뼈대 없이 부품 ≤ 3개를 코드로 흔든다(몸통 + 팔·날개 등). Meshy 모델도 같은 부품으로 나눠 넣는다.
1. 컨셉: `dev/meshy_summons.py concept <kind>`(아르테온 컨셉 참조, nano-banana-2 6 크레딧). 따로 움직이는 부위(골렘 팔)는 몸에서
   떨어져 떠 있는 모양으로 그린다 — 메시에서 섬으로 나뉘어 자르지 않고 부품이 된다.
2. 3D: `dev/meshy_summons.py model <kind>`(meshy-t2 smart-topology + 텍스처 15 크레딧, 4천 삼각형 안팎). 소환수 하나 21 크레딧.
3. 부품: `python3 dev/meshy_summon_fit.py golem <meshy>.glb assets/models/meshy/summons/golem.glb` — 정면을 −Z로 돌리고 키 2.3 m·발 y = 0,
   바깥쪽 섬 = 팔(Part1 −X, Part2 +X), 관절 = 그 위 어깨 덩이 중심, 나머지 = 몸통(Part0). 노드 원점 = 관절.
4. 게임: `summon.gd`가 `MESHY_DIR/<kind>.glb`가 있으면 그 부품을 영웅과 같은 그림 방식(Art.stylize)으로 쓴다. 움직임 코드는 그대로.
   `meshy = false`면 코드 모양. 검사: tests/summon_check.gd `(A2)`.

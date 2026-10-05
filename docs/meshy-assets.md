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
- 입력 이미지는 KayKit T자세 렌더를 바탕으로 한 정면 컨셉(팔 수평, 무기 없음)으로 만들어 뼈대와 비율을 맞춘다.

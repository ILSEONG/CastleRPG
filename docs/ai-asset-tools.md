# 무료 AI 에셋 도구 조사 (2026-10-05 기준)

> 웹 조사 결과 요약. 무료 등급 한도·라이선스는 자주 바뀌므로 쓰기 직전에 공식 페이지에서 다시 확인할 것.
> "미확인"은 공식 문서로 확인하지 못한 항목. 법률 자문 아님.

## 핵심
- 무료 등급만으로 **상업 출시에 쓸 수 있는** 3D 생성: **Meshy 무료(CC BY 4.0 — Meshy 표기 필수)**, **TRELLIS.2 / Stable Fast 3D 로컬 실행**.
- 리깅·애니메이션: **Mixamo(상업 무료, 원본 재배포 금지)**, **Rokoko Create(무료 등급 상업 가능, 월 한도 작음)**.
- 무료 등급 **상업 불가**: Tripo, Sloyd, DeepMotion, Krea, Scenario, Recraft.
- **Hunyuan3D 오픈 가중치는 라이선스 적용 지역에서 한국(EU·영국 포함)이 제외** → 쓰지 않는다.

## 3D 생성
| 도구 | 무료 한도 | 무료 상업 이용 | 비고 |
|---|---|---|---|
| Meshy (meshy.ai) | 월 100크레딧, 다운로드 월 10회(6 Lite 모델만) | 가능(CC BY 4.0, 표기 필수, 소유권은 유료) | 저폴리(Smart Topology), 리메시·리깅·프리셋 애니 0크레딧. Pro 월 $20 |
| Tripo (tripo3d.ai) | 월 200크레딧 | 불가 | 치비 품질 좋음, 오토리깅. 유료 시 최강 후보 |
| Rodin/Hyper3D | 생성 무료, 다운로드 유료 | 미확인 | 고디테일 위주 |
| TRELLIS.2-4B (MS, MIT) | 로컬 무제한 | 가능(단 원본 레포의 NVIDIA 비상업 의존성 → **ComfyUI 네이티브 구현** 사용) | 24GB GPU 필요 |
| Stable Fast 3D | 로컬 무제한 | 연 매출 $1M 미만 무료 | 6GB GPU, UV 펼친 저폴리 — 몬스터·소품용 |
| Hunyuan3D 2.x | — | **한국 제외** | 사용 안 함 |
| Luma Genie / CSM | — | — | 중단·인수로 제외 |

## 리깅·애니메이션
| 도구 | 무료 한도 | 무료 상업 이용 | 비고 |
|---|---|---|---|
| Mixamo | 무료 | 가능(게임 내 사용, 원본 재배포 금지) | 유지보수 모드 → 받은 파일 보관. 치비는 팔이 머리를 관통하는 문제 |
| Rokoko Create / Vision | 영상 모캡 월 30초, 텍스트→모션 월 5개 | 가능(FAQ) | 스킬 전용 모션 |
| AccuRIG 2 | 무료(Windows) | 직접 만든 캐릭터 가능 | Mixamo 대안 |
| Blender | 무료 | — | Rigify, Decimate, QRemeshify, Rokoko 리타겟 애드온 |

## 2D (일러스트·가챠 카드·아이콘·스토어)
| 도구 | 무료 상업 이용 | 비고 |
|---|---|---|
| ComfyUI 로컬 + Apache 2.0 모델(Z-Image, Qwen-Image, FLUX.2 klein 4B) | 가능(모델별 확인) | 비공개, 스타일 LoRA로 일관성 최고. FLUX.1 dev·Ideogram 오픈 가중치는 비상업 |
| Ideogram | 가능 | 무료 생성물은 공개·삭제 불가. 글자 렌더링 강함(배너·스토어) |
| Adobe Firefly | 가능(Firefly 자체 모델만) | 파트너 모델 결과는 본인 책임 |
| Leonardo | 허용되나 무료 출력물은 공개·IP 문제 | 핵심 캐릭터엔 비권장 |
| Krea / Scenario / Recraft | 불가 | 유료에서만 |

## 추천 (이 프로젝트)
- 3D 캐릭터: ① Meshy 무료(표기 필수; 36명 양산 시 Pro 1~2개월로 소유권 확보) ② TRELLIS.2 ComfyUI 네이티브(24GB GPU) ③ Stable Fast 3D(몬스터·소품)
- 리깅·애니: ① Mixamo ② Rokoko Create
- 2D: ① ComfyUI 로컬 + Apache 2.0 모델 + 자체 스타일 LoRA ② Ideogram ③ Firefly

## 36명 스타일 통일 파이프라인
1. 스타일 바이블: 2~2.5등신, 실루엣 규칙, 32색 팔레트, 툰 램프 1종(docs/art-direction.md와 맞춤).
2. **공통 베이스 바디 하나를 리깅해 36명이 공유**하고, AI로는 머리·헤어·갑옷·무기 파츠만 만들어 붙인다 → 비율·뼈대·애니메이션 자동 통일.
3. 2D 컨셉: 베이스 바디 렌더를 ControlNet 입력으로 고정, 프롬프트 템플릿 하나, 처음 3~5명 승인 후 스타일 LoRA 학습.
4. 이미지→3D(Meshy Smart Topology / TRELLIS.2), 가능하면 정면·측면·후면 입력.
5. Blender 정리: 스케일·피벗 통일, Decimate(각진 느낌), 노멀 재계산, **AI 텍스처의 구운 조명은 버리고 공통 팔레트 텍스처/정점 색으로 다시 칠함**, 영웅당 2~5k 삼각형(권장값).
6. 리깅: Mixamo(텍스처 뺀 FBX) 또는 베이스 바디 웨이트 전송.
7. 애니메이션: idle·run·attack·cast·hit·die·victory 공통 세트 + Rokoko 고유 스킬 모션.
8. GLB → Godot: Skeleton3D Retarget(BoneMap = SkeletonProfileHumanoid), AnimationLibrary 하나를 공유, 카툰 재질은 코드(Art.toonify)가 입힌다.
9. 가챠 카드·아이콘: 최종 3D를 카툰으로 렌더 → img2img(디노이즈 0.3~0.5) + 스타일 LoRA로 덧칠 → 모델과 일러스트가 일치.
10. 라이선스 기록: CREDITS에 에셋별 도구·플랜·라이선스·날짜, 약관 스크린샷 보관, Meshy CC BY 표기.

## 출처(주요)
- Meshy: https://www.meshy.ai/pricing , https://intercom.help/meshy/en/articles/15696428-what-is-included-on-the-free-plan
- Tripo: https://www.tripo3d.ai/pricing
- Hunyuan3D 2.1 라이선스: https://huggingface.co/tencent/Hunyuan3D-2.1/blob/main/LICENSE
- TRELLIS.2: https://huggingface.co/microsoft/TRELLIS.2-4B , https://blog.comfy.org/p/trellis2-and-pixal3d-are-now-native
- Stable Fast 3D: https://huggingface.co/stabilityai/stable-fast-3d , https://stability.ai/license
- Mixamo 라이선스 FAQ: https://community.adobe.com/t5/mixamo-discussions/mixamo-faq-licensing-royalties-ownership-eula-and-tos/m-p/13234775
- Rokoko: https://www.rokoko.com/pricing , https://www.rokoko.com/products/studio/rokoko-create
- Ideogram: https://ideogram.ai/licensing/ · Firefly: https://www.adobe.com/cc-shared/fragments/products/firefly/plans/faq
- Krea: https://www.krea.ai/pricing · Scenario: https://www.scenario.com/pricing · Recraft: https://www.recraft.ai/pricing
- Godot 리타겟: https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/retargeting_3d_skeletons.html

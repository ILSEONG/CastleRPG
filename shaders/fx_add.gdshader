shader_type spatial;
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// 스킬 이펙트 빛(섬광·번개·광선·불꽃·입자). 본문은 fx.gdshaderinc.
// 2026-10-30: 순수 더하기 → 미리 곱한 알파(PREMUL). 빛은 그대로 더하되 바닥을 cover만큼 덮어 — 밝은 풀밭 위에서 고유 색이
// 하얗게 날아가던 문제(스킬이 전부 흰 덩이로 보였다)를 막는다. 어두운 바닥(던전)에서는 거의 그대로 더하기처럼 보인다.
#define PREMUL
#include "res://shaders/fx.gdshaderinc"

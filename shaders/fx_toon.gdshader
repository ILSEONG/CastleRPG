shader_type spatial;
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// 툰 폭발 — 바닥 고리(충격파·흙먼지): 깊이 검사(유닛 뒤로 숨는다). 본문은 fx_toon.gdshaderinc.
#include "res://shaders/fx_toon.gdshaderinc"

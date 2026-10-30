shader_type spatial;
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

// 툰 폭발 — 불덩이·불기둥: 깊이 검사 없이 유닛 위에 그린다(몬스터 무리에 가려 폭발이 안 보이지 않게 — 0.4초 동안만). 본문은 fx_toon.gdshaderinc.
#include "res://shaders/fx_toon.gdshaderinc"

shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// 스킬 이펙트 반투명(빛기둥·지대·휩쓸기 궤적·연기): 밝은 바닥에서도 고유 색이 하얗게 날아가지 않는다. 본문은 fx.gdshaderinc.
#include "res://shaders/fx.gdshaderinc"

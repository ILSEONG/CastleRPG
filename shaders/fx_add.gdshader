shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// 스킬 이펙트 더하기 섞기(섬광·번개·광선·불꽃·입자). 본문은 fx.gdshaderinc.
#include "res://shaders/fx.gdshaderinc"

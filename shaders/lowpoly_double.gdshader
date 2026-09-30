shader_type spatial;
render_mode cull_disabled;

// 양면. 원본 재질이 양면(glTF doubleSided)인 모델용 — 망토·후드처럼 한 겹짜리 메시가 있는 Knight·Rogue·화살.
#include "res://shaders/lowpoly.gdshaderinc"

shader_type spatial;
// 피격 번쩍임(개정 26): 유닛 메시 위에 덧그리는 가산 흰빛(material_overlay). 가장자리가 더 밝다. flash = 인스턴스 값(1 → 0).
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

instance uniform float flash = 0.0;
instance uniform vec4 flash_tint : source_color = vec4(1.0, 0.96, 0.88, 1.0);

void fragment() {
	float rim = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	ALBEDO = flash_tint.rgb * flash * (0.55 + 0.7 * rim * rim);
}

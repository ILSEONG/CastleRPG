shader_type spatial;

// 개정 18 불꽃·빛기둥·눈빛(ArenaKit): 더하기 섞기, 빛 계산·그림자 없음. 색 = 정점 색 × tint × energy.
// flicker > 0: 높이(VERTEX.y)에 비례해 TIME으로 출렁·흔들린다(위상 = 인스턴스 월드 위치 — MultiMesh 인스턴스마다 다르게).
// fade_height > 0: 그 높이로 갈수록 사라진다(빛기둥).
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0);
uniform float energy = 1.0;
uniform float flicker = 0.0;
uniform float fade_height = 0.0;

varying float h;

void vertex() {
	h = VERTEX.y;
	if (flicker > 0.0) {
		float ph = dot(MODEL_MATRIX[3].xz, vec2(1.7, 2.3));
		float k = VERTEX.y;
		VERTEX.y *= 1.0 + flicker * (0.18 * sin(TIME * 11.0 + ph) + 0.08 * sin(TIME * 23.0 + ph * 3.1));
		VERTEX.xz *= 1.0 - flicker * 0.10 * sin(TIME * 9.0 + ph * 1.3);
		VERTEX.x += flicker * k * 0.12 * sin(TIME * 6.0 + ph);
		VERTEX.z += flicker * k * 0.10 * cos(TIME * 5.0 + ph * 0.7);
	}
}

void fragment() {
	float f = fade_height > 0.0 ? clamp(1.0 - h / fade_height, 0.0, 1.0) : 1.0;
	ALBEDO = COLOR.rgb * tint.rgb * energy;
	ALPHA = f;
}

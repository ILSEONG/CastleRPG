shader_type spatial;

// 개정 18 불타는 성 연기 기둥(ArenaKit): 반투명 면, 빛 계산·그림자 없음. 위로 갈수록 흔들리며 옅어지고, 짙은 띠가 위로 흐른다.
// 메시 바닥 y=0, 높이 height. 위상 = 인스턴스 월드 위치(MultiMesh 인스턴스마다 다르게).
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.16, 0.13, 0.12, 1.0);
uniform float height = 14.0;
uniform float opacity = 0.45;

varying float t;
varying float ph;

void vertex() {
	t = clamp(VERTEX.y / height, 0.0, 1.0);
	ph = dot(MODEL_MATRIX[3].xz, vec2(0.9, 1.3));
	VERTEX.x += sin(TIME * 0.7 + VERTEX.y * 0.35 + ph) * 0.6 * t;
	VERTEX.z += cos(TIME * 0.5 + VERTEX.y * 0.3 + ph) * 0.4 * t;
}

void fragment() {
	float puff = 0.65 + 0.35 * sin(t * 18.0 - TIME * 1.6 + ph);
	ALBEDO = mix(color.rgb, color.rgb * 1.8, (1.0 - t) * 0.5);  // 아래는 불빛을 받아 조금 밝다
	ALPHA = opacity * smoothstep(0.0, 0.12, t) * (1.0 - t) * puff;
}

shader_type spatial;

// 용암(ArenaKit.lair, 2026-10-07): 빛 계산 없이 정점 색(면마다 붉은 주황~밝은 주황)으로 빛나고, 밝은 물결이 flow 방향으로 천천히 흐른다.
// fall = true(용암 폭포): 물결이 아래로 빠르게 떨어진다(월드 높이 기준). 그림자·안개 없음.
render_mode unshaded, shadows_disabled, fog_disabled;

uniform vec4 hot : source_color = vec4(1.0, 0.86, 0.45, 1.0);
uniform vec2 flow = vec2(0.25, 0.25);
uniform float glint = 0.55;
uniform bool fall = false;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = fall ? vec2((wp.x - wp.z) * 0.7, wp.y * 0.8 + TIME * 2.4) : wp.xz - flow * TIME;
	float a = sin(p.x * 0.9 + p.y * 0.55) * sin(p.x * -0.4 + p.y * 1.15 + TIME * 0.7);
	float m = smoothstep(0.35, 0.95, a);
	ALBEDO = mix(COLOR.rgb, hot.rgb, m * glint) * (0.92 + 0.08 * sin(TIME * 2.0 + p.x + p.y));
}

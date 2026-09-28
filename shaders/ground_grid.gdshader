shader_type spatial;
render_mode unshaded;

// 월드 좌표 기준 격자 타일 바닥. 성 안은 포장 타일 + 십자 도로, 성 밖은 잔디 체커.
uniform float tile_size = 2.0;
uniform float interior_half = 16.0;
uniform float road_half = 2.0;
uniform vec4 grass_a : source_color = vec4(0.73, 0.84, 0.60, 1.0);
uniform vec4 grass_b : source_color = vec4(0.69, 0.80, 0.56, 1.0);
uniform vec4 paved_a : source_color = vec4(0.88, 0.85, 0.78, 1.0);
uniform vec4 paved_b : source_color = vec4(0.84, 0.81, 0.74, 1.0);
uniform vec4 road : source_color = vec4(0.78, 0.72, 0.62, 1.0);
uniform vec4 line_color : source_color = vec4(0.0, 0.0, 0.0, 0.12);
uniform float line_width = 0.03;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz / tile_size;
	float checker = mod(floor(p.x) + floor(p.y), 2.0);
	vec2 a = abs(world_pos.xz);
	vec3 base;
	if (max(a.x, a.y) < interior_half) {
		base = (min(a.x, a.y) < road_half) ? road.rgb : mix(paved_a.rgb, paved_b.rgb, checker);
	} else {
		base = mix(grass_a.rgb, grass_b.rgb, checker);
	}
	vec2 to_line = 0.5 - abs(fract(p) - 0.5);  // 격자선에서 0
	vec2 aa = fwidth(p);
	vec2 on_line = 1.0 - smoothstep(vec2(line_width), vec2(line_width) + aa, to_line);
	float line = max(on_line.x, on_line.y);
	ALBEDO = mix(base, line_color.rgb, line * line_color.a);
}

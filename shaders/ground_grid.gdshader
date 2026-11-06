shader_type spatial;

// 월드 좌표 기준 격자 타일 바닥. 성 안은 포장 타일 + 십자 도로(+ 가운데가 아닌 성문으로 가는 길), 성 밖은 잔디 체커.
uniform float tile_size = 2.0;
uniform float interior_half = 16.0;
uniform float road_half = 2.0;
// 가운데가 아닌 성문(면마다 성문 2·3개)의 옆 위치 |at|(없으면 0)과 안쪽 통로 깊이: 그 성문 앞 길 + 통로를 따라 가운데 길까지
uniform float gate_off = 0.0;
uniform float lane_depth = 0.0;
// 빛·그림자를 받는다. 아래 색은 main.gd의 태양·주변광 아래에서 예전 무광 바닥과 같은 밝기가 되게 맞춘 값.
uniform vec4 grass_a : source_color = vec4(0.441, 0.511, 0.372, 1.0);
uniform vec4 grass_b : source_color = vec4(0.417, 0.487, 0.347, 1.0);
uniform vec4 paved_a : source_color = vec4(0.531, 0.516, 0.482, 1.0);
uniform vec4 paved_b : source_color = vec4(0.507, 0.492, 0.457, 1.0);
uniform vec4 road : source_color = vec4(0.471, 0.438, 0.384, 1.0);
uniform vec4 line_color : source_color = vec4(0.0, 0.0, 0.0, 0.12);
uniform float line_width = 0.03;
uniform float facet_variation = 0.045;  // 타일을 대각선으로 나눈 두 삼각형의 명암 차이 폭
// 계절(개정 22): grass_a·grass_b를 seasons.gd가 바꾼다. edge_snow > 0 이면 성 안 포장 가장자리 삼각형 일부가 눈 얼룩(겨울).
uniform float edge_snow = 0.0;
uniform vec4 snow_color : source_color = vec4(0.70, 0.73, 0.78, 1.0);
// 맵 퀄리티(2026-11-06): 넓은 얼룩(마른 땅·짙은 풀) — 삼각형 중심에서 잰 값 잡음이라 면마다 한 색(로우폴리 그대로).
// patch_strength 0 이면 예전 바닥. patch_hue: 밝은 얼룩 쪽으로 더하는 색 기울기(어두운 쪽은 반대로).
uniform float patch_strength = 0.12;
uniform float patch_scale = 13.0;
uniform vec3 patch_hue = vec3(0.05, 0.03, -0.07);
// 성 밖(interior_half 바깥) 격자선 세기 배율 — 풀밭에 게임판 같은 선을 줄인다. 성 안 포장 타일 선은 그대로.
uniform float outside_line = 0.35;
// 성 밖 흙길: 성문 축을 따라 바깥으로 이어지는 밟힌 길(괴물 진입로). outer_road_half 0 = 없음. center_lane 1 = 가운데 성문 축도.
uniform float outer_road_half = 0.0;
uniform float center_lane = 1.0;
uniform vec4 path_color : source_color = vec4(0.53, 0.46, 0.35, 1.0);

varying vec3 world_pos;

float hash12(vec2 c) {
	vec3 q = fract(vec3(c.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float vnoise(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz / tile_size;
	float checker = mod(floor(p.x) + floor(p.y), 2.0);
	vec2 a = abs(world_pos.xz);
	vec3 base;
	if (max(a.x, a.y) < interior_half) {
		float d = max(a.x, a.y);
		float along = min(a.x, a.y);
		bool side_road = gate_off > 0.0 && ((abs(along - gate_off) < road_half && d > lane_depth - road_half)
			|| (abs(d - lane_depth) < road_half && along < gate_off));
		base = (along < road_half || side_road) ? road.rgb : mix(paved_a.rgb, paved_b.rgb, checker);
	} else {
		base = mix(grass_a.rgb, grass_b.rgb, checker);
		if (outer_road_half > 0.0) {
			float along_o = min(a.x, a.y);
			float lane = 1e5;
			if (center_lane > 0.5) lane = along_o;
			if (gate_off > 0.0) lane = min(lane, abs(along_o - gate_off));
			// 삼각형마다 가장자리를 들쭉날쭉하게(로우폴리 면 단위), 성에서 멀수록 조금 좁게
			vec2 fc = floor(world_pos.xz / tile_size);
			float jag = hash12(fc * 1.7 + step(fract(world_pos.x / tile_size), fract(world_pos.z / tile_size)) * 7.0) - 0.5;
			float w = outer_road_half * (1.0 - 0.25 * smoothstep(interior_half, interior_half + 80.0, max(a.x, a.y))) + jag * tile_size * 0.9;
			if (lane < w) base = mix(path_color.rgb, base, 0.15 * step(0.0, jag));
		}
	}
	// 로우폴리: 타일마다 대각선으로 나눈 두 삼각형에 서로 다른 명암
	vec2 cell = floor(p);
	float upper = step(fract(p).x, fract(p).y);
	// sin 없는 해시(Hoskins hash12): 큰 인자에서 줄무늬가 생기는 sin 해시와 달리 곱·fract만 쓴다. 중간 곱 (q.x + q.y) * q.z는 ~2e4까지 커지지만
	// 32비트 float 정밀도에서는 fract 뒤에도 자릿수가 충분해 줄무늬·반복이 없다.
	vec3 q = fract(vec3(cell.xyx + upper * vec3(0.37, 0.71, 0.37)) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	float h = fract((q.x + q.y) * q.z);
	float edge = edge_snow * (1.0 - smoothstep(0.0, 2.5 * tile_size, interior_half - max(a.x, a.y)));
	base = mix(base, snow_color.rgb, step(1.0 - edge, h) * step(max(a.x, a.y), interior_half));
	base *= 1.0 + facet_variation * (h * 2.0 - 1.0);
	if (patch_strength > 0.0) {
		vec2 c = (cell + mix(vec2(2.0, 1.0), vec2(1.0, 2.0), upper) / 3.0) * tile_size / patch_scale;
		float t = (vnoise(c) * 0.65 + vnoise(c * 2.7 + 17.0) * 0.35) * 2.0 - 1.0;
		t = clamp(t * 1.6, -1.0, 1.0) * patch_strength * (max(a.x, a.y) < interior_half ? 0.5 : 1.0);
		base = max(base * (1.0 + t) + patch_hue * t, vec3(0.0));
	}
	vec2 to_line = 0.5 - abs(fract(p) - 0.5);  // 격자선에서 0
	vec2 aa = fwidth(p);
	vec2 on_line = 1.0 - smoothstep(vec2(line_width), vec2(line_width) + aa, to_line);
	float line = max(on_line.x, on_line.y) * (max(a.x, a.y) < interior_half ? 1.0 : outside_line);
	ALBEDO = mix(base, line_color.rgb, line * line_color.a);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

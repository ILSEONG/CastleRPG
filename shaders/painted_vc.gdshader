shader_type spatial;

// 무대 메시(정점 색 로우폴리, Art.lowpoly_vc_material과 같은 면 음영) + 바닥 손그림 질감(맵 새로 만들기 2026-11-06).
// 위를 보는 낮은 면(높이 < floor_y)은 floor_tex(월드 xz, floor_m 미터마다 반복)를 칠하고, 정점 색은 floor_ref 대비 배로 곱한다 —
// 판석마다 다르던 명암·그을음·이끼 색은 그대로 남고 그 위에 손그림 결이 보인다. 벽·소품(높은 면·옆면)은 예전 정점 색 그대로.
uniform sampler2D floor_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float floor_m = 10.0;
uniform vec4 floor_ref : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float floor_y = 0.35;
uniform float floor_gain = 0.85;
uniform float vc_amount = 0.85;  // 정점 색 배를 얼마나 따를지(1 = 전부)

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float h12(vec2 c) {
	vec3 q = fract(vec3(c.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float vn(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h12(i), h12(i + vec2(1.0, 0.0)), f.x), mix(h12(i + vec2(0.0, 1.0)), h12(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec3 c = COLOR.rgb;
	vec3 wn = normalize(cross(dFdx(wpos), dFdy(wpos)));
	if (abs(wn.y) > 0.92 && wpos.y < floor_y) {
		vec2 uv = wpos.xz / floor_m;
		vec3 t1 = texture(floor_tex, uv).rgb;
		vec3 t2 = texture(floor_tex, mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * uv * 0.71 + vec2(0.31, 0.17)).rgb;
		vec3 t = mix(t1, t2, smoothstep(0.3, 0.7, vn(wpos.xz / (floor_m * 2.3) + 5.0)));
		vec3 k = mix(vec3(1.0), clamp(c / max(floor_ref.rgb, vec3(0.02)), vec3(0.0), vec3(2.0)), vc_amount);
		c = t * floor_gain * k;
	}
	ALBEDO = c;
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (n.z < 0.0) {
		n = -n;
	}
	NORMAL = n;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}

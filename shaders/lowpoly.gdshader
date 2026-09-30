shader_type spatial;

// 로우폴리 스타일: 원본 알베도(텍스처·색)는 그대로 쓰고, 법선은 화면 미분으로 면마다 하나 → 각진 면 음영.
// 앞면은 항상 카메라를 향하므로(뒷면 컬링) 법선을 카메라 쪽으로 맞춘다 — 화면 y축 방향 규약과 무관.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_texture = true;

void fragment() {
	vec4 c = albedo_color;
	if (use_texture) {
		c *= texture(albedo_tex, UV);
	}
	ALBEDO = c.rgb;
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, -VERTEX) < 0.0) {
		n = -n;
	}
	NORMAL = n;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}

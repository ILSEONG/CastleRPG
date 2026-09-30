// 로우폴리 스타일 공용 본문 — lowpoly.gdshader(한 면)와 lowpoly_double.gdshader(양면)가 include한다.
// 원본 알베도(텍스처·색)는 그대로 쓰고, 법선은 화면 미분으로 면마다 하나 → 각진 면 음영.
// 법선은 항상 카메라 쪽으로 맞춘다 — 화면 y축 방향 규약과 무관하고, 양면 변형에서 뒷면도 같은 음영이 된다.
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

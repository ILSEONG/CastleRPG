// 로우폴리 스타일 공용 본문 — lowpoly.gdshader(한 면)와 lowpoly_double.gdshader(양면)가 include한다.
// 원본 알베도(텍스처·색)는 그대로 쓰고, 법선은 화면 미분으로 면마다 하나 → 각진 면 음영.
// 법선은 항상 카메라 쪽(뷰 공간 +Z)으로 맞춘다 — 화면 y축 방향 규약과 무관하고, 양면 변형에서 뒷면도 같은 음영이 된다.
// 직교 카메라는 시선이 어느 픽셀에서나 -Z라 +Z가 카메라 쪽이다(-VERTEX는 원근 카메라에서만 맞고, 화면 가장자리에서 음영이 뒤집힌다).
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_texture = true;
uniform bool use_vertex_color = false;

void fragment() {
	vec4 c = albedo_color;
	if (use_texture) {
		c *= texture(albedo_tex, UV);
	}
	if (use_vertex_color) {
		// 정점 색은 sRGB로 적는다(팔레트 그대로). 이 렌더러(Compatibility/WebGL)는 fragment()에 오기 전에 이미
		// 선형으로 바꿔 준다 — 캡처 A/B 측정: 여기서 한 번 더 바꾸면 균일 albedo_color(source_color)보다 짙고 탁해졌다.
		c.rgb *= COLOR.rgb;
	}
	ALBEDO = c.rgb;
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (n.z < 0.0) {
		n = -n;
	}
	NORMAL = n;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}

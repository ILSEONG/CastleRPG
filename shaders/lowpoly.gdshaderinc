// 로우폴리 스타일 공용 본문 — lowpoly.gdshader(한 면)와 lowpoly_double.gdshader(양면)가 include한다.
// 원본 알베도(텍스처·색)는 그대로 쓰고, 법선은 화면 미분으로 면마다 하나 → 각진 면 음영.
// 법선은 항상 카메라 쪽(뷰 공간 +Z)으로 맞춘다 — 화면 y축 방향 규약과 무관하고, 양면 변형에서 뒷면도 같은 음영이 된다.
// 직교 카메라는 시선이 어느 픽셀에서나 -Z라 +Z가 카메라 쪽이다(-VERTEX는 원근 카메라에서만 맞고, 화면 가장자리에서 음영이 뒤집힌다).
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_texture = true;
uniform bool use_vertex_color = false;
// 영웅 생김새(개정 23): KayKit 텍스처는 8×4 칸 색 아틀라스. remap_tex(8×4, 칸마다 한 픽셀)의 알파가 1인 칸은
// 그 색 × (텍셀 밝기 / 칸 가운데 밝기)로 바꾼다 — 칸의 위아래 명암(그라데이션)은 그대로, 색만 바뀐다.
uniform bool use_remap = false;
uniform sampler2D remap_tex : source_color, filter_nearest;

void fragment() {
	vec4 c = albedo_color;
	if (use_texture) {
		vec4 t = texture(albedo_tex, UV);
		if (use_remap) {
			ivec2 cell = clamp(ivec2(floor(UV * vec2(8.0, 4.0))), ivec2(0), ivec2(7, 3));
			vec4 r = texelFetch(remap_tex, cell, 0);
			if (r.a > 0.5) {
				vec3 mid = textureLod(albedo_tex, (vec2(cell) + 0.5) / vec2(8.0, 4.0), 0.0).rgb;
				vec3 luma = vec3(0.2126, 0.7152, 0.0722);
				float k = dot(t.rgb, luma) / max(dot(mid, luma), 0.01);
				t.rgb = r.rgb * clamp(k, 0.0, 1.6);
			}
		}
		c *= t;
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

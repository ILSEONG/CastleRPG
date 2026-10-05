// 카툰 렌더링 공용 본문 — toon.gdshader(한 면)와 toon_double.gdshader(양면)가 include한다. 영웅·몬스터(UnitModel)만 쓴다.
// 알베도(텍스처·영웅 칸 색 바꿈·정점 색)는 lowpoly.gdshaderinc와 같다. 법선은 메시 그대로(부드럽게) 두고,
// 빛을 두 단계(밝은 면 / 그늘)로 끊고 가장자리에 테두리 빛(림)을 얹는다. 외곽선은 toon_outline.gdshader(next_pass).
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_texture = true;
uniform bool use_vertex_color = false;
uniform bool use_remap = false;
uniform sampler2D remap_tex : source_color, filter_nearest;
uniform float shade = 0.34;  // 그늘 밝기(빛 대비)
uniform float lit_level = 0.72;  // 밝은 면 밝기(1이면 각진 면 전부가 정면처럼 밝아 색이 바랜다)
uniform float saturation = 1.18;  // 카툰다운 진한 색
uniform float ambient = 0.6;  // 주변광 반영(낮을수록 그늘이 또렷 — AO로 주변광만 줄인다)
uniform float band_soft = 0.05;  // 밝은 면/그늘 경계 폭
uniform float rim = 0.35;  // 테두리 빛 세기

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
		c.rgb *= COLOR.rgb;
	}
	float l = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
	ALBEDO = clamp(mix(vec3(l), c.rgb, saturation), 0.0, 1.0);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	AO = ambient;
	AO_LIGHT_AFFECT = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(0.0, band_soft, ndl) * step(0.5, ATTENUATION);
	DIFFUSE_LIGHT += mix(shade, lit_level, lit) * LIGHT_COLOR / PI;
	float edge = smoothstep(0.62, 0.7, 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0));
	SPECULAR_LIGHT += edge * lit * rim * LIGHT_COLOR / PI;
}

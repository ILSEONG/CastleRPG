// 실사풍 공용 본문 — real.gdshader(한 면)와 real_double.gdshader(양면)가 include한다. 영웅·몬스터(UnitModel)만 쓴다.
// 알베도(텍스처·영웅 칸 색 바꿈·정점 색)는 lowpoly.gdshaderinc와 같다. 그 위에:
//  · 부드러운 법선 + 월드 좌표 잡음으로 미세한 표면 요철(천·가죽 결)과 알베도 얼룩 — 단색 면이 플라스틱처럼 보이지 않게.
//  · 재질 추정(알베도의 채도·밝기): 회색 금속(갑옷·칼날)은 금속성·낮은 거칠기, 그 밖(피부·천)은 거친 비금속.
//  · 하늘 반사 흉내(이 렌더러는 BG_COLOR라 반사광이 없다): 법선이 위를 볼수록 하늘색, 아래는 땅색을 금속·가장자리에 더한다.
// 빛 계산은 엔진 PBR(빛·그림자)을 그대로 쓴다. 외곽선 없음.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_texture = true;
uniform bool use_vertex_color = false;
uniform bool use_remap = false;
uniform sampler2D remap_tex : source_color, filter_nearest;
uniform vec3 sky_color : source_color = vec3(0.62, 0.74, 0.92);
uniform vec3 ground_color : source_color = vec3(0.32, 0.36, 0.24);
uniform float grain = 0.09;  // 표면 요철 세기
uniform float grain_scale = 9.0;  // 요철 크기(1 m에 몇 번)

varying vec3 wpos;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

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
	float sat = (max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b))) / max(max(c.r, max(c.g, c.b)), 0.001);
	float metal = smoothstep(0.22, 0.08, sat) * smoothstep(0.12, 0.3, l) * smoothstep(0.78, 0.6, l);  // 채도 낮은 중간 회색 = 금속(흰 칠·천은 아님)
	float n1 = noise3(wpos * grain_scale);
	float n2 = noise3(wpos * grain_scale * 2.7 + 13.1);
	vec3 albedo = c.rgb * (0.9 + 0.2 * n1);
	ALBEDO = albedo;
	vec3 n = NORMAL;
	if (!FRONT_FACING) {
		n = -n;
	}
	vec3 bump = vec3(n1 - 0.5, n2 - 0.5, noise3(wpos * grain_scale * 1.9 + 7.7) - 0.5);
	n = normalize(n + bump * grain * mix(1.0, 0.4, metal));
	NORMAL = n;
	METALLIC = metal * 0.45;
	ROUGHNESS = mix(0.72 - 0.12 * n2, 0.25 + 0.1 * n1, metal);
	SPECULAR = 0.5;
	// 하늘 반사 흉내: 월드 법선의 위/아래로 하늘·땅 색. 금속은 강하게, 비금속은 가장자리(프레넬)만 살짝.
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 env = mix(ground_color, sky_color, clamp(wn.y * 0.5 + 0.5, 0.0, 1.0));
	float fres = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 4.0);
	float spark = pow(clamp(wn.y, 0.0, 1.0), 6.0);  // 위를 보는 금속 면의 하늘 빛 맺힘
	EMISSION = env * (metal * (0.28 + 0.35 * spark) * albedo / max(l, 0.2) + fres * 0.14);
	AO = 0.85;
	AO_LIGHT_AFFECT = 0.0;
}

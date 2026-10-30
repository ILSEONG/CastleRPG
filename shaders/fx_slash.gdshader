shader_type spatial;
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// 검기 궤적(SkillVfx.blade_arc, 2026-10-30 사용자 참고 그림): 넓게 휘어 도는 빛 띠.
// 정점 색 r = 폭 방향(0 안쪽 ~ 1 바깥 날), g = 길이 방향(0 꼬리 ~ 1 머리), a = 불투명도.
// 폭: 바깥 날 끝은 가는 검은 선(테두리) → 바로 안쪽에 하얀 심 → 고유 색 몸 → 안쪽으로 갈수록 투명. 길이를 따라 가는 속도선이 흐른다.
// head(0 → 1.3)가 머리 위치 — 머리가 지나간 뒤 len만큼만 남고 꼬리부터 옅어진다(휘두르는 궤적). fade로 전체가 사라진다.
instance uniform vec4 tint : source_color = vec4(0.3, 0.9, 1.0, 1.0);
instance uniform float fade : hint_range(0.0, 1.0) = 1.0;
instance uniform float head = 1.0;
uniform float len = 0.8;

void fragment() {
	float w = COLOR.r;
	float t = COLOR.g;
	float vis = smoothstep(head - len, head - len * 0.35, t) * (1.0 - smoothstep(head, head + 0.04, t));
	float lines = 0.8 + 0.2 * sin(w * 46.0 + t * 7.0 - TIME * 20.0);  // 속도선
	vec3 hotc = mix(tint.rgb, vec3(1.0), 0.85);
	vec3 col;
	float a;
	if (w > 0.95) {  // 바깥 검은 테두리
		col = tint.rgb * 0.08;
		a = 0.9;
	} else if (w > 0.8) {  // 하얀 날
		col = hotc;
		a = 1.0;
	} else {  // 몸: 안쪽으로 갈수록 투명
		float k = w / 0.8;
		col = mix(tint.rgb, hotc, 0.45 * k * k) * lines;
		a = pow(k, 1.2) * 0.95;
	}
	a *= COLOR.a * vis * fade * tint.a;
	ALBEDO = col * a + col * 0.35 * a * step(0.8, w);  // 날만 살짝 빛을 더한다
	ALPHA = clamp(a, 0.0, 1.0);
}

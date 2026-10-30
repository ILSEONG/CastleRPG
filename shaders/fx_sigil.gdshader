shader_type spatial;
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// 마법진·문양(SkillVfx.sigil, 2026-10-30): 바닥에 누운 사각형 하나(QuadMesh)에 UV 극좌표로 그린다 — 텍스처·추가 메시 없음, 그리기 한 번.
// 겹: 바깥 두 줄 고리 + 그 사이를 도는 룬 띠(끊긴 눈금) + 안쪽 다각형 별(sides각, 반대로 돈다) + 가운데 작은 고리.
// 속성마다 sides(별 꼭짓점)·spin(도는 빠르기)·tint(색)가 다르다(인스턴스 값). 선은 하얀 심 + 색 번짐(premul: 밝은 바닥에서도 보인다).
// fade 1 → 0: 바깥부터 지워진다. grow 0 → 1: 안에서 바깥으로 그려지며 펼쳐진다(시전 준비).
instance uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.3, 1.0);
instance uniform float fade : hint_range(0.0, 1.0) = 1.0;
instance uniform float grow : hint_range(0.0, 1.0) = 1.0;
instance uniform float sides = 6.0;
instance uniform float spin = 1.0;

float band(float x, float c, float w) {
	return 1.0 - smoothstep(0.0, w, abs(x - c));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float ang = atan(p.y, p.x);
	float t = TIME * spin;
	float w = fwidth(r) * 1.5 + 0.006;
	float line = band(r, 0.96, w * 1.6) + band(r, 0.84, w) + band(r, 0.30, w) * 0.9;
	// 룬 띠: 0.86~0.94 사이에 끊긴 눈금이 돈다
	float ra = ang + t * 0.6;
	float tick = step(0.55, fract(ra * 24.0 / 6.2831853)) * step(0.3, fract(ra * 3.0 / 6.2831853 + 0.1));
	line += tick * band(r, 0.90, 0.035) * 0.8;
	// 별: sides각 다각형 두 개를 엇갈려(별 모양) — 반대로 돈다
	float sa = 6.2831853 / sides;
	for (int k = 0; k < 2; k++) {
		float a2 = ang - t * (k == 0 ? -0.8 : 0.8) + float(k) * sa * 0.5;
		float d = cos(sa * 0.5) / cos(mod(a2, sa) - sa * 0.5);  // 정다각형 반지름(1 = 꼭짓점)
		line += band(r, 0.80 * d, w * 1.2) * 0.85 * step(r, 0.82);
	}
	// 가운데 문양: 꼭짓점에서 중심으로 가는 살
	float spoke = band(fract((ang - t * 0.8) / sa + 0.5), 0.5, 0.02 + w) * step(0.3, r) * step(r, 0.8);
	line += spoke * 0.5;
	float reveal = smoothstep(grow * 1.05, grow * 1.05 - 0.08, r);  // 안에서 바깥으로 펼쳐진다
	float vanish = smoothstep(fade * 1.1, fade * 1.1 - 0.15, r);  // 바깥부터 지워진다
	float m = clamp(line, 0.0, 1.0) * reveal * vanish;
	float soft = (1.0 - r) * 0.18 * reveal * vanish;  // 안쪽 옅은 빛
	vec3 hot = mix(tint.rgb, vec3(1.0), 0.4);
	float a = clamp(m * 0.75 + soft * 0.5, 0.0, 1.0) * tint.a;
	ALBEDO = (tint.rgb * soft + hot * m) * tint.a;
	ALPHA = a;
}

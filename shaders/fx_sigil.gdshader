shader_type spatial;
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// 마법진·문양(SkillVfx.sigil, 2026-10-30, 같은 날 사용자 참고 그림으로 다시): 바닥에 누운 사각형 하나(PlaneMesh)에 UV 극좌표로 그린다 — 텍스처·추가 메시 없음, 그리기 한 번.
// 겹: 바깥 두 줄 고리 사이를 도는 룬 글자 띠(칸마다 해시로 고른 획 조합 — 글자처럼 보인다) + 안쪽 작은 룬 띠(반대로 돈다)
// + 다각형 별(sides각, 두 개 엇갈려 반대로 돈다) + 별 꼭짓점의 빛 웅덩이 + 가운데 고리.
// 선은 하얀 심 + 고유 색 번짐(선 둘레로 부드럽게 퍼지는 빛 — 블룸 없이도 빛나 보인다). premul이라 밝은 바닥에서도 보인다.
// fade 1 → 0: 바깥부터 지워진다. grow 0 → 1: 안에서 바깥으로 그려지며 펼쳐진다(시전 준비).
instance uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.3, 1.0);
instance uniform float fade : hint_range(0.0, 1.0) = 1.0;
instance uniform float grow : hint_range(0.0, 1.0) = 1.0;
instance uniform float sides = 6.0;
instance uniform float spin = 1.0;

float band(float x, float c, float w) {
	return 1.0 - smoothstep(0.0, w, abs(x - c));
}

float h1(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

// 룬 한 칸: q = 칸 안 좌표(-1..1), id = 칸 번호. 세로획 + (해시로) 가로획 둘·대각선·작은 고리 중 몇 개.
float glyph(vec2 q, float id, float w) {
	float g = band(q.x, (h1(id) - 0.5) * 0.6, w);  // 세로획(살짝 어긋난 자리)
	g *= step(abs(q.y), 0.85);
	if (h1(id + 1.3) > 0.4) g = max(g, band(q.y, 0.6, w) * step(abs(q.x), 0.6));
	if (h1(id + 2.7) > 0.5) g = max(g, band(q.y, -0.2 + h1(id + 9.1) * 0.4, w) * step(abs(q.x), 0.55));
	if (h1(id + 4.1) > 0.55) g = max(g, band(q.x + q.y * 0.7, 0.0, w) * step(abs(q.y), 0.75));
	if (h1(id + 5.9) > 0.7) g = max(g, band(length(q - vec2(0.0, -0.45)), 0.3, w));
	return g * step(0.12, h1(id + 7.7));  // 가끔 빈칸(띄어쓰기)
}

float rune_ring(float r, float ang, float rc, float hw, float cells, float rot, float w) {
	float a = ang + rot;
	float u = fract(a / 6.2831853) * cells;
	float id = floor(u);
	vec2 q = vec2((fract(u) - 0.5) * 2.0, (r - rc) / hw);
	return glyph(q, id, w) * step(abs(r - rc), hw);
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
	float line = band(r, 0.97, w * 1.4) + band(r, 0.82, w) + band(r, 0.3, w) * 0.9 + band(r, 0.25, w) * 0.6;
	line += rune_ring(r, ang, 0.895, 0.055, 44.0, t * 0.35, 0.22) * 0.95;  // 바깥 룬 글자 띠
	line += rune_ring(r, ang, 0.37, 0.04, 22.0, -t * 0.5, 0.25) * 0.7;  // 안쪽 작은 룬 띠
	float sa = 6.2831853 / sides;
	float star = 0.0;
	for (int k = 0; k < 2; k++) {
		float a2 = ang - t * (k == 0 ? -0.8 : 0.8) + float(k) * sa * 0.5;
		float d = cos(sa * 0.5) / cos(mod(a2, sa) - sa * 0.5);
		star += band(r, 0.78 * d, w * 1.2) * 0.85 * step(r, 0.8);
	}
	line += star;
	// 별 꼭짓점 빛 웅덩이(바깥 고리 위)
	float av = mod(ang + t * 0.8 + sa * 0.5, sa) - sa * 0.5;
	vec2 pv = vec2(av * 0.82, r - 0.82);
	float pool = exp(-dot(pv, pv) * 260.0);
	float reveal = smoothstep(grow * 1.05, grow * 1.05 - 0.08, r);
	float vanish = smoothstep(fade * 1.1, fade * 1.1 - 0.15, r);
	float m = clamp(line, 0.0, 1.0) * reveal * vanish;
	// 번짐: 선 근처를 넓게 한 번 더(고리·별 위주 — 값싼 근사)
	float bloom = (band(r, 0.97, 0.05) + band(r, 0.82, 0.05) + band(r, 0.895, 0.07) * 0.6 + star * 0.4) * 0.35 + pool * 1.2;
	bloom *= reveal * vanish;
	float soft = (1.0 - r) * 0.16 * reveal * vanish;
	vec3 hot = mix(tint.rgb, vec3(1.0), 0.55);
	// 어두운 바탕: 원 안 바닥을 고유 색 그늘로 살짝 눌러 빛 선이 밝은 풀밭에서도 도드라진다(참고 그림의 어두운 바닥 대신)
	float under = 0.3 * smoothstep(1.0, 0.93, r) * reveal * vanish;
	float a = clamp(m * 0.85 + bloom * 0.45 + soft * 0.5 + under, 0.0, 1.0) * tint.a;
	ALBEDO = (tint.rgb * 0.1 * under + tint.rgb * (soft + bloom * 0.8) + hot * m * 1.15) * tint.a;
	ALPHA = a;
}

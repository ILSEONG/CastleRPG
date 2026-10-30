// 툰 폭발(SkillVfx.explosion, 2026-10-30 타격 임팩트): 셀 셰이딩 만화풍 불덩이·충격파 고리·흙먼지 고리.
// - shade 1(덩어리): 면 방향(+ 왼쪽 위 가짜 빛 + 노이즈)으로 4단 — 진한 테두리 → 몸(tint) → 밝은 띠(hot) → 하얀 심. 경계가 딱 끊겨 만화처럼 보인다.
// - shade 0(판): 정점 색 r(0 바깥 ~ 1 안쪽)을 3단으로 끊어 tint → hot → 하얀 빛(고리·흙먼지 줄기).
// - 사라짐(fade 1 → 0): 노이즈 낮은 곳부터 딱 끊기며 구멍이 나고, 구멍 가장자리는 진한 테두리 색(타고 남은 불덩이처럼).
// 색은 인스턴스 값(tint·hot) — 메시는 흰 한 벌을 모든 속성이 같이 쓴다. 비용: 값 노이즈 한 겹.
instance uniform float fade : hint_range(0.0, 1.0) = 1.0;
instance uniform vec4 tint : source_color = vec4(1.0, 0.42, 0.08, 1.0);
instance uniform vec4 hot : source_color = vec4(1.0, 0.8, 0.25, 1.0);
uniform float shade = 1.0;
uniform float glow = 0.2;  // 밝은 띠에 더하기로 얹는 빛

varying vec3 lp;

void vertex() {
	lp = VERTEX + MODEL_MATRIX[3].xyz * 0.37;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	float n = vnoise(lp * 2.4 + vec3(0.0, -1.5, 0.0) * TIME);
	vec3 rim = tint.rgb * vec3(0.62, 0.42, 0.42);  // 진한 테두리(조금 더 붉고 어둡게)
	vec3 white = mix(hot.rgb, vec3(1.0, 1.0, 0.94), 0.75);
	vec3 col;
	float l;
	if (shade > 0.5) {
		vec3 nv = normalize(NORMAL);
		float facing = abs(dot(nv, normalize(VIEW)));
		float key = max(dot(nv, normalize(vec3(-0.45, 0.65, 0.6))), 0.0);
		l = facing * 0.72 + key * 0.3 + (n - 0.5) * 0.3;
		col = l < 0.36 ? rim : (l < 0.58 ? tint.rgb : (l < 0.8 ? hot.rgb : white));
	} else {
		l = COLOR.r + (n - 0.5) * 0.2;
		col = l < 0.34 ? tint.rgb : (l < 0.7 ? hot.rgb : white);
	}
	float thr = (1.0 - fade) * 1.1 - 0.06;
	if (n < thr) {
		discard;
	}
	col = n < thr + 0.09 && fade < 0.98 ? rim : col;  // 구멍 가장자리
	float a = clamp(COLOR.a * tint.a, 0.0, 1.0);
	ALBEDO = col * a + col * glow * step(0.58, l) * a;
	ALPHA = a;
}

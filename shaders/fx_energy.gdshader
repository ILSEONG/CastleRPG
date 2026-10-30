shader_type spatial;
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// 스킬 에너지(SkillVfx, 2026-10-30 스킬 연출 고도화): 불덩이·검기·충격파·전류 같은 "덩어리 있는 빛"을 텍스처 없이 그린다.
// - 색: 정점 색 하나에서 3단 그라데이션을 만든다 — 가장자리(어둡고 진한 색) → 몸(정점 색) → 심(하얗게 달아오른 색).
//   화면을 정면으로 보는 면일수록·노이즈가 높을수록 심 쪽(로우폴리 면마다 밝기가 달라 각진 아트와 어울린다).
// - 섞기: 미리 곱한 알파(premul) — 몸은 바닥을 덮어 밝은 풀밭 위에서도 제 색이 진하게 보이고(가산처럼 하얗게 날아가지 않는다),
//   심만 살짝 더한다(glow). 그래서 블룸 후처리 없이도 빛나 보인다.
// - 노이즈: 메시 국소 좌표 3D 값 노이즈 두 겹이 scroll 방향으로 흐른다(불꽃은 위로, 검기는 옆으로). UV가 없는 MeshKit 메시에도 그대로 쓴다.
// - 사라짐(fade 1 → 0): 그냥 옅어지지 않고 노이즈 낮은 곳부터 갉아먹히며 흩어진다(가장자리 먼저). 갉아먹힌 경계는 잠깐 밝게 탄다.
// 비용: 프래그먼트당 값 노이즈 1~2겹(해시 8~16번) — 큰 화면 덮개는 피하고 짧게 쓴다(SkillVfx가 크기·수명을 관리한다).
instance uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float body = 0.85;  // 몸 불투명도
uniform float core = 0.85;  // 심이 하얗게 달아오르는 정도
uniform float edge_dark = 0.42;  // 가장자리 색 = 몸 색 × 이것
uniform float glow = 0.35;  // 더하기로 얹는 빛(심 쪽)
uniform float noise_amt = 0.55;  // 노이즈가 밝기·갉아먹힘에 주는 몫
uniform float noise_scale = 2.2;
uniform vec3 scroll = vec3(0.0, -1.4, 0.0);  // 노이즈가 흐르는 방향·빠르기(m/초, 국소 좌표)
uniform vec3 hot_color : source_color = vec3(1.0, 0.98, 0.92);  // 심 색(불꽃은 노란 흰빛)

varying vec3 lp;

void vertex() {
	lp = VERTEX + MODEL_MATRIX[3].xyz * 0.37;  // 같은 메시를 여러 곳에 띄워도 무늬가 다르게
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
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	vec3 q = lp * noise_scale + scroll * TIME;
	float n = vnoise(q);
	if (noise_amt > 0.5) {  // 일렁임이 큰 재질(불꽃·기본)만 두 번째 겹 — 검기·결정·오라는 한 겹(값싸게). 재질 값이라 분기 비용이 없다
		n = n * 0.65 + vnoise(q * 2.3 + vec3(3.1, 1.7, 5.3)) * 0.35;
	}
	float heat = clamp(mix(facing, n, noise_amt) * 1.35 - 0.2, 0.0, 1.0);
	vec3 base = COLOR.rgb;
	vec3 edge = base * edge_dark;
	vec3 hot = mix(base, hot_color, core);
	vec3 col = heat < 0.5 ? mix(edge, base, heat * 2.0) : mix(base, hot, (heat - 0.5) * 2.0);
	// 갉아먹힘: fade가 내려갈수록 문턱이 오른다. 가장자리(비스듬한 면)가 먼저 사라진다.
	float thr = (1.0 - fade) * 1.15 - 0.12 + (1.0 - facing) * 0.18 * noise_amt;
	float keep = smoothstep(thr, thr + 0.12, n);
	float burn = (1.0 - smoothstep(thr + 0.02, thr + 0.16, n)) * step(0.02, 1.0 - fade);  // 갉아먹히는 경계가 잠깐 밝게
	float a = clamp(COLOR.a * body * keep * mix(0.55, 1.0, facing), 0.0, 1.0);
	ALBEDO = col * a + (hot * glow * heat + hot * burn * 0.6) * keep * COLOR.a;
	ALPHA = a;
}

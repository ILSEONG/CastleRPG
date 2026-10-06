// 스킬 이펙트 공용 본문 — fx_add.gdshader(더하기 섞기: 섬광·번개·광선)와 fx_soft.gdshader(반투명: 빛기둥·지대·연기)가 include한다.
// 색 = 정점 색(CPUParticles3D면 입자 색이 곱해져 온다) × boost. 알파 = 정점 알파 × fade.
// fade(인스턴스마다): Fx가 수명 끝에 1 → 0으로 내린다 — 재질 하나를 모든 이펙트가 함께 쓰면서도 따로 사라진다.
// flicker > 0: 높이(VERTEX.y)에 비례해 TIME으로 출렁·흔들린다(불꽃 혀). 위상 = 정점 xz + 인스턴스 위치 — 메시 하나에 담은 혀들이 따로 흔들린다.
// rim > 0: 화면에 비스듬한 면일수록 밝게(빛기둥·돔 가장자리가 또렷하다).
instance uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float boost = 1.0;
uniform float flicker = 0.0;
uniform float rim = 0.0;

void vertex() {
	if (flicker > 0.0) {
		float ph = dot(VERTEX.xz, vec2(5.3, 7.1)) + dot(MODEL_MATRIX[3].xz, vec2(1.7, 2.3));
		float k = max(VERTEX.y, 0.0);
		VERTEX.y *= 1.0 + flicker * (0.22 * sin(TIME * 12.0 + ph) + 0.1 * sin(TIME * 25.0 + ph * 3.1));
		VERTEX.x += flicker * k * 0.14 * sin(TIME * 7.0 + ph);
		VERTEX.z += flicker * k * 0.12 * cos(TIME * 6.0 + ph * 0.7);
	}
}

void fragment() {
	float r = 1.0;
	if (rim > 0.0) {
		r = 1.0 + rim * (1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))));
	}
	ALBEDO = COLOR.rgb * boost * r;
	ALPHA = clamp(COLOR.a * fade, 0.0, 1.0);
}

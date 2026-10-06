shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

// 빛무리(Fx.halo): 카메라를 보는 사각형 하나에 가운데가 밝고 가장자리로 부드럽게 사라지는 원 — 텍스처 없이 UV로 계산한다.
// 각진 이펙트 뒤에 깔아 "빛나는" 느낌만 더한다(블룸 후처리 없이). 색·세기는 인스턴스마다(tint·fade).
// depth_test_disabled: 땅·몸에 잘리지 않는다(작고 옅어 앞뒤가 바뀌어도 티 나지 않는다).
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float fade : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	// 빌보드: 모델 회전을 버리고 배율만 남겨 카메라 평면에 세운다
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float d = clamp(length(UV - 0.5) * 2.0, 0.0, 1.0);
	float a = (1.0 - d) * (1.0 - d);
	a += 0.6 * pow(max(1.0 - d * 2.2, 0.0), 2.0);  // 작은 밝은 심
	ALBEDO = tint.rgb * a * fade * 0.7;
	ALPHA = 1.0;
}

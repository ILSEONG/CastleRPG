shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

// 카툰 외곽선(뒤집은 껍질): 카툰 재질의 next_pass. 정점을 법선 쪽으로 밀어낸 뒷면만 진한 색으로 그린다.
// 미는 거리는 화면에서 width_px 픽셀이 되게 맞춘다(줌과 상관없이 같은 두께): 법선이 화면에 비친 길이로 나눠
// 옆을 향한 면(윤곽)은 정확히, 카메라를 향한 면은 덜 민다. view_h = 3D 화면 높이(픽셀, Art.toon_view_height).
uniform vec4 outline_color : source_color = vec4(0.08, 0.05, 0.07, 1.0);
uniform float width_px = 2.2;
uniform float view_h = 1280.0;

void vertex() {
	vec3 vpos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float px = 2.0 / (abs(PROJECTION_MATRIX[1][1]) * view_h);  // 직교: 화면 1픽셀 = 뷰 공간 길이
	if (PROJECTION_MATRIX[3][3] < 0.5) {
		px *= abs(vpos.z);  // 원근 카메라(초상화 등)는 거리만큼
	}
	float on_screen = length((mat3(MODELVIEW_MATRIX) * NORMAL).xy);  // 모델 법선 1이 화면에서 차지하는 뷰 길이
	VERTEX += NORMAL * width_px * px / max(on_screen, 0.25);
}

void fragment() {
	ALBEDO = outline_color.rgb;
}

shader_type spatial;

// 관중(ArenaKit.colosseum, 2026-10-07): 로우폴리 정점 색(lowpoly.gdshaderinc 한 면) + 사람마다 다른 박자로 들썩인다.
// 사람 번호 = 메시 로컬 z를 seat_from부터 seat m 칸으로, 줄 = 로컬 |x|를 row_from부터 row m 칸으로 나눈 것 + 양옆(부호).
// 사람은 칸 가운데쯤 서 있어 몸·머리·팔 정점이 한 칸 안에 든다(ArenaKit._stands).
uniform float hop = 0.16;
uniform float seat = 0.9;
uniform float seat_from = 0.0;
uniform float row = 1.25;
uniform float row_from = 0.0;

void vertex() {
	float id = floor((VERTEX.z - seat_from) / seat) * 7.31 + floor((abs(VERTEX.x) - row_from) / row) * 3.17 + sign(VERTEX.x) * 1.73;
	float ph = fract(sin(id) * 43758.5453);
	VERTEX.y += hop * max(0.0, sin(TIME * (5.0 + 3.0 * ph) + ph * 6.2832));
}

#include "res://shaders/lowpoly.gdshaderinc"

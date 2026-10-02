extends RefCounted
## 로우폴리 레시피: 성 부품·건물·자연물·산 메시를 만든다(MeshKit). 오토로드 참조 없음.
## 성 부품 로컬 규약: 길이 방향 +X(가운데 기준), 두께 방향 Z(+Z = 성 바깥), 바닥 y=0. 계단만 예외(stairs 주석).
const Balance := preload("res://scripts/balance.gd")
const MeshKit := preload("res://scripts/mesh_kit.gd")

## 팔레트(sRGB, 셰이더가 그대로 씀). 해를 받는 윗면·지붕은 선형 약 ×2.3~2.5라 채널이 ~0.69를 넘으면 흰색으로 날아간다 →
## 윗면에 쓰는 색은 채널 ≤ 0.69, 해 쪽 지붕 경사는 더 밝게 받아 ≤ 0.64. 해 쪽 벽(+Z, 약 ×1.6)도 0.8이면 흰색으로 날아갔다(캡처).
const STONE := Color(0.66, 0.63, 0.58)
const STONE_DARK := Color(0.52, 0.50, 0.47)
const WOOD := Color(0.55, 0.38, 0.24)
const WOOD_DARK := Color(0.40, 0.28, 0.19)
const LOG_END := Color(0.68, 0.54, 0.36)
const ROOF_BLUE := Color(0.27, 0.43, 0.68)
const ROOF_RED := Color(0.62, 0.25, 0.21)
const ROOF_ORANGE := Color(0.64, 0.40, 0.19)
const ROOF_PURPLE := Color(0.50, 0.38, 0.64)
const ROOF_GREEN := Color(0.33, 0.50, 0.36)
const PLASTER := Color(0.74, 0.73, 0.69)
const WINDOW := Color(0.24, 0.26, 0.32)
const GLOW := Color(0.45, 0.72, 0.78)
const METAL := Color(0.58, 0.60, 0.64)
const LEAF := Color(0.36, 0.60, 0.34)
const LEAF_DARK := Color(0.25, 0.46, 0.30)
const ROCK := Color(0.50, 0.50, 0.53)
const SNOW := Color(0.70, 0.72, 0.76)
const CROP := Color(0.69, 0.60, 0.28)
const SOIL := Color(0.45, 0.34, 0.24)
const FLAG := Color(0.72, 0.24, 0.22)

const MERLON_H := 0.6
const MERLON_T := 0.4
const PILLAR_W := 1.2                      # 문루 기둥 탑 폭(성문 가장자리 바깥으로)
const PILLAR_Z0 := 0.45                    # 기둥 탑 안쪽 면(z). 성벽 위 중심선(z=0)을 걷는 영웅이 기둥을 뚫지 않게 바깥 절반에만 둔다
const PILLAR_OUT := 0.6                    # 기둥 탑이 성벽 바깥면보다 튀어나온 길이
const PARAPET_GAP := Balance.STAIR_GAP + 2.0 * Balance.STAIR_RUN / Balance.STAIR_STEPS  # 안쪽 난간을 양 끝에서 비우는 길이(계단 윗단 → 성벽 위 길)


## 성벽 한 토막: 몸통 + 바깥쪽 가장자리 톱니(1m 간격) + 안쪽 낮은 난간(양 끝은 계단 길이라 비움).
static func wall_run(length: float) -> ArrayMesh:
	var k = MeshKit.new()
	k.box(Vector3.ZERO, Vector3(length, Balance.WALL_H, Balance.WALL_T), STONE)
	_merlons(k, length, Balance.WALL_H)
	var rail := length - 2.0 * PARAPET_GAP
	if rail > 0.0:
		k.box(Vector3(0, Balance.WALL_H, -Balance.WALL_T / 2.0 + 0.1), Vector3(rail, 0.25, 0.2), STONE_DARK)
	return k.commit()


## 문루: 성문 좌우 기둥 탑(바깥 절반, 파란 피라미드 지붕) + 성문 위 통로 다리. 아래(0~WALL_H−0.6)는 통로.
static func gatehouse() -> ArrayMesh:
	var k = MeshKit.new()
	var h := Balance.WALL_H
	var z1 := Balance.WALL_T / 2.0 + PILLAR_OUT
	k.box(Vector3(0, h - 0.6, 0), Vector3(Balance.GATE_W, 0.6, Balance.WALL_T), STONE)
	_merlons(k, Balance.GATE_W, h)
	for s in [-1.0, 1.0]:
		var x: float = s * (Balance.GATE_W / 2.0 + PILLAR_W / 2.0)
		var zc := (PILLAR_Z0 + z1) / 2.0
		k.box(Vector3(x, 0, zc), Vector3(PILLAR_W, h + 1.2, z1 - PILLAR_Z0), STONE)
		k.pyramid(Vector3(x, h + 1.2, zc), PILLAR_W + 0.3, 1.1, ROOF_BLUE)
	return k.commit()


## 나무 문짝 두 짝(가로 띠 두 줄). 파괴되면 이 메시만 숨긴다.
static func gate_doors() -> ArrayMesh:
	var k = MeshKit.new()
	var w := Balance.GATE_W / 2.0 - 0.05
	var h := Balance.WALL_H - 0.7
	var z := Balance.WALL_T / 2.0 - 0.35
	for s in [-1.0, 1.0]:
		var x: float = s * Balance.GATE_W / 4.0
		k.box(Vector3(x, 0, z), Vector3(w, h, 0.3), WOOD)
		for y in [0.45, h - 0.65]:
			k.box(Vector3(x, y, z), Vector3(w, 0.18, 0.36), STONE_DARK)
	return k.commit()


## 모서리 탑: 8각 기둥 + 윗단 톱니 + 8각 원뿔 파란 지붕 + 깃발. 바닥 중심이 원점.
static func corner_tower() -> ArrayMesh:
	var k = MeshKit.new()
	var r := Balance.TOWER_SIZE / 2.0 + 0.2
	var h := Balance.WALL_H + 2.0
	k.prism_n(Vector3.ZERO, 8, r, r, h, STONE, PI / 8.0)
	for i in 8:
		var a := TAU * i / 8.0
		var m := r * cos(PI / 8.0) - 0.2  # 면 가운데(변심 거리)에서 안쪽으로
		k.xform = Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * m, h, sin(a) * m))
		k.box(Vector3.ZERO, Vector3(0.4, MERLON_H, 0.6), STONE_DARK)
	k.xform = Transform3D.IDENTITY
	var roof_y := h + MERLON_H
	k.cone(Vector3(0, roof_y, 0), 8, r + 0.3, 2.5, ROOF_BLUE, PI / 8.0)
	k.box(Vector3(0, roof_y + 2.5, 0), Vector3(0.1, 1.2, 0.1), WOOD)
	k.box(Vector3(0.4, roof_y + 3.25, 0), Vector3(0.7, 0.4, 0.05), FLAG)
	return k.commit()


## 계단(로컬 규약이 다르다): 길이 방향 +X로 올라간다 — x=0 높이 0, x=STAIR_RUN 높이 WALL_H. 폭 Z = STAIR_W(가운데 기준).
## 단 i는 x 구간 [i, i+1]×run/steps, 윗면 높이 (i+0.5)×WALL_H/steps(바닥부터 채운 박스): 아랫단→윗단 직선 경사를 걷는
## 영웅의 발이 반 단 넘게 묻히지 않는다. 마지막 단의 뒤 절반은 WALL_H로 올려 성벽 위와 같은 높이로 맞춘다.
static func stairs() -> ArrayMesh:
	var k = MeshKit.new()
	var n := Balance.STAIR_STEPS
	var d := Balance.STAIR_RUN / n
	for i in n:
		var w := d if i < n - 1 else d / 2.0
		k.box(Vector3(d * i + w / 2.0, 0, 0), Vector3(w, Balance.WALL_H * (i + 0.5) / n, Balance.STAIR_W), STONE_DARK)
	k.box(Vector3(Balance.STAIR_RUN - d / 4.0, 0, 0), Vector3(d / 2.0, Balance.WALL_H, Balance.STAIR_W), STONE_DARK)
	return k.commit()


## 성벽 위 바깥 가장자리 톱니: 1m 안팎 간격으로 번갈아. 양 끝이 톱니.
static func _merlons(k, length: float, y: float) -> void:
	var n := maxi(1, floori(length / 1.0))
	if n % 2 == 0:
		n += 1  # 홀수 칸 → 양 끝이 톱니라 좌우 대칭
	var step := length / n
	for i in range(0, n, 2):
		var x := -length / 2.0 + step * (i + 0.5)
		k.box(Vector3(x, y, Balance.WALL_T / 2.0 - MERLON_T / 2.0), Vector3(step, MERLON_H, MERLON_T), STONE_DARK)


# --- 건물 8종 (부지 중심 로컬, 바닥 y=0, 문·간판은 카메라가 보는 +Z/+X 쪽) ---

## 건물 메시 하나(그리기 호출 하나). 부지 = size×TILE − BUILDING_GAP 안(3×3 → ±2.7, 성채 4×4 → ±3.7).
static func building(id: String) -> ArrayMesh:
	var k = MeshKit.new()
	match id:
		"keep": _keep(k)
		"barracks": _barracks(k)
		"tavern": _tavern(k)
		"lab": _lab(k)
		"houses": _houses(k)
		"lumber": _lumber(k)
		"quarry": _quarry(k)
		"farm": _farm(k)
		"archery": _archery(k)
		"stable": _stable(k)
		_: push_error("unknown building %s" % id)
	return k.commit()


## 성채: 석조 본체 + 톱니, 네 모서리 6각 탑(파란 원뿔), 가운데 8각 탑(파란 원뿔 + 깃발), 문·창.
static func _keep(k) -> void:
	k.box(Vector3.ZERO, Vector3(5.2, 3.6, 5.2), STONE)
	k.box(Vector3(0, 3.6, 0), Vector3(5.5, 0.3, 5.5), STONE_DARK)
	for i in 4:
		k.xform = Transform3D(Basis(Vector3.UP, i * PI / 2.0), Vector3.ZERO)
		for x in [-1.0, 0.0, 1.0]:
			k.box(Vector3(x, 3.9, 2.55), Vector3(0.5, 0.45, 0.35), STONE_DARK)
	k.xform = Transform3D.IDENTITY
	for c in [Vector3(-2.5, 0, -2.5), Vector3(2.5, 0, -2.5), Vector3(2.5, 0, 2.5), Vector3(-2.5, 0, 2.5)]:
		k.prism_n(c, 6, 0.95, 0.95, 5.0, STONE)
		k.cone(c + Vector3(0, 5.0, 0), 6, 1.15, 1.9, ROOF_BLUE)
	k.prism_n(Vector3(0, 3.9, 0), 8, 1.6, 1.6, 4.2, STONE, PI / 8.0)
	k.prism_n(Vector3(0, 8.1, 0), 8, 1.75, 1.75, 0.3, STONE_DARK, PI / 8.0)
	k.cone(Vector3(0, 8.4, 0), 8, 1.95, 3.0, ROOF_BLUE, PI / 8.0)
	k.box(Vector3(0, 11.4, 0), Vector3(0.12, 1.5, 0.12), WOOD)
	k.box(Vector3(0.45, 12.3, 0), Vector3(0.8, 0.5, 0.05), FLAG)
	k.box(Vector3(0, 0, 2.6), Vector3(1.4, 2.2, 0.2), WOOD)
	for x in [-1.6, 1.6]:
		k.box(Vector3(x, 1.8, 2.6), Vector3(0.4, 0.8, 0.1), WINDOW)
		k.box(Vector3(2.6, 1.8, x), Vector3(0.1, 0.8, 0.4), WINDOW)
	k.box(Vector3(0, 6.0, 1.5), Vector3(0.4, 0.8, 0.1), WINDOW)
	k.box(Vector3(1.5, 6.0, 0), Vector3(0.1, 0.8, 0.4), WINDOW)


## 보병 막사: 돌 기단 위 긴 목조 막사 + 빨간 박공지붕, 문·창, 앞마당 무기 걸이(창 3자루)·방패 걸이(직사각 방패 2, 개정 13), 깃대(파란 깃발).
static func _barracks(k) -> void:
	for x in [-1.55, -0.45]:  # 방패 걸이: 기둥 둘 + 가로대, 빨간 방패 둘(가운데 쇠 장식)
		k.box(Vector3(x, 0, 1.9), Vector3(0.12, 1.0, 0.12), WOOD)
	k.box(Vector3(-1.0, 0.85, 1.9), Vector3(1.25, 0.1, 0.12), WOOD)
	for x in [-1.25, -0.75]:
		k.box(Vector3(x, 0.3, 2.0), Vector3(0.38, 0.55, 0.06), ROOF_RED)
		k.box(Vector3(x, 0.52, 2.04), Vector3(0.1, 0.1, 0.04), METAL)
	k.box(Vector3(0, 0, -0.5), Vector3(5.0, 0.35, 3.3), STONE_DARK)
	_house(k, Vector3(0, 0.35, -0.5), Vector3(4.6, 2.1, 3.0), 1.8, WOOD, ROOF_RED)
	k.box(Vector3(0, 0.35, 1.0), Vector3(1.0, 1.6, 0.12), WOOD_DARK)
	for x in [-1.5, 1.5]:
		k.box(Vector3(x, 1.25, 1.0), Vector3(0.7, 0.7, 0.1), WINDOW)
	for x in [0.6, 2.0]:
		k.box(Vector3(x, 0, 1.9), Vector3(0.14, 1.1, 0.14), WOOD)
	k.box(Vector3(1.3, 0.85, 1.9), Vector3(1.6, 0.12, 0.14), WOOD)
	for x in [0.85, 1.3, 1.75]:
		k.box(Vector3(x, 0.1, 1.8), Vector3(0.07, 1.5, 0.07), WOOD_DARK)
		k.pyramid(Vector3(x, 1.6, 1.8), 0.16, 0.3, METAL)
	k.box(Vector3(-2.2, 0, 1.9), Vector3(0.14, 5.2, 0.14), WOOD)
	k.box(Vector3(-1.75, 4.3, 1.9), Vector3(0.8, 0.8, 0.05), ROOF_BLUE)


## 주점: 1층 석조 + 2층 흰 벽(목재 띠) + 주황 박공지붕, 굴뚝, 통 2개(6각), 걸린 간판.
static func _tavern(k) -> void:
	var c := Vector3(-0.25, 0, -0.5)
	k.box(c, Vector3(4.0, 1.7, 3.2), STONE)
	k.box(c + Vector3(0, 1.7, 0), Vector3(4.3, 0.18, 3.5), WOOD)
	_house(k, c + Vector3(0, 1.88, 0), Vector3(4.3, 1.5, 3.5), 1.7, PLASTER, ROOF_ORANGE)
	k.box(c + Vector3(1.2, 3.0, 0.8), Vector3(0.55, 2.6, 0.55), STONE_DARK)
	k.box(c + Vector3(-0.6, 0, 1.6), Vector3(0.9, 1.4, 0.12), WOOD_DARK)
	for x in [-1.0, 1.0]:
		k.box(c + Vector3(x, 2.3, 1.75), Vector3(0.6, 0.7, 0.1), WINDOW)
	k.box(c + Vector3(2.15, 2.3, 0), Vector3(0.1, 0.7, 0.6), WINDOW)
	k.box(c + Vector3(1.0, 0.5, 1.6), Vector3(0.6, 0.6, 0.1), WINDOW)
	for p in [Vector3(1.7, 0, 1.9), Vector3(2.25, 0, 1.15)]:
		k.prism_n(p, 6, 0.38, 0.38, 0.75, WOOD)
		k.prism_n(p + Vector3(0, 0.5, 0), 6, 0.41, 0.41, 0.1, WOOD_DARK)
	k.box(c + Vector3(1.95, 2.85, 1.95), Vector3(0.1, 0.1, 0.8), WOOD_DARK)
	k.box(c + Vector3(1.95, 2.15, 2.1), Vector3(0.08, 0.6, 0.6), CROP)


## 연구소: 8각 원통 탑(보라 원뿔 + 빛나는 결정) + 둥근 창, 작은 부속 건물(보라 지붕).
static func _lab(k) -> void:
	var t := Vector3(-0.7, 0, -0.7)
	k.prism_n(t, 8, 1.5, 1.35, 5.2, STONE, PI / 8.0)
	k.prism_n(t + Vector3(0, 5.2, 0), 8, 1.6, 1.6, 0.3, STONE_DARK, PI / 8.0)
	k.cone(t + Vector3(0, 5.5, 0), 8, 1.9, 3.0, ROOF_PURPLE, PI / 8.0)
	k.cone(t + Vector3(0, 9.0, 0), 4, 0.4, 0.7, GLOW)
	k.xform = Transform3D(Basis(Vector3.RIGHT, PI), t + Vector3(0, 9.0, 0))
	k.cone(Vector3.ZERO, 4, 0.4, 0.5, GLOW)
	k.xform = Transform3D.IDENTITY
	for yaw in [0.0, PI / 2.0]:
		_disc(k, t + Vector3(sin(yaw) * 1.3, 3.6, cos(yaw) * 1.3), yaw, 0.38, GLOW)
	k.box(t + Vector3(0, 0, 1.3), Vector3(0.9, 1.6, 0.25), WOOD_DARK)
	_house(k, Vector3(1.2, 0, 1.0), Vector3(2.2, 1.5, 2.0), 1.0, PLASTER, ROOF_PURPLE, PI / 2.0)
	_disc(k, Vector3(2.2, 0.85, 1.0), PI / 2.0, 0.3, WINDOW)


## 민가: 작은 집 3채(빨강·파랑·주황 지붕) + 앞마당 울타리.
static func _houses(k) -> void:
	_house(k, Vector3(-1.2, 0, -1.2), Vector3(2.2, 1.9, 1.9), 1.3, PLASTER, ROOF_RED)
	_house(k, Vector3(1.3, 0, -0.9), Vector3(2.2, 1.7, 1.8), 1.2, STONE, ROOF_BLUE, PI / 2.0)
	_house(k, Vector3(-1.1, 0, 1.3), Vector3(1.9, 1.6, 1.6), 1.2, PLASTER, ROOF_ORANGE)
	k.box(Vector3(-0.6, 1.9, -0.8), Vector3(0.35, 1.7, 0.35), STONE_DARK)
	k.box(Vector3(-0.8, 0, -0.25), Vector3(0.6, 1.2, 0.1), WOOD_DARK)
	k.box(Vector3(-1.8, 0.9, -0.25), Vector3(0.5, 0.5, 0.1), WINDOW)
	k.box(Vector3(2.2, 0, -0.6), Vector3(0.1, 1.2, 0.6), WOOD_DARK)
	k.box(Vector3(-0.7, 0, 2.1), Vector3(0.55, 1.1, 0.1), WOOD_DARK)
	k.box(Vector3(-1.6, 0.8, 2.1), Vector3(0.45, 0.45, 0.1), WINDOW)
	k.box(Vector3(1.45, 0.35, 2.4), Vector3(2.0, 0.08, 0.08), WOOD)
	k.box(Vector3(2.4, 0.35, 1.45), Vector3(0.08, 0.08, 2.0), WOOD)
	for p in [Vector3(0.5, 0, 2.4), Vector3(1.45, 0, 2.4), Vector3(2.4, 0, 2.4), Vector3(2.4, 0, 1.45), Vector3(2.4, 0, 0.5)]:
		k.box(p, Vector3(0.12, 0.6, 0.12), WOOD)


## 벌목장: 기둥 네 개 + 초록 지붕의 작업 헛간(작업대), 누운 통나무 더미(5각), 그루터기 + 도끼.
static func _lumber(k) -> void:
	var s := Vector3(-0.6, 0, -1.1)
	for p in [Vector3(-1.5, 0, -1.0), Vector3(1.5, 0, -1.0), Vector3(-1.5, 0, 1.0), Vector3(1.5, 0, 1.0)]:
		k.box(s + p, Vector3(0.25, 2.4, 0.25), WOOD)
	k.gable(s + Vector3(0, 2.4, 0), Vector3(3.3, 0, 2.4), 1.3, ROOF_GREEN, 0.3)
	k.box(s + Vector3(0, 0, 0.1), Vector3(2.0, 0.8, 0.8), WOOD_DARK)
	_log(k, s + Vector3(-0.9, 0.8 + 0.2, 0.1), 1.8, 0.25)
	var r := 0.33
	for row in [[0, [1.0, 1.66, 2.32]], [1, [1.33, 1.99]], [2, [1.66]]]:  # 줄마다 반 칸 어긋나 쌓는다
		for z in row[1]:
			_log(k, Vector3(0.1, r * (0.81 + row[0] * 1.6), z), 2.4, r)
	for p in [Vector3(-1.9, 0, 1.3), Vector3(-1.0, 0, 2.1)]:
		k.prism_n(p, 6, 0.38, 0.38, 0.45, WOOD)
		k.prism_n(p + Vector3(0, 0.45, 0), 6, 0.3, 0.3, 0.02, LOG_END)
	k.xform = Transform3D(Basis(Vector3.BACK, -0.5), Vector3(-1.9, 0.45, 1.3))
	k.box(Vector3.ZERO, Vector3(0.07, 0.8, 0.07), WOOD_DARK)
	k.box(Vector3(0.12, -0.05, 0), Vector3(0.3, 0.25, 0.05), METAL)
	k.xform = Transform3D.IDENTITY


## 채석장: 각진 바위 더미, 잘린 석재 블록 더미, 작은 기중기(돛대 + 비스듬한 팔 + 쳇바퀴 + 밧줄 + 매달린 돌).
## 팔이 수평이면 교수대처럼 읽혀서(캡처) 위로 비스듬히 세우고 쳇바퀴를 달았다.
static func _quarry(k) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	k.rock(Vector3(-1.1, 0.6, -1.1), 1.35, ROCK, rng, 0.8, 0.0)
	k.rock(Vector3(-1.9, 0.3, 0.4), 0.75, ROCK, rng, 0.7, 0.0)
	k.rock(Vector3(0.3, 0.3, -1.9), 0.7, ROCK, rng, 0.7, 0.0)
	for p in [Vector3(0.9, 0, 1.2), Vector3(1.9, 0, 1.2), Vector3(1.4, 0.6, 1.2)]:
		k.box(p, Vector3(0.9, 0.6, 0.9), STONE)
	k.box(Vector3(1.4, 0, 2.2), Vector3(1.4, 0.5, 0.6), STONE_DARK)
	k.box(Vector3(-0.6, 0, 1.6), Vector3(0.8, 0.5, 0.8), STONE)
	k.box(Vector3(1.9, 0, -1.5), Vector3(1.1, 0.25, 1.1), WOOD_DARK)
	k.box(Vector3(1.9, 0.25, -1.5), Vector3(0.3, 3.6, 0.3), WOOD)
	_disc(k, Vector3(2.1, 1.25, -1.5), PI / 2.0, 0.95, WOOD)
	k.box(Vector3(2.25, 1.1, -1.5), Vector3(0.1, 0.3, 0.3), WOOD_DARK)
	k.xform = Transform3D(Basis(Vector3.BACK, -0.45), Vector3(1.9, 3.5, -1.5))  # 팔: −X(화면 왼쪽 위)로 뻗으며 위로, 끝 ≈ (−0.62, 4.72, −1.5)
	k.box(Vector3(-1.4, -0.11, 0), Vector3(2.8, 0.22, 0.22), WOOD)
	k.xform = Transform3D.IDENTITY
	k.box(Vector3(-0.62, 2.9, -1.5), Vector3(0.05, 1.8, 0.05), WOOD_DARK)
	k.box(Vector3(-0.62, 2.4, -1.5), Vector3(0.6, 0.5, 0.6), STONE)


## 농장: 헛간(빨간 박공지붕), 작은 풍차(흰 탑 + 날개 4), 밭고랑(노랑·초록 줄).
static func _farm(k) -> void:
	_house(k, Vector3(-1.1, 0, -1.3), Vector3(2.4, 1.8, 2.0), 1.5, WOOD, ROOF_RED)
	k.box(Vector3(-1.1, 0, -0.3), Vector3(1.0, 1.4, 0.12), WOOD_DARK)
	var m := Vector3(1.35, 0, -1.4)
	k.prism_n(m, 8, 0.95, 0.6, 4.0, PLASTER, PI / 8.0)
	k.cone(m + Vector3(0, 4.0, 0), 8, 0.8, 1.0, ROOF_RED, PI / 8.0)
	var hub := m + Vector3(0, 3.6, 0.65)
	k.box(hub - Vector3(0, 0.15, 0.1), Vector3(0.3, 0.3, 0.3), WOOD_DARK)
	for i in 4:
		k.xform = Transform3D(Basis(Vector3.BACK, PI / 4.0 + i * PI / 2.0), hub + Vector3(0, 0, 0.03))
		k.box(Vector3(0, 0.12, 0), Vector3(0.38, 1.45, 0.06), WOOD)
	k.xform = Transform3D.IDENTITY
	k.box(Vector3(0, 0, 1.45), Vector3(5.2, 0.06, 2.2), SOIL)
	for i in 4:
		k.box(Vector3(0, 0.06, 0.62 + i * 0.55), Vector3(4.8, 0.22, 0.32), CROP if i % 2 == 0 else LEAF)


## 궁병 훈련소(개정 13): 지붕 있는 사격대(나무 바닥·기둥 넷·초록 박공지붕·사격 난간), 과녁 2개(흰·빨강 동심원 원판, 카메라 쪽을 봄), 화살통.
static func _archery(k) -> void:
	var c := Vector3(-1.3, 0, -0.8)
	k.box(c, Vector3(1.9, 0.15, 2.7), WOOD_DARK)
	for p in [Vector3(-0.9, 0, -1.3), Vector3(0.9, 0, -1.3), Vector3(-0.9, 0, 1.3), Vector3(0.9, 0, 1.3)]:
		k.box(c + p, Vector3(0.2, 2.0, 0.2), WOOD)
	k.xform = Transform3D(Basis(Vector3.UP, PI / 2.0), c)  # 용마루가 Z 방향
	k.gable(Vector3(0, 2.0, 0), Vector3(2.6, 0, 1.8), 0.9, ROOF_GREEN)
	k.xform = Transform3D.IDENTITY
	k.box(c + Vector3(0.9, 0, 0), Vector3(0.12, 0.9, 2.4), WOOD)  # 사격 난간(과녁 쪽)
	for t in [Vector3(1.5, 0, -1.5), Vector3(1.6, 0, 1.0)]:
		var yaw := PI / 4.0
		var side := Basis(Vector3.UP, yaw) * Vector3.RIGHT
		var back := -(Basis(Vector3.UP, yaw) * Vector3.BACK) * 0.12
		for s in [-1.0, 1.0]:
			k.box(t + side * s * 0.35 + back, Vector3(0.1, 1.15, 0.1), WOOD_DARK)
		var front := Basis(Vector3.UP, yaw) * Vector3.BACK
		for i in 4:  # 바깥부터 흰·빨강 번갈아, 안쪽 원판이 조금씩 앞으로
			_disc(k, t + Vector3(0, 1.1, 0) + front * (0.02 * i), yaw, 0.6 - 0.15 * i, PLASTER if i % 2 == 0 else ROOF_RED)
	var q := Vector3(-0.1, 0, 1.1)  # 화살통 + 화살 셋(깃 흰색)
	k.prism_n(q, 6, 0.16, 0.13, 0.6, WOOD_DARK)
	for d in [Vector3(-0.05, 0, 0.03), Vector3(0.05, 0, -0.02), Vector3(0.0, 0, 0.06)]:
		k.box(q + d + Vector3(0, 0.6, 0), Vector3(0.03, 0.3, 0.03), WOOD)
		k.box(q + d + Vector3(0, 0.82, 0), Vector3(0.06, 0.1, 0.02), PLASTER)


## 기병 마구간(개정 13): 긴 마구간(빨간 박공지붕, 마구간 문 셋), 앞마당 울타리, 건초 더미, 여물통(물).
static func _stable(k) -> void:
	_house(k, Vector3(-0.1, 0, -1.2), Vector3(4.6, 1.8, 2.0), 1.2, WOOD, ROOF_RED)
	for x in [-1.5, -0.1, 1.3]:
		k.box(Vector3(x, 0, -0.18), Vector3(0.9, 1.0, 0.1), WOOD_DARK)  # 반쪽 문
		k.box(Vector3(x, 1.05, -0.19), Vector3(0.9, 0.5, 0.08), WINDOW)  # 위는 열린 칸
	for x in [-2.3, -1.4, -0.5, 0.4]:  # 울타리: 앞(z 2.2)과 왼쪽(x −2.3)
		k.box(Vector3(x, 0, 2.2), Vector3(0.12, 0.8, 0.12), WOOD)
	for z in [0.4, 1.3]:
		k.box(Vector3(-2.3, 0, z), Vector3(0.12, 0.8, 0.12), WOOD)
	for y in [0.35, 0.65]:
		k.box(Vector3(-0.95, y, 2.2), Vector3(2.7, 0.08, 0.06), WOOD)
		k.box(Vector3(-2.3, y, 1.3), Vector3(0.06, 0.08, 1.8), WOOD)
	k.box(Vector3(1.7, 0, 1.6), Vector3(0.8, 0.5, 0.55), CROP)  # 건초 더미 둘
	k.box(Vector3(1.75, 0.5, 1.6), Vector3(0.7, 0.45, 0.5), CROP.darkened(0.08))
	k.box(Vector3(-0.6, 0, 1.3), Vector3(1.2, 0.35, 0.4), WOOD_DARK)  # 여물통 + 물
	k.box(Vector3(-0.6, 0.3, 1.3), Vector3(1.0, 0.06, 0.28), ROOF_BLUE)


## 말(개정 13 기병, 원점 = 발 사이 바닥, 머리 +Z): 몸통·목·머리·다리 넷·꼬리, 갈색(갈기·꼬리는 진하게). 기병 등 높이 = HORSE_BACK.
const HORSE_BACK := 1.15
const HORSE := Color(0.50, 0.33, 0.20)
const HORSE_DARK := Color(0.28, 0.19, 0.13)


static func horse() -> ArrayMesh:
	var k = MeshKit.new()
	for p in [Vector3(-0.17, 0, 0.45), Vector3(0.17, 0, 0.45), Vector3(-0.17, 0, -0.45), Vector3(0.17, 0, -0.45)]:
		k.box(p, Vector3(0.14, 0.75, 0.14), HORSE)
		k.box(p, Vector3(0.15, 0.12, 0.15), HORSE_DARK)  # 발굽
	k.box(Vector3(0, 0.7, 0), Vector3(0.5, 0.45, 1.25), HORSE)  # 몸통(위 = HORSE_BACK)
	k.xform = Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3(0, 0.95, 0.5))  # 목: 앞(+Z)으로 기울어 올라간다(위 끝 ≈ (0, 1.57, 0.92))
	k.box(Vector3.ZERO, Vector3(0.28, 0.75, 0.32), HORSE)
	k.box(Vector3(0, 0, -0.17), Vector3(0.1, 0.8, 0.08), HORSE_DARK)  # 갈기(목 뒤)
	k.xform = Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0, 1.5, 0.95))  # 머리: 코가 아래 앞으로
	k.box(Vector3(0, -0.15, 0.12), Vector3(0.24, 0.3, 0.5), HORSE)
	k.xform = Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3(0, 1.0, -0.62))  # 꼬리: 뒤로 늘어진다
	k.box(Vector3(0, -0.5, 0), Vector3(0.12, 0.55, 0.1), HORSE_DARK)
	k.xform = Transform3D.IDENTITY
	return k.commit()


## 집 한 채: 벽 박스 + 박공지붕 + 벽색 박공 삼각형(지붕 끝이 테두리처럼 보인다). yaw = 용마루 방향(0: X). k.xform을 쓰고 되돌린다.
static func _house(k, base: Vector3, size: Vector3, roof_h: float, wall: Color, roof: Color, yaw := 0.0) -> void:
	k.xform = Transform3D(Basis(Vector3.UP, yaw), base)
	k.box(Vector3.ZERO, size, wall)
	k.gable(Vector3(0, size.y, 0), Vector3(size.x, 0, size.z), roof_h, roof)
	var hx := size.x / 2.0 + 0.26  # 지붕 끝면(처마 0.25) 바로 바깥
	var w := size.z / 2.0
	var h := roof_h * w / (w + 0.25)
	for s in [-1.0, 1.0]:
		k.face([Vector3(s * hx, size.y, -w), Vector3(s * hx, size.y, w), Vector3(s * hx, size.y + h, 0)], Vector3(s, 0, 0), wall)
	k.xform = Transform3D.IDENTITY


## 8각 원판(창·방패): 중심 center, 앞면이 +Z를 yaw만큼 돌린 방향을 본다. k.xform을 쓰고 되돌린다.
static func _disc(k, center: Vector3, yaw: float, r: float, color: Color) -> void:
	k.xform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI / 2.0), center)
	k.prism_n(Vector3.ZERO, 8, r, r, 0.1, color, PI / 8.0)
	k.xform = Transform3D.IDENTITY


## +X로 누운 5각 통나무(밑면이 평평), 시작 start(축 위 점), +X 끝에 밝은 나이테 면. k.xform을 쓰고 되돌린다.
static func _log(k, start: Vector3, length: float, r: float) -> void:
	k.xform = Transform3D(Basis(Vector3.BACK, -PI / 2.0), start)
	k.prism_n(Vector3.ZERO, 5, r, r, length, WOOD, PI / 5.0)
	k.prism_n(Vector3(0, length, 0), 5, r * 0.8, r * 0.8, 0.02, LOG_END, PI / 5.0)
	k.xform = Transform3D.IDENTITY


# --- 성 밖 자연물·산 (바닥 y=0, 한 표면) ---

## 계절 팔레트 pal(개정 22, seasons.gd가 넘긴다): 빈 사전 = 기본색(여름). 없는 키는 기본색. 같은 rng 상태면 같은 모양.

## 침엽수: 5각 줄기 + 원뿔 3층(위로 갈수록 작게), 높이 약 5~7m. pal: leaf·leaf_dark, snow = 층마다 눈 모자.
static func tree_pine(rng: RandomNumberGenerator, pal := {}) -> ArrayMesh:
	var k = MeshKit.new()
	var s := rng.randf_range(1.0, 1.3)
	k.prism_n(Vector3.ZERO, 5, 0.3 * s, 0.25 * s, 1.2 * s, WOOD)
	var y := 0.9 * s
	var r := 1.9 * s
	for i in 3:
		var h := (2.4 - 0.3 * i) * s
		var sides := rng.randi_range(6, 7)
		var rot := rng.randf_range(0.0, TAU)
		k.cone(Vector3(0, y, 0), sides, r, h, pal.get("leaf", LEAF) if i % 2 == 0 else pal.get("leaf_dark", LEAF_DARK), rot)
		if pal.get("snow", false):  # 층 위쪽을 덮는 조금 큰 원뿔(겹친 면 깜빡임 없게 바깥으로)
			k.cone(Vector3(0, y + h * 0.45, 0), sides, r * 0.6, h * 0.58, SNOW, rot)
		y += h * 0.55
		r *= 0.72
	return k.commit()


## 활엽수: 5각 줄기 + 각진 둥근 수관(흔든 20면체). pal: leaf(수관 색), bare = 수관 없이 앙상한 가지(겨울).
static func tree_round(rng: RandomNumberGenerator, pal := {}) -> ArrayMesh:
	var k = MeshKit.new()
	var r := rng.randf_range(1.6, 2.2)
	var trunk := rng.randf_range(1.4, 2.0)
	var top := trunk + r * 0.5
	k.prism_n(Vector3.ZERO, 5, 0.32, 0.26, top, WOOD)
	if not pal.get("bare", false):
		k.rock(Vector3(0, trunk + r * 0.8, 0), r, pal.get("leaf", LEAF), rng, 0.9)
		return k.commit()
	for i in 5:  # 위로 벌어진 가는 가지 5개(둘레를 돌며 높이 번갈아)
		var tilt := Basis(Vector3.BACK, rng.randf_range(0.45, 0.85))
		k.xform = Transform3D(Basis(Vector3.UP, TAU * i / 5.0 + rng.randf_range(-0.3, 0.3)) * tilt, Vector3(0, top - 0.25 - 0.35 * (i % 2), 0))
		k.prism_n(Vector3.ZERO, 4, 0.11, 0.04, r * rng.randf_range(0.9, 1.25), WOOD_DARK)
	k.xform = Transform3D.IDENTITY
	return k.commit()


## 덤불: 작은 각진 덩어리 2~3개. pal: bush.
static func bush(rng: RandomNumberGenerator, pal := {}) -> ArrayMesh:
	var k = MeshKit.new()
	for i in rng.randi_range(2, 3):
		var r := rng.randf_range(0.55, 0.9)
		k.rock(Vector3(rng.randf_range(-0.7, 0.7), r * 0.4, rng.randf_range(-0.7, 0.7)), r, pal.get("bush", LEAF_DARK), rng, 0.8, 0.0)
	return k.commit()


## 바위 무더기: 큰 바위 하나 + 작은 바위 1~3개(밑면 평평).
static func rock_cluster(rng: RandomNumberGenerator) -> ArrayMesh:
	var k = MeshKit.new()
	for i in rng.randi_range(2, 4):
		var r := rng.randf_range(1.0, 1.5) if i == 0 else rng.randf_range(0.4, 0.8)
		var a := rng.randf_range(0.0, TAU)
		var d := 0.0 if i == 0 else rng.randf_range(1.0, 1.8)
		k.rock(Vector3(cos(a) * d, r * 0.3, sin(a) * d), r, ROCK, rng, 0.7, 0.0)
	return k.commit()


## 산: 7~9각 원뿔을 흔든 봉우리(반지름 14~20, 높이 16~26). 면마다 한 색(면 중심 높이): 아래 1/3 초록, 가운데 바위, 꼭대기 눈.
## 절반은 옆에 낮은 봉우리를 하나 더 붙인다. pal: low(아래 띠 색), rock_line·snow_line(띠 경계 높이 비율, 기본 1/3·2/3).
static func mountain(rng: RandomNumberGenerator, pal := {}) -> ArrayMesh:
	var k = MeshKit.new()
	var r := rng.randf_range(14.0, 20.0)
	var h := rng.randf_range(16.0, 26.0)
	_peak(k, Vector3.ZERO, r, h, h, rng, pal)
	if rng.randf() < 0.5:
		var a := rng.randf_range(0.0, TAU)
		_peak(k, Vector3(cos(a), 0, sin(a)) * r * 0.6, r * 0.7, h * rng.randf_range(0.55, 0.75), h, rng, pal)
	return k.commit()


## 봉우리 하나: 바닥 고리·중간 고리 둘(흔듦) + 꼭짓점. band_h = 색 띠를 나누는 전체 높이.
static func _peak(k, base: Vector3, radius: float, height: float, band_h: float, rng: RandomNumberGenerator, pal := {}) -> void:
	var n := rng.randi_range(7, 9)
	var rings := []
	for ring in [[0.0, 1.0], [0.36, 0.66], [0.64, 0.36]]:  # (높이 비율, 반지름 비율)
		var row := []
		for i in n:
			var a := TAU * (i + rng.randf_range(-0.25, 0.25)) / n
			var rr: float = radius * ring[1] * rng.randf_range(0.82, 1.15)
			var y: float = height * ring[0] * rng.randf_range(0.88, 1.12)
			row.append(base + Vector3(cos(a) * rr, y, sin(a) * rr))
		rings.append(row)
	var apex := base + Vector3(rng.randf_range(-0.12, 0.12) * radius, height, rng.randf_range(-0.12, 0.12) * radius)
	var below := base - Vector3(0, height, 0)  # 원뿔 면의 바깥 = 축 아래 이 점에서 멀어지는 쪽
	for ri in 2:
		for i in n:
			var j := (i + 1) % n
			_mtri(k, [rings[ri][i], rings[ri][j], rings[ri + 1][j]], below, band_h, pal)
			_mtri(k, [rings[ri][i], rings[ri + 1][j], rings[ri + 1][i]], below, band_h, pal)
	for i in n:
		_mtri(k, [rings[2][i], rings[2][(i + 1) % n], apex], below, band_h, pal)


static func _mtri(k, tri: Array, below: Vector3, band_h: float, pal: Dictionary) -> void:
	var c: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
	var t := c.y / band_h
	var col: Color = pal.get("low", LEAF_DARK) if t < pal.get("rock_line", 1.0 / 3.0) else (ROCK if t < pal.get("snow_line", 2.0 / 3.0) else SNOW)
	k.face(tri, c - below, col)


# --- 상인 수레 (원점 = 수레 중심 바닥, 폭 X ≤ 2.4, 깊이 Z ≤ 1.6, 높이 ≤ 2.6) ---

## 나무 수레: 바닥 상자 + 바퀴 2개(8각 기둥, X축) + 줄무늬 차양(기둥 4개, 빨강/흰 띠) + 상자·자루.
static func merchant_cart() -> ArrayMesh:
	var k = MeshKit.new()
	k.box(Vector3(0, 0.45, 0), Vector3(2.0, 0.35, 1.2), WOOD)
	for x in [-1.16, 1.0]:  # 바퀴: X축으로 눕힌 8각 기둥(차체 옆에 붙음)
		k.xform = Transform3D(Basis(Vector3.BACK, -PI / 2.0), Vector3(x, 0.4157, 0.0))  # 8각 변심 거리 = 0.45·cos(π/8) → 바닥이 y=0
		k.prism_n(Vector3.ZERO, 8, 0.45, 0.45, 0.16, WOOD_DARK, PI / 8.0)
	k.xform = Transform3D.IDENTITY
	for p in [Vector3(-0.9, 0.8, -0.5), Vector3(0.9, 0.8, -0.5), Vector3(-0.9, 0.8, 0.5), Vector3(0.9, 0.8, 0.5)]:
		k.box(p, Vector3(0.1, 1.5, 0.1), WOOD_DARK)
	var n := 6  # 차양: X 방향 띠가 번갈아 빨강/흰, 앞(+Z)으로 살짝 기울어 내려옴
	var w := 2.2 / n
	for i in n:
		var x0 := -1.1 + i * w
		var col := ROOF_RED if i % 2 == 0 else PLASTER
		var a := Vector3(x0, 2.3, -0.65)
		var b := Vector3(x0 + w, 2.3, -0.65)
		var c := Vector3(x0 + w, 2.0, 0.75)
		var d := Vector3(x0, 2.0, 0.75)
		k.face([a, b, c, d], Vector3(0, 1.0, 0.2), col)
		k.face([a, b, c, d], Vector3(0, -1.0, -0.2), col.darkened(0.15))  # 뒷면(아래에서 보임)
	k.box(Vector3(-0.55, 0.8, -0.1), Vector3(0.6, 0.5, 0.5), WOOD_DARK)
	k.box(Vector3(0.1, 0.8, 0.15), Vector3(0.5, 0.4, 0.45), WOOD)
	k.box(Vector3(0.45, 0.8, -0.2), Vector3(0.4, 0.3, 0.4), WOOD_DARK)
	k.prism_n(Vector3(0.7, 0.8, 0.2), 6, 0.22, 0.17, 0.5, LOG_END)
	k.prism_n(Vector3(-0.1, 0.8, -0.35), 6, 0.2, 0.14, 0.45, CROP)
	return k.commit()

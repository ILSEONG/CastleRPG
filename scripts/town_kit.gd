extends RefCounted
## 로우폴리 레시피: 성 부품·건물·자연물·산 메시를 만든다(MeshKit). 오토로드 참조 없음.
## 성 부품 로컬 규약: 길이 방향 +X(가운데 기준), 두께 방향 Z(+Z = 성 바깥), 바닥 y=0. 계단만 예외(stairs 주석).
const Balance := preload("res://scripts/balance.gd")
const MeshKit := preload("res://scripts/mesh_kit.gd")

const STONE := Color(0.66, 0.63, 0.58)        # 밝은 톤이지만 해를 받는 윗면(선형 약 ×2.3)이 흰색으로 날아가지 않게 채널 ≤ 0.69
const STONE_DARK := Color(0.52, 0.50, 0.47)
const WOOD := Color(0.55, 0.38, 0.24)
const ROOF_BLUE := Color(0.27, 0.43, 0.68)
const ROOF_RED := Color(0.78, 0.33, 0.28)
const ROOF_ORANGE := Color(0.90, 0.56, 0.28)
const ROOF_PURPLE := Color(0.55, 0.42, 0.72)
const PLASTER := Color(0.95, 0.92, 0.84)
const LEAF := Color(0.40, 0.68, 0.38)
const LEAF_DARK := Color(0.28, 0.52, 0.32)
const ROCK := Color(0.62, 0.62, 0.64)
const SNOW := Color(0.96, 0.97, 0.99)
const CROP := Color(0.92, 0.80, 0.38)
const FLAG := Color(0.88, 0.30, 0.28)

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
## 단 i는 x 구간 [i, i+1]×run/steps, 높이 (i+1)×WALL_H/steps, 바닥부터 채운 박스.
static func stairs() -> ArrayMesh:
	var k = MeshKit.new()
	var n := Balance.STAIR_STEPS
	var d := Balance.STAIR_RUN / n
	for i in n:
		k.box(Vector3(d * (i + 0.5), 0, 0), Vector3(d, Balance.WALL_H * (i + 1) / n, Balance.STAIR_W), STONE_DARK)
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

extends RefCounted
## 로우폴리 레시피: 성 부품·건물·자연물·산 메시를 만든다(MeshKit). 오토로드 참조 없음.
## 성 부품 로컬 규약: 길이 방향 +X(가운데 기준), 두께 방향 Z(+Z = 성 바깥), 바닥 y=0. 계단만 예외(stairs 주석).
const Balance := preload("res://scripts/balance.gd")
const MeshKit := preload("res://scripts/mesh_kit.gd")
const Formation := preload("res://scripts/formation.gd")

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
const GOLD := Color(0.69, 0.53, 0.12)        # 금광 금(ArenaKit.GOLD 0.85/0.62/0.16을 윗면 한도 0.69로 낮춤)
const ROOF_GOLD := Color(0.58, 0.42, 0.10)   # 성 모습 5단계 금 지붕(해 쪽 경사가 노랗게 날아가지 않게 GOLD보다 어둡게)
const COALS := Color(0.95, 0.42, 0.10)       # 대장간 숯불(ArenaKit.COALS와 같다, 일부러 밝게)
const IRON := Color(0.30, 0.30, 0.34)        # 모루·쇠테
const SOOT := Color(0.16, 0.14, 0.13)        # 갱도 입구 어둠
const SACK := Color(0.62, 0.54, 0.38)
const GUILD := Color(0.16, 0.50, 0.52)       # 길드 깃발(청록)
const SLATE := Color(0.32, 0.35, 0.44)       # 길드 회관 지붕

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
## look(성 모습 단계, GameData.castle_look): 1+ 기둥 끝 삼각기, 3+ 기둥이 높아지고 금 꼭지·바깥면 횃불, 4+ 성문 위 문장(방패).
static func gatehouse(look := 0) -> ArrayMesh:
	var k = MeshKit.new()
	var h := Balance.WALL_H
	var z1 := Balance.WALL_T / 2.0 + PILLAR_OUT
	k.box(Vector3(0, h - 0.6, 0), Vector3(Balance.GATE_W, 0.6, Balance.WALL_T), STONE)
	_merlons(k, Balance.GATE_W, h)
	var ph := h + 1.2 + (0.9 if look >= 3 else 0.0)
	var roof := 1.1 + (0.4 if look >= 3 else 0.0)
	for s in [-1.0, 1.0]:
		var x: float = s * (Balance.GATE_W / 2.0 + PILLAR_W / 2.0)
		var zc := (PILLAR_Z0 + z1) / 2.0
		k.box(Vector3(x, 0, zc), Vector3(PILLAR_W, ph, z1 - PILLAR_Z0), STONE)
		if look >= 3:
			k.box(Vector3(x, ph - 0.3, zc), Vector3(PILLAR_W + 0.14, 0.18, z1 - PILLAR_Z0 + 0.14), STONE_DARK)
		k.pyramid(Vector3(x, ph, zc), PILLAR_W + 0.3, roof, ROOF_BLUE)
		var tip := Vector3(x, ph + roof, zc)
		if look >= 3:
			_finial(k, tip, 0.16)
			tip.y += 0.3
		if look >= 1:
			_pennant(k, tip, s, 0.9 if look >= 3 else 0.7)
		if look >= 3:
			_sconce(k, Vector3(x, 2.0, z1))
	if look >= 4:
		_crest(k, Vector3(0, h - 1.15, Balance.WALL_T / 2.0 + 0.1), 1.0)
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
## look: 1+ 깃발이 커진다, 2+ 탑이 높아지고(+1.5 m) 금 꼭지, 3+ 기단 띠·윗단 돌림띠, 4+ 한 번 더 높아지고 지붕이 커진다, 5 금 지붕 띠.
static func corner_tower(look := 0) -> ArrayMesh:
	var k = MeshKit.new()
	var r := Balance.TOWER_SIZE / 2.0 + 0.2
	var h := Balance.WALL_H + 2.0 + (1.5 if look >= 2 else 0.0) + (1.0 if look >= 4 else 0.0)
	k.prism_n(Vector3.ZERO, 8, r, r, h, STONE, PI / 8.0)
	if look >= 3:
		k.prism_n(Vector3.ZERO, 8, r + 0.3, r + 0.12, 0.9, STONE_DARK, PI / 8.0)  # 기단
		k.prism_n(Vector3(0, h - 0.45, 0), 8, r + 0.12, r + 0.12, 0.45, STONE_DARK, PI / 8.0)  # 톱니 아래 돌림띠
	for i in 8:
		var a := TAU * i / 8.0
		var m := r * cos(PI / 8.0) - 0.2  # 면 가운데(변심 거리)에서 안쪽으로
		k.xform = Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * m, h, sin(a) * m))
		k.box(Vector3.ZERO, Vector3(0.4, MERLON_H, 0.6), STONE_DARK)
	k.xform = Transform3D.IDENTITY
	var roof_y := h + MERLON_H
	var roof_h := 2.5 + (0.8 if look >= 4 else 0.0)
	var roof_r := r + 0.3 + (0.15 if look >= 4 else 0.0)
	if look >= 5:
		k.prism_n(Vector3(0, roof_y, 0), 8, roof_r + 0.05, roof_r - 0.1, 0.3, ROOF_GOLD, PI / 8.0)
		roof_y += 0.3
		roof_r -= 0.1
	k.cone(Vector3(0, roof_y, 0), 8, roof_r, roof_h, ROOF_BLUE, PI / 8.0)
	var tip := Vector3(0, roof_y + roof_h, 0)
	if look >= 2:
		_finial(k, tip, 0.22)
		tip.y += 0.4
	var f := 1.0 if look < 1 else (1.4 if look < 4 else 1.7)
	k.box(tip, Vector3(0.1, 1.2 * f, 0.1), WOOD)
	k.box(tip + Vector3(0.35 * f + 0.05, 0.75 * f, 0), Vector3(0.7 * f, 0.4 * f, 0.05), FLAG)
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
## id의 "#" 뒤(같은 종류 사본 키, 예: "lumber#2")는 떼고 종류로 고른다.
## look = 성 모습 단계(GameData.castle_look — 성채만 쓴다).
static func building(id: String, look := 0) -> ArrayMesh:
	var k = MeshKit.new()
	match id.get_slice("#", 0):
		"keep": _keep(k, look)
		"barracks": _barracks(k)
		"tavern": _tavern(k)
		"lab": _lab(k)
		"houses": _houses(k)
		"lumber": _lumber(k)
		"quarry": _quarry(k)
		"farm": _farm(k)
		"archery": _archery(k)
		"stable": _stable(k)
		"warehouse": _warehouse(k)
		"goldmine": _goldmine(k)
		"forge": _forge(k)
		"guild_hall": _guild_hall(k)
		"watchtower": _watchtower(k)
		"dispatch": _dispatch(k)
		_: push_error("unknown building %s" % id)
	return k.commit()


## 성채: 석조 본체 + 톱니, 네 모서리 6각 탑(파란 원뿔), 가운데 8각 탑(파란 원뿔 + 깃발), 문·창.
## look(성 모습 단계): 1+ 본체에 걸린 깃발·모서리 탑 삼각기, 2+ 탑들이 높아지고 금 꼭지·금 고리, 3+ 돌 기단·앞 계단(전체가 기단 위로),
## 4+ 가운데 탑 발코니 한 층 더·첨탑이 더 높게, 5 금 첨탑·큰 깃발. 부지 ±3.7 안(테스트).
static func _keep(k, look := 0) -> void:
	var base := 0.0
	if look >= 3:
		base = 0.35
		k.box(Vector3.ZERO, Vector3(7.0, base, 7.0), STONE_DARK)
		k.box(Vector3(0, 0, 3.55), Vector3(2.4, base * 0.5, 0.3), STONE_DARK)  # 앞 계단 한 단
	var up := Transform3D(Basis.IDENTITY, Vector3(0, base, 0))
	k.xform = up
	k.box(Vector3.ZERO, Vector3(5.2, 3.6, 5.2), STONE)
	k.box(Vector3(0, 3.6, 0), Vector3(5.5, 0.3, 5.5), STONE_DARK)
	for i in 4:
		k.xform = up * Transform3D(Basis(Vector3.UP, i * PI / 2.0), Vector3.ZERO)
		for x in [-1.0, 0.0, 1.0]:
			k.box(Vector3(x, 3.9, 2.55), Vector3(0.5, 0.45, 0.35), STONE_DARK)
		if look >= 1:  # 본체 네 면에 걸린 깃발: 앞(+Z)은 문 양옆 둘, 나머지는 가운데 하나
			for x in ([-1.05, 1.05] if i == 0 else [0.0]):
				_banner(k, Vector3(x, 3.55, 2.6), 0.55 if i == 0 else 0.8, 1.7, look >= 4)
	k.xform = up
	var t_h := 5.0 + (1.0 if look >= 2 else 0.0) + (0.6 if look >= 4 else 0.0)
	for c in [Vector3(-2.5, 0, -2.5), Vector3(2.5, 0, -2.5), Vector3(2.5, 0, 2.5), Vector3(-2.5, 0, 2.5)]:
		k.prism_n(c, 6, 0.95, 0.95, t_h, STONE)
		if look >= 2:
			k.prism_n(c + Vector3(0, t_h - 0.3, 0), 6, 1.05, 1.05, 0.3, STONE_DARK)
		k.cone(c + Vector3(0, t_h, 0), 6, 1.15, 1.9, ROOF_BLUE)
		var tip: Vector3 = c + Vector3(0, t_h + 1.9, 0)
		if look >= 2:
			_finial(k, tip, 0.16)
			tip.y += 0.3
		if look >= 1:
			_pennant(k, tip, 1.0, 0.75)
	var c_h := 4.2 + (1.2 if look >= 2 else 0.0) + (1.0 if look >= 4 else 0.0)
	k.prism_n(Vector3(0, 3.9, 0), 8, 1.6, 1.6, c_h, STONE, PI / 8.0)
	var top := 3.9 + c_h
	if look >= 4:  # 가운데 탑 중간 발코니(돌림 바닥 + 톱니)
		var by := 3.9 + c_h * 0.55
		k.prism_n(Vector3(0, by, 0), 8, 1.95, 1.95, 0.25, STONE_DARK, PI / 8.0)
		for i in 8:
			var a := TAU * i / 8.0 + PI / 8.0
			k.xform = up * Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * 1.78, by + 0.25, sin(a) * 1.78))
			k.box(Vector3.ZERO, Vector3(0.45, 0.35, 0.3), STONE_DARK)
		k.xform = up
	k.prism_n(Vector3(0, top, 0), 8, 1.75, 1.75, 0.3, GOLD if look >= 2 else STONE_DARK, PI / 8.0)
	var spire := 3.0 + (1.3 if look >= 4 else 0.0)
	k.cone(Vector3(0, top + 0.3, 0), 8, 1.95, spire, ROOF_GOLD if look >= 5 else ROOF_BLUE, PI / 8.0)
	var tip := Vector3(0, top + 0.3 + spire, 0)
	if look >= 2:
		_finial(k, tip, 0.24)
		tip.y += 0.45
	var f := 1.0 + 0.25 * maxi(look - 1, 0)  # 깃발이 단계마다 커진다
	k.box(tip, Vector3(0.12, 1.5 * f, 0.12), WOOD)
	k.box(tip + Vector3(0.4 * f + 0.05, 0.9 * f, 0), Vector3(0.8 * f, 0.5 * f, 0.05), FLAG)
	k.box(Vector3(0, 0, 2.6), Vector3(1.4, 2.2, 0.2), WOOD)
	for x in [-1.6, 1.6]:
		k.box(Vector3(x, 1.8, 2.6), Vector3(0.4, 0.8, 0.1), WINDOW)
		k.box(Vector3(2.6, 1.8, x), Vector3(0.1, 0.8, 0.4), WINDOW)
	k.box(Vector3(0, 6.0, 1.5), Vector3(0.4, 0.8, 0.1), WINDOW)
	k.box(Vector3(1.5, 6.0, 0), Vector3(0.1, 0.8, 0.4), WINDOW)
	k.xform = Transform3D.IDENTITY


# --- 성 모습 장식(look) 부품: 로컬 +Z가 붙는 벽 바깥 ---

## 벽에 걸린 깃발: 윗변 가운데 top(벽면 위, +Z가 벽 바깥), 폭 w, 길이 l(제비꼬리 끝 제외). 금 마름모 문장, gold_edge면 금 테두리.
static func _banner(k, top: Vector3, w: float, l: float, gold_edge := false) -> void:
	var z := top.z
	k.box(Vector3(top.x, top.y - 0.06, z + 0.06), Vector3(w + 0.2, 0.1, 0.1), WOOD_DARK)  # 걸이 막대
	if gold_edge:
		k.box(Vector3(top.x, top.y - l - 0.04, z + 0.02), Vector3(w + 0.12, l, 0.04), GOLD)
	k.box(Vector3(top.x, top.y - l, z + 0.04), Vector3(w, l - 0.08, 0.06), FLAG)
	var y0 := top.y - l
	var f := z + 0.1
	k.face([Vector3(top.x - w / 2.0, y0 + 0.001, f), Vector3(top.x + w / 2.0, y0 + 0.001, f), Vector3(top.x, y0 - w * 0.5, f)], Vector3.BACK, FLAG.darkened(0.12))
	var d := w * 0.3
	var cy := top.y - l * 0.42
	k.face([Vector3(top.x, cy + d, f + 0.01), Vector3(top.x + d * 0.8, cy, f + 0.01), Vector3(top.x, cy - d, f + 0.01), Vector3(top.x - d * 0.8, cy, f + 0.01)], Vector3.BACK, GOLD)


## 꼭대기 삼각기: 깃대 아래 끝 base, 깃발이 dir(±1) X쪽으로. 크기 s.
static func _pennant(k, base: Vector3, dir: float, s: float) -> void:
	k.box(base, Vector3(0.07, 1.1 * s, 0.07), WOOD)
	var y := base.y + 1.1 * s
	var a := Vector3(base.x, y, base.z)
	var b := Vector3(base.x, y - 0.42 * s, base.z)
	var c := Vector3(base.x + dir * 0.8 * s, y - 0.21 * s, base.z)
	k.face([a, b, c], Vector3.BACK, FLAG)
	k.face([a, b, c], Vector3.FORWARD, FLAG.darkened(0.12))


## 지붕 꼭대기 금 장식(위아래 4각 뿔 = 마름모 구슬). 아래 끝 base, 반지름 r.
static func _finial(k, base: Vector3, r: float) -> void:
	k.prism_n(base, 4, r * 0.4, r, r * 0.8, GOLD)
	k.cone(base + Vector3(0, r * 0.8, 0), 4, r, r * 1.2, GOLD)


## 벽걸이 횃불: 벽면 위 점 at(+Z 바깥), 받침 + 쇠 그릇 + 숯불.
static func _sconce(k, at: Vector3) -> void:
	k.box(at + Vector3(0, -0.15, 0.12), Vector3(0.14, 0.4, 0.24), WOOD_DARK)
	k.prism_n(at + Vector3(0, 0.2, 0.3), 6, 0.12, 0.22, 0.22, IRON)
	k.cone(at + Vector3(0, 0.42, 0.3), 6, 0.18, 0.4, COALS)


## 성문 위 문장: 금 테두리 방패(빨강 + 금 띠). 아래 가운데 base(벽면 위, +Z 바깥), 폭 w.
static func _crest(k, base: Vector3, w: float) -> void:
	var z := base.z
	var h := w * 0.75
	var tip := w * 0.45
	for layer in [[w + 0.16, GOLD, 0.05], [w, FLAG, 0.1]]:
		var hw: float = layer[0] / 2.0
		var zz: float = z + layer[2]
		var e: float = (layer[0] - w) / 2.0
		k.face([Vector3(-hw, base.y + tip - e, zz), Vector3(hw, base.y + tip - e, zz), Vector3(hw, base.y + tip + h + e, zz), Vector3(-hw, base.y + tip + h + e, zz)], Vector3.BACK, layer[1])
		k.face([Vector3(-hw, base.y + tip - e, zz), Vector3(hw, base.y + tip - e, zz), Vector3(0, base.y - e, zz)], Vector3.BACK, layer[1])
	k.box(Vector3(0, base.y + tip, z + 0.12), Vector3(0.18, h * 0.95, 0.03), GOLD)
	k.box(Vector3(0, base.y + tip + h * 0.5, z + 0.12), Vector3(w * 0.9, 0.16, 0.03), GOLD)


## 성벽 장식(성 모습 단계 look ≥ 2, 성 하나에 메시 하나): 성벽 바깥면·안쪽면에 걸린 깃발(모서리 탑·문루 기둥·계단을 비켜 고르게),
## 3+ 바깥 깃발 위 성벽 바깥 가장자리에 삼각기(궁병이 서는 중심선에서 0.8 m 밖), 4+ 바깥면 톱니 아래 돌림띠.
## 성 로컬 좌표(성 중심 원점, castle.gd와 같은 놓임). 장식이 없으면 null.
static func castle_dressing(half: float, offs: Array, look: int) -> ArrayMesh:
	if look < 2:
		return null
	var k = MeshKit.new()
	var c := half + Balance.WALL_T / 2.0
	var tower := Balance.TOWER_SIZE / 2.0 + 1.2
	var spacing := 7.0 if look < 4 else 5.5
	var w := 1.3 if look < 4 else 1.5
	var l := 1.8 if look < 4 else 2.1
	for side in 4:
		var dir: Vector3 = Formation.SIDE_DIR[side]
		var out := Basis(Vector3.UP, atan2(dir.x, dir.z))  # 로컬 +Z가 성 바깥
		var inn := Basis(Vector3.UP, atan2(-dir.x, -dir.z))  # 로컬 +Z가 성 안
		# 바깥면: 모서리 탑 ~ 문루 기둥 바깥 끝 사이 / 안쪽면: 계단 아랫단 너머 ~ 모서리 탑
		var outer := []
		var inner := []
		var pill := Balance.GATE_W / 2.0 + PILLAR_W + 0.5
		var stair := Balance.GATE_W / 2.0 + Balance.STAIR_GAP + Balance.STAIR_RUN + 0.8
		var prev_o := -c + tower
		var prev_i := -c + tower
		for at in offs:
			outer.append([prev_o, at - pill])
			inner.append([prev_i, at - stair])
			prev_o = at + pill
			prev_i = at + stair
		outer.append([prev_o, c - tower])
		inner.append([prev_i, c - tower])
		for pair in [[outer, out, Balance.WALL_T / 2.0], [inner, inn, Balance.WALL_T / 2.0]]:
			for seg in pair[0]:
				var a: float = seg[0]
				var b: float = seg[1]
				var n := floori((b - a) / spacing)
				if b - a < w + 0.6:
					continue
				n = maxi(n, 1)
				for i in n:
					var at: float = a + (b - a) * (i + 0.5) / n
					k.xform = Transform3D(pair[1], Formation.gate_position(half, side, at))
					_banner(k, Vector3(0, Balance.WALL_H - 0.15, pair[2]), w, l, look >= 4)
					if look >= 3 and pair[1] == out:
						_pennant(k, Vector3(0, Balance.WALL_H, Balance.WALL_T / 2.0 - MERLON_T / 2.0), 1.0, 0.9 if look < 4 else 1.05)
		if look >= 4:  # 바깥면 돌림띠(톱니 바로 아래, 문루 사이도 이어서)
			k.xform = Transform3D(out, Formation.gate_position(half, side))
			k.box(Vector3(0, Balance.WALL_H - 0.38, Balance.WALL_T / 2.0 + 0.05), Vector3(2.0 * c, 0.22, 0.12), STONE_DARK)
	k.xform = Transform3D.IDENTITY
	return k.commit()


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


## 창고: 돌 기단 + 목조 몸체(돌 모서리 기둥) + 파란 박공지붕(용마루 Z, 박공이 앞을 봄), 큰 쌍여닫이 문(띠·빗장),
## 다락 문 + 도르래 들보에 매달린 자루, 앞마당 상자 더미·자루·통.
static func _warehouse(k) -> void:
	var c := Vector3(-0.4, 0, -0.5)
	k.box(c, Vector3(4.2, 0.3, 3.6), STONE_DARK)
	_house(k, c + Vector3(0, 0.3, 0), Vector3(3.4, 2.5, 4.0), 1.6, WOOD, ROOF_BLUE, PI / 2.0)
	for p in [Vector3(-1.85, 0, -1.55), Vector3(1.85, 0, -1.55), Vector3(-1.85, 0, 1.55), Vector3(1.85, 0, 1.55)]:
		k.box(c + p + Vector3(0, 0.3, 0), Vector3(0.36, 2.5, 0.36), STONE)
	var fz := c.z + 1.7  # 앞벽
	k.box(Vector3(c.x, 0.3, fz), Vector3(2.5, 2.25, 0.1), STONE_DARK)  # 문틀
	for s in [-1.0, 1.0]:
		var x: float = c.x + s * 0.55
		k.box(Vector3(x, 0.3, fz + 0.04), Vector3(1.0, 2.0, 0.12), WOOD_DARK)
		for y in [0.55, 1.85]:
			k.box(Vector3(x, y, fz + 0.08), Vector3(1.0, 0.14, 0.1), WOOD)
		k.xform = Transform3D(Basis(Vector3.BACK, s * 0.88), Vector3(x, 1.27, fz + 0.1))  # 빗댄 사선 띠
		k.box(Vector3(0, -0.75, 0), Vector3(0.13, 1.5, 0.06), WOOD)
		k.xform = Transform3D.IDENTITY
	k.box(Vector3(c.x, 1.2, fz + 0.14), Vector3(0.9, 0.12, 0.08), IRON)  # 빗장
	var gz := fz + 0.26  # 박공 삼각형 면
	k.box(Vector3(c.x, 3.05, gz), Vector3(0.7, 0.75, 0.08), WINDOW)  # 다락 문
	k.box(Vector3(c.x, 4.0, gz - 0.3), Vector3(0.16, 0.16, 1.0), WOOD_DARK)  # 도르래 들보
	k.box(Vector3(c.x, 2.95, gz + 0.55), Vector3(0.04, 1.05, 0.04), WOOD_DARK)
	k.prism_n(Vector3(c.x, 2.45, gz + 0.55), 6, 0.2, 0.26, 0.5, SACK)
	# 앞마당 오른쪽: 상자 더미
	for p in [Vector3(1.05, 0, 1.75), Vector3(1.85, 0, 1.75), Vector3(1.45, 0.75, 1.75), Vector3(2.15, 0, 0.75), Vector3(2.2, 0, -0.15)]:
		_crate(k, p, 0.72)
	_crate(k, Vector3(2.2, 0.72, 0.3), 0.55)
	# 왼쪽: 통 둘 + 자루 더미
	for p in [Vector3(-2.15, 0, 1.6), Vector3(-1.45, 0, 2.15)]:
		_barrel(k, p)
	for p in [Vector3(-2.2, 0, 2.35), Vector3(0.45, 0, 2.3), Vector3(0.0, 0, 2.4)]:
		k.prism_n(p, 6, 0.28, 0.2, 0.5, SACK)


## 금광: 바위 언덕(금맥 반짝이) + 돌로 짠 갱도 입구(나무 기둥·들보, 안은 어둠), 레일(침목) 위 광차(금덩이 수북),
## 옆에 금광석 무더기 + 곡괭이, 등불 기둥.
static func _goldmine(k) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var m := Vector3(-0.2, 0, -0.85)
	k.rock(m + Vector3(0, 0.6, 0), 1.8, ROCK, rng, 1.4, 0.0)
	k.rock(m + Vector3(-1.4, 0.3, 0.9), 0.95, ROCK, rng, 0.9, 0.0)
	k.rock(m + Vector3(1.5, 0.3, 0.45), 1.0, ROCK, rng, 0.9, 0.0)
	for p in [Vector3(-1.0, 2.1, 0.65), Vector3(0.9, 2.25, 0.75), Vector3(-0.2, 2.95, 0.25), Vector3(1.75, 0.9, 1.0), Vector3(0.6, 2.7, -0.55), Vector3(-1.45, 0.75, 1.55)]:
		k.rock(m + p, 0.3, GOLD, rng, 0.9)
	var ex := m.x
	k.box(Vector3(ex, 0, 0.75), Vector3(2.0, 2.0, 1.3), STONE_DARK)  # 갱도 입구 덩어리(앞면 z 1.4)
	k.box(Vector3(ex, 0, 1.4), Vector3(1.3, 1.75, 0.06), SOOT)
	for s in [-1.0, 1.0]:
		k.box(Vector3(ex + s * 0.75, 0, 1.5), Vector3(0.24, 1.9, 0.24), WOOD)
	k.box(Vector3(ex, 1.9, 1.5), Vector3(2.0, 0.3, 0.32), WOOD)
	k.box(Vector3(ex, 2.05, 0.9), Vector3(2.3, 0.14, 1.65), WOOD_DARK)  # 차양 판자(입구 덩어리 윗면을 덮는다)
	# 레일: 침목 + 쇠 레일 둘(입구 → 앞)
	for i in 4:
		k.box(Vector3(ex, 0, 1.6 + i * 0.32), Vector3(0.95, 0.07, 0.16), WOOD_DARK)
	for s in [-1.0, 1.0]:
		k.box(Vector3(ex + s * 0.3, 0.07, 2.05), Vector3(0.06, 0.07, 1.3), METAL)
	# 광차: 쇠테 두른 나무 상자 + 바퀴 4 + 금덩이
	var cz := 2.15
	for s in [-1.0, 1.0]:
		for dz in [-0.28, 0.28]:
			k.xform = Transform3D(Basis(Vector3.BACK, -PI / 2.0), Vector3(ex + s * 0.3 - s * 0.05, 0.27, cz + dz))
			k.prism_n(Vector3.ZERO, 8, 0.13, 0.13, 0.1, IRON, PI / 8.0)
	k.xform = Transform3D.IDENTITY
	k.prism_n(Vector3(ex, 0.25, cz), 4, 0.5, 0.62, 0.5, WOOD_DARK, PI / 4.0)
	k.prism_n(Vector3(ex, 0.68, cz), 4, 0.6, 0.63, 0.09, IRON, PI / 4.0)
	for p in [Vector3(-0.15, 0.7, -0.1), Vector3(0.15, 0.72, 0.12), Vector3(0.0, 0.85, 0.0), Vector3(-0.12, 0.7, 0.2), Vector3(0.14, 0.7, -0.18)]:
		k.rock(Vector3(ex, 0, cz) + p, 0.18, GOLD, rng, 0.9)
	# 금광석 무더기(오른쪽 앞) + 곡괭이
	var h := Vector3(1.55, 0, 1.75)
	k.rock(h + Vector3(0, 0.15, 0), 0.6, ROCK, rng, 0.7, 0.0)
	for p in [Vector3(-0.15, 0.45, 0.1), Vector3(0.2, 0.35, 0.2), Vector3(0.0, 0.5, -0.15)]:
		k.rock(h + p, 0.2, GOLD, rng, 0.9)
	var lean := Basis(Vector3.BACK, 0.45)
	k.xform = Transform3D(lean, h + Vector3(0.75, 0.03, 0.35))
	k.box(Vector3.ZERO, Vector3(0.07, 1.0, 0.07), WOOD)
	k.box(Vector3(0, 0.92, 0), Vector3(0.7, 0.09, 0.09), METAL)
	k.xform = Transform3D.IDENTITY
	# 등불 기둥(입구 왼쪽)
	k.box(Vector3(ex - 1.35, 0, 1.75), Vector3(0.12, 1.7, 0.12), WOOD_DARK)
	k.box(Vector3(ex - 1.35, 1.45, 1.75), Vector3(0.24, 0.3, 0.24), COALS)


## 대장간: 돌 바닥 위 기둥 넷 + 빨간 박공지붕(옆이 트인 작업장), 뒤쪽 돌 화덕(벌건 숯 + 불 아가리) + 지붕을 뚫는 굴뚝,
## 앞마당 그루터기 위 모루, 담금질 통(물), 오른쪽 무기 걸이(칼 셋 + 방패).
static func _forge(k) -> void:
	var c := Vector3(-0.55, 0, -0.75)
	k.box(c, Vector3(3.8, 0.15, 3.0), STONE_DARK)
	for p in [Vector3(-1.6, 0, -1.25), Vector3(1.6, 0, -1.25), Vector3(-1.6, 0, 1.25), Vector3(1.6, 0, 1.25)]:
		k.box(c + p, Vector3(0.26, 2.5, 0.26), WOOD)
	k.box(c + Vector3(0, 0.15, -1.3), Vector3(3.3, 1.1, 0.25), STONE)  # 뒷벽(낮은 돌담)
	k.gable(c + Vector3(0, 2.5, 0), Vector3(3.5, 0, 2.7), 1.15, ROOF_RED, 0.3)
	var f := c + Vector3(-0.8, 0, -0.55)  # 화덕
	k.box(f, Vector3(1.5, 1.0, 1.3), STONE)
	k.box(f + Vector3(0, 1.0, 0), Vector3(1.6, 0.12, 1.4), STONE_DARK)
	k.box(f + Vector3(0, 1.12, 0.1), Vector3(1.0, 0.1, 0.8), COALS)
	k.box(f + Vector3(0, 0.25, 0.62), Vector3(0.7, 0.45, 0.1), COALS)  # 불 아가리
	k.box(f + Vector3(0, 1.75, -0.35), Vector3(0.9, 0.7, 0.6), STONE_DARK)  # 연기 후드
	k.box(f + Vector3(0, 2.45, -0.35), Vector3(0.6, 2.6, 0.6), STONE_DARK)  # 굴뚝(지붕 위로)
	k.box(f + Vector3(0, 5.05, -0.35), Vector3(0.75, 0.2, 0.75), STONE)
	# 모루: 그루터기 + 몸통 + 뿔(앞 +X)
	var a := Vector3(0.75, 0, 1.25)
	k.prism_n(a, 6, 0.36, 0.33, 0.55, WOOD)
	k.box(a + Vector3(0, 0.55, 0), Vector3(0.32, 0.22, 0.3), IRON)
	k.box(a + Vector3(0, 0.77, 0), Vector3(0.62, 0.2, 0.32), IRON)
	k.xform = Transform3D(Basis(Vector3.BACK, -PI / 2.0), a + Vector3(0.31, 0.87, 0))
	k.cone(Vector3.ZERO, 4, 0.11, 0.3, IRON, PI / 4.0)
	k.xform = Transform3D.IDENTITY
	k.box(a + Vector3(-0.1, 0.97, 0.02), Vector3(0.08, 0.06, 0.4), WOOD_DARK)  # 망치 자루
	k.box(a + Vector3(-0.1, 0.97, 0.22), Vector3(0.16, 0.14, 0.12), METAL)
	# 담금질 통
	var q := Vector3(-0.4, 0, 1.75)
	k.prism_n(q, 6, 0.4, 0.42, 0.6, WOOD_DARK)
	k.prism_n(q + Vector3(0, 0.6, 0), 6, 0.33, 0.33, 0.01, ROOF_BLUE)
	# 무기 걸이(오른쪽, +X를 봄): 기둥 둘 + 가로대 둘, 칼 셋(날·자루·코등이), 둥근 방패
	var r := Vector3(2.15, 0, -0.35)
	for dz in [-1.0, 1.0]:
		k.box(r + Vector3(0, 0, dz), Vector3(0.14, 1.45, 0.14), WOOD)
	for y in [0.35, 1.25]:
		k.box(r + Vector3(0, y, 0), Vector3(0.12, 0.1, 2.15), WOOD)
	for dz in [-0.6, -0.15, 0.3]:
		k.box(r + Vector3(0.12, 0.2, dz), Vector3(0.04, 1.1, 0.12), METAL)
		k.box(r + Vector3(0.12, 1.3, dz), Vector3(0.05, 0.08, 0.32), IRON)
		k.box(r + Vector3(0.12, 1.38, dz), Vector3(0.06, 0.28, 0.06), WOOD_DARK)
	_disc(k, r + Vector3(0.22, 0.85, 0.78), PI / 2.0, 0.34, ROOF_BLUE)
	_disc(k, r + Vector3(0.27, 0.85, 0.78), PI / 2.0, 0.1, METAL)


## 길드 회관: 넓은 돌 기단 + 석조 본관(앞 기둥 넷) + 높은 회색 박공지붕 + 용마루 위 작은 종탑(청록 지붕),
## 앞쪽 박공 현관(큰 문, 문 위 금테 청록 문장 방패), 계단, 앞마당 깃대 둘(청록 깃발 + 금 띠).
static func _guild_hall(k) -> void:
	var c := Vector3(0, 0, -0.85)
	k.box(c, Vector3(5.1, 0.4, 3.4), STONE_DARK)
	_house(k, c + Vector3(0, 0.4, 0), Vector3(4.6, 2.6, 2.9), 2.0, STONE, SLATE)
	for x in [-1.75, -0.95, 0.95, 1.75]:  # 앞벽 기둥
		k.box(Vector3(x, 0.4, c.z + 1.5), Vector3(0.28, 2.6, 0.2), PLASTER)
	for x in [-1.35, 1.35]:
		k.box(Vector3(x, 1.4, c.z + 1.47), Vector3(0.4, 0.9, 0.1), WINDOW)
	for z in [-0.5, 0.5]:
		k.box(Vector3(2.32, 1.4, c.z + z), Vector3(0.1, 0.9, 0.4), WINDOW)
	# 종탑
	var t := c + Vector3(-1.0, 4.4, 0)
	k.box(t + Vector3(0, -0.6, 0), Vector3(0.9, 1.5, 0.9), PLASTER)
	k.box(t + Vector3(0, 0.1, 0.46), Vector3(0.4, 0.55, 0.04), WINDOW)
	k.box(t + Vector3(0.46, 0.1, 0), Vector3(0.04, 0.55, 0.4), WINDOW)
	k.pyramid(t + Vector3(0, 0.9, 0), 1.25, 1.1, GUILD)
	# 현관: 앞으로 튀어나온 작은 박공(용마루 Z)
	var p := Vector3(0, 0.4, c.z + 1.65)
	_house(k, p, Vector3(1.2, 2.9, 1.5), 1.0, PLASTER, SLATE, PI / 2.0)
	k.box(p + Vector3(0, 0, 0.6), Vector3(0.95, 1.9, 0.12), WOOD_DARK)
	k.box(p + Vector3(0, 1.9, 0.6), Vector3(1.15, 0.15, 0.14), STONE_DARK)
	k.box(Vector3(0, 0, p.z + 0.95), Vector3(1.6, 0.25, 0.45), STONE_DARK)  # 계단
	# 문장: 금 테두리 + 청록 방패 + 금 띠
	var e := p + Vector3(0, 2.3, 0.62)
	k.box(e + Vector3(0, -0.05, 0), Vector3(0.7, 0.75, 0.06), GOLD)
	k.box(e, Vector3(0.56, 0.62, 0.1), GUILD)
	k.box(e + Vector3(0, 0.22, 0.02), Vector3(0.1, 0.36, 0.1), GOLD)
	k.box(e + Vector3(0, 0.32, 0.02), Vector3(0.36, 0.1, 0.1), GOLD)
	# 깃대 둘: 기둥 + 가로대 + 늘어진 깃발(아래 금 띠) + 꼭대기 금 구슬
	for x in [-1.9, 1.9]:
		var b := Vector3(x, 0, 1.95)
		k.box(b, Vector3(0.14, 3.9, 0.14), WOOD_DARK)
		k.box(b + Vector3(0, 3.55, 0), Vector3(0.85, 0.08, 0.08), WOOD_DARK)
		k.box(b + Vector3(0, 2.05, 0.06), Vector3(0.72, 1.5, 0.05), GUILD)
		k.box(b + Vector3(0, 2.15, 0.08), Vector3(0.72, 0.12, 0.05), GOLD)
		k.box(b + Vector3(0, 2.9, 0.09), Vector3(0.22, 0.22, 0.05), GOLD)
		k.prism_n(b + Vector3(0, 3.9, 0), 6, 0.12, 0.12, 0.18, GOLD)
	# 벽에 걸린 청록 휘장 둘(현관 양옆)
	for x in [-0.95, 0.95]:
		k.box(Vector3(x, 1.2, c.z + 1.62), Vector3(0.45, 1.6, 0.05), GUILD)


## 망루: 위로 좁아지는 4각 돌 기단(문·화살 구멍) + 나무 다리 넷(X자 버팀) + 넓은 사격 발판(난간, 앞 사다리 자리 비움)
## + 모서리 기둥 넷 위 빨간 4각 지붕 + 깃발, 앞(+Z) 사다리가 땅에서 발판까지.
const WATCH_DECK := 6.3  # 망루 발판 윗면 높이(전투 화살 출발점 참고)


static func _watchtower(k) -> void:
	k.prism_n(Vector3.ZERO, 4, 1.95, 1.6, 3.0, STONE, PI / 4.0)
	k.prism_n(Vector3(0, 3.0, 0), 4, 1.7, 1.7, 0.25, STONE_DARK, PI / 4.0)
	k.box(Vector3(0.55, 0, 1.33), Vector3(0.7, 1.4, 0.12), WOOD_DARK)  # 문(사다리 옆)
	k.box(Vector3(1.24, 1.8, 0), Vector3(0.12, 0.6, 0.18), WINDOW)
	k.box(Vector3(-0.5, 1.8, 1.24), Vector3(0.18, 0.6, 0.12), WINDOW)
	var y0 := 3.25
	var y1 := WATCH_DECK - 0.25
	for p in [Vector3(-0.95, 0, -0.95), Vector3(0.95, 0, -0.95), Vector3(-0.95, 0, 0.95), Vector3(0.95, 0, 0.95)]:
		k.box(p + Vector3(0, y0, 0), Vector3(0.28, y1 - y0, 0.28), WOOD)
	var span := sqrt(1.9 * 1.9 + (y1 - y0) * (y1 - y0))
	var tilt := atan2(1.9, y1 - y0)
	for yaw in [0.0, PI / 2.0, PI, 3.0 * PI / 2.0]:  # 네 면 X자 버팀
		for s in [-1.0, 1.0]:
			k.xform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, s * tilt), Basis(Vector3.UP, yaw) * Vector3(0, (y0 + y1) / 2.0, 0.97) + Vector3(0, 0, 0))
			k.box(Vector3(0, -span / 2.0, 0), Vector3(0.12, span, 0.08), WOOD_DARK)
	k.xform = Transform3D.IDENTITY
	k.box(Vector3(0, y1, 0), Vector3(3.3, 0.25, 3.3), WOOD_DARK)  # 발판
	k.box(Vector3(0, y1 - 0.18, 0), Vector3(2.4, 0.18, 2.4), WOOD)
	var d := WATCH_DECK
	for yaw in [0.0, PI / 2.0, PI, 3.0 * PI / 2.0]:  # 난간: 앞(+Z)은 사다리 자리를 비운다
		k.xform = Transform3D(Basis(Vector3.UP, yaw), Vector3(0, d, 0))
		if yaw == 0.0:
			k.box(Vector3(-1.05, 0, 1.58), Vector3(1.1, 0.75, 0.12), WOOD)
			k.box(Vector3(0.8, 0, 1.58), Vector3(1.6, 0.75, 0.12), WOOD)
		else:
			k.box(Vector3(0, 0, 1.58), Vector3(3.3, 0.75, 0.12), WOOD)
		k.box(Vector3(0, 0.75, 1.58), Vector3(3.36, 0.1, 0.2), WOOD_DARK)
	k.xform = Transform3D.IDENTITY
	for p in [Vector3(-1.5, 0, -1.5), Vector3(1.5, 0, -1.5), Vector3(-1.5, 0, 1.5), Vector3(1.5, 0, 1.5)]:
		k.box(p + Vector3(0, d, 0), Vector3(0.18, 1.85, 0.18), WOOD)
	k.pyramid(Vector3(0, d + 1.85, 0), 3.8, 1.5, ROOF_RED)
	k.box(Vector3(0, d + 3.3, 0), Vector3(0.1, 1.2, 0.1), WOOD)
	k.box(Vector3(0.4, d + 4.05, 0), Vector3(0.7, 0.4, 0.05), FLAG)
	# 사다리: 앞(+Z) 바깥, 땅 → 발판 위
	var lz := 1.82
	for x in [-0.22 - 0.25, 0.22 - 0.25]:
		k.box(Vector3(x, 0, lz), Vector3(0.08, d + 0.8, 0.08), WOOD)
	var n := int(d / 0.4)
	for i in n:
		k.box(Vector3(-0.25, 0.3 + i * 0.4, lz), Vector3(0.48, 0.06, 0.06), WOOD_DARK)


## 나무 상자(가운데 진한 띠). 바닥 중심 p, 한 변 s.
## 파견소: 돌 기단 위 통나무 오두막(초록 박공지붕, 앞 문·창), 앞마당 왼쪽 큰 의뢰 게시판(종이 여러 장 — 희귀도 색 핀),
## 오른쪽 갈림길 이정표(화살 판 셋), 앞 상자·자루, 지붕 끝 작은 깃발.
static func _dispatch(k) -> void:
	var c := Vector3(0.35, 0, -0.75)
	k.box(c, Vector3(3.4, 0.2, 2.6), STONE_DARK)
	k.box(c + Vector3(0, 0.2, 0), Vector3(3.0, 1.9, 2.2), WOOD)
	for dx in [-1.5, 1.5]:  # 통나무 모서리
		for dz in [-1.1, 1.1]:
			k.box(c + Vector3(dx, 0.2, dz), Vector3(0.26, 1.9, 0.26), LOG_END)
	k.box(c + Vector3(0, 0.2, 1.11), Vector3(0.75, 1.25, 0.06), WOOD_DARK)  # 문
	for dx in [-0.95, 0.95]:
		k.box(c + Vector3(dx, 1.0, 1.11), Vector3(0.5, 0.45, 0.06), WINDOW)
	k.gable(c + Vector3(0, 2.1, 0), Vector3(3.5, 0, 2.7), 1.2, ROOF_GREEN, 0.3)
	k.box(c + Vector3(1.55, 3.3, 0), Vector3(0.07, 1.0, 0.07), WOOD_DARK)  # 깃대
	k.box(c + Vector3(1.85, 3.95, 0), Vector3(0.55, 0.35, 0.04), FLAG)
	# 의뢰 게시판(앞 왼쪽, +Z를 봄): 다리 둘 + 판 + 작은 지붕 + 종이(희귀도 핀 N 회색·R 파랑·SR 보라·SSR 금)
	var b := Vector3(-1.45, 0, 1.45)
	for dx in [-0.75, 0.75]:
		k.box(b + Vector3(dx, 0, 0), Vector3(0.14, 1.85, 0.14), WOOD_DARK)
	k.box(b + Vector3(0, 0.75, 0), Vector3(1.7, 1.0, 0.1), WOOD)
	k.gable(b + Vector3(0, 1.85, 0), Vector3(1.9, 0, 0.45), 0.3, ROOF_GREEN, 0.06)
	var pins := [METAL, ROOF_BLUE, ROOF_PURPLE, GOLD]
	for i in 4:
		var px := -0.55 + i * 0.37
		var py := 0.9 + (0.25 if i % 2 == 0 else 0.0)
		k.box(b + Vector3(px, py, 0.06), Vector3(0.3, 0.36, 0.02), PLASTER)
		k.box(b + Vector3(px, py + 0.3, 0.08), Vector3(0.07, 0.07, 0.03), pins[i])
	# 이정표(앞 오른쪽): 기둥 + 화살 판 셋(방향 다르게)
	var g := Vector3(1.7, 0, 1.55)
	k.box(g, Vector3(0.14, 2.0, 0.14), WOOD_DARK)
	for i in 3:
		k.xform = Transform3D(Basis(Vector3.UP, [0.4, -0.9, 2.2][i]), g + Vector3(0, 1.3 + i * 0.25, 0))
		k.box(Vector3(0.35, 0, 0), Vector3(0.7, 0.16, 0.05), LOG_END)
		k.xform = Transform3D.IDENTITY
	_crate(k, Vector3(-0.05, 0, 1.5), 0.5)
	k.box(Vector3(0.55, 0, 1.75), Vector3(0.45, 0.4, 0.35), SACK)


static func _crate(k, p: Vector3, s: float) -> void:
	k.box(p, Vector3(s, s, s), WOOD)
	k.box(p + Vector3(0, s * 0.42, 0), Vector3(s + 0.03, s * 0.16, s + 0.03), WOOD_DARK)


## 6각 통(위 테 진하게). 바닥 중심 p.
static func _barrel(k, p: Vector3) -> void:
	k.prism_n(p, 6, 0.38, 0.38, 0.75, WOOD)
	k.prism_n(p + Vector3(0, 0.5, 0), 6, 0.41, 0.41, 0.1, WOOD_DARK)


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

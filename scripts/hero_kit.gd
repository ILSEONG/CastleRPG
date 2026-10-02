extends RefCounted
## 영웅 생김새 코드 부품(개정 23, Art.HERO_LOOKS parts·swap): 머리 장식·등·어깨·무기를 MeshKit 로우폴리(정점 색, 공유 재질)로 만든다.
## 뼈 공간(KayKit 다섯 모델 공통, GLB 휴식 자세에서 잼): 머리 = 목 원점, +Y 위, +Z 얼굴 앞(머리 옆 |x| ≈ 0.54, 눈 y 0.3~0.43·z ≈ 0.45,
## 얼굴 앞 z ≈ 0.52, 정수리 0.95~1.07, 기사 투구 꼭대기 1.23, 마법사 모자 끝 (0, 1.47, −0.34), 두건 꼭대기 1.01).
## 가슴 = 등 위 원점(+Y 위, +Z 앞, 앞가슴 z ≈ 0.37, 망토 뒷면 z ≈ −0.39, 어깨 x ≈ ±0.4, 목 y ≈ 0.3).
## 손 슬롯 = 손잡이 원점, +Y 무기 끝(지팡이 머리 y ≈ 1.25, 완드 끝 0.7). 메시는 id마다 한 번 만들어 공유한다. 오토로드 참조 없음.

const Art := preload("res://scripts/art.gd")
const MeshKit := preload("res://scripts/mesh_kit.gd")

const GOLD := Color("F0C040")
const GOLD_DARK := Color("B8862A")
const IRON := Color("5E646C")
const IRON_DARK := Color("3A3F46")
const STEEL := Color("C8D0D8")
const BONE := Color("E8DFC8")
const WOOD := Color("7A5232")
const WOOD_DARK := Color("4A3220")
const WHITE := Color("F6F4EE")
const FIRE := Color("FF6A10")
const FIRE_CORE := Color("FFD23A")
const ICE := Color("C8F2FF")
const ICE_DEEP := Color("62B8EE")

## 부품 id 전체(Art.HERO_LOOKS가 쓰는 것). has_part로 ArenaKit 부품과 가른다.
const PARTS := ["arteon_wings", "arteon_pauldrons", "baldur_spikes", "baldur_pauldrons", "bron_crest", "torvin_mitre", "torvin_mace",
	"felix_plume", "felix_spear", "hans_kettle", "ignis_flame", "ignis_fire", "seraphine_crown", "seraphine_ice", "lumina_halo",
	"lumina_wings", "echo_scarf", "echo_spark", "nina_wreath", "nina_bloom", "sylvana_feather", "sylvana_quiver", "nev_bolts",
	"mira_mask", "mira_vials", "ella_flower", "kyle_mask", "rian_band", "rian_saber", "jack_bandana", "grom_horns", "harald_skull",
	"harald_sword", "gork_mohawk", "gork_axes", "dorik_beanie"]

static var _meshes := {}


static func has_part(id: String) -> bool:
	return PARTS.has(id)


## 부품 노드(이름 = id). 메시는 id마다 공유, 재질은 로우폴리 정점 색 공유 재질.
static func part(id: String) -> Node3D:
	if not _meshes.has(id):
		var k = MeshKit.new()
		_build(id, k)
		_meshes[id] = k.commit()
	var mi := MeshInstance3D.new()
	mi.name = id
	mi.mesh = _meshes[id]
	mi.material_override = Art.lowpoly_vc_material()
	return mi


static func _build(id: String, k) -> void:
	match id:
		"arteon_wings": _arteon_wings(k)
		"arteon_pauldrons": _pauldrons(k, GOLD, WHITE, 0.0)
		"baldur_spikes": _baldur_spikes(k)
		"baldur_pauldrons": _pauldrons(k, IRON, IRON_DARK, 1.0)
		"bron_crest": _bron_crest(k)
		"torvin_mitre": _torvin_mitre(k)
		"torvin_mace": _torvin_mace(k)
		"felix_plume": _felix_plume(k)
		"felix_spear": _felix_spear(k)
		"hans_kettle": _hans_kettle(k)
		"ignis_flame": _flame(k, Vector3(-0.03, 1.36, -0.32), 0.42, 1.0)  # 끝 ≈ 1.8 — 피규어 그림 위(≈ 3.1 m)에 걸리지 않게
		"ignis_fire": _flame(k, Vector3(0, 1.05, 0), 0.6, 1.2)
		"seraphine_crown": _seraphine_crown(k)
		"seraphine_ice": _ice_crystal(k)
		"lumina_halo": _lumina_halo(k)
		"lumina_wings": _lumina_wings(k)
		"echo_scarf": _echo_scarf(k)
		"echo_spark": _flame(k, Vector3(0, 0.62, 0), 0.32, 0.6)
		"nina_wreath": _nina_wreath(k)
		"nina_bloom": _flower(k, Vector3(0, 1.22, 0), Vector3.UP, 0.32, Color("FF9EC4"), Color("FFE07A"))
		"sylvana_feather": _sylvana_feather(k)
		"sylvana_quiver": _sylvana_quiver(k)
		"nev_bolts": _nev_bolts(k)
		"mira_mask": _mask(k, Color("2A2230"), Color("9CE03A"))
		"mira_vials": _mira_vials(k)
		"ella_flower": _flower(k, Vector3(0.44, 0.62, 0.3), Vector3(0.8, 0.1, 0.6), 0.2, WHITE, Color("FFD23A"))
		"kyle_mask": _mask(k, Color("1C1A22"), Color("B070FF"))
		"rian_band": _rian_band(k)
		"rian_saber": _rian_saber(k)
		"jack_bandana": _jack_bandana(k)
		"grom_horns": _grom_horns(k)
		"harald_skull": _harald_skull(k)
		"harald_sword": _harald_sword(k)
		"gork_mohawk": _gork_mohawk(k)
		"gork_axes": _gork_axes(k)
		"dorik_beanie": _dorik_beanie(k)
		_: push_error("unknown hero part %s" % id)


# --- 도형 도우미 ---

## a → b 원뿔대 관(sides각, 반지름 r0 → r1, r1 = 0이면 원뿔). k.xform을 쓰고 되돌린다.
static func _tube(k, a: Vector3, b: Vector3, r0: float, r1: float, sides: int, color: Color) -> void:
	var y := (b - a).normalized()
	var x := y.cross(Vector3.BACK)
	if x.length() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	k.xform = Transform3D(Basis(x, y, x.cross(y)), a)
	k.prism_n(Vector3.ZERO, sides, r0, r1, (b - a).length(), color)
	k.xform = Transform3D.IDENTITY


## base → tip 납작한 마름모(잎·깃털·불꽃 혀·날개깃): 폭 w는 축 × thick 방향, 두께 t는 thick 쪽. 가장 넓은 곳 = frac 지점.
static func _leaf(k, base: Vector3, tip: Vector3, w: float, t: float, thick: Vector3, color: Color, frac := 0.4) -> void:
	var axis := tip - base
	var side := axis.cross(thick).normalized() * w * 0.5
	var th := side.cross(axis).normalized() * t * 0.5
	var m := base + axis * frac
	var ring := [m + side, m + th, m - side, m - th]
	for i in 4:
		var p: Vector3 = ring[i]
		var q: Vector3 = ring[(i + 1) % 4]
		k.face([base, p, q], (base + p + q) / 3.0 - m, color)
		k.face([tip, p, q], (tip + p + q) / 3.0 - m, color.lightened(0.08))


## 볼록 다각형(한 평면 위 점들)을 그 면의 법선 d 쪽으로 두께 t만큼 세운 판.
static func _slab(k, pts: Array, d: Vector3, t: float, color: Color) -> void:
	var h := d.normalized() * t * 0.5
	var front := pts.map(func(p): return p + h)
	var back := pts.map(func(p): return p - h)
	k.face(front, h, color)
	k.face(back, -h, color)
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	for i in pts.size():
		var j := (i + 1) % pts.size()
		k.face([front[i], front[j], back[j], back[i]], (pts[i] + pts[j]) / 2.0 - c, color.darkened(0.12))


## 가운데 c, 수평 고리(안 반지름 r_in, 바깥 r_out, 두께 h). k.xform 그대로 쓴다(기울일 때 쓰는 쪽이 정한다).
static func _ring(k, c: Vector3, r_in: float, r_out: float, h: float, sides: int, color: Color) -> void:
	var up := Vector3(0, h, 0)
	for i in sides:
		var d0 := Vector3(cos(TAU * i / sides), 0, sin(TAU * i / sides))
		var d1 := Vector3(cos(TAU * (i + 1) / sides), 0, sin(TAU * (i + 1) / sides))
		var o0 := c + d0 * r_out
		var o1 := c + d1 * r_out
		var i0 := c + d0 * r_in
		var i1 := c + d1 * r_in
		k.face([i0 + up, o0 + up, o1 + up, i1 + up], Vector3.UP, color)
		k.face([i0, o0, o1, i1], Vector3.DOWN, color.darkened(0.2))
		k.face([o0, o1, o1 + up, o0 + up], d0 + d1, color.darkened(0.05))
		k.face([i0, i1, i1 + up, i0 + up], -(d0 + d1), color.darkened(0.15))


## 머리에 얹는 둥근 모자 몸통: 밑 반지름 r(높이 y0) → 위로 좁아지는 두 단 + 윗면.
static func _cap(k, y0: float, r: float, h: float, color: Color, z := 0.0) -> void:
	k.prism_n(Vector3(0, y0, z), 10, r, r * 0.9, h * 0.55, color)
	k.prism_n(Vector3(0, y0 + h * 0.55, z), 10, r * 0.9, r * 0.5, h * 0.45, color.lightened(0.05))


## 불꽃 한 덩이(밑 c, 높이 h, 굵기 s): 바깥 주황 혀 다섯 + 안쪽 노란 혀 셋, 위로(+Y).
static func _flame(k, c: Vector3, h: float, s: float) -> void:
	for i in 5:
		var a := TAU * i / 5.0
		var d := Vector3(cos(a), 0, sin(a)) * 0.09 * s
		_leaf(k, c + d, c + d * 1.6 + Vector3(0, h * (0.75 + 0.25 * (i % 2)), 0), 0.2 * s, 0.08 * s, d, FIRE, 0.35)
	for i in 3:
		var a := TAU * i / 3.0 + 0.5
		var d := Vector3(cos(a), 0, sin(a)) * 0.04 * s
		_leaf(k, c + d, c + Vector3(0, h * 1.05, 0), 0.14 * s, 0.07 * s, d, FIRE_CORE, 0.35)


## 꽃(가운데 c, 꽃잎이 n에 수직인 면에 퍼짐): 꽃잎 다섯 + 가운데.
static func _flower(k, c: Vector3, n: Vector3, size: float, petal: Color, heart: Color) -> void:
	n = n.normalized()
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := n.cross(u)
	for i in 5:
		var a := TAU * i / 5.0
		var d := u * cos(a) + v * sin(a)
		_leaf(k, c, c + d * size, size * 0.6, size * 0.15, n, petal, 0.55)
	_tube(k, c - n * size * 0.08, c + n * size * 0.15, size * 0.25, size * 0.15, 6, heart)


## 아랫얼굴 복면(머리 공간): 코부터 턱까지 머리를 한 바퀴 감은 천 + 눈 바로 밑 빛줄.
static func _mask(k, cloth: Color, glow: Color) -> void:
	k.prism_n(Vector3(0, -0.06, 0.03), 10, 0.55, 0.57, 0.34, cloth)
	k.prism_n(Vector3(0, 0.27, 0.03), 10, 0.575, 0.575, 0.04, glow)


## 어깨받이 둘(가슴 공간 x = ±0.4): 둥근 판 두 단(색 → 테두리), spikes = 1이면 위로 가시 둘.
static func _pauldrons(k, color: Color, rim: Color, spikes: float) -> void:
	for s in [-1.0, 1.0]:
		var at := Vector3(s * 0.4, 0.14, 0.0)
		k.xform = Transform3D(Basis(Vector3.BACK, -s * 0.45), at)
		var r := 0.27 + 0.05 * spikes
		k.prism_n(Vector3.ZERO, 8, r, r * 0.95, 0.06, rim, PI / 8.0)
		k.prism_n(Vector3(0, 0.06, 0), 8, r * 0.92, r * 0.55, 0.12, color, PI / 8.0)
		k.prism_n(Vector3(0, 0.18, 0), 8, r * 0.55, r * 0.2, 0.05, color.lightened(0.1), PI / 8.0)
		k.xform = Transform3D.IDENTITY
		if spikes > 0.0:
			for z in [-0.1, 0.1]:
				_tube(k, at + Vector3(s * 0.08, 0.12, z), at + Vector3(s * 0.3, 0.5, z), 0.06, 0.0, 4, IRON_DARK)


# --- 기사 ---

## 빛의 성기사: 날개 투구 — 투구 양옆에서 위뒤로 펼친 흰 날개(깃 넷, 금 뿌리) + 이마 금 태양 보석. 날개 면을 45°로 세워 앞·옆 어디서 봐도 열려 보인다.
static func _arteon_wings(k) -> void:
	for s in [-1.0, 1.0]:
		var root := Vector3(s * 0.56, 0.86, -0.02)
		var tips := [Vector3(s * 0.86, 1.62, -0.2), Vector3(s * 1.04, 1.4, -0.36), Vector3(s * 1.1, 1.12, -0.46), Vector3(s * 0.98, 0.86, -0.5)]
		for i in tips.size():
			_leaf(k, root, tips[i], 0.26 - 0.03 * i, 0.08, Vector3(s, 0, 0.8), WHITE.darkened(0.04 * i), 0.4)
		_tube(k, root - Vector3(s * 0.06, 0, 0), root + Vector3(s * 0.12, 0.1, -0.04), 0.13, 0.09, 6, GOLD)
	_tube(k, Vector3(0, 0.98, 0.6), Vector3(0, 0.98, 0.75), 0.12, 0.05, 6, GOLD)


## 철벽 수문장: 투구 꼭대기 앞뒤로 쇠 가시 셋 + 이마 쇠 띠.
static func _baldur_spikes(k) -> void:
	for z in [0.28, 0.0, -0.28]:
		_tube(k, Vector3(0, 1.08, z), Vector3(0, 1.48 - absf(z) * 0.4, z - 0.05), 0.1, 0.0, 4, IRON_DARK)
	k.box(Vector3(0, 0.98, 0.0), Vector3(0.2, 0.22, 1.1), IRON)


## 방패병 대장: 투구 위 좌우로 펼친 붉은 말총 볏(백인대장).
static func _bron_crest(k) -> void:
	var red := Color("C0392B")
	_slab(k, [Vector3(-0.62, 1.0, 0), Vector3(-0.5, 1.36, 0), Vector3(-0.2, 1.52, 0), Vector3(0.2, 1.52, 0), Vector3(0.5, 1.36, 0),
		Vector3(0.62, 1.0, 0)], Vector3.BACK, 0.16, red)
	k.box(Vector3(0, 1.08, 0), Vector3(1.2, 0.08, 0.2), GOLD_DARK)


## 전투 사제: 흰 주교관(앞에서 뾰족한 아치, 금 띠·금 십자).
static func _torvin_mitre(k) -> void:
	k.prism_n(Vector3(0, 0.7, 0.0), 10, 0.55, 0.55, 0.1, GOLD)
	_slab(k, [Vector3(-0.5, 0.78, 0), Vector3(0.5, 0.78, 0), Vector3(0.44, 1.32, 0), Vector3(0, 1.82, 0), Vector3(-0.44, 1.32, 0)],
		Vector3.BACK, 0.66, WHITE)
	k.box(Vector3(0, 0.86, 0.33), Vector3(0.12, 0.8, 0.04), GOLD)
	k.box(Vector3(0, 1.22, 0.33), Vector3(0.42, 0.12, 0.04), GOLD)


## 전투 사제 철퇴(칼 자리): 나무 자루, 금 머리(8각 + 날개 넷 + 꼭지), 금 꼭지쇠. 길이 ≈ 1.6.
static func _torvin_mace(k) -> void:
	k.prism_n(Vector3(0, -0.4, 0), 6, 0.075, 0.06, 0.1, GOLD)
	k.prism_n(Vector3(0, -0.3, 0), 6, 0.05, 0.05, 1.15, WOOD_DARK)
	k.prism_n(Vector3(0, 0.82, 0), 8, 0.15, 0.17, 0.34, GOLD)
	k.cone(Vector3(0, 1.16, 0), 8, 0.17, 0.16, GOLD)
	k.box(Vector3(0.2, 0.84, 0), Vector3(0.12, 0.3, 0.05), GOLD_DARK)
	k.box(Vector3(-0.2, 0.84, 0), Vector3(0.12, 0.3, 0.05), GOLD_DARK)
	k.box(Vector3(0, 0.84, 0.2), Vector3(0.05, 0.3, 0.12), GOLD_DARK)
	k.box(Vector3(0, 0.84, -0.2), Vector3(0.05, 0.3, 0.12), GOLD_DARK)


## 기사단 창병: 투구 꼭대기에서 위뒤로 부채처럼 펼친 깃털 다섯(파랑·흰색) — 앞에서도 옆에서도 넓게 보인다.
static func _felix_plume(k) -> void:
	var blue := Color("2E86C1")
	for i in 5:
		var x := (i - 2) * 0.17
		_leaf(k, Vector3(x * 0.3, 1.12, 0.05), Vector3(x, 1.74 - absf(x) * 0.5, -0.4 - absf(x) * 0.6), 0.28, 0.12,
			Vector3(1, 0, x * 2.0), WHITE if i == 2 else blue.darkened(0.08 * absf(i - 2)))


## 기사단 창(대검 자리): 긴 나무 자루, 강철 촉(마름모), 촉 아래 파란 삼각 깃발. 길이 ≈ 4.
static func _felix_spear(k) -> void:
	k.prism_n(Vector3(0, -1.1, 0), 6, 0.045, 0.045, 3.4, WOOD)
	k.prism_n(Vector3(0, 2.25, 0), 6, 0.065, 0.06, 0.14, STEEL)
	k.cone(Vector3(0, 2.38, 0), 4, 0.13, 0.62, STEEL, PI / 4.0)
	k.xform = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, 2.4, 0))
	k.cone(Vector3.ZERO, 4, 0.13, 0.06, STEEL.darkened(0.2), PI / 4.0)
	k.xform = Transform3D.IDENTITY
	var flag := [Vector3(0.05, 2.2, 0), Vector3(0.05, 1.82, 0), Vector3(0.7, 1.98, 0)]
	k.face(flag, Vector3.BACK, Color("2E86C1"))
	k.face(flag, Vector3.FORWARD, Color("2E86C1").darkened(0.15))
	k.face([Vector3(0.05, 2.2, 0.01), Vector3(0.05, 2.08, 0.01), Vector3(0.45, 2.05, 0.01)], Vector3.BACK, WHITE)


## 민병대 검사: 쇠 챙모자(둥근 몸통 + 넓게 처진 챙).
static func _hans_kettle(k) -> void:
	k.prism_n(Vector3(0, 0.6, 0.0), 12, 0.9, 0.52, 0.16, IRON)
	_cap(k, 0.74, 0.54, 0.46, STEEL.darkened(0.25))
	k.prism_n(Vector3(0, 0.74, 0.0), 12, 0.555, 0.555, 0.06, WOOD_DARK)


# --- 마법사 ---

## 서리 마녀: 머리띠 위 얼음 결정 일곱(앞이 가장 높다), 흰색·하늘색 번갈아.
static func _seraphine_crown(k) -> void:
	k.prism_n(Vector3(0, 0.72, 0.02), 10, 0.53, 0.53, 0.09, ICE_DEEP)
	for i in 7:
		var a := TAU * i / 7.0
		var d := Vector3(sin(a), 0, cos(a))
		var h := 0.24 + 0.36 * pow((cos(a) + 1.0) / 2.0, 2.0)
		_tube(k, Vector3(0, 0.76, 0.02) + d * 0.5, Vector3(0, 0.76 + h, 0.02) + d * 0.58, 0.09, 0.0, 4, ICE if i % 2 == 0 else WHITE)


## 서리 마녀 완드 끝 얼음 결정(마름모 기둥 + 작은 결정 둘).
static func _ice_crystal(k) -> void:
	k.cone(Vector3(0, 0.66, 0), 4, 0.11, 0.42, ICE, PI / 4.0)
	k.xform = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, 0.68, 0))
	k.cone(Vector3.ZERO, 4, 0.11, 0.1, ICE_DEEP, PI / 4.0)
	k.xform = Transform3D.IDENTITY
	_tube(k, Vector3(0.04, 0.7, 0), Vector3(0.18, 0.92, 0.02), 0.05, 0.0, 4, WHITE)
	_tube(k, Vector3(-0.04, 0.7, 0), Vector3(-0.14, 0.88, -0.04), 0.05, 0.0, 4, ICE_DEEP)


## 성녀: 머리 위 금빛 후광 고리(뒤로 살짝 기움).
static func _lumina_halo(k) -> void:
	k.xform = Transform3D(Basis(Vector3.RIGHT, 0.45), Vector3(0, 1.22, -0.1))  # 앞으로 기울여 위·앞에서 보는 카메라에 고리가 열려 보이게
	_ring(k, Vector3.ZERO, 0.38, 0.56, 0.08, 16, Color("FFE27A"))
	k.xform = Transform3D.IDENTITY


## 성녀: 등에 흰 날개 한 쌍(깃 넷씩 부채꼴, 뿌리 금색).
static func _lumina_wings(k) -> void:
	for s in [-1.0, 1.0]:
		var root := Vector3(s * 0.12, 0.12, -0.4)
		var tips := [Vector3(s * 0.8, 1.08, -0.68), Vector3(s * 1.18, 0.72, -0.72), Vector3(s * 1.28, 0.26, -0.7), Vector3(s * 0.98, -0.2, -0.62)]
		for i in tips.size():
			_leaf(k, root, tips[i], 0.4 - 0.04 * i, 0.07, Vector3(0, 0.1, 1.0), WHITE.darkened(0.03 * i), 0.45)
		_tube(k, root - Vector3(s * 0.04, 0, 0), root + Vector3(s * 0.22, 0.12, -0.06), 0.08, 0.05, 6, GOLD)


## 견습 화염술사: 목에 감은 붉은 목도리 + 등 뒤로 날리는 두 자락.
static func _echo_scarf(k) -> void:
	var red := Color("C8302A")
	k.prism_n(Vector3(0, 0.2, 0.0), 10, 0.4, 0.36, 0.15, red)
	_leaf(k, Vector3(0.1, 0.26, -0.36), Vector3(0.34, -0.34, -0.66), 0.22, 0.05, Vector3(0, 0.3, 1.0), red, 0.25)
	_leaf(k, Vector3(-0.06, 0.26, -0.36), Vector3(-0.1, -0.5, -0.6), 0.2, 0.05, Vector3(0, 0.3, 1.0), red.darkened(0.12), 0.25)


## 견습 치유사: 꽃 화관(잎 고리 + 분홍·흰 꽃 다섯).
static func _nina_wreath(k) -> void:
	for i in 10:
		var a := TAU * i / 10.0
		var d := Vector3(sin(a), 0, cos(a))
		var t := Vector3(cos(a), 0, -sin(a))
		_leaf(k, Vector3(0, 0.8, 0.02) + d * 0.5 - t * 0.12, Vector3(0, 0.84, 0.02) + d * 0.52 + t * 0.16, 0.14, 0.05, Vector3.UP, Color("5FAF4A"), 0.5)
	for i in 5:
		var a := TAU * i / 5.0 - 0.6
		var d := Vector3(sin(a), 0, cos(a))
		_flower(k, Vector3(0, 0.86, 0.02) + d * 0.52, d + Vector3(0, 0.6, 0), 0.15, Color("FF8AB8") if i % 2 == 0 else WHITE, Color("FFE07A"))


# --- 두건 사수 ---

## 바람의 명사수: 두건 옆에서 위뒤로 뻗은 긴 흰 깃털 + 짧은 초록 깃.
static func _sylvana_feather(k) -> void:
	_leaf(k, Vector3(0.4, 0.8, 0.0), Vector3(0.86, 1.78, -0.5), 0.34, 0.08, Vector3(0.4, 0, 1), WHITE, 0.45)
	_leaf(k, Vector3(0.44, 0.74, -0.06), Vector3(0.98, 1.3, -0.6), 0.22, 0.08, Vector3(0.4, 0, 1), Color("9BE07A"), 0.45)


## 바람의 명사수: 등에 비스듬한 가죽 화살통 + 흰 깃 달린 화살 넷.
static func _sylvana_quiver(k) -> void:
	k.xform = Transform3D(Basis(Vector3.BACK, 0.45), Vector3(0.05, -0.42, -0.5))
	k.prism_n(Vector3.ZERO, 6, 0.15, 0.16, 0.85, Color("8A5A32"))
	k.prism_n(Vector3(0, 0.78, 0), 6, 0.17, 0.17, 0.08, GOLD_DARK)
	for i in 4:
		var o := Vector3(-0.06 + 0.04 * i, 0.86, -0.04 + 0.05 * (i % 2))
		k.prism_n(o, 4, 0.015, 0.015, 0.18, WOOD)
		k.cone(o + Vector3(0, 0.12, 0), 3, 0.06, 0.16, WHITE if i % 2 == 0 else Color("3DB45C"))
	k.xform = Transform3D.IDENTITY


## 천둥 궁수: 두건 양쪽에서 위로 꺾여 오르는 노란 번개 뿔(마름모 세 마디).
static func _nev_bolts(k) -> void:
	var yellow := Color("FFD21A")
	for s in [-1.0, 1.0]:
		var pts := [Vector3(s * 0.34, 0.86, 0.0), Vector3(s * 0.62, 1.16, -0.1), Vector3(s * 0.46, 1.24, -0.12), Vector3(s * 0.78, 1.72, -0.26)]
		for i in 3:
			_leaf(k, pts[i], pts[i + 1], 0.2, 0.08, Vector3(0, 0, 1), yellow, 0.5)


## 독화살 사냥꾼: 가슴을 가로지르는 띠 + 허리 양옆에 매단 연두 독병 넷(코르크 마개) — 쇠뇌가 가슴 앞을 가려도 보이게.
static func _mira_vials(k) -> void:
	var a := Vector3(0.36, 0.3, 0.37)
	var b := Vector3(-0.34, -0.5, 0.36)
	var side := (b - a).cross(Vector3.BACK).normalized() * 0.06
	k.face([a + side, b + side, b - side, a - side], Vector3.BACK, Color("2A2230"))
	for p in [Vector3(0.42, -0.62, 0.16), Vector3(0.44, -0.6, -0.04), Vector3(-0.42, -0.62, 0.16), Vector3(-0.44, -0.6, -0.04)]:
		k.prism_n(p, 6, 0.075, 0.07, 0.2, Color("9CE03A"))
		k.prism_n(p + Vector3(0, 0.2, 0), 6, 0.04, 0.035, 0.07, WOOD)


# --- 도적 ---

## 쌍검사: 이마 붉은 머리띠 + 뒤로 날리는 리본 두 자락.
static func _rian_band(k) -> void:
	var red := Color("D03A3A")
	k.prism_n(Vector3(0, 0.6, 0.0), 12, 0.55, 0.55, 0.11, red)
	_leaf(k, Vector3(0.04, 0.66, -0.52), Vector3(0.36, 0.12, -0.98), 0.16, 0.04, Vector3(1, 0, 0.2), red, 0.25)
	_leaf(k, Vector3(-0.04, 0.66, -0.52), Vector3(-0.2, 0.02, -0.92), 0.15, 0.04, Vector3(1, 0, -0.2), red.darkened(0.12), 0.25)


## 쌍검사 휜 장검(단검 자리, 양손 같은 메시): 검은 손잡이, 금 코등이, 끝으로 갈수록 휘는 강철 칼날. 길이 ≈ 1.6.
static func _rian_saber(k) -> void:
	k.prism_n(Vector3(0, -0.24, 0), 6, 0.04, 0.04, 0.3, Color("22222A"))
	k.box(Vector3(0, 0.05, 0), Vector3(0.24, 0.05, 0.1), GOLD)
	var ys := [0.1, 0.55, 0.95, 1.3]
	var xs := [0.0, 0.02, 0.07, 0.15]
	var ws := [0.065, 0.06, 0.055, 0.045]
	var t := 0.02
	for i in 3:
		var p := [Vector3(xs[i] - ws[i], ys[i], 0), Vector3(xs[i] + ws[i], ys[i], 0), Vector3(xs[i + 1] + ws[i + 1], ys[i + 1], 0),
			Vector3(xs[i + 1] - ws[i + 1], ys[i + 1], 0)]
		_slab(k, p, Vector3.BACK, t * 2.0, STEEL)
	_slab(k, [Vector3(xs[3] - ws[3], ys[3], 0), Vector3(xs[3] + ws[3], ys[3], 0), Vector3(0.26, 1.5, 0)], Vector3.BACK, t * 2.0, STEEL)


## 떠돌이 도적: 머리를 덮는 갈색 반다나(뒤 매듭 자락 둘) + 오른눈 검은 안대.
static func _jack_bandana(k) -> void:
	var cloth := Color("8E3A2A")
	_cap(k, 0.56, 0.56, 0.44, cloth, -0.02)
	_leaf(k, Vector3(0.04, 0.66, -0.5), Vector3(0.2, 0.36, -0.82), 0.14, 0.05, Vector3(1, 0, 0), cloth, 0.3)
	_leaf(k, Vector3(-0.04, 0.66, -0.5), Vector3(-0.12, 0.3, -0.78), 0.13, 0.05, Vector3(1, 0, 0), cloth.darkened(0.12), 0.3)
	k.box(Vector3(-0.17, 0.28, 0.44), Vector3(0.2, 0.18, 0.08), Color("141216"))
	k.box(Vector3(0, 0.44, 0.47), Vector3(0.9, 0.03, 0.1), Color("141216"))


# --- 야만전사 ---

## 대지의 광전사: 쇠 투구(둥근 두 단) + 바깥으로 휘어 오르는 큰 뿔 둘(마디마다 가늘어지고 끝은 짙게).
static func _grom_horns(k) -> void:
	_cap(k, 0.5, 0.6, 0.5, IRON)
	k.prism_n(Vector3(0, 0.5, 0.0), 10, 0.62, 0.62, 0.08, IRON_DARK)
	for s in [-1.0, 1.0]:
		var pts := [Vector3(s * 0.48, 0.74, 0.02), Vector3(s * 0.86, 0.86, 0.06), Vector3(s * 1.04, 1.16, 0.08), Vector3(s * 0.98, 1.5, 0.02)]
		var rs := [0.16, 0.12, 0.08, 0.0]
		for i in 3:
			_tube(k, pts[i], pts[i + 1], rs[i], rs[i + 1] if i < 2 else 0.0, 6, BONE.darkened(0.22 * i))


## 용사냥꾼: 왼 어깨(가슴 공간 +X) 용 해골 — 뼈 머리통, 앞으로 뻗은 주둥이·이빨, 검은 눈구멍, 뒤로 뻗은 뿔 둘.
static func _harald_skull(k) -> void:
	var c := Vector3(0.42, 0.24, 0.0)
	k.xform = Transform3D(Basis(Vector3.BACK, -0.5), c)
	k.prism_n(Vector3(0, -0.06, 0), 6, 0.24, 0.18, 0.24, BONE)
	k.box(Vector3(0.0, -0.02, 0.2), Vector3(0.24, 0.14, 0.34), BONE.darkened(0.06))
	for x in [-0.08, 0.08]:
		k.box(Vector3(x, 0.08, 0.17), Vector3(0.08, 0.06, 0.05), Color("201A18"))
		k.cone(Vector3(x, -0.02, 0.34), 3, 0.03, -0.08, WHITE)
	k.xform = Transform3D.IDENTITY
	_tube(k, c + Vector3(0.04, 0.12, -0.06), c + Vector3(0.24, 0.52, -0.42), 0.07, 0.0, 5, BONE.darkened(0.1))
	_tube(k, c + Vector3(-0.1, 0.14, -0.06), c + Vector3(-0.04, 0.5, -0.46), 0.06, 0.0, 5, BONE.darkened(0.2))


## 용사냥꾼 대검(도끼 자리): 긴 가죽 손잡이, 넓은 쇠 코등이, 폭 넓은 두꺼운 칼날(밝은 날 + 붉은 홈). 길이 ≈ 2.9.
static func _harald_sword(k) -> void:
	k.prism_n(Vector3(0, -0.62, 0), 6, 0.08, 0.07, 0.1, IRON_DARK)
	k.prism_n(Vector3(0, -0.52, 0), 6, 0.05, 0.05, 0.72, Color("3A2420"))
	k.box(Vector3(0, 0.2, 0), Vector3(0.62, 0.12, 0.16), IRON_DARK)
	var w := 0.19
	_slab(k, [Vector3(-w, 0.32, 0), Vector3(w, 0.32, 0), Vector3(w, 1.95, 0), Vector3(0, 2.28, 0), Vector3(-w, 1.95, 0)], Vector3.BACK, 0.07, IRON)
	_slab(k, [Vector3(-0.04, 0.4, 0), Vector3(0.04, 0.4, 0), Vector3(0.04, 1.8, 0), Vector3(-0.04, 1.8, 0)], Vector3.BACK, 0.08, Color("8E2418"))
	for s in [-1.0, 1.0]:
		_slab(k, [Vector3(s * w, 0.32, 0), Vector3(s * (w + 0.04), 0.36, 0), Vector3(s * (w + 0.04), 1.93, 0), Vector3(s * w, 1.95, 0)],
			Vector3.BACK, 0.04, STEEL)


## 도끼 투척꾼: 정수리 앞뒤로 선 주황 모히칸(마름모 깃 일곱, 가운데가 높다).
static func _gork_mohawk(k) -> void:
	for i in 7:
		var z := 0.36 - 0.13 * i
		var h := 0.3 + 0.22 * sin(PI * (i + 0.5) / 7.0)
		_leaf(k, Vector3(0, 0.86 - absf(z) * 0.25, z), Vector3(0, 0.9 + h, z - 0.12), 0.2, 0.12, Vector3.RIGHT,
			Color("F06A1A") if i % 2 == 0 else Color("D8461A"), 0.35)


## 도끼 투척꾼: 등에 엇갈려 멘 손도끼 둘(나무 자루 + 강철 날).
static func _gork_axes(k) -> void:
	for s in [-1.0, 1.0]:
		var a := Vector3(-s * 0.36, -0.4, -0.46)
		var b := Vector3(s * 0.34, 0.5, -0.5)
		_tube(k, a, b, 0.035, 0.03, 5, WOOD)
		var d := (b - a).normalized()
		_leaf(k, b - d * 0.18, b - d * 0.18 + Vector3(s * 0.3, 0.06, 0), 0.3, 0.05, Vector3.BACK, STEEL, 0.6)


## 나무꾼 전사: 겨자색 털모자(접은 단 + 둥근 몸통 + 흰 방울).
static func _dorik_beanie(k) -> void:
	var wool := Color("E3B23C")
	k.prism_n(Vector3(0, 0.52, 0.0), 10, 0.6, 0.6, 0.16, wool.darkened(0.2))
	_cap(k, 0.68, 0.57, 0.36, wool)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	k.rock(Vector3(0, 1.1, 0), 0.15, WHITE, rng, 1.0)

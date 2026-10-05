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
	"harald_sword", "gork_mohawk", "gork_axes", "dorik_beanie",
	"valen_crown", "valen_flames", "valen_orb", "frieda_crown", "frieda_collar", "frieda_flake", "morgana_horns", "morgana_skulls",
	"gaia_crown", "gaia_staff", "selene_stars", "pip_hat", "pip_spirit", "tia_hat", "thorgar_crown", "thorgar_boulders", "thorgar_maul",
	"orin_wolf", "grit_helmet", "grit_hammer", "dante_horns", "dante_wings", "kaz_goggles", "kaz_pack", "luna_tiara", "luna_blade",
	"raven_crest", "raven_mantle"]

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
		"valen_crown": _valen_crown(k)
		"valen_flames": _valen_flames(k)
		"valen_orb": _valen_orb(k)
		"frieda_crown": _frieda_crown(k)
		"frieda_collar": _frieda_collar(k)
		"frieda_flake": _frieda_flake(k)
		"morgana_horns": _morgana_horns(k)
		"morgana_skulls": _morgana_skulls(k)
		"gaia_crown": _gaia_crown(k)
		"gaia_staff": _gaia_staff(k)
		"selene_stars": _selene_stars(k)
		"pip_hat": _pip_hat(k)
		"pip_spirit": _pip_spirit(k)
		"tia_hat": _tia_hat(k)
		"thorgar_crown": _thorgar_crown(k)
		"thorgar_boulders": _thorgar_boulders(k)
		"thorgar_maul": _thorgar_maul(k)
		"orin_wolf": _orin_wolf(k)
		"grit_helmet": _grit_helmet(k)
		"grit_hammer": _grit_hammer(k)
		"dante_horns": _dante_horns(k)
		"dante_wings": _dante_wings(k)
		"kaz_goggles": _kaz_goggles(k)
		"kaz_pack": _kaz_pack(k)
		"luna_tiara": _luna_tiara(k)
		"luna_blade": _luna_blade(k)
		"raven_crest": _raven_crest(k)
		"raven_mantle": _raven_mantle(k)
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



# --- 새 영웅(개정 24) 도형 도우미 ---

## 가운데 c, 크기 size의 닫힌 상자(밑면까지 — 무기 머리처럼 아래에서도 보이는 덩어리).
static func _block(k, c: Vector3, size: Vector3, color: Color) -> void:
	var h := size / 2.0
	_slab(k, [c + Vector3(-h.x, 0, -h.z), c + Vector3(h.x, 0, -h.z), c + Vector3(h.x, 0, h.z), c + Vector3(-h.x, 0, h.z)], Vector3.UP, size.y, color)


## 가운데 c, n 방향을 보는 다섯 꼭지 별(바깥 반지름 r, 두께 t). 볼록한 연(가운데·안 꼭짓점 둘·끝) 다섯 장.
static func _star(k, c: Vector3, n: Vector3, r: float, t: float, color: Color) -> void:
	n = n.normalized()
	var u := n.cross(Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.UP).normalized()
	var v := n.cross(u)
	for i in 5:
		var a := TAU * i / 5.0
		var tip := c + (v * cos(a) + u * sin(a)) * r
		var a0 := c + (v * cos(a - PI / 5.0) + u * sin(a - PI / 5.0)) * r * 0.42
		var a1 := c + (v * cos(a + PI / 5.0) + u * sin(a + PI / 5.0)) * r * 0.42
		_slab(k, [c, a0, tip, a1], n, t, color)


## 초승달(k.xform 공간의 XY 면, +Z를 본다): 바깥 반원(반지름 r, 왼쪽) − 안쪽 납작 반원. 두 끝 (0, ±r), 가운데 두께 0.55r.
static func _crescent(k, r: float, t: float, color: Color) -> void:
	var n := 8
	for i in n:
		var a0 := PI / 2.0 + PI * i / n
		var a1 := PI / 2.0 + PI * (i + 1) / n
		var pts := [Vector3(r * cos(a0), r * sin(a0), 0), Vector3(r * cos(a1), r * sin(a1), 0)]
		if i < n - 1:
			pts.append(Vector3(0.45 * r * cos(a1), r * sin(a1), 0))
		if i > 0:
			pts.append(Vector3(0.45 * r * cos(a0), r * sin(a0), 0))
		_slab(k, pts, Vector3.BACK, t, color)


# --- 새 마법사 ---

## 불꽃 군주: 금 머리띠 위 금 뾰족 다섯(앞이 가장 높다), 뾰족마다 불꽃.
static func _valen_crown(k) -> void:
	k.prism_n(Vector3(0, 0.7, 0.02), 10, 0.55, 0.56, 0.12, GOLD_DARK)
	for i in 5:
		var a := (i - 2) * 0.62
		var d := Vector3(sin(a), 0, cos(a))
		var h := 0.26 + 0.14 * (1.0 - absf(i - 2) / 2.0)
		var base := Vector3(0, 0.8, 0.02) + d * 0.54
		_tube(k, base, base + Vector3(0, h, 0) + d * 0.05, 0.11, 0.0, 4, GOLD)
		_flame(k, base + Vector3(0, h * 0.75, 0) + d * 0.05, 0.3 + 0.12 * (1.0 - absf(i - 2) / 2.0), 0.55)
	k.prism_n(Vector3(0, 0.74, 0.57), 6, 0.07, 0.05, 0.05, FIRE)


## 불꽃 군주: 검은 쇠 어깨받이(금 테) 위로 타오르는 불꽃.
static func _valen_flames(k) -> void:
	_pauldrons(k, Color("2A1A16"), GOLD, 0.0)
	for s in [-1.0, 1.0]:
		_flame(k, Vector3(s * 0.5, 0.3, 0.0), 0.42, 0.8)


## 불꽃 군주 지팡이 머리: 흑요석 덩이를 감싼 금 갈퀴 넷 + 위로 솟는 큰 불꽃.
static func _valen_orb(k) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	k.rock(Vector3(0, 1.16, 0), 0.17, Color("3A1A12"), rng, 1.0)
	for i in 4:
		var d := Vector3(cos(TAU * i / 4.0 + 0.4), 0, sin(TAU * i / 4.0 + 0.4))
		_tube(k, Vector3(0, 0.98, 0) + d * 0.05, Vector3(0, 1.3, 0) + d * 0.2, 0.035, 0.0, 4, GOLD)
	_flame(k, Vector3(0, 1.2, 0), 0.62, 1.1)


## 빙하의 여왕: 은 머리띠 + 바깥으로 벌어진 큰 얼음 가시 아홉(앞 가운데가 가장 높은 왕관) + 이마 푸른 보석.
static func _frieda_crown(k) -> void:
	k.prism_n(Vector3(0, 0.7, 0.02), 12, 0.54, 0.56, 0.1, Color("D8E4EE"))
	for i in 9:
		var a := (i - 4) * 0.4
		var d := Vector3(sin(a), 0, cos(a))
		var h := 0.3 + 0.55 * pow(1.0 - absf(i - 4) / 4.0, 1.5)
		var base := Vector3(0, 0.76, 0.02) + d * 0.52
		_tube(k, base, base + Vector3(0, h, 0) + d * 0.16, 0.08 + 0.03 * (1.0 - absf(i - 4) / 4.0), 0.0, 4, ICE if i % 2 == 0 else WHITE)
	_leaf(k, Vector3(0, 0.72, 0.6), Vector3(0, 0.98, 0.62), 0.16, 0.08, Vector3.BACK, ICE_DEEP, 0.5)


## 빙하의 여왕: 목 뒤로 높이 선 얼음 깃(부채꼴 고드름 일곱).
static func _frieda_collar(k) -> void:
	for i in 7:
		var a := (i - 3) * 0.36
		var base := Vector3(sin(a) * 0.3, 0.28, -0.4 + absf(sin(a)) * 0.12)
		var tip := base + Vector3(sin(a) * 0.5, 0.55 + 0.35 * cos(a * 1.4), -0.12)
		_tube(k, base, tip, 0.1, 0.0, 4, ICE if i % 2 == 0 else WHITE)
	k.prism_n(Vector3(0, 0.22, 0.0), 10, 0.42, 0.4, 0.1, WHITE)


## 빙하의 여왕 완드 끝 눈송이(앞을 보는 여섯 가지, 가지마다 작은 곁가지 둘).
static func _frieda_flake(k) -> void:
	var c := Vector3(0, 0.88, 0)
	k.prism_n(Vector3(0, 0.62, 0), 6, 0.05, 0.03, 0.18, ICE_DEEP)
	for i in 6:
		var a := TAU * i / 6.0
		var d := Vector3(cos(a), sin(a), 0)
		var side := Vector3(-sin(a), cos(a), 0)
		_leaf(k, c, c + d * 0.26, 0.06, 0.04, Vector3.BACK, WHITE if i % 2 == 0 else ICE, 0.5)
		for s in [-1.0, 1.0]:
			_leaf(k, c + d * 0.14, c + d * 0.21 + side * s * 0.07, 0.035, 0.03, Vector3.BACK, ICE, 0.5)


## 망자의 여왕: 뼈 머리띠 + 이마 작은 해골 + 머리 옆에서 뒤로 휘어 오르는 검은 뿔 둘(끝은 보라).
static func _morgana_horns(k) -> void:
	k.prism_n(Vector3(0, 0.66, 0.02), 10, 0.54, 0.55, 0.08, BONE)
	k.prism_n(Vector3(0, 0.7, 0.5), 6, 0.12, 0.1, 0.17, BONE)
	k.box(Vector3(0, 0.64, 0.55), Vector3(0.14, 0.07, 0.08), BONE.darkened(0.15))
	for x in [-0.045, 0.045]:
		k.box(Vector3(x, 0.76, 0.6), Vector3(0.05, 0.05, 0.03), Color("201A18"))
	for s in [-1.0, 1.0]:
		var pts := [Vector3(s * 0.4, 0.8, 0.05), Vector3(s * 0.64, 1.04, -0.08), Vector3(s * 0.7, 1.3, -0.34), Vector3(s * 0.56, 1.46, -0.6),
			Vector3(s * 0.4, 1.42, -0.78)]
		var rs := [0.15, 0.12, 0.09, 0.06, 0.0]
		for i in 4:
			_tube(k, pts[i], pts[i + 1], rs[i], rs[i + 1] if i < 3 else 0.0, 6, Color("2A2030") if i < 3 else Color("8A4FC0"))


## 망자의 여왕: 양 어깨에 얹은 해골(뼈 머리통, 검은 눈구멍, 턱).
static func _morgana_skulls(k) -> void:
	for s in [-1.0, 1.0]:
		var c := Vector3(s * 0.44, 0.2, 0.02)
		k.prism_n(c, 7, 0.17, 0.14, 0.2, BONE)
		k.cone(c + Vector3(0, 0.2, 0), 7, 0.14, 0.06, BONE.lightened(0.05))
		k.box(c + Vector3(0, -0.07, 0.06), Vector3(0.18, 0.08, 0.14), BONE.darkened(0.12))
		for x in [-0.06, 0.06]:
			k.box(c + Vector3(x, 0.07, 0.13), Vector3(0.06, 0.06, 0.05), Color("201A18"))
		k.box(c + Vector3(0, 0.02, 0.15), Vector3(0.03, 0.04, 0.03), Color("201A18"))


## 숲의 대현자: 잎 왕관(위로 선 잎 열둘) + 머리 옆에서 갈라져 오르는 나무 뿔 둘.
static func _gaia_crown(k) -> void:
	k.prism_n(Vector3(0, 0.68, 0.02), 10, 0.54, 0.55, 0.08, Color("5A3E26"))
	for i in 12:
		var a := TAU * i / 12.0
		var d := Vector3(sin(a), 0, cos(a))
		var h := 0.26 + 0.12 * (cos(a) + 1.0) / 2.0
		_leaf(k, Vector3(0, 0.72, 0.02) + d * 0.52, Vector3(0, 0.74 + h, 0.02) + d * 0.66, 0.2, 0.05, d, Color("4CAF50") if i % 2 == 0 else Color("7CCB50"), 0.4)
	for s in [-1.0, 1.0]:
		var a := Vector3(s * 0.4, 0.86, -0.06)
		var b := Vector3(s * 0.62, 1.3, -0.16)
		var c := Vector3(s * 0.6, 1.62, -0.3)
		_tube(k, a, b, 0.07, 0.055, 5, WOOD)
		_tube(k, b, c, 0.055, 0.0, 5, WOOD)
		_tube(k, b + (c - b) * 0.2, Vector3(s * 0.9, 1.5, -0.12), 0.045, 0.0, 5, WOOD)
		_tube(k, a + (b - a) * 0.5, Vector3(s * 0.38, 1.36, 0.05), 0.04, 0.0, 5, WOOD)
		_leaf(k, c - (c - b) * 0.3, c + Vector3(s * 0.16, 0.0, 0.1), 0.12, 0.04, Vector3(0, 1, 0.3), Color("7CCB50"), 0.4)


## 숲의 대현자 지팡이(지팡이 자리): 굽은 나무 자루, 꼭대기 나뭇가지 셋이 감싼 초록 빛구슬, 잎 넷. 길이 ≈ 2.2.
static func _gaia_staff(k) -> void:
	var pts := [Vector3(0, -0.75, 0), Vector3(0.04, -0.2, 0.02), Vector3(-0.04, 0.4, -0.02), Vector3(0.04, 0.92, 0.0), Vector3(0, 1.12, 0)]
	for i in 4:
		_tube(k, pts[i], pts[i + 1], 0.065 - 0.005 * i, 0.06 - 0.005 * i, 6, WOOD if i % 2 == 0 else WOOD.darkened(0.1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	k.rock(Vector3(0, 1.32, 0), 0.13, Color("9CFF7A"), rng, 1.0)
	for i in 3:
		var d := Vector3(cos(TAU * i / 3.0), 0, sin(TAU * i / 3.0))
		_tube(k, Vector3(0, 1.1, 0), Vector3(0, 1.26, 0) + d * 0.2, 0.045, 0.035, 5, WOOD)
		_tube(k, Vector3(0, 1.26, 0) + d * 0.2, Vector3(0, 1.52, 0) + d * 0.04, 0.035, 0.0, 5, WOOD)
	for i in 4:
		var d := Vector3(cos(TAU * i / 4.0 + 0.8), 0, sin(TAU * i / 4.0 + 0.8))
		_leaf(k, Vector3(0, 1.08, 0) + d * 0.05, Vector3(0, 1.0, 0) + d * 0.32, 0.14, 0.04, Vector3.UP, Color("5FBF4A"), 0.45)


## 별의 예언자: 모자 끝에 큰 금 별 + 모자 둘레에 떠 있는 작은 별 셋.
static func _selene_stars(k) -> void:
	_star(k, Vector3(0, 1.52, -0.36), Vector3(0, 0.2, 1), 0.24, 0.09, Color("FFD84A"))  # 끝 ≈ 1.76 — 피규어 그림 위에 걸리지 않게
	_star(k, Vector3(0.78, 1.12, 0.1), Vector3(0.3, 0.2, 1), 0.12, 0.06, Color("FFE88A"))
	_star(k, Vector3(-0.74, 1.3, -0.1), Vector3(-0.3, 0.2, 1), 0.1, 0.05, Color("FFE88A"))
	_star(k, Vector3(-0.2, 1.24, 0.62), Vector3(0, 0.2, 1), 0.08, 0.05, WHITE)


## 견습 정령술사: 비스듬히 얹은 작은 뾰족 모자(하늘색, 흰 띠, 끝에 작은 별).
static func _pip_hat(k) -> void:
	var cyan := Color("4FC3D7")
	k.xform = Transform3D(Basis(Vector3.BACK, -0.32), Vector3(0.06, 0.9, 0.0))
	k.prism_n(Vector3(0, 0, 0), 10, 0.42, 0.38, 0.05, cyan.darkened(0.15))
	k.prism_n(Vector3(0, 0.05, 0), 10, 0.27, 0.24, 0.08, WHITE)
	k.prism_n(Vector3(0, 0.13, 0), 10, 0.24, 0.12, 0.3, cyan)
	k.cone(Vector3(0, 0.43, 0), 10, 0.12, 0.24, cyan.lightened(0.1))
	k.xform = Transform3D.IDENTITY
	_star(k, Vector3(0.29, 1.52, 0.0), Vector3(0, 0, 1), 0.1, 0.05, Color("FFE07A"))


## 견습 정령술사: 어깨 위에 떠 있는 작은 물 정령(하늘색 덩이, 검은 눈, 꼬리).
static func _pip_spirit(k) -> void:
	var c := Vector3(-0.66, 0.78, 0.18)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	k.rock(c, 0.17, Color("B2F5FF"), rng, 1.0)
	_leaf(k, c + Vector3(0, -0.06, -0.05), c + Vector3(0.12, -0.42, -0.12), 0.18, 0.08, Vector3.BACK, Color("80DEEA"), 0.2)
	for x in [-0.06, 0.06]:
		k.box(c + Vector3(x, 0.0, 0.15), Vector3(0.045, 0.07, 0.04), Color("1A2A3A"))


## 늪지 마녀: 축 처진 넓은 챙 + 뒤로 꺾인 이끼색 모자, 보라 띠, 챙 위 붉은 버섯 둘과 늘어진 이끼.
static func _tia_hat(k) -> void:
	var moss := Color("4E6B2A")
	k.prism_n(Vector3(0, 0.6, 0.0), 12, 1.0, 0.58, 0.14, moss.darkened(0.15))
	var pts := [Vector3(0, 0.72, 0), Vector3(0, 1.08, -0.06), Vector3(-0.06, 1.4, -0.22), Vector3(0.12, 1.6, -0.5), Vector3(0.34, 1.6, -0.66)]
	var rs := [0.56, 0.4, 0.24, 0.12, 0.0]
	for i in 4:
		_tube(k, pts[i], pts[i + 1], rs[i], rs[i + 1], 9, moss if i % 2 == 0 else moss.lightened(0.06))
	k.prism_n(Vector3(0, 0.72, 0.0), 12, 0.56, 0.52, 0.1, Color("6A2E7A"))
	for m in [[Vector3(0.62, 0.66, 0.3), 1.0], [Vector3(0.42, 0.68, 0.52), 0.7]]:
		var p: Vector3 = m[0]
		var sz: float = m[1]
		k.prism_n(p, 6, 0.045 * sz, 0.04 * sz, 0.18 * sz, WHITE)
		k.prism_n(p + Vector3(0, 0.16 * sz, 0), 8, 0.15 * sz, 0.13 * sz, 0.04 * sz, Color("C8302A"))
		k.cone(p + Vector3(0, 0.2 * sz, 0), 8, 0.13 * sz, 0.08 * sz, Color("D8402A"))
	for a in [-1.1, -0.2, 0.9, 2.2, 3.2]:
		var d := Vector3(sin(a), 0, cos(a))
		_leaf(k, Vector3(0, 0.6, 0) + d * 0.92, Vector3(0, 0.3, 0) + d * 0.96, 0.12, 0.04, d, Color("7A9A3A"), 0.3)


# --- 새 야만전사 ---

## 대지의 거인: 이끼 띠 위 바위 기둥 일곱(앞이 가장 높은 돌 왕관) + 이마 호박색 결정.
static func _thorgar_crown(k) -> void:
	var stone := Color("8A8276")
	k.prism_n(Vector3(0, 0.5, 0.0), 10, 0.62, 0.62, 0.12, Color("5F7F3A"))
	for i in 7:
		var a := TAU * i / 7.0
		var d := Vector3(sin(a), 0, cos(a))
		var h := 0.24 + 0.24 * pow((cos(a) + 1.0) / 2.0, 2.0)
		k.prism_n(Vector3(0, 0.6, 0) + d * 0.54, 5, 0.15, 0.07, h, stone.darkened(0.08 * (i % 3)), a)
	_tube(k, Vector3(0, 0.56, 0.62), Vector3(0, 0.86, 0.66), 0.09, 0.0, 4, Color("F0A030"))


## 대지의 거인: 양 어깨에 얹힌 큰 바위(이끼 덮개, 호박색 결정).
static func _thorgar_boulders(k) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for s in [-1.0, 1.0]:
		var c := Vector3(s * 0.48, 0.2, 0.0)
		k.rock(c, 0.34, Color("8A8276"), rng, 0.75)
		k.rock(c + Vector3(0, 0.2, 0), 0.24, Color("5F8F3A"), rng, 0.45)
		_tube(k, c + Vector3(s * 0.12, 0.18, -0.1), c + Vector3(s * 0.3, 0.48, -0.16), 0.07, 0.0, 4, Color("F0A030"))


## 대지의 거인 망치(도끼 자리): 굵은 나무 자루, 쇠 띠 두른 큰 돌 머리. 길이 ≈ 2.3.
static func _thorgar_maul(k) -> void:
	k.prism_n(Vector3(0, -0.6, 0), 6, 0.07, 0.065, 2.0, WOOD_DARK)
	k.prism_n(Vector3(0, -0.2, 0), 6, 0.08, 0.08, 0.3, Color("3A2A1E"))
	_block(k, Vector3(0, 1.3, 0), Vector3(0.66, 0.44, 0.42), Color("8A8276"))
	for x in [-0.2, 0.2]:
		_block(k, Vector3(x, 1.27, 0), Vector3(0.08, 0.5, 0.48), IRON_DARK)
	for s in [-1.0, 1.0]:
		_block(k, Vector3(s * 0.35, 1.34, 0), Vector3(0.05, 0.3, 0.3), Color("9E968A"))


## 야수 조련사: 늑대 머리 두건(회색 머리통, 앞으로 나온 주둥이·검은 코·송곳니, 노란 눈, 선 귀) + 등으로 늘어진 털가죽.
static func _orin_wolf(k) -> void:
	var fur := Color("8A8A90")
	_cap(k, 0.52, 0.64, 0.5, fur)
	_block(k, Vector3(0, 0.66, 0.66), Vector3(0.36, 0.24, 0.44), fur.lightened(0.08))
	_block(k, Vector3(0, 0.82, 0.62), Vector3(0.3, 0.1, 0.36), fur.darkened(0.06))
	_block(k, Vector3(0, 0.78, 0.88), Vector3(0.14, 0.1, 0.08), Color("1A1A1E"))
	for x in [-0.12, 0.12]:
		k.xform = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(x, 0.67, 0.82))
		k.cone(Vector3.ZERO, 4, 0.035, 0.12, WHITE)
		k.xform = Transform3D.IDENTITY
	for s in [-1.0, 1.0]:
		k.box(Vector3(s * 0.22, 0.86, 0.5), Vector3(0.1, 0.06, 0.06), Color("F0C030"))
		_tube(k, Vector3(s * 0.34, 0.92, 0.0), Vector3(s * 0.48, 1.28, -0.04), 0.13, 0.0, 4, fur.darkened(0.12))
	_slab(k, [Vector3(-0.42, 0.74, -0.46), Vector3(0.42, 0.74, -0.46), Vector3(0.32, 0.02, -0.64), Vector3(0, -0.2, -0.68),
		Vector3(-0.32, 0.02, -0.64)], Vector3(0, 0.2, -1), 0.08, fur.darkened(0.08))


## 광산 대장장이: 노란 광부 모자(둥근 몸통 + 챙) + 이마 쇠 등잔과 빛나는 등.
static func _grit_helmet(k) -> void:
	var yellow := Color("E8B020")
	k.prism_n(Vector3(0, 0.52, 0.04), 12, 0.74, 0.64, 0.07, yellow.darkened(0.15))
	_cap(k, 0.58, 0.62, 0.48, yellow)
	k.box(Vector3(0, 0.98, 0.0), Vector3(0.12, 0.08, 1.0), yellow.darkened(0.1))
	_tube(k, Vector3(0, 0.78, 0.56), Vector3(0, 0.78, 0.78), 0.14, 0.13, 8, IRON_DARK)
	_tube(k, Vector3(0, 0.78, 0.78), Vector3(0, 0.78, 0.82), 0.11, 0.11, 8, Color("FFF2A0"))


## 광산 대장장이 망치(손도끼 자리): 나무 자루, 가로 쇠 머리(한쪽 넓은 면·한쪽 뾰족). 길이 ≈ 1.2.
static func _grit_hammer(k) -> void:
	k.prism_n(Vector3(0, -0.3, 0), 6, 0.045, 0.04, 1.15, WOOD)
	_block(k, Vector3(0.0, 0.76, 0), Vector3(0.42, 0.24, 0.24), IRON)
	_block(k, Vector3(0.24, 0.74, 0), Vector3(0.08, 0.28, 0.28), STEEL.darkened(0.15))
	_tube(k, Vector3(-0.2, 0.88, 0), Vector3(-0.42, 0.88, 0), 0.1, 0.0, 4, IRON_DARK)


# --- 새 기사 ---

## 용기사: 투구 옆에서 뒤로 휘어 뻗은 용 뿔 둘 + 정수리 앞뒤로 선 붉은 지느러미 볏.
static func _dante_horns(k) -> void:
	for s in [-1.0, 1.0]:
		var pts := [Vector3(s * 0.5, 0.98, 0.05), Vector3(s * 0.7, 1.22, -0.18), Vector3(s * 0.78, 1.42, -0.52), Vector3(s * 0.72, 1.6, -0.86)]
		var rs := [0.13, 0.1, 0.06, 0.0]
		for i in 3:
			_tube(k, pts[i], pts[i + 1], rs[i], rs[i + 1], 6, Color("2A1E1E").lightened(0.1 * i))
	_slab(k, [Vector3(0, 1.16, 0.42), Vector3(0, 1.48, 0.1), Vector3(0, 1.56, -0.3), Vector3(0, 1.36, -0.66), Vector3(0, 1.12, -0.5)],
		Vector3.RIGHT, 0.08, Color("C0392B"))
	for z in [0.1, -0.3]:
		_tube(k, Vector3(0, 1.46, z), Vector3(0, 1.72, z - 0.14), 0.05, 0.0, 4, GOLD)


## 용기사: 등에 펼친 박쥐 날개 한 쌍(검은 뼈대, 붉은 막).
static func _dante_wings(k) -> void:
	var skin := Color("8E2418")
	var spar := Color("2A1E1E")
	for s in [-1.0, 1.0]:
		var root := Vector3(s * 0.14, 0.18, -0.44)
		var elbow := Vector3(s * 0.62, 0.78, -0.62)
		var tips := [Vector3(s * 1.2, 1.0, -0.72), Vector3(s * 1.32, 0.44, -0.74), Vector3(s * 1.02, -0.08, -0.66)]
		_tube(k, root, elbow, 0.06, 0.05, 5, spar)
		for t in tips:
			_tube(k, elbow, t, 0.04, 0.0, 4, spar)
		for i in tips.size() - 1:
			var mid: Vector3 = (tips[i] + tips[i + 1]) / 2.0 * 0.82 + elbow * 0.18
			_slab(k, [elbow, tips[i], mid], Vector3.BACK, 0.03, skin.lightened(0.05 * i))
			_slab(k, [elbow, mid, tips[i + 1]], Vector3.BACK, 0.03, skin.darkened(0.05 * i))
		_slab(k, [root, elbow, tips[2]], Vector3.BACK, 0.03, skin.darkened(0.12))


# --- 새 도적 ---

## 떠돌이 기계공: 머리를 감은 가죽 끈 + 이마에 올린 놋쇠 고글 둘(호박색 렌즈).
static func _kaz_goggles(k) -> void:
	var brass := Color("C8902A")
	k.prism_n(Vector3(0, 0.6, 0.0), 12, 0.56, 0.56, 0.09, Color("4A3022"))
	for x in [-0.19, 0.19]:
		_tube(k, Vector3(x, 0.66, 0.44), Vector3(x, 0.66, 0.62), 0.15, 0.13, 8, brass)
		_tube(k, Vector3(x, 0.66, 0.62), Vector3(x, 0.66, 0.65), 0.1, 0.1, 8, Color("FFB040"))
	k.box(Vector3(0, 0.62, 0.56), Vector3(0.12, 0.06, 0.06), brass.darkened(0.2))


## 떠돌이 기계공: 등에 멘 가죽 짐(옆에 놋쇠 톱니바퀴, 위로 구리 굴뚝관).
static func _kaz_pack(k) -> void:
	var brass := Color("C8902A")
	_block(k, Vector3(0, -0.32, -0.6), Vector3(0.62, 0.66, 0.36), Color("7A5232"))
	_block(k, Vector3(0, 0.28, -0.6), Vector3(0.66, 0.1, 0.4), Color("5A3A22"))
	for x in [-0.2, 0.2]:
		k.box(Vector3(x, -0.34, -0.4), Vector3(0.08, 0.64, 0.04), Color("4A3022"))
	k.xform = Transform3D(Basis(Vector3.BACK, -PI / 2.0), Vector3(0.3, 0.0, -0.6))
	k.prism_n(Vector3.ZERO, 8, 0.2, 0.2, 0.06, brass)
	for i in 8:
		var a := TAU * i / 8.0 + PI / 8.0
		k.box(Vector3(cos(a) * 0.23, 0, sin(a) * 0.23), Vector3(0.08, 0.06, 0.08), brass.darkened(0.1))
	k.prism_n(Vector3(0, 0.06, 0), 6, 0.06, 0.06, 0.03, IRON_DARK)
	k.xform = Transform3D.IDENTITY
	_tube(k, Vector3(-0.18, 0.34, -0.66), Vector3(-0.2, 0.74, -0.7), 0.06, 0.06, 6, Color("B86A3A"))
	k.prism_n(Vector3(-0.2, 0.72, -0.7), 6, 0.09, 0.09, 0.06, Color("8A4A2A"))


## 달빛 무희: 은 머리띠 + 이마 위 은빛 초승달(양 끝이 위) + 연보라 보석.
static func _luna_tiara(k) -> void:
	k.prism_n(Vector3(0, 0.6, 0.0), 12, 0.56, 0.56, 0.06, Color("E4E4F0"))
	k.xform = Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(0, 0.86, 0.56))
	_crescent(k, 0.22, 0.06, Color("F4F2FF"))
	k.xform = Transform3D.IDENTITY
	k.prism_n(Vector3(0, 0.62, 0.55), 6, 0.06, 0.04, 0.08, Color("B9A8FF"))


## 달빛 무희 초승달 칼(단검 자리, 양손 같은 메시): 검은 손잡이, 은 코등이, 휘어 오르는 연보라 칼날. 길이 ≈ 1.1.
static func _luna_blade(k) -> void:
	k.prism_n(Vector3(0, -0.22, 0), 6, 0.035, 0.035, 0.28, Color("2A2440"))
	k.box(Vector3(0, 0.04, 0), Vector3(0.2, 0.04, 0.08), Color("E4E4F0"))
	var blade := Color("D8D0FF")
	var ys := [0.08, 0.38, 0.64, 0.84]
	var xs := [0.0, 0.05, 0.14, 0.27]
	var ws := [0.05, 0.075, 0.07, 0.05]
	for i in 3:
		_slab(k, [Vector3(xs[i] - ws[i], ys[i], 0), Vector3(xs[i] + ws[i], ys[i], 0), Vector3(xs[i + 1] + ws[i + 1], ys[i + 1], 0),
			Vector3(xs[i + 1] - ws[i + 1], ys[i + 1], 0)], Vector3.BACK, 0.035, blade)
	_slab(k, [Vector3(xs[3] - ws[3], ys[3], 0), Vector3(xs[3] + ws[3], ys[3], 0), Vector3(0.42, 0.96, 0)], Vector3.BACK, 0.035, blade)


## 그림자 명궁: 두건 꼭대기에서 뒤로 선 검은 깃 볏(일곱, 끝은 남보라) + 관자놀이에서 뒤로 뻗은 긴 깃 둘.
static func _raven_crest(k) -> void:
	var black := Color("1E1F2A")
	for i in 7:
		var z := 0.3 - 0.12 * i
		var h := 0.3 + 0.2 * sin(PI * (i + 0.5) / 7.0)
		_leaf(k, Vector3(0, 0.9 - absf(z) * 0.2, z), Vector3(0, 0.96 + h, z - 0.3), 0.2, 0.08, Vector3.RIGHT,
			black if i % 2 == 0 else Color("3A3F68"), 0.35)
	for s in [-1.0, 1.0]:
		_leaf(k, Vector3(s * 0.44, 0.62, 0.0), Vector3(s * 0.8, 0.96, -0.6), 0.2, 0.06, Vector3(s, 0.4, 0), black, 0.4)
		_leaf(k, Vector3(s * 0.46, 0.56, -0.04), Vector3(s * 0.84, 0.66, -0.66), 0.16, 0.06, Vector3(s, 0.4, 0), Color("4A4F80"), 0.4)


## 그림자 명궁: 어깨를 덮은 검은 깃 망토(어깨마다 아래로 겹친 깃 다섯) + 목 뒤 깃 고리.
static func _raven_mantle(k) -> void:
	var black := Color("1E1F2A")
	for s in [-1.0, 1.0]:
		for i in 5:
			var z := 0.2 - 0.12 * i
			_leaf(k, Vector3(s * 0.18, 0.32, z), Vector3(s * 0.66, -0.12 - 0.04 * (i % 2), z * 1.2), 0.22, 0.05, Vector3(s, 1.2, 0),
				black if i % 2 == 0 else Color("2E3350"), 0.35)
	for i in 5:
		var a := (i - 2) * 0.5
		_leaf(k, Vector3(sin(a) * 0.2, 0.26, -0.36), Vector3(sin(a) * 0.4, 0.62, -0.5), 0.2, 0.05, Vector3(0, 0.2, -1), black, 0.35)

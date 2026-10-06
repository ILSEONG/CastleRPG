extends RefCounted
## 발동형 스킬 썸네일(사용자 2026-10-06: 영웅 초상화 좌우 아래 쿨 칸에 스킬 그림). 아이콘(icons.gd)과 같은 평면 로우폴리 —
## 각진 다각형, 면마다 단색, 밝은 면 하나, 얇은 진한 외곽. 칸 = 속성 색 원 + 그 위 그림 하나(KIND).
## 그림은 icons.gd의 것을 다시 쓰거나(검·도끼·망치·과녁…) 여기서 정의한 스킬 그림(불덩이·눈송이·번개…). 텍스처 없음(APK 크기 0).

const Icons := preload("res://scripts/icons.gd")

const OUTLINE := Color(0.16, 0.11, 0.07)
# 속성 바탕색
const FIRE := Color(0.86, 0.36, 0.16)
const LAVA := Color(0.62, 0.18, 0.12)
const ICE := Color(0.34, 0.62, 0.86)
const STORM := Color(0.24, 0.30, 0.58)
const WIND := Color(0.40, 0.70, 0.64)
const EARTH := Color(0.55, 0.40, 0.24)
const NATURE := Color(0.34, 0.58, 0.28)
const POISON := Color(0.44, 0.56, 0.18)
const HOLY := Color(0.93, 0.76, 0.30)
const SHADOW := Color(0.36, 0.22, 0.52)
const BLOOD := Color(0.66, 0.16, 0.20)
const STEEL := Color(0.56, 0.32, 0.26)  # 물리 공격(붉은 갈색)
const GUARD := Color(0.32, 0.46, 0.66)  # 방어·도발
const HEAL := Color(0.40, 0.72, 0.46)
const SUMMON := Color(0.48, 0.40, 0.70)
const SONG := Color(0.82, 0.48, 0.22)

## 스킬 kind → [그림, 바탕색]. 없는 kind는 "burst" + 물리 바탕.
const KIND := {
	"meteor": ["fireball", FIRE], "inferno": ["flame", FIRE], "ignite": ["flame", FIRE], "firespread": ["flame", LAVA],
	"fire_bolt": ["fireball", FIRE], "dragon_breath": ["flame", LAVA], "lava_burst": ["fireball", LAVA], "aoe_blast": ["fireball", FIRE],
	"solar_flare": ["sun", FIRE],
	"blizzard": ["snowflake", ICE], "frost_nova": ["snowflake", ICE], "ice_spikes": ["ice_spike", ICE], "frost_chain": ["chain", ICE],
	"deep_freeze": ["snowflake", STORM],
	"thunder_storm": ["bolt", STORM], "sky_bolt": ["bolt", STORM], "tornado": ["swirl", WIND], "whirlwind": ["swirl", STEEL],
	"earthquake": ["crack", EARTH], "ground_slam": ["crack", EARTH], "shockwave": ["wave", EARTH], "crushing_blow": ["hammer", EARTH],
	"poison_cloud": ["cloud", POISON], "snare": ["vine", NATURE],
	"starfall": ["star", STORM], "comet": ["comet", STORM], "holy_smite": ["sun", HOLY], "sanctuary": ["cross", HOLY],
	"mass_heal": ["cross", HEAL], "heal_aura": ["cross", HEAL], "resurrection": ["heart", HOLY],
	"shadow_strike": ["dagger", SHADOW], "void_rift": ["swirl", SHADOW], "abyss_hand": ["claw", SHADOW], "hex": ["eye", SHADOW],
	"lunar_veil": ["moon", SHADOW], "crescent": ["moon", STORM], "cheap_shot": ["dagger", STEEL],
	"blood_rage": ["drop", BLOOD], "drain_slash": ["drop", SHADOW], "rend": ["claw", BLOOD],
	"arrow_rain": ["arrows", STEEL], "volley": ["arrows", NATURE], "piercing_shot": ["arrow", STEEL],
	"spear_throw": ["spear", STEEL], "spear_sweep": ["spear", EARTH],
	"blade_flurry": ["elite", STEEL], "wide_swing": ["sword", STEEL], "sunder": ["axe", STEEL], "axe_volley": ["axe", EARTH],
	"boomerang": ["moon", EARTH],
	"war_cry": ["burst", BLOOD], "battle_hymn": ["note", SONG], "howl": ["paw", STORM], "taunt": ["burst", GUARD],
	"shield": ["shield", GUARD], "shield_ally": ["heart_shield", GUARD], "bulwark": ["shield", EARTH], "parry": ["sword", GUARD],
	"shield_bash": ["shield", STEEL], "gate_repair": ["gate", GUARD],
	"summon_wolf": ["paw", SUMMON], "summon_skeleton": ["skull", SUMMON], "summon_golem": ["stone", SUMMON],
	"summon_treant": ["tree", NATURE], "summon_spirit": ["orb", SUMMON], "summon_phoenix": ["bird", FIRE],
	"summon_hawk": ["bird", WIND], "summon_turret": ["crossbow", SUMMON],
}


static func glyph_of(kind: String) -> String:
	return KIND.get(kind, ["burst", STEEL])[0]


static func bg_of(kind: String) -> Color:
	return KIND.get(kind, ["burst", STEEL])[1]


## ci에 at 중심 반지름 r 원 칸: 속성 바탕 + 밝은 위 반달 + 그림. dim이면 회색으로 눌러 그린다(잠김).
static func draw_badge(ci: CanvasItem, kind: String, at: Vector2, r: float, dim := false) -> void:
	var bg := bg_of(kind)
	if dim:
		bg = _gray(bg)
	ci.draw_circle(at, r, bg)
	var top := PackedVector2Array()
	for i in 13:
		top.append(at + Vector2.from_angle(PI + PI * i / 12.0) * r)
	ci.draw_colored_polygon(top, Color(1, 1, 1, 0.14))
	draw_glyph(ci, glyph_of(kind), at, r * 1.5, dim)


static func draw_glyph(ci: CanvasItem, glyph: String, center: Vector2, size_px: float, dim := false) -> void:
	var line_w := maxf(1.0, size_px / 28.0)
	for shape in shapes(glyph):
		var pts := PackedVector2Array()
		for p in shape[0]:
			pts.append(center + p * size_px)
		var col: Color = shape[1]
		if col.a > 0.0:
			ci.draw_colored_polygon(pts, _gray(col) if dim else col)
		if shape[2]:
			pts.append(pts[0])
			ci.draw_polyline(pts, OUTLINE, line_w)


static func _gray(c: Color) -> Color:
	var v := c.get_luminance() * 0.75 + 0.08
	return Color(v, v, v, c.a)


## [점 배열(단위 좌표 -0.5..0.5), 색, 외곽선 여부]. 스킬 그림이 아니면 icons.gd 그림.
static func shapes(glyph: String) -> Array:
	match glyph:
		"fireball":  # 왼 아래에서 날아오는 불덩이: 넓은 불꼬리(주황·노랑) + 주황 몸통 + 노란 속 + 흰 빛
			var o := Vector2(0.10, -0.10)
			var pp := Vector2(0.707, 0.707)
			return [
				[[o + pp * 0.24, Vector2(-0.22, 0.42), Vector2(-0.46, 0.46), Vector2(-0.42, 0.22), o - pp * 0.24], Color(0.98, 0.50, 0.14), true],
				[[o + pp * 0.13, Vector2(-0.26, 0.34), Vector2(-0.38, 0.38), Vector2(-0.34, 0.26), o - pp * 0.13], Color(1.0, 0.80, 0.30), false],
				[_ngon(8, 0.25, 0.3).map(func(p): return p + o), Color(0.98, 0.42, 0.12), true],
				[_ngon(8, 0.16, 0.3).map(func(p): return p + o + Vector2(0.02, -0.02)), Color(1.0, 0.80, 0.26), false],
				[_ngon(6, 0.06, 0.0).map(func(p): return p + o + Vector2(0.05, -0.06)), Color(1.0, 0.98, 0.84), false],
			]
		"flame":  # 세 갈래 불꽃(가운데 높게) + 노란 속불
			var outer := [Vector2(0.0, 0.44), Vector2(-0.30, 0.30), Vector2(-0.36, 0.02), Vector2(-0.22, -0.18), Vector2(-0.18, 0.02),
				Vector2(-0.06, -0.20), Vector2(0.02, -0.46), Vector2(0.16, -0.22), Vector2(0.18, -0.02), Vector2(0.28, -0.18),
				Vector2(0.36, 0.04), Vector2(0.30, 0.30)]
			var inner := [Vector2(0.0, 0.40), Vector2(-0.16, 0.30), Vector2(-0.18, 0.12), Vector2(-0.04, -0.08), Vector2(0.04, 0.08),
				Vector2(0.12, -0.02), Vector2(0.18, 0.16), Vector2(0.14, 0.32)]
			return [
				[outer, Color(0.98, 0.44, 0.12), true],
				[[Vector2(0.0, 0.44), Vector2(-0.30, 0.30), Vector2(-0.36, 0.02), Vector2(-0.22, -0.18), Vector2(-0.18, 0.02), Vector2(-0.06, -0.20),
					Vector2(0.02, -0.46), Vector2(0.0, 0.0)], Color(1.0, 0.56, 0.18), false],
				[inner, Color(1.0, 0.84, 0.28), false],
			]
		"sun":  # 금빛 해: 8갈래 빛살 + 둥근 속
			var rays := []
			for i in 16:
				rays.append(Vector2.from_angle(-PI / 2.0 + TAU * i / 16.0) * (0.46 if i % 2 == 0 else 0.26))
			return [
				[rays, Color(1.0, 0.82, 0.26), true],
				[_ngon(12, 0.22, 0.0), Color(1.0, 0.94, 0.62), true],
				[[Vector2(-0.14, -0.08), Vector2(-0.06, -0.16), Vector2(0.0, -0.12), Vector2(-0.10, -0.03)], Color(1, 1, 1, 0.9), false],
			]
		"snowflake":  # 눈송이: 6갈래 + 가지
			var out := []
			for i in 6:
				var d := Vector2.from_angle(-PI / 2.0 + TAU * i / 6.0)
				out.append([_quad(Vector2.ZERO, d * 0.44, 0.045), Color(0.92, 0.98, 1.0), true])
			for i in 6:
				var d := Vector2.from_angle(-PI / 2.0 + TAU * i / 6.0)
				var m := d * 0.28
				out.append([_quad(m, m + d.rotated(0.8) * 0.13, 0.03), Color(0.92, 0.98, 1.0), false])
				out.append([_quad(m, m + d.rotated(-0.8) * 0.13, 0.03), Color(0.92, 0.98, 1.0), false])
			out.append([_ngon(6, 0.09, PI / 6.0), Color(0.70, 0.88, 1.0), true])
			return out
		"ice_spike":  # 얼음 가시 셋(가운데 높게), 밝은 왼쪽 면
			var out := []
			for s in [[Vector2(-0.24, 0.40), 0.12, 0.50], [Vector2(0.24, 0.40), 0.12, 0.50], [Vector2(0.0, 0.42), 0.16, 0.86]]:
				var b: Vector2 = s[0]
				var w: float = s[1]
				var tip := b + Vector2(0, -s[2])
				out.append([[b + Vector2(-w, 0), tip, b + Vector2(w, 0)], Color(0.72, 0.90, 1.0), true])
				out.append([[b + Vector2(-w, 0), tip, b], Color(0.92, 0.98, 1.0), false])
			return out
		"chain":  # 고리 셋 대각선 사슬(얼음색)
			var out := []
			for i in 3:
				var c := Vector2(-0.26, 0.26) + Vector2(0.26, -0.26) * i
				var ring := _ngon(8, 0.18, PI / 8.0)
				var hole := _ngon(8, 0.09, PI / 8.0)
				out.append([ring.map(func(p): return Vector2(p.x * 1.3, p.y * 0.8).rotated(-PI / 4.0 if i != 1 else PI / 4.0) + c), Color(0.84, 0.94, 1.0), true])
				out.append([hole.map(func(p): return Vector2(p.x * 1.5, p.y * 0.6).rotated(-PI / 4.0 if i != 1 else PI / 4.0) + c), Color(0.20, 0.36, 0.56), false])
			return out
		"bolt":  # 번개: 지그재그 노랑, 밝은 왼쪽
			var z := [Vector2(0.10, -0.46), Vector2(-0.24, 0.04), Vector2(-0.02, 0.04), Vector2(-0.14, 0.46), Vector2(0.26, -0.10),
				Vector2(0.04, -0.10), Vector2(0.20, -0.46)]
			return [
				[z, Color(1.0, 0.86, 0.22), true],
				[[Vector2(0.10, -0.46), Vector2(-0.24, 0.04), Vector2(-0.02, 0.04), Vector2(0.08, -0.20)], Color(1.0, 0.96, 0.66), false],
			]
		"swirl":  # 회오리: 아래로 좁아지는 띠 넷
			var out := []
			var ys := [-0.38, -0.18, 0.02, 0.22]
			for i in 4:
				var w := 0.42 - i * 0.09
				var y: float = ys[i]
				var x := (i % 2) * 0.06 - 0.03
				out.append([[Vector2(-w + x, y), Vector2(w + x, y - 0.04), Vector2(w - 0.06 + x, y + 0.13), Vector2(-w + 0.06 + x, y + 0.15)],
					Color(0.92, 0.96, 0.96) if i % 2 == 0 else Color(0.78, 0.86, 0.88), true])
			out.append([[Vector2(-0.06, 0.38), Vector2(0.08, 0.38), Vector2(0.02, 0.48)], Color(0.78, 0.86, 0.88), true])
			return out
		"crack":  # 갈라진 땅: 돌판 위 지그재그 금 + 튀는 돌
			return [
				[[Vector2(-0.46, 0.10), Vector2(0.46, 0.10), Vector2(0.40, 0.36), Vector2(-0.40, 0.36)], Color(0.70, 0.58, 0.40), true],
				[[Vector2(-0.46, 0.10), Vector2(0.46, 0.10), Vector2(0.44, 0.18), Vector2(-0.44, 0.18)], Color(0.84, 0.72, 0.52), false],
				[[Vector2(-0.04, 0.10), Vector2(0.06, 0.20), Vector2(-0.02, 0.26), Vector2(0.06, 0.36), Vector2(-0.08, 0.36), Vector2(-0.12, 0.26),
					Vector2(-0.06, 0.20), Vector2(-0.14, 0.10)], Color(0.20, 0.14, 0.10), false],
				[_ngon(5, 0.10, 0.3).map(func(p): return p + Vector2(-0.24, -0.16)), Color(0.78, 0.66, 0.46), true],
				[_ngon(5, 0.08, 0.9).map(func(p): return p + Vector2(0.20, -0.26)), Color(0.78, 0.66, 0.46), true],
				[_ngon(4, 0.06, 0.4).map(func(p): return p + Vector2(0.02, -0.38)), Color(0.78, 0.66, 0.46), true],
			]
		"wave":  # 퍼지는 충격파: 반원 고리 둘 + 가운데 점
			var out := []
			for rr in [0.44, 0.28]:
				var arc := []
				for i in 9:
					arc.append(Vector2.from_angle(PI + PI * i / 8.0) * rr + Vector2(0, 0.18))
				for i in 9:
					arc.append(Vector2.from_angle(TAU - PI * i / 8.0) * (rr - 0.09) + Vector2(0, 0.18))
				out.append([arc, Color(0.98, 0.90, 0.70), true])
			out.append([_ngon(8, 0.09, 0.0).map(func(p): return p + Vector2(0, 0.14)), Color(1.0, 0.98, 0.88), true])
			return out
		"cloud":  # 독구름: 초록 구름 + 해골 점 둘
			var c := Color(0.66, 0.86, 0.36)
			return [
				[_ngon(8, 0.20, 0.2).map(func(p): return p + Vector2(-0.20, 0.06)), c, true],
				[_ngon(8, 0.24, 0.0).map(func(p): return p + Vector2(0.06, -0.08)), c, true],
				[_ngon(8, 0.18, 0.3).map(func(p): return p + Vector2(0.26, 0.10)), c, true],
				[[Vector2(-0.36, 0.10), Vector2(0.40, 0.10), Vector2(0.36, 0.26), Vector2(-0.32, 0.26)], c, false],
				[[Vector2(-0.30, -0.04), Vector2(-0.14, -0.20), Vector2(0.04, -0.26), Vector2(0.0, -0.12)], c.lightened(0.3), false],
				[_ngon(6, 0.05, 0.0).map(func(p): return p + Vector2(-0.06, 0.08)), Color(0.22, 0.30, 0.12), false],
				[_ngon(6, 0.05, 0.0).map(func(p): return p + Vector2(0.12, 0.08)), Color(0.22, 0.30, 0.12), false],
			]
		"vine":  # 휘감는 덩굴: 굽은 줄기 + 잎 셋
			var g := Color(0.60, 0.84, 0.34)
			return [
				[_quad(Vector2(-0.30, 0.42), Vector2(-0.10, 0.04), 0.05), Color(0.46, 0.66, 0.22), true],
				[_quad(Vector2(-0.10, 0.04), Vector2(0.26, -0.16), 0.045), Color(0.46, 0.66, 0.22), true],
				[_quad(Vector2(0.26, -0.16), Vector2(0.14, -0.42), 0.04), Color(0.46, 0.66, 0.22), true],
				[[Vector2(-0.18, 0.20), Vector2(-0.42, 0.06), Vector2(-0.24, 0.02)], g, true],
				[[Vector2(0.08, -0.06), Vector2(0.30, 0.10), Vector2(0.36, -0.04)], g, true],
				[[Vector2(0.20, -0.30), Vector2(-0.04, -0.36), Vector2(0.06, -0.22)], g, true],
			]
		"star":  # 떨어지는 별 둘
			return [
				[Icons._star(Vector2(0.06, -0.06), 0.36, 0.15, 5), Color(1.0, 0.88, 0.32), true],
				[Icons._star(Vector2(-0.28, 0.28), 0.16, 0.07, 5), Color(1.0, 0.94, 0.62), true],
				[[Vector2(0.06, -0.42), Vector2(0.06, -0.06), Vector2(-0.28, -0.18)], Color(1.0, 0.96, 0.70), false],
			]
		"comet":  # 혜성: 하늘색 머리 + 왼 위로 긴 꼬리
			return [
				[[Vector2(-0.46, -0.46), Vector2(0.20, 0.0), Vector2(0.0, 0.20)], Color(0.70, 0.90, 1.0, 0.85), true],
				[[Vector2(-0.30, -0.42), Vector2(0.18, -0.02), Vector2(0.06, 0.04)], Color(0.92, 0.98, 1.0), false],
				[_ngon(8, 0.20, 0.3).map(func(p): return p + Vector2(0.18, 0.18)), Color(0.80, 0.94, 1.0), true],
				[_ngon(6, 0.08, 0.0).map(func(p): return p + Vector2(0.14, 0.14)), Color(1, 1, 1), false],
			]
		"cross":  # 치유 십자: 흰 테 녹색 십자
			var c := [Vector2(-0.13, -0.42), Vector2(0.13, -0.42), Vector2(0.13, -0.13), Vector2(0.42, -0.13), Vector2(0.42, 0.13),
				Vector2(0.13, 0.13), Vector2(0.13, 0.42), Vector2(-0.13, 0.42), Vector2(-0.13, 0.13), Vector2(-0.42, 0.13),
				Vector2(-0.42, -0.13), Vector2(-0.13, -0.13)]
			return [
				[c, Color(0.98, 0.98, 0.92), true],
				[c.map(func(p): return p * 0.62), Color(0.40, 0.84, 0.46), false],
			]
		"eye":  # 저주의 눈: 아몬드 + 보라 눈동자
			return [
				[[Vector2(-0.46, 0.0), Vector2(-0.20, -0.22), Vector2(0.20, -0.22), Vector2(0.46, 0.0), Vector2(0.20, 0.22), Vector2(-0.20, 0.22)],
					Color(0.96, 0.92, 0.98), true],
				[_ngon(8, 0.17, 0.0), Color(0.80, 0.30, 0.86), true],
				[_ngon(6, 0.07, 0.0), Color(0.12, 0.06, 0.16), false],
				[_ngon(4, 0.03, 0.0).map(func(p): return p + Vector2(-0.06, -0.06)), Color(1, 1, 1), false],
			]
		"moon":  # 초승달
			var arc := []
			for i in 11:
				arc.append(Vector2.from_angle(PI * 0.32 + PI * 1.36 * i / 10.0) * 0.42)
			for i in 11:
				arc.append(Vector2.from_angle(PI * 1.62 - PI * 1.24 * i / 10.0) * 0.34 + Vector2(0.16, 0.0))
			return [[arc, Color(0.96, 0.92, 0.70), true]]
		"drop":  # 핏방울
			var d := [Vector2(0.0, -0.46), Vector2(0.18, -0.16), Vector2(0.30, 0.10), Vector2(0.26, 0.30), Vector2(0.10, 0.42),
				Vector2(-0.10, 0.42), Vector2(-0.26, 0.30), Vector2(-0.30, 0.10), Vector2(-0.18, -0.16)]
			return [
				[d, Color(0.92, 0.18, 0.22), true],
				[[Vector2(0.0, -0.46), Vector2(-0.18, -0.16), Vector2(-0.30, 0.10), Vector2(-0.26, 0.30), Vector2(-0.10, 0.10)], Color(1.0, 0.40, 0.40), false],
				[[Vector2(-0.18, 0.06), Vector2(-0.12, -0.04), Vector2(-0.08, 0.10), Vector2(-0.14, 0.18)], Color(1.0, 0.86, 0.86), false],
			]
		"claw":  # 할퀸 자국 셋
			var out := []
			for i in 3:
				var x := -0.24 + i * 0.22
				out.append([[Vector2(x + 0.12, -0.44), Vector2(x + 0.06, -0.40), Vector2(x - 0.12, 0.40), Vector2(x - 0.04, 0.44)],
					Color(0.98, 0.92, 0.86), true])
			return out
		"arrow":  # 화살 하나(오른 위)
			var a := Vector2(-0.42, 0.42)
			var b := Vector2(0.42, -0.42)
			return [
				[Icons._ax(a, b, [Vector2(0.0, 0.03), Vector2(0.92, 0.03), Vector2(0.92, -0.03), Vector2(0.0, -0.03)]), Color(0.86, 0.66, 0.40), true],
				[Icons._ax(a, b, [Vector2(0.88, 0.10), Vector2(1.19, 0.0), Vector2(0.88, -0.10)]), Color(0.86, 0.90, 0.96), true],
				[Icons._ax(a, b, [Vector2(0.0, 0.03), Vector2(0.10, 0.13), Vector2(0.26, 0.13), Vector2(0.18, 0.03)]), Color(0.96, 0.96, 0.96), true],
				[Icons._ax(a, b, [Vector2(0.0, -0.03), Vector2(0.10, -0.13), Vector2(0.26, -0.13), Vector2(0.18, -0.03)]), Color(0.86, 0.86, 0.86), true],
			]
		"arrows":  # 쏟아지는 화살 셋(아래로)
			var out := []
			for s in [[-0.24, -0.06], [0.0, 0.10], [0.24, -0.10]]:
				var x: float = s[0]
				var y: float = s[1]
				out.append([_quad(Vector2(x, y - 0.32), Vector2(x, y + 0.22), 0.025), Color(0.86, 0.66, 0.40), true])
				out.append([[Vector2(x - 0.08, y + 0.18), Vector2(x + 0.08, y + 0.18), Vector2(x, y + 0.36)], Color(0.86, 0.90, 0.96), true])
				out.append([[Vector2(x - 0.07, y - 0.40), Vector2(x, y - 0.30), Vector2(x + 0.07, y - 0.40), Vector2(x, y - 0.22)], Color(0.96, 0.96, 0.96), true])
			return out
		"spear":  # 창: 긴 자루 + 넓은 촉
			var a := Vector2(-0.44, 0.44)
			var b := Vector2(0.44, -0.44)
			return [
				[Icons._ax(a, b, [Vector2(0.0, 0.035), Vector2(0.86, 0.035), Vector2(0.86, -0.035), Vector2(0.0, -0.035)]), Color(0.76, 0.55, 0.33), true],
				[Icons._ax(a, b, [Vector2(0.80, 0.11), Vector2(0.92, 0.11), Vector2(1.22, 0.0), Vector2(0.92, -0.11), Vector2(0.80, -0.11)]), Color(0.80, 0.84, 0.90), true],
				[Icons._ax(a, b, [Vector2(0.80, 0.11), Vector2(0.92, 0.11), Vector2(1.22, 0.0), Vector2(0.80, 0.0)]), Color(0.94, 0.96, 0.98), false],
				[Icons._ax(a, b, [Vector2(0.74, 0.06), Vector2(0.80, 0.06), Vector2(0.80, -0.06), Vector2(0.74, -0.06)]), Color(0.95, 0.74, 0.22), true],
			]
		"shield":  # 둥근 윗변 방패: 쇠 테 + 파란 면 + 금 가로띠
			var rim := [Vector2(-0.40, -0.40), Vector2(0.40, -0.40), Vector2(0.40, 0.04), Vector2(0.26, 0.28), Vector2(0.0, 0.46),
				Vector2(-0.26, 0.28), Vector2(-0.40, 0.04)]
			var face: Array = rim.map(func(p): return p * 0.82)
			return [
				[rim, Color(0.80, 0.84, 0.90), true],
				[face, Color(0.30, 0.44, 0.72), true],
				[[face[0], Vector2(0.0, face[0].y), Vector2(0.0, face[4].y), face[5], face[6]], Color(0.42, 0.58, 0.86), false],
				[_quad(Vector2(0.0, -0.30), Vector2(0.0, 0.34), 0.05), Color(0.95, 0.74, 0.22), false],
				[_quad(Vector2(-0.30, -0.06), Vector2(0.30, -0.06), 0.05), Color(0.95, 0.74, 0.22), false],
			]
		"note":  # 음표 둘(찬가)
			var w := Color(0.98, 0.96, 0.88)
			return [
				[_quad(Vector2(-0.12, -0.32), Vector2(-0.12, 0.24), 0.035), w, true],
				[_quad(Vector2(0.28, -0.40), Vector2(0.28, 0.16), 0.035), w, true],
				[[Vector2(-0.15, -0.34), Vector2(0.31, -0.42), Vector2(0.31, -0.26), Vector2(-0.15, -0.18)], w, true],
				[_ngon(8, 0.13, 0.3).map(func(p): return Vector2(p.x * 1.25, p.y) + Vector2(-0.24, 0.28)), w, true],
				[_ngon(8, 0.13, 0.3).map(func(p): return Vector2(p.x * 1.25, p.y) + Vector2(0.16, 0.20)), w, true],
			]
		"paw":  # 발자국: 큰 볼 + 발가락 넷
			var c := Color(0.96, 0.92, 0.84)
			var out := [[_ngon(7, 0.20, 0.0).map(func(p): return Vector2(p.x * 1.15, p.y) + Vector2(0.0, 0.18)), c, true]]
			for s in [Vector2(-0.30, -0.06), Vector2(-0.12, -0.28), Vector2(0.12, -0.28), Vector2(0.30, -0.06)]:
				out.append([_ngon(6, 0.10, 0.0).map(func(p): return p + s), c, true])
			return out
		"skull":  # 해골
			var c := Color(0.96, 0.94, 0.88)
			return [
				[[Vector2(-0.34, -0.10), Vector2(-0.26, -0.36), Vector2(0.0, -0.44), Vector2(0.26, -0.36), Vector2(0.34, -0.10),
					Vector2(0.26, 0.14), Vector2(0.18, 0.18), Vector2(0.18, 0.38), Vector2(-0.18, 0.38), Vector2(-0.18, 0.18), Vector2(-0.26, 0.14)], c, true],
				[_ngon(6, 0.10, 0.0).map(func(p): return p + Vector2(-0.14, -0.08)), Color(0.14, 0.10, 0.12), false],
				[_ngon(6, 0.10, 0.0).map(func(p): return p + Vector2(0.14, -0.08)), Color(0.14, 0.10, 0.12), false],
				[[Vector2(0.0, 0.04), Vector2(0.05, 0.14), Vector2(-0.05, 0.14)], Color(0.14, 0.10, 0.12), false],
				[_quad(Vector2(-0.06, 0.24), Vector2(-0.06, 0.38), 0.012), Color(0.40, 0.36, 0.34), false],
				[_quad(Vector2(0.06, 0.24), Vector2(0.06, 0.38), 0.012), Color(0.40, 0.36, 0.34), false],
			]
		"tree":  # 나무 정령: 갈색 줄기 + 각진 잎 덩어리
			return [
				[[Vector2(-0.08, 0.10), Vector2(0.08, 0.10), Vector2(0.12, 0.44), Vector2(-0.12, 0.44)], Color(0.56, 0.38, 0.20), true],
				[[Vector2(0.0, -0.46), Vector2(0.36, -0.10), Vector2(0.30, 0.16), Vector2(-0.30, 0.16), Vector2(-0.36, -0.10)], Color(0.40, 0.70, 0.30), true],
				[[Vector2(0.0, -0.46), Vector2(-0.36, -0.10), Vector2(-0.30, 0.16), Vector2(0.0, 0.0)], Color(0.54, 0.84, 0.38), false],
			]
		"bird":  # 날개 편 새(정면)
			var c := Color(1.0, 0.88, 0.40)
			return [
				[[Vector2(0.0, -0.10), Vector2(-0.20, -0.30), Vector2(-0.46, -0.30), Vector2(-0.30, -0.16), Vector2(-0.40, -0.12), Vector2(-0.16, 0.04)], c, true],
				[[Vector2(0.0, -0.10), Vector2(0.20, -0.30), Vector2(0.46, -0.30), Vector2(0.30, -0.16), Vector2(0.40, -0.12), Vector2(0.16, 0.04)], c.darkened(0.12), true],
				[[Vector2(-0.10, -0.16), Vector2(0.10, -0.16), Vector2(0.12, 0.16), Vector2(0.0, 0.26), Vector2(-0.12, 0.16)], Color(1.0, 0.62, 0.22), true],
				[[Vector2(-0.12, 0.20), Vector2(0.0, 0.44), Vector2(0.12, 0.20)], Color(1.0, 0.46, 0.18), true],
				[_ngon(6, 0.10, 0.0).map(func(p): return p + Vector2(0.0, -0.24)), Color(1.0, 0.62, 0.22), true],
			]
	return Icons.shapes(glyph)


static func _ngon(n: int, r: float, rot: float) -> Array:
	return Icons._ngon(n, r, rot)


static func _quad(from: Vector2, to: Vector2, half_w: float) -> Array:
	return Icons._quad(from, to, half_w)

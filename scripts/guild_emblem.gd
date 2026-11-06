extends RefCounted
## 길드 문양(2026-11-05, 사용자 "길드 문양은 길드장이 만들 수 있게해, 배경 모양 + 가운데 문양 + 배경 색 + 가운데 문양 색 조합으로, 퀄리티 높여서"):
## 라이즈 오브 킹덤즈 연맹 깃발(모양·문양·색 조합), 로드 모바일 길드 배지, 클래시 오브 클랜 배지 편집기처럼 네 가지를 골라 만든다.
## 그림은 각진 로우폴리 평면(외곽선 없음, 금색 없음): 테두리 띠(어두운 배경색, 왼쪽 위 밝은 면) → 문양색 장식 띠 → 면을 나눈 바탕 → 그림자 진 문양(오른쪽 면 어둡게).
##
## 값 하나(int)로 저장한다(서버 guilds.emblem, server/src/guild.ts EMBLEM_*와 같은 식):
##   0..7  = 예전 문장(방패, 문양 i, 배경색 LEGACY_BG[i], 문양색 상아) — 이미 만든 길드는 그대로 보인다.
##   8 이상 = 8 + 모양 + SHAPES × (문양 + SYMBOLS × (배경색 + BG.size() × 문양색)).

const LEGACY := 8
const SHAPES := 8
const SYMBOLS := 20

## 배경 색 12가지(금색·노랑 없음).
const BG := [Color(0.72, 0.16, 0.18), Color(0.86, 0.44, 0.14), Color(0.18, 0.48, 0.26), Color(0.12, 0.48, 0.52),
	Color(0.24, 0.55, 0.82), Color(0.16, 0.24, 0.52), Color(0.42, 0.24, 0.62), Color(0.60, 0.17, 0.40),
	Color(0.86, 0.45, 0.60), Color(0.46, 0.29, 0.18), Color(0.42, 0.45, 0.50), Color(0.15, 0.16, 0.20)]
## 문양 색 10가지(금색 없음).
const FG := [Color(0.97, 0.97, 0.95), Color(0.95, 0.89, 0.76), Color(0.74, 0.78, 0.84), Color(0.16, 0.17, 0.20),
	Color(0.88, 0.24, 0.22), Color(0.26, 0.48, 0.88), Color(0.32, 0.72, 0.38), Color(0.64, 0.42, 0.88),
	Color(0.52, 0.84, 0.96), Color(0.98, 0.58, 0.22)]
## 예전 문장 0..7의 배경색(빨강·파랑·초록·보라·주황·청록·회색·분홍).
const LEGACY_BG := [0, 4, 2, 6, 1, 3, 10, 8]
## 무작위 문양(추천·상대 길드)이 고르는 문양색: 흰색·상아·은색·검정. 어두운 배경에 검정이면 흰색.
const DARK_BG := [5, 9, 11]


static func count() -> int:
	return LEGACY + SHAPES * SYMBOLS * BG.size() * FG.size()


static func encode(shape: int, symbol: int, bg: int, fg: int) -> int:
	return LEGACY + posmod(shape, SHAPES) + SHAPES * (posmod(symbol, SYMBOLS) + SYMBOLS * (posmod(bg, BG.size()) + BG.size() * posmod(fg, FG.size())))


## {shape, symbol, bg, fg}. 범위 밖 값은 예전 문장 0으로.
static func decode(v: int) -> Dictionary:
	if v < 0 or v >= count():
		v = 0
	if v < LEGACY:
		return {"shape": 0, "symbol": v, "bg": LEGACY_BG[v], "fg": 1}
	var n := v - LEGACY
	var shape := n % SHAPES
	n /= SHAPES
	var symbol := n % SYMBOLS
	n /= SYMBOLS
	var bg := n % BG.size()
	return {"shape": shape, "symbol": symbol, "bg": bg, "fg": n / BG.size()}


## 수 하나(0 이상)로 정해지는 무작위 문양 — 서버 randomEmblem과 같은 식.
static func from_seed(n: int) -> int:
	n = absi(n)
	var bg := (n / (SHAPES * SYMBOLS)) % BG.size()
	var fg := (n / (SHAPES * SYMBOLS * BG.size())) % 4
	if fg == 3 and bg in DARK_BG:
		fg = 0
	return encode(n % SHAPES, (n / SHAPES) % SYMBOLS, bg, fg)


# --- 그리기 ---

## 문양 v를 c 가운데, 한 변 size 칸에 그린다.
static func draw(ci: CanvasItem, c: Vector2, size: float, v: int) -> void:
	var d := decode(v)
	draw_parts(ci, c, size, int(d.shape), int(d.symbol), BG[int(d.bg)], FG[int(d.fg)])


## 모양·문양 번호와 색으로 그린다(편집기 미리보기는 symbol -1이면 문양 없이).
static func draw_parts(ci: CanvasItem, c: Vector2, size: float, shape: int, symbol: int, bg: Color, fg: Color) -> void:
	var s := size / 2.0
	var outer := _place(shape_poly(shape), c, s)
	# 바닥 그림자(살짝 아래)
	ci.draw_colored_polygon(_place(shape_poly(shape), c + Vector2(0, s * 0.06), s), Color(0, 0, 0, 0.22))
	# 테두리 띠: 어두운 배경색, 왼쪽 위 반은 밝은 면
	var rim := bg.darkened(0.42)
	ci.draw_colored_polygon(outer, rim)
	_fill_clip(ci, outer, _half(c, s, Vector2(-1, -1)), rim.lightened(0.22))
	# 장식 띠(문양색과 배경색 사이)
	var trim := fg.lerp(bg, 0.35)
	var band := _place(shape_poly(shape), c, s * 0.86)
	ci.draw_colored_polygon(band, trim.darkened(0.12))
	_fill_clip(ci, band, _half(c, s, Vector2(-1, -1)), trim.lightened(0.08))
	# 바탕: 네 면(왼쪽 위 밝게, 오른쪽 아래 어둡게) — 보석처럼 깎인 면
	var field := _place(shape_poly(shape), c, s * 0.78)
	ci.draw_colored_polygon(field, bg)
	_fill_clip(ci, field, _quad(c, s, -1, -1), bg.lightened(0.16))
	_fill_clip(ci, field, _quad(c, s, 1, -1), bg.lightened(0.06))
	_fill_clip(ci, field, _quad(c, s, 1, 1), bg.darkened(0.14))
	# 가운데 위 빛줄기(얇은 밝은 쐐기)
	_fill_clip(ci, field, PackedVector2Array([c + Vector2(-0.55, -1.2) * s, c + Vector2(-0.30, -1.2) * s, c + Vector2(0.10, 1.2) * s,
		c + Vector2(-0.15, 1.2) * s]), Color(1, 1, 1, 0.07))
	if symbol < 0:
		return
	var sc := s * 0.6 * shape_symbol_scale(shape)
	var sym_c := c + Vector2(0, s * shape_symbol_dy(shape))
	var parts: Array = symbol_parts(symbol)
	var shade := bg.darkened(0.5)
	shade.a = 0.55
	for p in parts:  # 문양 그림자(오른쪽 아래)
		ci.draw_colored_polygon(_place(p.poly, sym_c + Vector2(0.05, 0.07) * sc, sc), shade)
	var accent := fg.lerp(bg, 0.6).darkened(0.1)
	for p in parts:
		var poly := _place(p.poly, sym_c, sc)
		var col: Color = accent if p.accent else fg
		ci.draw_colored_polygon(poly, col)
		if not p.accent:  # 오른쪽 면은 어둡게(로우폴리 면)
			_fill_clip(ci, poly, _half(sym_c, sc * 2.0, Vector2(1, 0)), col.darkened(0.16))
			_fill_clip(ci, poly, _quad(sym_c, sc * 2.0, -1, -1), col.lightened(0.10))


static func _place(poly: PackedVector2Array, c: Vector2, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(poly.size())
	for k in poly.size():
		out[k] = c + poly[k] * s
	return out


## a ∩ b를 col로(겹치는 조각이 여럿이면 모두).
static func _fill_clip(ci: CanvasItem, a: PackedVector2Array, b: PackedVector2Array, col: Color) -> void:
	for piece in Geometry2D.intersect_polygons(a, b):
		if piece.size() >= 3:
			ci.draw_colored_polygon(piece, col)


## c를 지나는 대각선(dir 쪽) 반 평면을 덮는 큰 사각형. dir (-1,-1)이면 왼쪽 위, (1,0)이면 오른쪽 반.
static func _half(c: Vector2, s: float, dir: Vector2) -> PackedVector2Array:
	var n := dir.normalized()
	var t := Vector2(-n.y, n.x)
	var r := s * 4.0
	return PackedVector2Array([c + t * r, c + t * r + n * r, c - t * r + n * r, c - t * r])


## c에서 (sx, sy) 쪽 사분면.
static func _quad(c: Vector2, s: float, sx: int, sy: int) -> PackedVector2Array:
	var r := s * 4.0
	return PackedVector2Array([c, c + Vector2(sx * r, 0), c + Vector2(sx * r, sy * r), c + Vector2(0, sy * r)])


# --- 배경 모양(단위 좌표, 대략 -1..1) ---

const SHAPE_NAMES := ["heater", "kite", "round", "hexagon", "banner", "diamond", "octagon", "sun"]


static func shape_poly(i: int) -> PackedVector2Array:
	match posmod(i, SHAPES):
		0:  # 방패(아래가 둥글게 모이는 기사 방패)
			return PackedVector2Array([Vector2(-0.84, -0.88), Vector2(0, -0.80), Vector2(0.84, -0.88), Vector2(0.84, 0.10), Vector2(0.66, 0.52),
				Vector2(0.34, 0.80), Vector2(0, 0.96), Vector2(-0.34, 0.80), Vector2(-0.66, 0.52), Vector2(-0.84, 0.10)])
		1:  # 연(카이트) 방패: 둥근 위, 길게 뾰족한 아래
			var p := PackedVector2Array()
			for k in 7:
				var a := PI + k * PI / 6.0
				p.append(Vector2(cos(a) * 0.80, -0.42 + sin(a) * 0.54))
			p.append(Vector2(0.62, 0.20))
			p.append(Vector2(0, 0.98))
			p.append(Vector2(-0.62, 0.20))
			return p
		2:  # 원형
			return _ngon(14, 0.92, 0.0)
		3:  # 육각
			return _ngon(6, 0.95, 0.0)
		4:  # 깃발(제비꼬리 배너)
			return PackedVector2Array([Vector2(-0.76, -0.92), Vector2(0.76, -0.92), Vector2(0.76, 0.96), Vector2(0, 0.56), Vector2(-0.76, 0.96)])
		5:  # 마름모
			return PackedVector2Array([Vector2(0, -0.98), Vector2(0.86, 0), Vector2(0, 0.98), Vector2(-0.86, 0)])
		6:  # 팔각
			return _ngon(8, 0.94, PI / 8.0)
		_:  # 해 문장(톱니 16개)
			var p := PackedVector2Array()
			for k in 24:
				var r := 0.98 if k % 2 == 0 else 0.82
				var a := -PI / 2.0 + k * TAU / 24.0
				p.append(Vector2(cos(a), sin(a)) * r)
			return p


## 모양마다 문양이 들어갈 크기·높이(뾰족한 아래가 있는 모양은 문양을 조금 위로·작게).
static func shape_symbol_scale(i: int) -> float:
	return [0.95, 0.85, 1.0, 0.95, 0.9, 0.78, 1.0, 0.92][posmod(i, SHAPES)]


static func shape_symbol_dy(i: int) -> float:
	return [-0.02, -0.08, 0.0, 0.0, -0.08, 0.0, 0.0, 0.0][posmod(i, SHAPES)]


static func _ngon(n: int, r: float, rot: float, c := Vector2.ZERO, ry := -1.0) -> PackedVector2Array:
	var p := PackedVector2Array()
	for k in n:
		var a := -PI / 2.0 + rot + k * TAU / n
		p.append(c + Vector2(cos(a) * r, sin(a) * (r if ry < 0.0 else ry)))
	return p


# --- 가운데 문양(단위 좌표, 대략 -1..1) ---

const SYMBOL_NAMES := ["star", "sword", "crown", "tree", "moon", "flame", "tower", "heart", "swords", "axe",
	"hammer", "bolt", "wings", "sun", "lily", "skull", "wolf", "dragon", "eagle", "gem"]

static var _cache := {}


## 문양 조각들 [{poly, accent}] — accent면 문양색과 배경색 사이 색(눈·창문 같은 안쪽 무늬).
static func symbol_parts(i: int) -> Array:
	i = posmod(i, SYMBOLS)
	if not _cache.has(i):
		_cache[i] = _make_symbol(i)
	return _cache[i]


static func _P(pts: Array) -> PackedVector2Array:
	return PackedVector2Array(pts)


static func _rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


static func _rot(poly: PackedVector2Array, a: float, pivot := Vector2.ZERO) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in poly:
		out.append(pivot + (v - pivot).rotated(a))
	return out


static func _mirror(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in range(poly.size() - 1, -1, -1):
		out.append(Vector2(-poly[k].x, poly[k].y))
	return out


static func _sub(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	for piece in Geometry2D.clip_polygons(a, b):
		if not Geometry2D.is_polygon_clockwise(piece) == Geometry2D.is_polygon_clockwise(a):
			continue
		return piece
	return a


static func _sword(len_up: float) -> Array:
	return [_P([Vector2(0, -len_up), Vector2(0.19, -len_up + 0.24), Vector2(0.19, 0.28), Vector2(-0.19, 0.28), Vector2(-0.19, -len_up + 0.24)]),
		_P([Vector2(-0.56, 0.24), Vector2(0.56, 0.24), Vector2(0.48, 0.44), Vector2(-0.48, 0.44)]), _rect(-0.11, 0.44, 0.11, 0.78), _ngon(4, 0.17, 0.0, Vector2(0, 0.86))]


static func _make_symbol(i: int) -> Array:
	var solid: Array = []
	var accent: Array = []
	match i:
		0:  # 별
			var p := PackedVector2Array()
			for k in 10:
				var r := 0.98 if k % 2 == 0 else 0.42
				var a := -PI / 2.0 + k * PI / 5.0
				p.append(Vector2(cos(a), sin(a)) * r + Vector2(0, 0.06))
			solid = [p]
		1:  # 검
			solid = _sword(0.98)
			accent = [_P([Vector2(0, -0.68), Vector2(0.05, -0.58), Vector2(0.05, 0.18), Vector2(-0.05, 0.18), Vector2(-0.05, -0.58)])]
		2:  # 왕관
			solid = [_P([Vector2(-0.82, 0.42), Vector2(-0.86, -0.46), Vector2(-0.44, -0.06), Vector2(0, -0.72), Vector2(0.44, -0.06),
				Vector2(0.86, -0.46), Vector2(0.82, 0.42)]), _rect(-0.84, 0.50, 0.84, 0.72),
				_ngon(4, 0.14, 0.0, Vector2(-0.86, -0.58)), _ngon(4, 0.14, 0.0, Vector2(0, -0.86)), _ngon(4, 0.14, 0.0, Vector2(0.86, -0.58))]
			accent = [_ngon(4, 0.12, 0.0, Vector2(0, 0.14)), _ngon(4, 0.09, 0.0, Vector2(-0.46, 0.20)), _ngon(4, 0.09, 0.0, Vector2(0.46, 0.20))]
		3:  # 나무(전나무)
			solid = [_P([Vector2(0, -0.98), Vector2(0.46, -0.40), Vector2(-0.46, -0.40)]),
				_P([Vector2(0, -0.62), Vector2(0.66, 0.06), Vector2(-0.66, 0.06)]),
				_P([Vector2(0, -0.22), Vector2(0.86, 0.56), Vector2(-0.86, 0.56)]), _rect(-0.14, 0.56, 0.14, 0.94)]
		4:  # 초승달 + 작은 별
			var moon := _sub(_ngon(18, 0.86, 0.0, Vector2(-0.08, 0.04)), _ngon(18, 0.72, 0.0, Vector2(0.30, -0.12)))
			var star := PackedVector2Array()
			for k in 8:
				var r := 0.26 if k % 2 == 0 else 0.09
				var a := -PI / 2.0 + k * PI / 4.0
				star.append(Vector2(0.52, 0.18) + Vector2(cos(a), sin(a)) * r)
			solid = [moon, star]
		5:  # 불꽃(안쪽 불꽃은 밝은 무늬)
			solid = [_P([Vector2(0, -1.0), Vector2(0.22, -0.56), Vector2(0.50, -0.42), Vector2(0.46, -0.66), Vector2(0.74, -0.24),
				Vector2(0.76, 0.30), Vector2(0.46, 0.76), Vector2(0, 0.94), Vector2(-0.46, 0.76), Vector2(-0.76, 0.30), Vector2(-0.70, -0.20),
				Vector2(-0.44, -0.04), Vector2(-0.36, -0.52)])]
			accent = [_P([Vector2(0.04, -0.20), Vector2(0.30, 0.18), Vector2(0.34, 0.50), Vector2(0, 0.74), Vector2(-0.34, 0.50),
				Vector2(-0.28, 0.20), Vector2(-0.12, 0.30)])]
		6:  # 성탑
			solid = [_P([Vector2(-0.62, 0.94), Vector2(-0.52, -0.40), Vector2(0.52, -0.40), Vector2(0.62, 0.94)]),
				_P([Vector2(-0.74, -0.40), Vector2(-0.74, -0.86), Vector2(-0.44, -0.86), Vector2(-0.44, -0.66), Vector2(-0.15, -0.66),
					Vector2(-0.15, -0.86), Vector2(0.15, -0.86), Vector2(0.15, -0.66), Vector2(0.44, -0.66), Vector2(0.44, -0.86),
					Vector2(0.74, -0.86), Vector2(0.74, -0.40)])]
			var gate := PackedVector2Array([Vector2(-0.24, 0.94), Vector2(-0.24, 0.46)])
			for k in 5:
				var a := PI + k * PI / 4.0
				gate.append(Vector2(0, 0.46) + Vector2(cos(a), sin(a)) * 0.24)
			gate.append(Vector2(0.24, 0.94))
			accent = [gate, _rect(-0.08, -0.20, 0.08, 0.14)]
		7:  # 하트
			solid = [_heart()]
		8:  # 교차한 두 검
			for a in [-0.70, 0.70]:
				for p in _sword(0.98):
					solid.append(_rot(_place(p, Vector2(0, -0.02), 0.88), a, Vector2(0, 0.0)))
		9:  # 양날 도끼
			var bit := _P([Vector2(0.08, -0.52), Vector2(0.52, -0.84), Vector2(0.86, -0.74), Vector2(0.72, -0.24), Vector2(0.86, 0.24),
				Vector2(0.52, 0.34), Vector2(0.08, 0.02)])
			solid = [_rect(-0.10, -0.80, 0.10, 0.98), bit, _mirror(bit), _ngon(4, 0.16, 0.0, Vector2(0, -0.86), 0.18)]
		10:  # 전투 망치
			solid = [_P([Vector2(-0.80, -0.86), Vector2(0.80, -0.86), Vector2(0.90, -0.74), Vector2(0.90, -0.10), Vector2(0.80, 0.02),
				Vector2(-0.80, 0.02), Vector2(-0.90, -0.10), Vector2(-0.90, -0.74)]), _rect(-0.13, 0.02, 0.13, 0.98)]
			accent = [_rect(-0.64, -0.50, -0.50, -0.36), _rect(0.50, -0.50, 0.64, -0.36), _rect(-0.13, 0.62, 0.13, 0.70), _rect(-0.13, 0.80, 0.13, 0.88)]
		11:  # 번개
			solid = [_P([Vector2(0.18, -1.0), Vector2(0.62, -1.0), Vector2(0.24, -0.20), Vector2(0.62, -0.20), Vector2(-0.30, 1.0),
				Vector2(-0.02, 0.10), Vector2(-0.44, 0.10)])]
		12:  # 날개(깃털 세 겹 × 양쪽)
			var wing: Array = []
			wing.append(_P([Vector2(0.08, -0.30), Vector2(0.50, -0.80), Vector2(0.98, -0.86), Vector2(0.80, -0.56), Vector2(0.26, -0.04)]))
			wing.append(_P([Vector2(0.10, -0.06), Vector2(0.58, -0.40), Vector2(0.92, -0.38), Vector2(0.72, -0.12), Vector2(0.20, 0.20)]))
			wing.append(_P([Vector2(0.12, 0.18), Vector2(0.52, 0.00), Vector2(0.80, 0.06), Vector2(0.56, 0.30), Vector2(0.16, 0.42)]))
			wing.append(_P([Vector2(0.10, 0.40), Vector2(0.40, 0.36), Vector2(0.58, 0.48), Vector2(0.34, 0.64), Vector2(0.10, 0.62)]))
			for w in wing:
				solid.append(w)
				solid.append(_mirror(w))
			solid.append(_ngon(6, 0.16, 0.0, Vector2(0, 0.18), 0.40))
		13:  # 해
			solid = [_ngon(12, 0.44, 0.0)]
			for k in 8:
				var a := k * TAU / 8.0
				var dir := Vector2(cos(a), sin(a))
				var side := Vector2(-dir.y, dir.x)
				var r1 := 0.56
				var r2 := 0.98 if k % 2 == 0 else 0.80
				solid.append(_P([dir * r1 + side * 0.14, dir * r2, dir * r1 - side * 0.14]))
		14:  # 백합 문장
			solid = [_P([Vector2(0, -0.98), Vector2(0.22, -0.60), Vector2(0.22, -0.10), Vector2(0.12, 0.20), Vector2(-0.12, 0.20),
				Vector2(-0.22, -0.10), Vector2(-0.22, -0.60)])]
			var petal := _P([Vector2(0.16, 0.16), Vector2(0.36, -0.30), Vector2(0.70, -0.46), Vector2(0.88, -0.24), Vector2(0.74, 0.02),
				Vector2(0.56, -0.12), Vector2(0.44, 0.06), Vector2(0.30, 0.28)])
			solid.append(petal)
			solid.append(_mirror(petal))
			solid.append(_rect(-0.56, 0.22, 0.56, 0.38))
			solid.append(_P([Vector2(-0.12, 0.38), Vector2(0.12, 0.38), Vector2(0.30, 0.86), Vector2(0, 0.66), Vector2(-0.30, 0.86)]))
		15:  # 해골
			var head := _ngon(12, 0.76, 0.0, Vector2(0, -0.18), 0.68)
			solid = [head, _P([Vector2(-0.44, 0.30), Vector2(0.44, 0.30), Vector2(0.38, 0.82), Vector2(-0.38, 0.82)])]
			accent = [_ngon(6, 0.20, 0.0, Vector2(-0.30, -0.12), 0.22), _ngon(6, 0.20, 0.0, Vector2(0.30, -0.12), 0.22),
				_P([Vector2(0, 0.14), Vector2(0.10, 0.32), Vector2(-0.10, 0.32)]),
				_rect(-0.22, 0.56, -0.12, 0.82), _rect(-0.05, 0.56, 0.05, 0.82), _rect(0.12, 0.56, 0.22, 0.82)]
		16:  # 늑대 머리(앞모습)
			solid = [_P([Vector2(-0.74, -0.96), Vector2(-0.30, -0.52), Vector2(0.30, -0.52), Vector2(0.74, -0.96), Vector2(0.78, -0.24),
				Vector2(0.96, 0.10), Vector2(0.56, 0.24), Vector2(0.30, 0.66), Vector2(0, 0.96), Vector2(-0.30, 0.66), Vector2(-0.56, 0.24),
				Vector2(-0.96, 0.10), Vector2(-0.78, -0.24)])]
			accent = [_P([Vector2(-0.56, -0.70), Vector2(-0.38, -0.50), Vector2(-0.60, -0.36)]), _P([Vector2(0.56, -0.70), Vector2(0.60, -0.36), Vector2(0.38, -0.50)]),
				_P([Vector2(-0.48, -0.16), Vector2(-0.16, -0.06), Vector2(-0.40, 0.02)]), _P([Vector2(0.48, -0.16), Vector2(0.40, 0.02), Vector2(0.16, -0.06)]),
				_P([Vector2(-0.16, 0.52), Vector2(0.16, 0.52), Vector2(0, 0.70)])]
		17:  # 용 머리(옆모습, 오른쪽을 본다 — 뒤로 뻗은 뿔 둘, 벌린 입)
			solid = [_P([Vector2(-0.80, 0.98), Vector2(-0.86, 0.30), Vector2(-0.70, -0.20), Vector2(-0.98, -0.70), Vector2(-0.48, -0.42),
				Vector2(-0.60, -0.98), Vector2(-0.22, -0.52), Vector2(0.30, -0.46), Vector2(0.96, -0.18), Vector2(0.94, -0.04),
				Vector2(0.36, 0.02), Vector2(0.86, 0.24), Vector2(0.70, 0.36), Vector2(0.10, 0.34), Vector2(-0.20, 0.56), Vector2(-0.30, 0.98)])]
			accent = [_P([Vector2(-0.04, -0.36), Vector2(0.24, -0.32), Vector2(0.02, -0.22)]),
				_P([Vector2(-0.66, 0.16), Vector2(-0.46, -0.04), Vector2(-0.42, 0.26)]), _P([Vector2(-0.62, 0.58), Vector2(-0.42, 0.40), Vector2(-0.40, 0.70)])]
		18:  # 독수리(날개 편)
			var wing := _P([Vector2(0.12, -0.24), Vector2(0.50, -0.70), Vector2(0.98, -0.60), Vector2(0.80, -0.40), Vector2(0.92, -0.24),
				Vector2(0.70, -0.10), Vector2(0.78, 0.06), Vector2(0.50, 0.10), Vector2(0.20, 0.20)])
			solid = [wing, _mirror(wing), _P([Vector2(-0.22, -0.30), Vector2(0.22, -0.30), Vector2(0.26, 0.40), Vector2(0, 0.56), Vector2(-0.26, 0.40)]),
				_P([Vector2(-0.24, 0.40), Vector2(0, 0.52), Vector2(0.24, 0.40), Vector2(0.36, 0.92), Vector2(0, 0.80), Vector2(-0.36, 0.92)]),
				_P([Vector2(-0.18, -0.40), Vector2(-0.10, -0.70), Vector2(0.14, -0.74), Vector2(0.38, -0.56), Vector2(0.14, -0.50), Vector2(0.16, -0.30)])]
			accent = [_ngon(4, 0.05, 0.0, Vector2(0.04, -0.60))]
		_:  # 보석(깎은 면)
			solid = [_P([Vector2(-0.56, -0.66), Vector2(0.56, -0.66), Vector2(0.92, -0.24), Vector2(0, 0.94), Vector2(-0.92, -0.24)])]
			accent = [_P([Vector2(-0.30, -0.24), Vector2(0.30, -0.24), Vector2(0, 0.62)]), _P([Vector2(-0.56, -0.66), Vector2(-0.30, -0.24), Vector2(-0.92, -0.24)]),
				_P([Vector2(0.56, -0.66), Vector2(0.92, -0.24), Vector2(0.30, -0.24)])]
	var out: Array = []
	for p in solid:
		out.append({"poly": p, "accent": false})
	for p in accent:
		out.append({"poly": p, "accent": true})
	return out


## 하트: 오른쪽 반(아래 꼭짓점 → 가운데 홈 → 둥근 위 → 옆)을 만들고 거울로 왼쪽을 붙인다.
static func _heart() -> PackedVector2Array:
	var right: Array = []
	for k in 8:
		var a := -PI + k * PI * 1.25 / 7.0
		right.append(Vector2(0.44, -0.30) + Vector2(cos(a), sin(a)) * 0.44)
	var p := PackedVector2Array([Vector2(0, 0.90), Vector2(-0.70, 0.12)])
	for k in range(right.size() - 1, -1, -1):  # 왼쪽 반(거울), 바깥 → 홈
		p.append(Vector2(-right[k].x, right[k].y))
	for k in range(1, right.size()):  # 오른쪽 반, 홈 → 바깥
		p.append(right[k])
	p.append(Vector2(0.70, 0.12))
	return p

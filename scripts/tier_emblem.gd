extends RefCounted
## PVP 티어 문양(사용자 2026-11-05 "브론즈, 실버 이런 티어 문양이 너무 멋없어"). 리그 오브 레전드·클래시 로얄 리그 엠블럼처럼
## 티어가 오를수록 장식이 하나씩 붙는다. 모두 코드로 그린 로우폴리 면(밝은 면·어두운 면), 외곽선 없음.
##  브론즈 = 방패 + 작은 보석 / 실버 = + 짧은 날개 / 골드 = + 긴 날개·위 뿔 장식 / 플래티넘 = + 아래 월계 잎
##  다이아몬드 = + 뒤 수정 조각 / 마스터 = + 왕관·큰 날개·보석 빛 / 챌린저 = + 무지개 빛살(최고 등급은 무지개 — 금색 테두리 쓰지 않는다)
## draw(ci, 티어 id, 가운데, 높이 s). 그리는 폭은 대략 s × 1.3(날개 포함).
## 2026-11-05 "지금도 구져 … 다른 게임좀 참고해" → 그림 문양(클래시 로얄·서머너즈 워 리그 배지 참고, 사용자가 B안 선택)을
## assets/ui/pvp/tiers/<티어>.png로 쓴다(dev/meshy/tier_icons.py로 자름). 그림이 없을 때만 아래 코드 문양을 그린다.

const PvpRules := preload("res://scripts/pvp_rules.gd")

const ORDER := ["bronze", "silver", "gold", "platinum", "diamond", "master", "challenger"]
const RAINBOW := [Color("FF5A5A"), Color("FFA640"), Color("FFE45C"), Color("6EE07A"), Color("58B8FF"), Color("8E7CFF"), Color("E070F0")]


static func level(tier_id: String) -> int:
	return maxi(0, ORDER.find(tier_id))


static var _tex := {}


static func texture(tier_id: String) -> Texture2D:
	if not _tex.has(tier_id):
		var path := "res://assets/ui/pvp/tiers/%s.png" % tier_id
		_tex[tier_id] = load(path) if tier_id in ORDER and ResourceLoader.exists(path) else null
	return _tex[tier_id]


static func draw(ci: CanvasItem, tier_id: String, o: Vector2, s: float) -> void:
	var tex := texture(tier_id)
	if tex != null:
		var side := s * 1.3
		ci.draw_texture_rect(tex, Rect2(o - Vector2(side, side) / 2.0, Vector2(side, side)), false)
		return
	draw_vector(ci, tier_id, o, s)


static func draw_vector(ci: CanvasItem, tier_id: String, o: Vector2, s: float) -> void:
	var lv := level(tier_id)
	var col: Color = PvpRules.tier_color(tier_id)
	if lv >= 6:
		_rays(ci, o + Vector2(0, -s * 0.04), s * 0.86, 16, RAINBOW, 0.75)
		_halo(ci, o + Vector2(0, -s * 0.04), s * 0.56, s * 0.05)
	elif lv >= 4:
		_rays(ci, o + Vector2(0, -s * 0.04), s * (0.70 + 0.08 * (lv - 4)), 12, [col.lightened(0.45), col.lightened(0.2)], 0.6)
	if lv >= 4:
		_shards(ci, o, s, col, lv)
	if lv >= 1:
		_wings(ci, o, s, col, lv)
	if lv >= 3:
		_laurel(ci, o, s, col, lv)
	_shield(ci, o, s, col, lv)
	if lv >= 2:
		_crest(ci, o, s, col, lv)
	var gem_col := col.lightened(0.5) if lv < 6 else Color("FF8A8A")
	if lv >= 5:
		ci.draw_circle(o + Vector2(0, -s * 0.04), s * 0.19, Color(Color.WHITE, 0.22))
	_gem(ci, o + Vector2(0, -s * 0.04), s * (0.12 + 0.01 * lv), gem_col, 4 + mini(lv, 4))


## 챌린저 무지개 고리: 방패 뒤 굵은 원을 무지개 일곱 조각으로.
static func _halo(ci: CanvasItem, o: Vector2, r: float, w: float) -> void:
	var n := RAINBOW.size()
	for i in n:
		var a0 := -PI / 2.0 + TAU * i / n
		ci.draw_arc(o, r, a0, a0 + TAU / n + 0.02, 10, RAINBOW[i], w, true)


## 방패: 위가 넓고 아래가 뾰족한 6각. 왼쪽 반 밝게·오른쪽 반 어둡게, 안쪽 판 한 겹(티어가 오르면 테 두께가 굵어진다).
static func _shield(ci: CanvasItem, o: Vector2, s: float, col: Color, lv: int) -> void:
	var w := s * 0.36
	var pts := PackedVector2Array([o + Vector2(-w, -s * 0.36), o + Vector2(0, -s * 0.44), o + Vector2(w, -s * 0.36),
		o + Vector2(w * 0.92, s * 0.08), o + Vector2(0, s * 0.42), o + Vector2(-w * 0.92, s * 0.08)])
	_facet(ci, pts, o, col.darkened(0.2))
	var k := 0.80 - 0.015 * lv
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(o + (p - o) * k)
	_facet(ci, inner, o, col)


## 볼록 다각형을 가운데 세로선으로 갈라 왼쪽은 밝게, 오른쪽은 어둡게(로우폴리 면).
static func _facet(ci: CanvasItem, pts: PackedVector2Array, o: Vector2, col: Color) -> void:
	var n := pts.size()
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var mid := (a + b) / 2.0
		var c := col.lightened(0.16) if mid.x < o.x - 0.5 else (col.darkened(0.14) if mid.x > o.x + 0.5 else col)
		if mid.y < o.y - 0.0 and absf(mid.x - o.x) < (b - a).length():
			c = c.lightened(0.06)
		ci.draw_colored_polygon(PackedVector2Array([o, a, b]), c)


## 날개: 방패 양옆 깃털(사각 조각) — 실버 2장, 골드 3장, 플래티넘 3장, 다이아 4장, 마스터·챌린저 5장(더 길게).
static func _wings(ci: CanvasItem, o: Vector2, s: float, col: Color, lv: int) -> void:
	var n: int = [0, 2, 3, 3, 3, 4, 4][lv]
	var span := s * (0.20 + 0.055 * lv)
	var feather := col.lerp(Color.WHITE, 0.35 if lv < 5 else 0.2)
	for side in [-1.0, 1.0]:
		for i in n:
			var t := float(i) / maxf(1.0, n - 1)
			var root := o + Vector2(side * s * 0.30, -s * 0.22 + t * s * 0.30)
			var ang := deg_to_rad(-40.0 + t * 55.0)
			var dir := Vector2(cos(ang) * side, sin(ang))
			var length := span * (1.0 - t * 0.45)
			var tip := root + dir * length
			var nrm := Vector2(-dir.y, dir.x) * s * 0.06
			var quad := PackedVector2Array([root - nrm, root + dir * length * 0.55 - nrm * 1.3, tip, root + dir * length * 0.55 + nrm * 1.3, root + nrm])
			ci.draw_colored_polygon(quad, feather.darkened(0.08 * i) if side < 0.0 else feather.darkened(0.12 + 0.08 * i))


## 위 장식: 골드·플래티넘 = 뿔 하나, 다이아 = 셋, 마스터 = 왕관 셋, 챌린저 = 왕관 다섯.
static func _crest(ci: CanvasItem, o: Vector2, s: float, col: Color, lv: int) -> void:
	var n: int = [0, 0, 1, 1, 3, 3, 5][lv]
	var base_y := -s * 0.42
	var crown := lv >= 5
	var c := col.lightened(0.25) if not crown else col.lerp(Color.WHITE, 0.15)
	if crown:
		var band := PackedVector2Array([o + Vector2(-s * 0.26, base_y - s * 0.02), o + Vector2(s * 0.26, base_y - s * 0.02),
			o + Vector2(s * 0.24, base_y + s * 0.06), o + Vector2(-s * 0.24, base_y + s * 0.06)])
		ci.draw_colored_polygon(band, c.darkened(0.15))
	for i in n:
		var x := 0.0 if n == 1 else lerpf(-s * 0.22, s * 0.22, float(i) / (n - 1))
		var h := s * (0.20 if i == n / 2 else 0.13) * (1.15 if crown else 1.0)
		var bw := s * 0.07
		var p := o + Vector2(x, base_y)
		ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-bw, 0), p + Vector2(0, -h), p + Vector2(0, 0)]), c.lightened(0.1))
		ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, 0), p + Vector2(0, -h), p + Vector2(bw, 0)]), c.darkened(0.12))
		if crown:
			_gem(ci, p + Vector2(0, -h - s * 0.025), s * 0.03, RAINBOW[i % RAINBOW.size()] if lv >= 6 else Color.WHITE, 4)


## 아래 월계 잎: 방패 아래 양쪽으로 잎 넷(마스터부터 다섯).
static func _laurel(ci: CanvasItem, o: Vector2, s: float, col: Color, lv: int) -> void:
	var n := 4 if lv < 5 else 5
	var leaf := col.lerp(Color("7FD08A"), 0.35).lightened(0.1)
	for side in [-1.0, 1.0]:
		for i in n:
			var t := float(i) / (n - 1)
			var ang := deg_to_rad(100.0 - t * 70.0)
			var p := o + Vector2(cos(ang) * side, sin(ang)) * s * 0.42 + Vector2(0, -s * 0.02)
			var d := Vector2(cos(ang + PI / 2.0 * -side) * side, sin(ang + PI / 2.0 * -side)) * s * 0.09
			var nrm := Vector2(-d.y, d.x) * 0.55
			ci.draw_colored_polygon(PackedVector2Array([p - d, p + nrm, p + d, p - nrm]), leaf.darkened(0.06 * i) if side < 0 else leaf.darkened(0.1 + 0.06 * i))


## 뒤 빛살(다이아부터): 가늘고 긴 삼각형을 돌려 가며.
static func _rays(ci: CanvasItem, o: Vector2, r: float, n: int, cols: Array, alpha: float) -> void:
	for i in n:
		var a := TAU * i / n - PI / 2.0
		var w := TAU / n * 0.42
		var long := r * (1.0 if i % 2 == 0 else 0.78)
		ci.draw_colored_polygon(PackedVector2Array([o + Vector2.from_angle(a - w) * r * 0.3, o + Vector2.from_angle(a) * long,
			o + Vector2.from_angle(a + w) * r * 0.3]), Color(cols[i % cols.size()], alpha))


## 뒤 수정 조각(다이아부터): 방패 뒤 양옆 위로 뾰족한 결정 둘(마스터부터 넷).
static func _shards(ci: CanvasItem, o: Vector2, s: float, col: Color, lv: int) -> void:
	var list := [[-0.30, -0.30, -25.0], [0.30, -0.30, 25.0]]
	if lv >= 5:
		list += [[-0.40, 0.02, -60.0], [0.40, 0.02, 60.0]]
	for e in list:
		var p := o + Vector2(e[0], e[1]) * s
		var dir := Vector2.UP.rotated(deg_to_rad(e[2]))
		var h := s * 0.26
		var w := s * 0.06
		var nrm := Vector2(-dir.y, dir.x) * w
		var tip := p + dir * h
		var c := col.lerp(Color.WHITE, 0.45)
		ci.draw_colored_polygon(PackedVector2Array([p - nrm, tip, p]), c)
		ci.draw_colored_polygon(PackedVector2Array([p, tip, p + nrm]), c.darkened(0.18))


## 보석(외곽선 없음): 위 밝은 면·아래 어두운 면.
static func _gem(ci: CanvasItem, c: Vector2, r: float, col: Color, sides: int) -> void:
	var ring := PackedVector2Array()
	for i in sides:
		ring.append(c + Vector2.from_angle(-PI / 2.0 + TAU * i / sides) * r)
	var tip := c + Vector2(-r * 0.15, -r * 0.15)
	for i in sides:
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % sides]
		var up := ((a + b) / 2.0 - c).y < 0.0
		var left := ((a + b) / 2.0 - c).x < 0.0
		var k := col.lightened(0.3) if up and left else (col.lightened(0.1) if up else (col.darkened(0.05) if left else col.darkened(0.25)))
		ci.draw_colored_polygon(PackedVector2Array([tip, a, b]), k)

extends Control
## 자원 아이콘(골드·목재·석재·식량, 개정 23 다이아)과 장비 아이콘(개정 18: 방어구 6·무기 5), 성장 줄 아이콘(개정 20: 하트·시계·과녁·폭발 별): 평면 로우폴리 — 각진 다각형, 면마다 단색, 밝은 면 하나, 얇은 진한 외곽.
## 도형은 단위 좌표(-0.5..0.5)로 정의하고 draw_icon이 크기를 곱한다 → 어느 크기에서도 같은 모양. 장비 칸은 draw_item(등급 배경·테두리). 오토로드 참조 없음.

const Art := preload("res://scripts/art.gd")

const KINDS := ["gold", "wood", "stone", "food", "diamond"]  # 재화(HUD 칩이 이 순서로 쓴다, 개정 23: 다이아 칩)
const ITEM_KINDS := ["hat", "top", "bottom", "shoes", "pauldron", "gloves", "sword", "axe", "staff", "crossbow", "dagger"]
const OUTLINE := Color(0.16, 0.11, 0.07)
const ITEM_ICON_FRAC := 0.74  # 장비 칸 한 변 중 아이콘 크기
const TILE_CHAMFER := 0.22  # 장비 칸 모서리 깎기(반 변 대비)
# 장비 팔레트
const STEEL := Color(0.66, 0.70, 0.77)
const STEEL_LIGHT := Color(0.86, 0.89, 0.93)
const STEEL_DARK := Color(0.42, 0.46, 0.53)
const GOLD := Color(0.95, 0.74, 0.22)
const LEATHER := Color(0.58, 0.37, 0.21)
const LEATHER_LIGHT := Color(0.72, 0.50, 0.30)
const LEATHER_DARK := Color(0.38, 0.23, 0.13)
const WOOD := Color(0.60, 0.40, 0.22)
const WOOD_LIGHT := Color(0.76, 0.55, 0.33)
const CLOTH := Color(0.28, 0.40, 0.64)
const CLOTH_LIGHT := Color(0.40, 0.54, 0.78)
const CLOTH_DARK := Color(0.19, 0.28, 0.47)
const PLUME := Color(0.82, 0.22, 0.20)
const SLIT := Color(0.10, 0.10, 0.14)
const GEM := Color(0.36, 0.86, 0.96)

var kind := "gold":
	set(v):
		kind = v
		queue_redraw()


func _draw() -> void:
	draw_icon(self, kind, size / 2.0, minf(size.x, size.y))


## ci(_draw 안의 CanvasItem)에 center 중심, 한 변 size 픽셀 안에 kind 아이콘을 그린다.
static func draw_icon(ci: CanvasItem, kind_name: String, center: Vector2, size_px: float) -> void:
	var line_w := maxf(1.0, size_px / 32.0)
	for shape in shapes(kind_name):
		var pts := PackedVector2Array()
		for p in shape[0]:
			pts.append(center + p * size_px)
		ci.draw_colored_polygon(pts, shape[1])
		if shape[2]:
			pts.append(pts[0])
			ci.draw_polyline(pts, OUTLINE, line_w)


## 그리는 순서대로 [점 배열(단위 좌표), 색, 외곽선 여부]. 모르는 kind는 빈 배열.
static func shapes(kind_name: String) -> Array:
	match kind_name:
		"gold":
			return [
				[_ngon(8, 0.46, PI / 8.0), Color(0.78, 0.55, 0.10), true],
				[_ngon(8, 0.34, PI / 8.0), Color(0.95, 0.76, 0.20), true],
				[[Vector2(-0.22, -0.12), Vector2(-0.08, -0.24), Vector2(0.02, -0.2), Vector2(-0.14, -0.02)], Color(1.0, 0.92, 0.55), false],
			]
		"wood":
			return [
				[_ngon(10, 0.46, 0.0), Color(0.38, 0.25, 0.14), true],
				[_ngon(10, 0.37, 0.0), Color(0.78, 0.60, 0.38), false],
				[_ngon(8, 0.27, 0.2), Color(0.66, 0.47, 0.28), false],
				[_ngon(8, 0.19, 0.0), Color(0.80, 0.63, 0.40), false],
				[_ngon(6, 0.09, 0.0), Color(0.62, 0.43, 0.25), false],
			]
		"stone":
			var a := Vector2(-0.46, 0.18)
			var b := Vector2(-0.30, -0.26)
			var c := Vector2(0.10, -0.42)
			var d := Vector2(0.42, -0.10)
			var e := Vector2(0.46, 0.30)
			var f := Vector2(0.0, 0.42)
			var g := Vector2(-0.32, 0.36)
			var m := Vector2(0.0, 0.0)
			return [
				[[a, b, m, f, g], Color(0.44, 0.44, 0.48), false],
				[[d, e, f, m], Color(0.56, 0.56, 0.60), false],
				[[b, c, d, m], Color(0.72, 0.72, 0.76), false],
				[[a, b, c, d, e, f, g], Color(0, 0, 0, 0), true],
			]
		"food":  # 밥그릇(사용자 요청: 이삭은 화살·칼처럼 보인다) — 각진 고봉밥 + 그릇 + 받침
			var rice := Color(0.97, 0.95, 0.88)
			return [
				# 고봉밥: 각진 반원(면 3개 명암)
				[[Vector2(-0.38, 0.02), Vector2(-0.30, -0.22), Vector2(-0.10, -0.36), Vector2(0.10, -0.36), Vector2(0.30, -0.22), Vector2(0.38, 0.02)], rice, true],
				[[Vector2(-0.30, -0.22), Vector2(-0.10, -0.36), Vector2(0.02, -0.12), Vector2(-0.22, -0.04)], Color(1.0, 1.0, 0.97), false],
				[[Vector2(0.10, -0.36), Vector2(0.30, -0.22), Vector2(0.38, 0.02), Vector2(0.14, -0.04)], Color(0.88, 0.85, 0.76), false],
				# 밥알 몇 개(작은 마름모)
				[[Vector2(-0.16, -0.20), Vector2(-0.12, -0.24), Vector2(-0.08, -0.20), Vector2(-0.12, -0.16)], Color(0.80, 0.77, 0.68), false],
				[[Vector2(0.10, -0.14), Vector2(0.14, -0.18), Vector2(0.18, -0.14), Vector2(0.14, -0.10)], Color(0.80, 0.77, 0.68), false],
				# 그릇: 위가 넓은 사다리꼴(청자색) + 밝은 왼쪽 면
				[[Vector2(-0.46, 0.0), Vector2(0.46, 0.0), Vector2(0.30, 0.34), Vector2(-0.30, 0.34)], Color(0.30, 0.52, 0.62), true],
				[[Vector2(-0.46, 0.0), Vector2(-0.06, 0.0), Vector2(-0.10, 0.34), Vector2(-0.30, 0.34)], Color(0.42, 0.66, 0.76), false],
				[[Vector2(-0.46, 0.0), Vector2(0.46, 0.0), Vector2(0.44, 0.06), Vector2(-0.44, 0.06)], Color(0.22, 0.40, 0.48), false],
				# 받침
				[[Vector2(-0.18, 0.34), Vector2(0.18, 0.34), Vector2(0.22, 0.46), Vector2(-0.22, 0.46)], Color(0.24, 0.42, 0.50), true],
			]
		"diamond":  # 개정 23 다이아: 각진 하늘색 보석(브릴리언트 컷 — 위 테이블·크라운 3면, 아래 파빌리온 3면, 흰 반짝임)
			var tl := Vector2(-0.30, -0.30)
			var tr := Vector2(0.30, -0.30)
			var l := Vector2(-0.46, -0.08)
			var r := Vector2(0.46, -0.08)
			var b := Vector2(0.0, 0.44)
			var t1 := Vector2(-0.12, -0.30)
			var t2 := Vector2(0.12, -0.30)
			var g1 := Vector2(-0.20, -0.08)
			var g2 := Vector2(0.20, -0.08)
			return [
				[[tl, t1, g1, l], Color(0.62, 0.90, 1.0), false],
				[[t1, t2, g2, g1], Color(0.84, 0.97, 1.0), false],
				[[t2, tr, r, g2], Color(0.45, 0.80, 0.97), false],
				[[l, g1, b], Color(0.40, 0.76, 0.96), false],
				[[g1, g2, b], Color(0.28, 0.64, 0.90), false],
				[[g2, r, b], Color(0.18, 0.48, 0.78), false],
				[[Vector2(-0.24, -0.25), Vector2(-0.19, -0.29), Vector2(-0.14, -0.25), Vector2(-0.19, -0.21)], Color(1, 1, 1, 0.95), false],
				[[tl, tr, r, b, l], Color(0, 0, 0, 0), true],
			]
	var growth := _growth_shapes(kind_name)
	return growth if not growth.is_empty() else _item_shapes(kind_name)


## 성장 줄 아이콘(개정 20 §5): 하트(체력)·쌍화살표 시계(공격속도)·과녁(치명타 확률)·폭발 별(치명타 배율). 공격력은 "sword", 이동속도는 "shoes".
static func _growth_shapes(kind_name: String) -> Array:
	match kind_name:
		"heart":  # 각진 하트: 밝은 왼쪽 면 + 오른 아래 그늘 + 흰 빛
			var red := Color(0.86, 0.20, 0.24)
			var left := [Vector2(0.0, 0.44), Vector2(-0.42, 0.02), Vector2(-0.47, -0.16), Vector2(-0.40, -0.34), Vector2(-0.24, -0.42), Vector2(-0.08, -0.36), Vector2(0.0, -0.24)]
			var whole: Array = left + [Vector2(0.08, -0.36), Vector2(0.24, -0.42), Vector2(0.40, -0.34), Vector2(0.47, -0.16), Vector2(0.42, 0.02)]
			return [
				[whole, red, true],
				[left, red.lightened(0.22), false],
				[[Vector2(0.0, 0.44), Vector2(0.42, 0.02), Vector2(0.18, 0.04)], red.darkened(0.25), false],
				[[Vector2(-0.34, -0.26), Vector2(-0.24, -0.33), Vector2(-0.16, -0.28), Vector2(-0.28, -0.17)], Color(1.0, 0.86, 0.86), false],
				[whole, Color(0, 0, 0, 0), true],
			]
		"haste":  # 쌍화살표 시계: 파란 테 시계(눈금 넷·바늘 둘) + 오른 아래 금색 ≫
			var c := Vector2(-0.08, -0.04)
			var out := [
				[_ngon(12, 0.40, PI / 12.0).map(func(p): return p + c), CLOTH, true],
				[_ngon(12, 0.31, PI / 12.0).map(func(p): return p + c), Color(0.98, 0.96, 0.90), true],
			]
			for k in 4:
				var dir := Vector2.from_angle(k * PI / 2.0)
				out.append([_quad(c + dir * 0.23, c + dir * 0.29, 0.022), SLIT, false])
			out.append([_quad(c, c + Vector2(0, -0.20), 0.03), SLIT, false])
			out.append([_quad(c, c + Vector2(0.15, 0.08), 0.03), SLIT, false])
			out.append([_ngon(6, 0.045, 0.0).map(func(p): return p + c), PLUME, false])
			for x0 in [0.10, 0.24]:
				out.append([[Vector2(x0, 0.0), Vector2(x0 + 0.12, 0.0), Vector2(x0 + 0.26, 0.21), Vector2(x0 + 0.12, 0.42), Vector2(x0, 0.42),
					Vector2(x0 + 0.14, 0.21)], GOLD, true])
			return out
		"target":  # 과녁(빨강·흰 고리, 금 한가운데) + 가운데 꽂힌 화살(자루·파란 깃)
			var red := Color(0.84, 0.20, 0.22)
			var a := Vector2(0.0, 0.0)
			var b := Vector2(0.42, -0.42)
			return [
				[_ngon(16, 0.46, 0.0), red, true],
				[_ngon(16, 0.35, 0.0), Color(0.98, 0.96, 0.90), false],
				[_ngon(16, 0.24, 0.0), red, false],
				[_ngon(16, 0.12, 0.0), GOLD, true],
				[_ax(a, b, [Vector2(0.0, 0.022), Vector2(0.58, 0.022), Vector2(0.58, -0.022), Vector2(0.0, -0.022)]), LEATHER_DARK, true],
				[_ax(a, b, [Vector2(0.40, 0.02), Vector2(0.48, 0.10), Vector2(0.58, 0.10), Vector2(0.52, 0.02)]), CLOTH_LIGHT, true],
				[_ax(a, b, [Vector2(0.40, -0.02), Vector2(0.48, -0.10), Vector2(0.58, -0.10), Vector2(0.52, -0.02)]), CLOTH, true],
			]
		"burst":  # 폭발 별: 들쭉날쭉 8갈래 주황 별(밝은 왼쪽 반) + 노란 속별 + 흰 가운데(치명타 불꽃 색)
			var star := []
			var core := []
			for i in 16:
				var ang := -PI / 2.0 + TAU * i / 16.0
				star.append(Vector2.from_angle(ang) * ([0.48, 0.22, 0.38, 0.22][i % 4]))
				core.append(Vector2.from_angle(ang) * (0.28 if i % 2 == 0 else 0.13))
			var orange := Color(0.96, 0.45, 0.12)
			return [
				[star, orange, true],
				[[Vector2.ZERO] + star.slice(8) + [star[0]], orange.lightened(0.2), false],
				[core, Color(1.0, 0.84, 0.30), false],
				[_ngon(8, 0.07, 0.0), Color(1.0, 0.98, 0.86), false],
				[star, Color(0, 0, 0, 0), true],
			]
	return []


## 장비 칸 하나(개정 18 §8): 등급 색 배경 면(모서리 깎은 사각, 왼쪽 위 절반 밝게) + 등급 색 테두리 + kind 아이콘.
## LR 테두리는 무지개 금이 t(초)에 따라 흐른다 — 쓰는 쪽이 매 프레임 queue_redraw. t < 0이면 지금 시각.
static func draw_item(ci: CanvasItem, kind_name: String, grade: String, center: Vector2, size_px: float, t := -1.0) -> void:
	if t < 0.0:
		t = Time.get_ticks_msec() / 1000.0
	var base: Color = Art.ITEM_GRADE_COLORS.get(grade, Art.ITEM_GRADE_COLORS.N)
	var pts := PackedVector2Array()
	for p in item_tile():
		pts.append(center + p * size_px)
	ci.draw_colored_polygon(pts, base.darkened(0.6))
	ci.draw_colored_polygon(PackedVector2Array([pts[6], pts[7], pts[0], pts[1], pts[2]]), base.darkened(0.48))
	var ring := PackedVector2Array()
	for i in 8:  # 테두리: 변마다 4등분(LR 무지개가 부드럽게 흐르게)
		for j in 4:
			ring.append(pts[i].lerp(pts[(i + 1) % 8], j / 4.0))
	ring.append(pts[0])
	ci.draw_polyline_colors(ring, border_colors(grade, ring.size(), t), maxf(2.0, size_px / 14.0))
	draw_icon(ci, kind_name, center, size_px * ITEM_ICON_FRAC)


## 장비 칸 외곽(단위 좌표, 한 변 0.96): 모서리 깎은 8각, 위 왼쪽부터 시계 방향.
static func item_tile() -> Array:
	var h := 0.48
	var c := h * TILE_CHAMFER
	return [Vector2(-h + c, -h), Vector2(h - c, -h), Vector2(h, -h + c), Vector2(h, h - c),
		Vector2(h - c, h), Vector2(-h + c, h), Vector2(-h, h - c), Vector2(-h, -h + c)]


## 테두리 점 n개의 색: 등급 색 하나. LR은 둘레를 따라 무지개(금빛 섞음)가 t에 따라 흐른다(끝점 = 첫 점 색이라 이음매 없음).
static func border_colors(grade: String, n: int, t: float) -> PackedColorArray:
	var base: Color = Art.ITEM_GRADE_COLORS.get(grade, Art.ITEM_GRADE_COLORS.N)
	var out := PackedColorArray()
	for i in n:
		if grade == "LR":
			out.append(Color.from_hsv(fposmod(float(i) / (n - 1) - t * 0.35, 1.0), 0.6, 1.0).lerp(base, 0.35))
		else:
			out.append(base)
	return out


## 장비 도형(단위 좌표, 그리기 순서). 무기는 왼쪽 아래 → 오른쪽 위 대각선 축 좌표(_ax)로 그린다.
static func _item_shapes(kind_name: String) -> Array:
	match kind_name:
		"hat":  # 투구: 앞을 막은 통투구 + 가로 눈구멍 + 숨구멍, 위에 붉은 깃털
			return [
				[[Vector2(-0.06, -0.34), Vector2(0.02, -0.46), Vector2(0.20, -0.48), Vector2(0.34, -0.40), Vector2(0.18, -0.30)], PLUME, true],
				[[Vector2(-0.36, 0.42), Vector2(-0.38, -0.06), Vector2(-0.30, -0.26), Vector2(-0.14, -0.36), Vector2(0.14, -0.36),
					Vector2(0.30, -0.26), Vector2(0.38, -0.06), Vector2(0.36, 0.42)], STEEL, true],
				[[Vector2(-0.38, -0.06), Vector2(-0.30, -0.26), Vector2(-0.14, -0.36), Vector2(-0.02, -0.36), Vector2(-0.02, 0.42), Vector2(-0.36, 0.42)], STEEL_LIGHT, false],
				[[Vector2(-0.02, -0.36), Vector2(0.02, -0.36), Vector2(0.02, 0.42), Vector2(-0.02, 0.42)], STEEL_DARK, false],
				[[Vector2(-0.31, -0.07), Vector2(0.31, -0.07), Vector2(0.31, 0.03), Vector2(-0.31, 0.03)], SLIT, false],
				[[Vector2(0.10, 0.14), Vector2(0.16, 0.14), Vector2(0.16, 0.20), Vector2(0.10, 0.20)], SLIT, false],
				[[Vector2(0.20, 0.14), Vector2(0.26, 0.14), Vector2(0.26, 0.20), Vector2(0.20, 0.20)], SLIT, false],
				[[Vector2(0.15, 0.25), Vector2(0.21, 0.25), Vector2(0.21, 0.31), Vector2(0.15, 0.31)], SLIT, false],
				[[Vector2(-0.36, 0.33), Vector2(0.36, 0.33), Vector2(0.36, 0.42), Vector2(-0.36, 0.42)], GOLD, true],
			]
		"top":  # 갑옷 상의: 어깨 판 + 목 파임 흉갑, 가운데 능선, 배 마디, 허리띠
			var body := [Vector2(-0.20, -0.40), Vector2(-0.07, -0.30), Vector2(0.07, -0.30), Vector2(0.20, -0.40), Vector2(0.42, -0.33),
				Vector2(0.45, -0.12), Vector2(0.30, -0.06), Vector2(0.28, 0.30), Vector2(0.20, 0.42), Vector2(-0.20, 0.42),
				Vector2(-0.28, 0.30), Vector2(-0.30, -0.06), Vector2(-0.45, -0.12), Vector2(-0.42, -0.33)]
			return [
				[body, STEEL, true],
				[[Vector2(-0.07, -0.30), Vector2(0.0, -0.30), Vector2(0.0, 0.42), Vector2(-0.20, 0.42), Vector2(-0.28, 0.30), Vector2(-0.30, -0.06)], STEEL_LIGHT, false],
				[[Vector2(-0.20, -0.40), Vector2(-0.42, -0.33), Vector2(-0.45, -0.12), Vector2(-0.30, -0.08), Vector2(-0.24, -0.30)], STEEL_DARK, true],
				[[Vector2(0.20, -0.40), Vector2(0.42, -0.33), Vector2(0.45, -0.12), Vector2(0.30, -0.08), Vector2(0.24, -0.30)], STEEL_DARK, true],
				[[Vector2(-0.015, -0.30), Vector2(0.015, -0.30), Vector2(0.015, 0.28), Vector2(-0.015, 0.28)], STEEL_DARK, false],
				[[Vector2(-0.29, 0.08), Vector2(0.29, 0.08), Vector2(0.29, 0.11), Vector2(-0.29, 0.11)], STEEL_DARK, false],
				[[Vector2(-0.285, 0.18), Vector2(0.285, 0.18), Vector2(0.285, 0.21), Vector2(-0.285, 0.21)], STEEL_DARK, false],
				[[Vector2(-0.28, 0.28), Vector2(0.28, 0.28), Vector2(0.26, 0.37), Vector2(-0.26, 0.37)], LEATHER, true],
				[[Vector2(-0.05, 0.27), Vector2(0.05, 0.27), Vector2(0.05, 0.38), Vector2(-0.05, 0.38)], GOLD, true],
				[[Vector2(-0.20, -0.40), Vector2(-0.07, -0.30), Vector2(0.07, -0.30), Vector2(0.20, -0.40), Vector2(0.16, -0.43),
					Vector2(0.06, -0.35), Vector2(-0.06, -0.35), Vector2(-0.16, -0.43)], GOLD, false],
			]
		"bottom":  # 바지: 허리띠(금 버클) + 두 다리(가랑이 틈), 무릎 보호대
			return [
				[[Vector2(-0.32, -0.32), Vector2(0.32, -0.32), Vector2(0.36, 0.44), Vector2(0.07, 0.44), Vector2(0.0, -0.02),
					Vector2(-0.07, 0.44), Vector2(-0.36, 0.44)], CLOTH, true],
				[[Vector2(-0.32, -0.32), Vector2(-0.12, -0.32), Vector2(-0.20, 0.44), Vector2(-0.36, 0.44)], CLOTH_LIGHT, false],
				[[Vector2(0.0, -0.02), Vector2(0.07, 0.44), Vector2(0.17, 0.44), Vector2(0.09, -0.02)], CLOTH_DARK, false],
				[[Vector2(-0.36, 0.37), Vector2(-0.07, 0.37), Vector2(-0.07, 0.44), Vector2(-0.36, 0.44)], CLOTH_DARK, false],
				[[Vector2(0.07, 0.37), Vector2(0.36, 0.37), Vector2(0.36, 0.44), Vector2(0.07, 0.44)], CLOTH_DARK, false],
				[[Vector2(-0.29, 0.14), Vector2(-0.20, 0.06), Vector2(-0.11, 0.14), Vector2(-0.20, 0.22)], STEEL, true],
				[[Vector2(0.11, 0.14), Vector2(0.20, 0.06), Vector2(0.29, 0.14), Vector2(0.20, 0.22)], STEEL, true],
				[[Vector2(-0.34, -0.45), Vector2(0.34, -0.45), Vector2(0.34, -0.31), Vector2(-0.34, -0.31)], LEATHER_DARK, true],
				[[Vector2(-0.07, -0.44), Vector2(0.07, -0.44), Vector2(0.07, -0.32), Vector2(-0.07, -0.32)], GOLD, true],
			]
		"shoes":  # 장화(옆모습, 발끝 오른쪽): 접힌 목 + 버클 띠 + 굽 있는 밑창
			return [
				[[Vector2(-0.28, -0.40), Vector2(0.08, -0.40), Vector2(0.10, 0.06), Vector2(0.34, 0.14), Vector2(0.44, 0.26),
					Vector2(0.44, 0.36), Vector2(-0.28, 0.36)], LEATHER, true],
				[[Vector2(-0.28, -0.32), Vector2(-0.14, -0.32), Vector2(-0.14, 0.30), Vector2(-0.28, 0.30)], LEATHER_LIGHT, false],
				[[Vector2(0.10, 0.06), Vector2(0.34, 0.14), Vector2(0.44, 0.26), Vector2(0.30, 0.22), Vector2(0.10, 0.16)], LEATHER_LIGHT, false],
				[[Vector2(-0.28, -0.12), Vector2(0.09, -0.12), Vector2(0.09, -0.04), Vector2(-0.28, -0.04)], LEATHER_DARK, false],
				[[Vector2(-0.12, -0.14), Vector2(-0.02, -0.14), Vector2(-0.02, -0.02), Vector2(-0.12, -0.02)], GOLD, true],
				[[Vector2(-0.33, -0.47), Vector2(0.13, -0.47), Vector2(0.13, -0.33), Vector2(-0.33, -0.33)], LEATHER_LIGHT, true],
				[[Vector2(-0.30, 0.34), Vector2(0.45, 0.34), Vector2(0.45, 0.42), Vector2(-0.30, 0.42)], LEATHER_DARK, true],
				[[Vector2(-0.30, 0.34), Vector2(-0.06, 0.34), Vector2(-0.08, 0.47), Vector2(-0.30, 0.47)], LEATHER_DARK, true],
			]
		"pauldron":  # 견장: 목 가리개 양옆 어깨 판 한 쌍(둥근 윗판 + 바깥 아래로 겹친 판 둘, 금 테두리·징) — 몸통이 없어 상의와 구별된다
			var out := [
				[[Vector2(-0.17, -0.14), Vector2(0.17, -0.14), Vector2(0.21, 0.08), Vector2(0.0, 0.16), Vector2(-0.21, 0.08)], STEEL_DARK, true],
				[[Vector2(-0.11, -0.14), Vector2(0.11, -0.14), Vector2(0.07, -0.07), Vector2(0.0, -0.05), Vector2(-0.07, -0.07)], SLIT, false],
			]
			for s in [-1.0, 1.0]:
				var m := func(pts: Array) -> Array: return pts.map(func(p): return Vector2(p.x * s, p.y))
				out.append_array([
					[m.call([Vector2(0.28, -0.30), Vector2(0.36, -0.46), Vector2(0.40, -0.28)]), STEEL_LIGHT, true],
					[m.call([Vector2(0.18, 0.12), Vector2(0.45, 0.20), Vector2(0.43, 0.32), Vector2(0.20, 0.25)]), STEEL_DARK, true],
					[m.call([Vector2(0.16, 0.02), Vector2(0.48, 0.08), Vector2(0.47, 0.21), Vector2(0.18, 0.14)]), STEEL, true],
					[m.call([Vector2(0.12, -0.14), Vector2(0.17, -0.27), Vector2(0.28, -0.34), Vector2(0.40, -0.31), Vector2(0.48, -0.18),
						Vector2(0.49, 0.04), Vector2(0.14, 0.02)]), STEEL, true],
					[m.call([Vector2(0.17, -0.27), Vector2(0.28, -0.34), Vector2(0.40, -0.31), Vector2(0.30, -0.18), Vector2(0.16, -0.16)]), STEEL_LIGHT, false],
					[m.call([Vector2(0.14, 0.02), Vector2(0.49, 0.04), Vector2(0.49, 0.09), Vector2(0.14, 0.07)]), GOLD, false],
					[_ngon(6, 0.03, 0.0).map(func(p): return p + Vector2(0.34 * s, -0.10)), GOLD, true],
				])
			return out
		"gloves":  # 장갑: 손가락 넷 + 엄지 + 손바닥, 쇠 손등판, 넓은 손목
			var fingers := []
			for f in [[-0.195, -0.36], [-0.07, -0.44], [0.055, -0.42], [0.175, -0.32]]:
				var x: float = f[0]
				var top: float = f[1]
				fingers.append([[Vector2(x - 0.055, -0.08), Vector2(x - 0.055, top + 0.03), Vector2(x - 0.03, top), Vector2(x + 0.03, top),
					Vector2(x + 0.055, top + 0.03), Vector2(x + 0.055, -0.08)], LEATHER, true])
				fingers.append([[Vector2(x - 0.055, top + 0.13), Vector2(x + 0.055, top + 0.13), Vector2(x + 0.055, top + 0.155), Vector2(x - 0.055, top + 0.155)], LEATHER_DARK, false])
			var thumb := [Vector2(-0.24, 0.16), Vector2(-0.24, -0.02), Vector2(-0.34, -0.14), Vector2(-0.40, -0.17), Vector2(-0.45, -0.12),
				Vector2(-0.43, -0.04), Vector2(-0.34, 0.08)]
			return [[thumb, LEATHER, true]] + fingers + [
				[[Vector2(-0.25, -0.12), Vector2(0.23, -0.12), Vector2(0.25, 0.22), Vector2(-0.25, 0.22)], LEATHER, true],
				[[Vector2(-0.25, -0.12), Vector2(-0.08, -0.12), Vector2(-0.10, 0.22), Vector2(-0.25, 0.22)], LEATHER_LIGHT, false],
				[[Vector2(-0.27, -0.16), Vector2(0.25, -0.16), Vector2(0.25, -0.03), Vector2(-0.27, -0.03)], STEEL, true],
				[[Vector2(-0.27, -0.16), Vector2(-0.05, -0.16), Vector2(-0.05, -0.03), Vector2(-0.27, -0.03)], STEEL_LIGHT, false],
				[[Vector2(-0.30, 0.18), Vector2(0.30, 0.18), Vector2(0.35, 0.46), Vector2(-0.35, 0.46)], LEATHER_DARK, true],
				[[Vector2(-0.30, 0.18), Vector2(0.30, 0.18), Vector2(0.31, 0.23), Vector2(-0.31, 0.23)], GOLD, false],
			]
		"sword":  # 검: 길고 곧은 칼날(밝은 반쪽·홈) + 금 코등이 + 가죽 손잡이 + 금 폼멜
			var a := Vector2(-0.40, 0.40)
			var b := Vector2(0.42, -0.42)
			return [
				[_ax(a, b, [Vector2(0.30, 0.075), Vector2(1.04, 0.075), Vector2(1.16, 0.0), Vector2(1.04, -0.075), Vector2(0.30, -0.075)]), STEEL, true],
				[_ax(a, b, [Vector2(0.30, 0.075), Vector2(1.04, 0.075), Vector2(1.16, 0.0), Vector2(0.30, 0.0)]), STEEL_LIGHT, false],
				[_ax(a, b, [Vector2(0.36, 0.014), Vector2(0.92, 0.014), Vector2(0.92, -0.014), Vector2(0.36, -0.014)]), STEEL_DARK, false],
				[_ax(a, b, [Vector2(0.07, 0.042), Vector2(0.26, 0.042), Vector2(0.26, -0.042), Vector2(0.07, -0.042)]), LEATHER, true],
				[_ax(a, b, [Vector2(0.24, 0.20), Vector2(0.31, 0.20), Vector2(0.31, -0.20), Vector2(0.24, -0.20)]), GOLD, true],
				[_ax(a, b, [Vector2(0.0, 0.0), Vector2(0.05, 0.065), Vector2(0.10, 0.0), Vector2(0.05, -0.065)]), GOLD, true],
			]
		"axe":  # 도끼: 나무 자루(가죽 손잡이) + 위쪽 왼편에 크고 넓은 초승달 날(밝은 날 끝) + 반대쪽 짧은 가시
			var a := Vector2(-0.24, 0.46)
			var b := Vector2(0.32, -0.12)
			return [
				[_ax(a, b, [Vector2(0.0, 0.045), Vector2(0.92, 0.045), Vector2(0.92, -0.045), Vector2(0.0, -0.045)]), WOOD, true],
				[_ax(a, b, [Vector2(0.0, 0.045), Vector2(0.92, 0.045), Vector2(0.92, 0.0), Vector2(0.0, 0.0)]), WOOD_LIGHT, false],
				[_ax(a, b, [Vector2(0.03, 0.056), Vector2(0.24, 0.056), Vector2(0.24, -0.056), Vector2(0.03, -0.056)]), LEATHER_DARK, true],
				[_ax(a, b, [Vector2(0.66, -0.05), Vector2(0.76, -0.22), Vector2(0.84, -0.05)]), STEEL_DARK, true],
				[_ax(a, b, [Vector2(0.58, 0.04), Vector2(0.50, 0.16), Vector2(0.40, 0.34), Vector2(0.50, 0.45), Vector2(0.66, 0.49),
					Vector2(0.82, 0.45), Vector2(0.90, 0.32), Vector2(0.84, 0.16), Vector2(0.80, 0.04)]), STEEL, true],
				[_ax(a, b, [Vector2(0.40, 0.34), Vector2(0.50, 0.45), Vector2(0.66, 0.49), Vector2(0.82, 0.45), Vector2(0.90, 0.32),
					Vector2(0.84, 0.30), Vector2(0.78, 0.39), Vector2(0.66, 0.42), Vector2(0.53, 0.39), Vector2(0.46, 0.30)]), STEEL_LIGHT, false],
				[_ax(a, b, [Vector2(0.56, 0.065), Vector2(0.84, 0.065), Vector2(0.84, -0.065), Vector2(0.56, -0.065)]), STEEL_DARK, true],
			]
		"staff":  # 지팡이: 나무 자루(금 띠) + 꼭대기 갈퀴 둘이 쥔 하늘색 수정(빛 번짐)
			var a := Vector2(-0.38, 0.44)
			var b := Vector2(0.14, -0.14)
			var c := Vector2(0.22, -0.28)
			return [
				[_ngon(8, 0.20, PI / 8.0).map(func(p): return p + c), Color(GEM, 0.35), false],
				[_ax(a, b, [Vector2(0.0, 0.04), Vector2(0.78, 0.035), Vector2(0.78, -0.035), Vector2(0.0, -0.04)]), WOOD, true],
				[_ax(a, b, [Vector2(0.0, 0.04), Vector2(0.78, 0.035), Vector2(0.78, 0.0), Vector2(0.0, 0.0)]), WOOD_LIGHT, false],
				[_ax(a, b, [Vector2(0.55, 0.05), Vector2(0.61, 0.05), Vector2(0.61, -0.05), Vector2(0.55, -0.05)]), GOLD, true],
				[_ax(a, b, [Vector2(0.0, 0.045), Vector2(0.06, 0.045), Vector2(0.06, -0.045), Vector2(0.0, -0.045)]), GOLD, true],
				[[c + Vector2(-0.04, 0.17), c + Vector2(-0.16, 0.03), c + Vector2(-0.12, 0.0), c + Vector2(-0.01, 0.12)], WOOD, true],
				[[c + Vector2(0.04, 0.17), c + Vector2(0.16, 0.03), c + Vector2(0.12, 0.0), c + Vector2(0.01, 0.12)], WOOD, true],
				[[c + Vector2(0.0, -0.17), c + Vector2(0.11, 0.0), c + Vector2(0.0, 0.14), c + Vector2(-0.11, 0.0)], GEM, true],
				[[c + Vector2(0.0, -0.17), c + Vector2(0.0, 0.0), c + Vector2(-0.11, 0.0)], GEM.lightened(0.45), false],
				[[c + Vector2(0.0, 0.0), c + Vector2(0.11, 0.0), c + Vector2(0.0, 0.14)], GEM.darkened(0.25), false],
			]
		"crossbow":  # 석궁(위에서 본 모습, 위를 겨눔): 휜 활(쇠) + 시위 + 나무 개머리 + 장전된 볼트
			return [
				[_quad(Vector2(-0.42, 0.04), Vector2(0.0, 0.12), 0.012), SLIT, false],
				[_quad(Vector2(0.42, 0.04), Vector2(0.0, 0.12), 0.012), SLIT, false],
				[[Vector2(-0.46, 0.04), Vector2(-0.34, -0.12), Vector2(-0.14, -0.22), Vector2(0.14, -0.22), Vector2(0.34, -0.12), Vector2(0.46, 0.04),
					Vector2(0.39, 0.06), Vector2(0.29, -0.06), Vector2(0.12, -0.15), Vector2(-0.12, -0.15), Vector2(-0.29, -0.06), Vector2(-0.39, 0.06)], STEEL_DARK, true],
				[[Vector2(-0.065, -0.24), Vector2(0.065, -0.24), Vector2(0.075, 0.26), Vector2(0.11, 0.44), Vector2(-0.11, 0.44), Vector2(-0.075, 0.26)], WOOD, true],
				[[Vector2(-0.065, -0.24), Vector2(0.0, -0.24), Vector2(0.0, 0.44), Vector2(-0.11, 0.44), Vector2(-0.075, 0.26)], WOOD_LIGHT, false],
				[[Vector2(0.065, 0.14), Vector2(0.13, 0.17), Vector2(0.12, 0.24), Vector2(0.07, 0.22)], SLIT, false],
				[[Vector2(-0.018, -0.36), Vector2(0.018, -0.36), Vector2(0.018, 0.12), Vector2(-0.018, 0.12)], LEATHER_LIGHT, false],
				[[Vector2(-0.05, 0.06), Vector2(0.0, 0.02), Vector2(0.05, 0.06), Vector2(0.0, 0.12)], PLUME, false],
				[[Vector2(-0.055, -0.33), Vector2(0.0, -0.47), Vector2(0.055, -0.33)], STEEL, true],
			]
		"dagger":  # 단검: 짧고 넓은 나뭇잎 칼날 + 짧은 쇠 코등이 + 감은 손잡이 + 고리 폼멜
			var a := Vector2(-0.30, 0.34)
			var b := Vector2(0.36, -0.32)
			var ring: Array = _ngon(8, 0.06, PI / 8.0).map(func(p): return p + _ax(a, b, [Vector2(0.0, 0.0)])[0])
			return [
				[ring, STEEL_DARK, true],
				[_ax(a, b, [Vector2(0.28, 0.115), Vector2(0.62, 0.095), Vector2(0.93, 0.0), Vector2(0.62, -0.095), Vector2(0.28, -0.115)]), STEEL, true],
				[_ax(a, b, [Vector2(0.28, 0.115), Vector2(0.62, 0.095), Vector2(0.93, 0.0), Vector2(0.28, 0.0)]), STEEL_LIGHT, false],
				[_ax(a, b, [Vector2(0.05, 0.045), Vector2(0.24, 0.045), Vector2(0.24, -0.045), Vector2(0.05, -0.045)]), LEATHER_DARK, true],
				[_ax(a, b, [Vector2(0.11, 0.046), Vector2(0.13, 0.046), Vector2(0.13, -0.046), Vector2(0.11, -0.046)]), LEATHER_LIGHT, false],
				[_ax(a, b, [Vector2(0.17, 0.046), Vector2(0.19, 0.046), Vector2(0.19, -0.046), Vector2(0.17, -0.046)]), LEATHER_LIGHT, false],
				[_ax(a, b, [Vector2(0.22, 0.15), Vector2(0.29, 0.13), Vector2(0.29, -0.13), Vector2(0.22, -0.15)]), STEEL_DARK, true],
			]
	return []


## 축 좌표 → 단위 좌표: p0에서 p1 쪽으로 s(=x), 진행 방향 왼쪽(화면에서 위·왼쪽) 법선으로 t(=y). 무기를 대각선으로 그릴 때.
static func _ax(p0: Vector2, p1: Vector2, st: Array) -> Array:
	var d := (p1 - p0).normalized()
	var n := Vector2(d.y, -d.x)
	var out := []
	for q in st:
		out.append(p0 + d * q.x + n * q.y)
	return out


## 정 n각형(원점 중심, 반지름 r, 시작각 rot).
static func _ngon(n: int, r: float, rot: float) -> Array:
	var pts := []
	for i in n:
		pts.append(Vector2.from_angle(rot + TAU * i / n) * r)
	return pts


## from → to 선분을 두께 2*half_w로 만든 사각형.
static func _quad(from: Vector2, to: Vector2, half_w: float) -> Array:
	var n := (to - from).normalized().orthogonal() * half_w
	return [from + n, to + n, to - n, from - n]

extends StyleBox
## 두루마리 창 박스(2026-10-12 사용자 "게임 내 팝업창을 두루마리 느낌으로"): 위아래로 말린 종이 축 + 그 사이 펼친 양피지.
## 모양(rect 안에 다 그린다 — 창이 화면 가장자리에 붙어도 잘리지 않게):
##  - 종이: 축보다 조금 좁게(축이 양옆으로 OVERHANG만큼 삐져나온다), 위 축 가운데 ~ 아래 축 가운데. 옆 가장자리는 살짝 울퉁불퉁,
##    로우폴리 면(왼위 광원 + 위치 해시)에 가장자리로 갈수록 그을린 갈색. 안쪽에 가는 장식 테두리. 외곽선은 종이 색을 어둡게
##    (UI 박스 외곽선 규칙 — LowpolyBox.edge_color).
##  - 축(위·아래): 말린 종이 원통 — 가로 띠 5줄(위 밝게 ~ 아래 어둡게), 양끝에 말린 단면(겹친 8각형), 그 바깥에 금빛 고리 + 나무 손잡이.
##    위 축 아래·아래 축 위에 옅은 그림자.
## 내용 여백은 축·손잡이·테두리를 피한다(set_roll이 정한다). 같은 크기면 지오메트리를 재사용한다(LowpolyBox와 같다).

const LowpolyBox := preload("res://scripts/lowpoly_box.gd")

const PAPER := Color("F3E2BC")  # 양피지
const BURN := Color("C49A5E")  # 가장자리 그을린 색
const ROLL := Color("E4C68E")  # 말린 종이(종이보다 진하게)
const WOOD := Color("7B4B2A")  # 축 손잡이
const GOLD := Color("D8A646")  # 손잡이 고리
const TRIM := Color(0.55, 0.38, 0.18, 0.45)  # 안쪽 장식 테두리
const SHADOW := Color(0.35, 0.22, 0.1, 0.2)
const CELL := 72.0  # 종이 면 한 칸(px)
const WAVE := 1.6  # 종이 옆 가장자리 울퉁불퉁 폭(px)
const OVERHANG := 6.0  # 축이 종이보다 양옆으로 나온 길이
const TRIM_IN := 7.0  # 장식 테두리가 종이 가장자리에서 들어온 거리

var roll_h := 28.0  # 축 굵기
var knob_w := 18.0  # 축 끝 손잡이(고리 포함) 길이
var seed := 3

var _size := Vector2(-1, -1)
var _layers: Array = []  # 그리는 순서대로 [삼각형 점, 점 색, 선 목록[[PackedVector2Array, Color, 굵기]]] — 종이(선 포함) 위에 축
var _pts := PackedVector2Array()
var _cols := PackedColorArray()
var _lines: Array = []


## 축 굵기·손잡이 길이와 종이 안 여백(옆 pad, 위아래 pad_v)을 정하고 내용 여백을 맞춘다
## (옆 = 손잡이 + 축이 나온 길이 + pad, 위·아래 = 축 + pad_v).
func set_roll(p_roll_h: float, p_knob_w: float, pad: float, pad_v: float) -> void:
	roll_h = p_roll_h
	knob_w = p_knob_w
	content_margin_left = knob_w + OVERHANG + pad
	content_margin_right = knob_w + OVERHANG + pad
	content_margin_top = roll_h + pad_v
	content_margin_bottom = roll_h + pad_v
	_size = Vector2(-1, -1)
	emit_changed()


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if rect.size.x < (knob_w + OVERHANG) * 2.0 + 8.0 or rect.size.y < roll_h * 2.0 + 4.0:
		return
	if rect.size != _size:
		_build(rect.size)
	RenderingServer.canvas_item_add_set_transform(to_canvas_item, Transform2D(0.0, rect.position))
	for layer in _layers:
		RenderingServer.canvas_item_add_triangle_array(to_canvas_item, PackedInt32Array(), layer[0], layer[1])
		for l in layer[2]:
			var cs := PackedColorArray()
			cs.resize(l[0].size())
			cs.fill(l[1])
			RenderingServer.canvas_item_add_polyline(to_canvas_item, l[0], cs, l[2], true)
	RenderingServer.canvas_item_add_set_transform(to_canvas_item, Transform2D.IDENTITY)


func _build(s: Vector2) -> void:
	_layers = []
	_reset_layer()
	var px := knob_w + OVERHANG
	var paper := Rect2(px, roll_h * 0.5, s.x - px * 2.0, s.y - roll_h)
	_paper(paper)
	_tri_rect(Rect2(px, roll_h, paper.size.x, 6.0), SHADOW)  # 위 축 그림자
	_tri_rect(Rect2(px, s.y - roll_h - 3.0, paper.size.x, 3.0), Color(SHADOW, SHADOW.a * 0.5))  # 아래 축 위 그림자
	var trim := Rect2(px + TRIM_IN, roll_h + TRIM_IN, paper.size.x - TRIM_IN * 2.0, s.y - (roll_h + TRIM_IN) * 2.0)
	if trim.size.x > 20.0 and trim.size.y > 20.0:
		var t := LowpolyBox.octagon(trim, 5.0)
		t.append(t[0])
		_lines.append([t, TRIM, 1.2])
	_end_layer()
	_roll(Rect2(0, 0, s.x, roll_h))
	_roll(Rect2(0, s.y - roll_h, s.x, roll_h))
	_end_layer()
	_size = s


## 펼친 종이: 칸 격자(안쪽 점은 살짝 흔들고, 옆 가장자리 점은 WAVE만큼 울퉁불퉁) → 칸마다 삼각형 둘.
func _paper(r: Rect2) -> void:
	var cols := maxi(2, roundi(r.size.x / CELL))
	var rows := maxi(2, roundi(r.size.y / CELL))
	var grid := []
	for j in rows + 1:
		var line := []
		for i in cols + 1:
			var p := r.position + Vector2(r.size.x * i / cols, r.size.y * j / rows)
			var edge_x := i == 0 or i == cols
			var edge_y := j == 0 or j == rows
			if edge_x and not edge_y:
				p.x += (LowpolyBox.hash01(seed + i, j) - 0.5) * 2.0 * WAVE
			elif not edge_x and not edge_y:
				p += Vector2(LowpolyBox.hash01(seed, i * 31 + j) - 0.5, LowpolyBox.hash01(seed + 7, i * 17 + j) - 0.5) * CELL * 0.35
			line.append(p)
		grid.append(line)
	var ctr := r.get_center()
	var face := 0
	for j in rows:
		for i in cols:
			var a: Vector2 = grid[j][i]
			var b: Vector2 = grid[j][i + 1]
			var c: Vector2 = grid[j + 1][i + 1]
			var d: Vector2 = grid[j + 1][i]
			var tris := [[a, b, c], [a, c, d]] if (i + j) % 2 == 0 else [[a, b, d], [b, c, d]]
			for t in tris:
				var tri := PackedVector2Array(t)
				var col := LowpolyBox.shade(PAPER, tri, r, 0.035, seed, face)
				var g := (tri[0] + tri[1] + tri[2]) / 3.0
				# 가장자리까지 거리(px) — 큰 시트도 가장자리 띠만 그을린다
				var edge := minf(minf(g.x - r.position.x, r.end.x - g.x), minf(g.y - r.position.y, r.end.y - g.y))
				col = col.lerp(BURN, 0.45 * (1.0 - smoothstep(0.0, 70.0, edge)))
				_add_tri(tri, col)
				face += 1
	var outline := PackedVector2Array()
	for j in rows + 1:
		outline.append(grid[j][cols])
	for j in range(rows, -1, -1):
		outline.append(grid[j][0])
	outline.append(grid[0][cols])
	_lines.append([outline, LowpolyBox.edge_color(PAPER), 1.5])


## 말린 종이 축 하나(r = 축 전체 폭 — 손잡이 포함): 원통 띠 + 양끝 말린 단면 + 금빛 고리 + 나무 손잡이.
func _roll(r: Rect2) -> void:
	var body := Rect2(r.position.x + knob_w, r.position.y, r.size.x - knob_w * 2.0, r.size.y)
	var bands := [[0.0, 0.14, -0.02], [0.14, 0.34, 0.16], [0.34, 0.56, 0.05], [0.56, 0.8, -0.08], [0.8, 1.0, -0.22]]  # [위, 아래, 밝기]
	for bd in bands:
		var y0: float = body.position.y + body.size.y * bd[0]
		var y1: float = body.position.y + body.size.y * bd[1]
		var col := ROLL.lightened(bd[2]) if bd[2] >= 0.0 else ROLL.darkened(-bd[2])
		_tri_rect(Rect2(body.position.x, y0, body.size.x, y1 - y0), col)
	var o := LowpolyBox.octagon(body, minf(5.0, body.size.y * 0.3))
	o.append(o[0])
	_lines.append([o, LowpolyBox.edge_color(ROLL), 1.5])
	var h := r.size.y
	var cy := r.get_center().y
	for side in [-1.0, 1.0]:
		var x_end: float = body.position.x if side < 0.0 else body.end.x  # 축 끝
		# 말린 단면: 겹친 8각형 셋(바깥 종이 → 안쪽 말린 층 → 가운데 심)
		var ew := h * 0.36
		for k in 3:
			var f: float = [1.0, 0.66, 0.3][k]
			var cap := Rect2(x_end - ew * f * 0.5, cy - h * 0.5 * f, ew * f, h * f)
			var col: Color = [ROLL.lightened(0.1), ROLL.darkened(0.12), WOOD.lightened(0.1)][k]
			var co := LowpolyBox.octagon(cap, minf(cap.size.x, cap.size.y) * 0.3)
			_fan(co, cap.get_center(), col, cap, 0.06, k)
			co.append(co[0])
			_lines.append([co, LowpolyBox.edge_color(col), 1.0])
		# 금빛 고리 + 나무 손잡이(단면 바깥쪽)
		var ring_w := 4.0
		var rx: float = x_end - ew * 0.5 - ring_w if side < 0.0 else x_end + ew * 0.5
		var ring := Rect2(rx, cy - h * 0.2, ring_w, h * 0.4)
		_tri_rect(Rect2(ring.position.x, ring.position.y, ring_w, ring.size.y * 0.45), GOLD.lightened(0.15))
		_tri_rect(Rect2(ring.position.x, ring.position.y + ring.size.y * 0.45, ring_w, ring.size.y * 0.55), GOLD.darkened(0.12))
		var knob := Rect2(r.position.x, cy - h * 0.32, ring.position.x - r.position.x, h * 0.64)
		if side > 0.0:
			knob = Rect2(ring.end.x, cy - h * 0.32, r.end.x - ring.end.x, h * 0.64)
		if knob.size.x < 3.0:
			continue
		var ko := LowpolyBox.octagon(knob, minf(4.0, knob.size.x * 0.45))
		_fan(ko, knob.get_center() + Vector2(-knob.size.x * 0.15, -knob.size.y * 0.15), WOOD, knob, 0.14, 7)
		ko.append(ko[0])
		_lines.append([ko, LowpolyBox.edge_color(WOOD), 1.2])


## 볼록 다각형 poly를 c에서 부채꼴 삼각형으로(면마다 LowpolyBox.shade).
func _fan(poly: PackedVector2Array, c: Vector2, base: Color, r: Rect2, facet: float, s: int) -> void:
	for i in poly.size():
		var tri := PackedVector2Array([c, poly[i], poly[(i + 1) % poly.size()]])
		_add_tri(tri, LowpolyBox.shade(base, tri, r, facet, seed + s, i))


## 지금까지 모은 삼각형·선을 한 층으로 넣고 새 층을 시작한다(Packed 배열은 값으로 복사되니 다 모은 뒤에 넣는다).
func _end_layer() -> void:
	_layers.append([_pts, _cols, _lines])
	_reset_layer()


func _reset_layer() -> void:
	_pts = PackedVector2Array()
	_cols = PackedColorArray()
	_lines = []


func _tri_rect(r: Rect2, col: Color) -> void:
	_add_tri(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end]), col)
	_add_tri(PackedVector2Array([r.position, r.end, Vector2(r.position.x, r.end.y)]), col)


func _add_tri(tri: PackedVector2Array, col: Color) -> void:
	for p in tri:
		_pts.append(p)
		_cols.append(col)

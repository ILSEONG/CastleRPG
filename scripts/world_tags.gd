extends Node2D
## 월드 이름표(개정 15 다듬기): 건물 "이름 Lv N"·상인 "상인"을 Label3D 대신 화면 공간에서 한 번에 그린다
## (hp_bars·badges 방식 — 줌·회전과 무관하게 글자 NAME_SIZE 논리 px). 태그 = 로우폴리 알약(크림 8각 면 분할, 건물은 오른쪽에 짙은 "Lv N" 칸).
## 자리: 기준점(anchor — 지붕·머리·문루 위 월드 좌표)의 화면 위치 바로 위. 태그 위에는 badges.gd의 건설 막대·말풍선이 쌓인다 —
## 태그와 한 덩어리(stack, 크기는 badges.stack_size)로 놓고, badges는 top(id)(태그 윗변 가운데)에서 그린다.
## 매 프레임 겹침 피하기(place, 욕심쟁이 한 번): 기준점이 화면 아래인 덩어리부터 놓고, 이미 놓은 덩어리와 GAP보다 가까우면 그 위로 민다.
## 밀려 올라간 덩어리도 건물까지 잇는 선(지시선)은 긋지 않는다.
## 많이 축소하면(카메라 폭 > NAMES_HIDE_SIZE) 이름표는 그리지 않는다(자리도 차지하지 않는다) — 막대·말풍선만 기준점 위에 남는다.
## 그리기 호출 상한: 알약 삼각형 전부 canvas_item_add_triangle_array 한 번 + 외곽선 draw_multiline 한 번 +
## 태그마다 글자 ≤ 2(태그 ≤ MAX_TAGS). layout()은 프레임마다 한 번만 계산한다(badges가 먼저 불러도 같은 결과).

const Formation := preload("res://scripts/formation.gd")
const GameData := preload("res://scripts/game_data.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const UiKit := preload("res://scripts/ui_kit.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const NAME_SIZE := 20  # 건물·상인 이름(논리 px, 720 폭 기준)
const SIDE_SIZE := 18  # 문루 방향 글자
const LV_SIZE := 14
const TAG_H := 25.0  # 디자인 보강 7번: 28 → 25(알약을 납작하게 — 성을 덜 가린다)
const SIDE_H := 26.0
const PAD_X := 7.0
const LV_PAD := 4.0  # Lv 칸 안 글자 좌우 여백
const LV_INSET := 3.0  # Lv 칸이 알약 테두리에서 들어간 양
const CHAMFER := 6.0
const GAP := 3.0  # 덩어리 사이 최소 간격(px)
const EDGE_PAD := 4.0  # 화면 좌우 끝과 덩어리 사이 최소 여백(px)
const MOVED_PX := 8.0  # 이보다 많이 밀린 덩어리는 "밀렸다"(테스트용 — 지시선은 없다)
const NAMES_HIDE_SIZE := 95.0  # 카메라 가로 폭(m)이 이보다 넓으면(많이 축소) 이름표를 그리지 않는다(기본 66, 최대 150)
const MAX_TAGS := 16  # 한 프레임에 그리는 태그 상한(지금 건물 10 + 상인 + 문루 4 = 15)
const SCREEN_MARGIN := 80.0  # 기준점이 화면 밖 이만큼까지는 그린다
const FILL := UiKit.CREAM
const LV_FILL := Color(0.29, 0.35, 0.45)
const EDGE := UiKit.OUTLINE

var camera: Camera3D
var scenery  # buildings.gd — tag_anchors·merchant_anchor
var castle  # castle.gd — side_anchors
var badges  # badges.gd — stack_size(id, now): 태그 위에 쌓을 막대·말풍선 크기. 없으면 태그만

var tags: Array = []  # [{id, anchor, name, lv, font, size, pts, cols, segs, name_pos, lv_pos}] (건물 → 상인 → 문루 순)
var rects := {}  # id → 이번 프레임 태그 알약 Rect2(화면 밖이면 없음)
var stacks := {}  # id → 이번 프레임 덩어리 Rect2(태그 + 위에 쌓인 것)
var desired := {}  # id → 겹침 피하기 전 덩어리 Rect2(테스트용)
var draw_calls := 0  # 지난 그리기의 그리기 호출 수(테스트용)
var names_hidden := false  # 이번 프레임 많이 축소해 이름표를 숨겼다 — 막대·말풍선은 기준점 바로 위에 그대로 쌓인다

var _frame := -1


func _ready() -> void:
	for id in scenery.tag_anchors:
		tags.append({"id": id, "anchor": scenery.tag_anchors[id]})
	tags.append({"id": "merchant", "anchor": scenery.merchant_anchor})
	for side in castle.side_anchors.size():
		tags.append({"id": "gate:%d" % side, "anchor": castle.side_anchors[side]})
	_sync()
	Economy.changed.connect(_sync)


func _process(_delta: float) -> void:
	queue_redraw()


## 태그 글자 "이름 Lv N"(건물), "상인", "북"… 모르는 id면 "".
func text(id: String) -> String:
	for t in tags:
		if t.id == id:
			return (t.name + " " + t.lv).strip_edges()
	return ""


## 이번 프레임 태그 알약 윗변 가운데(badges가 막대·말풍선을 그 위에 쌓는다). 화면 밖이라 안 놓았으면 null.
func top(id: String):
	layout()
	return Vector2(rects[id].get_center().x, rects[id].position.y) if rects.has(id) else null


## 글자를 Economy(건물 레벨)에 맞추고, 바뀐 태그만 모양(로컬 삼각형·외곽선·글자 자리)을 다시 만든다.
func _sync() -> void:
	for t in tags:
		var nm := ""
		var lv := ""
		if t.id == "merchant":
			nm = "상인"
		elif t.id.begins_with("gate:"):
			nm = ""  # 문루 방향 글자는 그리지 않는다 — 태그는 크기 0 기준점으로만 남아 성문 건설 막대를 받친다
		else:
			nm = GameData.building_def(t.id).get("name", t.id)
			lv = "Lv %d" % Economy.building_level(t.id) if Economy.is_built(t.id) else "공터"  # 튜토리얼 공터
		if nm != t.get("name") or lv != t.get("lv"):
			t.name = nm
			t.lv = lv
			_shape(t)


## 태그 모양(원점 = 알약 왼위): 크림 8각 면 분할 16삼각형 + Lv 칸 8각 부채꼴 6삼각형, 외곽선 8선분, 글자 기준선 자리.
static func _shape(t: Dictionary) -> void:
	if t.name == "" and t.lv == "":  # 글자 없는 태그(문루): 자리 차지·그리기 없이 기준점만
		t.font = SIDE_SIZE
		t.size = Vector2.ZERO
		t.pts = PackedVector2Array()
		t.cols = PackedColorArray()
		t.segs = PackedVector2Array()
		t.name_pos = Vector2.ZERO
		t.lv_pos = Vector2.ZERO
		return
	var side: bool = t.id.begins_with("gate:")
	t.font = SIDE_SIZE if side else NAME_SIZE
	var h := SIDE_H if side else TAG_H
	var name_w := FONT.get_string_size(t.name, HORIZONTAL_ALIGNMENT_LEFT, -1, t.font).x
	var lv_w := FONT.get_string_size(t.lv, HORIZONTAL_ALIGNMENT_LEFT, -1, LV_SIZE).x + LV_PAD * 2.0 if t.lv != "" else 0.0
	var w := PAD_X + name_w + (5.0 + lv_w + LV_INSET if t.lv != "" else PAD_X)
	t.size = Vector2(ceilf(maxf(w, h)), h)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for f in LowpolyBox.faces(Rect2(Vector2.ZERO, t.size), CHAMFER, FILL, 0.06, hash(t.id) & 0xffff):
		pts.append_array(f[0])
		cols.append_array(PackedColorArray([f[1], f[1], f[1]]))
	var lv_rect := Rect2(t.size.x - LV_INSET - lv_w, LV_INSET, lv_w, h - LV_INSET * 2.0)
	if t.lv != "":
		var lo := LowpolyBox.octagon(lv_rect, 4.0)
		for i in range(1, 7):
			pts.append_array(PackedVector2Array([lo[0], lo[i], lo[i + 1]]))
			cols.append_array(PackedColorArray([LV_FILL, LV_FILL, LV_FILL]))
	t.pts = pts
	t.cols = cols
	var o := LowpolyBox.octagon(Rect2(Vector2.ZERO, t.size), CHAMFER)
	var segs := PackedVector2Array()
	for i in 8:
		segs.append(o[i])
		segs.append(o[(i + 1) % 8])
	t.segs = segs
	var base := func(size: int) -> float: return (h + FONT.get_ascent(size) - FONT.get_descent(size)) / 2.0
	t.name_pos = Vector2((t.size.x - name_w) / 2.0 if t.lv == "" else PAD_X, base.call(t.font))
	t.lv_pos = Vector2(lv_rect.position.x + LV_PAD, base.call(LV_SIZE))


## 이번 프레임 자리 계산(프레임마다 한 번 — force면 다시): 화면 안 태그의 덩어리를 기준점 위에 두고 place로 겹침을 피한다.
func layout(force := false) -> void:
	var f := Engine.get_process_frames()
	if (f == _frame and not force) or camera == null:
		return
	_frame = f
	rects.clear()
	stacks.clear()
	desired.clear()
	var view := get_viewport_rect().grow(SCREEN_MARGIN)
	var now := Economy.time_now()
	names_hidden = camera.size > NAMES_HIDE_SIZE
	var shown := []  # [태그, 기준점 화면 위치]
	var want := []
	for t in tags:
		if shown.size() >= MAX_TAGS:
			break
		var p := camera.unproject_position(t.anchor)
		if not view.has_point(p):
			continue
		var extra: Vector2 = badges.stack_size(t.id, now) if badges != null else Vector2.ZERO
		var tsz: Vector2 = Vector2.ZERO if names_hidden else t.size  # 숨기면 이름표 자리 없이 막대·말풍선만
		var w := maxf(tsz.x, extra.x)
		var h: float = tsz.y + extra.y
		want.append(Rect2(p.x - w / 2.0, p.y - h, w, h))
		shown.append([t, p])
	var placed := place(_inside(want, shown.map(func(e): return e[1].x)))
	for i in shown.size():
		var t: Dictionary = shown[i][0]
		var s: Rect2 = placed[i]
		desired[t.id] = want[i]
		stacks[t.id] = s
		var tsz: Vector2 = Vector2.ZERO if names_hidden else t.size
		rects[t.id] = Rect2(Vector2(s.get_center().x - tsz.x / 2.0, s.end.y - tsz.y), tsz)


## 기준점이 화면 안인 덩어리가 화면 좌우 끝에 잘리면 EDGE_PAD만큼 안으로 민다(디자인 보강 7번 — "궁병 훈련소"가 오른쪽에서 잘렸다).
## 기준점이 화면 밖인 덩어리는 그대로 두어 자연스럽게 밀려 나간다. desired는 밀기 전 자리 그대로다.
func _inside(want: Array, xs: Array) -> Array:
	var vw := get_viewport_rect().size.x
	var out := []
	for i in want.size():
		var r: Rect2 = want[i]
		if xs[i] >= 0.0 and xs[i] <= vw and r.size.x < vw - EDGE_PAD * 2.0:
			r.position.x = clampf(r.position.x, EDGE_PAD, vw - EDGE_PAD - r.size.x)
		out.append(r)
	return out


## 욕심쟁이 겹침 피하기(순수 함수). want[i] = 덩어리 i가 가고 싶은 화면 상자(아랫변 = 기준점). 아랫변이 화면 아래인 것부터 놓고,
## 놓은 상자와 gap보다 가까우면 그 위로 민다(위로만 움직여 반드시 끝난다). 반환 = 같은 순서의 최종 상자.
## (개정 21: 방치 모드에 병사 대열이 없어 병사 장애물은 뺐다.)
static func place(want: Array, gap := GAP) -> Array:
	var order := range(want.size())
	order.sort_custom(func(a, b): return want[a].end.y > want[b].end.y or (want[a].end.y == want[b].end.y and want[a].position.x < want[b].position.x))
	var out := []
	out.resize(want.size())
	var placed := []
	for i in order:
		var r: Rect2 = want[i]
		for _guard in placed.size() + 1:
			var hit = null
			for q in placed:
				if _near(r, q, gap):
					hit = q
					break
			if hit == null:
				break
			r.position.y = hit.position.y - gap - r.size.y
		placed.append(r)
		out[i] = r
	return out


## 두 상자가 gap보다 가깝다(겹친다).
static func _near(a: Rect2, b: Rect2, gap: float) -> bool:
	return a.grow(gap * 0.5).intersects(b.grow(gap * 0.5))


func _draw() -> void:
	layout()
	draw_calls = 0
	if rects.is_empty():
		return
	if names_hidden:
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var segs := PackedVector2Array()
	for t in tags:
		if rects.has(t.id):
			var xf := Transform2D(0.0, rects[t.id].position)
			pts.append_array(xf * t.pts)
			cols.append_array(t.cols)
			segs.append_array(xf * t.segs)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(), pts, cols)
	draw_multiline(segs, EDGE, 1.5, true)
	draw_calls += 2
	for t in tags:
		if not rects.has(t.id) or t.name == "":
			continue
		var o: Vector2 = rects[t.id].position
		draw_string(FONT, o + t.name_pos, t.name, HORIZONTAL_ALIGNMENT_LEFT, -1, t.font, UiKit.INK)
		draw_calls += 1
		if t.lv != "":
			draw_string(FONT, o + t.lv_pos, t.lv, HORIZONTAL_ALIGNMENT_LEFT, -1, LV_SIZE, Color.WHITE)
			draw_calls += 1

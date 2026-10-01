extends Node2D
## 유닛 머리 위 실시간 HP 바(아군·적군). 매 프레임 두 그룹을 돌며 화면 공간에 한 번에 그린다 —
## 유닛마다 노드를 두지 않아 몬스터가 많아도 가볍다. HUD(CanvasLayer)보다 아래 캔버스에 그려진다.
## 바는 모서리를 깎은 8각형(배경 + 채움)이고, 프레임의 모든 바를 삼각형 배열 하나(canvas_item_add_triangle_array 한 번)로 그린다.
## 정점·색·인덱스 배열은 멤버로 재사용한다(유닛마다 배열을 만들지 않는다). 인덱스는 8각형 칸마다 고정된 부채꼴이라 늘어날 때만 채운다.
## 유닛 인터페이스: is_alive(), hp_ratio(), bar_height(), bar_scale(). 영웅은 selected·def(이름표)도.

const BAR_W := 34.0           # 논리 px(720 폭 기준). 줌과 무관
const BAR_H := 5.0
const BORDER := 1.5
const CHAMFER := 1.5          # 바 모서리 깎기 px
const SCREEN_MARGIN := 40.0   # 화면 밖 이만큼까지는 그린다(가장자리 걸친 유닛)
const HERO_COLOR := Color(0.35, 0.85, 0.40)
const MONSTER_COLOR := Color(0.92, 0.28, 0.22)
const BACK := Color(0, 0, 0, 0.55)
const NAME_SIZE := 20
const NAME_OUTLINE := Color(0.12, 0.10, 0.14)
const Art := preload("res://scripts/art.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

var camera: Camera3D
var octagons := 0  # 지난 프레임에 그린 8각형 수(테스트용)

var _pts := PackedVector2Array()
var _cols := PackedColorArray()
var _idx := PackedInt32Array()
var _n := 0  # 이번 프레임에 채운 8각형 수


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if camera == null:
		return
	var view := get_viewport_rect().grow(SCREEN_MARGIN)
	_n = 0
	_add_group("heroes", HERO_COLOR, view)
	_add_group("monsters", MONSTER_COLOR, view)
	if _flush():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _idx, _pts, _cols)
	_draw_name_tags(view)


func _add_group(group: String, color: Color, view: Rect2) -> void:
	for u in get_tree().get_nodes_in_group(group):
		if not u.is_alive():
			continue
		var p := camera.unproject_position(u.global_position + Vector3(0, u.bar_height(), 0))
		if not view.has_point(p):
			continue
		var w: float = BAR_W * u.bar_scale()
		var top_left := p - Vector2(w / 2.0, BAR_H / 2.0)
		# 각진 테두리: 배경 8각형(테두리만큼 크게) 위에 채움 8각형
		add_octagon(top_left - Vector2(BORDER, BORDER), Vector2(w + BORDER * 2.0, BAR_H + BORDER * 2.0), CHAMFER + BORDER, BACK)
		var fw := w * clampf(u.hp_ratio(), 0.0, 1.0)
		if fw > 0.5:
			add_octagon(top_left, Vector2(fw, BAR_H), CHAMFER, color)


## 8각형 하나(LowpolyBox.octagon과 같은 점 순서: 윗변 왼쪽부터 시계 방향)를 이번 프레임 배열에 더한다. 배열은 모자랄 때만 늘린다.
func add_octagon(pos: Vector2, size: Vector2, chamfer: float, color: Color) -> void:
	var b := _n * 8
	if _pts.size() < b + 8:
		_pts.resize(maxi(64, _pts.size() * 2))
		_cols.resize(_pts.size())
	var c := clampf(chamfer, 0.0, minf(size.x, size.y) * 0.5)
	var x0 := pos.x
	var y0 := pos.y
	var x1 := pos.x + size.x
	var y1 := pos.y + size.y
	_pts[b] = Vector2(x0 + c, y0)
	_pts[b + 1] = Vector2(x1 - c, y0)
	_pts[b + 2] = Vector2(x1, y0 + c)
	_pts[b + 3] = Vector2(x1, y1 - c)
	_pts[b + 4] = Vector2(x1 - c, y1)
	_pts[b + 5] = Vector2(x0 + c, y1)
	_pts[b + 6] = Vector2(x0, y1 - c)
	_pts[b + 7] = Vector2(x0, y0 + c)
	for i in 8:
		_cols[b + i] = color
	_n += 1


## 이번 프레임 배열을 그릴 길이로 맞춘다(정점 8개·인덱스 18개 × 8각형 수). 그릴 게 없으면 false.
## 줄어들어도 다시 늘 때 인덱스(칸마다 고정)는 새 칸만 채운다.
func _flush() -> bool:
	octagons = _n
	if _n == 0:
		return false
	_pts.resize(_n * 8)
	_cols.resize(_n * 8)
	var had := _idx.size() / 18
	_idx.resize(_n * 18)
	for k in range(had, _n):
		for t in 6:  # 부채꼴: 0번 점과 (t+1, t+2)
			_idx[k * 18 + t * 3] = k * 8
			_idx[k * 18 + t * 3 + 1] = k * 8 + t + 1
			_idx[k * 18 + t * 3 + 2] = k * 8 + t + 2
	return true


## 선택된 영웅 머리 위(HP 바 위) "칭호 이름"을 등급 색으로(진한 외곽선).
func _draw_name_tags(view: Rect2) -> void:
	for u in get_tree().get_nodes_in_group("heroes"):
		if not u.selected or not u.is_alive():
			continue
		var p := camera.unproject_position(u.global_position + Vector3(0, u.bar_height(), 0))
		if not view.has_point(p):
			continue
		var text := "%s %s" % [u.def.title, u.def.name]
		var font: Font = FONT
		var pos := p + Vector2(-font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x / 2.0, -BAR_H - 8.0)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, 6, NAME_OUTLINE)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, Art.GRADE_COLORS[u.def.grade])

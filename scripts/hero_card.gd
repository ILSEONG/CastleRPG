extends Button
## 영웅 카드(스펙 §5): 등급 색 테두리 로우폴리 카드 + 위쪽 등급 보석 + 영웅 피규어(개정 14 §2, Portraits — 렌더 전엔 등급 색 실루엣)와
## 발밑 고유 색 받침 원판 + 이름·칭호 + 아래 badge(NEW·+1 조각) 또는 금색 별(개정 15: 별 = 승급 단계). live(상세 큰 카드)면 피규어가 실시간(대기 애니메이션)이고 가로로 끌면 돈다 —
## 끌기는 카드가 먹어 상세의 좌우 스와이프로 새지 않는다. 보일 때만 Portraits에 미리보기를 건다(목록으로·창 닫힘이면 내린다).
## SSR은 금색 면이 반짝인다(면 밝기 순환). hero_id가 ""이면 빈 슬롯 칸. 짧게 누르면 tapped, LONG_PRESS_MS 이상 눌렀다 떼면 long_pressed.
## 바탕·보석·별 지오메트리는 (크기, 영웅, 별)이 바뀔 때만 만들고(_ensure_geo), 그리기는 삼각형 배열 몇 번이다 — SSR은 매 프레임
## 다시 그리므로 반짝임은 색 배열의 알파만 바꾼다. 창이 닫혀 안 보이면 다시 그리지 않는다.
## 입력은 부모로도 넘긴다(MOUSE_FILTER_PASS) — 스크롤 격자 안에서 끌어 스크롤할 수 있게.
## 개정 11 영웅 목록: level > 0이면 왼위 "Lv N", power > 0이면 아래 "전투력 N", deployed면 "배치" 배지, can_level이면 오른위 초록 ▲(다각형).
## burst(): 레벨업 성공 연출 — 빛 조각이 BURST_SEC 동안 가운데에서 퍼진다.
## 개정 15: shards ≥ 0이면 맨 아래 조각 막대 "조각 3 / 5"(shard_need 0 = 최대 승급 "MAX"), can_promote면 오른위 ▲ 아래 금색 ⬆.
## live(상세 큰 카드)는 피규어가 카드 대부분을 채우고(figure_rect) 이름·칭호는 그리지 않는다(상세 글자가 보여 준다), 별은 아래에 크게.
## promote_fx(): 승급 성공 연출 — 피규어 주위로 금색 로우폴리 빛 조각이 퍼지고, 새 별 하나가 날아와 제자리에 박힌다(PROMOTE_FX_SEC).
## 디자인 보강 5번(2026-10-07): 목록·슬롯·모집 카드(live 아님)는 전신 피규어 대신 얼굴이 크게 보이는 흉상(Portraits "bust:")을
## 등급 색 초상화 창(portrait_rect — 위가 밝은 등급 색 그러데이션 + 깎은 면, SR은 빛살, SSR은 도는 금빛 빛살)에 꽉 채워 그리고,
## 창 아래 띠가 영웅 고유 색이다(받침 원판은 live 큰 카드만).

const UiKit := preload("res://scripts/ui_kit.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const GameData := preload("res://scripts/game_data.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const LONG_PRESS_MS := 500
const SHIMMER_SPEED := 4.0
const STAR_COLOR := Color("F2B233")
const HIGHLIGHT := Color("F9B233")
const UP_COLOR := Color(0.2, 0.72, 0.3)  # 레벨업 가능 ▲
const BURST_SEC := 0.5
const BURST_SHARDS := 14
const FIGURE_TOP := 14.0  # 피규어 칸 위 끝(등급 보석 아래)
const BASE_SIDES := 10  # 받침 원판 각 수
const BAR_H := 16.0  # 조각 막대 높이(개정 15)
const BAR_GAP := 4.0
const BAR_FILL := Color("9B6CD6")  # 조각 막대 채움(SR 보라 — 레벨 막대 호박색과 구분)
const LIVE_BAND := 48.0  # 큰 카드 아래 별 줄 높이
const LIVE_STAR_R := 15.0
const PROMOTE_FX_SEC := 0.9
const STAR_FLY_SEC := 0.55  # 별이 날아오는 시간(그 뒤 박히는 반짝임)
const PROMOTE_SHARDS := 22
const WIN_INSET := 8.0  # 초상화 창: 카드 테두리 안쪽 여백
const WIN_TOP := 9.0
const WIN_CHAMFER := 7.0  # 창 위 모서리만 깎는다(흉상 아래는 곧게 잘린다)
const BAND_H := 5.0  # 창 아래 고유 색 띠
const FACE_AT := 0.45  # 창 세로에서 얼굴 가운데가 올 비율
const RAYS := 10  # SR·SSR 창 빛살 수

signal tapped(card)
signal long_pressed(card)

var hero_id := "":
	set(v):
		hero_id = v
		_update_process()
		_sync_live()
		queue_redraw()
var live := false:  # 상세 큰 카드: 같은 SubViewport 실시간 미리보기
	set(v):
		live = v
		_sync_live()
var badge := ""  # 아래 줄 글자("NEW"). 비면 별
var stars := 0
var corner := ""  # 왼위 작은 글자(슬롯 번호)
var highlight := false  # 고른 슬롯·카드: 호박색 테두리
var empty_text := "빈 칸"
var level := 0  # > 0이면 "Lv N"
var power := 0  # > 0이면 "전투력 N"
var deployed := false  # "배치" 배지
var can_level := false  # 오른위 초록 ▲
var shards := -1  # ≥ 0이면 아래 조각 막대(개정 15)
var shard_need := 0  # 다음 승급에 드는 조각. 0 = 최대 승급("MAX")
var can_promote := false  # 오른위 금색 ⬆(승급 가능)
var badge_color := Color("D9480F")  # badge 글자색(NEW 주황, 모집 창이 "+1 조각"에 보라로 바꾼다)
var promote_fxs := 0  # 승급 연출 횟수(테스트용)

var geo_builds := 0  # 지오메트리를 만든 횟수(테스트용)

var _down_ms := 0
var _t := 0.0
var _burst := 0.0  # 남은 빛 조각 시간
var _pfx := 0.0  # 남은 승급 연출 시간
var _flying := -1  # 날아오는 중인 별 번호(그동안 그 자리 별은 지오메트리에서 뺀다), 없으면 -1
var _geo_key := []
var _body := PackedVector2Array()  # 카드 바탕(테두리 8각 + 안쪽 면) 삼각형 점(3개씩)
var _body_cols := PackedColorArray()
var _edge := PackedVector2Array()  # 카드 외곽선(닫힘)
var _shine := PackedVector2Array()  # SSR 반짝임 면
var _shine_cols := PackedColorArray()  # 매 프레임 알파만 바꾼다
var _base := PackedVector2Array()  # 피규어 아래: 고유 색 받침 원판(옆면 + 윗면)
var _base_cols := PackedColorArray()
var _base_lines: Array = []  # 받침 외곽선(윗면 둘레, 옆면 아래 둘레)
var _win := PackedVector2Array()  # 초상화 창(live 아님): 등급 색 바탕 + 깎은 면 + 아래 고유 색 띠
var _win_cols := PackedColorArray()
var _win_edge := PackedVector2Array()  # 창 테두리(닫힘)
var _top := PackedVector2Array()  # 피규어 위: 등급 보석·별
var _top_cols := PackedColorArray()
var _lines: Array = []  # [[닫힌 선, 두께]] 보석·별 외곽선


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # 피규어(256px, 밉맵)를 1/2~1/5로 줄여 그린다
	button_down.connect(func(): _down_ms = Time.get_ticks_msec())
	pressed.connect(_on_pressed)


func _ready() -> void:
	hero_id = hero_id  # _process가 있으면 엔진이 처리를 켠다 — SSR만 켜 둔다
	if PortraitsScript.current != null:
		PortraitsScript.current.portrait_ready.connect(func(key): if key == _key(): queue_redraw())


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_EXIT_TREE:
		_sync_live(what == NOTIFICATION_EXIT_TREE)


func _key() -> String:
	return "hero:" + hero_id


## live 카드가 보이면 그 영웅을 실시간 미리보기로 건다. 안 보이거나(목록·창 닫힘) 트리를 떠나면 내린다.
func _sync_live(leaving := false) -> void:
	var p = PortraitsScript.current
	if live and p != null:
		var on := not leaving and hero_id != "" and is_inside_tree() and is_visible_in_tree()
		p.set_live(_key() if on else "")


## live 카드: 가로로 끌면 모델이 돈다. 누름·끌기·뗌을 여기서 먹는다(상세의 좌우 스와이프로 새지 않게).
func _gui_input(event: InputEvent) -> void:
	if not live or not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	var mm := event as InputEventMouseMotion
	if mm != null and mm.button_mask & MOUSE_BUTTON_MASK_LEFT and PortraitsScript.current != null:
		PortraitsScript.current.turn(mm.relative.x)
	accept_event()


func _process(delta: float) -> void:
	if _burst > 0.0:
		_burst -= delta
		if _burst <= 0.0:
			_update_process()
	if _pfx > 0.0:
		_pfx -= delta
		if _flying >= 0 and _pfx <= PROMOTE_FX_SEC - STAR_FLY_SEC:
			_flying = -1  # 박혔다 — 그 자리 별을 다시 그린다
		if _pfx <= 0.0:
			_update_process()
	if not is_visible_in_tree():
		return  # 닫힌 창의 카드는 다시 그리지 않는다
	_t += delta
	queue_redraw()


## SSR(반짝임)이거나 빛 조각·승급 연출이 남았을 때만 매 프레임 다시 그린다.
func _update_process() -> void:
	set_process(_burst > 0.0 or _pfx > 0.0 or (hero_id != "" and GameData.hero(hero_id).get("grade", "") == "SSR"))


## 레벨업 성공 연출: 빛 조각이 가운데에서 BURST_SEC 동안 퍼지며 사라진다.
func burst() -> void:
	_burst = BURST_SEC
	_update_process()


func is_bursting() -> bool:
	return _burst > 0.0


## 승급 성공 연출: 금색 빛 조각이 피규어 주위로 퍼지고, 마지막 별(stars번째)이 위에서 날아와 박힌다. stars를 새 승급으로 둔 뒤 부른다.
func promote_fx() -> void:
	_pfx = PROMOTE_FX_SEC
	_flying = stars - 1
	promote_fxs += 1
	_update_process()
	queue_redraw()


func is_promoting() -> bool:
	return _pfx > 0.0


func _on_pressed() -> void:
	if Time.get_ticks_msec() - _down_ms >= LONG_PRESS_MS:
		long_pressed.emit(self)
	else:
		tapped.emit(self)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var h := GameData.hero(hero_id) if hero_id != "" else {}
	if h.is_empty():
		draw_colored_polygon(LowpolyBox.octagon(r.grow(-3.0), 10.0), Color(UiKit.INK, 0.08))
		_outline(r.grow(-3.0), Color(UiKit.INK, 0.35), 2.0)
		_text(empty_text, size.y * 0.55, 18, Color(UiKit.INK, 0.5))
	else:
		_ensure_geo(h)
		var ci := get_canvas_item()
		RenderingServer.canvas_item_add_triangle_array(ci, PackedInt32Array(), _body, _body_cols)
		draw_polyline(_edge, UiKit.OUTLINE, UiKit.CARD_OUTLINE_W, true)
		if not _shine.is_empty():  # SSR: 금색 면이 차례로 밝아진다
			_tick_shine(UiKit.GRADE_COLORS[h.grade])
			RenderingServer.canvas_item_add_triangle_array(ci, PackedInt32Array(), _shine, _shine_cols)
		if live:  # 큰 카드: 받침 원판 위 실시간 전신
			RenderingServer.canvas_item_add_triangle_array(ci, PackedInt32Array(), _base, _base_cols)
			for l in _base_lines:
				draw_polyline(l, UiKit.OUTLINE, 1.2, true)
			draw_texture_rect(figure_texture(), figure_rect(), false)
		else:  # 목록·슬롯·모집: 등급 색 창에 흉상
			RenderingServer.canvas_item_add_triangle_array(ci, PackedInt32Array(), _win, _win_cols)
			if h.grade == "SSR" or h.grade == "SR":
				_draw_rays(UiKit.GRADE_COLORS[h.grade], h.grade == "SSR")
			var tex := figure_texture()
			var wr := portrait_rect()
			draw_texture_rect_region(tex, wr, bust_region(tex.get_size(), wr.size))
			draw_polyline(_win_edge, Color(UiKit.GRADE_COLORS[h.grade]).darkened(0.35), 1.5, true)
		RenderingServer.canvas_item_add_triangle_array(ci, PackedInt32Array(), _top, _top_cols)
		for l in _lines:
			draw_polyline(l[0], UiKit.OUTLINE, l[1], true)
		var name_size := _name_size()
		if not live:  # 큰 카드는 상세 글자가 이름·칭호를 보여 준다
			_text(h.name, size.y * 0.6, name_size, UiKit.INK)
			_text(h.title, size.y * 0.6 + name_size * 0.95, maxi(11, name_size - 7), UiKit.INK.lightened(0.3))
		if badge != "":
			_text(badge, size.y - 10.0 - _bar_space(), name_size - 2, badge_color, true)
		_draw_list_info()
		_draw_shard_bar()
	if _burst > 0.0:
		_draw_burst()
	if _pfx > 0.0 and not h.is_empty():
		_draw_promote_fx()
	if corner != "":
		draw_string_outline(FONT, Vector2(9, 22), corner, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.WHITE)
		draw_string(FONT, Vector2(9, 22), corner, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.INK)
	if highlight:
		_outline(r.grow(1.0), HIGHLIGHT, 5.0)


func _name_size() -> int:
	return clampi(roundi(size.x * 0.17), 14, 24)


## 피규어 칸: live(상세 큰 카드)는 보석 아래 ~ 별 줄 위를 거의 다 채우는 정사각, 아니면 초상화 창(portrait_rect).
func figure_rect() -> Rect2:
	if live:
		var h := size.y - FIGURE_TOP - LIVE_BAND
		var s := maxf(minf(size.x - 24.0, h), 0.0)
		return Rect2(size.x / 2.0 - s / 2.0, FIGURE_TOP + (h - s) / 2.0, s, s)
	return portrait_rect()


## 초상화 창(live 아님): 카드 테두리 안쪽 폭 전부, 위 테두리 아래부터 이름 글자 위(고유 색 띠 자리를 뺀다)까지.
func portrait_rect() -> Rect2:
	var bottom := size.y * 0.6 - _name_size() * 0.95 - 3.0 - BAND_H
	return Rect2(WIN_INSET, WIN_TOP, maxf(size.x - WIN_INSET * 2.0, 0.0), maxf(bottom - WIN_TOP, 0.0))


## 흉상 그림에서 창에 넣을 부분: 창을 꽉 채우고(창이 넓으면 위아래를, 좁으면 양옆을 자른다) 얼굴(Portraits.FACE_Y 조금 아래)이
## 창 세로 FACE_AT에 오게 — 영웅마다 머리 높이가 같게 렌더돼 있어 모두 같은 자리에 얼굴이 온다.
static func bust_region(tex: Vector2, win: Vector2) -> Rect2:
	if tex.x <= 0.0 or win.x <= 0.0 or win.y <= 0.0:
		return Rect2(Vector2.ZERO, tex)
	var aspect := win.x / win.y
	var h := tex.x / aspect
	if h <= tex.y:
		var face := tex.y * (PortraitsScript.FACE_Y + 0.05)
		return Rect2(0.0, clampf(face - h * FACE_AT, 0.0, tex.y - h), tex.x, h)
	var w := tex.y * aspect
	return Rect2((tex.x - w) / 2.0, 0.0, w, tex.y)


## 조각 막대 칸(맨 아래). 막대가 없으면 빈 Rect2.
func shard_bar_rect() -> Rect2:
	if shards < 0:
		return Rect2()
	return Rect2(14.0, size.y - BAR_H - 8.0, size.x - 28.0, BAR_H)


## 막대가 있으면 아래 글자·별을 그만큼 올린다.
func _bar_space() -> float:
	return BAR_H + BAR_GAP if shards >= 0 else 0.0


## 막대 글자: "조각 3 / 5", 최대 승급이면 "MAX".
func shard_text() -> String:
	return "MAX" if shard_need <= 0 else "조각 %d / %d" % [shards, shard_need]


## 별 줄 [가운데, 별 반지름]: 목록·모집은 아래(막대 위)에 작게, live는 아래 별 줄에 크게.
func _star_row() -> Array:
	if live:
		return [Vector2(size.x / 2.0, size.y - LIVE_BAND / 2.0), LIVE_STAR_R]
	return [Vector2(size.x / 2.0, size.y - 16.0 - _bar_space()), minf(9.0, size.x / 14.0)]


## i번째 별의 가운데(stars개를 가운데 맞춤).
func star_center(i: int) -> Vector2:
	var row := _star_row()
	var gap: float = row[1] * 2.1
	var c: Vector2 = row[0]
	return Vector2(c.x - gap * (stars - 1) / 2.0 + gap * i, c.y)


## 그릴 피규어: live면 실시간 미리보기(전신), 아니면 흉상 캐시(렌더 전엔 자리표시 실루엣).
func figure_texture() -> Texture2D:
	var p = PortraitsScript.current
	if live:
		return p.live_texture(_key()) if p != null else PortraitsScript.portrait(_key())
	return PortraitsScript.portrait("bust:" + hero_id)


## 창 빛살: 흉상 머리 뒤(창 위 40%)에서 창 테두리까지 번갈아 밝은 부채꼴. SSR은 천천히 돌고(매 프레임 그린다) 진하다.
func _draw_rays(gc: Color, spin: bool) -> void:
	var wr := portrait_rect()
	if wr.size.x <= 0.0:
		return
	var c := Vector2(wr.get_center().x, wr.position.y + wr.size.y * 0.4)
	var a0 := _t * 0.35 if spin else 0.0
	var col := Color(gc.lightened(0.75), 0.42 if spin else 0.26)
	var reach := wr.size.length()
	var tris := PackedVector2Array()  # 삼각형 배열(다각형 삼각분할 없이 — 모서리에 걸친 부채꼴도 깨지지 않게)
	for i in RAYS:
		var a := a0 + TAU * i / RAYS
		var p1 := _to_edge(wr, c, Vector2.from_angle(a), reach)
		var p2 := _to_edge(wr, c, Vector2.from_angle(a + TAU / RAYS * 0.45), reach)
		var corner := _corner_between(wr, p1, p2)
		if corner != Vector2.INF:
			tris.append_array([c, p1, corner, c, corner, p2])
		else:
			tris.append_array([c, p1, p2])
	var cols := PackedColorArray()
	cols.resize(tris.size())
	cols.fill(col)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(), tris, cols)


## c에서 dir로 나가 창 사각형 테두리에 닿는 점.
static func _to_edge(r: Rect2, c: Vector2, dir: Vector2, reach: float) -> Vector2:
	var t := reach
	if dir.x > 0.0001:
		t = minf(t, (r.end.x - c.x) / dir.x)
	elif dir.x < -0.0001:
		t = minf(t, (r.position.x - c.x) / dir.x)
	if dir.y > 0.0001:
		t = minf(t, (r.end.y - c.y) / dir.y)
	elif dir.y < -0.0001:
		t = minf(t, (r.position.y - c.y) / dir.y)
	return c + dir * t


## 테두리 위 두 점이 다른 변에 있으면 그 사이 모서리(부채꼴이 모서리를 감싸게), 같은 변이면 INF.
static func _corner_between(r: Rect2, a: Vector2, b: Vector2) -> Vector2:
	var ex := func(p: Vector2) -> float: return r.position.x if absf(p.x - r.position.x) < 0.5 else (r.end.x if absf(p.x - r.end.x) < 0.5 else NAN)
	var ey := func(p: Vector2) -> float: return r.position.y if absf(p.y - r.position.y) < 0.5 else (r.end.y if absf(p.y - r.end.y) < 0.5 else NAN)
	var ax: float = ex.call(a)
	var ay: float = ey.call(a)
	var bx: float = ex.call(b)
	var by: float = ey.call(b)
	if not is_nan(ax) and not is_nan(by):
		return Vector2(ax, by)
	if not is_nan(ay) and not is_nan(bx):
		return Vector2(bx, ay)
	return Vector2.INF


## 목록 카드 정보: 왼위 "Lv N"·그 아래 "배치" 배지, 오른위 초록 ▲, 별 위 "전투력 N".
func _draw_list_info() -> void:
	if level > 0:
		draw_string_outline(FONT, Vector2(10, 28), "Lv %d" % level, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 5, Color.WHITE)
		draw_string(FONT, Vector2(10, 28), "Lv %d" % level, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiKit.INK)
	if deployed:
		var chip := Rect2(8, 36, 48, 24)
		draw_colored_polygon(LowpolyBox.octagon(chip, 5.0), UiKit.AMBER)
		draw_string(FONT, Vector2(chip.position.x, chip.end.y - 6), "배치", HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 16, Color.WHITE)
	if can_level:
		var c := Vector2(size.x - 22, 22)
		var tri := PackedVector2Array([c + Vector2(0, -11), c + Vector2(11, 8), c + Vector2(-11, 8)])
		draw_colored_polygon(tri, UP_COLOR)
		tri.append(tri[0])
		draw_polyline(tri, UiKit.OUTLINE, 1.5, true)
	if can_promote:  # 승급 가능: 금색 ⬆(자루 달린 화살표 — 레벨업 ▲와 모양·색이 다르다)
		var c := Vector2(size.x - 22, 52)
		var arrow := PackedVector2Array([c + Vector2(0, -13), c + Vector2(12, 0), c + Vector2(5, 0), c + Vector2(5, 12),
			c + Vector2(-5, 12), c + Vector2(-5, 0), c + Vector2(-12, 0)])
		draw_colored_polygon(arrow, STAR_COLOR)
		arrow.append(arrow[0])
		draw_polyline(arrow, UiKit.OUTLINE, 1.5, true)
	if power > 0:
		_text("전투력 %s" % UiKit.commas(power), size.y - 34.0 - _bar_space(), 17, UiKit.INK.lightened(0.15))


## 조각 막대(개정 15): 어두운 바탕 + 보라 채움(모였거나 최대 승급이면 금색) + 가운데 흰 글자.
func _draw_shard_bar() -> void:
	var r := shard_bar_rect()
	if r.size.x <= 0.0:
		return
	draw_colored_polygon(LowpolyBox.octagon(r, 4.0), Color(UiKit.INK, 0.18))
	var full := shard_need <= 0 or shards >= shard_need
	var f := 1.0 if full else clampf(float(shards) / shard_need, 0.0, 1.0)
	if f > 0.0:
		draw_colored_polygon(LowpolyBox.octagon(Rect2(r.position, Vector2(maxf(r.size.x * f, 8.0), r.size.y)), 4.0), STAR_COLOR if full else BAR_FILL)
	var line := LowpolyBox.octagon(r, 4.0)
	line.append(line[0])
	draw_polyline(line, UiKit.OUTLINE, 1.2, true)
	var at := Vector2(r.position.x, r.end.y - 3.0)
	draw_string_outline(FONT, at, shard_text(), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13, 4, Color(UiKit.INK, 0.85))
	draw_string(FONT, at, shard_text(), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13, Color.WHITE)


## 승급 연출: 피규어 가운데에서 금색 로우폴리 조각(삼각형·사각형)이 돌며 바깥으로 퍼지고, 새 별이 카드 위에서 크게 날아와
## 제자리(star_center)에 박힌 뒤 고리가 반짝인다.
func _draw_promote_fx() -> void:
	var t := 1.0 - _pfx / PROMOTE_FX_SEC  # 0 → 1
	var fr := figure_rect()
	var c := fr.get_center()
	var base := maxf(fr.size.x, 40.0)
	for i in PROMOTE_SHARDS:
		var dir := Vector2.from_angle(TAU * i / PROMOTE_SHARDS + LowpolyBox.hash01(i, 3) * 0.5)
		var p := c + dir * base * 0.75 * (0.15 + 0.85 * t) * (0.6 + 0.4 * LowpolyBox.hash01(i, 5))
		var r := base * 0.045 * (1.0 - t * 0.5) * (0.7 + 0.6 * LowpolyBox.hash01(i, 11))
		var n := 3 if i % 2 == 0 else 4
		var col := Color("FFF3C4") if i % 3 == 0 else STAR_COLOR.lightened(0.35 * LowpolyBox.hash01(i, 13))
		col.a = 1.0 - t * t
		var pts := PackedVector2Array()
		for k in n:
			pts.append(p + Vector2.from_angle(t * 6.0 + i + TAU * k / n) * r)
		draw_colored_polygon(pts, col)
	if stars <= 0:
		return
	var sr: float = _star_row()[1]
	var home := star_center(stars - 1)
	if _flying >= 0:  # 위에서 크게 → 제자리에 작게(감속)
		var e := clampf((PROMOTE_FX_SEC - _pfx) / STAR_FLY_SEC, 0.0, 1.0)
		e = 1.0 - (1.0 - e) * (1.0 - e)
		_star(Vector2(size.x / 2.0, -sr * 2.0).lerp(home, e), sr * lerpf(3.0, 1.0, e))
	else:  # 박힌 뒤: 별 주위로 퍼지며 흐려지는 고리
		var k := clampf((PROMOTE_FX_SEC - STAR_FLY_SEC - _pfx) / (PROMOTE_FX_SEC - STAR_FLY_SEC), 0.0, 1.0)
		draw_arc(home, sr * (1.2 + 1.5 * k), 0.0, TAU, 12, Color(1, 0.95, 0.7, 1.0 - k), 3.0, true)


## 연출용 별 하나(지오메트리 캐시 밖, 매 프레임 그린다).
func _star(c: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		pts.append(c + Vector2.from_angle(-PI / 2.0 + PI * k / 5.0) * (r if k % 2 == 0 else r * 0.45))
	draw_colored_polygon(pts, STAR_COLOR)
	pts.append(pts[0])
	draw_polyline(pts, UiKit.OUTLINE, 1.5, true)


## 빛 조각: 가운데에서 바깥으로 날아가며 작아지고 흐려지는 금색·흰 삼각형. 방향은 결정적(조각 번호 해시).
func _draw_burst() -> void:
	var t := 1.0 - _burst / BURST_SEC  # 0 → 1
	var c := size / 2.0
	var reach := minf(size.x, size.y) * 0.75
	for i in BURST_SHARDS:
		var dir := Vector2.from_angle(TAU * i / BURST_SHARDS + LowpolyBox.hash01(i, 7) * 0.4)
		var p := c + dir * reach * (0.2 + 0.8 * t) * (0.7 + 0.3 * LowpolyBox.hash01(i, 9))
		var r := 9.0 * (1.0 - t * 0.6)
		var col := (HIGHLIGHT if i % 2 == 0 else Color.WHITE)
		col.a = 1.0 - t
		draw_colored_polygon(PackedVector2Array([p + dir * r, p + dir.orthogonal() * r * 0.5, p - dir.orthogonal() * r * 0.5]), col)


func _outline(r: Rect2, color: Color, width: float) -> void:
	var line := LowpolyBox.octagon(r, 10.0)
	line.append(line[0])
	draw_polyline(line, color, width, true)


## 가운데 정렬 글자(baseline y).
func _text(text: String, y: float, font_size: int, color: Color, outline := false) -> void:
	if outline:
		draw_string_outline(FONT, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, 5, Color.WHITE)
	draw_string(FONT, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, color)


## (크기, 영웅, 별, badge·막대·live·날아오는 별)이 바뀌었을 때만 지오메트리를 다시 만든다.
func _ensure_geo(h: Dictionary) -> void:
	var key := [size, hero_id, stars, badge != "", shards >= 0, live, _flying]
	if key == _geo_key:
		return
	_geo_key = key
	geo_builds += 1
	var r := Rect2(Vector2.ZERO, size)
	var gc: Color = UiKit.GRADE_COLORS[h.grade]
	var ssr: bool = h.grade == "SSR"
	var card := UiKit.facet_card_geometry(r, gc, UiKit.CREAM.lerp(gc, 0.18) if ssr else UiKit.CREAM)
	_body = card[0]
	_body_cols = card[1]
	_edge = card[2]
	_shine = PackedVector2Array()
	_shine_cols = PackedColorArray()
	if ssr:
		for f in LowpolyBox.faces(r.grow(-5.0), 7.0, gc, 0.05, hash(gc) & 0xffff):
			_shine.append_array(f[0])
		_shine_cols.resize(_shine.size())
	_top = PackedVector2Array()
	_top_cols = PackedColorArray()
	_lines = []
	_add_gem(UiKit.card_gem_center(r), UiKit.CARD_GEM_R, gc)
	_base = PackedVector2Array()
	_base_cols = PackedColorArray()
	_base_lines = []
	_win = PackedVector2Array()
	_win_cols = PackedColorArray()
	_win_edge = PackedVector2Array()
	if live:
		_add_base(Color(h.color))
	else:
		_add_window(gc, Color(h.color))
	if badge == "" and stars > 0:
		_add_stars()


func _add_gem(center: Vector2, r: float, color: Color) -> void:
	var g := UiKit.gem_geometry(center, r, color, 6)
	_top.append_array(g[0])
	_top_cols.append_array(g[1])
	_lines.append([g[2], UiKit.gem_outline_width(r)])


## 초상화 창: 위 모서리를 깎은 사각 — 등급 색 깎은 면(LowpolyBox.faces) 위에 위가 밝고 아래가 짙은 그러데이션, 아래에 고유 색 띠
## (위 반 밝게, 아래 반 짙게). 테두리는 등급 색의 어두운 톤(_draw).
func _add_window(gc: Color, unique: Color) -> void:
	var wr := portrait_rect()
	if wr.size.x <= 0.0 or wr.size.y <= 0.0:
		return
	var k := WIN_CHAMFER
	var shape := PackedVector2Array([wr.position + Vector2(k, 0), Vector2(wr.end.x - k, wr.position.y), Vector2(wr.end.x, wr.position.y + k),
		wr.end, Vector2(wr.position.x, wr.end.y), wr.position + Vector2(0, k)])
	for i in range(1, shape.size() - 1):  # 바탕(등급 색 중간 톤)
		for p in [shape[0], shape[i], shape[i + 1]]:
			_win.append(p)
			_win_cols.append(gc.lightened(0.3))
	for f in LowpolyBox.faces(wr, k, gc.lightened(0.3), 0.07, hash(gc) & 0xffff):  # 깎은 면
		for p in f[0]:
			_win.append(p)
			_win_cols.append(f[1])
	var top_glow := Color(1, 1, 1, 0.42)  # 위 밝게 → 아래 짙게
	var bottom_dark := Color(gc.darkened(0.45), 0.4)
	var mid_y := wr.position.y + wr.size.y * 0.55
	for q in [[wr.position.y, mid_y, top_glow, Color(1, 1, 1, 0.0)], [mid_y, wr.end.y, Color(gc.darkened(0.45), 0.0), bottom_dark]]:
		var y0: float = q[0]
		var y1: float = q[1]
		var quad := [Vector2(wr.position.x, y0), Vector2(wr.end.x, y0), Vector2(wr.end.x, y1), Vector2(wr.position.x, y1)]
		var cols := [q[2], q[2], q[3], q[3]]
		for t in [[0, 1, 2], [0, 2, 3]]:
			for j in t:
				_win.append(quad[j])
				_win_cols.append(cols[j])
	var band := Rect2(wr.position.x, wr.end.y, wr.size.x, BAND_H)  # 고유 색 띠
	for half in [[band.position.y, band.position.y + BAND_H * 0.5, unique.lightened(0.15)], [band.position.y + BAND_H * 0.5, band.end.y, unique.darkened(0.2)]]:
		var a: float = half[0]
		var b: float = half[1]
		for p in [Vector2(band.position.x, a), Vector2(band.end.x, a), Vector2(band.end.x, b), Vector2(band.position.x, a), Vector2(band.end.x, b), Vector2(band.position.x, b)]:
			_win.append(p)
			_win_cols.append(half[2])
	_win_edge = shape.duplicate()
	_win_edge[3] = band.end
	_win_edge[4] = Vector2(band.position.x, band.end.y)
	_win_edge.append(shape[0])


## 받침 원판(고유 색): 피규어 발밑(Portraits.feet_y)의 납작한 BASE_SIDES각 타원 — 어두운 옆면(아래로 두께만큼) 위에 면 분할 윗면
## (왼위가 밝다), 외곽선은 윗면 둘레와 옆면 아래 둘레.
func _add_base(color: Color) -> void:
	var fr := figure_rect()
	var c := fr.position + Vector2(fr.size.x * 0.5, fr.size.y * PortraitsScript.feet_y())
	var rad := Vector2(fr.size.x * 0.24, fr.size.x * 0.075)
	var drop := Vector2(0.0, rad.y * 0.7)
	var ring := PackedVector2Array()
	for i in BASE_SIDES:
		ring.append(c + Vector2.from_angle(TAU * i / BASE_SIDES) * rad)
	_base = PackedVector2Array()
	_base_cols = PackedColorArray()
	for top in [false, true]:
		var o := Vector2.ZERO if top else drop
		for i in BASE_SIDES:
			var a: Vector2 = ring[i]
			var b: Vector2 = ring[(i + 1) % BASE_SIDES]
			var mid := (a + b) * 0.5 - c
			var col := color.lightened(clampf(-(mid.x / rad.x + mid.y / rad.y) * 0.12, 0.0, 0.2)) if top else color.darkened(0.35)
			for p in [c + o, a + o, b + o]:
				_base.append(p)
				_base_cols.append(col)
	var rim := PackedVector2Array([ring[0]])  # 아래 반(각 0..180°)을 두께만큼 내려 잇는다
	for i in BASE_SIDES / 2 + 1:
		rim.append(ring[i] + drop)
	rim.append(ring[BASE_SIDES / 2])
	var edge := ring.duplicate()
	edge.append(ring[0])
	_base_lines = [edge, rim]


## 반짝임: 면 i의 알파 = 0.38 × max(0, sin(t × 속도 − i × 0.8)). 점 3개씩 같은 색.
func _tick_shine(gc: Color) -> void:
	var base := gc.lightened(0.45)
	for i in _shine.size() / 3:
		var c := Color(base, 0.38 * maxf(0.0, sin(_t * SHIMMER_SPEED - i * 0.8)))
		for k in 3:
			_shine_cols[i * 3 + k] = c


## 금색 별 stars개(= 승급 단계, 각진 5각 별: 가운데 부채꼴 10삼각형, 글꼴과 무관). 날아오는 중인 별(_flying)은 뺀다.
func _add_stars() -> void:
	var r: float = _star_row()[1]
	for s in stars:
		if s == _flying:
			continue
		var c := star_center(s)
		var pts := PackedVector2Array()
		for k in 10:
			pts.append(c + Vector2.from_angle(-PI / 2.0 + PI * k / 5.0) * (r if k % 2 == 0 else r * 0.45))
		for k in 10:
			for p in [c, pts[k], pts[(k + 1) % 10]]:
				_top.append(p)
				_top_cols.append(STAR_COLOR)
		pts.append(pts[0])
		_lines.append([pts, 1.2])

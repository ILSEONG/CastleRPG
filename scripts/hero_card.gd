extends Button
## 영웅 카드(스펙 §5): 등급 색 테두리 로우폴리 카드 + 위쪽 등급 보석 + 영웅 피규어(개정 14 §2, Portraits — 렌더 전엔 등급 색 실루엣)와
## 발밑 고유 색 받침 원판 + 이름·칭호 + 아래 NEW 또는 별. live(상세 큰 카드)면 피규어가 실시간(대기 애니메이션)이고 가로로 끌면 돈다 —
## 끌기는 카드가 먹어 상세의 좌우 스와이프로 새지 않는다. 보일 때만 Portraits에 미리보기를 건다(목록으로·창 닫힘이면 내린다).
## SSR은 금색 면이 반짝인다(면 밝기 순환). hero_id가 ""이면 빈 슬롯 칸. 짧게 누르면 tapped, LONG_PRESS_MS 이상 눌렀다 떼면 long_pressed.
## 바탕·보석·별 지오메트리는 (크기, 영웅, 별)이 바뀔 때만 만들고(_ensure_geo), 그리기는 삼각형 배열 몇 번이다 — SSR은 매 프레임
## 다시 그리므로 반짝임은 색 배열의 알파만 바꾼다. 창이 닫혀 안 보이면 다시 그리지 않는다.
## 입력은 부모로도 넘긴다(MOUSE_FILTER_PASS) — 스크롤 격자 안에서 끌어 스크롤할 수 있게.
## 개정 11 영웅 목록: level > 0이면 왼위 "Lv N", power > 0이면 아래 "전투력 N", deployed면 "배치" 배지, can_level이면 오른위 초록 ▲(다각형).
## burst(): 레벨업 성공 연출 — 빛 조각이 BURST_SEC 동안 가운데에서 퍼진다.

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

var geo_builds := 0  # 지오메트리를 만든 횟수(테스트용)

var _down_ms := 0
var _t := 0.0
var _burst := 0.0  # 남은 빛 조각 시간
var _geo_key := []
var _body := PackedVector2Array()  # 카드 바탕(테두리 8각 + 안쪽 면) 삼각형 점(3개씩)
var _body_cols := PackedColorArray()
var _edge := PackedVector2Array()  # 카드 외곽선(닫힘)
var _shine := PackedVector2Array()  # SSR 반짝임 면
var _shine_cols := PackedColorArray()  # 매 프레임 알파만 바꾼다
var _base := PackedVector2Array()  # 피규어 아래: 고유 색 받침 원판(옆면 + 윗면)
var _base_cols := PackedColorArray()
var _base_lines: Array = []  # 받침 외곽선(윗면 둘레, 옆면 아래 둘레)
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
	if not is_visible_in_tree():
		return  # 닫힌 창의 카드는 다시 그리지 않는다
	_t += delta
	queue_redraw()


## SSR(반짝임)이거나 빛 조각이 남았을 때만 매 프레임 다시 그린다.
func _update_process() -> void:
	set_process(_burst > 0.0 or (hero_id != "" and GameData.hero(hero_id).get("grade", "") == "SSR"))


## 레벨업 성공 연출: 빛 조각이 가운데에서 BURST_SEC 동안 퍼지며 사라진다.
func burst() -> void:
	_burst = BURST_SEC
	_update_process()


func is_bursting() -> bool:
	return _burst > 0.0


func _on_pressed() -> void:
	if Time.get_ticks_msec() - _down_ms >= LONG_PRESS_MS:
		long_pressed.emit(self)
	else:
		tapped.emit(self)


## 별 = min(copies − 1, hero_max_stars).
static func stars_of(copies: int) -> int:
	return clampi(copies - 1, 0, int(GameData.config_num("hero_max_stars")))


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
		RenderingServer.canvas_item_add_triangle_array(ci, PackedInt32Array(), _base, _base_cols)
		for l in _base_lines:
			draw_polyline(l, UiKit.OUTLINE, 1.2, true)
		draw_texture_rect(figure_texture(), figure_rect(), false)
		RenderingServer.canvas_item_add_triangle_array(ci, PackedInt32Array(), _top, _top_cols)
		for l in _lines:
			draw_polyline(l[0], UiKit.OUTLINE, l[1], true)
		var name_size := _name_size()
		_text(h.name, size.y * 0.6, name_size, UiKit.INK)
		_text(h.title, size.y * 0.6 + name_size * 0.95, maxi(11, name_size - 7), UiKit.INK.lightened(0.3))
		if badge != "":
			_text(badge, size.y - 10.0, name_size - 2, Color("D9480F"), true)
		_draw_list_info()
	if _burst > 0.0:
		_draw_burst()
	if corner != "":
		draw_string_outline(FONT, Vector2(9, 22), corner, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.WHITE)
		draw_string(FONT, Vector2(9, 22), corner, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.INK)
	if highlight:
		_outline(r.grow(1.0), HIGHLIGHT, 5.0)


func _name_size() -> int:
	return clampi(roundi(size.x * 0.17), 14, 24)


## 피규어 칸(정사각, 가운데): 등급 보석 아래부터 이름 글자 위까지.
func figure_rect() -> Rect2:
	var side := maxf(size.y * 0.6 - _name_size() * 0.85 - FIGURE_TOP, 0.0)
	return Rect2(size.x / 2.0 - side / 2.0, FIGURE_TOP, side, side)


## 그릴 피규어: live면 실시간 미리보기, 아니면 캐시(렌더 전엔 자리표시 실루엣).
func figure_texture() -> Texture2D:
	var p = PortraitsScript.current
	return p.live_texture(_key()) if live and p != null else PortraitsScript.portrait(_key())


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
	if power > 0:
		_text("전투력 %s" % UiKit.commas(power), size.y - 34.0, 17, UiKit.INK.lightened(0.15))


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


## (크기, 영웅, 별)이 바뀌었을 때만 지오메트리를 다시 만든다.
func _ensure_geo(h: Dictionary) -> void:
	var key := [size, hero_id, stars, badge != ""]
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
	_add_base(Color(h.color))
	if badge == "" and stars > 0:
		_add_stars(Vector2(size.x / 2.0, size.y - 16.0), minf(9.0, size.x / 14.0))


func _add_gem(center: Vector2, r: float, color: Color) -> void:
	var g := UiKit.gem_geometry(center, r, color, 6)
	_top.append_array(g[0])
	_top_cols.append_array(g[1])
	_lines.append([g[2], UiKit.gem_outline_width(r)])


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


## 별 stars개(각진 5각 별: 가운데 부채꼴 10삼각형, 글꼴과 무관).
func _add_stars(center: Vector2, r: float) -> void:
	var gap := r * 2.1
	var x0 := center.x - gap * (stars - 1) / 2.0
	for s in stars:
		var c := Vector2(x0 + gap * s, center.y)
		var pts := PackedVector2Array()
		for k in 10:
			pts.append(c + Vector2.from_angle(-PI / 2.0 + PI * k / 5.0) * (r if k % 2 == 0 else r * 0.45))
		for k in 10:
			for p in [c, pts[k], pts[(k + 1) % 10]]:
				_top.append(p)
				_top_cols.append(STAR_COLOR)
		pts.append(pts[0])
		_lines.append([pts, 1.2])

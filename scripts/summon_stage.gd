extends Control
## 영웅 모집 소환 연출(2026-10-15, 사용자 "영웅뽑기 좀 더 화려하게 연출해줘"): 모집 창 위 화면 전체를 덮는 막(recruit_panel이 맨 위 자식으로 둔다).
## 참고한 게임: 원신(기원 — 떨어지는 별빛 색이 최고 등급을 미리 알린다), 블루 아카이브(모집 쪽지 색이 마지막 순간 한 단계 바뀐다),
## 클래시 로얄(가장 높은 등급은 무지개빛), AFK 아레나(10회 결과를 한 화면에서 빠르게 차례로 뒤집고 언제든 건너뛴다).
## 1) 소환진(play): 어두운 밤 막 위 로우폴리 마법진(두 고리 + 룬 + 육각별)이 돌며 빛을 모은다. 빛은 파랑(R)에서 시작해 이번 모집 최고 등급이
##    SR이면 SR_AT에 보라로, SSR이면 SSR_AT에 무지개빛으로 바뀐다(번쩍 + 흔들림 + 빛기둥). 끝에 터지며 걷히고 intro_done — 창의 카드가
##    차례로 뒤집히기 시작한다. 화면을 누르면 바로 터지며 걷힌다(그 모집의 최고 등급 빛으로). [건너뛰기]는 skip_all(카드를 모두 바로 열고 SSR 화면도 건너뛴다).
## 2) SSR 화면(splash): SSR 카드가 펴지면 도는 무지개 빛살 위 큰 기울어진 창에 영웅 일러스트 + "SSR" + 이름·칭호(새 영웅이면 NEW).
##    누르면 닫힌다(SPLASH_SEC 뒤 저절로). 여러 장이면 차례로.
## 3) UR(2026-10-29, 사용자 "UR은 개멋지게 뽑아줘"): SSR처럼 터질 순간에 무지개빛이 한 번 더 바뀌어 일식이 된다 — 가운데 검은 해 둘레로 불꽃 혀가
##    일렁이고, 빛이 진홍·주황 불꽃빛으로 바뀌며 충격파 고리 + 굵은 불기둥 + 화면 가득 오르는 불씨, 소환진도 UR_HOLD만큼 길다.
##    UR 화면은 SSR보다 크다: 대각선 섬광이 창을 가르며 열리고, 불꽃 테두리 위로 불길이 일렁이며 "UR"은 크게(진홍 두께).
##    참고: 원신(최고 등급 별똥별 색), 블루 아카이브(마지막 순간 색이 한 번 더 바뀜), 세븐나이츠 키우기(최고 등급 소환 섬광·불꽃) — 화면 모습 기준.
## 금색은 쓰지 않는다(SSR = 무지개빛, UR = 주황 불꽃빛 — 사용자 2026-10-14 "금색되는거 촌스러워"). 그리는 것은 다각형 몇백 개뿐, 보일 때만 돈다(발열).

const Lang := preload("res://scripts/lang.gd")

const UiKit := preload("res://scripts/ui_kit.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const HeroArt := preload("res://scripts/hero_art.gd")
const Portraits := preload("res://scripts/portraits.gd")
const GameData := preload("res://scripts/game_data.gd")
const Sfx := preload("res://scripts/sfx.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const INTRO_ONE := 1.3  # 1회 소환진 길이(초)
const INTRO_TEN := 1.6  # 10회
const SR_AT := 0.5  # 소환진 시간 비율: 빛이 보라로
const SSR_AT := 0.74  # 무지개로
const UR_HOLD := 0.8  # UR: 소환진이 SSR처럼 터질 때 대신 일식이 되고, 이만큼 더 돈다
const BURST := 0.24  # 끝: 터지며 걷힘
const FADE_IN := 0.15
const SPLASH_IN := 0.3
const SPLASH_SEC := 2.4
const SPLASH_OUT := 0.22
const SPLASH_MIN := 0.45  # SSR 화면이 뜬 뒤 이보다 이른 누름은 무시(연타가 바로 닫지 않게)
const UR_SLASH := 0.16  # UR 화면: 섬광이 화면을 가르는 시간
const UR_IN := 0.5  # UR 화면: 섬광 + 창이 열리는 시간
const UR_SPLASH_SEC := 3.0
const UR_WAVE := 0.6  # 일식 충격파 고리
const NIGHT := Color("120F26")
const BLUE := Color("7DB4FF")  # R 빛(R 등급 회청색을 밝게)
const PURPLE := Color("B48CFF")  # SR 빛
const ORANGE := Color("FF6A1F")  # UR 빛(= UR 등급 색)
## UR 불꽃빛: 진홍 → 주황 → 살구 → 흰빛을 돈다(노란 금빛은 피한다).
const FLAME := [Color("E8344A"), Color("FF6A1F"), Color("FF9A5C"), Color("FFE2D0")]
const EMBERS := 34
const TONGUES := 14  # UR 화면 창 위 불길 수
const RAYS := 16
const MOTES := 26
const RUNES := 16

signal intro_done
signal skip_all
signal splash_done  # 마지막 SSR 화면이 걷혔다

enum Mode { IDLE, INTRO, SPLASH }

var mode := Mode.IDLE
var best := "R"  # 이번 모집 최고 등급
var skip_button: Button
var splash_hero := ""  # 지금 SSR 화면 영웅(테스트)

var _t := 0.0
var _len := INTRO_TEN
var _base := INTRO_TEN  # UR 일식 전 소환진 길이(빛이 바뀌는 비율의 기준)
var _rank := 0  # 지금 빛 0 R · 1 SR · 2 SSR · 3 UR
var _ur_at := 0.0  # UR 일식이 시작된 시각(_t)
var _flash := 0.0
var _shake := 0.0
var _queue: Array = []  # 기다리는 SSR·UR 화면 [{hero, new, grade}]
var _splash := {}


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	skip_button = Button.new()
	skip_button.text = Lang.t("summon_stage.init")
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.add_theme_font_override("font", FONT)
	skip_button.add_theme_font_size_override("font_size", 24)
	UiKit.apply_button(skip_button, UiKit.STEEL, 10.0)
	skip_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	skip_button.offset_left = -190
	skip_button.offset_right = -20
	skip_button.offset_top = 96
	skip_button.offset_bottom = 152
	skip_button.pressed.connect(_on_skip)
	add_child(skip_button)


## 소환진을 처음부터. grade = 이번 모집 최고 등급, count = 장수(1 또는 10).
func play(grade: String, count: int) -> void:
	best = grade
	_base = INTRO_ONE if count == 1 else INTRO_TEN
	_len = _base + (UR_HOLD if grade == "UR" else 0.0)
	_t = 0.0
	_rank = 0
	_flash = 0.0
	_shake = 0.0
	_queue.clear()
	_splash = {}
	splash_hero = ""
	mode = Mode.INTRO
	visible = true
	skip_button.visible = true
	Sfx.play("sk_summon")
	queue_redraw()


## SSR·UR 화면을 줄 세운다(소환진 중이면 걷힌 뒤에). grade가 ""이면 영웅 표의 등급.
func splash(hero_id: String, is_new: bool, grade := "") -> void:
	if grade == "":
		grade = str(GameData.hero(hero_id).get("grade", "SSR"))
	_queue.append({"hero": hero_id, "new": is_new, "grade": grade})
	if mode == Mode.IDLE:
		_next_splash()


## 다 멈추고 숨긴다(창을 닫을 때·새 결과).
func stop() -> void:
	mode = Mode.IDLE
	_queue.clear()
	_splash = {}
	splash_hero = ""
	visible = false


func is_busy() -> bool:
	return mode != Mode.IDLE


func _on_skip() -> void:
	stop()
	skip_all.emit()


func _gui_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if not pressed:
		return
	accept_event()
	if mode == Mode.INTRO and _t < _len:
		_upgrade(_goal())  # 바로 터진다 — 그 모집의 최고 등급 빛으로
		_t = _len
	elif mode == Mode.SPLASH and _t >= SPLASH_MIN and _t < _splash_in() + _splash_sec():
		_t = _splash_in() + _splash_sec()  # 빠지기 시작


func _goal() -> int:
	return {"UR": 3, "SSR": 2, "SR": 1}.get(best, 0)


func _ur_splash() -> bool:
	return _splash.get("grade", "") == "UR"


func _splash_in() -> float:
	return UR_IN if _ur_splash() else SPLASH_IN


func _splash_sec() -> float:
	return UR_SPLASH_SEC if _ur_splash() else SPLASH_SEC


func _process(delta: float) -> void:
	if mode == Mode.IDLE:
		return
	_t += delta
	_flash = maxf(0.0, _flash - delta * 2.6)
	_shake = maxf(0.0, _shake - delta * 2.2)
	if mode == Mode.INTRO:
		var k := _t / _base
		if _rank < 1 and _goal() >= 1 and k >= SR_AT:
			_upgrade(1)
		if _rank < 2 and _goal() >= 2 and k >= SSR_AT:
			_upgrade(2)
		if _rank < 3 and _goal() >= 3 and k >= 1.0:  # SSR이 터질 때 대신 한 번 더 바뀐다
			_upgrade(3)
		if _t >= _len + BURST:
			mode = Mode.IDLE
			intro_done.emit()  # 카드가 뒤집히기 시작한다(SSR이 펴지면 splash로 다시 뜬다)
			if mode == Mode.IDLE:
				_next_splash()
	elif mode == Mode.SPLASH and _t >= _splash_in() + _splash_sec() + SPLASH_OUT:
		_next_splash()
	queue_redraw()


func _upgrade(r: int) -> void:
	if r <= _rank:
		return
	_rank = r
	_flash = 0.55 if r == 1 else 1.0
	_shake = [0.0, 0.6, 1.0, 1.8][r]
	if r == 3:  # 일식: 쿵 + 불길
		_ur_at = _t
		Sfx.play("sk_boom")
		Sfx.play("sk_fire")
	else:
		Sfx.play("sk_holy" if r == 1 else "sk_thunder")


func _next_splash() -> void:
	if _queue.is_empty():
		var was := mode == Mode.SPLASH
		stop()
		if was:
			splash_done.emit()
		return
	_splash = _queue.pop_front()
	splash_hero = _splash.hero
	mode = Mode.SPLASH
	visible = true
	skip_button.visible = false
	_t = 0.0
	queue_redraw()


## 무지개빛(살짝 옅게 — 원색 무지개가 촌스럽지 않게).
static func prism(h: float, a := 1.0) -> Color:
	var c := Color.from_hsv(fposmod(h, 1.0), 0.55, 1.0)
	c.a = a
	return c


## 불꽃빛(UR) — FLAME을 h(0..1)에 따라 이어 돈다.
static func flame(h: float, a := 1.0) -> Color:
	var x := fposmod(h, 1.0) * FLAME.size()
	var i := int(x)
	var c: Color = FLAME[i].lerp(FLAME[(i + 1) % FLAME.size()], x - i)
	c.a = a
	return c


## 불꽃빛에서 흰빛을 뺀 진홍 ↔ 살구(빛살·고리 — 흰빛이 넓게 깔리면 화면이 바랜다). 오가며 돈다(끊김 없이).
static func ember(h: float, a := 1.0) -> Color:
	return flame(absf(fposmod(h, 1.0) * 2.0 - 1.0) * 0.6, a)


func _light(i := 0, n := 1) -> Color:
	if _rank == 3:
		return ember(float(i) / maxi(n, 1) + _t * 0.5)
	if _rank == 2:
		return prism(float(i) / maxi(n, 1) + _t * 0.35)
	return PURPLE if _rank == 1 else BLUE


func _draw() -> void:
	if mode == Mode.INTRO:
		_draw_intro()
	elif mode == Mode.SPLASH:
		if _ur_splash():
			_draw_splash_ur()
		else:
			_draw_splash()


func _draw_intro() -> void:
	var vs := size
	var a := clampf(_t / FADE_IN, 0.0, 1.0)
	var out := clampf((_t - _len) / BURST, 0.0, 1.0)  # 터지며 걷힘
	var fade := 1.0 - out
	draw_rect(Rect2(Vector2.ZERO, vs), Color(NIGHT, 0.93 * a * fade))
	var ur := _rank == 3
	var since := _t - _ur_at  # UR 일식 뒤 초
	if ur:  # 불빛에 밤이 붉게 물든다
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.5, 0.1, 0.02, 0.22 * clampf(since * 4.0, 0.0, 1.0) * fade))
	var shake := Vector2(sin(_t * 71.0), cos(_t * 53.0)) * 9.0 * _shake
	var c := Vector2(vs.x * 0.5, vs.y * 0.46) + shake
	var big := minf(vs.x, vs.y) * 0.38
	var grow := ease(clampf(_t / (_len * 0.35), 0.0, 1.0), 0.4)
	var r := big * (0.5 + 0.5 * grow) * (1.0 + out * 0.7) * (1.0 + 0.1 * _flash)  # 빛이 바뀔 때 한 번 쿵
	var k := clampf(_t / _base, 0.0, 1.0)
	# 뒤에서 도는 빛살(갈수록 짙어지고, SSR이면 무지개빛으로 더 짙게)
	var ray_a: float = (0.06 + 0.2 * k) * a * fade * [1.0, 1.0, 1.5, 1.6][_rank]
	var reach := vs.length()
	for i in RAYS:
		var ang := _t * 0.4 + TAU * i / RAYS
		draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(ang) * reach, c + Vector2.from_angle(ang + TAU / RAYS * 0.4) * reach]),
			Color(_light(i, RAYS), ray_a * (0.6 + 0.4 * (i % 2))))
	# 바닥 빛: 겹 다각형(바깥일수록 옅다)
	for i in 4:
		var rr := r * (1.5 - i * 0.28) * (0.9 + 0.1 * sin(_t * 6.0 + i))
		draw_colored_polygon(_ngon(c, rr, 16, _t * 0.2), Color(_light(i, 4), (0.05 + 0.04 * i) * a * fade * (0.6 + 0.6 * k)))
	# 빛기둥(SSR): 마법진에서 위로 솟는 가는 빛 6줄. UR은 굵은 불기둥 8줄
	if _rank >= 2:
		var n := 8 if ur else 6
		for i in n:
			var x := c.x + (i - (n - 1) / 2.0) * r * (0.27 if ur else 0.32)
			var w := (10.0 + 8.0 * LowpolyBox.hash01(i, 3)) * (1.8 if ur else 1.0)
			var top := -vs.y * (0.2 + 0.3 * LowpolyBox.hash01(i, 5))
			var col := flame(float(i) / n + _t * 0.4, 0.45 * fade) if ur else prism(i / 6.0 + _t * 0.4, 0.35 * fade)
			draw_colored_polygon(PackedVector2Array([Vector2(x - w, c.y), Vector2(x + w, c.y), Vector2(x + w * 0.3, top), Vector2(x - w * 0.3, top)]), col)
	# 모이는 빛줄기: 화면 가장자리에서 가운데로(뒤 절반)
	if k > 0.45:
		var s := (k - 0.45) / 0.55
		for i in 12:
			var dir := Vector2.from_angle(TAU * i / 12.0 + LowpolyBox.hash01(i, 11) * 0.3)
			var far := vs.length() * 0.6 * (1.0 - fmod(_t * 1.6 + LowpolyBox.hash01(i, 13), 1.0))
			var p0 := c + dir * maxf(far, r * 0.3)
			var p1 := c + dir * maxf(far - 90.0, r * 0.2)
			draw_line(p0, p1, Color(_light(i, 12), 0.7 * s * fade), 3.0, true)
	# 마법진: 바깥 고리 두 줄 + 룬(마름모) + 안쪽 육각별 + 가운데 빛 덩어리
	_ring(c, r, 32, 5.0, _t * 0.5, a * fade)
	_ring(c, r * 0.86, 32, 2.5, -_t * 0.8, a * fade)
	for i in RUNES:
		var ang := TAU * i / RUNES + _t * 0.5
		var p := c + Vector2.from_angle(ang) * r * 0.93
		var s := 7.0 + 3.0 * (i % 2)
		var d := Vector2.from_angle(ang)
		draw_colored_polygon(PackedVector2Array([p + d * s, p + d.orthogonal() * s * 0.55, p - d * s, p - d.orthogonal() * s * 0.55]), Color(_light(i, RUNES), a * fade))
	for tri in 2:
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		for i in 4:
			var ang := TAU * (i % 3) / 3.0 + PI * tri - _t * 0.9 * (1.0 if tri == 0 else -1.0)
			pts.append(c + Vector2.from_angle(ang - PI / 2.0) * r * 0.74)
			cols.append(Color(_light(i + tri * 3, 6), 0.85 * a * fade))
		draw_polyline_colors(pts, cols, 3.0, true)
	var core := r * (0.18 + 0.22 * k + 0.25 * out)
	if ur:
		_draw_eclipse(c, core * 1.1 * (1.0 + 0.25 * ease(clampf(since * 3.0, 0.0, 1.0), 0.4)), a * fade)
	else:
		draw_colored_polygon(_ngon(c, core * 1.6, 12, -_t), Color(_light(1, 3), 0.25 * a * fade))
		draw_colored_polygon(_ngon(c, core, 12, _t), Color(_light(0, 3).lightened(0.4), 0.85 * a * fade))
		draw_colored_polygon(_ngon(c, core * 0.55, 8, _t * 2.0), Color(1, 1, 1, 0.9 * a * fade))
	# 떠오르는 빛 조각
	for i in MOTES:
		var u := fmod(_t * (0.35 + 0.3 * LowpolyBox.hash01(i, 1)) + LowpolyBox.hash01(i, 2), 1.0)
		var px := c.x + (LowpolyBox.hash01(i, 4) - 0.5) * r * 2.4
		var py := c.y + r * 0.6 - u * vs.y * 0.55
		var s := 4.0 + 4.0 * LowpolyBox.hash01(i, 6)
		draw_colored_polygon(PackedVector2Array([Vector2(px, py - s), Vector2(px + s * 0.6, py), Vector2(px, py + s), Vector2(px - s * 0.6, py)]),
			Color(_light(i, MOTES).lightened(0.3), (1.0 - u) * 0.9 * a * fade))
	if ur:  # 불씨가 화면 아래에서 가득 오른다 + 일식 충격파
		_draw_embers(vs, a * fade * clampf(since * 3.0, 0.0, 1.0))
		var sw := since / UR_WAVE
		if sw < 1.0:
			_ring(c, r * (1.0 + sw * 2.4), 32, 22.0 * (1.0 - sw), 0.0, (1.0 - sw) * fade)
	# 터짐: 퍼지는 고리
	if out > 0.0:
		_ring(c, r * (1.0 + out * 1.2), 32, 14.0 * (1.0 - out), 0.0, 1.0 - out)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 1, 1, 0.6 * _flash))
	if out > 0.0:  # 걷힐 때 한 번 번쩍
		draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 1, 1, 0.5 * sin(PI * out)))


func _draw_splash() -> void:
	var vs := size
	var t := _t
	var in_k := ease(clampf(t / SPLASH_IN, 0.0, 1.0), 0.3)
	var out_k := clampf((t - SPLASH_IN - SPLASH_SEC) / SPLASH_OUT, 0.0, 1.0)
	var a := clampf(t / (SPLASH_IN * 0.6), 0.0, 1.0) * (1.0 - out_k)
	draw_rect(Rect2(Vector2.ZERO, vs), Color(NIGHT, 0.9 * a))
	var c := Vector2(vs.x * 0.5, vs.y * 0.45)
	var reach := vs.length()
	for i in RAYS:  # 도는 무지개 빛살
		var ang := t * 0.35 + TAU * i / RAYS
		draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(ang) * reach, c + Vector2.from_angle(ang + TAU / RAYS * 0.42) * reach]),
			prism(float(i) / RAYS + t * 0.08, 0.22 * a))
	# 기울어진 큰 창(들어올 때 커지며 아래에서 떠오른다, 빠질 때 위로)
	var w := minf(vs.x * 0.84, 600.0)
	var h := minf(vs.y * 0.5, 640.0)
	var slant := 56.0
	var sc := 0.82 + 0.18 * in_k
	var off := Vector2(0, (1.0 - in_k) * 60.0 - out_k * 80.0)
	var o := c + off
	var hw := w * 0.5 * sc
	var hh := h * 0.5 * sc
	var frame := PackedVector2Array([o + Vector2(-hw + slant, -hh), o + Vector2(hw, -hh), o + Vector2(hw - slant, hh), o + Vector2(-hw, hh)])
	draw_colored_polygon(frame, Color(NIGHT.lightened(0.12), a))
	var inset := 10.0
	var win := PackedVector2Array([frame[0] + Vector2(inset * 0.6, inset), frame[1] + Vector2(-inset, inset), frame[2] + Vector2(-inset * 0.6, -inset), frame[3] + Vector2(inset, -inset)])
	var wr := Rect2(win[3].x, win[0].y, win[1].x - win[3].x, win[2].y - win[0].y)
	var zoom := lerpf(1.08, 1.0, clampf(t / (SPLASH_IN + SPLASH_SEC), 0.0, 1.0))
	if not HeroArt.draw_in(self, _splash.hero, win, wr, 0.3, zoom):
		draw_colored_polygon(win, Color(UiKit.GRADE_COLORS.SSR.darkened(0.4), a))
	if a < 1.0:
		draw_colored_polygon(win, Color(NIGHT, 1.0 - a))
	# 무지개 테(꼭짓점마다 다른 색이 돈다)
	var edge := frame.duplicate()
	edge.append(frame[0])
	var cols := PackedColorArray()
	for i in edge.size():
		cols.append(prism(float(i % 4) / 4.0 + t * 0.4, a))
	draw_polyline_colors(edge, cols, 7.0, true)
	draw_polyline(edge, Color(1, 1, 1, 0.6 * a), 2.0, true)
	# 글자: 위 "SSR"(글자마다 무지개), 아래 이름·칭호
	var h_def: Dictionary = GameData.hero(_splash.hero)
	var font: Font = FONT
	var ssr := "SSR"
	var fs := 84
	var tw := font.get_string_size(ssr, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := o.x - tw * 0.5
	var y := o.y - hh - 26.0
	for i in ssr.length():
		var ch := ssr[i]
		var cw := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(font, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 14, Color(NIGHT, a))
		draw_string(font, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, prism(i / 3.0 + t * 0.5, a).lightened(0.2))
		x += cw
	var name_s := str(h_def.get("name", ""))
	var title_s := str(h_def.get("title", ""))
	var ny := o.y + hh + 66.0
	_centered(name_s, Vector2(o.x, ny), 54, Color(1, 1, 1, a), a)
	_centered(title_s, Vector2(o.x, ny + 44.0), 28, Color(0.92, 0.88, 1.0, a), a)
	if _splash.get("new", false):
		var nb := Vector2(o.x + hw - 70.0, o.y - hh + 6.0)
		var badge := PackedVector2Array([nb + Vector2(-58, -24), nb + Vector2(58, -24), nb + Vector2(48, 24), nb + Vector2(-68, 24)])
		draw_colored_polygon(badge, Color(UiKit.GRADE_COLORS.SR.darkened(0.15), a))
		draw_polyline(PackedVector2Array([badge[0], badge[1], badge[2], badge[3], badge[0]]), Color(UiKit.GRADE_COLORS.SR.darkened(0.5), a), 2.0, true)
		_centered("NEW", nb + Vector2(-5, 12), 30, Color(1, 1, 1, a), a)
	if t > SPLASH_MIN:
		_centered(Lang.t("summon_stage.draw_splash"), Vector2(o.x, vs.y - 120.0), 24, Color(1, 1, 1, 0.6 * a * clampf((t - SPLASH_MIN) * 3.0, 0.0, 1.0)), a)


## UR 화면: SSR보다 크고 거칠다 — 진홍·주황 빛살이 빠르게 돌고, 대각선 섬광이 화면을 가른 뒤 그 선에서 창이 열린다.
## 창 테두리는 불꽃빛으로 일렁이고 위 변에서 불길이 오르며, 불씨가 화면 가득 오른다. "UR"은 크게, 뒤에 진홍 두께.
func _draw_splash_ur() -> void:
	var vs := size
	var t := _t
	var out_k := clampf((t - UR_IN - UR_SPLASH_SEC) / SPLASH_OUT, 0.0, 1.0)
	var a := clampf(t / (UR_SLASH * 0.6), 0.0, 1.0) * (1.0 - out_k)
	var slash := ease(clampf(t / UR_SLASH, 0.0, 1.0), 0.4)  # 섬광이 가르는 정도
	var open := ease(clampf((t - UR_SLASH) / (UR_IN - UR_SLASH), 0.0, 1.0), 0.35)  # 창이 열리는 정도
	draw_rect(Rect2(Vector2.ZERO, vs), Color(NIGHT, 0.94 * a))
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.5, 0.1, 0.02, 0.24 * a))
	var shake := Vector2(sin(t * 67.0), cos(t * 49.0)) * 12.0 * clampf(1.0 - (t - UR_SLASH) / 0.45, 0.0, 1.0) * float(t > UR_SLASH)
	var c := Vector2(vs.x * 0.5, vs.y * 0.45) + shake
	var reach := vs.length()
	var n := RAYS + 8
	for i in n:  # 빛살: 넓은 진홍·좁은 주황이 번갈아 빠르게 돈다
		var ang := t * 0.6 + TAU * i / n
		draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(ang) * reach, c + Vector2.from_angle(ang + TAU / n * 0.45) * reach]),
			flame(float(i % 4) / 4.0 + t * 0.15, (0.3 if i % 2 == 0 else 0.17) * a * open))
	var w := minf(vs.x * 0.92, 660.0)
	var h := minf(vs.y * 0.56, 720.0)
	var slant := 70.0
	var o := c + Vector2(0, -out_k * 90.0)
	var hw := w * 0.5
	var hh := h * 0.5
	var full := PackedVector2Array([o + Vector2(-hw + slant, -hh), o + Vector2(hw, -hh), o + Vector2(hw - slant, hh), o + Vector2(-hw, hh)])
	var frame := _opening(full, open)
	var inset := 10.0
	var win_full := PackedVector2Array([full[0] + Vector2(inset * 0.6, inset), full[1] + Vector2(-inset, inset), full[2] + Vector2(-inset * 0.6, -inset), full[3] + Vector2(inset, -inset)])
	var win := _opening(win_full, open)
	var wr := Rect2(win_full[3].x, win_full[0].y, win_full[1].x - win_full[3].x, win_full[2].y - win_full[0].y)
	if open > 0.0:
		draw_colored_polygon(frame, Color(NIGHT.lightened(0.1), a))
		var zoom := lerpf(1.12, 1.0, clampf(t / (UR_IN + UR_SPLASH_SEC), 0.0, 1.0))
		if not HeroArt.draw_in(self, _splash.hero, win, wr, 0.3, zoom):  # 일러스트 전: 주황 창에 3D 전신 피규어
			draw_colored_polygon(win, Color(ORANGE.darkened(0.45), a))
			var fs := wr.size.y * 1.05 * zoom
			draw_texture_rect(Portraits.portrait("hero:" + str(_splash.hero)), Rect2(wr.get_center() - Vector2(fs, fs) * 0.5, Vector2(fs, fs)), false,
				Color(1, 1, 1, a * clampf((open - 0.6) * 2.5, 0.0, 1.0)))
		if a < 1.0:
			draw_colored_polygon(win, Color(NIGHT, 1.0 - a))
		# 위 변 불길(창이 다 열린 뒤 일렁인다)
		var top_a := a * clampf((t - UR_IN) * 4.0, 0.0, 1.0)
		var along := (frame[1] - frame[0]).normalized()
		for j in TONGUES:
			var p := frame[0].lerp(frame[1], (j + 0.5) / TONGUES)
			var fl := 0.6 + 0.4 * sin(t * 11.0 + j * 2.3) + 0.3 * LowpolyBox.hash01(j, 41)
			var bw := (frame[1] - frame[0]).length() / TONGUES * 0.62
			draw_colored_polygon(PackedVector2Array([p - along * bw, p + along * bw, p + Vector2(sin(t * 5.0 + j) * 6.0, -(16.0 + 26.0 * fl))]),
				flame(0.15 + 0.5 * LowpolyBox.hash01(j, 43) + t * 0.2, 0.9 * top_a))
		# 불꽃 테두리: 넓고 옅은 바깥 + 꼭짓점마다 다른 불꽃빛 + 흰 속선
		var edge := frame.duplicate()
		edge.append(frame[0])
		draw_polyline(edge, Color(ORANGE, 0.3 * a), 20.0, true)
		var cols := PackedColorArray()
		for i in edge.size():
			cols.append(flame(float(i % 4) / 4.0 + t * 0.5, a))
		draw_polyline_colors(edge, cols, 8.0, true)
		draw_polyline(edge, Color(1, 0.95, 0.9, 0.7 * a), 2.0, true)
	# 섬광: 창의 대각선을 따라 화면을 가르고(UR_SLASH), 창이 열리며 옅어진다
	var d := (full[1] - full[3]).normalized()
	var s0 := full[3] - d * reach * 0.3
	var s1 := s0 + d * reach * 1.1 * slash
	var sa := (1.0 - open * 0.85) * a
	draw_line(s0, s1, Color(ORANGE, 0.5 * sa), 34.0 * (1.0 - open) + 4.0, true)
	draw_line(s0, s1, Color(1, 0.96, 0.92, sa), 10.0 * (1.0 - open) + 2.0, true)
	if t < UR_IN + 0.15:  # 열리는 순간 번쩍
		draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 0.62, 0.4, 0.3 * sin(PI * clampf((t - UR_SLASH) / (UR_IN + 0.15 - UR_SLASH), 0.0, 1.0)) * a))
	_draw_embers(vs, a * open)
	if open < 0.5:
		return
	var ta := a * clampf((open - 0.5) * 2.0, 0.0, 1.0)
	# 글자: 위 "UR"(크게, 진홍 두께 위에 글자마다 불꽃빛), 아래 이름·칭호
	var h_def: Dictionary = GameData.hero(_splash.hero)
	var ur := "UR"
	var fs := 128
	var tw := FONT.get_string_size(ur, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := o.x - tw * 0.5
	var y := o.y - hh - 30.0 - 10.0 * (1.0 - open)
	for i in ur.length():
		var ch := ur[i]
		var cw := FONT.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(FONT, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 18, Color(NIGHT, ta))
		draw_string(FONT, Vector2(x + 5.0, y + 7.0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(FLAME[0].darkened(0.35), ta))
		draw_string(FONT, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, flame(0.3 + i * 0.25 + t * 0.35, ta).lightened(0.1))
		x += cw
	var ny := o.y + hh + 72.0
	_centered(str(h_def.get("name", "")), Vector2(o.x, ny), 60, Color(1, 1, 1, ta), ta)
	_centered(str(h_def.get("title", "")), Vector2(o.x, ny + 48.0), 30, Color(1.0, 0.9, 0.84, ta), ta)
	if _splash.get("new", false):
		var nb := Vector2(o.x + hw - 74.0, o.y - hh + 8.0)
		var badge := PackedVector2Array([nb + Vector2(-58, -24), nb + Vector2(58, -24), nb + Vector2(48, 24), nb + Vector2(-68, 24)])
		draw_colored_polygon(badge, Color(UiKit.GRADE_COLORS.SR.darkened(0.15), ta))
		draw_polyline(PackedVector2Array([badge[0], badge[1], badge[2], badge[3], badge[0]]), Color(UiKit.GRADE_COLORS.SR.darkened(0.5), ta), 2.0, true)
		_centered("NEW", nb + Vector2(-5, 12), 30, Color(1, 1, 1, ta), ta)
	if t > SPLASH_MIN + UR_IN:
		_centered(Lang.t("summon_stage.draw_splash"), Vector2(o.x, vs.y - 120.0), 24, Color(1, 1, 1, 0.6 * ta * clampf((t - SPLASH_MIN - UR_IN) * 3.0, 0.0, 1.0)), ta)


## 창이 대각선(꼭짓점 3 → 1)에서 열린다: 그 선 밖의 두 꼭짓점(0·2)을 선 위 가장 가까운 점에서 제자리로(open 0 → 1).
static func _opening(q: PackedVector2Array, open: float) -> PackedVector2Array:
	var d := (q[1] - q[3]).normalized()
	var out := q.duplicate()
	for i in [0, 2]:
		var on := q[3] + d * (q[i] - q[3]).dot(d)
		out[i] = on.lerp(q[i], open)
	return out


## UR 일식: 검은 해 둘레로 불꽃 혀가 일렁인다(흰 테 + 옅은 주황 번짐).
func _draw_eclipse(c: Vector2, rr: float, a: float) -> void:
	draw_colored_polygon(_ngon(c, rr * 2.4, 20, _t * 0.3), Color(ORANGE, 0.2 * a))
	var n := 22
	for i in n:
		var ang := TAU * i / n + _t * 0.6
		var fl := 0.7 + 0.3 * sin(_t * 9.0 + i * 1.7) + 0.4 * LowpolyBox.hash01(i, 21)
		var hw := TAU / n * 0.55
		draw_colored_polygon(PackedVector2Array([c + Vector2.from_angle(ang - hw) * rr * 0.95, c + Vector2.from_angle(ang) * rr * (1.3 + 0.6 * fl),
			c + Vector2.from_angle(ang + hw) * rr * 0.95]), flame(float(i) / n + _t * 0.4, 0.9 * a))
	draw_colored_polygon(_ngon(c, rr * 1.08, 20, 0.0), Color(1.0, 0.93, 0.86, a))
	draw_colored_polygon(_ngon(c, rr, 20, 0.0), Color(NIGHT.darkened(0.6), a))


## 불씨: 화면 아래에서 위로 오르며 흔들리고 흐려지는 불꽃빛 마름모(UR).
func _draw_embers(vs: Vector2, a: float) -> void:
	if a <= 0.0:
		return
	for i in EMBERS:
		var u := fmod(_t * (0.4 + 0.45 * LowpolyBox.hash01(i, 31)) + LowpolyBox.hash01(i, 32), 1.0)
		var px := vs.x * LowpolyBox.hash01(i, 33) + sin(_t * 2.2 + i) * 16.0
		var py := vs.y * (1.05 - u * 1.1)
		var s := 3.0 + 5.0 * LowpolyBox.hash01(i, 34)
		draw_colored_polygon(PackedVector2Array([Vector2(px, py - s * 1.4), Vector2(px + s * 0.6, py), Vector2(px, py + s), Vector2(px - s * 0.6, py)]),
			flame(0.15 + 0.6 * LowpolyBox.hash01(i, 35), (1.0 - u) * 0.95 * a))


func _centered(text: String, base: Vector2, fs: int, col: Color, a: float) -> void:
	var w := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2(base.x - w * 0.5, base.y)
	draw_string_outline(FONT, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(6, fs / 6), Color(NIGHT, 0.95 * a))
	draw_string(FONT, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## 고리: n각 선(SSR이면 꼭짓점마다 무지개 색).
func _ring(c: Vector2, r: float, n: int, w: float, rot: float, a: float) -> void:
	if w <= 0.1 or a <= 0.0:
		return
	var pts := _ngon(c, r, n, rot)
	pts.append(pts[0])
	var cols := PackedColorArray()
	for i in pts.size():
		cols.append(Color(_light(i % n, n), a))
	draw_polyline_colors(pts, cols, w, true)


static func _ngon(c: Vector2, r: float, n: int, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		pts.append(c + Vector2.from_angle(rot + TAU * i / n) * r)
	return pts

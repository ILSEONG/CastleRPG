extends Control
## 영웅 모집 소환 연출(2026-10-15, 사용자 "영웅뽑기 좀 더 화려하게 연출해줘"): 모집 창 위 화면 전체를 덮는 막(recruit_panel이 맨 위 자식으로 둔다).
## 참고한 게임: 원신(기원 — 떨어지는 별빛 색이 최고 등급을 미리 알린다), 블루 아카이브(모집 쪽지 색이 마지막 순간 한 단계 바뀐다),
## 클래시 로얄(가장 높은 등급은 무지개빛), AFK 아레나(10회 결과를 한 화면에서 빠르게 차례로 뒤집고 언제든 건너뛴다).
## 1) 소환(play, 2026-11-03 사용자 "마법진이 너무 유치해 … 다른 게임 참고해서 마법진 아니어도 좋으니까 바꿔줘" — 마법진을 뺐다):
##    어두운 밤에 별빛 터널(붕괴: 스타레일 워프)이 스치고, 유성(원신 기원)이 오른쪽 위에서 떨어져 가운데에 닿으면 가로 섬광과 함께
##    세로 빛의 틈이 열린다(명일방주 헤드헌팅의 빛줄기). 유성 꼬리·틈의 빛이 등급을 미리 알린다. 빛은 파랑(R)에서 시작해 이번 모집 최고 등급이
##    SR이면 SR_AT에 보라로, SSR이면 SSR_AT에 무지개빛으로 바뀐다(번쩍 + 흔들림 + 빛기둥). 끝에 터지며 걷히고 intro_done — 창의 카드가
##    차례로 뒤집히기 시작한다. 화면을 누르면 바로 터지며 걷힌다(그 모집의 최고 등급 빛으로). [건너뛰기]는 skip_all(카드를 모두 바로 열고 SSR 화면도 건너뛴다).
## 2) SSR 화면(splash): SSR 카드가 펴지면 도는 무지개 빛살 위 큰 기울어진 창에 영웅 일러스트 + "SSR" + 이름·칭호(새 영웅이면 NEW).
##    누르면 닫힌다(SPLASH_SEC 뒤 저절로). 여러 장이면 차례로.
## 3) UR(2026-10-29, 사용자 "UR은 개멋지게 뽑아줘", "SSR을 그대로 가져오면 어떡하냐"; 2026-10-30 "SSR은 왜 스킵하고 바로 블랙홀…
##    블랙홀 멋없어"): 파랑 → 보라 → 무지개(SSR)까지 똑같이 오른 뒤 UR_AT에 한 단계 더 — 무지개 핵이 깨져 조각이 튀고(UR_CRACK),
##    가운데에 하얗게 타는 불꽃 해(흰 → 살구 → 주황 → 진홍 겹 + 길게 일렁이는 불꽃 혀 + 도는 불꽃 고리)가 솟는다.
##    빛이 진홍·주황 불꽃빛으로 바뀌며 충격파 고리 + 화면을 꿰는 큰 불기둥 + 바깥 셋째 불꽃 고리 + 화면 가득 오르는 불씨, 소환진도 UR_HOLD만큼 길다.
##    참고: 페이트 그랜드 오더·승리의 여신 니케(무지개에서 한 번 더 바뀌는 '확정 승급' 연출), 원신(마지막 순간 별똥별 색 승급).
##    UR 화면은 SSR보다 크다: 대각선 섬광이 창을 가르며 열리고, 불꽃빛 테두리에 "UR"은 크게(진홍 두께). 일러스트 위에는 아무것도
##    그리지 않는다(2026-10-30 사용자 "일러스트 위에 불꽃효과 너무 좆밥같아") — 불씨는 창 뒤로, 섬광은 창이 열리면 사라진다.
##    참고: 원신(최고 등급 별똥별 색), 세븐나이츠 키우기(최고 등급 소환 섬광·불꽃) — 화면 모습 기준.
## 금색은 쓰지 않는다(SSR = 무지개빛, UR = 주황 불꽃빛 — 사용자 2026-10-14 "금색되는거 촌스러워"). 그리는 것은 다각형 몇백 개뿐, 보일 때만 돈다(발열).

const Lang := preload("res://scripts/lang.gd")

const UiKit := preload("res://scripts/ui_kit.gd")
const SummonFx := preload("res://scripts/summon_fx.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const HeroArt := preload("res://scripts/hero_art.gd")
const Portraits := preload("res://scripts/portraits.gd")
const GameData := preload("res://scripts/game_data.gd")
const Sfx := preload("res://scripts/sfx.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const INTRO_ONE := 1.3  # 1회 소환진 길이(초). 2026-11-03 사용자 "카드 뽑기 딜레이가 많이 심한거같아": 1.9 → 1.3
const INTRO_TEN := 1.5  # 10회(2.2 → 1.5)
const SR_AT := 0.6  # 소환진 시간 비율: 빛이 보라로
const SSR_AT := 0.8  # 무지개로
const UR_AT := 1.05  # UR: 무지개가 이만큼(소환진 시간 비율) 보인 뒤 불꽃 해로
const UR_HOLD := 1.0  # UR: 소환진이 이만큼 더 돈다(불꽃 해가 보일 시간)
const UR_CRACK := 0.3  # UR: 무지개 핵이 깨져 조각이 튀는 시간
const BURST := 0.24  # 끝: 터지며 걷힘
const FADE_IN := 0.15
const SPLASH_IN := 0.3
const SPLASH_SEC := 1.8  # 2.4 → 1.8(2026-11-03, 누르면 더 일찍 걷힌다)
const SPLASH_OUT := 0.22
const SPLASH_MIN := 0.45  # SSR 화면이 뜬 뒤 이보다 이른 누름은 무시(연타가 바로 닫지 않게)
const UR_SLASH := 0.16  # UR 화면: 섬광이 화면을 가르는 시간
const UR_IN := 0.5  # UR 화면: 섬광 + 창이 열리는 시간
const UR_SPLASH_SEC := 3.0
const UR_WAVE := 0.6  # UR 충격파 고리
const NIGHT := Color("120F26")
const BLUE := Color("7DB4FF")  # R 빛(R 등급 회청색을 밝게)
const PURPLE := Color("B48CFF")  # SR 빛
const ORANGE := Color("FF6A1F")  # UR 빛(= UR 등급 색)
## UR 불꽃빛: 진홍 → 주황 → 살구 → 흰빛을 돈다(노란 금빛은 피한다).
const FLAME := [Color("E8344A"), Color("FF6A1F"), Color("FF9A5C"), Color("FFE2D0")]
const EMBERS := 34
const RAYS := 16
const MOTES := 26
const STARS := 80  # 밤하늘 별
const SHARDS := 10  # 빛의 틈 둘레를 도는 결정 조각
const FALL_AT := 0.4  # 소환 시간 비율: 유성이 가운데에 닿는다(그 뒤 빛의 틈이 열린다)

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
var _base := INTRO_TEN  # UR 연장 전 소환진 길이(빛이 바뀌는 비율의 기준)
var _rank := 0  # 지금 빛 0 R · 1 SR · 2 SSR · 3 UR
var _ur_at := 0.0  # UR 불꽃 해가 솟은 시각(_t)
var _flash := 0.0
var _shake := 0.0
var _queue: Array = []  # 기다리는 SSR·UR 화면 [{hero, new, grade}]
var _splash := {}
var fx  # 빛·입자·카메라(summon_fx.gd)
var _flash_rect: ColorRect  # 흰 번쩍임(빛 위)
var _pending := false  # play(pending): 결과 등급을 기다리는 중
var _skip_wanted := false  # 기다리는 동안 [건너뛰기]를 눌렀다


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
	fx = SummonFx.new()
	fx.stage = self
	fx.visible = false
	add_child(fx)
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.color = Color(1, 1, 1, 0)
	add_child(_flash_rect)
	add_child(skip_button)  # 빛 위에


## 소환진을 처음부터. grade = 이번 모집 최고 등급, count = 장수(1 또는 10).
## pending이면 등급을 아직 모른다(버튼을 누르자마자 서버 응답을 기다리며 돌린다 — 2026-11-03 딜레이 줄이기): resolve(grade)가 올 때까지
## 등급 빛이 오르기 직전(SR_AT)에서 더 나아가지 않고, 누름·[건너뛰기]도 결과가 올 때까지 기다린다.
func play(grade: String, count: int, pending := false) -> void:
	best = grade
	_pending = pending
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
	fx.vs = size if size != Vector2.ZERO else get_viewport_rect().size
	fx.reset()
	skip_button.visible = true
	Sfx.play("sk_summon")
	queue_redraw()


## pending으로 시작한 소환진에 결과 최고 등급을 알려 준다(그 뒤로는 play(grade)와 같다).
func resolve(grade: String) -> void:
	best = grade
	_len = _base + (UR_HOLD if grade == "UR" else 0.0)
	_pending = false
	if _skip_wanted:  # 기다리는 동안 누른 [건너뛰기]
		_skip_wanted = false
		_on_skip()


func is_pending() -> bool:
	return mode == Mode.INTRO and _pending


## SSR·UR 화면을 줄 세운다(소환진 중이면 걷힌 뒤에). grade가 ""이면 영웅 표의 등급.
func splash(hero_id: String, is_new: bool, grade := "") -> void:
	if grade == "":
		grade = str(GameData.hero(hero_id).get("grade", "SSR"))
	_queue.append({"hero": hero_id, "new": is_new, "grade": grade})
	if grade == "UR":
		Portraits.portrait("big:" + hero_id)  # 연출 창에 크게 그릴 피규어 — 소환진이 도는 동안 미리 찍어 둔다
	if mode == Mode.IDLE:
		_next_splash()


## 다 멈추고 숨긴다(창을 닫을 때·새 결과).
func stop() -> void:
	_pending = false
	_skip_wanted = false
	fx.stop()
	_flash_rect.color.a = 0.0
	mode = Mode.IDLE
	_queue.clear()
	_splash = {}
	splash_hero = ""
	visible = false


func is_busy() -> bool:
	return mode != Mode.IDLE


func _on_skip() -> void:
	if _pending:
		_skip_wanted = true  # 결과가 오면 건너뛴다
		return
	stop()
	skip_all.emit()


func _gui_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if not pressed:
		return
	accept_event()
	if mode == Mode.INTRO and _pending:
		pass  # 결과를 기다리는 중
	elif mode == Mode.INTRO and _t < _len:
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
		if _pending:
			_t = minf(_t, _base * SR_AT - 0.01)  # 결과가 올 때까지 등급 빛 직전에서 돈다
		var k := _t / _base
		if _rank < 1 and _goal() >= 1 and k >= SR_AT:
			_upgrade(1)
		if _rank < 2 and _goal() >= 2 and k >= SSR_AT:
			_upgrade(2)  # UR도 무지개까지는 SSR과 같이 오른다
		if _rank < 3 and _goal() >= 3 and k >= UR_AT:
			_upgrade(3)  # 한 단계 더: 무지개가 깨지고 불꽃 해
		var out := clampf((_t - _len) / BURST, 0.0, 1.0)
		fx.tick(delta, _t, _base, _len, _base * FALL_AT, out, _rank, _light_at, _shake)
		_flash_rect.color.a = maxf(0.6 * _flash, 0.55 * sin(PI * out))
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
	fx.burst(1.3 + 0.5 * r)
	_flash = 0.55 if r == 1 else 1.0
	_shake = [0.0, 0.6, 1.0, 1.8][r]
	if r == 3:  # 불꽃 해: 쿵 + 불길
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
	fx.stop()
	_flash_rect.color.a = 0.0
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


## 지금 등급 빛, x(0..1) 자리(무지개·불꽃은 x와 시간에 따라 돈다).
func _light_at(x: float) -> Color:
	if _rank == 3:
		return ember(x + _t * 0.5)
	if _rank == 2:
		return prism(x + _t * 0.35)
	return PURPLE if _rank == 1 else BLUE


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
	var out := clampf((_t - _len) / BURST, 0.0, 1.0)  # 걷힘
	var fade := 1.0 - out
	# 밤하늘(위는 깊은 남색, 아래는 등급 빛이 살짝 번진다)
	var low := NIGHT.lerp(_light_at(0.0), 0.18 + 0.12 * _rank)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(vs.x, 0), vs, Vector2(0, vs.y)]),
		PackedColorArray([Color(NIGHT.darkened(0.4), 0.96 * a * fade), Color(NIGHT.darkened(0.4), 0.96 * a * fade), Color(low, 0.96 * a * fade), Color(low, 0.96 * a * fade)]))
	# 반짝이는 별(카메라와 따로 — 먼 하늘)
	for i in STARS:
		var p := Vector2(LowpolyBox.hash01(i, 61) * vs.x, LowpolyBox.hash01(i, 62) * vs.y * 0.8)
		var tw := 0.35 + 0.65 * absf(sin(_t * (1.5 + 2.0 * LowpolyBox.hash01(i, 63)) + i))
		draw_circle(p, 0.8 + 1.4 * LowpolyBox.hash01(i, 64), Color(1, 1, 1, tw * 0.8 * a * fade))
	if _rank == 3:
		var since := _t - _ur_at
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.5, 0.1, 0.02, 0.25 * clampf(since * 4.0, 0.0, 1.0) * fade))


## 세로(또는 가로) 렌즈 모양(빛의 틈): 가운데 c, 반너비 w, 반높이 h.
static func _lens(c: Vector2, w: float, h: float, horizontal := false) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 16:
		var ang := TAU * i / 16.0
		var v := Vector2(cos(ang) * w, sin(ang) * h)
		v.x *= absf(cos(ang)) ** 0.6 if not horizontal else 1.0  # 끝이 뾰족하게
		v.y *= 1.0 if not horizontal else absf(sin(ang)) ** 0.6
		pts.append(c + v)
	return pts


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
	if not HeroArt.draw_in(self, _splash.hero, win, wr, 0.3):  # 그림은 제자리(천천히 당겨지지 않는다 — 2026-11-05 사용자 "배너가 조금씩 움직이는거 하지마")
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
## 창 테두리는 불꽃빛으로 일렁이고, 불씨는 창 뒤에서 오른다(일러스트를 가리지 않게). "UR"은 크게, 뒤에 진홍 두께.
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
	_draw_embers(vs, a * open)  # 창 뒤 — 창 밖 빛살 위로만 보인다
	if open > 0.0:
		draw_colored_polygon(frame, Color(NIGHT.lightened(0.1), a))
		if not HeroArt.draw_in(self, _splash.hero, win, wr, 0.3):  # 그림은 제자리. 일러스트 전: 주황 창에 3D 전신 피규어
			draw_colored_polygon(win, Color(ORANGE.darkened(0.45), a))
			var fs := wr.size.y * 1.05
			draw_texture_rect(Portraits.portrait("big:" + str(_splash.hero)), Rect2(wr.get_center() - Vector2(fs, fs) * 0.5, Vector2(fs, fs)), false,
				Color(1, 1, 1, a * clampf((open - 0.6) * 2.5, 0.0, 1.0)))
		if a < 1.0:
			draw_colored_polygon(win, Color(NIGHT, 1.0 - a))
		# 불꽃 테두리: 넓고 옅은 바깥 + 꼭짓점마다 다른 불꽃빛 + 흰 속선
		var edge := frame.duplicate()
		edge.append(frame[0])
		draw_polyline(edge, Color(ORANGE, 0.3 * a), 20.0, true)
		var cols := PackedColorArray()
		for i in edge.size():
			cols.append(flame(float(i % 4) / 4.0 + t * 0.5, a))
		draw_polyline_colors(edge, cols, 8.0, true)
		draw_polyline(edge, Color(1, 0.95, 0.9, 0.7 * a), 2.0, true)
	# 섬광: 창의 대각선을 따라 화면을 가르고(UR_SLASH), 창이 다 열리면 사라진다(그림 위에 선이 남지 않게)
	var d := (full[1] - full[3]).normalized()
	var s0 := full[3] - d * reach * 0.3
	var s1 := s0 + d * reach * 1.1 * slash
	var sa := (1.0 - open) * a
	draw_line(s0, s1, Color(ORANGE, 0.5 * sa), 34.0 * (1.0 - open) + 4.0, true)
	draw_line(s0, s1, Color(1, 0.96, 0.92, sa), 10.0 * (1.0 - open) + 2.0, true)
	if t < UR_IN + 0.15:  # 열리는 순간 번쩍
		draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 0.62, 0.4, 0.3 * sin(PI * clampf((t - UR_SLASH) / (UR_IN + 0.15 - UR_SLASH), 0.0, 1.0)) * a))
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


## UR 불꽃 해: 처음 UR_CRACK 동안 무지개 핵 조각이 사방으로 튀고, 하얗게 타는 핵 둘레로 두 겹 불꽃 혀가 엇갈려 돈다.
func _draw_sun(c: Vector2, rr: float, a: float, since: float) -> void:
	var ck := since / UR_CRACK
	if ck < 1.0:  # 깨지는 무지개 핵
		for i in 10:
			var ang := TAU * i / 10.0 + LowpolyBox.hash01(i, 51) * 0.5
			var d := Vector2.from_angle(ang)
			var p := c + d * rr * (0.3 + 3.2 * ease(ck, 0.4))
			var s := rr * (0.35 + 0.25 * LowpolyBox.hash01(i, 52)) * (1.0 - ck * 0.6)
			draw_colored_polygon(PackedVector2Array([p + d * s, p + d.orthogonal() * s * 0.4, p - d * s * 0.5]), prism(i / 10.0 + _t, (1.0 - ck) * a))
	var grow := ease(clampf(since / UR_CRACK, 0.0, 1.0), 0.3)
	rr *= 0.4 + 0.6 * grow
	draw_colored_polygon(_ngon(c, rr * 3.0, 20, _t * 0.3), Color(ORANGE, 0.16 * a))
	draw_colored_polygon(_ngon(c, rr * 2.1, 20, -_t * 0.4), Color(FLAME[0], 0.22 * a))
	for layer in 2:  # 바깥 긴 진홍 혀 · 안쪽 짧은 살구 혀(서로 반대로 돈다)
		var n := 18 if layer == 0 else 14
		var dir := 1.0 if layer == 0 else -1.3
		for i in n:
			var ang := TAU * i / n + _t * 0.7 * dir
			var fl := 0.7 + 0.3 * sin(_t * 10.0 + i * 1.9 + layer) + 0.4 * LowpolyBox.hash01(i, 21 + layer)
			var hw := TAU / n * 0.5
			var reach := rr * ((1.5 + 0.9 * fl) if layer == 0 else (1.2 + 0.4 * fl))
			var tip := c + Vector2.from_angle(ang + 0.25 * dir) * reach  # 끝이 휘어 불길처럼
			draw_colored_polygon(PackedVector2Array([c + Vector2.from_angle(ang - hw) * rr * 0.9, tip, c + Vector2.from_angle(ang + hw) * rr * 0.9]),
				flame((0.05 if layer == 0 else 0.45) + 0.25 * float(i) / n + _t * 0.3, (0.85 if layer == 0 else 0.95) * a))
	draw_colored_polygon(_ngon(c, rr * 1.05, 20, _t), Color(FLAME[1], a))
	draw_colored_polygon(_ngon(c, rr * 0.82, 16, -_t), Color(FLAME[2], a))
	draw_colored_polygon(_ngon(c, rr * 0.58, 12, _t * 2.0), Color(FLAME[3], a))
	draw_colored_polygon(_ngon(c, rr * 0.34, 8, 0.0), Color(1, 1, 1, a * (0.85 + 0.15 * sin(_t * 17.0))))


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
